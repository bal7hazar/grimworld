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
| `Enemy Pack/Extra/Goblin Hut/Goblin Hut.png` | `goblin_hut` (cell 192 × 256, frame 0 of 16) | 140 | 5 | added |
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

# Part 2 — the palette in the editor

Opus 5.5, 2026-10-05. The palette of part 1 wired into the editor's screen: its four menus place
the pack's buildings, characters, props and bridges on a zone or a town, in the records track game
agreed for ENG-08 (D-215).

## 6. What exists now

- **The menus** sit under the editor's objects in the left panel, headed *The pack*, in the brief's
  order: Buildings, Characters, Props, Bridges (part 1's "NPCs" menu is labelled *Characters*).
  Choosing a kind arms Place with it; the armed kind stays pressed in the palette, and the status
  line reads `Place: <kind>`. Thumbnails come from the atlas the canvas already loaded (PixiJS keeps
  its pages: nothing is fetched twice); without the art, labels alone.
- **Four object kinds** join CLI-09b's table (`editor/pack.ts`, rows in `KINDS`), held by zones and
  towns alike (`map: "both"`): `building` (`type`, `depth`, `door` as the offset `"dx,dy"` from the
  anchor), `npc` (`type`, `facing` 0 to 5), `scenery` (the pack's props: `type`, `variant`,
  `facing`, `mirror`) and `bridge` (`type`, `mirror`; `at` is the southern end). Each row's
  `record` is part 1's `recordOf`: the record ENG-08's export writes (building: kind, footprint,
  anchor, door; NPC: template, hex, facing; prop: kind, hex, variant or flip, or facing; bridge:
  kind, deck, ends). A placement whose record cannot be written (past the plane's bound) is refused
  with its reason.
- **Turn and mirror**: R (new, a same-place letter no game screen binds; the keys test checks it)
  turns the selected characters and cannons a facing, takes a prop's next variant, and a building's
  next door along its footprint's border. H mirrors a pack prop (its `flip`) and a bridge (its
  deck's lean). The inspector edits every field; its door list is the footprint's border hexes.
- **The walkable plane**: a building covers its footprint but its door, a blocking prop its hex
  (`covers`). The walk's world of a town makes them walls; the checks read them (below).
- **Drawing**: in a town, buildings, props and bridges are the renderer's structures (`look`), as
  CLI-09b's; characters, and on a zone all four, are drawn on the editor's overlay at the renderer's
  scale and anchor (`editor/packDraw.ts`), under the markers. The placement's preview (part 1's
  `drawPreview`: footprint, door, doorstep, deck, facing) and the sprite at 60 % follow the pointer.
- **The checks** (`validate.ts`), on zones and towns:
  - E-16 now runs on a zone's footprints too (the pack's buildings): on land, painted, apart.
  - **E-20**: a building's door is a hex of its footprint's border, and walkable.
  - **E-21**: a character stands on a walkable hex.
  - **E-22**: a prop stands on a painted hex inside the outline.
  - **E-23**: the record can be written (a kind of the table, a variant, facing or depth in range).
  "Walkable" is a painted floor hex inside the outline that no object covers: a blocking prop on a
  door or under a character fails E-20 or E-21.
- **The file**: format 2's `objects` list carries them by their rows' fields (`{ kind, x, y, type,
  … }`); a file without them opens as before.

## 7. Choices (reversible)

1. **On both maps.** ENG-08's export is a zone's, and CLI-09d's town files replace `hubs.ts`: the
   pack's objects are offered on both. To reverse: a row's `map`.
2. **CLI-09b's town pieces stay** (`Decor building`, `Prop`, `Figure spot`): they serve the hubs'
   fixtures. The pack's prop is named *Pack prop* in the inspector to keep the two apart; retiring
   the old two is a later lot's.
3. **Overlaps are a check, not a refusal**: a building over another fails E-16, as CLI-09b's
   buildings do, so the author can fix rather than guess why a click did nothing (part 1 proposed
   refusing).
4. **The door is kept as an offset** from the anchor, so a moved building keeps its door; R and the
   inspector offer the border only, and a file's door off it is E-20's.
