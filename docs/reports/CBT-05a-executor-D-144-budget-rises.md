Archived at the merge of #334, f50c1fc. Library file of the CBT-05a thread (t-0009).

# D-144: every budget that rises above origin/main's (CBT-05a)

From one `snforge test --workspace --fuzzer-seed 1` on Scarb 2.20.1 (VPS); budgets `ceil(1.05 × measured)`.

The rises of route (c) with option (3)'s levers 1 and 3, and of the fixtures' positions (F-2), are accepted under D-207 (the project manager, 2026-10-03). The tick's cost is ENG-01 §9.2's measured line: 45,999,941 the worst tick, accepted as a one-tick batch.

**Fixture artefacts, gone.** At #334's earlier head the five library-call fixtures placed every goblin on one tile, so each call carried every goblin: `test_cost_library_call` 835,954,852, `_batch` 844,148,703, `_kills` 103,470,757, `_two_members` 932,517,909, `test_library_matches_pipeline` 875,616,563 (budgets). With one goblin a tile they are the figures below.

## On the expedition's path, above +10 % (for the project manager)

59 tests.

| Package | Test | Main | New | Rise | Cause |
|---|---|---:|---:|---:|---|
| grimworld_logic | `test_tick::test_cost_path_goblin_below` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_below_dead` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_down` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_down_dead` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_up` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_up_full` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_above` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_above_full` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_effect_zero` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_effect_over` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_energy_capped` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_adrenaline_zero` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `test_tick::test_cost_path_goblin_engaged` | 324,681 | 715,092 | +120.24 % | CBT-05a R3: the test builds a content and its sheets to give the goblin its caste's regeneration (the test's setup, not the path) |
| grimworld_logic | `types::tick::tests::test_index_positions` | 462,294 | 769,776 | +66.51 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::tick::tests::test_sheets_read_oracle` | 1,167,600 | 1,859,025 | +59.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_index_fixture` | 887,345 | 1,356,884 | +52.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_index_skill_first` | 887,880 | 1,356,999 | +52.84 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_index_caste_first` | 887,880 | 1,356,999 | +52.84 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_index_skill_last` | 888,090 | 1,357,209 | +52.82 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_index_caste_last` | 888,090 | 1,357,209 | +52.82 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::tick::tests::test_index_no_skill` | 316,113 | 481,877 | +52.44 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::tick::tests::test_index_no_caste` | 316,113 | 481,877 | +52.44 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::tick::tests::test_index_no_potion` | 316,113 | 481,877 | +52.44 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_call_two_members` | 31,818,283 | 47,995,230 | +50.84 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_logic | `models::goblin::tests::test_goblin_adrenaline_gain` | 478,065 | 660,146 | +38.09 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheets_unpacked` | 555,198 | 757,512 | +36.44 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_apply` | 1,060,521 | 1,386,725 | +30.76 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_load_store` | 1,064,028 | 1,368,738 | +28.64 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_call_batch` | 37,458,488 | 47,749,195 | +27.47 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_logic | `models::goblin::tests::test_goblin_hold` | 699,489 | 891,576 | +27.46 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_condition_base` | 613,253 | 778,491 | +26.94 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_source_base` | 614,093 | 779,331 | +26.91 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_idle_base` | 614,513 | 779,751 | +26.89 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_dead_base` | 614,513 | 779,751 | +26.89 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_predicates` | 623,501 | 788,739 | +26.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_call` | 31,328,392 | 39,555,344 | +26.26 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_logic | `types::tick::tests::test_kits` | 166,719 | 209,496 | +25.66 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_apply_crippled` | 644,637 | 808,931 | +25.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_apply_bleeding` | 644,637 | 808,931 | +25.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_apply_dead` | 645,057 | 809,351 | +25.47 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_knock_refresh_not_longer` | 641,004 | 803,513 | +25.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_cure` | 647,063 | 810,726 | +25.29 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_knock` | 661,532 | 825,720 | +24.82 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_knock_idle` | 661,952 | 826,140 | +24.80 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_cost_goblin_oracle` | 693,788 | 856,401 | +23.44 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_load` | 900,522 | 1,087,002 | +20.71 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_potion_damage` | 24,192 | 28,886 | +19.40 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_potion_regen` | 24,402 | 29,096 | +19.24 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_potion_regen_negative` | 24,402 | 29,096 | +19.24 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_call_kills` | 32,437,160 | 38,621,989 | +19.07 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_logic | `test_tick::test_library_matches_pipeline` | 60,352,169 | 71,111,778 | +17.83 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_logic | `models::goblin::tests::test_goblin_apply_refresh_cure` | 920,273 | 1,081,626 | +17.53 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_knockdown_interrupts` | 936,243 | 1,099,172 | +17.40 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_call_batch_representative` | 16,495,038 | 19,303,095 | +17.02 % | CBT-05a, route (c) with option (3)'s levers 1 and 3 (D-207): each concluding carrier calls ExecutorLibrary; one goblin a tile (F-2). At #334's earlier head, every goblin on one tile, this figure was a fixture artefact (see the note below) |
| grimworld_ephemeral | `test_tick_words::test_tick_words_goblin` | 605,735 | 708,320 | +16.94 % | the load reads through the content's index, built first (CBT-02d) |
| grimworld_logic | `test_tick::test_cost_library_call_all_dead` | 31,446,170 | 36,243,214 | +15.25 % | CBT-05a: the content carries the executor's fields; run takes the board and the executor's class (no carrier runs: every goblin dead) |
| grimworld_ephemeral | `test_tick_words::test_potion_regeneration_every_belt_slot` | 3,149,919 | 3,589,008 | +13.94 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `types::hit::tests::test_evade` | 73,112 | 81,911 | +12.03 % | CBT-05a: D-179's case and track CV's three hit cases |
| grimworld_logic | `models::member::tests::test_hold_refresh` | 7,299,600 | 8,087,846 | +10.80 % | CBT-05a: the sheets carry the executor's fields, actors their positions |

