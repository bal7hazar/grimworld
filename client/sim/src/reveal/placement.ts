// The quotas, the band and the placement of a reveal: the mirror of
// `contracts/logic/src/types/reveal/placement.cairo` (`PlacementTrait`, ENG-05, ENG-05b, ENG-10b),
// whose documentation holds the rules and their reasons. Only what `RevealTrait::reveal` calls is
// mirrored: a quota's hosts are drawn at `create` (`hosts`, `floor_hosts`) and reach the reveal in
// `Site.masks`, above each chunk's board, so they are inputs here.

import { add, mul, narrow, sub, u16, u32, u8 } from "../felt";
import { type Rng, draw } from "../hexx";
import { CAVE, RUIN, count, has, minus, nth, pow } from "./board";

/** Quotas of an instance: the location's 6, then 8 for the snapshotted tasks. */
export const QUOTAS = 14;
export const LOCATION_QUOTAS = 6;
/** Draws of a tile by rejection before the exact draw. */
export const TRIES = 16;
/** The spine's core: rows and columns 3 to 11 of row 7 and column 7. */
export const CORE = 0x100020004000801ff002000400080010000000000000n;
/** The tiles within 2 of tile 32, itself left out, its global row even and odd. */
export const NEAR_EVEN = 0xe001e006c007800en;
export const NEAR_ODD = 0xe003c006c00f000en;
export const MAX_PACKS_PER_CHUNK = 2;
export const MAX_PACK_SIZE = 5;
export const MAX_OBJECTS_PER_CHUNK = 3;
/** `content::CRITERION_REACH_LANDMARK`: a task to reach a landmark. */
export const CRITERION_REACH_LANDMARK = 2;

/** `models::quotas::kind`. */
export const quota = {
  EXIT: 1,
  HEART: 2,
  VEIN: 3,
  COLLECTOR: 4,
  LANDMARK: 5,
  SET_PIECE: 6,
} as const;

/** `models::chunk::object`. */
export const object = {
  NONE: 0,
  CHEST: 1,
  VEIN: 2,
  NODE: 3,
  TRAP: 4,
  COLLECTOR: 5,
  LANDMARK: 6,
  LEVER: 7,
  EXIT: 8,
  PLACED_TRAP: 9,
} as const;

export type Quota = { kind: number; param: number; count: number };
export type TaskEntry = { task: number; kind: number; param: number };
export type Spawn = { template: number; weight: number };
export type SpawnTable = { spawns: Spawn[]; density: number };
export type PackCaste = { caste: number; min: number; max: number };
/** A pack template; `level` is an `i8`, the offset from the band. */
export type Pack = { castes: PackCaste[]; level: number };
export type SetPack = { tile: number; template: number };
export type PlacedObject = { tile: number; kind: number; state: number; param: number };
export type SetPiece = { walls: bigint; packs: SetPack[]; objects: PlacedObject[] };
export type PackPlacement = {
  tile: number;
  template: number;
  level: number;
  count: number;
  offsets: number;
  alert: number;
};

/** What the reveal reads of a location (`types::reveal::Site`). */
export type Site = {
  target: number;
  biome: number;
  level_min: number;
  level_max: number;
  width: number;
  height: number;
  entry_chunk: number;
  chunk_set: bigint;
  west: bigint;
  north: bigint;
  masks: [number, bigint][];
  anchors: [number, number][];
  quotas: Quota[];
  tasks: TaskEntry[];
  spawn: SpawnTable;
  packs: [number, Pack][];
  pieces: [number, SetPiece][];
};

const u8add = (a: number, b: number): number => Number(add(u8, BigInt(a), BigInt(b)));
const u8sub = (a: number, b: number): number => Number(sub(u8, BigInt(a), BigInt(b)));

/** `Site::total`: the chunks a location reveals in all. */
export function total(site: Site): number {
  if (site.target !== 0) return site.target;
  if (site.chunk_set === 0n) return Number(mul(u8, BigInt(site.width), BigInt(site.height)));
  return count(site.chunk_set);
}

/** `Site::pack`: the template `id`, the last entry that names it. */
export function sitePack(site: Site, id: number): Pack | undefined {
  let found: Pack | undefined;
  for (const [at, pack] of site.packs) if (at === id && id !== 0) found = pack;
  return found;
}

