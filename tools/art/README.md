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

One command. It needs **Python 3.12 or 3.13**, exactly: the versions whose wheels
`requirements.txt` pins by hash (`PYTHONS` in `build.py`, the one place that says so), and a
network the first time. A newer Python (3.14) is refused, naming them. Started by an older Python
(`python3` is 3.11 on some Macs), it re-executes itself once under the `python3.12` on `PATH`,
after asking that interpreter its version; it refuses, naming 3.12 and 3.13, when there is none,
when it reports another version, or when it was already re-executed once, before it creates or
uses anything. On first run it creates `tools/art/.venv` and installs the pinned
`requirements.txt` (Pillow, NumPy) with `pip --require-hashes`, then hands off to the venv's
interpreter, once. An existing `.venv` is asked directly (its interpreter, not only `pyvenv.cfg`):
it is rebuilt when its Python is not 3.12 or 3.13, when `pyvenv.cfg` is missing, unreadable or names
another version, or when a pinned distribution is missing or at another version; a 3.13 venv under
a 3.12 start is kept. Started directly by `tools/art/.venv/bin/python`, the build checks the
running venv the same way and refuses when it is wrong (run `python3 tools/art/build.py` to
rebuild it). If the venv's interpreter does not run inside the venv after the handoff, the build
refuses instead of looping. It reads `assets/` and `manifest.toml`, rewrites `out/`, prints two
tables and the fingerprints, and exits 0. It fails if a check fails (see below).

`requirements.txt` pins each distribution with the SHA-256 of its wheels from PyPI (CPython 3.12
and 3.13, macOS arm64 and manylinux x86_64); no sdist, so a machine without such a wheel is
refused rather than compiling NumPy.

Every mode (any other argument is refused):

    tools/art/build.py                       # build out/
    tools/art/build.py --check               # build, then the PixiJS 8 check (below)
    tools/art/build.py --resample=FILTER     # area (default), area-blend or nearest (a sprite with a height in px)
    tools/art/build.py --fingerprint         # the fingerprints of the existing out/, no build
    tools/art/build.py --pack-heights        # the visible height of every unit of the pack
    tools/art/.venv/bin/python -m unittest discover -s tools/art/tests    # the tests

Nothing the build prints carries the manga's name: its output goes through a filter that replaces
it.

## Same output on every machine

The build prints two fingerprints of what it writes to `out/` (dotfiles and other files ignored):

    out/ sha256: …                      every file's bytes
    out/ pixels+metadata sha256: …      every PNG decoded to RGBA, every JSON canonicalised
    encoders: zlib (python) …, zlib (Pillow) …, Pillow …, NumPy …

Two runs on one machine give the same two lines. At `4c2b25c` the build was measured on two
machines, two clean runs each, with the same pack (the `assets` gitlink of that commit):

| | macOS arm64 | Linux x86_64 |
|---|---|---|
| OS / CPU | Darwin 25.6.0, Apple M2 Max | Linux 6.8.0-139, AMD EPYC 9354P |
| Python | 3.12.0 | 3.12.3 |
| `zlib (python)` | 1.2.12 | 1.3 |
| `zlib (Pillow)` | 1.3.1.zlib-ng | 1.3 |

Both machines, both runs, printed the same two fingerprints, and every file of `out/` (five files)
has the same bytes and the same sha256 on both:

    out/ sha256: f6c2caa7b1b477c144bfb948eedc6cfa070b35a2b550506a6dd5cdd9a2cd8602
    out/ pixels+metadata sha256: 2b98b8857637072c50c4803dad7cdd1e42eb434d9d388a5e55f0f95f04fea5f5

(Pillow 12.3.0 and NumPy 2.5.3 on both; only the `encoders:` line differs, as the table shows.)
The files are identical although Python's zlib (1.2.12 vs 1.3) and Pillow's (zlib-ng vs zlib)
differ. If another machine's `out/ sha256` differs, compare the second line: it holds what the
client loads (pixels and data), whatever compressed it.

These are the fingerprints of `4c2b25c`'s manifest; a later manifest has others (CLI-03e's added
the hubs' art and recorded none).

