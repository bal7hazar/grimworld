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
> D-200, D-207, D-208, D-209, D-210; pins on Linux only (OPERATIONS.md §3).

## Goal
After this lot **an authored zone has a format, measured, that the chain, the editor and the
converter share**: the records that hold an authored zone in `Registry` (terrain per chunk as packed
bits, features, quota places, entry and gate points, the outline), the content checks that guard
them, what registering a zone and revealing an authored chunk cost (measured by a spike, against
ENG-05's generated reveal), what stays random on an authored map, and a versioned JSON export with
a schema and a converter (JSON → on-chain records) that track CV can build the editor against. ENG-08
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

## Scope
- In (the deliverables):
  1. **The on-chain format of an authored zone**, written into ENG-01 §3.5 as proposed layouts:
     - **terrain per chunk**: the walkable plane (225 bits, one felt with `LIVE`, the convention of
       `Terrain` and `SET_PIECE`: 1 = wall) and **kind bits** if Open question 1 keeps any on chain
       (each bit of kind a further 225-bit plane, so one felt each); name exactly what fits in a felt
       (225 tile bits, bits 225–249 free, `LIVE` at 250) and **how many felts a chunk takes**, the
       spike measuring the packing, the read and the decode;
     - **features**: authored packs (tile and template at least, as `SetPack`) and objects (chest,
       node, terrain trap, landmark, lever, as `Object`) within E-3; **quota places** (where a quota may
       land: Open question 3); **entry and gate points** (the entry chunk and tile `LOCATION` holds; gate
       anchors, with how a chunk names the gates it anchors, which answers the deferred gate index);
     - **the outline**: what an authored zone keeps of `OUTLINE` (the chunk set: void chunks, the
       world map, TP-2) and whether its border tile masks are still written (Open question 6);
     - **the record shape**: a new kind or an extension of `SET_PIECE`/`OUTLINE`, its id scheme
       (composite, keyed by the location and the chunk, as `OUTLINE`), its parts (≤ 3 keeps `bundle`'s
       bound of 32 records "at most 3 parts each"; more is a change of ENG-01 §4.5 to state), its
       `LOCATION` marker (how the reveal tells an authored zone from a generated one).
  2. **Registration**: the order of writes, the validators and the content checks, as `...Assert`
     rules to add (written into ENG-01 §3.5's *The writer's checks*; built by ENG-09):
     - each authored chunk's local checks (fields within their widths; placements on floor; within
       E-3; whatever D-134 still requires, Open question 5);
     - **the four deferred bounds**: the chunk set ⊆ the `width × height` rectangle; a quota's count ≤
       the zone's members (or the places it may land, under Open question 3); a Heart template's caste
       minimums ≥ 1; a dungeon floor's `width × height` > `N`; for each, which record's write checks
       it and what it reads, **whatever the order of writes** (CBT-02c's precedent, DS-18: a check that
       holds when the other record is written later) or a stated order;
     - what stays the content pipeline's (OPS-01) and the converter's because no record holds it alone:
       every walkable tile of the zone reachable from its entry, every gate anchor reachable, seams
       between neighbouring chunks consistent.
  3. **Cost, measured by the spike, not estimated** (L2 gas, snforge M and, where the node gives it, D):
     - **registration**, once per zone: one authored chunk's record written new (and rewritten), its
       content checks apart; a whole zone (at least the test zone's 5 chunks and the largest zone the
       format allows, 15 × 15) as the sum of measured parts **and** one measured multi-record
       registration; how many chunk records fit one transaction under 1.1 × 10⁹;
     - **the reveal of an authored chunk as a read**: the records read (in `create`'s `bundle` or a
       call of their own), the decode, the placement left (drawn or copied, Open questions 3 and 4),
       and the chunk's two words written, **against today's generated reveal**: the spike quotes
       ENG-05's measured figures at merge (in memory, worst and typical; `create` per chunk) and gives
       the difference; whether the instance keeps copying the terrain into its own slot (Open
       question 2), with both measured if both are open;
     - **classes under D-200**: the authored path's CASM felts measured in a spike class, and where
       ENG-09 can put it (`RevealLibrary`, `Instances`, `HostsLibrary` or a new class) against 50 % and
       D-209's exceptions and condition.
  4. **What stays random on an authored map**: quota placement **drawn** (ENG-05's hosts, D-208,
     D-210) **or authored**, and the packs (the spawn table drawn per chunk, or authored spawn points
     with their level and count drawn). ENG-08 **recommends, with reasons**; the project manager
     decides (Open questions 3 and 4). Either way **ADR-0006's levers stay closed**: no order of moves,
     no side entered and no reveal chooses where anything lands (D-208); what is drawn is drawn once at
     entry or from the chunk's word fixed at entry. The recommendation states what a modified client
     can still gain, in one sentence with a figure, as D-208's re-audit did for dungeons.
  5. **The JSON export the editor writes**: versioned (a `format` name and an integer `version`; the
     rule for a change that breaks readers), with a **JSON Schema** file and a **converter** (JSON →
     the on-chain records, and to the seed's rows) defined and prototyped in the spike, so that track CV
     can build the editor against it. It covers: the zone's identity and `LOCATION` fields (region,
     biome, band, rank, size); the chunk set; the tiles in global coordinates with the hex layout pinned
     (pointy or flat, the row offset parity of ADR-0006 §4, `15 cy + cx`, `15 row + column`); the
     on-chain layers and the **client-only layers** (decoration, visual tile kinds, props); features,
     quota places, entry and gates (by name, the converter resolving registry ids from a content
     manifest); **set pieces** (one authored chunk, for dungeons' `SET_PIECE` quotas: CM-7 asks for them
     too); and **towns** (the same file, `kind` town: **everything client-only**, D-03, D-202; the
     converter emits no town terrain, only what `LOCATION` and the hub gates already hold). The
     converter refuses what the content checks of 2 would refuse, and checks the pipeline's rules of 2
     (reachability, seams) itself.
  6. **The documents**: design/18's zone rows (*Locations*: zones authored, D-214; *Biomes*: the order
     of generation for generated locations only; *Features*: the collector's and the gate's rows as
     Open question 3 is decided; *Open* TP-2 answered); ENG-01 §3.5 (the new layout, the checks, the
     parts bound if it moves; §1.3 only if a class is proposed; §10 the spike's figures as proposed rows,
     marked "SPK-16, not built"); ADR-0006 (authored zones beside generated locations: §2's "everything
     is generated" narrowed to dungeons, §3 *Outlines* and *Set pieces*, *Judgement on complexity*'s
     "zones can no longer be learnt", CM-7 closed or narrowed; marked D-214); and **a decision record
     proposal** for the format (`docs/decisions/2026-10-xx-authored-zones-format.md`, "proposed", its
     number given by the project manager at acceptance), listing every open question with its
     recommendation and decider.
