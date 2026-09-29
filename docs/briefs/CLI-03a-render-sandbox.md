# CLI-03a — A rendering sandbox on fixed data

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, under [ORCH-client-visual](ORCH-client-visual.md) §5 and §6 (D-146).

## Agent
Title: `[Opus 5.5] CLI-03a render sandbox` · Profile: implement · Launched on the owner's Mac with
`scripts/mac/agent.sh` (without the `assets` submodule: the orchestrator builds the atlas when it looks)

## Goal

After this task, `pnpm --filter @grimworld/app dev` opens a sandbox in which a hexagonal map is drawn
**on demand** from fixed data: the adventurer and about ten goblins with their sprites (or plain
shapes when the atlas is not built), a camera that follows the adventurer, what is in sight (radius 6)
and what was seen before, facing and the arcs of a selected goblin, and touch input that turns a tap
into an **intent** (a target tile). It works in a phone's portrait viewport (375 × 812) and on a
desktop window. It holds **no rule of the game**: what the chain decides is read from fixtures or from
one file of placeholders that CLI-03 deletes. It is the ground on which the owner sets the sprites'
sizes by eye, and the build SPK-6 measures on real phones.

## Context

- Mandate §6, **binding**: [ORCH-client-visual](ORCH-client-visual.md) §6, points 1–6 (no rule in
  `client/app`; the design's conventions; the renderer's input is a view state; pixels ↔ tiles are
  presentation; on demand, no render loop; no randomness and no clock in anything `client/sim` will
  decide).
- ADRs: [ADR-0003](../architecture/ADR-0003-client.md) (PixiJS on demand; **power budget rules**;
  mobile first; SPK-6's thresholds), [ADR-0006](../architecture/ADR-0006-chunked-maps.md) (chunks of
  15 × 15, the window 15 × 16 whose origin is on an even global row, D-120; the camera follows the
  adventurer, pinch and pan; an unrevealed chunk is wall, D-136).
- Design: [11-interface](../design/11-interface.md) (rules I-1…I-7, what the rules need to show,
  desktop), [18-rooms](../design/18-rooms.md) (*What the adventurer sees*: sight radius 6, dimmed
  terrain beyond, traps hidden), [04-combat](../design/04-combat.md) *Facing and arcs (D-41)* (six
  facings, four arcs), [10-art-direction](../design/10-art-direction.md) (*Hex grid with a square
  tileset*: continuous ground, hex outline overlay, walls as obstacle objects; *Facing*: mirror for
  the three left directions, a wedge to the front tile).
- Hex conventions: **pointy-top** (D-11); the coordinates, directions and **their numbering** of
  `hexx` as ported in [`bal7hazar/hexx-cairo`](https://github.com/bal7hazar/hexx-cairo) (public; read
  its files with WebFetch on `raw.githubusercontent.com`, clone nothing), and the offset layout of
  `origami_hexmap` that the window uses (D-120), as `contracts/` of this repository consumes it. Where the two disagree or the
  numbering is unclear, stop that part and escalate: do not choose.
- The client today: `client/app` (Vite 8, React 19, PixiJS 8.21.0, `frame.ts` renders one placeholder
  tile on demand), `client/sim` (`exp2` only). CLI-01 (`account/`, `chain.ts`) and CLI-02 (the
  simulation mirror) are not started.
- The art: `tools/art/build.py` writes `tools/art/out/atlas-*.{png,json}` and `sprites.json` (see
  [tools/art/README.md](../../tools/art/README.md): frame names, anchors on the feet, sprites face
  right). ART-02 runs in parallel and changes the sprites' sizes: read the sizes from `sprites.json`,
  never hard-code a pixel height.

## Scope

