# The cost of an expedition against the threshold of ADR-0001 — decided 2026-09-28 (D-129)

| | |
|---|---|
| Prepared by | `[Fable 5.1]` project manager, 2026-09-28 |
| Decides | The owner: it is what the game pays for every player (pillar 7, Q-10) |
| Source | `docs/research/SPK-2-cost.md` (summary, §9), `[Opus 5.5]`; audit `[GPT-6-Astra]`, PASS WITH FINDINGS after three fix loops (`docs/reports/SPK-2-audit-gpt-6-astra.md`) |
| Blocks | Nothing in Phase 0. ENG-01 (storage layout, events) and FND-04 (budgets) depend on it |

## 1. What is measured

On a local node (starknet-devnet 0.10.0), through an account compiled with Cairo 2.19, the
flood stopped at 15 layers (D-127). Prices read on mainnet on 2026-09-28 at 19:30 UTC: L2
gas 21.7 Gfri, STRK $0.0406.

| | Dojo 1.8 | Native | |
|---|---|---|---|
| The game's worst tick, as a transaction | 18.94M L2 gas | **5.16M** | Native is 0.27× |
| Every action measured | — | — | Native is **0.26× to 0.58×** Dojo, like for like |
| An expedition of 300 actions | $1.21 to $2.83 | **$0.69 to $0.93** | The threshold is $0.50: **1.38× to 1.86×** |
| An active player, per day | — | **$3.48 to $4.66** | 5 Rifts, quests, hub actions |

**The decision to leave Dojo (D-123) is confirmed by measurement.** The threshold is not met.

## 2. Where the gas goes

| Action | L2 gas per action |
|---|---|
| A move alone, 8 goblins following | 5.20M |
| The same move in a queue of 10 | 2.01M |
| An exploring move in a queue of 10, no goblin | 0.22M |
| A fight | 5.16M |
| The rules of a tick, in memory | about 1.6M |

**A transaction costs about 3.5M before the game computes anything** (account, fee transfer,
reads and writes of the instance and of the goblins). The tick itself is a third of a fight.
A cheaper flood alone cannot reach the threshold: in the worst scenario even a free tick
leaves $0.49.

## 3. What these figures are not

| | |
|---|---|
| Not mainnet | The local node meters by VM resources. Mainnet meters these contracts in Sierra gas: the native figures are **probably upper bounds**. Not verified |
| Not the real account | A burner through a paymaster costs differently from the test account |
| Not the whole game | Line of sight, skills, conditions and the real storage layout are not in the spike |
| Not the library | The flood is the spike's own; the map library's is measured by SPK-7 and LIB-05 |

## 4. Options

| | Option | What it takes | Project manager |
|---|---|---|---|
| **(c)** | **Measure on Sepolia before deciding** | The Sepolia credentials in the orchestrator's environment now, not at Phase 1; SPK-1 brought forward and extended to the worst tick | **Recommended first**: the decision should not rest on a figure we believe is an upper bound |
| **(a)** | **Make the transaction cheaper**, as a constraint on ENG-01 | One write per instance and per tick (goblins packed together: measured, 5.04M against 5.16M, so the gain is elsewhere); fewer reads; the fixed part of a transaction studied with the account provider | **Recommended in parallel**: it is engineering we do anyway (docs/CAIRO.md §5) |
| (e) | More actions per transaction in a fight | A change of design: today the queue stops when the adventurer takes damage or a goblin acts (design/02). A queue of 10 moves costs 2.0M per move against 5.2M alone | To study only if (c) and (a) are not enough: it touches what the player decides |
| (b) | Wait for a lower gas price | 11.6 to 15.6 Gfri needed; 17.9 to 30.5 over the last two weeks | Not a plan |
| (d) | Restate the threshold | $0.50 for 300 actions was a proposal of ADR-0001, not a figure of the business model (Q-10, not written) | **To decide with the business model**, on the Sepolia figures |
| B | An L3 (ADR-0001, option B) | A chain to run; the hosted offer examined was retired | Not recommended |

## 5. Recommendation

1. **Keep the threshold as the target for now, and decide nothing on the local figures.**
2. **Bring the Sepolia measurement forward** (c): it needs the owner to provide the Sepolia
   credentials.
3. **Give ENG-01 a cost constraint** (a): the fixed part of a transaction and the writes per
   tick are budgeted before the storage layout is frozen.
4. **When the Sepolia figures are in**, decide between a restated threshold and a change of
   the queue, with the cost per active player per day in front of the business model.

## Answer

Decided by the project manager on 2026-09-28, under the owner's rule of the same day (D-128:
the project manager goes ahead with its own recommendations). The owner agreed to a
measurement on Sepolia.

| # | Decision (D-129) |
|---|---|
| 1 | **The threshold of $0.50 for 300 actions stays the target.** Nothing is decided on the figures of the local node |
| 2 | **SPK-1 is brought forward and extended**: besides latency it measures, on Sepolia, the worst tick, a queue of 10 moves, an exploring queue, enter and leave, as native contracts, from the account the MVP will use. It gives the expedition's cost on a public network |
| 3 | **ENG-01 carries a cost constraint**: a budget for the fixed part of a transaction and for the reads and writes of a tick, set from SPK-2 and SPK-1, before the storage layout is frozen |
| 4 | **When the Sepolia figures are in**, the project manager decides between a restated threshold and a change of the queue in fights, and reports. The cost of an active player per day is written in front of the business model (Q-10), which is the owner's |
| 5 | Waiting for a lower gas price and an L3 are not pursued |

What would reverse it: Sepolia figures at or above the local ones. Then the fixed part of a
transaction is the problem, and the queue in fights (design/02) is reopened first.

**Blocked on 2026-09-28**: the Sepolia credentials are not in the environment. The only
variable defined in `~/.claude/settings.json` on the VPS is the registry token; no file of
settings on the machine names a Sepolia account or key (names checked, no value read).
