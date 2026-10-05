/**
 * The editor's kind table (CLI-09e): every prop, building, NPC and bridge the author can place, and
 * the atlas sprite that draws it (`tools/art/manifest.toml`). Presentation and authoring data, no
 * rule: whether a prop blocks and which hexes a building covers are proposed here for ENG-08's
 * schema (track game decides, under D-215), and the converter alone writes the walkable plane.
 *
 * Hex sides are numbered as `sideOf` walks them (`../model.ts`): 0 South-East, 1 South-West,
 * 2 West, 3 North-West, 4 North-East, 5 East. A shape is a list of walks from the anchor, one walk
 * a list of sides, so it holds on odd and even rows alike.
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

const { west, northWest, northEast, east } = SIDE;

/** A walk from the anchor: the sides crossed, in order. `[]` is the anchor itself. */
export type Walk = readonly number[];

/**
 * Building footprints, by the art's visible width (the atlas cell less its 4 px margins): up to
 * 104 px one hex; up to 130 px the anchor and the two hexes behind it (the art's two hex widths);
 * up to 200 px a front row of three and two behind; past it a front row of three, four behind and
 * three behind those. The anchor is the front row's middle hex, where the sprite's base is drawn.
 */
export const FOOTPRINTS = {
  one: [[]],
  three: [[], [northWest], [northEast]],
  five: [[], [west], [east], [northWest], [northEast]],
  ten: [
    [],
    [west],
    [east],
    [northWest, west],
    [northWest],
    [northEast],
    [northEast, east],
    [northWest, northWest],
    [northWest, northEast],
    [northEast, northEast],
  ],
} as const satisfies Record<string, readonly Walk[]>;

export type FootprintName = keyof typeof FOOTPRINTS;

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

/** A building: its sprite, its footprint and its door, a hex of the footprint's border. */
export interface BuildingKind extends KindBase {
  readonly category: "building";
  readonly sprite: string;
  readonly footprint: FootprintName;
  /** The door by default: a walk from the anchor to a hex of the footprint's border. */
  readonly door: Walk;
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
 * A bridge (D-217): a deck of `deck` hexes between two end hexes, North-South as the pack draws
 * both. Its sprite is a whole image: no deck piece to repeat, so `deck` is fixed by the art.
 */
export interface BridgeKind extends KindBase {
  readonly category: "bridge";
  readonly sprite: string;
  readonly deck: number;
}

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

const building = (
  id: string,
  footprint: FootprintName,
  sprite = id,
  name = label(id),
): BuildingKind => ({
  id,
  label: name,
  category: "building",
  sprite,
  footprint,
  // The front row's middle hex: the door faces the viewer.
  door: [],
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
  building("castle", "ten"),
  building("barracks", "five"),
  building("archery", "five"),
  building("monastery", "five"),
  building("tower", "three"),
  building("house1", "three", "house1", "House 1"),
  building("house2", "three", "house2", "House 2"),
  building("house3", "three", "house3", "House 3"),
  // `Buildings/Others/`.
  building("abbey", "three"),
  building("acueduct", "three"),
  building("arbor", "three"),
  building("barn", "three"),
  building("bourgeois_house", "three"),
  building("church", "three"),
  building("cloister", "three"),
  building("cottage", "three"),
  building("farm", "three"),
  building("forge", "three"),
  building("fortress", "three"),
  building("grain_silo", "one"),
  building("hall_of_the_gods", "three"),
  building("hotel", "three"),
  building("hut", "one"),
  building("inn", "three"),
  building("market_hall", "three"),
  building("pigsty", "three"),
  building("postal_relay", "three"),
  building("rural_house", "three"),
  building("sacrificial_house", "three"),
  building("small_house", "one"),
  building("stable", "three"),
  building("straw_hut", "one"),
  building("tavern", "three"),
  building("treehouse", "three"),
  building("urban_house", "three"),
  building("urban_inn", "three"),
  building("washhouse", "three"),
  building("watchtower", "one"),
  building("watermill", "three"),
  building("windmill", "three"),
  // The extra pack's single buildings.
  building("cave", "five"),
  building("dead_tree", "ten", "dead_tree", "Hollow tree"),
  building("fish_hut", "five"),
  building("gnome_hut", "one"),
  building("gnome_tower", "three"),
  building("goblin_hut", "ten"),
  building("pirate_tower", "three"),
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
 * facing prop without its six sprites, a door off its footprint, a deck shorter than one, or a
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
      const walks = FOOTPRINTS[kind.footprint] as readonly Walk[];
      if (!walks.some((walk) => sameWalk(walk, kind.door))) {
        problems.push(`${kind.id}: the door is not a hex of its footprint`);
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

function sameWalk(a: Walk, b: Walk): boolean {
  return a.length === b.length && a.every((side, i) => side === b[i]);
}
