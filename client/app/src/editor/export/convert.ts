import * as R from "./records";
import { KIND_TABLE, validate } from "./schema";

/**
 * ENG-08's converter (CLI-09c): an editor's export (`grimworld-export` v1) to the on-chain records
 * of its map, in the order of their writes. A port of `tools/map-format/convert.py` (track game's), with
 * the same refusals in the same order: the Registry's (`records.ts`), the content pipeline's (every
 * walkable tile reachable from the entry, the records re-assembled across their seams equal to the
 * painted map, each bridge's deck connected) and the export's own. The editor runs it as its
 * export checks and its "Export for the chain…": what it accepts and writes is what the converter
 * accepts and writes, felt for felt (`export.test.ts`).
 */

export const FORMAT = "grimworld-export";
export const VERSION = 1;
export const RECORDS_FORMAT = "grimworld-records";

/** A content manifest (OPS-01 writes it): the registry ids of the names an export uses. */
export interface Manifest {
  readonly [table: string]: unknown;
  readonly pack_bounds?: Readonly<Record<string, readonly [number, number]>>;
  /** Each location's kind (`zone`, `town`, `dungeon`…): a gate to a dungeon may stand inside. */
  readonly location_kinds?: Readonly<Record<string, string>>;
  /** Each location with a map, its `[width, height]` in chunks (R-41, ENG-R1c-1). */
  readonly location_sizes?: Readonly<Record<string, readonly [number, number]>>;
}

export type Hex = readonly [number, number];

/** The export file, as `schema.json` describes it (checked by `validate` before it is read). */
export interface ExportFile {
  format: string;
  version: number;
  editor?: string;
  kind: "zone" | "town" | "outpost" | "set_piece";
  name: string;
  location?: string;
  region?: string;
  biome?: keyof typeof R.BIOMES;
  level_min?: number;
  level_max?: number;
  rank?: number;
  spawn_table?: string | null;
  origin: { x: number; y: number };
  size: { width: number; height: number };
  rows: { y: number; x: number; terrain: string; ground?: string; outline?: string }[];
  entry?: { x: number; y: number };
  quotas?: { kind: keyof typeof R.QUOTA_KINDS; param: string | null; count: number }[];
  candidates?: { quota: number; x: number; y: number }[];
  spawns?: { template: string; x: number; y: number }[];
  features?: {
    feature: "chest" | "node" | "trap" | "landmark" | "lever";
    param?: string | null;
    x: number;
    y: number;
  }[];
  gates?: {
    gate: string;
    to: string;
    kind: keyof typeof R.GATE_KINDS;
    rank?: number;
    quest?: number;
    entry_chunk: number;
    entry_tile: number;
    x: number;
    y: number;
  }[];
  npcs?: { kind: string; x: number; y: number; facing: number }[];
  buildings?: {
    kind: string;
    footprint: Hex[];
    anchor: Hex;
    door: Hex;
    depth?: number;
    mirror?: boolean;
  }[];
  props?: {
    kind: string;
    x: number;
    y: number;
    variant?: number;
    facing?: number;
    flip?: boolean;
  }[];
  bridges?: { kind: string; deck: Hex[]; ends: [Hex, Hex] }[];
  obstacles?: { x: number; y: number; sprite: string }[];
}

/** One write: `set_record(kind, id, parts)`. */
export interface Write {
  readonly kind: number;
  readonly id: number;
  readonly parts: readonly bigint[];
  readonly what: string;
}

const ZONE_FIELDS = ["location", "region", "biome", "level_min", "level_max", "entry"] as const;
const HUB_FIELDS = ["location", "region"] as const;

/** Python's `//` and `%`: the floor and a remainder of the divisor's sign. */
const fdiv = (a: number, b: number) => Math.floor(a / b);
const fmod = (a: number, b: number) => ((a % b) + b) % b;

/** `Gate.quest: u32`, authored in the export, not named in the manifest. */
const GATE_QUEST_BITS = 32;

/**
 * The width of the field each manifest table's ids are packed into: 16 bits for all (a region, a
 * location, a gate, a pack template, a param; a set piece's id is a u16 for the game too:
 * `Location.set_pieces` is `Lanes16`). Only a gate's quest is wider: `GATE_QUEST_BITS`.
 */
export const ID_BITS = 16;

