# 19 — Effects: the catalogue and the resolution order

> Status: **Draft v0.2** (DES-04, D-150). v0.2: fix loop 1 after the `[GPT-6-Astra]` audit (F-1 to
> F-13): complete enumerations, an entry format with its encoding, hit classes, guards' subject and
> time, a total order for refresh and replacement, the awake set and busy actors, mining as ENG-01
> froze it, traps in the order, bombs within the area bound, executable counters and decay, a state
> inventory against ENG-01 §3.2, examples in §10.
>
> The closed list of what a skill, a condition, an item, a modifier or a goblin can do to an
> instance, and the exact order in which a tick resolves it. CBT-01 freezes the combat interfaces
> from it; the contracts and the client's TypeScript mirror (SPK-4, D-140) follow it.
> **Rules marked ⟨FX-n⟩ are escalations** the design documents do not settle: the text states the
> recommendation, which stands only once the project manager has decided it (D-150). §9 groups
> them and marks those CBT-01 needs first. Everything else is read from design/02, 03, 04, 05, 07,
> 14, 15, 17, 18 and ENG-01, cited. No number here is a balance value: values are CNT-01's,
> DES-06's and BAL-01's.

## 1. Principles

| # | Principle | From |
|---|---|---|
| X-1 | **The catalogue is closed.** An effect kind, passive kind, skill kind, condition, shape, filter, guard or hit class not listed here does not exist. New content picks from the lists and fills values; anything else is a change of this document and of CBT-01's interfaces | Pillar 6, S-6 |
| X-2 | Content refers to every enumeration by its **id**, which never changes meaning once frozen by CBT-01. One `elements/` file per kind (CONTEXT §4) | CONTEXT §4 |
| X-3 | Every effect is an integer function of the state and its parameters: no draw, no block data, no floating point. Every division truncates **toward zero** | D-40, ADR-0002 |
| X-4 | **A rule never panics on a legal action** (D-140): every value is clamped or saturated to its field (§6); a counter never wraps (§5.12) | D-140 |
| X-5 | Percent modifiers of one quantity are **summed, then applied once**, the result truncated (D-140's rule for damage, applied to every percent) | D-140 |
| X-6 | Durations become deadlines on the instance clock (M-2), bounded by `grimworld_logic::durations` | D-02, ENG-01 §3.1 |
| X-7 | Iteration is by lowest entity id, then lowest tile index (`x + 256 y`). **One exception, stated where it applies: the actors of an area are taken in tile order** (§2.3) | COMMON §4, design/04 |

**Words.** A **carrier** holds effects: a skill (`SKILL`, 3 entries), a potion (`ITEM`, 1 entry), a
modifier (`MODIFIER`, a benefit and a cost), a set bonus (`ARMOR_SET`), a trap (a chunk object), a
condition, a primary attribute. The **source** is the actor whose carrier acts (member 0–7, or a
goblin; a terrain trap has none, §5.11); the **holder** is the actor an effect stays on, or the
actor wearing a passive. An **attack** is a weapon attack or an attack skill (design/03, kind
*Attack*). A **hit** is defined in §5.6. The **action phase** is the moment between two ticks where
the adventurer's action is applied (design/02).

## 2. The effect entry

### 2.1 Fields and encoding

Every carrier that acts writes its effects as **entries**; the entry is the unit CBT-01 freezes.
One entry is **98 bits**, so that it fits one 128-bit limb and three fit a `SKILL` record's two
parts (§7.2, F-11):

| Field | Bits | Values | Meaning |
|---|---:|---|---|
| `kind` | 8 | an id of §3 | — |
| `param` | 8 | by kind (§3's "param" column) | the condition, the damage type, the attribute… |
| `v0`, `v12` | 16 + 16 | **signed**, two's complement, −32,768…32,767 | the value at rank 0 and at rank 12 (§2.2) |
| `d0`, `d12` | 16 + 16 | 0…`MAX_BASE_DURATION` (43,688) | the **holding duration** at rank 0 and at rank 12, in ticks: how long the effect stays on its holder. 0 = the effect does not stay (instant) |
| `charges` | 8 | 0…63 | uses before the effect ends (a block, an oil); 0 = none. 63 is the goblin's field width (§7.2) |
| `target` | 2 | `SELF` 0, `FOE` 1, `ALLY` 2, `TILE` 3 | the addressing: where the shape is centred (§2.3). An ally is an **entity id** (M-5), the source itself included |
| `shape` | 4 | §2.3 | the tiles |
| `filter` | 2 | `FOES` 0, `ALLIES` 1 | which actors of the tiles the entry takes (§2.3) |
| `guard` | 4 | §2.4 | the entry applies only when its guard holds |
| `scope` | 2 | `WEAPON` 0, `ATTACK_SKILL` 1, `SPELL` 2, `ALL` 3 | for a kind that modifies hits: which hit classes (§5.4) |
| — | 2 | reserved, 0 | — |

**Entries with two durations.** A condition carried by a holding effect has two durations: how long
the carrier stays (`d0`, `d12`) and how long the condition it inflicts lasts. The second is the
**value** (`v0`, `v12`, which are non-negative for such kinds). Venom Coat: `ON_ATTACK_CONDITION`,
`param` Poison, `v0 = v12 = 24`, `d0`, `d12` the preparation's life. Rending Cut: `CONDITION`,
`param` Bleeding, `v0 = 5`, `v12 = 20`, `d0 = d12 = 0`. The duration of a condition is always its
entry's value; the holding duration is never a condition's.

**Legal combinations** are §3's table: each kind says which fields it reads; the others must be 0,
and the registry's content pipeline refuses an entry that sets a field its kind does not read, a
negative value where the kind says non-negative, or a value outside the kind's bounds.

### 2.2 Scaling

`value(rank) = v0 + (v12 − v0) × rank / 12`, in `i32`, the division truncating toward zero (X-3);
the same for durations. `|v12 − v0| ≤ 65,535` and `rank ≤ 15`, so the product fits `i32`. The rank
is the source's attribute rank of the skill's attribute: a member's from its snapshot (4 bits a bar
slot, 0–15, ENG-01 §3.2), a goblin's from its caste sheet (§7.3). A potion, a modifier and a
terrain trap do not scale: their entries have `v0 = v12`, `d0 = d12`.

**Ranks above 12** (runes reach about 16, design/15; the snapshot holds up to 15) ⟨FX-0b⟩: the
recommendation, after the audit, extrapolates the line up to 15 (the baseline scales beyond 12);
the writer then checks that `value(15)` still fits its field. The other option caps the rank at 12.

### 2.3 Addressing, shape, filter; which tiles and in which order

The **addressing** (`target`) says where the shape is centred: on the source (`SELF`), on a target
entity's tile (`FOE`, `ALLY`), on a target tile (`TILE`). The **filter** says which actors of the
shape's tiles the entry takes: the source's foes (members for a goblin, goblins for a member) or
its allies. There is no friendly fire and no "every actor" filter; a dead goblin (remains) is
neither a foe nor an ally.

| Id | Shape | Tiles | Count | Used by |
|---|---|---|---:|---|
| 1 | `SINGLE` | the centre | 1 | most skills, potions, traps |
| 2 | `RING_1` | the 6 tiles around the centre, **the centre excluded** | 6 | Cinder Ring (`SELF`: "adjacent foes", design/03) |
| 3 | `DISC_1` | the centre and its 6 neighbours | 7 | bombs (design/07), if their recipe says so; bound: FX-35 |
| 4 | `DISC_2` | the tiles within 2 of the centre, centre included | 19 | design/04's "small area effects": **no MVP source**; FX-21, FX-33 |
| 5 | `DISC_3` | the tiles within 3, centre included | 37 | design/04's "large area effects": **no MVP source**; FX-21, FX-33 |

design/04's ranges count 6, 18 and 36 tiles **around an actor** (its own tile excluded). An area
centred on a target must take the target, so the discs include their centre: 7, 19, 37 tiles.
Whether design/04's "18" and "36" meant rings or discs is FX-33.

- **Which tiles.** Walls hold no actor. **A tile outside the window is skipped** (clipped): the
  window is the board the tick is computed on (design/02), and a disc centred near its edge loses
  the tiles beyond it. For radius 1 no line of sight from the centre is asked (adjacent tiles see
  each other); for radius 2 and 3 it is FX-21.
- **In which order.** The actors of an area are taken in **ascending tile index** (the exception of
  X-7): one actor per tile. For each actor, the carrier's entries are applied in their order (1, 2,
  3) before the next actor: **target-major** ⟨FX-0⟩.
- **When the set is taken.** At the carrier's resolution, from the state at that moment ⟨FX-0⟩: a
  foe that stepped into a ring during an activation is hit, one that stepped out is not.
