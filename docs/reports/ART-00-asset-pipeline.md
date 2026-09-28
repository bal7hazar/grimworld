# [Sonnet 5] ART-00 — Asset pipeline, outside git

## Summary
`tools/art/build.py` now turns the private art pack into the client's sprites in the git-ignored `tools/art/out/`: one atlas page (2048 × 1504) with a PixiJS 8 "hash" JSON with `animations`, an index (`sprites.json`), a report and a `preview.html`. Eight sprites (five castes, three professions) are cleaned, renamed and packed. `CREDITS.md` credits Pixel Frog. No image or derived file is committed. CI is green.

Pull request: https://github.com/bal7hazar/grimworld/pull/12 (not merged).

The model I ran as (Sonnet 5) is the one the brief names.

**AC-4 was only partly met in the first run; it is closed in "Resume 1" below.**

## Files changed
- `tools/art/build.py`: entry point; creates `.venv` and installs the pins on first run, re-executes inside it, builds, verifies, prints the report table.
- `tools/art/artpipe/clean.py`: magenta keying with fringe unmixing, silhouette cutting, feet registration, cell placement.
- `tools/art/artpipe/atlas.py`: shelf packing, PNG pages, TexturePacker hash JSON.
- `tools/art/artpipe/preview.py`: generates `preview.html`.
- `tools/art/manifest.toml`: source → our names, animations, frame rates, settings.
- `tools/art/requirements.txt`: `Pillow==12.3.0`, `numpy==2.5.3`.
- `tools/art/.gitignore`: `out/`, `.venv/`, caches.
- `tools/art/README.md`: getting the pack, running, outputs, the D-73 rule.
- `CREDITS.md`: credits *Tiny Swords* by Pixel Frog.

## Commands run
- `tools/art/build.py`, first run created the venv. Output of the last run:
```
key tolerance: 48 (max channel distance)
sprite     role       cell      frames  magenta pinkish page
runt       caste      340x166  18      0       1       atlas-0
skirmisher caste      220x159  21      0       0       atlas-0
slinger    caste      156x91   22      0       0       atlas-0
shaman     caste      468x208  18      0       12      atlas-0
hobgoblin  caste      422x246  18      0       110     atlas-0
vanguard   profession 130x113  28      0       0       atlas-0
warden     profession 106x98   18      0       0       atlas-0
cleric     profession 130x79   21      0       0       atlas-0
out/ sha256: eca5e89349fd9617c25ea26927410db8c503f3632b8387541ee03c45e8386d01
```
  About 16 s per run. The same digest came out on three runs; per-file `sha256sum tools/art/out/*` was identical on two consecutive runs (`atlas-0.png` c4e69b24…, `atlas-0.json` 1b971e0a…).
- `git status --short` before the commit: only `CREDITS.md` and `tools/` (untracked, my files); `git ls-files` lists no image.
- Grep for the forbidden name over `tools/art` (excluding `.venv`) and `CREDITS.md`: no match; the same check runs inside the build.
- `gh pr checks 12 --watch`: `tooling` pass.
- I looked at the atlas composited on grey, white and dark: no pink halo, feet aligned across frames.

## Cost
—

