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
| Kept | On the device, **written before the action is drawn**: instance id, adventurer id, expected sequence, the actions, and **the result the player saw** after each one (the predicted state, or its hash) |
| The app closes or crashes | At the next launch the client reads the whole instance (*The client's copy*) and **recovers** the kept actions (*The chain's answer*) before any new action |
| The chain moved meanwhile (another device played this adventurer, a reorg) | Recovery keeps the kept actions whose results are still the same on the chain's state, and drops the rest (design/11) |
| The device is lost | Lost with it, as the burner is (ADR-0005) |
| How much can be lost | **At most two batches, weight 20**: the one filling and the one in flight not yet included. The bound is in actions, not seconds |
| Taken back | Never, in our client (I-5). A modified client can already compute any sequence before sending it: nothing is given away (*Security*) |

**No maximum age of a batch.** A batch that is not full leaves after 5 seconds without input;
a batch filled without pause is full within weight 10. A maximum age would only split batches
that are being filled, paying the fixed part again, without lowering the bound in actions,
which is what the player can lose.

This amends D-05: an instance resumed **on another device** resumes at the last action the
chain has; the actions played on the first device and not sent, at most two batches, are lost.

### The client's copy of the instance

The client simulates only over **authoritative state it holds**. The indexer is never a
source of simulation state: no indexer is needed to play (ADR-0007); it serves display
(other players, hubs).

| | |
|---|---|
| What the copy holds | The instance (sequence, clock, entropy, status); the adventurers in it; **every revealed chunk** (terrain, occupancy, objects, remains); **every goblin of the instance, frozen or awake**, with its full state (position, facing, health, conditions, effects, activation, deadlines, AI state and memory, spawn) |
| How it is read | Reads **pinned to one accepted block hash**: several calls pinned to the same block are one coherent state. `instance_state(instance_id)` for the instance and what the windows hold; `instance_region(instance_id, chunk range)` for the rest, paged by chunks |
| At launch, on another device, after a reorg | The **whole instance** is read that way, at one block, before play resumes |
| After a confirmed batch | The snapshot of *Reconciling*; and, once the batch's block is accepted, `instance_state` again with the regions the batch's windows crossed, all at that block hash (a `pre_confirmed` read is one call and cannot be joined to another) |
| Crossing into a chunk | Speculation runs **only over state the copy holds or the client generates**. The window meets three kinds of chunk, below; only the first is ever read |

