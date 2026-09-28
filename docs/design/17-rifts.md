# 17 — Rifts: ephemeral dungeons and stillstone

> Status: **Draft v0.2** (v0.2: Rift; closing delay triggered by the first clear; ten grades; stillstone is a rare reagent) — proposal following the lore premise
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

## Life of a Rift

```
 appears ──▶ open ──▶ ripening ──▶ spills
    │          │          │
  graded       └────┬─────┘
                    │ first adventurer kills the Heart
                    ▼
                 closing ──▶ closed for everyone
```

| Stage | Duration (initial) | Effect |
|---|---|---|
| Appears | — | Drawn for a region: site, grade, size, seed. Posted on the Guild board of the region's hubs |
| Open | 3 days | Anyone of sufficient rank may enter. Each entry is that adventurer's own instance |
| Ripening | 2 more days | Castes one tier higher appear; remains are richer |
| **Closing** | **24 hours** from the first kill of the Heart, by anyone | Still open to everyone. The board shows the countdown and who struck first |
| Closed | — | Nobody can enter. Instances already running go on to their end |
| Spills | If the 5 days pass without any kill | See below |

Closure rule (D-95):

| | |
|---|---|
| Instances | **Individual**: each adventurer who enters has their own copy, same grade, same layout seed |
| First clear | Starts the closing delay **for everyone** |
| During the delay | Everyone can still enter and clear. Each adventurer clears a given Rift **once** |
| Why | The first clear is an event the whole region sees, and gives the others a deadline instead of taking the content away from them |
| Credit | The first to clear is named on the board and earns a title counter; rewards inside are the same for all |

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
| Smith | **Lift a modifier off an item without any risk** for the item | Expert salvage kit: the item is destroyed one time in two |
| Smith | Personalise an item ([15-equipment](15-equipment.md#personalisation-d-48)) | Not possible |
| Alchemist | **Read a pair** before brewing it: learn whether these two ingredients make a potion for this adventurer, without consuming them | Try, and lose the ingredients on a failure |
| Enchanter | Set a modifier on an item **without losing the one it replaces**, which comes back as a component | The replaced modifier is lost |
| Collector | With a heartstone: choose which piece of the boss set is given | The piece is drawn |

This replaces the "perfect salvage kit" of the equipment document.

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
| Closing | The first clear writes a closing time on the Rift's record, through the results interface. Entering checks it. One write, by the first finisher only |
| Once per adventurer | A bitmap of cleared Rifts per adventurer, keyed by the Rift's id within its period |

## Scope

| Release | Contains |
|---|---|
| **MVP** | Rifts of grades Wood to Copper in Region 1; closing delay; mining; stillstone and its uses; Red Rifts; heartstone |
| Later | Spill with consequences; higher grades with their regions |

## Open

| # | Question |
|---|---|
| RF-2 | How many Rifts at once per region? Initial value: 3 |
| RF-4 | Should a Red Rift be announced on the board after enough players have met it, as rumour? |
