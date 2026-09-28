# PENDING — Sight and the simulation window (ADR-0006 §4)

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

Until the owner answers, SPK-7 measures **both** rules (follow, hysteresis of 3), so that
the answer costs no time.

## Answer

*To be filled with the owner's decision and its date.*
