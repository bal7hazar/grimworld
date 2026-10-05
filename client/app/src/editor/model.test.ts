import { describe, expect, it } from "vitest";
import { hexesWithin } from "../render/ground";
import {
  CHUNK,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  type NewMap,
  WALL,
  apply,
  brushAt,
  chunkOf,
  createMap,
  erase,
  fill,
  indexOf,
  newMapProblem,
  outlineFromFloor,
  outlineRecords,
  paint,
  pick,
  sideTable,
} from "./model";

const ZONE: NewMap = {
  kind: "zone",
  name: "Ashen Meadow",
  location: 2,
  width: 3,
  height: 2,
  biome: "meadow",
  start: "wall",
};

const water = GROUND_KINDS.indexOf("water");
const earth = GROUND_KINDS.indexOf("earth");
const at = (doc: MapDocument, x: number, y: number) => indexOf(doc, { x, y });

describe("a new map", () => {
  it("is whole chunks at the start fill, a zone wholly inside its outline, a town without one", () => {
    const zone = createMap(ZONE);
    expect(zone.terrain.length).toBe(45 * 30);
    expect(zone.terrain.every((v) => v === WALL)).toBe(true);
    expect(zone.ground.every((v) => GROUND_KINDS[v] === "grass")).toBe(true);
    expect(zone.outline?.every((v) => v === 1)).toBe(true);
    const town = createMap({ ...ZONE, kind: "town", start: "floor" });
    expect(town.outline).toBeNull();
    expect(town.meta.biome).toBeNull();
    expect(town.terrain.every((v) => v === FLOOR)).toBe(true);
  });

  it("refuses sizes beyond 15 × 15 chunks for a zone and 4 × 4 for a town, names over 15 characters", () => {
    expect(newMapProblem({ ...ZONE, width: 15, height: 15 })).toBeNull();
    expect(newMapProblem({ ...ZONE, width: 16 })).toMatch(/1 to 15/);
    expect(newMapProblem({ ...ZONE, width: 0 })).toMatch(/1 to 15/);
    expect(newMapProblem({ ...ZONE, kind: "town", width: 5 })).toMatch(/1 to 4/);
    expect(newMapProblem({ ...ZONE, name: "x".repeat(16) })).toMatch(/15 characters/);
    expect(newMapProblem({ ...ZONE, name: "  " })).toMatch(/empty/);
    expect(newMapProblem({ ...ZONE, location: -1 })).toMatch(/location/);
    expect(() => createMap({ ...ZONE, height: 16 })).toThrow();
  });
});

describe("indices (§4.1)", () => {
  it("chunk index is 15 cy + cx and tile index 15 row + column", () => {
    expect(chunkOf({ x: 0, y: 0 })).toEqual({ cx: 0, cy: 0, chunk: 0, tile: 0 });
    expect(chunkOf({ x: 14, y: 9 })).toEqual({ cx: 0, cy: 0, chunk: 0, tile: 149 });
    expect(chunkOf({ x: 16, y: 31 })).toEqual({ cx: 1, cy: 2, chunk: 31, tile: 16 });
    expect(chunkOf({ x: 224, y: 224 })).toEqual({ cx: 14, cy: 14, chunk: 224, tile: 224 });
  });

  it("the side table agrees with the drawing's hexes within one step, and stops at the map's edge", () => {
    const doc = createMap(ZONE);
    const width = CHUNK * 3;
    const table = sideTable(width, CHUNK * 2);
    for (const tile of [
      { x: 5, y: 5 },
      { x: 6, y: 6 },
      { x: 0, y: 0 },
      { x: 44, y: 29 },
    ]) {
      const fromTable = [
        ...table.slice(at(doc, tile.x, tile.y) * 6, at(doc, tile.x, tile.y) * 6 + 6),
      ]
        .filter((i) => i >= 0)
        .sort((a, b) => a - b);
      const expected = hexesWithin(tile, 1)
        .filter((t) => !(t.x === tile.x && t.y === tile.y))
        .filter((t) => t.x >= 0 && t.y >= 0 && t.x < width && t.y < 30)
        .map((t) => at(doc, t.x, t.y))
        .sort((a, b) => a - b);
      expect(fromTable).toEqual(expected);
    }
  });
});

describe("brushes (§3)", () => {
  it("are hexagons of 1, 7, 19 and 37 hexes, cut by the map's edge", () => {
    const doc = createMap(ZONE);
    expect([0, 1, 2, 3].map((r) => brushAt(doc, { x: 20, y: 15 }, r).length)).toEqual([
      1, 7, 19, 37,
    ]);
    expect(brushAt(doc, { x: 0, y: 0 }, 1).length).toBeLessThan(7);
  });
});

