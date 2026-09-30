# [Opus 5.5] CBT-02b — The tick's cost: two levers, the Hub wiring, and a proved bound

## Summary

The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

**What exists now that did not before:**

- **Lever (b), a cheaper split** (D-161):
  - `packing::split` removes `LIVE` with one overflowing subtraction. It is the same function for every layout: ~3,050 → ~2,780 L2 gas a word.
  - `packing::limbs` splits a word known to carry `LIVE` (every stored record) with a field subtraction: ~1,810.
  - `packing::peel` reads a limb field after field, one `u128` division a field; `field` takes two.
  - The goblin's and the member's hot decoders read each limb in one pass. Their `store` rewrites 4 (goblin) or 5 (member) hot regions, one difference each, instead of re-reading 13 fields. The sheets' readers use `limbs` and `peel`.
- **Lever (a), fewer goblin copies** (D-161):
  - Step 1 collects the awake set in its one pass (fixed for the tick once perception has run, §5.2); steps 2 and 3 read the awake goblins alone.
  - Step 1's writes are pending and go into the array in one rebuild: before the executor's hook (the hook sees the world as it is), and when the step ends.
  - Step 3 rebuilds the array only if a goblin is awake.
  - `set_goblin` and `set_member` copy the unchanged runs whole.
  - The tick refuses more than 8 awake goblins (design/02: `WorldAssert::assert_awake`).
  - The `World` and `Goblin` types are unchanged, so every CBT-02 test passes as written (AC-1).
- **The upper bound, proved term by term** (COST-1a–c, COST-3):
  - **Sierra charges a function that has no loop, and calls none, its costliest path, whatever runs.** Measured: all 13 paths of a goblin's step 3 cost 316,230; all 13 of a member's cost 4,695,380; `store` and `line` likewise (`test_cost_path_*`).
  - A cost therefore varies only with its loops: counts, the path each iteration takes, and lookup positions. Each is measured at its maximum.
  - The costliest tick state is reached and measured: 8,769,187.
  - The tick's upper bound is **≤ 8,834,287**, against CBT-02's 12,618,207.
  - Per tick inside a batch, with load and store, the call and the content: **≤ 15,148,134**, against CBT-02's 19,561,962.
- **The overrun is reported, not accepted** (AC-4): the bound is 10.3× the 1,469,435 target; the representative state is 1,104,546 (75.2 %). The make-up is in *Cost*.
- **The wiring (AC-3) was built, tested and measured, then held back**, and escalated.
  - What it did (0607c1d):
    - `set_build` flattens the build: DS-2's floors, DS-23's insignia pieces and design/20's counts refuse there.
    - `enter` builds its snapshot through the flattening; its snapshot equals the flattening's.
  - What it costs:
    - the flattening adds **30,314 CASM felts** to `Hub`: **79.83 %** of the class limit, over ENG-01 §1.3's 50 % rule (CI's `class_sizes.py` fails);
    - `set_build`'s worst case is 17,455,710 a call, `enter`'s 17,403,978, against D-158's 3.1M and 5.25M.
  - Why it is held back: splitting the flattening into a library class needs its class hash in `Hub`'s configuration, which is outside my allowlist.
  - 5c437de puts the pre-wiring files back; restoring 0607c1d's files restores the wiring. The project manager decides (*Escalations* 1).
- ENG-01 §1.3 and §9.2 carry the bound and its terms. GAS.md and BUDGETS.md are generated, and the lifecycle probe was re-run.

Pull request: https://github.com/bal7hazar/grimworld/pull/196. CI is green on every check (`cairo (contracts)` included: tests, gas budgets, class sizes).

## Files changed

- `contracts/logic/src/packing.cairo`: `split` with one overflowing subtraction; `limbs`, `peel`, the `N*` divisor constants.
- `contracts/logic/src/models/goblin.cairo`: `hot` in one pass; `store` by region; `recharge`, `crippled`, `effect_of` with `limbs`.
- `contracts/logic/src/models/member.cairo`: the same for the member (`hot`, `load`'s stats, effects and bar, `store`, the word accessors).
- `contracts/logic/src/types/tick.cairo`: the three sheets' `read` with `limbs` and `peel`.
- `contracts/logic/src/types/world.cairo`:
  - the pipeline's lever (a): `conclude` collects the awake set and batches its writes; `act` and `regenerate` read the awake set;
  - `WorldTrait::flush`, a cheaper `set_goblin` and `set_member`;
  - `WorldAssert::assert_awake`; the `Pending` type.
- `contracts/logic/tests/test_tick.cairo`:
  - the bound's tests (constancy of every step-3, `store` and `line` path; the branches at 1 and 8 goblins, four new branches, the costliest mix; load and store on their costliest paths; the sheets' paths; the call with 100 kills and with two members);
  - `test_world_assert_awake`;
  - COST-3's wording in CBT-02's comments;
  - budgets.
