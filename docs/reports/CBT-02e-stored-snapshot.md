# [Opus 5.5] CBT-02e — The snapshot flattened once at `set_build` and stored with the adventurer

## Summary

D-168 (a) with its three conditions, done. The model that ran is Opus 5.5 (my session), as the brief names.

- **`FlattenLibrary`**, a library class in `grimworld_logic` (`contracts/logic/src/systems/flatten.cairo`; `IFlattenLibrary::words` added to `interface.cairo`; its module line in `systems.cairo`). State in: the build's records as `Hub.set_build` read them (the `Loadout`, each worn item as `snapshot::Worn` {lane, slot, the five modifier ids and rolled values}, the distinct modifier ids and their `MODIFIER` parts). State out: the snapshot's three packed words (`MemberStats`, `MemberBar`, `MemberKit`). CBT-02c's `ItemModsTrait::held` and its checks moved out of `Hub` into `snapshot.cairo` (`WornTrait::held`, `WornAssert`, same error strings), with `SnapshotBuildTrait::words` = held → `build` → pack. Their unit tests are in `snapshot.cairo` (D-167).
- **The call**: `Hub.set_build` calls it with `IFlattenLibraryLibraryDispatcher { class_hash: self.flatten.read() }`, **once, at `set_build` only**. `set_contracts` gains `flatten: ClassHash` (storage `flatten`).
- **The stored words**: `Hub.snapshots: Map<u32, StoredSnapshot>`, **3 slots** an adventurer (`models/snapshot.cairo`). The kit word's free bits (the kit ends at bit 202) hold the registry's **content version** (bits 208–239) and the **stale mark** (bit 240). `set_build` now always makes its one `bundle` call, even for an empty build, to get the version.
- **`enter` copies**: it reads the gate with `bundle` (the content version comes in the same call), refuses `snapshot: missing` (never set) and `snapshot: stale` (mark set, another content version, or `MemberStats.level` other than the adventurer's), then hands the three words **as stored** to `Instances.create`. `create` now takes `SnapshotWords` and writes them without repacking. This was needed for AC-2: the three unpackers in `Hub` alone were 4,684 CASM felts and put it at 51.13 %.
- **Figures**: `Hub` **44.64 %**, `FlattenLibrary` 26.98 %, `Instances` 29.00 % (from 39.60 %). `enter` with the belt's worst case: **4,473,259** net on the node (D-158: 5,250,000; before: 5,233,259). `set_build`'s worst case: 8,097,073 a call (snforge), budget 8,501,927 = its measure. The snapshot's 3 new words cost **1,406,000** on the node, 468,667 each.

PR: https://github.com/bal7hazar/grimworld/pull/212. CI is green on every check (`indexer-node` skipped by its own filter).

## Files changed

- `contracts/logic/src/systems/flatten.cairo`: new, `FlattenLibrary`.
- `contracts/logic/src/systems.cairo`: its module line (`scarb fmt` put it before `tick`).
- `contracts/logic/src/interface.cairo`: `IFlattenLibrary` added. `IInstanceEntry.create`'s `snapshot` parameter changes type to `SnapshotWords`, and the import follows (see *Deviations*).
- `contracts/logic/src/snapshot.cairo`: `Worn`, `WornTrait::held`, `WornAssert` and 4 error constants; `SnapshotBuildTrait::words`; `SnapshotWords`; `SnapshotTrait::words`; unit tests.
- `contracts/logic/tests/test_flatten.cairo`: new. The library call against the direct flattening, and its cost (widest, empty).
- `contracts/persistent/src/models/snapshot.cairo`: new. `StoredSnapshot`, `StoredSnapshotTrait` (`seal`, `kit`), `StoredSnapshotAssert` (`assert_fresh`, `assert_level`), `STALE_MARK`, errors, unit tests.
- `contracts/persistent/src/models.cairo`: the module line.
- `contracts/persistent/src/models/adventurer.cairo`: `BuildTrait::loadout` (CBT-02c's `4ca5802`).
- `contracts/persistent/src/models/item.cairo`: `ItemModsTrait::worn`.
- `contracts/persistent/src/systems/hub.cairo`: `set_contracts(…, flatten)`, storage `flatten` and `snapshots`, the new `set_build` and `enter`, `equipment()`, the layout test.
- `contracts/ephemeral/src/systems/instances.cairo`: `create` receives `SnapshotWords` and writes them as stored (`MemberStateTrait::maxima` for health and energy).
- `contracts/persistent/Scarb.toml`: `build-external-contracts = ["grimworld_logic::systems::flatten::FlattenLibrary"]`, so the persistent tests can declare the library (see *Deviations*).
- Tests: `contracts/persistent/tests/test_build.cairo` (the fixtures of CBT-02c's modifiers, the worst case with 15 modifiers, the refusals, AC-1's extremal and widest builds), `test_lifecycle.cairo` (`put_snapshot`, missing and stale refusals, the copy), `test_accounts.cairo`, `test_admin.cairo`, `test_fate.cairo` (`set_contracts`, the doubles), `contracts/ephemeral/tests/test_lifecycle.cairo` (`snapshot().words()`).
- `contracts/tools/lifecycle_probe.py` and `lifecycle-probe-output.txt`: declare the library, `set_contracts` with it, a `set_build` before each first `enter`, the first-write and overwrite cases.
- `contracts/tools/class_sizes.py`: a class that two packages' artifacts list is printed once.
- `docs/architecture/ENG-01-interfaces.md` §1.3, §3.3, §9.3, §10; `docs/architecture/cost-budget.md`, the hub row.
- `GAS.md` ×3 and `docs/BUDGETS.md`: generated by `gas_budgets.py`.

## Commands run

```
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build     → Finished
$ python3 contracts/tools/class_sizes.py                                → exit 0
  Instances 23,760 felts 29.00 % · FlattenLibrary 22,098 26.98 % · TickLibrary 24.32 % · Registry 30.04 % · Hub 36,572 44.64 %
  (probe, not kept: Hub with enter unpacking the stored words into a Snapshot: 41,885, 51.13 % OVER; without the unpackers 37,201, 45.41 %)
$ cd contracts/logic && snforge test        → Tests: 445 passed, 0 failed
  flatten library call, widest: 3183138 · empty: 745553
$ cd contracts/persistent && snforge test   → Tests: 177 passed, 0 failed
  gas set_build, worst case, first (snapshot new): 8097073 · again (snapshot overwritten): 8097073  (snforge prices a new slot as an overwrite)
  gas set_build, empty: 1953463 · 8 skills alone 2945263 · 200 points alone 1972393 · 4 potions alone 2380723 · 7 pieces alone 3595027
  gas enter, no belt (Instances a double): 1406000 · a belt of 4 pages emptied: 1926180
$ cd contracts/ephemeral && snforge test    → Tests: 53 passed, 0 failed
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt   (receipts; net = − 189,141)
  set_build, empty, first (3 words new)       4,617,200   net 4,428,059   hub new 3
  set_build, empty, again (overwritten)       3,211,200   net 3,022,059
  enter, first entry (cold)                   9,448,400   net 9,259,259   (before 10,488,400)
  enter, later entry, no belt                 3,902,400   net 3,713,259   (before 4,702,400)
  set_build, 4 potions on 4 pages             3,731,200   net 3,542,059   (before 2,611,200: now the library call and 3 snapshot words)
  enter, the belt's worst case (4 pages)      4,662,400   net 4,473,259   (before 5,382,400 / net 5,233,259)
  leave / travel_back / set_account_owner: unchanged
$ scarb --manifest-path contracts/Scarb.toml fmt --workspace            → applied (one commit, formatting only)
$ python3 scripts/gas_budgets.py            → wrote the 3 GAS.md and docs/BUDGETS.md
$ python3 scripts/gas_budgets.py --check    → gas check: 675 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ gh pr checks 212 --watch                  → every check pass (indexer-node skipping)
```

## The library class and its call

`Hub.set_build` does what it did before: ownership, bar, attributes, belt, the equipment's checks on `ItemBase`. It then reads each worn item's `ItemMods` (`equipment()`: ≤ 7 items, ≤ 15 distinct ids), puts the distinct `MODIFIER` ids at the end of its single `bundle` request, builds the `Loadout` (`BuildTrait::loadout`), and makes the library call:

```
IFlattenLibraryLibraryDispatcher { class_hash: self.flatten.read() }
    .words(loadout, worn, modifiers, parts.slice(at, parts.len() - at))  -> (stats, bar, kit)
```

In the library, `WornTrait::held` refuses a modifier the registry lacks, one in the wrong slot type, a rolled value outside its record's range, or an insignia on another piece. `SnapshotBuildTrait::build` then refuses the counts and DS-2's floors. Any refusal reverts `set_build`, so nothing is stored.

## The stored words and their cost (D-168 3)

| | |
|---|---|
| Words | **3** (`StoredSnapshot { stats, bar, kit }`, `Hub.snapshots[adventurer]`): the flattening's packed words, `LIVE` set; the kit word also holds the content version (208–239) and the stale mark (240) |
| First write (an adventurer's first `set_build`) | **+1,406,000** L2 gas on the node for the three (4,428,059 − 3,022,059 net), **468,667 a word** (D-168 said about 453,524) |
| Overwrite (every later `set_build`) | inside `set_build`'s 3,022,059 net for an empty build; snforge prices both the same (8,097,073 either way on the worst case) |
| Write set | `set_build` 3 new + 3 overwritten cold, 0 / 6 after (ENG-01 §9.3); `enter` writes no more than before |
| `set_build`'s worst case | 8,097,073 the call (snforge), budget **8,501,927** = its measure (D-158 (c)); about **9.17 M (E)** the transaction overwriting, **10.57 M (E)** at an adventurer's first (the call + the node's excess over snforge on the empty build, 1,068,596, + 1,406,000). The node cannot build it yet: no entrypoint creates an item or teaches a skill |

## The staleness table (D-168 2)

The flattening's inputs are: the adventurer's level and primary profession (`core`); `build` (bar, elite slot); `belt` (its items, which go into the kit); `equipped`; each worn item's `ItemBase` (slot, the personalised flag) and `ItemMods`; the `MODIFIER` records. When they are laid out, attribute ids, weapon statistics, set bonuses and ratings join them.

**How `enter` detects each case, at no extra cost:**
- **Level**: `enter` compares the stored `MemberStats.level` with `core`'s level (bits 64–71 of the stats word, already read), so a level up needs no mark.
- **Content**: `enter` compares the stored content version with `Registry.bundle`'s, and gets it in the gate's call.
- **Everything else**: the stale mark, one write of the constant `STALE_MARK` with no read.

| Entrypoint | Present / planned | Changes an input? | What it does | Tested |
|---|---|---|---|---|
| `set_build` | present | yes: every input | **recomputes**: flattens and writes the 3 words, clearing any mark and matching the current version and level | `test_enter_refuses_a_stale_snapshot` (each cause cleared by `set_build`), `test_enter_refuses_a_missing_snapshot` |
| `create_adventurer` | present | creates the adventurer | no snapshot: `enter` refuses **`snapshot: missing`** until the first `set_build` | `test_enter_refuses_a_missing_snapshot` |
| `Registry.set_record` (a record rewritten or added) | present | yes: a `MODIFIER`, and any record | the **content version** moves: every stored snapshot is stale (`snapshot: stale`) until its adventurer's next `set_build`. Cost: none on the write; after a content update, one `set_build` per adventurer before its next entry (≈ 3.0 M net for an empty build, up to about 9.17 M E) | `test_enter_refuses_a_stale_snapshot` (a new gate) |
| `report` (`Results`) | present | experience only today (the level is not raised: ENG-06, `with_experience`); the belt's counts come back to the pack, but they are not in the words (`enter` takes them from the belt it debits) | nothing | — |
| GLD-01's level-up | planned | the level | nothing to write: `enter` compares levels and refuses **`snapshot: stale`** | `test_enter_refuses_a_stale_snapshot` (a level written with `store`), `test_other_level_refused` |
| `personalise` | present, not implemented | the personalised flag (and the rating, once laid out) of an item | on a **worn** entity: **mark stale** (`STALE_MARK` to `snapshots[adventurer].kit`); on another, nothing | the mark: `test_enter_refuses_a_stale_snapshot`, `test_stale_mark_refused` |
| `lift_modifier`, `set_modifier` (a rune, an insignia, any slot) | present, not implemented | the item's `ItemMods` | on a worn entity: **mark stale** | the same |
| `identify` | present, not implemented | `ItemMods` of an unidentified item | cannot reach a worn item (`set_build` refuses an unidentified fine item, and a common one has no modifier); if its lot allows it, **mark stale** | — |
| `sell`, `recycle`, `stow` to the vault, `Market.escrow` / `exchange` (an entity leaves the pack) | present, not implemented | `equipped` would name an entity the adventurer no longer holds | **refuse a worn entity** (recommended), or clear its lane and **mark stale**. Otherwise `enter` would copy the modifiers of an item that has gone. Their lots' rule | — |
| `buy_skill` | present, not implemented | no: the flattening reads the bar, and only `set_build` writes it (bar attributes are 0 until D-157 A numbers them) | nothing; if a learnt skill becomes an input (passive skills), **mark stale** | — |
| `claim_quest` (a trial: rank, secondary profession; experience) | present, not implemented | no: rank and secondary are not inputs (they only bound `set_build`'s points and bar); a level it raises is caught as above | nothing | — |
| RWD-06's equipment | planned | new entities into the pack: not worn | nothing; a reward that changes a **worn** item **marks stale** | — |
| `Hub.set_contracts` with another `FlattenLibrary` class | present | the rules themselves | **nothing today**: stored snapshots stay valid (*Escalations* 3) | — |
| `delete_adventurer`, `travel`, `register`, `set_account_owner`, `enter` | present | no | nothing | — |

## The figures against D-158 and 50 %

| | Target | Measured | Result |
|---|---:|---:|---|
| `Hub`'s class | < 50 % | **44.64 %** (36,572 CASM felts) | within; the stop does not apply |
| `FlattenLibrary`'s class | < 50 % | 26.98 % (22,098) | within |
| `Instances`' class | < 50 % | 29.00 % (23,760; was 39.60 %) | within |
| `enter`, the belt's worst case, node net | 5,250,000 (D-158) | **4,473,259** | within, −14.8 % |
| `enter`, no belt, node net | 4,100,000 (ENG-06) | 3,713,259 | within |
| `set_build`, worst case, the call | its measure (D-158 (c), D-168 1) | 8,097,073 → budget 8,501,927 | set |

## Cost

`python3 scripts/gas_budgets.py --report` (origin/main fetched). The rows that changed, of 675; every other row is `unchanged`.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::test_lifecycle::test_create_first_entry | 31910182 | 31788192 | 33377602 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_create_refusals | 33638056 | 33027356 | 34678724 | -1.8 % |
| grimworld_ephemeral::test_lifecycle::test_create_reuses_the_slot | 44465521 | 44099551 | 46304529 | -0.8 % |
| grimworld_ephemeral::test_lifecycle::test_create_sealed | 25997186 | 25875196 | 27168956 | -0.5 % |
| grimworld_ephemeral::test_lifecycle::test_create_without_tasks | 27925856 | 27803866 | 29194060 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_generation_isolation | 46052093 | 45814813 | 48105554 | -0.5 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_hub | 33348126 | 33226136 | 34887443 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_location | 39344897 | 39222907 | 41184053 | -0.3 % |
| grimworld_ephemeral::test_lifecycle::test_not_controller | 28148074 | 28026084 | 29427389 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_refused_absent | 40483822 | 40239842 | 42251835 | -0.6 % |
| grimworld_ephemeral::test_lifecycle::test_refused_closed | 38394635 | 38150655 | 40058188 | -0.6 % |
| grimworld_ephemeral::test_lifecycle::test_refused_gate | 58693276 | 58571286 | 61499851 | -0.2 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sealed | 29235369 | 29113379 | 30569048 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sequence | 33190946 | 33068956 | 34722404 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_set_controller | 33102432 | 32980442 | 34629465 | -0.4 % |
| grimworld_ephemeral::test_lifecycle::test_travel_back | 31656599 | 31534609 | 33111340 | -0.4 % |
| grimworld_logic::snapshot::tests::test_snapshot_words | — | 461100 | 484155 | new |
| grimworld_logic::snapshot::tests::test_words_are_the_flattening | — | 3849958 | 4042456 | new |
| grimworld_logic::snapshot::tests::test_worn_held | — | 684760 | 718998 | new |
| grimworld_logic::snapshot::tests::test_worn_insignia_piece_refused | — | 526300 | 552615 | new |
| grimworld_logic::snapshot::tests::test_worn_slot_type_refused | — | 528640 | 555072 | new |
| grimworld_logic::snapshot::tests::test_worn_unknown_modifier_refused | — | 348690 | 366125 | new |
| grimworld_logic::snapshot::tests::test_worn_value_above_refused | — | 522230 | 548342 | new |
| grimworld_logic::snapshot::tests::test_worn_value_below_refused | — | 521760 | 547848 | new |
| grimworld_logic::test_flatten::test_cost_library_call_empty | — | 1975853 | 2074646 | new |
| grimworld_logic::test_flatten::test_cost_library_call_widest | — | 4419698 | 4640683 | new |
| grimworld_logic::test_flatten::test_library_words_are_the_flattening | — | 7202536 | 7562663 | new |
| grimworld_persistent::models::snapshot::tests::test_missing_refused | — | 15520 | 16296 | new |
| grimworld_persistent::models::snapshot::tests::test_other_level_refused | — | 121890 | 127985 | new |
| grimworld_persistent::models::snapshot::tests::test_other_version_refused | — | 67180 | 70539 | new |
| grimworld_persistent::models::snapshot::tests::test_seal_round_trip | — | 290220 | 304731 | new |
| grimworld_persistent::models::snapshot::tests::test_stale_mark_bits | — | 13720 | 14406 | new |
| grimworld_persistent::models::snapshot::tests::test_stale_mark_refused | — | 19700 | 20685 | new |
| grimworld_persistent::systems::hub::layout_tests::test_hub_storage_addresses | 257780 | 271850 | 285443 | raised: CBT-02e: the layout checks the snapshots' and flatten's addresses; +5.5 % |
| grimworld_persistent::test_accounts::test_create_adventurer | 23818630 | 23866410 | 25009562 | +0.2 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9188810 | 9236590 | 9648251 | +0.5 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9190170 | 9237950 | 9649679 | +0.5 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19369560 | 19417340 | 20338038 | +0.2 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7549740 | 7597520 | 7927227 | +0.6 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40812560 | 40860340 | 42853188 | +0.1 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 13910710 | 13958490 | 14606246 | +0.3 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 12915440 | 12963220 | 13561212 | +0.4 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 27994670 | 28042450 | 29394404 | +0.2 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24227560 | 24275340 | 25438938 | +0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 12996260 | 13044040 | 13646073 | +0.4 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13319210 | 13366990 | 13985171 | +0.4 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13295720 | 13343500 | 13960506 | +0.4 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21157830 | 21205610 | 22215722 | +0.2 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49428420 | 49476200 | 51899841 | +0.1 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23823100 | 23870880 | 25014255 | +0.2 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40866160 | 40913940 | 42909468 | +0.1 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 16954200 | 17001980 | 17801910 | +0.3 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13313840 | 13361620 | 13979532 | +0.4 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 12921170 | 12968950 | 13567229 | +0.4 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18604170 | 18651950 | 19534379 | +0.3 % |
| grimworld_persistent::test_accounts::test_register | 14876920 | 14924700 | 15620766 | +0.3 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9033370 | 9081150 | 9485039 | +0.5 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27388590 | 27436370 | 28758020 | +0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21111810 | 21159590 | 22167401 | +0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21418100 | 21513660 | 22489005 | +0.4 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42711400 | 42759180 | 44846970 | +0.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14688070 | 14735850 | 15422474 | +0.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12721870 | 12769650 | 13357964 | +0.4 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13047740 | 13095520 | 13700127 | +0.4 % |
| grimworld_persistent::test_admin::test_hub_set_admin_hands_over | 4895740 | 5367750 | 5636138 | raised: CBT-02e: set_contracts takes FlattenLibrary's class hash (D-168); +9.6 % |
| grimworld_persistent::test_admin::test_hub_set_admin_refused | 4359910 | 4369130 | 4577906 | +0.2 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_by_admin | 4245460 | 4704660 | 4939893 | raised: CBT-02e: set_contracts takes FlattenLibrary's class hash (D-168); +10.8 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_refused_to_others | 4106290 | 4128320 | 4311605 | +0.5 % |
| grimworld_persistent::test_build::test_attributes_indices | 77727530 | 84824259 | 89065472 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +9.1 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 80707330 | 92582404 | 97211525 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +14.7 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 73480570 | 78336906 | 82253752 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +6.6 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 71671480 | 74887483 | 75255054 | +4.5 % |
| grimworld_persistent::test_build::test_bar_elite | 75360040 | 79151203 | 83108764 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +5.0 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 74957390 | 79271486 | 83235061 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +5.8 % |
| grimworld_persistent::test_build::test_bar_profession | 72450570 | 75629773 | 76073099 | +4.4 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 73929480 | 78193996 | 82103696 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +5.8 % |
| grimworld_persistent::test_build::test_belt_items | 73492240 | 76862603 | 77166852 | +4.6 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 76545984 | 82619400 | 86750370 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +7.9 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 75248047 | 82279658 | 86393641 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +9.3 % |
| grimworld_persistent::test_build::test_set_build_empty | 72689441 | 78195730 | 82105517 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +7.6 % |
| grimworld_persistent::test_build::test_set_build_floor_refused | — | 95512944 | 100288592 | new |
| grimworld_persistent::test_build::test_set_build_insignia_piece_refused | — | 95118231 | 99874143 | new |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 74164190 | 77991123 | 81890680 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +5.2 % |
| grimworld_persistent::test_build::test_set_build_modifier_slot_and_value_refused | — | 98895126 | 103839883 | new |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 71720330 | 75337023 | 79103875 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +5.0 % |
| grimworld_persistent::test_build::test_set_build_parts | 74636131 | 81979636 | 86078618 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +9.8 % |
| grimworld_persistent::test_build::test_set_build_sixth_rune_refused | — | 99709275 | 104694739 | new |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_health | — | 101180541 | 106239569 | new |
| grimworld_persistent::test_build::test_set_build_unknown_modifier_refused | — | 90908869 | 95454313 | new |
| grimworld_persistent::test_build::test_set_build_worst_case | 71917401 | 114322624 | 120038756 | raised: CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168); +59.0 % |
| grimworld_persistent::test_fate::test_fate_at_the_configured_address | 4706656 | 4754436 | 4941989 | +1.0 % |
| grimworld_persistent::test_lifecycle::test_enter | 36232800 | 39260690 | 41223725 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +8.4 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 43567510 | 46336413 | 48653234 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +6.4 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 31566920 | 33317590 | 34983470 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +5.5 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 43961610 | 45462580 | 46159691 | +3.4 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_missing_snapshot | — | 35002523 | 36752650 | new |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_stale_snapshot | — | 43095162 | 45249921 | new |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 34738940 | 36915850 | 38761643 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +6.3 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 35641351 | 37803651 | 39693834 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +6.1 % |
| grimworld_persistent::test_lifecycle::test_report_open | 35130182 | 36880852 | 36886692 | +5.0 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 35663424 | 37414094 | 37446596 | +4.9 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 35322669 | 37484969 | 39359218 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +6.1 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 36595302 | 38429152 | 40350610 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +5.0 % |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 24691850 | 26770970 | 28109519 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +8.4 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 28299060 | 28760650 | 29714013 | +1.6 % |
| grimworld_persistent::test_lifecycle::test_travel | 33230657 | 34981327 | 36730394 | raised: CBT-02e: FlattenLibrary declared and a snapshot stored before enter (D-168); +5.3 % |

The raised budgets all have a reason written above them. The persistent tests that deploy `Hub` also pay the larger `Hub` class, `FlattenLibrary`'s declaration and, in the lifecycle tests, a stored snapshot. The ephemeral `create` tests are cheaper, because `create` no longer packs the snapshot.

## Acceptance criteria

- **AC-1: done.** The flattening runs only in `FlattenLibrary`, called by `set_build` (`hub.cairo`: the only `IFlattenLibraryLibraryDispatcher` use). `enter` copies the stored words: `test_enter_after_set_build` checks that what `create` received equals the words read from `Hub.snapshots`; `test_enter_reserves_the_belt` does the same for the fixture.
  - The stored words equal the flattening's, computed directly from the same records, for the widest equipment of design/20 §1.2 (`test_set_build_worst_case`, 15 modifiers, level 20) and for design/20 §6's max-health build as items can hold it (`test_set_build_stores_the_extremal_max_health`, 920). `test_library_words_are_the_flattening` shows the library call returns `SnapshotBuildTrait::words`, and `test_words_are_the_flattening` shows `words` is `build`'s snapshot, packed.
  - The other extremal builds of §6 (with set bonuses, 37 armor passives) cannot be held by items yet; they stay tested on `build` itself in `snapshot.cairo` (CBT-02c).
- **AC-2: done.** `Hub` 44.64 %; `FlattenLibrary` 26.98 % in `class_sizes.py`, once.
- **AC-3: done.** `set_build`'s worst case: 8,097,073, budget 8,501,927 (`WORST_CASE_CALL`, asserted in `test_set_build_worst_case`). `enter` with the belt's worst case: 4,473,259 net on the node, under 5.25 M.
- **AC-4: done** (the table above).
  - `enter` refuses `snapshot: missing` (`test_enter_refuses_a_missing_snapshot`) and `snapshot: stale` for a changed record, a level up and the mark, each cleared by `set_build` (`test_enter_refuses_a_stale_snapshot`); the unit tests of `models::snapshot` cover each check.
  - The mark is tested as a written word. No present implemented entrypoint writes it, because the ones that must (`personalise`, `lift_modifier`, `set_modifier`, …) are still `not implemented`.
- **AC-5: done.** 3 words; first write +1,406,000 (468,667 a word), overwrite inside 3,022,059. ENG-01 §3.3 (the table and the layout), §9.3 (`set_build`'s row, 3 / 3 then 0 / 6, and the paragraph), §10 (the measured table) and the cost budget's hub row are updated.
- **AC-6: done.**
  - No event changed (`events.cairo` untouched; D-149).
  - D-143: the stored snapshot is a model with its `Assert` impl and errors; entrypoints only in `hub.cairo`; the library's rules scoped in traits.
  - Unit tests in their modules: `snapshot.cairo`, `models/snapshot.cairo`. Only the library call's tests are in `tests/`, because they need the declared class.
  - CI green; `gas_budgets.py --check` green.

## Deviations from the brief

1. **`IInstanceEntry.create`'s `snapshot` parameter changes type** from `Snapshot` to `SnapshotWords` (`interface.cairo`), which is not an addition.
   - **Why**: with the flattening out, `Hub` was still at **51.13 %**, because `enter` unpacked the stored words into a `Snapshot` (4,684 CASM felts) only for `Instances` to repack them. The allowlist gives `instances.cairo` "only where `create` receives the snapshot", so I read that as the intended lever and passed the words as stored.
   - **Effect**: `Hub` 44.64 %, `Instances` 29.00 %, `enter` −0.8 M.
   - **Security**: `Instances` no longer re-checks the snapshot fields (`pack_*`'s `assert_valid`) at `create`. The words were packed, and so checked, by the library at `set_build`, and only `Hub` can call `create`.
2. **`contracts/persistent/Scarb.toml`** gains `build-external-contracts = ["grimworld_logic::systems::flatten::FlattenLibrary"]`. The package's tests cannot declare the library otherwise. It is a package manifest outside the allowlist; CBT-02 edited `contracts/logic/Scarb.toml` for `TickLibrary` in the same way.
3. **`Hub`'s constructor is unchanged**: the class hash is set by `set_contracts` only, as the brief says. A deployment must call `set_contracts` before any `set_build` (the probe does), or `set_build` makes a library call to class hash 0 and reverts.
4. **`set_build` always makes one `bundle` call**, even for an empty build, to get the content version. An empty build pays one call more than before.
5. **The belt's counts are not stored** in the snapshot: `enter` takes them from the belt it debits, as before, and passes them in `SnapshotWords`. The belt's items are in the stored kit. Only `set_build` writes the belt, so the two agree.
6. The persistent `test_lifecycle` tests that are not about the build store a snapshot with `store` (`put_snapshot`, as the file already did for the belt). The real `set_build → enter` path is in `test_enter_after_set_build` and the two refusal tests, and in the node probe for every adventurer.

## Escalations

1. **ENG-01 §6** ("At entry … passes `Snapshot { … }`") and **§4.2** now describe `create`'s argument wrongly: it is `SnapshotWords`, the three words as `Hub` stored them. Both are outside the allowlist; a one-line fix each.
2. **The entrypoints that must refuse a worn entity or mark stale** (`sell`, `recycle`, `stow`, `Market.escrow` and `exchange`, `personalise`, `lift_modifier`, `set_modifier`) are not implemented. Their briefs should carry the table's line. The worst case to avoid is an item that leaves the pack while `equipped` still names it: `enter` would copy its modifiers.
3. **Changing `FlattenLibrary`'s class by `set_contracts` does not stale the stored snapshots.** This is a design question for the project manager. Options:
   - (a) a rules version in the kit word beside the content version, set by `set_contracts` (a storage read at `enter`, about one slot);
   - (b) the administrator also rewrites a record, which moves the content version;
   - (c) accept that snapshots computed by the old rules finish their life.
4. **A content update stales every stored snapshot**, since any changed record moves the version. After each update, every player's next `enter` is refused until a `set_build`. The client sends it first (D-168 2), but it costs one `set_build` per adventurer per content update. A per-kind version (only `MODIFIER`, `BASE`, `ARMOR_SET`) would narrow it; that would be a change to the registry, the project manager's call.

## Open questions

- D-168 listed "a skill learnt" among the inputs. Today the flattening reads only the bar, which only `set_build` writes, so `buy_skill` changes no input (table). If a later rule makes learnt skills an input, `buy_skill` marks stale.
- `set_build`'s node figure for the worst case is an estimate (E) until an item creator and `buy_skill` exist; CBT-08a's report had the same limit.

## Fix loop 1

Audits at `edfc33d`: `[GPT-6-Astra]` PASS WITH FINDINGS (its note is escalation 3, sent to the project manager; nothing changed for it); `[GPT-6-Sol]` FAIL, one major and three minors. origin/main had not moved (`git log HEAD..origin/main` empty): nothing to merge. Commits `7283547`, `ecf95c7`, `0bbcb5a`; head `0bbcb5a`. CI green on every check (`indexer-node` skipping).

### Quality 1 (major): design/20 §6 test 2's extremal builds, each checked for equal words

Each test compares the words with the direct flattening's (`SnapshotBuildTrait::words` on the same records). The library tests (`contracts/logic/tests/test_flatten.cairo`) check that the library's words equal the direct flattening's. The `set_build` tests (`contracts/persistent/tests/test_build.cairo`) check that the stored words equal the direct flattening's, computed from the stored build and the registry's records. The extremum reached in each case:

| Extremum (design/20) | Through the library | Through `set_build` | Why not the design's value, or not through `set_build` |
|---|---|---|---|
| Max health **1,020** | **920** `test_extremal_max_health_through_the_library` | **920** `test_set_build_stores_the_extremal_max_health` (CBT-02e) | 1,020 includes two +50 **set bonuses**. No item holds a set bonus: armor sets are not laid out in the loadout (`set_bonuses` 0 in `BuildTrait::loadout`; the counting of a set's pieces is not written) and `Worn` carries modifiers only. 920 is the highest the item model holds: level 20, five +30 held slots, insignias 15/10/5/5/5 (DS-23), five +50 runes of distinct ids |
| Max energy **130** | **120** `test_extremal_max_energy_through_the_library` (Arcanist, 12 points + a +3 rune: Wellspring 15, light armor, five +5 held slots) | **75** `test_set_build_stores_the_extremal_max_energy` (the same items; the rune stored but no rank) | The 10 missing from 130 are the two +5 set bonuses (as above). Through `set_build`, Wellspring's 45 is also missing: `BuildTrait::loadout` passes **no attribute point**, because `Build.attributes` holds build-local indices and the global attribute ids that runes name are not numbered (D-157 A). So the rank is 0 |
| Weapon damage **32** | **32** `test_extremal_weapon_damage_through_the_library` (personalised maul, base 27) | not representable | `BASE` lays out only the slot and the hands (D-158): the loadout's weapon damage is 0, so personalisation has nothing to raise |
| Ranks **15** | **15**, all eight bar ranks 15 `test_extremal_ranks_through_the_library` | not representable | no attribute point in the loadout (D-157 A, as above) |

### Quality 2 (minor): the stored snapshot through the store layer

- **Persistent side**: `contracts/persistent/src/store.cairo` gains `StoreTrait::get_snapshot` / `set_snapshot`, typed on the `StoredSnapshot` model (`StoragePath<Mutable<StoredSnapshot>>`, the derived `starknet::Store`, no offsets). The model gains `StoredSnapshotTrait::new` (the words sealed with the version) and `words` (unsealed into `SnapshotWords`). `Hub` no longer names a word offset of the snapshot; the offsets `STATS_WORD`/`BAR_WORD`/`KIT_WORD` of `models/snapshot.cairo` are removed.
- **Ephemeral side**: `contracts/ephemeral/src/store.cairo` gains `StoreTrait::set_snapshot(member, @SnapshotWords)`, which writes the three words as stored at `Member`'s `stats`, `bar` and `kit` slots; `create` calls it.
- **Class sizes**: `Hub` **36,629 CASM felts, 44.71 %** (was 36,572, 44.64 %: +57); `Instances` 23,795, 29.05 % (+35).
- **Gas (snforge)**: `set_build`'s worst-case call 8,098,273 (+1,200; budget 8,501,927 unchanged). The tests' totals rise by 1,000 to 72,720 each (rows below), all within their budgets. The node's receipts (`enter`, `set_build`) are unchanged to the unit.

### Quality 3 (minor): the overwrite measured on the node

`contracts/tools/lifecycle_probe.py`, adventurer 2, after the belt's round trip: three `set_build` with the same reads and computation (two potions on pages 0 and 1). Net of 189,141:

| Case | Keys changed | Net |
|---|---|---:|
| the belt's counts changed | the belt word | 3,302,059 |
| the belt's slots swapped | the belt word **and the snapshot's kit word** (it names the belt's items) | 3,342,059 |
| the same again | none | 3,182,059 |

**A snapshot word's overwrite: 40,000** (3,342,059 − 3,302,059), measured on the kit word. About 120,000 the three (E: the stats and bar words priced as the kit word, as §2.2's per-key figures allow). The first write's 1,406,000 is over the three words rewritten unchanged, so the premium of a new word over an overwritten one is about 428,667. The "again" case of adventurer 1 was mislabelled "overwritten": its words are rewritten unchanged, with no state change; it is relabelled. `set_build`'s worst-case transaction, overwriting, is re-derived as about **9.29 M (E)** (was 9.17 M: the words now counted as changing). ENG-01 §3.3 and §10 and the cost budget's hub row give the figure.

### Quality 4, and escalation 1

- Quality 4: the two deviations were accepted by the orchestrator; nothing changed.
- Escalation 1, now in the allowlist: ENG-01 §4.2 names `create(adventurer_id, controller, gate, snapshot: SnapshotWords, tasks)`, and §6 describes `SnapshotWords`: the words packed at `set_build`, stored by `create` as they are.

### Commands run

```
$ git fetch origin; git log HEAD..origin/main                  → empty
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build; python3 contracts/tools/class_sizes.py
  Instances 23,795 29.05 % · FlattenLibrary 22,098 26.98 % · Hub 36,629 44.71 %   → exit 0
$ cd contracts/logic && snforge test test_flatten              → 13 passed (4 new, all pass)
$ cd contracts/persistent && snforge test test_set_build_stores → 2 passed
$ snforge test test_set_build_worst_case                       → gas set_build, worst case: 8098273
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt
  set_build counts changed 3,302,059 · slots swapped 3,342,059 · same again 3,182,059 (net);
  every other receipt identical to the first run
$ scarb --manifest-path contracts/Scarb.toml fmt --workspace
$ python3 scripts/gas_budgets.py                               → the 5 new tests' budgets set at ceil(1.05 × measured); files written
$ python3 scripts/gas_budgets.py --check                       → gas check: 680 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ gh pr checks 212 --watch                                     → all pass (indexer-node skipping)
```

### Rows that changed (docs/BUDGETS.md, `edfc33d` → `0bbcb5a`; measured, budget)

| Test | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| logic `test_flatten::test_extremal_max_health_through_the_library` | — | 6,420,146 | 6,741,154 | new |
| logic `test_flatten::test_extremal_max_energy_through_the_library` | — | 3,303,036 | 3,468,188 | new |
| logic `test_flatten::test_extremal_weapon_damage_through_the_library` | — | 1,466,506 | 1,539,832 | new |
| logic `test_flatten::test_extremal_ranks_through_the_library` | — | 2,042,226 | 2,144,338 | new |
| persistent `test_build::test_set_build_stores_the_extremal_max_energy` | — | 85,531,037 | 89,807,589 | new |
| persistent `test_build::test_set_build_worst_case` | 114,322,624 | 114,395,344 | 120,038,756 | the store (+72,720), budget unchanged |
| persistent `test_build::*`, 20 other rows | | +2,400 to +18,070 | unchanged | the store |
| persistent `test_lifecycle::*`, 13 rows | | +1,000 to +41,080 | unchanged | the store |
| ephemeral `test_lifecycle::*`, 16 rows | | +2,000 to +12,050 | unchanged | `create` through the store |

No budget was raised in this fix loop.
