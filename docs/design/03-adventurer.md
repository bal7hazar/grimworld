# 03 — Adventurer

> Status: **Draft v0.1** — numbers are initial values for balancing. Profession, attribute
> and skill names are working names; none may reuse a Guild Wars name for a skill, and no
> icon may be derived from Guild Wars assets.

## Identity

- An account may own several adventurers. An adventurer is a persistent on-chain entity
  with a name, a primary profession, a level, a guild rank, skills, inventory and a
  location.
- Primary profession is chosen at creation and is permanent. It defines armor class, base
  energy, energy regeneration and the **primary attribute**.
- A **secondary profession** is unlocked by a quest at Copper rank. It gives access to the
  skills and attributes of that profession, except its primary attribute.

## Base stats

| Stat | Formula | At level 20 |
|---|---|---|
| Health | `100 + 20 × (level − 1)` | 480 |
| Attribute points | `5 × (level − 1)` until 10, then more per level, **200 total at 20** | 200 |
| Energy | by profession | 20–30 |
| Energy regeneration | by profession, in pips | 2–4 pips |
| Armor | by profession armor class, scales with level | 60–80 |

**Pips.** Regeneration is expressed in pips, as in GW1, converted to ticks:

- 1 energy pip = 1 energy every 3 ticks. Stored on-chain in thirds of energy so that all
  math stays integer.
- 1 health pip = 2 health per tick. Health regeneration/degeneration is capped at ±10 pips.

## Professions (D-30)

Six professions form the core set. Three ship in the MVP (marked ●).

| | Profession | Archetype | Armor | Energy | Regen | Primary attribute (effect) |
|---|---|---|---|---|---|---|
| ● | **Vanguard** | Melee, adrenaline | 80 | 20 | 2 | *Might* — armor penetration on attack skills |
| ● | **Warden** | Bow, traps, preparation | 70 | 25 | 3 | *Fieldcraft* — reduces energy cost of Warden skills |
| ● | **Arcanist** | Elemental damage, area control | 60 | 30 | 4 | *Wellspring* — increases maximum energy |
| | **Cleric** | Healing, protection, smiting | 60 | 30 | 4 | *Grace* — bonus heal on every Cleric spell |
| | **Gravecaller** | Curses, life steal, minions | 60 | 30 | 4 | *Harvest* — gain energy when anything dies nearby |
| | **Beguiler** | Interrupts, energy denial, illusions | 60 | 30 | 4 | *Quickness* — reduces activation time of spells |

MVP choice rationale: the three MVP professions cover melee / ranged / caster, and each can
sustain itself solo. The Cleric is the first post-MVP profession because goblin shamans
already need most of its skills.

### Attributes

Each profession has one primary attribute and three or four secondary ones. Each skill is
linked to one attribute; the attribute's rank scales the skill's numbers.

| Profession | Attributes (primary first) |
|---|---|
| Vanguard | Might, Blades, Axes, Mauls, Tactics |
| Warden | Fieldcraft, Archery, Survival, Trapping |
| Arcanist | Wellspring, Fire, Frost, Storm, Stone |
| Cleric | Grace, Mending, Warding, Wrath |
| Gravecaller | Harvest, Blood, Curses, Bones |
| Beguiler | Quickness, Dominion, Delusion, Insight |

**Rank cost.** Ranks go from 0 to 12. Cost of each rank follows the GW1 curve:

| Rank | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Cost | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 9 | 11 | 13 | 16 | 20 |
| Cumulative | 1 | 3 | 6 | 10 | 15 | 21 | 28 | 37 | 48 | 61 | 77 | 97 |

With 200 points, a level 20 adventurer can reach 12/12/3 or 12/10/8: meaningful trade-offs.

Attributes can be **re-spent freely in hubs**, never in an instance.

## Skills

### The skill bar

- An adventurer **knows** any number of skills but **equips 8**.
- The bar and attributes are **locked when leaving a hub** and cannot change until back in
  a hub. The build is the main strategic decision of an expedition (pillar 2).
- At most **one elite skill** on the bar.

### Skill definition (registry entry)

```
Skill {
  id, name, profession, attribute,
  kind,            // see kinds below
  elite,           // bool
  cost_energy,     // 0, 5, 10, 15, 25
  cost_adrenaline, // strikes required, Vanguard-style skills
  activation,      // ticks spent casting; 0 = instant, does not end the turn
  recharge,        // ticks before reuse
  range,           // touch | adjacent | nearby | area | ranged
  target,          // self | foe | ally | tile
  effects[],       // list of (effect kind, base value, value at rank 12, duration)
}
```

