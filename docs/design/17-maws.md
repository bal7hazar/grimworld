# 17 — Maws: ephemeral dungeons and stillstone

> Status: **Draft v0.1** — proposal following the lore premise
> ([lore/00-premise](../lore/00-premise.md)). Numbers are initial values. Names are
> working names.

This document turns the lore into features. It adds one kind of location and one
resource, and changes nothing to the rules of instances.

## Two kinds of dungeon

| | **Nest** | **Maw** |
|---|---|---|
| Exists | Always, at a fixed place on the map | For a limited time, at a place drawn among the region's sites |
| Role | Story, quests, promotion trials | Repeatable content; the core of the long game |
| Layout | Shifting ([01-world](01-world.md#geography-fixed-vs-shifting-d-10)) | Shifting |
| Difficulty | Set by the registry | **Graded** when it appears |
| Reward | Quest rewards, boss item | Stillstone, heartstone, equipment, boss item of the grade |

## Life of a Maw

```
 appears ──▶ open ──▶ ripening ──▶ spills
    │          │          │           │
  graded    can be     harder,     goblins raid the region;
            entered    richer      the Maw is gone
               │
               └── Heart killed ──▶ closed (for everyone)
```

| Stage | Duration (initial) | Effect |
|---|---|---|
| Appears | — | Drawn for a region: site, grade, size, seed. Posted on the Guild board of the region's hubs |
| Open | 3 days | Anyone of sufficient rank may enter. Each entry is that adventurer's own instance |
| Ripening | 2 more days | Castes one tier higher appear; stillstone veins are 50% richer |
| Spills | — | See below |

A Maw is **shared as an opportunity, not as a place**: every adventurer who enters gets
their own instance of it, with the same grade and the same layout seed. Killing the Heart
closes the Maw **for that adventurer**; the Maw leaves the board when its time is over.

> Open point MW-1: should the first kill close it for everyone, as the lore suggests?
> It would create a race and reward the fastest players; it would also let one player
> deny content to all. Recommendation: personal closure in the MVP, a shared counter of
> closures shown on the board ("closed by 214 adventurers").

## Grades

| Grade | Rank required | Goblin tiers | Floors | Heart |
|---|---|---|---|---|
| Wood | Wood | 1 | 1 | Skirmisher |
| Tin | Tin | 1–2 | 2 | Shaman |
| Copper | Copper | 2–3 | 2 | Hobgoblin |
| Iron | Iron | 3–4 | 3 | Hobgoblin with a retinue |
| Bronze | Bronze | 4 | 3 | Champion |
| Silver | Silver | 4–5 | 4 | Paladin |
| Gold | Gold | 5–6 | 4 | Lord |
| Platinum | Platinum | 6 | 5 | Lord, affixed |

An adventurer may enter a Maw **one grade above** their rank, at their own risk; it gives
no extra merit.

## Red Maws

| | |
|---|---|
| Frequency | 1 Maw in 10, **not shown on the board**: the player learns it at the second room |
| Decided | By the Fate draw of the instance seed, when entering |
| Effect 1 — sealed | Travelling back to a hub is disabled. The instance ends by killing the Heart or by defeat |
| Effect 2 — misgraded | Goblins and Heart are those of the grade above |
| Reward | Red stillstone (sells double); boss item chance doubled |
| Defeat | As everywhere: costs the instance only (D-04) |

Because a defeat costs little, a Red Maw is a surprise and a challenge, not a punishment.

## Stillstone

### Mining

Veins are **room features**, placed at generation like remains or chests.

| | |
|---|---|
| Action | Mine: adjacent to the vein, **3 ticks**, interrupted by any hit taken |
| Yield | Fixed per vein: 1 to 3 stones of the Maw's grade. **No draw**: mining is deterministic |
| Why it matters | Three ticks is three goblin turns. Mining a vein in a room that is not cleared is a decision |
| Carried | Stones are counted, not slotted; they weigh nothing in the MVP |

### Grades of stone

One grade of stillstone per grade of Maw, plus red stillstone and the heartstone.

| Item | From | Use |
|---|---|---|
| Stillstone (8 grades) | Veins | Sold to the Guild at a fixed price; **the material of smiths and armorers**; traded between players |
| Red stillstone | Veins of Red Maws | Sold double; looks (smiths) |
| Heartstone | The Heart, always | Proof of closure: merit; one per boss set piece at the collector |

### Place in the economy

| Before | Now |
|---|---|
| Gold came from remains and quests | Gold comes mainly from **selling stillstone** |
| Eleven generic materials, as in the baseline | **Stillstone by grade** is the material; goblin trophies stay for collectors |
| Maximum equipment cost gold and materials | It costs gold and stillstone of the hub's grade |

The Guild buys at a fixed price, which sets a floor. The auction house
([16-trade](16-trade.md)) sets the real price: smiths' customers need stones of a given
grade, and a Platinum adventurer does not mine Copper.

## Spill

When a Maw's time is over and it has been closed by fewer adventurers than a threshold
(initially: none needed in the MVP, the Spill is cosmetic), the region is **raided**.

| | MVP | Later |
|---|---|---|
| Effect | A notice on the board; the site shows burned ground for a day | Guild contracts of the region become "repel" contracts for a day, with higher rewards; a merchant closes |

The Spill is where shared consequences, and later co-operative play, can grow.

## Relation to guild contracts

Maws take over most of what repeatable contracts were for. Contracts stay for zones
(bounties, annihilation); Maws are the repeatable dungeons.

## On-chain

| Point | Design |
|---|---|
| Appearance | A Maw is a registry-like record in the persistent domain: region, site, grade, seed, start time. Created by a permissionless call that anyone can make once per region per period; its parameters come from a Fate draw |
| Stages | Derived from the start time, lazily. No transaction makes a Maw ripen |
| Time | Real time is used **outside** instances only, to know whether a Maw can be entered. Inside, the tick rule is untouched |
| Instance | Entering snapshots the Maw's grade and stage. A Maw that expires while an adventurer is inside does not end their instance |
| Red | A flag of the instance, derived from its Fate seed |
| Counters | Closures per Maw: one counter, incremented through the results interface |

## Scope

| Release | Contains |
|---|---|
| **MVP** | Maws of grades Wood to Copper in Region 1; mining; stillstone as material and as income; Red Maws; heartstone |
| Later | Spill with consequences; shared closure; higher grades with their regions |

## Open

| # | Question |
|---|---|
| MW-1 | Personal or shared closure (above) |
| MW-2 | How many Maws at once per region? Initial value: 3 |
| MW-3 | Does stillstone replace crafting materials entirely, or sit beside a few others (hide, wood)? |
| MW-4 | Should a Red Maw be announced on the board after enough players have met it, as rumour? |
