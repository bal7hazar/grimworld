# CLI-03k — Keyboard control for zones and hubs (desktop)

**Status: brief, ready to start from `main`.** It changes the client's input layer, the room
sandbox and the loop's screens. It does not touch any rule, the loop's machine, the placeholders or
the chain.

Written for the orchestrator of track CV on 2026-10-03, at the project manager's request. The owner
now tests on desktop only, because the phone is suspended (D-199). So keyboard control is the most
useful next lot. design/11 *Desktop* already names `Q W E A S D` for the six directions on the hex
grid. Since CLI-03f, zones and hubs share one engine (D-202), so there is **one keyboard model for
both**.

## Agent

Profile: `impl-opus`. The lot is input and presentation: a pure key map with tests, a few
controller methods, focus handling on the loop's screens, and a browser check.

Machine: the Mac or the VPS, at the orchestrator's choice. The lot commits no pin, gas table,
fingerprint or byte count, and needs no Cairo build. The browser check runs in headless Chromium,
like `verify:hubs`. With the art, link the pack as CLI-03i did (an **uncommitted** `assets`
symlink, removed afterwards). Without it, the check runs on shapes and says so.

Branch: a new branch from `main`. One pull request.

## Goal

After this lot, on a desktop window (1440 × 900):

1. **One hex at a time.** `Q W E A S D` move the adventurer one hex in the six directions of the
   pointy-top grid, in zones and in hubs. The arrow keys do the same where they map cleanly (§2).
2. **Places by keys.** `F` / `Shift+F` select the next or previous place: a hub's buildings, or a
   zone's hub gates. `Enter` goes there, exactly as a tap on that building or anchor does: the
   adventurer walks to the door and the place opens; in a zone, they walk to the anchor.
3. **The service row by keys.** In a hub, `1`–`9` press the row's buttons in their order. `Tab`
   reaches every button natively, and `Enter` presses the focused one.
4. **Leaving by the Gate (D-148).** In a zone, `L` opens the same I-5 confirmation as the Leave
   control, and only on a hub gate's anchor. The offer of CLI-03d is reached by `Tab` like any
   button. Leaving is still asked twice, and the dialog opens with **Stay** focused.
5. **Menus and dialogs.** `Esc` closes the top one: the key help, the I-5 confirmation, an
   adventurer's inspection, the planned walk, the selection, then a service or the Gate screen
   (back to the hub). `Enter` confirms through the focused button.
6. **The camera.** `0` brings the camera back to the adventurer (the ◎ button). `+` / `−` zoom in
   and out by one wheel notch, around the centre of the map.
7. **Key help.** `?` opens an overlay that lists the bindings of the current screen, built from the
   same table as the key map. A small "Keys ?" button in the desktop's left panel opens it too.
8. **Focus always visible**, with CLI-03i's focus ring. A new screen never leaves an armed button
   under `Enter` by surprise (§5).
9. **Nothing new at 375 px, and touch unchanged.** Every gesture of CLI-03a/f behaves as before.
   The phone layout shows no new control.

Presentation and input only. A key sends **the same intent as the tap it stands for**: a map
intent (`input/intent.ts` `Intent`) through `SandboxController.apply`, so a hub's `route` sees it,
or a `LoopIntent` through the screen's `dispatch`. There is no second path into the session or the
machine, no new intent kind, and no rule.

## Context

### What main has (read these)

- `docs/design/11-interface.md`: *Rules* (I-1, I-2, I-5), *Acting*, *Confirmation (I-5)*, *The
  queue* (cancel), *Hubs* (CLI-03d's arrival rule in the last row), *Desktop* (the `Keyboard`
  row), and *Accessibility*.
- `client/app/src/input/`: `intent.ts` (`Intent`, `LoopIntent`), `hubTaps.ts` (`targetIntent`,
  `figureIntent`), `gestures.ts` (`WHEEL_RATE`: one notch is `Math.exp(-100 × WHEEL_RATE)`) and
  `coords.ts`.
