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

Printed by `types::reveal::tests::test_vectors` (ids 0–170), `test_vectors_1` (171–185) and
`test_vectors_2` (186–196), split for snforge's step limit, each part with its digest
(`PART_1`, `PART_2` are the first ids of the later parts).

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

The cases (197):
- `word` (18): 3 entropies (0, a short string, `P − 1`) × 2 instance ids × 3 chunks (0, 112, 224);
  `feed` (15): the 3 entropies × 5 facts `('fact:test', 17, s)`; `base` (12): 3 words × the 4 biomes;
  `sight` (12): corners, sides, centres and edges of chunks in a 15 × 15 location; `member` (114):
  the 19 offsets from tiles 112, 97 and 16, both parities.
- `reveal`, part 1 (15): each biome on a 3 × 3 zone, chunk 16 (an odd chunk row) with nothing known,
  then chunk 1 (an even one) knowing it; chunk 16 of a forest after its South, East, West and North
  neighbours one at a time (1 to 4 sides known); the edge of a 2 × 2 zone whose chunk (1, 1) is
  outside the outline, an anchor on the East side (three chunks asked, the void one skipped); a
  ruin's chunk cut by a tile mask (columns 0–11), then its neighbour.
- `reveal`, part 2 (11): a cave dungeon floor of `N` 6 entered at chunk 112, its outline drawn at
  `create` (ENG-10b: `Site`'s `chunk_set`, `west` and `north`, every chunk's mask with its hosts
  above the board), revealed whole by index, with an exit and a vein quota; a 2 × 2 meadow with a
  collector, two landmarks, a Heart and a task's landmark, revealed whole (every quota placed); a
  set piece laid by quota, then its neighbour.

