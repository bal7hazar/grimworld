# [Opus 5.5] CBT-08a — `set_build`: the bar, the attributes, the belt and the equipment

## Summary

`Hub.set_build(adventurer_id, build, belt, equipped)` is now implemented, as ENG-01 §4.3 froze it. It is one call, in a hub, by the owner only. Every rule is checked before anything is written. The three words are stored as sent plus `LIVE`, which is 0 new and 3 overwritten keys, as in §9.3. The model this session ran as is Opus 5.5 (its system prompt), which is also the model the brief names.

Every rule of design/03 and design/15 that `set_build` enforces is a refusal, each with a test at its boundary (the table below). The node probe (`contracts/tools/lifecycle_probe.py`) now runs the belt's worst case of D-148: `set_build` with four potions on four pack pages, `enter` debiting them, and `leave` and `travel_back` crediting them back.

Pull request: https://github.com/bal7hazar/grimworld/pull/170. Head `342b57a`; every CI check passed (`indexer-node` skipped by its filter).

**Gas (escalated).**
- `set_build`'s worst case is about 3.2 times §10's estimate: 4.41 M net (E) against 1.37 M.
- The belt's worst case is over D-148's targets: `enter` +27.6 %, `leave` +30.8 %, `travel_back` +22.0 %.
- Both are beyond the orchestrator's +10 %, so they go to the project manager (cost-budget.md §2). No budget was raised.

## Files changed

- `contracts/logic/src/models/base.cairo` (new): the `BASE` record's model, with slot and hands only (escalation 3); its constructor, its checks, its `Record` impl.
- `contracts/logic/src/models/index.cairo`: the `Base` struct and its layout.
- `contracts/logic/src/models.cairo`: `pub mod base`.
- `contracts/logic/src/models/skill.cairo`: `SkillTrait::profile(part)`, the profession and the elite bit read from part 0.
- `contracts/logic/src/models/item.cairo`: `ItemTrait::class_of(part)`.
- `contracts/logic/src/professions.cairo`: `ProfessionTrait::attributes(id)`, design/03's attribute counts for all six professions (26 in all, D-157).
- `contracts/persistent/src/helpers.cairo`: `BitTrait`, with `pow2` (two tables, no loop), `limbs` (a split that keeps bit 250), `is_set`.
- `contracts/persistent/src/models/adventurer.cairo`: the refusals of `set_build`; the points and rank-cost tables; `BuildTrait` (`points`, `has_attribute`); `BuildAssert`, `KnownSkillsTrait`, `BeltAssert`, `EquippedAssert`; `AdventurerCoreTrait::secondary`.
- `contracts/persistent/src/models/item.cairo`: `COMMON`; `errors`; `ItemBaseAssert::assert_wearable`.
- `contracts/persistent/src/systems/hub.cairo`: `set_build`.
- `contracts/persistent/tests/test_build.cairo` (new): 17 tests, covering every rule, the worst case and its make-up.
- `contracts/persistent/tests/test_build_words.cairo` (new): the helpers against plain versions.
- `contracts/logic/tests/test_build_records.cairo` (new): `BASE`, the part-0 readers, the attribute counts.
- `contracts/persistent/tests/test_lifecycle.cairo`: `test_enter_after_set_build`.
- `contracts/persistent/tests/test_contracts.cairo`: the stub test calls `buy_skill`, since `set_build` is no longer a stub.
- `contracts/tools/lifecycle_probe.py` and `contracts/tools/lifecycle-probe-output.txt`: the belt's worst case on the node.
- `docs/BUDGETS.md`, `contracts/{logic,persistent,ephemeral}/GAS.md`: generated.

## Commands run

```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
    Finished `dev` profile target(s) in 12 seconds
cd contracts/logic && snforge test        Tests: 206 passed, 0 failed, 0 ignored, 0 filtered out
cd contracts/persistent && snforge test   Tests: 150 passed, 0 failed (after the stub test's fix; 1 failed before it:
                                          test_hub_deploys_and_stubs_revert still expected `set_build` to be a stub)
cd contracts/ephemeral && snforge test    Tests: 49 passed, 0 failed, 0 ignored, 0 filtered out
python3 scripts/gas_budgets.py            wrote contracts/{logic,persistent,ephemeral}/GAS.md, docs/BUDGETS.md
python3 scripts/gas_budgets.py --check    gas check: 405 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
python3 contracts/tools/class_sizes.py    Hub 959,205 bytes Sierra, 35,996 CASM felts, 43.94 % of the nearer limit, ok
                                          (every class ok; Instances 39.94 %)
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt
                                          exit 0; every transaction SUCCEEDED (rows below)
scarb --manifest-path contracts/Scarb.toml fmt --check    clean (CI's first run failed on a comment wider than 100
                                          columns; fixed in 342b57a)
gh pr checks 170                          every check pass; indexer-node skipping
```

