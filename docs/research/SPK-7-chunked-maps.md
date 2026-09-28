# SPK-7 — The chunked map, measured

Measured on 2026-09-28 on the VPS by `[Opus 5.5]`, on the repository's toolchain (Scarb 2.19.4,
snforge 0.61.0, sncast 0.61.0, starknet-devnet 0.10.0), with `origami_hexmap` 1.8.0 by published
version. Code, raw outputs and commands: `spikes/SPK-7/` (its `README.md`).

Every figure below was measured, with three exceptions, each marked where it appears:
- the one sum of two measurements (§2.2);
- the fallback's analysis (§4), which is analytical;
- the conditional part of the R-12 verdict (§3).

Fix loop 1 (after the `[GPT-6-Astra]` audit, §8) changed the flood's stopping rule and re-ran
everything. Every figure here is from that run.

## Summary

| Question | Answer |
|---|---|
| **Window assembly (N-3)** | **65,224 L2 gas** in memory, measured as one call against two identical calls. The same figure for 2 chunks and for 4 on this meter (§2.1). No loop: one mask (a product of two small tables) and one shift per chunk and layer. It equals a tile-by-tile oracle on all 225 offsets, 2 and 4 chunks, both row parities of the adventurer; an odd origin is refused. The ADR estimated about 40k |
| **The window in the tick, as transactions** | Assembling it from 4 chunks at each tick (A, D-120) costs **2,960,960 L2 gas** for the worst-case tick, against **2,240,960** on SPK-2's stand-in (one slot, no chunk). The chunked map's net overhead is **720,000 L2 gas and 256 L1 data gas per tick with goblins awake**: $0.000650 at SPK-2's prices, **+14.0 %** on SPK-2's worst tick |
| **Stored window** | **B**, kept in sync with the chunks at each tick (as briefed): **+440,000** waiting and **+320,000** moving, against A. **B′**, the working copy, its occupancy written back to the chunks only when it moves: **−640,000** on a tick where the adventurer does not move; **+440,000** on a move that changes the chunk row, beside A on the same destination; **+1,808,000** on a move within the same chunks that writes 4 chunks back from zero. B′'s maximum among the cases measured is **4,848,960** |
| **Reveal** | One chunk **2,455,200 L2 gas**, three chunks in one action **5,919,680** (cave, the most expensive biome), with 320 and 448 L1 data gas: **$0.0022 and $0.0052**. Generation in memory: 390k to 447k per chunk |
| **Shared flood (N-8)** | 26,452 L2 gas per layer on the window, 59,380 fixed. The capped worst case (15 layers, 8 goblins reached, 7 distinct distances) costs 634,655; with its 8 steps, 1,150,737. With no target the flood computes no layer, on both sides (shared vectors, §2.1) |
| **How deep a winding board can be** | A hill climb finds 88 steps from local (7, 7) and 91 from (7, 8) (SPK-2 found 93); the bound is 181. Unlimited, the flood on such a board costs 2,407,277 (83 layers); the cap of 15 layers (D-127) holds it to 456,160 |
| **Line of sight (N-5)** | 9,716 L2 gas: one table lookup, one exact shift, one AND. Symmetric, and equal to a plain version on all 14,708 ordered pairs of interior tiles within 6 |
| **R-12** | **Partly realised, not a blocker, on two conditions (§3):** that the fallback is not needed, which rests on an analysis, not a measurement (§4); and that D-133's batches carry the cost per transaction. Reveals are cheap for how rarely they happen. The window adds 14 % to ticks with goblins awake, and nothing to the others if it is assembled only then |
| **Fallback (sight 5, 13 × 14)** | **Out of scope by the orchestrator's amendment** (fix loop 1): not built and not measured. The analysis of §4 is analytical |

## 1. What was built, and how far it is from ADR-0006

`spikes/SPK-7/` is a native Starknet package: pure functions named after the needs they prototype,
and one contract, `Instances`, that stores chunks and runs the measured actions.

