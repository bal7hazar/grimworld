# [Opus 5.5] SPK-15 — The tick's cost levers, measured before CBT-05

## Summary

The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/234. CI is green on every check: `cairo (spikes/SPK-15)` ran its 96 tests (log: `Tests: 96 passed`), `cairo (contracts)` passed in 3m8s, `tooling` passed, and `indexer-node` was skipped.

**What exists now that did not before:** `spikes/SPK-15/`, a Scarb package that depends on `grimworld_logic` by path (main's code at `d4b5cdc`). It contains:
- the copied functions:
  - CBT-04's conditions from `feat/cbt-04-conditions` at `b5f4069`, in `src/cbt04.cairo`;
  - CBT-03a's hit from `feat/cbt-03a-hit` at `36bf2ba`, in `src/cbt03a.cairo`;
- the levers:
  - lever 1 in `src/words.cairo`;
  - lever 2 in `src/application.cairo`;
  - lever 3 in `src/executor.cairo`, an estimate of CBT-05's executor;
  - the one-pass selection (lever 4) in `src/words.cairo`;
- 96 tests:
  - 61 pairs, measured equal in two clean builds;
  - checks that each alternative gives the results of the code it replaces;
- the scripts that derive the pairs, the table and the budgets;
- `README.md`, which holds the full write-up, the table and the recommendation.

**Findings:**

1. **The brief's basis is 6,255,632 when re-measured, not 6,510,212.**
   - CBT-04's 108,100 for an application on the member includes 17,100 for reading the member's own kit (`infliction()`).
   - The 16 applications on the member come from goblins, which have no kit.
   - CBT-04's line is therefore 2,114,010 (−254,580).
2. **Two terms are outside the 6.51 M:**
   - ENG-07's perception (step 0, every tick) costs 4,657,300 over 100 candidates.
   - CBT-05's executor, written naively, would add about 6.24 M a worst tick (E). Most of it is gathering a hit's inputs (245,596 a hit, decoding the member's 4 effect slots) and writing actors back (114,670 an awake goblin).
3. **The engineering levers (no rule changes), per worst tick inside a batch of 10:**

   | Lever | What it does | Saves |
   |---|---|---:|
   | L1 | the frozen goblins kept as words | 744,153 |
   | L2 | an application written in place, split by condition | 773,960 |
   | L3 | the executor: the member's guard read once a tick, a carrier's goblins written in one rebuild, the entries decoded once a call with the sheets | 2,832,504 (E) |
   | L4 | perception's one-pass selection, with AI states kept at load | 1,091,010 |

   - The brief's basis: 6.26 M (4.26×) → **4.74 M (3.22×)**.
   - Everything counted (the executor, perception, the map): 18.26 M (12.43×) → **12.82 M (8.72×)**.
4. **The design levers (rule changes) are priced, not decided:**
   - awake 8 → 6 or 4;
   - one application on the member a goblin carrier;
   - 3 targets a carrier;
   - window 4 → 2 chunks and flood 15 → 10 layers;
   - 20 ticks a batch.

   All together they bring the worst tick to about **7.99 M (5.44×), E**. No measured combination reaches 1.47 M.
5. **On the representative tick the engineering levers save almost nothing.** It has no hit, no application, and its 8 goblins are all awake; L1 even costs 3,255 there. The design levers save 0.13 M or 0.26 M (D1: 6 or 4 awake), 0.15 M (D3) and 0.21 M (D4) a tick.
6. **S1 should be judged on a representative fight tick with the rules, which nobody has measured yet** (escalation 1).

## Files changed

- `spikes/SPK-15/Scarb.toml`, `Scarb.lock`, `.gitignore`: the package (`grimworld_logic` by path); `target/` and `.snfoundry_cache/` ignored.
- `spikes/SPK-15/src/lib.cairo`: the modules.
- `spikes/SPK-15/src/cbt04.cairo`: CBT-04's `Infliction`, `apply` and predicates, copied with a header naming the files and `b5f4069`.
- `spikes/SPK-15/src/cbt03a.cairo`: CBT-03a's `types/hit.cairo` above its tests, and `Arc`, copied with a header naming `36bf2ba`.
- `spikes/SPK-15/src/words.cairo`: lever 1 (`Lazy`, `lazy_load`, `lazy_store`, `thaw`, `set_frozen`, `awake`, `awake_single`) and `SelectionTrait` (`scan`, `single`).
- `spikes/SPK-15/src/application.cairo`: lever 2 (`apply_in_place`, `apply_split`, `knock`, `apply_hot`, `Afflictions`).
- `spikes/SPK-15/src/executor.cairo`: lever 3, an estimate of CBT-05 (`GatherTrait`, `Guard`, `OutcomeTrait`, `ExecutorTrait`).
- `spikes/SPK-15/tests/lib.cairo`, `fixtures.cairo`: the test crate; main's `test_tick.cairo` fixtures copied at `d4b5cdc`, and CBT-04's `opaque`.
- `spikes/SPK-15/tests/bench_application.cairo`, `bench_words.cairo`, `bench_executor.cairo`, `bench_design.cairo`: the pairs and the checks.
- `spikes/SPK-15/summarize.py`: every pair's difference, per run.
- `spikes/SPK-15/levers.py`: the table, from the pairs and the cited figures.
- `spikes/SPK-15/set_budgets.py`: SPK-14's, for this package.
- `spikes/SPK-15/snforge-test-output-1.txt`, `-2.txt`, `pairs.txt`, `levers-output.md`: the two clean runs and what was derived from them.
- `spikes/SPK-15/README.md`: the write-up.

## Commands run

```
$ git fetch origin feat/cbt-04-conditions feat/cbt-03a-hit      # b5f4069, 36bf2ba; never checked out
$ scripts/lock.sh scarb --manifest-path spikes/SPK-15/Scarb.toml build
    Finished `dev` profile target(s) in 4 seconds
$ (cd spikes/SPK-15) scarb clean && snforge test > snforge-test-output-1.txt     # clean build 1
Tests: 96 passed, 0 failed, 0 ignored, 0 filtered out
$ scarb clean && snforge test > snforge-test-output-2.txt                       # clean build 2
Tests: 96 passed, 0 failed, 0 ignored, 0 filtered out
$ python3 summarize.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt
61 pairs, every one "same" in both runs
$ python3 set_budgets.py snforge-test-output-1.txt snforge-test-output-2.txt
budgets set: 96; measured without a declaration found: []
$ scarb fmt && snforge test
Tests: 96 passed, 0 failed, 0 ignored, 0 filtered out          # under their budgets
$ python3 levers.py snforge-test-output-1.txt snforge-test-output-2.txt > levers-output.md
$ python3 scripts/gas_budgets.py --report --workspace spikes/SPK-15 --budgets spikes/SPK-15/BUDGETS.md \
    --from-output spikes/SPK-15/snforge-test-output-1.txt
KeyError: 'workspace'        # the tool reads a Scarb workspace; the spike is one package (Deviations 2)
$ gh pr create --base main ...                                   # #234
$ gh pr checks 234 --watch --interval 30
every check pass (indexer-node skipping); cairo (spikes/SPK-15) 18s, Tests: 96 passed
```

Main's figures that the spike reproduces: CBT-04's 108,100 and 76,820, CBT-02d's load and store (10,570,470) and its representative tick (636,067), each to the unit. Two figures land within 0.13 % of CBT-02d's: the costliest tick at 8 awake (1,477,717 against 1,475,797) and the selection formed from none (4,597,710 against 4,596,270).

## Cost

### The measured pairs (L2 gas; D, both clean runs equal)

| Lever | Measure | Main / as it is | Alternative |
|---|---|---:|---:|
| L1 | Load and store, CBT-02b's costliest words (100 goblins, 8 awake), a call | 10,570,470 | 3,128,940 |
| L1 | Load and store, the representative words (8, all awake) | 1,292,290 | 1,324,840 |
| L1 | A frozen goblin touched by a hook (read, written back) | 674,470 | 477,720 |
| L1 | Load and store at 100 / 60 / 40 goblins | 10,570,650 / 6,713,050 / 4,784,250 | 3,129,120 / 2,521,120 / 2,217,120 |
| L4 | Perception over 100 candidates (worst of formed, kept) | 4,657,300 | 3,566,290 |
| L4 | The selection alone (8 scans / one pass) | 2,562,050 | 1,071,130 |
| L4 | The content's index, a call | 557,210 | — |
| L2 | Member: CBT-04's pair / the source given / in place / knock / conditions 1–4 / 1–3 | 108,100 / 91,000 | 57,180 / 55,280 / 31,940 / 24,200 |
| L2 | Member's parts: the kit / duration / `inflict` / `interrupt` / a call | 19,020 / 13,250 / 37,820 / 37,900 / 3,600 | — |
| L2 | Member gathered: an add / a flush | — | 22,100 / 54,130 |
| L2 | Goblin: CBT-04 / in place / gathered flush | 76,820 | 47,900 / 60,090 |
| L2 | Goblin's parts: `inflict` / `interrupt` / a call | 33,490 / 29,150 / 2,600 | — |
| L3 | Round trip: member / awake goblin / frozen goblin | 32,930 / 114,670 / 674,470 | — |
| L3 | A hit's inputs gathered / with the guard given / the guard | 245,596 | 23,716 / 223,390 |
| L3 | A goblin's hit end to end / guarded | 475,576 | 254,796 |
| L3 | A bomb on 7: each written / flushed | 2,479,950 | 2,031,320 |
| L3 | A `CONDITION` read and written: member / goblin; an entry decoded | 125,010 / 191,770; 30,920 | — |
| D1 | The costliest tick at 8 / 6 / 4 / 0 awake | 1,477,717 | 1,090,071 / 751,785 / 207,133 |
| D1 | The representative tick at 8 / 6 / 4 | 636,067 | 508,201 / 380,335 |

### The table (per tick, worst inside a batch of 10; S1 = 300 ticks at $0.000881 a M)

| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |
|---|---|---:|---:|---:|---:|---|---|---|
| CBT-04's line re-measured | measure | −254,580 | 0 | 0 | −76.4 M ($0.067) | none | none | CBT-04 |
| **L1** frozen goblins as words | engineering | **−744,153** | +3,255 | +1.0 M (+$0.001) | −223.2 M ($0.197) | load, store, perception over words; the index kept | `load`'s contract with perception | ENG-07 |
| **L2** applications in place, by condition | engineering | **−773,960** | 0 | 0 | −232.2 M ($0.205) | one inlined function a condition kind | none | CBT-04's fix loop or CBT-05 |
| **L3** the executor's guard, flush, entries with the sheets | engineering | **−2,832,504** (E) | 0 | 0 | −849.8 M ($0.749) | CBT-05's design | `Sheets` gains the entries | CBT-05 |
| **L4** perception, one pass | engineering | **−1,091,010** | not measured | — | −327.3 M ($0.288) | the selection; AI states (with L1) | none | ENG-07 |
| D1 awake 8 → 6 | design | −1,310,246 (E) | −127,866 | −38.4 M ($0.034) | −393.1 M ($0.346) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D1 awake 8 → 4 | design | −2,571,132 (E) | −255,732 | −76.7 M ($0.068) | −771.3 M ($0.680) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D2 one application on the member a goblin carrier | design | −442,240 (E) | 0 | 0 | −132.7 M ($0.117) | a check | none | CBT-05; design/19 §5.14, §8 |
| D2′ a carrier's targets 7 → 3 | design | −1,034,204 (E) | 0 | 0 | −310.3 M ($0.273) | content | none | CNT-01; design/19 §9, FX-35 |
| D3 window 4 → 2 chunks, flood 15 → 10 layers | design | −390,467 (E) | −145,847 (E) | −43.8 M ($0.039) | −117.1 M ($0.103) | constants | `MAX_GOBLINS` | ENG-07, LIB-05; design/18 |
| D4 20 ticks a batch, not 10 | design | −611,678 (E) | −212,473 (E) | −63.7 M ($0.056) | −183.5 M ($0.162) | a constant | the batch's 40 M | ENG-07; design/02 |

How each E figure is made is in `spikes/SPK-15/README.md` (*How the E figures are made*), and `levers.py` computes them all from the pairs.

### The recommendation

- **The project manager's engineering set is all four, in this order of gain:**
  1. **L3**, in CBT-05's brief: without it, CBT-05 alone adds about 6.24 M a worst tick.
  2. **L4**, in ENG-07.
  3. **L2**, in CBT-04's fix loop or CBT-05, together with CBT-04's line corrected (a measure, not a change).
  4. **L1**, in ENG-07, because it changes `load`'s contract with perception.

  Together they take the brief's basis to 4.74 M (3.22×) and everything counted to 12.82 M (8.72×).
- **What remains for the owner's design levers.** After the engineering levers, the worst tick is about 11.35 M above its target, and the design levers close about 4.83 M of that (to about 7.99 M, E).
  - The worst tick will not reach 1.47 M.
  - It still matters for the batch's 40 M: at 12.8 M a tick, a worst batch holds 3 ticks.
  - S1's $0.50 rests on the average tick (escalation 1), with SPK-12 beside it.

### Gas table

`scripts/gas_budgets.py --report` cannot read the spike (Deviations 2). The table below is built from `snforge-test-output-1.txt` in the same format (the second run is equal). Every test is new, and every budget is ceil(1.05 × measured). No budget is raised. Nothing under `contracts/` changed, so `docs/BUDGETS.md` and the packages' `GAS.md` files are untouched.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| spk15_tests::bench_application::test_alternatives_match_cbt04_goblin | — | 10573280 | 11101944 | new |
| spk15_tests::bench_application::test_alternatives_match_cbt04_member | — | 327049890 | 343402385 | new |
| spk15_tests::bench_application::test_goblin_base | — | 591660 | 621243 | new |
| spk15_tests::bench_application::test_member_base | — | 4974080 | 5222784 | new |
| spk15_tests::bench_application::test_pair_goblin_cbt04_apply | — | 668480 | 701904 | new |
| spk15_tests::bench_application::test_pair_goblin_gather_flush | — | 651750 | 684338 | new |
| spk15_tests::bench_application::test_pair_goblin_in_place | — | 639560 | 671538 | new |
| spk15_tests::bench_application::test_pair_goblin_part_call | — | 594260 | 623973 | new |
| spk15_tests::bench_application::test_pair_goblin_part_inflict | — | 625150 | 656408 | new |
| spk15_tests::bench_application::test_pair_goblin_part_interrupt | — | 620810 | 651851 | new |
| spk15_tests::bench_application::test_pair_member_cbt04_apply | — | 5082180 | 5336289 | new |
| spk15_tests::bench_application::test_pair_member_cbt04_apply_given | — | 5065080 | 5318334 | new |
| spk15_tests::bench_application::test_pair_member_gather_add | — | 4996180 | 5245989 | new |
| spk15_tests::bench_application::test_pair_member_gather_flush | — | 5028210 | 5279621 | new |
| spk15_tests::bench_application::test_pair_member_hot | — | 4998280 | 5248194 | new |
| spk15_tests::bench_application::test_pair_member_in_place | — | 5031260 | 5282823 | new |
| spk15_tests::bench_application::test_pair_member_knock | — | 5029360 | 5280828 | new |
| spk15_tests::bench_application::test_pair_member_part_call | — | 4977680 | 5226564 | new |
| spk15_tests::bench_application::test_pair_member_part_duration | — | 4987330 | 5236697 | new |
| spk15_tests::bench_application::test_pair_member_part_inflict | — | 5011900 | 5262495 | new |
| spk15_tests::bench_application::test_pair_member_part_infliction | — | 4993100 | 5242755 | new |
| spk15_tests::bench_application::test_pair_member_part_interrupt | — | 5011980 | 5262579 | new |
| spk15_tests::bench_application::test_pair_member_split | — | 5006020 | 5256321 | new |
| spk15_tests::bench_design::test_design_awake_0_fixture | — | 13753590 | 14441270 | new |
| spk15_tests::bench_design::test_design_awake_4_fixture | — | 15568180 | 16346589 | new |
| spk15_tests::bench_design::test_design_awake_6_fixture | — | 16474280 | 17297994 | new |
| spk15_tests::bench_design::test_design_awake_8_fixture | — | 17380380 | 18249399 | new |
| spk15_tests::bench_design::test_design_representative_4_fixture | — | 6096470 | 6401294 | new |
| spk15_tests::bench_design::test_design_representative_6_fixture | — | 6664250 | 6997463 | new |
| spk15_tests::bench_design::test_design_representative_8_fixture | — | 7232030 | 7593632 | new |
| spk15_tests::bench_design::test_design_window_100_fixture | — | 11265380 | 11828649 | new |
| spk15_tests::bench_design::test_design_window_40_fixture | — | 10695380 | 11230149 | new |
| spk15_tests::bench_design::test_design_window_60_fixture | — | 10885380 | 11429649 | new |
| spk15_tests::bench_design::test_pair_design_awake_0 | — | 13960723 | 14658760 | new |
| spk15_tests::bench_design::test_pair_design_awake_4 | — | 16319965 | 17135964 | new |
| spk15_tests::bench_design::test_pair_design_awake_6 | — | 17564351 | 18442569 | new |
| spk15_tests::bench_design::test_pair_design_awake_8 | — | 18858097 | 19801002 | new |
| spk15_tests::bench_design::test_pair_design_representative_4 | — | 6476805 | 6800646 | new |
| spk15_tests::bench_design::test_pair_design_representative_6 | — | 7172451 | 7531074 | new |
| spk15_tests::bench_design::test_pair_design_representative_8 | — | 7868097 | 8261502 | new |
| spk15_tests::bench_design::test_pair_design_window_100_lazy | — | 14394500 | 15114225 | new |
| spk15_tests::bench_design::test_pair_design_window_100_main | — | 21836030 | 22927832 | new |
| spk15_tests::bench_design::test_pair_design_window_40_lazy | — | 12912500 | 13558125 | new |
| spk15_tests::bench_design::test_pair_design_window_40_main | — | 15479630 | 16253612 | new |
| spk15_tests::bench_design::test_pair_design_window_60_lazy | — | 13406500 | 14076825 | new |
| spk15_tests::bench_design::test_pair_design_window_60_main | — | 17598430 | 18478352 | new |
| spk15_tests::bench_executor::test_executor_bombs_agree | — | 32988570 | 34637999 | new |
| spk15_tests::bench_executor::test_executor_entry_fixture | — | 13496800 | 14171640 | new |
| spk15_tests::bench_executor::test_executor_fixture | — | 13453500 | 14126175 | new |
| spk15_tests::bench_executor::test_executor_gather_fixture | — | 13504600 | 14179830 | new |
| spk15_tests::bench_executor::test_executor_goblin_hit_lands | — | 13927716 | 14624102 | new |
| spk15_tests::bench_executor::test_executor_guarded_agrees | — | 29393422 | 30863094 | new |
| spk15_tests::bench_executor::test_executor_guarded_fixture | — | 13741590 | 14428670 | new |
| spk15_tests::bench_executor::test_executor_hit_guarded_fixture | — | 13679760 | 14363748 | new |
| spk15_tests::bench_executor::test_pair_executor_awake_round_trip | — | 13568170 | 14246579 | new |
| spk15_tests::bench_executor::test_pair_executor_bomb_each | — | 15933450 | 16730123 | new |
| spk15_tests::bench_executor::test_pair_executor_bomb_flushed | — | 15484820 | 16259061 | new |
| spk15_tests::bench_executor::test_pair_executor_condition_goblin | — | 13645270 | 14327534 | new |
| spk15_tests::bench_executor::test_pair_executor_condition_member | — | 13578510 | 14257436 | new |
| spk15_tests::bench_executor::test_pair_executor_entry | — | 13527720 | 14204106 | new |
| spk15_tests::bench_executor::test_pair_executor_frozen_round_trip | — | 14127970 | 14834369 | new |
| spk15_tests::bench_executor::test_pair_executor_gather | — | 13750196 | 14437706 | new |
| spk15_tests::bench_executor::test_pair_executor_gather_guarded | — | 13765306 | 14453572 | new |
| spk15_tests::bench_executor::test_pair_executor_gather_resolve | — | 13786836 | 14476178 | new |
| spk15_tests::bench_executor::test_pair_executor_goblin_hit | — | 13929076 | 14625530 | new |
| spk15_tests::bench_executor::test_pair_executor_goblin_hit_guarded | — | 13934556 | 14631284 | new |
| spk15_tests::bench_executor::test_pair_executor_guard | — | 13727990 | 14414390 | new |
| spk15_tests::bench_executor::test_pair_executor_member_round_trip | — | 13486430 | 14160752 | new |
| spk15_tests::bench_words::test_awake_lazy_fixture | — | 2338500 | 2455425 | new |
| spk15_tests::bench_words::test_awake_lazy_kept_fixture | — | 2856250 | 2999063 | new |
| spk15_tests::bench_words::test_awake_lazy_matches_main | — | 56791080 | 59630634 | new |
| spk15_tests::bench_words::test_awake_main_fixture | — | 8105240 | 8510502 | new |
| spk15_tests::bench_words::test_awake_main_kept_fixture | — | 8166600 | 8574930 | new |
| spk15_tests::bench_words::test_awake_single_matches_main | — | 38063150 | 39966308 | new |
| spk15_tests::bench_words::test_index_fixture | — | 531200 | 557760 | new |
| spk15_tests::bench_words::test_pair_awake_lazy_formed | — | 7734350 | 8121068 | new |
| spk15_tests::bench_words::test_pair_awake_lazy_kept | — | 7918460 | 8314383 | new |
| spk15_tests::bench_words::test_pair_awake_main_formed | — | 12702950 | 13338098 | new |
| spk15_tests::bench_words::test_pair_awake_main_kept | — | 12823900 | 13465095 | new |
| spk15_tests::bench_words::test_pair_awake_single_formed | — | 5904790 | 6200030 | new |
| spk15_tests::bench_words::test_pair_awake_single_kept | — | 6119140 | 6425097 | new |
| spk15_tests::bench_words::test_pair_index | — | 1088410 | 1142831 | new |
| spk15_tests::bench_words::test_pair_selection_scan | — | 2978060 | 3126963 | new |
| spk15_tests::bench_words::test_pair_selection_single | — | 1487140 | 1561497 | new |
| spk15_tests::bench_words::test_pair_touch_lazy | — | 8388880 | 8808324 | new |
| spk15_tests::bench_words::test_pair_touch_main | — | 14284320 | 14998536 | new |
| spk15_tests::bench_words::test_pair_words_bound_lazy | — | 14307060 | 15022413 | new |
| spk15_tests::bench_words::test_pair_words_bound_main | — | 21748590 | 22836020 | new |
| spk15_tests::bench_words::test_pair_words_representative_lazy | — | 16235840 | 17047632 | new |
| spk15_tests::bench_words::test_pair_words_representative_main | — | 16203290 | 17013455 | new |
| spk15_tests::bench_words::test_selection_agrees | — | 14442190 | 15164300 | new |
| spk15_tests::bench_words::test_selection_fixture | — | 416010 | 436811 | new |
| spk15_tests::bench_words::test_touch_lazy_fixture | — | 7911160 | 8306718 | new |
| spk15_tests::bench_words::test_touch_main_fixture | — | 13609850 | 14290343 | new |
| spk15_tests::bench_words::test_words_bound_fixture | — | 11178120 | 11737026 | new |
| spk15_tests::bench_words::test_words_representative_fixture | — | 14911000 | 15656550 | new |

## Acceptance criteria

- **AC-1: met.** Each engineering lever is measured as test pairs in two clean builds that agree on all 61 pairs (`pairs.txt`). Each lever has its saving on the worst tick, the representative tick and S1 (the table).
  - L3 is an estimate: its parts are measured on CBT-03a's and CBT-04's functions, and its assembly into CBT-05 is E.
  - L4's saving on the representative tick is not measured (perception over 8 candidates).
- **AC-2: met.** Each design lever is priced the same way, with the rule and the document it changes (design/02, D-133, D-141; design/19 §5.14, §8, §9, FX-35; design/18; design/02's batch weight).
  - D1's tick terms and its representative figures are measured.
  - The rest is E, from measured unit costs and LIB-05's cited ones.
- **AC-3: met.** The table, with engineering and design levers in separate rows and kinds, and the recommendation are in `spikes/SPK-15/README.md` and above.
- **AC-4: met.** `src/cbt04.cairo` names the files at `b5f4069`, `src/cbt03a.cairo` the files at `36bf2ba`, and `tests/fixtures.cairo` main's `test_tick.cairo` at `d4b5cdc`. `git diff --stat origin/main...HEAD` touches only `spikes/SPK-15/`.
- **AC-5: met.** CI is green on #234. The 96 budgets are ceil(1.05 × measured), from the higher of two equal runs (`set_budgets.py`). `snforge test` passes under them.

## Deviations from the brief

1. **CBT-04's member figure is corrected, not only taken apart.** The brief's 108,100 is CBT-04's pair, which reads the member's own kit before `apply`. On the member, the applications come from goblins, which have no kit, so the line is 2,114,010. I report this as a measure, apart from the levers.
2. **`gas_budgets.py --report` cannot run on the spike.** It reads `[workspace].members`, and a spike is one package. Its brief notes that "spikes stay out unless run with `--workspace`", but the tool then fails with `KeyError: 'workspace'`. The gas table above is built from the snforge output in the tool's format.
3. **Four terms are outside the brief's 6.51 M basis**, and I added them to show the whole tick:
   - perception (D);
   - the executor (E);
   - the map library (C);
   - the D4 transaction-cap observation.
4. **`scarb fmt` reformatted the copied bodies** in `cbt04.cairo` and `cbt03a.cairo` (line wrapping only). Their headers say so.
5. **History on the branch.** The first commits included the spike's `target/` build folder by mistake. Commit `0ce7d76` removes it and adds `.gitignore`, so the squash diff into main does not contain it. Two scratch files are left untracked at the worktree root, `pr-body.tmp.md` and `gas-table.tmp.md`, because my profile refused `rm`. Both are uncommitted and can be deleted.

## Escalations

1. **S1 has no representative tick with the rules.** CBT-02's representative tick (`Idle`) has no hit, no application and no frozen goblin, so the engineering levers measure ~0 on it. S1's real saving lies between the "representative × 300" and "worst × 300" columns. ENG-07 (or a CBT-05 follow-up) should define and measure a representative fight tick (its hits, applications and perception) to price S1 and R-2.
2. **Perception every tick is uncounted.** At 100 candidates it costs 4,657,300, or 3,566,290 with L4 and L1. It belongs in ENG-01 §9.2's per-tick line once ENG-07 fixes how often step 0 selects and over how many candidates. Selecting over the window's goblins only, or only when a goblin moved, would be a design question for design/18.
3. **CBT-04's ENG-01 row** should read 16 × 91,000 for the member's applications, plus one kit read a member carrier (2,114,010 in all). That edit is CBT-04's, outside my allowlist.
4. **CBT-05's brief** should carry L3's three measures (the guard once a tick, one rebuild per carrier, entries with the sheets) and the next two, which are not measured:
   - a lighter awake goblin value: the 24-felt rebuild costs 114,670 a write;
   - step 2's writes kept pending.
5. **The batch's 40 M against the worst tick:** at 12.8 M a tick, a worst batch of 10 is far above 40 M. ENG-07's batch weight must be set against the worst tick, not only the average.

## Open questions

- May L1's AI-state array (perception's keys) live in the call only, or should ENG-07's perception pass the eligibility in with the distances? The latter would remove the decoding at load, about 4,780 a goblin, which `lazy_load` now pays for all 100.
- Is "every application on the member a knock-down" a bound the content can reach? If BAL-01 or CNT-01 limits knock-downs a carrier, L2's bound falls from 55,280 toward 31,940 an application.

## Fix loop 1

**Input.** The Claude-side cost and method audit (`[Opus 5.5]`, D-170) of #234 at `92779d3`: FAIL, one major, four minors, five notes (`/home/claude/orchestrator/audits/SPK-15-cost-claude-opus.md`). The orchestrator confirmed the major. `origin/main` had not moved (`d4b5cdc`), so there was nothing to merge.

The fix is in commits `0dda365` (code, tests, two clean runs, budgets) and `9517865` (README). CI is green on `9517865`: every check passes (`cairo (spikes/SPK-15)` 25s, `cairo (contracts)` 2m54s, `tooling` 1m49s), and `indexer-node` is skipped. **This section supersedes the figures and the recommendation above wherever they differ.**

### What changed, finding by finding

1. **Major: L1 and L4 separated.**
   - Main's `World` keeps its goblins private, so `src/perception.cairo` holds the same three fields (`Decoded`). It copies main's `TickTrait::awake` verbatim, using main's own `TickTrait::key` and `place`.
   - `awake_single` is that copy with the one-pass selection.
   - `tests/bench_perception.cairo` measures 5 variants in 4 states, each as a pair against its representation's fixture:
     - the variants: main, the copy, L4 alone, L1 alone, L1 and L4 together;
     - the states: formed, kept at the end, kept at the start with distances rising (ENG-01's maximum), and replaced (8 out, 8 in).
   - The copy measures 3,300 below main in every state (0.07 %).
   - `test_perc_agree_*` checks, in all four states, that every variant picks main's set, values and flags, and that the words variants store every goblin's words unchanged.

   | Representation | formed | kept_end | kept_start | replaced | Worst |
   |---|---:|---:|---:|---:|---:|
   | main | 4,596,450 | 4,656,050 | 4,663,690 | 4,655,170 | **4,663,690** |
   | decoded_scan (the copy) | 4,593,150 | 4,652,750 | 4,660,390 | 4,651,870 | **4,660,390** |
   | decoded_single (**L4 alone**) | 3,101,190 | 3,160,790 | 2,582,390 | 3,159,910 | **3,160,790** |
   | lazy_scan (**L1 alone**) | 5,397,410 | 5,063,770 | 4,972,970 | 5,528,370 | **5,528,370** |
   | lazy_single (**L1 and L4**) | 3,567,850 | 3,264,450 | 2,587,610 | 3,729,050 | **3,729,050** |

   - **L4 alone: −1,502,900. It needs no L1 and changes no frozen interface.**
   - **L1 alone:** load and store −744,153; perception **+864,680**; the hooks' writes −1,180,500. That is −1,059,973 in all, or **+120,527 (a cost) without the hooks**.
   - **L1 given L4:** −1,356,393, or −175,893 without the hooks.
   - **L1 and L4 together:** −2,859,293.
   - The audit's E figures (−5,603 for L1 alone, −1,490,920 for L4 alone) leave out the hooks and the replaced state. The measured figures above include both.
2. **Minor: the batch.**
   - The per-call part is paid once a batch: 12,233,560 with L1, 19,675,090 without.
   - ENG-01 §10.1's batch writes are priced at about 4,436,950 (E): its worst branch, 47,336,950, less 10 ticks at 4.29 M each.
   - **A 40 M batch holds 0 worst ticks as it stands, 1 after L1–L4, and 2 with the design levers** (37.9 M). The audit found ≤ 2 after L1–L4, before the hooks and the batch's writes.
   - D4 is out of every worst-tick combination; its table row reads "average case only".
3. **Minor: the guard.**
   - `Guard` now keeps each slot's charges. A blocked hit spends a charge in the member's effect word (`OutcomeTrait::on_member`), and `GuardTrait::spend` updates the guard.
   - L3 now reads: "the guard once a tick, updated whenever the executor holds, spends or ends an effect".
   - `test_executor_guard_two_hits`: A is blocked and spends the one charge, B lands. The world is the same as with the guard read at each hit, and a stale guard would block B.
   - The spend path costs every hit +66,080, because Sierra charges the costliest path. A hit end to end is now 541,656 (guarded: 322,816); the naive executor is 6,768,568 and the levered one 3,956,304 (**−2,812,264, E**).
4. **Minor: L4's worst state.** The four states above are measured on every variant, and the worst of each is used. Main's figure is the larger of its measured worst and ENG-01's: 4,663,690 against 4,663,510.
5. **Minor: the hooks.** Six writes to frozen goblins a worst tick are counted in "everything counted": 4,046,820 on main, 2,866,320 with L1. Six is ENG-01 §9.2's count for an action, taken as a one-tick action at the worst.
6. **Notes 6 to 10:**
   - **6.** The stale 3,264,270 is gone; the README's table is now `levers-output.md`'s.
   - **7.** D2′ is measured as the 7-target bomb less the 3-target bomb: **273,945 a target**. The fixed part, 113,705, stays. D2′ is −1,095,780.
   - **8.** The goblin's alternatives are now checked at the values 1, 20 and 0, alive and dead. The one-pass selection's flags, its replaced case and its stored words are checked (`test_perc_agree_*`).
   - **9.** `cbt04.cairo`'s header names exactly what was copied. Of the goblin's trait, only `apply`, `takes_critical` and `can_defend` were copied, not `holds`, `can_act` or `move_ticks`.
   - **10.** D1's interaction is stated: with 4 awake, a 7-target bomb reaches 3 frozen goblins, about +611,325 with L1 (E). D2′ removes the interaction.

### The corrected table (per worst tick inside a batch of 10, priced on everything counted)

| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |
|---|---|---:|---:|---:|---:|---|---|---|
| CBT-04's line re-measured | measure | −254,580 | 0 | 0 | −76.4 M (−$0.067) | none | none | CBT-04 |
| **L1 alone**: frozen goblins kept as words, perception's 8 scans over words | engineering | −1,059,973 | +3,255 | +1.0 M (+$0.001) | −318.0 M (−$0.280) | `load`, `store`, perception over words; the index kept | **`load`'s contract with perception** | ENG-07 |
| **L2** an application in place, by condition | engineering | −773,960 | 0 | 0 | −232.2 M (−$0.205) | one inlined function a condition kind | none | CBT-04's fix loop or CBT-05 |
| **L3** the executor: the guard once a tick and updated at every effect write, a carrier's goblins flushed once, entries with the sheets | engineering | −2,812,264 (E) | 0 | 0 | −843.7 M (−$0.743) | CBT-05's design | the call's content (`Sheets` gains the entries) | CBT-05 |
| **L4 alone**: one-pass selection on main's goblins | engineering | −1,502,900 | not measured | — | −450.9 M (−$0.397) | the selection | none | ENG-07 |
| L1 given L4 | engineering | −1,356,393 | +3,255 | +1.0 M (+$0.001) | −406.9 M (−$0.358) | as L1 | as L1 | ENG-07 |
| L1 and L4 together | engineering | −2,859,293 | not measured | — | −857.8 M (−$0.756) | both | as L1 | ENG-07 |
| D1 awake 8 → 6 | design | −1,446,286 (E) | −127,866 | −38.4 M (−$0.034) | −433.9 M (−$0.382) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D1 awake 8 → 4 | design | −2,843,212 (E) | −255,732 | −76.7 M (−$0.068) | −853.0 M (−$0.751) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D2 one application on the member a goblin carrier | design | −442,240 (E) | 0 | 0 | −132.7 M (−$0.117) | a check in the executor | none | CBT-05; design/19 §5.14, §8 |
| D2′ a carrier's targets 7 → 3 | design | −1,095,780 | 0 | 0 | −328.7 M (−$0.290) | content | none | CNT-01; design/19 §9, FX-35 |
| D3 window 4 → 2 chunks, flood 15 → 10 layers | design | −390,467 (E) | −145,847 (E) | −43.8 M (−$0.039) | −117.1 M (−$0.103) | the window's constants | `MAX_GOBLINS` | ENG-07, LIB-05; design/18 |
| D4 20 ticks a batch (average case only) | design | not applicable | −212,473 (E) | −63.7 M (−$0.056) | — | a constant | the batch's 40 M | ENG-07; design/02 |

### Everything counted and the recommendation, corrected

| Per worst tick | As it stands | With L1–L4 |
|---|---:|---:|
| The brief's basis (CBT-04's line re-measured) | 6,255,632 (4.26×) | 4,737,519 (3.22×) |
| CBT-05's executor (E) | 6,768,568 | 3,956,304 |
| ENG-07's perception (worst of four states) | 4,663,690 | 3,729,050 |
| The map library (C) | 1,106,666 | 1,106,666 |
| The hooks' 6 writes to frozen goblins | 4,046,820 | 2,866,320 |
| **Everything counted** | **22,841,376 (15.54×)** | **16,395,859 (11.16×)** |

- With L2, L3 and L4 only (no frozen interface): 17,752,252 (12.08×).
- With the design levers on top (4 awake, one application a carrier, 3 targets, the smaller window and flood; D4 excluded): **11,845,280 (8.06×), E**.

**Recommendation, corrected.** The order is by gain on everything counted:
1. **L3** in CBT-05's brief: −2.81 M (E). It changes the call's content, because `Sheets` gains the entries.
2. **L4** in ENG-07: −1.50 M. No frozen interface changes.
3. **L2** in CBT-04's fix loop or CBT-05: −0.77 M. No frozen interface changes. CBT-04's line is corrected too (−0.25 M, a measure).
4. **L1** is **the only lever that changes a frozen interface** (`load`'s contract with perception).
   - Once L4 is in, it saves −1.36 M, but −1.18 M of that is the 6 hooks' writes to frozen goblins. Without those writes it saves −0.18 M.
   - Decide it once ENG-07 knows how many frozen goblins its hooks write in a tick.

The design levers close about 4.6 M of the 14.9 M left above the target. The worst tick does not reach 1.47 M, and a worst batch of 40 M holds 1 tick after the engineering levers, 2 with the design levers. S1 still rests on a representative fight tick, which ENG-07 has yet to define (escalation 1 above).

### Commands run

```
$ git fetch origin main                                   # d4b5cdc, not moved: nothing to merge
$ scarb --manifest-path spikes/SPK-15/Scarb.toml build
    Finished `dev` profile target(s) in 4 seconds
$ (spikes/SPK-15) snforge test                            # first run of the new tests
[FAIL] test_alternatives_match_cbt04_goblin (its old budget, with more cases)
[FAIL] test_executor_guard_two_hits ('u8_sub Overflow': the stale-guard check applied the block; it now only resolves)
$ snforge test
Tests: 122 passed, 0 failed
$ scarb clean && snforge test > snforge-test-output-1.txt; scarb clean && snforge test > snforge-test-output-2.txt
Tests: 122 passed, 0 failed (both)
$ python3 summarize.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt
76 pairs, every one "same" in both runs
$ python3 set_budgets.py snforge-test-output-1.txt snforge-test-output-2.txt && scarb fmt && snforge test
budgets set: 122; measured without a declaration found: []
Tests: 122 passed, 0 failed
$ python3 levers.py snforge-test-output-1.txt snforge-test-output-2.txt > levers-output.md
$ git push; gh pr checks 234 --watch --interval 30
9517865: every check pass (indexer-node skipping)
```

### Gas table (fix loop 1)

Before is `92779d3`'s measured run, and after is this loop's (both clean runs equal). Every budget is ceil(1.05 × measured). Only the rows that changed are listed; the other 73 tests measure as before.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| spk15_tests::bench_application::test_alternatives_match_cbt04_goblin | 10573280 | 25101430 | 26356502 | raised: 3 values × alive and dead (note 8); +137.4 % |
| spk15_tests::bench_executor::test_executor_goblin_hit_lands | 13927716 | 13993796 | 14693486 | raised: a block spends its charge (finding 3); +0.5 % |
| spk15_tests::bench_executor::test_executor_guard_two_hits | — | 30962950 | 32511098 | new |
| spk15_tests::bench_executor::test_executor_guarded_agrees | 29393422 | 29531942 | 31008540 | raised: the same; +0.5 % |
| spk15_tests::bench_executor::test_executor_guarded_fixture | 13741590 | 13747810 | 14435201 | raised: the guard keeps each slot's charges; +0.0 % |
| spk15_tests::bench_executor::test_executor_hit_guarded_fixture | 13679760 | 13684980 | 14369229 | raised: the same; +0.0 % |
| spk15_tests::bench_executor::test_pair_executor_bomb_flushed_3 | — | 14389040 | 15108492 | new |
| spk15_tests::bench_executor::test_pair_executor_gather | 13750196 | 13753916 | 14441612 | raised: the guard's charges; +0.0 % |
| spk15_tests::bench_executor::test_pair_executor_gather_guarded | 13765306 | 13772026 | 14460628 | raised: the same; +0.0 % |
| spk15_tests::bench_executor::test_pair_executor_gather_resolve | 13786836 | 13790556 | 14480084 | raised: the same; +0.0 % |
| spk15_tests::bench_executor::test_pair_executor_goblin_hit | 13929076 | 13995156 | 14694914 | raised: a block spends its charge; +0.5 % |
| spk15_tests::bench_executor::test_pair_executor_goblin_hit_guarded | 13934556 | 14007796 | 14708186 | raised: the same, and the guard's update; +0.5 % |
| spk15_tests::bench_executor::test_pair_executor_guard | 13727990 | 13732710 | 14419346 | raised: the guard's charges; +0.0 % |
| spk15_tests::bench_perception::test_pair_perc_decoded_scan_formed | — | 12806870 | 13447214 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_scan_kept_end | — | 12901320 | 13546386 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_scan_kept_start | — | 12961240 | 13609302 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_scan_replaced | — | 12961820 | 13609911 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_single_formed | — | 11314910 | 11880656 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_single_kept_end | — | 11409360 | 11979828 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_single_kept_start | — | 10883240 | 11427402 | new |
| spk15_tests::bench_perception::test_pair_perc_decoded_single_replaced | — | 11469860 | 12043353 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_scan_formed | — | 7850170 | 8242679 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_scan_kept_end | — | 8007780 | 8408169 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_scan_kept_start | — | 7969260 | 8367723 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_scan_replaced | — | 8533760 | 8960448 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_single_formed | — | 6020610 | 6321641 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_single_kept_end | — | 6208460 | 6518883 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_single_kept_start | — | 5583900 | 5863095 | new |
| spk15_tests::bench_perception::test_pair_perc_lazy_single_replaced | — | 6734440 | 7071162 | new |
| spk15_tests::bench_perception::test_pair_perc_main_formed | — | 12817340 | 13458207 | new |
| spk15_tests::bench_perception::test_pair_perc_main_kept_end | — | 12911790 | 13557380 | new |
| spk15_tests::bench_perception::test_pair_perc_main_kept_start | — | 12971710 | 13620296 | new |
| spk15_tests::bench_perception::test_pair_perc_main_replaced | — | 12972290 | 13620905 | new |
| spk15_tests::bench_perception::test_perc_agree_formed | — | 65609450 | 68889923 | new |
| spk15_tests::bench_perception::test_perc_agree_kept_end | — | 66253910 | 69566606 | new |
| spk15_tests::bench_perception::test_perc_agree_kept_start | — | 65207130 | 68467487 | new |
| spk15_tests::bench_perception::test_perc_agree_replaced | — | 67548750 | 70926188 | new |
| spk15_tests::bench_perception::test_perc_decoded_formed_fixture | — | 8213720 | 8624406 | new |
| spk15_tests::bench_perception::test_perc_decoded_kept_end_fixture | — | 8248570 | 8660999 | new |
| spk15_tests::bench_perception::test_perc_decoded_kept_start_fixture | — | 8300850 | 8715893 | new |
| spk15_tests::bench_perception::test_perc_decoded_replaced_fixture | — | 8309950 | 8725448 | new |
| spk15_tests::bench_perception::test_perc_lazy_formed_fixture | — | 2452760 | 2575398 | new |
| spk15_tests::bench_perception::test_perc_lazy_kept_end_fixture | — | 2944010 | 3091211 | new |
| spk15_tests::bench_perception::test_perc_lazy_kept_start_fixture | — | 2996290 | 3146105 | new |
| spk15_tests::bench_perception::test_perc_lazy_replaced_fixture | — | 3005390 | 3155660 | new |
| spk15_tests::bench_perception::test_perc_main_formed_fixture | — | 8220890 | 8631935 | new |
| spk15_tests::bench_perception::test_perc_main_kept_end_fixture | — | 8255740 | 8668527 | new |
| spk15_tests::bench_perception::test_perc_main_kept_start_fixture | — | 8308020 | 8723421 | new |
| spk15_tests::bench_perception::test_perc_main_replaced_fixture | — | 8317120 | 8732976 | new |
| spk15_tests::bench_words::test_awake_lazy_fixture | 2338500 | — | — | removed (moved to bench_perception) |
| spk15_tests::bench_words::test_awake_lazy_kept_fixture | 2856250 | — | — | removed (moved) |
| spk15_tests::bench_words::test_awake_lazy_matches_main | 56791080 | — | — | removed (now `test_perc_agree_*`) |
| spk15_tests::bench_words::test_awake_main_fixture | 8105240 | — | — | removed (moved) |
| spk15_tests::bench_words::test_awake_main_kept_fixture | 8166600 | — | — | removed (moved) |
| spk15_tests::bench_words::test_awake_single_matches_main | 38063150 | — | — | removed (now `test_perc_agree_*`) |
| spk15_tests::bench_words::test_pair_awake_lazy_formed | 7734350 | — | — | removed (moved) |
| spk15_tests::bench_words::test_pair_awake_lazy_kept | 7918460 | — | — | removed (moved) |
| spk15_tests::bench_words::test_pair_awake_main_formed | 12702950 | — | — | removed (moved) |
| spk15_tests::bench_words::test_pair_awake_main_kept | 12823900 | — | — | removed (moved) |
| spk15_tests::bench_words::test_pair_awake_single_formed | 5904790 | — | — | removed (moved) |
| spk15_tests::bench_words::test_pair_awake_single_kept | 6119140 | — | — | removed (moved) |

### Files changed in fix loop 1

- `spikes/SPK-15/src/perception.cairo` (new): `Decoded`, main's `TickTrait::awake` copied verbatim (`awake_scan`), and `awake_single`.
- `spikes/SPK-15/src/executor.cairo`: `Guard` keeps each slot's charges; `GuardTrait::spend`; a blocked hit spends its charge (`on_member`); `goblin_hit_guarded` takes `ref guard` and updates it.
- `spikes/SPK-15/src/cbt04.cairo`: the header names exactly what was copied.
- `spikes/SPK-15/src/lib.cairo`: `perception`.
- `spikes/SPK-15/tests/bench_perception.cairo` (new): 36 tests.
- `spikes/SPK-15/tests/bench_words.cairo`: the old perception tests moved out.
- `spikes/SPK-15/tests/bench_executor.cairo`: the 3-target bomb, the two-hit test, and the guarded tests with `ref guard`.
- `spikes/SPK-15/tests/bench_application.cairo`: the goblin's equivalence at three values, alive and dead.
- `spikes/SPK-15/tests/lib.cairo`: `bench_perception`.
- `spikes/SPK-15/summarize.py`: the perception pairs' bases.
- `spikes/SPK-15/levers.py`: rewritten. It prices each lever on everything counted (L1 and L4 alone, together and each given the other), perception's worst of four states, the hooks, the batch against 40 M, D2′ from the 3-target bomb, and D4 at the average only.
- `spikes/SPK-15/snforge-test-output-1.txt`, `-2.txt`, `pairs.txt`, `levers-output.md`: regenerated.
- `spikes/SPK-15/README.md`: the measured sections, the table, everything counted, the recommendation, *Not measured* and *History*.

### Deviations (fix loop 1)

1. **Raised budgets in a spike.** Eleven tests measure more than before:
   - the goblin's equivalence test, because it has more cases;
   - ten executor tests, because a blocked hit now spends its charge (a path Sierra charges every hit) and the guard keeps four charges.

   `set_budgets.py` rewrote their attributes to ceil(1.05 × measured) without a `// gas: raised` line. The spike is outside `gas_budgets.py`'s check, and the reasons are in the gas table above.
2. **Hooks counted at 6 a worst tick.** ENG-01 counts 6 an action. I took the worst tick to be a one-tick action. If a worst tick cannot coincide with an action's 6 frozen writes, use the figures given for L1 without the hooks.
3. **Three scratch files stay untracked**: `pr-body.tmp.md` and `gas-table.tmp.md` at the worktree root, and `spikes/SPK-15/before-run.tmp.txt` (this loop's copy of `92779d3`'s run, for the gas table). My profile refused `rm` (earlier) and `git clean -f` (this loop). None is committed, and all can be deleted.

### Escalations (fix loop 1)

1. **How many frozen goblins can a hook write in one tick?** This decides L1 (−1.36 M with 6, −0.18 M with none) and is ENG-07's to say. CBT-02d's escalation 3 counts 6 an action.
2. **The batch against 40 M.** No worst tick fits a batch of 10. After the engineering levers a 40 M batch holds one worst tick, and two with the design levers (**corrected to one in fix loop 2**). ENG-07's batch weight must be set on the worst tick, or on a cap that the worst tick's content cannot reach.

## Fix loop 2

**Input.** The Claude-side re-audit at `9517865` (`/home/claude/orchestrator/audits/SPK-15-2-cost-claude-opus.md`) confirmed every figure of fix loop 1 to the unit. It still FAILs on one major, which the orchestrator checked and which holds.

**The fix** is in commit `0f4b571` (`levers.py`, `levers-output.md`, `README.md`). No code or test changed, so the figures come from fix loop 1's committed clean runs (`snforge-test-output-1.txt`, `-2.txt`), not re-run. CI is green on `0f4b571`: every check passes (`cairo (spikes/SPK-15)` 18s, `cairo (contracts)` 2m39s, `tooling` 1m45s), and `indexer-node` is skipped. **This section supersedes the batch counts above.**

1. **Major: the batch counts.** L3 decodes the content's entries once a call: 118 × 30,920 = **3,648,560**. `exec_levered` spread them as 364,856 a tick, and the batch loop removed only load and store, the call and the content from the per-tick figure.
   - The entries are now a per-call cost, like the call and the content.
   - D3's per-call saving, 20 goblins fewer in the call (20 × 15,200 = 304,000), now comes off the per-call part.
   - As it stands, the naive executor decodes its entries at each use, so they stay per tick.

   | | Per-call part | A worst tick without it | Worst ticks a 40 M batch holds |
   |---|---:|---:|---:|
   | As it stands | 19,675,090 | 20,873,867 | **0** (1 would cost 44,985,907) |
   | After L1–L4 | 15,882,120 | 14,807,647 | **1** (35,126,717; 2 would cost 49,934,364) |
   | With the design levers | 15,578,120 | 10,287,468 | **1, not 2** (30,302,538; 2 would cost 40,590,006) |

   Totals are with the initialised writes. The per-tick figures of the table and of "everything counted" are unchanged; only the batch's split between per-call and per-tick moved.
2. **Note: L3's frozen-interface cell** (table, README and `levers.py`) now reads "none (`Sheets`, an in-call type, gains the entries)". The recommendation says the same, so table and recommendation agree that **L1 is the only lever that changes a frozen interface**.
3. **Note: the batch's writes, both ways** (E, ENG-01 §10.1, each branch less its 10 ticks at 4.29 M):
   - initialised, **4,436,950** (from 47,336,950);
   - cold, **5,637,162** (from 48,537,162, +1,200,212).

   The counts are computed with both and are **the same either way** (0 / 1 / 1). The totals quoted above are the initialised ones; cold adds 1,200,212 to each.

**The recommendation is otherwise unchanged:** L3, L4, L2, then L1, the only lever that changes a frozen interface. Its last paragraph now reads that a 40 M batch holds 1 worst tick after the engineering levers and still 1 with the design levers, since 2 would cost 40.59 M.

### Commands run

```
$ python3 spikes/SPK-15/levers.py spikes/SPK-15/snforge-test-output-1.txt spikes/SPK-15/snforge-test-output-2.txt > spikes/SPK-15/levers-output.md
- the entries decoded once a call: 118 × 30,920 = 3,648,560 (per-call, with L3)
- the batch's writes (E): initialised 4,436,950, cold 5,637,162
- as it stands: ... initialised **0** (24,112,040; 44,985,907 for 1); cold **0**
- after L1–L4: ... initialised **1** (35,126,717; 49,934,364 for 2); cold **1**
- and the design levers: ... initialised **1** (30,302,538; 40,590,006 for 2); cold **1** (31,502,750; 41,790,218 for 2)
$ git push; gh pr checks 234 --watch --interval 30
0f4b571: every check pass (indexer-node skipping)
```

### Files changed in fix loop 2

- `spikes/SPK-15/levers.py`: the batch section, with the entries and D3's call per-call, and the writes both ways; L3's frozen-interface cell.
- `spikes/SPK-15/levers-output.md`: regenerated.
- `spikes/SPK-15/README.md`: *A worst batch against 40 M*, L3's table row, the recommendation's L3 item and last paragraph, and *History* (fix loop 1's item 2 marked corrected, plus the fix loop 2 entry).

### Gas table (fix loop 2)

No test or budget changed.

### Deviations and escalations (fix loop 2)

- None new. Fix loop 1's escalation 2 now reads one worst tick with the design levers.
- The three untracked scratch files of fix loop 1's deviation 3 are still there, uncommitted: `pr-body.tmp.md`, `gas-table.tmp.md`, `spikes/SPK-15/before-run.tmp.txt`. I did not try to delete them again, because my profile refused it twice.
