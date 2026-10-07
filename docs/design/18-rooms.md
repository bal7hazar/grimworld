# 18 — Terrain, features and perception

> Status: **Draft v0.5** — v0.5: zones authored (D-214), their packs, collector and gates (D-215), TP-2 answered; v0.4: goblins away from their chunk, the full roster (D-141); v0.3: the window follows the adventurer (D-120); v0.2: rewritten for [ADR-0006](../architecture/ADR-0006-chunked-maps.md).
> Numbers are initial values; costs are measured in spike SPK-7. The file keeps its name
> so that links hold.

Completes [02-core-loop](02-core-loop.md#map) and [04-combat](04-combat.md).

## Locations

| Location | Outline | Size |
|---|---|---|
| Zone | **Authored** (D-214): drawn with the map editor, terrain and outline, held in the registry (ENG-08's format, D-215); any shape, up to 15 × 15 chunks | Free |
| Nest floor, Rift floor | **Emerges** during exploration | A target of 6 to 12 chunks, by grade |
| Boss arena | An authored chunk, placed by quota | 1 chunk |

## Biomes

A location has one biome, which sets how a chunk is generated. **An authored zone (D-214) is not
generated**: its biome keeps its art and its gathering's region; its terrain is the author's. The
order below is a generated location's (dungeons, and a zone not yet authored, D-215 ruling 7).

| Biome | Walkable share | Feel |
|---|---|---|
| Meadow, road | 80–90% | Open ground, scattered cover |
| Forest | 60–70% | Clearings joined by paths |
| Cave (nests, Rifts) | 45–55% | Pockets and chokepoints |
| Ruin | 40–50% | Corridors, corners |

Generation of a chunk, in this order: base from the chunk's random word; smoothing with
the margins of neighbours already revealed; edges and openings; cut by the outline mask
(zones); quotas; placement of packs and features.

## Features

Placed at generation, at least 2 tiles away from an opening to a neighbouring chunk.

| Feature | Frequency | Rule |
|---|---|---|
| **Pack** | 0 to 2 per chunk, from the location's spawn table, within its level band. **Authored zone (D-215 ruling 4)**: on the author's spawn points (a tile and a template); each chunk's level (within the band, the same for every spawn point of the chunk) and each point's count (within the template, at least 1) are drawn at entry | Members within 2 tiles of the pack's tile; asleep or on watch |
| **Remains** | Left by a dead goblin | Looting is a Fate draw and ends the queue and the batch |
| **Chest** | 1 chunk in 6 | Opened once; content is a Fate draw |
| **Vein** (Rifts only) | Quota: 1 per floor | 3 ticks to mine, interrupted by a hit; 1 stillstone |
| **Gathering node** | 1 chunk in 4, zones only | 1 tick; 1–2 common ingredients of the region, no draw |
| **Trap** | Ruins and caves, 1 chunk in 3; also set by trapper goblins | Hidden until an adventurer is adjacent; triggers on entering the tile |
| **Collector** | Quota: per zone. **Authored zone (D-215 ruling 3)**: drawn at entry among the places the author marks for it (at least its count of them) | Barter. **Its place changes with each instance**, among the author's candidates |
| **Landmark** | Quota or anchor, from quests | Objectives (reach, activate) |
| **Gate** | Anchor on the outline (zones; **authored**: a walkable tile the chunk's record names, at most 2 a chunk); entrance, and exit by quota (dungeons) | — |

## What the adventurer sees

| | |
|---|---|
| Terrain | Drawn only once seen within sight; the chain still reveals whole chunks (owner's request, 2026-10-05; D-213) |
| Goblins, remains, features that can change | Within **sight**: hexagon of radius 6, line of sight **not** required. Sight depends on the adventurer's position only: everything in sight is inside the simulation window, which follows the adventurer |
| Beyond sight | The terrain as last seen, in grayscale, with goblins shown: live in the simulation window, in their last-held state outside it (owner's request, 2026-10-05; D-213) |
| Hidden | Traps, until adjacent |
| A chunk is revealed | When sight touches one of its tiles |

The same rule applies to every screen. It is provisional until the owner has tested it on
a phone and a desktop.

Line of sight matters for **acting**, not for seeing: ranged attacks and spells need it.

## What goblins perceive

| State | Notices an adventurer when |
|---|---|
| Asleep | Within 2 tiles, or hit, or its pack is alerted |
| On watch | Within 5 tiles **and** in line of sight **and** in its front or front-side arcs; or within 2 tiles in any arc |
| Alerted | Knows the last tile where the adventurer was seen; walks there |
| Engaged | Always knows where the adventurer is, while it is in the window (15 × 16 around the adventurer) |

| Event | Effect |
|---|---|
| A goblin notices | Its whole pack becomes engaged |
| A shout, or a fight, within 8 tiles | Other packs within that distance become alerted |
| The goblin falls out of the window (the adventurer got more than 7 tiles away) | It returns to its place, regenerates, and goes back to its first state |

**Goblins away from their chunk (D-141, E-2).** A goblin that follows the adventurer out of the
chunk it was placed in, or dies away from it and is not yet looted, is kept in the instance's
roster of displaced goblins, which holds 60. **While the roster is full, a goblin does not leave
its spawn chunk**: it holds at the chunk's edge. No remains are ever dropped, and no loot lost.

Approach is part of the game: a pack on watch has a back, an asleep pack can be struck
first, and the side one arrives from decides both.

## Entering an instance

| | |
|---|---|
| Position | The entrance tile, in the first chunk, revealed by the entry draw |
| Facing | Away from the entrance |
| Goblins | In their first state; none acts before the adventurer's first action |

## Open

| # | Question |
|---|---|
| — | **Known design limit of version 1 (D-221, the project manager, 2026-10-07)**: sight reads the walkable plane, so water, like any wall, blocks sight on chain: **in v1 a lake hides what lies beyond it**. A sight plane (a third part of an authored chunk's record, ENG-01 §3.5) comes only if a playtest asks |
| TP-1 | Walkable shares and pack frequencies per biome, after the first playable |
| TP-2 | ~~Does a zone show its outline on the map before being explored?~~ **Answered (D-214)**: yes. An authored zone's outline and terrain are public records before any instance; the world map draws them. What the client shows inside an instance still follows D-213 (a tile drawn once it has entered sight) |
