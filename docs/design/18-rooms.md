# 18 — Rooms: size, generation, features, perception

> **Superseded in part by [ADR-0006](../architecture/ADR-0006-chunked-maps.md)** (2026-09-28): maps are large and cut in chunks; the unit of simulation is a window centred on the adventurer, not a room. What this document says of rooms is kept for the record until it is rewritten after spike SPK-7.
>
> Status: **Draft v0.1** — numbers are initial values; costs are the map library's own
> benchmarks and are re-measured in spike SPK-7.

Completes [02-core-loop](02-core-loop.md#map) and [04-combat](04-combat.md).

## Size

| | |
|---|---|
| Room | **9 columns × 17 rows**, pointy-top hexes: 153 tiles |
| Walkable at most | 7 × 15 = 105 (the outer ring is wall) |
| Why | It fills a phone in portrait with tiles about 40 points wide, without scrolling |
| Storage | 153 bits: one felt. At or under 128 tiles the library is about a third cheaper per step: **9 × 14 = 126** is the fallback if cost demands it |
| Set by | The location's registry entry; every room of a location has the same size |

## Locations

| Location | Rooms | Shape |
|---|---|---|
| Tutorial zone | 2 × 2 | Open |
| Zone | 3 × 3 to 4 × 4 | Open, entrances on all sides that have a neighbour |
| Nest floor, Rift floor | 3 to 6 rooms | A chain with one or two branches |
| Boss room | 1 | Single entrance; larger open space |

## Generation

| Biome | Generator | Feel |
|---|---|---|
| Meadow, road | Empty room, then obstacles by distribution (10–20% of tiles) | Open ground, scattered cover |
| Forest | Random walk, 120 steps | Clearings joined by paths |
| Cave (nests, Rifts) | Cellular cave, 3 generations | Pockets and chokepoints |
| Ruin | Maze of order 1 | Corridors, corners |
| Boss room | Hexagon of radius 4 inside the room | An arena |

Chain for every room, in this order:

1. Generator of the biome, with the room's seed.
2. `open_with_corridor` for each entrance.
3. `keep_component` from the first entrance: what cannot be reached becomes wall.
4. Reject and regenerate with the next seed if fewer than 40 walkable tiles remain
   (at most 3 attempts, then an empty room).
5. Placement of features, then of packs.

## Features

Placed by `compute_distribution` on walkable tiles, at least 2 tiles away from any
entrance.

| Feature | Frequency | Rule |
|---|---|---|
| **Pack** | 0 to 2 per room, from the location's spawn table | Members placed within 2 tiles of the pack's tile; asleep or on watch |
| **Remains** | Left by a dead goblin | Looting is a Fate draw and ends the queue |
| **Chest** | 1 room in 6 | Opened once; content is a Fate draw from the location's table |
| **Vein** (Rifts only) | About 1 per floor | 3 ticks to mine, interrupted by a hit; 1 stillstone |
| **Gathering node** | 1 room in 4, zones only | 1 tick; gives 1–2 common ingredients of the region, no draw |
| **Trap** | Ruins and caves, 1 room in 3; also set by trapper goblins | Hidden until an adventurer is adjacent; triggers on entering the tile |
| **Collector** | Fixed rooms of fixed zones, from the registry | Barter |
| **Landmark** | From the registry | Quest objectives (reach, activate) |
| **Gate** | From the registry | On an entrance of a border room |

## What the adventurer sees

| | |
|---|---|
| The current room | **Entirely**, from the moment it is entered: layout, goblins, features |
| Other rooms | Visited rooms are remembered on the map as they were left. Unvisited rooms are unknown |
| Hidden in the room | Traps, until adjacent |
| Why no field of view | The room is the screen. A fog inside it would hide what the player needs to plan, and would be presentation only, since the chain is public |

Line of sight matters for **acting**, not for seeing: ranged attacks and spells need it.

## What goblins perceive

| State | Notices an adventurer when |
|---|---|
| Asleep | Within 2 tiles, or hit, or its pack is alerted |
| On watch | Within 5 tiles **and** in line of sight **and** in its front or front-side arcs; or within 2 tiles in any arc |
| Alerted | Knows the last tile where the adventurer was seen; walks there |
| Engaged | Always knows where the adventurer is, while in the room |

| Event | Effect |
|---|---|
| A goblin notices | Its whole pack becomes engaged |
| A shout, or a fight, within 8 tiles | Other packs of the room become alerted |
| The adventurer leaves the room | Goblins return to their place, regenerate, and go back to their first state |

This is what makes **approach** a part of the game: a pack on watch has a back, an asleep
pack can be struck first, and the entrance you come in by decides both.

## Entering a room

| | |
|---|---|
| Position | The entrance tile |
| Facing | Into the room |
| Cost | 1 tick, as any move |
| The queue | Always stops |
| Goblins | Are in their first state; none acts before the adventurer's next action |

## Cost

From the library's benchmarks on a 17 × 14 room, which is larger than ours:

| Operation | When | Order of cost |
|---|---|---|
| Generate a cave room, with placement | First entry into a room | ~1.1M gas |
| Generate a maze room | Same | ~3M gas |
| One flood from the adventurer | Each tick with engaged goblins | ~0.5–0.7M gas |
| Line of sight | Per ranged action | To write and measure |

Ruins are the most expensive rooms to generate; they are used sparingly until measured.

## Open

| # | Question |
|---|---|
| RM-1 | 9 × 17, or 9 × 14 for cost: decided by SPK-6 and SPK-7 together |
| RM-2 | Should goblins be able to follow through an entrance (one room of pursuit)? Not in the MVP |
