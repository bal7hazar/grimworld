# CLI-09a2 — The map editor: an unbounded canvas, and chunks fitted afterwards

Lot CLI-09a2 of `docs/briefs/CLI-09-map-editor.md` (§9), track CV, 2026-10-05. The owner's request
(**D-216**): "I would like the chunks to be computed afterwards, that is, to have a theoretically
infinite map, and once finished we apply a grid of chunks to define the best partition rather than
having to define that number from the start." It changes CLI-09a's model (#361).

## What exists now

- **An unbounded map** (`editor/model.ts`). Only the painted hexes are stored, one number per hex in a
  `Map` keyed by `(x, y)`: the terrain bit, the ground and, for a zone, "outside the outline". Any
  coordinates within ±32,767 (`COORD_MAX`), negatives included. An unpainted hex is the void. Erase
  unpaints. The new map dialog asks the kind, name, location id and biome only: no size, no start fill.
- **Pan and zoom with no map edge.** `0` fits the painted hexes, or a 3 × 2-chunk area at `(0, 0)` on an
  empty map. The zoom goes out to the painted hexes or 255 × 255 tiles (a full zone and a chunk around
  it), whichever is larger.
- **Rendering through the game's `Renderer`, unchanged** (`render/**` untouched). Only what is near the
  view is sent to it (`view.ts`, `canvas.ts`):
  - the **window** is the visible tiles, grown by half the view on each side and snapped outward to
    multiples of 15, so that the renderer's baked chunks (`BAKE_CHUNK`) keep their keys while the camera
    moves inside it;
  - the window is rebuilt when the document changes, or when the camera's visible tiles leave it (every
    pan, zoom and resize checks it);
  - the renderer gets the window's part of the painted box, grown by 3 hexes: the painted hexes, and the
    unpainted ones as water walls. The renderer draws its void only outside its tiles' box shrunk by two
    hexes (`voidHole`), so a gap in the painting reads as the same water as the void beyond.
  - A view far from any painted hex sends nothing. The renderer's void then reaches 100,000 art px
    (`VOID_REACH`) around `(0, 0)`, and beyond that the page's background shows.