5. **An off-border door is said once**, by E-20, though the record refuses it too.
6. **A bridge is checked only by E-23** (its hexes in the plane): its walking and its ends' rules
   wait for ENG-08b (D-217).

## 8. What the renderer would need (not edited: `render/**`, `editor/view.ts`, `editor/canvas.ts`)

- **Characters' idle animation**: drawn at frame 0. To play it, the editor's view (`view.ts`) would
  send the characters as actors, and the renderer's actors would take a sprite name and its `idle`
  animation (they are drawn by profession today); or the structures would play an animation, not
  only `still`.
- **A zone's pack art by the renderer** (sorted with the walls' obstacles, under the fog): one line
  in `view.ts`, `structures: layers.objects ? townStructures(doc) : []` (today towns only). Until
  then the overlay draws them over the terrain.
- The zone's preview walk shows no pack object and keeps a blocking prop's hex walkable
  (`walkWorld` sends a zone no structures; making its covers walls would draw rocks there).

## 9. Not checked

- The cannon's six facings and the bridges' North-South lean were seen in one capture each, not
  every facing.
- E-6/E-7 (reach from a zone's entry) do not count a blocking prop or a building as a wall: the
  converter's reach check will (ENG-08).
- No phone or touch (O-3).

## 10. Cut fix: the Goblin Hut

The Goblin Hut's sheet is 3072 x 256 px: 16 frames of 192 x 256 px, not 12 of 256 x 256. The entry cut
cells 256 px wide, so frame 0 took in the left 64 px of frame 1 (the hut is 140 px wide, drawn from x = 26
to 166 in its 192 px cell, and the next hut starts at x = 218): the extra piece of hut on the right. The
entry is now `cell = [192, 256]`. Every other still cut from a strip was measured and is whole in its
cell, but for the rubber duck, whose frames' ripples touch the cell edges (a pack artefact, a few
pixels, left as it is). `clean.still` now refuses a cell whose width does not divide the sheet's width
and warns when frame pixels touch the cell's left or right edge (the duck's warning is expected).

# Part 3 — characters idle, a zone's pack art drawn by the renderer

The owner, on the editor: "the characters are not animated: put them at least in their idle
animation". The project manager: the same in the game's renderer for NPCs, if it is the same code.

## 11. What exists now

- **The renderer's figures** (`render/figures.ts`, `renderer.ts`). A `ViewStructure` may carry an
  `animation` (`kind: "figure"`): a pack character. It loops that animation at the sprite's fps
  (the pack's characters: 6 to 12 frames at 12 fps) on the actors' idle path: the scheduler's timed
  wake-ups, at most `IDLE_MAX_FPS`, nothing while the page is hidden, frame 0 with idle animations
  off (`?idle=0`). A frame is asked for only while an animated figure is on the screen (its sprite's
  box against the camera's rectangle, as the foam's). Its phase comes from its hex, world position
  only, as the foam's: `q + 3r` in axial coordinates. The six neighbours of a hex differ by ±1, ±2
  or ±3 frames, never by a whole loop of 4 frames or more, so two characters side by side never
  breathe in step. A frame of a figure only swaps its sprite's texture: no bake, no rebuild.
- **What the view hides.** A structure (figure, building, prop) on a hex the view hides (an
  instance's hex never in sight, or a chunk not revealed) is not drawn. Beyond sight it is dimmed as
  the walls' obstacles are, and under the view's fog it shows its still, or frame 0 for a figure,
  in grayscale, and asks for no frame. A game hub sends every tile in sight and no `revealed`: no
  change there.
- **A structure's node** is built again when its sprite, animation, mirror or covered hexes change.
  Before, only a changed key or hex rebuilt it, so by the code a prop's variant changed in the
  inspector would keep its old sprite until the set changed. Read from main's `syncStructures`, not
  reproduced in a browser.
- **The game's hubs.** Their figures and present adventurers are actors (`hubWorld.ts`, profession
  sprites), not structures. They already loop their idle, phased by actor id, and that code is
  unchanged. The new path serves the pack's characters, in the editor and its preview walk. The game
  draws no pack character yet.
- **The editor.** A character's kind has a `look` (a figure, `animation: "idle"`, mirrored on the
  West facings). `editorView` sends the map's structures on a zone as on a town
  (`structures: layers.objects ? townStructures(doc) : []`). The overlay draws no pack art any more:
  `packSprites` and the overlay's `under` hook are removed, so nothing is drawn twice. The
  placement's preview stays on the overlay (a character at frame 0). The palette's thumbnails stay
  at frame 0. The editor's renderer now runs idle animations (`?idle=0` stops them). Its overlay is
  redrawn after a renderer frame only when the camera or the size moved (`rendererDrew`): an idle
  frame or a deferred bake leaves it as it is, and a new scene still redraws it.
