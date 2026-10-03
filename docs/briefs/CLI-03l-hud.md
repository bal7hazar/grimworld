# CLI-03l — The HUD with the pack's bars, icons and avatars, on zones and hubs

**Status: brief, ready to start from `main`** (after CLI-03i, #338, and CLI-03j, #339). It changes the
loop's screens, the chrome (`client/app/src/chrome/`) and `tools/art`; it does not touch the map's
renderer.

Written for the orchestrator of track CV on 2026-10-03, at the project manager's request of the same
day: CLI-03i dressed the chrome with the pack's (*Tiny Swords*) UI elements and left out, by
decision, the bars, state icons, avatars, sword plates and cursors (its brief's open question 4).
The project manager brings the HUD forward now: the pack's bars, the adventurer's avatar, on zones
and hubs; **desktop first** (the owner tests on desktop, D-199), the mobile-first layout kept.

## Agent

Profile: `impl-opus`. Presentation with pixel judgement (three-slices with a fill at device pixel
ratios, a portrait reduced far below its art size, contrast) plus a contained pipeline change in
`tools/art`, both with tests.

Machine: **the VPS**. The lot commits no pin, gas table or fingerprint. The pack is at
`/home/claude/projects/assets`: link it into the worktree as `assets` by an **uncommitted** symlink
for `tools/art/build.py`, and remove the link afterwards, as CLI-03g and CLI-03i did. The browser
check runs here in headless Chromium.

Branch: a new branch from `main`. One pull request.

## Goal

After this lot:

1. **A status band** (design/11 *Screen in an instance*, the status zone) sits above the map in the
   instance **and** in both hubs: the adventurer's portrait, a **health** bar, an **energy** bar,
   and, for a Vanguard, the **adrenaline** count, each with its figures as text.
2. The bars are the pack's **wooden bar frames with their fill**, the portrait is one of the pack's
   **human avatars**, cut by the client at the device's scale like the rest of the chrome.
3. **The desktop** shows the portrait large at the top of the left panel's sheet; the hub's inspect
   dialog shows the inspected adventurer's portrait.
4. **On desktop, the pack's cursors**: the arrow on the page, the pointing hand on what takes a
   click (*Cursors*).
5. **Without the art, a plain HUD** with the same boxes (CSS bars, a lettered disc for the
   portrait), as CLI-03i's fallback does for the chrome.
6. **Presentation only**: the HUD **reads** fixed data marked as placeholders; no rule, no intent,
   no machine state, no chain change; the frame budget of CLI-03g kept.

## Context

- **design/11** *Rules*: I-1 (portrait, one thumb; desktop is the same interface with more room),
  I-4 (everything the rules use is visible), I-6 (tap targets), I-7 (the screen is still between two
  actions: no decorative animation). *Screen in an instance*: the status zone (~10 % of the height)
  holds "health, energy, adrenaline for Vanguards, conditions and effects with their remaining
  ticks"; the target zone and the actions zone below the room. *Desktop*: the portrait column in
  the centre, the left panel for the character sheet and build. *Accessibility*: colour never the
  only carrier of a meaning; text scales with the system (CLI-03j: sizes in `rem`).
- **design/03**: health `100 + 20 × (level − 1)`; energy by profession (Vanguard 20); adrenaline is
  counted in strikes, per skill (Cleave costs 4), with **no maximum** of its own (design/04 *Energy
  and adrenaline*). The client computes none of it (*Placeholders*).
- **design/10** *What the pack contains*: `UI Elements/` holds "banners, bars, buttons, icons,
  papers, avatars" for the interface; the client ships the art packed into atlases, never the
  pack's files (D-73). The Arcanist has no sprite in the pack (Q-12).
- **CLI-03i** (`docs/briefs/CLI-03i-client-chrome.md`, merged as #338): the `ui` role and `[[ui]]`
  entries in `tools/art`, the UI page `atlas-ui-N` that the map never loads, the client's cut at
  `CHROME_SCALE = 0.5` CSS px per art px × the device pixel ratio, nearest-neighbour, laid out with
  `border-image` at one image pixel per device pixel; `data-chrome="atlas" | "plain"` on the loop's
  root; the contrast table checked by `chrome/contrast.test.ts`. This lot **extends** that method;
  it does not reopen it.
- **D-73 and the public site** (owner, 2026-10-02): the built atlas pages and `sprites.json` are
  served at https://grimworld.bal7hazar.com; never the pack's raw files; nothing of the pack in a
  commit, a pull request, an issue, a comment or a report.
- **The mandate** `docs/briefs/ORCH-client-visual.md`: §4 (D-73), §6 (no rule in `client/app`
  outside `sandbox/placeholders.ts`).
- **The owner's eye no longer blocks** (owner's session, 2026-10-03): the orchestrator decides the
  provisional look, it is merged, the owner sees it on the public site; a remark comes back as a
  change request.
- **Phone work is suspended** (owner, 2026-10-02): mobile-first, checked in the browser at
  375 × 812 and 1440 × 900, nothing on a device.

### What main has

| Part | Where | Today |
|---|---|---|
| The instance | `sandbox/loop/InstanceScreen.tsx` | `RoomSandbox` fills the screen; over it, at the top right, a column of Leave / Travel back / "debug: defeat now"; the gate offer at the bottom; the I-5 confirmation on a scrim. **No status zone**: no health, energy or portrait anywhere |
| The hub | `sandbox/loop/HubScreen.tsx` | A header (the hub's name on a big blue ribbon, the gold coin and figure), the map (`RoomSandbox` in a `flex: 1` box), place labels, the inspect dialog (a scroll with the name, profession, level and ✕), the service row on the wooden board |
| The sheet | `sandbox/loop/screens.tsx` `SheetSummary`; `sandbox/fixtures/hubs.ts` `ADVENTURER` | Name Wren, Vanguard, level 4, the bar of 8 skills, attributes, belt; shown on the Gate screen and in the desktop's left panel. **No health, energy or adrenaline field** |
| The desktop | `sandbox/loop/Loop.tsx` | At ≥ 700 px: two `paper_dark` side panels (280 px) around the 430 px column; the left holds `SheetSummary` and the last hub visited |
| The overlay | `sandbox/Sandbox.tsx` | Inside `RoomSandbox`: the debug toggle top-left (8, 8), the debug panel under it, the walk counter bottom-centre, the recentre ◎ bottom-right |
| The chrome | `chrome/load.ts` (`CHROME_ENTRIES`, the cut), `chrome/scale.ts` (`CHROME_SCALE`, `cutScale`, `toDevicePx`, `sliceLengths`), `chrome/Chrome.tsx` (`ChromeProvider`, `Panel`, `Button`, `IconButton`, `Ribbon`, `Icon`, `Text`), `chrome/chrome.css`, `chrome/contrast.ts` | `loadChrome` refuses the whole chrome (plain look) when **any** entry of `CHROME_ENTRIES` is missing from `sprites.json` |
| `tools/art` | `manifest.toml` `[[ui]]` (14 entries: papers, scroll, wood, big buttons, ribbons, small buttons, three icons), `artpipe/ui.py` | Kinds `nine`, `three`, `still`; stills **untrimmed** at their native size; no recolouring |
| Game state | `sandbox/session.ts`, `sandbox/wiring.ts`, `render/view.ts` | Actors carry side, profession or caste, tile, facing, mark. **No health, energy, adrenaline or condition** exists in the client's state: nothing takes damage in the sandbox (CLI-02/CLI-04 bring the rules) |

### The pack's elements for the HUD (described in words, nothing copied)

Read with Pillow on `/home/claude/projects/assets/UI Elements/UI Elements/`. Sizes in the pack's
pixels ("art px"). Every sheet below has no semi-transparent pixel unless said.

| Folder, file | What it is | Layout and figures |
|---|---|---|
| `Bars/BigBar_Base` | A **wooden bar frame**: light wood (`#af7960`, `#dfa166`) outlined in the pack's ink `#161c2e`, an inner trough of darker wood (`#82564e`, `#5a4643`) | 320 × 64, a **three-slice on the 64 px lattice**: left end in cell 0 (visible x 40–64), middle in cell 128–192, right end in cell 256 (visible x 0–24 of the cell); visible rows 9–60. The trough runs on rows 21–43, between ink lines at rows 18–20 and 44–45; on row 32 it opens at x 51 (left end) and closes at x 268 (right end). The middle piece is uniform along x |
| `Bars/BigBar_Fill` | The **fill**: a red strip with a light band (`#ffa762`) over red `#ff3e3e` over crimson `#b22249` | 64 × 64, opaque on rows 20–43 only (24 rows), **every column identical**: it stretches horizontally with no visible change. Its rows match the base's trough |
| `Bars/SmallBar_Base` | A thinner frame: cream (`#efe1ab`, `#c8a876`) and ink, a dark trough (`#5b4848`, `#383032`) | 320 × 64, same lattice; visible rows 22–40 (19 rows); trough on rows 30–35 |
| `Bars/SmallBar_Fill` | A red line `#ff3e3e` | 64 × 64, rows 30–32 only, one colour |
| `Icons/Icon_01`…`12` | Twelve 64 px icons: a wooden mallet, a log, a gold coin (cut by CLI-03i), a slab of meat, **a sword** (`Icon_05`, a pale blade with a blue hilt), a shield, a green gem, the back arrow and the red cross (cut by CLI-03i), a gear, an info sign, a music note | 64 × 64, opaque, outlined in ink |
| `Icons/{4,5,ActionPoint,Gold,Score}_{Regular,Pressed,Disable}` | Small **state glyphs** (the digits 4 and 5, an action point, a pile of coins, a crown) drawn in ink, **semi-transparent at the edges**, made to sit on a button's face; Pressed is the same glyph 4 px lower; Disable a faded copy | 64 × 64, visible about 21–30 × 27 px |
| `Human Avatars/Avatars_01`…`25` | **Portraits**, head and shoulders on a coloured diamond backdrop. Five rows of five: the **rows are the five faction colours** in the pack's order (blue 01–05, red 06–10, yellow 11–15, purple 16–20, black 21–25); the **columns are five figures**: a knight in a plumed great helm (01), a soldier in a rounded helmet (02), a soldier in a tall nasal helm with a small plume (03), a bare-headed figure with curly hair (04), a long-haired figure with closed eyes (05) | 256 × 256 each, visible about 140–200 × 145–185 (Avatars_01: x 22–219, y 31–213), 11–13 colours, opaque |
| `Cursors/Cursor_01`…`04` | An **arrow** (01), a **pointing hand** (02), a "no" sign: a grey ring with a bar (03), and four **corner brackets** for a selection (04) | 01–03: 64 × 64, visible about 22–32 × 30–36; 04: 128 × 128. White and pale blue over ink |
| `Swords/Swords` | Sword-shaped plates, five colours (CLI-03i) | Not used here (*Scope*) |

## Scope and non-goals

- **In**:
  1. `tools/art`: new `[[ui]]` entries for the bars, the sword icon, three portraits and two
     cursors; **trimmed stills** and a **recoloured fill** in `artpipe/ui.py` (*The tools/art
     changes*).
  2. The chrome: the HUD's entries loaded **optionally** (a missing one drops only the HUD to its
     plain look), a per-entry display scale with a smoothed reduction for the portraits, and two
     components, `Bar` and `Portrait`.
  3. `sandbox/loop/Hud.tsx` (new): the status band, used by the instance and both hubs.
  4. The portrait in the desktop's sheet (`SheetSummary`) and in the hub's inspect dialog.
  5. The pack's arrow and hand cursors on desktop pointers.
  6. Placeholder fields on the fixed `ADVENTURER` (health, energy, adrenaline), marked, and a
     presentation parameter `?hud=` to show other figures for the browser check.
  7. A browser check (`verify:hud`) and unit tests.
- **Out (non-goals)**, with where each goes:
  - Any rule: the client computes no health, energy, regeneration or adrenaline; nothing takes
    damage or spends energy; `sandbox/placeholders.ts`, `machine.ts`, `client/sim`, the chain are
    unchanged. The "debug: defeat now" control keeps doing what it does (the bar does not empty
    first: it is a debug shortcut, not damage).
  - **To CLI-05** (combat UI, after CLI-04 gives the client the state): the conditions and effects
    row with remaining ticks (the client has no condition state, and the pack has **no condition
    icon**), the target zone (the selected actor's plate and bar: the **sword plates** would fit
    it), the skill bar and belt (the **state glyphs** 4 / 5 / action point / coins / crown are made
    for skill buttons: costs and recharges), the activation ring, the hit marks, the combat log's
    look, the **"no" cursor and the selection brackets** (they need hover previews over tiles,
    design/11 *Desktop*).
  - **To CLI-01 / CLI-03** (the chain): "saving…" in the status zone (design/11 *The chain,
    unseen*).
  - **To CLI-06** (hub UI): the full character sheet and build editor; this lot adds only the
    portrait to today's summary.
  - The ☰ menu of design/11's sketch: Leave and Travel back stay where they are, as buttons
    (moving them into a menu changes the taps of I-5: a later decision, not a dressing).
  - The map's renderer (`render/**` but `sprites.ts`), the place labels, the service row, the
    other screens' chrome.
  - A display font (CLI-03i *Open questions* §2), animation of any kind (I-7: a bar changes width
    at once, no tween), phone builds, simulators, devices.

## Placeholders: what the HUD shows from what exists

| HUD element | Source | Today's value | Marked |
|---|---|---|---|
| Portrait | `ADVENTURER.profession` → a portrait entry (*Portraits*) | Vanguard → the blue knight | — (presentation) |
| Name, profession, level | `ADVENTURER` (exists) | Wren, Vanguard, 4 | — |
| Health | **New** `ADVENTURER.health: { current, max }` | 160 / 160 (design/03's figure for a level-4 adventurer, written as data, not computed) | `/** PLACEHOLDER until CLI-04: fixed, never changes in the sandbox. */` |
| Energy | **New** `ADVENTURER.energy: { current, max }` | 20 / 20 (design/03, Vanguard) | same |
| Adrenaline | **New** `ADVENTURER.adrenaline: number \| null` (null for a profession without it) | 0 | same |
| Conditions | none | — | Not drawn (CLI-05) |

- The values live in `sandbox/fixtures/hubs.ts` beside today's sheet: **fixed data**, not a rule
  (mandate §6: no formula is evaluated by the client). The HUD reads them through one prop, so
  CLI-04 replaces the source, not the HUD.
- **`?hud=`** (presentation, `sandbox/params.ts`): `?hud=low` shows health 37 / 160, energy 5 / 20,
  adrenaline 3; `?hud=empty` shows 0 / 160, 0 / 20, 0; any other value is ignored. It changes only
  what the band draws (the browser check uses it to measure fills); it reaches no machine, intent
  or session. A unit test reads each value and an unknown one.
- The HUD shows the same figures in the hubs and in the instance (nothing changes them yet).

## The method

### 1. The status band

- **A band, not an overlay**: the band is a flex row **above** the map box, in the instance and in
  both hubs (in a hub, between the header and the map). design/11 gives the status its own zone
  above a room "never scrolled"; an overlay would cover the tiles the camera keeps in view. The map
  box shrinks by the band's height and the camera centres in what is left, as it already does on a
  resize. **What reverses it**: the owner finds the hub's map too short; then the hub's band merges
  into its header (portrait and health only), a change of `HubScreen.tsx` alone.
- **Surface**: `paper_dark` (the special paper, `#525b66`), white text (6.89 : 1, CLI-03i §5). The
  wooden bar frames read on the slate; on the cream paper or the wooden board they would not.
- **Content, left to right**: the portrait (48 CSS px box); a column with the health bar and its
  figures (`♥ 160 / 160`), then the energy bar and its figures (`⚡ 20 / 20`); for a Vanguard, the
  adrenaline count (the **sword icon** and the figure). The glyphs ♥ and ⚡ are text, in the
  figures' colour: the pack has no heart or lightning icon (its meat slab would mislead).
- **Height**: at most **72 CSS px** at the default text size (design/11's status zone is ~10 % of
  812 px, 81 px); the content inset of `paper_dark` (24 art px, 12 CSS px a side) included. At
  1440 × 900 the band sits in the 430 px column, same height (I-1: the same interface).
- **The instance's controls move down with the map**: the top-right column (Leave, Travel back,
  debug) stays at the map box's top right; nothing is placed over the band.
- **Accessibility**: each bar is `role="meter"` with `aria-label` ("Health", "Energy"),
  `aria-valuemin`, `aria-valuemax`, `aria-valuenow`; the figures are visible text (colour is never
  the only carrier); the portrait has `alt` / `aria-label` "Wren, Vanguard level 4"; the band is a
  `section` with `aria-label="Status"`. The band takes no tap and holds no control (I-6 does not
  apply; nothing to hit by mistake).

### 2. Bars: a three-slice frame with a fill

- **The frame** is a `three` entry (`bar_big`, `bar_small`), cut and laid out by CLI-03i's method:
  ends unscaled, the middle stretched (uniform along x, checked by the build's edge rule). Height
  fixed: the big frame's visible 51 rows are 25.5 CSS px; the small frame's 19 rows are 9.5 CSS px,
  **rounded to whole device px** (10 CSS px at 1×, 9.5 at 2×, 9.67 at 3×: `toDevicePx`).
- **The trough** is recorded as the entry's `content` insets (art px of the trimmed image: for the
  big bar about top 12, bottom 16, left 11, right 12, from the figures above; the implementer reads
  them from the build's report). The fill is drawn **inside the content box only**.
- **The fill** is a `still` (`bar_big_fill`, `bar_small_fill_energy`), every column identical, drawn
  as the background of an inner element **stretched horizontally only** (`background-size: <w>
  100%`, `image-rendering: pixelated`): no column differs, so stretching changes nothing but the
  length.
- **Width**: `fillWidth(trackDevicePx, current, max) = round(trackDevicePx × clamp(current, 0, max)
  / max)` in **device px**, then divided by the ratio for CSS; 0 draws no fill element (not a
  zero-width one), `current = max` fills the trough exactly. `max = 0` draws no fill. Pure, in
  `chrome/scale.ts`, unit-tested at 1, 1.5, 2 and 3 for 0, 1, half, max − 1, max, and a value above
  max and below 0.
- **Colours of meaning**: health red (the pack's fill as it is); energy **blue**, a recolour of the
  small fill by the build (*The tools/art changes*), in the blue button family of the pack (the
  implementer picks the three colours from `BigBlueButton_Regular`'s palette and lists them in the
  manifest). Both bars also differ by **size** (big for health, small for energy) and by their
  glyph and label: colour is never the only carrier.
- **Health uses the big bar, energy the small bar**: health is the figure the player watches;
  energy is read before a skill. **What reverses it**: the owner wants two equal bars; then the
  energy fill is a recolour of the big fill too (one more manifest entry).

### 3. Portraits

- **Which**: the **blue** row (the Blue faction of CLI-03e, kept by CLI-03i's open question 3).
  Vanguard → `Avatars_01` (the plumed great helm: the Warrior the Vanguard's sprite uses, manifest
  line 30); Warden → `Avatars_02`; Cleric → `Avatars_05`. The implementer checks the three by eye
  against the units' sheets the manifest already maps (Warrior, Archer, Monk) and may swap within
  the blue row; the report names the files chosen. **Arcanist**: no portrait (no caster in the
  pack, Q-12): the plain portrait (below) is drawn even with the art.
- **Trimmed**: the build trims each portrait's transparent margin (`trim = true`, *The tools/art
  changes*), so the box holds the face, not empty corners.
- **Reduced far below the art**: the band's box is 48 CSS px for a trimmed portrait of about
  200 art px, i.e. **0.24 CSS px per art px**, below `CHROME_SCALE`. A nearest-neighbour cut at
  0.24 × 1 device px per art px drops three pixels of four and loses the 2–4 px outlines. So a
  portrait entry carries its own **display size** (CSS px of its longer side: 48 in the band, 96 in
  the desktop's sheet, 40 in the inspect dialog), and the client cuts it **with smoothing on**
  (`imageSmoothingQuality = "high"`) whenever the cut is below 1 device px per art px, nearest
  otherwise. The cut stays one image pixel per device pixel in CSS, so the browser never
  resamples it again. Each size is its own cut (three small object URLs per portrait), redone on a
  ratio change and revoked like CLI-03i's. **What reverses it**: the smoothed portrait looks soft
  next to the crisp chrome on the owner's screen; then a larger band portrait (64 CSS px, 0.32) or
  a pre-reduced portrait made by the build (`--resample area`, as the units' sprites).
- **Frame**: none added; the avatar's own diamond backdrop is its frame, on the band's slate.
- **Plain portrait** (no art, or the Arcanist): a disc of the same box, `#2a2a33` with a 2 px
  `#f2c94c` ring and the profession's initial in white bold.
- **Where**: the band (48), the desktop's `SheetSummary` (96, above the name), the hub's inspect
  dialog (40, before the name: the inspected adventurer's profession picks the portrait).

### 4. Adrenaline

- A Vanguard shows **the sword icon** (`Icon_05`, at `CHROME_SCALE`, 32 CSS px box; it is the
  weapon whose hits make adrenaline) and the count of strikes as a figure, `aria-label="Adrenaline:
  0 strikes"`. No bar: adrenaline has no maximum (design/04), so a bar would invent one.
- Another profession shows nothing in that place (`adrenaline: null`).

### 5. Loading: the HUD's entries are optional

- CLI-03i's `loadChrome` refuses the whole chrome when one entry of `CHROME_ENTRIES` is missing.
  The HUD's entries go in a **second list, `HUD_ENTRIES`**, loaded in the same pass: when one is
  missing or fails, **only the HUD** draws plain (`data-hud="plain"` on the band), the chrome keeps
  its art. So a `sprites.json` built before this lot (a stale `out/`, the site between a merge and
  its rebuild) still shows CLI-03i's chrome. A unit test on fake loaders covers both: a missing HUD
  entry (chrome `atlas`, HUD `plain`) and a missing chrome entry (both `plain`).

### 6. Cursors (desktop)

- **Decided: in this lot, the arrow and the pointing hand only.** Under `@media (hover: hover) and
  (pointer: fine)`, the loop's root uses `Cursor_01` as its cursor and every enabled `button` and
  the map's canvas use `Cursor_02`; a disabled button keeps the arrow. Touch screens are unchanged.
- **How**: two `still` entries (`cursor_arrow`, `cursor_hand`), trimmed, cut at **CHROME_SCALE**
  (about 11–16 × 15–18 CSS px: the size of a system cursor) at 1× and 2×, and set through
  `cursor: image-set(url(<1×>) 1x, url(<2×>) 2x) <hx> <hy>, auto` (hot spot: the arrow's tip, the
  hand's fingertip, in CSS px, from the trimmed image). Object URLs as for the chrome. The keyword
  fallback (`auto`, `pointer`) stays in the declaration, so a browser that refuses the image keeps
  the system cursor.
- **Why not more**: the "no" sign (an unreachable tile) and the brackets (a selection) need hover
  previews over the map (design/11 *Desktop*: "hover shows previews"), which are CLI-05's.
  **What reverses it**: the owner finds the pack's arrow distracting; then the cursors are dropped
  by removing two CSS rules (the entries may stay).

### 7. Contrast and sizes

| Text | Surface | Colour | Ratio | Rule |
|---|---|---|---|---|
| Figures `160 / 160`, glyphs, adrenaline count | `paper_dark` `#525b66` | white | 6.89 | body ≥ 4.5 |
| Inspect dialog, sheet | unchanged (scroll, `paper_dark`) | unchanged | — | — |

- The figures are `0.8125rem` semi-bold with tabular figures; they sit **beside** the bar, never
  over the fill (a red fill under white text would measure about 3.3 : 1).
- `contrast.ts` gains the band's row; `contrast.test.ts` checks it against `paper_dark`'s centre
  colour, as CLI-03i's rows.
- At 375 × 812 the band never wraps: the bars shrink (min 96 CSS px of trough) before the figures;
  at the system text size enlarged to 200 % (CLI-03j's check), the band may grow in height, never
  clip (AC-6).

## The tools/art changes

- **`still` entries may be trimmed**: `trim = true` trims the transparent margin and records it as
  `outset`, as for nine-slices (an entry with states is trimmed by the margins its states share).
  Default `false`: CLI-03i's stills are unchanged.
- **`recolour`** on an entry: `recolour = { "#ff3e3e" = "#…", … }`, an exact colour map applied to
  the source pixels before packing. The build **refuses** a map that leaves an opaque source colour
  unmapped (no stray red pixel in a blue fill) or names a colour the source does not have.
- **Entries of this lot** (names indicative):

  | Name | Kind | Source | Notes |
  |---|---|---|---|
  | `bar_big` | three | `Bars/BigBar_Base` | `fill = "stretch"`; `content` = the trough |
  | `bar_big_fill` | still | `Bars/BigBar_Fill` | `trim = true` (24 rows kept) |
  | `bar_small` | three | `Bars/SmallBar_Base` | as `bar_big` |
  | `bar_small_fill_energy` | still | `Bars/SmallBar_Fill` | `trim = true`; `recolour` red → the pack's blue |
  | `icon_sword` | still | `Icons/Icon_05` | adrenaline |
  | `portrait_vanguard`, `portrait_warden`, `portrait_cleric` | still | `Human Avatars/Avatars_01`, `_02`, `_05` (*Portraits*) | `trim = true` |
  | `cursor_arrow`, `cursor_hand` | still | `Cursors/Cursor_01`, `_02` | `trim = true` |

  The red small fill (`SmallBar_Fill` unrecoloured), the state glyphs, the other icons, the other
  avatars, the "no" cursor, the brackets and the sword plates stay uncut.
- **The UI page**: the new frames go on the UI page(s) with CLI-03i's; three trimmed portraits add
  about 3 × 200 × 185 px (an estimate; the build's report gives the real page size).
- **README**: *UI elements* gains `trim` and `recolour` in its field table and the new entries in
  its list.
- **Fingerprints**: none committed (the `out/` fingerprints change; ART-02's dated record stays).
- **D-73**: nothing of the pack in a commit, the pull request, a comment or the report.

## Size

**One lot.** Estimate (not a measure): `tools/art` ~120 lines with tests (trim for stills,
recolour, the entries); the chrome ~200 (`HUD_ENTRIES`, the portrait cut, `fillWidth`, `Bar`,
`Portrait`, CSS, cursors); `Hud.tsx` and the screens ~200; the fixtures and `?hud=` ~40; the
browser check ~250. Commits in this order: (1) `tools/art` and its tests; (2) the chrome's loader,
scale and components with tests, plain first; (3) `Hud.tsx`, the fixtures and `?hud=`; (4) the
screens, one commit per file; (5) the cursors; (6) the browser check.

## Allowlist

- `tools/art/manifest.toml`, `tools/art/artpipe/**`, `tools/art/build.py`, `tools/art/tests/**`,
  `tools/art/README.md` (*UI elements* only).
- `client/app/src/render/sprites.ts` (only if the `ui` field needs a new optional key) and its test.
- `client/app/src/chrome/**` (`load.ts`, `scale.ts`, `Chrome.tsx`, `chrome.css`, `contrast.ts`, their
  tests; new files allowed).
- `client/app/src/sandbox/loop/Hud.tsx` and `hud.ts` (new), `hud.test.ts`; `HubScreen.tsx`, `InstanceScreen.tsx`,
  `screens.tsx` (`SheetSummary` only), `Loop.tsx` (only if the left panel's layout needs it),
  `styles.ts`.
- `client/app/src/sandbox/fixtures/hubs.ts` (`AdventurerSheet` and `ADVENTURER`: the three
  placeholder fields only).
- `client/app/src/sandbox/params.ts` and `params.test.ts` (`?hud=` only).
- `client/app/verify-hud.mjs` (new) and one `scripts` line in `client/app/package.json`
  (`verify:hud`; no dependency).
- `docs/reports/CLI-03l-hud.md`.

**Not in the allowlist**: `sandbox/placeholders.ts`, `sandbox/loop/machine.ts`, `sandbox/session.ts`,
`sandbox/wiring.ts`, `sandbox/Sandbox.tsx`, the other `sandbox/fixtures/**`, `input/**`,
`render/**` but `sprites.ts`, `client/sim/**`, `contracts/**`, `client/app/src/account/**`,
`client/app/src/chain.ts`, `pnpm-lock.yaml` (no new dependency), `tools/site/**`, `.github/`,
`docs/design/**`. `sandbox/imports.test.ts`: assertions may be added, no guard loosened. Anything
else is an escalation in the report, not an edit.

**For the orchestrator, overlap**: the files above overlap any lot that touches the chrome,
`HubScreen.tsx`, `InstanceScreen.tsx`, `screens.tsx`, `fixtures/hubs.ts`, `params.ts` or
`tools/art`'s `[[ui]]` section; they do not overlap the renderer, the input, `client/sim` or the
contracts.

## Interfaces

- `sandbox/fixtures/hubs.ts`: `AdventurerSheet.health: Gauge`, `.energy: Gauge`, `.adrenaline: number
  | null`, with `interface Gauge { readonly current: number; readonly max: number }`; the three
  marked as placeholders until CLI-04.
- `sandbox/params.ts`: `readHud(value): "low" | "empty" | null`, and the sheet the band shows for
  it (`hudSheet(sheet, hud)`), pure.
- `chrome/scale.ts`: `fillWidth(trackDevicePx, current, max): number` (device px);
  `portraitCut(artSize, displayCssPx, dpr): { devicePx, smooth }`.
- `chrome/load.ts`: `HUD_ENTRIES`; `ChromeImages.hud: ReadonlyMap<…> | null` (null: the HUD is
  plain); portrait cuts per display size.
- `chrome/Chrome.tsx`: `Bar` (`size: "big" | "small"`, `tone: "health" | "energy"`, `current`,
  `max`, `label`), `Portrait` (`profession`, `size: 40 | 48 | 96`, `label`); `useHudMode()`.
- `sandbox/loop/hud.ts` (pure): `hudModel(sheet, mode)` → the meters (label, current, max,
  `aria-*`), the figures' text, the adrenaline count or null, the portrait's entry or `plain`.
- `sandbox/loop/Hud.tsx`: `Hud({ sheet })`, a `section` with `data-hud="atlas" | "plain"`, drawn
  from `hudModel`; it renders only when `sheet` changes (`memo`).
- Intents, the machine, `placeholders.ts`, the map's `sprites.json` roles: unchanged.

## Acceptance criteria

- [ ] AC-1 **Presentation only**: `git diff origin/main --stat` lists only allowlisted files;
      `git diff origin/main -- client/app/src/sandbox/placeholders.ts client/app/src/sandbox/loop/machine.ts client/app/src/sandbox/session.ts`
      is empty (in the report); the loop's and the room's tests (`machine`, `hubDoors`,
      `walkFollowsPreview`, `wiring`, `session`, `placeholders`) pass unmodified.
- [ ] AC-2 **The pipeline** (`tools/art` tests, synthetic sheets only): a trimmed still records its
      outset; an untrimmed still is unchanged (CLI-03i's entries build as before); a recolour maps
      every opaque colour; a map leaving a colour unmapped, or naming one the source lacks, is
      refused; the bar three-slice's middle passes the edge rule; the existing tests pass
      unmodified.
- [ ] AC-3 **The loader** (unit, fake loaders): `HUD_ENTRIES` all present → chrome and HUD `atlas`;
      one HUD entry missing → chrome `atlas`, HUD `plain`; one chrome entry missing → both `plain`;
      portrait cuts at ratios 1, 1.5, 2 and 3 for the three display sizes: smoothing on below 1
      device px per art px, off otherwise, image size = display size × ratio rounded to whole
      device px; a ratio change re-cuts and revokes every old URL.
- [ ] AC-4 **The fill** (unit): `fillWidth` as *The method* §2, at ratios 1, 1.5, 2 and 3; no fill
      element at 0; the trough exactly filled at max.
- [ ] AC-5 **The band** (unit, `hud.test.ts` on the pure `hudModel`; the client has no DOM test
      dependency and adds none, as CLI-03d's `leaveQuestion`): with the Vanguard sheet, two meters
      with the right `aria-value*` values and figures, the adrenaline count; with a Warden sheet, no adrenaline; with an Arcanist, the plain
      portrait; `readHud` and `hudSheet` for `low`, `empty`, an unknown value; contrast of the
      band's text ≥ 4.5 : 1 (`contrast.test.ts`).
- [ ] AC-6 **The browser check** (`verify:hud`, VPS, headless Chromium), with the atlas built from
      this branch (never committed), at **1440 × 900** (mouse) and **375 × 812** (touch), each at
      `deviceScaleFactor` 1 and 2 (and 3 at 375), on **the town, the outpost and a zone** (the
      instance after the Gate), each with no `?hud=`, `?hud=low` and `?hud=empty`: `data-chrome`
      and `data-hud` both `atlas`; the band's height ≤ 72 CSS px and nothing overflows the viewport
      horizontally; each meter's fill width = `fillWidth` of its trough within one device pixel;
      the band, the map box and the instance's control column do not overlap; at 1440 the
      left panel shows the 96 px portrait; in the town, a tap on a present adventurer shows the
      inspect dialog with a portrait; with the root font size at 200 %, no figure is clipped
      (`scrollWidth ≤ clientWidth`); at 1440 the computed `cursor` of the root and of a button
      names an image (`image-set` or `url`), at 375 (touch) it does not; no page error.
- [ ] AC-7 **No mechanics change**: the same check on `origin/main` (built in a temporary worktree
      the thread creates and removes by its exact path) and on this branch records, for a 10-step
      walk in the zone and a building walk in the town, the tiles walked and the screens opened:
      **identical**. The map box is smaller by the band's height only (± 1 px); the report lists
      the boxes per screen and size.
- [ ] AC-8 **The frame budget of CLI-03g** (its AC-8), same machine and run, this branch against
      `origin/main`: the median draw time over the 10-step zone walk at both sizes within **+10 %**,
      the 95th percentile within **+25 %**; and the band renders **no** React update during the
      walk (a `data-hud-renders` counter read before and after). Headless Chromium renders in
      software: the figures are relative, and the report says so.
- [ ] AC-9 **The fallbacks**: with no art (`GRIMWORLD_ART_OUT` pointing to an empty folder), every
      checked screen has `data-chrome="plain"` and `data-hud="plain"`, the band's boxes within 1 px
      of the art's, the plain portrait and CSS bars, no page error; with a `sprites.json` lacking
      the HUD's entries (the check filters them out of a copy), `data-chrome="atlas"` and
      `data-hud="plain"`.
- [ ] AC-10 **Shots**: with `VERIFY_SHOTS=1`, a shot of the town, the outpost and the zone at both
      sizes, ratio 2, with no `?hud=` and with `?hud=low`, and the band alone at ratios 1 and 3,
      into the thread's library folder, **untracked**, never committed, attached or posted (D-73);
      the thread looks at them for seams between the bar's slices, the fill's alignment in the
      trough, the portrait's softness, and describes them in words in the report.
- [ ] AC-11 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `pnpm exec prettier --check client indexer`, `tools/art/.venv/bin/python -m unittest discover
      -s tools/art/tests` and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-12 **The owner's eye, after the merge**, on https://grimworld.bal7hazar.com: it does not
      block. A remark on a size, a colour or a portrait is a fix lot; a remark on the band's place
      goes back to *The method* §1.

## Verification

- On the VPS: the commands of AC-11; `tools/art/build.py` with the uncommitted `assets` symlink,
  removed afterwards; then `verify:hud` (AC-6 to AC-10), on this branch and on `main`.
- Start and stop the dev server inside one foreground command; signal only its recorded process
  group (never a search by name: no `pkill`, `pgrep`, `killall`, `ps | grep`). Remove the temporary
  `main` worktree by its exact path.
- `git fetch origin` and merge `origin/main` before every push; `scripts/prepush.sh`, never
  `--no-verify`; never touch `.git/config`. Do not poll CI: push, open the pull request, end the
  turn.

## Review and audit (D-177)

- **Review** on another model than the implementer's: `review` (Sonnet) for an Opus implementer.
  It checks most closely: nothing outside the allowlist and no rule (no health or energy computed,
  the placeholders marked); the HUD's optional loading (a stale `sprites.json` keeps the chrome);
  `fillWidth` and whole device pixels; the portrait cut's smoothing switch and URL revocation; the
  recolour's refusal of unmapped colours; meters' ARIA; the frame-budget figures against `main`;
  D-73 (no image in the diff, the pull request or the report).
- **Audit**: none (D-177; presentation only, the owner sees it). The orchestrator decides otherwise
  if the lot adds a dependency or leaves the allowlist.

## Rules of the run

- D-73: nothing of the pack committed or posted; sizes, counts, colours as hex values and words
  only. The shots stay untracked in the library folder.
- No pin, fingerprint or byte count committed.
- External issues named in words, not links, in commit messages and pull request text.
- Pull request title: `[<model>] CLI-03l the HUD with the pack's bars and avatars`; body through
  REST (`gh pr edit` fails on Projects-classic): the band as built, the portraits chosen, the frame
  figures against `main`, "Audit: none (D-177)", "Owner's eye: on the public site after the merge".

## Report

`docs/reports/CLI-03l-hud.md`, as in `docs/briefs/COMMON.md` §7, with: the method as built and any
deviation; the manifest's new entries, the portraits chosen and the recolour's colours; the UI
page's size from the build's report; the band's and the map's boxes per screen and size with
`main`'s; the frame figures with `main`'s; the shots described in words and where they are; the
tests updated and why; `git diff origin/main -- client/app/src/sandbox/placeholders.ts`; commands
refused; escalations; open questions.

## Open questions

1. **Decided (this brief, reversible by the orchestrator): a band above the map**, in the instance
   and both hubs (*The method* §1). Reverse: the hub's band merges into its header.
2. **Decided: health on the big bar in the pack's red, energy on the small bar recoloured blue by
   the build**; adrenaline as the sword icon and a count, no bar (no maximum in design/04).
3. **Decided: the blue row's portraits** (Vanguard 01, Warden 02, Cleric 05, the implementer may
   swap within the row by eye), no portrait for the Arcanist (Q-12), smoothed below 1 device px per
   art px. Reverse: *The method* §3.
4. **Decided: the arrow and hand cursors now**, the "no" sign and the brackets with CLI-05's hover
   previews.
5. **Decided: what goes to CLI-05**: conditions (no state, no icon in the pack), the target zone
   (the sword plates), the skill bar and belt (the state glyphs), activation rings, the combat
   log's look. CLI-05's brief should start from this list.
6. **For the orchestrator: the lot's letter.** The project manager named it CLI-03l; `PLAN.md` has
   no CLI-03k. This brief keeps CLI-03l; renaming is one line in the PLAN row and the file name.
7. **For the orchestrator: the ☰ menu** of design/11's sketch (Leave and Travel back moved into it)
   is left out: it changes the taps of I-5. A later lot if wanted.
8. **For the project manager, when CLI-04 lands**: the HUD reads `ADVENTURER`'s placeholder fields;
   CLI-04 (or CLI-03, the sandbox wired to `client/sim`) replaces that source with the actor's
   state, and the band follows with no change of its own.
