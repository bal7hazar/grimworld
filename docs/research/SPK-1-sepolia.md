# SPK-1 — Latency and cost on Sepolia

Measured on 2026-09-28, between 20:43 and 20:49 UTC, by `[Opus 5.5]`, on Starknet Sepolia
(Starknet 0.14.4, RPC specification 0.10.2). The contracts are SPK-2's native contracts
(`spikes/SPK-2/native/`, unchanged, Cairo 2.19.4, Sierra 1.9.3). The account is the owner's Sepolia
account: class Sierra 1.7.0, compiled with Cairo 2.11.2. Its address is not recorded anywhere
(OPERATIONS §7). The scripts and every raw output are in `spikes/SPK-1/`.

## Summary

| Question | Answer |
|---|---|
| **Latency to pre-confirmed** (ADR-0001: p50 ≤ 1 s, p95 ≤ 3 s) | **p95 is met, p50 is not.** Over the 70 measured transactions: p50 **1,265 ms** (between 1,017 and 1,265 at the polling resolution), p95 **2,774 ms**, max 3,019 ms. The worst tick alone: p50 1,020 ms (between 778 and 1,020), p95 2,770 ms |
| **Latency to accepted on L2** | p50 **3,764 ms**, p95 4,517 ms, max 4,765 ms. Sepolia produced a block about every 1.7 s |
| **Which meter** | **Sierra gas.** On Sepolia, the game's calls cost 0.79× to 0.87× devnet's VM-resource figures for the compute-heavy actions. They come within 2 % to 18 % of snforge's Sierra-gas figures. All of them are non-round figures (§3) |
| **Were the local figures upper bounds?** | **Only for computation.** Queues cost 0.88× to 0.93× devnet's figure and the worst tick 0.995×. The light actions cost more: exploring queue 1.25×, enter 1.15×, leave 1.29×. Under Sierra gas the fixed part of a transaction is heavier than on devnet (§4) |
| **The expedition, on Sepolia's receipts, at today's mainnet prices** | **$0.874** (S1, worst case everywhere) and **$0.685** (S2, mixed), against $0.925 and $0.702 on devnet's receipts at the same prices: **0.95× and 0.98×** |
| **Verdict on $0.50** | **The threshold of $0.50 for 300 actions does not hold on a public network: the expedition costs 1.37× to 1.75× the threshold.** Sepolia's figures are within 5 % of the local ones, so D-129's reversal condition ("Sepolia figures at or above the local ones") is met in substance: the local node was not an upper bound |
| **Fixed part of a transaction** | Everything but the game's call costs **1.34M to 1.62M L2 gas** per transaction (3.00M for `enter`), or 0.72× to 0.87× the equal-allocation reference of 1.85M per action. That is 26 % to 32 % of a worst tick |
| Transactions sent, total cost | **105 transactions, 72.22 test STRK** (the balance went from 305.13 to 232.91). The two declares account for 55.68 STRK of it |

Prices, for all dollar figures: mainnet L2 gas **21,345,234,918 fri**, L1 data gas 980,202,556,584
fri (`api.cartridge.gg`, block 15,594,144, 2026-09-28T20:49:58Z); STRK **$0.04125403** (CoinGecko,
2026-09-28T20:50:07Z). 1M L2 gas = $0.000881.

## 1. What was deployed, and how it was measured

`spikes/SPK-1/sepolia.json`:

| Contract | Class hash | Address |
|---|---|---|
| Hub | `0x5c1cf7384c44b93377f7a9d72ee85a82aa41907c8326976c10ff12c21a64bb4` | `0x98e5e98dd076c62ad0f89c2931d29be06a227a4ef2901b42e33a1bb5015300` |
| Instances | `0x79755c0ea06ff01a3cc50b9d926ec13a035860e7def2279d1100fcac4ab0f09` | `0x408dbc81e3d39ef65ee9393464f2dee3cce13df43f9e65edda07d4c63393a84` |

- **Declares.** Declared with Blake2s compiled class hashes, which starknet.js 10.8.0 uses for
  Starknet 0.14.1 and later.
