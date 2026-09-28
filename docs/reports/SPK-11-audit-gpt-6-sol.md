# [GPT-6-Sol] Audit — SPK-11 — security, quality

## Verdict

**PASS.** No blocker, major, or minor finding remains open.

## Findings

| # | Final severity | Evidence |
|---|---|---|
| 1 | — resolved | The client checks the node tip **before** checking the answer’s block. The committed [demo](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/results/demo.txt:23) aborts a block between those reads and shows the orphan rejected. |
| 2 | — resolved | [LotCache](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/client.ts:145) owns stream readiness and verifies its head on `read()`. The [snapshot run](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/results/snapshot.txt:1) matches all 10,050 chain lots across 11 pages. |
| 3 | — resolved | The [indexer](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/indexer.ts:349) serves a block only after reconciliation and clears that served identity on rewind. The [replaced-block run](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/results/demo.txt:107) halts without serving the inconsistent replacement. |
| 4 | — resolved | Lossless `u64` storage and boundary values, including rewind, remain tested. |
| 5 | — resolved | The indexer inherits no signing key; a keyed RPC URL is confined to its environment and redacted from logs. |
| 6 | — resolved | Committed [benchmark output](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/spikes/SPK-11/results/bench.txt:1) supports all three event gas deltas and the revised speed, disk, memory, and RPC figures. |
| 7 | — resolved | The [research handoff](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/docs/research/SPK-11-indexer.md:40) now applies all six [scope decisions](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-11/docs/decisions/2026-09-28-indexer-scope.md:1) to reads, MVP timing, queries, and the nine proposed events. |
| 8 | — resolved | Upstream Apibara, its Starkstream fork, and hosted streams remain separately compared. |

## Coverage

Reviewed `origin/main...HEAD`, the fix-loop code, scope decision, and committed demo, snapshot, and benchmark outputs. **AC-1 through AC-5 are satisfied for the spike.** The client’s guarantee is correctly limited to its last block-validation read; a later reorg requires a new check. Pre-confirmed blocks and production range catch-up remain explicitly outside the prototype. This was read-only; I inspected the committed runs without rerunning node-backed commands.
## History

| Round | Verdict |
|---|---|
| 1 | FAIL: 1 blocker (orphaned state served on restart or mid-reorg), 6 majors, 1 minor |
| 2 (fix loop 1) | FAIL: 4 majors (read order, cache lifecycle and snapshot cap, reconciliation identity, scope decision) |
| 3 (fix loop 2) | PASS |

Run by `scripts/agent.sh AUD-SPK-11 codex gpt-6-sol`, reasoning high, read-only; model recorded by the CLI: `gpt-6-sol`.
