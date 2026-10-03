# [Opus 5.5] CLI-03g1 — the textured ground for zones and hubs

Brief: `docs/briefs/CLI-03g-textured-ground.md` (#321), lot 1 of 2. Implemented by a thread of
track CV on the Mac, 2026-10-03.

## Summary

The zone's renderer now draws, under the grid, a continuous ground made of the pack's terrain, for
the zone and both hubs:

- A **ground kind per hex**, presentation only: `GroundKind = "grass" | "water" | "earth"` in
  `render/view.ts`, `Terrain.ground` and `SandboxWorld.void` in `sandbox/world.ts`, copied to
  `ViewTile.ground` and `ViewState.void` by `toView` (the only reader in `sandbox/`).
  `placeholders.ts` is unchanged; passability stays `TileKind`'s.
- **Method B, hex-exact**: `render/ground.ts` plans a chunk's ground: each hex of a layer (grown
  by half a pixel, as before) is cut by the world-aligned 64 px cells it overlaps (convex clip), and
  each piece is filled from the atlas's cell (`grass_c`, `water_c`) in global texture space, offset
  to its cell, so the cells meet on whole art pixels and the boundary between two kinds is exactly
  the hex edge. Without the atlas, the same layers are flat colours.
- Layers in each chunk's one bake: water, grass (earth's hexes too), earth's soft fill, the lip,
  the unrevealed, the grid (land only), rocks (not on water, not under a structure).
- **The zone is an island**: outside the seed's outline is water (and wall); its void is water.
- **The hubs get their look back** on the zone's engine: grass island, water around it and beyond,
  CLI-03e's earth path (`HUB_PATHS` in `fixtures/hubs.ts`, its tiles as CLI-03e wrote them).
- **The lip**: a darker line 3 art px wide, alpha 0.55, on the land side of every land–water edge,
  joined by run so corners show no notch.
- **The void beyond the terrain**: four bands around the terrain, two hexes in, under the chunks,
  placed once per view; inside, the background stays as on `main`.
