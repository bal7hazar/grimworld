# [Opus 5.5] CLI-03i — The client's chrome from the pack's UI elements, every screen at once

Brief: `docs/briefs/CLI-03i-client-chrome.md` (PR #337). Model read from the session: Opus 5.5,
as the brief names. Audit: none (D-177). Owner's eye: on the public site after the merge.

## Summary

- `tools/art` has a role `ui` and a `[[ui]]` manifest table (`artpipe/ui.py`): nine-slices,
  three-slices and stills of the pack's `UI Elements`, composed contiguous from the described
  lattice, the transparent margin trimmed (recorded as `outset`, one trim shared by a regular and a
  pressed sheet), packed untrimmed and without extrusion on their own page `atlas-ui-0`, listed in
  `sprites.json` with `group: "ui"` and a `ui` field per element. The build checks the layout, the
  pressed sheet, the drop, the insets and the uniformity of stretched edges, and reports each
  element's centre colour.
- The client: `readSpritesIndex` validates `group` and `ui`; `loadAtlas` never loads a `ui` page.
  `client/app/src/chrome/` cuts the UI page into object URLs at 0.5 CSS px per art px ×
  devicePixelRatio (nearest-neighbour), publishes them as custom properties, re-cuts on a ratio
  change and revokes the old URLs; `Panel`, `Button`, `IconButton`, `Ribbon`, `Icon`, `Text`;
  `chrome.css` scoped to `[data-chrome="atlas"]`; without the art `data-chrome="plain"` and today's
  look.
- Every screen wears the chrome (table below). `verify:chrome` checks every screen at 375 × 812 and
  1440 × 900 at ratios 1, 2 and 3, against `main`, without the art, and in forced colours.
- PLAN.md: rows CLI-03i (doing) and CLI-03j (rem text sizes, todo; the project manager's addition of
  2026-10-03, not done in this lot).

## The method as built

Option D of *The method* §1. `ChromeProvider` (the loop's root) runs a `ChromeSession`: fetch
`sprites.json`, refuse it or lack any of the 13 entries the stylesheet uses → plain; else fetch
the `ui` page's JSON and PNG once, cut each state's frame into a canvas of
`round(frame × 0.5 × dpr)` device px with smoothing off, `toBlob`, `URL.createObjectURL`. The custom
properties per element: the image (and `-pressed`), `-slice` (image px, whole), `-width`
(`slice / dpr` CSS px: one image pixel per device pixel), `-pad` (content insets on whole device
px), `-w`, `-h`, `-drop`, `-min-w`, `-min-h` (the slices' sums, so no box is ever smaller than its
unscaled border), and `--gw-px` (one device pixel, for the text outline). A
`matchMedia("(resolution: <dpr>dppx)")` change re-cuts; the replaced URLs are revoked, and a load
overtaken by a newer one is revoked unseen.

The plain look: each component takes its call site's former inline style as `plain` and renders it
whole without the art (so `main`'s look is reproduced by the same style objects of
`sandbox/loop/styles.ts`, not by copies in a stylesheet); with the art it keeps only the layout keys
of it and the stylesheet draws the rest. The brief said "the stylesheet's plain rules reproduce
today's look"; the outcome is the same, measured by AC-8.

Text (§5): **large white text** was built: button and big-ribbon labels bold 18.67 px (14 pt) white
with a one-device-pixel dark outline. Every label fits at 375 px, the longest ("Enchanter",
"Alchemist" in the service row) included: `scrollWidth ≤ clientWidth` on every button and plate at
every size and ratio. Ink 15 px on papers, scroll and the yellow ribbon; white on the special paper.

## Manifest entries and the UI page (the build's report, 2026-10-03)

UI page `atlas-ui-0`: 1644 × 656 px (world pages unchanged in role: `atlas-0` 2048 × 2020,
`atlas-1` 532 × 264).

| Entry | Kind | Fill | Trimmed size (art px) | Outset t/r/b/l | Slice t/r/b/l | Centre colour |
|---|---|---|---|---|---|---|
| paper | nine | round | 168 × 153 | 20/12/19/12 | 47/55/48/55 | `#eee1c6` |
| paper_dark | nine | round | 174 × 151 | 20/9/21/9 | 44/55/43/55 | `#525b66` |
| scroll | nine | round | 248 × 243 | 60/44/17/28 | 68/84/111/100 | `#dcdca5` |
| wood | nine | round | 232 × 252 | 43/44/25/44 | 42/30/58/30 | `#9b6253` |
| button_blue (+pressed) | nine | stretch | 164 × 160 | 17/14/15/14 | 34/20/20/18 | `#41919d` / `#4a6982` |
| button_red (+pressed) | nine | stretch | 164 × 160 | 17/14/15/14 | 34/20/20/18 | `#f65555` / `#ba4954` |
| ribbon_big_blue | three | round | 259 × 103 | 20/31/5/30 | 0/97/0/98 | `#41919d` |
| ribbon_big_red | three | round | 259 × 103 | 20/31/5/30 | 0/97/0/98 | `#be6e61` |
| ribbon_small_yellow | three | stretch | 188 × 60 | 4/2/0/2 | 0/42/0/42 | `#bbb552` |
| round_blue (+pressed) | still | — | 104 × 96 | 17/12/15/12 | — | `#41919d` / `#4a6982` |
| square_blue (+pressed) | still | — | 100 × 96 | 17/14/15/14 | — | (cut, not used yet) |
| icon_back, icon_close, icon_gold | still | — | 54 × 50, 51 × 55, 55 × 52 | — | — | — |

Stretched edges measured by the build (worst share of a row or column differing from its band):
buttons 0.15, small ribbon 0.12; `settings.ui_edge = 0.15`. Drop 11 art px checked for the four
pressed elements.

## Contrast as built (AC-5, `chrome/contrast.test.ts`)

| Component | Surface (state) | Text | Ratio | Needed |
|---|---|---|---|---|
| Button action | `#41919d` / `#4a6982` | white, large | 3.64 / 5.78 | 3 |
| Button commit | `#f65555` / `#ba4954` | white, large | 3.31 / 5.04 | 3 |
| Button quiet, Panel paper | `#eee1c6` | ink `#111` | 14.59 | 4.5 |
| Panel scroll | `#dcdca5` | ink | 13.33 | 4.5 |
| Panel dark | `#525b66` | white | 6.89 | 4.5 |
| Ribbon big blue / red | `#41919d` / `#be6e61` | white, large | 3.64 / 3.75 | 3 |
| Ribbon small yellow | `#bbb552` | ink | 8.85 | 4.5 |
| IconButton | `#41919d` / `#4a6982` | white glyph, large | 3.64 / 5.78 | 3 |

Captions and muted lines on paper and scroll are `#5b4636` (6.99 : 1 on `#eee1c6`); on the dark
paper white bold captions and `#e3e3e8` lines (the yellow accent measures 4.34 : 1 there, as the
brief found).

## Which screen got what

| Screen or control | With the art |
|---|---|
| Hub header | Name on a big blue ribbon; gold as the coin icon and the number |
| Place names | Small yellow ribbons, ink; still placed by the camera, no tap |
| Inspect dialog | Scroll panel; ✕ as the round blue button with the red cross |
| Service row | On the wooden board (its thick frame drawn partly over the map's lower edge and below the screen by `border-image-outset`, so the row keeps `main`'s height); services blue, the Gate red with ▸ |
| Service stub | Ribbon header with the round back button (orange arrow); the card on paper |
| Gate screen | Each gate a paper card with a blue Leave ▸; the sheet on paper; "Before leaving" on the special paper |
| Entry moment | Title and destination on the scroll; Skip a paper (quiet) button |
| Instance | Leave and Travel back blue (Leave greyed when disabled); the gate offer blue |
| Confirmation (I-5) | Scroll panel on the scrim; Stay quiet, Leave / Travel back red |
| Closing report | Blue ribbon (returned) or red (defeated); four paper cards; a full-width blue button |
| Desktop side panels | Special paper, white bold captions |
| Recentre ◎, walk counter | Round blue button with the glyph; the counter a quiet button, its "stopped" line a paper-coloured tag (CSS, the paper's art is too large for it) |
| Debug toggle and panel | Non-pack on purpose (red, dashed); the toggle 44 px tall |

## Files changed

- `tools/art/artpipe/ui.py` (new), `artpipe/atlas.py` (page prefix, group, no extrusion for `ui`),
  `build.py` (`[[ui]]` validation, the UI page, checks, report lines), `manifest.toml` (the 14
  entries, `settings.ui_edge`), `tests/test_build.py` (class `Interface`, one test of the real
  manifest), `README.md` (*UI elements*, *What it produces*).
- `client/app/src/render/sprites.ts` (`group`, `ui`, validation), `render/atlas.ts` (world pages
  only), `render/sprites.ui.test.ts` (new).
- `client/app/src/chrome/` (new): `scale.ts`, `load.ts`, `Chrome.tsx`, `chrome.css`, `contrast.ts`,
  and `scale.test.ts`, `load.test.ts`, `contrast.test.ts`.
- `client/app/src/sandbox/loop/HubScreen.tsx`, `InstanceScreen.tsx`, `screens.tsx`, `Loop.tsx`;
  `sandbox/Sandbox.tsx` (recentre, walk counter, debug toggle and panel frame).
- `client/app/verify-chrome.mjs` (new), `client/app/package.json` (`verify:chrome`).
- `PLAN.md` (rows CLI-03i, CLI-03j), this report.

## Commands run

- `python3 tools/art/build.py` (with the uncommitted `assets` symlink to `/home/claude/projects/assets`):
  builds; the UI elements' lines as in the table above.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 80 tests … OK`.
- `pnpm --filter @grimworld/app test`: `Tests 369 passed | 1 skipped (370)`; `lint`, `typecheck`:
  clean; `pnpm exec prettier --check client indexer`: clean.
- `pnpm --filter @grimworld/app verify:chrome` with `VERIFY_COMPARE` = `main`'s boxes: `ALL CHECKS
  PASSED` (6 passes × 9 screens, 28 focus stops and 6 presses per pass, forced colours: hub 11
  controls, confirmation 7).
- The same on `origin/main` (bad10a2) in a temporary worktree under the thread's scratch folder
  (`VERIFY_MAIN=1`, `VERIFY_ROOT`), removed by its exact path afterwards: boxes recorded.
- With `GRIMWORLD_ART_OUT` on an empty folder, `VERIFY_PLAIN=1`: `ALL CHECKS PASSED`.
- `scripts/prepush.sh`: see the pull request's push.

## Acceptance criteria

- AC-1: `git diff origin/main --stat` lists only allowlisted files plus PLAN.md (task Q6) and this
  report; `git diff origin/main -- client/app/src/sandbox/placeholders.ts
  client/app/src/sandbox/loop/machine.ts` is empty. `machine`, `hubDoors`, `walkFollowsPreview`,
  `wiring`, `session`, `placeholders` tests pass unmodified.
- AC-2: `test_build.Interface`: lattice composed with margins as outset; a three-slice row from a
  multi-row sheet; a pressed sheet of another layout (pixel in an empty cell; other size) refused;
  wrong drop, inset outside, non-uniform stretched edge refused; `ui` frames only on `ui` pages
  (and `verify` refuses a `ui` frame on a world page); existing tests unmodified.
- AC-3: `render/sprites.ui.test.ts`: a valid `ui` entry and `group` accepted, 17 malformed cases
  refused; `loadAtlas` on fake loaders asks only `sprites.json` and `atlas-0.json`.
- AC-4: `chrome/scale.test.ts` and `load.test.ts`: at 1, 1.25, 1.5, 2, 2.625 and 3 the cut size is
  the frame × `cutScale`, slices whole device px, `border-image-width × dpr = slice`; a ratio
  change re-cuts and revokes the old URLs; an overtaken load is revoked.
- AC-5: `chrome/contrast.test.ts` (table above; the stylesheet's colours read back from
  `chrome.css`).
- AC-6: `verify:chrome`: on every screen `data-chrome="atlas"` and `data-chrome-dpr` = the ratio;
  smallest button 44 px tall (the service row) and 48 px wide (◎), at both sizes; no horizontal
  overflow; no clipped label; Tab reaches every button with the 3 px outline; a pointer-down swaps
  `border-image-source` and moves the label by the drop (within Chromium's 1/64 px layout unit at
  3×); no page error.
- AC-7: the map's box at every screen and size is `main`'s or 1 px taller (town 599 vs 598 at 375,
  687 vs 686 at 1440; outpost 649 vs 648, 737 vs 736); no button left the viewport or overlaps
  another. Differences (375 × 812 at 2×; the same at the other ratios and at 1440): the service row
  1 px shorter (160 vs 161, 110 vs 111), its buttons 111 px wide instead of 115.7 and 1 px lower
  (the board's side padding); the back 52 × 48 instead of 72 × 44 (the round button); ◎ 52 × 48
  instead of 48 × 48; Leave by gate 84 wide instead of 77; Skip and Stay 47.5 tall instead of 44
  (the paper's slices); Leave 78 and Travel back 130 wide instead of 71 and 107 (large text); the
  debug toggle 58 × 44 instead of 52 × 25. All listed by the run.
- AC-8: without the art every screen is `data-chrome="plain"` with `main`'s boxes within 1 px,
  except the debug toggle (52 × 25 → 58 × 44: the brief's §6 size change), no page error.
- AC-9: forced colours: every control on the hub (11) and the confirmation (7) has a solid border,
  no border image, and text distinct from its background.
- AC-10: shots of every screen at both sizes at ratio 2 and the town at 1 and 3, untracked, in the
  thread's library folder (`shots/`). Looked at: crisp pixel edges at 1×, 2× and 3×, no blur; no
  seam between corners and edges on buttons and ribbons; the papers' grain repeats evenly (it
  streaked visibly when stretched in a first run, hence `round`); no clipped text. Seen and left:
  the paper "quiet" buttons (Skip, Stay, the walk counter) show the paper's fold creases as two
  faint vertical seams; the red button's rim is yellow in the art; the place names may sit over the
  debug toggle, as before.
- AC-11: commands above; CI on the pull request.
- AC-12: after the merge, on the public site.

## Deviations from the brief

1. Papers `fill = "round"` (the brief: stretch): stretched, the papers' grain made long streaks on
   the desktop panels and tall cards; repeated, it reads as paper. Reversible in the manifest.
2. Every `ui` entry is trimmed, stills included (the brief: stills untrimmed): the small buttons'
   regular and pressed images then share one trim (104 × 96 → 52 × 48 CSS px, a tap target with no
   transparent margin). Icons are trimmed the same way.
3. The plain look comes from each call site's former inline style (`plain` prop), not from plain
   rules in `chrome.css` (see *The method as built*).
4. The service row's board draws its frame partly outside the row (`border-image-outset` 13 px up,
   21 px down): its frame at 0.5 scale (21 + 29 CSS px) would otherwise have shrunk the map (AC-7).
5. The walk's "stopped" line is a paper-coloured CSS tag, not the paper's art (whose slices make it
   at least 48 px tall).
6. `square_blue` is cut (the brief's list) but not used by any component yet.

## Escalations

None. `PLAN.md` is outside the brief's allowlist and was edited by the task's Q6 and the project
manager's addition (CLI-03j row).

## Open questions

1. For the orchestrator: the paper quiet buttons' fold creases (AC-10) — keep, or a later lot gives
   the quiet buttons a flatter art (the tiny buttons, a slate plate).
2. CLI-03j (rem text sizes) starts after this merges, as the project manager asked.
