import { acrossSide, hexesWithin } from "../render/ground";
import type { GroundKind, Tile } from "../render/view";

/**
 * The map editor's document (CLI-09a, brief `docs/briefs/CLI-09-map-editor.md` §4), unbounded since
 * CLI-09a2 (D-216): a zone, a town or an outpost painted hex by hex on an endless plane; only the
 * painted hexes are stored. The chunks are fitted afterwards (`fit.ts`). A tool's document, not a
 * rule of the game: the editor reproduces checks, it decides none (mandate §6).
 *
 * Coordinates are the client's `(x, y)`: `x` grows West, `y` North, odd-r rows (`input/coords.ts`),
 * any sign, within ±`COORD_MAX`. The fitted origin moves them to the chain's global `(x, y)` by a
 * translation that keeps the rows' parity (`fit.ts`).
 */

/** Chunks are 15 × 15 tiles (ADR-0006). */
export const CHUNK = 15;

export type MapKind = "zone" | "town" | "outpost";
export const MAP_KINDS: readonly MapKind[] = ["zone", "town", "outpost"];

/** `location.cairo:22-27`. */
export type Biome = "meadow" | "forest" | "cave" | "ruin";
export const BIOMES: readonly Biome[] = ["meadow", "forest", "cave", "ruin"];

/** The walkable plane, the one bit the chain holds per tile (ENG-08 ruling 1, D-215). */
export const FLOOR = 0;
export const WALL = 1;
export type TerrainValue = typeof FLOOR | typeof WALL;

/** The ground, a client-only layer (D-215), in the order `GROUND_KINDS` gives. */
export const GROUND_KINDS: readonly GroundKind[] = ["grass", "earth", "water"];

/** Name bound: a short string of `REGION` (brief §2.2). */
export const NAME_MAX = 15;
/** The fitted map's bound in chunks, per side (brief §2.2, E-1): checked on the fit, not before. */
export const SIZE_MAX: Readonly<Record<MapKind, number>> = { zone: 15, town: 4, outpost: 4 };

/** The plane's bound: a coordinate is a whole number within ±`COORD_MAX`, far past any map. */
export const COORD_MAX = 32767;

/** What the map is, beside its hexes. Numbers the editor does not read (brief §4.2). */
export interface MapMeta {
  readonly kind: MapKind;
  readonly name: string;
  readonly location: number;
  /** A zone's; null for a town or an outpost. */
  readonly biome: Biome | null;
  readonly levelMin: number;
  readonly levelMax: number;
  readonly rank: number;
  readonly spawnTable: number;
}

/**
 * The chunk grid's origin (D-216): chunk seams run where `x ≡ origin.x` and `y ≡ origin.y`
 * (mod 15). `y` is even, 0 to 28, `x` 0 to 14: the map's global `(0, 0)` lies on an even row, so
 * the move to global coordinates keeps every row's parity (`fit.ts`). `how` says whether the fit
 * chose it or the author nudged it.
 */
export interface ChunkOrigin {
  readonly x: number;
  readonly y: number;
  readonly how: "fitted" | "nudged";
}

/**
 * A painted hex, packed in a number: bit 0 the terrain (`WALL`), bits 1-2 the ground's index in
 * `GROUND_KINDS`, bit 3 outside the outline (a zone's). An unpainted hex has no cell.
 */
export type Cell = number;
const GROUND_SHIFT = 1;
const OUTSIDE = 8;

export const cellOf = (terrain: TerrainValue, ground: number, outside = false): Cell =>
  terrain | (ground << GROUND_SHIFT) | (outside ? OUTSIDE : 0);
export const terrainOf = (cell: Cell): TerrainValue => (cell & 1) as TerrainValue;
export const groundOfCell = (cell: Cell): number => (cell >> GROUND_SHIFT) & 3;
export const isOutside = (cell: Cell): boolean => (cell & OUTSIDE) !== 0;

/**
 * The document. `hexes` and `obstacles` are mutated in place by the edits (`apply`), which the
 * history records as differences; the rest is replaced whole.
 */
