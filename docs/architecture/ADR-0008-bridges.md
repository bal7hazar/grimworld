# ADR-0008 — Bridges on two levels

| | |
|---|---|
| Status | **Proposed** (ENG-08b, track game, 2026-10-07). Each rule below is a recommendation; **the project manager rules on them before any code** (PLAN's ENG-08b row) |
| Date | 2026-10-07 |
| Decides | The rules of a bridge in play and in the content pipeline: a position's level, movement and pathfinding across levels, sight, combat reach, traps and quotas, the window and the reveal, the converter's reachability (P-1) |
| Builds on | **D-217** (the owner: bridges on two levels, pass under or on), ENG-08's format (ENG-01 §3.5, #378: the `BRIDGE` record, D-214, D-215, D-221), D-225 (ENG-07 one level until this lands), D-127, D-134, D-136, D-144, D-174, D-200; design/04, design/18, design/19 §2.3, §5.11; CLI-09e §1 *Bridges* (the editor's one-hex deck) |
| Measured by | `spikes/SPK-18-bridges/` (Linux, two clean builds; its README) |
| Bounded | Bridges only, two levels, no general multi-storey map (D-217) |

## Context

ENG-08 reserved a bridge plane and left its rules here: a `BRIDGE` record (kind 27, one felt) holds a
deck (bit `15 row + column` of its chunk, 1 = a deck tile), end A (225–232) and end B (233–240); a
bridge lies in one chunk; a one-tile deck with its two ends is valid (R-33: a deck, two distinct ends
off it; R-34: each end walkable and next to a deck tile; R-35: its index below its chunk's count;
P-3: a deck connected). The **walkable plane** (`ZONE_CHUNK` part 0) says nothing of the deck: the
ground beneath a deck tile is walkable (a road passes under) or a wall (a river). Track CV's editor
places a whole bridge sprite as **one deck tile, the southern end South-West of it and the northern
end North-West of it** (CLI-09e §1). Until this lands, P-1 reads the walkable plane only (a map
whose only crossing is a bridge is refused) and ENG-07 builds one level (D-225).

Every rule reads the board as a plane today (ENG-01 §3.5, *The rules that read terrain today*). A
bridge adds a second level on its deck tiles only; everywhere else nothing changes.

## Decision (proposed)

### Rule 1 — The level of a position

- **Two levels**: `GROUND` (0), every tile's, and `DECK` (1), only on a deck tile. An actor on a deck
  tile is on one of the two: on the deck, or under it (where the ground beneath is walkable).