- `client/app/src/sandbox/controller.ts`: `apply(intent)` routes, then `session.apply`.
  `cancelWalk()`, `recentre()`, `adventurerTile()`, `tileOnScreen()` and `listenToFrames()` (used
  to place the hub's labels).
- `client/app/src/sandbox/session.ts` and `wiring.ts`: a tap ends the planned queue first, and
  `playOnTap` off previews on the first tap and walks on the second.
- `client/app/src/sandbox/placeholders.ts`: `neighbour(tile, d)` is the map library's
  `Direction::next` (0 East, 1 North-East, 2 North-West, 3 West, 4 South-West, 5 South-East). Only
  `wiring.ts` and `loop/machine.ts` may import it (`imports.test.ts`). `render/facing.ts`: direction
  `d` points `d × 60°` counter-clockwise from the screen's right.
- `client/app/src/sandbox/loop/`: `machine.ts` (`step`, `gateHere`, `leaveOffer`, `leaveQuestion`),
  `Loop.tsx` (the reducer and the desktop's three columns), `HubScreen.tsx` (`HubDoors` routes the
  map's intents; the service row), `hubDoors.ts` (a tap on a place's hexes walks to its door, then
  opens it), `InstanceScreen.tsx` (the offer, Leave, Travel back and the I-5 dialog), `screens.tsx`
  (service, Gate, entry and report).
- `client/app/src/sandbox/fixtures/hubWorld.ts`: `hubTap(view, tile)`; a place's `at` is its door
  and lies on its footprint. `fixtures/region.ts`: `GATES`, `GATE_KIND`, `globalTile`.
- `client/app/src/chrome/chrome.css`: the focus ring is a 3 px `#f2c94c` outline with a dark halo,
  on `button:focus-visible` only.
- `client/app/verify-hubs.mjs`: the pattern for the browser check (its own dev server process
  group, `data-tile`, `data-walking`, `data-camera`, `data-frames`, untracked shots).

### What it must not break

- D-148 and CLI-03d's arrival rule: leaving only from a hub gate's anchor, offered on stepping onto
  it after having left one, or through the explicit Leave control, never on arrival.
- I-5: leaving and travelling back are asked twice. The keyboard adds no shortcut that skips the
  second step, and has no single key for Travel back.
- D-202: a hub is walked like a zone, with the same controller and session.
- `imports.test.ts`: `placeholders.ts` stays imported by `wiring.ts` and `machine.ts` only.

## Scope and non-goals

In scope: §1 to §8 below, their tests, the browser check `verify:keys` and the report.

Not in scope:
- The instance's combat keys of design/11 *Desktop*: `1`–`8` skills, `Z X C V` belt, `Space`
  wait, `R` turn. They belong to the HUD lots (CLI-05, CLI-08). This lot **reserves** them: it
  binds none of them on an instance, and the key map's table lists them as reserved, so CLI-05 adds
  them in the same table.
- Rebinding keys, a settings screen, hold-to-walk, gamepads.
- Any change to the loop's machine, the placeholders, the fixtures' data, the renderer's drawing,
  `client/sim`, the contracts or the chain.
- Keyboard play on the service and Gate screens beyond `Tab` / `Enter` / `Esc`: those screens are
  stubs until CLI-06 and CLI-07.

## The design

### 1. One key map, pure

New `client/app/src/input/keys.ts`, with no DOM, React or PixiJS:

```ts
export type KeyCommand =
  | { kind: "step"; direction: Facing }         // or { kind: "step"; vertical: "up" | "down" } for ↑/↓
  | { kind: "cycle"; by: 1 | -1 }
  | { kind: "go" }                               // Enter on the selected place
  | { kind: "service"; index: number }           // 1–9 in a hub
  | { kind: "leave" }                            // L in a zone
  | { kind: "escape" }
  | { kind: "zoom"; by: 1 | -1 }
  | { kind: "recentre" }
  | { kind: "help" };

export interface KeyLike {
  code: string; key: string; shiftKey: boolean; ctrlKey: boolean; metaKey: boolean;
  altKey: boolean; repeat: boolean; isComposing: boolean;
}
export type KeyScreen = "hub" | "instance" | "service" | "gate" | "entry" | "report";

export function keyCommand(event: KeyLike, screen: KeyScreen): KeyCommand | null;
export const BINDINGS: readonly Binding[];       // the one table: keys, screens, command, label
```

- **Physical keys for positions, characters for symbols.** Movement, `F`, `L` and the digits are
  read from `event.code` (`KeyQ`, `KeyF`, `Digit1`, `Numpad1`…), so an AZERTY keyboard gets the
  same physical block (`A Z E / Q S D`) and its digits without `Shift`. `?`, `+`, `-` and `=` are
  read from `event.key`, plus `NumpadAdd` and `NumpadSubtract` by code. `0` is `Digit0` or
  `Numpad0` by code.
- **Never with a modifier.** A key with `Ctrl`, `Meta` or `Alt` returns `null`, so `Ctrl +`
  and `Ctrl −` stay the browser's zoom, and `Cmd F`, `Cmd L` and `Ctrl W` stay the browser's.
  `Shift` is accepted only for `Shift+F` and for `?`.
- **No auto-repeat and no composition.** `repeat` or `isComposing` returns `null`: one press is
  one hex (see Q4).
- **Screen-scoped.** Movement, `F`, `Enter` as `go`, `0` and `+` / `−` exist on `hub` and
  `instance` only. `1`–`9` exist on `hub` only, `L` on `instance` only. `Esc` and `?` exist on
  every screen.

### 2. The six directions

The `Q W E / A S D` block is read as a ring around its centre. With the keyboard's row stagger,
each key's angle from that centre is closest to these directions of the pointy-top grid:

| Key (QWERTY) | AZERTY | Direction | `Facing` |
|---|---|---|---|
| `Q` | `A` | West | 3 |
| `W` | `Z` | North-West | 2 |
| `E` | `E` | North-East | 1 |
| `D` | `D` | East | 0 |
| `S` | `S` | South-East | 5 |
| `A` | `Q` | South-West | 4 |

**Decided (this brief, reversible by changing one row of `BINDINGS`).** This is the geometric
reading. The common alternative, `W` for North-East and `A` for West, puts `D` on South-East and
gives up the right hand's `D` = East. The key help shows the ring as a small hex diagram, so the
mapping can be seen without being learnt.

**Arrow keys.** `←` is West and `→` is East: these are clean. A pointy-top grid has no straight up
or down, so `↑` and `↓` take the upper or lower neighbour **on the side the adventurer faces**:
facing East, North-East or South-East, `↑` is North-East and `↓` is South-East; facing the other
three, `↑` is North-West and `↓` is South-West. Holding to one side then walks a straight diagonal.
`keys.ts` returns `{ kind: "step", vertical }`, and the controller resolves it from the
adventurer's facing, which the session already holds. **Decided, reversible (Q2):** if this reads
badly, `↑` and `↓` are dropped and only `←` / `→` stay.

**One hex is a tap on the neighbour.** New `wiring.ts` export:
`stepTarget(state, step) → Tile | null`, the neighbour of the adventurer's tile in that direction,
resolved through `placeholders.neighbour`. So `placeholders.ts` keeps its two importers. New
`SandboxController.step(step)` calls `this.apply({ kind: "tile", tile })`. So:

- In a zone, it is exactly a tap on that hex: it ends the planned queue first, then walks one step,
  or previews it when `playOnTap` is off, and a second press of the same key walks it. A wall, an
  actor, an unrevealed tile: whatever the tap does, here too.
- In a hub, the hub's `route` sees the tile. Stepping onto a place's hex walks to its door and
  opens it, as a tap on that building does. A prop or decor hex does nothing; a figure is
  inspected. These are the same answers as a tap.

### 3. Places by keys

New `client/app/src/sandbox/loop/keyTargets.ts`, pure, reading fixed data only:

- `hubTargets(view) → HubPlace[]`: the hub's places **in the order of `view.services`**, so
  `F`'s order matches the service row and `1`–`9`.
- `zoneTargets(location) → { gate: GateRecord; tile: Tile }[]`: the hub gates (`GATE_KIND.hub`) of
  that location, with `globalTile(anchor_chunk, anchor_tile)`, lowest id first. This is a listing
  of fixed data, not the rule `hubGateAt`, which stays in `placeholders.ts`. **Decided:** every hub
  gate of the location is listed, revealed or not. `Enter` on an unrevealed one does what a tap
  does (nothing); the zone's fixture has one gate, on its entry.
- `nextTarget(count, current, by) → number | null`: wraps around, `null` when `count` is 0, and
  starts at 0 (or `count − 1` for `Shift+F`) when nothing is selected.

Selection is the screen's React state, presentation only. The selected place is shown by a marker
that follows the camera, placed in `onFrame` as the hub's labels are, and **drawn in the focus
ring's colours**. In a hub, the selected place's label ribbon gets the ring and the marker sits at
its door. In a zone, a ring sits on the anchor's hex. A visually hidden `aria-live="polite"` line
says "Smith selected, Enter to go". When selecting moves the target off screen, the camera pans to
it through new `Renderer.lookAt(tile)` (a public wrapper of the existing eased `panCameraTo`) and
`SandboxController.lookAt(tile)`. `0` brings it back.

`Enter` on a selected place calls `controller.apply({ kind: "tile", tile: place.at })` in a hub.
`HubDoors.route` then walks to the door and opens the place, or opens it at once when the
adventurer already stands there, exactly as a tap on the building does. In a zone, it calls the
same with the anchor's tile: the walk goes there, and CLI-03d's offer appears on arrival if the
adventurer had left an anchor. The selection clears when the place opens, on `Esc`, and on any
step key.

`1`–`9` in a hub call `dispatch(targetIntent(view.services[i]))`, the service row's own `onClick`
(which opens at once, mid-walk too). A digit past the row's length does nothing.

### 4. Leaving, confirming, closing

- `L` in a zone does what the Leave button's `onClick` does: `gateHere && setAsking(...)`. Off an
  anchor it does nothing, and the button stays disabled as today.
- The I-5 dialog (`InstanceScreen`): on open, focus moves to **Stay**. `Tab` and `Shift+Tab` stay
  inside the dialog while it is open (a focus loop over its two buttons, the standard modal
  pattern; the map's keys are inert under it). `Esc` is Stay. `Enter` presses the focused button,
  so confirming takes `Tab` then `Enter`: two deliberate keys after the `L` or the offer, which
  keeps I-5's "asked twice". On close, focus returns to the control that opened it, or to the
  screen.
- `Esc`, top first: the key help, then the I-5 dialog (Stay), then a hub's inspection (`back`, the
  ✕'s intent), then the planned walk (`controller.cancelWalk()`, the counter's action, design/11
  *Desktop* "`Esc` cancel"), then the selection, then on a service or the Gate screen `back` (the
  header's ‹ Back intent). On a hub, zone, entry or report screen with nothing open, `Esc` does
  nothing.
- Entry screen: `Enter` presses Skip when it is focused (§5). Report screen: "On to …" gets the
  focus, so `Enter` continues; that is harmless, since it is no loss.

### 5. Focus

- **One listener**, on `document`, installed by `Loop` (and by the bare `RoomSandbox` outside the
  loop, so `?fixture=` rooms move too). New `client/app/src/sandbox/keyScope.ts` holds a small
  stack of handlers. The screen registers its handler, an open dialog or the key help pushes one
  on top, and only the top handler receives commands. Its pure part (the stack, and
  `ignoredTarget(target)`) is tested under node.
- `ignoredTarget`: a key is left to the page, not handled, when its target is an `input`,
  `textarea`, `select` or `[contenteditable]`. The debug panel has inputs, and later screens will
  have more. It is also left to the page when the key is `Enter` and the target is a `button` or
  a link: the browser presses it, and `go` is not sent. `Tab` is **never** handled by the key map,
  except inside the I-5 dialog's focus loop.
- A handled key calls `preventDefault()`. An unhandled one is left alone.
- **On a screen change**, focus moves to the new screen's root (`tabIndex={-1}`, no ring shown on
  a non-interactive root), except on the report screen ("On to …") and the entry screen (Skip). So
  no button sits armed under `Enter` after a screen opens.
- The ring: `chrome.css` extends the existing `button:focus-visible` rule to the marker and the
  key help's close button. The plain look (no art) gets the same ring, so focus is visible in both
  modes and in forced colours.

### 6. The camera

`0` calls `controller.recentre()`, the ◎ button. `+` / `−` call new
`SandboxController.zoomBy(by)`, which calls `renderer.zoomAt(factor, centre of the viewport)` with
one wheel notch's factor (`Math.exp(∓100 × WHEEL_RATE)`, exported from `gestures.ts` as
`WHEEL_NOTCH`). It is clamped by the renderer like any zoom.

