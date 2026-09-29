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
| A constant of every transaction + its 2 signature felts, **together** (the aggregate) | 14,880 | **chosen normalisation, not measured** | FND-04 §2, §4.1: every aggregate congruent to 880 modulo 2,000, from 880 to 74,880, fits the same receipts with the same divisibility |
| — split as a constant 4,640 + 2 × 5,120 | — | chosen normalisation | FND-04 §2: a free signature with a constant of 14,880 fits the same receipts. The floor depends on the aggregate, not on its split |
| **A felt of calldata** | **5,120** | M | FND-04 §3: controlled pairs, exact |
| A multicall's header: the first call 4 felts (count, to, selector, length); **each further call 3** (to, selector, length) | 20,480, then **15,360** a call | D | the account's calldata layout × 5,120 |
| **A new storage slot** (its value was 0 before the transaction) | **453,524** | M, fitted under the 14,880 convention | FND-04 §4: least squares over 23 shapes; pairs 426,000 to 482,000; 452,808 to 453,691 under every admissible aggregate (§4.1) |
| **An overwritten or zeroed slot** | **32,072** | M, fitted under the 14,880 convention | FND-04 §4: least squares; pairs 20,000 to 80,000; 24,878 to 33,751 under every admissible aggregate (§4.1) |
| An event | 0 beyond its emitting call | M | FND-04 §3 |
| **The floor of a burner transaction**: fixed part + constant + 6 felts (signature, the header of one call) + the fee token's 2 balances | **816,939** | D, under the 14,880 convention | the lines above. 815,419 to 818,459 under the aggregates 2,000 either side; 806,297 to 862,551 under every admissible one (FND-04 §4.1) |
| The L1 data gas | under 1 % of these transactions at today's price | M | SPK-1 §6 |

**A transaction of the game costs**

