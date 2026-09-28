# SPK-7 — The chunked map, measured

Measured on 2026-09-28 on the VPS by `[Opus 5.5]`, on the repository's toolchain (Scarb 2.19.4,
snforge 0.61.0, sncast 0.61.0, starknet-devnet 0.10.0), with `origami_hexmap` 1.8.0 by published
version. Code, raw outputs and commands: `spikes/SPK-7/` (its `README.md`). Every figure below was
measured; the one sum of two measurements is marked as such.

## Summary

| Question | Answer |
|---|---|
| **Window assembly (N-3)** | **65,734 L2 gas** for 4 chunks and 35,370 for 2, in memory: no loop, one mask (a product of two small tables) and one shift per chunk and layer. It equals a tile-by-tile oracle on all 225 offsets, 2 and 4 chunks, both row parities of the adventurer; an odd origin is refused. The ADR's estimate was about 40k |
| **The window in the tick, as transactions** | Assembling it from 4 chunks at each tick (A, D-120) costs **2,960,960 L2 gas** for the worst-case tick against **2,200,960** on SPK-2's stand-in (one slot, no chunk): the chunked map adds **760,000 L2 gas and 256 L1 data gas per tick with goblins awake** ($0.000685 at SPK-2's prices), **+14.7 %** on SPK-2's worst tick |
| **Stored window** | Kept in sync with the chunks at each tick (B, as briefed): **+440,000** waiting and **+280,000** moving, against A. As the working copy, occupancy written back to the chunks only when it moves (B′): **−680,000** on a tick where the adventurer does not move, **+1,768,000** on a move that writes 4 chunks back |
| **Reveal** | One chunk **2,455,200 L2 gas**, three chunks in one action **5,839,680** (cave, the most expensive biome), 320 and 448 L1 data gas: **$0.0022 and $0.0052**. Generation in memory: 390k to 447k per chunk |
| **Shared flood (N-8)** | 25,612 L2 gas per layer on the window, 59,940 fixed; the capped worst case (15 layers, 8 goblins reached, 7 distinct distances) 618,475; with its 8 steps, 1,134,557 |
| **How deep a winding board can be** | A hill climb finds 88 steps from local (7, 7) and 91 from (7, 8) (SPK-2 found 93); the bound is 181. Unlimited, the flood on such a board costs 2,338,807 (83 layers): the cap of 15 layers (D-127) costs 444,120 |
| **Line of sight (N-5)** | 9,716 L2 gas: one table lookup, one exact shift, one AND. Symmetric and equal to a plain version on all 14,708 ordered pairs of interior tiles within 6 |
| **R-12** | **Partly realised, not a blocker.** Reveals are cheap for how rarely they happen. The window's storage traffic (8 reads, up to 4 writes) is the cost, not its computation: +15 % on the worst tick. It is paid only when goblins are awake, and a queue can pay it once per transaction |
| **Fallback (sight 5, 13 × 14)** | **Not built**: it would not lower the worst case (still 4 chunks, still 15 layers on the two-limb path) and its assembly would lose the one-dimensional shift (§4) |

## 1. What was built, and how far it is from ADR-0006

`spikes/SPK-7/` is a native Starknet package: pure functions named after the needs they prototype,
and one contract, `Instances`, that stores chunks and runs the measured actions.