- `contracts/logic/tests/{test_build,test_build_records,test_combat,test_models,test_packing}.cairo`, `contracts/persistent/tests/*.cairo` (9 files), `contracts/ephemeral/tests/*.cairo` (3 files), `contracts/ephemeral/src/systems/instances.cairo` (one unit test's budget): budgets lowered after lever (b).
- `contracts/logic/GAS.md`, `contracts/persistent/GAS.md`, `contracts/ephemeral/GAS.md`, `docs/BUDGETS.md`: generated.
- `contracts/tools/lifecycle-probe-output.txt`: the node probe re-run.
- `docs/architecture/ENG-01-interfaces.md`: §1.3 (the class, the call at its bounds, load and store's bound) and §9.2 (the tick's figures, the bound's terms and how each is reached).
- In the branch's history only (0607c1d, reverted by 5c437de):
  - `contracts/persistent/src/systems/hub.cairo` (`set_build`, `enter`, the helpers `equipment`, `modifiers`, `held`);
  - `contracts/persistent/src/models/item.cairo` (`ItemModsTrait::held`, `ItemModsAssert`, two errors);
  - `contracts/persistent/src/models/adventurer.cairo` (`BuildTrait::loadout`);
  - the persistent tests of the wiring.

## Commands run

```
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
    Finished `dev` profile target(s) in 28 seconds
$ cd contracts/logic && snforge test
Tests: 422 passed, 0 failed, 0 ignored, 0 filtered out        (the final code)
$ cd contracts/persistent && snforge test
Tests: 153 passed, 0 failed                                    (the levers' code; 159 with the wiring, 0607c1d)
$ cd contracts/ephemeral && snforge test
Tests: 53 passed, 0 failed
$ python3 scripts/gas_budgets.py            # origin/main fetched
wrote contracts/logic/GAS.md, contracts/persistent/GAS.md, contracts/ephemeral/GAS.md, docs/BUDGETS.md
$ python3 scripts/gas_budgets.py --check
gas check: 628 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ grep -h "| -[0-9]" contracts/*/GAS.md     # no negative margin
(none)
$ python3 contracts/tools/class_sizes.py
| grimworld_ephemeral | `Instances` | 828,459 | 12,078 | 32,444 | 39.60 % | ok |
| grimworld_logic | `TickLibrary` | 491,811 | 7,170 | 19,923 | 24.32 % | ok |
| grimworld_persistent | `Hub` | 942,926 | 14,203 | 35,084 | 42.83 % | ok |
(with the wiring, 0607c1d: `Hub` 1,808,156 | 27,464 | 65,398 | 79.83 % | OVER; exit 1)
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check     # clean after fmt
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt
exit 0 (every case SUCCEEDED, the same write sets)
$ gh pr checks 196 --watch --interval 30
every check pass (indexer-node skipping); cairo (contracts) pass 2m47s
```

**Profiling behind the levers.** Scratch tests, not committed; snforge, per operation.

| Operation | L2 gas |
|---|---:|
| `felt252 → u256` | ~1,710 |
| `split` before CBT-02b (a comparison and a subtraction) | ~3,050 |
| `split` now (one overflowing subtraction) | ~2,780 |
| `limbs` | ~1,810 |
| a `u128` division by a constant | ~1,300 |
| `field` (two divisions) | ~2,600 |
| one `Goblin` copied into an array (23 felts) | ~6,000 |
| `set_goblin` on 100 goblins before CBT-02b | ~900,000 |
| a rebuild of 100 goblins now | ~600,000 |
| a scan reading `awake`: `at(i)` | ~3,300 a goblin |
| a scan reading `awake`: the span | ~1,800 a goblin |

**The flattening's size, measured to decide the wiring.** A scratch contract exposing only `SnapshotBuildTrait::build` is 31,042 CASM felts. With the sums replaced by `SnapshotTrait::new` it is 12,479 (the checks and the Serde). Without `assert_sources` it is 25,375. Marking `build` `#[inline(never)]` in `Hub` changed nothing.

## Cost

### The levers, before and after, on the same states (AC-1)

Net of fixtures (snforge). *Before*: `origin/main` (`docs/BUDGETS.md`). *(b)*: a9f6fad alone. *After*: this branch.

| Per tick (unless said) | Before | (b) | After | |
|---|---:|---:|---:|---:|
| Representative tick, the pipeline | 628,617 | 628,617 | 651,867 | +3.7 % |
| Representative batch of 10, the pipeline, per tick | 633,024 | — | 656,274 | +3.7 % |
| **Representative batch through one library call, per tick** | **961,079** | — | **920,910** | **−4.2 %** |
| CBT-02's heavy tick (`worst_state`: 8 conclusions, 100 goblins) | 12,413,093 | 12,399,513 | 8,709,103 | −29.8 % |
| The audit's permutation of it | 12,425,803 | — | 8,722,953 | −29.8 % |
| 8 lapses in the 100-goblin array (they now share one rebuild) | 12,552,207 | — | 4,592,257 | −63.4 % |
| `Busy`'s 10-tick batch, per tick | 11,961,127 | — | 8,247,347 | −31.0 % |
| Load and store of CBT-02's heavy words, once per call | 59,921,060 | 53,148,530 | 53,148,530 | −11.3 % |
| A sheet read, average of a skill and a caste | 42,710 | 34,015 | 34,015 | −20.4 % |
| **The tick's upper bound** | **12,618,207** (not proved per term) | — | **8,834,287** (proved) | −30.0 % |
| Load and store's upper bound, once per call | 62,118,160 | — | 55,363,190 | −10.9 % |
| **Per tick inside a batch, the upper bound** | **19,561,962** | — | **15,148,134** | −22.6 % |

- **The representative tick rose 3.7 % with lever (a).** With 8 goblins, all awake, the pipeline now pays for the awake list and the pending writes (profiled at about 22,500 a tick), where CBT-02 scanned a small dense array at once.
- Through the library call, lever (b) more than repays it: the representative batch falls 4.2 %.
- Lever (a) pays at the array's bound. The 100-goblin rebuild falls from ~900,000 to ~600,000, the lapses and recoveries share one rebuild, and steps 2 and 3 no longer read the 92 frozen goblins.
- CBT-02's estimate for (a) was −30 to −50 % of the pipeline. Measured: −30 % at the bound, +3.7 % on the dense representative array.

### The upper bound, term by term (AC-2; COST-1a–c)

**What can vary** (COST-1a). Sierra charges a function that has no loop, and calls none, its costliest path whatever path runs. A function with a loop, or calling one, pays the path it takes. Measured:

- all 13 paths of a goblin's step 3 cost 316,230 (`test_cost_path_goblin_*`): the pips below −10, in −10…−1 and in 0…10 and above 10, each with health lost, to 0 or to its max; no effect pips; an effect over; energy capped; no adrenaline; Engaged;
- all 13 of a member's cost 4,695,380;
- `store` costs the same unchanged or changed: 582,960 for a goblin, 9,318,220 for a member;
- `EntryTrait::line` costs the same rising or falling (21,620);
- so the audit's arithmetic branches (zero adrenaline, fixed regeneration values, the clamps, the signed division) cannot change a cost;
- conversely, the member's conclusion costs a constant plus exactly 2,170 a position scanned (slots 0 to 7 measured in scratch: 87,580 → 102,770 = 7 × 2,170).

A cost therefore varies only with its loops: how many times each runs, the path each iteration takes, and how far each lookup scans. The counts at their bounds are one member (the MVP), 100 goblins (`assert_goblins`), 8 awake (`assert_awake`), and 38 skills, 5 castes, 4 potions (design/19 §7.2). A lookup costs 2,170 a skill, 2,470 a caste and 1,670 a potion per position (`test_cost_scan_*`).

**The tick** (Idle rules, net of fixtures):

| Term | Maximum | Reached by | Status |
|---|---:|---|---|
| Base: the member concluding bar slot 7 and dying (step 5's defeat), the 100-goblin array, none awake | 1,098,563 | `test_cost_bound_base` (member alive: 1,089,093) | measured, max of the member's paths |
| Step 3's rebuild of the array, once a tick with an awake goblin | 1,333,696 | the activating branch, 1 and 8 goblins | measured |
| The end of step 1's rebuild, once a tick when step 1's last write is not a conclusion's | 603,700 | the lapse, 1 and 8 goblins | measured |
| Each awake goblin, its costliest branch: a conclusion clearing the field (its own rebuild for the executor), dying | 789,557 | `test_cost_bound_eight_conclude_clear` − `test_cost_bound_conclude_clear`, / 7 | measured |
| … the others, per goblin | into a recovery 788,584; lapse 194,537; lapse keeping a later recharge 177,043; recovery over 56,117; free 46,737; knocked down 40,360; recovering 40,260; activating 40,134; dead 20,060 | the 1 and 8 goblin tests of each | measured |
| Dying against surviving | +200 a goblin (conclusion into a recovery: 2,122,280 against 2,122,080) | `test_cost_bound_conclude_recover{,_alive}` | measured |
| The member's lookup at the list's end (it scans to position 8 of 38) | 65,100 | 30 × 2,170 | charged: not reachable with every goblin lookup at its end too (distinct ids) |

- **The costliest mix** follows from the terms: every branch but the conclusions costs at least 590,000 less a goblin. A lapse whose write is left for the end of step 1 costs 194,537 + 603,700 = 798,237 against a conclusion's 789,557.
  - So the maximum is **7 conclusions and a lapse last**. The terms give 8,757,397.
  - **Measured 8,769,187** (`test_cost_bound_mixed_last`). With the awake goblins at the array's start it is 8,769,177. Eight conclusions measure 8,748,717.
  - The two candidates within the terms' residual (11,790) are both measured, and the mix is the larger.
- **The tick's upper bound: 8,769,187 + 65,100 = 8,834,287.** Every tick of a batch is under it; `Busy`'s batch measures 8,247,347 a tick.
- **Load and store, once per call:**
  - measured on their costliest paths, 53,466,610 (`test_cost_load_bound`). Every goblin looks up its caste and its effect at their lists' ends and raises its adrenaline cap at each of 4 skills (costs 1–4). The member's 4 effects take the skill path, which is costlier than the potion path: 609,230 against 299,510 for 4 slots even before normalising positions. Its 8 bar skills each raise its cap (costs 1–8).
  - the cap's clamp at 252 is **not reachable**: DS-18 bounds a caste skill at 63 strikes;
  - `store` has no loop;
  - lookups not at their list's end are charged as full scans:
    - the member's bar, 268 comparisons: 581,560;
    - its effects, 6 comparisons: 13,020;
    - the goblins' caste skills, 600 comparisons: 1,302,000;
  - **Load and store's upper bound: 55,363,190.**
- **The library call** (COST-1b), every list at its bound: 100 goblins, 38 skills, 5 castes, 4 potions, **100 kills in and 100 out** (each goblin dies once), one member. It measures **3,323,680** (`test_cost_library_call_all_dead`). With 92 kills in and 100 out it is 3,292,640; with none in and 8 out, 2,578,020.
- **The content's sheets** (COST-1c), per record kind at its costliest path:
  - a skill, 40,200: its `REGENERATION` in the third entry, negative. The other paths cost 23,320–38,960;
  - a potion, 11,400: no loop; 11,200 without a `REGENERATION`;
  - a caste, 28,880: no loop.
  - For 38 + 4 + 5 records: 1,717,600 a batch. With the reads (D-145, ENG-06's measure: 54,000 a record, 98,000 a call, 2 calls): 4,451,600 a batch.
- **Each further member** (M-3 allows 8): +173,623 + 65,100 to a tick, +642,220 + 594,580 to load and store, +17,980 to the call (`*_two_members`).

### Against the expedition's target (AC-4)

| Per tick inside a batch of 10 | Representative | Upper bound |
|---|---:|---:|
| The pipeline | 656,274 | 8,834,287 |
| Load, store and the call, / 10 | 264,636 | 5,868,687 |
| **Through one library call** | **920,910** | **14,702,974** |
| The content (reads and sheets, per-kind maxima), / 10 | 183,636 | 445,160 |
| **The tick's share** | **1,104,546 (75.2 % of 1,469,435)** | **15,148,134 (10.3 ×)** |
| Left for the executor, AI, flood, window, writes and floor | 364,889 | −13,678,699 |

**The overrun is reported, not accepted.** The upper bound's make-up per tick:

- the tick, 8.83M:
  - 8 rebuilds of the 100-goblin array (7 for the executor's hook, one at the end of step 1), about 4.8M;
  - step 3's rebuild, 1.33M;
  - the base, 1.10M, which scans the array and runs the member;
  - the goblins' work, about 1.5M;
- load and store, 5.54M: the lookups are about 410,000 a goblin at the lists' ends (caste 5 × 2,470, effect 38 × 2,170, four caste skills 35–38 × 2,170);
- the call, 0.33M;
- the content, 0.45M.

**The levers that would move it next** (for the project manager; none applied here):

- **The array.** `World.goblins` is an array of 23-felt structs, so each executor hook needs a full rebuild. D-161's "hot fields apart" would change `World`'s representation, which AC-1's "every CBT-02 test unchanged" rules out here (*Deviations*).
- **Load's lookups.** A goblin looks up its 4 caste skills at every load. Deriving each caste's cap once a call, or giving the content an index, would remove most of the 41M of lookups a call. This is an estimate from the per-comparison terms, not measured.
- (c) and (d) (ENG-07) and (e) (after ENG-07), as D-161 decided.
- The awake selection, 4,264,890 wherever ENG-07 runs it at step 0.

### The wiring against D-158 (AC-3; measured in 0607c1d, then held back)

| Entrypoint | Before (main) | The levers alone (this branch) | With the wiring (0607c1d) | D-158's target |
|---|---:|---:|---:|---:|
| `set_build`, worst case, the call (snforge) | 2,960,731 | — | **17,455,710** (15 modifiers, 30 passives flattened) | 3,108,768 (call) / 3,798,150 net |
| `set_build`, worst case, as a transaction (node belt case + snforge's delta, as CBT-08a) | ~3.8M | — | **~18.5M** (2,811,200 + 15,689,150) | 3,798,150 net |
| `set_build`, 4 potions on 4 pages (node, transaction) | 2,611,200 | 2,611,200 | 2,811,200 | — |
| `enter`, later entry, no belt (node, transaction) | 4,702,400 | 4,702,400 | 5,142,400 | 4,513,259 net (4,702,400 gross) |
| `enter`, the belt's worst case (node, transaction) | 5,422,400 | 5,382,400 | 5,862,400 | 5,250,000 |
| `enter`, the worst case: the belt and 15 modifiers, the call (snforge, `Instances` a double) | — | — | **17,403,978** | — |
| `enter`, as a transaction (estimate) | — | — | **~20.6M** (5,862,400 + 14,744,668) | 5,250,000 |
| `Hub`'s class | 35,691 felts (43.57 %) | 35,084 (42.83 %) | **65,398 (79.83 %)** | < 50 % (ENG-01 §1.3) |

The flattening's checks are quadratic in the passives, and each statistic is a pass over them (CBT-02's escalation 2). For 30 passives it is ~14.5M of each worst case.

### Gas table

`python3 scripts/gas_budgets.py --report`, `origin/main` fetched. These are the rows this lot touched; the other 312 are `unchanged`. **No budget is raised.** Every change is a lowering, a new test, or a measure that rose within its budget: the dense-array tick tests, +0.1 to +2.0 %.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::systems::instances::close_tests::test_close_on_defeat | 4806860 | 4805780 | 5046069 | -0.0 % |
| grimworld_ephemeral::test_layout::test_chunk_layout | 357000 | 356280 | 374094 | -0.2 % |
| grimworld_ephemeral::test_layout::test_combat_fields_layout | 704800 | 704440 | 739662 | -0.1 % |
| grimworld_ephemeral::test_layout::test_deadline_boundaries | 321190 | 320470 | 336494 | -0.2 % |
| grimworld_ephemeral::test_layout::test_goblin_layout | 345130 | 344410 | 361631 | -0.2 % |
| grimworld_ephemeral::test_layout::test_member_layout | 557790 | 555950 | 583748 | -0.3 % |
| grimworld_ephemeral::test_layout::test_placement_and_header_layout | 445250 | 444170 | 466379 | -0.2 % |
| grimworld_ephemeral::test_lifecycle::test_create_first_entry | 31913652 | 31910182 | 33505692 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_create_refusals | 33645196 | 33638056 | 35319959 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_create_reuses_the_slot | 44470301 | 44465521 | 46688798 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_create_sealed | 25998856 | 25997186 | 27297046 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_create_without_tasks | 27927166 | 27925856 | 29322149 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_generation_isolation | 46064203 | 46052093 | 48354698 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_hub | 33351596 | 33348126 | 35015533 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_location | 39354487 | 39344897 | 41312142 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_not_controller | 28153704 | 28148074 | 29555478 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_refused_absent | 40488242 | 40483822 | 42508014 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_refused_closed | 38400625 | 38394635 | 40314367 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_refused_gate | 58707546 | 58693276 | 61627940 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sealed | 29237399 | 29235369 | 30697138 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sequence | 33195136 | 33190946 | 34850494 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_set_controller | 33106622 | 33102432 | 34757554 | -0.0 % |
| grimworld_ephemeral::test_lifecycle::test_travel_back | 31658989 | 31656599 | 33239429 | -0.0 % |
| grimworld_ephemeral::test_tick_words::test_potion_regeneration_every_belt_slot | 3195002 | 2979442 | 3128415 | -6.7 % |
| grimworld_ephemeral::test_tick_words::test_tick_words_goblin | 603260 | 486360 | 510678 | -19.4 % |
| grimworld_ephemeral::test_tick_words::test_tick_words_member | 1376240 | 1230510 | 1292036 | -10.6 % |
| grimworld_logic::test_build::test_caste_at_bounds | 225100 | 215420 | 226191 | -4.3 % |
| grimworld_logic::test_build::test_insignia_record_piece | 262710 | 262350 | 275468 | -0.1 % |
| grimworld_logic::test_build_records::test_base_round_trip | 78500 | 77780 | 81669 | -0.9 % |
| grimworld_logic::test_build_records::test_skill_profile_and_item_class | 2209570 | 2201890 | 2311985 | -0.3 % |
| grimworld_logic::test_capacity::test_flatten_damage_extremes | 3935540 | 3934460 | 4037786 | -0.0 % |
| grimworld_logic::test_capacity::test_flatten_penetration_and_armor_extremes | 7720350 | 7718190 | 7917620 | -0.0 % |
| grimworld_logic::test_capacity::test_flatten_saturated_extremes | 4001490 | 4000410 | 4097919 | -0.0 % |
| grimworld_logic::test_capacity::test_flatten_unguarded_armor_extremes | 7767660 | 7765500 | 7966770 | -0.0 % |
| grimworld_logic::test_capacity::test_flatten_weapon_scope_on_attack_skills | 3821430 | 3820350 | 3918411 | -0.0 % |
| grimworld_logic::test_capacity::test_flatten_worst_scope_overlap | 7813070 | 7810910 | 8014661 | -0.0 % |
| grimworld_logic::test_capacity::test_same_condition_summed | 4055880 | 4054800 | 4156215 | -0.0 % |
| grimworld_logic::test_combat::test_armor_set_round_trip | 252650 | 252290 | 264506 | -0.1 % |
| grimworld_logic::test_combat::test_caste_round_trip | 627200 | 626480 | 648690 | -0.1 % |
| grimworld_logic::test_combat::test_item_round_trip | 464890 | 464530 | 487757 | -0.1 % |
| grimworld_logic::test_combat::test_modifier_round_trip | 337460 | 337100 | 340631 | -0.1 % |
| grimworld_logic::test_combat::test_skill_round_trip | 1656300 | 1654140 | 1736847 | -0.1 % |
| grimworld_logic::test_models::test_gate_round_trip | 200400 | 199680 | 209664 | -0.4 % |
| grimworld_logic::test_models::test_location_round_trip | 728590 | 727150 | 763508 | -0.2 % |
| grimworld_logic::test_models::test_outline_round_trip | 29780 | 29060 | 30513 | -2.4 % |
| grimworld_logic::test_models::test_region_round_trip | 87480 | 86760 | 91098 | -0.8 % |
| grimworld_logic::test_packing::test_bar_and_kit_layout | 379970 | 379250 | 398213 | -0.2 % |
| grimworld_logic::test_packing::test_bar_passives_layout | 799210 | 798490 | 838415 | -0.1 % |
| grimworld_logic::test_packing::test_bitmap | 20570 | 20210 | 21221 | -1.8 % |
| grimworld_logic::test_packing::test_counter_never_zero | 18360 | 18000 | 18900 | -2.0 % |
| grimworld_logic::test_packing::test_kit_passives_layout | 616460 | 616100 | 646905 | -0.1 % |
| grimworld_logic::test_packing::test_lanes16 | 430370 | 430010 | 451511 | -0.1 % |
| grimworld_logic::test_packing::test_lanes32 | 111450 | 110730 | 116267 | -0.6 % |
| grimworld_logic::test_packing::test_stats_layout | 554270 | 553910 | 579516 | -0.1 % |
| grimworld_logic::test_packing::test_task_page_layout | 142250 | 141890 | 148985 | -0.3 % |
| grimworld_logic::test_tick::test_adrenaline_decay | 10884118 | 10886538 | 11399985 | +0.0 % |
| grimworld_logic::test_tick::test_adrenaline_gain | 5996260 | 5813650 | 6104333 | -3.0 % |
| grimworld_logic::test_tick::test_branch_worlds_take_their_branch | 314716584 | 295359514 | 310127490 | -6.2 % |
| grimworld_logic::test_tick::test_conditions_refresh_and_cure | 5726800 | 5597870 | 5877764 | -2.3 % |
| grimworld_logic::test_tick::test_cost_awake_100 | 47998980 | 45994980 | 48294729 | -4.2 % |
| grimworld_logic::test_tick::test_cost_batch_representative | 13249170 | 13481670 | 13911629 | +1.8 % |
| grimworld_logic::test_tick::test_cost_batch_worst | 177535330 | 138321450 | 145237523 | -22.1 % |
| grimworld_logic::test_tick::test_cost_bound_activating | 61781653 | 58270653 | 61184186 | -5.7 % |
| grimworld_logic::test_tick::test_cost_bound_activating_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_base | 61759143 | 56896823 | 59741665 | -7.9 % |
| grimworld_logic::test_tick::test_cost_bound_base_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_base_member_alive | 61749673 | 56887353 | 59731721 | -7.9 % |
| grimworld_logic::test_tick::test_cost_bound_base_member_alive_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_base_two_members | — | 57085316 | 59939582 | new |
| grimworld_logic::test_tick::test_cost_bound_base_two_members_fixture | — | 55813130 | 58603787 | new |
| grimworld_logic::test_tick::test_cost_bound_conclude_clear | 62829736 | 59020076 | 61971080 | -6.1 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_clear_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover | 62828863 | 59019103 | 61970059 | -6.1 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_alive | 62828663 | 59018903 | 61969849 | -6.1 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_alive_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_conclude_recover_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_dead | — | 58302213 | 61217324 | new |
| grimworld_logic::test_tick::test_cost_bound_dead_fixture | — | 55848500 | 58640925 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_activating | — | 58559993 | 61487993 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_activating_fixture | — | 55806660 | 58596993 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_conclude_clear | — | 64555377 | 67783146 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_conclude_clear_fixture | — | 55806660 | 58596993 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_conclude_recover | — | 64547593 | 67774973 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_conclude_recover_fixture | — | 55806660 | 58596993 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_dead | — | 58455653 | 61378436 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_dead_fixture | — | 55861520 | 58654596 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_free | — | 58612817 | 61543458 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_free_fixture | — | 55806660 | 58596993 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_knocked | — | 58621013 | 61552064 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_knocked_fixture | — | 55864480 | 58657704 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_lapse_keep | — | 60310337 | 63325854 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_lapse_keep_fixture | — | 55856800 | 58649640 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_lapses | 70434947 | 60398917 | 63418863 | -14.2 % |
| grimworld_logic::test_tick::test_cost_bound_eight_lapses_fixture | 57882740 | 55806660 | 58596993 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_eight_recovering | — | 58620213 | 61551224 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_recovering_fixture | — | 55864480 | 58657704 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_recovery_end | — | 59291397 | 62255967 | new |
| grimworld_logic::test_tick::test_cost_bound_eight_recovery_end_fixture | — | 55806660 | 58596993 | new |
| grimworld_logic::test_tick::test_cost_bound_free | 61788556 | 58277256 | 61191119 | -5.7 % |
| grimworld_logic::test_tick::test_cost_bound_free_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_knocked | — | 58322883 | 61239028 | new |
| grimworld_logic::test_tick::test_cost_bound_knocked_fixture | — | 55848870 | 58641314 | new |
| grimworld_logic::test_tick::test_cost_bound_lapse | 62842556 | 59028756 | 61980194 | -6.1 % |
| grimworld_logic::test_tick::test_cost_bound_lapse_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_bound_lapse_keep | — | 59062146 | 62015254 | new |
| grimworld_logic::test_tick::test_cost_bound_lapse_keep_fixture | — | 55847910 | 58640306 | new |
| grimworld_logic::test_tick::test_cost_bound_mixed_first | — | 64801317 | 68041383 | new |
| grimworld_logic::test_tick::test_cost_bound_mixed_first_fixture | — | 56032140 | 58833747 | new |
| grimworld_logic::test_tick::test_cost_bound_mixed_last | — | 64723637 | 67959819 | new |
| grimworld_logic::test_tick::test_cost_bound_mixed_last_fixture | — | 55954450 | 58752173 | new |
| grimworld_logic::test_tick::test_cost_bound_recovering | — | 58322783 | 61238923 | new |
| grimworld_logic::test_tick::test_cost_bound_recovering_fixture | — | 55848870 | 58641314 | new |
| grimworld_logic::test_tick::test_cost_bound_recovery_end | 62700996 | 58890176 | 61834685 | -6.1 % |
| grimworld_logic::test_tick::test_cost_bound_recovery_end_fixture | 57874340 | 55798260 | 58588173 | -3.6 % |
| grimworld_logic::test_tick::test_cost_fixture_candidates | 43734090 | 41730090 | 43816595 | -4.6 % |
| grimworld_logic::test_tick::test_cost_fixture_representative_words | 7512510 | 7105100 | 7460355 | -5.4 % |
| grimworld_logic::test_tick::test_cost_fixture_worst | 57923470 | 55847390 | 58639760 | -3.6 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_8 | 9430690 | 9198290 | 9658205 | -2.5 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_batch | 57924060 | 55847980 | 58640379 | -3.6 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_permuted | 58287780 | 56211700 | 59022285 | -3.6 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_words | 64608610 | 57836080 | 60727884 | -10.5 % |
| grimworld_logic::test_tick::test_cost_fixture_worst_words_twice | 129205120 | 115660060 | 121443063 | -10.5 % |
| grimworld_logic::test_tick::test_cost_library_baseline | 136558883 | 119310973 | 125276522 | -12.6 % |
| grimworld_logic::test_tick::test_cost_library_baseline_all_dead | — | 113480923 | 119154970 | new |
| grimworld_logic::test_tick::test_cost_library_baseline_batch | 64617240 | 57844710 | 60736946 | -10.5 % |
| grimworld_logic::test_tick::test_cost_library_baseline_kills | — | 119649723 | 125632210 | new |
| grimworld_logic::test_tick::test_cost_library_baseline_representative | 7523020 | 7115610 | 7471391 | -5.4 % |
| grimworld_logic::test_tick::test_cost_library_baseline_two_members | — | 119860406 | 125853427 | new |
| grimworld_logic::test_tick::test_cost_library_call | 139136903 | 121888993 | 127983443 | -12.4 % |
| grimworld_logic::test_tick::test_cost_library_call_all_dead | — | 116804603 | 122644834 | new |
| grimworld_logic::test_tick::test_cost_library_call_batch | 175379570 | 146343720 | 153660906 | -16.6 % |
| grimworld_logic::test_tick::test_cost_library_call_batch_representative | 17133810 | 16324710 | 17140946 | -4.7 % |
| grimworld_logic::test_tick::test_cost_library_call_kills | — | 122942363 | 129089482 | new |
| grimworld_logic::test_tick::test_cost_library_call_two_members | — | 122456406 | 128579227 | new |
| grimworld_logic::test_tick::test_cost_load_bound | — | 64551570 | 67779149 | new |
| grimworld_logic::test_tick::test_cost_load_bound_fixture | — | 11084960 | 11639208 | new |
| grimworld_logic::test_tick::test_cost_load_bound_two_members | — | 74457490 | 78180365 | new |
| grimworld_logic::test_tick::test_cost_load_bound_two_members_fixture | — | 20348660 | 21366093 | new |
| grimworld_logic::test_tick::test_cost_load_member_potions | 5286060 | 5227100 | 5488455 | -1.1 % |
| grimworld_logic::test_tick::test_cost_load_member_skills | 5622720 | 5537520 | 5814396 | -1.5 % |
| grimworld_logic::test_tick::test_cost_load_store_worst | 189126180 | 168808590 | 177249020 | -10.7 % |
| grimworld_logic::test_tick::test_cost_path_goblin_above | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_above_full | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_adrenaline_zero | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_below | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_below_dead | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_down | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_down_dead | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_effect_over | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_effect_zero | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_energy_capped | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_engaged | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_store_changed | — | 582960 | 612108 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_store_same | — | 582960 | 612108 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_up | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_goblin_up_full | — | 316230 | 332042 | new |
| grimworld_logic::test_tick::test_cost_path_line_falling | — | 21620 | 22701 | new |
| grimworld_logic::test_tick::test_cost_path_line_rising | — | 21620 | 22701 | new |
| grimworld_logic::test_tick::test_cost_path_member_above | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_above_full | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_adrenaline_zero | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_below | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_below_dead | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_down | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_down_dead | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_effects_over | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_effects_zero | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_energy_capped | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_engaged | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_store_changed | — | 9318220 | 9784131 | new |
| grimworld_logic::test_tick::test_cost_path_member_store_same | — | 9318220 | 9784131 | new |
| grimworld_logic::test_tick::test_cost_path_member_up | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_path_member_up_full | — | 4695380 | 4930149 | new |
| grimworld_logic::test_tick::test_cost_sheet_caste | — | 365130 | 383387 | new |
| grimworld_logic::test_tick::test_cost_sheet_caste_fixture | — | 336250 | 353063 | new |
| grimworld_logic::test_tick::test_cost_sheet_potion_damage | — | 30870 | 32414 | new |
| grimworld_logic::test_tick::test_cost_sheet_potion_fixture | — | 19670 | 20654 | new |
| grimworld_logic::test_tick::test_cost_sheet_potion_regen | — | 31070 | 32624 | new |
| grimworld_logic::test_tick::test_cost_sheet_potion_regen_negative | — | 31070 | 32624 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_damage_then_empty | — | 50720 | 53256 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_empty | — | 47270 | 49634 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_fixture | — | 23950 | 25148 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_none | — | 55740 | 58527 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_first | — | 56410 | 59231 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_second | — | 59660 | 62643 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_third | — | 62910 | 66056 | new |
| grimworld_logic::test_tick::test_cost_sheet_skill_regen_third_negative | — | 64150 | 67358 | new |
| grimworld_logic::test_tick::test_cost_sheets | 421470 | 404080 | 424284 | -4.1 % |
| grimworld_logic::test_tick::test_cost_sheets_unpacked | 538030 | 536590 | 562464 | -0.3 % |
| grimworld_logic::test_tick::test_cost_tick_representative | 7547547 | 7570797 | 7924925 | +0.3 % |
| grimworld_logic::test_tick::test_cost_tick_worst | 70336563 | 64556493 | 67784318 | -8.2 % |
| grimworld_logic::test_tick::test_cost_tick_worst_8 | 11763513 | 11448463 | 12020887 | -2.7 % |
| grimworld_logic::test_tick::test_cost_tick_worst_permuted | 70713583 | 64934653 | 68181386 | -8.2 % |
| grimworld_logic::test_tick::test_deaths_in_step_3 | 6257568 | 6289978 | 6545520 | +0.5 % |
| grimworld_logic::test_tick::test_defeat | 10260579 | 10277159 | 10753238 | +0.2 % |
| grimworld_logic::test_tick::test_deterministic | 356445600 | 278017840 | 291918732 | -22.0 % |
| grimworld_logic::test_tick::test_example_activated_attack_cost | 16451013 | 16564013 | 17215972 | +0.7 % |
| grimworld_logic::test_tick::test_example_burning_goblin | 5835094 | 5876854 | 6091674 | +0.7 % |
| grimworld_logic::test_tick::test_example_condition_degeneration | 6158176 | 6220816 | 6421670 | +1.0 % |
| grimworld_logic::test_tick::test_example_interrupt | 5918922 | 5951802 | 6188461 | +0.6 % |
| grimworld_logic::test_tick::test_example_lapse | 11254254 | 11205154 | 11763438 | -0.4 % |
| grimworld_logic::test_tick::test_example_member_activation | 14852416 | 14812576 | 15553205 | -0.3 % |
| grimworld_logic::test_tick::test_flags_cleared | 4838983 | 4844053 | 5071745 | +0.1 % |
| grimworld_logic::test_tick::test_goblin_load | 773660 | 753620 | 789285 | -2.6 % |
| grimworld_logic::test_tick::test_hold_eviction_and_stance | 7412620 | 7186920 | 7546266 | -3.0 % |
| grimworld_logic::test_tick::test_hold_refresh | 7283520 | 7064120 | 7417326 | -3.0 % |
| grimworld_logic::test_tick::test_hot_decoders | 5027830 | 4992190 | 5241800 | -0.7 % |
| grimworld_logic::test_tick::test_library_matches_pipeline | 276071306 | 241575486 | 253654261 | -12.5 % |
| grimworld_logic::test_tick::test_load_store | 11026010 | 10710610 | 11246141 | -2.9 % |
| grimworld_logic::test_tick::test_member_down_before_the_tick | 5025410 | 5025310 | 5276576 | -0.0 % |
| grimworld_logic::test_tick::test_regeneration | 10125689 | 10068819 | 10426415 | -0.6 % |
| grimworld_logic::test_tick::test_regeneration_extremes | 9664226 | 9674366 | 10129063 | +0.1 % |
| grimworld_logic::test_tick::test_sheets_read_oracle | 1330040 | 1294990 | 1359740 | -2.6 % |
| grimworld_logic::test_tick::test_who_acts | 7183999 | 7195079 | 7526095 | +0.2 % |
| grimworld_logic::test_tick::test_world_assert_awake | — | 7398433 | 7768355 | new |
| grimworld_persistent::test_accounts::test_create_adventurer | 23814770 | 23811380 | 25001949 | -0.0 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9182290 | 9181560 | 9640638 | -0.0 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9183540 | 9182920 | 9642066 | -0.0 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19362540 | 19362310 | 20330426 | -0.0 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7543960 | 7542490 | 7919615 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40808400 | 40805310 | 42845576 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 13906240 | 13903460 | 14598633 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 12910610 | 12908190 | 13553600 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 27992030 | 27987420 | 29386791 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24226700 | 24220310 | 25431326 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 12991790 | 12989010 | 13638461 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13314380 | 13311960 | 13977558 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13290890 | 13288470 | 13952894 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21157440 | 21150580 | 22208109 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49431320 | 49421170 | 51892229 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23818770 | 23815850 | 25006643 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40862100 | 40858910 | 42901856 | -0.0 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 16951760 | 16946950 | 17794298 | -0.0 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13310810 | 13306590 | 13971920 | -0.0 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 12916700 | 12913920 | 13559616 | -0.0 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18600160 | 18596920 | 19526766 | -0.0 % |
| grimworld_persistent::test_accounts::test_register | 14870290 | 14869670 | 15613154 | -0.0 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9026020 | 9026120 | 9477321 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27387010 | 27381340 | 28750407 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21108540 | 21104560 | 22159788 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21413900 | 21410850 | 22481393 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42710230 | 42704150 | 44839358 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14681310 | 14680820 | 15414861 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12715600 | 12714620 | 13350351 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13041830 | 13040490 | 13692515 | -0.0 % |
| grimworld_persistent::test_accounts::test_stored_words | 579000 | 577200 | 606060 | -0.3 % |
| grimworld_persistent::test_build::test_attributes_indices | 71865180 | 71784330 | 75373547 | -0.1 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 74866690 | 74764130 | 78502337 | -0.1 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 67617850 | 67537370 | 70914239 | -0.1 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 65802880 | 65728280 | 69014694 | -0.1 % |
| grimworld_persistent::test_build::test_bar_elite | 69501740 | 69416840 | 72887682 | -0.1 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 69096090 | 69014190 | 72464900 | -0.1 % |
| grimworld_persistent::test_build::test_bar_profession | 66582710 | 66507370 | 69832739 | -0.1 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 68063840 | 67986280 | 71385594 | -0.1 % |
| grimworld_persistent::test_build::test_belt_items | 67626240 | 67549040 | 70926492 | -0.1 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 70690664 | 70602784 | 74132924 | -0.1 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 69388187 | 69304847 | 72770090 | -0.1 % |
| grimworld_persistent::test_build::test_set_build_empty | 66824781 | 66746241 | 70083554 | -0.1 % |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 68306370 | 68220990 | 71632040 | -0.1 % |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 65852070 | 65777130 | 69065987 | -0.1 % |
| grimworld_persistent::test_build::test_set_build_parts | 68776951 | 68692931 | 72127578 | -0.1 % |
| grimworld_persistent::test_build::test_set_build_worst_case | 66050081 | 65974201 | 69272912 | -0.1 % |
| grimworld_persistent::test_build_words::test_known_skills_bits | 164100 | 160860 | 168903 | -2.0 % |
| grimworld_persistent::test_layout::test_account_and_adventurer_layout | 319110 | 317670 | 333554 | -0.5 % |
| grimworld_persistent::test_layout::test_item_grimoire_rift_layout | 350080 | 346320 | 363636 | -1.1 % |
| grimworld_persistent::test_layout::test_item_slot_and_hands | 180660 | 180300 | 189315 | -0.2 % |
| grimworld_persistent::test_layout::test_market_layout | 197570 | 196130 | 205937 | -0.7 % |
| grimworld_persistent::test_lifecycle::test_enter | 36173250 | 36145800 | 37953090 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 42321260 | 42273000 | 44386650 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 31504620 | 31479920 | 33053916 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 43934100 | 43874610 | 46068341 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 34681440 | 34651940 | 36384537 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 35587011 | 35554351 | 37332069 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_report_open | 35076812 | 35043182 | 36795342 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 35628584 | 35576424 | 37355246 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 35269309 | 35235669 | 36997453 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 36544242 | 36508302 | 38333718 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 24625590 | 24604850 | 25835093 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 28231460 | 28212060 | 29622663 | -0.1 % |
| grimworld_persistent::test_lifecycle::test_travel | 33172397 | 33143657 | 34800840 | -0.1 % |
| grimworld_persistent::test_read_cost::test_read_cost_baseline | 8252020 | 8237540 | 8649417 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_1 | 8452580 | 8438100 | 8860005 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_2 | 8506600 | 8492120 | 8916726 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_8 | 8830720 | 8816240 | 9257052 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_eight_calls | 9501170 | 9486690 | 9961025 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_1 | 8290920 | 8276440 | 8690262 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_8 | 8478250 | 8463770 | 8886959 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_one_call_one_read | 8385450 | 8370970 | 8789519 | -0.2 % |
| grimworld_persistent::test_read_cost::test_read_cost_two_calls | 8579870 | 8565390 | 8993660 | -0.2 % |
| grimworld_persistent::test_registry::test_bundle_version_and_order | 7127060 | 7120920 | 7476966 | -0.1 % |
| grimworld_persistent::test_registry::test_gas_set_record_changed | 3682770 | 3679830 | 3863822 | -0.1 % |
| grimworld_persistent::test_registry::test_gas_set_record_new | 3199720 | 3198120 | 3358026 | -0.1 % |
| grimworld_persistent::test_registry::test_missing_record_reads_zeros | 2943360 | 2941760 | 3088848 | -0.1 % |
| grimworld_persistent::test_registry::test_set_admin_hands_over | 3037050 | 3032630 | 3184262 | -0.1 % |
| grimworld_persistent::test_registry::test_set_admin_refused | 2718460 | 2716860 | 2852703 | -0.1 % |
| grimworld_persistent::test_registry::test_set_record_composite_needs_parent | 7068530 | 7065250 | 7418513 | -0.0 % |
| grimworld_persistent::test_registry::test_set_record_existing_changes | 4474080 | 4469140 | 4692597 | -0.1 % |
| grimworld_persistent::test_registry::test_set_record_id_zero_refused | 1171760 | 1166440 | 1224762 | -0.5 % |
| grimworld_persistent::test_registry::test_set_record_new_sequential | 4405610 | 4402010 | 4622111 | -0.1 % |
| grimworld_persistent::test_registry::test_set_record_not_live_refused | 2101080 | 2087860 | 2192253 | -0.6 % |
| grimworld_persistent::test_registry::test_set_record_not_next_refused | 3235250 | 3216060 | 3376863 | -0.6 % |
| grimworld_persistent::test_registry::test_set_record_outline_chunk_refused | 4191460 | 4189860 | 4399353 | -0.0 % |
| grimworld_persistent::test_registry::test_set_record_part_count_refused | 1646650 | 1638750 | 1720688 | -0.5 % |
| grimworld_persistent::test_registry::test_set_record_quiver_ids | 3604410 | 3604570 | 3784631 | +0.0 % |
| grimworld_persistent::test_registry::test_set_record_quotas_keyed_by_location | 5339330 | 5335970 | 5602769 | -0.1 % |
| grimworld_persistent::test_registry::test_set_record_refused_to_others | 1262730 | 1260150 | 1323158 | -0.2 % |
| grimworld_persistent::test_registry::test_version_rises_per_changed_record | 8363030 | 8353130 | 8770787 | -0.1 % |
| grimworld_persistent::test_seed::test_gas_seed_write | 19432660 | 19414980 | 20385729 | -0.1 % |
| grimworld_persistent::test_seed::test_seed_written_and_read_back | 21464410 | 21441290 | 22513355 | -0.1 % |
| grimworld_persistent::test_words::test_balance_pages | 278120 | 283660 | 292026 | +2.0 % |
| grimworld_persistent::test_words::test_belt_word | 86170 | 85450 | 89723 | -0.8 % |
| grimworld_persistent::test_words::test_core_words | 172950 | 172230 | 180842 | -0.4 % |
| grimworld_persistent::test_words::test_credit_overflow_refused | 45400 | 45040 | 47292 | -0.8 % |
| grimworld_persistent::test_words::test_debit_too_much_refused | 45100 | 44740 | 46977 | -0.8 % |
| grimworld_persistent::test_words::test_experience_overflow_refused | 74560 | 74200 | 77910 | -0.5 % |
| grimworld_persistent::test_words::test_place_words | 2552765 | 2541665 | 2668749 | -0.4 % |


## Fix loop 1

**Inputs:**
- two audits of #196 at 6849922, both FAIL:
  - cost, `[GPT-6-Astra]`: COST-READS, COST-BOUND, COST-LEVER-A;
  - quality, `[GPT-6-Sol]`: 1 the wiring, 2 REPORT.md, 3 the eight-goblin tests;
- the project manager's D-166, as the orchestrator relayed it:
  - the Hub wiring is CBT-02c's;
  - the goblin array's hot fields apart and a content index are CBT-02d's;
  - quality 1 and COST-LEVER-A are settled by D-166, and quality 2 is the project's convention (REPORT.md stays in the worktree).

`origin/main` is merged (ffac68b). **On main, `docs/decisions/2026-09-30-cbt-02b-wiring-and-bound.md` still reads "Decision: Pending", so I acted on D-166 as relayed.**

The fix is commit c80ed96. CI is green on it: every check passes, including `cairo (contracts)` (the tests, the gas budgets, the class sizes).

This section supersedes the figures above wherever they differ:
- the tick's bound: 8,834,287 → **8,750,367**;
- the content, per tick: 445,160 → **578,004**;
- the tick's share, per tick: 15,148,134 → **15,197,058**;
- the representative share: 1,104,546 → **1,161,750**.

### COST-BOUND: the mixed state's maximum, without a residual

**What was wrong.** The 11,790 "residual" was not the tick's: it came from the tests' own code. `test_cost_bound_mixed_last` asserts `goblin.recharge(3)` after the tick, a call its fixture test does not make, so fixture subtraction counted it into the term. Scratch tests (not committed) located it: within one consistent family of states, swapping the last goblin's branch changed the tick by exactly the single-goblin difference.

**Fix.**
- Every state of the tick's bound is now built by one builder (`term_world`: the 100-goblin array, the awake goblins at given indexes taking given branches, the member concluding and dying).
- Each is measured the same way: **the tick alone**, `get_available_gas` around `TickTrait::tick` inside the test, printed "gas tick" (`term_tick`). Neither a fixture nor a check after the tick enters a figure.
- New tests (`test_cost_term_*`, 31): no goblin (with either content, with two members); each of the 10 branches with 1 and with 8 goblins; a surviving conclusion; five mixes; three placements of the costliest mix.
- My first-pass tests that subtracted fixtures (`test_cost_bound_{lapse_keep,recovering,dead,knocked}`, `test_cost_bound_eight_*` but CBT-02's `eight_lapses`, `test_cost_bound_mixed_*`, `test_cost_bound_base_two_members`, each with its fixture) are replaced. CBT-02's own tests are untouched.

**Evidence** (`snforge test test_cost_term --max-threads 1`, the printed figures):

| Term | Value |
|---|---:|
| N, no goblin awake (`term_none`; `term_none_k3` the same, so the content's `k` changes nothing else) | 1,027,653 |
| R3, step 3's rebuild (from `one_activating`, then checked against `one_recovering`, `one_free`, `one_knocked`, `one_dead`, `one_conclude_*`: every one exact) | 1,333,870 |
| F, step 1's last rebuild (from `one_lapse`; checked on `one_lapse_keep`, `one_recovery_end`: exact) | 603,540 |
| d, per goblin: `(eight − one) / 7`, every one an integer | conclusion clearing 789,383; into a recovery 788,410; lapse 194,523; lapse keeping a later recharge 177,043; recovery over 55,943; free 46,563; knocked down 40,360; recovering 40,260; activating 39,960; dead 20,060; dying against surviving +200 |

The model T = N + R3·[a goblin awake] + F·[step 1's last write not a conclusion] + Σ d predicts every mixed state **to the unit**:

| State | Model | Measured |
|---|---:|---:|
| 7 conclusions, then a lapse | 8,685,267 | 8,685,267 |
| the same at the array's start | 8,685,267 | 8,685,267 |
| the same spread across the array | 8,685,267 | 8,685,267 |
| 7 conclusions, then an activating goblin | 7,927,164 | 7,927,164 |
| 7 conclusions, then a recovery over | 8,546,687 | 8,546,687 |
| 7 activating, then a lapse | 3,439,306 | 3,439,306 |
| a lapse, then 7 conclusions (no last rebuild) | 8,081,727 | 8,081,727 |

- **The maximum over every assignment of branches** is N + R3 + max(8 d_clear, 7 d_clear + F + d_lapse) = max(8,676,587, 8,685,267) = **8,685,267, reached** (`test_cost_term_mix_clear_lapse`).
- **The tick's upper bound is 8,685,267 + 65,100 = 8,750,367.** The one term not reached is the member's lookup, charged as a full scan (30 × 2,170), and labelled charged in ENG-01 §9.2. Every other term is measured and exact.
- **Before and after**:
  - before (6849922): the bound was 8,769,187 + 65,100, with a residual of 11,790 against its terms;
  - after (c80ed96): the model is exact on all seven mixed states and three placements.

### COST-READS: two-part records at their true cost

**What was wrong.** The content's reads were priced as 47 × 54,000 + 2 × 98,000 = 2,734,000 a batch. 54,000 is ENG-06's measure for a **one-part** `GATE` record, but the content has 38 two-part skills, 5 two-part castes and 4 one-part potions: 90 parts, not 47.

**Fix.** A `ContentProbe` (`test_read_cost.cairo`) reads the real record mix from the real `Registry` in `bundle` calls of at most `MAX_READ` = 32 records, as ENG-07 will. The setup is identical across its tests, and the probe alone is subtracted.

| Test | Measured | Net of the probe alone (84,340) | The old formula |
|---|---:|---:|---:|
| `test_content_read_worst`: 47 records, 90 parts, 2 calls | 4,146,780 | **4,062,440** | 2,734,000 (−33 %) |
| `test_content_read_representative`: 19 records, 37 parts, 1 call | 1,780,380 | **1,696,040** | 1,124,000 (−34 %) |

**Evidence.** Before the fix, the published content term was 2,734,000 + 1,717,600 = 4,451,600 a batch; the reads alone now measure 4,062,440, so the old term was below the cost it claimed to bound.

**After.**
- The content is 4,062,440 + 1,717,600 = 5,780,040 a batch: **578,004 a tick**.
- It assumes ENG-07 reads the batch's records in the fewest calls (2 for 47); each further call costs about 98,420 (ENG-06). ENG-01 §9.2 says so.

### Quality 3: the eight-goblin tests check their branch

**Fix.** `term_tick` checks, after the measured tick, that every awake goblin took its named branch:
- its activation field and deadline, and slot 3's recharge (a conclusion 69, a lapse 64, a kept later recharge 100, a recovery to 51);
- its death in step 3, or its survival;
- an awake goblin already dead left untouched;
- a knocked-down goblin still knocked down;
- the kills equal to those deaths, and the member down.

**Evidence.** I removed `goblin.lapse(caste, content)` from the pipeline, ran the tests, then restored the pipeline (`git checkout`, nothing committed):
- `test_cost_term_eight_lapse` and `test_cost_term_eight_lapse_keep` **fail** ('branch: field');
- a test in the old style, CBT-02's `test_cost_bound_eight_lapses`, which only counts the kills, **still passes**.

### Settled by D-166, not fixed here

- **Quality 1 (the wiring).** It stays reverted, as 5c437de left it; CBT-02c lands it.
- **COST-LEVER-A (the full-struct copies).** ENG-01 §9.2 now says the remaining copies and lookups go with CBT-02d. At 100 goblins those are the array rebuilds, about 600,000 each, up to 8 a tick plus step 3's, and load's lookups, about 410,000 a goblin.
- **Quality 2 (REPORT.md).** Per the relayed decision, the report stays in the worktree, as the project's convention is.

### Cost after fix loop 1

| Per tick inside a batch of 10 | Representative | Upper bound |
|---|---:|---:|
| The pipeline | 656,274 | 8,750,367 |
| Load, store and the call, / 10 | 264,636 | 5,868,687 |
| **Through one library call** | **920,910** | **14,619,054** |
| The content: reads measured, sheets at their costliest paths, / 10 | 240,840 | 578,004 |
| **The tick's share** | **1,161,750 (79.1 % of 1,469,435)** | **15,197,058 (10.3 ×)** |

The overrun is reported, not accepted.

Each further member (M-3) adds to a tick 172,603 (`term_none_two_members` − `term_none`) + 65,100. What it adds to load and store and to the call is unchanged from above.

### Commands run

```
$ git merge origin/main                    # ffac68b
$ cd contracts/logic && snforge test
Tests: 421 passed, 0 failed
$ snforge test test_cost_term --max-threads 1      # the printed "gas tick" figures above
Tests: 31 passed, 0 failed
$ cd contracts/persistent && snforge test
Tests: 156 passed, 0 failed
$ snforge test test_content_read --max-threads 1
content read, the probe alone: 84340
content read, 38 skills 5 castes 4 potions: 4146780
content read, 16 skills 2 castes 1 potion: 1780380
$ python3 scripts/gas_budgets.py && python3 scripts/gas_budgets.py --check
gas check: 630 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py
Instances 39.60 %, TickLibrary 24.32 %, Hub 42.83 % (every class ok)
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check     # clean
$ gh pr checks 196 --watch --interval 30
every check pass (indexer-node skipping); cairo (contracts) pass 2m49s
```

### Files changed in fix loop 1

- `contracts/logic/tests/test_tick.cairo`:
  - the `term_*` builder, the measured tick, the branch checks, 31 `test_cost_term_*` tests;
  - my first-pass branch, mix and two-member tests removed, with their fixtures;
  - the section's header comment.
- `contracts/persistent/tests/test_read_cost.cairo`: `ContentProbe` and three `test_content_read_*` tests.
- `docs/architecture/ENG-01-interfaces.md` §9.2: the bound 8,750,367 with its exact terms; the content's reads measured; the tick's share 15,197,058; CBT-02c and CBT-02d named for the wiring and the copies.
- `contracts/*/GAS.md`, `docs/BUDGETS.md`: generated.

### Gas table (fix loop 1)

**No budget is raised.**
- **New** (from `python3 scripts/gas_budgets.py --report`): the 31 `test_cost_term_*` and the 3 `test_content_read_*` tests, rows below.
- **Removed**, with their fixture twins: my first-pass `test_cost_bound_{lapse_keep,recovering,dead,knocked}`, `test_cost_bound_eight_*` (all but CBT-02's `eight_lapses`), `test_cost_bound_mixed_{last,first}` and `test_cost_bound_base_two_members`.
- Every other row is unchanged from the table above.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::test_tick::test_cost_term_eight_activating | — | 62795673 | 65935457 | new |
| grimworld_logic::test_tick::test_cost_term_eight_conclude_clear | — | 68786497 | 72225822 | new |
| grimworld_logic::test_tick::test_cost_term_eight_conclude_recover | — | 68776393 | 72215213 | new |
| grimworld_logic::test_tick::test_cost_term_eight_dead | — | 62634793 | 65766533 | new |
| grimworld_logic::test_tick::test_cost_term_eight_free | — | 62848417 | 65990838 | new |
| grimworld_logic::test_tick::test_cost_term_eight_knocked | — | 62800313 | 65940329 | new |
| grimworld_logic::test_tick::test_cost_term_eight_lapse | — | 64632677 | 67864311 | new |
| grimworld_logic::test_tick::test_cost_term_eight_lapse_keep | — | 64494357 | 67719075 | new |
| grimworld_logic::test_tick::test_cost_term_eight_recovering | — | 62798793 | 65938733 | new |
| grimworld_logic::test_tick::test_cost_term_eight_recovery_end | — | 63526997 | 66703347 | new |
| grimworld_logic::test_tick::test_cost_term_mix_activating_lapse | — | 63552026 | 66729628 | new |
| grimworld_logic::test_tick::test_cost_term_mix_clear_activating | — | 68036274 | 71438088 | new |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse | — | 68793997 | 72233697 | new |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse_spread | — | 68777607 | 72216488 | new |
| grimworld_logic::test_tick::test_cost_term_mix_clear_lapse_start | — | 68792627 | 72232259 | new |
| grimworld_logic::test_tick::test_cost_term_mix_clear_recovery_end | — | 68655787 | 72088577 | new |
| grimworld_logic::test_tick::test_cost_term_mix_lapse_first | — | 68177317 | 71586183 | new |
| grimworld_logic::test_tick::test_cost_term_none | — | 57352703 | 60220339 | new |
| grimworld_logic::test_tick::test_cost_term_none_k3 | — | 57352703 | 60220339 | new |
| grimworld_logic::test_tick::test_cost_term_none_two_members | — | 57533276 | 60409940 | new |
| grimworld_logic::test_tick::test_cost_term_one_activating | — | 59205023 | 62165275 | new |
| grimworld_logic::test_tick::test_cost_term_one_conclude_clear | — | 59953876 | 62951570 | new |
| grimworld_logic::test_tick::test_cost_term_one_conclude_recover | — | 59952613 | 62950244 | new |
| grimworld_logic::test_tick::test_cost_term_one_conclude_recover_surviving | — | 59952893 | 62950538 | new |
| grimworld_logic::test_tick::test_cost_term_one_dead | — | 59184913 | 62144159 | new |
| grimworld_logic::test_tick::test_cost_term_one_free | — | 59211616 | 62172197 | new |
| grimworld_logic::test_tick::test_cost_term_one_knocked | — | 59205603 | 62165884 | new |
| grimworld_logic::test_tick::test_cost_term_one_lapse | — | 59962746 | 62960884 | new |
| grimworld_logic::test_tick::test_cost_term_one_lapse_keep | — | 59945456 | 62942729 | new |
| grimworld_logic::test_tick::test_cost_term_one_recovering | — | 59205413 | 62165684 | new |
| grimworld_logic::test_tick::test_cost_term_one_recovery_end | — | 59824536 | 62815763 | new |
| grimworld_persistent::test_read_cost::test_content_read_probe_alone | — | 58691870 | 61626464 | new |
| grimworld_persistent::test_read_cost::test_content_read_representative | — | 60413620 | 63434301 | new |
| grimworld_persistent::test_read_cost::test_content_read_worst | — | 62780020 | 65919021 | new |

