import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Call, ExecutionId } from "../account/types";
import type { PlayAction } from "../preview/actions";
import { INSTANCES, INSTANCE_ID, type Played, playedTrace, view } from "../preview/fixtures";
import type { Prediction } from "../preview/reconcile";
import type { Simulator } from "../preview/rpc";
import { type InvokeTrace, Stop, extractOutcome } from "../preview/trace";
import { type ChainState, type Sent, type SendInput, sendBatch } from "./send";
import { type StagesDeps, createStages, lines } from "./stages";

const WAIT: PlayAction = { kind: "wait" };
const move = (direction: number): PlayAction => ({ kind: "move", direction });
const ID = "0x7a5" as ExecutionId;

/** A state at `sequence` (the fixtures' view: one member, two goblins). */
const chainAt = (sequence: number, clock = 12): ChainState => ({
  target: { instances: INSTANCES, instanceId: INSTANCE_ID, adventurerId: 41, sequence, version: 1 },
  mirror: { view: view(clock, sequence), member: 0, region: [] },
});

/** A mirror that plays every action and stops on nothing, unless told otherwise. */
const prediction = (played: number, done: Partial<Prediction["done"]> = {}): Prediction => ({
  words: { clock: 12 + played, members: [], goblins: [], killed: [], defeated: false },
  done: { played, reveal: false, illegal: undefined, heavy: false, undo: false, ...done },
});

/** A simulator whose answers the test gives, one call at a time. */
function simulator() {
  const pending: { calls: readonly Call[]; answer: (trace: InvokeTrace) => void }[] = [];
  const fake: Simulator = {
    simulate: (calls) => new Promise((answer) => pending.push({ calls, answer })),
  };
  /** Answers the `i`-th call still waiting with a batch that ran `batch`. */
  const answer = async (batch: Played, i = 0) => {
    const [call] = pending.splice(i, 1);
    if (call === undefined) throw new Error("no simulation waiting");
    call.answer(playedTrace(batch));
    await vi.advanceTimersByTimeAsync(0);
  };
  return { fake, pending, answer };
}

/** The `sent` of a batch that ran `batch`, the state after at `batch.sequence`. */
function sentOf(batch: Played): Sent {
  const chain = extractOutcome(playedTrace(batch));
  return {
    kind: "sent",
    id: ID,
    blockHash: "0xb10c",
    differs: [],
    after: chainAt(batch.sequence, batch.clock),
    chain,
    mirror: { kind: "not-mirrored", reason: "no mirror wired" },
    mismatches: [],
  };
}

