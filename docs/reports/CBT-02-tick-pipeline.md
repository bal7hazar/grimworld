# [Opus 5.5] CBT-02 — The world tick's pipeline, as pure rules

## Summary

The game now has the world tick's pipeline as pure, deterministic rules in a library class. The session ran as Opus 5.5 (`claude-opus-5-5`), the model the brief names.

- **`grimworld_logic::tick`** implements design/02's tick in design/19 §5.1's order, steps 0 to 5, over the members and the goblins the tick may touch:
  - step 0: clears the flags "since the last tick";
  - step 1: concludes the activations due, members first, then awake goblins by id, with the recharge counted from `A`;
  - FX-29's lazy lapse of a goblin frozen at `A`, and a recovery that is over clears;
  - step 2: decides which goblins may act (awake, alive, not busy, not knocked down, not resolved this tick);
  - step 3: regeneration, degeneration and adrenaline decay, with D-157 E's 1 quarter a tick;
  - deaths after every actor of step 3, in id order;
  - step 4 writes nothing; step 5 checks defeat;
  - FX-8: the adventurer at 0 in steps 1–2 stops the tick at once, and step 5 still runs.
- **The per-actor rules** are methods for the executor and the AI to call: start an activation (members `A = c + n`, goblins `A = T + n`, `n ≥ 1`), a goblin's recovery (FX-15), an activated attack's recovery `B = A + k − n − 1`, interrupt (recharge from `t₀`), lapse (the later recharge is kept), an instant skill's recharge, kill, and the awake set (the 8 nearest, ties by lowest id).
- **What later lots fill** are hooks of a `Rules` trait: perception (design/18), the executor (CBT-05), the goblins' AI and the objectives (ENG-07). `Idle` runs them as no-ops.
- **The tick works on the stored words** (ENG-01 §3.2). Each call loads each actor's hot fields once and writes them back as deltas. The ephemeral package's tests pin these accessors against its own packers, with every field checked and every other bit kept.
- **`TickLibrary`**, the library class, is in `contracts/logic/src/systems/tick.cairo`.
  - Its manifest lines are `[lib]` and `[[target.starknet-contract]]` in `contracts/logic/Scarb.toml`: a contract target replaces the default library target, so both are declared.
  - Its interface is `ITickLibrary::run(words, content, ticks) -> words` in `grimworld_logic::interface`, called once per invocation through `ITickLibraryLibraryDispatcher { class_hash }`.
  - It is 18,904 CASM felts, **23.08 %** of the nearer limit.
- **Content is read once per batch** (D-145). The tick reads *sheets*: the few fields of a `SKILL`, an `ITEM` and a `CASTE` it needs, read straight from the record's parts. That costs 40,995 a record against 100,990 through the full unpack, and the unpacked record is the oracle.
- **CBT-9 is closed.** `MemberKitTrait::condition_duration` sums `CONDITION_DURATION` per condition, then caps it at 50. The test oracle aggregates independently and compares with it (33 + 10 = 43; 40 + 30 → 50; two conditions refused).
- **D-157 G is applied (D-160).** The empty hook is replaced by design/20's per-source bounds in the validators and by the production flattening with its checks. See *D-160 applied* at the end.
- **ENG-01 §1.3** now describes the library class and its call; **§9.2** gives a tick's figures.

**The cost is escalated, not accepted.** The tick's measured share uses 69 % (representative) to 95 % (worst) of the 1,469,435 target per tick, before the executor, the AI, the flood, the window, the writes and the floor. The make-up and the levers are below.

Pull request: https://github.com/bal7hazar/grimworld/pull/182. CI is green on every check (`cairo (contracts)` included).

## Files changed

- `contracts/logic/src/tick.cairo`: the pipeline, the `Rules` hooks and `Idle`, the per-actor rules, the world helpers.
- `contracts/logic/src/types/tick.cairo`:
  - the words in and out (`Words`, `MemberWords`, `GoblinWords`);
  - the hot-field actors (`Member`, `Goblin`) with `load` and `store`;
  - the sheets (`SkillSheet`, `PotionSheet`, `CasteSheet`) with `new` (the oracle) and `read` (from parts);
  - `Content`, and the constants (`ADRENALINE_DECAY` = 1, statuses, AI states, flags).
