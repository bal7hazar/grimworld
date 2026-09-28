# 02 — Core loop: tick, instances, expeditions

> Status: **Draft v0.2** — v0.2: hex maps, instances not saved, defeat keeps loot, single clock.

## The tick (D-01)

In a dedicated instance, **time is discrete and owned by the adventurer**.

- The unit of time is the **tick**. There is no sub-tick.
- The world advances **only** as a consequence of an adventurer action. Block time and
  wall-clock time have no effect inside an instance.
- An action has a tick cost `n ≥ 0` ([04-combat](04-combat.md#actions)). Resolving an
  action means: apply the adventurer's action, then run `n` world ticks.
- One **world tick** runs, in this order:
  1. Activations in progress advance; those that complete resolve.
  2. Awake goblins act, in ascending entity id order.
  3. Conditions, regeneration and degeneration apply.
  4. Durations and recharges decrease.
  5. Defeat / objective checks.

Consequences:

- An instance can be left untouched for a week and resumed exactly where it was, as long
  as the adventurer has not left it.
- There is no time pressure, so difficulty must come from position, resources and
  information, never from reflexes.

### One clock per instance (D-02)

```
Instance.clock      world time, in ticks
```

Durations, recharges and activations are stored as **deadlines on the instance clock**,
not as counters decremented on "the adventurer's turn". The engine never assumes "one
adventurer per instance": instances are keyed by an instance id, and adventurers reference
the instance they are in. This is what keeps co-op possible
([08-multiplayer](08-multiplayer.md)) and deliberately departs from Grimscape, where rooms
and mobs are keyed by adventurer id.

## Instances

| | Shared (town, outpost) | Dedicated (zone, dungeon, elite) |
|---|---|---|
| Time | None on-chain | Tick |
| Who is there | Everyone at that location | One adventurer (a party later) |
| On-chain state | `Adventurer.location = hub id` | Full simulation state |
| Position in space | Off-chain presence, cosmetic (D-03) | On-chain, authoritative |
| Actions | Services: quests, build, craft, trade, travel | Move, fight, loot |

**D-03 — Hubs have no on-chain geometry.** Walking around a town is not game state.
The client renders the hub and other present adventurers from a presence channel; the
chain only knows *who is in which hub*. Every service is a direct contract call. This keeps
hubs free to use and removes the hardest latency problem from the most social place.

## Expedition lifecycle

```
        ┌────────────────────────── hub ──────────────────────────┐
        │ accept quests · set 8 skills · spend attributes · stock │
        └───────────────┬─────────────────────────────────────────┘
                        │ enter gate            (build is locked, instance seed drawn)
                        ▼
                ┌──── instance ────┐
                │ explore · fight  │◀──┐ next location through a gate
                │ loot · objectives│───┘ (each one is a new instance)
                └───┬──────────┬───┘
   reach a hub, or  │          │ health reaches 0
   travel back      ▼          ▼
                 RETURNED   DEFEATED
```

### Entering

- Requires meeting the gate's requirements.
- Draws the **instance seed** from the randomness source
  ([ADR-0002](../architecture/ADR-0002-randomness.md)).
- Locks skill bar and attributes.
- An adventurer is in **at most one instance**.

### Instances are not saved (D-05)

As in GW1, an instance lives only while the adventurer is inside it.

| Situation | Result |
|---|---|
| Stop playing, come back later, on any device | Same instance, same tick: its state is on-chain and the world waited |
| Leave through a gate, or travel back to a hub | The instance is **closed**. Its state can be discarded |
| Enter the same location again | A **new instance** with a new seed: goblins are back |
| Be defeated | The instance is closed |

There are no checkpoints and no camps. Long dungeons are made of floors, and each floor is
its own instance entered from the previous one; leaving the dungeon means starting again
from the first floor.

### Ending an expedition (D-04)

| Outcome | Trigger | XP | Loot | Quest progress | Where next |
|---|---|---|---|---|---|
| **Returned** | Walk into a hub gate, or travel back to an unlocked hub at any time | Kept | Kept | Kept | That hub |
| **Defeated** | Health reaches 0 | Kept | Kept | Kept | Last hub visited |

- Defeat costs the **instance**, nothing else: no loot loss, no experience loss, no
  durability, no permanent death. The goblins are back next time, and so is the player,
  with whatever was earned and a better idea of the fight. *Try, fail, adjust the build,
  retry* is the intended loop (pillar 2).
- Looted items go straight to the inventory.
- What cannot be kept is what was not finished: a boss at half health, an unlooted corpse,
  a gate not reached.
- A **hardcore** ruleset (permanent death or loot loss) may be offered later as an opt-in;
  it is never the default.

## Map

Maps are hexagonal and built on
[`origami_hexmap`](https://github.com/dojoengine/origami/tree/main/crates/hexmap) (D-11).

### Structure

```
Location ─ bounded grid of rooms (registry: columns × rows of rooms)
Room     ─ W × H hex tiles with W × H ≤ 251, stored as one felt bitmap
Tile     ─ index = y × W + x        pointy-top hexes, odd rows shifted (odd-r)
```

| Property | Value |
|---|---|
| Orientation | **Pointy-top**: every tile has an East and a West neighbour |
| Directions | East, North-East, North-West, West, South-West, South-East |
| Room size | Registry parameter per location. Default **15 × 15**; final default set by the client spike for portrait phones (e.g. 13 × 19) |
| Border | The outer ring of a room is wall, except **entrances** |
| Distance | Hex distance (`hex_distance`) for ranges; path distance (`distance_to`) for movement |

| Layer (one bitmap per room) | Meaning |
|---|---|
| `grid` | Walkable tiles |
| `entities` | Tiles occupied by an actor |
| `features` | Tiles holding a feature (remains, trap, chest, gate); details in a keyed model |

- Rooms connect through entrances opened on their edges; a path may start or end on an
  entrance but never crosses one, which makes them natural room transitions.
- A location's registry entry bounds the room grid and places its gates, so that, unlike
  Grimscape, a location is finite and has exits.
- Rooms are **generated lazily** on first entry from
  `hash(layout seed, room x, room y)`, where the layout seed is the location's registry
  seed for fixed locations and the instance seed for shifting ones
  ([01-world](01-world.md#geography-fixed-vs-shifting-d-10)).
- Generation chains library calls: a generator chosen by the location's biome
  (`new_cave` for nests, `new_random_walk` for wilds, `new_maze` for ruins), then
  `open_with_corridor` for each entrance, then `keep_component` so that every walkable
  tile is reachable, then `compute_distribution` to place packs and features.

### What the library gives and what we must build

| Need | Status |
|---|---|
| Generation, entrances, connectivity | Provided |
| Shortest path, distance, range, ring, movement field | Provided, deterministic tie-break (lowest tile index) |
| Moving obstacles (other actors) | Not a parameter; we pass `grid & ~entities` as the grid |
| **Line of sight** | **Not provided.** To be written (hex line between two tiles, blocked by walls) and contributed upstream if accepted |
| Facing and arcs | Ours, see [04-combat](04-combat.md#facing-and-arcs-d-41) |

### Fog

The client hides unexplored rooms. Because generation is deterministic from public seeds,
this fog is a **presentation choice, not a security property**; a modified client can
reveal layouts. We accept this (see non-goals). Rewards do not depend on it.

## Simulation budget

On-chain execution is bounded per transaction, so the design enforces:

| Rule | Value |
|---|---|
| Only the **current room** is simulated | Goblins in other rooms are frozen |
| Awake goblins per room | ≤ 8 |
| Goblins per room | ≤ 8 |
| Pathfinding | **One search per tick, not one per goblin**: a single breadth-first flood from the adventurer gives every goblin its next step |
| Actions per transaction | Batched up to a cap set by measurement (Phase 0) |

Library figures for a 17 × 14 room (its own benchmarks, to be re-measured in SPK-2): one
path search costs about 0.7M gas, a room generation with placement about 1.1M. Eight
independent searches per tick would not fit the budget, hence the shared flood.

Goblins do not follow across rooms in the MVP: leaving a room breaks the fight, and the
room keeps its state for as long as the instance lives (wounded goblins regenerate
according to elapsed world time when the room is re-entered). Entrance-camping is
countered by design: goblins adjacent to an entrance get a free attack on an adventurer
who leaves through it while Engaged.

## Action batching and interruption

As in Grimscape's `multiperform`, the client may submit a **queue of actions** in one
transaction. The contract executes them in order and **stops the queue** when something
the player would want to react to happens:

- the adventurer takes damage or gains a condition,
- a goblin becomes Alerted or starts activating a skill,
- a new room is entered,
- an action in the queue is invalid (the remainder is dropped; the transaction does not
  revert).

This gives auto-walk across explored rooms in a single transaction and keeps decisions in
the player's hands when they matter.
