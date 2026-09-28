# SPK-7 — Chunked map spike

## Agent
Title: `[Opus 5.5] SPK-7 chunked map spike` · Profile: implement · Branch:
`chore/spk-7-chunked-maps`

## Goal
After this task we know, measured and not estimated, what the map of ADR-0006 costs as
decided on 2026-09-28 (D-120): generating a chunk with margins at reveal, assembling the
**window of 15 columns × 16 rows that follows the adventurer, at each tick, from the chunks**,
one flood shared by 8 goblins, goblins crossing chunks, and line of sight. Above all: **the
worst case of a tick** (4 chunks overlapped, two layers each, 8 awake goblins), **with and
without a stored window**. The figures settle risk R-12, the budgets FND-04 writes, and what
ENG-05 and ENG-07 implement; they also tell the map library (track LIB) what its milestone
L-M1 must beat.

## Context
- **ADR-0006 in full**, especially §1 (three notions: chunk 15 × 15, window 15 × 16 never
  stored, sight of radius 6 always inside the window's ring), §2 (generation at reveal, the
  random word, joining chunks: edges copied, at least one opening per shared edge), §4 (the
  window: 2 or 4 chunks, masks from a table of constants and shifts by a power of two, no
  loop over rows, origin on an even global row, the adventurer on local `(7, 7)` or `(7, 8)`,
  the ring as wall, goblins crossing chunks), *Cost, unknown until measured*.
- **docs/decisions/2026-09-28-window-follows.md** (D-120): the window follows the adventurer,
  15 × 16, not stored; fallback **sight 5 on 13 × 14**; the assembly method.
- **docs/needs/hexmap.md**: the answers of 2026-09-28 (the seam is inside the chunk: its outer
  ring holds the tiles copied from its neighbours and the 13 × 13 interior evolves; a parity
  flag for chunks starting on an odd row, used by generation and seams, not by the window; the
  library's axis convention; flood rule (a): one flood per tick on the occupancy frozen at the
  start of the tick, current occupancy filtering each goblin's candidates in ascending id
  order; line of sight: integer line, ties to the lower tile index, symmetric) and *N-3 in
  detail: the window*.
- design/02 (*Map*, *Simulation budget*: ≤ 8 awake goblins, one flood per tick, ≤ 3 chunks
  revealed by one action), design/04 (*Ranges*: line of sight; *Goblin AI*: determinism,
  ties), design/18 (biomes and walkable shares, generation order, features), docs/CAIRO.md in
  full (arithmetic, then bitwise, then loops; `u252`; tables of constants; oracles; a gas
  budget on every test).
- **Toolchain and map library** (ADR-0007, D-123): the game is on **Cairo 2.19**, and
  `origami_hexmap` 1.8.0 builds on it (FND-01b proved it). The spike is a package in
  `spikes/SPK-7/` **on the repository's toolchain** (the root `.tool-versions`; no pin of its
  own), with `origami_hexmap` 1.8.0 by published version. N-9 and D-122 are void. The milestone
  L-M1 functions (generation with margins, assembly, line of sight, the shared flood with extra
  obstacles) do not exist yet: build what the spike needs on top of 1.8.0's primitives,
  following the library's conventions, and say which parts belong in the library. The fallback
  of R-15 / R-18 (rooms and corridors) is **not** triggered: do not write it.
- Native contracts (ADR-0007): the stored window of item 6 is contract storage, written the way
  ADR-0007 and docs/CAIRO.md §5 say (one write per struct per transaction, explicit packing).
- Depends on: SPK-5b and FND-01b (merged). SPK-2 measures the tick on an already assembled
  window; you measure the rest, so that the two add up.

