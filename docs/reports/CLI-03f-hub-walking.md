# [Opus 5.5] CLI-03f — walking in the hubs

## Summary

The player's adventurer now stands in the town and in the outpost and walks their hex grids,
client-side (D-196). A tap on the ground walks it there one hex per step. A tap on a building walks
it to the door, then opens the place. The service row opens a place at once, and the present
adventurers are still inspected by a tap. Walking to the Gate's door opens the Gate screen. The
machine keeps the adventurer's hex across a service, the Gate screen and back.

Nothing is on chain: no position is sent, checked or stored. The walk is presentation in
`input/hubWalk.ts`, outside `placeholders.ts` and `client/sim` (the project manager's ruling on
Q2).

design/11 *Hubs*'s first line is rewritten as the project manager ruled on Q1, under D-178's
lending.

- Model: Opus 5.5, as the brief names.
- Audit: none (D-177). Owner's eye: requested through the project manager.

## The six design choices, as built

1. **A lighter hub walk.** It reuses the room's geometry (`neighbours` added to `input/coords.ts`,
   tested equal to the library's `next`), its facing, its `move` frames and its pace
   (`HUB_STEP_MS` = `STEP_MS`, 180 ms). It also follows `SandboxSession`'s timer pattern. It uses
   none of the room's rules: no `wiring.ts`, no `placeholders.ts`, no room `Renderer`.
   - The path is a breadth-first search, neighbours taken lowest `y`, then `x`.
   - No preview and no counter. A faint target marker (`HUB_TARGET_ALPHA` 0.28) shows the tapped
     hex while the walk lasts.
   - A tap during a walk retargets from the hex being stepped to, once that step ends.
2. **A building's tap walks to its door, then opens.**
   - The place opens one step after the last step starts, once that step is drawn.
   - Standing on the door, a tap opens at once.
   - A walk that passes over a door opens nothing.
   - A ground tap on a door's hex opens that place, as the building's tap does.
   - The service row and a figure's tap end the walk where it stands and act at once.
3. **Arrival hex**: South-West of the Gate's door in each hub, on the road. In the town it is
   `(2, 0)`; `(2, 1)` holds `rock-2`, as the brief says. In the outpost it is `(1, 1)`.
   - Arriving puts the adventurer there after a report, whatever the outcome.
   - Arriving opens nothing and schedules nothing.
4. **Collisions** (`hubWalkable`, one pure function over the fixtures):
   - A building blocks every hex of its base row and of its `depth` rows behind it whose centre
     lies under the building's width. The door stays walkable for a place; a decor building blocks
     its door too.
   - Props and present figures block their hex.
   - **Deviation, the island's edge**: a hex is walkable when its centre is at least half a hex
     (32 art px) inside the illustration, not "off the border cells". The tileset's edge cells are
     grass except their outer ~12 px (read from the pack on the Mac). Excluding whole border cells
     would have closed the town's road (row 0, where the arrival hex and the Gate's other
     neighbours are), so the Gate's door could not be reached.
   - `depth`: 1 by default. **0 for the town's Market** and **0 for the outpost's straw hut**: with
     1, the front row sealed the road off from every other door. CLI-03e's drawn path climbs
     behind those two buildings, at `(5, 2)` and `(3, 3)`.
5. **The Gate** behaves like every place: walking to its door opens the Gate screen.
   - Back from the Gate screen, the adventurer stays on the door and nothing reopens.
   - `hubGateAt`, `entryThrough`, `hubAfter` and `placeholders.ts` are unchanged
     (`git diff --stat origin/main -- client/app/src/sandbox/placeholders.ts`: empty).
   - The instance's arrival-rule tests pass unmodified.
6. **No camera.** The fit stays fixed through a walk, and every hex of every walk stays inside the
   zone at both sizes (unit test).

## Measured

- **Longest walk from the arrival hex to a door** (`hubPath`, unit test): **16 steps in the town**
  (the Guild), 2.9 s at 180 ms a step; **7 steps in the outpost**, 1.3 s. The brief's estimate for
  the town was about 12 steps.
- **The Smith from the arrival hex**: 9 steps, pinned along the road and up the drawn path.
- **A hex across its flats in the town**: 34.1 points, in the 375 × 599 zone that the CLI-03e tests
  use for 375 × 812.
- **Browser** (Chromium 153.0.8010.12, headless, Mac):
  - town, arrival to `(7, 3)`: 1301 ms at 375 × 812 and 1287 ms at 1440 × 900;
  - `(7, 3)` to the Smith, then its screen: 825 ms and 832 ms;
  - outpost, arrival to `(4, 4)`: 793 ms and 791 ms;
  - `(4, 4)` to the Trainer, then its screen: 797 ms and 826 ms.

## Tests

- New: `input/hubWalk.test.ts` (29 tests), `neighbours` in `input/coords.test.ts`, the walker in
  `render/hubRenderer.test.ts` (5 tests), and the hub's hex in `sandbox/loop/machine.test.ts`
  (4 tests).
- `sandbox/imports.test.ts` gains one assertion: the hub walk imports nothing from
  `placeholders.ts`, `fixtures/region.ts` or the sandbox. It was shown red on a seeded
  `import { TOWN } from "../sandbox/fixtures/region"`, and on a seeded
  `import { findPath } from "../sandbox/placeholders"` (three tests red: this one and two older
  guards). The seeds were removed and the test is green.
- Updated for `at` (they build a hub, service or Gate screen without it), in
  `sandbox/loop/machine.test.ts`:
  - "hub → service → back, hub → Gate screen → back";
  - "inspects a present adventurer of this hub only";
  - "(a) leave on a hub gate's anchor: returned, report, that gate's hub".
- Every other CLI-03c, CLI-03d, CLI-03e and room test passes unmodified. `HubView.arrival` is
  optional for that reason: a view drawn alone, as the CLI-03e tests build one, needs none. The
  loop's fixtures are typed `WalkedHub`, where it is required.
- The older guard "is the only place that computes a path" matches text patterns (`queue.shift(`,
  `visited =`, `frontier`, a function named `find…`/`route…`). `hubWalk.ts`'s search matches none
  of them, so the guard stays green with no allow-list change. The guard is about the instance's
  rules. The hub's search is presentation by the brief's §1 and the project manager's Q2 ruling.

## Commands run

- `pnpm --filter @grimworld/app test`: `Tests 320 passed | 1 skipped (321)` on main before the lot;
  `Tests 360 passed | 1 skipped (361)` after.
- `pnpm --filter @grimworld/app lint`, `typecheck`: clean. `build`: "built", with the existing
  warning that a chunk is larger than 500 kB.
- `pnpm exec prettier --check client indexer`: "All matched files use Prettier code style!"
- `python3 tools/art/build.py` with the pack linked into the worktree by an uncommitted symlink,
  removed afterwards. The vanguard's `move` strip is in the atlas.
- `VERIFY_SHOTS=1 VERIFY_SHOTS_DIR=<thread library> pnpm --filter @grimworld/app verify:hubs`:
  106 checks ok, `ALL CHECKS PASSED`. That covers the CLI-03c/03d loop, CLI-03e's shots and the
  walking pass, in both hubs at both sizes. The shots are untracked, in the thread's library folder
  (D-73).
- `scripts/prepush.sh` before the push.
