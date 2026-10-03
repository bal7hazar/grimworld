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

- **The rest of the day's merges, track CV** (on `main`): the SPK-13b finding
  ([#283](https://github.com/bal7hazar/grimworld/pull/283): the build path, not the platform, makes the 7
  artefacts differ) and the build-root rule it gave
  ([#290](https://github.com/bal7hazar/grimworld/pull/290)); the briefs of CLI-02
  ([#285](https://github.com/bal7hazar/grimworld/pull/285)), CV-03
  ([#287](https://github.com/bal7hazar/grimworld/pull/287)), CLI-03d
  ([#297](https://github.com/bal7hazar/grimworld/pull/297)) and CLI-03e
  ([#301](https://github.com/bal7hazar/grimworld/pull/301)); the SPK-13 issue draft
  ([#289](https://github.com/bal7hazar/grimworld/pull/289)) and the record of its filing
  ([#311](https://github.com/bal7hazar/grimworld/pull/311)); the docs of
  [#282](https://github.com/bal7hazar/grimworld/pull/282); **CLI-02a**, the sim parity harness
  ([#292](https://github.com/bal7hazar/grimworld/pull/292)); **CLI-03d**, the hubs follow-up
  ([#300](https://github.com/bal7hazar/grimworld/pull/300)); **CLI-03e**, the hubs with the real assets
  ([#307](https://github.com/bal7hazar/grimworld/pull/307)); two client fixes, the renderer race
  ([#302](https://github.com/bal7hazar/grimworld/pull/302)) and the I-5 dialog
  ([#304](https://github.com/bal7hazar/grimworld/pull/304)); the test de-flake and relock
  ([#308](https://github.com/bal7hazar/grimworld/pull/308)); the scarb calls under the VPS lock
  ([#309](https://github.com/bal7hazar/grimworld/pull/309)); phone work suspended
  ([#313](https://github.com/bal7hazar/grimworld/pull/313)).

**CLI-03e's choices** (the owner delegated them on 2026-10-02: "take what seems most relevant to you,
autonomously; we will iterate later"; reversible):

- **Q1, walking:** walking on the hex grid in the hubs stays, client-side, with tap menus on top (D-196).
  CLI-03e added no movement, so it is its own lot, **CLI-03f**, running
  ([brief #317](https://github.com/bal7hazar/grimworld/pull/317)).
- **Q2, buildings, colours, terrain:** CLI-03e's set is kept: the Blue faction; a house and a cottage rather
  than an inn or tavern (the inn read as one building with the Armorer in the screenshots); the path as soft
  earth hexes (the tileset has no path cell); grass on an island with a water backdrop.
- **Q3, the pack's UI chrome:** not in the hubs alone; one later lot for the whole client's chrome (panels,
  buttons, plates), so that screens stay consistent.

**Open pull requests of the track:** [#316](https://github.com/bal7hazar/grimworld/pull/316), the site lot
(publish `main`'s client at grimworld.bal7hazar.com; the art stays off until the owner decides; the owner
installs the timer, the ACL and the Caddy block); [#317](https://github.com/bal7hazar/grimworld/pull/317), the
CLI-03f brief, with CLI-03f running from it; [#306](https://github.com/bal7hazar/grimworld/pull/306), CV-03,
paused (phone work suspended).

**The upstream SPK-13 issue** (the upstream issue 10434, filed 2026-10-02, https://github.com/starkware-libs/cairo/issues/10434):
OPEN, 0 comment(s) at this writing. Watched at each status: a maintainer answer or a fix release changes
D-176's pin.

**Waiting for the owner (through the project manager):** SPK-12's Q1–Q6 and ADR-0001 (R-2); the owner's eye
on CLI-03f (the hubs at the expected visual level, D-196).
**Waiting for the project manager:** PENDING-cv-market-queries; the `indexer-node` trigger paths.

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| SPK-12 | **Client-side proving against L2 batches** (D-161, D-172); [brief](../briefs/SPK-12-client-proving.md) | Opus 5.5 | **Done**, [#257](https://github.com/bal7hazar/grimworld/pull/257) (`fff96d8`); [note](../research/SPK-12-client-proving.md), [report](../reports/SPK-12-client-proving.md), three reviews (above); no audit (D-177). Recommendation: keep L2 batches; the owner decides on ADR-0001 |
| SPK-13 | **Builds of the same sources that differ** (D-154, D-164); [brief](../briefs/SPK-13-compiler-determinism.md) | Opus 5.5 | **Done**, [#252](https://github.com/bal7hazar/grimworld/pull/252) (`63fc5eb`); [report](../reports/SPK-13-compiler-determinism.md), [README](../../spikes/SPK-13/README.md), four reviews (above); no audit (D-177). The issue was filed 2026-10-02: https://github.com/starkware-libs/cairo/issues/10434. SPK-13b merged ([#283](https://github.com/bal7hazar/grimworld/pull/283)): the build path, not the platform, makes the 7 artefacts differ |
| CLI-03c | **Hubs and the transitions, on fixed data** (D-178; D-178 says CLI-03b, an ID already taken by #163): the town and an outpost after design/11 *Hubs*, the Gate screen on ENG-03's seed, hub → instance through the entry moment to CLI-03a's renderer, instance → hub by a hub gate, `travel_back` or a debug defeat through a closing report; the pack's buildings as still sprites in `tools/art`; five points of design/11 *Hubs* written as "proposed, the owner's eye"; [brief](../briefs/CLI-03c-hubs.md) | Opus 5.5 | **Done**, [#270](https://github.com/bal7hazar/grimworld/pull/270) (`8b4e3a4`); the owner found it below the expected visual level (D-196), hence CLI-03e; [report](../reports/CLI-03c-hubs.md), [review](../reports/CLI-03c-review-sonnet.md) (Claude Sonnet 5.5, PASS WITH FINDINGS, three notes); no audit (D-177). Playwright drove Chrome on both viewports, every check passed, two real defects found and fixed. The five proposed points were accepted by the owner (D-194). The arrival rule (project manager, 2026-10-01): the client offers to leave only when the adventurer steps onto a gate tile after having left it, or through the Gate button, never on arrival; one line of design/11 if the owner agrees; no seed change |
| CLI-02a | **Client sim parity harness**, a mirror of the merged ENG-02 geometry ([brief](../briefs/CLI-02-sim-parity.md)) | Opus 5.5 | **Done**, [#292](https://github.com/bal7hazar/grimworld/pull/292) (`e405340`); CLI-02b (Fate/packing mirror) waits for track game's VEC-01, CLI-02c for ENG-07 |
| CLI-03d | **Hubs follow-up**, mechanics only ([brief](../briefs/CLI-03d-hubs-followup.md)) | Sonnet 5.5 | **Done**, [#300](https://github.com/bal7hazar/grimworld/pull/300) (`1ab8817`); brief [#297](https://github.com/bal7hazar/grimworld/pull/297) |
| CLI-03e | **Hubs at the expected visual level with the real assets** (D-196); choices above | Opus 5.5 | **Done**, [#307](https://github.com/bal7hazar/grimworld/pull/307) (`7a29d03`); brief [#301](https://github.com/bal7hazar/grimworld/pull/301) |
| CLI-03f | **Walking on the hex grid in the hubs**, client-side presentation (D-196) | Opus 5.5 | **Running**, brief [#317](https://github.com/bal7hazar/grimworld/pull/317); then the owner's eye |
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

CLI-03f runs (Mac); the site lot (#316) and CV-03 (#306, paused) are open as pull requests. Threads run on the VPS and, through `--machine mac`, on the Mac (browser and heavy work); `machine-capacity` is read before they start.

## Open questions

| | For | State |
|---|---|---|
| [2026-10-02-cv-integer-scale](../decisions/2026-10-02-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | Accepted as proposed, D-194 |
| [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) | The project manager | The category of a balance; the unit of a lot's expiry |
| The `indexer-node` trigger paths | The project manager | Both audits of IDX-01a: narrower than the job's dependencies |
| The client chrome lot (panels, buttons, plates of the pack) | The owner, later | Planned, not briefed (CLI-03e's Q3) |
| The art on the published site | The owner | Off until decided (D-73 and the licence) |
| design/10's mapping of the castes (ART-03) | The project manager | Told; the project manager updates design/10 and D-146 |

## Next

1. CLI-03f to the owner's eye.
2. CLI-02b (Fate/packing mirror) when track game's VEC-01 merges; CLI-02c after ENG-07.
3. The client chrome lot, for the whole client.
4. CV-03 and SPK-6.1: suspended (owner, 2026-10-02); they resume when phone work resumes.
