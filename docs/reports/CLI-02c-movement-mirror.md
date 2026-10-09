# CLI-02c — The movement mirror in client/sim

Lot CLI-02c, track CV, 2026-10-09. ENG-07 (#392, f93518a) added
`contracts/logic/vectors/movement.jsonl`: 81 cases of the moves, the window, the flood and the
awake set. This lot mirrors them in `client/sim` and replays the table in place, as the other
mirrors are replayed (`src/parity/`).

## What is mirrored

| `fn` | Cases | Cairo | Mirror |
|---|---|---|---|
| `origin` | 13 | `SegmentTrait::board`'s origin (`types/play.cairo`), `hexx`'s `AssemblyTrait::origin`, `BoardTrait::position` (`types/executor.cairo`) | `movement.ts`: `origin`, `board`, `position` |
| `move` | 48 | `hexx`'s `LayoutTrait::neighbor` on the window, through `WindowAssert::direction` | `window.ts`: `neighbor` (new; `front` now uses it) |
| `ticks` | 7 | `TickMathTrait::move_ticks` (`helpers/tick.cairo`) | `movement.ts`: `move_ticks` |
| `flood` | 10 | `hexx`'s `Bfs::flood`, `FloodTrait::next_step`, `FloodTrait::distance` | `movement.ts`: `flood`, `next_step`, `flood_distance` |
| `awake` | 3 | `TickTrait::awake` and `woken` (`types/world.cairo`) | `movement.ts`: `awake` |

`window.ts` already held the window's directions and axial coordinates. The Move's tile reuses them
through a new `neighbor`, so no direction table was duplicated. `window.ts` had no origin or local
tile, so those live in `movement.ts`.

The one place where the mirror computes differently: `hexx` builds the flood by dilating limbs. The
mirror builds each layer tile by tile from `neighbor`, with the same sets: the walkable interior,
minus the obstacles and the source, layers 1 to `depth`, and none after the first empty layer.

## How the table is replayed

The table is one entry of `TABLES` (`src/parity/tables.ts`, floor 81). Each case's felts are
adapted as the table's README defines them:
- 255 is `None`.
- `flood` runs from the case's source, with no obstacle, capped at 15 layers, and no walker blocked.
- `awake` uses goblin entities `8 + k`, all alive, with the fourth (k = 3) asleep.

`parity.test.ts` pins the count of each `fn` (origin 13, move 48, ticks 7, flood 10, awake 3).
Two things fail the replay:
- a case with an unknown `fn`;
- a new case of a known `fn` (it fails the count).

All 81 cases pass.

## Mutants

Twelve mutants were added to `src/parity/mutants.test.ts`. The table kills 8 of them:
- the origin's row parity;
- the origin's column, off by one;
- Crippled's deadline, made exclusive;
- `MOVEMENT` not lifting Crippled;
- the distance not plus one;
- the awake set's ties going to the highest entity;
- a sleeping goblin woken;
- an awake set of 9.

Four survive. Each is marked `survives` and is a gap in the table, for track game:

1. **The flood one layer past its cap.** No walker stands at distance 15 or 16 from the source. The
   corridor's walkers are at distance 12 to 13, or beyond the cap.
2. **The D-25 check at the cap removed.** No walker touches only the last layer at the cap. A walker
   at distance 16 would show it: its step is 255 and its distance 16.
3. **A tie in the step broken by the highest index.** No walker has two neighbours in its least layer.
4. **The flood walking the window's ring.** The grid has no open tile on the ring (an edge entrance).

Each one needs a flood case: a walker at distance 15, a walker at distance 16, a walker with two
candidate steps, and a grid with an open ring tile. The table is never edited from here.

## Commands

```
pnpm --filter @grimworld/sim test        # 7 files, 97 tests passed
pnpm --filter @grimworld/sim lint        # clean
pnpm --filter @grimworld/sim typecheck   # clean
pnpm exec prettier --check client/sim/src
```

## Not changed

`client/sim/README.md` still lists "the tick (CLI-02c, ENG-07)" as not yet mirrored, and its table
has no `movement.ts` row. The README is outside this lot's allowlist (`client/sim/src/**`), so it is
left for the next docs change of the track.
