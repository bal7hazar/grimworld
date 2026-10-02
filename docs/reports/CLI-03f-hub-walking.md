# [Opus 5.5] CLI-03f — hubs as zones (D-202)

## Summary

The town and the outpost are now lived like the seed's exploration zone. A hub opens in the zone's
own engine: `RoomSandbox`, `SandboxController`, `SandboxSession`, `wiring.ts` and `Renderer`. It
has the same hex map, camera (follow, pan, pinch and wheel zoom, ◎), zoom levels, scale modes,
tile drawing, finder, step, turn and tween.

- A pure `hubWorld(view, at)` turns a hub's fixtures into a `SandboxWorld` of kind `"hub"`.
- The buildings and props stand on wall hexes as structures drawn by the zone's renderer.
- A tap on a building walks to its door with the zone's finder, then opens the place.
- The service row still opens a place at once.
- The Gate is a place. CLI-03d's arrival rule and D-148 are unchanged.

This replaces the light variant this pull request first carried (#319 before D-202): its own walk,
its own breadth-first search and `HubRenderer` are gone.

Nothing is on chain. The adventurer's hex inside a hub is presentation: never sent, checked or
stored (D-03, D-196, D-202).

- Pull request: https://github.com/bal7hazar/grimworld/pull/319
- Model: Opus 5.5, as the brief names.
- Audit: none (D-177). Owner's eye: on the public site after the merge (AC-13).

## The eight design choices, as built

1. **The zone's engine, as is.** `HubScreen` is a sibling of `InstanceScreen`: `RoomSandbox` on
   `hubWorld`, with the hub's labels, the inspection card and the service row.
   - Nothing of the zone's engine is forked: the controller, session, renderer, gestures, camera,
     `DEFAULT_ZOOM`, scale modes, `STEP_MS`, `TURN_MS`, `CAMERA_MS`, ghosts, ◎ and the debug panel
     are the zone's.
   - The camera opens centred on the adventurer at `DEFAULT_ZOOM.defaultAcross` (13).
2. **A hub's content as a zone's content** (`sandbox/fixtures/hubWorld.ts`):
   - Terrain: whole 15 × 15 chunks over the island, all revealed. The town is 15 × 30 (1 × 2
     chunks, 117 floor hexes); the outpost is 15 × 15 (70 floor hexes).
   - `floor` is the island: a hex whose centre is at least half a hex inside CLI-03e's rectangle.
     `wall` is everything else, plus every building's footprint and every prop's hex. A place's
     door stays `floor`.
   - Actors: the player's adventurer (id 1) on `at`, and each present figure on its hex. A figure
     facing `"left"` faces West (3), one facing `"right"` faces East (0); none has a mark.
   - Structures: one per place, decor building and prop, with the wall hexes each one covers.
3. **What a hub does not inherit.** `SandboxWorld.kind` (`"zone"` by default) is read by
   `wiring.ts` and, for the counter, by `Sandbox.tsx`; no other module reads it. In a hub:
   - every tile is in sight and every actor is seen;
   - nothing is revealed and no stop condition is evaluated;
   - the path is not bounded by the D-120 window;
   - a tap on an actor selects nothing (no arcs);
   - `RoomSandbox` shows no walk counter.
4. **The zone's finder, without the window.** `findPath` takes an optional last parameter,
   `bounded = true`. The wiring passes `false` for a hub only. The project manager accepted it on
   2026-10-02 on two conditions, both met:
   - The default keeps every zone path exactly as today. The room's tests are unmodified. A new
     test compares, tile for tile, every zone fixture's tap path through the wiring with the
     bounded finder's.
   - Only the hub world passes it: the wiring's one call reads the world's kind, and no zone
     caller passes it.
5. **Taps.** `RoomSandbox` and `SandboxController` take an optional `route(intent)`, applied before
   the session. The hub screen's route is `HubDoors.route`, built on the pure
   `hubTap(view, tile)`:
   - a hex of a place's footprint, its door included, becomes a tap on the door, and the place
     becomes the walk's goal;
   - a figure's hex inspects it, on a tap or a long press;
   - a decor building's or a prop's hex does nothing but log one line;
   - anything else is the zone's own tap.

   The goal opens when the walk ends on its door, once and `stepMs` later, so that the last step is
   drawn first. Otherwise:
   - standing on the door, a tap opens at once;
   - a walk that passes over a door opens nothing;
   - a new tap clears the goal;
   - a door with no path opens at once and the log says why (none in the fixtures: every door is
     reachable);
   - the service row opens at once. Leaving the hub screen unmounts the room, which ends the walk.
6. **Structures drawn by the zone's renderer.** `ViewState.structures` comes from `toView` (empty
   for a zone).
   - The renderer draws each structure in the actors' layer, its base on its hex's centre. It uses
     the atlas's `still` at native size, or a shape without it: CLI-03e's building shapes, moved
     into `render/shapes.ts`, plus a bush for a prop.
   - Structures sort with the actors by the y of their base. On the same row, an actor stands in
     front, since its feet are below the centre.
   - A wall hex under a structure draws no rock: `drawTerrain` takes the covered hexes, and a zone
     passes none.
   - Structures never move and ask for no frame.
   - The ground is the zone's plain ground and grid. The textured ground is the next lot, not this
     one.
   - The labels are HTML. After each drawn frame they are placed from the camera, above the
     building's height, and they take no tap.