/** `Site::piece`: the set piece `id`, the last entry that names it. */
export function sitePiece(site: Site, id: number): SetPiece | undefined {
  let found: SetPiece | undefined;
  for (const [at, piece] of site.pieces) if (at === id && id !== 0) found = piece;
  return found;
}

/** `PackTrait::bounds`: the castes' minimum and maximum, capped at `MAX_PACK_SIZE`. */
export function bounds(pack: Pack): [number, number] {
  let low = 0;
  let high = 0;
  for (const entry of pack.castes) {
    if (entry.caste !== 0) {
      low += entry.min;
      high += entry.max;
    }
  }
  high = Math.min(high, MAX_PACK_SIZE);
  low = Math.min(low, high);
  return [low, high];
}

/** `SpawnTableTrait::weight`. */
export function weight(spawn: SpawnTable): number {
  let total = 0n;
  for (const entry of spawn.spawns) {
    if (entry.template !== 0) total = add(u16, total, BigInt(entry.weight));
  }
  return Number(total);
}

/** `SpawnTableTrait::pick`: the template whose weight holds `draw`. */
export function pick(spawn: SpawnTable, draw: number): number {
  let left = draw;
  let template = 0;
  for (const entry of spawn.spawns) {
    if (template === 0 && entry.template !== 0) {
      if (left < entry.weight) template = entry.template;
      else left -= entry.weight;
    }
  }
  return template;
}

/** What quota slot `i` places: `[kind, param]`, `[0, 0]` for nothing. */
export function slot(site: Site, i: number): [number, number] {
  if (i < LOCATION_QUOTAS) {
    const entry = site.quotas[i]!;
    return [entry.kind, entry.param];
  }
  const task = site.tasks[i - LOCATION_QUOTAS];
  if (task === undefined) return [0, 0];
  return task.kind === CRITERION_REACH_LANDMARK ? [quota.LANDMARK, task.param] : [0, 0];
}

/** What each quota starts with: the location's counts, then one for each task that places. */
export function start(site: Site): number[] {
  const left = site.quotas.map((entry) => (entry.kind === 0 ? 0 : entry.count));
  for (let i = LOCATION_QUOTAS; i < QUOTAS; i++) left.push(slot(site, i)[0] === 0 ? 0 : 1);
  return left;
}

/** Bit `i`: quota `i` is due in this chunk, by the hosts above `mask`'s board; one draw a quota. */
export function due(site: Site, left: readonly number[], mask: bigint, rng: Rng): number {
  const all = total(site);
  const bound = all === 0 ? 1 : all;
  const counts = site.quotas.map((entry) => (entry.kind === 0 ? 0 : entry.count));
  for (const task of site.tasks) counts.push(task.kind === CRITERION_REACH_LANDMARK ? 1 : 0);
  let due = 0;
  let bit = 1;
  let host = 225;
  for (const [i, count] of counts.entries()) {
    if (i >= left.length) break;
    if (count !== 0) {
      draw(rng, bound);
      if (left[i] !== 0 && has(mask, host)) due += bit;
    }
    bit = Number(mul(u16, BigInt(bit), 2n));
    host = u8add(host, 1);
  }
  return due;
}

/** `left` less one for each quota placed. */
export function spend(left: readonly number[], placed: number): number[] {
  return left.map((value, i) => u8sub(value, (placed >> i) & 1));
}

/** The band's level of a chunk. */
export function level(site: Site, chunk: number): number {
  const cy = Math.floor(chunk / 15);
  const cx = chunk % 15;
  const ey = Math.floor(site.entry_chunk / 15);
  const ex = site.entry_chunk % 15;
  const distance = Math.abs(cx - ex) + Math.abs(cy - ey);
  const far = site.target !== 0 ? site.target - 1 : site.width + site.height - 2;
  const low = site.level_min;
  const high = site.level_max;
  if (far === 0 || high <= low) return low;
  const held = Math.min(distance, far);
  return u8add(low, Number(narrow(u8, BigInt(Math.trunc(((high - low) * held) / far)))));
}

