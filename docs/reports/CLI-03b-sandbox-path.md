# [Opus 5.5] CLI-03b — sandbox path

## Summary

Model read from my session: Opus 5.5 (`claude-opus-5-5`), the model the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/163 (branch `cv/CLI-03b-sandbox-path`, 2 commits after the brief). CI is green on every job; `client` passed in 43 s.

What exists now that did not before:

- **Sprites stand in their tile.** Every actor's body (atlas sprite or shape) has its feet below the tile's centre, by a fraction of the hex's inner radius. The rule is the same for every sprite. The fraction can be set in the debug panel ("feet below the centre (× inner radius)", next to the sprite scales) and with `?feet=<0..1>`.
- **`findPath`** in `sandbox/placeholders.ts`, marked `PLACEHOLDER until CLI-02`.
- **A planned path to a far tile.** A tap on a floor tile plans the path, shown as ghost markers plus a counter with the steps and the cost in ticks. The path is walked one step at a time, and the camera follows. The walk stops on the conditions of design/02 that the sandbox can evaluate: the remaining steps fade out and the reason is shown in one line. A tap on the counter cancels.
- The renderer stays on demand. Once a walk and its fade end, nothing more is drawn and no frame or timer is pending (tested).

## Files changed

- `client/app/src/sandbox/placeholders.ts`: `findPath`, `inWindow`, `WINDOW`, `TICKS_PER_STEP`.
- `client/app/src/sandbox/wiring.ts`:
  - the state gains `walking`, `dropped` and `stopped`;
  - a floor tap plans a path (walked or previewed);
  - `walkStep` plays one step and evaluates the stops;
  - `cancelWalk` and `pathCost` are new;
  - `toView` passes `dropped`.
- `client/app/src/sandbox/session.ts` (new): `SandboxSession`, the state over time. It sends intents through the wiring and walks on the host's timers, one step every `stepMs`. It has no DOM, so it can be tested with `FakeHost`.
- `client/app/src/sandbox/controller.ts`: delegates to the session. Adds `cancelWalk`, `setFeet`, `setPlayOnTap` and `listenToWalk` (the counter always listens; it changes only on a tap or a step).
- `client/app/src/sandbox/Sandbox.tsx`: the counter at the bottom centre (a 44 px button; a tap cancels) and the one-line stop reason. The panel gains the feet field and the "move played on the tap" checkbox.
- `client/app/src/sandbox/params.ts`: `feet`, `confirm=1` and `step=<ms>` (60–1000); `readFeet`.
- `client/app/src/render/renderer.ts`:
  - `DEFAULT_FEET`, `FEET_RANGE`, `feetOffset`, `setFeet` and `feetFraction`; `placeBody` places body and mark at the feet;
  - a `fading` layer for the dropped steps (`FADE_MS` = 400);
  - the `stepMs` option.
- `client/app/src/render/shapes.ts`: `drawGhosts`, shared by the planned path and the fading steps.
- `client/app/src/render/view.ts`: `ViewState.dropped`.
- Tests:
  - `sandbox/session.test.ts` (new);
  - `sandbox/placeholders.test.ts`, `sandbox/imports.test.ts` and `sandbox/params.test.ts` (extended);
  - `sandbox/wiring.test.ts` and `render/renderer.test.ts` (adapted and extended).

No dependency added; `package.json` and the lockfile are unchanged. Nothing of the art pack was used: the worktree has no `assets`, and the tests use shapes and the synthetic atlas.

## The foot offset rule and its default