## On the expedition's path, +10 % or less (for the project manager)

213 tests.

| Package | Test | Main | New | Rise | Cause |
|---|---|---:|---:|---:|---|
| grimworld_ephemeral | `test_tick_words::test_tick_words_member` | 1,376,372 | 1,511,801 | +9.84 % | the load reads through the content's index, built first (CBT-02d) |
| grimworld_logic | `types::world::tests::test_example_burning_goblin` | 6,971,490 | 7,585,688 | +8.81 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_member_potions` | 6,017,382 | 6,516,615 | +8.30 % | the fixture builds the content's index before the load (CBT-02d) |
| grimworld_logic | `test_tick::test_cost_load_member_skills` | 6,025,677 | 6,525,330 | +8.29 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_load_member_potions_fixture` | 5,748,089 | 6,217,628 | +8.17 % | the fixture builds the content's index (CBT-02d) |
| grimworld_logic | `test_tick::test_cost_load_member_skills_fixture` | 5,748,824 | 6,218,363 | +8.17 % | the fixture builds the content's index (CBT-02d) |
| grimworld_logic | `models::member::tests::test_hold_eviction_and_stance` | 7,809,029 | 8,446,830 | +8.17 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_apply` | 7,112,175 | 7,674,555 | +7.91 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_empty` | 41,412 | 44,552 | +7.58 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_bound_fixture` | 11,728,805 | 12,603,266 | +7.46 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_fixture_worst_8` | 6,581,558 | 7,059,402 | +7.26 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_condition_degeneration` | 7,044,299 | 7,547,354 | +7.14 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_damage_then_empty` | 45,035 | 48,174 | +6.97 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_candidates` | 7,991,340 | 8,537,225 | +6.83 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_awake_none_fixture` | 8,427,689 | 8,973,573 | +6.48 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_tick_worst_8` | 8,088,112 | 8,595,650 | +6.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_representative_run_ten` | 14,311,175 | 15,170,148 | +6.00 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_batch_representative` | 14,312,855 | 15,171,828 | +6.00 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_run_ticks_alone` | 15,251,597 | 16,110,570 | +5.63 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_branch_worlds_take_their_branch` | 73,963,454 | 78,101,556 | +5.59 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_deaths_in_step_3` | 7,262,817 | 7,659,402 | +5.46 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_awake_start_kept_fixture` | 10,060,124 | 10,603,488 | +5.40 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_lapse` | 12,578,627 | 13,213,425 | +5.05 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_condition_refreshed` | 7,509,865 | 7,886,532 | +5.02 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_condition_refreshed_variant` | 7,509,865 | 7,886,532 | +5.02 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_regen_first` | 51,009 | 53,519 | +4.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_bound` | 22,827,903 | 23,915,808 | +4.77 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_none_eight_members` | 16,331,474 | 17,109,702 | +4.77 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_regen_second` | 54,422 | 56,931 | +4.61 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_none_four_members` | 15,309,832 | 16,009,521 | +4.57 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_activating` | 14,370,251 | 15,019,855 | +4.52 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_free` | 14,374,549 | 15,024,152 | +4.52 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_recovery_end` | 14,397,260 | 15,045,572 | +4.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_base` | 14,297,665 | 14,940,275 | +4.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_recover_alive` | 14,417,018 | 15,064,837 | +4.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_recover` | 14,417,123 | 15,064,942 | +4.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_clear` | 14,419,132 | 15,066,950 | +4.49 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_lapse` | 14,439,932 | 15,086,459 | +4.48 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_none_two_members` | 14,905,450 | 15,568,388 | +4.45 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_base_member_alive` | 14,284,907 | 14,918,383 | +4.43 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_none` | 14,728,994 | 15,374,188 | +4.38 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_none_k3` | 14,728,994 | 15,374,188 | +4.38 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_base_fixture` | 14,088,911 | 14,701,911 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_base_member_alive_fixture` | 14,089,016 | 14,702,016 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_recover_fixture` | 14,092,607 | 14,705,292 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_recover_alive_fixture` | 14,092,712 | 14,705,397 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_conclude_clear_fixture` | 14,092,911 | 14,705,597 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_lapse_fixture` | 14,093,615 | 14,706,300 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_recovery_end_fixture` | 14,094,318 | 14,707,004 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_activating_fixture` | 14,094,917 | 14,707,602 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_free_fixture` | 14,095,022 | 14,707,707 | +4.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_regen_third` | 57,834 | 60,344 | +4.34 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_eight_lapses` | 15,365,204 | 16,028,489 | +4.32 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_bound_eight_lapses_fixture` | 14,116,473 | 14,724,896 | +4.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_activating` | 15,310,211 | 15,965,002 | +4.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_recovering` | 15,310,621 | 15,965,411 | +4.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_knocked` | 15,310,820 | 15,965,611 | +4.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_free` | 15,315,454 | 15,970,244 | +4.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_regeneration` | 11,006,855 | 11,476,898 | +4.27 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_recovery_end` | 15,339,467 | 15,992,966 | +4.26 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_conclude_recover` | 15,358,490 | 16,011,496 | +4.25 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_conclude_recover_surviving` | 15,358,784 | 16,011,790 | +4.25 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_conclude_clear` | 15,360,499 | 16,013,504 | +4.25 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_dead` | 15,288,907 | 15,938,584 | +4.25 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_lapse` | 15,382,160 | 16,033,874 | +4.24 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_one_lapse_keep` | 15,382,559 | 16,034,273 | +4.24 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_skill_regen_third_negative` | 59,136 | 61,604 | +4.17 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_knocked_predicates` | 6,216,339 | 6,472,696 | +4.12 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_busy_fixture` | 14,107,349 | 14,685,342 | +4.10 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_worst` | 14,108,189 | 14,686,182 | +4.10 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_worst_batch` | 14,109,974 | 14,687,967 | +4.10 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_bound_two_members_fixture` | 21,455,690 | 22,330,151 | +4.08 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_sheet_skill_none` | 50,306 | 52,353 | +4.07 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_tick_worst` | 15,715,238 | 16,322,401 | +3.86 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_interrupt` | 6,556,434 | 6,809,221 | +3.86 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_busy_tick` | 15,655,140 | 16,254,113 | +3.83 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_activating_tick` | 18,984,329 | 19,702,487 | +3.78 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::goblin::tests::test_goblin_load_missing_skill` | 446,607 | 463,313 | +3.74 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_activating` | 19,380,200 | 20,093,423 | +3.68 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_recovering` | 19,383,476 | 20,096,699 | +3.68 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_knocked` | 19,385,072 | 20,098,295 | +3.68 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_free` | 19,422,141 | 20,135,364 | +3.67 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheets` | 416,063 | 431,298 | +3.66 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_regeneration_extremes` | 10,685,300 | 11,076,257 | +3.66 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_flags_cleared` | 5,345,911 | 5,541,389 | +3.66 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_first` | 19,460,602 | 20,167,630 | +3.63 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_middle` | 19,463,584 | 20,170,612 | +3.63 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_last` | 19,463,584 | 20,170,612 | +3.63 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_l_first` | 19,482,263 | 20,188,000 | +3.62 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_l_middle` | 19,482,263 | 20,188,000 | +3.62 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_activating_lapse` | 19,496,060 | 20,201,797 | +3.62 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_a6_ll` | 19,540,856 | 20,244,178 | +3.60 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_recovery_end` | 19,566,107 | 20,269,218 | +3.59 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_cc_first` | 19,559,221 | 20,260,054 | +3.58 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_conditions` | 5,496,603 | 5,693,174 | +3.58 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_adrenaline_decay` | 11,941,270 | 12,367,801 | +3.57 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_defeat` | 11,376,403 | 11,775,655 | +3.51 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_term_fixture` | 18,241,388 | 18,879,872 | +3.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_activating_fixture` | 18,242,826 | 18,881,310 | +3.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_dead` | 19,209,764 | 19,882,079 | +3.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_apply_refresh` | 5,355,998 | 5,543,192 | +3.50 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_load_store` | 10,871,039 | 11,247,380 | +3.46 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_lapse` | 19,914,644 | 20,603,475 | +3.46 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_lapse_keep` | 19,917,836 | 20,606,667 | +3.46 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_parity_states` | 177,323,564 | 183,439,856 | +3.45 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_100` | 12,852,966 | 13,295,783 | +3.45 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_sheet_caste` | 375,291 | 388,175 | +3.43 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_bound_two_members` | 32,862,900 | 33,985,644 | +3.42 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_parity_terms_one` | 240,926,881 | 249,157,506 | +3.42 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_worst_words_twice` | 32,791,658 | 33,903,965 | +3.39 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_worst_words` | 16,398,144 | 16,954,298 | +3.39 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_baseline_batch` | 16,406,870 | 16,962,603 | +3.39 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_term_tick` | 19,791,080 | 20,458,386 | +3.37 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_awake_none` | 13,253,783 | 13,697,229 | +3.35 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_a_then_c` | 20,062,292 | 20,732,150 | +3.34 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_ll_c5` | 20,091,191 | 20,761,752 | +3.34 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_clear_activating` | 20,073,107 | 20,742,965 | +3.34 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c6_al` | 20,077,989 | 20,746,556 | +3.33 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c6_la` | 20,077,989 | 20,746,556 | +3.33 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_r_c6` | 20,088,524 | 20,757,090 | +3.33 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c6_rl` | 20,093,889 | 20,761,826 | +3.32 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_none` | 13,384,445 | 13,827,891 | +3.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c_l_c6` | 20,131,217 | 20,797,998 | +3.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_lapse_first` | 20,134,199 | 20,800,980 | +3.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_member_down_before_the_tick` | 5,548,379 | 5,731,992 | +3.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_set_c6_ll` | 20,136,582 | 20,802,734 | +3.31 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_clear_recovery_end` | 20,147,712 | 20,811,869 | +3.30 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_conclude_recover` | 20,157,095 | 20,820,758 | +3.29 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_eight_conclude_clear` | 20,173,164 | 20,836,827 | +3.29 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_clear_lapse_spread` | 20,173,196 | 20,835,567 | +3.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_clear_lapse` | 20,190,405 | 20,852,777 | +3.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_term_mix_clear_lapse_start` | 20,188,967 | 20,847,999 | +3.26 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_zero_base` | 5,216,054 | 5,385,492 | +3.25 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_condition_base` | 5,214,794 | 5,383,182 | +3.23 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_source_base` | 5,215,634 | 5,384,022 | +3.23 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_idle_base` | 5,217,104 | 5,385,492 | +3.23 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_predicates` | 5,226,480 | 5,394,869 | +3.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_knock` | 5,273,415 | 5,443,274 | +3.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_knock_idle` | 5,273,835 | 5,443,694 | +3.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_infliction` | 5,234,639 | 5,403,132 | +3.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_cure` | 5,253,150 | 5,422,064 | +3.22 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_apply_crippled` | 5,249,433 | 5,418,137 | +3.21 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_apply_bleeding` | 5,249,433 | 5,418,137 | +3.21 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_apply_not_alive` | 5,249,853 | 5,418,557 | +3.21 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_cost_member_oracle` | 5,310,218 | 5,480,601 | +3.21 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_knock_refresh_not_longer` | 5,243,018 | 5,410,986 | +3.20 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_apply_not_alive` | 5,178,600 | 5,344,469 | +3.20 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_load_store_worst` | 43,887,470 | 45,213,221 | +3.02 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_activated_attack_cost` | 18,089,687 | 18,634,637 | +3.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_parity_terms_eight` | 228,163,667 | 234,939,684 | +2.97 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_awake_start_kept` | 14,957,975 | 15,398,901 | +2.95 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_end_replaced` | 15,086,873 | 15,527,799 | +2.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_start_kept` | 15,087,797 | 15,528,723 | +2.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_spread_kept` | 15,118,404 | 15,559,331 | +2.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_spread_replaced` | 15,122,741 | 15,563,667 | +2.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_baseline_two_members` | 29,091,328 | 29,939,423 | +2.92 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_start_replaced` | 15,139,740 | 15,580,667 | +2.91 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_awake_end_kept` | 15,140,664 | 15,581,591 | +2.91 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_baseline_all_dead` | 27,955,991 | 28,764,775 | +2.89 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_apply_matches_oracle` | 36,581,507 | 37,639,067 | +2.89 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_representative_run_one` | 8,263,151 | 8,498,613 | +2.85 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_pair_representative_tick` | 8,252,399 | 8,487,021 | +2.84 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_tick_representative` | 8,254,079 | 8,488,701 | +2.84 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_parity_terms_mixed` | 162,655,346 | 167,233,829 | +2.81 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_baseline` | 28,620,316 | 29,420,447 | +2.80 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_library_baseline_kills` | 28,979,573 | 29,779,705 | +2.76 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_who_acts` | 7,895,884 | 8,112,037 | +2.74 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_bar_positions` | 5,889,209 | 6,050,258 | +2.73 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_awake_set_apart` | 7,149,975 | 7,341,527 | +2.68 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_batch_worst` | 31,109,453 | 31,911,936 | +2.58 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_deterministic` | 61,910,573 | 63,346,805 | +2.32 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_defeat_in_step_1_with_eight_awake` | 8,968,988 | 9,173,392 | +2.28 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_representative_words` | 7,824,222 | 7,997,126 | +2.21 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_library_baseline_representative` | 7,835,048 | 8,007,531 | +2.20 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `test_tick::test_cost_pair_representative_fixture` | 7,584,413 | 7,750,176 | +2.19 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_fixture_representative` | 7,585,463 | 7,751,226 | +2.19 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_logic | `types::world::tests::test_world_assert_awake_loaded` | 8,842,796 | 9,030,210 | +2.12 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_world_assert_awake_perceived` | 9,287,999 | 9,464,893 | +1.90 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_adrenaline_gain` | 5,675,271 | 5,776,449 | +1.78 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_parity_examples` | 136,197,649 | 138,619,736 | +1.78 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_example_member_activation` | 15,843,719 | 16,069,228 | +1.42 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_knockdown_interrupts` | 15,035,444 | 15,205,512 | +1.13 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::world::tests::test_world_assert_distances` | 311,378 | 314,633 | +1.05 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `types::hit::tests::test_vectors` | 961,496,367 | 968,230,791 | +0.70 % | CBT-05a: D-179's case and track CV's three hit cases |
| grimworld_logic | `test_tick::test_cost_tick_worst_permuted` | 17,757,961 | 17,859,580 | +0.57 % | CBT-05a, route (c) with levers 1 and 3, one goblin a tile (F-2), D-207 |
| grimworld_logic | `test_tick::test_cost_fixture_worst_permuted` | 16,253,087 | 16,325,012 | +0.44 % | CBT-05a, route (c) with levers 1 and 3, one goblin a tile (F-2), D-207 |
| grimworld_logic | `test_hit_cost::test_cost_pair_hit_one` | 54,968 | 55,073 | +0.19 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_hit_cost::test_cost_hits_per_tick` | 1,121,799 | 1,123,794 | +0.18 % | 15 hits a tick instead of 14 (FX-35 counts a bomb's 7; fix loop 1, minor 1) |
| grimworld_logic | `types::world::tests::test_world_assert_awake` | 7,640,021 | 7,652,358 | +0.16 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_hit_cost::test_cost_hit_paths` | 1,952,381 | 1,955,216 | +0.15 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_persistent | `test_lifecycle::test_enter_after_set_build` | 51,971,308 | 52,000,991 | +0.06 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_lifecycle::test_enter_refuses_after_an_input_rewritten` | 55,378,483 | 55,400,071 | +0.04 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_lifecycle::test_enter_after_other_records_changed` | 48,054,157 | 48,064,951 | +0.02 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_logic | `types::hit::tests::test_fuzz_no_panic` | 533,106 | 533,211 | +0.02 % | CBT-05a: D-179's case and track CV's three hit cases |
| grimworld_persistent | `test_lifecycle::test_enter_refuses_a_stale_snapshot` | 50,018,664 | 50,024,061 | +0.01 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_logic | `test_tick::test_cost_path_member_below` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_below_dead` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_down` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_down_dead` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_up` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_up_full` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_above` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_above_full` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_effects_zero` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_effects_over` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_energy_capped` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_adrenaline_zero` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_engaged` | 4,922,579 | 4,923,104 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_apply_knockdown_refused` | 4,885,608 | 4,885,923 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_crippled_move` | 4,915,145 | 4,915,460 | +0.01 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_store_same` | 9,776,330 | 9,776,750 | +0.00 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_tick::test_cost_path_member_store_changed` | 9,776,330 | 9,776,750 | +0.00 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `models::member::tests::test_member_knocked_predicates` | 4,878,290 | 4,878,395 | +0.00 % | CBT-05a: the sheets carry the executor's fields, actors their positions |

