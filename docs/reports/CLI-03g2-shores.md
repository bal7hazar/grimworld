# [Opus 5.5] CLI-03g2 — the pack's foam on the shores

Brief: `docs/briefs/CLI-03g-textured-ground.md` (#321), lot 2 of 2, after CLI-03g1 (#332, its report
`docs/reports/CLI-03g1-textured-ground.md`). Implemented by a thread of track CV on the Mac,
2026-10-03, from `main` at 3d3950f.

## Summary

- **`tools/art`**: a `[[tileset]]` entry takes an optional `cell` side (default 64). One new entry
  cuts the first 192 × 192 cell of `Terrain/Tileset/Water Foam.png` as `foam_c` (role `tile`,
  untrimmed, anchored top-left, edges extruded, like the other tiles). The build's check is now "a
  tile's frame is exactly its entry's cell". The README's *Buildings, props and tiles* section says
  so and names the tiles the zone's renderer reads (`grass_c`, `water_c`, `foam_c`).
- **The foam in the chunk bakes** (`render/ground.ts`, `groundPlan(...).foam`): one foam still
  centred under every land hex that touches water (a *coastal* hex), drawn after the water and
  before the grass, as the pack composes its shore. It is planned from the water's side: for each
  water hex of the chunk, the coastal land hexes within `FOAM_REACH` = 2 steps (a 192 px square
  centred on a hex reaches two steps, and at most touches the third). The part of each foam cell
  over that water hex is one piece, clipped to the hex, filled from `foam_c` in global texture
  space at the cell's corner, which is rounded to whole art pixels. So a chunk draws only on its own
  hexes and its frame does not change. The grass covers the rest of the cell, as in the pack.
- **The chunk key** looks three steps around the chunk instead of one (`ringOf`): two steps out to
  a land hex whose foam reaches the chunk, plus one more to that hex's own water.
- **The foam over the void** (`voidFoam`, new): see *The void* below. Without it, the zone shows
  no foam at all at the start: its revealed coast faces the void, not water inside its terrain.
- **No atlas, no foam**: the fallback stays CLI-03g1's flat colours and lip.
- **The lip is kept** as CLI-03g1 drew it (3 art px, alpha 0.55, `LIP` in `render/shapes.ts`):
  see *The look*.

## The void (the review's note on `placeVoid` and `VOID_REACH`)

CLI-03g1's void is still four sprites of the flat water cell, stretched around the terrain
(`placeVoid`, `VOID_REACH`). This lot leaves them as they are. The foam over the void goes on top
of them, in the same layer (`voidLayer`'s fifth child, under the chunks):

- `voidFoam(tiles, void)`: when the void is water, the pieces of every coastal land hex's foam over
  the hexes outside the terrain within `FOAM_REACH`, each clipped to its void hex. The same
  coastal rule applies: a revealed land hex with water across a side, the void counting as water.
- The pieces are grouped by the 15 × 15 chunk of the void hex they lie over. Each group is baked as
  a chunk is (the same bake, resolution rule and √2 steps), at its own frame, the pieces' box on
  whole art pixels, and drawn again only when its pieces change. A frame draws one sprite per
  group, as for the chunks.
- **Texture count**: with the atlas, the zone gets 5 more baked textures than CLI-03g1 (one per
  group). The chunks' textures keep their number and size (CLI-03g1's test, unchanged). The
  renderer test "rebakes every chunk once when the library arrives" now expects 12 bakes plus one
  per group (see *Tests updated*).
- **Why baked**: a first version drew one full foam sprite per coastal border hex (29 in the zone).
  It cost +14 to +18 % median at 1440 × 900, with ≈20 % fewer frames drawn. A second version drew
  the clipped pieces as one live `Graphics` and still cost +18 %. A run with the void's foam
  switched off matched `main`. Baking brought it within the budget (below).

Counts at the start of each location (initial state, from the plan functions):

| Location | Revealed hexes | Coastal land hexes with foam | Pieces over the terrain's water | Pieces over the void |
|---|---|---|---|---|
| zone | 520 | 29 | 0 | 196 |
| Town A | 450 | 49 | 163 | 176 |
| Outpost B | 225 | 36 | 125 | 131 |

The hubs' islands also reach the edge of their terrain on some sides (26 and 19 land hexes on the
terrain's border), so the void's foam matters there too.

## The look (the shots, in words)

The foam cell, measured with the pipeline's Python: 192 × 192, 10.9 % of its pixels drawn, two
colours, fully opaque where drawn. Its drawn part is a light, rounded square body of about one
tile, a darker shade under its lower side, and sparse dashes up to about 10 px around it, all
within the cell's centre 84 × 84 px. The pack puts the body under a square land tile, whose rounded
transparent edge lets a rim of it show.

On our hexes (method B, hex-exact):

- Along a hex's **vertical sides**, the body lies exactly under the hex: what shows on the water
  is the dashes, a few pixels off the edge.
- Along the **slanted sides**, the square body's corners stick out past the hex. They show as small
  light wedges of foam at the coast's corners, larger on the lower slanted sides, where the shade
  is too.
- The overlap of two neighbours' cells (each land hex has its own) adds dashes. It does not darken
  anything, because the drawn pixels are opaque.
- At the default zoom (13 across) the coast reads as the darker lip on the grass and light foam
  breaking on the water at each hex corner, along every coast: the zone's East shore and its bottom
  row facing the void, and all around both hubs' islands. At 4 across, the wedges are clearly
  square-born. At 25 across they are flecks.
- No foam shows next to an unrevealed hex (an unrevealed hex casts none), so the zone's unrevealed
  rows still end in a dark zigzag against the void, as on `main`.

**Decided (thread, by the brief's method, reversible):** keep the pack's composition (one still,
centred, grass over its inner part), and keep the lip, which marks the vertical sides where the
foam shows only dashes. The constants for the owner's eye are `LIP` (`render/shapes.ts`) and the
manifest's foam cell (another still of the strip is one number). What would reverse it: the owner
finds the wedges wrong. Then the next step is a hex-shaped foam (derived art, which design/10
leaves to the commission) or the foam's dashes alone (the body cut out by clipping), not a
constant.

Shots: in the thread's library folder (`shots/`), untracked, never committed, attached or posted
(D-73). `ground-<zone|town|outpost>-<375x812|1440x900>[-walked].png` (12) and
`zoom-<size>-<continuous|snap|sharp>-<4|9|13|25>.png` (24). At the four zoom presets in the three
modes, no seam between cells or between the foam and the water was seen by eye. In `sharp` at 25
across, the only artefact is CLI-03g1's dark sub-pixel seam between two chunks' bakes, unchanged.
`foam-cell-x3.png` is a local enlargement of the pack's cell for this description, also never
committed.

## Frame time (AC-8's budget, kept)

How: `client/app/verify-ground.mjs` as CLI-03g1 built it, unchanged: a 30-step walk in the zone at
the default zoom, `VERIFY_MAIN=1` on both sides (the same sequence), the page cross-origin isolated
(µs clock), CPU time of the frames that issued a WebGL draw. `main` ran from a temporary worktree
at `origin/main` 3d3950f (`/tmp/cli03g2-main`, created and removed by that path), its dev server
serving this branch's atlas (`GRIMWORLD_ART_OUT`; `main` does not read `foam_c`). Same machine (the
Mac), same headless Chromium 153.0.8010.12, alternating runs. Commit measured: 578934a. The next
commit only reorders the bakes inside one frame so that `bakeMs` reports a chunk (see *Deviations*).

Command, run from `client/app` (per round and side):
`GRIMWORLD_ART_OUT=<this worktree>/tools/art/out VERIFY_MAIN=1 VERIFY_ROOT=<root> VERIFY_MEASURE_OUT=<file> node verify-ground.mjs`

Median and p95 of the drawn frames, in ms, and the frames drawn per walk:

