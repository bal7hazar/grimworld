# Vector tables for the client's mirror

Each table is printed by tests of `grimworld_logic` and kept here, one JSON line per case, every
felt in hexadecimal. The tests hold a digest of every case and outcome: a change to a rule, or to
the cases, fails them until the table is regenerated (D-140, SPK-4). `check.py` closes the other
side: it runs the tests and fails while the committed file differs from what they print, so a new
digest without the regenerated file fails too (snforge cannot read a JSON-lines file from a test).

```
python3 contracts/logic/vectors/check.py           # exit 1 when a table is stale
python3 contracts/logic/vectors/check.py --write   # regenerate; prints each part's digest
```

After `--write`, set the tests' digests (and, if the first part's count moved, `PART_1`) to the
values it prints and run it again: it must say "as computed".

## `window.jsonl`: the geometry of the window (ENG-02)

Printed by `types::window::tests::test_vectors_0` to `test_vectors_3` (ids 0–1213, four slices of
the pair and triple cases) and `test_vectors_4` (ids 1214–2064), split for snforge's step limit and
memory (FND-23), each part with its digest.

One line: `{"id", "fn", "case", "ok"}`. A position is the window's index `15 y + x` (0–239; 240 and
up is outside the window), a facing `0..=5` (East, North-East, North-West, West, South-West,
South-East), a boolean 0 or 1. `open` is the window's walkable bitmap (bit `p` is 1 for a walkable
tile `p`); the vectors use one fixture with seven walls. The arguments of `arc`, `front` and
`facing` come in one order: the acting tile, the other tile, a facing.

