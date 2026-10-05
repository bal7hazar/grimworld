# CLI-03o part 1 — The pack's water frames in the atlas

Track CV. For part 2 (the renderer), which waits for CLI-03n. This part touches only `tools/art`.
No pixel of the pack is reproduced here (D-73): pieces are described in words and figures.

## What the pack has

Measured read-only on the pack (file sizes with `file`, colours and bounding boxes with Pillow).

- **The water is flat.** `Terrain/Tileset/Water Background color.png` is one 64 × 64 cell of a
  single colour, (71, 171, 169, 255). It has no frames, so there is nothing to offset between water
  tiles.
- **The foam is animated.** `Terrain/Tileset/Water Foam.png` is 3072 × 192: one row of **16 cells of
  192 × 192**. Each cell holds a ring, 3 colours in all, alpha 0 or 255 only (no partial alpha),
  drawn around the cell's middle. Its source `Water Foam.aseprite` is 192 × 192, 16 frames, 32-bit.
- `Water Rocks_01..04` (16 frames of 64 × 64) are also animated; they are **not** in this lot.

## The timing

Read from the source: the frame header of each of the 16 frames of `Water Foam.aseprite` (byte
offset 128, then each frame's `duration` field) says **100 ms** for every frame. So the pack's own
timing is **10 fps**, a loop of 1.6 s. The manifest says `fps = 10`, `loop = true`.

## The entries (what part 2 reads in `sprites.json`)

The existing entry stays: the sprite `foam_c`, role `tile`, cell 192 × 192, baseline 0, with its
animation `still` (1 frame, the pack's frame 0). It gains one animation:

| What | Value |
|---|---|
| Sprite | `foam_c` (unchanged name; `GROUND_TILES.foam` in the renderer) |
| New animation | `foam_c/loop`, **16 frames**, fps 10, loop true |
| Frame names | `foam_c/loop/00` … `foam_c/loop/15` |
| Cell | 192 × 192, untrimmed (`frame` = `sourceSize` = 192 × 192, `spriteSourceSize` 0, 0, 192, 192, `trimmed: false`) |
| Anchor | (0, 0), the cell's top-left corner, as the still's |
| Atlas | edges extruded into the gutter like every tile; the frames are packed on the world pages (a sprite never straddles two pages) |

`foam_c/still/00` and `foam_c/loop/00` are the same pixels; the still stays for the renderer until
part 2 switches. The build prints the foam as `tile +16` in its table, `report.json` lists
`animations: { still: 1, loop: 16 }`, and `sprites.json` has
`"loop": { "frames": 16, "fps": 10, "loop": true }` under `foam_c`. The real build runs in the site's
deploy after the merge; it was not run on this Mac (the pack is not in the worktree), so `sprites.json`
is to be checked there.

### Same centre as frame 0?

Yes, by construction: every frame is the whole 192 × 192 cell, so the cell origin and the cell
centre (96, 96) are the same for all 16, and the renderer's `foamOrigin` (the cell centred under the
land hex, rounded to whole art pixels) holds for all of them. What moves is the ring's drawing
inside the cell. Measured bounding box of the opaque pixels per frame, in cell pixels
(x0..x1 by y0..y1, the end excluded), and the box's centre:

| Frame | x | y | Centre |
|---|---|---|---|
| 00 | 54..138 | 58..142 | 96.0, 100.0 |
| 01 | 54..138 | 58..141 | 96.0, 99.5 |
| 02 | 54..132 | 63..140 | 93.0, 101.5 |
| 03 | 61..132 | 67..141 | 96.5, 104.0 |
| 04 | 59..131 | 66..142 | 95.0, 104.0 |
| 05 | 59..131 | 65..143 | 95.0, 104.0 |
| 06 | 60..132 | 64..144 | 96.0, 104.0 |
| 07 | 59..134 | 62..143 | 96.5, 102.5 |
| 08 | 58..135 | 62..146 | 96.5, 104.0 |
| 09 | 56..135 | 61..146 | 95.5, 103.5 |
| 10 | 55..137 | 61..147 | 96.0, 104.0 |
| 11 | 55..136 | 60..149 | 95.5, 104.5 |
| 12 | 52..137 | 59..149 | 94.5, 104.0 |
| 13 | 52..138 | 59..147 | 95.0, 103.0 |
| 14 | 54..138 | 59..145 | 96.0, 102.0 |
| 15 | 53..138 | 58..144 | 95.5, 101.0 |

The ring's box centre wanders by at most 3 px in x and 4.5 px in y (frame 02 x, frame 11 y) from frame 0,
and the centre of mass of the opaque pixels stays within about 1 px of (95.4, 101.5) in x and 2 px in y
(x 95.0..95.9, y 100.6..102.9). The pack draws the ring breathing (4016 opaque pixels at frame 00, 6032
at frame 11, 4106 at frame 15), not sliding. The frames were kept untrimmed, not trimmed to these boxes,
so no `spriteSourceSize` offset has to be applied and every frame lines up with frame 0 as the pack drew it.

## How a hex is cut from a frame (CLI-03g1, CLI-03g2 today)

- **The water.** CLI-03g1 cuts the 64 × 64 water cell by the hex: `hexPieces(tile)` clips the hex
  (grown by `GROW`) against each 64 px art cell it overlaps (`clipToRect`), one `Piece` per cell, and the
  chunk draws the water texture through that polygon. The water's cell is one flat colour, so the cut
  never shows; the void is one sprite of that cell stretched (`placeVoid`).
- **The foam.** CLI-03g2 does not cut the foam by a grid but by the land hex that owns it:
  `foamOrigin(source)` puts the 192 × 192 cell centred under a **land** hex (`source`) that touches
  water; `foamOver(targets, at)` takes every water hex `over` within `FOAM_REACH = 2` steps of such a
  hex and clips that hex's polygon to the foam cell's rectangle (`FoamPiece`: `source`, `origin`,
  `over`, `points`). The piece is drawn after the water and before the grass, and the grass covers its
  inner part. The animated frames line up the same way: they are the same cell, so the same
  `origin`, the same `points`; only the texture changes from frame to frame.
- Do the foam's frames line up with the water's? The water has no frames (flat), so the foam's frames
  line up with each other and with frame 0 (above), and need nothing from the water.

## What the chunk bakes do with the foam today (for part 2)

Chunk bakes draw `foamOver`'s pieces (`drawFoam(graphics, pieces, foam)`) into the chunk's
`Graphics` with the single still `foam_c`, then `surface.bake` renders the whole chunk (15 × 15 hexes,
`BAKE_CHUNK`) once into one texture, a `Sprite` that is never redrawn unless the chunk's key (its tiles'
grounds, and the grounds a lip or a foam looks at across its edge) changes. The foam over the void
(`voidFoam`, `syncVoidFoam`) is baked the same way, by group of 15 × 15 hexes, under the chunks.
So the foam is **frozen into the chunk textures**: switching the texture per frame needs either
16 bakes of each chunk (the foam frame in the chunk's key; 16 × the bake time and texture memory) or
the foam out of the bake, as its own live layer (the same pieces as a `Graphics`/`Mesh` or one sprite
per source hex, masked or clipped to the water, with the frame chosen per `source`).

## The phase rule (part 2's, decided by the orchestrator)

Per land hex, since each foam cell is centred under one `source`: the same phase along one diagonal,
plus one frame per diagonal; the thread of part 2 picks the diagonal's axis (`q`, `r` or `q + r`) by
look. `frame = (t × 10 + diagonal) mod 16`, with `t` in seconds. `?water=still` compares with today.
Neighbouring land hexes that share water pieces under their overlapping foam cells (the reach is two
steps, so cells overlap) will show two frames at once on one water hex; that is the rule's visible cost
and is part 2's to judge.

## What changed in `tools/art` (and why `build.py`)

- `manifest.toml`: the `animations` key on the `foam` tileset.
- `build.py`: `tile_animation_problems` (the key's checks), `tile_sprites` (cuts the frames) and the
  report line. **`build.py` is not in the brief's allowlist**; an animation entry cannot exist without
  it (the tileset code lives there). The orchestrator's order of the day asked for "a new entry kind, or
  extend `[[tileset]]` for strips", which needs it. Reversal: the manifest alone could give sixteen
  stills `foam_f00`…`foam_f15` (`cells = { f00 = [0, 0], … }`), with no animation or rate in
  `sprites.json`.
- `tests/test_build.py`: synthetic sheets only (no pixel of the pack).
- `README.md`: a section on tiles and the foam's animation.

## Not checked

- The real build (needs the pack in the worktree): the orchestrator checks `sprites.json` after the
  site's deploy.
- Atlas size: the 16 untrimmed cells are 16 × 192 × 192 × 4 bytes = 2.36 MB raw before PNG; the sprite
  must fit one 2048 × 2048 page (16 cells of 192 px plus the gutter are two shelves, about 2000 × 400 px
  of a page, by arithmetic, not measured), but how many world pages the whole atlas then needs is only
  known from the build.

# CLI-03o part 2 — The foam animated in the renderer

Track CV. `client/app/src/render/**`, `verify-water.mjs`, `PLAN.md`. Pixels are given in words and
hex values only (D-73); the captures stay in the thread's library folder.

## What the renderer does now

- **The foam is out of the chunk bakes.** A chunk bakes its water, grass, earth, lip, grid and
  unrevealed hexes as before, without the foam; `voidFoam`'s groups are no longer baked either. The
  foam's pieces (`waterFoam` per chunk, `voidFoam` over the void, the same pieces `groundPlan`
  planned) are drawn by `FoamMesh`: one PixiJS `Mesh` per group (a chunk's water, or the void's by
  the chunk of the hex it lies over), each piece a fan of triangles on its own vertices. The mesh's
  texture is the atlas page that holds `foam_c/loop`; a piece's texture coordinates are its frame's
  rectangle plus the point's offset in its cell. **A frame of the foam rewrites the coordinates of
  the meshes on screen (one small buffer upload each), never a bake, never a geometry.**
- **Why meshes.** Re-baking a chunk at 10 fps costs a bake a frame per chunk in view; 16 baked
  variants per chunk cost 16 × the chunks' texture memory. A `Graphics` per group with 16 cached
  contexts would hold 16 geometries per group and rebuild the render group's instructions at each
  swap. The mesh holds one geometry; its position buffer never changes; only its UV buffer
  (8 bytes a vertex) is rewritten, for the groups on screen. Groups off the screen are not drawn
  (`cullFoam`) and their coordinates are not rewritten. A group whose pieces change keeps its mesh
  (`setPieces`: new buffer contents, no child added or removed, so PixiJS does not rebuild the
  stage's instructions); the meshes are never batched (`no-batch`: a batched mesh's vertices are
  copied into PixiJS's batch, and a group growing past 100 vertices broke the batcher in the
  browser); a mesh's geometry is destroyed with it (PixiJS's `Mesh.destroy` leaves it).
