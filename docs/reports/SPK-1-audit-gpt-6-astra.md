# [GPT-6-Astra] Audit — PR 45 (SPK-1) — cost, security

## Verdict

**PASS WITH FINDINGS** at `cdd274c`.

Five findings are resolved. Finding 3 is reduced to **minor**; finding 7 retains a **minor** wording inconsistency. No remaining major or blocker identified. Under OPERATIONS §6, the minors require correction or explicit deferral with a PLAN entry.

The raw measurements are unchanged. S1/S2 remain **$0.874/$0.685 without tip**, or **$0.878/$0.688 with the measured 0.1 Gfri tip**. Both exceed $0.50.

## Findings

| # | Original severity | Final status / severity | Location | Evidence and remaining fix |
|---|---|---|---|---|
| 1 | major | **Resolved — none** | [lib.mjs:26](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/lib.mjs:26), [check_secrets.py:38](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/check_secrets.py:38), [redacted.py:59](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/redacted.py:59) | Felt syntax is checked before numeric conversion; URL parsing exceptions are caught without displaying input. `configure()` installs redaction before constructing the provider. The price wrapper captures stdout/stderr and redacts before writing them. Isolated synthetic checks confirmed value-free malformed-input failures and redacted normal output/errors. Full-suite limitations are recorded below. |
| 2 | major | **Resolved — none** | [lib.mjs:98](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/lib.mjs:98), [measure.mjs:23](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/measure.mjs:23), [deploy.mjs:21](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/deploy.mjs:21) | Existing outputs—including empty files—now cause refusal before configuration/network activity. The scripts create outputs with `openSync(..., "wx")`; the README removes shell redirection. Recovery requires an explicit flag and preserves the prior file by renaming it. Deployment additionally refuses an existing `sepolia.json`. Per-invocation transaction bounds remain intact. |
| 3 | major | **Still open — minor** | [latency.py:29](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/latency.py:29), [latency.py:78](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/latency.py:78), [research:77](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/docs/research/SPK-1-sepolia.md:77) | The invalid previous-response lower bounds are removed, percentiles are correctly named, and the current p50 verdict is now inconclusive. However, **410 ms is still treated as an uncertainty ceiling**: `verdict(1500, 1000)` returns “missed” despite having no lower bound. A median submission round trip is neither a maximum nor a receipt-request bound. **Fix:** without a valid lower bound, classify above-threshold transition latency as inconclusive; remove “up to” 410 ms. Future intervals also require a fresh, consistent RPC status view. Current sample conclusions are unaffected. |
| 4 | major | **Resolved — none** | [research:194](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/docs/research/SPK-1-sepolia.md:194) | The report explicitly says D-129’s reversal condition is **not met**, lists the below-local expedition/tick figures and above-local light actions, and leaves interpretation to the project manager. The erroneous “within 5%” assertion is removed. |
| 5 | minor | **Resolved for this PR — none** | [check_secrets.py:59](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/check_secrets.py:59) | Git failures now fail the check; log, report and research note are required; coverage is printed. Isolated tests returned exit **1** for a failed Git command and missing required inputs. History scanning now covers all refs, with binary-content exclusion disclosed. This remains a patch-based scanner, not certification of every historical blob. |
| 6 | minor | **Resolved — none** | [research:136](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/docs/research/SPK-1-sepolia.md:136), [money.py:154](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/spikes/SPK-1/money.py:154) | Both residuals are explicitly unattributed. The 1.34M figure is labelled the smallest observed non-game remainder for these actions/account, rather than a protocol floor. The approximately 0.52M derived game budget is conditional. Arithmetic remains correct. |
| 7 | minor | **Still open — minor** | [research:109](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/docs/research/SPK-1-sepolia.md:109), [research:203](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-45/docs/research/SPK-1-sepolia.md:203) | The new formula correctly includes the tip, reproduces **103/103 invoke fees**, states the zero-tip projection assumption, and calculates its effect correctly. However, §3 retains the original sentence saying fees are charged “at the block’s price,” without the tip. **Fix:** change that sentence to “block L2 price plus the signed tip,” or refer to §5. |

### New findings

None beyond the residual issues recorded against findings 3 and 7.

## Coverage

Reviewed commits `6e5f866`, `28924fd` and `cdd274c`, including configuration, output guards, redaction wrapper/tests, secret scanning, latency, money and research wording.

- **Offline analyses:** `latency.py` and `money.py` both exited successfully and reproduced their committed outputs exactly.
- **Measurement preservation:** deployment, measurement, probe and price raw outputs, plus `sepolia.json`, are byte-for-byte unchanged from the initial audit.
- **Requested redaction suite:** ran `test_redaction.py`. Its three Python malformed-input cases passed. The three Node cases stopped because `starknet` is not installed here; the suite then stopped because the sandbox prohibits temporary-directory creation. **The complete suite did not pass in this environment.**
- **Supplemental verification:** read-only, in-memory checks exercised configuration with a stubbed provider, exception redaction, wrapper output, and checker failure handling using synthetic values. These support the reviewed fixes but do not replace the complete integration suite. `test_guard.py` was reviewed, not executed.
- **Security invariants:** chain-ID verification remains the first explicit network operation in both sending scripts; User-Agent headers and transaction caps remain present. No real credential scan was possible, so actual-value absence from historical logs is not independently certified.

No network calls, transactions, installations or successful file writes occurred. The working tree remained unchanged.