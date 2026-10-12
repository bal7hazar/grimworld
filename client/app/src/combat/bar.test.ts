import {
  type Action,
  Illegal,
  type Words,
  actionAct,
  indexSheets,
  loadWorld,
  memberRecharge,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { barOf, beltOf, slotState } from "./bar";
import { readWorld } from "./fromWords";
import type { SlotState } from "./state";
import { actRow, atClock, contentOf, tickRow } from "./vectors.testkit";

const ACT = contentOf("act.jsonl");
const TICK = contentOf("tick.jsonl");

/** The member of an `act.jsonl` row's words, loaded by client/sim. */
const member = (words: Words) => loadWorld(words, indexSheets(ACT)).members[0]!;

/** `ActionLibrary::act` on a row's words with another action. */
function refusal(id: number, action: Action, words?: Words): number | undefined {
  const row = actRow(id);
  const out = actionAct({ ...row, words: words ?? row.words, content: ACT, action });
  return "illegal" in out.outcome ? out.outcome.illegal : undefined;
}

const skillOf = (id: number): Extract<Action, { kind: "skill" }> => {
  const action = actRow(id).action;
  if (action.kind !== "skill") throw new Error(`act.jsonl row ${id} plays a ${action.kind}`);
  return action;
};

describe("a bar slot's state (§2.2), in act's order", () => {
  // Each `act.jsonl` row whose skill action the action class refuses (or plays), with the state the
  // slot shows on the same words
  const CASES: readonly [number, SlotState, number | undefined][] = [
    [15, "not-now", Illegal.Knocked],
    [43, "empty", Illegal.Empty],
    [47, "wrong-weapon", Illegal.Kind],
    [57, "recharging", Illegal.Recharging],
    [60, "short-adrenaline", Illegal.Adrenaline],
    [64, "short-energy", Illegal.Energy],
    [48, "ready", undefined],
  ];

  for (const [id, state, illegal] of CASES) {
    it(`act.jsonl row ${id}: ${state}, and actionAct refuses with ${illegal ?? "nothing"}`, () => {
      const row = actRow(id);
      const { slot } = skillOf(id);
      expect(slotState(member(row.words), indexSheets(ACT), row.words.clock, slot).state).toBe(state);
      expect(refusal(id, row.action)).toBe(illegal);
    });
  }

  it("shows a recharge's ticks as recharge − clock, ready at the deadline, as act reads it", () => {
    const row = actRow(57);
    const { slot } = skillOf(57);
    const deadline = memberRecharge(member(row.words), slot);
    const sheets = indexSheets(ACT);
    const at = (clock: number) => slotState(member(atClock(row.words, clock)), sheets, clock, slot);
    expect(at(deadline - 1)).toEqual({ state: "recharging", ticks: 1 });
    expect(refusal(57, row.action, atClock(row.words, deadline - 1))).toBe(Illegal.Recharging);
    for (const clock of [deadline, deadline + 1]) {
      expect(at(clock).state).not.toBe("recharging");
      expect(refusal(57, row.action, atClock(row.words, clock))).not.toBe(Illegal.Recharging);
    }
  });

  it("an activation: its slot activating with act_deadline − clock, the others not now", () => {
    // tick.jsonl row 78: the adventurer activates slot 0 until tick 201, at clock 200
    const row = tickRow(78);
    const cw = readWorld(row.words, TICK, row.ground, row.board);
    const bar = barOf(cw.world.members[0]!, cw.sheets, row.words.clock);
    expect(bar[0]).toMatchObject({ state: "activating", ticks: 1 });
    expect(bar.slice(1).every((s) => s.state === "not-now")).toBe(true);
    // At its deadline it has resolved (`conclude` at `act_deadline <= t`): nothing activates
    const after = barOf(cw.world.members[0]!, cw.sheets, 201);
    expect(after[0]!.state).not.toBe("activating");
  });

  it("a carrier client/sim cannot mirror (R-44's mixed targets) is unavailable", () => {
    // Row 48's slot 0 is ready; its skill made to mix a TILE entry with a FOE one
    const row = actRow(48);
    const { slot } = skillOf(48);
    const sheets = indexSheets(ACT);
    const at = member(row.words).bar_at[slot]!;
    const entry = (kind: number, target: number) =>
      BigInt(kind) + (BigInt(target) << 86n) + (1n << 88n);
    const skills = ACT.skills.map((s, k) =>
      k === at ? { ...s, kind: 2, entry1: entry(1, 3), entry2: entry(1, 1), entry3: 0n } : s,
    );
    const mixed = indexSheets({ ...ACT, skills });
    expect(slotState(member(row.words), sheets, row.words.clock, slot).state).toBe("ready");
    const m = loadWorld(row.words, mixed).members[0]!;
    expect(slotState(m, mixed, row.words.clock, slot).state).toBe("unavailable");
  });

  it("gives the cost client/sim's energy gives, in whole points", () => {
    const row = actRow(64);
    const { slot } = skillOf(64);
    const view = barOf(member(row.words), indexSheets(ACT), row.words.clock)[slot]!;
    expect(view.skill).not.toBeNull();
    expect(view.skill!.energy * 3).toBeGreaterThan(member(row.words).energy);
  });
});

describe("a belt slot (§3), in act's order", () => {
  it("has some, none left (Belt), no item (Empty), as actionAct refuses", () => {
    const sheets = indexSheets(ACT);
    const some = actRow(144);
    expect(beltOf(member(some.words), sheets, some.words.clock)[0]!.state).toBe("some");
    expect(refusal(144, some.action)).toBeUndefined();
    const none = actRow(146);
    expect(beltOf(member(none.words), sheets, none.words.clock)[0]!).toMatchObject({
      state: "none-left",
      count: 0,
    });
    expect(refusal(146, none.action)).toBe(Illegal.Belt);
    const empty = actRow(150);
    expect(beltOf(member(empty.words), sheets, empty.words.clock)[3]!).toMatchObject({
      state: "empty",
      item: null,
    });
    expect(refusal(150, empty.action)).toBe(Illegal.Empty);
  });

  it("is not now while knocked down (Knocked)", () => {
    const row = actRow(16);
    expect(beltOf(member(row.words), indexSheets(ACT), row.words.clock)[0]!.state).toBe("not-now");
    expect(refusal(16, row.action)).toBe(Illegal.Knocked);
  });
});