7. **Arrival, the Gate, D-148, the arrival rule.** The arrival hexes are #319's.
   - Arriving opens nothing. The Gate's door ends a walk on the Gate screen.
   - `hubGateAt`, `entryThrough` and `hubAfter` are unchanged. The instance's `leaveOffer` and
     `gateHere` are untouched.
   - The machine keeps `at` on the hub, service and Gate screens. The hub screen answers the zone's
     `moved` (`stood` is gone); a `moved` on the same hex returns the same state.
8. **design/11 *Hubs*, first line**, written exactly as the brief gives it, under D-178's lending.

## Reused and dropped, as built

| From | Reused | Dropped |
|---|---|---|
| CLI-03e (main) | Places, decor, props, figures and their hexes; `BUILDINGS`; the atlas's stills (roles `building`, `prop`); the services; `targetLabel`, `targetIntent`, `figureIntent`; the service row; the building shapes (now in `render/shapes.ts`); the sort rule (y of the base, then a stable key) | `render/hubRenderer.ts` and its tests; `hubFit`, `placeRect`, `figureRect`, `overlap`, `MIN_TARGET`, `tileScreen` and their tests; `HubGround`, `groundCell`, `groundCells`, `standingOrder`, `feetPoint`, the water backdrop, `PATH_ALPHA`, `SHOW_GRID`; the fixtures' `ground` (tileset, water, drawn path); the HTML place and figure buttons over the canvas |
| #319's branch | `arrival` (town `(2, 0)`, outpost `(1, 1)`); `depth` and its two zeros (the Market, the straw hut); the island's half-hex rule (`EDGE_MARGIN`); `footprint`; the machine's `at` and its tests; the door rules; the walking pass of `verify-hubs.mjs`, adapted | `input/hubWalk.ts` and its tests; `neighbours` in `input/coords.ts` and its test; the walker, tween and target marker; `hubTile`; `WalkedHub` and `HubWalkerView` (`arrival` is now required on `HubView`); `stood`; the imports-test assertion on `hubWalk.ts`; its design/11 line; its report (this file, rewritten) |

No dependency added.

## Files

- Added:
  - `client/app/src/sandbox/fixtures/hubWorld.ts` (`hubWorld`, `hubTap`, `footprint`, `onIsland`,
    `onDoor`) and its test;
  - `client/app/src/sandbox/loop/hubDoors.ts` (`HubDoors`) and its test.