### 7. Key help

New `client/app/src/sandbox/loop/KeyHelp.tsx`: a `Panel` dialog (`role="dialog"`,
`aria-label="Keys"`) listing the current screen's rows of `BINDINGS` with their labels, and the
direction ring as a small diagram (DOM or inline SVG, no art). Reserved keys are shown greyed as
"later". `?` toggles it, `Esc` closes it, and focus goes to its ✕ and back on close. A "Keys ?"
`Button` in the desktop's left panel (`Loop.tsx`, desktop layout only) opens it, so the 375 px
layout gains nothing.

### 8. At 375 px

The listener exists at every width, because a tablet may have a keyboard. But **no element is
added to the phone layout**, and no pointer or touch path changes. The browser check proves it
(AC-7).

## Size

One lot. Estimate (not a measure): `keys.ts` and its tests ~250 lines; `keyScope.ts` and
`keyTargets.ts` with tests ~200; the controller, wiring and renderer additions with tests ~100;
the screens (hub, instance, screens, Loop, KeyHelp, Sandbox) ~300; `verify-keys.mjs` ~300.
Commits in this order: (1) `keys.ts` + tests; (2) `wiring.stepTarget`, the controller and renderer
methods + tests; (3) `keyScope.ts` and `keyTargets.ts` + tests; (4) the screens, one commit per
file; (5) the key help; (6) the browser check; (7) the report.