export function resolve(manifest: Manifest, table: string, name: unknown, what: string): number {
  const ids = (manifest[table] ?? {}) as Readonly<Record<string, number>>;
  if (typeof name !== "string" || !Object.hasOwn(ids, name)) {
    throw new R.Refused(
      "export: unknown name",
      `${what} ${JSON.stringify(name)} not in the manifest's ${table}`,
    );
  }
  // Before any packing: an id its field cannot hold is no registry id (E-48 to E-50). The
  // converter packs what it is given; a manifest `readManifest` read never holds one.
  return R.assertId(`${what} ${JSON.stringify(name)}`, ids[name], ID_BITS);
}

type G = readonly [number, number];
const gkey = ([x, y]: G) => `${x},${y}`;

/**
 * The painted hexes moved to the map's global coordinates: `(x, y)` = the editor's `(x, y)` less
 * the origin, the origin's row even so that every row keeps its parity (D-216).
 */
export class Plane {
  readonly ox: number;
  readonly oy: number;
  readonly width: number;
  readonly height: number;
  /** By global hex `"x,y"`: walkable, inside the outline. */
  readonly cells = new Map<string, { at: G; walk: boolean; inside: boolean }>();

  constructor(e: ExportFile) {
    if (fmod(e.origin.y, 2)) {
      throw new R.Refused("export: origin row odd", "the origin's y must be even (D-216)");
    }
    this.ox = e.origin.x;
    this.oy = e.origin.y;
    this.width = e.size.width;
    this.height = e.size.height;
    for (const span of e.rows) {
      for (const layer of ["ground", "outline"] as const) {
        const text = span[layer];
        if (text !== undefined && [...text].length !== [...span.terrain].length) {
          throw new R.Refused(
            "export: row lengths differ",
            `row y=${span.y}: ${layer} ${text.length}, terrain ${span.terrain.length}`,
          );
        }
      }
      [...span.terrain].forEach((t, i) => {
        if (t === " ") return;
        const g = this.glob(span.x + i, span.y);
        const inside = span.outline === undefined || span.outline[i] === "1";
        this.cells.set(gkey(g), { at: g, walk: t === ".", inside });
      });
    }
    for (const { at } of this.cells.values()) {
      const [x, y] = at;
      if (!(x >= 0 && x < 15 * this.width && y >= 0 && y < 15 * this.height)) {
        throw new R.Refused("export: hex outside the size", `(${x}, ${y})`);
      }
    }
  }

  glob(x: number, y: number): G {
    return [x - this.ox, y - this.oy];
  }

  static chunkTile([x, y]: G): [chunk: number, tile: number] {
    return [15 * fdiv(y, 15) + fdiv(x, 15), 15 * fmod(y, 15) + fmod(x, 15)];
  }

  static of(chunk: number, tile: number): G {
    return [15 * fmod(chunk, 15) + fmod(tile, 15), 15 * fdiv(chunk, 15) + fdiv(tile, 15)];
  }
}

export function connected(tiles: ReadonlySet<string>, start: G): Set<string> {
  const seen = new Set([gkey(start)]);
  const todo: G[] = [start];
  while (todo.length > 0) {
    const [x, y] = todo.pop()!;
    for (const n of R.neighbours(x, y)) {
      const k = gkey(n);
      if (tiles.has(k) && !seen.has(k)) {
        seen.add(k);
        todo.push(n);
      }
    }
  }
  return seen;
}

/** The converter's zone, and the walkable plane the pipeline's rules read. */
export interface BuiltZone extends R.Zone {
  walk: Set<string>;
  zone: Set<string>;
  plane: Plane;
}