- `contracts/logic/src/systems.cairo`, `contracts/logic/src/systems/tick.cairo`: the library class `TickLibrary`.
- `contracts/logic/src/interface.cairo`: `ITickLibrary`.
- `contracts/logic/src/lib.cairo`, `contracts/logic/src/types.cairo`: the module declarations.
- `contracts/logic/src/types/effect.cairo`: `EntryTrait::line`, §2.2's scaling for a value kept apart from its entry; `value` calls it.
- `contracts/logic/src/snapshot.cairo`: `MemberKitTrait::condition_duration` (CBT-9) and the D-157 G hook.
- `contracts/logic/Scarb.toml`: `[lib]` and `[[target.starknet-contract]]`.
- `contracts/logic/tests/test_tick.cairo`: 36 tests covering the worked examples, the rules, load and store, the sheets' oracle, determinism and the cost benchmarks.
- `contracts/logic/tests/test_capacity.cairo`: the oracle aggregates per condition and checks the builder; three CBT-9 tests.
- `contracts/logic/tests/test_combat.cairo`, `contracts/logic/tests/test_validators.cairo`: 19 budgets lowered (measures fell 0.2–1.5 %).
- `contracts/ephemeral/tests/test_tick_words.cairo`: the tick's words and constants pinned against the ephemeral packers.
- `docs/BUDGETS.md`, `contracts/logic/GAS.md`, `contracts/ephemeral/GAS.md`: generated.
- `docs/architecture/ENG-01-interfaces.md`: §1.3 (the library class) and §9.2 (a tick's figures).

## Commands run

```
$ cd contracts/logic && snforge test
Tests: 244 passed, 0 failed, 0 ignored, 0 filtered out
$ snforge test -p grimworld_ephemeral
Tests: 52 passed, 0 failed, 0 ignored, 0 filtered out
$ snforge test -p grimworld_persistent
Tests: 153 passed, 0 failed, 0 ignored, 0 filtered out
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
    Finished `dev` profile target(s) in 29 seconds
$ python3 contracts/tools/class_sizes.py
| grimworld_ephemeral | `Instances` | 828,127 | 12,121 | 32,719 | 39.94 % | ok |
| grimworld_logic | `TickLibrary` | 439,402 | 6,385 | 18,904 | 23.08 % | ok |
| grimworld_persistent | `Hub` | 948,895 | 14,366 | 35,691 | 43.57 % | ok |
(every class ok; limits 4,089,446 bytes, 81,920 felts; warning at 50 %)
$ python3 scripts/gas_budgets.py --check        # after scarb fmt, on the pushed commit
gas check: 449 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt   # CI's first run failed on format only
$ gh pr checks 182     # after the watch completed
every check pass (indexer-node skipping), cairo (contracts) pass
```

I profiled the steps with scratch tests (not committed) and changed the representation twice because of what they showed. On the representative tick, net of fixtures:

| Representation | Pipeline, one tick | What dominated |
|---|---:|---|
| A struct per actor, 30 to 55 felts | 924,247 | struct copies, and content lookups in step 3 |
| The words themselves, fields read by limb | 1,079,087 | a `split` of a word into limbs costs ~5.8k gas and was done ~6 times per goblin per tick |
| **Words in and out, hot fields loaded once (kept)** | **617,867** | copies of the ~23-felt goblin struct in the three passes (~6k each) |

## Cost

**The tick's figures, net of the tests' fixtures**, against the expedition's **1,469,435 L2 gas a tick inside a batch** (cost-budget §2, D-159). **Re-measured after D-160** (commit `c7effac`, `GAS.md`): every `test_tick::test_cost_*` figure is identical to the unit, because D-160 changes the validators and the snapshot, not the tick. The sheets moved by the baseline's fixture only (`test_cost_sheets` 418,040 − `test_cost_sheets_baseline` 336,050 = 81,990, the same 40,995 a record). **The cost stays escalated**, and no lever (a) to (e) is applied.

| Per tick | Representative | Worst |
|---|---:|---:|
| The pipeline, one tick | 617,867 | **1,792,171** |
| The pipeline, over a batch of 10 ticks | 622,274 | 751,553 |
| Load and store, and the library call, over the batch | 200,857 | 271,009 |
| **Through one library call, a batch of 10 ticks** | **823,131** | **1,022,562** |
| The content the tick reads, once per batch (D-145: 54,000 a record, 98,000 a call; 19 / 37 records; sheets at 40,995 a record) | 190,291 | 371,082 |
| **The tick's share** | **1,013,422 (69 %)** | **1,393,644 (95 %)** |
| Left for everything else (the executor, AI, flood, window, writes, floor) | 456,013 | 75,791 |

The states:
- *Representative*: the member with one condition and one effect; 8 awake goblins of 2 castes fighting; no activation due.
- *Worst*: the member with 4 `REGENERATION` effects (2 potions), 3 degenerating conditions and an activation resolving; 8 goblins of 5 castes, each with 3 degenerating conditions and an effect; 4 activations resolving (2 into a recovery), 2 lapsing, 2 recoveries ending. The 28 skills, 5 castes and 4 potions are the MVP's worst content (design/19 §7.2, `C = 5`), with the goblins' skills last, for the longest lookups.

How each figure is derived:
- The library call itself on the worst state is 799,800: `test_cost_library_call` 15,772,211 − `test_cost_library_baseline` 14,972,411. That is about 6.8 C: the content's ~230 felts of calldata, more than the syscall.
- Load and store on the worst state is 1,906,060 per call: `test_cost_load_store_worst` 13,179,700 − `test_cost_fixture_worst_words` 11,273,640.
- Declaring the class costs 10,510: 7,517,920 − 7,507,410.
- The rows add up: 1,906,060 + 7,515,528 + 799,800 = 10,221,388, against 10,225,618 measured in one call.

**Gas table** (`python3 scripts/gas_budgets.py --report`, `origin/main` fetched; the rows this lot touched; the 383 others are `unchanged`):

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::test_tick_words::test_tick_constants | — | 13720 | 14406 | new |
| grimworld_ephemeral::test_tick_words::test_tick_words_goblin | — | 551950 | 579548 | new |
| grimworld_ephemeral::test_tick_words::test_tick_words_member | — | 1199020 | 1258971 | new |
| grimworld_logic::test_capacity::test_flatten_damage_extremes | 3574320 | 3720010 | 3753036 | +4.1 % |
| grimworld_logic::test_capacity::test_flatten_penetration_and_armor_extremes | 7004290 | 7295670 | 7354505 | +4.2 % |
| grimworld_logic::test_capacity::test_flatten_saturated_extremes | 3518420 | 3662420 | 3694341 | +4.1 % |
| grimworld_logic::test_capacity::test_flatten_unguarded_armor_extremes | 7041980 | 7333360 | 7394079 | +4.1 % |
| grimworld_logic::test_capacity::test_flatten_weapon_scope_on_attack_skills | 3474630 | 3620320 | 3648362 | +4.2 % |
| grimworld_logic::test_capacity::test_flatten_worst_scope_overlap | 7093670 | 7385050 | 7448354 | +4.1 % |
| grimworld_logic::test_capacity::test_same_condition_capped | — | 3722330 | 3908447 | new |
| grimworld_logic::test_capacity::test_same_condition_summed | — | 3718650 | 3904583 | new |
| grimworld_logic::test_capacity::test_two_conditions_builder_refused | — | 28400 | 29820 | new |
| grimworld_logic::test_combat::test_carrier_attack_bonus_in_a_spell_refused | 172610 | 170610 | 179141 | -1.2 % |
| grimworld_logic::test_combat::test_carrier_attack_entry_on_self_refused | 77270 | 76270 | 80084 | -1.3 % |
| grimworld_logic::test_combat::test_carrier_attack_with_damage_refused | 89900 | 88900 | 93345 | -1.1 % |
| grimworld_logic::test_combat::test_carrier_damage_not_first_refused | 173100 | 171100 | 179655 | -1.2 % |
| grimworld_logic::test_combat::test_carrier_disc_1_in_a_skill_refused | 105250 | 104250 | 109463 | -1.0 % |
| grimworld_logic::test_combat::test_carrier_disc_2_refused | 89240 | 88240 | 92652 | -1.1 % |
| grimworld_logic::test_combat::test_carrier_gap_refused | 231560 | 228560 | 239988 | -1.3 % |
| grimworld_logic::test_combat::test_carrier_modifier_on_another_set_refused | 233970 | 230970 | 242519 | -1.3 % |
| grimworld_logic::test_combat::test_carrier_modifier_without_hit_refused | 219290 | 216290 | 227105 | -1.4 % |
| grimworld_logic::test_combat::test_carrier_trap_not_first_refused | 157760 | 155760 | 163548 | -1.3 % |
| grimworld_logic::test_combat::test_carrier_trap_payload_on_self_refused | 226940 | 223940 | 235137 | -1.3 % |
| grimworld_logic::test_combat::test_carrier_two_hits_refused | 173380 | 171380 | 179949 | -1.2 % |
| grimworld_logic::test_combat::test_carrier_two_holding_refused | 172430 | 170430 | 178952 | -1.2 % |
| grimworld_logic::test_combat::test_item_round_trip | 465690 | 464690 | 487925 | -0.2 % |
| grimworld_logic::test_combat::test_item_scaled_potion_refused | 80360 | 79360 | 83328 | -1.2 % |
| grimworld_logic::test_combat::test_legal_carriers | 1641630 | 1617630 | 1698512 | -1.5 % |
| grimworld_logic::test_tick::test_adrenaline_decay | — | 10857128 | 11399985 | new |
| grimworld_logic::test_tick::test_awake_set | — | 8231690 | 8643275 | new |
| grimworld_logic::test_tick::test_cost_batch_representative | — | 13136570 | 13793399 | new |
| grimworld_logic::test_tick::test_cost_batch_worst | — | 18193508 | 19103184 | new |
| grimworld_logic::test_tick::test_cost_fixture_representative | — | 6913830 | 7259522 | new |
| grimworld_logic::test_tick::test_cost_fixture_representative_words | — | 7507410 | 7882781 | new |
| grimworld_logic::test_tick::test_cost_fixture_worst | — | 10677980 | 11211879 | new |
| grimworld_logic::test_tick::test_cost_fixture_worst_words | — | 11273640 | 11837322 | new |
| grimworld_logic::test_tick::test_cost_library_baseline | — | 14972411 | 15721032 | new |
| grimworld_logic::test_tick::test_cost_library_baseline_representative | — | 7517920 | 7893816 | new |
| grimworld_logic::test_tick::test_cost_library_call | — | 15772211 | 16560822 | new |
| grimworld_logic::test_tick::test_cost_library_call_batch | — | 21509768 | 22585257 | new |
| grimworld_logic::test_tick::test_cost_library_call_batch_representative | — | 15749230 | 16536692 | new |
| grimworld_logic::test_tick::test_cost_load_store_worst | — | 13179700 | 13838685 | new |
| grimworld_logic::test_tick::test_cost_sheets | — | 415690 | 436475 | new |
| grimworld_logic::test_tick::test_cost_sheets_baseline | — | 333700 | 350385 | new |
| grimworld_logic::test_tick::test_cost_sheets_unpacked | — | 535680 | 562464 | new |
| grimworld_logic::test_tick::test_cost_tick_representative | — | 7531697 | 7908282 | new |
| grimworld_logic::test_tick::test_cost_tick_worst | — | 12470151 | 13093659 | new |
| grimworld_logic::test_tick::test_deaths_in_step_3 | — | 6233828 | 6545520 | new |
| grimworld_logic::test_tick::test_defeat | — | 10241179 | 10753238 | new |
| grimworld_logic::test_tick::test_deterministic | — | 36512356 | 38337974 | new |
| grimworld_logic::test_tick::test_example_activated_attack_cost | — | 16396163 | 17215972 | new |
| grimworld_logic::test_tick::test_example_burning_goblin | — | 5801594 | 6091674 | new |
| grimworld_logic::test_tick::test_example_condition_degeneration | — | 6115876 | 6421670 | new |
| grimworld_logic::test_tick::test_example_interrupt | — | 5893772 | 6188461 | new |
| grimworld_logic::test_tick::test_example_lapse | — | 11203274 | 11763438 | new |
| grimworld_logic::test_tick::test_example_member_activation | — | 14829016 | 15570467 | new |
| grimworld_logic::test_tick::test_flags_cleared | — | 4830233 | 5071745 | new |
| grimworld_logic::test_tick::test_goblin_load | — | 751700 | 789285 | new |
| grimworld_logic::test_tick::test_library_matches_pipeline | — | 33530658 | 35207191 | new |
| grimworld_logic::test_tick::test_load_store | — | 10370870 | 10889414 | new |
| grimworld_logic::test_tick::test_regeneration | — | 9929919 | 10426415 | new |
| grimworld_logic::test_tick::test_sheets_read_oracle | — | 1316590 | 1382420 | new |
| grimworld_logic::test_tick::test_who_acts | — | 7167709 | 7526095 | new |
| grimworld_logic::test_validators::test_attack_bonus_on_allies_refused | 89710 | 88710 | 93146 | -1.1 % |
| grimworld_logic::test_validators::test_attack_hit_penetration_on_allies_refused | 89900 | 88900 | 93345 | -1.1 % |
| grimworld_logic::test_validators::test_attack_modifiers_on_foes_accepted | 390170 | 384170 | 403379 | -1.5 % |

No budget was raised:
- The six `test_flatten_*` measures rose about 4 % because the oracle now also calls the builder (CBT-9). They stay under their existing budgets.
- The 19 `test_combat` and `test_validators` measures fell by 0.2–1.5 %, and their budgets were lowered.
- The tests' fixtures build the words bit by bit (a `two(n)` loop), so a benchmark's figure is always given net of its `test_cost_fixture_*`.

## Acceptance criteria

**AC-1: every step and rule follows design/02 and design/19 in order.** The rule map:

| Rule (design/02 *The tick*, design/19) | Code (`contracts/logic/src/`) | Test (`tests/test_tick.cairo` unless said) |
|---|---|---|
| The order of a tick, steps 0–5 (§5.1) | `tick.cairo` `TickTrait::tick`, `run` | every test that runs ticks; `test_who_acts` |
| Step 0: the clock advances; the flags "since the last tick" and "hit this tick" clear | `TickTrait::tick`, `clear_flags` | `test_flags_cleared` |
| Step 0: perception (design/18) | hook `Rules::perceive` (ENG-07) | — |
| Step 0: the awake set, the 8 nearest, ties by lowest id, not asleep and alive (§5.2, design/02) | `TickTrait::awake` | `test_awake_set` |
| A frozen goblin: nothing read or written (§5.2) | `awake` guards in `conclude`, `act`, `regenerate` | `test_example_lapse` (§10.5) |
| Step 1: a member's activation due at `A` resolves; its recharge counts from `A` (FX-1, FX-2) | `conclude`, `MemberTickTrait::conclude` | `test_example_member_activation` (§10.1) |
| Step 1: a goblin's activation due at `A`; it does not act in step 2 (§5.2) | `conclude` (the `resolved` mask), `GoblinTickTrait::conclude` | `test_example_activated_attack_cost` (§10.9) |
| An activated attack with `k ≥ n + 2` recovers until `B = A + k − n − 1` (FX-15) | `GoblinTickTrait::conclude` | `test_example_activated_attack_cost` (k = 3) |
| A frozen goblin's activation lapses at `A`, lazily; `R = A + r − 1`, a later `R` kept (FX-29) | `conclude`, `GoblinTickTrait::lapse` | `test_example_lapse` (§10.5) |
| A recovery ends when `T > B` (§5.2) | `conclude` | `test_example_activated_attack_cost`, `test_cost_tick_worst` |
| The executor at resolution (§5.14) | hook `Rules::resolve` (CBT-05) | `Script` rules record each call |
| Start: members `A = c + n`, goblins `A = T + n`, `n ≥ 1` (§5.1, §6) | `MemberTickTrait::start`, `GoblinTickTrait::start` | `test_example_member_activation`, `test_example_interrupt` |
| A goblin's act of cost `k > 1` recovers until `B = T + k − 1` (FX-15) | `GoblinTickTrait::recover` | `test_example_activated_attack_cost` |
| Interrupt: none, recharge from `t₀`; a recovery is not interrupted (§5.9, FX-2) | `MemberTickTrait::interrupt`, `GoblinTickTrait::interrupt` | `test_example_interrupt` (§10.2), `test_example_member_activation` (§10.6) |
| An instant skill recharges from its use (§5.1) | `use_instant` (both) | `test_example_member_activation` |
| Step 2: who acts; the knocked down, busy, frozen and dead do not (§5.2, FX-7) | `TickTrait::act` | `test_who_acts`, `test_example_interrupt` |
| Step 2: the AI (ENG-07) | hook `Rules::act` | — |
| Step 3: health pips from the snapshot, `REGENERATION` effects and −3/−4/−7, clamped ±10, × 2, clamped to [0, max] (§5.8, design/03) | `MemberTickTrait::regenerate`, `GoblinTickTrait::regenerate`, `heal`, `degeneration`, `held` | `test_example_condition_degeneration` (§10.3), `test_example_burning_goblin` (§10.1), `test_regeneration` |
| Step 3: energy by its pips in thirds, clamped to max | the same | `test_regeneration`, `test_deaths_in_step_3` |
| Step 3: adrenaline decay out of combat, 1 quarter (FX-12, D-157 E) | `decay`, `ADRENALINE_DECAY` | `test_adrenaline_decay` |
| Step 3: a goblin at 0 dies after every actor, in id order (§5.13) | `TickTrait::regenerate` | `test_deaths_in_step_3` |
| A goblin killed by the executor dies at once, once (§5.13) | `WorldTrait::kill` | `test_deaths_in_step_3` |
| Step 4: nothing written; a deadline ≤ the clock reads as ended | the `t ≤ D` reads | `test_example_burning_goblin` (tick 45) |
| Step 5: defeat; the objectives after it (§5.13, D-04) | `TickTrait::check`, hook `Rules::objectives` | `test_defeat` |
| FX-8: at 0 in steps 1–2 the tick stops at once; step 5 runs; the run stops | `tick`, `conclude`, `act`, `run` | `test_defeat` |
| A goblin's max health: design/03's formula × the caste's multiplier (design/05, §7.3) | `CasteSheetTrait::max_health` | `test_goblin_load`, `test_tick_words_goblin` |
| A held effect's pips at its rank (§2.2) | `SkillSheetTrait::regen`, `EntryTrait::line` | `test_regeneration`, `test_goblin_load` |
| Content read once per batch (D-145) | `SkillSheetTrait::read`, `PotionSheetTrait::read`, `CasteSheetTrait::read` | `test_sheets_read_oracle` |
| The words (ENG-01 §3.2) | `MemberTrait::load`/`store`, `GoblinTrait::load`/`store` | `test_load_store`; ephemeral `test_tick_words_*` |

**AC-2: deterministic.** `test_deterministic` runs the same worst state twice over 10 ticks, and the two worlds are equal; no rule reads a draw or block data. Six worked examples of design/19 are tests: `test_example_condition_degeneration` (§10.3), `test_example_burning_goblin` (§10.1, step 3), `test_example_interrupt` (§10.2), `test_example_lapse` (§10.5), `test_example_activated_attack_cost` (§10.9), and `test_example_member_activation` (§10.1's resolution, §10.6's interrupt).

**AC-3: the pipeline runs in a library class, and the call is measured.** It runs in `TickLibrary`. `test_library_matches_pipeline` shows the call gives the same words as a direct run. The call costs 799,800 on the worst state (above and ENG-01 §1.3).

**AC-4: the cost per tick is measured by budgeted tests, against 1,469,435, with its make-up.** It is measured on representative and worst states (`test_cost_*`), with the make-up in *Cost*. **It is escalated, not accepted**; see *Escalations*.

**AC-5:**
- CBT-9 is closed: `test_same_condition_summed`, `test_same_condition_capped`, `test_two_conditions_builder_refused`, and the oracle checks the builder in every flatten test.
- D-157 E is applied: `ADRENALINE_DECAY` = 1, tested by `test_adrenaline_decay`.
- D-157 G is applied under D-160 (see *D-160 applied*); the empty hook is gone.
- D-143: the layers are `types/` for the value types, `systems/` for the class, and the rules in traits. The free functions (`degeneration`, `held`, `heal`, `decay`, `recharge`, `delta`, `member_hot`, `goblin_hot`, `member_recharge_at`) each carry a written reason: the arithmetic of one quantity shared by members and goblins, or a table.
- CI is green; `gas_budgets.py --check` and `class_sizes.py` pass.

## Deviations from the brief

- **The tick's state is the stored words, not a copy of CBT-01's types.** The member and goblin words are the ephemeral package's, which depends on `grimworld_logic`, so logic cannot import them. The tick therefore repeats ENG-01's frozen offsets, and the ephemeral package's tests pin them against its packers (`test_tick_words`: every field loaded, every field stored, every other bit kept, the constants equal). I measured two other representations first (table in *Commands run*) and kept the cheapest. A layout change in ENG-01 §3.2 now fails those tests until the tick follows it.
- **CBT-9: there was no production snapshot builder in the code.** The flattening was only the test oracle, since ENG-06's builder does not exist yet. I added the builder's aggregation (`MemberKitTrait::condition_duration`), made the oracle aggregate on its own, and made the oracle compare the two.
- **The quick-cast counters are not moved at an activation's start.** §5.12 moves them with the costs at the start (§5.3 step 2, CBT-05's). Also, the snapshot's quick-cast attribute is a build-local index and the skill's is a global id (D-157 A), and the mapping between them is ENG-06's. `start` therefore takes `n` after reductions.
- **Nineteen budgets of tests this lot did not target were lowered.** Their measures fell 0.2–1.5 % after `EntryTrait::value` came to delegate to `line`. Lowering needs nothing (CAIRO §2); I list them because they are outside the brief's intent.

