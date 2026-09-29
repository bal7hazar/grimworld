# Seed data

Content written into `Registry` through `set_record` (ENG-03). The records' bit layouts are
`grimworld_logic::world` and docs/architecture/ENG-01-interfaces.md §3.5; the files here hold the
fields, not the packed felts.

| File | What |
|---|---|
| `test-region.json` | The test region: one region, its town, one zone, a dungeon of two floors, their gates |

## The test region

| Kind | Id | What |
|---|---|---|
| `REGION` | 1 | "Test Region": town 1, no book, first location 1 |
| `LOCATION` | 1 | The town (a hub: no map, so no size and no entry) |
| `LOCATION` | 2 | A zone: meadow, levels 1–3, 3 × 2 chunks, entered at chunk 0, tile 105 (row 7, column 0) |
| `LOCATION` | 3 | The dungeon's first floor: cave, levels 3–5, `N` 6, 2 floors, next floor 4, entered at chunk 112, tile 112 (the centre, ENG-01 §3.2) |
| `LOCATION` | 4 | The second and last floor: `N` 8 |
| `OUTLINE` | 767 (2 × 256 + 255) | The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1) |
| `OUTLINE` | 514 (2 × 256 + 2) | Chunk (2, 0)'s tile mask: columns 0–11 |
| `OUTLINE` | 528 (2 × 256 + 16) | Chunk (1, 1)'s tile mask: rows 0–9, and columns 0–9 of rows 10–14 |
| `GATE` | 1, 2 | Town → zone (entering at chunk 0, tile 105), zone → town (anchored there): hub gates |
| `GATE` | 3, 4 | Zone → floor 1 (anchored at chunk 16, tile 110), floor 1's entrance → zone: links |
| `GATE` | 5 | Floor 1 → floor 2: a floor gate, no anchor (a dungeon's exit is a quota, ADR-0006) |

A chunk of the chunk set with no tile mask is whole. No spawn table, set piece, book or quest is
referenced: those kinds' layouts are later tasks'.

## Format

snforge's `read_json` puts an object's values in the alphabetical order of its keys, flattens
nested arrays, drops empty arrays and writes a one-element array without its length. So each kind
is one flat array, a record per line with fixed columns, next to the names of its columns
(`<kind>_fields`), which the reader checks. No array may be empty. A region's name is a string of
at most 15 characters, in its row.

An outline's row lists `location`, `chunk` (255 for the chunk set) and 15 numbers: bit `c` of
`row_r` is bit `15 r + c` of the record, a chunk `(c, r)` of the set or a tile `(c, r)` of the
chunk.

## Writing it

`contracts/persistent/tests/test_seed.cairo`: `write_seed(registry)` reads the file, packs every
record with the layouts, and writes it as the administrator, regions first, locations before their
outlines. `test_seed_written_and_read_back` writes it and reads it back in one `bundle`. The
deployment scripts that write it to a network are OPS-01's.
