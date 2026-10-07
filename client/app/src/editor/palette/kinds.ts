/**
 * The editor's kind table (CLI-09e): every prop, building, NPC and bridge the author can place, and
 * the atlas sprite that draws it (`tools/art/manifest.toml`). Presentation and authoring data, no
 * rule: whether a prop blocks and which hexes a building covers are proposed here for ENG-08's
 * schema (track game decides, under D-215), and the converter alone writes the walkable plane.
 *
 * Hex sides are numbered as `sideOf` walks them (`../model.ts`): 0 South-East, 1 South-West,
 * 2 West, 3 North-West, 4 North-East, 5 East.
 */

export type Category = "prop" | "building" | "npc" | "bridge";

export const SIDE = {
  southEast: 0,
  southWest: 1,
  west: 2,
  northWest: 3,
  northEast: 4,
  east: 5,
} as const;

/** The rows a building covers behind its base row by default: the hubs' (`DEFAULT_DEPTH`). */
export const BUILDING_DEPTH = 1;

interface KindBase {
  /** The kind id the editor's file and ENG-08's export carry: lower case, digits, `_`. */
  readonly id: string;
  readonly label: string;
  readonly category: Category;
}

/**
 * A prop: one hex. `art` is its sprites: for a prop that turns by `flip`, its variants (the
 * record's `variant` indexes them); for one that turns by `facing`, one sprite per facing 0 to 5,
 * mirrored on the West facings as every sprite (`render/facing.ts`). `blocks`: its hex is not
 * walkable (ENG-08's kind table).
 */
export interface PropKind extends KindBase {
  readonly category: "prop";
  readonly art: readonly string[];
  readonly turn: "flip" | "facing";
  readonly blocks: boolean;
}

/**
 * A building: its sprite, the art's visible width in px (the pack's opaque columns, as the hubs'
 * `BUILDINGS` table measures it) and the rows it covers behind its base row. Its footprint is the
 * hubs' (`sandbox/fixtures/hubWorld.ts`, `footprint`): the hexes whose centres lie under its width,
 * on its base row and `depth` rows behind. Its anchor, the base row's hex under its centre, is its
 * door by default.
 */
export interface BuildingKind extends KindBase {
  readonly category: "building";
  readonly sprite: string;
  readonly width: number;
  readonly depth: number;
}

/**
 * An NPC (ENG-08: a unit template id, a hex, a facing): an idle animation, drawn facing right and
 * mirrored for the West facings (`render/facing.ts`, `isMirrored`). Its id is the template id.
 */
export interface NpcKind extends KindBase {
  readonly category: "npc";
  readonly sprite: string;
  readonly animation: "idle";
}

/**
 * A bridge (D-227, ADR-0008): a deck of one or more hexes over water between two end hexes, one
 * level, the deck walkable. `deck` is the length a new one is placed with, the art's own (the pack
 * draws each bridge whole, North-South, over one deck hex); a longer deck repeats the sprite
 * (CLI-09f).
 */
export interface BridgeKind extends KindBase {
  readonly category: "bridge";
  readonly sprite: string;
  readonly deck: number;
}

/**
 * The longest deck: a bridge lies in one chunk (format 1, `export: bridge across chunks`), so its
 * deck and its two ends fit along a chunk's 15 hexes.
 */
export const BRIDGE_DECK_MAX = 13;

export type Kind = PropKind | BuildingKind | NpcKind | BridgeKind;

