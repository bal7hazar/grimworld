import { Graphics } from "pixi.js";
import { describe, expect, it } from "vitest";
import { TILE_WIDTH, tileToPixel } from "../input/coords";
import { FIXTURES } from "../sandbox/fixtures";
import { HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { hubWorld } from "../sandbox/fixtures/hubWorld";
import { initialState, toView } from "../sandbox/wiring";
import {
  GROW,
  acrossSide,
  chunkFrame,
  clipToRect,
  groundPlan,
  hexCorners,
  hexPieces,
  polygonArea,
} from "./ground";
import { BAKE_CHUNK } from "./renderer";
import type { GroundKind, Tile, TileKind, ViewTile } from "./view";

const key = (t: Tile) => `${t.x},${t.y}`;

/** A block of tiles, `x0..x1` × `y0..y1`, its ground and kind given per tile. */
function block(
  x0: number,
  x1: number,
  y0: number,
  y1: number,
  ground: (t: Tile) => GroundKind = () => "grass",
  kind: (t: Tile) => TileKind = (t) => (ground(t) === "water" ? "wall" : "floor"),
): ViewTile[] {
  const tiles: ViewTile[] = [];
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++)
      tiles.push({ x, y, kind: kind({ x, y }), ground: ground({ x, y }) });
  }
  return tiles;
}

describe("the geometry under the plan", () => {
  it("the tile across each side is one of the six at a tile's width, each once", () => {
    for (const tile of [
      { x: 4, y: 4 },
      { x: 4, y: 5 },
    ]) {
      const c = tileToPixel(tile);
      const seen = new Set<string>();
      for (let side = 0; side < 6; side++) {
        const next = acrossSide(tile, side);
        const p = tileToPixel(next);
        expect(Math.hypot(p.x - c.x, p.y - c.y)).toBeCloseTo(TILE_WIDTH, 9);
        // The side's midpoint lies halfway between the two centres.
        const corners = hexCorners(c);
        const m = (side + 1) % 6;
        const mid = {
          x: (corners[2 * side]! + corners[2 * m]!) / 2,
          y: (corners[2 * side + 1]! + corners[2 * m + 1]!) / 2,
        };
        expect(mid.x).toBeCloseTo((c.x + p.x) / 2, 9);
        expect(mid.y).toBeCloseTo((c.y + p.y) / 2, 9);
        seen.add(key(next));
      }
      expect(seen.size).toBe(6);
    }
  });

  it("clips a square to a rectangle, and gives nothing outside it", () => {
    const square = [0, 0, 10, 0, 10, 10, 0, 10];
    expect(polygonArea(clipToRect(square, 5, 5, 20, 20))).toBeCloseTo(25, 9);
    expect(clipToRect(square, 20, 20, 30, 30)).toEqual([]);
  });

  it("a hex's pieces tile it exactly: their areas sum to the hex's, each inside its cell", () => {
    for (const tile of [
      { x: 0, y: 0 },
      { x: 3, y: 1 },
      { x: -2, y: 7 },
    ]) {
      const pieces = hexPieces(tile);
      const area = pieces.reduce((sum, p) => sum + polygonArea(p.points), 0);
      expect(area).toBeCloseTo(polygonArea(hexCorners(tileToPixel(tile), GROW)), 6);
      for (const { cell, points } of pieces) {
        expect(Math.abs(cell.x % TILE_WIDTH)).toBe(0);
        expect(Math.abs(cell.y % TILE_WIDTH)).toBe(0);
        for (let i = 0; i < points.length; i += 2) {
          expect(points[i]!).toBeGreaterThanOrEqual(cell.x - 1e-9);
          expect(points[i]!).toBeLessThanOrEqual(cell.x + TILE_WIDTH + 1e-9);
          expect(points[i + 1]!).toBeGreaterThanOrEqual(cell.y - 1e-9);
          expect(points[i + 1]!).toBeLessThanOrEqual(cell.y + TILE_WIDTH + 1e-9);
        }
      }
    }
  });
});