- **The grass still covers the foam's inner part.** The pieces are clipped to their water hex, as
  before; `trimFoam` also cuts each piece back from every side that faces a hex not drawn as water,
  by what that hex grown by `GROW` covers (0.43 px): the foam drawn over the bake then stops where
  the grass (or an unrevealed hex) baked over it stopped it. Order on screen: water, foam, grass, as
  before.
- **The phase.** `frame = (clock frame + q + r) mod 16`, axial `q = x − ⌊y / 2⌋`, `r = y`, per
  piece's source (the land hex its cell is centred under): world position only, so seamless across
  chunks and stable when the camera moves. Why `q + r`: `r` alone gives a whole row one frame, so a
  straight East–West shore (the hubs' south shores) pulses in lockstep, which is what the owner
  asked to avoid; `q` and `q + r` both step one frame per hex along a row and one frame per two
  rows up a North–South shore. `q + r` makes a crest travel West to East and North to South, toward
  the screen's bottom right. Captures: `water-town-1440x900.png` (an East–West shore),
  `water-zone-1440x900.png` (a North–South one) in the library folder.
- **Fog (CLI-03n).** Without fog (hubs, `?fog=full`), the foam is last in the ground's layer, under
  the cover and the overlay (which dims it beyond sight as it dims the ground); no piece over a
  hidden tile. Under fog, the foam in colour is only the pieces over the hexes in sight (and the
  void within sight's radius), in one group, first in the actors' layer: over the overlay's hexes in
  sight, which are filled from bakes that no longer hold foam. Its grayscale twin is **still**
  (frame 0): baked into each chunk's grayscale twin (the twin's source quad gets the foam's pieces
  before the filter), so it costs no frame; over the void, a mesh per group of frame 0 in grayscale
  (`greyTexture`), dimmed as the bands are, culled off the screen. What was explored is
  remembered, not live.
  Never-seen tiles stay hidden: no colour piece lies over one, and the grey ones are under the cover.
- **Power (ADR-0003).** The foam is an idle animation under the same cap (`IDLE_MAX_FPS`, 15): the
  renderer asks for its next frame through `nextIdle`, the scheduler's timed path, only while a
  colour mesh's bounds meet the view; nothing while the page is hidden (the scheduler), nothing with
  `?water=still` or without the atlas's loop. The foam does not follow `?idle=0` (that is the
  actors'): the walks that measure the frame budget run with `idle=0`, and must measure the foam.
- **`?water=still`**: every piece at frame 0 (`foam_c/loop/00`, the still's pixels), no frame asked.
  The renderer reads it from the page (`pageWater`) because the sandbox's controller, which builds
  the renderer, is outside this lot's files; `SandboxParams.water` is not added for the same reason
  (see the thread's escalation).
- A PixiJS 8 trap found on the way: a child's `zIndex` makes its parent sort its children. The foam
  layer's `-Infinity` (for the actors' layer) sorted it under the chunks in the ground's layer; it
  is now set only while the layer is detached, and only for the actors' layer (a unit test holds it).

## CLI-03n follow-up: the frontier

Asked by the orchestrator (2026-10-05) after t-0124's measures on `main` at `776bf21`: the lip of an
explored land hex was drawn toward a water hex never seen (median drop 58.9 in colour, 22.0 in
grey). Cause: the lip and the foam were planned from the chain's grounds.

- `PlanOptions.hidden` (the tiles drawn but never seen): the plan's `at` gives null for them, so no
  lip faces them and no foam comes from them or lies over them; they are still baked with their
  ground, under the cover. The renderer passes CLI-03n's hidden set to the bake and to `waterFoam`.
- The bake's key marks a hidden tile only when it is water (a lip looks only for water): a step that
  explores rebakes a chunk only when it reveals water beside land. The foam's own key marks every
  hidden tile (its sources are land); its pieces are planned again then, and the grey twin is
  rebaked only when they differ (`samePieces`): measured, one bake per walk, as on `main`.
- `verify-water.mjs`'s frontier (1440 × 900, zoom 21, the hero walked to (36, 8) then (40, 6); the
  luminance drop at a land hex's side, 5 points 1.5 px inside against 5 at 12 px), every side on
  screen between a land hex seen and water, same walk on both checkouts:

  | Side | `main` 7058083 | branch |
  |---|---|---|
  | toward water never seen, colour (7 sides) | median 63.7, max 70.0 | median 0.0, max 13.9 |
  | toward water never seen, grey (9 sides) | median 29.0 | median 0.0, max 0.0 |
  | toward water seen, colour (16 + 25 sides) | median 63.7 | median 63.7 |
  | toward water seen, grey (3 + 16 sides) | median 29.0 | median 29.0 |

  t-0124's eight listed sides were all seen by this walk (it differs from t-0124's), so they read as
  positive controls here (drop 63.7); the search above replaces them.
- Unit tests: `ground.test.ts` *a coast at the frontier* (no lip toward hidden water, the lips
  toward seen water unchanged, no foam from hidden land, none over hidden water, a land hex touching
  water only through a hidden hex is no source); `renderer.textures.test.ts` (review t-0120's
  deferred minor 2): every texture baked is held or destroyed across a reveal, a zoom step and
  `destroy()`.

## Measures (AC-2, AC-3)

Headless Chromium 1243 on the VPS (software GL), the site's built atlas, one browser run at a time.
The machine was shared with other projects: `/proc/loadavg` 4.5 to 14.9 over the runs.

**AC-2, `verify-water.mjs`** (103 checks, all pass on `662e06a`): in the zone, the town and the
outpost at 1440 × 900 and 375 × 812, two captures about 100 ms apart differ on 1 839 to 6 652
device pixels, none off the foam; screen pixels against the atlas's 16 frames (the pieces rebuilt in
the page from the same modules; overlapping cells modelled in draw order): `frame = clock + q + r`
explains 99.5 to 100 % of 1 151 to 2 596 samples per capture, all in step 60.6 to 82.4 %, the `r`
axis 60.4 to 88.0 %; the `q` axis 48.5 to 71.3 % in the zone (North–South shores) and as much as
`q + r` on the hubs' East–West shores, where the two differ only by a clock shift. `?water=still` and the plain
look: two captures 100 ms apart identical, no frame in a second.

