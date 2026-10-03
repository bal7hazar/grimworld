# CLI-03i — The client's chrome from the pack's UI elements, for every screen at once

**Status: brief, ready to start from `main`** (after CLI-03h, #336). It changes the loop's screens,
the sandbox's overlay controls and `tools/art`; it does not touch the map's renderer, so it does not
wait for any other open lot of the track.

Written for the orchestrator of track CV on 2026-10-03, from its decision of 2026-10-02 on
CLI-03e's Q3 (recorded in `docs/status/client-visual.md`): the owner asked for the pack's (*Tiny
Swords*) assets; the hubs and zones now draw the pack's buildings, ground, foam and obstacles
(CLI-03e, f, g1, g2, h), while the page's **chrome** (panels, buttons, plates, labels, dialogs, the
service row, the overlay controls) is still plain CSS. Decided: the pack's UI elements come in
**one lot for the whole client**, so every screen stays consistent, not the hubs alone.

## Agent

Profile: `impl-opus`. The lot is presentation with pixel judgement (nine-slices at device pixel
ratios, contrast, tap targets) plus a contained pipeline change in `tools/art`, both with tests.

Machine: **the VPS** (the Mac is full). The lot commits no pin, gas table or fingerprint. The pack
is at `/home/claude/projects/assets`: link it into the worktree as `assets` by an **uncommitted**
symlink for `tools/art/build.py`, and remove the link afterwards, as CLI-03g did. The browser check
runs here in headless Chromium.

Branch: a new branch from `main`. One pull request.

## Goal

After this lot:

1. **Every screen wears the pack's chrome**: the hub, the service stubs, the Gate screen, the entry
   moment, the instance's controls and its confirmation, the closing report, and the desktop's two
   side panels. Panels are the pack's papers and scroll; buttons are the pack's blue and red buttons
   with their pressed state; titles sit on the pack's ribbons.
2. **Nothing reads worse than today**: text contrast meets WCAG 2.2 AA (*The method* §5), every
   control keeps a tap target of at least 44 × 44 CSS px (design/11 I-6 asks 40 pt; the client's
   rule since CLI-03c is 44 px), a visible focus state, and no layout regression at 375 × 812 or
   1440 × 900.
3. **Crisp at 1×, 2× and 3×**: the chrome's pixels are cut and scaled nearest-neighbour by the
   client itself, so no browser resampling blurs them (*The method* §3).
4. **Without the art, today's look**: when `sprites.json` or the UI page is absent (CI, a checkout
   without the pack, the site with the art off), the screens draw exactly today's plain CSS.
5. **Presentation only**: no rule, no intent, no machine state, no chain change.

## Context

- **design/10** *What the pack contains*: `UI Elements/` holds "banners, bars, buttons, icons,
  papers, avatars" for the interface. *Licence and provenance*: the client ships the art **packed
  into atlases**, never the pack's files (D-73).
- **design/11**: I-1 (portrait, one thumb; desktop is the same interface with more room), I-5 (a
  mistaken tap is hard: leaving and travelling back are asked twice), I-6 (tap targets), I-7 (the
  screen is still between two actions: no decorative animation), *Hubs* (the service row below the
  map), *Desktop* (the portrait column in the centre, a left panel for the sheet, a right panel for
  the log), *Accessibility* (colour never the only carrier of meaning; text scales with the system).
- **D-73 and the public site** (owner, 2026-10-02): the built atlas pages and `sprites.json` are
  served at https://grimworld.bal7hazar.com; never the pack's raw files; nothing of the pack in a
  commit, a pull request, an issue, a comment or a report. `tools/site/deploy-site.sh` copies
  `sprites.json` and **every page it lists**: a new UI page listed there reaches the site with no
  change to the deploy.
- **The mandate** `docs/briefs/ORCH-client-visual.md`: §4 (D-73), §6 (no rule in `client/app`
  outside `sandbox/placeholders.ts`).
- **The owner's eye no longer blocks** (owner's session, 2026-10-03): the orchestrator decides the
  provisional look, it is merged, and the owner sees it on the public site; a remark comes back as
  a change request.
- **Phone work is suspended** (owner, 2026-10-02): mobile-first, checked in the browser at
  375 × 812 and 1440 × 900 (and at device pixel ratios 1, 2 and 3), nothing on a device.

### What main has

