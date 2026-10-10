import type { Tile } from "../../render/view";
import { EDITOR_VERSION, spans } from "../file";
import { fitted } from "../fit";
import {
  CHUNK,
  FLOOR,
  type MapDocument,
  type MapMeta,
  WALL,
  cellOf,
  defaultGround,
  keyOf,
  tileOfKey,
} from "../model";
import { BIOMES, type Biome } from "../model";
import type { FeatureKind, MapObject, Quota, QuotaKind } from "../objects";
import { doorOffset, footprintOffsets, isPack, recordFor } from "../pack";
import { BRIDGE_RUNS, bridgeAt, footprintAt, kindOf } from "../palette";
import { type ExportFile, FORMAT, type Hex, type Manifest, VERSION, idBits } from "./convert";
import { LOCATION_KINDS, Refused } from "./records";
import { validate } from "./schema";

/**
 * The editor's map as ENG-08's export (`grimworld-export` v1) and back (CLI-09c, brief §2.7, §10).
 *
 * The editor keeps registry ids, as its inspector types them; the export names them, and the content
 * manifest (OPS-01's, `samples/manifest.json`'s shape) maps one to the other: a name to its id on
 * import, an id to its name on export. An id the manifest does not name is written as `#<id>`, a
 * name no manifest holds, so that the converter refuses it as it would any unknown name (E-35).
 *
 * The export is of the **fitted** map (D-216): `origin` is the fit's global `(0, 0)` on the editor's
 * plane, `size` its rectangle; the painted hexes beyond the rectangle (outside the outline, or the
 * fit would hold them) are not written.
 */

/** The manifest tables a field's id is named in. */
const QUOTA_TABLES: Readonly<Partial<Record<QuotaKind, string>>> = {
  heart: "packs",
  collector: "collectors",
  landmark: "landmarks",
  exit: "gates",
};
const FEATURE_TABLES: Readonly<Partial<Record<FeatureKind, string>>> = {
  landmark: "landmarks",
  trap: "skills",
};

const ids = (manifest: Manifest, table: string): Readonly<Record<string, number>> =>
  (manifest[table] ?? {}) as Readonly<Record<string, number>>;

/** An id's name in a table of the manifest: the first that names it, or `#<id>`. */
export function nameOf(manifest: Manifest, table: string, id: number): string {
  const found = Object.entries(ids(manifest, table)).find(([, v]) => v === id);
  return found ? found[0] : `#${id}`;
}

/** A name's id in a table of the manifest, or null. */
function idOf(manifest: Manifest, table: string, name: string): number | null {
  const table_ = ids(manifest, table);
  return Object.hasOwn(table_, name) ? table_[name]! : null;
}

const hex = (t: Tile): Hex => [t.x, t.y];

/** The objects of a kind, in placing order. */
function objectsOf<K extends MapObject["kind"]>(
  doc: MapDocument,
  kind: K,
): Extract<MapObject, { kind: K }>[] {
  return [...doc.objects]
    .sort(([a], [b]) => a - b)
    .map(([, o]) => o)
    .filter((o): o is Extract<MapObject, { kind: K }> => o.kind === kind);
}

export type ExportResult = { readonly file: ExportFile } | { readonly problem: string };

