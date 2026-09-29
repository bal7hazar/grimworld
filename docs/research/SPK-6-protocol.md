# SPK-6 — The protocol on real phones

Written on 2026-09-29 by `[Opus 5.5]` (task SPK-6a), for the orchestrator of track CV. It says how
SPK-6 is run so that its result decides [ADR-0003](../architecture/ADR-0003-client.md) (PixiJS on
demand in a web view) without argument. **Nothing here was measured on a phone.** Every claim about
a tool or an API carries a source read on 2026-09-29 (§11), or the mark *(unverified)*.

## Summary

| Question | Answer |
|---|---|
| What is measured | CLI-03a's rendering sandbox (fixed data, no chain), then the same sandbox in a Capacitor shell, then CLI-01's burner in the shell |
| Stages | **6-A**, the phone's browser, runnable as soon as CLI-03a and the sandbox needs of §9 (points 1–8) are merged. **6-B**, a Capacitor shell around the sandbox (§9 point 9). **6-C**, 50 transactions from the burner in the shell, after CLI-01 (and FND-08 for Sepolia) |
| Devices | One iPhone and one mid-range Android with a display of 90 Hz or more, the owner's own if they fit (§1) |
| The rows | Six rows of ADR-0003's table plus frame time on demand, each with an instrument per platform, conditions, runs and a threshold (§3, §7) |
| Runs per device | Three 30-minute play runs of the product build, one of a forced render loop, one still baseline; short diagnostic runs for each power rule; 100 taps per zoom (§3.4) |
| What triggers the fallback (Godot, then Unity) | Only battery, heat, idle and steady animation, on the product build, **in the shell**, on the median of the runs, after the switches show the cost is the renderer's and not a fixable defect of the sandbox (§7.2). Taps and transactions never do: they are not the renderer's |
| The owner's part | §10: the phones, the Mac's tools, about one day per phone, and three spending options, none required |
| Plan issue | PLAN has CLI-01 depend on SPK-6, while the transactions row needs CLI-01's burner in the shell: 6-C runs after CLI-01, and SPK-6 is closed in two steps (escalated in the report) |

## 1. Devices

### 1.1 The minimum set

| Slot | Why | How to choose it |
|---|---|---|
| **One iPhone** | iOS is 32.36 % of mobile systems worldwide (StatCounter, August 2026 [S-30]) and Apple the first vendor at 32.35 % [S-31]; WebKit is the only engine on iOS, in Safari and in the shell alike | A recent non-Pro model (a 60 Hz display) stands for most players. If the owner's iPhone is a Pro (ProMotion, 120 Hz), it is the harsher case for the frame callback and is kept (§1.2) |
| **One mid-range Android** | Android is 67.61 % [S-30]; Samsung 19.72 %, Xiaomi 10.48 % of vendors [S-31]. A flagship would flatter the result | A Samsung Galaxy A or a Xiaomi Redmi of the last three years *(that these are the best-selling mid-range lines is unverified)*, **with a display of 90 or 120 Hz**: that is the case where an uncapped loop runs faster than 60 Hz (ADR-0003) |
| Optional: a Pixel 6 or later | Its power rails (ODPM) give the Android Studio Power Profiler and Perfetto's battery counters in µAh, not only a percentage [S-12] [S-13] | Only if the owner decides to buy one (§10) |

Not in the set: tablets, landscape (UI-2), phones older than the OS versions below.

### 1.2 Refresh rate: why it matters, and what is recorded

- A `requestAnimationFrame` callback generally follows the display's refresh rate and is paused in
  hidden pages [S-20]. On Android, several refresh rates exist since Android 11, and the developer
  option *Show refresh rate* displays the current one [S-17]. A render loop that is not on demand
  therefore costs 1.5× or 2× more on a 90 or 120 Hz Android than on a 60 Hz phone.
- ADR-0003 says iOS web views are capped at 60 Hz. WebKit's bug tracker records 120 Hz
  `requestAnimationFrame` on iPhone Pro as fixed in the iOS 18 cycle, behind Safari's feature flag
  *Prefer Page Rendering Updates near 60fps* [S-8]; Apple's documentation of that flag and of its
  default in WKWebView was not found *(unverified)*. Native apps opt into more than 60 Hz with
  `CADisableMinimumFrameDurationOnPhone` [S-7], whose effect on a web view in the app is
  *(unverified)*. **So the rate is measured, never assumed**: the sandbox measures it at the start of
  each run (§9 point 4) and the record holds it, in the browser and in the shell.
- Low Power Mode throttles `requestAnimationFrame` to 30 fps on iOS (WebKit bug, fixed in 2017 [S-9])
  and reduces CPU and GPU performance [S-10]: **Low Power Mode and Android's battery saver are off**
  in every run, and their state is recorded.

### 1.3 What the owner is asked to provide about each phone

Model, OS version, browser version (Android: also the WebView package's version [S-19]), battery
health (iOS Settings > Battery > Battery Health [S-4]; Android: as the maker shows it, or
"unknown"), the display's maximum refresh rate, and whether the phone may run a 30-minute session
five times on a day. A phone whose battery health is under 85 % is flagged: its drain is
over-estimated against a new battery (proposal, §7).

## 2. Builds

### 2.1 What is measured

CLI-03a's sandbox (the brief [S-40]), **the production build** (`pnpm --filter @grimworld/app build`,
served by `vite preview`), never the dev server (unminified code and the hot-reload socket would be
measured). The sandbox draws the pack's sprites only from the dev server today (CLI-03a scope 9);
measuring shapes instead of sprites would under-state texture and GPU cost, so a **local measurement
build with the atlas** is a need (§9 point 1). The build's commit is recorded in every run.

