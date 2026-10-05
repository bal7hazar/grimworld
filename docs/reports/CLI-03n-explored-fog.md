# [Opus 5.5] CLI-03n — Exploration by sight (D-213), and its frame budget

The owner's request (2026-10-05): show only the tiles the adventurer has explored with their sight,
not the whole chunk the chain reveals. The project manager's decision **D-213** (reversible; the owner
may ask for the other variant):

| State of a tile                                         | Drawn as                                                       |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| Never in sight (even if its chunk is revealed on chain) | hidden, as an unrevealed tile                                  |
| Explored (in sight once), out of sight now              | grayscale terrain and obstacles; goblins on it drawn in colour |
| In sight now (radius 6, `ViewState.sight`)              | full colour                                                    |

Zones and dungeons only; hubs unchanged. The chain, the rules and `client/sim` are unchanged:
presentation only (`client/app`).

The lot was written by t-0106 on the Mac (`a5624c9`..`5deae38`); t-0112 measured it on the VPS and
found the frame budget broken; t-0113 (this report) brought it within the budget on the same branch
(`f425f8e`, `188f2c8`, `6d43bd4`).

## The lot as t-0106 built it

- **The explored set** (`render/fog.ts`, `sandbox/wiring.ts`): `SandboxState.explored`, the tiles in
  sight at least once since the instance opened, by `"x,y"`. It opens on the sight of the entry, grows
  on each step (`explore`, the same set when nothing is new), and starts again with a new instance.
  None in a hub. It is lost on a reload (accepted for now; said in `fog.ts` and `wiring.ts`).
- **The view** (`toView`): an instance's tiles never in sight are sent as `unrevealed` (`fogTiles`);
  the actors drawn are the adventurer and every goblin on an explored tile (`drawnActors`), as the
  client holds it; `ViewState.fog` (`sightRadius`) asks for the grayscale. Selection and targeting
  are unchanged: only a goblin in sight (`seen`) can be selected.
- **Grayscale**: each chunk's bake has a grey twin, baked once through a `ColorMatrixFilter`
  (`desaturate`, luma 0.3 / 0.6 / 0.1) into a texture (`Surface.bake(…, grey)`), never filtered in a
  frame. The void's bands and foam have grey twins too, dimmed as the overlay dims the tiles beside
  them; the atlas's obstacle stills and the water's cell are baked grey once each.
- **`?fog=full`**: the explored tiles stay in colour beyond sight (dimmed, as before CLI-03n); the
  tiles never seen stay hidden. A few lines (`FogMode`).
- **Checks**: `data-fog` on the room (tiles drawn hidden, explored, in sight; goblins beyond sight;
  the explored set's size), `verify-fog.mjs` (a walk at 1440 × 900 and 375 × 812, both looks: the
  counts, a goblin beyond sight drawn, sampled pixels grey beyond sight and in colour in sight, the
  bake of an exploring step, the frame time), unit tests (`sandbox/fog.test.ts`, `renderer.test.ts`).