- Removed: `client/app/src/render/hubRenderer.ts` and its test; `client/app/src/input/hubWalk.ts`
  and its test (#319's).
- Changed:
  - `sandbox/world.ts` (`kind`, `structures`), `sandbox/wiring.ts` (the hub kind),
    `sandbox/placeholders.ts` (§4's parameter only), `sandbox/controller.ts` (`route`, frame
    listener, `tileOnScreen`, `scale`, `atlasState`, `structureFromAtlas`), `sandbox/Sandbox.tsx`
    (`route`, `onFrame`, no counter in a hub, `data-*` for the check);
  - `render/view.ts` (`ViewStructure`, `structures`), `render/renderer.ts` (structures, covered
    hexes, `STILL`), `render/shapes.ts` (`drawStructure`, covered hexes in `drawTerrain`),
    `render/hubView.ts` (data types only), `input/hubTaps.ts` (`targetIntent`, `figureIntent`
    only);
  - `sandbox/fixtures/hubs.ts` (no `ground`), `sandbox/loop/HubScreen.tsx` (rewritten on
    `RoomSandbox`), `sandbox/loop/machine.ts` (`moved` on the hub screen), `sandbox/loop/Loop.tsx`
    (no `scale` prop: the room reads it from the URL as in the instance);
  - `client/app/verify-hubs.mjs`, `docs/design/11-interface.md` (the first line of *Hubs*).
- Restored to main: `input/coords.ts`, `input/coords.test.ts`.

## Measures

| Hub | Arrival | Farthest hex from the arrival | Doors (steps from the arrival) |
|---|---|---|---|
| Town A | `(2, 0)` | `(0, 12)`: 17 steps, 3.06 s at 180 ms | Gate 1, Vault 2, Market 4, Alchemist 7, Smith 9, Armorer 9, Trainer 11, Guild 14, Enchanter 16 |
| Outpost B | `(1, 1)` | `(0, 10)`: 13 steps, 2.34 s | Gate 1, Vault 5, Guild 7, Trainer 7 |

- The `depth` values are #319's: 1 everywhere, except 0 for the town's Market and the outpost's
  straw hut. No fixture moved: every door is reachable (tested).
- A hex at the default zoom is 28.8 points across at 375 × 812 and 33.1 at 1440 × 900 (the browser
  check, `data-camera`). Under #319's `hubFit` the town's hex was 34.1 at 375 × 812.
- The zone's finder walks the town's Guild in 14 steps from the arrival hex, against #319's 16.
  The pinned path is in `hubWorld.test.ts`.

## Browser check

On the VPS, headless Chromium 153.0.8010.12. The atlas was built by `python3 tools/art/build.py`
with `assets` linked to `/home/claude/projects/assets` by an uncommitted symlink, removed
afterwards (the empty folder restored). The command:

    VERIFY_SHOTS=1 VERIFY_SHOTS_DIR=<thread library>/shots node verify-hubs.mjs

Result: `ALL CHECKS PASSED`, 130 `ok` lines and no `FAIL` line (the CLI-03c/03d loop at both
sizes, the hub shots, and the walking pass). The walking pass, quoted from the run:

    ok   walk town 375x812: the adventurer stands on 2,0 on arrival
    ok   walk town 375x812: arriving opens nothing
    ok   walk town 375x812: a hex is 28.8 points across at the default zoom
    ok   walk town 375x812: no walk counter in a hub
    ok   walk town 375x812: walked to 6,3 (937 ms)
    ok   walk town 375x812: the camera followed (0.0 px off the centre)
    ok   walk town 375x812: data-frames stops growing once it stands (77)
    ok   walk town 375x812: Smith: walked (844 ms), then opened
    ok   walk town 375x812: back, still on the Smith's door
    ok   walk town 375x812: walked to the Gate: the Gate screen
    ok   walk town 375x812: back, on the Gate's door
    ok   walk town 375x812: nothing reopens on the door
    ok   walk town 375x812: the service row opens the Vault at once, mid-walk
    ok   walk town 375x812: the wheel zooms in (0.451 → 0.821)
    ok   walk town 375x812: a drag pans
    ok   walk town 375x812: ◎ brings the camera back to the adventurer (0.0 px)

The outpost and 1440 × 900 lines read the same; the Trainer is the outpost's place. At 1440 × 900
the hex is 33.1 points and the wheel zooms 0.517 → 0.942.

The shots are in the thread's library folder: never committed, attached or posted (D-73). In
words:

- each hub shows the zone's plain green hex ground with its grid, and the buildings and props of
  CLI-03e on their hexes;
- the zone's rocks fill the wall hexes outside the island on the chunk's far side (West and
  North);
- the adventurer stands in the camera's centre, and the places' names float above the buildings.

How the check changed (only where it checked the light variant):

- The loop pass opens the Gate screen from the service row: the building buttons are gone.
- The hub pass reads `data-atlas` and `data-frames` on the room.
- The walking pass finds hexes through the room's camera (`data-camera`) instead of the fit's
  grid. It reads `data-tile` and `data-walking` instead of `data-walker`, and runs with `idle=0`,
  since idle animations draw frames by design.
- New checks: no counter, the camera's follow, the service row mid-walk, the wheel zoom, a pan
  and ◎. The instance also exposes `data-frames`.

## Tests updated or removed, and why

- Removed with the code they tested: `render/hubRenderer.test.ts` (`HubRenderer`, the fit),
  `input/hubWalk.test.ts` (#319's walk), and the fit tests of `input/hubTaps.test.ts`.
- `render/hubView.test.ts`: the standing order, ground cells, `feetPoint` and drawn-path checks
  are removed with their code. The pieces-on-hexes, no-shared-hex, sizes and atlas-names tests
  stay, without the ground tileset.
- `input/coords.test.ts`: restored to main (`neighbours` removed).
- `sandbox/loop/machine.test.ts`: #319's tests kept, with `stood` renamed `moved`. One assertion
  added: the same hex returns the same state.
- `sandbox/imports.test.ts`: the "decide nothing" list replaces the removed `hubRenderer.ts` by the
  zone's `renderer.ts` and `shapes.ts` (one more file guarded). Added:
  - the hub kind is read by `wiring.ts` and `Sandbox.tsx` only;
  - `hubWorld.ts`, `hubDoors.ts` and `HubScreen.tsx` import nothing from the placeholders;
  - no hub symbol is in `placeholders.ts`;
  - `hubWorld.ts` and `hubDoors.ts` are added to the no-randomness, no-clock list.

  No guard is loosened. Shown red on a seeded violation (an import of `findPath` in
  `hubWorld.ts`: three guards failed) and green once it was removed.
- `sandbox/placeholders.test.ts`: one test added (an unbounded path across 25 rows).
- Unmodified and green: `walkFollowsPreview`, `wiring`, `session`, `renderer`, `placeholders` (but
  the one added test), and CLI-03c and CLI-03d's tests (InstanceScreen's arrival rule, the
  machine's instance cases).

## `git diff origin/main -- client/app/src/sandbox/placeholders.ts`

```diff
@@ -160,6 +160,10 @@ export const TICKS_PER_STEP = 1;
  * the window around `from` and off its outer ring (D-120, `insideRing`). Null when there is none,
  * or when `to` is `from`. A breadth-first flood from `to`, bounded by the window's 240 tiles.
  *
+ * `bounded` false lifts the window bound (CLI-03f): the window bounds the chain's tick, and a hub
+ * has no tick and nothing on chain (D-03). The flood is then bounded by the terrain (outside is
+ * wall, D-134). Only the wiring passes it, for a hub; every zone path keeps the default.
+ *
@@ -169,9 +173,10 @@ export function findPath(
   actors: readonly ViewActor[],
   from: Tile,
   to: Tile,
+  bounded = true,
 ): Tile[] | null {
   const free = (tile: Tile) =>
-    insideRing(from, tile) &&
+    (!bounded || insideRing(from, tile)) &&
     kindAt(terrain, tile) === "floor" &&
     !actors.some((a) => sameTile(a.tile, tile));
```

## Commands refused by the profile

- `git config core.hooksPath` (read-only).
- Several compound commands mixing `git`, `cat` or `sed` on the tool-results folder.
- `git -C <worktree> rev-parse …`.

Each was replaced by a single allowed command.

## Deviations

- `ViewState.structures` is optional (`toView` always sets it), so that the renderer's tests, which
  write views by hand, pass unmodified.
- `ViewStructure` carries `covers` (the wall hexes it stands on) and an optional `shape` (house,
  decor, gate) for the drawing without the atlas. The brief's list did not name them.
- A prop without the atlas draws a bush shape: CLI-03e drew nothing, which would now leave an empty
  wall hex.
- The goal opens `stepMs` after the walk's last step, so that the step is seen. The brief says "when
  the walk ends".

## Escalations and open questions

- design/11 *Hubs*: the sketch under the first line still says "illustration of the town with its
  buildings" and "present adventurers walk by". It contradicts the new first line; not edited
  (§8).
- The owner's eye (AC-13): the wall hexes outside the island draw the zone's rocks on the chunk's
  far side, and nothing (the void) past the near edges.
- Q2 (the ground's look), Q4 (the feel) and Q5 (the keyboard) keep the brief's defaults.
