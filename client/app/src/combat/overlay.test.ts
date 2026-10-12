import { describe, expect, it } from "vitest";
import { combatFixture, FIGHT } from "./fixture";
import { readWorld, stateOf } from "./fromWords";
import { MAX_LETTERS, combatOverlay } from "./overlay";
import type { Chip, CombatState } from "./state";
import { aiming, areaOf } from "./targeting";
import { actRow, contentOf, tickRow } from "./vectors.testkit";

const letter = (l: string): Chip => ({
  kind: "condition",
  letter: l,
  name: l,
  ticks: 2,
  charges: null,
  pips: null,
  source: null,
});

describe("the combat overlay (§4.2, §4.3, §5, §6.1)", () => {
  it("at rest: the goblins' activations with their ticks and target lines, no range", () => {
    const state = combatFixture();
    const overlay = combatOverlay(state);
    expect(overlay.range).toEqual([]);
    expect(overlay.area).toEqual([]);
    const smash = overlay.activations.find((a) => a.actor === FIGHT.hobgoblin)!;
    expect(smash).toMatchObject({ ticks: 2, total: 3, target: state.adventurer.tile });
    const mend = overlay.activations.find((a) => a.actor === FIGHT.shaman)!;
    const runt = state.goblins.find((g) => g.entity === FIGHT.runt)!;
    expect(mend.target).toEqual(runt.tile);
    // The poisoned skirmisher's letter under its feet
    expect(overlay.letters).toEqual([
      { actor: FIGHT.skirmisher, tile: state.goblins[3]!.tile, letters: ["P"], more: false },
    ]);
  });

  it("the adventurer's own activation (the sandbox's second state), its ring and target line", () => {
    const state = combatFixture("activating");
    const own = combatOverlay(state).activations.find((a) => a.actor === 0)!;
    expect(own).toMatchObject({ ticks: 1, total: 2, interruptible: false });
    expect(own.target).toEqual(state.goblins.find((g) => g.entity === FIGHT.runt)!.tile);
  });

  it("at most three letters under a goblin, then +; the knocked down listed", () => {
    const state = combatFixture();
    const crowded: CombatState = {
      ...state,
      goblins: state.goblins.map((g, k) =>
        k === 0 ? { ...g, knocked: true, chips: ["B", "P", "F", "K"].map(letter) } : g,
      ),
    };
    const overlay = combatOverlay(crowded);
    const first = overlay.letters.find((l) => l.actor === FIGHT.hobgoblin)!;
    expect(first.letters).toHaveLength(MAX_LETTERS);
    expect(first.more).toBe(true);
    expect(overlay.knocked).toEqual([state.goblins[0]!.tile]);
  });

  it("an armed slot: the range, its greyed tiles, the area and the targets marked, from targeting", () => {
    // act.jsonl row 70: a FOE skill, goblin 8 in reach
    const row = actRow(70);
    const content = contentOf("act.jsonl");
    const cw = readWorld(row.words, content, row.ground, row.board);
    const state = stateOf(cw);
    const aim = aiming(cw, { kind: "skill", slot: 0 })!;
    const goblin = state.goblins.find((g) => g.entity === 8)!;
    const area = areaOf(cw, { kind: "skill", slot: 0 }, goblin.tile);
    const overlay = combatOverlay(state, { ...aim, area });
    expect(overlay.range).toEqual(aim.reach);
    expect(overlay.greyed).toEqual(aim.greyed);
    expect(overlay.area).toEqual(area.tiles);
    expect(overlay.targets).toContainEqual(goblin.tile);
  });

  it("a goblin's activation from the words, interruptible only by a ready slot that interrupts", () => {
    const row = tickRow(91);
    const cw = readWorld(row.words, contentOf("tick.jsonl"), row.ground, row.board);
    const overlay = combatOverlay(stateOf(cw));
    expect(overlay.activations).toHaveLength(1);
    expect(overlay.activations[0]).toMatchObject({ actor: 8, ticks: 1, interruptible: false });
  });
});
