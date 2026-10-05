import { describe, expect, it } from "vitest";
import { acrossSide, hexesWithin } from "../render/ground";
import type { Tile } from "../render/view";
import {
  COORD_MAX,
  FILL_MAX,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  type NewMap,
  WALL,
  apply,
  brushAt,
  cellAt,
  createMap,
  erase,
  fill,
  groundOfCell,
  isOutside,
  keyOf,
  mapKeys,
  newMapProblem,
  outlineFromFloor,
  paint,
  paintedBox,
  pick,
  sideOf,
  terrainOf,
  tileOfKey,
} from "./model";

const ZONE: NewMap = { kind: "zone", name: "Ashen Meadow", location: 2, biome: "meadow" };

const water = GROUND_KINDS.indexOf("water");
const earth = GROUND_KINDS.indexOf("earth");
/** Far from the origin, on an odd and negative row. */
const FAR: Tile = { x: 5003, y: -3001 };
const near = (dx: number, dy: number): Tile => ({ x: FAR.x + dx, y: FAR.y + dy });

function painted(doc: MapDocument, tiles: readonly Tile[], value = FLOOR as 0 | 1): void {
  apply(doc, paint(doc, tiles, { layer: "terrain", value }));
}

const insideCount = (doc: MapDocument) =>
  [...doc.hexes.values()].filter((c) => !isOutside(c)).length;

describe("a new map (D-216)", () => {
  it("has no size and nothing painted; a town no biome", () => {
    const zone = createMap(ZONE);
    expect(zone.hexes.size).toBe(0);
    expect(zone.origin).toBeNull();
    expect(paintedBox(zone)).toBeNull();
    const town = createMap({ ...ZONE, kind: "town" });
    expect(town.meta.biome).toBeNull();
  });

  it("refuses names over 15 characters, an empty name and a bad location", () => {
    expect(newMapProblem(ZONE)).toBeNull();
    expect(newMapProblem({ ...ZONE, name: "x".repeat(16) })).toMatch(/15 characters/);
    expect(newMapProblem({ ...ZONE, name: "  " })).toMatch(/empty/);
    expect(newMapProblem({ ...ZONE, location: -1 })).toMatch(/location/);
    expect(() => createMap({ ...ZONE, name: "" })).toThrow();
  });
});

describe("the plane", () => {
  it("keys every hex within ±COORD_MAX, negatives included", () => {
    for (const tile of [
      { x: 0, y: 0 },
      FAR,
      { x: -COORD_MAX, y: COORD_MAX },
      { x: COORD_MAX, y: -COORD_MAX },
      { x: -1, y: -1 },
    ]) {
      expect(tileOfKey(keyOf(tile))).toEqual(tile);
    }
    expect(keyOf({ x: 1, y: 0 })).not.toBe(keyOf({ x: 0, y: 1 }));
  });

  it("sideOf agrees with the drawing's hexes (acrossSide) on even, odd and negative rows", () => {
    for (const tile of [{ x: 0, y: 0 }, { x: 0, y: 1 }, { x: -7, y: -3 }, { x: 12, y: -4 }, FAR]) {
      for (let side = 0; side < 6; side++) {
        expect(sideOf(tile, side), `${tile.x},${tile.y} side ${side}`).toEqual(
          acrossSide(tile, side),
        );
      }
    }
  });

  it("brushes are hexagons of 1, 7, 19 and 37 hexes anywhere", () => {
    expect([0, 1, 2, 3].map((r) => brushAt(FAR, r).length)).toEqual([1, 7, 19, 37]);
    expect([0, 1, 2, 3].map((r) => brushAt({ x: -40, y: -41 }, r).length)).toEqual([1, 7, 19, 37]);
  });
});

