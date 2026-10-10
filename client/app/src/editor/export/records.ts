/**
 * The on-chain records of a map, packed as ENG-08's converter packs them (CLI-09c): a port of
 * `tools/map-format/records.py` (track game's, promoted from SPK-16 by ENG-09), line for line, with the same refusal codes. A record is a list of felts
 * (`bigint`); every part carries `LIVE` (bit 250). Tiles are `15 row + column` in their chunk,
 * chunks `15 cy + cx` in the location (ADR-0006 §4).
 *
 * A tool's port, not a game rule (mandate §6): the converter and the Registry decide; this file
 * must give their verdicts, and its tests hold it to the converter's outputs and cases.
 */

export const LIVE = 1n << 250n;
export const BOARD = (1n << 225n) - 1n;

// Kinds (`content.cairo`; 26-28 ENG-08's, built by ENG-09).
export const LOCATION = 2;
export const OUTLINE = 3;
export const GATE = 4;
export const QUOTAS = 5;
export const SET_PIECE = 24;
export const ZONE_CHUNK = 26;
export const BRIDGE = 27;
export const CANDIDATES = 28;
export const KIND_NAMES: Readonly<Record<number, string>> = {
  [LOCATION]: "LOCATION",
  [OUTLINE]: "OUTLINE",
  [GATE]: "GATE",
  [QUOTAS]: "QUOTAS",
  7: "PACK",
  [SET_PIECE]: "SET_PIECE",
  [ZONE_CHUNK]: "ZONE_CHUNK",
  [BRIDGE]: "BRIDGE",
  [CANDIDATES]: "CANDIDATES",
};
export const CHUNK_SET = 255;

export const LOCATION_KINDS = { town: 1, outpost: 2, zone: 3, dungeon: 4 } as const;
export const BIOMES = { meadow: 1, forest: 2, cave: 3, ruin: 4 } as const;
export const QUOTA_KINDS = {
  exit: 1,
  heart: 2,
  vein: 3,
  collector: 4,
  landmark: 5,
  setPiece: 6,
} as const;
export const HEART = 2;
export const EXIT = 1;
export const VEIN_Q = 3;
export const COLLECTOR_Q = 4;
export const LANDMARK_Q = 5;
export const SET_PIECE_Q = 6;
export const OBJECTS = {
  chest: 1,
  vein: 2,
  node: 3,
  trap: 4,
  collector: 5,
  landmark: 6,
  lever: 7,
  exit: 8,
} as const;
const AUTHORED_OBJECTS = new Set([1, 3, 4, 6, 7]);
export const GATE_KINDS = { hub: 1, link: 2, floor: 3, rift: 4 } as const;
export const GENERATED = 0;
export const AUTHORED = 1;
export const MAX_DRAWS = 640;

/** A record or an export refused, with the code the Cairo check panics with. */
export class Refused extends Error {
  constructor(
    readonly code: string,
    readonly detail = "",
  ) {
    super(detail ? `${code}: ${detail}` : code);
  }
}

export function fits(value: bigint, bits: number, code: string): bigint {
  if (value < 0n || value >= 1n << BigInt(bits)) {
    throw new Refused(code, `${value} does not fit ${bits} bits`);
  }
  return value;
}

export const has = (bits: bigint, i: number): boolean => ((bits >> BigInt(i)) & 1n) === 1n;
export const bit = (i: number): bigint => 1n << BigInt(i);

export function count(bits: bigint): number {
  let n = 0;
  for (let b = bits; b > 0n; b >>= 1n) n += Number(b & 1n);
  return n;
}

const B = BigInt;

// --- the records ---------------------------------------------------------------------------------

export interface LocationFields {
  kind: number;
  region: number;
  biome: number;
  level_min: number;
  level_max: number;
  rank: number;
  width: number;
  height: number;
  target: number;
  floors: number;
  next_floor: number;
  spawn_table: number;
  sealed: boolean;
  entry_chunk: number;
  entry_tile: number;
  map?: number;
}

export interface Spawn {
  tile: number;
  template: number;
}

export interface ChunkObject {
  tile: number;
  kind: number;
  state?: number;
  param: number;
}

export interface ZoneChunk {
  walls: bigint;
  spawns: Spawn[];
  objects: ChunkObject[];
  tiles: number[];
  bridges: number;
  gates: [number, number];
}

export interface GateFields {
  source: number;
  destination: number;
  anchor_chunk: number;
  anchor_tile: number;
  entry_chunk: number;
  entry_tile: number;
  kind: number;
  rank: number;
  quest: number;
}

