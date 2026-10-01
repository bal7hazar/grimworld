# ENG-02: the map library's name in the rules, and four geometry edges

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from ENG-02 ([#246](https://github.com/bal7hazar/grimworld/pull/246); report *Escalations* 1, *Open questions* 1) |
| To be answered by | `[Fable 5.1]` project manager (CAIRO.md and the design documents are not the orchestrator's to reword) |
| Needed by | ENG-02's merge (the documents follow it); CBT-05a (the edges) |

ENG-02 moved the game from `origami_hexmap` 1.8.0 to `hexx` 0.1.0-rc.1 by registry version (D-173):
nothing else used `origami_hexmap`, and no figure of the game moved. The geometry layer
(`types::window`: line of sight, reach, arcs, front tile, facing, shapes) is frozen for CBT-05a, and
`hexx`'s line already follows design/04's tie rule (the lower tile index).

## 1. The rules still name `origami_hexmap` and its `u252`

- **docs/CAIRO.md** line 4 ("the map library `origami_hexmap` is the reference") and **§4**'s row
  "**`u252` from `origami_hexmap`** for bitmaps and packed values", with line 73 ("fits a `u252`");
  **docs/briefs/COMMON.md** §1 repeats it. `hexx` has no `u252`: it handles bitmaps as `felt252` and
  `u256` through its `Bits`; no game code uses `u252`.
- **design/04** line 42 ("This function is not part of `origami_hexmap` and is ours to write"): line of
  sight is now `hexx`'s N-5, checked against design/04's tie rule. **design/02** line 149, the *Library*
  row. **CONTEXT.md** (8 mentions). A comment in `client/app/src/input/coords.ts` (track CV's file).

**Recommendation**: CAIRO.md §4 reads "**`felt252` bitmaps through `hexx`'s `Bits`** (and `u256` where a
board passes 252 bits)", line 4 names `hexx` (the map library, D-173) as the reference, line 73 "fits a
felt252"; COMMON.md §1 follows; design/04 line 42 says line of sight is `hexx`'s N-5 under design/04's
tie rule; design/02's row names `hexx`. The orchestrator makes COMMON.md's and the design documents'
edits once CAIRO.md's rule is reworded; CONTEXT.md is yours; the client's comment goes to track CV.

## 2. Four edges the design does not spell out

ENG-02 chose the only non-panicking answers consistent with design/04 and D-140, and tested them:

| Case | ENG-02's answer |
|---|---|
| Source and target on the same tile | no arc; facing unchanged |
| A position outside the window | line of sight false, arc `None`, facing unchanged, shape empty |
| A line that leaves the window | no sight; the arc and the facing still use the first step |
| A wall at an end of the line | not specified, not tested |

**Recommendation**: write the first three into design/19 §6 as they are (a small edit with ENG-02's
reference), and decide the fourth: **a wall at either end blocks the sight** (an actor never stands on a
wall, so it can only be a targeted tile: a `TILE` carrier aimed at a wall sees nothing), tested in
ENG-02's fix loop.

## 3. Recorded, no decision needed

- **The tie rule depends on the window's orientation**: "the lower tile index" agrees on the window's index
  (`15 y + x`) and the location's (`x + 256 y`) only while the window's axes run as the location's. ENG-07's
  assembly keeps that orientation (PLAN, ENG-07).
- A weapon hit's geometry (69,266) costs more than the hit itself (46,460): a combined `reach`-and-`arc`
  call for CBT-05a saves one step per hit (PLAN, CBT-05).

## Decision

Pending.