- **Where it matters, and where it is kept** (one bit beside the position, in the word that holds
  the position today: **no new slot**, and a move writes the word it already writes):

  | Who | Where (ENG-01 §3.2, free bits today) |
  |---|---|
  | A member | `MemberState` bit **176** (176–249 are free after `casts_2` 168–175) |
  | A goblin with a record | `GoblinState` bit **240** (240–249 are free after the recharges 128–239) |
  | A goblin's memory (design/18 *Alerted*: the last tile the adventurer was seen on) | `GoblinState` bit **241**: the remembered tile's level |
  | A goblin without a record (at its spawn, `Features`' pack placements) | none: a spawn is on the ground (rule 7), so its level is `GROUND` |
  | A tile target (a `TILE` skill, `MemberTimers` target 8–23 · "is a tile" 24–31) | none: a shape covers both levels (rule 6), and a trap lies on the ground (rule 7) |
  | An entity target (`MemberTimers`, `GoblinState.target`) | none: the entity carries its own level |

- A word never written holds level 0: an existing member or goblin is on the ground. Nothing to
  migrate.
- **Measured** (SPK-18, `pairs.txt`, one call): reading a position with its level costs **+3,430**
  (member 11,440 → 14,870; goblin 9,960 → 13,390); writing a move with its level **+1,300** (member
  1,400 → 2,700; goblin 1,300 → 2,600). New slots: 0.

### Rule 2 — Movement

A Move stays one tile in one of six directions, one tick (two Crippled), facing set to the direction
(design/04). With a deck in the window (`deck`: the window's deck tiles; `ends`: its bridges' ends;
`aloft`: the deck tiles taken):

| From | To | Result |
|---|---|---|
| An end, on the ground | a tile of its bridge's deck | **the climb**: onto the deck (`DECK`), if that tile is free aloft. Never under: from an end, the deck's tile is always the deck |
| A deck tile, on the deck | a tile of the same deck | along the deck, if free aloft |
| A deck tile, on the deck | an end of its bridge | **the descent**: onto the ground (`GROUND`), if the end is free |
| A deck tile, on the deck | anything else | **refused** (the railings): no jump, no fall (no displacement exists, design/19 §3.5) |
| A deck tile, on the ground (under) | an end of its bridge | **refused** (the cut): that edge is the climb's, so the graph stays undirected and a Move never needs to say which level it means |
| Any other ground tile | any tile | today's check: walkable on the ground plane and free on the ground. A deck tile with walkable ground beneath is **passed under** from its other neighbours |

- The deck is **entered and left only by its two end tiles** (D-217; the brief).
- The climb and the descent are ordinary Moves: one tick, Crippled's two, facing turned, the trap
  check after the move (rule 7: none aloft).
- **No deck in the window** (every generated chunk, a dungeon, most of an authored zone): today's
  one-level check, exactly (`test_no_deck_is_one_level`: equal on all 240 tiles × 6 directions).
- **Measured** (SPK-18): today's one-level check **19,396** a move (the base: ENG-07's check as D-225
  briefs it, prototyped in the spike; not on main). The two-level check **36,868** on every path
  (`bridged_none`, `_ground`, `_under`, `_climb`, `_descend` equal: a branch's merge is charged its
  dearest side), **+17,472** (×1.90). **With the branch on "a deck in the window" in the caller**
  (`either`): **21,456** with no deck (+2,060, ×1.11) and **36,568** with one. Recommendation: branch
  in the caller (once a move, or once a batch on the union of its windows); a batch of 10 moves pays
  at most +20,600 with no deck, +171,720 across a bridge.

### Rule 3 — Pathfinding (the goblins' flood)

- The shared flood (ADR-0006 §4, D-127: from the adventurer, 15 layers) runs on the **graph of
  rule 2**: nodes `(tile, GROUND)` for every walkable tile and `(tile, DECK)` for every deck tile,
  edges as the Moves above. Its source is the adventurer's tile **and level**; a goblin's step is its
  neighbour (by rule 2) in the least layer, ties as today. With no deck in the window the flood is
  today's, unchanged.
- Goblins use bridges (they climb, cross and descend) as members do. A goblin on the deck that
  cannot reach a member below waits for the flood to lead it down an end.
- **How** (proposed for the implementing lot): a layer is two bitmaps, the ground's and the deck's.
  Per layer, with `F` the ground frontier, `Fd` the deck frontier, `E` the ends, `D` the deck tiles,
  `N(·)` hexx's dilation: ground `N(F \ (E ∪ D)) ∪ (N(F ∩ E) \ D) ∪ (N(F ∩ D) \ E) ∪ (N(Fd) ∩ E)`
  on the open free tiles; deck `(N(F ∩ E) ∪ N(Fd)) ∩ D` on the free deck tiles. R-37 (rule 8) makes
  these masks exact.
- **Cost: E, not measured.** SPK-7's layer is 26,452 and the capped worst flood 634,655 (ADR-0006,
  *Measured*); with a deck in the window a layer holds up to five dilations instead of one, so
  **≤ 3.2 M at the cap (E, ×5)**, only on windows that hold a deck. The implementing lot measures it
  (D-144); Open question 3 gives the cheaper fallback.

### Rule 4 — Occupancy

- Two actors may share a deck tile on different levels (one under, one on). The window's occupancy
  (ENG-01 §3.2: not stored, built from the members and goblins in the window) gains `aloft`, the deck
  tiles taken on the deck, set from the actors whose level is `DECK`; the ground occupancy is built
  from the others. Two bitmaps instead of one, only when a deck is in the window.
- design/04's invariant ("a goblin's own tile is marked occupied") holds per level.

### Rule 5 — Sight (recommendation: the deck blocks nothing but itself)

- **Lines of sight** (design/04, `WindowTrait::sight`, D-174) are drawn on the plane, as today, on
  the **combat window `open | deck`**: a deck tile is open for sight on both levels, whatever lies
  beneath it. A deck hides nothing behind it, from above or below; actors never block (unchanged).
