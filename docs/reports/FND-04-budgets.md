# [Opus 5.5] FND-04 — Spike results into the ADRs, and the cost budget ENG-01 designs to

## Summary

Pull request: https://github.com/bal7hazar/grimworld/pull/71 (CI green, not merged). The model I
run as is Opus 5.5 (`claude-opus-5-5`), as the brief names.

What exists now:
- **The slot count on our own receipts** (`spikes/FND-04/`, reads only). I read the traces,
  receipts and state diffs of all 149 Sepolia transactions of SPK-1 (7 deployment, 98
  measurement) and SPK-1b (44), and each changed slot's value at the block before. The local
  node's state diffs of SPK-2's native entrypoints are read too.
- **The per-slot figure depends on whether the slot held a value:**
  - **a new slot** (value 0 before): **453,524 L2 gas** (least squares over 23 shapes; controlled
    pairs 426,000 to 482,000, median 456,375);
  - **an overwritten or zeroed slot: 32,072** (least squares; 20,000 to 80,000, median 33,333).
- **quiver's 402,000 is of the right size for a new slot** (1.13×; the excess of a new slot over
  an overwrite, 421,452, is within 5 % of it). It is **12.5× too high for an overwrite**, and the
  game's measured ticks and queues write no new slot.
- **SPK-1 §4's first residual is explained exactly:**
  - it is 4,640 + 5,120 per felt of calldata and signature + a state part;
  - the state part is a multiple of 2,000 L2 gas on every shape;
  - events cost nothing in it.
- **The differences between actions, now measured rather than inferred:**
  - `enter`'s 1.9M is its **4 new slots** (SPK-1 §8.3);
  - SPK-1b's relayer extra is **one new slot, the SNIP-9 nonce** (SPK-1b §7.2);
  - `leave` zeroes 4 slots, and the next `enter` pays them again as new slots.
- **`docs/research/FND-04-slots.md`** holds the slot tables, pairs, fit and spread.
- **`docs/architecture/cost-budget.md`** gives the prices of a transaction and a budget in L2 gas
  and in slots (new / other) for every kind of transaction. Each figure is marked M / D / E.
  - Every budget is written for the burner sending directly, in batches of 10 (D-137).
  - Each E row says what would measure it.
  - The expedition arithmetic reproduces D-137's $0.725 / $0.540 and gives the conditions for
    $0.50.
- **ADR-0001, 0005, 0006 and 0007** each gain a *Measured* section: figures and sources, no
  decision changed.

## Files changed

