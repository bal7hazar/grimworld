# [Opus 5.5] SPK-6a — protocol

## Summary
`docs/research/SPK-6-protocol.md` now says how SPK-6 is run on real phones so that it decides
ADR-0003. The model of this session is Opus 5.5, the same as the brief names. Pull request:
https://github.com/bal7hazar/grimworld/pull/138.

What it contains:
- **Three stages.**
  - **6-A**, the phone's browser. It runs once CLI-03a and the sandbox needs are merged. Its frame time, steady-animation and tap results are final; battery, heat and idle are provisional.
  - **6-B**, a thin Capacitor shell around the sandbox, with no chain. Battery, heat and idle become final here.
  - **6-C**, 50 burner transactions. They run after CLI-01, and after FND-08 for Sepolia.
- **Devices**: one iPhone and one mid-range Android with a 90 Hz or faster display. The refresh rate is measured, never assumed.
- **Build switches** (`loop`, `idle`, `idlefps`, `res`, `static`, `overlay`), so that each power rule's effect is measured.
- **Instruments** per row and platform: the sandbox's own run log, Event Timing, iOS Power Profiler (iOS 26+), Web Inspector's CPU timeline, `thermalState`, batterystats, Perfetto, the Android thermal status API.
- **Conditions.** Battery runs are unplugged and in aeroplane mode, starting at 80–90 % charge. A run set is 3 product runs, 1 forced-loop run and 1 still baseline, reported as median and range, with more runs when a result lands near a threshold.
- **A 30-minute session script** and a **tap test** (100 fixed targets per zoom, with the fields to log).
- **Transactions**: which network, with the rule that Sepolia is run by the orchestrator only.
- **Thresholds**, each with its reason, and a rule for what triggers the fallback. Only battery, heat, idle and steady animation can trigger it, on the product build in the shell, on the median of the runs, after fixable sandbox defects are ruled out.
- **Run records**: a template, where results live, and the D-73 rule on captures.
- **11 sandbox and shell needs**, and the owner's part.

Nothing was measured on a phone.

## Files changed
- `docs/research/SPK-6-protocol.md`: new, the protocol.
- `REPORT.md`: this file, not committed.

## Commands run
- `git push -u origin HEAD` pushed the new branch `cv/SPK-6a-protocol`.
- `gh pr create …` opened https://github.com/bal7hazar/grimworld/pull/138.
- `gh pr checks 138 --watch --interval 30` printed `no checks reported on the 'cv/SPK-6a-protocol' branch`. No CI ran, probably because the change is docs-only.
- `pnpm exec prettier --check docs/research/SPK-6-protocol.md` warned. CI runs prettier on `client` only, so nothing was changed.
- Web research: StatCounter, Apple, WebKit, Android/AOSP, Perfetto, Chrome, MDN compatibility data, W3C, Capacitor, and the device-cloud pricing pages, all read on 2026-09-29. Two sub-agents read the vendor pages; the URLs are in §11 of the protocol.

## Cost
—

