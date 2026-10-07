# CLI-09c — The map editor: the export for the chain

Lot CLI-09c of `docs/briefs/CLI-09-map-editor.md` (§9, §2.7, §6, §10), track CV, 2026-10-07. It builds
against ENG-08's format, on `main` under `spikes/SPK-16-authored-zone/map-format/` (#378): the schema
(`grimworld-export` v1), the kind table, the converter (`records.py`, `convert.py`), the table of
checks (`checks.json`) and the samples with their outputs. Track game owns that folder; this lot reads
it and edits nothing there.

**The owner's rule** (2026-10-05): the editor's JSON (`.grimmap.json`) is its save format only. "Export
for the chain…" writes the on-chain encoding: the packed felts as the Registry records them.

## What exists now

- **The converter, ported** (`client/app/src/editor/export/`):
  - `records.ts` is `records.py`: the packing of `LOCATION`, `OUTLINE`, `GATE`, `QUOTAS`, `ZONE_CHUNK`,
    `BRIDGE`, `CANDIDATES` and `SET_PIECE`, as `bigint` felts with `LIVE` in every part, and the
    Registry's checks of an authored zone (`check_zone`) with the same codes;
  - `convert.ts` is `convert.py`: the plane moved by the origin, the zone's records, the pipeline's
    rules (P-1 reach, P-2 seams, P-3 a connected deck), the order of writes, the set piece's and the
    town's records, the records file (`--out`) and the golden file (`--golden`). Its refusals come in
    the same order as the Python's;
  - `schema.ts` is `schema_check.py`, run on copies of `schema.json` and `kinds.json`. A test holds the
    copies equal to track game's files, and `checks.json` is copied the same way.
