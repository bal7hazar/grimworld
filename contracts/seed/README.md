# Seed data

Content written into `Registry` through `set_record` (ENG-03). The records' bit layouts are
the models of `grimworld_logic::models` and docs/architecture/ENG-01-interfaces.md §3.5; the files here hold the
fields, not the packed felts.

| File | What |
|---|---|
| `test-region.json` | The test region: one region, its town, one zone, a dungeon of two floors, their gates; the reveal's content (ENG-05): two pack templates, a spawn table, the zone's and floor 1's quotas |

## The test region

| Kind | Id | What |
|---|---|---|
| `REGION` | 1 | "Test Region": town 1, no book, first location 1 |
| `LOCATION` | 1 | The town (a hub: no map, so no size and no entry) |
| `LOCATION` | 2 | A zone: meadow, levels 1–3, 3 × 2 chunks, entered at chunk 0, tile 105 (row 7, column 0), spawn table 1 |
| `LOCATION` | 3 | The dungeon's first floor: cave, levels 3–5, `N` 6, 2 floors, next floor 4, entered at chunk 112, tile 112 (the centre, ENG-01 §3.2), spawn table 1 |
| `LOCATION` | 4 | The second and last floor: `N` 8, spawn table 1 |
| `OUTLINE` | 767 (2 × 256 + 255) | The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1) |
| `OUTLINE` | 514 (2 × 256 + 2) | Chunk (2, 0)'s tile mask: columns 0–11 |
| `OUTLINE` | 528 (2 × 256 + 16) | Chunk (1, 1)'s tile mask: rows 0–9, and columns 0–9 of rows 10–14 |
| `GATE` | 1, 2 | Town → zone (entering at chunk 0, tile 105), zone → town (anchored there): hub gates |
| `GATE` | 3, 4 | Zone → floor 1 (anchored at chunk 16, tile 110), floor 1's entrance → zone: links |
| `GATE` | 5 | Floor 1 → floor 2: a floor gate, no anchor (a dungeon's exit is a quota, ADR-0006) |
| `PACK` | 1 | 2 to 5 goblins: caste 1 (1–2), caste 2 (1–3); level offset 0 |
| `PACK` | 2 | 1 to 3 goblins: caste 3 (1), caste 1 (0–2); level offset +1 |
| `SPAWN_TABLE` | 1 | Template 1 (weight 3), template 2 (weight 1); density 128 (each of a chunk's two pack slots filled with probability 1/2) |
| `QUOTAS` | 2 | The zone's collector camp: collector 1, once (design/18) |
| `QUOTAS` | 3 | Floor 1's exit: gate 5, once (ADR-0006) |

**Quotas (D-145: `QUOTAS` id = the location's id; the layout is ENG-05's,
`grimworld_logic::models::quotas`).** `QUOTAS` 3, floor 1's exit (count 1; gate 5 has no anchor
because a dungeon's exit is a quota, ADR-0006); `QUOTAS` 2, the zone's collector camp (count 1,
design/18; collector 1 is a `COLLECTOR` id the seed does not write yet, its layout being a later
lot's). `QUOTAS` 4, floor 2's boss arena, a set-piece quota, waits for a `SET_PIECE` (an authored
chunk, CM-7 and TOOL-01). The town (1) has no map and no quota. The registry accepts them only after
their location.

**Packs (ENG-05, `models::pack`, `models::spawn_table`).** The castes 1 to 3 the templates name are
`CASTE` ids the seed does not write yet (CBT's lots and DES-06 fill them); the registry checks only
that a template's `min` is not above its `max` (`PackAssert`).

A chunk of the chunk set with no tile mask is whole. No set piece, book or quest is referenced:
those kinds' content is later tasks'.

## Format

snforge's `read_json` puts an object's values in the alphabetical order of its keys, flattens
nested arrays, drops empty arrays and writes a one-element array without its length. So each kind
is one flat array, a record per line with fixed columns, next to the names of its columns
(`<kind>_fields`), which the reader checks. No array may be empty. A region's name is a string of
at most 15 characters, in its row.

An outline's row lists `location`, `chunk` (255 for the chunk set) and 15 numbers: bit `c` of
`row_r` is bit `15 r + c` of the record, a chunk `(c, r)` of the set or a tile `(c, r)` of the
chunk. A pack template's row: `id`, five `(caste, min, max)`, `level` (a signed offset). A spawn
table's: `id`, seven `(template, weight)`, `density`. A location's quotas: `location`, six `(kind,
param, count)` (kind 1 exit, 2 Heart, 3 vein, 4 collector, 5 landmark, 6 set piece).

## Writing it

`contracts/persistent/tests/test_seed.cairo`: `SeedTrait::write(registry)` reads the file, builds
every record as its model, packs it through `content::Record`, and writes it as the
administrator, regions first, locations before their outlines and their quotas. `test_seed_written_and_read_back`
writes it and reads it back in one `bundle`. The deployment scripts that write it to a network are
OPS-01's.