| ADR-0006 / needs | The spike | Distance |
|---|---|---|
| Chunk 15 × 15, one felt per layer (§1) | `ChunkLayers { terrain, occupied }`, two slots under one key `instance · 2^16 + cy · 2^8 + cx` | As written. The features layer is not built (placement is ENG-05's) |
| Window 15 × 16 following the adventurer, origin on an even global row, adventurer on local (7, 7) or (7, 8) (§4, D-120) | `window_origin`, `assemble_window`. No loop: per chunk and layer, one mask `COLS × ROWS` from two tables of 15 entries and one field product by `2^±(15 dy + dx)`; the pieces are added; the ring is imposed as wall on the terrain | As written. The occupied layer keeps its ring (goblins there are frozen, and the flood never enters the ring) |
| Generation at reveal from a random word and the neighbours' edges (§2, design/18) | `generate_chunk(word, biome, sides, odd)`: a base at the biome's density from 3 random bitmaps; each side **copied** from a generated neighbour, **closed** on the location's border, or **drawn** (1 or 2 openings, then frozen, D-22); lines from each opening to a spine (row 7 and column 7); 2 passes of an automaton that counts the ring as neighbours (the margins, point 1); the component of the centre kept | Order of design/18 kept (base, smoothing with margins, edges and openings). Lines and spine are the spike's way to guarantee "every chunk reachable". **Corners are always wall** (§7). No outline cut, quotas, anchors or placement (ENG-05, out of scope) |
| The parity flag for chunks on odd rows (point 2) | Two constants: `CHUNK_EVEN[odd]` for the automaton, and the same mask as the `even` of the library's `Dilation` for the flood | As written: the library's `DilationTrait::dilate` takes the flag unchanged when the caller builds the `Dilation` |
| One flood shared by 8 goblins, rule (a), capped at 15 layers (point 5, D-127) | `shared_flood` and `step` on the library's `dilate`. The flood stops as soon as no goblin is left to reach, checked before each layer. Steps are filtered by the tiles goblins moved into this tick (the layers never hold a tile occupied at the start) | As written; tested against a scalar BFS and against the Python model with shared vectors |
| Goblins crossing chunks (R-5) | `move_goblin`: the bit of the chunk left and of the chunk entered; dirty slots written once | As written |
| Line of sight: integer line, ties to the lower tile index, symmetric, walls block, ends not tested (point 6, D-24) | `between_mask` from two tables (source on an even or an odd row) anchored at (7, 8) and (7, 7), shifted to the source; `line_of_sight` is one AND | Pairs up to 6 apart only (the ranged range, and sight); beyond, it refuses |
| Random word: `fate(domain)` | `poseidon(transaction hash, instance, chunk key)` | A stand-in, as the brief says (option C of ADR-0006 replaces it) |
| Stored window, for comparison (brief item 6) | B: `{ origin, terrain, occupied }` in 3 slots, re-centred (assembled) when its origin changes and written back; the chunks' occupancy kept in sync each tick. B′: the same window as the working copy, the chunks brought up to date only when it moves (`scatter_window`) | B′ is an addition: B alone would have answered "stored is always worse" |
| SPK-2's tick | S: SPK-2's stand-in. The window's terrain sits in one slot, the occupancy comes from the goblins' tiles, and no chunk is read or written | Added so that A − S is the chunked map's net overhead |

Not built:
- combat, conditions and the goblins' other fields (SPK-2's);
- the reveal engine's bands, quotas and anchors (ENG-05);
- movement rules, facing and the queue (ENG-07);
- the fallback (§4).

Storage: the goblins as 8 × 16 bits in one felt, the adventurer in one felt, the revealed set as a
225-bit felt per instance.

## 2. Measurements

### 2.1 Every function, in memory (snforge)

```
cd spikes/SPK-7 && snforge test > snforge-test-output.txt
Collected 106 test(s) from spk7 package
Tests: 106 passed, 0 failed, 0 ignored, 0 filtered out
```

