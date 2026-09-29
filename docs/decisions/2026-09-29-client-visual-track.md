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
5. **Question ART-1 answered provisionally**, *corrected by the owner the same day (below)*: the pack's hand-drawn units keep their native height (no resampling, no non-integer factor); only the generated goblin sheets are reduced to the scale of the pack's units (runt about 67–70 px, shaman about 87, hobgoblin about 119). The final sizes are the owner's eye on CLI-03a's sandbox, a line of the manifest.
6. **Nothing of the pack is posted on GitHub**, screenshots included: the repository is public
   (D-73).

## Amended, 2026-09-29 (answering the track's `PENDING-cv-mandate.md`, #118)

- The account check on the Mac reads the sub-agents' own configuration:
  `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status` shows claude-b7r, and the Mac's launcher
  forces that variable for every sub-agent; the default configuration stays the app's (bal7hazar).
- The track's briefs include `CV-*`; the macOS launcher is CV-01.

## Amended, 2026-09-29, the budget (owner)

The Mac has 12 cores and 64 GB, load about 3: **5 agents at a time on the Mac**, audits included,
with the load check of the VPS scaled to 12 cores (load above 18 or under 8 GB available: no new
launch). The Mac's launcher (CV-01) enforces them. Tasks lent by the game count in the 5 (D-149).

## Corrected, 2026-09-29, the sprites' heights (owner, option B of `PENDING-cv-art-heights.md`, #136)

78, 94 and 128 px were not heights of the pack's units: they were the targets the folder of
generated goblins had set for its own sprites (common goblin, shaman, hobgoblin). The Mac's
message called them the pack's target heights, and point 5 applied them to every sprite. The
owner's decision: the hand-drawn units keep their native height, with no resampling (a
non-integer factor damages pixel art); only the generated sheets are reduced, to the scale of
the pack's units (runt about 67–70 px, shaman about 87, hobgoblin about 119); the final sizes
are the owner's eye on CLI-03a, a line of the manifest. ART-02 (#134) follows it before its merge.

## What would reverse it

The owner preferring the game orchestrator to merge, or the art direction choosing other sizes.