- **Deploys.** Deployed through the Universal Deployer, with the owner's account as admin.
- **Instances and calls.** The same instance ids, boards and calls as SPK-2's
  `devnet_measure.py`, in production form (owner checked, one felt per goblin):

| Action | Call | SPK-2 instance |
|---|---|---|
| Worst tick under D-127 (capped winding board, 15 layers, 8 goblins reached) | `attack(31, 1, felt, checked)` | 31, board reset by `setup_board` before every tick |
| Queue of 10 moves, 8 goblins following | `walk(18, 10 × West, …)` | 18 |
| Queue of 5 and of 1 move, 8 goblins following | `walk(19, …)`, `walk(20, …)` | 19, 20 (needed by SPK-2's scenarios) |
| Exploring queue: 10 moves, no goblin | `walk(21, …)` | 21 |
| Enter, leave | `Hub.enter(3, 10)`, `Instances.leave(id)` | adventurer 3, alternating |

**How each transaction was sent and timed** (`lib.mjs`, `makeSender`):
- **One at a time.** Each transaction was sent after the previous one was accepted on L2.
- **Before the clock.** The fee was estimated before the clock started. The transaction then went
  out with starknet.js's estimated resource bounds and the recommended tip (0.1 Gfri), as a
  starknet.js client would send it.
- **The clock** starts just before `starknet_addInvokeTransaction`.
- **Polling.** The receipt is polled **every 250 ms on a fixed schedule** from submission. A status
  is timed when the first answer showing it arrives. That time is an upper bound; the arrival of the
  answer before it is the lower bound.
- **Where from.** Everything ran from the VPS. The endpoint answered a submission in 160 ms at the
  median, and that round trip is inside every latency figure.

All 98 transactions of the measured run succeeded. The 20 ticks gave identical receipts
(5,129,938 L2 gas, 832 L1 data gas), and so did the 25 enters and the 25 leaves.

## 2. Latency (AC-1)

`spikes/SPK-1/latency-output.txt`. Percentiles are nearest-rank.

| Set | n | Pre-confirmed p50 | p95 | max | p50 lower bound | Accepted on L2 p50 | p95 | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst tick under D-127 | 20 | 1,020 ms | 2,770 ms | 2,781 ms | 778 ms | 3,529 ms | 4,267 ms | 4,514 ms |
| Cheap action: enter and leave, alternating | 50 | 1,267 ms | 2,774 ms | 3,019 ms | 1,017 ms | 3,765 ms | 4,518 ms | 4,765 ms |
| Both (70) | 70 | **1,265 ms** | **2,774 ms** | 3,019 ms | 1,017 ms | **3,764 ms** | 4,517 ms | 4,765 ms |

Against ADR-0001:
- **p95 ≤ 3 s to pre-confirmed: met** (2,774 ms; its lower bound is 2,519 ms).
- **p50 ≤ 1 s to pre-confirmed: missed** for the 70 (1,017 to 1,265 ms). For the tick alone it is
  at the threshold (778 to 1,020 ms) and cannot be decided at this polling resolution.
- The distribution is wide: 24 of 70 transactions were pre-confirmed within 1 s, 7 took longer than
  2.75 s. The spread follows Sepolia's block rhythm (about 1.7 s), not the action: the worst tick
  is not slower than `leave`.

## 3. Gas, and the meter applied (AC-2)

Every receipt is in `spikes/SPK-1/measure-output.txt`: resource bounds as signed, tip, fee, L2
gas, L1 data gas, L1 gas (0 everywhere), block and its prices. The first transaction of each
action also has its trace.

| Action | n | Sepolia L2 gas | Devnet L2 gas (SPK-2) | Sepolia / devnet | L1 data gas, Sepolia / devnet | Fee paid on Sepolia (STRK) | $ at mainnet prices, Sepolia | $ devnet |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst tick under D-127 | 20 | **5,129,938** | 5,156,800 | 0.995 | 832 / 832 | 0.11074 | 0.00455 | 0.00457 |
| Queue of 10 moves, 8 goblins following | 1 | **17,676,853** | 20,128,000 | 0.878 | 832 / 832 | 0.38051 | 0.01560 | 0.01776 |
| Queue of 5 moves, 8 goblins following | 1 | 10,315,319 | 11,662,400 | 0.884 | 832 / 832 | 0.22223 | 0.00912 | 0.01030 |
| Queue of 1 move, 8 goblins following | 1 | 4,818,251 | 5,201,920 | 0.926 | 768 / 768 | 0.10400 | 0.00427 | 0.00461 |
| Exploring queue: 10 moves, no goblin | 1 | **2,816,505** | 2,248,000 | 1.253 | 320 / 320 | 0.06073 | 0.00249 | 0.00199 |
| Enter | 25 | **3,927,367** | 3,425,280 | 1.147 | 768 / 640 | 0.08428 | 0.00349 | 0.00304 |
| Leave | 25 | **2,030,065** | 1,576,320 | 1.288 | 576 / 576 | 0.04366 | 0.00181 | 0.00141 |

Resource bounds as signed: the worst tick's L2 gas bound was 7,742,926, 1.51× the gas it used, at
up to 32.1 Gfri. The fee is charged on the gas used, at the block's price (21.40 Gfri L2, about 0.53
Tfri L1 data during the run).

