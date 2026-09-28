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

Expected: the project manager's decision on points 1 to 3, recorded here and in CONTEXT.
