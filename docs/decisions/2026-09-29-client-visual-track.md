# Track CV: the client's visual work on the owner's Mac

| | |
|---|---|
| Asked by | The owner's session on the Mac, relayed by the owner, 2026-09-29 |
| Decided by | `[Opus 5.5]` project manager, under D-128; reversible by the owner |
| Mandate | [ORCH-client-visual](../briefs/ORCH-client-visual.md) |

## Why

The client's visual work needs a browser the agents can drive; the VPS has none, the owner's Mac
does. Three findings on ART-00's atlas, made in a real browser: the sprites are not resampled (a
basic goblin, the Runt, 121 to 157 px high, would be taller than a hero, 84 to 104 px; the
Hobgoblin up to 235 px); the pipeline says Python 3.11+ while its pinned NumPy needs 3.12; the
fingerprint of `out/` is stable on each machine but differs between the Mac and the VPS.

## Decided

1. **A fourth track, CV**, run by a local orchestrator on the Mac under OPERATIONS.md. It writes
   `client/app` (rendering, interface, input; not `account/` or `chain.ts`, which stay CLI-01's)
   and `tools/art` (moved from the game's track); never `contracts/`, `client/sim`, `.github/` or
   the shared documents. Needs outside it go through `PENDING-cv-*` files to the project manager.
2. **It merges its own pull requests** in that scope, on green CI and closed audits, like the other
   orchestrators; a pull request with a path outside the scope is not merged and is escalated.
   Having the game orchestrator merge would add a round trip for no check the rules do not already
   make.
3. **Budget**: 2 agents at a time on the Mac, audits included, apart from the VPS's 3 (D-118).
   The CLI must show claude-b7r before the first launch.
4. **First tasks**: ART-02 (scale, Python, determinism across machines), CLI-03a (a rendering
   sandbox on fixed data), SPK-6a (the protocol of SPK-6). CLI-03a keeps every rule in
   `client/sim` and renders a view state (mandate §6).
5. **Question ART-1 answered provisionally**: every sprite at the height of the pack's unit of its
   build (78, 94 or 128 px), a basic goblin never taller than a hero. The final sizes are the
   owner's eye on CLI-03a's sandbox.
6. **Nothing of the pack is posted on GitHub**, screenshots included: the repository is public
   (D-73).

## What would reverse it

The owner preferring the game orchestrator to merge, or the art direction choosing other sizes.
