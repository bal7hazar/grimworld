# [Opus 5.5] CLI-03l — The HUD with the pack's bars, icons and avatars

Brief: `docs/briefs/CLI-03l-hud.md` (#343). Branch `hp/grimworld-cv/t-0096-cli-03l-hud-with-the-pack-s-art`,
from `main` at 3ec8426, `origin/main` merged at de7fec6. Audit: none (D-177).

## Summary

- A **status band** on the special paper sits above the map in the instance and both hubs: the
  adventurer's portrait (48 CSS px), the **health** bar (the pack's big wooden bar, its red fill)
  with `♥ 160 / 160`, the **energy** bar (the small bar, its fill recoloured blue by the build)
  with `⚡ 20 / 20`, and for a Vanguard the **adrenaline**: the pack's sword icon and the count of
  strikes. 72 CSS px tall at the default text size, at every size and ratio checked.
- The **desktop's sheet** shows the portrait at 96 CSS px above the name; the hub's **inspect
  dialog** shows the inspected adventurer's portrait at 40.
- **The pack's arrow and hand cursors** on desktop pointers; touch screens unchanged.
- **Without the HUD's art**, a plain band of the same boxes (CSS bars, a lettered disc); a
  `sprites.json` without the HUD's entries keeps the chrome's art and draws only the HUD plain.
- **Placeholders**: `ADVENTURER.health`, `.energy`, `.adrenaline`, marked "PLACEHOLDER until
  CLI-04"; `?hud=low|empty` shows other figures, presentation only.