- The feet sit `fraction × 32` art px below the tile's centre. 32 is the inner radius, half of `TILE_WIDTH` = 64.
- Default `DEFAULT_FEET = 0.5`, which is **16 art px**. At that value the shapes' shadow ellipse stays inside the hex, and the body's lowest part reads inside the lower half of its tile. This is a starting value for the owner to set by eye.
- The same fraction applies to every sprite and shape. It does not depend on the sprite's scale, because it places the feet, not the body's size.
- Only the body moves, and the mark with it (it stays at the same height over the head). The container stays at the tile's centre. So the following do not move:
  - the facing wedge (drawn at the centre);
  - the arcs' tints and the selection (drawn by the overlay, from tile centres);
  - the drawing order (`zIndex` is still the tile centre's `y`, by row).

## `findPath` and what it stands for

It stands for the chain's path finding: the map library's finder (`hexx-cairo`), the flood of the tick, and CLI-02's mirror.

- **Result**: the shortest path from `from` to `to`, first step first, with `from` left out. Null when there is none, and when `to` is `from`, is not floor, or is held.
- **Tiles it may use**: floor tiles no actor holds. Walls and unrevealed tiles are not floor.
- **Bound**: the D-120 window around `from`:
  - 15 columns, exactly centred (7 on each side);
  - 16 rows, starting on the even row among `y − 8` and `y − 7`. This follows D-120 §2, "the sixteenth row absorbs the vertical offset that the parity of the origin imposes". It is my reading of it, stated in `inWindow`'s doc.
- **Method**: a breadth-first flood from `to` over the window, at most 240 tiles. Then from `from`, each step goes to the neighbour closest to `to`; ties go to the lowest tile index (`y`, then `x`).
- **Cost**: `TICKS_PER_STEP = 1` tick a step. This is a placeholder, and the code says so.

## The walk and its stops

- **Default: move is played on the tap.** This follows design/11 *Confirmation* (I-5): "Move, attack: played on the tap". The ghost markers and the counter show the path, with "▶ n steps · n ticks ✕", while it is walked.
- **Tap twice** is the design's optional setting. It is available as the panel's checkbox (unchecked) or `?confirm=1`. The first tap previews, with "◌ n steps · n ticks ✕" and "tap the tile again to walk". A second tap on the same tile walks the path.
- **Timing**: the first step is played on the tap, then one step every `stepMs`. That is `STEP_MS` = 180 ms by default, the step animation's duration, set with `?step=`. The renderer's step animation uses the same value.
- **Each step** goes through the same placeholder step as a tap (`stepToward` to the next tile of the path). The step then reveals chunks, as a tap does.
- **Any new tap on the map ends the current walk or preview**: its remaining steps fade out. The tap is then applied as usual, so a far tap plans a new path from where the adventurer stands.
- **Stops the sandbox evaluates**:
  - **The next step is invalid**: the walk stops before it. The reason is "a runt stands in the way", or "the way is blocked" for a wall.
  - **A goblin enters sight**: the step is played, then the walk stops, for example "a skirmisher came into sight". Several are listed ("a runt and a shaman came into sight").
  - **A chunk is revealed**: the step is played, then the walk stops with "a chunk was revealed".
  - When one step triggers both, the two reasons are joined with "; " on the one line.
- **Not available in the sandbox**: damage, gaining a condition, a goblin becoming alerted or starting to activate a skill, and Fate actions. The sandbox has no rule for any of them, so they never stop a walk.
- **On a stop or a cancel**: the dropped steps fade from full to nothing over `FADE_MS` = 400 ms in their own layer. Frames are drawn only during the fade.

## Commands run

From the worktree root, on the Mac:

```
$ pnpm install --frozen-lockfile
Done in 2.9s using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  17 passed | 1 skipped (18)
      Tests  159 passed | 1 skipped (160)
(the skipped file is the existing account/burner.node.test.ts; before this task: 142 passed)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (no output: clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (no output: clean)

$ pnpm --filter @grimworld/app build
✓ built in 111ms
(!) Some chunks are larger than 500 kB after minification. …   (Vite's size warning, not an error)

$ pnpm exec prettier --check client indexer
All matched files use Prettier code style!

$ gh pr checks 163 --watch --interval 30
client  pass  43s   (every other job pass; indexer-node skipping)
```

## Cost

— (no Cairo).

## Acceptance criteria

- **AC-1**: `render/renderer.test.ts`, *the feet in their tile*.
  - For shapes and the synthetic atlas, the test runs every combination of: 3 scale modes (`continuous`, `snap`, `sharp`); feet 0, 0.5 and 0.8; the 6 facings; zooms of 4, 9, 13 and 25 tiles across.
  - It checks that the feet are on screen at `worldToScreen(tile centre + (0, offset))`, and the wedge on the tile's centre. It also checks, exactly in every mode, that the feet are straight below the wedge by `offset × scale`. `zIndex` is the row.
  - In `sharp` the absolute check allows half a pixel. That comes from the offscreen's whole-pixel size, which shifts the wedge the same way; it was already true before this task.
  - A second test checks that `setFeet` moves body and mark together, and leaves the wedge and the overlay (arcs, selection) unchanged.
  - The value can be set by eye in the panel and with `?feet=` (`params.test.ts`).
- **AC-2**: `sandbox/session.test.ts`.
  - *plays N steps one by one*: first step on the tap, then one per 180 ms; each step animates and is drawn; the counter's steps and cost count down; the camera ends centred on the target.
  - *with tap twice*: preview with path, cost and selected tile, and nothing played; a second tap walks.
  - *a tap on the counter cancels*: the fade animates, nothing more is played, and nothing is pending afterwards.
- **AC-3**: `sandbox/session.test.ts`, one test per stop. *A goblin enters sight* (meadow, walking north); *a chunk is revealed* (edge, walking west: it stops after the first step, and 3 steps are dropped); *an invalid next step*, with a goblin and with a wall. Each checks the one-line reason and the dropped steps.
- **AC-4**: `findPath` lives in `placeholders.ts` and is marked (the existing test checks every export's mark).
  - `sandbox/imports.test.ts` *is the only place that computes a path*: `findPath`, `stepToward` and `neighbour` are called only from `wiring.ts`; no other file walks the grid (no direction table, flood or visited set); no other file declares a finder, search, route or flood function.
  - `placeholders.test.ts` covers: a straight line, around a wall, around an actor, a long wall, no path (wall, unrevealed, held, start, walled in), the tie rule checked step by step, and the window bound (columns, rows on both row parities, a way that exists only outside the window).
- **AC-5**: `sandbox/session.test.ts`, *on demand: nothing is drawn once the walk has ended*. After an arrival (meadow) and after a stop with a fade (edge), the host is quiet, and 60 s more add no render, frame or timer. The existing renderer on-demand tests still pass.
- **AC-6**: the commands above; CI green on PR #163.

## What to look at in the browser

`pnpm --filter @grimworld/app dev`, then:

1. **`?fixture=meadow&panel=1`** at the default zoom and at a close zoom (the panel's "9 (close)"), in each scale mode. Every body should stand in its tile: the feet in the lower half of the hex, the wedge still at the centre and pointing at the front tile. Change "feet below the centre" (0 to 1, step 0.05) until it looks right; the URL is updated with `feet=`. Tap a goblin: the rear-side and back tints and the ring and cross must be on the right tiles. Tap a floor tile: the selection hex must be on that tile.
2. **Tap a far floor tile** (meadow, a few tiles east). The ghost markers appear and the adventurer walks at once, one step every 180 ms, with the camera following. The counter "▶ n steps · n ticks ✕" at the bottom counts down; tap it mid-walk to cancel, and the remaining markers should fade.
3. **Tap twice**: untick "move played on the tap" (or use `?confirm=1`). A tap previews with "◌ … tap the tile again to walk"; a second tap on the same tile walks.
4. **Stops**:
   - Meadow: walk north toward the sleeping pack. It should stop with "a … came into sight" and the rest fading.
   - `?fixture=edge`: walk 3 or 4 tiles west (to the left). It stops after one step with "a chunk was revealed". The fixture's initial three markers are a preview; tapping their last tile walks it.
   - The pace can be slowed with `?step=600` to watch each step.
5. **Power**: with idle animations off, "frames drawn … since last input" must stop increasing once the walk and its fade end.

## Deviations from the brief

- **The cost in ticks is shown in the counter**, not as a label on the map. Pixi text cannot be drawn in the node test environment, and the counter is the sandbox's minimal HUD. Design/11's "the path is drawn, with its cost in ticks" is met by the ghost markers plus the counter; the real HUD (CLI-05, CLI-08) can place it elsewhere.
- **"Tiles where the path would be interrupted are marked"** (design/11 *Acting*) is not done. The brief's preview asks only for the ghost markers and the cost. The placeholders could compute it (goblins do not act), if it is wanted later.
- **One foot offset for all sprites**, not a value per sprite. The brief says "the same rule for every sprite"; I read that as one value, set by eye.
- **"Play on first tap" is on by default**, as design/11 *Confirmation* says. The brief's first wording ("previews … a second tap walks") is the tap-twice setting.
- `ViewState` gains `dropped` (the steps to fade), a change of the renderer's input type.

## Escalations

None.

## Open questions

- **The window's row origin** in `findPath` is my reading of D-120: the even row among `y − 8` and `y − 7`, with no one-row hysteresis, because the window is not stored. The map library's check confirms "the window moves vertically by two rows" but not the exact rows. CLI-02's mirror should take it from the library.
- **The default feet fraction** (0.5) is not a decision; the owner sets it by eye.
- **The step pace** (180 ms, the step animation's duration) and the fade (400 ms) are initial values.

---

## Resume 1

Model: Opus 5.5 (`claude-opus-5-5`). Two commits added to PR #163 (`9342926`); CI is green on every job again (`client` 43 s).

### Summary

**Neither bug could be reproduced.** Both follow the browser's tap path (screen point → camera → tile → session → renderer) at 800 × 658 and 375 × 812:

- In the sandbox's code, **the walk follows the preview**, step by step, and the camera goes to the tile stepped to.
- **Every stop for sight names goblins** that enter `visibleActors` at that step and lie on screen at the default zoom.

I found no north/south mirror in `findPath`, `walkStep`, `stepToward`, the session, the renderer or the controller. `origin/main` has no change to `client/app` since the branch was cut, so what the owner ran is this code.

What I did instead of guessing a fix:

- tests that would catch the reported symptoms, and that fail when a mirror is planted;
- log lines and a panel line that show a mismatch the moment it happens.

**Asked of the next look in the browser**: the console lines of the faulty walk, the panel's new "adventurer at / camera on" line before and after it, and the URL (fixture, `scale=`, `confirm=`).

### Bug 1, the walk off the preview: what I checked

- From the meadow's start (9, 14), 3 tiles south-east is (7, 11). The preview is (8, 13) → (8, 12) → (7, 11), the three south-east neighbours of the map library's table, each lower and to the right on screen. The walk plays exactly those tiles:
  - in both tap modes;
  - through a screen tap at 800 × 658 DPR 2;
  - with the camera ending centred on (7, 11) (`tileToPixel`).
- A scratch sweep walked all 543 reachable targets of the three fixtures at 800 × 658. It found no step off the preview and no stop naming a goblin that was not drawn.
- **An inconsistency in the report as given**:
  - From the meadow's start, the shaman (#5 at (10, 20)) is already in sight, at distance 6, and is drawn. The fixture's `visibleActors` at the start is 1, 5 and 6.
  - A walk from the start, in any direction, cannot make it "come into sight". A walk south-east takes it out of sight at the first step.
  - So the walk seen must have started elsewhere (after an earlier walk away), or the drawn scene and the model disagreed.
- **Browser-only paths the fake surface cannot run**, not verified:
  - the GPU passes, in particular `scale=sharp`'s offscreen render into part of a larger texture (a WebGL y-flip there would move the drawing, not the model);
  - React StrictMode's double mount in development (the first controller is destroyed when its mount resolves; its atlas callback can still reach its destroyed renderer).
  
  Neither explains a preview drawn right and a walk drawn wrong, since both are drawn by the same code. I leave them as candidates, not causes.

### Bug 2, "came into sight" with nothing on screen: what I checked

The stop is evaluated after the step, from the adventurer's new tile. It uses the same `visibleActors` that `toView` gives the renderer, on the terrain revealed by the step. A goblin is named only when it is in that set after the step and was not in it before.

A goblin at distance 6 is on the sight hexagon's rim. The default zoom fits that hexagon, so the goblin is on screen once the camera settles, about 260 ms after the step. Cases where it is not visible:

- **The debug panel covers the top-left of the canvas** (260 px wide, up to 70 % of the height). In the meadow the pack is north-west of the start, which is the top-left on screen. A goblin entering sight on that side is drawn under the open panel.
- **At a closer zoom** (the panel's 9 across, a pinch or the wheel), the rim of the sight hexagon is off screen.
- During the camera's pan, for up to 260 ms after the step.

These do not break the rule: the goblin is drawn, in sight, where the rules put it.

### Point 3, goblins do not move

Goblins do not move in the sandbox: their AI is the chain's (CLI-02), and the placeholders have no rule for it. A goblin "comes into sight" only because the adventurer's step brings it within radius 6. The stop line's wording ("a shaman came into sight") stays as it is: it says what happened. The full console line also gives the goblin's id and tile.

### Changes

- `sandbox/wiring.ts`: `walkStep`'s line (`said`) now reads `walk to (tx, ty) from (ax, ay): planned (nx, ny), stepped to (sx, sy), facing f`. On a stop it continues `; stop: <reason> (#id caste at (x, y), …)`, and an invalid step reads `planned (nx, ny) invalid, stop: <reason>`.
- `sandbox/controller.ts`:
  - the console logs the tap first (`[sandbox] tile (x, y)`), then **every change**, including the steps played on timers, which were not logged before;
  - `SandboxInfo` gains `adventurerTile` and `cameraTile` (the tile at the camera's centre).
- `sandbox/Sandbox.tsx`: the panel shows "adventurer at (x, y), camera on (x, y)".
- `sandbox/walkFollowsPreview.test.ts` (new), through the browser's tap path (screen point → `screenToTile` → session → renderer):
  - **The six directions**, 3 tiles each, from an even row and from an odd row. After each step: the adventurer's tile is the preview's next tile; the renderer's move and the camera's pan target are that tile; each step is the map library's neighbour in the direction tapped (`test/hexxLibrary.ts`).
  - **The meadow's start, 3 south-east**, as the owner tapped: each step lower and to the right on screen.
  - **Around a wall**, at both viewports.
  - **Every cave detour** of 4 to 6 steps from the start.
  - **Sight stops**: every walk to every floor tile of the three fixtures. At every stop for sight, the goblins that entered `visibleActors` at that step are named, within radius 6, with their tile's centre on screen at the default zoom (800 × 658 and 375 × 812, the camera on the adventurer). No caste is named that did not enter.
- Mutation check: with a north/south mirror planted in `walkStep`, the five walk tests fail. The file was restored with `git checkout`.

### Commands run

```
$ pnpm --filter @grimworld/app test
 Test Files  18 passed | 1 skipped (19)
      Tests  165 passed | 1 skipped (166)
$ pnpm --filter @grimworld/app lint        (clean)
$ pnpm --filter @grimworld/app typecheck   (clean)
$ pnpm --filter @grimworld/app build       ✓ built in 115ms (Vite's 500 kB chunk warning, as before)
$ pnpm exec prettier --check client indexer
All matched files use Prettier code style!
$ (mutation) walkStep stepping to the y-mirror of the planned tile
      Tests  5 failed | 1 passed (6)    (src/sandbox/walkFollowsPreview.test.ts)
$ gh pr checks 163 --watch --interval 30
every job pass (indexer-node skipping)
```

### What to look at in the browser

`?fixture=meadow&panel=1&idle=0`, with the browser console open at the "Verbose" level (the lines are `console.debug`).

1. Tap 3 tiles south-east. Each step logs `walk to (7, 11) from …: planned (…), stepped to (…)`: planned and stepped must be equal. The panel's "adventurer at" must follow the ghost markers.
2. If the adventurer goes off the markers, copy those lines, the panel's line, and the URL. The lines show whether the model stepped off the plan (planned ≠ stepped) or the drawing and the model disagree (the model on the plan, the sprite elsewhere).
3. For a stop for sight: the log line names the goblin by id and tile. Check it with the panel closed, and at the default zoom.

### Escalations

None.

---

## Resume 2 (fix loop 1: the audits of #163)

Model: Opus 5.5 (`claude-opus-5-5`). One commit, `bdd1752`, on PR #163. CI is green on every job (`client` 45 s, `tooling` 1 min 56 s).

### Findings and what was done

| Finding | Done | Where | Test |
|---|---|---|---|
| **F-1** (Opus, medium): an inspect during a walk played the next step at once and restarted the timer | `SandboxSession.apply` handles an inspect apart: the state's line changes, the timer is not touched, no step is played | `sandbox/session.ts` | *an inspect during a walk plays no step and keeps the walk's pace*: an inspect every 50 ms (on the adventurer and elsewhere), and the steps still land at 180, 360, 540, 720, 900 ms |
| **1** (GPT-6-Sol, major): the walk continued while the page was hidden | The session listens to the host's visibility (`WalkTimers` gains `hidden` and `onVisibilityChange`, which `FrameHost` and `browserHost` already have). **On hide**: the walk's timer is cleared, the plan kept, and a timer that fires while hidden plays nothing. **On show**: the walk **resumes**, its next step one step's duration later, then at the usual pace | `sandbox/session.ts` | *no step is played while the page is hidden; the walk resumes when it shows*: hidden after 2 steps; 60 s hidden gives no step, no render, no pending timer or frame; shown, the third step comes 180 ms later and the walk ends on its target |
| **F-2** (Opus, low): the stop conditions were evaluated in the wiring | `stopsAfterStep(before, after)` in `placeholders.ts`, `PLACEHOLDER until CLI-02` (design/02). It returns the goblins in `visibleActors` after the step and not before (lowest id first), and whether a tile unrevealed before is not after. The wiring only calls it and words the line | `sandbox/placeholders.ts`, `sandbox/wiring.ts` | `placeholders.test.ts` *stopsAfterStep*: two goblins entering, one already seen, the step back (leaving sight is no stop), a reveal and no reveal. The imports test checks that the wiring calls it and does not diff sight itself |
| **F-3** (Opus, low): the window's outer ring is wall for the chain | `insideRing(centre, tile)`, `PLACEHOLDER until CLI-02`: the window less its first and last columns and rows. `findPath`'s free tiles must be inside the ring, so a path never ends on it or crosses it | `sandbox/placeholders.ts` | `placeholders.test.ts` *bounded by the window … less its ring*: 6 columns each side, not 7; rows 3–16 for an even row and 5–18 for an odd one; the ring counts 58 tiles on both parities; a wall whose one gap is on the ring gives no path, and with the gap one row inside, the path uses it and stays inside the ring |
| **F-4** (info) | `findPath`'s comment says its tie rule is a reading of "lowest tile index", which CLI-02 replaces with the map library's finder | `sandbox/placeholders.ts` | — |
| **F-5** (info): a tap that cancels a walk says so | The line is "walk cancelled" (`CANCELLED`). It is shown for a tap on the counter and for a tap on the map that ends a walk. When the same tap starts a new walk (move played on the tap), the new walk replaces the line. Cancelling a preview shows no line | `sandbox/wiring.ts` | *a tap on the map that ends a walk says so; one that starts another walk does not*; the counter test now expects "walk cancelled" |
| **F-6** (info): the imports test | Across all non-test modules other than `placeholders.ts`: an import binding any of the 12 hex rules (`neighbour`, `distance`, `findPath`, `stepToward`, `stopsAfterStep`, `insideRing`, `inWindow`, `tilesInSight`, `visibleActors`, `revealInSight`, `arcsOf`, `facingToward`), from any module, is found only in `wiring.ts`; no other module exports one of them; `wiring.ts` names none of the grid's geometry (`neighbour`, `distance`, `inWindow`, `insideRing`) | `sandbox/imports.test.ts` | itself |
| **2** (GPT-6-Sol), not accepted: idle on is D-151 | No code change. The test asked for is added | — | *with idle animations on (D-151): after a walk and its fade, only the idle cadence remains*: edge fixture, walk stopped by a reveal. After the walk and its fade, no walk step is scheduled. Over 10 s, renders and wake-ups equal those of the 10 s before the walk (12 a second, ≤ 15) |

**Why resume and not stop, on show:**
- Nothing happened while the page was hidden. No step was played, and goblins act only on the adventurer's actions (D-40), so the state the plan was made on is unchanged.
- Each resumed step still runs the stop conditions.
- Stopping instead would drop a plan the player chose for no reason they could see.

The pause keeps the plan and the counter ("▶ n steps"). On show the walk waits one step's duration, so the first step after showing is seen as it is played.

### Commands run

```
$ pnpm --filter @grimworld/app test
 Test Files  18 passed | 1 skipped (19)
      Tests  172 passed | 1 skipped (173)
$ pnpm --filter @grimworld/app lint        (clean)
$ pnpm --filter @grimworld/app typecheck   (clean)
$ pnpm --filter @grimworld/app build       ✓ built in 105ms (Vite's 500 kB chunk warning, as before)
$ pnpm exec prettier --check client indexer
All matched files use Prettier code style!
$ gh pr checks 163 --watch --interval 30
every job pass (client 45s, tooling 1m56s; indexer-node skipping)
```

### What changes in the browser

- A long press or a right click during a walk no longer speeds it up.
- Switching tabs mid-walk pauses it; coming back resumes it after 180 ms.
- Far taps reach one tile less far: 6 columns each side, and 6 or 7 rows up and down depending on the row's parity. The ring of the 15 × 16 window is no longer a target.
- Cancelling a walk, from the counter or by a tap on the map, shows "walk cancelled".

### Escalations

None.
