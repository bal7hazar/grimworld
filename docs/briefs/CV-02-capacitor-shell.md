# CV-02 — The Capacitor shell for SPK-6.1 (iOS only, no chain)

Written by a thread of track CV's orchestrator (herdr project `grimworld-cv`) on 2026-10-02, from PLAN's
row CV-02, **D-151** and **D-152** (`docs/decisions/2026-09-29-spk-6-protocol.md`) and SPK-6's protocol
§2.2 and §9 point 9 (`docs/research/SPK-6-protocol.md`). PLAN calls this task CV-02; that ID is already
the merged launcher-budget lot (#129, `docs/briefs/CV-02-launcher-budget.md`), and the track's status
asks the project manager for **CV-03** instead. This file keeps the name it was ordered under until the
project manager answers (open question 1).

## Thread
Profile: `impl-opus` (PLAN names Opus 5.5; a native Swift plugin and a first Xcode project in the
repository) · Machine: `--machine mac` (Xcode, the iOS simulator, the atlas built from the `assets`
submodule) · From `origin/main`, one branch, one pull request

## Goal

After this task, `client/app` has a **Capacitor shell for iOS** that wraps the production build of the
sandbox, so that SPK-6.1's shell step (protocol §2.2) can run on the owner's iPhone 14. It gives SPK-6.1
exactly what the protocol asks of it, and nothing else:

1. The **production build** (`pnpm --filter @grimworld/app build`, never the dev server) bundled into an
   iOS app (WKWebView), opening on the sandbox exactly as in Safari, URL parameters included.
2. The **atlas embedded in a local build only** (D-151, D-73): built from `tools/art/out/` on the Mac,
   copied into the app's web assets at build time, never committed, never in CI's `dist/`, never
   distributed.
3. **Web inspection enabled** in these builds (Capacitor `ios.webContentsDebuggingEnabled`, which sets
   WKWebView's `isInspectable`; protocol [S-6]), so that Safari's Web Inspector reaches the page.
4. A **native read of the device state** the protocol's run log needs (§9 point 9, R-3, R-4, §1.2): the
   thermal state (`ProcessInfo.thermalState`), the battery level and state (`UIDevice`), and Low Power
   Mode (`ProcessInfo.isLowPowerModeEnabled`), exposed to the page through one typed function that
   returns `null` in a browser.
5. Build and run commands for the **simulator** (the agent) and for the **owner's iPhone** (the owner,
   who signs).

**Android is not built** (D-152, below). Accounts and the chain are CLI-01's (D-151).

## Context

- **D-151** (escalation 2): the shell is track CV's, before SPK-6.1; the track's scope takes "the
  Capacitor configuration and the iOS and Android projects"; CLI-01 then adds accounts and the chain.
  Escalation 4: the measured build embeds the atlas, built locally; these builds stay on the owner's
  phones and are never distributed (D-73). The owner's answers: an iPhone 14 (60 Hz, iOS 26); **Xcode is
  installed on the Mac when SPK-6 runs, not before**; spending: none.
- **D-152** (revised by the owner the same day): **Android is dropped for now**; SPK-6.1, SPK-6.2 and the
  shell run before Phase 6; CLI-01 builds for the browser first and Capacitor wraps it later; the
  Android at 90 or 120 Hz is no longer asked. **For the shell this means**: no `android/` project, no
  `@capacitor/android` dependency, no Android section in the configuration; the protocol's Appendix A
  (Android) adds them in a later task if the owner brings Android back. PLAN's row still says "iOS and
  Android projects": the row predates D-152, and its text is the project manager's (open question 2).
- **SPK-6's protocol** (`docs/research/SPK-6-protocol.md`, merged by SPK-6a, #138):
  - §2.1: the measured build is the production build with the atlas; the ten-actor fixture.
  - §2.2: the shell step repeats the browser step's rows once and gives the final battery, heat and
    idle figures; it **closes SPK-6.1**.
  - §2.3: the switches are URL parameters of the sandbox (`loop`, `idle`, `idlefps`, `res`, `static`,
    `overlay`, `scale`). The shell must let them through.
  - §3.1: the instruments; `ProcessInfo.thermalState` [S-3] and `UIDevice.batteryLevel` [S-5] in the
    shell; Low Power Mode off and recorded (§1.2).
  - §8.2: no capture of the screen showing the art; no build shared.
  - §9: points 1–8 are client work on the sandbox (the measurement build, the switches, **the run
    log**, the refresh-rate probe, the tap test, …); **point 9 is this task**; points 10–11 are CLI-01's
    and `scripts/mac/`'s.
  - §10: the owner's part. A free Apple account installs the owner's own builds on the owner's own
    iPhone for 7 days at a time [S-33]; the Apple Developer Program ($99 a year) is not for SPK-6.
- **The mandate** ([ORCH-client-visual](ORCH-client-visual.md)): §1 *Writes* includes "the Capacitor
  shell: its configuration and the iOS and Android projects of `client/app`"; `client/app/src/account/**`
  and `chain.ts` stay the game's; `.github/`, `scripts/` outside `scripts/mac/`, the `assets` pointer
  are never the track's. §4: nothing of the pack, nor a screenshot showing it, leaves the Mac. §6: no
  rule in `client/app`, rendered on demand.
- **The client as merged**:
  - `client/app` is Vite 8 + React 19 + PixiJS 8; `build` is `tsc --noEmit && vite build` into
    `client/app/dist/` (ignored by the root `.gitignore`, `client/*/dist/`).
  - **The atlas is served only by the development server**: `vite.config.ts`'s `devArt()` plugin
    (`apply: "serve"`) serves `GRIMWORLD_ART_OUT` or `tools/art/out/` at `/art/`; `render/atlas.ts`
    fetches `/art/sprites.json` (`ART_BASE`) and draws shapes when it is absent. **A production build
    today contains no atlas**: this task adds an opt-in copy at build time (scope 3).
  - `index.html` already has `viewport-fit=cover`.
  - `client/app/tsconfig.json` includes `src` and `*.config.ts`, so `capacitor.config.ts` is type-checked
    and linted.
  - `client/eslint.config.js` ignores `**/dist/` and `**/node_modules/` only. After `cap sync`, the
    copied bundle under `ios/App/App/public/` would be linted on the Mac (scope 7).
- **The toolchain**: Node 24.21.0 and pnpm 12.5.1 (`.tool-versions`). OPERATIONS §3: toolchains are the
  agents' to install, user-local; **Xcode is not a toolchain the agent installs**: it comes from the
  App Store or Apple's developer site, behind an Apple account, which is the owner's (D-151: installed
  when SPK-6 runs). The simulator runtime, once Xcode is there, is the agent's
  (`xcodebuild -downloadPlatform iOS`).
- **Capacitor, read on 2026-10-02** (npm registry dist-tags; the GitHub releases page; the support
  policy):
  - `latest` is **8.5.2** for `@capacitor/core`, `@capacitor/cli` and `@capacitor/ios` (released
    2026-09-11); `next` is 9.0.0-alpha.7, not used.
  - Capacitor 8 is the active line; it needs Node 22 or later (`@capacitor/cli` 8 `engines`) and
    **Xcode 26.0** or later.
  - Sources: https://www.npmjs.com/package/@capacitor/core ,
    https://github.com/ionic-team/capacitor/releases ,
    https://capacitorjs.com/docs/main/reference/support-policy .

## Scope

- **In**:
  1. **Dependencies, pinned exactly** (the repository's habit: no range): `@capacitor/core` 8.5.2 and
     `@capacitor/ios` 8.5.2 in `dependencies`; `@capacitor/cli` 8.5.2 in `devDependencies`. If a newer
     8.x patch is `latest` when the task runs, take it, and write the version and the date read in the
     pull request. No other Capacitor plugin; the device state comes from scope 5.
  2. **`client/app/capacitor.config.ts`**:
     - `appId`: the placeholder **`com.example.grimworld`**. The owner's real identifier is set in a
       local, ignored file (scope 4), never committed.
     - `appName`: `Grim World`; `webDir`: `dist`.
     - **No `server.url`**: the app loads its bundled assets, never the Mac's dev server (the protocol
       measures the production build). Capacitor's live reload may be used by hand to iterate; it is
       never committed in the configuration and never measured.
     - `ios.webContentsDebuggingEnabled: true`, with a comment: on for the measurement builds (protocol
       §9 point 9); a build for any store turns it off (HRD-08, later).
     - `ios.scrollEnabled: false`, so that the web view's rubber-band scroll does not fight the sandbox's
       pan and pinch; the agent checks that pinch and pan still work.
     - No `android` section (D-152).
  3. **The atlas in a local build only** (D-73), in `vite.config.ts`:
     - A build-only plugin (`apply: "build"`) that copies the atlas into `dist/art/`.
     - It runs **only when `GRIMWORLD_EMBED_ART=1`** is set.
     - It refuses (fails the build with a message) when `CI` is set.
     - It reads from the same `ART_OUT` as `devArt()` and copies only `sprites.json` and the `.png`
       pages it names, with the real-path checks of `serveArt.ts`.
     - Without the variable, `dist/` is what it is today.
     - Its pure part is unit-tested as `serveArt.ts` is, on synthetic files.
     - `ART_BASE` stays `/art/`: the shell serves `dist/` at its root, so the same URL works in the browser
       and the shell. The agent checks it.
  4. **The iOS project**, generated by `pnpm exec cap add ios` at `client/app/ios/`:
     - Committed as generated, with Capacitor 8's default dependency manager for a new project. The
       agent records whether that is Swift Package Manager or CocoaPods. If CocoaPods, it installs it
       user-locally and says so.
     - The deployment target as Capacitor 8 generates it, recorded.
     - **Portrait only** (design/11: portrait, one thumb): `UISupportedInterfaceOrientations` for the
       iPhone lists portrait only.
     - **Signing is the owner's**:
       - The committed project has no development team.
       - An optional `#include? "Signing.local.xcconfig"` in the app's configuration lets the owner set
         `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` locally.
       - `Signing.local.xcconfig` is listed in `client/app/ios/.gitignore`, and a committed
         `Signing.local.xcconfig.example` shows the two keys with placeholder values.
       - If Xcode does not honour `#include?` here, the agent says so and proposes another local
         override; it does not commit a team.
     - The generated `ios/.gitignore` must ignore `App/App/public/` (the copied web assets, with the
       atlas when embedded) and the copied `capacitor.config.json`. The agent checks both with
       `git check-ignore`, and adds the line if the template lacks it.
     - No `CADisableMinimumFrameDurationOnPhone`: the iPhone 14 is 60 Hz (protocol §1.2).
     - No `NSLocalNetworkUsageDescription`: no network in SPK-6.1. It is SPK-6.2's, with CLI-01.
  5. **The device state, natively** (protocol §9 point 9):
     - **A local Capacitor plugin in the iOS project** (Swift, in the app target, registered on the
       bridge as Capacitor 8 documents for app-local plugins), named `DeviceState`. It has one method,
       `read()`, returning:
       - `thermal`: `"nominal" | "fair" | "serious" | "critical"`;
       - `battery`: 0–1, or `null` when unknown; battery monitoring is enabled for the read;
       - `charging`: `"unplugged" | "charging" | "full" | "unknown"`;
       - `lowPower`: a boolean.
     - It also emits a `thermalChange` event on `ProcessInfo.thermalStateDidChangeNotification`.
     - Decision of this brief: one local plugin rather than the protocol's suggestion of Capacitor's
       Device plugin for the battery [S-32]. It reads the same `UIDevice` values, adds the thermal state
       and Low Power Mode the Device plugin does not give, and adds no dependency. Reversed if the
       orchestrator prefers `@capacitor/device` for the battery.
     - **A typed TypeScript side** in `client/app/src/shell/`:
       - `readDeviceState(): Promise<DeviceState | null>` (`null` when `Capacitor.isNativePlatform()` is
         false);
       - `onThermalChange(handler)`, returning an unsubscribe;
       - unit tests with the plugin mocked.
       - No rule, no clock, no randomness; the imports test (`sandbox/imports.test.ts`) extended so that
         `src/shell/` imports neither `client/sim` nor `src/account/` nor `src/chain.ts`.
     - **Wiring into the run log**:
       - If the run log of protocol §9 point 3 is merged at your base, add the device state to it: once
         at start and at stop, and each `thermalChange`, with its time in the log's clock.
       - If it is not merged, do not build a run log. Leave the functions exported and tested, and say
         in the report that the run-log task wires them.
       - Either way, **no polling loop**: a timer that wakes the page would distort the idle row (R-5).
  6. **Package scripts** in `client/app/package.json`, development only:
     - `shell:build` (`GRIMWORLD_EMBED_ART=1 pnpm build && cap sync ios`);
     - `shell:sync` (`pnpm build && cap sync ios`, without the atlas);
     - `shell:open` (`cap open ios`).
     - Name them as you see fit, one line each in the pull request.
  7. **Lint on the Mac after a sync**: one entry, `"**/ios/App/App/public/"`, added to the `ignores` of
     `client/eslint.config.js`. That file is shared with `client/sim`, so this is an escalation: it is
     listed in the allowlist below for this one line only, pending open question 4. If the orchestrator
     refuses it, leave the file alone and state in the report that `pnpm lint` on the Mac must run before
     a sync or after removing `public/`.
  8. **A short `client/app/SHELL.md`**:
     - what the shell is for (SPK-6.1);
     - the commands of scope 6;
     - the simulator steps, and the owner's device steps (§ *Verification*);
     - what never leaves the Mac (D-73);
     - signing and any Apple account action are the owner's;
     - Android not built (D-152).
- **Out**:
  - Accounts, the burner, starknet.js in the shell, a network or a local node: **CLI-01** and SPK-6.2
    (D-151).
  - The sandbox's instrumentation of protocol §9 points 1–8 (the measurement switches, the run log, the
    refresh-rate probe, the tap test, the overlay): another task. Only the wiring of scope 5 if the run
    log exists.
  - Android, `adb`, the protocol's Appendix A (D-152).
  - Signing with a team, provisioning, TestFlight, the App Store, the Apple Developer Program, any
    Apple account action: **the owner's** (acts reserved for the owner: accounts, store submissions,
    money).
  - App icons and a splash of the game's own (Capacitor's template ones stay). No art of the pack in
    the iOS project, ever.
  - A CI job for the shell: `.github/` is not the track's (scope of CI below; open question 3).
  - `client/sim`, `contracts/`, `scripts/` outside `scripts/mac/`, the `assets` pointer.