Most benchmarks have a baseline that builds the same inputs; the cost is the difference of the
two tests' L2 gas (snforge's figure, Sierra gas plus syscalls). The assembly is measured as one call
against two identical calls instead: its baseline difference moved from 35,370 to 66,034 between
two runs with `assemble_window` unchanged (fix loop 1, finding 4).

| Function | L2 gas | Tests |
|---|---:|---|
| `assemble_window`, 4 chunks | **65,224** | `bench_assemble_4_chunks_twice` − `_once` |
| `assemble_window`, 2 chunks | **65,224** | `bench_assemble_2_chunks_twice` − `_once` |
| `shared_flood`, deep board, cap 10 | 323,900 | `bench_flood_deep_10` − baseline |
| `shared_flood`, deep board, cap 15 | 456,160 | `bench_flood_deep_15` − baseline |
| `shared_flood`, deep board, cap 20 | 588,420 | `bench_flood_deep_20` − baseline |
| `shared_flood`, deep board, unlimited (83 layers) | 2,407,277 | `bench_flood_deep_unlimited` − baseline |
| `shared_flood`, capped worst case (15 layers, 8 goblins, 7 distances) | **634,655** | `bench_flood_capped` − baseline |
| `shared_flood`, the same board, one unreachable target / one goblin | 463,200 / 469,773 | `bench_flood_capped_{unreachable,one}_goblin` − baseline |
| World tick: flood and 8 steps, window given | **1,150,737** | `bench_tick_goblins` − baseline |
| Assembly, world tick and the chunks' occupancy | **1,456,429** | `bench_tick_full` − baseline |
| `move_goblin` across chunks | 5,726 | `bench_move_goblin_across` − baseline |
| `line_of_sight`, 6 apart | **9,716** | `bench_line_of_sight` − baseline |
| `generate_chunk`, 4 sides copied: meadow, forest, cave, ruin | 402,560, 390,752, 399,028, 390,352 | `bench_generate_*_copy` − baseline |
| `generate_chunk`, 4 sides drawn: meadow, forest, cave, ruin | **447,462**, 429,334, 437,610, 432,094 | `bench_generate_*_open` − baseline |

**Assembly, 2 and 4 chunks.** The 2-chunk path does half the pieces, yet costs the same 65,224 on
this meter; why is not isolated. It is reported as measured.

**The flood.**
- Its per-layer cost is the slope between caps 10 and 20: (588,420 − 323,900) / 10 = **26,452**.
- Its fixed part is 323,900 − 10 × 26,452 = 59,380.
- A layer that touches one goblin costs 6,573 more; a layer that touches several scans the 8 goblins.

**Unit costs** behind these figures (`test_micro`, 100 iterations each, less the loop):
- a loop iteration: 1,520;
- a table lookup (`Bits::pow`): 1,265;
- a bit test through the bitwise builtin (`Bits::get`): 4,170.

A loop over goblins that tests a bit for each costs about 5,700 per goblin: it is what the flood's
single-goblin fast path avoids.

**The flood with no target, and shared vectors (fix loop 1, finding 1).** Before fix loop 1 the
Python model stopped when no target was left, while Cairo checked that only after a hit. With no
target, Python computed one layer and Cairo ran to the cap or to the end of the frontier.

Both now follow one rule: **the flood stops before a layer when no target is left to reach**, so with
none it computes no layer beyond the start. Why:
- the flood only serves the goblins' steps (design/02: "gives every goblin its next step");
- D-127's 15 layers are a ceiling on that work, not a quota of layers to compute;
- the tick already skips the flood when no goblin is awake.

A benchmark of pure layers now gives one target that can never be reached (tile 0, a ring corner
next to no interior tile). `vectors.py` runs 12 vectors (empty, unreachable and real targets;
capped and unlimited; both adventurer rows) through the Python model, checks the layer counts
written in it, and writes the same inputs and results to `src/vectors.cairo`.
`test_flood::test_flood_shared_vectors` checks each vector in Cairo: layer count, distances, and the
union of the layers.

```
$ python3 spikes/SPK-7/vectors.py
CAPPED_TERRAIN     start 112 targets none            limit  15:   1 layers, distances []
CAPPED_TERRAIN     start 112 targets none            limit 255:   1 layers, distances []
DEEP_EVEN_TERRAIN  start 127 targets none            limit  15:   1 layers, distances []
DEEP_EVEN_TERRAIN  start 127 targets none            limit 255:   1 layers, distances []
CAPPED_TERRAIN     start 112 targets unreachable     limit  15:  16 layers, distances [0]
CAPPED_TERRAIN     start 112 targets unreachable     limit 255:  22 layers, distances [0]
DEEP_EVEN_TERRAIN  start 127 targets unreachable     limit  15:  16 layers, distances [0]
DEEP_EVEN_TERRAIN  start 127 targets unreachable     limit 255:  93 layers, distances [0]
CAPPED_TERRAIN     start 112 targets CAPPED_GOBLINS  limit  15:  16 layers, distances [13, 3, 15, 4, 3, 2, 5, 7]
CAPPED_TERRAIN     start 112 targets CAPPED_GOBLINS  limit 255:  16 layers, distances [13, 3, 15, 4, 3, 2, 5, 7]
DEEP_TERRAIN       start 112 targets DEEP_GOBLINS    limit  15:  16 layers, distances [0, 0, 0, 0, 0, 0, 0, 0]
DEEP_TERRAIN       start 112 targets DEEP_GOBLINS    limit 255:  83 layers, distances [0, 0, 0, 0, 82, 0, 0, 0]
wrote .../src/vectors.cairo: 12 vectors, every layer count as expected
```

**Correctness** (same run):
- the assembly equals its oracle on every offset `dx` 0 to 14, `dy` 0 to 14, both parities (`test_assemble_matches_oracle_*`);
- the automaton and the component equal scalar versions on both chunk parities (`test_smooth_*`, `test_keep_component_*`);
- generated chunks have wall corners, 1 or 2 openings per drawn side, closed borders, copied edges equal to the neighbour's, every walkable tile reachable, and are deterministic (`test_generate_open_border_and_copy`);
- the flood and every step equal a scalar BFS on the boards of `boards.py` and on random boards of both parities, capped and unlimited (`test_flood_*`);
- line of sight holds on 14,708 pairs (`test_line_of_sight_rows_*`).

Walkable share of the interior over 32 words per biome (design/18 ranges in brackets):

```
shares (thousandths): meadow 832 forest 665 cave 478 ruin 461
```

That is meadow 83.2 % [80–90], forest 66.5 % [60–70], cave 47.8 % [45–55], ruin 46.1 % [40–50].

### 2.2 The measured actions as transactions (local node)

```
scripts/with-node.sh python3 spikes/SPK-7/devnet.py > spikes/SPK-7/devnet-output-{1,2,3}.txt
python3 spikes/SPK-7/summarize.py spikes/SPK-7/devnet-output-*.txt > spikes/SPK-7/devnet-summary.md
```

Three runs of 55 invoke transactions each (27 measured, the rest setup); every one `SUCCEEDED`.
After each run:
- the nine instances of the worst-case tick hold the same goblins (`"check": "goblins after the nine ticks are equal", "ok": true`);
- the two instances of the chunk-row move hold the same goblins as each other (`"check": "goblins after the two chunk-row ticks are equal", "ok": true`).

The ticks are identical across runs. Reveals vary with the random word, which comes from the
transaction hash (ranges below).

The node meters in VM resources, as SPK-2 found (§8.2 there), and its receipts move in steps of
40,000. The receipt is what adds up. Transactions go through devnet's predeployed account (seed 0).

**The worst-case tick**: 4 chunks overlapped, two layers each, 8 awake goblins, a winding board
(unlimited depth 20), the flood at its cap of 15 layers, 8 goblins reached at distances 2 to 15,
all stepping, 5 steps crossing a chunk boundary; then the writes.

