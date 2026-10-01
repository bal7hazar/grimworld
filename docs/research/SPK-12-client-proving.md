# SPK-12 — Client-side proving against L2 batches

| | |
|---|---|
| Task | SPK-12 (D-161 §3, D-172 §3), lent to track CV; a spike: nothing merges into `contracts/` or `client/` |
| Author | `[Opus 5.5]`, 2026-10-01 |
| For | **The owner**: reopening ADR-0001 (option A, L2 batches, D-133) for option D (client-side proving, SNIP-36) is the owner's decision |
| Code and runs | `spikes/SPK-12/` (README there): the proved segment, its tests, `prove/prove.py`, `cost.py` |
| References | slingfall (`github.com/bal7hazar/slingfall`): its local clone's `main` is `d401cf2`; the SNIP-36 tier, the cost sheets W3 and B6 and research 07 were read at GitHub's `main`, **`f8810c5`** (2026-10-01), the clone being behind and not to be written in. stwo-cairo `467d5c6` with slingfall's two patches. grimworld `main` at `e9b8cef`; CBT-02's fixtures from `contracts/logic/tests/test_tick.cairo` at `2a8304d`; SPK-15 at `0f4b571` (its branch, not merged) |

Every figure is marked as cost-budget.md marks them: **M** measured (with its command), **D** derived by
arithmetic from M, **E** estimated on a stated assumption.

## Summary

- **The tick proves on the Mac, and is cheap in Cairo steps.** Today's tick library, run as a
  standalone executable on CBT-02's states and proved with Stwo (`canonical_small`, verified, two runs
  each): one representative tick 22,918 steps, **one worst tick 128,172 steps in 23–26 s** (a 1-tick segment, the load and store of its 101
  actors included), **CBT-02's
  busy batch of 10 ticks 247,686 steps in 25–26 s, 3.7 GiB, a proof of 1.1 MB** (M). Most of a tick's
  L2 gas is storage: its computation is about 120 L2 gas a step, and a representative tick about
  5.3 k steps (M).
- **A floor dominates.** Any segment under ~0.5 M steps takes about **14 s and 3.6 GiB** on the Mac
  (37 s and 3.0 GiB on one thread); above it, about 11–14 s and 1.5 GiB per million steps (M, D).
  `canonical_small` stops at 2^20 range checks, **2,600 representative ticks (13.8 M steps) in
  164–184 s and 21 GiB**; `canonical_without_pedersen` proved 4,500 ticks (23.8 M steps) in 314–344 s
  (M).
- **A phone (E):** 19–42 s a segment at the floor on the owner's iPhone 14, but the prover's 3.0–3.6 GiB
  floor is at or above what an iOS app may hold: **as built, it does not fit**. Thirteen proofs an
  expedition would take 2.7–5.9 % of the battery at the floor, and 12–32 % on a fight-heavy
  expedition, against SPK-6's 8 % for 30 minutes of play.
- **The cost.** One proof is a flat **75,000,000 L2 gas** (the protocol's charge, M by slingfall on the
  devnet), about **$0.066**, whatever it holds. An L2 batch of 10 ticks costs about 22 M in S1 (D from
  STATUS's 663 M). So **proofs win only when a segment is long or its ticks are heavy**: the break-even
  is **about 39 ticks a segment** at S1's average batched tick, **55** at the representative tick's
  target, and **2–3** at SPK-15's worst tick (E, `cost.py`).
- **S1 is cut short by its Fate actions.** Its segments end at every loot, chest, vein and gate. With 10
  Fate actions and 2 gates, S1 has 13 segments of about 23 ticks, and proofs cost **$0.95 against
  $0.58** (1.62×). With 5 Fate actions and no gate, 6 segments of 50 ticks: **$0.44** (0.75×). With 20
  and 4: **$1.82** (3.1×). S1 does not say how many of its 20 "other" actions are Fate actions: the
  verdict on S1 turns on that number (E).
- **A fight-heavy expedition is where proofs win**: 300 worst ticks, each an invocation alone under
  D-172, cost **$12.1 batched as it stands ($9.5 after SPK-15's levers) against $0.95 proved** (E): a
  worst tick sent alone costs 36–46 M, about half of a proved segment's 79.5 M, and one proof holds 46
  to 66 of them under the virtual transaction's cap.
- **What blocks option D today is not the cost but the prover.** SNIP-36 verifies proofs of a
  *virtual Starknet transaction* run by the virtual OS, not of a standalone program. **No prover
  answers PROOF2 today** (slingfall SN1 §5), the virtual-OS prover is a server backend, and nobody has
  measured its proving time. What this spike measured is the standalone Stwo proof of the same tick
  code, a **lower bound** on what the client would have to prove.
- **Recommendation: keep L2 batches; prepare a mixed design (proofs for heavy fight segments) as a
  contract lot only after a SNIP-36 virtual transaction has been proved on a phone.** §7.

## 1. The expedition in segments (AC-1)

### What ends a segment

A *segment* is the run of deterministic actions between two moments that need the chain: design/02's
*What a batch holds, and what ends one*, with the batch's own limits (weight 10, 16 goblins, 5 seconds,
two batches ahead) removed: a proof is bounded by its virtual transaction's 1.1e9 L2 gas, not by a
batch's 40 M (§2).

| Boundary (design/02) | Why it needs the chain | What the next segment takes from L2 |
|---|---|---|
| `enter`, a gate into another location (the entry draw, Fate) | ADR-0002: the draw is the chain's | The **entry word**, the seed of every chunk of the instance (D-111) |
| `loot`, `open`, `mine`, `barter` (Fate, sent alone after a confirmed state) | The draw is made on the state the chain has, and consumes what it draws from (ADR-0002 rule 5) | The state after the draw (remains consumed), and the drawn item's effect on the player entropy (ADR-0006: a looted remains feeds the reveal value) |
| `travel_back`, `leave` | Closes the instance; the results interface writes the persistent domain (ADR-0001) | — |
| Defeat | The instance closes | — |

**Reveals are not boundaries: a deviation from the brief.** The brief cites D-64, "every chunk
generated at reveal from a fresh random word", and asks for the fresh word of each reveal as a
boundary. The owner's later **D-111** ([owner review 3](../decisions/2026-09-28-owner-review-3.md):
"one draw at entry, then a value built from the adventurer's irreversible actions"; ADR-0006 option C)
replaced it: a chunk is computed from the **entry draw and the adventurer's irreversible actions**, and
"a move that reveals chunks" rides in a batch (design/02). **This note therefore models reveals inside
segments, under D-111, and not as boundaries under D-64**: a reveal asks nothing of L2, and the entry
word is a public input of every segment of its instance (§6.2). Nothing in the analysis depends on
D-64. The task's report, archived as `docs/reports/SPK-12-client-proving.md`, lists the same deviation.

