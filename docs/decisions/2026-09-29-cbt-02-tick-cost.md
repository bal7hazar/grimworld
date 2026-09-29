# CBT-02: the tick's cost against the expedition's budget

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from CBT-02 ([#182](https://github.com/bal7hazar/grimworld/pull/182), report *Cost* and *Escalations* 1; ENG-01 §9.2 as amended) |
| To be answered by | `[Opus 5.5]` project manager: D-159 asked for the overrun to be reported, not accepted |
| Needed by | CBT-03 to CBT-05 and ENG-07 (they add the executor, the AI, the window and the writes to the same budget); R-2 |

D-159 set **1,469,435 L2 gas a tick inside a batch** (what S1 needs for $0.50, cost-budget §2).
CBT-02 built the tick's pipeline as pure rules in `TickLibrary` and measured it (snforge, net of fixtures):

| Per tick | Representative | Worst |
|---|---:|---:|
| Through one library call, a batch of 10 ticks | 823,131 | 1,022,562 |
| The content the tick reads, once per batch (D-145) | 190,291 | 371,082 |
| **The tick's share** | **1,013,422 (69 %)** | **1,393,644 (95 %)** |
| Left for the executor, AI, flood, window, writes and floor | 456,013 | 75,791 |

*Representative*: the member with one condition and one effect, 8 awake goblins of 2 castes. *Worst*:
every actor with several degenerating conditions and effects, 4 activations resolving. **The target
cannot hold once CBT-03 to CBT-05 and ENG-07 add their parts, unless levers are taken.**

| Lever (CBT-02's report) | Estimated effect | Changes |
|---|---|---|
| (a) no copies of the goblin struct across the three passes (hot fields apart, masks of due activations) | the pipeline −30 to −50 % (estimate) | CBT-02's code only |
| (b) a cheaper split of a word into limbs (`packing::split`, ~5.8k a word, ~40 words a call) | up to ~1.9 M a worst call | `packing`, which every layout uses |
| (c) compact tick sheets written at registration (CAIRO §1) | the extraction (41k a record) and half the reads of two-part records | the registry (ENG-03), the content pipeline |
| (d) the content packed into fewer calldata felts (~230 felts on the worst state) | most of the call's 799,800 | the library call's interface |
| (e) design: fewer awake goblins, a batch's weight, the target itself | — | the design; the owner's for the target |

`TickLibrary` is already 23.08 % of the class limit; CBT-03 to CBT-05 add the executor to it.

**Recommendation:**
1. **(a) and (b) now**, as one follow-up of CBT-02 (CBT-02b), re-measured; they change no interface
   and cost no design.
2. **(c) and (d) with ENG-07**, which builds the content's sheets once per batch and wires the call:
   decided on its measure of a whole batch (CB-2).
3. **(e) only after ENG-07's measure**: R-2 is decided then, on real figures, with S1's running
   estimate (STATUS).
4. CBT-02 merges with its cost escalated (this file), once its audit passes; its measure stays in
   ENG-01 §9.2 as the reference the follow-ups improve on.

## Decision

**D-161**, `[Opus 5.5]` project manager, 2026-09-29, under D-128.

1. **The orchestrator's plan is accepted**: (a) no copies of the goblin struct and (b) a cheaper limb
   split now, as **CBT-02b**, re-measured, no interface change; (c) compact tick sheets and (d) packed
   content calldata decided with ENG-07 on its whole-batch measure; (e) the design's levers and R-2
   after ENG-07's measure; **CBT-02 merges with its cost escalated** once its audit passes.
2. **The worst tick is above its target with the map included.** The map library measured its part
   of a worst tick at 1.06M to 1.11M (window, flood at 15 layers, 8 walkers; `hexx-cairo`,
   LIB-05-M1-T9b), which this tick's 1.01M to 1.39M does not count. A worst tick is therefore about
   **2.1M to 2.5M before writes and the executor**, against 1.47M. The mixed expedition may still
   hold (shared reads, ticks without goblins awake); S1 does not without a lever. R-2 is
   **likely**, no longer a watch.
3. **SPK-12, client-side proving, is run now**, lent to track CV on the Mac (D-149): the one lever
   that changes the order of magnitude, since ADR-0001 option D priced a proof at about 75M L2 gas
   (not measured by us), against about 660M for S1. It compares, on our figures: L2 batches as
   designed; proving the deterministic segments on the client (SNIP-36) and settling one proof per
   segment, with randomness (entry, reveal, loot) staying as L2 transactions; its proving time on
   the Mac and an estimate for a phone, the proof's size and verification cost, what it does to
   co-op (D-80), to the fresh word of each reveal (D-64), to the client (the Cairo code run in the
   client, SPK-4 option b) and to cheating. It reads the owner's `slingfall` programme, which proves
   with SNIP-36 (`docs/proving.md`). **Reopening ADR-0001 is the owner's decision**, on SPK-12's
   report.

**What would reverse it**: ENG-07 measuring a tick inside a batch near its target (then SPK-12
stays a study for version 1).