| Part | Where | Today |
|---|---|---|
| Shared styles | `client/app/src/sandbox/loop/styles.ts` (`ui`: `screen`, `header`, `title`, `gold`, `card`, `button`, `primary`, `quiet`, `debug`, `grid`, `label`, …) | Inline `CSSProperties`: dark page `#0b0b0e`, grey cards, cream buttons, a yellow primary; every control ≥ 44 px. No stylesheet exists in the app: no `:active`, `:focus-visible` or `:disabled` rule anywhere |
| The hub | `loop/HubScreen.tsx` | A header (name, gold), the map, place labels on dark plates placed after each frame, an inspect dialog over the map, the service row (a 3-column grid of buttons, the Gate in yellow with ▸) |
| Service stubs, Gate, entry, report | `loop/screens.tsx` (`Header` with a ‹ Back button; `ServiceScreen`, `SheetSummary`, `GateScreen`, `EntryScreen`, `ReportScreen`) | Header + cards + buttons; the Gate's "Before leaving" note is a card with a gold border |
| The instance | `loop/InstanceScreen.tsx` | A column of buttons at the top right (Leave, disabled at 0.4 opacity when no gate; Travel back; the red dashed "debug: defeat now"), the gate offer centred at the bottom, the confirmation dialog (I-5) on a scrim |
| The desktop | `loop/Loop.tsx` | At ≥ 700 px: two side panels (`aside`, 280 px) around the 430 px column |
| The sandbox's overlay | `sandbox/Sandbox.tsx` | The recentre button ◎ (48 px round, white), the walk counter (a white pill; a tap cancels) and its "stopped" line, the **debug** toggle (12 px text, about 20 px tall: below I-6) and the debug panel (black, 12 px) |
| The atlas | `render/atlas.ts`, `render/sprites.ts` | `loadAtlas` reads `/art/sprites.json` and loads **every** page into PixiJS; `readSpritesIndex` checks each sprite's `role`, `page`, `cell`, `baseline`, animations |
| `tools/art` | `manifest.toml` (`[[sprite]]`, `[[still]]` with roles `building`, `prop`; `[[tileset]]` with role `tile`), `artpipe/`, `build.py`, `tests/` | Shelf-packed pages ≤ 2048 with a 2 px gutter; stills trimmed and anchored at the base; tiles untrimmed, top-left, edges extruded. No role for the interface |

### The pack's UI elements (described in words, nothing copied)

Read with Pillow on `/home/claude/projects/assets/UI Elements/` (108 files). Sizes in the pack's
pixels ("art px"); "lattice" means the sheet places its pieces on 64 px cells **with an empty cell
between pieces**, so a 3 × 3 nine-slice of 64 px pieces is a 320 × 320 sheet with pieces at 0, 128
and 256.

| Folder (under `UI Elements/UI Elements/`) | What it holds | Layout |
|---|---|---|
| `Papers/` | `RegularPaper` (cream paper, main colour `#eee1c6`) and `SpecialPaper` (dark slate `#525b66` with gold corner flourishes) | **Nine-slice** sheets, 320 × 320, 64 px pieces on the lattice. Transparent outer margin of the corner pieces: regular left 12, top 20, right 12, bottom 19; special 9 / 20 / 9 / 21 |
| `Banners/` | `Banner`: a parchment **scroll** (`#dcdca5`, textured) with curled left edge and rolled bottom corners; `Banner_Slots`: one 192 × 192 inset square (a slot) | `Banner` is a nine-slice, 448 × 448: **128** px corners, 64 px edges and centre (pieces at 0–128, 192–256, 320–448). Margins left 28, top 60, right 44, bottom 17 (asymmetric: the curls) |
| `Wood Table/` | `WoodTable`: a brown wooden board (`#9b6253`, wood grain) with metal corner brackets; `WoodTable_Slots`: an inset slot | As `Banner`: nine-slice 448 × 448 with 128 px corners. Margins 44 / 43 / 44 / 25 |
| `Buttons/` | `BigBlueButton` (teal `#41919d`) and `BigRedButton` (`#f65555`), each **Regular** and **Pressed**; `Small{Blue,Red}{Square,Round}Button`, each Regular and Pressed; `Tiny{Round,Square}{Blue,Red}Button`, one state | Big: **nine-slice** 320 × 320 on the lattice. Regular margins 19 / 17 / 19 / 17; **Pressed** 14 / 28 / 14 / 15: the pressed face is darker (blue `#4a6982`, red `#ba4954`), **11 art px lower** and slightly wider (its raised edge is gone). Small: one 128 × 128 image, visible about 88–104 × 85–94. Tiny: 64 × 64, no pressed state |
| `Ribbons/` | `BigRibbons`: five colours (blue, red, yellow `#bbb552`, purple, black-grey), one per row, a banner with forked tails; `SmallRibbons`: the same five colours, two shapes each (forked tails; pointed ends) | **Three-slice** (horizontal): Big, rows of 103 visible px, ends 128 px wide, middle 64. Small: rows of 54–60 px, 64 px pieces |
| `Swords/` | A plate shaped as a sword: hilt with a coloured guard (five colours), a cream blade (`#e1d4bd`), the point | Three-slice per row, five rows; hilt and point 128 px, blade 64 |
| `Bars/` | `BigBar_Base` (a wooden frame) and `BigBar_Fill` (a red strip); `SmallBar_*` the same, thinner | Three-slice bases, 320 × 64; fills are 64 px strips |
| `Icons/` | Twelve 64 px icons: hammer, log, gold coin, meat, sword, shield, green gem, **orange back arrow**, **red cross**, gear, info, music note. And small state icons (the digits 4 and 5, an action point, gold coins, a crown), each **Regular / Pressed / Disable**, drawn semi-transparent to sit on a button | 64 × 64 each, untrimmed |
| `Cursors/` | An arrow and three selection brackets | 64 or 128 px |
| `Human Avatars/` | 25 portraits, 256 × 256 | — |

