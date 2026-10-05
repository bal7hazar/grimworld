# CLI-09e part 1 — the pack's palette for the map editor

Track CV, 2026-10-05. The owner asked for menus to place buildings, bridges and characters, more
props and buildings, and idle units as NPCs. Part 1 adds the art to the atlas
(`tools/art/manifest.toml`) and a self-contained module, `client/app/src/editor/palette/`. No
existing editor file changes: CLI-09b is changing them. Part 2 wires the module in after CLI-09b
merges.

Everything below was measured on the Mac's pack (`/Users/bal7hazar/git/grimworld/assets/`), read
only. Sizes are in px. A strip is a row of square cells (cell = strip height) unless a cell is
given. No image of the pack is in the repository (D-73).

## 1. Inventory

### Counts

| Category | In the pack | In the atlas before | Added now | Left out |
|---|---|---|---|---|
| Props (ground decorations) | 54 images | 17 | 26 | 11: 8 clouds, the wooden fence, the cannon's up and down views |
| Buildings | 82 images (40 coloured, 34 `Others`, 8 extra) | 24 | 25 (2 of them bridges) | 33: the 32 Black, Purple, Red and Yellow buildings, the pirate tower on water |
| Units with an idle animation | 89 idle strips | 8 (castes and Blue professions) | 15 | 66: 48 other-colour units, 17 creatures of the enemy pack, the pig rider |
| Bridge pieces | 0 pieces; 2 whole bridges | 0 | 2 (counted with the buildings) | none |

"Left out" is a choice, recorded in §2. Adding any of them takes one manifest entry and one kind-table line.

### Props

