import { type CSSProperties, useSyncExternalStore } from "react";
import type { PlayAction } from "../preview/actions";
import type { ChainOutcome } from "../preview/trace";
import { Stop } from "../preview/trace";
import type { ChainController, ControllerState } from "./ChainController";
import type { Stages, StagesState } from "./stages";

/**
 * The chain mode's panel (CLI-11 §5): the batch, and its three stages as each becomes known, the
 * mirror's at once, the simulation's, the sent batch's beside it. It is a developer's tool behind
 * `?chain=`: it may say "batch", "sent" and "simulated" (I-3 governs the player's screen, CLI-03).
 * `describe` is the whole of what it says, as data, so that a test reads it without a DOM.
 */

export type StageLine = { readonly stage: "mirror" | "simulated" | "sent"; readonly text: string };

export interface PanelModel {
  /** The batch planned, one entry per action. */
  readonly batch: readonly string[];
  /** The stages known so far, in order. */
  readonly stages: readonly StageLine[];
  /** The fields where the mirror, the simulation or the sent outcome differ, for the stages' last line. */
  readonly differs: readonly string[];
  /** One line: a refusal, "no funds", "the instance closed", the controller's note. */
  readonly line: string | undefined;
  /** The keys that work now. */
  readonly phase: StagesState["phase"];
  readonly turning: boolean;
}

const STOP_NAMES: Readonly<Record<number, string>> = {
  [Stop.None]: "none",
  [Stop.Sequence]: "sequence",
  [Stop.Invalid]: "invalid",
  [Stop.Weight]: "weight",
  [Stop.Defeated]: "defeated",
  [Stop.Closed]: "closed",
  [Stop.Version]: "version",
};
export const stopName = (stop: number): string => STOP_NAMES[stop] ?? `stop ${stop}`;

/** An action in one short word: `move 3`, `turn 1`, `wait`, `attack #8`. */
export function actionText(action: PlayAction): string {
  switch (action.kind) {
    case "move":
    case "turn":
      return `${action.kind} ${action.direction}`;
    case "wait":
      return "wait";
    case "attack":
      return `attack #${action.entity}`;
    case "skill":
      return `skill ${action.slot}`;
    case "item":
      return `item ${action.slot}`;
    case "interact":
      return `interact ${action.tile}`;
  }
}

/** What an outcome of the chain says: how far the batch played, why it stopped, what it did. */
export function outcomeText(outcome: ChainOutcome): string {
  if (outcome.kind === "reverted") return `reverted: ${outcome.reason}`;
  const { batch, killed, revealed, defeated, closed } = outcome;
  const parts = [
    `played ${batch.played}, stop ${stopName(batch.stop)}, clock ${batch.clock}`,
    `killed ${killed.length}`,
    `revealed ${revealed.length}`,
  ];
  if (defeated) parts.push("defeated");
  if (closed !== undefined) parts.push("closed");
  return parts.join(", ");
}

/** The mirror's stage, in the mirror's own words where it predicts nothing. */
function mirrorText(mirror: NonNullable<StagesState["mirror"]>): string {
  if (mirror.kind === "not-mirrored") return `not mirrored: ${mirror.reason}`;
  const clock = mirror.words.clock;
  return `played ${mirror.played}, stop ${stopName(mirror.stop)}, clock ${clock}${mirror.words.defeated ? ", defeated" : ""}`;
}

