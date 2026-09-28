# [Opus 5.5] SPK-7 — Chunked map spike

## Summary
The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

What exists now:
- `spikes/SPK-7/`: a native Starknet package on the repository's toolchain (root `.tool-versions`, no pin of its own), with `origami_hexmap` 1.8.0 by published version. It prototypes, under the names of the library needs:
  - `generate_chunk` (N-1, N-2): margins, edges and openings, the parity flag, the four biomes of design/18;
  - `assemble_window` (N-3): no loop, masks from tables, one shift per chunk and layer;
  - `shared_flood` and `step` (N-8): rule (a), capped at 15 layers;
  - `line_of_sight` (N-5);
  - `move_goblin`: crossing chunks.
- An `Instances` contract with `reveal` and four tick variants:
  - A, assembled at each tick (D-120);
  - B, a stored window re-centred and written back (as briefed);
  - B′, a stored window as the working copy (added);
  - S, SPK-2's one-slot stand-in (added, so that A − S isolates the chunked map's cost).
- 96 snforge tests, each with a budget of ceil(1.05 × measured):
  - oracles for the assembly (all 225 offsets, 2 and 4 chunks, both parities), the automaton and the component (both chunk parities), the flood and the steps (scalar BFS), and line of sight (14,708 pairs);
  - benchmarks with baselines.
- A node script whose receipts come from three runs of 51 transactions each, all `SUCCEEDED`.
- `docs/research/SPK-7-chunked-maps.md`: every figure with its command, the stored against not-stored comparison, the verdict on R-12, the targets for L-M1, and the open questions.

Key figures (local node receipts, L2 gas):
- **The worst-case tick:**
  - A: 2,960,960 waiting, 3,040,960 moving.
  - B: 3,400,960 and 3,320,960.
  - B′: 2,280,960 waiting, and 2,880,960 to 4,808,960 moving.
  - S: 2,200,960 and 2,280,960.
  - **The chunked map adds 760,000 per tick with goblins, +14.7 % on SPK-2's worst tick.**
- **Reveal:** one chunk 2,455,200; three chunks 5,839,680 (cave).
- **In memory:**
  - assembly 65,734 for 4 chunks (the ADR estimated about 40k);
  - flood 25,612 per layer, and 618,475 for the capped worst case;
  - line of sight 9,716.
- **R-12:** partly realised, not a blocker. The cost is the window's storage traffic, paid only on ticks with goblins awake.
- **Fallback:** not built. It would not lower the worst case (§4 of the research file).

Pull request: https://github.com/bal7hazar/grimworld/pull/50. CI is green (all jobs; `cairo (spikes/SPK-7)`: 96 tests passed). Not merged.

## Files changed
- `spikes/SPK-7/Scarb.toml`, `.gitignore`: the package, on the root toolchain, with `max_n_steps` raised for the oracle tests.
- `spikes/SPK-7/src/window.cairo`: `window_origin`, `window_chunks`, `assemble_window` (N-3), and `scatter_window` (its inverse, for B′).
- `spikes/SPK-7/src/chunk.cairo`: `generate_chunk` (N-1, N-2), `smooth` (the automaton with margins and parity), `keep_component`.
- `spikes/SPK-7/src/flood.cairo`: `shared_flood` and `step` (N-8, rule (a), D-127).
- `spikes/SPK-7/src/sight.cairo`: `between_mask` and `line_of_sight` (N-5).
- `spikes/SPK-7/src/tick.cairo`: `world_tick`, `move_goblin` and `apply_moves` (item 4).
- `spikes/SPK-7/src/contract.cairo`: the `Instances` contract, with `reveal`, `act` (A), `act_stored` (B), `act_deferred` (B′), `act_standin` (S), setups and views.
- `spikes/SPK-7/src/fixtures.cairo`: the worst-case world cut into chunks, and the reveal fixture (an L of 3 chunks).
- `spikes/SPK-7/src/tables.cairo`, `src/boards.cairo`: generated constants (masks, line-of-sight tables, winding boards).
- `spikes/SPK-7/src/lib.cairo`: the module list.
- `spikes/SPK-7/tests/*.cairo`: 96 tests (oracles, invariants, benchmarks, contract calls, unit costs).
- `spikes/SPK-7/model.py`, `gen_tables.py`, `boards.py`, `tune.py`: the plain Python model, and the generators of tables, boards and biome parameters.
- `spikes/SPK-7/devnet.py`, `summarize.py`: the transactions on the local node, and their table.
- `spikes/SPK-7/snforge-test-output.txt`, `devnet-output-{1,2,3}.txt`, `devnet-summary.md`: raw outputs.
- `spikes/SPK-7/BUDGETS.md`, `GAS.md`: written by `scripts/gas_budgets.py`.
- `spikes/SPK-7/README.md`: what is where, and the commands.
- `docs/research/SPK-7-chunked-maps.md`: the research file.

