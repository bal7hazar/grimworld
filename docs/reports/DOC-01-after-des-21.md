# [Sonnet 5.5] DOC-01 — The documents after DES-21

## Summary
Every item 1 to 15 of DES-21's Escalations and D-136's rule are written in the allowlisted documents. PR: https://github.com/bal7hazar/grimworld/pull/63 (CI: all checks pass, none failing or pending). Model matches the brief.

**Precondition that was false**: the brief says ADR-0006 §4, CONTEXT and `docs/decisions/2026-09-28-after-DES-21.md` already carry D-136. On this branch (and on origin/main) they do not: commit 65425a2 (PR #60) removed them (the decision file, CONTEXT's D-136 row, the ADR-0006 §4 row, a line of docs/needs/hexmap.md), although 87cbc14 (#59) added them. I restored the ADR-0006 §4 row (allowlisted) and wrote design/02 from the brief's text and from 87cbc14's decision file. See Escalations.

## Files changed
- docs/design/02-core-loop.md: D-136 rule in *The client's copy of the instance* (unrevealed = wall; sight never reaches it; dungeon edges; no wait); OP-1 removed (OP-2 kept); ENG-01 item 8 and CLI-03 item 12 agree; a misplaced table row fixed.
- docs/architecture/ADR-0001, ADR-0002, ADR-0006, ADR-0007: as in the table.
- CONTEXT.md §5 only: glossary.
- docs/design/07, 09, 18: one line each.

| Item | File | What changed |
|---|---|---|
| 1 | CONTEXT §5 | Queue redefined (planned); added Batch, Played/planned, Rewind, Sequence, Weight |
| 2 | ADR-0001 | Decision point 3: "played actions travel in batches (D-133, design/02)" |
| 3 | ADR-0002 | Rule 3: "end a batch, and a planned queue"; "our client submits a Fate action alone" |
| 4 | ADR-0006 | Option A line marked not retained, reveal computed under option C (D-111) and can ride in a batch; "queue stops" row now planned queues only, evaluated by the client |
| 5 | design/07, 18, 09 | "and a batch" (07, 18); Client row "played batches" (09) |
| 6 | design/02 | Already there (D-05 amendment); nothing added |
| 7 | design/02 | Already there (40M target, SPK-7/SPK-1b in *Size*); the decision file's own bound line is not mine |
| 8 | ADR-0001 | Consequences: reorg to any depth, speculation not a rollback bound, pointer to design/02 *The chain's answer* |
| 9 | ADR-0001 | Rate limits count gas, not transactions |
| 10 | ADR-0002 | New rule 7: multicall; MVP accepted weakness; version 1 must not draw from anything the transaction can steer |
| 11 | ADR-0002 | Rule 5: every precondition checked before drawing |
| 12 | ADR-0002 | Version 1 requirements: attempt-stable draws, no re-roll by abort, allowed calls stated |
| 13 | ADR-0001 | Client installs state only from one snapshot; not-found is an unknown outcome |
| 14 | ADR-0001, ADR-0007 | Simulation only over a chain-read copy; indexer never a source; recovery by nonce and snapshot |
| 15 | CONTEXT §5 | Copy of the instance, Recovery added |
| D-136 | design/02, ADR-0006 §4 | Rule in design/02; ADR-0006 §4 row restored (was missing) |

## Commands run
- `git diff --stat`: 9 files, 76 insertions, 25 deletions.
- `git push -u origin HEAD`, `gh pr create`, `gh pr checks 63 --watch --interval 30`: all pass.

## Cost
—

## Acceptance criteria
- AC-1: table above.
- AC-2: OP-1 gone (`grep OP-1 docs/design/02-core-loop.md` is empty); rule in *The client's copy of the instance*, consistent with the ADR-0006 §4 row.
- AC-3: grep for "action queue|queued actions|waits for" in the allowlisted files: only design/07's "action queue and a batch" remains, and design/02's waits for a *revealed* chunk and the entry draw.
- AC-4: CONTEXT.md diff touches §5 lines only (glossary rows).

## Deviations from the brief
- ADR-0006 §4: the D-136 row was added, not only checked, because it was absent.
- ADR-0002: rule 7 added, and the header line "Rules 1 to 3, 5 and 6 apply from the MVP" updated to include it.

## Escalations
1. **PR #60 (65425a2) reverted D-136's files on main**: `docs/decisions/2026-09-28-after-DES-21.md`, the D-136 row in CONTEXT §6, the line in `docs/needs/hexmap.md`, and probably PROGRAMME.md's line. Recover them from 87cbc14. CONTEXT §6 and decisions/ are not mine, so I did not restore them.
2. The other documents (design/11, ENG-01 brief) may cite D-136 and the missing decision file.

## Open questions
- D-136 says "the client never waits for a chunk", but design/02 still says play waits for a *revealed* chunk missing from the copy (after a reorg or a device change). I kept that sentence, since DES-21 wrote it and D-136 does not name it. Confirm it means "never waits for an unrevealed chunk".