## Off the path, above +10 % (for the project manager)

0 tests.

| Package | Test | Main | New | Rise | Cause |
|---|---|---:|---:|---:|---|

## Off the path, +10 % or less (accepted with its cause, D-144)

53 tests.

| Package | Test | Main | New | Rise | Cause |
|---|---|---:|---:|---:|---|
| grimworld_logic | `test_build::test_caste_at_bounds` | 217,970 | 230,853 | +5.91 % | CBT-05a: a caste's sheet carries its armor and weapon |
| grimworld_logic | `test_validators::test_attack_modifiers_on_foes_accepted` | 397,005 | 413,196 | +4.08 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_legal_carriers` | 1,694,532 | 1,759,296 | +3.82 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_attack_entry_on_self_refused` | 72,093 | 74,792 | +3.74 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_modifier_without_hit_refused` | 219,429 | 227,525 | +3.69 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_item_scaled_potion_refused` | 75,212 | 77,910 | +3.59 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_trap_payload_on_self_refused` | 227,357 | 235,452 | +3.56 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_build::test_second_attack_bonus_refused` | 154,256 | 159,653 | +3.50 % | CBT-05a: a caste's sheet carries its armor and weapon |
| grimworld_logic | `test_combat::test_carrier_gap_refused` | 232,313 | 240,408 | +3.48 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_trap_not_first_refused` | 155,663 | 161,060 | +3.47 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_modifier_on_another_set_refused` | 234,843 | 242,939 | +3.45 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_disc_2_refused` | 84,662 | 87,360 | +3.19 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_validators::test_attack_bonus_on_allies_refused` | 85,470 | 88,169 | +3.16 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_two_holding_refused` | 171,171 | 176,568 | +3.15 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_attack_bonus_in_a_spell_refused` | 171,360 | 176,757 | +3.15 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_attack_with_damage_refused` | 85,670 | 88,368 | +3.15 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_validators::test_attack_hit_penetration_on_allies_refused` | 85,670 | 88,368 | +3.15 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_damage_not_first_refused` | 171,875 | 177,272 | +3.14 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_two_hits_refused` | 172,169 | 177,566 | +3.13 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_carrier_disc_1_in_a_skill_refused` | 101,577 | 104,276 | +2.66 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_logic | `test_combat::test_item_round_trip` | 479,535 | 482,234 | +0.56 % | CBT-05a: the sheets carry the executor's fields, actors their positions |
| grimworld_persistent | `test_read_cost::test_content_read_probe_alone` | 89,602,716 | 89,921,139 | +0.36 % | D-166: the Registry checks each record (CBT-02c), its class deploys dearer |
| grimworld_persistent | `test_read_cost::test_content_read_representative` | 91,655,729 | 91,974,152 | +0.35 % | D-166: the Registry checks each record (CBT-02c), its class deploys dearer |
| grimworld_persistent | `test_read_cost::test_content_read_worst` | 94,486,424 | 94,804,847 | +0.34 % | D-166: the Registry checks each record (CBT-02c), its class deploys dearer |
| grimworld_persistent | `test_registry::test_set_record_caste_skills_either_order` | 12,095,465 | 12,135,942 | +0.33 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_persistent | `test_registry::test_set_record_carriers` | 8,774,798 | 8,801,783 | +0.31 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_persistent | `test_registry::test_set_record_caste_rewrite_moves_the_bound` | 21,357,179 | 21,413,847 | +0.27 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_persistent | `test_build::test_bar_duplicate_refused` | 82,926,757 | 83,075,174 | +0.18 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_ownership_refusals` | 83,389,145 | 83,537,563 | +0.18 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_bar_profession` | 83,806,499 | 83,954,917 | +0.18 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_belt_items` | 85,143,611 | 85,292,029 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_layout_refusals` | 86,336,107 | 86,484,524 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_belt_counts_within_the_pack` | 86,635,654 | 86,784,071 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_empty` | 86,760,576 | 86,908,994 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_attributes_rank_and_points` | 86,784,565 | 86,932,982 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_bar_elite` | 87,805,466 | 87,953,884 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_bar_known_and_registered` | 87,956,942 | 88,105,360 | +0.17 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_parts` | 91,086,436 | 91,234,853 | +0.16 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_equipment_slots_and_hands` | 91,365,412 | 91,513,830 | +0.16 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_equipment_owned_and_wearable` | 91,689,413 | 91,837,830 | +0.16 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_attributes_indices` | 93,938,900 | 94,087,318 | +0.16 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_stores_the_extremal_max_energy` | 94,642,934 | 94,791,351 | +0.16 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_unknown_modifier_refused` | 100,653,188 | 100,801,606 | +0.15 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_attributes_points_by_level` | 103,026,971 | 103,175,388 | +0.14 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_insignia_piece_refused` | 105,298,916 | 105,447,333 | +0.14 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_floor_refused` | 105,733,944 | 105,882,362 | +0.14 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_modifier_slot_and_value_refused` | 109,497,944 | 109,646,362 | +0.14 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_sixth_rune_refused` | 110,304,417 | 110,452,834 | +0.13 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_stores_the_extremal_max_health` | 111,968,043 | 112,116,461 | +0.13 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_registry::test_inputs_version_per_kind` | 25,720,758 | 25,753,140 | +0.13 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
| grimworld_persistent | `test_build::test_set_build_requests_the_input_kinds` | 120,381,351 | 120,529,768 | +0.12 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_build::test_set_build_worst_case` | 126,665,768 | 126,814,185 | +0.12 % | ENG-R1a (D-144): the store's map addresses, a larger Hub class |
| grimworld_persistent | `test_registry::test_set_record_caste_bounds` | 16,509,161 | 16,525,352 | +0.10 % | Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost |
