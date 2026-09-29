# SPK-6a — The protocol of SPK-6 on real phones

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, under [ORCH-client-visual](ORCH-client-visual.md) §5 (D-146).

## Agent
Title: `[Opus 5.5] SPK-6a protocol` · Profile: implement (a document only; the profile is for the
commit and the pull request) · Launched on the owner's Mac with `scripts/mac/agent.sh`

## Goal

After this task, `docs/research/SPK-6-protocol.md` says exactly how SPK-6 will be run on real phones,
so that its result decides ADR-0003 (PixiJS on demand in a web view) without argument: which devices,
which builds, what is measured and how, the thresholds, and how a run is recorded. SPK-6 itself runs
later on CLI-03a's sandbox build; this task writes the protocol, it measures nothing on a phone.

## Context

- [ADR-0003](../architecture/ADR-0003-client.md): the decision it validates, the **power budget
  rules**, and *Validation — spike SPK-6*: the table of measures and proposed pass thresholds (a room of
  15 × 15 with 10 animated actors; battery ≤ 8 % over 30 minutes; no thermal throttling after 30
  minutes; near-zero processor use idle for 5 minutes with idle animations off; 50 burner transactions
  in a row from the shell, no prompt, no fee shown; taps land on the intended tile at the default zoom),
  and the fallback (Godot, then Unity) if they fail.
- [ADR-0006](../architecture/ADR-0006-chunked-maps.md) §5 (*One rule of sight, two screens*): the
  default zoom (the sight hexagon fills the width, 13 tiles across, about 30 points a tile at 390
  points), the closer zoom (9 tiles), taps snapping to the nearest valid tile with the preview shown
  before sending.
- [design/11](../design/11-interface.md): I-1 to I-7 (one thumb, portrait, touch targets of 40 points,
  a still screen between actions), the desktop rules; UI-1.
- [PLAN.md](../../PLAN.md): SPK-6's row (Phase 0), CLI-01 (the Capacitor shell, not started), CLI-03a
  (the sandbox this protocol will measure, running now), R-9.
- The team has no phone lab: the owner's own phones and, if the protocol needs more, what it would
  cost (a device cloud, second-hand devices) — **a spending is the owner's decision**: list options and
  costs, do not assume one.

## Scope

- In: `docs/research/SPK-6-protocol.md`, with:
  1. **Devices**: the minimum set (at least one mid-range Android and one iPhone, ADR-0003), how to
     choose them (the share of players they stand for, their refresh rate: 60, 90, 120 Hz, which matters
     for a frame callback), and what the owner is asked to provide.
  2. **Builds**: what is measured is CLI-03a's sandbox; in which shells (the phone's browser, and the
     Capacitor shell once CLI-01 exists; say what can be measured before CLI-01 and what must wait for
     it); a build switch for the power rules (render on demand vs a forced loop, idle animations on and
     off) so that each rule's effect is measured, not assumed.
  3. **Measures and instruments**, one per row of ADR-0003's table and for frame time on demand: the
     tool on each platform (Xcode Instruments' Energy and Time Profiler, the iOS battery settings and
     `thermalState`, Android's `dumpsys batterystats` and Perfetto, the thermal status API, what a web page
     can read itself: `requestAnimationFrame` counts, `PerformanceObserver`, the Battery Status API where
     it exists), the conditions (screen brightness fixed, radios, charge level at start, room
     temperature, the app in the foreground, the same scripted session), the number of runs, and how the
     variance is reported.
  4. **The session played**: a script a person can follow in 30 minutes (so many moves, attacks, pauses
     with nothing on screen, pinch and pan), so that runs compare.
  5. **Taps**: how "taps land on the intended tile at the default zoom" is measured (a target tile
     shown, N taps by the thumb in portrait, the error rate and the distance from the tile's centre),
     for the default and the closer zoom, with the pass threshold to propose; what the sandbox must log
     for it (CLI-03a's intents already carry the tile: say what else).
  6. **Transactions**: the 50-transaction row needs CLI-01's burner in the shell and a network: say
     which network (a local node reached from the phone, or Sepolia by the orchestrator's session —
     never by an agent) and defer it to after CLI-01 if it must.
  7. **Thresholds**: ADR-0003's proposed ones, each with the reason it is right or a proposed change,
     and what counts as a failure that triggers the fallback.
  8. **Recording a run**: a template (device, OS, build commit, conditions, raw figures, files of the
     instruments kept where), where results live (`docs/research/SPK-6-*.md`, raw traces outside git
     if large), and the rule that **no screenshot or recording showing the art of the pack is committed
     or posted** (D-73): a trace or a figure is fine, a capture of the screen is not.
  9. **What the sandbox still needs** for the protocol (a debug overlay, a build switch, a tap log),
     as a list for the orchestrator to brief.
- Out: running anything on a phone; code; choosing a spending; the Controller and vRNG rows (SPK-9).
- Allowlist: `docs/research/SPK-6-protocol.md`, `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 Every row of ADR-0003's SPK-6 table, plus frame time on demand, has an instrument per
  platform, conditions, a number of runs and a threshold.
- [ ] AC-2 The protocol says what can be run before CLI-01 (in a phone's browser) and what waits for it.
- [ ] AC-3 The owner's part is a short list: devices to provide, any spending as options with costs.
- [ ] AC-4 A run's record template, and the D-73 rule on captures.
- [ ] AC-5 Every claim about a tool or an API is sourced (a link to the vendor's documentation, read
  today) or marked unverified.

## Rules of this run

- You run on the owner's Mac. Web research is allowed (WebSearch, WebFetch). Nothing is installed.
- Pull request: branch `cv/SPK-6a-protocol` (your worktree is on it; this brief is on `main`), title
  `docs(research): SPK-6a, the protocol of SPK-6 on real phones`. Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Report

`REPORT.md`, header `[Opus 5.5] SPK-6a — protocol`: summary; what the owner must provide or decide;
sources; open questions.
