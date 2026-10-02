# CLI-03f — Walking in the hubs: the adventurer walks the hub's hex grid, client-side

**Status: ready to start.** CLI-03e merged as #307, so the hubs already stand on the hex grid. Branch
from `main`.

Written for the orchestrator of track CV on 2026-10-02, from **D-196**. The owner said, through the
project manager: "I want to keep the hex-map mechanics (even if it is entirely client-side, since the
player's position needs no on-chain verification)." The orchestrator's reading, corrected by the
project manager, is that the hubs are walked on the hex grid, client-side, and that the tap menus may
sit on top. CLI-03e laid the hubs on the instance's grid but added no movement. Today a hub is tapped,
not walked. This lot adds the walking.

## Agent

Profile: `impl-opus`. The lot is presentation with design judgement: a walk on the hub, its
animation in a renderer that draws on demand, the machine's hub state and the browser check. It also
touches five modules that must keep their tests green.

Branch: `cv/cli-03f-hub-walking`.

Machine: **the Mac** (`--machine mac`, repo `/Users/bal7hazar/git/grimworld`). The lot commits no
pin, gas table or fingerprint. The browser check and the atlas build also run there, as for CLI-03d.

## Goal

After this task, the player's adventurer stands in the town and in the outpost and walks their hex
grids:

1. **The adventurer is drawn in the hub**, at the room's scale, on a hex, and appears where it
   arrives.
2. **A tap on the ground walks it there**, one hex per step, along a short path around the buildings
   and props. It faces the way it goes, as in a room.
3. **A tap on a building walks it to the building's door, then opens the place.** The tap menus
   stay on top: the service row under the illustration opens a place at once, and the present
   adventurers are still inspected by a tap.
4. **The Gate is left by walking to its door**, which opens the Gate screen. The CLI-03d arrival
   rule is unchanged.

Everything is client-side. The chain only knows which hub an adventurer is in (D-03). The position
inside a hub is presentation (D-196) and is never sent, checked or stored.

## Context

- **D-196** (`docs/decisions/2026-10-02-cli-03c-visual.md`) and the correction of its reading (above).
- **The house style and the lots before this one**:
  - `docs/briefs/CLI-03c-hubs.md`: the loop, the screens, the intents.
  - `docs/briefs/CLI-03d-hubs-followup.md`: the arrival rule, `gateHere` and `leaveOffer`.
  - `docs/briefs/CLI-03e-hubs-visual.md`: the hex grid, one scale, the standing layer, the
    labels and the 750-art-pixel width budget.
- **design/11 *Hubs***, as CLI-03d and D-194 leave it:
  - the five accepted lines: the outpost's services, the entry moment, the closing report, the
    present adventurers standing still, where the buildings stand;
  - the arrival rule's line ("never automatically on arrival").
  - Its first line says "Hubs have no geometry (D-03): they are illustrated screens with places to
    tap". See *Open questions* §1.
