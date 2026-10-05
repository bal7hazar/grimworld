import type { ServiceId } from "../input/intent";
import type { Tile } from "../render/view";
import { BUILDINGS, OUTPOST_SERVICES, TOWN_SERVICES } from "../sandbox/fixtures/hubs";

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
  | { readonly kind: "feature"; readonly at: Tile; readonly feature: FeatureKind }
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
  | { readonly kind: "arrival"; readonly at: Tile };

export type ObjectKind = MapObject["kind"];

export const ZONE_OBJECTS: readonly ObjectKind[] = [
  "entry",
  "gate",
  "candidate",
  "feature",
  "spawn",
];
export const TOWN_OBJECTS: readonly ObjectKind[] = ["place", "decor", "prop", "figure", "arrival"];

/** The kinds a map of that kind holds. */
export function objectKindsOf(zone: boolean): readonly ObjectKind[] {
  return zone ? ZONE_OBJECTS : TOWN_OBJECTS;
}

/** One a map: placing another moves it (§3, "one entry per map"). */
export const SINGLE: readonly ObjectKind[] = ["entry", "arrival"];

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

/**
 * The marker's label (§2.3): `E` the entry, `G1…` gates by their order, `Q…` candidates by their
 * quota's kind, `F…` features by kind, `P` spawn points; a town's places by service, `D` decor,
 * `p` props, `A` figures, `In` the arrival.
 */
export function objectLabel(
  object: MapObject,
  gateNumber: number,
  quotas: readonly Quota[],
): string {
  switch (object.kind) {
    case "entry":
      return "E";
    case "gate":
      return `G${gateNumber}`;
    case "candidate": {
      const quota = quotas[object.quota];
      return quota ? QUOTA_LETTERS[quota.kind] : "Q?";
    }
    case "feature":
      return FEATURE_LETTERS[object.feature];
    case "spawn":
      return "P";
    case "place":
      return PLACE_LETTERS[object.target];
    case "decor":
      return "D";
    case "prop":
      return "p";
    case "figure":
      return "A";
    case "arrival":
      return "In";
  }
}

/** The kind's name, as the palette, the inspector and the validation say it. */
export const OBJECT_NAMES: Readonly<Record<ObjectKind, string>> = {
  entry: "Entry",
  gate: "Gate",
  candidate: "Quota place",
  feature: "Feature",
  spawn: "Spawn point",
  place: "Place",
  decor: "Decor building",
  prop: "Prop",
  figure: "Figure spot",
  arrival: "Arrival",
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

/** The same object moved by `(dx, dy)`. */
export function movedBy(object: MapObject, dx: number, dy: number): MapObject {
  return { ...object, at: { x: object.at.x + dx, y: object.at.y + dy } };
}

/** Whether `mirror` applies: a building, a decor or a prop (§3, Mirror). */
export function mirrorable(object: MapObject): boolean {
  return object.kind === "place" || object.kind === "decor" || object.kind === "prop";
}

/** A new object of a kind on a hex, with the palette's choices. */
export interface PlaceChoice {
  readonly kind: ObjectKind;
  /** The candidate's quota index. */
  readonly quota?: number;
  readonly feature?: FeatureKind;
  readonly target?: PlaceTarget;
  readonly building?: BuildingName;
  readonly sprite?: string;
}

export function newObject(choice: PlaceChoice, at: Tile): MapObject {
  switch (choice.kind) {
    case "entry":
      return { kind: "entry", at };
    case "gate":
      return {
        kind: "gate",
        at,
        to: 0,
        gate: "hub",
        rank: 0,
        quest: 0,
        entryChunk: 0,
        entryTile: 0,
      };
    case "candidate":
      return { kind: "candidate", at, quota: choice.quota ?? 0 };
    case "feature":
      return { kind: "feature", at, feature: choice.feature ?? "chest" };
    case "spawn":
      // A template id is typed by the author: 0 is refused by E-19 until then.
      return { kind: "spawn", at, template: 0 };
    case "place": {
      const target = choice.target ?? "gate";
      return {
        kind: "place",
        at,
        target,
        building: choice.building ?? DEFAULT_BUILDING[target],
        depth: 1,
        mirror: false,
      };
    }
    case "decor":
      return { kind: "decor", at, building: choice.building ?? "cottage", depth: 1, mirror: false };
    case "prop":
      return { kind: "prop", at, sprite: choice.sprite ?? "tree1", mirror: false };
    case "figure":
      return { kind: "figure", at, facing: "right" };
    case "arrival":
      return { kind: "arrival", at };
  }
}
