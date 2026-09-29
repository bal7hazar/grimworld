# 04 — Combat

> Status: **Draft v0.4** — numbers are initial values for balancing. v0.4: the effects, their order and their edges are [19-effects](19-effects.md) (DES-04). v0.3: the edges of the damage rules (D-140), the flood stopped at 15 layers (D-127).
> v0.2: hex grid, six facings and arcs.

Combat happens only in dedicated instances and is resolved tick by tick
([02-core-loop](02-core-loop.md)). It is **fully deterministic** given the instance state
and the adventurer's action (pillar 5, D-40): there is no hit roll, no damage roll, no
random critical hit. Randomness is reserved for rewards.

## Actions

Each tick-consuming action advances the world by its **tick cost**.

| Action | Tick cost | Notes |
|---|---|---|
| Move | 1 | One tile, 6 directions. Sets facing to the direction moved |
| Turn | 0 | Change facing without moving; at most once between two ticks |
| Wait | 1 | Regenerate, let recharges run |
| Weapon attack | weapon speed | See weapons |
| Skill | activation (min 1) | Instant skills (activation 0) cost 0 tick and do not end the turn; at most one instant skill between two ticks |
| Use item | 1 | Potions |
| Pick up | 0 | Walking on loot picks it up |
| Interact | 1 | Gate, chest, lever |
| Swap weapon set | 1 | Post-MVP |

## Ranges

GW1 ranges are mapped to hex distances.

