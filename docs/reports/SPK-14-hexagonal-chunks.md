# [Opus 5.5] SPK-14 — Hexagonal chunks of 251 tiles

## Summary

The session reports Opus 5.5, as the brief names. The first launch had the `research` profile and
could not build. It left an analytical draft and escalated, and the orchestrator resumed it with
the `implement` profile. This report replaces the first one.

**Pull request: https://github.com/bal7hazar/grimworld/pull/202**, CI green (all checks,
`cairo (spikes/SPK-14)` included). Never merged by me.

What exists now:
- **`spikes/SPK-14/`**, a Scarb package on `hexx` by git at `93639f2c17e3`, holding:
  - the 9-9-11 chunk's indexing and tile → chunk (`hexchunk.cairo`);
  - the 15 × 16 window from hexagonal chunks, as a walk of row runs, plus precomputed-piece
    variants (row runs; grouped, fix loop 1)
    (`window.cairo`);
  - a hexagonal chunk's generation with margins on two half-boards (`hexgen.cairo`);
  - SPK-7's rectangle generator on `hexx` (`rect.cairo`), for the same basis;
  - `geometry.py`, the shape in plain Python;
  - benchmarks, two clean runs, budgets, `BUDGETS.md` and `GAS.md`.
- **`docs/research/SPK-14-hexagonal-chunks.md`**, rewritten on the measurements: the six answers,
  the figures side by side, the list of changes, the recommendation.

The figures below are snforge L2 gas in memory, each benchmark twice − once, from two clean
builds that gave identical figures:

