# ENG-08 — Authored zones: the on-chain format

> The owner's decision **D-214** (2026-10-05, direct): zones get **authored maps**, drawn with a map
> editor and exported in a format the chain can hold. Dungeons stay generated (rooms of several
> kinds, mazes, caves, connected or not, in the manner of Grimscape). Towns stay client-only (D-03,
> D-202) but are drawn with the same editor. The owner's words: "Oui je confirme les cartes dessinées
> des zones avec l'éditeur" (yes, I confirm the drawn maps of zones, with the editor). Record:
> `docs/decisions/2026-10-05-zone-maps-editor.md` ("The format is track game's next design lot
> after ENG-05. The editor is track CV's").
> Order of the track: **ENG-05 merges first** (#348); then **ENG-08** (this lot: the design and the
> format, documents plus a measured spike; profile impl-opus); then **ENG-09** (the engine lot: an
> authored zone's reveal reads its terrain from the Registry instead of generating it). A
> Grimscape-like room-kinds design for dungeons is a later PLAN row, not part of ENG-08.
> Decisions: ADR-0006 (D-106, D-111, D-120, amended by D-208), D-134, D-136, D-144, D-145, D-165,
> D-200, D-207, D-208, D-209, D-210, D-213, D-214, **D-215** (the project manager's rulings on this
> brief's questions, 2026-10-05); pins on Linux only (OPERATIONS.md §3).

## Goal
After this lot **an authored zone has a format, measured, that the chain, the editor and the
converter share**: the records that hold an authored zone in `Registry` (terrain per chunk as packed
bits, features, quota candidates, entry and gate points, the outline), the Registry's content checks
that guard them and that the editor reproduces exactly, what registering a zone and revealing an
authored chunk cost (measured by a spike, against ENG-05's generated reveal), what stays random on
an authored map, and a versioned JSON export with a schema and a converter (JSON → on-chain
records) that track CV can build the editor against. ENG-08
**implements no production contract**: it writes the design into the documents, proves the format
and its costs in a spike, and leaves ENG-09 a design it can build without asking.

## Context
- **What exists, and what D-214 changes.** ADR-0006 §2 says "everything is generated, at reveal
  (D-106)", one engine for zones and dungeons; §3 *Outlines*: a zone's outline is "drawn in advance,
  in the registry", stored as its chunk set and a tile mask per border chunk; *Set pieces*: an
  authored chunk placed by a quota (`SET_PIECE`, ENG-01 §3.5); *Judgement on complexity*: "zones can
  no longer be learnt or mapped by the community", which D-214 reverses for zones. ADR-0006 *Open*
  **CM-7** ("format of authored chunks and outline masks, and the tool to draw them") is the question
  this lot answers; PLAN's **TOOL-01** (the map tool: outlines, authored chunks, written to the
  registry, the world map) is the editor's row. design/18 *Locations* ("Zone: drawn in advance in the
  registry: any shape, any size"), *Biomes* (the order of generation, of which an authored zone keeps
  only quotas and placement, if any), *Features* (the collector: "its place changes with each
  instance"; the gate: "anchor on the outline (zones)"), *Open* TP-2 (a zone's outline public).
- **ENG-05** (#348, open; read it from the branch `origin/hp/grimworld-game/t-0059-eng-05-chunk-reveal`,
  head `1d1e38e` when this brief was written; its brief `docs/briefs/ENG-05-chunk-reveal.md`, and
  ADR-0006 as amended there, D-208 and D-210). What ENG-08 builds beside:
  - `grimworld_logic::types::reveal`: `RevealTrait::reveal(site, ref progress, instance_id, known,
    chunks)`; `Site` (target `N`, 0 in a zone; biome; band; width and height; entry chunk;
    `chunk_set`; `masks`; `anchors`; `quotas`; `tasks`; `spawn`; `packs`; `pieces`) and `Progress`
    (revealed set and count, open edges, `left` of 14 quotas, entropy). `RevealLibrary`
    (`systems/reveal.cairo`) returns each chunk's two words packed as stored; `Instances` writes them.
  - `HostsLibrary` (D-210): a zone's quota hosts drawn **once at `create`** from the entry draw
    (`derive(entropy, domain(instance, 225, REVEAL), 0)`), one bitmap per quota; so a zone's quotas
    are **free of the order of moves** (ADR-0006 §3 as amended).
  - The records ENG-05 laid out (ENG-01 §3.5, `models::{quotas, spawn_table, pack, set_piece}`):
    `QUOTAS` (6 × kind, param, count), `SPAWN_TABLE`, `PACK`, and **`SET_PIECE`, 2 parts: walls
    (bit `15 row + column`, 1 = wall) in part 0; 2 packs (tile, template) and 3 objects in part 1**,
    checked by `SetPieceAssert::assert_legal` (corners wall, D-134; placements on interior floor).
    This is the nearest precedent of an authored chunk's record.
  - The chunk's stored words (ENG-01 §3.2, `models::chunk`): `Terrain` (walls 0–224, 1 = wall;
    dungeon edges 225–228) and `Features` (2 packs at 0 and 64, 3 objects at 128, 160, 192,
    `touched` 224–239); E-3: ≤ 2 packs of ≤ 5 goblins and ≤ 3 objects a chunk.
  - Once ENG-05 merges, **its zone generation stays as the fallback** until the authored path lands
    (ENG-09).
- **The Registry** (`docs/architecture/ENG-01-interfaces.md` §3.5; `docs/briefs/ENG-03-registries.md`):
  `records: Map<(kind, id, part), felt252>`; a record is `parts(kind)` felts (`content::PARTS`, at most
  3 today: `BOOK`); composite kinds keyed by a parent (`OUTLINE`: `location × 256 + chunk`, 255 for the
  chunk set); existence by part 0 (`LIVE`, bit 250); `set_record` one record a call, its checks in
  `RegistryAssert::assert_content` (each model's `assert_legal`); reads `record`, `records`, `bundle`
  (one call, **at most 32 records, `MAX_READ`, "at most 3 parts each"**, `content.cairo`). `LOCATION`
  (type, biome, band, width and height 1–15 chunks, `N`, spawn table, entry chunk and tile, 15 set
  pieces), `OUTLINE`, `GATE` (source anchor chunk and tile; destination entry). A location is at most
  15 × 15 chunks; a tile is `15 row + column` in its chunk; a chunk at an odd `cy` starts on an odd
  global row (ADR-0006 §4).
- **The content bounds ENG-05's reviews deferred** (to fold into this lot's registration design):
  a zone's chunk set within its `width × height` rectangle (#348's review at `1d1e38e`, minor 1:
  the hosts loop is unbounded on a stray bit); a quota's count at most the zone's members (the same
  review, note 4); a Heart template's caste minimums at least 1 (#348's randomness re-audit at
  `1d1e38e`); a dungeon floor's rectangle larger than `N` (ADR-0006 *Outlines*, as amended: "when `N` equals its rectangle's area, the last chunks can be walled in: a content rule is
  proposed"). PLAN's ENG-05 row also defers "gate anchors need a registry index of the gates by
  location (a later lot)".