| Range | Tiles | Used by |
|---|---|---|
| Touch / adjacent | 1 | Melee, touch skills (6 tiles) |
| Nearby | 2 | Small area effects (18 tiles) |
| In the area | 3 | Large area effects (36 tiles) |
| Alert radius | 5 | Goblin perception ([18-rooms](18-rooms.md#what-goblins-perceive)) |
| Ranged | 6 | Bows, spells. Requires line of sight |
| Earshot | 8 | Shouts, pack alert propagation |

Line of sight uses a fixed integer hex line between the two tiles; walls block, actors do
not. When the line passes exactly between two tiles, the lower tile index is taken. This
function is not part of `origami_hexmap` and is ours to write.

## Weapons

| Weapon | Profession | Damage | Tick cost | Range | Note |
|---|---|---|---|---|---|
| Sword | Vanguard | 18 | 1 | 1 | Balanced |
| Axe | Vanguard | 17 | 1 | 1 | +25% from rear-side and back arcs |
| Maul | Vanguard | 27 | 2 | 1 | Slow, heavy |
| Bow | Warden | 21 | 2 | 6 | Line of sight |
| Staff / wand | Casters | 16 | 2 | 6 | Damage type by attribute |

Damage is the fixed midpoint of the GW1 range, at the maximum requirement. Requirement,
modifiers and armor pieces are defined in [15-equipment](15-equipment.md).

## Facing and arcs (D-41)

Since there is no roll, critical strikes are **earned by position and state**. Every
actor has a **facing**, one of the six directions, set when it moves, attacks, uses a
targeted skill or turns.

The six tiles around an actor facing direction `d` form four arcs:

```
        rear-side   front-side
              ╲       ╱
      back ──  actor  ──▶ front        actor facing East
              ╱       ╲
        rear-side   front-side
```

| Arc | Tiles | Attacker standing there gets |
|---|---|---|
| Front | `d` | Nothing; the defender can block |
| Front-side | `d ± 1` | Nothing; the defender can block |
| Rear-side | `d ± 2` | **Flank**: blocks and stances that block are ignored |
| Back | `d + 3` | **Critical**: ×1.4 damage, and blocks are ignored |

Other sources of critical strikes:

| Situation | Effect |
|---|---|
| Target is knocked down | Critical from any arc |
| Target is asleep | Critical from any arc; the first hit cannot be blocked |

Why this gives enough variety on hexes:

- An actor covers 3 of its 6 neighbours. Two attackers on opposite sides always put one in
  a rear arc: **being surrounded is dangerous by geometry**, for goblins and adventurers
  alike, without any numeric "outnumbered" rule.
- A wall or a corridor removes tiles from the rear arcs: **terrain is defence**. Fighting
  with your back to a wall is a real decision.
- Turning is free but limited to once per tick, so facing is a commitment against several
  foes: you choose who gets your back.
- Ranged attacks use the arc of the tile the line of sight arrives from.
- Knock-down, Crippled and the `flank` AI profile exist to manipulate arcs.

Reading facing on screen is an art constraint: see
[10-art-direction](10-art-direction.md#facing).

## Damage formula

As in GW1, armor mitigates exponentially: +40 armor halves damage.

```
damage = base × 2^((strength − armor) / 40)

strength (weapon attack) = 5 × attribute rank of the weapon, capped by level
strength (spell)         = 3 × caster level
armor                    = target armor + bonuses − penetration
```

Implementation constraint: `2^(x/40)` is read from a **lookup table** in fixed point for
`x ∈ [−160, +80]`; out-of-range values clamp. No floating point, no runtime
exponentiation, no `u256` ([CAIRO](../CAIRO.md)).

### Edges (D-140)

**A rule never panics on a legal action.** A played batch holds several actions and a
panic reverts all of them (design/02): whatever a player can reach has a defined result. A
panic is kept for an invariant whose breach is a bug.

| Edge | Rule |
|---|---|
| The table of `2^(x/40)` | 16 fractional bits, each entry rounded to nearest; generated once, for the contracts and for the client |
| Armor after bonuses and penetration | Never below 0: penetration removes armor, it does not add damage |
| Percent modifiers of damage (critical +40 %, weakness −33 %, flank and arc bonuses, modifiers of equipment) | **Summed, then applied once**, the result truncated. A critical strike by a weakened attacker deals 107 %, in whatever order the two were gained. The sum is never below −100 % |
| Damage of one hit | Between 0 and 65,535: a result outside is brought back to the nearest bound |
| A goblin whose own tile is not marked occupied | Cannot happen by the rules: the contracts assert it, and a test holds the invariant |

Damage types: slashing, piercing, blunt, fire, cold, lightning, earth, shadow, holy. Armor
can carry a bonus against a type. Life steal and degeneration ignore armor. The order of one
hit (arc, block, armor, damage, on-hit effects, death) is [19-effects §5.4–§5.5](19-effects.md#55-one-hit-in-order), which also says which rules
apply to weapon hits and which to spells, bombs and traps;
whether penetration is flat, as above, or a percent is FX-9.

## Energy and adrenaline

- Energy regenerates per tick by profession pips ([03-adventurer](03-adventurer.md)).
- Adrenaline is gained per weapon hit landed (1 strike) and per hit taken (¼ strike), and
  decays out of combat. Adrenaline skills have no energy cost and no recharge.

## Conditions

Conditions are fixed-effect debuffs with a duration in ticks. They do not stack; reapplying
refreshes the duration (how: [19-effects §5.7](19-effects.md#57-effects-applied-refreshed-replaced), FX-6; whether
Knocked down is refreshed or ignored while held is FX-31).
The MVP has the first five of design/09 (Bleeding, Poison, Burning, Crippled, Knocked down);
Dazed, Blind, Weakness and Deep wound come after it (19-effects §3.2, FX-22).

| Condition | Effect |
|---|---|
| Bleeding | −3 health pips |
| Poison | −4 health pips |
| Burning | −7 health pips |
| Crippled | Moving costs 2 ticks per tile |
| Dazed | Spells take +1 tick and are interrupted by any hit |
| Blind | Attacks miss unless the target is on the front tile |
| Weakness | −33% weapon damage |
| Deep wound | −20% max health, −20% healing received |
| Knocked down | Cannot act for the duration (2–3 ticks); does not stack with itself |

`Blind` is the one GW1 condition that was purely a hit roll; it is redefined above to stay
deterministic.

## Interrupts and activation

A skill with activation `n` resolves at the end of the `n`-th tick. Between the start and
the resolution, the caster is **activating** and visible as such: goblins can interrupt the
adventurer, and the adventurer can interrupt a telegraphed goblin skill. An interrupted
skill still pays its energy and goes on recharge. What interrupts, when an activation resolves
and what it keeps: [19-effects §5.1 and §5.9](19-effects.md#59-activation-and-interrupts) (FX-1 to FX-4, FX-29);
mining is not an activation ([19-effects §5.10](19-effects.md#510-mining-eng-01-41-design17)).

This is the main source of tactical depth of the tick system: a hobgoblin's 3-tick
overhead smash gives exactly three ticks to step away, interrupt or brace: three actions if
each costs one tick, fewer if one costs more ([19-effects §5.1](19-effects.md#51-the-clock-deadlines-and-counting)).

## Goblin AI

Goblins act after the adventurer's action, once per elapsed tick, in a fixed order (by
entity id). AI is a deterministic state machine.

```
Asleep ──noise/hit──▶ Alerted ──sees target──▶ Engaged ──condition──▶ Fleeing
   ▲                     │                        │                      │
   └──── lost target ────┴──────── Returning ◀────┴──────────────────────┘
```

| State | Behaviour |
|---|---|
| Asleep | Does nothing. Perception radius halved. **Costs no simulation** |
| Alerted | Moves toward the last known position of the target; alerts its pack |
| Engaged | Runs its caste profile ([05-bestiary](05-bestiary.md#ai-profiles)): position, then first usable skill in its priority list, else weapon attack |
| Fleeing | Moves away; returns to Engaged if cornered or healed |
| Returning | Walks back to spawn, regenerates, falls Asleep |

Determinism rules:

- Ties (equidistant tiles, equal-health allies) are broken by lowest entity id, then by
  lowest tile index, as the map library does. Never by a random draw.
- Pathfinding is one breadth-first flood from the adventurer per tick, on the window,
  shared by all awake goblins ([02-core-loop](02-core-loop.md#simulation-budget)). Each goblin steps to its
  free neighbour closest to the target; profiles that want distance (`kite`, `support`)
  step to the farthest.
- The flood stops at **15 layers** (D-127). A goblin with no way to the adventurer within
  15 steps **holds its position**: it does not move this tick, and still uses a ranged
  attack or a skill if it can. Terrain is defence: a wall that forces a long way round
  keeps melee goblins where they are.

## Death and defeat

See [02-core-loop](02-core-loop.md#ending-an-expedition-d-04). In short: an adventurer at 0
health is **defeated**: the instance is lost, and nothing else (D-04). Death is not
permanent in the default mode.
