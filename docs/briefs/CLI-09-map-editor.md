# CLI-09 — The map editor

**Status: CLI-09a and CLI-09b can start against this brief; CLI-09c waits.** Part 1 (screens and
controls) was written by a thread of track CV on 2026-10-05 for the orchestrator of track CV. Part 2
folds in track game's format brief, `docs/briefs/ENG-08-authored-zones-format.md`, and D-215's answers
(2026-10-05). **The exact JSON schema waits for ENG-08's spike**, and so does every line marked
*waits for ENG-08's spike* (○). CLI-09c waits for that schema. Nothing here decides a game rule: the
editor reproduces checks, it does not invent them (mandate `docs/briefs/ORCH-client-visual.md` §6).

## Agent

To be set per lot by the orchestrator. Proposed: `impl-opus` for CLI-09a (a new page, a new input
model and the renderer reused in a new way), and `impl-sonnet` for the lots after it. No pin, gas
table or budget is involved, so every lot can run on the Mac (`--machine mac`, repo
`/Users/bal7hazar/git/grimworld`). Browser checks need a real Chrome through Playwright, as CLI-03c
did.

## Context

- **D-214** (owner, 2026-10-05; `docs/decisions/2026-10-05-zone-maps-editor.md`). Zones get **authored
  maps** made with a map editor and exported in a format the chain accepts. Towns are made with the
  same editor and stay client-only data (D-03). Dungeons stay generated. This reverses ADR-0006 §2
  ("Everything is generated, at reveal", D-106) **for zones only**. ADR-0006's open CM-7 ("Format of
  authored chunks and outline masks, and the tool to draw them", l.355) is answered for the tool by this
  brief and for the format by `docs/briefs/ENG-08-authored-zones-format.md`.
- **D-215** (project manager, 2026-10-05) and ENG-08's rulings, which this brief follows: only the
  walkable plane goes on chain; quotas are drawn among authored candidates; spawn points are authored;
  `tools/map-format/` is owned by track game and consumed by CV; the Registry's content checks for map
  records are the checks the editor reproduces exactly (§5, §10).
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
engine, and saves it as a file. Once ENG-08's schema exists (CLI-09c), they also export what a zone's
registration needs.

**In:**

- A page of the client: the same Vite app and the same modules, its own entry, served on the site like
  the rest (Open question O-1).
- **Desktop first and desktop only**: mouse and keyboard. **Touch: never in CLI-09.** Below 700 CSS px
  wide (design/11's desktop threshold, l.173) the page shows one line: "The map editor needs a desktop
  window." Reversible by a later lot if the owner asks (O-3).
- Two kinds of map:
  - **Zone maps**: a location of kind `ZONE` (`location.cairo:14`). They are exported for
    registration in ENG-08's format (§10).
  - **Town maps**: hubs of kind `TOWN` or `OUTPOST`. They are client data only (D-03), and their
    places are buildings (D-202).
- Painting terrain per hex, placing features and objects, marking candidate quota places and spawn
  points, the entry and gates, drawing the zone's outline.
- Validation: ENG-08's content checks for map records, and the editor's own (§5).
- A preview walk with the zone engine as the game runs it.
- Saving and loading local files. Exporting a zone for registration (§6, §10).

**Out:**

- **Dungeons**, Nests and Rift floors: they stay generated (D-214). **Set pieces** (authored chunks
  that a quota lays into a generated dungeon, ADR-0006 l.206-211) are not in CLI-09. The same canvas
  could draw them later (O-8).
- **Any on-chain write.** No key, no account, no wallet, no RPC call, no Registry read. Registration
  is the administrator's act through the content pipeline (OPS-01). The editor hands over a file.
- **Any server storage.** Nothing is uploaded, and nothing is saved on the site.
- Spawn tables, pack templates, castes, quests and shops as content. A zone's level band, spawn table
  and rank are typed as numbers in the map's properties, and a spawn point's template as a number. Their
  records are other content. A spawn point's level and a pack's goblin count are not authored: they are
  drawn at entry (D-215, ENG-08 ruling 4).
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
            |  Biome     [ Meadow ▾ ]   (zone only)                |
            |                                                      |
            |                         [ Cancel ]   [ Create ]      |
            +------------------------------------------------------+
```

- **No size, no start fill** (owner's request, 2026-10-05; D-216): the map is a theoretically endless plane; the author paints
  it anywhere and the chunks are fitted afterwards ("Fit chunks", §2.3). The bound in whole chunks
  moves to the fitted map: for a zone 1 to 15 on each side (`LocationAssert::assert_valid`,
  `location.cairo:110-111`, 4 bits each); for a town or an outpost 1 to 4 on each side, an editor bound,
  since a hub has no size on chain (`LocationRecord.width` 0 for a hub, `fixtures/region.ts:26-38`). A
  fitted map past it is a problem shown with the fit.
- **Name** is at most 15 characters, the bound of a short string in `REGION` (`models/index.cairo:22-33`).
  It is used for the file name and the list. Whether a location carries a name on chain waits for
  ENG-08's spike (G-8).
- **Location id** is a number. The editor cannot know the chain's `last_id` (§5). ENG-08's export
  names a zone's gates and destinations and lets the converter resolve registry ids from a content
  manifest, so whether the id typed here is carried or only a working label waits for the schema (§10).
- **Biome**: Meadow, Forest, Cave or Ruin (`location.cairo:22-27`). It sets the default ground and the
  walkable-share hint of design/18 (l.17-26) shown in the inspector.

### 2.3 Main editor

```
+----------------------------------------------------------------------------------------------------+
| ◂ Maps | Ashen Meadow · Zone · 1 204 hexes · loc 2 | Saved 14:02 (draft) | ⟲ ⟳ | Validate ● 0 | Export… |
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

- **Top bar**: back to the map list; the map's kind, name, painted hexes (owner's request, 2026-10-05; D-216) and location id; the save state
  ("Saved 14:02 (draft)" or "Unsaved changes"); undo and redo; the validation light (green ● 0,
  amber ● warnings, red ● errors, with the count), which opens the validation panel (§2.6); Export…
  (§2.7).