**Why the files differed between macOS arm64 and Linux x86_64 (ART-00), and why they no longer do.**
Measured on the Mac: Pillow 12's wheels compress PNGs with zlib-ng (`zlib (Pillow) 1.3.1.zlib-ng`); the same array written by Pillow and by `artpipe/png.py` gives
files of different sizes and hashes and identical decoded pixels. zlib-ng's output can depend on its
build and on the CPU's code paths, which explains different files with equal pixels. So the pipeline:
- writes PNGs itself (`artpipe/png.py`: Paeth filter in NumPy, Python's own `zlib` at level 9),
  so the files can be byte-identical wherever Python's zlib is the same deflate (the `encoders:`
  line says which);
- computes every pixel in integers: the registration on the feet, resampling by integer overlap
  weights (int64 sums are exact in any order), thresholds as integer fractions. The float values
  left are Python scalars (the anchor written to the JSON), which are IEEE double operations, the
  same on every machine.

The measure above bears this out: with the pipeline's own PNG writer the files are byte-identical
on both machines. When the file fingerprint still differs elsewhere, the pixel-and-metadata one is
the reference.

## What it produces (`out/`)

| File | Content |
|---|---|
| `atlas-N.png`, `atlas-N.json` | Atlas pages, at most 2048 × 2048. The JSON is TexturePacker "hash" format with `animations`, ready for PixiJS 8. A sprite never straddles two pages |
| `sprites.json` | Index: for each sprite its page, cell size, baseline, animations (frames, fps, loop) |
| `report.json` | Per sprite: source, cell, frames, height (source, target, result), page |
| `preview.html` | Every animation playing, with cell / baseline / anchor guides, zoom, mirror, background. Open it in a browser |

Names: frames are `<sprite>/<animation>/<nn>` (`runt/attack/03`), animations `<sprite>/<animation>`
(`hobgoblin/move`). Every frame carries `sourceSize` = the sprite's cell (one size per sprite),
`spriteSourceSize` (the trim offset in the cell) and `anchor` = (0.5, baseline / cell height), so
placing the sprite at its tile position puts the feet on it. A tile (role `tile`) is the exception:
untrimmed, `anchor` = (0, 0), its top-left corner (see *Buildings, props and tiles*). Frame rates and looping are in
`meta.animationRates` and in `sprites.json`. Sprites face right; left is a mirror (`scale.x = -1`).

## What it does

1. **Cutting.** Every sprite is made of the pack's own horizontal strips (`file`, in the sprite's
   `root` folder of the pack): transparent already, square cells (cell = strip height), each cell
   one pose. A building is a still, one image, one pose (below).
2. **Registration.** The feet of each pose (the lowest row that is not a thin tip) are put on one
   baseline and one horizontal anchor; every frame of a sprite gets the same cell size.
3. **Scale** (ART-02; D-146 as corrected by the owner; ART-03). Every sprite is at the pack's own
   size: `[height]` in the manifest gives each sprite `"native"`, never resampled, pixels untouched.
   A number stays possible: the sprite is then resampled to that visible height. The visible height
   is measured on the idle frames, from the feet to the top of the head, in a band of columns over
   the feet, so a weapon held beside or above the head does not count (`artpipe/scale.py` states the
   rule). A sprite with a number is resampled by target / measured, on a grid anchored at the feet,
   in integer arithmetic. The filter, `area`: the overlap average, with alpha kept to the source's
   own levels (an output pixel is visible when visible source pixels cover at least half of it) and,
   when the source has at most `palette_max` colours, every colour snapped back to its palette.
   `nearest` doubles rows and columns irregularly at non-integer factors. The feet are registered
   again after scaling, so baseline and anchor follow. An idle whose frames span more than 6 px gets
   a warning (the height is their median).
4. **Packing.** Frames are trimmed and shelf-packed with a 2 px gutter. Colours are straight
   (non-premultiplied) RGBA, so pixel art stays crisp with nearest-neighbour scaling in the client.
