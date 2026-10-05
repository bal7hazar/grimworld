import { acrossSide, hexesWithin } from "../render/ground";
import type { GroundKind, Tile } from "../render/view";

/**
 * The map editor's document (CLI-09a, brief `docs/briefs/CLI-09-map-editor.md` §4): a zone, a town
 * or an outpost of whole chunks, one value per hex in each layer. A tool's document, not a rule of
 * the game: the editor reproduces checks, it decides none (mandate §6).
 *
 * Coordinates are the chain's and the client's global `(x, y)`: `x` grows West, `y` North, odd-r
 * rows (`input/coords.ts`). A hex's index in a layer is `y * width + x`, as `Terrain.kinds`.
 */

/** Chunks are 15 × 15 tiles (ADR-0006). */
export const CHUNK = 15;

export type MapKind = "zone" | "town" | "outpost";
export const MAP_KINDS: readonly MapKind[] = ["zone", "town", "outpost"];

/** `location.cairo:22-27`. */
export type Biome = "meadow" | "forest" | "cave" | "ruin";
export const BIOMES: readonly Biome[] = ["meadow", "forest", "cave", "ruin"];

/** The terrain a new map starts as, and what Erase puts back. */
export type StartFill = "wall" | "floor";

/** The walkable plane, the one bit the chain holds per tile (ENG-08 ruling 1, D-215). */
export const FLOOR = 0;
export const WALL = 1;
export type TerrainValue = typeof FLOOR | typeof WALL;

/** The ground, a client-only layer (D-215), in the order `GROUND_KINDS` gives. */
export const GROUND_KINDS: readonly GroundKind[] = ["grass", "earth", "water"];

/** Name bound: a short string of `REGION` (brief §2.2). */
export const NAME_MAX = 15;
/** Size bounds in chunks, per side (brief §2.2, E-1). */
export const SIZE_MAX: Readonly<Record<MapKind, number>> = { zone: 15, town: 4, outpost: 4 };

/** What the map is, beside its hexes. Numbers the editor does not read (brief §4.2). */
export interface MapMeta {
  readonly kind: MapKind;
  readonly name: string;
  readonly location: number;
  /** In chunks. */
  readonly width: number;
  readonly height: number;
  /** A zone's; null for a town or an outpost. */
  readonly biome: Biome | null;
  readonly start: StartFill;
  readonly levelMin: number;
  readonly levelMax: number;
  readonly rank: number;
  readonly spawnTable: number;
}

/**
 * The document. The layers are mutated in place by the edits (`apply`), which the history records
 * as differences; everything else is replaced whole.
 */
export interface MapDocument {
  meta: MapMeta;
  /** `FLOOR` or `WALL` per hex. */
  readonly terrain: Uint8Array;
  /** An index into `GROUND_KINDS` per hex. */
  readonly ground: Uint8Array;
  /** 1 inside the zone's outline (brief §4.4); null for a town or an outpost (no outline). */
  readonly outline: Uint8Array | null;
  /**
   * The obstacle looks pinned on wall hexes, by hex index: a still's name (brief §4.1). A hex not
   * here is `auto` (the renderer's choice by `hexHash`). CLI-09a writes none; the inspector
   * (CLI-09b) pins them.
   */
  readonly obstacles: Map<number, string>;
}

/** The size in tiles. */
export function tilesWide(meta: Pick<MapMeta, "width">): number {
  return meta.width * CHUNK;
}

export function tilesHigh(meta: Pick<MapMeta, "height">): number {
  return meta.height * CHUNK;
}

/** The ground a new hex has and Erase puts back: grass for every biome until a second one is drawn. */
export function defaultGround(): number {
  return GROUND_KINDS.indexOf("grass");
}

export interface NewMap {
  readonly kind: MapKind;
  readonly name: string;
  readonly location: number;
  readonly width: number;
  readonly height: number;
  readonly biome: Biome;
  readonly start: StartFill;
}

