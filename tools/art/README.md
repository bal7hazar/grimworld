# tools/art — asset pipeline

Turns the private art pack into what the client loads: the MVP sprites cleaned, renamed after
our castes and professions, and packed into atlases.

**The D-73 rule.** The pack (*Tiny Swords* by Pixel Frog, see [CREDITS.md](../../CREDITS.md)) may
not be redistributed, even modified. So this folder holds the pipeline (code, manifest,
documentation) and **never an image**: everything the pipeline writes goes to `out/`, which git
ignores. Never commit anything from `out/` or from `assets/`; the CI refuses image files and
atlas descriptors.

## Get the pack

The art is the submodule `assets`, a private repository (`tiny-swords`):

    git submodule update --init assets

Without access to it, the rest of the repository still builds; only the art is missing.

## Run

    tools/art/build.py

One command. On first run it creates `tools/art/.venv` and installs the pinned
`requirements.txt` (Pillow, NumPy), then re-runs itself inside it; it needs Python 3.11+ and a
network the first time. It reads `assets/` and `manifest.toml`, rewrites `out/`, prints a table
and exits 0. It is deterministic: two runs give byte-identical files (compare the `out/ sha256:`
line, or `sha256sum tools/art/out/*`). It fails if a check fails (see below).

## What it produces (`out/`)

| File | Content |
|---|---|
| `atlas-N.png`, `atlas-N.json` | Atlas pages, at most 2048 × 2048. The JSON is TexturePacker "hash" format with `animations`, ready for PixiJS 8. A sprite never straddles two pages |
| `sprites.json` | Index: for each sprite its page, cell size, baseline, animations (frames, fps, loop) |
| `report.json` | Per sprite: source, cell, frames, magenta pixels left, page; per generated sheet: key colour, dropped specks |
| `preview.html` | Every animation playing, with cell / baseline / anchor guides, zoom, mirror, background. Open it in a browser |

Names: frames are `<sprite>/<animation>/<nn>` (`runt/attack/03`), animations `<sprite>/<animation>`
(`hobgoblin/move`). Every frame carries `sourceSize` = the sprite's cell (one size per sprite),
`spriteSourceSize` (the trim offset in the cell) and `anchor` = (0.5, baseline / cell height), so
placing the sprite at its tile position puts the feet on it. Frame rates and looping are in
`meta.animationRates` and in `sprites.json`. Sprites face right; left is a mirror (`scale.x = -1`).

## What it does

1. **Keying.** The generated goblin sheets are RGB on a noisy magenta, no alpha. The key colour is
   measured on each sheet's border; pixels within `key_tolerance` (48, max-channel distance) of
   it become transparent. Around them, anti-aliased edge pixels are treated as `a·fg + (1−a)·key`:
   alpha is estimated and the key colour subtracted back out, so there is no pink halo.
2. **Cutting.** Poses are cut along their silhouettes (connected components), not along the
   nominal 256 px grid. A detached spark or projectile follows the nearest body, in its row.
3. **Registration.** The feet of each pose (the lowest row that is not a thin tip) are put on one
   baseline and one horizontal anchor; every frame of a sprite gets the same cell size.
4. **Packing.** Frames are trimmed and shelf-packed with a 2 px gutter. Nothing is resampled, and
   colours are straight (non-premultiplied) RGBA, so pixel art stays crisp with nearest-neighbour
   scaling.
5. **Checks** (the build fails otherwise): no pixel within the key tolerance is left in any
   output frame; pages ≤ 2048; frames inside pages, none overlapping; one cell size per sprite;
   the baseline of every frame read back from the written PNG; JSON references valid; and no
   trace of the manga's name in `tools/art` or `CREDITS.md`.

The generated-sheet folder is found in code (the one subfolder of `assets/Enemy Pack` holding
`Animated/Raw`); its name is written nowhere here.

## The manifest

`manifest.toml` says which source feeds which of our names: `runt`, `slinger`, `skirmisher`,
`shaman`, `hobgoblin` (castes); `vanguard`, `warden`, `cleric` (professions, blue units), with
animations, source rows or files, frame rates (12 to 15, ADR-0003) and looping. Where design/10
offers a choice, the generated sheet is taken when it exists. The `slinger` is a placeholder (no
goblin slinger exists); the Arcanist has no sprite (Q-12) and is left out.

## PixiJS 8 check

`check/` is a small Node package of its own (exact `pixi.js` version of `client/app`, lockfile
committed). It is **not** part of the root pnpm workspace: always pass `--ignore-workspace`,
otherwise pnpm installs the whole workspace. It parses each atlas with PixiJS's own
`Spritesheet` (the PNG is replaced by a texture stand-in of its real size) and checks that every
animation of `out/sprites.json` resolves to frames of the right count and cell size.

    tools/art/build.py --check          # build, then the check
    pnpm --dir tools/art/check install --ignore-workspace --frozen-lockfile   # by hand
    pnpm --dir tools/art/check --ignore-workspace run check                   # after a build

Node and pnpm come from `.tool-versions` (`scripts/setup-toolchain.sh`).

## Loading in PixiJS 8

    import { Assets, AnimatedSprite } from 'pixi.js';
    const sheet = await Assets.load('atlas-0.json');   // next to atlas-0.png
    const s = new AnimatedSprite(sheet.animations['hobgoblin/move']);
    s.animationSpeed = 12 / 60; s.play();               // anchor comes from the JSON

Pixel art: set `scaleMode = 'nearest'` on the texture source.
