# [Opus 5.5] SPK-12 — Client-side proving against L2 batches

## Summary

The spike ran as Opus 5.5, as the note's byline says. This report archives it: every figure below is
taken from `docs/research/SPK-12-client-proving.md` (the note) and from the committed outputs
`spikes/SPK-12/prove-output.txt` and `spikes/SPK-12/cost-output.txt`. Labels as the note uses them:
**M** measured, **D** derived by arithmetic from M, **E** estimated on a stated assumption.

**Pull request: https://github.com/bal7hazar/grimworld/pull/257.** A spike: nothing merges into
`contracts/` or `client/`.

### The question

D-161 §3 and D-172 §3 (lent to track CV): would ADR-0001 option D, a player's phone proving its own
segment of ticks and the chain verifying the proof (SNIP-36), be cheaper and viable against option A, the
L2 batches of D-133? The question reopens an owner decision, so the result goes to the owner.

### The method

- **A proved segment** (`spikes/SPK-12/src/segment.cairo`): a run of world ticks from the stored words to
  the stored words, exactly as `TickLibrary.run` does it, on `grimworld_logic` by path (main at
  `e9b8cef`). Its public output is a binding header `[IN_HASH, CONTENT_HASH, rules, ticks, OUT_HASH,
  clock, defeated]`. Its tests show two 5-tick segments chain into the 10-tick segment's words.
- **The states** are CBT-02's, from `contracts/logic/tests/test_tick.cairo` at `2a8304d`: representative,
  worst (100 goblins, 8 awake, one tick), busy (every actor acts, 40 ticks to the defeat).
- **Proving on the Mac** (arm64, 12 cores, 64 GB): stwo-cairo `467d5c6` with slingfall's two patches,
  `run_and_prove` with `canonical_small`, `--verify`, then the separate `verify`; every case twice
  (`prove/prove.py`, `prove/collect.py`, output in `prove-output.txt`).
- **The cost model** `spikes/SPK-12/cost.py` (output `cost-output.txt`): a proved segment priced from
  slingfall's cost sheets at `f8810c5`, the batches from cost-budget and STATUS, S1 cut into segments by
  its Fate actions and gates under three readings (F = 5, 10, 20).
- **The phone** was not run: every phone figure is E, from the Mac's one-thread times and stated
  assumptions A1–A5 (iPhone 14, 0.5–0.8× a Mac core, 1.8–2.5× for six cores, about 3 GB for an app, 5 W
  of a 12.7 Wh battery).

### The result