**The meter is Sierra gas.** The evidence:

| Action | Sepolia game call | Devnet game call (VM resources) | snforge call (Sierra gas) | Sepolia / devnet | Sepolia / snforge |
|---|---:|---:|---:|---:|---:|
| Worst tick | 3,564,913 | 4,120,000 | 3,342,913 | 0.865 | 1.066 |
| Queue of 10 moves | 16,058,858 | 19,040,000 | 15,737,938 | 0.843 | 1.020 |
| Queue of 5 moves | 8,722,924 | 10,600,000 | 8,432,004 | 0.823 | 1.035 |
| Queue of 1 move | 3,326,336 | 4,200,000 | 3,059,416 | 0.792 | 1.087 |
| Exploring queue | 1,478,510 | 1,320,000 | 1,325,590 | 1.120 | 1.115 |
| Enter | 927,212 | 800,000 | 801,212 | 1.159 | 1.157 |
| Leave | 682,000 | 640,000 | 577,000 | 1.066 | 1.182 |

1. **The figures sit on the Sierra-gas side.** Sepolia's game calls are 2 % to 18 % above
   snforge's Sierra-gas figures. The gap is largest where the call is mostly storage, which is
   consistent with syscalls: snforge's figures exclude them, the chain charges them. The
   compute-heavy calls are 13 % to 21 % below devnet's VM-resource figures.
2. **The figures are not rounded.** Every Sepolia figure has single-gas resolution: 3,564,913 for
   the tick's call, 392,815 for validation, 455,360 for the fee transfer. Devnet's VM-resource
   figures are multiples of 40,000 (SPK-2 §8.2).
3. **The class versions qualify.** The game's classes are Sierra 1.9.3 and the account's is Sierra
   1.7.0. Starknet documents Sierra-gas metering for classes from Sierra 1.7.0 on. That is the
   documentation's rule, not something measured here; points 1 and 2 are the measurement.

## 4. The fixed part of a transaction

Under Sierra gas the receipt is additive. It is the sum of:
- the invocations: validate, the account's `__execute__`, the game's call, the fee transfer;
- the protocol's part: the trace's total minus the invocations, not attributed further here;
- calldata, signature and events: the receipt minus the trace's total.

