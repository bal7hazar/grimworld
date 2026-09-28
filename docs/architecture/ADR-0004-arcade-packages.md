# ADR-0004 — Reuse of the Arcade packages

> **Superseded in part by [ADR-0007](ADR-0007-native-starknet.md)** (2026-09-28, D-123): the game is built as native Starknet contracts, without Dojo, Torii or dojo.js. What this document says of them is kept for the record.

| | |
|---|---|
| Status | **Proposed** |
| Date | 2026-09-28 |
| Decides | Which features are built on the owner's existing Cairo packages, and in which mode |

Findings come from reading `cartridge-gg/arcade` at `main` (commit `c53fadc`,
2026-07-22) and the games that use it. **Nothing was built or run**: every statement about
behaviour is from reading the code.

## Context

The owner wrote Cairo packages for quests, achievements, social features and more, used
by several shipped games. Each feature generally offers two modes: **storage** (fully
on-chain) and **events** (cheaper, reconciled by the client or the indexer).

## What exists

| Package | Does | Mode | Shown by Controller |
|---|---|---|---|
| `achievement` | Achievements made of tasks with a target count; points, groups, hidden, time window | Chosen **per call** (`to_store`) | Yes, in both modes: list, progress, points, leaderboard by points |
| `quest` | Same, plus repeat intervals (daily, weekly), prerequisites, per-interval completion, claim | Chosen per call | Yes, **in storage mode only**; the claim button calls `quest_claim` on the game |
| `leaderboard` | Score event; optional bounded ranking in contract storage | Chosen per call | No |
| `social` | One-way follow; guilds with roles; alliances of guilds | Not selectable: follow is events only, guilds and alliances are storage only | No (Arcade site only). Deployed once in the Arcade world, across games |
| `orderbook` | Marketplace for tokens | Storage and events | Arcade marketplace |
| `bundle`, `merkledrop` | Paid bundles; airdrops | Storage and events | Purchase flow |

What event mode means for a contract: **it cannot read anything back**. Completion checks
return false, claims revert, hooks do not fire, prerequisites and time windows are not
enforced.

## Decision (proposed)

### Rule

> **Storage when a game rule depends on the data; events when it is only displayed.**

| Feature | Built on | Mode | Why |
|---|---|---|---|
| Quests, guild contracts | `quest` | **Storage** | Rewards, prerequisites and the daily interval must be enforced; Controller shows quests only in this mode |
| Titles | `achievement` | **Events** | A title never changes a rule (rule T-1). Controller shows them in either mode |
| Titles that a rule reads | `achievement` | Storage, for those only | None today. The mode is per call, so one title can be stored without the others |
| Rankings (trials, elite clears) | `leaderboard` | Events | Display only |
| Follow | `social` | Events | As the package does |
| Player guilds, alliances | `social` | Storage | As the package does; post-MVP |
| Auction house | To study: `orderbook` or our own | Storage | See design/16 |

### How it maps to our design

| Our concept | Package concept | Note |
|---|---|---|
| Quest | Quest with `interval = 0` | One-shot |
| Guild contract | Quest with `interval = duration = 86 400` | Daily, aligned on UTC midnight |
| Quest prerequisites | `conditions` | AND only |
| Objective (kill 10 runts) | `Task { total: 10 }` | The instance reports progress through the results interface (ADR-0001) |
| Reward | `on_quest_claim` hook | Ours to write: experience, gold, merit, skills, items |
| Who progresses | `player_id: felt252` | **We pass the adventurer's id** for character quests and titles, the account's for account titles |
| Title tier | One achievement per tier, same task | Tasks are shared across achievements |

## Points to settle before relying on the packages

| # | Point | Found |
|---|---|---|
| 1 | **Licence** | **MIT, stated by the owner (2026-09-28).** The `LICENSE` file read at the root of the repository on that date says otherwise (a custom non-commercial licence) and the package manifests say ISC or MIT: the repository should be made consistent with the owner's statement, so that nobody downstream reads the wrong terms |
| 2 | **Not published** | No package is on the registry; games pin a git revision. The latest tag predates the quest package |
| 3 | **Event mode is untested** | No test in `achievement` or `quest` uses `to_store = false` |
| 4 | **Quest edge cases** | From reading: unlock may fire on every decrement; an inactive dependent quest may revert the whole progress call; a recurring prerequisite may underflow the lock counter of a one-off quest. To confirm by tests |
| 5 | **Social flows** | From reading: guild creation, join and leave appear to revert or miscount; only constructor tests exist. To confirm by tests before any use |
| 6 | **Leaderboard** | Cap of 255 entries; packing keeps 32 bits of key and score |
| 7 | **Controller and the adventurer id** | Controller's profile is per account. Progress recorded under an adventurer's id will not appear under the player's account without a mapping. To test in Phase 0 |

## Dedicated repositories

The owner suggests one repository per theme. Recommended, for the reasons of the owner's
other programmes: one package, one repository, published on the registry, consumed **by
version**, with its own tests and changelog.

| Order | Package | Why first |
|---|---|---|
| 1 | `quest` | The game's career loop depends on it, in storage mode |
| 2 | `achievement` | Titles |
| 3 | `leaderboard`, `social` | Post-MVP; `social` needs its flows fixed and tested first |

This is work outside this repository. It belongs to a programme-level plan, with its own
orchestrator, and must not block Phase 0.

## Consequences

| | |
|---|---|
| + | Quests and achievements appear in Controller with no interface work |
| + | Daily contracts and prerequisites exist already |
| − | A dependency pinned by git revision until the packages are published |
| − | Our vocabulary collides: **"guild"** is the Adventurers' Guild in our design and a group of players in the package. The glossary now says **Guild** for the institution and **company** for a group of players |
