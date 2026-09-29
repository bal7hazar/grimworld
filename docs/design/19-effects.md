# 19 — Effects: the catalogue and the resolution order

> Status: **Draft v0.3** (DES-04, D-150). v0.3: fix loop 2 after the re-audit: the entry's bits
> recounted (97) and a signed range for durations carried as values; empty entries; one guard
> snapshot per carrier; perception and the awake set; lazy cancellation of frozen activations;
> activation and recovery in one field; a lossless state inventory with ranks 0–15; charge-only
> effects without a time limit; **one executor for every carrier** (§5.14) and the legal
> combinations; the registry reads as the true request union. v0.2: fix loop 1 (F-1 to F-13).
>
> The closed list of what a skill, a condition, an item, a modifier or a goblin can do to an
> instance, and the exact order in which a tick resolves it. CBT-01 freezes the combat interfaces
> from it; the contracts and the client's TypeScript mirror (SPK-4, D-140) follow it.
> **Rules marked ⟨FX-n⟩ are escalations** the design documents do not settle: the text states the
> recommendation, which stands only once the project manager has decided it (D-150). §9 groups
> them and marks those CBT-01 needs first. Everything else is read from design/02, 03, 04, 05, 07,
> 14, 15, 17, 18 and ENG-01, cited. No number here is a balance value.

## 1. Principles

| # | Principle | From |
|---|---|---|
| X-1 | **The catalogue is closed.** An effect kind, passive kind, skill kind, condition, shape, filter, guard, scope or hit class not listed here does not exist; nor does an entry combination §5.14 does not allow | Pillar 6, S-6 |
| X-2 | Content refers to every enumeration by its **id**, which never changes meaning once frozen by CBT-01. One `elements/` file per kind (CONTEXT §4) | CONTEXT §4 |
| X-3 | Every effect is an integer function of the state and its parameters: no draw, no block data, no floating point. Every division truncates **toward zero**; a subtraction that could fall below 0 saturates (`a ⊖ b = a − min(a, b)`) | D-40, ADR-0002 |
| X-4 | **A rule never panics on a legal action** (D-140): every value is clamped or saturated to its field (§6); a counter never wraps (§5.12) | D-140 |
| X-5 | Percent modifiers of one quantity are **summed, then applied once**, the result truncated | D-140 |
| X-6 | Durations become deadlines on the instance clock (M-2), bounded by `grimworld_logic::durations` | D-02, ENG-01 §3.1 |
| X-7 | Iteration is by lowest entity id, then lowest tile index (`x + 256 y`). **One exception: the actors of a carrier are taken in tile order** (§5.14) | COMMON §4, design/04 |

**Words.** A **carrier** holds effects: a skill (`SKILL`, up to 3 entries), a potion (`ITEM`, 1
entry), a modifier (`MODIFIER`, a benefit and a cost), a set bonus (`ARMOR_SET`), a trap (a chunk
object), a condition, a primary attribute. The **source** is the actor whose carrier acts (member
0–7, or a goblin; a terrain trap has none, §5.11); the **holder** is the actor an effect stays on,
or the actor wearing a passive. An **attack** is a weapon attack or an attack skill (design/03). A
**hit** is defined in §5.6. The **action phase** is the moment between two ticks where the
adventurer's action is applied (design/02).

## 2. The effect entry

### 2.1 Fields and encoding

Every carrier that acts writes its effects as **entries**; the entry is the unit CBT-01 freezes.

| Field | Bits | Encoding and range | Meaning |
|---|---:|---|---|
| `kind` | 8 | 0 = **empty entry**; else an id of §3 | — |
| `param` | 8 | 0–255, by kind (§3's "reads") | the condition, damage type, attribute… |
| `v0`, `v12` | 16 + 16 | **signed**, two's complement, −32,768…32,767 | the value at rank 0 and at rank 12 (§2.2) |
| `d0`, `d12` | 16 + 16 | unsigned, 0…43,688 (`MAX_BASE_DURATION`) | the **holding duration** at rank 0 and 12: how long the effect stays on its holder; 0 = it does not stay |
| `charges` | 6 | unsigned, 0…63 | uses before the effect ends (an oil); 0 = none |
| `target` | 2 | `SELF` 0, `FOE` 1, `ALLY` 2, `TILE` 3 | the addressing: where the shape is centred (§2.3); an ally is an **entity id** (M-5), the source included |
| `shape` | 3 | 1–5 (§2.3); 0 refused | the tiles |
| `filter` | 1 | `FOES` 0, `ALLIES` 1 | which actors of those tiles |
| `guard` | 3 | 0–4 (§2.4) | the entry applies only when its guard holds |
| `scope` | 2 | `WEAPON` 0, `ATTACK_SKILL` 1, `SPELL` 2, `ALL` 3 | for a kind that modifies hits (§5.4) |
| **Total** | **97** | 8 + 8 + 16 + 16 + 16 + 16 + 6 + 2 + 3 + 1 + 3 + 2 | fits one limb (≤ 122 or 128 bits, §7.2) |

- **Empty entries.** An entry of `kind` 0 has every field 0. A carrier's entries are packed from
  entry 1 without a gap: if entry `k` is empty, every later entry is empty. The **entry count** is
  the index of the last non-empty entry (0 to 3). The content pipeline refuses a gap and a non-zero
  field in an empty entry.
- **Durations carried as values.** A condition's duration is its entry's **value**: `CONDITION`
  (`v` = the condition's duration), `ON_ATTACK_CONDITION` (`v` = the condition's duration inflicted
  at each hit; `d` = how long the preparation stays). The value is signed, so **a duration carried
  as a value is bounded to 1…32,767 ticks** (below `MAX_BASE_DURATION`, 43,688); the pipeline
  refuses more. Venom Coat: `ON_ATTACK_CONDITION`, `param` Poison, `v0 = v12 = 24`, `d` its life.
  Rending Cut: `CONDITION`, `param` Bleeding, `v0 = 5`, `v12 = 20`, `d = 0`.
- **Legal combinations** are §3's "reads" column (fields a kind does not read must be 0) and
  §5.14's rules for carriers. The content pipeline refuses the rest.

### 2.2 Scaling

`value(rank) = v0 + (v12 − v0) × rank / 12`, in `i32`, truncating toward zero; the same for
durations. `|v12 − v0| ≤ 65,535` and `rank ≤ 15`, so the product (≤ 983,025) fits `i32`. The rank
is the source's rank in the skill's attribute: a member's from its snapshot (4 bits a bar slot,
0–15), a goblin's from its caste sheet (§7.3). Potions, modifiers and terrain traps do not scale
(`v0 = v12`, `d0 = d12`).

**Ranks 13–15** ⟨FX-0b⟩: the recommendation extrapolates the line up to 15 (the baseline scales
beyond 12). The content pipeline then checks `value(15)` and `value(0)` against the kind's bounds,
and every rank 0–15 is stored losslessly (§7.2). The other option caps the rank at 12.

### 2.3 Addressing, shape, filter

The **addressing** (`target`) says where the shape is centred: on the source (`SELF`), on a target
entity's tile (`FOE`, `ALLY`), on a target tile (`TILE`). The **filter** says which actors of the
shape's tiles the entry takes: the source's foes (members for a goblin, goblins for a member) or its
allies. There is no friendly fire; a dead goblin is neither.

| Id | Shape | Tiles | Count | Used by |
|---|---|---|---:|---|
| 1 | `SINGLE` | the centre | 1 | most skills, potions, traps |
| 2 | `RING_1` | the 6 tiles around the centre, centre excluded | 6 | Cinder Ring (`SELF`, "adjacent foes", design/03) |
| 3 | `DISC_1` | the centre and its 6 neighbours | 7 | bombs (design/07) if their recipe says so; FX-35 |
| 4 | `DISC_2` | within 2 of the centre, centre included | 19 | design/04's small areas: **no MVP source**; FX-21, FX-33 |
| 5 | `DISC_3` | within 3, centre included | 37 | design/04's large areas: **no MVP source**; FX-21, FX-33 |

A tile outside the window is skipped (the window is the board of the tick, design/02); walls hold no
actor; radius 1 needs no line of sight from the centre, radius 2 and 3 is FX-21. How the actors of
all a carrier's entries are ordered and when they are taken is §5.14.

### 2.4 Guards: subject and time

| Id | Guard | Holds when (strict, integers) | Used by |
|---|---|---|---|
| 0 | `ALWAYS` | — | most |
| 1 | `ABOVE_HALF` | the subject's health × 2 > its max health | "+15 % damage while your health is above 50 %" (design/15) |
| 2 | `BELOW_HALF` | the subject's health × 2 < its max health | Second Wind (FX-17) |
| 3 | `IN_STANCE` | the subject holds a stance | insignia "+10 armor while in a stance" |
| 4 | `ENCHANTED` | the subject holds an enchantment | insignia "+10 armor while enchanted" |

