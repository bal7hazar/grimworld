# The cost threshold on Sepolia's figures (D-129, point 4)

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from SPK-1 ([research](../research/SPK-1-sepolia.md), [report](../reports/SPK-1-sepolia.md), audit `[GPT-6-Astra]` PASS WITH FINDINGS, [#45](https://github.com/bal7hazar/grimworld/pull/45)) |
| To be answered by | `[Fable 5.1]` project manager (D-129 point 4, D-128) |
| Needed by | ENG-01 (its cost constraint), the design of fights (design/02), FND-04 |

## What Sepolia measured

| | Sepolia | Local node (SPK-2) |
|---|---:|---:|
| Expedition S1, worst case everywhere, today's mainnet prices, zero tip | **$0.874** | $0.925 |
| Expedition S2, mixed | **$0.685** | $0.702 |
| Worst tick under D-127, L2 gas | 5,129,938 | 5,156,800 |
| Break-even L2 gas price (S1 / S2) | 12.2 / 15.5 Gfri | — |
| Today's mainnet L2 gas price | 21.3 Gfri (19.6 to 30.8 over two weeks) | |

- **The $0.50 threshold does not hold** (1.37× to 1.75×).
- **D-129's reversal condition is not met to the letter**: Sepolia is slightly *below* the local
  figures on expeditions (0.945×, 0.976×) and above them on light actions (1.15× to 1.29×).
- **But its premise is**: about **1.09M L2 gas of every transaction is not the game's** (validation
  392,815, the account's execution about 207,000, the fee transfer 455,360, a residual about
  32,000), and the non-game remainder of a fight's tick is 1.57M. S1's whole budget for a fight
  is 0.88M. **No optimisation of the game's code can bring S1 under $0.50 at today's prices with
  one action per transaction and this account.**
- Latency: p95 to pre-confirmed 2.8 s, within ADR-0001's 3 s; p50 (1.27 s observed) not decided
  by this sampling.

## The routes

| Route | What it acts on | Cost |
|---|---|---|
| (e) Fewer transactions in fights: the queue does not stop at every damage or goblin action (design/02) | Divides the 1.09M per transaction; a queue of 10 moves cost 1.77M per move against 4.82M alone | A change of what the player decides; design work |
| (g) A cheaper account path: the MVP's burner class and a paymaster (a narrow part of SPK-9, which is planned before version 1) | The 0.6M of validation and execution, and the fee transfer | A measurement; does not touch the design |
| ENG-01 under its cost constraint (D-129) | The game's own part, and `enter`'s 1.9M of new storage (reuse instance slots) | Already planned |
| (d) Restate the threshold | Nothing technical | Needs the business model (Q-10, the owner's) and a cost per active player per day, which needs the hub actions measured |

## Recommendation

1. **Reopen the queue in fights now (e)**, as D-129 said to do when the fixed part of a transaction
   is the problem: it is, by the measurement, even though the literal condition is not met. A
   design task (DES) in Phase 0, before ENG-01 freezes the interfaces, since the queue shapes the
   entrypoints.
2. **Add SPK-1b in Phase 0 (g)**, a measurement only, not SPK-9: the fixed part of a transaction
   with the burner class the MVP will use, with and without a paymaster, on Sepolia under SPK-1's
   rules (a few tens of transactions). It sizes the part (e) cannot remove.
3. **Do not restate the threshold yet (d)**: keep $0.50 as the target until (e) and (g) are in and
   the owner has the business model; then the cost of an active player per day goes in front of
   Q-10.
4. ENG-01 keeps D-129's constraint, with `enter`'s new-storage cost as an explicit item.

## Decision

By the project manager on 2026-09-28, under D-128; reported to the owner.

| # | Decision (D-133) |
|---|---|
| 1 | **Fights are played on the client and sent in batches.** The design task DES-21 writes the rule in design/02 before ENG-01 freezes the entrypoints |
| 2 | **SPK-1b is added to Phase 0**: the fixed part of a transaction with the burner class of the MVP, with and without a paymaster, on Sepolia, a few tens of transactions |
| 3 | **The threshold of $0.50 for 300 actions stays the target.** It is restated, if it must be, with the owner's business model and the cost of an active player per day |
| 4 | ENG-01 keeps its cost budget, with the new storage of `enter` as an item of its own |

### What point 1 means, and what it does not change

Two things were one in design/02, and are now told apart:

| | A **planned** queue | A **played** batch |
|---|---|---|
| What it is | Actions chosen in advance, without seeing what happens in between: a path of ten steps | Actions the player chose **one by one**, each on the result of the previous one, which the client computed |
| Why the client can compute it | — | Tactics are deterministic (D-40): the client runs the same rules as the chain and shows the exact result at once |
| When it is sent | At once | In the background, several actions together; the chain follows the player (ADR-0001, point 3 of its decision) |
| Stop conditions of design/02 | **Kept**: the queue stops when the adventurer takes damage, a goblin notices, a chunk is revealed | **None but validity**: the contract executes the whole batch; an invalid action drops the rest |

| Unchanged | |
|---|---|
| What the player decides | Every action, seeing the result of the one before. Nothing is played for the player |
| What the chain decides | Everything: it executes the same actions and its result is the truth; on a difference the client rewinds |
| Fate | An action that draws (loot, chest, identification, the entry draw) ends a batch and is sent alone (ADR-0002, rule 3) |

| To be settled by DES-21 | First answer |
|---|---|
| Size of a batch | Bounded by gas, 10 actions to start with |
| When a batch leaves | When it is full, before a Fate action, after a few seconds without input, when the app goes to the background |
| Actions played and not yet sent when the app closes | Kept on the device and sent at the next launch; lost if the device is lost, as a burner is |
| Can a player take back an action that is not sent yet? | No in our client (I-5). A modified client can already compute any sequence in advance, since the rules and the state are public: nothing is given away |
| A reorg or a difference | The client rewinds further than before: up to a batch |

### Why this and not a cheaper tick

About 1.09M L2 gas of every transaction is the account and the protocol. The whole budget
of a fight in the worst expedition is 0.88M. With one action per transaction no optimisation
of the game reaches $0.50. In a queue of 10 the same move costs 1.77M instead of 4.82M: at
that figure the worst expedition is about at the threshold, before ENG-01 has optimised
anything.

### What would reverse it

SPK-1b showing a fixed part several times smaller with the MVP's account; or a playtest in
which sending by batch makes the game feel wrong (a rewind of several actions seen by
players). Then the queue goes back to one action per transaction in fights and the threshold
is restated.


## After SPK-1b (2026-09-29): what the account costs (D-137)

Measured on Sepolia by SPK-1b (`docs/reports/SPK-1b-audit-gpt-6-astra.md`, `[GPT-6-Astra]`,
passed after four fix loops).

| The fixed part of a transaction | L2 gas | Against the burner sending directly |
|---|---:|---:|
| The burner class of the MVP, sending directly | 717,435 | 1 |
| The owner's account (SPK-1) | 1,087,585 | 1.52 |
| The burner through a relayer of our own | 1,587,885 | 2.2 |
| The burner through a public paymaster, default mode | 3,654,080 | 5.1 |

| An expedition of 300 actions, today's prices | One action per transaction (measured) | Batches of 10 and the burner (estimate) |
|---|---:|---:|
| Worst case everywhere | $0.874 | about $0.73 |
| Mixed | $0.685 | about $0.54 |

The storage slots that a batch changes once are not counted in the estimate (ENG-01). The
two spikes spent 76.19 test STRK over 149 transactions.

| # | Decision (D-137) |
|---|---|
| 1 | **In the MVP a burner sends directly and the game funds it**: it is the cheapest path measured, and the MVP runs on test networks where the fee token has no value |
| 2 | **A paymaster is not used before version 1.** It multiplies the fixed part of every transaction by 2.2 to 5.1. It is what a public network needs (a burner that holds the fee token can send it elsewhere; the player must never hold it, ADR-0005 A-3), so its cost belongs to the business model and to SPK-9 |
| 3 | D-133 stands: the burner's gain does not replace the batches. The target of $0.50 is within reach of the mixed expedition and not yet of the worst one; ENG-01's count of changed slots decides the rest |

What would reverse 1: a test network whose token takes a value, or a playtest opened to
strangers, where a funded burner can be emptied by its holder.