The fixture: the one with **ten actors** (CLI-03a scope 2, "a room of 15 × 15 with 10 animated
actors"), at the default zoom.

### 2.2 In which shells, and what waits for CLI-01

| Stage | Shell | Needs | Measures that count |
|---|---|---|---|
| **6-A** | Safari on the iPhone, Chrome on the Android, the page served from the Mac on the local network | CLI-03a + §9 points 1–8 | **Final**: frame time on demand, steady animation and dropped input, taps (the geometry is the same in any shell). **Provisional**: battery, heat, idle, the power rules' effects |
| **6-B** | A Capacitor shell (iOS WKWebView, Android WebView) around the same build, no chain | §9 point 9 (a thin shell; CLI-01 or a task of its own) | **Final**: battery, heat, idle. The rows of 6-A are repeated once to check the shell changes nothing |
| **6-C** | CLI-01's shell with the burner | CLI-01; FND-08 for Sepolia | **Final**: 50 transactions, no prompt, no fee (§6) |

Rule between 6-A and 6-B: if 6-A passes, 6-B confirms with **one** run per row and device instead of
three, unless a result lands within the margin of §3.5. If 6-A fails a row, 6-B runs the full set
for that row before any conclusion: a browser adds its own interface and process model, and a
failure there is a warning, not a verdict.

Android WebView is updatable apart from the system [S-19]; that Chrome and the WebView run the same
Chromium release on a given day is *(unverified)*: both versions are recorded.

### 2.3 The build switch: each power rule measured, not assumed

URL parameters of the sandbox (§9 point 2), one rule each, recorded in the run log:

| Switch | Values (product first) | Rule of ADR-0003 it isolates |
|---|---|---|
| `loop` | `demand` · `forced` (a PixiJS ticker at the display rate) | No permanent render loop |
| `idle` | `on` · `off` | Idle animations pausable |
| `idlefps` | `12` · `15` · `display` | Idle animations capped at 12–15 fps |
| `res` | `cap2` (integer multiple, capped at 2× device pixels) · `dpr` (the device's ratio, 3 on most iPhones) | Resolution |
| `static` | `baked` · `live` (ground, walls and grid drawn as separate objects each frame) | Static layers baked |
| `overlay` | `off` · `on` | The debug overlay itself (§9 point 8): off in every measured run |

The product build is `loop=demand&idle=on&idlefps=12&res=cap2&static=baked&overlay=off` (whether 12 or
15 fps is the product default is the owner's call; both are measured). The background rule
(everything stops when the page is hidden) is checked by the log's counters across a
`visibilitychange` [S-22], not by a switch.

## 3. Measures and instruments

### 3.1 The instruments, per platform

| Instrument | Platform | What it gives | Source |
|---|---|---|---|
| **The sandbox's run log** (§9 point 3) | Both | Per second: `requestAnimationFrame` callbacks, frames drawn, CPU time of each `render()` (`performance.now()` around it), bake times; taps and intents; `visibilitychange`; the measured refresh rate; the switches; the build commit | [S-20] [S-22] |
| `PerformanceObserver`, `event` entries (Event Timing) | Chrome/WebView 76+, Safari 26.2+ | Each tap's input delay and the time to the next paint | [S-21] |
| `PerformanceObserver`, `long-animation-frame` | Chrome/WebView 123+ only; not Safari | Frames longer than 50 ms and their scripts | [S-21] |
| Battery Status API `navigator.getBattery()` | Chrome Android and WebView only, secure context; never Safari | The level, precision not guaranteed ("SHOULD not expose high precision readouts") | [S-23] [S-24] |
| Compute Pressure API | Chrome desktop only; **not** Chrome Android, WebView or Safari | Not usable on the phones | [S-25] |
| **Power Profiler** (Instruments, or on the phone: Settings > Developer > Performance Trace) | iPhone on **iOS 26 or later** | Per-process power impact from CPU, GPU, display and networking; system power as a share of the battery per hour; charger state, **thermal state**, display brightness. On-device recording lasts up to 10 hours without a Mac attached. Recording "All Processes" gives the system only | [S-1] |
| Settings > Battery | iOS | Level and per-app share of use over the recent days; Battery Health | [S-4] |
| `UIDevice.batteryLevel` | iOS, native (6-B) | 0.0–1.0; change notifications at most once a minute; Apple advises against computing a drain rate from them; granularity not documented *(5 % steps: unverified)* | [S-5] |
| `ProcessInfo.thermalState` | iOS, native (6-B) | `nominal`, `fair`, `serious` ("reduces performance"), `critical` | [S-3] |
| Web Inspector, remote (Safari on the Mac, Develop menu), Timelines | iOS, Safari and the shell (`isInspectable`, iOS 16.4+; Capacitor `ios.webContentsDebuggingEnabled`) | Frames, JavaScript & Events, Layout & Rendering, **CPU** of all the page's threads sampled every 500 ms with a rating (Low under 3 %, Medium under 30 %), Memory. The phone needs Settings > Safari > Advanced > Web Inspector | [S-6] [S-26] |
| Xcode Energy Impact gauge, Time Profiler | iOS shell | Native side of the shell only; Apple's gauge documentation is archived; attaching to the web view's process is not documented *(unverified)* | [S-2] |
| MetricKit | iOS shell | Daily CPU and GPU time and display luminance; **no energy total**; its `MX*` classes are deprecated from iOS 27.2 | [S-11] |
| `dumpsys batterystats --reset` / `--charged <package>`, `adb bugreport` + Battery Historian | Android | Per-app estimated use since the reset. Google's guide: disconnect from the computer so that only the battery supplies current | [S-14] [S-15] |
| `dumpsys battery unplug` / `reset` | Android | Makes the system behave as unplugged; documented for Doze testing, **not** for power measurement: the USB current still flows | [S-16] |
| **Perfetto**, `record_android_trace` or ui.perfetto.dev | Android 6+ (command line), 11+ (WebUSB) | Scheduling and CPU frequency per process; battery counters `batt.charge_uah`, `capacity_pct`, `current_ua` on most Pixels; power rails on few phones; thermal temperatures by ftrace; FrameTimeline (Android 12+). **On USB the counters read the charging current** | [S-12] |
| Android Studio Power Profiler | Pixel 6 or later, Android 10+ | Power rails (CPU clusters, GPU, display, memory, radios) and battery; the whole device, not one app | [S-13] |
| `PowerManager.getCurrentThermalStatus()`, listener | Android 10 (API 29)+, native (6-B) | `NONE`, `LIGHT` ("light throttling, UX isn't impacted"), `MODERATE`, `SEVERE`, `CRITICAL`… | [S-18] |
| `PowerManager.getThermalHeadroom(forecast)` | Android, API level disputed between two Google pages (30 or 33) *(unverified)* | 0.0 no throttling, 1.0 `SEVERE`; NaN if called more than once per 10 s | [S-18] |
| `adb shell dumpsys thermalservice` | Android, before 6-B | The thermal status without an app *(unverified: no official page)* | — |
| `dumpsys gfxinfo <package> framestats` | Android | Frame timings of the app's own UI | [S-15] |
| Chrome remote debugging (`chrome://inspect`), WebView debugging | Android | DevTools Performance panel; Rendering > *Frame rendering stats* (rendered, partially presented and dropped frames) | [S-27] [S-28] |
| Device's own *Show refresh rate* overlay | Android | The display rate during the run | [S-17] |

### 3.2 Per row: instrument, conditions, runs, threshold

"Page log" is the sandbox's run log. "C-play", "C-diag" are the conditions of §3.3. The thresholds are
argued in §7.

| # | Row | iOS | Android | Conditions | Runs per device | Threshold (§7) |
|---|---|---|---|---|---|---|
| R-1 | **Frame time on demand** | Page log (`render()` CPU time, the bake's time); Web Inspector Timelines (Frames, CPU) | Page log; Perfetto FrameTimeline and scheduling; DevTools *Frame rendering stats* | C-diag, the session script's first 10 minutes (§4), product build | 3 | `render()` p95 ≤ 8 ms, max ≤ 16.7 ms excluding the first frame; bake reported (§7) |
| R-2 | **Steady animation, no dropped input** (room 15 × 15, 10 animated actors) | Page log (frame intervals while something animates; taps vs intents); Event Timing (Safari 26.2+) | Page log; Event Timing; `long-animation-frame` | C-play, all 30 minutes of the product runs (R-3's runs) | 3 (the same runs as R-3) | Every tap gives one intent; tap to next paint p95 ≤ 100 ms; ≤ 1 % of animation frames later than 2 display intervals |
| R-3 | **Battery drain over 30 minutes** | System level at start and end (status bar percentage, Settings > Battery); Power Profiler on the phone (share of battery per hour, 6-A and 6-B) | System level (`dumpsys battery` after the run, or the status bar); `batterystats --charged` after the run; Perfetto battery counters on a Pixel only; `getBattery()` in the page log | C-play, the session script (§4), unplugged | Product: 3. Forced loop: 1. Still baseline (idle off, no input, 30 min): 1 | Product median ≤ 8 points; forced loop and baseline reported beside it |
| R-4 | **No thermal throttling after 30 minutes** | Power Profiler's thermal state (6-A); `ProcessInfo.thermalState` in the page log (6-B) | `dumpsys thermalservice` before and after (6-A, unverified); `getCurrentThermalStatus` listener in the page log (6-B); Perfetto thermal temperatures | Same runs as R-3; cold start (§3.3) | 3 (the same runs) | iOS: `nominal` or `fair` throughout. Android: `NONE` throughout. Plus `render()` p95 of the last 5 minutes ≤ 1.2× the first 5 |
| R-5 | **Idle screen, 5 minutes, idle animations off** | Page log (callbacks, frames); Web Inspector CPU timeline | Page log; Perfetto scheduling of the page's processes; DevTools Performance | C-diag; the ten-actor fixture after one move, then no touch for 1 minute to settle and 5 minutes measured | 3 | 0 frames drawn and 0 `requestAnimationFrame` callbacks; CPU of the page ≤ 3 % on average ("Low" in WebKit's rating) |
| R-5b | Idle, 5 minutes, idle animations **on** (not an ADR row: the setting's default) | As R-5 | As R-5 | As R-5 | 3 | Frames ≤ the `idlefps` cap per second; CPU reported; the owner rules the default from R-3's two figures |
| R-6 | **50 transactions from the burner** | The shell's transaction log; a text scan of the screen; the person watching | Same | §6 | 1 of 50 per network | 50 of 50 confirmed, 0 prompts, 0 forbidden words (§6) |
| R-7 | **Taps on the intended tile** | The tap log (§5) | Same | §5 | 100 taps per zoom, per person, per device | Default zoom: misses ≤ 2 %, median distance ≤ 0.3 tile; closer zoom: misses ≤ 1 % (§5) |
| R-8 | **The power rules' effects** (each switch of §2.3 alone) | Power Profiler (share of battery per hour); Web Inspector CPU | Perfetto (CPU time of the page's processes; battery counters on a Pixel) | C-diag, a 5-minute slice of the session script (§4, block 1) per switch value | 2 per value | None: reported, so that each rule's saving is a figure (§7) |

### 3.3 Conditions

**C-play** (the battery and heat runs):

| Condition | Rule |
|---|---|
| Charge at start | Between 80 % and 90 %, the same ±2 points for every run of a device; unplugged 5 minutes before the start |
| Cable | **None** during the run: USB supplies current and distorts the counters [S-12] [S-14]. On Android, the page is loaded while connected if needed, then unplugged; the sandbox needs no network after loading (fixtures only) |
| Temperature | The phone at room temperature, screen off and untouched 15 minutes before; out of its case, on a table between moves, held by the thumb during them; the room between 20 and 25 °C, its temperature recorded (or "unmeasured") |
| Screen | Automatic brightness off, the brightness slider at the same position for every run (recorded); Night Shift, True Tone and their Android equivalents off; auto-lock off; the percentage shown in the status bar |
| Radios | 6-A and 6-B: **aeroplane mode** after the page is loaded (no Wi-Fi, no cellular, no Bluetooth, no location), since nothing is fetched. 6-C: Wi-Fi only |
| System | Low Power Mode and battery saver off; Do Not Disturb on; every other app closed; no update installing; the same OS build for all runs of a device |
| App | In the foreground for the whole run; the browser's other tabs closed |
| Instruments | Only those that run on the phone without a cable (the page log; iOS Power Profiler recorded on the phone). No Web Inspector or DevTools attached: they cost power |
| Between runs | Recharge to the start band, then 15 minutes of rest |

**C-diag** (frame time, idle, the switches, taps): plugged in allowed, instruments attached, the same
screen and system settings. Their figures are never battery figures, except the iOS Power Profiler's
share per hour, which is compared between switches of the same session and never with R-3.

### 3.4 How many runs, and what it costs the owner

Per device, stage 6-A: 5 runs of 30 minutes (3 product, 1 forced loop, 1 baseline), about 1 hour each
with recharge and rest; 3 idle runs of 6 minutes; the switches, 11 values × 2 runs × 5 minutes; 200
taps per person. **About one day per phone**; the baseline runs while the person plays the other
phone. Stage 6-B repeats one run per row and device (§2.2), about half a day for the pair.

### 3.5 Variance, and when to add runs

- Every run's figures are recorded (§8); a row reports the **median** and the **range** (min–max) of
  its runs, never a mean alone.
- Battery levels are whole percentage points: a drain is known to ±1 point. If the median of R-3 is
  within 1 point of the threshold (7 to 9 %), two more runs are made and the median of five decides.
- Frame figures are reported as p50, p95, p99 and max per run, from the page log's histogram.
- A single run outside the threshold while the median passes is reported with its conditions, never
  dropped.

## 4. The session played (30 minutes)

A person follows it with a stopwatch and this page printed or on another screen. The ten-actor
fixture, default zoom, phone in portrait, one thumb. Six blocks of 5 minutes, identical:

| Time in the block | Do | Counts |
|---|---|---|
| 0:00–1:00 | **Moves**: tap a floor tile one to three tiles away, about one tap every 3 seconds, walking a loop through the room | 20 taps |
| 1:00–1:30 | **Attacks**: tap a goblin next to the adventurer (the stand-in strike animation plays, §9 point 7), about one every 3 seconds | 10 taps |
| 1:30–2:00 | **Pinch and pan**: pinch to the closer zoom, drag across the room and back, pinch back to the default, press the re-centre button | 1 cycle |
| 2:00–2:15 | **Inspect**: long press on three goblins | 3 presses |
| 2:15–4:45 | **Still**: hands off, the screen on; only idle animations move | 2:30 |
| 4:45–5:00 | **Turn and select**: tap a goblin far away (its arcs are shown), tap outside to clear | 2 taps |

Totals over 30 minutes: 120 moves, 60 attacks, 6 pinch-and-pan cycles, 18 long presses, 15 minutes
still, 12 selections. A tap that does nothing (a wall) counts; a missed step is not replayed. The run
log marks the start and the end (buttons of the sandbox) and the person writes down any deviation
(a call, a notification, a pause).

The forced-loop run and the product runs follow the same script. The still baseline is the same
fixture with `idle=off`, started, then untouched for 30 minutes.

## 5. Taps

**What is measured**: whether a tap by the thumb, in portrait, lands on the tile the player meant, at
the default zoom (13 tiles across, ADR-0006 §5: about 28.8 CSS pixels a tile at 375, 30 at 390) and at
the closer zoom (9 tiles across).

**How**: the sandbox's tap-test mode (§9 point 5) highlights a **target tile**; the person taps it
with the thumb of the hand holding the phone; the next target appears. 100 targets per zoom, from a
**fixed list** spread over the whole sight hexagon (its centre, its six edges, the tiles near the top
of the screen far from the thumb, and those next to the adventurer and next to a goblin), the same
list for every run, so that runs compare. A miss is not retried.

**What the sandbox logs, per tap** (CLI-03a's intent already carries the tile it resolved):

| Field | Why |
|---|---|
| Target tile, resolved tile, hit or miss | The error rate |
| Touch point and the target's centre, in CSS pixels; the distance in tile widths; its direction | How far off, and whether misses lean one way (the thumb's side, the top of the screen) |
| Zoom, tile width in CSS pixels, `devicePixelRatio`, viewport size | The geometry of the run |
| Time from the target shown to `pointerup`; the press's duration | A hurried tap; a tap read as a long press |
| Pointer type, and the touch's radius where the browser gives one *(unverified per browser)* | The thumb's contact size |
| Whether the resolved tile would change under "snap to the nearest valid tile" (ADR-0006 §5) | Snapping reported beside the raw figure, never instead of it |
| Hand and person (entered once at the start) | Different thumbs |

**Threshold proposed** (argued in §7): at the default zoom, **misses ≤ 2 %** and median distance
**≤ 0.3 tile width**; at the closer zoom, misses ≤ 1 %. With 100 taps an observed rate is uncertain by
about 3 points (0 misses out of 100 still allows about 3 % at 95 % confidence, the rule of three): if
the observed rate is between 1 % and 4 %, 100 more taps are made. At least the owner; a second person
with other hands is better and costs nothing.

## 6. Transactions (stage 6-C)

**What**: 50 actions in a row played in CLI-01's shell, each sent by the burner (ADR-0005 stage A;
`client/app/src/account/burner.ts` exists since FND-05, the funder is FND-08), with no prompt and no
fee on screen. It needs CLI-01's shell and a network; **it waits for CLI-01**.

| Network | How the phone reaches it | Notes |
|---|---|---|
| **Local node** on the Mac (`scripts/with-node.sh`) | Android: through `adb reverse` to the phone's `localhost` *(unverified)*. iOS: over the local network | `with-node.sh` binds `127.0.0.1` today: a host option is needed (a change to `scripts/`, the orchestrator's). **On iOS 14+, an app that reaches the local network shows a system permission prompt** [S-29]: it would count as a prompt, so on iOS the local node checks the burner's path but cannot pass the "no prompt" row. Android blocks clear-text HTTP by default *(unverified)*: the shell's network configuration must allow it for the node's address |
| **Sepolia** | The phone's Wi-Fi, through the RPC | **Run by the orchestrator's session, never by an agent**; after FND-08's funder (D-150); the burner's funding and every transaction's cost counted and reported (COMMON §4, OPERATIONS §7). The row's passing run |

**What counts**:

- 50 actions played by the person, one tap each, within the session script's moves (§4, block 1
  repeated as needed), **each sent as its own transaction** (the strictest case for prompts; D-133's
  batches change the count of transactions, not what the screen may show: open question).
- The shell logs per transaction: when played, sent, accepted and confirmed, and any failure.
- **No prompt**: the person watches and writes down any dialog, sheet or permission request, system
  or app; the run is also recorded by the shell's log of focus changes.
- **No fee shown**: an automatic scan of the DOM's text after each action for the words of design/11's
  *Never* column (wallet, address, key, gas, sign, token, network, block, mint, fee, transaction,
  pending, batch). Native dialogs are the person's to watch.
- Pass: 50 of 50 confirmed, 0 prompts, 0 forbidden words. A failure here is a CLI-01 or ADR-0005
  matter, not the renderer's (§7.2).

## 7. Thresholds

### 7.1 Each row

| Row | ADR-0003 proposes | This protocol proposes | Why |
|---|---|---|---|
| R-1 Frame time on demand | — (not in the table) | `render()` p95 ≤ 8 ms and max ≤ 16.7 ms, the first frame after loading excluded; the bake of the static layers reported, and ≤ 16.7 ms at p95 | 16.7 ms is one frame at 60 Hz; half of it leaves room for the browser's own work and the compositor. A render that fits keeps on-demand drawing cheap. A slow bake is a sandbox fix (bake off the step's frames), not a fallback |
| R-2 Steady animation, no dropped input | "Steady animation, no dropped input" | Every tap yields exactly one intent; tap to next paint p95 ≤ 100 ms (Event Timing where available, the page log otherwise); ≤ 1 % of the frames of a step, turn or strike later than two display intervals | "Steady" and "dropped" made countable. 100 ms is this protocol's reading of I-2 ("the result is drawn at once") *(a proposal, not a sourced standard)* |
| R-3 Battery | ≤ 8 % over 30 minutes on the reference phones | Kept: median ≤ 8 points on each of the two phones of §1, battery health ≥ 85 %; the forced loop's and the baseline's drains reported | 8 % in 30 minutes is about 6 hours of play for a full charge, a fair bar for a still game. The baseline shows how much of it is the screen alone, the forced loop how much the rules save. A worn battery reads high, hence the health bound |
| R-4 Heat | No thermal throttling reported by the system | iOS: `nominal` or `fair` throughout; Android: `NONE` throughout. A reading of `serious` (iOS) or `MODERATE` or above (Android) fails. `LIGHT` on Android is borderline: two more runs, and the owner rules | Apple documents `serious` as the state where the system reduces performance [S-3]; Android documents `LIGHT` as light throttling that does not affect the user [S-18]. The ADR's wording ("no throttling") read strictly fails `LIGHT`; that strictness is the owner's to confirm. The frame-time ratio (last 5 minutes against first 5, ≤ 1.2) catches throttling the system does not report *(a proposal)* |
| R-5 Idle, 5 minutes | Near-zero processor use with idle animations off | 0 frames drawn, 0 animation callbacks, and the page's CPU ≤ 3 % on average | "Near-zero" made countable: the counters prove no loop runs; 3 % is WebKit's own boundary of "Low" energy [S-26]; on Android the same figure is read from Perfetto |
| R-6 Transactions | 50 actions in a row, no prompt, no fee shown | Kept, as §6; on iOS the passing run is on Sepolia (the local node's permission prompt, §6) | — |
| R-7 Taps | Taps land on the intended tile at the default zoom | Default zoom: misses ≤ 2 %, median distance ≤ 0.3 tile width; closer zoom: ≤ 1 % | A move is played on the tap and cannot be undone (I-5): at 2 %, one action in 50 goes astray, the most a fight can bear. 0.3 tile keeps a margin inside a hexagon whose inner radius is 0.5 tile width. If the default zoom fails and the closer passes, the answer is a zoom or a tile size (ADR-0006 §5, UI-1), not an engine |
| R-8 The rules' effects | — | No threshold: each switch's figure is reported | The ADR's rules are binding; this row shows what each one buys, so that none is kept or dropped on faith |

### 7.2 What triggers the fallback

The ADR's fallback (a second spike on Godot, then Unity) is triggered only when **all** hold:

1. The row is **R-2, R-3, R-4 or R-5**: the ones the renderer and the web view decide. R-1 alone is a
   diagnosis; R-6 is CLI-01's and ADR-0005's; R-7 is the design's (tile size, zoom); R-8 has no
   threshold.
2. It fails on the **product build, in the shell (6-B)**, on the **median** of its runs, on at least
   one reference phone.
3. The switches (R-8) and the page log show the cost is **the web view's or PixiJS's**, not a defect
   of the sandbox that CLI-03 can fix: a stray animation callback, a bake every frame, an overlay
   left on, a resolution above the cap, a loop that does not stop when the page is hidden. A defect
   found is fixed and the row re-run first.
4. The owner has seen the figures: the fallback is the owner's decision on the orchestrator's report.

## 8. Recording a run

### 8.1 Where

| What | Where |
|---|---|
| The protocol | This file |
| One record per device and stage | `docs/research/SPK-6-<stage>-<device>.md` (for example `SPK-6-A-iphone-15.md`), the template below |
| The verdict | `docs/research/SPK-6-results.md`: each row, each device, median and range, pass or fail, and the decision it supports |
| The page logs (JSON, small, no image) | Committed beside the record, under `spikes/SPK-6/runs/<run-id>.json`, if each is under 1 MB; otherwise as the traces |
| Instrument files (Perfetto traces, Instruments and on-device performance traces, bug reports) | **Outside git**, on the Mac, under a folder the orchestrator names (for example `~/grimworld-spk6/<run-id>/`); the record lists each file's name, size and SHA-256 |

### 8.2 No capture of the screen (D-73)

**No screenshot, screen recording or photograph of the screen showing the pack's art is committed,
posted in a pull request or a comment, or attached to a record.** A trace or a figure is fine; a
capture of the screen is not. In practice:

- The DevTools Performance panel and some profilers can store screenshots inside a trace *(that
  DevTools records them by default is unverified)*: turn screenshots off before recording, and never
  share a trace that holds them.
- An Android bug report may hold a screenshot *(unverified)*: bug reports stay outside git, like
  every instrument file.
- Captures of shapes only, with the atlas absent, fall under the track's rule for debug shapes
  (ORCH-client-visual): allowed, but not needed by this protocol.

### 8.3 The template

```markdown
# SPK-6 — <stage 6-A | 6-B | 6-C>, <device>

| | |
|---|---|
| Date, person | |
| Device | model; OS and build; browser or shell and its version; WebView package version (Android) |
| Display | maximum refresh rate; refresh rate measured by the sandbox; `devicePixelRatio`; viewport |
| Battery | health; charge at start of each run |
| Build | commit; `loop`, `idle`, `idlefps`, `res`, `static`, `overlay`; fixture; zoom; atlas present (yes/no) |
| Conditions | C-play or C-diag; brightness slider position; aeroplane mode; Low Power Mode / battery saver off; room temperature; deviations |
| Instrument files | name, size, SHA-256, where kept (outside git) |

## Runs

| Run | Row | Start–end | Start % | End % | Drain | Energy (instrument) | Thermal (worst) | render() p50/p95/p99/max ms | Late frames % | Tap→paint p95 ms | Frames / callbacks idle | CPU idle % | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

## Taps

| Zoom | Person, hand | Taps | Misses | Miss % | Median distance (tile) | p95 distance | Would snapping change it (count) | Notes |
|---|---|---|---|---|---|---|---|---|

## Transactions (6-C)

| Network | Actions | Confirmed | Prompts seen | Forbidden words | Median played→confirmed s | Total cost (Sepolia) | Notes |
|---|---|---|---|---|---|---|---|

## Rows

| Row | Median | Range | Threshold | Pass |
|---|---|---|---|---|

## What was not as the protocol says
```

## 9. What the sandbox still needs

For the orchestrator to brief; points 1–8 are client work on CLI-03a's sandbox, point 9 is a
Capacitor shell, points 10–11 belong to CLI-01 and `scripts/`.

1. **A local measurement build with the atlas**: the production build (or `vite preview`) serving
   `tools/art/out/` on the Mac only, reachable from a phone on the local network (a `--host`
   option), never in `dist/` of CI, never committed (D-73).
2. **The switches of §2.3** as URL parameters (`loop`, `idle`, `idlefps`, `res`, `static`,
   `overlay`), each shown in the run log; `loop=forced` is a PixiJS ticker at the display rate.
3. **A run log**: start and stop buttons; per second the animation callbacks, frames drawn, and a
   histogram of `render()` CPU times; each bake's time; each tap and its intent; Event Timing and,
   in Chrome, long-animation-frame entries; `visibilitychange`; `getBattery()` where it exists; the
   user agent, `devicePixelRatio`, viewport; the switches; the build's commit, injected at build
   time. Kept in memory, exported at the end as a JSON file download; **nothing sent over the
   network**, no image in it.
4. **A refresh-rate probe**: two seconds of animation callbacks before a run starts, their median
   interval recorded, then stopped.
5. **A tap-test mode** (§5): the fixed list of 100 targets per zoom, the highlight, the fields of §5
   per tap, no retry.
6. **The session's time in the log**: the elapsed time shown only on request, so that the person can
   follow §4 (a printed script and a stopwatch are enough otherwise).
7. **A stand-in strike animation** on a tap on a goblin next to the adventurer, at the idle
   animations' frame rate, so that the "attacks" of §4 load the renderer as the game will (CLI-03a
   has no combat).
