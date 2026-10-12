import { describe, expect, it } from "vitest";
import { FIXTURES, fixtureNamed } from "./fixtures";
import type { Facing, Tile } from "../render/view";
import { neighbour } from "./placeholders";
import { FIGHT, combatFixture } from "../combat/fixture";
import {
  applyIntent,
  combatAim,
  fightWorld,
  initialState,
  stepTarget,
  toView,
  walkStep,
} from "./wiring";
import { CHUNK, kindAt } from "./world";

describe("fixtures", () => {
  it("are whole chunks, with one adventurer", () => {
    expect(Object.keys(FIXTURES)).toEqual(["meadow", "cave", "edge", "zone"]);
    for (const world of Object.values(FIXTURES)) {
      expect(world.terrain.width % CHUNK).toBe(0);
      expect(world.terrain.height % CHUNK).toBe(0);
      expect(world.actors.filter((a) => a.side === "adventurer")).toHaveLength(1);
    }
  });

  it("cave: ten goblins on watch, all in sight (SPK-6: ten animated actors)", () => {
    const view = toView(initialState(fixtureNamed("cave")));
    expect(view.actors.filter((a) => a.side === "goblin")).toHaveLength(10);
    expect(view.actors.every((a) => a.mark === null)).toBe(true);
  });

  it("meadow: a pack asleep, partly out of sight", () => {
    const world = fixtureNamed("meadow");
    const view = toView(initialState(world));
    const goblins = world.actors.filter((a) => a.side === "goblin");
    expect(goblins.every((g) => g.mark === "asleep")).toBe(true);
    const shown = view.actors.filter((a) => a.side === "goblin").length;
    expect(shown).toBeGreaterThan(0);
    expect(shown).toBeLessThan(goblins.length);
  });

  it("edge: unrevealed chunks, not in sight at the start", () => {
    const state = initialState(fixtureNamed("edge"));
    const { terrain } = state.world;
    const unrevealed = new Set(
      terrain.kinds.flatMap((kind, i) =>
        kind === "unrevealed" ? [`${i % terrain.width},${Math.floor(i / terrain.width)}`] : [],
      ),
    );
    expect(unrevealed.size).toBe(3 * CHUNK * CHUNK);
    const view = toView(state);
    expect(view.sight.some((t) => unrevealed.has(`${t.x},${t.y}`))).toBe(false);
    // Drawn hidden (CLI-03n): the unrevealed chunks, and the revealed tiles never in sight.
    const hidden = view.tiles.filter((t) => t.kind === "unrevealed");
    expect(hidden.length).toBe(terrain.width * terrain.height - state.explored.size);
    expect(hidden.length).toBeGreaterThan(unrevealed.size);
  });

  it("edge: one step West brings sight onto the unrevealed, and the move reveals it (ADR-0006)", () => {
    let state = initialState(fixtureNamed("edge"));
    const start = state.world.actors[0]!.tile;
    state = walkStep(applyIntent(state, { kind: "tile", tile: { x: start.x + 1, y: start.y } }));
    expect(state.world.actors[0]!.tile).toEqual({ x: start.x + 1, y: start.y });
    const view = toView(state);
    const kinds = new Map(view.tiles.map((t) => [`${t.x},${t.y}`, t.kind]));
    expect(view.sight.every((t) => kinds.get(`${t.x},${t.y}`) !== "unrevealed")).toBe(true);
    // The chunk (2, 0) sight touched is revealed; (2, 1) and (1, 1), out of sight, are not.
    const { terrain } = state.world;
    const inChunk = (cx: number, cy: number) =>
      terrain.kinds
        .map((kind, i) => ({ x: i % terrain.width, y: Math.floor(i / terrain.width), kind }))
        .filter((t) => Math.floor(t.x / CHUNK) === cx && Math.floor(t.y / CHUNK) === cy);
    expect(inChunk(2, 0).some((t) => t.kind === "unrevealed")).toBe(false);
    expect(inChunk(2, 1).every((t) => t.kind === "unrevealed")).toBe(true);
    expect(inChunk(1, 1).every((t) => t.kind === "unrevealed")).toBe(true);
  });

  it("an unknown name falls back to the meadow", () => {
    expect(fixtureNamed("nowhere").name).toBe("meadow");
    expect(fixtureNamed(null).name).toBe("meadow");
  });
});

