# Gate L-G1 of track LIB — decided 2026-09-28

| | |
|---|---|
| Prepared by | `[Fable 5.1]` project manager, 2026-09-28 |
| Decides | The owner |
| Source | `bal7hazar/hexx-cairo`: `docs/decisions/L-G1-hexx-port.md`, `docs/research/LIB-02-hexx-analysis.md` (`[Opus 5.5]`, audited twice by `[GPT-6-Sol]`, findings fixed) |
| Blocks | LIB-03, and through it L-M1, the pre-release SPK-7 waits for, and ENG-05 |
| Does not block | Phase 0 of the game: FND-03, SPK-5, ART-00, FND-01/02/06, SPK-2, SPK-4, SPK-8. SPK-7 can start on `origami_hexmap` 1.8.0 (R-18) |

## 1. Is a port of `hexx` relevant?

| Option | |
|---|---|
| **Partly** (recommended by the orchestrator and by the project manager) | The integer geometry of `hexx` is carried with its names and a parity table: directions and rotation, line, range and ring as geometry, distance, neighbours. Everything else of L-M1 is an extension of the board engine, documented as such |
| Fully | Every integer function of `hexx`. Nothing in the game asks for the rest; it can be a later milestone |
| No | No `hexx` names, no parity table |

Why: most of `hexx` 0.25.0 is floating point, meshes and engine integration; it has none of
the five board-level needs (N-1, N-2, N-3, N-4, N-8). `origami_hexmap` has the primitives of
every need and the finished function of none except distance and neighbours.

## 2. Where does the work land?

| Option | The game depends on | |
|---|---|---|
| **B. `origami_hexmap` extended in place** (recommended) | `origami_hexmap` only | The needs reuse internals private to that crate (automaton, stored flood layers, masks, tables). One engine, one `GAS.md`. Existing users unaffected: additions only. Matches ADR-0006: "generation with margins is added to the map library by its author" |
| A. `hexx-cairo` alone | Both libraries | Five needs of eight would be "extensions" of a mirror that does not have them, and would need the internals of the other crate made public |
| C. Both | Both, maybe one later | The most maintenance, a dependency across organisations |
| D. No library work | `origami_hexmap` 1.8.0 | The hardest algorithms written in the game, outside the library that owns their internals |

Conditions attached to B: the `hexx`-named subset lives in its own module, so that `range`,
`ring` and `distance_to` keep the meaning of `hexx` there; `bal7hazar/hexx-cairo` stays the
home of the track (plan, research, decisions, the off-chain harness generating the parity
vectors).

**The one risk of B is the owner's to weigh**: every pre-release of L-M1 is a release of the
`origami` workspace, in the `dojoengine` organisation. If that cadence cannot follow the game
(pre-releases for SPK-7, then ENG-05), A or C gives a cadence of our own at the price above.

## 3. Sight and the window (ADR-0006 §4), found by LIB-02

| | |
|---|---|
| The conflict | ADR-0006 says sight of radius 6 "fits in the window", which is true of a **centred** window (7 tiles to the ring). It also says the window moves only when the adventurer comes within 3 tiles of its edge. An adventurer 3 tiles from the edge sees, and can shoot, 3 tiles **beyond** the window, where goblins are frozen and the board is not assembled |
| **Recommended** | **The window follows the adventurer**: it re-centres as soon as the adventurer is more than 1 tile off its centre (1 row of slack is needed to keep the origin on an even row). Sight and ranged lines then always lie inside the window. Cost: one assembly per move or so, estimated at about 40k plus 4 to 8 reads, **to be measured by SPK-7** before it is frozen |
| Alternative | Keep the hysteresis of 3 and cut sight and ranged lines at the window's ring: what is shown and what can be targeted then depends on where the window happens to be, which a player cannot see |
| Fallback if the cost is too high | The 11 × 11 window with sight 5 of ADR-0006, with the same follow rule |

## 4. Already decided, recorded here

| | |
|---|---|
| `u252` | Its own crate `u252`, repository `bal7hazar/types-cairo`, published on scarbs.xyz, extracted by a separate session (owner, 2026-09-28, in the library orchestrator's session). `docs/CAIRO.md` §4 of the game is updated when the crate is published |
| Points 1, 2, 3, 5, 6, 7 of LIB-02 | Answered by the project manager in [docs/needs/hexmap.md](../needs/hexmap.md) |

## Answer

Given by the owner on 2026-09-28, in the library orchestrator's session; recorded in
`bal7hazar/hexx-cairo`, `docs/decisions/L-G1-hexx-port.md`. **It differs from the
recommendations of §1 and §2 above**, which are kept as they were put.

| # | Decision (D-119) |
|---|---|
| 1 | **Port `hexx` in full**: feature parity wherever it makes sense on-chain. The scope is extended with what Cairo and the network require (boards in one felt, generation, floods, assembly) |
| 2 | The library lives in **`bal7hazar/hexx-cairo`**, published under its own name and cadence. The bitmap engine of `origami_hexmap` 1.8.0 is taken over there; results for the same input stay identical, so that the game migrates without moving its test vectors |
| 2b | **`origami_hexmap` is decommissioned** once the port is complete and the game has migrated. Until then the game consumes `origami_hexmap` 1.8.0 *(found impossible the same day: [N-9](2026-09-28-N-9-compiler-target.md))* |
| §3 | Sight and the window: decided the same day, [window-follows](2026-09-28-window-follows.md) (D-120) |

Consequences for the game: milestone L-M1 is unchanged (N-1 to N-8 first); the game's
dependency moves to `hexx-cairo` at a published version, in its own task; `docs/CAIRO.md` §4
follows when `u252` and `hexx-cairo` are published. The risk named in §2 (release cadence in
another organisation) no longer exists.
