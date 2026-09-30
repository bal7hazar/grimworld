# SPK-14 — Hexagonal chunks of 251 tiles, measured

Measured on 2026-09-30 on the VPS by `[Opus 5.5]` under D-165, on the repository's toolchain
(Scarb 2.19.4, snforge 0.61.0), with the map library `hexx` read by git at commit `93639f2c17e3`.
Code, raw outputs and commands: `spikes/SPK-14/` (its `README.md`).

Every figure carries one of four labels:

| Label | Meaning |
|---|---|
| **M** | Measured by this spike: snforge L2 gas, in memory, each benchmark a test that calls twice less one that calls once (N-3's method). Two runs, each from a clean build (D-154), gave **identical** figures (`snforge-test-output-{1,2}.txt`) |
| **G** | Computed exactly and asserted by `geometry.py` or `generation.py` (output: `geometry-output.txt`) |
| **C** | Cited from an earlier measurement, named where it appears |
| **E** | An estimate or a sum of measurements, said so where it appears |

A first lot of this task had no build permissions and wrote an analytical draft. Every figure of
that draft that a measurement now covers is replaced below. The draft's estimates were low: the
window came out at 876,310, where the draft estimated 0.25–0.6 M.

## Summary

| Question | Answer |
|---|---|
| 1. Shape and indexing | 17 rows of **11 to 19** tiles (G). **The widest row is 19, not D-165's 27**: the hexagon widens by half a tile on each side per row. Bits go row by row from the South through two 17-entry tables; bits 0 and 250 are corners. The chunks tile the plane on the lattice `(−9, 17)`, `(19, −8)` (determinant 251). The bijection onto 0–250 is tested (M, `test_index_is_a_bijection`) |
| 2. Storage words | **0 new slots, `LIVE` kept.** Bit 250 is a corner tile, and corners are always wall (D-134), so in ENG-01's `Terrain` (1 = wall) bit 250 is always 1: it is `LIVE`. The 6 edge bits go to `Features` 240–245, or are derived from the ring. `OUTLINE` and `SET_PIECE` set bit 250, a corner no rule reads |
| 3. Window | **Up to 6 chunks** (G; 3, 4, 5, 6 chunks for 50, 173, 26 and 2 of the 251 origin classes), against 2 or 4. **The one-shift assembly does not survive**: a window row takes 1 to 3 runs, up to **32 pieces** a layer (G) against 4. Measured: **876,310** in memory (M) against N-3's **64,234** (M, re-measured here, equal to the library's), **13.6 times**. Grouped pieces precomputed per class (fix loop 1): 193,584 to **268,428** (M, 3.0× to 4.2×, the latter on the class with the most pieces); none reaches 2× (E, §3.2). The classes were chosen by count; these are maxima among the classes measured. Tested against a direct construction on all 251 classes (M) |
| 4. Reveal and generation | A 251-tile chunk generated with margins costs **0.97–1.15 M** (M) against the rectangle's **0.40–0.44 M** (M, SPK-7's generator on the same basis): **2.2 to 2.8 times**. No constant-stride layout holds the hexagon in a felt (307 bits at least, G), so it is generated on two half-boards and packed. Sight touches **up to 4 chunks**, so a move reveals up to 3 (G), as today. Corners stay wall, for a new reason |
| 5. What it changes | ADR-0006, D-120's reasoning, ENG-01 §3.2/§3.5, the library's N-3 (rewritten), N-1/N-2 (a board type the library does not have), ENG-05, ENG-07, TOOL-01, CLI-02 and the client (§5) |
| 6. Recommendation | **Keep the 15 × 15 rectangle.** Both reversal thresholds fail, now on measurements: the assembly at 13.6× N-3 for the walk, 4.2× for grouped precomputed pieces on the class with the most of them (E: no class under 2× with any real fixed part), against about 2×; generation at 2.2–2.8×, against SPK-7's range. The hexagon's gains are 26 bits a felt, about 10 % fewer chunks, and `LIVE` for free |