**AC-3, frame budget** (CLI-03n's method): `verify-fog.mjs` (atlas look) and `verify-ground.mjs`
walks, three main/branch pairs per size, `main` at `7058083`, the branch at `662e06a`; the frame
time is the JavaScript of each display frame that drew (the GPU's work is not in it):

| Walk, size | median, main → branch (ms), per pair | median of the pairs' ratios | p95 ratio | branch p95 max |
|---|---|---|---|---|
| fog 1440 × 900 | 0.770 → 0.905, 1.130 → 0.910, 0.895 → 0.885 | ×0.99 | ×0.78 | 3.77 ms |
| fog 375 × 812 | 0.660 → 0.765, 0.705 → 0.720, 0.697 → 0.805 | **×1.15** | ×1.19 | 4.23 ms |
| ground 1440 × 900 | 0.683 → 0.742, 0.692 → 0.645, 0.848 → 0.690 | ×0.93 | ×0.93 | 3.48 ms |
| ground 375 × 812 | 0.580 → 0.635, 0.575 → 0.655, 0.605 → 0.680 | **×1.12** | ×1.04 | 1.99 ms |

Noise: `main`'s own medians spread by up to 47 % between its three runs (fog 1440: 0.770 to
1.130 ms). Two earlier series on intermediate heads (`869320e`, `a8ba00c`, six pairs) gave ground
375 × 812 at ×1.12 again (pairs 0.97 to 1.19), fog 375 × 812 at ×0.98 and ×1.08. Budget: p95 within
+25 % everywhere, never near 16.7 ms; the median within +10 % at 1440 × 900, **above it at
375 × 812: +0.07 to +0.10 ms a frame** (the foam's meshes are one draw call each; the narrow view
holds a larger share of coast). Not resolved within this lot: see the thread's escalation.

**Idle cost**, standing still at the zone's opening coast, 1440 × 900, 10 s after 3 s, three runs
each (frames from `data-frames`; CPU from the page's `Performance.getMetrics`, `TaskDuration`, which
in headless software GL includes the rasterisation of every frame):

| | frames a second, main → branch | task time ms/s | script time ms/s |
|---|---|---|---|
| actors idle (default) | 6.4–8.3 → 5.9–8.3 | 945–957 → 948–956 | 6.8–12.4 → 9.2–15.6 |
| `idle=0` (the foam alone) | 0 → 6.0–9.1 | 0 → 915–959 | 0 → 8.4–11.9 |

With the actors idling the frame rate does not rise (software GL saturates near 8 frames a second
here; the cap is 15); with `idle=0`, standing at the coast now costs the foam's frames, about 1 ms of
script each. A device with a GPU rasterises far cheaper: not measured.

## Not checked

- A phone, a GPU-backed desktop: all browser figures are headless Chromium in software GL.
- The owner's eye on the wave (the site shows `main` once this merges).
