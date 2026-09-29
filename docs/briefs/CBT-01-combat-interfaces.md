# CBT-01 — Freeze the combat interfaces

> D-150, pulled forward while the engine chain waits for the map library. Written from design/19
> (DES-04, #139, the 43 rules of D-155). CBT-02 (the tick pipeline), CBT-03 (damage), CBT-05 (skills)
> and ENG-07 (`play`) build on it; DES-06 fills the caste sheets it shapes.

## Agent
Title: `[Opus 5.5] CBT-01 combat interfaces` · Profile: implement · Branch: `feat/cbt-01-combat-interfaces`

## Goal
After this task the combat's data is **frozen as compiling code**: the actor's stats, the effect
entry and its enumerations, the skill, the caste (the shape of DES-06's sheet, not its values), the
modifier's and the item's effects, and the state an actor carries between ticks, each as a model or
a type with its packing, round-trip tests and budgets, so that CBT-02 to CBT-05 and ENG-07 implement
rules without inventing a field.

## Context
- **`docs/design/19-effects.md`** in full (v0.5, decided by D-155): the catalogue, the entry format
  and its encoding (§2), the enumerations, the resolution order (§5), the state inventory and its
  fit (§7). Where it says a figure is ENG-05's estimate (the registry-read schedule, F-16), keep it
  an estimate. `docs/decisions/2026-09-29-des-04-effects.md` (D-155).
- **Notes the final audit handed to you** (`docs/reports/DES-04-audit-gpt-6-astra.md`): **F-21**, the
  unguarded armor's bound (9,945) sums `255 + 255 + 37 × 255` but the expression also includes
  personalisation: settle whether the two 255 limits include it, and size the field accordingly.
- **`docs/architecture/ENG-01-interfaces.md`**: §3.1 (packing, `LIVE`), §3.2 (the member's and the
  goblin's words, which ENG-06 now writes), §3.5 (the `SKILL`, `CASTE`, `MODIFIER`, `ITEM`, `BASE`
  records and their parts), §9–§10 (budgets). design/03, 04, 05, 15 as design/19 cites them. D-140
  (the damage table `Exp2`, ENG-02a; armor floored at 0).
- **docs/CAIRO.md, §7 and §8 (D-143, D-147)**: models, types, helpers scoped in traits, checks in
  `Assert` impls, a `mod errors` per file; no free function without a written reason; tracking a
  model's event is optional. COMMON.md.

## Scope
- In:
  - **Types and models in `grimworld_logic`**: the effect kinds, conditions, targets, area shapes,
    guards and every other enumeration design/19 closes; the effect entry with its encoding; the
    skill, caste, modifier and item effect records as the registry's parts (through ENG-03's
    `content::Record<T>`); the actor's stats; each with pack and unpack, round trips at the field
    bounds, refusals of values too wide.
  - **The state an actor carries** (design/19 §7): if it changes a word ENG-01 froze and ENG-06
    writes (the member's or goblin's words), make exactly the change §7 decided, update ENG-06's
    code and tests that write or read that word, and state the cost in slots and gas. Any other
    change to a frozen layout is an escalation.
  - **ENG-01 §3.5 and §3.2** amended to state the frozen layouts.
- Out: the rules themselves (the tick, damage, conditions, skills: CBT-02 to CBT-05), the values of
  castes and skills (DES-06, BAL-01), `play` (ENG-07).
- Allowlist: `contracts/logic/src/**` (new files welcome, D-143), the member and goblin models of
  `contracts/ephemeral/src/models/` and the lines of `contracts/ephemeral/src/systems/instances.cairo`
  that write them, the registry's layouts of these kinds, the three packages' tests,
  `docs/architecture/ENG-01-interfaces.md` §3.2 and §3.5, `GAS.md` and `docs/BUDGETS.md` as
  generated. A rule design/19 does not settle is an escalation, not a decision.

## Acceptance criteria
- [ ] AC-1 Every enumeration, field and bound of design/19 exists as a type or a model, named as the
      document names it; a table in the report maps each section of design/19 to its code.
- [ ] AC-2 Every record and word packs and unpacks losslessly at its bounds, and refuses a value too
      wide (tests); the registry records fit their part counts.
- [ ] AC-3 F-21 settled and the armor field sized from it.
- [ ] AC-4 Any change to a word ENG-06 writes is the one design/19 §7 decided, with ENG-06's tests
      passing and its cost stated.
- [ ] AC-5 D-143; CI green; `python3 scripts/gas_budgets.py --check`; `class_sizes.py`.

## Audits
Design, determinism and quality: **`[GPT-6-Astra]`**, with the organisation lens of CAIRO §8.

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the map from design/19 to code, the layouts with their
bits, F-21, any change to ENG-06's words with its cost, the gas table of every test.
