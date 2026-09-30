# CBT-02b — The tick's cost: two levers, the Hub wiring, and a proved bound

> D-161 (levers (a) and (b), no interface change), D-163 (the worst-case bound carried from CBT-02's
> final audit), D-160 (the capacity restrictions before any production snapshot). After CBT-02
> (#182). ENG-07 builds on it.

## Agent
Title: `[Opus 5.5] CBT-02b tick cost` · Profile: implement · Branch: `feat/cbt-02b-tick-cost`

## Goal
After this task the tick's pipeline costs less by the two levers D-161 chose, its cost section states
a **worst case proved term by term** (or says plainly which terms are only measured), and the
snapshot's flattening with its capacity checks is **wired into `Hub`**, so that no snapshot is built
without them.

## Context
- **CBT-02** (#182): `docs/reports/CBT-02-tick-pipeline.md` (Cost, Escalations, fix loops 1–3); the code
  in `contracts/logic/src/` (`helpers/tick.cairo`, `types/world.cairo`, `types/tick.cairo`, the models,
  `TickLibrary`); `docs/architecture/ENG-01-interfaces.md` §1.3 and §9.2.
- **D-161** (`docs/decisions/2026-09-29-cbt-02-tick-cost.md`): levers **(a)** no copies of the goblin
  struct across the three passes (hot fields apart, masks of due activations and free goblins) and
  **(b)** a cheaper split of a word into limbs (`packing::split`, ~5.8k a word); (c) and (d) are
  ENG-07's, (e) after ENG-07. The target: **1,469,435 L2 gas a tick** on average; the map library's
  share of a worst tick is 1.06–1.11 M (the same file). Above target: report, do not accept.
- **D-163** (`docs/decisions/2026-09-30-cbt-02-merge.md`) and CBT-02's final cost audit
  (`docs/reports/CBT-02-audit-cost-gpt-6-astra.md`): **COST-1a** the branch measurements must cover
  every legal arithmetic branch; **COST-1b** the library-call term with every count at its maximum;
  **COST-1c** the content-decoding allowance a demonstrated maximum, not an average; **COST-3** the
  terminology and figures consistent ("upper bound", never "worst state" where it is not). No test
  budget may rest on an unproved bound.
- **D-160** (`docs/decisions/2026-09-29-des-06-castes.md`, design/20): the capacity proof's restrictions
  must hold before any production snapshot. CBT-02 built the flattening in `grimworld_logic` but could
  not wire it: `Hub.set_build` must call it so that DS-2's floors refuse a build there, and `Hub.enter`
  must build its snapshot through it.
- docs/CAIRO.md §1–§2, §7–§8 (D-143, D-147), COMMON.md, D-154.

## Scope
- In:
  - **(a)** and **(b)**, the pipeline's results unchanged (every CBT-02 test passes unchanged), each
    measured before and after on the same states;
  - **the bound**: every term of the tick's and of load and store's cost bounded by a maximum over all
    legal states and reached, or shown not reachable, term by term (COST-1a–c), in the report and in
    §9.2; where a term can only be measured, say so and label it measured; COST-3's wording everywhere;
  - **the wiring**: `Hub.set_build` calls the flattening (DS-2's floors refuse there); `Hub.enter`
    builds the snapshot through it; tests that an illegal build is refused and that `enter`'s snapshot
    is the flattening's; `set_build`'s and `enter`'s figures re-measured against D-158's targets.
- Out: levers (c) and (d) (ENG-07), design levers (e), `play` (ENG-07).
- Allowlist: `contracts/logic/src/**`, `contracts/persistent/src/systems/hub.cairo` (`set_build`, `enter`
  and their helpers), `contracts/persistent/src/**` models and helpers they need (D-143), the three
  packages' tests, `docs/architecture/ENG-01-interfaces.md` §1.3 and §9.2, `GAS.md` and `docs/BUDGETS.md`
  as generated, the node probes under `contracts/tools/`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 (a) and (b) applied; every CBT-02 test passes unchanged; the cost before and after, per tick,
      on representative and bound states.
- [ ] AC-2 COST-1a–c: the bound proved term by term, or each unproved term labelled measured; COST-3's
      wording consistent; no budget rests on an unproved bound.
- [ ] AC-3 The flattening wired into `set_build` and `enter`, tested; their figures against D-158.
- [ ] AC-4 The cost against 1,469,435 stated; an overrun reported with its make-up, not accepted.
- [ ] AC-5 D-143; CI green; `python3 scripts/gas_budgets.py --check`; `class_sizes.py`.

## Audits
Cost (`[GPT-6-Astra]`) and quality with the organisation lens (`[GPT-6-Sol]`), through `nexus audit`;
the Codex review before the merge.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the levers and their measured effect, the bound term by
term, the wiring and its tests, the figures against 1,469,435 and D-158, the gas table of every test.