## Files the implementation touches

New:
- `client/app/src/input/keys.ts`, `client/app/src/input/keys.test.ts`
- `client/app/src/sandbox/keyScope.ts`, `client/app/src/sandbox/keyScope.test.ts`
- `client/app/src/sandbox/loop/keyTargets.ts`, `client/app/src/sandbox/loop/keyTargets.test.ts`
- `client/app/src/sandbox/loop/KeyHelp.tsx`
- `client/app/verify-keys.mjs`
- `docs/reports/CLI-03k-keyboard.md`

Changed:
- `client/app/src/input/gestures.ts` (export `WHEEL_NOTCH` only)
- `client/app/src/sandbox/wiring.ts` (`stepTarget` only), `wiring.test.ts` (added cases)
- `client/app/src/sandbox/controller.ts` (`step`, `zoomBy`, `lookAt`), `controller.test.ts`
- `client/app/src/render/renderer.ts` (`lookAt` only), `renderer.test.ts` (added case)
- `client/app/src/sandbox/Sandbox.tsx` (`RoomSandbox`: the map's handler, the marker slot, the
  listener outside the loop)
- `client/app/src/sandbox/loop/HubScreen.tsx`, `InstanceScreen.tsx`, `screens.tsx`, `Loop.tsx`
- `client/app/src/chrome/chrome.css` (the focus ring's selectors only)
- `client/app/package.json` (one `scripts` line: `verify:keys`; no dependency)

**Not touched**, so a lot that stays off these files can run in parallel:
`sandbox/placeholders.ts`, `sandbox/loop/machine.ts`, `sandbox/loop/hubDoors.ts`,
`sandbox/fixtures/**`, `sandbox/session.ts`, `input/intent.ts`, `input/hubTaps.ts`,
`input/coords.ts`, `render/` apart from `renderer.ts`'s one method, `chrome/Chrome.tsx`, `tools/`,
`client/sim/**`, `contracts/**`, `account/**`, `chain.ts`, `pnpm-lock.yaml`, `.github/`, and
`docs/design/**` (see Q6).

**Overlap warning for the orchestrator**: the loop's screens (`HubScreen`, `InstanceScreen`,
`screens.tsx`, `Loop.tsx`), `Sandbox.tsx` and `chrome.css` are the files CLI-03i changed. Any open
chrome or screen lot overlaps this one. Lots confined to `render/ground.ts`, `render/obstacles.ts`
or `tools/art` do not, except one that also changes `renderer.ts`. This lot adds one method at
its end there, so a renderer lot would see a trivial merge, not a conflict of meaning.

