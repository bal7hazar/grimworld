# CLI-09g — The editor's zoom without lag

Lot CLI-09g, track CV, 2026-10-05. The owner's feedback: "the tile grid lags when zooming out,
whereas it should be very light". CLI-09b (#366) made the grid one cached pattern; its report left
frame p95s of 0.5–2 s while zooming a painted 225 × 225 map, and put them on the view's window.

## What the time was

Measured with `client/app/verify-editor-zoom.mjs` (new, run by hand). The setup matches CLI-09b's grid
figures: headless Chromium (software rendering) on the VPS, the site's built atlas
(`GRIMWORLD_ART_OUT=/home/claude/site/grimworld/current/art`, read only), the page at 1440 × 900
(canvas 918 × 793 CSS px), and a painted 225 × 225 zone (a rock in nine). For each sequence it
records frame intervals (`requestAnimationFrame`, the first five dropped). It wraps the editor's and
the renderer's methods to time each window rebuild (`refreshView`, `editorView`, `setView`), each
bake pass (`bakeTerrain`) and the renderer's whole draw. It counts the textures baked, and reads the
Long Animation Frames API to split main-thread time between frame callbacks (the renderer) and the
page's messages (React).

1. **The window is not rebuilt.** At the widest zoom (258 hexes across) the window holds the whole
   painted box and its void pad: 231 × 231 = 53,361 tiles in 289 chunks. No sequence rebuilt it:
   `refreshView` ran 0 times in every run. `toView`/`editorView` cost nothing while zooming.
2. **Every chunk was baked again in one frame.** A chunk's texture follows the zoom in steps of √2
   (`bakeResolution`). Each step baked all 289 chunks in the same frame: 3,468 textures in 240 frames
   of the grid phase's zoom. A probe of one chunk with the GPU synced (`readPixels`) gave 2.8–4.2 ms
   per bake at the far zooms' resolutions (0.06–0.25) and 13 ms at 0.5. The JS side is 0.1 ms; the
   rest is SwiftShader drawing the chunk's 1,336 instructions. So one step costs about 289 × 4 ms,
   and those were the 0.6–3.6 s frames.
3. **The editor's screen re-rendered at every zoom frame.** Each camera move called
   `CanvasEvents.changed`, and `Editor.tsx` sets the status bar's zoom from it (`setAcross`). Panning
   keeps the zoom, so React bails out. Zooming changes it at every frame, so the whole editor screen
   rendered again: 50–460 ms of script in the long frames under this load.

## What changed

Three renderer options, all **off by default**: the game's renderer is unchanged and so are its
tests. The editor's canvas sets them, and it throttles one notice.

- **`bakesPerFrame`** (editor: 2). A frame bakes at once only the chunks on the screen whose tiles
  changed or that have no texture yet. That keeps what the editor shows correct: a stroke shows in
  the same frame. Every other chunk is baked at most two per frame: those on the screen first,
  nearest the centre first. A frame that leaves chunks asks the scheduler for another.
- **`keepSharper`** (editor: 2). A texture up to twice as sharp as the zoom wants is kept. A zoom out
  to half the scale bakes nothing, and a zoom back in finds its textures already sharp.
- **`rescaleAfterMs`** (editor: 200 ms). A chunk whose texture is only at another zoom's resolution
  is baked again once the zoom has been still for 200 ms. During a wheel or a pinch, the textures it
  already has are drawn scaled (nearest, pixel art).
- **The camera's notice** (`canvas.ts`, `CAMERA_NOTICE_MS` 250). The editor screen is told of camera
  moves at most every 250 ms, and once more after the last one. The status bar's "zoom N across"
  trails a gesture by at most 250 ms.

Why this and not the brief's other examples. A smaller or coarser window at far zooms would not help:
the window was never rebuilt, and fewer, larger bakes draw the same geometry. Hysteresis on the
window would not help either, for the same reason. The cost was the rebake, so the rebake is now
deferred, spread, and skipped when it is not needed.

## Figures, before and after, the same session

`VERIFY_ZOOM_BEFORE=1` measures the same build with the renderer's defaults (main's behaviour) and
every camera move told at once. Runs alternated before, after, before, after. Median / p95 / max of
the frame interval in ms; load is `/proc/loadavg` (1 min) at the sequence's end. Another thread was
measuring on this machine.

| Sequence | Before 1 | After 1 | Before 2 | After 2 |
|---|---|---|---|---|
| Zoom from the widest (258 ↔ 143 across, 3 %/frame) | 50 / 367 / 1400 (load 4.1) | 33 / **67** / **83** (6.7) | 67 / 600 / 983 (10.1) | 67 / **133** / **283** (10.9) |
| Sweep from 120 out to the widest and back (106 ↔ 258) | 67 / 633 / 833 (4.4) | 33 / **117** / 567 (8.5) | 67 / 800 / 3233 (10.4) | 50 / **100** / **117** (11.9) |
| Wheel steps from the widest (5 %/frame for 10 frames, 20 still; 258 ↔ 97) | — | — | 17 / 100 / 1133 (8.2) | 67 / 117 / **150** (12.1) |
| Pan at the widest | 50 / 67 / 233 (5.6) | 33 / 50 / 133 (8.1) | 67 / 117 / 233 (11.4) | 50 / 83 / 250 (10.8) |
| Pan at 120 across | 33 / 50 / 300 (7.4) | 33 / 50 / 50 (7.3) | 50 / 117 / 683 (11.8) | 50 / 67 / 150 (9.6) |