- A single target (`SINGLE` on an entity) is that entity if the filter takes it; an entity the
  filter refuses makes the action illegal at its start (§5.3), and does nothing at a resolution
  (§5.9).

### 2.4 Guards: subject and time

| Id | Guard | Holds when (strict, integers) | Used by |
|---|---|---|---|
| 0 | `ALWAYS` | — | most entries and passives |
| 1 | `ABOVE_HALF` | the subject's health × 2 > its max health | the inscription "+15 % damage while your health is above 50 %"; the kit's conditional damage and its threshold (design/15) |
| 2 | `BELOW_HALF` | the subject's health × 2 < its max health | Second Wind (FX-17) |
| 3 | `IN_STANCE` | the subject holds a stance (§3.4) | insignia "+10 armor while in a stance" |
| 4 | `ENCHANTED` | the subject holds an enchantment | insignia "+10 armor while enchanted" |

- **The subject** is the holder of the carrier. For a passive, the actor wearing it: the
  **defender** for an armor passive, the **attacker** for a damage passive. For a skill's or a
  potion's entry, the **source** (who casts or drinks). For a trap's entry, the trap's source; a
  terrain trap's entries carry no guard.
- **The time** is fixed once per carrier's use: **all the guards of one carrier are evaluated
  together, from the state before its first entry applies**. For a skill or a potion, at its
  resolution before entry 1, and for each target of an area, before that target's entries (the
  source's state is the same for all of them, since nothing of an area changes the source until the
  source-side step, §5.5 step 8). For a passive of a hit, at §5.5 step 3 (armor) and step 4
  (damage), before the damage is applied.
- So **Second Wind** (200 / 480 health, rank 12): its two guards are read at 200 (200 × 2 < 480):
  entry 1 heals 140 to 340, entry 2 (`BELOW_HALF`) still applies, although 340 × 2 > 480.
- Exactly 50 % holds neither `ABOVE_HALF` nor `BELOW_HALF`.

## 3. The catalogue: effects that act

Kinds are grouped; **P** marks a kind with no MVP source (catalogued for closure, its behaviour to be
completed before it ships). The "reads" column is the legal combination (§2.1): the fields the kind
reads besides `kind`, `target`, `shape`, `filter`, `guard`.

### 3.1 Health

| Id | Kind | Reads | Bounds | Rule |
|---|---|---|---|---|
| 1 | `DAMAGE` | `param` damage type; `v` base damage | 0…32,767 | a hit of the carrier's class (§5.4), resolved by §5.5 |
| 2 | `ATTACK_BONUS` | `v` added to the weapon's base damage | 0…32,767 | only in an attack skill: the attack's base is weapon damage (after its requirement, design/15) + this. Cleave, Aimed Shot |
| 3 | `HEAL` | `v` health | 0…32,767 | `health = min(max health, health + v)`; nothing on a dead actor. Deep wound (P) −20 % (X-5) |
| 4 | `LIFE_STEAL` | `v` health | 0…32,767 | ignores armor (design/04); the target loses `s = min(v, its health)` and the source heals `s`, capped at its max ⟨FX-0⟩ |
| 5 | `REGENERATION` | `v` pips; `d` | −10…+10 | a holding effect: its pips join the sum of step 3 (§5.8). Restoratives' "heal over time", draughts' "+health regeneration" (design/07) |

Damage types, ids in design/04's order: 1 slashing, 2 piercing, 3 blunt (physical), 4 fire, 5 cold,
6 lightning, 7 earth (elemental), 8 shadow, 9 holy (neither: FX-23).

### 3.2 Conditions

| Id | Kind | Reads | Rule |
|---|---|---|---|
| 6 | `CONDITION` | `param` condition; `v` its duration, 1…43,688 | applies or refreshes (§5.7); Knocked down: FX-31 |
| 7 | `CURE` | `param` condition | ends it now: a duration of 0 (§5.1). Field Dressing (Bleeding), restoratives' "remove a condition". Curing an absent condition does nothing |

Conditions, ids in ENG-01's storage order, then the ones after the MVP (design/04, design/09):

