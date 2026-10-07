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
- **Two refusals first** (the converter, before it writes the plane; ENG-09's list, one case each in
  `checks.json`): a deck tile **outside the zone** (outside its outline, where R-20 makes every tile
  of a border chunk's mask a wall: written walkable, it could satisfy neither R-20 nor R-34's
  extension), code `export: deck outside the zone`; a deck tile **on a blocked hex** (a building's
  footprint, a blocking prop: `convert.py`'s `blocked`, which the client draws as an obstacle), code
  `export: deck blocked`. Water beneath a deck is what D-227 means; nothing else is overridden.
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
- **Traps** (design/19 §5.11): a placed trap (a skill's, in play) needs a walkable tile with no actor
  and no object, so it may be placed on a deck and triggers on entry as anywhere; nothing in play
  keeps it off a deck. A terrain trap is authored content, kept off the crossing by R-37 (rule 5) as
  a content discipline, not because an object blocks a move: the two do not contradict.
- **Quotas** (ENG-05, D-208, D-220; ENG-09's authored draws) place on the author's candidate tiles,
  checked by R-14 and rule 5. Generated zones and dungeons have no bridge.

### Rule 5 — The content checks: R-37 kept (widened), R-38 dropped

- **R-37 kept, widened to the deck** (ENG-09's `ZoneAssert` and the converter; code `bridge: tile
  taken`): **no spawn point, object, candidate tile, gate anchor or entry on a bridge's deck or
  ends**. Why it still serves one level: it is a **content discipline**, keeping authored content
  (spawn points, objects, candidate tiles, gates, the entry) off the crossing, a one-tile corridor
  that is often a zone's only one (P-1 now accepts such a map, rule 6). It does not rest on blocking:
  **objects do not block movement** (the occupancy is the members' and goblins' tiles, ENG-01 §3.2;
  ENG-07's check is walkable, unoccupied, able to move). With decks walkable (rule 1), R-14 alone
  would let content onto a deck: hence the widening. Checked at the `BRIDGE` write against its
  `ZONE_CHUNK` (and the `LOCATION`'s entry, the anchored `GATE`s), and at those records' writes
  against the chunk's `BRIDGE`s (the reverse check).
- **What R-37 does not keep off a deck**: a pack's goblins spread over the 19 tiles within 2 of their
  spawn point (ENG-01 §3.2, *Features*), so a pack beside a bridge may stand on its deck, and goblins
  walk decks (rule 2). A goblin on a one-tile deck holds the corridor as in any one-tile corridor.
  Whether that needs a rule (a spawn point kept 2 tiles from a deck, for example) is **ENG-09's
  question** (bookkeeping list).
- **R-38 dropped** (two bridges' decks never touch; an end on no deck and touching no other deck). It
  only kept the two-level window's masks exact (a deck tile next to an end had to be that end's
  bridge's). With one level no rule reads which bridge a tile belongs to. Two touching bridges are a
  drawing matter for the editor, not a rule of the chain. The review's cross-seam finding on it
  (t-0095, note 4) lapses with it.

### Rule 6 — The converter's reachability (P-1)

- **P-1 reads decks as walkable**: it runs on the plane the converter writes (rule 1), so a map whose
  only crossing is a bridge is **accepted**. No second graph. P-3 (a deck connected) is kept: a deck
  in pieces would draw a broken bridge.
- Prototype: `spikes/SPK-18-bridges/reach.py`, one level (7 tests: a river crossed only by a bridge
  refused when its deck is left as water and accepted when written walkable; the editor's bridge;
  a two-tile deck; an end with no floor beside it but the deck, the far bank refused as
  `pipeline: unreachable tile`; a deck outside the zone and a deck on a blocked hex refused (rule 1);
  R-37 on an end and on the deck).

### Rule 7 — The window and the reveal

- **No deck bitmap in the window** (ADR-0006 §4): the window is the walkable plane, decks included.
  The reveal (ENG-05, ENG-09, ENG-10b) copies the plane: unchanged. Dungeons have no bridge.
- **The `Terrain` bridge count** (proposed by the two-level version at bits 229–232) is **not needed by
  play** any more: nothing in a tick reads a `BRIDGE` record. The client draws the sprites from the
  registry's public records (`ZONE_CHUNK` part 1 bits 208–211 and the `BRIDGE` records, D-214).
  **Dropped** (Open question 2, decided by the orchestrator): reversed if the client needs the count
  from the chain.
- `instance_state` and `instance_region` (ENG-01 §4.1), the frozen events (ENG-01 §5, D-193):
  unchanged.

### What each rule reads today, and what changes

| Rule (ENG-01 §3.5's terrain readers) | Reads today | With bridges (D-227) |
|---|---|---|
| Movement (ENG-07, D-225) | the walkable plane, the occupancy | unchanged: a deck is floor (rule 2) |
| The flood (D-127, 15 layers, `hexx`'s `Bfs`) | the walkable plane, frozen occupancy | unchanged |
| Line of sight (`WindowTrait::sight`, D-174) | walls | unchanged: a deck is not a wall (rule 3) |
| Shapes and reach (design/19 §2.3, §5.5) | walls | unchanged |
| Placement and traps' tiles (design/18, design/19 §5.11) | the allowed floor tiles | R-37 keeps authored content off a deck and its ends (rule 5, a content discipline); a placed trap and a pack's spread may sit on a deck |
| Sight and the window's assembly (ADR-0006 §4) | the chunks' walls | unchanged |
| The generation (dungeons, a zone not authored) | its own board | unchanged: no bridge |
| The converter (P-1, P-2, P-3, R-36; SPK-16) | the painted walkable plane | a deck outside the zone or on a blocked hex refused, then decks written walkable before the walls (rule 1); P-1 on that plane; P-2 against the map with decks walkable |
| The registry's checks (R-33 … R-35; R-36 is the converter's) | `BRIDGE`, `ZONE_CHUNK` | R-34 extended to the deck; R-37 added |

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
  bridge. The converter writes the deck walkable (Open question 1, decided); the editor may show it
  so.

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
  1. the converter refuses a deck tile outside the zone (`export: deck outside the zone`) or on a
     blocked hex (`export: deck blocked`), one case each in `checks.json`; then it writes each deck
     tile walkable before the walls, P-2 compares with the decks walkable, P-1 runs on that plane
     (`reach.py`);
  2. R-34 extended (`bridge: deck not floor`) and R-37 (`bridge: tile taken`), each with its reverse
     check, in `ZoneAssert` and the checks table;
  3. the `Terrain` bridge count: dropped (Open question 2), reversed if the client needs it from
     the chain;
  4. whether a pack's spread onto a deck needs a rule (rule 5: R-37 does not cover it), ENG-09's
     question.
- **ENG-07's brief** (`docs/briefs/ENG-07-movement-and-window.md`, a documents change as PLAN's
  ENG-07 row): Open question 7 ("ENG-08b's rules then change movement (a deck entered and left only
  by its ends); the report lists where they will plug in") → "D-227: one level; a deck is floor in
  the walkable plane (ADR-0008); no plug-in"; *Out* ("bridges and levels (ENG-08b, Open question
  7)") → "bridges: nothing to build (ADR-0008, D-227)".

## Open questions (each with its decider, its recommendation and its ruling)

| # | Question | Decider | Recommendation | Decided |
|---|---|---|---|---|
| 1 | Who makes a deck walkable: the editor when the bridge is placed, or the converter when it writes the plane? | orchestrator, with track CV (CLI-09) | **The converter** (one place, and R-34's extension refuses a record that disagrees); the editor may show it so, the export stays as painted | **Decided by the orchestrator, 2026-10-07**: the converter. Reversed if track CV's editor must export decks walkable itself |
| 2 | The `Terrain` bridge count at the reveal | orchestrator (ENG-09's scope) | **Drop it**: nothing in play reads it; the client reads the registry's public bridge records | **Decided by the orchestrator, 2026-10-07**: dropped. Reversed if the client needs the count from the chain |
| 3 | R-37 widened to the deck (content off a deck as well as its ends) | orchestrator (a content rule of the track) | **Yes**, as rule 5 | **Decided by the orchestrator, 2026-10-07**: widened. Reversed if authored content on a deck is wanted (a chest on a bridge) |

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