Textures baked in a sequence: before, 3,468 (zoom), 4,335–4,624 (sweep) and 2,312 (steps); after,
0–2, 0 and 212. The wheel steps were added after Before 1, so that run has no figure for them.

`verify-editor.mjs`'s own grid phase, same build: 258 across zoom 33.4 / 66.7 ms and 121 across zoom
33.4 / 83.4 ms (median / p95). CLI-09b reported 66.7 / 533.3 and 66.7 / 1399.9.

### The target

- **Zooming at the widest zooms, p95 under 100 ms**: met at load 6.7 (67 ms) and on the sweep at
  load 12 (100 ms, which is not under). Not met at load 11–12 for the zoom from the widest (133 ms)
  or the wheel steps (117 ms).
- **No frame over 250 ms**: not met. There are five "after" zoom runs, not six, and two of them
  miss the 250 ms maximum: 283 ms on the zoom from the widest at load 10.9, and 567 ms on the sweep at
  load 8.5. The other three stay under it (83, 117 and 150 ms). *(Corrected in CLI-09e part 3,
  review t-0140 of #373.)*
- **Panning no worse**: the medians and the p95 are no worse: every "after" one is at or below the
  "before" one beside it. One maximum is higher: 250 ms after against 233 ms before, at the widest
  zoom in the second pair (17 ms more). *(Corrected in CLI-09e part 3, review t-0140 of #373.)*

**What is left, and why.**
- **React.** The longest main-thread frames after the change are React rendering the editor screen
  again for the throttled notice. LoAF attributes 56–161 ms to `MessagePort.onmessage` per render,
  at most four a second. A render of the whole screen for a status-bar number is
  `client/app/src/editor/Editor.tsx`'s (outside this lot's allowlist; CLI-09e part 2 works there). The
  fix is to keep the zoom readout in a small component of its own, or to memoise the screen's
  panels, so `setAcross` re-renders only the status bar.
- **Off-thread frames.** The other long frames have no long main-thread work at all (no LoAF entry,
  draw ≤ 30 ms). They are the GPU process (SwiftShader) falling behind while the machine's load is
  6–12 on 8 cores. They appear the same way while panning with nothing baked, before and after.
- **The grid.** One run with the grid layer off (`VERIFY_ZOOM_GRID=0`) had the sweep at 50 / 67 /
  100. The grid-on sweeps spread from 100 / 117 to 117 / 650 across runs, so the grid's share is not
  established. The overlay's own drawing, synced with `getImageData`, takes at most 7 ms.

## Larger than a zone

A painted 450 × 450 draft (twice a zone's side; R-1 refuses it as a zone) opens with its whole box
in the window at the widest zoom (453 across): 207,936 tiles, 1,024 chunks, no rebuild. Its zoom
from the widest, after, ran at 217 / 267 / 350 ms (load 3.7). The renderer's draw alone takes about
120 ms a frame there (1,024 chunk sprites), whatever the bakes. Spreading its bakes two a frame takes
more than a minute to finish under software rendering. A 600 × 600 draft did not open within 30 s.
These are beyond the target and not addressed. A window that shrinks or coarsens at far zooms (a
lower-resolution "overview" bake of several chunks) would be the lever there.

## Game checks (`render/**` changed)

Run on this branch with the site's atlas:

| Check | Result |
|---|---|
| `node client/app/verify-fog.mjs` | ALL CHECKS PASSED (48 ok) |
| `node client/app/verify-ground.mjs` | ALL CHECKS PASSED (42 ok) |
| `node client/app/verify-water.mjs` | ALL CHECKS PASSED (103 ok) |
| `node client/app/verify-hubs.mjs` | Passes at `bf4381a`: ALL CHECKS PASSED, 130 ok (t-0133's recheck). *(Corrected in CLI-09e part 3, review t-0140 of #373: this row first gave 126 ok and 4 failed, "data-frames stops growing once it stands"; those 4 came from a run before the rebase onto main. `bf4381a` contains #368, "verify-hubs allows the animated foam's frames": the likely difference.)* |
| `node client/app/verify-editor.mjs` (run, not edited) | ALL CHECKS PASSED (117 ok) |

Unit tests (`pnpm --filter @grimworld/app test`): 63 files passed, 1 skipped; 685 tests passed,
1 skipped. That includes `src/render/renderer.bakes.test.ts` (new): the default still bakes every
chunk in a zoom step's frame; `bakesPerFrame` bakes on-screen chunks at once and the rest two a
frame, nearest first, until all are done and the scheduler sleeps; a changed chunk on the screen
bakes at once; `keepSharper` skips a zoom out within 2× and rebakes past it or on a zoom in;
`rescaleAfterMs` holds the rebakes while the zoom goes on and bakes once it is still. `typecheck`
and `lint` are clean.

## Choices (reversible)

1. **The budget is two chunks a frame.** It was measured against four. Four made the frames with
   bakes heavier, with no clear gain in time to full sharpness at this noise level. On a desktop GPU
   a bake is a fraction of a millisecond, and all 289 chunks are sharp again in about 2.4 s at 60 Hz,
   centre first.
2. **The game keeps its behaviour.** The options default to today's rules. Turning them on for the
   game (its pinch rebakes every chunk at once too) is a separate decision, to measure on a phone.
3. **A 250 ms status notice.** The zoom readout may trail by up to 250 ms. To reverse, set
   `CAMERA_NOTICE_MS` to 0.

## Not checked

- A real GPU, or a phone: every figure is headless software rendering on a loaded VPS.
- The visual effect of deferred bakes: up to 2× upscaled chunks during a zoom in, until they are
  baked again, sharpest at the centre first. No capture was taken.