**Keep L2 batches (ADR-0001 option A, D-133). Do not reopen ADR-0001 now.** Prepare a mixed design
(batches by default, a segment proved when its batched cost would pass a proof's, about 79 M L2 gas) as a
contract lot **only after a SNIP-36 virtual transaction has been proved on a phone.**

Why, in brief:

1. S1 does not need proofs and may get worse with them: at the central reading (13 segments) it costs
   1.62× more proved; proofs win S1 only when its Fate actions and gates together are about 6 or fewer (F + G ≤ 6; F + G = 7 with no gate is a tie, with any gate it loses; E, `cost.py`).
2. Heavy fights are where proofs win (0.08× to 0.10×, E), but the phone pays for it: 12–32 % of the
   battery for 13 proofs, against SPK-6's 8 % for 30 minutes of play. The "as it stands" worst tick
   (45.8 M) exceeds the 40 M batch limit (SPK-15), so its batched price is notional; only the "with
   L1–L4" 35.9 M is sendable.
3. The path is not open: no prover answers PROOF2 today (slingfall SN1 §5), nobody has measured a virtual
   transaction's proving time, and no Stwo virtual-OS prover runs on a phone.
4. The design cost is real: co-op needs a leader or loses whole segments, the chain would store a hash
   of the state, and the client would hold the logic three times (mirror, Cairo VM, prover).

**Deviation from the brief**: the brief cites D-64 (a chunk generated at reveal from a fresh random word)
and asks for each reveal as a segment boundary. The owner's later D-111 (one draw at entry, then a value
built from the adventurer's irreversible actions; ADR-0006 option C) replaced it, so the note models
reveals inside segments. Nothing in the analysis depends on D-64.

### Key figures

Proving on the Mac, `canonical_small`, verified, two runs each, deterministic proofs (M):

| Segment | Cairo steps | Wall time (s) | Peak RSS (GiB) | Proof bytes |
|---|--:|--:|--:|--:|
| representative, 1 tick | 22,918 | 14.77 / 13.69 | 3.60 / 3.65 | 1,090,994 |
| worst, 1 tick | 128,172 | 23.46 / 25.93 | 3.71 / 3.61 | 1,098,531 |
| busy, 10 ticks (CBT-02's busy batch) | 247,686 | 26.13 / 25.39 | 3.74 / 3.74 | 1,095,396 |
| representative, 2,600 ticks (the largest under `canonical_small`) | 13,781,143 | 164.33 / 183.73 | 21.03 / 20.57 | 1,202,257 |
| representative, 4,500 ticks, `canonical_without_pedersen` | 23,838,746 | 344.10 / 313.53 | 23.50 / 33.56 | 1,255,743 |

- A floor dominates: 14–31 s and 3.6–3.9 GiB for every segment under ~0.5 M steps (representative
  14–18 s, worst:1 23–26 s, busy:10 25–26 s, busy:40 27–31 s; 37–78 s and 3.0–3.7 GiB on one thread);
  above it about 11–14 s and 1.5 GiB per million steps (M, D). Six threads are as fast as twelve.
- `canonical_small` stops at 2^20 range checks (2,700 representative ticks fail); the proof is
  1.08–1.26 MB; verification 0.19–0.58 s.
- A tick's computation is about 115–121 L2 gas a Cairo step (D).
- Phone (E): 19–87 s a segment from the floor (representative:1) to busy:40, 3.0–3.9 GiB against about
  3 GB an iOS app may hold, so the prover as built does not fit; 13 proofs take 2.7–12.3 % of the battery
  from the floor to busy:40 (`cost-output.txt`) and 12–32 % on a fight-heavy expedition. 8 % is crossed
  above about 56 s of phone time a proof, inside busy:40's 35–87 s.
- One proof is a flat 75,000,000 L2 gas (M, slingfall on the devnet); a proved segment costs 79,472,160
  L2 gas, $0.070 (E).
- A proof holds 46 worst ticks as they stand, 66 with L1–L4, 680 representative ticks (E).

S1 against batches (E, `cost-output.txt`; batches 663.0 M, $0.584):

| Fate actions, gates | Segments | Ticks a segment | Proofs | Ratio |
|---|--:|--:|--:|--:|
| 5, 0 | 6 | 50 | 498.2 M, $0.439 | 0.75× |
| 10, 2 (central) | 13 | 23 | 1,076.3 M, $0.948 | 1.62× |
| 20, 4 | 25 | 12 | 2,066.3 M, $1.820 | 3.12× |

Fight-heavy expedition, 300 worst ticks, each alone under D-172 (E):

| Worst tick | Batches | Proofs | Ratio |
|---|--:|--:|--:|
| as it stands (45.8 M, over the 40 M limit: notional) | 13,784.1 M, $12.144 | 1,076.3 M, $0.948 | 0.078× |
| with L1–L4 (35.9 M) | 10,826.3 M, $9.538 | 1,076.3 M, $0.948 | 0.099× |

Break-even, ticks a segment above which one proof costs less than the same ticks batched: 39 at S1's
average batched tick (2,066,003 L2 gas, after taking `enter`, `leave`, 10 Fate actions and 2 gates,
43.2 M, out of the 663 M), 55 at the representative tick's target, 2 at a worst tick alone as it stands,
3 with L1–L4.

### The owner's questions

| # | Question |
|---|---|
| Q1 | Is the cost of a heavy fight (36–46 M a worst tick alone, D-172) acceptable, or should SPK-15's design levers make it impossible by rule, or should proofs carry it? |
| Q2 | May an instance's state on chain be a hash, with the words published in events (§5)? It changes design/02's rule that the indexer is never a source of simulation state. |
| Q3 | Co-op with proofs: a leader who orders the party's actions, or whole segments refused on collision (§6.1)? |
| Q4 | Is a proof-time wait before every loot acceptable (§6.2), on top of today's Fate wait? |
| Q5 | SNIP-36 phase 1 is verified by consensus only, and its proofs are not kept in blocks: acceptable for game state? |
| Q6 | Does the next spike (a virtual transaction proved on a phone) get a prover endpoint or a machine for the virtual OS when one exists? |

## Files changed

- `docs/research/SPK-12-client-proving.md`: the note.
- `docs/reports/SPK-12-client-proving.md`: this report.
- `spikes/SPK-12/`: the proved segment (`src/`), its tests (`tests/`), `prove/`, `cost.py`,
  `cost-output.txt`, `prove-output.txt`, the two `snforge-test-output-*.txt`, `README.md`.

## Commands run

```sh
spikes/SPK-12/prove/setup.sh --native
python3 spikes/SPK-12/prove/prove.py ...   # runs run1 to run8 (run6a, run6b); each one's exact command is
                                           # the header of its table in spikes/SPK-12/prove-output.txt
python3 spikes/SPK-12/prove/collect.py     # the runs' tables -> prove-output.txt
python3 spikes/SPK-12/cost.py              # -> cost-output.txt
(cd spikes/SPK-12 && snforge test)         # two clean runs -> snforge-test-output-1.txt, -2.txt
```

## Remaining

The recommendation's next steps, in order: ENG-07's representative fight tick, then `cost.py` rerun; a
spike proving a SNIP-36 virtual transaction of `TickLibrary.run` on the Mac and then the iPhone 14; only
then a design change and a contract lot for `submit_segment`.