Scaling between rank 0 and rank 12 is linear, as in GW1 ("12…41 damage").

### Skill kinds

| Kind | Rule |
|---|---|
| Attack | Replaces the next weapon attack; requires the matching weapon |
| Spell | Can be interrupted during activation |
| Hex | Negative spell that persists on a foe; removable |
| Enchantment | Positive spell that persists on an ally; removable |
| Stance | Instant, only one active at a time |
| Shout | Instant, cannot be interrupted |
| Signet | Costs no energy, long recharge |
| Preparation | Warden: modifies own attacks for a duration |
| Trap | Warden: placed on a tile, triggers when a foe enters |
| Glyph | Arcanist: modifies the next spell |

### Time conversion from the GW1 baseline (D-31)

We use GW1 numbers as a balance **baseline**, converted with one rule: **1 second = 1
tick**, rounded to the nearest integer, minimum 1 tick for anything with a non-zero
activation. Energy costs, damage and healing values are kept as-is and then tuned by
playtest.

| GW1 | Grim World |
|---|---|
| Activation ¾ s, 1 s | 1 tick |
| Activation 2 s, 3 s | 2, 3 ticks |
| Recharge 8 s | 8 ticks |
| Duration 10 s | 10 ticks |

### Acquiring skills

| Source | Skills |
|---|---|
| Profession trainer quests | The first ~8 skills of the primary profession (tutorial) |
| Trainers in hubs | Buy with gold; each hub's trainer sells a different set, which makes reaching new hubs matter |
| Quest rewards | Specific skills |
| **Capture** | Elite skills, taken from a boss that uses them — see below |

### Elite capture

Elite skills are never sold. To learn one, the adventurer equips a **Seal of Capture**
(working name) in one of the 8 slots, kills a boss that uses the elite skill, and uses the
seal on the corpse. The seal is replaced by the skill.

- Costs a slot for the whole expedition: capturing is a deliberate handicap.
- Elite-using bosses live in dungeons' last floors and in elite zones.
- Requires the adventurer to have the skill's profession as primary or secondary.

## MVP starter skills

Six per MVP profession, enough to teach every skill kind the profession uses. Format:
`energy / activation / recharge` in ticks; values are `rank 0…rank 12`.

### Vanguard

| Working name | Attribute | Kind | Cost | Effect |
|---|---|---|---|---|
| Cleave | Axes | Attack | 4 adrenaline | +10…30 damage |
| Rending Cut | Blades | Attack | 5 / – / 8 | Bleeding for 5…20 ticks |
| Skullring | Mauls | Attack | 6 adrenaline | Knock down for 2 ticks |
| Second Wind | Tactics | Skill | 5 / 1 / 20 | Heal 40…140, more if below 50% health |
| Brace | Tactics | Stance | 5 / 0 / 15 | Block the next 1…3 attacks |
| Warcry | Might | Shout | 5 / 0 / 20 | +armor penetration for 5…11 ticks |

### Warden

| Working name | Attribute | Kind | Cost | Effect |
|---|---|---|---|---|
| Aimed Shot | Archery | Attack | 10 / 1 / 6 | +10…25 damage |
| Hamstring Shot | Archery | Attack | 10 / 1 / 10 | Crippled for 3…12 ticks |
| Venom Coat | Survival | Preparation | 15 / 2 / 12 | Attacks apply Poison for 24 ticks |
| Snare | Trapping | Trap | 10 / 2 / 20 | Crippled + 10…40 damage to foes entering |
| Field Dressing | Survival | Skill | 5 / 1 / 15 | Heal 30…120, remove Bleeding |
| Sidestep | Fieldcraft | Stance | 5 / 0 / 20 | Evade melee attacks for 2…6 ticks |

### Arcanist

| Working name | Attribute | Kind | Cost | Effect |
|---|---|---|---|---|
| Ember Bolt | Fire | Spell | 5 / 1 / 2 | 15…60 fire damage |
| Cinder Ring | Fire | Spell | 15 / 2 / 12 | 20…80 fire damage to adjacent foes, Burning 1…3 ticks |
| Rime Shard | Frost | Spell | 5 / 1 / 4 | 10…50 cold damage, target moves 1 tile per 2 ticks for 2…5 ticks |
| Stone Skin | Stone | Enchantment | 10 / 1 / 20 | +armor for 8…20 ticks |
| Static Lash | Storm | Spell | 10 / 1 / 6 | 10…60 lightning damage, 25% armor penetration |
| Deep Draw | Wellspring | Glyph | 0 / 1 / 25 | Next spell costs 5…15 less energy |
