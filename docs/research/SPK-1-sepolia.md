# SPK-1 — Latency and cost on Sepolia

Measured on 2026-09-28, between 20:43 and 20:49 UTC, by `[Opus 5.5]`, on Starknet Sepolia
(Starknet 0.14.4, RPC specification 0.10.2). The contracts are SPK-2's native contracts
(`spikes/SPK-2/native/`, unchanged, Cairo 2.19.4, Sierra 1.9.3). The account is the owner's Sepolia
account: class Sierra 1.7.0, compiled with Cairo 2.11.2. Its address is not recorded anywhere
(OPERATIONS §7). The scripts and every raw output are in `spikes/SPK-1/`.

## Summary

| Question | Answer |
|---|---|
| **Latency to pre-confirmed** (ADR-0001: p50 ≤ 1 s, p95 ≤ 3 s), measured as the **first positive receipt response** | **p95 is met; p50 is not decided by this sampling.** Over the 70 measured transactions: p50 **1,265 ms**, p95 **2,774 ms**, max 3,019 ms. The worst tick alone: p50 1,020 ms, p95 2,770 ms. These are upper bounds on when the RPC first reported the status. No valid lower bound was recorded, and both p50 figures sit within the sampling uncertainty of 1 s (one 250 ms poll interval plus a round trip of about 160 ms, §2) |
| **Latency to accepted on L2** (first positive receipt response) | p50 **3,764 ms**, p95 4,517 ms, max 4,765 ms. Sepolia produced a block about every 1.7 s |
| **Which meter** | **Sierra gas.** On Sepolia, the game's calls cost 0.79× to 0.87× devnet's VM-resource figures for the compute-heavy actions. They come within 2 % to 18 % of snforge's Sierra-gas figures. All of them are non-round figures (§3) |
| **Were the local figures upper bounds?** | **The evidence is mixed.** Sepolia is slightly below the local node on the heavy actions: queues 0.88× to 0.93×, the worst tick 0.995×. It is above on the light ones: exploring queue 1.25×, enter 1.15×, leave 1.29×. Under Sierra gas, the non-game remainder of a transaction is heavier than on devnet (§4) |
| **The expedition, on Sepolia's receipts, at today's mainnet prices, zero tip** | **$0.874** (S1, worst case everywhere) and **$0.685** (S2, mixed), against $0.925 and $0.702 on devnet's receipts at the same prices: **0.945× and 0.976×**. The tip this run paid (0.1 Gfri) would add $0.0041 and $0.0032 (§5) |
| **Verdict on $0.50** | **The threshold of $0.50 for 300 actions does not hold on a public network: the expedition costs 1.37× to 1.75× the threshold.** On D-129's reversal condition ("Sepolia figures at or above the local ones"): the condition is **not met**. The expeditions (0.945×, 0.976×) and the worst tick (0.995×) are slightly below the local figures; enter, leave and the exploring queue are above. That mixed evidence is for the project manager to weigh (§5) |
| **Non-game remainder of a transaction** | For these actions and this account, the receipt minus the game's call was **1.34M to 1.62M L2 gas** (3.00M for `enter`). That is 0.72× to 0.87× the equal-allocation reference of 1.85M per action, and 26 % to 32 % of a worst tick. It is an observed remainder, not a universal floor (§4) |
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
  is timed when the first receipt response showing it arrives: the **first positive receipt
  response** latency. That is an upper bound on when the RPC first reported the status. The run
  recorded no valid lower bound. It kept the arrival of the previous, negative response, but the
  RPC evaluated that response at an unknown moment inside its own request (fix loop 1).
- **Where from.** Everything ran from the VPS. The endpoint answered a submission in 160 ms at the
  median, and that round trip is inside every latency figure.

All 98 transactions of the measured run succeeded. The 20 ticks gave identical receipts
(5,129,938 L2 gas, 832 L1 data gas), and so did the 25 enters and the 25 leaves.

## 2. Latency (AC-1)

`spikes/SPK-1/latency-output.txt`. First positive receipt response latency, from the submission.
Percentiles are nearest-rank.