- **The deck blocks itself**: the two actors of one deck tile (one on it, one under it) do not see
  each other. That is the only pair of tiles a level separates.
- **Seeing and the reveal** (design/18: a hexagon of radius 6, no line of sight) read the
  adventurer's tile only: unchanged by its level.
- **Consequence**: a deck tile over a river is open for sight, so a line across the river through
  the deck is clear, though the river elsewhere still hides what lies beyond it (D-221's v1 limit).
  This follows from "the deck blocks nothing"; Open question 2 asks whether to keep it.
- `WindowTrait` is frozen (ENG-02): nothing changes in it. The caller builds the `Window` it passes
  to `sight`, `reach` and `shape` from `open | deck` instead of `open`; the movement check keeps its
  own board (rule 2). Cost: one addition a tick when a deck is in the window (E, of the order of a
  felt addition).

### Rule 6 — Combat reach between levels

- **No melee between the deck and below** (recommendation): an action of range `TOUCH` (1) between an
  actor on the deck and one on the ground is illegal (a member: the batch stops, design/02; a goblin:
  its AI does not choose it), whether the two are adjacent or stacked on one tile. Adjacent on the
  same level: today's rules.
- **Ranged by the usual rules**: range 6 on the plane's hex distance (`WindowTrait::distance`), a line
  of sight on the combat window (rule 5), in either direction between the levels, except the stacked
  pair (no sight). Arcs and facing read the plane (`arc`, `front`, `facing`): unchanged.
- **Shapes** (recommendation; Open question 1): a shape (`SINGLE`, `RING_1`, `DISC_1` … `DISC_3`,
  design/19 §2.3) covers its tiles on **both levels** (a bomb on a deck tile also strikes the one
  under it), **except a shape of a `TOUCH` skill, which strikes its source's level only** (a cleave
  on the deck does not reach below, as its single hit would not). `WindowTrait::shape` is unchanged
  (on the combat window); the executor's actor list (§5.14 step 4, tile order) takes both levels'
  actors of a tile, ground first, then deck, filtered by the `TOUCH` rule.
- A tile target needs no level (rule 1).

### Rule 7 — Traps, objects, spawns and quotas on the ground only

- **Traps** (design/19 §5.11) lie on the ground. A placed trap's tile is a walkable ground tile, as
  today (aimed at a deck tile, it lands on the ground beneath it if walkable, else the skill is
  illegal as for any tile that cannot take one). A trap **triggers only on an entry at `GROUND`**:
  crossing above it on the deck triggers nothing.
- **Content stays on the ground**: spawn points, objects (chests, nodes, terrain traps, landmarks,
  levers), quota candidate tiles, gate anchors and the entry are on walkable ground tiles (R-14,
  R-18, R-26 read the walkable plane already). A deck tile with a walkable ground beneath may hold
  them **under** the deck.
- **R-36 (new, proposed)**: no spawn point, object, candidate tile, gate anchor or entry on a
  bridge's end, so content never closes a bridge (an object holds its tile, design/19 §5.11). Checked
  by `ZoneAssert` at the `BRIDGE` write against its `ZONE_CHUNK`, and at a `ZONE_CHUNK` write against
  its `BRIDGE`s (the reverse check); code `bridge: end taken`.
