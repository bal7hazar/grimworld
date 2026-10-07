import { TILE_WIDTH } from "../input/coords";
import type { ServiceId } from "../input/intent";
import type { Tile } from "../render/view";
import { footprint } from "../sandbox/fixtures/hubWorld";
import { BUILDINGS, OUTPOST_SERVICES, TOWN_SERVICES } from "../sandbox/fixtures/hubs";
import type { MapMeta } from "./model";
import { PACK_ROWS, type PackObject } from "./pack";
import type { RecordResult } from "./palette";

/**
 * The objects a map holds (CLI-09b, brief §4.2 and §4.3), each on one hex. A tool's data, not a
 * rule: the quotas, spawn templates and gates name records the editor does not read.
 *
 * - A zone (§4.2): the entry, gates, candidate quota places (one quota each, by its index in the
 *   map's quota list), features and spawn points. Only what ENG-08 puts on chain (D-215).
 * - A town or an outpost (§4.3): places (a service or the gate, in a building), decor buildings,
 *   props, figure spots and the arrival. Client data only (D-03, D-202).
 */

/** `GATE`'s `kind` (`models/gate.cairo:9-14`). */
export type GateKind = "hub" | "link" | "floor" | "rift";
export const GATE_KINDS: readonly GateKind[] = ["hub", "link", "floor", "rift"];

/** A quota's kind (ENG-05 l.141). */
export type QuotaKind = "exit" | "heart" | "vein" | "collector" | "landmark" | "setPiece";
export const QUOTA_KINDS: readonly QuotaKind[] = [
  "exit",
  "heart",
  "vein",
  "collector",
  "landmark",
  "setPiece",
];

/** An authored object of a zone's chunk (ENG-08 l.159-161). */
export type FeatureKind = "chest" | "node" | "trap" | "landmark" | "lever";
export const FEATURE_KINDS: readonly FeatureKind[] = ["chest", "node", "trap", "landmark", "lever"];

/** One quota of the map's list (`QUOTAS`: kind, parameter, count; ENG-08 l.55). */
export interface Quota {
  readonly kind: QuotaKind;
  readonly param: number;
  readonly count: number;
}

/** A building of the atlas a town draws (`fixtures/hubs.ts`'s table). */
export type BuildingName = keyof typeof BUILDINGS;
export const BUILDING_NAMES = Object.keys(BUILDINGS) as BuildingName[];

/** The props a town places: the atlas's stills of role `prop` the hubs use. */
export const PROP_SPRITES: readonly string[] = [
  "tree1",
  "tree2",
  "tree3",
  "tree4",
  "bush1",
  "bush2",
  "bush3",
  "rock1",
  "rock2",
  "rock3",
  "rock4",
  "stump1",
  "stump2",
  "sheep",
];

/** What a town place leads to: a service's screen or the Gate screen. */
export type PlaceTarget = ServiceId | "gate";

export type MapObject =
  | { readonly kind: "entry"; readonly at: Tile }
  | {
      readonly kind: "gate";
      readonly at: Tile;
      /** The gate's own registry id (`GATE`'s id; CLI-09c). */
      readonly id: number;
      /** The destination's location id (by id until ENG-08's schema names it, §10). */
      readonly to: number;
      readonly gate: GateKind;
      readonly rank: number;
      /** A quest's id, 0 for none. */
      readonly quest: number;
      /** Where the gate enters its destination: chunk and tile indices. */
      readonly entryChunk: number;
      readonly entryTile: number;
    }
  | { readonly kind: "candidate"; readonly at: Tile; readonly quota: number }
  | {
      readonly kind: "feature";
      readonly at: Tile;
      readonly feature: FeatureKind;
      /** A landmark's or a terrain trap's skill's registry id; 0 for the others (CLI-09c). */
      readonly param: number;
    }
  | { readonly kind: "spawn"; readonly at: Tile; readonly template: number }
  | {
      readonly kind: "place";
      /** Its door: the middle of the building's base stands on the hex. */
      readonly at: Tile;
      readonly target: PlaceTarget;
      readonly building: BuildingName;
      /** Rows behind its base row (`DEFAULT_DEPTH` 1). */
      readonly depth: number;
      readonly mirror: boolean;
    }
  | {
      readonly kind: "decor";
      readonly at: Tile;
      readonly building: BuildingName;
      readonly depth: number;
      readonly mirror: boolean;
    }
  | { readonly kind: "prop"; readonly at: Tile; readonly sprite: string; readonly mirror: boolean }
  | { readonly kind: "figure"; readonly at: Tile; readonly facing: "left" | "right" }
  | { readonly kind: "arrival"; readonly at: Tile }
  // The pack's buildings, characters, props and bridges (CLI-09e part 2, `pack.ts`).
  | PackObject;