function stages(over: Partial<StagesDeps> = {}) {
  const sim = simulator();
  const sends: SendInput[] = [];
  const results: Sent[] = [];
  const loads: ChainState[] = [];
  const deps: StagesDeps = {
    simulator: sim.fake,
    send: vi.fn(async (input: SendInput) => {
      sends.push(input);
      const result = results.shift();
      if (result === undefined) throw new Error("no send expected");
      return result;
    }),
    load: vi.fn(async () => {
      const state = loads.shift();
      if (state === undefined) throw new Error("no read expected");
      return state;
    }),
    mirror: () => (actions) => prediction(actions.length),
    log: () => undefined,
    ...over,
  };
  return { model: createStages(chainAt(3), deps), sim, sends, results, loads, deps };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("fetch", () => {
    throw new Error("the network was touched");
  });
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("the three stages", () => {
  it("shows the mirror at once and simulates 300 ms after the last input", async () => {
    const { model, sim } = stages();
    expect(model.input([WAIT])).toBe(true);
    expect(model.get().mirror).toMatchObject({ kind: "predicted", played: 1, stop: Stop.None });
    expect(model.get().simulation).toMatchObject({ status: "pending", actions: [WAIT] });
    await vi.advanceTimersByTimeAsync(200);
    expect(model.input([move(0)])).toBe(true);
    await vi.advanceTimersByTimeAsync(299);
    expect(sim.pending).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(1);
    // One simulation, of the whole batch
    expect(sim.pending).toHaveLength(1);
    await sim.answer({ played: 2, stop: Stop.None, sequence: 5, clock: 14 });
    expect(model.get().simulation).toMatchObject({
      status: "answered",
      actions: [WAIT, move(0)],
      preview: { kind: "simulated", chain: { batch: { played: 2, stop: Stop.None } } },
    });
  });

  it("discards a stale simulation: only the latest batch's answer is shown", async () => {
    const { model, sim } = stages();
    model.input([WAIT]);
    await vi.advanceTimersByTimeAsync(300);
    model.input([move(1)]);
    await vi.advanceTimersByTimeAsync(300);
    expect(sim.pending).toHaveLength(2);
    // The older answer arrives first: discarded, the newer request still pending
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 }, 0);
    expect(model.get().simulation).toMatchObject({ status: "pending", actions: [WAIT, move(1)] });
    await sim.answer({ played: 2, stop: Stop.None, sequence: 5, clock: 14 }, 0);
    expect(model.get().simulation).toMatchObject({
      status: "answered",
      preview: { chain: { batch: { played: 2 } } },
    });
  });

  it("discards an older answer arriving after the newer one", async () => {
    const { model, sim } = stages();
    model.input([WAIT]);
    await vi.advanceTimersByTimeAsync(300);
    model.input([WAIT]);
    await vi.advanceTimersByTimeAsync(300);
    await sim.answer({ played: 2, stop: Stop.None, sequence: 5, clock: 14 }, 1);
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 }, 0);
    expect(model.get().simulation).toMatchObject({ preview: { chain: { batch: { played: 2 } } } });
  });

  it("makes B wait for the simulation of the exact batch shown, then sends it", async () => {
    const { model, sim, sends, results, deps } = stages();
    results.push(sentOf({ played: 1, stop: Stop.None, sequence: 4, clock: 13 }));
    model.input([WAIT]);
    expect(model.send()).toBe(true);
    // At once on B, without the 300 ms; nothing sent before it answers
    await vi.advanceTimersByTimeAsync(0);
    expect(sim.pending).toHaveLength(1);
    expect(deps.send).not.toHaveBeenCalled();
    expect(model.get().phase).toBe("sending");
    // No input while the batch is in flight
    expect(model.input([WAIT])).toBe(false);
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    expect(sends).toHaveLength(1);
    expect(sends[0]).toMatchObject({
      actions: [WAIT],
      state: { target: { sequence: 3 } },
      simulated: { kind: "played", batch: { played: 1 } },
    });
    // The predict sent with is the preview's own
    expect(sends[0]!.predict).toBeTypeOf("function");
    // Stage 3 beside stage 2; the next batch runs on the state after
    expect(model.get()).toMatchObject({
      phase: "ready",
      planned: [],
      sent: {
        simulated: { kind: "simulated", chain: { batch: { played: 1 } } },
        result: { kind: "sent", chain: { batch: { played: 1 } } },
      },
      chain: { target: { sequence: 4 } },
    });
  });

  it("sends at once on B when the shown batch's simulation has answered", async () => {
    const { model, sim, results, deps } = stages();
    results.push(sentOf({ played: 1, stop: Stop.None, sequence: 4, clock: 13 }));
    model.input([WAIT]);
    await vi.advanceTimersByTimeAsync(300);
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    expect(deps.send).not.toHaveBeenCalled();
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    expect(deps.send).toHaveBeenCalledTimes(1);
    expect(sim.pending).toHaveLength(0);
  });

  it("does nothing on B with an empty batch", () => {
    const { model } = stages();
    expect(model.send()).toBe(false);
    expect(model.get().phase).toBe("ready");
  });
});

