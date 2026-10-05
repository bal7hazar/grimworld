# CLI-09 — The map editor (part 1: screens and controls)

**Status: draft, part 1.** Written by a thread of track CV on 2026-10-05 for the orchestrator of track
CV. Its sections on what the editor shows, how it is used, what it holds and what it checks can be
briefed into lots now. **The export waits for track game's format brief** (a design lot after ENG-05),
and so does every line marked *per game's format*. Nothing here decides a game rule: the editor
reproduces checks, it does not invent them (mandate `docs/briefs/ORCH-client-visual.md` §6).

## Agent

To be set per lot by the orchestrator. Proposed: `impl-opus` for CLI-09a (a new page, a new input
model and the renderer reused in a new way), and `impl-sonnet` for the lots after it. No pin, gas
table or budget is involved, so every lot can run on the Mac (`--machine mac`, repo
`/Users/bal7hazar/git/grimworld`). Browser checks need a real Chrome through Playwright, as CLI-03c
did.

## Context

- **D-214** (owner, 2026-10-05; its decision file is not on `main` yet). Zones get **authored maps**
  made with a map editor and exported in a format the chain accepts. Towns are made with the same
  editor and stay client-only data (D-03). Dungeons stay generated. This reverses ADR-0006 §2
  ("Everything is generated, at reveal", D-106) **for zones only**. ADR-0006's open CM-7 ("Format of
  authored chunks and outline masks, and the tool to draw them", l.355) is answered for the tool by this
  brief and for the format by track game.
- **D-202** (`docs/decisions/2026-10-02-hubs-as-zones.md`). A hub is lived like an exploration zone:
  the same hex map, camera, pathfinding and rendering, with buildings as its places. The editor
  therefore makes towns and zones with one canvas.
- **The client today.** Pointy-top hexes, odd-r offset, global `(x, y)` with **x growing West**
  (to the left on screen) and **y growing North** (`render/view.ts:6-8`, `input/coords.ts:6-46`).
  Chunks are 15 × 15 (`sandbox/world.ts:4`). Chunk and tile indices are `15 row + column`
  (`fixtures/region.ts:198-203`, `LocationTrait::position` in `contracts/logic/src/models/location.cairo:84-89`).
  `Terrain` holds `kinds` (`floor` / `wall` / `unrevealed`) and an optional `ground`
  (`grass` / `water` / `earth`, presentation only) per tile (`sandbox/world.ts:7-18`).
  The `Renderer` bakes ground per chunk and draws structures and obstacles z-sorted
  (`render/renderer.ts`). Its camera has `pan`, `zoomAt`, `zoomTo` and `recentre` (`renderer.ts:469-494`).
  Gestures are tap, press, pan and zoom (`input/gestures.ts:8-12`). Keys follow CLI-03k's `BINDINGS`
  (`input/keys.ts:86-206`).
- **Hubs today** are code fixtures (`fixtures/hubs.ts`): places with a service, a door hex, a
  footprint and depth, plus decor, props, figures and earth path tiles. `hubWorld` turns them into a
  `SandboxWorld` (`fixtures/hubWorld.ts:120-170`).
- **Zones today** are a fixture (`fixtures/zone.ts`, a meadow of 3 × 2 chunks) cut by the seed's
  `OUTLINE` rows (`fixtures/region.ts:54-59`, `insideOutline` in `zone.ts:23-30`), with gates as
  `GateRecord` anchors (`region.ts:40-51`).
- **There is one page today**: `client/app/index.html` → `main.tsx` → `App` → `Sandbox`, with screens
  chosen by query string (`sandbox/params.ts:98-116`). There is no router and no second Vite entry.
- **The art** is loaded from `/art/` (`render/atlas.ts:8`): the built atlas pages and `sprites.json`
  that `tools/art/build.py` writes to the git-ignored `out/`. The dev server serves them through
  `devArt` (`vite.config.ts:13-40`) and the public site serves them beside the build. Without them the
  client draws flat shapes.

## 1. Goal and scope

After CLI-09 an author opens a page of the client on a desktop, draws a zone or a town on the hex
grid the game uses, checks it against the rules the chain applies, walks it with the game's own
engine, and saves it as a file. Once game's format exists, they also export what a zone's registration
needs.

**In:**

- A page of the client: the same Vite app and the same modules, its own entry, served on the site like
  the rest (Open question O-1).