## Acceptance criteria
- **AC-1**: met. §3.2 gives R-1 to R-8 (the six ADR rows, frame time on demand, and the rules' effects), each with an iOS and an Android instrument, conditions, runs and a threshold. The reasons are in §7.1.
- **AC-2**: met. §2.2 has a table of the stages and says what is final in the browser; §6 covers what waits for CLI-01.
- **AC-3**: met. §10 lists the phones, the Mac's tools, iOS 26 and a free Apple account, then the spending options with their costs. None is required, and each has a recommendation.
- **AC-4**: met. §8.3 is the record template; §8.2 is the D-73 rule, including screenshots inside traces and bug reports.
- **AC-5**: met. §11 lists sources S-1 to S-40, and a closing list names every claim marked *(unverified)*.

## Deviations from the brief
- The brief lists "the iOS battery settings". I found no documented per-hour, per-app granularity for them (Apple's pages say 7 or 8 days, not 10). The protocol relies on the level at start and end, plus the Power Profiler.
- Two claims rest on WebKit's bug tracker, not on documentation: 120 Hz animation callbacks on iPhone Pro, and 30 fps in Low Power Mode. They are labelled that way.

## Escalations
1. **PLAN dependency loop.** PLAN has CLI-01 depend on SPK-6, but the transactions row needs CLI-01's burner in the shell. I propose closing SPK-6 in two steps: the rendering verdict after 6-A/6-B, which unblocks CLI-01, and the transactions row after CLI-01. PLAN.md is a shared file, so this is the orchestrator's or the project manager's call.
2. **A thin Capacitor shell for 6-B** (§9 point 9). CLI-03a's brief put Capacitor out of scope. Either CLI-01 builds it, or a task of its own comes before CLI-01 so that the battery and heat verdict does not wait for the chain.
3. **`scripts/with-node.sh` binds `127.0.0.1`.** A phone cannot reach the local node until it has a host option; this belongs to `scripts/`.
4. **iOS local-network prompt.** On iOS 14+, an app that reaches the local network shows a system permission prompt (Apple, `NSLocalNetworkUsageDescription`). So on iOS the local node cannot pass "no prompt", and that row's passing run has to be on Sepolia, run by the orchestrator's session after FND-08.
5. **The measurement build needs the atlas.** CLI-03a serves the atlas from the dev server only, and measuring shapes would understate GPU and texture cost. A local-only build that includes the atlas is needed (§9 point 1, D-73).

## What the owner must provide or decide
- Which iPhone and which Android are available: model, OS, battery health, refresh rate. Also about one day per phone.
- Whether to install Xcode and Android platform tools on the Mac when SPK-6 runs.
- iOS 26 or later on the iPhone, for the Power Profiler.
- Whether `LIGHT` thermal status on Android fails the heat row. The ADR's wording, read strictly, says yes.
- Whether idle animations default to 12 or 15 fps, and whether they are on by default. R-5b and R-3 give the figures.
- Spending: none required. The options are a second-hand mid-range Android (only if none fits), a second-hand Pixel 6+ for power rails (only if the battery result is borderline), the Apple Developer Program at $99/yr (not needed for SPK-6), and device clouds (not useful for battery, heat or taps). Second-hand prices are unverified.

## Sources
§11 of `docs/research/SPK-6-protocol.md` (S-1 to S-40), all read on 2026-09-29.

## Open questions
- Which contract entrypoint do the 50 transactions call? The row tests the account path, not the rules, so any game entrypoint deployed on the node at the time would do (for example ENG-06's instance lifecycle). The orchestrator decides when CLI-01 is briefed.
- One transaction per action, or D-133 batches? The protocol asks for one per action, the strictest case for prompts.
- Are the proposed thresholds acceptable to the owner? They are: `render()` p95 ≤ 8 ms; tap to next paint p95 ≤ 100 ms; idle page CPU ≤ 3 %; tap misses ≤ 2 % at the default zoom with median distance ≤ 0.3 tile; the frame-time ratio ≤ 1.2 between the last and first 5 minutes. They are my proposals, not sourced standards.
- Getting the API level of `getThermalHeadroom` (30 or 33) right matters only if 6-B's shell reads it.

## Resume 1 — aligned on D-151 and D-152

### Summary
`docs/research/SPK-6-protocol.md` is aligned on `docs/decisions/2026-09-29-spk-6-protocol.md`. I merged origin/main into the branch first (a merge, no rebase) and pushed the result to #138 (commit `cd40563`). Changes, and only these:
- **Two steps.**
  - **SPK-6.1**, the rendering verdict (battery, heat, frame time, taps), runs first in Safari, then in the Capacitor shell; it closes in the shell.
  - **SPK-6.2**, transactions from the burner, runs after CLI-01.
  - The old stage labels 6-A, 6-B and 6-C are gone everywhere, including the record template and the file names.
- **D-152 timing.** SPK-6 runs before Phase 6, not before CLI-01, and CLI-01 is built for the browser first.
- **The device is the owner's iPhone 14** (60 Hz, iOS 26, `devicePixelRatio` 3). SPK-6.1 closes on it alone.
- **Android moved to Appendix A, "not run now (D-152)", rather than deleted.** The appendix holds:
  - the Android device slot, the Pixel option and the refresh-rate case;
  - the Android instruments, and the Android instrument for each row;
  - the Android conditions and SPK-6.2 on Android (`adb reverse`, clear-text);
  - the heat threshold the owner decided: `NONE` and `LIGHT` pass, `MODERATE` fails.
- **The Capacitor shell task** of track CV comes before SPK-6.1's shell step, with the iOS project only for now. I used no ID, since CV-02 is already taken.
- **Local node for SPK-6.2**: an option in `scripts/mac/`, used on the owner's home network only. The shared `with-node.sh` is no longer asked for.
- **Atlas**: the measured build embeds it, built locally, and these builds stay on the owner's phones, never distributed (D-73, in §2.1, §8.2 and §9 point 1).
- **The owner's answers**:
  - Xcode first, then adb, installed when SPK-6 runs.
  - Idle animations on by default at 12 fps; the product build now uses `idlefps=12`; R-5b's threshold is 12 per second, and they are still measured off.
  - No spending; the options table is kept for the record, each option with its status.
- **Scale modes** (`?scale=continuous|snap|sharp`, PENDING-cv-integer-scale):
  - a `scale` switch in §2.3, noting that `snap` lifts the 2× cap on the iPhone 14 and that `res` applies only to `continuous` and `sharp`;
  - R-1 measures frame time per mode (3 runs each), and R-8 measures energy per mode;
  - R-3's product runs use the chosen mode, or `continuous` until one is chosen;
  - a mode that fails while another passes counts as a choice for PENDING-cv-integer-scale, not as a reason for the fallback;
  - the tap log and the record template carry the mode.
- **Owner's time**: now about one and a half days on the iPhone in the browser and half a day in the shell (16 switch values).

### Commands run
- `git fetch -q origin && git merge --no-edit origin/main`: the merge succeeded and brought in the decisions file.
- `git push`: `10db7e3..cd40563  cv/SPK-6a-protocol -> cv/SPK-6a-protocol`.
- `git diff --stat origin/main...HEAD`: only `docs/research/SPK-6-protocol.md`.

### Deviations
- None from the decisions. One judgement call: until the owner picks a scale mode, R-3's battery runs use `continuous`, the sandbox's default in `readScaleMode`.

### Open questions
- The owner still has to choose the product's scale mode (PENDING-cv-integer-scale). If it is not chosen when SPK-6.1 runs, the battery runs use `continuous` and the other modes are compared through R-1 and R-8 only.