| Size | Round | main median | branch median | main p95 | branch p95 | main frames | branch frames |
|---|---|---|---|---|---|---|---|
| 375 × 812 | 21 | 0.080 | 0.060 | 0.485 | 0.450 | 517 | 520 |
| | 22 | 0.053 | 0.045 | 0.475 | 0.428 | 514 | 511 |
| | 23 | 0.060 | 0.045 | 0.450 | 0.425 | 520 | 523 |
| | 24 | 0.045 | 0.050 | 0.425 | 0.420 | 517 | 519 |
| | 25 | 0.055 | 0.050 | 0.461 | 0.427 | 518 | 527 |
| | 26 | 0.045 | 0.050 | 0.422 | 0.420 | 513 | 520 |
| | **mean** | 0.0563 | 0.0500 (−11.2 %) | 0.453 | 0.428 (−5.4 %) | | |
| 1440 × 900 | 21 | 0.075 | 0.085 | 0.490 | 0.479 | 417 | 367 |
| | 22 | 0.095 | 0.080 | 0.510 | 0.461 | 377 | 376 |
| | 23 | 0.075 | 0.075 | 0.475 | 0.458 | 388 | 407 |
| | 24 | 0.075 | 0.085 | 0.475 | 0.476 | 456 | 375 |
| | 25 | 0.070 | 0.075 | 0.469 | 0.465 | 406 | 374 |
| | 26 | 0.075 | 0.075 | 0.474 | 0.479 | 396 | 403 |
| | **mean** | 0.0775 | 0.0792 (+2.2 %) | 0.482 | 0.470 (−2.6 %) | | |

**Budget**: median ≤ +10 %, p95 ≤ +25 % against `main`. **Met at both sizes.** The figures sit at
the clock's floor (5 µs steps on frames of 45–95 µs). They are relative, CPU side only, on one
machine: the GPU's own work is not in them. The frames drawn per walk at 1440 × 900 vary on both
sides (367–456): read them as noise, not a trend. The earlier versions' rounds (sprites, a live
`Graphics`, the off switch; rounds 1–16) are summarised under *The void*.

**A chunk's bake** (no budget, as in lot 1: it happens at load, a reveal and a zoom step), the
last chunk's bake that the page reports, in one full check run each, same session:

| Location | main 375 × 812 | branch 375 × 812 | main 1440 × 900 | branch 1440 × 900 |
|---|---|---|---|---|
| zone | 2.90 ms | 5.14 ms | 2.91 ms | 5.08 ms |
| Town A | 4.15 ms | 6.44 ms | 4.25 ms | 6.75 ms |
| Outpost B | 8.40 ms | 8.09 ms | 8.07 ms | 7.38 ms |

The foam adds about 2 ms to the bake of a chunk with a coast (the zone's and the town's last
chunk). The outpost's last chunk is about the same.

## Files changed

- `tools/art/build.py`: `cell` in `tileset_problems` and `tile_sprites`, the report's cell size,
  `verify`'s tile check against the entry's cell.
- `tools/art/manifest.toml`: the `foam` tileset (`foam_c`, `cell = 192`), the section's comment.
- `tools/art/tests/test_build.py`: `test_the_foam_tile`, `Tiles.test_a_cell_of_another_side`
  (a synthetic 192 px sheet, packed and checked; a 64 px claim on it fails the check),
  `Tiles.test_a_cell_side_is_checked`. The existing 64 × 64 test is unchanged.
- `tools/art/README.md`: *Buildings, props and tiles* only.
- `client/app/src/render/ground.ts`: `FOAM_SIZE`, `FOAM_REACH`, `FoamPiece`, `foamOrigin`,
  `hexesWithin`, the plan's `foam`, `voidFoam`.
- `client/app/src/render/shapes.ts`: `GroundTextures.foam`, `drawFoam` (after the water layer).
- `client/app/src/render/renderer.ts`: `GROUND_TILES.foam`, the key's three-step ring, the void's
  foam bakes, `piecesFrame`.
- Tests: `render/ground.test.ts` (the foam, the void's foam), `render/renderer.test.ts` (see
  below).
- This report.

## Tests updated, and why

- `renderer.test.ts`, "rebakes every chunk once when the library arrives": it expected 12 bakes.
  It now expects 12 plus one per group of the void's foam (5 in the zone), counted from
  `voidFoam`: the void's foam is baked once when the atlas arrives, then nothing (`host.quiet()`
  still holds).
