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
