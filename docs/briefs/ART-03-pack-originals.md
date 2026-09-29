# ART-03 — Only the pack's own drawings: the generated goblin sheets dropped

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, after the owner's decision of the same day.

## Agent
Title: `[Sonnet 5.5] ART-03 pack originals` · Profile: implement · Launched `--with-assets` on the
owner's Mac with `scripts/mac/agent.sh`

## Goal

The owner decided (2026-09-29) to **ignore the machine-generated goblin sheets** of the art pack (the
subfolder of `Enemy Pack` that `tools/art/build.py` finds by its `Animated/Raw` folder; its name is
written nowhere, and stays so): they were an attempt at new art and are not good enough. After this
task, every sprite of the atlas comes from the pack's own hand-drawn strips, at its native size, and
the pipeline no longer holds the code that only the generated sheets needed.

## The owner's mapping (2026-09-29)

| Our name | Sprite of the pack | Was |
|---|---|---|
| runt (caste) | **Thief** (`Enemy Pack/Thief`) | a generated sheet |
| skirmisher (caste) | Spear Goblin (unchanged) | |
| slinger (caste) | Torch Goblin (unchanged, still a placeholder, ART-2) | |
| shaman (caste) | **Hex Shaman** (`Enemy Pack/Hex Shaman`) | a generated sheet |
| hobgoblin (caste, boss) | **Troll** (`Enemy Pack/Troll`) | a generated sheet |
| vanguard, warden, cleric (professions) | Warrior, Archer, Monk, blue (unchanged) | |

Every sprite **native** (never resampled), as the owner decided for the pack's drawings (D-146 as
corrected). The final sizes stay the owner's eye on the sandbox (the sandbox scales per caste at
display time).

## Context

- `tools/art/` as merged by ART-02 ([report](../reports/ART-02-atlas-scale.md)): `manifest.toml`
  (`kind = "generated"` or `"strip"`, `[height]`, `[order]` with an exemption), `artpipe/clean.py`
  (keying of the magenta sheets, integer unmixing, silhouette cutting, registration), `scale.py`
  (resampling), `png.py`, `fingerprint.py`, `build.py` (Python selection, hashed pins, modes), the
  PixiJS check.
- design/10 (the mapping, to be updated by the project manager with this decision; not yours to
  edit).
- For each new strip, choose the animations as ART-00 did for the others: `idle`, `move`, `attack`
  (and what the strip offers: the Hex Shaman's projectile and explosion, the Troll's attack), frame
  rates 12 for idle and move, 15 for attacks (ADR-0003); read the strips' files to know which exist.

## Scope

- In:
  1. `manifest.toml`: the mapping above; every sprite a `strip`; every height `"native"`.
  2. **The order rule** (`[order]`, AC-2 of ART-02: "a basic goblin never taller than a hero", the
     boss the tallest) now meets only native drawings: report the native heights you measure (Thief,
     Hex Shaman, Troll with the others) and what the rule says about them. If the rule fails on native
     drawings, do not resample anything: make the rule a **warning** printed by the build for native
     sprites (the owner scales them by eye in the sandbox) and keep it an error only for a resampled
     sprite; say which case holds.
  3. **Dead code removed**: whatever only the generated sheets used (the magenta keying and its
     unmixing, the sheet-key measurement, the generated-folder discovery, `kind = "generated"`, their
     tests), unless a strip needs it; the resampler stays (a height in px remains possible in the
     manifest) with its tests. The forbidden-name check stays, and still covers `tools/art` and
     `CREDITS.md`.
  4. README and the manifest's comments updated; `CREDITS.md` untouched unless it names the generated
     sheets (then escalate: it is not in your allowlist).
  5. The build's table and both fingerprints printed; `--check` green (PixiJS: frames, animations,
     cells, anchors).
- Out: the client (`client/**`: the sandbox reads `sprites.json`, sprite names unchanged); new
  animations beyond what the strips hold; the Arcanist (Q-12); tiles and terrain (a separate search is
  running).
- Allowlist: `tools/art/**`, `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 The atlas holds the eight sprites of the mapping, all from strips, all native; the table
  prints each native height.
- [ ] AC-2 No code path, test or manifest entry for the generated sheets remains; the forbidden-name
  check passes.
- [ ] AC-3 The order rule's behaviour on native drawings is stated and tested.
- [ ] AC-4 `tools/art/build.py --check` green; the unit tests pass; two builds give the same
  fingerprints.
- [ ] AC-5 Nothing of the pack in git or the pull request (D-73); no folder name of the generated
  sheets written anywhere.

## Rules of this run

- You run on the owner's Mac; `tools/art/build.py` directly (your profile allows `tools/*`).
- Pull request: branch `cv/ART-03-pack-originals` (your worktree is on it, with this brief as its
  first commit), title `feat(tools/art): ART-03, only the pack's own drawings`. Commits end with
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. `gh pr edit` fails on this machine
  (a GitHub deprecation): if you need to change the body after creating the pull request, put the
  text in REPORT.md under "PR body". Wait for the CI in the foreground.

Foreground only: never run a command in the background and never end your turn waiting for one.

## Report

`REPORT.md`, header `[Sonnet 5.5] ART-03 — pack originals`: summary; the new table (sprite, source
strip, animations and frames, native height, cell); the order rule's outcome; what was removed;
commands with their real output; the fingerprints; deviations; escalations.