/** Why a new map's fields are refused, or null. */
export function newMapProblem(fields: NewMap): string | null {
  const max = SIZE_MAX[fields.kind];
  const name = fields.name.trim();
  if (name.length === 0) return "The name is empty.";
  if (name.length > NAME_MAX) return `The name is longer than ${NAME_MAX} characters.`;
  if (!Number.isInteger(fields.location) || fields.location < 0) {
    return "The location id is a whole number, 0 or more.";
  }
  for (const side of [fields.width, fields.height]) {
    if (!Number.isInteger(side) || side < 1 || side > max) {
      return `The size is 1 to ${max} chunks on each side for a ${fields.kind}.`;
    }
  }
  return null;
}

/**
 * A new map: every hex at the start fill and the default ground; a zone's outline holds every hex
 * (the author draws it smaller), a town has none.
 */
export function createMap(fields: NewMap): MapDocument {
  const problem = newMapProblem(fields);
  if (problem) throw new Error(problem);
  const meta: MapMeta = {
    kind: fields.kind,
    name: fields.name.trim(),
    location: fields.location,
    width: fields.width,
    height: fields.height,
    biome: fields.kind === "zone" ? fields.biome : null,
    start: fields.start,
    levelMin: 1,
    levelMax: 1,
    rank: 0,
    spawnTable: 0,
  };
  const count = tilesWide(meta) * tilesHigh(meta);
  return {
    meta,
    terrain: new Uint8Array(count).fill(fields.start === "wall" ? WALL : FLOOR),
    ground: new Uint8Array(count).fill(defaultGround()),
    outline: fields.kind === "zone" ? new Uint8Array(count).fill(1) : null,
    obstacles: new Map(),
  };
}

export function inMap(doc: MapDocument, tile: Tile): boolean {
  return tile.x >= 0 && tile.y >= 0 && tile.x < tilesWide(doc.meta) && tile.y < tilesHigh(doc.meta);
}

export function indexOf(doc: MapDocument, tile: Tile): number {
  return tile.y * tilesWide(doc.meta) + tile.x;
}

export function tileOf(doc: MapDocument, index: number): Tile {
  const width = tilesWide(doc.meta);
  return { x: index % width, y: Math.floor(index / width) };
}

/** A hex's chunk `(cx, cy)`, chunk index `15 cy + cx` and tile index `15 row + column` (§4.1). */
export function chunkOf(tile: Tile): { cx: number; cy: number; chunk: number; tile: number } {
  const cx = Math.floor(tile.x / CHUNK);
  const cy = Math.floor(tile.y / CHUNK);
  return {
    cx,
    cy,
    chunk: CHUNK * cy + cx,
    tile: CHUNK * (tile.y - cy * CHUNK) + (tile.x - cx * CHUNK),
  };
}

/**
 * The hexes next to each hex of a `width × height` map (the drawing's geometry, `acrossSide`):
 * six indices per hex, side by side, -1 beyond the map. Built once per size and kept.
 */
let sides: { key: string; table: Int32Array } | null = null;

export function sideTable(width: number, height: number): Int32Array {
  const key = `${width}x${height}`;
  if (sides?.key === key) return sides.table;
  const table = new Int32Array(width * height * 6);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      for (let side = 0; side < 6; side++) {
        const next = acrossSide({ x, y }, side);
        const inside = next.x >= 0 && next.y >= 0 && next.x < width && next.y < height;
        table[(y * width + x) * 6 + side] = inside ? next.y * width + next.x : -1;
      }
    }
  }
  sides = { key, table };
  return table;
}

/** The document's table of sides. */
export function sidesOfMap(doc: MapDocument): Int32Array {
  return sideTable(tilesWide(doc.meta), tilesHigh(doc.meta));
}

/** Brush radii: a hexagon of 1, 7, 19 or 37 hexes (§3). */
export const BRUSH_MAX = 3;

/** The hexes under a brush of `radius` centred on a hex, inside the map. */
export function brushAt(doc: MapDocument, centre: Tile, radius: number): Tile[] {
  return hexesWithin(centre, radius).filter((t) => inMap(doc, t));
}