/** The zone as ENG-08's export, or why there is none (not a zone, no fit). */
export function toExport(
  doc: MapDocument,
  manifest: Manifest,
  editor = EDITOR_VERSION,
): ExportResult {
  const { meta } = doc;
  if (meta.kind !== "zone") return { problem: "A town is not exported for the chain (D-03)." };
  const fit = fitted(doc);
  if (fit === "unfitted")
    return { problem: "The chunks are not fitted yet: Fit chunks (Shift+0)." };
  if (typeof fit === "string") return { problem: "There is no fitted map to export." };
  const inRect = (x: number, y: number) =>
    x >= fit.x0 && x < fit.x0 + CHUNK * fit.width && y >= fit.y0 && y < fit.y0 + CHUNK * fit.height;
  const rows = spans(doc).flatMap((span) => {
    // Only the hexes within the fitted rectangle: trimmed at both ends, gaps kept.
    let from = 0;
    let to = span.terrain.length;
    while (from < to && (span.terrain[from] === " " || !inRect(span.x + from, span.y))) from++;
    while (to > from && (span.terrain[to - 1] === " " || !inRect(span.x + to - 1, span.y))) to--;
    if (from === to) return [];
    return [
      {
        y: span.y,
        x: span.x + from,
        terrain: span.terrain.slice(from, to),
        ground: span.ground.slice(from, to),
        outline: span.outline!.slice(from, to),
      },
    ];
  });
  const name = (table: string, id: number) => nameOf(manifest, table, id);
  const entry = objectsOf(doc, "entry")[0];
  const file: ExportFile = {
    format: FORMAT,
    version: VERSION,
    editor,
    kind: "zone",
    name: meta.name,
    location: name("locations", meta.location),
    region: name("regions", meta.region),
    biome: meta.biome ?? "meadow",
    level_min: meta.levelMin,
    level_max: meta.levelMax,
    rank: meta.rank,
    spawn_table: meta.spawnTable ? name("spawn_tables", meta.spawnTable) : null,
    origin: { x: fit.x0, y: fit.y0 },
    size: { width: fit.width, height: fit.height },
    rows,
    // No entry: the converter refuses the file (E-34), as the editor's E-4 does.
    ...(entry ? { entry: { x: entry.at.x, y: entry.at.y } } : {}),
    quotas: meta.quotas.map((q) => {
      const table = QUOTA_TABLES[q.kind];
      return { kind: q.kind, param: table ? name(table, q.param) : null, count: q.count };
    }),
    candidates: objectsOf(doc, "candidate").map((c) => ({ quota: c.quota, ...c.at })),
    spawns: objectsOf(doc, "spawn").map((s) => ({ template: name("packs", s.template), ...s.at })),
    features: objectsOf(doc, "feature").map((f) => {
      const table = FEATURE_TABLES[f.feature];
      return { feature: f.feature, param: table ? name(table, f.param) : null, ...f.at };
    }),
    gates: objectsOf(doc, "gate").map((g) => ({
      gate: name("gates", g.id),
      to: name("locations", g.to),
      kind: g.gate,
      rank: g.rank,
      quest: g.quest,
      entry_chunk: g.entryChunk,
      entry_tile: g.entryTile,
      ...g.at,
    })),
    npcs: objectsOf(doc, "npc").map((n) => ({ kind: n.type, ...n.at, facing: n.facing })),
    buildings: [],
    props: [],
    bridges: [],
  };
  for (const o of [...doc.objects].sort(([a], [b]) => a - b).map(([, o]) => o)) {
    if (!isPack(o) || o.kind === "npc") continue;
    const placed = recordFor(o);
    if ("problem" in placed) {
      // What the record cannot write: the editor's E-20 or E-23 names it; the export stops.
      return { problem: `The ${o.type} at (${o.at.x}, ${o.at.y}): ${placed.problem}.` };
    }
    if (placed.category === "building" && o.kind === "building") {
      const { record } = placed;
      file.buildings!.push({
        kind: record.kind,
        footprint: record.footprint.map(hex),
        anchor: hex(record.anchor),
        door: hex(record.door),
        depth: o.depth,
        mirror: false,
      });
    } else if (placed.category === "prop") {
      const { kind, hex: at, ...rest } = placed.record;
      file.props!.push({ kind, x: at.x, y: at.y, ...rest });
    } else if (placed.category === "bridge") {
      const { record } = placed;
      file.bridges!.push({
        kind: record.kind,
        deck: record.deck.map(hex),
        ends: [hex(record.ends[0]), hex(record.ends[1])],
      });
    }
  }
  if (doc.obstacles.size > 0) {
    file.obstacles = [...doc.obstacles]
      .sort(([a], [b]) => a - b)
      .map(([key, sprite]) => ({ ...tileOfKey(key), sprite }));
  }
  for (const list of ["quotas", "candidates", "spawns", "features", "gates", "npcs"] as const) {
    if (file[list]!.length === 0) delete file[list];
  }
  for (const list of ["buildings", "props", "bridges"] as const) {
    if (file[list]!.length === 0) delete file[list];
  }
  return { file };
}

export type ImportResult =
  { readonly doc: MapDocument; readonly notes: readonly string[] } | { readonly problem: string };

const GROUND_CHARS = ["g", "e", "w"];

/**
 * A `grimworld-export` file opened in the editor: a zone, its names turned into the manifest's ids.
 * Refused, with the reason, when the file is not one the converter reads (its format, version and
 * schema), not a zone, names what the manifest lacks, or holds what the editor cannot draw as it
 * is (a bridge of another shape). A building keeps its file's footprint when its kind would draw
 * another (ENG-08's sample hut does).
 */
