# Needs — map library

What the game asks of the map library. Written by the game's side, answered by the
library's orchestrator through releases. The list of milestone L-M1 is in
[PLAN.md](../../PLAN.md#milestone-l-m1--what-the-game-needs-first); details and
signatures are added here as the design settles.

| # | Need | Asked | Answered in version |
|---|---|---|---|
| N-1 | Generation of a board given its margins | 2026-09-28 | — |
| N-2 | Edges and openings between boards | 2026-09-28 | — |
| N-3 | Assembly of a board of **15 × 16** from up to 4 chunks of 15 × 15, the origin on an even global row (detail below) | 2026-09-28, revised the same day (D-120) | — |
| N-4 | Cutting a board by a mask | 2026-09-28 | — |
| N-5 | Line of sight | 2026-09-28 | — |
| N-6 | Range and ring as geometry | 2026-09-28 | — |
| N-7 | Rotation, arcs relative to a facing | 2026-09-28 | — |
| N-8 | One flood for many walkers, with extra obstacles | 2026-09-28 | — |
| N-9 | `snforge_std` declared as a **dev-dependency**, so that the library resolves next to any test setup of its consumer. *(The rest of N-9, a release for Cairo 2.13, is void since ADR-0007: the game is on Cairo 2.19)* | 2026-09-28 (FND-01), reduced the same day | — |

## N-9 in detail: the game cannot build `origami_hexmap` 1.8.0 (FND-01, 2026-09-28)

**Void since ADR-0007 (D-123)**: the game dropped Dojo and is on Cairo 2.19, the library's
compiler. What remains of N-9: `snforge_std` as a dev-dependency. Earlier arbitration: [docs/decisions/2026-09-28-N-9-compiler-target.md](../decisions/2026-09-28-N-9-compiler-target.md).
N-9 is part of milestone L-M1; SPK-7 runs standalone on Cairo 2.19 meanwhile; the compiler
target is studied by LIB-03 and decided by the owner at gate L-G2.

Found by `[Sonnet 5]` FND-01 (repository scaffold,
[PR #18](https://github.com/bal7hazar/grimworld/pull/18)), checked by the game orchestrator.

| | |
|---|---|
| The game's toolchain | **Cairo 2.13** (Scarb 2.13.1, snforge 0.51.2), fixed by SPK-5: `sozo` 1.8.7 compiles with Cairo 2.13 and the Dojo test harness `dojo_snf_test` 1.8.0 depends on `snforge_std` exactly 0.51.2 ([docs/research/SPK-5-toolchain.md](../research/SPK-5-toolchain.md) §2). Dojo has published nothing newer |
| `origami_hexmap` 1.8.0 | The only published version (scarbs.xyz index, 2026-09-28). The origami workspace at 1.8.0 targets `starknet ^2.19.4` and `snforge_std 0.61.0` |
| Failure 1, resolution | Next to `dojo_snf_test` 1.8.0: *"origami_hexmap 1.8.0 depends on snforge_std >=0.61.0, <0.62.0 … grimworld 0.1.0 depends on snforge_std >=0.51.0, <0.52.0"*: the package declares `snforge_std` as a regular dependency, not a dev-dependency |
| Failure 2, compilation | Alone on Scarb 2.13.1: `error: Item core::internal::bounded_int::BoundedInt is not visible in this context` at `map.cairo:10`, `helpers/bits.cairo:12`, `helpers/rng.cairo:24` |
| Consequence | The game cannot use the library at all today: SPK-7 (planned on 1.8.0, D-119), then ENG-02 and ENG-05. SPK-2 writes its own plain flood, as its brief allows |
| What would answer it | A release of the map library (`origami_hexmap` or `hexx-cairo`) that builds on Cairo 2.13 with `snforge_std` as a dev-dependency; or the game moving to a newer Cairo once Dojo publishes one; or the fallback of R-15 / R-18 (the game's own code, rooms and corridors for dungeons) |

## Answers to the library's questions (LIB-02, 2026-09-28)

Asked in `bal7hazar/hexx-cairo`, `docs/decisions/L-G1-hexx-port.md`, "Points for the game".
Answered by the project manager on 2026-09-28. These are conventions of implementation: they
do not change what a player meets. Each stands unless a measurement of LIB-03 or SPK-7 shows
it wrong, in which case the library's orchestrator says so with the figure. Point 4 changed
an accepted ADR and was decided by the owner
([window-follows](../decisions/2026-09-28-window-follows.md), D-120).

| # | Point | Answer | Why |
|---|---|---|---|
| 1 | Margins (N-1) | **(a) The seam is inside the chunk**: the chunk's own outer ring holds the tiles copied from its neighbours; the 13 × 13 interior evolves | It fits one felt; 17 × 17 does not. It is what ADR-0006 says: "a new chunk copies the edge of each neighbour" |
| 2 | Chunks on odd rows | **A parity flag in the layout**; chunks stay 15 × 15 | The size is fixed by ADR-0006 and by the window. The flag is two constants (the complement `even` mask, swapped up and down factors) |
| 3 | Global axis | **The library's convention is kept** (`+x` West in the index, odd-r). Global coordinates of the game follow it; the client mirrors for display | Results of `origami_hexmap` are API since 1.8.0 and cannot move. East and West are names, the screen is the client's |
| 4 | Sight beyond the window | **The window follows the adventurer**, is 15 × 16 and is not stored (owner, D-120) | What the player sees never depends on a state the player does not know |
| 5 | Flood and occupancy (N-8) | **Rule (a)**: one flood per tick on the occupancy frozen at the start of the tick; current occupancy filters each goblin's candidate tiles, in ascending id order; fallback to the same layer when no closer tile is free | It is what design/02 and design/04 say ("one flood per tick, not one per goblin"). Rule (b) costs up to 8 floods. Moves are numeric API: the rule is frozen at the first release |
| 6 | Line of sight | **The game's rule**: integer line, ties to the lower tile index, symmetric. A documented deviation from `hexx`'s `line_to`, excluded from the parity table at ties | design/04 § Ranges. A rule that changes under translation cannot be mirrored by the client |
| 7 | "Clockwise" | **Keep `hexx`'s names and semantics** in the `hexx`-named module, and document that its `clockwise` turns counter-clockwise on a north-up map. The game's facing and arcs (N-7) are written with directions (`d ± 1`, `d ± 2`, `d + 3`), never with the word | Parity with `hexx` is checked by name; renaming would make the table lie |

## N-3 in detail: the window (D-120, 2026-09-28)

| | |
|---|---|
| Output | One board of **15 columns × 16 rows** (240 tiles, one felt), per layer |
| Input | The chunks of 15 × 15 the window overlaps: always 2 rows of chunks, 1 or 2 columns: **2 or 4 chunks**; per chunk its layers (terrain, occupied); the global origin of the window |
| **Constraint** | **The origin is on an even global row.** The function refuses an odd origin rather than return a board that is a different hex grid from the map |
| Where the adventurer is | Local column 7; local row 7 when its global row is odd, 8 when even. Functions indexed from the centre (N-5, N-6) take the local position or the parity as input |
| Method | No loop over rows. Per chunk and per layer: one mask from a table of constants (the rectangle that lands in the window), one shift by `15·dy + dx` as a multiplication or division by a power of two; the pieces are disjoint and added. The ring of the window is then imposed as wall |
| Called | **At each tick**: the window is not stored. Worst case to budget: 4 chunks, two layers each |
| Fallback sizes | Sight 5: 13 × 14. The width then differs from the chunk's 15: the shift is no longer one-dimensional, to be designed if SPK-7 asks for the fallback |
| Parity flag (point 2) | Still needed for generation and seams of chunks on odd rows; not used by the window |

## Answers to the questions of LIB-03 (gate L-G2, 2026-09-28)

Asked in `bal7hazar/hexx-cairo`, `docs/decisions/PENDING-L-G2.md`, "Questions for the game".
Answered by the project manager. They do not change what a player meets, except Q-5, which is
a rule of the game and is with the owner ([PENDING-L-G2](../decisions/PENDING-L-G2.md) §4).

| # | Question | Answer | Why |
|---|---|---|---|
| Q-5 / D-25 | Does the tick truncate the flood; what does a goblin beyond do? | **With the owner.** Recommended: 15 layers; a goblin not reached holds its position | A rule of the game |
| D-24 | Does a wall tile at the end of a line block sight? | **No**: only the tiles strictly between the two ends are tested | The end of a line is an actor or a tile the player may target; whether it can be targeted is the game's check, not the line's |
| D-22 | Ring tiles of a chunk that face no generated neighbour | **Drawn at generation and frozen**, as the plan says | ADR-0006 § Joining chunks: a new chunk copies the edge of each neighbour already generated and draws its other edges; the first of two chunks decides where the opening is |
| D-23 | `cut` clears the ring as well as what is outside the mask | **No, for the game: `cut` keeps the ring tiles that are inside the mask.** The game needs `grid & mask` | The ring of a chunk is a seam: it holds the openings to the neighbouring chunks, and design/18 opens edges **before** cutting by the outline. A cut that clears the ring would close every passage of a border chunk towards the inside of its zone. The window's ring is imposed by the assembly, not by `cut`. If the library keeps a variant that clears the ring, it has another name |
| D-32 | A goblin next to an adventurer on an open edge tile may step onto it | **The plan**, as a contract of the library | It does not occur in the game: the window follows the adventurer, who is never on its ring (D-120); and the game filters every step by occupancy |
| Q-1 | Earshot (radius 8) reaches beyond the window | **A distance test on global coordinates, without a board.** A pack alerted outside the window changes state and stays frozen until the window reaches it | design/04: earshot is a range, not a path |
| Q-4 | Does SPK-7 consume the release candidates? | **No**: SPK-7 runs on `origami_hexmap` 1.8.0. Its figures are measured again on the first release candidate that carries N-3 and N-8. ENG-02 and ENG-05 consume 0.1.0 | The spike must not wait; results of the engine are identical by the plan's own rule |