- **Desktop first and desktop only**: mouse and keyboard. **Touch: never in CLI-09.** Below 700 CSS px
  wide (design/11's desktop threshold, l.173) the page shows one line: "The map editor needs a desktop
  window." Reversible by a later lot if the owner asks (O-3).
- Two kinds of map:
  - **Zone maps**: a location of kind `ZONE` (`location.cairo:14`). They are exported for
    registration, *per game's format*.
  - **Town maps**: hubs of kind `TOWN` or `OUTPOST`. They are client data only (D-03), and their
    places are buildings (D-202).
- Painting terrain per hex, placing features and objects, placing quota places, the entry and gates,
  drawing the zone's outline.
- Validation: the Registry's checks, as far as they apply to a map, and the editor's own (§5).
- A preview walk with the zone engine as the game runs it.
- Saving and loading local files. Exporting a zone for registration (§6, §10).

**Out:**

- **Dungeons**, Nests and Rift floors: they stay generated (D-214). **Set pieces** (authored chunks
  that a quota lays into a generated dungeon, ADR-0006 l.206-211) are not in CLI-09. The same canvas
  could draw them later (O-8).
- **Any on-chain write.** No key, no account, no wallet, no RPC call, no Registry read. Registration
  is the administrator's act through the content pipeline (OPS-01). The editor hands over a file.
- **Any server storage.** Nothing is uploaded, and nothing is saved on the site.
- Spawn tables, packs, castes, quests and shops as content. A zone's level band, spawn table and rank
  are typed as numbers in the map's properties. Their records are other content.
- Region-wide editing: one map at a time. A gate names its destination by id (§4).
- A new game rule. Movement and reachability in the preview walk come from what the game uses today
  (`findPath`, a placeholder until CLI-02, `sandbox/placeholders.ts:171-223`).

## 2. Screens

All layouts are drawn at **1440 × 900** CSS px. One character is about 14 px wide and one line about
36 px high. The chrome is the plain chrome of CLI-03i (`data-chrome="plain"`, `system-ui` body text),
unless O-4 decides otherwise. Text never sits in art. Panels have fixed widths, and the canvas takes
the rest.

### 2.1 Map list (the editor's home)

This is what opens at the editor's address. It lists the maps the author has opened in this browser
(the drafts, §6) and offers to create a map or open a file.

```
+----------------------------------------------------------------------------------------------------+
| Grim World — Map editor                                                       [ Open file… ]  [?]  |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|   [ + New map ]                                                                                    |
|                                                                                                    |
|   Drafts in this browser                                                                           |
|   +------------------------------------------------------------------------------------------+     |
|   | Kind  | Name               | Size (chunks) | Location id | Edited            | Problems |     |
|   |-------|--------------------|---------------|-------------|-------------------|----------|     |
|   | Zone  | Ashen Meadow       | 3 × 2         | 2           | 2026-10-05 14:02  |  0       |     |
|   | Town  | Town A             | 1 × 1         | 1           | 2026-10-05 11:40  |  2       |     |
|   +------------------------------------------------------------------------------------------+     |
|   Row: Open · Duplicate · Download · Forget (asks first)                                           |
|                                                                                                    |
|   Drafts live in this browser only. Download a map to keep it.                                     |
+----------------------------------------------------------------------------------------------------+
```

### 2.2 New map dialog

```
            +------------------------------------------------------+
            | New map                                              |
            |                                                      |
            |  Kind      (•) Zone   ( ) Town   ( ) Outpost         |
            |  Name      [ Ashen Meadow                ]  ≤ 15 ch  |
            |  Location  [ 2   ]  (the LOCATION id it will be)     |
            |  Size      width [ 3 ] × height [ 2 ]  chunks        |
            |            = 45 × 30 tiles                           |
            |  Biome     [ Meadow ▾ ]   (zone only)                |
            |  Start as  (•) All wall  ( ) All floor               |
            |                                                      |
            |                         [ Cancel ]   [ Create ]      |
            +------------------------------------------------------+
```

- **Size** is in whole chunks. For a zone it is 1 to 15 on each side (`LocationAssert::assert_valid`,
  `location.cairo:110-111`, 4 bits each). For a town or an outpost it is 1 to 4 on each side: an editor
  bound, since a hub has no size on chain (`LocationRecord.width` 0 for a hub,
  `fixtures/region.ts:26-38`). The size can be changed later in the map's properties (§2.4). Shrinking
  asks first and names what would be cut.
- **Name** is at most 15 characters, the bound of a short string in `REGION` (`models/index.cairo:22-33`).
  It is used for the file name and the list. Whether a location carries a name on chain is *per game's
  format*.
- **Location id** is a number. The editor cannot know the chain's `last_id` (§5, R-4).
- **Biome**: Meadow, Forest, Cave or Ruin (`location.cairo:22-27`). It sets the default ground and the
  walkable-share hint of design/18 (l.17-26) shown in the inspector.

### 2.3 Main editor

```
+----------------------------------------------------------------------------------------------------+
| ◂ Maps | Ashen Meadow · Zone · 3×2 chunks · loc 2 | Saved 14:02 (draft) | ⟲ ⟳ | Validate ● 0 | Export… |
+----------+---------------------------------------------------------------------------+-------------+
| TOOLS    |                                                                           | INSPECTOR   |
| [B] Paint|                                                                           |             |
| [N] Erase|                                                                           | Hex (14, 9) |
| [G] Fill |              . . . . . . # # # . . . . .|. . . . .                        | chunk 0 (0,0)
| [I] Pick |             . . . . . # # # # . . . . . |. . . . .                        | tile 149    |
| [U] Selct|              . . . . . . # # . . . . . .|. . . . .                        |             |
| [O] Place|             . . . E . . . . . . . . . . |. . . G1.                        | Terrain     |
| [T] Outln|              . . . . . . . ~ ~ ~ . . . .|. . . . .                        |  ▸ Floor    |
|          |             . . . . . . . ~ ~ ~ ~ . . . |. . . . .                        | Ground      |
| PALETTE  |              . . . . . . . . ~ ~ . . . .|. . . . .                        |  ▸ Grass    |
| Terrain  |       -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -    (chunk seam)       | Obstacle    |
|  ■ Floor |             . . . . . . . . . . . . . . |. . . . .                        |  ▸ auto     |
|  ■ Wall  |                                                                           |             |
| Ground   |                                                                           | Objects     |
|  ■ Grass |                                                                           |  none       |
|  ■ Earth |                                                                           |             |
|  ■ Water |                                                                           | Outline     |
| Objects  |                                                                           |  inside     |
|  ◆ Entry |                                                                           |             |
|  ◆ Gate  |                                                                           |             |
|  ◆ Quota |                                                                           |             |
|  ◆ Featr |                                                                           |             |
|          |                                                                           |             |
| Brush 1  +---------------------------------------------------------------------------+             |
| [ ] [ ]  | Layers: ☑ Ground ☑ Obstacles ☑ Objects ☑ Outline ☐ Chunk seams ☑ Grid   |             |
+----------+---------------------------------------------------------------------------+-------------+
|  x 14  y 9  · chunk (0,0) tile 149 · zoom 13 across · Paint: Floor · brush 1           [P] Walk ▸  |
+----------------------------------------------------------------------------------------------------+
  Left column 200 px · canvas ≈ 960 × 780 px · right column 280 px · top bar and status bar 36 px each
```

- **Top bar**: back to the map list; the map's kind, name, size and location id; the save state
  ("Saved 14:02 (draft)" or "Unsaved changes"); undo and redo; the validation light (green ● 0,
  amber ● warnings, red ● errors, with the count), which opens the validation panel (§2.6); Export…
  (§2.7).
- **Canvas**: the game's `Renderer` on a world built from the map (§4). Everything is revealed (no
  fog in the editor). The void around the map is drawn as the game draws it: `void: "water"`, as in
  `zoneWorld` and `hubWorld`. Over the art the editor draws overlays as plain shapes, never as art:
  - the hex grid (land only, as `ground.ts` does, or everywhere when the grid layer is on);
  - **chunk seams** as dashed lines every 15 tiles, with the chunk index in each chunk's corner;
  - the **outline** as a thick line on the zone's border, with the tiles outside the outline shaded;
  - **objects** as hex markers with a one- or two-letter label: `E` the entry, `G1…` gates, `Q` quota
    places by kind, `F` features by kind;
  - in a town, each **place's footprint** shaded and its **door** hex marked;
  - the hovered hex, the selection, and the brush's footprint under the pointer.

  Colour is never the only carrier of meaning (design/11 l.175-182): every marker has a letter.
