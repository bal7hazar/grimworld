# Needs — Arcade packages (native)

What the game asks of the native rewrites of the Arcade packages (PLAN, track ARC; D-124).
Written by the game's side, answered by the track through releases.

| # | Need | For | Asked | Answered in version |
|---|---|---|---|---|
| A-1 | Quests made of tasks with a target count; one-shot and with an interval (daily, aligned on 00:00 UTC) | Quests, guild contracts (design/06, design/14) | 2026-09-28 | — |
| A-2 | Prerequisites between quests (AND) | Quest chains (design/14) | 2026-09-28 | — |
| A-3 | Progress keyed by a `felt252` the game chooses: the adventurer's id for character quests and titles, the account's for account titles | design/13, ADR-0004 | 2026-09-28 | — |
| A-4 | A claim hook the game implements (experience, gold, merit, skills, items) | design/06 | 2026-09-28 | — |
| A-5 | Progress reported by the contract that causes it, never by the client; callable from the results interface of the ephemeral contract | design/06 § Rules, ADR-0001 | 2026-09-28 | — |
| A-6 | Storage mode for what a rule reads, event mode for what is only shown, chosen per call | ADR-0004 | 2026-09-28 | — |
| A-7 | Achievements with tiers sharing one task | Titles (design/13) | 2026-09-28 | — |
| A-8 | No dependency on Dojo; builds on Cairo 2.19; `snforge_std` as a dev-dependency | ADR-0007 | 2026-09-28 | — |
| A-9 | The edge cases found by reading the Dojo packages are tests: unlock firing on every decrement, an inactive dependent quest reverting the whole progress call, a recurring prerequisite underflowing a lock counter, event mode untested | ADR-0004, points 3 and 4 | 2026-09-28 | — |
