# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 10:20 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146; on the branch `pm/client-visual-track`,
PR [#117](https://github.com/bal7hazar/grimworld/pull/117), until it is merged). Rewritten at each
check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

The track opened today. The owner lifted the wait for #117's merge (relayed by the owner's
architecture session on the Mac): the orchestrator writes briefs and launches, but **merges nothing
until #117 is on `main`**, since the scope check at a merge is the mandate's as merged.

## Checks of the machine (2026-09-29, 10:10 UTC)

| Check | Result |
|---|---|
| Account of the agents | `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status`: logged in, **claude-b7r@proton.me**. The Mac's default `claude` configuration (`~/.claude`) is on bal7hazar: it is the desktop app's, and no agent uses it (see *Asked of the project manager*) |
| `claude` CLI | 2.1.281 |
| `codex` | 0.156.1 (`gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`) |
| `gh` | logged in as bal7hazar (repo, workflow) |
| Python | `python3` 3.11; `python3.12` 3.12.0 (`/opt/homebrew/bin`), the one the art pipeline needs |
| Machine | macOS 26.6 arm64, 12 cores, 64 GB; load about 2 |
| The calling session's environment | Holds, by name, the Sepolia account (`STARKNET_*`), `ATLANTIC_API_KEY` and the app's own credentials (`ANTHROPIC_BASE_URL`, `CLAUDE_CODE_*`). An agent's environment is built from nothing (CV-01, requirement 3); the hand launch of CV-01 already did so |

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| CV-01 | The launcher of the track on the Mac, `scripts/mac/agent.sh` ([brief](https://github.com/bal7hazar/grimworld/blob/cv/CV-01-mac-launcher/docs/briefs/CV-01-mac-launcher.md), on its task branch) | Opus 5.5 | **Running** since 10:13 UTC. Launched by hand under the launcher's own rules: launchd job of the GUI domain (`KeepAlive` false), environment built from nothing, `CLAUDE_CONFIG_DIR=~/.claude-b7r` checked, profile `implement` plus Mac deny rules, no `--dangerously-skip-permissions`. Then its audit by `[GPT-6-Sol]` (security), before any other launch |
| ART-02 | ART-00's atlas corrected: scale, Python 3.12, the same output on macOS and Linux | Opus 5.5 | Brief to write; after CV-01's audit |
| CLI-03a | A rendering sandbox on fixed data | Opus 5.5 | Brief to write; after CV-01's audit |
| SPK-6a | The protocol of SPK-6 on real phones | Opus 5.5, research | Brief to write; when a slot frees |

### Findings on ART-00's atlas, on this Mac (`python3.12 tools/art/build.py --check`)

The PixiJS check is green (164 frames, 26 animations). The fingerprint of `out/` is `f4c768bf…`
here against `eca5e893…` on the VPS. Visible heights: runt 121–157 px, skirmisher 81–133, slinger
65–83, shaman 151–199, hobgoblin 156–235, vanguard 84–104, warden 79–90, cleric 62–71. ART-02
starts from these.

## Agents on the Mac

Budget: 2 at a time, audits included (D-146).

| Agent | Model (ran) | Since | State |
|---|---|---|---|
| CV-01 (launchd `grimworld.cv.CV-01.101314`, pid 7627) | Opus 5.5 | 10:13 UTC | running |

## Pull requests

| PR | Content | State |
|---|---|---|
| [#118](https://github.com/bal7hazar/grimworld/pull/118) (`cv/cv-00-status`) | This file; `PENDING-cv-mandate.md` | Open; merged after #117 |

## Asked of the project manager

[PENDING-cv-mandate](../decisions/PENDING-cv-mandate.md): the account check on the Mac, and the
prefix `CV-*` for the track's own tooling briefs.

## Next

1. CV-01's report and pull request; its audit by `[GPT-6-Sol]` (security lens); fixes by resuming it.
2. Then ART-02 and CLI-03a in parallel (their allowlists do not overlap: `tools/art/**` and
   `client/app/src/**`), their audits as slots free; SPK-6a after.
