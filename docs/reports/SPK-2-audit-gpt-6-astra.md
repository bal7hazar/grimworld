# [GPT-6-Astra] Audit — SPK-2 — cost

## Verdict

**PASS WITH FINDINGS.** C-1 through C-6 are resolved. One non-blocking documentation note remains.

The figures are now decision-grade **for the scoped local-node spike, with the stated caveats**. The receipt-based expedition estimates remain **$0.692–$0.928**. The correlated optimization case is a sensitivity model, explicitly conditional on its assumed linear split—not a measured saving or production cost floor.

## Findings

| # | Final severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| C-1 | **note — resolved** | [Research §8.2](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/docs/research/SPK-2-cost.md:567) | Unsupported overhead attribution withdrawn. | Invocation figures are explicitly non-additive; the rounding explanation and 0.76–0.88M account/protocol allocation are withdrawn. The capped serpentine residual recomputes to **−592,000**. Transaction costs use receipts rather than this residual. | None. |
| C-2 | **note — resolved** | [Controlled pairs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/docs/research/SPK-2-cost.md:589) | Previous closure stands. | Equal goblin storage, matched owner-check settings and shared logic remain unchanged. Checked native calls supply the expedition estimates. | None. |
| C-3 | **note — resolved within spike scope** | [Capped fixture search](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/spikes/SPK-2/adversarial.py:215) | Previous closure stands. | D-127’s cap, the 15-layer/eight-reached-goblin fixture, oracle coverage and measured receipts are unchanged. This remains a stress case for the scoped melee tick. | None. |
| C-4 | **note — resolved** | Research §8.6 | Unsupported library saving remains withdrawn. | No replacement numerical saving is claimed; equivalent-work benchmarking remains required. | None. |
| C-5 | **note — resolved** | [Break-even calculation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/spikes/SPK-2/money_devnet.py:269) | Correct fixed-DA calculation retained. | The regenerated output reproduces the existing scenario totals and break-even prices. | None. |
| C-6 | **note — resolved** | [Research §9.4](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/docs/research/SPK-2-cost.md:761), [calculations](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/spikes/SPK-2/money_devnet.py:314) | Equal allocation is distinguished from scenario-specific fight budgets; correlated reductions are explicitly assumed. | Independent calculation reproduces fight budgets **295,792 / 2,836,494 / 2,862,094 / 340,592 / 2,589,914** for S1–S5. It also reproduces the correlated slope **1,659,874.098**, S1’s zero-tick modeled cost **$0.489553**, and its threshold factor **r = 0.023820**. | None. |
| C-7 | **note — open, non-blocking** | [Research §9.4](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-2/docs/research/SPK-2-cost.md:781) | The stated discrepancy with the previous audit compares different fight costs. | The previous audit’s **$0.632482 / $0.628536** used **1,800,000** L2 gas. The new **$0.635396 / $0.631451** uses **1,833,096**. Both calculations are correct; there is no unexplained $0.003 discrepancy. | Replace the “not investigated” sentence with this explanation. |

## Coverage

Reviewed loop 3 at **6327161**, against previously audited **dd386ae**; `origin/main` remains **4ba87c3**. Changes are confined to the research report, measurement-script documentation, money calculation and generated output.

Executed the money script read-only: its output matches the committed file exactly. Independently recomputed all five fight budgets and correlated scenarios using decimal arithmetic and committed receipts/prices. C-2 through C-5 retain their prior closure because their implementations and measurement evidence are unchanged.

No files were written, and no node or Cairo suite was rerun. Mainnet metering, real account/paymaster costs and omitted game work remain outside what these figures establish.
## History

| Round | Head | Verdict |
|---|---|---|
| 1 | `641edc1` | FAIL: 3 majors (native meter misread, 11 storage slots against 1, 12-layer fixture not the worst case), 2 minors |
| 2 (fix loop 1, then loop 2 for D-127) | `dd386ae` | FAIL: 1 major (equal allocation presented as the fight budget), 1 minor (non-additive traces) |
| 3 (fix loop 3) | `6327161` | PASS WITH FINDINGS; C-7 fixed by the orchestrator on main |

Run by `scripts/agent.sh AUD-SPK-2 codex gpt-6-astra`, reasoning high, read-only; model recorded by the CLI: `gpt-6-astra`.