snforge, the call measured alone with `get_available_gas` around it (M):

```
gas set_build, worst case: 3573411
gas set_build, empty: 799720
gas set_build, 8 skills alone: 1991970
gas set_build, 200 points alone: 818650
gas set_build, 4 potions on 4 pages alone: 1424710
gas set_build, 7 pieces alone: 2152231
gas enter, no belt (Instances a double): 1736860      (ENG-06 measured 1,583,170 before CBT-01)
gas enter, a belt of 4 pages emptied (Instances a double): 2258600
```

Node, the probe's receipts (M). The table in *Cost* has the net figures.

```
2451200  set_build, 4 potions on 4 pack pages (empty bar, no equipment)       hub 1 overwritten
5422400  enter, later entry, the belt's worst case (4 pages, each lane emptied) hub 6 O, instances 5 O
3262400  leave to a hub, the belt credited back (4 pages)                     hub 6 O, instances 3 O
5342400  enter, later entry, the belt's worst case (again)                    hub 6 O, instances 4 O
3057280  travel_back, the belt credited back (4 pages)                        hub 6 O, instances 3 O
4702400  enter, later entry (no belt)                                         hub 1 O, instances 4 O
2502400  leave to a hub (no belt)
2297280  travel_back (no belt)
```

On the node, `set_build`'s belt case writes 1 key. The empty build and the empty equipment it sends are, plus `LIVE`, the words a new adventurer already holds, so they do not change in the state diff. `test_set_build_worst_case` shows 3 overwritten keys when all three change.

## Cost

**Against ENG-01 §10 and D-148.** "Net" is the node figure less 189,141, the difference between the node's fixed part and §10's F. This is ENG-06's rule (D-148's targets are net figures).

