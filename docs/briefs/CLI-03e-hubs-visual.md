# CLI-03e — The hubs at the expected visual level, with the real assets

**Status: starts when CLI-03d is merged** (both lots touch the hubs). Branch from `main` after that
merge.

Written for the orchestrator of track CV on 2026-10-02, from **D-196** (the owner, through the
project manager): the hubs drawn by CLI-03c are "not at all at the expected level"; the hex-map
mechanics stay, client-side; the placeholder buildings are replaced by the real assets. CLI-03d keeps
the mechanics; this lot brings the picture to the expected level.

## Agent

Profile: `impl-opus` (visual work with design judgement: composition, scale, depth, readability, and
a pipeline change in `tools/art`). Branch: `cv/cli-03e-hubs-visual`. Machine: **the VPS** (see
*Machine*). No pin is generated or committed (see *Fingerprints*).

## Goal

After this task the town and the outpost look like places of the game, built from the art pack, at
one scale with the instances:

1. Every building on a hub is a building of the pack, at its native size; no placeholder shape is
   left when the atlas is present.
2. The buildings stand on a ground made of the pack's terrain, among props (trees, bushes, rocks,
   stumps), on the instance's hex grid.
3. The present adventurers are drawn at the same scale as in a room.
4. Each hub reads clearly on a 375-point-wide phone and on a desktop window.

**The mechanics do not change**: the screens, the intents, the state machine, the arrival rule and
the five design/11 points as CLI-03d leaves them.

## Context

- **D-196** (above) and the owner's own reading of CLI-03c. CLI-03c's brief
  `docs/briefs/CLI-03c-hubs.md` (the loop, the screens, the intents) and CLI-03d's brief
  `docs/briefs/CLI-03d-hubs-followup.md` (the arrival rule, the owner's choices). design/11 *Hubs*
  as CLI-03d leaves it.
- **The mandate** `docs/briefs/ORCH-client-visual.md`:
  - §1 for what the track writes;
  - §4 (D-73) for the art;
  - §6, binding: no rule in `client/app` outside `client/app/src/sandbox/placeholders.ts`; the
    renderer's input is a view state; a tap produces an intent; rendered on demand, no render loop;
    no randomness and no clock in what `client/sim` will decide.
- **The art direction**, design/10:
  - pixel art on a 64 × 64 base tile, characters in 192 × 192 frames;
  - top-down three-quarter view;
  - `Buildings/` for the hubs, Pawn as a possible hub figure;
  - sprites face right and are mirrored;
  - one continuous textured ground per biome, obstacles as objects from `Terrain/Decorations`.
- design/11:
  - I-1 (portrait, one thumb);
  - I-6 (targets at least 40 points);
  - I-7 (the screen is still between two actions, idle animations apart);
  - *Desktop* (the portrait column in the centre);
  - *Accessibility* (colour never the only carrier).
- **What the hubs draw today on `main`**:
  - `client/app/src/render/hubRenderer.ts` and `render/hubView.ts`, `input/hubTaps.ts`,
    `sandbox/fixtures/hubs.ts`, `sandbox/loop/HubScreen.tsx`.
  - The ground is a flat green rectangle with a road.
  - Each building is either the pack's still or a drawn shape. A still is **scaled to its
    footprint's width**, so every building has its own factor (the castle at about 0.4, the houses at
    about 0.44), none of them integer.
  - The whole illustration (360 × 300 units for the town) is then fitted to the middle zone.
  - The adventurers are 34 units tall (`FIGURE_HEIGHT`) where their native height is 67 to 88 px
    (`tools/art/README.md`, *Native heights*).
  - These mixed, non-integer, per-building scales are the main reason the picture reads as a mock-up.
- **The scale rule**: `PENDING-cv-integer-scale` was accepted as proposed. The continuous scale is
  the default; `snap` and `sharp` (`render/scaling.ts`) are one toggle away. The hub follows the same
  modes as the room; it gets no rule of its own.