## Escalations

1. **The cost per tick (AC-4, D-159): not accepted.** The tick's measured share uses 69 % (representative) to 95 % (worst) of 1,469,435 before anything of CBT-03 to CBT-05 or ENG-07 runs. One worst tick alone is 1,792,171. The target cannot hold once the executor, the AI and flood, the window, the storage writes and the floor are added, unless some of the levers below are taken. The make-up is in *Cost* and in ENG-01 §9.2. The levers, with what each would save:
   - a. **The copies of the goblin struct.** Each of the three per-tick passes copies each goblin (~6k gas, ~23 felts). Splitting the hot fields from the rest (the words, the ids), or keeping masks of due activations and free goblins across steps, would cut the pipeline, by about 30 to 50 % (my estimate from the profile, not measured). This is CBT-02's own to do in a follow-up, or ENG-07's when the AI lands.
   - b. **The limb split.** `packing::split` costs ~5.8k gas a word (the `u256` conversion), and load and store split ~40 words a call on the worst state (1.9M a call). `u252` from `origami_hexmap` (CAIRO §4, noted in `packing.cairo`) or a cheaper split would cut this. It touches `packing`, the owner of every layout.
   - c. **Tick sheets written at registration** (CAIRO §1: work at registration, not at every call). One compact felt a record, holding the few fields the tick reads, would remove the extraction (40,995 a record) and halve the reads of two-part records. It changes the registry (ENG-03, ENG-05).
   - d. **The content's calldata into the call.** Most of the call's 799,800 is the sheets (~230 felts on the worst state). Packing a sheet into one felt would cut the content's felts about five times.
   - e. **Design levers**, for the project manager: fewer awake goblins, the weight of a batch, or the target itself.