- **Allowlist**:
  - `client/app/capacitor.config.ts`, `client/app/ios/**` (generated project, the plugin, `.gitignore`,
    the example signing file), `client/app/SHELL.md`.
  - `client/app/src/shell/**` and its tests; `client/app/src/sandbox/imports.test.ts` (the shell's
    rule); the run log's module only for the wiring of scope 5, if it exists.
  - `client/app/vite.config.ts` and a pure helper beside `src/dev/serveArt.ts` with its test (scope 3).
  - `client/app/package.json` (scope 1's three packages, scope 6's scripts) and `pnpm-lock.yaml`.
  - `client/eslint.config.js`, the one `ignores` entry of scope 7, pending the orchestrator's answer.
  - Anything else is an escalation.

## What CI can check, and what only the Mac can

| Check | Where | How |
|---|---|---|
| The configuration: `appId` the placeholder, `webDir: "dist"`, no `server.url`, no `android`, inspection on, scroll off | CI (Linux), `pnpm test` | A unit test importing `capacitor.config.ts` |
| The device-state bridge: `null` in a browser, the mapping of the plugin's answer, the unsubscribe | CI, `pnpm test` | Unit tests, plugin mocked |
| The art copy: off without `GRIMWORLD_EMBED_ART`, refused with `CI`, only `sprites.json` and its pages, no path outside the root | CI, `pnpm test` | Unit tests on synthetic files |
| `src/shell/` imports no rule, no account, no chain | CI, `pnpm test` | The imports test |
| Lint, types, the web build, prettier | CI, as today | The `client` job, unchanged |
| `dist/` of CI has no `art/` | CI | The build runs without the variable; a test of the plugin's default |
| `cap sync ios` | The Mac; **on Linux: unknown** | The agent runs `pnpm exec cap sync ios` once on Linux (the VPS, or a Linux container if the thread has none) only if cheap, and reports the real output; it adds nothing to CI |
| `xcodebuild`, the simulator, the native plugin | **The Mac only** | Xcode |
| The device: signing, install, the 7-day profile, real thermal and battery figures | **The owner, on the iPhone 14** | Xcode with the owner's Apple account |

