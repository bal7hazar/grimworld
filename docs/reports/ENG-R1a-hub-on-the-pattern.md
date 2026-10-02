# [Opus 5.5] ENG-R1a — `Hub` on the pattern: accounts, adventurers and packs through the store

## For the owner: what to read, in order

Line numbers are those of the head after fix loop 3 (`5b25a43`). "`HubStoreTrait`" is the store's trait; its impl is `HubStoreImpl`.

1. **The store**, `contracts/persistent/src/store.cairo`: read the module doc at the top (stored models, tracking, layers), then `HubStoreImpl` (line 67). `Hub`'s whole storage is now read and written here and nowhere else. As in `quiver_quest`, the store is a trait implemented on the contract's own state, so a call reads `self.get_core(adventurer_id)`.
   - **Getters and setters:** each model has its getter and setter. Some have more than one: a focused read of part of a model (the account's owner alone, its record alone), or a pair under one address (`get_account`, `get_core_place`).
   - **Focused reads across several slots:** `get_core_place` (331), `knows_skills` (388), `get_equipment` (467).
   - **The account list's insertion and swap removal**, moved here from `hub.cairo`: `add_adventurer_id` (244) and `remove_adventurer_id` (260).
   - **The balance pages:** `get_balance` (412) and `change_balances` (422).

   The store does no word arithmetic: it reads and writes, keeps their order and keeps loop bookkeeping (`count - 1`, the lanes filled and emptied summed, the counters' `value + 1`); the models change the words. Why: ENG-04's audit F-5 and CBT-08a's F-1.
2. **One model**, `contracts/persistent/src/models/stored_core.cairo` (157 lines). Read in order:
   - the module doc, with the packer's measured cost;
   - `StoredCore` (14) and its methods (`StoredCoreImpl`, 26);
   - its `errors` (82) and `StoredCoreAssert` (88);
   - its tests (97, e.g. `test_core_words` at 109), which pin each method against `AdventurerCore`'s packer.

   **Each stored model has a file of its own, laid out the same way** (CAIRO §7): the module doc (what it stores, what its packer costs, which store method reads it), the struct, its trait, its `Assert` and `errors` where it owns checks, and its tests.

   | File | Stored model | Its checks |
   |---|---|---|
   | `stored_core.cairo` | `StoredCore` (14) | `StoredCoreAssert`: experience overflow |
   | `stored_place.cairo` | `StoredPlace` (12) | `StoredPlaceAssert` (175): unlocked, in its instance, hub above 63 |
   | `stored_record.cairo` | `StoredRecord` (16) | none: a free slot is the account's (`AccountAssert`) |
   | `stored_build.cairo` | `StoredBuild` (17) | `StoredBuildAssert` (67): the three words' layouts |
   | `lanes.cairo` | `StoredLanes` (80), with the `Lanes32` operations `LanesTrait` and `LanesAssert` (`lane above 6`) | `LanesAssert` |
   | `snapshot.cairo` | `StoredSnapshot` (CBT-02e) | `StoredSnapshotAssert` |

   The full models and their packers stay in the entity's file: `adventurer.cairo` (`AdventurerCore`, `AdventurerPlace`, `Build`, `Adventurer`, with the build's and the belt's rules and the adventurer's own checks) and `account.cairo` (`AccountRecord`, `Account`, the owner key, the list's index). They are the layout and the stored models' oracle. What changed: the arithmetic `hub.cairo` and the store used to do on raw felts is now methods of typed stored models, tested beside their code (D-167). One dependency remains both ways inside `models/`: a stored model's file imports its model (for its tests, and `stored_build` the `Build` it decodes), and `adventurer.cairo` imports the stored models for `AdventurerTrait::new` and its checks of the place and pages.
3. **`hub.cairo` as it reads now**, `contracts/persistent/src/systems/hub.cairo`: `set_build` (396) and `enter` (465), then `report` (641). Each entrypoint is the ownership check, the store's reads, the checks, the calls (registry, `FlattenLibrary`, `Instances`) and the store's writes, in the old order. Its logic lives in model methods:
   - the walk of the registry's parts and the elite slot: `BuildAssert::assert_bar` (`models/adventurer.cairo` 313);
   - the potions, which return the modifiers' parts: `BeltAssert::assert_potions` (378);
   - the worn equipment and two hands: `EquippedAssert::assert_worn` (424);
   - the report's return: `StoredPlaceTrait::return_hub` and `returned` (`models/stored_place.cairo` 63, 73);
   - its credit: `ResultsTrait::credit` (`types/results.cairo` 43);
   - its gold: `GoldTrait::credited` (`models/item.cairo` 346).

   The file has no `.read(`, `.write(`, `.entry(` or word offset. Its access checks are `HubAssert` with an `errors` module (16, 28).
4. **One module's tests**, the `mod tests` of `contracts/persistent/src/store.cairo` (696): the account list's swap removal across two pages, the balance pages, the store's word offsets against the derived `Store` of `Adventurer` (`test_adventurer_offsets`, 779), the words the views return as stored. Before this lot such tests sat in `tests/` (`test_words.cairo` and `test_build_words.cairo`, now removed); they are beside their code (D-167).

**Differences from `quiver_quest` 0.2.0's pattern, with their reasons:**
- **Stored models for the words that paths read in part or change one field of.**
  - The models: `StoredCore`, `StoredPlace`, `StoredRecord`, `StoredBuild` and `StoredLanes`.
  - Where `StoredLanes` is used: the account list's pages on write, the balance pages, the pack's equipment page 0, the `equipped` word and the belt word.
  - What they are: each holds the word as stored, typed. Its methods are the arithmetic ENG-04 and ENG-06 had pinned against the packers, and they are pinned again in the stored models' tests.
  - Why not the packers: quiver reads every model through its packer, and here that is measurably dear. The packers cost, in l2 gas, `AdventurerCore` 42k to unpack and 41k to pack, `AdventurerPlace` 18k/15k, `AccountRecord` 20k/18k, a `Lanes32` 16k/22k. A path changes one or two fields or lanes. My first, fully typed version raised `delete_adventurer` by **+34 %** per call (517k → 696k), against D-144's +10 %.
  - Precedent: the closest in quiver is `HeadSlot`, a stored slot read for a few fields.
  - What still goes through its packer: configuration, counters, gold, items, the snapshot, the rules epoch, known skills, and the list pages read whole for the view and `set_account_owner`.
  - What is left raw: no path holds a storage word as a bare `felt252` outside a stored model, except the name (the felt it is) and the six words `get_adventurer_words` returns to the view.
- **Two store methods return stored words** to the views the interface freezes as returning words (`IHubViews::account`'s record via `StoredRecord.word`, and `get_adventurer_words`). A slot never written must read 0 there, where a packer would give `LIVE`.
- **No tracked model, and no `Tracked` trait.** No `Hub` model's writes match one ENG-01 event exactly (D-149). `AdventurerLocated` follows only some writes of `AdventurerPlace`, so it stays emitted by the systems, where it was. The store's module doc says how a later lot adds quiver's mechanism.
- **Separate address hashes.** One store method per model means the map address `h(selector, key)` is recomputed per call, where the old code reused it. That costs about 6,000 l2 gas per extra hash, and it is most of the remaining **+0.4 % to +3.8 % per call** (the largest is `report`, moved). The two reads that every path makes are combined (core and place; an account's owner and record).

**Open question for the owner: the storage's declared types (the one shape difference left).**
- **What quiver does:** it declares its storage with its stored slot types (`Quest_definitions: Map<u32, HeadSlot>`), so its store reads each slot typed and does no address arithmetic.
- **What `Hub` does:** it declares `adventurers: Map<u32, Adventurer>` (the full models). So the store reads an adventurer's stored words through `__storage_pointer_address__`, the offsets `CORE` to `NAME` and `Store::<felt252>::read_at_offset` / `write_at_offset` (`WordImpl`). The same applies to `accounts`' record word, the list pages, the balance pages and the pack pages; `test_adventurer_offsets` pins the offsets against the derived `Store`.
- **The alternative:** declare the storage with the stored types, for example `adventurers: Map<u32, StoredAdventurer>` with `StoredAdventurer { core: StoredCore, place: StoredPlace, build: felt252, belt: StoredLanes, equipped: StoredLanes, name: felt252 }`, each a one-felt `Store`, and `account_adventurers`, `balances`, `packs` as `Map<…, StoredLanes>`.
- **What it would keep:** the same slots and the same addresses. A struct's members are consecutive slots under the map entry's address, and the variables' names do not change. So ENG-01 §3.3's layout and the probe's stream would stay equal, and both checks would prove it: `layout_tests` and `test_adventurer_offsets` in snforge, and the node probe's `--expect`.
- **What it would change:** every store read becomes typed (`self.adventurers.entry(id).core.read()`), and `WordImpl`, the offsets and `__storage_pointer_address__` leave the store. The full models (`AdventurerCore`…) would no longer be the storage's declared types, only the packers' oracle in tests. The views that return stored words would read them through the stored types' `word`.
- **What it would cost:** not measured. A typed read of a one-felt `Store` that only wraps the word should cost about what `read_at_offset` costs, but the struct's member access computes `base + offset` the same way, and the gas would have to be measured per entrypoint (D-144). It touches only `store.cairo`, the `Storage` struct of `hub.cairo` and the tests. Because it is a declared-layout change, it needs the same checks again.
- **My recommendation:** do it in ENG-R1b, measured beside `Instances`' own storage. I have not done it here (fix loop 3's instruction).

## Summary

`Hub` reads and writes its storage only through `HubStoreTrait` (`store.cairo`). The checks are in `Assert` impls with `errors` modules, the unit tests are in the modules they test, and the event stream and the storage layout are proved unchanged on the node by an extended probe. PR: https://github.com/bal7hazar/grimworld/pull/221 (CI green, not merged). The model I ran as is Opus 5.5 (`claude-opus-5-5`), the one the brief names.

## Files changed

- `contracts/persistent/src/store.cairo`: `HubStoreTrait` on `Hub`'s state, with all of `Hub`'s storage access and the module doc (stored words, tracking, layers). No `Tracked` trait since fix loop 2: no model is tracked, and the doc says how a later lot adds it. `Registry`'s `StoreTrait` path methods are kept for ENG-R1b. Holds `layout_tests` (moved from `hub.cairo`) and new `tests`.
- `contracts/persistent/src/systems/hub.cairo`: the entrypoints through the store; `errors` and `HubAssert` (the old `NOT_ADMIN`, `ZERO_ADMIN` and `NOT_INSTANCES` stay re-exported); `WordImpl`, `change_pack`, `equipment` and the layout test moved out.
- `contracts/persistent/src/models/adventurer.cairo`: the full models of an adventurer's words and their packers, `AdventurerTrait::new`; `BeltTrait::request`, `BuildTrait::request`, `BuildAssert::assert_bar`, `BeltAssert::assert_potions`, `EquippedAssert::assert_worn`; `AdventurerAssert::assert_gate`; `assert_emptied` and `assert_owned_in_hub` take stored models; tests. Its stored words and their checks live in the `stored_*` files (fix loops 2 and 3).
- `contracts/persistent/src/models/account.cairo`: `AccountRecord`, `Account`, `OwnerTrait` (it replaces the free function `owner_key`), `AdventurerListTrait::at`, `AdventurerListAssert` (F-6), `errors::NOT_LISTED`; tests. `StoredRecord` moved to `stored_record.cairo` (fix loop 3).
- `contracts/persistent/src/models/stored_core.cairo`, `stored_place.cairo`, `stored_build.cairo` (fix loop 2), `stored_record.cairo` (fix loop 3): one stored model each, with its trait, its `Assert` and `errors` where it owns checks (fix loop 3), and its tests.
- `contracts/persistent/src/models/lanes.cairo` (fix loop 1): `LanesTrait`, `LanesAssert`, `errors::LANE_ABOVE_6`, `StoredLanes`; tests.
- `contracts/persistent/src/types/results.cairo` (fix loop 1): `ResultsTrait::credit`, `reaches_hub`.
- `contracts/persistent/src/models/balance.cairo`: `BalanceAssert`; credit and debit on `StoredLanes`, `apply` and `first_on_page` (fix loop 1); tests.
- `contracts/persistent/src/models/item.cairo`: `Equipment` with `EquipmentTrait` (the old `Hub::equipment` loop, filled by the store item by item); tests from `test_layout`.
- `contracts/persistent/src/helpers.cairo`: `test_pow2_and_bits`, moved in.
- `contracts/persistent/tests/`: `test_words.cairo` and `test_build_words.cairo` removed (moved into the modules); `test_layout.cairo` keeps record sizes and `Market`; `test_accounts.cairo` without `test_stored_words` (moved); imports updated in `test_accounts`, `test_build` and `test_lifecycle`; the budgets of the tests that rose are raised with `// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class`.
- `contracts/tools/lifecycle_probe.py`: `--stream <file>` and `--expect <file>`.
- `contracts/tools/lifecycle-stream-before.json`: the baseline, recorded on `main`'s code before the rework.
- `contracts/tools/lifecycle-probe-output.txt`: the run on the final code.
- `docs/architecture/ENG-01-interfaces.md` §3.3: `HubStoreTrait` named as the only access, `StoreTrait::get_rules_epoch` replaced by `HubStoreTrait::…`.
- `contracts/persistent/GAS.md` and `docs/BUDGETS.md`: generated.

## Commands run

```
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --stream contracts/tools/lifecycle-stream-before.json   # on main's code
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json   # same code, determinism
  {"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build              Finished
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json   # final code
  {"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}
cd contracts/persistent && snforge test     Tests: 211 passed, 0 failed
cd contracts/ephemeral && snforge test      Tests: 53 passed, 0 failed
cd contracts/logic && snforge test          Tests: 512 passed, 0 failed
python3 scripts/gas_budgets.py              wrote 3 GAS.md, docs/BUDGETS.md
python3 scripts/gas_budgets.py --check      gas check: 776 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
python3 contracts/tools/class_sizes.py      Hub 1,107,620 B Sierra, 37,207 CASM felts, 45.42 % (main: 44.71 %); Registry 30.04 %; all ok
grep -nE "\.read\(|\.write\(|\.entry\(|set_word|word\(" contracts/persistent/src/systems/hub.cairo   (no match)
gh pr checks 221                            every check pass (indexer-node skipped)
```

A measurement of the packers, in a temporary test that was removed afterwards (each figure is a test total minus the empty test's 14,220): `AdventurerCore` unpack 42,490 and pack 40,920; `AdventurerPlace` 18,480 and 15,020; `Lanes32` 16,500 and 22,420; `AccountRecord` 19,860 and 18,510; `Gold` unpack 5,460.

**Per call, snforge** (`get_available_gas()` around the dispatcher call, the lines the tests print). "Before" is `main`'s CI at `03feca2` (run 36804860352); "after" is this branch's final code.

| Call | Before | After | Δ |
|---|---:|---:|---:|
| register | 346,240 | 347,740 | +0.4 % |
| create_adventurer cold / initialised | 815,230 / 834,150 | 824,390 / 843,310 | +1.1 % |
| delete_adventurer, one page | 516,950 | 535,680 | +3.6 % |
| delete_adventurer, worst of two pages | 671,650 | 690,620 | +2.8 % |
| set_account_owner, none / seven inside | 479,170 / 1,975,840 | 493,810 / 2,002,330 | +3.1 % / +1.3 % |
| set_build, empty | 1,981,213 | 2,010,003 | +1.5 % |
| set_build, 7 pieces alone | 3,622,777 | 3,704,617 | +2.3 % |
| set_build, worst case | 8,124,823 | 8,210,773 | +1.1 % |
| enter, no belt / 4 pages | 1,433,550 / 1,953,730 | 1,439,840 / 1,965,250 | +0.4 % / +0.6 % |
| report, moved / returned with 4 pages | 273,873 / 1,037,709 | 279,893 / 1,060,849 | +2.2 % |

Every "after" figure is from the last full run on the final code (`snforge test`, 211 passed). **On the node** (the probe's receipts), all 27 recorded transactions cost the same l2 gas as before, except `set_build, the belt's counts changed`: 3,491,200 → 3,531,200 (+40,000, +1.15 %; the node's figures move in steps of 40,000).

## Cost

`python3 scripts/gas_budgets.py --report` after fix loop 3: 817 rows. 660 are unchanged. The 157 others are below: 75 raised (at most +0.81 % of a whole test), 55 new and 23 removed (unit tests in `src/`, moved or new, under new paths), and 4 marked "+0.0 %" or "+0.1 %".

| Entrypoint or algorithm | Before | After | Budget | Note |
| grimworld_ephemeral::systems::instances::close_tests::test_close_on_defeat | 4805780 | 4805780 | 5046069 | unchanged |
| grimworld_persistent::helpers::tests::test_pow2_and_bits | — | 3967220 | 4165581 | new |
| grimworld_persistent::models::account::tests::test_account_layout | — | 53100 | 55755 | new |
| grimworld_persistent::models::account::tests::test_list_at | — | 13720 | 14406 | new |
| grimworld_persistent::models::account::tests::test_not_listed_refused | — | 15520 | 16296 | new |
| grimworld_persistent::models::account::tests::test_owner_key | — | 13720 | 14406 | new |
| grimworld_persistent::models::adventurer::tests::test_adventurer_layout | — | 279210 | 293171 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_and_potions | — | 40220 | 42231 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_elite | — | 144280 | 151494 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_elite_slot_refused | — | 64460 | 67683 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_profession_refused | — | 29480 | 30954 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_two_elites_refused | — | 44180 | 46389 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_bar_unknown_refused | — | 26410 | 27731 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_potions_refused | — | 26470 | 27794 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_worn | — | 137138 | 143995 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_worn_not_in_pack_refused | — | 41160 | 43218 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_worn_two_hands_refused | — | 77319 | 81185 | new |
| grimworld_persistent::models::adventurer::tests::test_assert_worn_wrong_slot_refused | — | 46513 | 48839 | new |
| grimworld_persistent::models::adventurer::tests::test_attribute_indices | — | 97050 | 101903 | new |
| grimworld_persistent::models::adventurer::tests::test_attribute_points | — | 298290 | 313205 | new |
| grimworld_persistent::models::adventurer::tests::test_attributes_above_36_bits_refused | — | 41350 | 43418 | new |
| grimworld_persistent::models::adventurer::tests::test_belt_word | — | 130770 | 137309 | new |
| grimworld_persistent::models::adventurer::tests::test_known_skills_bits | — | 165890 | 174185 | new |
| grimworld_persistent::models::adventurer::tests::test_known_skills_past_page_255 | — | 15520 | 16296 | new |
| grimworld_persistent::models::adventurer::tests::test_new_adventurer_words | — | 139200 | 146160 | new |
| grimworld_persistent::models::balance::tests::test_apply | — | 142010 | 149111 | new |
| grimworld_persistent::models::balance::tests::test_balance_pages | — | 171990 | 180590 | new |
| grimworld_persistent::models::balance::tests::test_belt_merge | — | 518560 | 544488 | new |
| grimworld_persistent::models::balance::tests::test_credit_overflow_refused | — | 45040 | 47292 | new |
| grimworld_persistent::models::balance::tests::test_debit_too_much_refused | — | 44740 | 46977 | new |
| grimworld_persistent::models::item::tests::test_equipment | — | 151376 | 158945 | new |
| grimworld_persistent::models::item::tests::test_item_grimoire_rift_layout | — | 346320 | 363636 | new |
| grimworld_persistent::models::item::tests::test_item_hands_too_wide | — | 15520 | 16296 | new |
| grimworld_persistent::models::item::tests::test_item_slot_and_hands | — | 180300 | 189315 | new |
| grimworld_persistent::models::item::tests::test_item_slot_too_wide | — | 15520 | 16296 | new |
| grimworld_persistent::models::item::tests::test_pairs_overflow_refused | — | 15520 | 16296 | new |
| grimworld_persistent::models::lanes::tests::test_lane_above_6_refused | — | 15520 | 16296 | new |
| grimworld_persistent::models::lanes::tests::test_lanes | — | 254110 | 266816 | new |
| grimworld_persistent::models::lanes::tests::test_stored_lane_above_6_refused | — | 18020 | 18921 | new |
| grimworld_persistent::models::lanes::tests::test_stored_lanes | — | 290950 | 305498 | new |
| grimworld_persistent::models::stored_build::tests::test_stored_build | — | 180580 | 189609 | new |
| grimworld_persistent::models::stored_core::tests::test_core_words | — | 287770 | 302159 | new |
| grimworld_persistent::models::stored_core::tests::test_experience_overflow_refused | — | 74200 | 77910 | new |
| grimworld_persistent::models::stored_place::tests::test_place_hub_above_63_refused | — | 22650 | 23783 | new |
| grimworld_persistent::models::stored_place::tests::test_place_returned | — | 105396 | 110666 | new |
| grimworld_persistent::models::stored_place::tests::test_place_words | — | 2549385 | 2676855 | new |
| grimworld_persistent::models::stored_record::tests::test_record_words | — | 115470 | 121244 | new |
| grimworld_persistent::store::layout_tests::test_hub_storage_addresses | — | 272150 | 285758 | new |
| grimworld_persistent::store::tests::test_adventurer_offsets | — | 6847530 | 7189907 | new |
| grimworld_persistent::store::tests::test_change_balances | — | 2049990 | 2152490 | new |
| grimworld_persistent::store::tests::test_change_balances_refused | — | 96880 | 101724 | new |
| grimworld_persistent::store::tests::test_list_insert_and_swap_removal | — | 2927960 | 3074358 | new |
| grimworld_persistent::store::tests::test_remove_not_listed_refused | — | 670510 | 704036 | new |
| grimworld_persistent::store::tests::test_words_as_stored | — | 3656130 | 3838937 | new |
| grimworld_persistent::test_accounts::test_create_adventurer | 23912650 | 23924760 | 25120998 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9282830 | 9286710 | 9751046 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.0 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9284190 | 9296770 | 9761609 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19463580 | 19504540 | 20479767 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7643760 | 7654840 | 8037582 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40906580 | 40993530 | 43043207 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 14004730 | 14035730 | 14737517 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 13009460 | 13039650 | 13691633 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 28088690 | 28127740 | 29534127 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24321580 | 24368650 | 25587083 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 13090280 | 13120470 | 13776494 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13413230 | 13443420 | 14115591 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13389740 | 13420730 | 14091767 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21251850 | 21316900 | 22382745 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49522440 | 49645760 | 52128048 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23917120 | 23956670 | 25154504 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40960180 | 41047380 | 43099749 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 17048220 | 17097510 | 17952386 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13407860 | 13459020 | 14131971 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 13015190 | 13047000 | 13699350 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18698190 | 18760310 | 19698326 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_register | 14970940 | 14965630 | 15713912 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; -0.0 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9127390 | 9131900 | 9588495 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27482610 | 27575570 | 28954349 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21205830 | 21269680 | 22333164 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21601670 | 21630020 | 22711521 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42805420 | 42901130 | 45046187 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14782090 | 14832190 | 15573800 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12815890 | 12846420 | 13488741 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13141760 | 13190360 | 13849878 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_admin::test_hub_set_admin_hands_over | 5926910 | 5929920 | 6223256 | +0.1 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_by_admin | 5214550 | 5216050 | 5475278 | +0.0 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_refused_to_others | 4177590 | 4179100 | 4311605 | +0.0 % |
| grimworld_persistent::test_build::test_attributes_indices | 85644769 | 85809839 | 90100331 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 93594854 | 93937854 | 98634747 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 79147396 | 79279896 | 83243891 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 75617033 | 75694693 | 79479428 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_bar_elite | 79943743 | 80184883 | 84194128 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 80070126 | 80287446 | 84301819 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_build::test_bar_profession | 76363243 | 76496943 | 80321791 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 78969026 | 79128876 | 83085320 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_belt_items | 77633493 | 77797783 | 81687673 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 83465350 | 83822380 | 88013499 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 83100168 | 83421308 | 87592374 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_build::test_set_build_empty | 78954890 | 79099250 | 83054213 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_set_build_floor_refused | 96302714 | 96413124 | 101233781 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_insignia_piece_refused | 95908001 | 96010811 | 100811352 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 78791513 | 78900493 | 82845518 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_modifier_slot_and_value_refused | 99724276 | 99906486 | 104901811 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 76102033 | 76192263 | 80001877 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_parts | 82756976 | 82965516 | 87113792 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_build::test_set_build_requests_the_input_kinds | 109841165 | 109954935 | 115452682 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_sixth_rune_refused | 100499045 | 100669955 | 105703453 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_energy | 86409347 | 86487657 | 90812040 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_health | 102170601 | 102279161 | 107393120 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_unknown_modifier_refused | 91670889 | 91734009 | 96320710 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_build::test_set_build_worst_case | 115349374 | 115550494 | 121328019 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_fate::test_fate_at_the_configured_address | 4796206 | 4797706 | 4941989 | +0.0 % |
| grimworld_persistent::test_lifecycle::test_enter | 39954360 | 39988640 | 41988072 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_after_other_records_changed | 43499013 | 43549743 | 45727231 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 47088443 | 47154763 | 49512502 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_after_the_rules_epoch_wraps | 37992276 | 38089506 | 39993982 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 33946190 | 33968220 | 35666631 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 46305790 | 46489140 | 48813597 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_missing_snapshot | 35665043 | 35727183 | 37513543 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_stale_snapshot | 45023372 | 45204602 | 47464833 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_a_new_registry | 39132206 | 39230936 | 41192483 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_a_new_rules_class | 39583236 | 39693376 | 41678045 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_an_input_rewritten | 49879362 | 50060592 | 52563622 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.4 % |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 37581970 | 37617000 | 39497850 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 38469771 | 38570814 | 40499355 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_report_open | 37509452 | 37587942 | 39467340 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 38042694 | 38350427 | 40267949 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.8 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 38151089 | 38210549 | 40121077 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.2 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 39122822 | 39248498 | 41210923 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_rules_epoch_full_cycle_reads_fresh | 320612303 | 321453853 | 337526546 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.3 % |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 27372020 | 27384480 | 28753704 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.0 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 29324180 | 29277900 | 30741795 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; -0.2 % |
| grimworld_persistent::test_lifecycle::test_travel | 35609927 | 35630367 | 37411886 | raised: ENG-R1a (D-144): the store's map addresses, a larger Hub class; +0.1 % |
| grimworld_persistent::types::results::tests::test_credit | — | 324070 | 340274 | new |
| grimworld_persistent::types::results::tests::test_reaches_hub | — | 23589 | 24769 | new |
| grimworld_persistent::systems::hub::layout_tests::test_hub_storage_addresses | 272150 | — | — | removed |
| grimworld_persistent::test_accounts::test_stored_words | 577200 | — | — | removed |
| grimworld_persistent::test_build_words::test_attribute_indices | 97050 | — | — | removed |
| grimworld_persistent::test_build_words::test_attribute_points | 298290 | — | — | removed |
| grimworld_persistent::test_build_words::test_known_skills_bits | 160860 | — | — | removed |
| grimworld_persistent::test_build_words::test_known_skills_past_page_255 | 15520 | — | — | removed |
| grimworld_persistent::test_build_words::test_pow2_and_bits | 3967220 | — | — | removed |
| grimworld_persistent::test_layout::test_account_and_adventurer_layout | 317670 | — | — | removed |
| grimworld_persistent::test_layout::test_attributes_above_36_bits_refused | 41350 | — | — | removed |
| grimworld_persistent::test_layout::test_item_grimoire_rift_layout | 346320 | — | — | removed |
| grimworld_persistent::test_layout::test_item_hands_too_wide | 15520 | — | — | removed |
| grimworld_persistent::test_layout::test_item_slot_and_hands | 180300 | — | — | removed |
| grimworld_persistent::test_layout::test_item_slot_too_wide | 15520 | — | — | removed |
| grimworld_persistent::test_layout::test_pairs_overflow_refused | 15520 | — | — | removed |
| grimworld_persistent::test_words::test_balance_pages | 283660 | — | — | removed |
| grimworld_persistent::test_words::test_belt_merge | 518560 | — | — | removed |
| grimworld_persistent::test_words::test_belt_word | 85450 | — | — | removed |
| grimworld_persistent::test_words::test_core_words | 172230 | — | — | removed |
| grimworld_persistent::test_words::test_credit_overflow_refused | 45040 | — | — | removed |
| grimworld_persistent::test_words::test_debit_too_much_refused | 44740 | — | — | removed |
| grimworld_persistent::test_words::test_experience_overflow_refused | 74200 | — | — | removed |
| grimworld_persistent::test_words::test_place_hub_above_63_refused | 22650 | — | — | removed |
| grimworld_persistent::test_words::test_place_words | 2541665 | — | — | removed |

## Acceptance criteria

- **AC-1** The grep above finds nothing in `systems/hub.cairo`. No reason is needed.
- **AC-2** Checks are in `Assert` impls with `errors`:
  - `HubAssert` (admin, zero admin, `Instances`);
  - `AdventurerListAssert` (F-6: `not in the account list`, evaluated at the same point of the scan; `lane above 6`, now a never-returning arm in `unit`, `get`, `set` and `BalanceTrait::amount`);
  - `AdventurerAssert` (`assert_gate`, which replaces the inline `assert(exists(parts), gate::errors::NONE)` in `enter`; `assert_experience`; `hub_above_63`);
  - `BalanceAssert` (credit, debit).

  The messages are the same. The touched files hold no free function: `owner_key` became `OwnerTrait::key`. `market_key` (`models/market.cairo`) is untouched and belongs to ENG-R1b.
- **AC-3** The probe is extended to record each transaction's `Hub` storage writes (key, value), every `Hub` event with its keys and data, every `Instances` event's name in order, and `Hub`'s final storage. Deployed addresses and the class hash are normalised to names. Before (`main`'s code) and after (final code): `"stream": "equal"`, 85 transactions, 38 events, 97 keys of `Hub`. It also ran twice on `main`'s code with an equal result, so the comparison is deterministic.
- **AC-4** All budgets hold; the 75 rises are commented `raised` under D-144. Per call the rise is at most +3.8 % (`report`, moved: 273,873 → 284,323), within +10 %. `Hub` is at 45.89 %, under 50 % (figures of fix loop 2).
- **AC-5** The unit tests are in their modules: `store`, `models::{account, adventurer, balance, item, lanes, stored_build, stored_core, stored_place, stored_record}`, `types::results`, `helpers`. Integration tests and benchmarks stay in `tests/`, and the two unit tests left there say why (`test_record_sizes`: `Market`'s, ENG-R1b; `test_playable_professions`: the logic package's, ENG-R1c). CI is green; `gas_budgets.py --check` and `class_sizes.py` pass.
- **AC-6** The reading section opens this report.

**Tracking table**

| Model (store methods) | Tracked | Event | Reason |
|---|---|---|---|
| `Adventurer`: core, place, build words (`StoredCore`, `StoredPlace`, `StoredBuild`) | no | `AdventurerLocated` stays emitted by `enter`, `travel` and `report` | Creation and a Moved report write the place without the event (D-03, ENG-01 §5); a tracked place would add events. D-149: no change |
| `Account`, `account_of`, account list (`StoredRecord`, ids) | no | — | No ENG-01 event |
| balances, gold, items, packs, known skills | no | — | No ENG-01 event |
| `StoredSnapshot`, `RulesEpoch`, configuration, counters | no | — | Untracked since CBT-02e and CBT-02f; no event |
| (`TitleDisplayed`) | — | emitted, never stored (T-1) | Not a model |

## Deviations from the brief

- "The models `StorePacking`, never raw felts in the systems": the systems hold no raw felt from storage. But the hot words are read and written as typed stored models with their arithmetic rather than through the models' packers, because the packers measured beyond D-144 (see the reading section). The packers remain the layout and the tests' oracle.
- Not every store method is `get_x`/`set_x` of one whole model. Combined focused reads (`get_core_place`, `get_account`/`set_account`) save one address hash each on every path that names an adventurer or an account.
- The node probe's comparison, not an snforge test, is the event-stream check, as the brief allows ("a test (or the node probe)").

## Escalations

None blocking. For the orchestrator's review of the raised budgets: 75 whole tests rose, at most +0.81 %. Part of that is the larger `Hub` class that each test declares (+1.18 points of the limit, 44.71 % → 45.89 %), part is the store's per-call address hashes.

For the project manager (shared files, outside my allowlist): PLAN's ENG-R1b row could name the probe's run `--expect contracts/tools/lifecycle-stream-before.json` as an acceptance criterion; and a CI job could run it through `scripts/with-node.sh`, so that no lot relies on a run by hand (Sonnet note 4, fix loop 2).

## Open questions

- Should the owner want quiver's literal shape (every model through its packer), the cost is measured above: `delete_adventurer` +34 % per call before the stored models. That would need a decision beyond D-144.
- `StoredCore::with_pack_lanes` keeps the felt arithmetic of ENG-06. A `pack_lanes` that went below 0 would corrupt the word rather than refuse; this is unreachable today, and unchanged from before.

## Fix loop 1

Input: the Claude-side quality and organisation audit at 8b16ba5 (`[Opus 5.5]`, PASS WITH FINDINGS: 4 minors, 7 notes). Codex's audits and review are deferred until its quota returns. The head after this loop is 45ff32b. First, `origin/main` was merged (fd15165, documents only).

**What changed, finding by finding:**

| # | Finding | Fix |
|---|---|---|
| 1 | The owner's section understated the raw-word paths | Rewritten above: the section names every path read or written as a stored word, which model it now goes through, and why. No path holds a bare storage `felt252` outside a stored model, except the view's six words |
| 2 | Lane arithmetic on raw felts in the store | New `models/lanes.cairo`: `StoredLanes` with `new`, `get`, `ids`, `is_empty`, `added`, `removed`, `replaced`, pinned against `Lanes32`'s packer (`test_stored_lanes`). `add_adventurer_id` and `remove_adventurer_id` read and write `StoredLanes` and keep their reads, writes and scan order. `change_balances` reads each page, calls `BalanceTrait::apply` (and `first_on_page`), and writes it. `BalanceTrait::credit`/`debit` take `StoredLanes`; `BalanceTrait::amount` is gone. `get_belt`, `get_equipped` and `get_pack_page` return `StoredLanes`; `AdventurerAssert::assert_emptied` checks `is_empty()`. `StoredBuild.belt` and `.equipped` are `StoredLanes`. The store holds no arithmetic now; its only computation left is the counters' `value + 1`, on the typed `Counter` |
| 3 | Logic in entrypoints | `set_build`: `BuildAssert::assert_bar` (the parts walk, the skill checks, one elite, `elite_slot`), `BeltAssert::assert_potions`, `EquippedAssert::assert_worn` (wearable, slot, two hands), `EquipmentTrait::request`. `report`: `ResultsTrait::credit` and `reaches_hub`, `GoldTrait::credited`, `StoredPlaceTrait::return_hub` and `returned`. The checks run in the same order with the same messages; the probe's stream is equal |
| 4 | Lane helpers under the adventurer list | `LanesTrait::{unit, get, set}` and `LanesAssert::lane_above_6` with `lanes::errors::LANE_ABOVE_6` ('lane above 6', same message), in `models/lanes.cairo`. `AdventurerListTrait` keeps `at` alone, and `account::errors` no longer holds the lane error |
| 6 | Stale doc comment | Now names `StoredCoreTrait::with_experience` |
| 8 | Two unit tests in `tests/` with no reason | The slot counts of `Account`, `Adventurer`, `Item` and `Grimoire` moved into their models' tests. `test_record_sizes` keeps `Trade` and `Lot` with the reason written above (`models::market` is ENG-R1b's). `test_playable_professions` has its one-line reason (ENG-R1c, the logic package) |
| 5 | `assert_gate` under the adventurer | Left as it is, as asked: `GateAssert` and `RegionAssert` are ENG-R1c's (the logic package) |
| 7 | `lane_above_6` and `hub_above_63` naming | Left as it is (the audit found it acceptable) |

**Commands run in this loop:**

```
git merge origin/main                                                 fd15165, documents only
cd contracts/persistent && snforge test     Tests: 218 passed, 0 failed
cd contracts/ephemeral && snforge test      Tests: 53 passed, 0 failed
cd contracts/logic && snforge test          Tests: 512 passed, 0 failed
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build              Finished
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
  {"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}
python3 contracts/tools/class_sizes.py      Hub 1,118,896 B Sierra, 37,589 CASM felts, 45.89 % (round 0: 45.42 %; main: 44.71 %)
python3 scripts/gas_budgets.py              GAS.md and BUDGETS.md regenerated
python3 scripts/gas_budgets.py --check      gas check: 783 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
grep -nE "\.read\(|\.write\(|\.entry\(|set_word|word\(" contracts/persistent/src/systems/hub.cairo   (no match)
gh pr checks 221                            every check pass (indexer-node skipped)
```

**Rows that changed, per call (snforge, against `main`'s CI at 03feca2):**

| Call | main | Round 0 | Fix loop 1 | Δ against main |
|---|---:|---:|---:|---:|
| register | 346,240 | 347,740 | 347,740 | +0.4 % |
| create_adventurer cold | 815,230 | 824,390 | 824,690 | +1.2 % |
| delete_adventurer, one page | 516,950 | 535,680 | 534,780 | +3.4 % |
| delete_adventurer, worst of two pages | 671,650 | 690,620 | 689,980 | +2.7 % |
| set_account_owner, seven inside | 1,975,840 | 2,002,330 | 2,002,330 | +1.3 % |
| set_build, empty | 1,981,213 | 2,010,003 | 2,011,403 | +1.5 % |
| set_build, 7 pieces alone | 3,622,777 | 3,704,617 | 3,706,017 | +2.3 % |
| set_build, worst case | 8,124,823 | 8,210,773 | 8,210,973 | +1.1 % |
| enter, no belt / 4 pages | 1,433,550 / 1,953,730 | 1,439,840 / 1,965,250 | 1,439,730 / 1,976,300 | +0.4 % / +1.2 % |
| report, moved / returned with 4 pages | 273,873 / 1,037,709 | 279,893 / 1,060,849 | 284,323 / 1,062,139 | +3.8 % / +2.4 % |

Every rise is within D-144's +10 %; the budgets of the tests that rose carry their `raised` reason.

On the node (the probe's receipts), all 27 recorded transactions cost the same as in round 0. Only one differs from `main`: `set_build, the belt's counts changed`, 3,491,200 → 3,531,200 (+1.15 %), unchanged from round 0.

`gas_budgets.py --report` now has 805 rows: 660 unchanged, and 145 that change. Those 145 are 75 raised (the same tests as round 0, at most +0.81 % of a whole test), 43 new (the unit tests in `src/`, moved or new), 23 removed (moved) and 4 marked "+0.0 %" or "+0.1 %". The table under *Cost* is the one of this loop.

## Fix loop 2

Inputs:
- the Claude Sonnet quality run at 45ff32b (2 minors, 3 notes);
- what PLAN's ENG-R1 row defers to this loop, from the Opus re-audit at 45ff32b (1 minor, 6 notes).

The rule now is D-175: audits are Claude Opus 5.5 and reviews Claude Sonnet while Codex has no quota. First, `origin/main` was merged (4758092, documents only; nothing under `contracts/`, `scripts/` or `.github/`). The head after this loop is dd0282e.

| Item | Fix |
|---|---|
| Sonnet minor 1: stored models outside §7's one file per entity | `StoredCore`, `StoredPlace` and `StoredBuild` each have their own file, with their tests: `models/stored_core.cairo`, `models/stored_place.cairo` and `models/stored_build.cairo`. They sit beside `StoredRecord` (`account.cairo`), `StoredSnapshot` (`snapshot.cairo`) and `StoredLanes` (`lanes.cairo`). `adventurer.cairo` (1,013 lines, was 1,300 or more) keeps the full models and their packers, the build's and the belt's rules, and the adventurer's checks, and says so in its doc. The stored models still raise the adventurer's errors through `AdventurerAssert` (`hub above 63`, `experience overflow`): same messages, and the constants still live in `adventurer::errors`, where the tests import them |
| Sonnet minor 2: `Tracked` with no impl | **Removed.** I chose removal over a throwaway impl and test. A test model would pin a mechanism no `Hub` model uses, and ENG-R1b, ENG-R1c or the lot that tracks a model would rewrite it to its consumer's constant anyway. The store's module doc now states that no `Hub` model is tracked and why (D-149). It also describes how a later lot adds tracking on quiver's pattern: a `Tracked<M>` impl on the tracked model alone, a consumer's constant per model, the `set_x` emit behind it, and a test per tracked and per untracked model |
| Opus minor 1: the report's cost range | The owner's section says "+0.4 % to +3.8 % per call". AC-4 and *Escalations* use this loop's figures |
| Opus note 3: `StoredLanes::ids` | Renamed `decoded` |
| Opus note 4: the `Adventurer` word offsets | `store::tests::test_adventurer_offsets`. An adventurer written through the typed `adventurers.entry(id)` path reads back through `get_core`, `get_place`, `get_core_place`, `get_belt`, `get_equipped` and `get_adventurer_words`. One written through `set_adventurer` and `set_adventurer_build` reads back through the typed path, field by field |
| Opus note 5: thin unit tests | `results::tests::{test_credit, test_reaches_hub}`. `adventurer::tests::test_assert_bar_elite` covers the two-parts-a-skill walk, empty slots skipped, with and without an elite. Three refusals each have their own test: two elites, the wrong elite slot, the wrong profession. `adventurer::tests::test_assert_worn` covers a two-handed weapon, a one-handed weapon with an off-hand and nothing worn. Its refusals have their own tests: two hands, the wrong slot, not in the pack |
| Opus note 2: part cursors in `set_build` | `BeltTrait::request` returns how many items it appended, and `BeltAssert::assert_potions` returns the parts after the potions (the modifiers', which the flattening reads). `set_build` keeps no `requests.len()`, subtraction or `slice` |
| Opus note 6: the comment's wrap | `tests/test_layout.cairo`'s header reflowed |
| Opus note 1 (a–c): precision points | (a) The owner's section now says "no word arithmetic" and names the bookkeeping the store keeps. (b) It gives `return_hub` and `returned` their own lines (64 and 74 in `stored_place.cairo`). (c) It names the name word |
| Sonnet note 3: the store depends on `systems::hub`; the layout test sits in the store | **Fixed in the doc.** The store's module doc gains a *Layers* paragraph: the dependency is intended, as quiver's store on its component's state, and the store serves `Hub` alone. `layout_tests` is in the store because the store reads and writes those addresses |
| Sonnet note 4: the probe and its "before" file are run by hand, and nothing says the file is a contract | **Fixed in the probe; the name is kept.** The probe's doc now says that `lifecycle-stream-before.json` is the stream the indexer reads and the storage `Hub` keeps, and that ENG-R1b and every later lot touching `Hub`'s storage or events run `--expect` against it. A change of it is a change of ENG-01's frozen events or layout (D-149). I kept the name: your hard limits and PLAN's row name it, and renaming would break both. Escalation below: PLAN's ENG-R1b row should name this run, and a CI job could run it with `scripts/with-node.sh` (`.github/` is outside my allowlist) |
| Sonnet note 5: "Untracked" written above each group | **Fixed.** The per-group words are gone; the module doc carries the decision once |

**Commands run in this loop:**

```
git merge origin/main                                                 4758092, documents only
cd contracts/persistent && snforge test     Tests: 229 passed, 0 failed
cd contracts/ephemeral && snforge test      Tests: 53 passed, 0 failed
cd contracts/logic && snforge test          Tests: 512 passed, 0 failed
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build              Finished
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
  {"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}
python3 contracts/tools/class_sizes.py      Hub 1,116,717 B Sierra, 37,589 CASM felts, 45.89 % (fix loop 1: 45.89 %)
python3 scripts/gas_budgets.py              GAS.md and BUDGETS.md regenerated
python3 scripts/gas_budgets.py --check      gas check: 794 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
grep -nE "\.read\(|\.write\(|\.entry\(|set_word|word\(" contracts/persistent/src/systems/hub.cairo   (no match)
gh pr checks 221                            every check pass (indexer-node skipped), at dd0282e
```

**Rows that changed, per call (snforge, against `main`'s CI at 03feca2).** Only `set_build` moved, because the cursors went into the models. Every other call measures as in fix loop 1.

| Call | main | Fix loop 1 | Fix loop 2 | Δ against main |
|---|---:|---:|---:|---:|
| set_build, empty | 1,981,213 | 2,011,403 | 2,013,303 | +1.6 % |
| set_build, 7 pieces alone | 3,622,777 | 3,706,017 | 3,707,917 | +2.4 % |
| set_build, 8 skills alone | 2,973,013 | 3,007,463 | 3,009,363 | +1.2 % |
| set_build, worst case | 8,124,823 | 8,210,973 | 8,213,673 | +1.1 % |

The largest per-call rise is unchanged: `report, moved`, 273,873 → 284,323 (+3.8 %), within D-144's +10 %.

On the node, all 27 recorded transactions cost the same as in fix loop 1. Only one differs from `main`: `set_build, the belt's counts changed`, +40,000 (+1.15 %).

`gas_budgets.py --report` now has 816 rows: 660 unchanged, and 156 that change. Those 156 are 75 raised (the same tests, at most +0.81 % of a whole test), 54 new (unit tests in `src/`), 23 removed and 4 marked "+0.0 %" or "+0.1 %". The table under *Cost* is the one of this loop.

## Fix loop 3

Input: the organisation audit at dd0282e (Claude Opus 5.5, D-177, design lens): PASS WITH FINDINGS, 1 minor and 6 notes. First, `origin/main` was merged (65a0039, documents and a spike only; nothing under `contracts/`, `scripts/` or `.github/`). The head after this loop is 5b25a43.

| Item | Fix |
|---|---|
| Minor 1: "each stored model has its own file" was not true, and the new files had no `Assert`/`errors` | **True and uniform now.** `StoredRecord` moved from `account.cairo` to `models/stored_record.cairo`, with its tests (`test_record_words`); `account.cairo` keeps the model, its packer and a `test_account_layout` (round trip, two slots). Each stored model's file holds its struct, its trait, its `Assert` and `errors` where it owns checks, and its tests. `stored_core`: `StoredCoreAssert::assert_experience`, `errors::EXPERIENCE_OVERFLOW`. `stored_place`: `StoredPlaceAssert::{assert_unlocked, assert_in_instance, hub_above_63}`, `errors::{HUB_ABOVE_63, NOT_UNLOCKED, NOT_ITS_INSTANCE}`. `stored_build`: `StoredBuildAssert::{assert_build_layout, assert_belt_layout, assert_equipped_layout}`, `errors::{BUILD_LAYOUT, BELT_LAYOUT, EQUIPPED_LAYOUT}`. `stored_record`: no check; a free slot is `AccountAssert`'s. These checks and constants left `AdventurerAssert`, `BuildAssert`, `BeltAssert`, `EquippedAssert` and `adventurer::errors`. The messages are the same, and the tests import the constants from their new modules. `hub.cairo` calls `place.assert_unlocked(hub)` and `place.assert_in_instance(...)`. The owner's section has a table of what is where, and names the one two-way import left inside `models/` |
| Note 2: "HubStore" named nothing | **`HubStoreTrait` everywhere**: the 10 doc comments, the store's module doc, ENG-01 §3.3 (2) and REPORT.md. The owner's section says once that the impl is `HubStoreImpl` |
| Note 3: stale references | (a) The store's module doc now names the stored models' files, each of which gives its packer's measured cost. (b) *Files changed* now says where each stored model lives. (c) AC-5 lists every module with unit tests |
| Note 4: the storage declared with the full models, read at offsets | **Not changed, as asked.** It is the open question at the end of the owner's section: what it would keep (the same slots and addresses, so the layout test, the offsets test and the probe stay equal), what it would change (typed reads, `WordImpl` and the offsets gone), what it would cost (not measured), and my recommendation (ENG-R1b, measured) |
| Note 5: "one `get_x`/`set_x` per model" not literal | **Fixed in the owner's section**: each model has its getter and setter, and some have focused reads of part of it or a pair under one address (`get_account`, `get_core_place`) |
| Note 6 | **Not read.** The audit file `ENG-R1a-organisation-opus.md` ends in the middle of note 5 ("There is one `"), so note 6's text is not in it. I fixed what its table names (findings 1 to 5). If note 6 holds something else, I need its text |

**Commands run in this loop:**

```
git merge origin/main                                                 65a0039, documents and a spike only
cd contracts/persistent && snforge test     Tests: 230 passed, 0 failed
cd contracts/ephemeral && snforge test      Tests: 53 passed, 0 failed
cd contracts/logic && snforge test          Tests: 512 passed, 0 failed
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build              Finished
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
  {"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}
python3 contracts/tools/class_sizes.py      Hub 1,116,867 B Sierra, 37,589 CASM felts, 45.89 % (unchanged)
python3 scripts/gas_budgets.py              GAS.md and BUDGETS.md regenerated
python3 scripts/gas_budgets.py --check      gas check: 795 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
grep -nE "\.read\(|\.write\(|\.entry\(|set_word|word\(" contracts/persistent/src/systems/hub.cairo   (no match)
gh pr checks 221                            15 pass (indexer-node skipped), at 5b25a43
```

**Rows that changed:**
- **Per call:** none. Every per-call figure printed by the tests equals fix loop 2's; the largest rise against `main` is still `report, moved`, +3.8 %.
- **On the node:** all 27 recorded transactions cost the same as in fix loop 2.
- **The report table:** `gas_budgets.py --report` now has 817 rows, 157 of them changed: 75 raised (the same tests, at most +0.81 % of a whole test), 55 new (one more: `test_account_layout`), 23 removed and 4 marked "+0.0 %" or "+0.1 %". The table under *Cost* is this loop's.