| Variant | Adventurer waits: L2 gas | L1 data gas | Adventurer moves: L2 gas | L1 data gas |
|---|---:|---:|---:|---:|
| **A**, assembled from the chunks at each tick (D-120) | **2,960,960** | 512 | **3,040,960** | 576 |
| **B**, stored window, chunks kept in sync (re-centred and written back on a move) | 3,400,960 | 576 | 3,360,960 | 768 |
| **B′**, stored window as the working copy (occupancy deferred) | 2,320,960 | 320 | 2,880,960 (nothing pending) to **4,848,960** (4 chunks written back) | 512 to 768 |
| **S**, SPK-2's stand-in (one slot, occupancy from the goblins, no chunk) | 2,240,960 | 256 | 2,320,960 | 320 |

**A move that changes the window's chunks** (fix loop 1, finding 3). The world is the same board
placed at origin (37, 60). The adventurer starts on (44, 66), an even row, so its window's origin
is (37, 58), over chunks (2, 3), (2, 4), (3, 3) and (3, 4). It steps North-West onto (44, 67): the
origin becomes (37, 60) and the chunk row changes, to (2, 4), (2, 5), (3, 4), (3, 5).

For B′, each of the 4 old chunks holds a move the window knows and the chunk does not (a ghost bit
where a goblin left). Chunks (2, 4) and (3, 4) also miss the goblins that entered them. Writing
the window back therefore changes all 4 chunks, before the new set is read from storage.

| Variant, same destination | L2 gas | L1 data gas |
|---|---:|---:|
| A | 2,880,960 | 448 |
| B′, 4 chunks written back, new chunks read | 3,320,960 | 768 |

| Difference | L2 gas |
|---|---:|
| **A − S: the chunked map's net overhead in the tick** | **720,000** (waiting and moving) |
| B − A | +440,000 waiting, +320,000 moving |
| B′ − A | −640,000 waiting; +1,808,000 moving within the same chunks, 4 chunks written back; +440,000 moving into another chunk row, 4 chunks written back |

**B′'s maximum.** The chunk-row move (3,320,960) costs less than the same-chunks move with 4
chunks written back (4,848,960), which stays **the maximum among the cases measured**. The two
cases write different values:
- in the same-chunks case, the 4 occupied layers go from 0 to the goblins' tiles;
- in the chunk-row case, each goes from a ghost bit to its new value.

The gap between the two is not isolated. A move that changes the chunk row and writes 4 layers
from zero was not measured.

**In snforge**, the calls alone (test minus its setup baseline), waiting / moving:

| Variant | L2 gas |
|---|---|
| A | 1,741,181 / 1,806,567 |
| B | 1,976,107 / 1,982,767 |
| B′ | 1,544,647 / 2,043,325 (nothing pending) / 3,857,105 (4 pending) |
| S | 1,522,797 / 1,588,183 |
| Chunk-row move | A 2,105,547, B′ 1,529,245 |

The node and snforge disagree on the sign of B′ − A for the chunk-row move; the receipt is the
figure that counts.

**Reveals**, each from a fresh instance, in a location of 7 × 7 chunks:

| Reveal | Meadow | Forest | Cave | Ruin | L1 data gas |
|---|---:|---:|---:|---:|---:|
| 1 chunk, no neighbour known | 2,415,200–2,455,200 | 2,415,200–2,455,200 | 2,415,200–2,455,200 | 2,415,200–2,455,200 | 320 |
| 1 chunk, its 4 neighbours known | 2,133,200 | 2,133,200–2,173,200 | 2,173,200 | 2,173,200 | 320 |
| **3 chunks** (an L), none known around | 5,639,680–5,679,680 | 5,319,680–5,559,680 | **5,639,680–5,919,680** | 5,559,680 | 448 |
| 3 chunks, the 7 around known | 5,317,680 | 5,077,680–5,237,680 | 5,557,680–5,797,680 | 5,317,680–5,477,680 | 448 |

