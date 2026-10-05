import { describe, expect, it } from "vitest";
import {
  NOTHING_EXPLORED,
  drawnActors,
  explore,
  fogCounts,
  fogTiles,
  tileKey,
  tileSight,
} from "./fog";
import type { ViewActor, ViewState, ViewTile } from "./view";

const goblin = (id: number, x: number, y: number): ViewActor => ({
  id,
  side: "goblin",
  caste: "runt",
  tile: { x, y },
  facing: 0,
  mark: null,
});

const hero: ViewActor = {
  id: 1,
  side: "adventurer",
  profession: "vanguard",
  tile: { x: 0, y: 0 },
  facing: 0,
  mark: null,
};

describe("the explored set (CLI-03n, AC-1)", () => {
  it("grows with the tiles in sight, each once", () => {
    const first = explore(NOTHING_EXPLORED, [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
    ]);
    expect([...first].sort()).toEqual(["0,0", "1,0"]);
    const second = explore(first, [
      { x: 1, y: 0 },
      { x: 2, y: 0 },
    ]);
    expect([...second].sort()).toEqual(["0,0", "1,0", "2,0"]);
    // The set it grew from is not changed: the state before the step keeps its own.
    expect(first.size).toBe(2);
  });

  it("is the same set when sight brings nothing new: nothing downstream changes", () => {
    const explored = explore(NOTHING_EXPLORED, [{ x: 3, y: 4 }]);
    expect(explore(explored, [{ x: 3, y: 4 }])).toBe(explored);
    expect(explore(explored, [])).toBe(explored);
  });
});

describe("the state of a tile (CLI-03n, AC-1)", () => {
  const explored = explore(NOTHING_EXPLORED, [
    { x: 0, y: 0 },
    { x: 1, y: 0 },
  ]);
  const inSight = new Set([tileKey({ x: 1, y: 0 })]);

  it("unseen, explored, or in sight", () => {
    expect(tileSight({ x: 5, y: 5 }, explored, inSight)).toBe("unseen");
    expect(tileSight({ x: 0, y: 0 }, explored, inSight)).toBe("explored");
    expect(tileSight({ x: 1, y: 0 }, explored, inSight)).toBe("inSight");
  });

  it("a tile never in sight is drawn unrevealed, whatever the chain holds; the others as they are", () => {
    const tiles: ViewTile[] = [
      { x: 0, y: 0, kind: "floor", ground: "earth" },
      { x: 1, y: 0, kind: "wall" },
      { x: 2, y: 0, kind: "floor", ground: "water" },
      { x: 3, y: 0, kind: "unrevealed" },
    ];
    expect(fogTiles(tiles, explored)).toEqual([
      { x: 0, y: 0, kind: "floor", ground: "earth" },
      { x: 1, y: 0, kind: "wall" },
      // Its ground is not sent: no lip or foam toward it gives away a shore.
      { x: 2, y: 0, kind: "unrevealed" },
      { x: 3, y: 0, kind: "unrevealed" },
    ]);
  });
});

describe("the goblins drawn (CLI-03n, AC-1)", () => {
  const explored = explore(NOTHING_EXPLORED, [
    { x: 0, y: 0 },
    { x: 1, y: 0 },
    { x: 2, y: 0 },
  ]);

  it("the adventurer, and every goblin on an explored tile; none on a tile never seen", () => {
    const actors = [hero, goblin(2, 1, 0), goblin(3, 2, 0), goblin(4, 9, 9)];
    expect(drawnActors(actors, 1, explored).map((a) => a.id)).toEqual([1, 2, 3]);
  });

  it("the adventurer even off the explored set (it is never hidden)", () => {
    const away = { ...hero, tile: { x: 40, y: 40 } };
    expect(drawnActors([away], 1, explored).map((a) => a.id)).toEqual([1]);
  });

  it("counts what a view draws in each state, and the goblins beyond sight", () => {
    const view: ViewState = {
      tiles: fogTiles(
        [0, 1, 2, 3].map((x): ViewTile => ({ x, y: 0, kind: "floor" })),
        explored,
      ),
      actors: drawnActors([hero, goblin(2, 1, 0), goblin(3, 2, 0)], 1, explored),
      adventurerId: 1,
      sight: [
        { x: 0, y: 0 },
        { x: 1, y: 0 },
      ],
      arcs: null,
      path: [],
      dropped: [],
      selectedTile: null,
    };
    expect(fogCounts(view)).toEqual({ hidden: 1, explored: 1, inSight: 2, goblinsBeyond: 1 });
  });
});
