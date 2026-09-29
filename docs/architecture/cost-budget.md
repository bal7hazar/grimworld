# Cost budget — what ENG-01 designs to

| | |
|---|---|
| Status | Budgets set by FND-04 (2026-09-29) from the Phase 0 measurements. A budget is a design target, not a decision: the decisions are D-129, D-133 and D-137 |
| For | ENG-01 (interfaces, storage layouts, events), then every lot with an entrypoint |
| Rules applied | D-129 #3: ENG-01 carries a cost budget. D-133: fights are played on the client and sent in batches, 10 to start with. **D-137: every budget is written for a burner sending directly (OpenZeppelin `AccountUpgradeable` v3.0.0), funded by the game, no paymaster.** design/02 OP-2: count slots, not only gas |
| Arithmetic | `spikes/FND-04/budget.py` → `budget-output.txt`; the slot figures from `analyse.py` → `slots-output.txt` ([research](../research/FND-04-slots.md)) |

Every figure is marked:
- **M**: measured, with its source;
- **D**: derived from measurements by arithmetic only;
- **E**: an estimate that rests on a stated assumption. The *To measure it* column says what would
  replace an E with an M.

## 1. The prices of a transaction

| Item | L2 gas | Kind | Source |
|---|---:|---|---|
| The burner's fixed part: validation 87,805, its own execution 141,670, the fee transfer 455,360, the second residual 32,600 | **717,435** | M | SPK-1b §1, Sepolia |
| A constant of every transaction | 4,640 | M | FND-04 §2 |
| **A felt of calldata or signature** | **5,120** | M | FND-04 §3: controlled pairs, exact |
| **A new storage slot** (its value was 0 before the transaction) | **453,524** | M | FND-04 §4: least squares over 23 shapes; pairs 426,000 to 482,000 |
| **An overwritten or zeroed slot** | **32,072** | M | FND-04 §4: least squares; pairs 20,000 to 80,000 |
| An event | 0 beyond its emitting call | M | FND-04 §3 |
| **The floor of a burner transaction**: fixed part + constant + 6 felts (signature, the header of one call) + the fee token's 2 balances | **816,939** | D | the lines above |
| The L1 data gas | under 1 % of these transactions at today's price | M | SPK-1 §6 |

**A transaction of the game costs**

```
L2 gas ≈ 816,939                                 the floor (D)
       + game computation                        the calls, their storage reads and writes as syscalls
       + 5,120 × felts of arguments               beyond the header of one call; + 4 felts per extra call
       + 453,524 × new game slots
       + 32,072  × overwritten or zeroed game slots
```

- **Checked on the burner's receipts:** `leave` 1,664,419 against 1,659,915 measured (+0.3 %);
  `enter` 3,629,831 against 3,555,447 (+2.1 %) (`budget-output.txt`).
- **Dollars:** `$ = (L2 gas × 21,345,234,918 + L1 data gas × 980,202,556,584) × 10⁻¹⁸ × $0.04125403`.
  These are mainnet's prices of SPK-1 §5 (2026-09-28). 1M L2 gas = **$0.000881**.
- **The threshold in gas:** $0.50 for 300 actions is **567.8M L2 gas** per expedition, 1.89M per
  action on average (D, D-129).

**What the prices mean for a layout.**
- A new slot costs as much as **14 overwritten slots**, or **89 felts** of calldata.
- A slot freed by zeroing it earns nothing back and becomes new again. `leave` zeroes 4 slots
  and the next `enter` pays them as 4 new slots: about 1.7M more than overwriting them would cost
  (D).

## 2. Budgets per kind of transaction

The *game slots* do not count the fee token's 2 balances, which are in the floor.