| | Rectangle | Hexagon | Ratio |
|---|---:|---:|---:|
| Window assembly, both layers, the class with the most row runs (bit 25) | **64,234** (N-3, re-measured: equal to the library's) | **876,310** | 13.6 |
| Window, a class with 6 chunks | — | 799,152 | 12.4 |
| Window, row runs precomputed (not a floor: fix loop 1) | — | 318,044 | 5.0 |
| Window, grouped pieces precomputed, the class with the most of them (bit 65, fix loop 1) | — | 268,428 | 4.2 |
| Tile → chunk (`origin`) | 3,730 | 56,910 | 15.3 |
| Generation, one chunk, the most among the fixtures measured | 444,774 (ruin, drawn; inside SPK-7's 0.39–0.45 M) | 1,146,507 (meadow, copied) | 2.58 |
| Generation, range over 4 biomes × drawn/copied | 395,572–444,774 | 967,175–1,146,507 | 2.17–2.84 |

**Recommendation: keep the 15 × 15 rectangle.** The reversal thresholds of the first draft are
kept: an assembly within about 2× N-3, and generation within SPK-7's 0.39–0.45 M. Both now fail
on measurements.

**For the project manager: D-165's "27 tiles at its widest (11 + 2 × 8)" is wrong: the widest row
is 19 (11 + 8).** The hexagon widens by half a tile on each side per row. Its bounding box is
19 × 17, wider than the 15-wide window, which is why a window row crosses up to 3 chunks.
(`geometry.py` asserts the widths `[11, …, 19, …, 11]` and the 19-wide bounding box.)

## Files changed

In the pull request, all inside the allowlist:
- `docs/research/SPK-14-hexagonal-chunks.md`: the note, measured figures, labels M/G/C/E.
- `spikes/SPK-14/Scarb.toml`, `Scarb.lock`, `.gitignore`, `.cairofmtignore`: the package, with
  `hexx` by git at `93639f2c17e3`.
- `spikes/SPK-14/src/hexchunk.cairo`: `index`, `tile`, `locate`; unit tests (bijection, corners,
  `locate` against a brute-force search).
- `spikes/SPK-14/src/window.cairo`: `HexWindowTrait::window` (the walk) and `origin`,
  `HexWindowTableTrait::window` (precomputed pieces); unit tests (all 251 classes against a direct
  construction; void chunks).
- `spikes/SPK-14/src/hexgen.cairo`: `HexChunkGenTrait::generate` and its steps; unit tests (the
  automaton and the component against plain versions, whole-chunk invariants, walkable shares,
  the rectangle).
- `spikes/SPK-14/src/rect.cairo`: SPK-7's `generate_chunk` on `hexx`.
- `spikes/SPK-14/src/automaton.cairo`, `types.cairo`: SPK-7's rule, biomes and sides, shared.
- `spikes/SPK-14/src/tables.cairo`, `pieces.cairo`: generated.
- `spikes/SPK-14/src/testing.cairo`: the helpers of the unit tests.
- `spikes/SPK-14/tests/bench_window.cairo`, `bench_generation.cairo`, `test_micro.cairo`:
  benchmarks and unit costs.
- `spikes/SPK-14/geometry.py`, `geometry-output.txt`: the shape; the walk and `locate` checked in
  Python.
- `spikes/SPK-14/generation.py`, `gen_tables.py`: the constants; the six sides' copy maps checked.
- `spikes/SPK-14/summarize.py`, `summary.md`, `set_budgets.py`, `test.sh`, `README.md`.
- `spikes/SPK-14/snforge-test-output-1.txt`, `snforge-test-output-2.txt`: the two runs.
- `spikes/SPK-14/BUDGETS.md`, `GAS.md`: written by `scripts/gas_budgets.py`.

## Commands run

```
$ python3 spikes/SPK-14/geometry.py            (output in geometry-output.txt)
shape: 17 rows, widths [11, 12, 13, 14, 15, 16, 17, 18, 19, 18, 17, 16, 15, 14, 13, 12, 11] - bijection onto 0..250 checked
corners at bits [0, 10, 116, 134, 240, 250] - sides 11, 9, 9, 11, 9, 9; ring 52 tiles, interior 199
tiling: lattice T_U = (-9, 17), T_R = (19, -8); six neighbours checked
window: at most 32 row segments per layer (rectangles: 4 pieces)
sight radius 6: touches at most 4 chunks
linear layouts: the smallest span is 307 bits (q, stride 19)
plan: the walk equals the direct construction on all 251 origin classes; at most 32 pieces; slots [(0, -1), (0, 0), (0, 1), (1, 0), (1, 1), (1, 2), (2, 1), (2, 2)]
plan: runs per window row {1: 400, 2: 3424, 3: 192}
locate: rounding and at most one translation find the chunk of every tile of 256 x 256
worst class: origin tile (8, 2), bit 25: 32 pieces over 4 chunks
most chunks over the classes: 6; among those, origin tile (15, 11), bit 185: 28 pieces
chunks per window over the 251 classes: {3: 50, 4: 173, 5: 26, 6: 2}

$ python3 spikes/SPK-14/generation.py
sides: six sides of 9, 9, 7, 7, 7, 7 non-corner tiles; facing maps are bijections

$ scarb --manifest-path spikes/SPK-14/Scarb.toml clean && spikes/SPK-14/test.sh snforge-test-output-1.txt
passed: 66
Tests: 66 passed, 0 failed, 0 ignored, 0 filtered out
$ scarb --manifest-path spikes/SPK-14/Scarb.toml clean && spikes/SPK-14/test.sh snforge-test-output-2.txt
passed: 66
Tests: 66 passed, 0 failed, 0 ignored, 0 filtered out

$ python3 spikes/SPK-14/summarize.py spikes/SPK-14/snforge-test-output-{1,2}.txt   (summary.md)
bench_rect_window 64,234 | 64,234        bench_hex_window 876,310 | 876,310
bench_hex_window_six 799,152 | 799,152   bench_table_window 318,044 | 318,044   bench_table_window_six 289,880 | 289,880
bench_rect_origin 3,730 | 3,730          bench_hex_origin 56,910 | 56,910
generate rect open  meadow 435,136  forest 420,268  cave 436,014  ruin 444,774   (both runs)
generate rect copy  meadow 410,440  forest 395,572  cave 430,004  ruin 420,078
generate hex open   meadow 991,591  forest 968,175  cave 1,033,617  ruin 967,175
generate hex copy   meadow 1,146,507  forest 1,122,301  cave 1,141,153  ruin 1,121,301
unit costs: table lookup 1,005-1,370, loop iteration 1,895

$ (test_generate_shares, walkable share of the interior in thousandths, 16 words)
share Meadow: hexagon 938 rectangle 833
share Forest: hexagon 824 rectangle 672
share Cave: hexagon 653 rectangle 479
share Ruin: hexagon 648 rectangle 467

$ python3 spikes/SPK-14/set_budgets.py spikes/SPK-14/snforge-test-output-{1,2}.txt
budgets set: 66; measured without a declaration found: []
$ python3 scripts/gas_budgets.py --check --workspace .with-node/gasws --budgets spikes/SPK-14/BUDGETS.md --from-output .with-node/spk14-output.txt
gas check: 66 tests, every budget is ceil(1.05 x measured) or lower, 2 files current

$ gh pr checks 202 --watch --interval 30
every check pass (cairo (spikes/SPK-14) 41s, cairo (contracts), tooling, client, …); indexer-node skipping
```

Two failures on the way, both fixed:
- `scarb fmt` was killed (exit 137) on a generated table of 7,824 tuples. The pieces now live in
  their own module, left out of the formatter.
- Scarb 2.19.4 refused that table as one constant: "Type size computation failed for
  `[1435154]`: size overflow". Only the two benchmark classes' tables are generated.

## Cost

Printed by `python3 scripts/gas_budgets.py --report` (throwaway workspace
`.with-node/gasws`, run 1). All rows are new: this is a new package, so no budget was raised.
The benchmark figures above are differences of these rows.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| spk14::bench_generation::bench_generate_hex_cave_copy_once | — | 8901417 | 9346488 | new |
| spk14::bench_generation::bench_generate_hex_cave_copy_twice | — | 10042570 | 10544699 | new |
| spk14::bench_generation::bench_generate_hex_cave_open_once | — | 8739721 | 9176708 | new |
| spk14::bench_generation::bench_generate_hex_cave_open_twice | — | 9773338 | 10262005 | new |
| spk14::bench_generation::bench_generate_hex_forest_copy_once | — | 8882565 | 9326694 | new |
| spk14::bench_generation::bench_generate_hex_forest_copy_twice | — | 10004866 | 10505110 | new |
| spk14::bench_generation::bench_generate_hex_forest_open_once | — | 8720869 | 9156913 | new |
| spk14::bench_generation::bench_generate_hex_forest_open_twice | — | 9689044 | 10173497 | new |
| spk14::bench_generation::bench_generate_hex_meadow_copy_once | — | 8906771 | 9352110 | new |
| spk14::bench_generation::bench_generate_hex_meadow_copy_twice | — | 10053278 | 10555942 | new |
| spk14::bench_generation::bench_generate_hex_meadow_open_once | — | 8749025 | 9186477 | new |
| spk14::bench_generation::bench_generate_hex_meadow_open_twice | — | 9740616 | 10227647 | new |
| spk14::bench_generation::bench_generate_hex_ruin_copy_once | — | 8927955 | 9374353 | new |
| spk14::bench_generation::bench_generate_hex_ruin_copy_twice | — | 10049256 | 10551719 | new |
| spk14::bench_generation::bench_generate_hex_ruin_open_once | — | 8766459 | 9204782 | new |
| spk14::bench_generation::bench_generate_hex_ruin_open_twice | — | 9733634 | 10220316 | new |
| spk14::bench_generation::bench_generate_rect_cave_copy_once | — | 8165762 | 8574051 | new |
| spk14::bench_generation::bench_generate_rect_cave_copy_twice | — | 8595766 | 9025555 | new |
| spk14::bench_generation::bench_generate_rect_cave_open_once | — | 8193358 | 8603026 | new |
| spk14::bench_generation::bench_generate_rect_cave_open_twice | — | 8629372 | 9060841 | new |
| spk14::bench_generation::bench_generate_rect_forest_copy_once | — | 8156336 | 8564153 | new |
| spk14::bench_generation::bench_generate_rect_forest_copy_twice | — | 8551908 | 8979504 | new |
| spk14::bench_generation::bench_generate_rect_forest_open_once | — | 8183932 | 8593129 | new |
| spk14::bench_generation::bench_generate_rect_forest_open_twice | — | 8604200 | 9034410 | new |
| spk14::bench_generation::bench_generate_rect_meadow_copy_once | — | 8171204 | 8579765 | new |
| spk14::bench_generation::bench_generate_rect_meadow_copy_twice | — | 8581644 | 9010727 | new |
| spk14::bench_generation::bench_generate_rect_meadow_open_once | — | 8198800 | 8608740 | new |
| spk14::bench_generation::bench_generate_rect_meadow_open_twice | — | 8633936 | 9065633 | new |
| spk14::bench_generation::bench_generate_rect_ruin_copy_once | — | 8158996 | 8566946 | new |
| spk14::bench_generation::bench_generate_rect_ruin_copy_twice | — | 8579074 | 9008028 | new |
| spk14::bench_generation::bench_generate_rect_ruin_open_once | — | 8208438 | 8618860 | new |
| spk14::bench_generation::bench_generate_rect_ruin_open_twice | — | 8653212 | 9085873 | new |
| spk14::bench_window::bench_grouped_window_most_once | — | 298858 | 313801 | new |
| spk14::bench_window::bench_grouped_window_most_twice | — | 567286 | 595651 | new |
| spk14::bench_window::bench_grouped_window_once | — | 224014 | 235215 | new |
| spk14::bench_window::bench_grouped_window_six_once | — | 253792 | 266482 | new |
| spk14::bench_window::bench_grouped_window_six_twice | — | 477154 | 501012 | new |
| spk14::bench_window::bench_grouped_window_twice | — | 417598 | 438478 | new |
| spk14::bench_window::bench_hex_layer_once | — | 798642 | 838575 | new |
| spk14::bench_window::bench_hex_layer_six_once | — | 727463 | 763837 | new |
| spk14::bench_window::bench_hex_layer_six_twice | — | 1422996 | 1494146 | new |
| spk14::bench_window::bench_hex_layer_twice | — | 1565354 | 1643622 | new |
| spk14::bench_window::bench_hex_origin_once | — | 91150 | 95708 | new |
| spk14::bench_window::bench_hex_origin_twice | — | 148060 | 155463 | new |
| spk14::bench_window::bench_hex_window_once | — | 906140 | 951447 | new |
| spk14::bench_window::bench_hex_window_six_once | — | 828982 | 870432 | new |
| spk14::bench_window::bench_hex_window_six_twice | — | 1628134 | 1709541 | new |
| spk14::bench_window::bench_hex_window_twice | — | 1782450 | 1871573 | new |
| spk14::bench_window::bench_rect_layer_once | — | 74464 | 78188 | new |
| spk14::bench_window::bench_rect_layer_twice | — | 113898 | 119593 | new |
| spk14::bench_window::bench_rect_origin_once | — | 37970 | 39869 | new |
| spk14::bench_window::bench_rect_origin_twice | — | 41700 | 43785 | new |
| spk14::bench_window::bench_rect_window_once | — | 99264 | 104228 | new |
| spk14::bench_window::bench_rect_window_twice | — | 163498 | 171673 | new |
| spk14::bench_window::bench_table_window_once | — | 348474 | 365898 | new |
| spk14::bench_window::bench_table_window_six_once | — | 320310 | 336326 | new |
| spk14::bench_window::bench_table_window_six_twice | — | 610190 | 640700 | new |
| spk14::bench_window::bench_table_window_twice | — | 666518 | 699844 | new |
| spk14::hexchunk::tests::test_corners_and_live_bit | — | 41780 | 43869 | new |
| spk14::hexchunk::tests::test_index_is_a_bijection | — | 6757260 | 7095123 | new |
| spk14::hexchunk::tests::test_index_refuses_outside | — | 17210 | 18071 | new |
| spk14::hexchunk::tests::test_locate_matches_plain | — | 1482967730 | 1557116117 | new |
| spk14::hexgen::tests::test_component_matches_plain | — | 235859516 | 247652492 | new |
| spk14::hexgen::tests::test_generate_open_border_and_copy | — | 419437536 | 440409413 | new |
| spk14::hexgen::tests::test_generate_shares | — | 100473150 | 105496808 | new |
| spk14::hexgen::tests::test_rect_generate_deterministic_corners_wall | — | 1508495 | 1583920 | new |
| spk14::hexgen::tests::test_smooth_matches_plain | — | 230038455 | 241540378 | new |
| spk14::test_micro::micro_below_lookup | — | 501990 | 527090 | new |
| spk14::test_micro::micro_loop_baseline | — | 189520 | 198996 | new |
| spk14::test_micro::micro_mod_baseline | — | 327990 | 344390 | new |
| spk14::test_micro::micro_pow_lookup | — | 289990 | 304490 | new |
| spk14::test_micro::micro_row_lookup | — | 464990 | 488240 | new |
| spk14::test_micro::micro_slot_lookup | — | 435490 | 457265 | new |
| spk14::window::tests::test_window_matches_plain_0_to_63 | — | 4223604347 | 4434784565 | new |
| spk14::window::tests::test_window_matches_plain_126_to_189 | — | 4221973603 | 4433072284 | new |
| spk14::window::tests::test_window_matches_plain_189_to_251 | — | 4156554927 | 4364382674 | new |
| spk14::window::tests::test_window_matches_plain_63_to_126 | — | 4221823599 | 4432914779 | new |
| spk14::window::tests::test_window_void_chunks_are_wall | — | 65791255 | 69080818 | new |

## Acceptance criteria

- [x] **AC-1**, the six questions: note §1–§6.
  - Shape and indexing: computed (G) and tested (M).
  - Storage words: reasoned, 0 slots.
  - Window: counts (G), cost (M).
  - Reveal and generation: cost (M), sight bound (G).
  - Changes: §5.
  - Recommendation: §6.
- [x] **AC-2**, measured where SPK-7 measured, each twice:
  - the window's assembly: `bench_*_window_*`;
  - a chunk's generation: `bench_generate_*`.

  Two runs from clean builds (`snforge-test-output-1.txt`, `-2.txt`) gave identical figures. The
  rectangle was re-measured beside the hexagon on the same basis: N-3's own `window` (64,234,
  equal to the library's figure), and SPK-7's generator on `hexx` (0.40–0.44 M, inside SPK-7's
  range).
- [x] **AC-3**, the bijection and the assembly tested:
  - `hexchunk::tests::test_index_is_a_bijection`: every tile of the definition gets bits 0–250
    in order, inverted by `tile`;
  - `window::tests::test_window_matches_plain_*`: all 251 origin classes, random chunks in all 12
    slots, both layers, against a tile-by-tile construction from the definition, plus `origin`
    on both row parities;
  - `test_window_void_chunks_are_wall`: void chunks;
  - `geometry.py`: the same walk against a direct construction in Python.
- [x] **AC-4**: note §6.
  - The reversal thresholds are kept and each is judged against its measurement: assembly 13.6×,
    and 4.2× for grouped precomputed pieces on the class with the most of them (fix loop 1), against about 2×; generation 0.97–1.15 M against
    0.39–0.45 M.
  - Every figure is labelled M (measured here), G (computed and asserted), C (cited) or E
    (estimate). The estimates that remain: the reveal as a transaction (about 7.7 M), the tick in
    money (about $0.00073, +27 % of SPK-7's worst tick), and the lattice range of a 100 × 100
    location.

## Deviations from the brief

- **Unit tests in their modules** (D-167, merged into `main` during the task and merged into the
  branch). The oracle tests are `#[cfg(test)] mod tests` in `hexchunk.cairo`, `window.cairo` and
  `hexgen.cairo`; `tests/` holds only the gas benchmarks and unit costs. The brief predates the
  rule.
- **The rectangle's generator is SPK-7's code on `hexx`** instead of `origami_hexmap` 1.8.0, so
  both shapes are measured in one package on one library. Its figures stay inside SPK-7's range.
- **Table-driven window variants** were added beyond the brief. The row-run one was first
  described as the floor of the per-piece work, a claim withdrawn in fix loop 1; the grouped one
  was added in fix loop 1. Their tables are generated for the benchmark classes only, because the
  monolithic row-run table attempted does not compile.
- **The hexagon's biome parameters are SPK-7's, not retuned.** Its walkable shares sit above
  design/18's ranges (meadow 93.8 %, cave 65.3 %). Tuning is ENG-05's if the hexagon were taken.
  It would change the component's number of layers, not the two-board structure behind the cost
  factor.
- The draft's hand figures are all confirmed by `geometry.py`, with one correction: I first wrote
  502 origin classes, and there are 251, since an even origin row fixes the chunk's parity. The
  draft's cost estimates were low (window 0.25–0.6 M estimated, 0.88 M measured) and are all
  replaced.

## Escalations

1. **D-165's figure is wrong** (for the project manager): "27 tiles at its widest (11 + 2 × 8)"
   should be **19 (11 + 8)**, with a bounding box of 19 × 17. `docs/decisions/` is not in my
   allowlist.
2. **D-134's corner rule needs a new reason if the hexagon is ever taken.** A hexagonal tiling has
   no diagonal neighbours. The rule still holds because a corner lies on two sides facing two
   neighbours, and it yields `LIVE` (note §4.3).
3. **The audit** (`[GPT-6-Astra]`, cost and determinism) is the orchestrator's to launch through
   `nexus audit`.

## Open questions

- A design this study did not find could still reverse threshold 1 or 2. The note (§6) names one,
  a lattice-aligned window, and why it does not fit D-120.
- The window's class size was not measured as a contract. The table variant's data alone is
  39,120 felts, 48 % of the CASM limit (counted, not compiled). The walk's code size is small but
  unmeasured.

## Fix loop 1

The `[GPT-6-Astra]` audit of PR 202 at `480a4dc` was **PASS WITH FINDINGS**, with two minors.
`origin/main` was merged first (no change to `docs/CAIRO.md`, `COMMON.md` or the gas tool).
Commit `cb40a4c`; CI green on every check (`indexer-node` skipping, as before).

| Finding | Fix |
|---|---|
| 1 (minor) 318,044 is not an established assembly floor; "no trick removes the runs themselves" is false | **Withdrawn**, in the note (§3.2, Summary, §6) and in this report. 318,044 is now named for what it is, the precomputed **row-run** variant. **The audit's grouping is measured instead of estimated.** Runs of one chunk that move by the same shift share one piece and one mask (`gen_tables.py` `grouped_pieces`; tables `GROUPED_25`, `GROUPED_65`, `GROUPED_185`, checked against the direct construction in `window::tests`). Counted over all 251 classes: **15 to 26 pieces** (G), 17 for bit 25 and 20 for bit 185, as the audit found. Measured (M, two clean runs, identical): bit 25 **193,584** (3.0×), bit 185 **223,362** (3.5×), and bit 65, the class with the most grouped pieces (26), **268,428** (4.2×). **The lower bound the grouping supports** (E, a line through the three measurements: 8,316 a piece plus about 52,212 fixed): about 177,000 (2.8×) on the class with the fewest pieces. Only the per-piece work alone of that best class, with no fixed part at all, reaches 1.94×, and N-3's own 64,234 includes such a part. Since the window must be assembled for any class, the figure that counts is the class with the most pieces: 4.2× measured, 3.4× for its per-piece work alone. **Even that bound does not meet the reversal threshold of about 2× N-3 (128,468).** The note keeps the grouping labelled as the audit's, not a proven minimum. The compile failure is now scoped to the monolithic row-run table attempted, not to every table design |
| 2 (minor) "worst" claims beyond the benchmarks' coverage | Relabelled, not extended. The window classes are named by how they were chosen (the most row runs, the most chunks, the most grouped pieces), with the statement that these are **maxima among the classes measured**. Generation figures are **the maxima among the fixtures measured**, with their coverage stated: one word per biome, all sides drawn or all copied, and a flood length that depends on the word. "Worst" remains only where it cites SPK-7's own figures or the library's benchmark case |

Commands:

```
$ python3 spikes/SPK-14/gen_tables.py
grouped pieces per class: max 26 (class 65), min 15, classes 25 and 185: 17, 20; distribution {15: 2, 16: 30, 17: 22, 18: 22, 19: 12, 20: 56, 21: 48, 22: 10, 23: 30, 24: 13, 25: 4, 26: 2}
$ scarb --manifest-path spikes/SPK-14/Scarb.toml clean && spikes/SPK-14/test.sh snforge-test-output-1.txt   (and -2, after another clean)
Tests: 72 passed, 0 failed, 0 ignored, 0 filtered out     (both runs)
$ python3 spikes/SPK-14/summarize.py spikes/SPK-14/snforge-test-output-{1,2}.txt
bench_grouped_window 193,584 | 193,584   bench_grouped_window_six 223,362 | 223,362   bench_grouped_window_most 268,428 | 268,428
every earlier figure unchanged (bench_rect_window 64,234, bench_hex_window 876,310, generation as above)
$ python3 scripts/gas_budgets.py --check ...
gas check: 72 tests, every budget is ceil(1.05 x measured) or lower, 2 files current
```

- The 6 new benchmarks are the grouped variant's `once` and `twice` tests for three classes.
- The benchmark inputs grew by one fixture, which raised every window `once`/`twice` row by the
  same amount; the differences are unchanged. Four `once` budgets went stale, were stripped,
  re-measured from two clean builds with every attribute in place, and set again. The first
  re-measure without the attributes read exactly 100 gas less, the attribute's own cost.
- The Cost table above is the new `--report`.
- Nothing else changed: generation and its figures, the storage answer and the recommendation
  (keep 15 × 15) are as before.

## Fix loop 2

The Codex review of PR 202 at `cb40a4c` was **FAIL**, on the note's analysis of the hexagonal
option (the measurements were not in question). `origin/main` was merged first; it had not moved.
Commit `672d639`; CI green on every check (`indexer-node` skipping, as before).

| Review | Fix |
|---|---|
| 1 (major) `15 b + a` does not cover ENG-01's largest location (225 × 225 tiles) | **Withdrawn and replaced; the revealed set stays one felt, 0 new slots** (note §4.3, §5). `geometry.py` `check_revealed` (G) counts the chunks such a location touches over all 251 placements of the lattice: **226 to 241**, always below 250. The placement proposed puts the location's tile (0, 0) on bit 0 of chunk (0, 0). That gives **227 chunks**, rows `b` 0–15, each row one contiguous run of `a`, asserted. **The index:** `bit = FIRST_B[b] + a − A_MIN[b]`, two 16-entry tables, both given in the note. Bits 0–226 hold chunks and 250 stays `LIVE`. **Cost:** two lookups instead of `15 cy + cx`, about 2,000–2,700 (E). **What moves with it:** chunk keys and `OUTLINE` ids still fit; goblin entity ids reach 3,633, still a `u16` |
| 2 (minor) the "+812,076 a tick" applied a two-layer difference to a one-layer tick | **Measured on one layer.** `HexWindowTrait::assemble`, the same walk on one layer, is tested against the direct construction on all 251 classes. **Rectangle:** the library's `AssemblyTrait::assemble`, **39,434** (M), which matches the library's own one-layer benchmark. **Hexagon:** **766,712** on the class with the most runs, 695,533 on the 6-chunk class (M). **The tick's difference is now +727,278 in memory** (M, a difference; the ring and the map are common and cancel). In money, about $0.00066 a tick at SPK-7's prices (E). Against D-166's proved worst tick of 15.1 M (C), about +4.8 % (E), where the note had said +27 % of SPK-7's tick. N-3's two-layer comparison (64,234 against 876,310) is kept as the N-3 basis |
| 3 (minor) the 7.7 M reveal mixed SPK-7's transaction with ENG-01's layout | **Recomputed on one basis each, labelled E** (note §4.4). **On SPK-7's layout** (1 new slot a chunk): rectangle 5,919,680 (C), hexagon about 7.71 M, adding the generation difference 1,792,809. **On ENG-01's layout** (2 new slots a chunk): add 3 × 453,524 to both, rectangle about 7.28 M and hexagon about 9.07 M |

Commands:

```
$ python3 spikes/SPK-14/geometry.py > spikes/SPK-14/geometry-output.txt
revealed: a 225 x 225 location touches 226 to 241 chunks over the 251 placements of the lattice; placed at chunk (0, 0) bit 0, 227 chunks, b 0..15, a runs per b (b, a_min, a_max, first bit): [(0, 0, 13, 0), (1, 0, 13, 14), ..., (15, 7, 20, 213)]
$ scarb --manifest-path spikes/SPK-14/Scarb.toml clean && spikes/SPK-14/test.sh snforge-test-output-1.txt   (and -2, after another clean)
Tests: 78 passed, 0 failed, 0 ignored, 0 filtered out     (both runs)
$ python3 spikes/SPK-14/summarize.py spikes/SPK-14/snforge-test-output-{1,2}.txt
bench_rect_layer 39,434 | 39,434   bench_hex_layer 766,712 | 766,712   bench_hex_layer_six 695,533 | 695,533
every earlier figure unchanged (bench_rect_window 64,234, bench_hex_window 876,310, grouped, generation)
$ python3 scripts/gas_budgets.py --check ...
gas check: 78 tests, every budget is ceil(1.05 x measured) or lower, 2 files current
```

- The 6 new benchmarks were measured twice from clean builds with their budget attributes in
  place. The Cost table above is the new `--report`.
- The recommendation stays as the figures give it: keep 15 × 15. The tick's increment went from
  +812,076 (two layers) to +727,278 (one layer), and both reversal thresholds still fail.
