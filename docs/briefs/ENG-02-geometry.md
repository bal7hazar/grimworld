# ENG-02 — The game's geometry on `hexx`: line of sight, arcs, facing, shapes

> D-173: `hexx` 0.1.0-rc.1 is published (scarbs.xyz; content N-3, N-4, N-5, N-7, N-8: assembly, cut,
> line of sight, directions and arcs, flood). The game consumes it **by published version only** (a
> Scarb registry dependency), never by git revision. ENG-05 waits for rc.2 and the owner's chunk
> decision; this lot is ENG-02 alone.

## Agent
Title: `[Opus 5.5] ENG-02 geometry` · Profile: implement · Branch: `feat/eng-02-geometry`

## Goal
After this task the game has **one geometry layer on `hexx`** that the rules call: whether a tile sees
another (line of sight), **the arc a hit arrives from** relative to the target's facing (melee: the
source's tile; at range: the tile the line of sight arrives from), whether the target stands on the
source's front tile, the facing an action turns to, and **a shape's tiles from a centre, clipped to the
window**; exactly as design/04 and design/19 say, deterministic, with D-140's edges, its cost per call
stated, and **frozen as the trait CBT-05a's executor consumes**.

## Context
- **design/04**: *Range* (the table; ranged 6 requires line of sight), *Line of sight* ("a fixed
  integer hex line between the two tiles; walls block, actors do not; when the line passes exactly
  between two tiles, the lower tile index is taken"), *Facing and arcs* (front, front-side, rear-side,
  back; an actor covers 3 of its 6 neighbours; ranged attacks use the arc of the tile the line of sight
  arrives from; turning once per tick), *Edges*. **design/19**: §2.3 (shapes `SINGLE`, `RING_1`,
  `DISC_1`, `DISC_2`, `DISC_3`; a tile outside the window skipped; walls hold no actor; radius 1 needs no
  line of sight, radius 2–3 not used by MVP content: FX-21), §5.3 step 3 (facing toward the moved-to
  tile or the target; a target not adjacent: the direction of the first step of the hex line), §5.4–§5.6
  (where the arc and "on the front tile" enter a hit), §6. design/18 (the window, perception's radius).
- **`hexx` 0.1.0-rc.1**: its README, `crates/hexx/src/board/line.cairo` (N-5), `board/direction.cairo`
  and `direction/` (N-7), `board/geometry.cairo`, `board/layout.cairo`, the window's assembly (N-3);
  on the VPS at `/home/claude/projects/hexx-cairo`, tag `v0.1.0-rc.1`. **Check its line's tie rule
  against design/04's** (the lower tile index): if it differs, wrap it to design/04's rule or escalate
  (the client's TypeScript mirror depends on it, D-140), with the cases that differ.
- **What exists**: `origami_hexmap` 1.8.0 is still a workspace dependency (`contracts/Scarb.toml`;
  `contracts/logic/tests/test_hexmap.cairo`, a comment in `packing.cairo`). `hexx` is its takeover
  (`crates/takeover_tests`): replace it where `hexx` provides the same, with no figure of the game moving
  (an escalation otherwise). CBT-03a's `Arc` (`types/combat.cairo`, PR #229, merging after Codex's
  reset: if it is not on `main` when you start, define `Arc` the same way, same variants and order, and
  say so). ENG-01's tile index and the window's layout (§3, §9.2), SPK-7's window of 15 × 16 (N-3).
- **CBT-05a's brief** (`docs/briefs/CBT-05a-executor.md`) expects a **geometry trait** (the arc a hit
  arrives from, whether the target is on the source's front tile, a shape's tiles from a centre clipped
  to the window). **This lot defines and freezes it**; CBT-05a consumes it. CBT-03b (wiring the arcs into
  the hit) becomes CBT-05a's call to this trait: say in the report if anything of CBT-03b is left.
- **The cost**: SPK-15's figures (D-172; a worst tick at 22.8 M everything counted, the map library's
  share 1.11 M, 15 hits a worst tick); each call's cost here, and what a worst tick adds (lines of sight
  and arcs for 15 hits, shapes for the carriers), stated against them.
- CAIRO.md §2 (D-167), §7, §8 (D-143, D-147). COMMON.md, D-154, D-149.

## Scope
- In:
  - **The dependency**: `hexx = "0.1.0-rc.1"` from the registry in `contracts/Scarb.toml` (and the
    packages that use it), `Scarb.lock` updated; `origami_hexmap` removed if nothing still needs it.
  - **The geometry trait** in the logic package (a scoped trait over the window, its errors and asserts),
    with: line of sight between two tiles (walls block, actors do not, design/04's tie); the arc of a
    hit (melee and ranged) given the source's tile, the target's tile and facing; "on the front tile";
    the facing an action turns to (§5.3 step 3); a shape's tiles in a fixed order, clipped to the window
    and to walls; range checks (design/04's table).
  - **Tests** in the modules: every rule above, the tie cases of the line, each arc at each of the six
    directions and at range, shapes at the window's edges and corners, D-140's edges (a tile outside the
    window, a wall, the same tile); a vector table (JSON lines, as CBT-03a's `contracts/logic/vectors/`)
    for the client's mirror.
  - **The per-tick budget line**: each call's cost and the worst a tick adds, in the report and in ENG-01
    §9.2 as this lot's row.
- Out: perception and the window's assembly in the tick (ENG-07); generation and reveal (ENG-05, rc.2);
  the executor (CBT-05a); pathfinding (ENG-07's flood).
- Allowlist: `contracts/Scarb.toml`, `contracts/Scarb.lock`, the packages' `Scarb.toml` dependency lines;
  new files under `contracts/logic/src/` for this lot and their module lines; `contracts/logic/src/types/combat.cairo`
  for `Arc` only if it is not on `main` yet; `contracts/logic/tests/test_hexmap.cairo` (the takeover); the
  `origami_hexmap` comment in `packing.cairo`; `contracts/logic/vectors/`; ENG-01 §9.2 (this lot's row) and
  the sections that name `origami_hexmap`; `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is
  an escalation.

## Acceptance criteria
- [ ] AC-1 `hexx` 0.1.0-rc.1 by registry version; `origami_hexmap` gone or its remaining use justified;
      no figure of the game moved by the switch.
- [ ] AC-2 The geometry trait with each rule of design/04 and design/19 above, each tested; the line's
      tie rule equal to design/04's (or wrapped, with the differing cases tested).
- [ ] AC-3 The trait's signature frozen in the report for CBT-05a; CBT-03b's remainder named.
- [ ] AC-4 The vector table for the client's mirror.
- [ ] AC-5 The per-tick budget line in the report and ENG-01 §9.2.
- [ ] AC-6 D-143; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`; `class_sizes.py`.

## Audits
Determinism, D-140 and quality with the organisation lens: `[GPT-6-Sol]`; cost: `[GPT-6-Astra]`; through
`nexus audit` (queued for Codex), a Claude-side lens meanwhile (D-170), then the review.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the switch to `hexx`, the trait and its rules, the tie rule,
the frozen signature, the vectors, the per-tick budget line, the gas table of every test.
