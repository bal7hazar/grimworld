import { Rectangle } from "pixi.js";
import { HEX_RADIUS, type Point, TILE_WIDTH, pixelToTile, tileToPixel } from "../input/coords";
import type { GroundKind, Tile, ViewTile } from "./view";

/**
 * The ground of a chunk, as data (CLI-03g1, *The method* §1 B, §5): square cells of the pack's
 * terrain, world-aligned on multiples of `TILE_WIDTH`, clipped to the hexes of their ground kind,
 * so that every boundary between two kinds follows hex edges (design/11 I-4). Pure: no PixiJS
 * drawing, no atlas; `shapes.ts` draws it, the tests read it. Presentation only: the ground is
 * never a rule (passability stays `TileKind`'s).
 */

/** A hex grown by this much (art px) so that no seam shows between two hexes (as before). */
export const GROW = 0.5;

/** The ground of a tile; absent is grass (the fixtures written before CLI-03g1). */
export const groundOf = (tile: ViewTile): GroundKind => tile.ground ?? "grass";

/** Whether a tile's ground is walked on: grass and earth are land, water is not. */
export const isLand = (ground: GroundKind): boolean => ground !== "water";

/** A square cell of `TILE_WIDTH`, by its top-left corner in world pixels. */
export interface Cell {
  readonly x: number;
  readonly y: number;
}

/** A part of a hex inside one cell: the polygon the cell's texture fills (flat `x, y, …`). */
export interface Piece {
  readonly cell: Cell;
  readonly points: readonly number[];
}

/** One textured layer: a ground kind, its hexes, the cells covering them, the pieces to fill. */
export interface GroundLayer {
  readonly kind: "water" | "grass";
  readonly hexes: readonly Tile[];
  readonly cells: readonly Cell[];
  readonly pieces: readonly Piece[];
}

/** A land hex's side that faces water: the lip is drawn along it, on the land's side. */
export interface LipEdge {
  readonly tile: Tile;
  /** 0..5: the side between corners `side` and `side + 1` of `hexCorners`. */
  readonly side: number;
}

export interface GroundPlan {
  /** Water first, then grass (under the earth too): only the layers with hexes. */
  readonly layers: readonly GroundLayer[];
  /** The earth's hexes: a soft fill over the grass (the pack has no path cell). */
  readonly earth: readonly Tile[];
  readonly lip: readonly LipEdge[];
  /** The hexes the grid outlines: land only, never over water. */
  readonly grid: readonly Tile[];
  /** The wall hexes that draw a rock: not on water (the water is the obstacle), not covered. */
  readonly rocks: readonly Tile[];
  readonly unrevealed: readonly Tile[];
}

/** The six corners of a pointy-top hex around a centre, `grow` pixels out. */
export function hexCorners(centre: Point, grow = 0): number[] {
  const points: number[] = [];
  for (let k = 0; k < 6; k++) {
    const angle = Math.PI / 6 + (k * Math.PI) / 3;
    points.push(
      centre.x + (HEX_RADIUS + grow) * Math.cos(angle),
      centre.y + (HEX_RADIUS + grow) * Math.sin(angle),
    );
  }
  return points;
}

/**
 * The tile across side `side` of a hex: the one whose centre is a tile's width away along the
 * side's normal. Geometry of the drawing (which side a lip goes on), not a rule of movement.
 */
export function acrossSide(tile: Tile, side: number): Tile {
  const c = tileToPixel(tile);
  const angle = ((side + 1) * Math.PI) / 3;
  return pixelToTile({
    x: c.x + TILE_WIDTH * Math.cos(angle),
    y: c.y + TILE_WIDTH * Math.sin(angle),
  });
}

/** Clips a convex polygon (flat `x, y, …`) to an axis-aligned rectangle (Sutherland–Hodgman). */
export function clipToRect(
  points: readonly number[],
  x0: number,
  y0: number,
  x1: number,
  y1: number,
): number[] {
  type Edge = {
    inside: (x: number, y: number) => boolean;
    cut: (ax: number, ay: number, bx: number, by: number) => [number, number];
  };
  const edges: Edge[] = [
    {
      inside: (x) => x >= x0,
      cut: (ax, ay, bx, by) => [x0, ay + ((by - ay) * (x0 - ax)) / (bx - ax)],
    },
    {
      inside: (x) => x <= x1,
      cut: (ax, ay, bx, by) => [x1, ay + ((by - ay) * (x1 - ax)) / (bx - ax)],
    },
    {
      inside: (_, y) => y >= y0,
      cut: (ax, ay, bx, by) => [ax + ((bx - ax) * (y0 - ay)) / (by - ay), y0],
    },
    {
      inside: (_, y) => y <= y1,
      cut: (ax, ay, bx, by) => [ax + ((bx - ax) * (y1 - ay)) / (by - ay), y1],
    },
  ];
  let out = [...points];
  for (const edge of edges) {
    const input = out;
    out = [];
    const n = input.length / 2;
    for (let i = 0; i < n; i++) {
      const ax = input[(2 * (i + n - 1)) % (2 * n)]!;
      const ay = input[((2 * (i + n - 1)) % (2 * n)) + 1]!;
      const bx = input[2 * i]!;
      const by = input[2 * i + 1]!;
      const aIn = edge.inside(ax, ay);
      const bIn = edge.inside(bx, by);
      if (bIn) {
        if (!aIn) out.push(...edge.cut(ax, ay, bx, by));
        out.push(bx, by);
      } else if (aIn) {
        out.push(...edge.cut(ax, ay, bx, by));
      }
    }
    if (out.length < 6) return [];
  }
  return out;
}