- **Tools column**: one tool is active at a time (§3).
- **Palette**: three groups, terrain, ground and objects, each a column of swatches with a name.
  Choosing a terrain or ground swatch arms Paint. Choosing an object arms Place. Swatches of ground and
  obstacles are drawn from the built atlas when it is loaded and as flat colours otherwise (§7). In a
  town the object group lists the town's pieces instead: places by service, decor buildings, props,
  figure spots and the arrival hex (§4.3).
- **Layers bar** under the canvas: ground, obstacles, objects, outline, chunk seams and grid, each a
  checkbox with a key (§3).
- **Status bar**: the hovered hex in global `(x, y)`, its chunk `(cx, cy)` and tile index, the zoom in
  tiles across, the armed tool and brush size, and the Walk button.

### 2.4 Inspector (right column)

It shows what is under the selection: one hex, one object, or a group.

- **One hex**: its global `(x, y)`; its chunk index `15 cy + cx` and tile index `15 row + column`;
  terrain (floor or wall); ground (grass, earth or water); obstacle look (`auto`, or a pinned variant
  of rock, bush, stump or tree, §4.1); whether it is inside the outline; the objects on it. Each field is
  editable in place.
- **One object**: its kind and its fields (§4.2). A gate shows its destination location id, its gate
  kind (`HUB`, `LINK`, `FLOOR`, `RIFT`, `models/gate.cairo:9-14`), the rank required, the quest
  required (a quiver id, 0 for none) and the entry chunk and tile in the destination. A place in a town
  shows its service, its building, its door hex and its depth.
- **A group**: the count by kind, and "Delete", "Set terrain to …" and "Set ground to …".
- **Nothing selected**: the map's properties. These are the kind, the name, the location id, the size
  in chunks, the biome, the level band (min and max), the rank required, the spawn table id and the
  quota list (§4.2). For a zone the panel also shows the walkable share of the outline's floor against
  design/18's range for the biome (a hint, never an error).

### 2.5 Outline mode

The outline is a property of the zone (`OUTLINE`, ADR-0006 *Outlines*). It is drawn with the Outline
tool [T]:

- Painting with [T] marks hexes **inside** the zone; [T] with the eraser modifier (right drag) marks them
  **outside**. Fill [G] inside the outline tool fills a region bounded by the outline.
- "Outline from floor" (a button in the inspector while [T] is armed) sets the outline to the
  connected floor region that holds the entry.
- The canvas shades what is outside. The inspector shows the derived **chunk set** (which chunks hold
  at least one inside tile) and the **border chunks** (chunks partly inside), as a small 15 × 15 grid
  of chunk cells.
