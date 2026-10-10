// The reveal of a chunk (ENG-05, ENG-05b, ENG-10b, as ENG-07 plays it): the mirror of
// `contracts/logic/src/types/reveal.cairo` (`RevealTrait`, `SightTrait`, `Site`, `Progress`), of
// `fate::EntropyTrait` and of `PackPlacementTrait::member` (`models/chunk.cairo`), held equal to
// them by `contracts/logic/vectors/reveal.jsonl`. The board steps are `reveal/board.ts`, the
// quotas and the placement `reveal/placement.ts`, the draws and the automaton `hexx.ts`.
//
// The rules, their order (design/18) and their reasons are the Cairo module's documentation. A
// chunk that is not revealable is skipped, never generated (D-136: it stays wall in the window);
// its four corner tiles are always wall (D-134).

import { poseidonHashMany } from "@scure/starknet";
import { REVEAL, derive, domain } from "./fate";
import { type IntType, add, feltArg, fromFelt, i8, panic, toFelt, u16, u32, u8 } from "./felt";
import { felt, mix, rngNew, type Rng, draw } from "./hexx";
import {
  BOARD,
  CENTRE,
  INTERIOR,
  anchor_line,
  base,
  component,
  copy,
  count,
  cut,
  floor,
  has,
  lines,
  minus,
  near_openings,
  nth,
  pow,
  side as sideMask,
  smoothChunk,
} from "./reveal/board";
import {
  type PackPlacement,
  type PlacedObject,
  type SetPiece,
  type Site,
  TRIES,
  due as dueQuotas,
  place,
  quota,
  sitePiece,
  slot,
  spend,
} from "./reveal/placement";

export type { PackPlacement, PlacedObject, SetPiece, Site } from "./reveal/placement";

/** The sides of a chunk, in ENG-01's order of the edges (`Terrain.edges` bit `side`). */
export const side = { WEST: 0, EAST: 1, SOUTH: 2, NORTH: 3 } as const;
/** A dungeon's side is drawn as a border with probability 1 in `BORDER` (drawn, unread). */
export const BORDER = 7;

export const errors = { NEIGHBOUR: "reveal: neighbour not given" } as const;

/** A revealed chunk's walls (1 = wall) and its edges. */
export type Terrain = { walls: bigint; edges: number };
/** A revealed chunk's packs and objects. */
export type Features = { packs: PackPlacement[]; objects: PlacedObject[]; touched: number };
/** A chunk revealed: its two words. */
export type Revealed = { chunk: number; terrain: Terrain; features: Features };
/** What a reveal reads and writes of an instance. */
export type Progress = {
  revealed: bigint;
  count: number;
  open_edges: number;
  left: number[];
  entropy: bigint;
};

/** `ChunkKind`: what a chunk is for the window and the views. */
export const ChunkKind = { Void: 0, Unrevealed: 1, Revealed: 2 } as const;
export type ChunkKind = (typeof ChunkKind)[keyof typeof ChunkKind];

// ---- The entropy (`fate::EntropyTrait`) -------------------------------------------------------

/** `EntropyTrait::feed`: `entropy + poseidon(fact)`. */
export function feed(entropy: bigint, fact: readonly bigint[]): bigint {
  return felt(feltArg(entropy) + poseidonHashMany(fact.map(feltArg)));
}

/** `EntropyTrait::word`: a chunk's random word, `derive(entropy, domain(instance, chunk, REVEAL), 0)`. */
export function word(entropy: bigint, instance_id: bigint, chunk: number): bigint {
  return derive(entropy, domain(instance_id, BigInt(chunk), REVEAL), 0);
}

/** `EntropyTrait::hosts`: the seed of the quotas' hosts, the word of chunk 225. */
export function hosts(entropy: bigint, instance_id: bigint): bigint {
  return word(entropy, instance_id, 225);
}

/** `EntropyTrait::outline`: the seed of a dungeon floor's outline, the word of chunk 227. */
export function outline(entropy: bigint, instance_id: bigint): bigint {
  return word(entropy, instance_id, 227);
}

// ---- The site (`SiteTrait`) -------------------------------------------------------------------