/** The records of an authored zone (`build_zone`), before the checks. */
export function buildZone(e: ExportFile, manifest: Manifest): BuiltZone {
  const table = KIND_TABLE;
  const plane = new Plane(e);
  const blocked = new Set<string>();
  const footprints: [kind: string, foot: Set<string>, door: G][] = [];
  // What the client-only objects make unwalkable: a building's footprint but its door, a blocking
  // prop's hex (track game, 2026-10-05; CLI-09e §4).
  for (const b of e.buildings ?? []) {
    if (!table.buildings.includes(b.kind)) {
      throw new R.Refused("export: unknown kind", `building ${JSON.stringify(b.kind)}`);
    }
    const foot = new Set(b.footprint.map(([x, y]) => gkey(plane.glob(x, y))));
    const door = plane.glob(...b.door);
    if (!foot.has(gkey(door)) || R.neighbours(...door).every((n) => foot.has(gkey(n)))) {
      throw new R.Refused("export: door not on the border", `building ${JSON.stringify(b.kind)}`);
    }
    footprints.push([b.kind, foot, door]);
    for (const k of foot) if (k !== gkey(door)) blocked.add(k);
  }
  for (const p of e.props ?? []) {
    const kind = Object.hasOwn(table.props, p.kind) ? table.props[p.kind] : undefined;
    if (!kind) throw new R.Refused("export: unknown kind", `prop ${JSON.stringify(p.kind)}`);
    if (kind.blocks) blocked.add(gkey(plane.glob(p.x, p.y)));
  }
  for (const n of e.npcs ?? []) {
    if (!table.npcs.includes(n.kind)) {
      throw new R.Refused("export: unknown kind", `npc ${JSON.stringify(n.kind)}`);
    }
  }
  const zone = new Set<string>();
  for (const [k, c] of plane.cells) if (c.inside) zone.add(k);
  // Each building's footprint, authored per building (the kind table's is the editor's default):
  // in the zone and in one piece, its door walkable (track CV, 2026-10-07)
  for (const [kind, foot, door] of footprints) {
    const name = `building ${JSON.stringify(kind)}`;
    if ([...foot].some((k) => !zone.has(k))) {
      throw new R.Refused("export: footprint outside the set", name);
    }
    if (connected(foot, door).size !== foot.size) {
      throw new R.Refused("export: footprint not connected", name);
    }
    if (!plane.cells.get(gkey(door))!.walk) throw new R.Refused("export: door not walkable", name);
  }
  // The bridges' decks: walkable ground over water (D-227, ADR-0008 rule 1), refused outside the
  // zone or on a blocked hex, then written walkable before the walls
  const decks = new Set<string>();
  for (const b of e.bridges ?? []) {
    if (!Object.hasOwn(table.bridges, b.kind)) {
      throw new R.Refused("export: unknown kind", `bridge ${JSON.stringify(b.kind)}`);
    }
    for (const [x, y] of b.deck) decks.add(gkey(plane.glob(x, y)));
  }
  const outside = [...decks].filter((k) => !zone.has(k));
  if (outside.length > 0) {
    throw new R.Refused("export: deck outside the zone", outside.slice(0, 3).join(" "));
  }
  const onBlocked = [...decks].filter((k) => blocked.has(k));
  if (onBlocked.length > 0) {
    throw new R.Refused("export: deck blocked", onBlocked.slice(0, 3).join(" "));
  }
  const walk = new Set<string>(decks);
  for (const k of zone) if (plane.cells.get(k)!.walk && !blocked.has(k)) walk.add(k);
  // The chunk set and the border chunks' masks
  let chunkSet = 0n;
  const masks = new Map<number, bigint>();
  const tilesOf = new Map<number, bigint>();
  for (const k of zone) {
    const [c, t] = Plane.chunkTile(plane.cells.get(k)!.at);
    chunkSet |= R.bit(c);
    tilesOf.set(c, (tilesOf.get(c) ?? 0n) | R.bit(t));
  }
  for (const [c, m] of tilesOf) if (m !== R.BOARD) masks.set(c, m);
  const chunks = new Map<number, R.ZoneChunk>();
  for (const c of tilesOf.keys()) {
    let walls = R.BOARD;
    for (let t = 0; t < 225; t++) if (walk.has(gkey(Plane.of(c, t)))) walls &= ~R.bit(t);
    chunks.set(c, {
      walls,
      spawns: [],
      objects: [],
      tiles: [0, 0, 0, 0, 0, 0],
      bridges: 0,
      gates: [0, 0],
    });
  }

  const chunkOf = (x: number, y: number, what: string): [number, number] => {
    const [c, t] = Plane.chunkTile(plane.glob(x, y));
    if (!chunks.has(c))
      throw new R.Refused("zone: chunk not in the set", `${what} at (${x}, ${y})`);
    return [c, t];
  };

  for (const s of e.spawns ?? []) {
    const [c, t] = chunkOf(s.x, s.y, "spawn point");
    chunks
      .get(c)!
      .spawns.push({ tile: t, template: resolve(manifest, "packs", s.template, "pack") });
  }
  for (const f of e.features ?? []) {
    const [c, t] = chunkOf(f.x, f.y, "feature");
    let param = 0;
    if (f.feature === "landmark") param = resolve(manifest, "landmarks", f.param, "landmark");
    else if (f.feature === "trap") param = resolve(manifest, "skills", f.param, "trap skill");
    chunks.get(c)!.objects.push({ tile: t, kind: R.OBJECTS[f.feature], state: 0, param });
  }
  const quotas: R.Quota[] = [];
  const hearts = new Map<number, readonly [number, number] | null>();
  (e.quotas ?? []).forEach((q, i) => {
    const kind = R.QUOTA_KINDS[q.kind];
    let param = 0;
    if (q.kind === "heart") {
      param = resolve(manifest, "packs", q.param, "pack");
      const bounds = manifest.pack_bounds ?? {};
      const template =
        typeof q.param === "string" && Object.hasOwn(bounds, q.param) ? bounds[q.param] : undefined;
      hearts.set(i, template && template.length > 0 ? [template[0]!, template[1]!] : null);
    } else if (q.kind === "collector") {
      param = resolve(manifest, "collectors", q.param, "collector");
    } else if (q.kind === "landmark") {
      param = resolve(manifest, "landmarks", q.param, "landmark");
    } else if (q.kind === "exit") {
      param = resolve(manifest, "gates", q.param, "gate");
    }
    quotas.push([kind, param, q.count]);
  });
  const candidates: bigint[] = quotas.map(() => 0n);
  for (const cand of e.candidates ?? []) {
    const i = cand.quota;
    if (!(i >= 0 && i < quotas.length)) {
      throw new R.Refused("export: candidate of no quota", `quota ${i}`);
    }
    const [c, t] = chunkOf(cand.x, cand.y, "candidate");
    if (R.has(candidates[i]!, c)) {
      throw new R.Refused("export: two candidates in a chunk", `quota ${i}, chunk ${c}`);
    }
    candidates[i] = candidates[i]! | R.bit(c);
    chunks.get(c)!.tiles[i] = t;
  }
  const gates = new Map<number, R.GateFields>();
  const destinations = new Map<number, readonly [number, number]>();
  for (const gt of e.gates ?? []) {
    const [c, t] = chunkOf(gt.x, gt.y, "gate");
    const gid = resolve(manifest, "gates", gt.gate, "gate");
    // E-5: a gate to another location anchors on the outline (a zone hex with a neighbour outside
    // the zone); a dungeon's entrance (its destination a dungeon) may stand inside
    const kinds = manifest.location_kinds ?? {};
    const destination = Object.hasOwn(kinds, gt.to) ? kinds[gt.to] : undefined;
    if (
      destination !== "dungeon" &&
      R.neighbours(...plane.glob(gt.x, gt.y)).every((n) => zone.has(gkey(n)))
    ) {
      throw new R.Refused("export: gate not on the outline", `gate ${JSON.stringify(gt.gate)}`);
    }
    const slot = chunks.get(c)!.gates;
    const free = slot.indexOf(0);
    if (free < 0) throw new R.Refused("export: three gates in a chunk", `chunk ${c}`);
    slot[free] = gid;
    gates.set(gid, {
      source: resolve(manifest, "locations", e.location, "location"),
      destination: resolve(manifest, "locations", gt.to, "location"),
      anchor_chunk: c,
      anchor_tile: t,
      entry_chunk: gt.entry_chunk,
      entry_tile: gt.entry_tile,
      kind: R.GATE_KINDS[gt.kind],
      rank: gt.rank ?? 0,
      quest: R.assertId(`gate ${JSON.stringify(gt.gate)} quest`, gt.quest ?? 0, GATE_QUEST_BITS),
    });
    // R-41: the destination's rectangle, when the manifest gives it (`location_sizes`) and the
    // destination has a map (a hub has none)
    const sizes = manifest.location_sizes ?? {};
    const size = Object.hasOwn(sizes, gt.to) ? sizes[gt.to] : undefined;
    if (size !== undefined && destination !== "town" && destination !== "outpost") {
      destinations.set(gates.get(gid)!.destination, size);
    }
  }
  const bridges = new Map<number, R.BridgeFields[]>();
  for (const b of e.bridges ?? []) {
    const deck = b.deck.map(([x, y]) => Plane.chunkTile(plane.glob(x, y)));
    const ends = b.ends.map(([x, y]) => Plane.chunkTile(plane.glob(x, y)));
    const c = deck[0]![0];
    if ([...deck, ...ends].some((d) => d[0] !== c)) {
      throw new R.Refused("export: bridge across chunks", "format 1: a bridge lies in one chunk");
    }
    if (!chunks.has(c)) throw new R.Refused("zone: chunk not in the set", "a bridge");
    let deckBits = 0n;
    for (const [, t] of deck) deckBits |= R.bit(t);
    const list = bridges.get(c) ?? [];
    list.push({ deck: deckBits, ends: [ends[0]![1], ends[1]![1]] });
    bridges.set(c, list);
    chunks.get(c)!.bridges += 1;
    const own = new Set(b.deck.map(([x, y]) => gkey(plane.glob(x, y))));
    const first = plane.glob(...b.deck[0]!);
    if (connected(own, first).size !== own.size) {
      throw new R.Refused("pipeline: deck not connected");
    }
  }
  const entry = e.entry!;
  const [entryC, entryT] = Plane.chunkTile(plane.glob(entry.x, entry.y));
  const location: R.LocationFields = {
    kind: R.LOCATION_KINDS.zone,
    region: resolve(manifest, "regions", e.region, "region"),
    biome: R.BIOMES[e.biome!],
    level_min: e.level_min!,
    level_max: e.level_max!,
    rank: e.rank ?? 0,
    width: plane.width,
    height: plane.height,
    target: 0,
    floors: 0,
    next_floor: 0,
    spawn_table: e.spawn_table
      ? resolve(manifest, "spawn_tables", e.spawn_table, "spawn table")
      : 0,
    sealed: false,
    entry_chunk: entryC,
    entry_tile: entryT,
    map: R.AUTHORED,
  };
  return {
    id: resolve(manifest, "locations", e.location, "location"),
    location,
    chunk_set: chunkSet,
    masks,
    chunks,
    quotas,
    candidates,
    hearts,
    gates,
    destinations,
    bridges,
    walk,
    zone,
    plane,
  };
}