export interface BridgeFields {
  deck: bigint;
  ends: [number, number];
}

export type Quota = readonly [kind: number, param: number, count: number];

/** `LocationRecord::pack`, and the marker at 144-151 (ENG-08). */
export function packLocation(f: LocationFields): bigint[] {
  const low =
    B(f.kind) |
    (B(f.region) << 8n) |
    (B(f.biome) << 24n) |
    (B(f.level_min) << 32n) |
    (B(f.level_max) << 40n) |
    (B(f.rank) << 48n) |
    (B(f.width) << 56n) |
    (B(f.height) << 64n) |
    (B(f.target) << 72n) |
    (B(f.floors) << 80n) |
    (B(f.next_floor) << 88n) |
    (B(f.spawn_table) << 104n) |
    (B(Number(f.sealed)) << 120n);
  const high = B(f.entry_chunk) | (B(f.entry_tile) << 8n) | (B(f.map ?? GENERATED) << 16n);
  // The set-piece lanes, all 0: an exported zone names none.
  return [low | (high << 128n) | LIVE, LIVE];
}

export function packOutline(bits: bigint): bigint[] {
  return [fits(bits, 225, "outline: above bit 224") | LIVE];
}

export function packGate(f: GateFields): bigint[] {
  const low =
    B(f.source) |
    (B(f.destination) << 16n) |
    (B(f.anchor_chunk) << 32n) |
    (B(f.anchor_tile) << 40n) |
    (B(f.entry_chunk) << 48n) |
    (B(f.entry_tile) << 56n) |
    (B(f.kind) << 64n) |
    (B(f.rank) << 72n) |
    (B(f.quest) << 80n);
  return [low | LIVE];
}

/** Six `(kind, param, count)`, quota `i` at `32 i` (low limb) and `128 + 32 (i - 4)`. */
export function packQuotas(quotas: readonly Quota[]): bigint[] {
  const all = [...quotas, ...Array<Quota>(Math.max(0, 6 - quotas.length)).fill([0, 0, 0])];
  let word = 0n;
  all.forEach(([kind, param, n], i) => {
    const bits = B(kind) | (B(param) << 8n) | (B(n) << 24n);
    word |= bits << B(i < 4 ? 32 * i : 128 + 32 * (i - 4));
  });
  return [word | LIVE];
}

const objectBits = (o: ChunkObject): bigint =>
  B(o.tile) | (B(o.kind) << 8n) | (B(o.state ?? 0) << 12n) | (B(o.param) << 16n);

const EMPTY_SPAWN: Spawn = { tile: 0, template: 0 };
const EMPTY_OBJECT: ChunkObject = { tile: 0, kind: 0, param: 0 };
const padded = <T>(list: readonly T[], n: number, empty: T): T[] => [
  ...list,
  ...Array<T>(Math.max(0, n - list.length)).fill(empty),
];

/** `ZoneChunkRecord::pack` (src/zone_chunk.cairo). */
export function packZoneChunk(c: ZoneChunk): bigint[] {
  const walls = fits(c.walls, 225, "zone chunk: walls above 224");
  if (c.spawns.length > 2 || c.objects.length > 3) {
    throw new Refused("zone chunk: over its caps", "more than the layout holds");
  }
  const spawns = padded(c.spawns, 2, EMPTY_SPAWN);
  const objects = padded(c.objects, 3, EMPTY_OBJECT);
  const low =
    B(spawns[0]!.tile) |
    (B(spawns[0]!.template) << 8n) |
    (B(spawns[1]!.tile) << 24n) |
    (B(spawns[1]!.template) << 32n) |
    (objectBits(objects[0]!) << 48n) |
    (objectBits(objects[1]!) << 80n);
  let high = objectBits(objects[2]!);
  c.tiles.forEach((tile, i) => {
    high |= B(tile) << B(32 + 8 * i);
  });
  high |= fits(B(c.bridges), 4, "zone chunk: bridges above 15") << 80n;
  high |= (B(c.gates[0]) << 84n) | (B(c.gates[1]) << 100n);
  return [walls | LIVE, low | (high << 128n) | LIVE];
}

