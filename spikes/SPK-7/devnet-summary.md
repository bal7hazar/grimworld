runs: 3

| Transaction | L2 gas | L1 data gas |
|---|---:|---:|
| worst-case tick, A (assembled), adventurer waits | 2,960,960 | 512 |
| worst-case tick, B (stored), adventurer waits | 3,400,960 | 576 |
| worst-case tick, A (assembled), adventurer moves | 3,040,960 | 576 |
| worst-case tick, B (stored, re-centred and written back), adventurer moves | 3,360,960 | 768 |
| worst-case tick, S (SPK-2's stand-in), adventurer waits | 2,240,960 | 256 |
| worst-case tick, S (SPK-2's stand-in), adventurer moves | 2,320,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred), adventurer waits | 2,320,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred, nothing pending, re-centred), adventurer moves | 2,880,960 | 512 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, re-centred), adventurer moves | 4,848,960 | 768 |
| worst-case tick, A (assembled), adventurer moves into another chunk row | 2,880,960 | 448 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, chunk row changes), adventurer moves | 3,320,960 | 768 |
| reveal 1 chunk, no neighbour known, meadow | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, meadow | 2,133,200 | 320 |
| reveal 3 chunks, no neighbour known, meadow | 5,639,680–5,679,680 | 448 |
| reveal 3 chunks, 7 neighbours known, meadow | 5,317,680 | 448 |
| reveal 1 chunk, no neighbour known, forest | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, forest | 2,133,200–2,173,200 | 320 |
| reveal 3 chunks, no neighbour known, forest | 5,319,680–5,559,680 | 448 |
| reveal 3 chunks, 7 neighbours known, forest | 5,077,680–5,237,680 | 448 |
| reveal 1 chunk, no neighbour known, cave | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, cave | 2,173,200 | 320 |
| reveal 3 chunks, no neighbour known, cave | 5,639,680–5,919,680 | 448 |
| reveal 3 chunks, 7 neighbours known, cave | 5,557,680–5,797,680 | 448 |
| reveal 1 chunk, no neighbour known, ruin | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, ruin | 2,173,200 | 320 |
| reveal 3 chunks, no neighbour known, ruin | 5,559,680 | 448 |
| reveal 3 chunks, 7 neighbours known, ruin | 5,317,680–5,477,680 | 448 |

| Difference | L2 gas |
|---|---:|
| A − S, adventurer waits (the chunked map's part of the tick) | 720,000 |
| B − A, adventurer waits (stored, chunks kept in sync, against assembled) | 440,000 |
| B′ − A, adventurer waits (stored, occupancy deferred, its costliest case, against assembled) | -640,000 |
| A − S, adventurer moves (the chunked map's part of the tick) | 720,000 |
| B − A, adventurer moves (stored, chunks kept in sync, against assembled) | 320,000 |
| B′ − A, adventurer moves (stored, occupancy deferred, its costliest case, against assembled) | 1,808,000 |
| B′ − A, the move changes the chunk row, same destination (4 chunks written back) | 440,000 |

| Reveal | Most expensive biome | L2 gas (max over runs) |
|---|---|---:|
| reveal 1 chunk, no neighbour known | cave, forest, meadow, ruin | 2,455,200 |
| reveal 1 chunk, 4 neighbours known | cave, forest, ruin | 2,173,200 |
| reveal 3 chunks, no neighbour known | cave | 5,919,680 |
| reveal 3 chunks, 7 neighbours known | cave | 5,797,680 |