/** The content pipeline's rules (no record holds them alone). */
export function pipeline(z: BuiltZone): void {
  // P-2: the records, re-assembled across their seams, give the painted walkable plane back
  const assembled = new Set<string>();
  for (const [c, rec] of z.chunks) {
    for (let t = 0; t < 225; t++) if (!R.has(rec.walls, t)) assembled.add(gkey(Plane.of(c, t)));
  }
  const differ = [...assembled].filter((k) => !z.walk.has(k));
  differ.push(...[...z.walk].filter((k) => !assembled.has(k)));
  if (differ.length > 0) {
    throw new R.Refused(
      "pipeline: seam",
      `records and map differ at ${differ.slice(0, 3).join(" ")}`,
    );
  }
  // P-1: every walkable tile reachable from the entry
  const start = Plane.of(z.location.entry_chunk, z.location.entry_tile);
  if (assembled.has(gkey(start))) {
    const reach = connected(assembled, start);
    if (reach.size !== assembled.size) {
      const rest = [...assembled].filter((k) => !reach.has(k));
      throw new R.Refused("pipeline: unreachable tile", rest.slice(0, 3).join(" "));
    }
  }
}

const ascending = <V>(m: Map<number, V>): [number, V][] => [...m].sort(([a], [b]) => a - b);