2. **`TickLibrary` is already 23.08 % of the class limit.** CBT-03 to CBT-05 add the executor to the same class. If it passes 50 %, ENG-01 §1.3's rule splits it.
3. **Readings of the design I made, for confirmation:**
   - **Flags.** Step 0 clears the flags `TURNED` and `INSTANT` ("since the last tick", ENG-01 §3.2) and `HIT` ("hit this tick", design/19 §7.2), and keeps `HALVED`. No document says in which step they clear.
   - **FX-8.** I read "step 3 completes first" (§5.13) as applying when the adventurer reaches 0 in step 3. A stop in steps 1–2 skips step 3 and runs step 5.
   - **An instant skill's `t₀`.** In the action phase it is `c + 1`, like a duration's: §5.1 names "the use of an instant skill" without the phase's `t₀`.
   - **A goblin's max health**: *settled.* design/20 §1.5 (G1, D-160) states `⌊(100 + 20 (L − 1)) × m / 100⌋`, which the code already computes (`CasteSheetTrait::max_health`), in a `u32` as G1 requires. §6 test 6 checks it (`test_caste_at_bounds`: 51,800 at `m` = 1,000, level 255).
   - **"The adventurer at 0"**, with M-3's several members, is any member inside at 0. Only one member exists in the MVP; design/08 decides for several.
   - **The credit for a goblin killed by degeneration (M-4).** The pipeline records the kill, but a condition's source is not stored, so who is credited is ENG-07's. The MVP has one member, so it is unambiguous today.
4. **DES-06 is decided (D-160) and applied here.** What D-160 leaves open or outside this allowlist is in *D-160 applied*.
5. **ENG-07 must still wire the call.** `Instances` has to hold the class hash as configuration, read the words, call `run`, and write back the words that changed. It also has to build the content's sheets once per batch, from the records it reads.

## Open questions

- Whether the project manager wants lever 1a (the copies) done now as a CBT-02 follow-up, before CBT-03 to CBT-05 build on the pipeline's data layout, or left to ENG-07.
- Whether the registry should hold precomputed tick sheets (lever 1c): that is a content-pipeline decision (ENG-03, ENG-05).

## D-160 applied

`origin/main` merged (design/20 v1.0, the decision file with D-160). Commits `0e08144` (the code and tests) and `c7effac` (budgets, `scarb fmt`). CI is green on `c7effac` (`gh run list`: ci and tooling `success` on that SHA).

### What each decision became

