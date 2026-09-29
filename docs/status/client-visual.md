# Status — track CV (the client's visual work, on the owner's Mac)

**2026-09-29 14:35 UTC** — written by the orchestrator of track CV,
`[Opus 5.5] Orchestrateur client visuel (Mac)`. Mandate:
[ORCH-client-visual](../briefs/ORCH-client-visual.md) (D-146, amended by D-149, D-151, D-152,
D-153). Rewritten at each check-in; the project manager reads it like a track's `STATUS.md`.

## Where we are

Every task briefed so far is merged: the Mac launcher (CV-01, CV-02), the atlas (ART-02, ART-03), the
sandbox (CLI-03a, CLI-03b), the protocol of SPK-6 (SPK-6a) and the indexer lent by the game
(IDX-01a, IDX-01b). No agent runs. The owner has looked at the sandbox: sprites stand in their tile, a
tap on a far tile walks a planned path (a placeholder of the chain's finder), goblins do not move
(their AI is CLI-02's). The ground stays solid colours: the owner has asked Tiny Swords' artist for a
hex tilemap (a purchase, the owner's).

## Tasks

| ID | Task | Model | State |
|---|---|---|---|
| CV-01 | The Mac launcher, `scripts/mac/agent.sh` | Opus 5.5 | **Done**, [#121](https://github.com/bal7hazar/grimworld/pull/121); [report](../reports/CV-01-mac-launcher.md), [audit](../reports/CV-01-audit-gpt-6-sol.md) |
| CV-02 | The launcher's budget of 5, load 18, the pinned Node (D-149) | Sonnet 5.5 | **Done**, [#129](https://github.com/bal7hazar/grimworld/pull/129); [report](../reports/CV-02-launcher-budget.md), [audit](../reports/CV-02-audit-gpt-6-sol.md) |
| ART-02 | The atlas: Python 3.12 or 3.13 with hashed pins, integer pipeline, pixel fingerprint | Opus 5.5 | **Done**, [#134](https://github.com/bal7hazar/grimworld/pull/134); [report](../reports/ART-02-atlas-scale.md), audits [quality](../reports/ART-02-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-02-audit-gpt-6-sol.md). Open: the Linux fingerprint (asked of the project manager) |
| ART-03 | Only the pack's own drawings (owner, 2026-09-29): runt Thief, skirmisher Spear Goblin, slinger Torch Goblin, shaman Hex Shaman, hobgoblin Troll with windup and recover; all native; the generated sheets' code removed | Sonnet 5.5 | **Done**, [#164](https://github.com/bal7hazar/grimworld/pull/164); [report](../reports/ART-03-pack-originals.md), audits [quality](../reports/ART-03-audit-quality.md), [`[GPT-6-Sol]`](../reports/ART-03-audit-gpt-6-sol.md). Native heights: runt 73, skirmisher 70, slinger 67, shaman 70, hobgoblin 209, vanguard 87, warden 88, cleric 67 (the order rule warns: runt and skirmisher above the cleric) |
| CLI-03a | The rendering sandbox; three scale modes for PENDING-cv-integer-scale | Opus 5.5 | **Done**, [#135](https://github.com/bal7hazar/grimworld/pull/135); [report](../reports/CLI-03a-render-sandbox.md), audits [design and quality](../reports/CLI-03a-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03a-audit-gpt-6-sol.md) |
| CLI-03b | Sprites standing in their tile (an adjustable foot offset); a planned path to a far tile (`findPath`, the walk, the stops of design/02 the sandbox can evaluate), after the owner's first look | Opus 5.5 | **Done**, [#163](https://github.com/bal7hazar/grimworld/pull/163); [report](../reports/CLI-03b-sandbox-path.md), audits [design and quality](../reports/CLI-03b-audit-design-quality.md), [`[GPT-6-Sol]`](../reports/CLI-03b-audit-gpt-6-sol.md) |
| SPK-6a | The protocol of SPK-6, aligned on D-151 and D-152 | Opus 5.5 | **Done**, [#138](https://github.com/bal7hazar/grimworld/pull/138); [report](../reports/SPK-6a-protocol.md) |
| IDX-01a | The indexer's core (lent, D-149); the CI job `indexer-node` (D-153) | Opus 5.5 | **Done**, [#144](https://github.com/bal7hazar/grimworld/pull/144); [report](../reports/IDX-01a-indexer-core.md), audits [security and quality](../reports/IDX-01a-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01a-audit-gpt-6-sol.md) |
| IDX-01b | Queries Q1-Q5 and Q7, subscriptions (R4), the client library of the freshness rule (R3) for CLI-01 | Opus 5.5 | **Done**, [#154](https://github.com/bal7hazar/grimworld/pull/154); [report](../reports/IDX-01b-indexer-queries.md), audits [security and quality](../reports/IDX-01b-audit-security-quality.md), [`[GPT-6-Sol]`](../reports/IDX-01b-audit-gpt-6-sol.md) |
| The Capacitor shell | Before SPK-6.1, before Phase 6 (D-151, D-152); called CV-02 in PLAN, an ID taken: CV-03 proposed | Opus 5.5 | Later |

## Agents on the Mac

None running. Budget: 5 at a time, counted by the launcher's slots.

## Open questions

| | For | State |
|---|---|---|
| [PENDING-cv-integer-scale](../decisions/PENDING-cv-integer-scale.md) | The owner's eye on the sandbox, then SPK-6 | Open |
| [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) | The project manager | The category of a balance; the unit of a lot's expiry |
| The `indexer-node` trigger paths | The project manager | Both audits of IDX-01a: narrower than the job's dependencies |
| ART-02's Linux fingerprint | The project manager (the VPS) | Asked |
| CV-03 for the Capacitor shell | The project manager | Asked |
| design/10's mapping of the castes (ART-03) | The project manager | Told; the project manager updates design/10 and D-146 |

## Next

Candidates when lent or ready: CLI-02 (after ENG-02), the Capacitor shell before Phase 6; the hex
tilemap when the owner's purchase arrives (a licence check, then the private asset repository and
`tools/art`).