- A town has no outline. Its "island" (the land the hub stands on, `hubWorld`'s `onIsland`) is
  painted as ground, not drawn as an outline.

### 2.6 Validation panel

It opens from the top bar's light or with its key, as a drawer over the inspector column (280 px).

```
+-------------------------------------+
| Validation              ● 1 ● 2   ✕ |
|-------------------------------------|
| ● R  Entry tile outside the outline |
|      entry chunk 0 tile 105  [Show] |
| ● E  Gate G2 not reachable from the |
|      entry                   [Show] |
| ● E  Walkable share 52 % (meadow    |
|      80–90 %)                [Show] |
|-------------------------------------|
| R = the Registry's check · E = the  |
| editor's · per game's format: ○     |
+-------------------------------------+
```

- One line per finding: severity (error ● red, warning ● amber, with the words "error" and "warning"
  for screen readers), its source (**R** for the Registry's, **E** for the editor's, **○** for a check
  that waits for game's format), the message, and **Show**, which selects the hexes or objects at
  fault and pans the camera to them.
- The checks run on every change, debounced, and at once on the Validate key. The list of checks is
  §5.
- **Export is refused while an error stands.** Saving is never refused: an unfinished map can be saved.

### 2.7 Export and import dialog

```
            +--------------------------------------------------------------+
            | Export · Ashen Meadow                                        |
            |                                                              |
            |  ( ) Map file (.grimmap.json): the editor's own, to reload   |
            |  ( ) Registration (zone only): per game's format — waits     |
            |      for track game's format brief                (greyed)   |
            |                                                              |
            |  Validation: ● 0 errors · 2 warnings   [ Show ]              |
            |                                                              |
            |                         [ Cancel ]   [ Download ]            |
            +--------------------------------------------------------------+
```

Import is "Open file…" on the map list and the same item in the editor's menu. It accepts an
editor file, and later the registration format (O-9). A file of a newer editor version, or one that
fails to read, is refused with the reason, and the current map is not touched.

### 2.8 Preview walk

[P] or the "Walk ▸" button switches the canvas into the game's view of the map. The panels fold to a
thin bar, so the layout is the game's desktop layout (design/11 l.169).

```
+----------------------------------------------------------------------------------------------------+
| Walking · Ashen Meadow (preview)   Keys: the game's (Q W E A S D, arrows, F, Enter, 0, + −)  [P] ◂ Edit |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|                        the game's canvas: camera, zoom, sight of radius 6,                         |
|                        path preview, walk, as the instance screen draws them                       |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
| Start: (•) the entry  ( ) a gate [G1 ▾]  ( ) the selected hex           Fog: ( ) on  (•) off        |
+----------------------------------------------------------------------------------------------------+
```

- The world is built from the map exactly as the game builds an instance (zone) or a hub (town):
  the same `SandboxWorld`, the same `SandboxSession`, the same intents and the same `findPath`.
  A zone walks `bounded` and a town walks unbounded, as `wiring.ts:177` does today.
- **Fog** off by default (everything revealed). On shows the game's reveal by sight radius 6
  (`revealInSight`), so the author sees what a player sees on entering.
- No goblins and no combat in CLI-09. Packs are markers, not actors.
- Edits are not possible while walking. Leaving the walk returns to the same camera and selection.
  The walk changes nothing in the map.

## 3. Controls

**Rules:**

- Letters are read by **position** (`event.code`), as CLI-03k does (`keys.ts:9-12`), so AZERTY and
  QWERTY users press the same physical key. The tool letters are chosen among keys that sit at the
  **same place and carry the same letter** on both layouts (B C D E F G H I J K L N O P R S T U V X Y),
  so the mnemonic holds on both. A, Q, W, Z and M move between the layouts and are not used as tool
  keys.
- Symbols (`+`, `−`, `=`, `?`, `[`, `]`) are read by **character** (`event.key`), as CLI-03k reads
  its zoom keys (`keys.ts:209-215`). On AZERTY, `[` and `]` need AltGr, so the brush size also has
  `Shift+wheel` and the inspector's field.
- **Shortcuts with Ctrl or Cmd** (undo, redo, save) are read by **character** (`event.key`), as
  browsers and every editor do. Ctrl+Z is then the key labelled Z on both layouts. CLI-03k ignores any
  key with Ctrl, Cmd or Alt (`keys.ts:219`), so these never reach the game's bindings. Cmd on macOS,
  Ctrl elsewhere.
- **No editor key clashes with a game key, in either mode.** While editing, the editor's bindings are
  live, and the game's camera keys keep their meaning (0 recentres, `+`/`−` zoom). While walking
  (§2.8), **only the game's `BINDINGS` are live** (the instance screen's set, or the hub screen's in a
  town), plus `P` to leave the walk. `P` is bound by no screen of CLI-03k. The editor's tool letters
  avoid every code the game binds or reserves (KeyQ W E A S D F L R Z X C V, Digit0–9, Space, Enter,
  Escape, the arrows), so a press meant for one mode does nothing harmful in the other.
- A text field keeps its keys: the editor's bindings are ignored in `input`, `textarea`, `select` and
  `[contenteditable]`, as CLI-03k's key layers do (`sandbox/keyScope.ts:54`). The editor's bindings
  are one key layer of CLI-03k's stack (`useKeyLayer`, `keyScope.ts:103`). A dialog pushes its own
  layer, where Escape closes it and Enter confirms.
- One action per press. Auto-repeat is ignored but for the arrows (pan), which repeat.

| Action | Mouse | Key (edit mode) | Notes |
|---|---|---|---|
| **Paint** (terrain or ground) | Left drag with Paint armed | `B` arms Paint | Paints the palette's swatch under the brush |
| **Erase** | Right drag with any brush tool, or left drag with Erase armed | `N` arms Erase | Terrain back to the map's start fill; removes objects in Place mode |
| **Fill** | Left click with Fill armed | `G` arms Fill | Fills the connected region of the same terrain and ground (hex neighbours, inside the map) |
| **Pick** (eyedropper) | `Alt`+left click with any tool, or left click with Pick armed | `I` arms Pick | Takes the hex's terrain and ground into the palette, then returns to the previous tool |
| **Select** | Left click; drag for a box; `Shift`+click adds | `U` arms Select | Selects hexes or objects; the inspector follows |
| **Move** | Drag a selected object | — | Objects only; terrain is moved by Cut and Paste |
| **Cut / Copy / Paste** | — | `Ctrl/Cmd+X`, `+C`, `+V` | Read by character. Paste follows the pointer until a click; the paste keeps row parity (§4.1) |
| **Delete selection** | — | `Delete` or `Backspace` | Objects deleted; selected hexes back to the start fill |
| **Place object** | Left click with Place armed | `O` arms Place | Places the palette's object; one entry per map |
| **Outline** | Left drag inside, right drag outside, with Outline armed | `T` arms Outline | Zones only (§2.5) |
| **Mirror** (towns) | — | `H` | A building, decor or prop: `mirror` on or off (`ViewStructure.mirror`, `view.ts:83-99`) |
| **Rotate / facing** | — | none | Not relevant: no record of a map carries a facing (`Gate`, `Location`, `models/index.cairo:43-92`), and authored pieces rotate nothing (ADR-0006 l.210). The adventurer's facing at arrival is the game's |
| **Pan** | Middle drag, or `Space`+left drag, or two-finger trackpad scroll | Arrows (repeat) | `Space` is free in edit mode; it is reserved only on the instance screen, which edit mode is not |
| **Zoom** | Wheel (trackpad pinch), at the pointer | `+` / `=` in, `−` out | As the game (`keys.ts:159-170`), same meaning; limits as `DEFAULT_ZOOM` but `minAcross` raised to fit the whole map (§2.3) |
| **Fit / recentre** | — | `0` | Fits the whole map; the game's `0` recentres on the adventurer, the same idea |
| **Brush size** | `Shift`+wheel | `[` smaller, `]` larger | A hexagon of radius 0, 1, 2 or 3 (1, 7, 19 or 37 hexes) |
| **Undo / Redo** | Top bar ⟲ ⟳ | `Ctrl/Cmd+Z`; `Ctrl/Cmd+Shift+Z` or `Ctrl+Y` | One stroke (press to release) is one step; at least 200 steps |
| **Toggle grid** | Layers bar | `J` | |
| **Toggle layers** | Layers bar | `K` cycles the focus in the layers bar; `Shift+K` toggles the focused layer | Ground, obstacles, objects, outline, chunk seams, grid |
| **Validate** | Top bar light | `Y` | Runs every check now and opens the panel (§2.6) |
| **Save** | — | `Ctrl/Cmd+S` | Saves the draft in the browser and downloads the file (§6). `preventDefault` on the browser's save |
| **Export** | Top bar Export… | `Ctrl/Cmd+Shift+E` | Opens the dialog (§2.7) |
| **Open** | Map list | `Ctrl/Cmd+O` | Opens a file |
| **Walk** (preview) | Status bar "Walk ▸" | `P` (and `P` again to leave) | §2.8 |
| **Inspect** | Right click with Select or Place armed; hover shows the hex in the status bar | — | design/11's desktop mouse: right click inspects (l.170) |
| **Cancel** | — | `Escape` | Ends a paste, a box or a drag; clears the selection; closes a dialog |
| **Help** | — | `?` | Lists this table, built from the editor's bindings, as CLI-03k builds its help (CLI-03k §7) |

Right drag erases with a brush tool and inspects with Select or Place. The browser's context menu is
suppressed on the canvas only.

## 4. Data held by the editor

This section is in words, not a format. Where game's format will decide, it says **per game's
format**. The editor's file holds everything below, plus a format version and the editor's version
(§6).

### 4.1 The map and its hexes

- **The map**: its kind (zone, town or outpost), its name, its location id, its size in chunks (width
  and height), and for a zone its biome, level band, rank required, spawn table id and quota list (§4.2).
  The size in tiles is 15 × the size in chunks. Coordinates are the global `(x, y)` of the chain and of
  the client (x grows West, y North; odd-r rows), so that no conversion is needed between the editor,
  the game and the export. Chunk `(cx, cy) = (x / 15, y / 15)`; chunk index `15 cy + cx`; tile index
  `15 (y mod 15) + (x mod 15)`.
- **Each hex** carries:
  - its **terrain**: floor or wall. This is the one bit the chain uses (`Terrain`, 1 = wall,
    ENG-05 l.57). An `unrevealed` hex does not exist in the editor: revealing is the game's.
  - its **ground**: grass, earth or water (`GroundKind`, `view.ts:24`). Today ground is presentation
    and follows terrain: water is a wall, earth is floor (`world.ts:14-16`). In the editor ground and
    terrain are set apart, but the validation warns where they disagree (§5, E-12). Whether ground
    goes on chain or stays client data is **per game's format** (G-1).
  - its **obstacle look**: `auto` (today's choice by `hexHash`, `obstacles.ts:29-53`) or one pinned
    variant among rock, bush, stump and tree. This is presentation, client data, and has meaning only
    on a wall on land (`isRock`, `ground.ts:33-35`).
  - whether it is **inside the outline** (zones). This is stored as the outline itself (§4.4), not per
    hex.
- **Row parity**: a hex's neighbours depend on whether its row is odd. Cut, paste and move keep the
  rows' parity, so a pasted shape is the same shape. They move by an even number of rows, or the
  paste snaps to the nearest row of the same parity.

### 4.2 Objects of a zone

| Object | What it carries | Today's source | Where it goes |
|---|---|---|---|
| **Entry** | One hex: where an adventurer enters (`entry_chunk`, `entry_tile`) | `Location`, `models/index.cairo:66-68`; `LocationRecord`, `region.ts:26-38` | The `LOCATION` record |
| **Gate** | Its anchor hex (on the outline, ADR-0006 l.181); destination location id; kind; rank required; quest required; the entry chunk and tile in the destination | `Gate`, `models/index.cairo:78-92`; `GateRecord`, `region.ts:40-51` | One `GATE` record each; a gate's id is the registration's (sequential, §5 R-4) |
| **Quota place** | A hex, and the quota it serves: exit, Heart, vein, collector, landmark or set piece (ENG-05 l.141) | design/18 l.32-46; ADR-0006 kind 2 | **Per game's format** (G-3): today a quota is a count drawn at reveal, with no place. Under D-214 the author marks the candidate places |
| **Quota (the list)** | Up to 6 quotas: kind, parameter, count (ENG-05 l.141) | `QUOTAS` (kind 5), its layout ENG-05's | Map property; the `QUOTAS` record **per game's format** |
| **Feature** | A hex and its kind: chest, gathering node, trap, landmark (design/18 l.32-46) | ENG-05's `Features` objects (tile, kind, state, `param`; l.59-61) | **Per game's format** (G-3): today drawn by frequency at reveal |
| **Pack place** | A hex where a pack may stand, optionally a pack template id | ENG-05's `Features` packs (l.59-61) | **Per game's format** (G-4) |
| **Outline** | §4.4 | `OUTLINE` | `OUTLINE` records |

The level band, rank, spawn table and quota list are numbers typed in the map's properties. The editor
does not read the records they name.

### 4.3 Objects of a town

A town map replaces today's code fixtures (`fixtures/hubs.ts`, `hubWorld.ts`) with data of the same
meaning:

| Object | What it carries | Today's source |
|---|---|---|
| **Place** | A service (`ServiceId`, `input/intent.ts:14-15`) or the gate; a building (one of `BUILDINGS`, `hubs.ts:48-66`); its door hex; its depth in rows (default 1, `DEFAULT_DEPTH`); mirror | `HubPlace`, `hubView.ts:19-33`; `footprint`, `hubWorld.ts:44-56` |
| **Decor building** | A building without a service; its base hex; depth; mirror | `HubDecor`, `hubView.ts:36-45` |
| **Prop** | A prop sprite (tree, bush, stump, rock, sheep…); its hex; mirror | `HubProp`, `hubView.ts:48-53` |
| **Figure spot** | A hex where a present adventurer stands, and the side it faces (left or right) | `HubFigure`, `hubView.ts:56-63` (design/11 l.156-163) |
| **Arrival** | The hex where the adventurer appears | `HubView.arrival`, `hubView.ts:65-81` |
| **Path** | Earth ground, painted as ground | `HUB_PATHS`, `hubs.ts:214-233` |
| **Island** | Land ground (grass or earth) against water | `onIsland`, `hubWorld.ts:59-67` |

A building's footprint is computed as `footprint` computes it (the hexes under its width on its base
row, plus its depth behind). Those hexes are walls but for the door, as `structures()` does
(`hubWorld.ts:72-108`). The editor shows the footprint and does not let the author paint it by hand.

### 4.4 The outline (zones)

The author draws a set of inside hexes. The editor derives what ADR-0006 stores:

- the **chunk set**: the chunks that hold at least one inside hex, bit `15 cy + cx`;
- for each **border chunk** (partly inside), its **tile mask**: bit `15 row + column`, 1 when the tile
  belongs to the zone (`models/index.cairo:95-98`);
- a chunk wholly inside has no mask, as ENG-05 reads it ("a chunk of the set with no mask is whole",
  l.167-169).

Hexes outside the outline are void in the game: wall, drawn as the void (`zoneWorld`, `zone.ts:43-97`).
The editor shades them and keeps whatever terrain was painted there; the export ignores it.

## 5. Validation

Each check has an id, its owner, its source and its severity. **R** marks a check that the Registry or
its record models make: the editor reproduces it so that a registration is not refused. **E** marks
a check that is the editor's own. **○ per game's format** marks a check whose rule game's format brief
will confirm, change or drop. Until then such a check is a warning.

**What the Registry checks today.** `Registry.set_record` checks the administrator, the kind, the part
count, the id, `LIVE`, and the allocation (`registry.cairo:163-187`). Its content checks
(`assert_content`, `registry.cairo:245-271`) cover `MODIFIER`, `ARMOR_SET`, `SKILL`, `ITEM` and
`CASTE` only. **"Every other kind has no bound of design/20"** (l.244), so `LOCATION`, `OUTLINE`,
`GATE` and `QUOTAS` get no content check at `set_record`. Their bounds are checked when a record is
**packed** by its model in `grimworld_logic` (each `Record::pack` calls `assert_valid`), that is by
the content pipeline before registration. Both kinds are listed below as R, and the source says which.

| Id | Check | Owner | Source | Severity |
|---|---|---|---|---|
| R-1 | Width and height in chunks are below 16 (1–15); 0 is refused by the editor (E-1) | R (model, at pack) | `location.cairo:110-111` (`SIDE_BOUND`, l.32) | error |
| R-2 | The entry's chunk and tile indices are below 225 | R (model, at pack) | `location.cairo:112-113` (`INDEX_BOUND`, l.30) | error |
| R-3 | Each gate's anchor chunk and tile, and its entry chunk and tile in the destination, are below 225 | R (model, at pack) | `gate.cairo:102-107` | error |
| R-4 | A new sequential id is `last_id + 1`, and an existing id is at most `last_id` (`LOCATION`, `GATE`) | R (`set_record`) | `registry.cairo:167-179`, `assert_existing` l.275-277; `content.cairo:59-61` | not checkable offline: the editor shows the ids it will use and says the registration checks them |
| R-5 | An `OUTLINE` id's chunk is below 225 or is 255 (the chunk set) | R (`set_record`) | `registry.cairo:288-292`; `CHUNK_SET`, `outline.cairo:9` | error (holds by construction: the editor derives the ids) |
| R-6 | An `OUTLINE` or `QUOTAS` record's location exists: the `LOCATION` is registered first | R (`set_record`) | `registry.cairo:285-297`, `assert_exists` l.301-303 | the export's order, not a check of the map |
| R-7 | An outline's high limb is below 2^97: no bit above 224 | R (model, at pack) | `outline.cairo:33-35` | error (holds by construction) |
| R-8 | Each record has exactly `parts(kind)` felts, `LIVE` in part 0, and an id that is not 0 | R (`set_record`) | `registry.cairo:222-229`; `content.cairo:48-50` | the export's, **per game's format** |
| R-9 | At most 15 set-piece ids on a location | R (layout) | `models/index.cairo:41`, `Lanes16` | error, if game's format keeps set pieces on zones (○) |
| R-10 | At most 6 quotas | R (layout, ENG-05) | ENG-05 l.141 | error (○ until `QUOTAS` is laid out) |
| E-1 | The size is whole chunks, at least 1 × 1; at most 15 × 15 for a zone (R-1) and 4 × 4 for a town | E | §2.2 | error |
| E-2 | The outline is not empty and is **one connected region** (hex neighbours) | E | ADR-0006 *Outlines* ("an irregular shape") | error |
| E-3 | The outline is **closed**: no inside hex touches the map's edge unless it is a wall or a gate anchor (the border of a location is closed but for gates, ADR-0006 l.199) | E | ADR-0006 l.199 | error |
| E-4 | Exactly one entry. It is a floor hex inside the outline | E | `Location.entry_*`; ENG-05 l.175 ("the entry tile likewise": open and reachable) | error |
| E-5 | Every gate anchor is a floor hex inside the outline, **on its border** (a neighbour outside the outline, or on the map's edge) | E | ADR-0006 l.181 ("Gates: anchors on the outline"); ENG-05 l.175 | error |
| E-6 | **Every gate anchor is reachable from the entry**, and the entry from every gate, over floor inside the outline | E | ENG-05 l.175 ("a gate's anchor tile open and reachable") | error |
| E-7 | Every floor hex inside the outline is reachable from the entry (no sealed pocket) | E | ADR-0006 l.198 ("all chunks are therefore reachable") | warning |
| E-8 | Every quota in the list has at least `count` quota places of its kind | E | D-214 ("place quota places"); ENG-05 l.171-175 | error ○ |
| E-9 | At most 2 pack places, 5 goblins a pack and 3 objects (features and quota places) **per chunk** | E | ENG-05 l.61 (ENG-05's own E-3: the chunk's storage) | error ○ |
| E-10 | Features, pack places and quota places are on floor, inside the outline | E | design/18 l.32-46 | error |
| E-11 | The four corner tiles of each chunk are walls; every seam between two inside chunks has at least one opening | E | ADR-0006 l.198-200 (D-134); a rule of generation | warning ○ (G-5) |
| E-12 | Ground agrees with terrain: water only on walls, earth only on floor | E | `world.ts:14-16` | warning |
| E-13 | The walkable share of the floor inside the outline is within design/18's range for the biome | E | design/18 l.17-26 | hint (never blocks export) |
| E-14 | (Town) every service of the hub's list has one place, and one gate place exists | E | `TOWN_SERVICES` and `OUTPOST_SERVICES`, `hubs.ts:21, 37` | error |
| E-15 | (Town) every place's door and the arrival are floor; every door is reachable from the arrival | E | `structures()`, `hubWorld.ts:72-108` | error |
| E-16 | (Town) every footprint is on land and inside the map; no two footprints overlap | E | `footprint`, `hubWorld.ts:44-56` | error |

**Where the checks live.** The checks are code of the tool, in the editor's folder (`client/app/src/editor/`).
They are not game rules, so they are not `client/sim`'s (mandate §6). Reachability uses the hex
neighbours of today's `placeholders.ts` until CLI-02 gives `client/sim` its own. **Once game's format
lands**, the R checks should be fed by a vector table printed from the Cairo models
(`contracts/logic/vectors`), so that the editor and the Registry cannot drift (G-6).

## 6. Save, load, export

- **Save** writes the map to a local file: a download of one JSON document (`<name>.grimmap.json`). It
  carries the editor's format version, the editor's version (the client's commit), the kind and
  everything in §4. **Load** reads such a file from a file picker or by dropping it on the page.
- **Drafts**: the open map is also kept in the browser's local storage after each change, so that a
  closed tab loses nothing. This is a convenience of one browser (O-5). The map list shows the drafts
  and warns that they live in this browser only. Every read and write of the storage is guarded: the
  editor works without it.
- **Nothing on a server**: no upload, no account, no key, no Registry read, no chain call. The editor
  makes no network request but for the page's own files and `/art/`.
- **Town maps** are client data. A town file is what the game's hubs will read instead of the code
  fixtures. That move is a later lot (O-6), and it commits the town files as JSON under `client/app`.
  They are data, not art (D-73 holds: no image).
- **Zone maps** are saved the same way. They are also **exported for registration, per game's format**
  (§10). The export file is handed to the administrator's content pipeline (OPS-01), which writes the
  records. The editor never writes them.
- **Versions**: a file of an older format version is migrated on load, with a note. A newer one is
  refused, with the reason.

## 7. Art and D-73

- The editor draws only from the **built atlas and `sprites.json`**, loaded by `loadAtlas` from
  `/art/` as the game loads them (`render/atlas.ts:8-54`). It never reads the pack's raw files: no path
  into `tools/art/assets`, no PNG of the pack, nothing of the pack in the editor's code or bundle.
- The palette's swatches of ground, obstacles, buildings and props are drawn by Pixi from the same
  atlas frames the renderer uses (`grass_c`, `water_c`, `foam_c`, the `rock`, `bush`, `stump` and `tree`
  stills, the building stills of the manifest). Without the atlas, every swatch and the canvas fall
  back to the flat shapes the client already draws.
- Overlays (grid, seams, outline, markers, selection) are plain shapes, never art.
- **Nothing derived from the pack is committed or posted**: no screenshot or recording of the editor
  with the art in a pull request, an issue, a comment or a report. Captures of shapes without the art
  (the editor with the atlas off) may be posted. Captures with the art stay on the Mac or go to the
  owner directly (mandate §4).
- Map files hold sprite **names** (`castle`, `rock2`…), never pixels.

## 8. Open questions

Each has a recommended default. A lot may start on the default; the answer reverses it.

**For the orchestrator of track CV:**

| # | Question | Default |
|---|---|---|
| O-1 | How the editor is reached: its own Vite entry (`client/app/editor.html` and `src/editor/`, a second `build.rollupOptions.input`), or a query parameter of today's page (`?editor=1`, `params.ts`) | **Its own entry**, served at `/editor.html` on the site. The game's bundle does not carry the editor, and the editor imports the game's modules. The site's deploy builds every entry of `vite build` without change; CLI-09a checks it |
| O-2 | Whether the editor is published on the public site | **Yes**, with no link from the game. It holds no secret and writes nothing anywhere |
| O-3 | Touch | **Never in CLI-09**: one line below 700 px. A later lot only if the owner asks |
| O-4 | Chrome: plain (`data-chrome="plain"`) or the pack's chrome (CLI-03i's `Panel`, `Button`…) | **Plain**: a dense tool, and its panels are not the game's. The pack's chrome can be switched on later without changing the layout |
| O-5 | Drafts in the browser's local storage | **Yes**, guarded, with the warning on the map list |
| O-6 | Town maps replace `fixtures/hubs.ts` in the game | **Yes, in a lot after CLI-09b** (CLI-09d): the town and the outpost redrawn in the editor, committed as JSON, read by `hubWorld`; the hub screens unchanged |
| O-7 | Undo depth | **200 steps**, in memory, lost on reload (the draft keeps the map, not its history) |
| O-8 | Set pieces for dungeons (one authored chunk, ADR-0006 l.206-211) with the same canvas | **Not in CLI-09.** A 1 × 1-chunk map kind can be added once game's format covers `SET_PIECE` |

**For track game** (to answer in its format brief):

| # | Question | Default (track CV's recommendation) |
|---|---|---|
| G-1 | Does the chain hold only floor/wall per hex, or ground (grass, earth, water) too? If only floor/wall, how does a client get a zone's ground: from a client file of the map, matched to the chain's terrain? | Floor/wall on chain. Ground, obstacle looks and the town data stay client data, shipped with the client and checked against the chain's terrain by a hash |
| G-2 | Is an authored zone still revealed chunk by chunk (fog of war on terrain), or is its terrain public and only the goblins in sight? | The editor is the same either way; only the preview's Fog option follows the answer |
| G-3 | Which features are placed by the author (fixed) and which are drawn at reveal among the author's **candidate places** (quota places)? Are chests, gathering nodes and traps still drawn by frequency (design/18)? | Quotas (collector, landmark, exit) draw among the author's candidate places. Chests, nodes and traps are placed by the author as candidates and drawn by frequency among them |
| G-4 | Packs: places set by the author, or still drawn by the spawn table anywhere on floor? | The spawn table stays. The author may mark pack places; without marks the reveal places packs as today |
| G-5 | Do the generation rules (the corner tiles of a chunk are wall, at least one opening on every seam, features at least 2 tiles from an opening; ADR-0006 l.198-200, design/18 l.34) bind an authored zone? | No for corners and openings (the author's terrain is the map). Yes for ENG-05's per-chunk limits (its E-3, l.61; this brief's E-9) |
| G-6 | Will game's format lot print a vector table for the packing and `assert_valid` of the zone's records, so that the editor's R checks and the export are checked against Cairo? | Yes, one table in `contracts/logic/vectors`, read by `client/sim` as the other tables are |
| G-7 | Gate ids and location ids are sequential on chain. Does the export carry ids, or does the pipeline allocate them and rewrite the gates' references? | The export carries the author's ids. The pipeline refuses a file whose ids are not next (R-4) |
| G-8 | Does a location carry a name on chain? | No: names are client data, as today (`REGION` has a name, a location does not) |

## 9. Lots

| Lot | Scope | Acceptance (one line) |
|---|---|---|
| **CLI-09a** | The page (O-1), the map list, the new map dialog, the canvas with the game's renderer, the camera, Paint, Erase, Fill, Pick, brush sizes, the layers bar, undo and redo, the outline tool, save and load of the editor's file, drafts | A 15 × 15-chunk zone is created, painted, outlined, saved, reloaded from the file and identical (a test compares the documents), and the browser check shows it at 1440 × 900 in shapes |
| **CLI-09b** | Objects (entry, gates, quota places, features, pack places; a town's places, decor, props, figure spots, arrival), the inspector, Select and Move, Cut, Copy and Paste, Mirror, the validation panel with every check of §5 that does not wait for game's format, the preview walk | Each check of §5 has a failing and a passing fixture map in tests. The seed's zone (`fixtures/zone.ts`) and the town (`fixtures/hubs.ts`), redrawn in the editor, validate with no error and walk in the preview as in the game |
| **CLI-09c** | The registration export (and its import) **per game's format**, its R checks against game's vector table (G-6), the ○ checks settled | The seed's zone exported by the editor equals the records of `contracts/seed` for its `LOCATION`, `OUTLINE`, `GATE` and `QUOTAS`, felt for felt |
| CLI-09d (O-6) | The game's hubs read town files made by the editor instead of `fixtures/hubs.ts` | The hub screens' existing tests and browser checks pass unchanged on the town and outpost files |

CLI-09a and CLI-09b do not wait for track game. CLI-09c waits for game's format brief and its merged
models.

## 10. Export format — waits for track game's format brief

Only what is known on `main` today:

- A zone's registration is a set of Registry records written by the administrator (`set_record`,
  `registry.cairo:163-187`), each `parts(kind)` felts with `LIVE` in part 0 (`content.cairo:48-50`,
  l.57-58):
  - `LOCATION` (kind 2, 2 parts, sequential): the kind, region, biome, level band, rank, width and
    height in chunks, `N` (0 for a zone), floors, next floor, spawn table, sealed, entry chunk and
    tile; part 1 holds up to 15 set-piece ids (`models/index.cairo:36-71`, packed by
    `location.cairo:120-142`).
  - `OUTLINE` (kind 3, 1 part, composite): id `location × 256 + 255` is the chunk set, and id
    `location × 256 + chunk` is a border chunk's tile mask (`outline.cairo:24-27`; bits 0–127 in the low
    limb, 128–224 in the high).
  - `GATE` (kind 4, 1 part, sequential): source, destination, anchor chunk and tile, entry chunk and
    tile, kind, rank, quest (`models/index.cairo:73-92`).
  - `QUOTAS` (kind 5, 1 part, composite, id = the location's): its layout is ENG-05's (not on `main`).
- **Not known**: how an authored zone's **terrain** is stored (per chunk, as ENG-01 §3.2's `Terrain`
  word, 1 = wall, or as a new record kind), how authored features and quota places are stored, whether
  ground is stored (G-1), the file's shape (records as hex felts like the vector tables, or fields
  that the pipeline packs), and the order of registration (R-6: `LOCATION` before its `OUTLINE` and
  `QUOTAS`).
- The client's seed (`fixtures/region.ts`: `SEED_LOCATIONS`, `SEED_GATES`, `SEED_OUTLINES`) and
  `contracts/seed` hold today's example of a zone's records, and are CLI-09c's test.