- **Subject.** The holder of the carrier: for a passive, the actor wearing it (the defender for an
  armor passive, the attacker for a damage passive); for a skill's or a potion's entry, the source;
  for a trap's entry, the trap's source; a terrain trap's entries carry no guard.
- **Time, for a carrier** ⟨FX-40⟩: **one snapshot per carrier's execution**. Every guard of the
  carrier's entries is evaluated once, from the state before the executor (§5.14) applies anything,
  and the results hold for every actor and every entry of that execution, even when an earlier
  entry changes the subject meanwhile (life steal healing the source across 50 % between two
  targets: §10.7).
- **Time, for a passive of a hit**: at the hit's armor step (armor passives, subject the target) and
  damage step (damage passives, subject the source), §5.5 steps 3–4, before the damage applies.
- **Second Wind** at 200 / 480: both guards are read at 200 (200 × 2 < 480); entry 1 heals to 340,
  entry 2 (`BELOW_HALF`) still applies.
- Exactly 50 % holds neither `ABOVE_HALF` nor `BELOW_HALF`.

## 3. The catalogue: effects that act

Kinds grouped; **P** = no MVP source (catalogued for closure). "Reads" lists the fields the kind
reads besides `kind`, `target`, `shape`, `filter`, `guard`; every other field is 0. "Class" is the
kind's role for §5.14: **hit** (a damaging entry), **hit modifier**, **holding** (stays in an effect
slot), **instant**, **placement**.

### 3.1 Health

| Id | Kind | Class | Reads | Bounds | Rule |
|---|---|---|---|---|---|
| 1 | `DAMAGE` | hit | `param` damage type; `v` base damage | 0…32,767 | §5.5 |
| 2 | `ATTACK_BONUS` | hit modifier | `v` added to the weapon's base damage | 0…32,767 | attack skills only: base = weapon damage (after requirement, design/15) + `v` |
| 3 | `HEAL` | instant | `v` health | 0…32,767 | `health = min(max, health + v)`; nothing on a dead actor; Deep wound (P) −20 % |
| 4 | `LIFE_STEAL` | instant | `v` health | 0…32,767 | ignores armor (design/04); the target loses `s = min(v, its health)`, the source heals `s` (capped) ⟨FX-0⟩ |
| 5 | `REGENERATION` | holding | `v` pips; `d` | −10…+10 | its pips join step 3's sum (§5.8). "Heal over time", "+health regeneration" (design/07) |