| Kind | **Budget, L2 gas** | **Game slots: new / overwritten or zeroed** | What the budget rests on | Kind | To measure it |
|---|---:|---|---|---|---|
| **A played batch** (`play`, weight ≤ 10, design/02) | **40,000,000** | **0 / ≤ 16**; new only for revealed chunks: 2 each | design/02's target. 10 worst ticks, each as measured alone: 36.98M. With the window assembled from chunks at each tick (SPK-7: +0.72M a tick, local node): **44.18M, over the target** | Budget E; parts M | ENG-01's `play` on Sepolia, traced with `spikes/FND-04/trace.py` |
| — one tick inside a batch (game call, window included) | **3,851,631** | — | (40M − floor − 16 slots − 30 felts) / 10. Measured alone: 3,564,913 (SPK-1 §4) without the window | D | the same |
| — one tick inside a batch, the **expedition's target** | **1,469,435** | — | What S1 needs for $0.50 (§3). A move inside a queue costs 1,467,187 against 3,326,336 alone (SPK-1: the queue reads and writes the instance once) | E | the same |
| **A planned queue** (`walk` of ≤ 10 moves, design/02's stop conditions) | **17,400,000** | **0 / 10** | 10 moves, 8 goblins following: 17,306,703 with the burner. Exploring (no goblin): 2,446,355, 0 / 2 | D | — |
| **Enter** | **3,600,000** | **4 / 2** | 3,555,447 with the burner, 4 new slots in the instance | M (SPK-1b) | — |
| — enter, with the instance's slots never zeroed | **1,900,000** | 0 / 6 | The same with its 4 new slots overwritten instead | E | a layout that reuses them, traced |
| **Leave** | **1,700,000** | **0 / 5** (4 zeroed) | 1,659,915 with the burner | M (SPK-1b) | — |
| **A Fate action**, sent alone (a loot, a chest, an identification, the entry draw: design/02, ADR-0002 rule 3) | **2,900,000** | **≤ 2 / ≤ 4** | Floor + a call of about 1.0M (the order of `enter`'s 0.93M) + 2 new slots for what it gives + 4 others: 2,852,275 | E: not measured | ENG's first Fate entrypoint on Sepolia, traced |
| **A revealed chunk**, inside a batch at weight 2 | **2,500,000 a chunk** | **2 / 1** a chunk | Generation 0.39M to 0.45M in memory (SPK-7). SPK-7's layout writes 2 slots per chunk (terrain, occupied), new, and the revealed set once (0.94M on Sepolia's slot prices, D). One chunk revealed alone: 2,455,200 on the local node; three: 5,919,680 (SPK-7, local meter) | E | ENG-05 on Sepolia, traced |
| **A hub action** (ENG-01 defines them) | **2,000,000** | **≤ 1 / ≤ 4** | Estimated from SPK-2's native entrypoints: accept a quest 1.57M (1 / 0); claim it 1.82M (1 / 2); brew a known pair 1.50M (0 / 3) | E | the hub's entrypoints on Sepolia, traced |
| — a hub action that registers a discovery (brewing a new pair) | **2,800,000** | **2 / 3** | Estimated at 2.71M (the same method) | E | the same |
| The burner's deployment (once per burner) | 2,168,115 | 3 / 0 in the burner | `DEPLOY_ACCOUNT` of SPK-1b | M | — |
| Funding a burner (a STRK transfer by the game; once, then top-ups) | about 1,710,000 | 1 / 0 in the fee token (its first balance) | The burner's own STRK transfer back to the owner, 1,285,115 (M, SPK-1b), with the recipient's balance new instead of overwritten: 1,706,567. A top-up overwrites: about 1.29M | E | ADR-0005's funding path |

The hub estimates take snforge's call × 1.157 (the median Sepolia/snforge ratio of SPK-1 §3's
light actions), plus the floor, 3 felts of arguments and the slots the local node's traces show
(`budget-output.txt`).

**Rules the budgets imply for ENG-01** (from the prices; ENG-01 decides the layout):
1. **Count new slots first.**
   - A transaction of play writes no new slot, except for revealed chunks.
   - Storage that play reuses is never set to 0: an occupied flag or a generation counter frees it
     instead.
2. **A batch reads and writes each slot once.** Its storage part is paid once per transaction in
   any case. Its syscalls too, if the batch keeps the instance in memory between its actions, as the
   queue does.
3. **The window is assembled once per batch** when it can be (PLAN ENG-07 already says: read chunks
   once per batch). Assembled at each tick, it takes a worst batch over 40M.
4. **Arguments are cheap, calls are not.**
   - An action encoded in 3 felts costs 15,360.
   - A second call in the same transaction costs its 4 header felts (20,480), where a second
     transaction costs a floor (816,939).

