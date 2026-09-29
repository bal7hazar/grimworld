# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 11:15 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146; #117, amended by #119). Rewritten at
each check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

The track opened today. The mandate and its amendment are on `main`. **CV-01 is merged**
([#121](https://github.com/bal7hazar/grimworld/pull/121)): the Mac launcher `scripts/mac/agent.sh`,
audited by `[GPT-6-Sol]` (PASS at the fourth pass, after three fix loops). Its report and the four
audit passes are archived in `docs/reports/CV-01-*`. Next: ART-02 and CLI-03a, launched with it.

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
| CV-01 | The launcher of the track on the Mac, `scripts/mac/agent.sh` | Opus 5.5 | **Done**: [#121](https://github.com/bal7hazar/grimworld/pull/121), 102 local test cases; [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md): pass 1 FAIL (label not checked; test cleanup on interruption; a race test; `Read(//…)` withdrawn, Claude Code's absolute form), passes 2 and 3 FAIL (the test harness only), pass 4 PASS |
| ART-02 | ART-00's atlas corrected: scale, Python 3.12, the same output on macOS and Linux ([brief](../briefs/ART-02-atlas-scale.md)) | Opus 5.5 | Launched once this brief is on `main` |
| CLI-03a | A rendering sandbox on fixed data ([brief](../briefs/CLI-03a-render-sandbox.md)) | Opus 5.5 | Launched with ART-02 |
| SPK-6a | The protocol of SPK-6 on real phones | Opus 5.5, research | Brief to write; when a slot frees |

CV-01's own agent and its audits were launched by hand by the orchestrator under the launcher's
rules (launchd job, `KeepAlive` false, environment from nothing, `CLAUDE_CONFIG_DIR` checked,
profile plus Mac denies, never `--dangerously-skip-permissions`). Every launch from now on goes
through `scripts/mac/agent.sh`.

### Findings on ART-00's atlas, on this Mac (`python3.12 tools/art/build.py --check`)

The PixiJS check is green (164 frames, 26 animations). The fingerprint of `out/` is `f4c768bf…`
here against `eca5e893…` on the VPS. Visible heights: runt 121–157 px, skirmisher 81–133, slinger
65–83, shaman 151–199, hobgoblin 156–235, vanguard 84–104, warden 79–90, cleric 62–71. ART-02
starts from these.

## Agents on the Mac

Budget: 2 at a time, audits included (D-146).

| Agent | Model (ran) | Since | State |
|---|---|---|---|
| — | | | none running |

## Pull requests

| PR | Content | State |
|---|---|---|
| [#118](https://github.com/bal7hazar/grimworld/pull/118) | This file | Merged |
| [#121](https://github.com/bal7hazar/grimworld/pull/121) | CV-01, the Mac launcher | Merged |
| This one (`cv/cv-02-briefs`) | Briefs of ART-02 and CLI-03a; CV-01's report and audit archived; this file | Merged on green CI |

## Waiting for the owner

| | |
|---|---|
| ART-02's Linux check | The cross-machine fingerprint must be checked on Linux x86_64. Either the owner starts Docker Desktop on the Mac and the orchestrator runs it there, or the project manager has it run on the VPS |
| Sizes on screen | Later, on CLI-03a's sandbox: the sprites' heights (ART-1, provisional by D-146) and the tile size: sight of radius 6 across 375 px gives tiles under 29 px, against I-6's 40 points |

## Asked of the project manager

Nothing open. The two precisions asked on 2026-09-29 (the account check on the Mac, briefs `CV-*`)
are answered by #119.

## Next

1. ART-02 and CLI-03a in parallel with `scripts/mac/agent.sh` (allowlists apart: `tools/art/**`,
   `client/app/src/**`); their audits as slots free; SPK-6a after.
