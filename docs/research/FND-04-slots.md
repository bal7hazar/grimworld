# FND-04 — What a changed storage slot costs, on our own receipts

Read on 2026-09-29 by `[Opus 5.5]`, from the traces of the 149 Sepolia transactions SPK-1 and SPK-1b
sent (the 7 of SPK-1's deployment, the 98 of its measurement, the 44 of SPK-1b), and from the local
node's traces of SPK-2's native entrypoints. **Reads only**: no account, no key, no Sepolia
transaction. Scripts and raw outputs: `spikes/FND-04/` (its `README.md`).

## Summary

| Question | Answer |
|---|---|
| **What a changed slot costs** | **It depends on whether the slot held a value.** A slot whose value was 0 before (a **new** slot) costs **453,524 L2 gas** (least squares over 23 shapes; controlled pairs 426,000 to 482,000, median 449,187.5). A slot that held a value and is overwritten or set to 0 costs **32,072** (least squares; pairs and single cases 20,000 to 80,000, median 33,333.3). Both are beyond the write's computation, once per slot and per transaction (§3, §4) |
| **Against quiver's 402,000** (D-135) | **Of the right size for a new slot, 12 times too high for an overwritten one.** Our new slot is 1.13× quiver's figure (1.06× to 1.20× over the pairs). Its excess over an overwrite, 421,452, is within 5 % of 402,000. None of the game's measured ticks and queues writes a new slot: they overwrite 2 to 10 |
| **Does it explain SPK-1 §4's residuals?** | **Largely, with a stated error.** The first unattributed residual splits into a constant, 5,120 per felt of calldata (measured by controlled pairs) and a state part (§2). The constant and the signature's price are **not separable** (every transaction has a 2-felt signature); `4,640 + 5,120 × 2` is an assumed normalisation of their identified sum, 14,880. Slot counts **predict** the state part with an error of up to 165,481 L2 gas (−2.6 %), ±8.4 % on the game's actions (§4). Events are not in it (§3) |
| **The differences between actions** | Queues and ticks differ by their calldata (5,120 a felt) and their overwritten slots. `enter` is higher by its **4 new slots** in `Instances` (SPK-1 §8.3's inference, now measured). SPK-1b's relayer case is higher by **one new slot, the SNIP-9 nonce** in the burner (SPK-1b §7.2's inference, now measured), and by 11 felts of calldata |
| **Zeroing and reuse** | `leave` sets 4 slots of the instance to 0. Each `enter` writes 4 new slots **under a new instance id**: the 45 enters of SPK-1 and SPK-1b wrote 180 distinct new keys, and no new write revisits a zeroed key (`reuse_check.py`). **No zero-then-rewrite of the same key was observed**, and no refund for zeroing was seen. That a reused key holding a value would be priced as an overwrite is an **extrapolation** from the overwrites measured; the saving needs **reused keys** (instance slots reused, a generation in the record), not merely stopping the zeroing |
| **SPK-2's native entrypoints** | The local node reports state diffs (starknet-devnet, RPC 0.10.2). Game slots per transaction: ticks 10 overwritten; queues 2 to 10 overwritten; `enter` 4 new and 2 overwritten; `leave` 4 zeroed and 1 overwritten; brewing a new pair 2 new and 3 overwritten; accepting a quest 1 new; claiming it 1 new and 2 overwritten. Every transaction also changes 2 slots of the fee token (§5) |

## 1. What was read, and how

- **The transactions.** Their hashes come from `spikes/SPK-1/deploy-output.txt`,
  `spikes/SPK-1/measure-output.txt` and `spikes/SPK-1b/ledger.jsonl`.
- **The reader.** `spikes/FND-04/trace.py` reads each transaction's trace
  (`starknet_traceTransaction`), receipt and body. It also reads the value of every changed slot
  at the block before (`starknet_getStorageAt`), to tell a new slot from an overwritten one.
  `rpc.py` refuses every method outside an explicit list of nine read methods.
- **The endpoint.** Of the four public Sepolia endpoints listed in `spikes/SPK-2/prices.py`, only
  `starknet-sepolia-rpc.publicnode.com` returns a trace's state diff (RPC 0.10.2):
  - Cartridge's (RPC 0.9.0) returns none;
  - drpc answered 400;
  - lava answered 410.
- **Redaction.** The owner's account address is replaced by `<ACCOUNT>` before anything is
  written, and its presence in the output fails the run.
  - The address appears as the sender, the payer's nonce, the Hub's admin and adventurer 3's
    owner in the game's storage.
  - The fee token's keys are replaced by labels, since a balance key derives from the holder's
    address.
- **Reproducible.** A second read gave the same 149 records, apart from the order in which the
  RPC lists a state diff (`compare_runs.py`).
- **The split of a receipt** (SPK-1 §4's method):
  - *invocations*: validate, execute (the account's `__execute__`, with the game call inside)
    and the fee transfer;
  - *res1*: the trace's total minus the invocations;
  - *res2*: the receipt minus the trace's total.
- **The slots**, by their value at the block before:
  - *new*: the value was 0;
  - *overwritten*: non-zero to non-zero;
  - *zeroed*: non-zero to 0.

Every repeat of an action gave identical figures and an identical state diff, with two exceptions
(`slots-output.txt` §1):
- **`setup board 31`.** Its first run wrote 76 new slots (43,273,315 L2 gas). The 19 resets after
  it overwrote 12 slots (9,161,315).
- **One of AVNU's `leave`s** (`0x34ee11cb…`, SPK-1b §3). It has the same state diff as the others,
  so the 160,000 of res1 and the 80,000 of validation it lacks are **not** explained by slots.
  Case D is metered by steps (SPK-1b §3) and is left out of the fit.

## 2. The first residual, decomposed

`res1 = 4,640 + 5,120 × (felts of calldata and signature) + state part`

This is an accounting identity: it **defines** the state part. Two of its terms are measured and
one is not:
- **5,120 per felt of calldata** is measured by controlled pairs (§3).
- **The constant and the signature's price are not separable.** Every transaction here carries a
  2-felt signature, so only their sum is identified: 4,640 + 2 × 5,120 = **14,880**. Pricing a
  signature felt like a calldata felt is an **assumed normalisation**. A free signature with a
  constant of 14,880 fits the same receipts. So do other constants: 640, 2,640, 4,640, 6,640 …
  (every 2,000) with the signature priced 5,120, or 880 … 14,880 … with it free (`slots-output.txt`
  §2).

| Shape (burner and owner give the same res1) | Felts | res1 | State part | Slots new / overwritten / zeroed |
|---|---:|---:|---:|---|
| Exploring queue, 10 moves | 20 | 247,040 | 140,000 | 0 / 4 / 0 |
| Queue of 1 move, 8 goblins | 11 | 400,960 | 340,000 | 0 / 11 / 0 |
| Worst tick under D-127 | 10 | 475,840 | 420,000 | 0 / 12 / 0 |
| Queue of 5 moves | 15 | 501,440 | 420,000 | 0 / 12 / 0 |
| Queue of 10 moves | 20 | 527,040 | 420,000 | 0 / 12 / 0 |
| `leave` | 7 | 260,480 | 220,000 | 0 / 3 / 4 |
| `enter` | 8 | 1,913,600 | 1,868,000 | 4 / 4 / 0 |
| `leave` through a relayer (C) | 18 | 798,800 | 702,000 | 1 / 3 / 4 |
| `enter` through a relayer (C) | 19 | 2,451,920 | 2,350,000 | 5 / 4 / 0 |
| Deploy the burner (`DEPLOY_ACCOUNT`) | 3 | 1,366,000 | 1,346,000 | 3 / 2 / 0 |
| A board set up the first time | 8 | 34,617,600 | 34,572,000 | 76 / 2 / 0 |
| The same board reset | 8 | 465,600 | 420,000 | 0 / 12 / 0 |
| The burner returns its STRK | 9 | 110,720 | 60,000 | 0 / 3 / 0 |

The slot counts include the fee token's 2 balances (the payer's and the sequencer's) in every
transaction. `slots-output.txt` §2 lists all 23 shapes.

- **Divisibility is an observation, not accuracy.** On all 23 shapes the state part happens to be
  a multiple of 2,000 under this normalisation: that describes these receipts. How well the slot
  counts *predict* the state part is a separate question, answered in §4 (largest error 165,481).
- **What the constant holds is not attributed**: every transaction also bumps one nonce.
- **What would identify the missing terms**, as controlled measurements:
  - the signature's price: the same call signed with signatures of different lengths (an account
    that accepts extra signature felts, or a multisig), everything else equal;
  - the constant: a transaction whose state diff is only the nonce and the fee token (a call that
    writes nothing), at two calldata lengths;
  - the per-slot spread: calls that write the same number of slots in one contract with keys near
    each other and far apart.
- **Declares** are left out. Their res1 grows with the class, not with slots: 777M for the Hub and
  1,820M for `Instances`, with 2 slots each.
- **res2** is 29,800 to 38,600 on every Sierra-metered transaction. It is outside this model and
  stays unattributed, as in SPK-1 (−5,800 on the first board setup, 0 or 40,000 in case D).

## 3. Controlled pairs: one thing differs

| Pair | What differs | Per unit (L2 gas) |
|---|---|---:|
| Queue of 10 − queue of 5 | 5 felts of calldata, same slots | **5,120** a felt |
| Queue of 5 − worst tick | 5 felts, same slots | 5,120 a felt |
| Worst tick − the same board reset | 2 felts, **one event more** (3 event felts) | 5,120 a felt; **0 for the event** |
| Deploy `Instances` − deploy Hub | 1 new slot | 442,000 |
| Fund the burner − give adventurer 3 back | 1 new slot (the burner's STRK balance) | 442,000 |
| Set up the hub − link the hub | 5 new slots | 426,000 each |
| Set up queue 18 − set up queue 21 | 64 new slots | 456,375 each |
| `leave` through a relayer − `leave` sent by the owner | 1 new slot, the SNIP-9 nonce, in a contract with no other change | 482,000 |
| `enter` through a relayer − `enter` sent by the owner | the same | 482,000 |
| Queue of 10 − queue of 1 | 1 overwritten slot | 80,000 |
| Queue of 10 − exploring queue | 8 overwritten slots | 35,000 each |
| `leave` − give adventurer 3 back | 4 zeroed slots | 30,000 each |
| The burner returns its STRK (alone) | 3 overwritten balances in one contract | 20,000 each |

- **The price of a slot is not constant.** An overwritten slot costs 20,000 to 80,000 depending on
  the transaction. A new slot costs 426,000 to 482,000; it is highest (482,000) when it is the only
  slot changed in its contract. So the cost depends on how the changed keys lie, not only on how
  many there are. That dependence is an observation: this read did not establish its rule.
- **Events** cost nothing in res1: their cost is inside the invocation that emits them.

## 4. The figure per slot our data supports

A least-squares fit of the state part on two prices, over the 23 Sierra-metered shapes
(`slots-output.txt` §4):

| Kind of slot | Controlled pairs: min / median / max | Least squares | quiver (D-135) |
|---|---:|---:|---:|
| **New** (its value was 0) | 426,000 / 449,187.5 / 482,000 | **453,524** | 402,000 |
| **Overwritten or zeroed** | 20,000 / 33,333.3 / 80,000 | **32,072** | — |

The medians are conventional (the mean of the two middle values when their number is even).

- **The fit's error** is at most 165,481 L2 gas (a setup of 14 new slots, −2.6 %). On the game's
  actions it is within ±8.4 %: the ticks and queues of 12 slots are 420,000 against 384,866 fitted.
- **quiver's figure** matches the new slot, not the overwritten one. Its quest completion
  (1.17M, "about 0.92M of which are two changed slots") reads as two new slots at about 460,000
  each, which is within the range above.
- **For ENG-01**, the first item of the budget is therefore two counts per transaction, not one:
  - the new slots it writes, at about **0.45M** each;
  - the slots it overwrites or zeroes, at about **0.03M** each (up to 0.08M).

## 5. SPK-2's native entrypoints on the local node

`devnet_trace.py` walks every block of the local node from genesis and reads each transaction's
state diff in order. The transactions are those of SPK-2's unchanged `devnet_measure.py`. A slot
is new when no earlier transaction of the run gave it a value, or the last one set it to 0.

| Entrypoint (SPK-2 label, native, owner checked) | Game slots new / overwritten / zeroed |
|---|---|
| Worst tick under D-127, one felt per goblin | 0 / 10 / 0 |
| Worst tick, goblins packed | 0 / 10 / 0 |
| Worst tick, a storage struct per goblin (11 slots each) | 4 / 17 / 0 |
| Queue of 10, 5 or 1 move, 8 goblins following | 0 / 10 / 0, 0 / 10 / 0, 0 / 9 / 0 |
| Exploring queue of 10 moves | 0 / 2 / 0 |
| Queue of 10 moves on the serpentine | 0 / 3 / 0 |
| Brew, a new pair (signed or not) | 2 / 3 / 0 |
| Brew, a known pair | 0 / 3 / 0 |
| Accept a quest | 1 / 0 / 0 |
| Claim a quest | 1 / 2 / 0 |
| `enter` | 4 / 2 / 0 |
| `leave` | 0 / 1 / 4 |

- **Every transaction also changes the fee token's 2 slots.**
- **The same shapes on both networks.** The ticks, queues, `enter` and `leave` change the same
  slots on the local node as on Sepolia: the 10 instance slots, `enter`'s 4 new ones and
  `leave`'s 4 zeroed.
- **The local node's gas is another meter** (SPK-2 §8.2): it is not used for the per-slot figure.

## 6. What this does not establish

- **The rule behind the spread.** Why an overwrite costs 20,000 in one transaction and 80,000 in
  another is not established here. It is consistent with a charge that follows the part of the
  storage tree a transaction touches (shared paths are cheaper), but that is an inference.
- **Other shapes.** Many new slots in many contracts at once, or an overwrite in a contract with
  thousands of keys, were not measured.
- **Mainnet.** Sepolia runs 0.14.4, mainnet ran 0.14.3 at SPK-1's reading. The same rule is
  expected there (SPK-1 §6); that was not checked.
- **The constant and the signature's price.** Only their sum, 14,880, is identified (§2); res2 is
  not split further.
- **A reused key.** No transaction wrote a key that an earlier one had zeroed or used: every
  `enter` writes under a new instance id (`reuse-check-output.txt`: 180 new keys, all distinct, 0
  revisits). That a key reused while holding a value costs an overwrite is an extrapolation.

## 7. Open questions

1. **The rule of the overwrite's price.** A trace read of a transaction built to vary only the
   distance between its keys would settle it. Until then ENG-01 budgets 0.03M per overwritten slot,
   with 0.08M as the worst seen.
2. **AVNU's cheaper `leave`** (SPK-1b §3) has the same state diff as the others. Its difference is
   not in the slots.
