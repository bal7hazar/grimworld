# CBT-02c — Capacity checks at registration, and the flattening wired into `Hub`

> D-166 (`docs/decisions/2026-09-30-cbt-02b-wiring-and-bound.md`), option (a): D-160's restrictions
> before any production snapshot, without the quadratic cost CBT-02b measured. **No production
> snapshot before this task.** After CBT-02b (#196).

## Agent
Title: `[Opus 5.5] CBT-02c registration checks` · Profile: implement · Branch: `feat/cbt-02c-registration-checks`

## Goal
After this task design/20's **per-source bounds are checked once, when a content record is
registered**, so that `Hub.set_build` and `Hub.enter` build the snapshot through a **linear**
flattening (a sum over the build's sources with the totals' checks: DS-2's floors, design/20's counts),
wired and measured against D-158's targets and ENG-01 §1.3's 50 % class limit.

## Context
- **D-166** and CBT-02b's report (`docs/reports/CBT-02b-tick-cost.md`, *The wiring against D-158*): the
  wiring as CBT-02b built it (commit `0607c1d` on `feat/cbt-02b-tick-cost`, reverted by `5c437de`) took
  `Hub` to 79.8 % and `set_build` to ~18.5 M, `enter` to ~20.6 M, about 14.5 M of each being checks
  quadratic in the passives. Start from `0607c1d`'s wiring; move the per-source checks out of it.
- **design/20** (the per-source bounds, DS-1 to DS-9 and the rest as D-160 decided; §6's extremal
  builds), D-157 (`docs/decisions/2026-09-29-cbt-01-escalations.md`), CBT-01's validators and CBT-02's
  flattening in `contracts/logic/src/`.
- **The registry** (ENG-03, `contracts/persistent/src/systems/registry.cairo`, `RegistryAssert`;
  ENG-01 §3.5): `set_record` is where a record is refused; D-145's rule that the administrator pays for
  registration and players do not.
- **D-158** (`docs/decisions/2026-09-29-cbt-08a-costs.md`): `set_build` ~3.8 M net (its measured
  worst case), `enter` 5.25 M with the belt's worst case; D-144's rule for measured replacements
  (cost-budget.md §2). ENG-01 §1.3 (a class under 50 %; CI's `class_sizes.py`).
- **CAIRO.md §2 (D-167, owner)**: a module's unit tests live in its own file under `#[cfg(test)] mod
  tests`; only integration tests, entrypoint benchmarks and parity tables stay in `tests/`; existing
  test files are moved when a lot touches their module. `scripts/gas_budgets.py` already reads budgets
  in `src/` as well as `tests/` (its `declared` walks both): say so in the report after checking it
  runs green on your moved tests. §7 and §8 (D-143, D-147), COMMON.md, D-154.

## Scope
- In:
  - **At registration**: every per-source bound of design/20 that belongs to one record (a modifier, a
    rune, a passive, an item's effects, a caste) checked by the registry's validators when the record is
    written; a record past its bound refused, with tests at each bound.
  - **The flattening, linear**: `set_build` and `enter` sum the build's sources and check only what a sum
    can break (the totals' floors and caps, the counts); no check that a record's registration already
    guarantees.
  - **The wiring**: `Hub.set_build` refuses an illegal build through it; `Hub.enter` builds its snapshot
    through it; tests.
  - **The figures**: `set_build`'s and `enter`'s worst cases measured (the node and snforge, as CBT-08a
    and CBT-02b did) against D-158; `Hub`'s class against 50 %. If `Hub` still passes 50 %, stop and
    report: moving the flattening into a library class needs `set_contracts` to change, the project
    manager's decision (D-166 (b)).
  - The unit tests of the modules this task touches moved into their files (D-167).
- Out: the tick's levers (CBT-02d), `play` (ENG-07), any other frozen signature.
- Allowlist: `contracts/logic/src/**`, `contracts/persistent/src/systems/registry.cairo` and
  `hub.cairo` (`set_build`, `enter` and their helpers), the persistent models and helpers they need
  (D-143), the three packages' tests, `docs/architecture/ENG-01-interfaces.md` §1.3, §3.5 and §9.3,
  `GAS.md` and `docs/BUDGETS.md` as generated, the node probes under `contracts/tools/`.

## Acceptance criteria
- [ ] AC-1 Every per-source bound of design/20 checked at registration, each with a refusal test.
- [ ] AC-2 The flattening linear in the build's sources; no validated build can overflow a snapshot
      field (the extremal builds of design/20 §6 as tests).
- [ ] AC-3 `set_build` and `enter` wired and tested; their worst cases against D-158; `Hub` under 50 %,
      or the stop of the scope.
- [ ] AC-4 Unit tests in their modules (D-167); `gas_budgets.py --check` green on them.
- [ ] AC-5 D-143; CI green; `class_sizes.py`.

## Audits
Security (a build or a record that passes the checks and overflows) and cost: `[GPT-6-Astra]`; quality and
organisation: `[GPT-6-Sol]`; through `nexus audit`, then the Codex review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the checks moved to registration, the flattening, the wiring,
the figures against D-158 and 50 %, the tests moved, the gas table of every test.