// --- edits -------------------------------------------------------------------------------------

/** A layer an edit writes. */
export type Layer = "terrain" | "ground" | "outline";

/** What Paint and Fill put down: a terrain, a ground, or the outline's inside or outside. */
export type Swatch =
  | { readonly layer: "terrain"; readonly value: TerrainValue }
  | { readonly layer: "ground"; readonly value: number }
  | { readonly layer: "outline"; readonly value: 0 | 1 };

/** One hex of one layer changed: what it was and what it became. */
export interface Change {
  readonly layer: Layer;
  readonly index: number;
  readonly before: number;
  readonly after: number;
}

function layerOf(doc: MapDocument, layer: Layer): Uint8Array | null {
  return layer === "outline" ? doc.outline : doc[layer];
}

export function valueAt(doc: MapDocument, layer: Layer, tile: Tile): number | null {
  const values = layerOf(doc, layer);
  if (!values || !inMap(doc, tile)) return null;
  return values[indexOf(doc, tile)] ?? null;
}

/** Writes changes (or undoes them, `back`), in order. */
export function apply(doc: MapDocument, changes: readonly Change[], back = false): void {
  const ordered = back ? [...changes].reverse() : changes;
  for (const change of ordered) {
    const values = layerOf(doc, change.layer);
    if (values) values[change.index] = back ? change.before : change.after;
  }
}

/** The changes that put `swatch` on the hexes (none for a hex that already holds it). */
export function paint(doc: MapDocument, tiles: readonly Tile[], swatch: Swatch): Change[] {
  const values = layerOf(doc, swatch.layer);
  if (!values) return [];
  const changes: Change[] = [];
  for (const tile of tiles) {
    if (!inMap(doc, tile)) continue;
    const index = indexOf(doc, tile);
    const before = values[index]!;
    if (before !== swatch.value) {
      changes.push({ layer: swatch.layer, index, before, after: swatch.value });
    }
  }
  return changes;
}

/**
 * Erase (§3): terrain back to the map's start fill and ground back to the default; with the
 * outline tool, the hexes go outside the outline.
 */
export function erase(doc: MapDocument, tiles: readonly Tile[], outline = false): Change[] {
  if (outline) return paint(doc, tiles, { layer: "outline", value: 0 });
  const start: TerrainValue = doc.meta.start === "wall" ? WALL : FLOOR;
  return [
    ...paint(doc, tiles, { layer: "terrain", value: start }),
    ...paint(doc, tiles, { layer: "ground", value: defaultGround() }),
  ];
}

/**
 * The connected region of a hex (hex neighbours, inside the map) whose every hex `same` accepts,
 * the hex included, by index.
 */
export function regionOf(
  doc: MapDocument,
  start: Tile,
  same: (index: number) => boolean,
): number[] {
  if (!inMap(doc, start)) return [];
  const first = indexOf(doc, start);
  if (!same(first)) return [];
  const table = sidesOfMap(doc);
  const seen = new Uint8Array(doc.terrain.length);
  seen[first] = 1;
  const region: number[] = [];
  const pending = [first];
  while (pending.length > 0) {
    const index = pending.pop()!;
    region.push(index);
    for (let side = 0; side < 6; side++) {
      const i = table[index * 6 + side]!;
      if (i < 0 || seen[i] || !same(i)) continue;
      seen[i] = 1;
      pending.push(i);
    }
  }
  return region.sort((a, b) => a - b);
}

/**
 * Fill (§3): the connected region of the same terrain and ground as the hex takes the swatch. On
 * the outline (§2.5), the region is the hexes on the same side of the outline: bounded by it.
 */