export function unpackZoneChunk(parts: readonly bigint[]): ZoneChunk {
  const walls = parts[0]! - LIVE;
  const word = parts[1]! - LIVE;
  const low = word & ((1n << 128n) - 1n);
  const high = word >> 128n;
  const n = (v: bigint) => Number(v);
  const obj = (b: bigint): ChunkObject => ({
    tile: n(b & 0xffn),
    kind: n((b >> 8n) & 0xfn),
    state: n((b >> 12n) & 0xfn),
    param: n((b >> 16n) & 0xffffn),
  });
  const spawns = [
    { tile: n(low & 0xffn), template: n((low >> 8n) & 0xffffn) },
    { tile: n((low >> 24n) & 0xffn), template: n((low >> 32n) & 0xffffn) },
  ];
  const objects = [obj((low >> 48n) & 0xffffffffn), obj((low >> 80n) & 0xffffffffn)];
  objects.push(obj(high & 0xffffffffn));
  return {
    walls,
    spawns: spawns.filter((s) => s.template),
    objects: objects.filter((o) => o.kind),
    tiles: Array.from({ length: 6 }, (_, i) => n((high >> B(32 + 8 * i)) & 0xffn)),
    bridges: n((high >> 80n) & 0xfn),
    gates: [n((high >> 84n) & 0xffffn), n((high >> 100n) & 0xffffn)],
  };
}

export function packBridge(b: BridgeFields): bigint[] {
  const deck = fits(b.deck, 225, "bridge: deck above bit 224");
  const [a, e] = b.ends;
  return [deck | (B(a) << 225n) | (B(e) << 233n) | LIVE];
}

export function packCandidates(sets: readonly bigint[]): bigint[] {
  return padded(sets, 3, 0n).map((s) => fits(s, 225, "candidates: above bit 224") | LIVE);
}

/** `SetPieceRecord::pack`: walls, then 2 packs and 3 objects. */
export function packSetPiece(p: { walls: bigint; spawns: Spawn[]; objects: ChunkObject[] }) {
  const spawns = padded(p.spawns, 2, EMPTY_SPAWN);
  const objects = padded(p.objects, 3, EMPTY_OBJECT);
  const low =
    B(spawns[0]!.tile) |
    (B(spawns[0]!.template) << 8n) |
    (B(spawns[1]!.tile) << 24n) |
    (B(spawns[1]!.template) << 32n) |
    (objectBits(objects[0]!) << 48n) |
    (objectBits(objects[1]!) << 80n);
  return [
    fits(p.walls, 225, "set piece: walls") | LIVE,
    low | (objectBits(objects[2]!) << 128n) | LIVE,
  ];
}

// --- hexes ---------------------------------------------------------------------------------------

export function rectangle(width: number, height: number): bigint {
  const row = (1n << B(width)) - 1n;
  let out = 0n;
  for (let cy = 0; cy < height; cy++) out |= row << B(15 * cy);
  return out;
}

/**
 * Odd-r, `x` growing West as `hexx`'s `+1`: an even row's North and South neighbours are `x - 1`
 * and `x`, an odd row's `x` and `x + 1` (`board.cairo`, `dilate`).
 */
export function neighbours(x: number, y: number): [number, number][] {
  const d = ((y % 2) + 2) % 2 === 1 ? 0 : -1;
  return [
    [x - 1, y],
    [x + 1, y],
    [x + d, y - 1],
    [x + d + 1, y - 1],
    [x + d, y + 1],
    [x + d + 1, y + 1],
  ];
}

const divmod = (a: number, b: number): [number, number] => [Math.floor(a / b), a % b];

/** `BoardTrait::dilate` on one chunk: the tiles and their neighbours within it. */
export function dilate(tiles: bigint, chunk: number): bigint {
  const cy = Math.floor(chunk / 15);
  let out = tiles;
  for (let t = 0; t < 225; t++) {
    if (!has(tiles, t)) continue;
    const [row, col] = divmod(t, 15);
    for (const [nx, ny] of neighbours(col, 15 * cy + row)) {
      const nrow = ny - 15 * cy;
      if (nx >= 0 && nx < 15 && nrow >= 0 && nrow < 15) out |= bit(15 * nrow + nx);
    }
  }
  return out;
}

// --- the Registry's checks (src/checks.cairo) -----------------------------------------------------

/** The converter's zone: what each write reads (`records.check_zone`'s `z`). */
export interface Zone {
  id: number;
  location: LocationFields;
  chunk_set: bigint;
  masks: Map<number, bigint>;
  chunks: Map<number, ZoneChunk>;
  quotas: Quota[];
  candidates: bigint[];
  /** The Heart quotas' template bounds `(min, max)`, null when the manifest has none. */
  hearts: Map<number, readonly [number, number] | null>;
  gates: Map<number, GateFields>;
  bridges: Map<number, BridgeFields[]>;
}