The worst reveal is **3 chunks with no neighbour known, 5,919,680 L2 gas, in a cave**.
- **Drawing a side costs more than copying one.** A copy is one storage read, an AND and a
  product; a drawn side is three divisions, two remainders and two table lookups.
- **Three chunks form an L.** Sight of radius 6 spans 13 tiles, less than a chunk, so it touches
  at most a 2 × 2 block of chunks.
- **The parity flag is on the measured path.** Chunk C of the L is on an odd chunk row.

**In money**, at SPK-2's prices (L2 gas 21,687,750,610 fri, L1 data gas 1,544,531,203,854 fri,
STRK $0.04061; `spikes/SPK-2/prices-fixloop2-output.txt`):

| Item | Cost |
|---|---:|
| The chunked map's net overhead in a tick | $0.000650 |
| The tick A, adventurer waiting | $0.00264 |
| A reveal of 1 chunk | $0.00218 |
| A reveal of 3 chunks | $0.00524 |

**Sum of two measurements (an estimate):** SPK-2's worst tick under D-127, 5,156,800 L2 gas, plus
A − S, 720,000, gives about **5,877,000 L2 gas** for the game's worst tick on chunked maps. The two
were measured on the same node version with different accounts and fixtures; the increment itself
is measured on one node, with one account.

### 2.3 How many layers a winding 15 × 16 board can need

`boards.py` climbs from a spiral of one-tile corridors. It toggles one interior tile at a time and
keeps the change when the adventurer's eccentricity does not fall (300,000 steps each):

```
deepest board found, adventurer on local (7, 7): 88 steps; on (7, 8): 91 steps
  walkable interior tiles of the (7, 7) board: 102 of 182
  flood with limit 10: 11 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit 15: 16 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit 20: 21 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit None: 83 layers (start included), distances [0, 0, 0, 0, 82, 0, 0, 0]
```

SPK-2's hill climb reached an eccentricity of 93 (`spikes/SPK-2/src/fixtures.cairo`,
`DEEP_TERRAIN`). The bound is the interior less one tile, 181.

**A winding window can need about 90 layers.** The goblins, as obstacles under rule (a), cut it
shorter: here the nearest of the 8 goblins, at the end of the corridor, closes it at 82.

At 26,452 per layer, the cap of 15 layers keeps the flood under 0.46M, where an unlimited one
reaches 2.41M.

## 3. Verdict on R-12

R-12: *chunked maps exceed the cost budget (window assembly, chunk generation on reveal, flood)*.

