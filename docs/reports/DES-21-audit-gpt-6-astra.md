# [GPT-6-Astra] Audit — PR 49 (DES-21) — design, security

## Verdict

**FAIL**

At **`6247949`**, F-11 and F-12’s original defects are resolved under the rulings. F-1 through F-10 remain resolved.

The fixes introduce **one major contradiction** in chunk loading and **one minor contradiction** in the recovery example. After this third fix loop, these findings require the project-manager disposition specified by OPERATIONS §6.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| F-13 | **minor — new** | [02-core-loop.md:379](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-49/docs/design/02-core-loop.md:379), example at line 386 | **The “batch ran” example promises suffix recovery that the specified algorithm does not provide.** | Start at sequence/clock 0. The first `Wait` executes, but its receipt is unavailable; a second `Wait` remains unsent. Stored predicted results are `(1,1)` and `(2,2)`. Recovery adopts `(1,1)` and re-simulates **every unconfirmed action**, starting with the first `Wait`. Its result becomes `(2,2)`, differing from its stored `(1,1)`. The first-mismatch rule therefore drops both actions. The table instead says the next actions are retained. | Correct the example to describe this conservative loss. Retaining an unconfirmed suffix after skipping already-executed actions would require a separately specified rule; do not infer that prefix from the action count. |
| F-14 | **major — new** | [02-core-loop.md:301](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-49/docs/design/02-core-loop.md:301), region view at line 504, CLI-03 item 12 | **The unconditional missing-chunk read can prevent exploration and movement near boundaries indefinitely.** | The client waits before entering any chunk its copy lacks, but `instance_region` returns only **revealed** chunks. A move that would reveal a new chunk cannot obtain that chunk from the preceding accepted block: the move itself must generate it. Waiting for that read creates a circular dependency, contradicting D-111’s client-computed reveal and line 198’s inclusion of reveal moves in batches. At a location boundary, [D-134](https://github.com/bal7hazar/grimworld/blob/d9af605b298b05878c922f3489d4697545718be8/docs/decisions/2026-09-28-chunk-borders.md#decision) makes the problem permanent: void chunks are never revealed or stored and must be assembled as constants without reading them. | Distinguish **revealed state missing from the cache**, **real chunks not yet revealed**, and **void chunks**. Fetch the first coherently; predict generation of the second under D-111 in the speculative overlay; synthesize the third under D-134 without reading or waiting. Define how views distinguish these cases and add reveal/boundary cases to the implementation requirements. |

**F-11 verification.** Recovery now reads nonce and instance state at one accepted block, adopts the snapshot without attributing execution, and re-simulates a prefix against persisted predicted results. Renumbering, the nonce to use and first-mismatch behavior are specified. This resolves the original reliance on unavailable transaction history. F-13 concerns the illustrative claim, not the accepted recovery algorithm.

**F-12 verification.** The authoritative copy now contains every revealed chunk and every goblin, including frozen actors and their full state. `instance_state` plus paged `instance_region` at one accepted block supplies restart and resynchronization data. The indexer is excluded from simulation, and ENG-01 includes restart/window-crossing checks. This resolves the original missing-actor-state defect; F-14 concerns the newly added loading prerequisite.

## Coverage

Reviewed the final-loop diff and cumulative PR against the rulings, ADR-0001/0002/0006/0007, design/04, design/08 and D-133. D-134 is absent from this branch’s files, so its decision and revised ADR-0006 were read from **`origin/main`**.

No additional contradiction was found in tick costs, goblin ordering, zero-tick restrictions, M-1…M-6, Fate’s accepted MVP weakness, the version-1 escalation, or the distinction between speculation and reorg rollback.

Read-only throughout. Working tree clean; diff whitespace check passed. No implementation tests were run for this documentation-only task.

## Final finding table

| Finding | Final status | Open severity | Disposition |
|---|---|---|---|
| F-1 — Gas bound | **Resolved** | — | 40M and weights remain provisional; ENG-01 must prove or replace them. |
| F-2 — Invocation versus transaction | **Resolved under ruling** | — | Limits and composition claims remain appropriately scoped. |
| F-3 — Sequence versus history | **Resolved under ruling** | — | Optimistic divergence remains accepted; no history guarantee is restored. |
| F-4 — Reorg depth | **Resolved** | — | Arbitrary rollback remains separate from two-batch speculation. |
| F-5 — Included reverts | **Resolved** | — | Fresh-nonce recovery, batch splitting and singleton stopping remain specified. |
| F-6 — Coherent reconciliation | **Resolved under ruling** | — | Pre-confirmed reads remain single-call; accepted multipart reads are pinned to one block. |
| F-7 — Standalone entrypoints | **Resolved** | — | Entry, transition, sequence and refusal semantics remain specified. |
| F-8 — Weighted backpressure | **Resolved** | — | Capacity is measured by weight, not a fixed action count. |
| F-9 — Batch age | **Resolved** | — | No elapsed-time loss guarantee is reinstated. |
| F-10 — Version-1 randomness | **Resolved under ruling** | — | Requirements and ADR escalation remain explicit; no closure claim returns. |
| F-11 — Unknown transaction outcome | **Resolved under ruling** | — | Recovery no longer requires transaction attribution. |
| F-12 — Snapshot coverage | **Resolved under ruling** | — | Full revealed-instance and frozen-actor state are available through pinned views. |
| F-13 — Recovery example | **New** | **minor** | Already-executed unconfirmed actions trigger the first-mismatch rule; the example incorrectly promises suffix retention. |
| F-14 — Missing-chunk loading | **New** | **major** | The loading prerequisite needs separate handling for cached, unrevealed and void chunks. |
## Orchestrator's note (`[Opus 5.5]`, 2026-09-28): escalated after three fix loops

PR 49 (DES-21) went through three fix loops; this is the fourth report. F-1 to F-12 are resolved.
Two findings are new, introduced by the third loop's fix of F-12:

- **F-14 (major)**: the client waits to read any chunk its copy lacks, but an unrevealed chunk can
  only come into being through the move that reveals it (D-111), and a void chunk is never stored
  (D-134): play would stall at every unexplored edge and at every location's boundary.
- **F-13 (minor)**: the "batch ran" example promises to keep actions the first-mismatch rule drops.

**Recommendation**: one narrow fourth loop on F-13 and F-14 only, with this ruling: the client's copy
knows three kinds of chunk: *revealed* (read, pinned, as now), *not yet revealed* (predicted by the
client's own generation under D-111 in the speculative overlay, then checked by reconciliation
like any result), and *void* (a constant under D-134, never read, never waited for); only revealed
chunks missing from the copy are read before the window reaches them; the views tell the three
apart; reveal and boundary cases join the ENG-01 and CLI-03 lists. F-13: the example is corrected to
the conservative loss. Then a re-audit on those two findings only. Merging with a known major
contradiction in the design ENG-01 reads would cost more later.