## Commands run
```
$ scripts/lock.sh scarb --manifest-path spikes/SPK-7/Scarb.toml build
    Finished `dev` profile target(s) in 4 seconds

$ cd spikes/SPK-7 && snforge test > snforge-test-output.txt && cd -
Collected 96 test(s) from spk7 package
shares (thousandths): meadow 832 forest 665 cave 478 ruin 461
unlimited flood on the deep board: 83 layers
Tests: 96 passed, 0 failed, 0 ignored, 0 filtered out

$ scarb fmt --check        (from spikes/SPK-7)   -> clean

$ python3 scripts/gas_budgets.py --check --workspace .with-node/gasws --budgets spikes/SPK-7/BUDGETS.md --from-output .with-node/spk7-output.txt
gas: spikes/SPK-7/BUDGETS.md is absent at origin/main: empty baseline
gas check: 96 tests, every budget is ceil(1.05 x measured) or lower, 2 files current

$ scripts/with-node.sh python3 spikes/SPK-7/devnet.py > spikes/SPK-7/devnet-output-1.txt   (and -2, -3)
  51 transactions per run, 51 SUCCEEDED; {"check": "goblins after the nine ticks are equal", "ok": true} in each run

$ python3 spikes/SPK-7/summarize.py spikes/SPK-7/devnet-output-*.txt > spikes/SPK-7/devnet-summary.md
| worst-case tick, A (assembled), adventurer waits | 2,960,960 | 512 |
| worst-case tick, B (stored), adventurer waits | 3,400,960 | 576 |
| worst-case tick, A (assembled), adventurer moves | 3,040,960 | 576 |
| worst-case tick, B (stored, re-centred and written back), adventurer moves | 3,320,960 | 768 |
| worst-case tick, S (SPK-2's stand-in), adventurer waits | 2,200,960 | 256 |
| worst-case tick, S (SPK-2's stand-in), adventurer moves | 2,280,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred), adventurer waits | 2,280,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred, nothing pending, re-centred), adventurer moves | 2,880,960 | 512 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, re-centred), adventurer moves | 4,808,960 | 768 |
| A − S, adventurer waits (the chunked map's part of the tick) | 760,000 |
| reveal 1 chunk, no neighbour known | cave, forest, meadow, ruin | 2,455,200 |
| reveal 3 chunks, no neighbour known | cave | 5,839,680 |

$ python3 spikes/SPK-7/boards.py
deepest board found, adventurer on local (7, 7): 88 steps; on (7, 8): 91 steps
capped worst case: valid True, crossings 5, distinct distances 7, steps 8
  dx 7 dy 7, unlimited depth 20, distances [13, 3, 15, 4, 3, 2, 5, 7]

$ python3 spikes/SPK-7/gen_tables.py
wrote .../src/tables.cairo; line-of-sight tables checked on 14708 ordered pairs of interior tiles

$ gh pr checks 50 --watch --interval 30
cairo (spikes/SPK-7)  pass  39s    (log: Tests: 96 passed, 0 failed)
... every job pass
```

## Cost
Printed by `python3 scripts/gas_budgets.py --report --workspace .with-node/gasws --budgets spikes/SPK-7/BUDGETS.md --from-output .with-node/spk7-output.txt` from the worktree root, with `origin/main` fetched.

A spike is not a member of `contracts/`, so the tool reads the run through a throwaway workspace manifest outside git, as `spikes/SPK-7/README.md` explains.

