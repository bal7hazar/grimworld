import type { ServiceId } from "../../input/intent";
import {
  type HubDecor,
  type HubPlace,
  type HubProp,
  type HubTarget,
  type HubView,
  targetLabel,
} from "../../render/hubView";
import type { Profession, Tile } from "../../render/view";
import { OUTPOST, TOWN } from "./region";

/**
 * The hubs the loop walks (CLI-03c), as fixed data: the town (the seed's location 1) and the
 * outpost (a fixture, design/01's Outpost B). Where the buildings stand, who is present, the gold:
 * all written by hand, for the owner's eye (D-178). The present adventurers come from the indexer
 * later (design/09).
 */

/** The town's services, as design/11's sketch places them, row by row in three columns. */
export const TOWN_SERVICES: readonly ServiceId[] = [
  "guild",
  "smith",
  "enchanter",
  "trainer",
  "armorer",
  "alchemist",
  "market",
  "vault",
];

/**
 * The outpost's services: design/01 says "limited services" and leaves which open. **Proposed, the
 * owner's eye** (design/11 *Hubs*): the Guild's board, the Trainer (the build editor before a
 * deeper zone), the Vault. One constant: change it here.
 */
export const OUTPOST_SERVICES: readonly ServiceId[] = ["guild", "trainer", "vault"];

const service = (s: ServiceId): HubTarget => ({ kind: "service", service: s });
const GATE: HubTarget = { kind: "gate" };

/**
 * The buildings of the atlas the hubs draw, and their native size in art pixels (the still's
 * visible width, and its height above the base: `tools/art/build.py`'s table, without its margin).
 * **Proposed, the owner's eye** (CLI-03e): the Blue set for the large buildings, `Buildings/Others/`
 * for the trades and the life around them. Mirrored in `tools/art/README.md` *Buildings*.
 */
export const BUILDINGS = {
  castle: [312, 207],
  barracks: [184, 185],
  archery: [183, 177],
  tower: [120, 184],
  fortress: [126, 232],
  forge: [125, 171],
  cloister: [128, 139],
  market_hall: [127, 152],
  grain_silo: [104, 189],
  barn: [128, 211],
  watchtower: [98, 150],
  windmill: [128, 199],
  inn: [128, 188],
  cottage: [122, 143],
  small_house: [100, 106],
  hut: [100, 112],
  straw_hut: [100, 111],
} as const satisfies Record<string, readonly [number, number]>;

type Building = keyof typeof BUILDINGS;

const tile = (x: number, y: number): Tile => ({ x, y });

/**
 * `depth`: the rows behind the base row the building blocks for the walk (CLI-03f), 1 when not
 * given. **Proposed, the owner's eye**: 0 where the way climbs behind a building's side.
 */
function place(id: ServiceId | "gate", building: Building, at: Tile, depth?: number): HubPlace {
  const target = id === "gate" ? GATE : service(id);
  const [width, height] = BUILDINGS[building];
  return {
    id,
    label: targetLabel(target),
    target,
    building,
    at,
    width,
    height,
    ...(depth === undefined ? {} : { depth }),
  };
}

function decor(id: string, building: Building, at: Tile, depth?: number): HubDecor {
  const [width, height] = BUILDINGS[building];
  return { id, building, at, width, height, ...(depth === undefined ? {} : { depth }) };
}

const prop = (id: string, sprite: string, x: number, y: number, mirror = false): HubProp => ({
  id,
  sprite,
  at: tile(x, y),
  ...(mirror ? { mirror } : {}),
});

/**
 * The town, on the instance's hex grid (CLI-03e): three bands of buildings, doors facing the
 * viewer. **Proposed, the owner's eye**: the Guild in the castle at the back between the
 * Enchanter's tower and a windmill; the Trainer, the Smith and the Armorer along the middle street;
 * the Alchemist, the Market, the Vault and the Gate in front, along the road that leaves by the
 * Gate; the present adventurers on the street between the front and the middle. A path climbs
 * from the road to the middle street and the castle's door. Tiles in the room's coordinates: `x`
 * grows West (to the left), `y` North (up), from the front-right corner.
 */
