<!-- Archived by the orchestrator of track CV, 2026-09-29. Security, determinism and power audit of CLI-03a by [GPT-6-Sol] (codex, read-only), its third and last pass (PASS WITH FINDINGS; the one minor fixed in Resume 4). Pass 1 found: the dev art route following symlinks, unvalidated animation rates, an unbounded zoom parameter, a malformed escape; pass 2: an oversized sharp texture, a texture kept after leaving sharp. All fixed. -->

# [GPT-6-Sol] Audit — CLI-03a — security, determinism, power (third pass)

## Verdict

**PASS WITH FINDINGS** — both second-pass findings are fixed and have targeted tests. I found one minor error in the new panel cost figures.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | [renderer.ts](../../client/app/src/render/renderer.ts:381), [renderer.ts](../../client/app/src/render/renderer.ts:549) | The panel can underreport the texture *actually allocated* after bucket reuse. | `zoomInfo()` reports a freshly calculated bucket, while `ensureOffscreen()` may retain a larger one. At 390 × 844, resolution 2, moving from oversampling about 1.70 to 1.10 can retain a 683 × 1477 texture while the panel reports 488 × 1055: about 3.06× versus 1.56× the canvas pixels. | When a texture exists, report its actual dimensions and cost. Test the panel figures after a zoom that reuses a larger bucket. |

## Coverage

- **Oversized texture:** [renderer.ts](../../client/app/src/render/renderer.ts:524) now rejects an offscreen plan that exceeds the GPU limit and draws directly. The new [test](../../client/app/src/render/renderer.test.ts:349) covers the reported 1440 × 900, resolution 2, limit 2048 case.
- **Texture lifecycle:** Leaving `sharp` destroys the texture immediately, including while hidden; a [test](../../client/app/src/render/renderer.test.ts:368) covers that path. The bucket and cropped-view tests cover reuse through a pinch. Offscreen work still occurs only when the scheduler draws a frame.
- **Other changed code:** The art-server change moves test scratch files to the system temporary directory. I found no new security or rule-determinism issue in the Resume 3 diff.

`git diff --check` passed. I reviewed the tests but could not run them: this worktree has no installed dependencies. The dev server was not started.