## 1. The shape and its indexing (G, M)

Coordinates are the library's (docs/needs/hexmap.md point 3): odd-r offset `(x, y)`, axial
`q = x − ⌊y/2⌋`, `r = y`, `+y` North. On pointy-top tiles (D-11) the long sides of 11 are rows: the
South row (row 0) and the North row (row 16). A chunk anchored at axial (0, 0) is
`0 ≤ r ≤ 16, 0 ≤ q ≤ 18, 8 ≤ q + r ≤ 26`:

| Row r | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | **8** | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Width | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | **19** | 18 | 17 | 16 | 15 | 14 | 13 | 12 | 11 |
| First bit | 0 | 11 | 23 | 36 | 50 | 65 | 81 | 98 | 116 | 135 | 153 | 170 | 186 | 201 | 215 | 228 | 240 |
| q from | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

**D-165's "27 tiles at the widest (11 + 2 × 8)" is wrong: the widest row is 19 (11 + 8).** Its
bounding box is **19 × 17** in offset coordinates (G), wider than the window's 15.

- **Indexing.** `bit = FIRST[r] + q − QLO[r]`; the inverse is a 251-entry table
  (`HexChunkTrait::index`, `tile`). `test_index_is_a_bijection` (M) walks every tile of the
  definition and finds bits 0, 1, …, 250 in order, each inverted by `tile`.
- **Corners** (6): bits **0, 10, 116, 134, 240, 250** (G, `test_corners_and_live_bit`).
- **Sides**, corners included: 11, 9, 9, 11, 9, 9; the ring holds 52 tiles, the interior 199
  (13 × 13 = 169 today) (G).
- **Orientation.** The long sides are rows, the shape is symmetric on screen about its vertical
  axis. Vertical long sides would need flat-top tiles (D-165).

**The tiling.** Translates by `a T_U + b T_R`, `T_U = (−9, 17)`, `T_R = (19, −8)`, cover the plane
once, and a chunk's neighbours are `±T_U`, `±T_R`, `±(T_U + T_R)` (G, `check_tiling`). Chunks
start on both row parities (`T_U` moves 17 rows): the parity flag stays for anything that works
in offset coordinates.

**Which chunk holds a tile.** 251 is prime: the lattice is not a product of two strides, and
`(x / 15, y / 15)` has no counterpart. `locate` rounds the lattice coordinates from the inverse
matrix, then makes at most one translation (G: every tile of 256 × 256). It is tested against a
brute-force search (M, `test_locate_matches_plain`). **Cost: `HexWindowTrait::origin` 56,910
against the library's `AssemblyTrait::origin` 3,730 (M), 15 times.**

## 2. The storage words (ENG-01 §3.2, §3.5)

A layer takes bits 0–250, the whole felt.