5. **Checks** (the build fails otherwise): every resampled sprite's height (median of its idle
   frames) within 2 px of its target; the order rule: no basic goblin (`[order] basic`) taller than
   the shortest profession, `[order] tallest` taller than every other sprite. Between native
   drawings the rule is only a **warning** the build prints (the pack keeps its own proportions and
   the owner scales the sprites by eye in the sandbox); a failure that involves a resampled sprite
   is an error. On the native heights below, the shortest profession is the cleric (67): the runt
   (73) and the skirmisher (70) are taller than it, so the build prints two warnings; the slinger
   (67) is not; the hobgoblin (209) is taller than every other sprite, so the boss rule holds. `[order]` and `[height]` name only sprites of the manifest, with at least one
   profession; pages ≤ 2048; frames inside pages, none overlapping; one cell size per sprite; the
   baseline of every frame read back from the written PNG; JSON references valid; and no trace of
   the manga's name in `tools/art` or `CREDITS.md`.

## Native heights (a record)

Measured on 2026-09-29 by `tools/art/build.py` (the `scale:` table it prints: visible height of the
idle frames, feet to top of head, median with the range of the frames; rule in `artpipe/scale.py`).
`tools/art/build.py --pack-heights` prints the same measure for every unit of the pack. Every sprite
is native, so these are the pack's own drawings; they change only if the pack or a manifest line does.

| Sprite | Source unit | Height (px) | Idle frames |
|---|---|---|---|
| runt | Thief | 73 | 72-76 |
| skirmisher | Spear Goblin | 70 | 68-74 |
| slinger | Torch Goblin | 67 | 66-68 |
| shaman | Hex Shaman | 70 | 69-73 |
| hobgoblin | Troll | 209 | 206-211 |
| vanguard | Warrior, blue | 87 | 85-89 |
| warden | Archer, blue | 88 | 86-89 |
| cleric | Monk, blue | 67 | 66-68 |

## The manifest

`manifest.toml` says which source feeds which of our names: `runt` (the Thief), `skirmisher` (the
Spear Goblin), `slinger` (the Torch Goblin), `shaman` (the Hex Shaman), `hobgoblin` (the Troll)
(castes); `vanguard`, `warden`, `cleric` (professions, blue units), with animations, source files,
frame rates (12 to 15, ADR-0003) and looping. To change a sprite's height, edit its one line in
`[height]`: a number resamples it, `"native"` keeps the pack's drawing. The `slinger` is a
placeholder (no goblin slinger exists); the Arcanist has no sprite (Q-12) and is left out.

## Buildings, props and tiles: still sprites (CLI-03c, CLI-03e, CLI-03g2)

The pack's buildings are **single images**, not strips. A `[[still]]` entry of `manifest.toml` names
one (`name`, `role = "building"`, `file`: its path in the pack, `origin`). The build makes it one
frame at **native size**, never resampled. It is anchored at its **base**: the line under its lowest
solid row wide enough, the feet rule of the strips, so a thin pole is not the ground. Horizontally
it is anchored at its centre (`artpipe/clean.py`, `still`). It is packed like any sprite, with
one animation, `still`, of one frame (rate 1, no loop), named `<building>/still/00`. Its
`sprites.json` entry has `role: "building"`. It gets the same checks, the baseline read back from
the PNG included, and the client draws it once.

The manifest lists the eight Blue buildings (`castle`, `barracks`, `archery`, `monastery`, `tower`,
`house1`, `house2`, `house3`), one colour set until the owner chooses, and the single buildings of
`Buildings/Others/` the hubs use (`fortress`, `forge`, `cloister`, `market_hall`, `grain_silo`,
`barn`, `watchtower`, `windmill`, `inn`, `tavern`, `stable`, `hut`, `straw_hut`, `cottage`,
`small_house`, `rural_house`). To add one, add a `[[still]]` with its file and run the build.

