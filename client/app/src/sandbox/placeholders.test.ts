import { describe, expect, it } from "vitest";
import type { Facing, ViewActor } from "../render/view";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import {
  SIGHT_RADIUS,
  arcsOf,
  distance,
  facingToward,
  findPath,
  inWindow,
  neighbour,
  revealInSight,
  stepToward,
  tilesInSight,
  visibleActors,
} from "./placeholders";
import { CHUNK, type Terrain, sameTile } from "./world";

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

/** A terrain of floor with walls at the given tiles. */
function walled(
  width: number,
  height: number,
  walls: readonly { x: number; y: number }[],
): Terrain {
  const base = open(width, height);
  const kinds = base.kinds.map((kind, i) =>
    walls.some((w) => w.y * width + w.x === i) ? ("wall" as const) : kind,
  );
  return { ...base, kinds };
}

const hero = (x: number, y: number): ViewActor => ({
  id: 1,
  side: "adventurer",
  profession: "vanguard",
  tile: { x, y },
  facing: 0,
  mark: null,
});

/** Every step of a path is a neighbour of the one before, starting next to `from`. */
function isChain(from: { x: number; y: number }, path: readonly { x: number; y: number }[]) {
  let at = from;
  for (const tile of path) {
    if (distance(at, tile) !== 1) return false;
    at = tile;
  }
  return true;
}