- **The zone's preview walk** (`walkWorld.ts`). On a zone as on a town, a building's footprint (but
  its door) and a blocking prop's hex are walls, as the validation counts them (review t-0134 note
  3). The pack's objects are drawn as structures, and the renderer draws no rock under them. A bridge
  is drawn only (its walking waits for ENG-08b, D-217). With fog, an object on a chunk not revealed
  yet is not drawn.
- **Review t-0140 of #373.** The camera's notice is `editor/notice.ts` (`Notice`), tested for its
  leading notice, its trailing notice and its timer cleared on destroy. `renderer.bakes.test.ts`
  proves that every texture a deferred bake replaces is destroyed, frame by frame. CLI-09g's report
  has the three corrections.
- §1's Goblin Hut row now gives cell 192 × 256, 16 frames, 140 px, 5 hexes (review t-0141 of #372).

## 12. Choices (reversible)

1. **Characters as structures, not actors.** An actor carries a facing wedge, a mark, steps and
   arcs, and its sprite is named by profession. A pack character is placed authoring data that
   never moves, as a building is. Reverse: actors that take a sprite name, if characters ever walk.
2. **The phase `q + 3r`**, not the foam's diagonal: on a diagonal, neighbours would share a frame.
3. **Grey and still beyond sight under fog**, as the explored water is: no grey texture per frame.
4. **The editor's overlay follows the camera, not every frame.** Its drawing is the same; it is
   only not repeated when nothing it shows has moved.
5. `editor.html` in `main.tsx:6`, `Editor.tsx:63` and brief O-1: left as they are. #371 is not merged
   (open at the time of this lot).

## 13. Measures

Headless Chromium 153 on the VPS (software GL), the site's built atlas (read only), one browser run
at a time. Other projects shared the machine: `/proc/loadavg` (1 min) ran 3.0 to 14.9 over the runs.

