# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 11:30 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146; #117, amended by #119 and by #127,
D-149: a budget of 5 on the Mac, tasks lent by the game). Rewritten at each check-in; the project
manager reads it like a track's `STATUS.md`.

## Where we are

The Mac launcher is merged and audited (CV-01, CV-02), and carries the owner's budget of 5 with a
load threshold of 18 (owner, 2026-09-29; D-149). Four agents run: ART-02, CLI-03a, IDX-01a (lent by the
game) and SPK-6a.

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| CV-01 | The Mac launcher, `scripts/mac/agent.sh` | Opus 5.5 | **Done**, [#121](https://github.com/bal7hazar/grimworld/pull/121); [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md) (PASS at the fourth pass, three fix loops) |
| CV-02 | The launcher's budget of 5, load 18, the pinned Node on the agents' `PATH` (owner, 2026-09-29, D-149) | Sonnet 5.5 | **Done**, [#129](https://github.com/bal7hazar/grimworld/pull/129); [report](../reports/CV-02-launcher-budget.md), [audit](../reports/CV-02-audit-gpt-6-sol.md) (PASS) |
| ART-02 | ART-00's atlas corrected: scale, Python 3.12, the same output on macOS and Linux ([brief](../briefs/ART-02-atlas-scale.md)) | Opus 5.5 | **Running** since 11:11 UTC |
| CLI-03a | A rendering sandbox on fixed data ([brief](../briefs/CLI-03a-render-sandbox.md)) | Opus 5.5 | **Running** since 11:11 UTC |
| IDX-01a | The indexer, part 1: following the chain, the nine frozen events in versioned tables, rewind; a test emitter ([brief](../briefs/IDX-01a-indexer-core.md)). IDX-01 is lent by the game (D-149) and split at the brief stage: IDX-01b (queries, subscriptions, the client's freshness rule) follows | Opus 5.5 | **Running** since 11:23 UTC |
| SPK-6a | The protocol of SPK-6 on real phones ([brief](../briefs/SPK-6a-protocol.md)) | Opus 5.5 | **Running** since 11:23 UTC |

## Agents on the Mac

Budget: 5 at a time, audits and lent tasks included; no launch above a 5-minute load of 18 or under
8 GB available (D-149). Load at 11:23 UTC: 2.9.

| Agent | Model (ran) | Since | Launched |
|---|---|---|---|
| ART-02 | Opus 5.5 | 11:11 UTC | `scripts/mac/agent.sh`, slot cv-1 |
| CLI-03a | Opus 5.5 | 11:11 UTC | `scripts/mac/agent.sh`, slot cv-2 |
| IDX-01a | Opus 5.5 | 11:23 UTC | by hand, under the launcher's rules |
| SPK-6a | Opus 5.5 | 11:23 UTC | by hand, under the launcher's rules |

Why by hand: the slots `cv-3`…`cv-5` of CV-02 are created by `slots-init`, which runs only while every
slot is free (so that no held slot is ever replaced), and ART-02 and CLI-03a hold `cv-1` and `cv-2`.
IDX-01a and SPK-6a were launched with the same environment, account check, profile, deny rules and
record format as the launcher (so that it can resume them); `slots-init` runs as soon as both slots
are free, and every later launch goes through the launcher.

## The machine

| Check | Result |
|---|---|
| Account of the agents | `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status`: **claude-b7r@proton.me**, checked before every launch and resume. `~/.claude` (bal7hazar) is the desktop app's: no agent uses it |
| Node, pnpm | nodejs **24.21.0** installed with asdf (2026-09-29, for IDX-01, D-149), pnpm 12.5.1 among its global packages; no asdf plugin added, the owner's global versions untouched. The agents' `PATH` starts with asdf's shims (CV-02): in the repository `node` is 24.21.0 and `pnpm` 12.5.1 |
| Cairo | scarb 2.19.4, snforge 0.61.0, starknet-devnet 0.10.0; `scarb build` of `contracts/` green in 4 s |
| Python | `python3` 3.11; `python3.12` 3.12.0, for the art pipeline |
| codex | 0.156.1; its read-only sandbox works inside a launchd job |
| The session's environment | Holds, by name, the Sepolia account, `ATLANTIC_API_KEY` and the app's credentials; no agent inherits any of it (environment built from nothing, tested with decoys) |

## Pull requests

| PR | Content | State |
|---|---|---|
| [#118](https://github.com/bal7hazar/grimworld/pull/118), [#126](https://github.com/bal7hazar/grimworld/pull/126), [#131](https://github.com/bal7hazar/grimworld/pull/131) | Status, reports, briefs | Merged |
| [#121](https://github.com/bal7hazar/grimworld/pull/121), [#129](https://github.com/bal7hazar/grimworld/pull/129) | CV-01, CV-02 | Merged |

## Waiting for the owner

| | |
|---|---|
| ART-02's Linux check | The cross-machine fingerprint must be checked on Linux x86_64: the owner starts Docker Desktop on the Mac, or the project manager has it run on the VPS |
| Sizes on screen | On CLI-03a's sandbox: the sprites' heights (ART-1, provisional by D-146). The tile size is ADR-0006 §5's (about 30 points at 390, taps snapping to the nearest valid tile) |

## Asked of the project manager

Nothing open. Expected from IDX-01a: a `PENDING-cv-*` request for the CI (the prettier check and the
root `format` script cover `client` only; the `client` job has no starknet-devnet, so the indexer's
local-node scenario runs on the Mac only).

## Next

1. The four reports as they come; reviews; audits (ART-02: Q + `[GPT-6-Sol]`; CLI-03a: D Q +
   `[GPT-6-Sol]`; IDX-01a: S P Q + `[GPT-6-Sol]`; SPK-6a: D); CLI-03a looked at in the browser.
2. `slots-init` when `cv-1` and `cv-2` are free.
3. IDX-01b's brief after IDX-01a's report.
