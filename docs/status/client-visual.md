# Status — track CV (the client's visual work, on the owner's Mac)

**2026-10-01 14:05 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur CV (client visuel)` (on Fable 5.1 until 14:00 UTC; the owner's rule puts every orchestrator on Opus 5.5), a session on the VPS created by the project manager on
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
**SPK-12 runs on the Mac (the tick proved, the note being written); SPK-13, interrupted by the 4-hour job limit with its cause found (D-176 takes it), is resumed and queues behind it** (below). **Audits are the exception (D-177, owner's rule of 2026-10-01)**: the review of the pull request is
the routine gate; an audit only for value, access control, randomness, a published interface, a cost or
determinism only a measurement proves, a large refactoring, or a lot the owner asks to see. **Audits
stopped: 0** (`nexus agents --all` lists none of this track, queued or past). **Planned audits dropped:
2**, SPK-12's (cost, `[GPT-6-Astra]` then Opus 5.5) and SPK-13's (method, `[GPT-6-Sol]` then Opus 5.5):
their measurements and SPK-13's single-thread pin test carry them, and the review reads the report (the
project manager's reading). Each pull request says why an audit was asked or that none was needed.
Reviews: Claude Sonnet while Codex has no quota.

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| SPK-12 | **Client-side proving against L2 batches** (D-161, D-172): the segment model of S1, the cost side by side, the tick proved on the Mac with Stwo as `slingfall` does, a phone estimated, verification, the design consequences, a recommendation for the owner; [brief](../briefs/SPK-12-client-proving.md) | Opus 5.5 | **Running** on the Mac since 12:19:02 UTC, `grimworld/impl-spk-12`, account claude-b7r, class heavy (it takes the Mac's whole offer, raised by the owner to 8 CPU / 45 GB; the earlier `no_provider` wait was the heavy class not fitting 6 CPU, nexus #36, #39); branch `spike/spk-12-client-proving` |
| SPK-13 | **Builds of the same sources that differ** (D-154, D-164): reproduce N times on the library at `310b5f1` and on `contracts/`, diff the Sierra, minimise, tell the toolchain, the platform and the cache apart; the VPS run is the orchestrator's with the spike's script; a draft upstream issue as a file; [brief](../briefs/SPK-13-compiler-determinism.md) | Opus 5.5 | **Interrupted by the platform's 4-hour wall-clock limit** at 12:18:52 UTC during its last control series, no report yet; **resumed** (`nexus continue`, 12:25 UTC) with the order to finish and report first; its new job queues behind SPK-12 (a heavy job takes the whole Mac). Pull request [#252](https://github.com/bal7hazar/grimworld/pull/252), work in progress, CI green at `97b6494`. **Cause found, not yet reported**: the two Sierra programs differ only by which function of a call-graph cycle gets the `withdraw_gas` check; the choice follows the cycle's SCC representative, the lowest salsa intern id, which the compiler's parallel warm-up assigns in thread order; `RAYON_NUM_THREADS=1` gives one program 10 times out of 10, 12 threads gave three values (27,092 / 27,101 / 27,101 Sierra felts, three class hashes) on `HexxGenerators`; a minimal program and a draft issue for `starkware-libs/cairo` are on the branch **The VPS run is done** (this orchestrator, 12:26–12:59 UTC, `builds.sh` at `97b6494`, x86_64, 8 CPUs, `scripts/lock.sh`'s 4 threads): `consumer` 10 builds in each of three series (the machine's cache, a fresh cache, one thread), `contracts` 5 in each of two (clean, one thread); **every class identical in every build**, `HexxGenerators` 27,092 Sierra felts, CASM 49,375, at 4 threads as at 1; the programs of `contracts` differ between builds only by their ids' numbers (one canonical text per artefact, 129 of 129). So the single-thread value is 27,092, the committed snapshot; the VPS already gives it; CI's 27,101 is the value D-176's pin will remove; the table goes into #252 as `builds-vps.txt` once the agent's last push is in |
| CLI-03a check | **The owner's test of Playwright on the Mac through Nexus** (project manager, 2026-10-01): a verification run of the merged sandbox, no implementation; Playwright launched Chrome 154 headless, every browser-checkable criterion of CLI-03a passed at 375 × 812 and 1440 × 900, four commands refused by the profile (a compound command, two `ls` outside the worktree, `lsof`), no wait, no defect, nothing committed | Opus 5.5 | Done 08:34 UTC, `grimworld/impl-cli-03a`; [report](../reports/CLI-03a-browser-check.md); told to the project manager |
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

Budget 5 (owner), held by Nexus. At 12:30 UTC: `grimworld/impl-spk-12` (Opus 5.5, heavy class, the whole offer) of this track;
`grimworld/impl-spk-13` queued behind it; `grimworld/impl-cli-03a` ended 08:34 UTC (browser class); `grimworld/review-arc-07b` (Fable 5.1, the review of quiver's ARC-07b, not this track's).
Load 3.9, free memory 46 GB (`nexus resources`, 08:19 UTC). Accounts (`nexus accounts --refresh`,
08:19 UTC): claude-b7r at 16 % of its week (resets 10-03 05:59 UTC), 4 % of its Fable week; Codex
unavailable (quota) until 2026-10-04 13:36 UTC.

## Open questions

| | For | State |
|---|---|---|
| [PENDING-cv-integer-scale](../decisions/PENDING-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | Open |
| [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) | The project manager | The category of a balance; the unit of a lot's expiry |
| The `indexer-node` trigger paths | The project manager | Both audits of IDX-01a: narrower than the job's dependencies |
| ART-02's Linux fingerprint | This orchestrator, on the VPS, when the Mac's spikes are launched and followed | Carried from the pause (was: asked of the project manager) |
| CV-03 for the Capacitor shell | The project manager | Asked |
| design/10's mapping of the castes (ART-03) | The project manager | Told; the project manager updates design/10 and D-146 |

## Next

1. SPK-12's report and pull request; the review (no audit, D-177); merge; the report to the project
   manager for the owner's decision on ADR-0001.
2. SPK-13's report and the end of #252, with the VPS table (below); the review (no audit, D-177);
   merge; the draft issue stays a file until the owner's go (D-154 §3, asked by the project manager).
3. Then, as the pause left them and the project manager lends them: CLI-02 (after ENG-02), the
   Capacitor shell before Phase 6, the hex tilemap when the owner's purchase arrives.