/** A pack's level: the band's plus its template's offset, held in the location's band. */
export function pack_level(site: Site, level: number, offset: number): number {
  const sum = level + offset;
  return Math.min(Math.max(sum, site.level_min), site.level_max);
}

/** What a reveal places in a chunk, built in order. */
export type Placement = {
  packs: PackPlacement[];
  objects: PlacedObject[];
  allowed: bigint;
  placed: number;
  odd: boolean;
  level: number;
};

/** One tile drawn among those allowed, then taken: `TRIES` draws by rejection, then the exact draw. */
export function tile(placement: Placement, rng: Rng): number | undefined {
  if (placement.allowed === 0n) return undefined;
  let found: number | undefined;
  for (let tries = 0; found === undefined && tries < TRIES; tries++) {
    const drawn = draw(rng, 225);
    if (has(placement.allowed, drawn)) found = drawn;
  }
  if (found === undefined) {
    found = nth(placement.allowed, draw(rng, count(placement.allowed)));
  }
  placement.allowed -= pow(found);
  return found;
}

/** Takes `tile` if it is allowed. */
export function take(placement: Placement, tile: number): boolean {
  if (tile >= 225 || !has(placement.allowed, tile)) return false;
  placement.allowed -= pow(tile);
  return true;
}

/** An object on a drawn tile, if there is room. */
export function placeObject(placement: Placement, rng: Rng, kind: number, param: number): boolean {
  if (placement.objects.length >= MAX_OBJECTS_PER_CHUNK) return false;
  const at = tile(placement, rng);
  if (at === undefined) return false;
  placement.objects.push({ tile: at, kind, state: 0, param });
  return true;
}

/** The interior tiles within 2 of `tile`, itself left out; `odd` when its global row is odd. */
export function near(tile: number, odd: boolean): bigint {
  const template = odd ? NEAR_ODD : NEAR_EVEN;
  return tile >= 32 ? template * pow(tile - 32) : template / pow(32 - tile);
}

/** The index in `OFFSETS` of `member`, a tile within 2 of the pack's tile at `row` and `column`. */
export function offset(member: number, row: number, column: number, odd: boolean): number {
  const y = Math.floor(member / 15);
  const x = member % 15;
  const dr = u8sub(u8add(y, 2), row);
  const half = odd ? Math.floor((dr + 1) / 2) : Math.floor(dr / 2);
  const start = [1, 5, 10, 15][dr] ?? 19;
  return u8sub(u8sub(u8add(x, start), column), half);
}

/** A pack of `template`, on `at` or on a drawn tile, if there is room: at least one goblin. */
export function placePack(
  placement: Placement,
  rng: Rng,
  site: Site,
  template: number,
  at: number | undefined,
): boolean {
  if (placement.packs.length >= MAX_PACKS_PER_CHUNK) return false;
  const pack = sitePack(site, template);
  if (pack === undefined) return false;
  const [floor, high] = bounds(pack);
  if (high === 0) return false;
  const low = floor === 0 ? 1 : floor;
  const size = u8add(low, draw(rng, u8sub(high, low) + 1));
  let here: number;
  if (at !== undefined) {
    if (!take(placement, at)) return false;
    here = at;
  } else {
    const drawn = tile(placement, rng);
    if (drawn === undefined) return false;
    here = drawn;
  }
  const row = Math.floor(here / 15);
  const column = here % 15;
  const odd = (row % 2 === 1) !== placement.odd;
  let pool = near(here, odd) & placement.allowed;
  let left = count(pool);
  let offsets = 9n;
  let goblins = 1;
  let shift = 32n;
  while (goblins !== size && left !== 0) {
    const member = nth(pool, draw(rng, left));
    const bit = pow(member);
    pool -= bit;
    placement.allowed -= bit;
    offsets = add(u32, offsets, mul(u32, BigInt(offset(member, row, column, odd)), shift));
    shift = mul(u32, shift, 32n);
    goblins += 1;
    left -= 1;
  }
  const alert = draw(rng, 2);
  const packLevel = pack_level(site, placement.level, pack.level);
  placement.packs.push({
    tile: here,
    template,
    level: packLevel,
    count: goblins,
    offsets: Number(offsets),
    alert,
  });
  return true;
}

/** `PlacementTrait::bit`: `2^i`. */
const bit = (i: number): number => 2 ** i;