| Decision (design/20 §5) | Where | Tests |
|---|---|---|
| **DS-1**, the per-source bounds (§1.3, envelope B) | `types/passive.cairo`: `source_bound` (the table), `PassiveTrait::fits_source`, `PassiveAssert::assert_source_bounds`, called by `ModifierAssert::assert_legal` (benefit and cost summed) and `ArmorSetAssert::assert_legal` (each bonus). The flattening's whole-build checks: `snapshot.cairo` `BuildAssert::assert_sources` (each passive legal on its source; one kind per source; ≤ 2 passives a modifier, 1 a set bonus; nothing twice; at most §1.2's count of each source) | `test_build::test_per_source_bounds` (17 rows: at lo, at hi, a unit beyond each end), `test_modifier_beyond_bound_refused`, `test_set_bonus_beyond_bound_refused`, `test_sixth_rune_refused`, `test_instance_of_two_kinds_refused` |
| **DS-2**, the floors | `SnapshotBuildTrait::build`: max health, max energy, energy regeneration summed signed, refused below 1, 0, 0 | `test_floor_max_health_refused`, `test_floor_max_energy_refused`, `test_floor_energy_regen_refused` (§6 test 3) |
| **DS-3**, `health_bonus` | freed: the build writes the final maximum in `max_health`, and `health_bonus` 0 | `test_extremal_max_health` |
| **DS-4**, sources with no field | `PassiveTrait::allows`: `ENERGY_COST`, `BASE_DAMAGE_PERCENT` on no record; `ATTRIBUTE` on runes only. Also rows 2–4, 13, 14's sources (life steal and energy on hit on held slots; max energy and both regenerations not on insignias or runes). Personalisation's +20 % in the build | `test_per_source_bounds` (12 refused sources), `test_extremal_weapon` |
| **DS-5**, saturation | the build sums wide (`u32`), then `saturate`: condition and enchantment 50, knock-down 3, armor against a type 63. The content bounds (≤ 33, ≤ 20, ≤ 1 a source) are in `source_bound` | `test_saturation` (340 → 50, 4 → 3, 149 → 63), `test_capacity::test_same_condition_capped` (65,534 → 50) |
| **DS-7**, primary attributes and light armor | the build: *Wellspring* 3 energy a primary rank (the Arcanist's), light armor +20 energy and +1 pip. *Might* and *Fieldcraft* act at use (CBT-03, CBT-05), not in the snapshot | `test_extremal_max_energy_and_rank` (130) |
| **DS-8**, rank 15 | `HeldSums::rank`: points + the highest rune, refused above 15 | `test_extremal_max_energy_and_rank` (12 + 3) |
| **DS-9**, strength capped by level | the build: `min(5 × rank, strength_cap)` | `test_extremal_weapon` (50; 40 under a cap of 40) |
| DS-18 (the caste's checks; my allowlist includes CBT-01's validators) | `CasteAssert::assert_valid` at `pack`: multiplier ≤ 1,000, energy regeneration ≤ 10, weapon damage ≤ 255, flee ≤ 100; `CasteAssert::assert_skills`: a skill's adrenaline ≤ 63 strikes | `test_caste_at_bounds` (51,800; 255 thirds; 63 strikes), `test_caste_multiplier_1001_refused` and four more refusals (§6 test 6) |
| DS-20 (one `ATTACK_BONUS` a carrier) | `EntryAssert::assert_carrier` | `test_second_attack_bonus_refused`, `test_one_hit_product` (§6 test 7) |
| DS-29 (health regeneration ≤ 20 at pack) | `MemberStatsAssert::assert_valid`, `CasteAssert::assert_valid` | `test_stats_health_regen_20_packs`, `_21_refused`, `test_caste_health_regen_21_refused_at_pack`, `test_tick::test_regeneration_extremes` (−64 and +50 pips computed, clamped) (§6 test 9) |

**§6's tests, one by one:**
- 1 and 2: `test_build`, with the extremal builds (max health 1,020; max energy 130; weapon damage 32; rank 15) and `test_other_fields_within_envelopes`.
- 3 to 7 and 9: as the table says.
- 10: `test_durations` (`effective_duration(32,767, 50, 3)` = 49,153, and 43,688 → 65,535 already). The effect's 63 charges and rank 15 are in the ephemeral `test_layout` (`test_effect_charges_refused`, `test_effect_rank_refused`, `test_combat_fields_layout`), which existed.
- **Not built here:**
  - §6 test 8 (a hit's percents, +281 and −249 floored at −100) is the damage formula's, which is CBT-03's.
  - test 10's counters (`hits` at N − 1 resetting) are CBT-05's: no code moves them yet.

### The production flattening

`SnapshotBuildTrait::build(loadout, held) -> Snapshot` (`contracts/logic/src/snapshot.cairo`) is the production snapshot builder D-160 asks for before any production snapshot. It takes:
- the build (`Loadout`: level, profession, attribute points with the primary first, the bar's attributes, the weapon, the strength cap, the pieces' rating, the belt);
- the passives held (`HeldPassive`: each with its source, its source instance, its modifier id, benefit or cost).

It checks the build first (`BuildAssert`), then writes the three words. CBT-01's test oracle (`test_capacity::flatten`) stays; its tests moved from envelope A to B.

### Tests changed by D-160

- **`test_same_condition_summed` (CBT-9).** The audit's example, a prefix of Bleeding 33 + 10, is above DS-5's ≤ 33 on a prefix and is now refused (`test_same_condition_above_33_refused`). The summed case is 20 + 13 = 33. The saturation is tested on the builder's sum (65,534 → 50).
- **`test_flatten_saturated_extremes`.** It now uses B's values: 9 × 7 = 63, knock-down 13 → 3, enchantment 140 → 50.
- **`test_separate_sums_accepted`.** The two armor passives of one type on a rune are 3 + 4.
- **`test_life_steal_set_bonus_refused`** replaces `test_unruled_sums_accepted_and_escalated`, whose sums design/20 now rules.
- **`test_sources_accepted`.** The *Hob-breaker* knock-down is +1 a bonus.
- **`caste_max`** (`test_combat`) is at DS-18 and DS-29's bounds.

### Budgets

- **The new tests** are measured at `ceil(1.05 × measured)`.
- **14 budgets are raised**, each with `// gas: raised, D-160: the validators check design/20's per-source bounds (DS-1, DS-4, DS-5)`: 10 in `test_capacity`, 2 in `test_combat`, 1 in `test_validators`, and CBT-9's `test_same_condition_summed`. The raises come from the extra checks in `ModifierAssert` and `ArmorSetAssert`, for example `test_sources_accepted` 1,239,231 → 1,523,907. **They need the orchestrator's agreement** (CAIRO §2).
- `gas_budgets.py --check`: 476 tests, every budget current.
- `class_sizes.py`: `TickLibrary` is unchanged at 23.08 %; `Instances` is 39.97 %; `Hub` 43.57 %.

### Escalations from D-160

1. **The flattening is not wired: `persistent` is outside my allowlist.** `Hub.set_build` must call `SnapshotBuildTrait::build`, so that DS-2's floors refuse at `set_build` as decided. `enter` must use its snapshot, not `SnapshotTrait::new`, which still gives equipment 0; then "never a panic in `enter`" holds, since the build was refused at `set_build`. Both need the equipped items' passives, rolls and modifier ids, and the pieces' rating: ENG-06 and CBT-08's formulas, which `set_build` does not read today.
2. **The flattening's cost, measured, and above a hub action's budget.** The widest builds cost, with their small fixtures included, 6,803,060 (max health, 17 passives) and 11,092,130 (32 passives: the 15 modifiers at two passives, the 2 set bonuses). That is against `enter`'s 3.6M and a hub action's 2.0M (cost-budget §2). The checks are quadratic in the passives, and each statistic is a pass over them. The levers are for the project manager to choose:
   - one pass into fixed accumulators;
   - trusting the records' validation at the registry's write (the registry does not call `assert_legal` today: CBT-01), and keeping only the whole-build counts in the flattening;
   - flattening once at `set_build` and storing the three words, rather than at every `enter`.
3. **DS-23's per-piece insignia bound (15 / 10 / 5).** It needs the insignia record to name its piece, a `MODIFIER` layout change that D-160 gives to CNT-01 and CBT-08. The validators bound every insignia at the widest piece's 15. The proof still fits: max health ≤ 1,055 with five 15s, under `u16`. The extremal build uses 15 / 10 / 5 / 5 / 5, as §6 says.
4. **Values the decisions give only as bounds, used at the bound until BAL-01, for confirmation:**
   - DS-7's *Wellspring* 3 a rank and light armor +20 energy and +1 pip;
   - DS-5's content bounds read as per-source values, on every source that may hold the passive: design/20 writes "≤ 20 on the inscription, ≤ 1 on set bonuses" without saying these are the only sources.
5. **DS-9's cap has no curve.** design/04 and D-160 say "capped by level" and leave the curve to BAL-01, so I did not invent one. The build takes `strength_cap` as an input and applies `min(5 × rank, cap)`. Until BAL-01 writes the curve, the caller has none to pass.
6. **DS-18's cross-record check** (`CasteAssert::assert_skills`) exists but no one calls it. The registry's content pipeline (ENG-03, ENG-07) must call it with a caste's skill records.

My escalation 3's readings stay escalations (flags at step 0, FX-8, an instant skill's `t₀`, several members at 0, the credit for a degeneration kill); only the goblin's max health is settled by design/20 §1.5.

## Fix loop 1

The `[GPT-6-Astra]` audit of c7effac (`logs/AUD-182-audit1.md`) returned a FAIL with nine findings. `origin/main` is merged: D-161 decides the cost, and levers (a) and (b) go to CBT-02b. The fix is commit `0cb93db`. CI is green on it (`gh run list`: ci and tooling `success` on `0cb93db…`).

### Each finding, and the test that shows its fix

Each test fails on c7effac, for one of two reasons:
- **Behaviour**: c7effac gives another result or accepts what is now refused. The reason is in the finding's line.
- **Compile**: the test calls an API c7effac lacks, which is itself the finding.

I did not execute the tests against c7effac's sources: the logic tests compile as one crate, and the new APIs would stop the old one from compiling.

1. **AUD-182-1, belt slot 0** (major).
   - Fix: `MemberTrait::load` reads the potion tag before the empty-skill sentinel.
   - Test: ephemeral `test_tick_words::test_potion_regeneration_every_belt_slot` runs each of the four belt slots through ephemeral's packers, `load` and a tick.
   - On c7effac: behaviour; slot 0 loaded 0 pips.
2. **AUD-182-2, the capacity guarantee** (major).
   - Fix: `PassiveTrait::fits_source` also bounds **each passive** of a bounded statistic within its source's `[lo, hi]`, not only their sum. Then any selection the flattening makes (a rune's benefit once per id, the highest attribute rune) with every cost stays within `n × [lo, hi]`: for one id, `max b + Σ c = (b_j + c_j) + Σ_{k≠j} c_k ≤ n · hi`, and likewise `≥ n · lo`.
   - Fix: `BuildAssert::assert_loadout` checks the build's own bounds: points ≤ 12, weapon damage at requirement ≤ 27, rating ≤ 560.
   - Tests:
     - `test_build::test_capacity_proof` computes each field's envelope from the same tables the validators enforce (`source_bound`, `allows`, `max_instances`) and checks it fits: max health 5,180 + 575 ≤ 65,535; max energy 130; energy regeneration 7; health regeneration 3…12; life steal 25; energy on hit 5; rank 15; weapon 32 and strength 75; the `i8` and `u8` sums; unguarded armor ≤ 9,995. The saturated fields are saturated.
     - `test_envelope_builds` flattens the extremal builds at the envelope (max health 1,055; health regeneration 3 and 12; life steal 25; energy on hit 5; energy regeneration 7).
     - `test_cancelling_rune_refused` is the audit's −32,717 / +32,767 rune.
     - `test_repeated_rune_id`: three runes of one id give 480 + 50 − 225.
   - On c7effac: behaviour; the audit's rune was accepted.