- **No chunk grid while painting.** The "Fitted chunks" layer (CLI-09a's "Chunk seams") is off by
  default. "Fit chunks" turns it on; the author may toggle it, and it always shows the last chosen grid.
- **The outline and Fill on the sparse map.** The outline sorts painted hexes into inside and outside;
  a painted hex starts inside, and an unpainted hex is neither. Fill on a painted hex takes its
  connected region of the same terrain and ground, bounded by the painted hexes. Fill from the Outline
  tool takes the painted hexes on the same side of the outline. **Fill on an unpainted hex** works only
  in a region closed by painted hexes:
  - its search is confined to the painted hexes' box grown by one hex, and a region that reaches that
    ring is "open" and refused with its reason;
  - no fill takes more than **50,625 hexes** (`FILL_MAX`, a 15 × 15-chunk zone);
  - on an empty map, Fill is refused.
- **"Fit chunks"** (`editor/fit.ts`; inspector button, `Shift+0`):
  - **It tries all 15 × 15 origins** compatible with the hex layout and keeps the one that covers the
    map's hexes with the **fewest chunks**.
  - **Ties** go to the fewest partly filled chunks, then the smallest fitted rectangle, then the lowest
    origin row, then the lowest origin column.
  - **It shows** the grid (dashed seams around the chunks of the set, each chunk's index), the chunk
    count, the partly filled count, the fitted rectangle and where global `(0, 0)` lies, and the chunk
    cells of §2.5.
  - **Nudge:** `Shift`+arrows or four small buttons move the origin one hex West, East, North or South,
    as on screen. The counts follow at once, and the origin is marked "nudged".
  - **Painting after a fit** shows "Painted since: Fit chunks again".
  - **Not in the undo history:** the origin is the document's and is saved with it, but undo does not
    move it.
- **The map's hexes** (what the fit covers) are a town's painted hexes, and a zone's painted hexes
  **inside its outline**. The game draws the outside as void and the export ignores it (§4.4). Fitting
  it would add chunks that no record keeps. This also makes a converted format 1 map, painted
  wall-to-wall, fit its outline rather than its old rectangle.
- **Validation and export read the fitted result** (`fitted(doc)`):
  - the origin and the fitted rectangle;
  - the **chunk set** (`15 cy + cx`) and the border chunks' **tile masks** (`15 row + column`), in the
    fitted map's coordinates;
  - the problems: a fitted map past 15 chunks on a side for a zone, or 4 for a town or an outpost.

  The document keeps the origin and how it was chosen, and the chunk set and masks are derived from
  them, ready for CLI-09c. The inspector's outline line and the map list's "Chunks (fitted)" read them.
- **Files, format 2** (`editor/file.ts`):
  - The painted hexes are written as row spans `{ y, x, terrain, ground, outline? }`: one row from
    column `x` on, one character per hex, a space for an unpainted hex.
  - The objects (pinned obstacles) are written as before.
  - `chunks` holds the last chosen origin `{ x 0–14, y even 0–28, how: fitted | nudged }`, or null.
- **Format 1 files (CLI-09a) still open, converted:**
  - every hex of the old rectangle is painted as it was, the start fill included;
  - the outline is kept;
  - the chunk grid stays at `(0, 0)`, marked `nudged` because it was set by hand, not by the fit;
  - a note is shown in the top bar.

  Saving writes format 2. A newer or broken file is still refused with its reason. Drafts go through
  the same reader, so an old draft and its old list entry still open.
- **CLI-09a's three deferred minors** (review t-0114 of #361):
  - (a) The draft writer (`DraftWriter`) flushes a pending write when the screen unmounts and on
    `pagehide`, so a closed tab loses nothing. Save writes at once and cancels the pending write.
  - (b) The Space pan mode ends on its key's release, on `blur` and on `visibilitychange` to hidden
    (`spaceHold.ts`).
  - (c) Undo and redo end a stroke in progress first. The stroke becomes one step before the undo, and
    the moves until the release draw nothing.
  - Duplicate on the map list shows "Not duplicated: this browser refused the draft" when the storage
    refuses the copy.
- **The brief** is updated where D-216 changes it: §2.2, §2.3, §3, §4.1, §4.4, §6 and a CLI-09a2 row in
  §9. Each change is marked "owner's request, 2026-10-05; D-216".

## The parity rule, and where it comes from

The rule is derived from odd-r: `input/coords.ts:45` shifts every odd row by half a hex, so a
hex's neighbours depend on whether its row is odd. It is the same reason as the window's even origin
in ADR-0006 l.236 ("the library derives every neighbour from the parity of the **local** row"). The
fitted map is the editor's plane moved so that the origin is global `(0, 0)`. A move by an **odd**
number of rows would give every row the other parity's neighbours and turn the painted shape into
another shape. So **the origin's row is even.**

Seams repeat every 15 rows, and 15 is odd. Each row residue `r` therefore has exactly one even origin
row below 30: `r` itself, or `r + 15` (`evenRow`). The 15 column residues and the 15 row residues are
all tried, 225 origins in all. When the even origin row lies a whole chunk below the lowest painted row,
the fitted map keeps an **empty chunk row at its foot** (`lowRow`). The chunk set is the same; only the
rectangle is one row higher. The tie-break prefers an origin without it. A test checks that the move
keeps every neighbour on even, odd and negative rows, and that a one-row shift does not.

## The fit's complexity and time (AC-2)

The fit does not loop over 225 origins × the painted hexes. It builds one **summed-area table** of the
map's hexes over their box, O(box area). It then counts each chunk of each origin in four reads,
O(225 × the chunks of the rectangle). The painted box is bounded at 1,000 hexes a side
(`FIT_SPAN_MAX`); past it, the fit is refused with a message.

Measured by `src/editor/fit.test.ts` ("the fit's time (AC-2)"), on a 225 × 225 painted map (50,625
hexes) on the VPS:

```
[AC-2] fit of 225 × 225 painted hexes: median 11.9 ms of 5 (10.8, 11.2, 11.9, 12.5, 40.3)
```

## Acceptance

| AC | How it is shown | Result |
|---|---|---|
| AC-1 | `model.test.ts` (sparse paint, erase, fill, closed and open holes, `FILL_MAX`, outline far from the origin and below zero), `fit.test.ts` (hand-computed layouts: one hex, aligned and odd-row blocks, a far negative 3 × 2 block, the partly filled tie-break, a plus sign, a zone's inside only; the parity rule; the nudge; the fitted records), `file.test.ts` (format 2 round trip compared equal; format 1 → 2 converted and refused when broken; refusals), `session.test.ts` (the three minors and Duplicate), `overlay.test.ts`, `history.test.ts`, `keys.test.ts` | 64 editor tests pass |
| AC-2 | The timing test above | Median 11.9 ms of 5 |
| AC-3 | `node client/app/verify-editor.mjs` at 1440 × 900, with the site's built atlas (`GRIMWORLD_ART_OUT=/home/claude/site/grimworld/current/art`, read only) and plain | All checks pass in both looks. The run covers: a zone created with no size; painted at x 95..135, y 37..61; outlined; fitted (3 chunks, 3 partly filled, origin (0, 12)); nudged to origin (1, 28), with an empty foot row; saved, reloaded and saved again, byte for byte; a newer file refused; a format 1 file converted; a stroke kept by a reload within 400 ms (225 → 222 hexes listed); a blur ending the pan mode. Captures in the thread's library folder only (D-73) |
| AC-4 | `pnpm --filter @grimworld/app test`, `lint`, `typecheck`; `pnpm build`, then the game's `index.html` and its preloads grepped for the editor's strings | 521 passed, 1 skipped. Lint and typecheck clean. Only `editor-*.js` carries the editor |

## Choices and why

- **A zone fits its inside hexes, not every painted hex.** The task says "the painted hexes". For a
  zone, the painted hexes outside the outline are void in the game and ignored by the export, so the
  chunks only need the inside ones. For a town, and for a zone whose outline was never narrowed, the
  two are the same. To reverse: `mapKeys` returns every painted hex.
- **Unpainted hexes are drawn as water walls** near the painting, the same look as the game's void
  around a zone or a hub. An unpainted gap therefore reads as void, not as the page's background.
  Painted water looks the same; the inspector says "Not painted (void)" on hover.
- **The origin is not a step of the undo history.** It is a setting of the fit, saved with the
  document. Undoing paint should not undo a fit.
- **Converted format 1 maps keep their grid at `(0, 0)`, marked `nudged`.** It was chosen by the author
  (the old size), not by the fit. One `Shift+0` gives the best grid.
- **`Shift+0` and `Shift`+arrows** avoid new letters: §3's rule leaves no free tool letter that is at
  the same place on AZERTY and QWERTY and unbound by the game. They pair with `0` (fit the view) and the
  arrows (pan).

## Review of #362 (t-0117, PASS WITH FINDINGS), the three minors fixed

1. **The tiles sent to the renderer are capped at `VIEW_MAX` (250,000).** Past it, the window's
   painted hexes alone are sent, up to that many, and the renderer's void draws the water between
   them. The overlay's outside shading also stops past that many hexes in view. Tests: a file with one
   hex at (−32767, −32767) and one at (32767, 32767) opens, renders, outlines and refuses its fit in
   well under a second; two 30 × 30 islands 2,000 hexes apart, zoomed out over both, send their 1,800
   painted hexes.
2. **The parity comment** (`fit.ts`) and the paragraph above cite odd-r (`coords.ts:45`) and ADR-0006
   l.236 with its full quote.
3. **Brief §3, Delete selection:** "selected hexes unpainted (back to the void)", marked.

Of the optional notes, `regionOf` now treats a hex past the plane's bound as open. The fit's ranking
is unchanged: a rectangle past `SIZE_MAX` is shown as a problem rather than ranked lower.

## Deviations

- None from the allowlist. `render/**` is untouched; the renderer needed no change.
- Prettier is not run on the brief, since the pre-push hook checks `client` and `indexer` only. The
  brief keeps its own formatting, and its diff is only the D-216 changes.

## Not checked

- No phone or touch (O-3).
- The view far from any painted hex beyond `VOID_REACH` (100,000 art px, about 1,560 hexes from
  `(0, 0)`) shows the page's background rather than water; not exercised in the browser.
- The export itself is CLI-09c's (it waits for ENG-08's spike). Here, `fitted(doc)` only holds what it
  will read.