## Allowlist

Exactly the files above. `sandbox/imports.test.ts`: assertions may be added, no guard loosened.
Anything else is an escalation in the report, not an edit.

## Acceptance criteria

- [ ] AC-1 **Input only.** `git diff origin/main --stat` lists only allowlisted files.
      `git diff origin/main -- client/app/src/sandbox/placeholders.ts client/app/src/sandbox/loop/machine.ts client/app/src/sandbox/loop/hubDoors.ts client/app/src/input/intent.ts`
      is empty (in the report). The tests `machine`, `hubDoors`, `walkFollowsPreview`, `session`,
      `placeholders`, `hubTaps` and `imports` pass unmodified (`wiring.test.ts` only gains cases).
- [ ] AC-2 **The key map** (unit, `keys.test.ts`), with a table test over `BINDINGS`:
      - each of `KeyQ KeyW KeyE KeyD KeyS KeyA` gives its direction of §2 on `hub` and `instance`,
        and `null` on `service`, `gate`, `entry` and `report`;
      - `ArrowLeft` and `ArrowRight` give West and East; `ArrowUp` and `ArrowDown` give `vertical`;
      - with `ctrlKey`, `metaKey` or `altKey` set, **every** binding gives `null`;
      - `repeat` or `isComposing` gives `null`;
      - `Shift+KeyF` gives `cycle −1`, and `Shift` with any other bound letter gives `null`;
      - `Digit1`…`Digit9` and `Numpad1`…`Numpad9` give `service 0..8` on `hub` only;
      - `KeyL` gives `leave` on `instance` only;
      - `?` (by `key`, with any `code`) gives `help` everywhere;
      - `+`, `=` and `NumpadAdd` give `zoom 1`; `-` and `NumpadSubtract` give `zoom −1`;
        `Digit0` and `Numpad0` give `recentre`;
      - an AZERTY event (`code: "KeyQ"`, `key: "a"`) gives West, read by code;
      - the reserved keys (`Digit1`–`Digit8` on `instance`, `KeyZ KeyX KeyC KeyV`, `Space`,
        `KeyR`) give `null` on `instance` and are listed in `BINDINGS` as reserved;
      - no binding uses `Tab`.
