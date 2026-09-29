# [Opus 5.5] CBT-01 — Freeze the combat interfaces

## Summary

The combat's data from design/19 (v0.5, D-155) is now compiling code in `grimworld_logic`. CBT-02 to CBT-05 and ENG-07 can implement the rules without inventing a field. What exists now:

- **Every enumeration §7.1 names**, as frozen ids:
  - effect kinds 1–23 and their classes;
  - targets, shapes 1–5, filters, guards 0–4, scopes;
  - passive ids 40–65, conditions 1–9, damage types 1–9, skill kinds 1–12;
  - weapon classes 1–6, hit classes, trap object kinds 4 and 9;
  - the goblin activation states (activating 0–3, recovering 254, none 255);
  - `Placer`, the `param` of a placed trap.
- **The effect entry** (97 bits) and **the passive** (53 bits). Each has pack and unpack (signed fields in two's complement), the §2.2 scaling line through rank 15, and the content pipeline's checks:
  - the fields each kind reads;
  - value and duration bounds at ranks 0 and 15;
  - **the legal carriers of §5.14**, plus FX-21, FX-35 and the unscaled potion.
- **Five registry records** as D-143 models, each with `content::Record` packing into its parts, `...Assert` checks and `errors`:
  - `SKILL` (2 parts), `ITEM` (1), `MODIFIER` (1), `ARMOR_SET` (1);
  - `CASTE` (2 parts), with its inline `Weapon`.
- **The state an actor carries** (§7.2, FX-24): the snapshot words are repacked and ENG-06's member and goblin words are extended exactly as §7.2 decided. This costs **0 new slots**.
- **F-21 is settled**: |unguarded armor| ≤ 9,995, stored as an `i16`, and wider values are refused.
- ENG-01 §3.2 and §3.5 are amended.

Pull request: https://github.com/bal7hazar/grimworld/pull/165 (CI green on `b5bce2d`). I read my model as Opus 5.5 from my session, which is the model the brief names.

## Files changed

- `contracts/logic/src/types.cairo`: declares `combat`, `effect`, `passive`.
- `contracts/logic/src/types/effect.cairo` (new): effect kinds, `KindClass`, target, shape, filter, guard, scope, `Entry` (pack, unpack, value, duration, class), `EntryAssert` (`assert_valid`, `assert_legal`, `assert_carrier`), `Carrier`.
- `contracts/logic/src/types/passive.cairo` (new): passive ids 40–65, `Passive` (pack, unpack, pair of two), `PassiveAssert`, the §7.2 bounds.
- `contracts/logic/src/types/combat.cairo` (new): conditions with their pips, damage types, skill kinds, weapon classes, trap object kinds, activation states, `HitClass`, `Placer`.
- `contracts/logic/src/helpers/signed.cairo` (new) and `helpers.cairo`: `SignedTrait`, two's complement for `i8` and `i16`.
- `contracts/logic/src/models/{skill,item,modifier,armor_set,caste}.cairo` (new); `models.cairo`, `models/index.cairo`: the five records and `Weapon`.
- `contracts/logic/src/snapshot.cairo`: `MemberStats`, `MemberBar` (+`QuickCast`) and `MemberKit` repacked (FX-24); `MAX_UNGUARDED_ARMOR` (F-21); `SnapshotTrait::new` puts the class armor in `bar.armor`.
- `contracts/ephemeral/src/models/member.cairo`: `MemberState.casts_2`, `flag` constants, and `Effect` gains charges 0–63, a potion tag and a rank.
- `contracts/ephemeral/src/models/goblin.cairo`: `GoblinTimers.effect_charges` and `effect_rank`; `MAX_ADRENALINE`; `activation::NONE`; energy and adrenaline units documented.
- `contracts/ephemeral/src/systems/instances.cairo`: one test budget only. The lines that write the words did not need to change, because the words are written whole.
- Tests:
  - `contracts/logic/tests/test_combat.cairo` (new, 65 tests);
  - `test_packing.cairo` (+9 tests, 2 updated) and `test_lifecycle.cairo` (updated);
  - `contracts/ephemeral/tests/test_layout.cairo` (+6 tests, 3 updated) and `test_lifecycle.cairo` (literals, budgets);
  - `contracts/persistent/tests/test_lifecycle.cairo` (the armor is now read from `bar`; budgets).
- `docs/architecture/ENG-01-interfaces.md`: §3.2 (member and goblin words, F-21, placed traps) and §3.5 (layouts of `SKILL`, `ITEM`, `MODIFIER`, `ARMOR_SET`, `CASTE`, the entry and the passive).
- `contracts/{logic,ephemeral,persistent}/GAS.md` and `docs/BUDGETS.md`: generated.

## Commands run

```
$ scripts/lock.sh scarb --manifest-path contracts/logic/Scarb.toml build        (and ephemeral, persistent)
    Finished `dev` profile target(s) …   (no warning)
$ cd contracts/logic && snforge test
Tests: 128 passed, 0 failed, 0 ignored, 0 filtered out
$ cd contracts/ephemeral && snforge test
Tests: 49 passed, 0 failed          (before set_budgets: 45 passed, 4 failed on budgets only: the layout tests)
$ cd contracts/persistent && snforge test
Tests: 128 passed, 0 failed, 0 ignored, 0 filtered out
$ snforge test | python3 contracts/tools/set_budgets.py /dev/stdin     (per package)
set: 127 / 49 / 128 missing: []
$ python3 scripts/gas_budgets.py && python3 scripts/gas_budgets.py --check
gas check: 305 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py
| grimworld_ephemeral | `Instances` | 831,545 | 12,171 | 32,719 | 39.94 % | ok |
| grimworld_persistent | `Hub` | 747,910 | 11,434 | 29,243 | 35.70 % | ok |
| grimworld_persistent | `Registry` | 158,206 | 2,271 | 5,318 | 6.49 % | ok |   (every class ok)
$ gh pr checks 165      → cairo (contracts) pass, tooling pass, client pass, every spike pass (indexer-node skipped)
```

The first CI run failed only on `scarb fmt`: the formatter wrapped long `// gas: raised` comments. I shortened the reasons, ran `scarb fmt`, and the second run was green.

## Cost

**Slots: 0 new** (FX-24). Every addition sits in bits the frozen words already had free.

**Gas, the ENG-06 words** (whole snforge tests, measured):
- `create`: +164,690 (`test_create_without_tasks`, +0.6 %) to +1,068,550 (`test_create_refusals`, several creates, +3.3 %). `test_create_first_entry` rose +281,700 (+0.9 %).
- `Hub.enter`: +446,900 (`test_enter`, +1.3 %).
- The cause is the larger `Snapshot` crossing `Instances.create` by Serde (+21 felts: stats +5, bar +14, kit +2), plus the new fields' packing.
- `play` is not written yet, so nothing in it is measured.

Several tests of pure checks measure at the empty-test floor (13,720, or 15,520 for a panic): `test_entry_legal`, `test_entry_scaling`, `test_passive_legal`, `test_placer_round_trip`, `test_signed_ends`. The compiler folds their constant inputs. Their figures prove behaviour, not cost.

Table printed by `python3 scripts/gas_budgets.py --report` (origin/main fetched). Only the rows this lot touched are shown; every other row reads "unchanged".

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::systems::instances::close_tests::test_close_on_defeat | 4799530 | 4806860 | 5047203 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.2 % |
| grimworld_ephemeral::test_layout::test_combat_fields_layout | — | 704800 | 740040 | new |
| grimworld_ephemeral::test_layout::test_effect_belt_slot_refused | — | 15520 | 16296 | new |
| grimworld_ephemeral::test_layout::test_effect_charges_refused | — | 15520 | 16296 | new |
| grimworld_ephemeral::test_layout::test_effect_rank_refused | — | 15520 | 16296 | new |
| grimworld_ephemeral::test_layout::test_empty_timers_packed | 173400 | 209900 | 220395 | raised: CBT-01: design/19 section 7.2's fields in the words; +21.0 % |
| grimworld_ephemeral::test_layout::test_goblin_effect_charges_refused | — | 33950 | 35648 | new |
| grimworld_ephemeral::test_layout::test_goblin_effect_rank_refused | — | 33950 | 35648 | new |
| grimworld_ephemeral::test_layout::test_goblin_layout | 322870 | 345130 | 362387 | raised: CBT-01: design/19 section 7.2's fields in the words; +6.9 % |
| grimworld_ephemeral::test_layout::test_member_layout | 482580 | 557790 | 585680 | raised: CBT-01: design/19 section 7.2's fields in the words; +15.6 % |
| grimworld_ephemeral::test_lifecycle::test_create_first_entry | 31631012 | 31912712 | 33508348 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.9 % |
| grimworld_ephemeral::test_lifecycle::test_create_refusals | 32573826 | 33642376 | 35324495 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +3.3 % |
| grimworld_ephemeral::test_lifecycle::test_create_reuses_the_slot | 43967391 | 44468891 | 46692336 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +1.1 % |
| grimworld_ephemeral::test_lifecycle::test_create_sealed | 25833696 | 25998386 | 27298306 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.6 % |
| grimworld_ephemeral::test_lifecycle::test_create_without_tasks | 27762006 | 27926696 | 29323031 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.6 % |
| grimworld_ephemeral::test_lifecycle::test_generation_isolation | 45572993 | 46062793 | 48365933 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +1.1 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_hub | 33175476 | 33351126 | 35018683 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_location | 39121427 | 39354017 | 41321718 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.6 % |
| grimworld_ephemeral::test_lifecycle::test_not_controller | 27966354 | 28153234 | 29560896 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.7 % |
| grimworld_ephemeral::test_lifecycle::test_refused_absent | 40143332 | 40487302 | 42511668 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.9 % |
| grimworld_ephemeral::test_lifecycle::test_refused_closed | 38055615 | 38399685 | 40319670 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.9 % |
| grimworld_ephemeral::test_lifecycle::test_refused_gate | 58509716 | 58707076 | 61642430 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.3 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sealed | 29068609 | 29236929 | 30698776 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.6 % |
| grimworld_ephemeral::test_lifecycle::test_refused_sequence | 33019086 | 33194666 | 34854400 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |
| grimworld_ephemeral::test_lifecycle::test_set_controller | 32926602 | 33106152 | 34761460 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |
| grimworld_ephemeral::test_lifecycle::test_travel_back | 31486399 | 31658519 | 33241445 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |
| grimworld_logic::test_combat::test_armor_set_round_trip | — | 222550 | 233678 | new |
| grimworld_logic::test_combat::test_carrier_attack_bonus_in_a_spell_refused | — | 155230 | 162992 | new |
| grimworld_logic::test_combat::test_carrier_attack_entry_on_self_refused | — | 68580 | 72009 | new |
| grimworld_logic::test_combat::test_carrier_attack_with_damage_refused | — | 81010 | 85061 | new |
| grimworld_logic::test_combat::test_carrier_damage_not_first_refused | — | 155720 | 163506 | new |
| grimworld_logic::test_combat::test_carrier_disc_1_in_a_skill_refused | — | 96560 | 101388 | new |
| grimworld_logic::test_combat::test_carrier_disc_2_refused | — | 80550 | 84578 | new |
| grimworld_logic::test_combat::test_carrier_gap_refused | — | 205490 | 215765 | new |
| grimworld_logic::test_combat::test_carrier_modifier_on_another_set_refused | — | 207900 | 218295 | new |
| grimworld_logic::test_combat::test_carrier_modifier_without_hit_refused | — | 193220 | 202881 | new |
| grimworld_logic::test_combat::test_carrier_trap_not_first_refused | — | 140380 | 147399 | new |
| grimworld_logic::test_combat::test_carrier_trap_payload_on_self_refused | — | 200870 | 210914 | new |
| grimworld_logic::test_combat::test_carrier_two_hits_refused | — | 156000 | 163800 | new |
| grimworld_logic::test_combat::test_carrier_two_holding_refused | — | 155050 | 162803 | new |
| grimworld_logic::test_combat::test_caste_armor_vs_refused | — | 121940 | 128037 | new |
| grimworld_logic::test_combat::test_caste_energy_refused | — | 34250 | 35963 | new |
| grimworld_logic::test_combat::test_caste_health_regen_refused | — | 34250 | 35963 | new |
| grimworld_logic::test_combat::test_caste_rank_refused | — | 34250 | 35963 | new |
| grimworld_logic::test_combat::test_caste_round_trip | — | 617800 | 648690 | new |
| grimworld_logic::test_combat::test_caste_weapon_refused | — | 50650 | 53183 | new |
| grimworld_logic::test_combat::test_entry_charges_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_condition_of_zero_ticks_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_duration_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_empty_with_field_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_filter_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_guard_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_legal | — | 13720 | 14406 | new |
| grimworld_logic::test_combat::test_entry_negative_duration_at_15_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_oil_without_time_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_post_mvp_kind_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_rank_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_round_trip | — | 765240 | 803502 | new |
| grimworld_logic::test_combat::test_entry_scaling | — | 13720 | 14406 | new |
| grimworld_logic::test_combat::test_entry_scope_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_shape_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_shape_zero_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_target_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_unknown_condition_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_unread_field_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_entry_value_at_rank_15_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_item_entry_not_a_potion_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_item_round_trip | — | 457000 | 479850 | new |
| grimworld_logic::test_combat::test_item_scaled_potion_refused | — | 71670 | 75254 | new |
| grimworld_logic::test_combat::test_kind_classes_and_ids | — | 155480 | 163254 | new |
| grimworld_logic::test_combat::test_legal_carriers | — | 1432720 | 1504356 | new |
| grimworld_logic::test_combat::test_modifier_cost_not_fixed_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_modifier_round_trip | — | 182430 | 191552 | new |
| grimworld_logic::test_combat::test_modifier_slot_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_damage_percent_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_guard_not_its_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_guard_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_guarded_armor_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_legal | — | 13720 | 14406 | new |
| grimworld_logic::test_combat::test_passive_post_mvp_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_round_trip | — | 286920 | 301266 | new |
| grimworld_logic::test_combat::test_passive_scope_not_its_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_passive_scope_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_placer_member_entity_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_placer_round_trip | — | 13720 | 14406 | new |
| grimworld_logic::test_combat::test_placer_skill_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_signed_ends | — | 13720 | 14406 | new |
| grimworld_logic::test_combat::test_skill_recharge_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_skill_round_trip | — | 1656300 | 1739115 | new |
| grimworld_logic::test_combat::test_skill_seal_of_capture_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_combat::test_skill_target_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_lifecycle::test_snapshot | 13720 | 50750 | 53288 | raised: CBT-01: design/19's passives in the snapshot (FX-24); +269.9 % |
| grimworld_logic::test_lifecycle::test_snapshot_of_no_profession | 15520 | 21720 | 22806 | raised: CBT-01: design/19's passives in the snapshot (FX-24); +39.9 % |
| grimworld_logic::test_packing::test_bar_and_kit_layout | 212440 | 379970 | 398969 | raised: CBT-01: design/19's passives in the bar and the kit (FX-24); +78.9 % |
| grimworld_logic::test_packing::test_bar_armor_above_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_bar_armor_below_bound_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_bar_passives_layout | — | 799210 | 839171 | new |
| grimworld_logic::test_packing::test_bar_quick_cast_attribute_refused | — | 81210 | 85271 | new |
| grimworld_logic::test_packing::test_kit_condition_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_kit_knockdown_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_kit_passives_layout | — | 616460 | 647283 | new |
| grimworld_logic::test_packing::test_kit_percent_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_stats_armor_vs_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_packing::test_stats_layout | 302860 | 551920 | 579516 | raised: CBT-01: nine armors by damage type (FX-23, FX-24); +82.2 % |
| grimworld_persistent::test_lifecycle::test_enter | 35725410 | 36172310 | 37980926 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +1.3 % |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | 31350460 | 31504150 | 33079358 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |
| grimworld_persistent::test_lifecycle::test_enter_refusals | 43623030 | 43933630 | 46130312 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.7 % |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | 34444070 | 34680970 | 36415019 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.7 % |
| grimworld_persistent::test_lifecycle::test_report_moved | 35432851 | 35586541 | 37365869 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.4 % |
| grimworld_persistent::test_lifecycle::test_report_open | 34922652 | 35076342 | 36830160 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.4 % |
| grimworld_persistent::test_lifecycle::test_report_refusals | 35474424 | 35628114 | 37409520 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.4 % |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | 35115149 | 35268839 | 37032281 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.4 % |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | 36235922 | 36543302 | 38370468 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.8 % |
| grimworld_persistent::test_lifecycle::test_travel | 33018237 | 33171927 | 34830524 | raised: CBT-01: the snapshot carries design/19's passives (FX-24); +0.5 % |

## The map from design/19 to code (AC-1)

| design/19 | Code |
|---|---|
| §1 X-2 (ids never change meaning) | Every enumeration is a `pub const` id in a named module, with the ids the document gives |
| §2.1 the entry, 97 bits; empty entries; durations carried as values (1…32,767) | `types::effect::Entry`, `EntryTrait::{new, pack, unpack, is_empty}`, `ENTRY_BOUND`; `EntryAssert::assert_valid` (widths, `MAX_BASE_DURATION`), `assert_legal` (empty = all 0; `MAX_VALUE_DURATION`) |
| §2.2 scaling; ranks 13–15 (FX-0b) | `EntryTrait::value(rank)`, `duration(rank)` (`i32`, truncated toward zero), `MAX_RANK = 15`; checked at ranks 0 and 15 in `assert_legal` |
| §2.3 target, shapes 1–5, filter | `effect::target::{SELF, FOE, ALLY, TILE}`, `effect::shape::{SINGLE … DISC_3}`, `effect::filter::{FOES, ALLIES}` |
| §2.4 guards 0–4 | `effect::guard::{ALWAYS, ABOVE_HALF, BELOW_HALF, IN_STANCE, ENCHANTED}` |
| §3 kinds 1–23; the "class", "reads" and bounds columns | `effect::kind::*`, `KindClass`, `EntryTrait::{class, is_holding, is_hit_modifier}`; the table `reads(kind)`; `EVADE_MELEE` |
| §3.1 damage types; §3.2 conditions 1–9 and their pips | `combat::damage::*`, `combat::condition::*` (`*_PIPS`, `LAST_MVP`) |
| §3.4 skill kinds 1–12; the charge-only deadline | `combat::skill_kind::*` (`SHOUT_ALERT_RANGE`); the existing `types::MAX_CLOCK`, documented on `Effect.deadline` |
| §3.6 kinds 19–23, after the MVP | ids in `effect::kind`, `LAST_MVP = 18`; refused by `assert_legal` (escalation 2) |
| §4 passives 40–65; the §7.2 bounds of their sums | `types::passive::{id, Passive, PassiveTrait, PassiveAssert}`; `MAX_DAMAGE_PERCENT`, `MAX_GUARDED_ARMOR`, `MAX_PENETRATION`, `MAX_ARMOR`, `MAX_KNOCKDOWN_FLAT`, `MAX_DURATION_PERCENT` |
| §5.2 the goblin's activation field | `combat::activation::{LAST_SLOT, RECOVERING, NONE}`; `GoblinTimers.act_slot` and `act_deadline` (holding `A` or `B`) |
| §5.4 hit classes and scopes | `combat::HitClass`; `effect::scope::*` |
| §5.5–§5.13 the rules | Out of scope (CBT-02 to CBT-05). The fields they need exist: `flag::HIT`, `flag::HALVED`, `casts` and `casts_2`, `Effect.{charges, potion, rank}`, `GoblinTimers.effect_{charges, rank}` |
| §5.11 trap objects; a placed trap's `param` | `combat::object::{TERRAIN_TRAP, PLACED_TRAP}`; `combat::Placer`, `PlacerTrait::{param, from_param}` |
| §5.14 the legal carriers (FX-45) | `EntryAssert::assert_carrier(entries, Carrier)`, `Carrier::{Attack, Skill, Potion}`; `SkillAssert::assert_legal`, `ItemAssert::assert_legal` |
| §6 edges | The pipeline's side is the bounds and duration refusals of `assert_legal`. Clamping during play belongs to the rules (CBT-02 to CBT-05) |
| §7.1 the entry in `SKILL` (3) and `ITEM` (1); `MODIFIER`; `ARMOR_SET` | `models::skill::Skill`, `models::item::Item`, `models::modifier::Modifier`, `models::armor_set::ArmorSet` |
| §7.1 functions (`tick`, `execute` …) | Out of scope (CBT-02 to CBT-05, ENG-07) |
| §7.2 `MemberState`, `MemberEffects`, `GoblinState`, `GoblinTimers`, the chunk object | `member::{MemberState.casts_2, flag, Effect}`, `goblin::{GoblinTimers.effect_charges, effect_rank, MAX_ADRENALINE}`, `Placer` |
| §7.2 the lossless snapshot (FX-24); the weapon's identity | `snapshot::{MemberStats.armor_vs, MemberBar.{damage, penetration, quick_cast, armor}, QuickCast, MemberKit.*}`; `MemberStats.weapon` takes `combat::weapon::*` |
| §7.2 signed armor (F-20) and F-21 | `MemberBar.armor: i16`, `MAX_UNGUARDED_ARMOR = 9995`; `MemberKit.{armor_stance, armor_enchanted}: i8` |
| §7.2 registry reads (F-16) | Not encoded: the count stays ENG-05's estimate (D-155); `content::MAX_READ` is unchanged |
| §7.3 the caste sheet | `models::caste::{Caste, Weapon, CasteTrait, WeaponTrait, CasteAssert}`; `MAX_ENERGY = 85`, `MAX_HEALTH_REGEN = 20`, `LAST_TIER = 6` |
| §9 FX-0b, 15, 21, 23, 24, 26, 35, 42, 43, 45 | rank 15; `RECOVERING`; `DISC_2` and `DISC_3` refused; 9 × 6 bits; the repack; skill kind 12 refused; `DISC_1` only in potions; the potion tag; two quick-cast pairs and `casts_2`; `assert_carrier` |

## The layouts, with their bits

- **Entry** (one limb), 97 bits: kind 0–7 · param 8–15 · `v0` 16–31 · `v12` 32–47 (`i16`) · `d0` 48–63 · `d12` 64–79 · charges 80–85 · target 86–87 · shape 88–90 · filter 91 · guard 92–94 · scope 95–96.
- **Passive**, 53 bits: id 0–7 · param 8–15 · guard 16–18 · scope 19–20 · min 21–36 · max 37–52 (`i16`). Two passives fill 106 bits of a limb.
- **`SKILL`**:
  - part 0 low, the header (83 bits): profession 0–7 · attribute 8–15 · kind 16–23 · energy 24–31 · adrenaline 32–39 · activation 40–55 · recharge 56–71 · range 72–79 · target 80–81 · elite 82;
  - part 0 high: entry 1;
  - part 1 low: entry 2; part 1 high: entry 3.
- **`ITEM`**:
  - low limb (72 bits): class 0–7 · region 8–23 · rarity 24–31 · value 32–63 · book index 64–71;
  - high limb (113 bits): entry 128–224 · range 225–232 · strength 233–240.
- **`MODIFIER`**: slot type 0–7 · benefit 128–180 · cost 181–233.
- **`ARMOR_SET`**: five piece bases (`u16`) at 0, 16, 32, 48, 64 · bonuses at 128–180 and 181–233.
- **`CASTE`**, 243 bits; no field straddles a limb, and `LIVE` is set in both parts:
  - part 0 low (109 bits): tier 0–7 · AI profile 8–15 · health % 16–31 · health regeneration + 10 at 32–39 · armor 40–47 · weapon 48–79 (class 4 · damage 16 · type 4 · ticks 4 · range 4) · energy 80–87 · energy regeneration 88–95 · flee 96–103 · rank 104–107 · boss 108;
  - part 0 high (70 bits): armor per damage type 128–181 · loot table 182–197;
  - part 1 low: 4 skills at 0–63.
- **`MemberStats`**:
  - bits 40–47 are freed (the single armor moved to `MemberBar`);
  - `ARMOR_VS` for types 1–2 sits at 48–59; bits 60–63 are free;
  - bits 168–175 are freed (the single penetration moved to `MemberBar`);
  - `ARMOR_VS` for types 3–9 sits at 200–241.
- **`MemberBar`**, high limb (120 of 122 bits): elite 128–135 · damage percents, `i8` × 6 at 136–183 (index `3 g + s`) · penetration, `u8` × 3 at 184–207 · quick-cast, 2 × (attribute 4 + N 8) at 208–231 · unguarded armor `i16` at 232–247.
- **`MemberKit`**, high limb (75 bits): life steal 128–135 · energy on hit 136–143 · condition 144–147 · its percent 148–153 · enchantment % 154–159 · double adrenaline N 160–167 · health bonus 168–183 · armor in a stance `i8` 184–191 · armor enchanted `i8` 192–199 · knock-down 200–201 · halving 202.
- **`MemberState`**: flags bit 3 (hit this tick) and bit 4 (halving spent); `casts_2` at 168–175.
- **`MemberEffects`**, one 56-bit slot: skill 0–15 · charges 16–21 · bit 22 free · potion tag 23 · deadline 24–51 · rank 52–55.
- **`GoblinTimers`**: effect charges 240–245 · effect rank 246–249.

The empty words keep their packed values (`test_empty_timers_packed`): timers pack to `LIVE + 255`, and empty effects and recharges to `LIVE`.

## F-21 (AC-3)

The unguarded armor adds four contributions:
- the weighted rating of the five pieces: each is a `u8` and the weights sum to 1, so at most 255;
- the shield's rating: a `u8`, so at most 255;
- personalisation, which adds 10 % of a rating (design/15 D-48): at most ⌊255 × 10 / 100⌋ = 25 on each of the two;
- at most 37 unguarded `ARMOR` passives, each between −255 and +255.

**Settled: the two 255 limits are the ratings before personalisation.** The bound is 255 + 25 + 255 + 25 + 37 × 255 = **9,995**, below 32,767. The field stays an `i16`.
- The constant is `MAX_UNGUARDED_ARMOR = 9995`, and `pack_bar` refuses anything beyond ±9,995.
- Tests: `test_bar_armor_above_bound_refused` and `test_bar_armor_below_bound_refused`.
- The other reading does not threaten the `i16`: reaching its limit would take a personalisation bonus above 4,000 %.

## Changes to ENG-06's words and their cost (AC-4)

The changes are exactly the ones design/19 §7.2 decided:
- **`MemberState`**: `casts_2` at bits 168–175; flags bits 3 and 4.
- **`MemberEffects` slot**: the rank in the 4 unused deadline bits (52–55); the potion tag in bit 7 of the charges byte; charges in bits 0–5 of that byte.
- **`GoblinTimers`**: 6 bits of charges and 4 bits of rank at 240–249.
- **`GoblinState`**: units only (energy in thirds, adrenaline in quarters up to 252).
- **The snapshot**: repacked as FX-24 decided.

The lines of `instances.cairo` that write these words needed no change, because they write whole words:
- the snapshot, written at create;
- the constants `EMPTY_TIMERS`, `EMPTY_EFFECTS` and `EMPTY_RECHARGES`;
- `MemberStateTrait::entering`, which now also sets `casts_2: 0`.

`maxima` still reads bits 0–23 of `MemberStats`, which did not move. ENG-06's tests pass (49 ephemeral, 128 persistent).

**Cost: 0 new slots.** Gas, from the table above: `create` +0.6 % to +3.3 %, `Hub.enter` +0.4 % to +1.3 %.

## Acceptance criteria

- [x] **AC-1**: see the map above.
- [x] **AC-2**: every record and word round-trips at its bounds and refuses values that are too wide.
  - `test_combat`: the round trips of `Entry`, `Passive`, `Skill`, `Item`, `Modifier`, `ArmorSet`, `Caste`, `Placer` and the signed helper, at both ends and at each field's bit; the 51 `*_refused` tests.
  - `test_packing`: `test_stats_layout`, `test_bar_passives_layout`, `test_kit_passives_layout` and their refusals.
  - `test_layout`: `test_member_layout`, `test_goblin_layout`, `test_combat_fields_layout`, and the effect and goblin refusals.
  - Every record's `pack().len()` equals `parts(KIND)`, asserted in its round-trip test.
- [x] **AC-3**: `MAX_UNGUARDED_ARMOR`, with its two refusal tests.
- [x] **AC-4**: see the section above.
- [x] **AC-5**:
  - D-143 layering: records in `models/` (the struct in `index.cairo`, plus `Impl`, `Assert` and `errors`); value types in `types/`; the signed encoding in `helpers/`.
  - One new free function, `effect::reads`: a constant table, with its reason written above it.
  - CI is green; `gas_budgets.py --check` passes; `class_sizes.py` is ok.

## Deviations from the brief

- **Bit orders design/19 does not fix.** They are my choices, documented in the code and in ENG-01 §3.5:
  - the `SKILL` header is byte-aligned, with `elite` last (bit 82);
  - the placement of `CASTE`'s fields over its four limbs;
  - the order inside `MemberKit`'s high limb;
  - `Placer`'s offsets (design/19 gives only the widths).
- **Id orders design/19 does not fix.** `ITEM` classes 1–8 follow ENG-01's list. `MODIFIER` slot types 1–5 follow the order of the `ItemMods` slots.
- **`ON_ATTACK_CONDITION`.** "`d` or `charges` (one of them non-zero)" is read as *at least one* non-zero. The rules work with both set.
- **Where the checks run.** Packers refuse fields too wide for their bits, and durations above `MAX_BASE_DURATION`, as ENG-01 already does. The semantic checks are in `assert_legal`: they belong to the content pipeline, and the registry does not call them.
- **Legal-carrier checks I derived.** An attack skill cannot hold a `DAMAGE` entry, since it already has its implicit hit. A potion must hold an entry, and any other `ITEM` must not.
- **Budgets.** 34 budgets were raised, each with its `// gas: raised` reason, for your agreement.

## Escalations

1. **`MemberState` flags.** design/19 §7.2 counts three frozen flags, but the code and ENG-01 have two: bit 0 (turned) and bit 1 (instant skill used). I left bit 2 unassigned and put the two new flags on bits 3 and 4, as §7.2 says. Please confirm there is no third flag.
2. **Kinds after the MVP.** Effect kinds 19–23, passive ids 61–65 and skill kind 12 are refused by `assert_legal`: design/19 defines no "reads" column or bounds for them. Please confirm.
3. **`chunk.cairo`.** The doc comment of `Object` does not list kind 9, the placed trap. The file is outside my allowlist. Its 4-bit field already accepts 9.
4. **The snapshot crosses `Instances.create` by Serde.** The larger structs add 21 felts of internal calldata, which is most of the measured +0.2 M to +1.1 M at create. Passing the three packed words instead would change ENG-01 §4.2, which is outside this task.
5. **`ADRENALINE_DECAY` (FX-12).** It has no value in design/19. I did not define it; the rule that uses it belongs to CBT-02.
6. **Pipeline checks without the data they need.** "Health runes of the same kind do not add up" needs a rune kind, which the passive layout does not have. "`DAMAGE_TYPE` only on the weapon's slot type" needs to know which slot type that is.

## Open questions

- The `SKILL` header's `target` reuses the entry's addressing ids. `range` is stored as a number of tiles, not as design/03's named ranges (touch, adjacent, nearby, area, ranged). If content needs the named ranges, they need ids.

## Fix loop 1

The `[GPT-6-Astra]` audit of PR 165 at `b5bce2d` returned **FAIL**, with four majors and two minors, all in the content validators. It judged the packing, record sizes, signed encodings and F-21 sound.

I merged origin/main first; it brought no change to `contracts/`. The fix is commit `2d9990e`. CI is green on it (`cairo (contracts)`, `tooling`, `client` and every spike pass; `indexer-node` skipped).

### The findings and their fixes

| # | Finding | Fix |
|---|---|---|
| CBT-1 (major) | Passive legality did not check its parameter's enumeration or range, nor its scope | See **CBT-1** below |
| CBT-2 (major) | Modifier and armor-set validators omitted §7.2's source restrictions, so a snapshot sum could overflow (216 in an `i8`) | See **CBT-2** below |
| CBT-3 (major) | An attack skill's hit modifiers skipped the filter check | `assert_carrier` now requires an attack's `ATTACK_BONUS` and `HIT_PENETRATION` to have filter `FOES`: the implicit hit is on the attacked foe |
| CBT-4 (major) | A preparation could reach neither duration nor charges at a legal rank | Without charges, `ON_ATTACK_CONDITION` needs `duration(0) > 0` and `duration(15) > 0`. The line is monotonic, so every rank 0–15 is then positive |
| CBT-5 (minor) | A non-potion `ITEM` checked only its entry's kind | `ItemAssert` now runs `Entry::assert_legal` in both branches, so every field of an empty entry must be 0 |
| CBT-6 (minor) | New free functions and inline checks | See **CBT-6** below |

**CBT-1.** `PassiveAssert::assert_legal` now checks each passive's parameter, scope and value:
- **Parameter:**
  - a damage type 1–9 for `ARMOR_VS` and `DAMAGE_TYPE`;
  - a condition 1–9 for `CONDITION_DURATION`;
  - an attribute below 16 for `QUICK_CAST_EVERY_N` and `ATTRIBUTE` (the snapshot's 4-bit field);
  - a profession 1–6 for `ENERGY_COST`;
  - 0 for every other passive.
- **Scope:** 0–3 on `DAMAGE_PERCENT` and `PENETRATION`, refused here rather than only by the packer.
- **Value**, within the field the snapshot sums it into:
  - `ARMOR_VS` 0–63;
  - `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT` 0–255;
  - `RATING_PERCENT` 0–10 (F-21's assumption);
  - `DAMAGE_TYPE` and `HALVE_FIRST_HEAVY_HIT` exactly 0;
  - the bounds that were already there.
- Width checks moved to `PassiveAssert::assert_valid`.

**CBT-2.** A new `types::passive::Source` enum lists the five modifier slot types plus the set bonus. `PassiveTrait::allows(source)` states where §7.2 lets each passive be held:
- `DAMAGE_PERCENT` and `PENETRATION`: prefix, suffix, inscription, or a set bonus ("only the held items' slot types and set bonuses");
- guarded `ARMOR`: an insignia or a set bonus;
- `QUICK_CAST_EVERY_N`: the inscription only (the slot type is my choice, escalation B);
- `CONDITION_DURATION`: the prefix only;
- `DAMAGE_TYPE`: a weapon's slot type (prefix, suffix or inscription), never an armor slot or a set bonus;
- `KNOCKDOWN_FLAT`: a set bonus only;
- `BASE_DAMAGE_PERCENT` and `RATING_PERCENT`: no record at all (they come from personalisation);
- every other passive: any source.

The validators that use it:
- `ModifierAssert` checks the benefit **and the cost** with `assert_source` against the slot type. It also refuses a statistic the snapshot counts (`is_counted`) when a modifier holds it as both benefit and cost, because that would count one source twice.
- `ArmorSetAssert` checks both bonuses as set bonuses and keeps their knock-down sum at 3 or less. Only one set can reach 3 of the 5 pieces, so its two bonuses are the only set bonuses held.

`test_snapshot_capacity_from_sources` derives each capacity from `allows` and design/15's source counts per adventurer (1 prefix, 2 suffixes, 2 inscriptions, 5 insignias, 5 runes, 2 set bonuses):
- `DAMAGE_PERCENT`, `PENETRATION` and guarded `ARMOR`: 7 sources each, so 126 fits an `i8` and 252 fits a `u8`;
- `QUICK_CAST_EVERY_N`: 2 sources, matching the 2 pairs;
- `CONDITION_DURATION`: 1 source;
- personalisation's percents: 0 sources.

**CBT-6.**
- `pack_quick_cast` and `unpack_quick_cast` became `QuickCastTrait::{pack, unpack}`, with `QuickCastAssert`.
- The new inline width checks moved into `Assert` impls: `PassiveAssert::assert_valid`, `WeaponAssert`, `MemberStatsAssert`, `MemberBarAssert`, `MemberKitAssert`, `EffectAssert` (ephemeral) and `GoblinTimersAssert` (ephemeral).
- **Correction to the report above:** it said `reads` was the only new free function. That was wrong: `pack_quick_cast` and `unpack_quick_cast` were two more. Both are now scoped in `QuickCastTrait`, so `reads` (a constant table by kind, with its written reason) is now the only new free function.

### Evidence that b5bce2d accepted each refused case

I restored `b5bce2d`'s `contracts/logic/src` in the worktree and ran each regression case as a plain test that should pass. **All 37 passed**, so the old code accepted every one:

```
Tests: 37 passed, 0 failed, 0 ignored, 128 filtered out
```

The cases were:
- **CBT-1:** `ARMOR_VS` types 255 and 0, quick-cast attribute 16, `DAMAGE_TYPE` 10, condition 10, profession 7, a parameter on `MAX_HEALTH`, scope 4 on both scoped passives, `ARMOR_VS` 64 and −1, life steal 256, rating 11, `DAMAGE_TYPE` with a value, and a modifier holding `ARMOR_VS` 255.
- **CBT-2:** `DAMAGE_PERCENT` on an insignia and on a rune, penetration on an insignia, guarded armor on a prefix, quick-cast on a rune, a suffix and a set bonus, condition duration on a suffix and a set bonus, `DAMAGE_TYPE` on a set bonus and an insignia, knock-down on a modifier, rating on a modifier, a forbidden cost, `DAMAGE_PERCENT` as both benefit and cost, and a set with 2 + 2 knock-down.
- **CBT-3:** `ATTACK_BONUS` and `HIT_PENETRATION` with `ALLIES`.
- **CBT-4:** preparations with durations (5, 1), (1, 0) and (0, 5) and no charges.
- **CBT-5:** an ingredient with a stray field.

I then restored `HEAD` and deleted the temporary test; the tree was clean afterwards. At `2d9990e` each of these is a `*_refused` test in `contracts/logic/tests/test_validators.cairo` (49 tests). The file also holds the accepted boundaries:
- every domain's ends;
- every allowed source;
- "+15 % damage, −5 energy" (a counted benefit with an uncounted cost);
- *Hob-breaker*'s 1 + 2 knock-down;
- preparations of (4, 1), (1, 1), (1, 34,951) (exactly 43,688 at rank 15), charges without a duration, and (5, 1) with charges;
- an attack's modifiers with `FOES`;
- an ingredient with an empty entry.

### Commands run

```
$ git merge origin/main                           (no change under contracts/)
$ scarb --manifest-path contracts/Scarb.toml build  → no error, no warning
$ cd contracts/logic && snforge test               → Tests: 173 passed, 0 failed
$ cd contracts/ephemeral && snforge test           → Tests: 49 passed, 0 failed
$ cd contracts/persistent && snforge test          → Tests: 128 passed, 0 failed
$ snforge test | python3 ../tools/set_budgets.py /dev/stdin   (logic) → set: 172 missing: []
$ scarb fmt; python3 scripts/gas_budgets.py; python3 scripts/gas_budgets.py --check
gas check: 350 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ (b5bce2d's logic/src restored) snforge test test_old → Tests: 37 passed, 0 failed
$ gh run list … → ci success, tooling success, headSha 2d9990e
```

### Cost

- **Nothing on main was raised in this loop.** `gas_budgets.py --report` lists the same 34 raised rows as before; ephemeral and persistent measures are unchanged.
- **New tests:** the 49 in `test_validators`. They mostly sit at the 15,520 panic floor or the 13,720 folded floor. The larger ones:
  - `test_attack_modifiers_on_foes_accepted`: 390,170;
  - `test_snapshot_capacity_from_sources`: 173,230;
  - `test_attack_*_on_allies_refused`: about 89,800 each.
- **Budgets changed:** 16 tests in `test_combat` that are themselves new in this PR (not yet on main), because the carrier checks now also check filters and sources. For example, `test_legal_carriers` went from 1,432,720 to 1,641,630 and `test_carrier_gap_refused` from 205,490 to 231,560.
- **Play is untouched:** the validators are the content pipeline's; `play` never calls them.

### The escalations after the audit

1. **Third member flag.** The audit calls it a documentation discrepancy, not a defect of this PR. **Closed here.** For the project manager: correct design/19 §7.2's count of frozen flags from 3 to 2.
2. **Kinds and passives after the MVP refused.** The audit calls this a justified exclusion. **Closed.**
3. **`chunk.cairo`'s comment on kind 9.** A documentation omission outside my allowlist. **Handed off** to the owner of the chunk model (ENG-05 or ENG-06). There is no layout defect.
4. **The snapshot's Serde cost at create** (+21 felts). A real optimisation question outside this brief. **Kept open.**
   - (a) Keep the structs.
   - (b) Pass the three packed words (3 felts instead of 67) through a changed `Instances.create` interface (ENG-01 §4.2).
   - **Recommendation:** (b), decided with ENG-07 once `play` is measured, because it changes a frozen interface.
5. **`ADRENALINE_DECAY` (FX-12) has no value.** A real open design or balance question. **Kept open; this is AC-1's one explicit exception.**
   - (a) BAL-01 sets it.
   - (b) CBT-02 ships a placeholder with a test that pins it.
   - **Recommendation:** (a) before CBT-02 implements decay, with 1 quarter per tick (a strike every 4 ticks out of combat) as a starting value BAL-01 can change.
6. **Rune kind and `DAMAGE_TYPE`'s slot type.** The audit says these are not a waiver for CBT-2. **What design/19 states explicitly is now enforced** (CBT-2 above). Two mappings the documents leave open remain, with my choices:
   - A. **"Health runes of the same kind do not add up"** (design/15, FX-43). Checking this needs to know which modifiers are "the same kind".
     - (a) The same `MODIFIER` id: no new field, and the flattening at entry keeps the highest per id.
     - (b) A rune family in the record.
     - **Recommendation:** (a). It fits the frozen layout and it is the flattening's rule (ENG-06 or DES-06), not the validator's.
   - B. **Which slot type holds `DAMAGE_TYPE` and `QUICK_CAST_EVERY_N`.** The document says "the only slot type the pipeline gives it" for both, and names neither.
     - I enforce `QUICK_CAST_EVERY_N` on the **inscription**: the only slot type that the weapon and the off-hand each carry exactly once, which is what keeps the snapshot's 2 pairs sufficient. A suffix would also work.
     - I enforce `DAMAGE_TYPE` on **any weapon slot type** (prefix, suffix or inscription). That is capacity-safe because it is never summed; which of the three is DES-06's choice.
     - **Recommendation:** DES-06 confirms both.

### New open questions from this loop (the validators' capacity edges)

- **Attribute ids.** The snapshot's quick-cast attribute is 4 bits, so I bound it and `ATTRIBUTE`'s parameter to 0–15. But design/03 lists 27 attributes across six professions, and the `SKILL` header's attribute is 8 bits.
  - (a) The attribute is an index into the adventurer's list (the build's 9 ranks).
  - (b) It is a global id, and the pair needs more bits.
  - **Recommendation:** (a), which is what the 4-bit field implies. Confirm in DES-06 and make the `SKILL` header use the same space.
- **Sums design/19 gives no capacity for.**
  - `ENCHANT_DURATION` (6 bits) and the on-hit sums (`u8`) have no source restriction, so four +20 % enchantment modifiers would pass 63.
  - `MemberKit.health_bonus` is a `u16`, yet design/15's runes carry negative health costs.
  - **Recommendation:** the flattening saturates `ENCHANT_DURATION` at 63. This is lossless in effect, since `effective_duration` caps percents at 50. DES-06 or ENG-06 decides how negative health bonuses are stored. I did not invent a source rule for these.
- **Professions 1–6 for `ENERGY_COST`.** These are design/03's six. Restrict to the MVP's three if content must not name the others yet.

## Fix loop 2

The `[GPT-6-Astra]` re-audit of PR 165 at `2d9990e` returned **FAIL**:
- CBT-3, CBT-4 and CBT-5 are resolved.
- CBT-1, CBT-2 and CBT-6 are partial.
- Two new majors: CBT-7 (unsettled mappings implemented as rules) and CBT-8 (the blanket same-id ban).

origin/main was already merged, so there was nothing new to take. The fix is commit `eda7bc5`. CI is green on it (`ci` and `tooling` both success; `cairo (contracts)` and every spike pass; `indexer-node` skipped).

**The principle this loop:** a validator refuses only what design/19 states, or what a sum that §7.2 bounds by counting its sources needs. Where the document leaves a set undefined, the code no longer picks a set. It either accepts the widest set the document allows (with a content-wide check where the document says "one slot type"), or it accepts the content and the question is escalated below.

### Findings and fixes

| # | Re-audit status | This loop |
|---|---|---|
| CBT-1 | partial | See **CBT-1** below |
| CBT-2 | partial | See **CBT-2** below |
| CBT-6 | partial | See **CBT-6** below |
| CBT-7 | new major | See **CBT-7** below |
| CBT-8 | new major | See **CBT-8** below |
| CBT-3, 4, 5 | resolved | Unchanged |

**CBT-1: bounds that were not the documented rule are gone.**
- Removed: the per-passive caps `ARMOR_VS ≤ 63`, `KNOCKDOWN_FLAT ≤ 3`, the duration percents `≤ 63`, `LIFE_STEAL_ON_HIT`/`ENERGY_ON_HIT ≤ 255` and `RATING_PERCENT ≤ 10`, and the attribute `< 16`.
- A sum the snapshot saturates or caps no longer bounds a single passive:
  - `ARMOR_VS` saturates at 63 (FX-23);
  - `KNOCKDOWN_FLAT` and the duration percents are capped at use by ENG-01 §3.1 (3 ticks; 50 %).
- What stays is what §4, §7.2 and ENG-01 state:
  - ±18, ±255 and 0…36;
  - `ADRENALINE_EVERY_N` 1…255;
  - `QUICK_CAST_EVERY_N` N 0…255 (8 bits);
  - non-negative where §4 writes "+" (`ARMOR_VS` "+ armor", `KNOCKDOWN_FLAT` "+ ticks") or ENG-01 §3.1 speaks of "bonuses" (duration percents);
  - 0 for a passive without a value.

**CBT-2: the snapshot-capacity guarantee now holds for every sum a document bounds.** The flattening proof is under CBT-7 below. The sums no document gives a capacity rule for are **accepted and escalated** (G below); I no longer claim them as guaranteed. ENG-01 §3.5's sentence is corrected to say exactly this.

**CBT-6.**
- Slot validation is back in `ModifierAssert::assert_slot`. `ModifierImpl::source` now only maps a slot to `Option<Source>`.
- The ephemeral `EffectAssert` and `GoblinTimersAssert` use named errors: `member::errors::{CHARGES, RANK, BELT_SLOT}` and `goblin::errors::{CHARGES, RANK}`. The strings are unchanged.

**CBT-7: no unsettled mapping remains a rule.**
- `QUICK_CAST_EVERY_N` is no longer inscription-only. It is accepted on the slot types of the weapon and the off-hand ("held only on the weapon and the off-hand"): prefix, suffix, inscription.
- `ModifierAssert::assert_catalogue(modifiers)` enforces "the pipeline gives it one slot type" across the whole content, **without choosing which**. With any of the three, at most 2 pairs are held.
- `DAMAGE_TYPE` is also checked by `assert_catalogue`, so all its modifiers share one weapon slot type. The audit's fire prefix plus cold suffix is refused. Which slot type, and the weapon-only rule if it is one the off-hand also has, are escalated (C).
- `ATTRIBUTE` and the quick-cast attribute accept any `u8`; the attribute id space is escalated (A).
- **The flattening proof** is `logic/tests/test_capacity.cairo`. It builds the worst loadouts from records the validators accept:
  - each modifier passes `assert_catalogue` and the set passes `assert_legal`;
  - they are placed as design/15 places them: 1 prefix, 2 suffixes, 2 inscriptions, 5 insignias, 5 runes, and the set's 2 bonuses;
  - it flattens them into `MemberStats`, `MemberBar` and `MemberKit`, where a sum that does not fit panics in its conversion, then packs and unpacks each word.
- The three proof tests:
  - `test_flatten_damage_extremes`: damage above half is +126 on every scope (7 sources); held-item costs give −90 always; the insignias hold the audit's CBT-8 pair (stance +90, enchanted −90); unguarded armor with ratings is 1,835.
  - `test_flatten_penetration_and_armor_extremes`: penetration is 180, then 252 with the set's bonuses (7 sources); guarded armor is −126 (7 sources); unguarded armor is 15 × −255 = −3,825.
  - `test_flatten_saturated_extremes`: every saturated or capped statistic at 32,767 on every slot and bonus gives `ARMOR_VS` 63, knock-down 3, enchantment 50, one condition at 50, and two quick-cast pairs.
- The oracle's saturations are only the stated ones (FX-23, ENG-01 §3.1). It is a test oracle, not the snapshot builder, which is ENG-06's with design/15's formulas.

**CBT-8: the blanket same-id ban is replaced by `PassiveTrait::shares_sum`.** A modifier's benefit and cost are refused only when they would add to one sum that §7.2 bounds by counting its sources, because one slot is one source:
- `DAMAGE_PERCENT`: the same guard and overlapping scopes (equal, or either `ALL`);
- `PENETRATION`: overlapping scopes;
- `ARMOR`: the same guard. Unguarded armor counts too, from "at most 5 per item", one per slot;
- `QUICK_CAST_EVERY_N`, `CONDITION_DURATION`, `DAMAGE_TYPE`: any two.

Saturated or capped statistics may appear twice. The audit's insignia (`ARMOR +10 IN_STANCE`, `ARMOR −5 ENCHANTED`) is accepted, and it is also part of the damage flattening test.

**Also removed as unstated:**
- the set-level knock-down sum and `KNOCKDOWN_FLAT`'s set-only source: the use-time cap makes the sum representable;
- `BASE_DAMAGE_PERCENT`'s record ban: only `RATING_PERCENT` stays off records, because §7.2's armor bound counts personalisation apart from the 37 `ARMOR` passives.

### Tests at each finding's boundary

`logic/tests/test_capacity.cairo` has 23 tests, 14 of them refusals:

| Finding | Accepted | Refused |
|---|---|---|
| CBT-1 | `ARMOR_VS` 64 and 32,767, knock-down 4, enchantment and condition percents 64, `ARMOR_VS` 0 | knock-down −1, enchantment −1, `ADRENALINE_EVERY_N` 0 |
| CBT-2 | a set of two `LIFE_STEAL_ON_HIT` 255, and a life steal of 300: sums with no capacity rule, accepted and escalated | — |
| CBT-6 | `source` maps 0 and 6 to `None` and 5 to `Some` | slots 0 and 6 by `assert_legal` |
| CBT-7 | each of prefix, suffix and inscription as the one slot type for two quick-casts and two damage types; attributes 16 and 255 | quick-cast on suffix plus inscription; `DAMAGE_TYPE` on prefix plus suffix (the audit's case); quick-cast on an insignia |
| CBT-8 | stance plus enchanted armor (the audit's case); stance plus unguarded; damage weapon plus spell; damage on another guard; penetration weapon plus spell; `ARMOR_VS` twice; knock-down twice | damage `ALL` plus weapon on one guard; penetration `ALL` plus spell; unguarded armor twice; stance armor twice; two conditions; two quick-casts |
| CBT-7 flattening | the three worst-loadout tests above | a sum that does not fit panics in the oracle |

`test_validators.cairo` drops the 8 fix-loop-1 tests that encoded the removed rules, leaving 37 tests. One correction: the loop-1 section of this report said that file had 49 tests; it had 45.

### Commands run

```
$ git merge origin/main                               → Already up to date.
$ scarb --manifest-path contracts/Scarb.toml build     → no error, no warning
$ cd contracts/logic && snforge test                   → Tests: 188 passed, 0 failed
$ snforge test | python3 ../tools/set_budgets.py /dev/stdin → set: 187 missing: []
$ scarb fmt; python3 scripts/gas_budgets.py; python3 scripts/gas_budgets.py --check
gas check: 365 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
  (the workspace run includes ephemeral and persistent: all pass)
$ gh run list … → ci success, tooling success, headSha eda7bc5
```

### Cost

- **Nothing on main was raised.** The budgets that changed belong to tests new in this PR.
- **The flattening tests are the heaviest new ones**, a few million l2 gas each; their exact figures are in `contracts/logic/GAS.md`.
- **Play is untouched:** the validators and the oracle are the content pipeline's and the tests'.

### Escalations after fix loop 2

Each has its question, options and my recommendation. None is decided in code.

- **A. The attribute id space.** The quick-cast pair stores an attribute in 4 bits, `ATTRIBUTE`'s parameter and the `SKILL` header in 8, and design/03 lists 27 attributes.
  - (a) The attribute is an index into the adventurer's list (the build's 9 ranks, fits 4 bits). The flattening maps content ids to it.
  - (b) It is a global id, and the pair needs 8 bits (the `MemberBar` high limb has 2 free bits; the `MemberKit` high limb has 47).
  - **Recommendation:** (b) a global id in content, with (a)'s index in the snapshot. The mapping lives in the flattening (ENG-06), and no content record needs a new bound.
- **B. Which slot type is "the one" for `QUICK_CAST_EVERY_N`.** The code accepts any single one (`assert_catalogue`).
  - (a) prefix: 1 held;
  - (b) suffix: 2 held;
  - (c) inscription: 2 held.
  - **Recommendation:** (c), which is on "everything held", and DES-06 writes it. Content chooses it by construction; nothing in code changes.
- **C. `DAMAGE_TYPE`'s slot type, and "on the weapon".** The code accepts one weapon slot type for the whole content.
  - (a) prefix: weapon-only by the slot, so nothing more is needed;
  - (b) suffix or inscription: the off-hand has them too, so identification (ENG, Fate `IDENTIFY`) must refuse it on an off-hand, which needs the item's class.
  - **Recommendation:** (a).
- **D. Health-rune identity** ("runes of the same kind do not add up").
  - (a) The same `MODIFIER` id, and the flattening keeps the highest per id;
  - (b) a rune family field.
  - **Recommendation:** (a): no field, and it is the flattening's rule.
- **E. `ADRENALINE_DECAY`'s value** (FX-12). This is AC-1's one explicit exception.
  - (a) BAL-01 sets it before CBT-02;
  - (b) CBT-02 ships a pinned placeholder.
  - **Recommendation:** (a).
- **F. The snapshot's Serde at create.** The audit's correction: three packed words would replace the **63** felts of stats, bar and kit; the 4 belt-count felts would still travel.
  - (a) Keep the structs;
  - (b) Pack the words, with the belt counts as a fourth word or folded into `MemberState`'s belt, which ENG-06 already writes.
  - **Recommendation:** (b), decided with ENG-07.
- **G. Sums no document gives a capacity rule for.** Each is accepted as content today:
  - `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT` into `u8` (a set's two 255 bonuses sum to 510);
  - `MAX_HEALTH` into the unsigned `u16` `health_bonus`, although runes carry negative health costs;
  - `MAX_ENERGY` and `ENERGY_REGEN` into `u8` stats, although their costs are negative;
  - `HEALTH_REGEN` into the stored + 10 field (0–20): §5.8's clamp to ±10 pips applies after effects and conditions, so clamping the snapshot is not lossless;
  - `ATTRIBUTE` into 4-bit ranks: design/03 says "about 16 with everything", but ranks stop at 15 (§2.2);
  - `ENERGY_COST`: no snapshot field at all;
  - `BASE_DAMAGE_PERCENT` into `weapon_damage: u8`.

  The options:
  - (a) Source-count bounds per passive, like §7.2's `DAMAGE_PERCENT` (for example life steal ≤ 18 × …);
  - (b) Saturate where the rule at use makes it lossless;
  - (c) Widen or sign the field in the free bits (the `MemberKit` high limb has 47 free bits; `MemberStats` has bits 40–47, 60–63 and 168–175 free).

  **Recommendation:** DES-06 gives each statistic a per-source bound, as §7.2 did for damage (a), with (c) where a sum can be negative (health, energy, regeneration: signed fields). Then CBT-01's validators and the flattening proof extend to them. Until then, they are accepted and not claimed as guaranteed.
- **H. Professions 1–6 for `ENERGY_COST`.** These are design/03's six.
  - (a) Keep six;
  - (b) Only the MVP's three.
  - **Recommendation:** (a): the ids are frozen, and content decides which it names.

**Closed or handed off, per the audit:** the third member flag (a documentation handoff for design/19 §7.2), the post-MVP kinds (a justified exclusion), and `chunk.cairo`'s kind-9 comment (handed off).

## Fix loop 3

The `[GPT-6-Astra]` audit at `eda7bc5` resolved CBT-3 to CBT-7 and left CBT-1, CBT-2 and CBT-8 partial. origin/main was already merged. The fix is commit `a50772f`. CI is green on it (`ci` and `tooling` both success on `a50772f`; `cairo (contracts)`, `client` and every spike pass; `indexer-node` skipped).

### CBT-1: `ENERGY_COST`'s sign

design/19 states it:
- §4, line 266: "`ENERGY_COST` | a profession; **− energy**";
- §5.3, line 366: "energy after **reductions** (`ENERGY_COST`, …)".

I check it as the signed delta the table writes: `min ≥ −32,768` and `max ≤ 0`. This is the same reading as "+ armor" → non-negative for `ARMOR_VS`.

Tests in `test_capacity.cairo`:
- accepted: −1, 0, and −32,768…0;
- refused: +1, and a range −1…+1 crossing zero.

Whether content should instead carry a positive magnitude is an encoding question, not a gap in design/19. It is escalation I, for the project manager, in case DES-06 prefers magnitudes.

### CBT-2: overlapping scopes

design/19 §5.4, line 380: "`WEAPON` | a weapon attack; an attack skill (**then also `ATTACK_SKILL` for scopes**)". §7.2 keeps each sum "per guard × class (plain weapon, attack skill, spell)". So:
- the **attack-skill** sum takes `WEAPON`, `ATTACK_SKILL` and `ALL`;
- the plain-weapon sum takes `WEAPON` and `ALL`;
- the spell sum takes `SPELL` and `ALL`.

**The bound now holds for overlapping scopes, without new restrictions:**
- `PassiveTrait::applies_to(class)` encodes §5.4.
- `PassiveAssert::assert_contributions` requires the two passives of one source (a modifier's benefit and cost) to add to each counted sum no more than one passive may:
  - `DAMAGE_PERCENT`: −18…+18, per guard and class;
  - `PENETRATION`: 0…36, per class;
  - guarded `ARMOR`: −18…+18, per guard.
- Each of §7.2's 7 sources then adds at most 18 (or 36), so 7 × 18 = 126 and 7 × 36 = 252 hold whatever the scopes.
- This replaces loop 2's `shares_sum`, which both treated `WEAPON` and `ATTACK_SKILL` as disjoint (the audit's defect) and refused pairs whose total stays within the bound (too narrow).

**The oracle** now applies the same §5.4 classes, independently of the validator (`applies_to` in `Fixture::sum`).

New tests in `test_capacity.cairo`:
- `test_flatten_weapon_scope_on_attack_skills`: one `WEAPON +18` flattens to `[18, 18, 0]` (the audit's single-passive example).
- `test_flatten_worst_scope_overlap`: `WEAPON` and `ATTACK_SKILL` in both orderings on every held-item slot at the most a source may add (9 + 9; 18 + 18 of penetration), with the set's two `ALL` bonuses:
  - damage per class is `[81, 126, 36]` (above half);
  - penetration is `[162, 252, 72]`, the attack-skill sums reaching the bound exactly.
- `test_penetration_weapon_and_attack_skill_refused` and `test_penetration_attack_skill_and_weapon_refused`: the audit's case, 36 + 36 = 72 on an attack skill's hit, in both orderings.
- `test_damage_weapon_and_attack_skill_over_18_refused`: 18 + 1.
- `test_scope_overlap_within_bound_accepted`: `WEAPON +10` with `ATTACK_SKILL −5` gives 5; `WEAPON 18` with `SPELL 18` add to no common class; penetration 18 + 18 is 36.
- Loop 2's refusals now sit at the bound: `ALL 10 + WEAPON 10` is 20 > 18, `ALL 30 + SPELL 10` is 40 > 36, stance `10 + 10` is 20 > 18. The loop-2 values (10 − 5, 4 + 1, 10 − 2) are within the bound and now accepted.

The sums no document bounds stay escalated (G below), and are not claimed.

### CBT-8: the unguarded-armor pair

design/19 has **no line** that limits unguarded `ARMOR` to one passive per slot. §7.2 (line 710) bounds the unguarded armor by its **total**: "each bounded … to [−255, +255], at most 5 per item on 7 items plus 2 set bonuses = 37", giving ±9,995 (F-21).

So I removed the restriction:
- The audit's rune (`ARMOR +5`, `ARMOR −2`) is accepted, as is `+255` twice, in `test_unguarded_armor_twice_accepted`.
- `test_flatten_unguarded_armor_extremes` shows that two unguarded passives on every slot, plus the set's two bonuses, stay far inside the bound. That is 32 contributions: 32 × 255 + 560 = **8,720** and −8,160, against ±9,995. The per-item "5" of §7.2 counts modifier slots, and a weapon's three slots with two passives each are 6 contributions. The total bound holds with room, so no per-item rule is needed to keep the field.
- `conflicts` keeps refusing only what a single-valued field cannot hold:
  - two quick-casts (a source is one of the 2 pairs);
  - two `CONDITION_DURATION` **of different conditions** (loop 2 refused any two);
  - two `DAMAGE_TYPE` **of different types** (the same, loosened).

### Commands run

```
$ git merge origin/main                           → Already up to date.
$ scarb --manifest-path contracts/Scarb.toml build → no error, no warning
$ cd contracts/logic && snforge test               → first run: 190 passed, 8 failed (budgets only:
                                                     "Test cost exceeded the available gas")
$ snforge test | python3 ../tools/set_budgets.py /dev/stdin → set: 197 missing: []
$ snforge test                                     → Tests: 198 passed, 0 failed
$ scarb fmt; python3 scripts/gas_budgets.py; python3 scripts/gas_budgets.py --check
gas check: 375 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
```

### Cost

- **No budget of main was raised.** The budgets that changed belong to tests new in this PR: the per-class contribution check (15 contribution sums per modifier) costs more in `test_combat`'s modifier tests and in `test_capacity`.
- **Play is untouched:** these are the content pipeline's checks.

## For the project manager

After three fix loops, these escalations remain open. Each has its options, my recommendation, and the view of `[GPT-6-Astra]`'s last audit (at `eda7bc5`). None is decided in code.

| # | Question | Options | Recommendation | Auditor's view |
|---|---|---|---|---|
| A | **The attribute id space.** The quick-cast pair stores 4 bits; `ATTRIBUTE`'s param and the `SKILL` header store 8; design/03 lists 27 attributes. The code accepts any `u8` | (a) an index into the adventurer's 9 attributes; (b) a global id in content, mapped to the index when the snapshot is flattened | (b): global in content, the index in the snapshot, the mapping in ENG-06's flattening | "Legitimate question"; attribute identity and mapping remain open. CBT-7's arbitrary choice is removed |
| B | **Which slot type is "the one" for `QUICK_CAST_EVERY_N`.** The code enforces one slot type across the content (`assert_catalogue`), whichever it is | (a) prefix: 1 held; (b) suffix: 2; (c) inscription: 2 | (c), written by DES-06 | Legitimate; "the catalogue constraint [is] implemented", the choice left open |
| C | **`DAMAGE_TYPE`'s slot type, and "on the weapon"** | (a) prefix: weapon-only by the slot; (b) suffix or inscription, with identification refusing it on an off-hand (this needs the item's class) | (a) | "The weapon-only rule still needs enforcement at an interface with item context" |
| D | **Health-rune identity** ("do not add up") | (a) the same `MODIFIER` id, the highest kept at flattening; (b) a rune-family field | (a) | Legitimate mapping question; the grouping is a recommendation, not a settled rule |
| E | **`ADRENALINE_DECAY`'s value** (FX-12). This is AC-1's only exception | (a) BAL-01 sets it before CBT-02; (b) CBT-02 ships a pinned placeholder | (a) | A genuine open question; no value encoded, correctly |
| F | **The snapshot's Serde at create.** It is +21 felts; packing would replace 63 felts, and the 4 belt-count felts stay | (a) keep the structs; (b) packed words, the belt counts in a fourth word or in `MemberState`'s belt | (b), decided with ENG-07 when `play` is measured | "A legitimate optimisation question", with the 63-felt correction |
| G | **Sums no document gives a capacity rule for.** Life steal and energy on hit (`u8`: a set's two 255 bonuses make 510); `MAX_HEALTH` into an unsigned `u16` although runes have negative costs; `MAX_ENERGY` and `ENERGY_REGEN` into `u8` with negative costs; `HEALTH_REGEN` (§5.8 clamps after effects, so clamping the snapshot is lossy); attribute ranks above 15 ("about 16 with everything"); `ENERGY_COST` (no snapshot field); `BASE_DAMAGE_PERCENT` into `weapon_damage: u8`. All are accepted as content, not claimed | (a) per-source value bounds, as §7.2 gives for damage; (b) saturate where the rule at use is lossless; (c) widen or sign fields in free bits (`MemberKit` has 47 free high bits; `MemberStats` has bits 40–47, 60–63 and 168–175) | DES-06 gives each statistic a per-source bound (a), with signed fields (c) where a sum can be negative; CBT-01's validators and the flattening proof then extend to them | "Correctly exposes unresolved capacity requirements … appropriate; it does not prove that every accepted collection fits" |
| H | **Professions for `ENERGY_COST`** | (a) design/03's six (1–6); (b) the MVP's three | (a) | "Not a reason to invent a narrower enumeration": agrees with (a) |
| I | **`ENERGY_COST`'s encoding.** Checked as design/19 writes it: "− energy", a value of 0 or below | (a) a signed delta, as now; (b) a positive magnitude of reduction (the validator then flips) | (a): it is the table's text and matches `MAX_ENERGY`'s signed "±" | Its CBT-1 finding asks either for this check or for the magnitude question to be escalated; both are done |

**Documentation handoffs** (not open questions; the auditor agrees with each):
- design/19 §7.2 counts three frozen member flags where ENG-01 and the code have two. Correct the count.
- `chunk.cairo`'s `Object` comment does not list kind 9 (the placed trap). This is for the owner of the chunk model. There is no layout defect.
- The post-MVP kinds (19–23, passives 61–65, skill kind 12) are refused by the validators. The auditor calls this a justified exclusion.

**One dependency to carry into CBT-02 and ENG-06:** the flattening proof in `test_capacity.cairo` is a test oracle. The snapshot builder that ENG-06 writes must use the same classes (§5.4) and saturations (FX-23, ENG-01 §3.1), and it inherits G's open sums.