### S1 cut into segments

S1 (cost-budget §3, SPK-2 §3.3): 180 moves in 36 queues of 5 near goblins, 100 fight actions, 20 other
actions ("loot, chest, gate, potion"), `enter`, `leave`; **about 30 batches of weight 10, about 300
ticks** (ENG-01 §10.2, E). S1 does not say how many of the 20 others are Fate actions or gates, so the
model takes three readings (E), one instance per location, ticks spread evenly:

| Reading | Fate actions F | Gates G | Segments F + G + 1 | Ticks a segment (mean) |
|---|--:|--:|--:|--:|
| few draws, one location | 5 | 0 | 6 | 50 |
| **central**: half the others are draws, two floors | 10 | 2 | 13 | 23 |
| every other action is a draw or a gate | 20 | 4 | 25 | 12 |

The distribution is not even in play: a segment is usually an approach, a fight and the walk to the
remains, ended by the loot (design/02's *the end of a fight* trigger exists for that reason). S1's 100
fight actions spread over ~10 loots are about 10 fight actions and 10–20 moves a segment: the central
reading. Exploration without a fight gives the long segments (no draw), fights with many
drops the short ones.

### A co-op expedition (D-80)

Under D-80 every action of any member ticks the one world, and the instance's sequence is shared
(design/02, *Two adventurers in one instance*; design/08 M-1, M-2). A segment is then **a run of the
world's ticks, whoever played them**, ended by any member's Fate action or gate.

| Choice | Who proves | What it needs | Consequence |
|---|---|---|---|
| One proof per world segment | One member (a "leader") proves the actions of all | Every member's actions, in order, reach the leader before proving: an off-chain channel between members | The order of actions is the leader's, not the chain's: design/02's ordering by transaction disappears, and a channel (a server) enters the game's trust |
| One proof per member's run | Each member proves their own consecutive actions | Each segment starts from the world's current commitment | Two members acting at once produce two segments from the same state: the first submitted wins, the other is refused whole and **rewinds a whole segment** (tens of actions), where a batch loses at most two batches (design/02) |

Who pays is unchanged: the game funds the burners that send (D-137), whoever proves. Co-op is not in
the MVP (design/08); proofs make it harder, not impossible.

## 2. The cost, batches against proofs (AC-2)

`spikes/SPK-12/cost.py` (output `cost-output.txt`), at cost-budget §1's prices (1 M L2 gas =
$0.000881). Every input is listed in the script with its source.

