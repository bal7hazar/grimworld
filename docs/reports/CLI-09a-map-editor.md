# CLI-09a — The map editor: page, canvas, paint, outline, save and load

Lot CLI-09a of `docs/briefs/CLI-09-map-editor.md` (§9). Track CV, 2026-10-05. Open questions O-1 to O-8
as the brief decides them.

## What exists now

- **A second page** (O-1): `client/app/editor.html` → `src/editor/main.tsx`, a second
  `build.rollupOptions.input` in `vite.config.ts`. Served at `/editor.html` by the dev server and by the
  site; no link from the game (O-2). Plain chrome (`data-chrome="plain"`, `system-ui`, sizes in rem, O-4).
  Below 700 CSS px wide it shows one line, "The map editor needs a desktop window." (O-3).
- **The map list** (§2.1): the drafts of this browser (kind, name, size, location id, edited), each with
  Open, Duplicate, Download, Forget (asks first); "+ New map"; "Open file…" (and a file dropped on the page).
  The Problems column shows "—" until CLI-09b's validation.
- **The new map dialog** (§2.2): kind (zone, town, outpost), name (≤ 15 characters), location id, size in
  whole chunks (1–15 a side for a zone, 1–4 for a town or an outpost) with the size in tiles, biome (zone
  only), start as all wall or all floor. Escape cancels, Enter creates.
- **The canvas**: the game's `Renderer`, **unchanged**, on a world built from the map (`editor/view.ts`):
  every hex revealed and in sight, the void as water, no actor. Over it a 2D canvas draws the overlays as
  plain shapes in the renderer's camera after each of its frames: the grid, the chunk seams (dashed, with
  each chunk's index), the outline's border, the outside of the outline shaded, the brush under the pointer.
