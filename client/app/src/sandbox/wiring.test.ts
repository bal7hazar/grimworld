import { describe, expect, it } from "vitest";
import { FIXTURES, fixtureNamed } from "./fixtures";
import { applyIntent, initialState, toView, walkStep } from "./wiring";
import { CHUNK } from "./world";

describe("fixtures", () => {
  it("are whole chunks, with one adventurer", () => {
    expect(Object.keys(FIXTURES)).toEqual(["meadow", "cave", "edge"]);
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
    const view = toView(initialState(fixtureNamed("edge")));
    expect(view.tiles.filter((t) => t.kind === "unrevealed")).toHaveLength(3 * CHUNK * CHUNK);
    const unrevealed = new Set(
      view.tiles.filter((t) => t.kind === "unrevealed").map((t) => `${t.x},${t.y}`),
    );
    expect(view.sight.some((t) => unrevealed.has(`${t.x},${t.y}`))).toBe(false);
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
    const inChunk = (cx: number, cy: number) =>
      view.tiles.filter((t) => Math.floor(t.x / CHUNK) === cx && Math.floor(t.y / CHUNK) === cy);
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
