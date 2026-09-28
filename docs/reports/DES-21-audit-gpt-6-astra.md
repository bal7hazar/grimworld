# [GPT-6-Astra] Audit — PR 49 (DES-21) — design, security

## Verdict

**FAIL — one major remains**, to carry into ENG-01 under the supplied merge ruling.

At **`2f8c9c8`**, F-13 is resolved. F-14’s read/wait problem is corrected, but its new chunk classifier assumes a registry outline that dungeons do not have. F-1 through F-12 remain resolved under the earlier rulings.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Requirement to carry into ENG-01 |
|---|---|---|---|---|---|
| F-14 | **major — partially resolved** | [02-core-loop.md:312](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-49/docs/design/02-core-loop.md:312), views at line 518, CLI-03 item 12 | **Chunk classification is specified for zones but incorrectly generalized to dungeons.** | The draft says every location’s outline is registry content, then classifies unrevealed coordinates by membership in that outline. [ADR-0006:177](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-49/docs/architecture/ADR-0006-chunked-maps.md:177) explicitly distinguishes registry-defined zone outlines from dungeon outlines that emerge during exploration. Dungeons instead have a target chunk count, generated borders and frontier constraints. At an open dungeon frontier before the target count is reached, the classifier needs to permit further generation, but the prescribed registry outline does not exist. Dungeons are included in the MVP. | **Freeze chunk classification separately for zones and emerging dungeons.** Zones may use the registry outline. Dungeons must use their generated boundaries, frontier and chunk-count rules; expose any required state coherently through the views. Make contract and client classification agree, including speculative reveals. Add tests for dungeon frontier growth, preservation of the last opening before the target count, and boundary closure when that count is reached. |

**F-13:** The [corrected example](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-49/docs/design/02-core-loop.md:401) now describes the conservative loss accurately: replaying an already-executed, unconfirmed first action causes a mismatch, so the remaining local suffix is discarded. It no longer promises suffix retention.

**F-14’s completed portions:**

- Revealed chunks missing from the copy are read at a pinned accepted block.
- Unrevealed chunks are generated in the speculative overlay without waiting for stored data.
- Void chunks are constants, without reads or waits.
- The client waits for the standalone entry draw before predicting anything in the instance.
- The views return chunk-kind information; ENG-01 item 8 and CLI-03 item 12 include reveal and boundary checks.
- Design/11 limits the loading wait to previously explored data missing from the client.

These changes remove the original circular wait and respect D-111/D-134. The remaining issue is specifically how those kinds are determined for emerging dungeons.

## Coverage

Reviewed the final-loop diff, affected views, ENG-01 item 8, CLI-03 item 12, design/11, and the earlier finding dispositions. Checked the merged D-134 decision and ADR-0006 against the new classifier, alongside the relevant execution, randomness, multiplayer and MVP rules.

No regression was found in F-1 through F-12. The remaining F-14 requirement does not reopen the accepted gas target, recovery algorithm, snapshot approach or MVP randomness ruling.

Read-only throughout. Working tree clean; whitespace checks passed for both changed design files. No implementation tests were run for this documentation-only task.

## Final finding table

| Finding | Final status | Open severity | Disposition |
|---|---|---|---|
| F-1 — Gas bound | **Resolved** | — | Provisional target; ENG-01 must prove or replace it. |
| F-2 — Invocation versus transaction | **Resolved under ruling** | — | Limits and composition claims remain correctly scoped. |
| F-3 — Sequence versus history | **Resolved under ruling** | — | Optimistic divergence remains explicitly accepted. |
| F-4 — Reorg depth | **Resolved** | — | Arbitrary rollback remains separate from bounded speculation. |
| F-5 — Included reverts | **Resolved** | — | Nonce handling, splitting and singleton stopping remain specified. |
| F-6 — Coherent reconciliation | **Resolved under ruling** | — | Single-call pre-confirmed reads and consistently pinned accepted reads. |
| F-7 — Standalone entrypoints | **Resolved** | — | Entry, transition, sequence and refusal semantics remain specified. |
| F-8 — Weighted backpressure | **Resolved** | — | Waiting depends on weighted capacity. |
| F-9 — Batch age | **Resolved** | — | No elapsed-time loss guarantee. |
| F-10 — Version-1 randomness | **Resolved under ruling** | — | Requirements and ADR escalation replace the closure claim. |
| F-11 — Unknown transaction outcome | **Resolved under ruling** | — | Recovery uses observable state without execution attribution. |
| F-12 — Snapshot coverage | **Resolved under ruling** | — | Revealed chunks and frozen actors are available through pinned views. |
| F-13 — Recovery example | **Resolved** | — | Example now states the conservative suffix loss. |
| F-14 — Missing-chunk handling | **Partially resolved; carry into ENG-01** | **major** | Read/generate/constant behavior is correct; dungeon classification must follow its emerging outline rather than a nonexistent registry outline. |
## Merge exception (`[Opus 5.5]`, 2026-09-28)

**Merged after four fix loops with one major open**, by the project manager's decision: a fourth
loop was allowed on F-13 and F-14 only, with no fifth; a major left by its re-audit is merged as an
open point of the document and carried into ENG-01's brief. F-13 is resolved. F-14 is resolved for
zones and open for dungeons (the kind of an unrevealed chunk where the outline emerges while
explored): design/02 *Open points*, OP-1 (commit e82d475), and ENG-01's PLAN row. OP-2, storage
slots per transaction (quiver's measurement), was added at the same time.