A CI step that runs `cap sync` or `xcodebuild` (a macOS runner) needs `.github/`, which is the project
manager's: if the agent thinks one is worth it, it writes `docs/decisions/PENDING-cv-shell-ci.md` with the
measured `cap sync` result. That file is the only exception to the allowlist.

## Interfaces

```ts
// client/app/src/shell/deviceState.ts
export type ThermalState = "nominal" | "fair" | "serious" | "critical";
export interface DeviceState {
  readonly thermal: ThermalState;
  readonly battery: number | null; // 0–1
  readonly charging: "unplugged" | "charging" | "full" | "unknown";
  readonly lowPower: boolean;
}
export function readDeviceState(): Promise<DeviceState | null>; // null outside the native shell
export function onThermalChange(handler: (thermal: ThermalState) => void): () => void;
```

The native side's method and event names match these. CLI-01 adds its own modules to the shell; it does
not need to change these.

## Acceptance criteria

- [ ] AC-1 `@capacitor/core`, `@capacitor/ios` and `@capacitor/cli` pinned exactly at the current 8.x
      `latest` (8.5.2 on 2026-10-02), named in the pull request with the date read; no
      `@capacitor/android`, no `android/`.
- [ ] AC-2 `capacitor.config.ts` as scope 2, pinned by a unit test that CI runs.
- [ ] AC-3 `pnpm --filter @grimworld/app build` without `GRIMWORLD_EMBED_ART` produces no `dist/art/`;
      with it on the Mac, `dist/art/sprites.json` and its pages; with `CI=1` and the variable, the build
      fails with the message. Unit tests for the copy, real output of the three builds in the report.
