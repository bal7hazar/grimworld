# CLI-03b — The sandbox: sprites standing in their tile, a planned path to a far tile

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, after the owner's first look at CLI-03a's sandbox.

## Agent
Title: `[Opus 5.5] CLI-03b sandbox path` · Profile: implement · Launched on the owner's Mac with
`scripts/mac/agent.sh`

## Goal

The owner looked at the sandbox (CLI-03a, merged in #135) and said, in French: the character is
badly centred on its hex tile, and tapping a far tile does not walk there. After this task, every
sprite reads as standing **in** its tile, and a tap on a far floor tile draws the planned path with
its cost and walks it step by step, stopping as design/02 says, all within the rules of the mandate
(the path finding is a placeholder of the chain's rule).

## Context

- The sandbox: `client/app/src/` as merged by CLI-03a; its [report](../reports/CLI-03a-render-sandbox.md)
  and the mandate's §6 ([ORCH-client-visual](ORCH-client-visual.md)): no rule in `client/app` except
  in `sandbox/placeholders.ts`, each marked `PLACEHOLDER until CLI-02`; a tap produces an intent,
  never a result; on demand, no render loop.
- What the orchestrator saw (meadow, zoom 5): the sprites' feet are anchored at the **centre** of the
  hex (the atlas's anchor is the feet: `anchor = (0.5, baseline / cell height)`, tools/art/README.md);
  a sprite is taller than a tile (the vanguard is 87 art px for a 64 px tile), so its body stands in
  the tile above and the tile it is on cannot be read at a glance.
- design/11: *Acting* (Move: "the path is drawn, with its cost in ticks; tiles where the path would
  be interrupted are marked"), *The queue* (a planned queue only; ghost markers and a counter; walked
  one step at a time, each drawn as it is played; stops by itself with the remaining steps fading out
  and the reason in one line; cancel by tapping the counter).
- design/02 *The planned queue and its stop conditions*: the client walks the queue itself and stops
  when the adventurer takes damage or gains a condition; a goblin enters sight, becomes alerted or
  starts activating a skill; a chunk is revealed; the next step would be a Fate action; the next step
  is invalid.
- The chain's path finding is the map library's (`hexx`, ported in `bal7hazar/hexx-cairo`, the flood
  of the tick); its mirror is CLI-02's. Here it is a placeholder.

## Scope

- In:
  1. **Sprites in their tile.** A per-sprite foot offset: the feet placed below the tile's centre so
     that the body reads as standing in the tile, the same rule for every sprite (for example the feet
     at a fixed fraction of the hex's inner radius below the centre), with its value adjustable in the
     debug panel next to the sprite scales so that the owner sets it by eye, and a URL parameter.
     Check with the facing wedge, the arcs' tints, the state marks and the selection: each must still
     point at or sit on the right tile. The drawing order (zIndex by row) must stay right with the
     offset. Shapes (no atlas) follow the same rule.
  2. **A planned path to a far tile** (design/11, design/02):
     - `placeholders.ts` gains `findPath(terrain, actors, from, to)` (**PLACEHOLDER until CLI-02**,
       design/02 and the map library's finder): the shortest path over floor tiles, avoiding walls,
       unrevealed tiles and occupied tiles, ties broken by the design's convention (lowest tile
       index), bounded (the window of 15 × 16 around the adventurer, D-120); no path is an answer
       too. Its cost in ticks: one tick a step (a placeholder; say so).
     - A tap on a far floor tile shows the path (ghost markers and the cost) as a **preview**; a second
       tap on the same tile, or a setting "play on first tap" (design/11: move is played on the tap;
       keep the design's default and note the choice), walks it.
     - The walk: one step at a time, each step through the same placeholder step as a tap, drawn as it
       is played (the step animation), the camera following; the counter of remaining steps shown in
       the sandbox (a minimal counter; the real HUD is CLI-05/CLI-08); a tap on the counter cancels.
     - The stop conditions of design/02 that the sandbox's placeholders can evaluate: a goblin enters
       sight, a chunk is revealed, the next step is invalid (occupied, wall); the others (damage,
       conditions, activations, Fate actions) are listed as not available in the sandbox. On a stop
       the remaining steps fade out and one line says why ("a skirmisher came into sight").
     - Timing of the walk: a fixed step duration (the step animation's), a parameter; the renderer stays
       on demand (frames only while a step animates, none between inputs once the walk ends).
  3. **Tests**: the foot offset (a sprite's feet at the expected pixel for each facing and zoom; the
     wedge and selection unchanged); `findPath` (a straight line, around a wall, around an actor, no
     path, the tie rule, the window bound); the walk (N steps played one by one; each stop condition;
     cancel); the power rules (no frame after the walk settles).
- Out: the real HUD (CLI-05, CLI-08), attacks and approach-and-attack, optimistic state and rewind
  (CLI-03), `client/sim` (never), `tools/art`.
- Allowlist: `client/app/src/**` except `client/app/src/account/**`, `chain.ts` and its test;
  `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 Every sprite stands in its tile at every zoom and scale mode, with the offset adjustable by
  eye; wedge, arcs, marks and selection unchanged.
- [ ] AC-2 A tap on a far floor tile previews the path and its cost; walking it plays the steps one by
  one, with the camera following; the counter cancels.
- [ ] AC-3 The walk stops on the stop conditions the sandbox can evaluate, with the remaining steps
  fading and the reason in one line.
- [ ] AC-4 `findPath` lives in `placeholders.ts`, marked, and nothing else in `client/app` computes a
  path (the imports test extended).
- [ ] AC-5 On demand: nothing is drawn once the walk has ended (a test).
- [ ] AC-6 test, lint, typecheck, build, `prettier --check client indexer` pass; CI green.

## Rules of this run

- You run on the owner's Mac. No browser for you: the orchestrator and the owner look at it; write in
  the report what to look at. The atlas is served in development from `GRIMWORLD_ART_OUT` or the
  checkout's `tools/art/out/` (build it with `tools/art/build.py` if you need it: it needs the
  `assets` submodule, which your worktree has not; work with shapes otherwise).
- Nothing of the pack in git or the pull request (D-73).
- Pull request: branch `cv/CLI-03b-sandbox-path` (your worktree is on it, with this brief as its first
  commit), title `feat(client): CLI-03b, sprites in their tile, a planned path in the sandbox`.
  Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Wait for the CI in the
  foreground.

## Report

`REPORT.md`, header `[Opus 5.5] CLI-03b — sandbox path`: summary; files; the foot offset rule and its
default; `findPath` and what it stands for; the walk and its stops; commands with their real output;
what to look at in the browser; deviations; escalations.
