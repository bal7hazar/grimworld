# [Sonnet 5.5] ART-03 — pack originals

## Summary
Every sprite of the atlas now comes from the pack's own strips, at native size. runt = Thief, shaman = Hex Shaman, hobgoblin = Troll (skirmisher, slinger, vanguard, warden, cleric unchanged). The code only the generated sheets needed is gone. The order rule is a **warning** between native drawings and stays an **error** when a resampled sprite is involved. PR: https://github.com/bal7hazar/grimworld/pull/164 (CI green: discover, tooling, client and the rest). Model matches the brief (Sonnet 5.5).

## Files changed
- `tools/art/manifest.toml`: the mapping; every sprite a strip (the `kind` field is gone), every height `"native"`; `[order]` without `exempt`; the keying settings removed.
- `tools/art/build.py`: generated-folder discovery, keying/cut branch, magenta/pinkish measurement and columns removed; `check_scale` takes the specs and returns the order warnings; `--pack-heights` no longer excludes a folder; `verify` uses the same feet fallback as `clean.register` (needed by the small projectile frames).
- `tools/art/artpipe/clean.py`: `dilate`, `sheet_key`, `div_round`, `key_sheet`, `label`, `cut_generated`, `GRID`, `COLS` removed.
- `tools/art/artpipe/scale.py`: `validate_order`, `validate_manifest` lose `exempt` and `kind`; `check_order` returns (errors, warnings).
- `tools/art/tests/test_build.py`: the Keying tests removed; order-rule tests rewritten; new tests below.
- `tools/art/README.md`: updated (cutting, scale, checks, manifest).

## New table (sprite, strip, animations and frames, native height, cell)
| Sprite | Source strips | Animations (frames) | Native height | Cell |
|---|---|---|---|---|
| runt | Thief | idle 6, move 6 (Run), attack 6 | 73 (72-76) | 164x96 |
| skirmisher | Spear Goblin | idle 8, move 6, attack 7 | 70 (68-74) | 220x159 |
| slinger | Torch Goblin (placeholder) | idle 8, move 6, attack 8 | 67 (66-68) | 156x91 |
| shaman | Hex Shaman | idle 8, move 4 (Run), attack 10, projectile 3, explosion 9 | 70 (69-73) | 168x109 |
| hobgoblin | Troll | idle 12, move 10 (Walk), attack 6 | 209 (206-211) | 356x233 |
| vanguard | Warrior, blue | idle 8, move 6, attack 4, attack2 4, guard 6 | 87 (85-89) | 130x113 |
| warden | Archer, blue | idle 6, move 4, attack 8 | 88 (86-89) | 106x98 |
| cleric | Monk, blue | idle 6, move 4, heal 11 | 67 (66-68) | 130x79 |

Frame rates: 12 for idle and move, 15 for attacks, projectile (loop) and explosion. The Troll's Windup (5) and Recovery (10) strips exist and are not used ("only what the strips hold" for its attack: the Attack strip alone); adding them is a manifest change.

## The order rule's outcome
Measured on native drawings: runt 73 and skirmisher 70 are taller than the shortest profession (cleric, 67); slinger 67 is not; hobgoblin (Troll) 209 is the tallest by far. So the "basic goblin no taller than a hero" rule **fails on native drawings** (Thief and Spear Goblin), the "boss tallest" rule holds. Nothing was resampled: the failure is a warning printed by the build; it would be an error if any sprite involved had a height in px. Tested: `test_order_rule_on_native_drawings_is_a_warning`, `test_order_rule_on_a_resampled_sprite_is_an_error`, `test_check_scale_native_order_failure_only_warns`.

## What was removed
Magenta keying and unmixing (`key_sheet`, `sheet_key`, `div_round`), silhouette cutting (`cut_generated`, `label`, `dilate`, grid constants), generated-folder discovery (`generated_dir`), `kind = "generated"` and the `kind` field, the `exempt` mechanism, key settings, the magenta-left check and report columns, their tests. Kept: the resampler and its tests, the forbidden-name check (still covers `tools/art` and `CREDITS.md`) and the output filter.

