import { describe, expect, it } from "vitest";
import type { Facing, ViewActor } from "../render/view";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import {
  SIGHT_RADIUS,
  arcsOf,
  distance,
  facingToward,
  neighbour,
  revealInSight,
  stepToward,
  tilesInSight,
  visibleActors,
} from "./placeholders";
import { CHUNK, type Terrain } from "./world";

function open(width: number, height: number): Terrain {
  const kinds = new Array(width * height).fill("floor");
  return { width, height, kinds, hidden: kinds };
}

const goblin = (x: number, y: number, facing: Facing, id = 2): ViewActor => ({
  id,
  side: "goblin",
  caste: "runt",
  tile: { x, y },
  facing,
  mark: null,
});

describe("placeholders", () => {
  it("neighbour is the library's Direction::next, on both row parities", () => {
    for (const tile of [
      { x: 10, y: 10 },
      { x: 10, y: 11 },
      { x: 3, y: 0 },
    ]) {
      for (const d of LIBRARY_DIRECTIONS) {
        expect(neighbour(tile, d)).toEqual(libraryNext(tile, d));
      }
    }
  });

  it("distance matches the contracts' test of origami_hexmap (width 7)", () => {
    const at = (i: number) => ({ x: i % 7, y: Math.floor(i / 7) });
    expect(distance(at(3), at(9))).toBe(1);
    expect(distance(at(0), at(14))).toBe(2);
    expect(distance(at(7), at(13))).toBe(6);
    expect(distance(at(24), at(24))).toBe(0);
    for (const d of LIBRARY_DIRECTIONS)
      expect(distance({ x: 5, y: 5 }, neighbour({ x: 5, y: 5 }, d))).toBe(1);
  });

  it("sight is the hexagon of radius 6: 127 tiles, 13 on the adventurer's row", () => {
    const sight = tilesInSight(open(30, 30), { x: 15, y: 15 });
    expect(sight).toHaveLength(1 + 3 * SIGHT_RADIUS * (SIGHT_RADIUS + 1));
    expect(sight.filter((t) => t.y === 15)).toHaveLength(13);
    expect(sight.every((t) => distance(t, { x: 15, y: 15 }) <= 6)).toBe(true);
  });

  it("arcs: front d, front-side d ± 1, rear-side d ± 2, back d + 3, walls left out", () => {
    for (const d of LIBRARY_DIRECTIONS) {
      const actor = goblin(10, 11, d);
      const arcs = arcsOf(open(30, 30), actor);
      const at = (by: number) => libraryNext(actor.tile, ((d + by) % 6) as Facing);
      expect(arcs.front).toEqual([at(0)]);
      expect(arcs.frontSide).toEqual([at(1), at(5)]);
      expect(arcs.rearSide).toEqual([at(2), at(4)]);
      expect(arcs.back).toEqual([at(3)]);
    }
    const walled: Terrain = { ...open(30, 30), kinds: open(30, 30).kinds.map(() => "wall") };
    expect(arcsOf(walled, goblin(10, 11, 0)).back).toEqual([]);
  });

  it("a step goes to the closer free floor tile and faces the direction moved", () => {
    const terrain = open(30, 30);
    const adventurer: ViewActor = {
      ...goblin(10, 10, 0, 1),
      side: "adventurer",
      profession: "vanguard",
    } as ViewActor;
    // (8, 12) is 3 away; East (9, 10) and North-East (9, 11) are both 2 away: East, the lower.
    const step = stepToward(terrain, [adventurer], 1, { x: 8, y: 12 });
    expect(step).toEqual({ tile: { x: 9, y: 10 }, facing: 0 });
    const blocked = stepToward(terrain, [adventurer, goblin(9, 10, 0)], 1, { x: 8, y: 12 });
    expect(blocked).toEqual({ tile: { x: 9, y: 11 }, facing: 1 });
    // No closer free tile: no step.
    expect(stepToward(terrain, [adventurer, goblin(9, 10, 0)], 1, { x: 5, y: 10 })).toBeNull();
    expect(stepToward(terrain, [adventurer], 1, { x: 10, y: 10 })).toBeNull();
  });

  it("a tie between two steps goes to the lowest tile index, not the lowest direction", () => {
    const terrain = open(30, 30);
    const adventurer = { ...goblin(10, 10, 0, 1), side: "adventurer", profession: "vanguard" };
    // (12, 12) is 3 away; North-West (10, 11) and West (11, 10) are both 2 away. West has the
    // lower tile index (row 10 before row 11), though North-West has the lower direction (2 < 3).
    expect(stepToward(terrain, [adventurer as ViewActor], 1, { x: 12, y: 12 })).toEqual({
      tile: { x: 11, y: 10 },
      facing: 3,
    });
  });

  it("visibleActors: the adventurer, and the goblins within sight only (design/18)", () => {
    const adventurer = { ...goblin(10, 10, 0, 1), side: "adventurer", profession: "vanguard" };
    const near = goblin(16, 10, 0, 2);
    const far = goblin(17, 10, 0, 3);
    const seen = visibleActors(open(30, 30), [adventurer as ViewActor, near, far]);
    expect(seen.map((a) => a.id)).toEqual([1, 2]);
  });

  it("revealInSight: a chunk that sight touches takes its hidden terrain; others stay", () => {
    const base = open(45, 15);
    const kinds = base.kinds.map((kind, i) => (i % 45 >= 2 * CHUNK ? "unrevealed" : kind));
    const hidden = base.kinds.map((kind, i) => (i % 45 === 31 ? "wall" : kind));
    const terrain: Terrain = { ...base, kinds, hidden };
    // Six tiles from x = 30: sight touches the third chunk.
    const revealed = revealInSight(terrain, { x: 24, y: 7 });
    expect(revealed.kinds.filter((k) => k === "unrevealed")).toHaveLength(0);
    expect(revealed.kinds[7 * 45 + 31]).toBe("wall");
    // Seven tiles away: nothing changes.
    expect(revealInSight(terrain, { x: 23, y: 7 })).toBe(terrain);
  });

  it("facingToward gives the direction of an adjacent tile only", () => {
    for (const d of LIBRARY_DIRECTIONS) {
      expect(facingToward({ x: 4, y: 7 }, libraryNext({ x: 4, y: 7 }, d))).toBe(d);
    }
    expect(facingToward({ x: 4, y: 7 }, { x: 8, y: 7 })).toBeNull();
  });
});
