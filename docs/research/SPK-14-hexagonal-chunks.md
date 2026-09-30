# SPK-14 — Hexagonal chunks of 251 tiles, studied

Written on 2026-09-30 by `[Opus 5.5]` under D-165. **Nothing in this note was measured by this lot.**
Its launch profile was `research`, which refused `scarb`, `snforge`, `python3 <script>` and
`git add` (REPORT.md, Escalations). The brief asks for "research (with builds)".

Every figure carries one of three labels:

| Label | Meaning |
|---|---|
| **M** | Measured earlier by SPK-7, ENG-01 or N-3, with its source; not re-measured here |
| **H** | Derived by hand here. `spikes/SPK-14/geometry.py` asserts each of these; it has **not been run** |
| **E** | An estimate built from M figures and operation counts. It is not a measurement |

AC-2 (costs measured twice beside the rectangle's) and AC-3 (bijection and assembly tested) are
**not met**. §7 lists what the next run must build and measure.

## Summary

| Question | Answer |
|---|---|
| 1. Shape and indexing | 17 rows of **11 to 19 tiles** (H). The widest row is 19, not D-165's 27: a row grows by one tile a row (half a tile on each side), not two. The bounding box is 19 × 17. Bits go row by row, South to North, with row starts from a 17-entry table. Bits 0 and 250 are corners. The chunk tiles the plane with lattice vectors `(-9, 17)` and `(19, -8)` in axial coordinates, determinant 251 |
| 2. Storage words | **No new slot, and `LIVE` kept.** Bit 250 is a corner tile, and D-134 makes corners always wall, so bit 250 of `Terrain` is always 1: it *is* `LIVE`. The 6 edge bits go to `Features` 240–245, or are derived from the ring. In `OUTLINE` and `SET_PIECE`, bit 250 is a corner whose value no rule reads, so the writer sets it (H) |
| 3. Window | Overlaps **up to 6 chunks** (H, one case shown), against 4. **The one-shift assembly does not survive.** The chunk's rows are 11 to 19 bits long in a felt, the window's are 15, so every chunk row moves by its own shift: about 32 to 48 pieces a layer (H/E) against 4. Estimated **0.25–0.6 M** in memory (E) against N-3's 64,234 (M). The window's origin parity rule (D-120) does not change; chunks start on both row parities |
| 4. Reveal and generation | **The bit-parallel generation does not carry over.** No layout with a constant row stride holds the hexagon in 251 bits: the smallest is 307 (H). So the automaton's neighbour planes and the component flood need per-row pieces or a board of two felts. That board is beyond the library's 251-bit boards. Estimate **0.6–1.0 M** a chunk (E) against 0.39–0.45 M (M). Six neighbours, sides of 9 and 11. Corners stay wall, for a new reason. Sight touches **up to 4 chunks**, so up to 3 new chunks a move, as today (H). The revealed set stays one felt |
| 5. What it changes | ADR-0006, D-120's reasoning, ENG-01 §3.2/§3.5, N-1/N-2/N-3/N-4 in the library, ENG-05, ENG-07, TOOL-01, CLI-02 and the client. The largest items are N-3 (rewritten) and N-1/N-2 (a board model the library does not have) (§5) |
| 6. Recommendation | **Keep the 15 × 15 rectangle.** The hexagon's gains are 26 more tiles a felt (about 10 % fewer chunks for the same area) and a free `LIVE`. They are paid for at every tick with goblins awake (≥ 4× the assembly, 2 more chunks read) and at every reveal. This meets D-165's own reversal condition: "the window's assembly or the reveal materially dearer". It rests on estimates (E) until the next run measures them (§6) |

## 1. The shape and its indexing (H)

Coordinates are the library's (docs/needs/hexmap.md point 3): odd-r offset `(x, y)`, axial
`q = x − ⌊y/2⌋`, `r = y`, `+y` North. On pointy-top tiles (D-11) the long sides of 11 are rows: the
South row (row 0) and the North row (row 16).

A chunk anchored at axial (0, 0) is:

```
0 ≤ r ≤ 16,   0 ≤ q ≤ 18,   8 ≤ q + r ≤ 26
```

| Row r | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | **8** | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Width | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | **19** | 18 | 17 | 16 | 15 | 14 | 13 | 12 | 11 |
| First bit | 0 | 11 | 23 | 36 | 50 | 65 | 81 | 98 | 116 | 135 | 153 | 170 | 186 | 201 | 215 | 228 | 240 |
| q from | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The widths sum to 135 + 116 = 251. D-165's formula `ab + bc + ca − a − b − c + 1` also gives 251.

**D-165's "27 tiles at the widest (11 + 2 × 8)" is wrong: the widest row is 19 (11 + 8).** From one
row to the next, the hexagon widens by half a tile on each side, not a whole tile. The bounding
box in offset coordinates is **19 × 17** (323 cells, 251 used). This matters below: 19 > 15.

**Indexing.** `bit(q, r) = FIRST[r] + q − QFROM[r]`, with two tables of 17 entries (the rows
above). The inverse finds the row as the last `FIRST[r] ≤ bit`: a search in the 17-entry table,
or a 251-entry table of `(q, r)`. Rectangles use `15 r + x` and a division. The map is a
bijection onto 0–250 by construction: rows are contiguous and consecutive. `geometry.py` asserts
it and asserts the inverse; neither has been run.

**Corners** (6): the two ends of rows 0, 8 and 16, bits **0, 10, 116, 134, 240, 250**.

**Sides** (corners included), going round: South row 0 (11 tiles) · `q = 18`, rows 0–8 (9) ·
`q + r = 26`, rows 8–16 (9) · North row 16 (11) · `q = 0`, rows 8–16 (9) · `q + r = 8`, rows 0–8 (9).
The ring holds 52 tiles and the interior 199 (13 × 13 = 169 today).

**Orientation.** The shape is symmetric on screen about the vertical through the centre. Row 8's
cells have pixel centres 4 to 22 around 13, and row 0's 8 to 18 around 13. No other orientation
exists on pointy-top tiles: a vertical side would need flat-top tiles (D-165).

**The tiling.** Translates of the chunk by the lattice `a·T_U + b·T_R` cover the plane once, with
`T_U = (−9, 17)` (across the long sides), `T_R = (19, −8)`, and `T_U + T_R = (10, 9)`.
`|det| = |(−9)(−8) − 17·19| = 251`, which equals the area. The six neighbours are `±T_U`, `±T_R`
and `±(T_U + T_R)`. Checked by hand: across each pair of opposite sides, the neighbour's side lies
on the adjacent line. For example, our `q + r = 26` side, rows 8–16, faces the `(10, 9)`
neighbour's `q + r = 27` side, rows 9–17. `check_tiling` asserts full coverage on a region, not
yet run.

**Which chunk holds a tile.** Rectangles use `(x / 15, y / 15)`. Here 251 is prime, so the lattice
is not a product of two strides. The lattice coordinates are
`a ≈ (8 (q − 9) + 19 (r − 8)) / 251` and `b ≈ (17 (q − 9) + 9 (r − 8)) / 251`, rounded, then one to
three membership tests (`chunk_of`). The game needs this on:
- a move without the window (the terrain bit of the tile entered);
- a goblin's spawn chunk (its entity id);
- the chunks the window and sight touch.

It costs a few divisions and comparisons (E: about 10k–20k), where two `div_rem` do it today.

**Row parity.** `T_U` and `T_U + T_R` move by 17 and 9 rows, both odd. Chunks therefore start on
both row parities, and the parity flag of point 2 stays, for generation and seams, as today.

## 2. The storage words (ENG-01 §3.2, §3.5)

A layer takes bits 0–250, the whole felt. The four options:

| Option | Slots | What ENG-01 loses |
|---|---:|---|
| **(a) Bit 250 is a corner, always wall: it is `LIVE`** | **0** | Nothing in `Terrain`: 1 = wall, and D-134 keeps every corner wall. The "never zeroed" rule of §2.1 holds, since a stored `Terrain` always has bit 250 set. The packer's check changes from "`LIVE` is set" to "the six corner bits are set", which is stronger. **Recommended if the hexagon is taken** |
| (b) A `LIVE`-less word class | 0 | A second rule next to §3.1's "bit 250 is `LIVE` in every record": each class must prove it is never 0. For `Terrain`, (a) is that proof |
| (c) A second felt | +1 a chunk: 453,524 at reveal (N, M, ENG-01 §10) | Pays a new slot at every chunk's first reveal. Not needed |
| (d) `LIVE` in `Features` | 0 | `Features` already has `LIVE` at 250. It does not keep `Terrain` from being 0; (a) does |

**The 6 edge bits** (dungeon side open or border, ENG-01 §3.2 today at `Terrain` 225–228) move to
**`Features` 240–245**. Bits 240–249 are free there, and `Features` is written at the reveal with
`Terrain`, so there is no extra write. Alternatively they need not be stored. A side is open
exactly when a non-corner tile of its ring is walkable: openings are drawn and frozen with the
side (D-22). That makes the bit one AND with a side mask and one comparison. Features' 240–249
then stay free.

**`OUTLINE`** (§3.5): the tile mask of a border chunk is 1 in the zone, bits 0–250. Its corners are
always wall whatever the outline says, so no rule reads the corner bits. The writer **sets bit 250
as `LIVE`**, and the reveal ignores it: 0 slots. The chunk-set record (`location × 256 + 255`)
keeps its layout. Chunks are still indexed `15 b + a` on lattice coordinates below 15 (§4), at
most 225 chunks.

**`SET_PIECE`** (2 parts, authored terrain): its terrain has wall corners, so bit 250 is 1 and
`LIVE` holds. Its placements' tile fields (8 bits) hold 0–250.

**What is lost overall:** the uniform rule "bit 250 is `LIVE`, bits 0–249 are data" becomes "except
chunk-shaped layers, whose bit 250 is a wall corner". This costs one line in §3.1, the packers'
checks and their tests. The pack and object tile fields of `Features` (8 bits) hold 0–250
unchanged.

## 3. The window (D-120: 15 × 16, origin on an even row)

**How many chunks it overlaps: up to 6 (H), against 4.** Example: the window at offset origin
(6, 2), with a chunk H0 anchored at axial (0, 0). It holds tiles of:

| Chunk | A tile of the window in it |
|---|---|
| H0 | (13, 8) |
| `+T_U` | (7, 17) |
| `−T_R` | (6, 17) |
| `−(T_U + T_R)` | (6, 2) |
| `+T_R` | (20, 2) |
| `+(T_U + T_R)` | (18, 17) |

Only `−T_U`, below, is missed: reaching it would need 19 rows. A seventh chunk would have to lie
beyond this ring of neighbours, which a 15 × 16 window cannot reach from inside H0's bounding box
(H). `check_window` enumerates all 502 origin classes (251 positions × 2 anchor parities) for the
maximum and the histogram. Not run.

Consequences for the tick (ENG-01's layout: the window reads `Terrain` and `Features` of each
chunk it overlaps, and occupancy is derived from `Features`):
- **up to 12 slot reads instead of 8**;
- up to 6 unrevealed or void chunks to test (D-136, D-134) instead of 4.

**Whether the assembly without a loop over rows survives: no (H).** Today window and chunk share
the stride 15, so a whole chunk moves by one field product. A hexagonal chunk's rows are 11 to 19
bits long, packed end to end. Between chunk rows r and r + 1, the shift into the window changes by
`15 − width(r) + L(r+1) − L(r)`, where L is the row's offset left end. For a chunk on an even row
the steps are:

```
3, 3, 1, 1, −1, −1, −3, −3, −4, −2, −2, 0, 0, 2, 2, 4
```

Only rows 11–13 share a shift. **A chunk takes 15 pieces when whole.** A window row crosses 1 to 3
chunk segments: along a row the segments alternate between widths that sum to 29 or 30, so a
15-tile row meets 3 when the middle one is 13 or narrower. So a window takes **about 32 to 48
pieces a layer** (E; `check_window` counts the maximum), against 4. Each piece:
- a mask of a run of bits (`2^hi − 2^lo`: two table lookups);
- an AND on two limbs;
- a field product by a power of two or its inverse (a lookup);
- the bookkeeping of which chunk row lands on which window row.

Tables by origin class (502 classes × 16 rows × up to 3 segments) would remove the bookkeeping. At
thousands of felts of constants, they collide with the class size (ENG-01 §1.3, D-164).

**Cost, estimated (E).** SPK-7's unit costs (M): a table lookup 1,265, a bit test through the
bitwise builtin 4,170, a loop iteration 1,520. N-3's assembly is 64,234 (M, the library) for 4
pieces a layer, 2 layers, and the ring. A row piece costs about 8k–12k with its bookkeeping, so the
terrain layer alone comes to **0.25–0.6 M in memory: 4 to 9 times N-3**. The occupancy layer is
derived from goblins' tiles in ENG-01, not assembled from chunks. Unrolled, the code grows with
the pieces; a loop over rows is what docs/CAIRO.md §3 ranks last.

**Parity of the origin.** Unchanged: the window's origin stays on an even global row, and the
flood and the library's layout take the window as today. Chunks start on both parities, so the
pieces' left ends (L above) come from two tables, for even and odd anchors.

**An alternative not taken.** A hexagonal window of the chunk's own shape would also be 251 tiles,
the library's limit. It does not remove the per-row pieces: the window follows the adventurer, so
its origin is almost never a lattice point. It also changes D-120's board, which the library's
finders take as a rectangle.

## 4. Reveal and generation

**Generation with margins: the method of SPK-7 does not carry over (H).** SPK-7 generates on the
chunk's own felt:
- neighbour planes are six field products of the whole grid (±1, ±15 ± 1);
- the component is the library's `dilate` on a stride-15 board.

Both need a layout where a neighbour is a constant shift: an affine layout `bit = s·r + q`. The
smallest such layout that holds the hexagon without collisions spans **307 bits, stride 19**
(`check_linear_layouts`). That is more than a felt and beyond the library's 251-bit boards. So
generation needs one of:

| Way | What it costs (E) |
|---|---|
| Unpack to a stride-19 board of two felts, generate there, repack | 2 × 15 row pieces to unpack and repack (about 0.2–0.35 M), and every plane and dilation on 3 limbs instead of 2 (about × 1.5 on SPK-7's 0.39–0.45 M) |
| Per-row planes on the packed felt | 6 planes × 15 row pieces × 2 passes, plus the component flood the same way: a loop over rows, or hundreds of unrolled pieces |
| The library's boards extended beyond one felt | Not in L-M1. A new board model for N-1 and N-2 |

Taken together, **about 0.6–1.0 M a chunk** (E), against **0.39–0.45 M** (M, SPK-7 §2.1). A reveal
of 3 chunks (the worst, SPK-7: 5,919,680 as a transaction, M) would grow by about 0.6–1.6 M of
computation (E). Its storage does not change: 2 new slots a chunk, as ENG-01.

**Edges and openings with six neighbours.** Sides of 9 tiles (7 non-corner) and 11 tiles (9
non-corner). A side facing a generated neighbour copies its facing side. Neither is a constant
shift of the other in the packed felt: the two sides lie on different rows (a long side) or on a
diagonal of row ends (a short one). So the copy is one piece for a long side and 7 bit moves, or a
table-driven gather, for a short side (E: 30k–60k a side, against one AND and one product today).
A drawn side takes 1 or 2 openings among its non-corner tiles, as today.

**D-134 restated.**
- *Void margin:* unchanged. The chunks beyond a location's border or outline are void: wall,
  never revealed, never stored.
- *Corners:* **the 6 corner tiles are always wall.** The old reason ("a reveal never depends on a
  diagonal neighbour") has no object: a hexagonal tiling has no diagonal neighbours, since three
  chunks meet at each vertex and all three share edges. The new reason: a corner lies on two sides,
  each facing a different neighbour. A wall corner keeps each side depending on one neighbour only.
  It also gives `LIVE` (§2).
- *D-136* (an unrevealed chunk is wall in the window): unchanged, with up to 6 chunks to test.

**How many chunks one move can reveal: up to 3, as today (H).** A sight of radius 6 spans 13 tiles.
Centred on the middle of a 9-tile side, it reaches both end vertices, so it touches the two chunks
of the side and the two at its ends: 4 chunks, 3 of them new. It cannot reach a fifth: that would
mean crossing a whole chunk, at least 16 rows or 18 columns. `check_sight` enumerates it; not run.

**The revealed set** stays one felt. Chunks are indexed `15 b + a` on lattice coordinates, with a
location's chunks placed below 15 in each coordinate. A location of about 100 × 100 tiles spans
about 7 steps of `T_R` and 6 of `T_U`, plus 4 of skew: under 15 × 15 (E). Tiles stay `x + 256 y`:
15 chunk rows are at most 255 tile rows, under 256.

**Chunks for the same area:** 251 tiles against 225, **10.4 % fewer chunks and reveals** in the
interior of a location (H). At the edge of a location, a rectangular outline cut into hexagons
wastes more partial chunks than rectangles do (not counted).

## 5. What it changes

| Item | Change | Size |
|---|---|---|
| **ADR-0006** | §1 (chunk 15 × 15 → hexagon 251; `(x/15, y/15)` → lattice); §3 outlines, joining chunks (six neighbours, sides 9/11), corners; §4 window (built from up to 6 chunks, per-row pieces, not one shift); "Measured" table | Large: the ADR's decision on size and its cost section |
| **D-120** | The 15 × 16 window stays. Its argument "shares the chunk's width, which makes assembly a one-dimensional shift" no longer holds | Medium: reasoning, not the board |
| **ENG-01 §3.2** | `Chunk.Terrain`: bits 0–250, `LIVE` = corner bit 250; edges to `Features` 240–245 (or derived). Entity ids `8 + 16 × chunk + k` unchanged. Tile → chunk by lattice | Small: layout text, packers, their tests |
| **ENG-01 §3.5** | `OUTLINE` tile mask bits 0–250, bit 250 set by the writer; `SET_PIECE` terrain likewise; the chunk-set bitmap on lattice coordinates | Small |
| **ENG-01 §9–§10** | The window reads up to 12 slots instead of 8 | Small in text, a cost at every tick with goblins awake |
| **Library N-3** (done for rectangles) | A second assembly, per-row pieces from up to 6 chunks, with its oracle and budgets. Or a replacement | Large: N-3 was a one-shift design; measured 64,234 |
| **Library N-4** (done) | Cutting by a mask is `grid & mask` on any layout: unchanged in logic. Its tests and the ring semantics (D-23) move to the hexagon's ring | Small |
| **Library N-1, N-2** (not started) | A board model for a 251-tile hexagon: neighbour planes, the component, margins, six sides. There is no constant-stride layout in one felt, so it needs a new board type (two felts, or per-row) | Large, and it is the timing D-165 names: before they start |
| **Library N-5, N-6, N-7, N-8** | Unchanged: they run on the window | None |
| **ENG-05** (not started) | Six neighbours, sides 9/11, copied sides by gather, lattice coordinates, quotas' "chunks left" unchanged | Medium: written for the new shape from the start |
| **ENG-07** (not started) | Up to 6 chunks a tick; tile → chunk by lattice for moves without the window | Small to medium |
| **TOOL-01** (todo) | Drawing outlines and authored chunks on a hexagon lattice: a hexagonal brush, lattice coordinates | Medium: it is not started |
| **CLI-02, client chunk loading** | The TypeScript mirror of generation and assembly follows the Cairo. Rendering a chunk is a row table instead of a square. Loading by lattice coordinates | Medium |
| **docs/needs/hexmap.md** | N-1, N-2, N-3 restated. Point 1 (13 × 13 interior, seam inside the chunk) becomes a 199-tile interior. Point 2 (parity flag) stays | Small in text |
| **design/18** | Interior sizes and the zones' character (larger chunks) | Small |

## 6. Recommendation

Side by side. Nothing here was measured by this lot:

| | Rectangle 15 × 15 | Hexagon 9-9-11 |
|---|---|---|
| Tiles a felt | 225 (26 bits: edges, `LIVE`) | 251 (`LIVE` is a wall corner) |
| Chunks for the same area | 1 | 0.896 (H) |
| **Per tick** (goblins awake): chunks read | 4 × 2 slots (M, ENG-01) | **6 × 2** (H) |
| Per tick: assembly in memory | **64,234** (M, N-3) | **0.25–0.6 M** (E), 32–48 pieces |
| **Per reveal:** generation a chunk | **0.39–0.45 M** (M, SPK-7) | **0.6–1.0 M** (E) |
| Per reveal: slots | 2 new a chunk | 2 new a chunk |
| Chunks a move can reveal | ≤ 3 | ≤ 3 (H) |
| Tile → chunk | 2 divisions | lattice rounding and 1–3 tests (E: 10k–20k) |
| Library | N-3, N-4 done, N-1/N-2 on a stride-15 board | N-3 again; N-1/N-2 need a board type beyond one felt |
| Work to switch | — | §5: three large items (ADR-0006, N-3, N-1/N-2) and six medium ones |

**Keep the 15 × 15 rectangle.** At the tick, the hexagon's one gain (26 bits, about 10 % fewer
chunks) is paid for with 4 more slot reads and an assembly estimated 4 to 9 times dearer. At every
reveal, it is paid for with a generation estimated 1.5 to 2 times dearer. It would also make the
library carry a board type it does not have, before N-1 and N-2. The free `LIVE` bit is real, but
the rectangle already spends its 26 spare bits on the edges and `LIVE` at no cost.

**What would reverse it:**
1. A measured per-row assembly from hexagonal chunks within about **2× N-3's 64,234**, the extra 4
   reads included in a tick measured on the node. The estimate says 4–9×. A cheap trick not seen
   here (for example grouping rows by origin class within the class size) would change that.
2. A measured hexagon generation within **SPK-7's 0.39–0.45 M**.
3. A reason beyond cost that this study does not weigh: the look of hexagonal chunks, or
   exploration that feels rounder. That is the owner's to weigh.
4. D-165's premise was a widest row of 27. The real 19 does not change the conclusion. The
   hexagon's bounding box (19 wide) is wider than the window (15), which is why a window row
   crosses up to 3 chunks.

**Measured against estimated:** only the rectangle's figures are measured (SPK-7, N-3, ENG-01),
none of them re-measured here. Every hexagon cost is an estimate (E), and every hexagon count is
derived by hand (H), to be asserted by `geometry.py`.

## 7. What the next run must build (AC-2, AC-3)

With a profile that allows `scarb`, `snforge`, `python3` and `git`:

1. `python3 spikes/SPK-14/geometry.py`. It asserts every H figure above: bijection, corners,
   tiling, the six neighbours, the 6-chunk window at (6, 2), linear layouts at 307. It prints the
   maximum chunks and pieces over the 502 origin classes, and the sight bound. Correct §1–§4 where
   it disagrees.
2. `spikes/SPK-14/src/`, as SPK-7:
   - `hexchunk.cairo`: the index tables, `bit` and `tile`, `chunk_of`;
   - `window.cairo`: assembly of the 15 × 16 window from up to 6 hexagonal chunks by row pieces,
     and the rectangle's assembly on the same basis. Either SPK-7's `assemble_window` copied into
     the package, or the library's N-3 at `93639f2c17e3`, the git dependency already in
     `Scarb.toml`;
   - `chunk.cairo`: generation of a hexagonal chunk with margins by the cheapest way of §4.
3. Tests:
   - the bijection;
   - the assembly against a tile-by-tile oracle on every origin class (AC-3): a hexagon-tiled
     region assembled into the window equals a direct construction;
   - generation's invariants: wall corners, copied sides equal, every walkable tile reachable.
4. Benchmarks measured **twice** (D-154), one call against two as SPK-7 did:
   - the assembly, worst origin class, hexagon and rectangle on the same inputs;
   - generation, 6 sides drawn and 6 copied, per biome, beside SPK-7's rectangle on the same
     package.

   Budgets `ceil(1.05 × measured)`; `BUDGETS.md` and `GAS.md` by `scripts/gas_budgets.py`.
5. Then replace every E of §6 by its M and re-read the recommendation against the reversal
   thresholds.
