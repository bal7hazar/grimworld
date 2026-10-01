# ENG-R1a — `Hub` on the pattern: accounts, adventurers and packs through the store

> ENG-R1's first lot (D-143, D-147, D-167; PLAN row ENG-R1). **Shown to the owner before any other
> lot of ENG-R1** (D-167: the first lot on the game's code); after it, the project manager checks
> the organisation lens. After CBT-02f (it shares `contracts/persistent/src/`).

## Agent
Title: `[Opus 5.5] ENG-R1a Hub on the pattern` · Profile: implement · Branch: `feat/eng-r1a-hub-pattern`

## Goal
After this task the persistent package's **`Hub` reads and writes its storage only through the
store**, as typed models, on the pattern of `quiver_quest` 0.2.0 that the owner accepted (ARC-07a,
D-167): no word offsets, no `set_word`, no map access left in `systems/hub.cairo`; the checks in
`Assert` impls; the unit tests beside their code. **Nothing a player or the indexer sees changes**:
the same entrypoints, the same storage layout, the same events in the same order, the same results.

## Context
- **The pattern**: docs/CAIRO.md §7 and §8 (D-143, D-147), §2 (D-167, unit tests in their module).
  **The reference** is `quiver_quest` 0.2.0 in `bal7hazar/quiver` (on the VPS at
  `/home/claude/projects/quiver`, `origin/main`): `packages/quest/src/store.cairo` (the store on the
  contract's state, `get_x`/`set_x` per model, focused reads across slots, `Tracked` and the
  consumer's compile-time tracking), `packages/quest/src/models/`, its `README.md`, and the owner's
  review `docs/decisions/2026-09-30-arc-07a-owner-review.md`.
- **The findings deferred to this lot** (PLAN, ENG-R1): ENG-04's audit F-5 (`Hub`'s storage access
  and the account list's swap removal behind the store) and F-6 (`not in the account list` and
  `AdventurerListImpl`'s `lane above 6` panics into an `Assert` impl and `errors`),
  `docs/reports/ENG-04-audit-gpt-6-astra.md`; CBT-08a's F-1 (`set_build`'s storage access behind the
  store), `docs/reports/CBT-08a-audit-gpt-6-astra.md`. ENG-06's F-2 (`Instances`) is ENG-R1b's.
- **The code**: `contracts/persistent/src/` (`systems/hub.cairo`, `store.cairo`, `models/account.cairo`,
  `models/adventurer.cairo`, `models/item.cairo`, `models/balance.cairo`, `models/snapshot.cairo`),
  ENG-01 §3.3 (`Hub`'s storage) and §9.3 (the hub entrypoints' reads and writes).
- **D-149**: the indexer is lent to track CV and reads ENG-01's events. **No event may change**:
  not its name, keys, data, nor where, how often or in which order it is emitted. A model whose
  writes match one event exactly may become tracked with that event; one that does not stays
  untracked, and the event stays where it is emitted today, with a written reason. If the pattern
  cannot be met without changing the event stream, stop and escalate.
- D-144 (a measured replacement accepted up to +10 %), D-154, ENG-01 §1.3 (a class under 50 %:
  `Hub` is at 44.71 % after CBT-02e). COMMON.md.

## Scope
- In:
  - **Every storage access of `Hub`** through `store.cairo`: one `get_x`/`set_x` per model, focused
    reads and writes where a path needs less than the model (an adventurer's one word, a pack page),
    the account list's insertion and swap removal; the models `StorePacking`, never raw felts in the
    systems. `Hub`'s entrypoints keep only access control, the calls, the order of operations.
  - **Checks** into `Assert` impls with their `errors` modules (F-6 and any other inline `assert` in
    the systems); **free functions** scoped in traits or justified in a line above them.
  - **Tracking**: which of `Hub`'s models are tracked and with which event, decided under D-149's
    constraint above, the choice a compile-time property as quiver does it; a table in the report.
  - **Tests**: the unit tests of every module this lot touches moved into it (D-167); the
    integration and benchmark tests stay in `tests/`. **The event stream checked**: a test (or the
    node probe) that records every event of the persistent lifecycle (create, `set_build`, `enter`,
    `travel`, the report back, and whatever else the probe drives) before the rework and asserts the
    same after it.
- Out: `Registry` and `Market`'s own systems (ENG-R1b with `Instances`, unless a `Hub` call needs a
  store method there); the logic package (ENG-R1c); any change of an interface, a storage layout,
  an event, a rule or a figure the design states.
- Allowlist: `contracts/persistent/src/**` except `systems/registry.cairo` and `systems/market.cairo`;
  `contracts/persistent/tests/**`; `contracts/tools/` (the node probe, to record events);
  `docs/architecture/ENG-01-interfaces.md` §3.3 and §9.3 where they name an access path;
  `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 No storage access in `systems/hub.cairo` but through the store (a grep for `.read(`,
      `.write(`, `.entry(`, `set_word`, `word(` in the file, shown in the report, finds none or each
      with its written reason).
- [ ] AC-2 Checks in `Assert` impls with `errors` modules; no free function without a reason (CAIRO §8).
- [ ] AC-3 **The same storage layout** (the node probe's storage keys and values equal before and
      after) and **the same events** (the recorded stream equal), shown in the report.
- [ ] AC-4 Gas: every entrypoint's budget holds; a rise is a replacement under D-144 (≤ +10 %, its
      reason above the budget), beyond that an escalation; `Hub` under 50 %.
- [ ] AC-5 Unit tests in their modules (D-167); CI green; `gas_budgets.py --check`; `class_sizes.py`.
- [ ] AC-6 **For the owner's review**: the report opens with a short section naming the files to
      read, in order (the store, one model, `hub.cairo`'s `set_build` and `enter` as they read now,
      one module's tests), each with one line on what changed and why, and the differences from
      `quiver_quest` 0.2.0's pattern with their reasons.

## Audits
Quality with the organisation lens of CAIRO §8: `[GPT-6-Sol]`; cost (no entrypoint dearer beyond
D-144) and security (no access path or check lost): `[GPT-6-Astra]`; through `nexus audit`, then the
Codex review. Then the owner reads it (D-167), before ENG-R1b is briefed.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, opening with AC-6's section for the owner; then the
store's methods, the tracking table, the layout and event comparisons, the tests moved, the gas
table of every test.
