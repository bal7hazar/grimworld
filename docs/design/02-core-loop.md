# 02 — Core loop: tick, instances, expeditions

> Status: **Draft v0.3** — v0.3: reconciled with ADR-0006 (chunks, window, sight).

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
                        │ enter gate            (build is locked, entry draw made)
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
- Makes the **entry draw** ([ADR-0002](../architecture/ADR-0002-randomness.md)). It is
  not a seed from which the location could be computed: each chunk also depends on what
  the adventurer will have done by the time it is revealed.
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

Maps are hexagonal, large, cut in chunks and generated as they are revealed. The
mechanism and its reasons are in
[ADR-0006](../architecture/ADR-0006-chunked-maps.md); the rules a player meets are in
[18-terrain-and-perception](18-rooms.md). Summary:

| Notion | What | Size |
|---|---|---|
| **Tile** | A pointy-top hex, with global coordinates `(x, y)` in its location | — |
| **Chunk** | Unit of storage and generation | 15 × 15 tiles, one felt per layer |
| **Window** | The board on which a tick is computed, centred on the adventurer | 15 × 15 tiles |
| **Sight** | Where goblins are shown | Hexagon of radius 6 around the adventurer |

| | |
|---|---|
| Directions | East, North-East, North-West, West, South-West, South-East |
| Distance | Hex distance for ranges; path distance for movement |
| Generation | A chunk is generated when sight touches it, from the instance's entry draw and the adventurer's irreversible actions since (D-111) |
| Revealed | For the whole instance, and forgotten with it (D-105) |
| Library | [`origami_hexmap`](https://github.com/dojoengine/origami/tree/main/crates/hexmap) and its successor (PLAN, track LIB) |

## Simulation budget

On-chain execution is bounded per transaction, so the design enforces:

| Rule | Value |
|---|---|
| Only the **window** is simulated | Goblins outside it are frozen |
| Awake goblins | ≤ 8: the nearest to the adventurer, ties by lowest id |
| Pathfinding | **One flood per tick, not one per goblin**: a single breadth-first flood from the adventurer on the window gives every goblin its next step |
| Re-centring | The window moves only when the adventurer comes within 3 tiles of its edge |
| Chunks revealed by one action | ≤ 3 |
| Actions per transaction | Batched up to a cap set by measurement (Phase 0) |

Goblins **follow** the adventurer from chunk to chunk for as long as they are in the
window. Outrunning them is leaving it; they then walk back to where they stood, regenerate
and return to their first state.

## Action batching and interruption

As in Grimscape's `multiperform`, the client may submit a **queue of actions** in one
transaction. The contract executes them in order and **stops the queue** when something
the player would want to react to happens:

- the adventurer takes damage or gains a condition,
- a goblin enters sight, becomes alerted, or starts activating a skill,
- a chunk is revealed,
- remains are looted, a chest is opened (Fate draws),
- an action in the queue is invalid (the remainder is dropped; the transaction does not
  revert).

This gives auto-walk across revealed terrain in a single transaction and keeps decisions
in the player's hands when they matter.