export type ObjectKind = MapObject["kind"];

/** One object of a kind. */
type Of<K extends ObjectKind> = Extract<MapObject, { kind: K }>;

/** The services a hub's list holds (E-14): the town's or the outpost's. */
export function servicesOf(kind: "town" | "outpost"): readonly ServiceId[] {
  return kind === "town" ? TOWN_SERVICES : OUTPOST_SERVICES;
}

/** The building a new place of a service stands in: as the town's fixture places it. */
export const DEFAULT_BUILDING: Readonly<Record<PlaceTarget, BuildingName>> = {
  guild: "castle",
  enchanter: "tower",
  trainer: "barracks",
  smith: "forge",
  armorer: "archery",
  alchemist: "cloister",
  market: "market_hall",
  vault: "grain_silo",
  gate: "watchtower",
};

/** Two letters at most, on the marker: colour is never the only carrier (design/11 l.175-182). */
const QUOTA_LETTERS: Readonly<Record<QuotaKind, string>> = {
  exit: "QX",
  heart: "QH",
  vein: "QV",
  collector: "QC",
  landmark: "QL",
  setPiece: "QS",
};

const FEATURE_LETTERS: Readonly<Record<FeatureKind, string>> = {
  chest: "FC",
  node: "FN",
  trap: "FT",
  landmark: "FL",
  lever: "FV",
};

const PLACE_LETTERS: Readonly<Record<PlaceTarget, string>> = {
  guild: "Gu",
  trainer: "Tr",
  smith: "Sm",
  armorer: "Ar",
  enchanter: "En",
  alchemist: "Al",
  market: "Ma",
  vault: "Va",
  gate: "Ga",
};

export const QUOTA_NAMES: Readonly<Record<QuotaKind, string>> = {
  exit: "Exit",
  heart: "Heart",
  vein: "Vein",
  collector: "Collector",
  landmark: "Landmark",
  setPiece: "Set piece",
};

export const FEATURE_NAMES: Readonly<Record<FeatureKind, string>> = {
  chest: "Chest",
  node: "Gathering node",
  trap: "Terrain trap",
  landmark: "Landmark",
  lever: "Lever",
};

/** The palette's choices for a new object (§2.3). */
export interface PlaceChoice {
  readonly kind: ObjectKind;
  /** The candidate's quota index. */
  readonly quota?: number;
  readonly feature?: FeatureKind;
  readonly target?: PlaceTarget;
  readonly building?: BuildingName;
  readonly sprite?: string;
  /** A pack object's kind id (CLI-09e: the palette's choice). */
  readonly type?: string;
}

/**
 * A field of a kind (§2.4): what the inspector edits in place and the file reads back.
 * - `number`: a whole number, 0 or more;
 * - `choice`: one of `options` (the inspector's list for the map), or anything `valid` accepts when
 *   a file is read (default: the options' values);
 * - `toggle`: on or off.
 */
export type FieldSpec =
  | {
      readonly key: string;
      readonly label: string;
      readonly type: "number";
      /** What a file without the field reads (a field added after the file was written). */
      readonly fallback?: number;
    }
  | {
      readonly key: string;
      readonly label: string;
      readonly type: "choice";
      /** The object is the one the inspector shows; null when a file is read. */
      readonly options: (
        meta: MapMeta,
        object: MapObject | null,
      ) => readonly (readonly [value: string, label: string])[];
      /** The value is a number written as the option's value. */
      readonly numeric?: boolean;
      readonly valid?: (value: unknown) => boolean;
      readonly fallback?: string;
    }
  | { readonly key: string; readonly label: string; readonly type: "toggle" };

