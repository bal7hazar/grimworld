# 08 — Multiplayer

> Status: **Draft v0.2** — co-op is **out of scope for v1** and must stay **possible**.
> v0.2: direction changed from clock-min to *every action ticks* after owner review.

## What v1 has

| Feature | v1 |
|---|---|
| Seeing other adventurers in hubs | Yes: who is in the hub comes from the indexer; live movement is cosmetic and needs a relay (Q-09) |
| Chat in hubs | Client feature, off-chain (Q-09) |
| Inspecting another adventurer (rank, level, build) | Yes, read from chain |
| Leaderboards (rank, trials, elite clears) | Yes, from the indexer; **not in the MVP** (design/09). Their events are emitted from the MVP on |
| Trading | Open (Q-07) |
| Parties in dedicated instances | **No** |
| PvP | No |

## The co-op problem

The tick rule says the world moves when the player acts. With several players in one
instance, whose action moves the world?

## Models considered

| | Model | How it works | Verdict |
|---|---|---|---|
| A | Lockstep rounds | The world ticks when every member has acted, or a deadline passes | Rejected: needs a wall-clock timeout |
| B | Rate-limited world | At most one world tick per block; actions in between are collected | Rejected: players who synchronise their actions in one block get several actions for one tick. Ties rules to block time |
| C | Clock-min | World time is the minimum of the members' clocks | Rejected: one AFK member freezes the world for everyone |
| **D** | **Every action ticks** | Any action by any member advances the world by its tick cost, exactly as in solo | **Preferred (D-80)** |

## Preferred direction: every action ticks (D-80)

The solo rule is kept unchanged: `1 action = its tick cost in world ticks`, whoever acts.

| Property | Consequence |
|---|---|
| No new rule, no timer, no block dependency | Solo is a party of one; the engine has one code path |
| An AFK member cannot stall anyone | They simply stand there, and goblins can reach them |
| The world runs N times faster relative to each member | Goblins act more often per member action: **difficulty scales with party size by construction** |
| Durations, recharges and regeneration run on world time | Members also recharge and regenerate N times faster relative to their own actions, which partly offsets the point above |
| Order of actions is the order of transactions | Two members acting in the same block are sequenced by the chain; both actions are valid as long as each is still legal when executed |

To be settled when co-op is designed, not now:

- Net difficulty: whether spawn tables also need a party-size modifier.
- Conflicting optimistic predictions between members (each client predicts from a state
  the other may have changed). Expected approach: predict own action, reconcile on the
  indexer stream.
- Loot and quest credit sharing.
- What happens to a party member who is defeated while the others go on.

## What v1 must do to keep the door open

These constraints are binding on the v1 implementation and are checked in audits.

| # | Constraint |
|---|---|
| M-1 | Instance state is keyed by **instance id**, never by adventurer id |
| M-2 | Time is a field of the **instance**. Durations and recharges are stored as instance-clock deadlines, never as counters attached to "the" adventurer's turn |
| M-3 | Goblin target selection takes a **list** of adventurers, even if its length is 1 |
| M-4 | Loot and quest credit go through a function that takes the **set of contributors** |
| M-5 | Ally-targeted skills target an **entity id**, not "self" implicitly |
| M-6 | The permission model does not assume that the instance creator is the only writer |

## When to revisit

After the solo loop passes the fun gate (PLAN, Phase 3). Co-op then gets its own design
document and ADR.