3. **AUD-182-3, the attribute flattening** (major).
   - Fix: `HeldSums::rank` sums each rune's `ATTRIBUTE` passives for the attribute, then the highest rune counts.
   - Tests: `test_rune_attribute_contribution` (+1 and +2 on one rune: 12 → 15; c7effac gave 14) and `test_cancelling_attribute_rune_refused` (+32,767 / −32,764, accepted on c7effac).
4. **AUD-182-4, D-157 B and C** (major).
   - Fix: `PassiveTrait::allows` holds `QUICK_CAST_EVERY_N` on inscriptions only and `DAMAGE_TYPE` on prefixes only (design/20 §1.8). `assert_catalogue`'s "one slot type" check stays as a guard.
   - Tests: `test_decided_slot_types_accepted`, `test_undecided_slot_types_refused`, `test_damage_type_suffix_catalogue_refused` and `test_quick_cast_on_a_suffix_refused` replace the old "any consistent slot type" tests.
   - On c7effac: behaviour; a suffix was accepted.
5. **AUD-182-5, a member at 0 before the tick** (major).
   - Fix: `TickTrait::tick` checks first. A member inside at 0 (after the action phase: a trap on its move, §5.11) stops the tick before the clock advances or any actor runs; step 5's defeat and objectives run (FX-8, §5.13). The pipeline owns the check; the caller applies the action, then calls it.
   - Test: `test_member_down_before_the_tick`: no act, clock unchanged, no step 3, defeated and down.
   - On c7effac: behaviour; the goblin acted and the clock advanced.
6. **AUD-182-6, refresh and adrenaline gain** (major). New `MemberLifecycleTrait` and `GoblinLifecycleTrait` (`tick.cairo`):
   - `inflict`: FX-6's `max(D_old, t₀ + d − 1)`, Knocked down too (FX-31); a dead goblin takes nothing.
   - `cure`: `D = t₀ − 1` when held, else nothing.
   - `hold`, §5.7 in order: the same carrier keeps the later deadline, whole, the new one on a tie (FX-30), a potion identified by its item (FX-42); then a stance takes the held stance's slot; then the lowest free slot; then eviction, the earliest deadline with ties to the lowest slot (FX-13). A goblin's one slot is refreshed or replaced.
   - `gain_adrenaline`, `land_weapon_hit` (4 quarters, 8 on every N-th hit, `hits` reset at N) and `take_hit` (1 quarter while alive), each gain capped at the actor's cap: the bar's or the caste's highest cost, at most 252 for a goblin (§5.12, FX-12).
   - What they need: Crippled, `hits`, the double-adrenaline N, the belt and the held effects are read and written in the words directly (`MemberWordsTrait`, `GoblinWordsTrait`). The adrenaline caps are derived once at `load`, so `SkillSheet` gains the skill's `adrenaline`, read from the `SKILL` header.
   - Tests: `test_conditions_refresh_and_cure` (§10.3), `test_hold_eviction_and_stance` (§10.4), `test_hold_refresh` (FX-30, one potion in two belt slots), `test_adrenaline_gain`.
   - On c7effac: compile. The rule map of AC-1 gains these rows.
   - **Scope note**: the adrenaline spent at an adrenaline skill's start is a cost (§5.3 step 2), CBT-05's, not built.
7. **AUD-182-7, worst cases by construction** (major). The worst single tick's state is `worst_state`: the goblin array at its bound, `MAX_GOBLINS` = 100, 8 awake. Why no legal state costs more, pass by pass:
   - **Array**: each pass is linear in the array's length, and 100 is its bound.
   - **Step 0**: its cost is fixed.
   - **Step 1**: each awake goblin takes the costliest branch. A conclusion into a recovery makes a lookup at the end of every content list (38 skills with `T` = 10, the caste last), writes the recharge and the recovery, and rebuilds the array. A lapse makes the same lookup and rebuild with fewer writes; an ending recovery and "nothing" cost less.
   - **Step 2**: a goblin that resolved does not act, so under `Idle` step 2's cost per goblin is the check.
   - **Step 3**: every term is active on every awake actor. No goblin is Engaged, so the Engaged scan runs the full array and every actor takes the decay branch.
   - **Deaths**: every goblin and the member die (8 kill records; step 5 rewrites the members).
   - **Fixtures**: goblins are loaded from their words, so their maxima agree with their caste and level; the 400/280 mismatch is gone.
   - **Over a batch**: `Busy` rules make the member resolve every tick. Each goblin with a 1-tick weapon alternately resolves and acts, so every tick rewrites it; a goblin cannot resolve two ticks running, because it does not act in its resolution tick.
   - **Named as traces, not bounds**: the representative batch and the library's 10-tick call (the class runs `Idle`).
   - Budgets carry the measures.
   - On c7effac: behaviour; its "worst" tick, 1,792,171, is 12,413,893 under this construction.
8. **AUD-182-8, measures over their budgets** (minor). Re-measured:
   - Two of the seven are replaced (AUD-182-4).
   - The other five are a **real change, not a flake**: D-160's new branches in `PassiveTrait::allows` run before their panic point. Each is raised to ceil(1.05 × measured) with `// gas: raised, AUD-182-8: D-160's allows() branches run before this test's panic`, for example `test_damage_all_and_weapon_same_guard_refused` 44,384 → 50,190.
   - No `GAS.md` row has a negative margin now.
   - Such a row passed because snforge does not fail an expected-panic test above its budget, and `scripts/gas_budgets.py` does not flag it. **The checker fix is outside my allowlist**: escalated.
   - `gas_budgets.py --check`: 494 tests, every budget current. The raises need the orchestrator's agreement.
9. **AUD-182-9, scoped decoders** (minor).
   - Fix: `member_hot` and `goblin_hot` are now `MemberTrait::hot` and `GoblinTrait::hot`.
   - Test: `test_hot_decoders` (compile on c7effac).
   - The remaining free functions are tables or the arithmetic of one quantity, each with its reason in the code.

### Cost, re-measured (`0cb93db`, net of fixtures)

| Measure | Representative | Worst, by construction |
|---|---:|---:|
| The pipeline, one tick | 629,417 | 12,413,893 (2,333,623 with only the 8 awake goblins) |
| The pipeline, 10 ticks, per tick | 633,824 (trace) | 11,961,927 (`Busy`) |
| Load and store, once per call | — | 51,128,460 (101 actors) |
| The library call, once per call | — | 2,578,020 |
| Through one library call, 10 ticks, per tick | 960,751 | 17,332,575 |
| Content once per batch (19 / 47 records; sheets 42,710 a record) | 193,549 | 474,137 |
| **The tick's share, per tick** | **1,154,300** | **17,806,712** |

- The representative tick moved from 617,867 to 629,417 (+11,550): the new check at the tick's start and the new field.
- The representative library batch moved from 823,131 to 960,751 a tick: `load` reads the skills for the adrenaline caps.
- The worst case is dominated by the array's bound, since every goblin write rebuilds the 100-goblin array: lever (a), CBT-02b by D-161.
- **The cost stays escalated and decided (D-161); no lever is applied.**
- `TickLibrary`: 19,950 CASM felts, **24.35 %**.
- ENG-01 §1.3 and §9.2 carry these figures.

### Escalations from fix loop 1

- **The gas checker** should fail a measure above its budget (AUD-182-8); it is outside my allowlist.
- **An effect ended by its charges** is ended by the executor with the deadline `t − 1`: `hold` reads activity from the deadline. CBT-05 to confirm.
- **The worst case's 100-goblin array** is `MAX_GOBLINS`, the window's 40 goblins plus the roster's 60. If ENG-07 bounds the array the tick receives more tightly, the worst case falls by up to about 10M.
- **The wiring of the flattening into `Hub.set_build` and `Hub.enter`** is CBT-02b's and is left untouched.

## Fix loop 2

Two audits of 0cb93db (via nexus) returned a FAIL: cost by `[GPT-6-Astra]` (COST-1, COST-2) and quality by `[GPT-6-Sol]` (1 to 4). `origin/main` is merged; it changed no contract. The fix is commit `b5f068a`. CI is green on it (`gh run list`: ci and tooling `success` on `b5f068a…`).

