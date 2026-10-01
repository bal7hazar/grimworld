# [Opus 5.5] CBT-02f — The stored snapshot's epoch: rules and the flattening's inputs

## Summary
A stored snapshot is now stale **exactly when** the rules that flattened it, or a record the flattening reads, has changed since `set_build` (D-169, both parts).
- **The inputs version** (`Registry`): a second `u32` counter beside the content version. `set_record` raises it only for a changed **existing** record of an input kind (`SKILL`, `ITEM`, `MODIFIER`). `bundle` returns `(content version, inputs version, records)`. Both counters share **one slot**, so `bundle` still makes one read and `set_record` one write.
- **The rules epoch** (`Hub.rules_epoch`, 0–511): `set_contracts` raises it when the `FlattenLibrary` class changes, not when the same class is set again. It wraps 511 → 0.
- **The kit word** carries both as the **flattening epoch**: the inputs version at bits 208–239, the stale mark at 240, the rules epoch at 241–249, `LIVE` at 250. `enter` checks the inputs version, the mark and the rules epoch in the one division it already made, adding a single storage read (`rules_epoch`). A new gate, quest, shop, location or caste no longer costs any player a `set_build`.
- `enter` with the belt's worst case: **4,513,259** net on the node (D-158 limit: 5.25 M). `Hub` is at **45.30 %** of its class limit and `Registry` at 30.23 %.

Pull request: https://github.com/bal7hazar/grimworld/pull/219. Every CI check passes (indexer-node skips). Not merged.

The model I run as is Opus 5.5, as the brief names.

## Files changed
- `contracts/persistent/src/models/versions.cairo` (new): the `Versions` model (content and inputs versions, one slot), its packing, `raised(input)`, its unit tests.
- `contracts/persistent/src/models.cairo`: declares `versions`.
- `contracts/persistent/src/models/snapshot.cairo`: the flattening epoch (`epoch`, `next_rules`, `RULES_EPOCHS`), sealing and `assert_fresh` by epoch, unit tests for the layout, the wrap, another rules epoch, and the mark at any epoch.
- `contracts/persistent/src/systems/registry.cairo`: `Inputs::includes` (the input kinds, justified in its doc), the `versions` slot, `bundle`'s new return, `raise_versions(input)`, layout and cost tests.
- `contracts/persistent/src/systems/hub.cairo`: `rules_epoch` storage; `set_contracts` raises it on a class change; `set_build` and `enter` seal and compare the flattening epoch; layout test.
- `contracts/logic/src/interface.cairo`: `IRegistryRead::bundle -> (u32, u32, Span<felt252>)` (D-169).
- `contracts/persistent/tests/test_lifecycle.cairo`: the staleness tests (each input kind, other records, a new rules class, the wrap); snapshots sealed with the epoch.
- `contracts/persistent/tests/test_registry.cairo`: `test_inputs_version_per_kind`; `bundle`'s callers; the stored `versions` slot.
- `contracts/persistent/tests/test_build.cairo`, `test_seed.cairo`, `test_read_cost.cairo`, `contracts/ephemeral/tests/test_lifecycle.cairo`: `bundle`'s callers.
- `contracts/persistent/tests/test_accounts.cairo`, `test_admin.cairo`, `test_fate.cairo`, `test_words.cairo`: budgets only.
- `contracts/tools/budget_table.py`, `budget-keys-output.txt`: the registry slot `R.versions`.
- `contracts/tools/lifecycle-probe-output.txt`: the node probe re-run.
- `docs/architecture/ENG-01-interfaces.md` §3.3, §3.5, §9.3, §10: the rules epoch, the inputs version, the kit layout, the write sets, the figures.
- `contracts/persistent/GAS.md`, `docs/BUDGETS.md`: generated.

## Commands run
```
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build      → Finished
$ cd contracts/persistent && snforge test                                 → 191 passed (after the budgets were set)
$ python3 scripts/gas_budgets.py --check                                  → gas check: 757 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
  (runs the three packages: logic, persistent, ephemeral, all passing)
$ python3 contracts/tools/class_sizes.py
  Registry 24,763 CASM felts 30.23 % (30.04 % before) · Hub 37,108 45.30 % (44.64 %) · FlattenLibrary 26.98 % · Instances 29.05 % · TickLibrary 24.32 %
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt   (net = gross − 189,141, as CBT-02e)
  set_build, empty, first (3 words new)     4,657,200  net 4,468,059   (CBT-02e 4,428,059)
  set_build, empty, again                   3,251,200  net 3,062,059   (3,022,059)
  enter, first entry (cold)                 9,488,400  net 9,299,259   (9,259,259)
  enter, later entry, no belt               3,942,400  net 3,753,259   (3,713,259)
  set_build, 4 potions on 4 pages           3,771,200  net 3,582,059   (3,542,059)
  enter, the belt's worst case (4 pages)    4,702,400  net 4,513,259   (4,473,259)
$ snforge test test_set_build_worst_case   → gas set_build, worst case: 8124823 (CBT-02e 8097073; budget WORST_CASE_CALL 8501927)
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --workspace   → applied (one commit, then the raise reasons shortened)
$ python3 scripts/gas_budgets.py --report  → the table below
$ gh pr checks 219 --watch                 → every check pass (indexer-node skipping); the first run failed on `scarb fmt --check` (a reason line too long), fixed
```

## The input kinds and why
They are the kinds of `Hub.set_build`'s single `bundle` call, the only registry read the snapshot depends on:
- **`SKILL`**: each bar skill's profession and elite flag decide whether the build is accepted (`BuildAssert::assert_skill`, `assert_one_elite`). If the profession is rewritten, a stored bar could become illegal.
- **`ITEM`**: each belt item must be a potion (`BeltAssert::assert_potion`). If a potion is turned into another class, a stored belt could become illegal.
- **`MODIFIER`**: each worn modifier's slot type, benefit, cost, source and piece are flattened into the words (`WornTrait::held`). This is the nerf case D-169 names.