export function fromExport(raw: unknown, manifest: Manifest): ImportResult {
  const refuse = (why: string): ImportResult => ({ problem: `The export is refused: ${why}.` });
  const r = raw as Partial<ExportFile> | null;
  if (r?.format !== FORMAT) return refuse("its format is not grimworld-export");
  if (r.version !== VERSION) {
    return refuse(`it is of version ${String(r.version)}, this editor reads ${VERSION}`);
  }
  try {
    validate(raw);
  } catch (e) {
    if (e instanceof Refused) return refuse(`it does not match ENG-08's schema (${e.detail})`);
    throw e;
  }
  const e = raw as ExportFile;
  if (e.kind !== "zone") return refuse(`a ${e.kind} is not exported for the chain, a zone only`);
  if (!e.location || !e.region || !e.biome || !e.entry) {
    return refuse("a zone gives its location, region, biome, levels and entry");
  }
  const missing: string[] = [];
  const id = (table: string, name: string | null | undefined): number => {
    if (name === null || name === undefined) return 0;
    const found = idOf(manifest, table, name);
    if (found === null) missing.push(`${table} ${JSON.stringify(name)}`);
    return found ?? 0;
  };
  const quotas: Quota[] = (e.quotas ?? []).map((q) => {
    const table = QUOTA_TABLES[q.kind];
    return { kind: q.kind, param: table ? id(table, q.param) : 0, count: q.count };
  });
  const meta: MapMeta = {
    kind: "zone",
    name: e.name,
    location: id("locations", e.location),
    region: id("regions", e.region),
    biome: BIOMES.includes(e.biome as Biome) ? (e.biome as Biome) : "meadow",
    levelMin: e.level_min ?? 0,
    levelMax: e.level_max ?? 0,
    rank: e.rank ?? 0,
    spawnTable: id("spawn_tables", e.spawn_table),
    quotas,
  };
  const hexes = new Map<number, number>();
  for (const span of e.rows) {
    const terrain = [...span.terrain];
    if (span.ground !== undefined && span.ground.length !== terrain.length) {
      return refuse(`row ${span.y}'s ground is not as long as its terrain`);
    }
    if (span.outline !== undefined && span.outline.length !== terrain.length) {
      return refuse(`row ${span.y}'s outline is not as long as its terrain`);
    }
    for (const [i, t] of terrain.entries()) {
      if (t === " ") continue;
      const g = span.ground?.[i];
      const ground = g === undefined || g === " " ? defaultGround() : GROUND_CHARS.indexOf(g);
      const outside = span.outline !== undefined && span.outline[i] !== "1";
      hexes.set(
        keyOf({ x: span.x + i, y: span.y }),
        cellOf(t === "." ? FLOOR : WALL, ground, outside),
      );
    }
  }
  const objects: MapObject[] = [{ kind: "entry", at: { ...e.entry } }];
  for (const c of e.candidates ?? [])
    objects.push({ kind: "candidate", at: { x: c.x, y: c.y }, quota: c.quota });
  for (const s of e.spawns ?? []) {
    objects.push({ kind: "spawn", at: { x: s.x, y: s.y }, template: id("packs", s.template) });
  }
  for (const f of e.features ?? []) {
    const table = FEATURE_TABLES[f.feature];
    objects.push({
      kind: "feature",
      at: { x: f.x, y: f.y },
      feature: f.feature,
      param: table ? id(table, f.param) : 0,
    });
  }
  for (const g of e.gates ?? []) {
    objects.push({
      kind: "gate",
      at: { x: g.x, y: g.y },
      id: id("gates", g.gate),
      to: id("locations", g.to),
      gate: g.kind,
      rank: g.rank ?? 0,
      quest: g.quest ?? 0,
      entryChunk: g.entry_chunk,
      entryTile: g.entry_tile,
    });
  }
  for (const n of e.npcs ?? []) {
    objects.push({ kind: "npc", at: { x: n.x, y: n.y }, type: n.kind, facing: n.facing });
  }
  const same = (a: readonly Hex[], b: readonly Hex[]) =>
    a.length === b.length && a.every(([x, y], i) => x === b[i]![0] && y === b[i]![1]);
  for (const b of e.buildings ?? []) {
    const at = { x: b.anchor[0], y: b.anchor[1] };
    const kind = kindOf(b.kind);
    const depth = b.depth ?? (kind?.category === "building" ? kind.depth : 1);
    // The editor draws a kind's footprint from its anchor and depth; a file's other one is kept.
    const drawn = kind?.category === "building" ? footprintAt(kind, at, depth).map(hex) : null;
    const sorted = (list: readonly Hex[]) =>
      [...list].sort(([ax, ay], [bx, by]) => ay - by || ax - bx);
    const kept =
      drawn && same(sorted(drawn), sorted(b.footprint))
        ? ""
        : footprintOffsets(
            at,
            b.footprint.map(([x, y]) => ({ x, y })),
          );
    objects.push({
      kind: "building",
      at,
      type: b.kind,
      depth,
      door: doorOffset(at, { x: b.door[0], y: b.door[1] }),
      footprint: kept,
    });
  }
  for (const p of e.props ?? []) {
    objects.push({
      kind: "scenery",
      at: { x: p.x, y: p.y },
      type: p.kind,
      variant: p.variant ?? 0,
      facing: p.facing ?? 0,
      mirror: p.flip ?? false,
    });
  }
  for (const b of e.bridges ?? []) {
    const kind = kindOf(b.kind);
    const at = { x: b.ends[0][0], y: b.ends[0][1] };
    // Its deck's length is the file's (CLI-09f); its run and lean, the shape that draws it.
    const deck = b.deck.length;
    const shape = BRIDGE_RUNS.flatMap((run) =>
      [false, true].map((mirror) => ({ run, mirror })),
    ).find(({ run, mirror }) => {
      if (kind?.category !== "bridge") return false;
      const drawn = bridgeAt(kind, at, mirror, run, deck);
      return same(drawn.deck.map(hex), b.deck) && same(drawn.ends.map(hex), b.ends);
    });
    if (!shape) {
      return refuse(`the ${b.kind} from (${at.x}, ${at.y}) is not a bridge the editor draws`);
    }
    objects.push({ kind: "bridge", at, type: b.kind, mirror: shape.mirror, run: shape.run, deck });
  }
  if (missing.length > 0) {
    return refuse(`the content manifest does not name ${[...new Set(missing)].join(", ")}`);
  }
  const obstacles = new Map<number, string>();
  for (const o of e.obstacles ?? []) obstacles.set(keyOf({ x: o.x, y: o.y }), o.sprite);
  const doc: MapDocument = {
    meta,
    hexes,
    obstacles,
    objects: new Map(objects.map((o, i) => [i + 1, o])),
    // The fitted map's global (0, 0): its residues are the chunk grid's origin, as the author set it.
    origin: { x: mod(e.origin.x, CHUNK), y: mod(e.origin.y, 2 * CHUNK), how: "nudged" },
  };
  const notes: string[] = [];
  const fit = fitted(doc);
  if (
    typeof fit !== "string" &&
    (fit.x0 !== e.origin.x ||
      fit.y0 !== e.origin.y ||
      fit.width !== e.size.width ||
      fit.height !== e.size.height)
  ) {
    notes.push(
      `The file's map is ${e.size.width} × ${e.size.height} chunks from (${e.origin.x}, ${e.origin.y}); the editor fits it in ${fit.width} × ${fit.height} from (${fit.x0}, ${fit.y0}).`,
    );
  }
  return { doc, notes };
}