/** The area of a polygon (flat `x, y, …`), positive. */
export function polygonArea(points: readonly number[]): number {
  let twice = 0;
  const n = points.length / 2;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    twice += points[2 * i]! * points[2 * j + 1]! - points[2 * j]! * points[2 * i + 1]!;
  }
  return Math.abs(twice) / 2;
}

/** The hex (grown by `GROW`) cut into one piece per cell it overlaps. */
export function hexPieces(tile: Tile): Piece[] {
  const hex = hexCorners(tileToPixel(tile), GROW);
  const xs = hex.filter((_, i) => i % 2 === 0);
  const ys = hex.filter((_, i) => i % 2 === 1);
  const pieces: Piece[] = [];
  const first = (v: number) => Math.floor(v / TILE_WIDTH);
  for (let cy = first(Math.min(...ys)); cy * TILE_WIDTH < Math.max(...ys); cy++) {
    for (let cx = first(Math.min(...xs)); cx * TILE_WIDTH < Math.max(...xs); cx++) {
      const x = cx * TILE_WIDTH;
      const y = cy * TILE_WIDTH;
      const points = clipToRect(hex, x, y, x + TILE_WIDTH, y + TILE_WIDTH);
      if (points.length >= 6 && polygonArea(points) > 1e-9) pieces.push({ cell: { x, y }, points });
    }
  }
  return pieces;
}

function layer(kind: "water" | "grass", hexes: readonly Tile[]): GroundLayer {
  const pieces = hexes.flatMap(hexPieces);
  const cells = new Map<string, Cell>();
  for (const { cell } of pieces) cells.set(`${cell.x},${cell.y}`, cell);
  return { kind, hexes, cells: [...cells.values()], pieces };
}

export interface PlanOptions {
  /**
   * The ground of any tile, the chunk's neighbours included: a lip is planned toward a water hex
   * of another chunk, or beyond the terrain (the world's void). Null: nothing known there.
   */
  readonly around?: (tile: Tile) => GroundKind | null;
  /** The wall hexes a structure stands on (`"x,y"`): no rock there (CLI-03f). */
  readonly covered?: ReadonlySet<string>;
}

/**
 * The plan of one chunk's ground. An unrevealed tile is drawn as unrevealed whatever its ground;
 * a revealed tile joins the water layer, or the grass layer (earth too, under its soft fill).
 */
export function groundPlan(tiles: readonly ViewTile[], options: PlanOptions = {}): GroundPlan {
  const own = new Map(tiles.map((t) => [`${t.x},${t.y}`, t] as const));
  const covered = options.covered ?? new Set<string>();
  const at = (tile: Tile): GroundKind | null => {
    const mine = own.get(`${tile.x},${tile.y}`);
    if (mine) return mine.kind === "unrevealed" ? null : groundOf(mine);
    return options.around?.(tile) ?? null;
  };
  const water: Tile[] = [];
  const grass: Tile[] = [];
  const earth: Tile[] = [];
  const lip: LipEdge[] = [];
  const grid: Tile[] = [];
  const rocks: Tile[] = [];
  const unrevealed: Tile[] = [];
  for (const tile of tiles) {
    const t = { x: tile.x, y: tile.y };
    if (tile.kind === "unrevealed") {
      unrevealed.push(t);
      continue;
    }
    const ground = groundOf(tile);
    if (ground === "water") {
      water.push(t);
      continue;
    }
    grass.push(t);
    if (ground === "earth") earth.push(t);
    grid.push(t);
    for (let side = 0; side < 6; side++) {
      if (at(acrossSide(t, side)) === "water") lip.push({ tile: t, side });
    }
    if (tile.kind === "wall" && !covered.has(`${t.x},${t.y}`)) rocks.push(t);
  }
  const layers = [
    ...(water.length > 0 ? [layer("water", water)] : []),
    ...(grass.length > 0 ? [layer("grass", grass)] : []),
  ];
  return { layers, earth, lip, grid, rocks, unrevealed };
}

/**
 * The miter of a hex's stroke at its 120° corners: PixiJS pads a stroke's bounds by half its width
 * times this (`getMaxMiterRatio`).
 */
const MITER = 1 / Math.sin(Math.PI / 3);

/**
 * A chunk's baked frame, from its tiles' positions only, so that the ground never changes the
 * textures' size or count (*The method* §2): what `getLocalBounds` gave for the chunk's drawing
 * before CLI-03g1 (each hex filled grown by `GROW`, a revealed hex outlined by a stroke 1 wide),
 * floored and ceiled to whole art pixels.
 */
export function chunkFrame(tiles: readonly ViewTile[]): Rectangle {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  const add = (points: readonly number[], pad: number) => {
    for (let i = 0; i < points.length; i += 2) {
      minX = Math.min(minX, points[i]! - pad);
      maxX = Math.max(maxX, points[i]! + pad);
      minY = Math.min(minY, points[i + 1]! - pad);
      maxY = Math.max(maxY, points[i + 1]! + pad);
    }
  };
  for (const tile of tiles) {
    const centre = tileToPixel(tile);
    add(hexCorners(centre, GROW), 0);
    if (tile.kind !== "unrevealed") add(hexCorners(centre), 0.5 * MITER);
  }
  if (minX === Infinity) return new Rectangle(0, 0, 0, 0);
  const x = Math.floor(minX);
  const y = Math.floor(minY);
  return new Rectangle(x, y, Math.ceil(maxX) - x, Math.ceil(maxY) - y);
}