- `renderer.test.ts`, the helper `groundLibrary` gains `foam_c` (192 × 192), so the renderer tests
  with the atlas draw the foam.
- Every other existing test passes unmodified.

New tests: `ground.test.ts` "the foam (CLI-03g2)" (one foam still under every coastal land hex
and under no other; each piece inside one water hex; the cell's whole part over water planned; the
same pieces when the island is cut into chunks; none from or onto an unrevealed hex; none on grass
only; `hexesWithin` counts), "the foam over the void (CLI-03g2)" (none unless the void is water;
from every revealed border land hex, over void hexes only; equal to the chunks' foam over a ring
of water standing for the void). `renderer.test.ts`: a chunk rebakes when the foam across its
edge changes three steps away, not four; the void's foam is baked per group with the atlas only,
not again for the same view, and goes with the atlas.

## Commands run

- `tools/art/build.py` with the pack linked as `assets` (an uncommitted symlink to the Mac
  checkout's submodule, removed afterwards and the empty directory restored): built. `foam_c` is
  192x192 on page `atlas-1`. `out/` is not committed and no fingerprint is recorded here.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 69 tests … OK`
  (`main` has 66; the three new ones included).
- `pnpm --filter @grimworld/app test`: 333 passed, 1 skipped (`main`: 323 passed, 1 skipped).
- `pnpm --filter @grimworld/app lint`, `typecheck`: clean.
- `node verify-hubs.mjs`: `ALL CHECKS PASSED` (130 ok).
- `VERIFY_SHOTS=1 node verify-ground.mjs`: `ALL CHECKS PASSED` (42 ok), at both sizes in the zone
  and both hubs: `data-ground=atlas`, the walks, the camera within 0.0 px, no frame once the walk
  ends, no page error.
- The frame rounds above. `build`, `pnpm exec prettier --check client indexer` and
  `scripts/prepush.sh` before the push: see the pull request.

## Acceptance criteria (lot 2, as the brief lists them)

- **The foam cell cut at 192 × 192 and checked (synthetic test)**: `Tiles.test_a_cell_of_another_side`,
  `Tiles.test_a_cell_side_is_checked`, `test_the_foam_tile`. The real build packs `foam_c` 192x192.
- **One foam still under every land hex that touches water (plan test)**: `ground.test.ts`
  "one foam still under every land hex that touches water, and under no other", and the void's
  "from every revealed land hex on the border".
- **AC-8's frame budget still met**: the table above.
- **Shots as AC-7**: described above; `verify-ground.mjs` passes.
- **The owner's eye**: on the public site after the merge.
- Kept from lot 1: `git diff origin/main -- client/app/src/sandbox/placeholders.ts` is empty (this
  lot touches nothing in `sandbox/`). The mechanics tests, `verify-hubs.mjs` and
  `verify-ground.mjs` pass.

## Deviations from the brief

- **Foam planned per water hex, not drawn as one cell per land hex.** The brief says "centred under
  every land hex that touches water". Each such cell is drawn, but only its parts over water, each
  clipped to its water hex. The grass covers the rest anyway. This keeps the chunk's frame and
  draws nothing outside the chunk's own hexes.
- **The foam over the void**, baked in groups: not in the brief, which did not foresee a coast
  facing the void. It adds textures beyond the chunks' (5 in the zone). The chunks' own textures
  are unchanged.
- **Bake order**: the void's foam bakes before the chunks in a frame, so that `bakeMs` (the page's
  `data-bake-ms`, "last chunk's bake") stays a terrain chunk's when both bake.
- **The lip kept**, not retuned (*The look*).
- **The Mac, not the VPS**: as the task says.

## Escalations

None. Nothing outside the lot's allowlist was edited.

## Open questions

- For the owner's eye: the foam's light wedges at the hexes' slanted sides (the square-born body),
  and the lip. Constants first, a method change if the wedges are wrong (*The look*).
- The void's foam adds baked textures (one per border group). If GPU memory on a phone matters
  when phone work resumes, the groups can be capped in size like the chunks.
