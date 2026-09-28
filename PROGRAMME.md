# Programme

**2026-09-28, 22:40 UTC** — written by the project manager `[Fable 5.1] Chef de projet Grim World`.
Rewritten at each of its check-ins. The live state of each track is in the track's own
`STATUS.md`; this file says where the programme is, what was decided and what waits for the
owner.

## Tracks

| Track | Repository | Orchestrator (model verified) | Where it is | Next stop |
|---|---|---|---|---|
| Game | `bal7hazar/grimworld` | `[Opus 5.5]` | Phase 0. Done: FND-01b, FND-02, FND-03, FND-06, SPK-1, SPK-2, SPK-5b, SPK-11, ART-00. Running: SPK-7 (chunked maps), SPK-1b (account's part of a transaction). To come: DES-21, FND-05, SPK-4, FND-04 | Gate of Phase 0 |
| Map library (LIB) | `bal7hazar/hexx-cairo` | `[Fable 5.1]` | Gates L-G1 and L-G2 passed. LIB-04 merged under option B; LIB-05 starts with the take-over of the engine, then the assembly and the flood | First release candidate of `hexx` 0.1.0: a publication, asked of the project manager |
| Packages (ARC) | `bal7hazar/quiver` | `[Opus 5.5]` | Gate A-G1 passed. Workspace merged; `quiver_quest`: library merged, component in audit | `quiver_quest` 0.1.0: a publication, asked of the project manager |

Budget: 3 agents at a time across the three tracks, audits included (D-118, OPERATIONS §3).
The machine also runs the owner's other programmes: about 6 agents in all.

## Decided on 2026-09-28

| # | Decision | By |
|---|---|---|
| D-119 | `hexx` ported in full in `hexx-cairo`; `origami_hexmap` decommissioned at the end | Owner |
| D-120 | The window follows the adventurer, 15 × 16, not stored | Owner |
| D-121 | `main` is not protected for now | Owner |
| D-123 | Native Starknet contracts, without Dojo (ADR-0007). Measured since: native costs 0.26× to 0.58× Dojo | Owner |
| D-124, D-125 | The Arcade packages rewritten natively in one repository, `quiver` | Owner |
| D-126, D-127 | The porting plan of `hexx` accepted; the flood of the tick stops at 15 layers | Owner |
| D-128 | The project manager goes ahead with its own recommendations and reports | Owner |
| D-132 | Publications on scarbs.xyz are decided by the project manager in the owner's name | Owner |
| D-129, D-133 | The threshold of $0.50 for 300 actions stays the target; it does not hold with one action per transaction ($0.69 to $0.87 on Sepolia); played actions are sent in batches | Project manager |
| D-130 | The indexer is our own | Project manager |
| D-131 | The API of `quiver_quest` and `quiver_achievement` accepted | Project manager |
| — | LIB-03 and LIB-04 merged after more than three fix loops, their open findings carried as tasks | Project manager |

Every decision has its file in [docs/decisions/](docs/decisions/) and its row in
[CONTEXT.md](CONTEXT.md) §6.

## Waiting for the owner

Nothing blocks.

| Open, without urgency | Needed by |
|---|---|
| Q-12: the Arcanist needs a sprite to commission, or the Cleric takes its place in the MVP | Phase 2 |
| The owner's reaction to the lore premise | LORE-01 |
| The business model (Q-10): an active player costs the game about $3.5 to $4.7 a day at today's figures, before batches | Before mainnet |
| Art: the size of goblins on screen (ART-1), the slinger's sprite (ART-2) | CLI-03, ART-01 |

## Risks watched

| Risk | State |
|---|---|
| The cost of an expedition (R-2) | Over the target by 1.4× to 1.75× with one action per transaction; batches (D-133) and SPK-1b in progress |
| Secrets reach every agent of the machine | The launchers empty them in their agents; the settings file is restricted to its owner; the residual is accepted |
| Audits that need four passes (LIB-03, LIB-04, SPK-2) | Tasks cut smaller; the rule of three loops applied by the project manager |
| The game waits for the library (R-18) | SPK-7 runs on `origami_hexmap` 1.8.0; LIB-05 starts with what the tick needs |
