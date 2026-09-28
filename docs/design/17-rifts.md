# 17 — Rifts: ephemeral dungeons and stillstone

> Status: **Draft v0.4** (v0.4: Rifts are personal; six open, ten a day; no shared closure)
> Previous: **Draft v0.3** (v0.3: rotation by slots proposed; enchanter owns modifiers; no stillstone at collectors)
> Previous: **Draft v0.2** (v0.2: Rift; closing delay triggered by the first clear; ten grades; stillstone is a rare reagent) — proposal following the lore premise
> ([lore/00-premise](../lore/00-premise.md)). Numbers are initial values. Names are
> working names.

This document turns the lore into features. It adds one kind of location and one
resource, and changes nothing to the rules of instances.

## Two kinds of dungeon

| | **Nest** | **Rift** |
|---|---|---|
| Exists | Always, at a fixed place on the map | On the adventurer's own board, until cleared |
| Role | Story, quests, promotion trials | Repeatable content; the core of the long game |
| Layout | Shifting ([01-world](01-world.md#geography-fixed-vs-shifting-d-10)) | Shifting |
| Difficulty | Set by the registry | **Graded** when it appears |
| Reward | Quest rewards, boss item | Equipment, ingredients, trophies, gold; stillstone; heartstone; boss item of the grade |

## Supply (D-101)

Rifts are **personal**. Nothing about them is shared between players: no race, no closure
by others.

| | |
|---|---|
| Open at any time | **6 Rifts** on the adventurer's board, spread over the grades their rank allows |
| Clearing one | A new one opens **at once** in its place |
| **Daily cap** | **10 Rifts cleared per day, per account**, all adventurers together |
| Day | Changes at 00:00 UTC |
| Left untouched | A Rift **ripens** after one day (harder, richer) and is replaced after two |
| Defeat or leaving | The Rift stays on the board; entering again is a new instance of the same Rift. Only a clear counts towards the cap |

Why a cap, and why per account:

| | |
|---|---|
| Against farming | Supply is otherwise endless. The cap bounds what one account can bring to the market per day, which protects prices |
| Per account | Three adventurers must not mean three times the cap |
| Bounds cost | Ten Rifts a day is also the upper bound of what an account can cost in network fees, which the game pays (pillar 7) |
| No energy, no timer | The player chooses when and which. The cap is a number of clears, not a waiting time |

What is left after the cap: zones, nests, quests, contracts, collectors, the estate, the
market. The cap closes Rifts for the day, not the game.

## Life of a Rift

```
 opens ──▶ open ──▶ ripening ──▶ replaced
             │          │
             └────┬─────┘
                  │ Heart killed
                  ▼
               cleared ──▶ a new one opens in its place
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
| Onyx | Onyx | 6, affixed | 5 | Two Hearts |

An adventurer may enter a Rift **one grade above** their rank, at their own risk; it gives
no extra merit.

## Red Rifts

| | |
|---|---|
| Frequency | 1 Rift in 10, **not shown on the board**: the player learns it at the second room |
| Cap | A Red Rift counts as one clear |
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
| **Smith** | **Personalise** an item ([15-equipment](15-equipment.md#personalisation-d-48)) | Not possible |
| **Enchanter** | Lift a modifier off an item **without any risk** for the item | The item is destroyed one time in two |
| **Enchanter** | Set a modifier on an item **without losing the one it replaces**, which comes back as a component | The replaced modifier is lost |
| **Alchemist** | Buy a **hint** ([07-loot-and-alchemy](07-loot-and-alchemy.md#hints)) | Not possible |

Collectors do not use stillstone.

### Materials

Smiths and armorers keep ordinary materials, obtained by salvaging equipment: **iron,
hide, wood, cloth, bone**. Stillstone is not one of them.

## Relation to guild contracts

Rifts take over most of what repeatable contracts were for. Contracts stay for zones
(bounties, annihilation); Rifts are the repeatable dungeons.

## On-chain

| Point | Design |
|---|---|
| Board | Persistent domain, per adventurer: 6 slots, each with grade, seed, opening time |
| Opening | Drawn with the Fate word of the transaction that cleared the previous one: no extra transaction |
| Daily cap | One counter per account and per day, read when a clear is settled |
| Ripening | Derived from the opening time, lazily |
| Time | Real time is used **outside** instances only. Inside, the tick rule is untouched |
| Red | A flag of the instance, derived from its Fate seed |

## Scope

| Release | Contains |
|---|---|
| **MVP** | Rifts of grades Wood to Copper in Region 1; six open, ten a day; mining; stillstone and its uses; Red Rifts; heartstone |
| Later | Higher grades with their regions |

## Open

| # | Question |
|---|---|
| RF-4 | Should a Red Rift be announced on the board after enough players have met it, as rumour? |
