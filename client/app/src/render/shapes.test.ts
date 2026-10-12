import { memberPlace } from "@grimworld/sim";
import { Graphics } from "pixi.js";
import { describe, expect, it } from "vitest";
import { FIGHT, combatFixture } from "../combat/fixture";
import { readWorld, stateOf } from "../combat/fromWords";
import { type CombatOverlay, combatOverlay } from "../combat/overlay";
import type { Chip, CombatGoblin, CombatState } from "../combat/state";
import { aiming, areaOf } from "../combat/targeting";
import { actRow, contentOf } from "../combat/vectors.testkit";
import {
  type CombatPlan,
  drawCombat,
  drawCombatLabels,
  drawLabel,
  drawOverlay,
  hasGlyph,
  labelWidth,
  overlayPlan,
} from "./shapes";
import type { Tile, ViewState } from "./view";

const ACT = contentOf("act.jsonl");
const has = (tiles: readonly Tile[], t: Tile) => tiles.some((u) => u.x === t.x && u.y === t.y);
const tileFrom = (value: number): Tile => ({ x: value % 256, y: Math.floor(value / 256) });

/** A view with nothing but the adventurer at `own` and combat: no tile dimmed, no arc, no path. */
function viewOf(combat: CombatOverlay | undefined, own: Tile): ViewState {
  return {
    tiles: [],
    actors: [
      { id: 1, side: "adventurer", profession: "vanguard", tile: own, facing: 0, mark: null },
    ],
    adventurerId: 1,
    sight: [],
    arcs: null,
    path: [],
    dropped: [],
    selectedTile: null,
    combat,
  };
}

const planOf = (combat: CombatOverlay, own: Tile): CombatPlan =>
  overlayPlan(viewOf(combat, own)).combat!;

/** The fills and strokes a drawing issued. */
function counts(draw: (g: Graphics) => void): { fills: number; strokes: number } {
  const g = new Graphics();
  draw(g);
  const actions = g.context.instructions.map((i) => i.action);
  return {
    fills: actions.filter((a) => a === "fill").length,
    strokes: actions.filter((a) => a === "stroke").length,
  };
}

const empty: CombatPlan = {
  range: [],
  greyed: [],
  area: [],
  targets: [],
  activations: [],
  lines: [],
  shouts: [],
  letters: [],
  knocked: [],
};

const condition = (letter: string): Chip => ({
  kind: "condition",
  letter,
  name: letter,
  ticks: 2,
  charges: null,
  pips: null,
  source: null,
});

/** The fixture with the hobgoblin's activation changed. */
function withSmash(
  ticks: number,
  interruptible = false,
  goblin: Partial<CombatGoblin> = {},
): CombatState {
  const state = combatFixture();
  return {
    ...state,
    goblins: state.goblins.map((g) =>
      g.entity === FIGHT.hobgoblin
        ? { ...g, ...goblin, activation: { ...g.activation!, ticks, interruptible } }
        : g,
    ),
  };
}

