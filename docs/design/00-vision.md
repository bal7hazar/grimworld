# 00 — Vision

> Status: **Draft v0.1** — consolidated from the owner's ideation. Every numbered decision
> (`D-xx`) is a proposal by the orchestrator until the owner confirms it. Open questions
> are tracked as `Q-xx` in [CONTEXT.md](../../CONTEXT.md#7-open-questions).

## One-liner

**Grim World** is a fully on-chain, tick-based heroic-fantasy RPG where guild-ranked
adventurers leave shared towns to clear goblin-infested wilds alone, in instances where
*the world only moves when you do*.

## Inspirations and what we take from each

| Inspiration | What we take | What we leave |
|---|---|---|
| **Guild Wars 1 (pre-Searing)** | Shared towns/outposts + dedicated instances outside. Low level cap, build-driven power. 8-slot skill bar locked before leaving town. Attribute system. Skill balance as a numeric baseline. Elite areas. Map that grows by adding regions. | Real-time combat, names, icons, lore. 3D. |
| **Goblin Slayer** | One enemy family (goblins) whose *caste* defines difficulty. Adventurer ranks earned through quests and gating new quests. A grim, low-fantasy tone where goblins are a real threat. | Characters, names, plot. |
| **Pixel Dungeon / [Grimscape](https://github.com/bal7hazar/grimscape)** | Player-driven tick: in a dedicated instance the world is static until the player acts. Tiles, fog, sleeping mobs. | Permadeath as the default. Single endless dungeon. |
| **[Athanor](https://github.com/djizus/athanor)** | Probabilistic crafting of potions from ingredients dropped by mobs. | — |

## Design pillars

Pillars arbitrate every design disagreement. When two options conflict, the one serving the
higher pillar wins.

1. **The world waits for you.** In dedicated instances, time is a resource the player
   spends. No action, no tick. Every design choice must preserve this.
2. **Build over grind.** Power comes from the choice of 8 skills and attribute spread, not
   from hours played. The level cap is low and reached early; the long game is rank, skills
   and mastery.
3. **One enemy, many faces.** Goblins only. Variety comes from castes, group composition and
   terrain, not from a bestiary of unrelated creatures.
4. **Fully on-chain, no asterisk.** Game rules and state that matter live in contracts.
   Anything off-chain must be either cosmetic or reproducible from chain state.
5. **Deterministic tactics, random rewards.** What you *do* resolves predictably; what you
   *get* is decided by fate. (This pillar is also what makes optimistic rendering viable —
   see [ADR-0001](../architecture/ADR-0001-execution-layer.md).)
6. **Content scales horizontally.** New towns, zones, castes, skills and quests are data
   added to registries, not rewrites of core systems.

## Player fantasy

You are a freshly registered adventurer of the Guild, the lowest rank there is. Goblins are
considered vermin by veterans and a death sentence by the villagers they raid. You take
contracts from the guild board, walk out of the gate alone, and come back richer, wiser — or
carried.

## Core loops

```
Moment-to-moment (seconds)     tick: observe → choose action → world reacts
Expedition (5–20 minutes)      town: pick quest + build → instance → return or fall → rewards
Career (weeks)                 rank up → new quests/zones/skills → elite zones → new regions
```

## Target experience

- **Session length**: an expedition is completable in 5–20 minutes; can be paused at any
  time for free since the world waits.
- **Platform**: **mobile first** (iOS and Android, portrait), desktop web second. Input is
  one tap per action.
- **Audience**: on-chain gamers first; the game must nevertheless be understandable by
  someone who has played any roguelike or GW1.

## Non-goals for v1

- Cooperative play and PvP (the door stays open, see [08-multiplayer](08-multiplayer.md)).
- Hidden information on-chain (the chain is public; we design around it, not against it).
- Real-time combat.
- A token economy. Tradability and tokenization are deferred (Q-07).

## Document map

| Doc | Content |
|---|---|
| [01-world](01-world.md) | Lore frame, regions, location types, horizontal scaling |
| [02-core-loop](02-core-loop.md) | Tick, instances, expedition lifecycle, map |
| [03-adventurer](03-adventurer.md) | Professions, attributes, skills, builds |
| [04-combat](04-combat.md) | Actions, ranges, damage, conditions, mob AI |
| [05-bestiary](05-bestiary.md) | Goblin castes and packs |
| [06-guild](06-guild.md) | Ranks, quests, promotion trials |
| [07-loot-and-alchemy](07-loot-and-alchemy.md) | Drops, ingredients, probabilistic crafting |
| [08-multiplayer](08-multiplayer.md) | Shared spaces now, co-op later |
| [09-mvp-scope](09-mvp-scope.md) | What ships first |
| [10-art-direction](10-art-direction.md) | Pixel art, asset pack, constraints |