describe("wiring", () => {
  it("a tap on a floor tile plans the path; its first step faces the direction moved", () => {
    const state = initialState(fixtureNamed("meadow"));
    const adventurer = state.world.actors[0]!;
    const target = { x: adventurer.tile.x - 3, y: adventurer.tile.y };
    const planned = applyIntent(state, { kind: "tile", tile: target });
    expect(planned.walking).toBe(true);
    expect(planned.path).toHaveLength(3);
    expect(planned.world).toBe(state.world);
    const next = walkStep(planned);
    const moved = next.world.actors[0]!;
    expect(moved.tile).toEqual({ x: adventurer.tile.x - 1, y: adventurer.tile.y });
    expect(moved.facing).toBe(0);
    expect(next.selectedTile).toEqual(target);
  });

  it("a tap on a goblin selects it and shows its arcs; again, clears", () => {
    const state = initialState(fixtureNamed("cave"));
    const goblin = toView(state).actors.find((a) => a.side === "goblin")!;
    const selected = applyIntent(state, { kind: "tile", tile: goblin.tile });
    expect(toView(selected).arcs?.actorId).toBe(goblin.id);
    const again = applyIntent(selected, { kind: "tile", tile: goblin.tile });
    expect(toView(again).arcs).toBeNull();
  });

  it("a tap outside the location clears; inspect changes nothing", () => {
    const state = initialState(fixtureNamed("cave"));
    const goblin = toView(state).actors.find((a) => a.side === "goblin")!;
    const selected = applyIntent(state, { kind: "tile", tile: goblin.tile });
    expect(toView(applyIntent(selected, { kind: "tile", tile: { x: -4, y: 3 } })).arcs).toBeNull();
    const inspected = applyIntent(selected, { kind: "inspect", tile: goblin.tile });
    expect(inspected.world).toBe(selected.world);
    expect(inspected.said).toContain("inspect");
  });
});

describe("stepTarget (CLI-03k): a step key is a tap on the adjacent hex", () => {
  const FACINGS: readonly Facing[] = [0, 1, 2, 3, 4, 5];
  const standingAt = (tile: Tile, facing: Facing) => {
    const state = initialState(fixtureNamed("meadow"));
    const { world } = state;
    const actors = world.actors.map((a) =>
      a.id === world.adventurerId ? { ...a, tile, facing } : a,
    );
    return { ...state, world: { ...world, actors } };
  };

  it("is the map library's next tile in each of the six directions, on both row parities", () => {
    for (const tile of [
      { x: 10, y: 10 },
      { x: 10, y: 11 },
    ]) {
      for (const d of FACINGS) {
        expect(stepTarget(standingAt(tile, 0), { direction: d })).toEqual(neighbour(tile, d));
      }
    }
  });

  it("↑ / ↓ take the upper or lower hex on the side faced, on both row parities", () => {
    for (const tile of [
      { x: 10, y: 10 },
      { x: 10, y: 11 },
    ]) {
      for (const facing of FACINGS) {
        const east = facing === 0 || facing === 1 || facing === 5;
        const state = standingAt(tile, facing);
        expect(stepTarget(state, { vertical: "up" })).toEqual(neighbour(tile, east ? 1 : 2));
        expect(stepTarget(state, { vertical: "down" })).toEqual(neighbour(tile, east ? 5 : 4));
      }
    }
  });

  it("applied as a tap, it walks one step that way", () => {
    const state = initialState(fixtureNamed("meadow"));
    const start = state.world.actors[0]!.tile;
    const tile = stepTarget(state, { direction: 3 })!;
    const walked = walkStep(applyIntent(state, { kind: "tile", tile }));
    expect(walked.world.actors[0]!.tile).toEqual(neighbour(start, 3));
    expect(walked.world.actors[0]!.facing).toBe(3);
  });
});

