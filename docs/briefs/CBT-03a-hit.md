# CBT-03a — One hit: block, evasion, armor, damage

> D-170 (`docs/decisions/2026-10-01-game-slots-until-codex.md`): CBT-03's part that needs no geometry,
> pulled forward while Codex is out (until 2026-10-04 13:36 UTC), beside CBT-04 in disjoint files.
> **The arc and the flank are inputs** here; ENG-02 (line of sight and arcs on `hexx`) computes them
> later, and CBT-03b wires them. Its Codex audits and review queue for the reset; it merges after
> ENG-R1a and CBT-04.

## Agent
Title: `[Opus 5.5] CBT-03a hit` · Profile: implement · Branch: `feat/cbt-03a-hit`

## Goal
After this task **one hit is computed exactly as design/19 §5.5 steps 1 to 4 and §5.6 say**, as a pure,
scoped function: from the hit's inputs (its class, the arc it arrives from, the source's strength and
base damage, the target's armor terms, the penetrations and percents that apply, the target's state
flags) to its outcome (stopped: missed, blocked with a charge spent, evaded; or landed with its
damage), with every edge of D-140 and §6, deterministic, never panicking on a legal input. CBT-05's
executor gathers the inputs from the world and applies the outcome (§5.5 steps 5 to 9).

## Context
- **design/19**: §3.1 (`DAMAGE`, `ATTACK_BONUS`, damage types), §4 (the passives that a hit reads:
  `DAMAGE_PERCENT`, `PENETRATION`, `ARMOR`, `ARMOR_VS`, `HALVE_FIRST_HEAVY_HIT`, …), **§5.4** (hit
  classes and what applies to each), **§5.5 steps 1–4** (arc, miss/block/evade, signed armor with
  D-140's floor, penetration capped at 100, the exponent clamped to [−160, +80], `⌊base × table(x) /
  2^16⌋`, the percents summed once and truncated, ≥ −100, clamped to [0, 65,535], FX-19's halving),
  **§5.6** (block, evasion, miss; a knocked-down or sleeping target; what a hit is), §6 (edges),
  §10.7 (a guard crossing 50 %), §10.8, §10.9. design/04 (*Edges*, arcs: critical +40 %, axe +25 %,
  strength `5 × rank` capped by level for a weapon, `3 × level` for a spell or a trap), design/15
  (the weapon's damage after its requirement).
- **D-140** (`docs/decisions/2026-09-29-damage-edges.md`) and **ENG-02a**'s `Exp2` table
  (`contracts/logic/src/helpers/exp2.cairo`, `exp2_table.cairo`): use it, do not rebuild it.
- **CBT-01's types** (`types/combat.cairo`, `types/effect.cairo`, `types/passive.cairo`): the hit class,
  the arcs, the damage types, as frozen; a field this lot needs and CBT-01 lacks is an escalation.
- **Conditions are CBT-04's**, running at the same time: "the target is knocked down" (critical from
  any arc, neither blocks nor evades) arrives as an input boolean; do not call or edit CBT-04's files.
- **The cost**: CBT-02d's re-proved bound, **≤ 3,447,872 L2 gas a tick inside a batch** (ENG-01 §9.2,
  `docs/reports/CBT-02d-tick-levers.md`), 2.35× the 1,469,435 target, carried to ENG-07.
- **D-140's mirror**: the client recomputes the rules in TypeScript (SPK-4), checked by vectors from the
  Cairo code: emit a vector table from the tests (inputs → outcome) in a form a TypeScript test can read.
- CAIRO.md §2 (D-167), §7 and §8 (D-143, D-147). COMMON.md, D-154. D-149.

## Scope
- In:
  - **A new module** `contracts/logic/src/types/hit.cairo` (or `models/`, if CAIRO §7 places a value
    type there: say which and why): the hit's input and outcome types and `HitTrait` (§5.5 steps 1–4,
    §5.6), with `HitAssert` and `errors` for what an input may not be.
  - **Strength by class** (§5.4: weapon `5 × rank` capped by level; spell and trap `3 × level`; item from
    the recipe), the base damage (the weapon's after requirement + `ATTACK_BONUS` for attack skills), the
    arc's critical (+40 %, axe +25 %, from any arc on a knocked-down target), the flank, block (front and
    front-side only, a charge spent), evasion (melee, every arc, FX-11), Blind's miss (**P**: the input
    exists, the MVP never sets it), the first hit on a sleeping target unblockable.
  - **Tests** in the module: every row of §5.4's table that this lot covers, every edge of §6 that
    concerns a hit (armor below 0, penetration above 100, the exponent at both clamps, percents below
    −100, damage at both bounds, a 0-damage hit is a hit), §10.7–§10.9 where they concern the hit's
    computation, and the vector table for the TypeScript mirror (JSON lines, in the form of SPK-4's
    `spikes/SPK-4/vectors/vectors.jsonl`, under `contracts/logic/vectors/`).
  - **The per-tick budget line**: the cost of one hit at its costliest path, and the worst a tick can
    add (the most hits a tick can compute, derived from design/19 and ENG-01's bounds: the awake
    goblins' attacks, an area skill's targets), stated as a line added to CBT-02d's 3,447,872; carried
    into ENG-01 §9.2's table as this lot's row.
- Out: arcs and flank from positions (ENG-02, then CBT-03b); applying the outcome to the world (§5.5
  steps 5–9: CBT-05); conditions (CBT-04); skills (CBT-05).
- Allowlist: the new module and its line in `contracts/logic/src/types.cairo` (or `models.cairo`); a
  new vectors file if needed; `contracts/logic/tests/` (benchmarks only, a new file);
  `docs/architecture/ENG-01-interfaces.md` §9.2 (this lot's row); `contracts/logic/GAS.md` and
  `docs/BUDGETS.md` as generated. **Not** `models/goblin.cairo`, `models/member.cairo`,
  `helpers/tick.cairo`, `durations.cairo`, `types/world.cairo` (CBT-04's). Anything else is an
  escalation.

## Acceptance criteria
- [ ] AC-1 §5.5 steps 1–4 and §5.6 as one scoped pure function; each rule of §5.4's table it covers
      tested; the inputs that ENG-02 and CBT-04 will provide named.
- [ ] AC-2 Every edge of §6 concerning a hit tested; no panic on a legal input (D-140).
- [ ] AC-3 A vector table for the TypeScript mirror, generated from the tests.
- [ ] AC-4 The per-tick budget line against 3,447,872, measured, in the report and ENG-01 §9.2.
- [ ] AC-5 D-143; unit tests in their module (D-167); CI green; `gas_budgets.py --check`;
      `class_sizes.py`.

## Audits
Determinism, D-140's edges and quality with the organisation lens: `[GPT-6-Sol]`; cost: `[GPT-6-Astra]`;
through `nexus audit` (queued for Codex's reset), then the Codex review. A Claude-side quality lens may
run before the reset (D-170).

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the function and its inputs, the table of §5.4's rules
and §6's edges with their tests, the vectors, the per-tick budget line, the gas table of every test.
