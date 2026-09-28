# Needs — map library

What the game asks of the map library. Written by the game's side, answered by the
library's orchestrator through releases. The list of milestone L-M1 is in
[PLAN.md](../../PLAN.md#milestone-l-m1--what-the-game-needs-first); details and
signatures are added here as the design settles.

| # | Need | Asked | Answered in version |
|---|---|---|---|
| N-1 | Generation of a board given its margins | 2026-09-28 | — |
| N-2 | Edges and openings between boards | 2026-09-28 | — |
| N-3 | Assembly of a board from up to 4 chunks | 2026-09-28 | — |
| N-4 | Cutting a board by a mask | 2026-09-28 | — |
| N-5 | Line of sight | 2026-09-28 | — |
| N-6 | Range and ring as geometry | 2026-09-28 | — |
| N-7 | Rotation, arcs relative to a facing | 2026-09-28 | — |
| N-8 | One flood for many walkers, with extra obstacles | 2026-09-28 | — |

## Answers to the library's questions (LIB-02, 2026-09-28)

Asked in `bal7hazar/hexx-cairo`, `docs/decisions/L-G1-hexx-port.md`, "Points for the game".
Answered by the project manager on 2026-09-28. These are conventions of implementation: they
do not change what a player meets. Each stands unless a measurement of LIB-03 or SPK-7 shows
it wrong, in which case the library's orchestrator says so with the figure. Point 4 changes
an accepted ADR and is with the owner
([PENDING-window-follows](../decisions/PENDING-window-follows.md)).

| # | Point | Answer | Why |
|---|---|---|---|
| 1 | Margins (N-1) | **(a) The seam is inside the chunk**: the chunk's own outer ring holds the tiles copied from its neighbours; the 13 × 13 interior evolves | It fits one felt; 17 × 17 does not. It is what ADR-0006 says: "a new chunk copies the edge of each neighbour" |
| 2 | Chunks on odd rows | **A parity flag in the layout**; chunks stay 15 × 15 | The size is fixed by ADR-0006 and by the window. The flag is two constants (the complement `even` mask, swapped up and down factors) |
| 3 | Global axis | **The library's convention is kept** (`+x` West in the index, odd-r). Global coordinates of the game follow it; the client mirrors for display | Results of `origami_hexmap` are API since 1.8.0 and cannot move. East and West are names, the screen is the client's |
| 5 | Flood and occupancy (N-8) | **Rule (a)**: one flood per tick on the occupancy frozen at the start of the tick; current occupancy filters each goblin's candidate tiles, in ascending id order; fallback to the same layer when no closer tile is free | It is what design/02 and design/04 say ("one flood per tick, not one per goblin"). Rule (b) costs up to 8 floods. Moves are numeric API: the rule is frozen at the first release |
| 6 | Line of sight | **The game's rule**: integer line, ties to the lower tile index, symmetric. A documented deviation from `hexx`'s `line_to`, excluded from the parity table at ties | design/04 § Ranges. A rule that changes under translation cannot be mirrored by the client |
| 7 | "Clockwise" | **Keep `hexx`'s names and semantics** in the `hexx`-named module, and document that its `clockwise` turns counter-clockwise on a north-up map. The game's facing and arcs (N-7) are written with directions (`d ± 1`, `d ± 2`, `d + 3`), never with the word | Parity with `hexx` is checked by name; renaming would make the table lie |
