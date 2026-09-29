# ART-02 — ART-00's atlas corrected: scale, Python, the same output on every machine

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, under [ORCH-client-visual](ORCH-client-visual.md) §5 (D-146).

## Agent
Title: `[Opus 5.5] ART-02 atlas scale` · Profile: implement · Launched `--with-assets` on the
owner's Mac with `scripts/mac/agent.sh`

## Goal

After this task, `tools/art/build.py` writes an atlas in which every sprite stands at the height the
pack gives a unit of its build, so that a basic goblin is never taller than a hero; it runs on the
Python its pins need and says so; and its output is the same on the owner's Mac (macOS arm64) and
on the VPS (Linux x86_64), or it carries a fingerprint that is, with the cause of the difference
stated.

## Context

- Design: [docs/design/10-art-direction.md](../design/10-art-direction.md) (the pack, the mapping,
  facing by mirror, the licence); [docs/architecture/ADR-0003-client.md](../architecture/ADR-0003-client.md)
  (render at an integer multiple of the art resolution, nearest-neighbour pixel art, 12–15 fps).
- Decision: [D-146](../decisions/2026-09-29-client-visual-track.md) §5: question ART-1 answered
  **provisionally**: every sprite at the height of the pack's unit of its build (**78, 94 or
  128 px**), a basic goblin never taller than a hero. The final sizes are the owner's, by eye, on
  CLI-03a's sandbox: build the scale so that changing a caste's height is one line of the manifest.
- Depends on: ART-00 (merged). Its report: [docs/reports/ART-00-asset-pipeline.md](../reports/ART-00-asset-pipeline.md).
- **D-73**: the repository is public. Nothing of the pack and nothing derived from it is committed or
  posted on GitHub: no image, no atlas, no screenshot, in the repository, the pull request or a
  comment. Numbers (heights, cell sizes, fingerprints) may be written anywhere.

### What the orchestrator measured on this Mac (`python3.12 tools/art/build.py --check`)