Not inputs:
- `BASE`: its slot and hands are copied into the item at creation (D-158), so `set_build` reads no `BASE`, and `Build::loadout` lays out no weapon statistic.
- `ARMOR_SET`: no set bonus is laid out (`set_bonuses: 0`).
- Every other kind (`REGION`, `LOCATION`, `OUTLINE`, `GATE`, `QUOTAS`, `SPAWN_TABLE`, `PACK`, `CASTE`, `LOOT_TABLE`, `BOOK`, `TASK`, `QUEST`, `RANK`, `RIFT_GRADE`, `COLLECTOR`, `SHOP`, `LANDMARK`, `CONTRACT_POOL`, `SET_PIECE`, `COUNTER`): `set_build` and the flattening never read them.
- Level and profession: the level comes from the adventurer (checked separately), and the profession's values are code constants.

The list lives in one place, `Inputs::includes` in `systems/registry.cairo`, with this justification in its doc. `test_flattening_inputs` only guards the current list (it compares `includes` with the same three kinds written out). *Corrected in fix loop 1*: the tie to `set_build` is `test_set_build_requests_the_input_kinds`, which records the kinds `set_build`'s `bundle` call actually asks for and asserts they equal the kinds `includes` accepts.

**A new id of an input kind raises nothing.** No stored snapshot can name an id written after it, because:
1. `set_build` refuses a missing skill (`NO_SKILL`), a missing potion (`NOT_A_POTION`) or a missing modifier (`NO_MODIFIER`);
2. ids are append-only and never reused;
3. part 0 always carries `LIVE`, so a record never returns to "missing".

This means new items, skills and modifiers that come with a content update cost no player a `set_build`. An identical rewrite raises nothing, as for the content version.

## The counter
`Registry.versions: Versions { content: u32, inputs: u32 }`, one slot: content at bits 0–31, inputs at 32–63, no `LIVE`, 0 at deployment. Each version refuses to overflow past `u32`, as the content version alone did.
- `set_record` writes the slot through `raise_versions(input)`:
  - a new id raises the content version only;
  - a changed existing record raises the content version, and the inputs version too when `Inputs::includes(kind)`.
- `bundle` reads the slot once and returns `(content, inputs, records)`. `content_version()` returns the content field.

