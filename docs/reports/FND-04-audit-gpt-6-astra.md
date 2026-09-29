# [GPT-6-Astra] Audit — PR 71 (FND-04) — cost, design

## Verdict

**PASS — all ten findings resolved at 77f9f99. No new blocking finding or regression identified.**

The budget and ADR figures now distinguish measurements, conditional fits, derived arithmetic, and estimates. The chosen normalization is explicitly disclosed rather than presented as measured.

## Findings

| # | Final status | Severity remaining | Evidence |
|---|---|---|---|
| **1** | **Resolved** | — | [cost-budget.md:21](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-71/docs/architecture/cost-budget.md:21) identifies both **14,880 and its split as chosen normalizations**. Fit and floor qualifications propagate into the research, ADR-0001, ADR-0007, generated output, and REPORT. Independent refits across all **38** nonnegative admissible aggregates reproduce the ranges: new slot **452,808–453,691**, other slot **24,878–33,751**, floor **806,297–862,551**. Around the chosen aggregate ±2,000, the floor is **815,419–818,459**. |
| **2** | **Resolved** | — | [FND-04-slots.md:206](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-71/docs/research/FND-04-slots.md:206) now distinguishes **no observed zero-then-rewrite or instance-key recycling between enters** from ordinary overwrites, which were observed. The reuse check reproduces **45 enters, 180 distinct new keys, zero revisits after zeroing**. Recycling savings remain **E**. |
| **3** | **Remains resolved** | — | [cost-budget.md:73](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-71/docs/architecture/cost-budget.md:73) and ADR-0006 retain SPK-7’s actual reveal layout: terrain per chunk, revealed bitmap once per transaction, occupancy-at-reveal separately assumed. Slot-model arithmetic remains reproducible. |
| **4** | **Remains resolved** | — | ADR-0006 retains **window assembly at every tick**, distinguishes cached reads from assembly, and labels the **37.6M–44.2M** batch scenarios **E**, not proven bounds. No decision changed. |
| **5** | **Remains resolved** | — | Game-call traversal still counts topmost game invocations once. C leave reproduces **682,000 game gas / 2,386,685 non-game remainder**; AVNU leave reproduces **660,480 / 4,514,320**. |
| **6** | **Resolved** | — | [cost-budget.md:140](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-71/docs/architecture/cost-budget.md:140) and generated output correctly give **43.554% with batching alone** and **54.685% with shared reads/writes**, both **E**. The 27 additional felts remain included in the corrected expedition scenario: **$0.726 / $0.541**. The simplified **$0.725 / $0.540** reproduction remains separately labelled **E**. |
| **7** | **Remains resolved** | — | Planned moves join `play`. The spike’s `walk` remains a benchmark; the **17,388,623** move-only `play` projection is explicitly **E**, with its measurement path stated. |
| **8** | **Remains resolved** | — | Enter includes its entry draw; the generic Fate budget explicitly excludes it. |
| **9** | **Remains resolved** | — | Conventional medians remain **449,187.5** for new-slot pairs and **33,333.3** for the other-slot sample. |
| **10** | **Remains resolved** | — | Additional multicall headers remain **three felts / 15,360 gas**; the first call retains four header felts. Script, formula, and documentation agree. |

## Coverage

- Reviewed commits **89b943b** and **77f9f99**, the complete current budget and four ADR measurement sections, and [REPORT “Fix loop 2”](/home/claude/projects/grimworld/.claude/worktrees/cli-FND-04/REPORT.md:217).
- Ran `analyse.py`, `budget.py`, and `reuse_check.py` with `python3 -B`. **All three outputs match the committed files exactly.**
- Independently verified normalization sensitivity and both queue-share percentages. Checked previously resolved findings for regressions and searched for superseded claims in active documentation.
- No files changed, network calls, transaction submissions, or background commands. Working tree remains clean.
- Live CI was not independently checked. Trace capture and network readers are unchanged; the earlier limitation on definitive credential/owner-address absence verification remains.