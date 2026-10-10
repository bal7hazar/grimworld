# tools/map-format — the authored zones' export, its schema and its converter

The shared folder of D-215 ruling 9: track game owns the schema and the converter, track CV builds the
map editor (CLI-09) against them. Promoted by ENG-09 from `spikes/SPK-16-authored-zone/map-format/`
(ENG-08's format, ENG-01 §3.5 *Authored zones*), which stays as the spike's history until the editor's
tests read this folder. Python 3, the standard library only.

| Path | What |
|---|---|
| `schema.json` | The editor's export, `grimworld-export` version 1 (JSON Schema 2020-12); `schema_check.py` validates its keywords |
| `kinds.json` | The kind table of the editor's objects (props and their `blocks`, buildings and their default footprints, NPCs, bridges) |
| `checks.json` | **The one table of checks**: the Registry's (`registry`), the content pipeline's (`pipeline`) and the export's (`export`), each with its code |
| `convert.py` | Export → the on-chain records in the order of their writes (and the seed's rows, and the golden file the Registry's tests read) |
| `records.py` | The packers, exactly as the Cairo models pack, and the Registry's checks with the same codes |
| `samples/` | The test region's zone drawn as an authored 3 × 2 zone, a town, a set piece, the content manifest; the converter's outputs |
| `tests/` | Every case of `checks.json` refused with its code; the committed outputs are the converter's; each registry case has its Cairo twin |

```
python3 tools/map-format/convert.py tools/map-format/samples/zone.json \
    --manifest tools/map-format/samples/manifest.json --out out.records.json \
    [--golden zone.golden.json] [--seed zone.seed.json]
python3 -m unittest discover -s tools/map-format/tests -p 'test_*.py'
```

Exit 0 and the records written; exit 1 and one line `refused: <code>: <detail>`, never a traceback.

## What the converter writes

- **Only the hexes inside the fitted rectangle are exported**: the editor paints on an unbounded plane and
  fits the 15 × 15 chunk grid afterwards (D-216); the export's `origin` (its row even) and `size` (1 to 15
  chunks a side) name that rectangle, and a painted hex outside it is refused (`export: hex outside the
  size`). Within it, any chunk set (the outline) is valid.
- **The walkable plane**, one bit a tile (D-215 ruling 1): the painted floor, less each building's
  footprint (but its door) and each blocking prop's hex, **plus every bridge's deck**, written walkable
  whatever is painted beneath it (D-227, ADR-0008 rule 1). A deck tile outside the zone or on a blocked
  hex is refused first. Reachability (P-1) and the seams (P-2) read that plane, so a bridge may be a
  stream's only crossing.
- The records, in this order: `LOCATION` with the marker (bits 144–151, 1 authored), the chunk set,
  `CANDIDATES`, `QUOTAS`, the border masks, each `ZONE_CHUNK` and its `BRIDGE`s, the `GATE`s. The Registry
  checks every rule between two records at the write of either, so the order only makes each write find
  what it checks against.

## What it refuses, beyond the Registry's checks

- **A gate to another location anchors on the outline** (a zone hex with a neighbour outside the zone;
  E-5); a dungeon's entrance (a gate whose destination is a dungeon, the manifest's `location_kinds`) may
  stand inside the chunk set.
- **A building's footprint is authored per building** (the kind table's is the editor's default): it lies
  in the zone, in one piece, its door on its border and on painted walkable ground.
- **Every placement (spawn point, object, candidate tile) on a walkable tile of the interior** (rows and
  columns 1 to 13 of its chunk): a pack's goblins stand within 2 of its tile (R-14, ENG-09).
- Nothing on a bridge's deck or ends (R-37), every deck tile walkable (R-34 extended).

The manifest (`samples/manifest.json`) maps each name an export uses to its registry id, and each
location to its kind (`location_kinds`); OPS-01 writes the real one.