export function fill(doc: MapDocument, start: Tile, swatch: Swatch): Change[] {
  if (!inMap(doc, start)) return [];
  const i0 = indexOf(doc, start);
  let same: (index: number) => boolean;
  if (swatch.layer === "outline") {
    const outline = doc.outline;
    if (!outline) return [];
    const side = outline[i0];
    same = (i) => outline[i] === side;
  } else {
    const terrain = doc.terrain[i0];
    const ground = doc.ground[i0];
    same = (i) => doc.terrain[i] === terrain && doc.ground[i] === ground;
  }
  return paint(
    doc,
    regionOf(doc, start, same).map((i) => tileOf(doc, i)),
    swatch,
  );
}

/** Pick (§3): the hex's terrain and ground. */
export function pick(doc: MapDocument, tile: Tile): { terrain: TerrainValue; ground: number } | null {
  if (!inMap(doc, tile)) return null;
  const i = indexOf(doc, tile);
  return { terrain: doc.terrain[i] as TerrainValue, ground: doc.ground[i]! };
}

/**
 * "Outline from floor" (§2.5): the outline becomes the connected floor region of `from` (the
 * entry once CLI-09b places one), or, with no hex given or a wall there, the largest floor region
 * (the lowest index wins a tie). Nothing changes when the map has no floor.
 */
export function outlineFromFloor(doc: MapDocument, from: Tile | null): Change[] {
  const outline = doc.outline;
  if (!outline) return [];
  const isFloor = (i: number) => doc.terrain[i] === FLOOR;
  let region: number[] = [];
  if (from && inMap(doc, from) && isFloor(indexOf(doc, from))) {
    region = regionOf(doc, from, isFloor);
  } else {
    const taken = new Uint8Array(doc.terrain.length);
    for (let i = 0; i < doc.terrain.length; i++) {
      if (taken[i] || !isFloor(i)) continue;
      const found = regionOf(doc, tileOf(doc, i), isFloor);
      for (const j of found) taken[j] = 1;
      if (found.length > region.length) region = found;
    }
  }
  if (region.length === 0) return [];
  const inside = new Uint8Array(outline.length);
  for (const i of region) inside[i] = 1;
  const changes: Change[] = [];
  for (let i = 0; i < outline.length; i++) {
    if (outline[i] !== inside[i]) {
      changes.push({ layer: "outline", index: i, before: outline[i]!, after: inside[i]! });
    }
  }
  return changes;
}

// --- the outline's records (brief §4.4) ---------------------------------------------------------

export interface OutlineRecords {
  /** Chunk indices (`15 cy + cx`) holding at least one inside hex, ascending: the chunk set. */
  readonly chunks: readonly number[];
  /**
   * For each border chunk (partly inside), its tile mask: the tile indices (`15 row + column`)
   * inside, ascending. A chunk wholly inside has none (ENG-05: "no mask is whole").
   */
  readonly masks: ReadonlyMap<number, readonly number[]>;
}

/** What ADR-0006 stores of a zone's outline, derived from the inside hexes. */
export function outlineRecords(doc: MapDocument): OutlineRecords {
  const outline = doc.outline;
  if (!outline) return { chunks: [], masks: new Map() };
  const inside = new Map<number, number[]>();
  const width = tilesWide(doc.meta);
  for (let i = 0; i < outline.length; i++) {
    if (!outline[i]) continue;
    const at = chunkOf({ x: i % width, y: Math.floor(i / width) });
    let tiles = inside.get(at.chunk);
    if (!tiles) inside.set(at.chunk, (tiles = []));
    tiles.push(at.tile);
  }
  const chunks = [...inside.keys()].sort((a, b) => a - b);
  const masks = new Map<number, readonly number[]>();
  for (const chunk of chunks) {
    const tiles = inside.get(chunk)!;
    if (tiles.length < CHUNK * CHUNK) masks.set(chunk, [...tiles].sort((a, b) => a - b));
  }
  return { chunks, masks };
}

/** A deep copy: the same document, no layer shared. */
export function cloneMap(doc: MapDocument): MapDocument {
  return {
    meta: { ...doc.meta },
    terrain: doc.terrain.slice(),
    ground: doc.ground.slice(),
    outline: doc.outline ? doc.outline.slice() : null,
    obstacles: new Map(doc.obstacles),
  };
}
