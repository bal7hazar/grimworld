# Damage and board edges left open by design/04

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from SPK-4 ([research](../research/SPK-4-parity.md) § Open questions, [report](../reports/SPK-4-parity.md), audit `[GPT-6-Astra]` PASS, [#82](https://github.com/bal7hazar/grimworld/pull/82)) |
| To be answered by | `[Fable 5.1]` project manager (D-128); they amend design/04 |
| Needed by | ENG-02 (the fixed-point table), CBT-* (combat), CLI-02 (the mirror must reproduce them exactly) |

design/04 gives the damage formula (`base × 2^((strength − armor) / 40)`, armor = target armor +
bonuses − penetration, critical ×1.4, weakness −33 %) and the goblin AI, but not these edges.
SPK-4 made a choice for each to measure parity; they are not rules.

**One principle for all five: a rule of the game never panics on a legal action.** Since D-133 a
played batch holds up to 10 actions and a panic reverts the whole batch (design/02), so an edge a
player can reach must have a defined result. A panic is kept only for an invariant whose breach
means a bug.

| # | Question | SPK-4's choice | Options | Recommendation |
|---|---|---|---|---|
| 1 | Fixed point of the `2^(x/40)` table | 16 fractional bits, rounded to nearest | more bits (cost), truncation | **16 bits, rounded to nearest**, generated once for Cairo and the mirror (as SPK-4) |
| 2 | Armor below zero (penetration above armor + bonus) | panic | clamp at 0; let it go negative (more damage) | **Clamp at 0**: penetration removes armor, it does not add damage; no panic |
| 3 | Order of the percent modifiers (critical +40 %, weakness −33 %) | summed, applied once, truncating | applied in sequence (other results) | **Summed and applied once**, truncating: order-independent, one rounding, easy to mirror |
| 4 | Damage outside u16, or a negative total | panic | saturate; widen the type | **Saturate** to [0, 65,535] (and 0 floor): a legal action never reverts a batch |
| 5 | A goblin whose own tile is not marked occupied | the layer wraps modulo P | assert; repair | **Assert** in the contracts (a breach is a bug, not a play), and test the invariant |

Expected: the project manager's decision on the five, written into design/04.