- **The room's ground**: drawn by `render/renderer.ts` as shapes and baked chunk by chunk into
  textures. The pattern for drawing once and showing a texture is already there.
- **The art pipeline**, `tools/art/README.md` and `manifest.toml`:
  - strips of square cells for units;
  - `[[still]]` entries (role `building`, one image, native size, anchored at its base);
  - the eight Blue buildings listed;
  - the PixiJS check;
  - the tests on synthetic images.
  - The client loads every page `sprites.json` lists (`render/atlas.ts`).
- **The pack**:
  - It is the `assets` repository, on this VPS at `/home/claude/projects/assets` (read-only) and on
    the Mac. Its `README.md` says it holds the *Tiny Swords* pack, sprites derived from it and
    **buildings commissioned by the owner**.
  - It has no other guide (the only further documents are those of the generated goblin sheets).
  - What the hubs can use, by folder (sizes are pixel sizes, measured on the VPS with the files'
    headers):
    - `Buildings/{Blue,Red,Yellow,Purple,Black} Buildings/`: eight buildings per colour, from 128 ×
      192 (the three houses) to 320 × 256 (the castle) and 192 × 320 (the monastery).
    - `Buildings/Others/`: thirty-four single buildings, 128 px wide and 256 px tall (three of
      them 320 tall).
      - Their names map naturally onto services and town life: a forge, a market hall, an inn, a
        tavern, a church, a cloister, a fortress, a watchtower, a barn, a silo, a stable, cottages,
        huts, mills, bridges, and others.
      - These are presumably the owner's commissioned buildings ("assets planned for that",
        D-196). The pack's README does not say which files they are: see *Open questions*.
    - `Terrain/Tileset/`: five colour variants of a square autotile of 64 px cells (9 × 6 cells per
      sheet: grass, edges, cliffs), a water background, a water-foam strip and a shadow image.
    - `Terrain/Decorations/`:
      - bushes (strips of 8 square cells of 128 px);
      - rocks (single 64 × 64 images);
      - rocks in water;
      - clouds;
      - a rubber duck (an easter egg of the pack, not for the hubs).
    - `Terrain/Resources/`: trees (strips of 8 cells of 192 × 256 or 192 × 192, cells **not
      square**), stumps (single 192 × 256 images), sheep (strips), gold stones, tools.
    - `UI Elements/`: banners, ribbons in five colours, bars, buttons, cursors, avatars, papers,
      wood and stone plates.
    - `Units/` (Pawn in each colour) and `Characters/` (four worker figures with idle, run and
      hammer strips): possible hub figures beyond the present adventurers.
  - Name these by path; never copy, reproduce or describe them beyond words (D-73).

## The target level

"Expected level" means the following, each checkable by a reviewer on the screenshots and by the
owner on the dev server. Where a choice is aesthetic, the thread proposes, writes it as a constant or
a fixture value, and leaves it to the owner's eye.

### 1. One scale, the instance's

- The hub is composed in **art pixels at scale 1**: every building, prop and figure at its native
  size, none resampled, none scaled on its own.
- The whole scene is then drawn with **one** factor, chosen by the same scale modes as the room
  (`continuous` by default, `snap` and `sharp` honoured, `render/scaling.ts`).
- Per-building scaling to a footprint is removed.
- A building's footprint, its tap target and its label come from its native size: written in the
  fixture as numbers, which D-73 allows.
- An adventurer in a hub is as tall on screen as the same adventurer in a room at the same zoom.
- **Width budget**: a hub's illustration is at most **750 art pixels wide** (about 11 hex columns of
  64 px). On a 375-point phone at a device pixel ratio of 2 the factor is then about 0.5 point per
  art pixel, that is one device pixel per art pixel in `snap`. The height follows the composition;
  the middle zone fits it by width.
- On desktop the portrait column of design/11 *Desktop* keeps the same composition, at the larger
  factor the column allows.