8. **The debug overlay can be hidden**, and when shown updates at most once a second: measured runs
   are made with it off.
9. **A thin Capacitor shell** around the sandbox (stage 6-B), iOS and Android, no chain: inspection
   enabled in measurement builds (Capacitor `webContentsDebuggingEnabled`, iOS `isInspectable`
   [S-6]); a native read of the thermal state (iOS `ProcessInfo.thermalState` [S-3]; Android
   `getCurrentThermalStatus` and its listener [S-18]) and of the battery (Capacitor Device
   `getBatteryInfo` [S-32]) written into the run log. CLI-03a's brief put Capacitor out of its scope:
   CLI-01, or a task of its own before CLI-01 so that 6-B does not wait for the chain.
10. **CLI-01**: the burner in the shell, a "50 actions" run with the per-transaction log and the text
    scan of §6.
11. **`scripts/with-node.sh`**: a host option so that a phone can reach the local node (§6).

## 10. The owner's part

1. **Phones**: say which iPhone and which Android you have (model, OS, battery health, refresh
   rate), and whether they may be used for about one day each. The set needs one iPhone and one
   mid-range Android of 90 Hz or more (§1).
2. **The Mac's tools**, free, to install when SPK-6 runs (an installation is your decision): Xcode
   (Web Inspector needs only Safari; Xcode builds the shell for 6-B), Android's platform tools
   (`adb`); Perfetto runs in the browser. Android Studio only for a Pixel's Power Profiler.
