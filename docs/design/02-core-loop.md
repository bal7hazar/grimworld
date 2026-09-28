# 02 — Core loop: tick, instances, expeditions

> Status: **Draft v0.5** — v0.5: planned queues and played batches told apart; the rule of batches (D-133, DES-21); v0.4: the window follows the adventurer, 15 × 16, not stored (D-120); v0.3: reconciled with ADR-0006 (chunks, window, sight).

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
| Stop playing, come back later, on any device | Same instance, same tick: its state is on-chain and the world waited. On another device, the last seconds played and not yet sent are lost ([batches](#actions-played-and-not-yet-sent)) |
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
| **Window** | The board on which a tick is computed. It follows the adventurer and is assembled from the chunks at each tick, never stored | 15 columns × 16 rows |
| **Sight** | Where goblins are shown | Hexagon of radius 6 around the adventurer, always inside the window |

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
| Depth of the flood | **15 layers** (D-127). A goblin the flood did not reach **holds its position** this tick; it still acts if it can (a ranged attack with line of sight, a skill). Initial value, tuned by SPK-7 and playtest |
| The window | Follows the adventurer at every move; assembled at each tick from the 2 to 4 chunks it overlaps, two layers each; no write |
| Chunks revealed by one action | ≤ 3 |
| Actions per transaction | A batch of weight 10 at most, bounded at 40M L2 gas ([below](#size-10-bounded-by-gas)) |

Goblins **follow** the adventurer from chunk to chunk for as long as they are in the
window, which moves with the adventurer. Outrunning them is putting them out of it; they then walk back to where they stood, regenerate
and return to their first state.

## Planned queues and played batches (D-133)

Two things travel as several actions, and they are not the same:

| | A **planned queue** | A **played batch** |
|---|---|---|
| What it is | Actions chosen **in advance**, without seeing what happens in between: the steps of a path to a far tile | Actions the player chose **one by one**, each on the result of the previous one, which the client computed |
| Who decides each action | The player, once, for all of them | The player, for each of them, after seeing the one before |
| Stop conditions | **Yes** (below): the queue stops when something happens that the player would want to react to | **None but validity**: the contract executes the whole batch; an invalid action drops the rest |
| Where it lives | On the client only: it turns into played actions, step by step | On the chain: one transaction |
| Can be cancelled | Yes: the steps not yet walked | No: a played action is never taken back (I-5) |

In one sentence: **a queue is a plan the client walks; a batch is what was walked, sent.**

### The planned queue and its stop conditions

As in Grimscape's `multiperform`, the player can give several actions at once: tap a far
tile and the adventurer walks the path. The client **walks the queue itself, one step at a
time**, and stops it when something happens that the player would want to react to:

- the adventurer takes damage or gains a condition,
- a goblin enters sight, becomes alerted, or starts activating a skill,
- a chunk is revealed,
- the next step would be a Fate action (remains, a chest, a vein),
- the next step is invalid.

Each step walked is a **played** action and joins the current batch like a tap. The steps
not walked are dropped; nothing of them reaches the chain.

**Why the client and not the contract evaluates the stop conditions** (a change from
v0.4, where the contract stopped the queue): every condition is a function of the state the
client computes exactly (D-40; reveals are computed from the entry draw and the
adventurer's irreversible actions, D-111). The client stops at the same step the chain
would, so the player sees the same walk; the contract needs no second entrypoint and no
per-step checks; and the conditions protect the player, not the game, so a modified client
that ignores them gains nothing (see *Security* below). A planned queue therefore **sits
inside a batch**, as the played steps it produced, and may straddle two batches.

### What a batch holds, and what ends one

| Action ([04-combat](04-combat.md#actions)) | In a batch |
|---|---|
| Move, turn, wait, weapon attack, skill, use item | Yes |
| Interact with a lever or another object that draws nothing | Yes |
| A move that reveals chunks | Yes: the reveal is computed, not drawn (D-111) |
| Loot remains, open a chest, mine a vein, enter a location (entry draw) | **No**: a Fate action is sent **alone**, after the batch before it (ADR-0002, rule 3) |
| Leave through a gate, travel back to a hub | **No**: sent alone, after the batch before it |

| A batch ends when | Why |
|---|---|
| Its weight reaches 10 (below) | Bounded by gas |
| The next action is a Fate action, a gate or travelling back | Those are sent alone, on a state the chain has confirmed |
| The adventurer is defeated | The instance closes; nothing can follow |
| It leaves for one of the reasons of *When a batch leaves* | — |

### Size: 10, bounded by gas

A contract cannot measure its own gas, so the bound is stated in things it counts. Every
action has a **weight**:

```
weight(action) = max(1, world ticks it runs) + 2 × chunks it reveals
weight(batch)  = Σ weight(action)  ≤ 10
```

| Figure | L2 gas | Source |
|---|---:|---|
| Worst world tick under D-127, the game's call | 3,564,913 | SPK-1 §4 (Sepolia); 3,303,993 natively on devnet, SPK-2 §9.2 |
| Largest non-game remainder of a queue | 1,617,995 | SPK-1 §4, queue of 10 moves |
| A batch of weight 10, every tick the worst | 10 × 3.57M + 1.62M = **37.3M** | — |
| **Bound of a batch** | **40,000,000** | The client signs no more; 2.7M of margin for decoding the actions and the sequence check, unmeasured |

- **Why weight and not actions.** A maul blow, a bow shot or a 3-tick skill runs 2 or 3
  world ticks, and each tick can be the worst one. Ten actions of 3 ticks would be 30 ticks,
  about 108M. Counting ticks keeps every valid batch under the bound whatever happens in it.
- A zero-tick action (turn, instant skill) weighs 1: it still costs its own execution, and
  it keeps a batch at 10 actions at most.
- **A revealed chunk weighs 2**, a provisional figure: generating a chunk and writing its new
  storage has not been measured (`enter`'s new storage cost 1.9M, SPK-1 §4). ENG-01 measures
  it and the figure is replaced.
- **When the next action would pass 10**, the current batch leaves first and the action opens
  the next one. The player sees nothing. If the contract counts a weight above 10 anyway (a
  modified client), the action that passes is invalid and the batch stops there.
- **Why 10**: D-133's first answer, kept. A move in a queue of 10 costs 1.77M against 4.82M
  alone (SPK-1 §5): at 10 the fixed part of a transaction, about 1.09M, is 0.11M per action;
  at 20 it would save another 0.05M per action and double what a rewind can undo. SPK-1b and
  ENG-01's figures may move it; the rule does not change, only the number.

### When a batch leaves

| Trigger | Why |
|---|---|
| **Full**: the next action would pass weight 10 | The bound |
| **Before a Fate action, a gate, travelling back** | Those are sent alone, and only after the batch before them is confirmed: a draw must be made on the state the player saw |
| **5 seconds without a new action** | Long enough that a player thinking between two blows in a fight does not split a batch (each split pays the fixed part again); short enough that another device, the indexer and a lost phone lose little. Initial value, tuned by playtest from the mean batch size |
| **The app goes to the background** | A closed app may never come back; the batch is also kept on the device (below) |
| **The end of a fight**: no goblin is awake any more | The next action is usually looting (Fate, sent alone): sending now hides the wait for the confirmation behind the moment the player walks to the remains |
| **Defeat** | The instance closes; the hub needs the confirmed result |
| **Leaving the instance** | Covered by the second line: the batch leaves, then the gate or the travel alone |

**One batch in flight.** A batch is sent when the previous one is confirmed; meanwhile the
next one fills. If it is full and the one in flight is still not confirmed, play waits
(design/11: "saving…"). So at most **two batches, 20 actions**, are ahead of the chain. One in
flight keeps the account's nonce simple and means the client knows the result of a batch
before it sends the next one.

### Actions played and not yet sent

| | |
|---|---|
| Kept | On the device, **written before the action is drawn**: instance id, adventurer id, expected sequence, the actions |
| The app closes or crashes | Sent at the next launch, before any new action, if the chain's instance is still at the expected sequence |
| The chain moved meanwhile (another device played this adventurer, a reorg) | The kept actions are dropped; the chain's state is shown (design/11) |
| The device is lost | Lost with it, as the burner is (ADR-0005): a few seconds of play at most |
| Taken back | Never, in our client (I-5). A modified client can already compute any sequence before sending it: nothing is given away (*Security*) |

This amends D-05: an instance resumed **on another device** resumes at the last action the
chain has; the last seconds played on the first device, not sent, are lost.

### The chain's answer

The contract executes the batch in order. Before the first action it checks the **sequence**:
`Instance.sequence` counts the actions the instance has executed, and the batch carries the
sequence it was played from. A mismatch drops the whole batch. Then each action is checked
against the state it meets; the first invalid one stops the batch, and the rest is dropped.
**The transaction does not revert**: the account's nonce moves, and an event says what ran.

| Invalid when | |
|---|---|
| The sequence differs | Another device, a reorg, a retry of a batch that already landed, another adventurer (co-op) |
| The action is illegal in the state it meets | Tile blocked, out of range or of sight, not enough energy, recharging, a second turn or a second instant skill between two ticks, acting while knocked down, an item not in the belt |
| The weight passes 10 | Above |
| The adventurer is defeated, the instance closed | By an earlier action of the batch |

The client reads the event from the **receipt** (pre-confirmed, ADR-0001), not from the
indexer, then compares its own state after those actions with the chain's.

| The chain's answer | The client |
|---|---|
| Every action ran, same state | Nothing to do: the usual case |
| Fewer ran, or the state differs | **Rewinds**: takes the chain's state, drops every action played after the difference, including the batch being filled |
| The transaction never landed (network, fee, rejected before execution) | Sends the same batch again. The sequence makes it safe: if the first one landed after all, the retry runs nothing |
| A reorg removes a confirmed batch (the indexer says so, D-130) | Rewinds to the chain's state |

**How far and how often.** A rewind drops at most the actions ahead of the chain: **20** (one
batch in flight, one being filled). D-133's first answer was "up to a batch"; it becomes two,
because the batch being filled is played on top of the one in flight. The alternative, waiting
for each batch before playing on, would stop play at every batch. In solo, on a deterministic
action, **a difference is a bug** (S-3 asks for 0); the other causes are a reorg (two in 13
months), the same adventurer on two devices, and co-op. Every rewind is reported by the
client with both states. Rewinds seen by players in a playtest are D-133's reversal
condition.

### Two adventurers in one instance (design/08, not in the MVP)

Under D-80 every action of any member ticks the world. Batches of two members interleave in
the order of their transactions.

| | |
|---|---|
| Validity | The sequence is **the instance's**: a member's batch runs only on the state its player saw. When the other member acted in between, the batch runs nothing |
| The rewind | The other member's actions appear, the dropped ones fade out, and the player decides again on the new state |
| Its cost | Frequent when both act at once. The co-op design chooses between this strict check and a lenient one (the sequence of the member's own actions, each action still checked against the state it meets, as design/08 says), and sizes batches for parties (smaller, and sent when another member's action arrives) |
| What the MVP does to keep it open | The entrypoint takes the adventurer's entity id, the sequence is a field of the instance (M-1, M-2), targets are entity ids (M-5), the permission check is "the caller controls this adventurer, and it is in this instance", never "the caller created the instance" (M-6) |

### Security and fairness

The rules and the state of an instance are public, and tactics are deterministic (D-40). A
batch is executed **exactly as its actions would be, one per transaction, in the same order**
(ENG-01 tests it). So a batch can reach no state that single actions could not.

| A player tries to | Gains | Why |
|---|---|---|
| Play ahead, look, then not send (take back) | Nothing | A modified client can already simulate any sequence before sending it, batch or not. Our client never takes an action back (I-5) |
| Compute a batch off-chain, reorder or optimise it | Nothing | It is the same as playing those actions one by one with a solver at hand, which single transactions already allow. The world waits (D-01): there is no time to save |
| Hold actions back and send them later | Nothing | No rule inside an instance reads the block, the time or the transaction hash; an instance is private in the MVP. A late batch meets the same state |
| Replay a batch, or send it twice | Nothing | The sequence has moved: it runs nothing |
| Ignore the stop conditions of a planned queue | Nothing | They protect the player from a walk they did not watch; the contract never needed them |
| Steer the next chunk by the order of actions (D-111) | Nothing more | The player entropy is a set, not a sequence; trying irreversible options off-chain is possible without batches (ADR-0006) |
| Put a Fate action in a batch | Impossible | `play` cannot encode one; Fate actions have their own entrypoints and go alone |
| Burn gas with heavy batches | Less than today | Weight 10 bounds a transaction; a batch of invalid actions stops at the first. Limits on abuse stay silent rate limits per account (ADR-0001) |

**Fate and the transaction-hash provider (ADR-0002, MVP).** Batching changes nothing. Every
Fate draw of the MVP can already be steered by varying the transaction (the tip, the resource
bounds); a Fate action alone gives no more and no fewer ways to do so. If a Fate action could
ride in a batch, the actions before it would be one more thing to vary, still no worse than
today, but the result could not be computed, so nothing could be played after it anyway, and
version 1's `request_random` must be first in its multicall (rule 3). So Fate stays alone. A
Fate action is sent only after the batch before it is confirmed, with the expected sequence:
the draw is made on the state the player saw.

### Entrypoints (for ENG-01 to freeze)

In words; types and packing are ENG-01's.

```
play(instance_id, adventurer_id, sequence, actions)
    actions: 1 to 10 of
        Move(direction) | Turn(direction) | Wait
        | Attack(target entity id)
        | Skill(slot 0–7, target entity id or tile index)
        | Item(belt slot 0–3, target entity id)
        | Interact(tile index)            objects that draw nothing
    emits BatchPlayed {
        instance_id, adventurer_id,
        from,          the sequence the batch was played from
        played,        0–10, actions that ran
        stop,          None | Sequence | Invalid | Weight | Defeated | Closed
        sequence,      after the batch
        clock,         after the batch
    }
```

| | |
|---|---|
| Bounds | 1 to 10 actions; weight ≤ 10; each action's ticks are bounded by its tick cost ([04](04-combat.md#actions)); each tick by the simulation budget above |
| Fate actions and gates | Keep their own entrypoints (loot, open a chest, mine, enter, leave, travel back), one action each, and **gain the `sequence` argument**, with the same rule: a mismatch runs nothing, and says so |
| Other events | Each action emits what it emits alone (a goblin killed, a chunk revealed, defeat); `BatchPlayed` is the batch's summary |
| Never read | Block number, timestamp, transaction hash (ADR-0001) |

### What ENG-01 must do

1. `Instance.sequence`, incremented by every executed action, in `play` and in every Fate or
   gate entrypoint of the instance.
2. `play` as above: sequence check, weight counted as the actions run, stop at the first
   invalid action, no revert, `BatchPlayed`.
3. The `sequence` argument on loot, open, mine, leave, travel back.
4. No stop conditions in the contract: the planned queue is the client's.
5. A test that a batch and the same actions one per transaction give the same state and
   events, over the shared vectors (SPK-4).
6. Measure: `play` with 1, 5 and 10 actions; the worst batch of weight 10, to confirm it is
   under 40M; a revealed chunk, to replace its weight of 2.
7. Permission: the caller controls `adventurer_id`, and that adventurer is in `instance_id` (M-6).

### What CLI-03 must do

1. Draw each action at once from the shared rules; write it to the device before drawing it.
2. Fill batches by weight; send on the triggers above (5 s idle, background, fight end,
   defeat, before a Fate action or a gate); one batch in flight; wait at 20 actions ahead.
3. Walk planned queues step by step, evaluating the stop conditions; each step is a played
   action.
4. Read `BatchPlayed` from the receipt; compare states; rewind on any difference; retry a
   batch that never landed as it was.
5. At launch, send the kept batch if the sequence matches, else drop it and show the chain's
   state.
6. Send a Fate action or a gate alone, after the batch before it is confirmed.
7. Report every rewind with both states.
8. Never take a played action back.
