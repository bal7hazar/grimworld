# CBT-05a — The executor: one layer owns a carrier's entries

> CBT-05's first part (PLAN row CBT-05; D-172 puts SPK-15's lever L3 into it). **Launched after CBT-03a
> (#229, the hit) and CBT-04 (#228, the conditions) merge** (they wait for Codex, 2026-10-04 13:36 UTC):
> it calls both. CBT-05b (the action's costs, §5.3, and traps, §5.11) follows it.

## Agent
Title: `[Opus 5.5] CBT-05a executor` · Profile: implement · Branch: `feat/cbt-05a-executor`

## Goal
After this task **every carrier** (a weapon attack, an attack skill, any other skill, a potion; a trap's
payload once CBT-05b triggers it) **resolves through one executor**, exactly as design/19 §5.14 says,
with SPK-15's **lever L3** built in: the step-1 hook `Rules::resolve` of CBT-02's pipeline and the
action phase call it; it reads the carrier's entries, evaluates their guards once, takes its target sets
now, runs CBT-03a's hit and applies the other entries (CBT-04's conditions, heal, life steal, energy,
holding effects through §5.7) in §5.14's order, moves the counters and adrenaline (§5.12), and kills at 0
(§5.13); deterministic, never panicking on a legal carrier (D-140), its cost stated against the bound.

## Context
- **design/19**: **§5.14** (the carrier's hit, legal carriers, execution steps 1–6), §5.5 steps 5–9
  (applying a hit's outcome), §5.7 (holding effects: identity by carrier, same carrier, stance, lowest free
  slot, eviction), §5.9 (activation resolved in step 1, interrupts), §5.12 (counters, adrenaline), §5.13
  (deaths, `GoblinKilled` order, the adventurer at 0), §3 and §4 (each kind's rule), §2.3–§2.4 (shapes,
  filters, guards: FX-40), §6 (edges), §10.1, §10.2, §10.4, §10.6–§10.9 (worked examples).
- **What it calls**: CBT-03a's `HitTrait::resolve` (`types/hit.cairo`, `Arc` in `types/combat.cairo`);
  CBT-04's `MemberConditionTrait`/`GoblinConditionTrait::apply`, `cure`, the predicates
  (`types/infliction.cairo`); CBT-02's pipeline and its `Rules` hooks (`types/world.cairo`), the content
  index and `Sheets` (CBT-02d, `types/tick.cairo`). **Inventory first**: the report opens with a table of
  §5.14's steps and §5.7's rules, where each lives today, and what this lot adds.
- **SPK-15's lever L3** (D-172; `spikes/SPK-15/README.md`, `src/executor.cairo`, PR #234): **the member's
  guard read once a tick and updated whenever the executor holds, spends or ends an effect** (a block's
  charge spent mid-tick must reach the next hit: SPK-15's `test_executor_guard_two_hits`); **a carrier's
  goblins written back in one rebuild**; **the skills' entries decoded once a call into the sheets** (an
  in-call type: no frozen interface changes). Its measured target: the executor at about 3.96 M a worst
  tick against 6.77 M naive (E). The next two, not measured: a lighter awake goblin value (the 24-felt
  rebuild costs 114,670 a write) and step 2's writes kept pending: try them, measure, keep what pays.
- **Carried to this lot** (PLAN, CBT-05): the executor's lookups by id (`hold`, `put`, a stance) scan the
  content (~82,000 a skill): read at positions (CBT-02d); `MOVEMENT` (FX-18) is not in the tick's sheets,
  so Crippled's move takes it as a boolean (CBT-04): put the held effect's kind in the sheets; a
  `CONDITION`/`CURE` with condition 6–9 panics: the registry's validators refuse it until FX-22 (CBT-04;
  check `Registry.set_record`'s validators and add the refusal if missing, with a test); clamp the scaled
  `DAMAGE`/`ATTACK_BONUS` to the kind's bounds before building a `Hit` (CBT-03a, §6); one copy of the
  weapon-strength rule (CBT-03a's `HitTrait::weapon_strength` or the snapshot's); §10.7's guard read once
  (FX-40) tested here (CBT-03a).
- **Geometry is ENG-02's** (line of sight, arcs on `hexx`), waiting for the map library. The executor
  takes it through a **trait** (the arc a hit arrives from, whether the target is on the source's front
  tile, a shape's tiles from a centre clipped to the window): a stub in this lot's tests, the real one
  from ENG-02 and CBT-03b. Name the trait and freeze its signature in the report.
- **The cost**: CBT-02d's bound (≤ 3,447,872 a tick inside a batch), CBT-04's line (2,114,010
  re-measured, SPK-15), CBT-03a's (+693,750); ENG-01 §9.2. `TickLibrary` must stay under 50 % of the class
  limit (ENG-01 §1.3): if the executor pushes it over, stop and report (a second library class is the
  project manager's decision).
- CAIRO.md §2 (D-167), §7, §8 (D-143, D-147). COMMON.md, D-154. **D-149**: no event of ENG-01 changes
  (the logic package emits none; what `Instances` emits from the world, kills included, stays as frozen).

## Scope
- In:
  - **The executor** (§5.14 steps 1–6) as a scoped trait in the logic package, called by the step-1
    `resolve` hook for an activation that concludes and by the action phase for an immediate carrier;
    every legal carrier of §5.14's table; illegal ones are the content pipeline's (check the validators
    refuse each row of §5.14's *Legal carriers*; add what is missing, with tests).
  - **Each entry kind** of §3 and §4 that the MVP's content uses (design/19 §8's coverage table), applied
    by its rule: `DAMAGE` (via the hit), `ATTACK_BONUS`/`HIT_PENETRATION` (hit modifiers), `HEAL`,
    `LIFE_STEAL`, `REGENERATION`, `CONDITION`, `CURE`, the energy kinds (§3.3), the holding kinds of §3.4
    through §5.7, the control kinds of §3.5 the MVP uses. A post-MVP kind (**P**) refused by the
    validators, not executed.
  - **§5.5 steps 5–9** after the hit: health, the hit flag, the on-hit effects, adrenaline and `hits`, the
    target's +¼ strike, death at 0 (§5.13) in resolution order.
  - **L3** as above, each part measured against the naive version (test pairs).
  - **Tests** in their modules: §5.14's steps and order, each kind, §5.7's four cases, §6's edges for
    carriers, §10's worked examples named above to the unit, two hits in one tick against one guard.
  - **The per-tick budget line**: the executor's worst a tick (its derivation from design/19 and ENG-01:
    the member's carrier, 8 goblins' carriers), stated against the bound and written into ENG-01 §9.2.
- Out: the action's legality and costs, facing, quick cast (§5.3, CBT-05b); traps' placement and
  trigger (§5.11, CBT-05b); the AI choosing a goblin's carrier (ENG-07); geometry (ENG-02, CBT-03b);
  perception (ENG-07, with L4).
- Allowlist: `contracts/logic/src/**` (new files welcome); `contracts/persistent/src/systems/registry.cairo`
  for the validators' refusals only; the packages' tests; `docs/architecture/ENG-01-interfaces.md` §9.2;
  `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 The inventory table; §5.14's steps in order, each tested; every MVP kind applied by its rule.
- [ ] AC-2 §5.7's four cases, §5.12's counters, §5.13's deaths in resolution order, each tested; §10's
      worked examples named above reproduced to the unit.
- [ ] AC-3 L3's three parts built and measured (test pairs) against the naive executor; the guard updated
      at every effect write, with the two-hit test.
- [ ] AC-4 The geometry trait named, its signature frozen, stubbed in tests.
- [ ] AC-5 The carried items above, each done or answered.
- [ ] AC-6 The per-tick budget line in the report and ENG-01 §9.2; `TickLibrary` under 50 % or the stop.
- [ ] AC-7 D-143; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`; `class_sizes.py`.

## Audits
Determinism, D-140 and quality with the organisation lens: `[GPT-6-Sol]`; cost: `[GPT-6-Astra]`;
security (the validators' refusals, a carrier that passes them and panics): `[GPT-6-Astra]`; through
`nexus audit`, then the Codex review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the inventory, the executor, each kind, L3's measures, the
geometry trait, the carried items, the per-tick budget line, the gas table of every test.
