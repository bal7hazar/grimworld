# Status

**2026-09-28** — written by the orchestrator session `[Fable 5.1]`.

## Where we are

Phase −1 (ideation). The repository holds documents only. No code, no agent launched
through the CLI yet.

## What moved

| | |
|---|---|
| Design documents 00–10 | Written, revised once after the owner's first review (v0.2) |
| ADR-0001 execution layer | Accepted by the owner: Starknet mainnet, subject to spikes |
| ADR-0002 randomness | Proposed |
| ADR-0003 client | Accepted by the owner, subject to the phone spike: TypeScript, PixiJS on demand, Capacitor |
| Owner review, round 2 | Answered: [docs/decisions/2026-09-28-owner-review-2.md](docs/decisions/2026-09-28-owner-review-2.md) |
| VPS bootstrap prompt | Written: [docs/briefs/PM-vps-bootstrap.md](docs/briefs/PM-vps-bootstrap.md) |
| OPERATIONS | Realigned on the owner's conventions from the other programmes |
| Research (in-session, read-only) | Grimscape and Athanor; Starknet stack; `origami_hexmap`; mobile client options |

## Running agents

None.

## Blocked

| What | By |
|---|---|
| Phase 0 launch | The owner starting the project-manager session on the VPS (FND-00); documents must be committed and pushed first |
| Mainnet, later | Q-17 |

## Since the pull request was opened

Owner's third review (2026-09-28): adventurer slots and vault, estate, titles, quests of
Region 1, equipment with loot and boss sets, trade and auction house; companions designed
then withdrawn; ADR-0004 on the Arcade packages. The MVP has grown: see risk R-13.

## Design coverage

Rules and direction are written; interface, content and numbers are not. See the design
backlog in [PLAN.md](PLAN.md#design-backlog): 15 items, two of them (interface, vision)
due before Phase 1.

## Not verified

- Latency and cost on mainnet: public data only, no transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
- Nothing in this repository has been built or tested: there is nothing to build yet.
