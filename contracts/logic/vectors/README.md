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
(`contracts/ephemeral/tests/test_play_limits.cairo`) and by `batch.jsonl`'s `owed`.

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

Printed by `types::play::tests::test_segment2_vectors_0` to `test_segment2_vectors_4` (ids 0–11, 12–22, 23–25,
26–30, 31–42), split for snforge's step limit, each part with its digest. It covers what `segment.jsonl` cannot: the
branches of `run` that call `TickLibrary`, `ActionLibrary` or `TrapLibrary`, and those that meet a goblin, a trap, a
companion, a regeneration or a `MOVEMENT` effect. One line: `{"id", "fn", "case", "ok"}`, every felt in hex, every
value its Cairo `Serde` (as `segment.jsonl`).

**Row 0** (`fn` `content`): `case` empty, `ok` the table's `Content` (`types::tick::Content`): the unit-test
fixture's (`Fixture::content`), skill 8 instant (activation 0), and skill 9, an enchantment whose first entry is
`MOVEMENT` (FX-18). Every other row loads its words through it.

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
of the span instead: it checks the kind and, if it computes the inputs, their digest, then loads the recorded
`Words` and `ground` as `run` loads the class's (`SegmentTrait::reload`; `trap` writes back the members, and the
placer goblin of a placed trap). This is sound for `run`'s own logic: the classes are pure functions of their
inputs and the content, so a recorded result stands for the call whenever the mirror's inputs hash to the recorded
digest; a mirror that reaches a different call, or none, or calls with other inputs, differs from `run`, and the
row says so. It does not check the classes themselves (the ephemeral tests and `hit.jsonl` do): a mirror replaying
these rows needs no `ActionLibrary` or `TickLibrary` of its own. No branch needed a stub.

The classes are the real ones (`ExecutorLibrary`, `AiLibrary`, `TickLibrary`, `ActionLibrary`, `TrapLibrary`)
behind test recorders (`types/play/tests/recorder.cairo`) that forward each call and log the segment's own:
`TickLibrary`'s nested calls to the trap class are not in the span. The adventurer is the unit-test fixture's
member (two potions 101 in belt slot 1) on (22, 22) of chunk 16 of the 3 × 3 location of `segment.jsonl`, every
chunk revealed, at clock 40, unless a row says otherwise; goblin 264 is chunk 16's first (`8 + 16 chunk + k`), the
fixture's Hob (Engaged, awake, health 100).

**Not reached:** `LayoutTrait::neighbor` → `None` (a Move off the window's edge). The window is assembled around the
adventurer after every Move that does not end the segment, and nothing else moves it, so a Move always starts at
the window's centre (`movement.jsonl`'s `origin`: position 112 or 127), and every neighbour of the centre exists.
The mirror keeps refusing it.

The cases (43):

| `fn` | ids | what |
|---|---|---|
| `content` (1) | 0 | the table's content |
| `combat` (11) | 1–11 | the `_` arm, goblin 264 beside the adventurer, then a Wait: an Attack out of reach (1, `Reach`, the words kept), a spell on the goblin (2), Cinder Ring on itself (3, 2 ticks), a potion (4), an Attack on no entity (5, `Target`), an instant spell (6, 0 ticks charged 1); `Heavy` (`heavy`, the words kept): 0 ticks with no weight left (7), 2 ticks with 1 left (8), the potion with none (9); alone, a spell (10: the member activating, its ticks through `TickLibrary`) and a potion (11: its ticks on the fast path) after a Wait |
| `ticks` (4) | 12–15 | `Self::ticks` through `TickLibrary`: two Waits beside goblin 264 (12); 2 owed ticks, no action (13); a goblin awake outside the window, so not calm (14); an asleep one there, calm: the fast path, no call (15) |
| `fits` (7) | 16–22 | the goblin records of a Wait beside goblin 264 with no record (`touched` bit clear, E-1: 1 more): `ran` and the weight 1, refused (16, `undo`); weight 2, taken (17, 0 left); the invocation's first action, unbound (18); with a record, taken (19); held by an earlier segment, nothing added (20); E-16's 17th record refused (21, `undo`); the untouched one engaged (22): goblin 248 asleep beside the adventurer notices it and engages its pack, 249, outside the window and not awake, changes only its AI state (1 to 3) and is not counted (`changed` holds 248 alone) |
| `defeated` (3) | 23–25 | `world.defeated` breaks the loop: the adventurer at 0 health, defeated by the owed tick before the first action (23, `played` 0, no `illegal`); at 1 health with Bleeding, Poison and Burning, on the first Wait's tick, on the fast path (24) and through `TickLibrary` (25) |
| `trap` (3) | 26–28 | a Move West onto local (6, 7) of chunk 16, then a Wait: a terrain trap (26, `param` skill 2), a used one (27, no call), a placed trap of goblin 264, outside the window (28: its words go with the call) |
| `occupied` (2) | 29–30 | a Wait, then a Move West onto goblin 264: `Blocked` from `TrapTrait::occupied` (29); dead, it does not block (30) |
| `companions` (3) | 31–33 | a second member on (23, 22) blocks a Move East (31); down, it does not (32); on (25, 22), at 300 health with health regeneration, it regenerates on the fast path with an owed tick and two Waits (33) |
| `regeneration` (3) | 34–36 | an owed tick, a Wait, a Move and a Wait on the fast path: health regeneration under the max (34), at it (35), Bleeding to tick 42 (36) |
| `movement` (2) | 37–38 | Crippled to 100, two Moves West: with skill 9's `MOVEMENT` held to 100 each takes 1 tick (37); held to 40, ended at clock 40, 2 (38) |
| `turn` (2) | 39–40 | CV: Turn, Wait, Turn: the Wait's tick clears the turned flag, the second Turn is legal, `flags` 1 after it (39); a third Turn after it is `Turned` (40) |
| `follow` (2) | 41–42 | CV: the window follows each Move that reveals nothing: seven Moves West from (22, 22), the seventh onto (15, 22), on the first window's ring (never open in it), then a Wait (41); from (29, 22), the eighth Move West is `Blocked` by a wall on (21, 22), outside the first window (42) |

Per `fn`: `content` 1, `combat` 11, `ticks` 4, `fits` 7, `defeated` 3, `trap` 3, `occupied` 2, `companions` 3,
`regeneration` 3, `movement` 2, `turn` 2, `follow` 2.

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

