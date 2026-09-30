# [Opus 5.5] CBT-02c — Capacity checks at registration, and the flattening wired into `Hub`

## Summary

The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

**The scope's stop applies (D-166 (b)).** Wired into `Hub`, the linear flattening still takes `Hub`'s class to **61.15 %**, over ENG-01 §1.3's 50 %. Two size probes show that no arrangement fits:
- the wiring with a flattening that only copies the loadout: 46.20 %;
- the same plus the first pass and DS-2's floors: 51.42 %.

So the wiring was built, tested and measured (commit `4ca5802`), then held back as CBT-02b's was. `Hub`, its models and its wiring tests are `main`'s again. Moving the flattening into a library class needs a `set_contracts` change: that is the project manager's decision. **No production snapshot is written.**

What exists now that did not before:
- **Every per-record bound of design/20 is checked at registration.** `Registry.set_record` unpacks the record as its model and runs:
  - `MODIFIER`: `ModifierAssert::assert_legal`: DS-4 sources; DS-1 and DS-5 per-source bounds on the sum of the benefit and the cost; DS-23 piece health.
  - `ARMOR_SET`: `ArmorSetAssert::assert_legal`.
  - `SKILL` and `ITEM`: `assert_legal`, legal carriers including DS-20's one `ATTACK_BONUS`, and a potion unscaled.
  - `CASTE`: `CasteAssert::assert_legal` (DS-18, DS-29), plus the adrenaline (≤ 63 strikes) of each skill it names that the registry holds.

  A record past its bound is refused, whether it is new or a rewrite. The administrator pays once.
- **A linear flattening** (`SnapshotBuildTrait::build`, `contracts/logic/src/snapshot.cairo`), in two passes:
  - the first sums every additive passive into three felt words of biased signed 16-bit lanes (statistics, hits, damage types), one multiplication and one addition per word, with a table-driven lane per passive. It also counts the sources in one `u128`, checked with a single mask;
  - the second takes the passives that are not summed: rune health identity, attribute runes, quick-cast pairs, the lowest N, damage type, condition, halving.

  It checks only what a sum can break: the counts, one insignia per piece, instances numbered upward, the loadout's bounds, a quick-cast pair's attribute in the build, DS-2's floors, and each sum into its field (`fit`). On the widest build (17 sources, 32 passives) it costs **1,627,488**, against **10,687,280** for CBT-02's quadratic flattening (6.6× less).
- **The flattening's unit tests are in `snapshot.cairo`** (D-167):
  - design/20 §6's extremal builds, floors, saturations, rune identity and counts, each compared with CBT-02's flattening, kept in the tests as the oracle (CAIRO §2);
  - new tests: the signed lanes against the oracle (negative next to positive in every hit lane), the counts at their bounds, a second prefix, a third set bonus, instances out of order, the eight bar ranks, the quick-cast pairs, the passives not summed, and the benchmarks;
  - the snapshot layout tests, moved from `test_packing`.

  The eight-ranks test caught a real bug: the ranks' `u32` shift overflowed on the eighth slot. It is fixed.
- **The registry's refusal tests** (`test_registry::test_set_record_*`). Every row of design/20 §1.3 is tried at `lo` and `hi` (accepted) and at `hi + 1` and `lo − 1` (refused). Also tested: the DS-4 sources, the DS-23 pieces, a caste at its bounds and one unit beyond on each DS-18/DS-29 field, a skill of 64 strikes named by a caste, two attack bonuses, and illegal potions.
- **The wiring as measured** (history only, `4ca5802`). It is CBT-02b's (`0607c1d`) plus two per-item checks: a worn modifier must sit in its record's slot type, and its rolled value must lie within its record's range. Both are tested.

Pull request: https://github.com/bal7hazar/grimworld/pull/206. CI is green on every check (`cairo (contracts)`: tests, gas budgets, class sizes).

## Files changed

- `contracts/persistent/src/systems/registry.cairo`: `RegistryAssert::assert_content`, called by `set_record`.
- `contracts/logic/src/snapshot.cairo`:
  - the linear flattening (`FlattenTrait`, lanes, counts); `BuildAssert` reduced to the build's checks; errors;
  - `mod tests`: the flattening's tests with the oracle, the benchmarks, and the layout tests moved from `tests/`.
- `contracts/logic/tests/test_build.cairo`: the flattening's tests moved out (the validators' tests stay); `test_five_insignias_at_15_refused` and `test_instance_of_two_kinds_refused` removed (see *Deviations*).
- `contracts/logic/tests/test_packing.cairo`: the snapshot's layout tests moved out.
- `contracts/persistent/tests/test_registry.cairo`: the content checks' refusal tests; budgets.
- `contracts/persistent/tests/{test_build,test_lifecycle,test_read_cost}.cairo`: potion fixtures with a legal entry, which the registry now requires; budgets.
- `contracts/tools/lifecycle_probe.py`: the potions' legal entry. `contracts/tools/lifecycle-probe-output.txt`: re-run; the figures are `main`'s, only the hashes changed.
- `docs/architecture/ENG-01-interfaces.md`: §1.3 (the flattening and `Hub`, the size table), §3.5 (the content's checks), §9.3 (`set_record`'s reads; `set_build` and `enter` unchanged).
- `contracts/{logic,persistent,ephemeral}/GAS.md`, `docs/BUDGETS.md`: generated.
- In the branch's history only (`4ca5802`, held back by `47c7a33`): `hub.cairo`, `models/item.cairo` (`held`, `ItemModsAssert::assert_slot`, `assert_value`), `models/adventurer.cairo` (`loadout`), and the persistent wiring tests.

