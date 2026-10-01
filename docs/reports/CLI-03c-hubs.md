> Archived by the orchestrator of track CV on 2026-10-01 from `nexus report grimworld/impl-cli-03c` (the Mac, account claude-b7r, model claude-opus-5-5 as `nexus status` read it; job 14:32:39 → 15:16:09 UTC). Merged as #270 (`8b4e3a4`).

# [Opus 5.5] CLI-03c — hubs and transitions

## Summary

The sandbox now opens on a **hub**. On fixed data, the owner can walk the whole loop at 375 × 812 and in a desktop window:
town or outpost → a service stub or the Gate screen → the entry moment → CLI-03a's room on the entry chunk → out by a hub gate, by travelling back, or by a debug defeat → the closing report → the hub.

`tools/art` now packs still buildings. design/11 *Hubs* has one line per open point, each marked "proposed, the owner's eye".

- Pull request: https://github.com/bal7hazar/grimworld/pull/270
- CI: green, 15 checks pass. `indexer-node` is skipped by its path filter.
- Not merged.
- Model: Opus 5.5, as the brief names.

## Files changed

- `tools/art/artpipe/clean.py`: `still()`, one image as one pose, anchored at its base (the feet rule) and its centre.
- `tools/art/build.py`: `[[still]]` entries. Adds `still_problems`, `still_sprite` (one frame, animation `still`, rate 1, no loop) and the stills in the printed table.
- `tools/art/manifest.toml`: the eight Blue buildings (castle, barracks, archery, monastery, tower, house1–3).
- `tools/art/tests/test_build.py`: `Stills` on synthetic images, and the real manifest's stills.
- `tools/art/README.md`: the still role, and how to build and see the buildings.
- `client/app/src/input/intent.ts`: `LoopIntent`, the one module of the intents.
- `client/app/src/input/hubTaps.ts` (+ test): the illustration's fit, tap rectangles (at least 40 pt), and the intent of each tap.
- `client/app/src/render/hubView.ts`: the hub view state (places, figures, services).
- `client/app/src/render/hubRenderer.ts` (+ test): the hub drawn on demand, stills from the atlas or shapes.
- `client/app/src/sandbox/fixtures/region.ts` (+ test against the seed): the seed's records and the outpost fixtures.
- `client/app/src/sandbox/fixtures/zone.ts` (+ test): the seed's zone as a room fixture.
- `client/app/src/sandbox/fixtures/hubs.ts`: the hub views, `OUTPOST_SERVICES`, the adventurer sheet and the report figures.
- `client/app/src/sandbox/fixtures/index.ts`: `?fixture=zone`.
- `client/app/src/sandbox/placeholders.ts`: `hubGateAt`, `entryThrough`, `hubAfter`, each marked `PLACEHOLDER until CLI-02`.
- `client/app/src/sandbox/loop/machine.ts` (+ test): the state machine of screens.
- `client/app/src/sandbox/loop/{Loop,HubScreen,InstanceScreen,screens}.tsx`, `styles.ts`: the screens and the desktop layout.
- `client/app/src/sandbox/Sandbox.tsx`: a dispatcher. `RoomSandbox` is the old sandbox, taking an optional `world`, `onTile` and `children`.
- `client/app/src/sandbox/controller.ts`: the `world` option and `adventurerTile()`.
- `client/app/src/sandbox/params.ts` (+ test): `hub=`, `loop=1`, `entry=`.
- `client/app/src/sandbox/imports.test.ts`, `wiring.test.ts`: extended to the new modules.
- `docs/design/11-interface.md`: *Hubs* only, the five proposed lines.

## Screens and their intents

| Screen | Taps → intent |
|---|---|
| Hub (town, outpost) | building or service entry → `open service s` or `open gate screen` (the same intent for both); adventurer → `inspect adventurer a`; ✕ → `back` |
| Service (stub) | ‹ Back → `back` |
| Gate | Leave ▸ → `enter gate g`; ‹ Back → `back` |
| Entry | Skip → `skip entry`; the fixed delay answers `entry drawn` |
| Instance | "Gate to … · Leave" then confirm → `leave`; Travel back then confirm → `travel back`; "debug: defeat now" → `defeat now`; each step answers `moved` |
| Report | On to … → `close report` |