**A proved segment costs** (E): one Invoke carrying the proof and one `submit_chunk`-like message,
**77,321,760** (M: slingfall B6's cost sheet, devnet, of which **75,000,000** the protocol's flat charge
on any Invoke carrying proof facts), plus the segment's resulting state published as calldata so that a
Fate action, another device and the indexer can rebuild what the proof only hashes (design/02, *The
client's copy*): 420 felts × 5,120 = 2,150,400 (E). **79.5 M, $0.070 a segment.** The actions that need
the chain stay L2 transactions in both designs: `enter` 4,513,259 (M), `leave` 2,350,000 (M + 10 %), a
Fate action 2,900,000 (E, cost-budget §2), a gate 3,667,902 (E, ENG-01 §10).

**How many proofs a segment needs.** A SNIP-36 virtual transaction is capped at 1.1e9 L2 gas; slingfall
plans at 1.0e9 (about 9 M Cairo steps at its measured 111–150 L2 gas a step). Priced as conservatively
as the batch itself (every L2 gas of the tick inside the virtual transaction, storage included), a proof
holds:

| Tick | Per call (once a proof) | Per tick | Ticks a proof (E) |
|---|--:|--:|--:|
| SPK-15's worst, as it stands | 19,675,090 | 20,873,867 | **46** |
| SPK-15's worst, with L1–L4 | 15,882,120 | 14,807,647 | **66** |
| The representative at the expedition's target | — | 1,469,435 | **680** |

In Cairo steps alone, measured here (§3), the representative tick is about 5.3 k steps and the busy
tick 7.7–13.2 k: a 9 M-step proof would hold well over 600 of either. **Every segment of S1 and of the
fight-heavy expedition needs one proof**: the lever is the number of segments, not their size.

| Expedition | Batches as designed | Proofs (one a segment) + the L2 transactions that stay | Proofs / batches |
|---|--:|--:|--:|
| S1, F = 5, G = 0 (6 segments) | 663 M, $0.584 (E, STATUS) | 498 M, **$0.439** (E) | 0.75× |
| **S1, F = 10, G = 2 (13 segments)** | 663 M, **$0.584** (E) | 1,076 M, **$0.948** (E) | **1.62×** |
| S1, F = 20, G = 4 (25 segments) | 663 M, $0.584 (E) | 2,066 M, $1.820 (E) | 3.12× |
| Fight-heavy: 300 worst ticks, as it stands, 13 segments | 13,784 M, **$12.14** (E: 300 invocations of a tick alone, 45.8 M each, D-172) | 1,076 M, **$0.948** (E) | **0.078×** |
| Fight-heavy, with SPK-15's L1–L4 | 10,826 M, $9.54 (E: 35.9 M a tick alone) | 1,076 M, $0.948 (E) | 0.099× |

**The break-even** (E): a proof (79.5 M) costs less than the same ticks batched when a segment holds at
least

| Batched cost of a tick | L2 gas | Ticks a segment |
|---|--:|--:|
| S1's average: 663 M less `enter`, `leave`, the central reading's 10 Fate actions and 2 gates (36.3 M), over 300 ticks | 2,066,003 | **39** |
| The representative tick at the expedition's target (cost-budget §2) | 1,469,435 | **55** |
| A worst tick alone, as it stands (SPK-15) | 45,802,846 | **2** |
| A worst tick alone, with L1–L4 | 35,943,656 | **3** |

S1's row (fix loop 1) takes the transactions that are not batches out of the 663 M before dividing:
with them left in, the average tick was 2,187,122 and the break-even 37 ticks, a lower bound. With
fewer Fate actions the row moves little (F = 5, G = 0: 2,138,789, 38 ticks).

What the table assumes, and what would move it:

- the protocol's 75 M a proof is SNIP-36's published fee for a 500 KB proof (130 L2 gas a byte + 10 M,
  slingfall research 01b) and is **flat on the devnet whatever the size** (M, slingfall W3). If mainnet
  priced the bytes of a smaller proof, a segment would cost less: §3's standalone proofs are
  1.08–1.26 MB, above SNIP-36's 500 KB example, so no saving is in sight;
- the fight-heavy batched figure follows D-172 (a worst tick runs alone); it is the bound of a
  pathological expedition, not a forecast. ENG-07's representative *fight* tick will place real fights
  between the two ends;
- proving is free on the chain but not to the player: it is the phone's time and battery (§4).

## 3. Proving on the Mac (AC-3)

### What was proved

`spikes/SPK-12/src/segment.cairo`: a **segment** of world ticks, from the stored words to the stored
words, exactly as `TickLibrary.run` does it (`Words::load`, `TickTrait::run`, `World::store`), on
`grimworld_logic` by path (main at `e9b8cef`). Its arguments are private (the words, the content, the
rules, the tick count); its public output is a binding header `[IN_HASH, CONTENT_HASH, rules, ticks,
OUT_HASH, clock, defeated]`, the hashes Poseidon over the felts, as slingfall's chunk binding does. Its
tests show that two segments of 5 ticks chain by their hashes and give the 10-tick segment's words
(`test_segments_chain`).

The states are CBT-02's, copied with their source (`contracts/logic/tests/test_tick.cairo` at
`2a8304d`): **representative** (the member with one condition and one effect, 8 awake goblins, rules
`Idle`), **worst** (`worst_state(true, 3)`: 100 goblins, 8 awake, everything concludes and dies, one
tick), **busy** (`worst_state(false, 1)` under CBT-02's `Busy` rules: every actor acts or resolves at
every tick, until the member falls at clock 89, 40 ticks).

