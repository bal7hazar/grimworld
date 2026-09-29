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

One command. It needs **Python 3.12** or newer (NumPy 2.5.3 needs it) and a network the first
time. Started by an older Python (`python3` is 3.11 on some Macs), it re-executes itself under
`python3.12` when that is on `PATH`, and otherwise refuses, naming 3.12, before it creates or uses
anything. On first run it creates `tools/art/.venv` and installs the pinned `requirements.txt`
(Pillow, NumPy), then re-runs itself inside it; a `.venv` made with another Python is deleted and
rebuilt. It reads `assets/` and `manifest.toml`, rewrites `out/`, prints two tables and exits 0. It
fails if a check fails (see below).

    tools/art/build.py --resample=nearest    # another resampling filter (default: the manifest's)
    tools/art/build.py --pack-heights        # the visible height of every unit of the pack
    tools/art/build.py --fingerprint         # the fingerprints of the existing out/, no build
    tools/art/.venv/bin/python -m unittest discover -s tools/art/tests

## Same output on every machine

The build prints two fingerprints of `out/`:

    out/ sha256: …                      every file's bytes
    out/ pixels+metadata sha256: …      every PNG decoded to RGBA, every JSON canonicalised
    encoders: zlib (python) …, zlib (Pillow) …, Pillow …, NumPy …

Two runs on one machine give the same two lines. Across machines, compare the second one: it holds
what the client loads (pixels and data), whatever compressed it. **Why the files differed between
macOS arm64 and Linux x86_64 (ART-00):** the pixels were never the question; Pillow 12's wheels
compress PNGs with zlib-ng (`zlib (Pillow) 1.3.1.zlib-ng`), whose output depends on the build
and the CPU's code paths. The pipeline now writes PNGs itself (`artpipe/png.py`: Paeth filter in
NumPy, Python's own `zlib` at level 9), so the files are byte-identical wherever Python's zlib is
the same deflate (the `encoders:` line says which); when the file fingerprint still differs, the
pixel-and-metadata one is the reference.

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
4. **Scale** (ART-02). Every sprite stands at the height of its **build** (`[build]` in the
   manifest: small 78, medium 94, large 128 px, provisional, D-146), or at its own `height`. The
   visible height is measured on the idle frames, from the feet to the top of the head, in a band
   of columns over the feet, so a weapon held beside or above the head does not count
   (`artpipe/scale.py` states the rule). A sprite whose idle frames are not all within 2 px of its
   target is resampled by target / measured, on a grid anchored at the feet, in integer arithmetic.
   The filter, `area`: the overlap average, with alpha kept to the source's own levels (an output
   pixel is visible when visible source pixels cover at least half of it) and, for the pack's
   units (10 to 16 colours each), every colour snapped back to the sprite's palette. Compared with
   `nearest`, which doubles rows and columns irregularly at non-integer factors (outlines of uneven
   thickness), `area` keeps outlines even and adds no colour or transparency level to the pixel
   art. The feet are registered again after scaling, so baseline and anchor follow.
5. **Packing.** Frames are trimmed and shelf-packed with a 2 px gutter. Colours are straight
   (non-premultiplied) RGBA, so pixel art stays crisp with nearest-neighbour scaling in the client.
6. **Checks** (the build fails otherwise): no pixel within the key tolerance is left in any
   output frame; every sprite's height (median of its idle frames) within 2 px of its target; no
   basic goblin (`[order] basic`) taller than the shortest profession, and `[order] tallest` taller
   than every other sprite; pages ≤ 2048; frames inside pages, none overlapping; one cell size per
   sprite; the baseline of every frame read back from the written PNG; JSON references valid; and
   no trace of the manga's name in `tools/art` or `CREDITS.md`.

The generated-sheet folder is found in code (the one subfolder of `assets/Enemy Pack` holding
`Animated/Raw`); its name is written nowhere here.

## The manifest

`manifest.toml` says which source feeds which of our names: `runt`, `slinger`, `skirmisher`,
`shaman`, `hobgoblin` (castes); `vanguard`, `warden`, `cleric` (professions, blue units), with
their build, animations, source rows or files, frame rates (12 to 15, ADR-0003) and looping. To
change a caste's height, edit one line: its build's height in `[build]`, or add `height = N` to
the sprite. Where design/10
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
