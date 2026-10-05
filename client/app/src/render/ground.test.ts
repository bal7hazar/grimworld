import { Graphics } from "pixi.js";
import { describe, expect, it } from "vitest";
import { TILE_WIDTH, tileToPixel } from "../input/coords";
import { FIXTURES } from "../sandbox/fixtures";
import { HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { hubWorld } from "../sandbox/fixtures/hubWorld";
import { initialState, toView } from "../sandbox/wiring";
import {
  FOAM_REACH,
  FOAM_SIZE,
  GROW,
  type GroundPlan,
  acrossSide,
  chunkFrame,
  clipToRect,
  foamOrigin,
  groundPlan,
  hexCorners,
  hexPieces,
  hexesWithin,
  polygonArea,
  voidFoam,
  voidHole,
  waterFoam,
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

describe("the foam (CLI-03g2)", () => {
  /** An island: land in a hex disc of radius 3 around (6, 6), water around it, in 13 × 13. */
  const disc = new Set(hexesWithin({ x: 6, y: 6 }, 3).map(key));
  const island = (t: Tile): GroundKind =>
    disc.has(key(t)) ? (t.y === 6 ? "earth" : "grass") : "water";
  const tiles = block(0, 12, 0, 12, island);
  const inBlock = new Map(tiles.map((t) => [key(t), t] as const));
  const coastal = tiles.filter(
    (t) =>
      island(t) !== "water" &&
      [0, 1, 2, 3, 4, 5].some((side) => {
        const next = inBlock.get(key(acrossSide(t, side)));
        return next !== undefined && island(next) === "water";
      }),
  );
  const pieceKey = (p: GroundPlan["foam"][number]) => `${key(p.source)}|${p.points.join()}`;

  it("the hexes within n steps: 1, 7, 19, 37", () => {
    expect([0, 1, 2, 3].map((n) => hexesWithin({ x: 4, y: 5 }, n).length)).toEqual([1, 7, 19, 37]);
  });

  it("one foam still under every land hex that touches water, and under no other", () => {
    const plan = groundPlan(tiles);
    expect(coastal.length).toBe(18);
    const sources = new Set(plan.foam.map((p) => key(p.source)));
    expect([...sources].sort()).toEqual(coastal.map(key).sort());
    for (const piece of plan.foam) {
      // The cell centred under its land hex, on whole art pixels.
      expect(piece.origin).toEqual(foamOrigin(piece.source));
      expect(Number.isInteger(piece.origin.x) && Number.isInteger(piece.origin.y)).toBe(true);
      const c = tileToPixel(piece.source);
      expect(Math.abs(piece.origin.x + FOAM_SIZE / 2 - c.x)).toBeLessThanOrEqual(0.5);
      expect(Math.abs(piece.origin.y + FOAM_SIZE / 2 - c.y)).toBeLessThanOrEqual(0.5);
      for (let i = 0; i < piece.points.length; i += 2) {
        expect(piece.points[i]!).toBeGreaterThanOrEqual(piece.origin.x - 1e-9);
        expect(piece.points[i]!).toBeLessThanOrEqual(piece.origin.x + FOAM_SIZE + 1e-9);
        expect(piece.points[i + 1]!).toBeGreaterThanOrEqual(piece.origin.y - 1e-9);
        expect(piece.points[i + 1]!).toBeLessThanOrEqual(piece.origin.y + FOAM_SIZE + 1e-9);
      }
    }
  });

  it("over water only, each piece inside one water hex: the cell's whole part over water", () => {
    const plan = groundPlan(tiles);
    const water = tiles.filter((t) => island(t) === "water");
    for (const source of coastal) {
      const o = foamOrigin(source);
      const planned = plan.foam
        .filter((p) => key(p.source) === key(source))
        .reduce((sum, p) => sum + polygonArea(p.points), 0);
      // What the cell covers over the block's water, hex by hex, is what is planned.
      const expected = water.reduce((sum, w) => {
        const hex = hexCorners(tileToPixel(w));
        const part = clipToRect(hex, o.x, o.y, o.x + FOAM_SIZE, o.y + FOAM_SIZE);
        return sum + (part.length >= 6 ? polygonArea(part) : 0);
      }, 0);
      expect(planned).toBeCloseTo(expected, 6);
      expect(planned).toBeGreaterThan(0);
    }
    for (const piece of plan.foam) {
      // Within FOAM_REACH steps of its land hex, every corner inside one water hex.
      const near = hexesWithin(piece.source, FOAM_REACH).filter((t) => island(t) === "water");
      const holder = near.filter((w) => insideConvex(piece.points, hexCorners(tileToPixel(w))));
      expect(holder).toHaveLength(1);
    }
  });

  it("the same pieces when the island is cut into chunks, through `around`", () => {
    const whole = groundPlan(tiles).foam.map(pieceKey).sort();
    const around = (t: Tile) => {
      const tile = inBlock.get(key(t));
      return tile ? island(tile) : null;
    };
    const cut = [
      tiles.filter((t) => t.x < 6),
      tiles.filter((t) => t.x >= 6 && t.y < 5),
      tiles.filter((t) => t.x >= 6 && t.y >= 5),
    ].flatMap((chunk) => groundPlan(chunk, { around }).foam.map(pieceKey));
    expect(cut.sort()).toEqual(whole);
  });

  it("no foam from an unrevealed land hex, none on an unrevealed water hex, none on grass only", () => {
    expect(groundPlan(block(0, 4, 0, 4)).foam).toEqual([]);
    const hidden = tiles.map((t) => (t.x >= 6 ? { ...t, kind: "unrevealed" as const } : t));
    const plan = groundPlan(hidden);
    expect(plan.foam.length).toBeGreaterThan(0);
    for (const piece of plan.foam) {
      expect(piece.source.x).toBeLessThan(6);
      const holder = tiles.filter(
        (w) => w.x < 6 && insideConvex(piece.points, hexCorners(tileToPixel(w))),
      );
      expect(holder.length).toBeGreaterThan(0);
    }
  });
});

describe("the foam over the void (CLI-03g2)", () => {
  const ground = (t: Tile): GroundKind => (t.x === 4 ? "water" : t.y === 2 ? "earth" : "grass");
  const kind = (t: Tile): TileKind => (t.y === 0 ? "unrevealed" : t.x === 4 ? "wall" : "floor");
  const tiles = block(0, 4, 0, 4, ground, kind);
  const present = new Set(tiles.map(key));

  it("none unless the void is water", () => {
    expect(voidFoam(tiles, undefined)).toEqual([]);
    expect(voidFoam(tiles, "grass")).toEqual([]);
  });

  it("from every revealed land hex on the border, over the void's hexes only", () => {
    const pieces = voidFoam(tiles, "water");
    const border = tiles.filter(
      (t) =>
        t.kind !== "unrevealed" &&
        t.ground !== "water" &&
        [0, 1, 2, 3, 4, 5].some((side) => !present.has(key(acrossSide(t, side)))),
    );
    expect(border.length).toBeGreaterThan(0);
    const sources = new Set(pieces.map((p) => key(p.source)));
    for (const t of border) expect(sources.has(key(t))).toBe(true);
    for (const piece of pieces) {
      expect(piece.origin).toEqual(foamOrigin(piece.source));
      const holders = hexesWithin(piece.source, FOAM_REACH).filter((h) =>
        insideConvex(piece.points, hexCorners(tileToPixel(h))),
      );
      expect(holders).toHaveLength(1);
      expect(present.has(key(holders[0]!))).toBe(false);
    }
  });

  it("with the chunks' foam, the whole cell's part over water: the void as water hexes", () => {
    // The same block inside a ring of two water hexes: its foam over the ring, from the block's
    // land, equals the void's foam.
    const ring = block(
      -2,
      6,
      -2,
      6,
      (t) => (present.has(key(t)) ? ground(t) : "water"),
      (t) => (present.has(key(t)) ? kind(t) : "wall"),
    );
    const fromRing = groundPlan(ring, { around: () => "water" })
      .foam.filter((p) => present.has(key(p.source)))
      .filter((p) => {
        const holder = hexesWithin(p.source, FOAM_REACH).find((h) =>
          insideConvex(p.points, hexCorners(tileToPixel(h))),
        )!;
        return !present.has(key(holder));
      });
    const k = (p: GroundPlan["foam"][number]) => `${key(p.source)}|${p.points.join()}`;
    expect(voidFoam(tiles, "water").map(k).sort()).toEqual(fromRing.map(k).sort());
  });
});

describe("the foam over a concave terrain's inner void (CLI-03h)", () => {
  // A block of 15 × 15 grass with a notch of void cut from its South edge (y = 0) to its middle:
  // the notch is inside the tiles' box, where the void's bands leave the background.
  const inNotch = (t: Tile) => t.x >= 5 && t.x <= 9 && t.y <= 8;
  const tiles = block(0, 14, 0, 14).filter((t) => !inNotch(t));
  const present = new Set(tiles.map(key));
  const hole = voidHole(tiles)!;
  const underBands = (t: Tile) => {
    const c = tileToPixel(t);
    const xs = hexCorners(c).filter((_, i) => i % 2 === 0);
    const ys = hexCorners(c).filter((_, i) => i % 2 === 1);
    return (
      Math.max(...xs) <= hole.x0 ||
      Math.min(...xs) >= hole.x1 ||
      Math.max(...ys) <= hole.y0 ||
      Math.min(...ys) >= hole.y1
    );
  };

  it("no foam over a void hex the bands do not cover; the foam outside stays", () => {
    // The notch's deep hexes are void, next to land: without the rule they would get foam.
    const deep = { x: 7, y: 7 };
    expect(present.has(key(deep))).toBe(false);
    expect(underBands(deep)).toBe(false);
    expect(hexesWithin(deep, FOAM_REACH).some((t) => present.has(key(t)))).toBe(true);
    const pieces = voidFoam(tiles, "water");
    expect(pieces.length).toBeGreaterThan(0);
    for (const piece of pieces) expect(underBands(piece.over)).toBe(true);
    expect(pieces.some((p) => key(p.over) === key(deep))).toBe(false);
    // Away from the notch, the outer void keeps the foam the block without a notch has.
    const away = (p: GroundPlan["foam"][number]) => p.over.y > 10 || p.over.x < 3 || p.over.x > 11;
    const k = (p: GroundPlan["foam"][number]) =>
      `${key(p.source)}>${key(p.over)}|${p.points.join()}`;
    const whole = voidFoam(block(0, 14, 0, 14), "water");
    expect(pieces.filter(away).map(k).sort()).toEqual(whole.filter(away).map(k).sort());
    expect(pieces.filter(away).length).toBeGreaterThan(0);
  });
});

/** Whether every point of a polygon lies in a convex polygon (both flat `x, y, …`), edges included. */
function insideConvex(points: readonly number[], hull: readonly number[]): boolean {
  const n = hull.length / 2;
  for (let i = 0; i < points.length; i += 2) {
    for (let k = 0; k < n; k++) {
      const ax = hull[2 * k]!;
      const ay = hull[2 * k + 1]!;
      const bx = hull[(2 * k + 2) % (2 * n)]!;
      const by = hull[((2 * k + 2) % (2 * n)) + 1]!;
      if ((bx - ax) * (points[i + 1]! - ay) - (by - ay) * (points[i]! - ax) < -1e-6) return false;
    }
  }
  return true;
}

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

describe("a coast at the frontier of what was seen (CLI-03n follow-up)", () => {
  // Land West of x = 5, water from there: the coast between columns 4 and 5.
  const tiles = block(0, 9, 0, 9, (t) => (t.x >= 5 ? "water" : "grass"));
  const lipsOf = (plan: GroundPlan) =>
    new Set(plan.lip.map((l) => key(acrossSide(l.tile, l.side))));

  it("no lip toward a water hex never seen; the lip toward seen water stays", () => {
    const seen = groundPlan(tiles);
    // Rows 0..4 of the water column 5 never seen; rows 5..9 seen.
    const hidden = new Set(block(5, 5, 0, 4).map(key));
    const plan = groundPlan(tiles, { hidden });
    const toward = lipsOf(plan);
    for (const k of hidden) expect(toward.has(k)).toBe(false);
    // Where both hexes were seen, the coast is as before: the same lips.
    const kept = [...lipsOf(seen)].filter((k) => !hidden.has(k));
    expect(kept.length).toBeGreaterThan(0);
    for (const k of kept) expect(toward.has(k)).toBe(true);
    expect(plan.lip.filter((l) => !hidden.has(key(acrossSide(l.tile, l.side))))).toEqual(
      seen.lip.filter((l) => !hidden.has(key(acrossSide(l.tile, l.side)))),
    );
  });

  it("no foam from a land hex never seen, none over a water hex never seen", () => {
    // The coast's land column 4 never seen in rows 0..4; water column 5 never seen in rows 7..9.
    const hidden = new Set([...block(4, 4, 0, 4), ...block(5, 5, 7, 9)].map(key));
    for (const foam of [groundPlan(tiles, { hidden }).foam, waterFoam(tiles, { hidden })]) {
      expect(foam.length).toBeGreaterThan(0);
      for (const piece of foam) {
        expect(hidden.has(key(piece.source))).toBe(false);
        expect(hidden.has(key(piece.over))).toBe(false);
      }
    }
    // A land hex that touches seen water only through a hex never seen is no source either.
    const behind = new Set(block(5, 5, 0, 9).map(key));
    const sources = new Set(groundPlan(tiles, { hidden: behind }).foam.map((p) => key(p.source)));
    for (const k of block(4, 4, 0, 9).map(key)) expect(sources.has(k)).toBe(false);
    // With everything seen, column 4 is the coast and makes foam.
    const all = new Set(groundPlan(tiles).foam.map((p) => key(p.source)));
    expect(block(4, 4, 0, 9).every((t) => all.has(key(t)))).toBe(true);
  });
});