| Id | Condition | Effect | MVP | Stored |
|---|---|---|---|---|
| 1 | Bleeding | −3 health pips (step 3) | yes | `MemberTimers`, `GoblinTimers` |
| 2 | Poison | −4 health pips | yes | same |
| 3 | Burning | −7 health pips | yes | same |
| 4 | Crippled | a move costs 2 ticks per tile (a member's move action; a goblin: FX-15) | yes | same |
| 5 | Knocked down | cannot act (§5.2; FX-7); critical from any arc for a weapon hit (design/04); interrupts (§5.9); reapplied while held: FX-31 | yes | same |
| 6 | Dazed | spells take +1 tick; a hit interrupts a spell in activation | **P** | FX-22 |
| 7 | Blind | a weapon hit misses unless its target stands on the attacker's front tile | **P** | FX-22 |
| 8 | Weakness | −33 % to the holder's weapon hits (X-5) | **P** | FX-22 |
| 9 | Deep wound | −20 % max health, −20 % healing received | **P** | FX-22 |

### 3.3 Energy and adrenaline

| Id | Kind | Reads | Rule |
|---|---|---|---|
| 8 | `ENERGY` | `v` energy, −255…+255 | `energy = clamp(energy + v, 0, max)`, in thirds in storage (design/03). Restoratives' "restore energy"; a loss is Hexer's and Beguiler's energy denial (**P**) |
| 9 | `NEXT_SPELL_COST` | `v` energy, 0…255; `d` | a glyph (Deep Draw): consumed when the next spell **starts**, interrupted or not (§5.9); the cost never falls below 0 |

Adrenaline is changed by rules, not by entries (§5.12): gains on hits (§5.5 step 8), spending by
adrenaline skills, decay out of combat (§5.8).

### 3.4 Effects that stay on their holder

| Id | Kind | Reads | Rule | Sources |
|---|---|---|---|---|
| 10 | `ARMOR` | `v` armor 0…255; `d` | + armor while it lasts (§5.5 step 3) | Stone Skin; draughts' "+armor"; the Shaman's "shields" (FX-20) |
| 11 | `PENETRATION` | `v` percent 0…100 (FX-9); `d`; `scope` | + penetration on the holder's hits of its scope | Warcry (scope: FX-27) |
| 12 | `HIT_PENETRATION` | `v` percent 0…100 | penetration of **this carrier's** hits only (`d = 0`) | Static Lash (25 %) |
| 13 | `BLOCK` | `v` charges 1…63 (scaled); `d` | the holder blocks the next `v` weapon hits it can block (§5.6); ends at 0 charges or its deadline. The `charges` field is 0: the value is the charge count, since it scales | Brace |
| 14 | `EVADE` | `param` 1 melee; `d` | the holder evades melee weapon hits (range 1) while it lasts; arcs: FX-11 | Sidestep |
| 15 | `ON_ATTACK_CONDITION` | `param` condition; `v` the condition's duration; `d` **or** `charges` | each weapon hit of the holder applies the condition (§5.5 step 7); `charges` counts those hits | Venom Coat (`d`), oils "for N attacks" (`charges`, `d = 0`) |
| 16 | `MOVEMENT` | FX-18 | draughts' "+movement for N ticks" | design/07 |

**A holding effect with charges and `d = 0`** lasts until its charges are spent or the instance
closes: its deadline is set to `t₀ + MAX_DURATION − 1`, which `LAST_TICK` keeps below `MAX_CLOCK`
(ENG-01 §3.1). design/07 gives oils no time limit ("for N attacks").

**Skill kinds**, ids in design/03's order, and **`Skill`**, the generic kind of design/03's starter
tables (Second Wind, Field Dressing), which design/03's kinds table omits:

| Id | Skill kind | Rule | From |
|---|---|---|---|
| 1 | Attack | replaces the next weapon attack: the action is a weapon hit carrying the skill; needs the weapon of its attribute. Tick cost and landing: FX-5 | design/03 |
| 2 | Spell | can be interrupted during activation | design/03 |
| 3 | Hex | a spell that stays on a foe; removable (**P**: no removing kind has a source) | design/03 |
| 4 | Enchantment | a spell that stays on an ally; removable (**P**) | design/03 |
| 5 | Stance | instant, one at a time: a new stance ends the held one | design/03 |
| 6 | Shout | instant, cannot be interrupted, **alerts every pack within 8 tiles** (design/18: "a shout, or a fight, within 8 tiles") | design/03, design/18 |
| 7 | Signet | costs no energy, long recharge (**P**) | design/03 |
| 8 | Preparation | modifies the holder's own attacks for a duration | design/03 |
| 9 | Trap | placed on a tile, triggers when a foe enters (§5.11) | design/03 |
| 10 | Glyph | modifies the next spell | design/03 |
| 11 | `Skill` | FX-25: recommendation, interruptible as a spell, but not a spell (no Dazed, glyph, quick-cast) | design/03 starter tables |
| 12 | Seal of Capture | FX-26 (**P**) | design/03, *Elite capture* |

### 3.5 Control and placement

| Id | Kind | Reads | Rule | Sources |
|---|---|---|---|---|
| 17 | `INTERRUPT` | — | ends the target's activation in progress (§5.9) | **P**: Champion, Beguiler. In the MVP an interrupt is a knock-down (§5.9) |
| 18 | `TRAP` | — (the skill's other entries are the trap's) | places a trap on the target tile (§5.11); the entry's `target` is `TILE` | Snare; the Trapper (design/05) |

**No displacement exists**: no document names a push, a pull or a teleport; a knock-down does not
move its target. **No summon exists in the MVP** (FX-20).

### 3.6 Kinds after the MVP, catalogued for closure

| Id | Kind | Named by | What is missing |
|---|---|---|---|
| 19 | `REVIVE` | design/07: "revive once in the expedition" | FX-18: trigger, amount, the once-per-expedition state |
| 20 | `REVEAL_FLOOR` | design/07 | FX-18: the reveal bound |
| 21 | `ON_SKILL_USE` | design/05, Hexer: "punishes skill spam" | FX-32: its trigger and what it does. **A placeholder**, not a behaviour |
| 22 | `SUMMON` | design/05 (Lord), design/03 (Gravecaller) | FX-20: entity ids |
| 23 | `CAPTURE` | design/03, the Seal of Capture: used on the corpse of a boss that used an elite skill, the seal is replaced by the skill | FX-26 |
| — | Paladin "protects the lord", Beguiler "illusions" | design/05, design/03 | **not catalogued**: no document says what they do (FX-20) |

## 4. The catalogue: passive effects (modifiers, attributes, set bonuses, weapons)

Passive effects are read, never scheduled. **One id is one statistic.** Most are flattened into the
snapshot at entry (`MemberStats`, `MemberKit`, ENG-01 §3.2; equipment cannot change during an
expedition, design/15); the others are tested when they matter.

**A `MODIFIER` carries two passives**, a **benefit** and a **cost** (design/15, Q-4: "strong modifiers
have a condition or a cost"), each `(passive id u8, param u8, guard 4 bits, scope 2 bits, min i16,
max i16)`, 54 bits; the cost is fixed (`min = max`), the benefit's rolled value is the item's
`ItemMods` byte (0…255, design/15's ranges all fit). A modifier without a cost has cost id 0. Two
passives, 108 bits, fit `MODIFIER`'s one part (§7.2). An `ARMOR_SET` bonus is one passive.

| Id | Passive | Param; unit | When it acts | Sources |
|---|---|---|---|---|
| 40 | `MAX_HEALTH` | ± health | snapshot | Fortitude +30, insignias +15/10/5, runes +30…+50 and the costs −35/−75 (design/15) |
| 41 | `ARMOR` | ± armor; guard | snapshot, or at each hit when guarded | +4…+5; insignia +10 in a stance / enchanted; shield rating (design/15) |
| 42 | `ARMOR_VS` | damage type; + armor | at each hit of that type | +4…+7 against a type; the classes' innate +20 physical, +30 elemental (design/15). FX-23 |
| 43 | `MAX_ENERGY` | ± energy | snapshot | light armor's innate, Wellspring (design/03), the cost "−5 energy" (design/15) |
| 44 | `ENERGY_REGEN` | ± pips | snapshot | light armor's innate; energy-on-hit's cost (design/15) |
| 45 | `HEALTH_REGEN` | ± pips | snapshot, summed in step 3 | life steal's cost (design/15) |
| 46 | `DAMAGE_TYPE` | a damage type | snapshot | the damage type change (design/15); the staff "by attribute" (design/04) |
| 47 | `DAMAGE_PERCENT` | ± percent; guard; scope | at each hit of its scope (X-5) | "+15 % while health above 50 %", conditional damage +10…+15 %, "+15 % damage" with its cost (design/15). Scope: FX-27 |
| 48 | `PENETRATION` | percent; scope | at each hit of its scope | "+2…+4 %, always" (design/15, scope `WEAPON`); Might "on attack skills" (design/03, scope `ATTACK_SKILL`) |
| 49 | `LIFE_STEAL_ON_HIT` | health a hit | each weapon hit (kind 4's rule) | design/15 |
| 50 | `ENERGY_ON_HIT` | energy a hit | each weapon hit | design/15 |
| 51 | `CONDITION_DURATION` | a condition; percent | each such condition the holder inflicts (`effective_duration`, +50 % cap) | "Rending: bleeding you inflict lasts 33 % longer" |
| 52 | `ENCHANT_DURATION` | percent | each enchantment the holder casts | +10…+20 % |
| 53 | `KNOCKDOWN_FLAT` | + ticks | each knock-down the holder inflicts (flat, +3 cap) | *Hob-breaker*, 3 pieces |
| 54 | `ADRENALINE_EVERY_N` | N, 1…255 | the `hits` counter (§5.12) | "every 10th to 5th hit gives double adrenaline" |
| 55 | `QUICK_CAST_EVERY_N` | an attribute; N | the `casts` counter (§5.12) | "every 5th spell of the attribute costs 1 tick less" |
| 56 | `ATTRIBUTE` | an attribute; ± ranks | snapshot (the bar's ranks) | runes +1…+3; "only the highest rune of an attribute counts, every penalty counts" |
| 57 | `ENERGY_COST` | a profession; − energy | each skill start, never below 0 | Fieldcraft (design/03) |
| 58 | `HALVE_FIRST_HEAVY_HIT` | — | a weapon hit on the holder (FX-19) | *Hob-breaker*, 5 pieces |
| 59 | `BASE_DAMAGE_PERCENT` | percent of the weapon's base | snapshot | personalisation +20 % (design/15) |
| 60 | `RATING_PERCENT` | percent of a piece's rating | snapshot | personalisation +10 % (design/15) |
| 61–63 | `HEAL_BONUS`, `ACTIVATION_PERCENT`, `ENERGY_ON_DEATH` | — | **P** | Grace, Quickness, Harvest (design/03) |
| 64–65 | `CASTE_ARMOR`, `ATTACK_SPEED` | — | **P** | affixes *Scarred*, *Rabid* (design/05) |

**Weapons and arcs are rules, not entries** (design/04): the axe's +25 % from the rear-side and back,
the critical +40 %, flank ignoring blocks, the maul's 2 ticks, the bow's line of sight. A goblin's
weapon is its caste's.

## 5. The resolution order

### 5.1 The clock, deadlines and counting

design/02 runs a world tick in five steps; this document numbers them and adds step 0:

| Step | What | Order between actors |
|---|---|---|
| 0 | The clock advances, `clock = T`; the **awake set** of the tick is taken (§5.2) | — |
| 1 | Activations whose deadline is `T` resolve (§5.9) | ascending entity id: members (0–7), then awake goblins |
| 2 | Awake goblins act (design/04, *Goblin AI*) | ascending entity id; each sees the state the previous ones left |
| 3 | Regeneration, degeneration, adrenaline decay (§5.8) | members and awake goblins, ascending entity id; each actor's change depends only on its own state |
| 4 | Durations and recharges end (nothing is written: a deadline at or below the clock reads as ended) | — |
| 5 | Defeat and objective checks (§5.13); a `mine` action's check (§5.10) | — |

Between two ticks the clock reads `c`, the last tick run: the **action phase** is there.

**Counting.** A timer counts the executions of **the step that consumes it**, from the first one
after it is set ⟨FX-0, with FX-1 and FX-2⟩:

| Timer | Consumed by | Stored deadline | Active / due when |
|---|---|---|---|
| Holding effect or condition of `d` ticks | step 4 | `D = t₀ + d − 1`, `t₀` the first tick whose step 4 it meets: `c + 1` in the action phase, `T` in steps 1–3 of tick `T` | at any point of tick `T′ ≤ D`; in the action phase at clock `c < D` |
| Activation of `n` ticks | step 1 | `A = f + n − 1`, `f` the first tick whose step 1 comes after its start: `c + 1` in the action phase, `T + 1` if started in step 2 of `T` | resolves in step 1 of tick `A` |
| Recharge of `r` ticks | step 4, from the end of the activation (FX-2) | `R = t₀ + r − 1`, `t₀` taken where the activation ends (resolution, interruption, or use for an instant skill) | usable in the action phase at clock `c ≥ R`; by a goblin in step 2 of tick `T′ > R` |
| A goblin's recovery of `k − 1` ticks (FX-15) | step 2 | `B = T + k − 1` for an act of cost `k` in step 2 of `T` | it skips its act in step 2 of ticks `T′ ≤ B` |

So a condition of `d` ticks degenerates exactly `d` times, whether applied in the action phase or by
a goblin in step 2. A 1-tick spell of the adventurer resolves in step 1 of its action's first tick,
and goblins have `n − 1` steps 2 in which to interrupt an `n`-tick activation of the adventurer. A
goblin's 3-tick wind-up started in step 2 of tick `T` resolves in step 1 of `T + 3`: **three ticks**
run between (the action phases at clocks `T`, `T + 1`, `T + 2` are decision points only while each
action costs one tick; a 2-tick maul blow uses two of the three). An effect that "ends now" (a cure,
a spent block) takes a duration of 0: `D = t₀ − 1`, that is `c` in the action phase and `T − 1` in
tick `T`, so no later test finds it active. Deadlines stay below `MAX_CLOCK` by `LAST_TICK`.

### 5.2 The awake set and busy actors

- **The awake set is taken once, at step 0**, from the state then: the goblins in the window that
  are alive and not asleep, the 8 nearest to a member (M-3: the list of members; one in the MVP), by
  hex distance, ties by lowest entity id (design/02). It is **fixed for the tick**: a goblin that
  dies leaves it and **nothing refills it**; a goblin alerted during the tick joins from the next
  step 0. Only awake goblins resolve activations (step 1), act (step 2) and regenerate (step 3).
  **A goblin outside it is frozen** (design/02); its deadlines still pass on the instance clock, so
  a condition that ends while it is frozen is lost, not delayed (D-02) ⟨FX-0⟩.
- **An activation whose goblin is not awake at its deadline**: FX-29. Recommendation: it is
  **cancelled as an interrupt** in step 1 of tick `A` (costs stay paid, recharge from tick `A`),
  so no deadline is ever left overdue.
- **A busy goblin** (activating, or recovering, FX-15) does nothing in step 2: no move, no turn, no
  attack, no skill. It still takes hits and effects, and degenerates in step 3 if awake. A goblin
  whose activation resolves in step 1 has acted for that tick and does not act in step 2
  (design/04: "once per elapsed tick").
- **A member's activation lies inside its own action** (its `n` ticks are the action's; FX-3), so
  in solo a member has no action phase while activating. Co-op (several members) is not designed
  (design/08).
- **Acting while knocked down** is illegal (design/02); the knocked-down adventurer's only legal
  action is Wait (FX-7). A knocked-down goblin skips its act in step 2.

### 5.3 The adventurer's action

In the action phase, in this order (design/02, *Executing a batch*; design/04, *Actions*):

1. **Legality**, against the state as it is: design/02's list (tile blocked, out of range or of
   sight, not enough energy or adrenaline, recharging, a second turn or instant skill between two
   ticks, acting while knocked down, an item not in the belt), an attack skill without its weapon
   (design/03), a target the entry's filter refuses, a trap tile that cannot take one (§5.11). An
   illegal action is invalid: the batch stops, nothing of it runs.
2. **Costs** are paid at once ⟨FX-0⟩: energy after reductions (`ENERGY_COST`, a glyph, which is
   consumed), adrenaline. The `casts` counter moves if the skill counts (§5.12).
3. **Facing** is set (design/04): toward the moved-to tile, or the attack's or targeted skill's
   target; for a target not adjacent, the direction of the first step of the hex line to it ⟨FX-0⟩.
4. **Resolution now**: a move (a trap on the new tile triggers, §5.11), a weapon attack, an attack
   skill without activation (FX-5), a potion, an instant skill. **Or an activation starts**: a
   skill with activation `n ≥ 1` resolves in step 1 of its `n`-th tick (§5.1).
5. **Then `n` world ticks run**, `n` the action's tick cost (design/04; Crippled makes a move cost 2;
   an interrupt does not shorten it, FX-3). `mine` is its own pipeline (§5.10).

### 5.4 Hit classes and what applies to each

Every damaging entry, and every attack, has a **class**, fixed by its carrier:

| Class | Carriers |
|---|---|
| `WEAPON` | a weapon attack; an attack skill (then also `ATTACK_SKILL` for scopes) |
| `SPELL` | a damaging entry of any other skill kind (Spell, Hex, Enchantment, Shout, Signet, `Skill`…) |
| `ITEM` | a potion's damaging entry (a bomb) |
| `TRAP` | a trap's damaging entry, placed or terrain |

What applies to each class (✓ yes, — no):

| Rule | `WEAPON` | `SPELL` | `ITEM` | `TRAP` | From |
|---|:-:|:-:|:-:|:-:|---|
| Strength `5 × rank of the weapon's attribute` (capped by level) | ✓ | — | — | — | design/04 |
| Strength `3 × level` | — | ✓ | FX-28 | FX-28 | design/04 |
| Arcs: critical +40 % (back, knocked down, asleep), axe +25 % | ✓ | FX-27 | — | — | design/04 |
| Block, flank, evade (melee only), Blind's miss | ✓ | — | — | — | design/03, design/04 |
| Weakness −33 % | ✓ | — | — | — | design/04 ("weapon damage") |
| `DAMAGE_PERCENT`, `PENETRATION` (passive and held) | by scope | by scope | — | — | §2.1 `scope` |
| `HIT_PENETRATION` | its own carrier | its own carrier | — | — | — |
| Target's armor, `ARMOR` effects, `ARMOR_VS` | ✓ | ✓ | ✓ | ✓ | design/04 |
| Source's adrenaline +1 strike; the `hits` counter; `ENERGY_ON_HIT`, `LIFE_STEAL_ON_HIT`, `ON_ATTACK_CONDITION` | ✓ | — | — | — | design/04 ("weapon hit landed"), design/15 |
| Target's adrenaline +¼ strike; a hit for mining, Dazed, alerting | ✓ | ✓ | ✓ | ✓ | design/04, design/17; FX-10 |
| `HALVE_FIRST_HEAVY_HIT` | ✓ | — | — | — | design/15 ("the first attack", FX-19) |

### 5.5 One hit, in order

For one source, one target, one damaging entry or attack of class `K`:

1. **Arc** (design/04), if `K` takes arcs: the tile the source stands on or, at range, the tile the
   line of sight arrives from, in the target's arcs around its facing.
2. **Miss, block, evade** (§5.6), if `K` is `WEAPON`. A stopped attack applies **nothing else** (no
   damage, no effect, no adrenaline, not a hit).
3. **Armor** = the target's armor + `ARMOR` effects + guarded `ARMOR` passives (subject: the
   target) + `ARMOR_VS` of the damage type; then `armor − ⌊armor × p / 100⌋`, `p` the sum of the
   source's penetration percents that apply to `K` (capped at 100; FX-9); never below 0 (D-140).