const floorAt = (walls: bigint, tile: number) => tile < 225 && !has(walls, tile);

function assertSet(chunkSet: bigint, width: number, height: number): void {
  if (chunkSet & ~rectangle(width, height)) throw new Refused("zone: set outside rectangle");
}

function assertOutline(chunk: number, walls: bigint, chunkSet: bigint, mask: bigint): void {
  if (!has(chunkSet, chunk)) throw new Refused("zone: chunk not in the set", `chunk ${chunk}`);
  if (mask && BOARD & ~mask & ~walls) {
    throw new Refused("zone: mask disagrees", `chunk ${chunk}`);
  }
}

function assertChunk(
  record: ZoneChunk,
  chunk: number,
  candidates: readonly bigint[],
  quotas: readonly Quota[],
): void {
  const { walls } = record;
  const taken = new Set<number>();
  let packs = 0;
  let objects = 0;
  const take = (tile: number) => {
    // Walkable and in the interior (rows and columns 1-13): a pack's goblins stand within 2 of its
    // tile (`Placement::near`'s precondition, ENG-09)
    const row = Math.floor(tile / 15);
    const col = tile % 15;
    if (!(floorAt(walls, tile) && row > 0 && row < 14 && col > 0 && col < 14)) {
      throw new Refused("zone chunk: tile not floor", `chunk ${chunk} tile ${tile}`);
    }
    if (taken.has(tile)) throw new Refused("zone chunk: tile taken", `chunk ${chunk} tile ${tile}`);
    taken.add(tile);
  };
  for (const s of record.spawns) {
    if (s.template === 0) {
      if (s.tile) throw new Refused("zone chunk: empty with a value");
    } else {
      take(s.tile);
      packs += 1;
    }
  }
  for (const o of record.objects) {
    if (o.kind === 0) {
      if (o.tile || o.state || o.param) throw new Refused("zone chunk: empty with a value");
    } else {
      if (!AUTHORED_OBJECTS.has(o.kind) || o.state) {
        throw new Refused("zone chunk: object", `kind ${o.kind}`);
      }
      take(o.tile);
      objects += 1;
    }
  }
  for (let i = 0; i < 6; i++) {
    const tile = record.tiles[i]!;
    if (i < candidates.length && has(candidates[i]!, chunk)) {
      take(tile);
      if (quotas[i]![0] === HEART) packs += 1;
      else objects += 1;
    } else if (tile) {
      throw new Refused("zone chunk: empty with a value", `quota ${i}`);
    }
  }
  if (packs > 2 || objects > 3) throw new Refused("zone chunk: over its caps", `chunk ${chunk}`);
}

function assertEntry(entryTile: number, entryWalls: bigint): void {
  if (!floorAt(entryWalls, entryTile)) throw new Refused("zone: entry not floor");
}

function assertGate(gateId: number, gate: GateFields, anchor: ZoneChunk): void {
  if (!floorAt(anchor.walls, gate.anchor_tile)) {
    throw new Refused("zone: gate anchor not floor", `gate ${gateId}`);
  }
  if (!anchor.gates.includes(gateId)) throw new Refused("zone: gate not indexed", `gate ${gateId}`);
}

function assertCandidates(sets: readonly bigint[], chunkSet: bigint): void {
  for (const s of sets) if (s & ~chunkSet) throw new Refused("candidates: outside the set");
}

export function draws(n: number, left: number): number {
  if (n >= left) return 0;
  return 2 * n > left ? left - n : n;
}

function assertQuotas(z: Zone): void {
  const members = count(z.chunk_set);
  let total = 0;
  z.quotas.forEach(([kind, , n], i) => {
    if (kind === 0) return;
    if (kind === EXIT || kind === SET_PIECE_Q) throw new Refused("zone: quota kind", `quota ${i}`);
    if (n > members) throw new Refused("zone: count above members", `quota ${i}`);
    const left = i < z.candidates.length ? count(z.candidates[i]!) : 0;
    if (n > left) throw new Refused("zone: count above candidates", `quota ${i}`);
    total += draws(n, left);
    if (kind === HEART) {
      const bounds = z.hearts.get(i);
      if (!bounds || bounds[0] < 1 || bounds[1] < 1) {
        throw new Refused("zone: heart template", `quota ${i}`);
      }
    }
  });
  if (total > MAX_DRAWS) throw new Refused("zone: quota draws", `${total} draws`);
}