| Option | Slots | What ENG-01 loses |
|---|---:|---|
| **(a) Bit 250 is a corner, always wall: it is `LIVE`** | **0** | Nothing in `Terrain`, where 1 = wall and D-134 keeps every corner wall: a stored `Terrain` always has bit 250 set. The packer's check becomes "the six corner bits are set". **The one to take if the hexagon is taken** |
| (b) A `LIVE`-less word class | 0 | A second rule next to §3.1's; (a) is its proof for `Terrain` |
| (c) A second felt | +1 a chunk, 453,524 at its first reveal (C: ENG-01 §10's N) | Not needed |
| (d) `LIVE` in `Features` | 0 | `Features` has it already; it does not keep `Terrain` from being 0 |

- **The 6 edge bits** (a dungeon side open or border; today `Terrain` 225–228) go to `Features`
  240–245. That word is written at the reveal with `Terrain`, so no extra write. Or they are not
  stored at all: a side is open when a non-corner tile of its ring is walkable (openings are
  drawn and frozen with the side, D-22).
- **`OUTLINE`** (§3.5), a border chunk's tile mask: bits 0–250, and the writer sets bit 250 as
  `LIVE`. A corner is wall whatever the outline says, so no rule reads that bit. 0 slots.
- **`SET_PIECE`**: its terrain has wall corners, so `LIVE` holds as in `Terrain`. The pack and
  object tile fields (8 bits) hold 0–250 unchanged.

**Lost:** the uniform rule "bit 250 is `LIVE`, 0–249 data" gains an exception for chunk-shaped
layers.

## 3. The window (D-120: 15 × 16, origin on an even row)

### 3.1 Geometry (G)

The origin's position in its chunk decides everything. An even origin row fixes the chunk's
parity, so there are **251 classes** (G).

| Chunks overlapped | 3 | 4 | 5 | 6 |
|---|---:|---:|---:|---:|
| Origin classes (of 251) | 50 | 173 | 26 | 2 |

Rectangles: 2 or 4. The window reads chunks in 8 relative positions: `(0, −1)`, `(0, 0)`,
`(0, 1)`, `(1, 0)`, `(1, 1)`, `(1, 2)`, `(2, 1)`, `(2, 2)` (G). In ENG-01's layout (a window
reads `Terrain` and `Features` of each chunk), that is **up to 12 slot reads instead of 8**.

**Why one shift per chunk cannot work.** A chunk's rows are 11 to 19 bits, packed end to end. A
row moves into the window by its own shift. From one chunk row to the next, the shift changes by
`3, 3, 1, 1, −1, −1, −3, −3, −4, −2, −2, 0, 0, 2, 2, 4` (G): only rows 11–13 share one. A window
row takes 1, 2 or 3 runs (400, 3,424 and 192 of the 4,016 rows of all classes, G), **32 pieces at
most** a layer, against 4.

### 3.2 Measured (M)

Every assembly returns what N-3's `window` returns: two layers, the ring of the terrain as wall, a
`HexMap`. The rectangle is the library's own code on the case the library benchmarks as its worst
(4 chunks, `ox = oy = 7`), re-measured in this package. **The hexagon's classes were chosen by
count, not by gas** (fix loop 1, audit finding 2): the class with the most row runs (bit 25), a
class with the most chunks (bit 185), the class with the most grouped pieces (bit 65). Branches and
shifts differ between classes, so these are **the maxima among the classes measured**, not a
proven maximum over all 251.

| Assembly, both layers | L2 gas | Against N-3 | Test |
|---|---:|---:|---|
| **Rectangle, N-3** (`AssemblyTrait::window`) | **64,234** | 1 | `bench_rect_window_*` |
| **Hexagon, the walk**, the class with the most pieces (origin bit 25: 32 runs, 4 chunks) | **876,310** | **13.6** | `bench_hex_window_*` |
| Hexagon, the walk, a class with 6 chunks (bit 185: 28 runs) | 799,152 | 12.4 | `bench_hex_window_six_*` |
| Hexagon, every row run precomputed for the class, bit 25 (32 runs) | 318,044 | 5.0 | `bench_table_window_*` |
| Hexagon, every row run precomputed, bit 185 (28 runs) | 289,880 | 4.5 | `bench_table_window_six_*` |
| Hexagon, **grouped** pieces precomputed, bit 25 (17 pieces) | 193,584 | 3.0 | `bench_grouped_window_*` |
| Hexagon, grouped, bit 185 (20 pieces, 6 chunks) | 223,362 | 3.5 | `bench_grouped_window_six_*` |
| Hexagon, grouped, **bit 65, the most grouped pieces of all classes** (26) | **268,428** | **4.2** | `bench_grouped_window_most_*` |

- **The walk** (`HexWindowTrait::window`) follows the window's left column up through the chunks,
  row by row: a bounded loop of 16 rows and at most 3 runs each. Per run:
  - one lookup of the row's table;
  - one mask from a limb table (one limb, except row 8, which straddles bit 128);
  - one AND per layer;
  - one field product by a power of two or its inverse.

  A first version, with 10 lookups a run, measured 1,024,170. The one above has about 6.
