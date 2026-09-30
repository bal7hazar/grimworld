# SPK-14 — Hexagonal chunks of 251 tiles

> D-165 (`docs/decisions/2026-09-30-hexagonal-chunks-study.md`): the owner's finding, studied before
> ENG-05's brief and before the map library starts N-1 and N-2. **The shape is the owner's decision on
> this report**: it would revise ADR-0006 and D-120 ("chunks stay 15 × 15").

## Agent
Title: `[Opus 5.5] SPK-14 hexagonal chunks` · Profile: research (with builds) · Branch: `spike/spk-14-hex-chunks`

## Goal
After this task the owner can choose between today's **15 × 15 rectangular chunks** (225 tiles) and a
**hexagonal chunk of sides 9-9-11-9-9-11** (251 tiles, one felt252 a layer), on figures measured the
way SPK-7 measured the rectangles, and on a list of what the switch would change.

## Context
- **D-165** in full: the six questions below, the geometry already checked (251 tiles; on pointy-top
  tiles, D-11, the long sides of 11 at the top and bottom, 17 rows, 27 tiles at the widest), what
  would reverse it.
- **SPK-7** (`spikes/SPK-7/`, `docs/research/SPK-7-chunked-maps.md`, its report and audit): the
  rectangles' generation with margins (0.39–0.45 M a chunk), window assembly without a loop over rows,
  the flood and goblins across chunks; how it measured, to measure the hexagon the same way.
- **ADR-0006** (chunks, outlines, margins), **D-120** (the 15 × 16 window that follows the
  adventurer), D-134 (void margins, corners always wall), D-136 (an unrevealed chunk is wall), D-127
  (the flood's 15 layers).
- **`docs/architecture/ENG-01-interfaces.md` §3.2** (the chunk's Terrain and Features words, 4 edge
  bits at 225–228, `LIVE` at bit 250) and **§3.5** (`OUTLINE`, `SET_PIECE`); design/20's constraints
  where the chunk appears.
- **The map library** (`bal7hazar/hexx-cairo`): N-3 (the window's assembly, measured 64,234; SPK-7's
  was 65,224) and N-4, done for rectangles; N-1 and N-2 not started; `docs/needs/hexmap.md`. Read it as
  a **git dependency at commit `93639f2c17e3`** (main on 2026-09-30), never a copy.
- docs/CAIRO.md (§1 cost, §2 tests and budgets), COMMON.md; D-154 (a flaky gas figure is recorded,
  not trusted: measure twice).

## Scope
- In, a spike under `spikes/SPK-14/` (its own Scarb package, as SPK-7) and a research note
  `docs/research/SPK-14-hexagonal-chunks.md`, answering D-165's six questions:
  1. **The shape and its indexing**: the tile → bit map of the 9-9-11 hexagon on pointy-top tiles
     (row offsets instead of `15 row + column`), its 6 corners and 6 edges, the orientation; tests that
     the map is a bijection onto 0–250.
  2. **The storage words**: where `LIVE`, the 6 edge-opening bits and `OUTLINE`'s `LIVE` go when a layer
     takes 251 bits (the Features word's free bits 240–249, a `LIVE`-less word class, a second felt),
     each option's cost in slots and what ENG-01's rules (§2.1, records never zeroed) lose.
  3. **The window**: the 15 × 16 window assembled from hexagonal chunks: how many chunks it overlaps at
     most (4 today), whether assembly without a loop over rows survives, its measured cost against
     64,234, the parity of the origin.
  4. **Reveal and generation**: a 251-tile chunk generated with margins, measured against SPK-7's
     0.39–0.45 M; edges and openings between six neighbours; D-134's void margin and corner rule
     restated for hexagons; the revealed set (a location's chunks in one felt).
  5. **What it changes**: ADR-0006, ENG-01 §3.2 and §3.5, ENG-05, the library's N-3, N-4, N-1, N-2,
     TOOL-01, the client's chunk loading, `docs/needs/hexmap.md`: a list with the size of each change.
  6. **A recommendation**: rectangle and hexagon side by side, per tick (the window) and per reveal,
     with the work to switch; the owner decides.
- Out: any change to `contracts/`, the library, or a design document (proposals go in the note); no
  Sepolia.
- Allowlist: `spikes/SPK-14/**`, `docs/research/SPK-14-*`, `REPORT.md`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 The six questions answered, each with its figures or its reasoning.
- [ ] AC-2 Costs measured where SPK-7 measured (the window's assembly, a chunk's generation), each twice,
      with the test that carries it; the rectangle's figures re-measured beside them on the same basis.
- [ ] AC-3 The indexing's bijection and the window's assembly tested (a hexagon-tiled region assembled
      into the window matches a direct construction).
- [ ] AC-4 The recommendation states what would reverse it, and what is measured against what is estimated.

## Audits
Cost and determinism: **`[GPT-6-Astra]`** through `nexus audit`.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the answers, the figures side by side, the list of changes,
the recommendation; the note in `docs/research/SPK-14-hexagonal-chunks.md`.