| ADR-0006 / needs | The spike | Distance |
|---|---|---|
| Chunk 15 × 15, one felt per layer (§1) | `ChunkLayers { terrain, occupied }`, two slots under one key `instance · 2^16 + cy · 2^8 + cx` | As written. The features layer is not built (placement is ENG-05's) |
| Window 15 × 16 following the adventurer, origin on an even global row, adventurer on local (7, 7) or (7, 8) (§4, D-120) | `window_origin`, `assemble_window`: no loop; per chunk and layer one mask `COLS × ROWS` from two tables of 15 entries, one field product by `2^±(15 dy + dx)`; pieces added; the ring imposed as wall on the terrain | As written. The occupied layer keeps its ring (goblins there are frozen, and the flood never enters the ring) |
| Generation at reveal from a random word and the neighbours' edges (§2, design/18) | `generate_chunk(word, biome, sides, odd)`: base at the biome's density from 3 random bitmaps; each side **copied** from a generated neighbour, **closed** on the location's border, or **drawn** (1 or 2 openings, then frozen, D-22); lines from each opening to a spine (row 7 and column 7); 2 passes of an automaton that counts the ring as neighbours (the margins, point 1); the component of the centre kept | Order of design/18 kept (base, smoothing with margins, edges and openings); lines and spine are the spike's way to guarantee "every chunk reachable". **Corners are always wall** (§7). No outline cut, quotas, anchors or placement (ENG-05, out of scope) |
| The parity flag for chunks on odd rows (point 2) | Two constants: `CHUNK_EVEN[odd]` for the automaton, and the same mask as the `even` of the library's `Dilation` for the flood | As written: the library's `DilationTrait::dilate` takes the flag unchanged when the caller builds the `Dilation` |
| One flood shared by 8 goblins, rule (a), capped at 15 layers (point 5, D-127) | `shared_flood`, `step` on the library's `dilate`; steps filtered by the tiles goblins moved into this tick (the layers never hold a tile occupied at the start) | As written; tested against a scalar BFS |
| Goblins crossing chunks (R-5) | `move_goblin`: the bit of the chunk left and of the chunk entered, dirty slots written once | As written |
| Line of sight: integer line, ties to the lower tile index, symmetric, walls block, ends not tested (point 6, D-24) | `between_mask` from two tables (source on an even or odd row) anchored at (7, 8) and (7, 7), shifted to the source; `line_of_sight` = one AND | Pairs up to 6 apart only (ranged range and sight); beyond, it refuses |
| Random word: `fate(domain)` | `poseidon(transaction hash, instance, chunk key)` | A stand-in, as the brief says (option C of ADR-0006 replaces it) |
| Stored window, for comparison (brief item 6) | B: `{ origin, terrain, occupied }` in 3 slots, re-centred (assembled) when its origin changes and written back; chunks' occupancy kept in sync each tick. B′: the same window as the working copy, chunks brought up to date only when it moves (`scatter_window`) | B′ is an addition: B alone would have answered "stored is always worse" |
| SPK-2's tick | S: SPK-2's stand-in, the window's terrain in one slot, occupancy from the goblins' tiles, no chunk read or write | Added so that A − S is the chunked map's own cost |

Not built: combat, conditions and the goblins' other fields (SPK-2's), the reveal engine's bands,
quotas and anchors (ENG-05), movement rules, facing and the queue (ENG-07), the fallback (§4).
Storage: goblins as 8 × 16 bits in one felt, the adventurer in one felt, the revealed set as a
225-bit felt per instance.

## 2. Measurements

### 2.1 Every function, in memory (snforge)

```
cd spikes/SPK-7 && snforge test > snforge-test-output.txt
Collected 96 test(s) from spk7 package
Tests: 96 passed, 0 failed, 0 ignored, 0 filtered out
```

Each benchmark has a baseline building the same inputs; the cost is the difference of the two
tests' L2 gas (snforge's figure, Sierra gas plus syscalls).