- [ ] AC-3 **Same intents as taps** (unit):
      - `stepTarget` equals `neighbour(adventurer, d)` for the six directions, and resolves
        `vertical` from the facing as in §2, on both row parities;
      - `controller.step(d)` hands `apply` exactly `{ kind: "tile", tile: neighbour }`, with an
        injected router as the spy;
      - in a hub, `Enter` on a selected place sends the same `Intent` as a tap on `place.at`, and
        `service i` sends `targetIntent(view.services[i])`, the service row's own intent;
      - `L` off an anchor opens nothing;
      - `zoomBy(1)` then `zoomBy(−1)` restores the scale, within float tolerance and unless
        clamped.
- [ ] AC-4 **Targets and scope** (unit): `hubTargets` follows `view.services`' order for the
      town and the outpost; `zoneTargets` lists the fixture zone's hub gate on its entry tile;
      `nextTarget` wraps both ways and handles 0 and 1 targets; the key-scope stack gives
      commands only to the top handler and pops on close; `ignoredTarget` is true for `input`,
      `textarea`, `select` and `[contenteditable]`, and for `Enter` on a `button` or link.
- [ ] AC-5 **The browser check** (`verify:keys`, headless Chromium, **1440 × 900**, keyboard only:
      no `page.mouse`, no `tap`), idle animations off:
      - **A zone** (`?hub=town&entry=300`; the Gate screen and entry are reached by `Tab` /
        `Enter`): each of the six keys moves `data-tile` to the expected neighbour, and the
        walk ends (`data-walking=false`). `F` selects the hub gate, `Enter` walks there, and the
        offer appears only after the adventurer has left the anchor (CLI-03d). `L` on the anchor
        opens the dialog with **Stay** focused. `Esc` closes it and the instance is still open.
        `L`, `Tab`, `Enter` leave: the report screen, then `Enter` → the town. `L` off the anchor
        opens nothing.
      - **The town and the outpost**: a direction key walks one hex; `F` / `Shift+F` walk
        through the places in the service row's order (the label's ring moves, and the
        `aria-live` line changes); `Enter` walks to the door and the service screen opens;
        `Esc` → the hub, with the adventurer on the door; `3` opens the third service at once;
        the Gate is opened by `F`…`Enter` and closed by `Esc`.
      - **Camera**: `+` raises the scale in `data-camera`, `−` lowers it, and `0` brings the
        camera back to the adventurer's tile.
      - **Key help**: `?` opens it; it lists every binding of the screen; `Esc` closes it.
      - **Browser keys untouched**: `Control+Equal`, `Meta+KeyF` and `Control+KeyW` are not
        prevented (`defaultPrevented` false, read from a capture listener the check adds). Typing
        `qweasd` into the debug panel's input moves nothing.
      - **Focus**: after each screen change, `document.activeElement` is the screen's root (or
        the report's or entry's button); every `Tab` stop shows the ring (computed
        `outline-style` not `none`).
      - No page error.