`UI Elements/UI Banners from the store page/` holds the store page's large compositions (stones,
wooden signs, 960 × 576 ribbons): marketing art, not used.

**Fonts**: the pack has **no font file** (no `.ttf`, `.otf` or `.woff` anywhere in it), so there is
nothing of the pack to serve as a font. Any display font would come from elsewhere, under its own
licence: a font under the SIL Open Font License may be bundled and served by the site; a font
fetched at run time from a third-party CDN is not wanted (a request outside the site). This lot
adds **no font** (*Open questions* §2).

**Colours**: every sheet has 2 to 34 colours and no semi-transparent pixel, except the small state
icons (soft edges). Pixel art: it must be scaled nearest-neighbour.

## Scope and non-goals

- **In**:
  1. `tools/art`: a role `ui` and a `[[ui]]` manifest entry for nine-slices, three-slices and
     stills; the pieces composed contiguous; a separate **UI page**; slice metadata in
     `sprites.json` (*The tools/art changes*).
  2. The client: a chrome loader that cuts the UI page into images at the device's scale, a small
     set of chrome components and one stylesheet, the fallback to today's look.
  3. Every screen and control listed in *Screens and components*, restyled through them.
  4. A browser check of every screen at both sizes and three pixel ratios, plus unit tests.
- **Out (non-goals)**:
  - Any rule, intent, machine state, fixture figure, `client/sim`, chain or account change;
    `sandbox/placeholders.ts`.
  - The map's renderer (`render/renderer.ts`, `shapes.ts`, `ground.ts`, `obstacles.ts`): the
    chrome is DOM; nothing of it is drawn by PixiJS.
  - The instance's HUD of design/11 (status bars, conditions, target, skill bar, belt): CLI-05 and
    CLI-08. The pack's bars and state icons are therefore not cut in this lot.
  - Avatars, cursors, the store-page art, the tiny buttons, the sword plates (*Open questions* §4).
  - A display font (*Open questions* §2); converting `px` to `rem` for system text scaling
    (design/11 *Accessibility*: a later lot of the whole client, *Open questions* §5).
  - Animation of any kind (I-7): the pressed state is instant, no transition.
  - Phone builds, simulators, devices (suspended).

## The method

### 1. How a nine-slice reaches the DOM

| Option | How | For | Against |
|---|---|---|---|
| A. CSS `border-image` straight from the atlas page | `border-image-source: url(atlas-ui-0.png)` | No JavaScript | `border-image` takes a **whole image**: it cannot address a sub-rectangle of an atlas page. Unusable with an atlas |
| B. Nine positioned boxes per element | Each panel or button is a 3 × 3 grid of `div`s, each with `background: url(page) -x -y` scaled | Works with any atlas | Nine extra nodes per control (the service row alone is 9–12 buttons: ~100 nodes); scaling a background sub-rectangle needs `background-size` arithmetic per piece; the browser resamples (blur or uneven pixels at 1.5×) |
| C. Canvas per element | Each control draws itself on a `canvas` behind its text | Exact pixels | A canvas per button, resized on every layout change; text and focus must be layered by hand |
| **D. Cut once, then native `border-image`** (recommended) | At load, the client fetches the UI page once, **cuts each `ui` frame into its own small image at the device's scale** (canvas, smoothing off), keeps each as an in-memory object URL, and publishes them as CSS custom properties (`--gw-paper`, `--gw-button-blue`, `--gw-button-blue-pressed`, …) on the loop's root. A stylesheet uses `border-image: var(--gw-paper) <slice> fill / <width> / <outset> <repeat>` on ordinary elements | One node per control, native layout and text, `:active` / `:focus-visible` / `:disabled` in CSS; the served form stays the **atlas page** (D-73: nothing per element is served, the cut images live only in the page's memory); pixels scaled once by the client, nearest-neighbour, **at a 1 : 1 device-pixel ratio** in CSS, so the browser never resamples them | A few lines of async loading; the cut is redone when the pixel ratio changes (a window dragged to another screen) |

**Recommended: D.** It is the only option that keeps the controls plain DOM (accessibility, layout,
pseudo-classes) and still uses an atlas. **What reverses it**: a browser on the target list that
cannot use an object URL in `border-image` (none known among Chromium, WebKit and Gecko); then B
for that browser only.

### 2. The pieces and the slices

- The build composes each nine-slice's nine pieces **contiguous** (the lattice's empty cells
  removed), keeps the pack's pixels untouched, and **trims the transparent outer margin** of the
  corner pieces, recording it as the element's `outset` (art px). A regular paper's three 64 px
  pieces per side become about 168 × 153 px once composed and trimmed; a big button about 154 × 158.
