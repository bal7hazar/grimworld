import type { ServiceId } from "../../input/intent";
import type { HubPlace, HubTarget, HubView } from "../../render/hubView";
import type { Profession } from "../../render/view";
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

function building(
  id: string,
  label: string,
  target: HubTarget,
  name: string,
  at: readonly [number, number, number, number],
): HubPlace {
  const [x, y, width, height] = at;
  return { id, label, target, building: name, x, y, width, height };
}

/**
 * The town: three rows of buildings on a meadow, a road in front of the last row, the Gate at the
 * road's end. **Proposed, the owner's eye**: the Guild in the castle at the back, the Trainer in
 * the barracks, the Enchanter in the tower, the crafts and the Market along the road, the Vault in
 * front. Illustration units; drawn back to front.
 */
const town: HubView = {
  name: "Town A",
  gold: 1240,
  width: 360,
  height: 300,
  places: [
    building("guild", "Guild", service("guild"), "castle", [180, 112, 128, 96]),
    building("trainer", "Trainer", service("trainer"), "barracks", [62, 120, 84, 72]),
    building("enchanter", "Enchanter", service("enchanter"), "tower", [302, 122, 52, 92]),
    building("smith", "Smith", service("smith"), "house1", [46, 200, 56, 56]),
    building("armorer", "Armorer", service("armorer"), "archery", [124, 204, 72, 62]),
    building("alchemist", "Alchemist", service("alchemist"), "monastery", [234, 206, 70, 72]),
    building("market", "Market", service("market"), "house2", [314, 200, 56, 56]),
    building("vault", "Vault", service("vault"), "house3", [150, 290, 60, 52]),
    building("gate", "Gate", GATE, "gate", [312, 290, 56, 52]),
  ],
  figures: [
    { id: 11, name: "Maren", profession: "warden", level: 7, x: 84, y: 236, facing: "right" },
    { id: 12, name: "Tobin", profession: "vanguard", level: 3, x: 186, y: 240, facing: "left" },
    { id: 13, name: "Ilse", profession: "cleric", level: 12, x: 262, y: 236, facing: "right" },
  ],
  services: [...TOWN_SERVICES.map(service), GATE],
};

/** The outpost: smaller, a palisade's worth of buildings, fewer services, one adventurer present. */
const outpost: HubView = {
  name: "Outpost B",
  gold: 1240,
  width: 300,
  height: 220,
  places: [
    building("guild", "Guild", service("guild"), "house1", [86, 110, 60, 60]),
    building("trainer", "Trainer", service("trainer"), "barracks", [204, 112, 84, 72]),
    building("vault", "Vault", service("vault"), "house2", [90, 208, 56, 56]),
    building("gate", "Gate", GATE, "gate", [244, 208, 56, 52]),
  ],
  figures: [
    { id: 21, name: "Corvin", profession: "vanguard", level: 9, x: 160, y: 156, facing: "left" },
  ],
  services: [...OUTPOST_SERVICES.map(service), GATE],
};

/** Each hub's view, by location id. */
export const HUB_VIEWS: ReadonlyMap<number, HubView> = new Map([
  [TOWN, town],
  [OUTPOST, outpost],
]);

/** The names `?hub=` takes. */
export const HUB_NAMES: Readonly<Record<string, number>> = { town: TOWN, outpost: OUTPOST };

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
