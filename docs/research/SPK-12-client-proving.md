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

PROVING_SUMMARY

- **The cost.** One proof is a flat **75,000,000 L2 gas** (the protocol's charge, M by slingfall on the
  devnet), about **$0.066**, whatever it holds. An L2 batch of 10 ticks costs about 22 M in S1 (D from
  STATUS's 663 M). So **proofs win only when a segment is long or its ticks are heavy**: the break-even
  is **about 37 ticks a segment** at S1's average batched tick, **55** at the representative tick's
  target, and **2–3** at SPK-15's worst tick (E, `cost.py`).
- **S1 is cut short by its Fate actions.** Its segments end at every loot, chest, vein and gate. With 10
  Fate actions and 2 gates, S1 has 13 segments of about 23 ticks, and proofs cost **$0.95 against
  $0.58** (1.62×). With 5 Fate actions and no gate, 6 segments of 50 ticks: **$0.44** (0.75×). With 20
  and 4: **$1.82** (3.1×). S1 does not say how many of its 20 "other" actions are Fate actions: the
  verdict on S1 turns on that number (E).
- **A fight-heavy expedition is where proofs win**: 300 worst ticks, each an invocation alone under
  D-172, cost **$12.1 batched as it stands ($9.5 after SPK-15's levers) against $0.95 proved** (E): a
  worst tick fills a third of a 75 M proof's worth of L2 gas by itself, and a proof holds 46 to 66 of
  them under the virtual transaction's cap.
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
two batches ahead) removed, since a proof is not bounded by a transaction's gas (§2).

| Boundary (design/02) | Why it needs the chain | What the next segment takes from L2 |
|---|---|---|
| `enter`, a gate into another location (the entry draw, Fate) | ADR-0002: the draw is the chain's | The **entry word**, the seed of every chunk of the instance (D-111) |
| `loot`, `open`, `mine`, `barter` (Fate, sent alone after a confirmed state) | The draw is made on the state the chain has, and consumes what it draws from (ADR-0002 rule 5) | The state after the draw (remains consumed), and the drawn item's effect on the player entropy (ADR-0006: a looted remains feeds the reveal value) |
| `travel_back`, `leave` | Closes the instance; the results interface writes the persistent domain (ADR-0001) | — |
| Defeat | The instance closes | — |

**Reveals are not boundaries.** The brief cites D-64, "every chunk generated at reveal from a fresh
random word". The owner's later D-111 (owner review 3, ADR-0006 option C) replaced it: a chunk is
computed from the **entry draw and the adventurer's irreversible actions**, and "a move that reveals
chunks" rides in a batch (design/02). So a reveal stays inside a segment and asks nothing of L2; the
entry word is a public input of every segment of its instance (§6.2). The brief's premise is noted
under *Deviations* of the report; nothing in the analysis depends on D-64.

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
remains, ended by the loot (design/02's *the end of a fight* trigger exists for that reason). A fight of
100 fight actions spread over ~10 loots is about 10 fight actions and 10–20 moves a segment, which is
the central reading. Exploration without a fight gives the long segments (no draw), fights with many
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
| S1's average, 663 M less `enter` and `leave` over 300 ticks | 2,187,122 | **37** |
| The representative tick at the expedition's target (cost-budget §2) | 1,469,435 | **55** |
| A worst tick alone, as it stands (SPK-15) | 45,802,846 | **2** |
| A worst tick alone, with L1–L4 | 35,943,656 | **3** |

What the table assumes, and what would move it:

- the protocol's 75 M a proof is SNIP-36's published fee for a 500 KB proof (130 L2 gas a byte + 10 M,
  slingfall research 01b) and is **flat on the devnet whatever the size** (M, slingfall W3). If mainnet
  priced the bytes of a smaller proof, a segment would cost less: §3's proofs are PROOF_BYTES_RANGE;
- the fight-heavy batched figure follows D-172 (a worst tick runs alone); it is the bound of a
  pathological expedition, not a forecast. ENG-07's representative *fight* tick will place real fights
  between the two ends;
- proving is free on the chain but not to the player: it is the phone's time and battery (§4).

## 3. Proving on the Mac (AC-3)

PROVING_SECTION

## 4. A phone (AC-4, part 1)

PHONE_SECTION

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
- **Latency.** Before every Fate action the player waits for: the proof of the segment (§4: seconds on
  the Mac's standalone figure, an unmeasured multiple of it for the virtual transaction on a phone),
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
   expedition, E). They are D-172's open case: a worst tick runs alone at 36–46 M.
3. **The path is not open yet.** No prover answers PROOF2 today; a virtual transaction's proving time is
   measured by nobody; no Stwo virtual-OS prover runs on a phone (§4); SNIP-36 phase 1 is verified by
   consensus only, and its proofs are not kept permanently in blocks (slingfall research 01b).
4. **The design cost is real**: co-op needs a leader or loses whole segments (§6.1), the state the
   chain stores becomes a hash (§5), and the client carries the logic three times (§6.3).

**What would reverse it** (any one):

- ENG-07's representative fight tick, measured inside a batch, keeps S1 above $0.50 after the
  engineering levers, **and** S1's Fate actions are few enough that its segments pass about 37 ticks;
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