- `spikes/FND-04/rpc.py`: a read-only JSON-RPC client with an explicit allowlist of 9 read methods.
- `spikes/FND-04/trace.py`: reads the 149 Sepolia transactions and redacts the owner's address, failing if it would be written.
- `spikes/FND-04/traces.jsonl`: its raw output (149 records).
- `spikes/FND-04/compare_runs.py`: compares two reads; the second reproduced the first.
- `spikes/FND-04/devnet_trace.py`: the local node's state diffs, walked from genesis.
- `spikes/FND-04/devnet-output.txt`: its raw output.
- `spikes/FND-04/analyse.py` → `slots-output.txt`: the slot tables.
- `spikes/FND-04/budget.py` → `budget-output.txt`: the budget arithmetic.
- `spikes/FND-04/README.md`: files and commands.
- `docs/research/FND-04-slots.md`: new.
- `docs/architecture/cost-budget.md`: new.
- `docs/architecture/ADR-0001-execution-layer.md`: a *Measured* section (latency, meter, fixed part, slots, threshold, batches).
- `docs/architecture/ADR-0005-accounts.md`: a *Measured* section (the burner on cost, relayer, AVNU, SNIP-9 nonce, deploy and funding).
- `docs/architecture/ADR-0006-chunked-maps.md`: a *Measured* section (SPK-7's costs, R-12 conditional on batches, the window against 40M).
- `docs/architecture/ADR-0007-native-starknet.md`: a *Measured* section (native against Dojo, the fixed part, the storage prices, NS-1, the indexer).

## Commands run

- **The endpoints** (a probe, since deleted). The four public Sepolia endpoints of
  `spikes/SPK-2/prices.py` answered as follows; only publicnode returns a state diff:
  - `api.cartridge.gg` (spec 0.9.0): a trace without `state_diff`;
  - `starknet-sepolia-rpc.publicnode.com` (spec 0.10.2): with `state_diff`;
  - `drpc` 400, `lava` 410.
- `python3 spikes/FND-04/trace.py` (three attempts):
  - the first stopped at the UDC deploy: `Contract not found` for a slot read in a contract
    deployed by that transaction; now read as 0;
  - the second was stopped by its own redaction guard: `refused: the owner's address would be
    written`. The Hub stores the address as admin and as the adventurer's owner, so values are now
    redacted too;
  - the third: `transactions: 149 (SPK-1 deploy 7, SPK-1 measure 98, SPK-1b 44)` … `redaction
    check: the owner's address is in no line of traces.jsonl`.
- A second full read, after adding the events' felt counts:
  `git show HEAD:spikes/FND-04/traces.jsonl | python3 compare_runs.py traces.jsonl` gave
  `records 149 / 149; differing once the order is ignored: 0`.
- `scripts/with-node.sh python3 spikes/SPK-2/native/devnet.py …` failed: `Failed to deserialize
  param #3`. That script is stale against the production-form `attack`; SPK-2's later
  `devnet_measure.py` is current.
- `scripts/with-node.sh bash -c 'python3 spikes/SPK-2/devnet_measure.py > .with-node/spk2.jsonl;
  python3 spikes/FND-04/devnet_trace.py .with-node/spk2.jsonl' > spikes/FND-04/devnet-output.txt`
  gave `{"step": "done", "blocks": 197, "measured_transactions_traced": 85,
  "measured_transactions_listed": 85}`. The native side has 33 entrypoints with state diffs.
- `python3 spikes/FND-04/analyse.py > spikes/FND-04/slots-output.txt`:
  - the fit: `new slot 453,524, overwritten or zeroed slot 32,072`; largest error 165,481 (−2.6 %);
  - pairs: calldata `5,120` a felt (exact, twice); an event 0; new slots 442,000 / 442,000 /
    426,000 / 456,375 / 482,000 / 482,000; overwrites 80,000 / 35,000 / 30,000 (zeroed) / 20,000 /
    33,333.
- `python3 spikes/FND-04/budget.py > spikes/FND-04/budget-output.txt`:
  - the floor of a burner transaction: 816,939;
  - the model against the burner's receipts: `leave` +0.3 %, `enter` +2.1 %;
  - the expedition: S1 $0.874 (M) → $0.823 (burner, D) → **$0.725** (batched fights, D; D-137's
    figure) → $0.579 (batch shares its reads and writes, E) → $0.537 (and moves in tens, E);
  - S2: $0.685 → $0.638 → **$0.540** → **$0.394** → $0.380;
  - for S1 to meet $0.50, a tick inside a batch must average 1,469,435.
- `git diff origin/main..HEAD | grep -c -i <the owner's address>` → `0`. `git diff --check` is
  clean.
- `gh pr checks 71 --watch --interval 30`: every check passed (cairo × 8, client, tooling,
  discover). The last head, `2bc9c54`, has both workflow runs `completed` / `success`.

## Cost

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | No Cairo in this lot |

## Acceptance criteria

- **AC-1: met.**
  - `slots-output.txt` §1 lists every group of the 149 transactions: receipt, invocations, res1,
    res2, felts, and slots new / overwritten / zeroed per contract, nonces.
  - §4–5 give the per-slot figure against quiver's 402,000, with its spread.
  - The script (`trace.py`, `analyse.py`) and the raw output (`traces.jsonl`) are committed.
- **AC-2: met.** The four ADRs each have a *Measured* section with a source on every row. Nothing
  in their Decision or Status was edited (`git diff origin/main -- docs/architecture/ADR-*`
  shows added sections only).
- **AC-3: met.**
  - `cost-budget.md` §2 gives every kind of transaction (batch, tick inside a batch, planned
    queue, enter, leave, Fate action, revealed chunk, hub action, deploy and funding of a burner)
    a budget in L2 gas and in slots, each marked M, D or E.
  - §3 gives the expedition's arithmetic to dollars at the stated prices (`budget.py`).
- **AC-4: met.**
  - No credential was read or needed; the Sepolia variables were not used.
  - `rpc.py` refuses every method outside its read list.
  - No file of this task can send. The local node's transactions are sent by SPK-2's unchanged
    `devnet_measure.py`, on the throwaway node, from its pre-funded seed-0 account (see
    Deviations).

## Deviations from the brief

- **Local transactions for the devnet part.** The brief asks for SPK-2's native entrypoints'
  slots "by the same trace read on devnet". That needs transactions on the local node, so I ran
  SPK-2's existing, unchanged `devnet_measure.py` under `scripts/with-node.sh`. It sends only to
  the throwaway node, from devnet's public seed-0 account. My reader only reads. I read "no sending
  code of any kind" as covering the task's own files and Sepolia; if the orchestrator reads it more
  strictly, the devnet table (research §5) is the part that relied on it.
  - The run also executed that script's Cairo 2.13 build and Dojo parts. Their outputs are not
    used.
- **More transactions than "measured" ones.** All 149 of SPK-1's and SPK-1b's transactions were
  read, not only the measured 74 + 43: setups and deployments give the new-slot pairs.
- **The endpoint.** Only one of `prices.py`'s endpoints returns state diffs, publicnode; the others
  were not usable.

## Escalations

1. **The owner's account address was shown once in my session's output** (not in the repository).
   - How: the first probe printed a raw state diff, whose nonce entry is the sender's address.
     That output is in this session's transcript and possibly the agent's log.
   - Where it is not: in no committed file (checked with `grep` on the whole diff: 0).
   - What followed: the probe was deleted, and the reader redacts before printing or writing.
   - It is a public address on chain (anyone can read a transaction's sender from its hash), but
     OPERATIONS §7 says it is recorded nowhere. The orchestrator may want to check the log.
2. **design/02 § Size** (not in my allowlist):
   - its 37.3M and 40M leave out the window assembled from chunks (SPK-7: +0.72M per tick, local
     meter);
   - a batch of 10 worst ticks with the window at each tick is about 44.2M (E);
   - OP-2 can now be answered from `cost-budget.md`: slots are counted, with a price per new slot
     and one per other slot.
3. **PLAN's ENG-01 row and D-135's "For the game" row** say "about 402,000 L2 gas per changed
   slot". On our receipts that holds for a **new** slot only; an overwritten one is about 32,000.
   The wording belongs to the orchestrator and the project manager (shared files).
4. **SPK-2's `native/devnet.py` is stale**: its `attack` calldata fails against the
   production-form contract. `devnet_measure.py` is current. A note in SPK-2's README would save
   the next agent the attempt.

## Open questions

1. **"Power"** in PLAN's FND-04 row, a power budget of the adventurer: out of scope by the brief,
   listed as CB-1 in `cost-budget.md`.
2. **Does a tick inside a batch share its reads and writes as a walk does?** The $0.50 path for S1
   rests on it (E; CB-2). ENG-01's `play` on Sepolia, read with `trace.py`, measures it.
3. **The rule of an overwrite's price** (20,000 to 80,000): not established. It is consistent with
   a charge that follows the storage tree's shared paths, an inference (research §6–7).
4. **AVNU's cheaper `leave`** (SPK-1b §3): the same state diff as the others, so its 160,000 of
   res1 is not in the slots.

## Fix loop 1

The `[GPT-6-Astra]` audit of PR 71: FAIL, 4 majors, 6 minors. Fixed in four new commits on the same
branch, no force-push:
- `origin/main` merged first (a merge commit);
- `68d27ed`: `analyse.py`;
- `fbc6dcf`: `budget.py`;
- `0364a50`: the documents.

Every output a fix touches was regenerated: `slots-output.txt`, `budget-output.txt` and the new
`reuse-check-output.txt`. CI is green on `0364a50`: both workflow runs `completed` / `success`
(cairo × 8, client, tooling, discover).

Where this section disagrees with the sections above, it supersedes them. The claims withdrawn:
- "within 2,000 L2 gas";
- "a zeroed slot is new again";
- the reveal's "2 / 1" slots;
- "the window assembled once per batch";
- "4 felts per extra call";
- the median 456,375;
- $0.725 / $0.540 labelled D.

| # | Fix | Real output |
|---|---|---|
| 1 (major) | The base/signature split is now called an **assumed normalisation**: only their sum, 14,880, is identified. `analyse.py` §2 prints every constant that keeps the state parts multiples of 2,000, with the signature priced 0 or 5,120. The divisibility is described as an observation of these receipts, separate from predictive accuracy (§4, largest error 165,481). The "within 2,000" claim is removed. The research note §2 states the controlled measurements that would identify the missing terms: signatures of different lengths, a call that writes nothing at two calldata lengths, keys near and far | `\| 0 \| 880, 2,880, 4,880, 6,880, 8,880, 10,880, 12,880, 14,880, 16,880, 18,880 \|` and `\| 5,120 \| 640, 2,640, 4,640, 6,640, 8,640, …, 18,640 \|` (slots-output §2) |
| 2 (major) | Checked on our traces with `reuse_check.py`: every `enter` writes new keys and no new write revisits a zeroed key. "A zeroed slot is new again" is removed from the research note and `cost-budget.md`. "enter writes 4 new slots" is kept as measured. A reused key's price is an **extrapolation (E)**, and the saving is said to need **reused keys** (instance slots reused, a generation in the record), not merely stopping the zeroing. CB-5 is added | `enter transactions: 45; new game slots they wrote: 180; distinct: 180` / `game keys zeroed by some transaction: 180; new writes to a key zeroed earlier: 0`. Enter with reused keys: `1,869,639 \| E (extrapolation) \| − 4 × 421,452; no rewrite of a used key was observed` |
| 3 (major) | The reveal is counted on **SPK-7's observed layout** (`contract.cairo` `reveal`, lines 430–468): the terrain slot per chunk, new; the revealed bitmap once per transaction, new at the first reveal and overwritten after; no occupancy. An occupancy slot is a separate row, marked an assumption. Fixed in `cost-budget.md` §2 and ADR-0006 | `Slots of a reveal of 1 chunk … bitmap new: the instance's first reveal) \| 907,048`; `… 1 chunk … bitmap overwritten) \| 485,596`; `… 3 chunks … overwritten) \| 1,392,644`; `+ an occupancy slot per chunk … \| +453,524 a chunk \| E (assumption)` |
| 4 (major) | The window stays **per tick** (D-120). SPK-7's 720,000 is described as a whole-transaction A − S difference that includes storage effects; 65,224 is the in-memory assembly. A batch pays per tick somewhere between the two, depending on cached reads and slots changed once, and that is not measured. "Assembled once per batch" is replaced by: what a batch can do once is read chunks and change their slots. The batch stays an estimate (`cost-budget.md` §2, rule 3, CB-3; ADR-0006) | `Batch as measured + that overhead at each tick \| 44,182,245 \| E`; `Batch as measured + the assembly alone at each tick (reads and writes cached, no other effect) \| 37,634,485 \| E \| the lower reading` |
| 5 (minor) | `analyse.py` now finds game calls by traversal: the topmost Hub or Instances invocations, inclusive, counted once | `\| C burner via relayer: leave \| 2,386,685 \| 1,561,285 \| …` (slots-output §6), and its game call `682,000` in §1; before, 1,883,925 |
| 6 (minor) | The expedition discloses its assumption: a batch keeps one tick's state remainder and DA footprint. Every batched row is E, and the owner's row is D (a projection of receipts). A row with the 27 argument felts is added. Propagated to ADR-0001 | `Each batch carries the 27 argument felts … 138,240 a batch, 1,382,400 per expedition.`; `\| Fights in batches of 10, each tick as measured, with the 27 felts \| E \| 822,025,916 \| 0.726 \| … \| 612,698,120 \| 0.541 \|`; `\| One action per transaction, owner's account (SPK-1 §5: a projection of receipts) \| D \|` |
| 7 (minor) | The planned-queue row becomes **the spike's movement benchmark** (`walk`, D) and an **estimated move-only `play` batch** (E): under design/02, planned moves join `play` | `\| The spike's walk of 10 moves … (movement benchmark) \| 17,306,703 \| D \|`; `\| A move-only play batch of 10 moves near goblins … \| 17,388,623 \| E \| the benchmark with its 14 argument felts replaced by 30 …\|` |
| 8 (minor) | The Fate row excludes the entry draw; `enter`'s budget includes it | `\| A Fate action other than the entry draw (enter has its own budget) … \| 2,852,275 \| E \|` |
| 9 (minor) | Conventional median (`statistics.median`) | `\| New (its value was 0) \| 426,000 / 449,187.5 / 482,000 \| 453,524 \| 402,000 \|`; `\| Overwritten or zeroed \| 20,000 / 33,333.3 / 80,000 \| 32,072 \|` |
| 10 (minor) | A further call of a multicall is 3 header felts (to, selector, length): 15,360. The first call keeps its 4, the count included. Fixed in `budget.py` and `cost-budget.md` §1 and rule 4 | `A multicall's header: the first call 4 felts (count, to, selector, length), each further call 3 (to, selector, length) \| 20,480, then 15,360 a call \| D` |