/** The records of a zone in the order the converter writes them (README, *Registration*). */
export function zoneWrites(z: R.Zone): Write[] {
  const lid = z.id;
  const out: Write[] = [
    {
      kind: R.LOCATION,
      id: lid,
      parts: R.packLocation(z.location),
      what: "LOCATION, the marker set",
    },
    {
      kind: R.OUTLINE,
      id: lid * 256 + R.CHUNK_SET,
      parts: R.packOutline(z.chunk_set),
      what: "the chunk set",
    },
  ];
  const cands = [...z.candidates, ...Array<bigint>(Math.max(0, 6 - z.candidates.length)).fill(0n)];
  for (let k = 0; k < 2; k++) {
    const three = cands.slice(3 * k, 3 * k + 3);
    if (three.some((s) => s !== 0n)) {
      out.push({
        kind: R.CANDIDATES,
        id: lid * 2 + k,
        parts: R.packCandidates(three),
        what: `quotas ${3 * k}-${3 * k + 2}'s candidates`,
      });
    }
  }
  if (z.quotas.length > 0) {
    out.push({ kind: R.QUOTAS, id: lid, parts: R.packQuotas(z.quotas), what: "the quotas" });
  }
  for (const [c, mask] of ascending(z.masks)) {
    out.push({
      kind: R.OUTLINE,
      id: lid * 256 + c,
      parts: R.packOutline(mask),
      what: `chunk ${c}'s mask`,
    });
  }
  for (const [c, chunk] of ascending(z.chunks)) {
    out.push({
      kind: R.ZONE_CHUNK,
      id: lid * 256 + c,
      parts: R.packZoneChunk(chunk),
      what: `chunk ${c}`,
    });
    (z.bridges.get(c) ?? []).forEach((b, k) => {
      out.push({
        kind: R.BRIDGE,
        id: lid * 4096 + c * 16 + k,
        parts: R.packBridge(b),
        what: `chunk ${c} bridge ${k}`,
      });
    });
  }
  for (const [gid, gate] of ascending(z.gates)) {
    out.push({ kind: R.GATE, id: gid, parts: R.packGate(gate), what: `gate ${gid}` });
  }
  return out;
}

