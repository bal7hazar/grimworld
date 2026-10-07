# D-208: ENG-05 randomness, zone quota hosts order-free

| | |
|---|---|
| Decided by | project manager, 2026-10-03; read by the Overseer, not reversed |
| Status | Accepted 2026-10-03 (project manager) |

## Decided

- Zone quota hosts are made order-free.
- Dungeons keep an order-dependent exit position under D-111. A Rift HEART's level is fixed to its band.
- ADR-0006 is amended: every chunk's word is fixed at entry.
- The re-audit states the dungeon residue with a figure.
- A dungeon outline fixed at entry is the PLAN item that removes the residue.

## Measured residue (2026-10-07)

Until the lot that fixes a dungeon's outline at entry merges, a modified client can force a dungeon floor's exit 1 chunk from the entry: up to N − 2 chunks shorter (10 at N = 12), bounded only by N. Measured by ENG-05's randomness re-audit (#348, merged 9ffd4ff). This residue blocks any deployment to a non-test network until that lot removes it; its re-audit must measure the residue to zero.

## The residue removed (ENG-10b, 2026-10-07)

ENG-10b builds ENG-10a's design (ADR-0006 §3, *A dungeon floor's outline, fixed at entry*; D-223,
D-224): a floor's chunks, its open seams and every quota's hosts, the exit's and the Heart's among
its farthest chunks, are drawn once at `create` from the entry draw and stored with the instance; a
seam's openings come from the seam's own stream. Its zero-residue test on the real path
(`contracts/logic/tests/test_zero_residue.cairo`, 22 floors of 6 and 12 chunks, 7 orders each,
t-0077's forcing order among them) finds the same chunks, exit chunk, exit-to-entry distance in
chunks, edges, seam openings and walked distance in tiles in every order: **0 chunks and 0 tiles**
on that sample. The randomness re-audit (t-0099, Opus, at 1fdee83): a modified client gains 0
chunks and 0 tiles in a dungeon, checked by reading every reveal path, while nothing feeds the
instance's entropy (no production feeder exists). Its finding 1 bounds that figure: a seam's opening
tiles are derived from the instance's current entropy, so the first lot that feeds it would move
them again unless it re-seeds the seams from something fixed at `create` (PLAN, *The first entropy
feeder*). Until ENG-10b merges, the residue above still blocks any non-test deployment.

## What would reverse it

The owner, or a re-audit figure for the dungeon residue that D-111 does not accept.

## Sources

D-111, ADR-0006, ENG-05.