4. **Damage** = `⌊base × table(strength − armor) / 2^16⌋`; then the **sum** of the percents that
   apply to `K` (critical, axe, Weakness, `DAMAGE_PERCENT` whose guard holds for the source; never
   below −100) applied once, truncated; clamped to [0, 65,535] (D-140); then FX-19's halving if the
   target holds it and `K` is `WEAPON`.
5. **Apply**: `health = health − damage`, saturated at 0. The hit is recorded (a mining member's
   flag, §5.10).
6. **The carrier's other entries on this target**, only if the target is above 0, in entry order.
7. **Target-side effects of a weapon hit**, only if the target is above 0: the source's
   `ON_ATTACK_CONDITION` effects (a charge spent each), `LIFE_STEAL_ON_HIT`, and the interrupt of a
   knock-down just applied (§5.9).
8. **Source-side**: for `WEAPON`, the source's adrenaline (§5.12), `ENERGY_ON_HIT`, the `hits`
   counter, for any hit (the target dead or not); for every class, the target's +¼ strike if alive.
9. **Death** of the target at 0 (§5.13). A goblin hit while asleep or on watch notices: its pack is
   engaged (design/18); a hit is also "a fight" alerting packs within 8 tiles.

An area runs 1–9 for each actor in tile order (§2.3); the source's side (step 8) accumulates in
that order, which fixes the counters.

### 5.6 Block, evasion, miss, and what a hit is

| Case | Result | From |
|---|---|---|
| The target holds `BLOCK` with charges, a weapon hit from its front or front-side arc | blocked; one charge spent | design/03, design/04 |
| Same, from the rear-side (flank) or the back | not blocked, **no charge spent** (the block is "ignored") | design/04 |
| The target holds `EVADE`, a melee weapon hit | evaded, from the front and front-side; from the rear-side and back: FX-11 | design/03 |
| The target is knocked down | FX-7: recommendation, it neither blocks nor evades | — |
| A spell, a bomb, a trap | never blocked, evaded or missed | design/03 names attacks |
| Blind (P) | a weapon hit misses unless the target is on the attacker's front tile | design/04 |
| The target is asleep | the first hit cannot be blocked (design/04); an asleep goblin holds no stance | design/04 |

