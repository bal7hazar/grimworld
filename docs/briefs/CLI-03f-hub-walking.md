# CLI-03f — Hubs as zones: a hub is lived like an exploration zone, client-side

**Status: ready to start.** CLI-03e merged as #307. The work is done on the branch of #319, which
built a lighter hub walk from the first version of this brief. That variant is **not merged**: this
brief replaces it, and the same pull request is reworked.

Written for the orchestrator of track CV on 2026-10-02, from **D-202** (the project manager, from
the owner's feedback). The owner, on the hubs: "the town map is not right at all; the immersion
must stay the same: whether town, exploration zone or dungeon, we must model on the
exploration-zone experience (hex map, pathfinding, etc.)". The first version of this brief made a
hub a fitted illustration with its own light walk. D-202 rules that out: **a hub takes the zones'
engine as is**. A town or an outpost is a zone whose places are buildings.

## Agent

Profile: `impl-opus`. The lot is presentation with design judgement: it moves the hubs onto the
zone's controller, renderer and session, teaches the renderer to draw buildings and props on wall
hexes, and keeps the zone's tests green while doing it.

Branch: **#319's branch**, `hp/grimworld-cv/t-0062-cli-03f-walking-in-the-hubs`, the same pull
request. Bring `main` in by a merge if needed: never a rebase, never a force push.

Machine: **the VPS** (the Mac is not offered). The lot commits no pin, gas table or fingerprint.
The pack is at `/home/claude/projects/assets`: `tools/art/build.py` reads `assets/` at the repo
root, so link it into the worktree by an **uncommitted** symlink for the build and remove the link
afterwards, as #319 did. The browser check runs here in headless Chromium.

## Goal

After this task, the town and the outpost are lived exactly like the seed's zone:

1. **The same engine.** A hub opens in the zone's controller (`SandboxController`), on the zone's
   renderer (`Renderer`), with the zone's session (`SandboxSession`) and wiring (`wiring.ts`). Same
   hex map, same camera (follow, pan, pinch and wheel zoom, ◎ back to the adventurer), same zoom
   levels, same scale modes, same tile drawing, same path finder, same step, turn and tween.
2. **A hub is a zone's content.** Its ground is the zone's terrain. Its buildings and props stand
   on wall hexes, as obstacle objects (design/10). Its present adventurers are actors that stand
   still. The player's adventurer arrives on a hex beside the Gate.
3. **Places open by walking onto their door.** A tap on a building paths to its door with the
   zone's own pathfinding, then opens the place. The service row under the map still opens a place
   at once.
4. **The Gate is a place.** Walking onto its door opens the Gate screen. CLI-03d's arrival rule
   and D-148 are unchanged.

Everything is client-side. The chain knows only which hub an adventurer is in (D-03). The position
inside a hub is presentation (D-196, D-202): never sent, checked or stored.

## Context

- **D-202** (the project manager, 2026-10-02, from the owner's feedback above), recorded in this
  brief and in the orchestrator's decisions. It replaces the first version's design choices 1
  (a lighter hub walk) and 6 (no camera, the hub fits the screen). The project manager's earlier
  ruling that the hub walk is presentation, not a rule, still holds for the **position**. The
  **finder** is now the zone's: see *Design choices* §4.
- **D-196** (`docs/decisions/2026-10-02-cli-03c-visual.md`): the hubs keep the hex-map mechanics,
  client-side, and get the real assets.
- **D-178** (`docs/decisions/2026-10-01-cli-03c-hubs.md`) and its lending, extended to CLI-03d and
  CLI-03e: under it, this lot writes design/11 *Hubs*' first line (*Design choices* §8).
- **The house style and the lots before this one**:
  - `docs/briefs/CLI-03a-render-sandbox.md`, `docs/briefs/CLI-03b-sandbox-path.md`: the room, its
    renderer, its camera, its walk;
  - `docs/briefs/CLI-03c-hubs.md`: the loop, the screens, the intents;
  - `docs/briefs/CLI-03d-hubs-followup.md`: the arrival rule, `gateHere` and `leaveOffer`;
  - `docs/briefs/CLI-03e-hubs-visual.md`: the pack's buildings and props on anchor hexes, one
    scale (the room's), the labels.
- **design/10 *Hex grid with a square tileset***: one continuous ground per biome, a subtle hex
  grid, and **one obstacle object per wall tile** (rock, bush, tree, stump). A hub's buildings and
  props are exactly that.
- **D-148** (`docs/decisions/2026-09-29-eng-06-lifecycle.md`): a gate is used by standing on its
  anchor tile. The hub gates (the seed's gate 1, the fixture's gate 101) have anchor `0/0`: a hub
  has no map in the seed. See *Design choices* §7.
- **D-03 and the indexer's scope** (`docs/decisions/2026-09-28-indexer-scope.md`, question 2): the
  chain knows who is in which hub. Other adventurers moving live needs a relay (Q-09, Phase 5).
  **Only the player's own adventurer walks.**
- **The mandate** `docs/briefs/ORCH-client-visual.md`: §1 for the paths; §4 (D-73) for the art;
  §6, binding: no rule in `client/app` outside `sandbox/placeholders.ts`; the renderer's input is a
  view state; a tap produces an intent; rendered on demand; no randomness and no clock in what
  `client/sim` will decide.
- **Phone work is suspended** (owner, 2026-10-02). The design stays mobile-first: checked in the
  browser at 375 × 812 and 1440 × 900, nothing on a device.

### What main has today: the zone

The seed's zone, opened by the loop's instance (`sandbox/loop/InstanceScreen.tsx`), is:

| Part | Where | What it does |
|---|---|---|
| The world | `sandbox/world.ts` (`SandboxWorld`, `Terrain`), `sandbox/fixtures/zone.ts` (`zoneWorld`) | Terrain of whole 15 × 15 chunks (`floor`, `wall`, `unrevealed`), actors, the adventurer's id |
| The mount | `sandbox/Sandbox.tsx` (`RoomSandbox`) | Mounts the controller on a world, reports the adventurer's tile after each change (`onTile`), carries the loop's controls over the map, the ◎ button, the walk counter, the debug panel |
| The controller | `sandbox/controller.ts` (`SandboxController`) | PixiJS surface, gestures (`input/gestures.ts`): pan, zoom, tap → `{ kind: "tile" }`, press → `{ kind: "inspect" }`, through `screenToTile` |
| The session | `sandbox/session.ts` (`SandboxSession`) | Applies intents through the wiring; walks the planned queue on the host's timers, one step every `stepMs`; pauses while hidden |
| The wiring | `sandbox/wiring.ts` (`applyIntent`, `walkStep`, `toView`) | The only importer of `placeholders.ts`: path on a tap (`findPath`), step (`stepToward`), sight, reveal, stop conditions, arcs on a selected actor, the tick cost |
| The renderer | `render/renderer.ts` (`Renderer`) | Draws a `ViewState` on demand: terrain baked per chunk (`render/shapes.ts` `drawTerrain`: ground, a rock on each wall, the grid), actors sorted by y, the step tween (`STEP_MS`), the turn (`TURN_MS`), the camera's follow (`CAMERA_MS`), the path's ghosts, the zoom levels (`DEFAULT_ZOOM`), the scale modes |
| The rules' stand-ins | `sandbox/placeholders.ts` | `findPath` (BFS inside the D-120 window, off its outer ring), `stepToward`, `neighbour`, `tilesInSight`, `revealInSight`, `stopsAfterStep`, `visibleActors`, `arcsOf`, `TICKS_PER_STEP`, and the loop's `hubGateAt`, `entryThrough`, `hubAfter` |

### What main has today: the hub

| Part | Where |
|---|---|
| The view | `render/hubView.ts`: `HubView` (places, decor, props, figures, services, the ground's tileset, water and drawn path), `hubPoint`, `feetPoint`, `standingOrder`, `groundCell` |
| The renderer | `render/hubRenderer.ts` (`HubRenderer`): the water backdrop, the tileset ground baked once, the standing layer sorted by base y, buildings and props from the atlas's `still` (role `building`, `prop`), shapes without the atlas; no camera, no tween |
| The taps | `input/hubTaps.ts`: `hubFit` (the whole illustration fitted in its zone), `placeRect`, `figureRect`, `overlap`, `targetIntent`, `figureIntent` |
| The screen | `sandbox/loop/HubScreen.tsx`: one HTML button per place and present figure over the canvas, the service row below |
| The fixtures | `sandbox/fixtures/hubs.ts`: the town (11 columns × 19 rows of hexes, 9 places, 3 decor buildings, 14 props, 3 figures) and the outpost (4 places, 2 decor, 11 props, 1 figure), every one on a hex; `BUILDINGS` (native sizes) |
| The machine | `sandbox/loop/machine.ts`: the hub screen `{ kind: "hub", hub, inspected }`, no position |
| The browser check | `client/app/verify-hubs.mjs` (`pnpm --filter @grimworld/app verify:hubs`) |

### What #319's branch has (the light variant, not merged)

`input/coords.ts` `neighbours`; `input/hubWalk.ts` (`hubWalkable`, `hubPath`, a BFS, `HubWalker` on
timers); a walker, a step tween and a target marker in `HubRenderer`; `input/hubTaps.ts`
`hubTile`; the fixtures' `arrival` (town `(2, 0)`, outpost `(1, 1)`) and `depth` (0 for the town's
Market and the outpost's straw hut); the machine's `at` on the hub, service and Gate screens and
its `stood` answer; an imports-test assertion on `hubWalk.ts`; the walking pass of
`verify-hubs.mjs`; design/11's first line in the first ruling's words; its report
`docs/reports/CLI-03f-hub-walking.md`. Its measures: 16 steps from the arrival hex to the town's
Guild; a town hex 34.1 points across at 375 × 812 under `hubFit`.

## Scope and non-goals

- **In**:
  1. `hubWorld`: a hub's fixtures turned into a `SandboxWorld` (terrain, actors, the arrival hex).
  2. The renderer draws a view's **structures** (buildings, decor buildings, props) on their hexes,
     sorted with the actors, from the atlas's stills or as shapes.
  3. The hub screen built on `RoomSandbox`, with the places' labels following the camera, and the
     service row.
  4. A tap routed before the wiring: a building walks to its door, a figure is inspected; anything
     else is the zone's own tap.
  5. A place opens when a walk the player started toward it ends on its door.
  6. What a hub must not inherit from the zone's stand-ins (*Design choices* §3), as one world
     kind read by the wiring, and one parameter of `findPath` (§4).
  7. The machine keeps the adventurer's hex across a hub's screens.
  8. Removing what the hub no longer uses (CLI-03e's renderer and fit, #319's walk).
  9. design/11 *Hubs*' first line (§8). Tests, and the browser check extended.
- **Out (non-goals)**:
  - Anything on chain: no entrypoint, no event, no seed change, no position sent or stored.
  - Any new game rule, and any hub symbol in `placeholders.ts`.
  - `client/sim/**`, `contracts/**`, accounts (`client/app/src/account/**`, `client/app/src/chain.ts`).
  - Other adventurers walking: they stand still (D-194).
  - Moving a building, a prop or a figure: CLI-03e's positions stay, except where a door must be
    reachable (§5).
  - A textured ground (design/10's "one continuous textured ground per biome"), for the zone and
    the hub together: a later lot (*Open questions* §2).
  - The keyboard (design/11 *Desktop*), the client's chrome from the pack's `UI Elements/`, the
    service screens (CLI-06, CLI-07), the world map (CLI-08).
  - Remembering the position across a reload or a later visit.
  - Phone builds, simulators, devices (suspended).

## Design choices

Each choice gives a recommendation, its reason, and what would reverse it. The first two are
binding (D-202); the others are this brief's.

### 1. The zone's engine, as is (binding)

A hub opens through `RoomSandbox` with a `SandboxWorld`, exactly as the instance opens the zone.
The loop's `HubScreen` becomes a sibling of `InstanceScreen`: `RoomSandbox` with the hub's
controls as children.

- **Reused unchanged**: `SandboxController`, `SandboxSession`, `Renderer`, `GestureTracker`,
  `screenToTile`, the camera and its follow, `DEFAULT_ZOOM`, the scale modes, `STEP_MS`, `TURN_MS`,
  `CAMERA_MS`, the path's ghosts, `render/facing.ts`, the idle animation setting, the ◎ button and
  the debug panel.
- **Dropped**: `hubFit` and "the hub fits the screen"; `HubRenderer`; #319's `input/hubWalk.ts`
  (its BFS, `hubWalkable`, `HubWalker`), its walker, tween and target marker in `HubRenderer`,
  `hubTile`, and `neighbours` in `input/coords.ts` (the zone's finder needs no second copy of the
  hex rule: the imports test's F-6 guard forbids copies).
- The camera opens centred on the adventurer, at `DEFAULT_ZOOM.defaultAcross`, as in a zone.

**What reverses it**: only the owner or the project manager (D-202).

### 2. A hub's content as a zone's content (binding in substance, shape proposed)

A pure `hubWorld(view, at)` (in `sandbox/fixtures/hubs.ts`, or a new `sandbox/fixtures/hubWorld.ts`)
returns a `SandboxWorld`:

- **Terrain**: whole 15 × 15 chunks covering the hub's hexes (the town needs 1 × 2 chunks). Every
  chunk is revealed: a hub has no `unrevealed` tile.
  - `floor`: a hex of the island. The island is the hexes whose centre is at least half a hex
    inside CLI-03e's illustration rectangle (#319's measured rule: whole border cells would close
    the town's road on row 0).
  - `wall`: every other hex (outside is void, D-134), **and** every hex a building or a prop
    stands on.
- **Buildings**: a building, place or decor, makes `wall` the hexes of its footprint: its base row,
  the hexes whose centre lies under its width, centred on its anchor, and `depth` rows behind it
  (default 1; 0 for the town's Market and the outpost's straw hut, from #319). **A place's door,
  its anchor hex, stays `floor`**; a decor building's anchor is `wall`.
- **Props**: trees, bushes, rocks, stumps, sheep make their hex `wall`. They are design/10's
  obstacle objects of those wall hexes.
- **Actors**: the player's adventurer (`ADVENTURER`'s profession) on `at`, and each present figure
  as an adventurer actor on its hex, facing West (3) for `"left"` and East (0) for `"right"`, with
  no mark. Actors block a path as in a zone.
- **Structures**: the world carries the hub's buildings and props as data for the view (§6), not
  as actors.

Tests assert, for both hubs: the arrival hex is `floor` and free; every door is `floor`; every
door is reachable from the arrival hex with the zone's finder (§4); no structure stands on a
`floor` hex except at a door.

**What reverses it**: a hex the owner finds wrongly open or closed is a `depth` or an extra
`blocks` list on a building: a fixture value.

### 3. What a hub does not inherit from the zone's stand-ins

The zone's wiring calls stand-ins for the instance's rules. A hub has no fight, no goblin, no fog,
no tick: it must not inherit them as game rules. The world carries a kind, `kind: "zone" | "hub"`
(default `"zone"`, so every existing fixture and test is unchanged), and the wiring reads it:

| Stand-in | In a zone | In a hub |
|---|---|---|
| Sight (`tilesInSight`, design/18) | radius 6, beyond dimmed | every tile is in sight: nothing dimmed |
| Reveal (`revealInSight`) | chunks revealed by sight | nothing to reveal (no `unrevealed` tile) |
| Stop conditions (`stopsAfterStep`) | a goblin enters sight, a chunk is revealed | none can fire (no goblin, no reveal); a test asserts it |
| The D-120 window in `findPath` | the path stays inside it, off its outer ring | **no window**: §4 |
| Tick cost (`TICKS_PER_STEP`) and the walk counter | "*n* steps · *n* ticks ✕" | **no counter**: `RoomSandbox` hides it for a hub; a new tap retargets, as in a zone |
| A tap on an actor | selects it and shows its arcs (design/04) | routed before the wiring: a present figure is inspected (§5); the player's adventurer is a no-op |
| Goblins, fights, `defeat now`, Leave, Travel back | the instance's | none: those controls are `InstanceScreen`'s, not `RoomSandbox`'s |

`placeholders.ts` gains no hub symbol. The hub kind is read in `wiring.ts` only (and `Sandbox.tsx`
for the counter), so the imports test keeps its guards.

**What reverses it**: a game decision that gives hubs one of these (a night watch, a brawl in the
tavern) would be a rule in `client/sim`, not here.

### 4. The zone's finder, without the D-120 window

The town has 19 rows of hexes. The D-120 window is 16 rows around the adventurer, and `findPath`
keeps a path off its outer ring. From the arrival hex on row 0, the zone's finder would refuse the
Guild's door on row 12 (#319 measured 16 steps to it). The window bounds **the chain's tick**
(D-120): it is not the finder's, and a hub has no tick.

**Recommended**: `findPath` takes one optional parameter that lifts the window bound, default
bounded. The wiring passes it for a hub only. The zone's paths, and every test of `placeholders.ts`,
`wiring.ts`, `session.ts` and `walkFollowsPreview.test.ts`, are unchanged. One test is added: an
unbounded path across more than 16 rows. The tie rule and the BFS are untouched.

- The step stays `stepToward`, unchanged: a hub's step is the zone's step.
- When CLI-02/CLI-03 replace `findPath` by the map library's finder from `client/sim`, the hub uses
  that finder too, without the tick's window. The hub's position stays presentation: the finder is
  shared, nothing it answers in a hub is sent or checked.

**What reverses it**: the project manager prefers no change to `placeholders.ts`. The alternative
is a hub that walks in legs (a new path from where each leg ends), which shows as a stop in the
walk: worse, and still the zone's finder.

### 5. Taps: buildings to their door, figures inspected

A tap on the canvas goes through the controller's gestures and `screenToTile` as in a zone. The
hub screen gives `RoomSandbox` one optional hook, `route(intent) → Intent | null`, applied by the
controller before the session (the zone passes none):

- **A hex of a place's footprint, its door included**: the intent becomes a tap on the door. The
  hub screen remembers the place as the walk's **destination**.
- **A present figure's hex**: the hook dispatches `inspect adventurer` (the machine's, unchanged)
  and returns `null`. A long press on it does the same.
- **A decor building's or a prop's hex**: `null`, and one log line (no target, as CLI-03e).
- **Anything else**: the intent unchanged, the zone's own tap: a `floor` hex is walked to, a `wall`
  clears. A new tap clears the destination.

The destination opens the place when **the walk ends with the adventurer on the door** (the
session's walk is over, the planned queue empty, no stop). Then `targetIntent(place.target)` is
dispatched once: `open service` or `open gate screen`. So:

- if the adventurer already stands on the door, a tap on the building opens at once;
- a walk that passes over a door opens nothing;
- a ground tap on a door's hex opens that place, as the building's tap does;
- if no path to the door exists (a test asserts every door is reachable), the place opens at once
  and the log says why;
- **the service row opens a place at once**, with no walk, and ends a walk in progress: a
  one-thumb shortcut (I-1) and a way that never waits on an animation (accessibility).

The route is pure (`hubTap(world or view, tile)`), tested without a browser.

**What reverses it**: the owner wants a building's tap to open at once with the figure walking
unseen: one branch in the hub screen.

### 6. Buildings and props drawn by the zone's renderer

`ViewState` gains `structures`, empty for a zone: each `{ key, sprite, at, width, height,
mirror?, kind: "building" | "prop" }`, from the hub's places, decor buildings and props.

- The renderer draws each in the actor layer, its base on its hex's centre (CLI-03e §5: the middle
  of a building's base on its anchor), from the atlas's `still` (roles `building` and `prop`,
  `tools/art`), at native size: one scale, the room's (CLI-03e).
- Without the atlas, the shapes CLI-03e's `HubRenderer` draws for buildings move into
  `render/shapes.ts`.
- Structures and actors sort together by the y of their base, then by a stable key (CLI-03e's
  `standingOrder`), so a figure behind a house is covered and one in front covers it.
- **A wall hex under a structure draws no rock**: the structure is its obstacle object (design/10).
  `drawTerrain` gets the set of covered hexes. The zone passes none, so its terrain draws as today
  and the renderer's tests pass unmodified.
- Structures never move and are not tweened. They do not ask for frames: drawing stays on demand.
- **The ground is the zone's**: `drawTerrain`'s plain continuous ground, the subtle grid, chunk
  bakes. CLI-03e's tileset ground, its water backdrop and its drawn earth path are dropped with
  `HubRenderer` (the path was drawing only). A textured ground for zones and hubs together is a
  later lot (*Open questions* §2).

**Labels**: the places' names stay HTML, positioned from the renderer's camera (`tileToScreen` on
the anchor, above the building's height) after each drawn frame. They are not buttons: taps go
through the canvas. The present figures' names show on inspection, as CLI-03c's. The service row
under the map stays: it is the accessible way to every place.

**What reverses it**: the owner wants the tileset's grass back before the textured-ground lot. That
would be a ground layer of the zone's renderer, for zones too, never a hub-only renderer.

### 7. Arrival, the Gate, D-148 and the arrival rule

- **The arrival hex**: #319's, beside the Gate on the road: town `(2, 0)`, outpost `(1, 1)` (a
  fixture value, `arrival`). Every arrival puts the adventurer there: the first hub of the loop
  (`hubState`) and the hub a closing report leads to, whatever the outcome. Arriving never opens a
  place and never starts a walk.
- **The Gate is a place**: its door ends a walk → the Gate screen. The Gate screen is unchanged
  (the gates, the build, the belt, the last check, then *Leave* → `enter gate`).
- **D-148, in spirit, untouched in the data.** A hub has no map in the seed, so its gates' anchors
  (`0/0`) are not on the hub's grid. The Gate's door is a **client fixture hex**. Standing on it to
  open the Gate screen is the client's analogue of "used by standing on its anchor", and it decides
  nothing: entering is still the Gate screen's confirmed `enter gate`. No seed change; `hubGateAt`,
  `entryThrough` and `hubAfter` unchanged.
- **The arrival rule is unchanged.** In the instance, CLI-03d's `leaveOffer`, `gateHere` and the
  Leave control stay as they are. In the hub, "never on arrival" holds by construction: the
  adventurer arrives beside the Gate, not on its door, and only a walk the player started can open
  a place. Back from the Gate screen, the adventurer stands on the door and nothing reopens.
- **The machine** (`sandbox/loop/machine.ts`, #319's shape kept): the hub, service and Gate screens
  carry `at: Tile`. `hubState(hub)` and `close report` set it to the hub's `arrival`. `back` keeps
  it. The hub screen sends the zone's existing answer **`moved`** after each step (as the instance
  does), accepted on the hub screen; #319's `stood` is dropped. The machine records the hex and
  decides nothing about it.
- The hub's room is remounted on each return to the hub screen (the loop's key), with the
  adventurer on `at`.

### 8. design/11 *Hubs*, first line

Written by this lot under D-178's lending, replacing #319's line, exactly:

> Hubs have no geometry on chain (D-03). On the client, a hub is lived like an exploration zone:
> the same hex map, camera, pathfinding and rendering; its places are buildings the adventurer
> walks to (D-196, D-202).

Nothing else in `docs/design/` changes. If another line of design/11 *Hubs* contradicts it (the
sketch of a fitted illustration, for example), the thread lists it under *Escalations* instead of
editing it.

## What is reused and what is dropped

| From | Reused | Dropped |
|---|---|---|
| CLI-03e (#307, main) | The places, decor buildings, props and figures and their hexes; `BUILDINGS`; the atlas's stills of roles `building` and `prop`; the services lists; `targetLabel`, `targetIntent`, `figureIntent`; the service row; the building shapes without the atlas; the standing order's sort rule | `HubRenderer` and its tests; `hubFit`, `placeRect`, `figureRect`, `overlap`, `MIN_TARGET` and their tests; the tileset ground (`groundCell`, `groundCells`, `HubGround`), the water backdrop, `PATH_ALPHA`, `SHOW_GRID`; the HTML place and figure buttons over the canvas. `tools/art` keeps the role `tile` (not in the allowlist): the client no longer draws it until the textured-ground lot |
| #319's branch | `arrival` (town `(2, 0)`, outpost `(1, 1)`); `depth` and its two zeros; the island's half-hex rule; the machine's `at` and its tests; the door rules (walk ends on the door, already on it, passing over, the service row at once); the walking pass of `verify-hubs.mjs`, adapted; its measures as a reference | `input/hubWalk.ts` and its tests; `neighbours` in `input/coords.ts`; the walker, tween and target marker in `HubRenderer`; `hubTile`; `WalkedHub`; the `stood` answer; its imports-test assertion on `hubWalk.ts`; its design/11 line; its report, rewritten |

## Allowlist

- `client/app/src/**` except `client/app/src/account/**`, `client/app/src/chain.ts` and their tests.
  The expected files:
  - `sandbox/world.ts` (`kind`, `structures`), `sandbox/wiring.ts` (the hub kind), `sandbox/Sandbox.tsx`
    (`route`, no counter for a hub), `sandbox/controller.ts` (`route`);
  - `sandbox/placeholders.ts`: **only** the optional window parameter of `findPath` (§4), with one
    test;
  - `render/view.ts` (`structures`), `render/renderer.ts`, `render/shapes.ts` (structures, covered
    hexes, building shapes);
  - `render/hubView.ts` (kept as the fixtures' data types, its drawing helpers removed),
    `render/hubRenderer.ts` and `input/hubTaps.ts` (removed or reduced to `targetIntent`,
    `figureIntent`), `input/hubWalk.ts` and `input/coords.ts` (#319's additions removed);
  - `sandbox/fixtures/hubs.ts` (and a new `hubWorld.ts` if preferred);
  - `sandbox/loop/HubScreen.tsx`, `sandbox/loop/machine.ts`, `sandbox/loop/Loop.tsx`;
  - `sandbox/imports.test.ts`: guards kept; assertions may be added; none loosened. If the hub
    kind needs a guard's allow-list to grow, escalate instead.
- `client/app/verify-hubs.mjs`.
- `docs/design/11-interface.md`: **the first line of *Hubs* only** (§8).
- `docs/reports/CLI-03f-hub-walking.md`: rewritten for this lot.
- **Not in the allowlist**: `tools/art/**`, `client/app/package.json`, `pnpm-lock.yaml`,
  `client/sim/**`, `.github/`, the rest of `docs/design/`. Anything else is an escalation in the
  report, not an edit.

## Interfaces

- **`SandboxWorld`** (`sandbox/world.ts`): `kind?: "zone" | "hub"` (default `"zone"`);
  `structures?: readonly Structure[]` (default none).
- **`ViewState`** (`render/view.ts`): `structures: readonly ViewStructure[]` (empty for a zone),
  produced by `toView` from the world.
- **`findPath`** (`sandbox/placeholders.ts`): one optional last parameter that lifts the D-120
  window bound; default bounded.
- **`RoomSandbox`** and **`SandboxOptions`**: an optional `route(intent: Intent): Intent | null`.
- **`hubWorld(view, at): SandboxWorld`** and **`hubTap(view, tile)`**: pure, in the fixtures or a
  hub module of `sandbox/`, never in `placeholders.ts`.
- **The loop's intents** (`input/intent.ts`): unchanged. The map intents (`tile`, `inspect`) are
  unchanged.
- **The machine**: `at: Tile` on the hub, service and Gate screens; `moved` accepted on the hub
  screen.

## Acceptance criteria

- [ ] AC-1 **The same engine**: the hub screen mounts `RoomSandbox` with a `SandboxWorld` of kind
      `"hub"`; `HubRenderer`, `hubFit` and `input/hubWalk.ts` are gone (or no longer imported by
      the loop: the report says which); a test asserts the hub screen's world goes through
      `SandboxSession` and the zone's `Renderer`.
- [ ] AC-2 **The world** (unit tests on both hubs): the arrival hex is `floor` and free; every door
      is `floor`; every building's footprint (with `depth`) and every prop's hex is `wall`; no
      `unrevealed` tile; every door is reachable from the arrival hex with `findPath` unbounded;
      the present figures are actors on their hexes.
- [ ] AC-3 **The stand-ins a hub does not inherit**: in a hub, every tile is in sight; a walk
      across the town fires no stop; the walk counter is not shown; a tap on a figure inspects it
      and selects nothing (no arcs). In a zone, all of these are as before (the existing tests,
      unmodified).
- [ ] AC-4 **The finder**: `findPath` bounded gives the same paths as before (every existing test
      unmodified); bounded, the town's Guild door is out of reach from the arrival hex (row 12,
      beyond the window's ring); unbounded, a pinned path to it.
- [ ] AC-5 **Taps**: on fake timers (`FakeHost`): a tap on a `floor` hex walks there one step per
      `STEP_MS`, facing each step, with the camera following; a tap on a building walks to its
      door, then dispatches `targetIntent` once; standing on the door, a tap opens at once; a walk
      passing over a door opens nothing; a tap on a decor building or a prop does nothing but a log
      line; the service row opens at once and ends a walk; a new tap retargets; the walk pauses
      while hidden and resumes after.
- [ ] AC-6 **Drawing**: structures are drawn from the atlas's stills at native size (the synthetic
      atlas) and as shapes without it; they sort with the actors by base y (a figure behind a
      building is under it); a wall under a structure draws no rock; drawing stays on demand (no
      frame once a walk ends, no ticker left running); the zone's renderer tests pass unmodified.
- [ ] AC-7 **The Gate and the arrival rule**: a walk ending on the Gate's door opens the Gate
      screen; arriving opens nothing; back from the Gate screen keeps the adventurer on the door
      and nothing reopens; CLI-03d's arrival-rule tests in the instance pass **unmodified**;
      `hubGateAt`, `entryThrough`, `hubAfter` are unchanged and `placeholders.ts` changes only by
      §4's parameter (`git diff origin/main -- client/app/src/sandbox/placeholders.ts` in the
      report).
- [ ] AC-8 **The position survives the hub's screens** (machine tests): arrival on `arrival` after
      `hubState` and after `close report` for each of `gate`, `travel back` and `defeat`; a service,
      then back, keeps `at`; the Gate screen, then back, likewise.
- [ ] AC-9 **Mechanics unchanged elsewhere**: the room's tests (`walkFollowsPreview`, `wiring`,
      `session`, `renderer`, `placeholders`) and the CLI-03c and CLI-03d tests pass unmodified,
      except tests that build a hub screen without `at`, or test removed hub pieces: the report
      lists each one updated or removed, and why.
- [ ] AC-10 **The imports test**: green, no guard loosened; the hub kind and the route import nothing
      from `placeholders.ts` outside `wiring.ts`; shown red on a seeded violation, then removed.
- [ ] AC-11 **The browser check** (`pnpm --filter @grimworld/app verify:hubs`, adapted), on the VPS
      in headless Chromium, at **375 × 812** and **1440 × 900**, in both hubs, with the atlas built
      from this branch (never committed). It checks:
      - the hub's canvas is the zone's: `RoomSandbox` exposes the frames drawn as `data-frames`
        (the renderer's `onDraw` stats, as CLI-03e's `HubScreen` did), for the instance too;
      - a tap on a ground hex walks there, the camera follows, and `data-frames` stops growing once
        the walk ends;
      - a tap on the Smith (town) and the Trainer (outpost): walk, then the service screen; back,
        and the adventurer is on the door;
      - a walk to the Gate: the Gate screen;
      - a pinch or wheel zoom and the ◎ button work as in the instance;
      - the CLI-03c/03d loop as before; no page error.

      With `VERIFY_SHOTS=1`, a shot of each hub at each size, mid-walk and after, into the thread's
      library folder, **untracked**: never committed, attached or posted (D-73). The report
      describes them in words and gives the run's real output.
- [ ] AC-12 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `pnpm exec prettier --check client indexer` and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-13 **The owner's eye, last**, on **https://grimworld.bal7hazar.com after the merge** (the
      site rebuilds from `main` within 5 minutes once its timer is installed, with the atlas). The
      orchestrator sends the project manager one line: what to look at and the URL.
      - The question: does the hub look and play like a zone (same camera, zoom, pathfinding,
        rendering)?
      - The owner's answer is recorded in the pull request or the status file.
      - A change that is a constant or a fixture value (arrival hex, `depth`, a label's place) is a
        fix lot; a change of mechanics is a new lot.

## Verification

- **On the VPS**:
  - the commands of AC-12 (Cairo is not touched: `scripts/prepush.sh` runs no Cairo build);
  - `tools/art/build.py`, with `assets` linked to `/home/claude/projects/assets` by an uncommitted
    symlink, removed afterwards;
  - then the browser check of AC-11.
- Start and stop the dev server inside one foreground command, and kill only its recorded process
  group (the script does this already).
- `scripts/prepush.sh` before every push, never `--no-verify`.
- CI is polled at most once per pull request every 5 minutes. Better: push and end the turn.

## Review and audit

- **Review** by the other model on the pull request's head: `review` (Sonnet) when the implementer
  is Opus, as recommended. The reviewer works from the diff and the tests; the owner's eye is the
  visual verdict. It checks most closely:
  - that the hub runs on the zone's controller, session, wiring and renderer, with no hub-only
    walk, finder or renderer left;
  - that `placeholders.ts` changes by §4's parameter only, with the zone's paths unchanged;
  - that no zone stand-in (sight, stops, ticks, arcs) leaks into a hub, and no hub symbol into
    `placeholders.ts`;
  - that the arrival rule is untouched and drawing stays on demand.
- **Audit**: per D-177, none by default (the owner sees the lot). The orchestrator decides
  otherwise if the thread adds a dependency, touches a path outside the allowlist, or changes
  `placeholders.ts` beyond §4.

## Rules of this run

- D-73: nothing of the pack in a commit, the pull request, an issue, a comment or the report.
  Sizes, counts, paths and descriptions in words are fine. The symlink to the pack is never
  committed.
- No pin is generated or committed.
- Foreground only. Never merge unless prompted with the exact line. Never rebase or force-push
  #319's branch.
- External issues are named in words, not links, in commit messages and pull request text.
- Pull request (#319) title: `[<model>] CLI-03f hubs as zones (D-202)`. The body (set through REST,
  `gh pr edit` fails on Projects-classic):
  - says the light variant is replaced by D-202's design, and lists the eight design choices as
    built, with any deviation;
  - lists what was reused and dropped (the table above, as built);
  - names every dependency added (none expected);
  - says "Audit: none (D-177)" unless the orchestrator decides otherwise, and "Owner's eye: on the
    public site after the merge".

## Report

`docs/reports/CLI-03f-hub-walking.md`, rewritten, as in `docs/briefs/COMMON.md` §7, with:

- the summary and the pull request's URL;
- the files changed, added and removed;
- the arrival hexes, the `depth` values and any fixture moved so that a door is reachable;
- the measured longest walk (steps and seconds) in each hub, and the hex size in points at
  375 × 812 at the default zoom;
- the browser check's commands and real output, and where the shots are;
- the tests updated or removed, and why;
- `git diff origin/main -- client/app/src/sandbox/placeholders.ts`;
- the commands refused by the profile;
- deviations, escalations and open questions.

## Open questions

1. **Decided (D-202): a hub's engine.** The zone's, as is; no light hub walk, no fitted hub. The
   first version's §1 and §6 are withdrawn.
2. **For the owner, later: the ground's look.** The hub now draws the zone's plain ground and grid,
   so CLI-03e's tileset grass, water and earth path are gone from the hub until a textured ground
   (design/10's "one continuous textured ground per biome") is built for zones and hubs together.
   - Default: as written; the textured ground is a later lot of track CV, proposed to the project
     manager after the owner's eye (AC-13).
   - Reverse: the owner asks for the tileset's grass in the hubs now. It would then be a ground
     layer of the zone's renderer, for both.
3. **For the project manager: `findPath`'s window parameter** (§4). One optional parameter in
   `placeholders.ts`, default unchanged.
   - Default: as written, recorded in the PR.
   - Reverse: no change to `placeholders.ts`; the hub then walks in legs, which shows.
4. **For the owner: the feel.** The pace (`STEP_MS`, the zone's), the arrival hex, the `depth` of
   each building, the zoom (the zone's `DEFAULT_ZOOM`): each a constant or a fixture value, judged
   at AC-13.
5. **For the orchestrator: the keyboard.** design/11 *Desktop* gives `Q W E A S D`. Default: out of
   this lot; one later lot brings it to the zone, and so to the hub.
6. **Decided: where the owner looks.** On the public site after the merge (the art is served there
   since 2026-10-02), not on a dev server.
