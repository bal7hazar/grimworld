# CBT-02 — The world tick's pipeline, as pure rules

> D-159: slot 1 while the engine chain waits for the map library. From design/19 (D-155) and
> CBT-01's frozen types (#165, D-157). ENG-07 (`play`) and CLI-02 (the client's mirror) build on it.

## Agent
Title: `[Opus 5.5] CBT-02 tick pipeline` · Profile: implement · Branch: `feat/cbt-02-tick-pipeline`

## Goal
After this task the game has **the world tick's pipeline as pure, deterministic rules**: the steps
of a tick in their order, regeneration, durations and deadlines, recharges, adrenaline, the
activation lifecycle, over the state CBT-01 froze, in a **library class** (ENG-01 §1.3: `Instances`
is at 35 % of the class limit), with its cost per tick measured against the expedition's budget.
Damage, conditions and the skill engine are CBT-03 to CBT-05; `play` is ENG-07.

## Context
- **design/02** *The tick (D-01)* (the steps of a world tick), *Simulation budget*, *Planned queues and
  played batches* (a batch runs up to 10 weights of ticks); **design/19** in full (§5 the resolution
  order, §7 the state), D-155; **design/04** (energy and adrenaline, durations, recharges).
- **CBT-01's code** (`grimworld_logic`: the actor's stats and state words, the effect types) and its
  report; D-157 (`docs/decisions/2026-09-29-cbt-01-escalations.md`): **E**, adrenaline decays **1
  quarter a tick** out of combat until BAL-01; **G**, per-source bounds are DES-06's, running now.
- **The deferred CBT-9** (PLAN's CBT-02 row, `docs/reports/CBT-01-audit-gpt-6-astra.md`): the snapshot
  builder aggregates bonuses for the same condition, and its test oracle with it.
- **The cost** (D-159): `docs/architecture/cost-budget.md` §2, **a tick inside a batch at 1,469,435 L2
  gas on average** is what S1 needs for $0.50; ENG-01 §1.3 (library classes, their call cost), §9.2 (a
  tick's writes), §10.1 (the batch's bound); D-145 (**content read once per batch, only the records
  the tick uses**; a call about 98,000, a record added to a call about 54,000, ENG-06's measure).
- **docs/CAIRO.md §1–§2 (cost, tests as oracles), §7 and §8 (D-143, D-147)**, COMMON.md, D-154.

## Scope
- In:
  - the pipeline: each step of design/02's tick in order, over one actor set, deterministic (the
    orders of design/19 §5), with no storage access (it takes and returns the state; the caller reads
    and writes);
  - regeneration (health, energy by pips), durations and deadlines (the clock, expiry, refresh as
    design/19 decides), recharges, adrenaline's gain and decay (D-157 E), the activation's start,
    interruption and resolution points (not the skill's effects: CBT-05);
  - the snapshot builder's aggregation of same-condition bonuses (CBT-9) and its oracle; the bounds
    checks of D-157 G wait for DES-06: leave them as a named hook, not guessed values;
  - the **library class** and how `Instances` will call it (a `library_call` interface), with the call's
    measured cost;
  - **the cost per tick**: tests that run the pipeline over representative and worst states (8 awake
    goblins, the member, conditions and activations running) and **carry budgets**; a table of where a
    tick's gas goes (computation, the library call, the content records it needs, read once per batch);
    compared with 1,469,435. **Above it, report the make-up and the levers; do not accept it** (the
    project manager decides).
- Out: damage and its formula (CBT-03), conditions' effects (CBT-04), skills (CBT-05), goblin AI and
  movement (ENG-07 and later), `play` and storage (ENG-07), the TypeScript mirror (CLI-02).
- Allowlist: `contracts/logic/src/**` and a new library-class package or module if the layout needs
  one (say where, and its manifest line, D-143), the three packages' tests, `GAS.md` and
  `docs/BUDGETS.md` as generated, `docs/architecture/ENG-01-interfaces.md` §1.3 and §9.2 (the library
  class and a tick's figures). A rule design/02 or design/19 does not settle is an escalation.

## Acceptance criteria
- [ ] AC-1 Every step of the tick and every rule in scope follows design/02 and design/19 in order; a
      table maps each rule to its code and test.
- [ ] AC-2 Deterministic: the same state gives the same result; worked cases from design/19's examples
      as tests.
- [ ] AC-3 The pipeline runs in a library class; the call's cost measured.
- [ ] AC-4 The cost per tick measured by budgeted tests on representative and worst states, against
      1,469,435, with its make-up; an overrun is escalated, not accepted.
- [ ] AC-5 CBT-9 closed; D-157 E applied; D-157 G left as a hook; D-143; CI green;
      `python3 scripts/gas_budgets.py --check`; `class_sizes.py`.

## Audits
Determinism, cost and quality: **`[GPT-6-Astra]`**, with the organisation lens of CAIRO §8.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the rule map, the library class and its call, the cost per
tick and its make-up against 1,469,435, the escalations, the gas table of every test.
