# [Opus 5.5] ART-02 — atlas scale

> **Read "Resume 1", "Resume 2" and "Resume 3" at the end first. Resume 3 holds the "PR body" text for #134.** It follows the owner's correction of D-146: the pack's units are no longer resampled, and only the generated sheets are reduced (67 / 87 / 119). It also closes the two audits' findings. Where the first run's sections below differ, Resume 1 holds.

## Summary
`tools/art/build.py` now resamples every sprite to the height of its **build**. `manifest.toml` holds a `[build]` table (small 78, medium 94, large 128, D-146's provisional numbers). Each sprite has one `build = …` line, and an optional `height = N` overrides it. The build fails unless each sprite's measured height is within ±2 px of its target, no basic goblin is taller than the shortest profession, and the hobgoblin is the tallest sprite.

- **Python.** Started by Python < 3.12, the build re-executes under `python3.12`, or refuses naming 3.12 before creating or using a venv. A venv made with another Python is rebuilt.
- **Cross-machine difference.** Traced to Pillow's zlib-ng PNG encoder. PNGs are now written with Python's own zlib, and the build prints a fingerprint of the decoded pixels and canonical JSON next to the file fingerprint. `--fingerprint` prints both for an existing `out/`, which is the orchestrator's Linux check.

Pull request: https://github.com/bal7hazar/grimworld/pull/134 (CI all green, not merged).
The model I ran as (Opus 5.5) is the one the brief names.

## Files changed
- `tools/art/build.py`: Python selection (`select_python`, `venv_version`, `bootstrap`), `scale_sprite`, `check_scale` (AC-1, AC-2), the scale table, and the modes `--fingerprint`, `--pack-heights` and `--resample=`.
- `tools/art/artpipe/scale.py` (new): the visible-height rule, the integer resampler (`area`, `nearest`), alpha levels, the palette snap, `target_height`, `check_order`.
- `tools/art/artpipe/png.py` (new): PNG writer (NumPy Paeth filter plus stdlib `zlib` level 9).
- `tools/art/artpipe/fingerprint.py` (new): the file fingerprint, the pixels-and-metadata fingerprint, and the encoder versions.
- `tools/art/artpipe/atlas.py`: pages written by `png.write` instead of Pillow.
- `tools/art/manifest.toml`: `resample`, `palette_max`, `[build]`, `[order]`, one `build` line per sprite.
- `tools/art/tests/test_build.py` (new): 12 unittest tests (Python selection, weights, anchor, weapon exclusion, alpha levels and palette, order check positive and negative, target override, PNG read-back).
- `tools/art/README.md`: Python 3.12, the modes, the scale step and filter choice, the fingerprints and the cause, the one-line height change.

## Commands run
- `python3 tools/art/build.py`, first run (Python 3.11.6, no venv): re-executed under 3.12, created the venv, built. Fingerprint `f4c768bf…` (before any scaling change), which is the orchestrator's Mac figure for ART-00.
- `tools/art/build.py --pack-heights` (the rule applied to the pack's own idle strips, median and range):
```
Units/Blue Units/Warrior   87 (85-89)     Enemy Pack/Spear Goblin   70 (68-74)
Units/Blue Units/Archer    88 (86-89)     Enemy Pack/Torch Goblin   67 (66-68)
Units/Blue Units/Monk      67 (66-68)     Enemy Pack/Hex Shaman     70 (69-73)
Units/Blue Units/Pawn      72 (71-74)     Enemy Pack/Minotaur      119 (118-121)
Units/Blue Units/Lancer    75 (74-75)     Enemy Pack/Troll         209 (206-211)
Enemy Pack/Spider 79, Giant Bat 80, Panda 92, Bear 91, Pig Rider 96, Lizard 123
```
- `tools/art/build.py --check`, final state:
```
sprite     build   target  source        factor          result        cell
runt       small   78      147 (144-147) 78/147=0.531    78 (76-78)    184x92
skirmisher small   78      70 (68-74)    78/70=1.114     78 (76-80)    244x177
slinger    small   78      67 (66-68)    78/67=1.164     78 (77-79)    180x105
shaman     medium  94      153 (150-166) 94/153=0.614    94 (92-101)   290x131
hobgoblin  large   128     177 (176-178) 128/177=0.723   128 (128-128) 308x180
vanguard   medium  94      87 (85-89)    94/87=1.080     94 (92-96)    140x121
warden     medium  94      88 (86-89)    94/88=1.068     94 (92-95)    112x104
cleric     medium  94      67 (66-68)    94/67=1.403     94 (93-95)    180x108
out/ sha256: 0eaf99b0f0203e0ee3e892dffb36532a0650883ce54fa64fa8725daf012b6a63
out/ pixels+metadata sha256: 5af16e6dd2921bf45b6a1c66d1791b317007e4670ac79ec837293b6e46050f4f
encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3
...
PixiJS 8: 1 page(s), 164 frames, 26 animations parsed; every animation resolves to frames
```
  Magenta left is 0 for every sprite; the pinkish count is 58 on the hobgoblin (its art, as in ART-00). The same two fingerprints came out on four runs: `--check`, the run after the venv was removed, the run after the 3.11 venv was rebuilt, and `--fingerprint`.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests -v`: `Ran 12 tests … OK`. `python3 -m unittest discover -s tools/art/tests` (3.11): `Ran 12 tests … OK`.
- AC-3 run: `large = 128` changed to `large = 140` (one line), then a build. Only the hobgoblin changed: `hobgoblin large 140 177 (176-178) 140/177=0.791 140 (140-141) 336x196`; every other row was identical to the table above. Then reverted (`git status` clean).
- AC-2 negative run: `small = 100` makes the build exit non-zero with the message below; then reverted.
```
scale check failed:
  runt (100 px) is taller than the shortest profession, cleric (94 px)
  skirmisher (100 px) is taller than the shortest profession, cleric (94 px)
  slinger (100 px) is taller than the shortest profession, cleric (94 px)
```
- AC-5 runs:
  - `rm -r tools/art/.venv; python3 tools/art/build.py` printed `Python 3.11: re-executing under /opt/homebrew/bin/python3.12`, built the venv (`version = 3.12.0`) and ran the build.
  - `python3 -m venv tools/art/.venv` (a 3.11 venv), then `python3 tools/art/build.py` printed `tools/art/.venv was made with Python (3, 11), not 3.12: rebuilding it`. The venv came back as `version = 3.12.0`, and the build ran.
- Encoder evidence, a scratch script on ART-00's atlas (the same pixels encoded three ways):
```
atlas-0.png (ART-00, Pillow)  2333376 B  sha 2bfefdc57a727cc3  pixels 8a5a59f6bd335767
re-saved by Pillow            2333376 B  sha 2bfefdc57a727cc3  pixels 8a5a59f6bd335767
written by artpipe/png.py     2441050 B  sha 50fc04cea744b3c8  pixels 8a5a59f6bd335767
```
  Pixels-and-metadata fingerprint of ART-00's `out/` on this Mac: `883be85841e5533740ffadbaad6dee9f6a342b7fc187d1a518bcadace4bd075d`.
- `git ls-files '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.aseprite' '*out/*'` printed nothing. `git diff --name-only origin/main...HEAD` lists only `tools/art/**`. The forbidden-name check runs inside every build and passed.
- `gh pr checks 134 --watch`: every check passed (tooling, client, cairo ×9, discover).
- Not run: `shasum -a 256 tools/art/out/*`, which the profile refused. The build's file fingerprint hashes the same bytes.

## Cost
—

## Acceptance criteria
- **AC-1: met, with a stated reading (see Deviations).**
  - Every sprite's height, the median of its idle frames, equals its target (78/94/128) exactly, within the ±2 the check enforces.
  - The table is printed by the build and is above.
  - The height rule: from the line under the feet up to the highest pixel with alpha ≥ 64, inside a band of columns centred on the feet, of half-width max(4, 10% of the pose width). This excludes the hobgoblin's club, the shaman's staff, the skirmisher's spear and the slinger's torch; headwear counts.
- **AC-2: met.** `check_scale` and `scale.check_order` fail the build. The unit test `test_order_check_passes_and_fails` and the `small = 100` run are the negative tests.
- **AC-3: met.** One line (`large`) changed the hobgoblin alone (run above).
- **AC-4: met.** `--check` is green: the ART-00 checks (key, baseline read back from the PNG, one cell per sprite, pages, JSON), AC-1/AC-2, and PixiJS (164 frames, 26 animations, cell sizes, anchors).
- **AC-5: met.**
  - Re-execution from 3.11 and bootstrap from a removed venv: shown by the runs above.
  - Refusal with no `python3.12`: shown by the tests `test_refuses_naming_3_12_when_none_reachable` and `test_refusal_comes_before_any_venv` (the latter asserts no venv is created).
  - A wrong-Python venv is rebuilt (run above).
- **AC-6: met on the Mac; Linux still to run.**
  - Same file fingerprint and pixel fingerprint on four runs.
  - Cause stated with evidence (Cross-machine section).
  - Linux command below.
- **AC-7: met.** No image, atlas, `out/` or `assets/` file is tracked. The forbidden-name check passes. The pull request body holds only numbers.

## The filter comparison
Measured on the atlas, over all frames of each sprite, with `tools/art/build.py --resample=nearest`, `--resample=area-blend` and `--resample=area` (the default):

| sprite (original strip) | nearest: colours / rows equal to the row above | area-blend | area (snap) |
|---|---|---|---|
| vanguard | 12 / 212 | 4496 / 8 | 17 / 11 |
| warden | 12 / 116 | 2800 / 3 | 13 / 10 |
| cleric | 11 / 570 | 2510 / 8 | 13 / 20 |
| skirmisher | 10 / 378 | 3357 / 67 | 10 / 90 |
| slinger | 16 / 268 | 4316 / 19 | 19 / 11 |

"Colours" counts distinct RGBA values, so a palette RGB at a second alpha level counts twice. No new RGB colour appears after the snap.

- **nearest.** It keeps the palette but duplicates rows and columns irregularly at non-integer factors; on a 4× crop, outlines have uneven thickness.
- **area-blend** (overlap average; alpha kept to the source's levels 0, ~80 and 255). It has even outlines but thousands of blended colours, which soften the hard pixel-art outlines.
- **area** (the choice). It is area-blend, then each colour is snapped to the sprite's own palette (at most `palette_max = 64` colours; the units have 10–16). Outlines stay even and no new colour or transparency level appears. The generated goblin sheets (40k–100k colours, not clean pixel art) keep the averaged colours.
- **The alpha clean-up.** A first version made alpha binary. It deleted the units' translucent (alpha ≈ 80) parts at the feet and shifted the measured heights. The kept rule: a pixel is visible when visible source pixels cover at least half of it, and its alpha is snapped to the source's levels.

**What the orchestrator should look at in `preview.html`:**
- Outline thickness on the vanguard's helmet cross and shield edge, and on the cleric (×1.40, the largest upscale).
- The runt and the shaman at ×0.53 and ×0.61: fine details such as the shaman's necklace and the runt's face.
- The feet on the red baseline in every animation, especially the skirmisher and slinger runs.
- The hobgoblin's club, whose top is outside the measured height.

## The cross-machine cause and the Linux command
**Cause.**
- Pillow 12.3.0's wheels compress PNGs with zlib-ng (`PIL.features.version("zlib")` → `1.3.1.zlib-ng`). zlib-ng picks CPU-specific code paths, so its deflate bytes can differ between arm64 and x86_64.
- Evidence on the Mac: the same pixels, encoded by Pillow and by stdlib zlib, give different bytes and identical decoded pixels.
- I could not run Linux, so "the pixels were already equal on both machines" is unverified. It can be checked (step 1 below).

**Change.**
- PNGs are now written by `artpipe/png.py`, with Python's stdlib zlib (1.2.12 on this Mac): classic zlib has no CPU-specific deflate code.
- Resampling is integer-only, so it is identical everywhere by construction.
- The pixels-and-metadata fingerprint is printed in any case.

**On the VPS**, from the worktree of this branch (or `main` after merge), with the pack present:
1. **Before rebuilding**, if the VPS still has ART-00's `tools/art/out/`: `tools/art/build.py --fingerprint`. If the `pixels+metadata` line is `883be85841e5533740ffadbaad6dee9f6a342b7fc187d1a518bcadace4bd075d` (this Mac, ART-00), the old difference was the encoder alone.
2. `tools/art/build.py --check`, then compare with this Mac:
   - `out/ pixels+metadata sha256: 5af16e6dd2921bf45b6a1c66d1791b317007e4670ac79ec837293b6e46050f4f` must match.
   - `out/ sha256: 0eaf99b0f0203e0ee3e892dffb36532a0650883ce54fa64fa8725daf012b6a63` matches too if the VPS Python's zlib deflates like 1.2.12. The `encoders:` line shows its version.

## Deviations from the brief
- **AC-1 is checked on the sprite's height (the median of its idle frames), not on every frame.** Some idle animations move by more than 4 px in the pack itself: the shaman goes 150–166 (one frame raises the staff hand into the band), the skirmisher 68–74 and the vanguard 85–89. No single scale factor fits every frame into ±2. The per-frame range is printed in the table (result column).
- **The heroes are resampled.** D-146's heights are not the pack units' heights by any rule I found (next section), so the three original hero strips are resampled too: ×1.08, ×1.07 and ×1.40. None of them already stood at its build's height.
- Beyond the brief's list: three helper modes (`--pack-heights`, `--resample=`, `--fingerprint`) and a `tests/` folder, all inside `tools/art/**`.

## Escalations
- **78 / 94 / 128 are not the heights of the pack's units.** By the stated rule, and also by the plain bounding box (earlier scratch survey), no unit stands at them:
  - Warrior 87, Archer 88, Monk 67, Pawn 72, Lancer 75.
  - Spear Goblin 70, Torch Goblin 67, Hex Shaman 70.
  - Minotaur 119, Lizard 123, Troll 209.
  - Nearest: 78 ≈ Spider 79 / Giant Bat 80; 94 ≈ Panda 92 / Pig Rider 96; 128 ≈ Lizard 123.

  I kept D-146's numbers, as the decision names them and the owner sets the final sizes by eye. If "the height the pack gives a unit of its build" means the pack's own proportions, the builds would be roughly 67–72 (goblins, Monk, Pawn), 87–88 (Warrior, Archer) and 119–209 (Minotaur, Troll). The Monk (67) is then shorter than the basic goblins (67–70), so AC-2 would force resampling anyway. The project manager should say which reading D-146 meant.
- No shared file needed a change.

## Open questions (sizes the owner should look at first)
1. **The cleric** is scaled ×1.40 to 94, because every profession is `medium`; it looks the bulkiest hero. The alternative is `height = 78` on it (one line). The basic goblins would then equal it, still allowed by AC-2's "no taller".
2. **The shaman** is `medium` (94), as tall as the heroes. It could be `small` or its own height.
3. **The skirmisher's spear** reaches well above 78; its cell is 244×177. Check whether it reads as the same size as the runt.
4. **The runt** is scaled ×0.53, the largest downscale. Check the face details at 78 px.
5. **The hobgoblin** at 128 is 1.36× a hero. The Troll in the pack is 209.

## Resume 1

Fix loop 1: the owner's decision on the heights (option B of `PENDING-cv-art-heights.md`, D-146 corrected on main by #137, merged into the branch), and the accepted findings of the two audits.

Pull request #134, head `828bd9d`, CI green (tooling, client, cairo ×9, discover).

### Summary
- **Heights (owner's decision).** The pack's hand-drawn units are **not resampled at all**: factor exactly 1, and every frame is byte-identical to the pack's strip cell (110/110 frames, measured below). Only the three generated sheets are reduced: runt 67, shaman 87, hobgoblin 119.
- **Manifest.** `[build]` is gone. A `[height]` table has one line per sprite: `"native"` (never resampled) or a height in px. Any height stays one line to change.
- **Order check (AC-2), restated.** A basic goblin drawn from a generated sheet is never taller than the shortest profession. The pack's own hand-drawn goblins keep the pack's proportions and are not compared (its Spear Goblin, 70, is taller than its Monk, 67). The hobgoblin is taller than every other sprite. `[order]` and `[height]` are validated: unknown names fail, and so does a manifest with no profession.
- **Python.** The candidate `python3.12` is asked its version before `execv`, and a wrong one is refused. An environment marker (`GRIMWORLD_ART_REEXEC`) stops a second re-execution.
- **Venv.** The venv's own interpreter is asked its version and its installed distributions, which are checked against `requirements.txt`. It is rebuilt when its Python is below 3.12 or disagrees with `pyvenv.cfg`, or when a pin is missing or at another version. A 3.13 venv under a 3.12 start is kept.
- **Integer-only pipeline.** Every step that reaches an output pixel or a pose assignment is now integer (per-operation list below). The claim of equality across machines is a hypothesis until the orchestrator's Linux run, and the README says so.
- **Minors, all accepted and done:**
  - The PNG, fingerprint, snap, scale, order and venv tests.
  - `tomllib` imported inside `main`.
  - `--resample` checked at once; unknown arguments refused; the README lists every mode.
  - One grid helper; the `resample` docstring says the caller re-registers the feet.
  - A warning when an idle spans more than 6 px.
  - `--fingerprint` hashes only the build's outputs and skips dotfiles.
  - No output can print the forbidden name: every stream goes through a filter, and `--pack-heights` skips the generated folder.

### The chosen heights, and why
| sprite | `[height]` | why |
|---|---|---|
| runt | 67 | The pack's small goblins are Torch Goblin 67 and Spear Goblin 70 (owner: about 67–70). 67 is the only value in that range that keeps the order rule: the runt is a basic goblin from a generated sheet, so it may not be taller than the shortest profession, the cleric (Monk, 67). |
| shaman | 87 | The pack's heroes: Warrior 87, Archer 88 (owner: about 87). Not a basic goblin, so not compared with the cleric. |
| hobgoblin | 119 | The pack's Minotaur, 119 (owner: about 119). Taller than every other sprite (next: the warden at 88). |
| skirmisher, slinger, vanguard, warden, cleric | `"native"` | The pack's own drawings, untouched. |

Heights are the median of the idle frames by the rule of `artpipe/scale.py`, measured by `tools/art/build.py --pack-heights`. After the integer thresholds, it prints the same values as the first run: Warrior 87 (85–89), Archer 88 (86–89), Monk 67 (66–68), Pawn 72, Lancer 75, Torch Goblin 67 (66–68), Spear Goblin 70 (68–74), Minotaur 119 (118–121), Troll 209. It prints 35 lines, none carrying the forbidden name (grep count 0).

### Files changed (Resume 1)
- `tools/art/build.py`:
  - `parse_args` (unknown arguments and filters refused before anything runs);
  - `probe_version`, and `select_python` with the probe and the marker;
  - `pins`, `venv_problem`, and `bootstrap` (checks the venv, rebuilds, checks again, all injectable for tests);
  - the `Redacted` output filter;
  - `[height]` specs, `scale_sprite` (native or a number), `check_scale` (AC-1 on resampled sprites, the spread warning, the new order rule);
  - `pack_heights` skips the generated folder; `tomllib` imported in `main`.
- `tools/art/artpipe/clean.py`: integer key median, integer keying (fixed point 0–255), int64 centroid sums with integer division, integer width thresholds.
- `tools/art/artpipe/scale.py`: `grid` shared by both kernels; the `resample` docstring; `height_spec`, `validate_order`, and `check_order` with the new rule; integer band width.
- `tools/art/artpipe/fingerprint.py`: `outputs()`, only the files the build writes, dotfiles and others ignored.
- `tools/art/manifest.toml`: `[height]` replaces `[build]` and the per-sprite `build` lines; the `[order]` comment states the rule.
- `tools/art/tests/test_build.py`: 37 tests (were 12).
- `tools/art/README.md`: Python selection and venv rules, every mode, native heights, the order rule, the cause stated as a hypothesis with the measured evidence, the integer pipeline.

### Commands run
**`tools/art/build.py --check`** (started by Python 3.11 through the `#!/usr/bin/env python3` line):
```
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
warning: shaman: idle frames span 9 px (85-94), more than 6: the height is their median
key tolerance: 48 (max channel distance)
sprite     role       cell      frames  magenta pinkish page
runt       caste      160x80   18      0       0       atlas-0
skirmisher caste      220x159  21      0       0       atlas-0
slinger    caste      156x91   22      0       0       atlas-0
shaman     caste      270x122  18      0       0       atlas-0
hobgoblin  caste      286x168  18      0       52      atlas-0
vanguard   profession 130x113  28      0       0       atlas-0
warden     profession 106x98   18      0       0       atlas-0
cleric     profession 130x79   21      0       0       atlas-0
scale: resampling area; heights in px, visible height rule in artpipe/scale.py (idle frames, median and range)
sprite     height  target  source        factor          result        cell
runt       67      67      147 (144-147) 67/147=0.456    67 (66-67)    160x80
skirmisher native  70      70 (68-74)    1 (native)      70 (68-74)    220x159
slinger    native  67      67 (66-68)    1 (native)      67 (66-68)    156x91
shaman     87      87      153 (150-166) 87/153=0.569    87 (85-94)    270x122
hobgoblin  119     119     177 (176-178) 119/177=0.672   119 (119-120) 286x168
vanguard   native  87      87 (85-89)    1 (native)      87 (85-89)    130x113
warden     native  88      88 (86-89)    1 (native)      88 (86-89)    106x98
cleric     native  67      67 (66-68)    1 (native)      67 (66-68)    130x79
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3
✓ Lockfile passes supply-chain policies (verified 1h ago)
Lockfile is up to date, resolution step is skipped
Done in 2ms using pnpm v12.5.1
$ node check.mjs
PixiJS 8: 1 page(s), 164 frames, 26 animations parsed; every animation resolves to frames
```
The native sprites' cells are ART-00's exactly: 220×159, 156×91, 130×113, 106×98, 130×79.

**The two fingerprints (final, `out/` of the manifest as committed):**
```
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
```
They are identical on six builds on this Mac: two plain builds, `--check`, two starts by `python3` (3.11) in a row, and the final rebuild. They were also identical after a venv bootstrapped from nothing and after a rebuilt venv.

**Unit tests:**
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests -v`: `Ran 37 tests in 0.038s  OK`.
  - Command line (4): modes, unknown filter, unknown argument, the forbidden-name filter.
  - Fingerprint (3): encoder moves `files()` not `content()`, one pixel moves `content()`, only build outputs count.
  - Keying (1).
  - PNG (3): shapes 1×1, 1×9, 9×1, 37×53, flat; the chunk sequence and CRCs; the same array gives the same bytes.
  - Python selection (9): including a probed wrong `python3.12`, the marker, refusal before any venv.
  - Scale (11): including the two-colour snap at ×5/3, `scale_sprite` native and resampled, `check_scale` failure and warning, order rule and validation.
  - Venv (6): missing; a 3.11 venv rebuilt; a 3.13 venv kept under 3.12; a wrong numpy rebuilt; interpreter disagreeing with `pyvenv.cfg`; still unusable after a rebuild refused.
- `python3 -m unittest discover -s tools/art/tests` (3.11): `Ran 37 tests … OK`. This Python also has NumPy and Pillow, so nothing was skipped.

**The Python 3.11 start, real runs:**
```
$ python3 --version
Python 3.11.6
$ rm -r tools/art/.venv; python3 tools/art/build.py
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
... (venv created, pins installed, build) ...
out/ sha256: 347e8eaa…   out/ pixels+metadata sha256: 87c27153…
$ python3 -m venv tools/art/.venv; python3 tools/art/build.py
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
tools/art/.venv: pyvenv.cfg says Python 3.11, its interpreter is 3.12: rebuilding it
out/ sha256: 347e8eaa…   out/ pixels+metadata sha256: 87c27153…
$ grep version tools/art/.venv/pyvenv.cfg
version = 3.12.0
```
The second run is the audit's finding 2 in real life. A venv made by the 3.11 `python3` had a `bin/python` that actually runs 3.12, with `pyvenv.cfg` still saying 3.11. The old code would have used it whenever PIL and numpy imported; the new check rebuilt it.

**AC-3, one line:**
- `hobgoblin = 119` → `130`: the build moved only the hobgoblin, `hobgoblin  130  130  177 (176-178)  130/177=0.734  130 (130-130)  312x182`; every other row was unchanged. Reverted.

**AC-2, negative:**
- `runt = 67` → `70`: the build exited non-zero with the message below. Reverted; `git status` clean.
```
scale check failed:
  runt (70 px) is taller than the shortest profession, cleric (67 px)
```

**Refusals:**
```
$ tools/art/build.py --resample=lanczos
--resample=lanczos: unknown filter, one of area, area-blend, nearest
$ tools/art/build.py --chek
unknown argument '--chek'
```

**Native pixels untouched.** A scratch script (deleted) compared every atlas frame of the native sprites with the tight crop of the pack's strip cell:
```
skirmisher  frames identical to the pack's strip cells: 21/21
slinger     frames identical to the pack's strip cells: 22/22
vanguard    frames identical to the pack's strip cells: 28/28
warden      frames identical to the pack's strip cells: 18/18
cleric      frames identical to the pack's strip cells: 21/21
```

**Encoder evidence (Sonnet 5.5 finding 1).** The same array, the final atlas page, was written by Pillow (`compress_level=9`) and by `artpipe/png.write`, then read back:
```
pillow.png  991799 B  sha256 c1e3d13896e63482  decoded pixels sha256 b2d6c07e73afe432  equal to the array: True
stdlib.png  1025860 B  sha256 ecb00cc9fe04841c  decoded pixels sha256 b2d6c07e73afe432  equal to the array: True
encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3
```
The first run measured the same thing on ART-00's atlas: 2333376 B vs 2441050 B, different hashes, pixels equal.

**Memory (Sonnet 5.5 finding 11).** One build, peak RSS of the child through `resource.getrusage(RUSAGE_CHILDREN)`: **775 MiB** (exit 0). That is far below the Mac (64 GB) and the VPS (31 GB), so I changed nothing.

**Other checks:**
- `git ls-files '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.aseprite' '*out/*'` printed nothing.
- The forbidden-name check runs in every build and passed.
- `gh pr checks 134 --watch`: every check passed.

### Integer-only: every float operation that reached a pixel or a pose (GPT-6-Sol finding 3)
| Step | Before | Now |
|---|---|---|
| `clean.sheet_key`, the key colour | `np.median` (partition, then the float mean of two values) | Upper middle of an integer `np.sort`: an integer, no averaging |
| `clean.key_sheet`, the background test | float32 `abs(p - key).max` | int64 `abs(p - key).max`: max is exact in any order |
| `clean.key_sheet`, alpha | float32 `1 - m / m_key`, clip, `a < min_alpha` | Integer fixed point: `a = round(255 (m_key - m) / m_key)` by `(2n + d) // 2d`, clip 0–255, drop below `ceil(255 · min_alpha)` = 16 (a Python scalar) |
| `clean.key_sheet`, colour | float32 `(p - (1 - a) key) / max(a, 1e-3)`, `np.rint` | Integer `round((255 p - (255 - a) key) / a)`, clip 0–255 |
| `clean.cut_generated`, centroid sums | `np.bincount(weights=…)`: a float64 weighted sum | int64 `np.add.at`: exact in any order |
| `clean.cut_generated`, centroid cell | `int(sum / count) // 256`, a float division | `sum // count // 256`, integer |
| `clean.cut_generated`, areas, counts, boxes, gaps | Integer (unweighted `bincount`, `minimum.at`, `maximum.at`) | Unchanged |
| `clean.register`, feet thresholds | Python `round(0.08 · w)`, `round(0.04 · h)` | `(8w + 50) // 100`, `(4h + 50) // 100` |
| `scale.visible_height`, band | `round(0.10 · w)` | `(w + 5) // 10` |
| `build.verify`, the read-back rule | `round(0.08 · w)` | The same integer rule as `clean.register` |
| `scale.resample`, `scale.snap`, `artpipe/png.py` | Already int64: matrix products of integers, rounded integer division, integer distances, first-index argmin, int16 Paeth | Unchanged |
| Anchor written to the JSON, `round(baseline / cell_h, 6)` | A Python scalar: one IEEE double division, one `round`, `repr` | Kept: element-wise IEEE, correctly rounded, the same on every machine; no reduction |
| Decoding the sources (Pillow `open().convert()`) | Inflate plus exact conversions (RGB→RGB, RGBA or P→RGBA by table) | Unchanged |

The pixel fingerprint changed from the first run (`5af16e6d…` → `87c27153…`), as expected: the heights changed, and the integer keying rounds some fringe pixels differently from the float version. Equality across machines stays a hypothesis until the orchestrator's Linux run; the README says so.

### Acceptance criteria after Resume 1
- **AC-1: met, per the corrected decision.** Native sprites are their own target (factor 1, measured 110/110 frames identical to the pack). The three resampled sprites' medians are exactly 67 / 87 / 119, checked ±2 by the build. The shaman's idle spans 9 px (85–94) and the build warns about it, as it does for any spread above 6 px.
- **AC-2: met, with the restated rule.** Unit test `test_order_rule` (a generated runt at 70 fails; the native Spear Goblin at 70 is exempt; a short boss fails) and the negative build run.
- **AC-3: met.** One `[height]` line (`hobgoblin`) moved only the hobgoblin.
- **AC-4: met.** `--check` is green: the ART-00 checks, AC-1/AC-2, PixiJS (164 frames, 26 animations).
- **AC-5: met.**
  - Re-execution from 3.11 (real run); refusal of a missing, wrong or looping `python3.12` (tests); bootstrap from a removed venv (real run).
  - A wrong-Python venv rebuilt (real run and tests); a pin mismatch rebuilt (test).
- **AC-6: met on the Mac; Linux to run.** Same two fingerprints on six builds. The cause is stated as a hypothesis with its evidence.
- **AC-7: met.** No image tracked or posted; the pull request body carries this report, numbers only.

### The Linux command (for the orchestrator)
From this branch's worktree on the VPS, with the pack present:
1. `tools/art/build.py --check`
2. Compare with this Mac:
   - `out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7`: the reference.
   - `out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862`: equal too if the VPS Python's zlib deflates like 1.2.12. The `encoders:` line shows it.
3. If the pixel line differs, `out/report.json` shows where: `sheets.*.key` and every `scale` block (`source_frames`, `frames`). Comparing that file between the machines points to the step.

### Deviations (Resume 1)
- The owner named "about 67–70" for the runt; I chose 67, the lower bound, because the restated order rule (a generated basic goblin no taller than the shortest profession, the Monk at 67) allows nothing above it. If the owner wants 68–70, the order rule has to compare with another hero, or the cleric has to be exempt; that is one line in `[order]` or in `check_order`, not done.
- The integer keying rounds fringe alpha and colours slightly differently from ART-00's float keying. It is a pixel change on the generated sheets only; the magenta check stays at 0, and the hobgoblin's pinkish count is 52 (58 in the first run, 110 in ART-00, before any scaling).
- Memory: measured, not changed (775 MiB).

### Escalations
- **The pull request body could not be replaced.** `gh pr edit 134 --body-file REPORT.md` fails on every call with `GraphQL: Projects (classic) is being deprecated … (repository.pullRequest.projectCards)`: this `gh` version queries a field GitHub has retired. The REST form (`gh api -X PATCH …/pulls/134`) is refused by my profile. So the full report is posted as a **comment** on #134 (https://github.com/bal7hazar/grimworld/pull/134#issuecomment-5889674504), and the body still holds the first run's summary. The orchestrator can copy the comment into the body, or update `gh`.
- D-146 is corrected on main (#137), and no shared file needed a change.

### Open questions (for the owner, on CLI-03a's sandbox)
1. **The runt at 67** stands exactly as tall as the cleric and the slinger (Torch Goblin). Does it read as a basic goblin next to the 70 px skirmisher?
2. **The shaman at 87** is as tall as the vanguard. Its idle spans 85–94, because one frame raises the staff hand into the measured band.
3. **The hobgoblin at 119** is 1.37× the vanguard.
4. **Resampling now touches only the generated sheets** (×0.46, ×0.57, ×0.67, all downscales). In `preview.html`, look at the runt's face and the shaman's necklace at these sizes.

## Resume 2

Fix loop 2: the second passes of both audits. Pull request #134, head `633f2f5`, CI green (tooling, client, cairo ×9, discover). The heights, the table and the fingerprints are unchanged from Resume 1.

### What changed
- **[GPT-6-Sol] 1: direct launch from the venv.** Started by `tools/art/.venv/bin/python` (so `sys.prefix` is the venv), `bootstrap()` no longer returns at once. It checks the running venv with `venv_check`: Python ≥ 3.12, a readable `pyvenv.cfg` naming the same version, and every pin at its version (read in-process through `importlib.metadata`). When any check fails, it refuses and says how to rebuild (`python3 tools/art/build.py`), because a venv cannot rebuild itself while it runs.
- **[GPT-6-Sol] 2: `pyvenv.cfg` and the handoff.**
  - A venv without a readable `pyvenv.cfg` is now a problem ("no readable pyvenv.cfg"), so it is rebuilt.
  - The handoff to `.venv/bin/python` sets `GRIMWORLD_ART_VENV`. A process that finds it set, yet is not running inside the venv, refuses ("refusing to loop") instead of re-executing again. The marker is removed once inside the venv.
- **[GPT-6-Sol] 4: hashed pins.** `requirements.txt` pins `pillow==12.3.0` and `numpy==2.5.3` with `--hash=sha256:`, read from PyPI's JSON API (`https://pypi.org/pypi/<name>/<version>/json`). The venv is installed with `pip install --require-hashes`. The pinned files:
  - `pillow-12.3.0-cp312-cp312-macosx_11_0_arm64.whl` `ffd0c536…`
  - `pillow-12.3.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl` `78cb2c68…`
  - `pillow-12.3.0-cp313-cp313-macosx_11_0_arm64.whl` `d6914151…`
  - `pillow-12.3.0-cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl` `0847a763…`
  - `numpy-2.5.3-cp312-cp312-macosx_11_0_arm64.whl` `f59a878c…`
  - `numpy-2.5.3-cp312-cp312-macosx_14_0_arm64.whl` `a72f874b…`
  - `numpy-2.5.3-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl` `b7e18c62…`
  - `numpy-2.5.3-cp313-cp313-macosx_11_0_arm64.whl` `92f30e89…`
  - `numpy-2.5.3-cp313-cp313-macosx_14_0_arm64.whl` `f9a2353b…`
  - `numpy-2.5.3-cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl` `a5fa86b8…`

  The full hashes are in the file. I added cp313 because the build keeps a 3.13 venv (Resume 1, "no churn"), and pip would refuse a 3.13 install without its hashes. There is no sdist, so a machine without a matching wheel is refused rather than compiling NumPy.
- **[Sonnet 5.5] N2: the order rule is by outcome.** Every name in `[order] basic` is compared with the shortest profession, except the names in `[order] exempt`. `exempt` must be in `basic` and native, or the manifest is refused. The manifest lists the one exemption: `exempt = ["skirmisher"]`, the native Spear Goblin at 70 px, taller than the pack's Monk (the cleric) at 67. A resampled basic goblin is always compared: `slinger = 80` fails (real run and test).
- **[Sonnet 5.5] N4.** `scale.validate_manifest(manifest, methods)` holds every cross-check that needs no image:
  - `[height]` names exactly the sprites, and each line is `"native"` or a positive int;
  - `[order]` names only sprites, an exemption is basic and native, and there is at least one profession;
  - `settings.resample` is valid.

  It is tested with dicts. The "target equals measured: keep the cells" branch has its own test.
- **[Sonnet 5.5] N3.** A test of an exact 50 % fringe pixel. Key (250, 4, 250) and grey (100, 100, 100) mix to (175, 52, 175): alpha 127.5 rounds half up to 128, and the colour comes out (101, 100, 101). A test of `div_round` with negative numerators (−1.5 → −1, −2.5 → −2, −0.5 → 0, −1.75 → −2).
- **[Sonnet 5.5] N6.** The table prints `native, cells unchanged` in the factor column (and `1, cells unchanged` when a numeric target equals the measured height).
- **[Sonnet 5.5] N8.** The two long README lines are rewrapped. The README also describes the direct launch, the handoff guard, the hashed pins and the exemption.
- **[Sonnet 5.5] N1: not done, blocked.** See Escalations.
- **Not changed:** [GPT-6-Sol] 3 (not accepted: the pack's unit names are public, and the generated folder's name never prints), 5, 6, 7, and [Sonnet 5.5] N5, N7 (notes).

### Files changed (Resume 2)
- `tools/art/build.py`:
  - `HANDOFF`; `pins` reads continuation lines and `--hash`;
  - `own_info`, `venv_check` (split out of `venv_problem`), `pyvenv.cfg` required;
  - `bootstrap` checks the running venv, guards the handoff, installs with `--require-hashes`;
  - the manifest checked by `scale.validate_manifest`; `check_order` receives the `[height]` specs;
  - the table's `native, cells unchanged`.
- `tools/art/artpipe/scale.py`: `height_problem`, `validate_manifest`, `validate_order` (exempt must be basic and native), and `check_order` by outcome with `exempt`. `height_spec` is removed; its checks moved into `validate_manifest`.
- `tools/art/manifest.toml`: `[order] exempt = ["skirmisher"]` and the rule in the comment.
- `tools/art/requirements.txt`: hashed pins (10 wheels).
- `tools/art/tests/test_build.py`: 45 tests (were 37).
  - New: the direct launch, good and unpinned; the venv without `pyvenv.cfg`; the handoff happening once; `validate_manifest`; the exemption rules; `slinger = 80`; keep-cells; the 50 % fringe; `div_round`.
- `tools/art/README.md`: the venv rules, the hashes, the order rule; long lines rewrapped.

### Commands run
**Bootstrap from a removed venv with the hashed pins, then `--check`**: `rm -r tools/art/.venv; python3 tools/art/build.py --check`
```
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
warning: shaman: idle frames span 9 px (85-94), more than 6: the height is their median
key tolerance: 48 (max channel distance)
sprite     role       cell      frames  magenta pinkish page
runt       caste      160x80   18      0       0       atlas-0
skirmisher caste      220x159  21      0       0       atlas-0
slinger    caste      156x91   22      0       0       atlas-0
shaman     caste      270x122  18      0       0       atlas-0
hobgoblin  caste      286x168  18      0       52      atlas-0
vanguard   profession 130x113  28      0       0       atlas-0
warden     profession 106x98   18      0       0       atlas-0
cleric     profession 130x79   21      0       0       atlas-0
scale: resampling area; heights in px, visible height rule in artpipe/scale.py (idle frames, median and range)
sprite     height  target  source        factor                   result        cell
runt       67      67      147 (144-147) 67/147=0.456             67 (66-67)    160x80
skirmisher native  70      70 (68-74)    native, cells unchanged  70 (68-74)    220x159
slinger    native  67      67 (66-68)    native, cells unchanged  67 (66-68)    156x91
shaman     87      87      153 (150-166) 87/153=0.569             87 (85-94)    270x122
hobgoblin  119     119     177 (176-178) 119/177=0.672            119 (119-120) 286x168
vanguard   native  87      87 (85-89)    native, cells unchanged  87 (85-89)    130x113
warden     native  88      88 (86-89)    native, cells unchanged  88 (86-89)    106x98
cleric     native  67      67 (66-68)    native, cells unchanged  67 (66-68)    130x79
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3
✓ Lockfile passes supply-chain policies (verified 2h ago)
Lockfile is up to date, resolution step is skipped
Done in 5ms using pnpm v12.5.1
$ node check.mjs
PixiJS 8: 1 page(s), 164 frames, 26 animations parsed; every animation resolves to frames
```
Then `tools/art/.venv/bin/python -m pip list` showed `numpy 2.5.3` and `pillow 12.3.0`, installed through `--require-hashes`.

**The fingerprints**, the same as Resume 1, on every build of this resume: the `--check` above, a direct launch, two rebuilds and two 3.11 starts in a row.
```
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
```

**The Python 3.11 start**, twice:
```
$ python3 --version
Python 3.11.6
$ python3 tools/art/build.py      (first)
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
out/ sha256: 347e8eaa…   out/ pixels+metadata sha256: 87c27153…
$ python3 tools/art/build.py      (second)
out/ sha256: 347e8eaa…   out/ pixels+metadata sha256: 87c27153…
```

**Direct launch from the venv (GPT-6-Sol 1), real:**
```
$ tools/art/.venv/bin/python tools/art/build.py            (good venv: builds, same fingerprints)
$ tools/art/.venv/bin/python -m pip install --quiet pillow==12.2.0
$ tools/art/.venv/bin/python tools/art/build.py
tools/art/.venv, the running venv: pillow 12.2.0, requirements.txt pins 12.3.0. Run `python3 tools/art/build.py` (not the venv's python) to rebuild it.
$ python3 tools/art/build.py
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
tools/art/.venv: pillow 12.2.0, requirements.txt pins 12.3.0: rebuilding it
out/ sha256: 347e8eaa…   out/ pixels+metadata sha256: 87c27153…
```

**A venv without `pyvenv.cfg` (GPT-6-Sol 2), real.** Without the file, Python does not run the folder's interpreter as a venv (`sys.prefix` is the system's). The old code accepted such a venv and handed off to it on every run. Now it is rebuilt before the one handoff:
```
$ rm tools/art/.venv/pyvenv.cfg; tools/art/.venv/bin/python tools/art/build.py
tools/art/.venv: no readable pyvenv.cfg: rebuilding it
... (build) ...
$ grep version tools/art/.venv/pyvenv.cfg
version = 3.12.0
```
The loop guard itself is shown by `test_handoff_happens_once`: after one handoff, a process outside the venv with the marker set refuses, and `execv` is called exactly once.

**The order rule by outcome (N2), real negative run.** `slinger = "native"` changed to `slinger = 80`, then reverted:
```
build exited non-zero
scale check failed:
  slinger (80 px) is taller than the shortest profession, cleric (67 px)
```

**Unit tests:**
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 45 tests in 1.317s  OK`.
- `python3 -m unittest discover -s tools/art/tests` (3.11): `Ran 45 tests in 0.043s  OK`.

**Other checks:**
- `git ls-files '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.aseprite' '*out/*'` printed nothing.
- `gh pr checks 134 --watch`: every check passed.

### Acceptance criteria after Resume 2
All as in Resume 1, and:
- **AC-2:** the rule is now by outcome, with the one exemption listed explicitly.
- **AC-5:** the direct venv launch, the missing `pyvenv.cfg`, the handoff guard and the hashed install are all covered, by real runs and tests.

### Escalations
- **N1, the pull request body, is still not replaced.** `gh pr edit 134 --body-file pr-body.md` failed again with `GraphQL: Projects (classic) is being deprecated … (repository.pullRequest.projectCards)`, and `gh pr view` confirms the body is unchanged. This `gh` build queries a retired field before it edits; the REST form (`gh api -X PATCH …`) is refused by my profile. The current summary and table (67 / 87 / 119, five natives at factor 1, the fingerprints, the acceptance criteria) are posted as a comment: https://github.com/bal7hazar/grimworld/pull/134#issuecomment-5889888797. Copying that comment into the body needs either a newer `gh` or the REST call, from the orchestrator or with a profile that allows `gh api`.

## Resume 3

The last fix loop allowed on this lot (OPERATIONS §6), limited to the listed findings; nothing else changed. Pull request #134, head `47dc380`, CI green (tooling, client, cairo ×9, discover). The heights, the table and both fingerprints are unchanged.

### What changed
- **[GPT-6-Sol] 1: only the hashed Pythons.**
  - `build.py` now has one constant, `PYTHONS = ((3, 12), (3, 13))`: exactly the versions whose wheels `requirements.txt` pins by hash (cp312, cp313). Its comment and the requirements file's comment point to each other.
  - `select_python` accepts only those. A newer Python is refused before any venv is touched, naming them: `tools/art/build.py runs under Python 3.12 or 3.13 (the versions whose wheels requirements.txt pins by hash), found 3.14: run it with Python 3.12 or 3.13.`
  - An older Python still re-executes once under `python3.12`, whose probed version must also be in `PYTHONS`.
  - `venv_check` refuses a venv whose interpreter is outside `PYTHONS` (`its interpreter is Python 3.14, not 3.12 or 3.13`), so such a venv is rebuilt.
  - Tests: 3.14 refused with the exact message; 3.14 refused before any venv is created (no `run`, no `execv`); a 3.14 venv rebuilt.
- **[GPT-6-Sol] 2: an exemption must be a pack drawing.** `validate_order` receives the sprites' kinds: an `[order] exempt` name must be basic, native **and** of kind `strip`. `validate_manifest` passes the kinds, and so does `check_order` (from `check_scale`). The audit's case — a generated runt, native and exempt, at 150 px — now fails with `[order] exempt 'runt' is a generated sprite: only a drawing of the pack (kind strip) may be exempt` (tests on `validate_manifest` and `check_order`).
- **[GPT-6-Sol] 3.** The test of a missing venv asserts the pip command exactly: `-m pip install --quiet --require-hashes -r <tools/art/requirements.txt>`.
- **[Sonnet 5.5] 1: the pull request body.** `gh pr edit 134 --body-file pr-body.md` was refused again (the same GraphQL error, below). The text is under **PR body**, next section, for the orchestrator to set.
- **[Sonnet 5.5] 2: one interpreter check.** `INFO` holds the code once (`info(names)` → Python version and distribution versions). `PROBE` is `INFO` plus a JSON print, run in the venv's interpreter. `own_info` runs the same `INFO` in this process. Test: `PROBE` starts with `INFO`, and `own_info` returns this interpreter's version.
- **[Sonnet 5.5] 4.** The `validate_manifest` tests assert the exact messages (the whole list).
- **[Sonnet 5.5] 5, 6.**
  - The unused `cfg` parameter of the test helper `direct()` is dropped.
  - The nested comprehension at `scale.py:173` (the `[height]` line checks) is a plain loop.
- **Docs, only where the change made them false.**
  - README: "3.12 or 3.13, exactly", 3.14 refused, venv rebuilt when not 3.12 or 3.13, exemptions of kind strip.
  - The `build.py` docstring, the `[order]` comment in `manifest.toml`, the requirements comment.

### Files changed (Resume 3)
`tools/art/build.py`, `tools/art/artpipe/scale.py`, `tools/art/tests/test_build.py` (49 tests, were 45), `tools/art/README.md`, `tools/art/manifest.toml` (comment only), `tools/art/requirements.txt` (comment only).

### Commands run
**`rm -r tools/art/.venv; python3 tools/art/build.py --check`** (started by Python 3.11.6; the venv was bootstrapped from nothing with `--require-hashes`):
```
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
warning: shaman: idle frames span 9 px (85-94), more than 6: the height is their median
key tolerance: 48 (max channel distance)
sprite     role       cell      frames  magenta pinkish page
runt       caste      160x80   18      0       0       atlas-0
skirmisher caste      220x159  21      0       0       atlas-0
slinger    caste      156x91   22      0       0       atlas-0
shaman     caste      270x122  18      0       0       atlas-0
hobgoblin  caste      286x168  18      0       52      atlas-0
vanguard   profession 130x113  28      0       0       atlas-0
warden     profession 106x98   18      0       0       atlas-0
cleric     profession 130x79   21      0       0       atlas-0
scale: resampling area; heights in px, visible height rule in artpipe/scale.py (idle frames, median and range)
sprite     height  target  source        factor                   result        cell
runt       67      67      147 (144-147) 67/147=0.456             67 (66-67)    160x80
skirmisher native  70      70 (68-74)    native, cells unchanged  70 (68-74)    220x159
slinger    native  67      67 (66-68)    native, cells unchanged  67 (66-68)    156x91
shaman     87      87      153 (150-166) 87/153=0.569             87 (85-94)    270x122
hobgoblin  119     119     177 (176-178) 119/177=0.672            119 (119-120) 286x168
vanguard   native  87      87 (85-89)    native, cells unchanged  87 (85-89)    130x113
warden     native  88      88 (86-89)    native, cells unchanged  88 (86-89)    106x98
cleric     native  67      67 (66-68)    native, cells unchanged  67 (66-68)    130x79
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3
✓ Lockfile passes supply-chain policies (verified 2h ago)
Lockfile is up to date, resolution step is skipped
Done in 2ms using pnpm v12.5.1
$ node check.mjs
PixiJS 8: 1 page(s), 164 frames, 26 animations parsed; every animation resolves to frames
```

**A second 3.11 start, then a direct launch from the venv:**
```
$ python3 tools/art/build.py
Python 3.11: re-executing under /opt/homebrew/bin/python3.12
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
$ tools/art/.venv/bin/python tools/art/build.py
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
```

**The fingerprints** (the same on all three builds, and the same as Resumes 1 and 2):
```
out/ sha256: 347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862
out/ pixels+metadata sha256: 87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7
```

**Unit tests:**
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 49 tests … OK`.
- `python3 -m unittest discover -s tools/art/tests` (3.11): `Ran 49 tests … OK`.

No Python 3.14 is installed on this Mac, so the 3.14 refusal is shown by the tests only (`test_refuses_python_3_14_naming_the_hashed_versions`, `test_python_3_14_refused_before_any_venv`, `test_venv_of_python_3_14_is_rebuilt`).

**Other checks:**
- `git ls-files '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.aseprite' '*out/*'` printed nothing.
- `gh pr checks 134 --watch`: every check passed.

**The pull request body, refused:**
```
$ gh pr edit 134 --body-file pr-body.md
GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience, see: https://github.blog/changelog/2024-05-23-sunset-notice-projects-classic/. (repository.pullRequest.projectCards)
```
(exit code 1; the body is unchanged). The REST form (`gh api -X PATCH …`) is refused by my profile. The orchestrator should set the text below as the body of #134.

### PR body

````markdown
ART-02 (brief `docs/briefs/ART-02-atlas-scale.md`; D-146 as corrected by the owner on 2026-09-29, option B). No image or anything derived from the pack is in this pull request (D-73); numbers only. The full report, with every command's output, is `REPORT.md` in the task's worktree (first run, Resumes 1, 2 and 3).

## Summary
- **Heights.** The pack's hand-drawn units are native: never resampled, factor 1, every frame byte-identical to the pack's strip cell (110/110). Only the generated sheets are reduced, to the scale of the pack's units: runt 67, shaman 87, hobgoblin 119.
  - `tools/art/manifest.toml` `[height]` has one line per sprite: `"native"` or a height in px.
  - `tools/art/build.py --pack-heights` measures the pack's units: Warrior 87, Archer 88, Monk 67, Torch Goblin 67, Spear Goblin 70, Minotaur 119.
- **Order check (AC-2).** No basic goblin is taller than the shortest profession, except names in `[order] exempt`, which must be native drawings of the pack (kind strip): the skirmisher, the pack's Spear Goblin, 70 px, taller than its Monk, 67. A resampled or generated basic goblin is always compared. The hobgoblin is the tallest sprite.
- **Visible height rule.** The median of the idle frames, from the feet to the top of the head, in a band of columns over the feet, so held weapons don't count.
- **Resampling** (generated sheets only). Exact integer resampling anchored at the feet (`area`: overlap average, alpha kept to the source's levels, palette snap for small palettes).
- **Python and venv.**
  - The build runs under exactly the Pythons whose wheels `requirements.txt` pins by hash: 3.12 and 3.13 (`PYTHONS`, one place). A newer one (3.14) is refused, naming them. An older one re-executes once under a probed `python3.12`.
  - The venv is checked through its own interpreter: its version in `PYTHONS`, a readable `pyvenv.cfg` that matches, pins at their versions. Otherwise it is rebuilt with `pip --require-hashes`.
  - A direct launch from the venv validates the running venv; the handoff to the venv happens once.
- **Cross-machine.** PNGs are written with Python's own zlib (Pillow's zlib-ng is the suspected cause of ART-00's Mac/Linux difference: a hypothesis until the Linux run). Every pixel step is integer. The build prints a pixels-and-metadata fingerprint next to the file fingerprint.

| sprite | height | target | source (median, idle range) | factor | result (median, idle range) | cell |
|---|---|---|---|---|---|---|
| runt | 67 | 67 | 147 (144–147) | 67/147 = 0.456 | 67 (66–67) | 160×80 |
| skirmisher | native | 70 | 70 (68–74) | native, cells unchanged | 70 (68–74) | 220×159 |
| slinger | native | 67 | 67 (66–68) | native, cells unchanged | 67 (66–68) | 156×91 |
| shaman | 87 | 87 | 153 (150–166) | 87/153 = 0.569 | 87 (85–94) | 270×122 |
| hobgoblin | 119 | 119 | 177 (176–178) | 119/177 = 0.672 | 119 (119–120) | 286×168 |
| vanguard | native | 87 | 87 (85–89) | native, cells unchanged | 87 (85–89) | 130×113 |
| warden | native | 88 | 88 (86–89) | native, cells unchanged | 88 (86–89) | 106×98 |
| cleric | native | 67 | 67 (66–68) | native, cells unchanged | 67 (66–68) | 130×79 |

Fingerprints on macOS arm64, identical on every build of Resumes 1, 2 and 3:
- files `347e8eaa9187d6cb77daddc43c6624174a56587d73c3a442b09aa971e639e862`
- pixels and metadata `87c27153e2c681d3ffc8178f50f8c8a544ca20e45ebe37e506f67f12386abef7`

Linux check: `tools/art/build.py --check` on the VPS, then compare the `pixels+metadata` line.

## Acceptance criteria
- [x] AC-1: native sprites are their own target; the resampled medians are exactly 67 / 87 / 119, checked ±2. The table is printed by the build; the shaman's 9 px idle spread gets a warning.
- [x] AC-2: the order rule above. Tests, plus negative builds: `runt = 70` fails, `slinger = 80` fails; a generated sprite cannot be exempt.
- [x] AC-3: one `[height]` line changes one sprite (`hobgoblin = 130` moved only the hobgoblin).
- [x] AC-4: `tools/art/build.py --check` is green (ART-00 checks, scale checks, PixiJS: 164 frames, 26 animations).
- [x] AC-5: the 3.11 start re-executes under 3.12, and 3.14 is refused. The refusals and venv rebuilds are covered by 49 unit tests and by real runs (a removed venv, an unpinned venv, a venv without `pyvenv.cfg`).
- [x] AC-6: same fingerprints on every Mac run; the Linux comparison is for the orchestrator.
- [x] AC-7: `git ls-files` lists no image, atlas or anything from `out/` or `assets/`; the forbidden-name check passes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
````

### Escalations
- **The body of #134** must be set by the orchestrator from the "PR body" section above. My `gh` fails on `gh pr edit` (the GraphQL `projectCards` error), and my profile refuses `gh api`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