Every row is new; there is no budget before this task. Each benchmark's own cost is its figure minus its baseline's (`docs/research/SPK-7-chunked-maps.md` §2.1). The contract rows include deployment and setup.

*(Replaced in fix loop 1 by the new run's table; see the Fix loop 1 section.)*

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| spk7::test_bench::bench_assemble_2_chunks | — | 11043494 | 11595669 | new |
| spk7::test_bench::bench_assemble_2_chunks_baseline | — | 10977460 | 11526333 | new |
| spk7::test_bench::bench_assemble_2_chunks_once | — | 11043394 | 11595564 | new |
| spk7::test_bench::bench_assemble_2_chunks_twice | — | 11108618 | 11664049 | new |
| spk7::test_bench::bench_assemble_4_chunks | — | 11039324 | 11591291 | new |
| spk7::test_bench::bench_assemble_4_chunks_baseline | — | 10973590 | 11522270 | new |
| spk7::test_bench::bench_assemble_4_chunks_once | — | 11039724 | 11591711 | new |
| spk7::test_bench::bench_assemble_4_chunks_twice | — | 11104948 | 11660196 | new |
| spk7::test_bench::bench_flood_capped | — | 675055 | 708808 | new |
| spk7::test_bench::bench_flood_capped_baseline | — | 40400 | 42420 | new |
| spk7::test_bench::bench_flood_capped_one_goblin | — | 510173 | 535682 | new |
| spk7::test_bench::bench_flood_capped_unreachable_goblin | — | 503600 | 528780 | new |
| spk7::test_bench::bench_flood_deep_10 | — | 364300 | 382515 | new |
| spk7::test_bench::bench_flood_deep_15 | — | 496560 | 521388 | new |
| spk7::test_bench::bench_flood_deep_20 | — | 628820 | 660261 | new |
| spk7::test_bench::bench_flood_deep_baseline | — | 40400 | 42420 | new |
| spk7::test_bench::bench_flood_deep_unlimited | — | 2447677 | 2570061 | new |
| spk7::test_bench::bench_generate_baseline | — | 52128 | 54735 | new |
| spk7::test_bench::bench_generate_cave_copy | — | 451156 | 473714 | new |
| spk7::test_bench::bench_generate_cave_open | — | 489738 | 514225 | new |
| spk7::test_bench::bench_generate_forest_copy | — | 442880 | 465024 | new |
| spk7::test_bench::bench_generate_forest_open | — | 481462 | 505536 | new |
| spk7::test_bench::bench_generate_meadow_copy | — | 454688 | 477423 | new |
| spk7::test_bench::bench_generate_meadow_open | — | 499590 | 524570 | new |
| spk7::test_bench::bench_generate_ruin_copy | — | 442480 | 464604 | new |
| spk7::test_bench::bench_generate_ruin_open | — | 484222 | 508434 | new |
| spk7::test_bench::bench_line_of_sight | — | 23436 | 24608 | new |
| spk7::test_bench::bench_line_of_sight_baseline | — | 13720 | 14406 | new |
| spk7::test_bench::bench_move_goblin_across | — | 20616 | 21647 | new |
| spk7::test_bench::bench_move_goblin_baseline | — | 14890 | 15635 | new |
| spk7::test_bench::bench_tick_baseline | — | 11039620 | 11591601 | new |
| spk7::test_bench::bench_tick_full | — | 12496049 | 13120852 | new |
| spk7::test_bench::bench_tick_goblins | — | 12190357 | 12799875 | new |
| spk7::test_chunk::test_generate_biome_shares | — | 57984542 | 60883770 | new |
| spk7::test_chunk::test_generate_open_border_and_copy | — | 609264104 | 639727310 | new |
| spk7::test_chunk::test_keep_component_matches_oracle_both_parities | — | 76585976 | 80415275 | new |
| spk7::test_chunk::test_smooth_matches_oracle_both_parities | — | 661568850 | 694647293 | new |
| spk7::test_contract::test_act_deferred_pending_setup_baseline | — | 27866246 | 29259559 | new |
| spk7::test_contract::test_act_deferred_shift_setup_baseline | — | 22286062 | 23400366 | new |
| spk7::test_contract::test_act_deferred_worst_case_move | — | 20252031 | 21264633 | new |
| spk7::test_contract::test_act_deferred_worst_case_move_pending | — | 31723351 | 33309519 | new |
| spk7::test_contract::test_act_deferred_worst_case_shift | — | 23815307 | 25006073 | new |
| spk7::test_contract::test_act_deferred_worst_case_wait | — | 19753353 | 20741021 | new |
| spk7::test_contract::test_act_deferred_writes_back_when_the_window_moves | — | 53060056 | 55713059 | new |
| spk7::test_contract::test_act_every_variant_moves_the_goblins | — | 165626492 | 173907817 | new |
| spk7::test_contract::test_act_refuses_a_blocked_tile | — | 17514180 | 18389889 | new |
| spk7::test_contract::test_act_setup_baseline | — | 16569022 | 17397474 | new |
| spk7::test_contract::test_act_shift_moves_the_goblins_and_writes_back | — | 47075502 | 49429278 | new |
| spk7::test_contract::test_act_shift_setup_baseline | — | 19614638 | 20595370 | new |
| spk7::test_contract::test_act_standin_setup_baseline | — | 1695830 | 1780622 | new |
| spk7::test_contract::test_act_standin_worst_case_move | — | 3284013 | 3448214 | new |
| spk7::test_contract::test_act_standin_worst_case_wait | — | 3218627 | 3379559 | new |
| spk7::test_contract::test_act_stored_setup_baseline | — | 18208706 | 19119142 | new |
| spk7::test_contract::test_act_stored_worst_case_move | — | 20191473 | 21201047 | new |
| spk7::test_contract::test_act_stored_worst_case_wait | — | 20184813 | 21194054 | new |
| spk7::test_contract::test_act_worst_case_move | — | 18375589 | 19294369 | new |
| spk7::test_contract::test_act_worst_case_shift | — | 21720185 | 22806195 | new |
| spk7::test_contract::test_act_worst_case_wait | — | 18310203 | 19225714 | new |
| spk7::test_contract::test_reveal_baseline_around | — | 8391085 | 8810640 | new |
| spk7::test_contract::test_reveal_baseline_known | — | 10516013 | 11041814 | new |
| spk7::test_contract::test_reveal_baseline_open | — | 739180 | 776139 | new |
| spk7::test_contract::test_reveal_one_known_cave | — | 11834790 | 12426530 | new |
| spk7::test_contract::test_reveal_one_known_forest | — | 11560916 | 12138962 | new |
| spk7::test_contract::test_reveal_one_known_meadow | — | 11655770 | 12238559 | new |
| spk7::test_contract::test_reveal_one_known_ruin | — | 11782362 | 12371481 | new |
| spk7::test_contract::test_reveal_one_open_cave | — | 2367153 | 2485511 | new |
| spk7::test_contract::test_reveal_one_open_forest | — | 2338661 | 2455595 | new |
| spk7::test_contract::test_reveal_one_open_meadow | — | 2334463 | 2451187 | new |
| spk7::test_contract::test_reveal_one_open_ruin | — | 2366687 | 2485022 | new |
| spk7::test_contract::test_reveal_refuses_a_known_chunk | — | 10987557 | 11536935 | new |
| spk7::test_contract::test_reveal_refuses_four_chunks | — | 929500 | 975975 | new |
| spk7::test_contract::test_reveal_seams_cave | — | 36501214 | 38326275 | new |
| spk7::test_contract::test_reveal_seams_forest | — | 35877630 | 37671512 | new |
| spk7::test_contract::test_reveal_seams_meadow | — | 36090258 | 37894771 | new |
| spk7::test_contract::test_reveal_seams_ruin | — | 36406900 | 38227245 | new |
| spk7::test_contract::test_reveal_three_around_cave | — | 11777452 | 12366325 | new |
| spk7::test_contract::test_reveal_three_around_forest | — | 11547270 | 12124634 | new |
| spk7::test_contract::test_reveal_three_around_meadow | — | 11649234 | 12231696 | new |
| spk7::test_contract::test_reveal_three_around_ruin | — | 11734504 | 12321230 | new |
| spk7::test_contract::test_reveal_three_open_cave | — | 4350549 | 4568077 | new |
| spk7::test_contract::test_reveal_three_open_forest | — | 4259513 | 4472489 | new |
| spk7::test_contract::test_reveal_three_open_meadow | — | 4279521 | 4493498 | new |
| spk7::test_contract::test_reveal_three_open_ruin | — | 4352077 | 4569681 | new |
| spk7::test_contract::test_window_view_is_layers | — | 18374576 | 19293305 | new |
| spk7::test_flood::test_flood_capped_worst_case_matches_python | — | 59863167 | 62856326 | new |
| spk7::test_flood::test_flood_deep_boards_every_limit | — | 341479049 | 358553002 | new |
| spk7::test_flood::test_flood_random_boards_both_parities | — | 573137408 | 601794279 | new |
| spk7::test_flood::test_flood_shared_vectors | — | 9260741 | 9723779 | new |
| spk7::test_micro::micro_get | — | 568950 | 597398 | new |
| spk7::test_micro::micro_loop_baseline | — | 151990 | 159590 | new |
| spk7::test_micro::micro_pow | — | 278520 | 292446 | new |
| spk7::test_sight::test_line_of_sight_beyond_range | — | 15520 | 16296 | new |
| spk7::test_sight::test_line_of_sight_rows_12_to_14 | — | 1240844708 | 1302886944 | new |
| spk7::test_sight::test_line_of_sight_rows_1_to_4 | — | 1724682419 | 1810916540 | new |
| spk7::test_sight::test_line_of_sight_rows_5_to_8 | — | 2391128707 | 2510685143 | new |
| spk7::test_sight::test_line_of_sight_rows_9_to_11 | — | 1627040592 | 1708392622 | new |
| spk7::test_sight::test_line_of_sight_values | — | 45911 | 48207 | new |
| spk7::test_tick::test_move_across_chunks | — | 32342 | 33960 | new |
| spk7::test_tick::test_move_outside_the_window_chunks | — | 15520 | 16296 | new |
| spk7::test_tick::test_move_within_a_chunk | — | 23386 | 24556 | new |
| spk7::test_tick::test_worst_case_tick_in_memory | — | 12625103 | 13256359 | new |
| spk7::test_window::test_assemble_matches_oracle_2_chunks | — | 130863290 | 137406455 | new |
| spk7::test_window::test_assemble_matches_oracle_4_chunks_east | — | 1212788860 | 1273428303 | new |
| spk7::test_window::test_assemble_matches_oracle_4_chunks_west | — | 1212747390 | 1273384760 | new |
| spk7::test_window::test_assemble_refuses_missing_chunks | — | 131852 | 138445 | new |
| spk7::test_window::test_assemble_refuses_odd_origin | — | 67228 | 70590 | new |

## Acceptance criteria
- **AC-1:** met.
  - The assembly equals the oracle on every overlap case (`dx` 0 to 14 × `dy` 0 to 14, 2 and 4 chunks) and on both row parities of the adventurer: `test_window::test_assemble_matches_oracle_2_chunks`, `…_4_chunks_east`, `…_4_chunks_west`.
  - An odd origin is refused: `test_assemble_refuses_odd_origin`.
  - `assemble_window` has no loop at all: see `src/window.cairo`.
- **AC-2:** met. `test_sight::test_line_of_sight_rows_{1_to_4,5_to_8,9_to_11,12_to_14}` check every ordered pair of interior tiles within 6 (14,708) three ways: the table against a plain rounding, `between_mask(a, b) == between_mask(b, a)`, and `line_of_sight` against the mask on a terrain.
- **AC-3:** met.
  - Each of the 96 tests carries `#[available_gas(l2_gas: ceil(1.05 × measured))]`, confirmed by `gas_budgets.py --check`.
  - The worst case named in the brief is `test_contract::test_act_worst_case_{wait,move}`: 4 chunks, 2 layers each, 8 awake goblins, a winding board, the flood at 15 layers, 8 steps with 5 crossing a chunk boundary, then the writes.
- **AC-4:** met. `spikes/SPK-7/devnet-output-{1,2,3}.txt` hold the receipts of the worst-case tick with and without a stored window, side by side in `devnet-summary.md` and in §2.2 of the research file.
- **AC-5:** met.
  - The reveal of 1 chunk and of 3 chunks is measured for each of the 4 biomes, with and without known neighbours: `test_contract::test_reveal_*` and the node receipts.
  - The most expensive biome is cave, at 5,839,680 L2 gas for 3 chunks.
- **AC-6:** met. The research file gives the verdict on R-12 in §3 and the gas targets for L-M1 in §5.

## Deviations from the brief
- **Two tick variants beyond the brief:**
  - B′, the stored window as the working copy, with its occupancy written back to the chunks only when it moves. B as briefed (chunks kept in sync) was worse than A in every case, so B′ is the one stored design that can win: it does, on ticks where the adventurer stands still (−680,000).
  - S, SPK-2's stand-in, so that "SPK-2 measures the tick on an assembled window; you measure the rest" adds up by a measured difference (A − S) rather than by an estimate.
- **Item 7, the fallback, is not built.** Its condition is met: the worst case exceeds ADR-0001's threshold, as SPK-2 and SPK-1 already found. But the fallback cannot lower the worst case:
  - a 13 × 14 window still overlaps 4 chunks;
  - the flood stays on the two-limb path with the same cap;
  - the assembly would lose its single shift.
  The research file (§4) says what the assembly becomes.
- **Line of sight holds pairs up to 6 apart** (the ranged range, and sight). Beyond that it refuses; a general line is not measured.
- **The spike's own choices in generation**, to be confirmed by ENG-05 and the library:
  - corners are always wall;
  - each opening is joined to a spine by a straight line;
  - the component of the centre is kept;
  - 1 or 2 openings per drawn side;
  - biome parameters chosen by `tune.py`: every biome is inside design/18's range on average over 32 words.
- **Budgets are in `spikes/SPK-7/BUDGETS.md` and `GAS.md`, not `docs/BUDGETS.md`:**
  - `docs/BUDGETS.md` is the `contracts/` workspace's file and is outside my allowlist; `gas_budgets.py` keeps spikes out of it unless run with `--workspace` and `--budgets`.
  - The tool needs a workspace manifest and strips only the `<pkg>_integrationtest::` prefix. My tests are one crate (`tests/lib.cairo`, named `spk7_tests`), so I fed it a copy of the run with the prefix renamed, through a throwaway manifest outside git.
- **Budgets were set with SPK-2's `set_budgets.py`, run read-only from this folder.** It is not copied.

## Escalations
- **The window at a location's border (design question, not settled):** an adventurer within 7 columns or 8 rows of the location's edge gives the window an origin below 0. ADR-0006 §4 and D-120 do not say whether the window is clamped (then the adventurer is off-centre, and sight may reach the ring) or whether locations keep a margin of void chunks. The spike keeps its fixtures away from borders. Documents read: ADR-0006 §4, D-120, docs/needs/hexmap.md (N-3).
- **Chunk corners (design question, not settled):** corner tiles are the only tiles that touch a diagonal chunk. ADR-0006 § Joining chunks speaks only of shared edges, so the spike keeps corners as wall. Documents read: ADR-0006 §2, docs/needs/hexmap.md points 1 and D-22.
- **No shared file needs a change.** FND-04 will write the figures into the ADRs and `docs/BUDGETS.md`.

## Open questions
- **ENG-07:**
  - Assemble the window only when a goblin is awake: a move without goblins needs one terrain read.
  - In a queue, read the chunks once per transaction and write their occupancy once at the end. This is not measured, and it is where most of A − S would go.
  - Whether fights are long enough to pay for B′: it saves 680,000 per stationary tick and costs up to 1,768,000 when it writes back. This depends on the reopened queue in fights (route (e) of the Sepolia verdict).
  - How to select the ≤ 8 awake goblins among more in the window (by chunk).
- **ENG-05:**
  - The generation choices above.
  - A drawn side costs more than a copied one: the worst reveal is the one with no known neighbour.
  - The revealed set in one felt holds 15 × 15 chunks.
- **LIB-03 / LIB-05:** the targets of §5. Three findings:
  - the automaton with margins must combine its diagonal planes by OR (a sum carries: the oracle found it);
  - `Dilation`'s public fields already carry the parity flag, which `Layout::new` cannot;
  - measured unit costs are 4,170 per bit test, 1,265 per table lookup and 1,520 per loop iteration.
- **SPK-2's worst tick plus A − S is an estimate** of the game's worst tick on chunked maps: about 5.92M L2 gas. It should be measured once ENG-07 exists, and on Sepolia with the MVP's account.

## Fix loop 1

The `[GPT-6-Astra]` audit of #50 was FAIL, with two majors and two minors. It confirmed A − S as a sound controlled comparison, every budget, the oracles and the receipts.

The fixes are in three new commits on the same branch, with no force-push:
- `5c99c33`: finding 1;
- `c9f8ab9`: findings 3 and 4, with the reruns;
- `a60cb8f`: the research note.

Everything a fix touched was rerun through the lock: the snforge suite, the budgets and the three node runs. The committed outputs and budgets are the new ones.

**This section supersedes the figures quoted in Summary, Commands run and Cost above** (the Cost table has been replaced by the new run's). The changed figures:

| Figure | Before | Now |
|---|---:|---:|
| A − S | 760,000 | **720,000** |
| S, waiting / moving | 2,200,960 / 2,280,960 | 2,240,960 / 2,320,960 |
| B, moving | 3,320,960 | 3,360,960 |
| B′, waiting / costliest move | 2,280,960 / 4,808,960 | 2,320,960 / 4,848,960 |
| Worst reveal (3 chunks, cave) | 5,839,680 | 5,919,680 (the random words differ) |
| Flood per layer | 25,612 | 26,452 |
| Capped worst flood | 618,475 | 634,655 |
| Assembly (one call against two) | 65,734 / 35,370 | **65,224** for 4 chunks and for 2 |
| Tests | 96 | 106 |

### Finding 1 (major): Python/Cairo parity of the flood with no target

**Decision.** The flood stops before a layer when no target is left to reach, so with no target it computes no layer beyond the start. This rule now holds in both `model.py` and `src/flood.cairo`. Why:
- the flood only serves the goblins' steps (design/02: "gives every goblin its next step");
- D-127's 15 layers are a ceiling on that work, not a quota of layers;
- the tick already skips the flood when no goblin is awake (`tick.cairo`).

Python used to stop after the layer that emptied the targets, and never ran with an empty list; Cairo checked only after a hit. Both now test the targets in the loop condition. With targets, the layers are unchanged.

**Tests that needed the old behaviour.** The benchmarks of pure layers (`bench_flood_capped_unreachable_goblin`, formerly `…_no_goblins`) and the deep board of the even parity now pass one unreachable target: tile 0, a ring corner next to no interior tile.

**Shared vectors.** `spikes/SPK-7/vectors.py` checks 12 vectors on the model against the layer counts written in the script: empty, unreachable and real targets; caps 15 and unlimited; both adventurer rows. It writes the same inputs and results (layers, distances, the union of the layers) to `src/vectors.cairo`, and `test_flood::test_flood_shared_vectors` checks them in Cairo.

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
wrote .../spikes/SPK-7/src/vectors.cairo: 12 vectors, every layer count as expected

$ cd spikes/SPK-7 && snforge test > snforge-test-output.txt
[PASS] spk7_tests::test_flood::test_flood_shared_vectors (l1_gas: ~0, l1_data_gas: ~0, l2_gas: ~9260741)
Tests: 106 passed, 0 failed, 0 ignored, 0 filtered out
```

**Effect.** The test in the loop condition costs about 3 % in memory: per layer 25,612 → 26,452, capped worst case 618,475 → 634,655. On the node, S moved up by one of the meter's 40,000 steps while A did not, so **A − S is now 720,000**. The research note carries the new figures.

### Finding 2 (major): the fallback

Recorded in the research note (§4) and here as a **scope amendment by the orchestrator: the fallback is not measured**. D-133 takes the cost through batches, and a 13 × 14 window still overlaps 4 chunks.

Its cost conclusions are labelled **analytical**: the "same per-layer cost" and "about 14 times the assembly" are extrapolations.

The **R-12 verdict is now conditional** (§3): "partly realised, not a blocker", on two conditions:
- that the fallback is not needed (analysis only);
- that D-133's batches carry the cost per transaction.

If either fails, R-12 must be judged again with measured figures. No command applies.

### Finding 3 (minor): B′'s costliest case

A move that changes the window's chunks is now measured, beside A on the same destination:
- the board sits at origin (37, 60), and the adventurer steps North-West from (44, 66) to (44, 67);
- the origin goes from (37, 58) to (37, 60), and the chunk row from 3–4 to 4–5.

For B′, all 4 old chunks hold a move the window knows and the chunk does not (`fixtures::SHIFT_GHOSTS`), so writing the window back changes all 4, and the new set is then read from storage. The new pieces:
- fixtures `chunks_at`, `SHIFT_*`, and the setup entrypoint `setup_shift`;
- tests `test_act_{worst_case,deferred_worst_case}_shift`, their setup baselines, and `test_act_shift_moves_the_goblins_and_writes_back`;
- two new rows in `devnet.py`.

```
$ scripts/with-node.sh python3 spikes/SPK-7/devnet.py > spikes/SPK-7/devnet-output-{1,2,3}.txt
  55 transactions per run, 55 SUCCEEDED (x3)
  {"check": "goblins after the two chunk-row ticks are equal", "ok": true}   (x3)
  {"check": "goblins after the nine ticks are equal", "ok": true}            (x3)
$ python3 spikes/SPK-7/summarize.py spikes/SPK-7/devnet-output-*.txt > spikes/SPK-7/devnet-summary.md
| worst-case tick, A (assembled), adventurer moves into another chunk row | 2,880,960 | 448 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, chunk row changes), adventurer moves | 3,320,960 | 768 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, re-centred), adventurer moves | 4,848,960 | 768 |
| B′ − A, the move changes the chunk row, same destination (4 chunks written back) | 440,000 |
```

**The chunk-row move costs 3,320,960, less than 4,848,960.** The same-chunks move with 4 layers written back from zero stays **B′'s maximum among the cases measured**, and is qualified as such. A chunk-row move writing 4 layers from zero was not measured, and the gap between the two cases is not isolated.

In snforge the chunk-row calls cost A 2,105,547 and B′ 1,529,245, so the two meters disagree on the sign; the receipt counts.

### Finding 4 (minor): "the rest is storage"

**Removed.** A − S (720,000 on the node) is now stated as the chunked map's **net** overhead:
- the reads, the writes and the work in memory together;
- not split into computation and storage;
- the in-memory assembly plus the chunk updates cost 305,692 (`bench_tick_full` − `bench_tick_goblins`).

The same rewording is in §6, question 5 (how much a batch saves is not measured).

**While re-measuring, the assembly's baseline difference proved unstable.** The 2-chunk figure went from 35,370 to 66,034 with `assemble_window` unchanged. The assembly is now measured as one call against two identical calls (`bench_assemble_{2,4}_chunks_{once,twice}`): **65,224, for 2 chunks and for 4 alike**. Why the 2-chunk path is charged like the 4-chunk one is not isolated.

```
bench_assemble_4_chunks_twice 11104948   bench_assemble_4_chunks_once 11039724   -> 65,224
bench_assemble_2_chunks_twice 11108618   bench_assemble_2_chunks_once 11043394   -> 65,224
```

### Budgets and CI

The budgets were reset to ceil(1.05 × measured) from the new run, and `BUDGETS.md` and `GAS.md` were regenerated.

```
$ python3 ../SPK-2/set_budgets.py snforge-test-output.txt      (from spikes/SPK-7)
set: 106 missing: []
$ python3 scripts/gas_budgets.py --check --workspace .with-node/gasws --budgets spikes/SPK-7/BUDGETS.md --from-output .with-node/spk7-output.txt
gas check: 106 tests, every budget is ceil(1.05 x measured) or lower, 2 files current
$ scarb fmt --check   -> clean
$ gh pr checks 50 --watch --interval 30        (head a60cb8f)
cairo (spikes/SPK-7)  pass  37s   (log: Tests: 106 passed, 0 failed, 0 ignored, 0 filtered out)
... every job pass
```
