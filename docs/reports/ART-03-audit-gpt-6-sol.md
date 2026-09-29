<!-- Archived by the orchestrator of track CV, 2026-09-29. Security and determinism audit of ART-03 by [GPT-6-Sol], single pass. Its blocker (a forbidden token in seven tracked files) was not accepted: an identifier of client/app's renderer ('actors' followed by 'Layer') is a false positive of a case-insensitive substring, and the design documents citing the inspiration are the project manager's, told to the project manager. Its note 4 (a trailing blank line) was fixed and checked by the orchestrator (git diff --check). -->

# [GPT-6-Sol] Audit — ART-03 — security and determinism

## Verdict

**FAIL** against the stated rule that the prohibited name appear nowhere in Git. The ART-03 diff introduces no occurrence, but seven pre-existing tracked files contain the exact token used by the build’s redaction guard.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | blocker | [build.py](../../tools/art/build.py:238); seven tracked files outside its scan | The guard checks `tools/art` and `CREDITS.md`, while the prohibited token remains in Git elsewhere. | Repository scan found matches in `CONTEXT.md`, `client/app/src/render/renderer.ts`, and five files under `docs/`. All seven are unchanged from `origin/main`; the ART-03 diff has zero matches. | Remove or redact those references in a separately authorized change, then verify the tracked tree. |
| 2 | minor | [build.py](../../tools/art/build.py:368) | `--pack-heights` prints private pack directory names from broad globs. | Publicly captured command output can disclose unit directories beyond the approved sprite mapping. This behavior predates ART-03. | Print approved labels and measurements without pack paths. |
| 3 | note | [atlas.py](../../tools/art/artpipe/atlas.py:54) | Builds are deterministic for a fixed manifest, but atlas layout depends on sprite order in that manifest. | `pack` processes sprites sequentially; reordering entries can change pages and fingerprints. | Sort sprites before packing if permutation independence is required. |
| 4 | note | [scale.py](../../tools/art/artpipe/scale.py:200) | `git diff --check` fails on a new blank line at EOF. | The command exits 2. | Remove the extra blank line. |

## Coverage

All eight manifest sprites use native strips. The new shaman and boss animations flow into atlas PNGs and JSON, so both fingerprints cover them. Pixel operations remain integer based; the printed scale factor uses floating point only for display. Python selection, venv checks, and hashed requirements are unchanged. No image or `out/` file is tracked.

Twelve selected read-only tests passed. The private strips are absent from this worktree, so I could not run the build, PixiJS check, or compare actual fingerprints.