const town: HubView = {
  name: "Town A",
  gold: 1240,
  width: 704,
  height: 960,
  origin: { x: 672, y: 912 },
  places: [
    place("guild", "castle", tile(5, 12)),
    place("enchanter", "tower", tile(1, 12)),
    place("trainer", "barracks", tile(8, 7)),
    place("smith", "forge", tile(5, 7)),
    place("armorer", "archery", tile(2, 7)),
    place("alchemist", "cloister", tile(8, 1)),
    // The way climbs behind the market hall's side, (5, 2): open (CLI-03f).
    place("market", "market_hall", tile(5, 1), 0),
    place("vault", "grain_silo", tile(3, 1)),
    place("gate", "watchtower", tile(1, 1)),
  ],
  decor: [
    decor("windmill", "windmill", tile(9, 12)),
    decor("house", "small_house", tile(0, 7)),
    decor("cottage", "cottage", tile(8, 3)),
  ],
  props: [
    prop("tree-back-w", "tree4", 9, 13),
    prop("tree-back", "tree3", 2, 13, true),
    prop("tree-e", "tree1", 0, 11, true),
    prop("tree-mid-e", "tree2", 1, 8),
    prop("bush-1", "bush1", 6, 9),
    prop("bush-2", "bush3", 1, 10, true),
    prop("bush-3", "bush2", 0, 5),
    prop("bush-4", "bush1", 6, 4, true),
    prop("rock-1", "rock2", 0, 1),
    prop("rock-2", "rock4", 2, 1),
    prop("rock-3", "rock3", 7, 2),
    prop("stump-1", "stump1", 8, 5),
    prop("sheep-1", "sheep", 2, 10),
    prop("sheep-2", "sheep", 3, 10, true),
  ],
  figures: [
    { id: 11, name: "Maren", profession: "warden", level: 7, at: tile(7, 5), facing: "right" },
    { id: 12, name: "Tobin", profession: "vanguard", level: 3, at: tile(2, 5), facing: "left" },
    { id: 13, name: "Ilse", profession: "cleric", level: 12, at: tile(8, 11), facing: "right" },
  ],
  services: [...TOWN_SERVICES.map(service), GATE],
  // The road's hex South-West of the Gate's door, on the town's side (CLI-03f, the owner's eye).
  arrival: tile(2, 0),
};

/**
 * The outpost: smaller, two bands, a palisade's worth of props, fewer services, one adventurer
 * present. **Proposed, the owner's eye**: the Guild in the fortress, the Trainer in the barracks,
 * the Vault in the barn, the Gate a watchtower at the road's end.
 */
const outpost: HubView = {
  name: "Outpost B",
  gold: 1240,
  width: 576,
  height: 704,
  origin: { x: 512, y: 656 },
  places: [
    place("guild", "fortress", tile(2, 7)),
    place("trainer", "barracks", tile(5, 7)),
    place("vault", "barn", tile(6, 2)),
    place("gate", "watchtower", tile(1, 2)),
  ],
  // The way climbs behind the straw hut, (3, 3): open (CLI-03f).
  decor: [decor("hut", "hut", tile(0, 7)), decor("straw-hut", "straw_hut", tile(4, 2), 0)],
  props: [
    prop("tree-back-w", "tree1", 7, 8),
    prop("tree-back-e", "tree3", 0, 8, true),
    prop("tree-w", "tree4", 7, 6),
    prop("stump-1", "stump2", 6, 6),
    prop("stump-2", "stump1", 1, 5, true),
    prop("rock-1", "rock1", 3, 4),
    prop("rock-2", "rock3", 0, 4),
    prop("rock-3", "rock4", 5, 0),
    prop("rock-4", "rock2", 2, 0, true),
    prop("bush-1", "bush2", 2, 6),
    prop("sheep-1", "sheep", 0, 6),
  ],
  figures: [
    { id: 21, name: "Corvin", profession: "vanguard", level: 9, at: tile(2, 3), facing: "left" },
  ],
  services: [...OUTPOST_SERVICES.map(service), GATE],
  // The road's hex South-West of the Gate's door, as in the town (CLI-03f, the owner's eye).
  arrival: tile(1, 1),
};

/** Tiles `from`..`to` of row `y`. */
function row(y: number, from: number, to: number): Tile[] {
  const out: Tile[] = [];
  for (let x = Math.min(from, to); x <= Math.max(from, to); x++) out.push(tile(x, y));
  return out;
}

