import type { GroundKind, Tile, TileKind, ViewActor, ViewStructure } from "../render/view";

/** Chunks are 15 × 15 tiles (ADR-0006). */
export const CHUNK = 15;

/** The terrain of a sandbox location: a rectangle of whole chunks, `kinds[y * width + x]`. */
export interface Terrain {
  readonly width: number;
  readonly height: number;
  readonly kinds: readonly TileKind[];
  /** What each tile of an unrevealed chunk becomes when it is revealed (fixture data). */
  readonly hidden: readonly TileKind[];
  /**
   * Each tile's ground, indexed as `kinds` (CLI-03g1): presentation only, never read by a rule.
   * Absent: every tile is grass. A water tile is `wall`, an earth tile `floor`.
   */
  readonly ground?: readonly GroundKind[];
}

/** What a fixture holds: the state the chain would hold, written by hand. */
export interface SandboxWorld {
  readonly name: string;
  readonly description: string;
  readonly terrain: Terrain;
  readonly actors: readonly ViewActor[];
  readonly adventurerId: number;
  /** A planned path to draw, if the fixture shows one. */
  readonly path: readonly Tile[];
  /**
   * An exploration zone (the default), or a hub lived like one (CLI-03f, D-202): the wiring gives a
   * hub none of the instance's stand-ins (sight, reveal, stops, the window, ticks, arcs).
   */
  readonly kind?: "zone" | "hub";
  /** Buildings and props on wall hexes (a hub's); none by default. */
  readonly structures?: readonly ViewStructure[];
  /** The ground beyond the terrain's rectangle (CLI-03g1): water around an island; none by default. */
  readonly void?: GroundKind;
}

export function inBounds(terrain: Terrain, tile: Tile): boolean {
  return tile.x >= 0 && tile.y >= 0 && tile.x < terrain.width && tile.y < terrain.height;
}

/** Outside the location is wall (D-134). */
export function kindAt(terrain: Terrain, tile: Tile): TileKind {
  if (!inBounds(terrain, tile)) return "wall";
  return terrain.kinds[tile.y * terrain.width + tile.x] ?? "wall";
}

export function sameTile(a: Tile, b: Tile): boolean {
  return a.x === b.x && a.y === b.y;
}