const mod = (n: number, m: number) => ((n % m) + m) % m;

/** A file's text: an editor's export, or something else (the editor's own file). */
export function isExportText(raw: unknown): boolean {
  return typeof raw === "object" && raw !== null && (raw as { format?: unknown }).format === FORMAT;
}

/**
 * The manifest of a file's text, or why it is not one: tables of names to registry ids, each id a
 * whole number its records' fields hold (`ID_BITS`, review t-0147: a negative or over-wide id is
 * refused here, never packed); `pack_bounds`, each pack's `[min, max]`; `location_kinds`, each
 * location's kind (ENG-09: a gate into a dungeon may stand inside the zone).
 */
export function readManifest(text: string): Manifest | string {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return "The manifest is not JSON.";
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return "The manifest is not a JSON object of tables.";
  }
  for (const [table, value] of Object.entries(raw)) {
    if (table.startsWith("$")) continue;
    const entries = typeof value === "object" && value !== null ? Object.values(value) : null;
    const ok =
      entries !== null &&
      !Array.isArray(value) &&
      entries.every((v) =>
        table === "pack_bounds"
          ? Array.isArray(v) && v.length === 2 && v.every((n) => Number.isInteger(n))
          : table === "location_kinds"
            ? typeof v === "string" && Object.hasOwn(LOCATION_KINDS, v)
            : Number.isInteger(v),
      );
    if (!ok) return `The manifest's ${table} is not a table of names.`;
    if (table === "pack_bounds" || table === "location_kinds") continue;
    const bits = idBits(table);
    const wide = entries.find((v) => (v as number) < 0 || (v as number) >= 2 ** bits);
    if (wide !== undefined) {
      return `The manifest's ${table} holds the id ${String(wide)}: an id is 0 to ${2 ** bits - 1}.`;
    }
  }
  return raw as Manifest;
}