- **Also in this lot** (review t-0095 of #344, note 2): the I-5 confirmation's Tab trap leaves
  `Tab` with Ctrl, Meta or Alt to the browser (`trapsTab`, unit-tested).

## The method as built

1. **The band** (`sandbox/loop/Hud.tsx`, the pure model `hud.ts`): a `section aria-label="Status"`
   with `data-hud="atlas" | "plain"`, a `Panel variant="dark"` row; the map's box below it
   (`data-map-box`) takes what is left (`flex: 1`), and the camera centres in it as on a resize. In
   the instance the control column (Leave, Travel back, debug) and the gate offer stay inside the
   map's box. The band is `memo`, its one prop a sheet read once per page (`bandSheet()`), and
   counts its renders in `data-hud-renders`.
2. **Bars** (`chrome/Chrome.tsx` `Bar`): the frame by `border-image` at one image px per device px,
   the trough as its padding (the entry's `content`), the fill an inner element of
   `fillWidth(trough device px, current, max) / dpr` CSS px, absent at 0, its image stretched along
   the trough (`100% 100%`, every column alike) with its rows one to one. The trough is measured by
   a `ResizeObserver` (no render during a walk). `role="meter"` with `aria-label`,
   `aria-valuemin`, `aria-valuemax`, `aria-valuenow` (clamped).
3. **Portraits** (`Portrait`): each portrait cut per display size (40, 48, 96 CSS px of its
   longer side × the ratio, whole device px), **smoothed** (`imageSmoothingQuality = "high"`) below
   one device px per art px, nearest-neighbour otherwise (`chrome/scale.ts` `portraitCut`), shown
   at one image px per device px.
4. **Loading** (`chrome/load.ts`): `HUD_ENTRIES` beside `CHROME_ENTRIES` in the same pass, each group
   with its own URLs: a missing HUD entry or a failed HUD cut gives `hud: null` (HUD plain, its URLs
   revoked) and keeps the chrome. Every cut runs concurrently (see _Deviations_, 4).
5. **Cursors**: `--gw-cursor-arrow` / `--gw-cursor-hand` = `image-set(url(1×) 1x, url(2×) 2x) <hx>
<hy>, auto|pointer`, under `@media (hover: hover) and (pointer: fine)` on the loop's root
   (`data-cursors`), enabled buttons and the map's canvas; a disabled button keeps the arrow. Hot
   spots in art px of the trimmed images: arrow (0, 0), hand (4, 0) → CSS (0, 0) and (2, 0).

## Manifest entries, portraits and the recolour (the build of 2026-10-03, VPS)

| Entry                   | Kind, fill        | Source (in words)                                               | Cell (art px) | Content          |
| ----------------------- | ----------------- | --------------------------------------------------------------- | ------------- | ---------------- |
| `bar_big`               | three, **round**  | Big bar, the frame                                              | 112 × 51      | [11, 11, 16, 11] |
| `bar_big_fill`          | still             | Big bar, the red fill                                           | 64 × 24       | —                |
| `bar_small`             | three, stretch    | Small bar, the frame                                            | 94 × 19       | [8, 10, 8, 10]   |
| `bar_small_fill_energy` | still, recoloured | Small bar fill, `#ff3e3e` → `#41919d`                           | 64 × 3        | —                |
| `icon_sword`            | still             | Icon 05, the sword                                              | 57 × 56       | —                |
| `portrait_vanguard`     | still             | Avatar 01, blue: the plumed great helm (the Warrior)            | 197 × 182     | —                |
| `portrait_warden`       | still             | Avatar 03, blue: the nasal helm with a small plume (the Archer) | 140 × 160     | —                |
| `portrait_cleric`       | still             | Avatar 04, blue: the curly-haired, tonsured head (the Monk)     | 144 × 155     | —                |
| `cursor_arrow`          | still             | Cursor 01, the arrow                                            | 22 × 30       | —                |
| `cursor_hand`           | still             | Cursor 02, the pointing hand                                    | 27 × 32       | —                |

- **Portraits chosen by eye** against the units' idle frames: the Warden is Avatar 03 (the
  Archer's helm) and the Cleric Avatar 04 (the Monk's tonsure), not the brief's 02 and 05, a swap
  within the blue row as the brief allows. The Arcanist draws the plain disc (Q-12).
- **The recolour**: the small fill has one colour, `#ff3e3e`, mapped to `#41919d`, the big blue
  button's face (the most frequent colour of its palette).
- **The bars' troughs**: the fill's rows are the trough's rows of the sheet (the fill is drawn where
  the pack places it): big bar rows 11–34 of the trimmed frame (24 rows, the fill's height), small
  bar rows 8–10 (3 rows).
- **The UI page**: `atlas-ui-0`, 2044 × 656 px on this branch (one page). Main's page size was not
  measured.

## Boxes per screen and size (CSS px, `[x, y, w, h]`, no `?hud=`; the same at every ratio)

| Screen, size       | Band               | Map (this branch)    | Map (`main`)        |
| ------------------ | ------------------ | -------------------- | ------------------- |
| town 1440 × 900    | [505, 53, 430, 72] | [505, 125, 430, 615] | [505, 53, 430, 686] |
| outpost 1440 × 900 | [505, 53, 430, 72] | [505, 125, 430, 665] | [505, 53, 430, 736] |
| zone 1440 × 900    | [505, 0, 430, 72]  | [505, 72, 430, 828]  | [505, 0, 430, 900]  |
| town 375 × 812     | [0, 53, 375, 72]   | [0, 125, 375, 527]   | [0, 53, 375, 598]   |
| outpost 375 × 812  | [0, 53, 375, 72]   | [0, 125, 375, 577]   | [0, 53, 375, 648]   |
| zone 375 × 812     | [0, 0, 375, 72]    | [0, 72, 375, 740]    | [0, 0, 375, 812]    |

In the hubs the map is 71 px shorter for a 72 px band: the service row's box differs by 1 px
between the two runs (within the brief's ± 1 px).

## Frame figures (AC-8, VPS, headless Chromium: software rendering, relative figures only)

The zone's 10-step walk × 3 per run, `main` (temporary worktree at 3ec8426) and this branch run
alternately, three pairs, `VERIFY_WALKS_ONLY=1`:

| Pair                | 1440 median (main → branch) | 1440 p95               | 375 median             | 375 p95                |
| ------------------- | --------------------------- | ---------------------- | ---------------------- | ---------------------- |
| 1                   | 0.585 → 0.585 ms (×1.000)   | 2.645 → 2.769 (×1.047) | 0.600 → 0.605 (×1.008) | 2.970 → 2.918 (×0.982) |
| 2                   | 0.610 → 0.580 (×0.951)      | 2.710 → 1.911 (×0.705) | 0.610 → 0.590 (×0.967) | 2.388 → 2.399 (×1.005) |
| 3                   | 0.630 → 0.610 (×0.968)      | 1.997 → 2.692 (×1.348) | 0.580 → 0.585 (×1.009) | 2.233 → 1.837 (×0.823) |
| Median of the three | 0.610 → 0.585 (×0.959)      | 2.645 → 2.692 (×1.018) | 0.600 → 0.590 (×0.983) | 2.388 → 2.399 (×1.005) |

Medians are within ±5 % in every pair. The 95th percentile moves with the run: `main` alone spans
1.997–2.710 ms at 1440, and pair 3 at 1440 exceeds +25 % (×1.348) while pair 2 is ×0.705. Over the
three pairs both bounds hold. **The band rendered 0 times during every walk** (`data-hud-renders`
before and after, every run).

## Shots (AC-10)

In the thread's library folder (`.herdr-project/grimworld-cv-t-0096/library/`, untracked, never
committed, attached or posted, D-73): `hud-{town,outpost,zone}-{1440x900,375x812}[-low].png` at
ratio 2, and `hud-band-375x812@{1,3}x.png`, `hud-band-1440x900@1x.png`. What they show:

- **Seams**: none visible between the big bar's ends and its repeated middle, nor along the small
  bar; the big bar's wood grain repeats whole (`round`).
- **The fill in the trough**: the red fill's light band and crimson rows lie inside the trough
  with no gap at the left end, its right edge square; at `?hud=low` the red stops at about a
  quarter and the blue at a quarter, the dark trough beyond.
- **The portrait's softness**: at 48 px (ratio 3: 144 device px for 197 art px) the knight's helm
  and plume read clearly, its ink outlines slightly softer than the chrome's nearest-neighbour
  edges; at 96 px in the desktop's sheet it is close to crisp at ratio 2.
- The figures sit beside the bars in white on the slate, never over a fill; the sword icon and its
  count at the right.

## Tests updated and why

- `tools/art/tests/test_build.py` `RealManifest.test_the_interface_elements`: the set of `[[ui]]`
  names now includes the HUD's ten entries (the test lists every entry); it also checks the
  recolour map.
- `client/app/src/sandbox/params.test.ts`: the `readParams` equality gains `hud: null` (a new
  field of `SandboxParams`).
- New: `chrome/scale.test.ts` (`fillWidth`, `portraitCut`), `chrome/load.test.ts` (_the HUD's
  images_), `sandbox/loop/hud.test.ts`, `sandbox/loop/InstanceScreen.test.ts` (`trapsTab`),
  `tools/art` _Interface_ tests (trim of a still, recolour, the refusals, a bar three-slice).
- No other test changed; `machine`, `hubDoors`, `walkFollowsPreview`, `wiring`, `session`,
  `placeholders` pass unmodified.

`git diff origin/main -- client/app/src/sandbox/placeholders.ts client/app/src/sandbox/loop/machine.ts client/app/src/sandbox/session.ts`: empty.

## Commands run

- `python3 tools/art/build.py` with the uncommitted `assets` symlink (removed afterwards).
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: 85 tests OK.
- `pnpm --filter @grimworld/app test` (455 passed, 1 skipped), `lint`, `typecheck`, `build`;
  `pnpm exec prettier --check client indexer`; `scripts/prepush.sh`: all checks passed (Cairo
  compile skipped by the build lock, as designed).
- `pnpm --filter @grimworld/app verify:hud` in four modes: atlas against `main`'s record, plain
  (`GRIMWORLD_ART_OUT` on an empty folder) against the atlas record, stale (the HUD's entries
  filtered out of `sprites.json`), and three alternating walk pairs: all passed but the frame bound
  of one pair (above).
- `verify-hubs.mjs` (twice), `verify-ground.mjs`, `verify-keys.mjs`: all checks passed (see
  _Deviations_, 4, for `verify-hubs`; one `verify-ground` run timed out once waiting for an
  attribute and passed on the next run).

## Acceptance criteria

- AC-1: `git diff origin/main --stat` lists only allowlisted files, plus `InstanceScreen.test.ts`
  (the unit test the orchestrator asked for the Tab-trap fix); the three rule files' diff is empty.
- AC-2: `tools/art` tests (synthetic sheets): trimmed still with its outset, a still without
  margin unchanged, recolour of every colour, the two refusals, a bar's uniform middle passing and
  a textured one refused; existing tests unmodified but the entry list.
- AC-3: `load.test.ts` _the HUD's images_: all present → both `atlas`; a HUD entry missing → chrome
  `atlas`, HUD `null`; a chrome entry missing → `null`; a HUD frame failing → only the HUD's URLs
  revoked; portraits at 1, 1.5, 2, 3 for 40, 48, 96, smoothing below 1:1; a ratio change revokes
  every old URL.
- AC-4: `scale.test.ts` _a bar's fill_ at 1, 1.5, 2, 3.
- AC-5: `hud.test.ts`; contrast row "HUD figures" white on `paper_dark` (6.89 : 1) in
  `contrast.test.ts`.
- AC-6 to AC-10: `verify:hud`, as above.
- AC-11: as above; CI on the pull request.
- AC-12: after the merge, on the public site.

## Deviations from the brief

1. **No `trim` key**: on `main`, `[[ui]]` stills are already trimmed of their transparent margin
   with the margin recorded as `outset` (CLI-03i's code; its test `test_a_still_keeps_its_pixels`
   checks it), so the brief's premise "stills untrimmed" did not hold; a `trim = false` default
   would have changed CLI-03i's icons. The HUD's stills are trimmed the same way.
2. **`bar_big` is `fill = "round"`**, not `stretch`: its middle piece is wood grain (31 % of its
   columns differ), which the edge rule refuses for a stretch. Repeated whole, with no visible seam.
3. **Portraits**: Warden 03, Cleric 04 (by eye, within the blue row), not 02 and 05.
4. **The loader cuts concurrently**: with the HUD's 18 more cuts in sequence, the chrome's art
   arrived about 700 ms after the map's atlas (`main`: about 240 ms, measured on the VPS), often
   after `verify-hubs`' first walk had ended; the chrome's arrival then moved the service row by
   1 px and drew one more frame, failing "data-frames stops growing once it stands" in 4 of 4
   walks (main fails it in 1 of 4 on this machine, the same race). Concurrent, the art arrives in
   40–180 ms, and `verify-hubs` passed twice.
5. **The cursors' CSS uses `!important`** inside its media query: the plain styles set `cursor`
   inline on buttons.
6. Commit order: the cursors' CSS went in with the chrome's components (one file).

## Escalations

None.

## Open questions

1. **For the orchestrator**: the room writes `data-atlas` only on a drawn frame; without the art,
   when the first frames come before its listener is attached, the attribute never appears.
   `verify-hud` waits for the canvas in its plain mode; the other checks' plain modes may meet the
   same race. A small lot could write it once on mount.