const label = (id: string) => {
  const words = id.replace(/_/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
};

const prop = (
  id: string,
  art: readonly string[],
  blocks: boolean,
  turn: PropKind["turn"] = "flip",
): PropKind => ({ id, label: label(id), category: "prop", art, turn, blocks });

const numbered = (stem: string, count: number) =>
  Array.from({ length: count }, (_, i) => `${stem}${i + 1}`);

const building = (id: string, width: number, name = label(id)): BuildingKind => ({
  id,
  label: name,
  category: "building",
  sprite: id,
  width,
  depth: BUILDING_DEPTH,
});

const npc = (id: string, sprite: string, name = label(id)): NpcKind => ({
  id,
  label: name,
  category: "npc",
  sprite,
  animation: "idle",
});

export const PROPS: readonly PropKind[] = [
  prop("tree", numbered("tree", 4), true),
  prop("bush", numbered("bush", 4), false),
  prop("rock", numbered("rock", 4), true),
  prop("stump", numbered("stump", 4), false),
  prop("gold_stone", numbered("gold_stone", 6), true),
  prop("water_rock", numbered("water_rock", 4), true),
  prop("skull_spike", numbered("skull_spike", 2), true),
  prop("bones", numbered("bones", 3), false),
  prop("tool", numbered("tool", 4), false),
  prop("gold", ["gold"], false),
  prop("meat", ["meat"], false),
  prop("logs", ["logs"], false),
  prop("duck", ["duck"], false),
  // East, North-East, North-West, West, South-West, South-East: the pack draws right, up right
  // and down right; the West facings mirror them.
  prop(
    "cannon",
    [
      "cannon_right",
      "cannon_upright",
      "cannon_upright",
      "cannon_right",
      "cannon_downright",
      "cannon_downright",
    ],
    true,
    "facing",
  ),
];

export const BUILDINGS: readonly BuildingKind[] = [
  // Blue, the one colour set (D-178).
  building("castle", 312),
  building("barracks", 184),
  building("archery", 183),
  building("monastery", 160),
  building("tower", 120),
  building("house1", 112, "House 1"),
  building("house2", 128, "House 2"),
  building("house3", 122, "House 3"),
  // `Buildings/Others/`.
  building("abbey", 124),
  building("acueduct", 124),
  building("arbor", 116),
  building("barn", 128),
  building("bourgeois_house", 128),
  building("church", 123),
  building("cloister", 128),
  building("cottage", 122),
  building("farm", 126),
  building("forge", 125),
  building("fortress", 126),
  building("grain_silo", 104),
  building("hall_of_the_gods", 128),
  building("hotel", 128),
  building("hut", 100),
  building("inn", 128),
  building("market_hall", 127),
  building("pigsty", 114),
  building("postal_relay", 109),
  building("rural_house", 122),
  building("sacrificial_house", 116),
  building("small_house", 100),
  building("stable", 125),
  building("straw_hut", 100),
  building("tavern", 128),
  building("treehouse", 128),
  building("urban_house", 124),
  building("urban_inn", 128),
  building("washhouse", 106),
  building("watchtower", 98),
  building("watermill", 106),
  building("windmill", 128),
  // The extra pack's single buildings (an animated one at frame 0).
  building("cave", 154),
  building("dead_tree", 328, "Hollow tree"),
  building("fish_hut", 147),
  building("gnome_hut", 102),
  building("gnome_tower", 124),
  building("goblin_hut", 140),
  building("pirate_tower", 108),
];

export const NPCS: readonly NpcKind[] = [
  npc("pawn", "npc_pawn"),
  npc("pawn_axe", "npc_pawn_axe", "Pawn with an axe"),
  npc("pawn_gold", "npc_pawn_gold", "Pawn with gold"),
  npc("pawn_hammer", "npc_pawn_hammer", "Pawn with a hammer"),
  npc("pawn_knife", "npc_pawn_knife", "Pawn with a knife"),
  npc("pawn_meat", "npc_pawn_meat", "Pawn with meat"),
  npc("pawn_pickaxe", "npc_pawn_pickaxe", "Pawn with a pickaxe"),
  npc("pawn_wood", "npc_pawn_wood", "Pawn with wood"),
  npc("lancer", "npc_lancer"),
  npc("trainee", "npc_trainee"),
  npc("laborer", "npc_laborer"),
  npc("expert", "npc_expert"),
  npc("master", "npc_master"),
  // The professions' and the castes' own sprites, idle.
  npc("warrior", "vanguard"),
  npc("archer", "warden"),
  npc("monk", "cleric"),
  npc("thief", "runt"),
  npc("spear_goblin", "skirmisher"),
  npc("torch_goblin", "slinger"),
  npc("hex_shaman", "shaman"),
  npc("troll", "hobgoblin"),
  // Animals.
  npc("sheep", "npc_sheep"),
  npc("pig", "npc_pig"),
];

export const BRIDGES: readonly BridgeKind[] = [
  {
    id: "stone_bridge",
    label: "Stone bridge",
    category: "bridge",
    sprite: "stone_bridge",
    deck: 1,
  },
  {
    id: "covered_bridge",
    label: "Covered bridge",
    category: "bridge",
    sprite: "covered_bridge",
    deck: 1,
  },
];

/** The whole table, in the palette's order: props, buildings, NPCs, bridges. */
export const KINDS: readonly Kind[] = [...PROPS, ...BUILDINGS, ...NPCS, ...BRIDGES];

const BY_ID = new Map(KINDS.map((kind) => [kind.id, kind]));

export function kindOf(id: string): Kind | null {
  return BY_ID.get(id) ?? null;
}

/** Every sprite a kind draws. */
export function spritesOf(kind: Kind): readonly string[] {
  return kind.category === "prop" ? kind.art : [kind.sprite];
}

const ID = /^[a-z][a-z0-9_]*$/;

/**
 * What is wrong with a kind table: ids that repeat or are not lower case, a prop without art, a
 * facing prop without its six sprites, a building's width or depth out of range, a deck shorter
 * than one, or a
 * sprite missing from `sprites` (the atlas's names) when given. Empty when sound.
 */
export function kindTableProblems(table: readonly Kind[], sprites?: ReadonlySet<string>): string[] {
  const problems: string[] = [];
  const seen = new Set<string>();
  for (const kind of table) {
    if (!ID.test(kind.id)) problems.push(`${kind.id}: not a kind id`);
    if (seen.has(kind.id)) problems.push(`${kind.id}: the id is used twice`);
    seen.add(kind.id);
    if (kind.category === "prop") {
      if (kind.art.length === 0) problems.push(`${kind.id}: no art`);
      if (kind.turn === "facing" && kind.art.length !== 6) {
        problems.push(`${kind.id}: a facing prop needs six sprites`);
      }
    }
    if (kind.category === "building") {
      if (!(Number.isInteger(kind.width) && kind.width >= 1 && kind.width <= 1024)) {
        problems.push(`${kind.id}: a width of ${kind.width}`);
      }
      if (!(Number.isInteger(kind.depth) && kind.depth >= 0 && kind.depth <= 8)) {
        problems.push(`${kind.id}: a depth of ${kind.depth}`);
      }
    }
    if (kind.category === "bridge" && !(Number.isInteger(kind.deck) && kind.deck >= 1)) {
      problems.push(`${kind.id}: a deck of ${kind.deck}`);
    }
    if (sprites) {
      for (const sprite of spritesOf(kind)) {
        if (!sprites.has(sprite)) problems.push(`${kind.id}: no sprite ${sprite} in the atlas`);
      }
    }
  }
  return problems;
}
