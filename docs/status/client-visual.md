# Status — track CV (the client's visual work)

**2026-10-02** — written by the orchestrator of track CV, running in herdr as project `grimworld-cv`
(it succeeds the Nexus session `[Opus 5.5] Orchestrateur CV (client visuel)`, stopped at the soft stop of
2026-10-01). Mandate: [ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146, amended by D-149,
D-151, D-152, D-153, D-162). Rewritten at each check-in; the project manager reads it like a track's
`STATUS.md`.

## Where we are

The track now runs in herdr: threads of project `grimworld-cv` on the VPS and on the Mac, reviews on
another model than the one that wrote the code; Nexus is not used. Audits stay the exception (D-177); none
was asked for the two spikes, whose measurements carry them.

**Done today:**

- **SPK-13** merged, [#252](https://github.com/bal7hazar/grimworld/pull/252) (`63fc5eb`), after three reviews
  and three fix loops ([reviews](../reports/SPK-13-review-d0c0788-sonnet.md),
  [9d21082](../reports/SPK-13-review-9d21082-opus.md), [6238e46](../reports/SPK-13-review-6238e46-opus.md),
  [a2e98a5](../reports/SPK-13-review-a2e98a5-opus.md)). Its facts: the drift's cause is the salsa intern-id
  order in the compiler's parallel warm-up (which function of a call-graph cycle gets the `withdraw_gas`
  check); one thread (`RAYON_NUM_THREADS=1`, D-176) gives one program, stable per machine; Scarb 2.20.1
  still drifts; **across machines 7 of 51 artefacts differ, in two open groups** (`persistent`/Registry;
  `logic_integrationtest`). Programme rule from it: pins (hashes, class sizes, gas snapshots, fingerprints)
  are generated on Linux only.
