<!-- Archived by the orchestrator of track CV, 2026-09-29. Design and quality audit of CLI-03a by [Opus 5.5], its third and last pass (PASS WITH FINDINGS; the one minor, the sharp pass's real fill, fixed in Resume 4 and checked by the orchestrator). Earlier passes are summarised in its status tables. -->

# [Opus 5.5] Audit — CLI-03a — design and quality (third pass)

Scope: what changed since my second pass (`954f6c3`): commit `e089d50` "fix(client): CLI-03a,
second audit passes of #135". That is 6 files, +241 −68: `render/renderer.ts`,
`render/renderer.test.ts`, `render/scaling.test.ts`, `sandbox/Sandbox.tsx`,
`test/fakeSurface.ts` and `dev/serveArt.test.ts`, all read in full through
`git diff 954f6c3..HEAD`. The PR body has no "Resume 3" section, and no REPORT.md is tracked on
the branch, so the commit is the source. Lenses: DESIGN and QUALITY (OPERATIONS.md §6).

## Verdict

**PASS WITH FINDINGS**

**Findings fixed:**
- Both minor findings of the second pass are fixed and tested.
- Note N-2 (the cost of the extra pass) is on the panel and tested.
- Note N-1 asked for a sentence in the pending decision document, which is outside the
  implementer's allowlist and this diff, so it stays with the orchestrator.

**Diff checks:** the diff moves no rule and adds no render loop.
- **Fall-back:** when the offscreen texture does not fit the GPU, `sharp` falls back to direct
  drawing. It is tested and shown on the panel.
- **Leaving `sharp`:** the texture is dropped at once, even while the page is hidden. This is
  tested.
- **Reuse:** the bucketed texture is reused during a pinch. A 60-frame pinch allocates at most 6
  textures (tested).

**New finding (minor):** the reused texture has a cost the panel does not show. A frame draws the
world into the **whole** allocated texture, not only the part it shows. The panel's "cost" figure
counts only the part shown. So in `sharp`, the GPU can fill up to about 2.5× more than the figure
says after a zoom. It does not block the merge, but it biases the owner's power comparison, which
is what the figure is for.

## Findings

### Second pass, rechecked

| # (2nd pass) | Status | Fix | Test that would fail without it |
|---|---|---|---|
| 1 minor: the offscreen texture remade on every zoom frame | **Fixed** | `renderer.ts` `allocation` / `ensureOffscreen`. The texture is allocated in buckets of 0.25 of the viewport's oversampling, reused while the frame fits and is at most two buckets too large. The screen sprite draws a `Texture` whose `frame` is the part used, over the same source. | `renderer.test.ts` *a pinch of 60 frames allocates a few textures, not one per frame* (≤ 6; the old code gave one per frame). *…a new texture past its bucket* (still a new texture on crossing the bucket and on resize, and the old one destroyed). |
| 2 minor: scratch folder inside the package | **Fixed** | `serveArt.test.ts:8` uses `mkdtempSync(join(tmpdir(), "art-test-"))`. | The folder is no longer under `client/app`. There is nothing to assert beyond the path. |
| N-1 note: `snap` at resolution 3 lifts the 2× cap | **Open, outside the diff** | It belongs in `docs/decisions/PENDING-cv-integer-scale.md`, which is not in this worktree or the implementer's allowlist. | — (for the orchestrator) |
| N-2 note: the cost of `sharp`'s pass | **Done** | `ZoomInfo.offscreen.cost` (texels of the used part over the canvas's pixels) and `allocatedCost`. The panel shows both (`Sandbox.tsx:117-124`). | `scaling.test.ts` *the offscreen's cost…*: 1.23 / 1.56 on 375 × 812 at DPR 2, 1.52 / 1.56 on 1440 × 900, and between 3.8 and 4 at s × r = 1.01 (n = 2) |

### New in this diff

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | `render/renderer.ts` `draw` → `surface.renderTo(this.world, offscreen.texture)`; `pixiSurface.ts` `renderTo` (`clear: true`, no frame); `zoomInfo().offscreen.cost` | The pass fills the **whole allocated texture**, not the part the frame uses. The world is placed for the used part (top-left, `plan.width × plan.height`), but the terrain continues past it and is drawn into the slack. The clear also covers the whole texture. The panel's `cost` ("texels drawn per frame over the canvas's pixels") counts only the used part. So it understates the fill per frame, which is what the owner's power comparison of `sharp` rests on. | At 375 × 812, DPR 2, near s × r = 1.01, the need is k ≈ 1.98, in bucket 2.0. Zoom in to s × r ≈ 1.59 (n = 2, k ≈ 1.26, bucket 1.5). The current texture (2.0) is ≤ bucket + 2 × 0.25 = 2.0, so it is **reused**. The panel then says `cost` ≈ 1.59, but each frame clears and rasterises about 2.0² = 4.0× the canvas wherever the location's terrain reaches (a 2 × 1-chunk cave is about 1900 art px wide, so it covers the slack). No test measures the filled area. The fake surface only records the target. | Limit the pass to the used part: a render with a frame or viewport of `plan.width × plan.height` if PixiJS 8's render options take one for a render target, or a scissor. The simpler alternative: label the panel's first figure "shown", and report `allocatedCost` as the per-frame fill. |
| N-1 | note | `renderer.ts` `offscreenPlan` / `draw` | Near the GPU limit, a pinch that crosses the limit switches between the offscreen pass and the fall-back. Each switch back allocates a texture, since the fall-back drops it. This only happens at the edge of the limit (a large window at resolution 2), so it costs nothing in the phone case. | `falls back…` test: limit 2048, 1440 × 900 falls back. Raising the limit brings the pass back with a new texture. | None needed. Mention it next to the fall-back line of the panel if the owner compares on a large desktop window. |

Other points checked, no finding:
- `mountStage` no longer clears and re-adds the stage on each frame. It returns early when the
  right child is already mounted.
- `dropOffscreen` destroys the sub-texture `view` with `destroy(false)`, which keeps the shared
  source, before destroying the texture with `destroy(true)`. No double free.
- A new `view` Texture is made when the used size changes, which happens every zoom frame. It is a
  CPU object on the same source, with no GPU allocation.
- The allocation never exceeds `floor(maxTextureSize / resolution)`, and the plan itself is
  checked against the limit before any allocation (`offscreenPlan` returns null).
- `bakeResolution` uses oversample 1 in the fall-back.
- `FakeSurface.maxTextureSize` became mutable for the tests only.

## Coverage

**Commands.** I ran no pnpm command in this pass. The previous two passes had test and typecheck
refused by the session's permission policy. CI is green on every check at `e089d50`, including
`client`.

**The diff, point by point:**
- Bucketed texture and its reuse: finding 2-1 is fixed (pinch test), with one new minor finding
  on the fill.
- `sharp`'s fall-back to direct drawing: `offscreenPlan` returns null when `ceil(viewport × k) ×
  resolution` exceeds the GPU limit. `draw` then drops the texture, mounts the world and draws
  directly. `zoomInfo.sharpFallback` is true, the panel says so, and it is tested both ways.
- Dropping the texture on leaving `sharp`: `setMode` drops it at once, and the test checks it with
  the page hidden and no frame drawn.
- The panel's cost figures: `cost` and `allocatedCost` are computed and tested. Finding 1 is about
  what `cost` claims to measure.

Nothing outside the diff rose to blocker or major. Mandate §6 (rules only in `placeholders.ts`)
is untouched by this diff: no file under `sandbox/` except the panel changed. I left out the art
pack entirely.