describe("overlayPlan: combat on the map (CLI-05d)", () => {
  it("no combat in the view: no combat plan, and the overlay draws as before", () => {
    const view = viewOf(undefined, { x: 0, y: 0 });
    expect(overlayPlan(view).combat).toBeNull();
    const g = new Graphics();
    drawOverlay(g, view);
    expect(g.context.instructions).toHaveLength(0);
    drawCombatLabels(g, view);
    expect(g.context.instructions).toHaveLength(0);
  });

  it("a FOE skill's range: tinted, with its out-of-sight tiles greyed and crossed", () => {
    // act.jsonl row 75: a FOE skill of range 6, four tiles in range out of sight
    const row = actRow(75);
    const cw = readWorld(row.words, ACT, row.ground, row.board);
    const state = stateOf(cw);
    const aim = aiming(cw, { kind: "skill", slot: 0 })!;
    expect(aim.addressing).toBe("foe");
    expect(aim.greyed.length).toBeGreaterThan(0);
    const plan = planOf(combatOverlay(state, aim), state.adventurer.tile);
    expect(plan.range).toEqual(aim.reach);
    expect(plan.greyed).toEqual(aim.greyed);
    for (const t of plan.greyed) expect(has(plan.range, t)).toBe(false);
    // Range: a tint and an outline a tile; greyed: a fill and a cross a tile; nobody marked
    expect(plan.targets).toEqual([]);
    expect(counts((g) => drawCombat(g, plan))).toEqual({
      fills: plan.range.length + plan.greyed.length,
      strokes: plan.range.length + plan.greyed.length,
    });
  });

  it("a RING_1 on self: the six tiles around the adventurer tinted, not its own, the foes on them marked", () => {
    // Skill 40 (SELF, RING_1, on foes) put in bar slot 0 of act.jsonl row 50, as targeting's test does
    const row = actRow(50);
    const words = { ...row.words, members: row.words.members.map((m) => ({ ...m })) };
    const bar = words.members[0]!.bar;
    words.members[0]!.bar = bar - (bar & 0xffffn) + 40n;
    const cw = readWorld(words, ACT, row.ground, row.board);
    const state = stateOf(cw);
    const me = memberPlace(cw.world.members[0]!);
    const own = { x: me.x, y: me.y };
    const aim = aiming(cw, { kind: "skill", slot: 0 })!;
    expect(aim.addressing).toBe("self");
    const area = areaOf(cw, { kind: "skill", slot: 0 }, own);
    const plan = planOf(combatOverlay(state, { ...aim, area }), own);
    expect(plan.range).toEqual([]);
    expect(plan.area).toEqual(area.tiles);
    expect(plan.area.length).toBeGreaterThan(0);
    expect(plan.area.length).toBeLessThanOrEqual(6);
    expect(has(plan.area, own)).toBe(false);
    const foes = state.goblins.filter((g) => area.marked.includes(g.entity)).map((g) => g.tile);
    for (const t of foes) expect(has(plan.targets, t)).toBe(true);
    // The area: a tint and an outline a tile; a target mark: its circle and its four ticks
    expect(counts((g) => drawCombat(g, { ...empty, area: plan.area }))).toEqual({
      fills: plan.area.length,
      strokes: plan.area.length,
    });
    expect(counts((g) => drawCombat(g, { ...empty, targets: [own] }))).toEqual({
      fills: 0,
      strokes: 2,
    });
  });

  it("a DISC_1 potion: the centre and its neighbours tinted, the goblins it takes marked", () => {
    // act.jsonl row 144 throws potion 100 (DISC_1, foes) on tile 1801
    const row = actRow(144);
    const cw = readWorld(row.words, ACT, row.ground, row.board);
    const state = stateOf(cw);
    const aim = aiming(cw, { kind: "item", slot: 0 })!;
    const centre = tileFrom(1801);
    const area = areaOf(cw, { kind: "item", slot: 0 }, centre);
    const plan = planOf(combatOverlay(state, { ...aim, area }), state.adventurer.tile);
    expect(has(plan.area, centre)).toBe(true);
    expect(plan.area.length).toBeGreaterThan(1);
    expect(plan.area.length).toBeLessThanOrEqual(7);
    expect(area.marked.length).toBeGreaterThan(0);
    for (const g of state.goblins.filter((g) => area.marked.includes(g.entity))) {
      expect(has(plan.targets, g.tile)).toBe(true);
    }
  });

  it("a goblin's ring at 3, 2 and 1 tick left: filled from nothing to two thirds, its figure the ticks", () => {
    const filled: number[] = [];
    for (const ticks of [3, 2, 1]) {
      const state = withSmash(ticks);
      const plan = planOf(combatOverlay(state), state.adventurer.tile);
      const ring = plan.activations.find((a) => a.tile.x === 24 && a.tile.y === 7)!;
      expect(ring).toMatchObject({ ticks, total: 3, own: false, interruptible: false });
      filled.push(ring.filled);
      // A faint full turn (its backing and its line), then the part gone by, if any
      expect(counts((g) => drawCombat(g, { ...empty, activations: [ring] })).strokes).toBe(
        ticks === 3 ? 2 : 3,
      );
    }
    expect(filled).toEqual([0, 1 / 3, 2 / 3]);
  });

  it("the interruptible highlight: the ring in its own colour, doubled", () => {
    const state = withSmash(2, true);
    const plan = planOf(combatOverlay(state), state.adventurer.tile);
    const ring = plan.activations.find((a) => a.interruptible)!;
    expect(ring.tile).toEqual({ x: 24, y: 7 });
    const plain = { ...ring, interruptible: false };
    const one = counts((g) => drawCombat(g, { ...empty, activations: [plain] }));
    const two = counts((g) => drawCombat(g, { ...empty, activations: [ring] }));
    expect(two.strokes).toBe(one.strokes + 1);
    // Its figure too is in the highlight's colour
    const colours = (s: CombatState) => {
      const g = new Graphics();
      drawCombatLabels(g, viewOf(combatOverlay(s), s.adventurer.tile));
      return g.context.instructions
        .filter((i) => i.action === "fill")
        .map((i) => (i.data as { style: { color: number } }).style.color);
    };
    expect(colours(state)).not.toEqual(colours(withSmash(2, false)));
  });

  it("a target line from each caster to its target, ending on a target mark", () => {
    const state = combatFixture();
    const plan = planOf(combatOverlay(state), state.adventurer.tile);
    const runt = state.goblins.find((g) => g.entity === FIGHT.runt)!.tile;
    expect(plan.lines).toEqual([
      { from: { x: 24, y: 7 }, to: state.adventurer.tile },
      { from: { x: 26, y: 9 }, to: runt },
    ]);
    // Two lines, two marks (a circle and its ticks each), two rings (backing, line, part gone by)
    const drawn = counts((g) => drawCombat(g, plan));
    expect(drawn).toEqual({ fills: 0, strokes: 2 + 2 * 2 + 2 * 3 });
    // A caster aimed at itself draws no line
    const self = planOf(
      {
        ...combatOverlay(state),
        activations: [{ ...combatOverlay(state).activations[0]!, target: { x: 24, y: 7 } }],
      },
      state.adventurer.tile,
    );
    expect(self.lines).toEqual([]);
  });

  it("the adventurer's own ring (the sandbox's), in its colour, and its line to the runt", () => {
    const state = combatFixture("activating");
    const plan = planOf(combatOverlay(state), state.adventurer.tile);
    const own = plan.activations.find((a) => a.own)!;
    expect(own).toMatchObject({ tile: state.adventurer.tile, ticks: 1, total: 2, filled: 1 / 2 });
    const runt = state.goblins.find((g) => g.entity === FIGHT.runt)!.tile;
    expect(plan.lines).toContainEqual({ from: state.adventurer.tile, to: runt });
  });

  it("three letters and a + under a goblin; one letter alone", () => {
    const state = withSmash(2, false, { chips: ["B", "P", "F", "K"].map(condition) });
    const plan = planOf(combatOverlay(state), state.adventurer.tile);
    const skirmisher = state.goblins.find((g) => g.entity === FIGHT.skirmisher)!.tile;
    expect(plan.letters).toEqual([
      { tile: { x: 24, y: 7 }, text: "BPF+" },
      { tile: skirmisher, text: "P" },
    ]);
    // Each label: its backing, then its cells in one fill; two rings' figures, two letter rows
    const g = new Graphics();
    drawCombatLabels(g, viewOf(combatOverlay(state), state.adventurer.tile));
    expect(g.context.instructions.filter((i) => i.action === "fill")).toHaveLength(2 * 4);
  });

  it("the pixel font draws every figure and condition letter, and a block for the rest", () => {
    for (const c of "0123456789BPFCK+") expect(hasGlyph(c), c).toBe(true);
    expect(hasGlyph("Z")).toBe(false);
    // "1": 8 cells; "BPF+": 10 + 8 + 8 + 5 cells; an unknown character: its 15 cells
    const cells = (text: string) => {
      const g = new Graphics();
      drawLabel(g, text, 0, 0, 0xffffff);
      return g.context.instructions.at(-1)!.data as {
        path: { shapePath: { shapePrimitives: unknown[] } };
      };
    };
    expect(cells("1").path.shapePath.shapePrimitives).toHaveLength(8);
    expect(cells("BPF+").path.shapePath.shapePrimitives).toHaveLength(31);
    expect(cells("Z").path.shapePath.shapePrimitives).toHaveLength(15);
    expect(labelWidth("BPF+")).toBeGreaterThan(labelWidth("P"));
  });

  it("the knocked down listed as tiles, for the renderer", () => {
    const state = withSmash(2, false, { knocked: true });
    expect(planOf(combatOverlay(state), state.adventurer.tile).knocked).toEqual([{ x: 24, y: 7 }]);
  });
});
