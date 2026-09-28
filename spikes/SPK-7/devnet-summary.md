runs: 3

| Transaction | L2 gas | L1 data gas |
|---|---:|---:|
| worst-case tick, A (assembled), adventurer waits | 2,960,960 | 512 |
| worst-case tick, B (stored), adventurer waits | 3,400,960 | 576 |
| worst-case tick, A (assembled), adventurer moves | 3,040,960 | 576 |
| worst-case tick, B (stored, re-centred and written back), adventurer moves | 3,320,960 | 768 |
| worst-case tick, S (SPK-2's stand-in), adventurer waits | 2,200,960 | 256 |
| worst-case tick, S (SPK-2's stand-in), adventurer moves | 2,280,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred), adventurer waits | 2,280,960 | 320 |
| worst-case tick, B' (stored, occupancy deferred, nothing pending, re-centred), adventurer moves | 2,880,960 | 512 |
| worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, re-centred), adventurer moves | 4,808,960 | 768 |
| reveal 1 chunk, no neighbour known, meadow | 2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, meadow | 2,133,200 | 320 |
| reveal 3 chunks, no neighbour known, meadow | 5,639,680 | 448 |
| reveal 3 chunks, 7 neighbours known, meadow | 5,317,680 | 448 |
| reveal 1 chunk, no neighbour known, forest | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, forest | 2,133,200 | 320 |
| reveal 3 chunks, no neighbour known, forest | 5,239,680–5,479,680 | 448 |
| reveal 3 chunks, 7 neighbours known, forest | 4,997,680–5,237,680 | 448 |
| reveal 1 chunk, no neighbour known, cave | 2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, cave | 2,173,200 | 320 |
| reveal 3 chunks, no neighbour known, cave | 5,679,680–5,839,680 | 448 |
| reveal 3 chunks, 7 neighbours known, cave | 5,557,680 | 448 |
| reveal 1 chunk, no neighbour known, ruin | 2,415,200–2,455,200 | 320 |
| reveal 1 chunk, 4 neighbours known, ruin | 2,173,200 | 320 |
| reveal 3 chunks, no neighbour known, ruin | 5,559,680–5,759,680 | 448 |
| reveal 3 chunks, 7 neighbours known, ruin | 5,237,680–5,477,680 | 448 |

| Difference | L2 gas |
|---|---:|
| A − S, adventurer waits (the chunked map's part of the tick) | 760,000 |
| B − A, adventurer waits (stored, chunks kept in sync, against assembled) | 440,000 |
| B′ − A, adventurer waits (stored, occupancy deferred, its costliest case, against assembled) | -680,000 |
| A − S, adventurer moves (the chunked map's part of the tick) | 760,000 |
| B − A, adventurer moves (stored, chunks kept in sync, against assembled) | 280,000 |
| B′ − A, adventurer moves (stored, occupancy deferred, its costliest case, against assembled) | 1,768,000 |

| Reveal | Most expensive biome | L2 gas (max over runs) |
|---|---|---:|
| reveal 1 chunk, no neighbour known | cave, forest, meadow, ruin | 2,455,200 |
| reveal 1 chunk, 4 neighbours known | cave, ruin | 2,173,200 |
| reveal 3 chunks, no neighbour known | cave | 5,839,680 |
| reveal 3 chunks, 7 neighbours known | cave | 5,557,680 |
