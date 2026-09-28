# ART-00 — Asset pipeline, outside git

## Agent
Title: `[Sonnet 5] ART-00 asset pipeline` · Profile: implement · Launched `--with-assets` ·
Branch: `feat/art-00-asset-pipeline`

## Goal
After this task, one command turns the private art pack (the `assets` submodule) into what
the client will load: the MVP sprites cleaned, renamed after our castes and professions, and
packed into atlases, **in a folder git ignores**. The repository holds the pipeline (code,
manifest, documentation) and never an image. Pixel Frog is credited.

## Context
- Design: [docs/design/10-art-direction.md](../design/10-art-direction.md) in full (what
  the pack holds, the mapping to professions and castes, facing by mirroring, missing
  animations, licence and provenance rules); design/05 (castes); design/09 (MVP castes:
  Runt, Slinger, Skirmisher, Shaman, Hobgoblin as boss; professions: Vanguard, Warden,
  Arcanist).
- Decisions: **D-73** (nothing from the pack, nor derived from it, is committed here);
  CONTEXT §8 *Assets* and *Intellectual property*; COMMON.md §5.
- Depends on: FND-03 (merged). Runs in parallel with SPK-5: no shared file.
- What is in the pack (read `assets/README.md` and the README of the generated goblin
  folder under `assets/Enemy Pack/`):
  - Original *Tiny Swords* sprites: `Units/` (Warrior, Archer, Lancer, Monk, Pawn, five
    colours), `Enemy Pack/` (Torch Goblin, Spear Goblin, Hex Shaman, Troll, …), each as
    horizontal strips with generous margins (for example Torch Goblin: 192 × 192 cells;
    Troll: 384 × 384).
  - **Eight generated goblin sheets** (common, hobgoblin, shaman, champion, lord, paladin,
    priest, rider), derived from the Troll: RGB on a **magenta background, no alpha**,
    1536 × 1024, 6 columns × 4 rows of nominal 256 px cells (Idle, Walk, Jump, Attack, six
    poses each); margins are irregular and some weapons cross the nominal cell borders, so
    cutting must follow the silhouettes, not the grid. Hurt and Death do not exist.
  - The sprites face right; left is a mirror (design/10 *Facing*).

## Scope
- In:
  - `tools/art/`: the pipeline, in Python 3 with a virtualenv in `tools/art/.venv`
    (ignored) and pinned `tools/art/requirements.txt` (for example Pillow, numpy), or in
    Node with its own `tools/art/package.json` and lockfile. One entry point, for example
    `tools/art/build.py`, reading from `assets/` and writing to `tools/art/out/`.
  - **Clean-up of the generated sheets**: magenta keyed out to transparency (with the
    anti-aliased fringe handled, not a hard threshold that leaves a pink halo), each pose
    cut along its silhouette, poses re-registered on a common baseline (the feet) and
    re-assembled into regular strips with one cell size per caste.
  - **Renaming after our castes and professions**, driven by a committed manifest
    (`tools/art/manifest.toml` or `.json`): which source feeds which of our names
    (`runt`, `slinger`, `skirmisher`, `shaman`, `hobgoblin`; `vanguard`, `warden`,
    `cleric`), which animations, cell size, frame count, frame rate (12 to 15 frames per
    second, ADR-0003). Use design/10's candidate table; where it offers a choice, take the
    generated sheet when it exists and say so. The **slinger** has no goblin sprite: map it
    to the closest goblin placeholder and list it under *Open questions*. The **Arcanist**
    has none either (Q-12): leave it out and say so.
  - **Atlases**: pack the MVP sprites into texture atlases PixiJS 8 can load (PNG pages +
    JSON in the TexturePacker "hash" format with `animations`), pages at most 2048 × 2048,
    pixel art kept crisp (no resampling, no premultiplied fringe), in `tools/art/out/`.
  - A **preview** page (`tools/art/out/preview.html`, generated) showing every animation
    of the atlases, so that the owner can review the result.
  - **Credit**: `CREDITS.md` at the repository root crediting *Tiny Swords* by Pixel Frog
    (<https://pixelfrog-assets.itch.io/tiny-swords>), saying the pack is used under its
    licence and not redistributed.
  - `tools/art/README.md`: how to get the pack (`git submodule update --init assets`, a
    private repository), how to run the pipeline, what it produces, and the D-73 rule.
  - `tools/art/.gitignore`: `out/`, `.venv/`, caches.
- Out: new art, redrawing or AI generation of sprites; Hurt and Death animations; hex
  terrain (ART-01, a commission); the client's loading code (CLI-03); moving the
  submodule pointer or writing in it.
- Allowlist: `tools/art/**` (except what it ignores), `CREDITS.md`. Anything else is an
  escalation.

## Hard rules
- **No image, audio or font file is committed**, and nothing derived from the pack: the CI
  refuses image files. Run `git status --short` before every commit and read it.
- **No name from the manga** in anything committed: the generated goblin folder's own name
  and README refer to it. Resolve that folder in code without writing its name (for
  example the one subfolder of `assets/Enemy Pack/` that contains `Animated/Raw/`), and
  write `slayer` nowhere under `tools/art/` (a case-insensitive `grep -ri slayer tools/art`
  must print nothing; add this check to the pipeline itself).
- Never commit in `assets/`, never `git add assets`.

## Acceptance criteria
- [ ] AC-1 One command, from a clean clone with the submodule initialised, builds
      `tools/art/out/` (atlases, JSON, preview) and exits 0; run twice, the second run
      gives byte-identical outputs (deterministic).
- [ ] AC-2 Every generated sheet the manifest uses is transparent: no pixel of
      the magenta key (tolerance stated) left in any output frame; the report shows the
      count per sheet.
- [ ] AC-3 Every frame of a caste's animation has the same cell size and the same
      baseline; the preview shows the animations playing.
- [ ] AC-4 The atlas JSON loads in PixiJS 8 (`Assets.load` then `Spritesheet.parse` in a
      small Node or headless check, or a documented manual check with a screenshot kept
      out of git).
- [ ] AC-5 `git ls-files` shows no image file, no file from `assets/`, and
      `grep -ri slayer tools/art CREDITS.md` prints nothing.
- [ ] AC-6 `CREDITS.md` credits Pixel Frog.

## Verification
From the worktree root:
```
tools/art/<entry point>             # build
tools/art/<entry point>             # again; then compare checksums of tools/art/out/
git status --short; git ls-files | grep -iE '\.(png|jpe?g|gif|webp|psd|aseprite)$'   # nothing
grep -ri slayer tools/art CREDITS.md                                                  # nothing
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with a table per sprite: source (described
without the manga's name), our name, animations, cell size, frames, magenta pixels left,
and the atlas page it went to. No cost table (no Cairo).