## 3. The expedition: $0.50 for 300 actions (D-129)

SPK-1 §5's expedition:
- **S1:** 36 queues of 5 moves near goblins, 100 fights, 20 other actions (a move alone near
  goblins), `enter`, `leave`;
- **S2:** 12 queues of 5 near goblins and 12 exploring queues of 10, the rest as S1.

Zero tip, the prices of §1.

| Case | Kind | S1 L2 gas | **S1 $** | S1 × $0.50 | S2 L2 gas | **S2 $** | S2 × $0.50 |
|---|---|---:|---:|---:|---:|---:|---:|
| One action per transaction, owner's account (SPK-1 §5) | M | 986.7M | 0.874 | 1.75 | 772.9M | 0.685 | 1.37 |
| One per transaction, the burner | D | 928.2M | 0.823 | 1.65 | 718.9M | 0.638 | 1.28 |
| Fights in batches of 10, each tick as measured alone (D-137's estimate, reproduced) | D | 820.6M | **0.725** | 1.45 | 611.3M | **0.540** | 1.08 |
| Fights in batches of 10, the instance read and written once per batch | E | 654.7M | 0.579 | 1.16 | 445.4M | **0.394** | 0.79 |
| And the moves near goblins in tens (priced as the queue of 10) | E | 608.2M | **0.537** | 1.07 | 429.9M | 0.380 | 0.76 |

**The arithmetic.**
- A fight batch = 10 × the tick's call + the tick's non-game remainder with the burner (1,194,875,
  D), once. The storage part of the remainder is paid once per batch: D-137's "not counted"
  slots are counted, since a tick's 12 slots are in that remainder.
- "Read and written once" assumes a tick shares what a walk shares:
  - the part of a queue's call it pays only once, 1,859,149 (queue of 1 minus a marginal move,
    D);
  - so a tick inside a batch costs 1,705,764 (E).

**What it says.**
- **The mixed expedition meets $0.50** if a batch shares its reads and writes as the queue does
  (E).
- **The worst one does not yet.** It needs its moves near goblins in tens and a tick inside a
  batch of **1.47M on average** (E). Measured alone, the tick is 3.56M; shared as a walk, it
  would be 1.71M.
- S1's 36 queues of 5 near goblins are **55 %** of its total once fights are batched (D): the
  moves near goblins weigh as much as the fights.
- **Break-even L2 gas price**, fights batched and shared (E): **18.4 Gfri** for S1 and 27.1 for S2.
  Today it is 21.3; it ranged 19.6 to 30.8 over the fortnight before SPK-1.

## 4. What the budgets leave out

| | |
|---|---|
| The window of the real game | SPK-2's tick holds its board in one slot; the chunked map's window adds 0.72M a tick on the local meter (SPK-7), not measured on Sepolia |
| The real tick | Line of sight, skills, conditions and the real storage layout are not in SPK-2's contracts (SPK-1 §6) |
| The spread of an overwrite | 20,000 to 80,000 depending on the transaction (FND-04 §3); the budgets use the fit, 32,072 |
| A paymaster | None before version 1 (D-137); with one, the fixed part is 2.2× to 5.1× the burner's (SPK-1b) |
| The data price | Under 1 % today; a tenth of the worst tick's cost only at about 15 Tfri (SPK-1 §6) |
| The cost of an active player per day | Needs the hub's entrypoints (ENG-01) and a day's composition: in front of the business model (Q-10), D-133 #3 |

## 5. Open

| # | Question |
|---|---|
| CB-1 | **"Power" in PLAN's FND-04 row**, a power budget of the adventurer: out of this task's scope (brief); left open for the design |
| CB-2 | Does a tick inside a batch share its reads and writes as the walk does? The figure of 1.71M a tick is an estimate; ENG-01's `play` on Sepolia measures it |
| CB-3 | design/02's 37.3M and 40M leave out the window from chunks; with it, a worst batch as measured is 44.2M (§2). ENG-07's "read chunks once per batch" is needed for 40M, or the weights move |
| CB-4 | The rule behind an overwrite's spread (FND-04 §7): a layout that groups its keys may pay the low end |