## Acceptance criteria
- AC-1: met. One command; run twice, digests and per-file checksums identical. Not tested: a truly clean clone. I created `.venv` and installed the pins by hand before `build.py` existed, so the bootstrap's own venv creation and `pip install -r requirements.txt` were never exercised; only its "already set up, re-exec inside the venv" path was.
- AC-2: met. Tolerance 48 (max-channel distance from the sheet's measured key: runt (250,3,250), shaman (251,3,250), hobgoblin (249,3,249)). Magenta pixels left is 0 for every sprite; the build fails otherwise. A wider "pinkish" count (R, B > 160, G < 110) is also printed: 110 in the hobgoblin (its pink nipples, real art), 12 in the shaman (magic sparks), 1 in the runt; none is a halo (checked by eye on white and dark backgrounds).
- AC-3: met. Each sprite has one cell size (table below). Baseline of every frame is re-read from the written PNG and compared with the sprite's baseline by the build. `preview.html` plays every animation, with cell, baseline and anchor guides (written, not opened in a browser by me: this environment has none).
- AC-4: **not fully met**. The build checks the JSON against what `Spritesheet.parse` reads (frames, animations, `meta.image`/`size`/`scale`, frame rects inside the image, no overlaps, references valid), but `Assets.load` + `Spritesheet.parse` were not executed. README gives the loading snippet.
- AC-5: met. `git ls-files` has no image, nothing from `assets/`; grep prints nothing.
- AC-6: met. `CREDITS.md` credits Pixel Frog with the itch.io link.

### Per sprite
| Our name | Source (described) | Animations (frames) | Cell | Frames | Magenta left | Atlas page |
|---|---|---|---|---|---|---|
| runt | generated common goblin sheet | idle 6, move 6, attack 6 | 340 × 166 | 18 | 0 | atlas-0 |
| skirmisher | original Spear Goblin strips | idle 8, move 6, attack 7 | 220 × 159 | 21 | 0 (source already transparent) | atlas-0 |
| slinger (placeholder) | original Torch Goblin strips | idle 8, move 6, attack 8 | 156 × 91 | 22 | 0 (source already transparent) | atlas-0 |
| shaman | generated shaman sheet | idle 6, move 6, attack 6 | 468 × 208 | 18 | 0 | atlas-0 |
| hobgoblin | generated hobgoblin sheet | idle 6, move 6, attack 6 | 422 × 246 | 18 | 0 | atlas-0 |
| vanguard | original Warrior strips, blue | idle 8, move 6, attack 4, attack2 4, guard 6 | 130 × 113 | 28 | 0 (source already transparent) | atlas-0 |
| warden | original Archer strips, blue | idle 6, move 4, attack 8 | 106 × 98 | 18 | 0 (source already transparent) | atlas-0 |
| cleric | original Monk strips, blue | idle 6, move 4, heal 11 | 130 × 79 | 21 | 0 (source already transparent) | atlas-0 |

Frame rates: 12 for idle, move and guard; 15 for attacks; 12 for heal.

## Deviations from the brief
- No Node check of PixiJS (see Escalations); the check is structural, inside the build.
- The generated sheets' Jump row is not used (not asked for). Frames from those sheets use rows Idle, Walk (named `move`) and Attack.
- The brief said the Runt could be Torch Goblin or generated common: generated common taken, as instructed. The slinger placeholder is the Torch Goblin.
- Cell widths of the generated sprites are large (up to 468 px) because the anchor is centred and a right-facing attack reaches far to one side; atlas frames are trimmed, so no atlas space is lost.

## Escalations
- **AC-4 needs a PixiJS run.** `npm` is refused by this session's profile, and `pnpm` has no version set in the worktree (`No version is set for command pnpm`); setting one, or an env override, was also refused. I did not work around either. Someone with `pixi.js` installed should run `Assets.load('atlas-0.json')` and check `sheet.animations['hobgoblin/move']`. If the orchestrator wants the check kept in the repository, it needs a `tools/art/check/` with a `package.json` and a lockfile, which I could not produce (no version of `pixi.js` was verifiable).
- The bootstrap's venv creation and pip install were not exercised by `build.py` itself (see AC-1).

## Open questions
- **Slinger**: which goblin sprite stands in? I used the Torch Goblin (small, distinct from the runt and the skirmisher). A commissioned slinger, or the pack's Slingshot Gnome, would replace it.
- **Arcanist**: no sprite in the pack (Q-12); left out.
- **Scale**: the generated goblins are drawn about twice as large as the original units (hobgoblin frames ~200 px tall, runt ~150, warrior ~90, torch goblin ~70). Nothing is resampled, so the client must scale them (or the owner accepts the difference). Which display size should each caste have?
- **Hurt and Death** are missing for every sprite (design/10); not produced.
- **Attack timing**: the generated attack rows end on an idle-like pose; whether the client plays them at 15 fps once or stretches them is CLI-03's call.

## Resume 1

Two open points of the first run (AC-4 and the untested bootstrap) are closed. Pull request #12, new head `2a2d457`, CI `tooling` green (the only check the pull request reports).

### What changed
- Merged `origin/main` into the branch (`git merge`, no rebase): clean, no conflict, nothing resolved by hand, no root file edited by me.
- **AC-4, now met.** `tools/art/check/` is a Node package of its own: `package.json` (`pixi.js` `8.21.0`, the version of `client/app/package.json` on origin/main; `pnpm@12.5.1`), `pnpm-lock.yaml`, `check.mjs`. It parses every atlas with PixiJS 8's `Spritesheet` (a `Texture` on a `TextureSource` of the PNG's real size stands in for the image) and checks: each frame's texture rect, `orig` size (= the sprite's cell) and anchor match the JSON; PNG size = `meta.size`; every animation of every sprite in `out/sprites.json` resolves to the declared number of frames, all of the cell size; PixiJS resolved as many animations as the JSON holds.
- The package stays out of the root workspace: `pnpm --dir tools/art/check --ignore-workspace …`. `git status` shows only `tools/art/**` changes; the root `package.json`, `pnpm-workspace.yaml` and `pnpm-lock.yaml` are untouched.
- `tools/art/build.py --check` runs the check after the build (frozen-lockfile install, then the check). `tools/art/README.md` documents both commands and the `--ignore-workspace` rule.

