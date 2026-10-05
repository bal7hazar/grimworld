import {
  BIOMES,
  type Biome,
  MAP_KINDS,
  type MapDocument,
  type MapKind,
  type MapMeta,
  NAME_MAX,
  SIZE_MAX,
  tilesHigh,
  tilesWide,
} from "./model";

/**
 * The editor's own file (brief §6, `.grimmap.json`): one JSON document, the editor's to shape
 * (the registration export is CLI-09c's, in ENG-08's schema). Each layer is a list of rows, row
 * `y = 0` first, one character per hex, `x = 0` first:
 *
 * - `terrain`: `.` floor, `#` wall (the walkable plane);
 * - `ground`: `g` grass, `e` earth, `w` water;
 * - `outline` (a zone only): `1` inside, `0` outside.
 *
 * Pinned obstacle looks are a list of `{ x, y, sprite }`: a still's name, never pixels (§7).
 */

export const FORMAT = "grimworld-map";
/** The format's version: a file of a newer one is refused, an older one migrated (§6). */
export const FORMAT_VERSION = 1;

/** The editor's version written in a file: the client's commit when the build was given one. */
export const EDITOR_VERSION: string =
  (import.meta.env?.VITE_GRIMWORLD_COMMIT as string | undefined) ?? "dev";

/** By value: `FLOOR` 0, `WALL` 1; `GROUND_KINDS` grass, earth, water. */
const TERRAIN_CHARS = [".", "#"] as const;
const GROUND_CHARS = ["g", "e", "w"] as const;
const OUTLINE_CHARS = ["0", "1"] as const;

export interface MapFile {
  readonly format: typeof FORMAT;
  readonly version: number;
  readonly editor: string;
  readonly map: MapMeta;
  readonly layers: {
    readonly terrain: readonly string[];
    readonly ground: readonly string[];
    readonly outline: readonly string[] | null;
  };
  readonly obstacles: readonly { readonly x: number; readonly y: number; readonly sprite: string }[];
}

function rows(values: Uint8Array, width: number, chars: readonly string[]): string[] {
  const out: string[] = [];
  for (let start = 0; start < values.length; start += width) {
    let row = "";
    for (let i = start; i < start + width; i++) row += chars[values[i]!];
    out.push(row);
  }
  return out;
}

/** The file of a document. */
export function toFile(doc: MapDocument, editor = EDITOR_VERSION): MapFile {
  const width = tilesWide(doc.meta);
  return {
    format: FORMAT,
    version: FORMAT_VERSION,
    editor,
    map: { ...doc.meta },
    layers: {
      terrain: rows(doc.terrain, width, TERRAIN_CHARS),
      ground: rows(doc.ground, width, GROUND_CHARS),
      outline: doc.outline ? rows(doc.outline, width, OUTLINE_CHARS) : null,
    },
    obstacles: [...doc.obstacles]
      .sort(([a], [b]) => a - b)
      .map(([index, sprite]) => ({ x: index % width, y: Math.floor(index / width), sprite })),
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

function readMeta(raw: unknown): MapMeta | string {
  if (!isObject(raw)) return "the map's fields are missing";
  const kind = raw.kind as MapKind;
  if (!MAP_KINDS.includes(kind)) return `unknown kind ${JSON.stringify(raw.kind)}`;
  const { name } = raw;
  if (typeof name !== "string" || name.trim().length === 0 || name.length > NAME_MAX) {
    return `the name is not 1 to ${NAME_MAX} characters`;
  }
  const max = SIZE_MAX[kind];
  if (!isWhole(raw.width, 1, max) || !isWhole(raw.height, 1, max)) {
    return `the size is not 1 to ${max} chunks on each side`;
  }
  const biome = raw.biome as Biome | null;
  if (kind === "zone" ? !BIOMES.includes(biome as Biome) : biome !== null) {
    return `the biome ${JSON.stringify(raw.biome)} does not suit a ${kind}`;
  }
  if (raw.start !== "wall" && raw.start !== "floor") return "the start fill is not wall or floor";
  for (const field of ["location", "levelMin", "levelMax", "rank", "spawnTable"] as const) {
    if (!isWhole(raw[field], 0)) return `${field} is not a whole number, 0 or more`;
  }
  return {
    kind,
    name,
    location: raw.location as number,
    width: raw.width,
    height: raw.height,
    biome,
    start: raw.start,
    levelMin: raw.levelMin as number,
    levelMax: raw.levelMax as number,
    rank: raw.rank as number,
    spawnTable: raw.spawnTable as number,
  };
}

function readLayer(
  raw: unknown,
  name: string,
  width: number,
  height: number,
  chars: readonly string[],
): Uint8Array | string {
  if (!Array.isArray(raw) || raw.length !== height) return `layer ${name} does not have ${height} rows`;
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
 * Reads a saved file. A file that fails to read, or of a newer format, is refused with the reason
 * (the caller leaves the open map untouched); an older one would be migrated, with a note.
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
  const layers = raw.layers;
  if (!isObject(layers)) return { problem: "The file is refused: its layers are missing." };
  const width = tilesWide(meta);
  const height = tilesHigh(meta);
  const terrain = readLayer(layers.terrain, "terrain", width, height, TERRAIN_CHARS);
  if (typeof terrain === "string") return { problem: `The file is refused: ${terrain}.` };
  const ground = readLayer(layers.ground, "ground", width, height, GROUND_CHARS);
  if (typeof ground === "string") return { problem: `The file is refused: ${ground}.` };
  let outline: Uint8Array | null = null;
  if (meta.kind === "zone") {
    const read = readLayer(layers.outline, "outline", width, height, OUTLINE_CHARS);
    if (typeof read === "string") return { problem: `The file is refused: ${read}.` };
    outline = read;
  } else if (layers.outline !== null && layers.outline !== undefined) {
    return { problem: `The file is refused: a ${meta.kind} has no outline.` };
  }
  const obstacles = new Map<number, string>();
  if (!Array.isArray(raw.obstacles)) return { problem: "The file is refused: no obstacles list." };
  for (const pin of raw.obstacles) {
    if (
      !isObject(pin) ||
      !isWhole(pin.x, 0, width - 1) ||
      !isWhole(pin.y, 0, height - 1) ||
      typeof pin.sprite !== "string"
    ) {
      return { problem: "The file is refused: an obstacle pin is not { x, y, sprite } in the map." };
    }
    obstacles.set(pin.y * width + pin.x, pin.sprite);
  }
  const editor = typeof raw.editor === "string" ? raw.editor : "unknown";
  return { doc: { meta, terrain, ground, outline, obstacles }, editor, notes: [] };
}