## Commands run

```
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
    Finished `dev` profile target(s) in 26 seconds
$ cd contracts/logic && snforge test         → Tests: 435 passed, 0 failed
$ cd contracts/persistent && snforge test    → Tests: 161 passed, 0 failed
$ cd contracts/ephemeral && snforge test     → Tests: 53 passed, 0 failed
$ python3 scripts/gas_budgets.py --check     # origin/main fetched
gas check: 648 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py     (exit 0)
| grimworld_persistent | `Registry` | 622,974 | 9,981 | 23,296 | 28.44 % | ok |
| grimworld_persistent | `Hub` | 942,926 | 14,203 | 35,084 | 42.83 % | ok |
| grimworld_ephemeral | `Instances` | 828,459 | 12,078 | 32,444 | 39.60 % | ok |
| grimworld_logic | `TickLibrary` | 491,811 | 7,170 | 19,923 | 24.32 % | ok |
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check   (exit 0)
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt
exit 0, 22 transactions SUCCEEDED; set_build 2,611,200, enter (belt worst case) 5,382,400: main's
$ gh pr checks 206 --watch --interval 30     → every check pass (indexer-node skipping); cairo (contracts) 2m33s
```

**`gas_budgets.py` and `src/`** (the brief): its `declared` walks `src/` as well as `tests/`. `--check` is green on the 43 tests now in `grimworld_logic::snapshot::tests`, which are listed in `contracts/logic/GAS.md` under their module path.

**`Hub`'s class, measured on each version** (`class_sizes.py`, CASM felts):

| `Hub` with | Felts | Share |
|---|---:|---:|
| no flattening (`main`, this PR) | 35,084 | 42.83 % |
| CBT-02b's quadratic flattening, wired | 65,398 | 79.83 % |
| my first linear version (one pass, a branch per statistic), wired (`7cec6f6`) | 54,297 | 66.28 % |
| the lanes version, wired (`4ca5802`) | **50,091** | **61.15 %** |
| the lanes version with `fit` not inlined and one `multi_pop_front` per word (tried, dropped) | 53,374 | 65.15 % |
| probe: the wiring with a flattening that only copies the loadout | 37,848 | 46.20 % |
| probe: that plus the first pass (sums, counts) and DS-2's floors | 42,123 | 51.42 % |
| `Registry` without the content's checks / with them | 5,234 / 23,296 | 6.39 % / 28.44 % |

**The wiring against D-158** (`4ca5802`: snforge for the calls, `Instances` a double for `enter`; the node for the transaction bases; converted as CBT-08a and CBT-02b did, node belt case + snforge delta):

| | `main` | CBT-02b (quadratic) | CBT-02c (linear) | D-158 |
|---|---:|---:|---:|---:|
| `set_build`, worst case (15 modifiers, 30 passives), the call | 2,960,731 | 17,455,710 | **7,200,913** | 3,108,768 |
| … without the flattening's call (the reads and the held list alone) | — | — | 6,045,605 | — |
| `set_build`, 4 potions on 4 pages alone, the call | — | — | 1,779,463 | — |
| `set_build`, 4 potions, no equipment (node, transaction) | 2,611,200 | 2,811,200 | 2,811,200 | — |
| **`set_build`, worst case, as a transaction** | ~3.8 M | ~18.5 M | **≈ 8.23 M** (2,811,200 + 5,421,450) | 3,798,150 net |
| `enter`, worst case (the belt and 15 modifiers), the call | — | 17,403,978 | **7,149,181** | — |
| `enter`, the belt alone, the call | — | — | 2,672,213 | — |
| `enter`, later entry, no belt (node) | 4,702,400 | 5,142,400 | 5,502,400 | 4,513,259 net |
| `enter`, the belt's worst case (node) | 5,382,400 | 5,862,400 | 6,182,400 | 5,250,000 |
| **`enter`, worst case, as a transaction** | — | ~20.6 M | **≈ 10.66 M** (6,182,400 + 4,476,968) | 5,250,000 |

The wired `set_build` worst case breaks down as:
- `main`'s 2.96 M;
- **≈ 3.08 M** for reading the 7 `ItemMods` and the 15 `MODIFIER` records in the one `bundle` and building the held list (6,045,605 − 2,960,731);
- **≈ 1.16 M** for the flattening (7,200,913 − 6,045,605).

`enter` without equipment costs more than with CBT-02b's quadratic version (5,502,400 against 5,142,400, node). The flattening's fixed part is larger: the empty build measures 384,423 against the oracle's 254,770 (snforge, fixture included).

## Cost

### The flattening (snforge, `snapshot::tests`)