- **Camera**: wheel (and a trackpad's pinch) zooms at the pointer, a sideways two-finger scroll pans,
  middle drag or Space + left drag pans, the arrows pan (repeating), `+`/`=`/`−` zoom, `0` fits the whole
  map. The zoom is the game's `DEFAULT_ZOOM` with `minAcross` raised so the whole map fits.
- **Tools** (§3): Paint `B`, Erase `N` (and right drag with a brush tool), Fill `G`, Pick `I` (and
  Alt + click; Pick returns to the tool before it), Outline `T` (zones; right drag marks outside; Fill
  armed from it fills the outline, bounded by it; "Outline from floor" in the inspector). Brush radius 0–3
  (1, 7, 19, 37 hexes) by `[`/`]`, Shift + wheel or the buttons. Palette: terrain (floor, wall) and ground
  (grass, earth, water); a swatch arms Paint.
- **Layers bar**: ground, obstacles, objects, outline, chunk seams, grid; `J` toggles the grid, `K` walks
  the bar, `Shift+K` toggles the focused layer. Ground off draws every hex as grass; obstacles off draws
  walls with the renderer's unrevealed look (a flat dark hex). Objects has nothing to show until CLI-09b.
- **Undo and redo** (O-7): 200 steps in memory; a stroke (press to release), a fill or "Outline from
  floor" is one step; each step holds only the hexes it changed. `Ctrl/Cmd+Z`, `Ctrl/Cmd+Shift+Z`,
  `Ctrl+Y`, and the top bar's buttons.
- **The inspector, in part**: the hovered hex (global `(x, y)`, chunk index and `(cx, cy)`, tile index,
  terrain, ground, obstacle look, inside or outside), the map's properties (read only), and for a zone
  the chunk set as a 15 × 15 grid of cells (whole, border, outside) with its counts (§2.5).
- **Save and load** (§6): `Ctrl/Cmd+S` (or Save) writes the draft and downloads `<name>.grimmap.json`;
  "Open file…" / `Ctrl/Cmd+O` / a dropped file loads one. A file that fails to read, or of a newer
  format version, is refused with the reason and the open map is not touched.
- **Drafts** (O-5): the open map is written to local storage 400 ms after each change; every read and
  write is guarded and the editor works without the storage.

## The editor's file (`.grimmap.json`, format version 1)

The editor's own (§4, §6); the registration export is CLI-09c's, in ENG-08's schema.

```
{ "format": "grimworld-map", "version": 1, "editor": "<VITE_GRIMWORLD_COMMIT or dev>",
  "map": { "kind", "name", "location", "width", "height", "biome", "start",
           "levelMin", "levelMax", "rank", "spawnTable" },
  "layers": { "terrain": [rows], "ground": [rows], "outline": [rows] | null },
  "obstacles": [ { "x", "y", "sprite" } ] }
```

A layer is a list of rows, `y = 0` first, one character a hex, `x = 0` first, in the chain's global
coordinates (x West, y North, odd-r): terrain `.` floor `#` wall; ground `g` grass, `e` earth, `w` water;
outline `1` inside `0` outside (a zone only; `null` for a town or an outpost). Pinned obstacle looks are
names of stills, never pixels (§7); CLI-09a writes none. A 15 × 15-chunk zone saved by the browser check is 156 963 bytes.

## Acceptance

- **The brief's row**: `src/editor/file.test.ts` "a 15 × 15-chunk zone round-trips through its file"
  creates the zone, paints (a brush of radius 3, water, an earth fill), outlines (from the floor, then a
  right drag outside), saves, loads: `expect(back).toEqual(doc)`, and saving again gives the same text.
  In the browser, `verify-editor.mjs` does the same at 1440 × 900 (below).
- **AC-1**: `model.test.ts` (the document, indices, brushes, paint, erase, fill, pick, the outline's chunk
  set and masks, outline from floor, R-11 by construction), `history.test.ts` (a stroke is one step; 201
  steps keep 200, 200 undos and 200 redos), `session.test.ts` (the tools on strokes, Pick's return, the
  outline's fill, a town without an outline, drafts with no storage and a throwing one), `file.test.ts`
  (the round trips, refusals with their reasons). `pnpm --filter @grimworld/app test`: 48 files, 497
  passed, 1 skipped (40 of them the editor's, in 6 files).
- **AC-2**: `pnpm --filter @grimworld/app build` emits `dist/index.html` and `dist/editor.html`.
  `index.html` loads `assets/main-*.js` and the shared chunk `assets/keyScope-*.js` (the game's modules the
  editor also imports); neither holds an editor string (`grep -c -E "grimworld-map|grimworld\.editor\.drafts|The map editor needs"` prints 0 on both, 1 on `assets/editor-*.js`), and
  `overlay.test.ts` checks that no module outside `src/editor/` imports from it. `tools/site/` is
  untouched: `deploy-site.sh` runs `pnpm --filter @grimworld/app build` and copies the whole `dist/`, and
  the Caddy block's `try_files {path} /index.html` serves `/editor.html` as the file it is.
- **AC-3**: `node verify-editor.mjs` with `GRIMWORLD_ART_OUT=/home/claude/site/grimworld/current/art`
  (read only), in two looks, the art (`data-atlas="loaded"`) and the plain look (`/art/` answered 404,
  `data-atlas="none"`): the list opens empty; a 15 × 15-chunk zone is created; painted (2421 floor hexes);
  outlined (807 inside, 49818 outside; 9 chunks in the set, 9 on the border); saved (the draft, and a
  download of format 1); after a page reload the draft is listed; the file opened again and saved again
  is the same file byte for byte; a file of version 2 is refused and the open map stays; below 700 px the
  one line shows; no request beyond the page's origin; no page error. `ALL CHECKS PASSED`. A screenshot of
  each step (create, paint, outline, save, reload) in each look went to the thread's library folder: not
  committed, not posted (D-73).
- **AC-4**: `test` as above; `lint` and `typecheck` clean; `prettier --check client` clean (the pre-push
  hook ran them all). The existing verify scripts: see *What was checked of the others*.
- **AC-5**: `keys.test.ts`: the tool letters (B, N, G, I, T) are read by `event.code`, arm the same tool
  whatever character the layout prints there, and are among §3's same-place letters; A, Q, W, Z and M
  (AZERTY's M is `KeySemicolon`) arm nothing on either layout; no tool code, J or K is a code the game's
  `BINDINGS` binds or reserves; Ctrl+Z is undo on QWERTY (`KeyZ`) and AZERTY (`KeyW`, key `z`), and
  AZERTY's `KeyZ` with Ctrl (key `w`) is not; symbols by character (AZERTY's `=` and `-`, `[` with AltGr).

## Choices made in this lot (reversible)

1. **Overlays on a 2D canvas over the renderer's**, in its camera (`cameraState()`, redrawn on its
   `onDraw`), so the renderer stays the game's, unchanged.
2. **Ground off / obstacles off** are drawn with what the renderer already has: grass everywhere, and the
   unrevealed look for walls. A **pinned obstacle look** cannot be shown without a renderer change: see
   *Escalations*.
3. **Default ground is grass for every biome** (the brief: "the biome sets the default ground"); one
   grass is all the atlas draws today. A table per biome when a second ground is drawn.
4. **A new zone starts wholly inside its outline**; the author cuts it (right drag with `T`, Fill, or
   "Outline from floor").
5. **"Outline from floor" without an entry** (objects are CLI-09b's) takes the largest connected floor
   region; once an entry exists, CLI-09b passes it.
6. **Neighbours** are the drawing's (`acrossSide` of `render/ground.ts`), tabled once per map size:
   `sandbox/placeholders.ts` may be imported by the wiring and the machine only (`imports.test.ts`).
7. **Trackpad**: a wheel event with a sideways delta pans, a pinch (Ctrl) or a plain wheel zooms.
8. **Validation light, Export…, Walk ▸, Select and Place** are not on the screen yet (CLI-09b, CLI-09c).
9. **A layer checkbox gives the keys back** after a toggle: the game's key scope ignores keys typed in any
   `input`, so a focused checkbox would swallow Ctrl+S.
10. **Small hexes are shaded by runs of a row** (a rectangle a row high from flat side to flat side) below
    14 CSS px a hex: the outside of a 225 × 225 map was ~50 000 polygons a frame and blocked the page.

## Deviations from the task

- None of the allowlist: files under `client/app/src/editor/`, `editor.html`, `verify-editor.mjs`, the second
  entry in `vite.config.ts`, and this report.

## Escalations

- **Pinned obstacle looks need a renderer change** (for CLI-09b's inspector): the renderer chooses a wall's
  still by `obstacleOf(tile, …)` alone. The change I would make: an optional `obstacle?: string` on
  `ViewTile`, used by `syncObstacles` before `obstacleOf` when the atlas has that still. Not made
  (`render/**` is not this lot's).

## What was not checked

- A real trackpad and a real AZERTY keyboard: the layout claims are checked on `event.code` and `event.key`
  values in tests, the gestures only with Playwright's mouse.
- Frame times on a desktop GPU: headless Chromium renders in software; the first frame of a whole
  225 × 225 map blocks the page for about 2.5 s there (a `page.evaluate` measured during it).
