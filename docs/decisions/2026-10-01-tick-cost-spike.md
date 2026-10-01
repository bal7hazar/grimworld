# The game's slots after CBT-04 and CBT-03a: the tick's cost, measured before CBT-05

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, 2026-10-01 05:45 UTC |
| To be answered by | `[Fable 5.1]` project manager (D-150, D-170) |
| Needed by | now: both game slots are free until Codex returns (2026-10-04 13:36 UTC) |

**Where the game is.** ENG-R1a (#221), CBT-04 (#228) and CBT-03a (#229) are built, green, and through
their Claude-side quality lens and fix loops (D-170). Their Codex audits are queued at their current
heads, and they merge after the reset in the order ENG-R1a, CBT-04, CBT-03a. ENG-R1b waits for the
owner's reading of ENG-R1a; CBT-05 builds on CBT-03a and CBT-04, which are not merged; ENG-05 and
ENG-02 wait for `hexx` rc.1. **No briefed lot can start.**

**The tick's cost keeps rising as the rules land** (each lot's measured per-tick line, at the MVP's
content; STATUS):

| | Worst tick inside a batch | × 1,469,435 |
|---|---:|---:|
| CBT-02d's re-proved bound | 3,447,872 | 2.35 |
| + CBT-04 (16 applications on the member at 108,100, 7 on goblins at 76,820, the predicates) | +2,368,590 | |
| + CBT-03a (15 hits at 46,250) | +693,750 | |
| **Now** | **≈ 6,510,212** | **4.43** |

CBT-05's executor (reading entries, gathering a hit's inputs, writing the actors back) comes on top.
The levers are ENG-07's (D-161, D-166), but two figures above invite a measurement first: applying
one condition to the member costs **108,100** (a goblin 76,820) for a few field writes, a figure whose
make-up is not yet measured; and CBT-02d's escalation 2 prices keeping the frozen goblins as words at
**~0.85 M a tick**.

| Option | Effect |
|---|---|
| (a) **SPK-15, the tick's cost levers measured** (Opus 5.5, one slot, a spike package: nothing merged into the contracts): the frozen goblins kept as words (CBT-02d's escalation 2), what one condition's application on the member is made of and what writing its fields in place would save, and the executor's own overhead estimated on CBT-03a's and CBT-04's functions; each lever's saving measured against the 6.51 M above, with its cost in code and in the frozen interfaces | the project manager decides ENG-07's and CBT-05's levers on measurements before CBT-05 is briefed |
| (b) CBT-05 now, stacked on CBT-03a's and CBT-04's branches | the executor starts; rebases when they merge; its cost adds to a bound already 4.4× |
| (c) Nothing until Codex or the owner | slots idle |

**Recommendation: (a)**, one slot. Its allowlist is a new `spikes/SPK-15/` only, so it touches nothing
of the three lots waiting. The second slot stays free for ENG-R1b when the owner has read ENG-R1a, or
for ENG-02 if `hexx` lands.

## Decision

**D-171**, `[Fable 5.1]` project manager, 2026-10-01, under D-128: **(a)**. SPK-15 takes one game
slot, in `spikes/SPK-15/` only (Opus 5.5, research with measurements; `[GPT-6-Astra]` on cost when
Codex returns), and measures, before CBT-05 is briefed: the frozen goblins kept as words (about
0.85M), what a condition's 108,100 on the member is made of, the executor's overhead. Its report
**tells the engineering levers (no rule changes) from the design levers** (fewer goblins awake, fewer
conditions, a smaller window), each with its gain on the worst tick and on S1, so that the owner
decides the design ones and the project manager the others. The other slot stays for ENG-R1b (on the
owner's reading of ENG-R1a) or ENG-02 (on `hexx` rc.1).

**The expedition's cost (R-2)**: the worst tick is about 6.51M with CBT-04's and CBT-03a's lines,
4.43× the target of 1.47M, before CBT-05's executor; S1's running estimate in STATUS follows it.
The threshold of $0.50 for 300 actions (D-129) is not reachable by engineering alone at this
figure: the owner is told, and SPK-12 (client-side proving, D-161, on the Mac) and the design levers
of SPK-15 are the two answers in front of the owner.

**What would reverse it**: SPK-15 finding the executor cheap and the goblins' words recovering most
of the 6.51M (then CBT-05 is briefed on its figures and R-2 is decided after ENG-07, as D-161 said).

