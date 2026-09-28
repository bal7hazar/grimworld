# SPK-8 — Arcade packages spike

## Agent
Title: `[Opus 5.5] SPK-8 arcade packages spike` · Profile: implement · Branch:
`chore/spk-8-arcade`

## Goal
After this task we know whether the owner's Arcade packages can carry the game's quests and
titles as ADR-0004 proposes: `quest` in **storage mode** (quests, guild contracts) and
`achievement` in **event mode** (titles), with progress keyed by the **adventurer's id**, on
the game's toolchain; and whether the edge cases ADR-0004 found by reading the code are real.

## Context
- **ADR-0004 in full**: *What exists*, *Decision (proposed)* and its rule (storage when a game
  rule depends on the data, events when it is only displayed), *How it maps to our design*
  (a quest is `interval = 0`; a guild contract is `interval = duration = 86 400`; progress
  keyed by `player_id: felt252`, which we set to the **adventurer's id** for character quests
  and titles and to the account's for account titles), and **Points to settle** 2 to 7 (not
  published, pinned by git revision; event mode untested; quest edge cases: unlock firing on
  every decrement, an inactive dependent quest reverting the whole progress call, a recurring
  prerequisite underflowing the lock counter of a one-off quest; leaderboard packing; Controller
  and the adventurer id).
- design/06 (quests: board, at most 3 active, repeatable with diminishing merit), design/13
  (titles: rules T-1 to T-6), design/14 (guild contracts, daily), CONTEXT §4, docs/CAIRO.md.
- The toolchain: the game is on **Cairo 2.13 and Dojo 1.8** (SPK-5). The packages live in
  `cartridge-gg/arcade`, `packages/` (ADR-0004 read `main` at `c53fadc`). **First question: do
  they build on Cairo 2.13 with Dojo 1.8?** If not, say at which revision they would, and stop
  that part (like N-9 for the map library): no fork, no patch of the packages.
- Depends on: SPK-5 (merged), FND-01 (merged; do not write into `contracts/`).

## Scope
- In, a throwaway Dojo world in `spikes/SPK-8/`:
  1. `quest` in storage mode: a one-off quest and a daily contract, prerequisites, progress
     reported with the adventurer's id as `player_id`, claim with an `on_quest_claim` hook of
     ours that records a reward; the daily interval checked across a day boundary (with the
     test framework's block-timestamp cheat: **outside any instance**, design/14 allows the date
     in the hub).
  2. `achievement` in event mode: a title with tiers, progress by adventurer id, events
     emitted; and one title in storage mode, to show that the mode is per call.
  3. **Tests for each edge case of ADR-0004 point 4**: each either reproduced (a failing
     scenario, kept as a test that documents it) or shown not to happen.
  4. **Controller and the adventurer id** (point 7): what the packages' events and models say
     for an account holding several adventurers; what Controller would therefore display. No
     Controller login is needed: read what Controller's code reads, and say it is from reading.
- `docs/research/SPK-8-arcade.md`: build status on the game's toolchain, the revision used and
  how it is pinned, each point of ADR-0004 settled with its evidence, gas of each call, and a
  recommendation for GLD-02 (use the packages, fork them into dedicated repositories — Q-22 —,
  or write our own), including the licence point 1 (read the repository's `LICENSE` at the
  revision used and report exactly what it says).
- Out: the game's quest system (GLD-02); Controller login (SPK-9); `social`, `leaderboard`,
  `orderbook`; any change to the Arcade repository; `contracts/`, `client/`.
- Allowlist: `spikes/SPK-8/**`, `docs/research/SPK-8-arcade.md`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 The build status of `quest` and `achievement` on Cairo 2.13 / Dojo 1.8, with the
      exact revision and error if any.
- [ ] AC-2 If they build: a quest and a daily contract progressed and claimed by adventurer id,
      tests with gas budgets.
- [ ] AC-3 Each edge case of ADR-0004 point 4 has a test that shows it or disproves it.
- [ ] AC-4 A title in event mode and one in storage mode, from the same package.
- [ ] AC-5 A recommendation for GLD-02 with its reasons, and the licence as read.

## Verification
From the worktree root:
```
scripts/lock.sh sozo build --manifest-path spikes/SPK-8/Scarb.toml
scripts/lock.sh sozo test --manifest-path spikes/SPK-8/Scarb.toml
```

## Audits
Design and security (PLAN: D S): the auditor checks that the mapping of ADR-0004 holds and that
nothing lets a player claim twice or progress another adventurer's quest.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the gas table of every call measured.
