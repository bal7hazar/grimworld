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

## `hit.jsonl`: one hit (CBT-03a)

Printed by `types::hit::tests::test_vectors`, with its digest. One line: `{"id", "case", "ok"}`.
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

Printed by `fate::tests::test_vectors` (ids 0–217), one part, with its digest.

One line: `{"id", "fn", "case", "ok"}`, every felt in hex (a `u32` index is a felt below 2^32).
Poseidon is `core::poseidon::poseidon_hash_span`, the hash of the Starknet `poseidon` builtin.

| `fn` | `case` | `ok` |
|---|---|---|
| `purpose` | the index in `PURPOSES` (0 `ENTRY` … 7 `RIFT_BOARD`) | the purpose's felt (a short string, e.g. `'fate:entry'`) |
| `domain` | `subject`, `counter`, `purpose` | `fate::domain`: `poseidon(subject, counter, purpose)` |
| `derive` | `word`, `domain`, `index` | `fate::derive`: `poseidon(word, domain, index)` |

The cases (218):
- `purpose`: the 8 purposes.
- `domain` (120): each purpose over 8 pairs `(subject, counter)` — zeros, one on either side, `P − 1` for both, 2^128 with 2^64, a small pair, 2^250 with 2^32, a `u32` maximum counter; then 8 subjects × 7 counters (0, 1, 2, 255, 2^32, 2^64, `P − 1`) under `ENTRY`. `P − 1` is `0x800000000000011000000000000000000000000000000000000000000000000`.
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