- **D-148** (`docs/decisions/2026-09-29-eng-06-lifecycle.md`): a gate is used by standing on its
  anchor tile, and the client walks the adventurer onto it. The hub gates out of the town (the seed's gate 1) and
  the outpost (the fixture's gate 101) have anchor `0/0`, because a hub has no map. Their
  anchors mean nothing in a hub. See *Design choices* §5.
- **D-03 and the indexer's scope** (`docs/decisions/2026-09-28-indexer-scope.md`, question 2): the
  chain knows only who is in which hub. Live movement of other adventurers in a hub is cosmetic and
  needs a relay (Q-09, Phase 5, not in the MVP). **Only the player's own adventurer walks.**
- **The mandate** `docs/briefs/ORCH-client-visual.md`:
  - §1 for the paths;
  - §4 (D-73) for the art;
  - §6, binding: no rule in `client/app` outside `sandbox/placeholders.ts`; the renderer's input is
    a view state; a tap produces an intent; rendered on demand, no render loop; no randomness and no
    clock in what `client/sim` will decide.
- **Phone work is suspended** (owner, 2026-10-02). The design stays mobile-first: it is checked in
  the browser at 375 × 812 and on a desktop window, and nothing runs on a device.

### What main has today

- **The instance's walk** has several parts:
  - `sandbox/wiring.ts`: `applyIntent` plans a path on a tap (`findPath`), plays on the tap or
    previews it (`playOnTap`), and `walkStep` plays one step through `stepToward` and evaluates the
    stop conditions of design/02.
  - `sandbox/session.ts`: `SandboxSession` walks the planned queue on the host's timers, one step
    every `stepMs`. It pauses while the page is hidden and resumes after.
  - `render/renderer.ts`: the step's tween (`STEP_MS` 180), the turn (`TURN_MS`), the camera's
    follow (`CAMERA_MS`) and the `move` animation while stepping.
  - `render/facing.ts`: six facings, mirrored for West.
  - `sandbox/walkFollowsPreview.test.ts`: the walk stays on the preview, through the same path a
    browser tap takes.
  - Every rule in this chain is a placeholder (`findPath`, `stepToward`, `neighbour`, sight, the
    window of D-120). CLI-03 replaces them with `client/sim`.
- **The hub** has the following parts:
  - `render/hubView.ts`: `HubView`, `hubPoint` and `feetPoint` on the room's `tileToPixel`, and the
    standing layer sorted by base y (`standingOrder`).
  - `render/hubRenderer.ts`: the ground baked once, the standing layer, and drawing only on a
    change. Figures are drawn at their idle frame 0, so the hub has no tween.
  - `input/hubTaps.ts`: `hubFit` fits the whole illustration in its zone at one factor;
    `placeRect` and `figureRect` give the tap targets; `targetIntent` gives a tap's intent.
  - `sandbox/loop/HubScreen.tsx`: one HTML button per place and present figure over the canvas, and
    the service row below.
  - `sandbox/fixtures/hubs.ts`: the town (704 × 960 art px, 9 places, 3 decor buildings, 14 props,
    3 figures) and the outpost (576 × 704, 4 places, 2 decor, 11 props, 1 figure). Every one stands
    on a tile. The ground path is drawn only, not walked.
  - `sandbox/loop/machine.ts`: the hub screen is `{ kind: "hub", hub, inspected }`. It has no
    position. The service and Gate screens replace the hub screen, so `HubScreen` unmounts when a
    place opens.
  - `client/app/verify-hubs.mjs` (`pnpm --filter @grimworld/app verify:hubs`): the loop walked in a
    headless browser, with screenshots only under `VERIFY_SHOTS`, untracked.
- **The player's adventurer is not drawn in a hub.** `ADVENTURER` (Wren, vanguard) is shown on the
  Gate screen only.

## Scope and non-goals

- **In**:
  1. The player's figure in each hub, on a hex, drawn at its native size in the standing layer.
  2. A hub walk: which hexes are walkable, a path to a tapped hex, steps on the host's timers with
     the room's step animation and facing, retargeting by a new tap, and a pause while the page is
     hidden.
  3. Taps: ground walks; a building walks to its door, then opens; the service row opens at once;
     a figure is inspected (unchanged).
  4. The machine keeps the adventurer's hex across a hub's screens (a service, the Gate screen,
     back).
  5. The fixtures: an arrival hex per hub, and which hexes each building blocks.
  6. Tests, and the browser check extended to walking.
- **Out (non-goals)**:
  - Anything on chain: no entrypoint, no event, no seed change, no position sent or stored.
  - Any game rule. The hub walk decides nothing the chain decides (*Design choices* §1).
    `placeholders.ts` is not changed and no hub symbol is added to it.
  - `client/sim/**`, `contracts/**`, accounts (`client/app/src/account/**`, `client/app/src/chain.ts`).
  - Other adventurers walking: they stand still (D-194). Their live movement needs a relay (Q-09).
  - Moving a building, a prop or a figure. The positions are CLI-03e's, accepted as proposed.
  - A camera that pans or follows in a hub (*Design choices* §6).
  - The keyboard (design/11 *Desktop*'s `Q W E A S D`): the client has no keyboard input yet, and
    one later lot can bring it to the room and the hub together (*Open questions* §6).
  - Idle animations in a hub. A figure is animated only while it steps.
  - Remembering the position across a reload or a later visit.
  - The client's chrome from the pack's `UI Elements/` (the later chrome lot), the service screens
    (CLI-06, CLI-07) and the world map (CLI-08).
  - Phone builds, simulators, devices (suspended).
  - `docs/design/`. design/11's first line is the project manager's to route (*Open questions* §1).

## Design choices

Each choice gives a recommendation, its reason, and what would reverse it. Where the choice is
aesthetic (pace, marker, arrival hex), it is a constant or a fixture value, for the owner's eye.

### 1. Reuse the instance's walk, or a lighter hub walk

**Recommended: a lighter hub walk that reuses the room's presentation pieces but none of its rules.**

The hub walk reuses:

- `input/coords.ts` for the grid;
- `render/facing.ts` and the `move` animation for how a step looks;
- `STEP_MS` as the default pace;
- the pattern of `SandboxSession` for the timers: steps on injected `WalkTimers`, a pause while
  hidden, and nothing scheduled once the walk ends.

It does **not** reuse `wiring.ts`, `placeholders.ts` (`findPath`, `stepToward`, `neighbour`) or the
room's `Renderer`, for these reasons:

- **They are stand-ins for rules that `client/sim` will own.** CLI-03 deletes `placeholders.ts`, but
  the hub walk outlives it: a hub's position never reaches the sim or the chain. A hub walk built on
  them would have to be rewritten at CLI-03, or would make the sim answer a question the chain never
  asks.
- **Most of the room's walk does not apply in a hub.** A hub has no fog, sight, chunk reveal,
  goblins, stop condition, tick cost or queue counter. The D-120 window (15 × 16, with its outer
  ring as wall) would also forbid the hub's edge hexes for no reason.
- **The room's `Renderer` draws a different scene.** It draws tiles, fog and chunk bakes. The hub's
  renderer draws a baked pack ground, a sorted standing layer and HTML labels, and CLI-03e's tests
  pin it. Adding a tween for one figure to `HubRenderer` is smaller than teaching the room's
  renderer the hub.

The geometry is shared. The six neighbours of a hex are presentation (pointy-top, odd-r, the
library's numbering, mandate §6.2). They go into `input/coords.ts` as `neighbours(tile)`, tested
equal to `test/hexxLibrary.ts`'s `libraryNext` for the six directions on even and odd rows.
`placeholders.ts`'s `neighbour` is left alone: it stays the stand-in the sim replaces.

**Path**: a breadth-first search over the hub's walkable hexes, with a fixed tie-break (lowest
`y`, then `x`, as the room's reading). It is deterministic, so a test pins a path. It is not a rule:
nothing else depends on which of two equal paths is walked.

**No preview, no confirmation, no counter**: a tap walks at once (design/11's play-on-tap default).
A hub walk costs nothing and can be undone by another tap. The tapped hex carries a faint target
marker while the walk lasts (`HUB_TARGET_ALPHA`, a constant, for the owner's eye). The steps not yet
walked are not drawn.

**Retarget**: a tap during a walk plans a new path from the hex the adventurer is stepping to,
after the step in progress ends. Another place opening (the service row, a figure's inspection)
ends the walk where it stands.

**What reverses it**: the project manager rules that the hub walk is a rule after all, for example
because a later relay (Q-09) must replay the same paths. It would then move to `client/sim`
through a `PENDING-cv-hub-walk.md` (*Open questions* §2).

### 2. A tap on a building

**Recommended: walk to its door, then open.** The door is the place's anchor hex (`HubPlace.at`).

- When the walk ends on the anchor, the place's existing intent is dispatched (`targetIntent`):
  `open service` or `open gate screen`. The machine's intents do not change.
- If the adventurer already stands on the door, the place opens at once.
- A walk that passes over a door without ending there opens nothing. A walk to a ground hex that
  happens to be a door opens that place, so tapping the doorstep or the building gives the same
  result.
- If no path to the door exists (it should not happen: a test asserts every door is reachable from
  the arrival hex), the place opens at once and the log says why.
- **The service row opens at once**, with no walk. This keeps the tap menus on top, a one-thumb
  shortcut (I-1) and a way that never waits on an animation (accessibility).

Reason: this is the mechanic the owner kept, the adventurer going to the place. It is bounded: the
longest walk in the town, from the arrival hex to the Guild's door, is about 12 steps, or about
2.2 s at 180 ms a step. That figure is an estimate from the fixture's coordinates, not a
measurement; the thread measures it and reports it.

**What reverses it**: at the owner's eye, "open at once with the figure walking behind the menu" is
one branch in `HubScreen` (dispatch on tap, walk unseen). Both are cheap. The default is the one
that shows the walk.

### 3. Where the adventurer starts

**Recommended: on an arrival hex per hub, `HubView.arrival`: the path hex next to the Gate's door,
on the town's side.** In the town the Gate's door is `(1, 1)`. Its neighbour `(2, 1)` holds a rock
(`rock-2`), so the thread takes the nearest free path hex beside the door, on row 0 or 1, and says
which hex it took.

- Every arrival puts the adventurer there:
  - the first hub of the loop (`hubState`);
  - the hub a closing report leads to (`close report`), whatever the outcome: returned, travelled
    back or defeated.
- Arriving never opens a place and never starts a walk.

Reason: the hub is entered through its Gate, so arriving beside the Gate reads right. Not arriving
**on** the Gate's door avoids the trap CLI-03d closed in the instance (an offer at arrival). The
door rule of §2 already ignores arrival, so this is belt and braces, and it keeps the figure out of
the watchtower's base.

**What reverses it**: the owner wants another hex (a fixture value), or a different hex per way of
arriving (defeat at the Guild, for example). That would be a branch on the report's `how` in the
machine: a constant table, still no rule.

### 4. Collisions with buildings and props

**Recommended: a hex is walkable when its centre lies on the grass inside the island, and nothing
blocks it.**

- **Grass**: not on the ground's border cells, where the tileset's edges meet the water.
- **Buildings**: a building blocks the hexes of its ground footprint, which are:
  - its base row, `ceil(width / TILE_WIDTH)` hexes centred on the door;
  - `depth` rows behind it (a fixture value per building, default 1).

  **The door itself stays walkable**, since it is where the adventurer stands to open the place.
  Decor buildings block the same way and have no walkable door.
- **Props**: trees, stumps, rocks, bushes and sheep block their hex.
- **Present figures**: they block their hex, as actors do in a room, and are still inspected by a
  tap.
- **The ground path is not a constraint**: the adventurer may walk on grass anywhere free. The path
  stays drawing only.
- **Behind a building**: a figure walking behind a building's roof is drawn under it by the standing
  layer's sort (CLI-03e §5). That is the intended depth, not a collision.

The blocked set is computed from the fixtures by one pure function (`hubWalkable(view)`), not
listed by hand. Tests assert that:

- no path enters a blocked hex;
- every place's door is reachable from the arrival hex;
- the arrival hex is free;
- each hub has at least one walkable hex per place door.

**What reverses it**: the owner finds a hex wrongly open or closed. That is a `depth`, or an extra
`blocks` list on a building in the fixtures: a fixture value.

### 5. Leaving by the Gate, D-148 and the arrival rule

**Recommended: the hub's Gate behaves like every place.** A walk ending on the Gate's door, or a tap
on the Gate building or on "Gate ▸" in the service row, opens the **Gate screen**. The Gate screen
is unchanged (the gates, the build, the belt, the last check, then *Leave* → `enter gate`, the entry
moment, the instance).

- **D-148 is respected in spirit and untouched in the data.**
  - D-148 governs gates whose anchor is a tile of a location with a map. A hub has no map in the
    seed, so its gates' anchors (`0/0`) are not placed on the hub's grid, and the hub's Gate door is
    a **client fixture hex**, not a seed anchor.
  - Standing on the Gate's door to open the Gate screen is the client's analogue of "used by
    standing on its anchor". It decides nothing: entering is still the Gate screen's confirmed
    `enter gate`.
  - No seed change, and no change to `hubGateAt`, `entryThrough` or `hubAfter`.
- **The arrival rule is unchanged.**
  - In the instance, CLI-03d's `leaveOffer`, `gateHere` and the Leave control stay as they are.
  - In the hub, "never on arrival" holds by construction: arriving starts on the arrival hex, not
    the Gate's door (§3), and only a walk the player started can open a place (§2).
  - Back from the Gate screen, the adventurer still stands on the Gate's door and nothing reopens.
    Tapping the Gate again opens it at once (§2).
- **The imports test keeps its guard.** The hub walk compares hub fixture hexes, never a seed
  gate's anchor. It does not import `sameTile`, `hubGateAt` or a record's `anchor_*` fields, and the
  allow-lists of `sandbox/imports.test.ts` do not grow for it. If the thread needs to compare
  tiles, it uses the walk module's own key, and the imports test gains one assertion: the hub walk
  module imports nothing from `placeholders.ts` or `fixtures/region.ts`.

**What reverses it**: the seed gives hubs a map and real gate anchors (a game decision). Then the
Gate's door becomes that anchor, through `hubGateAt` in `placeholders.ts`, as in an instance.

### 6. The camera on a hub larger than the screen

**Recommended: no camera in this lot. The whole hub stays fitted (`hubFit`), and the fit does not
change while the adventurer walks.**

- CLI-03e's width budget (at most 750 art pixels) guarantees the fit by width. Today's hubs fit
  their zone at 375 × 812 and at 1440 × 900.
- At 375 points the town's factor is about 0.53 point per art pixel, so a hex is about 34 points
  across its flats. That is an estimate from `375 / 704 × 64`, before the zone's padding; the thread
  measures it.
- Keeping the fit fixed keeps every HTML tap target still during a walk, which CLI-03e's tests and
  the overlap test rely on.
- A test asserts that every hex of a walk stays inside the zone, at both sizes.

**What reverses it**: a hub that no longer fits (wider than the budget, or taller than the zone at
375 × 812), or the owner wanting a closer view. A later lot then follows the adventurer with the
room's camera tween (`CAMERA_MS`), and moves the HTML targets with the camera.

## Allowlist

- `client/app/src/**` except `client/app/src/account/**`, `client/app/src/chain.ts` and their tests.
  The expected files are:
  - `input/coords.ts` (`neighbours`), and a new `input/hubWalk.ts` (walkable hexes, path, the
    walker on timers), with their tests;
  - `render/hubView.ts`, `render/hubRenderer.ts` (the player's figure, the step tween, the target
    marker);
  - `input/hubTaps.ts` (a ground tap to a hex: `hubTile(view, fit, point)`);
  - `sandbox/fixtures/hubs.ts` (`arrival`, `depth`);
  - `sandbox/loop/machine.ts`, `sandbox/loop/HubScreen.tsx`, `sandbox/loop/Loop.tsx`;
  - `sandbox/imports.test.ts`: one assertion added, none loosened.
- `client/app/verify-hubs.mjs`: the walking pass.
- `docs/reports/` for this lot's report.
- **Not in the allowlist**:
  - `sandbox/placeholders.ts` (unchanged);
  - `tools/art/**` (no new art role is expected: the professions' `move` strips are in the atlas
    already; if one is missing, escalate);
  - `client/app/package.json` and `pnpm-lock.yaml` (no dependency expected);
  - `docs/design/`;
  - `.github/`.
- Anything else is an escalation in the report, not an edit.

## Interfaces

- **Intents** (`input/intent.ts`): the loop's intents are unchanged (`open service`,
  `open gate screen`, `enter gate`, `leave`, `travel back`, `close report`, `inspect adventurer`,
  `back`, `skip entry`, `defeat now`).
  - A tap on the hub's ground is the existing map intent `{ kind: "tile", tile }`, handled by the hub
    walk, never by `wiring.ts`.
  - A building's tap is still `targetIntent(place.target)`, dispatched when the walk ends on the
    door (§2).
- **The machine** (`sandbox/loop/machine.ts`):
  - The hub, service and Gate screens carry `at: Tile`, the adventurer's hex in that hub.
    `hubState(hub)` and `close report` set it to the hub's `arrival`. `back` from a service or the
    Gate screen keeps it.
  - A new answer, `{ kind: "stood", tile }`, is accepted on the hub screen only. It updates `at`
    after each step, as `moved` does in the instance.
  - The machine stays pure: it records the hex and decides nothing about it.
- **`HubView`** (`render/hubView.ts`) stays the hub renderer's only input. New fields, all data:
  - `arrival: Tile`;
  - `depth` on a place and on a decor building (optional, default 1);
  - the walker, `{ profession, at, facing: Facing, target: Tile | null }`, filled by `HubScreen`
    from the machine and the walk. `facing` is a six-way `Facing` drawn with `isMirrored`.

  The present figures keep `facing: "left" | "right"`.
- **`input/hubWalk.ts`**, pure except for the walker's injected timers:
  - `hubWalkable(view): (tile: Tile) => boolean`;
  - `hubPath(view, from, to): Tile[] | null` (first step first, `from` excluded);
  - `stepFacing(from, to): Facing`;
  - a `HubWalker` class on `WalkTimers` (`sandbox/session.ts`'s interface, or a copy of its shape
    if importing it would pull the room's wiring), with `walkTo(tile, then?)`, `stop()` and
    `destroy()`.
- **`HubRenderer`**:
  - It draws the walker in the standing layer, sorted with the rest.
  - On a step, it tweens the walker from hex to hex over the step's duration with the `move`
    animation, and asks for frames only while the tween runs.
  - Once the walk ends, it draws nothing more. The ground is **not** baked again by a walk.

## Acceptance criteria

- [ ] AC-1 **The walker is drawn**:
      - in each hub, the player's figure stands on the arrival hex at arrival (a machine test for
        `hubState` and for `close report` after each of `gate`, `travel back` and `defeat`);
      - it is drawn at the room's height at the same factor (CLI-03e's AC-1 test extended to the
        walker).
- [ ] AC-2 **Walkable hexes and paths** (unit tests on both hubs):
      - no path enters a blocked hex (building footprints with `depth`, props, figures, the ground's
        border);
      - every place's door is reachable from the arrival hex;
      - the arrival hex is free;
      - `hubPath` is deterministic (a pinned path in the town);
      - `neighbours` equals `libraryNext` for the six directions on even and odd rows.
- [ ] AC-3 **Ground taps walk**:
      - a tap's screen point maps to the hex the renderer draws there (`hubTile`, through `hubFit`,
        at 375 × 812 and 1440 × 900);
      - a tap on a free hex walks to it one step per `HUB_STEP_MS` on fake timers, facing each step's
        direction;
      - a tap during a walk retargets after the step in progress;
      - a tap on a blocked hex or off the island does nothing but a log line;
      - the walk pauses while the page is hidden and resumes after (`FakeHost`).
- [ ] AC-4 **Buildings walk, then open**:
      - a tap on a place walks to its door, then dispatches `targetIntent` once;
      - standing on the door, a tap opens at once;
      - a walk passing over a door opens nothing;
      - the service row opens at once and ends a walk in progress;
      - no tap reaches a decor building or a prop (CLI-03e's test unchanged).
- [ ] AC-5 **The Gate and the arrival rule**:
      - a walk ending on the Gate's door opens the Gate screen;
      - arriving opens nothing;
      - back from the Gate screen keeps the adventurer on the door, and nothing reopens;
      - CLI-03d's arrival-rule tests in the instance pass **unmodified**;
      - `hubGateAt`, `entryThrough`, `hubAfter` and `placeholders.ts` are unchanged
        (`git diff --stat` in the report);
      - `imports.test.ts` is green with its new assertion (the hub walk imports nothing from
        `placeholders.ts` or `fixtures/region.ts`), shown red on a seeded violation, then removed.
- [ ] AC-6 **The position survives the hub's screens**: open a service, then back, and the adventurer
      stands where it was; open the Gate screen, then back, and likewise (machine tests).
- [ ] AC-7 **On demand**:
      - while a walk runs, frames are drawn;
      - once it ends, nothing is drawn (CLI-03c's on-demand test extended with a walk; no ticker
        left running);
      - a walk bakes the ground zero times (CLI-03e's bake count unchanged).
- [ ] AC-8 **The fit and the targets**:
      - the hub's fit does not change during a walk;
      - every hex of every walk stays inside the zone at 375 × 812 and 1440 × 900;
      - the tap targets keep at least 40 points and do not overlap (CLI-03e's tests unchanged).
- [ ] AC-9 **Mechanics unchanged elsewhere**:
      - the CLI-03c, CLI-03d and CLI-03e tests pass unmodified, except those that construct a hub
        screen without `at`, which are updated and listed in the report;
      - the room's tests (`walkFollowsPreview`, `wiring`, `session`, `renderer`) pass unmodified.
- [ ] AC-10 **The browser check** (`pnpm --filter @grimworld/app verify:hubs`, extended), on the Mac
      in headless Chromium, at **375 × 812** and **1440 × 900**, in both hubs, with the atlas built
      from this branch (`tools/art/build.py`, never committed). The check:
      - taps a ground hex, waits for the walk to end, and asserts that `data-frames` stops growing;
      - taps the Smith (in the town) and the Trainer (in the outpost): walk, then the service
        screen;
      - goes back, and asserts that the adventurer is still on the door;
      - walks to the Gate: the Gate screen;
      - runs the CLI-03c/03d loop as before;
      - fails on any page error.

      With `VERIFY_SHOTS=1`, a shot of each hub mid-walk and after it goes into the thread's library
      folder, **untracked**: never committed, attached or posted (D-73). The report describes them
      in words and gives the run's real output.
- [ ] AC-11 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `pnpm exec prettier --check client indexer` and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-12 **The owner's eye, last**: the orchestrator asks through the project manager once AC-1
      to AC-11 hold (*Open questions* §5).
      - The owner's answer is recorded in the pull request.
      - A change asked for that is a constant or a fixture value (pace, arrival hex, marker,
        `depth`) is a fix loop of this lot.
      - A change of mechanics is a new lot.

## Verification

- **On the Mac**:
  - the commands of AC-11;
  - `tools/art/build.py` with the pack (`git submodule update --init assets`, or
    `GRIMWORLD_ASSETS` as the README says);
  - then the browser check of AC-10.
- Start and stop the dev server inside one foreground command, and kill only its recorded process
  group (the script does this already).
- `scripts/prepush.sh` before every push, never `--no-verify`.
- CI is polled at most once per pull request every 5 minutes. Better: open the PR and end the turn.

## Review and audit

- **Review** by the other model, on the pull request's head: `review` (Sonnet) when the implementer
  is Opus, as recommended; `review-opus` if Sonnet. The reviewer works from the diff and the tests.
  It does not need the pack, and the owner's eye is the visual verdict. The review checks most
  closely:
  - that nothing in the hub walk is a game rule, or imports one;
  - that the arrival rule is untouched;
  - that drawing stays on demand.
- **Audit: none** (D-177: the owner sees the lot). The orchestrator decides otherwise if the thread
  adds a dependency, touches a path outside the allowlist, or changes `placeholders.ts`.

## Rules of this run

- D-73: nothing of the pack in a commit, the pull request, an issue, a comment or the report. Sizes,
  counts, paths and descriptions in words are fine.
- No pin is generated or committed.
- Foreground only. Never merge unless prompted with the exact line.
- External issues are named in words, not links, in commit messages and pull request text.
- Pull request title: `[<model>] CLI-03f walking in the hubs`. The body:
  - lists the six design choices as built, with any deviation;
  - names every dependency added (none expected);
  - says "Audit: none (D-177)" and "Owner's eye: requested through the project manager".

## Report

`REPORT.md` as in `docs/briefs/COMMON.md` §7, with:

- the summary and the pull request's URL;
- the files changed;
- the arrival hexes and the `depth` values chosen;
- the measured longest walk (steps and seconds) in each hub, and the hex size in points at 375 ×
  812;
- the browser check's commands and real output, and where the shots are;
- the tests updated for `at`;
- the commands refused by the profile;
- deviations, escalations and open questions.

## Open questions

1. **For the project manager: design/11 *Hubs*, first line.** It says "Hubs have no geometry
   (D-03): they are illustrated screens with places to tap", which walking contradicts in words
   (D-03 itself, that the chain knows only who is in which hub, still holds).
   - Default: this lot writes nothing in `docs/design/`.
   - Proposed line, if the project manager routes it (the game's design document, the lending of
     D-178 or a game pull request): "Hubs have no geometry on chain (D-03): the chain knows which
     hub an adventurer is in. The client lays each hub on a hex grid and the player's adventurer
     walks it (D-196); a place opens when the walk ends on its door, or from the service row."
2. **For the project manager: the hub walk is presentation, not a rule.** The brief puts it in
   `input/hubWalk.ts`, outside `placeholders.ts`, because no chain state depends on it and it
   survives CLI-03.
   - Default: as written, recorded in the PR.
   - What reverses it: a ruling that it is a rule (for example, if the later relay of Q-09 must
     replay the same paths for other players). It would then move to `client/sim` through a
     `PENDING-cv-hub-walk.md`.
3. **For the owner: a building's tap.** Walk to the door, then open (default), or open at once with
   the figure walking unseen. The service row opens at once either way.
4. **For the owner: the feel.**
   - The pace: `HUB_STEP_MS`, default `STEP_MS` (180 ms), the room's.
   - The arrival hex: beside the Gate, per hub.
   - The target marker: faint, on the tapped hex.
   - The blocked rows behind each building: `depth`, default 1.

   Each is a constant or a fixture value.
5. **For the orchestrator: where the owner looks (AC-12).** The published client
   (`grimworld.bal7hazar.com`, lot t-0059) builds **without the atlas** until the owner allows the
   art to be served (D-73 and the licence).
   - Default: the owner looks on the Mac's dev server with the atlas built from the branch, as for
     CLI-03c and CLI-03e.
   - Alternative: after merge, on the published client, if the art is allowed by then. Without the
     atlas, the walk is visible on the shapes.
6. **For the orchestrator: the keyboard.** design/11 *Desktop* gives `Q W E A S D` for the six
   directions. The client has no keyboard input yet.
   - Default: out of this lot. One later lot brings it to the room and the hub together.
   - Reverse: the owner asks for it at AC-12.
7. **For the owner: a ground hex is about 34 points at 375 points**, under I-6's 40.
   - The room already taps hexes smaller than that (about 29 points at 13 hexes across), so the
     brief reads I-6 as governing buttons and places, not the map's hexes.
   - Default: accepted, as in the room.
   - Reverse: the owner finds the hub's hexes hard to hit, which brings the camera of §6 forward.