| Action | Receipt | Validate | Account `__execute__` (without the game call) | Game call | Fee transfer | Protocol part | Calldata, signature, events | **Everything but the game call** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst tick | 5,129,938 | 392,815 | 206,810 | 3,564,913 | 455,360 | 475,840 | 34,200 | **1,565,025** |
| Queue of 10 moves | 17,676,853 | 392,815 | 208,580 | 16,058,858 | 455,360 | 527,040 | 34,200 | 1,617,995 |
| Queue of 5 moves | 10,315,319 | 392,815 | 208,580 | 8,722,924 | 455,360 | 501,440 | 34,200 | 1,592,395 |
| Queue of 1 move | 4,818,251 | 392,815 | 208,580 | 3,326,336 | 455,360 | 400,960 | 34,200 | 1,491,915 |
| Exploring queue | 2,816,505 | 392,815 | 208,580 | 1,478,510 | 455,360 | 247,040 | 34,200 | **1,337,995** |
| Enter | 3,927,367 | 392,815 | 208,580 | 927,212 | 455,360 | 1,913,600 | 29,800 | 3,000,155 |
| Leave | 2,030,065 | 392,815 | 206,810 | 682,000 | 455,360 | 260,480 | 32,600 | 1,348,065 |

- **Fixed in every transaction: about 1.09M L2 gas.** Validation (392,815), the account's own
  execution (about 207,000), the fee transfer (455,360) and calldata (about 34,000) are the same
  in every transaction. They come from the account and the protocol, not from the game. On devnet
  the same three invocations were 320,000, 40,000 and 400,000.
- **The protocol's part grows with the state a transaction touches**: 247,040 for the exploring
  queue (320 L1 data gas) and 527,040 for the queue of 10 (832). `enter` is the only action that
  writes new storage keys (a new instance), and there it reaches 1,913,600. That it is a charge on
  new storage keys is an inference from this one case, not a measurement.
- **For ENG-01's cost constraint (D-129 #3):** a transaction costs **at least 1.34M L2 gas**
  before the game's call, about $0.0012 at today's prices. That is **0.72× the equal-allocation
  reference** ($0.50 / 300 = 1,854,492 L2 gas per action). So one transaction per action cannot
  reach the threshold unless the game's part of an average transaction stays under about 0.5M.
  The worst tick's game call is 3.56M.

## 5. Money (AC-3)

`spikes/SPK-1/money-output.txt`. The method is SPK-2's (`money_devnet.py`):
- **The expedition.** 180 moves in queues, 100 fights of one transaction each, 20 other actions,
  enter and leave. Every fight is the worst tick under D-127.
- **Break-even.** The L2 gas price at which the expedition costs $0.50, with the
  data-availability dollars held.
- **Fight budget.** The fight's L2 gas at which the expedition costs $0.50, everything else as
  measured.

The same prices are applied to both sides.

| Scenario | Transactions | **$ Sepolia** | $ devnet (SPK-2) | Sepolia / devnet | × $0.50 | Break-even L2 gas price, Sepolia | L2 gas per expedition, Sepolia | Fight budget, Sepolia |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| S1 worst case everywhere | 158 | **0.874** | 0.925 | 0.945 | **1.75** | 12.15 Gfri | 986,667,736 | 881,724 |
| S2 mixed (2/3 of the moves exploring) | 146 | **0.685** | 0.702 | 0.976 | **1.37** | 15.54 Gfri | 772,898,140 | 3,026,827 |

**Verdict: on Sepolia's receipts, a 300-action expedition costs $0.69 to $0.87 at today's mainnet
prices, 1.37× to 1.75× the $0.50 threshold. The threshold does not hold.** The public network
confirms the local node's figures (0.95× to 0.98×); it does not lower them.
- **The routes that remain:**
  - an L2 gas price at or below 12.2 to 15.5 Gfri (today 21.3; 19.6 to 30.8 over the last two
    weeks, `prices-output.txt`);
  - a fight at or below 0.88M L2 gas for S1. That is below the 1.57M a transaction costs besides
    its game call, so S1 cannot pass by cheaper fights alone;
  - a fight at or below 3.03M for S2, 0.59× today's.