/** What the game draws for a town object (`structures()`, `hubWorld.ts:72-108`). */
export interface StructureLook {
  /** A figure is a pack character (CLI-09e part 3): the renderer loops its `animation`. */
  readonly kind: "building" | "prop" | "figure";
  readonly sprite: string;
  readonly animation?: string;
  readonly width: number;
  readonly height: number;
  readonly shape?: "house" | "decor" | "gate";
  /** Mirrored by the look itself (a prop's facing); else the object's `mirror` says. */
  readonly mirror?: boolean;
}

/**
 * **The kind table** (CLI-09b; open for CLI-09e's props, buildings, NPCs and bridges): everything
 * the editor knows of a kind, in one row. A new kind joins the `MapObject` union and adds its row
 * here; the model, the file, the palette, the inspector, the markers, the walk's world and the
 * validation's flags read the row, not a switch.
 */
export interface KindSpec<O extends MapObject = MapObject> {
  /** Which maps hold it (the pack's objects: both). */
  readonly map: "zone" | "town" | "both";
  readonly name: string;
  /** One a map: placing another moves it (§3, "one entry per map"). */
  readonly single?: boolean;
  /** The marker's one or two letters (§2.3); `gate` is the gate's number, in placing order. */
  readonly letters: (object: O, context: { gate: number; quotas: readonly Quota[] }) => string;
  readonly fields: readonly FieldSpec[];
  /** A line the inspector shows under the fields. */
  readonly note?: string;
  readonly create: (choice: PlaceChoice, at: Tile) => O;
  /** A zone's on-chain object: on a walkable hex inside the outline (R-14, E-10). */
  readonly onWalkable?: boolean;
  /** What it counts against per chunk (R-15): spawn points, objects, or quota candidates (○). */
  readonly perChunk?: "spawn" | "object" | "candidate";
  /** A town's building: the hexes it stands on, its door included (E-16's footprint). */
  readonly footprint?: (object: O) => Tile[];
  /** The hexes it makes walls of in the walk's world (a place's door stays floor). */
  readonly covers?: (object: O) => Tile[];
  /** How the renderer draws it (a building, a prop or a character); none for a marker only. */
  readonly look?: (object: O) => StructureLook;
  /** The hexes its look is drawn on: `at` when absent; several for a repeated sprite (a bridge). */
  readonly drawnAt?: (object: O) => Tile[];
  /** The record ENG-08's export writes for it, or what is wrong with it (a pack object). */
  readonly record?: (object: O) => RecordResult;
}

/** A hub's footprints are measured from its origin; any origin gives the same hexes. */
const ROOM = { origin: { x: 0, y: 0 } };

function buildingFootprint(object: { at: Tile; building: BuildingName; depth: number }): Tile[] {
  const [width] = BUILDINGS[object.building];
  return footprint(ROOM, { at: object.at, width, depth: object.depth });
}

const whole = (key: string, label: string): FieldSpec => ({ key, label, type: "number" });
const named =
  <T extends string>(
    values: readonly T[],
    label: (value: T) => string = (v) => v,
  ): ((meta: MapMeta) => readonly (readonly [string, string])[]) =>
  () =>
    values.map((v) => [v, label(v)] as const);
const cap = (s: string) => s[0]!.toUpperCase() + s.slice(1);
const MIRROR: FieldSpec = { key: "mirror", label: "Mirror [H]", type: "toggle" };
const DEPTH = whole("depth", "Depth (rows)");
const BUILDING: FieldSpec = {
  key: "building",
  label: "Building",
  type: "choice",
  options: named(BUILDING_NAMES),
};

/** Every service and the gate: what a file's place may name (a service off the hub's list warns). */
const TARGETS: readonly PlaceTarget[] = [
  "guild",
  "trainer",
  "smith",
  "armorer",
  "enchanter",
  "alchemist",
  "market",
  "vault",
  "gate",
];

