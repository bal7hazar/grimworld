# Gate L-G2 of track LIB: the porting plan of `hexx` — accepted 2026-09-28

| | |
|---|---|
| Prepared by | `[Fable 5.1]` project manager, 2026-09-28 |
| Decides | The owner |
| Source | `bal7hazar/hexx-cairo`, `main`: `docs/decisions/PENDING-L-G2.md`, `docs/research/LIB-03-porting-plan.md` (`[Fable 5.1]`; five audit passes by `[GPT-6-Astra]`, four fix loops, merged with four findings open, none blocking LIB-04 or LIB-05 by the auditor's statement) |
| Blocks | LIB-04 and LIB-05, and through them ENG-02 and ENG-05 of the game |
| Does not block | Phase 0 of the game; SPK-7 runs on `origami_hexmap` 1.8.0 |

## 1. What the owner must know first

| | |
|---|---|
| The tick | Estimated at **1.34M to 1.67M gas** in the plan's worst case (window assembled from 4 chunks, one flood of 25 layers, 8 goblins choosing their step). **Nothing is measured.** The first draft said 740k; the figure doubled under audit |
| Not in that figure | Storage reads and writes, the game's own rules, line of sight |
| Against what | ADR-0001 asks an expedition of 300 actions for $0.50 or less. SPK-2's native figures are provisional ($0.72 to $2.08 before its cost audit is answered): the threshold is **not shown to hold today** |
| What follows | The tick is the first thing to measure, in the library and in SPK-7, before any budget is written |

## 2. The gate: is the plan accepted?

| Option | |
|---|---|
| **A, with two conditions** (recommended by the orchestrator and by the project manager) | Accept scope, contracts, milestones. (1) LIB-05 starts with what decides the tick, the assembly (N-3) and the flood with its selection (N-8), proved against their oracles and measured on their worst cases; above the upper bound, stop and report. (2) Nothing is published without the owner's go |
| B | Accept scope and milestones, and ask for a measuring spike before L-M1 |
| C | Amend: say what changes |

What is accepted at this gate is the **contracts, the scope and the order**; the plan's
algorithms are sketches that LIB-05 may replace, and none of its figures is a budget.

## 3. Decisions of the plan the owner may reverse

| # | The plan says | Alternative | Project manager |
|---|---|---|---|
| D-1 | The package is named **`hexx`** | `hexx_cairo`, or `quiver_hexx` | **`hexx`.** A name cannot change after the first release, and D-125 makes `quiver` the future home of the `*-cairo` libraries: decide now. Proposed rule: a mirror of a Rust crate keeps the crate's name, as the owner's `glam` and `nalgebra` do; packages of our own take the prefix (`quiver_quest`) |
| R-4 | Reserve the name by publishing an empty `0.0.1` | Publish nothing before 0.1.0 | **Reserve**, on the owner's go: a publication cannot be undone |
| D-4 | Boards stay `felt252` in the API of L-M1 | Boards typed `u252` (package `uint252`) from 0.1.0 | **The plan**: identical results and API with 1.8.0 make the game's migration a change of dependency. A typed API can come at 0.2.0, before 1.0.0 freezes it |
| D-5 | L-M1 carries the game's needs and the part of the mirror they rest on | Extensions only, or the whole foundation of the mirror | **The plan** |
| D-3 | Two direction types, `EdgeDirection` (mirror) and `Direction` (board), same indices | One type | **The plan** |
| D-6 | `Hex::line_to` carries the game's tie rule, a documented deviation | A separate function, `line_to` not ported | **The plan** |
| D-17 | At the end `origami_hexmap` is removed from `origami` `main`, kept on the registry and in a tag | Kept on `main`, deprecated | **The owner's**: it is `dojoengine`'s repository |

## 4. One rule of the game, for the owner

**Does the tick cut the flood short, and what does a goblin beyond do?** (plan Q-5, D-25)

| | |
|---|---|
| Why it is asked | The flood that gives every goblin its next step has no small bound: on a winding board a goblin 7 tiles away as the crow flies can be 45 steps away on foot. One layer costs about 19.3k. CONTEXT §8 asks that every loop have a bound stated in the design |
| **Recommended** | **The flood stops at 15 layers. A goblin it did not reach holds its position**: it does not move this tick; it still acts if it can (a ranged attack with line of sight, a skill). Flood at most 345k instead of 538k on the cave and 924k on the winding board |
| Why 15 | The adventurer is at the centre of the window: on open ground no tile of the window is further than about 10 steps. 15 allows a detour of 5 around an obstacle |
| What the player meets | A goblin with no way to the adventurer within 15 steps stays where it is. Terrain is defence (design/04); a goblin that would need 40 steps to arrive is not a threat this turn either way |
| Alternatives | No limit (cost up to 924k on the fixtures); a goblin beyond the limit walks by straight distance (it gets stuck against walls, and needs a second rule) |
| Frozen | At the first release of the library and in the client's simulation: moves are numeric results |
| Tuned | The number, by SPK-7 and the first playtest, before 0.1.0 |

## 5. Answered by the project manager

In [docs/needs/hexmap.md](../needs/hexmap.md), "Answers to the questions of LIB-03".

## Answer

Given by the owner on 2026-09-28: **the project manager's recommendations are accepted**.

| # | Decision |
|---|---|
| D-126 | **The plan is accepted** (option A) with its two conditions: LIB-05 starts with the assembly (N-3) and the flood with its selection (N-8), proved against their oracles and measured on their worst cases, and stops above the upper bound; nothing is published without the owner's go |
| D-126 | The package is named **`hexx`**. Rule: a mirror of a Rust crate keeps the crate's name; packages of our own take the prefix of their repository (`quiver_quest`) |
| D-126 | Boards stay `felt252` in the API of L-M1 (D-4); L-M1 carries the needs and the part of the mirror they rest on (D-5); two direction types (D-3); `line_to` carries the game's tie rule (D-6) |
| D-127 | **The flood of the tick stops at 15 layers; a goblin it did not reach holds its position** and still acts if it can. The number is tuned by SPK-7 and the first playtest, before 0.1.0 |

Still with the owner, not blocking:

| | |
|---|---|
| Reserving the name by publishing an empty `hexx` 0.0.1 (R-4) | **Declined by the owner on 2026-09-28**: not worth it. The first publication of `hexx` is 0.1.0, on the owner's go |
| What becomes of `origami_hexmap` on `origami` `main` at the end (D-17) | At milestone L-M4 |
