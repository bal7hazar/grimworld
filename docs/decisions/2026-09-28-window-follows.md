# Sight and the simulation window (ADR-0006 §4) — decided 2026-09-28 (D-120)

| | |
|---|---|
| Prepared by | `[Fable 5.1]` project manager, 2026-09-28; found by LIB-02 |
| Decides | The owner: it changes a rule of an accepted ADR |
| Needed by | SPK-7 (what it measures), then ENG-07. Not blocking today |

| | |
|---|---|
| The conflict | ADR-0006 says sight of radius 6 "fits in the window", which is true of a **centred** window (7 tiles to the ring). It also says the window moves only when the adventurer comes within 3 tiles of its edge. An adventurer 3 tiles from the edge sees, and can shoot, 3 tiles **beyond** the window, where goblins are frozen and the board is not assembled |
| **Recommended** | **The window follows the adventurer**: it re-centres as soon as the adventurer is more than 1 tile off its centre (1 row of slack keeps the origin on an even row). Sight and ranged lines then always lie inside the window. Cost: about one assembly per move, estimated at 40k plus 4 to 8 reads, **to be measured by SPK-7** before it is frozen |
| Alternative | Keep the hysteresis of 3 and cut sight and ranged lines at the window's ring: what is shown and what can be targeted then depends on where the window happens to be, which a player cannot see |
| Fallback if the cost is too high | The 11 × 11 window with sight 5 of ADR-0006, with the same follow rule |

## Answer

Given by the owner on 2026-09-28.

| # | Decision (D-120) |
|---|---|
| 1 | **The window follows the adventurer.** The margin of 3 tiles is dropped. Cutting sight at the ring is rejected: what the player sees must never depend on a state the player does not know |
| 2 | **Window of 15 columns × 16 rows** (240 tiles, under the library's 251): exact horizontal centring; the sixteenth row absorbs the vertical offset that the parity of the origin imposes. Sight of radius 6 is always inside the ring. Chunks stay 15 × 15 |
| 3 | **The window is not stored**: recomputed at each tick from the chunks; reads instead of a write |
| 4 | Fallback if the cost is too high: the same rule with a smaller sight |
| 5 | Assembly follows `docs/CAIRO.md`: no loop over rows; per chunk overlapped, a mask from a table of constants, then a shift by multiplication or division by a power of two |
| 6 | SPK-7 measures the worst case (4 chunks, two layers each, 8 awake goblins) and compares with and without a stored window. The figure of 40k is an estimate |

## Verification asked by the owner

By the library's orchestrator, in the library's code, read-only:
`bal7hazar/hexx-cairo`, `docs/research/window-parity-check.md`.

| Question | Result |
|---|---|
| Does the one-tile tolerance come from the parity of the origin? | **Confirmed.** Every neighbour is derived from the parity of the local row; no function takes an odd origin; the window moves vertically by two rows |
| Does sight reach the ring on 15 × 15? | **Confirmed**, for every even global row of the adventurer: 7 tiles of the ring are in sight; a goblin there is shown and not simulated |
| 15 × 16, or the parity handled in the assembly (an odd origin)? | **15 × 16.** Same cost per flood layer; a board the library already accepts, finders unchanged, results identical to 1.8.0. An odd origin would add a second parity, and a second set of results, to every algorithm of the tick |

## Decided by the project manager, and why

| | |
|---|---|
| **Fallback: sight 5 on 13 × 14**, not "11 × 12 with sight 5" | By the owner's own rule a sight of radius `r` needs `2r + 3` columns and `2r + 4` rows; 11 × 12 holds a sight of 4. The same error was in the first ADR ("11 × 11 with sight 5"). Sight is the rule the player meets, the window follows from it: sight 5 is kept and the window is sized for it. Confirmed by the library's check |
| The parity flag stays for generation and seams | Chunks are 15 rows high, so half of them start on an odd row. The flag does not reach the tick |