- The **slice insets** (art px, top / right / bottom / left) are given per entry in the manifest,
  chosen by the implementer by eye from the pieces: the smallest insets that keep the whole border
  and corner drawing in the slices, so the centre is plain fill. With the margins trimmed they are
  at most the piece's size (64 or 128) minus the margin. **The build checks** each inset lies inside
  the composed image and that the four edges between the insets are uniform along their length
  (a border that changes along an edge would be stretched visibly).
- Three-slices (ribbons) have left and right insets only; their height is fixed (the art's).
- `fill`: the centre is drawn (`border-image … fill`). Edges and centre **stretch** for the papers,
  the buttons and the ribbons (near-flat: the paper's centre is one colour on 93 % of its pixels,
  the buttons' 100 %); **repeat** (`round`) for the scroll and the wooden board, whose grain would
  smear when stretched. Given per entry (`fill = "stretch" | "round"`).
- **Content insets** (art px), per entry: where text may sit, inside the drawn border. The
  component pads its text by them × the chrome scale.

### 3. Scale: crisp at 1×, 2× and 3×

- **One chrome scale in CSS px**: `CHROME_SCALE = 0.5` CSS px per art px, at every pixel ratio, so
  a control has the same size on every screen. A big button's trimmed corner piece is about
  22 × 24 CSS px; its slices are at most that, and the button's `min-height` stays 44 CSS px.
- **Pixels scaled by the client, not the browser**: the cut (§1) draws each frame into a canvas at
  `CHROME_SCALE × devicePixelRatio` device px per art px with smoothing off (nearest-neighbour),
  then CSS sets `border-image-width` and the slices so that **one image pixel is one device
  pixel**. At 1× the art is halved (every other pixel; the pack's outlines are 2–4 px, they
  survive), at 2× it is 1 : 1 (exact), at 3× it is 1.5× (nearest: alternate pixels doubled, sharp,
  not blurred). `image-rendering: pixelated` is set as well, as a guard.
- **Insets on whole device pixels**: slice and content insets are rounded to whole device pixels
  after scaling, so no seam opens between a corner and an edge at 1.5×.
- **When the ratio changes** (a `matchMedia("(resolution: …dppx)")` listener), the cut is redone
  and the custom properties replaced; the old object URLs are revoked. A unit test covers the
  scale arithmetic at 1, 1.25, 1.5, 2, 2.625 and 3.
- **What reverses it**: the chrome looks too large or too small on the owner's screens: one
  constant (`CHROME_SCALE`), changed by a fix lot; or a scale per ratio (0.5 at 1× and 2×, ⅓ at
  3×: 1 : 1 device pixels everywhere at the cost of a smaller chrome on 3× phones).

### 4. Button states

| State | Art | CSS |
|---|---|---|
| Normal | The entry's Regular nine-slice | `.gw-button` |
| Pressed | The Pressed nine-slice; the **label moves down** by the face's drop (11 art px for the big buttons, × the chrome scale, rounded to device px) so the text rides the face | `:active`, and `[aria-pressed="true"]` for a toggle |
| Disabled | **No art in the pack**: the Regular art greyed by CSS (`filter: grayscale(1) brightness(0.85)`), the label at reduced opacity, `cursor: default`; the `disabled` attribute stays the source of truth (today's Leave) | `:disabled` |
| Focus | Not in the pack: a 3 px outline in today's yellow `#f2c94c` with a 1 px dark halo, offset outside the art's margin, on `:focus-visible` only (keyboard), never on a tap | `:focus-visible` |
| Hover (desktop) | `filter: brightness(1.06)`, no movement | `@media (hover: hover)` |

No transition between states (I-7). The pressed art is served as its own cut image, so a press
swaps a custom property, not a layout.

### 5. Text on the chrome: colours and contrast

Measured: the main colour of each surface's centre, WCAG contrast against white and against
`#111` (ink).

| Surface | Main colour | White | Ink `#111` | Text used |
|---|---|---|---|---|
| Regular paper | `#eee1c6` | 1.29 | 14.59 | **Ink** |
| Scroll (`Banner`) | `#dcdca5` | 1.42 | 13.33 | **Ink** |
| Special paper | `#525b66` | 6.89 | 2.74 | **White** |
| Wooden board | `#9b6253` | 4.92 | 3.84 | **White** |
| Yellow ribbon | `#bbb552` | 2.13 | 8.85 | **Ink** |
| Blue ribbon | `#41919d` | 3.64 | 5.18 | Large white (below) |
| Blue button, regular / pressed | `#41919d` / `#4a6982` | 3.64 / 5.78 | 5.18 / 3.27 | Large white (below) |
| Red button, regular / pressed | `#f65555` / `#ba4954` | 3.31 / 5.04 | 5.71 / 3.75 | Large white (below) |

- **No single text colour reaches 4.5 : 1 on a button in both of its states**. Recommended: button
  and blue-ribbon labels are **large text** in WCAG's sense (bold, at least 18.67 CSS px, i.e. 14 pt
  bold), white, with a one-device-pixel dark outline (`text-shadow` on four sides): the lowest
  ratio is 3.31 : 1 (red regular), above large text's 3 : 1. **What reverses it**: a label does not
  fit at 375 px (the service row's longest labels, "Enchanter", "Alchemist", in a third of 375 px
  minus the side insets); then ink `#111` at 15 px semi-bold on the regular faces (5.18 and
  5.71 : 1), the pressed face keeping ink (3.27 and 3.75 : 1, which then fails AA for the instant of
  the press) — the report says which was built.
- Text on papers and the scroll stays the body size (15 px) in ink: far above 4.5 : 1.
- **Text is never in the art**: every label is live text over the chrome, centred in the content
  box, one line, `text-overflow: ellipsis` on plates; a plate never clips a label at the tested
  sizes (AC-7).
- The contrast table is recomputed by the build (`report.json`: each `ui` entry's centre colour)
  and checked by a unit test of the client against the text colour each component uses, so a
  change of art cannot silently break contrast.
- **Forced colours** (`@media (forced-colors: active)`): the chrome's images are dropped and plain
  system borders drawn, so a high-contrast setting still shows every control.

### 6. Tap targets

- Every control's **hit box** is the element itself, at least 44 × 44 CSS px, whatever the art's
  transparent margin (the margin is drawn outside by `border-image-outset`, never inside the hit
  box). Measured on every interactive element by the browser check (AC-6).
- The **debug toggle** (today about 20 px tall) is raised to 44 px with the rest.

## Screens and components

### Components (new, `client/app/src/chrome/`)

| Component | Art | Use |
|---|---|---|
| `Panel` (`variant`: `paper`, `dark`, `scroll`, `wood`) | Regular paper, special paper, scroll, wooden board | Cards, dialogs, side panels, the service row's backdrop |
| `Button` (`variant`: `action`, `commit`, `quiet`) | Big blue; big red; regular paper with ink text | `action` for what moves on; `commit` for the second, irreversible tap of I-5 and for the Gate; `quiet` for Back, Stay, Skip, Close |
| `IconButton` (`icon`) | Small blue round or square button (fixed size, ~44–52 CSS px) with an icon or a glyph | ‹ Back (the orange arrow icon), ✕ Close (the red cross icon), ◎ recentre (a glyph: the pack has no recentre icon) |
| `Ribbon` (`colour`: `blue`, `red`, `yellow`; `size`: `big`, `small`) | Big or small ribbons, forked tails | Screen titles (big), place labels (small) |
| `Icon` (`name`) | The 64 px icons, drawn at the chrome scale | The gold coin, the back arrow, the cross |
| `ChromeProvider` | — | Loads and cuts the UI page, sets the custom properties and `data-chrome="atlas" | "plain"` on its root, revokes the URLs on unmount |

All are thin wrappers over real `button`, `section`, `h1`, `div` elements with the classes of one
stylesheet, `chrome/chrome.css` (imported by the module; Vite bundles it). Without the art
(`data-chrome="plain"`), the stylesheet's plain rules reproduce today's `styles.ts` look, so
screens without the atlas do not change.

### Which screen uses what

| Screen or control | Today | After |
|---|---|---|
| Page background (`Loop`, every screen) | `#0b0b0e` | Unchanged dark (the map and the papers carry the colour) |
| Screen header (`Header` in `screens.tsx`; the hub's header) | Grey bar, title, ‹ Back | The title on a **big blue ribbon** (the report: blue for Returned, red for Defeated), the back as an `IconButton` with the arrow, white large title text |
| Hub's gold | Yellow number | The **gold coin icon** and the number, tabular figures |
| Hub's service row (`nav` grid) | Cream buttons, yellow Gate | The row on the **wooden board**; services as `action` buttons; the **Gate** as `commit` (red) with ▸ |
| Hub's place labels (over buildings) | Dark plate, white 15 px | A **small yellow ribbon**, ink text (8.85 : 1); still takes no tap and is placed by the camera as today |
| Hub's inspect dialog | Dark card over the map | A **scroll** panel, ink text, `IconButton` ✕ |
| Service stubs (`ServiceScreen`) | Header, a card, a muted line | Ribbon header; the card on **paper** |
| Gate screen (`GateScreen`) | Cards per gate with a yellow Leave ▸; sheet summary; the "Before leaving" note | Each gate a **paper** card with an `action` Leave ▸; the sheet on paper; the note on **special paper** (white text) so it reads as a different kind of message |
| Entry moment (`EntryScreen`) | Title, line, Skip | Title and destination on the **scroll**, Skip as `quiet` |
| Closing report (`ReportScreen`) | Header, four cards, a full-width primary | Ribbon header (blue or red), four **paper** cards, a full-width `action` button |
| Instance: Leave, Travel back | Cream / outline buttons at the top right | `action` buttons; Leave disabled as §4 |
| Instance: the gate offer | Yellow button at the bottom | `action` button |
| Instance: confirmation (I-5) | Card on a scrim | A **scroll** panel on the scrim; **Stay** `quiet`, **Leave / Travel back** `commit` (red: the second, irreversible tap) |
| Walk counter and its "stopped" line | White pill, dark tag | `quiet` button (paper) and a small paper tag |
| Recentre ◎ | White disc | `IconButton`, small blue round |
| Desktop side panels | Plain columns | **Special paper** panels (white text), the section labels in white bold: today's yellow accent `#f2c94c` measures only 4.34 : 1 on
  the special paper's `#525b66`, below 4.5 : 1 for 13 px labels |

### What stays plain

- **The debug controls** ("debug" toggle, the debug panel, "debug: defeat now"): Decided, they keep
  a deliberately **non-pack** look (today's red dashed `ui.debug`, extended to the toggle and the
  panel's frame) so nobody mistakes a debug control for a game control; only the toggle's size
  changes (44 px, §6). **What reverses it**: the orchestrator wants them in the pack's chrome too;
  then `dark` panels with a red "debug" ribbon.
- The map itself, the place labels' placement code, the log's lines, every figure and sentence.

## The tools/art changes

- **A role `ui`** and a manifest table **`[[ui]]`**, one entry per element:
  - `name`, `role = "ui"`, `kind = "nine" | "three" | "still"`, `fill = "stretch" | "round"`;
  - `file` (path in the pack) and, for `nine` / `three`, `pieces`: the pieces' source rectangles
    as column and row bounds (`columns = [[x0, x1], …]`, `rows = [[y0, y1], …]`) — the lattice is
    described, not guessed; for a row of a multi-row sheet (ribbons), `rows` selects that row;
  - `states = { pressed = "<file>" }` when a pressed sheet exists (same layout, cut the same way);
  - `slice = [top, right, bottom, left]` and `content = [top, right, bottom, left]` in art px;
  - `drop` (art px) for an entry with a pressed state: checked by the build against the difference
    of the regular and pressed faces' top edges (11 for the big buttons).
- **Entries of this lot** (names indicative): `paper`, `paper_dark`, `scroll`, `wood`,
  `button_blue`, `button_red` (each with `pressed`), `ribbon_big_blue`, `ribbon_big_red`,
  `ribbon_small_yellow`, `round_blue`, `square_blue` (each with `pressed`), `icon_back`,
  `icon_close`, `icon_gold`. The other files stay uncut.
- **Composition**: pieces placed contiguous, outer margins trimmed and recorded as `outset`, the
  pack's pixels untouched; **no gutter extrusion** (the client cuts exact rectangles); stills
  untrimmed at their native size.
- **A separate page**: `ui` frames are packed on their own page(s), `atlas-ui-N.png` / `.json`,
  listed in `sprites.json`'s `pages` with `group: "ui"` (other pages `group: "world"`, or no group:
  world). Estimate, not a measure: under 1024 × 1024 for the entries above; the build's report
  gives the real size. The map's loader skips `ui` pages, so PixiJS never uploads them; the chrome
  loads only them.
- **`sprites.json`**: a `ui` sprite carries `ui: { kind, fill, slice, content, outset, drop?,
  states? }` beside its frame; `readSpritesIndex` validates it (every inset a finite integer ≥ 0
  inside the frame; known kinds and fills; a state's frame exists), and refuses the index as a
  whole on a bad entry, as today.
- **`report.json`**: each `ui` entry's centre colour (the most common opaque colour between the
  slices), read by the client's contrast test as a fixture **copied into the test as numbers**,
  never as an image.
- **Build checks**: insets inside the frame; uniform edges between the insets (§2); a pressed
  sheet has the regular sheet's layout; `drop` matches the faces; a `ui` page holds only `ui`
  frames.
- **README**: a new section *UI elements: nine-slices, three-slices and the UI page* (the table,
  the entries, how to add one), and the `pages` / `group` line in *What it produces*.
- **Fingerprints**: none committed. The new page changes `out/`'s fingerprints; the README keeps
  ART-02's dated record and its "a later manifest has others" line.
- **D-73**: nothing of the pack in a commit, the pull request, a comment or the report; the
  symlink is never committed. The UI page is a built atlas page, served by the site like the
  others by the owner's decision of 2026-10-02.

## Size

**One lot, CLI-03i**, as the orchestrator decided: the point is that every screen changes together.
Estimate (not a measure): `tools/art` ~250 lines with tests, the chrome loader and components ~400,
the screens' changes ~300 (mostly replacing inline styles), the browser check ~250. The work splits
naturally into commits in this order: (1) `tools/art` and its tests; (2) `sprites.ts` / `atlas.ts`
and the chrome loader with tests, the fallback first; (3) the components and the stylesheet;
(4) the screens, one commit per file; (5) the browser check. **What reverses it**: the reviewer finds
the pull request too large to review in one pass; then (1)–(2) merge first as CLI-03i1 (no visible
change: the fallback is today's look) and (3)–(5) follow as CLI-03i2, still one change for every
screen at once.

## Allowlist

- `tools/art/manifest.toml`, `tools/art/artpipe/**`, `tools/art/build.py`, `tools/art/tests/**`,
  `tools/art/README.md` (the new section and *What it produces*).
- `client/app/src/render/sprites.ts` (the `ui` field, `group`), `render/atlas.ts` (skip `ui`
  pages), and their tests.
- `client/app/src/chrome/**` (new: loader, scale arithmetic, components, `chrome.css`, tests).
- `client/app/src/sandbox/loop/HubScreen.tsx`, `InstanceScreen.tsx`, `screens.tsx`, `Loop.tsx`,
  `styles.ts`; `client/app/src/sandbox/Sandbox.tsx` (the overlay controls and the debug toggle's
  size only); their tests.
- `client/app/verify-chrome.mjs` (new) and one `scripts` line in `client/app/package.json`
  (`verify:chrome`; no dependency).
- `docs/reports/CLI-03i-client-chrome.md`.

**Not in the allowlist**: `sandbox/placeholders.ts`, `sandbox/loop/machine.ts`, `sandbox/fixtures/**`,
`input/**`, `render/renderer.ts`, `render/shapes.ts`, `render/ground.ts`, `render/obstacles.ts`,
`client/sim/**`, `contracts/**`, `client/app/src/account/**`, `client/app/src/chain.ts`,
`pnpm-lock.yaml` (no new dependency), `tools/site/**`, `.github/`, `docs/design/**`. `sandbox/
imports.test.ts`: assertions may be added, no guard loosened. Anything else is an escalation in the
report, not an edit.

## Interfaces

- `render/sprites.ts`: `SpritesIndex.pages[i].group?: "world" | "ui"`; `SpriteEntry.ui?: UiSlices`
  with `kind`, `fill`, `slice`, `content`, `outset`, `drop?`, `states?`.
- `render/atlas.ts`: `loadAtlas` loads the `world` pages only; the map draws exactly as before.
- `chrome/scale.ts` (pure): `cutScale(dpr)` (device px per art px), `toDevicePx(artPx, dpr)`, the
  CSS lengths of a slice; unit-tested.
- `chrome/load.ts`: `loadChrome(base, dpr, loaders?) → ChromeImages | null`, where `ChromeImages`
  maps an entry and state to an object URL and its slice lengths; injectable loaders (fetch, image
  decode, canvas) so it is tested without a browser.
- `chrome/Chrome.tsx`: `ChromeProvider`, `Panel`, `Button`, `IconButton`, `Ribbon`, `Icon`; the
  root's `data-chrome` attribute (`atlas` or `plain`) and `data-chrome-dpr`.
- Intents, the machine, `placeholders.ts`, the map's `sprites.json` roles: unchanged.

## Acceptance criteria

- [ ] AC-1 **Presentation only**: `git diff origin/main --stat` lists only allowlisted files;
      `git diff origin/main -- client/app/src/sandbox/placeholders.ts client/app/src/sandbox/loop/machine.ts`
      is empty (in the report); the loop's and the room's tests (`machine`, `hubDoors`,
      `walkFollowsPreview`, `wiring`, `session`, `placeholders`) pass unmodified.
- [ ] AC-2 **The pipeline** (`tools/art` tests, synthetic sheets only): a lattice nine-slice is
      composed contiguous with its margins as `outset`; a three-slice row is cut from a multi-row
      sheet; a pressed sheet with another layout is refused; a wrong `drop`, an inset outside the
      frame and a non-uniform edge are refused; `ui` frames land only on `ui` pages; the existing
      tests pass unmodified.
- [ ] AC-3 **The index** (unit): `readSpritesIndex` accepts a valid `ui` entry and `group`, and
      refuses each malformed field; `loadAtlas` never loads a `ui` page (a test on fake loaders).
- [ ] AC-4 **The cut and the scale** (unit, fake canvas): at pixel ratios 1, 1.25, 1.5, 2, 2.625 and
      3 the cut image's size is the frame × `cutScale(dpr)`, the slice lengths are whole device
      pixels, and the CSS `border-image-width` maps one image pixel to one device pixel; a ratio
      change re-cuts and revokes the old URLs.
- [ ] AC-5 **Contrast** (unit): for each component, its text colour against its surface's centre
      colour (copied from `report.json` as numbers) is ≥ 4.5 : 1 for body text and ≥ 3 : 1 for the
      large button and ribbon labels, in the normal and pressed states.
- [ ] AC-6 **The browser check** (`verify:chrome`, VPS, headless Chromium), with the atlas built from
      this branch (never committed), at **375 × 812** (touch) and **1440 × 900**, each at
      `deviceScaleFactor` **1, 2 and 3**, on **every screen**: the town and the outpost, one
      service stub, the Gate screen, the entry moment (with a long `?entry=`), the instance, its
      confirmation dialog, the closing report (returned and defeated), and at 1440 the desktop's
      side panels. For each: `data-chrome="atlas"`; every `button` and link has a bounding box of
      at least 44 × 44 CSS px; no element overflows the viewport horizontally; no label is
      clipped (`scrollWidth ≤ clientWidth` on every plate and button); a keyboard Tab reaches each
      button and shows the focus outline; a pointer-down shows the pressed image (the computed
      `border-image-source` changes) and the label moves by the drop; no page error.
- [ ] AC-7 **No layout regression**: the same check on `origin/main` (built in a temporary worktree
      the thread creates and removes by its exact path) records, per screen and size, the boxes of
      the map, the header, the service row and each button; on this branch the map's box is the
      same or larger at every screen and size, and no control has moved out of the viewport or
      under another. Differences are listed in the report.
- [ ] AC-8 **The fallback**: with no art (`GRIMWORLD_ART_OUT` pointing to an empty folder), every
      screen has `data-chrome="plain"`, the same boxes as `main` within 1 px, and no page error.
- [ ] AC-9 **Forced colours**: with `forcedColors: "active"` emulated, every control still shows a
      border and its text (checked on the hub and the confirmation dialog).
- [ ] AC-10 **Shots**: with `VERIFY_SHOTS=1`, a shot of every screen at both sizes and pixel ratio 2,
      and the hub at ratios 1 and 3, into the thread's library folder, **untracked**, never
      committed, attached or posted (D-73); the thread looks at them for seams, blur and clipped
      text, and describes them in words in the report.
- [ ] AC-11 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`,
      `pnpm exec prettier --check client indexer`, `tools/art/.venv/bin/python -m unittest discover
      -s tools/art/tests` and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-12 **The owner's eye, after the merge**, on https://grimworld.bal7hazar.com: it does not
      block. A remark on a colour, a size (`CHROME_SCALE`) or an element's choice is a fix lot; a
      remark on the method goes back to *The method*.

## Verification

- On the VPS: the commands of AC-11; `tools/art/build.py` with the uncommitted `assets` symlink,
  removed afterwards; then `verify:chrome` (AC-6 to AC-10), on this branch and on `main`.
- Start and stop the dev server inside one foreground command; signal only its recorded process
  group (never a search by name). Remove the temporary `main` worktree by its exact path.
- `git fetch origin` and merge `origin/main` before every push; `scripts/prepush.sh`, never
  `--no-verify`. Do not poll CI: push, open the pull request, end the turn.

## Review and audit

- **Review** on another model than the implementer's: `review` (Sonnet) for an Opus implementer.
  It checks most closely: nothing outside the allowlist and no rule touched; the fallback equal to
  `main`; the scale arithmetic and whole-device-pixel insets; the contrast test's figures and the
  colours actually used; tap targets and focus; object URLs revoked; `ui` pages kept out of PixiJS;
  the build's new checks; D-73 (no image in the diff, the pull request or the report).
- **Audit**: none (D-177; presentation only, the owner sees it). The orchestrator decides otherwise
  if the lot adds a dependency or leaves the allowlist.

## Rules of the run

- D-73: nothing of the pack committed or posted; sizes, counts, colours as hex values and words
  only. The shots stay untracked in the library folder.
- No pin, fingerprint or byte count committed.
- External issues named in words, not links, in commit messages and pull request text.
- Pull request title: `[<model>] CLI-03i the client chrome from the pack's UI`; body through REST
  (`gh pr edit` fails on Projects-classic): the method as built, the contrast table as built,
  "Audit: none (D-177)", "Owner's eye: on the public site after the merge".

## Report

`docs/reports/CLI-03i-client-chrome.md`, as in `docs/briefs/COMMON.md` §7, with: the method as
built and any deviation (which text option of §5 was built and why); the manifest's entries and the
UI page's size from the build's report; the contrast figures; the tap-target and layout figures of
AC-6 and AC-7 with `main`'s; the shots described in words and where they are; the tests updated and
why; `git diff origin/main -- client/app/src/sandbox/placeholders.ts`; commands refused;
escalations; open questions.

## Open questions

1. **Decided (orchestrator, 2026-10-02): one lot for the whole client** (CLI-03e's Q3). Split into
   CLI-03i1 / CLI-03i2 only if the reviewer asks (*Size*).
2. **For the orchestrator: a display font.** The pack has none. Default: **none in this lot**;
   `system-ui` stays, with bold large labels on buttons and ribbons. Reverse: a pixel display font
   under the SIL Open Font License, bundled from an npm font package (a dependency and a lockfile
   change, hence its own small lot, read by the orchestrator for an audit), for titles, ribbons
   and buttons only; body text stays `system-ui` for legibility at 15 px.
3. **Decided (this brief, reversible by the orchestrator): the colours of meaning.** Blue for
   actions, red for the Gate and the second tap of I-5, yellow ribbons for place names, special
   paper for the Gate's reminder and the desktop panels. The Blue faction of CLI-03e is kept.
   Reverse: one table in *Screens and components*.
4. **For the orchestrator, later lots**: the bars and state icons (with the HUD, CLI-05 / CLI-08),
   the avatars (a character sheet), the sword plates and the cursors (desktop). None is cut now.
5. **For the project manager: text that scales with the system** (design/11 *Accessibility*). The
   client sizes text in `px` today; moving to `rem` is a client-wide change outside this lot. The
   chrome's nine-slices grow with their content, so it will not block that change.
6. **For the orchestrator: the PLAN row.** CLI-03i has no row in `PLAN.md`; the orchestrator adds it
   with this brief's merge.
