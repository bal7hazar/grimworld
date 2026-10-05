import {
  BIOMES,
  type Biome,
  CHUNK,
  COORD_MAX,
  type Cell,
  type ChunkOrigin,
  FLOOR,
  MAP_KINDS,
  type MapDocument,
  type MapKind,
  type MapMeta,
  NAME_MAX,
  WALL,
  cellOf,
  groundOfCell,
  isOutside,
  keyOf,
  terrainOf,
  tileOfKey,
} from "./model";
import {
  KINDS,
  type MapObject,
  OBJECT_KINDS,
  type ObjectKind,
  QUOTA_KINDS,
  type Quota,
  objectFrom,
} from "./objects";

/**
 * The editor's own file (brief §6, `.grimmap.json`): one JSON document, the editor's to shape
 * (the registration export is CLI-09c's, in ENG-08's schema).
 *
 * Format 2 (CLI-09a2, D-216): the painted hexes only, as row spans. Each span is one row `y` from
 * column `x` on, one character per hex (`x` first, growing West), a space for an unpainted hex:
 *
 * - `terrain`: `.` floor, `#` wall (the walkable plane);
 * - `ground`: `g` grass, `e` earth, `w` water;
 * - `outline` (a zone only): `1` inside, `0` outside.
 *
 * `chunks` is the last chosen chunk origin and how it was chosen, or null before the first fit.
 * Pinned obstacle looks are a list of `{ x, y, sprite }`: a still's name, never pixels (§7).
 *
 * CLI-09b adds, still in format 2 (a file without them has none): the map's `quotas` (a zone's,
 * `{ kind, param, count }`) and `objects`, a list of `{ kind, x, y, …its fields }` in the order
 * they were placed (§4.2, §4.3; `objects.ts`). Sprite and building names, never pixels.
 *
 * Format 1 (CLI-09a) was a rectangle of whole chunks at `(0, 0)` with every hex filled: it opens,
 * converted, every hex painted and the chunk grid at `(0, 0)`.
 */

export const FORMAT = "grimworld-map";
/** The format's version: a file of a newer one is refused, an older one converted (§6). */
export const FORMAT_VERSION = 2;

/** The editor's version written in a file: the client's commit when the build was given one. */
export const EDITOR_VERSION: string =
  (import.meta.env?.VITE_GRIMWORLD_COMMIT as string | undefined) ?? "dev";

/** By value: `FLOOR` 0, `WALL` 1; `GROUND_KINDS` grass, earth, water. */
const TERRAIN_CHARS = [".", "#"] as const;
const GROUND_CHARS = ["g", "e", "w"] as const;
const OUTLINE_CHARS = ["0", "1"] as const;
const GAP = " ";

export interface RowSpan {
  readonly y: number;
  readonly x: number;
  readonly terrain: string;
  readonly ground: string;
  /** A zone's; absent for a town or an outpost. */
  readonly outline?: string;
}

export interface MapFile {
  readonly format: typeof FORMAT;
  readonly version: number;
  readonly editor: string;
  readonly map: MapMeta;
  readonly rows: readonly RowSpan[];
  readonly chunks: ChunkOrigin | null;
  readonly obstacles: readonly {
    readonly x: number;
    readonly y: number;
    readonly sprite: string;
  }[];
  readonly objects: readonly Record<string, unknown>[];
}

/** An object as the file writes it: its hex as `x`, `y`, then its fields. */
function objectOut(object: MapObject): Record<string, unknown> {
  const { kind, at, ...fields } = object;
  return { kind, x: at.x, y: at.y, ...fields };
}

/** One span per painted row, from its lowest `x` to its highest, the rows by `y`. */
function spans(doc: MapDocument): RowSpan[] {
  const byRow = new Map<number, Map<number, Cell>>();
  for (const [key, cell] of doc.hexes) {
    const { x, y } = tileOfKey(key);
    let row = byRow.get(y);
    if (!row) byRow.set(y, (row = new Map()));
    row.set(x, cell);
  }
  const zone = doc.meta.kind === "zone";
  return [...byRow.keys()]
    .sort((a, b) => a - b)
    .map((y) => {
      const row = byRow.get(y)!;
      const xs = [...row.keys()];
      const x0 = Math.min(...xs);
      const x1 = Math.max(...xs);
      let terrain = "";
      let ground = "";
      let outline = "";
      for (let x = x0; x <= x1; x++) {
        const cell = row.get(x);
        if (cell === undefined) {
          terrain += GAP;
          ground += GAP;
          outline += GAP;
          continue;
        }
        terrain += TERRAIN_CHARS[terrainOf(cell)];
        ground += GROUND_CHARS[groundOfCell(cell)];
        outline += OUTLINE_CHARS[isOutside(cell) ? 0 : 1];
      }
      return zone ? { y, x: x0, terrain, ground, outline } : { y, x: x0, terrain, ground };
    });
}