export const KINDS: { readonly [K in ObjectKind]: KindSpec<Of<K>> } = {
  entry: {
    map: "zone",
    name: "Entry",
    single: true,
    letters: () => "E",
    fields: [],
    create: (_, at) => ({ kind: "entry", at }),
  },
  gate: {
    map: "zone",
    name: "Gate",
    letters: (_, { gate }) => `G${gate}`,
    fields: [
      { key: "id", label: "Gate id", type: "number", fallback: 0 },
      whole("to", "Destination id"),
      {
        key: "gate",
        label: "Gate kind",
        type: "choice",
        options: named(GATE_KINDS, (g) => g.toUpperCase()),
      },
      whole("rank", "Rank required"),
      whole("quest", "Quest (0 none)"),
      whole("entryChunk", "Entry chunk"),
      whole("entryTile", "Entry tile"),
    ],
    create: (_, at) => ({
      kind: "gate",
      at,
      id: 0,
      to: 0,
      gate: "hub",
      rank: 0,
      quest: 0,
      entryChunk: 0,
      entryTile: 0,
    }),
  },
  candidate: {
    map: "zone",
    name: "Quota place",
    letters: (o, { quotas }) => {
      const quota = quotas[o.quota];
      return quota ? QUOTA_LETTERS[quota.kind] : "Q?";
    },
    fields: [
      {
        key: "quota",
        label: "For quota",
        type: "choice",
        numeric: true,
        options: (meta) =>
          meta.quotas.map((q, i) => [String(i), `Q${i + 1} ${QUOTA_NAMES[q.kind]}`]),
        // A file may name a quota its list lacks: R-13 says so.
        valid: (v) => typeof v === "number" && Number.isInteger(v) && v >= 0,
      },
    ],
    create: (choice, at) => ({ kind: "candidate", at, quota: choice.quota ?? 0 }),
    onWalkable: true,
    perChunk: "candidate",
  },
  feature: {
    map: "zone",
    name: "Feature",
    letters: (o) => FEATURE_LETTERS[o.feature],
    fields: [
      {
        key: "feature",
        label: "Feature",
        type: "choice",
        options: named(FEATURE_KINDS, (f) => FEATURE_NAMES[f]),
      },
      { key: "param", label: "Landmark or trap skill id", type: "number", fallback: 0 },
    ],
    create: (choice, at) => ({ kind: "feature", at, feature: choice.feature ?? "chest", param: 0 }),
    onWalkable: true,
    perChunk: "object",
  },
  spawn: {
    map: "zone",
    name: "Spawn point",
    letters: () => "P",
    fields: [whole("template", "Pack template")],
    note: "Its level and its goblin count are drawn at entry (D-215).",
    // A template id is typed by the author: 0 is refused by E-19 until then.
    create: (_, at) => ({ kind: "spawn", at, template: 0 }),
    onWalkable: true,
    perChunk: "spawn",
  },
  place: {
    map: "town",
    name: "Place",
    letters: (o) => PLACE_LETTERS[o.target],
    fields: [
      {
        key: "target",
        label: "Service",
        type: "choice",
        options: (meta) =>
          [...servicesOf(meta.kind === "outpost" ? "outpost" : "town"), "gate"].map(
            (s) => [s, cap(s)] as const,
          ),
        valid: (v) => TARGETS.includes(v as PlaceTarget),
      },
      BUILDING,
      DEPTH,
      MIRROR,
    ],
    create: (choice, at) => {
      const target = choice.target ?? "gate";
      return {
        kind: "place",
        at,
        target,
        building: choice.building ?? DEFAULT_BUILDING[target],
        depth: 1,
        mirror: false,
      };
    },
    footprint: buildingFootprint,
    covers: (o) => buildingFootprint(o).filter((t) => t.x !== o.at.x || t.y !== o.at.y),
    look: (o) => ({
      kind: "building",
      sprite: o.building,
      width: BUILDINGS[o.building][0],
      height: BUILDINGS[o.building][1],
      shape: o.target === "gate" ? "gate" : "house",
    }),
  },
  decor: {
    map: "town",
    name: "Decor building",
    letters: () => "D",
    fields: [BUILDING, DEPTH, MIRROR],
    create: (choice, at) => ({
      kind: "decor",
      at,
      building: choice.building ?? "cottage",
      depth: 1,
      mirror: false,
    }),
    footprint: buildingFootprint,
    covers: buildingFootprint,
    look: (o) => ({
      kind: "building",
      sprite: o.building,
      width: BUILDINGS[o.building][0],
      height: BUILDINGS[o.building][1],
      shape: "decor",
    }),
  },
  prop: {
    map: "town",
    name: "Prop",
    letters: () => "p",
    fields: [
      {
        key: "sprite",
        label: "Prop",
        type: "choice",
        options: named(PROP_SPRITES),
        // A still's name: the atlas may hold more than the list (CLI-09e).
        valid: (v) => typeof v === "string" && v.length > 0,
      },
      MIRROR,
    ],
    create: (choice, at) => ({ kind: "prop", at, sprite: choice.sprite ?? "tree1", mirror: false }),
    covers: (o) => [o.at],
    look: (o) => ({ kind: "prop", sprite: o.sprite, width: TILE_WIDTH, height: TILE_WIDTH }),
  },
  figure: {
    map: "town",
    name: "Figure spot",
    letters: () => "A",
    fields: [
      {
        key: "facing",
        label: "Faces",
        type: "choice",
        options: named(["left", "right"] as const, cap),
      },
    ],
    create: (_, at) => ({ kind: "figure", at, facing: "right" }),
  },
  arrival: {
    map: "town",
    name: "Arrival",
    single: true,
    letters: () => "In",
    fields: [],
    create: (_, at) => ({ kind: "arrival", at }),
  },
  ...PACK_ROWS,
};