| Algorithm | L2 gas | How |
|---|---:|---|
| Linear flattening, widest build (17 sources, 32 passives, costliest paths) | **1,627,488** | `test_cost_build_widest` − `test_cost_build_baseline` (1,915,658 − 288,170) |
| CBT-02's quadratic flattening, same build, its checks excluded | 10,687,280 | `test_cost_oracle_widest` − baseline |
| Linear flattening, empty build | 384,423 | `test_cost_build_empty` (the loadout fixture included) |
| CBT-02's, empty build | 254,770 | `test_cost_oracle_empty` |

### Gas table

`python3 scripts/gas_budgets.py --report`, `origin/main` fetched. These are the 171 rows this lot touched; the other 507 are `unchanged`.

- **23 budgets are raised.** Each is a test that deploys the `Registry` and writes content through `set_record`, which now checks each record and has a larger class to deploy. The reason is written above each attribute: `// gas: raised, D-166: the Registry checks each record (CBT-02c), its class deploys dearer`.
- The `test_read_cost` probes write 38 skills, 5 castes (each reading its skills) and 4 potions: +27.5 to +29.4 %.
- `test_build`'s setup writes 11 skills and 22 items: about +8 %.
- The registry's refusal tests: +10.8 to +32.7 %, mostly the deploy.
- No entrypoint of `Hub` changed. The `removed` rows are tests moved into `snapshot::tests` (new rows above them), plus the two removed tests below.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::snapshot::tests::test_bar_and_kit_layout | — | 379250 | 398213 | new |
| grimworld_logic::snapshot::tests::test_bar_armor_above_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_bar_armor_below_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_bar_passives_layout | — | 798490 | 838415 | new |
| grimworld_logic::snapshot::tests::test_bar_quick_cast_attribute_refused | — | 81210 | 85271 | new |
| grimworld_logic::snapshot::tests::test_cost_build_baseline | — | 288170 | 302579 | new |
| grimworld_logic::snapshot::tests::test_cost_build_empty | — | 384423 | 403645 | new |
| grimworld_logic::snapshot::tests::test_cost_build_widest | — | 1915658 | 2011441 | new |
| grimworld_logic::snapshot::tests::test_cost_oracle_empty | — | 254770 | 267509 | new |
| grimworld_logic::snapshot::tests::test_cost_oracle_widest | — | 10975450 | 11524223 | new |
| grimworld_logic::snapshot::tests::test_counts_at_bounds | — | 4084278 | 4288492 | new |
| grimworld_logic::snapshot::tests::test_envelope_builds | — | 11876303 | 12470119 | new |
| grimworld_logic::snapshot::tests::test_extremal_max_energy_and_rank | — | 2374153 | 2492861 | new |
| grimworld_logic::snapshot::tests::test_extremal_max_health | — | 4063098 | 4266253 | new |
| grimworld_logic::snapshot::tests::test_extremal_weapon | — | 1567946 | 1646344 | new |
| grimworld_logic::snapshot::tests::test_floor_energy_regen_refused | — | 743443 | 780616 | new |
| grimworld_logic::snapshot::tests::test_floor_max_energy_refused | — | 743443 | 780616 | new |
| grimworld_logic::snapshot::tests::test_floor_max_health_refused | — | 547723 | 575110 | new |
| grimworld_logic::snapshot::tests::test_instances_out_of_order_refused | — | 187836 | 197228 | new |
| grimworld_logic::snapshot::tests::test_kit_condition_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_kit_knockdown_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_kit_passives_layout | — | 616100 | 646905 | new |
| grimworld_logic::snapshot::tests::test_kit_percent_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_lanes_against_the_oracle | — | 3518159 | 3694067 | new |
| grimworld_logic::snapshot::tests::test_other_fields_within_envelopes | — | 5341908 | 5609004 | new |
| grimworld_logic::snapshot::tests::test_passives_not_summed | — | 1317633 | 1383515 | new |
| grimworld_logic::snapshot::tests::test_quick_cast_attribute_not_held_refused | — | 185073 | 194327 | new |
| grimworld_logic::snapshot::tests::test_quick_cast_pairs | — | 1068843 | 1122286 | new |
| grimworld_logic::snapshot::tests::test_ranks_of_every_bar_slot | — | 1172293 | 1230908 | new |
| grimworld_logic::snapshot::tests::test_repeated_rune_id | — | 1725493 | 1811768 | new |
| grimworld_logic::snapshot::tests::test_rune_attribute_contribution | — | 1314813 | 1380554 | new |
| grimworld_logic::snapshot::tests::test_rune_identity | — | 2180926 | 2289973 | new |
| grimworld_logic::snapshot::tests::test_saturation | — | 10720092 | 11256097 | new |
| grimworld_logic::snapshot::tests::test_second_prefix_refused | — | 184953 | 194201 | new |
| grimworld_logic::snapshot::tests::test_sixth_rune_refused | — | 264863 | 278107 | new |
| grimworld_logic::snapshot::tests::test_stats_armor_vs_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_stats_health_regen_20_packs | — | 107730 | 113117 | new |
| grimworld_logic::snapshot::tests::test_stats_health_regen_21_refused | — | 15520 | 16296 | new |
| grimworld_logic::snapshot::tests::test_stats_layout | — | 553910 | 579516 | new |
| grimworld_logic::snapshot::tests::test_task_page_layout | — | 141890 | 148985 | new |
| grimworld_logic::snapshot::tests::test_third_set_bonus_refused | — | 201653 | 211736 | new |
| grimworld_logic::snapshot::tests::test_two_insignias_on_a_piece_refused | — | 190119 | 199625 | new |
| grimworld_logic::snapshot::tests::test_widest_against_the_oracle | — | 12667928 | 13301325 | new |
| grimworld_persistent::test_accounts::test_create_adventurer | 23811380 | 23814490 | 25001949 | +0.0 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9181560 | 9184670 | 9640638 | +0.0 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9182920 | 9186030 | 9642066 | +0.0 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19362310 | 19365420 | 20330426 | +0.0 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7542490 | 7545600 | 7919615 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40805310 | 40808420 | 42845576 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 13903460 | 13906570 | 14598633 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 12908190 | 12911300 | 13553600 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 27987420 | 27990530 | 29386791 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24220310 | 24223420 | 25431326 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 12989010 | 12992120 | 13638461 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13311960 | 13315070 | 13977558 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13288470 | 13291580 | 13952894 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21150580 | 21153690 | 22208109 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49421170 | 49424280 | 51892229 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23815850 | 23818960 | 25006643 | +0.0 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40858910 | 40862020 | 42901856 | +0.0 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 16946950 | 16950060 | 17794298 | +0.0 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13306590 | 13309700 | 13971920 | +0.0 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 12913920 | 12917030 | 13559616 | +0.0 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18596920 | 18600030 | 19526766 | +0.0 % |
| grimworld_persistent::test_accounts::test_register | 14869670 | 14872780 | 15613154 | +0.0 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9026120 | 9029230 | 9477321 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27381340 | 27384450 | 28750407 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21104560 | 21107670 | 22159788 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21410850 | 21413960 | 22481393 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42704150 | 42707260 | 44839358 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14680820 | 14683930 | 15414861 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12714620 | 12717730 | 13350351 | +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13040490 | 13043600 | 13692515 | +0.0 % |
| grimworld_persistent::test_build::test_attributes_indices | 71784330 | 77533020 | 81409671 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.0 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 74764130 | 80512820 | 84538461 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +7.7 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 67537370 | 73286060 | 76950363 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.5 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 65728280 | 71476970 | 75050819 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.7 % |
| grimworld_persistent::test_build::test_bar_elite | 69416840 | 75165530 | 78923807 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.3 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 69014190 | 74762880 | 78501024 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.3 % |
| grimworld_persistent::test_build::test_bar_profession | 66507370 | 72256060 | 75868863 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.6 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 67986280 | 73734970 | 77421719 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.5 % |
| grimworld_persistent::test_build::test_belt_items | 67549040 | 73297730 | 76962617 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.5 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 70602784 | 76351474 | 80169048 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.1 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 69304847 | 75053537 | 78806214 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.3 % |
| grimworld_persistent::test_build::test_set_build_empty | 66746241 | 72494931 | 76119678 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.6 % |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 68220990 | 73969680 | 77668164 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.4 % |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 65777130 | 71525820 | 75102111 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.7 % |
| grimworld_persistent::test_build::test_set_build_parts | 68692931 | 74441621 | 78163703 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.4 % |
| grimworld_persistent::test_build::test_set_build_worst_case | 65974201 | 71722891 | 75309036 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +8.7 % |
| grimworld_persistent::test_lifecycle::test_enter | 36145800 | 36183120 | 37953090 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 42273000 | 43476660 | 44386650 | +2.8 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 31479920 | 31517240 | 33053916 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 43874610 | 43911930 | 46068341 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 34651940 | 34689260 | 36384537 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 35554351 | 35591671 | 37332069 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_open | 35043182 | 35080502 | 36795342 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 35576424 | 35613744 | 37355246 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 35235669 | 35272989 | 36997453 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 36508302 | 36545622 | 38333718 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 24604850 | 24642170 | 25835093 | +0.2 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 28212060 | 28249380 | 29622663 | +0.1 % |
| grimworld_persistent::test_lifecycle::test_travel | 33143657 | 33180977 | 34800840 | +0.1 % |
| grimworld_persistent::test_read_cost::test_content_read_probe_alone | 58691870 | 75951350 | 79748918 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +29.4 % |
| grimworld_persistent::test_read_cost::test_content_read_representative | 60413620 | 77673100 | 81556755 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +28.6 % |
| grimworld_persistent::test_read_cost::test_content_read_worst | 62780020 | 80039500 | 84041475 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +27.5 % |
| grimworld_persistent::test_read_cost::test_read_cost_baseline | 8237540 | 8262420 | 8649417 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_1 | 8438100 | 8462980 | 8860005 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_2 | 8492120 | 8517000 | 8916726 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_8 | 8816240 | 8841120 | 9257052 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_eight_calls | 9486690 | 9511570 | 9961025 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_1 | 8276440 | 8301320 | 8690262 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_8 | 8463770 | 8488650 | 8886959 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_one_call_one_read | 8370970 | 8395850 | 8789519 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_two_calls | 8565390 | 8590270 | 8993660 | +0.3 % |
| grimworld_persistent::test_registry::test_bundle_version_and_order | 7120920 | 7133360 | 7476966 | +0.2 % |
| grimworld_persistent::test_registry::test_gas_set_record_changed | 3679830 | 3686050 | 3863822 | +0.2 % |
| grimworld_persistent::test_registry::test_gas_set_record_new | 3198120 | 3201230 | 3358026 | +0.1 % |
| grimworld_persistent::test_registry::test_gas_set_record_unchanged | 3476910 | 3483130 | 3650756 | +0.2 % |
| grimworld_persistent::test_registry::test_missing_record_reads_zeros | 2941760 | 2944870 | 3088848 | +0.1 % |
| grimworld_persistent::test_registry::test_set_admin_hands_over | 3032630 | 3172440 | 3184262 | +4.6 % |
| grimworld_persistent::test_registry::test_set_admin_refused | 2716860 | 2719970 | 2852703 | +0.1 % |
| grimworld_persistent::test_registry::test_set_record_carriers | — | 7388450 | 7757873 | new |
| grimworld_persistent::test_registry::test_set_record_caste_bounds | — | 11710690 | 12296225 | new |
| grimworld_persistent::test_registry::test_set_record_composite_needs_parent | 7065250 | 7090130 | 7418513 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_existing_changes | 4469140 | 4478470 | 4692597 | +0.2 % |
| grimworld_persistent::test_registry::test_set_record_id_zero_refused | 1166440 | 1439840 | 1511832 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +23.4 % |
| grimworld_persistent::test_registry::test_set_record_insignia_pieces | — | 6501510 | 6826586 | new |
| grimworld_persistent::test_registry::test_set_record_new_sequential | 4402010 | 4408230 | 4622111 | +0.1 % |
| grimworld_persistent::test_registry::test_set_record_not_live_refused | 2087860 | 2771360 | 2909928 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +32.7 % |
| grimworld_persistent::test_registry::test_set_record_not_next_refused | 3216060 | 3228500 | 3376863 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_outline_chunk_refused | 4189860 | 4205410 | 4399353 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_part_count_refused | 1638750 | 2048850 | 2151293 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +25.0 % |
| grimworld_persistent::test_registry::test_set_record_per_source_bounds | — | 64966290 | 68214605 | new |
| grimworld_persistent::test_registry::test_set_record_quiver_ids | 3604570 | 3610790 | 3784631 | +0.2 % |
| grimworld_persistent::test_registry::test_set_record_quotas_keyed_by_location | 5335970 | 5354630 | 5602769 | +0.3 % |
| grimworld_persistent::test_registry::test_set_record_refused_to_others | 1260150 | 1396850 | 1466693 | raised: D-166: the Registry checks each record (CBT-02c), its class deploys dearer; +10.8 % |
| grimworld_persistent::test_registry::test_set_record_sources_refused | — | 7641790 | 8023880 | new |
| grimworld_persistent::test_registry::test_version_rises_per_changed_record | 8353130 | 8384230 | 8770787 | +0.4 % |
| grimworld_persistent::test_seed::test_gas_seed_write | 19414980 | 19455410 | 20385729 | +0.2 % |
| grimworld_persistent::test_seed::test_seed_rewritten_unchanged | 28008710 | 28089570 | 29409146 | +0.3 % |
| grimworld_persistent::test_seed::test_seed_written_and_read_back | 21441290 | 21481720 | 22513355 | +0.2 % |
| grimworld_logic::test_build::test_envelope_builds | 16288145 | — | — | removed (moved) |
| grimworld_logic::test_build::test_extremal_max_energy_and_rank | 3116860 | — | — | removed (moved) |
| grimworld_logic::test_build::test_extremal_max_health | 7630325 | — | — | removed (moved) |
| grimworld_logic::test_build::test_extremal_weapon | 604660 | — | — | removed (moved) |
| grimworld_logic::test_build::test_five_insignias_at_15_refused | 1323286 | — | — | removed (a registration check now) |
| grimworld_logic::test_build::test_floor_energy_regen_refused | 1958650 | — | — | removed (moved) |
| grimworld_logic::test_build::test_floor_max_energy_refused | 1958650 | — | — | removed (moved) |
| grimworld_logic::test_build::test_floor_max_health_refused | 2436310 | — | — | removed (moved) |
| grimworld_logic::test_build::test_instance_of_two_kinds_refused | 272350 | — | — | removed (no longer a flattening check) |
| grimworld_logic::test_build::test_other_fields_within_envelopes | 13328005 | — | — | removed (moved) |
| grimworld_logic::test_build::test_repeated_rune_id | 2091830 | — | — | removed (moved) |
| grimworld_logic::test_build::test_rune_attribute_contribution | 1356600 | — | — | removed (moved) |
| grimworld_logic::test_build::test_rune_identity | 1915000 | — | — | removed (moved) |
| grimworld_logic::test_build::test_saturation | 17018020 | — | — | removed (moved) |
| grimworld_logic::test_build::test_sixth_rune_refused | 1225770 | — | — | removed (moved) |
| grimworld_logic::test_build::test_stats_health_regen_20_packs | 107730 | — | — | removed (moved) |
| grimworld_logic::test_build::test_stats_health_regen_21_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_build::test_two_insignias_on_a_piece_refused | 588706 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_bar_and_kit_layout | 379250 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_bar_armor_above_bound_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_bar_armor_below_bound_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_bar_passives_layout | 798490 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_bar_quick_cast_attribute_refused | 81210 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_kit_condition_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_kit_knockdown_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_kit_passives_layout | 616100 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_kit_percent_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_stats_armor_vs_refused | 15520 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_stats_layout | 553910 | — | — | removed (moved) |
| grimworld_logic::test_packing::test_task_page_layout | 141890 | — | — | removed (moved) |