**What is not in it**: CBT-04's conditions, CBT-03a's hit, CBT-05's executor, ENG-07's perception and
AI, the map library. The tick proved is today's library class, which runs the pipeline with `Idle`
rules; §3's last table estimates the full tick from SPK-15's L2 gas.

### Commands

```sh
spikes/SPK-12/prove/setup.sh --native   # stwo-cairo 467d5c6 + slingfall's two patches (most of an hour cold, not timed)
python3 spikes/SPK-12/prove/prove.py --runs 2 --out spikes/SPK-12/prove/out/run1 \
  --case representative:1 --case worst:1 --case representative:10 --case busy:10
python3 spikes/SPK-12/prove/collect.py  # every run's table -> spikes/SPK-12/prove-output.txt
```

Each proof is one `run_and_prove --program_type executable --params_json params.canonical_small.json
--proof-format binary --verify`, then the separate `verify --proof_format binary`, whose
`VERIFICATION_OUTPUT` must equal the header `scarb execute` printed. Machine: the Mac, arm64, 12 cores,
64 GB (the chip's name could not be read: `sysctl` is refused to this run's profile).

### Measurements (M, two runs each)

| Segment | Cairo steps | Range checks | Wall time (s) | Peak RSS (GiB) | Proof bytes | Result |
|---|--:|--:|--:|--:|--:|---|
| representative, 1 tick | 22,918 | 2,309 | 14.77 / 13.69 | 3.60 / 3.65 | 1,090,994 | verified, output = header |
| **worst, 1 tick** | 128,172 | 17,659 | 23.46 / 25.93 | 3.71 / 3.61 | 1,098,531 | verified |
| representative, 10 ticks (a batch) | 70,663 | 5,927 | 18.09 / 17.00 | 3.68 / 3.60 | 1,076,280 | verified |
| **busy, 10 ticks** (CBT-02's busy batch) | 247,686 | 23,253 | 26.13 / 25.39 | 3.74 / 3.74 | 1,095,396 | verified |
| busy, 40 ticks (to the defeat) | 423,740 | 33,300 | 26.90 / 30.61 | 3.83 / 3.82 | 1,112,747 | verified |
| representative, 100 ticks | 547,353 | 41,547 | 19.74 / 18.94 | 3.88 / 3.84 | 1,081,389 | verified |
| representative, 1,000 ticks | 5,311,440 | 396,159 | 84.95 / 81.53 | 10.97 / 9.88 | 1,161,597 | verified |
| representative, 2,000 ticks | 10,604,956 | 790,175 | 145.93 / 151.33 | 19.22 / 19.44 | 1,221,292 | verified |
| **representative, 2,600 ticks**: the largest under `canonical_small` | 13,781,143 | 1,026,587 | 164.33 / 183.73 | 21.03 / 20.57 | 1,202,257 | verified |
| representative, 2,700 ticks, `canonical_small` | 14,310,443 | 1,065,987 | 66.64 / 71.45 | 13.63 / 13.65 | — | **stops**: a component over 2^20 rows (the range checks) |
| representative, 2,700 ticks, `canonical_without_pedersen` | 14,310,443 | 1,065,987 | 194.44 / 196.69 | 24.11 / 22.85 | 1,213,225 | verified |
| **representative, 4,500 ticks**, `canonical_without_pedersen` | 23,838,746 | 1,775,215 | 344.10 / 313.53 | 23.50 / 33.56 | 1,255,743 | verified |

Threads (`RAYON_NUM_THREADS`), `canonical_small`:

| Segment | 1 thread: s, GiB | 6 threads: s, GiB | all 12: s (above) |
|---|---|---|---|
| representative, 1 tick | 37.40 / 37.53, 2.97 | 14.27 / 14.25, 3.56 | 14.77 / 13.69 |
| busy, 40 ticks | 70.77 / 78.11, 3.68 / 3.65 | 25.08 / 24.90, 3.88 / 3.89 | 26.90 / 30.61 |
| representative, 1,000 ticks | — | 78.05 / 76.93, 10.67 / 10.45 | 84.95 / 81.53 |

- **The proofs are deterministic**: both runs of every case wrote the same bytes (sha256 equal), under
  one program hash, `0x3da0c2f599c5e5e34476eaca84e7b426e5daf157ce42eac1d87a3c8ca07a454`.
- **A floor dominates small segments**: about **14 s and 3.6 GiB** for any segment under ~0.5 M steps
  (37 s and 3.0 GiB on one thread). `canonical_small`'s preprocessed columns are proved whatever the
  trace; in the log of a 1-tick proof, `prove_cairo` takes 11.0 s, 8.0 s of it proving the STARKs.
- **Above the floor**, from 0.55 M to 13.8 M steps: about **11–14 s and 1.5 GiB per million steps** (D, the
  fit of the rows above; slingfall research 05 found 1.5 GiB per million too). Memory grows by powers
  of two, and the RSS of the same run varies (23.5 and 33.6 GiB at 4,500 ticks).
- **Where proving stops**: `canonical_small` at **2^20 range checks**, here about 2,630 representative
  ticks (13.8 M steps); `canonical_without_pedersen` goes on, and 4,500 ticks (23.8 M steps) fit in
  23.5–33.6 GiB. A larger segment was not tried: it would pass the run's 10-minute command limit
  before the Mac's memory.
- **The proof is 1.08–1.26 MB**, growing slowly with the trace, ~1.1 MB for every segment S1 would
  produce. Verification: 0.19–0.58 s.
- **Six threads are as fast as twelve.** The other cores add nothing, as slingfall found on its
  runners.

### Steps and L2 gas: what the full tick would cost to prove (D, E)

The same runs measured in snforge (`test_cost_run_ticks`, L2 gas of `run` alone; two clean runs
equal) against `scarb execute`'s steps, net of the 0-tick run:

| Run | L2 gas (snforge, M) | Cairo steps (M) | L2 gas a step (D) |
|---|--:|--:|--:|
| representative, 100 ticks − 0 | 64,036,490 | 529,871 | **121** |
| busy, 10 ticks − 0 | 15,268,560 | 132,336 | **115** |
| busy, 40 ticks − 0 | 35,901,316 | 308,390 | **116** |

So a tick's **computation** is about 115–121 L2 gas a Cairo step (slingfall's virtual transactions:
111–150). Taking **every** L2 gas of SPK-15's worst tick as computation (an upper bound, since its
hooks' 6 writes, 4.05 M, are storage), the full worst tick is **at most about 181 k steps** (20,873,867
/ 115) and its per-call part 171 k (E). A central S1 segment of 23 such ticks is then about **4.3 M
steps**, which proves in about **70 s and 10 GiB on the Mac** (D from the fit above). A segment of 23
representative ticks of today's library is about 140 k steps: the floor, about 14 s and 3.6 GiB (M).