- **The row-run table variant** (`HexWindowTableTrait::window` on `PIECES_<class>`) precomputes
  each run's slot, mask and shift: one lookup a run. It is **not a floor** (fix loop 1, audit
  finding 1: the first version of this note said it was). Its table was generated only for the
  benchmark classes. All 251 classes hold **7,824 runs**, 39,120 felts of constants (G). The
  monolithic table attempted does not compile ("Type size computation failed … size overflow",
  Scarb 2.19.4), and it would be 48 % of the 81,920-felt CASM limit (ENG-01 §1.3) as data. That
  says nothing about other table designs.
- **Grouped pieces** (fix loop 1, the audit's grouping): runs of one chunk that move by the same
  shift are joined into one piece, one mask. The same function runs on `GROUPED_<class>`,
  generated by `gen_tables.py` and checked against the direct construction on the three classes
  generated. Over all 251 classes (G, `gen_tables.py`):

  | Grouped pieces | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 |
  |---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
  | Classes | 2 | 30 | 22 | 22 | 12 | 56 | 48 | 10 | 23 | 13 | 4 | 2 |

  That is 5,010 pieces over all classes; a table of them was not tried.
- **Unit costs** (M, `test_micro`, per iteration):

  | Operation | L2 gas |
  |---|---:|
  | A table lookup | 1,005–1,370 |
  | A loop iteration | 1,895 |

  32 runs at about 6 lookups and 2 ANDs each account for the walk's figure.
- **The lower bound the grouping supports** (E, fix loop 1). The three grouped measurements lie
  on a line: 8,316 a piece (bit 25 to bit 65: 74,844 for 9 more pieces), plus a fixed part of
  about 52,212 (the chunks' limbs, the ring, the `HexMap`). Bit 185, predicted 218,532, measured
  223,362, with two more chunks to convert.

  | Case (E unless marked) | L2 gas | Against N-3 |
  |---|---:|---:|
  | The class with the fewest grouped pieces (15) | about 177,000 | 2.8 |
  | Its per-piece work alone, no fixed part at all (15 × 8,316) | 124,740 | 1.94 |
  | The class with the most grouped pieces (26), measured (M) | 268,428 | 4.2 |
  | Its per-piece work alone (26 × 8,316) | 216,216 | 3.4 |

  **No grouped variant meets the reversal threshold (about 2× N-3, 128,468).** The window is
  assembled for whatever class the adventurer's position gives, so the threshold must hold for
  the class with the most pieces: 4.2× measured there. Even its per-piece work alone, with no
  fixed part, is 3.4×.

  Only the best class's per-piece work, with a fixed part of zero, would come under 2× (1.94×).
  N-3's own 64,234 includes such a fixed part, so that case is not a real assembly.

  The grouping is the audit's, not a proven minimum. A design with fewer pieces than distinct
  (chunk, shift) pairs would need something other than one mask and one product a piece, and none
  was found.
- **Correctness** (M): `test_window_matches_plain_*` builds the window tile by tile from the
  definition of the hexagon, for all 251 origin classes with random chunks in all 12 slots, both
  layers, and compares it with the walk. On the classes whose tables are generated it compares
  the row-run and the grouped table variants too. It also checks that `origin` puts an
  adventurer on an odd or an even row into the
  right class. `test_window_void_chunks_are_wall` covers void chunks (D-134, D-136: `None`, no
  read).

**Parity of the origin.** Unchanged: the window's origin stays on an even global row, and the
flood takes the window as today.

## 4. Reveal and generation

### 4.1 How the hexagon is generated

SPK-7's generator relies on a stride-15 board in one felt: the automaton's six neighbour planes
are six field products, and the component flood is the library's `dilate`.
- **No layout with a constant row stride holds the hexagon in one felt: the smallest spans 307
  bits, stride 19** (G, `check_linear_layouts`).
- So `HexChunkGenTrait::generate` works on **two half-boards** in axial coordinates, stride 19:
  S holds rows 0–9 and N rows 7–16. A neighbour there is a constant shift: `±1`, `±19`, `+18`,
  `−18`. No parity flag is needed.
- S is right on rows 0–8 and N on rows 8–16. After each step, one piece each way copies S's rows
  7–8 into N and N's row 9 into S (`sync`).
- The chunk is packed into its 251 bits at the end, one piece a row.

The steps are SPK-7's:
1. A base at the biome's density: three random words per half, so one Poseidon permutation more
   than the rectangle.
2. Sides copied, closed or drawn (1 or 2 openings, D-22), corners wall.
3. Lines from each opening to a spine, each of one constant length. The spine is three axes
   through the centre (row 8, q = 9, q + r = 17), so that every side reaches it straight.
4. Two passes of the automaton with the ring as margins, SPK-7's rule.
5. The component of the centre.

**The six sides and their copies** (G, `generation.py` `check_sides`):
- Our row 0 copies the neighbour `−T_U`'s row 16, tile `(q, 0)` from its `(q − 8, 16)`. The two
  sides are adjacent tile for tile, corners on corners. The other five pairs are bijections the
  same way.
- **The long sides** (row 0, row 16) are one piece of the neighbour's felt.
- **The four short sides** (7 non-corner tiles each) are one tile per row in both chunks, at no
  common shift, so they are **gathered tile by tile**. A copied side therefore costs more than a
  drawn one: the opposite of the rectangle.

### 4.2 Measured (M)

Rectangle: SPK-7's `generate_chunk`, unchanged but for its library (`hexx` instead of
`origami_hexmap` 1.8.0), on the same words and neighbours as the hexagon.

| Generation, one chunk | Meadow | Forest | Cave | Ruin |
|---|---:|---:|---:|---:|
| **Rectangle**, 4 sides drawn | 435,136 | 420,268 | 436,014 | **444,774** |
| Rectangle, 4 sides copied | 410,440 | 395,572 | 430,004 | 420,078 |
| **Hexagon**, 6 sides drawn | 991,591 | 968,175 | 1,033,617 | 967,175 |
| Hexagon, 6 sides copied | **1,146,507** | 1,122,301 | 1,141,153 | 1,121,301 |
| Hexagon ÷ rectangle, drawn | 2.28 | 2.30 | 2.37 | 2.17 |
| Hexagon ÷ rectangle, copied | 2.79 | 2.84 | 2.65 | 2.67 |

- **Coverage** (fix loop 1, audit finding 2): one word (`'SECOND'`) per biome, with all sides
  drawn and all sides copied. The flood's length depends on the generated connectivity, so other
  words and side mixes cost other amounts. The figures are **the maxima among the fixtures
  measured**, not a proven maximum.
- **The rectangle re-measures inside SPK-7's 0.39–0.45 M** (C: SPK-7 §2.1, 390,352–447,462, on
  another library and by baseline differences). The most among the fixtures measured: 444,774
  (ruin, drawn).