**Frame budget against main** (CLI-03n and CLI-03o's method). `verify-fog.mjs` (atlas look) and
`verify-ground.mjs` walks, main/branch pairs, `main` at `2f2f964` (its own worktree), the frame time
being the JavaScript of each display frame that drew. A game zone has no figure: what the branch
adds there is a check per frame and per view.

Series 1, branch at `e3d8c07`, three pairs per size:

| Walk, size | median, main → branch (ms), per pair | median of the pairs' ratios | p95 ratio (pairs) | branch p95 max |
|---|---|---|---|---|
| fog 1440 × 900 | 1.513 → 1.200, 1.130 → 0.970, 0.955 → 1.105 | ×0.86 | ×0.96 (0.64, 0.96, 1.30) | 4.76 ms |
| fog 375 × 812 | 0.905 → 0.790, 0.810 → 0.800, 0.805 → 0.865 | ×0.99 | ×0.81 (0.58, 1.01, 0.81) | 3.19 ms |
| ground 1440 × 900 | 0.900 → 0.695, 0.685 → 0.732, 0.720 → 0.785 | ×1.07 | ×0.92 (0.41, 0.92, 1.27) | 2.70 ms |
| ground 375 × 812 | 0.735 → 0.675, 0.680 → 0.680, 0.678 → 0.702 | ×1.00 | **×1.28** (0.77, 1.28, 1.30) | 2.77 ms |

The ground 375 × 812 p95 ratio was over +25 %. Main's own p95 spread ×1.7 between its three runs
(1.88 to 3.20 ms), so the frame was guarded rather than the figure trusted: with no figure, the
frame's figure step is skipped (`d047591`). Series 2, branch at `d047591`, ground walks, three more pairs:

| Walk, size | median, main → branch (ms), per pair | median ratio | p95 ratio (pairs) | branch p95 max |
|---|---|---|---|---|
| ground 1440 × 900 | 0.725 → 0.718, 0.710 → 0.735, 0.692 → 0.722 | ×1.04 | ×1.14 (1.20, 1.14, 1.00) | 2.94 ms |
| ground 375 × 812 | 0.695 → 0.717, 0.710 → 0.690, 0.685 → 0.728 | ×1.03 | ×1.03 (1.24, 0.60, 1.03) | 2.44 ms |

Budget (median at most +10 %, p95 at most +25 %, never past 16.7 ms at 1440): met by the medians in
both series, by the p95 in series 2. The fog walks were not run again at `d047591`. Noise: main's
medians spread by up to ×1.58 between its runs (fog 1440: 0.955 to 1.513 ms).

**The editor, 50 characters on the screen** (`verify-editor.mjs`, 1440 × 900, `?water=still`, 51
pack characters looping on a 24 × 16 zone; the renderer's `advance` and `draw` timed per frame,
JavaScript only), two runs:

| | run 1 (load 4.2–5.0) | run 2 (load 6.8–7.8) |
|---|---|---|
| standing still: frames a second | 12.0 | 12.0 |
| standing still: script a frame, mean (median / p95) | 0.87 ms (0.60 / 1.80) | 0.82 ms (0.70 / 1.60) |
| panning, 3 px a frame: renderer median / p95 | 1.00 / 6.00 ms (18 frames) | 0.60 / 1.10 ms (71 frames) |
| the same pan, objects layer off | 0.50 / 2.70 ms | 0.50 / 1.00 ms |
| objects off, standing still: frames | 0 | 0 |

Standing still, the idle cost is the characters' 12 frames a second (the sprites' fps, under the cap
of 15), under 1 ms of script each. The overlay is not redrawn for them. Run 1's pan drew 18 frames in
3 s (the software GL at that load), too few for a p95. The GPU's work is not in these figures.

## 14. Checks

| Check | Result |
|---|---|
| `pnpm --filter @grimworld/app test` | 66 files passed, 1 skipped; 723 tests passed, 1 skipped |
| `pnpm --filter @grimworld/app lint`, `typecheck`, `prettier --check client indexer` | pass (pre-push) |
| `verify-editor.mjs` (extended) | ALL CHECKS PASSED, 154 ok. Two captures 100 ms apart: 360 device px differ, all in [950, 981] × [314, 355], inside the character's sprite box [946, 984] × [311, 358] |
| `verify-hubs.mjs` | ALL CHECKS PASSED, 130 ok |
| `verify-ground.mjs` | ALL CHECKS PASSED, 42 ok (each of the six branch runs) |
| `verify-fog.mjs` | ALL CHECKS PASSED, 48 ok (both looks); 24 ok in each atlas-only pair run |
| `verify-water.mjs` | ALL CHECKS PASSED, 103 ok |
| `verify-keys.mjs` | ALL CHECKS PASSED, 92 ok |
| The game's bundle | `vite build`: the editor-only strings ("The map editor needs a desktop window", "Fit chunks", "grimmap") are in `editor-*.js` only; `index.html` loads `main-*.js` and its imports, which hold none of them and do not import the editor's chunk |

New unit tests: `render/renderer.figures.test.ts` (the frame at the sprite's fps from its phase;
neighbours never in step for 6 to 12 frames; frames at most at `IDLE_MAX_FPS`, none with idle off,
hidden or off the screen; hidden hexes, grey beyond sight under fog; a structure rebuilt when its look
changes), `editor/notice.test.ts`, the deferred bakes' retired textures in
`render/renderer.bakes.test.ts`, and in `editor/pack.test.ts` the editor's view of a zone and a town
(its structures and characters) and the zone's walk walls.