| Set | n | Pre-confirmed p50 | p95 | max | Accepted on L2 p50 | p95 | max |
|---|---:|---:|---:|---:|---:|---:|---:|
| Worst tick under D-127 | 20 | 1,020 ms | 2,770 ms | 2,781 ms | 3,529 ms | 4,267 ms | 4,514 ms |
| Cheap action: enter and leave, alternating | 50 | 1,267 ms | 2,774 ms | 3,019 ms | 3,765 ms | 4,518 ms | 4,765 ms |
| Both (70) | 70 | **1,265 ms** | **2,774 ms** | 3,019 ms | **3,764 ms** | 4,517 ms | 4,765 ms |

Against ADR-0001, read as upper bounds. A figure within about 410 ms above a threshold (one poll
interval plus the median round trip) is not decided by this sampling:
- **p95 ≤ 3 s to pre-confirmed: met.** The observed 2,774 ms is an upper bound, and it is within
  3 s.
- **p50 ≤ 1 s to pre-confirmed: not decided.** The observed p50 is 1,265 ms for the 70 and
  1,267 ms for enter and leave, 265 ms above the threshold. For the tick it is 1,020 ms, 20 ms
  above. The true moments lie earlier by an unknown amount, up to about one poll interval plus a
  round trip. This run can call none of these a pass or a miss.
- **What a later run must record** (`lib.mjs` does so since fix loop 1): for every poll, the
  request start, the response arrival and the status reported. The status then became true after
  the last negative request's start and before the first positive response's arrival, which is a
  valid interval. A finer poll interval, or a pre-confirmation subscription, narrows it.
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

## 4. The non-game remainder of a transaction

Under Sierra gas the receipt is additive. The trace attributes the invocations: validate, the
account's `__execute__`, the game's call and the fee transfer. Two residuals are **unattributed**:
- the trace's total minus the invocations;
- the receipt minus the trace's total. Calldata, signature and events are the expected content;
  that is not verified.

The last column, the receipt minus the game's call, is the **observed non-game remainder for these
actions and this account** (class Sierra 1.7.0, Cairo 2.11.2). It is not a universal floor.

| Action | Receipt | Validate | Account `__execute__` (without the game call) | Game call | Fee transfer | Unattributed residual: trace total minus invocations | Unattributed residual: receipt minus trace total | **Non-game remainder** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst tick | 5,129,938 | 392,815 | 206,810 | 3,564,913 | 455,360 | 475,840 | 34,200 | **1,565,025** |
| Queue of 10 moves | 17,676,853 | 392,815 | 208,580 | 16,058,858 | 455,360 | 527,040 | 34,200 | 1,617,995 |
| Queue of 5 moves | 10,315,319 | 392,815 | 208,580 | 8,722,924 | 455,360 | 501,440 | 34,200 | 1,592,395 |
| Queue of 1 move | 4,818,251 | 392,815 | 208,580 | 3,326,336 | 455,360 | 400,960 | 34,200 | 1,491,915 |
| Exploring queue | 2,816,505 | 392,815 | 208,580 | 1,478,510 | 455,360 | 247,040 | 34,200 | **1,337,995** |
| Enter | 3,927,367 | 392,815 | 208,580 | 927,212 | 455,360 | 1,913,600 | 29,800 | 3,000,155 |
| Leave | 2,030,065 | 392,815 | 206,810 | 682,000 | 455,360 | 260,480 | 32,600 | 1,348,065 |

- **The same in every transaction measured here: about 1.09M L2 gas.** Validation (392,815), the
  account's own execution (about 207,000), the fee transfer (455,360) and the second residual
  (29,800 to 34,200) barely moved between these actions. The first three depend on the account
  class and the fee token, not on the game. On devnet the same three invocations were 320,000,
  40,000 and 400,000.
- **The first unattributed residual grows with the state a transaction touches**: 247,040 for the
  exploring queue (320 L1 data gas) and 527,040 for the queue of 10 (832). `enter` is the only
  action that writes new storage keys (a new instance), and there it reaches 1,913,600. That it is
  a charge on new storage keys is an inference from this one case, not a measurement.