| Kind of chunk | On the chain | The client |
|---|---|---|
| **Revealed** | Stored | Read, pinned to one accepted block, as above. A revealed chunk missing from the copy is read before the window reaches it; play waits for it (design/11: "saving…") |
| **Not yet revealed** (inside the location's outline) | Does not exist yet | **Generated by the client** from the entry draw and the adventurer's irreversible actions (D-111), in the speculative overlay, by the move that reveals it. Reconciliation checks it like any other result. The client never waits to read it |
| **Void** (the margin around a location, or outside a zone's outline, D-134) | Never revealed, never stored | A constant (wall everywhere), assembled without any read or wait |

**The first chunk.** The entry draw is a Fate action, sent alone (`enter`, or a gate): the
client waits for its result and predicts nothing in the instance before it.

**How the views tell them apart.** `instance_state` returns the instance's **revealed set**
(which chunks are revealed) and the location's id; the location's outline and its void margin
are content, read from the registry. A chunk in the revealed set is revealed; a chunk inside
the outline and not in it is not yet revealed; any other is void. `instance_region` returns,
for each chunk of its range, its kind, and data only for revealed chunks.
| What speculation adds | The predicted state of the actions played and not confirmed, layered over the copy; never written into it |

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
| **Not found** | **Unknown**: not received yet, rejected, dropped, or included and not yet visible to this node. Not a free nonce | Keeps the transaction's identity and **rebroadcasts the same signed transaction** (same nonce): at most one of them can run. Up to 5 times over about 60 seconds; then asks once more for its receipt and events. Still unknown: **recovers** (below) |

**Reconciling.** The chain's state is the truth; the client checks its prediction against it
after every succeeded batch.

1. Read `BatchPlayed` from the receipt: `from`, `played`, `stop`, `sequence` after.
2. Take its own state after the first `played` actions of the batch.
3. Read **one snapshot**: a single call of `instance_state(instance_id)`, pinned to the
   receipt's **block hash** once the block is accepted, or at `pre_confirmed` before it. One
   call, because several reads are not one state; a block's state (and `pre_confirmed` above
   all) can already hold later transactions.
4. Compare the snapshot's `sequence` with `BatchPlayed`'s `sequence` after:

| Snapshot's sequence | Means | The client |
|---|---|---|
| **Equal** | The snapshot is the state right after the batch | Compares field by field. Equal, and `played` is the whole batch: the batch is confirmed. A difference, or fewer played: **rewind** (below) |
| **Greater** | Later actions ran after the batch: another device, a co-op member | Adopts the snapshot as the chain's state and **recovers** what it played after the batch (below). **Not a divergence**: nothing is reported as a bug |
| **Smaller** | The read is stale (a node behind the one that gave the receipt) | Reads again; never installs it |

5. **Rewind**: take the snapshot as the state, drop every action played after the difference,
   including the batch filling, and report both states.

A state built from several reads is **never installed**. No state commitment is stored or
emitted on chain: hashing the state costs gas on every batch.

**Recovering.** When the outcome of a transaction stays unknown, and at every launch, the
client uses **only what it can observe**, never which transaction ran:

1. Read **the account's nonce** from the account, never assumed, pinned to one accepted block
   hash.
2. Read **one coherent snapshot** of the instance at the same block (*The client's copy*).
3. **Adopt the snapshot as the chain's state**, without claiming which transaction ran.
4. **Re-simulate, in order**, every action played and not seen confirmed, on the snapshot. The
   prefix whose results match what the player saw is **kept**, renumbered from the snapshot's
   sequence, and sent with the nonce read in step 1. From the first mismatch on, the actions
   are dropped and the view rewinds.

| What happened, unknown to the client | What recovery does, the same steps |
|---|---|
| The batch ran | Its actions are already in the snapshot, so replaying the first one on it gives another result than the one stored: the first mismatch is there, and **that action and every one after it are dropped**. The snapshot keeps what the batch did; the actions played after it are lost. A conservative loss: from sequence 0, a `Wait` that ran (stored result: clock 1) and a second `Wait` not sent (clock 2) are both dropped, since the first replays to clock 2 |
| The batch was included and reverted (nonce moved, sequence not) | Its actions replay on the snapshot with the same results and are sent again with the new nonce |
| The nonce was taken by something else (another device) | The actions replay on what that device did; those with the same results are kept, the rest dropped |
| Nothing was included | Same as the second line, with the old nonce |

A modified or unlucky history cannot make recovery keep an action whose result the player did
not see. **Only a node that cannot be reached** is shown as a lost connection: play is
suspended, the actions stay on the device, and recovery runs when the node answers.

**Reorgs.** A reorg can undo **any depth**: batches, and also Fate draws and gates that were
confirmed, and the instance itself (an `enter` that is gone). The two batches of speculation
are no ceiling on it. When a confirmed receipt's block is no longer on the canonical chain
(checked at the next pinned read; the indexer, D-130, may say so sooner), or a confirmed
transaction is no longer found, the client drops every prediction and every kept action,
reads the whole instance again (*The client's copy*), or finds it gone, and shows the result: the same instance at an earlier sequence, another instance, or the hub,
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
| Put a Fate call in the same transaction as a batch | Nothing new in the MVP; version 1 must close it (below) | `play` cannot encode a Fate action, but a multicall can carry a Fate call after it |
| Burn gas with heavy batches or long multicalls | Nothing new | Weight 10 bounds one invocation, not a transaction; a transaction is bounded by the resources it signs. A sponsor's limit (ADR-0001's silent rate limits) must count **gas**, not transactions |

**Fate (ADR-0002).**
- **MVP, transaction-hash provider.** Every Fate draw can already be steered by varying the
  transaction (the tip, the resource bounds, any call beside it). A multicall that carries a
  batch and then a Fate call adds one more thing to vary, not a new weakness: this is the
  accepted, pre-existing weakness of ADR-0002, with or without batches. Our client sends a
  Fate action alone, after the batch before it is confirmed, with the expected sequence.
- **Version 1: a requirement, not yet met.** Independent randomness is not enough. A
  transaction the player controls can read its draw and **abort** (revert) when it is
  unwanted, then try again; batching or not. The provider and the account design of version 1
  must give:
  - **Attempt-stable draws**: the same attempt cannot be retried for a new value; for example,
    a request committed in one transaction and fulfilled in a later one, the result bound to
    the request;
  - **No re-roll by a conditional abort**: a transaction that reverts after seeing its draw
    leaves the draw spent or the request pending with the same value;
  - **The permitted composition stated**: which calls may share a transaction with a Fate call.
  - Also: the provider does not draw from anything the same transaction can steer (its hash or
    calldata, state an earlier call of it wrote). `request_random` stays first in its
    multicall (rule 3).

  This is ADR-0002's to decide (an escalation of DES-21); design/02 does not claim version 1
  closes it.

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
| View | **`instance_state(instance_id)`**, one call, readable at a block hash or at `pre_confirmed`: the instance (sequence, clock, entropy, status, location, **revealed set**); the adventurers in it (position, facing, health, energy, adrenaline, conditions, effects, deadlines, activation, belt); every goblin of their windows (the same, plus AI state and memory); the occupancy and terrain of the chunks their windows overlap (tiles, objects, remains). Everything a played action depends on, in one snapshot |
| View | **`instance_region(instance_id, chunk range)`**, readable at a block hash: for each chunk of the range, its kind (revealed, not yet revealed, void); for each revealed one, its terrain, occupancy, objects and remains, and every goblin standing in it, frozen or not, with its full state. Paged: a range is bounded so that one call fits a node's limits. With `instance_state` at the same block, the whole instance |
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
7. The view `instance_state(instance_id)` above: one call, everything a played action
   depends on, readable at a block hash and at `pre_confirmed`.
8. The view `instance_region(instance_id, chunk range)`, readable at a block hash, with its page
   bound. Tests: **restart**, the whole instance read by `instance_state` and every region at
   one block equals the contract's state; **window crossing**, a goblin frozen outside the
   window read back by region has the state it had when it left.
   **Reveal**: a batch whose move reveals a chunk gives the chunk the client generates from
   the same entry draw and irreversible actions (shared vectors), and the revealed set gains
   it. **Boundary**: at the edge of a location, the window assembles void chunks as constants,
   with no storage read or write, and `instance_region` reports them as void.
9. Permission: the caller controls `adventurer_id`, and that adventurer is in `instance_id` (M-6).

### What CLI-03 must do

1. Draw each action at once from the shared rules; write it to the device before drawing it.
2. Fill batches by weight; send on the triggers above (5 s idle, background, fight end,
   defeat, before a Fate action or a gate); one batch in flight; **wait when the batch filling
   is full** while the other is in flight.
3. Walk planned queues step by step, evaluating the stop conditions; each step is a played
   action.
4. One call per transaction; sign resources for the batch's proven bound.
5. Handle the three receipt statuses as above: succeeded (reconcile), reverted (fresh nonce,
   half-size batches, never a single action twice), not found (keep the transaction's
   identity, rebroadcast it with the same nonce 5 times over about 60 s, ask once more for its
   receipt, then **recover**; "connection lost" only when the node cannot be reached).
6. Reconcile after every succeeded batch with one `instance_state` snapshot pinned to the
   receipt's block hash, or at `pre_confirmed`: equal sequence, compare and rewind on a
   difference; greater, adopt it and recover without reporting a divergence; smaller, read
   again. Never install a state built from reads at different blocks.
7. Recover from a reorg of any depth: drop predictions and kept actions, show the canonical
   state (the whole instance read again), including an instance that no longer exists and a
   draw or a gate that is gone.
8. At launch or on another device, read the whole instance at one block, then recover the
   kept actions. Recovery: nonce read from the account and snapshot at one block; adopt it;
   re-simulate every unconfirmed action in order; keep the prefix whose results match what the
   player saw, renumbered and sent with the nonce read; drop from the first mismatch.
9. Send a Fate action or a gate alone, after the batch before it is confirmed; take the new
   instance id from the entry event.
10. Report every rewind and every reverted batch with both states.
11. Never take a played action back.
12. Keep the copy of the instance: every revealed chunk and every goblin, frozen or not, read
    pinned to one block; refresh the regions a confirmed batch's windows crossed. Tell the three
    kinds of chunk apart by the revealed set and the outline: before the window reaches a
    **revealed** chunk the copy lacks, read it and wait; generate a **not yet revealed** chunk
    in the overlay and never wait for it; assemble a **void** chunk as a constant. Tests: a
    reveal move played without a read, and checked at reconciliation; walking along a
    location's edge with no read and no wait. Wait for the entry draw before predicting
    anything in a new instance. Never take simulation state from the indexer.
