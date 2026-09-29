# Programme

**2026-09-29, 00:45 UTC** — written by the project manager `[Fable 5.1] Chef de projet Grim World`.
Rewritten at each of its check-ins. The live state of each track is in the track's own
`STATUS.md`; this file says where the programme is, what was decided and what waits for the
owner.

## Tracks

| Track | Repository | Orchestrator (model verified) | Where it is | Next stop |
|---|---|---|---|---|
| Game | `bal7hazar/grimworld` | `[Opus 5.5]` | Phase 0, 15 tasks done: FND-01, 01b, 02, 03, 06, ART-00, SPK-1, 1b, 2, 5, 5b, 7, 11, DES-21, DOC-01. Running: FND-04 (cost budgets). Then ENG-01 (core interfaces, brief written), FND-05, SPK-4 | Gate of Phase 0 |
| Map library (LIB) | `bal7hazar/hexx-cairo` | `[Fable 5.1]` | Milestone L-M1. Running: M1-T1a, the take-over of the engine. Waiting for its slot: the audits of M1-T1a and of LIB-04b | First release candidate of `hexx` 0.1.0: a publication, asked of the project manager |
| Packages (ARC) | `bal7hazar/quiver` | `[Opus 5.5]` | `quiver_quest`: library merged; component being redone around the held list (ARC-03c, fix loop 1 after a first audit) | `quiver_quest` 0.1.0: a publication, asked of the project manager |

Budget: 3 agents at a time across the three tracks, audits included (D-118); caps: game 2,
map library 1, `quiver` 1; the game comes first through a waiting marker (OPERATIONS §3).
In use at 00:45 UTC: 3 of 3 (FND-04, M1-T1a, ARC-03c). Machine: load 6, 23 GB available.

The three launchers hold their agents by slot locks and are on the same reference, commit
`2628b21` of the game's launcher, audited by `[GPT-6-Sol]`. Its scope is stated: it guards
against accidental over-launch and fails closed; it does not guard against a deliberate act
of the same Unix user.

## Decided on 2026-09-28 and 2026-09-29

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
| D-137 | The MVP's burners send directly, funded by the game; no paymaster before version 1 | Project manager |
| D-136 | An unrevealed chunk is wall in the window; the ADR amendments of DES-21 (played batches) accepted | Project manager |
| D-134 | Void chunks around every location; chunk corners are wall. SPK-7 measured the chunked map at +720k gas per tick with goblins (+14 %) | Project manager |
| D-131 | The API of `quiver_quest` and `quiver_achievement` accepted | Project manager |
| D-135 | `quiver_quest` bounds what a player holds (4 quests), not what a task reaches: worst call about 5.6M gas instead of 704M | Project manager |
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
| The cost of an expedition (R-2) | Measured at $0.69 to $0.87 with one action per transaction; estimated at $0.54 to $0.73 with batches of 10 and the MVP's burner (D-133, D-137); target $0.50. A new storage slot costs about 0.45M L2 gas and an overwritten one 0.03M (FND-04, reproduced by its audit). `enter` creates 4 new slots at each instance; reusing them is a design for ENG-01 to measure, not a saving observed. Next: FND-04's budgets, then ENG-01. A paymaster, needed on a public network, costs 2.2 to 5.1 times the fixed part: for the business model |
| Sessions and agents share one machine and one user with the owner's other programmes | Incident of 2026-09-29, 00:02 UTC: a wildcard deletion in `/tmp` by the game orchestrator; no damage found. Rule in OPERATIONS §3: delete and kill only what you created, by exact path and pid |
| Secrets reach every agent of the machine | The launchers empty them in their agents; the settings file is restricted to its owner; the residual is accepted |
| Audits that need four passes (LIB-03, LIB-04, SPK-2) | Tasks cut smaller; the rule of three loops applied by the project manager |
| The game waits for the library (R-18) | SPK-7 runs on `origami_hexmap` 1.8.0; LIB-05 starts with what the tick needs |
