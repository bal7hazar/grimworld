# `quiver_quest`: how the worst call is bounded — decided 2026-09-28 (D-135)

| | |
|---|---|
| Asked by | `[Opus 5.5]` orchestrator of `quiver`: `bal7hazar/quiver`, `docs/decisions/PENDING-quest-cost-cap.md` |
| Decided by | `[Fable 5.1]` project manager, under D-128; it amends the API accepted at gate A-G1 (D-131) |
| Origin | The project manager's request that the worst call the package allows stay under 20M L2 gas: the first component measured about 704M for a call its caps allowed |

## What was measured

| | L2 gas |
|---|---|
| A quest that completes | 1.17M, of which about 0.92M are its two changed storage slots |
| **A storage slot changed by a transaction** | **About 402 000 beyond the computation of the write, once per slot and per transaction** |
| 16 tasks per call, one quest per task, no prerequisite | 20.6M: no cap on quests per task fits 16 tasks under 20M |
| The game's own use (16 tasks, 3 quests and one contract completing) | 10.1M |

## Decision

**Option (d): the package bounds what a player holds, not what a task reaches.**

| | |
|---|---|
| Acceptance | Mandatory for every quest |
| Held quests | A short list per player, at most **H = 4** by default (a constant of 0.1.0), 8 at most |
| Progress | Walks the player's held quests, not the pages of the tasks |
| Worst call | About 5.6M for H = 4 and 10.9M for H = 8 (estimates from the measured model), whatever the number of tasks, of quests per task and of prerequisites |
| Prerequisites | Checked at acceptance |
| Work | A new lot, ARC-03c, Opus 5.5, audit `[GPT-6-Astra]`; the component's frame, access control, events, hooks and claim of ARC-03b are kept |

## Why

The game's rules are the same bound: an adventurer holds at most 3 quests and one contract
(design/06, design/14), and a quest counts only once accepted. The cost of a call then
depends on what the player holds, which a consumer can reason about, and no longer on how
many quests share a task, which grows with the content of the game. Raising the cap or
cutting the tasks per call would have kept a worst case that content can reach.

## For the game

| | |
|---|---|
| Every quest of the game is accepted before it progresses | True of the board, of the contracts and of the main chain (design/14) |
| H = 4 | 3 active quests and one held contract. A change of that rule of the game changes H |
| Titles | Not counted: `quiver_achievement` in event mode |
| **ENG-01** | **A changed storage slot costs about 0.4M L2 gas per transaction.** The number of slots a tick changes matters more than its computation: it is the first item of ENG-01's cost budget (D-129) |
