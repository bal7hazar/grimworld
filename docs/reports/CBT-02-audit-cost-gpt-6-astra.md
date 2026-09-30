no report was written; this is the last message of the agent
# [gpt-6-astra] Audit — CBT-02-3 — cost

## Verdict

**FAIL**

Read revision **`4e4aa77f4941512200a3e486ed898472aaaa9777`**. The published arithmetic reproduces from the committed measurements, but **COST-1 remains open: not every term is established as an upper bound**. No new measured whole-call counterexample is claimed.

## Findings

| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| COST-1a | major | `contracts/logic/tests/test_tick.cairo:1565`; `models/member.cairo:155`; `models/goblin.cairo:112` | The new branch measurements do not establish maxima over all legal arithmetic branches. | The branch fixtures retain zero adrenaline and fixed regeneration values. Load fixtures give every goblin skill zero adrenaline and every member-bar skill the same cost. They therefore omit, for example, successive `cost > cap` updates from legally increasing skill costs. The added scan and effect-type allowances do not explicitly bound these omitted paths. | Enumerate and measure the remaining arithmetic branches, or derive conservative instruction-cost allowances for them. Tie each allowance to its tests and document its derivation. |
| COST-1b | major | `docs/architecture/ENG-01-interfaces.md:994`; `contracts/logic/tests/test_tick.cairo:1143`; `types/world.cairo:37` | The library-call term does not have “every count at its maximum.” | `Words.killed` crosses the ABI and survives load/store. The benchmark starts with zero kills and returns eight. A legal input containing a kill from the action phase, followed by eight pipeline deaths, serializes one incoming and nine outgoing IDs. The direct baseline merely carries that array through; the library call must serialize the additional elements. | Measure or conservatively price the maximum legal incoming and outgoing kill lists, then update the call term and total. |
| COST-1c | major | `docs/architecture/ENG-01-interfaces.md:996`; `contracts/logic/tests/test_tick.cairo:1237`; `types/tick.cairo:168` | The content-decoding allowance is an average, not a demonstrated maximum. | **42,710** is `(421,470 − 336,050) / 2`: one skill plus one caste. That skill has regeneration in its first entry. `SkillSheet::read` can scan three entries; potion decoding is another path. Applying this average to the 38-skill/5-caste/4-potion mix does not establish an upper bound. | Budget the maximum legal decoding path separately for each record kind, then weight those maxima by their record counts. |
| COST-3 | minor | `contracts/logic/tests/test_tick.cairo:865,1031,1062,1153`; `docs/architecture/ENG-01-interfaces.md:129` | The terminology and figures are not consistently updated. | Comments still say “worst state … by construction,” “worst single tick,” and “worst 10-tick batch.” §1.3 still reports **59,823,300** for load/store, while the current recorded subtraction is **59,921,060**. | Describe these fixtures as measured scenarios, reserve “upper bound” for the derived result, and synchronize §1.3 with §9.2. |

## Coverage

Read the brief, Cairo cost rules, relevant design/19 bounds, pipeline and actor implementations, library interface, cost tests, generated gas tables, and ENG-01 §§1.3/9.2.

Read-only checks found:

- **539 test declarations** across logic, ephemeral and persistent have budgets matching their package tables.
- All recorded budgets lie between the recorded measurement and `ceil(1.05 × measurement)`.
- Package tables agree with `docs/BUDGETS.md`.
- The published subtraction and bound arithmetic reproduce.

Earlier fixes remain present in source: retained effects on all 100 goblins, the 100-candidate awake-selection benchmark, full load/store equality, fixture-subtracted library-call measurements, and amortized loading/content costs. **The earlier COST-2 report was unavailable, so its identifier cannot be independently certified as closed.**

Runtime verification was incomplete. The filtered `snforge` run and `gas_budgets.py --check` produced no output before I interrupted them; both ended with exit **130**. `class_sizes.py` exited **1** with `class_sizes: no artifacts; build the workspace first`. No files changed.

D-161’s accepted overrun and CBT-02b’s Hub wiring are not findings.

The final table below reproduces **committed measurements and proposed bounds**, not fresh gas measurements or certified bounds:

| Measure | Representative | Published bound / allowance |
|---|---:|---:|
| Pipeline, one tick | 628,617 | 12,618,207 |
| Pipeline, ten-tick trace, per tick | 633,024 | 12,618,207 |
| Load/store, once per call | — | 62,118,160 |
| Library-call overhead, once per call | — | 2,578,020 |
| Library execution, ten ticks, per tick | 961,079 | 19,087,825 |
| Content, amortized per tick | 193,549 | 474,137 |
| **Combined share per tick** | **1,154,628** | **19,561,962 — not certified** |
| Awake selection, separately reported | — | 4,264,890 |