/** The file of a document. */
export function toFile(doc: MapDocument, editor = EDITOR_VERSION): MapFile {
  return {
    format: FORMAT,
    version: FORMAT_VERSION,
    editor,
    map: { ...doc.meta },
    rows: spans(doc),
    chunks: doc.origin ? { ...doc.origin } : null,
    obstacles: [...doc.obstacles]
      .sort(([a], [b]) => a - b)
      .map(([key, sprite]) => ({ ...tileOfKey(key), sprite })),
    objects: [...doc.objects].sort(([a], [b]) => a - b).map(([, object]) => objectOut(object)),
  };
}

/** The text saved (`<name>.grimmap.json`). */
export function saveMap(doc: MapDocument, editor = EDITOR_VERSION): string {
  return `${JSON.stringify(toFile(doc, editor), null, 1)}\n`;
}

/** A file's name: the map's name, letters, digits and dashes only. */
export function fileName(meta: Pick<MapMeta, "name">): string {
  const base = meta.name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${base || "map"}.grimmap.json`;
}

export type LoadResult =
  | { readonly doc: MapDocument; readonly editor: string; readonly notes: readonly string[] }
  | { readonly problem: string };

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const isWhole = (v: unknown, min: number, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;

const inPlane = (v: unknown): v is number => isWhole(v, -COORD_MAX, COORD_MAX);

function readMeta(raw: unknown): MapMeta | string {
  if (!isObject(raw)) return "the map's fields are missing";
  const kind = raw.kind as MapKind;
  if (!MAP_KINDS.includes(kind)) return `unknown kind ${JSON.stringify(raw.kind)}`;
  const { name } = raw;
  if (typeof name !== "string" || name.trim().length === 0 || name.length > NAME_MAX) {
    return `the name is not 1 to ${NAME_MAX} characters`;
  }
  const biome = raw.biome as Biome | null;
  if (kind === "zone" ? !BIOMES.includes(biome as Biome) : biome !== null) {
    return `the biome ${JSON.stringify(raw.biome)} does not suit a ${kind}`;
  }
  for (const field of ["location", "levelMin", "levelMax", "rank", "spawnTable"] as const) {
    if (!isWhole(raw[field], 0)) return `${field} is not a whole number, 0 or more`;
  }
  const quotas: Quota[] = [];
  if (raw.quotas !== undefined) {
    if (!Array.isArray(raw.quotas) || (kind !== "zone" && raw.quotas.length > 0)) {
      return "the quotas are not a list (a zone's only)";
    }
    for (const q of raw.quotas) {
      if (
        !isObject(q) ||
        !QUOTA_KINDS.includes(q.kind as Quota["kind"]) ||
        !isWhole(q.param, 0) ||
        !isWhole(q.count, 0)
      ) {
        return "a quota is not { kind, param, count }";
      }
      quotas.push({ kind: q.kind as Quota["kind"], param: q.param, count: q.count });
    }
  }
  return {
    kind,
    name,
    location: raw.location as number,
    biome,
    levelMin: raw.levelMin as number,
    levelMax: raw.levelMax as number,
    rank: raw.rank as number,
    spawnTable: raw.spawnTable as number,
    quotas,
  };
}

/** One object of the file, read by its kind's row (`KINDS`), or why it is refused. */
function readObject(raw: unknown, meta: MapMeta): MapObject | string {
  if (!isObject(raw) || !inPlane(raw.x) || !inPlane(raw.y)) return "not { kind, x, y, … }";
  const at = { x: raw.x, y: raw.y };
  const kind = raw.kind as ObjectKind;
  const spec = OBJECT_KINDS.includes(kind) ? KINDS[kind] : null;
  const object = spec && objectFrom(kind, at, raw, meta);
  if (!spec || !object) {
    return `an object ${JSON.stringify(raw.kind)} at (${at.x}, ${at.y}) is not read`;
  }
  const zone = meta.kind === "zone";
  if ((spec.map === "zone") !== zone) {
    return `a ${zone ? "zone" : "town or an outpost"} holds no ${object.kind}`;
  }
  return object;
}

function readObjects(raw: unknown, meta: MapMeta): Map<number, MapObject> | string {
  const objects = new Map<number, MapObject>();
  if (raw === undefined) return objects;
  if (!Array.isArray(raw)) return "the objects are not a list";
  for (const item of raw) {
    const object = readObject(item, meta);
    if (typeof object === "string") return object;
    objects.set(objects.size + 1, object);
  }
  return objects;
}

function readObstacles(
  raw: unknown,
  painted: (x: number, y: number) => boolean,
): Map<number, string> | string {
  const obstacles = new Map<number, string>();
  if (!Array.isArray(raw)) return "no obstacles list";
  for (const pin of raw) {
    if (
      !isObject(pin) ||
      !inPlane(pin.x) ||
      !inPlane(pin.y) ||
      typeof pin.sprite !== "string" ||
      !painted(pin.x, pin.y)
    ) {
      return "an obstacle pin is not { x, y, sprite } on a painted hex";
    }
    obstacles.set(keyOf({ x: pin.x, y: pin.y }), pin.sprite);
  }
  return obstacles;
}

// --- format 2 ----------------------------------------------------------------------------------

function readOrigin(raw: unknown): ChunkOrigin | null | string {
  if (raw === null) return null;
  if (
    !isObject(raw) ||
    !isWhole(raw.x, 0, CHUNK - 1) ||
    !isWhole(raw.y, 0, 2 * CHUNK - 2) ||
    raw.y % 2 !== 0 ||
    (raw.how !== "fitted" && raw.how !== "nudged")
  ) {
    return "the chunk origin is not { x 0-14, y even 0-28, how fitted or nudged } or null";
  }
  return { x: raw.x, y: raw.y, how: raw.how };
}

function readRows(raw: unknown, zone: boolean): Map<number, Cell> | string {
  if (!Array.isArray(raw)) return "its rows are missing";
  const hexes = new Map<number, Cell>();
  const rows = new Set<number>();
  for (const [i, span] of raw.entries()) {
    const where = `row span ${i}`;
    if (!isObject(span) || !inPlane(span.y) || !inPlane(span.x)) {
      return `${where} is not { y, x, terrain, ground${zone ? ", outline" : ""} } in the plane`;
    }
    const { y, x, terrain, ground, outline } = span;
    if (rows.has(y)) return `${where}: row ${y} comes twice`;
    rows.add(y);
    if (typeof terrain !== "string" || typeof ground !== "string") {
      return `${where}: terrain and ground are not text`;
    }
    if (zone ? typeof outline !== "string" : outline !== undefined) {
      return `${where}: ${zone ? "a zone's span has no outline" : "a town or an outpost has no outline"}`;
    }
    const layers = zone ? [terrain, ground, outline as string] : [terrain, ground];
    if (layers.some((l) => l.length !== terrain.length) || terrain.length === 0) {
      return `${where}: its layers are not of one length`;
    }
    if (!inPlane(x + terrain.length - 1)) return `${where} runs past the plane`;
    for (let k = 0; k < terrain.length; k++) {
      const gap = layers.map((l) => l[k] === GAP);
      if (gap.some((g) => g !== gap[0])) return `${where}, hex ${x + k}: a gap in one layer only`;
      if (gap[0]) continue;
      const [t, g, o] = [TERRAIN_CHARS, GROUND_CHARS, OUTLINE_CHARS].map((chars, n) =>
        n < layers.length ? (chars as readonly string[]).indexOf(layers[n]![k]!) : 1,
      ) as [number, number, number];
      if (t < 0 || g < 0 || o < 0) return `${where}, hex ${x + k}: an unknown character`;
      hexes.set(keyOf({ x: x + k, y }), cellOf(t === 1 ? WALL : FLOOR, g, o === 0));
    }
  }
  return hexes;
}

function loadVersion2(raw: Record<string, unknown>, meta: MapMeta): LoadResult {
  const hexes = readRows(raw.rows, meta.kind === "zone");
  if (typeof hexes === "string") return { problem: `The file is refused: ${hexes}.` };
  const origin = readOrigin(raw.chunks);
  if (typeof origin === "string") return { problem: `The file is refused: ${origin}.` };
  const obstacles = readObstacles(raw.obstacles, (x, y) => hexes.has(keyOf({ x, y })));
  if (typeof obstacles === "string") return { problem: `The file is refused: ${obstacles}.` };
  const objects = readObjects(raw.objects, meta);
  if (typeof objects === "string") return { problem: `The file is refused: ${objects}.` };
  const editor = typeof raw.editor === "string" ? raw.editor : "unknown";
  return { doc: { meta, hexes, obstacles, objects, origin }, editor, notes: [] };
}

// --- format 1 (CLI-09a), converted on load -------------------------------------------------------

/** Format 1's size bound in chunks, per side. */
const SIZE_MAX_1: Readonly<Record<MapKind, number>> = { zone: 15, town: 4, outpost: 4 };

function readLayer1(
  raw: unknown,
  name: string,
  width: number,
  height: number,
  chars: readonly string[],
): Uint8Array | string {
  if (!Array.isArray(raw) || raw.length !== height)
    return `layer ${name} does not have ${height} rows`;
  const values = new Uint8Array(width * height);
  for (let y = 0; y < height; y++) {
    const row = raw[y];
    if (typeof row !== "string" || row.length !== width) {
      return `layer ${name}, row ${y}: not ${width} characters`;
    }
    for (let x = 0; x < width; x++) {
      const value = chars.indexOf(row[x]!);
      if (value < 0) return `layer ${name}, row ${y}: unknown character ${JSON.stringify(row[x])}`;
      values[y * width + x] = value;
    }
  }
  return values;
}

/**
 * A format 1 file (CLI-09a): a rectangle of `width × height` chunks at `(0, 0)`, every hex filled.
 * Converted: every hex painted as it was (the start fill too), the outline kept, the chunk grid at
 * `(0, 0)` as the author had set it (`nudged`: chosen by hand, not by the fit); the size and the
 * start fill are dropped.
 */
function loadVersion1(raw: Record<string, unknown>, meta: MapMeta): LoadResult {
  const map = raw.map as Record<string, unknown>;
  const max = SIZE_MAX_1[meta.kind];
  if (!isWhole(map.width, 1, max) || !isWhole(map.height, 1, max)) {
    return { problem: `The file is refused: the size is not 1 to ${max} chunks on each side.` };
  }
  if (map.start !== "wall" && map.start !== "floor") {
    return { problem: "The file is refused: the start fill is not wall or floor." };
  }
  const layers = raw.layers;
  if (!isObject(layers)) return { problem: "The file is refused: its layers are missing." };
  const width = map.width * CHUNK;
  const height = map.height * CHUNK;
  const terrain = readLayer1(layers.terrain, "terrain", width, height, TERRAIN_CHARS);
  if (typeof terrain === "string") return { problem: `The file is refused: ${terrain}.` };
  const ground = readLayer1(layers.ground, "ground", width, height, GROUND_CHARS);
  if (typeof ground === "string") return { problem: `The file is refused: ${ground}.` };
  let outline: Uint8Array | null = null;
  if (meta.kind === "zone") {
    const read = readLayer1(layers.outline, "outline", width, height, OUTLINE_CHARS);
    if (typeof read === "string") return { problem: `The file is refused: ${read}.` };
    outline = read;
  } else if (layers.outline !== null && layers.outline !== undefined) {
    return { problem: `The file is refused: a ${meta.kind} has no outline.` };
  }
  const hexes = new Map<number, Cell>();
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const t = terrain[i] === 1 ? WALL : FLOOR;
      hexes.set(keyOf({ x, y }), cellOf(t, ground[i]!, outline ? outline[i] === 0 : false));
    }
  }
  const obstacles = readObstacles(
    raw.obstacles,
    (x, y) => x >= 0 && y >= 0 && x < width && y < height,
  );
  if (typeof obstacles === "string") return { problem: `The file is refused: ${obstacles}.` };
  const editor = typeof raw.editor === "string" ? raw.editor : "unknown";
  return {
    doc: { meta, hexes, obstacles, objects: new Map(), origin: { x: 0, y: 0, how: "nudged" } },
    editor,
    notes: [
      `Converted from format 1: its ${map.width} × ${map.height} chunks are painted, the chunk grid kept at (0, 0). Saving writes format ${FORMAT_VERSION}.`,
    ],
  };
}

/**
 * Reads a saved file. A file that fails to read, or of a newer format, is refused with the reason
 * (the caller leaves the open map untouched); a format 1 file is converted, with a note.
 */
export function loadMap(text: string): LoadResult {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return { problem: "The file is not JSON." };
  }
  if (!isObject(raw) || raw.format !== FORMAT) {
    return { problem: "The file is not a Grim World map (its format is not grimworld-map)." };
  }
  if (!isWhole(raw.version, 1)) return { problem: "The file's version is not a whole number." };
  if (raw.version > FORMAT_VERSION) {
    return {
      problem: `The file is of version ${raw.version}, newer than this editor's (${FORMAT_VERSION}): open it with a newer editor.`,
    };
  }
  const meta = readMeta(raw.map);
  if (typeof meta === "string") return { problem: `The file is refused: ${meta}.` };
  return raw.version === 1 ? loadVersion1(raw, meta) : loadVersion2(raw, meta);
}