- **The hexagon's most among the fixtures measured is 1,146,507** (meadow, copied): **2.58
  times** the rectangle's. Fixture by fixture, the ratio is 2.17 to 2.84.
- **Where the extra goes:**
  - two half-boards, so the automaton's two passes and the flood's layers are done twice, with a
    sync after each;
  - the four short sides gathered;
  - the 17 packing pieces;
  - a third Poseidon permutation.
- **Correctness** (M):
  - `test_smooth_matches_plain`: one pass on the halves, synced and packed, equals a tile-by-tile
    pass on the dense chunk, for all four biomes;
  - `test_component_matches_plain`: the component equals a plain breadth-first search;
  - `test_generate_open_border_and_copy`, per biome: corners wall; 1 or 2 openings on each drawn
    side; closed sides closed; six copied sides equal to six generated neighbours' facing sides;
    every walkable tile reachable from the centre; determinism.
- **Not tuned** (M, `test_generate_shares`, walkable share of the interior over 16 words):

  | Biome | Hexagon | Rectangle | design/18 |
  |---|---:|---:|---|
  | Meadow | 93.8 % | 83.3 % | 80–90 % |
  | Forest | 82.4 % | 67.2 % | 60–70 % |
  | Cave | 65.3 % | 47.9 % | 45–55 % |
  | Ruin | 64.8 % | 46.7 % | 40–50 % |

  The hexagon runs SPK-7's biome parameters unchanged, and its three-axis spine covers more of the
  interior, so its shares sit above design/18's ranges. Retuning would change the component's
  number of layers, not the two-board structure behind the factor above.

