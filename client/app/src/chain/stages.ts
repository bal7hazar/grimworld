import type { PlayAction } from "../preview/actions";
import { type MirrorState, mirrorOf } from "../preview/mirror";
import { type Preview, previewBatch } from "../preview/preview";
import {
  type MirrorResult,
  type ParityLog,
  type Predict,
  consoleParityLog,
  predict as mirrorPredict,
} from "../preview/reconcile";
import type { Simulator } from "../preview/rpc";
import { Stop } from "../preview/trace";
import { type Batch, actionsOf, add, afterPreview, afterSend, isFull, isStale } from "./batch";
import type { ChainState, Sent, SendInput } from "./send";

/**
 * The chain mode's batch and its three stages, as a model (CLI-11 §4.3, §5): no drawing, the
 * panel and the map read `get()` and redraw on `subscribe`.
 *
 * 1. The mirror, at once: client/sim's segment on the whole batch, at every input.
 * 2. The simulation: `previewBatch` 300 ms after the last input, and at once on send. Each batch
 *    takes a request number, and only the answer to the latest is kept: an older one is discarded.
 * 3. The sent batch: `send` (`sendBatch`), with the same two calls, then the chain's result beside
 *    the simulation's. The state the next batch runs on is the one that execution left.
 *
 * Sending (`B`) waits for the simulation of the exact batch shown. One batch is in flight at a
 * time, and no input is taken from `B` until it settles; a full batch takes none until it is sent.
 * Where a preview or a sent batch ends it is `batch.ts`'s: a refused action drops the rest; a stale
 * sequence or content version reads the state again and previews the same actions on it; a defeat
 * or a closing ends the instance.
 */

export type Simulation = { readonly request: number; readonly actions: readonly PlayAction[] } & (
  | { status: "pending" }
  | { status: "answered"; preview: Preview }
  | { status: "error"; error: string }
);

export type Phase =
  /** Takes input, and `B`. */
  | "ready"
  /** `B` was pressed: waiting for the simulation, then the execution. No input. */
  | "sending"
  /** The state is being read again (a stale batch, an execution that did not settle). No input. */
  | "reading"
  /** The instance closed: nothing plays until a new state is installed (entering again, §3.4). */
  | "closed";

export interface StagesState {
  readonly phase: Phase;
  /** What the batch runs on: the chain's last state. */
  readonly chain: ChainState;
  readonly planned: Batch;
  /** Stage 1; none for an empty batch. */
  readonly mirror: MirrorResult | undefined;
  /** Stage 2, of the batch planned; none for an empty batch. */
  readonly simulation: Simulation | undefined;
  /** Stage 3: the last batch sent, and the simulation it was sent on. */
  readonly sent: { readonly simulated: Preview; readonly result: Sent } | undefined;
  /** One line for the panel (a refusal, "no funds", "the instance closed"). */
  readonly line: string | undefined;
}

export interface StagesDeps {
  readonly simulator: Simulator;
  /** Stage 3: `sendBatch` with its dependencies bound (the provider and `assertChain` among them). */
  readonly send: (input: SendInput) => Promise<Sent>;
  /** A fresh read of the state (`readState` at `pre_confirmed`). */
  readonly load: () => Promise<ChainState>;
  /** The mirror of a state; `mirrorOf` by default. */
  readonly mirror?: (state: MirrorState) => Predict;
  readonly log?: ParityLog;
  /** Stage 2's delay after the last input, in milliseconds (300 by default). */
  readonly debounce?: number;
}

export interface Stages {
  get(): StagesState;
  subscribe(listener: (state: StagesState) => void): () => void;
  /**
   * Adds actions to the batch (`path` for the steps of a tapped path, §4.1), cut to its room.
   * False when nothing was taken: not ready, or the batch full.
   */
  input(actions: readonly PlayAction[], options?: { path?: boolean }): boolean;
  /** `B`: sends the batch once its simulation answered. False when there is nothing to send. */
  send(): boolean;
  /** A new chain state, the batch emptied (entering again after a closing, §3.4). */
  install(chain: ChainState): void;
}

export const lines = {
  CLOSED: "the instance closed",
  FULL: "the batch is full: send it",
  STALE: "the state moved: read again, preview again",
  SIMULATION_FAILED: "the simulation failed",
  NOT_SENT: "the batch was not sent",
} as const;

const quiet: ParityLog = () => undefined;