/** A kind's row, for an object of any kind. */
export function kindOf(object: MapObject): KindSpec {
  return KINDS[object.kind] as unknown as KindSpec;
}

export const OBJECT_KINDS = Object.keys(KINDS) as ObjectKind[];
export const ZONE_OBJECTS = OBJECT_KINDS.filter((k) => KINDS[k].map !== "town");
export const TOWN_OBJECTS = OBJECT_KINDS.filter((k) => KINDS[k].map !== "zone");

/** Whether a map of that kind holds a kind of object. */
export function mapHolds(zone: boolean, kind: ObjectKind): boolean {
  const map = KINDS[kind].map;
  return map === "both" || (map === "zone") === zone;
}
export const SINGLE = OBJECT_KINDS.filter((k) => KINDS[k].single);
export const OBJECT_NAMES = Object.fromEntries(
  OBJECT_KINDS.map((k) => [k, KINDS[k].name]),
) as Readonly<Record<ObjectKind, string>>;

/** The kinds a map of that kind holds. */
export function objectKindsOf(zone: boolean): readonly ObjectKind[] {
  return zone ? ZONE_OBJECTS : TOWN_OBJECTS;
}

/** The marker's label (§2.3), from the kind's row. */
export function objectLabel(
  object: MapObject,
  gateNumber: number,
  quotas: readonly Quota[],
): string {
  return kindOf(object).letters(object, { gate: gateNumber, quotas });
}

/** Whether `mirror` applies (§3, Mirror): the kind has the field. */
export function mirrorable(object: MapObject): boolean {
  return kindOf(object).fields.some((f) => f.key === "mirror");
}

export function newObject(choice: PlaceChoice, at: Tile): MapObject {
  return (KINDS[choice.kind] as unknown as KindSpec).create(choice, at);
}

/** The same object moved by `(dx, dy)`. */
export function movedBy(object: MapObject, dx: number, dy: number): MapObject {
  return { ...object, at: { x: object.at.x + dx, y: object.at.y + dy } };
}

/**
 * An object read from a file by its kind's row: its fields checked as the inspector writes them;
 * null when a field is missing or wrong.
 */
export function objectFrom(
  kind: ObjectKind,
  at: Tile,
  raw: Readonly<Record<string, unknown>>,
  meta: MapMeta,
): MapObject | null {
  const out: Record<string, unknown> = { kind, at };
  for (const field of KINDS[kind].fields) {
    const v = raw[field.key] === undefined && "fallback" in field ? field.fallback : raw[field.key];
    if (field.type === "number") {
      if (typeof v !== "number" || !Number.isInteger(v) || v < 0) return null;
    } else if (field.type === "toggle") {
      if (typeof v !== "boolean") return null;
    } else {
      const ok = field.valid
        ? field.valid(v)
        : field
            .options(meta, null)
            .some(([value]) => (field.numeric ? Number(value) : value) === v);
      if (!ok) return null;
    }
    out[field.key] = v;
  }
  return out as unknown as MapObject;
}