`back`, `skip entry` and `defeat now` are added to the brief's list: they are the stubs' back, the skippable entry and the debug control.

## Open points proposed in design/11

1. The outpost's services: Guild, Trainer, Vault, then Gate (`OUTPOST_SERVICES`).
2. The entry moment: "Through the gate, to …", a fixed 1.2 s on fixed data, with a Skip button.
3. The report's content: the outcome and how, the hub, experience, loot, quest progress, and the belt's potions back to the pack.
4. Present adventurers stand still at fixed spots near the road. A tap shows their name, profession and level. A hub draws nothing between taps.
5. Where the buildings stand:
   - Town: the castle (Guild) at the back, the barracks (Trainer), the tower (Enchanter); the crafts and the Market along the road; the Vault and the Gate in front.
   - Outpost: Guild and Trainer at the back, Vault and Gate in front.

## Commands run

- `python3 tools/art/build.py --fingerprint`: re-executed under `/opt/homebrew/bin/python3.12` and created `tools/art/.venv` (ignored), then `tools/art/out/ does not exist: build it first`. I used it to get the venv.
- `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests`: `Ran 55 tests … OK` before the change, `Ran 59 tests in 0.271s OK` after.
- `pnpm install --frozen-lockfile`, then `pnpm --filter @grimworld/app test` as a baseline: `Tests 172 passed | 1 skipped`.
- After the change, from `client/app`:
  - `eslint . --ignore-pattern verify-cli03c.mjs`: clean.
  - `tsc --noEmit`: clean.
  - `vitest run`: `Test Files 23 passed | 1 skipped (24)`, `Tests 208 passed | 1 skipped (209)`.
  - `vite build`: `✓ built in 884ms`, with the existing chunk-size warning.
- `pnpm exec prettier --check client indexer`: clean for every committed file. It warns only on the untracked `verify-cli03c.mjs`.
- `gh pr checks 270`: every check `pass` except `indexer-node` (skipping).

### Playwright run (AC-9)

Setup and teardown:

1. `pnpm --filter @grimworld/app add -D playwright-core`, for the run only.
2. `node client/app/verify-cli03c.mjs`, in the foreground. It spawns `pnpm --filter @grimworld/app dev --host 127.0.0.1 --port 5197 --strictPort` in its own process group, drives Chrome (`channel: "chrome"`, headless), and sends SIGTERM to that recorded group in `finally`.
3. `git checkout -- client/app/package.json pnpm-lock.yaml`, then `pnpm install --frozen-lockfile`.

Four runs:

- **Run 1**: 3 failures, all in my script:
  - The frame counter was read while a remounted hub canvas was still drawing its first frames.
  - With `entry=0` the entry screen had already passed when the script looked for it.
- **Run 2**: all checks passed. Every `[loop]` line was logged twice: a `console.debug` inside the reducer, which React StrictMode runs twice. I moved the log to an effect.
- **Run 3** found two real defects, both fixed in commit 475662a:
  - The hub's tap targets did not exist until the Pixi canvas had initialised. On the phone, right after a Back, there were no adventurer buttons.
  - Opening the inspect card resized the illustration and moved the buttons. A tap on the third adventurer missed.
