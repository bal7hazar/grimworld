# CBT-01: the combat interfaces' open questions (A to I)

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from CBT-01 ([#165](https://github.com/bal7hazar/grimworld/pull/165); [report](../reports/CBT-01-combat-interfaces.md), *Escalations after fix loop 2* and *For the project manager*; final audit `[GPT-6-Astra]`, [archived](../reports/CBT-01-audit-gpt-6-astra.md), *Escalations: the auditor's view*) |
| To be answered by | `[Opus 5.5]` project manager (D-128) |
| Needed by | DES-06 (A, B, C, D, G), BAL-01 and CBT-02 (E), ENG-07 (F); none blocks CBT-01's merge |

CBT-01 froze design/19's data as compiling code after three fix loops: every major resolved, no
runtime or packing defect. One minor test-oracle finding, **CBT-9**, is deferred by the orchestrator
to CBT-02 (PLAN): the production snapshot builder aggregates bonuses for the same condition, and its
test oracle with it. The questions below are the ones design/19 and design/03 leave open.

| # | Question | Recommendation (implementer) | Auditor |
|---|---|---|---|
| A | The attribute id space: 4 bits in the snapshot's quick-cast pair, 8 in `ATTRIBUTE` and the `SKILL` header | (b) a global id in content, mapped to a build-local index in the snapshot by the flattening (ENG-06) | Agrees; **design/03 names 26 attributes, not 27** |
| B | Which slot type carries `QUICK_CAST_EVERY_N` | (c) whichever content names ("everything held"); DES-06 writes it | Agrees (inscription a reasonable default) |
| C | `DAMAGE_TYPE`'s slot type ("on the weapon") | (a) one weapon slot type for all content | Agrees; a suffix or inscription would need an item-context check |
| D | Health-rune identity ("runes of the same kind do not add up") | (a) no field: the flattening's rule, by modifier id | Agrees, if separately authored ids never stand for the same rune family |
| E | `ADRENALINE_DECAY`'s value (FX-12) | (a) set before CBT-02: **1 quarter a tick** (a strike every 4 ticks out of combat), BAL-01 may change it | Agrees: BAL-01 before CBT-02 uses it |
| F | The snapshot crosses `Instances.create` as 63 felts; three packed words would save most of it but change ENG-01 §4.2 | (b) decided with ENG-07 once `play` is measured | Agrees |
| G | Sums no document bounds (health, energy, regeneration bonuses across sources) | DES-06 gives each statistic a per-source bound, signed where it can be negative; CBT-01's validators and the flattening prove them | **A design dependency to settle before production snapshots**, with acceptance tests |
| H | Professions 1–6 in `ENERGY_COST` | (a) keep the six ids of design/03; content picks | Agrees |
| I | `ENERGY_COST`'s sign | signed delta (done in fix loop 3) | Resolved; a positive magnitude would be an interface change |

**Recommendation:** accept A to H as the table says, I as done; G assigned to DES-06 as a
prerequisite of production snapshots (CBT-02, ENG-07); E's starting value written in design/19 by
BAL-01's first pass or by DES-06, whichever comes first.

## Decision

Pending.
