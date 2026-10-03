# [Opus 5.5] CLI-03k — Keyboard control for zones and hubs (desktop)

Brief: `docs/briefs/CLI-03k-keyboard.md` (PR #342). Model read from the session: Opus 5.5, as the
brief names. Audit: none (D-177). Owner's eye: on the public site after the merge.

## Summary

- On a desktop window, zones and hubs are played by keys: one hex per press, places selected and
  walked to, the service row, the Gate's Leave, the camera, a key help. Every key sends the intent
  of the tap or button it stands for: a map `Intent` through `SandboxController.apply` (so a hub's
  `route` sees it), a `LoopIntent` through the screen's `dispatch`, or `cancelWalk`, `recentre`,
  `zoomBy`. No new intent kind, no rule, no second path into the session or the machine.
- `input/keys.ts`: one table, `BINDINGS`, read by the key map (`keyCommand`) and listed by the key
  help; the combat keys of design/11 *Desktop* are in it as reserved.
- `sandbox/keyScope.ts`: one counted document listener, a stack of key layers (only the top one
  hears), the text-field and Enter-on-a-button guard; the screen-root focus hook.
- `sandbox/loop/keyTargets.ts`: a hub's places in the service row's order, a zone's hub gates, the
  wrap, and the taps' own intents for `Enter`, `1`–`9` and `L`.
- `verify:keys`: the keyboard in headless Chromium at 1440 × 900, keyboard only, and AC-7's
  375 px comparison with `main`.
- design/11 *Desktop*: one row, "Keyboard, outside combat (CLI-03k)" (the project manager's ruling
  on Q6, 2026-10-03, under D-178's lending).

## The bindings as built

| Keys | Screens | What it does |
|---|---|---|
| `Q` `W` `E` / `A` `S` `D` (by `event.code`) | hub, instance | One hex West, North-West, North-East / South-West, South-East, East: a tap on that hex |
| `←` `→` | hub, instance | One hex West, East |
| `↑` `↓` | hub, instance | The upper or lower hex on the side faced (facing E, NE, SE: NE / SE; else NW / SW) |
| `F` / `Shift+F` | hub, instance | Next / previous place: a hub's buildings in the service row's order, a zone's hub gates (lowest id first); wraps |
| `Enter` (and `NumpadEnter`) | hub, instance | A tap on the selected place's door, or the gate's anchor |
| `1`–`9` (digit row and numpad, by code) | hub | The service row's buttons in order; past the row, nothing |
| `L` | instance | The Leave control: the I-5 dialog, on a hub gate's anchor only |
| `Esc` | every screen | Top first: the key help, the I-5 dialog (Stay), a hub's inspection, the planned walk, the selection, then ‹ Back on a service or the Gate screen |
| `0` (digit row and numpad) | hub, instance | ◎, back to the adventurer |
| `+` `=` `NumpadAdd` / `-` `NumpadSubtract` | hub, instance | One wheel notch in / out, around the map's centre |
| `?` (by `event.key`) | every screen | The key help |
| `1`–`8`, `Z X C V`, `Space`, `R` | instance | Reserved for CLI-05 / CLI-08: bound to nothing, listed greyed "later" |

Never with `Ctrl`, `Meta` or `Alt`; `Shift` only for `Shift+F` and `?`; an auto-repeat or a
composition is nothing; a key typed in an `input`, `textarea`, `select` or editable element is
left to it; `Enter` on a button or link is the browser's; `Tab` is never bound (inside the I-5
dialog it loops over Stay and Leave).

Focus: a new screen focuses its root (`tabIndex={-1}`, no ring); the entry screen focuses Skip,
the report "On to …". The I-5 dialog focuses Stay; on closing the focus returns to the control
that opened it, or to the screen. The key help focuses its ✕ and gives the focus back. The focus
ring (`chrome.css`) now applies in both looks, and to the selected place's name
(`.gw-key-selected`) and the ring on its hex (`.gw-key-marker`). "Keys ?" sits in the desktop's
left panel only.

## Files changed

New: `client/app/src/input/keys.ts`, `keys.test.ts`; `client/app/src/sandbox/keyScope.ts`,
`keyScope.test.ts`; `client/app/src/sandbox/loop/keyTargets.ts`, `keyTargets.test.ts`,
`KeyHelp.tsx`; `client/app/verify-keys.mjs`; this report.

Changed: `input/gestures.ts` (`WHEEL_NOTCH`), `sandbox/wiring.ts` (`stepTarget`),
`wiring.test.ts`, `sandbox/controller.ts` (`step`, `zoomBy`, `lookAt`), `controller.test.ts`,
`render/renderer.ts` (`lookAt`, at the class's end), `renderer.test.ts`, `sandbox/Sandbox.tsx`,
`loop/HubScreen.tsx`, `loop/InstanceScreen.tsx`, `loop/screens.tsx`, `loop/Loop.tsx`,
`chrome/chrome.css` (the ring's selectors), `client/app/package.json` (`verify:keys`),
`docs/design/11-interface.md` (one row, by the ruling on Q6).

## Commands run

- `pnpm --filter @grimworld/app test`: 38 files passed, 1 skipped; 416 tests passed, 1 skipped.
- `pnpm --filter @grimworld/app lint`, `typecheck`, `build`: pass.
- `pnpm exec prettier --check client indexer`: "All matched files use Prettier code style!".
- `pnpm --filter @grimworld/app verify:keys` (with `VERIFY_SHOTS`, `VERIFY_PHONE_BASE`):
  101 checks ok, "ALL CHECKS PASSED", atlas loaded.
- `verify-keys.mjs` with `VERIFY_ONLY=phone VERIFY_PHONE_OUT=…` in a temporary worktree of
  `origin/main` (d42d87e), created and removed by its exact path: "ALL CHECKS PASSED".
- `verify:ground`: "ALL CHECKS PASSED". `verify:hubs`: see *Deviations*.
- `scripts/prepush.sh` before the push.

The browser checks served the atlas through `GRIMWORLD_ART_OUT`, pointed read-only at the site's
built atlas of `main` 5142f76 (`/home/claude/site/grimworld/releases/5142f76…/art`): only the built
atlas and `sprites.json`, never the pack's files; nothing linked or copied into the worktree.

## Acceptance criteria

- AC-1 **Input only.** `git diff origin/main --stat` lists the files above (all in the allowlist,
  plus design/11 by the ruling). The diff of `placeholders.ts`, `loop/machine.ts`,
  `loop/hubDoors.ts` and `input/intent.ts` against `origin/main` is empty (0 bytes). The tests
  `machine`, `hubDoors`, `walkFollowsPreview`, `session`, `placeholders`, `hubTaps` and `imports`
  pass unmodified; `wiring.test.ts` only gains cases.
- AC-2 **The key map**: `keys.test.ts` (21 tests): the ring on hub and instance and `null`
  elsewhere, AZERTY by code, the arrows, every binding `null` with Ctrl, Meta or Alt, repeat and
  composition `null`, `Shift+F` back and Shift with another bound letter `null`, the digits and
  numpad on hub only, `L` on instance only, `?` by key everywhere, the zoom and `0` keys, the
  reserved keys `null` and listed as reserved, no `Tab`, one meaning per key per screen.
- AC-3 **Same intents as taps**: `wiring.test.ts` (`stepTarget` equals `neighbour` in six
  directions and resolves ↑ / ↓ by facing, on both row parities); `controller.test.ts`
  (`step(d)` hands the injected router exactly `{ kind: "tile", tile: neighbour }`; `zoomBy` is
  one notch at the viewport's centre, in then out restores the scale; `lookAt`);
  `keyTargets.test.ts` (Enter on a place routes through `HubDoors` exactly as a tap on its door,
  on and off the door; `service i` is `targetIntent(view.services[i])`; `L` off an anchor is
  nothing); `renderer.test.ts` (one notch in then out restores the scale; `lookAt` then
  `recentre`).
- AC-4 **Targets and scope**: `keyTargets.test.ts` (both hubs' row order; the zone's hub gates,
  one on its entry tile; `nextTarget` with 0, 1 and 4 targets, both ways);
  `keyScope.test.ts` (top layer only, pop on close, closing a lower layer; `ignoredTarget`).
- AC-5 **The browser check**: the zone reached by `Shift+F`, `Enter`, `Tab` … `Enter`; each of the
  six keys and back (2,7 → 3,7 W; 3,8 NW; 2,8 NE; 1,7 E; 2,6 SE; 3,6 SW); `L` on the anchor with
  Stay focused, `Tab` / `Shift+Tab` kept inside, a step key inert under it, `Esc` closes it and the
  instance stays; `L` off the anchor opens nothing; `F` → "Gate to Town A selected, Enter to go",
  `Enter` walks to the anchor 0,7 and the offer appears (after leaving it); `Tab` reaches the offer;
  `L`, `Tab`, `Enter` → the report with "On to …" focused, `Enter` → the town. Town and outpost: a
  key walks one hex; `F` × the row gives the row's order (town: Guild, Smith, Enchanter, Trainer,
  Armorer, Alchemist, Market, Vault, Gate; outpost: Guild, Trainer, Vault, Gate), the name's ring
  (computed outline solid) and the live line move, `F` and `Shift+F` wrap, `Esc` clears; `Enter`
  walks to the door and opens the service, `Esc` → the hub on the door; `3` opens the third at
  once; the Gate by `F` … `Enter`, closed by `Esc`; `+` raises the scale, `−` lowers it, a far
  place pans the camera (612 px, 376 px) and `0` brings it back (0.0 px); `?` lists the hub's 15
  bindings with ✕ focused, `Esc` closes and gives the focus back. `Control+Equal`, `Meta+KeyF`,
  `Control+KeyW` not prevented, `F` prevented; `qweasd` typed into the debug panel's field moves
  nothing; every Tab stop shows the ring; no pointer event on the page; no page error.
- AC-6 **Arrow keys**: → from 2,7 (odd row) → 1,7 E; ↑ → 1,8 NE; ↓ from 1,8 (even row) → 0,7 SE;
  ← → 1,7 W; ↑ → 2,8 NW; ↓ from 2,8 (even) → 2,7 SW.
- AC-7 **375 px unchanged**: at 375 × 812 with touch, the CLI-03f taps (arrival, a ground walk, a
  place walked to then opened, back on its door, the service row mid-walk, the instance, Leave on
  the anchor, Stay) give the same screen, tile and visible buttons (accessible names) as
  `origin/main`, step by step (8 of 8); no "Keys ?" button.
- AC-8 **Shots**, 1440 × 900, untracked, in the thread's library folder (never committed or
  posted): `keys-town-place-selected` (the town; the Gate's name on its yellow ribbon wears the
  yellow-and-dark ring, a yellow ring circles its door's hex); `keys-zone-gate-selected` (the zone,
  a ring on the hub gate's anchor); `keys-dialog-stay` (the I-5 question, Stay with the ring);
  `keys-help` (the key help over the town: the direction ring as seven hexes, the adventurer's in
  yellow, `W E` above, `Q D` beside, `A S` below; then the hub's 15 rows; ✕ focused).
- AC-9: the commands above pass; CI on the pull request.
- AC-10: the owner's eye after the merge.

## Deviations from the brief

1. **`stepTarget` does not call `placeholders.neighbour`.** `imports.test.ts` (F-6) forbids the
   word `neighbour` in `wiring.ts` ("the wiring imports none of the grid's geometry"), and no guard
   may be loosened. `stepTarget` finds the adjacent tile whose `facingToward` (a placeholder the
   wiring already imports) is `d`, among the eight tiles around the adventurer. Same result (the
   test compares it with `neighbour` in six directions on both parities); the geometry stays in
   `placeholders.ts`.
2. **`zoneTargets(location, anchorOf)`**: the anchor is read by the caller. The guard of CLI-03c
   (AC-5) lists the only readers of `anchor_chunk` / `anchor_tile` (`InstanceScreen`, `Loop`,
   `machine`, `screens`); `keyTargets.ts` would have been a new one. `InstanceScreen` passes
   `globalTile(anchor_chunk, anchor_tile)`.
3. **`useScreenFocus`, `offScreen` and the key marks' styles live in `keyScope.ts`**, not in
   `loop/styles.ts`, which is not in the allowlist.
4. **`MapKeys.controller` may be null**: the room's renderer mounts asynchronously, and a key
   pressed in the first few hundred milliseconds of a screen (seen in the browser check: the first
   `F` after coming back to a hub was lost) now reaches the screen's own keys (select, digits, `L`,
   `Esc`); the map's keys wait for the renderer.
5. **Focus by effect, not `autoFocus`, in the two dialogs**: under React's StrictMode (the dev
   server) an effect runs twice, and the cleanup that gives the focus back took it from Stay. Stay
   and the help's ✕ are focused by the dialog's effect, so a remount focuses them again. Skip and
   "On to …" keep `autoFocus`.
6. **The pack is not linked**: the browser checks read the site's built atlas of `main` through
   `GRIMWORLD_ART_OUT` (above) instead of building `tools/art/out` from an `assets` symlink.
7. **`data-door` on a place's label** (`HubScreen`): the browser check reads the selected place's
   door from it.
8. A visually hidden `aria-live` line exists on the hub and zone screens at every width (it holds
   no text until a place is selected); the phone layout gains no visible element or button.

## Escalations

- `verify:hubs` fails one check intermittently: "data-frames stops growing once it stands", a
  different hub and width each run (outpost 1440, then outpost 375 and town 1440). It fails the same
  way on `origin/main` d42d87e in a temporary worktree (one run passed, the next failed the outpost
  1440 check), with a load average near 7. Not this lot's; every other `verify:hubs` check passes
  (129 ok in the first run).

## Open questions

None. Q1–Q5 stand as the brief decided. Q6: the project manager's ruling (2026-10-03) lent
design/11 to this lot; the row written is:

> | Keyboard, outside combat (CLI-03k) | In zones and hubs, each key the tap or button it stands for:
> `Q` West, `W` North-West, `E` North-East, `D` East, `S` South-East, `A` South-West, by physical
> key (AZERTY's `A Z E / Q S D`); `←` / `→` West / East, `↑` / `↓` the upper or lower hex on the
> side faced; `F` / `Shift+F` the next or previous place (a hub's buildings in the service row's
> order, a zone's hub gates), `Enter` goes there; `1`–`9` the service row, in hubs only; `L` the
> Leave control, on a hub gate's anchor only, asked twice (Stay focused); `0` back to the
> adventurer, `+` / `−` zoom; `Esc` closes the key help, the confirmation, an inspection, then
> cancels the planned walk, clears the selection, then goes back from a service or the Gate
> screen; `?` the key help. One press, one hex; never with `Ctrl`, `Cmd` or `Alt`; a text field
> keeps its keys. **Project manager, 2026-10-03; reversible** |