Unchanged by the fixes, and reproduced by the audit:
- 453,524 per new slot and 32,072 per other slot;
- the floor, 816,939 (it depends only on the identified sum 14,880);
- $0.725 / $0.540 for D-137's case, now labelled E, and $0.726 / $0.541 with the 27 felts.

Escalation 2 above now reads: a worst batch is 37.6M to 44.2M (E) against design/02's 40M, not
"44.2M".

## Fix loop 2

The `[GPT-6-Astra]` re-audit of PR 71 resolved findings 3, 4, 5, 7, 8, 9 and 10, and reproduced
the three regenerated outputs exactly. Findings 1, 2 and 6 remained. They are fixed in two new
commits on the same branch, no force-push:
- `89b943b`: the scripts, `slots-output.txt` and `budget-output.txt` regenerated;
- `77f9f99`: the research note, `cost-budget.md`, ADR-0001 and ADR-0007.

CI is green on `77f9f99`: both workflow runs `completed` / `success`.

This section supersedes the wording of the earlier sections of this report:
- "the identified sum 14,880" and "the floor depends only on the identified sum" (Fix loop 1);
- "the budgets use 453,524 and 32,072" without their convention;
- "none rewrote a used key";
- "55 % … (D)".

| # | Fix | Real output |
|---|---|---|
| 1 (major) | **The aggregate (constant + the 2 signature felts), 14,880, is now a chosen normalisation, not measured**, like its split. `analyse.py` gains §4.1: the fit and the floor refitted under every admissible aggregate, from the lowest (880) through 2,000 steps around 14,880 to the highest (74,880, where a state part reaches 0). The prices and the floor are labelled "under the 14,880 convention", with their ranges, in `budget.py`, the research note (summary, §2, §4, §6), `cost-budget.md` §1 (the aggregate row, the split row, both slot prices, the floor, the formula), ADR-0001 and ADR-0007 | `slots-output.txt` §4.1: `\| 880 \| 453,691 \| 33,751 \| 806,297 \| -10,642 \|`, `\| 12,880 \| 453,548 \| 32,312 \| 815,419 \| -1,520 \|`, `\| 14,880 (the convention used) \| 453,524 \| 32,072 \| 816,939 \| +0 \|`, `\| 16,880 \| 453,500 \| 31,832 \| 818,459 \| +1,520 \|`, `\| 74,880 \| 452,808 \| 24,878 \| 862,551 \| +45,612 \|`. `budget-output.txt`: `\| res1 constant + the 2 signature felts, together (the aggregate) \| 14,880 \| chosen normalisation, not measured \|`, and `\| **Floor of a burner transaction** … \| **816,939** \| D under the 14,880 convention \| … 806,297 to 862,551 over the admissible aggregates, 815,419 to 818,459 within ±2,000 …\|` |
| 2 (minor) | "No transaction rewrote a used key" is replaced by **"no zero-then-rewrite was observed, and no instance key was recycled between enters"**, adding that keys holding a value were overwritten many times and are the evidence for the other-slot price. Changed in the research note §6, `cost-budget.md` §1, the enter row and CB-5, and the generated budget text | `budget-output.txt`: `\| Enter, if its 4 slots are **reused keys** … \| 1,869,639 \| E (extrapolation) \| − 4 × 421,452; no zero-then-rewrite was observed, and no instance key was recycled between enters \|`. `reuse-check-output.txt` unchanged: `new writes to a key zeroed earlier: 0` |
| 6 (minor) | The queues' share of S1 is stated both ways with their labels, in the generated bullet and in `cost-budget.md` §3 | `budget-output.txt`: `- S1's 36 queues of 5 near goblins cost 358,026,084 (D): 43.554 % of S1 with fights batched, each tick as measured, with the 27 felts (E), and 54.685 % with fights batched and shared (E).` |

Unchanged: every other generated figure. The expedition table, the batch figures and the
reveal rows print as in fix loop 1.