- **Timing**: `FrameStats.drawMs` (the scheduler times `draw()`), and the renderer adds `bakeMs`
  (the last chunk's drawing plus its render to a texture) and `ground` (`atlas` or `colours`). The
  page shows `data-ground` and `data-bake-ms`.
- **`verify-ground.mjs`** (`pnpm --filter @grimworld/app verify:ground`): the browser check of AC-7,
  AC-8's frame measure on any branch, and AC-9's shots.

## Method as built, and its deviations

- **Clipped pieces, not masks.** The brief says "clipped by the union of that kind's hexes". Built
  as geometry, not as stencil masks: each hex is cut into per-cell pieces (`hexPieces`,
  Sutherland–Hodgman against the cell), so the bake is one `Graphics`, as before, and the plan is
  testable without a GPU (the pieces' areas sum to the hex's). PixiJS's global texture fill sets the
  atlas page's address mode to `repeat` the first time; a sprite samples inside its frame, so
  nothing else changes.
- **The chunk's frame comes from its tiles' positions only** (`chunkFrame`), reproducing what
  `getLocalBounds` gave on `main` (the hexes grown by half a pixel, a revealed hex's 1-px stroke
  padded by PixiJS's miter ratio). A test checks it equals main's drawing's bounds for every chunk
  of every room and both hubs.
- **The chunk key** adds each tile's ground and the grounds of the ring of hexes around the chunk
  (kept per chunk), so a lip across a chunk's edge rebakes its neighbour; nothing is drawn to
  compute it.
- **`ViewTile.ground` is optional** (absent = grass), as `Terrain.ground` is: every view written by
  hand in the tests stays a meadow, and no existing test changed.
- **Earth**: each side facing a non-earth hex is moved 4 art px inward, sides facing earth stay on
  the edge, so the path's hexes join without a gap or a double alpha. The corners are not rounded
  (the brief says "rounded joins"): taste for lot 2.
- **The void as bands, not a full backdrop.** A first version drew the void over the whole frame;
  at fractional scales the existing sub-pixel seams between two chunks' bakes then showed teal
  (they showed the dark background on `main`, invisible next to the unrevealed). The bands leave
  the background inside the terrain, so those seams look as on `main`. The seams themselves are
  `main`'s, out of this lot.
- **`FrameStats`** gains `bakeMs` and `ground` besides the draw time (the brief: "times only"),
  added by the renderer's wrapper of `onDraw`; the scheduler only times `draw()`.
- **`data-draw-ms` dropped** from the page: writing it in every frame lengthened the frame being
  measured; the check times frames itself.
- **The Mac, not the VPS**: the task sends this lot to the Mac. The browser check ran there in
  headless Chromium 153.0.8010.12 (playwright-core's); the brief's "software rendering on the VPS"
  does not apply as such: the figures are still relative, CPU side only.

## The fixtures' ground

| Location | Terrain | grass | water | earth |
|---|---|---|---|---|
| zone | 45 × 30 | 1055 | 295 | 0 |
| Town A | 15 × 30 | 133 | 282 | 35 |
| Outpost B | 15 × 15 | 84 | 129 | 12 |

Every CLI-03e path hex is still floor after CLI-03f's footprints (tested); no water hex is floor in
any fixture.

## Files changed

- `client/app/src/render/ground.ts` (new): the plan, `hexCorners` (moved from `shapes.ts`, still
  exported there), `acrossSide`, `clipToRect`, `hexPieces`, `chunkFrame`.
- `client/app/src/render/shapes.ts`: `drawTerrain` draws the plan; textures or flat colours.
- `client/app/src/render/renderer.ts`: chunk key and frame, ground textures, rebake on the library,
  the void's bands, `bakeMs` and `ground` in the stats.
- `client/app/src/render/scheduler.ts`: `FrameStats.drawMs`.
- `client/app/src/render/view.ts`: `GroundKind`, `ViewTile.ground`, `ViewState.void`.
- `client/app/src/sandbox/world.ts`, `wiring.ts` (`toView` copies the ground, nothing else),
  `fixtures/zone.ts`, `fixtures/hubWorld.ts`, `fixtures/hubs.ts` (`HUB_PATHS`), `Sandbox.tsx`.
- Tests: `render/ground.test.ts` (new), `render/renderer.test.ts`, `render/scheduler.test.ts`,
  `sandbox/fixtures/zone.test.ts`, `sandbox/fixtures/hubWorld.test.ts`, `sandbox/imports.test.ts`
  (assertions added only).
- `client/app/verify-ground.mjs` (new), `client/app/package.json` (one `scripts` line).
- This report.

## Commands run

- `python3 tools/art/build.py` with the pack linked as `assets` (uncommitted symlink to the Mac
  checkout's submodule, removed afterwards, the empty directory restored): built; `out/` not
  committed, no fingerprint recorded here.
- `pnpm --filter @grimworld/app test`: 323 passed, 1 skipped (`main`: 300 passed, 1 skipped at the
  start of the lot; every existing test passes unmodified).
- `pnpm --filter @grimworld/app lint`, `typecheck`: clean. `build`, `pnpm exec prettier --check
  client indexer`, `scripts/prepush.sh`: before the push, see the pull request.
- `node verify-hubs.mjs`: `ALL CHECKS PASSED` (130 ok).
- `VERIFY_SHOTS=1 node verify-ground.mjs`: `ALL CHECKS PASSED` (42 ok). Last chunk's bake: zone
  2.6 ms, town 3.9 ms, outpost 7.4 ms at 375 × 812; 2.6, 3.9, 7.2 ms at 1440 × 900.

### AC-8: frame time at the default zoom

How: `verify-ground.mjs` installs, before the page's scripts, a wrapper of `requestAnimationFrame`
that times every callback which issued a WebGL draw (`drawElements`/`drawArrays` counted), in a
page made cross-origin isolated by the script (COOP/COEP added to every response), so the clock
counts in µs. A walk of 30 steps (10 back-and-forth steps, three times) in the zone at the default
zoom, `idle=0`. `main` ran from a temporary worktree at `origin/main` 54dd7cc (no client change since
this branch's base), created at `/tmp/cli03g1-main` and removed by that path, its dev server serving
this branch's atlas (`GRIMWORLD_ART_OUT`). Same machine, same browser, alternating runs, the same
sequence (`VERIFY_MAIN=1` on both: the zone only). CPU time only: the GPU's work is not in it.

Final code (rounds 18–21), median and p95 of the frames drawn, in ms:

| Size | Run | main median | branch median | main p95 | branch p95 |
|---|---|---|---|---|---|
| 375 × 812 | 18 | 0.075 | 0.075 | 0.570 | 0.863 |
| | 19 | 0.085 | 0.080 | 0.621 | 0.568 |
| | 20 | 0.075 | 0.070 | 0.630 | 0.616 |
| | 21 | 0.070 | 0.075 | 0.690 | 0.585 |
| | mean | 0.0763 | 0.0750 (−1.6 %) | 0.628 | 0.658 (+4.8 %) |
| 1440 × 900 | 18 | 0.075 | 0.085 | 0.700 | 0.619 |
| | 19 | 0.080 | 0.085 | 0.695 | 0.773 |
| | 20 | 0.070 | 0.077 | 0.649 | 0.705 |
| | 21 | 0.080 | 0.085 | 0.734 | 0.705 |
| | mean | 0.0763 | 0.0830 (+8.9 %) | 0.695 | 0.701 (+0.9 %) |

Budget: median within +10 %, p95 within +25 %: met at both sizes, the 1440 × 900 median closest
(+8.9 %, about 7 µs). Frames drawn per 30-step walk: 375 × 812 the same (520–528 on both);
1440 × 900 `main` 525–530, branch 514–522, about 2 % fewer on the branch: a hint of GPU-side cost,
which this measure does not time.

The history, so the reviewer sees how the figures were taken: earlier rounds (void re-placed each
frame, three data attributes written each frame, all callbacks timed, the branch's run also visiting
the hubs between the two sizes) gave a 1440 × 900 median of +15 to +25 %. Two experiments (the void
hidden; the ground in flat colours) did not move it; making the void static, writing page data only
on change and running the same sequence on both brought it to the figures above. The figures are
at the clock's floor (5 µs steps on frames of 60–100 µs) and the machine's load changed during the
session (`main`'s own p95 moved from 0.40 to 0.95 ms between rounds): read them as relative.

## Shots (AC-7, AC-9)

In the thread's library folder (`shots/`), untracked, never committed, attached or posted (D-73):
`ground-<zone|town|outpost>-<size>.png` and `…-walked.png` at both sizes, and
`zoom-<size>-<continuous|snap|sharp>-<13|9|25|4>.png` (24). Described in words:

- The zone: textured grass (the pack's first green, fine darker and lighter flecks) on every inside
  hex, the hex grid over it; to the East (`x < 0`) and outside the outline, flat teal water; the
  coast follows hex edges in a zigzag, with the darker lip on the grass side. The rocks stand on
  grass only. Beyond sight the dimming and the unrevealed chunks draw as before.
- The hubs: the island of textured grass in water on every side; the buildings and props stand on
  it; the earth path (the front road, the climb to the middle street, the street, the climb to the
  castle) reads as browner rows at alpha 0.5, subtle at the default zoom.
- Zoom and modes: at 4, 9, 13 and 25 across in `continuous`, `snap` and `sharp`, no seam between
  cells and no gap between layers seen by eye; at 25 across in `sharp`, the only artefact is the
  pre-existing sub-pixel seam between two chunks' bakes, dark on dark as on `main`.

## Acceptance criteria

- AC-1: `git diff origin/main -- client/app/src/sandbox/placeholders.ts` is empty (0 lines);
  `imports.test.ts` "the ground is presentation…": no `ground` in `placeholders.ts`, `toView` the
  only reader of a terrain's ground in `sandbox/`, `render/ground.ts` imports no sandbox.
- AC-2: `zone.test.ts` "the zone's ground", `hubWorld.test.ts` "a hub's ground" (island, water and
  wall off it, path earth and floor, arrival and doors land, no water floor in any fixture).
- AC-3: `ground.test.ts` "groundPlan (AC-3)" (cells cover each layer on multiples of
  `TILE_WIDTH`; the lip exactly the land–water edges, across a chunk and into the void; grass only
  gives one layer and no lip; no grid on water; no rock on water).
- AC-4: `renderer.test.ts` "the ground in the bakes" (same count and sizes as the view without its
  ground; a ground change rebakes its chunk only; a lip across the edge rebakes the neighbour; the
  library rebakes every chunk once, then nothing, `host.quiet()`), `ground.test.ts` "chunkFrame"
  (equal to main's bounds for every chunk); the on-demand tests unchanged and passing.
- AC-5: without an atlas the layers are flat colours; every existing renderer test passes
  unmodified (none updated).
- AC-6: `walkFollowsPreview`, `wiring`, `session`, `placeholders`, CLI-03c/03d/03f's tests pass
  unmodified; `verify-hubs.mjs` passes.
- AC-7: `verify-ground.mjs` at both sizes in the zone and both hubs: `data-ground=atlas`, a walk,
  the camera within 0.0 px, no frame after the walk, no page error. Run on the Mac (see Deviations).
- AC-8: the table above.
- AC-9: shots described above; the cells are drawn at integer world positions (`hexPieces`, the
  fill's matrix `translate(cell.x, cell.y)`) and the atlas extrudes each tile's edges (CLI-03e).
- AC-10: test, lint, typecheck above; build, prettier and `scripts/prepush.sh` before the push;
  CI on the pull request.
- AC-11: the owner's eye on the public site after the merge.

## Deviations from the brief

Listed under *Method as built*: pieces instead of masks; `ViewTile.ground` optional; earth corners
not rounded; the void as bands; `FrameStats` gains `bakeMs` and `ground`; `data-draw-ms` dropped;
the Mac instead of the VPS (the task's choice).

## Escalations

None. Nothing outside the allowlist was edited.

## Open questions

- Lot 2 (the foam) will retune the lip; the constants are `LIP` and `EARTH_ALPHA`/`EARTH_INSET` in
  `render/shapes.ts`.
- The sub-pixel seams between two chunks' bakes at far zoom (dark dots between the unrevealed and
  the land at 25 across in `sharp`) are `main`'s; a later lot may overlap the frames by a pixel.