/** A set piece (one chunk, ADR-0006 *Set pieces*): one `SET_PIECE`, `SetPieceAssert`'s rules. */
function setPieceWrites(e: ExportFile, manifest: Manifest): Write[] {
  const plane = new Plane(e);
  if (plane.width !== 1 || plane.height !== 1) {
    throw new R.Refused("export: set piece size", "a set piece is one chunk");
  }
  let walls = R.BOARD;
  for (const c of plane.cells.values()) if (c.walk) walls &= ~R.bit(Plane.chunkTile(c.at)[1]);
  const corners = R.bit(0) | R.bit(14) | R.bit(210) | R.bit(224);
  if ((walls & corners) !== corners) throw new R.Refused("set piece: corner not wall");
  const interior = (t: number) => {
    const row = fdiv(t, 15);
    const col = t % 15;
    if (!(row > 0 && row < 14 && col > 0 && col < 14) || R.has(walls, t)) {
      throw new R.Refused("set piece: tile not floor", `tile ${t}`);
    }
    return t;
  };
  const tileOf = (x: number, y: number) => interior(Plane.chunkTile(plane.glob(x, y))[1]);
  const spawns = (e.spawns ?? []).map((s) => ({
    tile: tileOf(s.x, s.y),
    template: resolve(manifest, "packs", s.template, "pack"),
  }));
  const objects = (e.features ?? []).map((f) => ({
    tile: tileOf(f.x, f.y),
    kind: R.OBJECTS[f.feature],
    param: 0,
  }));
  if (spawns.length > 2 || objects.length > 3) throw new R.Refused("set piece: over its caps");
  const pid = resolve(manifest, "set_pieces", e.name, "set piece");
  return [
    {
      kind: R.SET_PIECE,
      id: pid,
      parts: R.packSetPiece({ walls, spawns, objects }),
      what: "the set piece",
    },
  ];
}

/** A town or an outpost: client-only (D-03, D-202). Only `LOCATION` (no map: 0 × 0, entry 0). */
function townWrites(e: ExportFile, manifest: Manifest): Write[] {
  const lid = resolve(manifest, "locations", e.location, "location");
  const loc: R.LocationFields = {
    kind: R.LOCATION_KINDS[e.kind as "town" | "outpost"],
    region: resolve(manifest, "regions", e.region, "region"),
    biome: 0,
    level_min: 0,
    level_max: 0,
    rank: 0,
    width: 0,
    height: 0,
    target: 0,
    floors: 0,
    next_floor: 0,
    spawn_table: 0,
    sealed: false,
    entry_chunk: 0,
    entry_tile: 0,
  };
  return [
    { kind: R.LOCATION, id: lid, parts: R.packLocation(loc), what: "LOCATION (a hub: no map)" },
  ];
}

export interface Converted {
  readonly writes: readonly Write[];
  /** The zone's records, null but for a zone. */
  readonly zone: BuiltZone | null;
}

