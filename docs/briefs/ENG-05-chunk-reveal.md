# ENG-05 — The chunk reveal engine

> PLAN row ENG-05: "Chunk reveal engine: random word, generation with margins, edges and openings,
> bands, quotas, anchors, placement (ADR-0006). D-134: void chunks around every location and outside a
> zone's outline (wall, never revealed, never stored); a chunk's four corner tiles are always wall".
> Prerequisites: ENG-02 (merged, #246), SPK-7 (done, #50), LIB-05 (`hexx` **0.1.0-rc.2**, tag `v0.1.0-rc.2`
> at `c60e05a` of `bal7hazar/hexx-cairo`: N-1, N-2, N-6). Decisions: ADR-0006 (D-106, D-111, D-120),
> D-134, D-136, **D-165 (chunks stay 15 × 15 rectangles, the owner, 2026-10-01)**, D-140, D-144, D-149,
> D-189, D-198, D-200; pins on Linux only (OPERATIONS.md §3). **It starts when FND-19 has merged** (the
> game on `hexx` 0.1.0-rc.2: this lot calls N-1, N-2 and N-6, which rc.1 lacks); it can run beside
> CBT-05a and CBT-05b under the file split of *Allowlist*. ENG-07 follows it; ENG-R1c follows ENG-07
> if ENG-05 is ready first (D-189).

## Goal
After this task **a chunk is revealed by one engine, for zones and dungeons alike**, exactly as
ADR-0006 §2–§3 and design/18 say: from **a random word that does not exist before the reveal**
(ADR-0006 option C: the entry draw plus the player entropy) and the edges of the neighbours already
revealed, it generates the chunk's terrain **with margins** on `hexx`, joins its **edges and openings**
(copied from a revealed neighbour, closed on the location's border or against a void chunk, drawn
otherwise; the emerging outline of a dungeon), **cuts it by the zone's outline**, draws its **bands**,
its **quotas** (sampling without replacement) and honours its **anchors**, and **places** its packs
and objects in the `Features` word; the result is the chunk's two stored words (ENG-01 §3.2,
unchanged), the revealed set, the quotas and the entropy. **The entry chunk is revealed at `create`**
(and at `leave` through a gate to a location). Deterministic, never panicking on legal content
(D-140), mirrored by vector tables, its cost stated against D-144.