## 4. A phone (AC-4, part 1)

Nothing was run on a phone. Every figure below is **E**, from the Mac's M figures and these
assumptions:

| # | Assumption | Basis |
|---|---|---|
| A1 | The reference phone is the owner's **iPhone 14** (D-151): A15, 2 performance and 4 efficiency cores, 6 GB of RAM | Apple's published specification |
| A2 | One A15 performance core runs this prover at **0.5–0.8×** one of the Mac's cores | Not measured; the Mac's chip could not be named (`sysctl` refused) |
| A3 | The A15's six cores give **1.8–2.5×** one core (the Mac's six threads gave 2.6× on the floor, 3.0× on busy:40, M) | Two performance cores and four slower ones |
| A4 | An iOS app may hold about **3 GB** on a 6 GB phone before the system ends it | Apple publishes no figure; the `increased-memory-limit` entitlement raises it by an unpublished amount |
| A5 | The phone draws about **5 W** under full multi-core load; its battery holds about **12.7 Wh** | Not measured; Apple publishes the battery's capacity, not the SoC's power |

**Time.** The formula (fix loop 1), computed by `cost.py` (`cost-output.txt`, *The phone*):

```
phone time = T1 / (A2 × A3)
  T1  the Mac's one-thread time (M, prove-output.txt run8)
  low  = T1 (shortest run) / (0.8 × 2.5) = T1 / 2.0
  high = T1 (longest run)  / (0.5 × 1.8) = T1 / 0.9
```

Where only six threads were run, T1 = the six-thread time × the measured one-thread over six-thread
ratio, 2.62 (the floor, 37.40 / 14.27) to 3.14 (busy:40, 78.11 / 24.90).

| Segment | T1, Mac one thread | Phone (E) |
|---|--:|--:|
| Any segment under ~0.5 M steps (the floor): S1's central segment of today's tick, ~140 k steps | 37.40–37.53 s (M) | **19–42 s** |
| busy, 40 ticks (0.42 M steps) | 70.77–78.11 s (M) | 35–87 s |
| A central S1 segment of 23 full worst ticks, ~4.3 M steps (§3, E) | 170–204 s (E: ~65 s on six threads, D, × 2.62–3.14) | 85–227 s |

**Memory.** The prover's floor is **3.0 GiB on one thread and 3.6 GiB on six** (M): at or above A4's
3 GB before the trace adds anything. **stwo-cairo's standalone prover as built here does not fit an
iPhone 14 app** (E). A 4.3 M-step segment would need about 10 GiB (D). To fit, the prover would need a
smaller preprocessed trace than `canonical_small` (its fixed columns make the floor) or a prover built
for phones; neither exists for Cairo programs as found below.

**Battery and heat** (A5, E: energy = phone time × 5 W, over 12.7 Wh): a floor proof of 19–42 s is
**0.20–0.46 % of the battery**. S1's central reading proves 13 segments: **2.7–5.9 % an expedition for
proving alone**, against SPK-6's threshold of **8 % over 30 minutes of play, rendering included**
(ADR-0003). A fight-heavy segment of 85–227 s is 0.93–2.48 % each, so **a fight-heavy expedition's 13
proofs take 12–32 % of the battery**: over SPK-6's 8 % by proving alone. ADR-0003's power rules ask for no permanent work and near-zero
use at idle; a proof is a burst of 20 s to 4 min at full load before every loot, and its heat against
"no thermal throttling after 30 minutes" is untested: SPK-6.1's protocol would have to include it.

