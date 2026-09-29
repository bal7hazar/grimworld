# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 12:40 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146, amended by D-149, D-151, D-152,
D-153). Rewritten at each check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

The first lot of the track is merged: the Mac launcher (CV-01, CV-02), the atlas at the pack's scale
(ART-02), the rendering sandbox (CLI-03a) and the protocol of SPK-6 (SPK-6a). IDX-01a, the indexer's
core (lent by the game, D-149), is green on every CI job and in the second pass of its audits. The
sandbox waits for the owner's eye (sprite sizes; the scale mode of PENDING-cv-integer-scale).

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| CV-01 | The Mac launcher, `scripts/mac/agent.sh` | Opus 5.5 | **Done**, [#121](https://github.com/bal7hazar/grimworld/pull/121); [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md) |
| CV-02 | The launcher's budget of 5, load 18, the pinned Node (D-149) | Sonnet 5.5 | **Done**, [#129](https://github.com/bal7hazar/grimworld/pull/129); [report](../reports/CV-02-launcher-budget.md), [audit](../reports/CV-02-audit-gpt-6-sol.md) |
| ART-02 | The atlas at the pack's scale (D-146 as corrected, option B: the pack's units native, runt 67, shaman 87, hobgoblin 119), Python 3.12 or 3.13 with hashed pins, integer pipeline, pixel fingerprint | Opus 5.5 | **Done**, [#134](https://github.com/bal7hazar/grimworld/pull/134), three fix loops; [report](../reports/ART-02-atlas-scale.md), audits [quality](../reports/ART-02-audit-quality.md) and [`[GPT-6-Sol]`](../reports/ART-02-audit-gpt-6-sol.md) (PASS at the fourth pass). **Open: the Linux fingerprint**, asked of the project manager on the VPS (expected pixels+metadata `87c27153…`) |
| CLI-03a | The rendering sandbox on fixed data; three scale modes (`?scale=continuous\|snap\|sharp`) for PENDING-cv-integer-scale | Opus 5.5 | **Done**, [#135](https://github.com/bal7hazar/grimworld/pull/135), two fix loops and a last targeted fix; [report](../reports/CLI-03a-render-sandbox.md), audits [design and quality](../reports/CLI-03a-audit-design-quality.md) and [`[GPT-6-Sol]`](../reports/CLI-03a-audit-gpt-6-sol.md). The hex convention (x toward the West) checked by the orchestrator in `hexx-cairo` |
| SPK-6a | The protocol of SPK-6, aligned on D-151 and D-152 | Opus 5.5 | **Done**, [#138](https://github.com/bal7hazar/grimworld/pull/138); [report](../reports/SPK-6a-protocol.md) |
| IDX-01a | The indexer's core: the nine frozen events in versioned tables, rewind by hash and commitments, a test emitter on `contracts/persistent`'s types; the CI job `indexer-node` (D-153) | Opus 5.5 | **Done**, [#144](https://github.com/bal7hazar/grimworld/pull/144), two fix loops; [report](../reports/IDX-01a-indexer-core.md), audits [security and quality](../reports/IDX-01a-audit-security-quality.md) and [`[GPT-6-Sol]`](../reports/IDX-01a-audit-gpt-6-sol.md) (PASS at the third pass). Open with the project manager: the `indexer-node` trigger paths (both audits: narrower than the job's dependencies) |
| IDX-01b | Queries, subscriptions, the client's freshness rule ([brief](../briefs/IDX-01b-indexer-queries.md)) | Opus 5.5 | Launched once this brief is on `main` |
| The Capacitor shell | Before SPK-6.1, moved before Phase 6 (D-151, D-152). Called CV-02 in PLAN, an ID already taken by the launcher's budget: CV-03 proposed to the project manager | Opus 5.5 | Later |

## Agents on the Mac

Budget: 5 at a time, audits included, counted by the launcher's slots (every agent now goes through
`scripts/mac/agent.sh`). At 12:40 UTC: none; IDX-01b next.

## Open questions

| | For | State |
|---|---|---|
| [PENDING-cv-integer-scale](../decisions/PENDING-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | The sandbox shows the three modes with their figures (device pixels per art pixel, tiles across, cost of `sharp`'s offscreen pass) |
| ART-02's Linux fingerprint | The project manager (the VPS) | Asked on 2026-09-29 |
| CV-02 / CV-03 for the Capacitor shell | The project manager | Asked |

## The machine

Node 24.21.0 and pnpm 12.5.1 under asdf (no plugin added); Scarb 2.19.4, snforge 0.61.0,
starknet-devnet 0.10.0; `python3.12`. The agents' account is claude-b7r (`CLAUDE_CONFIG_DIR=~/.claude-b7r`),
checked before every launch. The atlas is built in the main checkout's ignored `tools/art/out/` for
the sandbox; nothing of the pack leaves the Mac.

## Next

1. IDX-01b; its audits (S P Q + `[GPT-6-Sol]`).
2. The owner's look at the sandbox (sizes, scale mode).
3. Candidates when lent or ready: CLI-02 (after ENG-02), the Capacitor shell before Phase 6.