/** The chunk beyond `side` of `chunk`, if it is inside the location's rectangle. */
export function neighbour(site: Site, chunk: number, at: number): number | undefined {
  const cy = Math.floor(chunk / 15);
  const cx = chunk % 15;
  if (at === side.WEST) return cx + 1 < site.width ? chunk + 1 : undefined;
  if (at === side.EAST) return cx !== 0 ? chunk - 1 : undefined;
  if (at === side.SOUTH) return cy !== 0 ? chunk - 15 : undefined;
  return cy + 1 < site.height ? chunk + 15 : undefined;
}

/** Whether `chunk` is inside the location: its rectangle, and its chunk set (or outline). */
export function inside(site: Site, chunk: number): boolean {
  const cy = Math.floor(chunk / 15);
  const cx = chunk % 15;
  if (chunk >= 225 || cx >= site.width || cy >= site.height) return false;
  return site.chunk_set === 0n || has(site.chunk_set, chunk);
}

/** Whether the seam on `at` of `chunk`, toward `next`, is open in a dungeon's outline. */
export function seam(site: Site, chunk: number, at: number, next: number): boolean {
  if (at === side.WEST) return has(site.west, chunk);
  if (at === side.EAST) return has(site.west, next);
  if (at === side.SOUTH) return has(site.north, next);
  return has(site.north, chunk);
}

/** The mask word of `chunk`: its tiles, and above the board the quotas it hosts. */
export function mask(site: Site, chunk: number): bigint {
  let found = BOARD;
  for (const [at, value] of site.masks) if (at === chunk && value !== 0n) found = value;
  return found;
}

// ---- The reveal (`RevealTrait`) ---------------------------------------------------------------

/** `RevealTrait::kind`. */
export function kind(site: Site, progress: Progress, chunk: number): ChunkKind {
  if (!inside(site, chunk)) return ChunkKind.Void;
  if (has(progress.revealed, chunk)) return ChunkKind.Revealed;
  return ChunkKind.Unrevealed;
}

/** `RevealTrait::revealable`: not revealed, and inside the location. */
export function revealable(site: Site, progress: Progress, chunk: number): boolean {
  return !has(progress.revealed, chunk) && inside(site, chunk);
}

/** A corner tile of the chunk, never open (D-134). */
export function corner(tile: number): boolean {
  return tile === 0 || tile === 14 || tile === 210 || tile === 224;
}

const opposite = (at: number): number => [1, 0, 3][at] ?? 2;
const pow2 = (at: number): number => [1, 2, 4][at] ?? 8;
const isOpen = (edges: number, at: number): boolean => Math.floor(edges / pow2(at)) % 2 === 1;

/** The terrain of a revealed chunk given in `known`, the last entry for it. */
function knownTerrain(known: readonly [number, Terrain][], chunk: number): Terrain {
  let found: Terrain | undefined;
  for (const [at, terrain] of known) if (at === chunk) found = terrain;
  return found ?? panic(errors.NEIGHBOUR);
}

/** An opening on `at` among its `allowed` tiles (not empty): `TRIES` draws, then the exact one. */
export function opening(allowed: bigint, at: number, draws: Rng): number {
  const [first, step] = (
    [
      [14, 15],
      [0, 15],
      [0, 1],
    ] as const
  )[at] ?? [210, 1];
  for (let tries = 0; tries < TRIES; tries++) {
    const tile = first + step * (1 + draw(draws, 13));
    if (has(allowed, tile)) return tile;
  }
  return nth(allowed, draw(draws, count(allowed)));
}

/** A side's openings among its `allowed` tiles, 1 or 2 (0 when none; the count drawn either way). */
export function openings(allowed: bigint, at: number, draws: Rng): bigint {
  const two = draw(draws, 2) === 1;
  if (allowed === 0n) return 0n;
  let ring = pow(opening(allowed, at, draws));
  if (two) ring = ring | pow(opening(allowed, at, draws));
  return ring;
}