- **The spike**, `spikes/SPK-16-authored-zone/` (SPK-16 is the next free number: `spikes/` and PLAN
  go up to SPK-15), on SPK-15's pattern: its own `Scarb.toml` depending on `grimworld_logic` (and
  `grimworld_persistent` if it measures `Registry`) **by path, at `origin/main` with ENG-05 merged**;
  its own `src/` (the prototype record, its packer and checks, the authored reveal); `tests/` (pairs
  of tests that differ by the measured call alone, CBT-02d's method; two clean builds, D-154); the
  JSON Schema, the converter (Python 3, standard library, as the repository's scripts) and its tests;
  one sample zone (the test region's zone drawn as an authored 3 × 2 zone) and one sample town and set
  piece; a golden file of the converter's output read back by a Cairo test (small: the build-size
  rule); `README.md` with the method, the commands and their output. The spike measures `Registry` and
  `RevealLibrary` **as they are**: a record of the new shape may be measured through an existing kind
  of the same part count (`SET_PIECE`, 2 parts; `BOOK`, 3) and its checks apart, each proxy named.
- Out: any production contract (`contracts/**`: ENG-09's); the editor and the client's reading of the
  export (track CV, TOOL-01); the deployment scripts (OPS-01); the Grimscape-like room kinds of dungeons
  (a later PLAN row); the bit-parallel placement (ENG-05b); ENG-07's window and play; `client/sim/**`.
- Allowlist:
  - `spikes/SPK-16-authored-zone/**` (new);
  - `docs/design/18-rooms.md` (its zone rows and TP-2);
  - `docs/architecture/ENG-01-interfaces.md` §3.5 (and §1.3, §4.5, §10 only as deliverable 6 says);
  - `docs/architecture/ADR-0006-chunked-maps.md`;
  - `docs/decisions/2026-10-xx-authored-zones-format.md` (new, a proposal).
  Anything else is an escalation. **Overlaps**: ENG-05 (#348) must have merged (ENG-01, ADR-0006 and
  the code the spike depends on); ENG-05b (bit-parallel placement, `contracts/logic/src/types/reveal*`,
  class sizes) may run beside: the spike reads, never edits, `contracts/`; a figure ENG-05b moves is
  re-quoted at ENG-08's merge if ENG-05b merged first. **CLI-03n** (track CV, D-213) also updates
  design/18 (perception, display): ENG-08 edits only its zone rows and TP-2. Documents: whichever of
  ENG-08, CLI-03n and a bookkeeping lot merges second merges `origin/main`.

## Interfaces
- **Frozen, read only**: ENG-01 §3.2 (the chunk's stored words, `Instances`' layout), §5 (events,
  frozen, D-193), `IRevealLibrary`, `IHostsLibrary`, `IRegistryRead` (`record`, `records`, `bundle`) and
  `IRegistryAdmin.set_record` as merged.
- **Proposed by ENG-08, built by ENG-09**: the authored chunk's record (kind, id, parts, bit layout,
  model in `grimworld_logic::models`), its `...Assert`, the four bounds' checks, the `LOCATION` marker,
  and the reveal's authored branch (what `Site` gains or what new entry the library takes). A change
  of a frozen interface (a new `Registry` entrypoint, `MAX_READ`, an event) is named as such and goes
  to the project manager.
- **For track CV**: the schema (`spikes/SPK-16-authored-zone/schema/`, moved by Open question 9),
  the converter's command line, and the samples.

## Acceptance criteria
- [ ] AC-1 **Inventory first**: the report opens with a table of the six deliverables, each with where
      it lives after this lot (document and section, or spike file) and the test or measure that holds
      it.
- [ ] AC-2 The format: the authored chunk's record in ENG-01 §3.5 with its bit layout, what fits in a
      felt, the felts a chunk takes, the `LOCATION` marker, the gate points; a spike model packs and
      unpacks it, round-trip and bit tests.
- [ ] AC-3 Registration: every content check of deliverable 2, the four deferred bounds among them,
      written with the record that checks it and what it reads; each prototyped in the spike with a
      refusal test.
- [ ] AC-4 Cost: registration (one record, a zone) and the authored reveal against ENG-05's measured
      reveal at merge, every figure with its command and output, every derived figure marked so with its
      terms; the class-size forecast against D-200 and D-209.
- [ ] AC-5 Randomness: the recommendation on quota placement and packs, with reasons and the sentence
      with a figure; ADR-0006's levers shown closed (what is drawn, from what, when).
- [ ] AC-6 The JSON export: the schema, the converter and the samples (zone, town, set piece); the
      converter's output decoded by a Cairo test equals the sample; the converter refuses an unreachable
      tile, an inconsistent seam and each content check's case.
- [ ] AC-7 The documents of deliverable 6 updated; the decision record proposal lists every open
      question, its recommendation and its decider.
- [ ] AC-8 The Cairo builds capped; the committed figures from a Linux run; `scripts/prepush.sh` green;
      CI green.

## Verification
```
cd spikes/SPK-16-authored-zone
prlimit --as=8589934592 ../../scripts/lock.sh --heavy scarb build
prlimit --as=8589934592 snforge test
python3 convert.py samples/zone.json --out samples/zone.records.json
python3 -m unittest discover -s tests -p 'test_*.py'
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
The report as in `docs/briefs/COMMON.md` §7: the inventory (AC-1); the format; the registration and
its checks; the cost tables (registration, reveal against ENG-05, classes) with their commands; the
randomness recommendation; the export, its schema and converter; the documents changed; the open
questions with their recommendations and deciders.

## Audit
A document and spike lot: a review, no audit by default. The orchestrator decides at the close; if
ENG-08 recommends a change to what is drawn at entry or from a chunk's word, a short randomness lens
reads that recommendation before the project manager decides.

## Open questions
1. **Tile kinds on chain.** Today every rule reads one plane: a wall blocks movement and line of sight
   (design/04: "walls block"). A kind that blocks one and not the other (water, a pit, low cover) needs
   a second plane, so a rule that reads it. *Decider*: project manager (a rule of the game).
   *Recommendation*: the walkable plane only on chain (one felt a chunk); every visual kind client-only
   in the export; the format reserves the planes so that a later rule adds one by a new version.
2. **Where an authored chunk's terrain is read during play.** `Instances` stores each revealed chunk's
   `Terrain` (ENG-01 §3.2) and ENG-07's window assembles from it. *Decider*: orchestrator (the track's
   layout; a rise on the expedition's path goes to the project manager, D-144). *Recommendation*: copy
   the authored terrain into the instance's chunk at reveal, as today, so §3.2 and the window are
   unchanged; the alternative (no terrain slot, the window reading `Registry` at every tick, a call
   a tick) is measured by the spike only if the copy's slot is a large share of the reveal.
3. **Quota placement on an authored map.** (a) drawn over the zone's chunks as ENG-05's hosts (D-210);
   (b) authored candidate places per quota, one drawn among them at `create` (design/18's "its place
   changes with each instance" kept); (c) authored and fixed. *Decider*: project manager. *ENG-08
   recommends with reasons and the figure of AC-5*; whichever is chosen, the draw stays at entry, so
   the order of moves chooses nothing.
4. **Packs on an authored map.** The spawn table drawn per chunk from the chunk's word (today), or
   authored spawn points (tile and template, as `SetPack`) with level and count drawn. *Decider*:
   project manager. *ENG-08 recommends*, with the placement's measured cost (2.10 M of a worst
   generated reveal, ENG-05's profile) as one of its reasons.
5. **D-134's corner tiles in an authored chunk.** D-134 makes a chunk's four corners wall so that a
   reveal never depends on a diagonal neighbour; an authored chunk depends on no neighbour, and walls
   every 15 tiles would show in a drawn zone. *Decider*: project manager (D-134 is its decision).
   *Recommendation*: lifted for authored chunks if the spike shows no other code reads it (the window,
   the tick, `SetPieceAssert` for set pieces only); kept for generated chunks and set pieces.
6. **Border tile masks in an authored zone.** The authored walls already cut the zone. *Decider*:
   orchestrator. *Recommendation*: an authored zone writes its chunk set (`OUTLINE` 255: void chunks,
   the world map, TP-2) and no tile masks; the converter derives nothing else.
7. **The generated zone path after ENG-09.** *Decider*: project manager (class room under D-209).
   *Recommendation*: kept as the fallback while any zone of the content is not authored; removed by the
   lot that authors the last one, its class room won back and measured.
8. **Who builds the four deferred bounds.** *Decider*: orchestrator. *Recommendation*: ENG-09, which
   touches the registry's validators anyway; the dungeon bound (`width × height > N`) is `LOCATION`'s
   own and may land earlier with ENG-R1c; the orchestrator drops them from ENG-R1c's pending list
   when ENG-08 merges.
9. **Where the schema and the converter live after the spike.** They are shared by the game (the
   records) and track CV (the editor). *Decider*: project manager (the boundary between the two
   tracks). *Recommendation*: promoted by ENG-09 to a folder of their own outside `client/sim/**` and
   `contracts/` (for example `tools/map-format/`), the game owning the converter, CV reading the
   schema; a change of the format bumps its version and is announced in the CHANGELOG.
10. **A batched registration entrypoint.** A zone of up to 225 chunk records is written by
    `set_record` one record a call. *Decider*: project manager (a change of `IRegistryAdmin`, a
    frozen interface). *Recommendation*: no new entrypoint: an account's multicall writes many
    records in one transaction; the spike measures how many fit under 1.1 × 10⁹ and proposes one only
    if the per-call overhead it measures is a large share.