- [ ] AC-4 `client/app/ios/` is committed as generated, portrait only, no development team, the optional
      local signing include and its example.
      - `git check-ignore client/app/ios/App/App/public/art/sprites.json` and
        `git check-ignore client/app/ios/App/App/Signing.local.xcconfig` (or wherever the include
        points) both succeed.
      - `git ls-files client/app/ios` lists no file of the pack and nothing under `public/`. Real output in
        the report.
- [ ] AC-5 On the Mac, the app builds for the simulator without signing:
      ```
      xcodebuild -project client/app/ios/App/App.xcodeproj -scheme App -sdk iphonesimulator \
        -destination 'platform=iOS Simulator,name=<an iPhone>' CODE_SIGNING_ALLOWED=NO build
      ```
      or the workspace if CocoaPods. It installs and launches with `xcrun simctl`, and opens on the
      sandbox. Shown by a console line the app logs at start (forwarded by Capacitor to the system log
      and read with `xcrun simctl spawn booted log show`), real output in the report.
- [ ] AC-6 In the simulator, `readDeviceState()` returns a well-formed state, written to that log line;
      a `thermalChange` is observed if the simulator can trigger one, or reported as not triggerable.
      In a browser (`pnpm dev`) it returns `null`.
- [ ] AC-7 With `shell:build` (atlas embedded), the simulator's app loads the atlas: the sandbox's own
      log shows `sprites.json` read, not "drawing shapes". **No capture of that screen leaves the Mac**
      (D-73). Without the atlas, the sandbox draws shapes; a capture of shapes only may be described,
      not uploaded.