### 4.3 Sides, corners, sight, the revealed set

- **D-134 restated.**
  - *Void margin:* unchanged.
  - *Corners:* the 6 corner tiles stay wall. The old reason (no diagonal neighbour) has no object:
    three chunks meet at each vertex and all share edges. The new reason: a corner lies on two
    sides facing two neighbours, and a wall corner keeps each side depending on one neighbour. It
    also gives `LIVE`.
  - *D-136:* unchanged, with up to 6 chunks to test.
- **How many chunks one move can reveal: up to 3, as today.** A sight of radius 6 touches at
  most 4 chunks (G, `check_sight`, every tile of a chunk), the adventurer's among them.
- **The revealed set stays one felt, but not as `15 b + a`** (fix loop 2, review 1: the first
  version proposed `15 b + a`, which does not cover ENG-01's largest location). ENG-01 §3.2
  allows 225 × 225 tiles.
  - **Chunk count** (G, `check_revealed`): over the 251 placements of the lattice under such a
    location, it touches **226 to 241 chunks**, always fewer than 250.
  - **The placement proposed:** the location's tile (0, 0) is bit 0 of chunk (0, 0). The location
    then touches **227 chunks**, with `b` from 0 to 15. Each row `b` is one contiguous run of
    `a`, 14 or 15 chunks from `a_min[b]` (0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7).
  - **The index:** `bit = FIRST_B[b] + a − A_MIN[b]`, two 16-entry tables (`FIRST_B`: 0, 14, 28,
    43, 57, 72, 86, 101, 115, 129, 143, 157, 171, 185, 199, 213). The chunks of any smaller
    location with the same origin are a subset.
  - **Bits:** 0–226 hold chunks, 227–249 are free, and 250 stays `LIVE`.
  - **Cost: 0 new slots.** The rectangle's `15 cy + cx` becomes two table lookups, about 2,000 to
    2,700 L2 gas at the measured unit costs (E).
  - **What moves with it:** a chunk's index is below 227, so the `chunks[(slot, c)]` key and
    `OUTLINE`'s `location × 256 + chunk` still fit. Goblin entity ids `8 + 16 × chunk + k` reach
    3,633 instead of 3,601, still a `u16`.
- **Chunks for the same area:** 251 tiles against 225, **10.4 % fewer chunks and reveals** in a
  location's interior (G). A rectangular outline cut into hexagons wastes more partial chunks at
  its border (not counted).

### 4.4 A reveal as a transaction (E)

SPK-7's worst reveal, 3 chunks in a cave with no neighbour known, was **5,919,680** on the local
node (C).

Its storage is SPK-7's layout: one new `Terrain` slot a chunk, and the revealed bitmap. Fix loop 2
(review 3) keeps each estimate on one basis:

| Estimate (E) | Rectangle | Hexagon |
|---|---:|---:|
| **On SPK-7's layout** (1 new slot a chunk): SPK-7's transaction, the hexagon adding its extra generation, 3 × (1,033,617 − 436,014) = 1,792,809 (the drawn cave, in memory) | 5,919,680 (C) | about **7.71 M** |
| **On ENG-01's layout** (2 new slots a chunk, `Terrain` and `Features`): the row above plus one more new slot per chunk, 3 × 453,524 = 1,360,572 (ENG-01 §10's N, C), for both shapes | about **7.28 M** | about **9.07 M** |

