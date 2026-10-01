# CBT-03a: five readings of one hit, frozen in its vectors, for confirmation

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from CBT-03a ([#229](https://github.com/bal7hazar/grimworld/pull/229); report *Open questions* 1–4; a Claude Sonnet quality run's notes SQ 1, SQ 3) |
| To be answered by | `[Fable 5.1]` project manager (design/19 is the design's; a rule left open is an escalation, D-150) |
| Needed by | the client's TypeScript mirror, which consumes `contracts/logic/vectors/hit.jsonl` (D-140); not CBT-03a's merge (the answers move vectors, not the code's shape) |

CBT-03a computes one hit as design/19 §5.5–§5.6 says. Where the documents leave a case open, it chose
the reading below, tested it, and froze it in the vector table. Each is a one-line change if decided
otherwise, and moves the vectors.

| # | Case | CBT-03a's reading | Source it follows | Recommendation |
|---|---|---|---|---|
| 1 | The axe's +25 % on a knocked-down or sleeping target hit from a front arc | the critical alone; the axe's +25 % only from rear-side and back | design/04 (the axe's arcs) | confirm |
| 2 | A sleeping target | critical from any arc, and its first hit unblockable | design/04 *Other sources of critical strikes*; design/19 names only the unblockable hit | confirm, and write the critical into design/19 §5.4 |
| 3 | A target holding both a block and an evasion, hit in melee from the front | block first (a charge spent) | design/19 §5.5 step 2's order "miss, block, evade" | confirm |
| 4 | FX-19's halving on a hit that would kill | halves it (300 health, 301 damage → 150) | FX-19's formula `2(h ⊖ d) < max` | confirm (the halving is a survival mechanic; a killing blow is its case) |
| 5 | A sleeping target and evasion | evades (only a knocked-down target loses evasion, FX-7) | design/19 §5.6 to the letter | **decide**: a sleeper that evades reads oddly; recommended: **a sleeping target neither blocks its first hit nor evades** (one line, `&& !asleep`, in CBT-03a's next fix loop or CBT-05a) |

Recorded for CBT-05a, no decision needed: `asleep` means "asleep before this hit"; the executor clears it
when the target notices (§5.5 step 9), so only the first hit gains from it.

## Decision

Pending.
