import type { Tile, TileKind, ViewActor } from "../render/view";

/** Chunks are 15 × 15 tiles (ADR-0006). */
export const CHUNK = 15;

/** The terrain of a sandbox location: a rectangle of whole chunks, `kinds[y * width + x]`. */
export interface Terrain {
  readonly width: number;
  readonly height: number;
  readonly kinds: readonly TileKind[];
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