describe("groundPlan (AC-3)", () => {
  it("a chunk of grass only: one layer, no lip, the grid on every hex", () => {
    const tiles = block(0, 4, 0, 4);
    const plan = groundPlan(tiles);
    expect(plan.layers.map((l) => l.kind)).toEqual(["grass"]);
    expect(plan.lip).toEqual([]);
    expect(plan.grid).toHaveLength(tiles.length);
    expect(plan.earth).toEqual([]);
  });

  it("each layer's cells cover every hex of the layer, on multiples of TILE_WIDTH", () => {
    const tiles = block(0, 6, 0, 6, (t) =>
      t.x + t.y < 5 ? "water" : t.x === 4 ? "earth" : "grass",
    );
    const plan = groundPlan(tiles);
    expect(plan.layers.map((l) => l.kind)).toEqual(["water", "grass"]);
    for (const layer of plan.layers) {
      const cells = new Set(layer.cells.map((c) => `${c.x},${c.y}`));
      for (const cell of layer.cells) {
        expect(Math.abs(cell.x % TILE_WIDTH)).toBe(0);
        expect(Math.abs(cell.y % TILE_WIDTH)).toBe(0);
      }
      for (const hex of layer.hexes) {
        const pieces = layer.pieces.filter((p) =>
          hexPieces(hex).some(
            (q) =>
              q.cell.x === p.cell.x && q.cell.y === p.cell.y && q.points.join() === p.points.join(),
          ),
        );
        const area = pieces.reduce((sum, p) => sum + polygonArea(p.points), 0);
        expect(area).toBeCloseTo(polygonArea(hexCorners(tileToPixel(hex), GROW)), 6);
        for (const p of pieces) expect(cells.has(`${p.cell.x},${p.cell.y}`)).toBe(true);
      }
    }
    // Earth is grass underneath, plus its soft fill.
    const grass = new Set(plan.layers[1]!.hexes.map(key));
    for (const tile of plan.earth) expect(grass.has(key(tile))).toBe(true);
  });

  it("the lip's edges are exactly the land–water hex edges", () => {
    const ground = (t: Tile): GroundKind => (t.x >= 3 ? "water" : t.y === 2 ? "earth" : "grass");
    const tiles = block(0, 5, 0, 5, ground);
    const plan = groundPlan(tiles);
    const inBlock = new Set(tiles.map(key));
    const expected: string[] = [];
    for (const tile of tiles) {
      if (ground(tile) === "water") continue;
      for (let side = 0; side < 6; side++) {
        const next = acrossSide(tile, side);
        if (inBlock.has(key(next)) && ground(next) === "water")
          expected.push(`${key(tile)}/${side}`);
      }
    }
    expect(expected.length).toBeGreaterThan(0);
    expect(plan.lip.map((e) => `${key(e.tile)}/${e.side}`).sort()).toEqual(expected.sort());
  });

  it("looks across the chunk's edge and into the void through `around`", () => {
    const tiles = block(0, 2, 0, 2);
    expect(groundPlan(tiles).lip).toEqual([]);
    const plan = groundPlan(tiles, { around: () => "water" });
    // Every side of the block's border hexes that faces outside.
    const inBlock = new Set(tiles.map(key));
    const outward = tiles.flatMap((t) =>
      [0, 1, 2, 3, 4, 5].filter((side) => !inBlock.has(key(acrossSide(t, side)))),
    );
    expect(plan.lip).toHaveLength(outward.length);
  });

  it("no grid over water; a wall on water plans no rock; a covered wall none either", () => {
    const ground = (t: Tile): GroundKind => (t.x === 0 ? "water" : "grass");
    const kind = (t: Tile): TileKind => (t.x === 0 || t.y === 1 ? "wall" : "floor");
    const tiles = block(0, 3, 0, 2, ground, kind);
    const plan = groundPlan(tiles, { covered: new Set(["2,1"]) });
    expect(plan.grid.some((t) => t.x === 0)).toBe(false);
    expect(plan.grid).toHaveLength(9);
    expect(plan.rocks.map(key).sort()).toEqual(["1,1", "3,1"]);
  });

  it("an unrevealed hex draws as unrevealed whatever its ground: no layer, no lip toward it", () => {
    const tiles = block(
      0,
      2,
      0,
      2,
      (t) => (t.x === 2 ? "water" : "grass"),
      (t) => (t.x === 2 ? "unrevealed" : "floor"),
    );
    const plan = groundPlan(tiles);
    expect(plan.unrevealed).toHaveLength(3);
    expect(plan.layers.map((l) => l.kind)).toEqual(["grass"]);
    expect(plan.lip).toEqual([]);
  });
});

/** Every chunk of every room and both hubs, as the renderer groups them. */
function chunksOfEveryWorld(): ViewTile[][] {
  const worlds = [
    ...Object.values(FIXTURES),
    ...[...HUB_VIEWS.values()].map((view) => hubWorld(view, view.arrival)),
  ];
  const chunks: ViewTile[][] = [];
  for (const world of worlds) {
    const groups = new Map<string, ViewTile[]>();
    for (const tile of toView(initialState(world)).tiles) {
      const id = `${Math.floor(tile.x / BAKE_CHUNK)},${Math.floor(tile.y / BAKE_CHUNK)}`;
      groups.set(id, [...(groups.get(id) ?? []), tile]);
    }
    chunks.push(...groups.values());
  }
  return chunks;
}

describe("chunkFrame (AC-4: the baked textures keep main's size)", () => {
  it("equals the bounds main's drawing of the chunk gave, for every chunk of every world", () => {
    const chunks = chunksOfEveryWorld();
    expect(chunks.length).toBeGreaterThan(10);
    for (const tiles of chunks) {
      // Main's drawTerrain, before CLI-03g1: each hex filled grown by half a pixel, then each
      // revealed hex outlined, each unrevealed hex's inner edge; rocks inside the hexes.
      const g = new Graphics();
      for (const tile of tiles) g.poly(hexCorners(tileToPixel(tile), 0.5)).fill(0);
      for (const tile of tiles) {
        const centre = tileToPixel(tile);
        if (tile.kind === "unrevealed")
          g.poly(hexCorners(centre, -1)).stroke({ width: 1, color: 0 });
        else g.poly(hexCorners(centre)).stroke({ width: 1, color: 0, alpha: 0.35 });
      }
      const b = g.getLocalBounds();
      const frame = chunkFrame(tiles);
      expect([frame.x, frame.y, frame.width, frame.height]).toEqual([
        Math.floor(b.minX),
        Math.floor(b.minY),
        Math.ceil(b.maxX) - Math.floor(b.minX),
        Math.ceil(b.maxY) - Math.floor(b.minY),
      ]);
      g.destroy();
    }
  });
});