I packed both into one slot rather than add a second slot. `bundle` is the call every `play` invocation makes (E-5), so a second slot would cost about 21,000 more on every invocation, for every player. Packed, the extra cost is the unpacking only (+3,240 at `bundle`'s read).

## The epoch and its wrap
`Hub.rules_epoch: u16`, 0 at deployment. `set_contracts` compares the new `flatten` with the stored one:
- if they differ, it writes the class and `rules_epoch = (rules_epoch + 1) % 512`;
- if they are the same, it writes neither.

The first `set_contracts` after deployment therefore takes it to 1. Setting a class back to an earlier one (A → B → A) is two changes, and stale.

**Wrap:** 9 bits, so 511 → 0. A snapshot left without `set_build` through **exactly 512** class changes, with no input change in between, would read fresh again. Anything short of that is refused. `test_rules_epoch_wraps` (unit) and `test_enter_after_the_rules_epoch_wraps` (511 → 0, stale under 0, cleared by `set_build`) test it.

## The kit's layout
| Bits of the kit word | What |
|---|---|
| 0–202 | the packed kit (`MemberKit`) |
| 208–239 | the inputs version (`u32`) |
| 240 | the stale mark |
| 241–249 | the rules epoch (9 bits) |
| 250 | `LIVE` |

These are the bits the brief proposed (241–249).
- **Flattening epoch** = `inputs + rules × 2^33`, sealed at bit 208.
- **The check**: after `split` removes `LIVE`, the kit word's high limb divided by `2^80` must equal the flattening epoch. One comparison covers the inputs version, the mark (bit 32 of the state, never set in an epoch) and the rules epoch.
- `test_epoch_bits` shows that the widest epoch plus the mark fill bits 208–249 exactly (2^250 − 2^208).

## The staleness table (CBT-02e's, updated)
| Entrypoint | Present / planned | Changes an input? | What it does | Tested |
|---|---|---|---|---|
| `set_build` | present | every input | **recomputes** and seals with the current flattening epoch, clearing any mark | every stale test below ends with it |
| `create_adventurer` | present | creates the adventurer | no snapshot: **`snapshot: missing`** until the first `set_build` | `test_enter_refuses_a_missing_snapshot` |
| `Registry.set_record`, a rewritten `SKILL`, `ITEM` or `MODIFIER` | present | yes | the **inputs version** moves: every stored snapshot is stale until its `set_build` | `test_enter_refuses_after_an_input_rewritten` (each kind), `test_enter_refuses_a_stale_snapshot`, `test_inputs_version_per_kind` |
| `Registry.set_record`, a **new** id of those kinds, any record of another kind (new or rewritten), an identical rewrite | present | no | **nothing**: the content version moves, the inputs version does not | `test_enter_after_other_records_changed` (a new gate, a rewritten gate, a quest, a new and a rewritten location, a new skill, item and modifier), `test_inputs_version_per_kind` |
| `Hub.set_contracts` with another `FlattenLibrary` class | present | the rules | the **rules epoch** moves: every stored snapshot is stale | `test_enter_refuses_after_a_new_rules_class`, `test_enter_after_the_rules_epoch_wraps` |
| `Hub.set_contracts` with the same class | present | no | nothing (no write of `flatten` or the epoch) | `test_enter_refuses_after_a_new_rules_class` (last part) |
| `report` | present | experience only | nothing | — |
| GLD-01's level-up | planned | the level | nothing to write: `enter` compares levels | `test_enter_refuses_a_stale_snapshot`, `test_other_level_refused` |
| `personalise`, `lift_modifier`, `set_modifier` | stubs | a worn item's flags or `ItemMods` | on a worn entity: **mark stale** (their lots) | `test_stale_mark_refused`, `test_stale_mark_refused_at_any_epoch` |
| `identify` | stub | cannot reach a worn item | if its lot allows it: mark stale | — |
| `sell`, `recycle`, `stow`, `Market.escrow` / `exchange` | stubs | `equipped` would name an entity gone | refuse a worn entity, or clear and mark (their lots) | — |
| `buy_skill`, `claim_quest`, RWD-06's equipment | stubs / planned | no (as CBT-02e) | nothing | — |
| `delete_adventurer`, `travel`, `register`, `set_account_owner`, `enter` | present | no | nothing | — |

## The figures against D-158 and 50 %
| | Target | Measured | Result |
|---|---:|---:|---|
| `enter`, the belt's worst case, node net | 5,250,000 (D-158) | **4,513,259** (+40,000: one read of `rules_epoch`) | within, −14.0 % |
| `enter`, later entry without a belt, node net | 4,100,000 | 3,753,259 (+40,000) | within |
| `set_build`'s worst-case call, snforge | 8,501,927 | 8,124,823 (+27,750) | within |
| `set_record`, the administrator's added cost | — | +1,420 for a rewritten input (both versions in the same write, `test_version_cost_raise_input` 487,780 against `test_version_cost_raise` 486,360); every raise +3,440 for the packing (472,640 against 469,200 before, net of the baseline); a later raise 71,760 (67,200) | the administrator's |
| `bundle`'s read of the versions | — | 24,170 (20,930 before: +3,240 unpacking, no second read) | every `play` invocation pays it |
| `Hub`'s class | < 50 % | **45.30 %** (37,108 CASM felts; 44.64 % before) | within |
| `Registry`'s class | < 50 % | **30.23 %** (24,763; 30.04 % before) | within |

`set_contracts` writes one more key (`H.rules_epoch`) when it changes the class: a new slot the first time, measured inside `test_hub_set_contracts_by_admin` (+489,370 over `main`'s measure).

## Cost
Every row that moved, from `python3 scripts/gas_budgets.py --report` (origin/main fetched). Before is `main`'s measure. Nine budgets rise, each with a `// gas: raised, CBT-02f: …` reason, for the orchestrator to agree or refuse. Every other row keeps `main`'s budget: its new measure still fits under it. A "raised: …" note naming an earlier lot (CBT-02e, D-166, ENG-06) is that earlier lot's agreed raise, and its budget is unchanged here. The ±0.1–1 % shifts in tests that deploy `Hub` or `Registry` come from the larger classes, plus D-154's build variance.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_persistent::models::snapshot::tests::test_epoch_bits | — | 13720 | 14406 | new |
| grimworld_persistent::models::snapshot::tests::test_other_rules_refused | — | 71650 | 75233 | new |
| grimworld_persistent::models::snapshot::tests::test_rules_epoch_wraps | — | 13720 | 14406 | new |
| grimworld_persistent::models::snapshot::tests::test_stale_mark_refused_at_any_epoch | — | 19800 | 20790 | new |
| grimworld_persistent::models::versions::tests::test_versions_inputs_overflow | — | 15320 | 16086 | new |
| grimworld_persistent::models::versions::tests::test_versions_raised | — | 13720 | 14406 | new |
| grimworld_persistent::models::versions::tests::test_versions_round_trip | — | 13720 | 14406 | new |
| grimworld_persistent::systems::hub::layout_tests::test_hub_storage_addresses | 271850 | 272150 | 285443 | +0.1 % |
| grimworld_persistent::systems::registry::inputs_tests::test_flattening_inputs | — | 107000 | 112350 | new |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_raise | 482920 | 486360 | 507066 | +0.7 % |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_raise_again | 490140 | 494700 | 514647 | +0.9 % |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_raise_input | — | 487780 | 512169 | new |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_read | 34650 | 37890 | 39785 | raised: CBT-02f: the slot holds the content and inputs versions, unpacked at the read; +9.4 % |
| grimworld_persistent::test_accounts::test_create_adventurer | 23866410 | 23845550 | 25009562 | -0.1 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9236590 | 9215730 | 9648251 | -0.2 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9237950 | 9217090 | 9649679 | -0.2 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19417340 | 19396480 | 20338038 | -0.1 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7597520 | 7576660 | 7927227 | -0.3 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40860340 | 40839480 | 42853188 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 13958490 | 13937630 | 14606246 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 12963220 | 12942360 | 13561212 | -0.2 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 28042450 | 28021590 | 29394404 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24275340 | 24254480 | 25438938 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 13044040 | 13023180 | 13646073 | -0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13366990 | 13346130 | 13985171 | -0.2 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13343500 | 13322640 | 13960506 | -0.2 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21205610 | 21184750 | 22215722 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49476200 | 49455340 | 51899841 | -0.0 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23870880 | 23850020 | 25014255 | -0.1 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40913940 | 40893080 | 42909468 | -0.1 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 17001980 | 16981120 | 17801910 | -0.1 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13361620 | 13340760 | 13979532 | -0.2 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 12968950 | 12948090 | 13567229 | -0.2 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18651950 | 18631090 | 19534379 | -0.1 % |
| grimworld_persistent::test_accounts::test_register | 14924700 | 14903840 | 15620766 | -0.1 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9081150 | 9060290 | 9485039 | -0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27436370 | 27415510 | 28758020 | -0.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21159590 | 21138730 | 22167401 | -0.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21513660 | 21467470 | 22489005 | -0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42759180 | 42738320 | 44846970 | -0.0 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14735850 | 14714990 | 15422474 | -0.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12769650 | 12748790 | 13357964 | -0.2 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13095520 | 13074660 | 13700127 | -0.2 % |
| grimworld_persistent::test_admin::test_hub_set_admin_hands_over | 5367750 | 5893380 | 6188049 | raised: CBT-02f: set_contracts raises the rules epoch, a new slot (D-169); +9.8 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_by_admin | 4704660 | 5194030 | 5453732 | raised: CBT-02f: set_contracts raises the rules epoch, a new slot (D-169); +10.4 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_refused_to_others | 4128320 | 4164580 | 4311605 | +0.9 % |
| grimworld_persistent::test_build::test_attributes_indices | 84832699 | 85624249 | 89065472 | +0.9 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 92600474 | 93574334 | 97211525 | +1.1 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 78345356 | 79126876 | 82253752 | +1.0 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 74891103 | 75596513 | 79376339 | raised: CBT-02f: set_build reads the rules epoch (D-169); Hub and Registry deploy dearer; +0.9 % |
| grimworld_persistent::test_build::test_bar_elite | 79158453 | 79923223 | 83108764 | +1.0 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 79278726 | 80049606 | 83235061 | +1.0 % |
| grimworld_persistent::test_build::test_bar_profession | 75633393 | 76342723 | 80159860 | raised: CBT-02f: set_build reads the rules epoch (D-169); Hub and Registry deploy dearer; +0.9 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 78200026 | 78948506 | 82103696 | +1.0 % |
| grimworld_persistent::test_build::test_belt_items | 76868643 | 77612973 | 81493622 | raised: CBT-02f: set_build reads the rules epoch (D-169); Hub and Registry deploy dearer; +1.0 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 82630270 | 83444830 | 86750370 | +1.0 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 82288098 | 83079648 | 86393641 | +1.0 % |
| grimworld_persistent::test_build::test_set_build_empty | 78198130 | 78934370 | 82105517 | +0.9 % |
| grimworld_persistent::test_build::test_set_build_floor_refused | 95515354 | 96282194 | 100288592 | +0.8 % |
| grimworld_persistent::test_build::test_set_build_insignia_piece_refused | 95120641 | 95887481 | 99874143 | +0.8 % |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 77999583 | 78770993 | 81890680 | +1.0 % |
| grimworld_persistent::test_build::test_set_build_modifier_slot_and_value_refused | 98899956 | 99703756 | 103839883 | +0.8 % |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 75343063 | 76081513 | 79103875 | +1.0 % |
| grimworld_persistent::test_build::test_set_build_parts | 81984436 | 82736456 | 86078618 | +0.9 % |
| grimworld_persistent::test_build::test_set_build_sixth_rune_refused | 99711685 | 100478525 | 104694739 | +0.8 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_energy | 85531037 | 86388827 | 89807589 | +1.0 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_health | 101252061 | 102150081 | 106239569 | +0.9 % |
| grimworld_persistent::test_build::test_set_build_unknown_modifier_refused | 90910079 | 91650369 | 95454313 | +0.8 % |
| grimworld_persistent::test_build::test_set_build_worst_case | 114395344 | 115328854 | 120038756 | +0.8 % |
| grimworld_persistent::test_fate::test_fate_at_the_configured_address | 4754436 | 4729106 | 4941989 | -0.5 % |
| grimworld_persistent::test_lifecycle::test_enter | 39262690 | 39933840 | 41223725 | +1.7 % |
| grimworld_persistent::test_lifecycle::test_enter_after_other_records_changed | — | 43478493 | 45652418 | new |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 46339823 | 47067923 | 48653234 | +1.6 % |
| grimworld_persistent::test_lifecycle::test_enter_after_the_rules_epoch_wraps | — | 37930716 | 39827252 | new |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 33318590 | 33925670 | 34983470 | +1.8 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 45474680 | 46285270 | 48599534 | raised: CBT-02f: enter reads the rules epoch (D-169); Hub and Registry deploy dearer; +1.8 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_missing_snapshot | 35021863 | 35644523 | 36752650 | +1.8 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_stale_snapshot | 43136242 | 45002852 | 45249921 | +4.3 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_a_new_rules_class | — | 39454576 | 41427305 | new |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_an_input_rewritten | — | 49858842 | 52351785 | new |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 36916850 | 37561450 | 38761643 | +1.7 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 37804651 | 38449251 | 39693834 | +1.7 % |
| grimworld_persistent::test_lifecycle::test_report_open | 36881852 | 37488932 | 39363379 | raised: CBT-02f: enter reads the rules epoch (D-169); Hub and Registry deploy dearer; +1.6 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 37415094 | 38022174 | 39923283 | raised: CBT-02f: enter reads the rules epoch (D-169); Hub and Registry deploy dearer; +1.6 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 37485969 | 38130569 | 39359218 | +1.7 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 38431152 | 39102302 | 40350610 | +1.7 % |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 26770970 | 27351500 | 28109519 | +2.2 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 28760650 | 29303660 | 29714013 | +1.9 % |
| grimworld_persistent::test_lifecycle::test_travel | 34982327 | 35589407 | 36730394 | +1.7 % |
| grimworld_persistent::test_read_cost::test_content_read_probe_alone | 80778060 | 80988150 | 84816963 | +0.3 % |
| grimworld_persistent::test_read_cost::test_content_read_representative | 82499810 | 82715600 | 86624801 | +0.3 % |
| grimworld_persistent::test_read_cost::test_content_read_worst | 84866210 | 85087700 | 89109521 | +0.3 % |
| grimworld_persistent::test_read_cost::test_read_cost_baseline | 8295540 | 8331300 | 8710317 | +0.4 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_1 | 8496100 | 8536560 | 8920905 | +0.5 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_2 | 8550120 | 8590580 | 8977626 | +0.5 % |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_8 | 8874240 | 8914700 | 9317952 | +0.5 % |
| grimworld_persistent::test_read_cost::test_read_cost_eight_calls | 9544690 | 9580450 | 10021925 | +0.4 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_1 | 8334440 | 8370200 | 8751162 | +0.4 % |
| grimworld_persistent::test_read_cost::test_read_cost_local_8 | 8521770 | 8557530 | 8947859 | +0.4 % |
| grimworld_persistent::test_read_cost::test_read_cost_one_call_one_read | 8428970 | 8469090 | 8850419 | +0.5 % |
| grimworld_persistent::test_read_cost::test_read_cost_two_calls | 8623390 | 8659150 | 9054560 | +0.4 % |
| grimworld_persistent::test_registry::test_bundle_version_and_order | 7149520 | 7187840 | 7506996 | +0.5 % |
| grimworld_persistent::test_registry::test_gas_bundle_1 | 2646390 | 2652590 | 2778710 | +0.2 % |
| grimworld_persistent::test_registry::test_gas_bundle_10 | 15102750 | 15108950 | 15857888 | +0.0 % |
| grimworld_persistent::test_registry::test_gas_bundle_32 | 45551630 | 45557830 | 47829212 | +0.0 % |
| grimworld_persistent::test_registry::test_gas_set_record_changed | 3693930 | 3704570 | 3878627 | +0.3 % |
| grimworld_persistent::test_registry::test_gas_set_record_new | 3205370 | 3209840 | 3365639 | +0.1 % |
| grimworld_persistent::test_registry::test_gas_set_record_unchanged | 3491010 | 3496070 | 3665561 | +0.1 % |
| grimworld_persistent::test_registry::test_inputs_version_per_kind | — | 23133590 | 24290270 | new |
| grimworld_persistent::test_registry::test_missing_record_reads_zeros | 2949010 | 2953480 | 3096461 | +0.2 % |
| grimworld_persistent::test_registry::test_reads_bounded | 4820310 | 4830400 | 5061326 | +0.2 % |
| grimworld_persistent::test_registry::test_set_admin_hands_over | 3375570 | 3385610 | 3544349 | +0.3 % |
| grimworld_persistent::test_registry::test_set_admin_refused | 2724110 | 2728580 | 2860316 | +0.2 % |
| grimworld_persistent::test_registry::test_set_record_carriers | 8128360 | 8159580 | 8534778 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_caste_bounds | 15239100 | 15302640 | 16001055 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_caste_rewrite_moves_the_bound | 19218570 | 19289600 | 20179499 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_caste_skills_either_order | 11099690 | 11130120 | 11654675 | +0.3 % |
| grimworld_persistent::test_registry::test_set_record_composite_needs_parent | 7113410 | 7140890 | 7469081 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_existing_changes | 4490490 | 4505600 | 4715015 | +0.3 % |
| grimworld_persistent::test_registry::test_set_record_id_zero_refused | 1837820 | 1848960 | 1929711 | +0.6 % |
| grimworld_persistent::test_registry::test_set_record_insignia_pieces | 7213630 | 7244850 | 7574312 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_new_sequential | 4416510 | 4425450 | 4637336 | +0.2 % |
| grimworld_persistent::test_registry::test_set_record_not_live_refused | 3766310 | 3798520 | 3954626 | +0.9 % |
| grimworld_persistent::test_registry::test_set_record_not_next_refused | 3760970 | 3786510 | 3949019 | +0.7 % |
| grimworld_persistent::test_registry::test_set_record_outline_chunk_refused | 4568450 | 4600000 | 4796873 | +0.7 % |
| grimworld_persistent::test_registry::test_set_record_part_count_refused | 2645820 | 2666890 | 2778111 | +0.8 % |
| grimworld_persistent::test_registry::test_set_record_per_source_bounds | 71620060 | 71982600 | 75201063 | +0.5 % |
| grimworld_persistent::test_registry::test_set_record_quiver_ids | 3618270 | 3630610 | 3799184 | +0.3 % |
| grimworld_persistent::test_registry::test_set_record_quotas_keyed_by_location | 5372910 | 5394210 | 5641556 | +0.4 % |
| grimworld_persistent::test_registry::test_set_record_refused_to_others | 1595840 | 1605770 | 1675632 | +0.6 % |
| grimworld_persistent::test_registry::test_set_record_sources_refused | 9753910 | 9820750 | 10241606 | +0.7 % |
| grimworld_persistent::test_registry::test_set_record_unknown_kind_refused | 1209960 | 1209980 | 1270458 | +0.0 % |
| grimworld_persistent::test_registry::test_version_rises_per_changed_record | 8422430 | 8511950 | 8843552 | +1.1 % |
| grimworld_persistent::test_seed::test_gas_seed_write | 19508030 | 19571240 | 20483432 | +0.3 % |
| grimworld_persistent::test_seed::test_seed_rewritten_unchanged | 28190810 | 28266050 | 29600351 | +0.3 % |
| grimworld_persistent::test_seed::test_seed_written_and_read_back | 21534340 | 21603550 | 22611057 | +0.3 % |

## Acceptance criteria
- [x] **AC-1**:
  - A rewrite of each input kind stales every stored snapshot: `test_enter_refuses_after_an_input_rewritten` (SKILL, ITEM, MODIFIER in turn, each cleared by `set_build`) and `test_inputs_version_per_kind` (+1 per rewritten kind).
  - Any other kind, new or rewritten, stales none, and neither does a new id of an input kind: `test_enter_after_other_records_changed` (the stored kit word is the same and `enter` copies it) and `test_inputs_version_per_kind` (LOCATION, GATE, BOOK, QUEST, SHOP, ARMOR_SET).
  - The list of input kinds is justified above. `test_flattening_inputs` guards the list; `test_set_build_requests_the_input_kinds` (fix loop 1) ties it to what `set_build` requests.
- [x] **AC-2**:
  - A new class stales and the same class does not: `test_enter_refuses_after_a_new_rules_class`.
  - The wrap is defined and tested: `test_rules_epoch_wraps` and `test_enter_after_the_rules_epoch_wraps`.
  - Another rules epoch at the same inputs version is refused: `test_other_rules_refused`.
- [x] **AC-3**: `enter` 4,513,259 net on the node, under 5.25 M (`lifecycle-probe-output.txt`). `Hub` 45.30 % and `Registry` 30.23 % (`class_sizes.py`).
- [x] **AC-4**:
  - Every `bundle` caller is updated: `Hub.set_build`, `Hub.enter`, the tests of the three packages and the ephemeral registry double. `Instances` does not call `bundle` yet.
  - No event changed (`events.cairo` untouched, D-149).
- [x] **AC-5**:
  - Models, traits, an `Assert` impl and short scoped names, as D-143 asks. `Inputs::includes` is a trait function, not a free function.
  - Unit tests are in their modules (D-167): `models/versions.cairo`, `models/snapshot.cairo`, `systems/registry.cairo` (`inputs_tests`, `version_cost_tests`), `systems/hub.cairo` (layout).
  - CI green. `gas_budgets.py --check`: 757 tests, 4 files current.

## Deviations from the brief
- **The counter shares the content version's slot** (`versions: Versions`) instead of taking a slot of its own. The brief and D-169 say "a second counter" and "one counter slot". It is still a second counter, but packed, because `bundle` is on `play`'s path (E-5) and a second slot would add a read to every invocation (CAIRO §1: execution first). As a result, ENG-01's storage variable `content_version` is renamed `versions`; the `content_version()` view is unchanged.
- **A new id of an input kind does not raise the inputs version**; only a changed existing record does. D-169 says "a changed record of an input kind". This is narrower, and it is sound for the three reasons given under *The input kinds and why*. It keeps new items, skills and modifiers from staling every player. If the orchestrator prefers the literal rule, the change is one line (`raise_versions(false)` → `raise_versions(Inputs::includes(kind))` on the new-id path) plus the tests' expectations.
- `contracts/tools/budget_table.py` and its output: the slot name `R.content_version` → `R.versions`, within `contracts/tools/`.

## Escalations
- **ENG-01 outside the allowlisted sections**: §4.2's listing (`IRegistryRead (Registry): … bundle -> (version: u32, records) …`, around line 840) and §11's E-5 row ("`Registry.content_version` (`u32`), returned first by `bundle`") still describe the old return and slot. Both need the inputs version added. I did not edit them: the allowlist covers §3.3, §3.5, §9.3 and §10 only.
- **A future input kind**: once weapon statistics or set bonuses are laid out, `set_build` will read `BASE` or `ARMOR_SET`, and that lot must add them to `Inputs::includes`. `test_set_build_requests_the_input_kinds` (fix loop 1) will fail until it does, which is the reminder; `test_flattening_inputs` alone would not have caught it. Worth a line in PLAN for the lot that lays them out.
- **`set_contracts` in §10's admin row**: the row still prices 4 address writes. With CBT-02f, a class change adds `H.rules_epoch`, plus the `flatten` write already there. I described it in §9.3's text but did not reprice `budget_table.py`'s generic admin row.

## Open questions
- None blocking. The two deviations above are for the orchestrator to confirm at review: the packed slot, and new ids not counting.


## Fix loop 1
Two audits of `cb9f2bc`: quality, `[GPT-6-Sol]`, FAIL (one major, two minors); security and cost, `[GPT-6-Astra]`, PASS WITH FINDINGS (three notes; its note 3 is quality 3). All five fixed. First I merged `origin/main` (it added only ENG-R1a's brief, no code), and the generated budget files were regenerated, not edited. PR #219, commits `573e503`, `0c010f3` (tests, ENG-01, budgets) and `60a650f` (generated files). CI is green at `60a650f`: every check passes, indexer-node skips.

**1. Quality 1 (major): the new state as models, through the store.**
- `Hub.rules_epoch` is now the model `RulesEpoch { value: u16 }` (`models/rules_epoch.cairo`).
  - It packs to the value as a felt, so the storage layout is the `u16`'s, unchanged.
  - It holds `next()` (511 → 0, moved from `StoredSnapshotTrait::next_rules`) and `moves(flatten, stored flatten, registry, stored registry)`.
  - It has its own unit tests: wrap, packing, moves.
- **Why its own model and not a configuration model:** the rest of `Hub`'s configuration (registry, `Instances`, `Market`, the randomness provider, the flattening's class) is one full felt per slot. A configuration model would pack nothing, and its typed read would make every entrypoint that needs one address read all of them.
- `Registry.versions` was already the `Versions` model.
- `store.cairo` gains typed methods, on the CBT-02e pattern (paths typed on the model):
  - `get_rules_epoch` / `set_rules_epoch`;
  - `get_versions` / `set_versions`;
  - `get_address` and `get_class_hash`, for the two values `set_contracts` now compares.
- Every new read and write goes through them: `Hub::rules()` (read by `set_build`, `enter`, `set_contracts`), `set_contracts`' write of the epoch, and `Registry::stored_versions()` (read by `bundle`, `content_version`, `set_record`) with `raise_versions`' write.
- Left as they were (ENG-R1a's): the pre-existing direct accesses, including `set_contracts`' five address and class writes.
- **Effect:**
  - `Hub` 45.40 % (37,194 CASM felts; 45.30 % at `cb9f2bc`, +86 felts, mostly item 4's comparison);
  - `Registry` 30.04 % (24,611; 30.23 % at `cb9f2bc`, −152);
  - node: `enter` and `set_build` identical to `cb9f2bc` (belt's worst case 4,513,259 net; the probe's figures and write sets equal, so the output file is unchanged);
  - `set_build` worst-case call 8,124,823, unchanged.

**2. Quality 2: every non-input kind.** `test_registry::test_inputs_version_every_other_kind` writes a record of each of the 22 kinds that are not inputs, new and then changed. For each kind it asserts the content version rose by 2 and the inputs version stayed 0, and it counts that the loop ran 22 times. `CASTE` and `ARMOR_SET` take legal records; the composite kinds take ids under location 1. The representative `enter` checks are kept (`test_enter_after_other_records_changed`).

**3. Quality 3 / security note 3: the tie to `set_build`.** `test_build::test_set_build_requests_the_input_kinds` puts a recording registry (`RecordingRegistry`, a test contract) in front of the real one:
- it forwards every read, and records one bit per kind that `bundle` is asked for (through the storage syscall, since `bundle` is a view);
- the test runs `set_build`'s worst case (8 skills, 4 potions, 7 pieces holding 15 modifiers), which asks for every kind `set_build` can ask for;
- it asserts the recorded kinds equal the kinds `Inputs::includes` accepts.

`test_flattening_inputs` is now described as guarding the current list only, and the report's claim is corrected above (*The input kinds and why*, *Acceptance criteria*, *Escalations*).

**4. Security note 2: the registry moves the epoch.**
- `set_contracts` raises the rules epoch when `flatten` **or `registry`** changes (`RulesEpochTrait::moves`), and not when the same two are set again. The five writes stay unconditional, as before CBT-02f.
- `test_lifecycle::test_enter_refuses_after_a_new_registry`:
  - another registry: +1;
  - back to the original: +1, and `enter` refuses `snapshot: stale`;
  - the same two again: +0;
  - after `set_build`, the adventurer enters.
- ENG-01 §3.3 and §9.3 say so (two reads to compare, through the store).

**5. Security note 1: the limitation, documented and shown.**
- ENG-01 §3.3 (the `StoredSnapshot` paragraph) states it: the 9-bit epoch repeats after 512 changes. A snapshot left without `set_build` through exactly 512 (or a multiple) changes of the configuration, with no input change, reads fresh again. Only the administrator can reach this path; it is accepted as it stands.
- `test_lifecycle::test_rules_epoch_full_cycle_reads_fresh`: a snapshot flattened at epoch 1 is refused after 1 change and after 511 changes, and `enter` accepts it after exactly 512 changes (the epoch back at 1). Nothing else changed for it.

**Commands**
```
$ git merge origin/main                                                   → 9a77da7 (ENG-R1a's brief only)
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build        → first: error E2143, `#[inline(always)]` on a generic `moves`; made concrete → Finished
$ cd contracts/persistent && snforge test                                 → Tests: 198 passed, 0 failed
$ python3 ../tools/set_budgets.py <log>; main's budget kept wherever the measure fits under it
  → the same nine raises as at cb9f2bc, each keeping its `// gas: raised, CBT-02f: …` line
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --workspace   → applied; no raise line wrapped
$ python3 scripts/gas_budgets.py                                          → GAS.md, docs/BUDGETS.md written
$ python3 scripts/gas_budgets.py --check                                  → gas check: 763 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py                                  → Registry 24,611 30.04 % · Hub 37,194 45.40 %
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py         → every label's l2_gas and write set equal to the committed output (enter, belt's worst case: 4,702,400, net 4,513,259)
$ snforge test test_set_build_worst_case                                  → gas set_build, worst case: 8124823
$ gh pr checks 219 --watch                                                → every check pass (indexer-node skipping)
```

**Rows that changed since `cb9f2bc`** (docs/BUDGETS.md at `cb9f2bc` against now; measures in L2 gas). In summary:
- **New tests:** the three of `RulesEpoch`, `test_set_build_requests_the_input_kinds`, `test_inputs_version_every_other_kind`, `test_enter_refuses_after_a_new_registry`, `test_rules_epoch_full_cycle_reads_fresh`.
- **Moved:** `snapshot::tests::test_rules_epoch_wraps` → `rules_epoch::tests::test_rules_epoch_wraps`.
- **The two `set_contracts` raises** (`test_hub_set_contracts_by_admin` +20,520, `test_hub_set_admin_hands_over` +33,530: the two comparison reads) keep their CBT-02f reason with a re-measured budget.
- **The `test_accounts` and `test_fate` rows** rise by a flat +67,100. Their setup calls `set_contracts`, which now reads `flatten` and `registry`. Each still fits under its budget, unchanged.
- **The 40 rows under ±0.1 %** are D-154's build variance plus the deploys of the slightly changed classes.

| Test | Measured at cb9f2bc | Now | Budget at cb9f2bc | Now | Note |
|---|---:|---:|---:|---:|---|
| grimworld_persistent::models::rules_epoch::tests::test_rules_epoch_moves | — | 13720 | — | 14406 | new |
| grimworld_persistent::models::rules_epoch::tests::test_rules_epoch_packing | — | 13720 | — | 14406 | new |
| grimworld_persistent::models::rules_epoch::tests::test_rules_epoch_wraps | — | 13720 | — | 14406 | new |
| grimworld_persistent::models::snapshot::tests::test_rules_epoch_wraps | 13720 | — | 14406 | — | removed (moved) |
| grimworld_persistent::test_accounts::test_create_adventurer | 23845550 | 23912650 | 25009562 | 25009562 | +0.28 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 9215730 | 9282830 | 9648251 | 9648251 | +0.73 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 9217090 | 9284190 | 9649679 | 9649679 | +0.73 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 19396480 | 19463580 | 20338038 | 20338038 | +0.35 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 7576660 | 7643760 | 7927227 | 7927227 | +0.89 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 40839480 | 40906580 | 42853188 | 42853188 | +0.16 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 13937630 | 14004730 | 14606246 | 14606246 | +0.48 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 12942360 | 13009460 | 13561212 | 13561212 | +0.52 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 28021590 | 28088690 | 29394404 | 29394404 | +0.24 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 24254480 | 24321580 | 25438938 | 25438938 | +0.28 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 13023180 | 13090280 | 13646073 | 13646073 | +0.52 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 13346130 | 13413230 | 13985171 | 13985171 | +0.50 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 13322640 | 13389740 | 13960506 | 13960506 | +0.50 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 21184750 | 21251850 | 22215722 | 22215722 | +0.32 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 49455340 | 49522440 | 51899841 | 51899841 | +0.14 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 23850020 | 23917120 | 25014255 | 25014255 | +0.28 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 40893080 | 40960180 | 42909468 | 42909468 | +0.16 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 16981120 | 17048220 | 17801910 | 17801910 | +0.40 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 13340760 | 13407860 | 13979532 | 13979532 | +0.50 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 12948090 | 13015190 | 13567229 | 13567229 | +0.52 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 18631090 | 18698190 | 19534379 | 19534379 | +0.36 % |
| grimworld_persistent::test_accounts::test_register | 14903840 | 14970940 | 15620766 | 15620766 | +0.45 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 9060290 | 9127390 | 9485039 | 9485039 | +0.74 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 27415510 | 27482610 | 28758020 | 28758020 | +0.24 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 21138730 | 21205830 | 22167401 | 22167401 | +0.32 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 21467470 | 21601670 | 22489005 | 22489005 | +0.63 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 42738320 | 42805420 | 44846970 | 44846970 | +0.16 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 14714990 | 14782090 | 15422474 | 15422474 | +0.46 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 12748790 | 12815890 | 13357964 | 13357964 | +0.53 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 13074660 | 13141760 | 13700127 | 13700127 | +0.51 % |
| grimworld_persistent::test_admin::test_hub_set_admin_hands_over | 5893380 | 5926910 | 6188049 | 6223256 | +0.57 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_by_admin | 5194030 | 5214550 | 5453732 | 5475278 | +0.40 % |
| grimworld_persistent::test_admin::test_hub_set_contracts_refused_to_others | 4164580 | 4177590 | 4311605 | 4311605 | +0.31 % |
| grimworld_persistent::test_build::test_attributes_indices | 85624249 | 85644769 | 89065472 | 89065472 | +0.02 % |
| grimworld_persistent::test_build::test_attributes_points_by_level | 93574334 | 93594854 | 97211525 | 97211525 | +0.02 % |
| grimworld_persistent::test_build::test_attributes_rank_and_points | 79126876 | 79147396 | 82253752 | 82253752 | +0.03 % |
| grimworld_persistent::test_build::test_bar_duplicate_refused | 75596513 | 75617033 | 79376339 | 79397885 | +0.03 % |
| grimworld_persistent::test_build::test_bar_elite | 79923223 | 79943743 | 83108764 | 83108764 | +0.03 % |
| grimworld_persistent::test_build::test_bar_known_and_registered | 80049606 | 80070126 | 83235061 | 83235061 | +0.03 % |
| grimworld_persistent::test_build::test_bar_profession | 76342723 | 76363243 | 80159860 | 80181406 | +0.03 % |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | 78948506 | 78969026 | 82103696 | 82103696 | +0.03 % |
| grimworld_persistent::test_build::test_belt_items | 77612973 | 77633493 | 81493622 | 81515168 | +0.03 % |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | 83444830 | 83465350 | 86750370 | 86750370 | +0.02 % |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | 83079648 | 83100168 | 86393641 | 86393641 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_empty | 78934370 | 78954890 | 82105517 | 82105517 | +0.03 % |
| grimworld_persistent::test_build::test_set_build_floor_refused | 96282194 | 96302714 | 100288592 | 100288592 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_insignia_piece_refused | 95887481 | 95908001 | 99874143 | 99874143 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_layout_refusals | 78770993 | 78791513 | 81890680 | 81890680 | +0.03 % |
| grimworld_persistent::test_build::test_set_build_modifier_slot_and_value_refused | 99703756 | 99724276 | 103839883 | 103839883 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | 76081513 | 76102033 | 79103875 | 79103875 | +0.03 % |
| grimworld_persistent::test_build::test_set_build_parts | 82736456 | 82756976 | 86078618 | 86078618 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_requests_the_input_kinds | — | 109841165 | — | 115333224 | new |
| grimworld_persistent::test_build::test_set_build_sixth_rune_refused | 100478525 | 100499045 | 104694739 | 104694739 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_energy | 86388827 | 86409347 | 89807589 | 89807589 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_stores_the_extremal_max_health | 102150081 | 102170601 | 106239569 | 106239569 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_unknown_modifier_refused | 91650369 | 91670889 | 95454313 | 95454313 | +0.02 % |
| grimworld_persistent::test_build::test_set_build_worst_case | 115328854 | 115349374 | 120038756 | 120038756 | +0.02 % |
| grimworld_persistent::test_fate::test_fate_at_the_configured_address | 4729106 | 4796206 | 4941989 | 4941989 | +1.42 % |
| grimworld_persistent::test_lifecycle::test_enter | 39933840 | 39954360 | 41223725 | 41223725 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_enter_after_other_records_changed | 43478493 | 43499013 | 45652418 | 45673964 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | 47067923 | 47088443 | 48653234 | 48653234 | +0.04 % |
| grimworld_persistent::test_lifecycle::test_enter_after_the_rules_epoch_wraps | 37930716 | 37992276 | 39827252 | 39891890 | +0.16 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 33925670 | 33946190 | 34983470 | 34983470 | +0.06 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 46285270 | 46305790 | 48599534 | 48621080 | +0.04 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_missing_snapshot | 35644523 | 35665043 | 36752650 | 36752650 | +0.06 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_a_stale_snapshot | 45002852 | 45023372 | 45249921 | 45249921 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_a_new_registry | — | 39132206 | — | 41088817 | new |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_a_new_rules_class | 39454576 | 39583236 | 41427305 | 41562398 | +0.33 % |
| grimworld_persistent::test_lifecycle::test_enter_refuses_after_an_input_rewritten | 49858842 | 49879362 | 52351785 | 52373331 | +0.04 % |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 37561450 | 37581970 | 38761643 | 38761643 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 38449251 | 38469771 | 39693834 | 39693834 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_report_open | 37488932 | 37509452 | 39363379 | 39384925 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 38022174 | 38042694 | 39923283 | 39944829 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 38130569 | 38151089 | 39359218 | 39359218 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 39102302 | 39122822 | 40350610 | 40350610 | +0.05 % |
| grimworld_persistent::test_lifecycle::test_rules_epoch_full_cycle_reads_fresh | — | 320612303 | — | 336642919 | new |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | 27351500 | 27372020 | 28109519 | 28109519 | +0.08 % |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | 29303660 | 29324180 | 29714013 | 29714013 | +0.07 % |
| grimworld_persistent::test_lifecycle::test_travel | 35589407 | 35609927 | 36730394 | 36730394 | +0.06 % |
| grimworld_persistent::test_registry::test_inputs_version_every_other_kind | — | 50182340 | — | 52691457 | new |
