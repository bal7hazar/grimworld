# D-165: SPK-14, hexagonal chunks of 251 tiles, studied before ENG-05

| | |
|---|---|
| Raised by | The owner, 2026-09-30: a chunk shaped as a hexagon with sides 9-9-11-9-9-11 holds exactly 251 tiles, so a layer of one bit a tile fills a felt252 almost exactly; the two long sides on the axis that keeps the shape symmetric on screen |
| Decided by | `[Fable 5.1]` project manager, under D-128: the study; **the shape itself is the owner's decision** on the study's report, since it revises ADR-0006 and D-120 ("chunks stay 15 × 15") |

## Checked

A hexagonal region with opposite sides equal, sides `a, b, c, a, b, c`, holds `ab + bc + ca − a − b −
c + 1` tiles: with 9, 9, 11 that is 81 + 99 + 99 − 29 + 1 = **251**. A 251-bit value is below 2²⁵¹ and
therefore below the field's prime: it fits one felt252. Today a chunk is 15 × 15 = 225 tiles, one
felt a layer, and the Terrain word also holds 4 edge bits (225–228) and `LIVE` at bit 250 (ENG-01
§3.2); the `OUTLINE` masks of the registry are one felt a chunk with `LIVE` too. **On pointy-top
tiles (D-11) a hexagonal region has no vertical side**: its corners lie east and west, its two
horizontal sides are the top and bottom rows. The symmetric choice is therefore the long sides of 11
at the top and the bottom: a shape of 17 rows, 27 tiles at its widest (11 + 2 × 8), against 15 × 15.
Vertical long sides would need flat-top tiles.

## The study: SPK-14 (Opus 5.5, research with measurements; `[GPT-6-Astra]` on cost and determinism)

It answers, with figures measured where SPK-7 measured the rectangles:

1. **The shape and its indexing**: the tile → bit mapping of a 9-9-11 hexagon (row offsets instead of
   `15 row + column`), its 6 corner tiles and 6 edges; the orientation of the long sides (above).
2. **The storage words**: 251 tile bits leave no room for `LIVE` (bit 250) nor for the 6 edge-opening
   bits in the Terrain word, nor for `LIVE` in an `OUTLINE` mask. Where they go (the Features word
   has bits 240–249 free; a `LIVE`-less word class; a second felt) and what ENG-01's rules lose.
3. **The window**: assembling the 15 × 16 window (D-120) from hexagonal chunks: how many chunks it
   overlaps at most (against 4 today), whether the mask-and-shift assembly without a loop over rows
   survives, its cost against N-3's 64,234 (SPK-7: 65,224); the parity of the origin.
4. **Reveal and generation**: cost of generating a 251-tile chunk with margins against 0.39–0.45M
   (SPK-7); edges and openings between six neighbours; D-134's void margin and corner rule restated
   for hexagons; D-136 unchanged; the revealed set (at most 225 chunks a location today, one felt).
5. **What it changes**: ADR-0006 (chunk, outline, margins), ENG-01 §3.2 (`Chunk`, `OUTLINE`,
   `SET_PIECE`), ENG-05 (not started), the map library's N-3 and N-4 (done for rectangles; a
   second shape or a replacement), N-1 and N-2 (rc.2, not started), TOOL-01, the client's chunk
   loading, `docs/needs/hexmap.md`.
6. **A recommendation** with the cost per tick and per reveal side by side, rectangle against
   hexagon, and the work to switch.

Allowlist: `spikes/SPK-14/**`, `docs/research/SPK-14-*`, its brief and report; it reads
`hexx-cairo` as a git dependency at a named commit. No Sepolia. **Timing**: before ENG-05's brief
and before the library starts N-1 and N-2; rc.1 (line of sight, arcs) is unaffected.

## What would reverse it

The study finding the window's assembly or the reveal materially dearer, or the felt's last bits
costing more than the 26 bits a rectangle leaves free.

## Closed, 2026-10-01 (owner)

SPK-14 ([#202](https://github.com/bal7hazar/grimworld/pull/202), `docs/research/SPK-14-hexagonal-chunks.md`)
measured the hexagon of 251 tiles against the rectangle: the storage works (bit 250 is a corner, always
wall, and serves as `LIVE`; 0 new slots), but the window's assembly costs 4.2× to 13.6× N-3's 64,234,
a chunk's generation 2.2× to 2.8× SPK-7's, and a window overlaps up to 6 chunks. Both reversal
thresholds above fail on measurements. **The owner's decision: the chunks stay 15 × 15 rectangles;
cost efficiency is the priority.** ADR-0006 and D-120 stand; the library's N-1 and N-2 (rc.2) and
ENG-05 proceed on rectangles; the bit-250 note stays in the study for a later reopening.