| Function | L2 gas | Tests |
|---|---:|---|
| `assemble_window`, 4 chunks | **65,734** | `bench_assemble_4_chunks` − baseline |
| `assemble_window`, 2 chunks | **35,370** | `bench_assemble_2_chunks` − baseline |
| `shared_flood`, deep board, cap 10 | 316,060 | `bench_flood_deep_10` − baseline |
| `shared_flood`, deep board, cap 15 | 444,120 | `bench_flood_deep_15` − baseline |
| `shared_flood`, deep board, cap 20 | 572,180 | `bench_flood_deep_20` − baseline |
| `shared_flood`, deep board, unlimited (83 layers) | 2,338,807 | `bench_flood_deep_unlimited` − baseline |
| `shared_flood`, capped worst case (15 layers, 8 goblins, 7 distances) | **618,475** | `bench_flood_capped` − baseline |
| `shared_flood`, the same board, no goblin / one goblin | 448,020 / 452,393 | `bench_flood_capped_{no,one}_goblin` − baseline |
| World tick: flood and 8 steps, window given | **1,134,557** | `bench_tick_goblins` − baseline |
| Assembly, world tick and the chunks' occupancy | **1,440,249** | `bench_tick_full` − baseline |
| `move_goblin` across chunks | 5,726 | `bench_move_goblin_across` − baseline |
| `line_of_sight`, 6 apart | **9,716** | `bench_line_of_sight` − baseline |
| `generate_chunk`, 4 sides copied: meadow, forest, cave, ruin | 402,560, 390,752, 399,028, 390,352 | `bench_generate_*_copy` − baseline |
| `generate_chunk`, 4 sides drawn: meadow, forest, cave, ruin | **447,462**, 429,334, 437,610, 432,094 | `bench_generate_*_open` − baseline |

The flood's per-layer cost is the slope between caps 10 and 20: (572,180 − 316,060) / 10 =
**25,612**; its fixed part 316,060 − 10 × 25,612 = 59,940. A layer that touches goblins costs
about 4,400 more when it touches one, and a scan of the 8 goblins when it touches several.

Unit costs behind these (`test_micro`, 100 iterations each, less the loop): a loop iteration 1,520,
a table lookup (`Bits::pow`) 1,265, a bit test through the bitwise builtin (`Bits::get`) 4,170. A
loop over goblins that tests a bit each costs about 5,700 per goblin: it is what the flood's
single-goblin fast path avoids.

Correctness (same run): the assembly equals its oracle on every offset `dx` 0 to 14, `dy` 0 to 14,
both parities (`test_assemble_matches_oracle_*`); the automaton and the component equal scalar
versions on both chunk parities (`test_smooth_*`, `test_keep_component_*`); generated chunks have
wall corners, 1 or 2 openings per drawn side, closed borders, copied edges equal to the
neighbour's, every walkable tile reachable, and are deterministic (`test_generate_open_border_and_copy`);
the flood and every step equal a scalar BFS on the boards of `boards.py`, on random boards of both
parities, capped and unlimited (`test_flood_*`); line of sight on 14,708 pairs (`test_line_of_sight_rows_*`).

Walkable share of the interior over 32 words per biome (design/18 ranges in brackets):

```
shares (thousandths): meadow 832 forest 665 cave 478 ruin 461
```

meadow 83.2 % [80–90], forest 66.5 % [60–70], cave 47.8 % [45–55], ruin 46.1 % [40–50].

### 2.2 The measured actions as transactions (local node)

```
scripts/with-node.sh python3 spikes/SPK-7/devnet.py > spikes/SPK-7/devnet-output-{1,2,3}.txt
python3 spikes/SPK-7/summarize.py spikes/SPK-7/devnet-output-*.txt > spikes/SPK-7/devnet-summary.md
```

Three runs of 51 invoke transactions each (25 measured, the rest setup), every one `SUCCEEDED`; after each run the nine instances of the
tick hold the same goblins (`"check": "goblins after the nine ticks are equal", "ok": true`). The
ticks are identical across runs; reveals vary with the random word, which comes from the
transaction hash (ranges below). The node meters in VM resources, as SPK-2 found (§8.2 there); the
receipt is what adds up. Through devnet's predeployed account (seed 0).

**The worst-case tick**: 4 chunks overlapped, two layers each, 8 awake goblins, a winding board
(unlimited depth 20), the flood at its cap of 15 layers, 8 goblins reached at distances 2 to 15,
all stepping, 5 steps crossing a chunk boundary; then the writes.

