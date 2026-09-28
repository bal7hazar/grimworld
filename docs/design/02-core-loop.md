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
| Stop playing, come back later, on any device | Same instance, same tick: its state is on-chain and the world waited. On another device, the actions played and not yet sent, at most two batches, are lost ([batches](#actions-played-and-not-yet-sent)) |
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
| Actions per transaction | A batch of weight 10 at most per invocation, targeting 40M L2 gas, to be proven by ENG-01 ([below](#size-10-bounded-by-gas)) |

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
| The next action is a Fate action, a gate or travelling back | Our client sends those alone, on a state the chain has confirmed (a multicall can compose them: *Security*) |
| The adventurer is defeated | The instance closes; nothing can follow |
| It leaves for one of the reasons of *When a batch leaves* | — |

### Size: 10, bounded by gas

A contract cannot measure its own gas, so the bound is stated in things it counts. Every
action has a **weight**:

```
weight(action) = max(1, world ticks it runs) + 2 × chunks it reveals
weight(batch)  = Σ weight(action)  ≤ 10          per invocation of play
```

**The gas bound is a target, not yet a proven bound.** 40M L2 gas per batch is an estimate
from the figures below; ENG-01 proves it, or replaces the figure and the weights, before the
weights are frozen.

| Figure | L2 gas | Source, and what it leaves out |
|---|---:|---|
| Worst world tick under D-127, the game's call | 3,564,913 | SPK-1 §4 (Sepolia); 3,303,993 natively on devnet, SPK-2 §9.2. SPK-2's prototype (§1) leaves out the window's assembly from chunks, more goblins in the window than the 8 awake, chunk writes, the full AI and skills |
| Non-game remainder of a queue of 10 | 1,617,995 | SPK-1 §4. **Observed** for one account class, not a maximum |
| A batch of weight 10, every tick as the worst measured | 10 × 3.57M + 1.62M = 37.3M | — |
| **Target bound of a batch** | **40,000,000** | 2.7M of margin, unproven |
| A revealed chunk | weight 2, **unmeasured** | Generation and new storage (`enter`'s new storage cost 1.9M, SPK-1 §4) |

- **Why weight and not actions.** A maul blow, a bow shot or a 3-tick skill runs 2 or 3
  world ticks, and each tick can be the worst one. Ten actions of 3 ticks would be 30 ticks.
  Counting ticks bounds every valid batch whatever happens in it.
- A zero-tick action (turn, instant skill) weighs 1: it still costs its own execution, and
  it keeps a batch at 10 actions at most.
- **When the next action would pass 10**, the current batch leaves first and the action opens
  the next one. The player sees nothing. If the contract counts a weight above 10 anyway (a
  modified client), the action that passes is invalid and the batch stops there.
- **If a batch runs out of resources anyway** (the bound was wrong), the transaction is
  included and reverted: see *The chain's answer*. The client resubmits the same actions in
  smaller batches; a single action that runs out is a bug, reported, not retried.
- **Why 10**: D-133's first answer, kept. A move in a queue of 10 costs 1.77M against 4.82M
  alone (SPK-1 §5): at 10 the fixed part of a transaction, about 1.09M, is 0.11M per action;
  at 20 it would save another 0.05M per action and double what the client plays ahead of the
  chain. SPK-1b and ENG-01's figures may move it; the rule does not change, only the numbers.

### When a batch leaves

The triggers are **our client's**. A modified client may send what it likes; the contract
only guarantees the rules of *The chain's answer*.

| Trigger | Why |
|---|---|
| **Full**: the next action would pass weight 10 | The bound |
| **Before a Fate action, a gate, travelling back** | Those are sent alone, and only after the batch before them is confirmed: a draw is made on the state the chain has |
| **5 seconds without a new action** | Long enough that a player thinking between two blows in a fight does not split a batch (each split pays the fixed part again); short enough that another device and the indexer see the play soon. Initial value, tuned by playtest from the mean batch size |
| **The app goes to the background** | A closed app may never come back; the batch is also kept on the device (below) |
| **The end of a fight**: no goblin is awake any more | The next action is usually looting (Fate, sent alone): sending now hides the wait for the confirmation behind the moment the player walks to the remains |
| **Defeat** | The instance closes; the hub needs the confirmed result |
| **Leaving the instance** | Covered by the second line: the batch leaves, then the gate or the travel alone |

**One batch in flight, one filling.** A batch is sent when the previous one is confirmed;
meanwhile the next one fills. **When the batch filling is full** (its next action would pass
weight 10) and the one in flight is not confirmed yet, play waits (design/11: "saving…"). So
our client **plays at most two batches, weight 20, ahead of the chain**. That bounds
speculation, not rollback: a reorg can undo any depth (*The chain's answer*). One in flight
keeps the account's nonce simple and means the client knows the result of a batch before it
sends the next one.

### Actions played and not yet sent

| | |
|---|---|
| Kept | On the device, **written before the action is drawn**: instance id, adventurer id, expected sequence, the actions |
| The app closes or crashes | Sent at the next launch, before any new action, if the chain's instance still exists at the expected sequence |
| The chain moved meanwhile (another device played this adventurer, a reorg) | The kept actions are dropped; the chain's state is shown (design/11) |
| The device is lost | Lost with it, as the burner is (ADR-0005) |
| How much can be lost | **At most two batches, weight 20**: the one filling and the one in flight not yet included. The bound is in actions, not seconds |
| Taken back | Never, in our client (I-5). A modified client can already compute any sequence before sending it: nothing is given away (*Security*) |

**No maximum age of a batch.** A batch that is not full leaves after 5 seconds without input;
a batch filled without pause is full within weight 10. A maximum age would only split batches
that are being filled, paying the fixed part again, without lowering the bound in actions,
which is what the player can lose.

This amends D-05: an instance resumed **on another device** resumes at the last action the
chain has; the actions played on the first device and not sent, at most two batches, are lost.

### The chain's answer

**The sequence.** `Instance.sequence` counts the actions the instance has executed.

| | |
|---|---|
| `enter` | Creates the instance with **sequence 0**. It takes no sequence (there is no instance yet); a second `enter` is refused because the adventurer is already in an instance |
| `play` | Carries the sequence its batch was played from; +1 per action that runs |
| Loot, open a chest, mine | Carry the sequence; +1 when the action runs |
| Leave through a gate, travel back | Carry the sequence of the instance they close. A gate to another location closes this instance and **enters the next one in the same invocation** (its entry draw is Fate): a new instance id, at sequence 0, given by the entry event |

**What a matching sequence proves.** That the **count** of actions matches, not the history:
after a reorg, or with the same adventurer on two devices, the chain can hold the same count
reached by other actions. In the MVP (solo) this is accepted as an optimistic divergence: the
client finds it by reconciling (below) and rewinds. A check bound to the history (a hash chain
of the actions executed: one Poseidon hash per action and one felt written per invocation) or
to the state (a hash of the instance state: far more hashing, on every batch) costs gas on
every batch, unmeasured; it is left to co-op or version 1.

**Executing a batch.** The contract checks the sequence; a mismatch runs nothing. Then each
action is checked against the state it meets; the first invalid one stops the batch, and the
rest is dropped. **For invalidity in the game, with enough resources, the invocation does not
revert**: the account's nonce moves, the fee is paid, and `BatchPlayed` says what ran.

| Invalid when | |
|---|---|
| The sequence differs | Another device, a reorg, a retry of a batch that already landed, another adventurer (co-op) |
| The action is illegal in the state it meets | Tile blocked, out of range or of sight, not enough energy, recharging, a second turn or a second instant skill between two ticks, acting while knocked down, an item not in the belt |
| The weight passes 10 | Above |
| The adventurer is defeated, the instance closed | By an earlier action of the batch |

**Fate and gate actions** check the sequence and **every precondition before drawing**
(the adventurer is in the instance, on or next to the remains, the chest or the vein; the
object is still there; the gate is reachable). A failed check draws nothing, changes nothing
and emits `Refused`. The draw and the consumption of what was drawn from (the remains, the
chest) happen in the same invocation (ADR-0002, rule 5).

**The receipt.** The client reads the status of the transaction that carried the batch.

| Status | What it means | The client |
|---|---|---|
| **Succeeded** | Executed; `BatchPlayed` (or `Refused`) is in the receipt | Reconciles (below) |
| **Reverted** | Included, **nonce consumed, fee charged, no event, no state change**: the batch ran out of resources, or the contract panicked (a bug) | Resubmits the same actions, same sequence, **with a fresh nonce, in batches half the size**. A single action that reverts is not retried: the client rewinds to the chain's state, reports it, and the player is told their last steps were lost |
| **Not found** (not received, rejected before execution, dropped) | Nothing ran; the nonce did not move | Sends the same transaction again, **same nonce**, so that at most one of the two can run: up to 5 times over about 60 seconds. Then play is suspended ("connection lost"), the actions stay on the device, and sending resumes when the network does |

**Reconciling.** The chain's state is the truth; the client checks its prediction against it
after every succeeded batch.

1. Read `BatchPlayed` from the receipt: `from`, `played`, `stop`, `sequence` after.
2. Take its own state after the first `played` actions of the batch.
3. Read the instance through the **views** at the receipt's block (the RPC reads state at a
   block id; a pre-confirmed receipt without a block yet is read at the pre-confirmed block):
   the instance, the adventurer in it, the goblins of the window, and the chunks the batch
   revealed or changed.
4. Compare field by field. Equal, and `played` is the whole batch: the batch is confirmed.
5. Otherwise **rewind**: take the chain's state, drop every action played after the
   difference, including the batch filling, and report both states.

No state commitment is stored or emitted on chain: hashing the state costs gas on every batch.

**Reorgs.** A reorg can undo **any depth**: batches, and also Fate draws and gates that were
confirmed, and the instance itself (an `enter` that is gone). The two batches of speculation
are no ceiling on it. When the indexer reports a reorg (D-130), or a confirmed transaction is
no longer found, the client drops every prediction and every kept action, reads the canonical
state and shows it: the same instance at an earlier sequence, another instance, or the hub,
with a reward gone from the inventory if its draw is gone. Nothing is replayed for the player.

**How often.** In solo, on a deterministic action, **a difference is a bug** (S-3 asks for 0);
the other causes are a reorg (two in 13 months), the same adventurer on two devices, and co-op.
Every rewind is reported by the client with both states. Rewinds seen by players in a
playtest are D-133's reversal condition.

### Two adventurers in one instance (design/08, not in the MVP)

Under D-80 every action of any member ticks the world. Batches of two members interleave in
the order of their transactions.

| | |
|---|---|
| Validity | The sequence is **the instance's**: a member's batch runs only if no action ran since its player's count. When the other member acted in between, the batch runs nothing |
| The rewind | The other member's actions appear, the dropped ones fade out, and the player decides again on the new state |
| Its cost | Frequent when both act at once. The co-op design chooses between this strict check and a lenient one (the sequence of the member's own actions, each action still checked against the state it meets, as design/08 says), whether the check binds the history (above), and sizes batches for parties (smaller, and sent when another member's action arrives) |
| What the MVP does to keep it open | The entrypoint takes the adventurer's entity id, the sequence is a field of the instance (M-1, M-2), targets are entity ids (M-5), the permission check is "the caller controls this adventurer, and it is in this instance", never "the caller created the instance" (M-6) |

### Security and fairness

The rules and the state of an instance are public, and tactics are deterministic (D-40). An
invocation of `play` executes its actions **exactly as they would run one per invocation, in
the same order** (ENG-01 tests it). So a batch reaches no state that single actions could not.

**One transaction is not one invocation.** Our client puts one call in a transaction (with
version 1's `request_random` before a Fate call). An account's multicall can put several:
`play` twice, `play` then `loot`, `play` then a gate. Composing calls in one transaction gives
nothing that the same calls in consecutive transactions would not: each call checks its own
sequence and preconditions against the state it meets, and no rule inside an instance reads
anything of the transaction (ADR-0001), Fate apart (below).

| A player tries to | Gains | Why |
|---|---|---|
| Play ahead, look, then not send (take back) | Nothing | A modified client can already simulate any sequence before sending it, batch or not. Our client never takes an action back (I-5) |
| Compute a batch off-chain, reorder or optimise it | Nothing | It is the same as playing those actions one by one with a solver at hand, which single transactions already allow. The world waits (D-01): there is no time to save |
| Hold actions back and send them later | Nothing | No rule inside an instance reads the block, the time or the transaction hash; an instance is private in the MVP. A late batch meets the same state |
| Replay a batch, or send it twice | Nothing | The count has moved: it runs nothing |
| Compose several `play` calls, or `play` with a gate, in one multicall | Nothing | The same as consecutive transactions: same state, same rules, each call checked on its own |
| Ignore the stop conditions of a planned queue | Nothing | They protect the player from a walk they did not watch; the contract never needed them |
| Steer the next chunk by the order of actions (D-111) | Nothing more | The player entropy is a set, not a sequence; trying irreversible options off-chain is possible without batches (ADR-0006) |
| Put a Fate call in the same transaction as a batch | Nothing new in the MVP; closed in version 1 by the rule below | `play` cannot encode a Fate action, but a multicall can carry a Fate call after it |
| Burn gas with heavy batches or long multicalls | Nothing new | Weight 10 bounds one invocation, not a transaction; a transaction is bounded by the resources it signs. A sponsor's limit (ADR-0001's silent rate limits) must count **gas**, not transactions |

**Fate (ADR-0002).**
- **MVP, transaction-hash provider.** Every Fate draw can already be steered by varying the
  transaction (the tip, the resource bounds, any call beside it). A multicall that carries a
  batch and then a Fate call adds one more thing to vary, not a new weakness: this is the
  accepted, pre-existing weakness of ADR-0002, with or without batches. Our client sends a
  Fate action alone, after the batch before it is confirmed, with the expected sequence.
- **Version 1.** The provider **must not draw from anything the same transaction can steer**:
  neither the transaction's hash or calldata, nor state that an earlier call of the same
  transaction wrote. With that rule a Fate call behind a batch in one multicall draws what it
  would draw alone. `request_random` stays first in its multicall (rule 3).

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
        sequence,      after the batch (on a mismatch: the instance's current one)
        clock,         after the batch
    }

loot, open, mine(instance_id, adventurer_id, sequence, target)
leave(instance_id, adventurer_id, sequence, gate)    closes; enters the next location if the gate leads to one
travel_back(instance_id, adventurer_id, sequence)
    on a mismatch or a failed precondition, before any draw:
        emits Refused { instance_id, adventurer_id, from, sequence (current), reason }
        and changes nothing

enter(adventurer_id, gate)    creates the instance at sequence 0; its event gives the id
```

| | |
|---|---|
| Bounds | 1 to 10 actions per invocation; weight ≤ 10; each action's ticks bounded by its tick cost ([04](04-combat.md#actions)); each tick by the simulation budget above |
| Other events | Each action emits what it emits alone (a goblin killed, a chunk revealed, defeat); `BatchPlayed` is the batch's summary |
| Views | Readable at any block: the instance (clock, sequence, entropy, status); the adventurer in it (position, facing, health, energy, adrenaline, conditions, effects, deadlines, activation, belt); every goblin of the window (the same, plus AI state and memory); a chunk by its coordinates (terrain, objects, remains). Everything an action depends on |
| Never read | Block number, timestamp, transaction hash (ADR-0001) |

### What ENG-01 must do

1. `Instance.sequence`: 0 at `enter`; +1 per executed action in `play`, loot, open, mine; the
   gate and travel-back semantics above.
2. `play` as above: sequence check, weight counted as the actions run, stop at the first
   invalid action, no revert for invalidity in the game, `BatchPlayed`.
3. Loot, open, mine, leave, travel back: the `sequence` argument; every precondition checked
   before `fate(domain)`; `Refused` without a draw; the draw and the consumption in one
   invocation.
4. No stop conditions in the contract: the planned queue is the client's.
5. Tests that a batch, the same actions one per invocation, and several invocations in one
   multicall give the same state and events, over the shared vectors (SPK-4).
6. **Prove the gas bound before the weights are frozen**: the worst batch of weight 10 with
   the full action execution (window assembly, every goblin of the window, full AI, skills),
   worst ticks, reveals and their new storage, events, validation and the account's overhead,
   and the cost of rejecting at the first invalid action. Keep 40M and the weights, or replace
   them. Measure a revealed chunk.
7. The views above, readable at a block.
8. Permission: the caller controls `adventurer_id`, and that adventurer is in `instance_id` (M-6).

### What CLI-03 must do

1. Draw each action at once from the shared rules; write it to the device before drawing it.
2. Fill batches by weight; send on the triggers above (5 s idle, background, fight end,
   defeat, before a Fate action or a gate); one batch in flight; **wait when the batch filling
   is full** while the other is in flight.
3. Walk planned queues step by step, evaluating the stop conditions; each step is a played
   action.
4. One call per transaction; sign resources for the batch's proven bound.
5. Handle the three receipt statuses as above: succeeded (reconcile), reverted (fresh nonce,
   half-size batches, never a single action twice), not found (same nonce, 5 times over about
   60 s, then suspend).
6. Reconcile after every succeeded batch through the views at the receipt's block; rewind on
   any difference.
7. Recover from a reorg of any depth: drop predictions and kept actions, show the canonical
   state, including an instance that no longer exists and a draw or a gate that is gone.
8. At launch, send the kept batch if the instance exists at the expected sequence, else drop
   it and show the chain's state.
9. Send a Fate action or a gate alone, after the batch before it is confirmed; take the new
   instance id from the entry event.
10. Report every rewind and every reverted batch with both states.
11. Never take a played action back.
