# CBT-02d — The tick's remaining levers: hot fields apart, a content index

> D-166 (`docs/decisions/2026-09-30-cbt-02b-wiring-and-bound.md`, point 2): before ENG-07, which derives
> a batch's weight from the measured worst tick. After CBT-02b (#196). Runs beside CBT-02c's close and
> CBT-02e: its allowlist keeps off the registry, the snapshot and `Hub`.

## Agent
Title: `[Opus 5.5] CBT-02d tick levers` · Profile: implement · Branch: `feat/cbt-02d-tick-levers`

## Goal
After this task the tick no longer rebuilds the goblins' array of 23-felt structs at every executor
hook, nor looks its content up at every load: **the goblins' hot fields live apart from the array**, and
**the content is reached through an index**. The worst tick is re-proved term by term, as CBT-02b proved
it, and both figures (representative and bound) are measured against 1,469,435 L2 gas a tick.

## Context
- **CBT-02b** (`docs/reports/CBT-02b-tick-cost.md`, *Against the expedition's target*): the bound's make-up
  (8 rebuilds of the 100-goblin array about 4.8 M; load's lookups about 5.5 M, ~410,000 a goblin at the
  lists' ends; step 3's rebuild 1.33 M); why the hot fields were out of its scope (they change `World`'s
  representation, and CBT-02b had to keep every CBT-02 test unchanged). ENG-01 §9.2 (the bound as it
  stands, term by term), §1.3 (`TickLibrary` at about 23 % of the class limit).
- **D-166** point 2, and D-161 (the target, 1,469,435; the levers (c) and (d) are ENG-07's; above target:
  report, do not accept). The map library's share of a worst tick: 1.06–1.11 M (D-161's file).
- **Two findings deferred to this task** (PLAN's CBT-02d row): the eight-free-goblin cost test must prove
  each goblin acted in step 2 (an `act` hook that records it, not `Idle`); the eight-awake limit must be
  checked before `conclude` returns on the member's defeat (`types/world.cairo`).
- design/19 §5 (the order: the pipeline's results must not change), design/02 (at most 8 awake goblins).
- **docs/CAIRO.md §1–§2 (D-167: a module's unit tests in its own file under `#[cfg(test)] mod tests`; only
  integration tests and benchmarks stay in `tests/`), §7–§8 (D-143, D-147)**, COMMON.md, D-154.

## Scope
- In:
  - the goblins' hot fields apart from the array (the representation of `World` may change; every
    CBT-02 and CBT-02b behaviour kept: the results of the pipeline on every existing case, rewritten
    tests asserting the same outcomes, and a parity check old against new on the existing fixtures);
  - the content reached through an index built once per call (or per batch) instead of lookups at
    every load;
  - the two deferred findings, each with its test;
  - the worst tick re-proved term by term and the representative re-measured, in ENG-01 §9.2 and the
    report, against 1,469,435; an overrun reported with its make-up.
- Out: the registry, the snapshot and its flattening (CBT-02c, CBT-02e), `Hub`, `play` and the batch's
  weight (ENG-07), levers (c) and (d).
- Allowlist: `contracts/logic/src/types/world.cairo`, `types/tick.cairo`, `helpers/tick.cairo`, the goblin
  and member models of `contracts/logic/src/models/`, `contracts/logic/src/systems/` (`TickLibrary`), the
  content's in-memory form where the tick reads it, their tests (moved into their modules per D-167),
  `contracts/logic/tests/test_tick.cairo` (benchmarks), `docs/architecture/ENG-01-interfaces.md` §9.2,
  `contracts/logic/GAS.md` and `docs/BUDGETS.md` as generated. Not `snapshot.cairo`, not the registry,
  not `persistent/`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 Hot fields apart and the content index in place; the pipeline's results unchanged on every
      existing case (a parity check against the previous representation).
- [ ] AC-2 The two deferred findings fixed, each tested.
- [ ] AC-3 The worst tick re-proved term by term; the representative re-measured; both against 1,469,435,
      before and after; an overrun reported.
- [ ] AC-4 D-167 and D-143 on the code this task touches; CI green; `gas_budgets.py --check`;
      `class_sizes.py`.

## Audits
Cost and determinism (`[GPT-6-Astra]`) and quality with the organisation lens (`[GPT-6-Sol]`), through
`nexus audit`; then the Codex review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
(cd contracts/logic && snforge test)
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the new representation and the index, the parity check, the
bound term by term before and after, the deferred findings, the gas table of every test.
