import type { Tile } from "../render/view";
import {
  CHUNK,
  type ChunkOrigin,
  type MapDocument,
  SIZE_MAX,
  type TileBox,
  boxOf,
  mapKeys,
  tileOfKey,
} from "./model";

/**
 * "Fit chunks" (CLI-09a2, D-216): the chunk grid is laid over the painted map afterwards, at the
 * origin that needs the fewest chunks.
 *
 * **Row parity.** The hexes are odd-r rows (`input/coords.ts:45`, the library's layout; ADR-0006 §4
 * "Row parity": a neighbour depends on the parity of the row). The fitted map's global `(0, 0)` is a
 * translation of the editor's plane; moving by an odd number of rows would turn every row's
 * neighbours into the other parity's, and the painted shape into another shape. So the origin's
 * row is **even**. Seams repeat every 15 rows and 15 is odd: each of the 15 row residues has one
 * even origin row within 30 (`ry`, or `ry + 15`), and the 15 × 15 residues are all tried. When the
 * even origin row lies a whole chunk below the lowest painted row, the map keeps an empty chunk row
 * at its foot (`lowRow`): the chunk set is the same, the rectangle one row higher.
 */

/** A chunk holds 225 tiles: fewer painted is a partly filled (border) chunk. */
const TILES = CHUNK * CHUNK;

/** Past this many hexes on a side, the painted hexes are not fitted (a zone is 225 at most). */
export const FIT_SPAN_MAX = 1000;

/** How an origin covers the map. */
export interface FitScore {
  readonly origin: { readonly x: number; readonly y: number };
  /** The fitted map's global `(0, 0)` on the editor's plane: `y0` even. */
  readonly x0: number;
  readonly y0: number;
  /** The fitted rectangle in chunks. */
  readonly width: number;
  readonly height: number;
  /** Chunks holding at least one of the map's hexes. */
  readonly chunks: number;
  /** Of them, the partly filled ones. */
  readonly partial: number;
  /** An empty chunk row at the foot, for the even origin row. */
  readonly lowRow: boolean;
}

/** The map's hexes as a summed-area table over their box: any rectangle counted in four reads. */
interface Occupancy {
  readonly box: TileBox;
  readonly w: number;
  readonly sums: Int32Array;
}

function occupancy(keys: readonly number[]): Occupancy | null | "wide" {
  const box = boxOf(keys);
  if (!box) return null;
  const w = box.x1 - box.x0 + 1;
  const h = box.y1 - box.y0 + 1;
  if (w > FIT_SPAN_MAX || h > FIT_SPAN_MAX) return "wide";
  const sums = new Int32Array((w + 1) * (h + 1));
  for (const key of keys) {
    const { x, y } = tileOfKey(key);
    sums[(y - box.y0 + 1) * (w + 1) + (x - box.x0 + 1)] = 1;
  }
  for (let y = 1; y <= h; y++) {
    let row = 0;
    for (let x = 1; x <= w; x++) {
      row += sums[y * (w + 1) + x]!;
      sums[y * (w + 1) + x] = sums[(y - 1) * (w + 1) + x]! + row;
    }
  }
  return { box, w, sums };
}

/** The map's hexes in the tile rectangle `[x0, x1] × [y0, y1]`. */
function countIn(o: Occupancy, x0: number, y0: number, x1: number, y1: number): number {
  const { box, w, sums } = o;
  const a = Math.max(x0, box.x0) - box.x0;
  const b = Math.min(x1, box.x1) - box.x0 + 1;
  const c = Math.max(y0, box.y0) - box.y0;
  const d = Math.min(y1, box.y1) - box.y0 + 1;
  if (a >= b || c >= d) return 0;
  const at = (x: number, y: number) => sums[y * (w + 1) + x]!;
  return at(b, d) - at(a, d) - at(b, c) + at(a, c);
}

const mod = (n: number, m: number) => ((n % m) + m) % m;

/** The even origin row of a row residue: the residue, or the residue + 15 when it is odd. */
export const evenRow = (residue: number): number => {
  const r = mod(residue, CHUNK);
  return r % 2 === 0 ? r : r + CHUNK;
};

function score(o: Occupancy, ox: number, oy: number): FitScore {
  const { box } = o;
  const x0 = ox + CHUNK * Math.floor((box.x0 - ox) / CHUNK);
  // The origin row stays even: it steps by 30 rows.
  const y0 = oy + 2 * CHUNK * Math.floor((box.y0 - oy) / (2 * CHUNK));
  const width = Math.floor((box.x1 - x0) / CHUNK) + 1;
  const height = Math.floor((box.y1 - y0) / CHUNK) + 1;
  let chunks = 0;
  let partial = 0;
  for (let cy = 0; cy < height; cy++) {
    for (let cx = 0; cx < width; cx++) {
      const x = x0 + CHUNK * cx;
      const y = y0 + CHUNK * cy;
      const n = countIn(o, x, y, x + CHUNK - 1, y + CHUNK - 1);
      if (n === 0) continue;
      chunks += 1;
      if (n < TILES) partial += 1;
    }
  }
  return {
    origin: { x: ox, y: oy },
    x0,
    y0,
    width,
    height,
    chunks,
    partial,
    lowRow: box.y0 - y0 >= CHUNK,
  };
}