- [ ] AC-6 **Arrow keys**: in the zone, `←` / `→` step West / East; `↑` / `↓` step to the facing
      side's upper or lower neighbour (§2), on both row parities.
- [ ] AC-7 **375 px unchanged**: at 375 × 812 with `hasTouch`, the CLI-03f taps of
      `verify-hubs.mjs` (ground walk, place walk then open, the service row mid-walk, the zone's
      Leave on the anchor) give the same screens and tiles as on `origin/main`. The phone
      layout's set of buttons (their accessible names) equals `main`'s: no "Keys ?" button at
      375 px.
- [ ] AC-8 **Shots** (`VERIFY_SHOTS=1`): the town with a place selected, the zone with the gate
      selected, the I-5 dialog with Stay focused, and the key help, all at 1440 × 900. They go
      into the thread's library folder, **untracked**, never committed, attached or posted
      (D-73). The thread describes them in words in the report.
- [ ] AC-9 `pnpm --filter @grimworld/app test`, `lint`, `typecheck` and `build`,
      `pnpm exec prettier --check client indexer`, and `scripts/prepush.sh` pass. CI is green.
- [ ] AC-10 **The owner's eye, after the merge**, on the public site. It does not block. A remark
      on a binding is one row of `BINDINGS`; a remark on the model goes back to *The design*.

## Verification

- The commands of AC-9; then `verify:keys` (AC-5 to AC-8) on this branch, and AC-7's comparison
  on `origin/main` too. Build `main` in a temporary worktree the thread creates and removes by its
  exact path.