The PixiJS check is green (164 frames, 26 animations). The `out/ sha256:` fingerprint is
`f4c768bf…` here, `eca5e893…` on the VPS (ART-00's report). Visible heights of the frames (px):

| Sprite | Source | Visible height | | Sprite | Source | Visible height |
|---|---|---|---|---|---|---|
| runt | generated | 121–157 | | vanguard | Warrior strip | 84–104 |
| skirmisher | Spear Goblin strip | 81–133 | | warden | Archer strip | 79–90 |
| slinger | Torch Goblin strip | 65–83 | | cleric | Monk strip | 62–71 |
| shaman | generated | 151–199 | | | | |
| hobgoblin | generated | 156–235 | | | | |

The generated sheets are drawn about twice the size of the pack's original units.

## Scope

- In:
  1. **Scale.** Measure, from the pack's original units (`Units/`, `Enemy Pack/`), the three
     reference heights the decision names (78, 94, 128 px): which units define them, how the height
     is measured (the idle pose's visible body, feet to top of head, weapons and effects excluded, or
     another rule you state and apply to every sprite). Give each sprite a **build** in
     `manifest.toml` (one line per sprite, the height derived from the build, overridable per
     sprite), and resample every sprite whose visible height is not its build's height. A basic
     goblin (runt, slinger, skirmisher) is never taller than the shortest hero; the hobgoblin, the
     boss, is the tallest. Resampling of pixel art: choose the filter (and any alpha clean-up after
     it) that keeps the art crisp at non-integer factors, compare at least two on the atlas, state
     the choice and why; the original strips already at their build's height are **not** resampled.
     Every check of ART-00 (key, baseline read back, one cell per sprite, pages, JSON, PixiJS)
     still holds after scaling; the baseline and the anchor follow the scale.
  2. **Python.** Under a Python older than 3.12 (NumPy 2.5.3 needs 3.12; the Mac's `python3` is
     3.11), `build.py` re-executes itself under `python3.12` when it is on `PATH`, and otherwise
     refuses with a clear message naming 3.12, before creating or using a venv. The README says 3.12.
     If the venv exists with another Python, it is rebuilt or refused, not silently used.
  3. **Determinism across machines.** Find why `out/` differs between macOS arm64 and Linux x86_64
     (PNG encoder, zlib, Pillow's wheels, float order in NumPy, dict or file order, anything else),
     and either make `out/` byte-identical on both, or add a fingerprint of the **decoded pixels and
     the metadata** (JSON canonicalised) that is identical on both, printed by the build next to the
     file fingerprint, with the cause stated in the README. You run on the Mac only: write a
     `tools/art/fingerprint.py` (or a `--fingerprint` mode) that the orchestrator runs on Linux
     afterwards, and say exactly what to run.
  4. The report table: sprite → build → target height → scale factor → resulting visible height →
     cell size.
- Out: the client (`client/**`), CLI-03a's sandbox; new sprites or animations (Hurt, Death); the
  slinger's final sprite (ART-2) and the Arcanist (Q-12); the `assets` submodule (never committed,
  never moved); CI (`.github/`).
- Allowlist: `tools/art/**` (not `tools/art/out/`, `.venv/`, `node_modules/`, which git ignores),
  `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 Every sprite's visible height (by the rule you state) equals its build's height within
  ±2 px on its idle frames; the table of Scope 4 is in the report and printed by the build.
- [ ] AC-2 The runt, skirmisher and slinger are no taller than the shortest profession; the
  hobgoblin is the tallest sprite. The build fails otherwise (a check, with its own negative test).
- [ ] AC-3 A caste's height is changed by editing one line of `manifest.toml`; shown in the report by
  a run with one height changed and the table that results (then reverted).
- [ ] AC-4 `tools/art/build.py --check` is green: every check of ART-00 plus AC-2, and the PixiJS
  check (frames, animations, cell sizes, anchors).
- [ ] AC-5 Started by Python 3.11 (`python3 tools/art/build.py` on the Mac), it re-executes under
  3.12; with no `python3.12` reachable, it refuses naming 3.12 before creating or using a venv (shown
  by a test of the selection function, since your profile cannot change `PATH`); from a removed venv
  it bootstraps and builds.
- [ ] AC-6 Two runs on the Mac give the same `out/` (file fingerprint) and the same pixel-and-metadata
  fingerprint; the cause of the Mac/Linux difference is stated with evidence (what you changed or
  measured), and the command for the orchestrator's Linux check is in the report.
- [ ] AC-7 `git ls-files` lists no image, atlas or anything from `out/` or `assets/`; the forbidden-name
  check passes; the pull request body holds no image.

## Verification

```
tools/art/build.py --check
python3 tools/art/build.py               # started by 3.11: re-executes under 3.12
shasum -a 256 tools/art/out/*
git ls-files tools/art
```

Look at the result yourself: `tools/art/out/preview.html` in a browser is not available to you; the
orchestrator looks at it on the Mac. Describe in the report what to look at (the filter's effect on
edges, the feet on the baseline).

## Rules of this run

- You run on the owner's Mac (macOS arm64), not on the VPS. COMMON.md §3's VPS specifics
  (`scripts/lock.sh`, the build shims) do not apply; run `tools/art/build.py` directly (your profile
  allows `tools/*` and `python3 *`, not `python3.12 …` typed), and
  pnpm through `tools/art/build.py --check` or `pnpm --dir tools/art/check --ignore-workspace …`
  (never without `--ignore-workspace`).
- Nothing of the pack leaves the Mac: no image in a commit, the pull request or a comment.
- Pull request: branch `cv/ART-02-atlas-scale` (your worktree is on it, with this brief as its first
  commit), title `fix(tools/art): ART-02, sprites at their build's height, Python 3.12, cross-machine fingerprint`.
  Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Report

`REPORT.md`, header `[Opus 5.5] ART-02 — atlas scale`: summary; files; commands with their real
output; the heights table; the filter comparison; the cross-machine cause and the Linux command;
deviations; escalations; open questions (sizes the owner should look at first).