Damage types (design/04's order): 1 slashing, 2 piercing, 3 blunt (physical), 4 fire, 5 cold, 6
lightning, 7 earth (elemental), 8 shadow, 9 holy (neither: FX-23).

### 3.2 Conditions

| Id | Kind | Class | Reads | Rule |
|---|---|---|---|---|
| 6 | `CONDITION` | instant | `param` condition 1–9; `v` its duration, **1…32,767** (§2.1) | applies or refreshes (§5.7) |
| 7 | `CURE` | instant | `param` condition | a duration of 0 (§5.1); absent: nothing |

| Id | Condition | Effect | MVP | Stored |
|---|---|---|---|---|
| 1 | Bleeding | −3 health pips (step 3) | yes | `MemberTimers`, `GoblinTimers` |
| 2 | Poison | −4 health pips | yes | same |
| 3 | Burning | −7 health pips | yes | same |
| 4 | Crippled | a move costs 2 ticks per tile (a member's move; a goblin: FX-15) | yes | same |
| 5 | Knocked down | cannot act (§5.2; FX-7); critical from any arc for a weapon hit; interrupts (§5.9); reapplied while held: FX-31 | yes | same |
| 6 | Dazed | spells take +1 tick; a hit interrupts a spell in activation | **P** | FX-22 |
| 7 | Blind | a weapon hit misses unless its target is on the attacker's front tile | **P** | FX-22 |
| 8 | Weakness | −33 % to the holder's weapon hits | **P** | FX-22 |
| 9 | Deep wound | −20 % max health, −20 % healing received | **P** | FX-22 |

### 3.3 Energy

| Id | Kind | Class | Reads | Rule |
|---|---|---|---|---|
| 8 | `ENERGY` | instant | `v` energy, −255…+255 | `clamp(energy + v, 0, max)`, in thirds in storage |
| 9 | `NEXT_SPELL_COST` | holding | `v` 0…255; `d` | a glyph: consumed when the next spell **starts** (§5.9); cost ≥ 0 |

Adrenaline is changed by rules, not entries (§5.12).

### 3.4 Effects that stay on their holder

| Id | Kind | Class | Reads | Rule | Sources |
|---|---|---|---|---|---|
| 10 | `ARMOR` | holding | `v` 0…255; `d` | + armor while it lasts | Stone Skin; draughts; the Shaman's "shields" (FX-20) |
| 11 | `PENETRATION` | holding | `v` percent 0…100; `d`; `scope` | + penetration on the holder's hits of its scope | Warcry (FX-27) |
| 12 | `HIT_PENETRATION` | hit modifier | `v` percent 0…100 | penetration of **this carrier's** hit | Static Lash (25 %) |
| 13 | `BLOCK` | holding | `v` charges 1…63 (scaled); `d` | blocks the next `v` weapon hits it can block (§5.6); ends at 0 charges or its deadline | Brace |
| 14 | `EVADE` | holding | `param` 1 melee; `d` | evades melee weapon hits while it lasts (FX-11) | Sidestep |
| 15 | `ON_ATTACK_CONDITION` | holding | `param` condition; `v` its duration 1…32,767; `d` **or** `charges` (one of them non-zero) | each weapon hit landed by the holder spends a charge (if any) and applies the condition to a living target (§5.5 steps 7–8) | Venom Coat (`d`), oils "for N attacks" (`charges`, `d = 0`) |
| 16 | `MOVEMENT` | holding | FX-18 | draughts' "+movement" | design/07 |

**Charge-only effects** (`charges > 0`, `d = 0`) have **no time limit** (design/07: oils "for N
attacks"): their deadline is stored as `MAX_CLOCK` (2^28 − 1), which the clock never reaches (an
action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − 65,545`, and no action runs more than
`MAX_DURATION` ticks: ENG-01 §3.1). They end when their charges reach 0 or the instance closes.
For eviction (§5.7) their deadline is the latest possible.

**Skill kinds**, ids in design/03's order, and `Skill`, the generic kind of design/03's starter
tables:

| Id | Skill kind | Rule | From |
|---|---|---|---|
| 1 | Attack | the action is a weapon hit carrying the skill; needs the weapon of its attribute; tick cost and landing FX-5 | design/03 |
| 2 | Spell | interruptible in activation | design/03 |
| 3 | Hex | a spell that stays on a foe; removable (**P**) | design/03 |
| 4 | Enchantment | a spell that stays on an ally; removable (**P**) | design/03 |
| 5 | Stance | instant, one at a time: a new stance ends the held one | design/03 |
| 6 | Shout | instant, not interruptible, **alerts every pack within 8 tiles** | design/03, design/18 |
| 7 | Signet | no energy, long recharge (**P**) | design/03 |
| 8 | Preparation | modifies the holder's own attacks for a duration | design/03 |
| 9 | Trap | placed on a tile, triggers when a foe enters (§5.11) | design/03 |
| 10 | Glyph | modifies the next spell | design/03 |
| 11 | `Skill` | FX-25: interruptible; not a spell for Dazed, glyphs, quick cast | design/03 starter tables |
| 12 | Seal of Capture | FX-26 (**P**) | design/03 |

### 3.5 Control and placement

| Id | Kind | Class | Reads | Rule | Sources |
|---|---|---|---|---|---|
| 17 | `INTERRUPT` | instant | — | ends the target's activation (§5.9) | **P**: Champion, Beguiler |
| 18 | `TRAP` | placement | — | places a trap on the target tile; the carrier's other entries are the trap's (§5.11) | Snare; the Trapper |

**No displacement exists** (no document names a push, pull or teleport). **No summon in the MVP**.

### 3.6 Kinds after the MVP, catalogued for closure

| Id | Kind | Named by | Missing |
|---|---|---|---|
| 19 | `REVIVE` | design/07 | FX-18 |
| 20 | `REVEAL_FLOOR` | design/07 | FX-18 |
| 21 | `ON_SKILL_USE` | design/05, Hexer | FX-32: a **placeholder**, no behaviour |
| 22 | `SUMMON` | design/05, design/03 | FX-20 |
| 23 | `CAPTURE` | design/03, Seal of Capture | FX-26 |
| — | Paladin "protects the lord", Beguiler "illusions" | design/05, design/03 | **not catalogued** (FX-20) |

## 4. The catalogue: passive effects

Passive effects are read, never scheduled; **one id is one statistic**. They are flattened into the
snapshot at entry (equipment cannot change during an expedition, design/15), **losslessly** (§7.2):
every sum the rules read is stored apart.

**A `MODIFIER` carries two passives**, a **benefit** and a **cost** (design/15, Q-4), each
`(id 8, param 8, guard 3, scope 2, min 16, max 16)` = **53 bits**; the cost is fixed (`min = max`),
the benefit's rolled value is the item's `ItemMods` byte. A modifier without a cost has cost id 0.
An `ARMOR_SET` bonus is one passive.

| Id | Passive | Param; unit | When | Sources |
|---|---|---|---|---|
| 40 | `MAX_HEALTH` | ± health | snapshot | Fortitude +30, insignias, runes and their costs (design/15) |
| 41 | `ARMOR` | ± armor; guard 0, 3 or 4 | snapshot; guarded: at each hit | +4…+5; insignias +10 in a stance / enchanted; shield |
| 42 | `ARMOR_VS` | damage type; + armor | each hit of that type | +4…+7; classes' innate (+20 physical, +30 elemental) (FX-23) |
| 43 | `MAX_ENERGY` | ± energy | snapshot | light armor, Wellspring, "−5 energy" |
| 44 | `ENERGY_REGEN` | ± pips | snapshot | light armor; energy-on-hit's cost |
| 45 | `HEALTH_REGEN` | ± pips | snapshot | life steal's cost |
| 46 | `DAMAGE_TYPE` | a type | snapshot | the type change; staff "by attribute" |
| 47 | `DAMAGE_PERCENT` | ± percent; guard 0 or 1; scope | each hit of its scope | "+15 % above 50 %", conditional +10…+15 %, "+15 % damage" (FX-27) |
| 48 | `PENETRATION` | percent; scope | each hit of its scope | +2…+4 % (`WEAPON`); Might (`ATTACK_SKILL`, from the primary rank at use) |
| 49 | `LIFE_STEAL_ON_HIT` | health | each weapon hit | design/15 |
| 50 | `ENERGY_ON_HIT` | energy | each weapon hit | design/15 |
| 51 | `CONDITION_DURATION` | a condition; percent | each such condition inflicted | the prefix "Rending" (+33 %) |
| 52 | `ENCHANT_DURATION` | percent | each enchantment cast | +10…+20 % |
| 53 | `KNOCKDOWN_FLAT` | + ticks | each knock-down inflicted | *Hob-breaker*, 3 pieces |
| 54 | `ADRENALINE_EVERY_N` | N 1…255 | the `hits` counter | "every 10th to 5th hit" |
| 55 | `QUICK_CAST_EVERY_N` | an attribute; N | a `casts` counter | "every 5th spell of the attribute" |
| 56 | `ATTRIBUTE` | an attribute; ± ranks | snapshot | runes (the highest counts, every cost counts) |
| 57 | `ENERGY_COST` | a profession; − energy | each skill start | Fieldcraft |
| 58 | `HALVE_FIRST_HEAVY_HIT` | — | a weapon hit on the holder (FX-19) | *Hob-breaker*, 5 pieces |
| 59 | `BASE_DAMAGE_PERCENT` | percent | snapshot | personalisation +20 % |
| 60 | `RATING_PERCENT` | percent | snapshot | personalisation +10 % |
| 61–63 | `HEAL_BONUS`, `ACTIVATION_PERCENT`, `ENERGY_ON_DEATH` | — | **P** | Grace, Quickness, Harvest |
| 64–65 | `CASTE_ARMOR`, `ATTACK_SPEED` | — | **P** | affixes *Scarred*, *Rabid* |

**Aggregation of passives held more than once** ⟨FX-43⟩: additive passives (40–50, 52, 53, 57, 59,
60) are summed per statistic (per scope and guard for 47 and 48, per type for 42); 51 is summed per
condition; for 54, the lowest N counts (as "only the highest rune counts", design/15); 55 keeps
**one counter per quick-cast modifier held**, at most 2 (§7.2), each independent; 56 follows
design/15's rune rule.

**Weapons and arcs are rules, not entries** (design/04): the axe's +25 %, the critical +40 %, flank,
the maul's 2 ticks, the bow's line of sight. A goblin's weapon is its caste's (§7.3).

## 5. The resolution order

### 5.1 The clock, deadlines and counting

| Step | What | Order between actors |
|---|---|---|
| 0 | The clock advances, `clock = T`; **perception**, then the **awake set** (§5.2) | ascending entity id |
| 1 | Activations due at `T` resolve; lapsed activations are cleared (§5.2, §5.9) | members (0–7), then awake goblins, ascending id |
| 2 | Awake goblins act | ascending id; each sees the state the previous ones left |
| 3 | Regeneration, degeneration, adrenaline decay (§5.8) | members, then awake goblins, ascending id |
| 4 | Durations and recharges end (a deadline at or below the clock reads as ended; nothing written) | — |
| 5 | Defeat and objective checks (§5.13); `mine`'s check (§5.10) | — |

Between two ticks the clock reads `c`: the **action phase** is there.

**Counting** ⟨FX-0, FX-1, FX-2⟩. A timer counts the executions of the step that consumes it:

| Timer | Consumed by | Stored deadline | Active / due when |
|---|---|---|---|
| Holding effect or condition of `d` ticks | step 4 | `D = t₀ + d − 1`, `t₀` = `c + 1` in the action phase, `T` in steps 1–3 of tick `T` | tick `T′ ≤ D`; action phase at clock `c < D` |
| Charge-only effect | its charges | `MAX_CLOCK` | while charges > 0 (§3.4) |
| Activation of `n` ticks | step 1 | `A = f + n − 1`, `f` = `c + 1` in the action phase, `T + 1` if started in step 2 of `T` | resolves in step 1 of tick `A` |
| Recharge of `r` ticks | step 4, from the end of the activation (FX-2) | `R = t₀ + r − 1`, `t₀` where the activation ends: its resolution, its interruption, its lapse (§5.2, `t₀ = A`), or the use of an instant skill | action phase at `c ≥ R`; a goblin in step 2 of `T′ > R` |
| A goblin's recovery (FX-15) | step 2 | `B` (§5.2) | it skips step 2 of ticks `T′ ≤ B` |

A condition of `d` ticks degenerates exactly `d` times. A goblin's 3-tick wind-up started in step 2
of `T` resolves in step 1 of `T + 3`: three ticks run between (three decision points only if each of
the adventurer's actions costs one tick). "Ends now" is a duration of 0: `D = t₀ − 1`.

### 5.2 Perception, the awake set, busy actors

**Step 0, in order** ⟨FX-41⟩:

1. **Perception**: every goblin in the window that is asleep or on watch checks design/18's table
   against every member (M-3), in ascending entity id, from the state at step 0 (positions after the
   action phase and the previous tick). A goblin that notices engages its pack (the pack's `alert`
   bits, ENG-01 §3.2). The alerting of other packs within 8 tiles (a shout, a fight) is applied
   where it happens (§3.4, §5.5 step 9), not here.
2. **The awake set**: the goblins in the window, alive and not asleep (after step 0.1), the 8
   nearest to a member by hex distance, ties by lowest entity id (design/02). **Fixed for the
   tick**: a goblin that dies leaves it and **nothing refills it**; one alerted later in the tick
   joins at the next step 0.

Only awake goblins resolve activations, act and regenerate. **A goblin outside the set is frozen**
(design/02): nothing of it is read or written; its deadlines still pass on the clock, so a condition
that ends while it is frozen is lost, not delayed.

**A lapsed activation** ⟨FX-29⟩: an activation whose goblin is not awake in step 1 of its deadline
`A` (out of the 8, or out of the window) **lapses**, as an interrupt dated `A`. It is applied
**lazily**: nothing is written while the goblin is frozen; at the next step 1 in which the goblin is
awake with a stored activation deadline `A < T`, the activation is cleared and its skill's recharge
set to `R = A + r − 1` (kept if a later one is stored), in the write of that goblin's record, which
§5.2's awake bound already counts (ENG-01 §9.2: 8 goblins acting). Views and the client apply the
same reading to a stored `A` in the past. No scan of frozen goblins, no write beyond the awake ones.

**The goblin's activation field** (`GoblinTimers`: slot 8 bits, target, deadline) holds one of three
states: **none** (slot 255), **activating** (slot 0–3, a caste skill; deadline `A`), **recovering**
(slot 254; deadline `B`). Transitions:

| From | Event | To |
|---|---|---|
| none | step 2: a weapon attack or an instant attack skill of weapon cost `k` (FX-5, FX-15) | lands now; recovering with `B = T + k − 1` if `k > 1`, else none |
| none | step 2: a crippled move (cost 2) | recovering, `B = T + 1` |
| none | step 2: a skill with activation `n ≥ 1` | activating, `A = T + n` |
| activating | step 1 of `A`: resolves; its weapon cost `k` (an attack skill) exceeds `n` | recovering, `B = A + k − n`; else none |
| activating | interrupted (§5.9), or lapsed | none (recharge from the interruption or `A`) |
| recovering | `T > B` | none (read as such; cleared at the goblin's next write) |

A pending activation is never discarded by a recovery: recovery starts only when the activation
ends. **Busy** (activating or recovering) goblins do nothing in step 2, but take hits and
effects. A goblin whose activation resolves in step 1 does not act in step 2 (design/04).

**Members.** A member's activation lies inside its own action (FX-3). The knocked-down adventurer's
only legal action is Wait (FX-7); a knocked-down goblin skips step 2.

### 5.3 The adventurer's action

1. **Legality** against the state as it is: design/02's list; an attack skill without its weapon; a
   target the filter refuses; a trap tile that cannot take one (§5.11). Illegal: the batch stops.
2. **Costs** at once ⟨FX-0⟩: energy after reductions (`ENERGY_COST`, a glyph, consumed),
   adrenaline; the `casts` counters move (§5.12, FX-39).
3. **Facing** (design/04): toward the moved-to tile or the target; a target not adjacent: the
   direction of the first step of the hex line ⟨FX-0⟩.
4. **Resolution now** (a move and its trap, §5.11; a weapon attack; an attack skill without
   activation, FX-5; a potion; an instant skill), through the executor (§5.14). **Or** an
   activation starts, resolving in step 1 of its `n`-th tick.
5. **Then `n` world ticks run** (the action's tick cost; Crippled makes a move cost 2; FX-3).
   `mine` is §5.10.

### 5.4 Hit classes and what applies to each

| Class | Carriers |
|---|---|
| `WEAPON` | a weapon attack; an attack skill (then also `ATTACK_SKILL` for scopes) |
| `SPELL` | a `DAMAGE` entry of any other skill kind |
| `ITEM` | a potion's `DAMAGE` entry (a bomb) |
| `TRAP` | a trap's `DAMAGE` entry, placed or terrain |

| Rule | `WEAPON` | `SPELL` | `ITEM` | `TRAP` | From |
|---|:-:|:-:|:-:|:-:|---|
| Strength `5 × rank of the weapon's attribute` (capped by level) | ✓ | — | — | — | design/04 |
| Strength `3 × level` | — | ✓ | — | ✓ (FX-28) | design/04 |
| Strength from the recipe (`ITEM`'s field) | — | — | ✓ (FX-28) | — | — |
| Arcs: critical +40 %, axe +25 % | ✓ | FX-27 | — | — | design/04 |
| Block, flank, evade (melee), Blind's miss | ✓ | — | — | — | design/03, 04 |
| Weakness −33 % | ✓ | — | — | — | design/04 |
| `DAMAGE_PERCENT`, `PENETRATION` (passive, held) | by scope | by scope | — | — | §2.1 |
| `HIT_PENETRATION`, `ATTACK_BONUS` | its carrier | its carrier (not `ATTACK_BONUS`) | — | — | §5.14 |
| Target's armor, `ARMOR` effects, `ARMOR_VS` | ✓ | ✓ | ✓ | ✓ | design/04 |
| Source's adrenaline, `hits`, `ENERGY_ON_HIT`, `LIFE_STEAL_ON_HIT`, `ON_ATTACK_CONDITION` | ✓ | — | — | — | design/04, 15 |
| Target's +¼ strike; a hit for mining, Dazed, alerting | ✓ | ✓ | ✓ | ✓ | FX-10 |
| `HALVE_FIRST_HEAVY_HIT` | ✓ | — | — | — | FX-19 |

### 5.5 One hit, in order

One source, one target, one hit of class `K` with the carrier's hit modifiers (§5.14):

1. **Arc**, if `K` takes arcs: the source's tile or, at range, the tile the line of sight arrives
   from, in the target's arcs.
2. **Miss, block, evade** (§5.6), for `WEAPON`. A stopped hit ends here: nothing of it or of its
   carrier applies to this target, no charge but a block's is spent, not a hit.
3. **Armor** = the target's armor + `ARMOR` effects + guarded `ARMOR` passives + `ARMOR_VS`; then
   `armor − ⌊armor × p / 100⌋`, `p` the sum of the penetrations that apply to `K` (≤ 100; FX-9);
   ≥ 0.
4. **Damage** = `⌊base × table(strength − armor) / 2^16⌋`; the sum of the percents that apply to
   `K` (≥ −100) applied once, truncated; clamped to [0, 65,535]; then FX-19's halving if held.
5. **Apply**: `health = health ⊖ damage`. The hit is recorded (a member's "hit this tick" flag).
6. **Death check deferred** to step 9; the target's state after step 5 decides "alive" below.
7. **Target-side, `WEAPON`, target alive**: the conditions of the source's `ON_ATTACK_CONDITION`
   effects; `LIFE_STEAL_ON_HIT`.
8. **Source-side**, for `WEAPON` whether the target lives or not: each `ON_ATTACK_CONDITION` with
   charges spends one (§3.4; ends at 0), adrenaline (§5.12), `ENERGY_ON_HIT`, `hits`. For every
   class: the target's +¼ strike if alive.
9. **Death** of the target at 0 (§5.13). A goblin hit while asleep or on watch notices: its pack is
   engaged; a hit is "a fight" alerting packs within 8 tiles (design/18).

### 5.6 Block, evasion, miss, and what a hit is

| Case | Result | From |
|---|---|---|
| `BLOCK` with charges, weapon hit from front or front-side | blocked; a charge spent | design/03, 04 |
| Same, from rear-side or back | not blocked, no charge spent | design/04 |
| `EVADE`, a melee weapon hit | evaded (FX-11: from every arc) | design/03 |
| The target knocked down | neither blocks nor evades (FX-7) | — |
| A spell, a bomb, a trap | never blocked, evaded or missed | design/03 |
| Blind (P) | a weapon hit misses unless on the front tile | design/04 |
| The target asleep | the first hit cannot be blocked | design/04 |

**A hit** (FX-10): an attack or `DAMAGE` entry of any class that reaches its target unstopped,
whatever its damage (0 included). Degeneration and life steal are not hits.

### 5.7 Effects applied, refreshed, replaced

**Identity** ⟨FX-42⟩: a held effect is identified by its **carrier**: a skill id, or a **potion's
item id** (resolved through the belt slot the effect stores: two belt slots holding the same potion
are one carrier). The caster does not enter it. A condition is identified by its id.

**Conditions**: different ones stack (their pips are summed); the same one refreshes, `D = max(D_old,
D_new)` (FX-6); Knocked down: FX-31. A dead goblin takes nothing.

**Holding effects**, in order:

1. **Same carrier held**: keep the application with the **later deadline, whole** (rank, charges,
   deadline); on equal deadlines the new one (FX-30). A charge-only effect's deadline is `MAX_CLOCK`
   (§3.4), so a new charge-only application of the same oil replaces it.
2. Else **a stance** while one is held: it takes that slot.
3. Else the **lowest free slot**.
4. Else **eviction**: earliest deadline, ties lowest slot (FX-13). A goblin's one slot is replaced.

A slot stores the carrier, the **source's rank at application (0–15)** and the charges, so its
strength never depends on the caster afterwards (§7.2). Durations inflicted pass through
`effective_duration` with the source's `CONDITION_DURATION`, `ENCHANT_DURATION`, `KNOCKDOWN_FLAT`.

### 5.8 Step 3: regeneration, degeneration, adrenaline decay

For each member, then each awake goblin, ascending id:

1. **Health**: pips = its regeneration (snapshot `HEALTH_REGEN`, or the caste sheet's health
   regeneration, §7.3) + `REGENERATION` effects − 3 (Bleeding) − 4 (Poison) − 7 (Burning); clamped
   to [−10, +10] (design/03); × 2 health; clamped to [0, max].
2. **Energy**: + its regeneration in thirds; clamped to [0, max] (goblins in thirds, §7.2).
3. **Adrenaline decay** (FX-12): out of combat (a member: no goblin of the tick's awake set is
   Engaged; a goblin: not Engaged), − `ADRENALINE_DECAY` quarter strikes, floored at 0.
4. An actor at 0 dies (§5.13), after every actor of the step.

### 5.9 Activation and interrupts

- An activation resolves in step 1 of `A` (FX-1): members first, then awake goblins. A goblin not
  awake lapses (§5.2). At resolution the target must still be legal; if not, nothing happens and the
  costs stay paid ⟨FX-0⟩. The resolution runs the executor (§5.14).
- **What interrupts**: `INTERRUPT` (P); **a knock-down** (design/14: "interrupt its wind-up" with
  Skullring); a hit while Dazed, for a spell (P). Shouts cannot be interrupted; instant skills have
  none. **Mining is not an activation** (§5.10).
- **Interrupted**: energy stays paid, recharge from the interruption (FX-2), no effect, a glyph and a
  quick-cast bonus consumed at the start stay consumed (FX-39); adrenaline FX-4; the adventurer's
  remaining ticks run (FX-3). A goblin's field goes to none (§5.2).
- A goblin killed before `A` never resolves.

### 5.10 Mining (ENG-01 §4.1, design/17)

`mine` is sent alone (E-18) and is **not a skill**: no cost, recharge or activation; FX-3 and FX-4
do not apply.

1. **Legality**: next to a vein not yet mined; the content version matches.
2. For `k = 1, 2, 3`: tick `k` runs, steps 0–5; a hit on the member sets its "hit this tick" flag.
3. **After step 5 of tick `k`**: the flag set → the action **stops** (the vein stays, no stone, no
   further tick: ENG-01). Else, `k = 3` → **completion**: the vein is marked mined, the entropy is
   fed, one stillstone. Defeat ends it as any tick does.

### 5.11 Traps

**Two object kinds**: the terrain trap (kind 4, generated, design/18) and the placed trap (kind 9),
each with its `param` (§7.2).

**Placing** (a `TRAP` entry): the tile is walkable, holds no actor and no object, is in range; the
trap takes the lowest object index that is empty or a used trap; otherwise the skill is illegal (a
member) or skipped by the AI (a goblin) (FX-14).

**Triggering**, when an actor **enters** the tile by a move: right after a member's move in the
action phase, before the ticks; right after a goblin's move in step 2, within its act. It triggers
on a foe of the trap's side (placed: the placer's foes; terrain: FX-34), once:

1. **The source**: a member placer (its snapshot's level, the bar slot's rank); a goblin placer (its
   record's caste and level, the caste sheet's rank; a dead placer's record still holds them); a
   terrain trap: its location's values (FX-14, FX-28).
2. **The trap's carrier** (its skill without the `TRAP` entry) runs through the executor (§5.14)
   with the entering actor as its only actor, class `TRAP`.
3. The object is marked used. The move stands; its cost and a goblin's recovery for it were fixed
   before the trap (a Crippled just applied does not change them).
4. A death follows §5.13; a goblin killed in its own move ends its act.

A placed trap never triggers on its own side and lasts until triggered or the instance closes.

### 5.12 Counters and adrenaline

Every counter is 0 in a new instance (ENG-01 §2.1) and never wraps:

| Counter | Where | Moves when | Rule |
|---|---|---|---|
| `hits` (u8) | `MemberState` | §5.5 step 8 of each `WEAPON` hit by the member, if `ADRENALINE_EVERY_N` gives `N > 0` | `hits += 1`; if `hits = N`: this hit's adrenaline doubles, `hits = 0`. Stays < N ≤ 255; N = 0: stays 0 |
| `casts`, `casts_2` (u8 each) | `MemberState` | §5.3 step 2, when a spell (skill kind 2, 3 or 4) of that counter's attribute **with activation ≥ 1** starts, if its N > 0 (FX-39) | `casts += 1`; if `casts = N`: this spell's activation −1, `casts = 0`. Both counters count independently; bonuses add, the activation never below 1 (FX-43). Interrupted: the bonus stays spent |
| Adrenaline (quarter strikes) | `MemberState` u16; `GoblinState` u8 | + 4 per `WEAPON` hit landed by the actor (+ 8 doubled); + 1 per hit taken while alive; − cost at an adrenaline skill's start; decay (§5.8) | each gain capped at the actor's cap (FX-12: the highest adrenaline cost on its bar or caste, in quarters; 0 if none) and at its field (a goblin: 252, 63 strikes) |

### 5.13 Zero health, deaths, defeat

- **A goblin at 0 dies at once** at the step that brought it there: dead state (its record is its
  remains), out of the awake set without replacement, no act, effect or activation; remains do not
  block ⟨FX-0⟩. `GoblinKilled` in resolution order; credit to the source's member (M-4).
- **Simultaneous deaths** follow the resolution order (a carrier's actors in tile order, step 3 in
  id order). Nothing of the MVP reacts to a death.
- **The adventurer at 0** (FX-8): in the action phase and in steps 1–2 the tick stops at once; step
  3 completes first. Health 0 is terminal. Step 5's defeat and objective finalisation always run
  (kills before the stop count, D-04).

### 5.14 Executing a carrier: one layer owns the entries

Every skill resolution, potion, trap trigger and weapon attack goes through **one executor**; the hit
pipeline (§5.5) resolves one hit and never iterates entries.

**Legal carriers** ⟨FX-45⟩: the content pipeline refuses any other combination:

| Rule | Why |
|---|---|
| **At most one hit** per carrier: one `DAMAGE` entry, or the weapon hit of an attack skill (which then has no `DAMAGE` entry) | two hits of one carrier would double every on-hit rule; no source has two |
| **At most one holding entry** per carrier (kinds 5, 9–11, 13–16) | a held effect's slot is keyed by its carrier; no source has two |
| Hit modifiers (`ATTACK_BONUS`, `HIT_PENETRATION`) only with a hit; `ATTACK_BONUS` only in an attack skill | they modify the carrier's hit |
| An attack skill's entries are all `FOE`, `SINGLE`: its attacked target | "replaces the next weapon attack" |
| A `TRAP` entry is entry 1; the others are `FOE`, `SINGLE`, applied to the entrant | §5.11 |
| A potion has one entry | ENG-01 `ITEM` |

**Execution**, for a carrier with its source, its address and its class:

1. **Guards**: evaluate every entry's guard once (§2.4, FX-40).
2. **Hit modifiers**: collect `ATTACK_BONUS` and `HIT_PENETRATION` for the carrier's hit.
3. **Target sets**: for each entry, its tiles (shape around its addressing, clipped) and its actors
   (filter); all taken **now**, before anything applies. The **actor list** is the union of the
   entries' actors, in ascending tile index (X-7's exception).
4. **For each actor of the list, in order**, the entries whose set holds it, in entry order:
   - the **hit** (the weapon hit or the `DAMAGE` entry) through §5.5; **stopped** (blocked, evaded,
     missed) → the carrier's remaining entries skip this actor;
   - any other entry, **only if the actor is alive**: instant kinds apply; a holding entry goes
     through §5.7 on that actor; `TRAP` places the trap (its set is the target tile, no actor).
5. **Carrier-level effects**: a shout alerts packs within 8 tiles; a glyph consumed; `casts`
   already moved at the start.

A carrier whose actor list is empty does nothing but its carrier-level effects; its costs stay paid.

## 6. Edges (D-140)

| Edge | Result |
|---|---|
| Energy cost after reductions below 0 | 0 |
| Activation after reductions below 1, non-instant | 1 (design/03) |
| A rank 13–15 | FX-0b |
| A value outside its kind's bounds | refused by the pipeline; at play, clamped to the kind's bounds |
| A duration carried as a value above 32,767 | refused by the pipeline (§2.1) |
| Effective duration | `effective_duration`'s caps, ≤ `MAX_DURATION` |
| Heal or energy past max or below 0; health pips past ±10 | clamped |
| Armor below 0; penetration above 100 % | 0; 100 % |
| Percent sum below −100; damage outside [0, 65,535] | −100; the nearest bound |
| A 0-damage hit | a hit |
| Life steal above the target's health | the target's health |
| A cure of an absent condition; anything on a dead goblin | nothing |
| Knocked down reapplied while held | FX-31 |
| The adventurer knocked down | only Wait (FX-7) |
| A target illegal at resolution | nothing, costs paid |
| A carrier with no actor | carrier-level effects only |
| An area near the window's edge | clipped |
| A block at 0 charges; an oil at 0 charges | ended |
| A charge-only effect never used | lasts until the instance closes |
| A stance while one is held; slots full; equal deadlines | §5.7 |
| A goblin's activation while it is frozen | lapses at `A`, applied lazily (FX-29) |
| A trap on a full chunk, an occupied tile, a wall | invalid (FX-14) |
| A counter at N; adrenaline at its cap or its field | reset; capped |
| Two activations due in the same step 1 | id order; a goblin killed by an earlier one does not resolve |
| A goblin whose own tile is not marked occupied | cannot happen: asserted (design/04) |

## 7. What CBT-01 freezes

### 7.1 Enumerations and functions

- **Enumerations**: effect kinds 1–23, passive kinds 40–65, conditions 1–9, damage types 1–9, skill
  kinds 1–12, shapes 1–5, targets, filters, guards 0–4, scopes, hit classes, kind classes (§3),
  object kinds (terrain trap 4, placed trap 9), the goblin activation field's states (§5.2).
- **The entry** (§2.1, 97 bits) in `SKILL` (3), `ITEM` (1); the two-passive `MODIFIER`;
  `ARMOR_SET`'s two passives. **The legal carriers** (§5.14).
- **Functions**, pure, in §5's order: `apply_action`, `tick`, `perceive`, `awake_set`, `execute`
  (§5.14), `resolve_hit`, `hold`, `regenerate`, `interrupt`, `lapse`, `mine_tick`, `trigger_trap`,
  `kill`.

### 7.2 The state inventory against ENG-01 §3.2 (FX-24)

**Bit budget of a felt**: bits 0–249 are data, bit 250 is `LIVE`; a limb is 128 bits and no field
straddles bit 128, so a word offers a low limb of 128 bits (0–127) and a high limb of **122**
(128–249). Every count below is the sum of the fields as declared.

**Words written in play** (per tick, ENG-01 §9.2):

| Word | Frozen (ENG-01) | Added here | Placement | Free after |
|---|---|---|---|---|
| `MemberState` | flags 160–167: turned, instant used, since the last tick (3 of 8 used) | flags "hit this tick", `HALVE_FIRST_HEAVY_HIT` spent (2 bits); `casts_2` (8) | flags bits 3–4; `casts_2` at 168–175 | flags 3 bits; 176–249 (74) |
| `MemberTimers` | activation (0–63), 5 conditions (64–223) | — | — | 224–249 (26) |
| `MemberEffects` | 4 slots × 56 bits: skill 16 · charges 8 · deadline 32 (28 used) | per slot: **rank 0–15** in the 4 unused deadline bits; the **potion flag** as bit 15 of the skill field (skill ids ≤ 32,767; a potion's skill field holds its belt slot 0–3) | slots at 0, 56 (low), 128, 184 (high): 4 × 56 = 224 | 112–127, 240–249 |
| `Recharges` | 8 × 28 | — | — | — |
| `GoblinState` | energy 8 bits, adrenaline 8 bits, … | units: energy **in thirds** (a caste's energy ≤ 85, since 85 × 3 = 255); adrenaline in quarters (≤ 252) | existing fields | 240–249 (10) |
| `GoblinTimers` | activation slot 8 · target 16 · deadline 28 · 5 conditions · effect skill 16 · effect deadline 28 | the effect's **charges 6** and **rank 4** (10 bits); the activation slot's states 254 recovering / 255 none (§5.2) | 240–249: 6 + 4 = 10, full | 0 |
| Chunk object | tile 8 · kind 4 · state 4 · param 16 | placed trap (kind 9): bit 15 = 0 → member 3 bits + bar slot 3 bits (6); bit 15 = 1 → goblin entity − 8 in 12 bits (≤ 8 + 16 × 224 + 9 − 8 = 3,593 < 4,096) + caste skill 2 bits (14 + 1 = 15). Terrain trap (kind 4): param = its `SKILL` id | existing | — |

**Snapshot words, written at entry and at a gate, read in play.** A lossless flattening of §4
needs, besides ENG-01's fields:

| Need | Bits | Arithmetic |
|---|---:|---|
| `DAMAGE_PERCENT` sums, per guard (`ALWAYS`, `ABOVE_HALF`) × class (plain weapon, attack skill, spell), `i8` each | 48 | 2 × 3 × 8. Range: at most 7 damage passives can be held (weapon: prefix, suffix, inscription; off-hand: suffix, inscription; 2 set bonuses: the pipeline gives `DAMAGE_PERCENT` only the held items' slot types and set bonuses); it bounds a `DAMAGE_PERCENT`'s max at 18, so 7 × 18 = 126 ≤ 127 |
| `PENETRATION` sums per class (plain weapon, attack skill, spell), `u8` each, ≤ 100 | 24 | 3 × 8 (replaces ENG-01's single `penetration`, 168–175 of `MemberStats`, which is freed) |
| Two quick-cast modifiers: attribute 4 + N 8 each | 24 | 2 × 12. At most 2: `QUICK_CAST_EVERY_N` is held only on the weapon and the off-hand (the pipeline gives it one slot type) |
| `CONDITION_DURATION`: condition 4 + percent 6 | 10 | one prefix, on the weapon only (design/15: prefixes on weapons) |
| `ENCHANT_DURATION` percent (≤ 63) | 6 | — |
| `ARMOR` in a stance, `ARMOR` enchanted | 16 | 2 × 8 |
| `KNOCKDOWN_FLAT` (≤ 3) 2; `HALVE_FIRST_HEAVY_HIT` held 1 | 3 | — |
| `ARMOR_VS` per damage type, 9 × 6 bits (≤ 63, saturated: FX-23), replacing vs physical / vs elemental (16) | 54 | 9 × 6 |

ENG-01's `MemberKit` high limb (122 bits) holds today: conditional damage 8, threshold 8, life steal
8, energy on hit 8, condition duration 8, enchantment duration 8, double adrenaline N 8, quick cast N
8, health bonus 16 = **80**, free **42**. `MemberStats` has free 200–249 = **50** (high) and, once
vs physical / vs elemental go, 48–63 = **16** (low).

- **Without a new word**, the kit would hold: damage sums 48 + penetration 24 + quick cast 24 +
  condition duration 10 + enchantment 6 + armor 16 + knock-down and halving 3 + life steal 8 +
  energy on hit 8 + double adrenaline N 8 + health bonus 16 = **171 > 122**. Moving `ARMOR_VS` to
  `MemberStats` fits there (2 types × 6 = 12 in the 16 low bits, 7 × 6 = 42 in the 50 high bits), but
  the kit still overflows by 49 bits. **So a lossless snapshot needs one more member word**, or
  content restrictions (FX-24).
- **With one more word** (`MemberMods`, word 8), the recommendation:
  - `MemberMods` low limb: damage sums 48 + penetration 24 = **72 ≤ 128**; high limb: quick cast 24
    = **24 ≤ 122**. Free: 56 + 98 bits for later.
  - `MemberKit` high limb: life steal 8 + energy on hit 8 + condition duration 10 + enchantment 6 +
    double adrenaline N 8 + health bonus 16 + armor 16 + knock-down and halving 3 = **75 ≤ 122**
    (the conditional damage, threshold and quick-cast fields move to `MemberMods`).
  - `MemberStats`: `ARMOR_VS` 12 low + 42 high, as above.

**Registry records** (not yet laid out; ENG-03 laid out five kinds):

| Record | Parts | Layout | Arithmetic |
|---|---:|---|---|
| `SKILL` | 2 | part 0 low: header; part 0 high: entry 1; part 1 low: entry 2; part 1 high: entry 3 | header = profession 8 + attribute 8 + skill kind 8 + elite 1 + energy 8 + adrenaline 8 + activation 16 + recharge 16 + range 8 + target 2 = **83 ≤ 128**; each entry **97 ≤ 122** |
| `ITEM` | 1 | low: class 8 + region 16 + rarity 8 + value 32 + book index 8 = **72 ≤ 128**; high: the entry 97 + range 8 + bomb strength 8 = **113 ≤ 122** | FX-18, FX-28 |
| `MODIFIER` | 1 | low: slot type 8; high: 2 × 53 = **106 ≤ 122** | §4 |
| `ARMOR_SET` | 1 | low: 5 piece bases × 16 = **80**; high: 2 × 53 = **106 ≤ 122** | — |
| `CASTE` | 2 | §7.3, **239 bits** over 4 limbs | §7.3 |

**Cost.** With the recommendation, **+1 slot per member** (words 8 → 9; the MVP has 1 member per
instance slot):
- **Lifetime**: 1 new key per adventurer slot, N = **453,524 L2 gas once** (ENG-01 §10's N).
- **At every create and gate**: 1 more overwritten word, O = **32,072** (ENG-01 §2.1 writes every
  snapshot word at a generation change).
- **In play**: written never. Read by the ticks that resolve a hit or a spell start: one storage
  read, which ENG-01 does not price (ENG-07 measures it).

Everything else fits in the frozen words: **0 slots**. After the MVP: the four conditions (FX-22,
+1 word per member and per goblin), summons (FX-20), revive's state (FX-18).

**Registry reads, the true union of one invocation** (F-16). `bundle` refuses more than 32 records
(`MAX_READ`, asserted). What the rules of this document read, deduplicated, at worst in the MVP (5
castes):

| Records | Count | Parts (slots) | Why |
|---|---:|---:|---|
| The bar's `SKILL`s | 8 | 16 | used, or held as effects |
| The belt's potions (`ITEM`) | 4 | 4 | drunk, or held as effects |
| The castes (`CASTE`) of the goblins read in the invocation | 5 | 10 | every awake goblin's stats and weapon (inline, §7.3: no `BASE` read) |
| Those castes' `SKILL`s | 20 | 40 | 4 each; a goblin's held effect is one of them or a bar skill |
| `LOCATION` | 1 | 2 | a terrain trap's level (FX-28) |
| Terrain traps' `SKILL`s | `T` | 2 `T` | one per distinct terrain-trap skill triggered |
| **Total** | **38 + T** | **72 + 2 T** | 8 + 4 + 5 + 20 + 1 = 38 |

- **38 + T > 32** already at `T = 0`.
- The price at ~36,000 a slot: 72 × 36,000 = **2,592,000 L2 gas**, + 72,000 a terrain-trap skill,
  + one more `bundle` call (C ≈ 0.12–0.14 M).
- **ENG-05's generation reads** (spawn tables, packs, quotas, outlines, set pieces, for up to 4
  reveals) come on top.
- FX-29's lazy cleanup reads nothing more: the goblin's caste is already in the union.
- The bound and its price are FX-46.

### 7.3 The caste sheet's shape (DES-06 fills the values)

| Field | Bits | Notes |
|---|---:|---|
| tier | 8 | 1–6 |
| AI profile | 8 | design/05 |
| health multiplier | 16 | percent |
| **health regeneration** | 8 | signed pips −10…+10, stored +10 (§5.8) |
| armor | 8 | — |
| armor per damage type | 54 | 9 × 6 (FX-23) |
| weapon, inline | 28 | damage 16 · type 4 · ticks 4 · range 4 (no `BASE` read) |
| energy (≤ 85), energy regeneration | 8 + 8 | stored in thirds in `GoblinState` |
| 4 skills in priority order | 64 | 4 × 16 |
| rank of its skills | 4 | 0–15 (§2.2) |
| flee threshold | 8 | percent (`swarm`: 30 %) |
| loot table | 16 | — |
| boss flag | 1 | — |
| movement, boss phases | — | **P** (FX-20) |
| **Total** | **239** | 8 + 8 + 16 + 8 + 8 + 54 + 28 + 16 + 64 + 4 + 8 + 16 + 1. Laid over 2 parts (4 limbs of 128, 122, 128, 122), no field straddling a limb |

The adrenaline cap is derived (its skills' highest cost).

## 8. Coverage: every source the documents name, and its kinds

| Source | Document | Kinds |
|---|---|---|
| Cleave | design/03 | skill 1; 2 |
| Rending Cut | design/03 | 1; 6 (Bleeding, `v` 5…20) |
| Skullring | design/03 | 1; 6 (Knocked down 2); interrupts |
| Second Wind | design/03 | 11; 3, 3 `BELOW_HALF` (FX-17) |
| Brace | design/03 | 5; 13 |
| Warcry | design/03 | 6; 11 (alerts) |
| Aimed Shot | design/03 | 1; 2 (FX-5) |
| Hamstring Shot | design/03 | 1; 6 (Crippled) |
| Venom Coat | design/03 | 8; 15 (Poison 24, `d`) |
| Snare | design/03 | 9; 18, 6 (Crippled), 1 |
| Field Dressing | design/03 | 11; 3, 7 (Bleeding) |
| Sidestep | design/03 | 5; 14 |
| Ember Bolt | design/03 | 2; 1 (fire) |
| Cinder Ring | design/03 | 2; 1 (fire, `SELF`, `RING_1`, `FOES`), 6 (Burning) |
| Rime Shard | design/03 | 2; 1 (cold), 6 (Crippled: FX-16) |
| Stone Skin | design/03 | 4; 10 |
| Static Lash | design/03 | 2; 1 (lightning), 12 (25 %) |
| Deep Draw | design/03 | 10; 9 |
| Seal of Capture | design/03 | 12; 23 (**P**, FX-26) |
| Might, Fieldcraft, Wellspring | design/03 | 48, 57, 43 |
| Grace, Harvest, Quickness | design/03 | 61–63 (**P**) |
| The nine conditions | design/04, 09 | §3.2 |
| Arcs, critical, flank, axe, maul, bow, staff | design/04 | §5.4–§5.6; 46 |
| Adrenaline, energy, regeneration | design/04, 03 | §5.8, §5.12 |
| Runt, Slinger | design/05 | weapon only |
| Skirmisher | design/05 | 6 (Bleeding) |
| Shaman | design/05 | 3; 10 for "shields" (FX-20) |
| Hobgoblin | design/05, 04 | an attack skill with activation 3 |
| Trapper, Wolf rider, Hexer, Champion, Paladin, Lord | design/05 (**P**) | 18, 6; 6, movement; 21, 8; 5, 13, 14, 17; 3, "protects"; a shout to allies, 22 |
| Affixes | design/05 (**P**) | 64, 65 |
| Restoratives | design/07 | 5, 7, 8 |
| Draughts | design/07 | 10, 5, 16 (FX-18) |
| Oils | design/07 | 15 (`charges`) |
| Bombs | design/07 | 1 or 6; `TILE`, `DISC_1` or `SINGLE`, `FOES` (FX-18, FX-35) |
| Rare potions | design/07 (**P**) | 19, 20 |
| Every modifier of design/15 | design/15 | §4, benefit and cost |
| Insignias, runes, personalisation | design/15 | 40, 41, 56, 59, 60 |
| *Hob-breaker* | design/15 | 53; 58 (FX-19) |
| Terrain traps | design/18 | object kind 4 (FX-14, FX-34) |
| Veins | design/17, 18 | §5.10 |
| The Rift Heart | design/17 | a caste |
| Shouts and fights alerting | design/18 | skill kind 6; §5.5 step 9 |
| Chests, remains, nodes, collectors, levers, braziers, landmarks | design/18, 15 | not effects |

## 9. Escalations (open; the project manager decides, D-150)

Numbers are stable. **★ = CBT-01 needs it before freezing**: the decision changes a field, an
enumeration, a legal combination, or a step or order of §5's functions. Without ★: a value or
content only, or post-MVP. The options, the reasoning and the auditor's view are in the task's
report.

**A. Time, perception, activation**

| # | Question | Recommendation |
|---|---|---|
| FX-0 ★ | The ⟨FX-0⟩ conventions; **FX-0b** ranks 13–15 | as written; extrapolate to 15 |
| FX-1 ★ | Activation resolves in step 1 (design/02) or at the tick's end (design/04) | step 1 |
| FX-2 ★ | Recharge from the activation's end or from the use | the end |
| FX-3 ★ | The adventurer interrupted: remaining ticks run? | yes |
| FX-4 ★ | Interrupted adrenaline | spent |
| FX-5 ★ | Attack skills' tick cost and landing | max(weapon, activation); at once without activation, at resolution with one |
| FX-8 ★ | The adventurer at 0 mid-tick | §5.13 |
| FX-15 ★ | A goblin's act of cost `k > 1` | recovery of `k − 1` ticks in the activation field (§5.2) |
| FX-29 ★ | A goblin's activation while frozen at `A` | lapses at `A`, applied lazily |
| FX-41 ★ | **New.** Perception and the awake set within a tick | perception at step 0 before the selection; the set fixed for the tick, not refilled |

**B. Hits and damage**

| # | Question | Recommendation |
|---|---|---|
| FX-9 ★ | Penetration: flat or percent | percent, summed, ≤ 100 |
| FX-10 ★ | What is a hit | any class unstopped, 0 damage included, traps included |
| FX-11 ★ | Flank and evasion | evasion holds from every arc |
| FX-19 ★ | *Hob-breaker*'s halving | final damage of a weapon hit; `2h ≥ max ∧ 2(h ⊖ damage) < max`; spent when it triggers |
| FX-23 ★ | Shadow and holy; per-type armor | neither class bonus; 9 × 6 bits, saturated at 63 |
| FX-27 ★ | Arcs for spells; scopes | weapon hits only; `WEAPON` by default |
| FX-28 ★ | Strength of bombs and traps | **changed**: a bomb's from its recipe (a field of `ITEM`); traps `3 × level` |

**C. Held effects and carriers**

| # | Question | Recommendation |
|---|---|---|
| FX-6 ★ | Condition refresh | `max(old, new)` |
| FX-7 ★ | Knocked down: actions, block, evasion | Wait only; neither |
| FX-13 ★ | Slots full | earliest deadline, ties lowest slot; a goblin's is replaced |
| FX-30 ★ | Potency on refresh | the later-deadline application, whole; the new one on a tie |
| FX-31 ★ | Knocked down reapplied while held | **changed**: refreshed like any condition |
| FX-40 ★ | **New.** When a carrier's guards are evaluated | once per carrier's execution, before anything applies |
| FX-42 ★ | **New.** The identity of a held effect | its carrier (a skill id, a potion's item id), not the caster, not the belt slot |
| FX-45 ★ | **New.** Legal carriers | §5.14: one hit, one holding entry, and the rest |

**D. Adrenaline, counters, passives**

| # | Question | Recommendation |
|---|---|---|
| FX-12 ★ | Adrenaline's cap, out of combat, decay | as §5.8, §5.12; a code constant `ADRENALINE_DECAY` until BAL-01 |
| FX-39 ★ | Which spell takes the quick-cast bonus | **now ★**: the `N`-th spell with activation ≥ 1, counted at its start; spent if interrupted |
| FX-43 ★ | **New.** Passives held twice | summed per statistic, scope, guard and type; the lowest N for double adrenaline; one counter per quick-cast modifier (≤ 2), bonuses added, activation ≥ 1 |

**E. Areas, bombs, traps**

| # | Question | Recommendation |
|---|---|---|
| FX-14 ★ | Terrain traps' content, lifetime, trigger, full chunk | a `SKILL` id; until triggered; once; invalid when full |
| FX-33 ★ | design/04's 18 and 36 tiles | discs with their centre (19, 37) |
| FX-34 ★ | Whom a terrain trap hits | members only |
| FX-35 ★ | `DISC_1` hits 7, ENG-01 budgets 6 | raise to 7 |
| FX-21 | Radius 2 and 3 | none in MVP content until measured |

**F. Content shape**

| # | Question | Recommendation |
|---|---|---|
| FX-25 ★ | The generic `Skill` kind | interruptible; not a spell for Dazed, glyphs, quick cast |
| FX-18 ★ | Potions: "+movement", revive, reveal, bombs | a tile flag in `Item`, range and strength in `ITEM`, line of sight |
| FX-16 | Rime Shard's slow | Crippled |
| FX-17 | Second Wind's "more" | a second guarded `HEAL` |
| FX-20 | Shaman "shields", Paladin, summons, Wolf rider | `ARMOR`; the rest waits |
| FX-26 | The Seal of Capture | post-MVP; a standalone action on remains |
| FX-32 | The Hexer's trigger | waits for DES-06 |

**G. Storage and reads**

| # | Question | Recommendation |
|---|---|---|
| FX-22 ★ | The four post-MVP conditions | one more word per member and per goblin when they ship |
| FX-24 ★ | The inventory of §7.2 | **changed**: one more member word (`MemberMods`), lossless |
| FX-46 ★ | **New.** The registry reads exceed `MAX_READ` (38 + T records) | two `bundle` calls when needed (a second call only if the union passes 32), priced by ENG-07 |

## 10. Worked examples

Numbers illustrative. Each example states its assumptions.

### 10.1 An area kills two goblins at once

The Arcanist is level 20 with Fire 12, stands on (10, 10) facing East, and has no damage passive.
Three goblins stand adjacent, each facing the Arcanist, with armor 40, no block and health
regeneration 0; there is no other goblin in the window, so all three are awake:

| Goblin | Tile | Health |
|---|---|---:|
| **57** | (10, 9) = 2,314 | 90 |
| **90** | (11, 10) = 2,571 | 100 |
| **24** | (10, 11) = 2,826 | 200 |

The goblins attack in melee without moving and do not knock the Arcanist down.

- **Clock 40**: Cinder Ring (15 / 2 / 12). 15 energy is paid, and `A = 42`.
- **Tick 41**: goblins 24, 57 and 90 attack in id order; none interrupts.
- **Tick 42, step 1**: the executor runs.
  - Entries: 1 is `DAMAGE` fire, 2 is `CONDITION` Burning; both are `SELF`, `RING_1`, `FOES`.
  - The actor list, in tile order, is 2,314, 2,571, 2,826. The class is `SPELL`: no arc (FX-27).
  - The damage is `⌊80 × 92,682 / 65,536⌋ = 113`.
  - **57**: 90 → 0. Entry 2 is skipped because 57 is dead. `GoblinKilled(57)`.
  - **90**: 100 → 0. `GoblinKilled(90)`.
  - **24**: 200 → 87, then Burning 3 ticks: `t₀ = 42`, `D = 44`.
  - The recharge is `R = 53`.
- **Tick 42, step 2**: goblin 24 alone acts; the awake set is not refilled.
- **Step 3 of ticks 42, 43, 44**: goblin 24 goes 87 → 73 → 59 → 45.

### 10.2 An interrupt

The Hobgoblin, **entity 40**, has armor 70 and health 400, and is the only goblin. Its smash is an
attack skill with activation 3 and recharge 10, on a caste weapon costing 1 tick.
- **Step 2 of tick 50**: it starts the smash and pays its energy, so `A = 53`. Its field reads
  activating.

The adventurer is a Vanguard of level 20 with a maul and Mauls 12, holding 24 quarter strikes, with
no set bonus.
- **Clock 50**: the adventurer moves to the Hobgoblin's front tile (tick 51).
- **Clock 51**: Skullring. It lands at once (FX-5) and costs the maul's 2 ticks (52, 53).
  - Adrenaline 24 → 0.
  - Front arc, no block. Damage `⌊27 × 55,109 / 65,536⌋ = 22`: 400 → 378.
  - Knocked down, `t₀ = 52`, `D = 53`. This interrupts the smash: the field goes to none, and the
    recharge is `R = 52 + 10 − 1 = 61`.
  - The adventurer gains 4 quarters; the Hobgoblin +1.
- **Ticks 52, 53**: the Hobgoblin is knocked down.
- **Tick 54**: it acts again; its smash is usable from step 2 of tick 62.

Three ticks, two actions.

### 10.3 A condition refreshed while ticking

The adventurer has health regeneration 0, max health 480, and health above 200 throughout. It is
Poisoned with `D = 72`.
- **Step 2 of tick 70**: a weapon hit of goblin 17 applies Bleeding 8, so `D = 77`.
- **Ticks 70–72**: −14 health each. **Ticks 73–75**: −6 each.
- **Step 2 of tick 74**: Bleeding 8 again gives 81; one degeneration that tick.
  - Variant, Bleeding 2 at tick 74: `max` keeps 77, while replacing would give 75 (FX-6).
- **Clock 75**: Field Dressing, not interrupted, resolves in step 1 of tick 76. Its guards are read
  first, then Heal, then Cure: `D = 75`.
- **Total**: 60 health lost, ticks 70–75.

### 10.4 Equal deadlines at eviction; a stance replacing a stance

The member holds 4 effects and no stance:

| Slot | Effect | Deadline |
|---:|---|---:|
| 0 | Stone Skin | 90 |
| 1 | Warcry | 85 |
| 2 | Venom Coat | 85 |
| 3 | a draught | 100 |

- **Clock 80**: Sidestep (`d` 6). It needs a slot and none is free. The earliest deadline is 85, in
  slots 1 and 2; ties go to the lowest slot, so **Warcry is evicted**. Sidestep goes in slot 1 with
  `t₀ = 81`, `D = 86`, rank 12.
- **Clock 82**: Brace. A stance is held, so Brace takes slot 1.

### 10.5 An activation that lapses while frozen

Nine goblins are engaged. **Goblin 30** starts a 3-tick activation in step 2 of tick 100, so
`A = 103`; its recharge is 10. It is awake and busy in ticks 101 and 102. At step 0 of tick 103 it
is the ninth nearest: frozen, and nothing is written.

- It stays frozen through tick 106 and is awake again at step 0 of tick 107.
- **Step 1 of tick 107**: its stored `A = 103 < 107`, so the activation has **lapsed at 103**. The
  field goes to none and the recharge is `R = 103 + 10 − 1 = 112`. This is written in goblin 30's
  record, which is counted like any awake goblin's.
- **Step 2 of tick 107**: it may act, but not with that skill until step 2 of tick 113.

The result is the one an eager cancellation at 103 would give, without writing a frozen goblin.

### 10.6 The fifth cast, interrupted

The kit has `QUICK_CAST_EVERY_N`, Fire, `N = 5`, and `casts = 4`. The content holds a Fire spell
with activation 3.
- **Clock 200**: the spell starts. `casts` goes 4 → 5, so the activation becomes 2 and `casts = 0`;
  `A = 202`.
- **Step 2 of tick 201**: a goblin's weapon hit knocks the Arcanist down, which interrupts the
  spell. Energy stays paid; the recharge counts from `t₀ = 201`.
- **Tick 202 runs.** The bonus is spent: the next Fire spell makes `casts` 1.

### 10.7 A guard crossing 50 % in the middle of an area (FX-40)

The content is illustrative and legal under §5.14. A carrier has two entries, both `SELF`, `RING_1`,
`FOES`:
- entry 1: `LIFE_STEAL` 20;
- entry 2: `DAMAGE` 50 (the carrier's one hit), guarded `BELOW_HALF`.

The source has 230 / 480 health (460 < 480). Two foes are adjacent, A on the lower tile index and B
on the higher, each with 100 health, and the source's strength equals their armor.
- **Guards**, read once: `BELOW_HALF` holds.
- **A**: entry 1 steals 20, so the source goes to 250 (500 > 480: now above half) and A to 80.
  Entry 2 applies because the guard was read before: 80 → 30.
- **B**: entry 1 steals 20, so the source is at 270 and B at 80. Entry 2 still applies: 80 → 30.

With a guard read per target, B would have taken no damage; FX-40 fixes the first reading.

### 10.8 An oil spent on a killing blow

The member drank an oil: `ON_ATTACK_CONDITION` Poison 10, `charges 2`, `d = 0`, so its deadline is
`MAX_CLOCK` (§3.4).
- **Hit 1**: the goblin survives. Poison is applied and charges go 2 → 1.
- **Hit 2**: it kills the goblin. No Poison is applied (step 7: the target is dead), but charges go
  1 → 0 (step 8), and the oil ends.
- An unused oil would have lasted until the instance closed, however long the member waited.
