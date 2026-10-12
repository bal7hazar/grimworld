import { describe, expect, it } from "vitest";
import { combatFixture, FIGHT } from "./fixture";

describe("the sandbox's fixed fight (§9)", () => {
  it("at rest: one slot ready, one recharging, one short of energy, one of adrenaline, one wrong weapon, three empty", () => {
    const { adventurer } = combatFixture();
    const states = adventurer.bar.map((s) => s.state).sort();
    expect(states).toEqual(
      [
        "empty",
        "empty",
        "empty",
        "ready",
        "recharging",
        "short-adrenaline",
        "short-energy",
        "wrong-weapon",
      ].sort(),
    );
    expect(adventurer.bar.slice(0, 5).map((s) => s.skill?.name)).toEqual([
      "Cleave",
      "Shield bash",
      "Charge",
      "Taunt",
      "Second wind",
    ]);
    expect(adventurer.bar.find((s) => s.state === "recharging")!.ticks).toBe(3);
    expect(adventurer.activation).toBeNull();
  });

  it("the belt: two potions with a count, an emptied slot, an empty slot", () => {
    const { belt } = combatFixture().adventurer;
    expect(belt.map((s) => [s.name ?? null, s.count, s.state])).toEqual([
      ["Healing potion", 3, "some"],
      ["Antidote", 1, "some"],
      ["Regeneration potion", 0, "none-left"],
      [null, 0, "empty"],
    ]);
  });

  it("Wren's chips: bleeding 4, a REGENERATION, Shield bash's BLOCK with 2 charges and 6 ticks", () => {
    const { adventurer } = combatFixture();
    expect(adventurer.chips.map((c) => [c.letter, c.ticks, c.charges])).toEqual([
      ["B", 4, null],
      ["R", 5, null],
      ["▣", 6, 2],
    ]);
    const shieldBash = adventurer.bar[1]!.skill!;
    expect(adventurer.chips[2]!.source).toEqual({ potion: false, id: shieldBash.id });
  });

  it("the goblins: the hobgoblin on Wren, the shaman on the runt, the skirmisher poisoned", () => {
    const { goblins, adventurer } = combatFixture();
    const by = (entity: number) => goblins.find((g) => g.entity === entity)!;
    expect(by(FIGHT.hobgoblin).activation).toMatchObject({
      name: "Overhead Smash",
      ticks: 2,
      target: { tile: false, entity: adventurer.entity },
    });
    expect(by(FIGHT.shaman).activation).toMatchObject({
      name: "Mend Kin",
      target: { tile: false, entity: FIGHT.runt },
    });
    expect(by(FIGHT.skirmisher).chips.map((c) => c.letter)).toEqual(["P"]);
  });

  it("the second state: Wren activating Charge, the rest of the bar not now", () => {
    const { adventurer } = combatFixture("activating");
    expect(adventurer.activation).toMatchObject({ name: "Charge", ticks: 1 });
    const states = adventurer.bar.map((s) => s.state);
    expect(states.filter((s) => s === "activating")).toHaveLength(1);
    expect(states.filter((s) => s === "not-now")).toHaveLength(4);
    expect(states.filter((s) => s === "empty")).toHaveLength(3);
  });

  it("decides nothing: no clock, no randomness", async () => {
    const text = (await import("./fixture.ts?raw")).default;
    expect(text).not.toMatch(/Math\.random|Date\.|performance\.now|crypto\./);
  });
});