- [ ] AC-8 URL parameters reach the sandbox in the shell (for example `?fixture=` and `?scale=`): how is
      the agent's choice (a launch argument, a start page, Safari's Web Inspector), shown in the report.
      If the shell cannot take parameters without a code change outside the allowlist, it is an
      escalation.
- [ ] AC-9 Web Inspector: Safari on the Mac lists the simulator's app under Develop (inspection on).
- [ ] AC-10 Pinch and pan of the sandbox work in the simulator with `scrollEnabled: false`.
- [ ] AC-11 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`; `pnpm exec prettier --check
      client indexer`: pass, on the Mac and in CI. CI green.
- [ ] AC-12 `client/app/SHELL.md` holds the commands, the owner's device steps, and the D-73 and signing
      rules.

## Verification

- **The agent, on the Mac**: AC-3 to AC-10 with real output. Before starting, `xcodebuild -version` must
  show Xcode 26.0 or later. **If Xcode is absent**, the agent does everything that does not need it
  (scopes 1–3, 5's TypeScript side, 6–8, `cap add ios`, `cap sync ios`), commits and pushes it, and
  reports the Xcode-dependent criteria (AC-5, AC-6's native half, AC-7, AC-9, AC-10) as **blocked on
  Xcode, the owner's install**. It never installs Xcode or signs into an Apple account. The simulator
  runtime is the agent's to download.
- **The owner, on the iPhone 14**, when SPK-6.1's shell step comes (the steps SHELL.md gives):
  1. Build the atlas on the Mac.
  2. Run `shell:build`, then open Xcode.
  3. Put the team and an identifier in `Signing.local.xcconfig`.
  4. Run on the phone, trust the developer profile, and check the run on the phone.
  - A free account's profile lasts 7 days (protocol §10). This is not an acceptance criterion of the
    task: the agent has no phone.
- **The reviewer**: the allowlist (`gh pr view <n> --json files`), no art and no team id in the diff,
  the ignores of AC-4, the configuration test, and the native plugin's mapping of the four thermal states.

## Review and audit (D-177)

- **Review**: yes, as every pull request. Use the `review` profile (Sonnet), since the code is written by
  Opus.
- **Audit**: none. The lot is none of OPERATIONS §6's kinds: no value, access control, randomness,
  published interface, or cost or determinism that only a measurement proves, and not a large
  refactoring. Its measurement is SPK-6.1's, which is a separate step. The pull request says
  "Audit: none (D-177)".

## Rules of this run

- **D-73**:
  - No image, atlas or screenshot showing the pack in a commit, the pull request, an issue, a comment or
    the report.
  - Builds with the atlas stay on the Mac and the owner's phone.
  - Your worktree has no `assets` submodule: use the Mac checkout's `tools/art/out/` through
    `GRIMWORLD_ART_OUT`. Never touch the `assets` pointer.
- **Signing, Apple accounts, Xcode's installation, the App Store, TestFlight, the Developer Program**:
  the owner's. Never logged in, never paid, never submitted.
- Pins: the class-hash rule of OPERATIONS §3 does not concern this task; `pnpm-lock.yaml` changes only
  for scope 1's packages.
- Foreground only. Delete and stop only what you created, by exact path and process id (simulator
  devices you created included).
- Pull request: title `[Opus 5.5] CV-02 the Capacitor shell (iOS, for SPK-6.1)`. The body names every
  dependency added with its version, says "Audit: none (D-177)", and lists what the owner must do on
  the phone. Never merge.

## Report

The report of the thread, in the project's form (`PR:`, `## Report`, `## Next`):
- the summary and the pull request;
- the files changed;
- Capacitor's version and dependency manager, the deployment target, the Xcode and simulator used;
- the real output of AC-3 to AC-10;
- what `cap sync ios` does on Linux, if measured;
- what is blocked on Xcode, if anything;
- **the owner's steps for the iPhone**;
- deviations, escalations, open questions.