The checks:
- `gas_budgets.py --check`: 502 tests, every budget current.
- **No `GAS.md` row with a negative margin (0 in each of the three files).** Seven expected-panic tests had gone over budget silently, the AUD-182-8 case again. Each is set from its measure, with a raise line where the test exists on main (`test_stance_armor_twice_refused`: `// gas: raised, DS-23: the fixture's insignia is made for its piece`). The checker's fix stays escalated.
- The logic tests pass, as do ephemeral's 53 and persistent's 153.
- `TickLibrary` is 19,950 CASM felts, **24.35 %**, unchanged.

### COST-1: the worst case with every loaded actor's lookup, and the awake selection

- **Fix**: in `worst_of`, the 92 frozen goblins now each hold a retained effect (skill 43, the content's last, at rank 4). `load` therefore looks it up and scales it for all 100 goblins, as the audit showed a permitted input does. The awake set's selection (§5.2, `TickTrait::awake`) gets its own benchmark at the candidate bound: `test_cost_awake_100`, 100 eligible candidates at distances falling along the array. There, each of the 8 selection scans updates its running minimum at every element, the costliest order for that loop.
- **Evidence that the old figure was not an upper bound**:
  - load/store of the worst state: **51,128,460 at 0cb93db → 59,823,300 now**. The +8,694,840 is the 92 frozen lookups.
  - The awake selection was not measured at all; it is **4,263,890** over 100 candidates.
  - The tick itself is unchanged (12,413,893), since frozen goblins do nothing in a tick.
- **Cost table, worst column, updated** (ENG-01 §9.2 too):
  - through one library call, 10 ticks: **18,202,059 a tick**;
  - with the content: **18,676,196 a tick**;
  - the awake selection: 4,263,890 wherever ENG-07 runs it at step 0.
  - The representative column is unchanged: 1,154,300.

### COST-2: DS-23's insignia pieces

An insignia's health is now bounded by its piece, **15 / 10 / 5 / 5 / 5**, in two places.
- **The record.** `MODIFIER` gains `piece`, low limb bits 8–15, `base::slot::CHEST` … `FEET`, set with `ModifierTrait::insignia(piece, …)`. `ModifierAssert::assert_piece` refuses an insignia without a piece, any other slot type with one, and health above the piece's bound (`ModifierTrait::insignia_health`, per passive and summed). Every slot type but insignias keeps piece 0, so their records are unchanged.
- **The flattening.** `HeldPassive` gains `piece`, the armor piece the item is worn on. `BuildAssert::assert_insignia` bounds each insignia by its piece and allows one insignia a piece.
- **The proof.** `test_capacity_proof` now sums the pieces' 40, not five times 15, and shows **max health 1,020** at level 20. `test_envelope_builds` flattens the 15 / 10 / 5 / 5 / 5 build to 1,020 and no longer accepts 1,055.
- **Tests that fail on 0cb93db** (behaviour: all were accepted there; the record tests also call `ModifierTrait::insignia`, which did not exist):
  - `test_five_insignias_at_15_refused`;
  - `test_two_insignias_on_a_piece_refused`;
  - `test_insignia_record_above_piece_refused` (legs at 11);
  - `test_insignia_record_without_piece_refused`;
  - `test_insignia_record_piece` (the piece round-trips).
- **Still `set_build`'s**: the check that a record's piece matches the worn item's `BASE.slot` (DS-23) needs the item, so it belongs to CBT-02b and CBT-08.

### Quality 1: CAIRO §7's layers

| What | Where now | Why |
|---|---|---|
| `MemberWords`, `Member`, `GoblinWords`, `Goblin` (the actors' stored words and their in-call view) | `models/index.cairo` (the structs of every model) | They are stored entities, or the view of one; the storage layouts stay the ephemeral package's |
| The member's behaviour: load/store and word accessors (`MemberTrait`, `MemberWordsTrait`), activation rules (`MemberTickTrait`), lifecycle (`MemberLifecycleTrait`) | `models/member.cairo` | A model's file holds its behaviour. The recharge and effect tables are now `MemberTrait::recharge_at` and `MemberTrait::effect_at` |
| The goblin's behaviour, the same four traits | `models/goblin.cairo` | Same |
| The arithmetic shared by members and goblins (`delta`, `tag`, `refreshed`, `cured`, `min16`, `degeneration`, `effect_pips`, `heal`, `decay`, `recharge_deadline`), and its input checks | `helpers/tick.cairo`: `TickMathTrait`, and `TickAssert` with its `errors` | §7's `helpers/`: what belongs to no entity, scoped in traits |
| `World`, `Words`, `Actor`, the `Rules` hooks, `Idle`, and **the pipeline** (`TickTrait`: run, tick, the steps, the awake set; `WorldTrait`, `WordsTrait`, `WorldStoreTrait`) | `types/world.cairo` | **§7 has no layer for pure game rules**, and D-147 forbids a `logic/` folder. The pipeline is the behaviour of the `World` value type, which is not stored on its own, so it sits in `types/` with it, as `types/combat.cairo` holds `PlacerTrait`. The rules of one actor are its model's; `elements/` is one file per content behaviour, which the pipeline is not |
| `Held`, the sheets, `Content`, the frozen encodings (status, AI states, flags), the tick's constants | `types/tick.cairo` | Value types not stored on their own |
| `TickLibrary` | `systems/tick.cairo` (unchanged) | The entrypoint |
| The top-level `tick.cairo` | **removed** | It was a rules module outside §7's layers |

**Evidence.** The old layout had `contracts/logic/src/tick.cairo`, a rules module outside §7, and the stored words' structs in `types/`. Now `git show b5f068a --stat` shows `tick.cairo` deleted, and `models/member.cairo`, `models/goblin.cairo`, `helpers/tick.cairo` and `types/world.cairo` added. Every test now imports the new paths and would not compile against 0cb93db's.

### Quality 2: free functions

- `member_recharge_at` and `member_effect_at` are the member's methods.
- `tag`, `recharge` (now `recharge_deadline`), `delta` and the other arithmetic are `TickMathTrait`'s.
- The free functions left in the files this lot touched each carry a written reason: `saturate`, `max_instances`, `source_bound` (tables or single-field arithmetic, as before), and `fit` (a new reason: "a conversion generic over every field's type, which no type owns"). The `pack_*` functions are CBT-01's.
- **Evidence**: a `grep` for `^fn|^pub fn` in `types/tick.cairo`, `types/world.cairo`, `models/member.cairo`, `models/goblin.cairo` and `helpers/tick.cairo` finds none. At 0cb93db, `tick.cairo` had 8 and `types/tick.cairo` 4.

### Quality 3: validation in Assert impls, one `errors` module

- `snapshot.cairo`'s `build_errors` is merged into its `errors` module. The build's quick-cast error becomes `QUICK_CAST_ATTRIBUTE` so as not to clash; the messages are unchanged.
- The checks move into Assert impls:
  - `condition_duration`'s one-condition check is `MemberKitAssert::assert_one_condition`;
  - the flattening's floors are `BuildAssert::assert_floors`;
  - the single-valued fields (one damage type, at most two quick-cast pairs, each of the build's attributes) are `BuildAssert::assert_single_fields`;
  - DS-23 is `BuildAssert::assert_insignia` and `ModifierAssert::assert_piece`;
  - the lifecycle's condition id and duration checks are `TickAssert::assert_condition` and `assert_duration`.
- **Evidence**: the refusal tests keep their messages and pass (`test_floor_*`, `test_two_conditions_builder_refused`, the quick-cast and damage-type refusals). No `assert(` is left in `build` or `condition_duration`, nor in the lifecycle rules outside `TickAssert`.

### Quality 4: the load/store benchmark

- **Fix**: `test_cost_load_store_worst` now asserts that `store(load(words))` equals its input words, every member and goblin word, the clock and the kills. Its baseline, `test_cost_fixture_worst_words_twice`, builds the same two fixtures.
- **Evidence**: the old assertion, `words.goblins.len() == 100`, held for any output with 100 goblins, such as a `store` that dropped a member's hot field. The new one fails on any changed word. The round-trip equality holds (the test passes), which also pins `load` and `store` as exact inverses on the worst state.

### Escalations from fix loop 2

- **DS-23's record-to-item check.** The record's piece must equal the worn item's `BASE.slot`; that is `set_build`'s (CBT-02b, CBT-08).
- **The gas checker.** Expected-panic tests over their budget passed silently seven more times in this loop. `scripts/gas_budgets.py` should fail them; it is outside my allowlist.
- **The awake selection's 4.26M at the candidate bound.** It is for ENG-07 to weigh with the array's size, together with lever (a) (CBT-02b, D-161).

## Fix loop 3

Two audits of b5f068a:
- **Cost** (`[GPT-6-Astra]`): FAIL on COST-1 only; COST-2 is resolved.
- **Quality** (`[GPT-6-Sol]`): PASS WITH FINDINGS, one minor.

`origin/main` had nothing new. The fix is commit `4e4aa77`. CI is green on it (`gh run list`: ci and tooling `success` on `4e4aa77…`).

The checks:
- `gas_budgets.py --check`: 539 tests, every budget current.
- No `GAS.md` row with a negative margin: 0 in each of the three files.
- The logic tests pass (333), as do ephemeral's 53 and persistent's 153.
- Nothing else changes.

### COST-1: the worst case is now an **upper bound from per-term maxima**, not a claimed maximum

I did not prove a closed-form worst case; **the figure below is an upper bound**. Two reasons:
- **A lookup's cost grows with the record's position.** The audit's permutation (skills 40 and 42 exchanged) is one of many orderings that change it: every looked-up id cannot sit at the end of its list at once.
- **Step 1's branches differ by a few operations**, so which state is the true maximum hinges on micro-costs. Measured, a **lapse** costs more than the conclusion into a recovery that the old fixture used (1,083,413 against 1,069,720 per goblin), so the old fixture was not the maximum either.

**The bound's method.** Each term is measured at its own maximum, apart, and the terms are summed.

1. **The cost of one more comparison in each content list.** In the same content (38 skills, 5 castes, 4 potions), a lookup of the last record is measured against the first, and the difference is divided by the positions between:
   - skill (382,270 − 301,980) / 37 = **2,170**;
   - caste (312,460 − 302,580) / 4 = **2,470**;
   - potion (305,990 − 300,980) / 3 = **1,670**.
   - Tests: `test_cost_scan_{skill,caste,potion}_{first,last}`.
2. **The base.** The tick with no awake goblin: the member at its worst (concluding bar slot 7, 3 conditions, 4 regenerating effects, decaying, dying: step 5's defeat path) and the 100-goblin array, all frozen, each with a retained effect.
   - Dying costs 3,884,803; surviving 3,875,333; the bound takes the dying member.
   - Tests: `test_cost_bound_base`, `_member_alive`, and their fixtures.
3. **Each step-1 branch one awake goblin can take**, with every step-3 term active and dying, its lookups at the end of their lists (caste 5 is the last caste, skill 43 the last skill). The marginal over the base, net of each test's own fixture (every fixture measures 57,874,340):

   | Branch | Tick | Marginal |
   |---|---:|---:|
   | Lapse (FX-29) | 4,968,216 | **1,083,413** |
   | Conclusion clearing the field (`k` < `n` + 2) | 4,955,396 | 1,070,593 |
   | Conclusion into a recovery | 4,954,523 | 1,069,720 |
   | The same, surviving | 4,954,323 | 1,069,520 |
   | Recovery ending | 4,826,656 | 941,853 |
   | Free (acts in step 2) | 3,914,216 | 29,413 |
   | Activating (busy) | 3,907,313 | 22,510 |

   - Dying costs 200 more than surviving, so the dying variants are the maxima.
   - `test_branch_worlds_take_their_branch` checks that each state takes the branch it names.
4. **Additivity.** Every awake goblin's work is independent: its own branch, its own lookups, one rebuild of the 100-goblin array per write whichever goblin writes, and the Engaged scan already whole in the base. The check at the maximum, 8 goblins all lapsing (`test_cost_bound_eight_lapses`), measures **12,552,207** against the additive 12,552,107. The +100 is the goblins' interaction, for which the bound adds **1,000**.

**The tick's bound (pipeline only, `Idle` rules):**

| Term | L2 gas |
|---|---:|
| Base (the member at its worst, the 100-goblin array) | 3,884,803 |
| The member's one lookup charged as a full scan (skill 8 at position 8 of 38: 30 × 2,170) | 65,100 |
| 8 × the costliest branch (a lapse, its lookups already at their lists' ends) | 8,667,304 |
| The goblins' interaction | 1,000 |
| **Upper bound of a tick** | **12,618,207** |

States measured under it:
- the old fixture, 8 conclusions: 12,413,093;
- **the audit's permutation, `test_cost_tick_worst_permuted`: 12,425,803**;
- 8 lapses: 12,552,207.

A batch's every tick is under the same bound. `Busy` measures 11,961,127 a tick over 10 ticks.

**Load and store, once per call (bound):**

| Term | L2 gas |
|---|---:|
| Measured, the worst state's 101 actors (`test_cost_load_store_worst`, round trip asserted) | 59,921,060 |
| Every lookup of the load charged as a full scan: the goblins' caste-skill lookups at 35–38 (6 comparisons each, × 100), the member's bar at 1–8 (268), its skill effects at 7 and 8 (61) and its potions at 3 and 4 (1 potion comparison) | 2,017,600 |
| The member's two potion slots charged as the costlier skill branch at position 38. From `test_cost_load_member_{skills,potions}` and their matched fixtures (694,430 and 358,470 net): at most (335,960 / 4 + 1.5 × 2,170 + 1.5 × 1,670) = 89,750 a slot | 179,500 |
| **Upper bound of load and store** | **62,118,160** |

- The store is branch-free.
- A goblin's load has one branch, a retained effect, and every goblin holds one in the fixture.
- The library call, 2,578,020, has every count at its maximum (100 goblins, 38 skills, 5 castes, 4 potions); its calldata's size depends only on the counts.
- The awake set's selection, 4,264,890, is measured in its costliest order (argued in fix loop 2).

**Per tick inside a batch, bound:**
- the tick, 12,618,207;
- plus (62,118,160 + 2,578,020) / 10 = **19,087,825**;
- with the content's estimate (474,137): **≤ 19,561,962**;
- if ENG-07 runs the awake selection at every tick: ≤ 23,826,852.

The representative column is re-measured: 628,617 a tick; 961,079 through the library; 1,154,628 with the content.

ENG-01 §9.2 now states the worst column as this upper bound, in these words.

**Tests.** The new ones:
- `test_cost_bound_*` (18: the base, its member-alive variant, 7 branch variants, the 8 lapses, each with its fixture);
- `test_cost_scan_*` (6);
- `test_cost_load_member_*` (4);
- `test_cost_tick_worst_permuted` and its fixture;
- `test_branch_worlds_take_their_branch`.

Their budgets carry their measures. `test_cost_batch_worst` is re-set to its measure (177,535,330); its headroom had fallen to 0.03 %, too little under D-154.

**Evidence that c7effac's and b5f068a's claim fails.** A lapse is measured costlier than the conclusion the "worst" fixture used, and the audit's permutation is measured costlier than that fixture (12,425,803 > 12,413,093). The claim is withdrawn and replaced by the bound.

### The quality minor: checks in Assert impls, each actor's own errors

- **`types/world.cairo`**: `TickTrait::tick`'s goblin count and `TickTrait::awake`'s distance count are now `WorldAssert::assert_goblins` and `assert_distances`, with the module's `errors`.
- **`models/member.cairo`, `models/goblin.cairo`**: each has its own `errors` module (`REGEN`) and an Assert impl, `MemberAssert::assert_pips` and `GoblinAssert::assert_pips`.
  - `load` calls it before the conversion, as do the lifecycle's `hold` and `put`; those two converted pips with `unwrap` before, without a check.
  - `types::tick::errors::REGEN` is removed, since the models no longer import `types::tick`'s errors.
- **Tests, compiled only against the new API**: `test_world_assert_goblins` (101 goblins), `test_world_assert_distances`, `test_member_assert_pips` (128), `test_goblin_assert_pips` (−129).
- **Evidence**: no `assert(` or `expect(` outside an Assert impl in `types/world.cairo`, `models/member.cairo` or `models/goblin.cairo` (`grep`: the only four are in `WorldAssert`, `MemberAssert` and `GoblinAssert`).

### Still open, for the project manager

- **The bound is a bound.** A closed-form maximum is not proved, for the two reasons above; the bound's terms are each measured.
- **Its one assumption beyond the measures** is additivity across goblins. It rests on the code's structure (each awake goblin's work is independent) and is checked once at the maximum (+100 over 8 goblins, allowed 1,000).
- **Unchanged from earlier loops:** the gas checker for expected-panic tests, DS-23's record-to-item check (CBT-02b, CBT-08), and levers (a) to (e) (D-161).