| Part | Measured | Verdict |
|---|---|---|
| The window in the tick: assembly and chunk traffic | On the node, A − S = 720,000: the chunked map's **net** overhead (8 slot reads instead of 1, up to 4 occupied layers written, and the work in memory together). **It is not split into computation and storage** (fix loop 1, finding 4). In memory, assembly plus the chunks' occupancy updates cost 305,692 (`bench_tick_full` − `bench_tick_goblins`). In snforge, A − S is 218,384, less than that, because S does work A does not (occupancy from the goblins' tiles) | **The cost of the chunked map:** +14.0 % on the worst tick |
| Flood | 26,452 a layer; the cap (D-127) holds it to 15 layers whatever the board | As SPK-2 found; the chunked map changes nothing |
| Reveal | 2.46M for 1 chunk, 5.92M for 3 (cave) | A few reveals per location: six reveals of 3 chunks cost $0.031, 6 % of the $0.50 target (D-129) |

**R-12 is partly realised and is not a blocker, on two conditions:**

1. **The fallback is not needed.** That rests on the analysis of §4, which is analytical: its
   "same per-layer cost" and "about 14 times the assembly" are extrapolations, not measurements.
   The orchestrator took the fallback out of scope.
2. **D-133's batches carry the cost per transaction.** The threshold of ADR-0001 was out of reach
   with one action per transaction because of the fixed part of a transaction (SPK-1, D-129
   point 4).

Under both, the chunked map adds about 14 % to the ticks that have goblins awake, and nothing to
the others if the implementation assembles the window only when a goblin is awake (§6). If either
condition fails, R-12 must be judged again with measured figures.

What to keep:
- **D-120 (A) stays the default.**
- **B, the stored window as briefed, is worse in every case measured.**
- **B′ is the one measured way to cheapen fights**, and the choice is ENG-07's (§6).

## 4. The fallback (brief item 7): out of scope, analysis only

**Scope amendment by the orchestrator (fix loop 1):** the fallback is not measured. D-133 now
takes the cost through batches, and the analysis below says that a 13 × 14 window still overlaps
4 chunks. Nothing was built or measured for it.

**The analysis below is analytical, not measured:**
- **The chunks.** A window of 13 × 14 still overlaps 4 chunks whenever it crosses a column and a
  row boundary (offsets `dx >= 3`, `dy >= 2`). In that worst case, the reads and writes behind
  A − S do not change. This is geometry.
- **The flood (an extrapolation).** 182 bits is still the two-limb path, and the cap of 15 layers
  binds on a winding board of either size. The per-layer cost is expected to be about the same
  26,452; it was not measured on a 13 × 14 board.
- **The assembly (an extrapolation).** A window 13 wide takes 13 of a chunk's 15 columns per row,
  so a row of the chunk no longer lands on a row of the window by one shift of the whole felt. It
  becomes one mask and one shift per row and per chunk (14 rows × up to 2 chunks, each an AND and
  a product), about 14 times today's work by count of operations; or a loop over rows, which
  docs/CAIRO.md rules out. Not written, not measured.
- **Open boards.** It saves flood layers only on open boards, where the flood is cheap anyway.

## 5. What the map library should provide (L-M1), and the gas to beat

Figures are snforge L2 gas in memory, on this spike's worst cases. The library's release candidate
should be measured on the same inputs (`spikes/SPK-7/tests/test_bench.cairo`) and beat them.

| Need | Function here | To beat | Notes for LIB-03 |
|---|---|---:|---|
| N-3 assembly | `assemble_window` | 65,224 (2 or 4 chunks, one-vs-two calls) | Keep the masks as limb pairs (`u128`) in the tables: each `felt → u256` split of a mask costs range checks. The inverse (`scatter_window`) is needed only if the game stores the window (B′) |
| N-8 flood | `shared_flood` | 26,452 a layer, 634,655 the capped worst case | Stop when no target is left, checked before each layer (§2.1, shared vectors). The hit test per layer (2 applications) and the goblin lookup per hit are the extra over a plain flood; a single-goblin fast path (one AND, felt comparisons) is here |
| N-8 selection | `step` (rule (a)) | 1,150,737 for the flood and 8 steps | Filter by the tiles goblins moved into this tick, not by the whole occupancy: 0 until the first move, then sparse |
| N-1, N-2 generation with margins | `generate_chunk` | 447,462 (4 sides drawn), 402,560 (4 copied) | The automaton with margins must build its diagonal planes by OR, not by sum: row-wrapped edge bits collide and carry into the interior (found here by the oracle, `chunk.cairo`) |
| Parity flag | `CHUNK_EVEN[1]`, and `Dilation { even: CHUNK_EVEN[1], .. }` | — | `Layout::new` cannot express it; `Dilation`'s public fields can. The library should take the flag in its layout constructor |
| N-5 line of sight | `between_mask`, `line_of_sight` | 9,716 | Tables of 169 felts per row parity, valid for interior tiles up to 6 apart; a general line (beyond 6) is not measured here |
| Cutting by a mask (N-4) | — | — | Not needed by anything measured here |

**The library's:**
- the assembly and its inverse;
- the automaton with margins and parity;
- the component flood with parity;
- the shared flood with its selection;
- line of sight.

**The game's (ENG-05, ENG-07):**
- the layers' storage;
- `move_goblin` (which chunk a goblin's bit lives in);
- the reveal's sides (which neighbour is generated, the location's border);
- the random word.

## 6. Open questions

**For ENG-05 (reveal engine)**
1. Corners wall (§7), lines to a spine for connectivity, and the component kept are the spike's
   choices. The component is a flood of up to 169 layers on the chunk; it removes the pockets no
   opening reaches. Its share of a generation was not measured apart.
2. A drawn side costs more than a copied one, so the worst reveal is the one with no neighbour
   known, not the one with the most reads.
3. The revealed set as one felt holds 15 × 15 chunks (bit `15 cy + cx`): enough for 7 × 7
   locations; a larger zone needs two felts.

**For ENG-07 (the tick and the batches of D-133)**
4. **Assemble only when a goblin is awake.** Awake goblins can be found from their tiles; a move
   without goblins needs only the terrain bit of the tile entered (one chunk read). Then A − S is
   paid only by ticks with goblins.
5. **In a batch, read the chunks once per transaction** and write their occupancy once at the end.
   How much of A − S a batch saves is not measured: A − S is not split into storage and
   computation (§3).
6. **B′ for fights.** A stored window that is the working copy saves 640,000 on every tick the
   adventurer does not move. It costs +440,000 (chunk-row move) to +1,808,000 (same chunks, 4
   layers from zero) on the move that writes it back. Whether fights are long enough to pay for it
   depends on DES-21's batches.
7. Which ≤ 8 goblins are awake when more stand in the window (design/02: the nearest, ties by id)
   needs the goblins by chunk; the spike stores the 8 of the fixture only.

**For LIB-03**
8. The targets of §5, and the unit costs of §2.1: 4,170 per bit test, 1,265 per table lookup,
   1,520 per loop iteration.
9. The 2-chunk assembly costs what the 4-chunk one does on snforge's meter (§2.1): worth checking
   on the library's build.

## 7. Escalations

| Question | Why it stops here | Read |
|---|---|---|
| **The window at the border of a location.** An adventurer less than 7 columns or 8 rows from the location's edge gives a window origin below 0. The spike keeps its fixtures away from the border | ADR-0006 §4 does not say whether the window is clamped (then the adventurer is off-centre, and sight can reach the ring) or whether locations keep a margin of void chunks (then coordinates start at 15) | ADR-0006 §4, D-120, docs/needs/hexmap.md N-3 |
| **Corners of a chunk are wall.** They are the only tiles adjacent to a diagonal chunk; the spike never opens them, so diagonal chunks never touch directly | ADR-0006 § Joining chunks speaks of edges shared by two chunks, not of corners | ADR-0006 §2, docs/needs/hexmap.md points 1 and D-22 |

## 8. Fix loop 1 (`[GPT-6-Astra]` audit of #50: FAIL, two majors, two minors)

The audit confirmed A − S as a sound controlled comparison, every budget, the oracles and the
receipts.

| Finding | Fix |
|---|---|
| 1 (major) Python/Cairo parity of the flood with no target | One rule on both sides: stop before a layer when no target is left (§2.1). `model.py` and `flood.cairo` changed. Benchmarks of pure layers use an unreachable target. 12 shared vectors in `vectors.py` and `test_flood_shared_vectors`. The extra test per layer moved the flood by about 3 % in memory (per layer 25,612 → 26,452). On the node, S moved by one 40,000 step while A did not: **A − S is now 720,000 (was 760,000)**, and the figures here are the new run's |
| 2 (major) the fallback | Out of scope by the orchestrator's amendment (§4). Its cost conclusions are labelled analytical, and the R-12 verdict is conditional on them (§3) |
| 3 (minor) B′'s costliest case | Measured a move that changes the chunk row, (37, 58) to (37, 60), with 4 chunks to write back, beside A on the same destination (§2.2): 3,320,960 against 2,880,960. It is below 4,848,960, which stays the maximum among the cases measured, qualified as such |
| 4 (minor) "the rest is storage" | Removed. A − S is the net overhead, not split (§3). The assembly is now measured as one-vs-two calls, because its baseline difference was not stable |
