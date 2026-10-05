# CLI-09b — The map editor: objects, inspector, selection, validation, preview walk

Lot CLI-09b of `docs/briefs/CLI-09-map-editor.md` (§9), track CV, 2026-10-05. It builds on CLI-09a
(#361) and CLI-09a2 (#362): the sparse, unbounded map, "Fit chunks", file format 2.

## What exists now

- **Objects** (§4.2, §4.3; `editor/objects.ts`), each on one hex, kept in the document by an id:
  - a zone's: the **entry** (one a map: placing it again moves it); **gates** (destination location
    id, kind HUB / LINK / FLOOR / RIFT, rank, quest, entry chunk and tile in the destination);
    **candidate quota places** (each for one quota of the map's list, by its index); **features**
    (chest, gathering node, terrain trap, landmark, lever); **spawn points** (a pack template id;
    level and goblin count are drawn at entry, D-215);
  - a town's or an outpost's: **places** (a service of the hub's list or the gate, a building of
    `BUILDINGS`, depth, mirror); **decor buildings**; **props** (a still's name, mirror); **figure
    spots** (left or right); the **arrival** (one a map).
  - The map's properties gain the **quota list** (kind, parameter, count).
- **Markers** on the canvas (objects layer): a hex with one or two letters, never colour alone (`E`,
  `G1…`, `QX QH QV QC QL QS` by quota kind, `FC FN FT FL FV` by feature, `P`; a town's places by
  service `Gu Sm En Tr Ar Al Ma Va Ga`, `D`, `p`, `A`, `In`). Several objects on one hex share it.
  A marker the validation names in an error is drawn red. A town's footprints are shaded, and its
  **buildings and props are drawn by the renderer as the game draws them** (`townStructures`, the
  shape of `hubWorld`'s `structures()`).
- **Tools** (§3): **Select** `U` (a click takes the hex's last placed object, or the hex; a drag is a
  box of hexes and objects; Shift adds; dragging a selected object moves it) and **Place** `O` (the
  palette's object; the same kind on the same hex is selected instead of doubled). Right click with
  either inspects the hex. **Cut, Copy, Paste** `Ctrl/Cmd+X C V` (read by character; the paste
  follows the pointer until a click, right click or Esc cancels it). **Delete** / **Backspace**
  (objects removed, hexes unpainted). **Mirror** `H` (buildings, decor, props). **Validate** `Y`.
  **Walk** `P`. Escape ends a paste, a box or a drag, then clears the selection.
- **Row parity** (§4.1): a copy's anchor is on an even row and a paste lands on an even row, so the
  pasted shape keeps every neighbour (a test checks the six sides of each pasted hex); a group of
  objects moves by an even number of rows. One object moves freely.
- **Undo** covers everything: a step is now a list of hex, object and property changes. Placing,
  moving, pasting, deleting, mirroring and every inspector edit are one step each.
- **The palette** gains an objects group: a zone's entry, gate, one swatch per quota of the list,
  the five features, the spawn point; a town's places by service (the hub's list and the gate),
  decor, prop, figure spot, arrival.
- **The inspector** (§2.4): one object (its fields, editable in place; Delete; Mirror for the
  mirrorable); one hex (its global coordinates in the fitted map, chunk and tile indices, terrain and
  ground editable, obstacle look, inside or outside, the objects on it); a group (counts by kind,
  Delete, Mirror, Set terrain, Set ground); nothing (the map's properties: name, location id, biome,
  level band, rank, spawn table, the quota list with add and remove, the walkable share against
  design/18's range). Removing a quota removes its candidates and renumbers the later ones, in one
  step. A number is written on Enter or when the field is left.
- **Validation** (§5; `editor/validate.ts`): every check of §5 that does not wait for ENG-08's spike,
  and the ○ checks as warnings. It runs on the **fitted** map (D-216), debounced 250 ms after each
  change, and at once on `Y`. The top bar's **light** shows green ● 0, or the error and warning
  counts (amber or red). The **panel** (a drawer over the inspector's column) lists each finding with
  its severity in words, its source (R, E, ○), its check's id, its message, and **Show** (selects the
  hexes and objects at fault and pans to the first). The map list's **Problems** column shows the
  counts each draft was saved with.
- **The preview walk** (§2.8; `walkWorld.ts`, `walk.ts`, `WalkScreen.tsx`): `P` or "Walk ▸". The map
  is built as the game builds it, in the fitted map's coordinates (the best fit when none was chosen
  yet): a zone as `zoneWorld`'s instance (inside the outline its terrain and ground, the void
  outside; with the fog, every chunk but the start's unrevealed), a town as `hubWorld`'s hub
  (footprints as walls but the doors, structures, figures). The game's `SandboxSession` walks it,
  with the game's gestures (a tap walks, a press or a right click inspects, a drag pans, the wheel
  zooms) and the game's keys only (the instance's or the hub's `BINDINGS`), plus `P` to leave. The
  start is the entry or the arrival, a gate, or the selected hex. **Fog** off by default: the
  session explores and stops as on entering, and only what the renderer is sent shows every tile.
  The panels fold to a bar above and below the canvas. Leaving gives back the same camera and
  selection; the walk changes nothing in the map.
- **Files** stay **format 2** (§6, as the task asks): the map's `quotas` and a list `objects`
  (`{ kind, x, y, …fields }`, in the order they were placed) are added; a file without them (CLI-09a2's)
  opens with none. An object of the other kind of map, or unknown, is refused with its reason.
- **Fixtures** (`editor/fixtures/*.grimmap.json`, committed in format 2): the seed's zone, Town A
  and Outpost B redrawn from `fixtures/zone.ts` and `fixtures/hubs.ts` (see below).

## The checks and their fixtures (AC)

Every row has a passing map and a failing map in `src/editor/validate.test.ts`. The passing maps are
the committed fixtures (they validate with no error; the seed's zone with no finding at all); each
failing map is one of them with one change. The checks that hold by construction (R-5, R-7, R-11,
R-20) fail on a forged `Fitted` record (`checkFitted`).

| Check | Severity | Failing map |
|---|---|---|
| R-1 width and height 1–15 | error | a row of 240 floor hexes, fitted: 16 × 1 chunks |
| R-2 entry's indices below 225 | error | the entry moved one hex West of the fitted map |
| R-3 gate anchor and destination entry below 225 | error | `entryTile` 225; an anchor outside the fitted map |
| R-5 an OUTLINE id below 225 | error (construction) | chunk 230 forged into the set |
| R-7 a mask's bits below 225 | error (construction) | tile 225 forged into a mask |
| R-10 at most 6 quotas | error | 7 quotas |
| R-11 chunk set within the rectangle | error (construction) | the rectangle forged 2 chunks wide |
| R-13 a quota's count at most its candidates | error | the exit counts 3 with 2 candidates; a candidate for a quota the list does not hold |
| R-14 spawn points, features, candidates on walkable hexes | error | **a spawn point on a wall** (the task's case); a feature and a candidate on a wall |
| R-15 at most 2 spawn points and 3 features a chunk | error | **a third spawn point in chunk 16** (the task's case); 4 features in chunk 0 |
| R-16 corner tiles may be floor | no check (○, §5) | four floor corners in chunk 0: no finding, no error |
| R-18 gate anchors walkable | error | a gate anchored on a rock |
| R-20 masks agree with the map | error (construction) | a forged mask missing one tile |
| E-1 fitted, whole chunks, a town ≤ 4 × 4 | error | no origin; nothing painted; a town 5 chunks wide |
| E-2 the outline one region | error | a far inside hex apart; every hex outside |
| E-3 the outline closed | error | the void touching an inside floor hex (a ring hex unpainted) |
| E-4 exactly one entry, floor inside | error | none; two; one on a rock |
| E-5 gate anchors on the outline's border | error | the client's own anchor of gate 102, (40, 7) |
| E-6 gate anchors and candidates reachable | error | a candidate walled in |
| E-7 no sealed pocket | error | a floor hex walled in |
| E-10 features, spawns, candidates inside | error | a chest on a painted floor hex outside the outline |
| E-12 ground agrees with terrain | warning | water on a floor hex, earth on a wall |
| E-13 walkable share in the biome's range | hint | the seed's meadow called a ruin |
| E-14 one place per service, one gate | error (a service not of the hub: warning) | the market removed; two gates; a smith in the outpost |
| E-15 doors and arrival floor; doors reachable | error | the arrival on the water; the guild's door walled in; no arrival |
| E-16 footprints on land and apart | error | the windmill moved onto the castle; a hut on the water |
| E-19 a spawn point's template not 0 | error | a spawn point with template 0 |
| R-12 ○ a quota's count at most the zone's members | warning | a count of 5000 |
| R-15 ○ a candidate counted as an object | warning | 2 features and 2 candidates in one chunk |
| E-17 ○ seams consistent | warning | chunks 15 and 16 with no walkable crossing on their seam |

R-17 (a template named by the location's content) is the pipeline's against a content manifest (○);
the editor checks only E-19, as §5 says.

## The redrawn fixtures (AC)

`src/editor/fixtures.test.ts` builds each document from the game's fixture and checks that the
committed file holds it, reads back to it, and validates with no error.

- **The seed's zone** (`seed-zone.grimmap.json`): location 2, meadow, levels 1–3; its terrain and
  ground as `zoneWorld` makes them (the rocks' pattern); the outline from the seed's `OUTLINE`
  records; the outside painted as the void's water, with **one ring of it around the rectangle** so
  that the outline is closed (E-3); the entry (chunk 0, tile 105); gates 2 and 102; given **an exit
  and a collector quota with two candidate places each, two spawn points** (template 1: the runts'
  pack at (21, 10), and (18, 22) in chunk 16) and a chest. Fit chunks finds the seed's own grid:
  origin (0, 0), 3 × 2, chunk set {0, 1, 2, 15, 16}, masks on 2 and 16.
- **Town A** and **Outpost B** (`town-a.grimmap.json`, `outpost-b.grimmap.json`): the island
  (`onIsland`) painted floor over the hub world's whole chunks, the water off it wall; the ground as
  `hubWorld` makes it (the path's earth); every place, decor, prop, figure and the arrival as objects.
- **"Walk in the preview as in the game"**: the preview world of the seed's zone equals `zoneWorld`'s
  terrain, ground and reveal, with the fog and without; the same taps walk the same way in both (the
  game's runts removed: the preview has no goblins). The hubs' preview worlds equal `hubWorld`'s
  terrain, ground, structures and figures; the walk to each of the town's doors arrives there in both.

**Found by the validation**: the client's fixture gate 102 (`FIXTURE_GATES`, not the seed's) anchors
at (40, 7), one hex inside the outline's border, which E-5 refuses. The redrawn zone moves it one hex
East to (41, 7), on the border; a test checks that the game's own anchor fails E-5 and nothing else.

## Acceptance, with commands

| AC | Command | Result |
|---|---|---|
| The brief's row: each non-○ check passes and fails, each ○ check warns, the fixtures validate and walk | `pnpm --filter @grimworld/app test` (`validate.test.ts`, `fixtures.test.ts`, `objects.test.ts`) | 54 files: 53 passed, 1 skipped; 611 tests passed, 1 skipped |
| The browser check at 1440 × 900, with the art and plain | `GRIMWORLD_ART_OUT=/home/claude/site/grimworld/current/art VERIFY_PORT=5287 node client/app/verify-editor.mjs` | `ALL CHECKS PASSED`, 117 checks in the two looks (the grid's phase included) |
| The grid's cost (owner's feedback) | the same script's grid phase (`VERIFY_GRID_ONLY=1` runs it alone) | below, *The grid's figures* |
| `lint`, `typecheck` | `pnpm --filter @grimworld/app lint`, `typecheck` | clean |
| The game's bundle excludes the editor | `pnpm --filter @grimworld/app build`, then the editor's strings counted in each chunk | only `assets/editor-*.js` holds them; `index.html`'s `main-*.js` and its ten preloads hold none |
| `sandbox/imports.test.ts` | in the test run | passes: no `placeholders` import, no `findPath(`, no `visited =` / `frontier` / `queue.shift(`, no find/search/route/flood function; the walk reaches the finder through the wiring (`SandboxSession`, `stepTarget`) |

The browser check, per look: the seed's zone opens from its file with the light at 0; a spawn point
without a template turns it red; `Y` lists E-19; Show selects the spawn point; the template typed in
the inspector turns it green; a node, a quota place, a gate and the entry are placed (every zone
kind); the node is selected and dragged two hexes; a box with it is copied and pasted on another row
of the same parity; the zone is walked by a tap and by the game's `D`, with the fog on, and leaving
gives the same camera back; `B` pressed while walking arms nothing. Then Town A opens with the light
at 0; a decor, a prop (mirrored with `H`), a figure spot and the arrival are placed; a second vault
turns the light red (E-14) and `Delete` fixes it; the town is walked to the market's door. No page
error, no request beyond the page's origin. Captures went to the thread's library folder only (D-73).

**The checks' time** (`validate.test.ts`, "the checks' time"): a 225 × 225 painted zone, the
largest, is validated in a median of 115–200 ms of 5 on the VPS (other work running beside it); the
seed's zone (1,504 hexes) in 3.3 ms. The first version took 415 ms on the largest map: the checks now
walk a dense grid of the painted box instead of sets of keys.

### The grid's figures (owner's feedback, 2026-10-05)

Measured by `verify-editor.mjs`'s grid phase on the VPS, headless Chromium (software rendering), with
the site's built atlas: a painted 225 × 225 zone (a rock in nine), the canvas 960 × 792 CSS px.
240 frames of panning (6 CSS px a frame), then 240 of zooming in and out by 3 % a frame, each
sequence cut at 30 s; the frame interval (`requestAnimationFrame`) and the overlay's own drawing
time (`EditorCanvas.overlayMs`). Before and after in the same session, one after the other.

| Zoom | Gesture | Before: frame | Before: overlay | After: frame | After: overlay |
|---|---|---|---|---|---|
| 258 across (the widest) | pan | 50.0 / 100.0 ms | 6.5 / 14.1 ms | 33.4 / 66.7 ms | 0.2 / 0.4 ms |
| 258 across | zoom | 66.7 / 633.3 ms | 3.1 / 7.3 ms | 66.7 / 533.3 ms | 0.1 / 0.2 ms |
| 121 across (the widest that draws the grid) | pan | **1583.2 / 2783.3 ms** (18 frames in 30 s) | **1398.7 / 1627.8 ms** | 66.6 / 100.1 ms | 0.2 / 0.6 ms |
| 121 across | zoom | 750.0 / 1499.9 ms (30 frames) | 314.3 / 847.2 ms | 66.7 / 1399.9 ms | 0.1 / 0.3 ms |

(median / p95.) The final run of the whole check, on the last commit: overlay 0.1–0.2 ms median and
1.3 ms p95 at most, frames 50–117 ms median.

- **What changed.** The grid was one path per visible hex every frame (≈ 15,000 at 121 across). It
  is now **one fill of a cached pattern**: one period of the grid (a hex wide, two rows high) drawn
  once per zoom step (its size in device pixels) and kept (48 steps at most), placed by the pattern's
  transform. The **outline's outside shading** at small hexes (below 14 CSS px) shared the cost (a
  test per visible hex, 6.5 ms at the widest zoom): it is now **one image** of the painted box, a pixel
  per half hex, rebuilt when the map changes and drawn scaled in one call. The chunk seams and the
  outline's border are precomputed segments, culled per frame: they cost a fraction of a millisecond
  and are unchanged.
- **Where the grid is skipped**: below 7 CSS px a hex (`GRID_MIN_PX`, as before), that is past about
  137 hexes across on this canvas.
- **What is left.** The frame interval while zooming keeps a p95 of 0.5–2 s at both zooms: it is not
  the overlay (0.1 ms). When a zoom crosses the edge of the view's window, the editor sends the
  renderer a new window of tiles (up to 250,000, `VIEW_MAX`) and the renderer bakes its chunks again;
  under software rendering that frame is long. Measuring and cutting it is a next step (a smaller
  window at far zooms, or the bake spread over frames, which is `render/**`'s); not done in this lot.

## Owner's feedback, 2026-10-05

1. **The grid** — done, measured above.
2. **The export is not JSON** — `docs/briefs/CLI-09-map-editor.md` §2.7, §6 and §10 say it: the
   editor's JSON (`.grimmap.json`) is its **save format only**; CLI-09c's **export** writes the
   **on-chain encoding** ENG-08 defines, packed felts as the Registry records them, as calldata or a
   multicall file ready to send; the button reads **"Export for the chain…"** with the file kind named
   in its dialog, and "Save" stays the JSON file. Each edit is marked "owner's request, 2026-10-05".
   Outside those sections, §2.3's top bar still writes "Export…" and §9's CLI-09c row "registration
   export": not edited (outside the lent sections); the next brief edit should align them. CLI-09b
   adds no export button (CLI-09c's).
3. **An open kind table for CLI-09e** — `KINDS` in `client/app/src/editor/objects.ts`, one row per
   kind; no switch over the kinds is left in the editor. **Where a new kind plugs in:**
   - **The model**: a member of the `MapObject` union and a row of `KINDS` (`map` zone or town,
     `name`, `single`, `letters`, `fields`, `create`). TypeScript refuses a kind without a row.
   - **The file**: nothing more. `objectFrom` reads any kind by its row's `fields` (a `number`, a
     `choice` with its `valid` test, a `toggle`); the writer writes every field.
   - **The palette**: `objectSwatches` in `Editor.tsx` lists what Place offers (a swatch is a
     `PlaceChoice`); CLI-09e's palette in `editor/palette/**` can hand the screen its own choices.
   - **The inspector**: nothing more. `ObjectFields` renders the row's `fields` and `note`.
   - **The drawing**: `letters` (the marker); `look` (how the renderer draws it: building or prop,
     sprite, size, shape) and `covers` (the walls it makes in the walk's world); `footprint` for a
     building (shaded on the canvas). `townStructures` and `walkWorld` read them.
   - **The validation**: the row's flags. `onWalkable` (R-14, E-10: on a walkable hex inside the
     outline), `perChunk` (R-15: counted as a spawn point, an object, or a candidate ○), `footprint`
     (E-16: on land, apart from the other buildings). A rule of its own goes in `validate.ts`
     (`zoneChecks` or `townChecks`), with a passing and a failing map in `validate.test.ts`.
   - Bridges (CLI-09f, D-217) need levels in the model and the renderer: not covered by a row alone.

## Choices made in this lot (reversible)

1. **Format 2 is kept**, extended with `quotas` and `objects` (the task says format 2). An editor of
   CLI-09a2 opening a CLI-09b file would ignore its objects; a format 3 would refuse it instead. To
   reverse: `FORMAT_VERSION` 3, format 2 read as now.
2. **E-3's "map's edge" on the unbounded plane** (D-216) is the painted hexes' edge: an inside floor
   hex with an unpainted neighbour is open, unless it is a gate anchor. The author closes the outline
   by painting the outside around it. The redrawn seed's zone carries one ring of painted void.
3. **The preview walk runs on the editor's renderer**, not a second one: two PixiJS applications on
   one page broke each other's GPU state (page errors in `GlGraphicsAdaptor.execute` and the batcher,
   seen in the browser check). The walk saves the camera, sets the game's `DEFAULT_ZOOM`, hides the
   overlays and the editor's pointer, and gives the camera back.
4. **Fog off** shows every tile by sending the renderer the session's `revealed` tiles; the walk
   itself (exploration, stops) is the game's either way.
5. **A spawn point is placed with template 0**, which E-19 refuses until the author types one: the
   editor does not guess a template.
6. **A candidate names its quota by index**; removing a quota removes its candidates and renumbers.
7. **Figure spots walk with professions in turn** (warden, vanguard, cleric, arcanist): a spot
   carries no adventurer (§4.3).
8. **A group of objects moves by an even number of rows**; one object moves freely.
9. **E-14**: a service missing or doubled is an error; a service not of the hub's list a warning.
10. **E-17 ○** is read as "two neighbouring chunks of the set have at least one walkable crossing on
    their seam", as a warning, until ENG-08's spike says what "consistent" means.
11. **The draft is written with the screen's last counts** (it does not validate a second time).

## Deviations from the task

- None of the allowlist: every change is under `client/app/src/editor/**` and
  `client/app/verify-editor.mjs`, with this report. No module of the game changed.

## Escalations

- **Pinning an obstacle's look per hex** (CLI-09a's escalation) needs the renderer change named
  there (an optional `obstacle?: string` on `ViewTile`, read by `syncObstacles` before `obstacleOf`).
  Left out, as the task decides: it is **the next renderer change** after CLI-03o part 2. The
  inspector shows the look (`auto`) read only.

## What was not checked

- A real trackpad and a real AZERTY keyboard (layouts checked on `event.code` / `event.key` in
  tests). A desktop GPU (headless Chromium renders in software).
- The registration export (CLI-09c, waits for ENG-08's spike); the ○ checks' exact rules.
- The verify script's own port: another session's server held port 5199 on the VPS at the time, so
  the runs used `VERIFY_PORT=5287`.
