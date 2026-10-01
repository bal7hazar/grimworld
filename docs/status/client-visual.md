# Status — track CV (the client's visual work, on the owner's Mac)

**2026-10-01 08:30 UTC** — written by the orchestrator of track CV,
`[Fable 5.1] Orchestrateur CV (client visuel)`, a session on the VPS created by the project manager on
2026-10-01 to replace the Mac's orchestrator, silent since the pause of 2026-09-29. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146, amended by D-149, D-151, D-152, D-153,
D-162). Rewritten at each check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

Every task of the pause is merged (CV-01, CV-02, ART-02, ART-03, CLI-03a, CLI-03b, SPK-6a, IDX-01a,
IDX-01b). The track's priorities since the transition (D-162) are the two spikes lent by the game:
**SPK-12** (client-side proving, D-161 §3 and D-172 §3: the structural answer to the expedition's cost,
R-2) and **SPK-13** (the compiler's non-reproducible builds, D-154, with D-164's CI/local fact). Both
briefs are merged ([#242](https://github.com/bal7hazar/grimworld/pull/242)); both agents are started
through `nexus run --require browser` (Opus 5.5, as the project manager's model policy says).
**SPK-13 runs on the Mac. SPK-12 is stuck on the control plane** (below). Codex is out until
2026-10-04 13:36 UTC: the audits of both spikes queue for its reset; the pull-request reviews fall back
to a Claude model (the standard's rule of 2026-10-01); **merges of the spikes wait for Codex's audits**,
as the project manager asked.

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| SPK-12 | **Client-side proving against L2 batches** (D-161, D-172): the segment model of S1, the cost side by side, the tick proved on the Mac with Stwo as `slingfall` does, a phone estimated, verification, the design consequences, a recommendation for the owner; [brief](../briefs/SPK-12-client-proving.md) | Opus 5.5 | **Blocked**: agent `grimworld/impl-spk-12` created 08:18:39 UTC with no account resolved (`account: null`, pool `workers`); its job waits on `no_provider` ("no approved machine has this provider and account"); `nexus continue` gave a second job with the same wait; `nexus retire` is forbidden to this session's token; a second `nexus run` is refused while the agent exists. The owner's to repair (retire the agent, or repair the dispatch); the brief is on `main`, nothing else is needed |
| SPK-13 | **Builds of the same sources that differ** (D-154, D-164): reproduce N times on the library at `310b5f1` and on `contracts/`, diff the Sierra, minimise, tell the toolchain, the platform and the cache apart; the VPS run is the orchestrator's with the spike's script; a draft upstream issue as a file; [brief](../briefs/SPK-13-compiler-determinism.md) | Opus 5.5 | **Running** on the Mac, `grimworld/impl-spk-13`, account claude-b7r, since 08:18:51 UTC; branch `spike/spk-13-compiler-determinism` |
| CV-01 | The Mac launcher, `scripts/mac/agent.sh` (retired by D-162: `nexus` starts the track's agents) | Opus 5.5 | Done, [#121](https://github.com/bal7hazar/grimworld/pull/121); [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md) |
| CV-02 | The launcher's budget of 5, load 18, the pinned Node (D-149) | Sonnet 5.5 | Done, [#129](https://github.com/bal7hazar/grimworld/pull/129); [report](../reports/CV-02-launcher-budget.md), [audit](../reports/CV-02-audit-gpt-6-sol.md) |
| ART-02 | The atlas: Python 3.12 or 3.13 with hashed pins, integer pipeline, pixel fingerprint | Opus 5.5 | Done, [#134](https://github.com/bal7hazar/grimworld/pull/134); [report](../reports/ART-02-atlas-scale.md), audits [quality](../reports/ART-02-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-02-audit-gpt-6-sol.md). Open: the Linux fingerprint (below) |
| ART-03 | Only the pack's own drawings (owner, 2026-09-29), all native; the generated sheets' code removed | Sonnet 5.5 | Done, [#164](https://github.com/bal7hazar/grimworld/pull/164); [report](../reports/ART-03-pack-originals.md), audits [quality](../reports/ART-03-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-03-audit-gpt-6-sol.md). Native heights: runt 73, skirmisher 70, slinger 67, shaman 70, hobgoblin 209, vanguard 87, warden 88, cleric 67 |
| CLI-03a | The rendering sandbox; three scale modes for PENDING-cv-integer-scale | Opus 5.5 | Done, [#135](https://github.com/bal7hazar/grimworld/pull/135); [report](../reports/CLI-03a-render-sandbox.md), audits [design and quality](../reports/CLI-03a-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03a-audit-gpt-6-sol.md) |
| CLI-03b | Sprites standing in their tile; a planned path to a far tile | Opus 5.5 | Done, [#163](https://github.com/bal7hazar/grimworld/pull/163); [report](../reports/CLI-03b-sandbox-path.md), audits [design and quality](../reports/CLI-03b-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03b-audit-gpt-6-sol.md) |
| SPK-6a | The protocol of SPK-6, aligned on D-151 and D-152 | Opus 5.5 | Done, [#138](https://github.com/bal7hazar/grimworld/pull/138); [report](../reports/SPK-6a-protocol.md) |
| IDX-01a | The indexer's core (lent, D-149); the CI job `indexer-node` (D-153) | Opus 5.5 | Done, [#144](https://github.com/bal7hazar/grimworld/pull/144); [report](../reports/IDX-01a-indexer-core.md), audits [security and quality](../reports/IDX-01a-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01a-audit-gpt-6-sol.md) |
| IDX-01b | Queries Q1-Q5 and Q7, subscriptions (R4), the client library of the freshness rule (R3) | Opus 5.5 | Done, [#154](https://github.com/bal7hazar/grimworld/pull/154); [report](../reports/IDX-01b-indexer-queries.md), audits [security and quality](../reports/IDX-01b-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01b-audit-gpt-6-sol.md) |
| The Capacitor shell | Before SPK-6.1, before Phase 6 (D-151, D-152); CV-03 proposed as its id | Opus 5.5 | Later |

## Agents on the Mac

Budget 5 (owner), held by Nexus. At 08:30 UTC: `grimworld/impl-spk-13` (Opus 5.5, build class) of
this track; `grimworld/review-arc-07b` (Fable 5.1, the review of quiver's ARC-07b, not this track's).
Load 3.9, free memory 46 GB (`nexus resources`, 08:19 UTC). Accounts (`nexus accounts --refresh`,
08:19 UTC): claude-b7r at 16 % of its week (resets 10-03 05:59 UTC), 4 % of its Fable week; Codex
unavailable (quota) until 2026-10-04 13:36 UTC.

## Open questions

| | For | State |
|---|---|---|
| **SPK-12's agent without an account** (`no_provider`, above) | The owner (Nexus) | **Blocking SPK-12**; told to the project manager 2026-10-01 |
| [PENDING-cv-integer-scale](../decisions/PENDING-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | Open |
| [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) | The project manager | The category of a balance; the unit of a lot's expiry |
| The `indexer-node` trigger paths | The project manager | Both audits of IDX-01a: narrower than the job's dependencies |
| ART-02's Linux fingerprint | This orchestrator, on the VPS, when the Mac's spikes are launched and followed | Carried from the pause (was: asked of the project manager) |
| CV-03 for the Capacitor shell | The project manager | Asked |
| design/10's mapping of the castes (ART-03) | The project manager | Told; the project manager updates design/10 and D-146 |

## Next

1. SPK-13: its report and pull request; a Claude-side quality lens meanwhile; `nexus review`; the
   `[GPT-6-Sol]` audit at Codex's reset; the VPS run of its `builds.sh` by this orchestrator; merge
   after the audit.
2. SPK-12: the same, once its agent is dispatched; `[GPT-6-Astra]` on the report.
3. Then, as the pause left them and the project manager lends them: CLI-02 (after ENG-02), the
   Capacitor shell before Phase 6, the hex tilemap when the owner's purchase arrives.
