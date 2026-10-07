# ADR-0008 — Bridges: one level, walkable ground over water

| | |
|---|---|
| Status | **D-227 (the owner, 2026-10-07) replaces D-217's two levels.** Bridges have **one level**: nobody passes under a bridge, what lies under it is water. The rules below are ENG-08b's, proposed for the project manager's ruling. **D-226 is void** but for its content rules (R-37, R-38: one kept, one dropped, rule 5) |
| Date | 2026-10-07 |
| Decides | What a bridge is in play and in the content pipeline: its deck as walkable ground, what each rule that reads terrain does with it, the converter's reachability (P-1), the content checks |
| Builds on | **D-227** (the owner), ENG-08's format (ENG-01 §3.5, #378: the `BRIDGE` record, D-214, D-215, D-221), D-225 (ENG-07: one level, the walkable plane), D-144; design/04, design/18, design/19 §5.11; CLI-09e §1 *Bridges* (the editor's one-hex deck) |
| History | The two-level proposal (D-217) was reviewed at `38cfd13` (t-0095, PASS WITH FINDINGS) and ruled by D-226; D-227 voids it. Its spike, `spikes/SPK-18-bridges/`, keeps its measured figures as history (*History* below) |

## Context

ENG-08 reserved a bridge plane: a `BRIDGE` record (kind 27, one felt) holds a deck (bit `15 row +
column` of its chunk, 1 = a deck tile), end A (225–232) and end B (233–240); a bridge lies in one
chunk (R-36, `export: bridge across chunks`); a one-tile deck with its two ends is valid (R-33: a
deck, two distinct ends off it; R-34: each end walkable and next to a deck tile; R-35: its index
below its chunk's count; P-3: a deck connected). Track CV's editor places a whole bridge sprite as
one deck tile, the southern end South-West of it and the northern end North-West of it (CLI-09e §1).
The SPK-16 converter builds the walkable plane from the painted map (`convert.py`: `walk`, then each
chunk's `walls`) **before** it reads the bridges: a deck painted as water is a wall today, so P-1
refuses a map whose only crossing is a bridge.

Every rule of play reads terrain as one plane, one bit a tile (ENG-01 §3.5, *The rules that read
terrain today*). With one level a bridge fits that plane as it is.

## Decision (proposed)

### Rule 1 — A deck is walkable ground drawn over water

- **The converter writes every deck tile walkable** in its chunk's walkable plane (`ZONE_CHUNK`
  part 0, 0 = floor), whatever the map paints beneath it (water). The ends are walkable already
  (R-34). The `BRIDGE` record stays what the client draws (the sprite, its deck and ends); **no rule
  of play reads it**.
- **R-34 extended** (ENG-09, `ZoneAssert`): every deck tile is walkable in its chunk's plane, besides
  each end; checked at the `BRIDGE` write against its `ZONE_CHUNK` and at a `ZONE_CHUNK` rewrite
  against its `BRIDGE`s (R-34's reverse check). New code `bridge: deck not floor`. It holds the one
  invariant D-227 needs on chain: a deck is floor.
- **P-2** (the records re-assembled equal to the painted map) compares against the painted map with
  the decks made walkable, so it does not refuse the converter's own change.
- Nobody passes under a deck: its tile is one ground tile, taken by at most one actor (the occupancy
  of today, ENG-01 §3.2).

### Rule 2 — Movement and pathfinding: nothing changes

- **A Move** (design/04: one tile, six directions, one tick, two Crippled, facing set) is legal on a
  deck tile as on any floor: ENG-07's check reads "the tile walkable on the one walkable plane;
  unoccupied; the adventurer able to move" (its brief, scope 2 and Open question 7, D-225). The
  window that check reads is assembled from the revealed chunks' `Terrain` walls (ENG-01 §3.2:
  "`Terrain`: walls, bit `15 row + column`"; ADR-0006 §4), which an authored zone's reveal (ENG-09)
  copies from `ZONE_CHUNK` part 0, where the converter wrote the deck walkable (rule 1). **So ENG-07's
  move check needs nothing for bridges beyond walkability**: no level, no second board, no branch.
  The +2,060 a move of the two-level proposal (its caller's branch) goes away with it.
- **The goblins' flood** (D-127, `hexx`'s `Bfs::flood` on the window's walkable bitmap) walks decks
  as any ground: no rule, no cost. Goblins cross bridges; a goblin's return to its spawn walks the
  same plane.
- A bridge is a crossing of one tile's width (the editor's): two actors cannot pass each other on a
  one-tile deck, as in any one-tile corridor.

### Rule 3 — Sight

- **A deck does not block sight**: it is floor in the walkable plane, and line of sight (design/04,
  `WindowTrait::sight`, D-174) is blocked by walls only. **D-221's water rule holds for the rest of
  the water**: a lake or a river is a wall and hides what lies beyond it, except along a deck's own
  tiles.
- Seeing and the reveal (design/18: radius 6, no line of sight) read positions only: unchanged.

### Rule 4 — Combat, traps and quotas: nothing changes

- Reach, shapes, arcs and facing (design/04, design/19 §2.3) read the plane: a deck is a floor tile.
  No melee or shape rule is added.
- **Traps** (design/19 §5.11): a placed trap needs a walkable tile with no actor and no object, so it
  may be placed on a deck and triggers on entry as anywhere. Terrain traps are authored objects:
  rule 5.
- **Quotas** (ENG-05, D-208, D-220; ENG-09's authored draws) place on the author's candidate tiles,
  checked by R-14 and rule 5. Generated zones and dungeons have no bridge.

### Rule 5 — The content checks: R-37 kept (widened), R-38 dropped

- **R-37 kept, widened to the deck** (ENG-09's `ZoneAssert` and the converter; code `bridge: tile
  taken`): **no spawn point, object, candidate tile, gate anchor or entry on a bridge's deck or
  ends**. Why it still serves one level: an object holds its tile (design/19 §5.11: a trap's tile
  "holds no actor and no object"), and a bridge is often a zone's only crossing (P-1 now accepts such
  a map, rule 6), so an object on its deck or an end would close it; P-1 reads tiles, not objects,
  so only this check keeps a bridge open. With decks walkable (rule 1), R-14 alone would let content
  onto a deck: hence the widening. Checked at the `BRIDGE` write against its `ZONE_CHUNK` (and the
  `LOCATION`'s entry, the anchored `GATE`s), and at those records' writes against the chunk's
  `BRIDGE`s (the reverse check).
- **R-38 dropped** (two bridges' decks never touch; an end on no deck and touching no other deck). It
  only kept the two-level window's masks exact (a deck tile next to an end had to be that end's
  bridge's). With one level no rule reads which bridge a tile belongs to. Two touching bridges are a
  drawing matter for the editor, not a rule of the chain. The review's cross-seam finding on it
  (t-0095, note 4) lapses with it.

### Rule 6 — The converter's reachability (P-1)

- **P-1 reads decks as walkable**: it runs on the plane the converter writes (rule 1), so a map whose
  only crossing is a bridge is **accepted**. No second graph. P-3 (a deck connected) is kept: a deck
  in pieces would draw a broken bridge.
- Prototype: `spikes/SPK-18-bridges/reach.py`, one level (5 tests: a river crossed only by a bridge
  refused when its deck is left as water and accepted when written walkable; the editor's bridge;
  a floor tile beyond the bridge that nothing reaches refused; R-37 on an end and on the deck).

### Rule 7 — The window and the reveal

- **No deck bitmap in the window** (ADR-0006 §4): the window is the walkable plane, decks included.
  The reveal (ENG-05, ENG-09, ENG-10b) copies the plane: unchanged. Dungeons have no bridge.
- **The `Terrain` bridge count** (proposed by the two-level version at bits 229–232) is **not needed by
  play** any more: nothing in a tick reads a `BRIDGE` record. The client draws the sprites from the
  registry's public records (`ZONE_CHUNK` part 1 bits 208–211 and the `BRIDGE` records, D-214).
  Listed for ENG-09 (bookkeeping), recommended dropped unless the client asks (Open question 2).
- `instance_state` and `instance_region` (ENG-01 §4.1), the frozen events (ENG-01 §5, D-193):
  unchanged.

### What each rule reads today, and what changes

| Rule (ENG-01 §3.5's terrain readers) | Reads today | With bridges (D-227) |
|---|---|---|
| Movement (ENG-07, D-225) | the walkable plane, the occupancy | unchanged: a deck is floor (rule 2) |
| The flood (D-127, 15 layers, `hexx`'s `Bfs`) | the walkable plane, frozen occupancy | unchanged |
| Line of sight (`WindowTrait::sight`, D-174) | walls | unchanged: a deck is not a wall (rule 3) |
| Shapes and reach (design/19 §2.3, §5.5) | walls | unchanged |
| Placement and traps' tiles (design/18, design/19 §5.11) | the allowed floor tiles | R-37 keeps authored content off a deck and its ends (rule 5); a placed trap may sit on a deck |
| Sight and the window's assembly (ADR-0006 §4) | the chunks' walls | unchanged |
| The generation (dungeons, a zone not authored) | its own board | unchanged: no bridge |
| The converter (P-1, P-2, P-3; SPK-16) | the painted walkable plane | decks written walkable before the walls (rule 1); P-1 on that plane; P-2 against the map with decks walkable |
| The registry's checks (R-33 … R-36) | `BRIDGE`, `ZONE_CHUNK` | R-34 extended to the deck; R-37 added |

### The cost

None in play: no bit, no slot, no check is added to a tick or a batch (rule 2). The registry's
writes gain R-34's extension and R-37 (ENG-09 measures them with its other checks, off the
expedition's path). The two-level figures are history (below).

### The client mirror and the vectors

- **`client/sim`**: nothing. No rule of play changes; the window's mirror already reads one plane.
- **`contracts/logic/vectors/`**: no new table. ENG-07's movement table (its brief, scope 11) may
  hold one row on a deck tile, as floor; nothing else.
- **The converter's checks table** (`spikes/SPK-16-authored-zone/map-format/checks.json`, promoted by
  ENG-09; the editor runs the same cases): R-34's deck case (`bridge: deck not floor`), R-37's cases
  (each content kind on an end and on the deck), P-1 accepting a bridge as the only crossing.
- **`client/app`** (track CV): the bridge sprite drawn over the water; an actor on a deck drawn on the
  bridge. The editor writes the deck walkable, or leaves it to the converter (Open question 1).

### What the bookkeeping changes (not edited by this lot: ENG-10b holds ENG-01, ADR-0006 and PLAN)

- **ENG-01 §3.5**: the `BRIDGE` row's "the reveal does not read it in version 1: its rules are
  ENG-08b's" → "no rule of play reads it (D-227): the deck is walkable in the plane, the record is
  the client's"; R-34 extended to the deck and R-37 added to the checks table; P-1's sentence ("a map
  whose only crossing is a bridge is refused until ENG-08b") → P-1 on the plane with decks walkable.
- **ADR-0006**: CM-7's "Open in it: a bridge's rules (ENG-08b)" → answered by this ADR.
- **design/18**: D-221's limit gains "except along a bridge's deck" (rule 3).
- **PLAN**: ENG-08b done; **ENG-07b cut** (D-227); ENG-07's row "Movement across bridges takes
  ENG-08b's rules" → "a deck is floor (ADR-0008); nothing to build". **ENG-09's row gains what
  remains of the bridge work**:
  1. the converter writes each deck tile walkable before the walls, P-2 compares with the decks
     walkable, P-1 runs on that plane (`reach.py`);
  2. R-34 extended (`bridge: deck not floor`) and R-37 (`bridge: tile taken`), each with its reverse
     check, in `ZoneAssert` and the checks table;
  3. the `Terrain` bridge count: not needed by play; build it only if the client asks (Open
     question 2).

## Open questions (each with its decider and a recommendation)

| # | Question | Decider | Recommendation |
|---|---|---|---|
| 1 | Who makes a deck walkable: the editor when the bridge is placed, or the converter when it writes the plane? | orchestrator, with track CV (CLI-09) | **The converter** (one place, and R-34's extension refuses a record that disagrees); the editor may show it so, the export stays as painted |
| 2 | The `Terrain` bridge count at the reveal | orchestrator (ENG-09's scope) | **Drop it**: nothing in play reads it; the client reads the registry's public bridge records |
| 3 | R-37 widened to the deck (content off a deck as well as its ends) | orchestrator (a content rule of the track) | **Yes**, as rule 5 |

## History: the two-level proposal (D-217, D-226), void under D-227

The version reviewed at `38cfd13` gave a position a level bit (`MemberState` 176, `GoblinState` 240,
241), a two-level movement check (the climb from an end, the descent, the passage under, the cut, the
railings), a two-level flood, occupancy per level, sight through a deck as a combat window
`open | deck`, no melee across levels with shapes on both, deck bitmaps in the window, and R-38. The
project manager ruled its questions (D-226). D-227 voids all of it but the content rules (rule 5).
Its spike measured, on Linux in two clean builds (`spikes/SPK-18-bridges/pairs.txt`): the one-level
check 19,396 a move, the two-level check 36,868 on every path (equal on every path: measured, cause
not established), 21,456 with no deck and 36,568 with one when the caller branched; a level read
+3,430 and written +1,300. Kept as history; nothing builds on them.

## What would reverse it

The owner's word on D-227 (two levels again: the history above is where to start).

## Sources

ENG-01 §3.2, §3.5, §4.1; ADR-0006 §4; design/04, 18, 19 §5.11; docs/briefs/ENG-07-movement-and-window.md
(scope 2, Q7, D-225); docs/briefs/ENG-08-authored-zones-format.md (A3); docs/decisions/2026-10-07-authored-zones-format.md;
docs/reports/CLI-09e-palette.md §1, §2.4; `spikes/SPK-16-authored-zone/map-format/` (`convert.py`,
`checks.json`); `spikes/SPK-18-bridges/`; review t-0095 at `38cfd13`.
