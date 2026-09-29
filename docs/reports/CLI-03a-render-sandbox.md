# [Opus 5.5] CLI-03a — render sandbox

## Summary

Model read from my session: Opus 5.5 (`claude-opus-5-5`), the model the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/135 (branch `cv/CLI-03a-render-sandbox`, 4 commits, CI green on every job).

What exists now that did not before:

- `pnpm --filter @grimworld/app dev` opens a **rendering sandbox**. It draws a hex map on demand from fixtures, chosen with `?fixture=meadow|cave|edge`. It shows:
  - the adventurer and the goblins in sight: atlas sprites when `tools/art/out/` exists, plain shapes otherwise;
  - a camera that follows the adventurer;
  - sight of radius 6 drawn bright, remembered terrain dimmed, unrevealed chunks dark;
  - a facing wedge on every actor;
  - the selected actor's rear-side tiles (a tint and a ring) and back tile (a tint and a cross);
  - state marks over goblins;
  - touch and mouse input that produces **intents**;
  - a debug panel.
- **No rule of the game in `client/app`** except `sandbox/placeholders.ts`. Each of its functions is marked `PLACEHOLDER until CLI-02`, and only `sandbox/wiring.ts` imports it (a test checks this).
- **On demand**, from `render/scheduler.ts`:
  - no ticker;
  - one frame per change;
  - display frames only while a step, a turn or the camera's pan runs;
  - idle animations at most 15 frames a second, sleeping on a `setTimeout` between two frames (not on `requestAnimationFrame`);
  - zero frames when idle animations are off;
  - nothing while the page is hidden.
- **A finding worth knowing for SPK-6**: PixiJS 8 runs a loop of its own even with `autoStart: false`. Its renderer's `SchedulerSystem` (texture garbage collection) and its event system add themselves to `Ticker.system` at init, and that ticker **auto-starts a permanent `requestAnimationFrame` loop** (`pixi.js/lib/rendering/renderers/shared/SchedulerSystem.mjs:14`, `lib/events/EventTicker.mjs:39`). `render/pixiSurface.ts` stops `Ticker.system` and `Ticker.shared` and keeps them from starting again (`autoStart = false`). The debug panel shows "PixiJS tickers running: none". The cost: PixiJS's automatic texture garbage collection does not run, so the renderer destroys its textures by hand.
- The atlas in development only: a `vite.config.ts` middleware (`apply: "serve"`) serves `tools/art/out/` at `/art/`. `GRIMWORLD_ART_OUT=<dir>` points it at another checkout. Nothing of the art is imported, bundled or committed.

## Files changed