## Context
- **The design.** ADR-0006 §2 (generated at reveal; option C, D-111: one draw at entry, player
  entropy inside, the rule of option B: what feeds the value, a set not a sequence), §3 (the three
  kinds of constraint: bands, quotas, anchors; *Outlines*: zones drawn in the registry, dungeons
  emerging from `N` 6–12 with a border drawn at 1 in 7 and the two rules that keep it sound;
  *Joining chunks*: copy an edge, at least one opening per shared edge decided by the first of the two,
  the void margin and the corners of D-134, smoothing with margins; *Set pieces*), §4 (row parity: a
  chunk at an odd `cy` starts on an odd global row). design/18 *Locations*, *Biomes* (walkable shares;
  **the order of generation: base from the word, smoothing with the margins, edges and openings, cut
  by the outline, quotas, placement**), *Features* (frequencies and rules, at least 2 tiles from an
  opening), *Entering an instance*. design/02 *Map*, *Simulation budget* (≤ 3 chunks revealed by one
  action), the table of chunk kinds (revealed, not yet revealed, void: D-136, D-134) and *What ENG-01
  must do* items 6 and 8 (measure a revealed chunk; the reveal, unrevealed and boundary cases).
  design/17 (a Rift floor's vein and Heart quotas), design/14 (a held contract adds a quota).
- **D-134** (`docs/decisions/2026-09-28-chunk-borders.md`): a margin of void chunks around every
  location and every chunk of the bounding grid outside a zone's outline: wall, never revealed, never
  stored; **a chunk's four corner tiles are always wall**, so a reveal never depends on a diagonal
  neighbour. **D-136** (`2026-09-28-after-DES-21.md` §1): a chunk not revealed is wall in the window;
  in a dungeon whether a neighbour exists beyond an edge is decided with the edge, at the reveal of
  the chunk that owns it. **D-165** (`2026-09-30-hexagonal-chunks-study.md`, *Closed*): SPK-14
  measured the 251-tile hexagon and the owner kept **15 × 15 rectangles**; ADR-0006 and D-120 stand.
- **SPK-7** (`docs/research/SPK-7-chunked-maps.md` §1, §5, §6; `docs/reports/SPK-7-chunked-maps.md`;
  `spikes/SPK-7/src/chunk.cairo`, `tune.py`): the prototype `generate_chunk(word, biome, sides, odd)`
  (base at the biome's density from random bitmaps, sides copied, closed or drawn with 1 or 2
  openings, lines from each opening to a spine, two passes of the automaton with margins, the
  component of the centre kept, corners wall) and its **choices to confirm here**: the lines to a
  spine, the component kept, 1 or 2 openings a drawn side, the biome parameters of `tune.py`. Its
  open questions for ENG-05: the component's share of a generation is not measured apart; **the worst
  reveal is the one with no known neighbour** (a drawn side costs more than a copied one).
- **The storage, frozen by ENG-01** (`docs/architecture/ENG-01-interfaces.md` §3.2): `chunks[(slot,
  chunk)]` = `Chunk { terrain, features }`, two words written at the reveal; `Terrain` bit `15 row +
  column` (**1 = wall**) and, for a dungeon, edges at 225–228 (**West, East, South, North**; 1 open);
  `Features`: 2 packs at 0 and 64 (tile, template, level, count 0–5, each goblin's tile as one of the
  19 tiles within 2, the pack's `alert`), 3 objects at 128, 160, 192 (tile, kind, state, `param`),
  `touched` 224–239 (cleared at the reveal); **E-3: ≤ 2 packs of ≤ 5 goblins and ≤ 3 objects a chunk**;
  occupancy not stored. `revealed[slot]` (bit `15 cy + cx`), `quotas[slot]` (`Quotas`: target `N`,
  open edges, 14 counters "left to place": the location's quotas, then the tasks'), `entropy[slot]`
  ("entry draw + Σ hashes of irreversible actions"), `Header` (revealed count 136–143, entry chunk and
  tile, location). Entity ids `8 + 16 × chunk + k`; tiles `x + 256 y`; locations at most 15 × 15
  chunks; a dungeon's entrance chunk is (7, 7). §2.1: a chunk outside `revealed` is never read; the
  reveal clears `touched`. §5: `ChunkRevealed { instance_id; chunk: u8 }` "at each reveal, in the
  invocation where they happen (a batch, `open`, `mine`, `barter`)".
- **The registry's records** (§3.5): `LOCATION` (type, biome 1 meadow … 4 ruin, level min/max, width
  and height in chunks, `N`, floors, next floor, spawn table, sealed, entry chunk and tile; part 1:
  up to 15 `SET_PIECE` ids) and `OUTLINE` (`location × 256 + 255`: the zone's chunk set;
  `location × 256 + chunk`: a border chunk's tile mask, 1 in the zone) and `GATE` (source anchor
  chunk and tile) are laid out (`grimworld_logic::models::{location, outline, gate}`). **`QUOTAS` (5),
  `SPAWN_TABLE` (6), `PACK` (7) and `SET_PIECE` (24) are not**: ENG-01 lists their fields only, and
  `contracts/seed/README.md` says "`QUOTAS`' bit layout is ENG-05's" and names the quotas the test
  region gets (floor 1's exit, the zone's collector camp, floor 2's boss arena once a set piece exists).
- **The code at `origin/main` `6887010`** (ENG-R1b part 1 merged, #320):
  `contracts/ephemeral/src/systems/instances.cairo` `begin` writes the header (entry chunk and tile),
  the entry draw (`fate(domain(id, 0, ENTRY))`, then `derive(word, draw, 0)` into `entropy`), an empty
  revealed set and `QuotasTrait::new(target)` ("what each quota has left to place is written by
  ENG-05"); `create`'s doc: "the entry chunk's reveal is ENG-05's"; `instance_region` panics
  `NOT_IMPLEMENTED`. `contracts/ephemeral/src/store.cairo` (`InstancesStoreTrait`, typed slots) has
  no chunk method yet. `contracts/ephemeral/src/models/chunk.cairo` holds `Terrain`, `PackPlacement`,
  `Object`, `Features`, `Chunk` and the private free functions `pack_pack`, `unpack_pack`,
  `pack_object`, `unpack_object` (**deferred from #320's review, minor 2: scoped in traits by the next
  lot that touches `chunk.cairo`; this one**). `contracts/logic/src/fate.cairo`: `domain`, `derive`
  and eight purposes (no reveal purpose). ENG-01 §1.3: **the pure rules of generation go into a library
  class** (`library_call`, state in and out); `Hub` keeps `FlattenLibrary`'s class hash in its storage
  and `set_contracts` (CBT-02f's precedent); `Instances` holds no class hash yet.
- **`hexx` 0.1.0-rc.2 — what ENG-05 calls** (`crates/hexx/src/`, rc.2's CHANGELOG *Extensions*; the
  library's grid is **1 = walkable**, the inverse of `Terrain`):
  - N-1 `generators::caver::CaverTrait::generate_with_margins(width, height, order, seed, fixed,
    values, odd)` (the automaton `B4/S2` with the ring frozen to the tiles copied from the neighbours,
    rows of the chunk's global parity, **corners always wall**; 15 × 15 is within its bound
    `W (H + 1) + 1 ≤ 251`), `CaverTrait::smooth(grid, width, height, order, held, odd)`,
    `CaverTrait::keep_component(grid, width, height, from)` (panics if `from` is not floor), and their
    facade `board::map::HexMapTrait::{new_cave_with_margins, smooth, keep_component}`;
  - N-2 `board::seams::{Side, SeamTrait::{side, openings, is_open_across}}` (**`Side::East` is column
    0, `West` column `W − 1`, `South` row 0, `North` row `H − 1`**: `+x` is West) and
    `board::layout::LayoutTrait::new_odd` for a chunk on an odd global row;
  - N-4 `board::cut::CutTrait::cut(map, mask)` (`grid & mask`, the ring kept: open the edges first,
    then cut by the outline);
  - N-6 `board::hexagon::HexagonTrait::{hexagon, hexagon_ring}` (the 19 tiles within 2 of a pack's
    tile; "2 tiles from an opening");
  - `board::rng::{Rng, RngTrait::{new, draw, draw6}}` for bounded draws from one seed.
  rc.2's own figures (`docs/GAS.md` there, Cairo 2.20.0): `bench_map_new_cave_with_margins_15x15_order_3`
  184,691; `bench_map_smooth_15x15_order_3` 178,194; `SeamTrait::openings` 26,302 to 43,066 a side;
  `is_open_across` 42,866.
- **Vector tables** (`contracts/logic/vectors/README.md`, `check.py`, in CI's `contracts` job): one
  JSON line per case `{"id", "fn", "case", "ok"}`, every felt in hex, printed by a test of
  `grimworld_logic` that holds a digest; `check.py` fails while a committed table differs from what the
  tests print. **The TypeScript mirror of track CV reads them** (`client/sim/**` is lent to track CV,
  D-149; it has no reveal and no fate mirror today): a new rule gets a paired CV pull request, asked
  through the orchestrator.
- **The cost.** SPK-7, gathered in ADR-0006 *Measured*: a reveal of one chunk **2,455,200** L2 gas
  and of three **5,919,680** (cave) as transactions on the local node; generation **390k–447k** a chunk
  in memory. ENG-01 §9.2 (a batch reveals at most 4 chunks: `Σ (1 + 2 cᵢ) ≤ 10`; 13 chunk keys), §10.1
  (the 4-reveal branches, up to 70 keys) and **E-12** ("a reveal weighs 2 but costs 1.4 M, 0.6 M after
  its first time; weight 1 after ENG-05's measurement"). §10 *Measured by ENG-06*: `enter` 4,100,000,
  and "the entry chunk's two keys move from `enter` to ENG-05's reveal". **D-144**
  (`2026-09-29-eng-04-budgets.md` decision 1): a measured replacement up to +10 % is the
  orchestrator's; beyond, **or on the expedition's path (`play`, the actions sent alone, `enter`,
  `leave`, `travel_back`), the project manager's at any size**: the entry reveal raises `enter` (through
  `create`) and `leave` to a location, so both go to the project manager. Class sizes: ENG-01 §1.3, a
  new class under 50 % (D-200's default; `TickLibrary` ≤ 75 %, `ExecutorLibrary` ≤ 80,420 felts are
  other classes'). **Pins are generated on Linux only** (the VPS or CI; OPERATIONS.md §3, #280): a Mac
  run gives tests, never a committed `GAS.md`, budget or class size.
- docs/CAIRO.md §2 (tests first, gas a test result, every test with its budget, an oracle beside an
  optimised algorithm, **benchmarks on the worst case: "a reveal of 3 chunks"**, D-167: unit tests in
  their module's file), §7 (layers, scoped functions, every stored entity a model, the store), §8 (the
  organisation lens). COMMON.md. **D-149: no event of ENG-01 changes** (name, keys, data, where, how
  often, order); what `Instances` emits stays emitted by its systems (D-193, the owner's reading of
  ENG-R1a).

## Scope
- In:
  - **The record layouts** of `QUOTAS` (up to 6 quotas: kind exit, Heart, vein, collector,
    landmark, set piece; param; count), `SPAWN_TABLE` (up to 7 pack templates with weights; density),
    `PACK` (up to 5 castes with count min and max; level offset) and `SET_PIECE` (terrain and
    placements, two parts), as models in `grimworld_logic::models` on the pattern of
    `models/location.cairo` (struct in `models/index.cairo`, `new`, `...Assert`, `errors`,
    `content::Record`), round-trip and bit tests, written into ENG-01 §3.5's table; the test region's
    seed gains the quotas `contracts/seed/README.md` names and a spawn table with its packs.
  - **The random word** (ADR-0006 option C): a reveal purpose in `fate.cairo` (appended to
    `PURPOSES`, so `fate.jsonl` is regenerated and the move announced); the chunk's word derived from
    the instance's `entropy` at the reveal (Open question 2); **the entropy's feed**, the set sum of
    ENG-01 §3.2 (`entropy + poseidon(fact)`), as a scoped function every later feeder calls, and the
    reveal's own fact (the chunk and the side it was entered from, ADR-0006's table). Other feeders
    (a kill, health lost, a consumable, loot, a chest, a vein) are their lots'.
  - **Generation with margins**, in design/18's order, on the `hexx` calls above: the base and the
    automaton from the word with the ring frozen to what the revealed neighbours fix (their facing
    tiles, read from their stored terrain), each biome's parameters (density, generations) chosen so
    that its walkable share is inside design/18's range on average (SPK-7's `tune.py` as the start;
    TP-1 tunes them later), the parity of the chunk's rows (`odd = cy` odd), corners wall.
  - **Edges and openings** (ADR-0006 *Joining chunks*, *Outlines*): a side facing a revealed
    neighbour copies its decision (open with at least one opening across the seam, or border); a side
    facing the location's border or a void chunk is closed but for a gate anchor; any other side is
    drawn (its openings, at least one; in a dungeon border with probability 1 in 7, except the last
    open edge of the frontier while fewer than `N` chunks are revealed; every open edge border once `N`
    are). **Every open tile of the chunk is reachable from each of its openings** (SPK-7's lines and
    component, or better, measured). `Terrain`'s edge bits 225–228 written for a dungeon chunk, in
    ENG-01's order (West, East, South, North), which is not `hexx`'s `Side` order: a test pins the map.
  - **The cut by the outline** (zones): a chunk outside the zone's chunk set is void (never
    revealed); a border chunk is cut by its tile mask after its edges are opened (`CutTrait::cut`); a
    chunk of the set with no mask is whole.
  - **Bands** (a pack's level within the location's band, growing with the chunk's distance to the
    entry chunk, ADR-0006 kind 3), **quotas** (sampling without replacement: `left / chunks left`,
    1 when they are equal, "chunks left" being `N − revealed count` in a dungeon and the chunk set's
    count less the revealed count in a zone; the location's quotas from `QUOTAS` at `create`, the
    tasks' after them in `Quotas`; a set-piece quota lays an authored chunk whose edges are joined like
    any other), **anchors** (a gate's anchor tile open and reachable; the entry tile likewise).
  - **Placement** into `Features`: 0–2 packs from the spawn table within the band (members within 2
    tiles of the pack's tile, on floor, asleep or on watch), objects by design/18's frequencies (chest
    1 chunk in 6; gathering node 1 in 4, zones only; terrain trap 1 in 3 in ruins and caves) and by
    quota (vein, collector, landmark, exit), never more than E-3's 2 packs, 5 goblins a pack and 3
    objects; at least 2 tiles from an opening; `touched` cleared.
  - **The engine as pure code in `grimworld_logic`**, one scoped entry (the reveal of one chunk:
    the content and the neighbours' words in, the chunk's two words and the new quotas and entropy out)
    plus **which chunks sight touches from a tile** (hex distance 6, D-136: the move that would bring
    sight onto a chunk reveals it), for ENG-07 to call at each move; **declared as a library class**
    if Open question 1 stays as recommended.
  - **In `Instances`**: the store's chunk methods (`get_chunk`, `set_chunk`, focused reads of a
    neighbour's terrain) in `InstancesStoreTrait`, on its typed slots, `layout_tests` unchanged; the
    reveal path that writes the chunk, the revealed set, the header's revealed count, the quotas and
    the entropy; **the entry reveal in `begin`** (every chunk sight touches from the entry tile, Open
    question 3), with the content it needs read in the fewest calls; `instance_region`'s chunk kinds
    (void, not yet revealed, revealed: design/02 *How the views tell them apart*) and the revealed
    chunks' words (Open question 5).
  - **`models/chunk.cairo`'s four private free functions scoped in traits** (#320's deferred minor),
    whichever package the chunk's models end in (Open question 4).
  - **Vector tables**, `contracts/logic/vectors/reveal.jsonl` (more parts if snforge's step limit
    needs them), printed by tests with digests, registered in `check.py`'s `TABLES` and documented in the
    README, covering every computation the client repeats: the chunk's word and the entropy's feed; a
    generation for each biome and both row parities, with 0 to 4 known sides and borders; the edges of
    a dungeon chunk (the emerging-outline rules at `N − 1` and `N`); a zone's cut; the quota draws;
    the placement; the chunks sight touches.
  - **Tests**, in their modules (D-167), integration and benchmarks in `tests/`: each step against
    design/18 and ADR-0006; invariants over many words (corners wall, every opening reachable, every
    shared edge open across its seam from both sides, no placement on a wall or within 2 of an
    opening, E-3 never passed, a quota's last chunks holding what is owed, a dungeon never closing
    before `N` and always closing at `N`); an oracle for any optimised step; D-140 (no legal content
    and no word panics: `keep_component`'s source is floor); the reveal at a location's edge and next
    to a void chunk; design/02 item 8's reveal, unrevealed and boundary cases where this lot can hold
    them (a view of a void chunk, a chunk outside `revealed` never read).
  - **The budget lines**: a reveal's cost in memory (generation and placement) on its worst case
    (no neighbour known, four sides drawn) and its typical case; the reveal of one chunk and of three
    as the invocation's difference, new and overwritten slots; the entry reveal's rise of `create`
    (`enter`) and of `leave` to a location; **E-12 answered** with the measure (weight 2 kept, or 1
    proposed); written into ENG-01 §9.2 (per batch: the reveals) and §10.1 / §10.2 where they price a
    reveal, and stated against D-144 in the report.
- Out: movement, the window's assembly and which ticks reveal (ENG-07, which calls this lot's
  engine and sight function from `play` and emits `ChunkRevealed` there); goblins' derived state in
  the views, the roster, the awake selection (ENG-07); the AI; traps' trigger and placed traps
  (CBT-05b: kind 9); the content of a chest, a vein, a collector (their actions' lots); the other
  feeders of the entropy; the content pipeline's semantic checks of the new kinds (OPS-01); the map
  tool and authored chunks' format (TOOL-01, CM-7); `N` per grade (CM-9); `client/sim/**` (track CV:
  the mirror is its paired lot); any change of ENG-01's storage layouts or events.
- Allowlist:
  - `contracts/logic/src/**`: **new files** (e.g. `types/reveal.cairo`, `models/quotas.cairo`,
    `models/spawn_table.cairo`, `models/pack.cairo`, `models/set_piece.cairo`, `models/chunk.cairo` if
    the models move, `systems/reveal.cairo`) and, in existing files, **only** the module lists
    (`lib.cairo`, `models.cairo`, `types.cairo`, `systems.cairo`, `helpers.cairo`),
    `models/index.cairo` (the new structs), `interface.cairo` (the library's interface),
    `fate.cairo` (the purpose and the feed), `content.cairo` if a kind's part count needs it; never
    the tick's, the hit's, the conditions', the window's or the executor's files (CBT-05a's and
    CBT-05b's).
  - `contracts/logic/tests/**`; `contracts/logic/vectors/reveal*.jsonl`, `fate.jsonl` (regenerated),
    `README.md`, `check.py` (`TABLES` only).
  - `contracts/ephemeral/src/models/chunk.cairo`, `models/instance.cairo` (`Quotas`, `Header`'s
    revealed count), `store.cairo` (chunk methods; the class hash if Open question 1),
    `systems/instances.cairo` (`begin`, the reveal path, `instance_region`, `set_contracts` if Open
    question 1); `contracts/ephemeral/tests/**`.
  - `contracts/persistent/src/systems/registry.cairo` for the new kinds' content checks only, **after
    CBT-05a has merged** (its validators); `contracts/persistent/tests/test_seed.cairo`;
    `contracts/seed/test-region.json` and `README.md`.
  - `contracts/tools/lifecycle_probe.py` and `lifecycle-stream-before-r1b.json` for the entry
    reveal's keys only (Open question 6).
  - `docs/architecture/ENG-01-interfaces.md` §1.3 (the new class), §3.2 (where it names the reveal),
    §3.5 (the four layouts), §4.1 (`set_contracts`, if Open question 1), §9.2, §9.3 (`enter`,
    `leave`), §10.1–§10.2 (the reveal's rows), §11 (E-12); `contracts/*/GAS.md` and `docs/BUDGETS.md`
    as generated. Anything else is an escalation.
  - **Overlaps, hence when it starts:**
    - **FND-19** (the game on `hexx` 0.1.0-rc.2: `contracts/Scarb.toml`, `Scarb.lock`, the generated
      gas files): **a prerequisite**. ENG-05 starts on an `origin/main` that has it.
    - **CBT-05a** (in progress, review soon; `contracts/logic/src/**`, `registry.cairo`'s validators,
      ENG-01 §9.2, `GAS.md`, `docs/BUDGETS.md`): ENG-05 runs beside it under the file split above (new
      files; module lists and `index.cairo` by appending; ENG-01 §9.2 a separate line). Whichever
      merges second merges `origin/main`, regenerates `GAS.md` and `docs/BUDGETS.md` and re-runs
      `class_sizes.py` (never by hand). The registry's checks of the new kinds wait for CBT-05a's merge.
    - **CBT-05b** (after CBT-05a; `contracts/logic/src/**`, the validators, the chunk object of kind
      9): the same split; ENG-05 places terrain traps (kind 4, CBT-05b's *Out*), CBT-05b places and
      triggers kind 9 on the object layout ENG-05 leaves unchanged. If the chunk's models move to the
      logic package (Open question 4), CBT-05b imports them from there.
    - **ENG-R1b part 2** (`Registry` on its store, after CBT-05a): `registry.cairo` and the persistent
      store; ENG-05 touches the validators only; whichever merges second merges `origin/main`.
    - **ENG-R1c** (D-189): it takes the first window with no lot in `contracts/logic/src` and never
      delays ENG-05 or ENG-07; ENG-05's new code is written on CAIRO §7's pattern from the start, so
      ENG-R1c has nothing of it to move.
    - **ENG-07** follows this lot; **track CV**'s mirror of the reveal follows its vectors (a paired
      PR in `client/sim/**`).

## Acceptance criteria
- [ ] AC-1 **Inventory first**: the report opens with a table of design/18's six steps, ADR-0006's
      rules (edges, openings, outlines, bands, quotas, anchors, set pieces) and D-134, where each lives
      after this lot (function, file) and the test that holds it; SPK-7's choices kept or replaced, with
      the measure.
- [ ] AC-2 The four record layouts as models, round-trip and bit tests, ENG-01 §3.5's table; the seed
      written and read back (`test_seed_written_and_read_back`) with the new records.
- [ ] AC-3 The engine reveals one chunk in design/18's order on the `hexx` calls named above; every
      invariant of *Scope*'s tests holds over many words; corners wall; ENG-01's edge order pinned
      against `hexx`'s `Side`; no panic on legal content or any word (D-140).
- [ ] AC-4 The random word and the entropy's feed: a reveal never uses a value used by another
      decision (ADR-0002 rule 2), the same chunk revealed under the same entropy gives the same words,
      the feed is order-independent (a set) and tested so.
- [ ] AC-5 `create` and `leave` to a location reveal the entry chunk(s); `instance_region` tells void,
      not yet revealed and revealed apart and returns a revealed chunk's words; `ENG-01`'s storage
      layouts unchanged (`layout_tests`); **no event of ENG-01 added, removed or moved** (D-149).
- [ ] AC-6 **Vector tables**: `reveal.jsonl` (and `fate.jsonl` regenerated) in the JSON-lines format,
      registered in `check.py`, documented in the README; `python3 contracts/logic/vectors/check.py`
      passes; the moved and the new tables announced in the report for the CHANGELOG and for track CV.
- [ ] AC-7 **The budget lines** of *Scope* in the report and in ENG-01 §9.2 / §10; every rise of
      `create` (`enter`), `leave` or `play` stated for the project manager (D-144, at any size); E-12
      answered; every class under 50 % (`class_sizes.py`), the new library class included.
- [ ] AC-8 `models/chunk.cairo`'s free functions scoped in traits; D-143 (no free function without a
      written reason); unit tests in their modules (D-167); CI green; `gas_budgets.py --check`; pins
      generated on Linux only.

## Verification
```
for p in logic persistent ephemeral; do (cd contracts/$p && ../../scripts/lock.sh --heavy scarb build && snforge test); done
python3 contracts/logic/vectors/check.py
python3 scripts/gas_budgets.py --check && python3 scripts/gas_budgets.py --report
python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --scope r1b --expect contracts/tools/lifecycle-stream-before-r1b.json
grep -nE '^(pub )?fn ' contracts/ephemeral/src/models/chunk.cairo contracts/logic/src/models/*.cairo contracts/logic/src/types/reveal*.cairo
scripts/prepush.sh
```
The gas files, budgets and class sizes committed come from a Linux run (the VPS or CI).

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, opening with AC-1's inventory; then the layouts, the
random word, each step of generation with its `hexx` calls and its measure, the invariants, the
entry reveal, the views, the vector tables (what moved, for the CHANGELOG and track CV), the budget
lines against D-144 and E-12, the probe's comparisons, the gas table of every test.

## Audit
This lot meets the exception rule (OPERATIONS.md §6, "chunk reveal and the simulation window"): one
audit, the security-and-determinism lens (can a player read or steer a chunk beyond what option C
accepts; do chain and mirror compute the same chunk); the orchestrator decides at the close.

## Open questions
1. **Where the engine runs.** ENG-01 §1.3 puts the pure rules of generation in a library class;
   SPK-7's `Instances` with generation and the tick measured 45.3 % of the CASM limit; `Instances`
   holds no class hash today. *Recommendation*: a **`RevealLibrary`** class in `grimworld_logic`
   (`systems/reveal.cairo`), its class hash in `Instances`' storage and `set_contracts` as `Hub` keeps
   `flatten` (an administrator's argument, no event; ENG-01 §1.2 and §4.1 updated), one library call a
   reveal; `TickLibrary`'s 75 % stays for ENG-07 and CBT-05. Reversed if the measure shows the code
   fits `Instances` under 50 % with room for ENG-07's wiring and the call's ~0.12 M a reveal matters:
   then linked into `Instances`, with the figures.
2. **The chunk's word.** *Recommendation*: `derive(entropy, domain(instance_id, chunk, REVEAL), i)`,
   the entropy read at the reveal (so every irreversible fact before it counts and nothing after),
   the chunk index as the counter (never the sequence or the clock, which ADR-0006 says must not feed
   it), and the side entered fed into the entropy with the chunk after the reveal. Reversed by the
   determinism lens finding a free choice this leaves.
3. **What `create` reveals.** design/18: "the entrance tile, in the first chunk, revealed by the
   entry draw"; D-136: sight never reaches a chunk not revealed. An entry tile within 6 of a chunk's
   side (the test zone's is on column 0) has sight on its neighbour. *Recommendation*: `create`
   reveals **every chunk sight touches from the entry tile** (at most 4 with the entry chunk: a
   radius of 6 overlaps at most 2 × 2 chunks), the entry chunk first, so D-136 holds from the first
   tick; the rise is measured and goes to the project manager (D-144). The alternative (the entry chunk only, ENG-07 revealing the rest at
   the first move) breaks D-136 until then.
4. **Where the chunk's models live.** The engine is in `grimworld_logic`; `Terrain`, `PackPlacement`,
   `Object` and `Features` are in the ephemeral package. *Recommendation*: move them to
   `grimworld_logic::models::chunk` (scoped, with their tests), the ephemeral `Chunk` storage struct
   importing them; the layout and its addresses unchanged (`layout_tests`, the probe). It also lets
   CBT-05b and ENG-07 read the objects without a dependency on `Instances`.
5. **How much of the views.** `instance_region` panics today; its goblins (derived or stored) need
   the roster and `touched`, which ENG-07 brings. *Recommendation*: this lot fills each chunk's kind
   and words; `RegionChunk.goblins` and `InstanceView`'s window chunks and goblins stay empty, for
   ENG-07, with a line in the code saying so.
6. **The probe's streams.** The entry reveal adds two chunk keys (and, under Open question 3, up to
   four more) to `create`'s and `leave`'s writes; `ChunkRevealed` is not emitted there (ENG-01 §5
   lists the invocations: a batch, `open`, `mine`, `barter`; the client knows the entry from
   `InstanceEntered` and the header). *Recommendation*: `--expect lifecycle-stream-before.json` passes
   unchanged (it records `Hub`'s storage and `Instances`' events); the `r1b` stream differs by
   exactly the reveal's keys: the probe records the chunk words by key only (they follow the entry
   draw, as the entropy does) and `lifecycle-stream-before-r1b.json` is re-recorded with that diff
   shown in the report.
7. **Quotas the tasks add.** design/14: a held contract adds its targets to the zone as a quota;
   `Quotas` keeps slots for them after the location's. *Recommendation*: this lot counts and draws
   them from the snapshotted tasks' quota kinds where a `TaskEntry` names one (a landmark to reach, a
   caste to kill), placing what it can place (a landmark, a pack holding the caste); a kind it cannot
   place is listed in the report, for the lot that brings it.