## Acceptance criteria

- **AC-1: met.** Every per-source bound of design/20 is checked at registration, each with a refusal test:
  - `test_registry::test_set_record_per_source_bounds` (§1.3's 17 rows at `lo`, `hi`, `hi + 1` and `lo − 1`; the benefit and cost summed; a benefit's range; a rewrite past its bound);
  - `…_sources_refused` (DS-4; §7.2's per-source contributions);
  - `…_insignia_pieces` (DS-23);
  - `…_caste_bounds` (DS-18, DS-29, the skill of 64 strikes);
  - `…_carriers` (DS-20, potions).
- **AC-2: met.** The flattening is linear in the build's sources: two passes; constant-bounded inner work (at most 25 rune comparisons, 10 rank lookups over at most 10 attribute runes). No validated build overflows a snapshot field:
  - design/20 §6's extremal builds are tests: `snapshot::tests::test_extremal_*`, `test_envelope_builds`, `test_other_fields_within_envelopes`, `test_saturation`, `test_widest_against_the_oracle`;
  - every one is compared with the oracle, and every sum goes into its field through `fit`, which refuses rather than wraps.
- **AC-3: the stop of the scope.**
  - `set_build` and `enter` were wired and tested (`4ca5802`: the refusals, the snapshot equal to the flattening's, the worst cases), and measured against D-158 (tables above).
  - `Hub` is 61.15 % with the wiring, so the wiring is held back and D-166 (b) is the project manager's.
- **AC-4: met.** The unit tests of the modules touched are in `snapshot.cairo`'s `mod tests` (the flattening and the layouts). `gas_budgets.py --check` is green on them (648 tests).
- **AC-5: met.**
  - D-143: the checks are in `...Assert` impls (`RegistryAssert::assert_content`, `BuildAssert`), the flattening's helpers in a private `FlattenTrait`, and `fit` is a documented free function.
  - CI is green on every check.
  - `class_sizes.py` exits 0.

## Deviations from the brief

- **The wiring is not in the PR's final state.** It is in the branch's history (`4ca5802`), held back by `47c7a33`, because `Hub` passes 50 % with it. That is the brief's stop, and CI's `class_sizes.py` fails on it.
- **Two logic tests were removed rather than moved:**
  - `test_five_insignias_at_15_refused`: insignia health by piece is now a registration check (`test_registry::test_set_record_insignia_pieces`, `test_build::test_insignia_record_above_piece_refused`);
  - `test_instance_of_two_kinds_refused`: one instance, one record, one source, by the caller's construction.

  `test_instances_out_of_order_refused` and the count tests replace them.
- **`test_capacity.cairo` stays in `tests/`.** Its subject is the validators of `passive`, `modifier` and `armor_set`, which this lot did not touch. Its own oracle still uses `MemberKitTrait::condition_duration`. Production code no longer calls that function; it is kept for that test and for the oracle (*Open questions*).
- **The condition-duration saturation test changed.** It is now a legal 20 + 13 = 33 on one prefix. With the registry's bounds, only one prefix at ≤ 33, no legal build reaches DS-5's saturation at 50. The saturation stays as a guard, and the 65,534 case remains in `test_capacity::test_same_condition_capped`.

## Escalations

1. **D-166 (b) is due**, and its reversal clause holds: `Hub` stays above 50 % and `set_build` above D-158 after (a).
   - A library class for the flattening fixes the size, not the cost. With the wiring, `set_build`'s worst case is ≈ 8.23 M as a transaction (D-158: 3.80 M) and `enter`'s ≈ 10.66 M (5.25 M).
   - Of `set_build`'s call, ≈ 3.08 M is reading the 7 `ItemMods` and the 15 `MODIFIER` records and building the held list, and ≈ 1.16 M is the flattening.
   - A lever for the project manager (not applied, it is a storage change): CAIRO §1 favours work done once, so `set_build` could store the three flattened snapshot words, and `enter` would read 3 words instead of re-reading and re-flattening the equipment. `enter` would then drop to about `main`'s figure. This needs slots in `Hub`'s adventurer layout (ENG-01 §3.3) and a rule for the equipment changing after `set_build`.
2. **DS-18's cross-record check is partial.** `set_record` checks a caste's skills that the registry already holds. It does not catch:
   - a caste written before its skills;
   - a skill rewritten above 63 strikes after a caste names it (there is no reverse index).

   Options: require the skills to exist first (refuse a caste naming a missing skill), keep a reverse index, or leave both to the content pipeline (OPS-01). design/20 does not say which.
3. **Items changing after `set_build`** (for the wiring, when it lands). The rolled-value and slot-type checks of `4ca5802` run at `set_build` and `enter`.
   - The later lots that write `ItemMods` (identification, the enchanter) should enforce the value range and the slot type when they write.
   - A modifier changed on an equipped item after `set_build` would make `enter` refuse, against design/20 §6 test 3's "never a panic in `enter`". Either those services refuse an equipped item, or `enter` falls back to the checked build.
4. **What `Hub`'s models do not hold yet** is unchanged since CBT-02b's escalation: attribute ids, weapon statistics, ratings, set bonuses, the strength cap. One consequence: with `Loadout.points` empty, a quick-cast modifier worn would make the wired `set_build` refuse (`build: quick-cast attribute`).

## Open questions

- `MemberKitTrait::condition_duration` and `MemberKitAssert::assert_one_condition` are now used only by tests (the oracle, `test_capacity`). Should they stay in `snapshot.cairo` or move to the tests?
- The `Registry` grew from 6.39 % to 28.44 % of the class limit with the content's checks, mostly the effect-entry validators behind `SKILL` and `ITEM`. It is far from 50 %; noted for the classes to come.

## Fix loop 1

The audits of PR 206 at `47c7a33` found no security defect. Security and cost: FAIL on one minor (SEC-1). Quality: PASS WITH FINDINGS, two minors. All three are fixed at **`5900d21`**, after `origin/main` was merged in (`cc2d8e4`; it changed nothing under `contracts/`). The held-back wiring stays out: it is CBT-02e now (D-168).

| Finding | Fix |
|---|---|
| **SEC-1** (D-167): `test_same_condition_capped` and `test_two_conditions_builder_refused`, in `tests/test_capacity.cairo`, are unit tests of `snapshot.cairo`'s `MemberKitTrait::condition_duration` | Both moved into `snapshot.cairo`'s `mod tests`, unchanged but for the fixture (`passive`, the module's own). The comment of `test_saturation` that pointed to `test_capacity` now points to them. |
| **Quality 1**: the caste registration test did not cover every bound it claims | `test_set_record_caste_bounds` now also refuses energy 86 (`caste: energy above 85`) and tier 7 (`caste: tier`), beside health 1,001 %, health regeneration 21, weapon damage 256, energy regeneration 11, flee 101 and tier 0. Its caste at bounds now holds armor 63 against every type. The rank (15) and the armor per type (63) are at their fields' widest: one more is the next field's bit, not a value a record can carry. |
| **Quality 2**: some changed budgets were below ceil(1.05 × measured) (a lower budget kept) | Every test whose measure differs from `origin/main`'s `BUDGETS.md`, or is new, now has exactly **ceil(1.05 × measured)**. That is **143 rows**, **93 of them raised** above `main`'s budget, each with its one-line `// gas: raised, …` reason. Most are raised by a few thousand gas: every persistent test that deploys the `Registry` pays for its larger class. `test_enter_after_set_build` is 45,650,493 for 43,476,660 measured. The unchanged rows keep their budgets. |

**Re-measured, no flake (D-154).** The per-package snforge runs, `gas_budgets.py`, `--check` and `--report` measured the same figures, test by test. A scratch check of `--report` confirms that every changed row's budget equals ceil(1.05 × after): 143 changed, 0 not exact.

Commands:

```
$ git merge origin/main                              → cc2d8e4 (docs only: D-168, CBT-02d's brief)
$ cd contracts/logic && snforge test                 → Tests: 434 passed, 0 failed
$ cd contracts/persistent && snforge test            → 161 passed (test_set_record_caste_bounds: 12,745,610 measured)
$ cd contracts/ephemeral && snforge test             → Tests: 53 passed, 0 failed
$ python3 scripts/gas_budgets.py --check             → gas check: 648 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py             → exit 0; Hub 42.83 %, Registry 28.44 %
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check   → exit 0
$ gh pr checks 206 --watch --interval 30             → every check pass (indexer-node skipping); cairo (contracts) 1m59s
```

The gas table's rows that changed in this fix loop:
- `snapshot::tests::test_same_condition_capped`: new, 39,010, budget 40,961;
- `snapshot::tests::test_two_conditions_builder_refused`: new, 29,660, budget 31,143;
- `test_capacity::test_same_condition_capped` and `test_capacity::test_two_conditions_builder_refused`: removed (moved);
- `test_registry::test_set_record_caste_bounds`: 11,710,690 → 12,745,610 (two more refusals), budget 13,382,891;
- the budgets of the rows above set to exactly ceil(1.05 × measured).

SEC-2 was a note, not a finding to fix: DS-18's cross-record check depends on registration order and rewrites. It is this report's escalation 2 and stays open for the project manager.

## Fix loop 2

The Codex review of PR 206 at `5900d21` failed on one major, SEC-2 of fix loop 1 made concrete. DS-18's bound (a caste's skills at most 63 strikes) was checked only against the skills present when the caste was written. It is fixed at **`b178e87`**. `origin/main` had not moved since fix loop 1's merge (`git merge origin/main`: already up to date). **Escalation 2 is closed.**

**The fix: `Registry` counts the castes that name each skill.** A new storage variable, `caste_skills: Map<skill id, u32>`, counts how many `CASTE` records name each skill (a caste naming it twice counts twice).
- **A caste written** (new or rewritten, after every check) moves the counts from the skills its stored record named to the ones the new record names. Only the counts that change are written: at most 8 keys, and none when a rewrite names the same skills.
- **A `SKILL` above 63 strikes** is refused (`caste: skill adrenaline`) while its count is not 0, whether the skill is new or rewritten. That is one read, made only above 63.
- **The check at a caste's write is unchanged:** the skills it names that exist must be at most 63.

The bound therefore holds in either order of writes. A caste written before its skill binds that skill's id, and a skill written first binds the caste.

**Why this one**, among the brief's three:

| Option | Cost | Rule design/20 does not state? |
|---|---|---|
| The skill record carries the bound: every skill ≤ 63 strikes | nothing | **Yes.** DS-18 bounds only the skills a caste names; §1.4 lets a member's skill cost up to 255 strikes (a `SKILL` byte) |
| A caste may name only skills that exist, plus a skill's rewrite refused when it would break a caste | the existence reads, and still a way to find the castes naming a skill on a rewrite, which is the same count | **Yes:** it refuses a caste written before its skills (a seeding order) |
| **The count (chosen)** | a caste: its stored record (2 reads) and ≤ 8 counts read, only those that change written; a skill: 1 read, only above 63; `Registry` +1,312 CASM felts (28.44 → **30.04 %**) | **No:** it is DS-18 itself, in both orders |

The count is the only option that adds no rule. The other honest option needs the same reverse lookup anyway, so it costs no less. Every write is the administrator's; no player's call pays for it.

**Other cross-record bounds checked at registration: none.** The only other cross-record checks are ENG-03's composite parents (`QUOTAS`, `OUTLINE`, `SHOP`), which require the parent to exist first. They are existence checks, not bounds, and a record is never deleted or zeroed, so they cannot be broken by a later write. Every other check of CBT-02c reads one record alone.

**Tests** (`test_registry`):
- `test_set_record_caste_skills_either_order`:
  - the caste is written first, naming skill 1 before it exists;
  - skill 1 at 64 is then refused (and not written), and accepted at 63;
  - rewritten from 63 to 64, refused; rewritten to 62, accepted;
  - a skill no caste names takes 64.
- The other order, the skill first at 64 and then a caste naming it refused, stays in `test_set_record_caste_bounds`.
- `test_set_record_caste_rewrite_moves_the_bound`:
  - a caste naming skill 1 twice, then once: skill 1 stays bound;
  - rewritten to name skill 2: skill 1 is released (64 accepted) and skill 2 bound;
  - two castes naming skill 2: it stays bound until neither does.
- `layout_tests::test_registry_storage_addresses` checks `caste_skills`' address.

**ENG-01:** §3.5 (the storage variable, "DS-18 holds whatever the order of writes"), §9.3 (a caste's ≤ 8 counts written, its reads; a skill's one read above 63), §1.3 (`Registry` 30.04 %).

**Budgets:** every changed row is exactly ceil(1.05 × measured), re-measured. `--report` gives 146 changed rows (new ones included), 94 raised, 0 not exact. The larger class makes each `Registry` deploy about 400,000 dearer in snforge, so the tests that deploy it rose again (`test_set_record_id_zero_refused`: 1,439,840 → 1,837,820). The layout test's raise is its extra assertion, and its reason line says so. Several runs measured the same, so there is no flake to record (D-154).

```
$ git merge origin/main                        → Already up to date
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build   → Finished
$ cd contracts/persistent && snforge test      → every test passes (after the budgets); the two new: 11,099,690 and 19,218,570
$ cd contracts/ephemeral && snforge test       → Tests: 53 passed, 0 failed
$ python3 scripts/gas_budgets.py --check       → gas check: 650 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py       → exit 0; Registry 24,608 felts, 30.04 %; Hub 42.83 %
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check   → exit 0
$ gh pr checks 206 --watch --interval 30       → every check pass (indexer-node skipping); cairo (contracts) 2m40s
```

The gas table's rows new in this fix loop:
- `test_registry::test_set_record_caste_skills_either_order`: new, 11,099,690, budget 11,654,675;
- `test_registry::test_set_record_caste_rewrite_moves_the_bound`: new, 19,218,570, budget 20,179,499;
- `test_registry::test_set_record_caste_bounds`: 15,239,100, budget 16,001,055;
- `layout_tests::test_registry_storage_addresses`: 55,520 → 69,290, budget 72,755, raised (the extra assertion).