## 15. Not checked

- No phone, no GPU: software GL only.
- The fog walks' pairs were not run again after `d047591` (a guard that only removes work).
- A figure under fog beyond sight was checked in unit tests only. No browser capture of the preview
  walk's fog over the pack's objects.
- Captures with the art are in the thread's library folder only (D-73).

# CLI-09f — bridges in the editor, one level

Opus 5.5, 2026-10-07. D-227 (the owner): a bridge has one level, its deck walkable ground over
water, nobody passes under it. ADR-0008 (#383) is the reference; §7 choice 6 above (a bridge
checked only by E-23) is replaced by what follows.

## 16. What exists now

- **A deck of 1 to 13 hexes.** A bridge object keeps its deck's length (`deck`, inspector *Deck
  (hexes)*); 13 is the longest that fits one chunk with its two ends (format 1: `export: bridge
  across chunks`). Its hexes follow its run from the southern end, as CLI-09e drew them: *North*
  (the deck leaning North-East then North-West in turn, one column on the screen, the art's
  direction) or *West* (along the row, a straight hex line). Each hex touches the one before.
- **Placed across the water.** A bridge placed from the menu on a land hex spans the water ahead
  along its run: its deck takes the water hexes up to the next land hex, which becomes its far end
  (`placedOn`, `spanned` in `pack.ts`; the preview under the pointer shows the same). On water, or
  with land ahead, or with no land within 13 hexes, it keeps the kind's one-hex deck, and the
  inspector or the checks say the rest.
- **Drawn with the pack's art, repeated.** The pack has two whole bridges and no deck piece
  (CLI-09e §1). The sprite spans one deck hex and its two ends; a longer deck **repeats** it every
  second hex from the southern end, the last copy ending on the far end (overlapping the one before
  when the length is even): a deck of 3 draws two copies, 4 draws three. Repeating keeps the art's
  pixels; stretching would scale them unevenly. Each copy is one structure of the view
  (`drawnAt`, keys `bridge:<id>` then `bridge:<id>:<n>`); no renderer change.
- **Walkable.** The preview walk's world makes every deck hex inside the outline floor, its ground
  still water under the sprite (ADR-0008 rule 1). The reach checks (E-6, E-7, and a town's E-15)
  walk decks as floor. A river crossed by a bridge alone passes E-7; without its bridge it fails.
- **The checks** (`validate.ts`, zones and towns; the converter's codes from ADR-0008, which ENG-09
  adds to `checks.json`; each with a passing fixture, `bridge-zone`, and failing ones in
  `bridges.test.ts`):

  | Check | Code | Rule | Failing fixtures |
  |---|---|---|---|
  | R-37 | `bridge: tile taken` | nothing on an end or deck hex: entry, gate, spawn point, quota place, feature, character, prop, a building's footprint, another bridge | a chest and a character on the deck; a spawn point, a prop, the entry and a house's footprint on an end |
  | E-24 | `export: deck outside the zone` | every deck hex painted, inside the outline | a deck hex outside the outline; one unpainted |
  | E-25 | `export: deck blocked` | no deck hex blocked (a footprint but its door, a blocking prop); every deck hex over water | a water rock and a barracks on the deck; a deck hex painted land |
  | R-34 | `bridge: end not floor` | each end walkable land: a floor hex inside the outline, not water, not blocked | an end painted wall; an end in the water; a rock on an end |

- **The export** writes a bridge as before (`{ kind, deck, ends }`), its deck hexes as painted
  (water): the converter makes them walkable (ADR-0008 Open question 1). An export's bridge of any
  length opens again (`fromExport`).
- **Save and load.** The editor's file keeps `deck`; a file without it (CLI-09e's) opens with a
  one-hex deck, the same hexes as before.

## 17. Parity with the converter