3. **iOS 26 or later on the iPhone**, for the Power Profiler [S-1]; without it, battery and heat on
   iOS rest on the battery percentage and, in the shell, `thermalState`.
4. **An Apple account for the shell**: a free account installs your own builds on your own iPhone
   for 7 days at a time (3 devices, 3 apps per device) [S-33]; enough for SPK-6.
5. **Spending, none required.** Options if the owner's phones do not fit or a finer measure is
   wanted:

| Option | Cost | What it buys | Recommendation |
|---|---|---|---|
| None | 0 | The owner's two phones | **Default**, if they fit §1 |
| A second-hand mid-range Android of 90/120 Hz | *(price unverified; to check on a second-hand market)* | The Android slot, if the owner has none | Only if the owner has no Android that fits |
| A second-hand Pixel 6 or later | *(price unverified)* | Power rails: energy in µAh per run instead of whole percentage points [S-12] [S-13] | Only if R-3 lands in the 7–9 % margin and more runs do not settle it |
| Apple Developer Program | $99 a year [S-34] | No 7-day expiry; TestFlight | Not for SPK-6; needed later for the stores (HRD-08) |
| A device cloud: BrowserStack App Live $150 a month (team, yearly) or App Automate from $59 [S-35]; TestMu (formerly LambdaTest) real devices from $39 a month [S-36]; AWS Device Farm $0.17 per device minute, 1,000 minutes free [S-37]; Firebase Test Lab $5 per physical device hour [S-38] | As listed | Many models for a frame-time sweep. Useless for battery and heat (no vendor documents whether its phones are unplugged; BrowserStack says it "manages device battery" [S-39]) and for taps (no thumb) | Not for SPK-6 |

