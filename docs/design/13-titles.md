# 13 — Titles

> Status: **Draft v0.1** — names are working names; thresholds are initial values.
> Baseline: the title system of Guild Wars (official wiki, read 2026-09-28) and what its
> players said of it.

## What a title is

A title is a line of text shown under an adventurer's name in hubs. It records something
done. One title is displayed at a time, chosen by the player among those earned.

| | Character title | Account title |
|---|---|---|
| Progress belongs to | One adventurer | The account, all adventurers together |
| Records | What this adventurer did | What the player did, whoever they played |
| Survives deletion of the adventurer | No | Yes |

## Rules (D-38)

| # | Rule | Why |
|---|---|---|
| T-1 | **A title never changes a game rule**: no statistic, no skill strength, no drop chance | In Guild Wars, titles that scaled skills turned a cosmetic into near-mandatory power, against its own promise. Pillar 2 |
| T-2 | **A title rewards something done, not something repeated.** Thresholds count distinct things (locations, bosses, recipes, quests) rather than raw quantities | Its most criticised titles were counters that could be filled by buying items or by leaving the game running |
| T-3 | **No title can be lost to an accident.** A track that can reset keeps the best tier reached | Its survival title used to freeze forever at the first death, including on a disconnection |
| T-4 | **Progress is recorded by the system that causes it**, never claimed by the client | Same rule as quests |
| T-5 | Anything that is a repeated account-wide effort is an **account** title | It moved two of its titles from character to account after complaints |
| T-6 | Progress is not retroactive unless the counter already exists on-chain | Cost and simplicity |

## Character titles

| Title (working name) | Counts | Tiers |
|---|---|---|
| **Pathfinder** of *region* | Zones of the region **entirely revealed within one instance** (every chunk of the outline) | 1 zone / half / all |
| **Warden** of *region* | Distinct quests of the region completed | 50 / 80 / 100 % |
| **Nestbreaker** | Distinct dungeons cleared | 1 / 3 / 6 / all |
| **Bane of** *caste* | Distinct packs compositions defeated that include the caste, plus its boss | 3 tiers per caste |
| **Unbroken** | Experience gained since the last defeat; keeps the best tier | Level 20 worth / 4× / 10× |
| **Flawless** | Promotion trials passed on the first attempt | 1 / 3 / all |
| **Skill hunter** | Distinct elite skills captured | 25 / 50 / 100 % of a profession's |
| **Grimoire keeper** | Recipes discovered in a book (the grimoire is personal) | 50 / 100 % per book |
| **Collector's friend** | Distinct collector offers completed | 25 / 50 / 100 % per region |

## Account titles

| Title (working name) | Counts | Tiers |
|---|---|---|
| **Veteran** | Highest guild rank reached by each profession played | 1 / 3 / 6 professions at Silver |
| **Appraiser** | Rare items identified | 5 tiers |
| **Scavenger** | Remains looted | 5 tiers, steep |
| **Trophy hunter** | Distinct boss items obtained | 25 / 50 / 100 % |
| **Landholder** | Sum of the estate's building levels (post-MVP) | 5 tiers |
| **Founder** | Account created during a given season | 1 tier, never obtainable again |

## Meta-title

| Title | Counts |
|---|---|
| **Renowned** | Number of titles brought to their last tier, character and account together: 3 / 6 / 10 / 15 / 20 |

## MVP

Pathfinder, Warden, Nestbreaker, Unbroken, Flawless, Grimoire keeper for Region 1; Veteran
and Scavenger for the account. The others come with the features they count.

## Implementation notes

- Persistent domain. Most titles read counters that other systems already keep (quests
  completed, rooms discovered, recipes). A title adds a tier table in a registry, not a
  new counter, whenever possible.
- Tiers are evaluated when the player opens the title or claims it, not at every action.
- "Distinct" counters are bitmaps keyed by registry ids, which bounds their cost.