## Open questions (for the orchestrator and the project manager)

1. **The task's ID**: PLAN's CV-02 collides with the merged launcher lot (#129); the track asked for
   CV-03. If the project manager confirms CV-03, this file is renamed `CV-03-capacitor-shell.md` before
   the launch, and PLAN's row follows. That is the project manager's.
2. **PLAN's row text** still says "iOS and Android projects" (pre-D-152). This brief builds iOS only. The
   project manager may want the row to say "iOS (Android dropped, D-152)".
3. **A CI check of the shell**: today CI checks only the web side. `cap sync ios` on Linux, or
   `xcodebuild` on a macOS runner, would need `.github/` (the project manager's) and, for macOS runners,
   is free for a public repository but slow. Decided by the project manager on the agent's
   `PENDING-cv-shell-ci.md`, if one is written.
4. **`client/eslint.config.js`**: one `ignores` line for `ios/App/App/public/`, in a file shared with
   `client/sim`. Does the orchestrator grant it (scope 7)?
5. **Xcode on the Mac**: D-151 installs it when SPK-6 runs. This task needs it for AC-5 to AC-10. Does the
   owner install Xcode 26 before CV-02 launches, or does CV-02 run its Linux-able part first and the
   rest after the install?
6. **Order with the sandbox's instrumentation** (protocol §9 points 1–8, not yet briefed): if the run log
   lands first, CV-02 wires the device state into it; otherwise the run-log task does. The orchestrator
   chooses the order.
7. **The real bundle identifier** (for example under a domain of the owner's) is the owner's. It is not
   needed for SPK-6, which uses the placeholder overridden locally, but it is needed before any store
   (HRD-08).
