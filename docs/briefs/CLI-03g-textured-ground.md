# CLI-03g — The textured ground: the pack's grass, water and earth on the hex grid, for zones and hubs

**Status: brief, waiting for CLI-03f.** The lot starts from `main` once CLI-03f (hubs as zones,
D-202; brief in #317, implementation in #319) is merged: it changes the same renderer, world and
hub fixtures. Its first lot (*Size*) is the version shown to the owner with the zone engine in the
hubs.

Written for the orchestrator of track CV on 2026-10-02, from the project manager's request: the
owner asked for the pack's assets; with CLI-03f a hub draws the zone's plain green ground and grid,
which reads as a step back from CLI-03e's tileset grass, water and earth path. design/10 asks for
"one continuous textured ground per biome, not tiled per hex". This lot gives that ground to the
zones and the hubs together, through the zone's renderer.

## Agent

Profile: `impl-opus`. The lot is rendering with pixel judgement (masks, bakes, seams at fractional
scales, the scale modes) and a measured frame budget.

Machine: **the VPS** (the Mac is unreachable). The lot commits no pin, gas table or fingerprint. The
pack is at `/home/claude/projects/assets`: link it into the worktree as `assets` by an
**uncommitted** symlink for `tools/art/build.py`, and remove the link afterwards, as CLI-03f does.
The browser check runs here in headless Chromium.

Branch: a new branch from `main` after CLI-03f's merge. One pull request per lot.

## Goal

After the first lot:

1. **One ground for every location.** The zone's renderer draws, under the grid, a continuous
   ground made of the pack's terrain: grass on land, water around it, earth on a hub's path.
2. **Exact on the hexes.** Where grass meets water or earth, the boundary follows hex edges: a hex
   the player can walk on always reads as land (design/11 I-4, "everything the rules use is
   visible").
3. **The hubs get their look back**, on the zone's engine: CLI-03e's island of grass in water and
   the town's earth path return, now drawn by the zone's renderer from the hub's world.
4. **The zone becomes an island too**: its void (outside the seed's outline, D-134) is drawn as
   water, not as grass with rocks.
5. **No slower in play.** A frame still draws one baked sprite per chunk; the extra cost is at bake
   time. Frame time at the default zoom is measured against `main` and stays within *Acceptance
   criteria* AC-8's budget.

## Context

- **design/10 *Hex grid with a square tileset*** (binding): one continuous textured ground per
  biome, not tiled per hex; a subtle hex grid on top; one obstacle object per wall tile. A true hex
  tileset belongs to the first commission.
- **D-202** and CLI-03f (#317's brief): a hub is a zone; its island, buildings and props are the
  zone's world; its ground is the zone's. CLI-03f's *Design choices* §6 and *Open questions* §2
  name this lot: "a ground layer of the zone's renderer, for zones too, never a hub-only renderer".
- **D-196**: the hubs at the expected visual level with the real assets.
- **CLI-03e** (`docs/briefs/CLI-03e-hubs-visual.md`, #307): the `tools/art` roles `prop` and `tile`;
  a tile is a 64 × 64 cell, packed untrimmed at native size, anchored top-left, its edges extruded
  into the gutter. The manifest cuts `grass_*` (the 3 × 3 flat-ground autotile of the first colour
  variant) and `water_c`. CLI-03e drew them as square cells over the hub's rectangle, edge cells on
  its border, plus soft earth hexes for the path (the tileset has no path cell). CLI-03f drops that
  drawing with `HubRenderer`; the atlas entries stay.
- **The owner's choices for the hubs** (orchestrator's decisions, 2026-10-02, reversible): Blue
  faction; path as soft earth hexes; tileset grass on an island with a water backdrop.
- **The mandate** `docs/briefs/ORCH-client-visual.md`: §4 (D-73), §6 (no rule in `client/app`
  outside `sandbox/placeholders.ts`; the renderer's input is a view state; rendered on demand).
- **D-73 and the public site**: nothing of the pack is committed; the built atlas and
  `sprites.json` are served at the public site by the owner's decision, never the raw files.
- **Phone work is suspended** (owner, 2026-10-02): mobile-first, checked in the browser at
  375 × 812 and 1440 × 900, nothing on a device.

### What main has (after CLI-03f)

| Part | Where | What it does today |
|---|---|---|
| The terrain | `sandbox/world.ts` (`Terrain`: `kinds` of `floor`, `wall`, `unrevealed`, whole 15 × 15 chunks) | The rules' kinds only; outside the rectangle is wall (D-134) |
| The view | `render/view.ts` (`ViewTile { x, y, kind }`), built by `toView` in `sandbox/wiring.ts` | No ground field |
| The bake | `render/renderer.ts` `syncChunks` / `bakeTerrain`, `render/shapes.ts` `drawTerrain` | One `Graphics` per 15 × 15 chunk (each hex filled one flat green, grown half a pixel; the grid; a rock on each wall), baked into one texture per chunk at `bakeResolution` (the camera scale × canvas resolution, stepped by √2, capped by the GPU's texture size); a chunk is redrawn when its kinds change |
| Zoom and scale | `DEFAULT_ZOOM` (13 tiles across by default, 9 close, 25 out, 4 in), `render/scaling.ts` (`continuous`, `snap`, `sharp`) | A zoom step can rebake (the √2 steps keep it rare) |
| The zone | `sandbox/fixtures/zone.ts` (`zoneWorld`, a meadow of 3 × 2 chunks) | Outside the outline is `wall`: drawn as grass with a rock |
| The hubs | CLI-03f's `hubWorld` | Island hexes `floor`, everything else `wall`; buildings and props as structures on wall hexes; CLI-03e's `ground.path` data kept or dropped by CLI-03f |

### The pack's terrain (described in words, nothing copied)

Read with the pipeline's own Python (Pillow) on `/home/claude/projects/assets/Terrain/Tileset/`:

| File | Size | What it holds |
|---|---|---|
| `Tilemap_color1.png` … `Tilemap_color5.png` | 576 × 384 each: 9 × 6 cells of 64 px | Five colour variants of one **square** autotile. Columns 0–3, rows 0–3: the **flat ground** (a 3 × 3 block of centre, edges and corners, plus one-wide strips and a single piece, by their transparency). Column 4 is empty. Columns 5–8: the same for **raised ground**, with **cliff faces** below it in rows 4–5. The variants differ only by their greens: from yellow-green (1) through bright green (3) to dry olive (4) and teal-green (5). 11 to 13 colours per sheet |
| `Water Background color.png` | 64 × 64 | **One flat colour**, fully opaque: water has no texture to tile |
| `Water Foam.png` | 3072 × 192: 16 cells of 192 × 192 | An animated foam ring, about 14 % opaque, two colours: drawn under a land tile's edge, three tiles wide |
| `Shadow.png` | 192 × 192 | A soft shadow, one colour, for raised ground |

- **No earth, sand, dirt or path cell exists** in the pack's terrain (no file of those names, and
  every tileset cell is a green). The path stays drawn, as CLI-03e drew it.
- The edge cells' outer pixels are transparent (rounded edges meant to sit over water and foam):
  the pack's shore is "grass edge over foam over water".
- **Square, not hex.** Our hex is 64 art px across (flat to flat), 73.9 tall, rows 55.4 apart
  (`input/coords.ts`). Square 64 px cells line up with hex columns on one row but not between rows
  (odd rows shift by half a tile) nor in height. A square edge cell can therefore not follow a hex
  boundary.

## Scope and non-goals

- **In** (both lots; *Size* splits them):
  1. A **ground kind per hex**, presentation only, carried by the world and the view (*Method* §3).
  2. The ground drawn from the atlas's tiles into the chunk bakes, hex-exact, for zones and hubs.
  3. The zone's void as water; the hubs' island, water and earth path through the same layers.
  4. The shore between land and water (lot 2: the pack's foam; *Method* §4).
  5. A drawn fallback with no atlas (flat colours), so tests and builds without the pack work.
  6. `tools/art`: the foam cell (lot 2), and the README's *Tiles* section.
  7. A frame-time measure in the browser check, against `main`.
- **Out (non-goals)**:
  - Any rule, seed, chain or `client/sim` change. The ground kind is never read by the rules'
    stand-ins: passability stays `TileKind`'s.
  - `sandbox/placeholders.ts` (unchanged).
  - Raised ground and cliffs (they outline square plateaus; design/10 already rules them out for
    hex walls).
  - The pack's rocks, bushes and trees on the **zone's** walls (the zone keeps `drawRock`); a hub's
    walls keep CLI-03f's structures. A later lot may give zones the pack's obstacles (*Open
    questions* §4).
  - Animated water or foam (I-7: the screen is still between two actions; the bake is static).
  - Other biomes' looks (forest, cave, ruin): the seed has one meadow and two hubs (*Open
    questions* §3).
  - A hex tileset, derived or commissioned (design/10: the first commission).
  - The client's chrome from `UI Elements/`, the keyboard, the service screens.
  - Phone builds, simulators, devices (suspended).

## The method

### 1. How square tiles become a continuous hex ground

| Option | How | For | Against |
|---|---|---|---|
| **A. Square autotile on a resampled grid** | Each 64 px square of the world takes a kind from the hex under its centre, then the pack's autotile (centre, edges, corners) picks the cell, as CLI-03e did on a rectangle | The pack's own rounded edges, as drawn by its artist | Boundaries follow squares, not hexes: a floor hex on the shore shows partly as water, a water hex partly as grass. It breaks I-4 on every coast, and the grid on top makes the mismatch visible |
| **B. Hex-masked layers of square cells** (recommended) | Per chunk, one layer per ground kind: world-aligned 64 px cells of that kind's centre tile (or its flat colour) covering the chunk, **clipped by the union of that kind's hexes**; layers in order water → (shore) → grass → earth; baked with the chunk | Continuous texture (a world-aligned grid of a seamless cell has no seam and no repetition at hex scale); boundaries exactly on hex edges; uses only the centre cell, the water and the foam; one more draw per layer at bake time, none per frame | The pack's rounded edge cells are not used: a coast is a hex zigzag. Lot 2's foam and lip soften it |
| C. Hex cells pre-composed in `tools/art` | The build cuts hex-shaped cells from the tiles and composes edge variants per neighbour mask (2⁶ per kind pair) | Hex-native look | The heaviest pipeline work; derived art the commission will replace; seams of hex sprites at fractional scales |

**Recommended: B.** It is the only option that keeps the rules readable on the ground (I-4), it
uses the pack's grass and water as they are, and it fits the renderer's existing per-chunk bake
without a new layer per frame. A replaces exactness with the pack's edges; C does the commission's
job early. **What reverses it**: the owner prefers the pack's rounded coasts to exact hexes: then A,
for the hubs' coasts only (a hub's island edge is fixture data, so an A-style coast can be checked
against its floor hexes).

### 2. Baked per chunk, not per view

- **Per chunk** (recommended, today's scheme): the ground joins the chunk's `Graphics` and its one
  texture. A frame draws one sprite per visible chunk, as now; the bake runs at load, at a reveal,
  when a chunk's kinds or grounds change, when the atlas arrives, and at a zoom step that crosses a
  √2 step of `bakeResolution`. The texture's size and count are **unchanged** (same frame
  rectangle, same resolution rule), so GPU memory does not grow; only the bake takes longer.
- **Per view** (not recommended): one texture over the viewport, rebaked when the camera moves. The
  camera follows every step (`CAMERA_MS`), so it would rebake during walks: frame spikes exactly
  where the budget matters.
- **What the budget watches**: at 375 × 812 the default zoom shows about one chunk across (13 tiles
  in a 15-tile chunk), so a few chunks are on screen; at 1440 × 900 the zoom fits by height and
  shows more. Both are estimates from the zoom rule, not measures: AC-8 measures them.
- **The D-120 window** plays no part: it bounds the chain's tick and the finder, not the drawing.
  The bake covers the location's tiles as today, whatever the window.
- **Zoom levels and scale modes**: the cells are drawn at integer world coordinates and their
  edges are extruded in the atlas (CLI-03e), so a bake at a fractional resolution (the √2 steps,
  `continuous`) shows no seam between cells; the masks are hard-edged (pixel art, no blur at the
  coast). `snap` and `sharp` change only the resolution the bake is drawn at. The browser check
  looks at the four zoom presets in each mode (AC-9).

### 3. What the world carries: a ground kind per hex

`TileKind` (`floor`, `wall`, `unrevealed`) is the rules' and stays the only thing the stand-ins
read. The ground is a second, presentation-only field:

- `GroundKind = "grass" | "water" | "earth"` in `render/view.ts`.
- `Terrain.ground?: readonly GroundKind[]` in `sandbox/world.ts`, indexed as `kinds`. Absent → every
  hex is `grass` (every existing fixture and test unchanged).
- `ViewTile.ground: GroundKind`, copied by `toView` (`sandbox/wiring.ts`) from the terrain.
- **Consistency, tested on every fixture**: a `water` hex is `wall` (water is never walked); an
  `earth` hex is `floor`; an `unrevealed` hex draws as unrevealed whatever its ground.
- **Beyond the terrain's rectangle**: the backdrop takes the look of the world's `void` ground
  (`SandboxWorld.void?: GroundKind`, default none: today's background), so an island sits in
  endless water when the camera reaches the edge.

How each world fills it (client fixtures only, no rule):

| World | `grass` | `water` | `earth` | Walls |
|---|---|---|---|---|
| The zone (`zoneWorld`) | Inside the seed's outline | Outside it (D-134's void, read from the registry's outline as `insideOutline` does) and `void: "water"` | none | Inside the outline: grass with `drawRock`, as today. On water: **no rock** (the water is the obstacle) |
| A hub (`hubWorld`) | The island's floor hexes and the hexes under its buildings and props | Every hex off the island, and `void: "water"` | The path's hexes (CLI-03e's `ground.path`, or CLI-03f's equivalent): the road from the arrival hex to the Gate and the doors | Structures stand on grass; covered walls draw no rock (CLI-03f) |

**What reverses it**: the chain one day carries a ground or a terrain type per hex (a biome
generator with water): then `toView` reads it from there, and the fixtures' fill goes.

### 4. Transitions

| Between | Lot 1 | Lot 2 |
|---|---|---|
| Grass and water | Hard hex edge, plus a thin darker **lip** stroked by shapes along the land side of every land–water hex edge (a constant colour chosen by eye, not sampled from the pack) | The pack's **foam**: one still cell of `Water Foam.png`, centred under every land hex that touches water, drawn after the water and before the grass, so the grass covers its inner part and the ring shows on the water side, as the pack composes it |
| Grass and earth | Earth hexes drawn as CLI-03e's soft earth: a brown fill at an alpha over the grass, each hex inset with rounded joins between neighbours, so the path reads as trodden ground, not tiles | Kept, tuned by the owner's eye |
| Anything and unrevealed | As today: the unrevealed fill and edge over the ground | As today |
| Beyond sight | As today: the overlay dims it | As today |

The grid is drawn on land only (grass, earth): over water it would draw hexes no one can enter.

### 5. The drawing, testable without a GPU

- A pure `groundPlan(tiles)` (a new `render/ground.ts`) returns, per chunk: the hexes of each layer,
  the square cells each layer needs (world-aligned on multiples of `TILE_WIDTH`, covering every
  hex of the layer), the lip's edges (lot 1) and the foam's centres (lot 2). Unit-tested on small
  synthetic tile lists.
- `drawTerrain` draws the plan: from the atlas's tiles when given, else flat colours (the fallback).
  It gets the ground textures as an argument; it never reads the atlas itself.
- `syncChunks`' key includes each tile's ground; the chunks are marked dirty once when the library
  arrives or goes (`setLibrary`), so the ground switches from flat colours to tiles with one rebake.
- Draw order inside a chunk: water, foam (lot 2), grass, earth, lip, grid (land only), rocks,
  unrevealed.

## The tools/art changes

- **Lot 1: none.** `grass_c` and `water_c` exist (CLI-03e). The other eight `grass_*` cells stay in
  the manifest (A's reversal would use them).
- **Lot 2**: the foam.
  - A `[[tileset]]` entry gains an optional `cell` size (default 64), so one entry cuts the first
    192 × 192 cell of `Terrain/Tileset/Water Foam.png` as `foam_c`, role `tile`, untrimmed,
    anchored top-left, edges extruded.
  - The build's check becomes "a tile's frame is exactly its entry's cell size", tested on a
    synthetic sheet (the existing 64 × 64 test unchanged).
  - The README's *Buildings, props and tiles* section: the `cell` size, `foam_c`, and which tiles
    the zone's renderer reads (`grass_c`, `water_c`, `foam_c`).
- **Fingerprints**: none committed. The manifest's change changes `out/`'s fingerprints; the README
  keeps ART-02's dated record and its CLI-03e line ("a later manifest has others").
- **D-73**: nothing of the pack in a commit, the pull request, a comment or the report; the
  symlink is never committed. The built atlas reaches the public site through its own build, by the
  owner's decision.

## Size

**Two lots.**

- **CLI-03g1 — the ground** (shown to the owner): ground kinds in the world and the view; grass and
  water layers hex-masked in the chunk bake; the zone's void as water; the hubs' island, water and
  earth path; the lip; the fallback; the frame measure. It brings back everything CLI-03e's hub
  showed (grass island, water, earth path) on the zone's engine, and gives the zone the same
  ground.
- **CLI-03g2 — the shores**: the pack's foam (`tools/art`'s `cell` size, `foam_c`), the lip retuned
  or dropped, and what the owner asks of lot 1's look that is a constant.

**Why two**: lot 1 carries the risk a reviewer must check (masks, bakes, the ground key, the
frame budget) and is enough for the owner's look at "zone engine plus the pack's ground". Lot 2 is
taste (how the coast looks), touches the art pipeline, and is better judged after the owner has
seen lot 1. One lot would delay the version the project manager wants shown by the pipeline change
and its tests. **What reverses it**: the orchestrator wants one pull request; then lot 2's items
join lot 1's allowlist unchanged.

## Allowlist

Lot 1:

- `client/app/src/render/view.ts` (`GroundKind`, `ViewTile.ground`, the view's `void`),
  `render/ground.ts` (new, the plan), `render/shapes.ts` (`drawTerrain`), `render/renderer.ts`
  (chunk key, dirty on the library, backdrop, ground textures), `render/scheduler.ts` (frame timing
  in `FrameStats` only), and their tests.
- `client/app/src/sandbox/world.ts` (`Terrain.ground`, `SandboxWorld.void`),
  `sandbox/wiring.ts` (`toView` copies the ground: nothing else), `sandbox/fixtures/zone.ts`,
  `sandbox/fixtures/hubs.ts` or CLI-03f's `hubWorld` module, `sandbox/Sandbox.tsx` (the timing as
  `data-` attributes for the check), and their tests.
- `client/app/verify-hubs.mjs` (extended), or a new `client/app/verify-ground.mjs` with one
  `scripts` line in `client/app/package.json` (no dependency).
- `docs/reports/CLI-03g1-textured-ground.md`.

Lot 2 adds: `tools/art/manifest.toml`, `tools/art/artpipe/**`, `tools/art/build.py` (the `cell`
size and its check), `tools/art/tests/**`, `tools/art/README.md` (*Buildings, props and tiles*
only), `docs/reports/CLI-03g2-shores.md`.

**Not in the allowlist**: `sandbox/placeholders.ts`, `client/sim/**`, `contracts/**`, accounts
(`client/app/src/account/**`, `client/app/src/chain.ts`), `pnpm-lock.yaml`, `.github/`,
`docs/design/**`. `sandbox/imports.test.ts`: assertions may be added, no guard loosened. Anything
else is an escalation in the report, not an edit.

## Interfaces

- `render/view.ts`: `type GroundKind = "grass" | "water" | "earth"`; `ViewTile.ground: GroundKind`;
  `ViewState.void?: GroundKind`.
- `sandbox/world.ts`: `Terrain.ground?: readonly GroundKind[]` (default all `grass`);
  `SandboxWorld.void?: GroundKind`.
- `render/ground.ts`: `groundPlan(tiles: readonly ViewTile[]): GroundPlan`, pure.
- `render/shapes.ts`: `drawTerrain(tiles, textures?: GroundTextures)`; without textures, flat
  colours.
- `render/scheduler.ts`: `FrameStats` gains the last frame's draw time in milliseconds and the last
  bake's; nothing else changes in the scheduler.
- Intents, the machine, `placeholders.ts`, `sprites.json`'s roles: unchanged (lot 2 adds the sprite
  `foam_c` of the existing role `tile`).

## Acceptance criteria (lot 1)

- [ ] AC-1 **The ground kind is presentation**: `placeholders.ts` is unchanged
      (`git diff origin/main -- client/app/src/sandbox/placeholders.ts` empty in the report); the
      imports test asserts no stand-in reads `ground`; `toView` is the only reader in `sandbox/`.
- [ ] AC-2 **The fixtures** (unit tests): in the zone, every hex outside the outline is `water` and
      `wall`, every hex inside is `grass`; in both hubs, every island hex is `grass` or `earth`,
      every other hex `water` and `wall`, every path hex `earth` and `floor`, the arrival hex and
      every door are land; no `water` hex is `floor` in any fixture.
- [ ] AC-3 **The plan** (unit tests on synthetic tiles): each layer's cells cover every hex of the
      layer and lie on multiples of `TILE_WIDTH`; the lip's edges are exactly the land–water hex
      edges; a chunk of grass only gives one layer and no lip; the grid is not planned over water;
      a wall on water plans no rock.
- [ ] AC-4 **The bake**: a chunk is redrawn when a tile's ground changes, not otherwise; the
      chunks rebake once when the library arrives; the number and size of the baked textures are
      the same as `main`'s for the same view (a test on the fake surface); drawing stays on demand
      (no frame once a walk ends).
- [ ] AC-5 **The fallback**: without an atlas, the ground draws in flat colours and every existing
      renderer test passes unmodified, or the report names each one updated and why.
- [ ] AC-6 **Mechanics unchanged**: the room's tests (`walkFollowsPreview`, `wiring`, `session`,
      `placeholders`) and CLI-03c/03d/03f's tests pass unmodified.
- [ ] AC-7 **The browser check**, on the VPS in headless Chromium, at **375 × 812** and
      **1440 × 900**, in the zone and both hubs, with the atlas built from this branch (never
      committed): the ground is drawn from the atlas's tiles (the renderer reports it); a walk;
      the camera follows; no frame once the walk ends; no page error. With `VERIFY_SHOTS=1`, a
      shot of each location at each size into the thread's library folder, **untracked**, never
      committed, attached or posted (D-73); the report describes them in words.
- [ ] AC-8 **Frame time at the default zoom**, measured in the same check, same machine and run,
      on this branch and on `origin/main` (built in a temporary worktree the thread creates and
      removes by its exact path): the median and 95th percentile of the draw time over a 10-step
      walk in the zone, at both sizes, and the bake time of one chunk. **Budget**: median within
      +10 % of `main`'s, 95th percentile within +25 %; a chunk's bake is reported, with no budget
      on it in lot 1 (it happens at load, a reveal and a zoom step, never per frame). Headless
      Chromium on the VPS renders in software: the figures are relative, and the report says so.
- [ ] AC-9 **Zoom and scale modes**: at the four zoom presets and in `continuous`, `snap` and
      `sharp`, no seam between cells and no gap between layers in the shots (checked by eye by the
      thread, described in the report; the reviewer checks the extrusion and the integer
      coordinates in the code).
- [ ] AC-10 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `pnpm exec prettier --check client indexer` and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-11 **The owner's eye, last**, on the public site after the merge: does the ground read as
      the pack's, in the zone and the hubs? A change of a constant (the lip, the earth's alpha, a
      colour variant) is a fix lot; a change of method goes back to *The method*.

Lot 2's criteria: the foam cell cut at 192 × 192 and checked (synthetic test); one foam still under
every land hex that touches water (plan test); the frame budget of AC-8 still met; shots as AC-7;
the owner's eye.

## Verification

- On the VPS: the commands of AC-10; `tools/art/build.py` with the uncommitted `assets` symlink,
  removed afterwards; then the browser check (AC-7, AC-8, AC-9).
- Start and stop the dev server inside one foreground command; kill only its recorded process
  group. Remove the temporary `main` worktree by its exact path.
- `scripts/prepush.sh` before every push, never `--no-verify`. Do not poll CI: push, open the pull
  request, end the turn.

## Review and audit

- **Review** on another model than the implementer's: `review` (Sonnet) for an Opus implementer.
  It checks most closely: the ground never reaches the stand-ins; boundaries on hex edges; the
  chunk key and the library's rebake; bakes unchanged in size and count; drawing on demand; the
  frame figures and how they were taken.
- **Audit**: none (D-177; the owner sees the lot). The orchestrator decides otherwise if the lot
  adds a dependency or leaves the allowlist.

## Rules of the run

- D-73: nothing of the pack committed or posted; sizes, counts and words only.
- No pin, fingerprint or byte count committed.
- External issues named in words, not links, in commit messages and pull request text.
- Pull request title: `[<model>] CLI-03g1 the textured ground for zones and hubs`; body through
  REST (`gh pr edit` fails on Projects-classic): the method as built, the frame figures with
  `main`'s, "Audit: none (D-177)", "Owner's eye: on the public site after the merge".

## Report

`docs/reports/CLI-03g1-textured-ground.md`, as in `docs/briefs/COMMON.md` §7, with: the method as
built and any deviation; the fixtures' ground (counts per kind in each location); the frame figures
of AC-8 with the commands and their real output; the shots described in words and where they are;
the tests updated and why; `git diff origin/main -- client/app/src/sandbox/placeholders.ts`;
commands refused; deviations, escalations, open questions.

## Open questions

1. **For the owner: exact hexes or the pack's rounded coasts** (*The method* §1). Default: B, exact
   on hexes, softened by the lip (lot 1) and the foam (lot 2). Reverse: A on the hubs' coasts.
2. **For the owner: the zone's void as water** (*The method* §3). Default: water, so zones and hubs
   are islands as the pack draws them. Reverse: a dark void (today's background) or grass with
   rocks (today's look): one fixture value.
3. **For the orchestrator: biomes and colour variants.** The seed has one meadow; the pack has five
   greens. Default: `grass_c` of the first variant everywhere (the hubs' choice). Later, when a
   forest or a cave exists, a biome picks a variant (a `[[tileset]]` entry per variant, a mapping
   in the client): proposed meadow 1, forest 3, ruin 4, cave 5, the owner's eye deciding. No lot
   until a second biome exists in the fixtures.
4. **For the orchestrator: the pack's obstacles on the zone's walls.** design/10 names rocks,
   bushes, trees and stumps from `Terrain/Decorations`; the zone still draws a shaped rock. Default:
   out of this lot; a small later lot reuses CLI-03f's structures for the zone's walls.
5. **For the project manager: two lots or one** (*Size*). Default: two, lot 1 shown to the owner.
6. **For the orchestrator: the PLAN row.** CLI-03g has no row in `PLAN.md`; the orchestrator adds
   it (or the project manager's log thread) with this brief's merge.
