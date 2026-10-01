# SPK-15 — The tick's cost levers, measured before CBT-05

> D-171 (`docs/decisions/2026-10-01-tick-cost-spike.md`). A spike: nothing of it merges into the
> contracts. While ENG-R1a, CBT-04 and CBT-03a wait for Codex (2026-10-04 13:36 UTC).

## Agent
Title: `[Opus 5.5] SPK-15 tick cost levers` · Profile: implement · Branch: `spike/spk-15-tick-cost-levers`

## Goal
After this spike the project manager and the owner can choose **the levers that bring the worst tick
back toward its budget**, on measurements: each lever with its **saving on the worst tick** (against
≈ 6,510,212 L2 gas a tick inside a batch, 4.43× the 1,469,435 target) **and on S1** (the expedition of
300 actions, D-129's $0.50), its cost in code and in frozen interfaces, and whether it changes a rule.
**Engineering levers** (no rule changes; the project manager decides) are kept apart from **design
levers** (a rule changes: fewer goblins awake, fewer conditions, a smaller window; the owner decides).

## Context
- **The figures to beat** (the decision file's table): CBT-02d's re-proved bound **3,447,872**
  (`docs/reports/CBT-02d-tick-levers.md`, ENG-01 §9.2: the tick 1.48 M, load and store 1.06 M, the call
  0.33 M, the content 0.58 M); CBT-04's line **+2,368,590** (PR #228, `feat/cbt-04-conditions` at
  `b5f4069`: 16 applications on the member at 108,100, 7 on goblins at 76,820, the predicates); CBT-03a's
  **+693,750** (PR #229, `feat/cbt-03a-hit` at `36bf2ba`: 15 hits at 46,250). The representative tick:
  1,065,651. The map library's share of a worst tick: 1.06–1.11 M (LIB-05 M1-T9b; STATUS).
- **Levers already named**: CBT-02d's escalation 2 (the frozen goblins kept as words until touched,
  ~0.85 M a tick; it changes `load`'s contract with perception); D-161's (c) and (d) (ENG-07's);
  D-166. ENG-01 §1.3, §9.2, §10. `docs/architecture/cost-budget.md`. S1's running estimate (STATUS).
- **CBT-04 and CBT-03a are not merged.** Measure their functions on their branches' code, copied into
  the spike's package with a header naming the source file and commit, never by editing those branches.
- **The design's rules** for the design levers: design/02 (the awake set, batches), design/18
  (perception, the window), design/19 (§5's order, the catalogue), design/20 (the castes' carriers),
  D-133 and D-141 (at most 16 goblins changed an invocation). A design lever is described and priced
  here, never decided.
- COMMON.md; CAIRO.md §2 for the spike's own tests; D-154 (each figure from two clean runs).

## Scope
- In:
  - **A Scarb package `spikes/SPK-15/`** on `grimworld_logic` (by path, main's code) plus the copied
    functions above, with benchmarks for each lever, measured as test pairs (CBT-02d's lesson: a call
    measured alone misses its straight-line part).
  - **Engineering levers**, at least:
    1. the frozen goblins kept as words until a step or a hook touches them (what perception then
       reads, and how);
    2. what one condition's application on the member is made of (108,100 against the goblin's 76,820)
       and what writing its fields in place, or batching a tick's applications, would save;
    3. the executor's overhead as CBT-05 will add it (reading an entry, gathering a hit's inputs from
       the world, writing the actors back), estimated on CBT-03a's and CBT-04's functions;
    4. any other the measurements show (the content index's ~0.56 M a call; load and store).
  - **Design levers**, priced: fewer goblins awake (8 → 6, 4), fewer condition applications a carrier
    (a cap per tick), a smaller simulation window (its share of the map library's part), fewer ticks a
    batch; each with the rule it changes and the design document it touches.
  - **A table**: each lever, engineering or design, its saving on the worst tick and on the
    representative tick, on S1 (in L2 gas and dollars at ENG-01's price), its cost in code and in frozen
    interfaces, and which lots it would land in (ENG-07, CBT-05, a new one).
  - **A recommendation**: the set of engineering levers that brings the worst tick lowest, and what
    remains for the owner's design levers to close.
- Out: any change to `contracts/`; any design decision.
- Allowlist: `spikes/SPK-15/**` only (CI discovers the package). Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 Each engineering lever measured (two clean runs, test pairs), with its saving on the worst
      and representative ticks and on S1.
- [ ] AC-2 Each design lever priced the same way, with the rule and document it changes.
- [ ] AC-3 The table and the recommendation; engineering and design kept apart.
- [ ] AC-4 The copied functions' sources named (file and commit); nothing outside `spikes/SPK-15/`.
- [ ] AC-5 CI green; the spike's budgets ceil(1.05 × measured).

## Audits
Cost and method: `[GPT-6-Astra]` through `nexus audit` (queued for Codex's reset); a Claude-side lens
may run before it (D-170).

## Verification
```
scarb --manifest-path spikes/SPK-15/Scarb.toml build
(cd spikes/SPK-15 && snforge test)
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the levers, their measurements, the table, the
recommendation, the gas table of every benchmark.
