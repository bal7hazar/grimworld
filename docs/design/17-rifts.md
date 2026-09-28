# 17 — Rifts: ephemeral dungeons and stillstone

> Status: **Draft v0.5** (v0.5: three open, five a day, the fifth is the Red Rift)
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

Rifts are **personal**. Nothing about them is shared between players.

| | |
|---|---|
| Open at the start of the day | **3 Rifts**, spread over the grades the account's adventurers can enter |
| **Per day** | **5 Rifts, per account**, all adventurers together |
| Clearing the 1st | The 4th opens |
| Clearing the 2nd | **The 5th opens: the Red Rift** |
| Day | Changes at 00:00 UTC. Rifts not cleared are replaced by the new day's |
| Defeat or leaving | The Rift stays on the board; entering again is a new instance of the same Rift |

```
 day starts      ①  ②  ③
 one cleared     ✓  ②  ③  ④
 two cleared     ✓  ✓  ③  ④  ⑤ red
```

The day has a shape: three ordinary choices, a fourth as a reward for starting, and the
Red Rift as the **finale**, earned by clearing two. A player who wants only the finale
clears two easy Rifts first; a player who wants everything clears five.

Why a cap, and why per account:

| | |
|---|---|
| Against farming | Bounds what one account can bring to the market per day |
| Per account | Three adventurers must not mean three times the cap, nor the feeling of repeating the same day on each of them |
| Bounds cost | Five Rifts a day is also the upper bound of what an account costs in network fees, which the game pays (pillar 7) |
| No energy, no timer | The player chooses when and which |

After the fifth: zones, nests, quests, contracts, collectors, the market. The cap closes
Rifts for the day, not the game.

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

The Red Rift is the **last Rift of the day**. It is announced: the player knows what they
walk into.

| | |
|---|---|
| Opens | When two Rifts of the day are cleared |
| Grade | The highest grade the adventurer entering it may enter |
| **Sealed** | Travelling back to a hub is disabled. The instance ends by killing the Heart or by defeat |
| **Misgraded** | Goblins and Heart are those of the grade above |
| Attempts | Defeat costs the instance only (D-04): the Red Rift stays on the board until the day ends |
| Reward | Rarity of looted equipment shifted one step up; boss item chance doubled; one stillstone guaranteed |

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
| Board | Persistent domain, **per account and per day**: five Rift identities (grade, biome, target size) derived from one Fate draw made by the first board action of the day, and a bitmap of cleared Rifts. **An identity is not a layout**: the content of a Rift is decided at reveal, inside the instance |
| Opening | Derived: Rift 4 is enterable when one bit is set, Rift 5 when two are. No transaction opens a Rift |
| Daily cap | Falls out of the five seeds: there is nothing more to enter |
| Time | Real time is used **outside** instances only. Inside, the tick rule is untouched |
| Red | The fifth Rift of the day |

## Scope

| Release | Contains |
|---|---|
| **MVP** | Rifts of grades Wood to Copper in Region 1; three open, five a day, the Red Rift last; mining; stillstone and its uses; heartstone |
| Later | Higher grades with their regions |

## Open

| # | Question |
|---|---|
