# 18 — Terrain, features and perception

> Status: **Draft v0.3** — v0.3: the window follows the adventurer (D-120); v0.2: rewritten for [ADR-0006](../architecture/ADR-0006-chunked-maps.md).
> Numbers are initial values; costs are measured in spike SPK-7. The file keeps its name
> so that links hold.

Completes [02-core-loop](02-core-loop.md#map) and [04-combat](04-combat.md).

## Locations

| Location | Outline | Size |
|---|---|---|
| Zone | **Drawn in advance** in the registry: any shape, any size | Free |
| Nest floor, Rift floor | **Emerges** during exploration | A target of 6 to 12 chunks, by grade |
| Boss arena | An authored chunk, placed by quota | 1 chunk |

## Biomes

A location has one biome, which sets how a chunk is generated.

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
| **Pack** | 0 to 2 per chunk, from the location's spawn table, within its level band | Members within 2 tiles of the pack's tile; asleep or on watch |
| **Remains** | Left by a dead goblin | Looting is a Fate draw and ends the queue |
| **Chest** | 1 chunk in 6 | Opened once; content is a Fate draw |
| **Vein** (Rifts only) | Quota: 1 per floor | 3 ticks to mine, interrupted by a hit; 1 stillstone |
| **Gathering node** | 1 chunk in 4, zones only | 1 tick; 1–2 common ingredients of the region, no draw |
| **Trap** | Ruins and caves, 1 chunk in 3; also set by trapper goblins | Hidden until an adventurer is adjacent; triggers on entering the tile |
| **Collector** | Quota: per zone, in an authored chunk (a camp) | Barter. **Its place changes with each instance** |
| **Landmark** | Quota or anchor, from quests | Objectives (reach, activate) |
| **Gate** | Anchor on the outline (zones); entrance, and exit by quota (dungeons) | — |

## What the adventurer sees

| | |
|---|---|
| Terrain | Of every chunk revealed in this instance |
| Goblins, remains, features that can change | Within **sight**: hexagon of radius 6, line of sight **not** required. Sight depends on the adventurer's position only: everything in sight is inside the simulation window, which follows the adventurer |
| Beyond sight | Terrain, dimmed, as it was last seen; no goblins |
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
| TP-1 | Walkable shares and pack frequencies per biome, after the first playable |
| TP-2 | Does a zone show its outline on the map before being explored? Recommendation: yes, it is public and drawn in advance |