| Entrypoint, case | Node L2 (M) | Net (D) | Target | Over |
|---|---:|---:|---:|---:|
| `set_build`, 4 potions on 4 pages, empty bar and equipment | 2,451,200 | 2,262,059 | 1,369,635 (§10) | **+65.2 %** |
| `set_build`, the worst case: 8 skills, 200 points, 4 potions on 4 pages, 7 pieces. **E**: the node's belt case + snforge's delta (3,573,411 − 1,424,710 = 2,148,701) | 4,599,901 | 4,410,760 | 1,369,635 (§10) | **+222 %** |
| `enter`, later entry, the belt's worst case | 5,422,400 | 5,233,259 | 4,100,000 (D-148) | **+27.6 %** |
| `leave` to a hub, the belt credited back | 3,262,400 | 3,073,259 | 2,350,000 (D-148) | **+30.8 %** |
| `travel_back`, the belt credited back | 3,057,280 | 2,868,139 | 2,350,000 (D-148) | **+22.0 %** |
| `enter`, later entry, no belt (main's code) | 4,702,400 | 4,513,259 | 4,100,000 (D-148) | +10.1 % |
| `leave` to a hub, no belt | 2,502,400 | 2,313,259 | 2,350,000 | −1.6 % |
| `travel_back`, no belt | 2,297,280 | 2,108,139 | 2,350,000 | −10.3 % |

**`set_build`'s make-up** (snforge, the call alone, M). The worst case is 3,573,411. The empty call costs 799,720: the ownership check's 3 reads, the 3 writes, the checks of the three layouts. What each part adds over the empty call:

| Part | Alone | Over the empty call | What it reads |
|---|---:|---:|---|
| 8 skills | 1,991,970 | +1,192,250 | 1 `known_skills` page; 8 `SKILL` records of 2 parts (16 slots), part 0 needed; the `bundle` call |
| 200 points | 818,650 | +18,930 | nothing (arithmetic and two tables) |
| 4 potions on 4 pages | 1,424,710 | +624,990 | 4 pack pages; 4 `ITEM` records (4 slots); the call |
| 7 pieces | 2,152,231 | +1,352,511 | 7 `ItemBase` words; 7 `BASE` records of 2 parts (14 slots), part 0 needed; the call |

The parts add up to 3,988,401. The worst case, with one call instead of three, costs 3,573,411. Most of `set_build` is registry reads, and §10 counted 1 call but no content slot. `bundle` reads every part of a record, so 15 of the 34 content slots it reads are unused. §10's estimate, 1,369,635, is F plus 1 call, 4 felts of calldata and 3 overwritten keys, with little computation.

**The belt's own share on the node.** It adds +720,000 to `enter` (5,422,400 − 4,702,400) and +760,000 to `leave` and to `travel_back` (the report credits 4 pages and rewrites `core`). §10 modelled it as 5 × O = 160,360 plus the reads. ENG-06 put an upper bound of +521,740 on `enter` in snforge. The node says more.

**Main's `enter` without a belt** is 440,000 above the committed probe output, which was ENG-06's and was not re-run after CBT-01. The first entry is up the same 440,000 (10,048,400 → 10,488,400). This lot does not change `enter`'s code, and `test_enter`'s total (36,172,310) is identical to main's `docs/BUDGETS.md` row. The inferred cause is CBT-01's larger snapshot sent to `Instances.create` (`test_enter`'s budget carries "raised, CBT-01: the snapshot carries design/19's passives").

**Gas table** (`python3 scripts/gas_budgets.py --report`, `origin/main` = `9430ff2` fetched). The 374 other rows are `unchanged`.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::test_build_records::test_base_armor_hands_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_build_records::test_base_no_slot_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_build_records::test_base_round_trip | — | 78500 | 82425 | new |
| grimworld_logic::test_build_records::test_base_slot_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_build_records::test_base_weapon_hands_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_build_records::test_profession_attributes | — | 33520 | 35196 | new |
| grimworld_logic::test_build_records::test_profession_attributes_none | — | 15520 | 16296 | new |
| grimworld_logic::test_build_records::test_skill_profile_and_item_class | — | 2209570 | 2320049 | new |
| grimworld_persistent::test_build::test_attributes_indices | — | 81922830 | 86018972 | new |
| grimworld_persistent::test_build::test_attributes_points_by_level | — | 84828850 | 89070293 | new |
| grimworld_persistent::test_build::test_attributes_rank_and_points | — | 77701110 | 81586166 | new |
| grimworld_persistent::test_build::test_bar_duplicate_refused | — | 75899030 | 79693982 | new |
| grimworld_persistent::test_build::test_bar_elite | — | 79486390 | 83460710 | new |
| grimworld_persistent::test_build::test_bar_known_and_registered | — | 79118590 | 83074520 | new |
| grimworld_persistent::test_build::test_bar_profession | — | 76636320 | 80468136 | new |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | — | 78146080 | 82053384 | new |
| grimworld_persistent::test_build::test_belt_items | — | 77666720 | 81550056 | new |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | — | 81537504 | 85614380 | new |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | — | 81434697 | 85506432 | new |
| grimworld_persistent::test_build::test_set_build_empty | — | 77521911 | 81398007 | new |
| grimworld_persistent::test_build::test_set_build_layout_refusals | — | 78415320 | 82336086 | new |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | — | 75952800 | 79750440 | new |
| grimworld_persistent::test_build::test_set_build_parts | — | 79629411 | 83610882 | new |
| grimworld_persistent::test_build::test_set_build_worst_case | — | 76768181 | 80606591 | new |
| grimworld_persistent::test_build_words::test_attribute_indices | — | 97050 | 101903 | new |
| grimworld_persistent::test_build_words::test_attribute_points | — | 298290 | 313205 | new |
| grimworld_persistent::test_build_words::test_known_skills_bits | — | 164100 | 172305 | new |
| grimworld_persistent::test_build_words::test_known_skills_past_page_255 | — | 15520 | 16296 | new |
| grimworld_persistent::test_build_words::test_pow2_and_bits | — | 3967220 | 4165581 | new |
| grimworld_persistent::test_contracts::test_hub_deploys_and_stubs_revert | 4001730 | 4001330 | 4201397 | -0.0 % |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | — | 42306880 | 44422224 | new |

About 75 M of each `test_build` test is its setup: 2 contracts, 34 registry records, and the pack and entities written with `store`. The benchmark is the call alone, printed above.

## Acceptance criteria

- **AC-1: done.** The words are stored as frozen (`test_set_build_worst_case`: each word = sent + `LIVE`; core, place and name unchanged; `test_set_build_empty`). `test_enter_after_set_build` checks the stored belt, bar and elite slot reach `enter`'s reserve and snapshot, and that inside, `set_build` is refused. The rules and their tests:

| Rule (source) | Refusal | Test, boundary |
|---|---|---|
| Owner, not deleted, in a hub (ADR-0007; design/03: locked inside) | `no adventurer`, `not owner`, `adventurer deleted`, `not in a hub` | `test_set_build_ownership_refusals`: accepted back in the hub; `test_enter_after_set_build` |
| Layouts: `Build` 164–167 and 176 up; belt 160 up; equipped 224 up; no caller `LIVE` (ENG-01 §3.3, §4.3) | `build: layout`, `belt: layout`, `equipped: layout` | `test_set_build_layout_refusals`: bits 163 and 159 are field bits (refused by their own rules), 164, 167, 176, 160, 224 and 250 refused |
| No skill twice (design/03) | `build: duplicate skill` | `test_bar_duplicate_refused`: slots 0 and 7; 7 distinct accepted |
| Skill known | `build: skill not known` | `test_bar_known_and_registered`: bit cleared, refused; page past 255 (skill 65000); `test_known_skills_bits` (bits 0, 127, 128, 249; 249 → 250 across pages) |
| Skill in the registry | `build: no skill` | known skill 12 without a record |
| Of the primary or the secondary profession (design/03) | `build: skill profession` | `test_bar_profession`: a Warden skill refused, then accepted with a Warden secondary; an Arcanist skill still refused |
| At most one elite; `elite_slot` names it, 255 without (design/03) | `build: two elites`, `build: elite slot` | `test_bar_elite`: slot 7 accepted; 6 and 255 refused with the elite; 0 refused without one (with and without skills) |
| Rank 0–12 (design/03) | `build: rank above 12` | `test_attributes_rank_and_points`: 12 accepted, 13 and 15 refused |
| Points within level and rank (design/03: 5/10/15 a level, +15 Tin, +15 Copper) | `build: points` | `test_attributes_rank_and_points`: 200 accepted, 201 refused (L20 Copper); 185 at Tin (180 accepted, 194 refused). `test_attributes_points_by_level`: L1 Wood 0 and 1; L1 Tin 15 and 16; L10 45 and 46 (48 refused); L11 55 and 56; L16 110 and 111; L99 capped at 200. `test_attribute_points`: the table against the rule as a loop |
| Build-local attribute indices (D-157 A) | `build: no such attribute` | `test_attributes_indices`: Warden index 4 and 5 refused; Vanguard secondary 5–8 accepted; Arcanist + Warden secondary: 8 refused; `test_attribute_indices` |
| A count only with an item (ENG-01 §4.5) | `belt: count without item` | `test_belt_items`, and bit 159 in `test_set_build_layout_refusals` |
| Potion items only (brief; design/03) | `belt: not a potion` | ingredient with and without a count; item without a record; potion without a count accepted |
| Within the pack, same item summed (ENG-01 §6) | `belt: not in the pack` | `test_belt_counts_within_the_pack`: 3 of 3 accepted, 4 refused; 1 + 2 accepted, 2 + 2 refused; another adventurer's potions |
| In the adventurer's own pack | `item: not in the pack` | `test_equipment_owned_and_wearable`: another's pack, the vault, an entity never written |
| Not a component (design/15) | `item: a component` | same test |
| Identified unless common (design/15: "needed to equip it") | `item: unidentified` | fine unidentified refused, fine identified and common accepted |
| No entity twice | `equipped: duplicate` | chest in lanes 2 and 6 |
| Base in the registry | `equipped: no base` | base 9 without a record |
| Base worn in its lane's slot (design/15) | `equipped: wrong slot` | `test_equipment_slots_and_hands`: chest in legs, shield in weapon, sword in feet |
| Two hands leave the off-hand empty (design/15, *Hands*) | `equipped: two hands` | maul + shield refused; maul alone, sword + shield, and a shield alone accepted |
| `BASE` layout checks | `base: slot`, `base: hands` | `test_build_records` |

- **AC-2: writes done; gas over §10, escalated (escalation 1).** 0 new and 3 overwritten keys, as in §9.3. `test_set_build_worst_case` reads the three words before (all non-zero) and after. On the node the belt case changes the 1 word that differs. The gas is +65.2 % (node, belt only) and +222 % (E, the worst case) over §10. That is beyond +10 %, so it goes to the project manager.
- **AC-3: done; overruns escalated (escalation 2).** Measured on the node against D-148: `enter` +27.6 %, `leave` to a hub +30.8 %, `travel_back` +22.0 %, with the make-up above.
- **AC-4: done.** The code follows D-143: every function in a trait (`BuildTrait`, `BuildAssert`, `BeltAssert`, `EquippedAssert`, `KnownSkillsTrait`, `ItemBaseAssert`, `BitTrait`, `BaseTrait`/`BaseAssert`/`BaseRecord`); no free function; errors in the models' `errors` modules. Storage is read and written as elsewhere in `hub.cairo`, since the store is still empty (ARC-06, ENG-R1). CI is green; `gas_budgets.py --check` and `class_sizes.py` pass.

## Deviations from the brief

- **"Its requirements met" is not an attribute check.** design/15 settles it: "Anyone can hold any weapon | The requirement, not a class lock, is what ties a weapon to a build", and below the requirement "Damage divided by 3; modifiers still work". So `set_build` does not refuse a requirement above the attribute's rank; the snapshot will apply the ÷ 3 (CBT-02 or ENG-07). The requirements design/15 does state for equipping are refused: identified ("Needed to: Equip it"; only fine and above are ever unidentified) and not a component.
- **The node covers the belt, not the bar or the equipment.** No entrypoint yet teaches a skill (`buy_skill`) or creates an equipment entity, so the full worst case runs in snforge only (with `store`). Its node figure is an estimate (E).
- **The probe fills adventurer 2's pack through one `report`.** The administrator's account stands in as `instances` for that one call, then the real `Instances` is registered again. No entrypoint fills a pack yet. This runs only on the local node, as the probe's docstring says.
- **Scope change beyond the allowlist's words:** `test_contracts.cairo`'s stub test now calls `buy_skill`. It is a test of the persistent package, which the allowlist covers ("the three packages' tests").

## Escalations

1. **`set_build`'s cost (project manager, beyond +10 %; cost-budget.md §2).** It measures about 3.2 times §10's estimate: 4.41 M net (E) against 1,369,635. The make-up is above. Options, none taken:
   - (a) Copy the base's slot and hands into `ItemBase`'s free bits 120–127 when an item is created. That word is written anyway, and CAIRO §1 prefers a stored field. It removes the 7 `BASE` reads (14 slots) and most of the equipment's +1.35 M (snforge). This is an ENG-01 §3.3 layout change.
   - (b) A registry read of part 0 only (a `headers` view), for `SKILL` and `BASE`. It saves 15 slot reads, and is a change to the registry's interface.
   - (c) Accept the measured figure as the target.
2. **The belt's worst case is over D-148's targets (project manager).** Net: `enter` 5.23 M (+27.6 %), `leave` to a hub 3.07 M (+30.8 %), `travel_back` 2.87 M (+22.0 %). The belt adds about +0.72 M to `enter` and +0.76 M to each return on the node, against §10's model of 5 × O plus reads. Separately, **main's `enter` without a belt is already +10.1 %** (4.51 M net) since CBT-01. The committed probe output was ENG-06's, from before CBT-01; this run replaces it.
3. **`BASE` had no bit layout** (ENG-01 §3.5 lists only its fields). I laid out only what `set_build` reads, from bit 0 of part 0: slot 0–7 (1 weapon … 7 feet, `equipped`'s lane + 1) and hands 8–15 (1 or 2 on a weapon, 0 elsewhere). The lot that lays out the rest (class, profession, damage by requirement, rating, look) can then append to it. This needs confirming. ENG-01 §3.5 needs the row, and that is a shared document outside the allowlist.
4. **Armor and profession.** design/15 gives armor classes by profession but does not say whether a Vanguard may wear light armor. It is not refused.
5. **D-157 A binds here.** The build-local attribute indices are 0–4 for the primary's attributes in design/03's row order (its primary attribute at 0), and 5–8 for the secondary's without its primary attribute. The flattening (CBT-02, ENG-07) and the client must use the same mapping. ENG-01 §3.3's comment on `Build.attributes` ("in the order of the profession's registry list") should say this; the code's comment does (`models/adventurer.cairo`, `SECONDARY_FIRST`). No global attribute id was needed: `set_build` checks counts only.
6. **Points come from design/03's table, not from state.** `AdventurerCore.unspent` is not used, because §9.3's write set for `set_build` has no `core`. The `RANK` record's "points given" (ENG-01 §3.5) is not read, because it has no model yet. design/03's numbers are used (15 at Tin, 15 at Copper; nothing above level 20). Whoever lays out `RANK` should reconcile the two, or `core.unspent` should be dropped.
7. **The stored `Build` of a new adventurer** (`NEW_BUILD`) equals `set_build` of an empty build. On the node, re-sending an empty bar or no equipment therefore writes an unchanged value. This was noted for the write counts; no action.

## Open questions

- Should `set_build` refuse a potion slot that names an item with a count of 0? It is accepted today: it carries nothing, and the snapshot copies the item id.
- A secondary profession equal to the primary cannot occur yet (no entrypoint sets `secondary`). `has_attribute` does not special-case it.

## Fix loop 1

The input: the `[GPT-6-Astra]` audit at `342b57a` (PASS WITH FINDINGS), and the project manager's D-158 on the cost escalations. F-1 (storage outside the store) was deferred to ENG-R1 by the orchestrator, so this loop does nothing about it. `origin/main` (`672808d`) was merged first. Head: `8152fc6`. Every CI check passed; `indexer-node` was skipped by its filter.

**Summary: `set_build` is still above the hub budget of 2.0 M net, and goes back to the project manager.** No longer reading `BASE` cut its worst case from 4.41 M to about 3.94 M net (E). Even the belt-only case, which the node measures, is 2.42 M net. The bar's 8 `SKILL` records are now the largest share. The belt's figures are within the new targets.

### D-158 (1): the slot and the hands are in `ItemBase`, and `set_build` reads no `BASE`

- **`ItemBase`** (`contracts/persistent/src/models/item.cairo`) gains `slot` in bits 120–123 and `hands` in bits 124–127. Both come from the item's `BASE` record. The packer refuses a value wider than 4 bits (`'packing: slot above 4 b'`, `'packing: hands above 4 b'`).
- **The creators.** No code creates an item entity today. Nothing writes the `items` map: `report` refuses `Results.equipment`, and `buy`, `craft`, loot, quests and collectors are still stubs or not written. So the one place that sets the new fields is the constructor that every creator must call: `ItemBaseTrait::new(base, record: @Base, …)`. It copies the record's slot and hands, and `ItemBaseTrait::is_two_handed` reads the hands back. ENG-01 §3.3 now says this, including for the ephemeral domain's drops in `Results.equipment`.
  - Tests: `test_item_slot_and_hands` (the bits at 120 and 124, the copy from a two-handed weapon and from feet, the round trip), `test_item_slot_too_wide`, `test_item_hands_too_wide`, and `test_item_grimoire_rift_layout` (every field at its maximum, slot and hands included).
  - `test_build.cairo` now creates every entity through `ItemBaseTrait::new` from its base's record.
- **`set_build`** now checks `ItemBase.slot == lane + 1` and the lane-0 item's hands directly. Its one `bundle` call asks for the bar's skills and the belt's items only, at most 12 records (it was 19). The refusal `equipped: no base` is gone: an item of no slot (0) is refused as `equipped: wrong slot` (`test_equipment_owned_and_wearable`, entity `NOT_WORN`).
- **The `BASE` model** in `grimworld_logic` stays. It is what the creators copy from. Its comment now says it covers the prefix only and that its packer writes 0 to every other bit (the audit's F-2 note).

**Re-measured.** snforge, the call alone (M), before this loop → after:

| Case | Before | After | Change |
|---|---:|---:|---:|
| Worst case | 3,573,411 | 2,960,731 | −612,680 |
| Empty | 799,720 | 821,260 | +21,540 |
| 8 skills alone | 1,991,970 | 2,009,950 | +17,980 |
| 200 points alone | 818,650 | 840,190 | +21,540 |
| 4 potions alone | 1,424,710 | 1,442,690 | +17,980 |
| 7 pieces alone | 2,152,231 | 1,348,261 | −803,970 |

On the node (M), with net = node − 189,141:

| `set_build` case | Node L2 | Net | Hub budget | Over |
|---|---:|---:|---:|---:|
| 4 potions on 4 pages, empty bar and equipment (measured) | 2,611,200 | 2,422,059 | 2,000,000 | **+21.1 %** |
| Worst case: 8 skills, 200 points, 4 potions, 7 pieces (**E**) | 4,129,241 | 3,940,100 | 2,000,000 | **+97 %** |

The worst case's estimate is the node's belt case plus snforge's delta (2,960,731 − 1,442,690 = 1,518,041). It is still an estimate: no entrypoint yet teaches a skill or creates equipment, so the node cannot reach it.

**Why the belt case rose 160,000 on the node.** It was 2,451,200 at `342b57a`; its code path did not change in this loop. snforge shows only +18,000 on that case and +21,500 on the empty call. I did not find the cause. One possibility is the build-to-build variance of D-154; this is a guess, not verified.

**The make-up now** (snforge, what each part adds over the empty call):

| Part | Adds | What it reads |
|---|---:|---|
| 8 skills | +1,188,690 | 1 known-skills page; 8 `SKILL` records of 2 parts (16 slots, part 0 needed); the call |
| 4 potions | +621,430 | 4 pack pages; 4 `ITEM` records; the call |
| 7 pieces | +527,001 | 7 `ItemBase` words, no registry |
| 200 points | +18,930 | nothing |

The parts add up to 3,177,311. The worst case costs 2,960,731, because it makes one registry call instead of two.

The next lever is the bar's `SKILL` reads. Escalation 1's option (b), a part-0 view in the registry, would save 8 of its 16 slots; it is a change to the registry's interface. That is the project manager's to decide.

**Targets** (D-158: the measure becomes the target). Only the belt case is measured on the node: 2,422,059 net. The worst case is 3,940,100 net (E) until a creator of items and `buy_skill` exist and it can be measured.

### D-158 (2): the belt against its new targets

These are node receipts (M), net of 189,141.

| Entrypoint | Node L2 | Net | Target (D-158) | Result |
|---|---:|---:|---:|---|
| `enter`, a later entry, 4 pages emptied | 5,422,400 | 5,233,259 | 5,250,000 | within, −0.3 % |
| `enter`, the second such entry | 5,342,400 | 5,153,259 | 5,250,000 | within, −1.8 % |
| `leave` to a hub, 4 pages credited | 3,262,400 | 3,073,259 | 3,100,000 | within, −0.9 % |
| `travel_back`, 4 pages credited | 3,057,280 | 2,868,139 | 2,900,000 | within, −1.1 % |

These are unchanged from `342b57a`: the loop did not touch those paths.

### F-2: the layouts are frozen in ENG-01

- **§3.3, `ItemBase`:** slot 120–123 and hands 124–127, their values, and who writes them.
- **§3.3, `Build`:** the build-local attribute indices of D-157 A, the elite sentinel 255, and the layout refusal.
- **§3.5:** two `BASE` rows. Part 0 holds slot 0–7 and hands 8–15, with the remaining fields to be appended after bit 15; part 1 holds `LIVE` only until then.

### Commands run

```
git merge origin/main                                   672808d merged
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build     Finished
cd contracts/persistent && snforge test                 Tests: 152 passed, 1 failed (test_item_grimoire_rift_layout over its
                                                        budget: 350,080 against 341,397); after the raise, the gas check passes
python3 contracts/tools/set_budgets.py (test_build::, test_layout, test_enter_after_set_build)   set: 16, 9, 1
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt   exit 0,
                                                        every transaction SUCCEEDED
python3 scripts/gas_budgets.py                          4 files written
python3 scripts/gas_budgets.py --check                  408 tests, every budget ceil(1.05 x measured) or lower, 4 files current
python3 contracts/tools/class_sizes.py                  Hub 948,895 bytes, 43.57 % (was 43.94 %); all ok
gh pr checks 170                                        every check pass at 8152fc6; indexer-node skipping
```

The logic and ephemeral packages were not re-run locally: logic changed in comments only, and ephemeral does not depend on the persistent package. CI ran all three packages and passed.

### Cost (the rows changed in this loop; `gas_budgets.py --report`, 373 rows unchanged)

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_persistent::test_layout::test_item_grimoire_rift_layout | 325140 | 350080 | 367584 | raised: D-158: `ItemBase` gains slot and hands, packed and unpacked in the round trip; +7.7 % |
| grimworld_persistent::test_layout::test_item_slot_and_hands | — | 180660 | 189693 | new |
| grimworld_persistent::test_layout::test_item_slot_too_wide | — | 15520 | 16296 | new |
| grimworld_persistent::test_layout::test_item_hands_too_wide | — | 15520 | 16296 | new |
| grimworld_persistent::test_build::test_set_build_worst_case | — | 66049511 | 69351987 | new (was 76768181 at 342b57a) |
| grimworld_persistent::test_build::test_set_build_parts | — | 68776951 | 72215799 | new |
| grimworld_persistent::test_build::test_set_build_empty | — | 66824781 | 70166021 | new |
| grimworld_persistent::test_build::test_equipment_owned_and_wearable | — | 70690664 | 74225198 | new |
| grimworld_persistent::test_build::test_equipment_slots_and_hands | — | 69388187 | 72857597 | new |
| grimworld_persistent::test_build::test_attributes_indices | — | 71865180 | 75458439 | new |
| grimworld_persistent::test_build::test_attributes_points_by_level | — | 74866690 | 78610025 | new |
| grimworld_persistent::test_build::test_attributes_rank_and_points | — | 67617850 | 70998743 | new |
| grimworld_persistent::test_build::test_bar_duplicate_refused | — | 65802880 | 69093024 | new |
| grimworld_persistent::test_build::test_bar_elite | — | 69501740 | 72976827 | new |
| grimworld_persistent::test_build::test_bar_known_and_registered | — | 69096090 | 72550895 | new |
| grimworld_persistent::test_build::test_bar_profession | — | 66582710 | 69911846 | new |
| grimworld_persistent::test_build::test_belt_counts_within_the_pack | — | 68063840 | 71467032 | new |
| grimworld_persistent::test_build::test_belt_items | — | 67626240 | 71007552 | new |
| grimworld_persistent::test_build::test_set_build_layout_refusals | — | 68306370 | 71721689 | new |
| grimworld_persistent::test_build::test_set_build_ownership_refusals | — | 65852070 | 69144674 | new |
| grimworld_persistent::test_lifecycle::test_enter_after_set_build | — | 42320790 | 44436830 | new |
| grimworld_persistent::test_contracts::test_hub_deploys_and_stubs_revert | 4001730 | 4001330 | 4201397 | -0.0 % |

The `test_build` totals fell by about 10 M each, because the setup no longer writes the 8 `BASE` records. The rows of `test_build_words` and `test_build_records` did not change in this loop.

### Escalations after fix loop 1

1. **`set_build` is above the hub budget of 2.0 M net** (project manager, as D-158 says): 2.42 M measured for the belt case and 3.94 M (E) for the worst case. The make-up is above. The remaining lever is the registry's part-0 view for `SKILL`, escalation 1's option (b).
2. **Unexplained +160,000 on the node's belt case** of `set_build`, on an unchanged path (see above). This is recorded, not chased (D-154's rule for flaky gas).
3. **D-158's decision file** on `main` (`docs/decisions/2026-09-29-cbt-08a-costs.md`) still reads "Decision: Pending" at `672808d`. This loop applied the decision as the orchestrator relayed it.

## The worst case measured (D-158)

The project manager accepted option (c), on the condition that a test carrying a budget measures `set_build`'s worst case. `origin/main` (`cd979f8`) was merged first. Head: `bcacc3d`. Every CI check passed; `indexer-node` was skipped by its filter. Nothing else changed.

**The test.** `test_set_build_worst_case` (`contracts/persistent/tests/test_build.cairo`) now measures the `set_build` call alone and asserts it against its own budget.
- **The case:** 8 skills with an elite in slot 3, 200 attribute points (12/12/3, a level 20 Copper), 4 potions on 4 pack pages, and 7 pieces worn.
- **The measure:** `get_available_gas()` before and after the one dispatcher call, as ENG-04 and ENG-06 did.
- **The assertion:** `assert(call <= WORST_CASE_CALL, 'set_build over its budget')`, with `const WORST_CASE_CALL: u128 = 3108768;`, which is ceil(1.05 × 2,960,731 measured).
- **The test's own budget** still covers the whole test, deploy and setup included: 69,352,586, ceil(1.05 × 66,050,081).

```
cd contracts/persistent && snforge test test_set_build_worst_case
gas set_build, worst case: 2960731
[PASS] grimworld_persistent_integrationtest::test_build::test_set_build_worst_case (l1_gas: ~0, l1_data_gas: ~9792, l2_gas: ~66050081)
python3 scripts/gas_budgets.py --check     gas check: 408 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
gh pr checks 170                           every check pass at bcacc3d; indexer-node skipping
```

**As a transaction.** This uses the same conversion as the report, on §10's basis: the snforge call, plus F, plus the calldata. F is 816,939. The calldata is 4 felts (adventurer, build, belt, equipped) × 5,120 = 20,480.

| | L2 gas |
|---|---:|
| The call, snforge (M) | 2,960,731 |
| + F | 816,939 |
| + calldata, 4 × 5,120 | 20,480 |
| **The transaction, net (D)** | **3,798,150** |
| The fix-loop-1 estimate: node belt case − 189,141 + snforge's delta | 3,940,100 (E) |
| Difference | −141,950 (−3.6 %) |
| Hub budget (D-158) | 2,000,000; the transaction is +89.9 % over it, which option (c) accepts |

**Why the two figures differ.** The same conversion applied to the belt-only case gives 1,442,690 + 837,419 = 2,280,109. The node measured that case at 2,422,059 net, which is exactly 141,950 more. So the difference is the one between the node and this conversion on the part both cases share. It is not a difference in the worst case's own work. On the node's meter, the worst case would therefore come out near the estimate, 3.94 M net (E), and the measured transaction's 3.80 M is the lower of the two readings. The test's constant is the snforge call, which is what CI can check on every run.

**Gas table** (the rows this section changed):

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_persistent::test_build::test_set_build_worst_case | — | 66050081 | 69352586 | new (the call alone: 2,960,731, budget `WORST_CASE_CALL` 3,108,768) |