## Commands run
- `python3 tools/art/build.py --check` → table above; warnings: `runt (73 px) is taller than the shortest profession, cleric (67 px)`, `skirmisher (70 px) ... cleric (67 px)`; `PixiJS 8: 1 page(s), 190 frames, 28 animations parsed; every animation resolves to frames`.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests` → `Ran 49 tests ... OK`.
- Second `python3 tools/art/build.py` → identical fingerprints.
- `python3 tools/art/build.py --pack-heights`: no redacted name in the output (0 matches of `<generated>`).

## Fingerprints (two builds identical)
- `out/ sha256: 78cea42020f5b3e0b7687772b06f3bc0659c69322b3335dfe2cf438b64383dd1`
- `out/ pixels+metadata sha256: a58ff45210ad77f844cd66a7ed4a5cf537c4f6523acd1258eea4918134f33182`
- `encoders: zlib (python) 1.2.12, zlib (Pillow) 1.3.1.zlib-ng, Pillow 12.3.0, NumPy 2.5.3`

## Cost
—

## Acceptance criteria
- AC-1: eight sprites, all strips, all native; the table prints each height (build output).
- AC-2: no generated-sheet code, test or manifest entry; forbidden-name check runs at every build and passes; `CREDITS.md` does not name the sheets.
- AC-3: see the order rule section and the three tests.
- AC-4: `--check` green, 49 tests OK, fingerprints equal across two builds.
- AC-5: only `tools/art/**` files in the commit; no image, `out/` ignored; no folder name of the generated sheets written (the redaction test builds its sample from the filter's own constant with a neutral path).

## Deviations from the brief
- The Hex Shaman's projectile and explosion are registered on their lowest wide row like any pose; this widens the shaman's cell (168x109) beyond the body. The idle height is unaffected. `build.py`'s `verify` needed the same fallback as `register` for those small frames.
- The `exempt` list of `[order]` was removed (the warning/error split replaces it).

## Escalations
None. design/10 needs the mapping updated by the project manager (not in my allowlist). `CREDITS.md` untouched.

## Open questions
- Is the Troll's Windup/Recovery wanted as animations (the boss's telegraph)?
- The shaman's projectile and explosion sit in the shaman's cell; the client may prefer them positioned separately.

## Resume 1
The open question is answered (owner: yes). Added to the hobgoblin, from the Troll's strips:
- `windup` = `Troll_Windup.png`, 5 frames, 12 fps, not looping (the boss's telegraph).
- `recover` = `Troll_Recovery.png`, 10 frames, 15 fps, not looping.

The hobgoblin now has idle 12, move 10, windup 5, recover 10, attack 6 (43 frames). Same cell and baseline: cell 356x233 unchanged, baseline 228 for every frame (`sprites.json`), and `verify` re-reads each frame's baseline from the PNG and passes. Native height still 209 (206-211): windup and recover are not idle frames. The README lists no per-sprite animations, and the PixiJS check reads `sprites.json`, so neither needed an edit; the check now parses 205 frames, 30 animations.

Commands: `python3 tools/art/build.py --check` green (`PixiJS 8: 1 page(s), 205 frames, 30 animations parsed; every animation resolves to frames`); unit tests `Ran 49 tests ... OK`; two builds give the same fingerprints:
- `out/ sha256: 4f9d1953e24eef7cd5669e2f36b2f6831a1287e548b3584964d6b98a0f0b5ea5`
- `out/ pixels+metadata sha256: cddc2d8fa21c7621165c638d79bfe7db127b6c875d8b845c8b115032a8578db5`

Pushed to #164 (commit 796923a); CI green (discover, tooling, client, cairo jobs; indexer-node skipped). The earlier fingerprints and the hobgoblin's table row (28 frames, no windup/recover) are superseded.

## Resume 2 (fix loop 1, the two audits of #164)
Accepted findings, all done (commit 27e8367):
- **[Sonnet 5.5] 1**: `RealManifest` tests in `tests/test_build.py` (stdlib only, `tomllib`, runs without the venv): exactly the eight sprites with their pack roots and animation sets (runt Thief, skirmisher Spear Goblin, slinger Torch Goblin, shaman Hex Shaman, hobgoblin Troll with windup and recover, vanguard Warrior, warden Archer, cleric Monk); every height `"native"`; no `kind` and no `row` anywhere (strips only, `file` per animation), no keying settings; the Troll's windup, recover and attack not looping. One more test validates the real manifest with `scale.validate_manifest` (skipped outside the venv). The manifest has no `kind` field any more, so "all strip" is tested as "no `kind`, no `row`, every animation names a `.png` file".
- **[Sonnet 5.5] 2**: README, new section "Native heights (a record)": table of the eight measured heights with the idle-frame ranges, dated 2026-09-29, the command that prints them (`tools/art/build.py`, its `scale:` table; `--pack-heights` for the whole pack). The order-rule sentence now follows from it: shortest profession cleric 67; runt 73 and skirmisher 70 above it (two warnings), slinger 67 not; hobgoblin 209 tallest.
- **[Sonnet 5.5] 3, 4 and [GPT-6-Sol] 4**: trailing blank lines of `artpipe/scale.py` removed; the long README bullet rewrapped. `git diff --check` prints nothing.
- **[Sonnet 5.5] 5**: the feet-row read of `verify` is now `build.feet_row(alpha)`, with a docstring naming the strip that needs the fallback (measured: `shaman/explosion/08`, 28 x 46 px, from the Hex Shaman's explosion strip, no row wide enough). Tests `FeetRow`: the lowest wide row (a thin tip is not the feet) and the fallback to the last row.
- **[Sonnet 5.5] 6**: `Redacted` substitutes `<redacted>`; its test updated.

Not accepted by the orchestrator, untouched: [GPT-6-Sol] 1, 2; notes 3, 7, 8.

Commands and output:
- `python3 tools/art/build.py --check`: green; table unchanged (hobgoblin 43 frames, cell 356x233); `PixiJS 8: 1 page(s), 205 frames, 30 animations parsed; every animation resolves to frames`.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 55 tests ... OK` (was 49). `python3 -m unittest tools/art/tests/test_build.py -k RealManifest` also passes under the system Python 3.11 without the venv.
- Fingerprints, identical to Resume 1 (the code changes touch no output), two builds equal:
  - `out/ sha256: 4f9d1953e24eef7cd5669e2f36b2f6831a1287e548b3584964d6b98a0f0b5ea5`
  - `out/ pixels+metadata sha256: cddc2d8fa21c7621165c638d79bfe7db127b6c875d8b845c8b115032a8578db5`
- `git diff --check`: no output.
- Pushed to #164; CI green on the new commit (discover, tooling, client, cairo jobs; indexer-node skipped).