/**
 * The order of the fit: fewest chunks, then fewest partly filled, then the smallest rectangle (an
 * empty foot row loses), then the lowest origin row, then the lowest origin column.
 */
export function better(a: FitScore, b: FitScore): boolean {
  if (a.chunks !== b.chunks) return a.chunks < b.chunks;
  if (a.partial !== b.partial) return a.partial < b.partial;
  const area = a.width * a.height - b.width * b.height;
  if (area !== 0) return area < 0;
  if (a.origin.y !== b.origin.y) return a.origin.y < b.origin.y;
  return a.origin.x < b.origin.x;
}

export type FitResult = FitScore | "empty" | "wide";

/** Every origin compatible with the rows' parity (15 × 15), the best kept. */
export function fitChunks(doc: MapDocument): FitResult {
  const o = occupancy(mapKeys(doc));
  if (o === null) return "empty";
  if (o === "wide") return "wide";
  let best: FitScore | null = null;
  for (let ry = 0; ry < CHUNK; ry++) {
    for (let ox = 0; ox < CHUNK; ox++) {
      const s = score(o, ox, evenRow(ry));
      if (!best || better(s, best)) best = s;
    }
  }
  return best!;
}

/** How a given origin covers the map (the counts shown after a nudge). */
export function scoreAt(doc: MapDocument, origin: Pick<ChunkOrigin, "x" | "y">): FitResult {
  const o = occupancy(mapKeys(doc));
  if (o === null) return "empty";
  if (o === "wide") return "wide";
  return score(o, mod(origin.x, CHUNK), evenRow(origin.y));
}

/**
 * The origin moved by whole hexes (D-216's nudge): `dx` West, `dy` North, wrapping every 15; the
 * row kept even.
 */
export function nudge(origin: Pick<ChunkOrigin, "x" | "y">, dx: number, dy: number): ChunkOrigin {
  return { x: mod(origin.x + dx, CHUNK), y: evenRow(origin.y + dy), how: "nudged" };
}

/** What the validation and the export read (§4.4, ADR-0006), in the fitted map's coordinates. */
export interface Fitted extends FitScore {
  /** Chunk indices `15 cy + cx` holding at least one of the map's hexes, ascending: the chunk set. */
  readonly chunkSet: readonly number[];
  /**
   * For each partly filled chunk, its tile mask: the tile indices (`15 row + column`) of the map's
   * hexes, ascending. A whole chunk has none (ENG-05: "no mask is whole").
   */
  readonly masks: ReadonlyMap<number, readonly number[]>;
  /** Why the fitted map cannot be registered as it is: too many chunks on a side. */
  readonly problems: readonly string[];
}

/** The map at its chosen origin, or why there is none to read. */
export function fitted(doc: MapDocument): Fitted | "unfitted" | "empty" | "wide" {
  if (!doc.origin) return "unfitted";
  const keys = mapKeys(doc);
  const s = scoreAt(doc, doc.origin);
  if (typeof s === "string") return s;
  const tiles = new Map<number, number[]>();
  for (const key of keys) {
    const at = chunkAt(tileOfKey(key), s);
    let list = tiles.get(at.chunk);
    if (!list) tiles.set(at.chunk, (list = []));
    list.push(at.tile);
  }
  const chunkSet = [...tiles.keys()].sort((a, b) => a - b);
  const masks = new Map<number, readonly number[]>();
  for (const chunk of chunkSet) {
    const list = tiles.get(chunk)!;
    if (list.length < TILES)
      masks.set(
        chunk,
        list.sort((a, b) => a - b),
      );
  }
  const max = SIZE_MAX[doc.meta.kind];
  const problems: string[] = [];
  if (s.width > max || s.height > max) {
    problems.push(
      `The fitted map is ${s.width} × ${s.height} chunks: a ${doc.meta.kind} is at most ${max} × ${max}.`,
    );
  }
  return { ...s, chunkSet, masks, problems };
}

/**
 * A hex's place in the fitted map (§4.1): its global `(x, y)`, chunk `(cx, cy)`, chunk index
 * `15 cy + cx` and tile index `15 row + column`.
 */
export function chunkAt(
  tile: Tile,
  at: Pick<FitScore, "x0" | "y0">,
): { x: number; y: number; cx: number; cy: number; chunk: number; tile: number } {
  const x = tile.x - at.x0;
  const y = tile.y - at.y0;
  const cx = Math.floor(x / CHUNK);
  const cy = Math.floor(y / CHUNK);
  return {
    x,
    y,
    cx,
    cy,
    chunk: CHUNK * cy + cx,
    tile: CHUNK * (y - cy * CHUNK) + (x - cx * CHUNK),
  };
}