### 2. On the hex grid

- The hub is laid out on the **instance's pointy-top hex grid** (`input/coords.ts`: `TILE_WIDTH` 64,
  the room's conventions).
  - Every building stands with the middle of its base on the centre of one hex, its **anchor tile**
    (its door).
  - Every prop stands on a hex.
  - Every adventurer stands on a hex, where a room puts its feet (`render/renderer.ts`, the feet's
    offset in the tile).
- The fixtures give positions **as hex coordinates**, not as free units. The renderer converts them
  with the room's own functions.
- No hex outline is drawn in a hub by default: the grid places things, it is not shown. Showing a
  faint grid is a constant, for the owner's eye.
- This keeps the hubs at the instances' scale. If the owner wants to walk the hub (see *Open
  questions*), a later lot adds movement without moving a building.
- **No movement is added here**: taps on buildings and services stay the only inputs, as CLI-03d
  leaves them.

### 3. Buildings from the pack

- Every place of the town and the outpost is drawn from a `[[still]]` of the atlas.
- The mapping of service to building is one table, in `sandbox/fixtures/hubs.ts`, mirrored in
  `tools/art/README.md`. Proposed default, for the owner's eye:

  | Place | Town | Outpost |
  |---|---|---|
  | Guild | Blue castle | `Others/Fortress` |
  | Trainer | Blue barracks | Blue barracks |
  | Enchanter | Blue tower | — |
  | Smith | `Others/Forge` | — |
  | Armorer | Blue archery | — |
  | Alchemist | `Others/Cloister` (or the Blue monastery) | — |
  | Market | `Others/Market_Hall` | — |
  | Vault | `Others/Grain_Silo` (or a Blue house) | `Others/Barn` |
  | Gate | `Others/Watchtower` beside the road's end | `Others/Watchtower` |

  The outpost's column follows `OUTPOST_SERVICES` as CLI-03d leaves it: a service added there gets a
  building here.
- **Life around the services**: a few buildings that are not places to tap, so the town reads as a
  town.
  - Town: an inn or a tavern, two or three houses, a windmill or a well-placed stable.
  - Outpost: a hut or two, a palisade's worth of props.
  - They have no tap target and no label. A test asserts that no tap reaches them.
- **Colours**: one colour set for the coloured buildings (Blue, as CLI-03c chose, until the owner
  picks).
- **Style**: whether `Others/` and the coloured sets sit well together is judged by eye on the
  screenshots. If they clash, the thread proposes the set that holds together and says why in the
  report.
- The labelled shapes stay **only** as the fallback without an atlas (CI, a checkout without the
  pack). Every test passes without the pack.

### 4. Ground and props