| `fn` | `case` | `ok` |
|---|---|---|
| `sight` | `open`, `from`, `to` | `WindowTrait::sight` (a wall at either end blocks) |
| `reach` | `open`, `from`, `to`, `range` (6) | `WindowTrait::reach` |
| `arc` | `source`, `target`, `facing` (the target's) | `Option<Arc>` as Cairo `Serde`: `[0, a]` for `Some`, `a` 0 `Front`, 1 `FrontSide`, 2 `RearSide`, 3 `Back`; `[1]` for `None` |
| `facing` | `from`, `to`, `facing` (the actor's) | the facing after the action |
| `front` | `source`, `target`, `facing` (the source's) | `WindowTrait::front` |
| `distance` | `from`, `to` | `WindowTrait::distance` |
| `shape` | `open`, `shape` (1 `SINGLE` … 5 `DISC_3`), `centre` | the bitmap of the shape's tiles |

The cases:
- `sight` and `reach`: from both row parities at the centre to every tile within 7, and the edges (a line leaving the window at a corner, a position outside, and `from` on a wall at range, adjacent and on the same tile, D-174).
- `arc` and `facing`: from every tile within 6 of the targets `(7, 8)` (an even row) and `(7, 7)` (an odd row), the facing turning with the source, and the edges.
- `front`: every neighbour and facing, at the centre and on the East edge, where a neighbour outside the window is given as the position 240.
- `distance`: from `(7, 7)`, `(7, 8)` and `(0, 0)` to every tile, and a position outside the window (240, 255) at either end or both, whose distance is 255 (`FAR`, above every range).
- `shape`: each shape at the corners, the edges, the centre and next to walls.

## `movement.jsonl`: moves, the window, the flood, the awake set (ENG-07)

Printed by `types::play::tests::test_vectors`, with its digest. One line: `{"id", "fn", "case", "ok"}`;
a position is the window's index `15 y + x` (0–239), a direction `0..=5` (East, North-East,
North-West, West, South-West, South-East), 255 none.

| `fn` | `case` | `ok` |
|---|---|---|
| `origin` | the adventurer's tile `x`, `y` (global) | `Board.x`, `Board.y` (the window's origin plus 15, so a negative origin at a West or South edge holds, D-134) and its window position: local `(7, 7)` (112) on an odd row, `(7, 8)` (127) on an even one |
| `move` | `from`, a direction | the tile a Move reaches (`hexx`'s `LayoutTrait::neighbor` on the window), 255 at the window's edge |
| `ticks` | Crippled's deadline, `t0`, a `MOVEMENT` effect held (0 or 1) | a Move's ticks: 2 while Crippled without `MOVEMENT`, else 1 |
| `flood` | the walkable grid, the flood's source, a walker | the walker's step toward the source and its distance, 255 when beyond the 15 layers (it holds, D-127) |
| `awake` | each goblin's distance (entity `8 + k`; the fourth asleep) | the awake set's entities: the 8 nearest, ties by the lowest id |

The `flood` rows after the corridor's ten: a walker at distance 15 steps and one at 16 holds (255, 16: the cap is 15 layers); a walker touching only the last layer (two tiles of it) holds; a walker with two candidate steps in its least layer takes the lowest tile index; an open tile on the window's ring is never in a layer (the pocket reached only through the ring is not reached, 255, 255).

## `batch.jsonl`: where a played batch stops (CBT-05d)

Printed by `types::play::tests::test_batch_vectors`, with its digest. One line: `{"id", "fn", "case", "ok"}`,
every value an integer, a boolean 0 or 1. The rules are `SegmentTrait::admit` (E-16's cap of 16 goblin
records an invocation and E-1's weight of a first record, D-141) and `SegmentTrait::revealed` (a reveal's
weight, 2 a chunk), which `SegmentLibrary` and `PlayLibrary` call.

| `fn` | `case` | `ok` |
|---|---|---|
| `records` | the records counted before the action, its new records, how many of them are first records, its ticks, whether an action ran before it in the invocation, the weight left | stopped (the batch stops before the action, nothing of it kept), the records counted after, the weight left (floored at 0) |
| `owed` | the records counted before, the owed ticks' new records and first records, the next action's new records, first records and ticks, the weight left, whether a next action exists | the next action stopped, the records written, the weight left |
| `reveal` | the weight before the revealing Move, its ticks, its first records, the chunks revealed | the weight after the Move, after the reveal |

The cases:
- `records`: the 16th record passes and the 17th stops (from 10, and at the boundary 15 + 1, 16 + 0, 16 + 1); first records weigh 1 more each, the weight cut at exactly 0 and one past; a Move of 2 ticks with 1 left; the invocation's first action binds neither (E-21), its weight floored at 0.
- `owed`: a Move that ends a segment (a reveal, a chunk crossed) has its ticks run first in the next segment, counted with that segment's first action. Its 7 records after 10 stop a next action that adds none (`test_play_records_owed_ticks`), the owed records still written (17); 6 do not. With no next action nothing is counted: the records written are E-16's bound, 16 plus the owed ticks' (16 + 40, the goblins of the window; 16 + 2 × 40 = 96, ENG-01 E-16).
- The `owed` rows restate the rule: only `admit` is the contract's code in them; the test builds the rest (the owed
  records added, the `written` count when no action follows). `SegmentTrait::run`'s counting of owed ticks is checked by
  `test_play_records_owed_ticks` (`contracts/ephemeral/tests/test_play_limits.cairo`: 17 records written, the next Move
  stopped), not by this table.
- `reveal`: the Move's ticks and first records are taken first, then 2 a chunk, floored at 0: a Move that reveals more chunks than the weight left still plays.

## `segment.jsonl`: one segment of a batch, `SegmentTrait::run` (RV-01, D-248)

Printed by `types::play::tests::test_segment_vectors`, with its digest. One line: `{"id", "fn", "case", "ok"}`,
every felt in hex; every struct, `Option` and `Span` is its Cairo `Serde` (a span: its length, then its elements;
an `Option`: `1` for `None`, `0` then the value for `Some`; an enum: its variant's index, then its value).
`fn` names the branch of `run` the row is about; the shape is the same for every row.

**`case`**, in order:
- the adventurer (member 0, alone in the world, no goblin): `clock`, `x`, `y` (global tile), `facing`, `status`
  (0 inside, 1 down), `health`, Crippled's deadline (0: not Crippled; a Move at tick `t0 ≤ deadline` takes 2 ticks),
  the end of a knock-down (0: none; knocked while `t0 ≤` it); energy and the rest as the unit-test fixture;
  as the fixture's member, it holds no effect in any slot (no `MOVEMENT` effect) and starts with `flags` 0;
- `Area`: `width`, `height` (3 × 3 chunks, all known), `known`, `revealed`, `chunks` (the span of `(chunk, walkable
  bits)` of the revealed chunks: bit `15 ly + lx`, 1 walkable), `changed` (the goblin entities whose records
  the invocation's earlier segments changed), `ran`;
- `owed` (ticks), `weight`;
- the actions (a span): `Move(d)` is `0, d`, `Turn(d)` `1, d`, `Wait` `2`, `Interact(tile)` `6, tile`.
  A direction is the one of `vectors/movement.jsonl`: 0 takes x − 1, 3 takes x + 1, 1 and 2 take y + 1, 4 and 5 take y − 1
  (one tile, the window's rows; odd and even rows are the window's, not these columns).

**`ok`**: the world after: `clock`, `x`, `y`, `facing`, the adventurer's `flags` (bit 0: turned since the last
tick; cleared by the next tick); then `Done`: `played`, `weight`, `owed`, `reveal`, `illegal` (`Option<Illegal>`:
`[1]`, or `[0, i]` with `i`: 0 Clock, 1 Absent, 2 Knocked, 3 Turned, 13 Kind, 14 Blocked), `heavy`, `changed` (its
length, then the entities), `undo`. The world after is also the world of a row that stopped: an action that is
`heavy` without `undo`, or illegal, wrote nothing; one that is `undo` is written (the caller runs the segment again
with the actions before it).

No class is called (the class hashes are zero), so every row has no goblin and its ticks take the fast path
(`TickTrait::idle`: the clock advances, the adventurer regenerates and the turned flag clears). The goblin
records of a fight (`fits` counting new records and first records, the weight of E-1, the owed ticks' records) are
`TickLibrary`'s; `fits` is reached here through the 17 records the area already holds (E-16: more than 16 stops an
action when `ran`). The owed ticks' records are held by `test_play_records_owed_ticks`
(`contracts/ephemeral/tests/test_play_limits.cairo`) and by `batch.jsonl`'s `owed`. The branches that call a class,
or meet a goblin, a trap, a companion, a change of health or a `MOVEMENT` effect, are `segment2.jsonl`'s.

The cases (47):

| `fn` | ids | what |
|---|---|---|
| `fold` (6) | 0–5 | the owed ticks run first: `owed` 0 and 3 before a Wait (0, 1), with no action (2); with Crippled to tick 42 a Move takes 2 ticks without `owed` and 1 after 2 owed ticks (3, 4); `changed` passes through (5) |
| `reveal` (6) | 6–11 | a Move ends the segment (`reveal`, `owed` = its ticks, the clock not advanced, the actions after it do not run): sight reaches an unrevealed chunk (6), the chunk changes East (7), after Wait, Turn with 2 owed ticks and Crippled (8, `owed` 2), West (10), North (11); 9: Moves that reveal nothing (the window follows, they and the Wait run) |
| `cost` (12) | 12–23 | `max(1, ticks)`: a Turn (0 ticks, none run) is charged 1 (12), a Wait 1 (13), a Move 1 or 2 (14, 15); the weight exact: Wait 1 (16), Turn 1 (17), Crippled Move 2 (20); over by 1, nothing written: Wait 0 (18), Turn 0 (19), Crippled Move 1 (21: `step` stops it, `heavy`); weight spent over several actions (22, 23) |
| `ran` (4) | 24–27 | `ran = area.ran or played > 0`, with 17 records held (16 for the last): neither, the first action runs (24); `area.ran` alone refuses it (25, `heavy` and `undo`); `played` alone refuses the second (26); both at 16 records run both (27) |
| `fits` (5) | 28–32 | accepts at 16 records after a Move and a Turn (28), refuses at 17 with the Move kept (29, `undo`); refuses a Turn then a Wait (30); a Move that reveals accepted at 16 (31) and refused at 17 (32: `reveal` false, `played` 0, the Move written) |
| `halt` (14) | 33–46 | the illegal halts: Clock (33–35: Move, Turn, Wait at `LAST_TICK + 1`), Absent (36–38 health 0, 39 status down), Knocked (40, 41; a Wait is legal, 42), Blocked (43 a wall; the Wait before it runs), Turned (44), Kind (Interact, 45, and after two Waits, 46) |

`Heavy` is not an `Illegal`: it is `heavy` in `Done` (ids 18, 19, 21 and 22, 23).

## `segment2.jsonl`: a segment that calls the classes, `SegmentTrait::run` (RV-02, D-254)

Printed by `types::play::tests::test_segment2_vectors_0` to `test_segment2_vectors_5` (ids 0–11, 12–22, 23–25,
26–30, 31–45, 46–47), split for snforge's step limit, each part with its digest. It covers what `segment.jsonl` cannot: the
branches of `run` that call `TickLibrary`, `ActionLibrary` or `TrapLibrary`, and those that meet a goblin, a trap, a
companion, a regeneration or a `MOVEMENT` effect. One line: `{"id", "fn", "case", "ok"}`, every felt in hex, every
value its Cairo `Serde` (as `segment.jsonl`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content` (`types::tick::Content`): the unit-test
fixture's (`Fixture::content`), skill 8 instant (activation 0), skill 9, an enchantment whose first entry is
`MOVEMENT` (FX-18), and skill 10, an instant trap skill (range 3, a `TRAP` entry, Snare's earth payload). Every other row loads its words through it.

**`case`**, in order: the `Words` (`clock`, the members' `MemberWords`, the goblins' `GoblinWords`, `killed`,
`defeated`), the `Area`, the `level` (1), the `ground` (`Array<(u8, Features)>`: the chunk objects and `touched`
bits the call starts with), `owed`, `weight`, the actions (`Attack(e)` is `3, e`, `Skill((slot, target))` `4, slot,
t, v` with `t` 0 an entity, 1 a tile, `Item((slot, e))` `5, slot, e`; the others as `segment.jsonl`), then **the
calls**: the span of the class calls `run` made, in order (`recorder::Call`):
- `0, digest, Words, ground`: `TickLibrary::ticks`, what it returned;
- `1, digest, Words, ground, Result<u8, Illegal>`: `ActionLibrary::act` (`Ok` is `0, ticks`, `Err` `1, i`);
- `2, digest, Words, ground, triggered`: `TrapLibrary::trigger`.

`digest` is the Poseidon hash of the call's inputs as `Serde` felts, the content and the class hashes left out (the
table's environment): `words, board, level, ground, n` for `ticks`; `words, board, ground, action` for `act`; `words,
board, ground, entrant, position, level` for `trigger`. `board` is `executor::Board` (`window`, `x`, `y`).

**`ok`**: the `Words` after, the `ground` after, then `Done` (as `segment.jsonl`; `illegal` adds 10 Target and 11 Reach).

**Replaying a row.** The mirror runs `run` on the case's words and, where `run` calls a class, takes the next call
of the span instead: it checks the kind and the digest of the inputs it computes, then loads the recorded
`Words` and `ground` as `run` loads the class's (`SegmentTrait::reload`; `trap` writes back the members, and the
placer goblin of a placed trap). This is sound for `run`'s own logic: the classes are pure functions of their
inputs and the content, so a recorded result stands for the call whenever the mirror's inputs hash to the recorded
digest; a mirror that reaches a different call, or none, or calls with other inputs, differs from `run`, and the
row says so. It does not check the classes themselves (the ephemeral tests and `hit.jsonl` do): a mirror replaying
these rows needs no `ActionLibrary` or `TickLibrary` of its own. No branch needed a stub. A replay is sound only when
the mirror computes each call's inputs and checks them against the digest: a mirror that takes the recorded results
without that check can pass a row while calling the classes with other inputs (row 43 is one such case). A mirror
that leaves a recorded call unused also differs: it asserts that each row's span of calls is fully consumed.

The classes are the real ones (`ExecutorLibrary`, `AiLibrary`, `TickLibrary`, `ActionLibrary`, `TrapLibrary`)
behind test recorders (`types/play/tests/recorder.cairo`) that forward each call and log the segment's own:
`TickLibrary`'s nested calls to the trap class are not in the span. The adventurer is the unit-test fixture's
member (two potions 101 in belt slot 1) on (22, 22) of chunk 16 of the 3 × 3 location of `segment.jsonl`, every
chunk revealed, at clock 40, unless a row says otherwise; goblin 264 is chunk 16's first (`8 + 16 chunk + k`), the
fixture's Hob (Engaged, awake, health 100).

**Three behaviours of `run` a mirror reproduces** (track CV's replay, D-255):
- A refused combat action (`Illegal` or `Heavy`) restores the words and leaves the ground as it was (D-259, FIX-01;
  `play.cairo`, `SegmentTrait::combat`: `rules.ground` takes `ActionLibrary`'s ground only when the result is kept).
  A `Heavy` action has already resolved in `ActionLibrary` (an instant trap skill, 0 ticks, with no weight left
  after a first action places its trap there), so its ground is dropped with its words and spends nothing; an
  `Illegal` refusal comes before the first `carry`, so the ground it returns is the one given. Row 44 (an instant
  trap skill refused as `Heavy`): the `ground` in `ok` is the `ground` in `case`. Held by
  `types::play::tests::test_heavy_trap_keeps_the_ground` and `test_illegal_trap_keeps_the_ground`.
- The fast path's ticks (`TickTrait::idle`) regenerate the members as a tick's step does in `TickLibrary`
  (`MemberTrait::regenerate`): health, energy up to its max, and adrenaline decaying (not engaged), not only health.
- The trap call carries the clock, the members and the placer goblin, with `killed` empty and `defeated` false:
  the trap reads neither, and `run` reads back only the members and the placer goblin (a defeat is found by the
  next tick's step 5). `defeated` is false in every reachable state (`run` breaks on `world.defeated` before any
  action); `killed` is not, and the digest of a `trigger` call is over those words with it empty: row 43 holds it
  with a goblin in the world's `killed`.

**Not reached:** `LayoutTrait::neighbor` → `None` (a Move off the window's edge). This rests on there being no
displacement effect (`types/effect.cairo` kinds) and on `rules.board` being refreshed only after a Move: a future
push, teleport or dash must add a refresh and a vector (D-255). The window is assembled around the
adventurer after every Move that does not end the segment, and nothing else moves it, so a Move always starts at
the window's centre (`movement.jsonl`'s `origin`: position 112 or 127), and every neighbour of the centre exists:
hexx 0.2.0's `AssemblyTrait::origin` (`src/board/assembly.cairo`) puts the origin at `(x − 7, y − 7)` on an odd row
and `(x − 7, y − 8)` on an even one, Euclidean. Held by tests in `contracts/logic/src/types/play.cairo` (D-255),
on a 15 × 15-chunk location, every chunk revealed and walkable:
- `types::play::tests::test_board_centred_0` to `_11`: on every tile of four chunks, the board puts the adventurer on
  112 or 127 with its six neighbours in the window. The chunks: 16 (every residue of `x` and `y` modulo 15), 31
  (each residue of `y` on the other row parity), 0 (`x` or `y` below 7, the origin negative, D-134), and 224 (the
  location's last chunk); three tests a chunk, five rows each;
- `types::play::tests::test_move_keeps_board_centred_0` to `_3`: through `run`, walks of 1 to 6 Moves in each
  direction, none ending the segment, from (22, 22), (22, 37), (7, 7) and (217, 217) (chunks 16, 31, 0, 224): after
  each, the segment's board is centred on the adventurer.

The mirror keeps refusing it.

The cases (48):

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `combat` (12) | 1–11, 44 | the `_` arm, goblin 264 beside the adventurer, then a Wait: an Attack out of reach (1, `Reach`, the words kept), a spell on the goblin (2), Cinder Ring on itself (3, 2 ticks), a potion (4), an Attack on no entity (5, `Target`), an instant spell (6, 0 ticks charged 1); `Heavy` (`heavy`, the words kept): 0 ticks with no weight left (7), 2 ticks with 1 left (8), the potion with none (9); appended, 44: the instant trap skill 10 refused as `Heavy` after a Wait spent the weight, the ground unchanged (D-259); alone, a spell (10: the member activating, its ticks through `TickLibrary`) and a potion (11: its ticks on the fast path) after a Wait |
| `ticks` (4) | 12–15 | `Self::ticks` through `TickLibrary`: two Waits beside goblin 264 (12); 2 owed ticks, no action (13); a goblin awake outside the window, so not calm (14); an asleep one there, calm: the fast path, no call (15) |
| `fits` (9) | 16–22, 46, 47 | the goblin records of a Wait beside goblin 264 with no record (`touched` bit clear, E-1: 1 more): `ran` and the weight 1, refused (16, `undo`); weight 2, taken (17, 0 left); the invocation's first action, unbound (18); with a record, taken (19); held by an earlier segment, nothing added (20); E-16's 17th record refused (21, `undo`); the untouched one engaged (22): goblin 248 asleep beside the adventurer notices it and engages its pack, 249, outside the window and not awake, changes only its AI state (1 to 3) and is not counted (`changed` holds 248 alone); appended by RV-03c, 46 and 47 (two actions of one segment changing one goblin, and E-1's exception across them; they do not separate the `fits` mutant that compares with the goblins before the segment, which is equivalent: see below the table): 248 asleep beside the adventurer engages its pack at the first Wait's tick; 249, of that pack, in the window on (19, 22), knocked down to 41 and at its energy's max, changes only its AI state there (no record, E-1's exception); knocked down to 41 (46), it acts at the second Wait's tick (it starts an activation: a change against its words after the first Wait, its first record); to 42 (47), it changes nothing more |
| `defeated` (3) | 23–25 | `world.defeated` breaks the loop: the adventurer at 0 health, defeated by the owed tick before the first action (23, `played` 0, no `illegal`); at 1 health with Bleeding, Poison and Burning, on the first Wait's tick, on the fast path (24) and through `TickLibrary` (25) |
| `trap` (5) | 26–28, 43, 45 | a Move West onto local (6, 7) of chunk 16, then a Wait: a terrain trap (26, `param` skill 2), a used one (27, no call), a placed trap of goblin 264, outside the window (28: its words go with the call); appended, 43: the terrain trap with goblin 265 dead and in the world's `killed`, the call's `killed` empty; appended, 45 (FIX-02, D-266): a terrain trap of skill 10, which no member or goblin of the call holds: on chain the content holds it only because `play` reads the unused terrain traps' skills (`GoblinsLibrary`, FIX-02b), and the client's content must too |
| `occupied` (2) | 29–30 | a Wait, then a Move West onto goblin 264: `Blocked` from `TrapTrait::occupied` (29); dead, it does not block (30) |
| `companions` (3) | 31–33 | a second member on (23, 22) blocks a Move East (31); down, it does not (32); on (25, 22), at 300 health with health regeneration, it regenerates on the fast path with an owed tick and two Waits (33) |
| `regeneration` (3) | 34–36 | an owed tick, a Wait, a Move and a Wait on the fast path: health regeneration under the max (34), at it (35), Bleeding to tick 42 (36) |
| `movement` (2) | 37–38 | Crippled to 100, two Moves West: with skill 9's `MOVEMENT` held to 100 each takes 1 tick (37); held to 40, ended at clock 40, 2 (38) |
| `turn` (2) | 39–40 | CV: Turn, Wait, Turn: the Wait's tick clears the turned flag, the second Turn is legal, `flags` 1 after it (39); a third Turn after it is `Turned` (40) |
| `follow` (2) | 41–42 | CV: the window follows each Move that reveals nothing: seven Moves West from (22, 22), the seventh onto (15, 22), on the first window's ring (never open in it), then a Wait (41); from (29, 22), the eighth Move West is `Blocked` by a wall on (21, 22), outside the first window (42) |

Per `fn`: `content` 1, `combat` 12, `ticks` 4, `fits` 9, `defeated` 3, `trap` 5, `occupied` 2, `companions` 3,
`regeneration` 3, `movement` 2, `turn` 2, `follow` 2.

**`fits` against the goblins before the segment is equivalent** (track CV's candidate 17, RV-03a2). `fits` compares
each goblin's words with those after the previous action (`before`, `types/play.cairo` 533–537, its first value the
world before the owed ticks, 168); the mutant keeps the segment's start instead. The two differ only for a goblin whose
words after an action equal the segment's start while differing from the previous action's: a goblin left unrecorded
by an Engaged-only change (542–545: E-1's exception) whose AI state goes back to its start value at a later action,
nothing else changed. No AI state leaves `ENGAGED` but for `DEAD`: perception engages a goblin at or below `ALERTED`
(`types/world.cairo` 590–595, written at 616); a Fleeing goblin cornered engages (`types/ai.cairo` 270–278); a goblin
struck asleep or on watch engages (`types/executor.cairo` 830–837); every other write is a death (`ExecutorTrait::put`
2008–2011, `World::kill` `types/world.cairo` 937–945, step 3's at 438–441). An Engaged goblin goes back to no earlier
state within a segment, so no row can kill the mutant, and none is appended.

## `trap.jsonl`: a trap's trigger, `TrapTrait::trigger` (RV-03a, D-257)

Printed by `types::trap::tests::vectors::test_trap_vectors_0` to `_7` (ids 0–13, 14–23, 24–35, 36–58, 59–62, 63–68,
69–78, 79–86), split for snforge's step limit, each part with its digest. Where `segment2.jsonl` records the trap class's result for a replay,
this table tests a port of the class itself: each row is one call of `TrapLibrary::trigger` (the real class, declared
in the test), which loads the words through the content, finds the entrant by its entity
(`ExecutorTrait::actor`: none, nothing triggers), runs `TrapTrait::trigger` with a fresh `Cache`, and stores the words
back. One line: `{"id", "fn", "case", "ok"}`, every felt in hex, every value its Cairo `Serde` (as `segment2.jsonl`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content`: the executor tests' (`types::executor::tests::
content(40, [])`: castes of armor 40, a sword of 30 at rank 12; Snare, skill 45: `TRAP`, earth 10 to 40, Crippled 3),
with Hob's caste skill 26 (its slot 2) a trap skill of Snare's payload; skill 70, a terrain trap's (earth 10 to 40,
Poison 4); 71, a pit (earth 30 to 60 guarded `BELOW_HALF`, Knocked down 2); 72, caltrops (Bleeding 10 to 22, no hit).

**`trigger`**: `case` the call's arguments but the content: the `Words` (`clock` 305, the members' `MemberWords`, the
goblins' `GoblinWords`, `killed`, `defeated`), the `Board` (`window`, `x`, `y`: the origin plus 15, D-134), the
ground (`Array<(u8, Features)>`), the entrant's entity (a member's index 0–7, or a goblin's entity), the window's
position, the level (the location band's lower level, a terrain trap's source). `ok` what it returns: the `Words`,
the ground (the trap's object marked used, state 1), then whether it triggered (0 or 1).

**`free`**: `TrapTrait::free`, the object index a placed trap takes (§5.11): `case` the chunk's `Features` and the
tile, `ok` the `Option<u32>` (`[1]` none, `[0, k]`).

The world, unless a row says otherwise: the trapper, member 0 on (7, 7) (level 20, health 400 of 480; its bar Snare in
slot 0 at rank 12, the pit in slot 1 at rank 0, caltrops in slot 2 at rank 15, slot 7 empty), goblin 44 (the entrant,
a Hob on the trap's tile, health 100, Engaged) and goblin 45 (a Hob, a placer); the board at origin 0, the trap on
position 142, chunk 0's tile 142. A trap's hit is never blocked or evaded and has no arc (`ExecutorTrait::trap`): the
"evaded or blocked" rows are the entrant holding a `BLOCK` or an `EVADE` effect, landed all the same.

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `trigger`, terrain (7) | 1–7 | a terrain trap (kind 4, `param` skill 70) on the member at levels 20, 1 and 40 (1–3); on a goblin, nothing (4: FX-34); a skill the content lacks (99), nothing, the trap left unused (5); used (state 1), nothing (6); the member at 1 health, killed, its Poison not applied (7) |
| `trigger`, a member's (6) | 8–13 | Snare (slot 0, rank 12, level 20) on goblin 44: §10.10's 100 → 44, Crippled to 307 (8); on the member, its side, nothing (9); on a second member, nothing (10); placer member 1 of a world of one (`m ≥ count`), nothing (11); of two (12: it triggers, member 1's slot 0 holds skill 1, no entry, nothing applied); bar slot 7 empty (`ABSENT_LANE`), nothing (13) |
| `trigger`, the source (10) | 14–23 | the pit's hit guarded `BELOW_HALF` on the placer (health × 2 < 480): at 400 and 240 not held (the knock-down alone, to 306), at 239 held (100 → 58) (14–16); caltrops at rank 15 (Bleeding 25: to 329), with `CONDITION_DURATION` Bleeding 33 % (337), 63 % (capped at 50: 341), Poison 33 % (another condition: 329) (17–20); `KNOCKDOWN_FLAT` 3 with the pit's hit held: 2 + 3, to 309 (21); Snare at rank 0 (100 → 86) and 15 (100 → 34) (22, 23) |
| `trigger`, a goblin's (4) | 24–27 | goblin 45's trap (caste slot 2, rank 12, level 10) on the member (24); on goblin 44, its side, nothing (25); its placer dead, its record still the source (26); its placer not in the call (entity 46), nothing (27) |
| `trigger`, the entrant (8) | 28–35 | under Snare: goblin 44 asleep (wakes, Engaged), on watch (wakes), at 1 health (killed, in `killed`, Crippled not applied) (28–30); the member under goblin 45's trap holding Brace (a `BLOCK` charge: not blocked, the charge kept), Sidestep (`EVADE`: not evaded), Knocked down (31–33); an entrant the call does not hold: entity 99, member 1 of one, nothing (34, 35) |
| `trigger`, the lookup (13) | 36–48 | the object written: a chest on the tile at 0, the trap at 1 (36); a chunk of 3 objects, used traps on the tile at 0 and 1, the trap at 2 (37); the trap on another tile, nothing (38); chunk 0 the ground's second entry, entry 1 written (39); no chunk 0, nothing (40); chunk 0 twice, the trap in the second: only the first is read, nothing (41). The position: 240, outside, nothing (42); 239, chunk 15's tile 14 (43); a negative origin on the x axis, `(−5, 0)`: position 0 before the location, nothing, position 5 its tile (0, 0) (44, 45; the y axis: 59, 60); origin x 210, position 14 chunk 14's tile 14 (46); origin x 240, chunk column 16, nothing (47); origin y 240, chunk row 16, nothing (48) |
| `free` (10) | 49–58 | an empty chunk: 0 (49); a chest elsewhere at 0: 1 (50); a used placed trap, a used terrain trap at 0: 0 (51, 52); a chest on the tile, an unused trap on it: none (53, 54); a used trap on the tile at 1: 1 (55); full, a used vein at 1: none (56); full, a used trap at 2: 2 (57); an empty object (kind 0) whose tile is the tile: 0 (58) |
| `trigger`, appended (4) | 59–62 | RV-03a's fix loop 1 (the review of #440), after every earlier id: a negative origin on the y axis, `(0, −5)`: position 0 before the location, nothing (59), position 75 (row 5) its tile (0, 0), chunk 0's tile 0 (60); goblin 45's trap from caste slot 0 (skill 24) and slot 3 (skill 27), neither holding an entry: it triggers on the member, nothing applied, the trap used (61, 62) |
| `content` (1) | 63 | RV-03a2 (D-257), after every earlier id: the content of rows 63–86 (below) |
| `trigger`, the lookup's bounds (5) | 64–68 | each ground holding an unused terrain trap where a port without the bound would look, nothing triggered: position 240 (chunk 15's tile 15 if read as inside) (64); origin x 240, position 14 (chunk column 16; chunk 16's tile 14 without the column's bound) (65); origin y 240, position 0 (chunk 240) (66); origin y 225 (chunk 225, `MAX_CHUNKS`, on the bound) (67); origin `(−5, 15)`, position 15 (x before the location; chunk 14's tiles 10 and 25 without the West guard) (68) |
| `trigger`, the entrant's defence (10) | 69–78 | the member under goblin 45's trap (Snare's earth at rank 12) with `ARMOR_VS` 9 against earth (`MemberStats` 224) (69); goblin 44 under the member's Snare, Hob's `ARMOR_VS` 9 against earth (70); the member's armor 10, stance sum 4 and enchanted sum 3 (`MemberBar` 232, `MemberKit` 184, 192) holding Brace (a stance) and the shield (`ARMOR` 30, an enchantment) (71), holding neither (72); the member holding the shield to 305 (the clock: held) and 304 (lapsed) (73, 74); the rust (−20, clamped to 0) and the shield (75); goblin 44 holding the shield to 305 and 304, the rust alone (76–78) |
| `trigger`, the payload (8) | 79–86 | goblin 45's trap from caste slot 3 (skill 27: earth guarded `BELOW_HALF`, Knocked down 2), the placer at 140 of 280 (not held: the knock-down alone) and 139 (held) (79, 80); the member's from bar slot 3 holding skill 74 (Crippled guarded `BELOW_HALF`) on goblin 44, the placer at 400 (not held: the hit alone) and 239 (held) (81, 82); bar slot 3 holding skill 47 (heal 30, cure Bleeding, 5 energy) on goblin 44 bleeding to 400: 130, cured (`D = T − 1`), 15 thirds (83); bar slot 3 holding the shield: goblin 44 holds it to 309 (84); a dead goblin (health 0, `DEAD`) entering the member's Snare: it triggers, nothing applied, `killed` empty (85); goblin 45 a Runt of level 16 (rank 6), goblin 44 (the world's first goblin) a Hob of level 10: Runt's slot 2 (skill 30: earth, Poison 4) at rank 6 and level 16 on the member (86) |

Per `fn`: `content` 2, `trigger` 75, `free` 10.

`place` and `spot` (placing, `free` with the window's checks) are not in this table (the trap unit tests `test_place`
and `test_example_trap` hold them; RV-03b's `act` places).

**Row 63** (RV-03a2): every row from 63 on reads the content of row 63, the last `content` row before it; rows 1–62 read
row 0's. It is row 0's with: Hob's caste skill 27 (its slot 3) a trap skill of the pit's payload (earth 30 to 60
guarded `BELOW_HALF`, Knocked down 2); Runt's caste skill 30 (its slot 2) a trap skill of earth 10 to 40 and Poison 4;
Hob's `ARMOR_VS` 9 against earth (type 7, bits 36–41); Runt's rank 6; skill 73, the rust (a hex holding `ARMOR` −20);
skill 74, a trap skill of earth 10 to 40 and Crippled 3 guarded `BELOW_HALF`.

**Track CV's surviving mutants of the trap port (#444), RV-03a2's rows.** By the mutant's name in
`client/sim/src/parity/mutants.test.ts`: the window's last position read as inside (`locate`): 64; a chunk column past
the location is in it: 65; a chunk row past the location is in it: 66 (and 67 on the bound); a tile West of the
location is in it: 68; a goblin placer's guards all held (`by_goblin`): 79 (not held) against 80; the target's
`ARMOR` effects ignored (`resolve`): 73, 75, 76; an expired effect still defends (`DefenceTrait::member`, `::goblin`):
74, 77 against 73, 76; an `ARMOR` effect not clamped at 0 (`DefenceTrait::add`): 75, 78; an entry's guard ignored
(`entries`): 81 (not held) against 82; a `HEAL` and a `CURE` entry apply nothing (`ops`): 83; a holding entry applies
nothing: 84; a dead goblin at 0 health killed again (`put`): 85; the kit, the rank and the level of another goblin's
caste, not the placer's (`by_goblin`, the `trap` mutants of `parity/trapcases.ts`): 86 (placer and entrant of distinct
castes, #440's review; the world's first goblin, 44, is the Hob). The entrant's `ARMOR_VS` against the trap's type: 69,
70; its armor terms (`DefenceTrait::member`'s armor, stance and enchanted sums, read only in a stance or enchanted):
71 against 72.

**The dead-entrant split cannot be built.** "An entrant killed by the hit takes the other entries (`trap`)" (the
mutant returning `true` from `ExecutorTrait::trap`) is equivalent on the trap path: `trigger` runs `entries` only when
`trap` returns the entrant alive (`types/executor.cairo` 2085–2086, `trap` returns `target.alive()` at 2115), and
`entries` checks the same `target.alive()` before every entry it applies (2327); no entry before it can kill (a
`HEAL`, a `CONDITION`, a `CURE`, an `ENERGY` or a holding entry lowers no health), so the two checks read the same
value and either masks the other. Rows 7 and 30 kill the two dropped together. `entries`' own check is pinned without
`trap`'s by the `act` rows, whose carriers reach it through `ExecutorTrait::on` (2123), which has no `trap` check.

## `body.jsonl`: the `Body` operations and the effect entry's (RV-03a, D-257)

Printed by `types::executor::tests::body::test_body_vectors_0` to `_6` (ids 0–51, 52–122, 123–172, 173–220,
221–311, 312–326, 327–333), split for snforge's step limit, each part with its digest. One line: `{"id", "fn", "case", "ok"}`, every
felt in hex (a negative integer `P − |v|`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content` (`body_content`): the fixtures' (`Fixture::
content`: the bar's skills 1–8 at positions 0–7, the castes' 24–31 at 8–15), with skill 1 of adrenaline cost 5 (a
member's cap: 20 quarters), skill 3 a stance whose `REGENERATION` line is 1 to 4, skill 4 a stance, skill 5 an
enchantment of −2 to −5 pips, skill 24 (Hob's slot 0) of cost 5 (Hob's cap, 20); the belt's potions 100 to 103 (pips
1, 3, −2, 0); the castes of armor 20, Hob's `ARMOR_VS` 5 against type 1 and 63 against type 9, Runt's 11 to 19 against types 1 to
9 (one a lane: added by the fix loop of #440, the only change to an earlier row). Every actor is loaded through
it (`MemberTrait::load`, `GoblinTrait::load`), its hot fields written back into its words (`store`).

**The actor** is `Unit`'s layout: `0` then a `Member`'s 35 fields, or `1` then a `Goblin`'s 21, each in its struct's
declaration order (`contracts/logic/src/models/index.cairo`): what `#[derive(Serde)]` would write (the structs derive
none). A `Member`: `status`, `health`, `energy`, `adrenaline`, `flags`, `act_slot`, `act_target`, `act_tile`,
`act_deadline`, `bleeding`, `poison`, `burning`, `knocked`, `effect_deadlines` (4), `effect_regen` (4, signed),
`max_health`, `max_energy`, `health_regen` (signed), `energy_regen`, `adrenaline_cap`, `bar_at`, `effect_at`, then
`words` (`MemberWords`: `state`, `timers`, `effects`, `recharges`, `stats`, `bar`, `kit`). A `Goblin`: `entity`,
`awake`, `ai`, `health`, `energy`, `adrenaline`, `caste`, `act_slot`, `act_target`, `act_deadline`, `bleeding`,
`poison`, `burning`, `knocked`, `effect_deadline`, `effect_regen` (signed), `max_health`, `caste_at`, `effect_at`,
`state`, `timers`. The operations run through `UnitBody` (the executor's dispatch, CBT-05a route (c)).

**`case`** is the actor, then the operation's arguments in its signature's order (the sheets are the content's);
**`ok`** a read's value, or a write's actor after:

| `fn` | arguments | `ok` |
|---|---|---|
| `health`, `max_health`, `is_member`, `alive`, `asleep`, `halves`, `enchant_percent`, `slots` | none | the value (a boolean 0 or 1) |
| `place` | none | `x`, `y`, `facing` |
| `knocked` | `t` | the boolean |
| `armor_vs` | the damage type | the armor |
| `infliction` | none | `Infliction`: `condition`, `percent`, `knockdown` |
| `effect` | the slot | `Held` (`carrier`, `potion`, `charges`, `deadline`, `rank`), then the carrier's position (`ABSENT`, `2^32 − 1`, for none) |
| `wound`, `heal` | the amount (`u16`) | the actor |
| `energize` | `v` in energy (`i32`; × 3 thirds) | the actor |
| `struck`, `landed`, `halved` | none | the actor |
| `inflict` | the condition 1–5, `v` (`i32`), the source's `Infliction`, `t` | the actor |
| `cure` | the condition, `t` | the actor |
| `hold` | `Held`, the carrier's position `at`, `stance`, `t` | the actor |
| `spend` | the slot, `t` | the actor |

The effect entry's rows (`types/effect.cairo`, `EntryTrait`), no actor:

| `fn` | `case` | `ok` |
|---|---|---|
| `line` | `v0`, `v12` (`i16`), the rank | `v0 + (v12 − v0) × rank / 12`, truncated toward zero (`i32`) |
| `value` | `Entry`, the rank | `value`: the line on its `v0`, `v12` |
| `duration` | `Entry`, the rank | the line on its `d0`, `d12` |
| `class` | the kind | `Option<KindClass>` (`[1]` none; `[0, c]`: 0 `Hit`, 1 `HitModifier`, 2 `Holding`, 3 `Instant`, 4 `Placement`), then `is_holding`, `is_hit_modifier` |
| `pack` | `Entry` | its 97 bits |
| `unpack` | the bits | `Entry` |

`Entry` is its `Serde`: `kind`, `param`, `v0`, `v12`, `d0`, `d12`, `charges`, `target`, `shape`, `filter`, `guard`,
`scope`.

The actors, unless a row says otherwise: the fixtures' member (health 400 of 480, energy 30 of 60 thirds, adrenaline
0 of its cap 20, no condition, no effect); goblin 264, a Hob (Engaged, health 100 of 280, energy 0 of 30 thirds,
adrenaline 0 of 20). `T`, the `t` of every operation that takes one, is 50.

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `health`, `max_health`, `is_member`, `place` (8) | 1–8 | one a kind; `place`: the member on (7, 9) facing 4, the goblin on (11, 3) facing 2 |
| `alive` (9) | 9–17 | a member inside at 1, at 0, down at 50, gone; a goblin Engaged at 1, at 0, Returning (the last state below `DEAD`), Dead at 50, Looted |
| `knocked` (6) | 18–23 | Knocked down to 50, at `t` 49, 50 (held: `t ≤ D`), 51; member, goblin |
| `asleep` (3) | 24–26 | a goblin asleep, on watch; a member |
| `halves` (4) | 27–30 | `HALVE_FIRST_HEAVY_HIT` held (`MemberKit` bit 202), spent (`HALVED`), not held; a goblin |
| `armor_vs` (10) | 31–40 | a member's per-type armors 5, 6, 7, 63 (types 1, 2, 3, 9: `MemberStats` 48, 54, 200, 236) at types 0, 1, 2, 3, 9, 10; the goblin's caste at 0, 1, 9, 10 |
| `infliction`, `enchant_percent` (4) | 41–44 | a member's kit (Burning 33 %, `KNOCKDOWN_FLAT` 1, `ENCHANT_DURATION` 15 %); a goblin's none |
| `slots`, `effect` (7) | 45–51 | 4 and 1; a member's slot holding skill 5 (2 charges, rank 12), an empty slot, a slot holding belt potion 2; the goblin holding skill 5, empty |
| `wound` (10) | 52–61 | 400 by 0, 399, 400, 401, 65,535; at 0 by 0; the goblin's 100 by 99, 100, 101; a dead goblin at 50 (no alive check) |
| `heal` (13) | 62–74 | 400 of 480 by 0, 79, 80, 81, 65,535; at the max by 1; at 0, down: nothing; the goblin to its max − 1, its max, past it; dead, at 0: nothing |
| `energize` (14) | 75–88 | the member's 30 of 60 thirds by 10 (exactly the max), 11, 9, 0, −10 (exactly 0), −11, −9; the goblin's 0 of 30 by 10, 11, 9, −1, and from 30 by −10, −11, −9 |
| `struck` (16) | 89–104 | a member: the `HIT` flag and 1 quarter from 0, at 0 health (the flag only), from 19 (to the cap), at 20, above it (25: kept), with `TURNED \| HIT` set; a goblin Engaged from 0, 19, 20, 21; asleep and on watch (engages); Alerted (stays); asleep at 0 health (nothing); dead (nothing); Returning |
| `landed` (15) | 105–119 | a member: 4 quarters with `ADRENALINE_EVERY_N` 0 (`MemberKit` 160–167: the `hits` counter, `MemberState` 112–119, stays 0); N 3 from `hits` 0, 1, 2 (the third: 8, the counter back to 0); N 1 (8 each); from 17 (+4 capped at 20) and 13 on the N-th (+8 capped); at the cap; at 0 health (no alive check). A goblin, 4 quarters capped at 20: from 0, 15, 16, 17, 20, 21 |
| `halved` (3) | 120–122 | a member's `HALVED` flag, already set; a goblin, nothing |
| `inflict` (50) | 123–172 | each condition 1–5 on each kind, the value 3: `D = 52` (123–132); the value's clamp on Bleeding, 0, −1, 1, 2, 32,767, 32,768 (133–144); the refresh by `max` over a later deadline (53: kept) and an earlier one (51), on Bleeding and on Crippled (in the timers word) (145–152); Knocked down (2: `D = 51`) interrupting an activation (the member's bar slot 1, recharge 12: `R = 61`; the goblin's caste slot 2), with none held and over a later one (60: kept, interrupted all the same); over an earlier one (50); a goblin recovering keeps its recovery (153–159); the source's `CONDITION_DURATION` Bleeding 33 % (10 → 13), on Poison (10), 49 % (14), 50 % (15), 63 % (capped at 50: 15), `KNOCKDOWN_FLAT` 3 on Knocked down (2 → 5), on Crippled (2), 4 (capped at 3), a goblin with Bleeding 33 % (160–168); not alive, through `apply` and through `knock` (169–172) |
| `cure` (19) | 173–191 | each condition held to 60 on each kind: to 49 (173–182); Bleeding to 50 (held at `T`: to 49), 48 (not held: kept), 0 (183–188); a member at 0, down, a dead goblin: nothing (189–191) |
| `hold` (22) | 192–213 | a member: skill 5 into slot 0; held in slot 0 to 60, again to 70 (replaced), 55 (kept), 60 at rank 0 (a tie: replaced); held to 49, lapsed (slot 0 free again); held to 50 (`T`: held), skill 6 takes slot 1; lapsed, skill 6 takes slot 0; spell 6 in slot 0 and stance 4 in slot 1: stance 3 takes slot 1, not as a stance slot 2; both lapsed: slot 0; every slot held (70, 55, 60, 55): the earliest, the lowest of the tie, slot 1; potion belt slot 1 held in slot 2 (the same item: slot 2); skill 1 held, potion 1 is not it (slot 1); not alive (192–205). A goblin's one slot: empty; held to 60, again to 55 (kept), 60 at rank 0 (replaced); held to 50, again to 49 (kept); held to 49, again to 40 (lapsed: replaced); skill 6 over it; a potion (never held); dead (206–213) |
| `spend` (7) | 214–220 | 2 charges to 1, 1 to 0 (the effect ending at `T − 1`), 0 (nothing), on a member's slot 0 and the goblin; a member's slot 3, the other slots' pips kept |
| `line` (36) | 221–256 | `(v0, v12)` (10, 40), (40, 10), (0, 7), (0, −7), (−32,768, 32,767), (32,767, −32,768), each at ranks 0, 1, 11, 12, 13, 15 |
| `value` (3) | 257–259 | earth 10 to 40 at rank 7; energy −5 to −17 at 7 and 15 |
| `duration` (16) | 260–275 | `(d0, d12)` (5, 17), (17, 5), (0, 43,688), (43,688, 0), each at ranks 0, 1, 12, 15 |
| `class` (26) | 276–301 | every kind 0–24, and 255 |
| `pack`, `unpack` (10) | 302–311 | each in turn on: the empty entry, earth 10 to 40, energy −5 to −17, every field at its layout's maximum (the durations at `MAX_BASE_DURATION`), `scope` alone |
| appended: `armor_vs` (12), `hold` (3) | 312–326 | RV-03a's fix loop 1 (the review of #440), after every earlier id: `armor_vs` on every lane, a member's per-type armors 5 to 12 and 63 (types 1 to 9) at types 4 to 8 (312–316), a Runt goblin (11 to 19) at types 2 to 8 (317–323); `hold`, belt potion 2 beside potion 1 held in slot 0 (not the same item: slot 1) (324); step 2's `!old.potion`, both sides: belt potion 3 held in slot 0 (its sheet at position 3, where stance 4 sits), stance 3 goes to slot 1 (325); stance 4 held in slot 0, stance 3 takes slot 0 (326) |
| appended: `hold` (2), `inflict` (5) | 327–333 | RV-03a2 (D-257), track CV's surviving mutants of the body port (#443), after every earlier id: `hold`'s step 1 at its bound, skill 5 held in slot 0 to `T` and held again to 60: the same carrier, slot 0 (327); step 1's potion compared by its item: belt slots 1 and 2 both holding item 101 (`MemberKit` 64–95), belt potion 1 held in slot 0, belt potion 2 (the sheet of item 101, position 1) held to 60: the same item, slot 0 (328); Knocked down interrupting the member's activation of bar slots 4, 5, 6 and 7 (spells of recharge 10: `R = T + 9`), every lane of the recharges word holding `40 + slot` before, the high limb's lanes (329–332); a goblin activating caste slot 3 (`LAST_SLOT`), knocked down: interrupted, its slot 3 recharging to `T + 19` (333) |

Per `fn`: `content` 1, `health` 2, `max_health` 2, `is_member` 2, `place` 2, `alive` 9, `knocked` 6, `asleep` 3,
`halves` 4, `armor_vs` 22, `infliction` 2, `enchant_percent` 2, `slots` 2, `effect` 5, `wound` 10, `heal` 13,
`energize` 14, `struck` 16, `landed` 15, `halved` 3, `inflict` 55, `cure` 19, `hold` 27, `spend` 7, `line` 36,
`value` 3, `duration` 16, `class` 26, `pack` 5, `unpack` 5.

**The inventory** (what the earlier tables already pin of these operations). `hit.jsonl` pins `HitTrait::resolve`,
which reads `knocked`, `asleep`, `halves`, `armor_vs` and the target's health as inputs, but no `Body` function
itself. `segment.jsonl` calls no class. `segment2.jsonl` reaches `wound`, `struck`, `landed`, `energize`, `inflict`,
`hold` and the trap's trigger inside `ActionLibrary`, `TickLibrary` and `TrapLibrary` calls whose results it records:
a mirror replaying it takes those results and runs none of these operations. So no table pinned any of them as a port,
and every one is vectored here. Two are not: `defence` and `offence` build a hit's `Defence` and `Offence` from the
executor's `Context`, its lever and its cache, the carrier's side of a hit, and go with `act` (RV-03b). Adrenaline's
decay is not a `Body` operation: it is the tick's step 3 (`MemberTickTrait::regenerate`, `GoblinTickTrait::
regenerate`, D-157 E), RV-03c's (`ticks`); `segment2.jsonl`'s fast path reaches it only on the member. The entry's
checks (`EntryAssertTrait`: `assert_valid`, `assert_legal`, `assert_carrier`) panic and run in the content pipeline,
not in play: they are not vectored (`pack`'s rows are valid entries).

**How the rows are sized for mutants** (as `hit.jsonl`): for every comparison, a row on each side of its bound and, for
`≥` against `>`, on it (`wound`'s `damage ≥ health` at health − 1, health, health + 1; `heal`'s max at max − 1, max,
max + 1; `energize`'s clamp exactly at 0 and the max and one past each; `knocked`'s `t ≤ D` at `D − 1`, `D`, `D + 1`;
the adrenaline caps from cap − 1, cap, cap + 1; the `hits` counter reaching `N`; the refresh's `max` over an earlier
and a later deadline (an equal one would hide a mutant `≥`/`>`: both give the same deadline); `cure`'s `old ≥ t` at
`T` and below; `hold`'s `deadline ≥ t` at `T − 1` and `T`, and its tie; the value's clamp at 0, 1, 2 and 32,767,
32,768; the percent's cap at 49, 50, 63). For every arithmetic step, a row whose result tells the operator apart
(`line`'s truncation toward zero on a negative slope at rank 1 and 11; `refreshed`'s `t0 + d − 1`; `spend`'s
`t − 1`; the thirds of `energize`). Each kind has its own rows wherever its code differs (a member's `alive` reads its
status, a goblin's its AI state; a goblin's `heal` and `cure` guard on alive, a member's `wound` and `landed` do not;
Crippled lives in the timers word). Each branch of a dispatch has a row (each condition 1–5, each `KindClass`, every
step of §5.7's slot choice). Track CV names further cases for surviving mutants; they are appended, as `hit.jsonl`'s.

**Track CV's surviving mutants of the body port (#443), RV-03a2's rows.** By the mutant's name in
`client/sim/src/parity/mutants.test.ts`: `hold`'s step 1, a carrier held to `t` not held (`deadline > t`): 327 (it
would go to slot 1); a potion the same by its belt slot, not its item: 328 (slot 1); `recharge_at`'s high limb (bar
slots 4–7): 329–332; a goblin's interrupt ignoring caste slot 3 (`LAST_SLOT`, `>` against `≥`): 333.

## `hit.jsonl`: one hit (CBT-03a)

Printed by `types::hit::tests::test_vectors_0` to `test_vectors_4` (ids 0–40, 41–81, 82–122, 123–163, 164–202; FND-23), each part with its digest. One line: `{"id", "case", "ok"}`.
The case is the `Serde` of `(Hit, HitTarget)`, 28 felts, and `ok` the `Serde` of `HitOutcome`
(1 felt for a stopped hit, 4 for a landed one); the order and meaning of every felt are in the
module's header, `contracts/logic/src/types/hit.cairo`. A negative integer is `P − |v|`.

The cases: the hand-written edges (each rule of design/19 §5.4–§5.6 and §6 at its bounds), then
seeded cases over every input.

**Moved by CBT-05a (D-179).** A sleeping target neither blocks nor evades its first hit. One edge
was added, id 6: `(sword, asleep + evade)`, which lands critical (`[3, 140, 1, 0]`) where the old
rule evaded it. Every later case moved up one id, and the table, 200 cases, lost its last seeded
case. No case kept from before changed its outcome (checked against `origin/main`'s table).

**Added by CBT-05a for track CV** (their mutation check of the mirror): three hand-picked cases after
the seeded ones, so no earlier id moved, the table now 203 cases:
- id 200: an axe hit from the front-side arc, landing below the clamp (no axe bonus);
- id 201: the `ABOVE_HALF` damage passive at exactly half health, with a percent of 20 (it does not
  apply);
- id 202: FX-19's halving when the hit leaves the target at exactly half (300 − 60 = 240 of 480:
  not halved).

## `fate.jsonl`: the Fate derivations (VEC-01)

Printed by `fate::tests::test_vectors` (ids 0–226), one part, with its digest. ENG-05 added the
`REVEAL` purpose (index 8): its `purpose` row and its 8 `domain` rows are new, every other row is
unchanged and the ids after them moved by up to 9.

One line: `{"id", "fn", "case", "ok"}`, every felt in hex (a `u32` index is a felt below 2^32).
Poseidon is `core::poseidon::poseidon_hash_span`, the hash of the Starknet `poseidon` builtin.

| `fn` | `case` | `ok` |
|---|---|---|
| `purpose` | the index in `PURPOSES` (0 `ENTRY` … 7 `RIFT_BOARD`, 8 `REVEAL`) | the purpose's felt (a short string, e.g. `'fate:entry'`) |
| `domain` | `subject`, `counter`, `purpose` | `fate::domain`: `poseidon(subject, counter, purpose)` |
| `derive` | `word`, `domain`, `index` | `fate::derive`: `poseidon(word, domain, index)` |

The cases (227):
- `purpose`: the 9 purposes.
- `domain` (128): each purpose over 8 pairs `(subject, counter)` — zeros, one on either side, `P − 1` for both, 2^128 with 2^64, a small pair, 2^250 with 2^32, a `u32` maximum counter; then 8 subjects × 7 counters (0, 1, 2, 255, 2^32, 2^64, `P − 1`) under `ENTRY`. `P − 1` is `0x800000000000011000000000000000000000000000000000000000000000000`.
- `derive` (90): 5 words (0, 1, a small one, 2^128, `P − 1`) × 3 domains (0, `domain(1, 0, ENTRY)`, `P − 1`) × 6 indices (0, 1, 7, 255, 65535, `u32::MAX`).

## `packing.jsonl`: the packing of records into a felt (VEC-01)

Printed by `packing::tests::test_vectors` (ids 0–519), one part, with its digest.

One line: `{"id", "fn", "case", "ok"}`, every felt in hex. A `u128` limb or a field is its value. A
struct is its `Serde` (`Lanes32`: seven felts, `Lanes16`: fifteen, `Counter`: one, `Bitmap`: one).

A function that refuses has its outcome as `[0, result…]` for accepted and `[1]` for refused (the
`Option` form of the window's `arc`). A panic cannot be caught in a test: a refused row is the
function's guard evaluated by the test (`high < LIVE_HIGH`, `value < size`, `bits` below bit 250),
and the panics themselves are asserted by `tests/test_packing.cairo`. A mirror must refuse on the
same rows and never write the word.

| `fn` | `case` | `ok` |
|---|---|---|
| `split` | `word` | `[low, high]`, `LIVE` removed from the high limb if set (any word, 0 and `P − 1` included) |
| `limbs` | `word` | `[low, high]` of a word that carries `LIVE`; the row of word 0 is outside the contract (the subtraction wraps) |
| `join` | `low`, `high` | `[0, word]`, or `[1]` when `high ≥ 2^122` |
| `peel` | `rest`, `size` (a power of two) | `[value, rest]` after the low field is removed |
| `fits` | `value`, `size` | `[0]` accepted, `[1]` refused (`value ≥ size`) |
| `field` | `limb`, `shift`, `size` | the field at `shift` of width `size` |
| `byte_at`, `u16_at`, `u32_at` | `limb`, `shift` | the byte, `u16`, `u32` at `shift` |
| `low_field` | `limb`, `size` | the low field of width `size` |
| `pack_lanes32`, `pack_lanes16` | the lanes | the word (`LIVE` set) |
| `unpack_lanes32`, `unpack_lanes16` | `word` | the lanes (a word without `LIVE` decodes by `split`) |
| `pack_counter` | `value` (`u64`) | the word |
| `unpack_counter` | `word` | the `u64` |
| `pack_bitmap` | `bits` | `[0, word]`, or `[1]` when `bits ≥ 2^250` |
| `unpack_bitmap` | `word` | the bits |

The cases (520): `split` 14 and `limbs` 8, edges of the limbs, of `LIVE` and of the field; `join` 56
(7 low limbs × 8 high limbs, around 2^122); `peel` 70 (10 widths × 7 limbs); `fits` 30 (5 sizes ×
6 values around the size); `field` 56, `byte_at` 28, `u16_at` 28, `u32_at` 28, `low_field` 35 (7
limbs from 0 to `u128::MAX`, shifts across both halves of the limb); the lanes: zeros, ones,
maxima, ascending, and one lane set at a time (`pack` and `unpack` rows, 126 in all, and the
words without `LIVE`); `Counter` from 0 to `u64::MAX`; `Bitmap` around bit 250 and `P − 1`.

## `reveal.jsonl`: the chunk reveal (ENG-05)

Printed by `types::reveal::tests::test_vectors` (ids 0–170), `test_vectors_1` (171–185),
`test_vectors_2` (186–196), `test_vectors_3` (197–207) and `test_vectors_4` (208–213), split for
snforge's step limit, each part with its digest (`PART_1` to `PART_4` are the first ids of the later
parts).

One line: `{"id", "fn", "case", "ok"}`, every felt in hex. A struct, an `Option`, a tuple or a
`Span` is its Cairo `Serde` (a span: its length, then its elements; an `Option`: `0` then the
value for `Some`, `1` for `None`; an `i8` as a felt, `-1` as `P − 1`).

| `fn` | `case` | `ok` |
|---|---|---|
| `word` | `entropy`, `instance_id`, `chunk` | `EntropyTrait::word`: `derive(entropy, domain(instance_id, chunk, REVEAL), 0)` |
| `feed` | `entropy`, then a fact's three felts (a tag, two values) | `EntropyTrait::feed(entropy, fact)`: `entropy + poseidon(fact)` (no reveal feeds the entropy: audit #348, major 1) |
| `base` | `word`, `biome` (1 meadow … 4 ruin) | `BoardTrait::base`: the base's floor bitmap (1 = floor, interior only) |
| `sight` | `x`, `y`, `width`, `height` (a global tile, a location in chunks) | `SightTrait::chunks`: the chunks within 6, the tile's own first, then by index |
| `member` | `tile`, `k` (0–18), `odd` (the tile's global row parity) | `PackPlacementTrait::member`: `Option<u8>`, the chunk's tile at `OFFSETS[k]` |
| `reveal` | `Site` (ENG-10b: with `west` and `north` after `chunk_set`, a dungeon's open seams; 0 in a zone), `Progress`, `instance_id`, `known` (`Span<(u8, Terrain)>`; in a dungeon every revealed chunk), `chunks` (`Span<u8>`) | `RevealTrait::reveal`: the `Progress` after, then the chunks revealed, `Span<Revealed>` (chunk, `Terrain` (walls 1 = wall, edges), `Features` (2 `PackPlacement`, 3 `Object`, `touched`)) |

`reveal` covers every computation the client repeats: the chunk's word, the base, the smoothing with
the margins (`hexx`'s `CaverTrait::smooth`, B4/S2, one generation), the ring's decisions and
openings (a dungeon side's from its seam's stream, D-224), the lines to the spine, the cut,
`keep_component`, the quotas' draws, the bands and the placement (the draws of `hexx`'s `RngTrait`
from `mix(word, k)`: 2 quotas, 3 placement, 4 the ring), and the progress (revealed set, count, open
edges, quotas left; the entropy unchanged).

The cases (214): `word` 18, `feed` 15, `base` 12, `sight` 14, `member` 115, `reveal` 40.
- `word` (18): 3 entropies (0, a short string, `P − 1`) × 2 instance ids × 3 chunks (0, 112, 224);
  `feed` (15): the 3 entropies × 5 facts `('fact:test', 17, s)`; `base` (12): 3 words × the 4 biomes;
  `sight` (12 in part 0, 2 in part 3): corners, sides, centres and edges of chunks in a 15 × 15
  location; `member` (114 in part 0, 1 in part 3): the 19 offsets from tiles 112, 97 and 16, both
  parities.
- `reveal`, part 1 (15): each biome on a 3 × 3 zone, chunk 16 (an odd chunk row) with nothing known,
  then chunk 1 (an even one) knowing it; chunk 16 of a forest after its South, East, West and North
  neighbours one at a time (1 to 4 sides known); the edge of a 2 × 2 zone whose chunk (1, 1) is
  outside the outline, an anchor on the East side (three chunks asked, the void one skipped); a
  ruin's chunk cut by a tile mask (columns 0–11), then its neighbour.
- `reveal`, part 2 (11): a cave dungeon floor of `N` 6 entered at chunk 112, its outline drawn at
  `create` (ENG-10b: `Site`'s `chunk_set`, `west` and `north`, every chunk's mask with its hosts
  above the board), revealed whole by index, with an exit and a vein quota; a 2 × 2 meadow with a
  collector, two landmarks, a Heart and a task's landmark, revealed whole (every quota placed); a
  set piece laid by quota, then its neighbour. ENG-05c: case 196 (the neighbour) is now revealed
  with the set piece's host drawn (bit 225 of its mask), so that its piece is laid.
- Part 3 (11, ENG-05c, track CV's surviving mutants of CLI-02b): `sight` from (12, 9) and (0, 9)
  (197, 198); `member` (13, 11, even) (199); `reveal` of a chunk asked twice in one call (200), an
  anchor on a corner (201), an interior anchor off the spine (tile 48) in a cave with a spawn of
  density 255 (202) and in a ruin whose mask keeps columns 0–5, its centre cut, the flood from the
  anchor and a pocket outside its component dropped (203: ENG-05's `pow(tile) + anchor_line(tile)`
  carried and gave another terrain), a set piece on an odd chunk row
  (204), pack templates of minimum 0 and maximum above 5 (205), a Heart of offset 0 hosted below the
  band's top (206), a spawn roll equal to the density (207).
- Part 4 (6, ENG-05c): a cave dungeon floor of `N` 6 (entropy 15) whose outline holds two
  neighbouring chunks with their seam closed, revealed whole by decreasing index (208–213).


## `act.jsonl`: the adventurer's action, `ActionTrait::act` (RV-03b, D-257)

Printed by `types::action::tests::vectors::test_act_vectors_0` to `_14` (ids 0–26, 27–42, 43–69, 70–94, 95–106,
107–127, 128–143, 144–157, 158–176, 177–204, 205–214, 215–222, 223–231, 232–238, 239–243), split for snforge's step
limit, each part with its digest. Where
`segment2.jsonl` records the action class's result for a replay, this table tests a port of the class itself: each
`act` row is one call of `ActionLibrary::act` (the real class, declared in the test), which loads the words through
the content, runs `ActionTrait::act` for member 0 with `Delegate` rules whose carrier runs through the real
`ExecutorLibrary` (also declared), and returns the words stored back, the ground and the tick cost, or, on a refusal,
the words as they came, the ground and the `Illegal`. One line: `{"id", "fn", "case", "ok"}`, every felt in hex,
every value its Cairo `Serde` (as `segment2.jsonl`; a negative integer `P − |v|`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content` (`act_content`): the action unit tests'
(`types::action::tests::bench`, with skill 1 (position 0) made a glyph of `NEXT_SPELL_COST` 2 and skill 2 (position 1)
an enchantment, where the held potions' positions fall, so that a potion read as the skill at its position is seen: the executor tests' `content(40, …)`, castes of armor 40 and a sword of 30 at rank
12, Snare 45 at 10 energy, activation 2, recharge 20; skill 60 a glyph, `NEXT_SPELL_COST` 4 for 10 ticks; 61 a fire
spell, 5 energy, activation 3, range 6, fire 40 on a foe; 62 a Warden skill, 8 energy, profession 2, instant, a heal
of 10 on `SELF`; 63 a stance, instant; 64 an attack skill of 2 adrenaline strikes, activation 0; 65 an instant heal
of 10 on an ally, range 6), with: 66 an instant trap skill (range 3, `TRAP` then earth 10 to 40); 67 the same, its
`TRAP` entry guarded `BELOW_HALF`; 68 a hex of activation 1 (range 6, fire 40); 69 an enchantment on `SELF` of
activation 2; 70 an attack skill of activation 2, 5 energy and 1 strike; 71 an instant spell (range 6, fire 40); 72
a glyph whose `NEXT_SPELL_COST` is 1 to 13 with the rank; 73 an enchantment holding `PENETRATION` 20 of scope
`WEAPON`; 74 a stance holding `PENETRATION` 150 of scope `SPELL`; 75 a hex holding `ARMOR` −20; 76 an enchantment
holding `ARMOR` 300. Its potions: 100 the bomb (fire 30 on `DISC_1`
around a tile, range 6, strength 30), 101 a draught (a heal of 25 on `SELF`), 102 a dart (20 piercing on a foe,
range 4, strength 45), and a sheet of id 0, which no belt slot names (an empty slot never takes it). Every actor is
loaded through it.

**`act`**: `case` the call's arguments but the content and the executor's class: the `Words` (`clock`, the members'
`MemberWords`, the goblins' `GoblinWords`, `killed`, `defeated`), the `Board` (`window`'s one felt, `x`, `y`: the
origin plus 15, D-134), the ground (`Array<(u8, Features)>`), the `Action` (`Move(d)` `0, d`; `Turn(d)` `1, d`;
`Wait` `2`; `Attack(e)` `3, e`; `Skill((slot, target))` `4, slot, t, v` with `t` 0 an entity, 1 a tile `x + 256 y`;
`Item((slot, a))` `5, slot, a`; `Interact(tile)` `6, tile`). `ok` what it returns: the `Words`, the ground (a trap
placed is a `PLACED_TRAP` object, `param` its placer), then the `Result<u8, Illegal>`: `0, ticks`, or `1, i` with `i`
the variant (0 `Clock`, 1 `Absent`, 2 `Knocked`, 3 `Turned`, 4 `Instant`, 5 `Empty`, 6 `Belt`, 7 `Recharging`, 8
`Energy`, 9 `Adrenaline`, 10 `Target`, 11 `Reach`, 12 `Trap`, 13 `Kind`, 14 `Blocked`). On a refusal the words and
the ground are the case's, felt for felt (every one of the 78 refusals here).

**`defence`**: `Body::defence` through `UnitBody` (the executor's dispatch), the lever `Levered` with a fresh `Cache`
(a member as member 0). `case` the actor, then `t`; `ok` its `Defence` (`armor` signed, `effects`, `stance` and
`enchanted` signed, `in_stance`, `is_enchanted`, `block`, `block_slot`, `evade`). **`offence`**: `Body::offence`
the same way. `case` the actor, the `HitClass` (0 `Weapon`, 1 `Spell`, 2 `Item`, 3 `Trap`), the `Entry` (its
`Serde`, as `body.jsonl`), `bonus` (`u32`), `penetration` (`u16`), then the `Context`'s fields in order: `rank`, the
`Infliction` (`condition`, `percent`, `knockdown`), `enchant`, `skill_kind`, `carrier`, `potion`, `at` (`ABSENT`,
`2^32 − 1`, for a weapon), `scope`, `t`; `ok` the `Offence`'s fields in order: `class`, `weapon`, `melee`,
`strength`, `base`, `percent` and `above` (signed), `penetration`, `damage_type`, `steal`, `energy`. The actor in both
is `0` then its `MemberWords`, or `1` then its `GoblinWords`, loaded through the content (`MemberTrait::load`,
`GoblinTrait::load`).

The world, unless a row says otherwise: the clock 200; the adventurer, member 0 on (7, 7) (window position 112)
facing 0, level 20, health 400 of 480, 30 energy thirds of 60, adrenaline 0, its sword (damage 27, range 1, `k` 0:
1 tick, strength 60, slashing), its bar the row's skills from slot 0 at rank 12 and the fixtures' 1–8 after, its belt
items 100–103 at count 0; goblin 8, a Hob of health 100, adjacent East (position 113). The board is the open window
at the origin, the ground chunk 0 empty. A dead goblin is at health 0 and in AI state `DEAD`, but in 217–222, dead by
one field only (a state play never makes: those rows pin the port, which reads liveness from the AI state where the
class does, `TrapTrait::occupied`, and from health where it does, `locate` reading both); a second member is the
executor tests' member.

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `act`, the preamble (26) | 1–26 | Wait (1 tick, nothing written) (1); at `LAST_TICK` legal, past it `Clock` (2, 3); dead past it, `Clock` first (4); `Absent` at 0 health, legal at 1, `Absent` down and gone above 0 (5–8); at 0 and knocked down, `Absent` first (9); knocked down to `c` (lapsed at `t₀ = c + 1`: legal), to `c + 1` and `c + 2`, `Knocked` (10–12); knocked down: Wait legal, Turn, Skill, Item, Move and Interact `Knocked` (13–18); Turn to 0, 5 (the last direction) and to the facing it has: 0 ticks, the facing and `TURNED` set (19–21); with `TURNED`, `Turned` (22); with `INSTANT` only, legal (23); Wait with both flags, legal (24); Move and Interact, `Kind` (the segment's) (25, 26) |
| `act`, Attack (16) | 27–42 | the sword on goblin 8, adjacent East (lands now, the member turned toward it), on goblin 11 a row up (27, 28); goblin 9 at 2, `Reach` (29); a dead goblin, an entity no actor holds (77), the member itself (0), member 1 of a world of one, entity 7, a living member adjacent: `Target` (30–35); `k` 2 and 255 (`MemberStats` 104–111) (36, 37); a range of 3 (`MemberStats` 112): a goblin at 3 legal, at 4 `Reach`, at 3 behind a wall at 2 `Reach`, at 3 outside the window (the board's origin at (5, 0)) `Reach` (38–41); from facing 4 at `LAST_TICK` (42) |
| `act`, the skill's refusals (27) | 43–69 | each in `act`'s order at its bound, and the one before it winning: `Empty` (bar slot 0 of id 0; slot 7 holding the stance, legal; emptied; emptied with its weapon-required bit) (43–46); `Kind` (the attack skill with its slot's bit, `MemberStats` 40 + slot; with slot 1's bit only, legal; with the bit and recharging, `Kind` first; the stance with its bit, legal) (47–50); `Instant` (the stance and the instant spell with `INSTANT`; the spell of activation 3 and the attack skill of activation 0 with it, legal; the stance with `TURNED`, legal; with `INSTANT` and recharging, `Instant` first) (51–56); `Recharging` (`R = c + 1` refused, `R = c` legal; the attack skill recharging and short of adrenaline, `Recharging` first) (57–59); `Adrenaline` (2 strikes, 8 quarters: 7 refused, 8 and 9 legal; the attack skill of activation 2 short of both, `Adrenaline` first, of energy only, of neither) (60–65); `Energy` (the fire spell's 5, 15 thirds: 14 refused, 15 legal; short and aimed at no actor, `Energy` first; aimed at no actor, `Target`) (66–69) |
| `act`, the aim (25) | 70–94 | the fire spell (`FOE`, range 6): a goblin at 6 (started: activation 3, `A = c + 3`, its target the entity), at 7 `Reach`, a dead one, the member, a tile `Target`, behind a wall `Reach` (70–75); the ally heal (`ALLY`, range 6, instant): the member itself; member 1 at 6 (legal), at 7 (`Reach`), at 0 health, a goblin, a tile, member 1 of a world of one (`Target`) (76–82); `SELF` (the stance): a goblin, no actor, a tile, all legal, the facing kept (83–85); the enchantment on `SELF` of activation 2 on a tile (`act_tile` 1, its target the member) and on an entity (86, 87); Snare (`TILE`, range 3, activation 2): an empty tile at 3 (started, `act_tile` 1, its target the tile), at 4 `Reach`, an entity `Target`, goblin 8's tile and the member's own `Trap`, a dead goblin's (legal), a walled tile `Reach` (88–94) |
| `act`, the trap's tile (12) | 95–106 | the instant trap on position 114 (chunk 0's tile 114): the ground's chunk 0 empty (index 0 written), a chest elsewhere at 0 (index 1), a used trap on the tile at 0 (index 0) (95–97); a chest on the tile, an unused trap on it, three objects elsewhere `Trap` (98–100); chunk 0 the ground's second entry (101); no chunk 0, `Trap` (102); the board's origin at (5, 0), the trap on (16, 7), chunk 1's tile 106 (103); the guarded trap (`BELOW_HALF` on the placer, health × 2 < 480): at 400 and 240 nothing placed (legal, 0 ticks, its recharge spent), at 239 placed (104–106) |
| `act`, the energy (21) | 107–127 | the Warden skill (8 energy): a Warden primary (`MemberStats` 72) of rank 12 at 0 energy (floored: free), rank 8 (8 − 8: free), rank 7 at 2 thirds (`Energy`) and at 3; a primary 1 of rank 12 at 23 thirds (`Energy`) and 24; a Warden of rank 12 casting the fire spell at 14 (`Energy`) and 15 (no *Fieldcraft*) (107–114); the glyph (4) held in effect slot 0 to `c + 1` (the fire spell's 5 − 4, 3 thirds: legal, the glyph consumed, `D = c`), to `c` (lapsed: `Energy`) (115, 116); with the glyph held: the Warden skill (not a spell: kept), the hex, the enchantment, the instant spell (consumed) (117–120); the rune (1 + rank) on the fire spell: rank 0 at 11 and 12 thirds, rank 3 at 3, rank 4 and 12 at 0 (121–125); a potion held (belt slot 0: its position is skill 1's, a glyph here): not a glyph, kept, the full 15 thirds (126); two glyphs (slots 0 and 2: 4 + 1, both consumed), the stance (slot 1) and a potion (slot 3) held and kept (127) |
| `act`, quick cast and the tick cost (16) | 128–143 | pair 0 (`MemberBar` 208–219) of N 5, pair 1 (220–231) of N 2, bar slot 0's pairs (`MemberStats` 168, 169), the counters (`MemberState` `casts`, `casts_2`). The fire spell (activation 3): pair 0 at 4 (its bonus: activation 2, the counter 0), at 3 (to 4, activation 3), N 0 (kept), the slot not counting (kept), pair 1 at 1 (its bonus), both (bonuses 2: activation 1) (128–133); the hex (activation 1) with one bonus and with two: kept at 1 (`quick ≥ n`) (134, 135); the enchantment (activation 2) with two: 1 (136); Snare (a trap, not a spell) and the instant spell (activation 0): no count (137, 138); the attack skill of activation 2 (`max(k, n)`, FX-5) at `k` 1, 2, 3 (139–141); the attack skill of activation 0 at `k` 2 (lands now, `k` ticks, its recharge from `c + 1`, `INSTANT` not set), the instant spell (lands now, 0 ticks, `INSTANT`, its recharge) (142, 143) |
| `act`, Item (14) | 144–157 | the bomb (belt slot 0, `TILE`, range 6, `DISC_1`): count 1 (to 0, both goblins on the disc hit, the member turned toward the tile), 2 (to 1), 0 (`Belt`); a tile at 6 (legal), at 7 and behind a wall (`Reach`) (144–149); belt slot 3, item 103, which the content lacks: count 1 and 0 (`Empty` first); slot 0's item 0 (the potion of id 0 not taken): `Empty` (150–152); the draught (slot 1, `SELF`): healed 25, the facing kept, any address (153); the dart (slot 2, `FOE`, range 4): a goblin at 4 (legal), at 5 (`Reach`), the member (`Target`), a tile's value read as an entity (`Target`) (154–157) |
| `defence` (19) | 158–176 | a member: none held; its armor (`MemberBar` 232–247, −7) and guarded sums (`MemberKit` 184–191 in a stance 4, 192–199 enchanted −3); the shield (`ARMOR` 30, an enchantment) to `t` (held) and `t − 1` (lapsed); in two slots (summed); a potion held (neither stance nor enchanted); each `ARMOR` clamped to 0…255: the rust (−20: 0, a hex: neither stance nor enchanted), the bulwark (300: 255), both with the shield (285); Brace (`BLOCK`, a stance) with 2 charges in slot 2; 0 charges in slot 1 and 3 in slot 3 (the first with charges); 1 in slot 0 and 3 in slot 2 (the lowest slot); Sidestep (`EVADE`) (158–170). A goblin (its caste's armor 40): none; the shield to `t`, to `t − 1`; the rust (0); Brace; Sidestep (171–176) |
| `offence` (28) | 177–204 | the member's sword, a plain weapon hit (scope 0): bonus 0, 5, 255; its requirement not met (`MemberStats` 176); a range of 3 (not melee); `LIFE_STEAL_ON_HIT` 3 and `ENERGY_ON_HIT` 2 (`MemberKit` 128, 136) (177–182); the passives (`MemberBar` 136, 160, 184 for scope 0: +10, −5, 3; 144, 168, 192 for 1: 20, 6, 4; 152, 176, 200 for 2: −30, 7, 5) and the call's penetration 7: a plain weapon hit, an attack skill (`Weapon`, scope 1), the fire entry (40 to 70) as a spell at ranks 0, 6, 12 (level 20: strength 60), a bomb (`Item`, scope 3: the potion's strength 30, no passives), a trap (`Trap`, scope 3), a cold entry of −20 (its base clamped to 0) (183–190); the edge (`PENETRATION` 20, `WEAPON`) and the focus (150 clamped to 100, `SPELL`) held to `t`: scopes 0, 1, 2, 3 (191–194); to `t − 1`: none (195–198); a goblin (a Hob of caste rank 12, a sword of 30, range 1, slashing, level 10): its weapon hit at bonus 0 and 5, a spell, a trap; holding the edge: its weapon hit, a spell (199–204) |
| `act`, the struck target (10) | 205–214 | appended for track CV's trap port (#444): the sword on goblin 8 holding Brace (`BLOCK`), the member in its front arc (facing 0): blocked, 2 charges to 1, 1 to 0 (the effect ends) (205, 206); the member behind it (facing 3): landed, the charges kept (207); the attack skill: blocked, a charge spent (208); knocked down to `t₀ = c + 1` (held: landed, not blocked) and to `c` (lapsed: blocked) (209, 210); asleep (its first hit neither blocked nor evaded, D-179: landed) and on watch (blocked) (211, 212); 63 charges (the cap, `MAX_BLOCK`: blocked, to 62) and 62 (to 61) (213, 214) |
| `act`, the bar rank and one-field deaths (8) | 215–222 | appended for #447's review: the rune (instant, `SELF`) on bar slot 2 at ranks 3 and 9 (slot 0 at 12), held at the slot's rank, the rank the carrier takes (`Carrier::Skill((at, member.rank(slot)))`) (215, 216); goblin 8 dead by one field only, at health 0 and Engaged (217–219), at health 100 and `DEAD` (220–222): the sword (`Target`: `locate` reads both), the instant trap on its tile (`TrapTrait::occupied` reads the AI state), the bomb on its tile (count 1) |
| `content` (1) | 223 | RV-03a2 (D-257), after every earlier id: the content of rows 223–243 (below) |
| `act`, by slot, a negative glyph, the attack skill's terms (8) | 224–231 | the attack skill (2 strikes, 8 quarters) on bar slot 1 with slot 0's weapon-required bit only (`MemberStats` 40): legal (224); with slot 1's (41): `Kind` (225); a glyph of −2 (skill 77) held in effect slot 0 to `c + 5`: the fire spell costs its full 15 thirds, the glyph consumed (`D = c`) (226); the fire spell on bar slot 1 counting for pair 0 (`MemberStats` 170; pair 0 of N 5, its counter at 4): the bonus, activation 2 (227); the attack skill (scope 1) with the passives of every scope (`MemberBar` 136–200, as 183–190) on goblin 8 (228); holding the edge (`PENETRATION` 20, `WEAPON`) (229); skill 78 (`ATTACK_BONUS` 10) and skill 85 (`HIT_PENETRATION` 50), attack skills of activation 0, on goblin 8 (armor 40) (230, 231) |
| `act`, the source's side of a hit (7) | 232–238 | holding skill 79 (`PENETRATION` 30 of scope `ALL`) in effect slot 2: the bomb (count 1) on goblin 8's tile (scope 3: none taken) (232), the sword (taken) (233), the instant spell (taken) (234); the sword holding skill 80 (`ON_ATTACK_CONDITION` Poison 4) in slot 0: goblin 8 poisoned to 204 (235); with skill 81 (`ON_ATTACK_CONDITION` Bleeding 6, 2 charges) in slot 1 beside it: both applied, the charge spent (2 to 1) (236); `LIFE_STEAL_ON_HIT` 3 (`MemberKit` 128), the member at 400 of 480: 403 (237); `ENERGY_ON_HIT` 2 (136), at 30 thirds: 36 (238) |
| `act`, the target sets (5) | 239–243 | skill 82 (fire 40 on `DISC_1` around the member, filter `ALLIES`) with member 1 West of it (111): member 1 hit (400 → 287, `HIT`), the member not (239); member 1 there at 0 health: no candidate, nothing (240); skill 83 (fire 40 on a `SINGLE` `TILE`) on goblin 8's tile: hit (241); the bomb (count 1) on 113, goblin 8 on 114 and goblin 9 on 113, both at 1 health: killed 9 then 8, ascending position, not index order (242); skill 84 (fire 40 on a foe, Burning 3 on `DISC_1` around it) on goblin 8 (113), goblin 9 on 114: 9 burns, not hit (243) |

Per `fn`: `content` 2, `act` 195, `defence` 19, `offence` 28.

**Row 223** (RV-03a2): every row from 223 on reads the content of row 223, the last `content` row before it; rows
1–222 read row 0's. It is row 0's with skills 77–85 appended, every one instant (activation 0) and free: 77 a glyph of
`NEXT_SPELL_COST` −2; 78 an attack skill holding `ATTACK_BONUS` 10; 79 an enchantment holding `PENETRATION` 30 of scope
`ALL`; 80 a preparation holding `ON_ATTACK_CONDITION` Poison 4; 81 one holding `ON_ATTACK_CONDITION` Bleeding 6 with 2
charges; 82 a spell of fire 40 on `DISC_1` around its source, filter `ALLIES`; 83 a spell of fire 40 on a `SINGLE`
`TILE` (range 6); 84 a spell of fire 40 on a foe and Burning 3 on `DISC_1` around it (range 6); 85 an attack skill
holding `HIT_PENETRATION` 50 (row 0's skill 49 holds one too, but at activation 1: it would not land in the action).
None mixes `TILE` with `FOE` or `ALLY` (D-271).

**Track CV's surviving mutants of the act port (#450), RV-03a2's rows.** By the mutant's name in
`client/sim/src/parity/mutants.test.ts`: the weapon-required bit of slot 0 read for every slot: 224, 225; a negative
`NEXT_SPELL_COST` added (`glyphs`): 226; a slot's pairs one bit a slot (`quick_cast_matches`): 227; an attack skill's
scope a spell's (`read`): 228, 229; `ATTACK_BONUS` ignored (`modifiers`): 230; `HIT_PENETRATION` ignored: 231; an
effect of `ALL` not taken: 233, 234; an
`ON_ATTACK_CONDITION` not gathered (`attack`): 235, 236 (and the charge spent on a landed hit); `LIFE_STEAL_ON_HIT`
ignored (`on`): 237; `ENERGY_ON_HIT` not gained (`run`): 238; a dead
member a candidate of a wide carrier: 240 (a hit of filter `ALLIES` on it would set its `HIT` flag: `struck` has no
alive check); a `SINGLE` `TILE` entry read narrow: 241; the actors not in ascending position: 242; the hit given to
every set's actor (`run`): 243.

Two still survive (rows 232 and 239 do not kill them). A bomb or a trap takes held penetration (`penetration`):
`resolve` reads penetration only for a weapon hit or a spell (`types/hit.cairo` 252, 325–327). The source in its own
hit's set (`actors`): the source's bits reach only `entries` (`types/executor.cairo` 1935–1938, 2741), where `HIT_BIT`
8 is entry 3's bit (2324–2326, 2858–2859), and skill 82 holds a single entry.

**The inventory** (what the earlier tables already pin of `act`). `segment2.jsonl` reaches `ActionLibrary::act` in its
combat rows, but through `ActionRecorder`: each row records the class's result for the segment to replay, so a mirror
replaying it runs no `act` at all. `hit.jsonl` pins `HitTrait::resolve`, the hit a carrier's entry lands, from a
`Hit` that holds the `Offence` and `Defence` terms already built; `body.jsonl` pins the `Body` operations a carrier
writes (`wound`, `struck`, `landed`, `inflict`, `hold`, `spend`); `trap.jsonl` the trigger of a placed trap and
`free`. `segment.jsonl` calls no class. So no table pinned `act` as a port, nor `defence` and `offence`: every branch
of `act` is vectored here, and the two `Body` operations RV-03a deferred are vectored directly, on a member and a
goblin, rather than through `act` rows: an `act` row shows their result only through the hit it lands (a defence's
block slot, an offence's steal and energy reach the words only on some hits), so the direct rows pin every field. The
`act` rows run them all the same, through the real executor (the attacks, the spells, the bomb, the dart). `Blocked`
is not `act`'s (the segment's Move): no row gives it. `ActionTrait::aim`, `energy`, `glyphs`, `consume` and
`QuickCastTrait::count` are private steps of `act`, pinned through it.

**No refusal changes the ground** (FIX-01, track CV's review note): every `Err` of `act` returns before its arm's
`rules.carry`, the only write to the ground (a trap placed): `Clock`, `Absent` and `Knocked` before the arms; Turn's
`Turned` writes nothing; Attack's `aim` before its carry; the skill's every refusal, `Trap` the last, before its costs;
the item's `Empty`, `Belt` and `aim` before its count. `types::action::tests::test_no_carry_before_a_refusal` pins it:
the in-class executor behind a `Carry` that counts its calls, each refusal `act` gives is refused with no carry, and
each legal combat action carries once. Its Snare is instant (0 ticks), so its `Trap` refusal is on the path that
carries at once: a carry moved before that refusal fails the test. `Reach` and `Target` are refused there on each arm
that aims (RV-03a2, #447's review): the weapon's (goblin 9 at 2, `Reach`; the member, `Target`), the skill's (the fire
spell at goblin 10, 7 away, `Reach`; aimed at a tile, `Target`) and the item's (the bomb, count 1, at a tile 7 away,
`Reach`; the dart, count 1, at the member, `Target`): 19 refusals, none carrying. In this table, every refusal's words
and ground are the case's.

**Track CV's surviving mutants of the trap port (#444)**, killed by `act` rows only (a trap's hit is never blocked, so
`trap.jsonl` cannot): `ExecutorTrait::strike`'s block spend (a blocked weapon hit spends one charge of the blocking
slot) by 205, 206, 208, 210, 212, 213 and 214 (the charges before and after, and 206's effect ended); a knocked-down
target (`Struck.knocked`, read at `t₀`) by 209 against 210; a sleeping target (`Struck.asleep`) by 211 against 212; the
block's cap at 63 (`resolve`'s `defence.block > MAX_BLOCK`) by 213 (on the bound: 63, blocked) and 214 (below it: 62).
Above the bound no `act` row can go: `act` strikes goblins only (a weapon's or an attack skill's foe), and a goblin's
charges are 6 bits (`GoblinWords` 240–245), at most 63, and so are a member's (corrected by RV-03c: an effect's bits
16–21 in `MemberEffects`, bit 22 free; `MemberTrait::held` reads them modulo 64, so a 64 written there reads as 0):
`tick.jsonl` holds the member's side at 63 and 62 (72, 73) and the grant clamped to 63 (80).

**How the rows are sized for mutants** (as `hit.jsonl`): for every comparison, a row on each side of its bound (the
clock at `LAST_TICK` and past it; knocked down to `c` and `c + 1`; `R` at `c` and `c + 1`; adrenaline at 4 × cost − 1
and 4 × cost; energy at the cost − 1 third and the cost; *Fieldcraft* at the cost − 1, the cost and past it; a glyph
to `c` and `c + 1`; a range at its value and one past; `quick` below, equal to and above `n`; `k` below, equal to and
above the activation; the guarded trap's health × 2 at 480, 478; a belt count at 0, 1, 2); for every arithmetic step a
row whose result tells the operator apart (the bar rank the carrier takes: a skill at ranks 3 and 9 on slot 2, 215
and 216, held at that rank; the energy in thirds; *Fieldcraft*'s rank × 1 against the cost; the
glyphs' sum against the cost, with a rune whose line rises with the rank; the counter's `+ 1` and its reset; `n −
quick`; `A = c + n`; the recharge from `c + 1`; the count − 1). For every refusal, a row where it wins over the next
one in `act`'s order, so a mutant that swaps two checks is seen. Each flag test reads one bit among others set
(`TURNED` with `INSTANT`, `INSTANT` with `TURNED`), so a mutant reading the whole byte is seen. Each kind of target
has its own rows (`FOE`, `ALLY`, `SELF`, `TILE`, a weapon's foe, an attack skill's foe, a potion's by its entry).
`defence` and `offence` have a row on each side of each held effect's deadline (`t − 1`, `t`), each scope of
`PENETRATION`, each `HitClass`, the clamps (an `ARMOR` effect below 0 and above 255, a percent above 100, a base
below 0). A held potion's position is a skill's position too: skills 1 and 2 sit where the potions held fall (a glyph,
an enchantment), so a potion read as a skill (`glyphs`, `DefenceTrait::add`) is seen. Track CV names
further cases for surviving mutants; they are appended, as `hit.jsonl`'s.

## `tick.jsonl`: the ticks with a fight, `TickLibrary::ticks` (RV-03c, D-257)

Printed by `types::tick::tests::vectors::test_tick_vectors_0` to `_13` (ids 0–24, 25–40, 41–55, 56–71, 72–85,
86–109, 110–118, 119–128, 129–130, 131–147, 148–160, 161–165, 166–167, 168–170), split for snforge's step limit, each
part with its digest. Where `segment2.jsonl`
records the tick class's result for a replay, this table tests a port of the class itself.

**The entry vectored, and why.** `TickLibrary::ticks` (`ITickLibrary`, `systems/tick.cairo`), the real class declared
in the test: it is what `play` calls (`SegmentTrait::ticks`, the only caller), and everything a tick does sits behind
it: it loads the words through the content (`WordsTrait::indexed`), runs `TickTrait::run` with `Delegate` rules
(step 0 perception and the awake set in process; step 1 each concluded carrier through the real `ExecutorLibrary`;
step 2 in one call of the real `AiLibrary`, whose carriers go through `ExecutorLibrary` and whose trap entered goes
through the real `TrapLibrary`; step 3 and step 5 in process), and stores the words and the ground back. `AiLibrary::act`
alone is not a port's boundary (its inputs, the frozen tiles and the roster count, are computed by `TickLibrary`'s
`Delegate::step`), so it is vectored through `ticks`. The ticks `play` runs without the class are the `skip` rows.
The `skip` rows do not call `SegmentTrait::ticks`: their printer (`types::tick::tests::vectors::skip`) holds a copy of
its choice of path (none, the fast path, the class), so a change to that branch in `play` must be made in the copy too
(RV-03a2, #456's review). `MAX_ATTACKERS` (8) is unreachable from `ticks`: the goblins that act in step 2 are the
awake set's (`AiTrait::capped` walks `world.woken()`), at most `MAX_AWAKE` = 8 (`WorldAssert::assert_awake`), so
`attacks < MAX_ATTACKERS` holds for each of them and the cap never makes one hold; a mutant of the bound (`≤` for `<`)
is equivalent, and no row reaches it.

One line: `{"id", "fn", "case", "ok"}`, every felt in hex, every value its Cairo `Serde` (as `segment2.jsonl`; a
negative integer `P − |v|`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content` (`tick_content`): the executor tests'
(`types::executor::tests::content(40, …)`: the fixtures' bar skills 1–8, castes Hob (1) and Runt (2) of armor 40, a
sword of 30, range 1, rank 12; Cinder Ring 40, Brace 43, Snare 45 and the others), with the castes' skills made the AI's
cases: Hob (`k` 1) slot 0 skill 24, an attack skill of activation 2 and 1 strike (4 quarters); slot 1 skill 25, an
instant fire spell (40 on a foe, range 2, 5 energy: 15 thirds, recharge 6); slot 2 skill 26, an instant trap skill
(the AI skips it); slot 3 skill 27, an instant shout on itself (recharge 20). Runt (`k` 3): slot 0 skill 28, an
instant attack skill; slot 1 skill 29, an attack skill of activation 1. And the table's: skill 80, an enchantment
holding `REGENERATION` 2 to 6 pips with the rank (`regen0` 2, `regen12` 6); skill 81, a stance granting `BLOCK` 60 to
72 charges with the rank (60 + rank), activation 1; potion 101 (the fixtures' belt slot 1) holding `REGENERATION` 3
(`regen` 3). The `REGENERATION` content is the table's own, not `contracts/seed`'s (a seed change would move the
probe and the streams). Every actor is loaded through it.

**`ticks`**: `case` the call's arguments but the content and the classes: the `Words` (`clock`, the members'
`MemberWords`, the goblins' `GoblinWords`, `killed`, `defeated`), the `Board` (`window`, `x`, `y`: the origin plus
15, D-134), the level (20), the ground (`Array<(u8, Features)>`), `n` (the ticks). `ok` what it returns: the `Words`,
the ground. **`skip`**: `SegmentTrait::ticks`' path for `n` ticks: `case` the `Words`, the `Board`, `n`; `ok` the path
(0 `TickLibrary`, 1 the fast path `TickTrait::idle`: no member activating, no goblin awake, no living goblin in the
window; 2 none: `n` 0 or the adventurer defeated), then the `Words` after it (`TickLibrary`'s with the empty ground).

The world, unless a row says otherwise: the clock 200 (the first tick `T` = 201); the adventurer, member 0 on (7, 7)
(window position 112, `AT`) facing 0 (toward `AT − 1`), the executor tests' member: level 20, health 400 of 480, 30
energy thirds of 60 regenerating 2 a tick, health regeneration 0, adrenaline 0, bar 1–8 at rank 0, belt items
100–103. Goblins are chunk 0's (entities 8–12 pack 0, 13–17 pack 1), a Hob unless a row says Runt, health 100 of 280,
no energy (30 thirds at most, 1 a tick), no adrenaline, level 10, facing the adventurer; `AT + d` is `d` tiles East on
the adventurer's row. "Armed": every caste slot recharging to `T` (`t > R` is false), so its weapon or a step. The
board is the open window at the origin, the ground chunk 0 empty, `n` 1.

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `ticks`, the member's steps (24) | 1–24 | alone: the clock to `T`, energy 30 → 32 (1); health regeneration 3 pips from 400, 473, 474 (the max), 475 (clamped) (2–5); the ±10 pips clamp: 10, 11, Bleeding, Poison and Burning (−14), the same with 4 pips (6–9); each condition to `T` (held: −3, −4, −7 pips) and to `T − 1` (ended) (10–15); energy from 57, 58, 59, 60 (16–19); **adrenaline's decay** out of combat: from 2 (to 1), 1 (to 0: it reaches 0), 0, and 2 over 3 ticks (1, 0, 0) (20–23); the flags `TURNED`, `INSTANT`, `HIT` cleared, `HALVED` kept (24) |
| `ticks`, **`REGENERATION`**, `n`, the stops (16) | 25–40 | skill 80 held in effect slot 0 at rank 12 to `T` (6 pips) and `T − 1` (none), at rank 0 to `T` (2) and `T + 1` (2) (25–28); potion 101 held (belt slot 1) to `T` (3 pips) and `T − 1` (none) (29, 30); both over 3 ticks, the skill to `T + 1`, the potion to `T`: 9, 6, 0 pips (31); `n` 0 (nothing), 2, 10 (the largest `play` passes: an action's ticks are at most the weight, `MAX_WEIGHT`) (32–34); at 0 before the tick: down, defeated, the clock kept (35); at 1 with the three conditions: down at step 3 of `T`, the 2 ticks after not run (36); down (status 1) and gone (2): no regeneration (37, 38); a companion (member 1) inside at 0: the tick stops at once (FX-8) (39); at 300 with 3 pips, both regenerate (40) |
| `ticks`, perception and the awake set (15) | 41–55 | asleep at 2 (wakes Engaged, acts) and 3 (41, 42); on watch at 2 facing away (43); at 5 facing the adventurer (front arc: notices), at 6 (`range::ALERT`: not) (44, 45); at 5 facing away (46); at 5, sight blocked by a wall on `AT + 3` (47); at 5 turned one step (front-side: notices) and two (rear-side: not) (48, 49); Alerted at 5 (awake, steps) (50); Returning at 1 (awake, does nothing) (51); dead at 1 (52); the pack: 8 on watch at 2 notices, 9 (pack 0) asleep at 7 engaged with it and acting, 13 (pack 1) asleep at 6 not (53); nine Alerted goblins at 2, 2, 3, 3, 4, 4, 5, 6, 6, eight awake on the words: the eight nearest, the tie at the set's edge to the lower id (15 in, 16 out) (54); Engaged outside the window (on (7, 20)): out of the set, its awake flag cleared, no act (55) |
| `ticks`, an Engaged goblin's act (16) | 56–71 | a Hob adjacent (`AT + 1`): slots 0 (short of adrenaline), 1 (of energy) and 2 (the trap) skipped, the shout used, `R = T + 19` (56); the shout recharging to `T` (the weapon) and `T − 1` (the shout) (57, 58); slot 0 at adrenaline 4 (starts, `A = T + 2`, 4 spent), 3 (the weapon), 5 (starts, 1 left); slot 0 recharging to `T` with 4 (the weapon), to `T − 1` (starts) (59–63); slot 1 at 15 thirds (the spell lands, `R = T + 5`), 14 (the weapon); at 2 tiles with 15 (lands), at 3 (out of range and reach: a step) (64–67); a Runt: the instant attack skill (lands, recovering to `T + 2`, `R = T + 9`); armed, its weapon (recovering to `T + 2`) (68, 69); armed, the weapon from behind the adventurer (`AT + 1`) and from its front (`AT − 1`) (70, 71) |
| `ticks`, **the block cap**, the member's activations (14) | 72–85 | Brace held in effect slot 0, an armed goblin in front (`AT − 1`): **63 charges, blocked, to 62** (72); 62 to 61 (73); 1 to 0, the effect ended (`T − 1`) (74); 63 knocked down to `T` (held: landed, kept) and to `T − 1` (blocked, to 62) (75, 76); 63 from behind (`AT + 1`, landed) (77); skill 81 concluding at `T` on bar slot 0 at ranks 2, 3, 4: 62, 63, and 64 clamped to 63 (`MAX_BLOCK`) (78–80); bar slot 1 (skill 2, recharge 12) concluding at `T` (`R = T + 11`), overdue at `T − 1` (concluded, `R = T + 10`), at `T + 1` (not yet), down at 400 (not concluded; no target for the goblin, which leaves the set) (81–84); Cinder Ring concluding at `T` among goblins 8 (`AT + 1`, 90), 9 (`AT − 1`, 100) and 10 (`AT + 15`, 280): 9 then 8 killed (tile order), 10 burns and strikes (85) |
| `ticks`, the AI's states, step 1 and step 3 of a goblin (24) | 86–109 | Fleeing at 2: a step away (86); every tile around it walled but `AT + 1`, nearer the adventurer: it steps there, still Fleeing (87); every tile walled: cornered, Engaged again (88); knocked down to `T` (no act) and `T − 1` (acts) (89, 90); slot 0 activating to `T` (concludes: its weapon hit, `R = T + 9`, no act after), to `T − 1` (lapsed, FX-29: `R = T + 8`, then the shout), to `T + 1` (busy) (91–93); recovering to `T − 1` (cleared, the shout) and `T` (busy) (94, 95); a Runt's slot 1 concluding at `T`: recovering to `T + 1` (FX-15) (96); Alerted at 6 at 1 health, Bleeding to `T` (dies: `DEAD`, in `killed`) and `T − 1` (97, 98); energy from 29 and 30; **adrenaline** Alerted from 2 (to 1) and 1 (to 0), Engaged from 2 (kept) (99–103); the adventurer's adrenaline 2 beside an Engaged goblin (kept: in combat) and an Alerted one (decays) (104, 105); a goblin holding skill 80 (rank 12) to `T` (+12) and `T − 1` (106, 107); Crippled to `T` (its step costs 2: recovering to `T + 1`) and `T − 1` (108, 109) |
| `ticks`, goblin order, the carrier, traps, defeats (9) | 110–118 | goblins 8 and 9 Alerted on `AT + 2` and `AT + 2 − 15`, the tile `AT + 1 − 15` walled: both would take `AT + 1`, the lower id first, the other holds (110); the ids swapped: the other moves first (111); a step onto the tile of an asleep goblin (13, not awake: frozen) refused, another taken (112); a step onto the member's Snare (bar slot 0, placer `(0, 0)`): it triggers through `TrapLibrary` (100 → 44, Crippled to 203, the trap used) (113); onto a terrain trap: nothing (FX-34) (114); **the same goblin three times in one tick**: Cinder Ring concluding at `T` strikes goblin 8 (280 → 153, Burning), it strikes in step 2, burns in step 3 (115); goblin 8 Alerted at 5 over 2 ticks, two steps (116); defeats: goblin 8's attack skill concluding at `T` on the adventurer at 1 (down at step 1, no step 2 or 3, the 2 ticks after not run) (117); goblin 8's weapon at step 2 on it at 1: goblin 9 does not act after it (118) |
| `skip` (10) | 119–128 | alone: the fast path, 1 and 10 ticks (119, 120); `n` 0, defeated: none (121, 122); activating: `TickLibrary` (123); outside the window, Engaged (not calm: `TickLibrary`) and asleep (the fast path) (124, 125); in the window asleep and on watch (`TickLibrary`), dead (the fast path) (126–128) |
| `ticks`, the roster (2) | 129–130 | goblin 248 (spawn chunk 15) Alerted on (7, 15), the adventurer on (7, 12): its step leaves its spawn chunk (D-238); with 59 other goblins away from theirs (asleep on (100, 100)) it steps (129); with 60 the roster is full: it holds (130) |
| `content` (1) | 131 | RV-03d (D-257), after every earlier id: the content of rows 131–170 (below) |
| `ticks`, the stops, step 1's order, step 2's set, the target, perception (16) | 132–147 | the adventurer at 1, member 1 on `AT − 2`, goblin 9 armed on `AT − 3` beside it: goblin 8's weapon downs it in step 2 (132), goblin 8's attack skill concluding at `T` in step 1 (133): goblin 9 does not act; skill 95 concluding at `T` downs member 1 (on `AT − 1`, at 1): goblin 8's activation to `T` not concluded (134); goblins 8 and 9 concluding at `T` on the adventurer at 1: 8's hit downs it, 9's activation not concluded (135); goblin 8 concluding at `T` (resolved), goblin 9 armed acts (136); Cinder Ring kills goblin 8 (90) activating to `T`: not concluded (137), kills goblin 9 (90) on `AT + 1`: goblin 8 Alerted on `AT + 2` steps onto its tile (138); a concluding target no longer legal: skill 96 on goblin 8, dead: no heal (139), goblin 8's attack skill on the adventurer 2 tiles away: no hit (140); the target, the first member alive in the window: member 0 outside it (on (7, 20)) (141) and down (status 1) (142), goblin 8 hits member 1; goblin 8 asleep 2 tiles from member 0 and 7 from member 1 (`AT − 5`): it notices (143); goblin 8 on watch at 2 notices: goblin 24 (chunk 1's pack 0) asleep at 4 not engaged (144), goblin 9 (pack 0) Alerted at 5 Engaged (145); the adventurer's adrenaline 2 beside an Engaged goblin outside the window: decays (146); the adventurer on a tile the window does not hold walkable: no flood, goblin 8 Alerted at 3 holds (147) |
| `ticks`, the goblins' skills (13) | 148–160 | facing away: the weapon (148) and the fire spell (149) turn the goblin; slot 0 lapsed from `T − 1` (`T + 8`) below its stored `T + 50`: kept (150); a Runt, slot 0 recharging: slot 1 (activation 1) starts, `A = T + 1` (151); slots 0–2 recharging: its slot 3, the instant shout, no recovery (152); Gap: slot 2 empty, the shout (153); Shaman: slot 0 at rank 12 (fire 80) now (154), slot 1 concluding at `T` (rank 12, cleared: a spell) (155), slots 0 and 1 recharging: slot 2 on the adventurer's tile (156), slot 3's activation concluding at `T` (157), Alerted at 6, 3 pips (158); Crippled to `T` holding skill 94 (`MOVEMENT`) to `T` (a step of 1) and `T − 1` (of 2) (159, 160) |
| `ticks`, the flood, a trap's kill (5) | 161–165 | goblin 8 Alerted on `AT + 2` steps onto `AT + 1`, where dead goblin 9 lies (161); goblin 8 asleep on (8, 4) (frozen), goblin 9 Fleeing on (7, 4): to (7, 3) (162); the adventurer on (1, 1), the flood at its cap: goblin 8 Alerted on (13, 8) (layer 15) steps (163), Fleeing on (13, 9) (16, beside layer 15) is not reached: cornered, Engaged (164); goblin 8 (50 health) killed by the member's Snare it enters (165) |
| `ticks`, the roster (5) | 166–170 | as 129 and 130, 59 away frozen: goblin 120 (spawn chunk 7) Alerted on (2, 3), away: full, goblin 248 holds (166); goblins 248 on (5, 15) and 249 on (9, 15): 248 steps out (60), 249 holds (167); goblin 120 on (7, 15) steps into chunk 0, neither home (168); goblin 8 (chunk 0) on (5, 15) steps home (59), then 248 on (9, 15) out (60) (169); 60 away frozen, goblin 248 Fleeing on (7, 15): held by the full roster, still Fleeing (170) |

Per `fn`: `content` 2, `ticks` 159, `skip` 10.

**Row 131** (RV-03d): every row from 131 on reads the content of row 131, the last `content` row before it; rows
1–130 read row 0's. It is row 0's with skills 90–96 and castes 3 and 4 appended. Skills: 90 an instant spell of fire
20 to 80 with the rank on a foe (range 2, recharge 6); 91 the same at activation 1; 92 an instant spell of fire 40 on a
`SINGLE` `TILE` (range 2); 93 a shout on itself at activation 1; 94 an enchantment holding `MOVEMENT`; 95 a spell of
fire 40 on `RING_1` around its source, filter `ALLIES`, activation 1; 96 a spell of fire 40 on a foe then a heal of 30
on itself (range 6, activation 1). Castes, the Hob's but: Shaman (3), `k` 3, health regeneration 13 (3 pips), skills
90–93; Gap (4), skills 24, 25, none, 27 (slot 2 empty). None mixes `TILE` with `FOE` or `ALLY` (D-271): 92 is `TILE`
alone, 96 is `FOE` then `SELF`. Rows 141 and 147 are inputs the class takes but `play` never passes: member 0 outside
the board's window, and on a tile the window does not hold walkable (`AiTrait::flood` returns `None` there, so the
class does not panic; a flood from it would, `Bfs::flood`).

**Track CV's surviving mutants of the tick port (#459), RV-03d's rows.** By their number in #459's list (*Survive
(45)*; each mutant's name is in `client/sim/src/parity/mutants.test.ts`): 1: 132; 2: 133; 3: 166; 4: 144; 5: 141;
6: 142; 7: 161; 8: 163; 9: 162; 10: 147; 11: 135; 12: 165; 13: 140, 139; 14: 152; 16: 165; 17: 153; 18: 151; 19: 146;
20: 145; 21: 148; 22: 167; 23: 168; 24: 169; 25: 149; 26: 134; 27: 150; 28: 157; 30: 155; 31: 158; 32: 159; 33: 160;
34: 136; 35: 143; 36: 170; 37: 139; 38: 138; 39: 137; 41: 154; 42: 156; 43: 155; 44: 164; 45: 164. Some are built
otherwise than #459 suggests: the Runt's slot 3 in row 0 is already an instant shout (skill 31, the fixtures'), so 152
needs no new content (14); no caste of row 0 has an empty slot, Gap has (17); 134's carrier is on `RING_1`, since a
skill takes `DISC_1` only as a potion (`ExecutorTrait::assert_carrier`) (26); a dead target is in no set, so a hit on it
shows nothing: skill 96 heals its source after its foe entry, which the mutants run and the code does not (37, and 13).

Three are equivalent, and no row is built for them:
- 15, an entered trap's members not written back: a trap writes its entrant alone. `ExecutorTrait::trigger` gives every
  entry the entrant as its set and writes only it (`types/executor.cairo` 2064–2090); `TrapTrait::trigger` reads the
  placer and writes the ground (`types/trap.cairo` 189–228). The members cross `TrapLibrary` unchanged.
- 29, a goblin's nearest member is its farthest (`d < near || near == FAR`): `near` is `FAR` only while every member
  read so far is at `FAR`, and `d` is at most `FAR`, so both leave `near` at `min(near, d)` (`types/world.cairo`
  568–574).
- 40, a dead goblin acts (`AiTrait`): `AiTrait::act` returns at once for a state other than Engaged, Alerted or
  Fleeing (`types/ai.cairo` 240–243), and a goblin not alive is `DEAD` or `LOOTED` (`is_alive` is `ai < DEAD`,
  `models/goblin.cairo` 236–238), so it acts on nothing and the step's stop is unchanged.

#459's eight equivalent mutants were read against the code and hold.

**The rows asked for by name.** The block cap above 63 (track CV, 2026-10-11): a member's charge field holds 6 bits,
not 7 (`MemberEffects`, an effect's bits 16–21; bit 22 is free and `MemberTrait::held` reads the charges modulo 64),
and the grant clamps to 63 (`ExecutorTrait::hold`, `MAX_BLOCK`), so no tick puts a member at 64: the bound the tick
reaches is pinned instead, 72 (63, blocked, to 62) and 73 (62), and the grant at 64 clamped to 63, 80; a row above it
(`resolve`'s `defence.block > MAX_BLOCK`) cannot come from any words and goes to RV-03a2. Adrenaline's decay: the
member 20–23; a goblin not Engaged 101 (2 to 1) and 102 (1 to 0); Engaged, kept 103; the member beside an Engaged
goblin, kept 104; the member beside an Alerted one, decays 105 (corrected by RV-03a2, #456's review). The same goblin
changed twice in one call: 115 and 116 here; `fits` is the segment's, so `segment2.jsonl` 46 and 47 are appended for
it. `REGENERATION`: row 0's skill 80 and potion 101; 25–31 (the member), 106, 107 (a goblin), each on both sides of
its deadline.

**The inventory** (what the earlier tables already pin of the tick). `segment.jsonl` calls no class: its ticks are the
fast path (`TickTrait::idle`, the members' regeneration alone). `segment2.jsonl` reaches `TickLibrary::ticks` through
`TickRecorder`: each row records the class's result for the segment to replay, so a mirror replaying it runs no tick;
its fast-path rows pin `idle`'s member regeneration and `SegmentTrait::idle`'s choice on four worlds. `batch.jsonl`
pins `admit` and `revealed`, no tick. `movement.jsonl` pins the pure rules the step uses (the flood, a Move's ticks,
the awake set's choice by distance). `hit.jsonl` pins the hit and `body.jsonl` the `Body` operations a carrier
writes. So no table pinned the tick as a port: perception, the awake set formed on the window, step 1's conclusions,
the AI's act, step 3's regeneration with the held effects and the decay, step 5, and the path `play` takes, all are
vectored here; the flood is reached through the steps.

**How the rows are sized for mutants** (as `hit.jsonl`): for every comparison, a row on each side of its bound and,
for `≥` against `>`, on it: a deadline at `T` and `T − 1` (the conditions, the held effects, a knock-down, an
activation, a recovery); a recharge at `T` and `T − 1` (`t > R`); adrenaline at 4 × cost − 1, 4 × cost and above;
energy at the cost − 1 third and the cost; a spell's range at its value and one past; perception at 2 and 3 tiles
asleep, 5 and 6 on watch, each arc; health and energy at the max − 1, the max and past it; the ±10 pips clamp at 10 and
11; the block at 63 and 62 and the grant at 62, 63, 64; the roster at 59 and 60; the awake set's eighth and ninth
candidates, tied. For every arithmetic step a row whose result tells the operator apart (`R = A + r − 1` from `T` and
from `T − 1`; `A = T + n`; FX-15's `B = A + k − n − 1`; the pips × 2; a REGENERATION line at ranks 0 and 12). For every
order the code fixes, a row where the other order differs (goblin ids swapped, a member before a goblin, a stop
before the next goblin). Track CV names further cases for surviving mutants; they are appended, as `hit.jsonl`'s.