## 11. Sources

Read on 2026-09-29. Some Apple pages render only with JavaScript: their JSON form on the same site
was read instead.

| # | Source |
|---|---|
| S-1 | Apple, *Measuring your app's power use with Power Profiler*: https://developer.apple.com/tutorials/data/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler.json |
| S-2 | Apple (archived), *Energy Efficiency Guide for iOS Apps*, Xcode gauge and Instruments: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MonitorEnergyWithXcode.html and …/MonitorEnergyWithInstruments.html |
| S-3 | Apple, `ProcessInfo.ThermalState` and its `serious` case: https://developer.apple.com/tutorials/data/documentation/foundation/processinfo/thermalstate-swift.enum.json |
| S-4 | Apple Support, battery usage and health: https://support.apple.com/en-us/120745 ; https://support.apple.com/en-us/102432 |
| S-5 | Apple, `UIDevice.batteryLevel`, `isBatteryMonitoringEnabled`, `batteryLevelDidChangeNotification`: https://developer.apple.com/tutorials/data/documentation/uikit/uidevice/batterylevel.json |
| S-6 | Apple, `WKWebView.isInspectable`: https://developer.apple.com/tutorials/data/documentation/webkit/wkwebview/isinspectable.json ; WebKit, *Enabling the inspection of web content in apps*: https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/ ; Capacitor configuration: https://capacitorjs.com/docs/config |
| S-7 | Apple, `CADisableMinimumFrameDurationOnPhone`: https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone.json |
| S-8 | WebKit bug 272165, *120Hz requestAnimationFrame is not supported on iPhone Pros* (a bug tracker, not documentation): https://bugs.webkit.org/show_bug.cgi?id=272165 |
| S-9 | WebKit bug 168837, *Throttle requestAnimationFrame to 30fps in low power mode on iOS* (a bug tracker): https://bugs.webkit.org/show_bug.cgi?id=168837 |
| S-10 | Apple, `ProcessInfo.isLowPowerModeEnabled`: https://developer.apple.com/tutorials/data/documentation/foundation/processinfo/islowpowermodeenabled.json |
| S-11 | Apple, `MXMetricManager` and its payloads: https://developer.apple.com/tutorials/data/documentation/metrickit/mxmetricmanager.json |
| S-12 | Perfetto, battery counters and power rails: https://perfetto.dev/docs/data-sources/battery-counters ; system tracing: https://perfetto.dev/docs/getting-started/system-tracing ; CPU frequency: https://perfetto.dev/docs/data-sources/cpu-freq ; scheduling: https://perfetto.dev/docs/data-sources/cpu-scheduling ; FrameTimeline: https://perfetto.dev/docs/data-sources/frametimeline ; thermal ftrace: https://perfetto.dev/docs/getting-started/periodic-trace-snapshots |
| S-13 | Android Studio Power Profiler: https://developer.android.com/studio/profile/power-profiler |
| S-14 | Android, Battery Historian setup: https://developer.android.com/topic/performance/power/setup-battery-historian |
| S-15 | Android, `dumpsys` (batterystats, gfxinfo): https://developer.android.com/tools/dumpsys |
| S-16 | Android, Doze and standby testing (`dumpsys battery unplug`): https://developer.android.com/training/monitoring-device-state/doze-standby ; https://developer.android.com/topic/performance/power/test-power |
| S-17 | AOSP, multiple refresh rates: https://source.android.com/docs/core/graphics/multiple-refresh-rate ; Android, frame rate: https://developer.android.com/media/optimize/performance/frame-rate |
| S-18 | AOSP, thermal mitigation (status levels): https://source.android.com/docs/core/power/thermal-mitigation ; `PowerManager`: https://developer.android.com/reference/kotlin/android/os/PowerManager ; ADPF thermal: https://developer.android.com/games/optimize/adpf/thermal ; NDK thermal: https://developer.android.com/ndk/reference/group/thermal |
| S-19 | Android, managing WebView: https://developer.android.com/develop/ui/views/layout/webapps/managing-webview |
| S-20 | MDN, `requestAnimationFrame`: https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame |
| S-21 | MDN browser compatibility data: `PerformanceLongAnimationFrameTiming`, `PerformanceLongTaskTiming`, `PerformanceEventTiming`, `PerformancePaintTiming`: https://bcd.developer.mozilla.org/bcd/api/v0/current/api.PerformanceEventTiming.json (and the same path for each) |
| S-22 | MDN, Page Visibility API: https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API |
| S-23 | MDN compatibility data, `Navigator.getBattery`: https://bcd.developer.mozilla.org/bcd/api/v0/current/api.Navigator.getBattery.json |
| S-24 | W3C, Battery Status API: https://www.w3.org/TR/battery-status/ |
| S-25 | MDN, Compute Pressure API: https://developer.mozilla.org/en-US/docs/Web/API/Compute_Pressure_API ; compatibility: https://bcd.developer.mozilla.org/bcd/api/v0/current/api.PressureObserver.json |
| S-26 | WebKit, Timelines tab: https://webkit.org/web-inspector/timelines-tab/ ; *CPU Timeline in Web Inspector*: https://webkit.org/blog/8993/cpu-timeline-in-web-inspector/ |
| S-27 | Chrome, remote debugging of Android devices and WebViews: https://developer.chrome.com/docs/devtools/remote-debugging ; https://developer.chrome.com/docs/devtools/remote-debugging/webviews |
| S-28 | Chrome DevTools, Performance reference and rendering performance: https://developer.chrome.com/docs/devtools/performance/reference ; https://developer.chrome.com/docs/devtools/rendering/performance |
| S-29 | Apple, `NSLocalNetworkUsageDescription` (iOS 14+): https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription.json |
| S-30 | StatCounter, mobile OS market share worldwide, August 2026: https://gs.statcounter.com/os-market-share/mobile/worldwide |
| S-31 | StatCounter, mobile vendor market share worldwide, August 2026: https://gs.statcounter.com/vendor-market-share/mobile/worldwide |
| S-32 | Capacitor, Device plugin (`getBatteryInfo`): https://capacitorjs.com/docs/apis/device |
| S-33 | Apple, comparing memberships: https://developer.apple.com/support/compare-memberships/ |
| S-34 | Apple Developer Program: https://developer.apple.com/programs/ |
| S-35 | BrowserStack pricing: https://www.browserstack.com/pricing?product=app-live ; https://www.browserstack.com/pricing |
| S-36 | TestMu AI (formerly LambdaTest) pricing: https://www.testmuai.com/pricing/ |
| S-37 | AWS Device Farm pricing and FAQ: https://aws.amazon.com/device-farm/pricing/ ; https://aws.amazon.com/device-farm/faqs/ |
| S-38 | Firebase Test Lab, usage and pricing: https://firebase.google.com/docs/test-lab/usage-quotas-pricing |
| S-39 | BrowserStack, App Performance, battery usage on Android: https://www.browserstack.com/docs/app-performance/app-performance-guides/android/battery-usage |
| S-40 | This repository: [ADR-0003](../architecture/ADR-0003-client.md), [ADR-0006 §5](../architecture/ADR-0006-chunked-maps.md), [design/11](../design/11-interface.md), [CLI-03a's brief](../briefs/CLI-03a-render-sandbox.md), [PLAN.md](../../PLAN.md) |

### Marked unverified in this document

That Galaxy A and Redmi are the best-selling mid-range lines; the default of Safari's 60 fps flag in
WKWebView and the effect of `CADisableMinimumFrameDurationOnPhone` on a web view; the granularity of
`UIDevice.batteryLevel`; attaching Instruments to a web view's process; `adb shell dumpsys
thermalservice`; `adb reverse` for the local node; Android's clear-text default; the touch radius per
browser; the API level of `getThermalHeadroom` (30 or 33); that Chrome and the WebView run the same
release; screenshots inside DevTools traces and Android bug reports; second-hand phone prices.
