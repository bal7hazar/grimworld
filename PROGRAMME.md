# Programme

**2026-09-29, 09:40 UTC** — written by the project manager `[Opus 5.5] Chef de projet Grim World`, before handing over to a fresh session ([handoff](docs/briefs/PM-handoff-2026-09-29.md)).
Rewritten at each of its check-ins. The live state of each track is in the track's own
`STATUS.md`; this file says where the programme is, what was decided and what waits for the
owner.

## Tracks

| Track | Repository | Orchestrator (model verified) | Where it is | Next stop |
|---|---|---|---|---|
| Game | `bal7hazar/grimworld` | `[Opus 5.5]` | Phase 0, 18 tasks done. **ENG-01 is merged: the interfaces, storage layouts and events of the five contracts are frozen**, designed against the cost budget. SPK-4 done: the client mirrors the rules in TypeScript. Next: ENG-01b (accounting), FND-05 (providers), then the engine tasks of Phase 1 | Gate of Phase 0 |
| Map library (LIB) | `bal7hazar/hexx-cairo` | `[Opus 5.5]` | Milestone L-M1. Running: M1-T1a, the take-over of the engine. Waiting for its slot: the audits of M1-T1a and of LIB-04b | First release candidate of `hexx` 0.1.0: a publication, asked of the project manager |
| Packages (ARC) | `bal7hazar/quiver` | `[Opus 5.5]` | ARC-06 merged and reviewed by the owner (D-147). Next: ARC-07, both packages rewritten as 0.2.0 without `logic/`, tracking chosen by the consumer | ARC-07's first lot shown to the owner |
| Client visual (CV) | `bal7hazar/grimworld` (`client/app`, `tools/art`) | A local orchestrator on the owner's Mac (D-146) | Opened 2026-09-29: ART-02, CLI-03a, SPK-6a | The sandbox shown to the owner |

Budget: 3 agents at a time across the three tracks, audits included (D-118); caps: game 2,
map library 1, `quiver` 1; the game comes first through a waiting marker (OPERATIONS §3).
The three tracks hold their slots through the launchers' locks.

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
| D-138 | **First publication**: `quiver_quest` 0.1.0 on scarbs.xyz, after the project manager's own checks; the registry lists it with the checksum of the go | Project manager, in the owner's name |
| D-150 | The game's slots while the engine chain waits: DES-04 then CBT-01; FND-08, the funder | Project manager |
| D-149 | The Mac takes tasks of the game without Sepolia, under track CV's orchestrator: IDX-01 first; 5 agents on the Mac (owner) | Project manager; budget by the owner |
| D-148 | ENG-06: three measured budgets on the lifecycle; a gate is used by standing on its anchor tile; armor flat until BAL-01 | Project manager |
| D-147 | The owner's review of ARC-06: no `logic/` folder; tracking a model is optional, chosen by the consumer | Owner |
| D-146 | **Track CV** on the owner's Mac: the client's visual work; ART-1 answered provisionally | Project manager |
| D-143 | **The owner's rule on the organisation of Cairo code**: Arcade's layering, functions scoped in traits, models with their storage and their event, the store emitting on write | Owner |
| D-142 | **Second publication**: `quiver_achievement` 0.1.0, event mode only; the registry lists it with the checksum of the go; both packages consumed together by a fresh project | Project manager, in the owner's name |
| D-141 | ENG-01 merged; its design escalations decided (caps of a batch, belt credited back on defeat, nothing carries through a gate, content version) | Project manager |
| D-140 | A rule never panics on a legal action; percent modifiers of damage are summed, not multiplied; the client mirrors the rules in TypeScript, checked by vectors from the Cairo code | Project manager |
| D-139 | `quiver_achievement` 0.1.0 in event mode only: its storage mode would cost about 200M gas in the worst call | Project manager |
| D-137 | The MVP's burners send directly, funded by the game; no paymaster before version 1 | Project manager |
| D-136 | An unrevealed chunk is wall in the window; the ADR amendments of DES-21 (played batches) accepted | Project manager |
| D-134 | Void chunks around every location; chunk corners are wall. SPK-7 measured the chunked map at +720k gas per tick with goblins (+14 %) | Project manager |
| D-131 | The API of `quiver_quest` and `quiver_achievement` accepted | Project manager |
| D-135 | `quiver_quest` bounds what a player holds (4 quests), not what a task reaches: worst call about 5.6M gas instead of 704M | Project manager |
| — | LIB-03 and LIB-04 merged after more than three fix loops, their open findings carried as tasks | Project manager |

Every decision has its file in [docs/decisions/](docs/decisions/) and its row in
[CONTEXT.md](CONTEXT.md) §6.

## Waiting for the owner

**The owner's review of the next iterations of code on the pattern of D-143**: the reference model of ARC-06, then the first lots of ARC-07 and ENG-R1, until nothing is left to say; autonomy after that.

| Open, without urgency | Needed by |
|---|---|
| Q-12: the Arcanist needs a sprite to commission, or the Cleric takes its place in the MVP | Phase 2 |
| The owner's reaction to the lore premise | LORE-01 |
| The business model (Q-10): an active player costs the game about $3.5 to $4.7 a day at today's figures, before batches | Before mainnet |
| Art: the size of goblins on screen (ART-1), the slinger's sprite (ART-2) | CLI-03, ART-01 |

## Risks watched

| Risk | State |
|---|---|
| The cost of an expedition (R-2) | Target $0.50 for 300 actions. Measured with one action per transaction: $0.69 to $0.87. **Estimated on the frozen interfaces, with batches: $0.556 in the worst case**, under the target in the mixed one. The answer turns on ENG-07's measure of a tick inside a batch. Levers listed in [the decision](docs/decisions/2026-09-29-eng-01-escalations.md). A paymaster, needed on a public network, costs 2.2 to 5.1 times the fixed part: for the business model |
| Sessions and agents share one machine and one user with the owner's other programmes | Incident of 2026-09-29, 00:02 UTC: a wildcard deletion in `/tmp` by the game orchestrator; no damage found. Rule in OPERATIONS §3: delete and kill only what you created, by exact path and pid |
| Secrets reach every agent of the machine | The launchers empty them in their agents; the settings file is restricted to its owner; the residual is accepted |
| Audits that need four passes (LIB-03, LIB-04, SPK-2) | Tasks cut smaller; the rule of three loops applied by the project manager |
| The game waits for the library (R-18) | SPK-7 runs on `origami_hexmap` 1.8.0; LIB-05 starts with what the tick needs |
