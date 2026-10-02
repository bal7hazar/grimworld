# The iOS shell (CV-03)

A Capacitor 8 shell that wraps the **production build** of the sandbox in an iOS app (WKWebView),
for SPK-6.1's shell step (`docs/research/SPK-6-protocol.md` §2.2): the owner's iPhone 14 runs the
same page as Safari, with the atlas embedded and Safari's Web Inspector reaching it. It has no
account, no chain and no network (CLI-01, SPK-6.2). **Android is not built** (D-152).

- `capacitor.config.ts`: `appId` is the placeholder `com.example.grimworld`; `webDir` is `dist`;
  no `server.url` (the app loads its bundled build, never a dev server); Web Inspector on
  (`ios.webContentsDebuggingEnabled`, off in any store build, HRD-08); the web view's scroll off.
- `ios/`: the Xcode project `cap add ios` generated, with Swift Package Manager (`CapApp-SPM`).
  It has no icon or splash image: the owner's are added locally (ignored by git), never committed.
- `src/shell/deviceState.ts`: `readDeviceState()` (the thermal state, the battery level and state,
  Low Power Mode, read by the native `DeviceState` plugin; `null` in a browser) and
  `onThermalChange()`. No polling: read at start and stop, and on each change. `readDeviceState()`
  rejects when the native read fails: its caller handles the rejection.
- `src/shell/startLog.ts`: `logShellStart()`, called by `src/main.tsx`, writes the page's
  `[shell] start {"href":…,"state":{…}}` line once at start and `[shell] thermalChange <state>` on
  each change, in the shell only (nothing in a browser).

## Commands

From `client/app/`:

| Command            | What it does                                                                           |
| ------------------ | -------------------------------------------------------------------------------------- |
| `pnpm shell:build` | The production build **with the atlas** (`GRIMWORLD_EMBED_ART=1`), then `cap sync ios` |
| `pnpm shell:sync`  | The production build without the atlas (the sandbox draws shapes), then `cap sync ios` |
| `pnpm shell:open`  | Opens `ios/App/App.xcodeproj` in Xcode                                                 |

The atlas is copied from `tools/art/out/`, or from `GRIMWORLD_ART_OUT` (another checkout's
`tools/art/out/`): `sprites.json` and the pages it names, nothing else. The build refuses
`GRIMWORLD_EMBED_ART` when `CI` is set.

After a sync, `ios/App/App/public/` holds the copied build. It is ignored by git and by the client's
lint; `pnpm exec prettier --check client indexer` lists its files and the copied
`capacitor.config.json` on the Mac, so run that check before a sync or after removing them.

## The simulator (the agent)

Xcode 26.0 or later (checked with Xcode 27.0 and the iOS 26.5 simulator, iPhone 17).

```sh
pnpm shell:sync            # or shell:build, with the atlas
xcodebuild -project ios/App/App.xcodeproj -scheme App -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/grimworld-shell \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot 'iPhone 17'
xcrun simctl install booted /tmp/grimworld-shell/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch --console-pty booted com.example.grimworld \
  -startQuery 'fixture=cave&scale=sharp&panel=1'
```

- `-startQuery` (Debug builds only) gives the sandbox its URL parameters, as `?fixture=…` does in
  Safari (protocol §2.3). Without it the app opens on `capacitor://localhost/`.
- `--console-pty` shows the app's output: the page's console as Capacitor forwards it
  (`⚡️  [log] - [shell] start {…}`, `⚡️  [log] - [shell] thermalChange …`, the sandbox's own lines),
  and the native `[shell] native start inspectable=… scrollEnabled=… state=…` line, which is also
  in the system log (`xcrun simctl spawn booted log show --last 2m --predicate 'process == "App"'`).
- The atlas: after `shell:build` the app serves `dist/art/` at `/art/`, as the dev server does, and
  the sandbox draws the sprites (the debug panel, `panel=1`, says `atlas: loaded`). After
  `shell:sync` it logs `[sandbox] no atlas at /art/: drawing shapes` and draws shapes. No capture
  of a screen with the atlas leaves the Mac (D-73).
- Safari's Web Inspector: Safari, Develop, the simulator, then the app's page.

## The owner's iPhone 14 (the owner, who signs)

Signing and every Apple account action are the owner's; the agent never signs, never logs in.

1. Build the atlas on the Mac (`tools/art`, see `tools/art/README.md`).
2. `pnpm shell:build`, then `pnpm shell:open`.
3. Copy `ios/App/Signing.local.xcconfig.example` to `ios/App/Signing.local.xcconfig` (ignored by
   git) and put your team and a bundle identifier of your own in it. `ios/debug.xcconfig` includes
   it, for the Debug configuration (Xcode's Run).
4. In Xcode, choose the iPhone and Run. On the phone, trust the developer profile (Settings,
   General, VPN & Device Management), then open the app and check the run.

A free Apple account's profile lasts 7 days (protocol §10); the Apple Developer Program is not
needed for SPK-6.

## What never leaves the Mac (D-73)

The atlas, a build that embeds it, and any screenshot or recording of a screen showing the art stay
on the Mac and the owner's phone: never in a commit, a pull request, an issue, a comment or a
report, never shared or distributed. A build without the atlas draws shapes only.