- **Measured figures to set the authored reveal against** (the spike quotes ENG-05's figures **at its
  merge**, not these):
  - SPK-7 (ADR-0006 *Measured*): a reveal of one chunk **2,455,200** L2 gas, three **5,919,680**, as
    transactions on the local node; generation 390k–447k a chunk in memory.
  - ENG-05 at `1d1e38e` (ENG-01 §10 *Measured by ENG-05* on #348's branch, snforge M): one chunk in
    memory, worst **3,901,320** (meadow) to **4,067,457** (cave), typical **2,830,905**
    (`test_cost_reveal_*`); three chunks 11,856,780; the library call itself 544,510
    (`test_cost_library_call`); `create` revealing 1, 2, 4 chunks 5,277,858 · 7,398,860 · 11,233,690,
    "each chunk after the first about 2.0–2.1 M, its two new slots included" (`test_cost_create_reveals`).
    Its profile (same section): board steps 0.72 M, sides 0.40 M, quotas' draws 0.10 M, placement
    2.10 M (0.38 M with nothing to place).
  - The Registry (ENG-01 §3.5, ENG-03): `set_record` of a new 3-part record **2,486,480** (whole call in
    snforge) and **3,489,099** as a transaction with §10's prices (D); `bundle` of one 3-part record
    140,800 in execution, "about 36,000 a slot", a call about 0.12–0.14 M (C).
- **Class sizes** (ENG-01 §1.3; D-200: 50 % of the 81,920-felt limit is the default; its exceptions
  `ExecutorLibrary` ≤ 80,420 felts and `TickLibrary` ≤ 75 %; **D-209**: `RevealLibrary` ≤ 50.5 %,
  `Instances` ≤ 51 % for ENG-05, on the condition that the bit-parallel placement lot, ENG-05b, brings
  both under 50 % before ENG-07). At `1d1e38e`: `RevealLibrary` 41,131 felts **50.21 %**, `Instances`
  41,247 **50.35 %**, `HostsLibrary` 5,033 6.14 % (ENG-01 §1.3 on #348's branch). The authored path
  adds code to one of them or to a new class: the spike measures how much.
- **Cost rules.** D-144 (`docs/decisions/2026-09-29-eng-04-budgets.md`, decision 1): a measured
  replacement up to +10 % is the orchestrator's; beyond, **or on the expedition's path (`play`, the
  actions sent alone, `enter`, `leave`, `travel_back`) at any size**, the project manager's; an
  authored reveal runs in `create` (`enter`) and `leave` to a location, so ENG-09's figures go to the
  project manager; ENG-08's spike states them in advance. D-207 (ENG-01 §9.2): 40 M is a batch target,
  not a protocol limit; the worst tick measured, 45,999,941, accepted as a one-tick batch. The
  transaction cap: 1.1 × 10⁹ L2 gas (docs/CAIRO.md §1), which bounds what one registration
  transaction can write.
- **What the fog is today** (ADR-0006 §2, amended by D-208): every chunk's word is fixed at entry;
  the fog is "0 chunks deep for a client that reads the chain". An authored zone's terrain is public
  before any instance: the format hides nothing the fog held, and the community can map a zone again.
  **D-213** (`docs/decisions/2026-10-05-exploration-display.md`): the client draws a tile only once it
  has entered the adventurer's sight; the chain still reveals whole chunks. An authored zone keeps
  both rules: the export's layers are drawn under the same fog on the client.
- **Towns** (D-03: hubs have no on-chain geometry; D-202: a hub is lived like a zone on the client):
  the editor draws them in the same format; nothing of a town's map goes on chain.
- **The seed's format** (`contracts/seed/README.md`, `test-region.json`): flat arrays read by snforge's
  `read_json` (alphabetical keys, no empty arrays), the test zone 3 × 2 chunks with two border masks.
  It is a test fixture shaped by snforge, not an editor format; the converter may emit it.
- **Track CV** (D-192): `client/sim/**` is lent to track CV; the editor and
  the client's reading of the export are CV's. ENG-08 defines the format; CV builds against it.
- docs/CAIRO.md §2 (tests first, gas a test result, measured on the worst case), §7 (layers, scoped
  functions, every stored entity a model); COMMON.md; the spike's precedent `spikes/SPK-15/`
  (`README.md`: method, pairs, two clean builds, D-154).
- **The Registry checks no map record's content today.** At `origin/main`,
  `RegistryAssert::assert_content` (`contracts/persistent/src/systems/registry.cairo`, from line 245)
  bounds `MODIFIER`, `ARMOR_SET`, `SKILL`, `ITEM` and `CASTE` only; the map records (`LOCATION`,
  `OUTLINE`, `GATE`) have only their models' pack-time checks (a field wider than its layout refused).
  #348 adds the `assert_legal` of `QUOTAS`, `SPAWN_TABLE`, `PACK` and `SET_PIECE`. An authored zone's
  records need checks of their own, and the editor must reproduce exactly those (deliverable 2).

## Decided before the lot starts
The questions this brief raised were answered on 2026-10-05; ENG-08 builds on them and does not
reopen them. Each is reversible by its decider; a measure of the spike that contradicts one goes back
to that decider with the figure.

| # | Ruling | By |
|---|---|---|
| 1 | **Only the walkable plane on chain**; visual tile kinds are client-only; planes are reserved by a format version. Condition: if a rule needs more than walkable (sight blocking that differs from walking, e.g. water), it becomes a **reserved plane on chain**, never a client guess. ENG-08 lists which rules read terrain today | project manager, **D-215** |
| 2 | **The authored terrain is copied into the instance's chunk at reveal**, as today: ENG-01 §3.2 and ENG-07's window unchanged. Reversed by a measure that puts the copy's slot on the expedition's path beyond what the project manager accepts (D-144) | orchestrator |
| 3 | **Quotas are drawn among authored candidates**: the author marks candidate places per quota; the draw at entry picks among them (design/18 wants the collector's place to change each instance; the author keeps level-design control). **Order-free**, as D-208 and D-210 | project manager, **D-215** |
| 4 | **Packs: authored spawn points**, their level (within the zone's band) and their count drawn at entry | project manager, **D-215** |
| 5 | **D-134's corner walls are lifted for authored chunks** if no other code reads them (the spike checks); kept for generated chunks and set pieces | project manager, **D-215** |
| 6 | **The chunk set's border masks only**: an authored zone keeps `OUTLINE` as today, its chunk set and the tile masks of its border chunks, and gains no other outline record; the converter derives the masks from the authored walls and refuses a mask that disagrees with them | orchestrator |
| 7 | **The generated zone path stays as the fallback** until every zone is authored | project manager, **D-215** |
| 8 | **The four deferred bounds are built by ENG-R1c** (they protect today's generated zones); **ENG-09 reuses them for authored zones**, extending a bound only where an authored record changes what it reads (a quota's count against its authored candidates, ruling 3). ENG-08 specifies how they apply to an authored zone and builds none of them | orchestrator |
| 9 | **`tools/map-format/` is the shared folder**: track game owns the schema and the converter, track CV consumes them for the editor (CLI-09); promoted there by ENG-09 from the spike | project manager, **D-215** |
| 10 | **No batched registration entrypoint**: an account's multicall writes many records in one transaction; the spike measures how many fit in one | project manager, **D-215** |

## Additions decided since the brief merged (#357), folded into the lot

| # | Addition | By |
|---|---|---|
| A1 | **D-216**: the editor paints on an unbounded plane and lays the 15 × 15 chunk grid afterwards, at the origin that covers the painted hexes with the fewest chunks. The format takes any chunk set at a chosen origin (not starting at 0, 0) and states the origin's constraints: its row even (the rows' parity), its column free, the map within `[0, 15 width) × [0, 15 height)` after the move, ±32,767 on the editor's plane | the owner, 2026-10-05 |
| A2 | **The editor's objects** (track CV): NPC (hex, template, facing), building (kind, footprint, anchor, door on the footprint's border), prop (kind, hex, variant, facing or flip), in the export and the schema; on chain only through the walkable plane (a footprint unwalkable but its door; a blocking prop's hex unwalkable). The kind table from CLI-09e §4 (#367, merged) | the orchestrator under D-215 |
| A3 | **D-217**: bridges on two levels. Format version 1 reserves a bridge plane: each bridge's deck hexes and two end hexes, in the export and on chain, a one-hex deck valid; its storage measured. The rules are ENG-08b's | the owner, 2026-10-05 |
| A4 | **D-220**: a content bound on a zone's total quota draws, sized so that the worst legal plan stays under 100,000,000 L2 gas, from ENG-05's measure (98,153,254, `test_hosts_worst_half`) | the project manager, 2026-10-06 |
| A5 | The deferred content bounds (ruling 8) are ENG-R1c's; ENG-08's checks reuse them: count ≤ members; chunk set ⊆ rectangle; a Heart template with a minimum ≥ 1 and a maximum ≥ 1; a floor rectangle larger than `N` | the orchestrator |
| A6 | The PLAN rows of ENG-05's bookkeeping in this lot's first commit; the fixed dungeon outline as two rows, ENG-10a and ENG-10b, queued after ENG-08 (the residue blocks any non-test deployment until ENG-10b merges; ENG-10b's gate a re-audit measuring it at zero) | the project manager and the Overseer, 2026-10-07 |

## Scope
- In (the deliverables):
  1. **The on-chain format of an authored zone**, written into ENG-01 §3.5 as proposed layouts:
     - **terrain per chunk**: the walkable plane only (ruling 1): 225 bits, one felt with `LIVE`, the
       convention of `Terrain` and `SET_PIECE` (1 = wall); name exactly what fits in a felt (225 tile
       bits, bits 225–249 free, `LIVE` at 250) and **how many felts a chunk takes**, the spike measuring
       the packing, the read and the decode; how a later version adds a reserved plane (ruling 1's
       condition) without moving the first;
     - **which rules read terrain today**, a table (ruling 1): movement and the flood (design/02, D-127),
       line of sight ("walls block", design/04), placement and traps' tiles (design/19 §5.11), sight
       and the window (ADR-0006 §4), each with what it reads (walkable only, or more) and its source;
     - **features**: **authored spawn points** (tile and template, as `SetPack`; ruling 4) and objects
       (chest, node, terrain trap, landmark, lever, as `Object`) within E-3; **quota candidates**, the
       places the author marks per quota (ruling 3); **entry and gate points** (the entry chunk and tile
       `LOCATION` holds; gate anchors, with how a chunk names the gates it anchors, which answers the
       deferred gate index);
     - **the outline**: the chunk set (void chunks, the world map, TP-2) and its border chunks' tile
       masks, as today (ruling 6);
     - **the record shape**: a new kind or an extension of `SET_PIECE`/`OUTLINE`, its id scheme
       (composite, keyed by the location and the chunk, as `OUTLINE`), its parts (≤ 3 keeps `bundle`'s
       bound of 32 records "at most 3 parts each"; more is a change of ENG-01 §4.5 to state), its
       `LOCATION` marker (how the reveal tells an authored zone from a generated one, ruling 7).
  2. **Registration and the Registry's content checks for authored map records**: the order of writes
     and, as `...Assert` rules to add in `RegistryAssert::assert_content` (written into ENG-01 §3.5's
     *The writer's checks*; built by ENG-09), **every content check of an authored map record**, since
     today the Registry checks none (*Context*). **The editor reproduces exactly those checks**: the same
     list, the same refusals, one table shared by the brief's reader, ENG-09 and track CV:
     - each authored chunk's local checks (fields within their widths; spawn points, objects and quota
       candidates on walkable tiles; within E-3; the corners per ruling 5);
     - the checks between records an authored zone adds (a candidate per quota at least its count; a
       spawn point's template named by the location's content; gates anchored on walkable tiles);
     - **the four deferred bounds** (ruling 8: ENG-R1c builds them, ENG-09 reuses them): the chunk set ⊆
       the `width × height` rectangle; a quota's count ≤ the zone's members, and for an authored zone ≤
       its candidates; a Heart template's caste minimums ≥ 1; a dungeon floor's `width × height` > `N`;
       for each, which record's write checks it and what it reads, **whatever the order of writes**
       (CBT-02c's precedent, DS-18) or a stated order;
     - what stays the content pipeline's (OPS-01) and the converter's because no record holds it alone:
       every walkable tile of the zone reachable from its entry, every gate anchor and quota candidate
       reachable, seams between neighbouring chunks consistent.
  3. **Cost, measured by the spike, not estimated** (L2 gas, snforge M and, where the node gives it, D):
     - **registration**, once per zone: one authored chunk's record written new (and rewritten), its
       content checks apart; a whole zone (at least the test zone's 5 chunks and the largest zone the
       format allows, 15 × 15) as the sum of measured parts **and** one measured multicall registration;
       **how many chunk records fit one transaction** under 1.1 × 10⁹ (ruling 10);
     - **the reveal of an authored chunk as a read**: the records read (in `create`'s `bundle` or a
       call of their own), the decode, the draws left (quota candidates at entry, ruling 3; each spawn
       point's level and count, ruling 4), and the chunk's two words written, the terrain copied into
       the instance's slot (ruling 2) and that write measured apart, **against today's generated
       reveal**: the spike quotes ENG-05's measured figures at merge (in memory, worst and typical;
       `create` per chunk) and gives the difference;
     - **classes under D-200**: the authored path's CASM felts measured in a spike class, and where
       ENG-09 can put it (`RevealLibrary`, `Instances`, `HostsLibrary` or a new class) against 50 % and
       D-209's exceptions and condition, the generated fallback kept (ruling 7).
  4. **What stays random on an authored map, as decided** (rulings 3 and 4): the quota draw among the
     authored candidates at entry, and each spawn point's level (within the band) and count at entry;
     from what each draw takes its word (the entry draw, a domain of its own, never a value another
     decision uses: ADR-0002 rule 2) and how it extends `HostsLibrary` or replaces it for an authored
     zone. **ADR-0006's levers stay closed**: no order of moves, no side entered and no reveal chooses
     where anything lands or what it holds (D-208); an order-independence test proves it. The lot
     states what a modified client can still gain, in one sentence with a figure, as D-208's re-audit
     did for dungeons.
  5. **The JSON export the editor writes**: versioned (a `format` name and an integer `version`; the
     rule for a change that breaks readers), with a **JSON Schema** file and a **converter** (JSON →
     the on-chain records, and to the seed's rows) defined and prototyped in the spike, laid out as
     they will live in `tools/map-format/` (ruling 9; ENG-09 promotes them), so that track CV can build
     the editor (CLI-09) against it. It covers: the zone's identity and `LOCATION` fields (region,
     biome, band, rank, size); the chunk set; the tiles in global coordinates with the hex layout pinned
     (pointy or flat, the row offset parity of ADR-0006 §4, `15 cy + cx`, `15 row + column`); the
     walkable layer (on chain) and the **client-only layers** (visual tile kinds, decoration, props;
     ruling 1); spawn points, objects, quota candidates, entry and gates (by name, the converter
     resolving registry ids from a content manifest); **set pieces** (one authored chunk, for dungeons'
     `SET_PIECE` quotas: CM-7 asks for them too); and **towns** (the same file, `kind` town:
     **everything client-only**, D-03, D-202; the converter emits no town terrain, only what `LOCATION`
     and the hub gates already hold). The converter refuses exactly what deliverable 2's checks refuse,
     and checks the pipeline's rules (reachability, seams) itself.
  6. **D-214 against ADR-0006 and D-106.** D-214 reverses ADR-0006 §2 and D-106 ("everything is
     generated") **for zones only**. ENG-08 states it in ADR-0006 and updates: ADR-0006 §2 (generated
     at reveal: dungeons; zones authored), §3 *Outlines*, *Set pieces*, *Judgement on complexity*
     ("zones can no longer be learnt" reversed), CM-7 closed or narrowed, each change marked D-214 and
     D-215; design/18's zone rows (*Locations*: zones authored; *Biomes*: the order of generation for
     generated locations only; *Features*: the pack, collector and gate rows per rulings 3 and 4;
     *Open* TP-2 answered); and **ENG-05's text where it calls zones generated**: ENG-01's sections
     (§3.2, §3.5, §10 where they name a zone's generation) and the doc comments of ENG-05's modules
     (`contracts/logic/src/types/reveal*.cairo`, `models/{quotas,set_piece,chunk}.cairo`,
     `systems/{reveal,hosts}.cairo`), **comments only, and only once #348 has merged**.
  7. **The documents and the decision record**: ENG-01 §3.5 (the new layout, the checks of deliverable
     2, the parts bound if it moves; §1.3 only if a class is proposed; §10 the spike's figures as
     proposed rows, marked "SPK-16, not built"); and **a decision record** for the format
     (`docs/decisions/2026-10-xx-authored-zones-format.md`, "proposed", its number given by the project
     manager at acceptance), citing D-214 and D-215 and the orchestrator's rulings, and listing any
     question the spike raises with its recommendation and decider.
- **The spike**, `spikes/SPK-16-authored-zone/` (SPK-16 is the next free number: `spikes/` and PLAN
  go up to SPK-15), on SPK-15's pattern: its own `Scarb.toml` depending on `grimworld_logic` (and
  `grimworld_persistent` if it measures `Registry`) **by path, at `origin/main` with ENG-05 merged**;
  its own `src/` (the prototype record, its packer and checks, the authored reveal and its draws);
  `tests/` (pairs of tests that differ by the measured call alone, CBT-02d's method; two clean builds,
  D-154); **a test that no code but the generation reads D-134's corner walls** (ruling 5: the window's
  assembly, the tick, the flood, `SetPieceAssert`; or the list of what does); `map-format/` (the JSON
  Schema, the converter in Python 3 with the standard library, as the repository's scripts, and its
  tests); one sample zone (the test region's zone drawn as an authored 3 × 2 zone) and one sample
  town and set piece; a golden file of the converter's output read back by a Cairo test (small: the
  build-size rule); `README.md` with the method, the commands and their output. The spike measures
  `Registry` and `RevealLibrary` **as they are**: a record of the new shape may be measured through an
  existing kind of the same part count (`SET_PIECE`, 2 parts; `BOOK`, 3) and its checks apart, each
  proxy named.
- Out: any production contract code (`contracts/**` but the doc comments of deliverable 6: ENG-09's);
  the four bounds' code (ENG-R1c); `tools/map-format/` itself (ENG-09 promotes the spike's files);
  the editor and the client's reading of the export (track CV, CLI-09, TOOL-01); the deployment
  scripts (OPS-01); the Grimscape-like room kinds of dungeons (a later PLAN row); the bit-parallel
  placement (ENG-05b); ENG-07's window and play; `client/sim/**`.
- Allowlist:
  - `spikes/SPK-16-authored-zone/**` (new);
  - `docs/design/18-rooms.md` (its zone rows and TP-2);
  - `docs/architecture/ENG-01-interfaces.md` §3.5, and §1.3, §3.2, §4.5, §10 only as deliverables 6
    and 7 say;
  - `docs/architecture/ADR-0006-chunked-maps.md`;
  - `docs/decisions/2026-10-xx-authored-zones-format.md` (new, a proposal);
  - **once #348 has merged**, the doc comments (`//!`, `///`) of ENG-05's modules named in deliverable
    6, where they call zones generated: comments only, no code line.
  Anything else is an escalation. **Overlaps**: ENG-05 (#348) must have merged (ENG-01, ADR-0006 and
  the code the spike depends on); ENG-05b (bit-parallel placement, `contracts/logic/src/types/reveal*`,
  class sizes) may run beside: the spike reads `contracts/` and ENG-08 edits only doc comments there,
  so whichever of the two merges second merges `origin/main`; a figure ENG-05b moves is re-quoted at
  ENG-08's merge if ENG-05b merged first. **ENG-R1c** (the four bounds, ruling 8) and **CLI-03n**
  (track CV, D-213, design/18's perception and display) may run beside: ENG-08 edits only design/18's
  zone rows and TP-2. Documents: whichever of ENG-08, CLI-03n and a bookkeeping lot merges second
  merges `origin/main`.

## Interfaces
- **Frozen, read only**: ENG-01 §3.2 (the chunk's stored words, `Instances`' layout), §5 (events,
  frozen, D-193), `IRevealLibrary`, `IHostsLibrary`, `IRegistryRead` (`record`, `records`, `bundle`) and
  `IRegistryAdmin.set_record` as merged (no batched entrypoint, ruling 10).
- **Proposed by ENG-08, built by ENG-09**: the authored chunk's record (kind, id, parts, bit layout,
  model in `grimworld_logic::models`), its `...Assert` and the Registry's content checks of
  deliverable 2, the four bounds as they apply to an authored zone (built by ENG-R1c for generated
  zones, reused by ENG-09; ruling 8), the `LOCATION` marker, the draws at entry (rulings 3 and 4) and
  the reveal's authored branch (what `Site` gains or what new entry the library takes). A change of a
  frozen interface (a `Registry` entrypoint, `MAX_READ`, an event) is named as such and goes to the
  project manager.
- **For track CV** (CLI-09): the schema, the converter's command line, the checks' table of
  deliverable 2 and the samples, in `spikes/SPK-16-authored-zone/map-format/` until ENG-09 moves them
  to `tools/map-format/` (ruling 9).

## Acceptance criteria
- [ ] AC-1 **Inventory first**: the report opens with a table of the seven deliverables, each with
      where it lives after this lot (document and section, or spike file) and the test or measure that
      holds it.
- [ ] AC-2 The format: the authored chunk's record in ENG-01 §3.5 with its bit layout, what fits in a
      felt, the felts a chunk takes (the walkable plane only, the reserved planes' rule), the `LOCATION`
      marker, spawn points, quota candidates, the gate points; the table of the rules that read
      terrain; a spike model packs and unpacks it, round-trip and bit tests.
- [ ] AC-3 The Registry's content checks of authored map records, the four bounds' authored form
      among them, written with the record that checks it and what it reads; each prototyped in the spike
      with a refusal test; **the converter refuses exactly the same cases** (one shared table, a test
      that runs each case through both).
- [ ] AC-4 Cost: registration (one record, a zone, records per transaction) and the authored reveal
      against ENG-05's measured reveal at merge, every figure with its command and output, every
      derived figure marked so with its terms; the class-size forecast against D-200 and D-209.
- [ ] AC-5 Randomness as decided: the quota draw among candidates and the spawn points' level and
      count, each from its own domain at entry; an order-independence test; the sentence with a figure.
- [ ] AC-6 D-134's corners: the spike's test of what reads them, and ruling 5 applied or sent back to
      the project manager with that list.
- [ ] AC-7 The JSON export: the schema, the converter and the samples (zone, town, set piece); the
      converter's output decoded by a Cairo test equals the sample; the converter refuses an unreachable
      tile, an inconsistent seam and each content check's case.
- [ ] AC-8 The documents of deliverables 6 and 7 updated: D-214's reversal of ADR-0006 §2 and D-106
      for zones stated; ENG-05's text that calls zones generated corrected (after #348 merges); the
      decision record proposal written.
- [ ] AC-9 The Cairo builds capped; the committed figures from a Linux run; `scripts/prepush.sh` green;
      CI green.

## Verification
```
cd spikes/SPK-16-authored-zone
prlimit --as=8589934592 ../../scripts/lock.sh --heavy scarb build
prlimit --as=8589934592 snforge test
python3 map-format/convert.py samples/zone.json --out samples/zone.records.json
python3 -m unittest discover -s map-format/tests -p 'test_*.py'
cd ../..
scripts/prepush.sh
```
The figures committed (the spike's outputs, the README's tables, ENG-01's proposed rows) come from a
Linux run (the VPS or CI), never the Mac (OPERATIONS.md §3). A Cairo build or measure runs capped at
`prlimit --as=8589934592`; a build that the cap kills is a stop signal: find the cause statically and
shrink, never rerun uncapped.

## Rules for ENG-08's thread
- One push, with the ssh keepalive:
  `git -c core.sshCommand='ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=40' push …`.
- `scripts/prepush.sh` runs uncapped (the hook's steps are measured well under 8 GB); the Cairo
  builds and measures inside the spike run capped as above.
- `git rebase origin/main`, exactly that and alone in the call, only before the first push; after a
  push, merge `origin/main`; a rebase that stops on a conflict is reported to the orchestrator, not
  driven. Never skip hooks, never force-push.
- An untracked file of your own worktree is removed with `git clean -f -- <exact path>` only; never
  `git clean` with `-d`, `-x` or `-X`.
- No figure that was not measured; a derived figure is called one.

## Report
The report as in `docs/briefs/COMMON.md` §7: the inventory (AC-1); the format and the rules that read
terrain; the Registry's checks and the converter's; the cost tables (registration, reveal against
ENG-05, classes) with their commands; the draws at entry and the order-independence test; D-134's
corners; the export, its schema and converter; the documents changed; any question the spike raises,
with its recommendation and decider.

## Audit
A document and spike lot: a review, no audit by default. The orchestrator decides at the close; the
draws at entry of rulings 3 and 4 are new randomness, so a short randomness lens reads them (order
independence, the domain of each draw, the sentence with a figure) before ENG-09 builds them.

## Open questions
None left: every question this brief raised is decided above (D-215 and the orchestrator's rulings,
2026-10-05). A question the spike raises goes into ENG-08's report and its decision record, with a
recommendation and its decider.