- **The ground**: grass from one colour variant of `Terrain/Tileset/` (proposed: the first; the
  owner's eye).
  - It fills the illustration; its edges are the tileset's own edge cells, not a hard rectangle.
  - A path from the front of the scene to the Gate and between the buildings' doors. If the tileset
    has no path cell, the path is the tileset's sand or flat variant, or it is left out; the
    thread's proposal, for the owner's eye.
  - Water and cliffs are optional dressing, at the thread's judgement, never under a tap target.
- **Baking**: the ground is drawn **once** per hub and per size into one texture, as the room bakes
  its chunks, so that a frame is one sprite for the ground.
- **Props**: trees, stumps, bushes, rocks and, if they help, sheep. Placed on hexes, never covering
  a building's door or a label, never overlapping a tap target in a way that hides the building.
- **No idle animation in a hub** (CLI-03c/03d: a hub draws nothing between taps). An animated
  strip (a tree, a bush, a sheep) is drawn at one frame. Animating them is a later choice for the
  owner, since I-7 allows idle animations and the motion setting can turn them off.

### 5. Depth and layering

- Everything that stands (buildings, props, figures) is drawn in one layer **sorted by the y of its
  base**, then by a stable id. A figure in front of a house covers it; a figure behind is covered.
- Ground first, then that layer, then the labels and the selection outline on top.
- Shadows: the pack's buildings and props carry the shading they have. No drop shadow is added
  unless the thread shows it reads better, as one constant.

### 6. Readability at 375 points

- Every tap target is at least 40 points on its smaller side at 375 × 812 (I-6), measured on the
  drawn building at the chosen factor.
- No two tap targets overlap. The existing overlap test is kept and runs on the new fixtures at 375
  × 812.
- Every place carries a **label** readable at 375 points: the service's name on a plate under or
  over the building, at least the size of the page's body text, with contrast that holds on grass.
  - The plate may be drawn with a pack UI element only if *Open questions* §3 says so; otherwise it
    is a plain plate of the page.
  - A label never covers another building's door.
- The Gate is recognisable without its label: by its building and by its place at the path's end.
- The service row under the illustration is unchanged in content and order (design/11's sketch).

## Scope

- **In**:
  1. The hub composition (§1–§6 above) for the town and the outpost: `render/hubView.ts`,
     `render/hubRenderer.ts`, `input/hubTaps.ts`, `sandbox/fixtures/hubs.ts`, and the hub screen's
     layout in `sandbox/loop/HubScreen.tsx` where the labels need it.
  2. **The atlas pipeline** (`tools/art`):
     - New `[[still]]` entries for every building the fixtures name.
     - **A still taken from one cell of a strip**: an optional frame index and a cell size that may
       be non-square (the trees' cells are 192 × 256), so trees, bushes and sheep can be drawn at
       one frame. Anchored at the base, as a still is.
     - **Props** as stills with their own role (`role = "prop"`), so `sprites.json` tells props
       from buildings.
     - **Terrain cells**: a tileset entry that cuts named 64 × 64 cells of a `Terrain/Tileset/`
       sheet.
       - Packed **untrimmed**, at native size, anchored at their top-left corner.
       - Their edge pixels extruded into the gutter, so a cell drawn next to another shows no seam
         when the scene is scaled.
       - A role `tile`.
     - The checks extended to the new roles: frames inside pages, none overlapping; the baseline of
       a still or prop read back from the written PNG; a tile's cell exactly 64 × 64.
     - Every new behaviour tested on **synthetic images**, as the existing tests do. The CLI-03d
       test (strips' frames identical with and without stills) is extended: identical with and
       without props and tiles.
     - The README's sections *Buildings* and *The manifest* updated: the new roles, how to add one,
       the mapping of places to buildings.
     - A **pack path override** if the thread's worktree cannot fetch the submodule: an environment
       variable (for example `GRIMWORLD_ASSETS`) read by `build.py` in place of `assets/`, named in
       the README. Add it only if `git submodule update --init assets` is refused in the worktree;
       say which in the report.
  3. The hub's renderer draws the baked ground, the sorted layer and the labels, on demand.
     - The CLI-03c test "nothing is drawn on a hub screen once input stops" stays green.
  4. Tests:
     - The hex positions of the fixtures. No two places share an anchor tile; no prop stands on an
       anchor tile or on the path to the Gate.
     - The sort order of the standing layer.
     - The tap targets: at least 40 points, no overlap, at 375 × 812 and a desktop window.
     - No tap reaches a decor building or a prop.
     - The fallback with no atlas: every place drawn as a labelled shape at its footprint.
     - Every intent unchanged: the CLI-03c/03d hub tests pass unmodified, except those that assert
       coordinates, which are updated to the new fixtures and named in the report.
- **Out**:
  - Any mechanics change:
    - no walking in a hub;
    - no new screen, intent or state of the machine;
    - no change to the arrival rule;
    - no change to the five design/11 points' behaviour.
  - Any rule, the chain, accounts (`client/app/src/account/**`, `client/app/src/chain.ts`),
    `client/sim`, `contracts/`.
  - The room's rendering (`render/renderer.ts` is read, not changed; a shared helper may be
    extracted from it only if the room's tests pass unmodified).
  - The service screens (CLI-06, CLI-07), the world map (CLI-08).
  - Idle animations in hubs.
  - The pack's UI elements for the page's chrome (title bar, service row, buttons), unless *Open
    questions* §3 brings them in.
  - design/10 and the rest of `docs/design/`: they belong to the game's design. The mapping lives in
    the fixtures and in `tools/art/README.md`.
- **Allowlist**:
  - `client/app/**` except `client/app/src/account/**`, `client/app/src/chain.ts` and their tests.
  - `client/app/package.json` and `pnpm-lock.yaml`: no addition is expected. `playwright-core` is
    already a development dependency of `client/app` if CLI-03d committed its check. Any addition is
    named in the pull request and is an escalation to the orchestrator before it is pushed.
  - `tools/art/**`: the manifest, `artpipe/`, `build.py`, the tests, the README (the *Same output on
    every machine* section only as *Fingerprints* allows).
  - `docs/reports/` for this lot's report.
  - `docs/design/11-interface.md` *Hubs*: **not** in the allowlist by default.
    - If the composition changes a fact one of its lines states (for example where the buildings
      stand), the thread keeps the line's arrangement (Guild at the back, crafts along the path,
      Vault and Gate in front) and writes nothing there.
    - A change the owner asks for later goes through the lending of D-178, extended by the project
      manager.
  - Anything else is an escalation.

## Interfaces

- **Intents**: unchanged (`open service s`, `open gate screen`, `enter gate g`, `leave`,
  `travel back`, `close report`, `inspect adventurer a`).
- **`HubView`** (`render/hubView.ts`) stays the hub renderer's only input. Expected changes, all
  data:
  - places, props and figures positioned by **hex coordinates**;
  - a place's `building` names an atlas still;
  - a place's footprint in art pixels (its native size);
  - a list of **props** (still name, hex, no target);
  - a list of **decor buildings** (still name, hex, no target);
  - the **ground**: the tileset cells and their hexes or a small grid of cells, as data.

  The hub tests and `imports.test.ts` keep guarding that the hub modules hold no rule.
- **`sprites.json`**: new roles `prop` and `tile` beside `building`. A consumer that knows only
  `building` keeps working: the client ignores a role it does not draw.
- **The atlas pages**: more than one page is allowed (the client already loads every page listed).
  A sprite never straddles two pages.

## Fingerprints

- Adding entries to `manifest.toml` changes the `out/` fingerprints. The README records those of
  `4c2b25c`'s manifest (ART-02's measure); they stay as a dated record and are **not** rewritten by
  this lot.
- The thread adds one line under them: they are the fingerprints of that manifest, and a later
  manifest has others.
- **No fingerprint, hash or byte count of the new atlas is committed by this lot.** The programme's
  rule (pins generated and checked on Linux only, VPS or CI) would allow a VPS measurement. The
  orchestrator decides whether a new record is wanted (*Open questions* §5).
- The tests assert rectangles, roles, anchors and counts computed from synthetic images, never PNG
  bytes.

## Machine

- **The VPS**:
  - The pack is on this machine (`/home/claude/projects/assets`), the build of `tools/art` runs
    there (Python 3.12, `tools/art/README.md`).
  - A headless Chromium for Playwright is installed (`~/.cache/ms-playwright/chromium-1243` and the
    headless shell, measured on 2026-10-02).
  - The screenshots and the owner's later look need no other machine.
- In the thread's worktree:
  - Get the pack with `git submodule update --init assets`; if that is refused, use the override of
    Scope In 2.
  - Build with `tools/art/build.py`.
  - Serve with `pnpm --filter @grimworld/app dev` (it serves `tools/art/out/` at `/art/`, or
    `GRIMWORLD_ART_OUT`).
- **The Mac is not needed.** If the owner looks on the Mac, the README's recipe (*Buildings*) builds
  the atlas there, never committed.

## Acceptance criteria

- [ ] AC-1 **One scale**:
      - with the atlas, no building, prop or figure is scaled on its own (a test on the renderer: one
        scale on the scene, every child at 1 or −1 for a mirror);
      - an adventurer in a hub and in a room have the same height on screen at the same factor (a
        test);
      - the town and the outpost are at most 750 art pixels wide (a test on the fixtures).
- [ ] AC-2 **Hex grid**:
      - every place, decor building, prop and figure stands on a hex centre of the room's grid (a
        test using the room's conversion);
      - no two places share an anchor tile;
      - no prop stands on an anchor tile or on the path.
- [ ] AC-3 **Buildings from the pack**:
      - every place's `building` names a `[[still]]` of `manifest.toml` (a test reads the manifest);
      - with the atlas built on the VPS, the town and the outpost show no placeholder shape (checked
        on the screenshots, stated in the report);
      - without the atlas, every place is a labelled shape and every test passes.
- [ ] AC-4 **Ground and props**:
      - the ground is drawn from tileset cells and baked once per hub and size (a test counts the
        bakes);
      - props are drawn at one frame;
      - nothing is drawn once input stops (the CLI-03c on-demand test, unchanged, green).
- [ ] AC-5 **Depth**: the standing layer is sorted by base y then id (a unit test with a figure in
      front of and behind a building).
- [ ] AC-6 **Readability**:
      - at 375 × 812 and at a desktop window, every tap target is at least 40 points on its smaller
        side and none overlap (tests);
      - no tap reaches a decor building or a prop (a test);
      - every place has a label (a test).
- [ ] AC-7 **Mechanics unchanged**:
      - the CLI-03c and CLI-03d tests of the machine, the intents, the Gate screen, the reports and
        the arrival rule pass unmodified;
      - the hub tests that assert coordinates are updated and listed in the report;
      - `imports.test.ts` is green.
- [ ] AC-8 **`tools/art`**:
      - stills from a strip's cell (non-square cell included), props and tiles are packed (tests on
        synthetic images: a tile's cell is 64 × 64 and untrimmed, its gutter extruded, a prop's
        baseline read back);
      - strips' frames are identical with and without the new entries;
      - `tools/art/build.py --check` passes on the VPS with the pack (the real output in the report:
        the tables, without the fingerprints if *Fingerprints* says so);
      - the README says how to add each role.
- [ ] AC-9 **Screenshots** (the thread checks them, nobody else receives them):
      - each hub (town, outpost) at **375 × 812** and at a **desktop window** (1440 × 900), with the
        atlas, through headless Chromium on the VPS (the CLI-03d check script, extended to take the
        four shots);
      - kept **untracked** in the thread's library folder on the VPS (`.herdr-project/<thread>/library/`,
        excluded from git), never committed, attached or posted (D-73);
      - the report describes each in words against §1–§6 of *The target level*, and says where the
        files are.
