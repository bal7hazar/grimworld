import { describe, expect, it, vi } from "vitest";
import type { PlayAction } from "./actions";
import { playedTrace, view } from "./fixtures";
import { type ParityRecord, type Prediction, reconcile } from "./reconcile";
import { type ChainOutcome, Outcome, Stop, extractOutcome } from "./trace";

const actions: PlayAction[] = [{ kind: "move", direction: 0 }, { kind: "wait" }];

/** The chain's outcome of `actions`: 2 played, clock 14, goblin 24 killed. */
function chain(overrides: Partial<Parameters<typeof playedTrace>[0]> = {}): ChainOutcome {
  return extractOutcome(
    playedTrace({
      played: 2,
      stop: Stop.None,
      sequence: 5,
      clock: 14,
      killed: [{ entity: 24, caste: 3, tile: 7, by: 0 }],
      ...overrides,
    }),
  );
}

/** The mirror agreeing with `chain()`, from the same view's words. */
function agreeing(): Prediction {
  const after = view(14, 5);
  return {
    words: {
      clock: 14,
      members: after.members.map((m) => ({
        state: m.state,
        timers: m.timers,
        effects: m.effects,
        recharges: m.recharges,
        stats: m.stats,
        bar: m.bar,
        kit: m.kit,
      })),
      goblins: [
        {
          entity: 24,
          awake: false,
          state: after.goblins[0]!.state,
          timers: after.goblins[0]!.timers,
        },
      ],
      killed: [24],
      defeated: false,
    },
    done: { played: 2, reveal: false, illegal: undefined, heavy: false, undo: false },
  };
}

class NotMirrored extends Error {
  constructor(branch: string) {
    super(`not mirrored: ${branch}`);
    this.name = "NotMirrored";
  }
}

describe("reconcile", () => {
  it("finds nothing when the mirror predicts what the chain did, and logs nothing", () => {
    const log = vi.fn();
    const result = reconcile(chain(), actions, () => agreeing(), log);
    expect(result.mismatches).toEqual([]);
    expect(result.mirror).toMatchObject({ kind: "predicted", played: 2, stop: Stop.None });
    expect(log).not.toHaveBeenCalled();
  });

  it("logs a mismatch as a parity bug, and the chain's outcome stands", () => {
    const log = vi.fn<(record: ParityRecord) => void>();
    const wrong = agreeing();
    wrong.words = {
      ...wrong.words,
      clock: 15,
      members: [{ ...wrong.words.members[0]!, state: 1n }],
      goblins: [{ ...wrong.words.goblins[0]!, timers: 2n }],
    };
    const onChain = chain();
    const result = reconcile(onChain, actions, () => wrong, log);
    const after = view(14, 5);
    expect(result.chain).toBe(onChain);
    expect(result.mismatches).toEqual([
      { field: "clock", chain: 14, mirror: 15 },
      { field: "members[0].state", chain: after.members[0]!.state, mirror: 1n },
      { field: "goblins[24].timers", chain: after.goblins[0]!.timers, mirror: 2n },
    ]);
    expect(log).toHaveBeenCalledTimes(1);
    expect(log).toHaveBeenCalledWith({
      kind: "grimworld.parity",
      actions,
      mismatches: result.mismatches,
    });
  });

  it("logs to the console by default, as one structured record", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const wrong = agreeing();
    wrong.done = { ...wrong.done, played: 1, illegal: 14 };
    reconcile(chain(), actions, () => wrong);
    expect(warn).toHaveBeenCalledWith(
      "grimworld.parity",
      expect.objectContaining({
        mismatches: [
          { field: "played", chain: 2, mirror: 1 },
          { field: "stop", chain: Stop.None, mirror: Stop.Invalid },
        ],
      }),
    );
    warn.mockRestore();
  });

  it("counts a segment the mirror does not reach as no prediction, never a mismatch", () => {
    const log = vi.fn();
    const result = reconcile(
      chain(),
      actions,
      () => {
        throw new NotMirrored("TickLibrary::ticks");
      },
      log,
    );
    expect(result.mirror).toEqual({
      kind: "not-mirrored",
      reason: "not mirrored: TickLibrary::ticks",
    });
    expect(result.mismatches).toEqual([]);
    expect(log).not.toHaveBeenCalled();
  });

  it("does not hide another failure of the mirror", () => {
    expect(() =>
      reconcile(chain(), actions, () => {
        throw new RangeError("a bug");
      }),
    ).toThrow("a bug");
  });

  it("has no prediction past a reveal, after an admission refusal, after a revert or unwired", () => {
    const revealing = agreeing();
    revealing.done = { ...revealing.done, reveal: true };
    expect(reconcile(chain(), actions, () => revealing).mirror.kind).toBe("not-mirrored");
    const refused = chain({ played: 0, stop: Stop.Sequence, sequence: 3, killed: [] });
    expect(reconcile(refused, actions, () => agreeing()).mirror.kind).toBe("not-mirrored");
    const reverted: ChainOutcome = { kind: "reverted", reason: "x", raw: "x" };
    expect(reconcile(reverted, actions, () => agreeing())).toMatchObject({
      mirror: { kind: "not-mirrored" },
      mismatches: [],
    });
    expect(reconcile(chain(), actions, undefined).mirror).toEqual({
      kind: "not-mirrored",
      reason: "no mirror wired",
    });
  });

  it("runs the segment again on the actions before an undo, as PlayLibrary does", () => {
    const first = agreeing();
    first.done = { ...first.done, played: 1, heavy: true, undo: true };
    first.words = { ...first.words, clock: 99 };
    const again = agreeing();
    const run = vi.fn((batch: readonly PlayAction[]) => (batch.length === 2 ? first : again));
    const result = reconcile(chain({ played: 1, stop: Stop.Weight }), actions, run);
    expect(run).toHaveBeenLastCalledWith([actions[0]]);
    expect(result.mismatches).toEqual([]);
  });

  it("leaves the words alone once the batch closed the instance", () => {
    const defeated = agreeing();
    defeated.words = {
      ...defeated.words,
      defeated: true,
      members: [{ ...defeated.words.members[0]!, state: 0n }],
    };
    const closed = chain({ stop: Stop.Defeated, defeated: true, closed: Outcome.Defeated });
    expect(reconcile(closed, actions, () => defeated).mismatches).toEqual([]);
  });
});