- **Run 4**, the final one. Real output, trimmed:
```
art: …/impl-cli-03c/tools/art/out not built, the sandbox draws shapes
Chrome launched: version 154.0.8037.59
=== phone-375x812 ===
  ok   layout phone
[town] Town A: canvas 375x598; places Guild … Gate building; services Guild | Smith | Enchanter | Trainer | Armorer | Alchemist | Market | Vault | Gate ▸
  {"atlas":"none","frames":1,"tickers":"false"}
  ok   tap <each of 9 buildings> → service/gate → back → hub; ok service entry <each of 9> → … → back
  ok   3 present adventurer(s) tappable right after Back
  ok   inspect Adventurer Maren: "Maren · warden, level 7" (Tobin, Ilse likewise)
  ok   on demand, frames 1 → 1 over 3 s without input; tickers false
[town] Gate screen: Gate 1 → the meadow zone (levels 1–3); reminder: "…This bar has no condition removal, nothing at range. A reminder, not a block."
  ok   entry moment → instance after 1181 ms
  ok   on gate 2's anchor at the entry (0, 7): leave offered
  ok   one step off the anchor: no offer
  ok   back on the anchor: leave offered again
  asked: "Leave the instance for Town A? The goblins will be back next time."
  ok   report returned: Returned · Back to Town A, through the gate. … Experience · +140 · Loot · Runt tooth × 3 …
  ok   closed the report → Town A
  ok   travel: report returned … travelled back …; closed the report → Town A
  ok   defeat: report defeated: Defeated · Carried back to Town A, health at 0. … +60 …; closed the report → Town A
[outpost] Outpost B: canvas 375x648; places Guild, Trainer, Vault, Gate; services Guild | Trainer | Vault | Gate ▸
  ok   … every building and entry, inspect Corvin, on demand frames 1 → 1 over 3 s
[outpost] Gate screen: Gate 101 → the meadow zone (levels 1–3)
  ok   outpost's way in on gate 102's anchor: "Gate to Outpost B" offered
  ok   leave → report returned → Outpost B; travel back → report returned → Outpost B
  ok   ?fixture=cave still opens the room: adventurer at (12, 7), camera on (12, 7)
  console: 89 [loop] lines, 23 × 404 (the atlas probe), 0 other error(s)
=== desktop-1440x900 ===
  ok   layout desktop; Town A canvas 430x686 (the portrait column, panels left and right)
  … the same checks, all ok; on demand frames 1 → 1 over 3 s; 33 × 404, 0 other error(s)
dev server process group 57491 sent SIGTERM
ALL CHECKS PASSED
```

The 404s are the atlas probe against the missing `tools/art/out`, as in CLI-03a's check. There was no `pageerror`.

The screenshots are in `client/app/.verify-out/`, untracked. They show shapes only, since no atlas was built. They stay on this Mac.

## What the owner should look at, and how

`pnpm --filter @grimworld/app dev`, then open:

- `/?hub=town` for the whole loop from the town. `/?loop=1` does the same.
- `/?hub=outpost` for the outpost and its fewer services.
- `&entry=0` skips the entry wait, and `&entry=3000` lengthens it.
- `/?fixture=zone` opens the seed's zone as a plain room. The other rooms still open with `?fixture=meadow|cave|edge`.
- A phone (or devtools at 375 × 812), and a window wider than 700 pt for the desktop layout.

To see the buildings from the atlas, on the Mac with the pack:

```
git submodule update --init assets
tools/art/build.py            # writes tools/art/out/, with the eight Blue buildings
pnpm --filter @grimworld/app dev
```

From a worktree without the pack, run `GRIMWORLD_ART_OUT=<checkout that built it>/tools/art/out pnpm --filter @grimworld/app dev`.

I could not build the atlas: this worktree has no `assets` submodule. So the buildings-from-atlas path is tested only on a synthetic still (`hubRenderer.test.ts`), never on the pack.

## Commands refused by the profile

Each was refused automatically ("requires approval, and this session has no approval surface"):

1. A compound `cd client/app && ls; cat package.json; find …` survey. I used Glob and Read instead.
2. `python3 --version; command -v python3.12 python3.13`, and then `python3.12 --version`. Instead, `tools/art/build.py`'s own bootstrap found Python 3.12.
3. A `git -C <worktree> add … && commit …` run from `client/app`. I re-ran it from the worktree root.
4. `gh api -X PATCH …/pulls/270 -F body=@…`, to update the PR body after `gh pr edit` failed. `gh pr edit` failed on GitHub's "Projects (classic) is being deprecated" GraphQL error.
   - The PR body is therefore the one from opening. Its AC-9 line says "see the report", with no browser result.

## Acceptance criteria

