<!-- Archived by the orchestrator of track CV, 2026-09-29. The security and determinism audit of ART-02 by [GPT-6-Sol] (codex, read-only, reasoning high): the first pass (its own session), then the fourth and last pass of a second session that carried passes 2 to 4 (PASS). Passes 2 and 3 found: a direct launch from the venv skipping checks, an unreadable pyvenv.cfg accepted, Python versions beyond the hashed pins, an exemption applicable to a generated sheet; all fixed. -->

# [GPT-6-Sol] Audit — ART-02 — security and determinism

## Verdict

**FAIL.** The output paths are contained under `tools/art` for normal use, and the PNG writer is structurally sound. The Python bootstrap can loop or use unintended packages, however, and cross-machine equality of the pixel fingerprint remains unverified while the earlier sheet-cleaning stage still uses floating point arithmetic.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | major | [build.py](../../tools/art/build.py:29) | Re-execution trusts the first `python3.12` on `PATH` without checking it. | If that executable is actually Python 3.11, lines 61–65 re-execute it indefinitely. A PATH shim can also run an unintended program. | Probe the candidate’s version before `execv`; refuse a wrong version and guard against repeated re-execution. |
| 2 | major | [build.py](../../tools/art/build.py:67) | An existing venv is accepted when `PIL` and `numpy` merely import. | A same-version venv containing different package versions skips the pinned requirements entirely. `pyvenv.cfg` also does not validate the executable at `.venv/bin/python`. | Check the executable’s Python version and installed distribution versions against `requirements.txt`; rebuild on mismatch. |
| 3 | major | [clean.py](../../tools/art/artpipe/clean.py:39) | The complete pixel pipeline is not integer-only. | Generated-sheet keying uses `float32`, division, and `np.rint` at lines 43–67; component centroids use weighted `np.bincount` and floating point division at lines 129–146. A rounding difference can change a pixel or its assigned pose before integer resampling begins. The report has Mac results but no Linux comparison. | Compare the new **pixels+metadata** fingerprint on Linux against the reported Mac value. If it differs, make the affected cleanup operation deterministic before claiming cross-machine equality. |
| 4 | minor | [build.py](../../tools/art/build.py:75) | Bootstrap and `--check` can write outside `tools/art`. | `pip install` uses an enabled cache by default, under `~/Library/Caches/pip` on macOS or `~/.cache/pip` on Linux; `pnpm install` may likewise use its shared store. [pip documents these default cache paths](https://pip.pypa.io/en/stable/topics/caching/). The generated art itself is written under `tools/art/out`. | If containment is required, set cache and store paths under `tools/art`, or disable their caches. |
| 5 | minor | [build.py](../../tools/art/build.py:241) | `--pack-heights` prints private pack directory names. | Lines 245–253 discover directories in `assets` and print their relative names. Its output must not be copied into a public PR or log without review; the brief permits numbers, while barring pack material from GitHub. | Print approved labels or numeric measurements only in output intended for sharing. |
| 6 | note | [png.py](../../tools/art/artpipe/png.py:38) | Compression level 9 does not guarantee identical PNG bytes across zlib builds. | The PNG format permits different valid deflate streams for the same pixels. Python also distinguishes the zlib version loaded at runtime from its build version in its [zlib documentation](https://docs.python.org/3/library/zlib.html). The file fingerprint should be treated as an exact-byte comparison, **not** an expected cross-build invariant. | Use the pixel-and-metadata fingerprint as the cross-machine comparison; compare file hashes only when identical encoding has been demonstrated. |

## Coverage

- Reviewed `git diff origin/main...HEAD -- tools/art`, the ART-02 brief, `REPORT.md`, and the relevant tooling and D-73 rules. The branch is clean; the diff contains only `tools/art/**`. `out/` and `.venv/` are gitignored, no generated image or output is tracked, and the `assets` gitlink is unchanged.
- The explicit `shutil.rmtree` targets are `.venv` and `out`, both rooted under `tools/art`. A top-level symlink is not followed by `rmtree`; I found no ordinary path that deletes outside that directory. This is a mistake-prevention assessment, not a defense against deliberate actions by the same Unix user.
- The forbidden-name check remains at the end of a normal build. The early-return `--fingerprint` and `--pack-heights` modes skip it.
- [scale.py](../../tools/art/artpipe/scale.py:47) uses integer weights, sums, rounding, and fixed tie breaks. Manifest order drives packing; relevant glob results are sorted. I found no timestamp or locale input to generated artifacts. Float calculations remain in cleanup and in height-band and anchor calculations.
- The PNG writer uses valid RGBA8 IHDR fields, Paeth filter byte 4 on every row, modulo-256 residuals, CRCs over chunk type plus data, and `IHDR`–`IDAT`–`IEND` order. [fingerprint.py](../../tools/art/artpipe/fingerprint.py:19) sorts top-level filenames and canonicalizes JSON with sorted keys, compact separators, and ASCII escaping. Its content fingerprint covers PNG pixels and JSON; it intentionally excludes `preview.html`.
- This was a static, read-only audit. I did not run `build.py` or tests that create temporary files.

# [GPT-6-Sol] Audit — ART-02 — security and determinism (fourth pass)

## Verdict

**PASS.** All three third-pass findings are fixed. I found no blocker in the diff from `633f2f5` to `47dc380`.

## Findings

None.

## Coverage

The build now accepts only Python 3.12 or 3.13 and tests rejection of 3.14. Manifest validation rejects an exemption unless the sprite is both native and a pack drawing (`kind = "strip"`); the previous generated-runt scenario now fails. A new test asserts that the pip command includes `--require-hashes`.

Seven relevant read-only tests, the current manifest check, and `git diff --check` passed. I did not run `build.py` or the tests requiring temporary-directory writes. `gh pr view 134` could not connect, and `REPORT.md` was absent, so this pass relies on the new commit and its diff.