- [ ] AC-10 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `prettier --check client indexer`, the art pipeline's tests and `scripts/prepush.sh` if it
      exists: pass. CI green.
- [ ] AC-11 **The owner's eye, last**:
      - on the dev server (`pnpm --filter @grimworld/app dev`, then `/?hub=town` and `/?hub=outpost`),
        with the atlas built from this branch;
      - requested by the orchestrator through the project manager once AC-1 to AC-10 hold;
      - the owner's answer (accepted, or what to change) is recorded in the pull request.
      - A change asked for is a constant or a fixture value: a fix loop of this lot. A change of
        mechanics is a new lot.

## Review

- By a model other than the implementer, on the pull request's head: `review` (Sonnet) if the
  implementer is Opus, as recommended; `review-opus` if Sonnet.
- The reviewer works from the diff and the tests. It does not need the pack: D-73 keeps the
  screenshots on the VPS, and the owner's eye is the visual verdict.
- **Audit: none** (D-177: the owner sees the lot), unless the thread adds a dependency or touches a
  path outside the allowlist; then the orchestrator decides.

## Rules of this run

- Nothing of the pack leaves the VPS pack folder, the worktree's ignored `assets/` and
  `tools/art/out/`, or the thread's library folder (D-73):
  - no image, atlas or screenshot in a commit, the pull request, an issue, a comment or the
    report;
  - sizes, counts and file paths are fine;
  - a description in words is fine.