**A hit** (FX-10) is an attack or a damaging entry, of any class, that reaches its target and is
not blocked, evaded or missed, whatever damage it deals (0 included). Degeneration and life steal
are not hits. A hit counts for the target's adrenaline, for Dazed (P), for mining (design/17: "any
hit taken") and for alerting.

### 5.7 Effects applied, refreshed, replaced

**Identity.** An effect held in a slot is identified by its **carrier**: a skill id, or a belt
potion (a belt slot, §7.2). A condition is identified by its id. The caster does not enter the
identity: two Shamans casting the same shield on one goblin hold one effect.

**Conditions.** Different conditions stack (each has its deadline; their pips are summed, §5.8).
The same condition does not stack: reapplying it refreshes (design/04): `D = max(D_old, D_new)`
(FX-6; conditions have no strength, so the deadline is all there is). Knocked down reapplied while
held: FX-31. A dead goblin takes nothing.

**Holding effects: one rule for every case.** When a carrier applies a holding effect to a holder:

1. **Same carrier already held** (in any slot): the new application is compared with the held one
   by deadline; **the one with the later deadline is kept whole** (its rank, its charges, its
   deadline); on equal deadlines the new one is kept (FX-30).
2. Else, **a stance** while a stance is held: it takes that stance's slot, whatever the deadlines
   (design/03: one stance at a time).
3. Else, the **lowest free slot**.
4. Else, **eviction**: the slot with the earliest deadline, ties by **lowest slot index** (FX-13).
   A goblin has one slot: the new effect replaces its effect (FX-13).

A slot holds the carrier, the source's rank at application (0–12, or the potion flag) and the
charges, so the effect's strength does not depend on its caster afterwards (the caster may die):
§7.2. Durations inflicted pass through `effective_duration(base, percent, flat)` (ENG-01 §3.1) with
the source's `CONDITION_DURATION`, `ENCHANT_DURATION`, `KNOCKDOWN_FLAT`.

### 5.8 Step 3: regeneration, degeneration, adrenaline decay

For each member and each awake goblin, ascending entity id:

1. **Health**: pips = the holder's regeneration (snapshot or caste) + its `REGENERATION` effects −
   3 (Bleeding) − 4 (Poison) − 7 (Burning), each counted once if active; the sum is **clamped to
   [−10, +10]** (design/03), then × 2 health; health clamped to [0, max].
2. **Energy**: + its regeneration in thirds (1 pip = 1 energy every 3 ticks, design/03), clamped
   to [0, max]. A goblin's energy is in thirds too (§7.2).
3. **Adrenaline decay** (FX-12): if the actor is **out of combat**, its adrenaline falls by the
   constant `ADRENALINE_DECAY` quarter strikes, floored at 0. Out of combat: for a member, no goblin
   of this tick's awake set is Engaged; for a goblin, it is not Engaged. Gains earlier in the tick
   were already added (and capped); decay comes after them.
4. An actor brought to 0 here dies (§5.13) after every actor of the step has been processed.

### 5.9 Activation and interrupts

- An activation resolves in step 1 of its deadline tick (§5.1, FX-1), members first, then awake
  goblins (§5.2). At resolution the target must still be legal (in range, in sight, taken by the
  filter, alive): if not, the skill does nothing and its costs stay paid ⟨FX-0⟩.
- **What interrupts**: `INTERRUPT` (P); **a knock-down** (design/14, *The brute at the bridge*:
  "interrupt its wind-up" with Skullring, a knock-down); a hit while Dazed, for a spell (P). A shout
  cannot be interrupted (design/03); instant skills have none. **Mining is not an activation**
  (§5.10).
- **An interrupted activation** (design/04): the energy stays paid, the skill goes on recharge from
  the interruption (FX-2), its effects do not happen, a glyph and a quick-cast bonus consumed at its
  start stay consumed (§5.12). Adrenaline: FX-4. The adventurer's remaining ticks run (FX-3); it
  does nothing in them.
- A goblin killed before its deadline never resolves its activation.

### 5.10 Mining (ENG-01 §4.1, design/17)

`mine` is sent alone (E-18) and is **not a skill**: no cost, no recharge, no activation deadline;
FX-3 and FX-4 do not apply to it. As ENG-01 froze it:

1. **Legality**: the member stands next to a vein not yet mined, the content version matches.
2. For `k = 1, 2, 3`: world tick `k` runs, steps 0–5. A hit taken by the member at any point of the
   tick (§5.5 step 5) sets its "hit this tick" flag.
3. **After step 5 of tick `k`**: if the flag is set, the action **stops**: the vein stays, no stone,
   no further tick runs (ENG-01: "ends the action after that tick"). Else if `k = 3`, **completion**:
   the vein's object is marked mined, the entropy is fed, one stillstone is credited. A defeat ends
   it as any tick does (§5.13).

A hit in step 2 of the third tick therefore stops it: three ticks **without a hit** complete it.

### 5.11 Traps

**Two object kinds** (ENG-01's chunk objects, kind 4 bits): the **terrain trap** of design/18 (kind
4, generated), and the **placed trap** (a new kind id, 9), each with its own `param` encoding (§7.2).