describe("paint, erase, fill, pick", () => {
  it("paint writes one layer and reports only the hexes it changed", () => {
    const doc = createMap(ZONE);
    const tiles = brushAt(doc, { x: 10, y: 10 }, 1);
    const changes = paint(doc, tiles, { layer: "terrain", value: FLOOR });
    expect(changes).toHaveLength(7);
    apply(doc, changes);
    expect(paint(doc, tiles, { layer: "terrain", value: FLOOR })).toEqual([]);
    apply(doc, paint(doc, tiles, { layer: "ground", value: earth }));
    expect(doc.ground[at(doc, 10, 10)]).toBe(earth);
    expect(doc.terrain[at(doc, 10, 10)]).toBe(FLOOR);
    // Undone in reverse: the start again.
    apply(doc, changes, true);
    expect(doc.terrain[at(doc, 10, 10)]).toBe(WALL);
  });

  it("erase puts back the start fill and the default ground; with the outline, marks outside", () => {
    const doc = createMap(ZONE);
    const tile = [{ x: 3, y: 3 }];
    apply(doc, paint(doc, tile, { layer: "terrain", value: FLOOR }));
    apply(doc, paint(doc, tile, { layer: "ground", value: water }));
    apply(doc, erase(doc, tile));
    expect(doc.terrain[at(doc, 3, 3)]).toBe(WALL);
    expect(GROUND_KINDS[doc.ground[at(doc, 3, 3)]!]).toBe("grass");
    apply(doc, erase(doc, tile, true));
    expect(doc.outline?.[at(doc, 3, 3)]).toBe(0);
    expect(doc.terrain[at(doc, 3, 3)]).toBe(WALL);
  });

  it("fill takes the connected region of the same terrain and ground, not across a wall", () => {
    const doc = createMap({ ...ZONE, start: "floor" });
    // A wall line across the whole map at y = 10 splits it in two.
    const line = Array.from({ length: 45 }, (_, x) => ({ x, y: 10 }));
    apply(doc, paint(doc, line, { layer: "terrain", value: WALL }));
    const changes = fill(doc, { x: 0, y: 0 }, { layer: "ground", value: water });
    expect(changes).toHaveLength(45 * 10);
    apply(doc, changes);
    expect(doc.ground[at(doc, 5, 9)]).toBe(water);
    expect(GROUND_KINDS[doc.ground[at(doc, 5, 11)]!]).toBe("grass");
    expect(GROUND_KINDS[doc.ground[at(doc, 5, 10)]!]).toBe("grass");
    // Filling a hex that already has the swatch changes nothing.
    expect(fill(doc, { x: 0, y: 0 }, { layer: "ground", value: water })).toEqual([]);
    expect(fill(doc, { x: -1, y: 0 }, { layer: "ground", value: water })).toEqual([]);
  });

  it("fill on the outline is bounded by it", () => {
    const doc = createMap(ZONE);
    // Outside: a ring of radius 3 around (20, 15), with its inside still inside.
    const ring = brushAt(doc, { x: 20, y: 15 }, 3).filter(
      (t) => !brushAt(doc, { x: 20, y: 15 }, 2).some((u) => u.x === t.x && u.y === t.y),
    );
    apply(doc, erase(doc, ring, true));
    // Fill the outside of the ring's inside: the 19 hexes within it go out, nothing else.
    const changes = fill(doc, { x: 20, y: 15 }, { layer: "outline", value: 0 });
    expect(changes).toHaveLength(19);
  });

  it("pick reads a hex's terrain and ground", () => {
    const doc = createMap(ZONE);
    apply(doc, paint(doc, [{ x: 7, y: 8 }], { layer: "ground", value: earth }));
    expect(pick(doc, { x: 7, y: 8 })).toEqual({ terrain: WALL, ground: earth });
    expect(pick(doc, { x: 99, y: 8 })).toBeNull();
  });
});

describe("the outline (§4.4)", () => {
  it("derives the chunk set and the border chunks' masks; a whole chunk has none", () => {
    const doc = createMap(ZONE);
    let records = outlineRecords(doc);
    expect(records.chunks).toEqual([0, 1, 2, 15, 16, 17]);
    expect(records.masks.size).toBe(0);
    // Chunk 2 (cx 2, cy 0) wholly out; one tile of chunk 16 out.
    const chunk2 = [];
    for (let y = 0; y < 15; y++) for (let x = 30; x < 45; x++) chunk2.push({ x, y });
    apply(doc, erase(doc, chunk2, true));
    apply(doc, erase(doc, [{ x: 16, y: 17 }], true));
    records = outlineRecords(doc);
    expect(records.chunks).toEqual([0, 1, 15, 16, 17]);
    expect([...records.masks.keys()]).toEqual([16]);
    const mask = records.masks.get(16)!;
    expect(mask).toHaveLength(224);
    expect(mask).not.toContain(chunkOf({ x: 16, y: 17 }).tile);
  });

  it("every chunk of the set lies within the map's rectangle (R-11, by construction)", () => {
    const doc = createMap({ ...ZONE, width: 15, height: 15 });
    const { chunks } = outlineRecords(doc);
    expect(chunks).toHaveLength(225);
    expect(Math.max(...chunks)).toBe(224);
    for (const c of chunks) {
      expect(c % 15).toBeLessThan(15);
      expect(Math.floor(c / 15)).toBeLessThan(15);
    }
  });

  it("from floor: the connected floor region of a hex, else the largest", () => {
    const doc = createMap(ZONE);
    const small = brushAt(doc, { x: 5, y: 5 }, 1);
    const large = brushAt(doc, { x: 30, y: 20 }, 2);
    apply(doc, paint(doc, [...small, ...large], { layer: "terrain", value: FLOOR }));
    apply(doc, outlineFromFloor(doc, null));
    expect(doc.outline?.reduce((s, v) => s + v, 0)).toBe(19);
    expect(doc.outline?.[at(doc, 30, 20)]).toBe(1);
    apply(doc, outlineFromFloor(doc, { x: 5, y: 5 }));
    expect(doc.outline?.reduce((s, v) => s + v, 0)).toBe(7);
    expect(doc.outline?.[at(doc, 30, 20)]).toBe(0);
    expect(outlineFromFloor(createMap(ZONE), null)).toEqual([]);
  });
});