- `client/app/src/render/view.ts`: the view state (types only).
- `client/app/src/render/scheduler.ts`: `FrameScheduler` (frames on demand, visibility) and `browserHost()`.
- `client/app/src/render/renderer.ts`: the PixiJS renderer. Scene nodes; tweens for a step (180 ms), a turn (120 ms) and the camera (260 ms); idle frames; the baked terrain; camera, zoom and sprite scales.
- `client/app/src/render/shapes.ts`: terrain, rocks (walls as obstacle objects), the overlay (dimming, arcs, path, selection), wedge, bodies as shapes, marks.
- `client/app/src/render/facing.ts`: rotation of a facing, mirror, wedge geometry.
- `client/app/src/render/sprites.ts`: the `sprites.json` index, and the library built from parsed pages.
- `client/app/src/render/atlas.ts`: `loadAtlas()` from `/art/`; null without an atlas.
- `client/app/src/render/pixiSurface.ts`: the PixiJS application as a surface. Resolution is an integer ≤ 2, scaling is nearest-neighbour, and PixiJS's tickers are stopped.
- `client/app/src/input/coords.ts`: pixel ↔ tile, the camera transform, `fitScale`.
- `client/app/src/input/gestures.ts`: tap, long press or right click, drag, pinch, wheel.
- `client/app/src/input/intent.ts`: `Intent` (`tile`, `inspect`).
- `client/app/src/sandbox/placeholders.ts`: the only rules: neighbour, distance, sight, arcs, facing toward, step.
- `client/app/src/sandbox/wiring.ts`: `applyIntent` and `toView`.
- `client/app/src/sandbox/world.ts`: the fixture's world type (terrain, actors).
- `client/app/src/sandbox/fixtures/build.ts`, `fixtures/index.ts`: the three fixtures, as ASCII maps drawn as on screen.
- `client/app/src/sandbox/controller.ts`: the sandbox in the browser (surface, renderer, gestures, wiring, atlas).
- `client/app/src/sandbox/Sandbox.tsx`: the React component, the re-centre button and the debug panel.
- `client/app/src/App.tsx`: mounts the sandbox.
- `client/app/src/frame.ts`, `frame.test.ts`: **removed** (the renderer replaces the placeholder frame).
- `client/app/vite.config.ts`: the dev-only `/art/` middleware.
- Tests:
  - `input/coords.test.ts`, `input/gestures.test.ts`;
  - `render/renderer.test.ts`, `render/atlas.test.ts`, `render/pixiSurface.test.ts`;
  - `sandbox/placeholders.test.ts`, `sandbox/wiring.test.ts`, `sandbox/imports.test.ts`;
  - test helpers: `src/test/hexxLibrary.ts` (the library's `Direction::next` table, transcribed), `src/test/fakeHost.ts`, `src/test/syntheticAtlas.ts` (a plain-colour atlas made in code).

No dependency was added; `package.json` and `pnpm-lock.yaml` are unchanged.

## Commands run

From the worktree root, on the Mac (node 22.22.2, pnpm 12.5.1):

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 11ms using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  12 passed | 1 skipped (13)
      Tests  91 passed | 1 skipped (92)
(the skipped file is the existing account/burner.node.test.ts, not touched)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (no output: clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (no output: clean)

$ pnpm --filter @grimworld/app build
✓ 740 modules transformed.
✓ built in 110ms
(dist/ holds index.html and assets/*.js only: `find client/app/dist -type f | grep -vE "\.(js|html)$"` prints nothing)

$ pnpm exec prettier --check client
Checking formatting...
All matched files use Prettier code style!
```

A smoke test of the dev server: one foreground Node process started it through Vite's `createServer`, fetched, and closed it. Its script was put in a scratch folder and deleted afterwards.

```
With a scratch /art/ directory holding a synthetic sprites.json:
  art: serving …/client/app/.smoke-art at /art/
  ["/?fixture=cave",200,"text/html", …]
  ["/src/sandbox/Sandbox.tsx",200,"text/javascript", …]
  ["/art/sprites.json",200,"application/json", …]
  ["/art/atlas-0.json",404, …]          (not present)
  ["/art/smoke.mjs",404, …]             (only .json and .png are served)
Without it (the worktree has no tools/art/out):
  art: …/tools/art/out not built, the sandbox draws shapes
  ["/art/sprites.json",404, …]
```

CI of PR #135: every job passes, including `client` (Node 24: install, lint, typecheck, test, build, prettier) and `tooling` (the D-73 image and atlas check). Node 22 locally and Node 24 on CI showed no difference.

## Cost

— (no Cairo).

## The view state's type (`client/app/src/render/view.ts`)

```ts
interface Tile { readonly x: number; readonly y: number }            // global offset coordinates
type TileKind = "floor" | "wall" | "unrevealed";
type Seen = "now" | "before";
interface ViewTile extends Tile { readonly kind: TileKind; readonly seen: Seen }
type Facing = 0 | 1 | 2 | 3 | 4 | 5;                                 // the library's Direction: E NE NW W SW SE
type Caste = "runt" | "skirmisher" | "slinger" | "shaman" | "hobgoblin";
type Profession = "vanguard" | "warden" | "cleric" | "arcanist";
type Mark = "asleep" | "alerted" | "engaged" | "fleeing";
type ViewActor =
  | { id; tile; facing; mark: Mark | null; side: "adventurer"; profession: Profession }
  | { id; tile; facing; mark: Mark | null; side: "goblin"; caste: Caste };
interface ViewArcs { actorId; front: Tile[]; frontSide: Tile[]; rearSide: Tile[]; back: Tile[] }
interface ViewState {
  tiles: ViewTile[];          // revealed terrain and unrevealed tiles
  actors: ViewActor[];        // the adventurer, and goblins in sight only
  adventurerId: number;
  sight: Tile[];              // tiles in sight
  arcs: ViewArcs | null;      // of the selected actor
  path: Tile[];               // planned path
  selectedTile: Tile | null;
}
```

## The placeholders and what they stand for (`client/app/src/sandbox/placeholders.ts`)

| Function | Stands for |
|---|---|
| `neighbour(tile, d)` | The library's `Direction::next` (`hexx-cairo` `direction.cairo`), on global coordinates |
| `distance(a, b)` | The library's `distance` (odd-r → cube); checked against `contracts/logic/tests/test_hexmap.cairo` |
| `tilesInSight(terrain, centre)` | design/18 *What the adventurer sees*: a hexagon of radius 6, line of sight not required |
| `arcsOf(terrain, actor)` | design/04 *Facing and arcs (D-41)*. "When you can reach them" (design/11) is taken as "floor tiles" |
| `facingToward(from, to)` | design/04 *Actions*: turn (the adventurer turns to an adjacent goblin it taps) |
| `stepToward(terrain, actors, id, target)` | design/04 *Actions*: move one tile, set facing to the direction moved. It moves to a free floor neighbour strictly closer to the target, choosing the lowest direction number on a tie. **Not pathfinding** (CLI-03) |

The fixtures are hand data. Goblins do not act.

## Default zoom and tile width

The zoom is expressed as **the number of tiles across the sight hexagon's widest row that fit the viewport**. The hexagon is fitted by its width in portrait and by its height on a desktop (ADR-0006 §5). Hexes are 64 art pixels wide (the art tile).

| Viewport | Zoom | Tile width on screen |
|---|---|---|
| 375 × 812 | **13 across (default)** | **28.8 CSS px** (375 / 13), **72 % of I-6's 40 points** |
| 375 × 812 | 9 across ("close", one button or pinch away) | 41.7 CSS px |
| 1440 × 900 | 13 across | about 77.9 CSS px (fitted by the height) |

This is exposed and not decided: the defaults are in `render/renderer.ts` `DEFAULT_ZOOM`. The debug panel changes the default and has presets for 13 and 9, and `?zoom=<across>` sets it from the URL. Pinch and wheel range from 25 across to 4 across.

## What to look at in the browser

Open `http://localhost:5173/?fixture=cave&panel=1` at 375 × 812, then on a desktop window. Parameters: `fixture` = `meadow` | `cave` | `edge`; `idle=0` turns idle animations off; `panel=1` opens the panel; `zoom=9` sets the default zoom. The "debug" button at the top left toggles the panel, and the round button at the bottom right re-centres on the adventurer.

1. **Orientation (most important)**: direction 0 (East) must point to the screen's right, and the odd rows are shifted left. Tap a floor tile to the right of the adventurer: the step goes right and the wedge points right. See the escalation below.
2. **Sight**: the 13-tile hexagon around the adventurer is bright and the rest dimmed. In `meadow`, part of the sleeping pack is outside sight and not drawn; walk toward it (tap tiles north-west) and it appears.
3. **Facing**: in `cave`, ten goblins face in various directions. Each wedge should point at a neighbouring tile's centre. Sprites should be mirrored exactly for the three left-facing directions.
4. **Arcs**: tap a goblin. Its two rear-side tiles get an orange tint and ring, and its back tile a red tint and cross; walls are left out. Tap it again, or tap outside the map, to clear. Tapping an adjacent goblin also turns the adventurer to face it.
5. **Marks**: `meadow` shows Z (asleep). `edge` shows ! (alerted), a red cross (engaged) and chevrons (fleeing).
6. **Unrevealed**: in `edge`, the three dark chunks on the left and top are wall (D-136), 7 tiles from the adventurer.
7. **Camera**: a step eases the camera to the adventurer. Drag pans, pinch or wheel zooms around the fingers or the pointer, and ◎ re-centres.
8. **Power**:
   - With idle animations off, "frames drawn" must not move while nothing is touched.
   - With them on, it should rise by about 12 a second.
   - "since last input" restarts on every touch.
   - "PixiJS tickers running" must read "none".
   - DevTools' Performance panel should show no `requestAnimationFrame` between idle frames, only timers.
9. **Sprites**: with `tools/art/out/` built in the checkout that runs `pnpm dev` (or `GRIMWORLD_ART_OUT` set), "atlas: loaded" appears and each sprite gets a scale field. Set the scales by eye there; they start at `sprites.json`'s `scale` if ART-02 adds one, else 1.
10. **Inspect**: long press, or right click on a desktop, writes the tile or actor into the panel's last line. Every intent is also logged with `console.debug("[sandbox]", …)`.
11. **Console**: without an atlas, the console shows one info line ("no atlas at /art/"). A failed atlas or renderer start is a `console.error` with the cause.

## Acceptance criteria

- **AC-1**: the dev server serves the sandbox, and `?fixture=` selects each fixture (`fixtureNamed`, `wiring.test.ts` "fixtures"). With the atlas, sprites come from `/art/` (loading tested on a synthetic plain-colour atlas parsed by PixiJS's `Spritesheet`, `render/atlas.test.ts`). Without it, `loadAtlas` returns null and shapes are drawn (tested; dev server smoke test above). The real atlas has not been seen by me: I have no browser and no atlas.
- **AC-2**: `render/renderer.test.ts` "renderer on demand", with a fake host (clock, 120 Hz display, timers, visibility) and a fake surface:
  - one frame per view, and nothing pending afterwards;
  - after a step, 10 to 40 frames, then no frame or timer pending and none in the next 10 s;
  - idle off: zero frames in 60 s;
  - idle on (shapes and atlas sprites): 11 to 15 frames a second, with display frame callbacks equal to frames drawn, so no wasted wake-up;
  - the cave's ten goblins draw exactly 12 frames a second;
  - hidden: nothing is drawn and nothing is pending, and drawing resumes when shown.
- **AC-3**: `input/coords.test.ts`:
  - a round trip, screen → tile → screen, on every tile of a 15 × 16 window, for origins (30, 44) and (7, 13), at three scales (fit 13 on 375, 1, 2.5), including points toward each corner;
  - **the boundary rule**: a point on the edge of two hexes goes to the lower tile index (lower `y`, then lower `x`), and a corner of three hexes to the lowest. This is the tie-break design/04 uses for line of sight.
- **AC-4**: `render/renderer.test.ts` "the six facings", for shapes and for atlas sprites, on both row parities. For each direction 0–5, the wedge's tip is on the ray to the centre of the library's `Direction::next` neighbour, transcribed from `hexx-cairo` in `src/test/hexxLibrary.ts`. The body is mirrored exactly when that neighbour is to the left, which is exactly directions 2, 3 and 4. The numbering is cited in `render/facing.ts` and `render/view.ts`.
- **AC-5**: `sandbox/imports.test.ts` checks three things:
  - of all non-test sources, only `./wiring.ts` imports `placeholders`;
  - every exported function of `placeholders.ts` has `PLACEHOLDER until CLI-02` in its comment;
  - no `Math.random`, `Date.`, `performance.now` or `crypto.` appears in the file.
- **AC-6**: the commands above pass locally, and PR #135's CI is green.
- **AC-7**: no image, atlas or screenshot is in git or the PR; the synthetic atlas is built in code in the test, with plain colours. `dist/` holds JS and `index.html` only. The `/art/` middleware is `apply: "serve"`.

## Deviations from the brief

1. **`frame.ts` and `frame.test.ts` removed**: the renderer replaces the placeholder frame, and `App.tsx` mounts the sandbox.
2. **"Tap outside clears" is decided by the wiring, not by a third kind of intent.** Input always produces `{ kind: "tile", tile }`. The wiring clears the selection when that tile is outside the location or unrevealed, or when the tap is on the actor already selected.
3. **A tap on a goblin selects it**, and the adventurer turns toward it if it is adjacent. A tap on a floor tile takes **one** placeholder step toward it. The planned path is fixture data only (`edge` shows a three-tile path, cleared by the first step); computing paths is CLI-03's.
4. **The sandbox cannot reveal a chunk.** When the adventurer walks until sight touches an unrevealed chunk, those tiles stay drawn as unrevealed. The real game reveals them in that move (ADR-0006 §4).
5. **`fleeing` added to the marks**: design/11 lists "asleep / alerted / engaged / fleeing". A goblin on watch has no mark.
6. **Idle animations share frame boundaries.** Every sprite's frame index is `floor(t · fps) + id`, so ten sprites change in one frame and not ten, each starting on a different frame. Shapes have a synthetic 6-frame bob at 12 fps, so that the power behaviour can be seen without the atlas. During a step, an atlas sprite plays its `move` animation.
7. **PixiJS's tickers are stopped** (see the summary). PixiJS's texture garbage collection therefore does not run, and the renderer destroys its baked textures itself.
8. **The terrain bake's resolution** is the screen's pixels per art pixel, rounded to steps of √2 and capped by a 4096 texture. The largest fixture, `edge`, is about 2900 art pixels wide, so when zoomed in past about 1.4 device pixels per art pixel the terrain is upscaled, and its grid lines look blocky. Actors and the overlay are not baked and stay crisp.
9. The PR title is the brief's (`feat(client): CLI-03a, a rendering sandbox on fixed data`) rather than COMMON §6's `[<Model>] <TASK-ID> …`: the brief wins.

## Escalations

1. **The screen orientation of the library's layout: settled from the sources, but surprising. Please confirm with the library's owner.**
   - What `bal7hazar/hexx-cairo` says:
     - `layout.cairo`: "Pointy-top, odd-r offset, row-major: i = y * width + x".
     - `direction.cairo`: `Direction` into `u8` is East 0, NorthEast 1, NorthWest 2, West 3, SouthWest 4, SouthEast 5. `next`: East `i − 1`, West `i + 1`, NorthEast `i + W − 1` on an even row and `i + W` on an odd one. "Odd rows are drawn shifted half a tile toward increasing x".
     - `printer.cairo`: "Rows are printed top (y = H − 1) to bottom, x = 0 on the right".
   - Together these mean **x grows toward the West, the left of the screen, and y toward the North, up**, which mirrors the usual screen x axis. I drew it that way, so that East is the screen's right as design/10 *Facing* requires.
   - It agrees with `contracts/logic/tests/test_hexmap.cairo` (`origami_hexmap`, width 7): `distance(3, 9) == 1`, that is (3, 0)–(2, 1) adjacent, which holds only if North-East is `i + W − 1` on an even row. I found no disagreement between the two libraries.
   - A caveat on the sources: WebFetch refused to reproduce the files verbatim. The quotes above come from its answers to targeted questions, run twice on different files, and cross-checked by the contracts' own test. I transcribed the `next` table into `src/test/hexxLibrary.ts`, and every geometry test checks against that table.
   - If the owner's convention is x to the right, the fix is a sign in `tileToPixel`, `pixelToTile` and `facingRotation`. The tests against the table would then show which directions moved.
2. **Mandate §6.1 and "who is visible"**: which goblins the view carries (those in sight) is computed by the wiring through `tilesInSight`. When CLI-02 or CLI-03 produces the view from `client/sim`, that filter belongs there. It is a `PENDING-cv-*` candidate, not something I could write.

## Open questions

1. **Tile size (I-6)**: the default zoom of 13 tiles across gives tiles of 28.8 CSS px on a 375-px-wide phone, under the 40 points of I-6. At 9 across they are 41.7 px. Which default, and should the closer level be the default for taps? For the owner and SPK-6.
2. **Sprite sizes**: `sprites.json` has no scale field today. The loader reads an optional `scale` per sprite, defaulting to 1 (drawn at the atlas's own pixel size against 64-pixel hexes). Should ART-02 write the scale, or should the owner's values from the panel be kept in a file of the client?
3. **Camera after a manual pan**: the next step eases the camera back to the adventurer. Should a pan instead "detach" the camera until ◎ is pressed?
4. **Durations**: a step takes 180 ms, a turn 120 ms and the camera 260 ms, with a cubic ease-out, all at display rate. Should steps also be drawn at the pixel art's 12–15 fps to save power?
5. **Mark shapes**: Z asleep, ! alerted, crossed red lines engaged, chevrons fleeing, and nothing on watch. These are my stand-ins until the icon set (design/10 *Icons*).

## Resume 1

Fix loop 1: the two audits of #135 (design and quality, `[Opus 5.5]`; security, `[GPT-6-Sol]`), every finding accepted by the orchestrator.

### Summary

All findings are fixed and tested, and two commits are pushed to #135:

- `d6aecf9` fixes the security audit;
- `cc762e3` fixes the design and quality audit.

CI is green on every job. There are now 114 tests, against 91 before.

**Escalation 1 is closed.** The orchestrator read `bal7hazar/hexx-cairo` `crates/hexx/src/board/direction.cairo` itself: "i = y * width + x, bit 0 is printed bottom-right, +1 is West and +width is North. Odd rows are drawn shifted half a tile toward increasing x". My reading of the layout was right, and so was my drawing: x grows toward the West (screen left), y toward the North (up), and East (direction 0) is the screen's right. Nothing changed in the code for it.

### What changed, finding by finding

**Design and quality audit**

1. **Integer scale (major; the conflict between ADR-0003 and ADR-0006 §5 is escalated by the orchestrator, not settled here).**
   - Added an "integer scale" option: `?snap=1`, or the "integer scale (ADR-0003)" checkbox in the panel. The continuous scale stays the default.
   - `snapScale` (`render/renderer.ts`) snaps the scale to a whole number of device pixels per art pixel (1, 2, 3, …), or to a whole fraction of one below 1 (1/2, 1/3, …), choosing the nearest by ratio. The wanted scale (fit, pinch, wheel) is kept apart from the drawn one, so pinching walks through the snapped steps.
   - The panel now shows the device pixels per art pixel, the CSS scale, the tile width and the tiles across.
   - Measured at 375 × 812 (tests `the integer scale option`); the table follows this list.
2. `visibleActors(terrain, actors)` is added to `placeholders.ts`, marked PLACEHOLDER until CLI-02 (design/18). Both places in `wiring.ts` use it. `imports.test.ts` now fails if any non-placeholder source filters actors by sight, and checks that the wiring calls `visibleActors(`.
3. **The reveal (the preferred option).** `revealInSight(terrain, centre)` in `placeholders.ts` (ADR-0006 §2 and §4) gives each unrevealed chunk that sight touches the terrain the fixture holds for it; `Terrain.hidden` stands for the generation at reveal. The wiring calls it after every step and at the start. Test: in `edge`, one step West reveals chunk (2, 0), and no tile in sight is unrevealed; chunks (2, 1) and (1, 1), out of sight, stay unrevealed.
4. **Gestures.** When one finger of a pinch lifts, the remaining finger becomes the drag's start and the gesture counts as a drag, so the camera no longer jumps. Test: after the pinch, a move of (5, 2) pans by exactly (5, 2).
5. **`surfaceResolution`** now rounds down, capped at 2: DPR 1.5 → 1 (it was 2), 2.625 → 2, 3 → 2, NaN → 1. Test updated.
6. **Terrain baked per chunk.**
   - The terrain is baked as one texture per 15 × 15 chunk, rebuilt only when that chunk's tiles change kind or the zoom crosses a √2 step.
   - The texture cap is the GPU's own: WebGL's `MAX_TEXTURE_SIZE` or WebGPU's `maxTextureDimension2D`, with 2048 when unreadable (`gpuMaxTextureSize`, tested).
   - Tests: changing one tile's kind rebakes exactly one chunk (2 bakes, then 3); the same view again rebakes nothing; a 2048 limit caps the texture resolution.
7. **Step tie-break.** A tie between two steps now goes to the lowest tile index, `y` then `x` (design/04 and the determinism rules). Test with the audit's case: from (10, 10) toward (12, 12), North-West (10, 11) and West (11, 10) are both 2 away, and the step now goes West, facing 3 (it used to go North-West, facing 2).
8. **Dead code and one source of truth.** Removed `FrameScheduler.poke()`, `FrameScheduler.idle()` (also unused) and `tileWidthOnScreen`. `ViewTile.seen` is removed: `ViewState.sight` is now the only record of "seen now". A revealed tile in `sight` is bright, and every other revealed tile was seen before and is dimmed. This is documented in `view.ts`.

**Notes**

- 9: `pixelToTile` now cites design/04 *Ranges* ("the lower tile index is taken"), not CONTEXT §8.
- 10: during a step, an actor's `zIndex` follows its drawn position. Test: mid-step, every actor's z equals its y.
- 11: `overlayPlan(view)` separates what the overlay draws from the drawing. The test checks:
  - dimming of the tiles seen before;
  - rear-side rings and the back cross;
  - the fills and strokes the Graphics records (13 fills, 4 strokes);
  - an empty overlay when there is nothing to show.

  The rebake test is under 6.

Default zoom at 375 × 812 (finding 1):

| Mode | Screen resolution | Device px per art px | Tile width (CSS px) | Tiles across 375 |
|---|---|---|---|---|
| Continuous (default), 13 across | 1 (DPR 1 or 1.5) | 0.451 | **28.8** | 13.0 |
| Continuous (default), 13 across | 2 (DPR ≥ 2) | 0.901 | **28.8** | 13.0 |
| Continuous, 9 across ("close") | 1 or 2 | 0.651 or 1.302 | 41.7 | 9.0 |
| Integer scale, 13 across | 2 | **1** | **32** | 11.7 |
| Integer scale, 13 across | 1 | **1/2** | **32** | 11.7 |
| Integer scale, 9 across | 2 (1.30 → 1) or 1 (0.65 → 1/2) | 1 or 1/2 | 32 | 11.7 |
| Integer scale, next step in | 2, or 1 | 2, or 1 | 64 | 5.9 |
| Integer scale, next step out | 2, or 1 | 1/2, or 1/3 | 16, or 21.3 | 23.4, or 17.6 |

With the integer scale, a 375-px phone has no step between 32 px and 64 px, so both 13 and 9 across land on 32 px. That is the owner's comparison to make by eye.

**Security audit**

1. The `/art/` handler moved to `src/dev/serveArt.ts`; `vite.config.ts` imports it and it runs in the dev server only (`dist/` holds no trace of it: `grep` for `readFileSync` or `realpathSync` in `dist/assets` finds nothing). It resolves the root and the requested file with `realpathSync` and requires the resolved file inside the resolved root. Only `.json` and `.png` are served. Tests on a scratch folder of plain-text files, removed after the run:
   - a symlink inside `out/` to a file outside is refused, and so is a symlinked folder;
   - a symlink that stays inside is served;
   - `..`, `%2e%2e`, a NUL byte, other types, a folder and a missing root all answer 404.
2. `readSpritesIndex` now returns `{ index }` or `{ problem }`. It accepts:
   - frame rates that are finite within 1..30 (`FPS_RANGE`; the design's 12–15 is inside);
   - integer frame counts from 1 to 1000;
   - cells within 1..4096, a baseline inside the cell, a scale within 0.05..10.

   On a problem, `loadAtlas` writes `console.error("[sandbox] sprites.json refused (<problem>); drawing shapes")` and returns null, so shapes are drawn. Tests: −1, 0, 0.5, 31, ∞, NaN, "12" and null are refused, and 1, 12, 15 and 30 accepted; a bad rate never loads a page and logs one error each.
3. `?zoom` is read by `sandbox/params.ts`: only a finite number within the panel's bounds (3..31) is accepted, otherwise the default applies. The panel's field uses the same check, and the sprite-scale fields accept only finite values within 0.1..4. Tests: `Infinity`, `-Infinity`, `NaN`, `1e308`, 2, 32, −13, `abc` and the empty string are all ignored.
4. A malformed escape (`/art/%`, `%zz`, a truncated UTF-8 escape) answers 404 instead of throwing. Tested, and checked on the dev server: `["/art/%",404,null]`.

### Commands run (real output, node 22.22.2 on the Mac)

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 8ms using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  14 passed | 1 skipped (15)
      Tests  114 passed | 1 skipped (115)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (clean)

$ pnpm --filter @grimworld/app build
✓ 741 modules transformed.
✓ built in 108ms
(dist/: only .js and index.html; no readFileSync/realpathSync in dist/assets)

$ pnpm exec prettier --check client
Checking formatting...
All matched files use Prettier code style!
```

Dev server smoke test (one foreground Node process: Vite's `createServer`, fetch, close; the scratch folder was deleted afterwards):

```
  art: serving …/client/app/.smoke-art at /art/
["/?fixture=edge&snap=1",200,"text/html"]
["/art/sprites.json",200,"application/json"]
["/art/%",404,null]
["/art/smoke.mjs",404,null]
```

The first smoke run printed Vite's warning that an extensionless import in the config is unsupported by the future native config loader. The import is now `./src/dev/serveArt.js`, which TypeScript's Bundler resolution maps to the `.ts` file, and the warning is gone.

CI of #135 after the push: every job passes (`client`, `tooling`, `discover` and every `cairo` job).

### Files changed in this resume

- `client/app/vite.config.ts`
- New:
  - `src/dev/serveArt.ts` and its test;
  - `src/sandbox/params.ts` and its test.
- `src/render/`: `renderer.ts`, `shapes.ts`, `sprites.ts`, `atlas.ts`, `pixiSurface.ts`, `scheduler.ts`, `view.ts`.
- `src/input/`: `coords.ts`, `gestures.ts`.
- `src/sandbox/`: `placeholders.ts`, `wiring.ts`, `world.ts`, `fixtures/build.ts`, `controller.ts`, `Sandbox.tsx`.
- Their tests.

No dependency was added.

### Deviations (added)

- **Integer scale**: an option, off by default. With the default continuous scale, the art is drawn at about 0.45 (portrait) and at non-integer scales in general, which ADR-0003 does not allow. The conflict between ADR-0003 and ADR-0006 §5 is the orchestrator's escalation to the project manager and the owner; the sandbox lets them compare by eye.
- The reveal gives an unrevealed chunk the terrain written in the fixture. In the game, that terrain is generated from a random word at reveal (ADR-0006 §2); the sandbox has no generator. Deviation 4 of the first report no longer holds: the sandbox now reveals.
- `FrameScheduler.idle()` was removed along with `poke()`: it was unused too.
- `ViewTile.seen` was removed, and the view state no longer has a `seen` field. "Seen before" is every revealed tile not in `sight`.

### Escalations

- Escalation 1 (orientation): **settled** by the orchestrator, as above.
- Escalation 2 (the visible-goblins filter belongs to whoever produces the view from `client/sim`): unchanged. It is now one placeholder, `visibleActors`, which CLI-03 replaces.

### For SPK-6

- The resolution rounds down, so a DPR 1.5 phone renders at 1× (it was 2×) and a DPR 2.625 or 3 phone at 2×.
- The terrain's texture limit is read from the GPU.
- Whether the integer scale looks better or worse on a real phone is for the owner and SPK-6 to judge. Try `?snap=1` against the default. *(Superseded by Resume 2: `?scale=snap`.)*

## Resume 2

The owner's comparison of scales (PENDING-cv-integer-scale), asked by the owner's architecture session.

### Summary

Resume 1's snap toggle is replaced by one parameter, `?scale=continuous|snap|sharp`, with the same choice in the debug panel. The default is `continuous`, and anything else in the URL also reads as `continuous`.

- `snap` now counts the integer in **device (screen) pixels**. To make that possible, it renders the canvas at the screen's own ratio when that ratio is a whole number.
- `sharp` ("sharp bilinear") is new. It draws the world nearest-neighbour at the next integer scale into an offscreen render texture, then draws that texture down to the target scale with linear filtering.
- The panel shows, for the current mode:
  - the devicePixelRatio;
  - the canvas resolution;
  - the device pixels per art pixel, to two decimals, with "integer" or "not an integer";
  - the canvas pixels per art pixel;
  - for `sharp`, the offscreen pass (its `n` and its size in texels);
  - the tile width in CSS points and the tiles across the width.

Every fix of Resume 1 is kept. Commit `954f6c3` is pushed to #135, and CI is green on every job. There are now 122 tests.

### 1. Which pixels the integer is counted in

Three numbers are involved (`render/scaling.ts` explains them):

- the world scale `s`, in CSS pixels per art pixel (the zoom);
- the canvas resolution `r`, in render pixels per CSS pixel (the canvas's backing store);
- the screen's `devicePixelRatio`, `dpr`.

PixiJS draws an art pixel over `s × r` canvas pixels. The browser then composites the canvas onto the screen, scaling the whole bitmap by `dpr / r` with bilinear filtering (a canvas's default `image-rendering`). An art pixel therefore covers `s × dpr` **screen** pixels.

**How the canvas resolution relates to the devicePixelRatio** (after Resume 1's floor and cap, in `continuous` and `sharp`): `r = min(2, max(1, floor(dpr)))`.

| dpr | 1 | 1.5 | 2 | 2.625 | 3 |
|---|---|---|---|---|---|
| r | 1 | 1 | 2 | 2 | 2 |

**On an iPhone 14 (dpr 3):** the canvas renders at **2** render pixels per CSS pixel. The browser then stretches that bitmap by **1.5** to the screen's 3 pixels per CSS pixel, smoothing it. So an integer counted in canvas pixels, such as 1 canvas pixel per art pixel, becomes 1.5 screen pixels per art pixel after the browser's resample. That is neither an integer nor crisp.

**What I chose.** The integer that matters is the one against the screen's pixels, and it holds only if the canvas pixels are the screen's pixels (`r = dpr`) and `s × r` is a whole number.

- In `snap`, the canvas therefore renders at the screen's own ratio when that ratio is a whole number up to 3 (dpr 3 → `r = 3`). `snap` then picks a whole number `n ≥ 1` of canvas pixels per art pixel, which are then screen pixels. It takes the `n` nearest by ratio to the default zoom, which fits the sight's 13 tiles closest, and never a fraction.
- **Cost:** on a 3× phone this lifts ADR-0003's 2× cap, in `snap` only. The canvas has 2.25 times as many pixels as at 2×. The owner judges whether the crispness is worth it.
- **A fractional ratio** (2.625 on many Android phones) has no whole canvas resolution equal to the screen's. There, `snap` keeps `r = min(2, floor(dpr))`, and the browser's uniform bilinear resample to the screen stays; the panel then says "not an integer".
- `continuous` and `sharp` keep the capped canvas resolution.
- The panel's "integer" is true only when `r = dpr` and `s × dpr` is a whole number.

### 2. Sharp bilinear

For the target scale `s`, the pass takes `n = ceil(s × r)` (at least 1) and oversamples by `k = n / (s × r)`.

**What the renderer does:**
- The world is a root container, rendered into a `RenderTexture` of `ceil(width × k) × ceil(height × k)` CSS pixels at the canvas resolution, with `scaleMode: "linear"`, at world scale `s × k`. An art pixel there is exactly `n` texels, and the art's own textures stay nearest-neighbour.
- One sprite on the stage draws that texture at `1 / k`, sampling it linearly. 13 tiles across hold on any screen.
- The offscreen pass happens only inside a frame being drawn: on demand, still one per frame and none between inputs.
- The texture is kept while its size holds (a pan keeps it). It is destroyed and remade on zoom and resize, and dropped when the mode leaves `sharp`.
- `k` is lowered if the GPU's texture limit requires it.
- The terrain is baked at the offscreen's scale in this mode.

**Tests** (`render/renderer.test.ts`, "sharp bilinear"):
- the texture's size, resolution and linear filtering;
- `n = 1` at 13 tiles across on a phone;
- the stage holds only the down-drawing sprite, at scale `1 / k`;
- one pass per frame drawn, over 5 s;
- the texture is kept on a pan, and remade (the old one destroyed) on zoom and on resize;
- it is dropped when switching to `continuous`;
- nothing is pending after it settles.

### 3. The three modes' figures, at the default zoom (13 across)

These are measured by `render/scaling.test.ts`, which asserts every figure below from the renderer's `zoomInfo()`. "Device px/art px" is `s × dpr`.

**375 × 812, DPR 2**

| Mode | Canvas res. | Device px/art px | Integer? | Tile width (CSS pt) | Tiles across | Offscreen |
|---|---|---|---|---|---|---|
| continuous | 2 | 0.90 | no | 28.85 | 13.00 | — |
| snap | 2 | **1.00** | **yes** | 32.00 | 11.72 | — |
| sharp | 2 | 0.90 | no (offscreen `n = 1`) | 28.85 | 13.00 | 832 × 1802 texels |

**375 × 812, DPR 3 (an iPhone 14)**

| Mode | Canvas res. | Device px/art px | Integer? | Tile width (CSS pt) | Tiles across | Offscreen |
|---|---|---|---|---|---|---|
| continuous | 2 | 1.35 | no (and the browser's 1.5× resample) | 28.85 | 13.00 | — |
| snap | **3** | **1.00** | **yes** | 21.33 | 17.58 | — |
| sharp | 2 | 1.35 | no (offscreen `n = 1`, then the browser's 1.5× resample) | 28.85 | 13.00 | 832 × 1802 texels |

**1440 × 900 desktop, DPR 2** (the sight fits the height)

| Mode | Canvas res. | Device px/art px | Integer? | Tile width (CSS pt) | Tiles across | Offscreen |
|---|---|---|---|---|---|---|
| continuous | 2 | 2.44 | no | 77.94 | 18.48 | — |
| snap | 2 | **2.00** | **yes** | 64.00 | 22.50 | — |
| sharp | 2 | 2.44 | no (offscreen `n = 3`) | 77.94 | 18.48 | 3548 × 2218 texels |

**What the tables say:**
- On a phone, `snap` cannot hold 13 tiles across exactly.
  - At DPR 2, the nearest integer, 1, gives 11.7 across: less than the sight, so its edges need a pan.
  - At DPR 3, 1 screen pixel per art pixel gives 17.6 across with tiles of 21 points, half of I-6's 40. The next integer, 2, would give 8.8 across with tiles of 42.7 points; 1 is nearer by ratio (1.35 against 2).
- `sharp` keeps exactly 13 across on every screen, with even pixel columns before the final linear pass.
- On the desktop, `snap` at 2 shows 22.5 across and the sight fits.

### Commands run (real output, node 22.22.2 on the Mac)

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 8ms using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  15 passed | 1 skipped (16)
      Tests  122 passed | 1 skipped (123)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (clean)

$ pnpm --filter @grimworld/app build
✓ 742 modules transformed.
✓ built in 108ms
(dist/: only .js and index.html)

$ pnpm exec prettier --check client
Checking formatting...
All matched files use Prettier code style!
```

CI of #135 after the push: every job passes (`client`, `tooling`, `discover` and every `cairo` job).

### Files changed in this resume

- New: `src/render/scaling.ts` (modes, canvas resolution, `snapScale`, `sharpFactor`) and its test.
- New: `src/test/fakeSurface.ts`, the fake surface now shared by the tests.
- `src/render/renderer.ts`:
  - the mode replaces the snap flag;
  - the offscreen pass;
  - `ZoomInfo` gains the mode, DPR, resolution, canvas and device scales, the integer flag and the offscreen pass.
- `src/render/pixiSurface.ts`:
  - the resolution comes from the mode;
  - `setResolution` and `renderTo` are added;
  - `surfaceResolution` gave way to `canvasResolution`.
- `src/sandbox/params.ts`, `controller.ts` (`setScaleMode`), `Sandbox.tsx` (the panel), and their tests.

No dependency was added.

### Deviations

- **`snap` lifts ADR-0003's 2× cap on a whole-numbered 3× screen** (canvas at 3), in that mode only, so that its integer is an integer of screen pixels. `continuous` (the default) and `sharp` keep the cap.
- `snap` no longer uses fractions below 1 (1/2, 1/3): the owner asked for 1, 2, 3 ….
- The canvas resolution now changes at run time when the mode changes (`renderer.resize(width, height, resolution)`).

### What to look at

Open `?fixture=cave&panel=1` and switch the "scale" choice, on a 2× and a 3× phone and on a desktop. Compare:

- the evenness of the pixel columns in `continuous` against `sharp`;
- the crispness of `snap` against its tiles across;
- in DevTools, `sharp` should still draw nothing between inputs when idle animations are off.

## Resume 3

Fix loop 2: the second passes of both audits (`[GPT-6-Sol]` 1 major and 1 minor; `[Opus 5.5]` 2 minors and notes N-1 and N-2), all accepted by the orchestrator.

### Summary

Everything is fixed and tested. Commit `e089d50` is pushed to #135, and CI is green on every job. There are now 125 tests, against 122 before.

### Finding by finding

**[GPT-6-Sol] 1 (major): no oversized offscreen.** `offscreenPlan()` no longer forces an oversampling of at least 1 past the GPU's limit.
- **Rule:** when the offscreen at its integer `n` does not fit `MAX_TEXTURE_SIZE`, `sharp` **falls back**. It draws the world directly, as `continuous`, and never asks for a larger texture.
- **Panel:** it says "sharp falls back: its offscreen does not fit the GPU's texture limit; drawn directly, as continuous", and `ZoomInfo.sharpFallback` is true.
- **Test (1440 × 900, resolution 2, limit 2048):**
  - no render texture is created and no offscreen pass runs;
  - the world is on the stage, and the fallback is reported;
  - with a 4096 limit on the same window, the pass comes back within the limit.
- **Also:** the old code lowered the oversampling to a non-integer `n` when the limit fell between 1 and the needed oversampling. That is no longer done, since such an offscreen is not sharp bilinear. It falls back instead.

**[GPT-6-Sol] 2: leaving sharp gives the texture back at once.** `setMode()` drops the offscreen texture when the mode leaves `sharp`, without waiting for a frame. Test: with the page hidden, switching to `continuous` destroys the texture immediately and draws no frame.

**[Opus 5.5] 1: no allocation per pinch frame.**
- **Buckets:** the render texture is allocated in quarter-viewport steps of oversampling (`OFFSCREEN_BUCKET = 0.25`), never above the GPU's limit. A frame draws into the top-left part it needs.
- **Views:** the screen sprite shows that part through a lightweight texture view on the same source. The view is remade only when the needed size changes; it allocates no GPU memory.
- **Reallocation:** the texture is reallocated only when the needed size grows past it, or when it is more than two buckets too large (given back while zooming out).
- **Test:** a 60-frame wheel pinch (30 frames out, 30 back in) allocates **at most 6** textures, not 60. Existing tests are updated: the allocated size is the bucket, and the view is the needed part.

**[Opus 5.5] 2.** `dev/serveArt.test.ts` now makes its scratch folder with `mkdtempSync(join(tmpdir(), "art-test-"))`, and nothing is written inside `client/app`.

**Panel: the offscreen's cost.** The panel shows the texels drawn per frame against the canvas's own pixels (the oversampling squared), and the texels allocated against the canvas. It also shows the allocated size. Measured by `render/scaling.test.ts`:

| Screen | `n` | Texels drawn | Cost vs canvas | Allocated | Allocated vs canvas |
|---|---|---|---|---|---|
| 375 × 812, resolution 2 (DPR 2 or 3) | 1 | 832 × 1802 | **1.23×** | 938 × 2030 | 1.56× |
| 1440 × 900, resolution 2 | 3 | 3548 × 2218 | **1.52×** | 3600 × 2250 | 1.56× |
| 375 × 812, zoomed so that `s × r` = 1.01 | 2 | — | **3.8–4×** (asserted) | — | — |

### What SPK-6 must know (N-1, N-2)

- **N-1: `snap` lifts ADR-0003's 2× cap on a 3× screen.**
  - To make its integer an integer of screen pixels, `snap` renders the canvas at the screen's own ratio when that ratio is a whole number up to 3. An iPhone at DPR 3 is therefore drawn at 3× in `snap`: 2.25 times the pixels of the 2× canvas that `continuous` and `sharp` use.
  - Measure `snap` on a 3× phone for battery and heat against the others before choosing it. On a fractional ratio (2.625), `snap` keeps the 2× cap and the browser's resample remains.
- **N-2: `sharp`'s oversampling nears 2 just above an integer.**
  - The oversampling is `k = ceil(s × r) / (s × r)`. When `s × r` sits just above a whole number (1.01 → `n = 2`), `k` is close to 2, and the offscreen pass draws close to **4×** the canvas's pixels (asserted between 3.8 and 4). Just below one (0.99 → `n = 1`), it draws about 1×.
  - The cost depends on the zoom: 1.23× at the phone's default, 1.52× on the 1440 × 900 desktop.
  - The pass runs only in frames being drawn, so it costs nothing between inputs. It does cost on every animated frame: steps, pans, and idle animations at up to 15 per second. The panel shows the current cost; measure the worst zooms.

### Commands run (real output, node 22.22.2 on the Mac)

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 10ms using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  15 passed | 1 skipped (16)
      Tests  125 passed | 1 skipped (126)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (clean)

$ pnpm --filter @grimworld/app build
✓ 742 modules transformed.
✓ built in 115ms
(dist/: only .js and index.html)

$ pnpm exec prettier --check client
Checking formatting...
All matched files use Prettier code style!
```

CI of #135 after the push: every job passes (`client`, `tooling`, `discover` and every `cairo` job).

### Files changed in this resume

- `src/render/renderer.ts`: the fallback, bucketed allocation with a view, the drop in `setMode`, and `ZoomInfo`'s cost and `sharpFallback`.
- `src/sandbox/Sandbox.tsx`: the cost and fallback lines in the panel.
- `src/test/fakeSurface.ts`: the texture limit is settable.
- Tests: `src/render/renderer.test.ts`, `src/render/scaling.test.ts`, `src/dev/serveArt.test.ts`.

No dependency was added.

### Deviations

- When the GPU's limit sits between the plain offscreen and the needed oversampling, `sharp` falls back instead of shrinking to a non-integer `n` (see finding 1).
- The pinch test asserts at most 6 allocations. I did not record the exact count.

## Resume 4

The last fix loop, limited to the one finding that both third-pass audits raised (both otherwise PASS).

### Summary

- **The finding.** In `sharp`, once a larger bucket was reused, the offscreen pass drew the world into the **whole** allocated texture. The panel's cost figure counted only the part the frame needs. After a zoom, the GPU could fill up to about 2.5× what the figure said.
- **The fix (the cheaper one for the GPU).** The pass now draws **only into the needed part** of the reused texture, so the real fill equals the figure.
- **Pushed:** commit `53cadf8`, to #135; CI is green on every job. There are now 126 tests.

### How

- **Target:** the pass renders into the frame's *view*, the texture over the same source with frame `(0, 0, needed width, needed height)` that the screen sprite already drew. It no longer renders into the whole `RenderTexture`.
  - PixiJS 8 binds a Texture target's frame as the pass's viewport: `RenderTargetSystem.bind`, "if (!frame && renderSurface instanceof Texture) frame = renderSurface.frame", then `viewport = frame × resolution`.
  - The projection maps that viewport, so rasterisation is confined to the needed texels.
- **No clear:** the pass runs with `clear: false`, because a WebGL `gl.clear` ignores the viewport (it has no scissor) and would still wipe the whole allocation. Instead, the pass's root (`passRoot`) is a backdrop in the canvas's background colour (`BACKGROUND`, now shared with the application's background) covering exactly the needed part, followed by the world. Every frame repaints that part before drawing, so nothing stale shows; the screen sprite only ever shows that part.
- **Panel's allocated figure:** the test also showed that the panel's "allocated" figure was the bucket recomputed from the plan, not the texture actually held. It now reports the held texture's size (or the bucket the next frame will allocate, when none is held). The cost figure (texels drawn over the canvas's pixels) is unchanged and now equals the real fill.

### Test

`render/renderer.test.ts`, "after a zoom that reuses a larger bucket, the pass fills what the figure counts". On 375 × 812 at resolution 2:

1. Zoom out (× 0.8: oversampling 1.39, bucket × 1.5), then back in (× 1.25: oversampling 1.11, bucket × 1.25). The × 1.5 texture is reused.
2. The pass targets a view over that texture's source.
3. The texels it fills (the target's frame at its resolution, recorded by the fake surface) **equal the figure**: `offscreen.width × offscreen.height`.
4. That fill is less than 0.7 of the reused texture.
5. `cost` is that fill over the canvas's pixels.
6. The panel's allocated size is the held texture's.
7. The backdrop covers exactly the needed part.

The earlier `sharp` tests still pass. Their pass target is now the view.

### Commands run (real output, node 22.22.2 on the Mac)

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 7ms using pnpm v12.5.1

$ pnpm --filter @grimworld/app test
 Test Files  15 passed | 1 skipped (16)
      Tests  126 passed | 1 skipped (127)

$ pnpm --filter @grimworld/app lint
$ eslint .                       (clean)

$ pnpm --filter @grimworld/app typecheck
$ tsc --noEmit                   (clean)

$ pnpm --filter @grimworld/app build
✓ 742 modules transformed.
✓ built in 105ms
(dist/: only .js and index.html)

$ pnpm exec prettier --check client
Checking formatting...
All matched files use Prettier code style!
```

CI of #135 for `53cadf8` (runs 36567348056 and 36567348058): every job passes (`client`, `tooling`, `discover` and every `cairo` job).

### Files changed

- `src/render/renderer.ts`: the pass root and backdrop, the view as the pass's target, the held allocation in `zoomInfo`, and the `BACKGROUND` constant.
- `src/render/pixiSurface.ts`: `renderTo` takes a Texture, with `clear: false`; the background uses `BACKGROUND`.
- `src/test/fakeSurface.ts`: records each pass's filled texels.
- `src/render/renderer.test.ts`: the new test; the existing `passes` expectation now names the view.

Nothing else changed.

### Deviation

- The panel's "allocated" figure was corrected along with the fill: it reports the texture actually held. It belongs to the same misleading cost display the finding names, and the finding's own fallback asked for "the allocated size".
- A caveat I could not measure here: the fill is confined by the viewport, which PixiJS applies on WebGL and WebGPU alike. I checked the WebGL path in PixiJS's source (`GlRenderTargetAdaptor`: `gl.viewport`, and a `gl.clear` that ignores it, hence no clear). The WebGPU path was not read. A real GPU trace is SPK-6's.