export interface MapDocument {
  meta: MapMeta;
  /** The painted hexes, by `keyOf`. */
  readonly hexes: Map<number, Cell>;
  /**
   * The obstacle looks pinned on wall hexes, by `keyOf`: a still's name (brief §4.1). A hex not here
   * is `auto` (the renderer's choice by `hexHash`). CLI-09a writes none; the inspector (CLI-09b)
   * pins them.
   */
  readonly obstacles: Map<number, string>;
  /** The last chosen chunk origin, null before the first fit (D-216). */
  origin: ChunkOrigin | null;
}

const SPAN = 2 * COORD_MAX + 2;

/** A hex's key in the maps: one number per `(x, y)` within the plane's bound. */
export function keyOf(tile: Tile): number {
  return (tile.y + COORD_MAX + 1) * SPAN + (tile.x + COORD_MAX + 1);
}

export function tileOfKey(key: number): Tile {
  return { x: (key % SPAN) - COORD_MAX - 1, y: Math.floor(key / SPAN) - COORD_MAX - 1 };
}

export function inPlane(tile: Tile): boolean {
  return Math.abs(tile.x) <= COORD_MAX && Math.abs(tile.y) <= COORD_MAX;
}

/** The ground a new hex has: grass for every biome until a second one is drawn. */
export function defaultGround(): number {
  return GROUND_KINDS.indexOf("grass");
}

export function isZone(doc: MapDocument): boolean {
  return doc.meta.kind === "zone";
}

export interface NewMap {
  readonly kind: MapKind;
  readonly name: string;
  readonly location: number;
  readonly biome: Biome;
}

/** Why a new map's fields are refused, or null. */
export function newMapProblem(fields: NewMap): string | null {
  const name = fields.name.trim();
  if (name.length === 0) return "The name is empty.";
  if (name.length > NAME_MAX) return `The name is longer than ${NAME_MAX} characters.`;
  if (!Number.isInteger(fields.location) || fields.location < 0) {
    return "The location id is a whole number, 0 or more.";
  }
  return null;
}

/** A new map: nothing painted, no chunk grid yet (D-216). */
export function createMap(fields: NewMap): MapDocument {
  const problem = newMapProblem(fields);
  if (problem) throw new Error(problem);
  return {
    meta: {
      kind: fields.kind,
      name: fields.name.trim(),
      location: fields.location,
      biome: fields.kind === "zone" ? fields.biome : null,
      levelMin: 1,
      levelMax: 1,
      rank: 0,
      spawnTable: 0,
    },
    hexes: new Map(),
    obstacles: new Map(),
    origin: null,
  };
}

/** The hex's cell, or null when it is not painted. */
export function cellAt(doc: MapDocument, tile: Tile): Cell | null {
  return doc.hexes.get(keyOf(tile)) ?? null;
}

/** The painted hexes' bounding box in tiles, or null when nothing is painted. */
export interface TileBox {
  readonly x0: number;
  readonly y0: number;
  readonly x1: number;
  readonly y1: number;
}

export function boxOf(keys: Iterable<number>): TileBox | null {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const key of keys) {
    const { x, y } = tileOfKey(key);
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  return x0 === Infinity ? null : { x0, y0, x1, y1 };
}

export function paintedBox(doc: MapDocument): TileBox | null {
  return boxOf(doc.hexes.keys());
}

/**
 * The hexes the chunks must hold (D-216): every painted hex of a town; a zone's painted hexes inside
 * its outline, since the game draws the outside as void and its export ignores it (§4.4).
 */
export function mapKeys(doc: MapDocument): number[] {
  const zone = isZone(doc);
  const out: number[] = [];
  for (const [key, cell] of doc.hexes) if (!zone || !isOutside(cell)) out.push(key);
  return out;
}

/**
 * The six hexes around a hex, as offsets for an even and an odd row: odd-r rows, so a translation
 * by an even number of rows keeps them. Read once from the drawing's geometry (`acrossSide`).
 */
const SIDE_STEPS: readonly (readonly Tile[])[] = [0, 1].map((p) =>
  Array.from({ length: 6 }, (_, side) => {
    const next = acrossSide({ x: 0, y: p }, side);
    return { x: next.x, y: next.y - p };
  }),
);

/** The hex across side `side` (0 to 5) of a hex: as `acrossSide`, without the pixels. */
export function sideOf(tile: Tile, side: number): Tile {
  const step = SIDE_STEPS[tile.y & 1]![side]!;
  return { x: tile.x + step.x, y: tile.y + step.y };
}

