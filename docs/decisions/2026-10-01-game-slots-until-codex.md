# The game's slots until Codex returns (2026-10-04 13:36 UTC)

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, 2026-10-01 04:20 UTC |
| To be answered by | `[Fable 5.1]` project manager (D-150's rule: what is pulled forward while the engine chain waits) |
| Needed by | now: both game slots are idle |

**Where the game is.** CBT-02d (#211) and CBT-02f (#219) are **merged**, with CBT-02c (#206) and
CBT-02e (#212): the CBT-02 chain is done. ENG-R1a (#221) is built, green, and waits for Codex's two
audits and review (blocked until 2026-10-04 13:36 UTC); its Claude-side quality lens runs now (as
decided). ENG-R1b waits for the owner's reading of ENG-R1a; ENG-05 and ENG-02 wait for `hexx` rc.1;
ENG-07 after ENG-05. **No lot is briefed and ready.**

**The lots whose dependencies are met** (PLAN): CBT-03, CBT-04, CBT-05 and CBT-06 (each after CBT-02).
- CBT-03 (damage) needs arcs and flank, which are ENG-02's (line of sight and arcs on `hexx`), waiting.
- CBT-06 needs the shared flood pathfinding, the map library's.
- CBT-05 (the skill engine) is the largest, and builds on damage and conditions.
- CBT-04 (the five conditions) needs nothing that waits.

| Option | Effect |
|---|---|
| (a) **CBT-04 and CBT-03a now**, two slots: CBT-04 the MVP's five conditions; CBT-03a the damage formula, armor, critical and D-140's edges, with the arc and flank **as inputs** (wired by ENG-02 later); disjoint files in the logic package, each a rule of the tick's executor (CBT-02's hooks) | both slots used; their Codex audits queue for the reset and their merges wait; Claude-side lenses meanwhile. ENG-R1c (the logic package's organisation) comes after them, so it reworks their code once |
| (b) CBT-04 alone | one slot used; less to merge at the reset |
| (c) Nothing until Codex returns | no work for three days; the owner's reading of ENG-R1a only |

**Recommendation: (a).** Both are rules design/19 already closes (§5's order, the catalogue, D-140, D-155,
D-157), they write new code on the pattern from the start, and neither touches `Hub` (ENG-R1a's).
Merges at the reset in the order ENG-R1a, CBT-04, CBT-03a.

## Decision

**D-170**, `[Fable 5.1]` project manager, 2026-10-01, under D-128: **(a)**. CBT-04 (the five
conditions of the MVP) and CBT-03a (damage, armor, critical, D-140; arc and flank as inputs until
ENG-02) start now, in disjoint files, on CBT-02's tick as CBT-02d left it; on the pattern of CAIRO.md
§7 and the test rule of §2 (D-167). Their claude-side lenses run meanwhile; their Codex audits and
reviews queue for the reset of 2026-10-04 13:36 UTC (or earlier, if the owner repairs the account);
they merge after ENG-R1a, so that the pattern's first lot on the game lands first. Each brief carries
the per-tick budget of CBT-02d's re-proved bound (3,447,872 a tick inside a batch, 2.35× the target,
reported and not accepted: ENG-07 derives the batch's weight, D-166) and states what it adds to it.

**What would reverse it**: `hexx` rc.1 landing first (then ENG-02 takes a slot back).