describe("where the batch ends", () => {
  it("takes 10 actions, and an 11th waits until the batch is sent", async () => {
    const { model } = stages();
    for (let i = 0; i < 10; i++) expect(model.input([WAIT])).toBe(true);
    expect(model.input([WAIT])).toBe(false);
    expect(model.get().planned).toHaveLength(10);
    expect(model.get().line).toBe(lines.FULL);
  });

  it("keeps the action unplayed for the weight: full until sent, then it opens the next batch", async () => {
    // The mirror counts the weight as the contract does: the third action does not fit
    const { model, sim, results } = stages({
      mirror: () => (actions) =>
        actions.length > 2 ? prediction(2, { heavy: true }) : prediction(actions.length),
    });
    model.input([WAIT, WAIT]);
    model.input([{ kind: "turn", direction: 2 }]);
    expect(model.get().mirror).toMatchObject({ played: 2, stop: Stop.Weight });
    expect(model.input([WAIT])).toBe(false);
    results.push(sentOf({ played: 2, stop: Stop.Weight, sequence: 5, clock: 14 }));
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 2, stop: Stop.Weight, sequence: 5, clock: 14 });
    expect(model.get().planned).toEqual([{ action: { kind: "turn", direction: 2 }, path: false }]);
    expect(model.get().phase).toBe("ready");
    expect(model.get().simulation).toMatchObject({ status: "pending" });
  });

  it("drops the refused action and every one after it (Stop.Invalid), and B waits again", async () => {
    const { model, sim, deps } = stages();
    model.input([WAIT, move(0), move(1)], { path: true });
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 1, stop: Stop.Invalid, sequence: 4, clock: 13 });
    expect(model.get().planned).toEqual([{ action: WAIT, path: true }]);
    // A new batch, previewed again; nothing was sent, B is the player's again
    expect(model.get()).toMatchObject({ phase: "ready", simulation: { status: "pending" } });
    expect(deps.send).not.toHaveBeenCalled();
  });

  it.each([
    ["Stop.Sequence", Stop.Sequence],
    ["Stop.Version", Stop.Version],
  ])(
    "on %s from the simulation: nothing played, actions kept, the state read again",
    async (_, stop) => {
      const { model, sim, loads, deps } = stages();
      loads.push({ ...chainAt(7), target: { ...chainAt(7).target, version: 2 } });
      model.input([WAIT, move(2)]);
      await vi.advanceTimersByTimeAsync(300);
      await sim.answer({ played: 0, stop, sequence: 3, clock: 12 });
      expect(deps.load).toHaveBeenCalledTimes(1);
      expect(model.get()).toMatchObject({
        phase: "ready",
        planned: [
          { action: WAIT, path: false },
          { action: move(2), path: false },
        ],
        chain: { target: { sequence: 7, version: 2 } },
        simulation: { status: "pending" },
      });
      // Previewed again on the state read again: the next simulation sends sequence 7, version 2
      await vi.advanceTimersByTimeAsync(300);
      expect(sim.pending[0]!.calls[0]!.calldata.slice(2, 4)).toEqual([7n, 2n]);
    },
  );

  it.each([
    ["Stop.Sequence", Stop.Sequence],
    ["Stop.Version", Stop.Version],
  ])(
    "on %s from the sent batch: nothing played, actions kept, the state read again",
    async (_, stop) => {
      const { model, sim, results, loads, deps } = stages();
      results.push(sentOf({ played: 0, stop, sequence: 3, clock: 12 }));
      loads.push(chainAt(8));
      model.input([WAIT]);
      model.send();
      await vi.advanceTimersByTimeAsync(0);
      await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
      expect(deps.send).toHaveBeenCalledTimes(1);
      expect(deps.load).toHaveBeenCalledTimes(1);
      expect(model.get()).toMatchObject({
        phase: "ready",
        planned: [{ action: WAIT, path: false }],
        chain: { target: { sequence: 8 } },
        line: lines.STALE,
      });
    },
  );

  it("ends the instance on a defeat; a new state installed plays again", async () => {
    const { model, sim, results } = stages();
    results.push(
      sentOf({ played: 1, stop: Stop.Defeated, sequence: 4, clock: 13, defeated: true, closed: 2 }),
    );
    model.input([WAIT, WAIT]);
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 1, stop: Stop.Defeated, sequence: 4, clock: 13, defeated: true });
    expect(model.get()).toMatchObject({ phase: "closed", planned: [], line: lines.CLOSED });
    expect(model.input([WAIT])).toBe(false);
    model.install(chainAt(0));
    expect(model.get()).toMatchObject({ phase: "ready", planned: [], sent: undefined });
    expect(model.input([WAIT])).toBe(true);
  });

  it("drops the path's steps not played once a batch is sent", async () => {
    const { model, sim, results } = stages();
    results.push(sentOf({ played: 1, stop: Stop.None, sequence: 4, clock: 13 }));
    model.input([move(0), move(1), move(2)], { path: true });
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 3, stop: Stop.None, sequence: 6, clock: 15 });
    expect(model.get().planned).toEqual([]);
  });
});

describe("the send's refusals", () => {
  it("on a fake chain id SN_MAIN, the injected assertChain refuses before execute", async () => {
    const execute = vi.fn(async () => ID);
    const { model, sim } = stages({
      send: (input) =>
        sendBatch(input, {
          account: { execute, status: async () => "succeeded" },
          assertChain: async () => {
            throw new Error("chain mode refused: not a test chain (SN_MAIN)");
          },
          reads: {
            trace: () => Promise.reject(new Error("no read expected")),
            blockOf: () => Promise.reject(new Error("no read expected")),
          },
          readerAt: () => {
            throw new Error("no read expected");
          },
          registry: "0x0456",
        }),
    });
    model.input([WAIT]);
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    expect(execute).not.toHaveBeenCalled();
    expect(model.get()).toMatchObject({
      phase: "ready",
      planned: [{ action: WAIT, path: false }],
      line: "chain mode refused: not a test chain (SN_MAIN)",
      sent: { result: { kind: "refused" } },
    });
  });

  it("reads again after an execution that did not settle, the actions kept", async () => {
    const { model, sim, results, loads } = stages();
    results.push({ kind: "unsettled", id: ID, status: "failed" });
    loads.push(chainAt(3));
    model.input([WAIT]);
    model.send();
    await vi.advanceTimersByTimeAsync(0);
    await sim.answer({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    expect(model.get()).toMatchObject({
      phase: "ready",
      planned: [{ action: WAIT, path: false }],
      line: `${lines.NOT_SENT}: failed`,
    });
  });
});