/** `convert`: the records in their order, or a `Refused` thrown with the converter's code. */
export function convertStrict(raw: unknown, manifest: Manifest): Converted {
  // The format and its version first, so that a newer file is told as such, not as a schema error
  const file = raw as Partial<ExportFile> | null;
  if (typeof raw !== "object" || raw === null || Array.isArray(raw) || file!.format !== FORMAT) {
    throw new R.Refused("export: format", "not a grimworld-export file");
  }
  if (file!.version !== VERSION) {
    throw new R.Refused(
      "export: version",
      `${String(file!.version)} (this converter reads ${VERSION})`,
    );
  }
  validate(raw);
  const e = raw as ExportFile;
  const needed = e.kind === "zone" ? ZONE_FIELDS : e.kind === "set_piece" ? [] : HUB_FIELDS;
  const missing = needed.filter((key) => !(key in e));
  if (missing.length > 0) {
    throw new R.Refused("export: field missing", `a ${e.kind} needs ${missing.join(", ")}`);
  }
  if (e.kind === "town" || e.kind === "outpost")
    return { writes: townWrites(e, manifest), zone: null };
  if (e.kind === "set_piece") return { writes: setPieceWrites(e, manifest), zone: null };
  const z = buildZone(e, manifest);
  R.checkZone(z);
  pipeline(z);
  return { writes: zoneWrites(z), zone: z };
}

/**
 * `convert` as `main` runs it: the records, or the refusal with its code. A failure no check names
 * is still a refusal (`export: malformed`), never a thrown error (review t-0084).
 */
export function convert(raw: unknown, manifest: Manifest): Converted | R.Refused {
  try {
    return convertStrict(raw, manifest);
  } catch (e) {
    if (e instanceof R.Refused) return e;
    const error = e instanceof Error ? e : new Error(String(e));
    return new R.Refused("export: malformed", `${error.name}: ${error.message}`);
  }
}

/** The records file the converter writes (`--out`): `grimworld-records` v1, as its text. */
export function recordsFile(writes: readonly Write[], source: string): string {
  const out = {
    format: RECORDS_FORMAT,
    version: VERSION,
    source,
    writes: writes.map((w, order) => ({
      order,
      kind: R.KIND_NAMES[w.kind],
      kind_id: w.kind,
      id: w.id,
      parts: w.parts.map((f) => `0x${f.toString(16)}`),
      what: w.what,
    })),
  };
  return `${JSON.stringify(out, null, 1)}\n`;
}

const limbs32 = (felt: bigint): number[] =>
  Array.from({ length: 8 }, (_, i) => Number((felt >> BigInt(32 * i)) & 0xffffffffn));

/**
 * The golden file (`--golden`): each chunk's fields and its two parts as 32-bit limbs, and the
 * other records', for snforge's `read_json`. Kept to compare with ENG-08's, felt for felt.
 */
export function golden(writes: readonly Write[]) {
  const fields: number[] = [];
  const parts: number[] = [];
  for (const w of writes) {
    if (w.kind !== R.ZONE_CHUNK) continue;
    const c = w.id % 256;
    const rec = R.unpackZoneChunk(w.parts);
    const sp = [...rec.spawns, ...Array(2 - rec.spawns.length).fill({ tile: 0, template: 0 })];
    const ob = [
      ...rec.objects,
      ...Array(3 - rec.objects.length).fill({ tile: 0, kind: 0, param: 0 }),
    ];
    fields.push(c, ...limbs32(rec.walls));
    for (const s of sp) fields.push(s.tile, s.template);
    for (const o of ob) fields.push(o.tile, o.kind, o.param);
    fields.push(...rec.tiles, rec.bridges, ...rec.gates);
    parts.push(c, ...limbs32(w.parts[0]!), ...limbs32(w.parts[1]!));
  }
  const records: number[] = [];
  const others = new Set([R.LOCATION, R.OUTLINE, R.CANDIDATES, R.QUOTAS, R.BRIDGE, R.GATE]);
  for (const w of writes) {
    if (!others.has(w.kind)) continue;
    for (const f of w.parts) records.push(w.kind, w.id, ...limbs32(f));
  }
  return { chunk_count: parts.length / 17, chunk_fields: fields, chunk_parts: parts, records };
}
