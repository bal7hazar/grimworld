# Status

**2026-09-28** — written by the project-manager session `[Fable 5.1] Chef de projet Grim World`.

## Where we are

**Phase 0 — Foundations**, opened today. The repository still holds documents only. FND-00
(bootstrap of the project-manager session on the VPS) is done: accounts, toolchain, repository
and machine checked, report given to the owner, three rounds of decisions recorded.

## What moved today

| | |
|---|---|
| Owner review, round 3 and follow-up | All proposed decisions accepted (D-02, D-04, D-30, D-31, D-41, D-50, D-52 conditional on SPK-2, D-63, D-80); D-115 trials generated, D-116 mainnet go, D-117 library repository, D-118 concurrency: [docs/decisions/2026-09-28-owner-review-3.md](docs/decisions/2026-09-28-owner-review-3.md) |
| Design reconciled with ADR-0006 and the accepted decisions | PR #5: design/01, 02, 04, 06, 07, 09, 13, 15, 17, 18; ADR-0005 status |
| Spikes moved to burner accounts | PLAN v0.13; ADR-0001 and ADR-0003 validation tables (this PR) |
| Orchestrator mandates | [docs/briefs/ORCH-game.md](docs/briefs/ORCH-game.md), [docs/briefs/ORCH-hexmap.md](docs/briefs/ORCH-hexmap.md) |
| Milestone M0 | Reached |

## Orchestrators and agents

| Orchestrator | Session | First task | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | FND-03 agent tooling, then SPK-5 ∥ ART-00 | Being created by the project manager |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | LIB-02 analysis of `hexx`, stop at gate L-G1 | Being created by the project manager |

Sub-agents running: none yet. Budget: 3 Grim World agents at a time (D-118): 2 for the game,
1 for the library in wave 1.

## Machine (VPS, 2026-09-28 13:40 UTC)

| | |
|---|---|
| Accounts | `claude` CLI on claude-b7r ✓; `gh` on bal7hazar, ADMIN on grimworld and tiny-swords ✓; codex 0.155.1 with gpt-6-astra / sol / luna ✓ |
| Toolchain | scarb 2.19.4, snforge 0.61.0, node 24.21, pnpm 12.5 present; **sozo, katana, torii absent** (SPK-5 installs and pins them) |
| Load | 8 cores, load ≈ 5–9 with 3 agents of the owner's other programmes (nalgebra, rapier); 31 GB RAM, ~19 GB available |
| Sepolia credentials | Not in the environment; not needed before Phase 1 (owner) |
| `assets` submodule | Not initialised in the main checkout; an independent clone of `tiny-swords` at the same commit exists in `~/projects/assets`. Initialised only in worktrees that need the art |

## Blocked

| What | By |
|---|---|
| Any sub-agent launch | FND-03 (the launcher), first task of the game orchestrator |
| SPK-1, deployments | Sepolia credentials, Phase 1 |
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Open on the owner's side (not blocking)

Q-12 Arcanist sprite or Cleric (Phase 2); reaction to the lore premise (DES-14); Q-08
registry writers and Q-03 defeat severity (Phase 1).

## MVP and version 1

The MVP is a test version: burner accounts, randomness from the transaction hash, test
networks only, nothing of value, progress may be wiped. Version 1 replaces both providers
behind their interfaces and goes through the hardening phase.

## Design coverage

Written: 19 design documents, the lore premise, 6 ADRs. Still to write before the phases that
need them: effect catalogue, remaining skills, caste sheets, curves, content lists
([PLAN.md](PLAN.md#design-backlog)).

## Not verified

- Latency and cost on mainnet: public data only, no transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
- Nothing in this repository has been built or tested: there is nothing to build yet.