/** Places everything of a chunk: `due`, the quotas drawn for it; `piece`, the set piece laid. */
export function place(
  site: Site,
  chunk: number,
  due: number,
  piece: [number, SetPiece] | undefined,
  allowed: bigint,
  odd: boolean,
  rng: Rng,
): Placement {
  const placement: Placement = {
    packs: [],
    objects: [],
    allowed,
    placed: 0,
    odd,
    level: level(site, chunk),
  };
  // A dungeon's exit and Heart first, each on a tile of the spine's core less the piece's tiles
  let first = 0;
  if (site.target !== 0) {
    let reserved = 0n;
    if (piece !== undefined) {
      for (const entry of piece[1].packs) if (entry.template !== 0) reserved |= pow(entry.tile);
      for (const entry of piece[1].objects) if (entry.kind !== 0) reserved |= pow(entry.tile);
    }
    let core = minus(CORE, reserved);
    for (let i = 0; i < QUOTAS; i++) {
      if (((due >> i) & 1) !== 1) continue;
      const [kind, param] = slot(site, i);
      if (kind !== quota.EXIT && kind !== quota.HEART) continue;
      const before = placement.allowed;
      placement.allowed = core;
      const drawn = tile(placement, rng);
      core = placement.allowed;
      placement.allowed = minus(before, reserved);
      let done = false;
      if (drawn !== undefined) {
        if (kind === quota.EXIT) {
          if (take(placement, drawn)) {
            placement.objects.push({ tile: drawn, kind: object.EXIT, state: 0, param });
            done = true;
          }
        } else {
          const band = placement.level;
          placement.level = site.level_max;
          done = placePack(placement, rng, site, param, drawn);
          placement.level = band;
        }
      }
      placement.allowed = placement.allowed | (before & reserved);
      if (done) placement.placed += bit(i);
      first += bit(i);
    }
  }
  // The set piece's own packs and objects
  if (piece !== undefined) {
    const [pieceSlot, set] = piece;
    placement.placed += bit(pieceSlot);
    for (const entry of set.packs) {
      if (entry.template !== 0) placePack(placement, rng, site, entry.template, entry.tile);
    }
    for (const entry of set.objects) {
      if (
        entry.kind !== 0 &&
        placement.objects.length < MAX_OBJECTS_PER_CHUNK &&
        take(placement, entry.tile)
      ) {
        placement.objects.push({ ...entry, state: 0 });
      }
    }
  }
  // The quotas due, in order, but those laid first
  const rest = due - first;
  for (let i = 0; i < QUOTAS; i++) {
    if (((rest >> i) & 1) !== 1) continue;
    const [kind, param] = slot(site, i);
    let done = false;
    if (kind === quota.EXIT) done = placeObject(placement, rng, object.EXIT, param);
    else if (kind === quota.VEIN) done = placeObject(placement, rng, object.VEIN, 0);
    else if (kind === quota.COLLECTOR) done = placeObject(placement, rng, object.COLLECTOR, param);
    else if (kind === quota.LANDMARK) done = placeObject(placement, rng, object.LANDMARK, param);
    else if (kind === quota.HEART) {
      const band = placement.level;
      placement.level = site.level_max;
      done = placePack(placement, rng, site, param, undefined);
      placement.level = band;
    }
    if (done) placement.placed += bit(i);
  }
  // The spawn table's two slots
  const total = weight(site.spawn);
  for (let slot = 0; slot < MAX_PACKS_PER_CHUNK; slot++) {
    const roll = draw(rng, 256);
    const picked = total === 0 ? 0 : draw(rng, total);
    if (total !== 0 && roll < site.spawn.density) {
      placePack(placement, rng, site, pick(site.spawn, picked), undefined);
    }
  }
  // The objects by frequency
  const chest = draw(rng, 6) === 0;
  const node = draw(rng, 4) === 0;
  const trap = draw(rng, 3) === 0;
  if (chest) placeObject(placement, rng, object.CHEST, placement.level);
  if (node && site.target === 0) placeObject(placement, rng, object.NODE, 0);
  if (trap && (site.biome === RUIN || site.biome === CAVE)) {
    placeObject(placement, rng, object.TRAP, 0);
  }
  return placement;
}