- In:
  1. **The view state** `client/app/src/render/view.ts`: a type, and nothing but data. Tiles (global
     offset coordinates, kind: floor, wall, unrevealed; seen now, seen before), actors (id, caste or
     profession, tile, facing 0–5, state marks: asleep, alerted, engaged), the tiles in sight, the
     arcs of a selected actor as four lists of tiles, the planned path as tiles, a selected tile.
     CLI-02 or CLI-03 will produce it from `client/sim`; here, fixtures produce it.
  2. **Fixtures** `client/app/src/sandbox/fixtures/`: at least three, chosen by a URL parameter
     (`?fixture=`): an open meadow with a pack asleep; a cave with walls, chokepoints and a pack on
     watch; the edge of the unrevealed (a chunk not revealed is wall, D-136). Ten actors in one of
     them (SPK-6's row: "a room of 15 × 15 with 10 animated actors").
  3. **Placeholders** `client/app/src/sandbox/placeholders.ts`, the **only** file that computes
     anything the chain decides (a step to a neighbouring floor tile, a turn, the tiles in sight, the
     arcs of a facing), each function marked `PLACEHOLDER until CLI-02` with the design section it
     stands for; no randomness, no clock. A test checks that no other file of `client/app/src/`
     imports it except the sandbox's wiring.
  4. **The renderer** `client/app/src/render/`: PixiJS 8, **on demand**: no ticker running, one
     `render()` per change, animation frames only while something animates (a step, a turn, idle
     animations at their 12–15 fps) and none after; idle animations can be turned off, and then
     nothing is drawn between two inputs; everything stops when the page is hidden. Static layers
     (ground, walls, grid) baked into one texture, rebuilt when the tiles change. Resolution: an
     integer multiple of the art, capped at 2× device pixels. Nearest-neighbour scaling for pixel
     art. Walls as obstacle objects and a continuous ground (design/10); plain shapes are fine where
     the pack has nothing.
  5. **Showing the rules** (design/11 table): the facing wedge on every actor's tile; the selected
     goblin's back and rear-side tiles tinted, with a shape, not only a colour; sight: tiles in sight
     bright, seen before dimmed, goblins only in sight; state marks over goblins; sprites mirrored for
     the three left facings.
  6. **Camera**: follows the adventurer (eased pan on a step, rendered on demand), pinch to zoom and
     drag to pan on touch, wheel and drag on desktop, back to the adventurer on a button. Zoom levels
     as a parameter: at the default zoom on 375 × 812, the whole sight (13 tiles across) fits the
     width; say what tile width that gives, against I-6's 40 points. **Do not decide the size**: the
     owner and SPK-6 do; expose it.
  7. **Input** `client/app/src/input/`: pixel → tile and tile → pixel (pure functions, tested both
     ways on every tile of a window, at several zooms); a tap produces an intent `{ kind: "tile", tile }`
     (never a result); a long press produces `{ kind: "inspect", tile }`; tap outside clears. The
     sandbox's wiring applies an intent through the placeholders and redraws.
  8. **A debug panel** of the sandbox only (fixture, zoom, idle animations on/off, a render counter
     and the number of frames drawn since the last input, the sprites' scale per caste read from
     `sprites.json` and adjustable, so that the owner can try sizes by eye).
  9. **The atlas in development only**: Vite serves `tools/art/out/` to the dev server when it
     exists (a dev-only middleware or alias in `vite.config.ts`); nothing of it is imported by a
     module, copied into `dist/` or committed. Without it (CI, a clone without the pack) the sandbox
     draws shapes and every test and `pnpm build` pass.
- Out: the HUD zones of design/11 (status, target, skill bar, belt: CLI-05, CLI-08); paths and their
  costs, the queue, optimistic state and rewind (CLI-03); anything of the chain; Capacitor (CLI-01,
  SPK-6); `client/sim` (never: a need there is an escalation); new sprites; `tools/art`.
- Allowlist: `client/app/src/**` except `client/app/src/account/**`, `client/app/src/chain.ts` and
  `chain.test.ts`; `client/app/index.html`; `client/app/vite.config.ts`; `client/app/package.json`
  and `pnpm-lock.yaml` for rendering, input or development dependencies only, each addition named and
  justified in the pull request (prefer none); `REPORT.md`. `App.tsx` and `main.tsx` may mount the
  sandbox (CLI-01 is not started).

## Acceptance criteria

- [ ] AC-1 `pnpm --filter @grimworld/app dev` serves the sandbox; `?fixture=` selects each fixture;
  with the atlas built, sprites are drawn from it; without it, shapes.
- [ ] AC-2 On demand: a test drives the renderer with a fake PixiJS application or a counter and
  shows that after an input and its animation settle no frame is scheduled; with idle animations on,
  frames are drawn at ≤ 15 per second and only for the animated sprites' changes; with them off,
  zero frames between inputs; none while the page is hidden.
- [ ] AC-3 Pixel ↔ tile round trip on every tile of a 15 × 16 window, both row parities of the
  origin, at three zooms; a tap on the boundary between two tiles is resolved by one stated rule.
- [ ] AC-4 The six facings: wedge direction and sprite mirror checked for each, against the
  direction numbering of the hex library (cited in a comment and the report).
- [ ] AC-5 Every function that stands for a rule of the chain is in `placeholders.ts`, marked, and
  imported only by the sandbox's wiring (a test).
- [ ] AC-6 `scripts/lock.sh`-free on the Mac: `pnpm --filter @grimworld/app test`, `lint`,
  `typecheck`, `build` pass, and `pnpm exec prettier --check client`; the pull request's CI is green.
- [ ] AC-7 Nothing of the pack in git or in the pull request: no image, no atlas, no screenshot
  (D-73); `dist/` holds no file from `tools/art/out/`.

## Verification

```
pnpm install --frozen-lockfile
pnpm --filter @grimworld/app test
pnpm --filter @grimworld/app lint
pnpm --filter @grimworld/app typecheck
pnpm --filter @grimworld/app build
pnpm exec prettier --check client
```

You have no browser. The orchestrator looks at the sandbox on the Mac in a real browser, at
375 × 812 and on a desktop window, and resumes you with what it sees: make the sandbox easy to
inspect (the debug panel, fixtures by URL, a clear console on error), and write in the report what to
look at.

## Rules of this run

- You run on the owner's Mac, not on the VPS: COMMON.md §3's VPS specifics (`scripts/lock.sh`, the
  build shims) do not apply; run `pnpm` directly. `node` is 22.22.2 here while `.tool-versions` pins
  24.21.0 (not installed): the CI runs 24; report anything that differs.
- Nothing of the pack leaves the Mac: no image, atlas or screenshot in a commit, the pull request or a
  comment. Your worktree has no `assets` submodule and no atlas: do not build one (`tools/art` is ART-02's,
  running in parallel). Write the atlas path so that it works once `tools/art/out/` exists, test the
  loading against a small synthetic atlas made in the test (plain colours, never from the pack), and
  work with shapes otherwise.
- Pull request: branch `cv/CLI-03a-render-sandbox` (your worktree is on it, with this brief as its
  first commit), title `feat(client): CLI-03a, a rendering sandbox on fixed data`. Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Report

`REPORT.md`, header `[Opus 5.5] CLI-03a — render sandbox`: summary; files; commands with their real
output; the view state's type; the placeholders and the design sections they stand for; the default
zoom and the tile width it gives on 375 px; what to look at in the browser; deviations; escalations
(any convention of the hex library you could not settle); open questions for the owner (sizes, zoom).