- **Documents**: design/11's sight row, design/18's _Terrain_ and _Beyond sight_ rows (the project
  manager's lending), the PLAN row.

## What broke the frame budget (t-0112's figures, the cause)

t-0112 measured `5deae38` against `main` on the VPS (site atlas, load about 7, three main/branch pairs
per size, ms per frame, median of the three pairs). Every check passed; the budget did not:

| Fog walk, look and size | main median / p95 | branch median / p95 | ratio median / p95 |
| ----------------------- | ----------------- | ------------------- | ------------------ |
| atlas 1440 × 900        | 0.68 / 4.4        | 1.25 / 16.5         | 1.75 / 3.51        |
| atlas 375 × 812         | 0.59 / 2.0        | 0.74 / 9.8          | 1.29 / 4.40        |
| plain 1440 × 900        | 0.56 / 4.1        | 0.78 / 13.5         | 1.40 / 3.67        |
| plain 375 × 812         | 0.51 / 2.7        | 0.63 / 8.6          | 1.23 / 2.89        |

Ground walk: median ×1.19 to ×1.25, p95 ×0.71 and ×1.05. Bake of an exploring step 3.0 to 4.0 ms
(median), 7 to 12 ms (max).

What t-0113 found (a frame-by-frame log of the walk, draw calls counted per frame, layers switched
on and off in one page):

- **The p95: a step that explores rebaked.** Tiles never seen were sent as `unrevealed`, so a step
  that explored changed the key of every chunk it touched (and of a neighbour whose 3-hex ring
  changed): each was rebaked in colour and again in grey (the chunk's drawing through the filter).
  16 of the walk's steps explored: 17 bakes, frames of 10 to 34 ms with 11 to 18 draw calls. `main`
  bakes only when a chunk is revealed.
- **The median: draw calls.** A frame on `main` is 3 draw calls; on `5deae38` it was 7: the grey
  twins, the stencil mask's push, the colour ground, the mask's pop, the cover of hidden tiles
  (folded in the bakes then), the overlay, the actors. Each costs about 0.04 to 0.06 ms in headless
  Chromium here; switched off one at a time in one page (a pan, 312 frames each, 1440 × 900): all
  0.570 ms, without the mask 0.475, without the twins 0.445, without all three 0.395.

## What changed (t-0113)

1. **The chunks hold the chain's tiles** (`ViewState.revealed`, `hiddenTiles`, `syncChunks`): a step
   that explores changes no chunk's key, so it bakes nothing; a chunk is baked when it is revealed or
   at a zoom step, as on `main`. The view's `tiles` still hide what was never seen (what is drawn,
   counted and tapped).
2. **The cover** (`Renderer.cover`, `drawUnrevealed` shared with the bakes): the tiles the view hides
   are drawn as unrevealed hexes (in their grey under fog, as the twin drew them), above the ground.
   It is drawn again only when it must: a tile just explored is in sight, and the hexes in sight are
   drawn over the cover, so under fog it is redrawn when a tile it covers has left sight or a reveal
   hides one it does not cover; without fog (`?fog=full`), at every change.
3. **No stencil.** The hexes in sight are filled from the colour bakes, each from its chunk's texture
   (a void hex in sight: the water's cell or flat colour clipped to the void's bands, and the void's
   foam bakes clipped to their frames), first in the overlay's Graphics (`drawSight`). The colour
   ground is not drawn under fog. A frame is 4 draw calls: the grey twins, the cover, the overlay,
   the actors.
4. **The grey twin is the colour bake through the filter**, one quad kept with its chunk, in the
   same frame as the colour bake: a reveal costs one frame, not two, and less than drawing the chunk
   again.
5. **The overlay is drawn with the view** (as on `main`), and again only in a frame whose bakes
   replaced a texture it fills from; textures replaced or dropped are destroyed after that.
6. **A tap on a tile never seen does nothing** (below).

## Choices, and why

- **Hide by covering, not by baking.** Baking the hidden tiles as unrevealed is what made a step
  rebake. Covering costs one Graphics, rebuilt rarely; the chunks keep the bake rhythm of `main`.
- **Colour in sight by textured hexes, not a mask.** A stencil mask is two extra draw calls and their
  state in every frame. Filling the hexes in sight from the same bakes draws the same texels, in the
  overlay's Graphics (no extra draw call). They are not snapped to whole pixels as sprites are
  (`roundPixels`): the content in sight can sit up to half a pixel from where the sprite drew it,
  the same order as two chunks' sprites or a prop and the ground on `main`.
- **The cover is drawn again only when needed.** Rebuilding about 700 hexes on every exploring step
  was most of such a step's frame (3 to 12 ms of render, measured).
- **Twins from the colour bake, kept quad.** One quad through the filter is cheaper than the chunk's
  drawing through it. A quad destroyed right after its filtered bake, or a Sprite used as the root of
  repeated filtered bakes, corrupted PixiJS 8.21's batch pool (`Cannot read properties of null
(reading 'clear')` in `DefaultBatcher.break`, at 375 × 812); a Graphics kept with its chunk and
  destroyed with it does not.
- **A tap on a tile never seen does nothing** (the orchestrator's decision, 2026-10-05): in an
  instance, a tap on an in-bounds tile not in the explored set plans no walk, selects nothing, and
  ends no walk going on (`applyIntent`; the debug line says "never seen, nothing"). A tap outside
  the location still clears, as before; keyboard steps are unchanged. A tap on a tile drawn plans a
  path as before, even across tiles revealed but never seen; on the four fixtures, at the start and
  after a walk of four tiles West, no path to a tile drawn crosses a tile never seen (meadow 123 and
  136 paths, cave 79 and 79, edge 116 and 134, zone 62 and 62: none). Test: `sandbox/fog.test.ts`,
  "a tap on a tile never seen does nothing".
- **Kept from t-0106**: the explored set and its life (lost on a reload), the grey filter and its
  weights, the grey void and obstacles, `?fog=full`, goblins beyond sight drawn from the state held
  and never targetable, `data-fog`, `verify-fog.mjs`.

## Frame time

Same method as t-0112: `GRIMWORLD_ART_OUT` the site's built atlas (read only), `main` in a worktree
of its own (`e35b760`; the branch merged `3052243`, which adds only the map editor and documents, no
renderer change), three main/branch pairs, one browser run at a time, the load before each pair.
Headless Chromium renders in software; the figures compare runs on this machine, not a device.
Ratios are each pair's branch over main; the table gives the median of the three.

**Fog walk** (`verify-fog.mjs`; load 5.5, 9.4, 7.7 before the pairs):

| Look, size       | main median (3 pairs) | branch median         | main p95           | branch p95         | ratio median | ratio p95 |
| ---------------- | --------------------- | --------------------- | ------------------ | ------------------ | ------------ | --------- |
| atlas 1440 × 900 | 0.780 / 0.683 / 0.685 | 0.788 / 0.928 / 0.915 | 3.71 / 4.09 / 4.78 | 2.41 / 6.40 / 5.49 | **1.34**     | 1.15      |
| atlas 375 × 812  | 0.610 / 0.615 / 0.635 | 0.680 / 0.755 / 0.685 | 2.12 / 2.25 / 2.39 | 1.68 / 3.25 / 1.94 | **1.11**     | 0.81      |
| plain 1440 × 900 | 0.648 / 0.680 / 0.610 | 0.670 / 0.665 / 0.765 | 4.38 / 4.35 / 4.33 | 2.89 / 3.56 / 4.48 | 1.03         | 0.82      |
| plain 375 × 812  | 0.555 / 0.550 / 0.545 | 0.580 / 0.857 / 0.637 | 3.29 / 3.07 / 3.80 | 1.94 / 8.54 / 3.25 | **1.17**     | 0.85      |

**Ground walk** (`verify-ground.mjs`, the zone, atlas only as the script measures it; load 9.1, 6.3, 4.2):

| Size       | main median           | branch median         | main p95           | branch p95         | ratio median | ratio p95 |
| ---------- | --------------------- | --------------------- | ------------------ | ------------------ | ------------ | --------- |
| 375 × 812  | 0.525 / 0.515 / 0.555 | 0.570 / 0.570 / 0.617 | 1.69 / 1.65 / 2.33 | 1.87 / 1.72 / 2.27 | **1.11**     | 1.04      |
| 1440 × 900 | 0.590 / 0.545 / 0.610 | 0.655 / 0.593 / 0.680 | 2.37 / 2.38 / 3.58 | 2.10 / 2.01 / 2.04 | **1.11**     | 0.85      |

- **p95: within +25 % everywhere**, at or below `main` in five of six rows; **no p95 past 16.7 ms**
  at 1440 (the largest, 6.4 ms).
- **Median: over +10 %** at atlas 1440 (×1.34), plain 375 (×1.17), atlas 375 (×1.11) and the ground
  walk (×1.11): accepted (Deviations).
- **Noise**: the load was 4 to 9 on 8 cores, from other work on the machine. Pair 2 of the fog walk
  is visibly disturbed (the branch drew 174 frames at plain 375 against 368 and 276 in the other
  pairs; its p95 8.5 ms is that pair's). `main`'s own p95 spans 3.7 to 4.8 ms at atlas 1440 over
  three runs. The branch draws fewer frames over the same walk (ground walk: 330 to 372 at 375
  against 449 to 510): headless Chromium fires fewer display frames when the GPU process (software)
  is busier, so the branch's frames include more step frames.
- **A steady pan** (a drag of 300 moves after the walk, the same page; probe, not committed):
  0.448 to 0.465 ms on the branch at 188f2c8 against 0.47 to 0.48 ms on `main` at 1440.
- **Bakes**: over the fog walk, 3 bakes in the atlas look (a chunk revealed, colour and grey in one
  frame, 1.9 to 3.6 ms median, 9 to 16 ms max; the void's foam groups) and 1 in the plain look (9 to
  21 ms); 17 on `5deae38`. A step that explores bakes nothing.

Raw figures: the thread's library folder (`measures/*.json`), not committed.

## Files changed (t-0113)

- `client/app/src/render/renderer.ts`: `hiddenTiles`, the cover, `drawSight` and `clipToBox`, the
  grey twin from the colour bake, the overlay drawn with the view, retired textures.
- `client/app/src/render/shapes.ts`: `drawUnrevealed` (shared by the bakes and the cover);
  `drawOverlay` takes what to draw under it.
- `client/app/src/render/view.ts`: `ViewState.revealed`.
- `client/app/src/sandbox/wiring.ts`: `revealed` in the view; the tap rule.
- Tests: `sandbox/fog.test.ts` (the renderer's fog layers rewritten: no mask, the hexes in sight
  filled from the bakes, the cover, a step that explores bakes nothing; the void in sight; the tap
  rule), `render/renderer.test.ts` (the world's children; a step bakes nothing),
  `sandbox/session.test.ts` (a tap outside the location ends the walk, as a tile never seen no
  longer does), `sandbox/loop/hubDoors.test.ts` (the paths compared on the tiles a tap can reach).
- `docs/reports/CLI-03n-explored-fog.md` (this report).

## Deviations

- **The median budget is not met**: +34 % at atlas 1440, +17 % at plain 375, +11 % at atlas 375 and
  on the ground walk (budget +10 %). Accepted by the project manager, **D-218** (2026-10-05;
  reversible if a phone or a slower desktop shows it): the price of D-213's grey layer. The p95 and
  the 16.7 ms ceiling are met.
- `main` was measured at `e35b760`, not at the merged `3052243` (moving that worktree was refused);
  the commits between add the map editor and documents only.
- The ground walk is measured in the atlas look only, as `verify-ground.mjs` does (t-0112 likewise).

## What was not checked

- **A shore at the edge of the unexplored.** The chunks are baked from the chain's tiles, so where a
  tile explored borders a tile never seen across a coast, the bake can draw the lip (land toward
  water) or foam (up to two hexes into explored water from unseen land) toward a hidden tile. The
  zone holds 295 terrain water tiles; on the shots of the fog walk the frontier is clean (land
  against the cover), but no check samples a coast at the frontier. If it shows, the fix is a patch
  over the frontier's coastal hexes drawn from the hidden view, without rebaking.
- `?fog=full` was checked by the unit tests only (no browser run).
- The explored set on a phone or a slower desktop; the figures are headless software rendering.
- The sub-pixel offset of the hexes in sight (up to half a pixel against the sprites) was judged on
  shots, not measured.