/** The ring of a chunk and its edges: each side copied, closed or drawn, then its openings. */
export function decide(
  site: Site,
  progress: Progress,
  instance_id: bigint,
  known: readonly [number, Terrain][],
  chunk: number,
  tiles: bigint,
  draws: Rng,
): [bigint, number] {
  const emerging = site.target !== 0;
  let ring = 0n;
  let edges = 0;
  let open = 0;
  for (let at = 0; at < 4; at++) {
    const next = neighbour(site, chunk, at);
    if (next === undefined) continue;
    if (has(progress.revealed, next)) {
      const terrain = knownTerrain(known, next);
      ring = felt(ring + copy(at, floor(terrain.walls)));
      if (isOpen(terrain.edges, opposite(at))) edges += pow2(at);
    } else if (inside(site, next)) {
      draw(draws, BORDER);
      if ((sideMask(at) & tiles) !== 0n && (!emerging || seam(site, chunk, at, next))) {
        open += pow2(at);
      }
    }
  }
  const seams = emerging ? outline(progress.entropy, instance_id) : 0n;
  for (let at = 0; at < 4; at++) {
    if (((open >> at) & 1) !== 1) continue;
    const allowed = sideMask(at) & tiles;
    let drawn: bigint;
    if (emerging) {
      const [low, axis] = [
        [chunk, 0],
        [chunk - 1, 0],
        [chunk - 15, 1],
      ][at] ?? [chunk, 1];
      const stream = rngNew(poseidonHashMany([seams, BigInt(low!), BigInt(axis!)]));
      drawn = openings(allowed, at, stream);
    } else {
      drawn = openings(allowed, at, draws);
    }
    if (drawn !== 0n) {
      ring = ring | drawn;
      edges += pow2(at);
    }
  }
  return [ring, edges];
}

/** The set piece of the first set-piece quota due whose piece the site holds, with its slot. */
export function piece(site: Site, due: number): [number, SetPiece] | undefined {
  for (let i = 0; due >> i !== 0; i++) {
    if (((due >> i) & 1) !== 1) continue;
    const [kind, param] = slot(site, i);
    const set = kind === quota.SET_PIECE ? sitePiece(site, param) : undefined;
    if (set !== undefined) return [i, set];
  }
  return undefined;
}

/** The flood's source: the centre if it is floor, else the first interior anchor on floor. */
export function root(interior: bigint, anchors: readonly number[]): number | undefined {
  if (has(interior, CENTRE)) return CENTRE;
  return anchors.find((tile) => has(interior, tile));
}

const EMPTY_PACK: PackPlacement = {
  tile: 0,
  template: 0,
  level: 0,
  count: 0,
  offsets: 0,
  alert: 0,
};
const EMPTY_OBJECT: PlacedObject = { tile: 0, kind: 0, state: 0, param: 0 };

/** Generates one revealable chunk and records it in `progress`. */
export function generate(
  site: Site,
  progress: Progress,
  instance_id: bigint,
  known: readonly [number, Terrain][],
  chunk: number,
): Revealed {
  const chunkWord = word(progress.entropy, instance_id, chunk);
  const odd = Math.floor(chunk / 15) % 2 === 1;
  const wordMask = mask(site, chunk);
  const tiles = wordMask & BOARD;
  // 5. The quotas due here, drawn first: a set piece replaces the generation
  const quotas = rngNew(mix(chunkWord, 2n));
  const due = dueQuotas(site, progress.left, wordMask, quotas);
  const set = piece(site, due);
  // 3. The ring: each side copied, closed or drawn; the anchors opened
  const draws = rngNew(mix(chunkWord, 4n));
  const [decided, edges] = decide(site, progress, instance_id, known, chunk, tiles, draws);
  let ring = decided;
  const anchors: number[] = [];
  let inner = 0n;
  for (const [at, tile] of site.anchors) {
    if (at !== chunk || tile >= 225) continue;
    if (has(INTERIOR, tile)) {
      inner = inner | anchor_line(tile);
      anchors.push(tile);
    } else if (has(BOARD - INTERIOR, tile) && !corner(tile)) {
      ring = ring | pow(tile);
    }
  }
  // 1–2. The base and the smoothing with the ring frozen, or the set piece
  const interior =
    set !== undefined
      ? floor(set[1].walls) & INTERIOR
      : smoothChunk(felt(base(chunkWord, site.biome) + ring), odd) & INTERIOR;
  // 3. The openings and anchors joined to the spine
  const grid = interior | lines(ring) | inner;
  // 4. The cut by the outline, then the centre's component
  const kept = cut(felt(grid + ring), tiles);
  const keptRing = minus(kept, INTERIOR);
  let floorTiles = kept & INTERIOR;
  const source = root(floorTiles, anchors);
  if (source !== undefined) floorTiles = component(floorTiles, source, odd);
  const terrain: Terrain = {
    walls: felt(BOARD - floorTiles - keptRing),
    edges: site.target !== 0 ? edges : 0,
  };
  // 6. The placement, on the floor away from the openings and anchors
  const allowed = minus(floorTiles, near_openings(keptRing, anchors, odd));
  const placement = place(site, chunk, due, set, allowed, odd, rngNew(mix(chunkWord, 3n)));
  const features: Features = {
    packs: [0, 1].map((i) => placement.packs[i] ?? EMPTY_PACK),
    objects: [0, 1, 2].map((i) => placement.objects[i] ?? EMPTY_OBJECT),
    touched: 0,
  };
  // The instance's progress
  progress.left = spend(progress.left, placement.placed);
  progress.revealed = felt(progress.revealed + pow(chunk));
  progress.count = Number(add(u8, BigInt(progress.count), 1n));
  progress.open_edges = 0;
  return { chunk, terrain, features };
}