export function describe(state: StagesState, controller: ControllerState): PanelModel {
  const stages: StageLine[] = [];
  const differs: string[] = [];
  if (state.mirror !== undefined) stages.push({ stage: "mirror", text: mirrorText(state.mirror) });
  const { simulation } = state;
  if (simulation !== undefined) {
    if (simulation.status === "pending") {
      stages.push({ stage: "simulated", text: "simulating…" });
    } else if (simulation.status === "error") {
      stages.push({ stage: "simulated", text: `failed: ${simulation.error}` });
    } else if (simulation.preview.kind === "refused") {
      stages.push({ stage: "simulated", text: `refused: ${simulation.preview.reason}` });
    } else {
      const { chain, mismatches } = simulation.preview;
      stages.push({ stage: "simulated", text: outcomeText(chain) });
      if (mismatches.length > 0) {
        differs.push(...mismatches.map((m) => `mirror differs: ${m.field}`));
      }
    }
  }
  const { sent } = state;
  // Once a send settled the plan is the next batch's: the simulation the batch was sent on stays
  // beside the sent result (§5.3)
  if (simulation === undefined && sent !== undefined) {
    const { simulated } = sent;
    stages.push({
      stage: "simulated",
      text:
        simulated.kind === "refused"
          ? `refused: ${simulated.reason}`
          : outcomeText(simulated.chain),
    });
  }
  if (sent !== undefined) {
    const { result } = sent;
    if (result.kind === "sent") {
      stages.push({ stage: "sent", text: outcomeText(result.chain) });
      differs.push(...result.mismatches.map((m) => `mirror differs: ${m.field}`));
      differs.push(...result.differs.map((field) => `sent differs from simulated: ${field}`));
    } else if (result.kind === "refused") {
      stages.push({ stage: "sent", text: `refused: ${result.reason}` });
    } else if (result.kind === "unsettled") {
      stages.push({ stage: "sent", text: `not settled: ${result.status}` });
    } else {
      stages.push({ stage: "sent", text: `sent, unread: ${result.error}` });
    }
  }
  return {
    batch: state.planned.map(({ action }) => actionText(action)),
    stages,
    differs,
    line: controller.note ?? state.line,
    phase: state.phase,
    turning: controller.turning,
  };
}

function useStore<T>(subscribe: (listener: () => void) => () => void, get: () => T): T {
  return useSyncExternalStore(subscribe, get);
}

export function ChainPanel({
  stages,
  controller,
}: {
  stages: Stages;
  controller: ChainController;
}) {
  const staged = useStore(
    (listener) => stages.subscribe(listener),
    () => stages.get(),
  );
  const own = useStore(
    (listener) => controller.subscribe(listener),
    () => controller.get(),
  );
  const model = describe(staged, own);
  const busy = model.phase === "sending" || model.phase === "reading";
  return (
    <div style={styles.panel} data-chain-panel={model.phase} aria-live="polite">
      <div data-panel="batch">
        batch {model.batch.length}/10: {model.batch.length === 0 ? "empty" : model.batch.join(", ")}
        {model.turning ? " · turn: press a step key" : ""}
      </div>
      {model.stages.map(({ stage, text }) => (
        <div key={stage} data-stage={stage}>
          {stage}: {text}
        </div>
      ))}
      {model.differs.map((text) => (
        <div key={text} data-panel="differs">
          {text}
        </div>
      ))}
      {model.line !== undefined && <div data-panel="line">{model.line}</div>}
      <div style={styles.buttons}>
        <button
          disabled={busy || model.phase === "closed" || model.batch.length === 0}
          onClick={() => controller.send()}
        >
          Send (B)
        </button>
        {model.phase === "closed" && (
          <button disabled={own.entering} onClick={() => void controller.enterAgain()}>
            Enter again (N)
          </button>
        )}
      </div>
      <div style={styles.keys}>
        tap / Q W E A S D / arrows: move · Space: wait · R + key: turn · 2nd tap on a goblin: attack
      </div>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  panel: {
    position: "fixed",
    left: 8,
    bottom: 8,
    maxWidth: "min(46rem, calc(100vw - 16px))",
    padding: "6px 10px",
    borderRadius: 6,
    border: "1px dashed #6bc7ff",
    font: "0.75rem ui-monospace, monospace",
    color: "#eee",
    background: "rgba(0,0,0,0.78)",
    zIndex: 10,
    display: "grid",
    gap: 2,
  },
  buttons: { display: "flex", gap: 6, marginTop: 4 },
  keys: { opacity: 0.6 },
};
