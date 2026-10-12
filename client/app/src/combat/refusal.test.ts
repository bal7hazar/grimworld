import { Illegal } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { NOT_AVAILABLE_YET, UNREACHABLE, beltLine, refusalLine, slotLine } from "./refusal";
import type { BarSlot, BeltSlot } from "./state";

describe("the refusals before the batch (§4.4)", () => {
  it("gives each Illegal a skill or item tap can meet its line", () => {
    expect(refusalLine(Illegal.Knocked)).toBe("You are knocked down.");
    expect(refusalLine(Illegal.Instant)).toBe("Only one instant skill between two ticks.");
    expect(refusalLine(Illegal.Belt)).toBe("None left.");
    expect(refusalLine(Illegal.Kind)).toBe("Needs its weapon.");
    expect(refusalLine(Illegal.Recharging, 3)).toBe("Recharging: 3 ticks.");
    expect(refusalLine(Illegal.Recharging, 1)).toBe("Recharging: 1 tick.");
    expect(refusalLine(Illegal.Energy)).toBe("Not enough energy.");
    expect(refusalLine(Illegal.Adrenaline)).toBe("Not enough adrenaline.");
    expect(refusalLine(Illegal.Target)).toBe("Not a valid target.");
    expect(refusalLine(Illegal.Reach)).toBe("Out of reach.");
    expect(refusalLine(Illegal.Trap)).toBe("A trap cannot go there.");
  });

  it("says nothing of Empty, nor of the refusals a tap cannot reach (a parity record instead)", () => {
    expect(refusalLine(Illegal.Empty)).toBeNull();
    for (const illegal of UNREACHABLE) expect(refusalLine(illegal)).toBeNull();
    expect(UNREACHABLE).toEqual([Illegal.Clock, Illegal.Absent, Illegal.Turned, Illegal.Blocked]);
  });

  it("speaks of no chain, and offers no interaction", () => {
    const every = Object.values(Illegal).map((i) => refusalLine(i, 2) ?? "");
    for (const line of [...every, NOT_AVAILABLE_YET]) {
      expect(line).not.toMatch(/chain|batch|transaction|contract|stark/i);
    }
    expect(NOT_AVAILABLE_YET).toBe("Not available yet.");
  });
});

describe("a tap on a slot that is not ready says its state in one line (§2.4)", () => {
  const slot = (state: BarSlot["state"], ticks: number | null = null): BarSlot => ({
    slot: 0,
    skill: null,
    state,
    ticks,
  });

  it("by state", () => {
    expect(slotLine(slot("recharging", 3), false)).toBe("Recharging: 3 ticks.");
    expect(slotLine(slot("short-energy"), false)).toBe("Not enough energy.");
    expect(slotLine(slot("short-adrenaline"), false)).toBe("Not enough adrenaline.");
    expect(slotLine(slot("wrong-weapon"), false)).toBe("Needs its weapon.");
    expect(slotLine(slot("not-now"), true)).toBe("You are knocked down.");
    expect(slotLine(slot("not-now"), false)).toBe("You are activating a skill.");
    expect(slotLine(slot("unavailable"), false)).toBe("Not available.");
    expect(slotLine(slot("ready"), false)).toBeNull();
    expect(slotLine(slot("empty"), false)).toBeNull();
  });

  it("a belt slot", () => {
    const belt = (state: BeltSlot["state"]): BeltSlot => ({
      slot: 0,
      item: 1,
      look: "heal",
      count: 0,
      state,
      addressing: "self",
      range: 0,
    });
    expect(beltLine(belt("none-left"), false)).toBe("None left.");
    expect(beltLine(belt("not-now"), true)).toBe("You are knocked down.");
    expect(beltLine(belt("some"), false)).toBeNull();
  });
});
