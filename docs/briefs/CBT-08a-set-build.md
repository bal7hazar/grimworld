# CBT-08a — `set_build`: the bar, the attributes, the belt and the equipment

> D-150: the first part of CBT-08, pulled forward while the engine chain waits, after CBT-01
> (#165). It also measures the belt's worst case on the node (D-148).

## Agent
Title: `[Opus 5.5] CBT-08a set_build` · Profile: implement · Branch: `feat/cbt-08a-set-build`

## Goal
After this task an adventurer in a hub can **set its build in one call**, as ENG-01 froze it
(`Hub.set_build(adventurer_id, build, belt, equipped)`), and the contract refuses any build the
rules do not allow; and the belt's worst case, which ENG-06 could not run without it, is measured on
the local node against D-148's targets.

## Context
- **design/03** (the adventurer: professions, the secondary profession, attributes and their points
  by level, the skill bar of 8 with at most one elite, the belt of 4 potion slots filled from the
  pack, equipment slots and requirements), design/15 (equipment: slots, requirements, the look),
  design/07 (the belt).
- **`docs/architecture/ENG-01-interfaces.md`**: §3.3 (`Hub` storage: `Adventurer.build`, `belt`,
  `equipped`, `known_skills`, `packs`, `balances`, `items`; the layouts of `Build`, `Lanes32`,
  `ItemBase`), §4.3 (`set_build`, "one call, stored layouts"), §9.3 and §10 (its write set and
  budget). **CBT-01's models** (`grimworld_logic`: the `SKILL` record, its profession, attribute and
  elite flag; the actor's stats) and its report (`docs/reports/CBT-01-combat-interfaces.md`), and the
  open questions it left (`docs/decisions/2026-09-29-cbt-01-escalations.md`: A, the attribute ids;
  do not decide them: follow the recommendation and say where it binds).
- **ENG-04's ownership check** (`owned_in_hub`, `AdventurerAssert`) and ENG-06's `enter` and closing
  report (the belt's reserve debited at entry, credited back unused, E-15); **D-148**: `enter` 4.10M
  (a later entry without a belt), `leave` to a hub and `travel_back` 2.35M; the belt's worst case was
  to be re-measured on the node once `set_build` exists, and comes to the project manager if it passes
  the targets. The lifecycle probe: `contracts/tools/lifecycle_probe.py`.
- **docs/CAIRO.md §7 and §8 (D-143, D-147)**, COMMON.md; D-154 (a flaky gas budget is recorded, not
  raised).

## Scope
- In: `set_build` on `Hub`: the ownership check and the hub; the bar (each skill known, of the
  adventurer's primary or secondary profession, at most one elite, no duplicate); the attributes (the
  points spent within what the level gives, the primary attribute only for the primary profession, as
  design/03 says); the belt (potion items only, held in the pack, the counts within what the pack
  holds); the equipment (each item owned by the adventurer's pack, fitting its slot, its requirements
  met); every refusal with its test. The node probe gains the belt's worst case: `enter` with four
  potion items on four pack pages, and a return crediting them back, against D-148's targets.
- Out: skills' purchase (`buy_skill`), attribute respec rules beyond what design/03 states, the
  equipment's modifiers and sets in combat (CBT-*), `stow`.
- Allowlist: `contracts/persistent/src/systems/hub.cairo` (`set_build` and its helpers), the models,
  types, helpers and errors files that it needs (D-143), `contracts/tools/lifecycle_probe.py` and its
  output, the three packages' tests, `GAS.md` and `docs/BUDGETS.md` as generated. A rule design/03
  does not settle is an escalation, not a decision.

## Acceptance criteria
- [ ] AC-1 `set_build` stores the three words as frozen and refuses every illegal build (each rule a
      test at its boundary).
- [ ] AC-2 Its writes match ENG-01 §9.3 and its gas is within §10 or replaced under cost-budget.md
      §2's rule (+10 % the orchestrator's; beyond, the project manager's).
- [ ] AC-3 The belt's worst case measured on the node for `enter`, `leave` to a hub and
      `travel_back`, against D-148's targets; an overrun is escalated with its make-up.
- [ ] AC-4 D-143 on the code this task adds; CI green; `python3 scripts/gas_budgets.py --check`;
      `class_sizes.py`.

## Audits
Security (ownership, items) and quality: **`[GPT-6-Astra]`**, with the organisation lens of CAIRO §8.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: each rule and its test, the writes and gas, the belt's
worst case against D-148, the escalations, the gas table of every test.
