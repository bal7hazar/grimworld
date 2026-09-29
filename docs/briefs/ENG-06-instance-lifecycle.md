# ENG-06 — The instance lifecycle: enter, resume, leave, close

> Phase 1, on ENG-01's frozen interfaces, ENG-03's registry and ENG-04's accounts (#81, #93, #106,
> #100). The first task in which an adventurer is inside an instance.

## Agent
Title: `[Opus 5.5] ENG-06 instance lifecycle` · Profile: implement · Branch: `feat/eng-06-instance-lifecycle`

## Goal
After this task an adventurer can **enter** a location from its hub (the entry draw made, the
snapshot taken, the instance created in a reused slot), **resume** it from any device by reading
its state, **leave** through a gate to the next location or **travel back** to a hub, and every
way out **closes** the instance with its results settled on `Hub`. `play` and the tick are
ENG-07's; this task makes the instance they run in.

## Context
- **`docs/architecture/ENG-01-interfaces.md`**: §1.2 (who calls whom: `Hub` → `Instances.create`,
  `set_controller`; `Instances` → `Hub.report`), **§2.1** (instance slots reused, the generation in
  the id and the header, never in a key; records never zeroed; what a new generation resets:
  F-12, F-13, F-14), §3.2 and §3.3 (storage), §4.1 (`enter`, `leave`, `travel_back`, the views;
  sequences, refusals), §4.2 (`IInstanceEntry`, `IResults`), §5 (events: `InstanceEntered`,
  `InstanceClosed`, `AdventurerLocated`, `Refused`), **§6** (the snapshot and the results), §7
  (randomness: domains), §9.3 and §10 (the write sets and budgets of these entrypoints).
- **Decisions**: D-141 (docs/decisions/2026-09-29-eng-01-escalations.md: **E-15** the belt's
  unused potions credited back on defeat as on return; **E-20** nothing but the belt's reserve
  carries through a gate, the four member words written at a gate whatever the rule), the content
  version (`enter`, `leave`, `travel_back` do not carry it: design/02 *Which entrypoints carry it*),
  **D-144** (docs/decisions/2026-09-29-eng-04-budgets.md: the start hub becomes Region 1's town read
  from the registry, in this task; `set_account_owner` with adventurers inside re-measured with the
  real `set_controller`; the rule for measured worst cases in cost-budget.md §2), **D-145**
  (docs/decisions/2026-09-29-eng-03-registry.md: read only the records the invocation uses, and
  **measure where `bundle`'s 36,000 a slot goes**, the call against the read).
- design/02 (*Expedition lifecycle*, *Instances are not saved*, *Ending an expedition*, *The chain's
  answer*: sequences, `Refused`, reorgs), design/01 (gates, hubs, travel), ADR-0002 (Fate: every
  precondition before the draw; the draw and its consumption in one invocation), FND-05
  (`grimworld_logic::fate`: `derive`, `domain`, the `ENTRY` purpose), ENG-03's seed
  (`contracts/seed/`: the test region you enter and leave), ENG-04's ownership check
  (`Hub::InternalTrait::owned_in_hub`, `AdventurerAssert`).
- **docs/CAIRO.md in full, §7 and §8 (D-143)**: models, types, helpers scoped in traits, checks in
  `Assert` impls, a `mod errors` per file, no free function without a written reason. The store's
  emission of events waits for ARC-06: emit the frozen events as ENG-01 declares them. COMMON.md.

## Scope
- In, `Hub`: `enter(adventurer_id, gate)` (the ownership check, the gate from the registry and its
  requirements, the belt's reserve debited from the pack, the snapshot and the task ids, then
  `Instances.create`); `travel(adventurer_id, hub)` (map travel between unlocked hubs); `report`
  (`IResults`, called by `Instances` only: the settlement of a closed instance, as §6 says; apply
  what the models of today hold, the belt per E-15 and the placement first, and escalate a result
  field whose model does not exist yet rather than invent it); the **start hub** of
  `create_adventurer` read from Region 1's town (D-144).
- In, `Instances`: `create` (`Hub` only: a slot reused or a new one, the generation, the header,
  the member's words reset for a new generation as §2.1 says, the entry draw with its domain, the
  first chunk's reveal left to ENG-05: say what `create` writes for it until then); `set_controller`
  (`Hub` only); `leave(…, gate)` (to a hub: close and report; to a location: close, report, and
  enter the next one in the same invocation, E-20); `travel_back`; the closing path as one internal
  function that ENG-07's defeat will call; `instance_state` (the view of §4.1, from the stored words).
- Out: `play`, the tick, goblins, reveals and chunk generation (ENG-05, ENG-07); `enter_rift` and the
  Rift board (a later task); `instance_region` (ENG-05); loot and the Fate actions (later tasks).
- Allowlist: `contracts/persistent/src/systems/hub.cairo` (the entrypoints above, their helpers),
  `contracts/ephemeral/src/systems/instances.cairo` (the entrypoints above, their helpers), the
  models, types, helpers and errors files of `contracts/{logic,persistent,ephemeral}/src/` that these
  need (new files welcome, D-143), the three packages' tests, `GAS.md` and `docs/BUDGETS.md` as
  generated. A frozen signature, layout or event that must change is an escalation, not an edit.

## Acceptance criteria
- [ ] AC-1 Enter, resume (`instance_state`), leave to a hub, leave to a location, travel back and
      travel work as frozen; every refusal (§4.1: sequence, caller, gate, requirement, already
      inside) has a test; a refused Fate or gate action draws nothing and changes nothing.
- [ ] AC-2 **Generation isolation** (§2.1): an instance created in a slot another generation used
      shows nothing of it (the member's words, the roster through the masked read, the revealed set),
      tested on a reused slot with stale data left in every word.
- [ ] AC-3 Each entrypoint's storage writes match §9.3 (new and overwritten, counted by tests and
      by a node probe as ENG-04's `contracts/tools/accounts_probe.py`), and its gas is within §10 or
      replaced under cost-budget.md §2's rule, escalated when it must be; `enter`, `leave` and
      `travel_back` are on the expedition's path: any overrun comes to the project manager.
- [ ] AC-4 D-145: the records each invocation reads through `bundle`, listed; the share of the call
      and of the read in its cost, measured.
- [ ] AC-5 D-144: the start hub from the registry; `set_account_owner` with 7 inside re-measured.
- [ ] AC-6 D-143 on the code this task adds. CI green; `python3 scripts/gas_budgets.py --check`;
      `class_sizes.py`.

## Audits
Security (control of an adventurer inside, generation isolation, randomness) and quality:
**`[GPT-6-Astra]`**, with the organisation lens of CAIRO §8.

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/<your probe>.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: each entrypoint's writes against §9.3 and its gas
against §10, the generation-isolation tests, the records read and the call-versus-read measure,
the escalations, the gas table of every test.
