# CBT-02f — The stored snapshot's epoch: rules and the flattening's inputs

> D-169 (`docs/decisions/2026-09-30-cbt-02e-snapshot-staleness.md`): both parts of the
> recommendation. After CBT-02e (#212). **Before the first deployment that stores snapshots.**

## Agent
Title: `[Opus 5.5] CBT-02f flattening epoch` · Profile: implement · Branch: `feat/cbt-02f-flattening-epoch`

## Goal
After this task a stored snapshot is stale **exactly when** the rules that flattened it or a record
the flattening reads has changed since `set_build`: a new `FlattenLibrary` class set by
`set_contracts` stales every snapshot (the **rules epoch**), and a content update stales them only
if it changes a kind the flattening reads (the **counter of the flattening's input kinds**, returned
by `Registry.bundle` and stored **instead of** the content version). A new gate, quest or shop no
longer costs every player a `set_build`.

## Context
- **D-169** and the decision file above (cases 1 and 2, options 1 (a) and 2 (b)); **D-168**.
- **CBT-02e's report** (`docs/reports/CBT-02e-stored-snapshot.md`): *The stored words and their cost*
  (the kit word: its fields end at bit 202; the content version at bits 208–239; the stale mark at
  bit 240; `LIVE` at bit 250), *The staleness table*, `StoredSnapshotAssert::assert_fresh`, how
  `enter` gets the content version in the gate's `bundle` call.
- **ENG-03** (the registry: `set_record`, the content version, `bundle`; ENG-01 §3.5), the
  flattening's reads in `contracts/logic/src/snapshot.cairo` and `systems/flatten.cairo`, and
  `Hub.set_build`'s reads (which record kinds the flattening depends on: list them from the code).
- **D-158**: `enter` 5.25 M with the belt's worst case; CBT-02e measured 4,473,259 net on the node.
- CAIRO.md §2 (D-167), §7 and §8 (D-143, D-147); COMMON.md; D-154. D-149: no event changes; if one
  must, stop and escalate.

## Scope
- In:
  - **The counter**: `Registry` keeps a second counter that `set_record` moves only when a changed
    record is of a kind the flattening reads (the lot lists the kinds from the code, and says why each
    other kind is not an input); `bundle` returns it beside the content version (a frozen interface,
    changed by D-169). Nothing moves on an identical rewrite, as for the content version.
  - **The rules epoch**: `Hub` counts the `set_contracts` calls that change the flattening's class
    hash (not the calls that leave it unchanged); its width and what happens when it wraps, stated.
  - **The kit's bits**: the stored word carries the counter where the content version was and the
    rules epoch in free bits (241–249, or another layout that fits under `LIVE`: say which); `enter`
    compares both, in the `bundle` call it already makes plus whatever read the epoch needs, and
    refuses `snapshot: stale`.
  - **Tests**: a rewrite of each input kind stales; a new gate, quest or other non-input record does
    not; a new flattening class stales; the same class set again does not; `set_build` clears each;
    the epoch's wrap.
  - **The figures**: `enter`'s added cost on the node with the belt's worst case, against 5.25 M;
    `set_record`'s added cost (the administrator's); `Hub`'s and `Registry`'s classes against 50 %.
  - The staleness table of CBT-02e updated (ENG-01 where it holds it).
- Out: the entrypoints still stubbed (`sell`, `recycle`, `stow`, the market, `personalise`, the
  modifiers): their own lots; any deployment.
- Allowlist: `contracts/persistent/src/**` (the registry, `Hub`, the snapshot model, `Store`),
  `contracts/logic/src/interface.cairo` (the registry's `bundle` return and its readers only), the
  three packages' tests, `contracts/tools/` (the node probe), `docs/architecture/ENG-01-interfaces.md`
  §3.3, §3.5, §9.3, §10, `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 A changed record of an input kind stales every stored snapshot; a changed record of any
      other kind stales none (tests per kind); the list of input kinds justified from the code.
- [ ] AC-2 A new `FlattenLibrary` class stales every stored snapshot; setting the same class does not;
      the epoch's wrap is defined and tested.
- [ ] AC-3 `enter` under 5.25 M with the belt's worst case, measured on the node; `Hub` and `Registry`
      under 50 %.
- [ ] AC-4 `bundle`'s callers all updated; no event changed (D-149).
- [ ] AC-5 D-143; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`.

## Audits
Security (a stale snapshot that still enters; a counter that misses an input kind) and cost:
`[GPT-6-Astra]`; quality and organisation: `[GPT-6-Sol]`; through `nexus audit`, then the Codex review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the input kinds and why, the counter, the epoch and its
wrap, the kit's layout, the staleness table, the figures against D-158 and 50 %, the gas table of
every test.