- **Quotas** (ENG-05, D-208, D-220, ENG-09's authored draws) place on ground tiles only: their hosts,
  the placement's allowed tiles (`Placement`) and the authored candidate tiles read the walkable
  plane, which holds no deck. **Nothing changes**; R-36 keeps a candidate tile off an end.
- Remains (a dead goblin's record) lie where it fell, at its level (its `GoblinState` keeps it).
  Looting reaches them by the `TOUCH` rule (rule 6).

### Rule 8 — The converter's reachability (P-1) and the layout

- **P-1 with bridges**: every walkable tile on the ground **and every deck tile aloft** is reachable
  from the entry over the graph of rule 2. A map whose only crossing is a bridge is then accepted.
  With no bridge, P-1 is SPK-16's unchanged. Prototype: `spikes/SPK-18-bridges/reach.py` (8 tests: a
  river crossed only by a bridge refused without it and accepted with it, the editor's bridge over a
  road and over a river, the cut leaving a pocket unreachable, the three R-37 refusals).
- **R-37 (new, proposed; the converter's `export:` codes, and `ZoneAssert` across one chunk's
  bridges)**: two bridges' decks neither share nor touch a tile; an end is on no deck and touches no
  other bridge's deck. Then a deck tile next to an end is that end's bridge's, so the window needs
  only the masks `deck` and `ends` (no bridge index a tile). Codes `export: decks touch`, `export:
  end by another deck`, `export: bridge end on a deck`. Format 1 keeps a bridge in one chunk; a
  bridge's tiles at a chunk's edge and another's across the seam are checked by the converter, which
  sees both.
- P-3 (a deck connected) is kept; P-2 is unchanged (the deck is not in the walkable plane).
- **The format needs no new plane** (the reversal condition of ENG-08's decision record does not
  fire): the deck's level is implied by the `BRIDGE` record.

### Rule 9 — The window and the reveal

- **The window** (ADR-0006 §4: 15 × 16, assembled each tick, never stored) gains, only when one of
  its chunks holds a bridge, the bitmaps `deck` and `ends` (assembled from the chunks' `BRIDGE`
  records as the walls are, each tile at its window position) and `aloft` (rule 4). **The ring is
  wall on both levels**: the assembly clears `deck` and `ends` on it as it does `open`. A bridge cut
  by the window's edge is fine: the checks are local (one step); an end outside the window is not
  followed by the flood (the ring is wall).
- **Which chunks hold bridges**: generated chunks and dungeons never do. The authored reveal (ENG-09)
  copies the chunk's bridge count (`ZONE_CHUNK` part 1 bits 208–211) into the instance's `Terrain`
  word, **bits 229–232 (proposed; 229–249 are free after the edges 225–228)**, so that `play` reads
  the `BRIDGE` records (`location × 4096 + chunk × 16 + k`) of the batch's chunks with a count, once
  a batch (D-145; `bundle`, about 36,000 a slot, ENG-01 §3.5: **E**, one slot a bridge). A batch
  with no such chunk reads nothing and runs the one-level path.
- **The reveal** (sight touching a chunk, radius 6 on the plane): unchanged. Rule 5's seeing reads
  the adventurer's tile only. A dungeon's outline (ENG-10a/b) has no bridge.
- **`instance_state` and `instance_region`** (ENG-01 §4.1): a member's and a goblin's level are in
  their words already (rule 1); a region's chunk gains its bridge count in `Terrain`. The indexer's
  frozen events (ENG-01 §5, D-193) do not change: no event carries a level (a position event that
  needs one is an announcement in STATUS first).

### What each rule reads today, and what changes

| Rule (ENG-01 §3.5's terrain readers, and the others a level touches) | Reads today | With bridges |
|---|---|---|
| Movement (ENG-07, D-225) | the walkable plane, the occupancy | rule 2: the plane, `deck`, `ends`, both occupancies; the actor's level; one level's check when no deck is in the window |
| The flood (D-127, 15 layers, `hexx`'s `Bfs`) | the walkable plane, frozen occupancy | rule 3: the two-level graph; today's when no deck |
| Line of sight (`WindowTrait::sight`, D-174) | the window's `open` | rule 5: the window built from `open \| deck`; the stacked pair refused by the caller |
| `reach`, `shape` (design/19 §2.3, §5.5) | `open` | rule 5's window; rule 6: `TOUCH` across levels refused, a `TOUCH` shape on its source's level |
| `arc`, `front`, `facing`, `distance` | positions | unchanged (the plane) |
| Perception (design/18: *On watch* needs a line of sight; *Alerted* remembers a tile) | positions, `sight` | rule 5's sight; the memory's level (rule 1, bit 241) |
| Placement (packs, objects), quotas' hosts, traps' tiles (design/18, design/19 §5.11, `Placement`) | the allowed ground tiles | unchanged; R-36 keeps ends free; a trap triggers on a `GROUND` entry only (rule 7) |
| Sight and the window's assembly (ADR-0006 §4, D-120, D-134) | the chunks' walls | rule 9: `deck`, `ends` from `BRIDGE` records, the ring cleared on both |
| The reveal (ENG-05, ENG-09, ENG-10b) | the adventurer's tile, radius 6 | unchanged; ENG-09 copies the bridge count into `Terrain` 229–232 |
| The generation (dungeons, a zone not authored) | its own board | unchanged: no bridge |
| The converter (P-1, P-3; SPK-16) | the walkable plane | rule 8: the two-level graph, R-36, R-37 |
| The registry's checks (R-33, R-34, R-35) | `BRIDGE`, `ZONE_CHUNK` | unchanged, plus R-36 and R-37 |
| The executor's actor list (§5.14 step 4) | tiles in ascending order | both levels of a tile, ground then deck |

### The cost, together

| Figure | Value | M/E | Source |
|---|---:|---|---|
| A position's level: new slots | 0 | M (layout) | rule 1 |
| Read a position with its level, extra | +3,430 a read | M | SPK-18 `member_place_level` − `member_place`, `goblin_…` |
| Write a move with its level, extra | +1,300 a move | M | SPK-18 `…_moved_level` − `…_moved` |
| The movement check, one level (base) | 19,396 | M (spike's prototype) | SPK-18 `ground_step` |
| The movement check, two levels, any path | 36,868 (+17,472) | M | SPK-18 `bridged_*` |
| The same, branched in the caller: no deck / a deck | 21,456 (+2,060) / 36,568 | M | SPK-18 `either_none`, `either_climb` |
| The flood with a deck in the window | ≤ 3.2 M at the cap (≤ 5 dilations a layer) | **E** | rule 3, SPK-7's 26,452 a layer |
| The combat window `open \| deck` | one addition a tick | **E** | rule 5 |
| `BRIDGE` records read in a batch | ≈ 36,000 a bridge | **E** | ENG-01 §3.5 `bundle` |

Every rise on the expedition's path goes to the project manager (D-144) from the implementing lot's
own measures; the figures above are the spike's.

### The client mirror and the vectors (for the implementing lot)

`client/sim/**` is lent to track CV: what follows is a paired CV PR, asked through the orchestrator;
the vector tables are the game's.

1. **`contracts/logic/vectors/bridge.jsonl`** (new, JSON lines, `check.py` extended; small, well under
   FND-23's limits: a few hundred rows):
   - movement: `(board, from, level, facing) → (to, level) | refused` on the spike's boards (the
     editor's bridge over a road and over a river, a two-tile deck, no deck), every path of rule 2
     (climb, along, descent, under, cut, railings, aloft taken, end taken, ground taken, ring);
   - the level in the words: member and goblin words with the level set and cleared (bits 176,
     240, 241), read and written;
   - sight, reach and shapes between levels (rule 5, 6): the stacked pair, adjacent melee across
     levels refused, ranged allowed through a deck over a river, a `DISC_1` on a deck tile with an
     actor under it, a `TOUCH` shape on the deck;
   - the flood with a deck in the window (rule 3), once the flood exists in the logic package
     (ENG-07).
2. **`client/sim`**: `window.ts` unchanged (it mirrors the frozen `WindowTrait`); a new `bridge.ts`:
   the two-level movement check, the combat window `open | deck`, the `TOUCH` rule across levels;
   the level's bits in the member and goblin decoders (`packing.ts`'s users); the two-level flood
   when the flood is mirrored; parity tests against `bridge.jsonl`.
3. **`client/app`** (track CV, not the mirror): an actor on the deck drawn above the bridge sprite,
   an actor under it drawn beneath; the editor (CLI-09) runs P-1 with bridges and R-36/R-37 with the
   converter's codes (`checks.json` gains their cases).
4. **The converter** (`tools/map-format/`, ENG-09, from SPK-16's): `reach.py`'s P-1 and R-37 into
   `pipeline`, R-36 into the checks table both sides run.

### What the bookkeeping changes (not edited by this lot: ENG-10b holds ENG-01, ADR-0006 and PLAN)

- **ENG-01 §3.2**: `MemberState` level 176; `GoblinState` level 240, memory level 241; `Terrain`
  bridge count 229–232 (authored chunks).
- **ENG-01 §3.5**: the `BRIDGE` row's "the reveal does not read it in version 1: its rules are
  ENG-08b's" → this ADR; the terrain readers' table → the table above; R-36 and R-37 added to the
  checks table; P-1's sentence ("a map whose only crossing is a bridge is refused until ENG-08b") →
  P-1 over two levels.
- **ENG-01 §9.2 / §10**: the move's two-level figures (rule 2) beside ENG-07's.
- **ADR-0006 §4** (the window): the bridge bitmaps and the two-level flood, a pointer here; CM-7's
  "Open in it: a bridge's rules (ENG-08b)" → answered by this ADR.
- **design/04** (*Actions*, *Ranges*): the climb and the descent are Moves; no melee between levels.
  **design/18**: the deck does not block sight. **design/19** §2.3, §5.11, §5.14: shapes across
  levels, traps on the ground only, the actor list's order on a deck tile.
- **PLAN**: ENG-08b done; the implementing lot's row (Open question 4); ENG-07's row "Movement across
  bridges takes ENG-08b's rules" → the lot that builds them; ENG-09's row: R-36, R-37, P-1 with
  bridges, the bridge count copied at the reveal.

## Open questions (each with its decider and a recommendation)

| # | Question | Decider | Recommendation |
|---|---|---|---|
| 1 | Shapes across levels: both levels on a shape's tiles, except a `TOUCH` skill's shape (its source's level)? | project manager (a combat rule; CBT track's design/19) | Yes, as rule 6. Reversed if a playtest finds bombs through decks wrong (then a shape strikes its centre's level only, and a tile target needs a level bit) |
| 2 | A deck over a river opens a line of sight across the river at the deck's tile (rule 5's consequence), against D-221's "a lake hides what lies beyond it" | project manager (D-221 is theirs) | Keep: the deck is a visible structure; it changes sight on the deck's tiles only. Reversed: the combat window takes `deck` only where the ground beneath is walkable |
| 3 | Goblins use bridges (rule 3) at an estimated ≤ 3.2 M a capped flood on windows with a deck, or never climb in v1 (decks out of their graph: a goblin stops at an end, members on a deck are reached only by ranged goblins) | project manager (D-144, R-2) | Use bridges; the implementing lot measures the flood first and stops for the project manager if the capped flood with a deck passes 1.5 M (≈ 2.4 × today's capped worst) |
| 4 | Which lot builds the rules in play: ENG-07 is one level (D-225) | project manager (the order of lots) | A lot **ENG-07b, bridges in play**, after ENG-07 and ENG-09 (it needs the authored reveal's bridge count and ENG-07's window and flood): rules 1–7 and 9 in the contracts, the vectors and the paired CV PR. ENG-09 takes rule 8 (P-1, R-36, R-37 in the converter and `ZoneAssert`) and the `Terrain` count. ENG-07 meanwhile builds its check as a function of a board (as SPK-18's `Ground`), so ENG-07b swaps it for the two-level one and branches in the caller |
| 5 | R-36 (nothing on an end) and R-37 (decks apart): accepted as content rules? | orchestrator (the track's own rule) | Yes: both are cheap, keep the window's masks exact and a bridge never closed |
| 6 | An actor on the deck and a goblin's return to its spawn (`GoblinState`'s AI state *returning*, ENG-01 §3.2): the spawn is on the ground; the flood leads it down | orchestrator | Nothing to add: the return walks the same graph |

## What would reverse it

The owner's word on D-217; a playtest that asks for melee between levels (then rule 6's `TOUCH` rule
goes, and the stacked pair needs a rule); the implementing lot's measures beyond what the project
manager accepts under D-144 (then Open question 3's fallback); a bridge art longer than one tile
(CLI-09e: a middle piece) changes nothing here (the rules hold for any connected deck).

## Sources

ENG-01 §3.2, §3.5, §4.1, §9.2; ADR-0006 §4; design/02, 04, 18, 19; docs/briefs/ENG-07-movement-and-window.md
(Q7, D-225); docs/briefs/ENG-08-authored-zones-format.md (A3, D-217); docs/decisions/2026-10-07-authored-zones-format.md;
docs/reports/CLI-09e-palette.md §1, §2.4; `spikes/SPK-16-authored-zone/map-format/` (`convert.py`'s
`pipeline`, `records.py`'s `assert_bridge`); `spikes/SPK-18-bridges/`.