**Placing** (a `TRAP` entry, at the carrier's resolution): the tile must be walkable, hold no actor
and no object, and be in range; the trap takes the chunk's lowest object index that is empty or
holds a used trap (placed or terrain). Otherwise the skill is illegal at its start (a member) or
skipped by the AI (a goblin) (FX-14).

**Triggering.** A trap triggers when an actor **enters** its tile by a move: in the action phase
right after a member's move is applied, before the ticks; in step 2 right after a goblin's move, as
part of that goblin's act. It triggers if the entering actor is a foe of the trap's side (a placed
trap: its placer's foes; a terrain trap: FX-34, members only recommended), once:

1. The trap's **source** is its placer: a member (its snapshot's level and the bar slot's rank), a
   goblin (its record's caste and level, and the caste sheet's rank; a **dead** placer's record
   still holds them, so its trap stays live); a terrain trap has the location's values (FX-14,
   FX-28).
2. The skill's entries other than `TRAP` apply to the entering actor, in entry order, as a
   `SINGLE` target and class `TRAP` (§5.4, §5.5): no arc, no block.
3. The object is marked used. The entering actor's move stands; its cost was fixed before the
   trap (a Crippled just applied does not make the move that triggered it cost more, and a goblin's
   recovery for that move is decided before, FX-15).
4. A death follows §5.13; a goblin killed in its own step-2 move ends its act.

A placed trap never triggers on its own side; it lasts until triggered or the instance closes
(FX-14).

### 5.12 Counters and adrenaline

Every counter starts at 0 in a new instance (ENG-01 §2.1: the member's transient words are written
at every generation change) and never wraps (X-4):

| Counter | Where | Moves when | Rule |
|---|---|---|---|
| `hits` (u8) | `MemberState` | at §5.5 step 8 of each `WEAPON` hit by the member, if its `ADRENALINE_EVERY_N` is `N > 0` | `hits += 1`; if `hits = N`, **this** hit's adrenaline is doubled and `hits = 0`. It stays below `N ≤ 255`; with `N = 0` it stays 0 |
| `casts` (u8) | `MemberState` | at §5.3 step 2 when a spell of the kit's attribute **with activation ≥ 1** starts, if `QUICK_CAST_EVERY_N` is `N > 0` (FX-39) | `casts += 1`; if `casts = N`, **this** spell's activation is 1 tick less (never below 1) and `casts = 0`. An interruption after the start keeps the bonus spent |
| Adrenaline (quarter strikes) | `MemberState` (u16), `GoblinState` (u8) | + 4 per `WEAPON` hit landed by the actor (8 on a doubled one), + 1 per hit taken while alive; − cost when an adrenaline skill starts; decay in step 3 (§5.8) | each gain is capped at the actor's **cap** at once (FX-12: the highest adrenaline cost on its bar or caste, 0 if none), and never passes its field (a goblin: 255 quarters) |

### 5.13 Zero health, deaths, defeat

- **A goblin at 0 dies at once**, at the step of §5.5, §5.8 or §5.11 that brought it there: its AI
  state becomes dead (its record is its remains, ENG-01), it leaves the awake set without being
  replaced (§5.2), it no longer acts, takes effects or resolves an activation; its remains do not
  block movement ⟨FX-0⟩. `GoblinKilled` is emitted in resolution order; kill credit goes to the
  source's member through the contributors' function (M-4).
- **Simultaneous deaths** follow the resolution order: an area in tile order, step 3 in entity-id
  order. Nothing of the MVP reacts to a death (Harvest is **P**).
- **The adventurer at 0**: FX-8. Recommendation: in the action phase and in steps 1–2 (sequential),
  the moment a member's health reaches 0 it is defeated and the tick stops there; in step 3 the
  step completes for every actor first. Health at 0 is terminal. Step 5's defeat and objective
  finalisation always run for the tick that stopped: kills made before the stop count (D-04).

## 6. Edges (D-140)

Every case a player can reach, with its result. "Invalid" means the action is refused (design/02:
the batch stops there, no revert).

| Edge | Result |
|---|---|
| Energy cost after reductions below 0 | 0 |
| Activation after reductions below 1 for a non-instant skill | 1 (design/03, D-31) |
| A rank above 12 | FX-0b: extrapolated to 15 (recommended) or capped at 12 |
| Scaled value outside its kind's bounds | the writer refuses the entry (§2.1); at play, clamped to the kind's bounds |
| Effective duration | `effective_duration`'s caps, never above `MAX_DURATION` (ENG-01) |
| Heal above max health; energy above max; energy below 0 | clamped |
| Health pips beyond ±10 | clamped (design/03) |
| Armor below 0; penetration above 100 % | 0; 100 % |
| Percent sum below −100 | −100 (D-140): damage 0 |
| Damage outside [0, 65,535] | the nearest bound (D-140) |
| A 0-damage hit | still a hit (§5.6) |
| Life steal from a target with less health | the target's health (kind 4) |
| Curing a condition not held; anything on a dead goblin | nothing |
| Knocked down reapplied while held | FX-31 |
| The adventurer knocked down | only Wait is legal (FX-7) |
| A target illegal at resolution | nothing, costs paid (§5.9) |
| An area with no actor on its tiles | nothing; costs paid; a shout still alerts |
| An area near the window's edge | the tiles outside are skipped (§2.3) |
| A block at 0 charges | ended (§3.4) |
| A new stance while one is held; all slots full; equal deadlines | §5.7's order (FX-13, FX-30) |
| A goblin's activation while it is not awake | FX-29 |
| A trap on a full chunk, an occupied tile, a wall | invalid (FX-14) |
| Counters at `N`; adrenaline at its cap or field width | reset; capped (§5.12) |
| Two activations due in the same step 1 | entity-id order; a goblin killed by an earlier one does not resolve |
| A goblin whose own tile is not marked occupied | cannot happen (design/04): asserted |

## 7. What CBT-01 freezes

### 7.1 Enumerations and functions

- **Enumerations with stable ids**: effect kinds (§3, 1–23), passive kinds (§4, 40–65), conditions
  (1–9), damage types (1–9), skill kinds (§3.4, 1–12), shapes (1–5), targets, filters, guards
  (0–4), scopes, hit classes (§5.4), object kinds (terrain trap 4, placed trap 9).
- **The entry** of §2.1, in `SKILL` (3), `ITEM` (1, rank-free), and the two-passive `MODIFIER` (§4);
  `ARMOR_SET`'s two bonuses as passives.
- **The pipeline's functions**, pure, in §5's order: `apply_action`, `tick` (steps 0–5),
  `awake_set`, `resolve_hit`, `apply_entry`, `hold` (§5.7), `regenerate`, `interrupt`, `mine_tick`,
  `trigger_trap`, `kill`.

### 7.2 The state inventory against ENG-01 §3.2 (FX-24)

Every piece of state the rules above read or write, where it lives, and what it costs. **Free
bits** are the bits ENG-01's layouts leave below `LIVE` (bit 250); no field may straddle bit 128.

| Record (ENG-01) | Holds already | Needs (this document) | Where | Bits | Slots |
|---|---|---|---|---:|---:|
| `MemberState` (word 0) | health, energy (thirds), adrenaline (quarters), `hits`, `casts`, belt counts, flags 160–167 | flags: "hit this tick" (mining), `HALVE_FIRST_HEAVY_HIT` used | flags 160–167 (3 bits used today: turned, instant used, since the last tick) | 2 | 0 |
| `MemberTimers` | activation (slot, target, is-tile, deadline), 5 conditions | nothing more in the MVP; 4 post-MVP conditions | free 224–249 (26) | — | 0 (MVP); FX-22 |
| `MemberEffects` | 4 × (skill `u16`, charges `u8`, deadline 32 bits of which 28 used) | per slot: the source's **rank** (0–12) and the **potion flag** | the 4 unused deadline bits: 0–12 the rank, 15 "the skill field is a belt slot" (a potion does not scale) | 4 × 4 | 0 |
| `Recharges` | 8 deadlines | — | — | — | 0 |
| `MemberStats` | armor, vs physical, vs elemental, penetration, damage type… | armor against each damage type (FX-23): 9 × 6 bits, 0–63, replacing the two aggregates (16 bits) | 48–63 freed + 200–249 | 54 of 66 | 0 |
| `MemberKit` | conditional damage and its threshold, life steal, energy on hit, condition duration, enchant duration, double adrenaline N, quick cast N, health bonus | the condition of `CONDITION_DURATION` (4); the attribute of `QUICK_CAST_EVERY_N` (4); unguarded `DAMAGE_PERCENT` (8); `ARMOR` in a stance (8) and enchanted (8); scopes of the two damage percents (4); `KNOCKDOWN_FLAT` (2); `HALVE_FIRST_HEAVY_HIT` held (1) | free 208–249 (42) | 39 | 0 |
| `GoblinState` | health, energy (8 bits), adrenaline (8 bits), caste, level, flags 120–127, 4 recharges | **energy in thirds** (0–255: a caste's energy ≤ 85; §7.3); adrenaline in quarters (≤ 63 strikes) | the existing fields, units fixed | 0 | 0 |
| `GoblinTimers` | activation (slot, target, deadline), 5 conditions, one effect (skill, deadline) | the effect's **charges** (0–63) and **rank** (0–12); recovery (FX-15) | charges 6 + rank 4 in free 240–249; recovery as the activation slot's value 254 "recovering", its deadline `B` | 10 | 0 |
| Chunk object (`Features`) | tile 8, kind 4, state 4, param 16 | placed trap (kind 9): bit 15 = 0 member: member 3 bits, bar slot 3 bits; bit 15 = 1 goblin: entity id − 8 (12 bits, ≤ 3,600), caste skill index 2 bits. Terrain trap (kind 4): param = its `SKILL` id | the existing fields | 0 | 0 |
| `SKILL` (2 parts) | the fields of ENG-01 §3.5 | the header (profession 8, attribute 8, kind 8, elite 8, energy 8, adrenaline 8, activation 16, recharge 16, range 8, target 8: 96 bits) in part 0's low limb; entry 1 in part 0's high limb (98 ≤ 122); entries 2 and 3 in part 1's low and high limbs | not yet laid out (ENG-03 laid out five kinds) | — | 0 |
| `ITEM` (1 part) | class, region, rarity, value, book index, potion effect | the potion's entry (98 bits) + a range 8 bits for a thrown potion (FX-18) | its high limb (122) | 106 | 0 |
| `MODIFIER` (1 part) | slot, effect, value range, condition or cost | two passives (§4), 108 bits | its high limb | 108 | 0 |
| `CASTE` (2 parts) | tier, AI, health multiplier, armor, weapon, 4 skills, loot table, boss | §7.3's added fields (about 60 bits) | part 1 | — | 0 |
| `Action::Item` | belt slot 3–4, entity 5–20 | a tile flag (FX-18) | bit 21 of 24 | 1 | 0; wire format |
| Belt reserve through gates | the counts | revive's "used in this expedition" (**P**, FX-18) | with what carries through a gate (design/02, E-20) | 1 | FX-18 |

**Reads.** A tick reads the `SKILL` records of the effects it applies (the bar's 8, the awake
goblins' castes' 4 each, the held effects' carriers) and the potions' `ITEM`s: `bundle` takes at
most 32 records an invocation (`MAX_READ`, ENG-01 §3.5), about 72,000 L2 gas a 2-part record (D-145:
"reads limited to what a tick uses"). With the MVP's 5 castes: 8 + 20 + 4 = 32 at the worst,
exactly the bound; a sixth caste in one window passes it. **Recorded for ENG-07**, which measures
the tick's reads.

**Conclusion.** The MVP's rules fit ENG-01's words with **0 new slots**, with the packings above.
New slots come only after the MVP: the four conditions (FX-22), summons (FX-20), revive's state
(FX-18); a sixth caste in a window needs a second `bundle` call or a larger `MAX_READ`.

### 7.3 The caste sheet's shape (DES-06 fills the values)

| Field | Type | Notes |
|---|---|---|
| caste id, tier | `u16`, 1–6 | design/05 |
| AI profile | `swarm`, `kite`, `flank`, `support`, `brute`, `caster`, `boss` | design/05 |
| health multiplier | percent | on `100 + 20 × (level − 1)` (design/05) |
| armor; armor against each damage type | `u8`; 9 × 6 bits | FX-23 |
| weapon | a `BASE` id | damage, type, ticks, range |
| energy (≤ 85), energy regeneration | `u8`, pips | stored in thirds (§7.2) |
| 4 skills, **in priority order** | `SKILL` ids | design/04 |
| the rank of its skills | 0–15 | scales its entries (§2.2) |
| adrenaline cap | derived: its skills' highest cost | §5.12 |
| flee threshold | percent | `swarm`: 30 % (design/05) |
| loot table, boss flag | ids | ENG-01 `CASTE` |
| movement | tiles a move | **P**: Wolf rider (FX-20) |
| boss phases | health thresholds → skill sets | **P** |

## 8. Coverage: every source the documents name, and its kinds

| Source | Document | Kinds (§3, §4) |
|---|---|---|
| Cleave | design/03 | skill kind 1; 2 |
| Rending Cut | design/03 | 1; 6 (Bleeding, `v` 5…20) |
| Skullring | design/03 | 1; 6 (Knocked down, 2); interrupts (§5.9) |
| Second Wind | design/03 | skill kind 11 (`Skill`); 3, 3 guarded `BELOW_HALF` (§2.4, FX-17) |
| Brace | design/03 | 5; 13 |
| Warcry | design/03 | 6; 11 (alerts within 8) |
| Aimed Shot | design/03 | 1; 2 (FX-5) |
| Hamstring Shot | design/03 | 1; 6 (Crippled) |
| Venom Coat | design/03 | 8; 15 (Poison 24, holding `d`) |
| Snare | design/03 | 9; 18, 6 (Crippled), 1 (§5.11) |
| Field Dressing | design/03 | 11 (`Skill`); 3, 7 (Bleeding) |
| Sidestep | design/03 | 5; 14 (FX-11) |
| Ember Bolt | design/03 | 2; 1 (fire) |
| Cinder Ring | design/03 | 2; 1 (fire, `SELF`, `RING_1`, `FOES`), 6 (Burning) |
| Rime Shard | design/03 | 2; 1 (cold), 6 (Crippled: FX-16) |
| Stone Skin | design/03 | 4; 10 |
| Static Lash | design/03 | 2; 1 (lightning), 12 (25 %) |
| Deep Draw | design/03 | 10; 9 |
| Seal of Capture | design/03 | skill kind 12; 23 (**P**, FX-26) |
| Might, Fieldcraft, Wellspring | design/03 | 48 (`ATTACK_SKILL`), 57, 43 |
| Grace, Harvest, Quickness | design/03 | 61–63 (**P**) |
| The nine conditions | design/04, design/09 | §3.2 (6–9 **P**) |
| Arcs, critical, flank, axe, maul, bow, staff | design/04 | §5.4–§5.6; 46 |
| Adrenaline, energy, regeneration | design/04, design/03 | §5.8, §5.12 |
| Runt, Slinger | design/05 | weapon only (AI) |
| Skirmisher | design/05 | 6 (Bleeding) through its skills |
| Shaman | design/05 | 3 on allies; "shields": 10 (FX-20) |
| Hobgoblin | design/05, design/04 | an attack skill with activation 3 (FX-5), 1 |
| Trapper, Wolf rider, Hexer, Champion, Paladin, Lord | design/05 (**P**) | 18, 6; 6 (Knocked down), movement (FX-20); 21 (FX-32), 8; 5, 13/14, 17, adrenaline; 3, "protects" (FX-20); a shout to allies within 8 (FX-21), 22 |
| Affixes *Scarred*, *Rabid* | design/05 (**P**) | 64, 65 |
| Restoratives: heal over time, remove a condition, restore energy | design/07 | 5, 7, 8 |
| Draughts: +armor, +health regeneration, +movement | design/07 | 10, 5, 16 (FX-18) |
| Oils | design/07 | 15 (`charges`) |
| Bombs | design/07 | 1 or 6; `TILE`, `DISC_1` or `SINGLE`, `FOES` (FX-18, FX-35) |
| Rare: revive, reveal the floor | design/07 (**P**) | 19, 20 (FX-18) |
| Every modifier of design/15 | design/15 | §4: 40–60, benefit and cost |
| Insignias, runes, personalisation | design/15 | 40, 41 (guarded), 56, 59, 60 |
| *Hob-breaker* | design/15 | 53; 58 (FX-19) |
| Traps of the terrain | design/18 | object kind 4; §5.11 (FX-14, FX-34) |
| Veins | design/17, design/18 | §5.10 (not an effect: `mine`) |
| The Rift Heart | design/17 | a caste: its skills; no effect of its own |
| Shouts and fights alerting packs | design/18 | skill kind 6; §5.5 step 9 |
| Chests, remains, nodes, collectors, levers, braziers, landmarks | design/18, design/15 | **not effects**: Fate actions or objectives |

## 9. Escalations (open; the project manager decides, D-150)

Numbers are stable (FX-0 to FX-24 from v0.1; FX-25 onward from fix loop 1). Grouped so that they
can be decided in one pass. **★ = CBT-01 needs it before it freezes** (it changes a schema, a
field or the order of the pipeline); the others can follow with the content. The options, the
reasoning and the auditor's view are in the task's report; the recommendation is here.

**A. Time and activation** (★ all)

| # | Question | Recommendation |
|---|---|---|
| FX-0 ★ | The conventions marked ⟨FX-0⟩ (area order and set, costs at start, facing, life steal bound, target-side on the living, busy goblins, remains not blocking, frozen timers lapsing); **FX-0b** ranks above 12 | as written; ranks extrapolated to 15 |
| FX-1 ★ | An activation resolves in step 1 of its `n`-th tick (design/02) or at its end (design/04's words) | step 1 |
| FX-2 ★ | A recharge counts from the end of the activation, or from the use | the end of the activation |
| FX-3 ★ | The adventurer interrupted: do the action's remaining ticks run? | yes |
| FX-4 | An interrupted adrenaline skill's adrenaline | spent |
| FX-5 ★ | An attack skill's tick cost and landing | max(weapon, activation); at once without activation, at resolution with one |
| FX-15 ★ | A goblin's act that costs more than one tick (a 2-tick weapon, a crippled move) | it skips its next `k − 1` acts (recovery, stored), even if Crippled ends meanwhile |
| FX-29 ★ | A goblin's activation while it is not awake at its deadline | cancelled as an interrupt |
| FX-8 ★ | The adventurer at 0 mid-tick | §5.13 |

**B. Hits and damage**

| # | Question | Recommendation |
|---|---|---|
| FX-9 ★ | Penetration: flat or percent | percent, summed, capped at 100 |
| FX-10 | What is a hit | any class reaching its target unstopped, 0 damage included; traps included |
| FX-11 | Does flank ignore Sidestep's evasion? | **no** (changed): evasion holds from every arc |
| FX-19 | *Hob-breaker*'s halving | on the final damage of a weapon hit; predicate `2 h ≥ max` and `2 (h − damage) < max`; the flag spent only when it triggers |
| FX-27 ★ | Do spells take arcs and criticals; the scope of Warcry and of damage percents | no arcs for spells; Warcry and `DAMAGE_PERCENT` `WEAPON` unless the modifier says `ALL` |
| FX-28 ★ | The strength of a bomb and a trap | `3 × level` of the source (a terrain trap: its location's minimum level) |
| FX-23 ★ | Shadow and holy; armor against one type | neither class bonus; 9 × 6 bits per type, saturated at 63 |

**C. Held effects**

| # | Question | Recommendation |
|---|---|---|
| FX-6 ★ | Refresh of a condition | `max(old, new)` |
| FX-30 ★ | Refresh of a holding effect: which strength and charges survive | the application with the later deadline, whole; the new one on a tie |
| FX-13 ★ | Slots full; a goblin's single slot | earliest deadline, ties lowest slot; a goblin's is replaced |
| FX-31 ★ | Knocked down reapplied while held: refreshed like every condition, or not at all | not at all |
| FX-7 | Knocked down: legal actions; block and evasion | Wait only; neither blocks nor evades |

**D. Adrenaline and counters**

| # | Question | Recommendation |
|---|---|---|
| FX-12 ★ | Adrenaline's cap, "out of combat", decay | cap: highest cost on bar or caste (0 if none); out of combat as §5.8; decay in step 3 after gains, by a code constant `ADRENALINE_DECAY` until BAL-01 |
| FX-39 | Which spell takes the quick-cast bonus | the `N`-th spell of the attribute with activation ≥ 1, counted at its start; interrupted, the bonus stays spent |

**E. Areas, bombs, traps**

| # | Question | Recommendation |
|---|---|---|
| FX-14 ★ | Traps: terrain traps' content, lifetime, trigger, full chunk | a `SKILL` id per terrain trap; until triggered or the instance closes; once; invalid when full |
| FX-34 | Whom a terrain trap triggers on | members only |
| FX-35 ★ | A bomb's `DISC_1` hits up to 7 goblins; ENG-01 §9.2 budgets 6 beyond the awake 8 | raise the bound to 7 (+2 goblin words in the worst tick, about 64,000 L2 gas at O) |
| FX-33 | design/04's 18 and 36 tiles: rings or discs | discs with their centre (19, 37) for areas on a target |
| FX-21 | Areas of radius 2 and 3 | none in MVP content until ENG-01's bound is re-measured (19 or 37 goblins); line of sight from the centre |

**F. Content shape**

| # | Question | Recommendation |
|---|---|---|
| FX-25 ★ | The generic `Skill` kind's rules | interruptible like a spell; not a spell for Dazed, glyphs, quick cast |
| FX-16 | Rime Shard's slow is Crippled? | yes |
| FX-17 | Second Wind's "more" | a second `HEAL` guarded `BELOW_HALF`, read before either heal (§2.4) |
| FX-18 ★ | Potions: "+movement", revive, reveal, a bomb's target and range | §9's report entry; a tile flag in `Item`, a range in `ITEM`, line of sight required |
| FX-20 | Shaman "shields", Paladin, summons, Wolf rider | `ARMOR` for shields; the rest waits for its design |
| FX-26 | The Seal of Capture | post-MVP; a standalone action on remains |
| FX-32 | Hexer's "punishes skill spam" | waits for DES-06; kind 21 is a placeholder |

**G. Storage** (★ all)

| # | Question | Recommendation |
|---|---|---|
| FX-22 ★ | The four post-MVP conditions | **one more word per member and per goblin** when they ship (changed, after the audit) |
| FX-24 ★ | The inventory of §7.2 | accept: 0 new slots in the MVP |

## 10. Worked examples

The numbers are illustrative, not balance. Each example states what it assumes; with those inputs,
two implementations of §5 reach the states given.

### 10.1 An area kills two goblins at once

An Arcanist of level 20 with Fire 12 stands on (10, 10), facing East. Its kit has no damage
passive. Three goblins stand adjacent, each facing the Arcanist, each with armor 40, health
regeneration 0, no block, and no other goblin in the window, so all three are awake:
**57** on (10, 9) = tile 2,314 with health 90, **90** on (11, 10) = tile 2,571 with health 100, and
**24** on (10, 11) = tile 2,826 with health 200. The goblins attack in melee and do not move; the
Arcanist is not knocked down.

- **Action phase, clock 40**: Cinder Ring (15 / 2 / 12). 15 energy is paid at once, and the
  activation has `f = 41`, `A = 42`.
- **Tick 41**: step 2, goblins 24, 57, 90 attack in id order; none interrupts.
- **Tick 42, step 1**: the member resolves first. Its targets are the foes on `RING_1`, in tile
  order 2,314, 2,571, 2,826. The class is `SPELL`, so no arc applies (FX-27). Each goblin faces the
  Arcanist anyway, so a front arc would give no critical either.
  - The damage is `⌊80 × table(60 − 40) / 2^16⌋ = ⌊80 × 92,682 / 65,536⌋ = 113`.
  - **57**: 90 → 0, dies, and Burning is skipped. `GoblinKilled(57)`.
  - **90**: 100 → 0, dies. `GoblinKilled(90)`.
  - **24**: 200 → 87. Burning 3 ticks, `t₀ = 42`, `D = 44`.
  - The recharge of 12 gives `R = 53`.
  - Nothing refills the awake set: goblin 24 alone acts in step 2 of tick 42.
- **Step 3 of ticks 42, 43, 44**: goblin 24 takes −14 health each tick: 87 → 73 → 59 → 45.

### 10.2 An interrupt

A Hobgoblin, **entity 40**, has armor 70, health 400, and a smash that is an attack skill with
activation 3 and recharge 10; it is the only goblin. It starts the smash in **step 2 of tick 50**
and pays its energy, so `A = 51 + 3 − 1 = 53`. The adventurer is a Vanguard of level 20 with a maul
and Mauls 12, holding 24 quarter strikes, with no set bonus.

- **Action phase, clock 50**: the adventurer moves to the Hobgoblin's front tile (1 tick, tick 51).
- **Action phase, clock 51**: the adventurer uses Skullring (6 adrenaline, knock-down 2).
  - Under FX-5 the skill has no activation, so it lands at once. Its cost is the maul's, 2 ticks
    (52 and 53).
  - The adrenaline cost is paid first: 24 → 0.
  - The hit comes from the front arc, and the Hobgoblin holds no block.
  - The damage is `⌊27 × 55,109 / 65,536⌋ = 22`: 400 → 378.
  - Knocked down: `t₀ = 52`, `D = 53`. The knock-down interrupts the smash: its energy stays spent,
    and its recharge counts from `t₀ = 52`, so `R = 61`.
  - Source side: the adventurer gains 4 quarters, and the Hobgoblin +1.
- **Ticks 52, 53**: step 1 resolves nothing. The Hobgoblin is knocked down and skips its act.
- **Tick 54 onward**: it acts again. Its smash is usable in step 2 of ticks 62 and later.

The adventurer had three ticks, not necessarily three actions: here two actions (a 1-tick move and a
2-tick blow) used them.

### 10.3 A condition refreshed while ticking

The adventurer has health regeneration 0, max health 480, and health above 200 throughout. It is
Poisoned with `D = 72`. **Goblin 17** hits it with a weapon hit in **step 2 of tick 70** that
applies Bleeding 8, so `t₀ = 70`, `D = 77`.

- **Ticks 70–72**, step 3: −3 − 4 = −7 pips → −14 health a tick.
- **Ticks 73 and later**: −3 pips → −6.
- **Step 2 of tick 74**: Bleeding 8 again, so `D_new = 81` and `max(77, 81) = 81`. Step 3 of tick
  74 degenerates once.
- **Variant**, Bleeding 2 at tick 74: `D_new = 75`. `max` keeps 77, while replacing would give 75
  (FX-6).
- **Action phase, clock 75**: Field Dressing (`Skill`, 5 / 1 / 15), not interrupted. It resolves in
  step 1 of tick 76: Heal, then Cure, which gives `D = 76 − 1 = 75`. Step 3 of tick 76 has no
  Bleeding.
- **Total**: 3 × 14 + 3 × 6 = 60 health lost to degeneration, ticks 70–75.

### 10.4 Equal deadlines at eviction, and a stance replacing a stance

The member holds 4 effects, and no stance:

| Slot | Effect | Deadline |
|---:|---|---:|
| 0 | Stone Skin | 90 |
| 1 | Warcry | 85 |
| 2 | Venom Coat | 85 |
| 3 | a draught (potion flag) | 100 |

- **Action phase, clock 80**: Sidestep (a stance, `d` 6 at rank 12). It is not held, and no stance
  is held, so it needs a slot. There is no free slot. The earliest deadline is 85, in slots 1 and
  2, so the tie goes to the lowest slot. **Warcry is evicted.** Sidestep goes in slot 1 with
  `t₀ = 81`, `D = 86`.
- **Action phase, clock 82**: Brace (a stance). A stance is held (slot 1), so Brace takes slot 1
  whatever the deadlines. The other slots are untouched.

### 10.5 An activation that falls out of the awake set

Nine goblins are engaged. **Goblin 30** starts a 3-tick activation in step 2 of tick 100, so
`A = 103`. It is awake in ticks 101 and 102, busy in both, and does nothing in step 2. The
adventurer then walks so that, at step 0 of tick 103, goblin 30 is the ninth nearest.

- Under FX-29's recommendation, step 1 of tick 103 cancels the activation as an interrupt: the
  energy stays spent, and the recharge counts from `t₀ = 103`.
- Under the other options, the activation would either resolve at goblin 30's next awake step 1,
  with its target re-checked, or keep goblin 30 in the awake set.

### 10.6 The fifth cast, interrupted

The Arcanist's kit has `QUICK_CAST_EVERY_N`, Fire, `N = 5`, and `casts = 4`. The content holds a
Fire spell with activation 3 (illustrative).

- **Action phase, clock 200**: the spell starts.
  - `casts` goes 4 → 5 = `N`, so the activation is 2 and `casts` becomes 0.
  - `A = 201 + 2 − 1 = 202`.
- **Tick 201, step 2**: a goblin's weapon hit knocks the Arcanist down, which interrupts the spell.
  Energy stays paid, and the recharge counts from `t₀ = 201`.
- **Tick 202 still runs** (FX-3). The Arcanist does nothing in it.
- The bonus is spent: the next Fire spell makes `casts` 1.
