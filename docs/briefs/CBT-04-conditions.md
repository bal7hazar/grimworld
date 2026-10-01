# CBT-04 — The MVP's five conditions

> D-170 (`docs/decisions/2026-10-01-game-slots-until-codex.md`): pulled forward while Codex is out
> (until 2026-10-04 13:36 UTC), beside CBT-03a in disjoint files. Its Codex audits and review queue for
> the reset; it merges after ENG-R1a. After CBT-02 (the pipeline) and CBT-02d.

## Agent
Title: `[Opus 5.5] CBT-04 conditions` · Profile: implement · Branch: `feat/cbt-04-conditions`

## Goal
After this task the five MVP conditions (Bleeding, Poison, Burning, Crippled, Knocked down) are
**complete as rules**: every way design/19 says one is applied, refreshed, cured, ticks, or changes
what its holder can do exists as a scoped, tested function that CBT-05's executor and ENG-07's
movement call, with D-140's edges, and with its cost per tick stated against CBT-02d's bound.

## Context
- **design/19**: §3.2 (the conditions and `CONDITION`/`CURE`), §5.1 (deadlines, a duration of 0),
  §5.2 (busy actors, Knocked down cannot act; FX-7), §5.6 (a knocked-down target neither blocks nor
  evades), §5.7 (applied, refreshed `D = max(D_old, D_new)`, FX-6, FX-31; a dead goblin takes nothing;
  durations through `effective_duration` with the source's `CONDITION_DURATION` and `KNOCKDOWN_FLAT`),
  §5.8 (step 3: the pips −3, −4, −7), §5.9 (Knocked down interrupts an activation), §5.13, §6 (edges),
  §10.3 (a condition refreshed while ticking). D-155, D-157, FX-15 (a crippled goblin's move).
- **What already exists — inventory it first, do not rebuild it**: CBT-01's and CBT-02's
  `GoblinLifecycleTrait::{inflict, cure, condition, set_condition}`, `interrupt`, the member's
  equivalents (`contracts/logic/src/models/goblin.cairo`, `member.cairo`), `TickMathTrait::{refreshed,
  cured}` (`helpers/tick.cairo`), `durations::effective_duration`, the snapshot's
  `condition_duration` (CBT-02c), and step 3's regeneration in `types/world.cairo`. The report opens
  with a table: each rule of the list above, where it lives today, and what this lot adds.
- **The cost**: CBT-02d's re-proved bound, **≤ 3,447,872 L2 gas a tick inside a batch** (ENG-01 §9.2,
  `docs/reports/CBT-02d-tick-levers.md`), 2.35× the 1,469,435 target, carried to ENG-07.
- CAIRO.md §2 (D-167: unit tests in their module), §7 and §8 (D-143, D-147). COMMON.md, D-154. D-149.

## Scope
- In:
  - **Applying a condition** as an effect entry's rule: a function the executor calls with the
    target, the condition, the inflicted duration and the source's duration passives
    (`effective_duration`, `KNOCKDOWN_FLAT`), refreshing by `max`, nothing on a dead actor;
    Knocked down applied to an actor in activation **interrupts** it (§5.9, what it spends and keeps).
  - **`CURE`**: a duration of 0; nothing when absent.
  - **What a condition changes**: Crippled's move cost (2 ticks a tile, a member's and a goblin's,
    FX-15) as a function ENG-07's movement will call; Knocked down's "cannot act" (check the pipeline
    already holds it), "critical from any arc for a weapon hit" and "neither blocks nor evades" as
    predicates CBT-03a's hit takes as inputs (CBT-03a does not call them; it receives booleans).
  - **Step 3's degeneration** checked against §5.8 (the pips summed, clamped to [−10, +10], × 2) for
    members and goblins; fix it only if it disagrees, with a test.
  - **Tests** in the modules: every row of §3.2's MVP table, §6's edges for conditions, §10.3 to the
    unit, refresh at equal and smaller durations, a dead goblin, a cure of an absent condition.
  - **The per-tick budget line**: the cost of one application, one cure and the predicates, and the
    worst a tick can add (how many applications a tick can make at most, derived from design/19 and
    ENG-01's bounds), stated as a line added to CBT-02d's 3,447,872; carried into ENG-01 §9.2's table
    as this lot's row.
- Out: the executor that reads effect entries and dispatches them (CBT-05); the hit (CBT-03a); the
  post-MVP conditions (Dazed, Blind, Weakness, Deep wound, **P**); movement itself (ENG-07).
- Allowlist: `contracts/logic/src/models/goblin.cairo`, `models/member.cairo`, `helpers/tick.cairo`,
  `durations.cairo`, the condition-related parts of `types/world.cairo` (step 3), new files under
  `contracts/logic/src/` for this lot (with their module lines), `contracts/logic/tests/` (benchmarks
  only), `docs/architecture/ENG-01-interfaces.md` §9.2 (this lot's row), `contracts/logic/GAS.md` and
  `docs/BUDGETS.md` as generated. **Not** `types/hit.cairo` nor `exp2*` (CBT-03a's). Anything else is
  an escalation.

## Acceptance criteria
- [ ] AC-1 The inventory table: every rule of §3.2, §5.7, §5.8, §5.9 that concerns the five conditions,
      where it lives, tested.
- [ ] AC-2 Applying, refreshing, curing, interrupting by Knocked down, Crippled's move cost, and the
      predicates for CBT-03a, each a scoped function with its tests and §6's edges (no panic on a
      legal action, D-140).
- [ ] AC-3 §10.3 reproduced to the unit.
- [ ] AC-4 The per-tick budget line against 3,447,872, measured, in the report and ENG-01 §9.2.
- [ ] AC-5 D-143; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`;
      `class_sizes.py` (`TickLibrary` under 50 %).

## Audits
Quality with the organisation lens and determinism: `[GPT-6-Sol]`; cost: `[GPT-6-Astra]`; through
`nexus audit` (queued for Codex's reset), then the Codex review. A Claude-side quality lens may run
before the reset (D-170).

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the inventory table, the functions added, the edges, §10.3,
the per-tick budget line, the gas table of every test.