describe("paint, erase, fill, pick on the sparse map", () => {
  it("paint stores only the painted hexes, anywhere, and reports only what changed", () => {
    const doc = createMap(ZONE);
    const tiles = brushAt(FAR, 1);
    const changes = paint(doc, tiles, { layer: "terrain", value: FLOOR });
    expect(changes).toHaveLength(7);
    expect(changes.every((c) => c.before === null)).toBe(true);
    apply(doc, changes);
    expect(doc.hexes.size).toBe(7);
    expect(paint(doc, tiles, { layer: "terrain", value: FLOOR })).toEqual([]);
    apply(doc, paint(doc, tiles, { layer: "ground", value: earth }));
    const cell = cellAt(doc, FAR)!;
    expect(groundOfCell(cell)).toBe(earth);
    expect(terrainOf(cell)).toBe(FLOOR);
    // A ground swatch on an unpainted hex paints it as floor.
    apply(doc, paint(doc, [{ x: -2, y: -2 }], { layer: "ground", value: water }));
    expect(pick(doc, { x: -2, y: -2 })).toEqual({ terrain: FLOOR, ground: water });
    expect(paintedBox(doc)).toEqual({ x0: -2, y0: -3002, x1: 5004, y1: -2 });
    // Undone in reverse: the plane is empty again.
    apply(doc, changes, true);
    expect(cellAt(doc, FAR)).toBeNull();
  });

  it("erase unpaints; with the outline, it marks painted hexes outside and leaves the void alone", () => {
    const doc = createMap(ZONE);
    painted(doc, [FAR, near(1, 0)]);
    apply(doc, erase(doc, [near(1, 0), near(2, 0)]));
    expect(doc.hexes.size).toBe(1);
    apply(doc, erase(doc, [FAR, near(5, 5)], true));
    expect(isOutside(cellAt(doc, FAR)!)).toBe(true);
    expect(doc.hexes.size).toBe(1);
    // Outline in: back inside; an unpainted hex stays unpainted.
    apply(doc, paint(doc, [FAR, near(9, 9)], { layer: "outline", value: 1 }));
    expect(isOutside(cellAt(doc, FAR)!)).toBe(false);
    expect(doc.hexes.size).toBe(1);
    // A town has no outline: the outline swatch changes nothing.
    const town = createMap({ ...ZONE, kind: "town" });
    painted(town, [FAR]);
    expect(erase(town, [FAR], true)).toEqual([]);
  });

  it("fill takes the connected painted region of the same terrain and ground, not across a wall", () => {
    const doc = createMap(ZONE);
    // A 20 × 10 floor block far away, cut by a wall row at dy = 4.
    const block: Tile[] = [];
    for (let dy = 0; dy < 10; dy++) for (let dx = 0; dx < 20; dx++) block.push(near(dx, dy));
    painted(doc, block);
    painted(
      doc,
      block.filter((t) => t.y === FAR.y + 4),
      WALL,
    );
    const changes = fill(doc, FAR, { layer: "ground", value: water });
    expect(Array.isArray(changes) && changes).toHaveLength(20 * 4);
    apply(doc, changes as never);
    expect(groundOfCell(cellAt(doc, near(3, 3))!)).toBe(water);
    expect(GROUND_KINDS[groundOfCell(cellAt(doc, near(3, 5))!)]).toBe("grass");
    // Filling a hex that already has the swatch changes nothing.
    expect(fill(doc, FAR, { layer: "ground", value: water })).toEqual([]);
  });

  it("fill on an unpainted hex: a closed hole takes the swatch, an open region is refused", () => {
    const doc = createMap(ZONE);
    const ring = brushAt(FAR, 3).filter(
      (t) => !brushAt(FAR, 2).some((u) => u.x === t.x && u.y === t.y),
    );
    painted(doc, ring, WALL);
    const hole = fill(doc, FAR, { layer: "terrain", value: FLOOR });
    expect(Array.isArray(hole) && hole).toHaveLength(19);
    // Outside the ring: open, refused, nothing changed.
    expect(fill(doc, near(10, 0), { layer: "terrain", value: FLOOR })).toMatch(/open/);
    // On an empty plane: refused.
    expect(fill(createMap(ZONE), FAR, { layer: "terrain", value: FLOOR })).toMatch(/Nothing/);
  });

  it(`fill takes at most ${FILL_MAX} hexes (a zone of 15 × 15 chunks)`, () => {
    const doc = createMap(ZONE);
    // A wall ring of radius 131 holds 3 · 130 · 131 + 1 = 51,091 hexes: more than the limit.
    const inner = new Set(hexesWithin(FAR, 130).map(keyOf));
    painted(
      doc,
      hexesWithin(FAR, 131).filter((t) => !inner.has(keyOf(t))),
      WALL,
    );
    expect(fill(doc, FAR, { layer: "terrain", value: FLOOR })).toMatch(/at most/);
  });

  it("fill on the outline is bounded by it, far from the origin", () => {
    const doc = createMap(ZONE);
    painted(doc, brushAt(FAR, 3));
    // Outside: a ring of radius 3 around FAR, its inside still inside.
    const ring = brushAt(FAR, 3).filter(
      (t) => !brushAt(FAR, 2).some((u) => u.x === t.x && u.y === t.y),
    );
    apply(doc, erase(doc, ring, true));
    const changes = fill(doc, FAR, { layer: "outline", value: 0 });
    expect(Array.isArray(changes) && changes).toHaveLength(19);
    // On an unpainted hex the outline fill does nothing.
    expect(fill(doc, near(20, 0), { layer: "outline", value: 0 })).toEqual([]);
  });

  it("pick reads a painted hex's terrain and ground, nothing on the void", () => {
    const doc = createMap(ZONE);
    apply(doc, paint(doc, [{ x: -7, y: -8 }], { layer: "ground", value: earth }));
    expect(pick(doc, { x: -7, y: -8 })).toEqual({ terrain: FLOOR, ground: earth });
    expect(pick(doc, { x: 99, y: 8 })).toBeNull();
  });
});

describe("the outline (§4.4)", () => {
  it("from floor: the connected floor region of a hex goes inside, every other painted hex out", () => {
    const doc = createMap(ZONE);
    painted(doc, brushAt(FAR, 4), WALL);
    painted(doc, brushAt(near(-1, 0), 1));
    painted(doc, brushAt(near(40, 0), 2));
    apply(doc, outlineFromFloor(doc, null));
    expect(insideCount(doc)).toBe(19);
    expect(isOutside(cellAt(doc, near(40, 0))!)).toBe(false);
    apply(doc, outlineFromFloor(doc, near(-1, 0)));
    expect(insideCount(doc)).toBe(7);
    expect(isOutside(cellAt(doc, near(40, 0))!)).toBe(true);
    // The map's hexes (what the chunks must hold) are the inside ones.
    expect(mapKeys(doc)).toHaveLength(7);
    expect(outlineFromFloor(createMap(ZONE), null)).toEqual([]);
  });
});