- **Canvas**: the game's `Renderer` on a world built from the map (§4). Everything is revealed (no
  fog in the editor). The void around the map is drawn as the game draws it: `void: "water"`, as in
  `zoneWorld` and `hubWorld`. Over the art the editor draws overlays as plain shapes, never as art:
  - the hex grid (land only, as `ground.ts` does, or everywhere when the grid layer is on);
  - **chunk seams** as dashed lines around the chunks of the **last fitted grid**, with the chunk index in
    each chunk's corner. **No chunk grid while painting** (owner's request, 2026-10-05; D-216): the layer is off until "Fit
    chunks" shows it, and the author may toggle it;
  - the **outline** as a thick line on the zone's border, with the tiles outside the outline shaded;
  - **objects** as hex markers with a one- or two-letter label: `E` the entry, `G1…` gates, `Q`
    candidate quota places by kind, `F` features by kind, `P` spawn points;
  - in a town, each **place's footprint** shaded and its **door** hex marked;
  - the hovered hex, the selection, and the brush's footprint under the pointer.

  Colour is never the only carrier of meaning (design/11 l.175-182): every marker has a letter.
- **The canvas is unbounded** (owner's request, 2026-10-05; D-216): only the painted hexes are stored; an unpainted hex is the
  void (drawn as the game's water). Pan and zoom have no map edge; `0` fits the painted hexes. The
  renderer is sent only the tiles around the view (the visible tiles grown by half the view on each
  side, snapped to multiples of 15), rebuilt when the camera leaves them.
- **"Fit chunks"** (owner's request, 2026-10-05; D-216), in the inspector and `Shift+0`: tries every chunk grid origin compatible
  with the hex layout (15 × 15: the column residue, and the row residue on an **even** row so that the
  move to global coordinates keeps the rows' parity, §4.1) and keeps the one that covers the map's hexes
  with the **fewest chunks**, then the **fewest partly filled chunks**, then the smallest rectangle, then
  the lowest origin row and column. It shows the grid, the chunk count, the partly filled count and the
  fitted rectangle. The author **nudges** the origin by one hex with `Shift`+arrows or the four small
  buttons; the counts follow. The map's hexes are a town's painted hexes, and a zone's painted hexes
  inside its outline (outside is void, §4.4).
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
| R = ENG-08's check · E = the        |
| editor's · waits for the spike: ○   |
+-------------------------------------+
```

- One line per finding: severity (error ● red, warning ● amber, with the words "error" and "warning"
  for screen readers), its source (**R** for ENG-08's content checks for map records, **E** for the editor's, **○** for a check
  whose exact rule waits for ENG-08's spike), the message, and **Show**, which selects the hexes or objects at
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
            |  ( ) Registration (zone only): ENG-08's format — greyed      |
            |      until CLI-09c (needs ENG-08's spike schema)             |
            |                                                              |
            |  Validation: ● 0 errors · 2 warnings   [ Show ]              |
            |                                                              |
            |                         [ Cancel ]   [ Download ]            |
            +--------------------------------------------------------------+
```

Import is "Open file…" on the map list and the same item in the editor's menu. It accepts an
editor file, and in CLI-09c the registration format. A file of a newer editor version, or one that
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
| **Erase** | Right drag with any brush tool, or left drag with Erase armed | `N` arms Erase | The hexes are unpainted, back to the void (owner's request, 2026-10-05; D-216); removes objects in Place mode |
| **Fill** | Left click with Fill armed | `G` arms Fill | Fills the connected region of the same terrain and ground (hex neighbours). On an unpainted hex, the region must be closed by painted hexes (it may not reach past the painted hexes' box) and no fill takes more than 50 625 hexes (a 15 × 15-chunk zone); else it is refused with the reason (owner's request, 2026-10-05; D-216) |
| **Pick** (eyedropper) | `Alt`+left click with any tool, or left click with Pick armed | `I` arms Pick | Takes the hex's terrain and ground into the palette, then returns to the previous tool |
| **Select** | Left click; drag for a box; `Shift`+click adds | `U` arms Select | Selects hexes or objects; the inspector follows |
| **Move** | Drag a selected object | — | Objects only; terrain is moved by Cut and Paste |
| **Cut / Copy / Paste** | — | `Ctrl/Cmd+X`, `+C`, `+V` | Read by character. Paste follows the pointer until a click; the paste keeps row parity (§4.1) |
| **Delete selection** | — | `Delete` or `Backspace` | Objects deleted; selected hexes unpainted (back to the void) (owner's request, 2026-10-05; D-216) |
| **Place object** | Left click with Place armed | `O` arms Place | Places the palette's object; one entry per map |
| **Outline** | Left drag inside, right drag outside, with Outline armed | `T` arms Outline | Zones only (§2.5) |
| **Mirror** (towns) | — | `H` | A building, decor or prop: `mirror` on or off (`ViewStructure.mirror`, `view.ts:83-99`) |
| **Rotate / facing** | — | none | Not relevant: no record of a map carries a facing (`Gate`, `Location`, `models/index.cairo:43-92`), and authored pieces rotate nothing (ADR-0006 l.210). The adventurer's facing at arrival is the game's |
| **Pan** | Middle drag, or `Space`+left drag, or two-finger trackpad scroll | Arrows (repeat) | `Space` is free in edit mode; it is reserved only on the instance screen, which edit mode is not |
| **Zoom** | Wheel (trackpad pinch), at the pointer | `+` / `=` in, `−` out | As the game (`keys.ts:159-170`), same meaning; limits as `DEFAULT_ZOOM` but `minAcross` raised to fit the painted hexes and a full zone's room around them (§2.3) (owner's request, 2026-10-05; D-216) |
| **Fit / recentre** | — | `0` | Fits the painted hexes (owner's request, 2026-10-05; D-216); the game's `0` recentres on the adventurer, the same idea |
| **Fit chunks** | Inspector "Fit chunks" | `Shift+0` | The chunk grid with the fewest chunks (§2.3) (owner's request, 2026-10-05; D-216) |
| **Nudge the chunk origin** | Inspector ◂ ▸ ▴ ▾ | `Shift`+arrows (repeat) | One hex West, East, North or South, as on screen (owner's request, 2026-10-05; D-216) |
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

This section is in words, not a format: the exact JSON schema waits for ENG-08's spike (§10). It
follows D-215: **only the walkable plane goes on chain**, and everything else a hex or a zone carries is
a client-only layer. The editor's file holds everything below, plus a format version and the editor's
version (§6).

### 4.1 The map and its hexes

- **The map**: its kind (zone, town or outpost), its name, its location id, and for a zone its biome,
  level band, rank required, spawn table id and quota list (§4.2); **no size** (owner's request, 2026-10-05; D-216). Its
  **painted hexes** lie anywhere on an endless plane (x grows West, y North; odd-r rows, the client's
  layout); only they are stored. The map also keeps its **last chosen chunk origin** and whether it was
  fitted or nudged (§2.3). The **fitted map** is the plane moved so that the origin's chunk is global
  `(0, 0)`: its width and height in chunks are the fitted rectangle's, its global `(x, y)` are the
  chain's. Chunk `(cx, cy) = (x / 15, y / 15)`; chunk index `15 cy + cx`; tile index
  `15 (y mod 15) + (x mod 15)`, in the fitted map's coordinates. The origin's row is even: a move by an
  even number of rows keeps every row's parity (below), so the painted shape is the fitted shape. When
  the best grid's even origin row lies a whole chunk below the lowest painted row, the fitted map keeps
  an empty chunk row at its foot.
- **Each hex** carries:
  - whether it is **painted**: an unpainted hex is the void, not part of the map (owner's request, 2026-10-05; D-216);
  - its **terrain**: floor or wall. This is **the walkable plane**, the one bit the chain holds per
    tile (`Terrain`, 1 = wall; ENG-08 ruling 1, D-215). It is copied into the instance's chunk at reveal
    (ENG-08 ruling 2). An `unrevealed` hex does not exist in the editor: revealing is the game's.
  - its **ground**: grass, earth or water (`GroundKind`, `view.ts:24`). It is a **client-only layer**
    (D-215): visual tile kinds never go on chain, unless a rule needs more than walkable, in which case
    ENG-08 makes it a reserved plane on chain (its condition on ruling 1, not a guess of the client).
    Today ground is presentation and follows terrain: water is a wall, earth is floor
    (`world.ts:14-16`). In the editor ground and terrain are set apart, but the validation warns where
    they disagree (§5, E-12). Which ground a zone's export carries beside the walkable plane is the
    schema's (○, G-1 settled in principle).
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
| **Gate** | Its anchor hex (on the outline, ADR-0006 l.181); destination (by name or location id, §10); kind; rank required; quest required; the entry chunk and tile in the destination | `Gate`, `models/index.cairo:78-92`; `GateRecord`, `region.ts:40-51` | One `GATE` record each; a gate's id is the registration's (sequential; the registration's, §5). ENG-08 names the gate points a chunk anchors (deliverable 1, l.162-163); the layout waits for the spike |
| **Candidate quota place** | A hex, and the quota it is a candidate for: exit, Heart, vein, collector, landmark or set piece (ENG-05 l.141). **Several candidates per quota**: the author marks them, the draw at entry picks among them | design/18 l.32-46; ADR-0006 kind 2; ENG-08 ruling 3, D-215 | Candidates are on chain with the chunk's record (ENG-08 deliverable 1, l.161-162); the draw is the chain's, order-free (D-208, D-210). The layout waits for the spike |
| **Quota (the list)** | Up to 6 quotas: kind, parameter, count (ENG-05 l.141; ENG-08 l.55) | `QUOTAS` (kind 5) | Map property; the `QUOTAS` record is ENG-05's, with a candidate bound added (§5, R-13) |
| **Feature** (an object) | A hex and its kind: chest, gathering node, terrain trap, landmark, lever (ENG-08 l.159-161) | ENG-05's `Features` objects (tile, kind, state, `param`; ENG-08 l.59-61) | **Authored** (ENG-08 deliverable 1): placed by the author, within the per-chunk limit (§5, R-15). Whether chests, nodes and traps are also drawn among candidates by frequency waits for the spike (G-3) |
| **Spawn point** | A hex where a pack may stand, and a pack template id (typed as a number). Its **level** (within the zone's band) and the pack's **goblin count** are **not authored**: drawn at entry | ENG-05's `Features` packs, `SetPack` (ENG-08 l.159, l.59-61); D-215 ruling 4 | **Authored** spawn points on chain; the draws at entry are the chain's. The template's existence in the location's content is the pipeline's check (§5, R-17) |
| **Outline** | §4.4 | `OUTLINE` | `OUTLINE` records: the chunk set and the border chunks' masks only (ENG-08 ruling 6) |

The level band, rank, spawn table and quota list are numbers typed in the map's properties. The editor
does not read the records they name. Visual layers (ground, obstacle looks, decoration, props) are
client-only and are not in this table (§4.1, D-215).

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

The author sorts the painted hexes into inside and outside (a painted hex starts inside). The editor
derives what ADR-0006 stores, **from the fitted map** (owner's request, 2026-10-05; D-216):

- the **chunk set**: the chunks that hold at least one inside hex, bit `15 cy + cx`;
- for each **border chunk** (partly inside), its **tile mask**: bit `15 row + column`, 1 when the tile
  belongs to the zone (`models/index.cairo:95-98`);
- a chunk wholly inside has no mask, as ENG-05 reads it ("a chunk of the set with no mask is whole",
  l.167-169).

Hexes outside the outline are void in the game: wall, drawn as the void (`zoneWorld`, `zone.ts:43-97`).
The editor shades them and keeps whatever terrain was painted there; the export ignores it.

## 5. Validation

Each check has an id, its owner, its source and its severity. **R** marks one of **ENG-08's content
checks for map records**: the same list and the same refusals as the Registry's, which the editor
reproduces exactly so that a registration is not refused (ENG-08 deliverable 2, l.170-175: "one table
shared by the brief's reader, ENG-09 and track CV"; project manager's ruling, D-215). **E** marks a check
that is the editor's own. **○** marks a check whose exact rule waits for ENG-08's spike: until then it is
a warning. A source written `ENG-08 l.N` is a line of `docs/briefs/ENG-08-authored-zones-format.md`.

**What the Registry checks today.** At `main` `Registry.set_record` checks the administrator, the kind,
the part count, the id, `LIVE` and the allocation (`registry.cairo:163-187`), and its content checks
(`assert_content`, `registry.cairo:245-271`) cover `MODIFIER`, `ARMOR_SET`, `SKILL`, `ITEM` and `CASTE`
only. **It checks no map record's content** (ENG-08 l.123-128): `LOCATION`, `OUTLINE` and `GATE` have
only the pack-time checks of their models (`assert_valid`, run when the content pipeline packs a
record). ENG-08 specifies the content checks of the authored map records, ENG-09 builds them into
`RegistryAssert::assert_content`, ENG-R1c builds the four deferred bounds and ENG-09 reuses them for an
authored zone (ENG-08 ruling 8, l.144). The R checks below are that list. The exact JSON schema, and
with it the exact record layout each check reads, waits for ENG-08's spike.

| Id | Check | Owner | Source | Severity |
|---|---|---|---|---|
| R-1 | Width and height in chunks are 1–15 (0 is refused by E-1) | R (model, at pack) | `location.cairo:110-111` (`SIDE_BOUND`, l.32) | error |
| R-2 | The entry's chunk and tile indices are below 225 | R (model, at pack) | `location.cairo:112-113` (`INDEX_BOUND`, l.30) | error |
| R-3 | Each gate's anchor chunk and tile, and its entry chunk and tile in the destination, are below 225 | R (model, at pack) | `gate.cairo:102-107` | error |
| R-5 | An `OUTLINE` id's chunk is below 225 or is 255 (the chunk set) | R (model, at pack) | `outline.cairo:9`; `registry.cairo:288-292` | error (holds by construction: the editor derives the ids) |
| R-7 | An outline's high limb has no bit above 224 | R (model, at pack) | `outline.cairo:33-35` | error (holds by construction) |
| R-10 | At most 6 quotas | R (`QUOTAS` layout) | ENG-08 l.55 (`QUOTAS`: 6 × kind, param, count) | error |
| R-11 | The chunk set lies **within the `width × height` rectangle** | R (the four bounds, bound 1) | ENG-08 l.179-180; ruling 8, l.144 | error (holds by construction: the editor draws inside the map; a test proves it) |
| R-12 | A quota's count is at most the zone's members | R (the four bounds, bound 2) | ENG-08 l.180 | error ○ (what "members" counts, the zone's walkable tiles or its hosts, is the spike's) |
| R-13 | For an authored zone, a quota's count is at most **its candidate places** | R (bound 2, authored form) | ENG-08 l.176-177, l.180-181; ruling 3, l.139, ruling 8, l.144 | error |
| R-14 | Each authored chunk's fields fit their widths; **spawn points, objects and candidate quota places are on walkable tiles** | R (chunk-local) | ENG-08 l.173-174 | error |
| R-15 | Per chunk: at most **2 spawn points** and at most **3 objects** | R (chunk-local, E-3) | ENG-08 l.59, l.174 | error (whether a candidate quota place counts against the 3 objects is the spike's ○) |
| R-16 | The four corner tiles of an **authored** chunk may be floor: D-134's corner walls are **lifted** for authored chunks and kept for generated ones | R (ruling 5) | ENG-08 l.141; the spike's test, l.243-245 | no check ○ (if the spike finds code that reads the corners, the project manager decides; until then the editor does not check them) |
| R-17 | A spawn point's template is named by the location's content | R (between records) | ENG-08 l.177-178 | the editor checks only that the number is typed and not 0 (E-19); the existence check is the pipeline's, against a content manifest (○) |
| R-18 | Every gate anchor is on a walkable tile | R (between records) | ENG-08 l.178 | error |
| R-20 | Each border chunk's tile mask **agrees with the walls**, and the outline's chunk set is derived from the authored walls | R (ruling 6) | ENG-08 l.142 | error (holds by construction: the editor derives masks, §4.4; the importer refuses a file whose mask disagrees) |
| E-1 | The size is whole chunks, at least 1 × 1; at most 15 × 15 for a zone (R-1) and 4 × 4 for a town | E | §2.2 | error |
| E-2 | The outline is not empty and is **one connected region** (hex neighbours) | E | ADR-0006 *Outlines* ("an irregular shape") | error |
| E-3 | The outline is **closed**: no inside hex touches the map's edge unless it is a wall or a gate anchor | E | ADR-0006 l.199 | error |
| E-4 | Exactly one entry. It is a floor hex inside the outline | E | `Location.entry_*`; ENG-08 l.161-162 | error |
| E-5 | Every gate anchor is **on the outline's border** (a neighbour outside the outline, or on the map's edge) | E | ADR-0006 l.181 ("Gates: anchors on the outline") | error |
| E-6 | **Every gate anchor and every candidate quota place is reachable from the entry**, and the entry from every gate, over floor inside the outline | E; the converter and the pipeline check it too | ENG-08 l.184-186, l.221-222 | error |
| E-7 | **Every walkable hex inside the outline is reachable from the entry** (no sealed pocket) | E; the converter refuses it too (ENG-08's AC-7, l.311) | ENG-08 l.184-185 | error (was a warning in part 1: ENG-08 makes it a refusal) |
| E-10 | Features, spawn points and candidate quota places are **inside the outline** | E | design/18 l.32-46; R-14 holds the walkable part | error |
| E-12 | Ground agrees with terrain: water only on walls, earth only on floor | E | `world.ts:14-16` | warning |
| E-13 | The walkable share of the floor inside the outline is within design/18's range for the biome | E | design/18 l.17-26 | hint (never blocks export) |
| E-14 | (Town) every service of the hub's list has one place, and one gate place exists | E | `TOWN_SERVICES` and `OUTPOST_SERVICES`, `hubs.ts:21, 37` | error |
| E-15 | (Town) every place's door and the arrival are floor; every door is reachable from the arrival | E | `structures()`, `hubWorld.ts:72-108` | error |
| E-16 | (Town) every footprint is on land and inside the map; no two footprints overlap | E | `footprint`, `hubWorld.ts:44-56` | error |
| E-17 | **Seams** between neighbouring inside chunks are consistent | E; the converter checks it too | ENG-08 l.185-186 | warning ○ (what "consistent" means is the spike's; part 1's "one opening on every seam" was a rule of generation and is replaced) |
| E-19 | A spawn point carries a template id that is not 0 | E | ENG-08 l.159, l.177-178 | error |

R-4, R-6, R-8 and R-9 of part 1 are no longer in the table:

- **R-4** (sequential ids, `last_id + 1`) and **R-6** (a `LOCATION` is registered before its `OUTLINE` and
  `QUOTAS`) are the registration's write order, not a content check of a map. The editor cannot read
  `last_id`: its export names the gates and destinations and the converter resolves registry ids from a
  content manifest (ENG-08 l.217-218), and the order of writes is ENG-08's (l.170). Both wait for the
  spike's schema (○). The editor shows no finding for them.
- **R-8** (a record has exactly `parts(kind)` felts, `LIVE` in part 0) is the converter's output, not a
  property of a map: the converter's.
- **R-9** (at most 15 set pieces on a location) is dropped: set pieces are not in CLI-09 (§1, O-8). The
  export covers them for dungeons (ENG-08 l.217-218), and a later lot may add a set-piece map kind.

What changed from part 1, in one list:

- **Dropped:** part 1's **E-8** (a quota has at least `count` places), replaced by **R-13**; **E-9**
  ("at most 5 goblins a pack"): a pack's goblin count is drawn at entry, not authored (D-215 ruling 4), so
  only the per-chunk limits stay (**R-15**); **E-11**'s corner walls (ruling 5, **R-16**) and its "one
  opening per seam" (replaced by **E-17**); the "floor" half of **E-4**'s and **E-5**'s gate rule (moved
  to **R-18**); R-4, R-6, R-8 and R-9 above.
- **Added:** R-11, R-12, R-13, R-14, R-15, R-16, R-17, R-18, R-20, E-17, E-19.
- **Changed severity:** E-7 from warning to error. **Settled:** E-8, E-9 and G-5's per-chunk limits are
  no longer ○.
- **Not the editor's** (ENG-08 l.181-182): a Heart template's caste minimums at least 1 (a template's
  content, which the editor does not write), and a dungeon floor's `width × height` above `N` (dungeons
  stay generated).

**Where the checks live.** The checks are code of the tool, in the editor's folder
(`client/app/src/editor/`). They are not game rules, so they are not `client/sim`'s (mandate §6).
Reachability uses the hex neighbours of today's `placeholders.ts` until CLI-02 gives `client/sim` its own.
ENG-08 asks for **one shared table of cases** that the converter and the Cairo checks both run (its AC-3,
l.299-302): when `tools/map-format/` publishes it, CLI-09c runs each case through the editor's checks
and the editor must refuse the same cases, no more and no fewer. Whether the R checks are also fed by a
vector table printed from the Cairo models stays open for the spike (G-6).

## 6. Save, load, export

- **Save** writes the map to a local file: a download of one JSON document (`<name>.grimmap.json`). It
  carries the editor's format version, the editor's version (the client's commit), the kind and
  everything in §4. **Load** reads such a file from a file picker or by dropping it on the page.
  **Format 2** (owner's request, 2026-10-05; D-216) holds the painted hexes only (row spans: one row, from a column on, a
  character per hex, a space for an unpainted one), the objects as before, the outline, and the last
  chosen chunk origin with whether it was fitted or nudged. A **format 1** file (CLI-09a, a rectangle
  of whole chunks at `(0, 0)`) opens converted: every hex painted as it was, the chunk grid at `(0, 0)`,
  with a note. Drafts the same way.
- **Drafts**: the open map is also kept in the browser's local storage after each change, so that a
  closed tab loses nothing (the pending write is flushed when the screen goes or the tab closes). This is a convenience of one browser (O-5). The map list shows the drafts
  and warns that they live in this browser only. Every read and write of the storage is guarded: the
  editor works without it.
- **Nothing on a server**: no upload, no account, no key, no Registry read, no chain call. The editor
  makes no network request but for the page's own files and `/art/`.
- **Town maps** are client data. A town file is what the game's hubs will read instead of the code
  fixtures. That move is a later lot (O-6), and it commits the town files as JSON under `client/app`.
  They are data, not art (D-73 holds: no image).
- **Zone maps** are saved the same way. They are also **exported for registration in ENG-08's format** (CLI-09c)
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

Each has a default. A lot may start on the default; a later answer reverses it.

**For the orchestrator of track CV — Decided (orchestrator, 2026-10-05), reversible:**

| # | Question | Decision |
|---|---|---|
| O-1 | How the editor is reached: its own Vite entry (`client/app/editor.html` and `src/editor/`, a second `build.rollupOptions.input`), or a query parameter of today's page (`?editor=1`, `params.ts`) | **Decided (orchestrator, 2026-10-05): its own entry**, served at `/editor.html` on the site. The game's bundle does not carry the editor, and the editor imports the game's modules. The site's deploy builds every entry of `vite build` without change; CLI-09a checks it |
| O-2 | Whether the editor is published on the public site | **Decided (orchestrator, 2026-10-05): yes**, published with **no link from the game**. It holds no secret and writes nothing anywhere |
| O-3 | Touch | **Decided (orchestrator, 2026-10-05): never in CLI-09**: no touch input, one line below 700 px. A later lot only if the owner asks |
| O-4 | Chrome: plain (`data-chrome="plain"`) or the pack's chrome (CLI-03i's `Panel`, `Button`…) | **Decided (orchestrator, 2026-10-05): plain**: a dense tool, and its panels are not the game's. The pack's chrome can be switched on later without changing the layout |
| O-5 | Drafts in the browser's local storage | **Decided (orchestrator, 2026-10-05): yes**, guarded, with the warning on the map list |
| O-6 | Town maps replace `fixtures/hubs.ts` in the game | **Decided (orchestrator, 2026-10-05): yes, in CLI-09d**, after CLI-09b: the town and the outpost redrawn in the editor, committed as JSON, read by `hubWorld`; the hub screens unchanged |
| O-7 | Undo depth | **Decided (orchestrator, 2026-10-05): 200 steps**, in memory, lost on reload (the draft keeps the map, not its history) |
| O-8 | Set pieces for dungeons (one authored chunk, ADR-0006 l.206-211) with the same canvas | **Decided (orchestrator, 2026-10-05): no set pieces** in CLI-09. ENG-08's export covers them (its deliverable 5, l.217-218), so a 1 × 1-chunk map kind can be added later |

**For track game — ENG-08's answer, where it gives one.** ENG-08's brief and D-215 answer some of these
in principle; the rest is **open, addressed to ENG-08's spike**. "ENG-08 l.N" is a line of
`docs/briefs/ENG-08-authored-zones-format.md`.

| # | Question | Answer and status |
|---|---|---|
| G-1 | Does the chain hold only floor/wall per hex, or ground too? | **Answered (D-215, ENG-08 ruling 1, l.137):** only the walkable plane is on chain; visual tile kinds, decoration and props are client-only layers, with the condition that a rule needing more than walkable becomes a reserved plane on chain. Open for the spike: which client layers the export carries and how the client matches them to the chain's terrain |
| G-2 | Is an authored zone revealed chunk by chunk, or is its terrain public? | **Answered (ENG-08 l.107-112):** an authored zone's terrain is public before any instance; the chain still reveals whole chunks; D-213 holds, so the client draws a tile only once it has entered the adventurer's sight. The preview's Fog option shows exactly that (§2.8) |
| G-3 | Which features are fixed by the author, and which are drawn among candidate places? | **Answered in part:** quotas are drawn among the author's candidates, order-free (ruling 3, l.139, D-215); objects (chest, node, terrain trap, landmark, lever) are authored within the per-chunk limit (l.159-161). **Open for the spike:** whether chests, nodes and traps are also drawn among candidates by frequency |
| G-4 | Packs: places set by the author, or drawn anywhere on floor? | **Answered (ruling 4, l.140, D-215):** authored spawn points; their level (within the zone's band) and their count are drawn at entry |
| G-5 | Do the generation rules bind an authored zone? | **Answered in part:** the corner walls are **lifted** for authored chunks if no other code reads them (ruling 5, l.141; the spike checks); ENG-05's per-chunk limits stay (l.59, l.174). **Open for the spike:** what "seams consistent" means (§5, E-17) |
| G-6 | Will game's format lot print a vector table for the packing and `assert_valid` of the zone's records? | **Answered in part:** one shared table of the checks' cases, run by the converter and the Cairo checks (ENG-08 l.174, AC-3 l.299-302). **Open for the spike:** whether the records' packing is also a vector table in `contracts/logic/vectors` |
| G-7 | Does the export carry ids, or does the pipeline allocate them? | **Answered in part:** the export names the gates and destinations, and the converter resolves registry ids from a content manifest (l.217-218). **Open for the spike:** what the editor's "Location id" field is in the file (§2.2) |
| G-8 | Does a location carry a name on chain? | **Open, addressed to ENG-08's spike** (the zone's identity fields, l.213-214). Default until then: no, names are client data |

## 9. Lots

**CLI-09a and CLI-09b start now against this brief.** CLI-09c waits for ENG-08's spike schema.

| Lot | Scope | Acceptance (one line) |
|---|---|---|
| **CLI-09a** | The page (O-1), the map list, the new map dialog, the canvas with the game's renderer, the camera, Paint, Erase, Fill, Pick, brush sizes, the layers bar, undo and redo, the outline tool, save and load of the editor's file, drafts | A 15 × 15-chunk zone is created, painted, outlined, saved, reloaded from the file and identical (a test compares the documents), and the browser check shows it at 1440 × 900 in shapes |
| **CLI-09b** | Objects (entry, gates, **candidate quota places per quota, authored spawn points with a template id**, features; a town's places, decor, props, figure spots, arrival), the inspector, Select and Move, Cut, Copy and Paste, Mirror, the validation panel with every check of §5 that does not wait for ENG-08's spike, the preview walk | Each check of §5 that is not ○ has a failing and a passing fixture map in tests; each ○ check runs as a warning with a fixture. **The fixtures carry candidate quota places** (a quota with fewer candidates than its count fails R-13) **and spawn points** (a third spawn point in one chunk fails R-15; a spawn point on a wall fails R-14). The seed's zone (`fixtures/zone.ts`), given candidate quota places and spawn points, and the town (`fixtures/hubs.ts`), redrawn in the editor, validate with no error and walk in the preview as in the game |
| **CLI-09c** (waits for ENG-08's spike) | The registration export (and its import) in ENG-08's schema, built against `spikes/SPK-16-authored-zone/map-format/` and then `tools/map-format/` (§10); the editor's checks run against the shared table of cases; the ○ checks settled | ENG-08's sample zone, loaded in the editor, validates and exports to what the converter takes; the converter's output for it equals the golden file of ENG-08's spike; every case of the shared table is refused or accepted by the editor's checks as the converter does |
| **CLI-09a2** (owner's request, 2026-10-05; D-216) | The unbounded canvas: sparse painted hexes, no size in the new map dialog, "Fit chunks" (the origin with the fewest chunks, then the fewest partly filled, the rows' parity kept) and its nudge, format 2 with format 1 converted on load; CLI-09a's three deferred minors | A shape painted away from the origin is fitted, nudged, saved, reloaded and identical (a test compares the documents; the browser check at 1440 × 900); the fit's cases computed by hand pass; the fit of a 225 × 225 painted map is measured well under a second |
| CLI-09d (O-6) | The game's hubs read town files made by the editor instead of `fixtures/hubs.ts` | The hub screens' existing tests and browser checks pass unchanged on the town and outpost files |

CLI-09a and CLI-09b do not wait for track game: they use the editor's own file (§6), not ENG-08's
schema. CLI-09c waits for ENG-08's spike (its schema, converter and samples) and ENG-09's promotion of
them to `tools/map-format/` (ENG-08 ruling 9, l.145).

## 10. Export format — ENG-08's, folded in

`docs/briefs/ENG-08-authored-zones-format.md` fixes the format's design and D-215 answers its first
questions. **The exact JSON schema waits for ENG-08's spike. CLI-09c waits for it.** What is fixed now,
in words:

- **What is registered.** A zone's registration is a set of Registry records written by the
  administrator through the content pipeline (OPS-01), one `set_record` per record, with no batched
  entrypoint (ENG-08 ruling 10, l.146). The records are:
  - `LOCATION` (kind 2, sequential): kind, region, biome, level band, rank, width and height in chunks,
    `N` (0 for a zone), spawn table, entry chunk and tile (`models/index.cairo:36-71`,
    `location.cairo:120-142`), plus **a marker that tells an authored zone from a generated one**
    (ruling 7, l.143: the generated path stays as the fallback until every zone is authored);
  - `OUTLINE` (kind 3, composite): **the chunk set and the tile masks of the border chunks only**, as
    today (ruling 6, l.142). The converter derives the masks from the authored walls and refuses a mask
    that disagrees;
  - `GATE` (kind 4, sequential): source anchor chunk and tile, destination entry, kind, rank, quest
    (`models/index.cairo:73-92`);
  - `QUOTAS` (kind 5): up to 6 quotas of kind, parameter and count (ENG-08 l.55), with ENG-08's bound that
    a count is at most the authored candidates (§5, R-13);
  - **a record per authored chunk**: a new kind, or an extension of `SET_PIECE` or `OUTLINE`, composite
    and keyed by the location and the chunk. Its content, in ENG-08's words (deliverable 1, l.151-169):
    **the walkable plane only**, 225 bits, 1 = wall, `LIVE` in the part 0 word; **authored spawn points**
    (tile and template); **objects** (chest, node, terrain trap, landmark, lever) within the per-chunk
    limit; **candidate quota places** per quota; and how a chunk names the gates it anchors. How many
    felts a chunk takes, its bit layout and its parts are the spike's measure.
- **What is on chain and what stays client-side** (ruling 1, D-215). **On chain:** the walkable plane, the
  authored spawn points, objects and candidate quota places, the entry and the gate points, the outline.
  **Client-only layers:** visual tile kinds (ground), obstacle looks, decoration and props. A **town** is
  the same file with `kind` town: everything client-only (D-03, D-202), and the converter emits no town
  terrain. A rule that needs more than walkable (sight that differs from walking, for example water)
  becomes a reserved plane on chain, by a format version, never a client guess (ruling 1's condition).
- **What is drawn at entry, not authored** (rulings 3 and 4): which candidate serves each quota, and each
  spawn point's level (within the zone's band) and the pack's goblin count. The preview walk shows
  markers, not draws (§2.8).
- **The shape of the file** (ENG-08 deliverable 5, l.209-222): versioned (a `format` name and an integer
  `version`), with a JSON Schema and a converter (JSON to the on-chain records, and to the seed's rows).
  It covers the zone's identity and `LOCATION` fields, the chunk set, the tiles in **global coordinates
  with the hex layout pinned** (pointy or flat, the row-offset parity of ADR-0006 §4, `15 cy + cx`,
  `15 row + column`), the walkable layer and the client-only layers, spawn points, objects, candidate
  quota places, entry and gates **by name** (the converter resolves registry ids from a content
  manifest), set pieces for dungeons, and towns. The converter refuses exactly what §5's R checks refuse
  and checks the pipeline's rules (reachability, seams) itself.
- **`tools/map-format/` is the shared folder** (ruling 9, l.145; D-215). **Track game owns the schema and
  the converter; track CV consumes them** for the editor. ENG-08's spike writes them under
  `spikes/SPK-16-authored-zone/map-format/` (the schema, the converter in Python 3 with the standard
  library, its tests and the samples of a zone, a town and a set piece), and ENG-09 promotes them to
  `tools/map-format/`. **CLI-09 never edits the schema or the converter**: a change it needs goes to
  track game. The editor builds against the files and the samples there.
- **The editor's own file stays its own** (§6, `.grimmap.json`): it holds what an editor session needs
  (the kind, the size, every layer, undo-free drafts), and the registration export is derived from it by
  CLI-09c, to ENG-08's schema.

**Waits for ENG-08's spike (○), to settle in CLI-09c:** the JSON schema and the layers it carries beyond
the walkable plane (G-1); what the editor's "Location id" is in the file (G-7); the chunk record's
shape, parts and bit layout; whether chests, nodes and traps are also drawn among candidates (G-3); what
"members" counts in R-12 and whether a candidate counts against a chunk's three objects (R-15);
what "seams consistent" means (E-17); the order of registration; whether the editor receives a content
manifest to check spawn-point templates (R-17); whether a location carries a name (G-8); whether the
packing is also a vector table (G-6). The client's seed (`fixtures/region.ts`: `SEED_LOCATIONS`,
`SEED_GATES`, `SEED_OUTLINES`) and `contracts/seed` hold today's example of a zone's records;
ENG-08's samples and golden file are CLI-09c's test.
