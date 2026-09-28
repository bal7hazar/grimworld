# 06 — Guild: ranks and quests

> Status: **Draft v0.1** — numbers are initial values for balancing.

## Two axes of progression

| Axis | Measures | Cap | Earned by | Unlocks |
|---|---|---|---|---|
| **Level** | Raw power (health, attribute points) | 20, reached early | XP from kills and quests | Attribute points |
| **Guild rank** | Reputation and trust | Platinum, long-term | Quest merit + promotion trial | Quests, zones, elite zones, trainers, secondary profession |

Level is the tutorial; rank is the career (pillar 2).

## Rank ladder (D-20)

Ranks are worn as a tag made of the rank's material.

| # | Rank | Merit to be eligible | Unlocks |
|---|---|---|---|
| 0 | **Wood** | — (registration) | Region 1 town, tier 1–2 quests |
| 1 | **Tin** | 100 | Tier 3 quests, first dungeon |
| 2 | **Copper** | 300 | Tier 4 quests, **secondary profession** quest |
| 3 | **Iron** | 700 | Second outpost trainers |
| 4 | **Bronze** | 1 500 | Tier 5 quests |
| 5 | **Silver** | 3 000 | Tier 6 quests, **elite zones** |
| 6 | **Gold** | 6 000 | Elite quests, region-level bounties |
| 7 | **Platinum** | 12 000 | Prestige; future content |

The ladder is a registry: ranks can be appended as regions are added.

### Promotion

Reaching the merit threshold makes the adventurer **eligible**. Promotion itself requires
passing a **promotion trial**: a specific quest given by the guild, played in a dedicated
dungeon with fixed parameters and designed to check one competence (e.g. Tin trial: clear
a nest led by a shaman; Silver trial: defeat a champion).

- Trials can be retried without limit; failure costs only the expedition.
- Trials use a fixed seed per rank so that they are a fair, comparable test.

## Quests

### Quest board

Each hub has a guild board listing the quests available **to this adventurer**: filtered by
rank, region unlocks and prerequisites. An adventurer holds at most **3 active quests**.

### Quest types

| Type | Objective | Completed |
|---|---|---|
| **Extermination** | Kill N goblins of caste X in location Y | On last kill |
| **Nest clearing** | Kill the boss of dungeon D | On boss kill |
| **Gathering** | Bring N of ingredient I | On hand-in (consumes items) |
| **Scouting** | Reach gate/landmark in location Y | On reach |
| **Delivery** | Carry a parcel from hub A to hub B through the wilds | On hand-in |
| **Trial** | Promotion trial | On instance success |
| *Escort* | Not planned: allied characters in instances were considered and dropped | — |

### Quest definition (registry entry)

```
Quest {
  id, region, giver_hub,
  kind,                       // one of the types above
  target, quantity, location, // objective parameters
  rank_required,              // minimum guild rank
  prerequisites,              // quest ids that must be completed
  repeatable,                 // one-shot (story) or repeatable (board)
  rewards { xp, gold, merit, skill_id?, item? }
}
```

### Rules

- Objective progress is recorded on-chain by the system that causes it (a kill, a gate
  reached), never claimed by the client.
- Progress is **kept on defeat** (see
  [02-core-loop](02-core-loop.md#ending-an-expedition-d-04)): a quest asking for ten kills
  can be finished over several expeditions.
- Rewards are claimed at a guild board in a hub.
- Repeatable quests give reduced merit after the first completion (diminishing to a floor)
  so that rank reflects breadth, not farming of one quest.

### Skill quests

As in GW1 pre-Searing, **the first skills of each profession are quest rewards** from the
profession's trainer. This is how the tutorial teaches the build system: one skill at a
time, each with a quest built around using it.
