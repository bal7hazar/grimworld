# D-151: SPK-6 in two steps, the Capacitor shell, the owner's phones and thresholds

| | |
|---|---|
| Raised by | Track CV's orchestrator, SPK-6a ([#138](https://github.com/bal7hazar/grimworld/pull/138), `docs/research/SPK-6-protocol.md`): four escalations and questions for the owner |
| Decided by | The owner, relayed on 2026-09-29, recorded by the `[Opus 5.5]` project manager |

## The escalations

1. **SPK-6 closes in two steps.** **SPK-6.1**, the rendering verdict (battery, heat, frame time,
   accuracy of taps), unblocks CLI-01. **SPK-6.2**, transactions from a burner, follows CLI-01.
2. **The Capacitor shell is a task of track CV (CV-02), before SPK-6.1.** The track's scope takes
   the shell's files: the Capacitor configuration and the iOS and Android projects. CLI-01 then adds
   accounts and the chain to it.
3. **The local node** concerns SPK-6.2 only: an option to listen on the local network lives in
   `scripts/mac/`, not in the shared scripts, and is used on the owner's home network only.
4. **The atlas**: the measured build embeds it, built locally. These builds stay on the owner's
   phones and are never distributed (D-73).

## The owner's answers

| | |
|---|---|
| Phones | An iPhone 14 (60 Hz screen, iOS 26). No Android yet. SPK-6.1 starts on the iPhone. **SPK-6.1 does not close without an Android** at 90 or 120 Hz, the most exposed case; the owner borrows a mid-range one or buys one (about €150 to €250: the owner's decision, pending) |
| Tools | Xcode and adb are installed on the Mac when SPK-6 runs, not before; Xcode first |
| Heat | Android's first throttling level does not fail the line; the moderate level fails it |
| Idle animations | On by default, at 12 frames per second; SPK-6 also measures them off |
| Spending | None so far |