| Variant | Adventurer waits: L2 gas | L1 data gas | Adventurer moves: L2 gas | L1 data gas |
|---|---:|---:|---:|---:|
| **A**, assembled from the chunks at each tick (D-120) | **2,960,960** | 512 | **3,040,960** | 576 |
| **B**, stored window, chunks kept in sync (re-centred and written back on a move) | 3,400,960 | 576 | 3,320,960 | 768 |
| **B′**, stored window as the working copy (occupancy deferred) | 2,280,960 | 320 | 2,880,960 (nothing pending) to **4,808,960** (4 chunks written back) | 512 to 768 |
| **S**, SPK-2's stand-in (one slot, occupancy from the goblins, no chunk) | 2,200,960 | 256 | 2,280,960 | 320 |

| Difference | L2 gas |
|---|---:|
| **A − S: the chunked map's part of the tick** | **760,000** (waiting and moving) |
| B − A | +440,000 waiting, +280,000 moving |
| B′ − A | −680,000 waiting, +1,768,000 moving with 4 chunks to write back |

In snforge, the calls alone (test minus its setup baseline): A 1,725,001 / 1,790,387, B 1,959,927 /
1,966,587, B′ 1,528,467 / 2,027,145 (nothing pending) / 3,840,925 (4 pending), S 1,506,617 /
1,572,003. The in-memory part of A, assembly included, is 1,440,249 (§2.1).

**Reveals**, each from a fresh instance, in a location of 7 × 7 chunks:

| Reveal | Meadow | Forest | Cave | Ruin | L1 data gas |
|---|---:|---:|---:|---:|---:|
| 1 chunk, no neighbour known | 2,455,200 | 2,415,200–2,455,200 | 2,455,200 | 2,415,200–2,455,200 | 320 |
| 1 chunk, its 4 neighbours known | 2,133,200 | 2,133,200 | 2,173,200 | 2,173,200 | 320 |
| **3 chunks** (an L), none known around | 5,639,680 | 5,239,680–5,479,680 | **5,679,680–5,839,680** | 5,559,680–5,759,680 | 448 |
| 3 chunks, the 7 around known | 5,317,680 | 4,997,680–5,237,680 | 5,557,680 | 5,237,680–5,477,680 | 448 |

The worst reveal is **3 chunks with no neighbour known, 5,839,680 L2 gas, in a cave**.
Drawing a side costs more than copying one: a copy is one storage read, an AND and a product; a
drawn side three divisions, two remainders and two table lookups. Three chunks form an L because
sight of radius 6 spans 13 tiles, less than a chunk: it touches at most a 2 × 2 block of chunks.
Chunk C of the L is on an odd chunk row: the parity flag is on the measured path.

At SPK-2's prices (L2 gas 21,687,750,610 fri, L1 data gas 1,544,531,203,854 fri, STRK $0.04061;
`spikes/SPK-2/prices-fixloop2-output.txt`): the chunked map's part of a tick $0.000685; the tick A
$0.00264 (waiting); a reveal of 1 chunk $0.00218, of 3 chunks $0.00517.

**Sum of two measurements (an estimate):** SPK-2's worst tick under D-127, 5,156,800 L2 gas, plus
A − S, 760,000, gives about **5,917,000 L2 gas** for the game's worst tick on chunked maps. The two
were measured on the same node version with different accounts and fixtures; the increment is
measured on one node, one account.

### 2.3 How many layers a winding 15 × 16 board can need

`boards.py` climbs from a spiral of one-tile corridors, toggling one interior tile at a time and
keeping the change when the adventurer's eccentricity does not fall (300,000 steps each):

```
deepest board found, adventurer on local (7, 7): 88 steps; on (7, 8): 91 steps
  walkable interior tiles of the (7, 7) board: 102 of 182
  flood with limit 10: 11 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit 15: 16 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit 20: 21 layers (start included), distances [0, 0, 0, 0, 0, 0, 0, 0]
  flood with limit None: 83 layers (start included), distances [0, 0, 0, 0, 82, 0, 0, 0]
```

