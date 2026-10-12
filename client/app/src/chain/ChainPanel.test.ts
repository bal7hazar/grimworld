import { describe, expect, it } from "vitest";
import type { ExecutionId } from "../account";
import type { PlayAction } from "../preview/actions";
import { type MirrorResult, reconcile } from "../preview/reconcile";
import { recordedPlayed, recordedReverted } from "../preview/recorded-goblins";
import { Stop, extractOutcome } from "../preview/trace";
import type { ControllerState } from "./ChainController";
import { actionText, describe as panelOf, outcomeText, stopName } from "./ChainPanel";
import type { ChainState, Sent } from "./send";
import type { StagesState } from "./stages";

const WAIT: PlayAction = { kind: "wait" };
const ID = "0x1" as unknown as ExecutionId;
const chain = {} as ChainState;
const own: ControllerState = { turning: false, selected: null, entering: false, note: undefined };

const played = () => extractOutcome(recordedPlayed);
const predicted: MirrorResult = {
  kind: "predicted",
  played: 1,
  stop: Stop.None,
  moved: false,
  words: { clock: 24, members: [], goblins: [], killed: [], defeated: false },
};

function stagesState(more: Partial<StagesState> = {}): StagesState {
  return {
    phase: "ready",
    chain,
    planned: [{ action: WAIT, path: false }],
    mirror: undefined,
    simulation: undefined,
    sent: undefined,
    line: undefined,
    ...more,
  };
}

describe("the panel's words (§5)", () => {
  it("names the actions and the stops", () => {
    expect(actionText({ kind: "move", direction: 3 })).toBe("move 3");
    expect(actionText({ kind: "turn", direction: 1 })).toBe("turn 1");
    expect(actionText(WAIT)).toBe("wait");
    expect(actionText({ kind: "attack", entity: 8 })).toBe("attack #8");
    expect(stopName(Stop.Weight)).toBe("weight");
    expect(stopName(99)).toBe("stop 99");
  });

  it("says how far a played batch ran and why it stopped, and what a revert said", () => {
    const text = outcomeText(played());
    expect(text).toMatch(/^played 1, stop none, clock \d+, killed 0, revealed 0$/);
    const reverted = outcomeText(extractOutcome(recordedReverted));
    expect(reverted).toBe("reverted: not controller");
  });
});

