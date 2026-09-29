# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 11:05 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146; #117, amended by #119). Rewritten at
each check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

The track opened today. The mandate and its amendment are on `main`. The Mac launcher (CV-01) is
written and in its third audit pass by `[GPT-6-Sol]`; nothing else launches before a clean verdict
(mandate §3). ART-02 and CLI-03a are briefed and ready.

## Checks of the machine (2026-09-29, 10:10 UTC)

| Check | Result |
|---|---|
| Account of the agents | `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status`: logged in, **claude-b7r@proton.me**, checked before every launch and resume. The Mac's default `claude` configuration (`~/.claude`) is the desktop app's, on bal7hazar: no agent uses it |
| `claude` CLI | 2.1.281 |
| `codex` | 0.156.1; its read-only sandbox (Seatbelt) works inside a launchd job (the audits of CV-01 ran so) |
| `gh` | logged in as bal7hazar |
| Python | `python3` 3.11; `python3.12` 3.12.0 (`/opt/homebrew/bin`), the one the art pipeline needs |
| Node | 22.22.2 on the agents' `PATH` (it holds the `claude` CLI); `.tool-versions` pins 24.21.0, not installed on the Mac; the CI runs 24 |
| Machine | macOS 26.6 arm64, 12 cores, 64 GB; load about 2 |
| The calling session's environment | Holds, by name, the Sepolia account (`STARKNET_*`), `ATLANTIC_API_KEY` and the app's own credentials (`ANTHROPIC_BASE_URL`, `CLAUDE_CODE_*`). An agent's environment is built from nothing (CV-01, requirement 3), tested with decoys |

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| CV-01 | The launcher of the track on the Mac, `scripts/mac/agent.sh` ([#121](https://github.com/bal7hazar/grimworld/pull/121)) | Opus 5.5 | Written (launchd jobs, environment from nothing, account check, profiles plus Mac denies, budget of 2 by kernel locks); 90 local test cases pass, run by the orchestrator too. Audit `[GPT-6-Sol]`: pass 1 FAIL (label not checked; test cleanup on interruption; a race test; one finding withdrawn: `Read(//…)` is Claude Code's absolute form), pass 2 FAIL (three findings in the test harness only), **pass 3 running**. Two fix loops so far |
| ART-02 | ART-00's atlas corrected: scale, Python 3.12, the same output on macOS and Linux | Opus 5.5 | Briefed; launched with the Mac launcher after CV-01's audit |
| CLI-03a | A rendering sandbox on fixed data | Opus 5.5 | Briefed; launched with ART-02 |
| SPK-6a | The protocol of SPK-6 on real phones | Opus 5.5, research | Brief to write; when a slot frees |

Until CV-01 is merged, its agent and its audits are launched by hand by the orchestrator under the
launcher's own rules (launchd job, `KeepAlive` false, environment from nothing, `CLAUDE_CONFIG_DIR`
checked, profile plus Mac denies, never `--dangerously-skip-permissions`).

### Findings on ART-00's atlas, on this Mac (`python3.12 tools/art/build.py --check`)

The PixiJS check is green (164 frames, 26 animations). The fingerprint of `out/` is `f4c768bf…`
here against `eca5e893…` on the VPS. Visible heights: runt 121–157 px, skirmisher 81–133, slinger
65–83, shaman 151–199, hobgoblin 156–235, vanguard 84–104, warden 79–90, cleric 62–71. ART-02
starts from these.

## Agents on the Mac

Budget: 2 at a time, audits included (D-146).

| Agent | Model (ran) | Since | State |
|---|---|---|---|
| CV-01 audit, pass 3 (launchd `grimworld.cv.CV-01-audit-sol.105937`) | GPT-6-Sol | 10:59 UTC | running |

## Pull requests

| PR | Content | State |
|---|---|---|
| [#118](https://github.com/bal7hazar/grimworld/pull/118) | This file | Merged by the orchestrator once its CI is green |
| [#121](https://github.com/bal7hazar/grimworld/pull/121) | CV-01, the Mac launcher | In audit |

## Waiting for the owner

| | |
|---|---|
| ART-02's Linux check | The cross-machine fingerprint must be checked on Linux x86_64. Either the owner starts Docker Desktop on the Mac and the orchestrator runs it there, or the project manager has it run on the VPS |
| Sizes on screen | Later, on CLI-03a's sandbox: the sprites' heights (ART-1, provisional by D-146) and the tile size: sight of radius 6 across 375 px gives tiles under 29 px, against I-6's 40 points |

## Asked of the project manager

Nothing open. The two precisions asked on 2026-09-29 (the account check on the Mac, briefs `CV-*`)
are answered by #119.

## Next

1. CV-01: the third audit's verdict; merge; the audit report archived in `docs/reports/`.
2. ART-02 and CLI-03a in parallel with `scripts/mac/agent.sh` (allowlists apart: `tools/art/**`,
   `client/app/src/**`); their audits as slots free; SPK-6a after.