- Start and stop the dev server inside one foreground command. Signal only its recorded process
  group, never a process found by search (`pgrep`, `pkill`, `ps | grep`).
- `git fetch origin` and merge `origin/main` before every push; `scripts/prepush.sh`, never
  `--no-verify`; never touch `.git/config`. Do not poll CI: push, open the pull request, end the
  turn.

## Review and audit

- **Review** on another model than the implementer's: `review` (Sonnet) for an Opus implementer.
  It checks most closely:
  - no new path into the session or the machine: every key ends in `apply`, `dispatch`,
    `cancelWalk`, `recentre` or `zoomBy`;
  - `placeholders.ts` and `machine.ts` untouched;
  - the modifier, repeat, composition and text-field guards;
  - I-5 kept (Stay focused, two deliberate keys, no single key for Travel back);
  - D-148 and CLI-03d kept;
  - focus moved on every screen change, and the dialog's focus loop released on close;
  - the 375 px layout unchanged;
  - the key help built from `BINDINGS`, not from a second list.
- **Audit**: none (D-177: input and presentation, no rule, the owner sees it). The orchestrator
  decides otherwise if the lot leaves the allowlist.

## Rules of the run

- D-73: nothing of the pack committed or posted; shots untracked in the library folder.
- No pin, fingerprint or byte count committed.
- External issues named in words, not links, in commit messages and pull request text.
- Pull request title: `[<model>] CLI-03k keyboard control for zones and hubs`. Set the body
  through REST, because `gh pr edit` fails on Projects-classic. It holds the bindings table as
  built, "Audit: none (D-177)" and "Owner's eye: on the public site after the merge".

## Report

`docs/reports/CLI-03k-keyboard.md`, as in `docs/briefs/COMMON.md` §7, with:
- the bindings as built, and any deviation from §1 to §7;
- AC-1's empty diffs;
- the browser check's output, and AC-7's comparison with `main`;
- the shots described in words, and where they are;
- the tests added;
- commands refused, escalations, open questions;
- the proposed design/11 wording (Q6).

## Open questions

1. **Decided (this brief): `F` / `Shift+F` cycle the places, not `Tab`.** `Tab` stays the browser's
   focus order over the buttons: the service row, Leave, Travel back. Taking it for the map would
   trap focus away from those buttons. Reverse: the orchestrator prefers `Tab` while the map has
   focus; then the map host takes `tabIndex=0`, and `Tab` cycles inside it until the last place,
   then leaves.
2. **Decided, reversible: `↑` / `↓` follow the facing side** (§2). Reverse: drop them, and keep
   `←` / `→`.
3. **Decided (this brief, reversible by one row): the direction ring** `Q`=W, `W`=NW, `E`=NE,
   `D`=E, `S`=SE, `A`=SW (§2). The alternative is in §2.
4. **Decided: one press, one hex; auto-repeat ignored.** A held key walks one hex. Fast presses
   move as fast taps do today (each press ends the walk and plays its step at once). Reverse:
   hold-to-walk, by queueing one step per `stepMs` while the key is down; that is its own small
   lot.
5. **Decided: `1`–`9` open services in hubs only**, where there is no skill bar. On an instance
   they stay reserved for CLI-05's skills, as design/11 says. Reverse: drop digits in hubs if
   CLI-05 wants the same keys everywhere.
6. **For the orchestrator: a design/11 line.** *Desktop*'s `Keyboard` row names the combat keys
   but not `F`, `Enter`, `L`, `0`, `+` / `−`, `?`, or `1`–`9` in hubs. Default: **design/11 is not
   edited by this lot**. The report proposes one row, "Keyboard, outside combat (CLI-03k)", for
   the orchestrator to have written by its next docs pull request (under D-178, as CLI-03d's line
   was). Reverse: the project manager lends design/11 to the lot, and the lot writes the row.
7. **Decided: `Esc` cancels the planned walk before it clears the selection** (design/11
   *Desktop* "`Esc` cancel"), and closes a service or the Gate screen last.