**What the phone uploads**: one proof of **1.08–1.26 MB** a segment (M), deterministic, plus the
transaction. SNIP-36 prices a proof by its bytes in its published fee (130 L2 gas a byte + 10 M; the
devnet charged a flat 75 M, slingfall W3): a phone's proof of a virtual transaction is of the same
order, unmeasured.

**These figures are a lower bound.** The phone would prove a SNIP-36 virtual transaction (§5): the
virtual OS around the same code (the account's validation, the syscalls, the virtual block's
commitments) adds steps nobody has measured, and the virtual-OS prover is not stwo-cairo's
`run_and_prove`.

**A prover in the browser or in the Capacitor shell, as found on 2026-10-01:**

| What | Proves | Where it runs | Status |
|---|---|---|---|
| stwo-cairo `run_and_prove` (this spike) | Cairo standalone executables | Native, measured on arm64 macOS | iOS and Android builds not tried; a Rust library in a Capacitor plugin is plausible, unverified |
| SNIP-36 virtual-OS prover (`starknet-innovation/snip-36-prover-backend`, via slingfall research 01) | Virtual Starknet transactions | A server: slingfall plans a ≥ 32 GB prover box for it (its PLAN, E2) | No phone or browser build found; no prover answers PROOF2 today (slingfall SN1 §5) |
| `AbdelStark/stwo-wasm-demo` | Stwo (not Cairo): a Fibonacci example | Browser, WebAssembly | A demo |
| FibRace (KKRT Labs and Hyli, September 2025; arXiv 2510.14693) | **Cairo M**, KKRT's own VM on Stwo: Fibonacci up to n = 100,000 | A native mobile app, 1,420 device models, 2,195,488 proofs | Most phones under 5 s; stable from 3 GB of RAM. **A different VM**: Cairo (CASM) programs such as ours do not run on it |
| stwo-cairo-ts (via slingfall research 01) | Cairo executables | Browser, Wasm64 | Needs Memory64 and the COOP/COEP headers; RAM-bound; not verified here |
| Cairo Playground, "Prove & Verify" (cairo-lang.org) | Cairo programs, with Stwo | Not stated (browser or server) | Its page does not say where the proof is made |

## 5. Verification on the chain (AC-4, part 2)

**What the chain can verify today, and at what cost.**

| Path | What is proved | Verified by | Cost on chain | Latency | Client-side? |
|---|---|---|---|---|---|
| **SNIP-36** (protocol, live since April 2026, phase 1 by consensus) | A **virtual Starknet transaction** executed by the virtual OS on a base block at least 10 blocks old | The sequencer, before inclusion; the contract reads `proof_facts` (`get_execution_info_v3`) | **75 M L2 gas a proof** (flat), plus the contract's checks: `submit_chunk` 0.84–1.20 M, `finalize` 7.0–7.2 M for 5–7 links + 71 k a link (M, snforge, slingfall contract v3) | One block after the proof exists | Only if the phone runs the virtual-OS prover: **nobody does today**, and no prover answers PROOF2 (slingfall SN1 §5) |
| Standalone Stwo proof (this spike's §3) | Our `segment` program | **No verifier on Starknet**: a Stwo proof is "tens of thousands of felts" against 5,000 of calldata (slingfall research 01) | — | — | Yes (measured here on the Mac) |
| Atlantic + SHARP + Satellite (slingfall E3) | A Cairo PIE, proved by Herodotus | Ethereum's SHARP verifier, the fact bridged to Starknet | `submit_settled` 4.45–18.8 M (M, slingfall) | **≈ 66 min** (M, slingfall E3b) | No: a hosted prover with an account (the owner's, out of scope) |

So **option D for grimworld means SNIP-36**, and the client would prove a virtual transaction, not the
standalone program measured in §3. slingfall's contract v3 shows the shape, which grimworld would follow:

- **The proved program** is a chain contract's entrypoint run as a virtual transaction: it
  library-calls `TickLibrary` (the class the game already declares, ENG-01 §1.3) over the segment's
  actions and **sends one L2→L1 message** whose payload is the binding header: `[instance_id, IN_HASH,
  OUT_HASH, entry word hash, content version, sequence or clock after, defeated, results so far]`. The
  admin pins the virtual-OS program hash and the chain contract (slingfall's `pin_virtual_os`,
  `pin_chain`), so a proof of other code is refused. The pinned **bundle** of class hashes (slingfall's
  `BUNDLE_HASH`) is the program hash of the game's rules: a content or rules upgrade is a new bundle.
