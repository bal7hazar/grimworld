# [GPT-6-Astra] Audit — PR 51 (SPK-1b) — cost, security

## Verdict

**PASS.** At `c167003`, findings **1 and 8 are closed**, and findings **2–7 remain closed**. No new findings.

No reachable transaction-submission or account-spending path remains in the reviewed spike code. Findings 1 and 7 are closed through retirement, not approval of the former recovery logic.

## Findings

Severity below records each finding’s original severity. No further fixes are requested.

| # | Final status | Severity | Location | Evidence |
|---|---|---|---|---|
| 1 | **Closed by retirement** | major | [lib.mjs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/lib.mjs:22), [test_retired.mjs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/test_retired.mjs) | The SDK provider is module-private and never returned. `account`, `makeSender`, and `tracked` refuse before construction, callbacks, or submission. RPC access uses a private, explicit read-method allowlist; transaction, paymaster, estimation, and unknown methods are rejected. Both measurement scripts contain only a refusal. |
| 2 | **Closed** | major | [lib.mjs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/lib.mjs) | Separate receipt-fee and owner-spending accounting is unchanged. Sending retirement introduces no accounting regression. |
| 3 | **Closed** | major | [lib.mjs:95](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/lib.mjs:95) | Redaction-before-truncation remains intact. The read allowlist retains the RPC method used by the redaction regression test. |
| 4 | **Closed** | minor | [research note](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/docs/research/SPK-1b-fixed-part.md:18) | Conditional cost estimates and their assumptions are untouched by this commit. Prior closure carries forward. |
| 5 | **Closed** | minor | [check_secrets.py](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/check_secrets.py:80) | Required-burner validation and empty-inventory rejection are untouched. Prior closure carries forward. |
| 6 | **Closed** | minor | [research note](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/docs/research/SPK-1b-fixed-part.md:85) | The corrected numerical explanations are untouched. Prior closure carries forward. |
| 7 | **Closed by retirement** | major | [measure.mjs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/measure.mjs), [measure-d.mjs](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/measure-d.mjs) | Both files now contain only the retirement import and refusal. Recovery, keyed `Account` construction, AVNU client construction, funding, and submission code have been removed. Both entrypoints exit **5** offline. |
| 8 | **Closed** | minor | [README.md:30](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-51/spikes/SPK-1b/README.md:30) | The README now describes the retirement test’s actual coverage and explicitly identifies the removed ledger tests. The measurement scripts are labelled retired. |

## Coverage

Review was limited to **`git show HEAD` and its five touched files**, carrying forward the preceding audit for unchanged material.

- Ran `test_retired.mjs` under **`env -i`**, using the matching locally installed **starknet.js 10.8.0** through an in-memory dependency-resolution hook: **13 checks passed**, zero fetch calls.
- Additional offline checks confirmed both scripts exit 5; the provider remains unexported after synthetic configuration; **16 forbidden calls through `rpcRaw` and `rpc`** are refused; and all three sending helpers refuse without invoking callbacks or transport.
- Import and configuration produced no fetch calls. No keyed SDK account or AVNU client is reachable. Allowed read methods still work against the local stub.
- HEAD leaves measurement outputs, ledgers, analysis, and numerical conclusions untouched. Previously verified totals remain **44 transactions**, **3.6938 STRK receipt fees**, and **3.9654 STRK owner spending**.
- The commit passes `git diff --check`; the worktree remains clean.

No credentials were accessed, files written, network requests made, or transactions submitted.
## Orchestrator's note (`[Opus 5.5]`, 2026-09-29): merge exception and the programme's figures

**Merged after four fix loops** by the project manager's decision (one narrow re-audit allowed after
the third, then merge): that re-audit passed at c167003. Every round after the first was about
retiring the spike's ability to send (findings 1 and 7 closed by retirement, not by approving the
former recovery code); the measurements were confirmed at every round.

**The three figures the programme needs** (from `docs/research/SPK-1b-fixed-part.md` and SPK-1's
receipts):

1. **The fixed part of a transaction with the burner class**: 717,435 L2 gas sending directly
   (OpenZeppelin v3.0.0), against 1,087,585 for the owner's account (1.52× smaller, measured). With a
   paymaster it is larger: 1,587,885 with a relayer of our own (+500,300; the non-game remainder
   1.77× the reference), 3,654,080 through AVNU's public paymaster in default mode (+2,566,495;
   3.35×). Sponsored mode needs an API key: not measured.
2. **The expedition under D-133's batches of 10** (an estimate from SPK-1's receipts, not a
   measurement): the 100 one-action fight transactions become 10 batches of 10 worst ticks (10 ×
   3,564,913 game + about 1,194,875 non-game with the burner), and the other 58 (S1) or 46 (S2)
   transactions each save 370,150 with the burner. S1: about 820.6M L2 gas instead of 986.7M,
   **about $0.73** instead of $0.874; S2: about 611.3M instead of 772.9M, **about $0.54** instead of
   $0.685 (today's prices, zero tip, L1 data gas scaled with L2). Not counted: the saving of storage
   slots a batch changes once (OP-2, ENG-01).
3. **Test STRK spent**: SPK-1 72.22 (105 transactions), SPK-1b 3.97 of the owner's money (44
   transactions, 3.69 in receipt fees): **76.19 test STRK** in all.
