# 01 — World

> Status: **Draft v0.1**

## Lore frame

Placeholder names are marked with `*`; naming is its own task (see PLAN, track `LORE`).

The Frontier is the edge of the settled lands. Beyond the last walls, goblins breed in
caves, ruins and abandoned mines. They are weak alone, cruel in numbers, and they learn.
The kingdom's knights do not ride for a burned farm; the **Adventurers' Guild** does, for a
fee. Every goblin nest left alone grows a shaman, then a hob, then a lord.

Tone rules:

- Low fantasy. Magic exists but is costly and rare among common folk.
- Goblins are never comic relief. They ambush, flee, use traps and hostages.
- The player is not a chosen one. They are rank-and-file who may become a legend.
- No gore for its own sake; menace is conveyed through consequence, not description.

## World structure

The world is a **graph of regions**. A region is a self-contained content pack.

```
World
└── Region (e.g. "Ashfall Vale"*)
    ├── Town            ×1      shared    hub: guild hall, trainers, alchemist, bank
    ├── Outpost         ×0..n   shared    small hub at the far end of zones
    ├── Explorable zone ×1..n   dedicated open-air area between hubs
    ├── Dungeon         ×0..n   dedicated multi-floor nest, entered from a zone or hub
    └── Elite zone      ×0..n   dedicated rank-gated, hardest content, unique rewards
```

### Location types

| Type | Instance | Time | Purpose |
|---|---|---|---|
| **Town** | Shared | Real time, no tick | Social hub, all services, guild board |
| **Outpost** | Shared | Real time, no tick | Forward base: limited services, entry to deeper zones |
| **Explorable zone** | Dedicated | Player tick | Travel, quests, gathering. Connects hubs |
| **Dungeon** | Dedicated | Player tick | Multi-floor nest with a boss. Quest targets |
| **Elite zone** | Dedicated | Player tick | End-game challenge; elite skill capture; gated by rank |

### Connectivity

- Locations are linked by **gates**. A gate has a source location, a destination location
  and optional requirements (rank, quest flag).
- Walking through a hub gate **creates a dedicated instance** of the zone behind it.
- Reaching the far gate of a zone **unlocks the destination hub** for that adventurer.
  Unlocked hubs can be reached by **map travel** from any hub (as in GW1).
- Outposts are therefore earned by crossing the wilds at least once.

### Geography: fixed vs shifting (D-10)

| Location | Layout | Populations |
|---|---|---|
| Explorable zone | **Generated at reveal**, within the zone's biome, level band and set pieces | Generated; levels within the zone's band, never scaled to the adventurer |
| Dungeon | **Shifting**: derived from the instance seed. Different each run | Vary per instance seed |
| Elite zone | Fixed layout, hand-tuned parameters | Hand-tuned packs, varies lightly |

Every location is generated chunk by chunk when revealed
([ADR-0006](../architecture/ADR-0006-chunked-maps.md)). A zone keeps a character of its
own through its biome, its level band, its anchors (where its gates are) and its authored
set pieces.

## Horizontal scaling

Content is **data in registries**, not code (pillar 6). Adding a region must not require
redeploying core systems.

| Registry | Entry defines |
|---|---|
| Region | id, name, town, list of locations |
| Location | id, type, region, generator parameters (size, biome, seed), level range, rank requirement |
| Gate | source, destination, requirements |
| Spawn table | per location: packs, weights, density, boss |
| Loot table | per caste / per location: ingredient weights |
| Quest | see [06-guild](06-guild.md) |
| Skill | see [03-adventurer](03-adventurer.md) |
| Caste | see [05-bestiary](05-bestiary.md) |

Rules:

1. Core systems read registries; they never hardcode a content id.
2. Registries are append-only for ids. Balance changes update values, never reuse ids.
3. Who may write registries (admin key, multisig, governance) is decided in Q-08.
4. A region is shippable when its registry entries pass the content validation suite
   (reachability of all gates, non-empty spawn tables, level ranges consistent with gates).

## Region 1 (MVP) — shape only

Names and detailed content are produced in the `LORE` and `CONTENT` tracks.

```
[Town A] ──zone 1── [Outpost B] ──zone 2── (elite zone E, Silver+)
    │                    │
  zone 0 (tutorial)   dungeon D1 (first nest)
```

- **Zone 0**: tutorial meadow at the town gate, level 1–3, runts only.
- **Zone 1**: road to the outpost, level 3–8, first shamans.
- **Dungeon D1**: 3 floors, hobgoblin boss.
- **Zone 2**: level 8–14.
- **Elite zone E**: level 20, post-MVP.