/** `RevealTrait::reveal`: reveals `chunks` in order, each revealable one known to the next ones. */
export function reveal(
  site: Site,
  progress: Progress,
  instance_id: bigint,
  known: readonly [number, Terrain][],
  chunks: readonly number[],
): Revealed[] {
  const terrains = [...known];
  const out: Revealed[] = [];
  for (const chunk of chunks) {
    if (revealable(site, progress, chunk)) {
      const revealed = generate(site, progress, instance_id, terrains, chunk);
      terrains.push([chunk, revealed.terrain]);
      out.push(revealed);
    }
  }
  return out;
}

// ---- Sight (`SightTrait`) ---------------------------------------------------------------------

const u8add = (a: number, b: number): number => Number(add(u8, BigInt(a), BigInt(b)));

/** Whether the hexagon of radius 6 around `(x, y)` reaches chunk `(column, row)`. */
export function touches(x: number, y: number, column: number, row: number): boolean {
  const top = row * 15;
  const nearY = y < top ? top : y > top + 14 ? top + 14 : y;
  const dr = nearY + 6 - y;
  if (dr > 12) return false;
  const lowQ = dr >= 6 ? 0 : 6 - dr;
  const highQ = dr <= 6 ? 12 : 18 - dr;
  const first = x + lowQ + Math.floor(nearY / 2);
  const last = x + highQ + Math.floor(nearY / 2);
  const left = column * 15 + 6 + Math.floor(y / 2);
  const right = left + 14;
  return first <= right && last >= left;
}

/** `SightTrait::chunks`: the chunks within 6 of the global tile `(x, y)`, its own first, then by index. */
export function chunks(x: number, y: number, width: number, height: number): number[] {
  const own = u8add(Math.floor(y / 15) * 15, Math.floor(x / 15));
  const out = [own];
  const lowX = x >= 6 ? Math.floor((x - 6) / 15) : 0;
  const highX = Math.floor(u8add(x, 6) / 15);
  const lowY = y >= 6 ? Math.floor((y - 6) / 15) : 0;
  const highY = Math.floor(u8add(y, 6) / 15);
  for (let row = lowY; row <= highY && row < height; row++) {
    for (let column = lowX; column <= highX && column < width; column++) {
      const chunk = u8add(row * 15, column);
      if (chunk !== own && touches(x, y, column, row)) out.push(chunk);
    }
  }
  return out;
}

// ---- A pack's goblins (`PackPlacementTrait::member`) ------------------------------------------

/** The tile of the chunk at index `k` of `OFFSETS` from `tile`; `odd` when its global row is odd. */
export function member(tile: number, k: number, odd: boolean): number | undefined {
  const row = Math.floor(tile / 15);
  const column = tile % 15;
  const [dr, dq] =
    k < 3
      ? [0, k + 2]
      : k < 7
        ? [1, k - 2]
        : k < 12
          ? [2, k - 7]
          : k < 16
            ? [3, k - 12]
            : [4, k - 16];
  const half = odd ? Math.floor((dr + 1) / 2) : Math.floor(dr / 2);
  const x = column + dq + half;
  const y = row + dr;
  if (x < 3 || x > 17 || y < 2 || y > 16) return undefined;
  return (y - 2) * 15 + x - 3;
}

// ---- The `Serde` of the vectors ---------------------------------------------------------------

/** A reader of a `Serde` encoding, one felt at a time. */
class Felts {
  private at = 0;
  constructor(private readonly felts: readonly bigint[]) {}