- **The editor's map as ENG-08's export, and back** (`export/document.ts`):
  - `toExport` writes the **fitted** zone (D-216): `origin` is the fit's global `(0, 0)` on the editor's
    plane, `size` its rectangle, and `rows` the painted hexes within it (the editor's format 2 spans);
  - `fromExport` opens an export as a map;
  - the editor keeps registry **ids**, as its inspector types them. The export **names** them. A content
    manifest (OPS-01's, the shape of `samples/manifest.json`) maps a name to its id on import and an id
    to its name on export. An id the manifest does not name is written as `#<id>`, a name no manifest
    holds, so that the converter refuses it as any unknown name (E-35).
- **"Export for the chain…"** (top bar, a zone's only). The dialog shows:
  - the content manifest loaded;
  - the validation's counts;
  - the converter's verdict: so many records, or its refusal with its code.

  **Download** writes the converter's **records file**, `<name>.records.json`, enabled only with no
  error and the converter's acceptance. Beside it, "Download the grimworld-export JSON" writes ENG-08's
  export, `<name>.json`.
- **The content manifest** is loaded from the top bar ("Manifest…", on the map list and in the editor)
  and kept for the page.
- **Import**: "Open file…" (or a drop) reads a `grimworld-export` file through the manifest. Without
  one, it is refused with the reason, and the open map is untouched.
- **The converter in the validation.** With a manifest, `validate(doc, manifest)` runs the converter on
  the map's export. Its refusal is an error finding under its check's id from `checks.json`: "The
  converter refuses the export: <code> (<detail>)." So the editor refuses what the converter refuses.
- **What the editor's map now holds** (format 2, each read as 0 or its default when a file lacks it):
  - the map's **region** id (inspector: "Region id");
  - a gate's own **id** ("Gate id", the `GATE` record's id);
  - a feature's **param** ("Landmark or trap skill id");
  - a bridge's **run**: North (as before) or West along the row;
  - a building's **footprint**: `""` draws it from its kind and depth, as before. Offsets from the anchor
    keep a file's footprint when its kind would draw another one. The inspector can set it back to
    "Drawn from its kind".

## The form of the export file

The converter emits a **list of writes**: for each record, its kind, its id and its parts, in the order
of registration (`grimworld-records` v1, `samples/zone.records.json`). The Registry has one entrypoint
per record, `set_record(kind: u8, id: u32, record: Span<felt252>)` (`registry.cairo:41`), and no
batched one (ENG-08 ruling 10). The file is therefore named a **multicall file**: the calls of one
registration, one `set_record` each. A write's calldata is `[kind_id, id, len(parts), ...parts]`.
The editor writes exactly the converter's file. The content pipeline (OPS-01) adds the Registry's
address and sends it; the editor sends nothing.

## Parity (the acceptance)

| Criterion | Shown by | Result |
|---|---|---|
| ENG-08's sample zone, loaded in the editor, validates | `export/document.test.ts` "validates: no error, the converter's checks included"; `verify-editor.mjs` "it validates: 0 errors · 2 warnings" | 0 errors (the warnings: E-12, the sample's walls on earth ground; E-5, its inner link gate) |
| Its export equals the converter's output, felt for felt | `document.test.ts` "exports to the converter's records file, text for text": `recordsFile` = `samples/zone.records.json`, and `golden` = `samples/zone.golden.json`; `verify-editor.mjs` compares the downloaded file | equal, 14 writes; the records file equal text for text (but its `source`, the file's own name) |
| The converter's port writes the committed outputs | `export/convert.test.ts`: zone, town and set piece records files, text for text; the golden file | equal |
| Every case of `checks.json` refused or accepted as the converter does | `convert.test.ts`: each of the 26 registry cases by `test_convert.py`'s mutation, the 3 pipeline cases and the 20 export cases by its edits, each refused with its code; the sample accepted | 49 cases, each refused with its code |
| Import: a `grimworld-export` file opens and round-trips | `document.test.ts` "round-trips": the export of the opened sample is the sample (deep equal), and it opens again to the same map; "survives the editor's own file"; `verify-editor.mjs`: the downloaded JSON is the sample, and opened again it exports the same records | equal |

How a case reaches the editor's checks. The editor runs the converter itself on the map's export (with
a manifest), so any map the converter refuses shows an error under that case's id. A registry case is a
mutation of the records, so most cannot be painted: the editor derives the chunk set, the masks, the gate
index and the bridge count (R-20, R-24, R-25, R-35 hold by construction). The editor's own checks
refuse the paintable cases before the converter does:

- R-13 count above candidates;
- R-14 a spawn point on a wall;
- R-15 over the caps;
- R-18 a gate anchor on a wall;
- E-4 an entry off the floor;
- E-7 an unreachable tile;
- E-20 a door off its footprint's border;
- E-23 an unknown kind.

## The ○ checks, settled by the converter

- **R-12** (what "members" counts): the zone's **chunks**, `count(chunk_set)` in `assert_quotas`. It is
  now an error.
- **R-15** (whether a candidate counts against the caps): **every candidate counts**. A Heart quota's
  candidate counts against the chunk's 2 packs, any other quota's against its 3 objects
  (`assert_chunk`). It is now an error.
- **R-16** (corner walls of an authored chunk): **no check**. The Registry lifts D-134's corners for
  authored zone chunks and keeps them for set pieces only (`set piece: corner not wall`).
- **R-17** (a template's existence): it is **E-35, against the content manifest**. With a manifest, the
  converter's `export: unknown name` is a finding.
- **E-17** (seams "consistent"): it is **P-2**, the records re-assembled across their seams giving the
  painted plane back. That holds by construction: the editor writes the records from the plane. A seam
  with no walkable crossing is not refused by the converter, so the editor's warning is dropped. A
  sealed part stays E-7's (P-1).
- **G-7** (the editor's "Location id" in the file): a **name**, resolved by the manifest. The editor
  keeps the id.

## Choices and why

- **Ids in the editor, names in the export, a manifest between them.** The model's change stays
  additive (format 2 kept, older files read). The records need the ids anyway, and R-27's Heart bounds
  need the manifest's `pack_bounds`. Reversible: holding names in the editor is a format 3 and an
  inspector change.
- **E-5 is a warning.** ENG-08's sample zone anchors its link gate (`to_floor`) inside the zone, and
  the converter and the Registry accept it. As an error, E-5 would refuse what the converter accepts.
  ADR-0006's "anchors on the outline" stays as advice. Reversible: if the programme wants the rule
  held, track game moves the sample's gate and E-5 becomes an error again.
- **A building may keep a file's footprint.** The schema carries footprints, and the sample's hut
  (`make_samples.py`: `(5, -2), (6, -2), (5, -1)`) is not the footprint the editor's kind table draws
  for a hut at depth 1 (`(5, -2), (4, -1), (5, -1)`). Without it, the sample could not be opened as it
  is.
- **A bridge may run West.** The sample's bridge runs along its row (ends `(-13, 6)` and `(-11, 6)`,
  deck `(-12, 6)`). An export bridge of another shape is refused on import, with its reason.
- **Copies of the schema, the kind table and the checks** in the editor's folder, held equal to track
  game's by a test. The app does not import from `spikes/`, and ENG-09's move to `tools/map-format/`
  changes one path in the test.
- **Only the hexes within the fitted rectangle** are exported: the converter refuses a hex outside the
  size. A zone's painted hexes outside its outline and beyond the rectangle are not in the export file,
  and they are lost on a round trip through it (the editor's own file keeps them).
- **A town is not exported** (D-03; §2.7). Its import is refused with the reason. The port converts
  towns and set pieces only for the parity of `checks.json`.

## Deviations

- Brief §5 lists E-5 as an error; it is a warning (above).
- The editor's file gains fields within format 2 (region, gate id, feature param, bridge run, building
  footprint), each read as its default when absent; no format 3.
- The committed fixtures (`fixtures/*.grimmap.json`) are rewritten by their own test to carry the new
  fields.

## Not checked

- The editor's `validate` runs the converter at every debounced change when a manifest is loaded. On
  the sample, the whole browser check shows no lag, but a 15 × 15-chunk zone with a manifest was not
  timed.
- JSON numbers such as `1.0`: Python reads a float that the schema refuses, while JavaScript reads the
  integer 1. The editor never writes one.