export function createStages(initial: ChainState, deps: StagesDeps): Stages {
  const log = deps.log ?? consoleParityLog;
  const mirrorFor = deps.mirror ?? mirrorOf;
  const debounce = deps.debounce ?? 300;
  const listeners = new Set<(state: StagesState) => void>();
  let state: StagesState = {
    phase: "ready",
    chain: initial,
    planned: [],
    mirror: undefined,
    simulation: undefined,
    sent: undefined,
    line: undefined,
  };
  let predict = mirrorFor(initial.mirror);
  let request = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  /** The request whose simulation runs now, if any. */
  let running: number | undefined;

  function set(next: Partial<StagesState>) {
    state = { ...state, ...next };
    for (const listener of listeners) listener(state);
  }

  /** The stop the preview shows for the batch planned: the simulation's, else the mirror's. */
  function stopShown(): Stop | undefined {
    const { simulation, mirror } = state;
    if (simulation?.status === "answered" && simulation.request === request) {
      const { preview } = simulation;
      if (preview.kind === "simulated" && preview.chain.kind === "played") {
        return preview.chain.batch.stop;
      }
    }
    return mirror?.kind === "predicted" ? mirror.stop : undefined;
  }

  /** The batch changed: stage 1 at once, stage 2 after the delay, a new request number. */
  function plan(planned: Batch, extra: Partial<StagesState> = {}) {
    clearTimeout(timer);
    timer = undefined;
    request++;
    if (planned.length === 0) {
      set({ planned, mirror: undefined, simulation: undefined, ...extra });
      return;
    }
    const actions = actionsOf(planned);
    const mirror = mirrorPredict(actions, predict, quiet);
    set({ planned, mirror, simulation: { request, actions, status: "pending" }, ...extra });
    const mine = request;
    timer = setTimeout(() => void simulate(mine), debounce);
  }

  function installChain(chain: ChainState) {
    predict = mirrorFor(chain.mirror);
    state = { ...state, chain };
  }

  /** Reads the state again and previews the batch on it (a stale sequence or version). */
  async function reread(planned: Batch, line: string | undefined) {
    clearTimeout(timer);
    timer = undefined;
    request++;
    set({ phase: "reading", line });
    try {
      installChain(await deps.load());
      plan(planned, { phase: "ready" });
    } catch (error) {
      // The read failed: the batch stays on the old state, the next `B` tries again
      plan(planned, { phase: "ready", line: `${lines.STALE}: ${(error as Error).message}` });
    }
  }

  async function simulate(mine: number) {
    if (mine !== request || running === mine) return;
    clearTimeout(timer);
    timer = undefined;
    running = mine;
    const actions = actionsOf(state.planned);
    let answered: Simulation;
    try {
      const preview = await previewBatch(
        { ...state.chain.target, actions },
        { simulator: deps.simulator, predict, log },
      );
      answered = { request: mine, actions, status: "answered", preview };
    } catch (error) {
      answered = { request: mine, actions, status: "error", error: (error as Error).message };
    } finally {
      if (running === mine) running = undefined;
    }
    // A batch changed since: its own request answers it
    if (mine !== request) return;
    set({ simulation: answered });
    if (answered.status === "error") {
      if (state.phase === "sending") set({ phase: "ready", line: lines.SIMULATION_FAILED });
      return;
    }
    const { preview } = answered;
    if (preview.kind === "refused") {
      if (state.phase === "sending") set({ phase: "ready", line: preview.reason });
      return;
    }
    if (preview.chain.kind === "played") {
      const { batch } = preview.chain;
      if (isStale(batch.stop)) {
        // Nothing ran: the same actions, previewed again on the state read again; `B` again
        await reread(state.planned, lines.STALE);
        return;
      }
      if (batch.stop === Stop.Closed) {
        clearTimeout(timer);
        set({ phase: "closed", planned: [], mirror: undefined, line: lines.CLOSED });
        return;
      }
      const kept = afterPreview(state.planned, batch);
      if (kept.length !== state.planned.length) {
        // The refused action and the rest dropped: a new batch, previewed again; `B` again
        plan(kept, { phase: "ready" });
        return;
      }
    }
    if (state.phase === "sending") await execute(preview);
  }

  async function execute(simulated: Preview & { kind: "simulated" }) {
    const planned = state.planned;
    let result: Sent;
    try {
      result = await deps.send({
        state: state.chain,
        actions: actionsOf(planned),
        predict,
        simulated: simulated.chain,
      });
    } catch (error) {
      // Past the send (a trace or a read that failed): play resumes from a fresh read
      set({ sent: undefined });
      await reread(planned, `${lines.NOT_SENT}: ${(error as Error).message}`);
      return;
    }
    set({ sent: { simulated, result } });
    if (result.kind === "refused") {
      set({ phase: "ready", line: result.reason });
      return;
    }
    if (result.kind === "unsettled") {
      // Nothing it did holds, or it is unknown: the actions stay, the state is read again
      await reread(planned, `${lines.NOT_SENT}: ${result.status}`);
      return;
    }
    if (result.chain.kind !== "played") {
      await reread(planned, `${lines.NOT_SENT}: ${result.chain.reason}`);
      return;
    }
    const { batch, defeated, closed } = result.chain;
    const ending = afterSend(planned, { played: batch.played, stop: batch.stop, defeated, closed });
    if (ending.kind === "reread") {
      await reread(ending.planned, lines.STALE);
      return;
    }
    installChain(result.after);
    if (ending.kind === "closed") {
      clearTimeout(timer);
      request++;
      set({
        phase: "closed",
        planned: [],
        mirror: undefined,
        simulation: undefined,
        line: lines.CLOSED,
      });
      return;
    }
    plan(ending.planned, { phase: "ready", line: undefined });
  }

  return {
    get: () => state,

    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },

    input(actions, options = {}) {
      if (state.phase !== "ready" || actions.length === 0) return false;
      if (isFull(state.planned, stopShown())) {
        set({ line: lines.FULL });
        return false;
      }
      plan(add(state.planned, actions, { path: options.path }), { line: undefined });
      return true;
    },

    send() {
      if (state.phase !== "ready" || state.planned.length === 0) return false;
      set({ phase: "sending", line: undefined });
      const { simulation } = state;
      if (simulation?.request === request && simulation.status === "answered") {
        const { preview } = simulation;
        if (preview.kind === "refused") {
          set({ phase: "ready", line: preview.reason });
          return false;
        }
        void execute(preview);
      } else {
        // At once on `B`; one already running is awaited, its answer sends
        void simulate(request);
      }
      return true;
    },

    install(chain) {
      clearTimeout(timer);
      timer = undefined;
      request++;
      installChain(chain);
      set({
        phase: "ready",
        planned: [],
        mirror: undefined,
        simulation: undefined,
        sent: undefined,
        line: undefined,
      });
    },
  };
}