## Scope
- In: a Scarb package in `spikes/SPK-7/`, native Starknet, on the repository's toolchain:
  1. **Chunk generation with margins**, from a random word (a stand-in for `fate(domain)`
     reading the transaction hash) and the edges of the neighbours already generated: base,
     smoothing with the known margins, edges and openings, per biome's walkable share
     (design/18). Measure one chunk, and **the worst reveal: 3 chunks in one action**.
  2. **Window assembly**, per ADR-0006 §4 and needs N-3: 15 × 16, origin on an even global
     row (refuse an odd one), 2 or 4 chunks, two layers (terrain, occupied), masks from a
     table of constants and shifts by a power of two, no loop over rows, the ring imposed as
     wall. Test it against a plain, obviously correct tile-by-tile assembly kept in the tests
     (oracle), on every overlap case (2 and 4 chunks, both row parities of the adventurer).
  3. **The shared flood** for 8 awake goblins on the assembled window, rule (a), with the
     occupancy frozen at the start of the tick.
  4. **Goblins crossing chunks**: a goblin's move updating the occupied bit of the chunk left
     and of the chunk entered.
  5. **Line of sight** between two tiles, the game's rule, symmetric, tested against a plain
     version.
  6. **The worst case of the tick**: 4 chunks overlapped, two layers each, 8 awake goblins,
     assembly + flood + goblin moves (some crossing chunks) + writes; **once with the window
     assembled at each tick (no storage), once with a stored window** re-centred on the
     adventurer and written back (the design D-120 rejected, for comparison only).
  7. **The fallback**, only if the worst case exceeds what SPK-2's figures and ADR-0001's
     threshold allow: sight 5 on 13 × 14 (the width then differs from the chunk's: say what
     the assembly becomes).
- Measure everything as **snforge tests with gas budgets** and, for the worst-case tick and
  the reveal of 3 chunks, as transactions on the local node (`scripts/with-node.sh`, `sncast`).
- `docs/research/SPK-7-chunked-maps.md`: what was built, how far from ADR-0006, every figure
  with its command and output, the comparison stored / not stored, the verdict on R-12, what
  the library should provide (with the gas each function must beat), open questions for
  ENG-05, ENG-07 and LIB-03.
- Out: the reveal engine with bands, quotas and anchors (ENG-05); movement, facing and the
  action queue (ENG-07); combat; `contracts/`, `client/`; any change to the map library's
  repository; any deployment outside the local node.
- Allowlist: `spikes/SPK-7/**`, `docs/research/SPK-7-chunked-maps.md`. Anything else is an
  escalation. A design question (a rule ADR-0006 does not settle) stops that part and goes
  under *Escalations*.

## Interfaces
Throwaway. Name the functions after the library's needs they prototype (`assemble_window`,
`line_of_sight`, `shared_flood`, `generate_chunk`) so that the report maps each to N-1…N-8.

## Acceptance criteria
- [ ] AC-1 Window assembly equals the oracle on every overlap case and both row parities; an
      odd origin is refused; no loop over rows in the optimised version.
- [ ] AC-2 Line of sight is symmetric and equals the oracle on an exhaustive set of pairs
      in one window.
- [ ] AC-3 Every function and the worst-case tick have a test with a gas budget
      (`ceil(1.05 × measured)`); the worst case is the one named above.
- [ ] AC-4 The worst-case tick measured with and without a stored window, side by side, with
      the local node's receipts for both.
- [ ] AC-5 The reveal of one chunk and of 3 chunks in one action measured, with the biome
      that is the most expensive.
- [ ] AC-6 The research file gives a verdict on R-12 and the gas targets for L-M1.

## Verification
From the worktree root:
```
scripts/lock.sh scarb build --manifest-path spikes/SPK-7/Scarb.toml
cd spikes/SPK-7 && snforge test && cd -
scripts/with-node.sh <the command that declares, deploys and sends the worst-case transactions>
```

## Audits
Cost and determinism (PLAN: C P), by `[GPT-6-Astra]`: "chunk reveal and the simulation window
(determinism, cost)" is an audit codex always does (OPERATIONS §2).

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the cost table of every function and of
the worst-case tick, stored and not stored.
