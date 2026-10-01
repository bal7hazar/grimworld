# [Opus 5.5] CBT-02d — The tick's remaining levers: hot fields apart, a content index

## Summary

The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/211. CI is green on every check (`cairo (contracts)` 2m6s; `indexer-node` skipping).

**What exists now that did not before:**

- **The awake set apart** (`contracts/logic/src/types/world.cairo`; D-166, D-161's lever (a) in full).
  - `World.goblins` holds every goblin as 23-felt structs. Writing one rebuilt the whole array: about 590,000 L2 gas at 100 goblins, at every executor hook.
  - The steps write only the awake set (≤ 8, fixed for the tick once perception has run, §5.2). Its goblins now live apart:
    - `World.awake` holds their current values;
    - `World.woken` holds their indexes in the array.
  - A write now rebuilds at most 8 goblins. The frozen goblins are never read by the steps.
  - The set is formed when the world is made (`WorldTrait::new`, `WordsTrait::load`) and again only when an awake flag changes (`TickTrait::awake` in step 0, `set_goblin`).
  - The set is put back in its places once, when the call stores the words.
  - Goblins are private to the world: they are read through `goblin(i)` and written through `set_goblin` and `kill`.
- **The content through an index** (`types/tick.cairo`).
  - `ContentTrait::index` builds, once per call:
    - an `Index`: one `Felt252Dict` of positions, keyed by id and kind;
    - `Sheets`: the content's sheets, plus each caste's `Kit` (its 4 skills' positions, its goblins' adrenaline cap, its weapon's tick cost).
  - A load reads each id through the index, at about 2,700 L2 gas wherever the record lies. Before, a lookup scanned its list, up to 38 comparisons, about 82,000 L2 gas.
  - The goblin's load has no loop left: its cap is its kit's.
  - The actors hold their positions (`Goblin.caste_at`; `Member.bar_at`, the bar's 8 positions packed in one `u128`). The pipeline reads at those positions and never scans.
  - `SheetsTrait::skill` and `potion` keep a scan by id, for the executor's rules that receive a carrier's id (`hold`, `put`, a stance).
- **Costs found on the way, each measured.**
  - **The members down.** `is_down` loaded every member after every hook (~16,000 L2 gas a call, about 10 calls a tick). The world now counts the members down with every member write; members are private, read through `member(i)` and written through `set_member`.
  - **A conclusion's write.** When nothing is pending, a conclusion writes its goblin straight into the set (−11,000 a conclusion).
  - **The kit.** A conclusion reads only its caste's kit (−5,400 a conclusion).
  - **The awake selection** walks the frozen runs between the set's indexes.
- **The two deferred findings** (AC-2).
  1. The term tests' measured tick runs rules that record each act (`Acts`). `term_tick` checks that every goblin free in step 2 acted there, at its turn, and that no other did: a free goblin, and one whose lapse or recovery step 1 ended.
  2. The eight-awake limit is refused **where the set is formed**, so no tick can run over a larger set, even one that step 1 would stop on the member's defeat. Tests:
     - the world made of nine awake goblins;
     - the library call's load of nine;
     - perception waking a ninth in step 0 while the member dies at its resolution in step 1;
     - the same tick with eight awake, which stops in step 1.
- **D-167.** The 45 unit tests (fix loop 1: 45, not 44) of the pipeline, the goblin, the member and the content moved into their modules, under `#[cfg(test)] mod tests`:
  - 22 in `types::world`, 7 in `types::tick`, 8 in `models::goblin`, 8 in `models::member`;
  - their shared fixtures are in the test-only module `types::world::fixtures`.
  - `tests/test_tick.cairo` keeps what needs the benchmarks' states, a declared class, or both representations. It keeps its own copy of the fixtures, because the test crate cannot see `cfg(test)` items (checked).
- **The parity check** (AC-1). `test_parity_*` hash (Poseidon) the words the pipeline leaves, the clock, the kills, the defeat, and each hook the rules recorded, over 60 cases:
  - the worked examples and every rule test's scenario;
  - the representative batch, CBT-02's heavy tick, `Busy`'s batch, the load's costliest words, the kills, two members, the awake selection;
  - every branch of step 1 with 1 and 8 goblins, and the mixes.

  The hashes were taken on the old representation before any change (commit 2251f0a). All 60 are equal on the new one.

## Files changed

- `contracts/logic/src/types/world.cairo`: the awake set apart, the members' count down, `Sheets` through the hooks, the checks where the set is formed, the unit tests.
- `contracts/logic/src/types/world/fixtures.cairo` (new, `#[cfg(test)]`): the unit tests' fixtures and the recording rules (`Script`).
- `contracts/logic/src/types/tick.cairo`: `Index`, `Sheets`, `Kit`, `ContentTrait::index`, the scans by id on `Sheets`, the unit tests (the sheets' oracle, the index, the kits).
- `contracts/logic/src/models/goblin.cairo`: `load` through the index, the rules at their positions, the unit tests.
- `contracts/logic/src/models/member.cairo`: `load` through the index, `bar_at` packed, `downs`, the unit tests.
- `contracts/logic/src/models/index.cairo`: `Goblin.caste_at`, `Member.bar_at`.
- `contracts/logic/src/systems/tick.cairo`: the library call loads the sheets.
- `contracts/logic/tests/test_tick.cairo`:
  - the unit tests removed (now in their modules);
  - the benchmarks ported;
  - `Acts` added;
  - 15 more term states and the index tests;
  - the heavy tick and `Busy`'s ticks measured alone;
  - the parity table.
- `contracts/ephemeral/tests/test_tick_words.cairo`: the new `load` and `WorldTrait::new` (*Deviations*).
- `docs/architecture/ENG-01-interfaces.md` §9.2: the tick re-proved.
- `contracts/logic/GAS.md`, `contracts/ephemeral/GAS.md`, `docs/BUDGETS.md`: generated.

## Commands run

```
$ cd contracts/logic && snforge test test_parity_        # on the old code, before any change (2251f0a)
Tests: 5 passed (22 + 8 + 13 + 10 + 7 hashes printed, then pinned)
$ snforge test test_parity_                               # on the new code, after every change
[PASS] test_parity_examples / states / terms_one / terms_eight / terms_mixed
$ snforge test                                            # the logic package
Tests: 445 passed, 0 failed
$ snforge test test_cost_term --max-threads 1             # the printed "gas tick" figures below
Tests: 46 passed, 0 failed
$ cd contracts/ephemeral && snforge test test_tick_words
Tests: 4 passed (after the budgets)
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
Finished `dev` profile target(s) in 27 seconds
$ python3 scripts/gas_budgets.py && python3 scripts/gas_budgets.py --check
gas check: 689 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py
Instances 39.60 %, TickLibrary 29.13 % (23,860 CASM felts; was 24.32 %), Hub 42.83 % (every class ok)
$ git merge origin/main       # CBT-02c and #210; conflicts only in GAS.md and BUDGETS.md, regenerated
$ gh pr checks 211 --watch --interval 30
every check pass (indexer-node skipping); cairo (contracts) pass 2m6s
```

The profiles that guided the changes were scratch tests, not committed:
- the representative steps, old against new code;
- load and store split;
- a dict read against a scan and array rebuilds.

## Cost

### The re-proved bound (AC-3; ENG-01 §9.2)

The measure: every state is built by `term_world` and measured as the tick alone (`get_available_gas` around `TickTrait::tick`, printed "gas tick"). Each test checks the branch taken, the acts, the deaths and the defeat.

**What can vary.** CBT-02b's rules still hold: a function without a loop is charged its costliest path, so a cost varies only with the loops. Since CBT-02d:
- no loop scans the content (`test_cost_index_*`: 853,330 to 853,530 L2 gas for any position);
- the steps read only the awake set, so a tick's cost depends on the set's branches in the set's order, not on the array. The costliest state measures the same at the array's end, start and spread.

Each awake goblin adds work, and one more goblin to each rebuild of the set, so the maximum is at 8. For reference:
- the 1-goblin states measure 170,303 to 258,286;
- none awake measures 126,373 (before: 1,027,653).

**The model at 8 awake goblins.** Against the state with all 8 activating, S = 626,553 (the member concluding bar slot 7 and dying), each position of the set adds:

| A position of the awake set | Adds to S |
|---|---:|
| A conclusion clearing the field | 94,493 (91,653 first in the set) |
| A conclusion into a recovery | 92,870 (90,030 first) |
| The first write step 1 leaves for its end (with that rebuild): a lapse, the later recharge kept or not | 111,093 |
| … a recovery over | 69,783 |
| The first write a later conclusion puts in the set with its own: a lapse | 67,863 |
| … a recovery over | 26,553 |
| Each further write of the same group: a lapse | 55,183 |
| … a recovery over | 13,873 |
| Free, acting in step 2 (the hook records the act) | 4,293 |
| Knocked down; recovering; activating; dead | 400; 300; 0; −20,080 |

The model predicts **all 32 measured 8-goblin states to the unit** (fix loop 1: 32 states, 29 distinct orders; 13 fix the terms, 19 check them, see *Fix loop 1*). They are the 10 `term_eight_*` states, the 7 `term_mix_*` states and 15 new `term_set_*` states:
- conclusions first, in the middle and last in the set;
- 1, 2 and 6 conclusions among activating goblins;
- lapses and recoveries over alone, in pairs, before a conclusion and after the last one.

**Two predictions checked before measuring:**
- a recovery over flushed by a conclusion: predicted 26,553 from the lapse's terms; `term_set_c_r_c6` measures exactly that;
- two lapses flushed with one conclusion: predicted 67,863 + 55,183; `term_set_c_ll_c5` measures exactly that.

**The maximum over every assignment** of the 9 branches to the 8 positions (9⁸ = 43,046,721, enumerated) is 7 conclusions then a lapse:

S + 91,653 + 6 × 94,493 + 111,093 = **1,396,257, reached** (`test_cost_term_mix_clear_lapse`).

Nothing is charged beyond the measure. Before, the bound charged the member's scan as a full list, 65,100.

**The terms, before and after:**

| Term | CBT-02b | CBT-02d |
|---|---:|---:|
| The base, none awake (the member concluding and dying) | 1,027,653 | 126,373 |
| Step 3's rebuild (100 goblins → the awake set) | 1,333,870 | inside S (8 goblins) |
| The end of step 1's rebuild | 603,540 | in the first write left for the end: it costs 55,910 more than each further one |
| A conclusion clearing the field, over an activating goblin (8 in the set) | 749,423 (789,383 − 39,960) | 94,493 |
| The costliest state | 8,685,267 | **1,396,257** |
| The member's scan, charged | 65,100 | 0 (read at its position) |
| **The tick's upper bound** | **8,750,367** | **1,396,257** |

### Against the expedition's target, before and after (AC-3)

| Per tick inside a batch of 10 | Representative: CBT-02b → CBT-02d | Upper bound: CBT-02b → CBT-02d |
|---|---:|---:|
| The pipeline | 656,274 → **640,706** (one tick alone: 651,867 → 636,797) | 8,750,367 → **1,396,257** |
| Load, store and the call, / 10 | 264,636 → **184,105** | 5,868,687 → **1,389,505** |
| **Through one library call** | 920,910 → **824,811** | 14,619,054 → **2,785,762** |
| The content (reads and sheets, unchanged), / 10 | 240,840 | 578,004 |
| **The tick's share** | 1,161,750 (79.1 %) → **1,065,651 (72.5 %)** | 15,197,058 (10.3 ×) → **3,363,766 (2.29 ×)** |
| Left for the executor, AI, flood, window, writes and floor | 307,685 → **403,784** | −13,727,623 → **−1,894,331** |

The rows:
- **Load and store, once per call:** ≤ 55,363,190 → **≤ 10,570,470**, measured on their costliest paths (`test_cost_load_bound` − its fixture). Every list is at its bound, and each caste's kit raises its cap at each skill (the load fixture now gives every caste increasing costs). Nothing is charged.
- **The call:** 3,323,680 → 3,324,580, every list at its bound (100 kills in and out).
- **Each further member** (M-3): 157,443 to a tick (was 172,603 + 65,100), 293,440 to load and store (was 1,236,800), 17,980 to the call.
- **CBT-02's heavy tick** (`worst_state`, measured alone): 1,361,673, under the bound.
- **`Busy`'s batch**, each tick measured alone, alternates 1,365,007 (8 conclusions) and 1,462,087 (8 acts).
  - In the act ticks each of `Busy`'s hooks writes its goblin: the AI's stand-in's own work, which ENG-07 prices.
  - With the lot's `Idle` hooks every tick is under the pipeline's bound.
  - Before, the batch was measured by fixture subtraction, which also counted the batch's loop and checks.
- **The awake selection** over 100 candidates (ENG-07's step 0): 4,264,890 → **4,630,240 (+8.6 %)**. It now forms the set apart in the pass that writes the flags, and reads the replaced set at its current values.

**The overrun is reported, not accepted** (D-161). The upper bound's make-up per tick:
- **the tick, 1.40 M.** S = 0.63 M: the base with the member (0.13 M) and 8 awake goblins' steps. The 7 conclusions and the lapse add 0.77 M.
- **load and store, 1.06 M.**
  - Building the index is ~0.56 M a call.
  - Decoding and re-encoding the goblins no step touches is ~0.85 M a tick: a goblin's load ~71,000 (of which the words' decoding ~41,000), its store ~21,000; scratch measures.
- **the call, 0.33 M.**
- **the content, 0.58 M.**

### Gas table

**Raised budgets.** Five, each with `// gas: raised, <reason>` above it:

| Test | Before | After | Why |
|---|---:|---:|---|
| `test_cost_load_member_potions` | 5,227,100 | 5,738,570 | its fixture builds the content's index first; the member's load itself falls |
| `test_cost_load_member_potions_fixture` | 4,927,590 | 5,482,100 | the same |
| `test_cost_load_member_skills_fixture` | 4,928,290 | 5,482,800 | the same |
| `test_tick_words_member` (ephemeral) | 1,230,510 | 1,318,560 | the load reads through the index, which the test builds first |
| `test_tick_words_goblin` (ephemeral) | 486,360 | 584,620 | the same |

**Kept budgets.** About 40 tests whose measure rose slightly but still fits under origin/main's budget keep that budget; their comment says `ceil(1.05 × <old> measured), kept: <new> now`. They are:
- the `test_cost_path_*` tests: the goblin and member structs carry their positions, +735 and +525;
- the representative fixtures, which now build the sheets' index.

**Removed tests.**
- The unit tests moved into their modules: new rows under `types::…::tests` and `models::…::tests`.
- `test_cost_scan_caste_*`: no caste is looked up by id any more.

**New tests.** The parity table, the index and kit tests, 15 `test_cost_term_set_*`, and the finding tests.

`python3 scripts/gas_budgets.py --report` from the worktree root (origin/main fetched at 7b693c8), rows this lot touched:

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::test_tick_words::test_potion_regeneration_every_belt_slot | 2979442 | 3007552 | 3128415 | +0.9 % |
| grimworld_ephemeral::test_tick_words::test_tick_constants | 13720 | 13720 | 14406 | unchanged |
| grimworld_ephemeral::test_tick_words::test_tick_words_goblin | 486360 | 584620 | 613851 | raised: the load reads through the content's index, built first (CBT-02d); +20.2 % |
| grimworld_ephemeral::test_tick_words::test_tick_words_member | 1230510 | 1318560 | 1384488 | raised: the load reads through the content's index, built first (CBT-02d); +7.2 % |
| grimworld_logic::models::goblin::tests::test_goblin_adrenaline_gain | — | 463030 | 486182 | new |
| grimworld_logic::models::goblin::tests::test_goblin_assert_pips | — | 15520 | 16296 | new |
| grimworld_logic::models::goblin::tests::test_goblin_conditions | — | 584270 | 613484 | new |
| grimworld_logic::models::goblin::tests::test_goblin_hold | — | 673910 | 707606 | new |
| grimworld_logic::models::goblin::tests::test_goblin_hot | — | 325080 | 341334 | new |
| grimworld_logic::models::goblin::tests::test_goblin_load | — | 865370 | 908639 | new |
| grimworld_logic::models::goblin::tests::test_goblin_load_missing_skill | — | 433070 | 454724 | new |
| grimworld_logic::models::goblin::tests::test_goblin_load_store | — | 1021090 | 1072145 | new |
| grimworld_logic::models::member::tests::test_hold_eviction_and_stance | — | 7444900 | 7817145 | new |
| grimworld_logic::models::member::tests::test_hold_refresh | — | 6959730 | 7307717 | new |
| grimworld_logic::models::member::tests::test_member_adrenaline_gain | — | 5412750 | 5683388 | new |
| grimworld_logic::models::member::tests::test_member_assert_pips | — | 15520 | 16296 | new |
| grimworld_logic::models::member::tests::test_member_bar_positions | — | 5616500 | 5897325 | new |
| grimworld_logic::models::member::tests::test_member_conditions | — | 5242590 | 5504720 | new |
| grimworld_logic::models::member::tests::test_member_hot | — | 4681150 | 4915208 | new |
| grimworld_logic::models::member::tests::test_member_load_store | — | 10361100 | 10879155 | new |
| grimworld_logic::test_combat::test_entry_condition_of_zero_ticks_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_tick::test_branch_worlds_take_their_branch | 295359514 | 70449014 | 73971465 | -76.1 % |
| grimworld_logic::test_tick::test_cost_awake_100 | 45994980 | 12248650 | 12861083 | -73.4 % |
| grimworld_logic::test_tick::test_cost_batch_representative | 13481670 | 13638920 | 13911629 | +1.2 % |
| grimworld_logic::test_tick::test_cost_batch_worst | 138321450 | 29635680 | 31117464 | -78.6 % |
| grimworld_logic::test_tick::test_cost_bound_activating | 58270653 | 13693583 | 14378263 | -76.5 % |
| grimworld_logic::test_tick::test_cost_bound_activating_fixture | 55798260 | 13431340 | 14102907 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_base | 56896823 | 13624453 | 14305676 | -76.1 % |
| grimworld_logic::test_tick::test_cost_bound_base_fixture | 55798260 | 13425620 | 14096901 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_base_member_alive | 56887353 | 13612303 | 14292919 | -76.1 % |
| grimworld_logic::test_tick::test_cost_bound_base_member_alive_fixture | 55798260 | 13425720 | 14097006 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_clear | 59020076 | 13740136 | 14427143 | -76.7 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_clear_fixture | 55798260 | 13429430 | 14100902 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover | 59019103 | 13738223 | 14425135 | -76.7 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_alive | 59018903 | 13738123 | 14425030 | -76.7 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_alive_fixture | 55798260 | 13429240 | 14100702 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_fixture | 55798260 | 13429140 | 14100597 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_eight_lapses | 60398917 | 14641157 | 15373215 | -75.8 % |
| grimworld_logic::test_tick::test_cost_bound_eight_lapses_fixture | 55806660 | 13451870 | 14124464 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_free | 58277256 | 13697676 | 14382560 | -76.5 % |
| grimworld_logic::test_tick::test_cost_bound_free_fixture | 55798260 | 13431440 | 14103012 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_lapse | 59028756 | 13759946 | 14447944 | -76.7 % |
| grimworld_logic::test_tick::test_cost_bound_lapse_fixture | 55798260 | 13430100 | 14101605 | -75.9 % |
| grimworld_logic::test_tick::test_cost_bound_recovery_end | 58890176 | 13719306 | 14405272 | -76.7 % |
| grimworld_logic::test_tick::test_cost_bound_recovery_end_fixture | 55798260 | 13430770 | 14102309 | -75.9 % |
| grimworld_logic::test_tick::test_cost_fixture_candidates | 41730090 | 7618410 | 7999331 | -81.7 % |
| grimworld_logic::test_tick::test_cost_fixture_representative | 6918930 | 7231860 | 7264877 | +4.5 % |
| grimworld_logic::test_tick::test_cost_fixture_representative_words | 7105100 | 7459370 | 7460355 | +5.0 % |
| grimworld_logic::test_tick::test_cost_fixture_worst | 55847390 | 13443980 | 14116179 | -75.9 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_8 | 9198290 | 6275760 | 6589548 | -31.8 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_batch | 55847980 | 13445800 | 14118090 | -75.9 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_permuted | 56211700 | 15486860 | 16261203 | -72.4 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_words | 57836080 | 15624890 | 16406135 | -73.0 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_words_twice | 115660060 | 31237880 | 32799774 | -73.0 % |
| grimworld_logic::test_tick::test_cost_index_caste_first | — | 853330 | 895997 | new |
| grimworld_logic::test_tick::test_cost_index_caste_last | — | 853530 | 896207 | new |
| grimworld_logic::test_tick::test_cost_index_fixture | — | 852820 | 895461 | new |
| grimworld_logic::test_tick::test_cost_index_skill_first | — | 853330 | 895997 | new |
| grimworld_logic::test_tick::test_cost_index_skill_last | — | 853530 | 896207 | new |
| grimworld_logic::test_tick::test_cost_library_baseline | 119310973 | 27265073 | 28628327 | -77.1 % |
| grimworld_logic::test_tick::test_cost_library_baseline_all_dead | 113480923 | 26632383 | 27964003 | -76.5 % |
| grimworld_logic::test_tick::test_cost_library_baseline_batch | 57844710 | 15633320 | 16414986 | -73.0 % |
| grimworld_logic::test_tick::test_cost_library_baseline_kills | 119649723 | 27607223 | 28987585 | -76.9 % |
| grimworld_logic::test_tick::test_cost_library_baseline_representative | 7115610 | 7469680 | 7471391 | +5.0 % |
| grimworld_logic::test_tick::test_cost_library_baseline_two_members | 119860406 | 27713656 | 29099339 | -76.9 % |
| grimworld_logic::test_tick::test_cost_library_call | 121888993 | 29844793 | 31337033 | -75.5 % |
| grimworld_logic::test_tick::test_cost_library_call_all_dead | 116804603 | 29956963 | 31454812 | -74.4 % |
| grimworld_logic::test_tick::test_cost_library_call_batch | 146343720 | 35682980 | 37467129 | -75.6 % |
| grimworld_logic::test_tick::test_cost_library_call_batch_representative | 16324710 | 15717790 | 16503680 | -3.7 % |
| grimworld_logic::test_tick::test_cost_library_call_kills | 122942363 | 30900763 | 32445802 | -74.9 % |
| grimworld_logic::test_tick::test_cost_library_call_two_members | 122456406 | 30311356 | 31826924 | -75.2 % |
| grimworld_logic::test_tick::test_cost_load_bound | 64551570 | 21748590 | 22836020 | -66.3 % |
| grimworld_logic::test_tick::test_cost_load_bound_fixture | 11084960 | 11178120 | 11639208 | +0.8 % |
| grimworld_logic::test_tick::test_cost_load_bound_two_members | 74457490 | 31305730 | 32871017 | -58.0 % |
| grimworld_logic::test_tick::test_cost_load_bound_two_members_fixture | 20348660 | 20441820 | 21366093 | +0.5 % |
| grimworld_logic::test_tick::test_cost_load_member_potions | 5227100 | 5738570 | 6025499 | raised: the fixture builds the content's index before the load (CBT-02d); +9.8 % |
| grimworld_logic::test_tick::test_cost_load_member_potions_fixture | 4927590 | 5482100 | 5756205 | raised: the fixture builds the content's index (CBT-02d); +11.3 % |
| grimworld_logic::test_tick::test_cost_load_member_skills | 5537520 | 5746470 | 5814396 | +3.8 % |
| grimworld_logic::test_tick::test_cost_load_member_skills_fixture | 4928290 | 5482800 | 5756940 | raised: the fixture builds the content's index (CBT-02d); +11.3 % |
| grimworld_logic::test_tick::test_cost_load_store_worst | 168808590 | 41805320 | 43895586 | -75.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_above | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_above_full | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_adrenaline_zero | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_below | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_below_dead | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_down | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_down_dead | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_effect_over | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_effect_zero | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_energy_capped | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_engaged | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_store_changed | 582960 | 583960 | 612108 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_store_same | 582960 | 583960 | 612108 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_up | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_goblin_up_full | 316230 | 316930 | 332042 | +0.2 % |
| grimworld_logic::test_tick::test_cost_path_line_falling | 21620 | 21620 | 22701 | unchanged |
| grimworld_logic::test_tick::test_cost_path_line_rising | 21620 | 21620 | 22701 | unchanged |
| grimworld_logic::test_tick::test_cost_path_member_above | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_above_full | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_adrenaline_zero | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_below | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_below_dead | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_down | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_down_dead | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_effects_over | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_effects_zero | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_energy_capped | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_engaged | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_store_changed | 9318220 | 9318620 | 9784131 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_store_same | 9318220 | 9318620 | 9784131 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_up | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_path_member_up_full | 4695380 | 4695880 | 4930149 | +0.0 % |
| grimworld_logic::test_tick::test_cost_scan_potion_first | 300980 | 300780 | 315819 | -0.1 % |
| grimworld_logic::test_tick::test_cost_scan_potion_last | 305990 | 305790 | 321080 | -0.1 % |
| grimworld_logic::test_tick::test_cost_scan_skill_first | 301980 | 301480 | 316554 | -0.2 % |
| grimworld_logic::test_tick::test_cost_scan_skill_last | 382270 | 381770 | 400859 | -0.1 % |
| grimworld_logic::test_tick::test_cost_sheet_caste | 365130 | 365130 | 383387 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_caste_fixture | 336250 | 336250 | 353063 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_potion_damage | 30870 | 30870 | 32414 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_potion_fixture | 19670 | 19670 | 20654 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_potion_regen | 31070 | 31070 | 32624 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_potion_regen_negative | 31070 | 31070 | 32624 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_damage_then_empty | 50720 | 50720 | 53256 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_empty | 47270 | 47270 | 49634 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_fixture | 23950 | 23950 | 25148 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_none | 55740 | 55740 | 58527 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_first | 56410 | 56410 | 59231 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_second | 59660 | 59660 | 62643 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_third | 62910 | 62910 | 66056 | unchanged |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_third_negative | 64150 | 64150 | 67358 | unchanged |
| grimworld_logic::test_tick::test_cost_sheets | 404080 | 404080 | 424284 | unchanged |
| grimworld_logic::test_tick::test_cost_sheets_baseline | 336050 | 336050 | 350385 | unchanged |
| grimworld_logic::test_tick::test_cost_sheets_unpacked | 536590 | 536590 | 562464 | unchanged |
| grimworld_logic::test_tick::test_cost_term_eight_activating | 62795673 | 18464963 | 19388212 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_conclude_clear | 68786497 | 19220167 | 20181176 | -72.1 % |
| grimworld_logic::test_tick::test_cost_term_eight_conclude_recover | 68776393 | 19204863 | 20165107 | -72.1 % |
| grimworld_logic::test_tick::test_cost_term_eight_dead | 62634793 | 18302643 | 19217776 | -70.8 % |
| grimworld_logic::test_tick::test_cost_term_eight_free | 62848417 | 18504907 | 19430153 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_knocked | 62800313 | 18469603 | 19393084 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_lapse | 64632677 | 18973957 | 19922655 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_lapse_keep | 64494357 | 18976997 | 19925847 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_recovering | 62798793 | 18468083 | 19391488 | -70.6 % |
| grimworld_logic::test_tick::test_cost_term_eight_recovery_end | 63526997 | 18642017 | 19574118 | -70.7 % |
| grimworld_logic::test_tick::test_cost_term_mix_activating_lapse | 63552026 | 18575306 | 19504072 | -70.8 % |
| grimworld_logic::test_tick::test_cost_term_mix_clear_activating | 68036274 | 19124874 | 20081118 | -71.9 % |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse | 68793997 | 19236587 | 20198417 | -72.0 % |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse_spread | 68777607 | 19220197 | 20181207 | -72.1 % |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse_start | 68792627 | 19235217 | 20196978 | -72.0 % |
| grimworld_logic::test_tick::test_cost_term_mix_clear_recovery_end | 68655787 | 19195927 | 20155724 | -72.0 % |
| grimworld_logic::test_tick::test_cost_term_mix_lapse_first | 68177317 | 19183057 | 20142210 | -71.9 % |
| grimworld_logic::test_tick::test_cost_term_none | 57352703 | 14035123 | 14736880 | -75.5 % |
| grimworld_logic::test_tick::test_cost_term_none_k3 | 57352703 | 14035123 | 14736880 | -75.5 % |
| grimworld_logic::test_tick::test_cost_term_none_two_members | 57533276 | 14203176 | 14913335 | -75.3 % |
| grimworld_logic::test_tick::test_cost_term_one_activating | 59205023 | 14588783 | 15318223 | -75.4 % |
| grimworld_logic::test_tick::test_cost_term_one_conclude_clear | 59953876 | 14636676 | 15368510 | -75.6 % |
| grimworld_logic::test_tick::test_cost_term_one_conclude_recover | 59952613 | 14634763 | 15366502 | -75.6 % |
| grimworld_logic::test_tick::test_cost_term_one_conclude_recover_surviving | 59952893 | 14635043 | 15366796 | -75.6 % |
| grimworld_logic::test_tick::test_cost_term_one_dead | 59184913 | 14568493 | 15296918 | -75.4 % |
| grimworld_logic::test_tick::test_cost_term_one_free | 59211616 | 14593776 | 15323465 | -75.4 % |
| grimworld_logic::test_tick::test_cost_term_one_knocked | 59205603 | 14589363 | 15318832 | -75.4 % |
| grimworld_logic::test_tick::test_cost_term_one_lapse | 59962746 | 14657306 | 15390172 | -75.6 % |
| grimworld_logic::test_tick::test_cost_term_one_lapse_keep | 59945456 | 14657686 | 15390571 | -75.5 % |
| grimworld_logic::test_tick::test_cost_term_one_recovering | 59205413 | 14589173 | 15318632 | -75.4 % |
| grimworld_logic::test_tick::test_cost_term_one_recovery_end | 59824536 | 14616646 | 15347479 | -75.6 % |
| grimworld_logic::test_tick::test_cost_term_set_a6_ll | — | 18617969 | 19547482 | new |
| grimworld_logic::test_tick::test_cost_term_set_a_then_c | — | 19114574 | 20068917 | new |
| grimworld_logic::test_tick::test_cost_term_set_c6_al | — | 19129524 | 20084615 | new |
| grimworld_logic::test_tick::test_cost_term_set_c6_la | — | 19129524 | 20084615 | new |
| grimworld_logic::test_tick::test_cost_term_set_c6_ll | — | 19185327 | 20143208 | new |
| grimworld_logic::test_tick::test_cost_term_set_c6_rl | — | 19144667 | 20100515 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_first | — | 18541536 | 19467227 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_l_c6 | — | 19180217 | 20137842 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_last | — | 18544376 | 19470209 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_ll_c5 | — | 19142097 | 20097816 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_middle | — | 18544376 | 19470209 | new |
| grimworld_logic::test_tick::test_cost_term_set_c_r_c6 | — | 19139557 | 20095149 | new |
| grimworld_logic::test_tick::test_cost_term_set_cc_first | — | 18635459 | 19565846 | new |
| grimworld_logic::test_tick::test_cost_term_set_l_first | — | 18562166 | 19488889 | new |
| grimworld_logic::test_tick::test_cost_term_set_l_middle | — | 18562166 | 19488889 | new |
| grimworld_logic::test_tick::test_cost_tick_representative | 7570797 | 7868657 | 7924925 | +3.9 % |
| grimworld_logic::test_tick::test_cost_tick_worst | 64556493 | 14974523 | 15723250 | -76.8 % |
| grimworld_logic::test_tick::test_cost_tick_worst_8 | 11448463 | 7710593 | 8096123 | -32.6 % |
| grimworld_logic::test_tick::test_cost_tick_worst_permuted | 64934653 | 16919973 | 17765972 | -73.9 % |
| grimworld_logic::test_tick::test_deterministic | 278017840 | 58970080 | 61918584 | -78.8 % |
| grimworld_logic::test_tick::test_library_matches_pipeline | 241575486 | 57486386 | 60360706 | -76.2 % |
| grimworld_logic::test_tick::test_parity_examples | — | 129719576 | 136205555 | new |
| grimworld_logic::test_tick::test_parity_states | — | 168887114 | 177331470 | new |
| grimworld_logic::test_tick::test_parity_terms_eight | — | 217306260 | 228171573 | new |
| grimworld_logic::test_tick::test_parity_terms_mixed | — | 154917383 | 162663253 | new |
| grimworld_logic::test_tick::test_parity_terms_one | — | 229461702 | 240934788 | new |
| grimworld_logic::types::tick::tests::test_index_no_caste | — | 308790 | 324230 | new |
| grimworld_logic::types::tick::tests::test_index_no_potion | — | 308790 | 324230 | new |
| grimworld_logic::types::tick::tests::test_index_no_skill | — | 308790 | 324230 | new |
| grimworld_logic::types::tick::tests::test_index_positions | — | 448010 | 470411 | new |
| grimworld_logic::types::tick::tests::test_kits | — | 166510 | 174836 | new |
| grimworld_logic::types::tick::tests::test_sheets_read_oracle | — | 1119830 | 1175822 | new |
| grimworld_logic::types::world::tests::test_adrenaline_decay | — | 11380268 | 11949282 | new |
| grimworld_logic::types::world::tests::test_awake_set | — | 8824740 | 9265977 | new |
| grimworld_logic::types::world::tests::test_awake_set_apart | — | 6817230 | 7158092 | new |
| grimworld_logic::types::world::tests::test_deaths_in_step_3 | — | 6924598 | 7270828 | new |
| grimworld_logic::types::world::tests::test_defeat | — | 10842299 | 11384414 | new |
| grimworld_logic::types::world::tests::test_defeat_in_step_1_with_eight_awake | — | 8549523 | 8977000 | new |
| grimworld_logic::types::world::tests::test_example_activated_attack_cost | — | 17235903 | 18097699 | new |
| grimworld_logic::types::world::tests::test_example_burning_goblin | — | 6647144 | 6979502 | new |
| grimworld_logic::types::world::tests::test_example_condition_degeneration | — | 6716486 | 7052311 | new |
| grimworld_logic::types::world::tests::test_example_interrupt | — | 6251852 | 6564445 | new |
| grimworld_logic::types::world::tests::test_example_lapse | — | 11987274 | 12586638 | new |
| grimworld_logic::types::world::tests::test_example_member_activation | — | 15096886 | 15851731 | new |
| grimworld_logic::types::world::tests::test_flags_cleared | — | 5098973 | 5353922 | new |
| grimworld_logic::types::world::tests::test_member_down_before_the_tick | — | 5291800 | 5556390 | new |
| grimworld_logic::types::world::tests::test_regeneration | — | 10490349 | 11014867 | new |
| grimworld_logic::types::world::tests::test_regeneration_extremes | — | 10184106 | 10693312 | new |
| grimworld_logic::types::world::tests::test_who_acts | — | 7527519 | 7903895 | new |
| grimworld_logic::types::world::tests::test_world_assert_awake | — | 7283840 | 7648032 | new |
| grimworld_logic::types::world::tests::test_world_assert_awake_loaded | — | 8429340 | 8850807 | new |
| grimworld_logic::types::world::tests::test_world_assert_awake_perceived | — | 8853343 | 9296011 | new |
| grimworld_logic::types::world::tests::test_world_assert_distances | — | 304380 | 319599 | new |
| grimworld_logic::types::world::tests::test_world_assert_goblins | — | 28481960 | 29906058 | new |
| grimworld_logic::test_tick::test_adrenaline_decay | 10886538 | — | — | removed |
| grimworld_logic::test_tick::test_adrenaline_gain | 5813650 | — | — | removed |
| grimworld_logic::test_tick::test_awake_set | 8238390 | — | — | removed |
| grimworld_logic::test_tick::test_conditions_refresh_and_cure | 5597870 | — | — | removed |
| grimworld_logic::test_tick::test_cost_scan_caste_first | 302580 | — | — | removed |
| grimworld_logic::test_tick::test_cost_scan_caste_last | 312460 | — | — | removed |
| grimworld_logic::test_tick::test_deaths_in_step_3 | 6289978 | — | — | removed |
| grimworld_logic::test_tick::test_defeat | 10277159 | — | — | removed |
| grimworld_logic::test_tick::test_example_activated_attack_cost | 16564013 | — | — | removed |
| grimworld_logic::test_tick::test_example_burning_goblin | 5876854 | — | — | removed |
| grimworld_logic::test_tick::test_example_condition_degeneration | 6220816 | — | — | removed |
| grimworld_logic::test_tick::test_example_interrupt | 5951802 | — | — | removed |
| grimworld_logic::test_tick::test_example_lapse | 11205154 | — | — | removed |
| grimworld_logic::test_tick::test_example_member_activation | 14812576 | — | — | removed |
| grimworld_logic::test_tick::test_flags_cleared | 4844053 | — | — | removed |
| grimworld_logic::test_tick::test_goblin_assert_pips | 15520 | — | — | removed |
| grimworld_logic::test_tick::test_goblin_load | 753620 | — | — | removed |
| grimworld_logic::test_tick::test_hold_eviction_and_stance | 7186920 | — | — | removed |
| grimworld_logic::test_tick::test_hold_refresh | 7064120 | — | — | removed |
| grimworld_logic::test_tick::test_hot_decoders | 4992190 | — | — | removed |
| grimworld_logic::test_tick::test_load_store | 10710610 | — | — | removed |
| grimworld_logic::test_tick::test_member_assert_pips | 15520 | — | — | removed |
| grimworld_logic::test_tick::test_member_down_before_the_tick | 5025310 | — | — | removed |
| grimworld_logic::test_tick::test_regeneration | 10068819 | — | — | removed |
| grimworld_logic::test_tick::test_regeneration_extremes | 9674366 | — | — | removed |
| grimworld_logic::test_tick::test_sheets_read_oracle | 1294990 | — | — | removed |
| grimworld_logic::test_tick::test_who_acts | 7195079 | — | — | removed |
| grimworld_logic::test_tick::test_world_assert_awake | 7398433 | — | — | removed |
| grimworld_logic::test_tick::test_world_assert_distances | 283780 | — | — | removed |
| grimworld_logic::test_tick::test_world_assert_goblins | 27688060 | — | — | removed |

## Acceptance criteria

- **AC-1: hot fields apart and the content index in place; the results unchanged. Met.**
  - The awake set lives apart from the array (`World.awake`, `World.woken`).
  - The content is reached through `Index` and `Sheets` (one dictionary a call; each caste's kit derived once).
  - Parity: `test_parity_examples`, `_states`, `_terms_one`, `_terms_eight`, `_terms_mixed` pin 60 hashes taken on the old representation (commit 2251f0a). All pass on the new one.
  - The rewritten unit tests assert the same outcomes as before, moved as they were. Three changed:
    - `test_world_assert_goblins` makes its 101 goblins frozen, so the goblins' check is the one that fires;
    - `test_awake_set` also checks the set formed apart and a replaced goblin's current value;
    - `test_goblin_load` adds a second caste, to check the caste's position and cap.
- **AC-2: the two deferred findings. Met.**
  - The eight-free-goblin test: `term_tick` runs `Acts`, which records every act. `test_cost_term_eight_free` checks that the 8 goblins acted in order. The lapse and recovery-over states also check their acts, and every state checks that no other goblin acted.
  - The eight-awake limit before `conclude` can return: the limit is refused where the set is formed. Tests:
    - `types::world::tests::test_world_assert_awake` (the world made);
    - `test_world_assert_awake_loaded` (the library call's load; the member would die in step 1);
    - `test_world_assert_awake_perceived` (a ninth woken in step 0, the member dying at its resolution in step 1);
    - `test_defeat_in_step_1_with_eight_awake` (the same tick with eight awake, which stops in step 1).
- **AC-3: the worst tick re-proved term by term; the representative re-measured; both against 1,469,435, before and after; the overrun reported. Met.** See *Cost* above and ENG-01 §9.2. The overrun is 2.29 × at the bound, with its make-up; the representative is at 72.5 %.
- **AC-4: D-167 and D-143; CI green; `gas_budgets.py --check`; `class_sizes.py`. Met.**
  - D-167: the unit tests sit in their modules; `tests/test_tick.cairo` keeps the benchmarks, the library call and the parity table, and its header says why.
  - D-143: the new behaviour is scoped in traits (`IndexTrait`, `SheetsTrait`, `WorldTrait::goblin`, `set_goblin`, `member`, `set_member`), with no free function. The checks are in `WorldAssert` and `GoblinAssert::assert_kit`.
  - CI green on #211. `--check`: 689 tests. `TickLibrary`: 29.13 %.

## Deviations from the brief

1. **A file outside the allowlist.** `contracts/ephemeral/tests/test_tick_words.cairo` pins the goblin's and the member's `load` and `store` against the ephemeral packers. It called `load(words, @content)` and built a `World` literal, which this lot's changes remove. It now builds the index once and uses `WorldTrait::new` and `world.member(0)`. Its assertions are unchanged. Two of its budgets are raised, with reasons. Without this edit the workspace does not compile.
2. **`contracts/logic/src/models/index.cairo`.** The `Goblin` and `Member` structs live there (D-143's models index), so the goblin and member models' new fields went there: `caste_at`, `bar_at`. I read "the goblin and member models of `models/`" as including them.
3. **A test-only module**, `contracts/logic/src/types/world/fixtures.cairo` (`#[cfg(test)]`), holds the fixtures the moved unit tests share across four modules. `tests/test_tick.cairo` keeps its own copy because the test crate cannot see `cfg(test)` items (checked with a probe).
4. **Beyond the two named levers**, four measured changes on the tick's own path:
   - the members-down count, which makes `is_down` O(1);
   - the bar's positions packed;
   - a conclusion's direct write;
   - the kit carrying the weapon's cost.

   Each is inside the allowlist and under the parity table.
5. **A new refusal**: `'tick: more skills than ids'`, when the content holds more than 65,535 skills. It follows from the packed bar positions (16-bit lanes). Skill ids are `u16`, so such a content repeats ids, and only the first is ever read. It is a limit of the representation, not a game rule.
6. **The members are private** to `World` (read through `member(i)`, written through `set_member`), so the count of members down cannot be bypassed. The goblins are private for the same reason.
7. **Two CBT-02 benchmarks now print their tick measured alone.** `test_cost_tick_worst` and `test_cost_batch_worst` did fixture subtraction, which also counted their checks and the batch's loop. Their assertions are unchanged.
8. **`test_cost_scan_caste_*` removed**: no caste is looked up by id any more. The skill and potion scans remain, re-pointed at `Sheets` (the executor's lookups by id).

## Escalations

1. **ENG-01 §1.3 is stale and outside my allowlist.** Its `TickLibrary` row says 24.32 % (now 564,872 → 582,969 bytes of Sierra, 23,860 CASM felts, **29.13 %**). Its load-and-store row says ≤ 55,363,190 with every lookup charged as a full scan (now **≤ 10,570,470**, nothing charged). §9.2 has the new figures.
2. **The overrun: 3,363,766 a tick at the bound, 2.29 × the target** (it was 10.3 ×). The next lever, not taken here because it is outside the brief:
   - **What it would save:** most of load and store's 1.06 M a tick, which is now the largest share after the tick itself. It is spent decoding and re-encoding the goblins no step touches: ~0.85 M a tick at 92 frozen goblins.
   - **What it would change:** frozen goblins would stay as their words until a step or a hook touches them. `load`'s contract with perception would change (the awake selection reads every goblin's AI state and life), so it is ENG-07's to weigh with the design levers (D-166).
3. **A contract for the hooks (CBT-05, ENG-07).**
   - After step 0, a hook does not wake a goblin or put one to sleep (§5.2: the set is fixed for the tick). The module doc states it; nothing enforces it.
   - A hook that writes a goblin outside the awake set rebuilds the 100-goblin array. §9.2 counts up to 6 such goblins an action.
   - Every hook write into the set rebuilds its 8 goblins. `Busy`'s act ticks show the cost: 1,462,087 against 1,365,007 for its conclusion ticks.
4. **The executor's lookups by id** (`hold`, `put`, a stance: `SheetsTrait::skill`, `potion`) still scan the content, at up to ~82,000 L2 gas a skill. CBT-05 should either pass positions or price the scans.
5. **The awake selection costs 8.6 % more** (4,630,240 against 4,264,890 over 100 candidates): it now forms the set apart in the same pass. ENG-07 runs it at step 0, so its figure moves in §9.2.

## Open questions

- Should the pipeline enforce that a hook after step 0 does not change an awake flag (Escalation 3)? Enforcing it costs a check at every `set_goblin`, so I left it documented only.

## Fix loop 1

**Inputs.** Two audits of #211 at 61cea3a, through Nexus:
- cost and determinism, `[GPT-6-Astra]`: FAIL (COST-1 and COST-2 major, COST-3 minor);
- quality, `[GPT-6-Sol]`: PASS WITH FINDINGS (one minor on the count of states, one note on the count of moved tests).

The fix is in commits f7ad400 (benchmarks) and b4d160a (ENG-01), then aa8ec96 merges `origin/main` (#213, #214; no conflict). CI is green on aa8ec96: every check passes, `indexer-node` skipping. **This section supersedes the figures above wherever they differ.**

### A finding of my own while fixing COST-1: a call measured alone misses its straight-line part

While measuring `run`'s loop, `run` over ten ticks came out 1,116,400 above the same ten ticks measured alone (`Busy`): too much for a check and a count.

**The cause.** Sierra charges a function's code outside its loops when its caller withdraws gas, before the call runs. So `get_available_gas` around a call sees only what the callee's loops withdraw, and the refunds of its cheaper branches.

**The evidence.** Pairs of tests that differ by the call alone and check nothing, compared as snforge's totals (`test_cost_pair_*`):

| The call | Measured alone | As the pair's difference | The missing part |
|---|---:|---:|---:|
| `tick<Acts>`, the costliest state (7 conclusions then a lapse) | 1,396,257 | 1,475,797 | 79,540 |
| `tick<Acts>`, 8 activating goblins | 626,553 | 706,093 | 79,540 |
| `tick<Idle>`, the representative tick | 564,337 | 636,067 | 71,730 |
| `tick<Busy>`, `Busy`'s first tick (8 conclusions) | 1,365,007 | 1,472,677 | 107,670 |
| `awake`, a prior set of 8 at the array's start, kept | 4,635,960 | 4,663,510 | 27,550 |
| `awake`, no prior set | 4,568,720 | 4,596,270 | 27,550 |

**What it changes.** The missing part is one constant for each monomorphization, whatever the state. So:
- every difference between two states measured alone is exact: the model's terms, the members' deltas;
- every absolute figure measured alone is short by that constant: the bound, S, the heavy tick, `Busy`'s ticks, the selection.

CBT-02b's term method had the same blind spot (its "tick alone" figures). The fixture-subtraction figures (representative, load and store, the call) never had it.

### COST-1: `run`'s own loop, charged

`test_cost_pair_representative_run_ten` less the fixture: 6,406,330 for ten ticks through `run`. Ten `tick<Idle>` measured alone come to 5,643,370 (`test_cost_run_ticks_alone`: all ten are 564,337), and the tick's missing part adds 10 × 71,730.

So **`run`'s loop at ten iterations costs 45,660: 4,566 a tick.** That covers eleven checks of `k < ticks && !world.defeated`, the count and the calls. One tick through `run` costs 10,240 beyond the tick (`test_cost_pair_representative_run_one`).

`run` belongs to the call. The library call's subtraction cancels it, and `term_tick` measures `tick` alone, so it is now charged in the batch table's pipeline row.

### COST-2: the awake selection from a prior set

`test_cost_awake_*` measure `TickTrait::awake` alone from a prior set of 8, adding the selection's missing part (27,550) to each. Each test checks the set it keeps or replaces.

| Prior set | Distances | New set | Cost |
|---|---|---|---:|
| None | falling | the last 8 | 4,596,270 |
| At the end | falling | kept | 4,655,870 |
| At the start | falling | replaced by the last 8 | 4,654,990 |
| Spread | falling | replaced by the last 8 | 4,654,990 |
| **At the start** | **rising** | **kept** | **4,663,510** (pair-measured) |
| At the end | rising | replaced by the first 8 | 4,662,630 |
| Spread | the set nearest | kept | 4,660,030 |

**The maximum is 4,663,510.** Before this loop the figure was 4,630,240, from `candidates()` where no goblin is awake. The old code's was 4,264,890.

The rising order costs slightly more than the falling one that CBT-02 took as the scans' costliest: the maximum is over what is measured.

### COST-3: the members

157,443 is labelled as **the second member's measured delta**. The same holds for 293,440 to load and store and 17,980 to the call.

The base tick with 4 and 8 members (`term_none_four_members`, `term_none_eight_members`, measured alone; their differences are exact):

| Members | The base, alone | Each member of the range adds |
|---|---:|---:|
| 1 | 126,373 | — |
| 2 | 283,816 | 157,443 |
| 4 | 647,722 | 181,953 (the 3rd and 4th) |
| 8 | 1,571,614 | 230,973 (the 5th to 8th) |

A member adds more the more there are: each member's conclusion rebuilds the members' array. The bound is the MVP's, one member. A bound for eight members is not derived here.

### Quality 1 and the note: the counts

- **The states.** 32 states of 8 goblins are measured: 10 `term_eight_*`, 7 `term_mix_*`, 15 `term_set_*`. They make 29 distinct orders of branches, since the lapse keeping a later recharge measures as a lapse, and the costliest mix is placed three ways.
  - **13 fix the terms:**
    - S: `eight_activating`;
    - a conclusion: `set_c_middle`, `set_c_first`;
    - a conclusion into a recovery: `eight_conclude_recover`, whose first-position term borrows a clearing conclusion's 2,840. It never enters the maximum, being below a clearing conclusion at every position;
    - the writes left for the end: `mix_activating_lapse`, `eight_lapse`, `mix_clear_recovery_end`, `eight_recovery_end`;
    - a lapse a later conclusion writes: `mix_lapse_first`;
    - the goblins that write nothing: `eight_free`, `eight_knocked`, `eight_recovering`, `eight_dead`.
  - **The other 19 check the model, all to the unit.** Two of them (`set_c_r_c6`, `set_c_ll_c5`) were predicted before they were measured.
- **The moved unit tests** are 45 (22 world, 7 content, 8 goblin, 8 member), not 44.

### The bound, before and after this loop (rows that changed)

| Per tick inside a batch of 10 | At 61cea3a | After fix loop 1 |
|---|---:|---:|
| The tick, its costliest state | 1,396,257 (measured alone) | **1,475,797** (reached, as its pair) |
| S, 8 activating goblins | 626,553 | 706,093 |
| `run`'s loop | not charged | **4,566** (45,660 over ten ticks) |
| The pipeline in a batch | ≤ 1,396,257 | **≤ 1,480,363** |
| Through one library call | ≤ 2,785,762 | **≤ 2,869,868** |
| **The tick's share at the bound** | ≤ 3,363,766 (2.29 ×) | **≤ 3,447,872 (2.35 ×)** |
| The representative pipeline in a batch | 640,706 (fixture subtraction with a check) | 640,633 (`run`'s pair, no check) |
| The representative tick | 636,797 (the same) | 636,067 (its pair) |
| The representative share | 1,065,651 (72.5 %) | 1,065,651 (72.5 %), unchanged |
| The awake selection over 100 candidates | 4,630,240 | **4,663,510** |
| CBT-02's heavy tick, `Idle` | 1,361,673 (alone) | 1,433,403 (+ 71,730) |
| `Busy`'s ticks | 1,365,007 and 1,462,087 (alone) | 1,472,677 (8 conclusions) and 1,569,757 (8 acts with its hooks' writes) |

The tick alone is now above the 1,469,435 target, by 6,362, with `Acts`' recording hook. With `Idle` it is at most 1,475,797 − 7,810 (the smaller straight-line part), less the lapse's recorded act.

The overrun at the bound is 2.35 ×. It goes to the project manager, as the orchestrator relayed.

**Unchanged:** load and store ≤ 10,570,470 a call and the call 3,324,580 (fixture subtraction); the content 578,004 a tick.

### ENG-01

- **§9.2:** the table's rows above; the paragraph on the missing straight-line part; S, the maximum, the states counted, the members.
- **§1.3:** the `TickLibrary` rows, my escalation 1:
  - class: 582,969 bytes of Sierra, 23,860 CASM felts, **29.13 %**;
  - load and store: ≤ 10,570,470, nothing charged.

  I updated the load-and-store row too, since it was the second figure of that escalation. The call's rows in §1.3 (3,323,680; 2,578,020) are CBT-02b's and are within 1,700 of today's.

### Commands run

```
$ git fetch origin main                                  # not moved at the start; later #213, #214
$ cd contracts/logic && snforge test test_cost_awake --max-threads 1
gas awake: 4628320 / 4635080 / 4568720 / 4632480 / 4627440 / 4635960 / 4627440   (the 7 states, alone)
$ snforge test test_cost_pair_ --max-threads 1
term_fixture 17380480, term_tick 18856277; activating_fixture 17381850, activating_tick 18087943;
representative_fixture 7230860, _tick 7866927, _run_one 7877167, _run_ten 13637190;
awake_start_kept_fixture 9588680, awake_start_kept 14252190; awake_none_fixture 8033980, awake_none 12630250;
busy_fixture 13443180, busy_tick 14915857
$ snforge test test_cost_run_ticks_alone             # gas representative tick 0..9: 564337 each
$ snforge test test_cost_term_none --max-threads 1   # 126373, 283816, 647722, 1571614 alone
$ snforge test test_tick::                           # Tests: 193 passed, 0 failed
$ python3 scripts/gas_budgets.py && python3 scripts/gas_budgets.py --check
gas check: 713 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build && python3 contracts/tools/class_sizes.py
TickLibrary 582,969 bytes, 23,860 CASM felts, 29.13 % (ok)
$ git merge origin/main                              # #213, #214: docs only, no conflict
$ gh pr checks 211 --watch --interval 30            # aa8ec96: every check pass, indexer-node skipping
```

### Files changed in fix loop 1

- `contracts/logic/tests/test_tick.cairo`:
  - `test_cost_awake_*` (7) with `awake_state` and `awake_tick`;
  - `test_cost_pair_*` (14);
  - `test_cost_run_ticks_alone`;
  - `test_cost_term_none_{four,eight}_members`;
  - the notes on the straight-line part.
- `docs/architecture/ENG-01-interfaces.md`: §9.2 as above; §1.3's `TickLibrary` rows.
- `contracts/logic/GAS.md`, `docs/BUDGETS.md`: generated.
- `REPORT.md`: the counts of states and of moved tests in the text above, and this section.

### Gas table (fix loop 1)

**No budget is raised; every existing row is unchanged.** 24 new rows, each budget `ceil(1.05 × measured)`:

| Test | Measured |
|---|---:|
| `test_cost_awake_none`, `_end_kept`, `_start_replaced`, `_spread_replaced`, `_start_kept`, `_end_replaced`, `_spread_kept` | 12,754,700; 14,427,260; 14,426,380; 14,410,220; 14,376,910; 14,376,030; 14,404,390 |
| `test_cost_pair_term_fixture`, `_term_tick` | 17,380,480; 18,856,277 |
| `test_cost_pair_activating_fixture`, `_activating_tick` | 17,381,850; 18,087,943 |
| `test_cost_pair_representative_fixture`, `_tick`, `_run_one`, `_run_ten` | 7,230,860; 7,866,927; 7,877,167; 13,637,190 |
| `test_cost_pair_awake_start_kept_fixture`, `_awake_start_kept` | 9,588,680; 14,252,190 |
| `test_cost_pair_awake_none_fixture`, `_awake_none` | 8,033,980; 12,630,250 |
| `test_cost_pair_busy_fixture`, `_busy_tick` | 13,443,180; 14,915,857 |
| `test_cost_run_ticks_alone` | 14,531,530 |
| `test_cost_term_none_four_members`, `_eight_members` | 14,588,302; 15,561,294 |

### Escalations after fix loop 1

1. **The straight-line part of measures taken alone.** Any other lot that measures with `get_available_gas` around a call (the map library's per-layer figures, ENG-06's) may be short in the same way. The pairs above are the way to check.
2. **The tick alone now exceeds the target** (1,475,797 with `Acts`, against 1,469,435), before the executor, the AI and load, store, the call and the content. For the project manager, with the overrun.

## Merge of main after CBT-02e

**What happened.** `origin/main` (CBT-02e, #212) is merged into the branch: commit 1e9dee2. Only `contracts/ephemeral/GAS.md` and `docs/BUDGETS.md` conflicted. I resolved them by regenerating with `scripts/gas_budgets.py` (main's versions taken first, never merged by hand), and regenerated `contracts/logic/GAS.md` and `contracts/persistent/GAS.md` too. Nothing else changed.

**ENG-01** auto-merged and reads right:
- §1.3 holds both rows: `TickLibrary` (582,969 bytes, 23,860 CASM felts, 29.13 %) and `FlattenLibrary` (22,098 felts, 26.98 %);
- the load-and-store row still reads ≤ 10,570,470;
- §9.2 is unchanged from fix loop 1.

**Rows that moved: none of this lot's.** Comparing the measured values and budgets of the generated `docs/BUDGETS.md` before and after the merge:
- every row of `test_tick`, `types::world`, `types::tick`, `models::goblin`, `models::member` and `test_tick_words` is unchanged; only the date and commit provenance moved;
- the table grows from 713 to 743 rows with CBT-02e's tests;
- no budget fails, and none is raised (D-154).

**Commands run**

```
$ git fetch origin main && git merge origin/main
CONFLICT (content): contracts/ephemeral/GAS.md, docs/BUDGETS.md
$ git checkout --theirs contracts/ephemeral/GAS.md docs/BUDGETS.md
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
Finished `dev` profile target(s) in 27 seconds
$ python3 scripts/gas_budgets.py                       # wrote the 3 GAS.md and docs/BUDGETS.md
$ python3 scripts/gas_budgets.py --check
gas check: 743 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py
Instances 29.05 %, FlattenLibrary 26.98 %, TickLibrary 29.13 %, Market 3.44 %, Registry 30.04 %, Hub 44.71 % (every class ok)
$ cd contracts/logic && snforge test        # Tests: 512 passed, 0 failed
$ cd contracts/persistent && snforge test   # Tests: 178 passed, 0 failed
$ cd contracts/ephemeral && snforge test    # Tests: 53 passed, 0 failed
$ git push && gh pr checks 211 --watch --interval 30
1e9dee2: every check pass (14), indexer-node skipping; cairo (contracts) pass 3m2s
```