- Pins on Linux only; this lot commits none.
- Start and stop the dev server inside one foreground command and kill only its recorded process
  group.
- Foreground only. Wait for CI in the foreground. Never merge unless prompted with the exact line.
- Pull request: title `[<model>] CLI-03e hubs with the real assets`. The body:
  - lists the place → building table as built;
  - names every dependency added (none expected);
  - says "Audit: none (D-177)" and "Owner's eye: requested through the project manager".

## Report

`REPORT.md` as in `docs/briefs/COMMON.md` §7:
- the summary and the pull request's URL;
- the files changed;
- the place → building table and the props used (by pack path);
- the scale reached at 375 points (art pixels per point, and device pixels per art pixel in `snap`
  at a device pixel ratio of 2 and 3);
- the `tools/art` build's real output;
- the screenshots' paths on the VPS and their description;
- the hub tests whose coordinates changed;
- the commands refused by the profile;
- deviations, escalations, open questions.

## Open questions

1. **For the owner, through the project manager: does "keep the hex-map mechanics" mean walking the
   hub?**
   - Today a hub is a screen of buildings to tap (design/11: "Hubs have no geometry", D-03); there
     is no hex map in a hub, and the hex map is the instance's. D-196 says the player's position in
     a hub "needs no on-chain verification", which reads as an adventurer walking a hub on a
     client-side hex map.
   - **This brief's default**: CLI-03e lays the hub on the instance's hex grid, at the instance's
     scale, and adds **no** movement, so a later lot can add walking without moving a building.
   - **What reverses it**: the owner says the hub is walked. Then a mechanics lot (CLI-03f: the
     adventurer on the hub's hexes, a building opened by standing on its door or by a tap) follows
     CLI-03e. design/11's "no geometry" line is the game's design document; the project manager
     routes its change.
2. **For the owner: which buildings.**
   - The pack's `README.md` says the repository holds "buildings commissioned by the owner" but not
     which files.
   - The default takes the coloured set (Blue) for the large buildings and `Buildings/Others/` for
     the trades.
   - The owner confirms which set is the "assets planned for that", the colour, and the place →
     building table; each answer is a fixture value.
3. **For the owner: the page's chrome.** Should the title bar, the labels and the service row use
   the pack's `UI Elements/` (ribbons, banners, wooden or stone plates, buttons) in this lot?
   - Default: **no** (plain page elements, labels as plain plates); the chrome is a later lot.
   - Reverse: the owner judges the hub not at the level without it.
   - Cost: a `ui` role in the pipeline and drawing it in the page, not only in the canvas.
4. **For the project manager: design/11 *Hubs*.** The default writes nothing there. If the owner,
   at AC-11, moves buildings so that the line "Where the buildings stand" no longer holds, the
   lending of D-178 needs extending to CLI-03e.
5. **For the orchestrator: a new atlas fingerprint.** The default records none. If one is wanted, it
   is measured on the VPS from this lot's manifest and written as a dated record beside ART-02's,
   with the commit and the machine.
6. **For the orchestrator: where the owner looks (AC-11).**
   - Default: the owner runs the README's recipe on the Mac (pull the branch, `tools/art/build.py`,
     `pnpm --filter @grimworld/app dev`), as for CLI-03c.
   - The alternative is the VPS dev server reached through a tunnel the owner opens. Opening a port
     or a tunnel touches the machine's security settings, which are the owner's.
