# Gate A-G1 of track ARC: the API of quiver — accepted 2026-09-28 (D-131)

| | |
|---|---|
| Asked by | `[Opus 5.5]` orchestrator of `quiver` |
| Decided by | `[Fable 5.1]` project manager, under D-128; reported to the owner |
| Source | `bal7hazar/quiver`, `main`: `docs/decisions/PENDING-A-G1.md`, `docs/research/ARC-01-quest-achievement.md` (`[Opus 5.5]`); audit `[GPT-6-Sol]`, three passes, PASS WITH FINDINGS, no blocker or major open |

## Decision

**Option A: the API is accepted** with the answers recommended for Q-1 to Q-20.

| What is accepted | |
|---|---|
| Packages | `quiver_quest`, then `quiver_achievement`; first version 0.1.0 |
| Shape | Tasks with a target, windows, intervals, AND prerequisites, completion, claim, hooks; storage or event mode per call; definitions always stored; no presentation on-chain |
| Prerequisites | Evaluated lazily: met once each has been completed at least once; cached per player |
| Packing | `u32` ids, `u64` interval ids and counters, every record in one storage slot; 3 tasks per quest or achievement |
| Progress | One aggregated call per player and per transaction, at most 16 distinct tasks |
| Access control | In the package: only registered reporters report progress; administration and player authorisation are hooks of the consumer |
| The fourteen defects found in the Dojo packages | Each is a named test case of ARC-03 or ARC-04 |

Not decided here: **publication**. The first publication of each package is asked of the
owner when the package is accepted (D-128).

## The game's answers

| # | Question | Answer | Why |
|---|---|---|---|
| Q-18 | Does a held guild contract survive the day? | **No.** A contract held and not finished at 00:00 UTC is lost with its progress; the board offers the new day's | Contracts are daily (design/14); an acceptance that outlives its interval would let a player hoard the best ones |
| Q-19 | A ceiling on the distinct tasks one expedition reports | **16, enforced by the game.** At entry the instance snapshots the task ids it will report (the adventurer's active quests and contract, the titles in progress), 16 at most; the results interface reports only those | Bounded execution (CONTEXT §8). Three active quests of three tasks, one contract and the MVP's titles fit. An input of ENG-01 |
| Q-12 | Repeatable quests without an interval | **Not needed in 0.1.** What repeats in the game is the daily contract | design/06's `repeatable` is what design/14 calls a contract |
| Q-17 | A daily quest rolls over at 00:00 UTC only if its start is a multiple of 86 400 | Accepted; the game's content validation checks it | design/14 |
| Titles | The game's own counters and a tier table, or `achievement`? | **`quiver_achievement` in event mode** (D-63). The game keeps the counters that are its own (the "distinct" bitmaps of design/13) and reports their progress as tasks. **ARC-04 is on the game's path**, after `quiver_quest` | One mechanism for tiers and claims; design/13's note is corrected |
