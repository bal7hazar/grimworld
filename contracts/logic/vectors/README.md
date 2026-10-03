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

Printed by `types::window::tests::test_vectors` (ids 0–1213) and `test_vectors_1` (ids
1214–2064), split for snforge's step limit, each part with its digest.

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
| `feed` | `entropy`, `chunk`, `side` (0 West, 1 East, 2 South, 3 North, 4 none) | `EntropyTrait::feed(entropy, reveal_fact(chunk, side))`: `entropy + poseidon('fact:reveal', chunk, side)` |
| `base` | `word`, `biome` (1 meadow … 4 ruin) | `BoardTrait::base`: the base's floor bitmap (1 = floor, interior only) |
| `sight` | `x`, `y`, `width`, `height` (a global tile, a location in chunks) | `SightTrait::chunks`: the chunks within 6, the tile's own first, then by index |
| `member` | `tile`, `k` (0–18), `odd` (the tile's global row parity) | `PackPlacementTrait::member`: `Option<u8>`, the chunk's tile at `OFFSETS[k]` |
| `reveal` | `Site`, `Progress`, `instance_id`, `known` (`Span<(u8, Terrain)>`), `chunks` (`Span<(u8, u8)>`, chunk and side entered) | `RevealTrait::reveal`: the `Progress` after, then the chunks revealed, `Span<Revealed>` (chunk, `Terrain` (walls 1 = wall, edges), `Features` (2 `PackPlacement`, 3 `Object`, `touched`)) |

`reveal` covers every computation the client repeats: the chunk's word, the base, the smoothing
with the margins (`hexx`'s `CaverTrait::smooth`, B4/S2, one generation), the ring's decisions and
openings, the lines to the spine, the cut, `keep_component`, the quotas' draws, the bands and the
placement (the draws of `hexx`'s `RngTrait` from `mix(word, k)`: 2 quotas, 3 placement, 4 the
ring), and the progress (revealed set, count, open edges, quotas left, the entropy fed).

The cases (197):
- `word` (18): 3 entropies (0, a short string, `P − 1`) × 2 instance ids × 3 chunks (0, 112, 224);
  `feed` (15): the 3 entropies × the 5 sides of chunk 17; `base` (12): 3 words × the 4 biomes;
  `sight` (12): corners, sides, centres and edges of chunks in a 15 × 15 location; `member` (114):
  the 19 offsets from tiles 112, 97 and 16, both parities.
- `reveal`, part 1 (15): each biome on a 3 × 3 zone, chunk 16 (an odd chunk row) with nothing known,
  then chunk 1 (an even one) knowing it; chunk 16 of a forest after its South, East, West and North
  neighbours one at a time (1 to 4 sides known); the edge of a 2 × 2 zone whose chunk (1, 1) is
  outside the outline, an anchor on the East side (three chunks asked, the void one skipped); a
  ruin's chunk cut by a tile mask (columns 0–11), then its neighbour.
- `reveal`, part 2 (11): a cave dungeon floor of `N` 6 grown from its entry chunk 112 to its close
  (the frontier's rules at `N − 1` and `N`), with an exit and a vein quota; a 2 × 2 meadow with a
  collector, two landmarks, a Heart and a task's landmark, revealed whole (every quota placed); a
  set piece laid by quota, then its neighbour.