- **AC-1**: passed.
  - `hubTaps.test.ts`: each building and its service entry give the same intent, and targets are at least 40 pt on 375 × 520 and 430 × 600.
  - `hubRenderer.test.ts`: a still is drawn from the atlas when present, and a shape otherwise.
  - `machine.test.ts`: service → back.
  - Browser check on both viewports.
- **AC-2**: passed.
  - `region.test.ts` reads `contracts/seed/test-region.json` and compares every copied field of region 1, locations 1–2, gates 1–2 and the zone's three outlines. It also checks that the fixture ids are absent from the seed.
  - `machine.test.ts`: `gatesFrom`.
  - "Leave" emits `enter gate g` (`screens.tsx`, and the browser check).
- **AC-3**: passed.
  - `machine.test.ts`: entry → instance at (0, 7), the same for skip.
  - `zone.test.ts`: the outline, and only the entry chunk revealed.
  - The renderer and input are unchanged: all existing renderer and sandbox tests pass unmodified, except the fixture list in `wiring.test.ts`.
- **AC-4**: passed.
  - `machine.test.ts` (a) leave by gate 2 → Town A, (b) travel back → last hub, (c) defeat → last hub, each through `report`.
  - Browser check for each, in the town and the outpost.
- **AC-5**: passed.
  - `imports.test.ts`: `placeholders.ts` is imported only by `wiring.ts` and `loop/machine.ts`.
  - The new rules are exported only there and imported only by the machine.
  - No other module compares a tile to an anchor.
  - The hub renderer, view and taps import nothing from the sandbox.
  - There is no randomness or clock in the machine or the fixtures.
  - `hubTaps.test.ts`: every tap yields an intent.
- **AC-6**: passed.
  - `hubRenderer.test.ts`: one frame per view, size or atlas, then `host.quiet()`. There are 0 extra frames over 60 s, and none while the page is hidden.
  - Browser check: frames 1 → 1 over 3 s, tickers false.
- **AC-7**: passed. The `Stills` tests run on synthetic images: base and centre anchor, one frame packed at native size, `verify` reading the baseline back from the PNG, and the manifest problems. The README section says how.
- **AC-8**: passed. design/11 changed only in *Hubs*: one table of five lines, each marked "Proposed, the owner's eye".
- **AC-9**: passed. See the Playwright run above.
- **AC-10**: passed. test, lint, typecheck, build, prettier and the art tests pass locally, and CI is green.

## Deviations from the brief

- **Intents**: three intents beyond the brief's list (`back`, `skip entry`, `defeat now`), and two answers that are not taps (`entry drawn`, `moved`). They are typed with the others in `input/intent.ts` and `loop/machine.ts`.
- **Present adventurers stand still.** The brief's "walk by" allowed fixed positions. Standing still keeps AC-6 strict (no idle frames on a hub). It is written as a proposed line.
- **Leaving is asked twice.** Leaving by a hub gate takes the offer, then a confirmation, as design/11 I-5 says ("leaving the instance, travelling back: asked twice").
- **Desktop instance layout.** On a desktop, the instance's room is drawn in the portrait column, not the whole window (design/11 *Desktop*). The room's renderer and input are unchanged; only its box is narrower.
- **The outpost's gate leads into the seed's only zone.** It enters at the zone's far end (chunk 2, tile 115), with a fixture hub gate (102) back to the outpost anchored there. design/01 places Outpost B beyond zone 1, which the seed does not have.

## Escalations

None.

## Open questions

- The entry tile of the seed's zone (chunk 0, tile 105) is gate 2's anchor. The adventurer therefore arrives standing on the gate back to town, and is offered to leave at once. That follows the seed, but the owner may want the zone's entry one tile away from the gate's anchor (a seed change, ENG-03's).
- `playwright-core` was added for the run and reverted, as in CLI-03a's check. The script `client/app/verify-cli03c.mjs` stays untracked on this machine. Should it become a committed development script, with `playwright-core` as a named development dependency?
- The atlas probe's 404s on every hub mount are noise, as CLI-03a's check already noted.
