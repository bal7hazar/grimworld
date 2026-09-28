# 17 — Rifts: ephemeral dungeons and stillstone

> Status: **Draft v0.3** (v0.3: rotation by slots proposed; enchanter owns modifiers; no stillstone at collectors)
> Previous: **Draft v0.2** (v0.2: Rift; closing delay triggered by the first clear; ten grades; stillstone is a rare reagent) — proposal following the lore premise
> ([lore/00-premise](../lore/00-premise.md)). Numbers are initial values. Names are
> working names.

This document turns the lore into features. It adds one kind of location and one
resource, and changes nothing to the rules of instances.

## Two kinds of dungeon

| | **Nest** | **Rift** |
|---|---|---|
| Exists | Always, at a fixed place on the map | For a limited time, at a place drawn among the region's sites |
| Role | Story, quests, promotion trials | Repeatable content; the core of the long game |
| Layout | Shifting ([01-world](01-world.md#geography-fixed-vs-shifting-d-10)) | Shifting |
| Difficulty | Set by the registry | **Graded** when it appears |
| Reward | Quest rewards, boss item | Stillstone, heartstone, equipment, boss item of the grade |

## How many Rifts, and for how long (proposal, RF-5)

The question to answer first is supply. Two simple answers both fail:

| Model | Failure |
|---|---|
| A fixed batch per day (say 10), renewed at midnight | A strong player clears them in half an hour and has nothing left until tomorrow |
| Closing 24 hours after the first clear | Too slow to matter if Rifts are renewed daily anyway; and it does not create new content |

Proposal: **slots that refill**.

| | |
|---|---|
| Slots | Each region has a fixed number of Rift slots: **2 per grade available in the region**. Region 1 (Wood, Tin, Copper): 6 slots |
| A slot always holds a Rift | When a Rift closes, the slot **draws a new one at once**: new site, new seed, same grade |
| Instances | Individual: each adventurer who enters has their own copy |
| Once | An adventurer clears a given Rift once |
| First clear | Starts the **closing delay for everyone: 30 minutes** |
| Closing | Still open to all during the delay; then closed and replaced |
| Nobody clears it | It ripens after 1 day (harder, richer), and spills after 2: closed and replaced |

What this gives:

| Situation | Result |
|---|---|
| A strong player clears the six Rifts in half an hour | Each closes 30 minutes after they cleared it, and is replaced. They always have fresh Rifts within the half hour |
| A quiet region, few players | Rifts stay up to 2 days; nothing is lost by coming late |
| A busy region | Rifts turn over fast; the board is alive; being first means something |
| Two players of different strength | The strong one sets the pace of the rotation; the other has 30 minutes from the first clear, which is more than an instance lasts |

What limits farming, since supply never runs out:

| Limit | |
|---|---|
| Time | A Rift is 5 to 20 minutes of actual play |
| Merit | Diminishing returns per grade per day, as for contracts |
| Transactions | Every action is a transaction. The paymaster sponsors a daily allowance per account; beyond it the player pays their own fees. **This is the real budget of the game and must be sized in Phase 0** |
| No energy, no keys | Deliberately. Nothing stops a player who wants to play |

## Life of a Rift

```
 drawn ──▶ open ──▶ ripening ──▶ spills ──▶ replaced
             │          │
             └────┬─────┘
                  │ first adventurer kills the Heart
                  ▼
               closing (30 min) ──▶ closed ──▶ replaced
```

## Grades

| Grade | Rank required | Goblin tiers | Floors | Heart |
|---|---|---|---|---|
| Wood | Wood | 1 | 1 | Skirmisher |
| Tin | Tin | 1–2 | 2 | Shaman |
| Copper | Copper | 2–3 | 2 | Hobgoblin |
| Iron | Iron | 3 | 3 | Hobgoblin with a retinue |
| Steel | Steel | 3–4 | 3 | Hexer |
| Bronze | Bronze | 4 | 3 | Champion |
| Silver | Silver | 4–5 | 4 | Paladin |
| Gold | Gold | 5–6 | 4 | Lord |
| Platinum | Platinum | 6 | 5 | Lord, affixed |
| Still | Still | 6, affixed | 5 | Two Hearts |

An adventurer may enter a Rift **one grade above** their rank, at their own risk; it gives
no extra merit.

## Red Rifts

| | |
|---|---|
| Frequency | 1 Rift in 10, **not shown on the board**: the player learns it at the second room |
| Decided | By the Fate draw of the instance seed, when entering |
| Effect 1 — sealed | Travelling back to a hub is disabled. The instance ends by killing the Heart or by defeat |
| Effect 2 — misgraded | Goblins and Heart are those of the grade above |
| Reward | Rarity of looted equipment shifted one step up; boss item chance doubled; one stillstone guaranteed |
| Defeat | As everywhere: costs the instance only (D-04) |

Because a defeat costs little, a Red Rift is a surprise and a challenge, not a punishment.

## Stillstone

**The treasure of a Rift is what its goblins carry** (D-96): equipment, ingredients,
trophies, gold. Stillstone is not an income and not a bulk material. It is a **rare
reagent**, asked for by a few precise operations.

### Finding it

| Source | Yield |
|---|---|
| A vein, as a room feature | 1 stone. About one vein per Rift floor, none in most rooms |
| The Heart of a Rift | 1 stone, always |
| Nests and zones | None |

Mining: adjacent to the vein, **3 ticks**, interrupted by any hit taken. No draw. Three
ticks is three goblin turns: mining in a room that is not cleared is a decision.

Stillstone has **one grade**. It is counted, not slotted, and can be traded.

### What it is for

Each use consumes one stone, in a hub.

| Craft | Operation | Without a stone |
|---|---|---|
| **Enchanter** | Lift a modifier off an item **without any risk** for the item | The item is destroyed one time in two |
| **Enchanter** | Set a modifier on an item **without losing the one it replaces**, which comes back as a component | The replaced modifier is lost |
| **Alchemist** | **Read a pair** before brewing it: learn whether these two ingredients make a potion for this adventurer, without consuming them | Try, and lose the ingredients on a failure |

Smiths and collectors do not use stillstone.

### Materials

Smiths and armorers keep ordinary materials, obtained by salvaging equipment: **iron,
hide, wood, cloth, bone**. Stillstone is not one of them.

## Spill

When a Rift's time is over and it has been closed by fewer adventurers than a threshold
(initially: none needed in the MVP, the Spill is cosmetic), the region is **raided**.

| | MVP | Later |
|---|---|---|
| Effect | A notice on the board; the site shows burned ground for a day | Guild contracts of the region become "repel" contracts for a day, with higher rewards; a merchant closes |

The Spill is where shared consequences, and later co-operative play, can grow.

## Relation to guild contracts

Rifts take over most of what repeatable contracts were for. Contracts stay for zones
(bounties, annihilation); Rifts are the repeatable dungeons.

## On-chain

| Point | Design |
|---|---|
| Appearance | A Rift is a registry-like record in the persistent domain: region, site, grade, seed, start time. Created by a permissionless call that anyone can make once per region per period; its parameters come from a Fate draw |
| Stages | Derived from the start time, lazily. No transaction makes a Rift ripen |
| Time | Real time is used **outside** instances only, to know whether a Rift can be entered. Inside, the tick rule is untouched |
| Instance | Entering snapshots the Rift's grade and stage. A Rift that expires while an adventurer is inside does not end their instance |
| Red | A flag of the instance, derived from its Fate seed |
| Slots | One record per slot: current Rift id, grade, seed, start time, closing time. Replacing a Rift is a permissionless call that draws the next one (Fate); the client of whoever looks at the board first makes it |
| Closing | The first clear writes a closing time on the slot's record, through the results interface. Entering checks it. One write, by the first finisher only |
| Once per adventurer | A bitmap of cleared Rifts per adventurer, keyed by the Rift's id within its period |

## Scope

| Release | Contains |
|---|---|
| **MVP** | Rifts of grades Wood to Copper in Region 1; closing delay; mining; stillstone and its uses; Red Rifts; heartstone |
| Later | Spill with consequences; higher grades with their regions |

## Open

| # | Question |
|---|---|
| RF-5 | Supply model: slots that refill, 30 minutes of closing delay (above). Owner's ruling needed |
| RF-4 | Should a Red Rift be announced on the board after enough players have met it, as rumour? |