### Commands run
- `pnpm --dir tools/art/check install --ignore-workspace` → `+ pixi.js 8.21.0`, `Packages: +12`, lockfile written in `tools/art/check/`.
- **A mistake of mine, undone.** I first ran `pnpm --dir tools/art/check check` *without* `--ignore-workspace`: pnpm found the root workspace (`Scope: all 3 workspace projects`) and installed the root and `client/*` dependencies into this worktree (311 packages). No tracked file changed (`git status`, `git diff --stat` empty apart from my folder); I deleted the three `node_modules` folders it created (`node_modules`, `client/app/node_modules`, `client/sim/node_modules`, all ignored, all created by that command) and ran everything after with `--ignore-workspace`. Anyone running the check by hand must pass it (the README says so).
- `pnpm --dir tools/art/check --ignore-workspace run check` →
```
$ node check.mjs
PixiJS 8: 1 page(s), 164 frames, 26 animations parsed; every animation resolves to frames
```
- Negative test (the check can fail): I edited the ignored `out/sprites.json` to say `runt/idle` has 7 frames and to add a `runt/jump` animation; the check exited 1 with
```
runt/idle: 6 frames, expected 7
runt/jump: no frames
```
  then I rebuilt `out/`.
- **Bootstrap from a clean state.** `rm -r tools/art/.venv`, then one run of `tools/art/build.py --check`: it recreated the venv, ran `pip install -r requirements.txt`, re-executed inside the venv, built, and exited 0. The first build lines and the check are the same as above (`out/ sha256: eca5e89349fd9617c25ea26927410db8c503f3632b8387541ee03c45e8386d01`, identical to every earlier run, then `PixiJS 8: 1 page(s), 164 frames, 26 animations parsed…`). The pip step is silent (`--quiet`); its result: `pip freeze` in the new venv prints `numpy==2.5.3` and `pillow==12.3.0`, and `site-packages` holds `pip-24.0` plus those two. The pip download may have come from the machine's pip cache rather than the network; I did not check which.
- `git status --short` before the commit: only `tools/art/README.md`, `tools/art/build.py`, `tools/art/check/` (no image); `grep -ri` for the forbidden name over `tools/art` (without `.venv` and `node_modules`): no match.
- `gh pr checks 12 --watch`: `tooling` pass.

### Still open
- The `preview.html` has not been opened in a browser by me (none here); unchanged from the first run.
- The check uses a texture stand-in, so it proves parsing and frame resolution, not GPU upload or rendering.
