# ENG-06: the lifecycle's budgets, two registry reads, armor by level, which tile is a gate

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from ENG-06 ([#120](https://github.com/bal7hazar/grimworld/pull/120), report *Gas against ENG-01 §10*, *Records read*, *Escalations*) |
| To be answered by | `[Opus 5.5]` project manager (D-128): 1 and 2 are on the expedition's path (D-144), 3 and 4 are design |
| Needed by | ENG-06's merge (1); ENG-05 and ENG-07 (2, 4); the snapshot's armor (3) |

ENG-06 made the instance lifecycle: `enter`, `leave` (to a hub, or to the next location in the same
invocation), `travel_back`, `travel`, the closing report on `Hub`, `set_controller`, `instance_state`.
Figures are the local node's receipts, net of its higher fixed part (D), against ENG-01 §10.

## 1. Budgets on the expedition's path (D-144: the project manager's)

| Entrypoint, without a belt | Measured, net | §10 | Proposed target |
|---|---:|---:|---:|
| `enter`, a later entry | 4,073,259 | 3,728,526 (+9.2 %) | **4,100,000** |
| `leave` to a hub | 2,313,259 | 1,954,739 (+18.3 %) | **2,350,000** |
| `travel_back` | 2,108,139 | 1,954,739 (+7.8 %) | **2,350,000** (as `leave`) |
| `leave` to a location | 3,083,499 | 3,667,902 (−15.9 %) | §10 stands |
| `enter`, the first | 9,859,259 | 11,768,186 (−16.2 %) | §10 stands |

What §10 did not count: `leave` reads its gate, and `create` and `leave` to a location read the gate
then its destination (one call each, about 0.1 M, D-145's measure: **a call is about 98,000, a record
added to a call about 54,000**). The belt's worst case (four potion pages) cannot run on the node
before `set_build` exists; snforge's upper bounds add about +0.5 M to `enter` and +0.77 M to a
return. These entrypoints run once or twice an expedition: the overrun is about **0.7 M on S1,
under $0.001**.

**Recommendation:** accept the three measured targets; the belt's case re-measured on the node by
the task that brings `set_build`.

## 2. Two registry calls where a gate names its location (`create`, `leave` to a location)

The gate holds its destination's id, so the location cannot be asked in the same call: (a) accept
(about 0.1 M each); (b) the `GATE` record repeats its destination's seal and quota count (content
kept equal by the pipeline); (c) a registry read that follows a reference.

**Recommendation: (a).** ENG-05's reveal at `create` needs the whole location anyway.

## 3. Armor by level (design/03)

design/03 says armor "scales with level" without a formula; ENG-06's snapshot takes the class's
armor at every level. **Recommendation:** the class's armor, flat, until the balance simulator
(BAL-01) sets the curve; design/03 says so.

## 4. Which tile a gate is ("the gate is reachable", design/02)

ENG-06 reads it as **standing on the gate's anchor tile** ("walk into a hub gate", design/02 *Ending
an expedition*). The alternative is being adjacent to it. **Recommendation:** standing on it, one rule
for every gate, written in design/02; the client walks the adventurer onto the tile.

## Settled by the orchestrator (no decision asked)

- `set_account_owner` with 7 inside: 3,893,819 net (D), +5.2 % over D-144's 3,700,000: within the
  orchestrator's +10 % (D-144), accepted.
- Class sizes: `Instances` 35.2 %, `Hub` 35.4 % (the rule of ENG-01 §1.3 is 50 %). ENG-05 and ENG-07
  put the pure rules (the tick, the reveal) in library classes, as ENG-01 §1.3 decided; PLAN says so.
- A test of `Hub` with the real `Instances` needs a dev-dependency between the packages: allowed to
  ENG-07. ENG-01's §9.3, §10 and §1.3 figures are updated by the orchestrator after the merge.
- Later lots, as ENG-06 left them: task ids (E-14, GLD-02), the level-up rule, equipment drops and
  the facts other than a hub reached; the facing at entry (ENG-05).

## Decision

**D-148**, `[Opus 5.5]` project manager, 2026-09-29, under D-128: the four recommendations.

1. **Accepted**: `enter` (a later entry) **4,100,000**; `leave` to a hub and `travel_back`
   **2,350,000**; `leave` to a location and the first `enter` keep §10. The reads §10 did not
   count are the design's (a gate, then its destination); the overrun is about 0.7M on S1, under
   $0.001, and none of it is in a tick. The belt's worst case is measured on the node by the task
   that brings `set_build`; if it passes these targets, it comes back to the project manager.
2. **(a)**, two registry calls: (b) would duplicate content that the pipeline must keep equal, for
   0.1M on entrypoints that run once or twice an expedition.
3. **The class's armor, flat, at every level**, until BAL-01 sets the curve; design/03 says so.
4. **A gate is used by standing on its anchor tile**, one rule for every gate, written in design/02;
   the client walks the adventurer onto the tile.

The design lines of 3 and 4 go into design/03 and design/02 in ENG-06's pull request (OPERATIONS
§5). **What would reverse it**: 1, a batch or a tick found paying these reads; 3, the owner or
BAL-01 wanting armor to grow before the balance pass; 4, the owner preferring a gate used from an
adjacent tile (a change of design/02 and of the client's path, not of storage).