SPK-2's hill climb reached an eccentricity of 93 (`spikes/SPK-2/src/fixtures.cairo`, `DEEP_TERRAIN`).
The bound is the interior less one tile, 181. **A winding window can need about 90 layers**; the
goblins, as obstacles under rule (a), cut it shorter (here the nearest of the 8 goblins, at the
end of the corridor, closes it at 82). At 25,612 per layer, the cap of 15 layers keeps the flood
under 0.45M where an unlimited one reaches 2.34M.

## 3. Verdict on R-12

R-12: *chunked maps exceed the cost budget (window assembly, chunk generation on reveal, flood)*.

| Part | Measured | Verdict |
|---|---|---|
| Assembly, computation | 65,734 in memory | Not the cost: 3.8 % of A's call in snforge (1,725,001) |
| Assembly, storage | 8 slot reads instead of 1, and up to 4 occupied layers written. In snforge A − S is 218,384, of which the assembly's computation is 65,734: the rest is storage. On the node, A − S = 760,000 (its split cannot be isolated there, SPK-2 §8.2) | **The cost of the chunked map.** +14.7 % on the worst tick |
| Flood | 25,612 a layer; the cap (D-127) holds it at 15 layers whatever the board | As SPK-2 found; the chunked map changes nothing |
| Reveal | 2.46M for 1 chunk, 5.84M for 3 (cave) | A few reveals per location: six reveals of 3 chunks are $0.031, 6 % of the $0.50 target (D-129) |

**R-12 is partly realised and is not a blocker.** The threshold of ADR-0001 was already out of reach
because of the fixed part of a transaction (SPK-1, D-129 point 4); the chunked map adds about 15 %
to the ticks that have goblins awake and nothing to the others, if the implementation assembles
the window only when a goblin is awake (§6). Keep D-120 (A) as the default; B, the stored window
as briefed, is worse in every case measured; B′ is the one measured way to cheapen fights and is a
choice for ENG-07 (§6).

## 4. The fallback (brief item 7): not built

The worst case exceeds the threshold (SPK-2 and SPK-1 already did), so the condition of item 7 is
met; the fallback would not help:
- **The chunks are the same.** A window of 13 × 14 still overlaps 4 chunks whenever it crosses a
  column and a row boundary (offsets `dx >= 3`, `dy >= 2`): the reads and writes that make A − S
  do not change in the worst case.
- **The flood is the same.** 182 bits is still the two-limb path, and the cap of 15 layers binds
  on a winding board of either size: the same 25,612 per layer.
- **The assembly gets worse.** A window 13 wide takes 13 of a chunk's 15 columns per row: a row of
  the chunk no longer lands on a row of the window by one shift of the whole felt. It becomes one
  mask and one shift per row and per chunk (14 rows × up to 2 chunks, each an AND and a product),
  about 14 times the work of today's assembly, or a loop over rows, which docs/CAIRO.md rules out.
- It saves flood layers only on open boards, where the flood is cheap anyway.

## 5. What the map library should provide (L-M1), and the gas to beat

Figures are snforge L2 gas in memory, on this spike's worst cases: the library's release candidate
should be measured on the same inputs (`spikes/SPK-7/tests/test_bench.cairo`) and beat them.

