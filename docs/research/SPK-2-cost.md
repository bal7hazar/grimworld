# SPK-2 — Cost of the heaviest ordinary actions

Measured on 2026-09-28 on the VPS by `[Opus 5.5]`, with the SPK-5 pins (Cairo/Scarb 2.13.1,
snforge 0.51.2, sozo 1.8.7, Katana 1.7.1, `dojo` 1.8.0). Everything below comes from the throwaway
world in `spikes/SPK-2/`; the raw outputs are committed next to it and quoted here.

Sections 1 to 6 are **part 1, the Dojo baseline**, kept as they were. **Part 2** (§7, the same
worst cases as native Starknet contracts on Cairo 2.19, ADR-0007) is at the end. Part 1's
commands now run with its own pins: `spikes/SPK-2/test.sh` and
`spikes/SPK-2/with-katana.sh bash run.sh` (see `spikes/SPK-2/README.md`).

> **Fix loop 1 (§8) supersedes the comparisons and verdicts of §3 and §7.** After the
> `[GPT-6-Astra]` cost audit, both sides were measured again on **one node and one account**
> (starknet-devnet 0.10.0, an OpenZeppelin account compiled with Cairo 2.19), with **equal
> goblin storage and equal checks**, adversarial flood cases and the corrected break-even formula.
> §§1–7 stay as the record of what was measured before; where a figure differs, §8's is the one
> to use. **Fix loop 2 (§9) implements D-127** (the tick's flood stops at 15 layers) on both
> sides and supersedes §8's scenarios and verdict: every fight is now the capped worst case.

## Summary — does ADR-0001's threshold hold for the native contracts?

**No, not at today's prices.** Measured on starknet-devnet 0.10.0 through an account compiled with
Cairo 2.19, with the tick's flood stopped at 15 layers (D-127), a 300-action expedition on the
native contracts in production form costs **$0.69 to $0.93**. The threshold is **$0.50**, so that is
**1.38× to 1.86×**. The same expedition on Dojo costs $1.21 to $2.83. Prices: mainnet L2 gas
21,687,750,610 fri and L1 data gas 1,544,531,203,854 fri (block 15,591,320, 2026-09-28T19:30Z);
STRK $0.04061 (CoinGecko, 19:30:18Z).

**Equal-allocation reference** (not a budget for any one action): $0.50 / 300 = **$0.001667 per
action**, which is **1,833,096 L2 gas per action** at those prices, with 832 L1 data gas (DA) per
action included. Each measured native action, per player action, against that reference:

| Native action (owner checked) | L2 gas per action | $ per action | × the equal-allocation reference |
|---|---:|---:|---:|
| Fight: the game's worst tick under D-127 (15 layers, 8 goblins reached) | 5,156,800 | 0.004594 | **2.76** |
| Fight, goblins packed per instance | 5,036,800 | 0.004488 | 2.69 |
| Fight on part 1's fixture (12 layers) | 4,996,800 | 0.004453 | 2.67 |
| Move in a queue of 10, 8 goblins following | 2,012,800 | 0.001778 | 1.07 |
| Move in a queue of 5, 8 goblins following | 2,332,480 | 0.002065 | 1.24 |
| Move alone (queue of 1), 8 goblins following | 5,201,920 | 0.004630 | 2.78 |
| Exploring move (queue of 10, no goblin) | 224,800 | 0.000200 | **0.12** |
| Move in a queue of 10 on the serpentine (capped) | 1,356,800 | 0.001197 | 0.72 |
| Enter / leave | 3,425,280 / 1,576,320 | 0.003057 / 0.001424 | 1.83 / 0.85 |
| Brew (new pair), accept quest, claim quest | 2,485,920 / 1,473,680 / 1,713,680 | 0.002222 / 0.001314 / 0.001533 | 1.33 / 0.79 / 0.92 |

Exploration is well under the reference, moves near goblins are at or just over it, and fights are
2.7× to 2.8× over it. The expedition average is $0.0023 to $0.0031 per action (1.38× to 1.86×).

**The reference is not what a fight must cost.** Fights at 1,833,096 L2 gas, everything else as
measured, still leave S1 at **$0.635** and S4 at **$0.631**. What a fight would have to cost for each
scenario to reach $0.50 exactly, every other transaction and every DA as measured (fix loop 3,
C-6):

| Scenario (§9.3) | Fights per expedition | Measured fight | **Fight budget** | Share of today's fight |
|---|---:|---:|---:|---:|
| S1 worst case everywhere | 100 | 5,156,800 | **295,792** | 5.7 % |
| S2 mixed (2/3 of the moves exploring) | 100 | 5,156,800 | **2,836,494** | 55 % |
| S3 mixed, goblins packed | 100 | 5,036,800 | **2,862,094** | 57 % |
| S4 worst case everywhere, goblins packed | 100 | 5,036,800 | **340,592** | 6.8 % |
| S5 serpentine queues (capped; 120 fight-priced transactions) | 120 | 5,156,800 | **2,589,914** | 50 % |

A cheaper tick would also cheapen the queued moves: each carries a tick. So the **correlated
case** is modelled too. The tick's part of a transaction is taken as the slope of the queues with
8 goblins: 1,659,874 L2 gas per move, least squares on 1, 5 and 10 moves. It is scaled by the same
factor *r* in every fight and every queued move near goblins, with the rest kept. The model is
linear over receipts, which is an assumption.

| Scenario | Expedition with free ticks (*r* = 0) | *r* for $0.50 | Fight at that *r* |
|---|---:|---:|---:|
| S1 | $0.490 | **0.024** | 3,536,464 |
| S2 | $0.441 | 0.223 | 3,867,741 |
| S3 | $0.428 | 0.272 | 3,828,630 |
| S4 | $0.475 | 0.057 | 3,471,397 |
| S5 | $0.381 | 0.305 | 4,003,722 |

**Plainly: the threshold does not hold at today's prices, and no plausible cheapening of the fight
alone makes it hold in the worst case.**

- **S1 (every move near goblins).** A fight would have to cost 295,792 L2 gas with everything
  else unchanged. That is 5.7 % of today's 5,156,800, and under the fight's own non-tick part in
  the model (about 3.5M: account, fee transfer, instance and goblin reads and writes). If the tick
  cheapens everywhere at once, S1 reaches $0.50 only with the tick's part at **2.4 %** of today's;
  even free ticks leave $0.490.
- **Mixed expeditions (S2, S3).** They pass with fights at about 2.84M to 2.86M (55 % to 57 % of
  today's), or with the tick's part at about a quarter of today's everywhere.
- **Other routes.** An L2 gas price of **11.6 to 15.6 Gfri** (today 21.7; 18.1 to 30.8 over two
  weeks), or mainnet metering these contracts in Sierra gas, below devnet's VM-resource figures
  used here: to be measured on Sepolia (§8.6).

Detail in §9 and §9.4.

## Verdict (part 1, Dojo)

| Question | Answer |
|---|---|
| **ADR-0001 threshold: 300 actions ≤ $0.50, sponsored, on Starknet mainnet** | **Not met at today's prices.** An expedition costs **$1.73 to $2.69** with one model per goblin (3.5× to 5.4× the threshold), and still **$0.97 to $1.08** (1.9× to 2.2×) with the goblins packed in one model (the cheapest storage measured). R-2 materialises: option B of ADR-0001 is to be re-examined (escalated, see the end) |
| What dominates | **Storage through the Dojo world, not computation.** In the worst-case tick (13.2M L2 gas), the world's reads and writes are 9.5M (72 %); the whole world tick in memory (flood, 8 goblins, conditions) is 1.25M, the flood alone 0.69M |
| Where the money goes | Fight actions: one transaction each (the queue stops on damage), 100 of the 300 actions, 60 % to 70 % of the expedition's cost |
| What it would take | At today's STRK price, the L2 gas price would have to fall to **5.2 to 11.0 Gfri** (now 21.5; 17.8 to 30.4 over the last two weeks), or the expedition to cost **≤ 569M L2 gas: 1.9M per action on average**. The worst-case tick's computation plus the transaction overhead alone is 1.5M |
| **D-52 (rarity signature)** | **Keep it.** Overhead measured in memory on the same pair and outcome: **+38,930 L2 gas** when a recipe is found, **+27,090** when the brew fails; at system level +73,820 (1.6 % of a 4.6M brew) = **$0.000065 per first brew of a pair**, nothing for a known pair |
| 10 or 5 Rifts | **5 a day per account (D-101)**, as the brief says; PLAN's SPK-2 row still says 10 |

## 1. What was built, and how far it is from the design

`spikes/SPK-2/` is a Dojo world with five systems named after what they measure, 27 snforge
tests with gas budgets, and a script that sends the same actions to a local Katana.

| Measured | System | What it does |
|---|---|---|
| Worst-case tick | `tick_worst_case.attack` | Window of **15 × 16** (D-120), adventurer on local (7, 7), walls, **8 awake goblins**. The adventurer attacks an adjacent goblin (sword, damage from the `2^(x/40)` table of design/04), then one world tick: **one flood from the adventurer shared by all goblins**; goblins in ascending id order attack if adjacent (the same table), else step to their free neighbour closest to the adventurer (rule (a) of docs/needs/hexmap.md: flood on the occupancy frozen at the start of the tick, current occupancy filters the candidates, lowest tile index on ties, fallback to the same layer); bleeding, poison, burning and regeneration applied (pips of design/03). Read and write once per model |
| Storage lever | `tick_worst_case.attack_packed` | The same action, the 8 goblins in **one model, one felt each, packed by hand** |
| Queue of moves | `queue_moves.walk` | Up to 10 moves in one transaction, a tick after each on the window that followed the adventurer; stops when a goblin hits, a goblin enters sight, the adventurer is defeated; an invalid move drops the rest without reverting. Measured with 10, 5 and 1 moves (8 goblins following, none adjacent, all awake for 10 ticks) and 10 moves without goblin |
| Brewing | `brew.brew`, `brew.brew_unsigned` | design/07's discovery with and without the rarity signature; Region 1 book (10 ingredients, 12 recipes); a new pair (discovery) and a known pair |
| Hub day | `hub.accept_quest`, `claim_quest`, `enter`, `leave` | Owner check, registry reads, quest log; `enter` makes the entry draw through a `fate` stand-in reading the transaction hash and writes the instance and the adventurer's snapshot; `leave` erases them |

Distance from the design (every item makes the real figure **higher** unless marked ↓):

| | In the spike | In the design |
|---|---|---|
| Flood | **A bitboard flood of our own** (`src/board.cairo`, the library's field-product dilation rewritten, tested against a scalar BFS). `origami_hexmap` 1.8.0 does not build here (see Escalations) | `origami_hexmap` 1.8.0 or its successor |
| Window | A **stand-in**: the terrain of the 15 × 16 board already assembled, read from one model per origin (1 read per tick). Assembly is SPK-7's | Assembled at each tick from 2 to 4 chunks, 2 layers each, never stored |
| Awake goblins | The instance has exactly the goblins it reads (8, or 0); no selection of the 8 nearest among more | ≤ 8 nearest among the goblins of the window |
| Occupancy | Derived from the goblins' positions | A chunk layer; crossing a chunk writes the occupied bit of two chunks (ADR-0006 §4) |
| Goblin AI | Melee "close" only, all engaged; no state machine, skills, pack alert, line of sight, facing or arcs | design/04 *Goblin AI*, *Facing and arcs* |
| Adventurer | Sword attack; 3 conditions; energy regeneration; no skills, adrenaline, energy costs | design/03, design/04 |
| Stop conditions | Hit, a goblin entering sight, defeat, invalid move | Also: a condition gained, an alert, an activation, a chunk revealed, loot |
| Randomness | `fate` = Poseidon(transaction hash, domain), hubs only | ADR-0002 provider (SPK-3) |
| Entering | No chunk revealed, no goblin placed, no daily Rift counter | Reveal (SPK-7), D-101 counter |
| Leaving | Instance and snapshot erased; goblins left in storage (↓) | Instance state discarded |
| Account | Katana's dev account; no session, no paymaster | Controller session (SPK-9), a paymaster sponsoring |
| Typical fights (↓) | Every fight action priced at the worst case (8 awake goblins, deepest flood of the fixture) | Fewer goblins awake most of the time |

## 2. Measurements

### 2.1 snforge: per call, and budgets

Per-call L2 gas is read from the trace (`--trace-components contract-name gas`); the test's own
figure includes the world's deployment and the setup. Both metering modes are given: snforge's
default (Sierra gas, what Starknet charges contracts of Sierra ≥ 1.7) and Cairo steps (what
Katana applied, §2.2).

```
cd spikes/SPK-2
snforge test test_systems --trace-components contract-name gas > snforge-trace.txt
snforge test test_systems --tracked-resource cairo-steps --trace-components contract-name gas > snforge-trace-steps.txt
python3 summarize_trace.py snforge-trace.txt          # → snforge-summary.md
```

| Call | L2 gas, Sierra gas | of which world calls | L2 gas, Cairo steps |
|---|---:|---:|---:|
| `tick_worst_case.attack` | 13,203,148 | 9,524,983 (7 calls) | 17,659,840 |
| `tick_worst_case.attack_packed` | 6,619,410 | 3,157,690 (7 calls) | 7,606,720 |
| `queue_moves.walk`, 10 moves | 28,046,442 | 10,471,263 (17 calls) | 33,539,840 |
| `queue_moves.walk`, 5 moves | 19,705,588 | 9,998,123 (12 calls) | 24,579,840 |
| `queue_moves.walk`, 1 move | 13,503,304 | 9,619,611 (8 calls) | 17,739,840 |
| `queue_moves.walk`, 10 moves, no goblin | 7,052,124 | 3,244,799 (17 calls) | 6,519,680 |
| `queue_moves.walk`, stopped by a hit after 1 | 13,391,271 | 9,619,611 | 17,659,840 |
| `queue_moves.walk`, invalid first move | 11,960,630 | 9,524,983 | 16,059,840 |
| `brew.brew`, new pair (R + R, found) | 4,646,384 | 2,545,854 (12 calls) | 4,251,840 |
| `brew.brew_unsigned`, new pair | 4,572,564 | 2,545,854 (12 calls) | 4,211,840 |
| `brew.brew`, known pair | 3,312,392 | 1,792,244 (9 calls) | 3,048,960 |
| `hub.accept_quest` | 1,710,148 | 948,296 (4 calls) | 1,581,440 |
| `hub.claim_quest` | 3,082,129 | 1,824,263 (7 calls) | 2,834,560 |
| `hub.enter` | 3,986,642 | 2,586,017 (7 calls) | 3,727,680 |
| `hub.leave` | 3,928,888 | 2,581,015 (6 calls) | 4,098,240 |

The worst-case tick, call by call (Sierra gas, from `snforge-trace.txt`):

```
├─ [selector] attack
│  ├─ [contract name] tick_worst_case
│  ├─ [L2 gas] 13203148
│  ├─ [selector] entity          world  225372     Instance (5 fields)
│  ├─ [selector] entity          world  500572     InstanceAdventurer (16 fields)
│  ├─ [selector] entities        world  2899194    8 goblins (11 fields each)
│  ├─ [selector] entity          world  94628      Window (1 field)
│  ├─ [selector] set_entity      world  450643     Instance
│  ├─ [selector] set_entity      world  833744     InstanceAdventurer
│  └─ [selector] set_entities    world  4520830    8 goblins
```

A world read costs about 70k plus 26k per field, a write about 280k plus 35k per field (fit on
the lines above; Dojo 1.8 packs `IntrospectPacked` fields by a generic loop in the world). Hence
the lever: 88 goblin fields become 8 felts packed by hand, and the world's share falls from 9.5M
to 3.2M. A first attempt that let Dojo pack a `[GoblinState; 8]` (88 fields in one model) cost
more, not less (13.55M against 13.20M): the saving comes from the number of fields, not of models.

Algorithms alone, in memory (the measured test minus a baseline test building the same inputs;
`get_available_gas` differences were tried and rejected: gas is withdrawn in chunks, a reading
can go up):

| Benchmark | Test L2 gas | Baseline | Algorithm |
|---|---:|---:|---:|
| Flood, worst-case window, 8 goblins, 12 layers | 2,013,172 | 1,318,950 | **694,222** (58k per layer) |
| World tick, worst case (flood, 2 attacks, 6 steps, conditions) | 2,563,624 | 1,313,290 | **1,250,334** |
| Discovery, C + U pair, recipe found: signed / unsigned | 73,916 / 34,986 | 14,020 | **59,896 / 20,966** (+38,930) |
| Discovery, same pair, failed: signed / unsigned | 54,936 / 27,846 | 14,020 | **40,916 / 13,826** (+27,090) |

The flood costs 3× the library's figure per layer (19k on a two-limb board): it tests which
goblins each layer touches and keeps every layer. Its share of the tick is 5 %, so it was not
optimised.

Tests and budgets (`scripts/lock.sh sozo test --manifest-path spikes/SPK-2/Scarb.toml`, raw output
`spikes/SPK-2/sozo-test-output.txt`): **27 passed**, every one with
`#[available_gas(l2_gas: ceil(1.05 × measured))]`. The oracle of AC-1:
`test_flood_matches_reference_on_the_fixtures` and `…_on_random_boards` check every layer of the
flood, every goblin's distance and every goblin's step against a scalar queue BFS over
coordinates, on the two fixture windows and six pseudo-random boards (adventurer on local row 7
and row 8).

### 2.2 Katana: the same actions as transactions

```
scripts/with-katana.sh bash spikes/SPK-2/run.sh > spikes/SPK-2/katana-output.txt
```

`run.sh` builds, migrates, and `katana.py` sends each action with `sozo execute --wait`, then
reads `starknet_getTransactionReceipt`. Each measured transaction starts from its own fresh
fixture (instances 1 to 6). Katana is deterministic here: rerunning the same list of
transactions gave the same hashes and figures.

| Action | Katana L2 gas | L1 gas (DA) | Fee (STRK, Katana's 20 Gfri) | snforge call, Cairo steps | Difference: the transaction |
|---|---:|---:|---:|---:|---:|
| Worst-case tick | 17,940,800 | 13,462 | 0.359085 | 17,659,840 | 280,960 |
| Worst-case tick, packed goblins | 7,927,680 | 13,462 | 0.158823 | 7,606,720 | 320,960 |
| Queue, 10 moves | 33,832,000 | 13,462 | 0.676909 | 33,539,840 | 292,160 |
| Queue, 5 moves | 24,846,400 | 13,462 | 0.497197 | 24,579,840 | 266,560 |
| Queue, 1 move | 18,025,920 | 12,360 | 0.360766 | 17,739,840 | 286,080 |
| Queue, 10 moves, no goblin | 7,331,840 | 4,646 | 0.146730 | 6,519,680 | 812,160 |
| Brew, signature, new pair | 5,143,040 | 9,054 | 0.103042 | 4,251,840 | 891,200 |
| Brew, no signature, new pair | 5,143,040 | 9,054 | 0.103042 | 4,211,840 | 931,200 |
| Brew, known pair | 3,860,160 | 5,748 | 0.077318 | 3,048,960 | 811,200 |
| Accept quest | 2,262,400 | 4,095 | 0.045330 | 1,581,440 | 680,960 |
| Claim quest | 3,595,520 | 6,299 | 0.072036 | 2,834,560 | 760,960 |
| Enter | 4,448,640 | 9,605 | 0.089165 | 3,727,680 | 720,960 |
| Leave | 4,414,080 | 6,850 | 0.088419 | 4,098,240 | 315,840 |

Comparison:

- **Katana meters these transactions in Cairo steps**, not in Sierra gas: its figures sit 0.27M
  to 0.32M above snforge's Cairo-steps figures for the tick and the queues, a constant that is
  the transaction around the call (account validation, `__execute__`, fee transfer). Against
  snforge's default Sierra gas, Katana is 36 % higher on the tick and 21 % on the 10-move
  queue. The likely reason is Katana's dev account, compiled to an older Sierra: a call chain
  rooted in such a contract is metered in steps. Starknet charges contracts of Sierra ≥ 1.7 in
  Sierra gas, so **mainnet should sit between the two figures**; the money gives both.
- The overhead is larger (0.68M to 0.93M) for brewing, hub actions and the empty queue; not
  explained here.
- Katana posts state diffs as calldata (`l1_gas`, 512 per felt); mainnet posts them in blobs
  (`l1_data_gas`, 32 per felt). The money uses `l1_gas / 16` as mainnet data gas: **under 0.5 %
  of any action's cost** (0.2 % of the tick).
- The two brews cost the same on Katana in this run and 40,000 apart in an earlier one: their
  `fate` word comes from the transaction hash, which changed with the order of the setup
  transactions, and with it the branch taken. The D-52 figure is therefore the in-memory one,
  on the same pair and outcome.

## 3. Money

```
python3 spikes/SPK-2/prices.py > spikes/SPK-2/prices-output.txt
python3 spikes/SPK-2/money.py > spikes/SPK-2/money-output.txt
```

### 3.1 Inputs

| | Value | Source, time |
|---|---|---|
| Mainnet L2 gas price | **21,498,730,231 fri** | `starknet_getBlockWithTxHashes("latest")`, `https://api.cartridge.gg/x/starknet/mainnet`, block 15,585,149, 2026-09-28T16:35:53Z (same price from `starknet-rpc.publicnode.com`, block 15,585,142) |
| Mainnet L1 data gas price | 910,973,468,582 fri | same block |
| Sepolia L2 gas price | 21,677,546,495 fri | `https://api.cartridge.gg/x/starknet/sepolia`, block 15,776,697, 16:35:57Z (same from publicnode and drpc) |
| Mainnet L2 gas price, past blocks | 21.90, 22.40, 21.71, 21.01, 22.28, **17.81**, **30.38** Gfri | the same endpoint, 1k to 800k blocks back (2026-09-28T16:07Z back to 2026-09-13T00:49Z) |
| STRK | **$0.04084113** | CoinGecko `simple/price`, 16:36:04Z. Binance 0.04086, Coinbase 0.04082, Kraken last 0.04088, same minute |
| ⇒ | 1M L2 gas = 0.021499 STRK = **$0.000878** | |

Endpoints that did not answer: `rpc.starknet.lava.build` (410, discontinued), Blast (403),
`free-rpc.nethermind.io` (no DNS), `1rpc.io` and mainnet drpc (method not available).

### 3.2 Per action

"Sierra estimate" = snforge's Sierra-gas call + Katana's transaction overhead (§2.2). Dollars
include the data-availability estimate.

| Action | Katana tx L2 gas | Sierra estimate | $ (Katana) | $ (Sierra estimate) |
|---|---:|---:|---:|---:|
| Worst-case tick | 17,940,800 | 13,484,108 | 0.01578 | 0.01187 |
| Worst-case tick, packed goblins | 7,927,680 | 6,940,370 | 0.00699 | 0.00613 |
| Queue, 10 moves (per move) | 33,832,000 | 28,338,602 | 0.02974 (0.00297) | 0.02491 (0.00249) |
| Queue, 5 moves | 24,846,400 | 19,972,148 | 0.02185 | 0.01757 |
| Queue, 1 move | 18,025,920 | 13,789,384 | 0.01586 | 0.01214 |
| Queue, 10 moves, no goblin (per move) | 7,331,840 | 7,864,284 | 0.00645 (0.00065) | 0.00692 (0.00069) |
| Brew, new pair, signature | 5,143,040 | 5,537,584 | 0.00454 | 0.00488 |
| Brew, known pair | 3,860,160 | 4,123,592 | 0.00340 | 0.00363 |
| Accept quest | 2,262,400 | 2,391,108 | 0.00200 | 0.00211 |
| Claim quest | 3,595,520 | 3,843,089 | 0.00317 | 0.00339 |
| Enter | 4,448,640 | 4,707,602 | 0.00393 | 0.00416 |
| Leave | 4,414,080 | 4,244,728 | 0.00389 | 0.00374 |

A queue costs a fixed part and a part per move: 1.62M per move in Sierra gas
((28.05M − 13.50M) / 9), 11.9M fixed with 8 goblins (their reads and writes).

### 3.3 An expedition of 300 actions

Assumptions (in `money.py`): 180 moves (60 %) in queues, 100 fight actions (33 %) of one
transaction each (the queue stops on damage), 20 others (7 %: loot, chest, gate, potion) of one
transaction each priced as a 1-move queue with 8 goblins, plus `enter` and `leave`. Moves near
goblins go in queues of 5 with 8 goblins; exploring moves in queues of 10 without goblin.

| Scenario | Transactions | $ (Katana) | $ (Sierra estimate) | × $0.50 | L2 gas price that would pass |
|---|---:|---:|---:|---:|---:|
| S1: every fight at the worst case, every move near 8 goblins | 158 | 2.690 | 2.070 | 4.1 to 5.4 | 5.15 Gfri |
| S2: as S1, 2/3 of the moves exploring | 146 | 2.243 | 1.732 | 3.5 to 4.5 | 6.17 Gfri |
| S3: S2 with the goblins packed in one model | 146 | 1.082 | 0.973 | 1.9 to 2.2 | 11.00 Gfri |

S3's queues are **estimated**: the queue's measured cost minus the saving measured on the tick
(10.0M on Katana, 6.5M in Sierra gas), the same 8 goblins being read and written once per
transaction. The tick itself is measured.

### 3.4 An active player per day

5 Rifts (D-101), each one expedition of 300 actions (floors not counted apart), 3 quests accepted
and claimed, 5 brews of a new pair.

| Scenario | $ per day (Katana) | $ per day (Sierra estimate) | $ per 30 days (Sierra estimate) |
|---|---:|---:|---:|
| S1 | 13.49 | 10.39 | 311.7 |
| S2 | 11.25 | 8.70 | 261.0 |
| S3 | 5.45 | 4.91 | 147.2 |

Hub actions are under 1 % of the day; the Rifts are the cost.

## 4. D-52

| Measure | Signed | Unsigned | Overhead |
|---|---:|---:|---:|
| Discovery in memory, same pair and outcome, found | 59,896 | 20,966 | **+38,930** |
| Discovery in memory, same pair and outcome, failed | 40,916 | 13,826 | **+27,090** |
| `brew` system, snforge Sierra gas (pair 8, 9) | 4,646,384 | 4,572,564 | +73,820 (1.6 %), outcomes may differ |
| Known pair | — | — | 0 (no discovery) |

The overhead is two rarity lookups (divisions of the packed constant) and a mask and counter
taken from packed words. It is below 2 % of a brew and $0.000065, once per pair and adventurer
(45 pairs per book). **Recommendation: keep D-52.** It could be made cheaper still by storing
the signature of each of the 45 pairs in the book at registration (one lookup), which
docs/CAIRO.md §1 prefers; not worth it at this size.

## 5. What would change the numbers

| Change | Effect, from the measurements |
|---|---|
| Storage layout | The largest lever: packing the goblins by hand halves the tick (−6.6M Sierra, −10.0M Katana). The adventurer's snapshot (16 fields, 1.33M read + write) and the instance (5 fields, 0.68M) are the next. Beyond that, the world's call overhead (≈ 70k per read, ≈ 280k per write call) remains |
| Fewer awake goblins | Each goblin costs about 0.93M of storage (read + write, one model each) and 0.07M to 0.15M of computation. 4 instead of 8 saves ≈ 4M per tick with one model per goblin |
| Queue length | Fixed part 11.9M with 8 goblins, 1.62M per move (Sierra): longer queues amortise, but fights cannot be queued |
| Fallback of D-120 (sight 5, 13 × 14) | Fewer flood layers on the same two-limb board: at most the flood's share, 0.69M of 13.2M (< 5 %) |
| Window assembly (SPK-7), per tick | Replaces the stand-in's one read (95k) by 2 to 4 chunk reads, two layers each, plus masks and shifts. At ≈ 70k + 26k per field per read, 4 two-field chunk models ≈ 0.5M per tick: +4M on a 10-move queue |
| Chunk writes on crossing, awake selection among more goblins, skills, loot rolls (SPK-3), events | Not measured, all upward |
| The account (Controller session) and a paymaster | Katana's dev account adds 0.27M to 0.93M; a session with policies and an outside-execution paymaster add validation (SPK-9, SPK-1) |
| Prices | Linear in the L2 gas price and in STRK's dollar price. Over two weeks the L2 gas price moved from 17.8 to 30.4 Gfri |

## 6. Open questions

For **FND-04** (budgets):

1. **Metering.** Budgets should be written in Sierra gas (snforge's default), with a transaction
   overhead measured on Sepolia with the real account; Katana 1.7.1 meters in Cairo steps here.
2. **Storage of hot instance state.** One model per goblin costs more than the computation it
   stores. Options: goblins packed per instance or per chunk (measured: −50 % on the tick); the
   snapshot and the instance packed by hand; or instance state kept outside Dojo models, raw
   storage in the system, with events for Torii (an ADR matter: ADR-0004 and the indexing). What
   does FND-04 allow?
3. **Per-action budget.** At today's prices the ADR threshold means 1.9M L2 gas per action on
   average. Is the threshold kept (then option B), or restated?

For **SPK-7**:

4. Measure the assembly with chunk **models read through the world** in this same harness (the
   stand-in here is one read of a one-field model), and the occupied-bit writes when a goblin
   crosses a chunk.
5. How are the awake goblins found: goblins keyed by chunk, or a list per instance? Reading all
   goblins of an instance does not scale.

For the design (not cost):

6. Rule (a) (flood on the occupancy frozen at the start of the tick) walls a goblin off behind
   its own pack: in the first queue fixture, a goblin behind the front rank took detours and
   fell out of the window within 7 ticks. The fixture was changed so that all 8 stay awake. Is
   that the behaviour wanted?

## 7. Part 2 — the same worst cases as native contracts (ADR-0007, D-123)

> **Superseded by §8.** This section paired Dojo on Katana with native on devnet through
> devnet's default account, and a one-slot Dojo goblin with an 11-slot native one. Its receipts
> are kept (`spikes/SPK-2/native/devnet-default-account-output.txt`) as a harness measurement.
> Its native entrypoints (`attack_felt`, `attack_packed`, `walk_packed`) are now `attack` and
> `walk` with a layout and a check parameter.

Measured on 2026-09-28 by `[Opus 5.5]` on the root toolchain: Scarb 2.19.4, snforge 0.61.0,
sncast 0.61.0, starknet-devnet 0.10.0. Code and raw outputs: `spikes/SPK-2/native/`.

### 7.1 Verdict

| Question | Answer |
|---|---|
| **Native against Dojo, per action** | **Every action is cheaper natively.** As full transactions, native costs **0.33 to 0.81×** the Dojo figure: the worst-case tick 0.70× (one storage struct per goblin) and 0.62× (goblins packed), queues 0.74 to 0.76× with 8 goblins and 0.33× without, brewing 0.41 to 0.52×, hub actions 0.40 to 0.81×. On the contract's own execution (snforge, Sierra gas, same meter on both sides) the gap is wider: 0.42 to 0.59× on the tick, 0.13 to 0.20× on hub and brewing actions, where the Dojo world's calls were most of the cost |
| **ADR-0001 threshold, native** | **Still not met at today's prices.** A 300-action expedition costs **$0.72 to $2.08** natively (1.4× to 4.2× the $0.50), against $1.15 to $2.86 on Dojo at the same prices. The best measured case (goblins packed per instance, two thirds of the moves exploring) needs an L2 gas price of **15.7 Gfri** to pass, against 22.6 Gfri today (17.9 to 30.5 over two weeks) |
| What dominates now | **No longer storage: the tick's own computation and the transaction around it.** A 10-move queue with 8 goblins is 20.5M of execution, of which ≈ 12.5M is ten world ticks in memory. A packed fight is 4.9M as a transaction: 2.8M of execution (the world tick alone is 1.25M) and ≈ 2.1M around it on devnet (account, fee transfer, storage syscalls) |
| D-52 | Unchanged: +73,820 L2 gas at call level (755,698 against 681,878), +40,000 on devnet; the logic is the same code. Keep it |

### 7.2 What was built

| | Part 1 (Dojo) | Part 2 (native) |
|---|---|---|
| Contracts | A world, 5 systems, 14 models | **Two contracts** (ADR-0007): `Hub` (persistent: adventurers, balances, alchemy, quests, gates) and `Instances` (ephemeral: instances, snapshot, goblins, window stand-in). `enter` calls `Instances.open`; `leave` sends the results back in one call to `Hub.apply_results`, which accepts only the registered `Instances` |
| Pure logic | `board`, `rules`, `alchemy`, `tables`, `fixtures`, `fate` | **The same files, copied unchanged** (`native/check.sh` compares them byte for byte); the models are plain structs with the same fields, packed by hand into felts (`native/src/models.cairo`) |
| Goblin storage | One model per goblin (11 fields); variant: 8 hand-packed felts in one model | `attack`, `walk`: **one storage struct per goblin**, default layout, one slot per field (11 slots); `attack_felt`: one felt per goblin; `attack_packed`, `walk_packed`: **8 felts under one instance key** |
| Other state | Dojo-packed models | Adventurer snapshot in 1 felt, instance in 1 slot, hero in 1 felt, book in 2 slots, grimoire, quest log, location in 1 slot each |
| Access control | The world's writers only; no owner check on instance actions | **Ours**: the caller must own the instance or the adventurer; setups by the admin; `apply_results` only from `Instances`; `open` only from `Hub` (tested: `test_tick_refuses_a_stranger`, `test_results_only_from_the_instances`) |
| Events | One per model write (the world's) | One small event per action (`Acted`, `Opened`, `Closed`); the client reads its own instance by view calls (ADR-0007, *Events are an interface*) |
| Tests | 27, budgets | **31**, budgets `ceil(1.05 × measured)`: the same oracle, rules and in-memory benchmarks, the same system scenarios, plus the three layouts compared, the packed queues and the two access checks |

Everything part 1 left out (§1) is still left out; the window is still the one-read stand-in.

### 7.3 Measurements

```
spikes/SPK-2/native/check.sh                                       # same: src/{alchemy,board,fate,fixtures,rules,tables}.cairo
cd spikes/SPK-2/native && snforge test > snforge-test-output.txt   # Tests: 31 passed, 0 failed
cd spikes/SPK-2/native && snforge test test_systems --trace-components contract-name gas > snforge-trace.txt
scripts/with-node.sh python3 spikes/SPK-2/native/devnet.py > spikes/SPK-2/native/devnet-output.txt
python3 spikes/SPK-2/prices.py > spikes/SPK-2/native/prices-output.txt
python3 spikes/SPK-2/native/money.py > spikes/SPK-2/native/money-output.txt
```

Two runs of the devnet script gave the same figures. Every transaction `SUCCEEDED`.

**What each figure includes.** snforge's per-call trace figure is the contract's Sierra gas
**without the cost of its syscalls**. On `test_tick_worst_case_layouts`, `--detailed-resources`
reports 43,802,612 of Sierra gas for 139,153,412 L2 gas in total, with 439 storage writes and 285
storage reads. The devnet receipt is the whole transaction:
- the account's validation and execution;
- the storage syscalls;
- the fee transfer;
- events and calldata.

The gap between the two grows with storage accesses. It is +1.04M on the queue without goblin and
+4.76M on the tick with a storage struct per goblin (160 more slot accesses than one felt per
goblin, ≈ 17k each). Two consequences:
- part 1's "Sierra estimate" (§3.2: snforge call plus Katana's overhead) is a **lower bound**, since
  it misses those syscalls;
- the fair side-by-side is transaction against transaction: Katana for Dojo, devnet for native.

The two nodes do not meter the same way. Katana 1.7.1 metered in Cairo steps (§2.2), while
devnet 0.10.0 does not: its overhead over snforge's steps-mode figure is 5.0M on the tick, where
Katana's was a constant 0.28M. Treat the transaction ratios as indicative. The call-level ratios
use one meter, but leave syscalls out on both sides.

### 7.4 Side by side, per action

At the prices of §7.5; dollars include data availability (Katana's calldata `l1_gas / 16`,
devnet's `l1_data_gas` as reported).

| Action | Dojo tx L2 gas (Katana) | Native tx L2 gas (devnet) | Difference | Native / Dojo | $ Dojo | $ native | Dojo call (Sierra) | Native call (Sierra) | Native / Dojo (call) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Worst-case tick, a model / storage struct per goblin | 17,940,800 | 12,594,560 | −5,346,240 | 0.70 | 0.01677 | 0.01180 | 13,203,148 | 7,838,454 | 0.59 |
| Worst-case tick, goblins packed per instance | 7,927,680 | 4,906,560 | −3,021,120 | 0.62 | 0.00743 | 0.00461 | 6,619,410 | 2,812,014 | 0.42 |
| Worst-case tick, one felt per goblin (native only) | — | 4,986,560 | — | — | — | 0.00468 | — | 3,000,054 | — |
| Queue of 10 moves | 33,832,000 | 25,173,760 | −8,658,240 | 0.74 | 0.03160 | 0.02354 | 28,046,442 | 20,546,918 | 0.73 |
| Queue of 5 moves | 24,846,400 | 18,788,160 | −6,058,240 | 0.76 | 0.02321 | 0.01758 | 19,705,588 | 13,272,684 | 0.67 |
| Queue of 1 move | 18,025,920 | 13,685,680 | −4,340,240 | 0.76 | 0.01685 | 0.01282 | 13,503,304 | 7,923,696 | 0.59 |
| Queue of 10 moves, no goblin | 7,331,840 | 2,397,760 | −4,934,080 | 0.33 | 0.00685 | 0.00225 | 7,052,124 | 1,357,970 | 0.19 |
| Queue of 10 moves, goblins packed (native only) | — | 20,037,760 | — | — | — | 0.01873 | — | 15,520,378 | — |
| Queue of 5 moves, goblins packed (native only) | — | 11,572,160 | — | — | — | 0.01083 | — | 8,246,144 | — |
| Queue of 1 move, goblins packed (native only) | — | 5,111,680 | — | — | — | 0.00480 | — | 2,897,156 | — |
| Brew, signature, new pair | 5,143,040 | 2,685,920 | −2,457,120 | 0.52 | 0.00482 | 0.00252 | 4,646,384 | 755,698 | 0.16 |
| Brew, no signature, new pair | 5,143,040 | 2,645,920 | −2,497,120 | 0.51 | 0.00482 | 0.00249 | 4,572,564 | 681,878 | 0.15 |
| Brew, known pair | 3,860,160 | 1,601,920 | −2,258,240 | 0.41 | 0.00361 | 0.00151 | 3,312,392 | 493,050 | 0.15 |
| Accept quest | 2,262,400 | 1,673,680 | −588,720 | 0.74 | 0.00212 | 0.00157 | 1,710,148 | 248,930 | 0.15 |
| Claim quest | 3,595,520 | 1,913,680 | −1,681,840 | 0.53 | 0.00337 | 0.00180 | 3,082,129 | 403,150 | 0.13 |
| Enter | 4,448,640 | 3,625,280 | −823,360 | 0.81 | 0.00417 | 0.00340 | 3,986,642 | 801,212 | 0.20 |
| Leave | 4,414,080 | 1,776,320 | −2,637,760 | 0.40 | 0.00413 | 0.00168 | 3,928,888 | 577,000 | 0.15 |

The native `enter` and `leave` include the call to the other contract (448,122 and 140,300 at
call level). The native tick checks the owner, which part 1's did not.

### 7.5 Money, native

| | Value | Source, time |
|---|---|---|
| Mainnet L2 gas price | **22,573,370,546 fri** | `https://api.cartridge.gg/x/starknet/mainnet`, block 15,587,811, 2026-09-28T17:51:30Z |
| Mainnet L1 data gas price | 813,320,714,552 fri | same block |
| Past blocks | 21.48, 21.79, 21.27, 21.33, 22.44, **17.89**, **30.50** Gfri | 1k to 800k blocks back (to 2026-09-13T02:03Z) |
| STRK | **$0.04133903** | CoinGecko `simple/price`, 2026-09-28T17:51:39Z |
| ⇒ | 1M L2 gas = **$0.000933** | |

Same expedition model as §3.3 (180 moves in queues, 100 fight actions of one transaction each,
20 others, enter and leave) and the same day (5 Rifts, 3 quests, 5 brews):

| Scenario | $ Dojo (Katana) | $ native (devnet) | Native / Dojo | Native × $0.50 | L2 gas price for native to pass | $ per day, native |
|---|---:|---:|---:|---:|---:|---:|
| S1 worst case everywhere, a model / struct per goblin | 2.858 | 2.075 | 0.73 | 4.15 | 5.4 Gfri | 10.40 |
| S2 mixed (2/3 of the moves exploring), a model / struct per goblin | 2.383 | 1.680 | 0.70 | 3.36 | 6.7 Gfri | 8.42 |
| S3 mixed, goblins packed per instance | 1.150 | 0.719 | 0.63 | 1.44 | 15.7 Gfri | 3.62 |
| S4 worst case everywhere, goblins packed per instance | 1.400 | 0.951 | 0.68 | 1.90 | 11.9 Gfri | 4.78 |

Dojo's S3 and S4 use part 1's estimated packed queues; on native every figure is measured.
Dojo's figures differ from §3.3 only by the fresher prices.

### 7.6 What would change the native numbers

| Change | Effect |
|---|---|
| Fights | 100 packed fights are $0.46 alone: at today's prices the threshold cannot be met with one transaction per fight at 4.9M. A fight costs ≈ 2.8M of execution (world tick 1.25M, the flood 0.69M of it) and ≈ 2.1M around it |
| The flood | ~~≈ −0.45M per tick with the map library~~ **Withdrawn (fix loop 1, C-4):** the figure set our flood (which records each goblin's distance and keeps every layer) against the library's per-layer cost for a different task. Using the library is an **unmeasured opportunity** |
| Transaction overhead | 1.0M to 2.1M per transaction on devnet with its predeployed account and packed storage (up to 4.8M with a storage struct per goblin, the syscalls); the real one (Controller session, paymaster) is SPK-9 and SPK-1's to measure on Sepolia |
| Layout | Packing goblins per instance cuts the fight by 61 % (12.59M to 4.91M) and the queues by 20 % (10 moves) to 63 % (1 move); per instance against one felt per goblin changes little (4.91M against 4.99M) |
| Assembly of the window (SPK-7) | Natively, chunk reads are plain storage reads (≈ 17k each, §7.3) plus masks: much cheaper than the 0.5M per tick estimated through the Dojo world (§5) |

### 7.7 Open questions, part 2

1. **FND-04:** with storage no longer dominant, is the per-action budget written against the
   transaction (devnet) or the execution (snforge)? The two differ by 1 to 5M.
2. **The real account's overhead** on Sepolia (SPK-1, SPK-9): it sets a floor under every action
   and decides whether one transaction per fight can ever fit 1.9M.
3. **Threshold (R-2):** native narrows the gap (1.4× to 4.2× instead of 2.3× to 5.7× at the same
   prices) but does not close it; the owner's call stands (escalated in part 1).

## 8. Fix loop 1 — decision-grade figures (after the `[GPT-6-Astra]` cost audit)

Measured on 2026-09-28 by `[Opus 5.5]`. Five findings (C-1 to C-5), each fixed below. The
figures of this section are the ones to use.

### 8.1 Verdict

| Question | Answer |
|---|---|
| **Native against Dojo, controlled** (same node, same account, equal goblin storage, equal checks) | **Every action is cheaper natively.** The worst-case tick costs **0.26×** Dojo's (4,956,800 against 18,740,800 L2 gas). Queues cost 0.28× to 0.58×, and 0.26× without goblin. The adversarial ticks cost 0.26× to 0.45×, the expensive valid queue 0.88×, brewing 0.29× to 0.33×, hub actions 0.29× to 0.49×. At call level (snforge, Sierra gas): 0.13× to 0.56× |
| **ADR-0001 threshold, native (production form, owner checked)** | **Still not met at today's prices, but within 2×.** A 300-action expedition costs **$0.67 to $0.91** (1.35× to 1.82× the $0.50), against $1.19 to $2.81 for Dojo. With every fight on the deepest board found and every move near goblins in the expensive queue, it costs **$1.35** (2.7×). Break-even L2 gas price, DA held fixed: **11.7 to 15.8 Gfri** for the ordinary scenarios, **7.9 Gfri** for the adversarial one. Today: 21.3 Gfri; 17.9 to 30.5 over two weeks |
| **Metering** | devnet 0.10.0 meters **both** sides in VM resources (Cairo steps), whatever the account or the Sierra version (§8.2). The ratios compare like with like. Whether mainnet meters these classes in Sierra gas instead is open, to be measured on Sepolia. Native's Sierra-gas call is 0.56× to 0.79× of its VM-resource call on the four ticks compared, so the native figures here are likely **upper bounds** |
| **Flood depth** | **Not bounded by the design documents measured against** (ADR-0006 §4, design/02 *Simulation budget*, design/18 say one flood per tick, nothing about its depth). **Since then, D-127 (owner, gate L-G2, merged into this branch) caps the tick's flood at 15 layers**, a goblin it does not reach holding its position; SPK-7 tunes the number. The figures below are the **uncapped** cost that motivated the cap. The fixture's 12 layers is a property of the fixture. The deepest valid board found needs **92 layers**: in memory the flood costs 2.75M and the whole tick 3.28M. As a native transaction: **9.04M** (Dojo 20.06M). The expensive valid queue: **24.41M** for 10 moves (Dojo 27.76M). Question for FND-04 and the owner (§8.6) |
| D-52 | Unchanged: keep it. Native: +40,000 L2 gas on devnet, +73,820 at call level |

### 8.2 C-1 — one account compiled with Cairo 2.19, and what devnet meters

| | Class hash | Sierra | Compiler |
|---|---|---|---|
| devnet's default predeployed account (part 2's harness) | `0x5b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564` | 1.6.0 | 2.9.4 |
| **The account used now**: OpenZeppelin `openzeppelin_account` 4.0.1 (`spikes/SPK-2/account/`), declared, deployed and funded on devnet | `0x3daacb519bf62c729e518fd406139288bbed05488d03b70c518f99421a0b65` | **1.9.3** | **2.19.4** |

`spikes/SPK-2/devnet_measure.py`, run under `scripts/with-node.sh`, does the following:
- declares and deploys that account;
- deploys the native contracts, twice: built with Cairo 2.19 (Sierra 1.9.3), and the same sources built with Cairo 2.13 (Sierra 1.7.0, `spikes/SPK-2/native213/`);
- migrates the **Dojo world to the same devnet** with sozo 1.8.7 (`--use-blake2s-casm-class-hash`: devnet checks Blake2s compiled class hashes);
- sends every measured transaction of both sides through the one account, and records each receipt and trace (`spikes/SPK-2/devnet-output.txt`).

All 75 measured transactions succeeded: 29 native (Cairo 2.19), the same 29 on the Cairo 2.13 build, and 17 Dojo.

**What devnet meters.** The account was not what set the meter. devnet 0.10.0 charges every contract call in **VM resources**, for both sides:

| Evidence | Figures |
|---|---|
| Native calls on devnet against snforge's Cairo-steps mode (`native/meter-check-output.txt`) | Worst-case tick 3,920,000 against 3,945,600; maze 4,200,000 against 4,225,600; unreachable target 3,840,000 against 3,865,600; deepest board 8,960,000 against 8,985,600: **the steps figure minus 25,600, every time**. The Sierra-gas figures are 2,967,674, 3,327,411, 2,890,981 and 4,987,755 |
| Dojo on devnet against snforge's Cairo-steps mode (`meter-check-output.txt`) | Deepest board minus worst-case tick: **1,280,000 on devnet, 1,280,000 in steps mode**, 2,019,901 in Sierra gas |
| Sierra version | The Cairo 2.13 build of the native sources (Sierra 1.7.0) gives the **same** figures as the 2.19 build, within 40,000 |
| Account | The native tick through the default account (part 2's harness) cost 4,986,560; through the 2.19 account, 4,996,800 |

On this node, a transaction's cost therefore follows its VM resources. That explains why the flood's delta differs between the sides. On Dojo, the world's large step count hides the flood's bitwise work; natively the bitwise work shows. This reading assumes that VM-resource pricing takes the largest weighted resource rather than a sum; it is an inference, not a measurement.

**Invocation figures of native traces** (devnet). *Fix loop 3 (C-1): these figures are **not
additive**.* A transaction's fee is a weighted maximum over its resources
(<https://docs.starknet.io/learn/protocol/fees>), so the invocations do not sum to the receipt.
The last column is only the **non-additive residual**, the receipt minus their sum, not the cost
of anything. It can be negative: −643,200 here, −592,000 on the capped serpentine queue.

| Action | Receipt | Validate | Account execute | Game calls | Fee transfer | Non-additive residual |
|---|---:|---:|---:|---:|---:|---:|
| Worst-case tick, owner checked | 4,996,800 | 320,000 | 80,000 | 3,920,000 | 400,000 | 276,800 |
| Queue of 10 moves, checked | 20,128,000 | 320,000 | 40,000 | 19,040,000 | 400,000 | 328,000 |
| Queue of 10 moves, no goblin, checked | 2,248,000 | 320,000 | 120,000 | 1,320,000 | 400,000 | 88,000 |
| Tick, deepest board (92 layers) | 9,036,800 | 320,000 | 0 | 8,960,000 | 400,000 | −643,200 |
| Brew, new pair | 2,485,920 | 320,000 | 160,000 | 720,000 | 400,000 | 885,920 |
| Accept quest | 1,473,680 | 320,000 | 120,000 | 240,000 | 400,000 | 393,680 |
| Enter | 3,425,280 | 320,000 | 160,000 | 800,000 | 400,000 | 1,745,280 |

- **No allocation is drawn from these figures** (fix loop 3, C-1). An earlier version of this section gave an "account and protocol" share of 0.76M to 0.88M per transaction, and read the residual as calldata, events and rounding. Both are withdrawn: neither was derived from the resource vectors and the fee formula.
- **Game calls:** the invocation figure of everything the game's contracts execute, syscalls included. Under VM-resource metering, devnet does not separate syscalls.
- **Execution alone:** snforge's Sierra-gas call, without syscalls (§8.3, second table).
- **Syscalls cannot be isolated on this node.** The gap between devnet's figure and the Sierra-gas figure mixes the syscalls with the change of meter.
- **What is additive is the receipt:** the transaction's L2 gas and L1 data gas. Every cost, ratio and scenario in this file uses receipts only.

### 8.3 C-2 — the controlled comparison

- **Same storage per goblin on both sides.** Part 1's `Goblin` model is `IntrospectPacked` in one slot; the controlled native layout is one felt per goblin, packed by hand.
- **Same checks on both sides.** Part 1's systems check no owner, so the controlled native runs skip the check. The check costs 40,000 on devnet (4,956,800 → 4,996,800) and is measured apart.
- **The 11-slot layout is only a layout experiment:** 12,404,800 for the tick, 24,984,000 for 10 moves.
- **Queues are redone the same way.** Same node, same account (`spikes/SPK-2/money-devnet-output.txt`), prices of §8.5:

| Action | Dojo tx L2 gas | Native tx L2 gas | Difference | Native / Dojo | $ Dojo | $ native |
|---|---:|---:|---:|---:|---:|---:|
| Worst-case tick (goblins: one slot each) | 18,740,800 | 4,956,800 | −13,784,000 | **0.26** | 0.01651 | 0.00439 |
| Worst-case tick (goblins packed per instance) | 8,727,680 | 4,876,800 | −3,850,880 | 0.56 | 0.00770 | 0.00432 |
| Queue of 10 moves | 34,712,000 | 20,128,000 | −14,584,000 | 0.58 | 0.03054 | 0.01772 |
| Queue of 5 moves | 25,686,400 | 11,662,400 | −14,024,000 | 0.45 | 0.02261 | 0.01028 |
| Queue of 1 move | 18,785,920 | 5,201,920 | −13,584,000 | 0.28 | 0.01654 | 0.00460 |
| Queue of 10 moves, no goblin | 8,451,840 | 2,208,000 | −6,243,840 | 0.26 | 0.00744 | 0.00195 |
| Tick, corridor maze (45 layers) | 18,620,800 | 4,836,800 | −13,784,000 | 0.26 | 0.01640 | 0.00428 |
| Tick, unreachable target (13 layers) | 18,660,800 | 4,876,800 | −13,784,000 | 0.26 | 0.01644 | 0.00432 |
| Tick, deepest board found (92 layers) | 20,060,800 | 9,036,800 | −11,024,000 | 0.45 | 0.01767 | 0.00798 |
| Queue of 10 moves, serpentine (expensive valid queue) | 27,764,480 | 24,408,000 | −3,356,480 | 0.88 | 0.02442 | 0.02147 |
| Brew, signature, new pair | 7,507,040 | 2,485,920 | −5,021,120 | 0.33 | 0.00662 | 0.00221 |
| Brew, no signature, new pair | 7,427,040 | 2,445,920 | −4,981,120 | 0.33 | 0.00655 | 0.00217 |
| Brew, known pair | 4,900,160 | 1,401,920 | −3,498,240 | 0.29 | 0.00432 | 0.00125 |
| Accept quest | 3,144,400 | 1,473,680 | −1,670,720 | 0.47 | 0.00277 | 0.00131 |
| Claim quest | 5,037,520 | 1,713,680 | −3,323,840 | 0.34 | 0.00444 | 0.00152 |
| Enter | 6,974,640 | 3,425,280 | −3,549,360 | 0.49 | 0.00615 | 0.00304 |
| Leave | 5,414,080 | 1,576,320 | −3,837,760 | 0.29 | 0.00478 | 0.00141 |

The same pairs at call level (snforge, Sierra gas, syscalls excluded): worst-case tick 13,203,148 → 2,967,674 (**0.22**); packed 6,619,410 → 2,782,334 (0.42); queue of 10 moves 28,046,442 → 15,676,138 (0.56); of 5, 0.43; of 1, 0.23; no goblin 0.19; maze 0.25; unreachable target 0.22; deepest board 0.33; serpentine 0.53; brewing 0.15 to 0.16; hub actions 0.13 to 0.20.

**Native production figures** (owner checked, used in the scenarios):

| Action | Tick | Queue of 10 | Queue of 5 | Queue of 1 | 10 moves, no goblin |
|---|---:|---:|---:|---:|---:|
| One felt per goblin | 4,996,800 | 20,128,000 | 11,662,400 | 5,201,920 | 2,248,000 |
| Goblins packed per instance | 4,876,800 | 20,048,000 | 11,582,400 | 5,121,920 | — |

### 8.4 C-3 — adversarial floods

`spikes/SPK-2/adversarial.py` models the flood exactly (it gives the fixture's 12 layers). It builds three cases:
- the auditor's corridor maze;
- an unreachable target (the fixture's comb with goblin 8 walled in);
- the deepest valid board found: a seeded hill climb from the maze, eccentricity 93 from the adventurer, with goblin 1 adjacent so that the measured attack is legal.

All three are in `fixtures.cairo`, shared by both sides. They are checked against the scalar BFS oracle, with the layer count asserted (`test_flood_matches_reference_on_adversarial_boards`), benchmarked with baselines in memory, and measured as transactions on both sides.

| Case | Layers | Flood in memory | World tick in memory | Dojo tx | Native tx |
|---|---:|---:|---:|---:|---:|
| Part 1's fixture (comb) | 12 | 694,022 | 1,256,774 | 18,740,800 | 4,956,800 |
| Unreachable target (frontier exhausted) | 13 | 651,046 | 1,179,681 | 18,660,800 | 4,876,800 |
| Corridor maze (auditor's board) | **45** | 1,229,674 | 1,616,111 | 18,620,800 | 4,836,800 |
| **Deepest valid board found** | **92** | **2,752,390** | **3,276,455** | **20,060,800** | **9,036,800** |

In-memory figures come from native's snforge (Sierra gas); part 1's agree within 6,000.

The maze costs no more than the fixture on devnet. Six of its goblins are unreachable and stay put, and its layers are thin corridors: about 27k per layer against 58k on the open comb.

The **expensive valid queue** walks 10 moves West along a serpentine: corridors on odd rows, one gap every 14 columns. Goblin 1 follows; goblins 2 to 5 are walled off behind it; two goblins sit in sealed pockets 7 rows away, never in sight. So every tick's flood runs until the frontier is exhausted. It completes its 10 moves on both sides (`test_queue_serpent`) and costs **24,408,000** natively against **27,764,480** on Dojo, and 13,065,314 against 24,603,228 at call level. It is the one action where native gains little: flood computation dominates, and the flood is the same code.

### 8.5 C-5 and the money

Break-even L2 gas price, per C-5: `(threshold − DA_USD) / (L2_gas × STRK_USD × 1e-18)`, with the data-availability dollars held at today's price (`spikes/SPK-2/money_devnet.py`).

| | Value | Source, time |
|---|---|---|
| Mainnet L2 gas price | **21,345,442,020 fri** | `https://api.cartridge.gg/x/starknet/mainnet`, block 15,590,108, 2026-09-28T18:56:03Z (`spikes/SPK-2/prices-fixloop1-output.txt`) |
| Mainnet L1 data gas price | 977,190,847,683 fri | same block |
| STRK | **$0.0411773** | CoinGecko `simple/price`, 2026-09-28T18:56:14Z |
| ⇒ | 1M L2 gas = **$0.000879** | |

Expedition as §3.3 (180 moves in queues, 100 fight actions of one transaction each, 20 others, enter and leave); day as §3.4 (5 Rifts, 3 quests, 5 brews). Native in its production form:

| Scenario | $ Dojo | $ native | Native / Dojo | Native × $0.50 | Break-even L2 gas price, native | Native L2 gas per expedition | $ per day, native |
|---|---:|---:|---:|---:|---:|---:|---:|
| S1 worst case everywhere | 2.806 | **0.909** | 0.32 | 1.82 | 11.68 Gfri | 1,028,566,400 | 4.57 |
| S2 mixed (2/3 of the moves exploring) | 2.353 | **0.686** | 0.29 | 1.37 | 15.51 Gfri | 775,644,800 | 3.45 |
| S3 mixed, goblins packed per instance | 1.191 | **0.674** | 0.57 | 1.35 | 15.81 Gfri | 761,084,800 | 3.39 |
| S4 worst case everywhere, goblins packed | 1.433 | **0.895** | 0.62 | 1.79 | 11.87 Gfri | 1,012,086,400 | 4.49 |
| S5 adversarial floods (every fight on the deepest board, every move near goblins in serpentine queues) | 2.570 | **1.348** | 0.52 | 2.70 | 7.87 Gfri | 1,528,761,600 | 6.76 |

Dojo's S3 and S4 use part 1's estimated packed queues; every native figure is measured.

### 8.6 What remains open

1. **The flood's bound: answered by D-127 (15 layers).** Uncapped, a valid window can need 92 layers, and the tick then costs 1.8× the fixture's (9.04M against 5.00M natively). With the cap, the flood's cost is bounded near the 12-to-15-layer figures measured here: about 0.7M to 0.9M in memory on an open board, and less on corridors. The capped flood is SPK-7's to measure (10, 15, 20 layers and unlimited). This spike's code does not implement the cap. For FND-04: budget the tick at the cap, not at the fixture.
2. **Mainnet's meter.** devnet 0.10.0 meters in VM resources. Mainnet (Starknet 0.14.3 at the time of reading) may meter Sierra ≥ 1.7 classes in Sierra gas. To be measured on Sepolia (SPK-1, SPK-9) with the real account: native's figures here are likely upper bounds.
3. **The library's flood (C-4):** an unmeasured opportunity, to benchmark against the oracle with identical results before any figure is claimed.

*(Fix loop 2 implements the cap: see §9.)*

## 9. Fix loop 2 — the tick under D-127, and the threshold stated plainly

Measured on 2026-09-28 by `[Opus 5.5]`. §9 supersedes §8's scenarios and verdict. The summary
at the top of this file answers the threshold question.

### 9.1 The cap, implemented on both sides

`board::flood` takes a `limit`, and the tick passes `FLOOD_LAYERS = 15` (design/02 *Simulation
budget*, design/04 *Goblin AI*, ADR-0006 §4). The flood computes at most 15 distances. A goblin
it did not touch has distance 0 and **holds its position**; it still takes its conditions and
regeneration. It would still use a ranged attack or a skill, which this spike's goblins do not
have.

`board` and `rules` are shared, byte for byte, by part 1 and the native package
(`native/check.sh`). So **the Dojo tick is capped too, at no cost**, and the pairs stay
controlled. `UNLIMITED` (255) keeps the uncapped flood for the oracle and the unlimited
benchmarks.

`test_flood_capped_matches_reference` checks the capped flood against the scalar BFS on four
boards:
- every computed layer;
- at most 16 layers (the start and 15 distances);
- a goblin farther than 15 steps has distance 0.

### 9.2 The worst case under D-127

Under the cap, the costliest tick computes all 15 layers and has every goblin reached, touched at
as many different layers as possible (each hit layer tests the goblins), and stepping.

- **Why not the one-tile corridors.** In one-tile corridors, goblins block one another under
  rule (a), and at most 4 or 5 can be reached.
- **The board.** `adversarial.py` hill-climbs a **winding board**: eccentricity 14 from the
  adventurer, with detours around the goblins (`CAPPED_TERRAIN` in `fixtures.cairo`,
  instances 30 to 33).
- **What happens on it.** The flood runs its **15 layers**, and **all 8 goblins are reached**, at
  distances 1, 9, 10, 11, 12, 13, 14 and 15. Goblin 1 is hit and hits back; the 7 others step
  (`test_tick_capped_worst_case`, both sides).

| Tick | Layer array (start included) | Flood in memory | Tick in memory | Dojo call | Native call | Dojo tx (devnet) | Native tx (devnet) | Native / Dojo |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Worst case under D-127** (winding, 8 reached) | 16 | **1,005,344** | **1,592,793** | 13,539,287 | 3,303,993 | **18,940,800** | **5,156,800** | **0.27** |
| The same, goblins packed per instance | 16 | — | — | 6,955,549 | 3,118,653 | 8,887,680 | 5,036,800 | 0.57 |
| Part 1's fixture (comb) | 12 | 694,022 | 1,256,774 | 13,212,048 | 2,976,574 | 18,740,800 | 4,956,800 | 0.26 |
| Deepest board found, **capped** | 16 | 551,436 | — | 12,884,467 | 2,649,173 | 18,260,800 | 4,476,800 | 0.25 |
| Deepest board found, **unlimited** (fix loop 1) | 92 | 2,752,390 | 3,276,455 | 15,223,049 | 4,987,755 | 20,060,800 | 9,036,800 | 0.45 |
| Corridor maze, capped / unlimited | 16 / 45 | — | — | 12,784,512 / 13,562,705 | 2,549,218 / 3,327,411 | 18,180,800 / 18,620,800 | 4,396,800 / 4,836,800 | 0.24 / 0.26 |
| Expensive valid queue (10 moves), capped / unlimited | ≤ 16 / exhausted | — | — | 21,716,096 / 24,603,228 | 10,178,182 / 13,065,314 | 25,004,480 / 27,764,480 | 13,568,000 / 24,408,000 | 0.54 / 0.88 |

Notes on the table:
- D-127 counts distances (15); the layer array also holds the start (16), as the earlier sections count (the fixture's 12, the deep board's 92).
- The native in-memory tick figure is native's snforge run: 1,676,463 − 83,670.
- Unlimited figures are fix loop 1's, from the same code without the cap (`devnet-output-fixloop1-uncapped.txt`).
- All 85 transactions of this run succeeded (`devnet-output.txt`).
- The native tick checked (production form) costs the same 5,156,800 on devnet as unchecked: the owner check does not move this receipt (on part 1's fixture it added 40,000).

The cap makes the game's worst tick **5,156,800 natively, 1.03× part 1's fixture** (4,996,800
checked) instead of 1.8×. The deep and maze boards get cheaper than the fixture: their far goblins
now hold, and holding costs no step.

### 9.3 Scenarios and verdict with the capped tick

The money is in `spikes/SPK-2/money-devnet-output.txt` (`money_devnet.py`). Prices are those of
the summary (`prices-fixloop2-output.txt`). Every fight is the capped worst-case tick; native is
in production form (owner checked). The expedition is as in §3.3.

| Scenario | $ Dojo | $ native | Native / Dojo | Native × $0.50 | Break-even L2 gas price, native | $ per day, native |
|---|---:|---:|---:|---:|---:|---:|
| S1 worst case everywhere | 2.833 | **0.928** | 0.33 | **1.86** | 11.60 Gfri | 4.66 |
| S2 mixed (2/3 of the moves exploring) | 2.378 | **0.704** | 0.30 | 1.41 | 15.33 Gfri | 3.54 |
| S3 mixed, goblins packed per instance | 1.209 | **0.692** | 0.57 | 1.38 | 15.62 Gfri | 3.48 |
| S4 worst case everywhere, goblins packed | 1.451 | **0.914** | 0.63 | 1.83 | 11.78 Gfri | 4.59 |
| S5 every move near goblins in serpentine queues (capped) | 2.416 | **0.771** | 0.32 | 1.54 | 13.99 Gfri | 3.88 |

Uncapped, fix loop 1's S5 cost $1.348 natively. With the cap, the serpentine queue's walled-off
goblins hold, and **S1 is the worst scenario**.

**Verdict: ADR-0001's threshold does not hold for the native contracts at today's prices**, by
1.38× to 1.86×. ~~It would hold with fights at about 1.8M L2 gas.~~ *Withdrawn in fix loop 3
(C-6):* 1.8M is the equal-allocation reference, not a fight budget. With fights at 1,833,096, S1
still costs $0.635 and S4 $0.631. The scenario-specific fight budgets and the correlated case
are in §9.4. The other routes are an L2 gas price at or below 11.6 to 15.6 Gfri, or mainnet
metering these classes in Sierra gas well below devnet's VM resources (§8.6).

### 9.4 Fix loop 3 — what a fight would have to cost (C-6)

Computed by `money_devnet.py` from the same receipts and prices (`money-devnet-output.txt`); no
measurement changed.

- **Equal-allocation reference.** $0.50 / 300 = $0.001667 per action, which is 1,833,096 L2 gas
  with 832 L1 data gas per action. It is a yardstick for any single action, not a budget: the
  actions of an expedition do not cost the same.
- **Fight budget per scenario.** The fight L2 gas F at which the expedition costs exactly $0.50,
  every other transaction and every DA as measured:
  F = ($0.50 − others' USD − fights' DA USD) / (fights × L2 gas price × STRK × 10⁻¹⁸).

  | Scenario | Fights | Measured fight | Fight budget | Expedition with fights at 1,833,096 |
  |---|---:|---:|---:|---:|
  | S1 | 100 | 5,156,800 | **295,792** | 0.635 |
  | S2 | 100 | 5,156,800 | 2,836,494 | 0.412 |
  | S3 | 100 | 5,036,800 | 2,862,094 | 0.409 |
  | S4 | 100 | 5,036,800 | **340,592** | 0.631 |
  | S5 | 120 | 5,156,800 | 2,589,914 | 0.420 |

  The auditor's figures for S1 and S4 (about 295,792 and 340,592) are reproduced exactly. The
  auditor's $0.632 and $0.629 were computed at 1,800,000 L2 gas per fight, these at 1,833,096: both are correct, and the $0.003 between them is that difference ([GPT-6-Astra] re-audit, C-7).
- **Correlated case.** A queued move near goblins carries a tick. The tick's part of a transaction
  is taken as the slope of the checked queues with 8 goblins over 1, 5 and 10 moves:
  **1,659,874 L2 gas per tick**, the same for both layouts. That part is scaled by r in every
  fight (1 tick), every queued move near goblins (1 tick per move) and every "other" transaction
  (1 tick); in the serpentine queue it is capped at the queue's own cost. Exploring moves,
  enter, leave and the rest of each transaction are kept.

  | Scenario | Free ticks (r = 0) | r for $0.50 | Fight at that r |
  |---|---:|---:|---:|
  | S1 | $0.490 | 0.024 | 3,536,464 |
  | S2 | $0.441 | 0.223 | 3,867,741 |
  | S3 | $0.428 | 0.272 | 3,828,630 |
  | S4 | $0.475 | 0.057 | 3,471,397 |
  | S5 | $0.381 | 0.305 | 4,003,722 |

  The model is linear over receipts. The receipts are what is additive, but the linear split of
  a VM-resource fee (a weighted maximum) into a per-tick part and a rest is an assumption.
- **Conclusion.**
  - **Worst case (S1, S4).** Cutting the fight alone cannot reach $0.50. The fight budget
    (0.30M to 0.34M) is below the fight's own non-tick part in the model (about 3.5M), and even
    free ticks everywhere leave S1 at $0.490 and S4 at $0.475, just under.
  - **Mixed expeditions (S2, S3).** They pass with fights at 55 % to 57 % of today's, or with the
    tick's part at about a quarter of today's in every tick-bearing transaction.
