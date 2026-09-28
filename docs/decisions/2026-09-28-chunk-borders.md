# Chunk borders: the window at a location's edge, and chunk corners

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from SPK-7 ([research](../research/SPK-7-chunked-maps.md), [report](../reports/SPK-7-chunked-maps.md), audit `[GPT-6-Astra]` PASS WITH FINDINGS, [#50](https://github.com/bal7hazar/grimworld/pull/50)) |
| To be answered by | `[Fable 5.1]` project manager (D-128); both amend ADR-0006 |
| Needed by | ENG-05 (chunk generation), ENG-07 (the window), the map library's N-3 |

ADR-0006 and D-120 settle neither point. SPK-7 kept its fixtures away from both and handled them
safely (the audit says so); the engine must choose.

## 1. The window at a location's edge

D-120: the window is 15 × 16 tiles, centred on the adventurer, not stored. An adventurer within 7
columns or 8 rows of the location's edge gives the window an origin below 0.

| Option | What it means | Cost |
|---|---|---|
| (a) **A margin of void chunks** around every location | The window stays centred; the chunks beyond the edge are void: wall everywhere, never revealed, never stored (assembled as a constant) | One more case in assembly (a constant mask instead of a storage read); none in storage |
| (b) Clamp the window | The window stops at the edge; the adventurer is off-centre | A clamp in assembly and in every local coordinate; sight may reach the ring, where goblins do not act (D-120's frozen ring) |
| (c) Keep locations away from the adventurer's reach | Generation never places a walkable tile within 7 × 8 of the edge | Wastes the outer chunks of every location |

**Recommendation: (a).** It keeps D-120 as written (the window follows the adventurer, centred) and
costs the least: a void chunk is the cheapest thing to assemble.

## 2. Chunk corners

A corner tile of a chunk is the only tile that touches a diagonal chunk. ADR-0006 § Joining chunks
speaks only of shared edges. SPK-7 keeps every corner as wall.

| Option | What it means | Cost |
|---|---|---|
| (a) **Corners are always wall** | Chunks connect through their edges only, never diagonally | A slightly less open map at the four corners; nothing to generate or check |
| (b) Corners follow their neighbours | A corner is open when both edges meeting there allow it | A rule across three chunks at reveal, and a case the reveal of one chunk cannot always settle (the diagonal neighbour may not exist yet) |

**Recommendation: (a).** Deterministic and local to one chunk (a reveal never depends on a diagonal
neighbour), and the openings of each side already connect chunks.

Expected: the project manager's decision on both, recorded here and in ADR-0006.