- **For ENG-01's cost constraint (D-129 #3):** the smallest observed non-game remainder is
  **1,337,995 L2 gas**, about $0.0012 at today's prices. It is 0.72× the equal-allocation
  reference ($0.50 / 300 = 1,854,492 L2 gas per action). If every transaction carried at least that
  remainder, the game's own call could average at most about **0.52M** under equal allocation. The
  worst tick's game call is 3.56M. That derived budget holds for this account class and
  transactions like these only; a burner class, a paymaster, other calldata or another state diff
  change the remainder.

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
prices with zero tip, 1.37× to 1.75× the $0.50 threshold. The threshold does not hold.**

**Against D-129's reversal condition** ("Sepolia figures at or above the local ones"): **not met.**
The evidence is mixed, and weighing it is for the project manager:
- **Below the local figures:** the expeditions, slightly (S1 0.945×, S2 0.976×), the worst tick
  (0.995×) and the queues near goblins (0.88× to 0.93×).
- **Above them:** the light actions, exploring queue 1.25×, enter 1.15×, leave 1.29×. Their
  non-game remainder is heavier under Sierra gas.
- **So** the local node overstated computation and understated the transaction's non-game
  remainder. On these expeditions the two nearly cancel.

**The tip.** The fee charged is L2 gas × (block L2 gas price + tip) + L1 data gas × block data
price + L1 gas × block L1 price. This formula reproduces the fee to the fri on all 103 invoke
receipts. The dollar projections above assume a **zero tip**. At the tip this run paid (0.1 Gfri,
starknet.js's recommendation), S1 costs **+$0.0041** ($0.878) and S2 **+$0.0032** ($0.688).
- **The routes that remain:**
  - an L2 gas price at or below 12.2 to 15.5 Gfri (today 21.3; 19.6 to 30.8 over the last two
    weeks, `prices-output.txt`);
  - a fight at or below 0.88M L2 gas for S1. That is below the tick's observed non-game remainder
    (1.57M), so S1 cannot pass by cheaper fights alone with this account;
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
  class changes the non-game remainder.
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
- **The secret scan.** At the time of measurement, `check_secrets.py` found 0 occurrences of
  the three values in `git log -p origin/main..HEAD`, the spike folder, this file and the report.
  One line of `prices-output.txt` had named the endpoint (SPK-2's `prices.py` polls public
  endpoints) and was redacted by hand before it was committed.
- **Fix loop 1** (run without the account: nothing was sent and the scan could not be re-run with
  the real values):
  - the configuration is validated with value-free errors before anything can echo it;
  - price collection goes through `redacted.py`, which redacts before writing;
  - the scan now covers `git log -p --all`, fails on a git error, and requires the agent's log and
    the report. It prints its coverage and does not scan binary file contents.
  - `test_redaction.py` shows all of this with synthetic values.
- **Expected when the scan is re-run.** Over `--all`, it should report the endpoint's value in
  SPK-2's files on `main`, where it is one of the public endpoints listed there. It is not in any
  SPK-1 commit.

## 8. Open questions

1. **p50 to pre-confirmed.** The first positive receipt response came at 1.02 to 1.27 s at the
   median from the VPS, which does not decide the 1 s target at this sampling. A later run should
   record [request start, response arrival, status] per poll (now in `lib.mjs`) and poll more
   finely, or subscribe to pre-confirmations. Also to decide: is ADR-0001's target measured at the
   RPC or at the player, and does Sepolia's block rhythm stand for mainnet's?
2. **The non-game remainder.** The smallest observed is 1.34M L2 gas per transaction with this
   account class. SPK-9 (paymaster,
   burner class) should measure it for the MVP's account: 0.6M of it is validation and
   `__execute__`.
3. **New storage keys.** `enter`'s first unattributed residual is 1.91M against 0.25M to 0.53M elsewhere. If new
   keys are charged, ENG-01's layout should reuse keys (instance slots) rather than allocate them.