describe("the three stages, each shown as soon as it is known", () => {
  it("an empty batch shows no stage, a planned one shows the batch and stage 1 at once", () => {
    expect(panelOf(stagesState({ planned: [] }), own)).toMatchObject({ batch: [], stages: [] });
    const model = panelOf(stagesState({ mirror: predicted }), own);
    expect(model.batch).toEqual(["wait"]);
    expect(model.stages).toEqual([{ stage: "mirror", text: "played 1, stop none, clock 24" }]);
  });

  it("says 'not mirrored' in the mirror's own words", () => {
    const mirror: MirrorResult = { kind: "not-mirrored", reason: "a goblin cannot load" };
    expect(panelOf(stagesState({ mirror }), own).stages).toEqual([
      { stage: "mirror", text: "not mirrored: a goblin cannot load" },
    ]);
  });

  it("stage 2 is pending, then the simulation's outcome with the mirror's mismatches", () => {
    const mirror = predicted;
    const pending = stagesState({
      mirror,
      simulation: { request: 1, actions: [WAIT], status: "pending" },
    });
    expect(panelOf(pending, own).stages.map((s) => s.stage)).toEqual(["mirror", "simulated"]);
    expect(panelOf(pending, own).stages[1]?.text).toBe("simulating…");
    const reconciliation = reconcile(played(), [WAIT], undefined);
    const answered = stagesState({
      mirror,
      simulation: {
        request: 1,
        actions: [WAIT],
        status: "answered",
        preview: {
          kind: "simulated",
          ...reconciliation,
          mismatches: [{ field: "clock", chain: 24, mirror: 25 }],
        },
      },
    });
    const model = panelOf(answered, own);
    expect(model.stages[1]).toEqual({ stage: "simulated", text: outcomeText(played()) });
    expect(model.differs).toEqual(["mirror differs: clock"]);
  });

  it("a simulation that failed or was refused says so", () => {
    const error = stagesState({
      simulation: { request: 1, actions: [WAIT], status: "error", error: "node down" },
    });
    expect(panelOf(error, own).stages).toEqual([{ stage: "simulated", text: "failed: node down" }]);
    const refused = stagesState({
      simulation: {
        request: 1,
        actions: [WAIT],
        status: "answered",
        preview: { kind: "refused", reason: "a batch is 1 to 10 actions" },
      },
    });
    expect(panelOf(refused, own).stages[0]?.text).toBe("refused: a batch is 1 to 10 actions");
  });

  it("stage 3 shows the chain's result beside the simulation's, and which fields differ", () => {
    const reconciliation = reconcile(played(), [WAIT], undefined);
    const simulated = { kind: "simulated" as const, ...reconciliation };
    const result: Sent = {
      kind: "sent",
      id: ID,
      blockHash: "0x2",
      differs: ["batch.clock", "view.members.0.state"],
      after: chain,
      ...reconciliation,
      mismatches: [{ field: "goblins.0.state", chain: 1, mirror: 2 }],
    };
    const model = panelOf(
      stagesState({
        mirror: predicted,
        simulation: { request: 1, actions: [WAIT], status: "answered", preview: simulated },
        sent: { simulated, result },
      }),
      own,
    );
    expect(model.stages.map((s) => s.stage)).toEqual(["mirror", "simulated", "sent"]);
    expect(model.stages[2]?.text).toBe(outcomeText(played()));
    expect(model.differs).toEqual([
      "mirror differs: goblins.0.state",
      "sent differs from simulated: batch.clock",
      "sent differs from simulated: view.members.0.state",
    ]);
  });

  it("after a settled send the simulation it was sent on stays beside the sent result", () => {
    const reconciliation = reconcile(played(), [WAIT], undefined);
    const simulated = { kind: "simulated" as const, ...reconciliation };
    const model = panelOf(
      stagesState({
        planned: [],
        sent: {
          simulated,
          result: {
            kind: "sent",
            id: ID,
            blockHash: "0x2",
            differs: [],
            after: chain,
            ...reconciliation,
          },
        },
      }),
      own,
    );
    expect(model.stages).toEqual([
      { stage: "simulated", text: outcomeText(played()) },
      { stage: "sent", text: outcomeText(played()) },
    ]);
  });

  it("a send that was refused, did not settle or could not be read, says so", () => {
    const reconciliation = reconcile(played(), [WAIT], undefined);
    const simulated = { kind: "simulated" as const, ...reconciliation };
    const sentAs = (result: Sent) => panelOf(stagesState({ sent: { simulated, result } }), own);
    expect(
      sentAs({ kind: "refused", reason: "no funds" }).stages.find((line) => line.stage === "sent")
        ?.text,
    ).toBe("refused: no funds");
    expect(
      sentAs({ kind: "unsettled", id: ID, status: "failed" }).stages.find(
        (line) => line.stage === "sent",
      )?.text,
    ).toBe("not settled: failed");
    expect(
      sentAs({ kind: "unread", id: ID, status: "succeeded", error: "no trace" }).stages.find(
        (line) => line.stage === "sent",
      )?.text,
    ).toBe("sent, unread: no trace");
  });
});

describe("the panel's line", () => {
  it("is the controller's note first, then the stages' line", () => {
    const state = stagesState({ line: "the instance closed", phase: "closed" });
    expect(panelOf(state, own).line).toBe("the instance closed");
    expect(panelOf(state, { ...own, note: "no path" }).line).toBe("no path");
    expect(panelOf(stagesState(), own).line).toBeUndefined();
    expect(panelOf(state, own).phase).toBe("closed");
  });

  it("shows an armed turn", () => {
    expect(panelOf(stagesState(), { ...own, turning: true }).turning).toBe(true);
  });
});

describe("the selection (CLI-11c2)", () => {
  it("names the selected goblin, and nothing when none is", () => {
    expect(panelOf(stagesState(), own).selected).toBeNull();
    expect(panelOf(stagesState(), { ...own, selected: 8 }).selected).toBe(8);
  });
});