On either basis, the difference between the shapes is the generation's, about 1.79 M for this
reveal. Storage is the same for both shapes on a given layout.

## 5. What it changes

| Item | Change | Size |
|---|---|---|
| **ADR-0006** | §1 (chunk 15 × 15 → hexagon 251; `(x/15, y/15)` → lattice rounding); §3 (six neighbours, sides of 9 and 11, the copy maps, corners' new reason); §4 (up to 6 chunks, per-row pieces); "Measured" | Large |
| **D-120** | The 15 × 16 window stays. Its argument ("shares the chunk's width, which makes assembly a one-dimensional shift") no longer holds | Medium |
| **ENG-01 §3.2** | `Terrain` bits 0–250, `LIVE` = corner 250; edges to `Features` 240–245 or derived; tile → chunk by `locate`; `revealed` indexed by two 16-entry tables (§4.3), one felt, 0 slots; entity ids up to 3,633 | Small (layout text, packers, tests) |
| **ENG-01 §3.5** | `OUTLINE` masks 0–250, bit 250 set by the writer; `SET_PIECE` likewise; the chunk set (and `revealed`, §3.2) indexed `FIRST_B[b] + a − A_MIN[b]` on lattice coordinates (§4.3), 227 chunks for 225 × 225 tiles | Small |
| **ENG-01 §9–§10** | Up to 12 slot reads a tick instead of 8; the tick's one-layer assembly 766,712 instead of 39,434 in memory | Small in text, a cost at every tick with goblins awake |
| **Library N-3** (done, 64,234) | A second assembly: a walk of row runs over up to 6 chunks (this spike's `window.cairo`, 876,310), its oracle and budgets | Large |
| **Library N-4** (done) | `grid & mask` works on any layout; its tests and the ring semantics (D-23) move to the hexagon's ring | Small |
| **Library N-1, N-2** (not started) | A board type the library does not have: two half-boards with a sync, or boards beyond one felt, plus a packer; six sides with gathers | Large, and before they start (D-165's timing) |
| **Library N-5 to N-8** | Unchanged: they run on the window | None |
| **ENG-05** (not started) | Six neighbours, the copy maps, lattice coordinates; biome parameters retuned (§4.2) | Medium |
| **ENG-07** (not started) | Up to 6 chunks a tick, `locate` (56,910) for moves without the window | Small to medium |
| **TOOL-01** (todo) | Outlines and authored chunks on a hexagonal lattice | Medium |
| **CLI-02, the client** | The mirror follows the Cairo; chunks rendered from a row table; loading by lattice coordinates | Medium |
| **docs/needs/hexmap.md** | N-1, N-2, N-3 restated. Point 1's 13 × 13 interior becomes 199 tiles. Point 2's parity flag stays for offset work; the half-boards do not need it | Small in text |

## 6. Recommendation

| | Rectangle 15 × 15 | Hexagon 9-9-11 |
|---|---|---|
| Tiles a felt | 225 (26 bits: edges, `LIVE`) | 251 (`LIVE` is a wall corner) |
| Chunks for the same area | 1 | 0.896 (G) |
| Assembly against N-3, both layers, in memory | **64,234** (M) | **876,310** (M), 13.6× for the walk; 268,428 (M), 4.2×, grouped pieces precomputed, class with the most pieces |
| **Per tick: the one layer ENG-01's tick assembles** (terrain), in memory | **39,434** (M) | **766,712** (M), 19.4×, the walk, class with the most runs |
| Per tick: chunks overlapped, slot reads | 2 or 4; 8 (ENG-01) | 3 to 6 (G); 12 |
| Tile → chunk (`origin`) | 3,730 (M) | 56,910 (M) |
| **Per reveal: generation a chunk** | **0.40–0.44 M** (M) | **0.97–1.15 M** (M), 2.2–2.8× |
| Per reveal: slots | 2 new a chunk | 2 new a chunk |
| Chunks a move can reveal | ≤ 3 | ≤ 3 (G) |
| Library | N-3, N-4 done; N-1/N-2 on a stride-15 board | N-3 again; N-1/N-2 on a board type it does not have |
| Work to switch | — | §5: three large items, five medium |

**Keep the 15 × 15 rectangle.** Every tick with goblins awake pays for the hexagon's gain (26
bits, about 10 % fewer chunks).

*The tick* (fix loop 2, review 2: the first version applied the two-layer difference, 812,076, to
the tick). ENG-01's tick assembles one layer, the terrain: occupancy is not stored but derived
from the actors (§3.2), and that derivation does not depend on the chunk's shape.

| On one layer | L2 gas |
|---|---:|
| Rectangle, the library's `AssemblyTrait::assemble` (M) | 39,434 |
| Hexagon, the same walk on one layer, `HexWindowTrait::assemble`, on the class with the most runs (M) | 766,712 |
| Hexagon, on the 6-chunk class (M) | 695,533 |
| **The difference, the hexagon's cost per tick in memory** (M, a difference of two measurements) | **+727,278** |

- The ring and the `HexMap` the tick then builds are the same for both shapes, and cancel. The
  grouped variant was measured on two layers only.
- The hexagon also reads 4 more slots.
- At SPK-7's prices (C) the difference is about **$0.00066 a tick** (E, a conversion).
- Against D-166's proved worst tick of 15.1 M on ENG-01's layout (C), it is about **+4.8 %**
  (E, a ratio).

*The reveal:* every reveal pays **0.52–0.74 M more per chunk** (M, differences of
measurements). The library would need a board type it does not have
before N-1 and N-2. The free `LIVE` bit is real; the rectangle already spends its 26 spare bits
on the edges and `LIVE` at no cost.

**What would reverse it** (the thresholds of the first draft, kept):

| # | Threshold | Now |
|---|---|---|
| 1 | A hexagonal assembly within about **2× N-3's 64,234** | **Not met**: 13.6× measured for the walk. Grouped precomputed pieces: 4.2× measured on the class with the most pieces; the grouping's bound (E, §3.2) stays above 2× for every class once any fixed part is counted |
| 2 | A hexagonal generation within **SPK-7's 0.39–0.45 M** | **Not met**: 0.97–1.15 M measured |
| 3 | A reason beyond cost: the look of hexagonal chunks, rounder exploration | The owner's to weigh; this study does not |
| 4 | D-165's premise of 27 tiles at the widest | The real 19 changes nothing above, but it is why a window row crosses up to 3 chunks: the hexagon is wider than the window |

A different design could reverse 1 or 2, and none was found here. For example, a window that is
itself a lattice-aligned hexagon would take whole chunks. But the window follows the adventurer
(D-120), so its origin is almost never a lattice point, and that is not this study's board.

**Measured against estimated:**
- Measured here (M): the window's assembly (the walk, row runs precomputed, grouped pieces precomputed) and `origin`; both generators; the
  unit costs; the tests of the bijection, the window and generation.
- Measured here (M, fix loop 2): the one-layer assembly of both shapes, the tick's basis.
- Computed (G, fix loop 2): the revealed set's layout for a 225 × 225 location.
- Cited (C): SPK-7's figures and prices, ENG-01's slot prices, D-166's proved worst tick.
- Estimated (E):
  - the reveal as a transaction, on SPK-7's layout and on ENG-01's (§4.4);
  - the tick's money and its share of D-166's worst tick;
  - the cost of the revealed index's lookups.
