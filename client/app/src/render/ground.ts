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

/** The foam's cell side: the pack's `Water Foam.png` cell, three tiles wide (CLI-03g2). */
export const FOAM_SIZE = 192;

/**
 * How many hex steps a foam cell centred under a land hex reaches: its square, `FOAM_SIZE` wide,
 * overlaps the hexes two steps away and only touches, at most, those three steps away.
 */
export const FOAM_REACH = 2;

/**
 * A part of a water hex under the foam of one land hex that touches water (CLI-03g2, *The method*
 * §4): the foam cell is centred under the land hex and drawn after the water, before the grass;
 * the grass covers its inner part, so only its parts over water are planned, each clipped to its
 * water hex, so a chunk draws only on its own hexes.
 */
export interface FoamPiece {
  /** The land hex the foam is centred under. */
  readonly source: Tile;
  /** The foam cell's top-left corner, on whole art pixels. */
  readonly origin: Cell;
  /** The water hex the piece lies in. */
  readonly over: Tile;
  readonly points: readonly number[];
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
  /** The foam over the water hexes, after the water layer, before the grass. */
  readonly foam: readonly FoamPiece[];
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

/** The top-left corner of the foam cell centred under a hex, rounded to whole art pixels. */
export function foamOrigin(tile: Tile): Cell {
  const c = tileToPixel(tile);
  return { x: Math.round(c.x - FOAM_SIZE / 2), y: Math.round(c.y - FOAM_SIZE / 2) };
}

/** The hexes within `steps` hex steps of a tile, the tile included, each once. */
export function hexesWithin(tile: Tile, steps: number): Tile[] {
  const seen = new Map<string, Tile>([[`${tile.x},${tile.y}`, tile]]);
  let edge = [tile];
  for (let step = 0; step < steps; step++) {
    const next: Tile[] = [];
    for (const t of edge) {
      for (let side = 0; side < 6; side++) {
        const n = acrossSide(t, side);
        const key = `${n.x},${n.y}`;
        if (!seen.has(key)) {
          seen.set(key, n);
          next.push(n);
        }
      }
    }
    edge = next;
  }
  return [...seen.values()];
}

/**
 * The foam over some water hexes: under every land hex that touches water (`at`), seen from each of
 * the given hexes it reaches, clipped to that hex.
 */
function foamOver(targets: readonly Tile[], at: (tile: Tile) => GroundKind | null): FoamPiece[] {
  const coastal = new Map<string, boolean>();
  const isCoastal = (tile: Tile): boolean => {
    const k = `${tile.x},${tile.y}`;
    let known = coastal.get(k);
    if (known === undefined) {
      const ground = at(tile);
      known =
        ground !== null &&
        isLand(ground) &&
        [0, 1, 2, 3, 4, 5].some((side) => at(acrossSide(tile, side)) === "water");
      coastal.set(k, known);
    }
    return known;
  };
  const foam: FoamPiece[] = [];
  for (const tile of targets) {
    const hex = hexCorners(tileToPixel(tile));
    for (const source of hexesWithin(tile, FOAM_REACH)) {
      if (!isCoastal(source)) continue;
      const origin = foamOrigin(source);
      const points = clipToRect(
        hex,
        origin.x,
        origin.y,
        origin.x + FOAM_SIZE,
        origin.y + FOAM_SIZE,
      );
      if (points.length >= 6 && polygonArea(points) > 1e-9)
        foam.push({ source, origin, over: tile, points });
    }
  }
  return foam;
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
  const foam = foamOver(water, at);
  const layers = [
    ...(water.length > 0 ? [layer("water", water)] : []),
    ...(grass.length > 0 ? [layer("grass", grass)] : []),
  ];
  return { layers, earth, foam, lip, grid, rocks, unrevealed };
}

/**
 * The foam over the void beyond the terrain (CLI-03g2), when the void is water: the pieces of every
 * coastal land hex's foam over the hexes outside the terrain, within `FOAM_REACH` of it. The chunks
 * bake the foam over the terrain's own water; the void is not baked (the renderer's bands), so
 * these pieces are drawn over the bands, under the chunks, clipped to the void's hexes so that
 * only the foam that shows is filled.
 */
export function voidFoam(tiles: readonly ViewTile[], beyond: GroundKind | undefined): FoamPiece[] {
  if (beyond !== "water") return [];
  const own = new Map<string, ViewTile>(tiles.map((t) => [`${t.x},${t.y}`, t] as const));
  const at = (tile: Tile): GroundKind | null => {
    const mine = own.get(`${tile.x},${tile.y}`);
    if (!mine) return beyond;
    return mine.kind === "unrevealed" ? null : groundOf(mine);
  };
  // The void's hexes near the terrain: within FOAM_REACH of a tile on its border.
  const targets = new Map<string, Tile>();
  for (const tile of tiles) {
    const sides = [0, 1, 2, 3, 4, 5].map((side) => acrossSide(tile, side));
    if (sides.every((t) => own.has(`${t.x},${t.y}`))) continue;
    for (const hex of hexesWithin(tile, FOAM_REACH)) {
      const k = `${hex.x},${hex.y}`;
      if (!own.has(k)) targets.set(k, hex);
    }
  }
  return foamOver([...targets.values()], at);
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