| Need | Function here | To beat | Notes for LIB-03 |
|---|---|---:|---|
| N-3 assembly | `assemble_window` | 65,734 (4 chunks), 35,370 (2) | Keep the masks as limb pairs (`u128`) in the tables: each `felt → u256` split of a mask costs range checks. The inverse (`scatter_window`) is needed only if the game stores the window (B′) |
| N-8 flood | `shared_flood` | 25,612 a layer, 618,475 the capped worst case | The hit test per layer (2 applications) and the goblin lookup per hit are the extra over a plain flood: a single-goblin fast path (one AND, felt comparisons) is here |
| N-8 selection | `step` (rule (a)) | 1,134,557 for the flood and 8 steps | Filter by the tiles goblins moved into this tick, not the whole occupancy: 0 until the first move, then sparse |
| N-1, N-2 generation with margins | `generate_chunk` | 447,462 (4 sides drawn), 402,560 (4 copied) | The automaton with margins must build its diagonal planes by OR, not by sum: row-wrapped edge bits collide and carry into the interior (found here by the oracle, `chunk.cairo`) |
| Parity flag | `CHUNK_EVEN[1]`, and `Dilation { even: CHUNK_EVEN[1], .. }` | — | `Layout::new` cannot express it; `Dilation`'s public fields can. The library should take the flag in its layout constructor |
| N-5 line of sight | `between_mask`, `line_of_sight` | 9,716 | Tables of 169 felts per row parity, valid for interior tiles up to 6 apart; a general line (beyond 6) is not measured here |
| Cutting by a mask (N-4) | — | — | Not needed by anything measured here |

What belongs where: the assembly, its inverse, the automaton with margins and parity, the component
flood with parity, the shared flood with its selection and line of sight are the library's; the
layers' storage, `move_goblin` (which chunk a goblin's bit lives in), the reveal's sides (which
neighbour is generated, the location's border) and the random word are the game's (ENG-05, ENG-07).

## 6. Open questions

**For ENG-05 (reveal engine)**
1. Corners wall (§7), lines to a spine for connectivity, and the component kept: the spike's
   choices. The component is a flood of up to 169 layers on the chunk; it removes the pockets no
   opening reaches (its share of a generation was not measured apart).
2. A drawn side costs more than a copied one: the worst reveal is the one with no neighbour
   known, not the one with most reads.
3. The revealed set as one felt holds 15 × 15 chunks (bit `15 cy + cx`): enough for 7 × 7
   locations; a larger zone needs two felts.

**For ENG-07 (the tick and the queue)**
4. **Assemble only when a goblin is awake.** Awake goblins can be found from their tiles; a move
   without goblins needs only the terrain bit of the tile entered (one chunk read). Then A − S is
   paid only by ticks with goblins.
5. **In a queue, read the chunks once per transaction** and write their occupancy once at the end:
   A − S is mostly storage, which a queue of 10 moves would otherwise pay 10 times. Not measured.
6. **B′ for fights**: a stored window that is the working copy saves 680,000 on every tick the
   adventurer does not move and costs up to 1,768,000 on the move that writes it back. Whether
   fights are long enough to pay for it depends on the queue's rules (the reopened queue in fights,
   Sepolia verdict, route (e)).
7. Which ≤ 8 goblins are awake when more stand in the window (design/02: nearest, ties by id)
   needs the goblins by chunk; the spike stores the 8 of the fixture only.

**For LIB-03**
8. The targets of §5, and the unit costs of §2.1: 4,170 per bit test, 1,265 per table lookup, 1,520
   per loop iteration.

## 7. Escalations

| Question | Why it stops here | Read |
|---|---|---|
| **The window at the border of a location.** An adventurer less than 7 columns or 8 rows from the location's edge gives a window origin below 0. The spike keeps its fixtures away from the border | ADR-0006 §4 does not say whether the window is clamped (then the adventurer is off-centre and sight can reach the ring), or whether locations keep a margin of void chunks (then coordinates start at 15) | ADR-0006 §4, D-120, docs/needs/hexmap.md N-3 |
| **Corners of a chunk are wall.** They are the only tiles adjacent to a diagonal chunk; the spike never opens them, so diagonal chunks never touch directly | ADR-0006 § Joining chunks speaks of edges shared by two chunks, not of corners | ADR-0006 §2, docs/needs/hexmap.md points 1 and D-22 |