describe("findPath (PLACEHOLDER until CLI-02)", () => {
  const me = hero(10, 10);

  it("a straight line, first step first, the start left out", () => {
    const path = findPath(open(30, 30), [me], me.tile, { x: 13, y: 10 });
    expect(path).toEqual([
      { x: 11, y: 10 },
      { x: 12, y: 10 },
      { x: 13, y: 10 },
    ]);
    expect(findPath(open(30, 30), [me], me.tile, { x: 9, y: 10 })).toEqual([{ x: 9, y: 10 }]);
  });

  it("around a wall, and around an actor, by the lowest tile index", () => {
    // (11, 10) blocked: two ways of 3 steps, by row 9 or by row 11; row 9 is the lower index.
    const around = [
      { x: 10, y: 9 },
      { x: 11, y: 9 },
      { x: 12, y: 10 },
    ];
    const wall = walled(30, 30, [{ x: 11, y: 10 }]);
    expect(findPath(wall, [me], me.tile, { x: 12, y: 10 })).toEqual(around);
    const runt = goblin(11, 10, 0);
    expect(findPath(open(30, 30), [me, runt], me.tile, { x: 12, y: 10 })).toEqual(around);
    // A longer wall: the path goes round its end.
    const long = walled(
      30,
      30,
      [7, 8, 9, 10, 11, 12].map((y) => ({ x: 12, y })),
    );
    const path = findPath(long, [me], me.tile, { x: 14, y: 10 })!;
    expect(isChain(me.tile, path)).toBe(true);
    expect(path.at(-1)).toEqual({ x: 14, y: 10 });
    expect(path.some((t) => t.x === 12 && t.y >= 7 && t.y <= 12)).toBe(false);
    expect(path[0]!.y).toBeGreaterThan(10); // row 13 is 3 rows away, row 6 is 4
  });

  it("no path: the target is a wall, unrevealed, held, the start, or walled in", () => {
    const terrain = open(30, 30);
    const unrevealed: Terrain = {
      ...terrain,
      kinds: terrain.kinds.map((k, i) => (i === 10 * 30 + 13 ? "unrevealed" : k)),
    };
    expect(
      findPath(walled(30, 30, [{ x: 13, y: 10 }]), [me], me.tile, { x: 13, y: 10 }),
    ).toBeNull();
    expect(findPath(unrevealed, [me], me.tile, { x: 13, y: 10 })).toBeNull();
    expect(findPath(terrain, [me, goblin(13, 10, 0)], me.tile, { x: 13, y: 10 })).toBeNull();
    expect(findPath(terrain, [me], me.tile, me.tile)).toBeNull();
    const target = { x: 13, y: 10 };
    const ring = ([0, 1, 2, 3, 4, 5] as const).map((d) => neighbour(target, d));
    expect(findPath(walled(30, 30, ring), [me], me.tile, target)).toBeNull();
    // Walls and unrevealed tiles are never stepped on.
    const band = walled(
      30,
      30,
      [9, 10, 11].map((y) => ({ x: 11, y })),
    );
    const kinds = band.kinds.map((k, i) =>
      i === 8 * 30 + 11 || i === 12 * 30 + 11 ? "unrevealed" : k,
    );
    const path = findPath({ ...band, kinds }, [me], me.tile, { x: 12, y: 10 })!;
    expect(path.every((t) => kinds[t.y * 30 + t.x] === "floor")).toBe(true);
    expect(isChain(me.tile, path)).toBe(true);
    expect(path.at(-1)).toEqual({ x: 12, y: 10 });
  });

  it("the tie rule: every step takes the lowest tile index among the shortest", () => {
    const terrain = open(30, 30);
    for (const to of [
      { x: 12, y: 12 },
      { x: 7, y: 13 },
      { x: 14, y: 7 },
      { x: 6, y: 8 },
    ]) {
      const path = findPath(terrain, [me], me.tile, to)!;
      expect(path).toHaveLength(distance(me.tile, to));
      let at = me.tile;
      for (const tile of path) {
        const candidates = ([0, 1, 2, 3, 4, 5] as const)
          .map((d) => neighbour(at, d))
          .filter((t) => distance(t, to) === distance(at, to) - 1)
          .sort((a, b) => a.y - b.y || a.x - b.x);
        expect(tile, JSON.stringify(to)).toEqual(candidates[0]);
        at = tile;
      }
    }
  });

  it("bounded by the window of 15 × 16 around the adventurer (D-120)", () => {
    const terrain = open(40, 40);
    // Columns: 7 each side.
    expect(findPath(terrain, [me], me.tile, { x: 17, y: 10 })).toHaveLength(7);
    expect(findPath(terrain, [me], me.tile, { x: 18, y: 10 })).toBeNull();
    expect(findPath(terrain, [me], me.tile, { x: 3, y: 10 })).toHaveLength(7);
    expect(findPath(terrain, [me], me.tile, { x: 2, y: 10 })).toBeNull();
    // Rows on an even row: 10 - 8 = 2 to 17; on an odd row: 11 - 7 = 4 to 19.
    const window = (centre: { x: number; y: number }) => {
      const rows = new Set<number>();
      for (let y = 0; y < 40; y++) if (inWindow(centre, { x: centre.x, y })) rows.add(y);
      return [Math.min(...rows), Math.max(...rows), rows.size];
    };
    expect(window({ x: 10, y: 10 })).toEqual([2, 17, 16]);
    expect(window({ x: 10, y: 11 })).toEqual([4, 19, 16]);
    expect(findPath(terrain, [me], me.tile, { x: 10, y: 2 })).not.toBeNull();
    expect(findPath(terrain, [me], me.tile, { x: 10, y: 1 })).toBeNull();
    expect(findPath(terrain, [me], me.tile, { x: 10, y: 17 })).not.toBeNull();
    expect(findPath(terrain, [me], me.tile, { x: 10, y: 18 })).toBeNull();
    // A way that exists only outside the window is no way: a wall across the window's rows.
    const wall = walled(
      40,
      40,
      Array.from({ length: 30 }, (_, y) => ({ x: 13, y })).filter((t) => t.y !== 20),
    );
    expect(findPath(wall, [me], me.tile, { x: 15, y: 10 })).toBeNull();
    const open20 = walled(
      40,
      40,
      Array.from({ length: 30 }, (_, y) => ({ x: 13, y })).filter((t) => t.y !== 16),
    );
    const path = findPath(open20, [me], me.tile, { x: 15, y: 10 })!;
    expect(path.every((t) => inWindow(me.tile, t))).toBe(true);
    expect(path.some((t) => sameTile(t, { x: 13, y: 16 }))).toBe(true);
  });
});