  felt(): bigint {
    const value = this.felts[this.at++];
    if (value === undefined) throw new RangeError(`the encoding ends at felt ${this.at - 1}`);
    return value;
  }

  int(type: IntType): number {
    return Number(fromFelt(type, this.felt()));
  }

  span<T>(read: () => T): T[] {
    return Array.from({ length: this.int(u32) }, read);
  }

  done(): void {
    if (this.at !== this.felts.length) {
      throw new RangeError(`${this.felts.length - this.at} felts left after the encoding`);
    }
  }
}

function readObject(r: Felts): PlacedObject {
  return { tile: r.int(u8), kind: r.int(u8), state: r.int(u8), param: r.int(u16) };
}

function readSite(r: Felts): Site {
  return {
    target: r.int(u8),
    biome: r.int(u8),
    level_min: r.int(u8),
    level_max: r.int(u8),
    width: r.int(u8),
    height: r.int(u8),
    entry_chunk: r.int(u8),
    chunk_set: r.felt(),
    west: r.felt(),
    north: r.felt(),
    masks: r.span(() => [r.int(u8), r.felt()]),
    anchors: r.span(() => [r.int(u8), r.int(u8)]),
    quotas: Array.from({ length: 6 }, () => ({
      kind: r.int(u8),
      param: r.int(u16),
      count: r.int(u8),
    })),
    tasks: r.span(() => ({ task: r.int(u32), kind: r.int(u8), param: r.int(u16) })),
    spawn: {
      spawns: Array.from({ length: 7 }, () => ({ template: r.int(u16), weight: r.int(u8) })),
      density: r.int(u8),
    },
    packs: r.span(() => [
      r.int(u16),
      {
        castes: Array.from({ length: 5 }, () => ({
          caste: r.int(u16),
          min: r.int(u8),
          max: r.int(u8),
        })),
        level: r.int(i8),
      },
    ]),
    pieces: r.span(() => [
      r.int(u16),
      {
        walls: r.felt(),
        packs: Array.from({ length: 2 }, () => ({ tile: r.int(u8), template: r.int(u16) })),
        objects: Array.from({ length: 3 }, () => readObject(r)),
      },
    ]),
  };
}

function readProgress(r: Felts): Progress {
  return {
    revealed: r.felt(),
    count: r.int(u8),
    open_edges: r.int(u8),
    left: Array.from({ length: 14 }, () => r.int(u8)),
    entropy: r.felt(),
  };
}

function readTerrain(r: Felts): Terrain {
  return { walls: r.felt(), edges: r.int(u8) };
}

/** The arguments of `RevealTrait::reveal` from their `Serde`: site, progress, instance, known, chunks. */
export function revealFromFelts(
  felts: readonly bigint[],
): [Site, Progress, bigint, [number, Terrain][], number[]] {
  const r = new Felts(felts);
  const site = readSite(r);
  const progress = readProgress(r);
  const instance = r.felt();
  const known = r.span((): [number, Terrain] => [r.int(u8), readTerrain(r)]);
  const asked = r.span(() => r.int(u8));
  r.done();
  return [site, progress, instance, known, asked];
}

export function progressToFelts(progress: Progress): bigint[] {
  if (progress.left.length !== 14) throw new RangeError("a progress holds 14 quotas");
  return [
    progress.revealed,
    BigInt(progress.count),
    BigInt(progress.open_edges),
    ...progress.left.map(BigInt),
    progress.entropy,
  ];
}

/** `Span<Revealed>`'s `Serde`: its length, then each chunk, terrain and features. */
export function revealedToFelts(revealed: readonly Revealed[]): bigint[] {
  const out = [BigInt(revealed.length)];
  for (const { chunk, terrain, features } of revealed) {
    out.push(BigInt(chunk), terrain.walls, BigInt(terrain.edges));
    for (const p of features.packs) {
      out.push(...[p.tile, p.template, p.level, p.count, p.offsets, p.alert].map(BigInt));
    }
    for (const o of features.objects) out.push(...[o.tile, o.kind, o.state, o.param].map(BigInt));
    out.push(BigInt(features.touched));
  }
  return out;
}

/** `Option<u8>`'s `Serde`: `[0, value]` for `Some`, `[1]` for `None`. */
export function optionToFelts(value: number | undefined): bigint[] {
  return value === undefined ? [1n] : [0n, toFelt(u8, BigInt(value))];
}
