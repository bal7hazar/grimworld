# 05 — Bestiary

> Status: **Draft v0.1** — numbers are initial values for balancing, not commitments.

## Principle

Every enemy is a goblin (pillar 3). A goblin is defined by:

```
Goblin = Caste × Level × (optional) Affix
```

- **Caste** defines role, skill list, AI profile and threat tier.
- **Level** scales health, armor and damage inside the caste's allowed range.
- **Affix** (post-MVP) is a modifier for elite zones, e.g. *Scarred* (+armor), *Rabid*
  (+attack speed).

A player reading a pack should be able to assess danger at a glance from the castes in it.

## Castes

Threat tier is the guild's official classification and drives quest rank requirements.

| Tier | Caste | Role | Profession analogue | Signature behaviour |
|---|---|---|---|---|
| 1 | **Runt** | Fodder melee | — | Swarms, flees when alone and hurt |
| 1 | **Slinger** | Fodder ranged | Warden | Keeps distance, targets lowest armor |
| 2 | **Skirmisher** | Melee | Vanguard | Flanks, applies Bleeding |
| 2 | **Trapper** | Control | Warden | Places traps on chokepoints, applies Crippled |
| 3 | **Shaman** | Support caster | Cleric / Arcanist | Heals and shields the pack, flees melee. Kill first |
| 3 | **Wolf rider** | Fast melee | Vanguard | Moves 2 tiles per tick, knocks down |
| 4 | **Hobgoblin** | Brute | Vanguard | High health, heavy hits with wind-up (telegraphed) |
| 4 | **Hexer** | Offensive caster | Gravecaller / Beguiler | Hexes, energy denial, punishes skill spam |
| 5 | **Champion** | Elite duelist | Vanguard | Uses stances, interrupts, adrenaline skills |
| 6 | **Paladin** | Elite hybrid | Vanguard / Cleric | Heavy armor, self-heal, protects the lord |
| 6 | **Lord** | Boss | any | Commands: buffs the pack, calls reinforcements |

Notes:

- Goblins use the **same skill system as adventurers** (as GW1 monsters do). A caste's skill
  list is a registry entry pointing to skill ids. This gives us enemy variety for free as
  the skill pool grows, and is what makes elite skill capture possible. What a skill can do is
  [19-effects](19-effects.md); the shape of a caste's sheet is its §7.3, and every caste's sheet,
  with its initial values, skills and priority list, is [20-castes](20-castes.md).
- Castes 5–6 only appear as dungeon bosses, in elite zones, or in rank trials.

## Level ranges and scaling

| Tier | Level range | Appears from guild rank |
|---|---|---|
| 1 | 1–6 | Wood |
| 2 | 3–10 | Wood |
| 3 | 6–14 | Tin |
| 4 | 10–20 | Copper |
| 5 | 16–24 | Bronze |
| 6 | 20–28 | Silver |

Goblin stats use the same formulas as adventurers ([04-combat](04-combat.md)) with a caste
multiplier on health and a caste armor value. Goblins above level 20 are how elite content
stays threatening to capped adventurers.

## Packs

Goblins spawn in **packs**, never alone (except bosses and scouts). A pack is a registry
entry: a list of `(caste, count range)` and a level offset.

| Pack | Composition | Tier |
|---|---|---|
| Rabble | 3–5 Runt | 1 |
| Raiders | 2–3 Runt, 1–2 Slinger | 1 |
| Warband | 2 Skirmisher, 1 Slinger, 1 Shaman | 3 |
| Hunting party | 2 Wolf rider, 1 Trapper | 3 |
| Hob guard | 1 Hobgoblin, 2 Skirmisher, 1 Shaman | 4 |
| Coven | 2 Hexer, 1 Shaman, 2 Runt | 4 |
| Lord's retinue | 1 Lord, 1 Paladin, 1 Champion, 2 Shaman | 6 |

Pack rules:

- A pack shares aggro: alerting one member alerts all.
- Pack size is capped so that **at most 8 goblins are awake** around the adventurer at
  any tick (technical budget, see [02-core-loop](02-core-loop.md#simulation-budget)).

## AI profiles

AI is fully deterministic given the instance state (pillar 5). Each caste references one
profile; details of the state machine are in [04-combat](04-combat.md#goblin-ai).

| Profile | Summary |
|---|---|
| `swarm` | Close distance, attack nearest. Flee if last of pack and health < 30% |
| `kite` | Stay at max range, step back if adjacent |
| `flank` | Prefer tiles behind or beside the target |
| `support` | Heal lowest-health ally, keep ≥ 3 tiles from the adventurer |
| `brute` | Walk straight, use telegraphed heavy attacks |
| `caster` | Keep range, use skills by priority list, never melee |
| `boss` | Scripted phases by health thresholds |

## Drops

Each caste has a loot table of ingredients (see
[07-loot-and-alchemy](07-loot-and-alchemy.md)). Higher tiers drop rarer ingredients; bosses
have a guaranteed drop.