/** R-39 (audit t-0131): an authored zone's band at most 255 levels (0 to 255 refused). */
function assertBand(l: LocationFields): void {
  if (l.level_min === 0 && l.level_max === 255) throw new Refused("zone: level band");
}

function assertFloorRectangle(l: LocationFields): void {
  if (l.kind === LOCATION_KINDS.dungeon && l.width * l.height <= l.target) {
    throw new Refused("location: floor rectangle");
  }
}

function assertBridge(bridge: BridgeFields, k: number, chunk: number, record: ZoneChunk): void {
  const { deck } = bridge;
  if (deck === 0n) throw new Refused("bridge: deck empty");
  const [a, b] = bridge.ends;
  if (!(a < 225 && b < 225 && a !== b && !has(deck, a) && !has(deck, b))) {
    throw new Refused("bridge: end");
  }
  if (k >= record.bridges) throw new Refused("bridge: index");
  if (!(floorAt(record.walls, a) && floorAt(record.walls, b))) {
    throw new Refused("bridge: end not floor");
  }
  const near = dilate(deck, chunk);
  if (!(has(near, a) && has(near, b))) throw new Refused("bridge: end not by the deck");
  // R-34 extended (ADR-0008 rule 1): every deck tile walkable in the chunk's plane
  if (deck & record.walls) throw new Refused("bridge: deck not floor");
}

/** The tiles a chunk's authored content stands on: spawn points, objects, candidate tiles. */
function content(record: ZoneChunk): Set<number> {
  const tiles = new Set<number>();
  for (const s of record.spawns) if (s.template) tiles.add(s.tile);
  for (const o of record.objects) if (o.kind) tiles.add(o.tile);
  for (const t of record.tiles) if (t) tiles.add(t);
  return tiles;
}

/**
 * R-37 (ADR-0008 rule 5): no spawn point, object, candidate tile, gate anchor or entry on a
 * bridge's deck or ends.
 */
function assertClear(bridge: BridgeFields, tiles: ReadonlySet<number>): void {
  const on = new Set<number>(bridge.ends);
  for (let t = 0; t < 225; t++) if (has(bridge.deck, t)) on.add(t);
  const hit = [...on].filter((t) => tiles.has(t)).sort((x, y) => x - y);
  if (hit.length > 0) throw new Refused("bridge: tile taken", `tiles ${hit.slice(0, 3).join(" ")}`);
}

const ascending = <V>(m: Map<number, V>): [number, V][] => [...m].sort(([a], [b]) => a - b);

/**
 * Every Registry check of an authored zone's records: the same rules as `src/checks.cairo`, run on
 * what each write reads (`records.check_zone`).
 */
export function checkZone(z: Zone): void {
  const loc = z.location;
  const anchors = new Map<number, Set<number>>();
  const anchor = (chunk: number, tile: number) =>
    anchors.set(chunk, (anchors.get(chunk) ?? new Set()).add(tile));
  for (const gate of z.gates.values()) anchor(gate.anchor_chunk, gate.anchor_tile);
  anchor(loc.entry_chunk, loc.entry_tile);
  assertBand(loc);
  assertFloorRectangle(loc);
  assertSet(z.chunk_set, loc.width, loc.height);
  assertCandidates(z.candidates, z.chunk_set);
  assertQuotas(z);
  for (const [chunk, record] of ascending(z.chunks)) {
    assertOutline(chunk, record.walls, z.chunk_set, z.masks.get(chunk) ?? 0n);
    assertChunk(record, chunk, z.candidates, z.quotas);
    (z.bridges.get(chunk) ?? []).forEach((bridge, k) => {
      assertBridge(bridge, k, chunk, record);
      assertClear(bridge, new Set([...content(record), ...(anchors.get(chunk) ?? [])]));
    });
  }
  const entry = z.chunks.get(loc.entry_chunk);
  if (!entry) throw new Refused("zone: chunk not in the set", "the entry chunk");
  assertEntry(loc.entry_tile, entry.walls);
  for (const [gateId, gate] of ascending(z.gates)) {
    const anchor = z.chunks.get(gate.anchor_chunk);
    if (!anchor) throw new Refused("zone: chunk not in the set", `gate ${gateId}'s anchor`);
    assertGate(gateId, gate, anchor);
  }
}
