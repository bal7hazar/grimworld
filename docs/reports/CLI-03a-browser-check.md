> Archived by the orchestrator of track CV on 2026-10-01 from `nexus report grimworld/impl-cli-03a` (the Mac, account claude-b7r, model claude-opus-5-5 as `nexus status` read it; job 08:31:04 → 08:34:44 UTC). A verification run of the merged sandbox (#135, #163) asked by the project manager as the owner's test of Playwright on the Mac through Nexus: nothing was committed by the agent.

# [Opus 5.5] CLI-03a — render sandbox (browser verification run)

## Summary

This was a verification run of the merged sandbox (#135, #163), not an implementation. **Playwright
launched a real Google Chrome (version 154.0.8037.59, `channel: "chrome"`, headless) on this machine.**
It drove the sandbox, served by `pnpm --filter @grimworld/app dev`, at 375 × 812 (touch, DPR 3) and
at 1440 × 900 (mouse).

Every check a browser can make passed. The sandbox opens with each of the three fixtures. A tap
becomes a tile intent, and the adventurer walks to that tile. The camera follows the adventurer on
every step. A long press or right click becomes an inspect. With idle animations off, no frame is
drawn between inputs.

I found no defect. No pull request was opened and nothing was committed.

The model is Opus 5.5, as the brief names.

## Files changed

None in git. These files are local and untracked:

- `client/app/verify-cli03a.mjs`: the Playwright script. It starts the dev server as a child process
  group, drives Chrome, and sends SIGTERM to that recorded group in `finally`.
- `client/app/.verify-out/*.png`: 16 screenshots. The atlas was absent (`atlas: none`), so they hold
  debug shapes only (D-73). They stay on this machine.
- `client/app/package.json` and `pnpm-lock.yaml`: I added `playwright-core` temporarily, then reverted
  it with `git checkout --`. `pnpm install --frozen-lockfile` then removed the package (`Packages: -1`).

## Commands run

1. `pnpm install --frozen-lockfile`: `Done in 2.3s using pnpm v12.5.1`, +217 packages. Playwright
   was not in the workspace (no `node_modules/.pnpm/*playwright*`).
2. `pnpm --filter @grimworld/app add -D playwright-core`: `Packages: +1 … Done in 3.2s`. This changed
   `client/app/package.json` (+1 line) and `pnpm-lock.yaml` (+10 lines). Both were reverted in step 4.
3. `node client/app/verify-cli03a.mjs`, one foreground command. The script spawns
   `pnpm --filter @grimworld/app dev --host 127.0.0.1 --port 5199 --strictPort`. Real output,
   trimmed:
   ```
   dev server pid 50773
   $ vite --host 127.0.0.1 --port 5199 --strictPort
     art: …/impl-cli-03a/tools/art/out not built, the sandbox draws shapes
     VITE v8.3.1  ready in 942 ms
   Chrome launched: version 154.0.8037.59

   === phone-375x812 ===
   [meadow] viewport {"width":375,"height":812}, canvas 375x812
     tile width 28.8 CSS pt (I-6: 40), tiles across 13.0
     adventurer at (9, 14), camera on (9, 14)
     atlas: none
     frames drawn 8, since last input 8
     PixiJS tickers running: none
   [cave]   … canvas 375x812, adventurer at (12, 7), camera on (12, 7), frames drawn 13, tickers none
   [edge]   … canvas 375x812, adventurer at (23, 7), camera on (23, 7), frames drawn 12, tickers none
   [tap] before: adventurer at (9, 14), camera on (9, 14); tile width 28.8
   [tap +1 tiles at (216, 406)]
     said: ["debug: [sandbox] tile (8, 14)","debug: [sandbox] tap (8, 14): walk 1 steps, 1 ticks",
            "debug: [sandbox] walk to (8, 14) from (9, 14): planned (8, 14), stepped to (8, 14), facing 0; arrived"]
     adventurer at (8, 14), camera on (8, 14)
     frames drawn 34, since last input 21
   [tap +3 tiles at (274, 406)]
     said: [… "tap (5, 14): walk 3 steps, 3 ticks", … stepped to (7, 14) … (6, 14) … (5, 14), facing 0; arrived"]
     adventurer at (5, 14), camera on (5, 14)
     frames drawn 63, since last input 24
   [inspect] said: ["debug: [sandbox] inspect (4, 15)","debug: [sandbox] inspect (4, 15): floor"]
   [idle=0] after 1 s: frames drawn 2, since last input 2; 3 s later: frames drawn 2, since last input 2

   === desktop-1440x900 ===
   [meadow] … canvas 1440x900, tile width 77.9 CSS pt (I-6: 40), tiles across 18.5,
            adventurer at (9, 14), camera on (9, 14), atlas: none, frames drawn 10, tickers none
   [cave]   … adventurer at (12, 7), camera on (12, 7), frames drawn 11, tickers none
   [edge]   … adventurer at (23, 7), camera on (23, 7), frames drawn 10, tickers none
   [tap +1 tiles at (798, 450)]  tap (8, 14): walk 1 steps … arrived; adventurer at (8, 14), camera on (8, 14)
   [tap +3 tiles at (954, 450)]  tap (5, 14): walk 3 steps … arrived; adventurer at (5, 14), camera on (5, 14)
   [inspect] (right click) inspect (4, 15): floor
   [idle=0] after 1 s: frames drawn 2, since last input 2; 3 s later: frames drawn 2, since last input 2
   dev server process group 50773 sent SIGTERM
   ```
   On every page load the console also showed `error: Failed to load resource: the server responded
   with a status of 404 (Not Found)`, two or three times. Each was followed by
   `info: [sandbox] no atlas at /art/: drawing shapes (build tools/art to see sprites)`. These are the
   atlas probes against the missing `tools/art/out`, doubled by React's development double mount.
   There was no `pageerror` and no other error.
4. `git checkout -- client/app/package.json pnpm-lock.yaml`: no output.
5. `pnpm install --frozen-lockfile`: `Packages: -1 … Done in 161ms`.
6. `git status --short`: shows only `?? client/app/.verify-out/` and `?? client/app/verify-cli03a.mjs`.
7. `curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:5199/`: printed `000` and
   exited with code 7 (connection refused). So the dev server is stopped.

Waits: the script contains only fixed sleeps (300 ms to 3 s) and Playwright's `waitForSelector`. No
wait timed out and no step failed.

## Commands refused by the permission profile

Each was refused automatically ("requires approval, and this session has no approval surface"):

1. A compound command:
   `ls client/app/src …; cat client/app/vite.config.ts; node --version; pnpm --version; ls ~/Library/Caches/ms-playwright 2>&1; ls "/Applications/Google Chrome.app" …`.
   Refused as "multiple operations". I re-ran the parts separately.
2. `ls ~/Library/Caches/ms-playwright`: refused because it is outside the working directory.
3. `ls "/Applications/Google Chrome.app/Contents/MacOS"`: refused because it is outside the working
   directory. Chrome's presence was shown instead by Playwright launching it.
4. `lsof -nP -iTCP:5199 -sTCP:LISTEN`, the check that the dev server had stopped: "This command
   requires approval". I replaced it with the `curl` check in step 7.

## Acceptance criteria (what a browser can check)

- **The sandbox opens; `?fixture=` selects each fixture (AC-1): passed.** `meadow`, `cave` and
  `edge` each loaded with a different adventurer tile: (9, 14), (12, 7) and (23, 7). The canvas
  filled the viewport. The meadow screenshot shows the description "Open meadow, 2 × 2 chunks; a pack
  of five asleep north-west". Without the atlas the sandbox reported `atlas: none` and drew shapes.
  The atlas-loaded branch was not exercised, because no atlas exists here and I was told not to
  build one.
- **375 × 812 and a desktop window: passed.**
  - Phone: canvas 375 × 812. Default zoom gives 13.0 tiles across, a tile width of 28.8 CSS pt
    (I-6 asks for 40), DPR 3, canvas resolution 2.
  - Desktop: canvas 1440 × 900, 18.5 tiles across, tile width 77.9.
- **A tap turns into an intent: passed.** A tap one tile east of the adventurer resolved to
  `tile (8, 14)`. The sandbox applied it through the placeholders (`walk 1 steps, 1 ticks`). A tap
  three tiles east gave `walk 3 steps, 3 ticks`. This worked with touch (`touchscreen.tap`) and with
  a mouse click. A long press (CDP touch, 900 ms) and a right click each gave `inspect (4, 15): floor`.
- **The camera follows: passed.** After each walk the panel read `camera on` equal to `adventurer at`:
  (8, 14), then (5, 14), on both viewports. In the screenshot after the walk, the adventurer's shape is
  still at the centre of the viewport, with its wedge pointing right (facing 0, east).
- **On demand (the browser side of AC-2): passed.**
  - The panel read `PixiJS tickers running: none` on every page.
  - With `idle=0`, the frame count stayed at 2 over 3 s with no input.
  - With idle animations on, frames since the last input stayed bounded (21 to 27 after a walk).
- I did not measure pinch, drag, wheel, the "back to the adventurer" button, or the rate of 15 fps or
  fewer with idle animations on.

## Deviations from the brief

- To run Playwright I had to add `playwright-core` to `client/app`, because no Playwright existed in
  the workspace. It was reverted, and nothing was committed.
- I used `channel: "chrome"` in headless mode, not a headed window.

## Escalations

None.

Something that may look like a bug but is not: tapping to the right of the adventurer lowers `x`
(9 → 8), and tapping above it raises `y`. This is the documented convention of
`client/app/src/input/coords.ts:10-13`, from origami_hexmap: x grows to the West and y grows to the
North.

## Open questions

- The 404s in the console when no atlas is built are noise. Should the atlas probe stay silent
  (for example, a HEAD request, or the dev middleware answering 204) so that the only console line
  is the info message?
- The default zoom gives 28.8 pt tiles on 375 px, against I-6's 40 pt. The tile size is still the
  owner's decision, after SPK-6.
- Should I delete `client/app/verify-cli03a.mjs` and `client/app/.verify-out/`, or keep them for the
  orchestrator to look at?
