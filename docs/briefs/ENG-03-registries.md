# ENG-03 — Registries: the store, the content version, a test region

> Phase 1, on ENG-01's frozen interfaces and ENG-01b's content version (#81, #93, D-141). Runs
> beside ENG-04; the allowlists do not overlap.

## Agent
Title: `[Opus 5.5] ENG-03 registries` · Profile: implement · Branch: `feat/eng-03-registries`

## Goal
After this task the game's content lives in `Registry` as data: the administrator writes records,
every contract and the client read them in one call with the **content version**, and a **test
region** (a town, a zone, a dungeon of two floors, their gates) is written as seed data that later
tasks (ENG-05, ENG-06) build on.

## Context
- **`docs/architecture/ENG-01-interfaces.md`**: §1.2 (the administrator writes the registry), §2.1
  (reused keys: records never zeroed), §3.1 (`LIVE` at bit 250, packing), **§3.5** (the store, the
  allocation rules for sequential and composite kinds, existence by part 0, the 25 kinds and their
  fields: "ENG-03 writes the bit layout within the parts"), §4.2 (`IRegistryRead`: `record`,
  `records`, `bundle`, `content_version`), §4.5 (bounds on list arguments), §9.3 and §10 (the write
  set and budget of `set_record`: 0 N / 5 O → 1,058,019; cold 5 N / 0 O → 3,165,279; `bundle`'s
  read bound 97), §11 E-5.
- **The content version** (D-141 and its refinement): design/02 *The chain's answer* ("The content
  version", "Which entrypoints carry it"); `docs/decisions/2026-09-29-eng-01-escalations.md` and
  `2026-09-29-content-version-standalone.md`. The version rises by one with **every changed record**
  (a rewrite with the same values is not a change: say how you tell), automatically, with no admin
  setter.
- design/01 (the world: regions, locations, gates; rules 1–2 on content), design/17 (Rifts, for the
  location types), design/18 (terrain and features), ADR-0006 (chunks, outlines), D-134 (void chunks
  around locations). docs/CAIRO.md, COMMON.md.
- `contracts/persistent/src/systems/registry.cairo` (the stubs), `contracts/logic/src/content.cairo`
  (kinds, `PARTS`, `is_sequential`).

## Scope
- In, `Registry`:
  - `set_record(kind, id, record)`: the admin only; exactly `parts(kind)` felts, part 0 with
    `LIVE`; the allocation rules (sequential: `last_id + 1` for a new id, append-only; composite:
    the parent exists); an existing record may change; the content version raised when the record
    changed. `set_admin` (the admin only, handed over, never to zero, as FND-05 did for `Hub`).
    `upgrade` stays a stub.
  - Reads: `record`, `records` (bounded as §4.5 says), `bundle(requests)` returning
    `(content_version, the records in the order asked)`, `content_version()`, `last_id(kind)`. A
    missing record: say what a read returns and test it.
  - Its gas against §10: `set_record` new and changed, `bundle` with 1, 10 and its bound of
    requests; **the cost of the version** measured apart (the read in `bundle`, the compare and
    raise in `set_record`), for ENG-07 and ENG-06 to take.
- In, `grimworld_logic`: **the bit layouts within the parts of `REGION`, `LOCATION` and `GATE`**
  (and `OUTLINE`'s two forms if the test region needs them), with pack and unpack functions and
  round-trip tests; every field of §3.5's table placed, its width justified from the design's
  ranges. Other kinds' layouts are their tasks'.
- In, **seed data for a test region**: one region with its town hub, one zone, one dungeon of two
  floors, and the gates between them, as a data file under `contracts/seed/` and a way to write
  it through `set_record` (a Cairo test helper that writes it on the test node; the deployment
  scripts are OPS-01's). A test writes the seed and reads it back through `bundle`, and the test
  region's figures (records, slots, gas to write it all) go in the report.
- Out: the other kinds' layouts; the `Hub`, `Instances` and `Market` contracts (ENG-04 edits
  `Hub` now); the version's check in `play`, `open`, `mine`, `barter` (ENG-06, ENG-07); the map
  tool (TOOL-01).
- Allowlist: `contracts/persistent/src/systems/registry.cairo`, `contracts/logic/src/content.cairo`
  and new files under `contracts/logic/src/` for the layouts (with their `mod` lines),
  `contracts/seed/**`, the tests of those packages, `GAS.md` and `docs/BUDGETS.md` as generated;
  `docs/architecture/ENG-01-interfaces.md` **§3.5 only**, to write the layouts and the measured
  cost of the version. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 `set_record` enforces the admin, the part count, `LIVE`, and both allocation rules; each
      refusal has a test.
- [ ] AC-2 The content version rises by exactly one per changed record, not for an unchanged
      rewrite, and `bundle` returns it with the records; tested.
- [ ] AC-3 `REGION`, `LOCATION`, `GATE` (and any `OUTLINE` form used) have bit layouts in
      `grimworld_logic` with round-trip tests, and §3.5 states them.
- [ ] AC-4 The test region is seed data, written and read back by a test; its size and cost are in
      the report.
- [ ] AC-5 Gas: `set_record` and `bundle` against §10's figures; the version's cost measured apart.
      CI green; `python3 scripts/gas_budgets.py --check`; `class_sizes.py`.

## Audits
Design, security and quality (PLAN: D S Q), and **`[GPT-6-Astra]`** (the administrator's access
control of the content every contract reads; OPERATIONS §2).

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the layouts, the test region's content and cost,
the version's measured cost, the refusals, the gas table of every test.