`fixtures/bridge-zone.grimmap.json` (one chunk, two ponds, a stone bridge North over 3 deck hexes, a
covered bridge West over 2) exports to `fixtures/bridge-zone.export.json`. Track game's converter,
run on it from this branch:

    python3 spikes/SPK-16-authored-zone/map-format/convert.py \
        client/app/src/editor/fixtures/bridge-zone.export.json \
        --manifest spikes/SPK-16-authored-zone/samples/manifest.json \
        --out client/app/src/editor/fixtures/bridge-zone.records.json
    5 records -> bridge-zone.records.json

It accepts the export: LOCATION, the chunk set, the chunk, and two `BRIDGE` records (deck bits 3 and
2). The editor's port writes the same records, felt for felt (`bridges.test.ts`), and the fixture
validates with no error with the converter's checks included.

## 18. Choices (reversible)

1. **Repeat, not stretch**, as above. Reversed by deck art, or by the owner's eye.
2. **Span on placement.** Reversed by a plain one-hex placement and the inspector alone.
3. **E-24 and E-25 are the editor's ids** for the converter's two deck refusals, which
   `checks.json` does not hold yet: they follow ENG-09's ids when it adds them.
4. **R-37 also flags two bridges sharing a hex** (R-38, on touching decks, is dropped; sharing is
   not touching). Touching bridges are left to the eye.

## 19. Not checked, and what remains

- **The converter on `main` does not apply ADR-0008 rule 1 yet** (ENG-09's): it neither writes a
  deck walkable nor refuses a deck outside the zone or blocked. So a zone whose only crossing is a
  bridge passes the editor's checks but is refused by the converter, and by the editor's export
  checks that run its port, as `pipeline: unreachable tile` (a test holds it). The port follows
  `convert.py` when ENG-09 changes it.
- The *North* run zig-zags (a column on the screen): it is not an axial hex line. The *West* run is.
  The pack's art runs North-South, so a *West* bridge shows the vertical sprite side by side.
- No phone, no GPU: software GL only. Captures with the art stay in the thread's library (D-73).

## 20. CLI-09h: a building's footprint, painted hex by hex

The project manager's decision (2026-10-07): the author may paint a pack building's footprint, from
the kind's default. Before, the inspector offered only "As the file gives it" and "Drawn from its
kind".

- **The tool.** `F` (or the Footprint button) arms it with one pack building selected; with none it
  says so and arms nothing. A press on a hex of the footprint removes hexes for the whole drag; a
  press anywhere else adds them (right click always removes). Each stroke is one undo step.
  `F` is not a tool letter in the keys table (`F` is the game's cycle key): it is its own command.
- **The data.** The first stroke turns the building's `footprint` (offsets from the anchor, as a
  file's export gives it) from "drawn from its kind" to the painted hexes, in reading order, so the
  same hexes are the same file. "Drawn from its kind" in the inspector throws the painting away.
  The file and the export write it as before (`footprint` offsets, ENG-08's `footprint` record).
- **The door.** Its hex cannot be removed ("move the door first"), and a hex that would leave the
  door off the border is refused. The checks are the existing ones: E-16 (one piece, painted, in
  the chunk set, apart from the others) and E-20 (the door on the border, walkable).
- **Bridges, deck along one line** (the review of CLI-09f): `bridges.test.ts` walks the line in all
  six directions from even and odd rows and from negative coordinates, and checks every run
  (North, West, each mirrored) at every deck length from 1 to 5: one chain of neighbours on the
  run's own sides, the sprite's copies on the line two hexes apart, the span to the far bank.
- **Dimmed objects.** `editorView` sent `sight` as the window's painted tiles, so a pack object on
  an unpainted hex or beyond the window was drawn dimmed. Every placed object's hex is now in
  `sight` (the objects layer on); `render/**` is unchanged.

Not checked: a footprint of hundreds of hexes (no measure; a stroke records one change a hex), and a
footprint painted on a zone's chunk border beyond the outline (E-16 names it; no capture).

`verify-editor.mjs` (pack phase, both looks, on the VPS, headless): `F`, a click and a drag paint,
each one undo step, the door refused, save, reload, the footprint back. Its idle-loop frame-rate
checks are load-bound (8.1 and 9.7 frames/s at a load average of 11 to 19 against a floor of 10).