- **SPK-12** merged, [#257](https://github.com/bal7hazar/grimworld/pull/257) (`fff96d8`), after three reviews
  ([903c38f](../reports/SPK-12-review-903c38f-sonnet.md), [05a9745](../reports/SPK-12-review-05a9745-opus.md),
  [b42d11b](../reports/SPK-12-review-b42d11b-opus.md)); its answer to R-2 is the note's recommendation: keep L2
  batches (ADR-0001 option A) for the MVP. The reviews' last notes are applied in the pull request that
  archives them.
- **ART-02's Linux fingerprint** closed by [#278](https://github.com/bal7hazar/grimworld/pull/278)
  (`5052c4f`): identical on Linux x86_64 and macOS arm64 at `4c2b25c`.

**Waiting for the owner (through the project manager):** filing the SPK-13 issue draft
(`spikes/SPK-13/issue-draft.md`, not filed); SPK-12's Q1–Q6 and ADR-0001 (R-2); the test of CLI-03c, its five
points and the arrival rule; PENDING-cv-integer-scale.
**Waiting for the project manager:** SPK-13b (the cause of the Mac/Linux difference), proposed;
PENDING-cv-market-queries; the `indexer-node` trigger paths; `verify-cli03c.mjs` as a committed dev script.

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| SPK-12 | **Client-side proving against L2 batches** (D-161, D-172); [brief](../briefs/SPK-12-client-proving.md) | Opus 5.5 | **Done**, [#257](https://github.com/bal7hazar/grimworld/pull/257) (`fff96d8`); [note](../research/SPK-12-client-proving.md), [report](../reports/SPK-12-client-proving.md), three reviews (above); no audit (D-177). Recommendation: keep L2 batches; the owner decides on ADR-0001 |
| SPK-13 | **Builds of the same sources that differ** (D-154, D-164); [brief](../briefs/SPK-13-compiler-determinism.md) | Opus 5.5 | **Done**, [#252](https://github.com/bal7hazar/grimworld/pull/252) (`63fc5eb`); [report](../reports/SPK-13-compiler-determinism.md), [README](../../spikes/SPK-13/README.md), four reviews (above); no audit (D-177). The issue draft stays a file until the owner's go. Open: SPK-13b, the cross-machine difference |
| CLI-03c | **Hubs and the transitions, on fixed data** (D-178; D-178 says CLI-03b, an ID already taken by #163): the town and an outpost after design/11 *Hubs*, the Gate screen on ENG-03's seed, hub → instance through the entry moment to CLI-03a's renderer, instance → hub by a hub gate, `travel_back` or a debug defeat through a closing report; the pack's buildings as still sprites in `tools/art`; five points of design/11 *Hubs* written as "proposed, the owner's eye"; [brief](../briefs/CLI-03c-hubs.md) | Opus 5.5 | **Done**, [#270](https://github.com/bal7hazar/grimworld/pull/270) (`8b4e3a4`); [report](../reports/CLI-03c-hubs.md), [review](../reports/CLI-03c-review-sonnet.md) (Claude Sonnet 5.5, PASS WITH FINDINGS, three notes); no audit (D-177). Playwright drove Chrome on both viewports, every check passed, two real defects found and fixed. **The owner tests it** (`?hub=town`, `?hub=outpost`). **Follow-up, after the owner's test**: the owner's choices on the five proposed points; the arrival rule (project manager, 2026-10-01): the client offers to leave only when the adventurer steps onto a gate tile after having left it, or through the Gate button, never on arrival; one line of design/11 if the owner agrees; no seed change |
| CLI-03a check | **The owner's test of Playwright on the Mac through Nexus** (project manager, 2026-10-01): a verification run of the merged sandbox, no implementation; Playwright launched Chrome 154 headless, every browser-checkable criterion of CLI-03a passed at 375 × 812 and 1440 × 900, four commands refused by the profile (a compound command, two `ls` outside the worktree, `lsof`), no wait, no defect, nothing committed | Opus 5.5 | Done 08:34 UTC, `grimworld/impl-cli-03a`; [report](../reports/CLI-03a-browser-check.md); told to the project manager |
| CV-01 | The Mac launcher, `scripts/mac/agent.sh` (retired by D-162: `nexus` starts the track's agents) | Opus 5.5 | Done, [#121](https://github.com/bal7hazar/grimworld/pull/121); [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md) |
| CV-02 | The launcher's budget of 5, load 18, the pinned Node (D-149) | Sonnet 5.5 | Done, [#129](https://github.com/bal7hazar/grimworld/pull/129); [report](../reports/CV-02-launcher-budget.md), [audit](../reports/CV-02-audit-gpt-6-sol.md) |
| ART-02 | The atlas: Python 3.12 or 3.13 with hashed pins, integer pipeline, pixel fingerprint | Opus 5.5 | Done, [#134](https://github.com/bal7hazar/grimworld/pull/134); [report](../reports/ART-02-atlas-scale.md), audits [quality](../reports/ART-02-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-02-audit-gpt-6-sol.md). Linux fingerprint closed by [#278](https://github.com/bal7hazar/grimworld/pull/278) (`5052c4f`), identical on Linux and macOS at `4c2b25c` |
| ART-03 | Only the pack's own drawings (owner, 2026-09-29), all native; the generated sheets' code removed | Sonnet 5.5 | Done, [#164](https://github.com/bal7hazar/grimworld/pull/164); [report](../reports/ART-03-pack-originals.md), audits [quality](../reports/ART-03-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-03-audit-gpt-6-sol.md). Native heights: runt 73, skirmisher 70, slinger 67, shaman 70, hobgoblin 209, vanguard 87, warden 88, cleric 67 |
| CLI-03a | The rendering sandbox; three scale modes for PENDING-cv-integer-scale | Opus 5.5 | Done, [#135](https://github.com/bal7hazar/grimworld/pull/135); [report](../reports/CLI-03a-render-sandbox.md), audits [design and quality](../reports/CLI-03a-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03a-audit-gpt-6-sol.md) |
| CLI-03b | Sprites standing in their tile; a planned path to a far tile | Opus 5.5 | Done, [#163](https://github.com/bal7hazar/grimworld/pull/163); [report](../reports/CLI-03b-sandbox-path.md), audits [design and quality](../reports/CLI-03b-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03b-audit-gpt-6-sol.md) |
| SPK-6a | The protocol of SPK-6, aligned on D-151 and D-152 | Opus 5.5 | Done, [#138](https://github.com/bal7hazar/grimworld/pull/138); [report](../reports/SPK-6a-protocol.md) |
| IDX-01a | The indexer's core (lent, D-149); the CI job `indexer-node` (D-153) | Opus 5.5 | Done, [#144](https://github.com/bal7hazar/grimworld/pull/144); [report](../reports/IDX-01a-indexer-core.md), audits [security and quality](../reports/IDX-01a-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01a-audit-gpt-6-sol.md) |
| IDX-01b | Queries Q1-Q5 and Q7, subscriptions (R4), the client library of the freshness rule (R3) | Opus 5.5 | Done, [#154](https://github.com/bal7hazar/grimworld/pull/154); [report](../reports/IDX-01b-indexer-queries.md), audits [security and quality](../reports/IDX-01b-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01b-audit-gpt-6-sol.md) |
| The Capacitor shell | Before SPK-6.1, before Phase 6 (D-151, D-152); CV-03 proposed as its id | Opus 5.5 | **Suspended (owner, 2026-10-02)**; its pull request (#306) stays open, paused, not to be merged until resumed |
| SPK-6.1 (the phone verdict) | SPK-6.1 | Orchestrator + Opus 5.5 | **Suspended (owner, 2026-10-02)**; mobile-first design is kept, tests and measures run on desktop |
| CLI-02, the full-tick threshold | 10 queued actions within one 60 Hz frame (16.7 ms), Node and browser worker | Opus 5.5 | Re-checked on a phone when phone work resumes (phone work suspended by the owner, 2026-10-02) |

## Agents

None of the track runs at this writing. Threads run on the VPS and, through `--machine mac`, on the Mac (browser and heavy work); `machine-capacity` is read before they start.

## Open questions

| | For | State |
|---|---|---|
| [2026-10-02-cv-integer-scale](../decisions/2026-10-02-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | Accepted as proposed, D-194 |
| [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) | The project manager | The category of a balance; the unit of a lot's expiry |
| The `indexer-node` trigger paths | The project manager | Both audits of IDX-01a: narrower than the job's dependencies |
| SPK-13b: the cause of the Mac/Linux difference (two open groups) | The project manager | Proposed |
| CV-03 for the Capacitor shell | The project manager | Asked |
| design/10's mapping of the castes (ART-03) | The project manager | Told; the project manager updates design/10 and D-146 |

## Next

1. CLI-03d, after the owner's test of CLI-03c.
2. CLI-02, when ENG-02 is merged.
3. The Capacitor shell: suspended (owner, 2026-10-02); resumes before Phase 6 when phone work resumes.
