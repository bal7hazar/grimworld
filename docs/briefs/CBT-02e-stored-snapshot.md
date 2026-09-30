# CBT-02e — The snapshot flattened once at `set_build` and stored with the adventurer

> D-168 (`docs/decisions/2026-09-30-cbt-02c-wiring.md`), option (a) with its three conditions. After
> CBT-02c (#206: the registry's per-record checks and the linear flattening, merged unwired).
> **The first production snapshot is this task's**; D-160 holds until it merges.

## Agent
Title: `[Opus 5.5] CBT-02e stored snapshot` · Profile: implement · Branch: `feat/cbt-02e-stored-snapshot`

## Goal
After this task `Hub.set_build` flattens the build **once, through a library class**, and stores the
result **with the adventurer as packed words**; `Hub.enter` **copies** the stored snapshot to
`Instances` and **refuses a stale one** with a named error. `Hub`'s class is back under ENG-01 §1.3's
50 %, `enter` is under D-158's 5.25 M, and every entrypoint that changes an input of the flattening
is listed and handled.

## Context
- **D-168** in full (the decision file above): its three conditions are this brief's acceptance
  criteria; its *What would reverse it* is this brief's stop.
- **CBT-02c's report** (`docs/reports/CBT-02c-registration-checks.md`): the linear flattening
  (`SnapshotBuildTrait::build`, `contracts/logic/src/snapshot.cairo`), the wiring as it built it and
  held it back (commit `4ca5802` on `feat/cbt-02c-registration-checks`: `hub.cairo`,
  `models/item.cairo`'s `held`, `ItemModsAssert::assert_slot` and `assert_value`,
  `models/adventurer.cairo`'s `loadout`, the persistent wiring tests), and its figures: `Hub` 61.15 %
  wired, `set_build` ≈ 8.23 M, `enter` 7.15 M a call. Start from `4ca5802`'s wiring and move the
  flattening out of `Hub`.
- **ENG-01** §1.3 (library classes: `grimworld_logic` code declared as its own class, called by
  `library_call` with its class hash as configuration, state in and state out; `TickLibrary` in
  `contracts/logic/src/systems/tick.cairo` is the example), §3.3 (`Hub`'s storage), §9.3 (the hub
  entrypoints' reads and writes), §10. ADR-0001 (the ephemeral domain reads a snapshot taken at entry).
- **D-158** (`docs/decisions/2026-09-29-cbt-08a-costs.md`: `enter` 5.25 M with the belt's worst
  case; (c), a hub action's target is its measure), D-144 (measured replacements,
  `docs/architecture/cost-budget.md` §2), D-157 F (the snapshot's form, settled by D-168: packed).
- The planned entrypoints that will change the flattening's inputs: GLD-01's level-up, RWD-06's
  equipment (PLAN.md rows); the present ones are in `hub.cairo` (`set_build`, `personalise`,
  `identify`, `lift_modifier`, `set_modifier`, `buy_skill`, `sell`, `recycle`, the `leave` path, and
  any other you find). A content record rewritten by the administrator after a snapshot was stored
  is an input too: say how it is handled (the content's version in the snapshot and checked at
  `enter`, or another way, with its cost).
- **CAIRO.md** §2 (D-167: unit tests in their modules), §7 and §8 (D-143, D-147). COMMON.md, D-154.
- D-149: no event of ENG-01 changes. If one must, stop and escalate (the indexer is lent to track CV).

## Scope
- In:
  - **The library class**: a new file `contracts/logic/src/systems/flatten.cairo` declaring the
    flattening as its own class (state in: the build's records as read; state out: the packed
    words), its dispatcher trait added to `contracts/logic/src/interface.cairo`, its module line in
    `contracts/logic/src/systems.cairo`. Additions only in those two shared files.
  - **`set_contracts` gains the library's class hash** (a frozen signature, changed by D-168): the
    contract, its storage, and every caller (tests, `contracts/tools/lifecycle_probe.py`, the
    fixtures). `Hub`'s storage gains the snapshot words per adventurer and whatever the stale mark
    needs.
  - **`set_build`** reads the records, calls the library, stores the words; its worst case measured
    (the node and snforge, as CBT-08a and CBT-02c did) and made its target (D-158 (c)); the cost
    budget's hub row takes it (D-168 3).
  - **`enter`** reads the stored words and passes them to `Instances.create`; refuses a missing or
    stale snapshot with a named error (tested); its worst case with the belt's measured against
    5.25 M.
  - **Staleness (D-168 2)**: a table in the report of every entrypoint, present and planned, that
    changes an input, and what each does (recomputes, or marks stale); the present ones implemented
    and tested (the mark set, `enter` refused, `set_build` clearing it).
  - **The storage's cost (D-168 3)**: the count of words, the first write's cost (about 453,524 a
    new slot) and an overwrite's, stated in the report and in ENG-01 §3.3 and §9.3.
- Out: the tick (CBT-02d runs at the same time and owns `contracts/logic/src/systems/tick.cairo`,
  the tick's types and helpers, and ENG-01 §9.2); `play` (ENG-07); GLD-01 and RWD-06 themselves
  (only their line in the table); any deployment.
- Allowlist: `contracts/logic/src/snapshot.cairo` and the new `systems/flatten.cairo`, additions in
  `contracts/logic/src/systems.cairo` and `interface.cairo`; `contracts/persistent/src/**`;
  `contracts/ephemeral/src/systems/instances.cairo` only where `create` receives the snapshot; the
  three packages' tests; `contracts/tools/` (the probes, `class_sizes.py`'s list of classes);
  `docs/architecture/ENG-01-interfaces.md` §1.3, §3.3, §9.3, §10; the hub row of
  `docs/architecture/cost-budget.md`; `GAS.md` and `docs/BUDGETS.md` as generated (if CBT-02d merges
  first, merge `origin/main` and regenerate). Anything else is an escalation.

## Stop
If `Hub` is still above 50 % with the flattening out of it, stop before moving any storage and
report the figures (D-168: the snapshot's storage would then move to `Instances`' persistent side or
a third contract, the project manager's decision). Likewise if `enter` stays above 5.25 M.

## Acceptance criteria
- [ ] AC-1 The flattening runs in a library class at `set_build` only; `enter` copies the stored
      words; the snapshot `enter` passes equals the flattening's for design/20 §6's extremal builds
      (tests).
- [ ] AC-2 `Hub` under 50 % (`class_sizes.py`); the library's class listed there too.
- [ ] AC-3 `set_build`'s worst case measured and made its target; `enter` under 5.25 M with the
      belt's worst case, or the stop.
- [ ] AC-4 The staleness table; each present entrypoint tested; `enter` refuses a stale or missing
      snapshot with a named error.
- [ ] AC-5 The words' count and their first-write and overwrite costs stated; ENG-01 §3.3, §9.3 and
      the cost budget's hub row updated.
- [ ] AC-6 No event changed (D-149); D-143; unit tests in their modules (D-167); CI green;
      `gas_budgets.py --check`.

## Audits
Security (a stale or forged snapshot reaching an instance; the new configuration) and cost:
`[GPT-6-Astra]`; quality and organisation: `[GPT-6-Sol]`; through `nexus audit`, then the Codex review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the library class and its call, the stored words and
their cost, the staleness table, the figures against D-158 and 50 %, the gas table of every test.