**Props** (CLI-03e): a `[[still]]` with `role = "prop"`: trees, bushes, rocks, stumps, a sheep.
`sprites.json` tells them from buildings by the role. An animated strip is drawn at **one frame**
(no idle animation in a hub): `frame` is the cell's index from the left, `cell = [width, height]`
its size, which may be non-square (the trees' cells are 192 × 256); `cell` defaults to the strip's
height, square. Without `frame` and `cell` the whole image is the still. The cell is then trimmed
and anchored at its base like any still. The zone's wall hexes draw the same props as their
obstacle objects (CLI-03h): `rock1`–`rock4`, `bush1`–`bush4`, `stump1`–`stump4`, `tree1`–`tree4`,
one per hex chosen by a hash of its coordinates (`client/app/src/render/obstacles.ts`,
`OBSTACLES`); without them the zone draws its shaped rocks.

**Tiles** (CLI-03e): a `[[tileset]]` entry (`name`, `role = "tile"`, `file`, `origin`, and
`cells = { <cell> = [column, row] }`) cuts named **64 × 64** cells of a sheet of
`Terrain/Tileset/`, or square cells of another side given by the entry's optional `cell` (in px;
CLI-03g2), the column and row then counted in cells of that side. Each cell becomes the sprite `<name>_<cell>` (`grass_c`, `grass_nw`, …) with one
animation `still` of one frame. A tile is packed **untrimmed**, at native size (an edge cell keeps
its transparent part, so cells laid side by side meet exactly), anchored at its **top-left corner**
(`anchor` = (0, 0)), and its edge pixels are **extruded** into the gutter around it (half the atlas
padding), so a scaled scene that samples just outside a cell finds the cell's own edge: no seam.
The build checks every tile's frame is exactly its entry's cell (64 × 64 by default), untrimmed,
at offset (0, 0). The manifest cuts the 3 × 3 flat-ground autotile of `Tilemap_color1.png`
(`grass_nw` … `grass_se`, the centre `grass_c`; the first colour variant, proposed for the owner's
eye), the flat water (`water_c`), and the first still of the foam's strip `Water Foam.png`, one
192 × 192 cell (`foam_c`, `cell = 192`). The zone's renderer reads `grass_c`, `water_c` and
`foam_c` (`client/app/src/render/renderer.ts`, `GROUND_TILES`): the grass and the water fill the
hexes of their ground, and the foam is centred under every land hex that touches water, its part
over the water drawn (CLI-03g). The other eight `grass_*` cells stay for a square coast.

Stills, props and tiles are packed after the strips: the strips' frames are the same with and
without them (`tests/test_build.py`, `StillsBesideStrips`). A sprite never straddles two pages; the
tiles may land on another page than the buildings, and the client loads every page. The tests make
their buildings, props and tiles from synthetic images (`Stills`, `Tiles`).

**The hubs' places** (CLI-03e, `client/app/src/sandbox/fixtures/hubs.ts`, proposed for the owner's
eye; the fixtures are the source, this table mirrors them):

| Place | Town | Outpost |
|---|---|---|
| Guild | `castle` (Blue castle) | `fortress` (`Others/Fortress`) |
| Trainer | `barracks` (Blue barracks) | `barracks` (Blue barracks) |
| Enchanter | `tower` (Blue tower) | — |
| Smith | `forge` (`Others/Forge`) | — |
| Armorer | `archery` (Blue archery) | — |
| Alchemist | `cloister` (`Others/Cloister`) | — |
| Market | `market_hall` (`Others/Market_Hall`) | — |
| Vault | `grain_silo` (`Others/Grain_Silo`) | `barn` (`Others/Barn`) |
| Gate | `watchtower` (`Others/Watchtower`) | `watchtower` (`Others/Watchtower`) |

Around them, without a tap target: in the town a `windmill`, a `small_house` and a `cottage`; in
the outpost a `hut` and a `straw_hut`; props `tree1`–`tree4`, `bush1`–`bush3`, `rock1`–`rock4`,
`stump1`, `stump2`, `sheep` (`bush4`, `stump3` and `stump4` serve the zone only). The ground is `grass_*`, the water around it `water_c`.

To see the buildings in the hubs of the sandbox, on the Mac, with the pack:

    git submodule update --init assets         # the private pack, once
    tools/art/build.py                         # writes tools/art/out/, the hubs' art included
    pnpm --filter @grimworld/app dev           # serves tools/art/out/ at /art/
    # open http://localhost:5173/?hub=town and http://localhost:5173/?hub=outpost

From a worktree without the pack, point the dev server at a checkout that built it:
`GRIMWORLD_ART_OUT=<that checkout>/tools/art/out pnpm --filter @grimworld/app dev`.

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
