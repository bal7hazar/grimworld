<!-- Archived by the orchestrator of track CV, 2026-09-29. Quality and design audit of ART-03 by [Sonnet 5.5], second and last pass: Approve (one cosmetic long README line left as a note). First pass: no test of the real manifest, native heights unrecorded, whitespace, an untested fallback, a leftover placeholder word. All fixed. -->

# [Sonnet 5.5] Audit — ART-03 — quality and design (second pass)

## Verdict

**Approve.** Findings 1–6 of the first pass are fixed, and 5 and 6 are also tested. The diff since my first pass (`796923a..27e8367`, 4 files under `tools/art`) adds nothing outside those fixes, except a record table in the README (see the table below). One cosmetic leftover: a README line that is too long again. Nothing blocks the merge.

I read the diff and did not run the tests or the build: `python3` is refused in this sandbox and there is no art pack.

## Findings of the first pass

| # | Status | Where | Check |
|---|---|---|---|
| 1 (real manifest untested) | Fixed and tested | `tests/test_build.py`, class `RealManifest` | It loads the committed `manifest.toml` with stdlib `tomllib`. It asserts exactly the eight sprites of the mapping, each with its `root` and animation set, and no duplicates. It asserts every `[height]` is `"native"`, no `kind`, no `row`, no sprite-level `file`, and none of the four keying settings left. It asserts the Troll's windup, recover and attack do not loop, and their file names. `test_the_manifest_is_sound` runs `validate_manifest` on it (needs NumPy). I checked the mapping against the manifest for the roots I could see (Archer `Units/Blue Units/Archer`, Monk `…/Monk`, Monk has `heal`). |
| 2 (README claim without a record) | Fixed | `README.md`, "Native heights (a record)" | The table records all eight native heights and idle ranges (Thief 73, Spear Goblin 70, Torch Goblin 67, Hex Shaman 70, Troll 209, Warrior 87, Archer 88, Monk 67). The order-rule paragraph now states the outcome from those numbers: two warnings (runt 73, skirmisher 70 over cleric 67), slinger not, boss rule holds. The figures are consistent with each other and with the test values (73, 209). I cannot verify them against the pack; the PR's build output is where they must match. |
| 3 (trailing blank lines) | Fixed | `artpipe/scale.py` | The two extra blank lines at the end are removed. |
| 4 (long README line) | Fixed there, but a new long line appeared | `README.md:75-80` re-wrapped. `README.md:127` is now 100+ characters. | See finding A below. |
| 5 (verify fallback untested, duplicated) | Fixed and tested | `build.py` `feet_row`, `tests/test_build.py` class `FeetRow` | The feet rule and its last-row fallback moved into one function, and `verify()` calls it. Two tests: the lowest wide row (a thin tip is ignored), and the fallback (a 28 × 46 frame with a 2 px spark gives 46). The docstring says which frame needs it (the Hex Shaman's last explosion frame). Still a second copy of the rule next to `clean.register`, but the comment names it and the duplication is now one function. |
| 6 (`<generated>` placeholder) | Fixed | `build.py` `Redacted`, test | It is now `<redacted>`, and the test asserts it. |
| 7, 8 | Notes, accepted | | No change needed. |

## New in this diff

| # | Severity | Location | Finding | Suggested fix |
|---|---|---|---|---|
| A | Low (cosmetic) | `tools/art/README.md:127` | The rewritten order-rule paragraph leaves a line over 100 characters ("…so the boss rule holds. `[order]` and `[height]` name only sprites of the manifest, with at least one"). Line 49 (`--resample` comment) is also long, from the first pass. | Re-wrap the paragraph. Optional. |
| B | Info | `README.md`, "Native heights (a record)" | The height table is a hand-copied record. No test ties it to the build, so it can go stale if the pack changes. The section says so ("they change only if the pack or a manifest line does"). | None required. |

Nothing else was added: the diff touches `README.md`, `scale.py` (blank lines only), `build.py` (`feet_row`, `<redacted>`) and the tests. A grep for the generated-sheet vocabulary and the forbidden name in `tools/art` still finds nothing. The first-pass acceptance mapping is unchanged (AC-4 still needs the build run with the pack, which I could not do).