```
L2 gas ≈ 816,939                                 the floor (D, under the 14,880 convention)
       + game computation                        the calls, their storage reads and writes as syscalls
       + 5,120 × felts of arguments               beyond the header of one call; + 3 felts per further call
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
- **Zeroing a slot earned nothing back** in any receipt read.
- **Every `enter` writes 4 new slots under a new instance id** (M). The 45 enters read wrote 180
  distinct new keys. No zero-then-rewrite was observed, and no instance key was recycled between
  enters (FND-04, `reuse-check-output.txt`).
- **The saving needs reused keys**, not merely stopping the zeroing: instance slots reused, with a
  generation in the record. No instance key was recycled in the transactions read. Pricing a reused key holding a value as
  an overwrite is an **extrapolation (E)**: 4 × 421,452 = about 1.7M less per `enter`.

## 2. Budgets per kind of transaction

The *game slots* do not count the fee token's 2 balances, which are in the floor.

| Kind | **Budget, L2 gas** | **Game slots: new / overwritten or zeroed** | What the budget rests on | Kind | To measure it |
|---|---:|---|---|---|---|
| **A played batch** (`play`, weight ≤ 10, design/02) | **40,000,000** | **0 / ≤ 16**; new only for revealed chunks (see *A revealed chunk*) | design/02's target. 10 worst ticks, each as measured alone: 36.98M (E). The chunked map's overhead (below) at each tick: 37.63M to 44.18M (E) | Budget E; parts M | ENG-01's `play` on Sepolia, traced with `spikes/FND-04/trace.py` |
| — the chunked map's overhead, per tick | 65,224 to 720,000 | — | **The window follows the adventurer and is assembled at every tick** (D-120, ADR-0006). 65,224 is the assembly in memory (snforge, M). 720,000 is SPK-7's whole-transaction difference A − S on a one-tick transaction (local meter, M): chunk reads, assembly and storage effects together. Inside a batch, cached chunk reads and slots changed once per transaction may bring it toward the lower figure; how far is **not measured** | E | `play` with the chunked window on Sepolia: cached reads, assembly, updates and slots per transaction apart |
| — one tick inside a batch (game call, window included) | **3,851,631** | — | (40M − floor − 16 slots − 30 felts) / 10. Measured alone: 3,564,913 (SPK-1 §4) without the window | D | the same |
| — one tick inside a batch, the **expedition's target** | **1,469,435** | — | What S1 needs for $0.50 (§3). A move inside a queue costs 1,467,187 against 3,326,336 alone (SPK-1: the queue reads and writes the instance once) | E | the same |
| **A move-only `play` batch** (10 moves near goblins; under design/02 planned moves are queued on the client and join `play`) | **17,400,000** | **0 / 10** | The spike's movement benchmark, SPK-2's `walk` of 10 moves, 8 goblins following: 17,306,703 with the burner (D). With its 14 argument felts replaced by 30 (3 a move): 17,388,623 (E). Exploring (no goblin): 2,446,355, 0 / 2 (D) | E | ENG-01's `play` with moves only, traced |
| **Enter** (its entry draw included) | **3,600,000** | **4 / 2** | 3,555,447 with the burner; 4 new slots under a new instance id | M (SPK-1b) | — |
| — enter, if its instance slots are **reused keys** (a generation in the record) | **1,900,000** | 0 / 6 | 1,869,639: the same with its 4 new slots priced as overwrites. No instance key was recycled between enters | E (extrapolation) | a layout that reuses keys, traced |
| **Leave** | **1,700,000** | **0 / 5** (4 zeroed) | 1,659,915 with the burner | M (SPK-1b) | — |
| **A Fate action**, sent alone (a loot, a chest, an identification: design/02, ADR-0002 rule 3). **Not the entry draw: `enter` has its own budget above** | **2,900,000** | **≤ 2 / ≤ 4** | Floor + a call of about 1.0M (the order of `enter`'s 0.93M) + 2 new slots for what it gives + 4 others: 2,852,275 | E: not measured | ENG's first Fate entrypoint on Sepolia, traced |
| **A revealed chunk**, inside a batch at weight 2 | **2,500,000 a chunk** | **1 new a chunk**, and the revealed bitmap once per transaction: **new** at the instance's first reveal, **overwritten** after | Generation 0.39M to 0.45M in memory (SPK-7). **SPK-7's observed layout**: `reveal` writes the terrain slot of each chunk (new) and the revealed bitmap once; no occupancy. Slots on Sepolia's prices (D): 1 chunk 907,048 at the first reveal, 485,596 after; 3 chunks 1,392,644 after. One chunk revealed alone: 2,455,200 on the local node; three: 5,919,680 (SPK-7, local meter) | E | ENG-05 on Sepolia, traced |
| — if a future layout also writes an occupancy slot per chunk at reveal | +453,524 a chunk | +1 new a chunk | **An assumption**: SPK-7 writes occupancy only when goblins move | E | the same |
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
   - A new key costs about 0.45M whatever follows. Only **reused keys** (instance slots reused,
     a generation in the record) turn later writes into overwrites; that price for them is an
     extrapolation (E).
2. **A batch changes each slot once per transaction.** Its storage part is paid once in any case.
   Its read and write syscalls are paid once only if the batch keeps the instance in memory between
   its actions, as the queue does.
3. **The window is still assembled at every tick** (D-120). What a batch can do once is read the
   chunks (PLAN ENG-07: read chunks once per batch) and change their slots once. Assembly and
   updates stay per tick. Their costs are to be measured apart (§2); the batch figure stays an
   estimate until then.
4. **Arguments are cheap, calls are not.**
   - An action encoded in 3 felts costs 15,360.
   - A further call in the same transaction costs its 3 header felts (15,360), where a second
     transaction costs a floor (816,939).

## 3. The expedition: $0.50 for 300 actions (D-129)

SPK-1 §5's expedition:
- **S1:** 36 queues of 5 moves near goblins, 100 fights, 20 other actions (a move alone near
  goblins), `enter`, `leave`;
- **S2:** 12 queues of 5 near goblins and 12 exploring queues of 10, the rest as S1.

Zero tip, the prices of §1.

| Case | Kind | S1 L2 gas | **S1 $** | S1 × $0.50 | S2 L2 gas | **S2 $** | S2 × $0.50 |
|---|---|---:|---:|---:|---:|---:|---:|
| One action per transaction, owner's account (SPK-1 §5: a projection of measured receipts) | D | 986.7M | 0.874 | 1.75 | 772.9M | 0.685 | 1.37 |
| One per transaction, the burner | D | 928.2M | 0.823 | 1.65 | 718.9M | 0.638 | 1.28 |
| Fights in batches of 10, each tick as measured alone, without the batch's argument felts (D-137's estimate, reproduced) | E | 820.6M | 0.725 | 1.45 | 611.3M | 0.540 | 1.08 |
| The same with the 27 argument felts of each batch's 9 further actions | E | 822.0M | **0.726** | 1.45 | 612.7M | **0.541** | 1.08 |
| Fights in batches of 10, the instance read and written once per batch | E | 654.7M | 0.579 | 1.16 | 445.4M | **0.394** | 0.79 |
| And the moves near goblins in tens (priced as the queue of 10) | E | 608.2M | **0.537** | 1.07 | 429.9M | 0.380 | 0.76 |

**The arithmetic.**
- A fight batch = 10 × the tick's call + the tick's non-game remainder with the burner
  (1,194,875, D), once, + 27 argument felts.
  - **The assumption that makes every batched row E**: a batch keeps **one** tick's state
    remainder and one tick's DA footprint (832 L1 data gas), as if its 10 ticks changed the same
    12 slots once.
  - The 27 felts are 3 for each of the 9 further actions, also an assumption: 138,240 a batch,
    1,382,400 per expedition. D-137's estimate left them out; the row above includes them. The
    cheaper rows below include them too.
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
- S1's 36 queues of 5 near goblins cost 358.0M (D). Their share of S1 once fights are batched:
  - **43.554 %** with each tick as measured and the 27 felts (E);
  - **54.685 %** with the batch's reads and writes shared (E).

  Either way, the moves near goblins weigh about as much as the fights.
- **Break-even L2 gas price**, fights batched and shared (E): **18.4 Gfri** for S1 and 27.1 for S2.
  Today it is 21.3; it ranged 19.6 to 30.8 over the fortnight before SPK-1.

## 4. What the budgets leave out

| | |
|---|---|
| The window of the real game | SPK-2's tick holds its board in one slot. The chunked map adds 65,224 (assembly in memory) to 720,000 (SPK-7's whole-transaction difference, local meter) a tick; not measured on Sepolia, nor inside a batch |
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
| CB-3 | design/02's 37.3M and 40M leave out the chunked map's per-tick overhead. With it, a worst batch as measured is 37.6M to 44.2M (§2, E). Whether 40M holds depends on how much of SPK-7's 720,000 a batch pays once (cached chunk reads, slots changed once) and how much per tick (assembly, updates). A measurement of `play` with the chunked window decides it, or the weights move |
| CB-5 | A recycled instance key's price: no zero-then-rewrite was observed, and no instance key was recycled between enters (keys holding a value were overwritten many times: they price the other slot). `enter`'s 1.9M budget with reused keys is an extrapolation until a layout with a generation in the record is traced |
| CB-4 | The rule behind an overwrite's spread (FND-04 §7): a layout that groups its keys may pay the low end |
