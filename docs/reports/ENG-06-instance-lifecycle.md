# [Opus 5.5] ENG-06 — The instance lifecycle: enter, resume, leave, close

## Summary

An adventurer can now **enter** a location from its hub, **resume** its instance from any device
(`instance_state`, `placement`), **leave** through a gate to a hub (Returned) or to the next
location (Moved: the next instance in the same slot, in the same invocation, with its entry draw),
**travel back** to its last hub, and **travel** between unlocked hubs. Every way out closes the
instance through one internal path, `Instances::InternalTrait::close`, which ENG-07's defeat calls
(`Outcome::Defeated`, tested by a unit test), and settles on `Hub.report`.

- `Hub`: `enter` (ownership, the gate from the registry and its requirements, the belt's reserve
  debited, the snapshot, `Instances.create`), `travel`, `report` (`IResults`, `Instances` only: the
  belt credited back on return and on defeat, E-15; the placement; a hub reached unlocked; gold,
  balances, experience; equipment, tasks and the other facts refused until their models exist),
  and D-144: `create_adventurer` places the adventurer in region 1's town read from the registry.
- `Instances`: `create` (`Hub` only: slot reused or new, generation + 1, the header, the entry draw
  `fate(poseidon(id, 0, ENTRY))`, the member's eight words, `⌈t/4⌉` task pages), `set_controller`
  (`Hub` only), `leave`, `travel_back`, the closing path, `instance_state`, `placement`.
- Gate actions check the caller (a revert: not a game refusal), then `Closed`, `Absent`,
  `Sequence`, then the gate (`Gate`) or the seal (`Sealed`), each a `Refused` event that changes
  nothing and draws nothing.
- A node probe runs the real `Registry`, `TxHashFate`, `Hub` and `Instances` together
  (`contracts/tools/lifecycle_probe.py`, output committed); D-145's call-versus-read measure is
  `contracts/persistent/tests/test_read_cost.cairo`.

The model named by the brief and the model of this session are the same: Opus 5.5.

Pull request: https://github.com/bal7hazar/grimworld/pull/120 (CI green on every check).

## Files changed

- `contracts/logic/src/content.cairo`: `exists(parts)`, the registry's existence rule.
- `contracts/logic/src/interface.cairo`: `facts` (the bits of `Results.facts`, `HUB_REACHED`).
- `contracts/logic/src/models/gate.cairo`: `anchor`, `entry`, `can_leave`; `GateAssert::assert_enterable`; errors.
- `contracts/logic/src/models/location.cairo`: `position(chunk, tile)`, `has_map`.
- `contracts/logic/src/professions.cairo`: base energy, pips and armor of each profession (design/03).
- `contracts/logic/src/snapshot.cairo`: `SnapshotTrait::new` (design/03's base stats).
- `contracts/persistent/src/models/adventurer.cairo`: place words (new, entered, moved, located, unlocked, the hub-bit table), core words (`profile`, `pack_lanes`, experience), `BeltTrait`, checks and errors.
- `contracts/persistent/src/models/balance.cairo` (new): pages of balances: amount, credit, debit, the belt's merge.
- `contracts/persistent/src/models.cairo`: declares `balance`.
- `contracts/persistent/src/types.cairo`, `types/results.cairo` (new): what `report` settles or refuses.
- `contracts/persistent/src/systems/hub.cairo`: `enter`, `travel`, `report`, the start hub (D-144), `change_pack`.
- `contracts/ephemeral/src/models/instance.cairo`: `PlacementTrait`, `HeaderTrait`, `HeaderAssert::refusal`, `QuotasTrait`, errors, `SEALED`.
- `contracts/ephemeral/src/models/member.cairo`: `MemberStateTrait::entering`, `maxima`, the empty words as stored, word offsets, errors.
- `contracts/ephemeral/src/systems/instances.cairo`: `create`, `set_controller`, `leave`, `travel_back`, `instance_state`, `placement`; `admit`, `begin`, `close`, `report`; the defeat unit test.
- `contracts/logic/tests/test_lifecycle.cairo` (new), `contracts/persistent/tests/test_lifecycle.cairo`, `test_words.cairo`, `test_read_cost.cairo` (new), `contracts/ephemeral/tests/test_lifecycle.cairo` (new).
- `contracts/persistent/tests/test_accounts.cairo`: a registry holding region 1 in the setup (D-144); budgets raised with their reason.
- `contracts/ephemeral/tests/test_instances.cairo`: formatting of its budget line only.
- `contracts/tools/lifecycle_probe.py`, `contracts/tools/lifecycle-probe-output.txt` (new).
- `contracts/{logic,persistent,ephemeral}/GAS.md`, `docs/BUDGETS.md`: generated.

## Commands run

```
$ scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
    Finished `dev` profile target(s) in 10 seconds
$ cd contracts/logic && snforge test        # through the budgets run below
$ cd contracts/persistent && snforge test
$ cd contracts/ephemeral && snforge test
    (225 tests in all, every one passing; each package's run piped into contracts/tools/set_budgets.py)
$ python3 scripts/gas_budgets.py --check
gas check: 225 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ python3 contracts/tools/class_sizes.py
| grimworld_ephemeral | `Instances` | 724,161 | 10,688 | 28,841 | 35.21 % | ok |
| grimworld_persistent | `Registry` | 158,206 | 2,271 | 5,318 | 6.49 % | ok |
| grimworld_persistent | `Hub` | 742,928 | 11,355 | 28,980 | 35.38 % | ok |
| (probes, Market, TxHashFate unchanged)
$ scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py > contracts/tools/lifecycle-probe-output.txt
    exit 0 (17 measured transactions, all SUCCEEDED; table below)
$ scarb --manifest-path contracts/Scarb.toml fmt --check      (clean)
$ gh pr checks 120                                              (every check pass)
```

The first CI run failed on formatting, the second on the gas check (the formatter had wrapped the
`// gas: raised` notes onto two lines, away from their attributes); both fixed, third run green.

## Each entrypoint's writes against ENG-01 §9.3

Counted by the tests (`load` before and after, value changes: a write of the value already stored
is no state change, ENG-01 §2.2 point 4) and by the node probe (the trace's state diff, each key
classified against every value the run wrote). N new, O overwritten, Z zeroed.

| Entrypoint | §9.3 | Tests (snforge) | Node probe | Difference, and why |
|---|---|---|---|---|
| `enter`, first entry | 19 N / 7 O | Instances 17 N / 1 O with 16 tasks, 13 N / 1 O without (`test_create_first_entry`, `test_create_without_tasks`); Hub 4 pages + `core` + `place` = 6 O (`test_enter_reserves_the_belt`) | Instances 13 N / 1 O, Hub 1 O (no belt, no task) | −2 N: the entry chunk's two words, ENG-05's reveal (`revealed` is written empty meanwhile, so no chunk of an earlier generation is reachable). Tasks: none sent until quiver is embedded (E-14); `create` writes `⌈t/4⌉` pages when they come. Belt: `set_build` does not exist yet, so the node cannot fill one |
| `enter`, later entry | 0 / 25 | 0 N and nothing zeroed (`test_create_reuses_the_slot`) | Instances 4 O changed (header, entropy, member state, placement), Hub 1 O | the same 23 keys written less the 2 chunk words; written with their own value: revealed, quotas, the empty words and the snapshot of the same build |
| `leave` / `travel_back` to a hub | 0 / 9 | Instances 3 O (`test_leave_to_a_hub`, `test_travel_back`); Hub 4 pages + `core` + `place` = 6 O (`test_report_returned_through_a_hub_gate`) | Instances 3 O, Hub 1 O (no belt) | none (the 5 belt keys when the belt holds potions) |
| `leave` to a location | 2 / 11 cold, 0 / 13 | Instances 9 written, 8 changed (`test_leave_to_a_location`); Hub `place` 1 O (`test_report_moved`) | Instances 5 O changed, Hub 1 O | −2: the entry chunk's words (ENG-05); −1: `H.core`, written only when experience comes (none on a gate) |
| `leave` / `travel_back` refused | none | 0 (`assert_refused`, every refusal) | none | — |
| `travel` | 0 / 1 | 1 O (`test_travel`) | none: the probe travels to the hub it stands in | — |
| `set_controller` | 1 O each | 1 O (`test_set_controller`) | 1 O per adventurer inside | — |
| `set_account_owner`, k inside | 1 / 9 at 7 | (ENG-04's tests, double) | Hub 1 N / 1 O / 1 Z, Instances k O, k = 0 to 3 | — |
| `create_adventurer` | 7 / 2, 6 / 3 | unchanged (`test_create_adventurer`) | 7 N / 2 O, 6 N / 3 O | — |

## Gas against ENG-01 §10

The node's receipts (M). The local node's fixed part is 1,006,080 against §10's Sepolia floor
F = 816,939 (ENG-04's finding): "net" subtracts the 189,141 difference (D). Calls counted from the
code.

| Entrypoint, case | Node L2 (M) | Net of the floor (D) | §10 target | Net against §10 | Calls (§10) |
|---|---:|---:|---:|---:|---|
| `enter`, first entry, cold, no belt, no task | 10,048,400 | 9,859,259 | 11,768,186 | −16.2 % | 5 (4) |
| `enter`, later entry, no belt | 4,262,400 | 4,073,259 | 3,728,526 | **+9.2 %** | 5 (4) |
| `leave` to a hub, no belt | 2,502,400 | 2,313,259 | 1,954,739 | **+18.3 %** | 2 (1) |
| `leave` to a location | 3,272,640 | 3,083,499 | 3,667,902 | −15.9 % | 4 (3) |
| `travel_back`, no belt | 2,297,280 | 2,108,139 | 1,954,739 | **+7.8 %** | 1 (1) |
| `travel` (to the hub it is in: no write) | 1,226,560 | 1,037,419 | 1,005,587 | +3.2 % | 0 (0) |
| `leave` refused (sequence) | 1,292,160 | 1,103,019 | — | — | 0 |
| `create_adventurer`, cold (D-144) | 4,894,960 | 4,705,819 | 4,501,991 | +4.5 % | 1 (1) |
| `create_adventurer`, initialised | 4,532,960 | 4,343,819 | 4,080,539 | +6.5 % | 1 (1) |
| `set_account_owner`, 0 / 1 / 2 / 3 inside | 1,882,960 / 2,162,960 / 2,482,960 / 2,802,960 | — | — | — | k |
| `set_account_owner`, 7 inside (D: 3 inside + 4 × 320,000) | 4,082,960 | 3,893,819 | 2,721,351 (D-144 proposed 3,700,000) | +43 % (+5.2 % on D-144's) | 7 (7) |

`create_adventurer` costs 200,000 more than ENG-04's 4,694,960: the registry call of D-144, which
§10 had already counted.

**The belt's worst case** could not run on the node (no `set_build`). In snforge (M, the call
measured with `get_available_gas` around it, `Instances` a double): `enter` 1,583,170 without a
belt, 2,104,910 with four items on four pages each emptied (**+521,740**); `report` of a move
274,613, of a return crediting four pages 1,042,929 (**+768,316**, which also holds the
`AdventurerLocated` and the located place, so an upper bound). snforge prices storage above the
node, so these are upper bounds (E). §10's model of the same keys is 5 × O = 160,360 plus their
reads. With them, a later `enter` is at most about 4.60 M net (+23 %), `leave` to a hub and
`travel_back` at most about 3.08 M and 2.88 M net (+58 %, +47 %).

The same calls in snforge (M, `get_available_gas` around the call; doubles for the other
contracts): `create` first entry with 16 tasks 2,884,026, later entry 2,813,216; `leave` to a hub
1,434,470, to a location 2,428,666; `travel_back` 1,230,063; `set_controller` 221,200; a refused
`leave` 353,000; Hub `travel` 280,873.

## Generation isolation (AC-2)

- `test_generation_isolation` (ephemeral): generation 1 closes; every word of slot 1 is filled
  with stale data (entropy, revealed, quotas, the four task pages, the four roster pages with 15
  entries each, the member's state, timers with an activation and conditions, effects, recharges,
  the chunk words of chunks 0, 16 and 112) and the header claims 60 roster entries and 200 chunks
  revealed. Generation 2 is created with one task: the header's counts are reset, `revealed` is
  empty, the quotas fresh, the entropy new, one task page holding the new task, no roster page,
  no chunk and no goblin, the member's eight words fresh. Then one roster entry is appended (as
  ENG-07 will): the view shows that entry and zeros in the fourteen lanes the stale page holds.
  The old id's view answers nothing; id 0 answers nothing.
- `test_leave_to_a_location`: conditions, effects, recharges, an activation, lost health and
  energy, adrenaline and hits set before a gate are all gone in the next instance; only the belt's
  counts carry (E-13's F-12 case, D-141 E-20).
- `test_create_reuses_the_slot`: the slot is reused (no new slot, no new key); a second adventurer
  takes the next slot.
- `test_refused_closed`: an id of an earlier generation is refused `Closed`.

## Records read, and the call against the read (AC-4, D-145)

These entrypoints do not carry the content version (design/02), so they read with `record`, not
`bundle`: `bundle` would add the version's read (20,010, ENG-03) for nothing.

| Invocation | Records read | Calls to `Registry` | Slots |
|---|---|---:|---:|
| `create_adventurer` | `REGION` 1 (D-144) | 1 | 1 |
| `enter`: `Hub` | `GATE` g | 1 | 1 |
| `enter`: `Instances.create` | `GATE` g, then `LOCATION` of its destination | 2 | 3 |
| `leave` to a hub | `GATE` g | 1 | 1 |
| `leave` to a location | `GATE` g, then `LOCATION` of its destination | 2 | 3 |
| `travel_back`, `travel`, `report`, `set_controller`, `set_account_owner` | none | 0 | 0 |

The location's id is in the gate, so it cannot be asked in the same call. `create` needs the
location for `N` (quotas) and the seal (header), and ENG-05's reveal of the entry chunk will need
it whole.

The measure (`test_read_cost.cairo`, snforge, M: the probe's one call measured around it; one-part
`GATE` records):

| Case | L2 gas |
|---|---:|
| the probe alone (the test's call to it) | 84,340 |
| + 1 read of its own storage | 115,810 |
| + 8 reads of its own storage | 303,410 (26,800 a read) |
| one call to `Registry` reading the version | 199,420 |
| one `bundle` of 1 / 2 / 8 records | 277,950 / 331,970 / 656,090 (54,020 a record) |
| 2 / 8 calls of `record`, one record each | 393,340 / 1,307,980 (152,440 a record) |

So (D): a record added to a call already made costs 54,020 (one part; ENG-03's 36,000 a slot is
the same for three-part records, whose key is hashed once); a record read by a call of its own
costs 152,440: **the call is about 98,420**, and it is not in the per-slot price at all. Of the
54,020, a storage read with its address hash is about 26,800; the rest is the record's key (two
Pedersen hashes) and the felts moved across the call boundary. D-145's condition holds: an
invocation should read its records in one call; ENG-06's two sequential reads in `create` and in
`leave` to a location cost one extra call each (escalated).

## Acceptance criteria

- [x] AC-1: `test_create_first_entry`, `test_create_without_tasks`, `test_create_reuses_the_slot`,
  `test_create_sealed`, `test_leave_to_a_hub`, `test_leave_to_a_location`, `test_travel_back`,
  `test_generation_isolation` (`instance_state`), `test_enter`, `test_travel`, `test_report_*`.
  Refusals: `test_create_refusals` (not the hub, too many tasks, no gate, no location, a hub as
  destination, already inside), `test_refused_sequence`, `test_refused_closed`,
  `test_refused_absent`, `test_refused_gate` (nine gates), `test_refused_sealed`,
  `test_not_controller`, `test_set_controller`, `test_enter_refusals` (owner, adventurer, gate
  none, not here, floor, Rift, rank, quest, the belt not in the pack, inside, deleted),
  `test_start_hub_refusals`, `test_report_refusals`. Every gate-action refusal is checked for no
  write, no draw (the fate double counts draws), no report, and its `Refused` event.
- [x] AC-2: above.
- [x] AC-3: the write tables above (tests and probe); gas against §10 above; overruns on the
  expedition's path escalated to the project manager (E-1 below).
- [x] AC-4: the records and the measure above.
- [x] AC-5: `test_start_hub_from_the_registry`, `test_start_hub_refusals`; `set_account_owner`
  measured on the node with the real `set_controller` at 0 to 3 inside, 7 derived (escalated,
  E-2).
- [x] AC-6: models, types and helpers scoped in traits, checks in `Assert` impls, an `errors`
  module per file that reverts; one free function added (`content::exists`, with its reason
  written: the registry's rule, owned by no model). CI green; `gas_budgets.py --check` passes;
  `class_sizes.py` passes (escalated, E-3).

## Cost

Printed by `python3 scripts/gas_budgets.py --report` (origin/main fetched). Every raised budget is
a pre-existing test of ENG-04 whose setup now deploys a `Registry` and whose `create_adventurer`
reads it (D-144).

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::systems::instances::close_tests::test_close_on_defeat | — | 4799530 | 5039507 | new |
| grimworld_ephemeral::systems::instances::layout_tests::test_instances_storage_addresses | 184040 | 184040 | 193242 | unchanged |
| grimworld_ephemeral::test_admin::test_instances_set_admin_hands_over | 3474760 | 3474760 | 3648498 | unchanged |
| grimworld_ephemeral::test_admin::test_instances_set_admin_refused | 2999520 | 2999520 | 3149496 | unchanged |
| grimworld_ephemeral::test_admin::test_instances_set_contracts_by_admin | 2837290 | 2837290 | 2979155 | unchanged |
| grimworld_ephemeral::test_admin::test_instances_set_contracts_refused_to_others | 2733090 | 2733090 | 2869745 | unchanged |
| grimworld_ephemeral::test_events::test_instances_event_keys_and_data | 205040 | 205040 | 215292 | unchanged |
| grimworld_ephemeral::test_events::test_per_action_event_keys_and_data | 59100 | 59100 | 62055 | unchanged |
| grimworld_ephemeral::test_instances::test_instances_deploys_and_stubs_revert | 2650960 | 2650960 | 2783298 | unchanged |
| grimworld_ephemeral::test_instances::test_probe_events_eight_killed | 736580 | 736580 | 773409 | unchanged |
| grimworld_ephemeral::test_instances::test_probe_events_four_revealed | 442850 | 442850 | 464993 | unchanged |
| grimworld_ephemeral::test_instances::test_probe_events_none | 282660 | 282660 | 296793 | unchanged |
| grimworld_ephemeral::test_instances::test_probe_read_direct | 5095200 | 5095200 | 5349960 | unchanged |
| grimworld_ephemeral::test_instances::test_probe_read_through_a_call | 5213110 | 5213110 | 5473766 | unchanged |
| grimworld_ephemeral::test_layout::test_chunk_layout | 357000 | 357000 | 374850 | unchanged |
| grimworld_ephemeral::test_layout::test_deadline_boundaries | 321190 | 321190 | 337250 | unchanged |
| grimworld_ephemeral::test_layout::test_empty_timers_packed | 173400 | 173400 | 182070 | unchanged |
| grimworld_ephemeral::test_layout::test_goblin_deadline_above_28_bits_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_ephemeral::test_layout::test_goblin_layout | 322870 | 322870 | 339014 | unchanged |
| grimworld_ephemeral::test_layout::test_member_deadline_past_max_clock_refused | 47230 | 47230 | 49592 | unchanged |
| grimworld_ephemeral::test_layout::test_member_layout | 482580 | 482580 | 506709 | unchanged |
| grimworld_ephemeral::test_layout::test_pack_offsets_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_ephemeral::test_layout::test_placement_and_header_layout | 445250 | 445250 | 467513 | unchanged |
| grimworld_ephemeral::test_layout::test_recharge_above_28_bits_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_ephemeral::test_layout::test_record_sizes | 13720 | 13720 | 14406 | unchanged |
| grimworld_ephemeral::test_layout::test_roster_masking | 328620 | 328620 | 345051 | unchanged |
| grimworld_ephemeral::test_layout::test_walls_above_224_refused | 17720 | 17720 | 18606 | unchanged |
| grimworld_ephemeral::test_lifecycle::test_create_first_entry | — | 31631012 | 33212563 | new |
| grimworld_ephemeral::test_lifecycle::test_create_refusals | — | 32573826 | 34202518 | new |
| grimworld_ephemeral::test_lifecycle::test_create_reuses_the_slot | — | 43967391 | 46165761 | new |
| grimworld_ephemeral::test_lifecycle::test_create_sealed | — | 25833696 | 27125381 | new |
| grimworld_ephemeral::test_lifecycle::test_create_without_tasks | — | 27762006 | 29150107 | new |
| grimworld_ephemeral::test_lifecycle::test_generation_isolation | — | 41891115 | 43985671 | new |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_hub | — | 33175476 | 34834250 | new |
| grimworld_ephemeral::test_lifecycle::test_leave_to_a_location | — | 39121427 | 41077499 | new |
| grimworld_ephemeral::test_lifecycle::test_not_controller | — | 27966354 | 29364672 | new |
| grimworld_ephemeral::test_lifecycle::test_refused_absent | — | 40143332 | 42150499 | new |
| grimworld_ephemeral::test_lifecycle::test_refused_closed | — | 38055615 | 39958396 | new |
| grimworld_ephemeral::test_lifecycle::test_refused_gate | — | 58509716 | 61435202 | new |
| grimworld_ephemeral::test_lifecycle::test_refused_sealed | — | 29068609 | 30522040 | new |
| grimworld_ephemeral::test_lifecycle::test_refused_sequence | — | 33019086 | 34670041 | new |
| grimworld_ephemeral::test_lifecycle::test_set_controller | — | 32926602 | 34572933 | new |
| grimworld_ephemeral::test_lifecycle::test_travel_back | — | 31486399 | 33060719 | new |
| grimworld_logic::test_actions::test_batch_layout | 120610 | 120610 | 126641 | unchanged |
| grimworld_logic::test_actions::test_batch_refusals | 102710 | 102710 | 107846 | unchanged |
| grimworld_logic::test_actions::test_batch_round_trip | 368360 | 368360 | 386778 | unchanged |
| grimworld_logic::test_actions::test_encoder_refusals | 40480 | 40480 | 42504 | unchanged |
| grimworld_logic::test_durations::test_base_above_cap_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_durations::test_effective_duration_maximum | 13720 | 13720 | 14406 | unchanged |
| grimworld_logic::test_exp2::test_assert_covered | 13720 | 13720 | 14406 | unchanged |
| grimworld_logic::test_exp2::test_assert_covered_above_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_exp2::test_assert_covered_below_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_exp2::test_bench_lookup | 19160 | 19160 | 20118 | unchanged |
| grimworld_logic::test_exp2::test_clamp_ends | 20850 | 20850 | 21893 | unchanged |
| grimworld_logic::test_exp2::test_every_entry_and_clamp | 2901800 | 2901800 | 3046890 | unchanged |
| grimworld_logic::test_exp2::test_octaves_exact | 23960 | 23960 | 25158 | unchanged |
| grimworld_logic::test_fate::test_derive_distinct_per_domain_and_index | 3325820 | 3325820 | 3492111 | unchanged |
| grimworld_logic::test_fate::test_derive_fuzz | 1054980 | 1054980 | 1107729 | unchanged |
| grimworld_logic::test_fate::test_derive_oracle | 56600 | 56600 | 59430 | unchanged |
| grimworld_logic::test_fate::test_domain_binds_subject_and_counter | 98770 | 98770 | 103709 | unchanged |
| grimworld_logic::test_fate::test_purposes_distinct | 369296 | 369296 | 387761 | unchanged |
| grimworld_logic::test_hexmap::test_hexmap_distance | 13720 | 13720 | 14406 | unchanged |
| grimworld_logic::test_lifecycle::test_can_leave | — | 62090 | 65195 | new |
| grimworld_logic::test_lifecycle::test_enterable | — | 13720 | 14406 | new |
| grimworld_logic::test_lifecycle::test_enterable_elsewhere | — | 15520 | 16296 | new |
| grimworld_logic::test_lifecycle::test_enterable_floor | — | 15520 | 16296 | new |
| grimworld_logic::test_lifecycle::test_enterable_quest | — | 15520 | 16296 | new |
| grimworld_logic::test_lifecycle::test_enterable_rank | — | 15520 | 16296 | new |
| grimworld_logic::test_lifecycle::test_has_map | — | 32960 | 34608 | new |
| grimworld_logic::test_lifecycle::test_position | — | 13720 | 14406 | new |
| grimworld_logic::test_lifecycle::test_snapshot | — | 13720 | 14406 | new |
| grimworld_logic::test_lifecycle::test_snapshot_of_no_profession | — | 15520 | 16296 | new |
| grimworld_logic::test_models::test_gate_anchor_chunk_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_gate_anchor_tile_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_gate_entry_chunk_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_gate_entry_tile_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_gate_round_trip | 200400 | 200400 | 210420 | unchanged |
| grimworld_logic::test_models::test_location_bits | 237140 | 237140 | 248997 | unchanged |
| grimworld_logic::test_models::test_location_entry_chunk_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_location_entry_tile_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_location_height_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_location_round_trip | 728590 | 728590 | 765020 | unchanged |
| grimworld_logic::test_models::test_location_width_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_outline_above_bit_224_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_models::test_outline_round_trip | 29780 | 29780 | 31269 | unchanged |
| grimworld_logic::test_models::test_region_name_too_long | 24470 | 24470 | 25694 | unchanged |
| grimworld_logic::test_models::test_region_round_trip | 87480 | 87480 | 91854 | unchanged |
| grimworld_logic::test_packing::test_bar_and_kit_layout | 212440 | 212440 | 223062 | unchanged |
| grimworld_logic::test_packing::test_bitmap | 20570 | 20570 | 21599 | unchanged |
| grimworld_logic::test_packing::test_bitmap_above_249_refused | 17720 | 17720 | 18606 | unchanged |
| grimworld_logic::test_packing::test_counter_never_zero | 18360 | 18360 | 19278 | unchanged |
| grimworld_logic::test_packing::test_identifiers | 19050 | 19050 | 20003 | unchanged |
| grimworld_logic::test_packing::test_join_refuses_live_overflow | 15520 | 15520 | 16296 | unchanged |
| grimworld_logic::test_packing::test_lanes16 | 430370 | 430370 | 451889 | unchanged |
| grimworld_logic::test_packing::test_lanes32 | 111450 | 111450 | 117023 | unchanged |
| grimworld_logic::test_packing::test_stats_layout | 302860 | 302860 | 318003 | unchanged |
| grimworld_logic::test_packing::test_task_page_layout | 142250 | 142250 | 149363 | unchanged |
| grimworld_persistent::systems::hub::layout_tests::test_hub_storage_addresses | 257780 | 257780 | 270669 | unchanged |
| grimworld_persistent::systems::market::layout_tests::test_market_storage_addresses | 62770 | 62770 | 65909 | unchanged |
| grimworld_persistent::systems::registry::detection_cost_tests::test_detection_cost_changed | 1524720 | 1524720 | 1600956 | unchanged |
| grimworld_persistent::systems::registry::detection_cost_tests::test_detection_cost_changed_blind | 1465410 | 1465410 | 1538681 | unchanged |
| grimworld_persistent::systems::registry::detection_cost_tests::test_detection_cost_identical | 1387530 | 1387530 | 1456907 | unchanged |
| grimworld_persistent::systems::registry::detection_cost_tests::test_detection_cost_identical_blind | 1465410 | 1465410 | 1538681 | unchanged |
| grimworld_persistent::systems::registry::detection_cost_tests::test_detection_cost_stored_baseline | 1288420 | 1288420 | 1352841 | unchanged |
| grimworld_persistent::systems::registry::layout_tests::test_part_address_is_the_maps | 177360 | 177360 | 186228 | unchanged |
| grimworld_persistent::systems::registry::layout_tests::test_registry_storage_addresses | 55520 | 55520 | 57981 | unchanged |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_baseline | 13720 | 13720 | 14406 | unchanged |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_raise | 482920 | 482920 | 507066 | unchanged |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_raise_again | 490140 | 490140 | 514647 | unchanged |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_read | 34650 | 34650 | 36383 | unchanged |
| grimworld_persistent::systems::registry::version_cost_tests::test_version_cost_stored_baseline | 422940 | 422940 | 444087 | unchanged |
| grimworld_persistent::test_accounts::test_create_adventurer | 21147480 | 23814770 | 25005509 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +12.6 % |
| grimworld_persistent::test_accounts::test_create_bad_profession_refused | 6900080 | 9182290 | 9641405 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +33.1 % |
| grimworld_persistent::test_accounts::test_create_empty_name_refused | 6851820 | 9183540 | 9642717 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +34.0 % |
| grimworld_persistent::test_accounts::test_create_no_free_slot_refused | 16446570 | 19362540 | 20330667 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +17.7 % |
| grimworld_persistent::test_accounts::test_create_without_account_refused | 5212240 | 7543960 | 7921158 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +44.7 % |
| grimworld_persistent::test_accounts::test_delete_across_pages | 36972610 | 40808400 | 42848820 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +10.4 % |
| grimworld_persistent::test_accounts::test_delete_after_the_pack_was_emptied | 11433700 | 13906240 | 14601552 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +21.6 % |
| grimworld_persistent::test_accounts::test_delete_equipped_refused | 10438070 | 12910610 | 13556141 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +23.7 % |
| grimworld_persistent::test_accounts::test_delete_frees_the_slot_and_marks_the_record | 24935240 | 27992030 | 29391632 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +12.3 % |
| grimworld_persistent::test_accounts::test_delete_negative_delta | 21169910 | 24226700 | 25438035 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +14.4 % |
| grimworld_persistent::test_accounts::test_delete_pack_balances_refused | 10519250 | 12991790 | 13641380 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +23.5 % |
| grimworld_persistent::test_accounts::test_delete_pack_equipment_refused | 10841840 | 13314380 | 13980099 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +22.8 % |
| grimworld_persistent::test_accounts::test_delete_pack_gold_refused | 10818350 | 13290890 | 13955435 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +22.9 % |
| grimworld_persistent::test_accounts::test_delete_the_last_listed | 18295400 | 21157440 | 22215312 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +15.6 % |
| grimworld_persistent::test_accounts::test_delete_within_the_final_page | 45206030 | 49431320 | 51902886 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +9.3 % |
| grimworld_persistent::test_accounts::test_delete_worst_three_slots | 20956730 | 23818770 | 25009709 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +13.7 % |
| grimworld_persistent::test_accounts::test_delete_worst_two_pages | 37026310 | 40862100 | 42905205 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +10.4 % |
| grimworld_persistent::test_accounts::test_helper_deleted | 14284470 | 16951760 | 17799348 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +18.7 % |
| grimworld_persistent::test_accounts::test_helper_no_adventurer | 10838270 | 13310810 | 13976351 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +22.8 % |
| grimworld_persistent::test_accounts::test_helper_not_in_a_hub | 10444160 | 12916700 | 13562535 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +23.7 % |
| grimworld_persistent::test_accounts::test_helper_not_owner | 15932870 | 18600160 | 19530168 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +16.7 % |
| grimworld_persistent::test_accounts::test_playable_professions | 13720 | 13720 | 14406 | unchanged |
| grimworld_persistent::test_accounts::test_register | 12592500 | 14870290 | 15613805 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +18.1 % |
| grimworld_persistent::test_accounts::test_register_twice_refused | 6748230 | 9026020 | 9477321 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +33.8 % |
| grimworld_persistent::test_accounts::test_set_account_owner | 24524970 | 27387010 | 28756361 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +11.7 % |
| grimworld_persistent::test_accounts::test_set_account_owner_only_those_inside | 18246500 | 21108540 | 22163967 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +15.7 % |
| grimworld_persistent::test_accounts::test_set_account_owner_rolled_back_when_set_controller_reverts | 18736780 | 21413900 | 22484595 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +14.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_seven_inside | 39069190 | 42710230 | 44845742 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +9.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_an_account_holder_refused | 12208770 | 14681310 | 15415376 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +20.3 % |
| grimworld_persistent::test_accounts::test_set_account_owner_to_zero_refused | 10243060 | 12715600 | 13351380 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +24.1 % |
| grimworld_persistent::test_accounts::test_set_account_owner_wrong_caller_refused | 10569290 | 13041830 | 13693922 | raised: the setup deploys a `Registry`; `create_adventurer` reads it (D-144, ENG-06); +23.4 % |
| grimworld_persistent::test_accounts::test_stored_words | 570170 | 579000 | 607950 | raised: the new place is computed from region 1's town (D-144, ENG-06); +1.5 % |
| grimworld_persistent::test_admin::test_hub_set_admin_hands_over | 4895740 | 4895740 | 5140527 | unchanged |
| grimworld_persistent::test_admin::test_hub_set_admin_refused | 4359910 | 4359910 | 4577906 | unchanged |
| grimworld_persistent::test_admin::test_hub_set_contracts_by_admin | 4245460 | 4245460 | 4457733 | unchanged |
| grimworld_persistent::test_admin::test_hub_set_contracts_refused_to_others | 4106290 | 4106290 | 4311605 | unchanged |
| grimworld_persistent::test_contracts::test_fate_refuses_mainnet_calls | 388601 | 388601 | 408032 | unchanged |
| grimworld_persistent::test_contracts::test_fate_refuses_mainnet_deployment | 272510 | 272510 | 286136 | unchanged |
| grimworld_persistent::test_contracts::test_fate_word | 397644 | 397644 | 417527 | unchanged |
| grimworld_persistent::test_contracts::test_hub_deploys_and_stubs_revert | 4001730 | 4001730 | 4201817 | unchanged |
| grimworld_persistent::test_contracts::test_market_and_registry_deploy | 3706010 | 3706010 | 3891311 | unchanged |
| grimworld_persistent::test_events::test_hub_events | 81630 | 81630 | 85712 | unchanged |
| grimworld_persistent::test_events::test_market_events | 78760 | 78760 | 82698 | unchanged |
| grimworld_persistent::test_fate::test_fate_anyone_gets_only_their_domain | 746048 | 746048 | 783351 | unchanged |
| grimworld_persistent::test_fate::test_fate_at_the_configured_address | 4706656 | 4706656 | 4941989 | unchanged |
| grimworld_persistent::test_fate::test_fate_deterministic_per_transaction_and_domain | 965838 | 965838 | 1014130 | unchanged |
| grimworld_persistent::test_fate::test_fate_values_distinct_through_derive | 3427106 | 3427106 | 3598462 | unchanged |
| grimworld_persistent::test_layout::test_account_and_adventurer_layout | 319110 | 319110 | 335066 | unchanged |
| grimworld_persistent::test_layout::test_attributes_above_36_bits_refused | 41350 | 41350 | 43418 | unchanged |
| grimworld_persistent::test_layout::test_item_grimoire_rift_layout | 325140 | 325140 | 341397 | unchanged |
| grimworld_persistent::test_layout::test_market_layout | 197570 | 197570 | 207449 | unchanged |
| grimworld_persistent::test_layout::test_pairs_overflow_refused | 15520 | 15520 | 16296 | unchanged |
| grimworld_persistent::test_layout::test_record_sizes | 13720 | 13720 | 14406 | unchanged |
| grimworld_persistent::test_lifecycle::test_enter | — | 35725410 | 37511681 | new |
| grimworld_persistent::test_lifecycle::test_enter_one_debit_per_item | — | 31350460 | 32917983 | new |
| grimworld_persistent::test_lifecycle::test_enter_refusals | — | 43623030 | 45804182 | new |
| grimworld_persistent::test_lifecycle::test_enter_reserves_the_belt | — | 34444070 | 36166274 | new |
| grimworld_persistent::test_lifecycle::test_report_moved | — | 35432851 | 37204494 | new |
| grimworld_persistent::test_lifecycle::test_report_open | — | 34922652 | 36668785 | new |
| grimworld_persistent::test_lifecycle::test_report_refusals | — | 35474424 | 37248146 | new |
| grimworld_persistent::test_lifecycle::test_report_returned_through_a_hub_gate | — | 35115149 | 36870907 | new |
| grimworld_persistent::test_lifecycle::test_report_to_the_last_hub | — | 36235922 | 38047719 | new |
| grimworld_persistent::test_lifecycle::test_start_hub_from_the_registry | — | 24625590 | 25856870 | new |
| grimworld_persistent::test_lifecycle::test_start_hub_refusals | — | 28231460 | 29643033 | new |
| grimworld_persistent::test_lifecycle::test_travel | — | 33018237 | 34669149 | new |
| grimworld_persistent::test_read_cost::test_read_cost_baseline | — | 8252020 | 8664621 | new |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_1 | — | 8452580 | 8875209 | new |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_2 | — | 8506600 | 8931930 | new |
| grimworld_persistent::test_read_cost::test_read_cost_bundle_8 | — | 8830720 | 9272256 | new |
| grimworld_persistent::test_read_cost::test_read_cost_eight_calls | — | 9501170 | 9976229 | new |
| grimworld_persistent::test_read_cost::test_read_cost_local_1 | — | 8290920 | 8705466 | new |
| grimworld_persistent::test_read_cost::test_read_cost_local_8 | — | 8478250 | 8902163 | new |
| grimworld_persistent::test_read_cost::test_read_cost_one_call_one_read | — | 8385450 | 8804723 | new |
| grimworld_persistent::test_read_cost::test_read_cost_two_calls | — | 8579870 | 9008864 | new |
| grimworld_persistent::test_registry::test_bundle_version_and_order | 7127060 | 7127060 | 7483413 | unchanged |
| grimworld_persistent::test_registry::test_gas_bundle_1 | 2646390 | 2646390 | 2778710 | unchanged |
| grimworld_persistent::test_registry::test_gas_bundle_10 | 15102750 | 15102750 | 15857888 | unchanged |
| grimworld_persistent::test_registry::test_gas_bundle_32 | 45551630 | 45551630 | 47829212 | unchanged |
| grimworld_persistent::test_registry::test_gas_deploy | 713240 | 713240 | 748902 | unchanged |
| grimworld_persistent::test_registry::test_gas_records_1 | 2624840 | 2624840 | 2756082 | unchanged |
| grimworld_persistent::test_registry::test_gas_set_record_changed | 3682770 | 3682770 | 3866909 | unchanged |
| grimworld_persistent::test_registry::test_gas_set_record_new | 3199720 | 3199720 | 3359706 | unchanged |
| grimworld_persistent::test_registry::test_gas_set_record_unchanged | 3479850 | 3479850 | 3653843 | unchanged |
| grimworld_persistent::test_registry::test_missing_record_reads_zeros | 2943360 | 2943360 | 3090528 | unchanged |
| grimworld_persistent::test_registry::test_reads_bounded | 4820310 | 4820310 | 5061326 | unchanged |
| grimworld_persistent::test_registry::test_set_admin_hands_over | 3037050 | 3037050 | 3188903 | unchanged |
| grimworld_persistent::test_registry::test_set_admin_refused | 2718460 | 2718460 | 2854383 | unchanged |
| grimworld_persistent::test_registry::test_set_record_composite_needs_parent | 7068530 | 7068530 | 7421957 | unchanged |
| grimworld_persistent::test_registry::test_set_record_existing_changes | 4474080 | 4474080 | 4697784 | unchanged |
| grimworld_persistent::test_registry::test_set_record_id_zero_refused | 1171760 | 1171760 | 1230348 | unchanged |
| grimworld_persistent::test_registry::test_set_record_new_sequential | 4405610 | 4405610 | 4625891 | unchanged |
| grimworld_persistent::test_registry::test_set_record_not_live_refused | 2101080 | 2101080 | 2206134 | unchanged |
| grimworld_persistent::test_registry::test_set_record_not_next_refused | 3235250 | 3235250 | 3397013 | unchanged |
| grimworld_persistent::test_registry::test_set_record_outline_chunk_refused | 4191460 | 4191460 | 4401033 | unchanged |
| grimworld_persistent::test_registry::test_set_record_part_count_refused | 1646650 | 1646650 | 1728983 | unchanged |
| grimworld_persistent::test_registry::test_set_record_quiver_ids | 3604410 | 3604410 | 3784631 | unchanged |
| grimworld_persistent::test_registry::test_set_record_quotas_keyed_by_location | 5339330 | 5339330 | 5606297 | unchanged |
| grimworld_persistent::test_registry::test_set_record_refused_to_others | 1262730 | 1262730 | 1325867 | unchanged |
| grimworld_persistent::test_registry::test_set_record_unknown_kind_refused | 1209960 | 1209960 | 1270458 | unchanged |
| grimworld_persistent::test_registry::test_upgrade_stub | 818220 | 818220 | 859131 | unchanged |
| grimworld_persistent::test_registry::test_version_rises_per_changed_record | 8363030 | 8363030 | 8781182 | unchanged |
| grimworld_persistent::test_seed::test_gas_seed_baseline | 5897700 | 5897700 | 6192585 | unchanged |
| grimworld_persistent::test_seed::test_gas_seed_write | 19432660 | 19432660 | 20404293 | unchanged |
| grimworld_persistent::test_seed::test_seed_rewritten_unchanged | 28039790 | 28039790 | 29441780 | unchanged |
| grimworld_persistent::test_seed::test_seed_written_and_read_back | 21464410 | 21464410 | 22537631 | unchanged |
| grimworld_persistent::test_words::test_balance_pages | — | 278120 | 292026 | new |
| grimworld_persistent::test_words::test_belt_merge | — | 518560 | 544488 | new |
| grimworld_persistent::test_words::test_belt_word | — | 86170 | 90479 | new |
| grimworld_persistent::test_words::test_core_words | — | 172950 | 181598 | new |
| grimworld_persistent::test_words::test_credit_overflow_refused | — | 45400 | 47670 | new |
| grimworld_persistent::test_words::test_debit_too_much_refused | — | 45100 | 47355 | new |
| grimworld_persistent::test_words::test_experience_overflow_refused | — | 74560 | 78288 | new |
| grimworld_persistent::test_words::test_place_hub_above_63_refused | — | 22650 | 23783 | new |
| grimworld_persistent::test_words::test_place_words | — | 2552765 | 2680404 | new |

## Deviations from the brief

- **The entry chunk is not written by `create`** (the brief: "say what `create` writes for it
  until then"): `revealed` is written empty (`LIVE`), `revealed_count` 0, no chunk word. A chunk is
  read only through `revealed` (§2.1), so no chunk of an earlier generation is reachable. ENG-05
  sets the entry chunk's bit and writes its two words in the same invocation (§9.3's 2 chunk keys).
  `Quotas` holds the location's `N` and nothing else until ENG-05's `QUOTAS` layout.
- **Reads use `record`, not `bundle`**: these entrypoints carry no content version, so the
  version's read would be paid for nothing (see AC-4).
- **A caller who does not control the member reverts** (`'not controller'`), rather than a
  `Refused`: `Refusal` has no variant for it, and access control is not a refusal of the game
  (design/02: "no revert for invalidity in the game"). Every other refusal of `leave` and
  `travel_back` is a `Refused` event.
- **`Header.status` `MOVED` is never stored**: through a link the slot's header becomes the next
  generation's in the same invocation; `InstanceClosed { outcome: Moved }` says it.
- **`Results.hub` 0 means "its last hub"** (travel back, defeat: D-04): `Instances` does not know
  the adventurer's last hub; `Hub.report` resolves it. A hub gate reports its destination and
  `HUB_REACHED` with `location` the hub.
- **Watched-key counts in the tests are value changes**: a key written with the value it holds is
  no state change on the node (ENG-01 §2.2), so `leave` to a location shows 8 changed keys for 9
  written (the revealed set, empty before and after).
- **`Instances`' empty timers, effects and recharges are written as their stored words**
  (`EMPTY_TIMERS` = `LIVE + 255`, `LIVE`), and `leave` reads the two maxima it needs from the
  stats word: 400,000 less on `enter` and 640,000 less on `leave` to a location on the node than
  writing the packed structs, and 2,440 CASM felts.

## Escalations

1. **Budgets on the expedition's path** (D-144's rule: to the project manager). Net of the
   floor, without a belt: `enter` (later entry) **4.07 M, +9.2 %** over §10's 3.73 M; `leave` to a
   hub **2.31 M, +18.3 %** over 1.95 M; `travel_back` **2.11 M, +7.8 %**. With the belt's worst
   case the snforge upper bounds give about 4.60 M, 3.08 M and 2.88 M. `leave` to a location
   (3.08 M, −15.9 %) and the first entry (9.86 M, −16.2 %) are under, but both lack the entry
   chunk's two words ENG-05 will add (about +0.06 M initialised, +0.91 M cold). What §10 did not
   count: `leave` must read its gate (§10 priced `leave` to a hub with the report as its only
   call), and `create` and `leave` to a location read the gate, then its destination: one call
   more each (about 0.1 M, D-145's measure). The rest is computation §10 estimated. Proposed: the
   measured figures as the rows' targets (`enter` 4.10 M initialised without a belt, `leave` and
   `travel_back` 2.35 M), the belt's worst case re-measured on the node once `set_build` exists.
2. **`set_account_owner` with 7 inside**: 3.89 M net (D, from the node at 0 to 3 inside, 320,000
   an adventurer inside) against D-144's proposed 3.70 M (+5.2 %) and §10's 2.72 M. The node cannot
   reach 7 adventurers (no entrypoint sells slots), nor can snforge run the real `Instances`
   beside `Hub` without a manifest change (escalation 10).
3. **Class sizes**: `Instances` 28,841 CASM felts, **35.2 %** (7.8 % at ENG-01); `Hub` 28,980,
   **35.4 %** (22.4 % after ENG-04). Measured by stubbing one function at a time: in `Instances`,
   `create` about 4,800 felts (the `Snapshot` it deserialises and packs), `instance_state` about
   3,500 (the view's types), `leave` about 1,700; in `Hub`, `enter` about 3,100 and `report` about
   2,300. Both are under the 50 % rule of ENG-01 §1.3, but `Instances` has the tick, the reveal and
   the Fate actions still to come: ENG-01's decision (the pure rules as library classes) is not
   optional for ENG-05 and ENG-07.
4. **Two registry calls where the location is named by the gate** (`create`, `leave` to a
   location): (a) accept, about 0.1 M each; (b) the `GATE` record carries its destination's seal
   and `N` (content repeated, the pipeline keeps them equal); (c) a registry read that follows a
   reference. ENG-05's reveal at `create` needs the whole location anyway: (a) is the default.
5. **Task ids** (E-14): quiver is not embedded, so `enter` snapshots no task, a gate with a quest
   requirement is refused at `enter` and at `leave`, and `report` refuses task increments.
6. **The snapshot** is what the models hold today: design/03's health by level and energy, pips
   and armor by profession. design/03 says armor "scales with level" without a formula: the class's
   value is used at every level. Attribute ranks, equipment modifiers and set bonuses are 0 until
   `set_build` and equipment exist. **Facing at entry** is 0: design/18 says "away from the
   entrance", whose side ENG-05's generation knows.
7. **`leave`'s gate** ("the gate is reachable", design/02): read as *standing on its anchor tile*
   ("walk into a hub gate", design/02 *Ending an expedition*). Refused until their lots: floor
   gates (a dungeon's exit is a quota object, ENG-05), Rift gates (`enter_rift`'s lot), gates with a
   rank requirement (the snapshot holds no guild rank) or a quest (E-14). Adjacency instead of the
   tile itself is a design question.
8. **`report`'s settlement** applies experience without raising the level (design/03's rule is a
   later lot's), and refuses equipment drops (the pack list's capacity, design/15), and the facts
   other than a hub reached (the "distinct" counters, the Rift board, trials: their events
   `DungeonCleared`, `TrialPassed` are not emitted yet).
9. **ENG-01's figures** to update (docs/architecture is not in the allowlist): §9.3's rows of
   `enter` and `leave` (the entry chunk's keys move to ENG-05; `H.core` only with experience), §10's
   calls (`enter` 5, `leave` 2 or 4) and the measured targets, §1.3's class sizes.
10. **An snforge test of `Hub` with the real `Instances`** needs `grimworld_ephemeral` as a
    dev-dependency of `grimworld_persistent` with `build-external-contracts` (a manifest, the
    orchestrator's). Until then each side is tested with doubles and the node probe runs both.

## Open questions

- Should `travel` to the hub the adventurer already stands in be refused? It is allowed (no state
  change, one `AdventurerLocated`); design/01 does not say.
- D-144's decision file still reads "Decision: Pending" although the brief cites it as decided;
  this task followed the brief.

## Fix loop 1

After the `[GPT-6-Astra]` audit of `5e4bfc2` (FAIL: F-1 major, F-2 minor; no lifecycle or
settlement defect). `origin/main` merged first (D-148, #122: `4234faf`).

**F-1 (major), fixed** in `02cab98`, `test_generation_isolation`
(`contracts/ephemeral/tests/test_lifecycle.cairo`):
- `fill_slot` now poisons **all eight member words**: state, timers (an activation and five
  conditions), effects, recharges, and also stats, bar and kit (junk) and the controller (Alice,
  the earlier expedition's).
- The reused slot is entered with **another snapshot** (an Arcanist of level 5, another bar and
  elite slot, another belt of items and counts) and **another controller** (Bob).
- The test asserts all eight words, through the view and in storage, equal the new generation's:
  the entering state (180 health, 90 energy in thirds, belt `[4, 3, 2, 1]`), `EMPTY_TIMERS`, `LIVE`,
  `LIVE`, the new stats, bar and kit packed, and Bob.
- Alice can no longer act: `travel_back` and `leave` both revert `'not controller'`. Bob's
  `travel_back` runs, and its report carries the new instance and the new belt.
- The other isolation cases are kept: header counts, revealed set, quotas, entropy, task pages,
  the masked roster, and the old id and id 0 answering nothing.
- Its budget: 45,572,993 measured, 47,851,643 set. The test is new in this PR, so this is not a
  raise.

**F-2 (minor)**: deferred by the orchestrator to ENG-R1 (the store), as ENG-04's was. Nothing
changed.

**D-148's two design lines**, and only these:
- `docs/design/03-adventurer.md`, *Base stats*: armor is "the class's, flat at every level, until
  BAL-01 sets its curve (D-148)". This is the code's rule already
  (`ProfessionTrait::armor`).
- `docs/design/02-core-loop.md`, *The chain's answer*: "A gate is used by standing on its anchor
  tile, one rule for every gate (D-148)". This is `GateTrait::can_leave`'s rule already.
- Committed in `02cab98`; `b9cf43c` moves the gate line to after its paragraph, as a line of its
  own.

D-148 also accepted the targets I proposed (`enter` 4.10 M; `leave` to a hub and `travel_back` 2.35 M)
and the two registry calls. The orchestrator updates ENG-01's §9.3, §10 and §1.3 figures after the
merge. No code changed for them.

Also removed: an unused `MemberStats` import in `instances.cairo` (a compiler warning). No
behaviour or gas changed; every other budget is as before.

Commands:
```
$ git merge origin/main                                   (4234faf)
$ cd contracts/ephemeral && snforge test | python3 ../tools/set_budgets.py /dev/stdin
set: 43 missing: []
$ scarb --manifest-path contracts/Scarb.toml fmt
$ python3 scripts/gas_budgets.py && python3 scripts/gas_budgets.py --check
gas check: 225 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
$ gh run view 36559769621 (ci, head b9cf43c): success on every job; tooling: success
```