- **Not measured on Sepolia**, because they are outside the brief's list:
  - goblins packed per instance (SPK-2's S3, S4);
  - the serpentine queue (S5);
  - hub actions, so no cost per active player per day. On devnet, packing moved the tick by 2 %
    (SPK-2 §9.2).

## 6. What Sepolia says about mainnet, and what it cannot

**What it says:**
- **Same protocol generation.** Sepolia runs Starknet 0.14.4, mainnet 0.14.3 at the time of
  reading. Both meter these classes the same way under the published rule, and the fee formula
  is the same.
- **The same gas in any network.** L2 gas and L1 data gas used are properties of the transaction
  and the protocol version, not of the network's prices. Mainnet should charge the same gas
  within the differences between 0.14.3 and 0.14.4.
- **Similar L2 gas prices** today: Sepolia 21.26 Gfri, mainnet 21.35 Gfri.
- **The same money.** Every dollar figure above is Sepolia's gas × mainnet's prices.

**What it cannot say:**
- **Mainnet's data price.** It moved from 0.03 to 1.67 Tfri over the fortnight
  (`prices-output.txt`). Data availability is under 1 % of these transactions at today's price
  (0.98 Tfri). It would reach a tenth of the worst tick's cost only at about 15 Tfri.
- **Latency on mainnet, and under load.** Mainnet's block rhythm, its load, and a transaction
  queued behind another of the same player are not measured here. The transactions here went out
  one at a time, each after the previous one was accepted. A player acting faster than a block
  would pipeline nonces; that is not measured.
- **Latency from a player's device.** The figures include the round trip from the VPS to one RPC
  endpoint: 160 ms to answer a submission. A browser elsewhere, or another provider, shifts them.
- **The MVP's burner.** ADR-0005 stage A's burner is an account deployed by the game with a key on
  the device. This spike used the owner's account (Sierra 1.7.0, Cairo 2.11.2). Validation (0.39M)
  and the account's own execution (0.21M) depend on the account class, so a different burner
  class changes the fixed part.
- **A paymaster.** Out of scope (SPK-9); it adds its own calls.
- **The real game.** Line of sight, skills, conditions and the real storage layout are not in
  SPK-2's contracts.

## 7. Transactions sent and their cost (AC-4)

| Step | Transactions | Fee (test STRK) |
|---|---:|---:|
| Declare Hub and Instances (0.78G and 1.82G L2 gas), deploy both | 4 | 55.7800 |
| Link the contracts, set up the hub | 3 | 0.1670 |
| Setups: 4 queues, 20 board resets | 24 | 10.0951 |
| Measured: 4 queues, 20 worst ticks, 25 enter, 25 leave | 74 | 6.1781 |
| **Total** | **105** | **72.2203** |

- **Planned before sending**, with a hard cap in the code: 7 for the deployment and 98 for the
  measurement. No transaction was repeated or retried.
- **The first deployment run stopped** after sending the Hub declare, on a script error. The second
  run found that declare on chain and counted it. It sent nothing twice.
- **Every sending script asked the RPC for its chain id first** (`requireSepolia()`, `lib.mjs`), and
  every request carried a usual `User-Agent`.
- **No value of the four variables** is in the branch's history, the spike folder, this file or the
  report: `python3 spikes/SPK-1/check_secrets.py` reports 0 occurrences. It checks the account
  address, the key and the endpoint, without printing any of them. One line of
  `prices-output.txt` named the endpoint (SPK-2's `prices.py` reads public endpoints) and was
  redacted.

## 8. Open questions

1. **p50 to pre-confirmed.** It is 1.02 to 1.27 s from the VPS. Decide whether ADR-0001's 1 s
   target is measured at the RPC or at the player, and whether Sepolia's block rhythm stands for
   mainnet's. The next step would be finer polling, or a pre-confirmation subscription (WebSocket),
   to narrow the bound.
2. **The fixed part.** It is 1.34M L2 gas per transaction with this account class. SPK-9 (paymaster,
   burner class) should measure it for the MVP's account: 0.6M of it is validation and
   `__execute__`.
3. **New storage keys.** `enter`'s protocol part is 1.91M against 0.25M to 0.53M elsewhere. If new
   keys are charged, ENG-01's layout should reuse keys (instance slots) rather than allocate them.