| Source (pack path) | Cell, frames | Atlas name | Status |
|---|---|---|---|
| `Terrain/Resources/Wood/Trees/Tree1.png`, `Tree2.png` | 192 × 256, 8 | `tree1`, `tree2` (frame 0) | before |
| `…/Trees/Tree3.png`, `Tree4.png` | 192 × 192, 8 | `tree3`, `tree4` (frame 0) | before |
| `…/Trees/Stump 1.png` … `Stump 4.png` | 192 × 256, single | `stump1`–`stump4` | before |
| `Terrain/Decorations/Bushes/Bushe1.png` … `Bushe4.png` | 128, 8 | `bush1`–`bush4` (frame 0) | before |
| `Terrain/Decorations/Rocks/Rock1.png` … `Rock4.png` | 64, single | `rock1`–`rock4` | before |
| `Terrain/Resources/Meat/Sheep/Sheep_Idle.png` | 128, 6 | `sheep` (frame 0) | before (the hubs); an NPC now too |
| `Terrain/Resources/Tools/Tool_01.png` … `Tool_04.png` | 64, single | `tool1`–`tool4` | added |
| `Terrain/Resources/Gold/Gold Resource/Gold_Resource.png` | 128, single | `gold` | added |
| `…/Gold Stones/Gold Stone 1.png` … `6.png` | 128, single | `gold_stone1`–`gold_stone6` | added |
| `Terrain/Resources/Meat/Meat Resource/Meat Resource.png` | 64, single | `meat` | added |
| `Terrain/Resources/Wood/Wood Resource/Wood Resource.png` | 64, single | `logs` (`wood` is the interface's table) | added |
| `Terrain/Decorations/Rocks in the Water/Water Rocks_01.png` … `_04.png` | 64, 16 | `water_rock1`–`water_rock4` (frame 0) | added |
| `Terrain/Decorations/Rubber Duck/Rubber duck.png` | 32, 3 | `duck` (frame 0) | added |
| `Enemy Pack/Extra/Skull decorations/Bones_01.png` … `_03.png` | 64, single | `bones1`–`bones3` | added |
| `…/Skull decorations/Skull Spike_01.png`, `_02.png` | 64 × 128, single | `skull_spike1`, `skull_spike2` | added |
| `Enemy Pack/Extra/Cannon/Cannon_Right.png`, `_UpRight.png`, `_DownRight.png` | 128, single | `cannon_right`, `cannon_upright`, `cannon_downright` | added |
| `…/Cannon/Cannon_Up.png`, `_Down.png` (and `Cannon_Ball.png`) | 128, single | — | left out: no hex facing points straight up or down |
| `Terrain/Decorations/Clouds/Clouds_01.png` … `_08.png` | 576 × 256, single | — | left out: sky, not ground |
| `Enemy Pack/Extra/Wooden Fence/Wooden Fence_64x64 tile.png` | 4 × 3 cells of 64 | — | left out: an autotile that joins by neighbours (a later lot, like a road) |
| `…/Gold_Resource_Highlight.png`, `Gold Stone N_Highlight.png` (7) | 128, 6 | — | not counted: a highlight for interaction, not a prop |

### Buildings

The atlas cell is the visible width and height plus a 4 px margin on each side. The proposed
footprint follows the hubs' rule (§2.2) at the default depth 1: the hexes under the width on the
base row, and one row behind.

| Source | Atlas name | Visible width | Hexes (depth 1) | Status |
|---|---|---|---|---|
| `Buildings/Blue Buildings/Castle.png` | `castle` | 312 | 9 | before |
| `…/Barracks.png`, `Archery.png` | `barracks`, `archery` | 184, 183 | 5 | before |
| `…/Monastery.png` | `monastery` | 160 | 5 | before |
| `…/Tower.png` | `tower` | 120 | 3 | before |
| `…/House1.png`, `House2.png`, `House3.png` | `house1`–`house3` | 112, 128, 122 | 3, 5, 3 | before |
| `Buildings/Others/` (16): Barn, Cloister, Cottage, Forge, Fortress, Grain Silo, Hut, Inn, Market Hall, Rural House, Small House, Stable, Straw Hut, Tavern, Watchtower, Windmill | their names in snake case | 98 to 128 | 3 or 5 | before |
| `Buildings/Others/Acueduct.png` | `acueduct` | 124 | 3 | added |
| `…/Arbor.png` | `arbor` | 116 | 3 | added |
| `…/Bourgeois_House.png` | `bourgeois_house` | 128 | 5 | added |
| `…/Church.png` | `church` | 123 | 3 | added |
| `…/Farm.png` | `farm` | 126 | 3 | added |
| `…/Hall_of_the_Gods.png` (128 × 320) | `hall_of_the_gods` | 128 | 5 | added |
| `…/Hotel.png` | `hotel` | 128 | 5 | added |
| `…/Monastery.png` (128 × 320) | `abbey` (`monastery` is the Blue one) | 124 | 3 | added |
| `…/Pigsty.png` | `pigsty` | 114 | 3 | added |
| `…/Postal_Relay.png` | `postal_relay` | 109 | 3 | added |
| `…/Sacrificial_House.png` (128 × 320) | `sacrificial_house` | 116 | 3 | added |
| `…/Treehouse.png` | `treehouse` | 128 | 5 | added |
| `…/Urban_House.png` | `urban_house` | 124 | 3 | added |
| `…/Urban_Inn.png` | `urban_inn` | 128 | 5 | added |
| `…/Washhouse.png` | `washhouse` | 106 | 3 | added |
| `…/Watermill.png` | `watermill` | 106 | 3 | added |
| `…/Stone_Bridge.png`, `Covered_Bridge.png` | `stone_bridge`, `covered_bridge` | 126 | a bridge (§1, Bridges) | added |
| `Enemy Pack/Extra/Gnome Buildings/Gnome Hut.png` (128 × 192) | `gnome_hut` | 102 | 3 | added |
| `…/Gnome Buildings/Gnome Tower.png` (128 × 256) | `gnome_tower` | 124 | 3 | added |
| `Enemy Pack/Extra/Pirate Tower/Pirate Tower_Ground.png` (128 × 192) | `pirate_tower` | 108 | 3 | added |
| `Enemy Pack/Extra/Dead Tree/Dead Tree.png` (384 × 320) | `dead_tree` (a hollow tree with a door) | 328 | 11 | added |
| `Enemy Pack/Extra/Goblin Hut/Goblin Hut.png` | `goblin_hut` (cell 256, frame 0 of 12) | 230 | 7 | added |
| `Enemy Pack/Extra/Fish Hut/Fish Hut.png` | `fish_hut` (cell 192, frame 0 of 8) | 147 | 5 | added |
| `Enemy Pack/Extra/Cave/Cave_Idle.png` | `cave` (cell 192, frame 0 of 8) | 154 | 5 | added |
| `Enemy Pack/Extra/Pirate Tower/Pirate Tower_Water.png` (8 cells of 128 × 192) | — | — | — | left out: stands in water |
| `Buildings/{Black,Purple,Red,Yellow} Buildings/` (4 × 8) | — | — | — | left out: one colour set, Blue (D-178) |

The animated buildings (goblin hut, fish hut, cave) are drawn at frame 0, as the props are.

### Units with an idle animation (NPCs)

| Source | Cell, idle frames | Atlas name | Status |
|---|---|---|---|
| `Units/Blue Units/Warrior/Warrior_Idle.png` | 192, 8 | `vanguard` | before (an NPC from its idle) |
| `Units/Blue Units/Archer/Archer_Idle.png` | 192, 6 | `warden` | before |
| `Units/Blue Units/Monk/Idle.png` | 192, 6 | `cleric` | before |
| `Units/Blue Units/Pawn/Pawn_Idle.png` and `Pawn_Idle Axe`, `Gold`, `Hammer`, `Knife`, `Meat`, `Pickaxe`, `Wood` | 192, 8 each | `npc_pawn`, `npc_pawn_axe` … `npc_pawn_wood` | added (8) |
| `Units/Blue Units/Lancer/Lancer_Idle.png` | 320, 12 | `npc_lancer` | added |
| `Characters/1_Trainee` … `4_Master/*_Idle.png` | 192, 7 each | `npc_trainee`, `npc_laborer`, `npc_expert`, `npc_master` | added (4) |
| `Terrain/Resources/Meat/Sheep/Sheep_Idle.png` | 128, 6 | `npc_sheep` | added |
| `Enemy Pack/Extra/Pig/Pig_Idle.png` | 192, 10 | `npc_pig` | added |
| `Enemy Pack/Thief`, `Spear Goblin` (256, 8), `Torch Goblin`, `Hex Shaman`, `Troll` (384, 12) | 192 unless given; 6, 8, 8, 8, 12 | `runt`, `skirmisher`, `slinger`, `shaman`, `hobgoblin` | before (NPCs from their idle) |
| `Units/{Black,Purple,Red,Yellow} Units/` (Warrior, Archer, Monk, Lancer, 8 Pawn idles: 12 each) | as Blue | — | left out (48): D-178 |
| `Enemy Pack/`: Bear (256, 8), Bomb Fish (192, 8), Bumblebee (192, 8), Giant Bat (192, 6), Gnoll (192, 6), Gnome (192, 8), Harpoon Shark (192, 8), Imp (192, 8), Lizard (192, 7), Minotaur (320, 16), Paddle Shark (192, 8), Panda (256, 10), Skull (192, 8), Slingshot Gnome (192, 10), Snake (192, 8), Spider (192, 8), Turtle (320, 10) | — | — | left out (17): monsters, not townsfolk |
| `Enemy Pack/Extra/Pig Rider Spear Goblin/Pig Rider_Idle.png` | 256, 8 | — | left out: a mount, not an NPC |

Timing: every `.aseprite` read (`Units (aseprite in Blue only)/Pawn`, `Lancer`, `Warrior`, the four
`Characters`) gives 100 ms a frame for every idle frame, so 10 fps. The NPC strips keep the
manifest's 12 fps, the professions' pace, so a Warrior NPC (from `vanguard`) and a Pawn NPC idle
alike.

Measured cells of the added NPCs (from the build's report): `npc_pawn` 68 × 82 and its tools 72 to
98 wide, `npc_lancer` 90 × 158, `npc_trainee` 70 × 81, `npc_laborer` 84 × 73, `npc_expert` 74 × 74,
`npc_master` 78 × 78, `npc_sheep` 54 × 52, `npc_pig` 72 × 59. Visible heights (idle median): Pawn
72–73, Lancer 75, the Characters 64 to 69, Sheep 44, Pig 50; the Trainee's and the Laborer's idle
frames span 7 and 8 px (the build warns, as it does for any idle over 6).

### Bridges

The pack has **no bridge pieces** to join along a deck: `Buildings/Others/` holds two whole bridges,
`Stone_Bridge.png` (visible 126 × 134) and `Covered_Bridge.png` (126 × 161), each 128 × 256. Both
are drawn with the deck running North-South: posts at the near (bottom) and far (top) ends. The
stone bridge's visible height, 134 px, is close to two rows of hexes (2 × 55.4 = 111 px between the
two ends' centres, plus the posts). So each bridge is proposed as **one deck hex between two end
hexes**: the southern end, the deck North-East of it (or North-West, mirrored), the northern end
North-West (North-East) of the deck, so both ends sit in one column on screen. A longer deck needs
art the pack does not have (a middle piece to repeat) or a stretched image; neither is done here.

### The atlas

Built with the pack on the Mac (the build run against the Mac's pack into a scratch folder outside
the repository): **no new page**. The map's pages stay two: `atlas-0` 2048 × 2020 → 2048 × 2032,
`atlas-1` 1944 × 456 → 2048 × 1396; the interface page `atlas-ui-0` is unchanged (2044 × 656). Every
page stays within `atlas_max` = 2048, which `sprites.ts` and `atlas.ts` accept (the client loads
every `world` page and refuses an unknown `group`, so the new sprites are `world` sprites). The game
loads `atlas-1` already; it grows by 1,972,544 px (2048 × 1396 − 1944 × 456), about 7.9 MB as RGBA
in memory. The site's deploy builds the real
atlas after the merge.

## 2. The kind table's choices

The table is `client/app/src/editor/palette/kinds.ts`: 86 kinds, 14 props, 47 buildings, 23 NPCs,
2 bridges. A kind id is what the editor's file and ENG-08's export carry.

### 2.1 Props

A prop kind groups the variants of one thing: `rock` is `rock1`–`rock4`, and the record's
`variant` picks one. `turn` is `flip` (mirror on or off) for all but the cannon, which turns by
`facing`: East is `cannon_right`, North-East and North-West `cannon_upright`, South-East and
South-West `cannon_downright`, the West facings mirrored as every sprite is (`render/facing.ts`).

`blocks`, proposed for ENG-08's kind table:

| Kind | Variants | blocks |
|---|---|---|
| `tree` | 4 | yes |
| `rock` | 4 | yes |
| `gold_stone` | 6 | yes |
| `water_rock` | 4 | yes (it stands in water, already unwalkable) |
| `skull_spike` | 2 | yes |
| `cannon` | by facing | yes |
| `bush` | 4 | no |
| `stump` | 4 | no |
| `bones` | 3 | no |
| `tool` | 4 | no |
| `gold`, `meat`, `logs`, `duck` | 1 | no |

The zone's wall obstacles (CLI-03h) draw bushes and stumps on wall hexes: there the wall is the
terrain's, not the prop's, so a bush does not need to block.

### 2.2 Buildings

A building kind is its sprite, its **visible width** (the pack's opaque columns, as the hubs'
`BUILDINGS` table in `sandbox/fixtures/hubs.ts` measures it: the same numbers for the 17 the hubs
draw) and its **depth**, the rows it covers behind its base row (1 by default, the hubs'
`DEFAULT_DEPTH`; a placement may give 0 to 8). Its footprint is computed exactly as the hubs compute
it (`hubWorld.ts`, `footprint`): every hex whose centre lies within half the width of the anchor's
centre, on the anchor's row and `depth` rows behind. A test checks the two agree for every building,
depth 0 to 2, on even and odd rows. So the town and the outpost redrawn in the editor (CLI-09d, O-6)
cover what the game covers today.

The **anchor** is the base row's hex under the building's centre, where the sprite's base is drawn,
and the **door** by default (the hubs' `at`, which is the door). The author may move the door to any
hex of the footprint's border (`doorChoices`); a hex surrounded by the footprint is refused. The
door's outward side is the first of South-East, South-West, East, West, North-East, North-West whose
hex across lies outside the footprint; the preview marks that hex as the doorstep.

### 2.3 NPCs

An NPC kind is an idle animation; its id is the unit template id ENG-08 carries. Any of the six
facings; the sprite faces right and is mirrored for West, North-West and South-West, as every unit
(`isMirrored`). 23 kinds: the Pawn and its seven tools, the Lancer, the four Characters, the
Warrior, Archer and Monk (from `vanguard`, `warden`, `cleric`), the five goblins (from the castes'
sprites), the sheep and the pig.

### 2.4 Bridges

`stone_bridge` and `covered_bridge`, deck 1, North-South (§1, *Bridges*). The record is the deck
hexes (South to North) and the two ends; the walking rules are ENG-08b's (D-217).

### 2.5 Choices made here, and what reverses them

- Blue only for coloured buildings and units (D-178): reversed by the owner's choice of colours.
- Enemy-pack creatures and the pig rider not offered as NPCs: they are monsters or mounts.
  Reversed by a manifest line and a kind line each.
- NPC idles at 12 fps rather than the pack's 10: reversed by the four lines of `fps`.
- Bridges one deck hex long: reversed by deck art, or by an owner's call to stretch.
- Props' `blocks` as in §2.1, buildings' depth 1: proposals for track game (§4).
- Prop kind ids group variants (`rock` with `variant` 0–3) rather than one kind per image.

## 3. What part 2 must wire, and where

The module's entry is `client/app/src/editor/palette/index.ts`. Nothing imports it yet; a test
(`Palette.test.tsx`) checks that no module outside `editor/` imports it, so the game's bundle never
holds it (the build confirms: no palette string in `dist/`).

| Part 2 step | What to use | Where (CLI-09a2's files; CLI-09b's report will name the exact place) |
|---|---|---|
| The menus in the side panel | `<Palette thumbs onSelect />` | `Editor.tsx`, the palette column (`ed-tools`), the brief's §2.4 *Objects* group |
| Thumbnails | `thumbsFromLibrary(library)` | `canvas.ts` already loads the atlas (`loadAtlas`); pass its library up |
| Place on click | `recordOf(placement)`; refuse on `problem`, and on `overlaps` with a placed record | `session.ts`, the Place tool (`O`), through `history.ts` |
| Preview under the pointer | `previewOf(placement)`, `drawPreview(ctx, camera, viewport, preview)` | `canvas.ts`, after `drawOverlays` on the same 2D canvas |
| Turn and mirror | `facing` (NPC, cannon), `flip` (props), `door` via `doorChoices`, `mirrored` (bridge) | `keys.ts`: the brief's `H` (mirror); a key for the facing |
| Save and load | the four record types | `file.ts`, the editor's own format, next to CLI-09b's objects |
| Draw the placed art | sprite, frame and mirror from the record and the kind | the renderer's structures (`ViewStructure`) for buildings and props, actors for NPCs |

## 4. For track game: kind ids and fields proposed for ENG-08's schema

- **Prop**: `{ kind, hex, variant?, facing? | flip? }`. Kinds and `blocks` as §2.1; `variant`
  written only for a kind of several sprites, `flip` only when true, `facing` only for `cannon`.
- **Building**: `{ kind, footprint, anchor, door }`, the 47 ids of §1 *Buildings*. The footprint is
  written whole (the hubs' rule from `width` and `depth`, §2.2), so the converter needs no width
  table. **Walkability, decided by track game on 2026-10-05**: the footprint is unwalkable but for
  its door; the door hex is walkable and lies on the footprint's border (`doorChoices`), as
  `hubWorld.ts` ships it. ENG-08 states this rule in the format and in the converter.
- **NPC**: `{ template, hex, facing }`, the 23 template ids of §2.3, client-only.
- **Bridge**: `{ kind, deck, ends }`, `stone_bridge` and `covered_bridge`. Track game, 2026-10-05: a
  one-hex deck with its two end hexes is a valid bridge in format v1.

**The kind table's owner** (track game, 2026-10-05): after this merges, ENG-08 takes this section as
the input to its kind table, and from then on the schema owns it. A later change to a kind id, a
prop's `blocks` or a building's footprint goes through ENG-08's schema, and the palette follows.

## 5. Not checked

- The bridges' North-South reading and their one-hex deck, the cannon's directions, and every
  footprint against its art were not seen drawn on the map: part 2's renderer shows them.
- The Palette component is tested by server rendering only (no DOM in the tests); its thumbnails'
  drawing on a canvas is not run in a test.