/** Brush radii: a hexagon of 1, 7, 19 or 37 hexes (§3). */
export const BRUSH_MAX = 3;

/** The hexes under a brush of `radius` centred on a hex, inside the plane's bound. */
export function brushAt(centre: Tile, radius: number): Tile[] {
  return hexesWithin(centre, radius).filter(inPlane);
}

// --- edits -------------------------------------------------------------------------------------

/** What Paint and Fill put down: a terrain, a ground, or the outline's inside (1) or outside (0). */
export type Swatch =
  | { readonly layer: "terrain"; readonly value: TerrainValue }
  | { readonly layer: "ground"; readonly value: number }
  | { readonly layer: "outline"; readonly value: 0 | 1 };

/** One hex changed: its cell before and after, null for unpainted. */
export interface Change {
  readonly key: number;
  readonly before: Cell | null;
  readonly after: Cell | null;
}

/** Writes changes (or undoes them, `back`), in order. */
export function apply(doc: MapDocument, changes: readonly Change[], back = false): void {
  const ordered = back ? [...changes].reverse() : changes;
  for (const change of ordered) {
    const value = back ? change.before : change.after;
    if (value === null) doc.hexes.delete(change.key);
    else doc.hexes.set(change.key, value);
  }
}

/** The cell a swatch makes of a hex (null: it leaves the hex as it is). */
function painted(cell: Cell | null, swatch: Swatch): Cell | null {
  switch (swatch.layer) {
    case "terrain":
      // An unpainted hex becomes painted: the terrain, the default ground, inside the outline.
      return cell === null ? cellOf(swatch.value, defaultGround()) : (cell & ~1) | swatch.value;
    case "ground":
      return cell === null
        ? cellOf(FLOOR, swatch.value)
        : (cell & ~(3 << GROUND_SHIFT)) | (swatch.value << GROUND_SHIFT);
    case "outline":
      // The outline sorts painted hexes only: an unpainted hex is nothing to keep or leave out.
      if (cell === null) return null;
      return swatch.value === 1 ? cell & ~OUTSIDE : cell | OUTSIDE;
  }
}

/** The changes that put `swatch` on the hexes (none for a hex that already holds it). */
export function paint(doc: MapDocument, tiles: readonly Tile[], swatch: Swatch): Change[] {
  if (swatch.layer === "outline" && !isZone(doc)) return [];
  const changes: Change[] = [];
  for (const tile of tiles) {
    if (!inPlane(tile)) continue;
    const key = keyOf(tile);
    const before = doc.hexes.get(key) ?? null;
    const after = painted(before, swatch);
    if (after !== null && after !== before) changes.push({ key, before, after });
  }
  return changes;
}

/**
 * Erase (§3): the hexes are unpainted, back to the void (D-216); with the outline tool, they go
 * outside the outline instead.
 */
export function erase(doc: MapDocument, tiles: readonly Tile[], outline = false): Change[] {
  if (outline) return paint(doc, tiles, { layer: "outline", value: 0 });
  const changes: Change[] = [];
  for (const tile of tiles) {
    if (!inPlane(tile)) continue;
    const key = keyOf(tile);
    const before = doc.hexes.get(key);
    if (before !== undefined) changes.push({ key, before, after: null });
  }
  return changes;
}

/**
 * The most hexes one Fill takes: a zone of 15 × 15 chunks. Past it the fill is refused (D-216:
 * Fill never runs unbounded on the endless plane).
 */
export const FILL_MAX = (CHUNK * CHUNK) ** 2;

/**
 * The connected region of a hex (hex neighbours) whose every hex `same` accepts, the hex included,
 * by key, ascending; or why it is refused: it reaches outside `within` (an open region) or holds
 * more than `FILL_MAX` hexes.
 */
export function regionOf(
  start: Tile,
  same: (key: number) => boolean,
  within: TileBox,
): number[] | "open" | "large" {
  const first = keyOf(start);
  if (!same(first)) return [];
  const seen = new Set([first]);
  const region: number[] = [];
  const pending = [start];
  while (pending.length > 0) {
    const tile = pending.pop()!;
    region.push(keyOf(tile));
    if (region.length > FILL_MAX) return "large";
    for (let side = 0; side < 6; side++) {
      const next = sideOf(tile, side);
      const key = keyOf(next);
      if (seen.has(key) || !same(key)) continue;
      const out =
        next.x < within.x0 || next.x > within.x1 || next.y < within.y0 || next.y > within.y1;
      if (out) return "open";
      seen.add(key);
      pending.push(next);
    }
  }
  return region.sort((a, b) => a - b);
}