/**
 * Each hub's path, drawn as earth (CLI-03e's road, back with CLI-03g1): from the arrival along the
 * front road, up to the middle street and the castle's door (the town), or to the fortress's
 * (the outpost). **Proposed, the owner's eye.** Presentation only: a path hex is walked like any
 * floor hex; a hex a building covers stays grass under it.
 */
export const HUB_PATHS: ReadonlyMap<HubView, readonly Tile[]> = new Map([
  [
    town,
    [
      ...row(0, 0, 9),
      tile(4, 1),
      tile(5, 2),
      tile(4, 3),
      tile(4, 4),
      tile(4, 5),
      ...row(6, 2, 9),
      tile(4, 7),
      tile(4, 8),
      tile(4, 9),
      tile(4, 10),
      ...row(11, 1, 8),
    ],
  ],
  [outpost, [...row(1, 0, 7), tile(3, 3), tile(4, 4), tile(3, 5), tile(4, 6)]],
]);

/** Each hub's view, by location id. */
export const HUB_VIEWS: ReadonlyMap<number, HubView> = new Map([
  [TOWN, town],
  [OUTPOST, outpost],
]);

/** The names `?hub=` takes. */
export const HUB_NAMES: Readonly<Record<string, number>> = { town: TOWN, outpost: OUTPOST };

/** A figure and its maximum (CLI-03l): health, energy. */
export interface Gauge {
  readonly current: number;
  readonly max: number;
}

/** The player's adventurer, as the Gate screen and the desktop's left panel show it. */
export interface AdventurerSheet {
  readonly name: string;
  readonly profession: Profession;
  readonly level: number;
  /** The skill bar: 8 slots, in order; null is an empty slot. */
  readonly bar: readonly (string | null)[];
  readonly attributes: readonly (readonly [string, number])[];
  /** The belt: what is taken from the pack into its reserve at entry (D-141). */
  readonly belt: readonly (readonly [string, number])[];
  /**
   * What the bar cannot do, for design/11's reminder (never a block). Fixed data: which skills
   * heal, cleanse or reach is the rules', and CLI-07's build editor reads it from them.
   */
  readonly cannot: readonly string[];
  /** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */
  readonly health: Gauge;
  /** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */
  readonly energy: Gauge;
  /**
   * PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. Strikes of adrenaline (no
   * maximum, design/04); null for a profession without it.
   */
  readonly adrenaline: number | null;
}

export const ADVENTURER: AdventurerSheet = {
  name: "Wren",
  profession: "vanguard",
  level: 4,
  bar: ["Cleave", "Shield bash", "Charge", "Taunt", "Second wind", null, null, null],
  attributes: [
    ["Strength", 8],
    ["Tactics", 4],
    ["Endurance", 6],
  ],
  belt: [
    ["Healing potion", 3],
    ["Antidote", 1],
  ],
  cannot: ["no condition removal", "nothing at range"],
  // design/03's figures for a level-4 Vanguard, written as data, not computed (the HUD reads them).
  /** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */
  health: { current: 160, max: 160 },
  /** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */
  energy: { current: 20, max: 20 },
  /** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */
  adrenaline: 0,
};

/** The figures of a closing report: fixed, nothing computed (design/02 *Ending an expedition*). */
export interface ReportFigures {
  readonly experience: number;
  readonly loot: readonly string[];
  readonly quests: readonly string[];
  /** The belt's potions not used, credited back to the pack (D-141). */
  readonly beltBack: readonly string[];
}

export const REPORT_FIGURES: Readonly<Record<"returned" | "defeated", ReportFigures>> = {
  returned: {
    experience: 140,
    loot: ["Runt tooth × 3", "Copper ore × 2", "Worn leather cap"],
    quests: ["Clear the meadow: 3 / 5 runts"],
    beltBack: ["Healing potion × 2 back to the pack (1 drunk)", "Antidote × 1 back to the pack"],
  },
  defeated: {
    experience: 60,
    loot: ["Runt tooth × 1"],
    quests: ["Clear the meadow: 1 / 5 runts"],
    beltBack: ["Healing potion × 0 back to the pack (3 drunk)", "Antidote × 1 back to the pack"],
  },
};