- **`submit_segment(instance, payload)`** on `Instances`: checks the facts (`'PROOF2'`, `'VIRTUAL_SNOS'`,
  the program, the base block, the message hash among `facts[8 .. 8 + n)`), then **`IN_HASH` equals the
  instance's stored commitment** and replaces it with `OUT_HASH`, and emits the published state.
- **The binding between segments** is slingfall's chunk binding: each proof's `IN_HASH` is the previous
  `OUT_HASH`. With the commitment checked at submission, proofs may be produced in parallel and
  submitted in order; a segment proved from a state the chain does not hold is refused whole.
- **ENG-01's `play` keeps** its code (it is the virtual transaction's body) and its role for every
  segment that is not proved (§7's mixed design) and for co-op. The **two domains** of ADR-0001 hold:
  the proof's public output carries the ephemeral commitment; the persistent writes (experience, items,
  quest progress) still go through the results interface at `leave`, `travel_back` and defeat, which
  read the results from the published state, checked against the commitment.
- **What the chain stores** changes from the instance's words (ENG-01 §3.2) to their hash, plus the
  words as calldata in events. `instance_state` and `instance_region` (design/02) would read events or
  the indexer, which design/02 forbids as a source of simulation state: either the words are also
  written (their storage cost returns, about ENG-01 §10.2's 29 slots a segment), or design/02's
  *client's copy* changes. **An escalation for the design, not decided here.**

## 6. What it does to the design (AC-4, part 3)

### 6.1 Co-op (D-80)

Answered in §1: one proof per world segment needs an off-chain channel and a leader who orders the
members' actions; one proof per member's run turns every simultaneous action into a refused segment.
Who pays does not change (the game's burners). **Proofs fit solo play; co-op stays on batches** unless
the co-op design accepts a leader.

### 6.2 The randomness at each boundary

- **Reveals (D-111, not D-64).** A reveal is computed inside the proof from the entry word and the
  player-entropy set, both inputs the proof cannot choose: the entry word is bound by its hash in the
  public output and checked against the instance's at submission; the entropy set is part of the state
  hashed into `IN_HASH`. What a modified client can do is what D-111 already accepts (reading one chunk
  ahead, steering at the price of playing badly); proofs add nothing to it.
- **The entry draw, loot, chests, veins, brewing (ADR-0002, D-50)** stay L2 transactions: a proof is
  made before sequencing and cannot contain a draw it could not choose (ADR-0001 option D's own
  "no same-transaction VRF"). The order is therefore **segment proved → submitted and accepted → the
  Fate action on the committed state → the next segment proved from the state after the draw**.
- **Latency.** Before every Fate action the player waits for: the proof of the segment (§4: 19–42 s on
  the phone for the standalone floor, E, a lower bound for the virtual transaction),
  its submission and inclusion (≈ 1.3 s to pre-confirmed, p50, SPK-1), then the Fate action itself (the
  same as today). A SNIP-36 proof must also be built on a base block **at least 10 blocks old** (≈ 17 s
  at 1.7 s a block): harmless if the segment's input comes as calldata bound to the commitment
  (slingfall's chain), blocking if the virtual transaction reads the previous commitment from storage.
  design/02 already sends the batch "before a Fate action" to hide the wait while the player walks to
  the remains; a proof lengthens what must be hidden.

### 6.3 The client (SPK-4, ADR-0003)

SPK-4 chose the TypeScript mirror, with option (b) (the Cairo code in cairo-vm compiled to WebAssembly:
1.37 MB wasm, 25 MB of memory, cairo-vm 3.2.0 having **dropped WebAssembly support upstream**) kept as
the vector oracle. Proving would need, beyond the mirror:

- the **Cairo execution** of the segment (option b's runner, or a native one) to produce the trace: the
  mirror alone cannot be proved;
- **a prover of virtual transactions** (the virtual OS over a base block's state, which the client must
  fetch with its storage proofs), not stwo-cairo's `run_and_prove` of a standalone program;
- that prover **inside the Capacitor shell**: a native library (Rust for iOS and Android) or WebAssembly
  with Memory64 and the threading headers (slingfall research 01, *stwo-cairo-ts*), RAM-bound.

So the client would hold the game's logic **three times**: the mirror (speculation), the Cairo VM
(execution for the proof) and the prover.

### 6.4 Cheating: what a proof prevents, and what it does not

| A player tries to | Batches (design/02) | Proofs |
|---|---|---|
| Submit an illegal state transition | The chain executes and refuses | **The proof cannot exist**: same guarantee |
| Choose the inputs, compute the best sequence off-chain | Possible, gains nothing new | The same: the actions are private witness |
| Replay a batch or a proof | Refused by the sequence number (a count, not the history) | Refused by `IN_HASH` ≠ the commitment: **stronger**, it binds the state, which design/02 found too expensive with batches |
| Hold a segment back, or never send it (take back) | Possible with a modified client (design/02: nothing gained) | The same, and cheaper: up to a whole segment of play can be tried and discarded before anything is sent |
| Grind a Fate draw across proofs: prove several segments ending in different states, read each one's coming draw, submit the best | Possible today by simulating off-chain (the MVP's transaction-hash draw can be steered anyway, ADR-0002) | The same weakness, no worse; **closed only by version 1's attempt-stable draws** (design/02 *Fate*, ADR-0002), which proofs do not change |
| Content or rules other than the chain's | Refused by the content version | Refused by the pinned bundle and the content hash in the header |
| Withhold the state from others (indexer, other devices) | Impossible: the chain stores the words | Possible if only the hash is stored: §5's escalation |

## 7. Recommendation (AC-5)

**Keep L2 batches (ADR-0001 option A, D-133) for the MVP. Do not reopen ADR-0001 now.** Prepare a
**mixed design** as the reversal path: batches by default, and a segment proved by SNIP-36 when its
batched cost would pass the proof's (about 79 M L2 gas, $0.07), which the client knows exactly before
sending since it computes every tick.

Why:

1. **S1 does not need proofs, and may get worse with them.** At the central reading (13 segments) S1 costs
   1.62× more proved; proofs win S1 only if it has 5 or fewer Fate actions and no gate (E). S1's
   problem is the per-tick cost of fights, which ENG-07's representative fight tick will measure.
2. **Heavy fights are where proofs win, by an order of magnitude** (0.08× to 0.10× on the fight-heavy
   expedition, E). They are D-172's open case: a worst tick runs alone at 36–46 M. **But the phone pays
   for it**: a fight-heavy expedition's 13 proofs of 85–227 s each take **12–32 % of the battery** (§4,
   E), against SPK-6's 8 % for 30 minutes of play; the saving on the chain is spent on the device.
3. **The path is not open yet.** No prover answers PROOF2 today; a virtual transaction's proving time is
   measured by nobody; no Stwo virtual-OS prover runs on a phone (§4); SNIP-36 phase 1 is verified by
   consensus only, and its proofs are not kept permanently in blocks (slingfall research 01b).
4. **The design cost is real**: co-op needs a leader or loses whole segments (§6.1), the state the
   chain stores becomes a hash (§5), and the client carries the logic three times (§6.3).

**What would reverse it** (any one):

- ENG-07's representative fight tick, measured inside a batch, keeps S1 above $0.50 after the
  engineering levers, **and** S1's Fate actions are few enough that its segments pass about 39 ticks;
- fights at D-172's worst case turn out frequent in playtest (the worst tick alone costs 36–46 M, so
  ~2 such ticks a segment already favour a proof);
- a SNIP-36 prover of virtual transactions runs on the reference phone within §4's bounds.

**The next step**, in this order:

1. ENG-07 (already planned): the representative fight tick; then rerun `cost.py` with it.
2. **A spike that proves a SNIP-36 virtual transaction** of `TickLibrary.run` over CBT-02's state, on the
   Mac first (the virtual-OS prover, when one answers PROOF2), then on the owner's iPhone 14: time,
   memory, battery against ADR-0003's thresholds. It needs the owner's choices below.
3. Only then, a design change (design/02's segments, the commitment, the published state) and a contract
   lot for `submit_segment`.

**The owner's questions.**

| # | Question | Why it is the owner's |
|---|---|---|
| Q1 | Is the cost of a heavy fight (36–46 M a worst tick alone, D-172) acceptable, or should SPK-15's design levers make it impossible by rule, or should proofs carry it? | It decides whether option D is needed at all |
| Q2 | May an instance's state on chain be a hash, with the words published in events (§5)? | It changes design/02's rule that the indexer is never a source of simulation state |
| Q3 | Co-op with proofs: a leader who orders the party's actions, or whole segments refused on collision (§6.1)? | design/08 is the owner's |
| Q4 | Is a proof-time wait before every loot acceptable (§6.2), on top of today's Fate wait? | Pillar 7 (the chain invisible), the feel of the game |
| Q5 | SNIP-36 phase 1 is verified by consensus only, and its proofs are not kept in blocks: acceptable for game state? | A trust choice of ADR-0001's kind |
| Q6 | Does the next spike (a virtual transaction proved on a phone) get a prover endpoint or a machine for the virtual OS when one exists? | Accounts and infrastructure are the owner's |

## Sources

- slingfall, `docs/proving.md` (*Measurements P1, P1b*, *Memory model*, *Size limit of canonical_small*,
  *SNIP-36 tier*, *Cost sheet W3*, *Cost sheet on alpha.8 B6*), `docs/contract-v3.md`,
  `docs/research/07-split-game-step.md`, `docs/research/01-proof-pipeline.md` and `01b`, at `f8810c5`.
- FibRace (KKRT Labs and Hyli, arXiv 2510.14693, 2025-10-09): https://arxiv.org/abs/2510.14693.
- SNIP-36: https://community.starknet.io/t/snip-36-in-protocol-proof-verification/116123 (via slingfall
  research 01b).
- stwo-wasm-demo: https://github.com/AbdelStark/stwo-wasm-demo.