/**
 * Fill (§3): the connected region of the same terrain and ground as the hex takes the swatch; on
 * an unpainted hex, the connected unpainted region, which must be closed by painted hexes: it may
 * not reach the painted hexes' box grown by one hex (D-216). On the outline (§2.5), the region is the
 * painted hexes on the same side of the outline: bounded by it. Refused regions give the reason.
 */
export function fill(doc: MapDocument, start: Tile, swatch: Swatch): Change[] | string {
  if (!inPlane(start)) return [];
  const startCell = cellAt(doc, start);
  let same: (key: number) => boolean;
  if (swatch.layer === "outline") {
    if (startCell === null || !isZone(doc)) return [];
    const side = isOutside(startCell);
    same = (k) => {
      const cell = doc.hexes.get(k);
      return cell !== undefined && isOutside(cell) === side;
    };
  } else if (startCell === null) {
    same = (k) => !doc.hexes.has(k);
  } else {
    const look = startCell & ~OUTSIDE;
    same = (k) => {
      const cell = doc.hexes.get(k);
      return cell !== undefined && (cell & ~OUTSIDE) === look;
    };
  }
  const box = paintedBox(doc);
  if (!box) return "Nothing is painted around: Fill needs a region closed by painted hexes.";
  const within = { x0: box.x0 - 1, y0: box.y0 - 1, x1: box.x1 + 1, y1: box.y1 + 1 };
  const region = regionOf(start, same, within);
  if (region === "open") return "This empty region is open: close it with painted hexes first.";
  if (region === "large") return `Fill takes at most ${FILL_MAX} hexes.`;
  return paint(doc, region.map(tileOfKey), swatch);
}

/** Pick (§3): the hex's terrain and ground; null on an unpainted hex. */
export function pick(
  doc: MapDocument,
  tile: Tile,
): { terrain: TerrainValue; ground: number } | null {
  const cell = cellAt(doc, tile);
  return cell === null ? null : { terrain: terrainOf(cell), ground: groundOfCell(cell) };
}

/**
 * "Outline from floor" (§2.5): the connected floor region of `from` (the entry once CLI-09b places
 * one) goes inside and every other painted hex outside; with no hex given or no floor there, the
 * largest floor region (the lowest key wins a tie). Nothing changes when the map has no floor.
 */
export function outlineFromFloor(doc: MapDocument, from: Tile | null): Change[] {
  if (!isZone(doc)) return [];
  const isFloor = (k: number) => {
    const cell = doc.hexes.get(k);
    return cell !== undefined && terrainOf(cell) === FLOOR;
  };
  const box = paintedBox(doc);
  if (!box) return [];
  const regionAt = (tile: Tile): number[] => {
    const region = regionOf(tile, isFloor, box);
    // The painted hexes are all within their box: a floor region is never open.
    return Array.isArray(region) ? region : [];
  };
  let region: number[] = [];
  if (from && isFloor(keyOf(from))) {
    region = regionAt(from);
  } else {
    const taken = new Set<number>();
    for (const key of [...doc.hexes.keys()].sort((a, b) => a - b)) {
      if (taken.has(key) || !isFloor(key)) continue;
      const found = regionAt(tileOfKey(key));
      for (const k of found) taken.add(k);
      if (found.length > region.length) region = found;
    }
  }
  if (region.length === 0) return [];
  const inside = new Set(region);
  const changes: Change[] = [];
  for (const [key, before] of doc.hexes) {
    const after = inside.has(key) ? before & ~OUTSIDE : before | OUTSIDE;
    if (after !== before) changes.push({ key, before, after });
  }
  return changes;
}

/** A deep copy: the same document, nothing shared. */
export function cloneMap(doc: MapDocument): MapDocument {
  return {
    meta: { ...doc.meta },
    hexes: new Map(doc.hexes),
    obstacles: new Map(doc.obstacles),
    origin: doc.origin ? { ...doc.origin } : null,
  };
}