describe("the combat screen's fight (CLI-05c, `?combat=`)", () => {
  const combat = combatFixture();
  const world = fightWorld(fixtureNamed("edge"), combat);
  const state = initialState(world);

  it("puts the fixture's actors on the edge fixture: a Vanguard, each goblin by its entity", () => {
    const adventurer = world.actors.find((a) => a.id === world.adventurerId)!;
    expect(adventurer).toMatchObject({
      side: "adventurer",
      profession: "vanguard",
      tile: { x: 23, y: 7 },
    });
    for (const g of combat.goblins) {
      expect(world.actors.find((a) => a.id === g.entity)).toMatchObject({
        side: "goblin",
        caste: g.casteName,
        tile: g.tile,
        mark: g.mark,
      });
      expect(kindAt(world.terrain, g.tile)).toBe("floor");
    }
    // Wren faces the hobgoblin beside her, and it faces her.
    const hobgoblin = world.actors.find((a) => a.id === FIGHT.hobgoblin)!;
    expect(neighbour(adventurer.tile, adventurer.facing)).toEqual(hobgoblin.tile);
    expect(neighbour(hobgoblin.tile, hobgoblin.facing)).toEqual(adventurer.tile);
    expect(world.path).toEqual([]);
    // Every goblin is in sight at the start.
    expect(toView(state).actors).toHaveLength(5);
  });

  it("a FOE skill reaches its range from Wren and takes the goblins there, nearest first", () => {
    // Charge: range 4 (fixture.ts); the hobgoblin beside, the shaman and the runt within 4.
    const aim = combatAim(state, combat, { kind: "skill", slot: 2 })!;
    expect(aim.addressing).toBe("foe");
    expect(aim.marked[0]).toBe(FIGHT.hobgoblin);
    expect(aim.marked).not.toContain(FIGHT.skirmisher);
    expect(aim.reach.length).toBeGreaterThan(0);
    // Cleave: range 1, the hobgoblin alone.
    expect(combatAim(state, combat, { kind: "skill", slot: 0 })!.marked).toEqual([FIGHT.hobgoblin]);
  });

  it("a SELF skill takes Wren; a shout touches the six tiles around her; an empty slot nothing", () => {
    expect(combatAim(state, combat, { kind: "skill", slot: 1 })).toMatchObject({
      addressing: "self",
      marked: [0],
    });
    const taunt = combatAim(state, combat, { kind: "skill", slot: 3 })!;
    expect(taunt.area?.tiles).toHaveLength(6);
    expect(combatAim(state, combat, { kind: "skill", slot: 6 })).toBeNull();
    expect(combatAim(state, combat, { kind: "item", slot: 3 })).toBeNull();
    expect(combatAim(state, combat, { kind: "item", slot: 0 })).toMatchObject({ marked: [0] });
  });

  it("toView carries the combat overlay only when the session has a fight", () => {
    expect(toView(state).combat).toBeUndefined();
    const rest = toView(state, "sight", { state: combat, armed: null })!.combat!;
    expect(rest.activations.map((a) => a.actor)).toEqual([FIGHT.hobgoblin, FIGHT.shaman]);
    expect(rest.letters).toEqual([
      { actor: FIGHT.skirmisher, tile: { x: 19, y: 10 }, letters: ["P"], more: false },
    ]);
    expect(rest.range).toEqual([]);
    const armed = toView(state, "sight", {
      state: combat,
      armed: { kind: "skill", slot: 2 },
    })!.combat!;
    expect(armed.range.length).toBeGreaterThan(0);
    expect(armed.targets).toContainEqual({ x: 24, y: 7 });
    const preview = toView(state, "sight", {
      state: combat,
      armed: { kind: "skill", slot: 2 },
      preview: { x: 22, y: 7 },
    }).combat!;
    expect(preview.area).toEqual([{ x: 22, y: 7 }]);
  });
});
