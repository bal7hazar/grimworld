# 19 — Effects: the catalogue and the resolution order

> Status: **Draft v0.1** (DES-04, D-150). The closed list of what a skill, a condition, an item, a
> modifier or a goblin can do to an instance, and the exact order in which a tick resolves it.
> CBT-01 freezes the combat interfaces from it; the contracts and the client's TypeScript mirror
> (SPK-4, D-140) follow it to compute the same state from the same state.
> **Rules marked ⟨FX-n⟩ are escalations** the design documents do not settle: the text states the
> recommendation, which stands only once the project manager has decided it (D-150). Rules marked
> ⟨C⟩ are ordering conventions this document proposes for determinism; they are listed together as
> FX-0. Everything else is read from design/02, 03, 04, 05, 07, 15, 17, 18 and ENG-01, cited.
> No number here is a balance value: values are CNT-01's, DES-06's and BAL-01's.

## 1. Principles

| # | Principle | From |
|---|---|---|
| X-1 | **The catalogue is closed.** An effect kind not listed in §3 or §4 does not exist. New content picks kinds and fills values; a new kind is a change of this document and of CBT-01's interfaces | Pillar 6, S-6 |
| X-2 | Content refers to kinds by their **id** (§3, §4), which never changes meaning once frozen by CBT-01. One `elements/` file per kind (CONTEXT §4) | CONTEXT §4 |
| X-3 | Every effect is an integer function of the state and its parameters: no draw, no block data, no floating point | D-40, ADR-0002 |
| X-4 | **A rule never panics on a legal action** (D-140): every value is clamped to its bounds, every case a player can reach has a result (§6) | D-140 |
| X-5 | Percent modifiers of one quantity are **summed, then applied once**, the result truncated toward zero (D-140's rule for damage, applied here to every percent) | D-140 |
| X-6 | Durations become deadlines on the instance clock (M-2), bounded by `grimworld_logic::durations` | D-02, ENG-01 §3.1 |
| X-7 | Iteration is by lowest entity id, then lowest tile index (`x + 256 y`) | COMMON §4, design/04 |

**Words.** A **carrier** holds effects: a skill (`SKILL`, 3 effects), a potion (`ITEM`, 1 effect), a
modifier (`MODIFIER`), a set bonus (`ARMOR_SET`), a trap (a chunk object), a condition, a primary
attribute. A **source** is the actor whose carrier acts (member 0–7, or a goblin); the **holder** is
the actor an effect stays on. An **attack** is a weapon attack or an attack skill (design/03, kind
*Attack*); a **spell** is a skill of kind Spell, Hex or Enchantment. A **hit** is defined in §5.4.

## 2. What an effect entry holds

Every carrier writes its effects as **entries**. The entry is the unit CBT-01 freezes:

| Field | Values | Notes |
|---|---|---|
| `kind` | an id of §3 | — |
| `param` | the condition (§3.2), the damage type (§3.1), the stat, the guard (§2.2) | meaning by kind |
| `value` at rank 0 and at rank 12 | `u16` each | scaled linearly by the attribute rank, truncated: `v0 + (v12 − v0) × rank / 12` (design/03). A potion, a modifier, a trap of the terrain and a goblin's constant use `v0 = v12` |
| `duration` at rank 0 and at rank 12 | `u16` each, ≤ `MAX_BASE_DURATION` | scaled like `value`. Rending Cut (5…20 ticks), Warcry (5…11), Sidestep (2…6) scale their duration; Stone Skin (8…20) too. **ENG-01 lists one duration only: FX-24** |
| `target` | `SELF`, `FOE`, `ALLY`, `TILE` | the skill's `target` (design/03); an ally is an **entity id** (M-5), the source itself included |
| `shape` | §2.1 | — |
| `guard` | §2.2 | the effect applies only when its guard holds |

Scaling with signed differences: `v12 < v0` is allowed (a value that falls with rank); the product
is computed in `u32` and cannot overflow (`65,535 × 12`).

### 2.1 Shapes: which tiles, which actors, in which order

| Id | Shape | Tiles | Used by |
|---|---|---|---|
| 1 | `SINGLE` | the target entity's tile, or the target tile | almost every skill, potions |
| 2 | `ADJACENT` | the 6 tiles around the **source** | Cinder Ring (design/03: "adjacent foes") |
| 3 | `DISC_1` | the target tile and its 6 neighbours (7 tiles) | bombs (design/07), if their recipe says so |
| 4 | `NEARBY` | the tiles within 2 of the target (19) | design/04's "small area effects": **no MVP source; FX-21** |
| 5 | `IN_THE_AREA` | the tiles within 3 of the target (37) | design/04's "large area effects": **no MVP source; FX-21** |

- **Which actors.** An area effect has a **filter**, from the entry's `target`: `FOE` hits the
  source's foes on the tiles (members for a goblin; goblins for a member), `ALLY` its allies. There
  is no friendly fire: a filter never takes both. A dead goblin (remains) is neither.
- **Which tiles.** Walls hold no actor. A tile outside the window holds no simulated actor and is
  skipped (the window always holds the adventurer; design/02). Line of sight from the centre is
  not asked for areas of radius 1 (adjacent tiles see each other); for radius 2 and 3 it is FX-21.
- **In which order.** ⟨C⟩ The actors of an area are taken in **ascending tile index** (X-7; one
  actor per tile). For each actor, the entry's effects are applied in their order (1, 2, 3)
  before the next actor: **target-major**.
- **When the set is taken.** ⟨C⟩ At resolution, from the state at that moment: a foe that stepped
  into the ring during the activation is hit, one that stepped out is not (as in the baseline).

### 2.2 Guards

| Id | Guard | Holds when | Used by |
|---|---|---|---|
| 0 | `ALWAYS` | — | most effects |
| 1 | `HOLDER_ABOVE_HALF` | the source's health × 2 > its max health | "+15 % damage while health is above 50 %" (design/15, inscription; the kit's conditional damage and its threshold) |
| 2 | `HOLDER_BELOW_HALF` | the source's health × 2 < its max health | Second Wind, "more if below 50 % health" (FX-17) |
| 3 | `IN_STANCE` | the source holds a stance (§3.4) | insignia "+10 armor while in a stance" |
| 4 | `ENCHANTED` | the source holds an enchantment | insignia "+10 armor while enchanted" |

A guard reads the state **before** the entry applies (Second Wind tests health before its heal).
Exactly 50 % holds neither guard 1 nor guard 2 (strict comparisons, integers only).

## 3. The catalogue: effects that act (entries of skills, potions, traps)

Ids are proposals for CBT-01, grouped; the MVP ones first. **P** marks a kind with no MVP source.

### 3.1 Health

| Id | Kind | Parameters, units, bounds | Rule |
|---|---|---|---|
| 1 | `DAMAGE` | `param` damage type; `value` base damage, 0–65,535 | design/04's formula: `base × 2^((strength − armor) / 40)`, strength of a spell `3 × level`, armor per §5.3; the percent modifiers summed (X-5); result in [0, 65,535] (D-140). Damage types, ids in design/04's order: 1 slashing, 2 piercing, 3 blunt (physical), 4 fire, 5 cold, 6 lightning, 7 earth (elemental), 8 shadow, 9 holy (FX-23) |
| 2 | `ATTACK_BONUS` | `value` added to the weapon's base damage, 0–65,535 | only in an attack skill: the attack's base is weapon damage (after requirement, design/15) + this, then the formula. Cleave, Aimed Shot |
| 3 | `HEAL` | `value` health, 0–65,535; `guard` | `health = min(max health, health + value)`; nothing on a dead actor. Deep wound (P) lowers it by 20 % (X-5) |
| 4 | `LIFE_STEAL` | `value` health | ignores armor (design/04). ⟨C⟩ The target loses `s = min(value, its health)`, the source heals `s` (capped at its max). A target at 0 gives nothing |
| 5 | `REGENERATION` | `value` signed pips (−10…+10), a duration | a timed effect on the holder, summed in step 3 (§5.6). Restoratives' "heal over time", draughts' "+health regeneration" (design/07) |

### 3.2 Conditions

| Id | Kind | Parameters | Rule |
|---|---|---|---|
| 6 | `CONDITION` | `param` the condition; the **duration** is the entry's (scaled) duration | applies or refreshes (§5.5) |
| 7 | `CURE` | `param` the condition | ends it now: its deadline set to the current tick's end (§5.1). Field Dressing (Bleeding), restoratives' "remove a condition" (design/07). Curing an absent condition does nothing |

Conditions, ids in ENG-01's storage order, then the post-MVP ones (design/04, design/09):

| Id | Condition | Effect | MVP | Stored |
|---|---|---|---|---|
| 1 | Bleeding | −3 health pips (step 3) | yes | `MemberTimers`, `GoblinTimers` |
| 2 | Poison | −4 health pips | yes | same |
| 3 | Burning | −7 health pips | yes | same |
| 4 | Crippled | a move costs 2 ticks per tile (goblins: FX-15) | yes | same |
| 5 | Knocked down | cannot act (§6, FX-7); critical from any arc (design/04); interrupts (§5.7). **Does not stack with itself**: applied to an actor already knocked down, it does nothing, not even a refresh (design/04's words, set apart from the general refresh rule) | yes | same |
| 6 | Dazed | spells take +1 tick; a hit interrupts a spell in activation | **P** | none: FX-22 |
| 7 | Blind | an attack misses unless its target stands on the attacker's front tile | **P** | none |
| 8 | Weakness | −33 % weapon damage (a percent of X-5) | **P** | none |
| 9 | Deep wound | −20 % max health, −20 % healing received | **P** | none |

### 3.3 Energy and adrenaline

| Id | Kind | Parameters | Rule |
|---|---|---|---|
| 8 | `ENERGY` | `value` signed energy | `energy = clamp(energy + value, 0, max energy)`, in thirds in storage (design/03). Restoratives' "restore energy"; loss is Hexer's and Beguiler's energy denial (**P**) |
| 9 | `NEXT_SPELL_COST` | `value` energy off the next spell's cost; a duration | a glyph (Deep Draw): consumed when the next spell **starts** (paid or interrupted: ⟨C⟩); the cost never falls below 0 |

Adrenaline is changed by rules, not by entries: +1 strike to the source per weapon hit landed, +¼
to the target per hit taken (design/04), stored in quarter strikes; spent by adrenaline skills. Its
cap and its decay "out of combat" are FX-12.

### 3.4 Effects that stay on their holder (stance, enchantment, preparation, draught, oil)

| Id | Kind | Parameters | Rule | Sources |
|---|---|---|---|---|
| 10 | `ARMOR` | `value` armor; a duration | + armor while it lasts (§5.3) | Stone Skin; draughts' "+armor"; the Shaman's "shields" (FX-20) |
| 11 | `PENETRATION` | `value` percent (FX-9); a duration | + penetration on the holder's attacks while it lasts | Warcry |
| 12 | `HIT_PENETRATION` | `value` percent | penetration of **this** effect's hit only | Static Lash (25 %) |
| 13 | `BLOCK` | `value` charges 1–255; a duration | the holder blocks the next `value` attacks it can block (§5.4); the effect ends at 0 charges or at its deadline | Brace |
| 14 | `EVADE` | `param` 1 melee; a duration | the holder evades melee attacks (range 1) while it lasts; arcs: FX-11 | Sidestep |
| 15 | `ON_ATTACK_CONDITION` | `param` condition; `value` its duration; a duration **or** `charges` | each attack of the holder that hits applies the condition; charges count attacks that hit | Venom Coat (duration), oils "for N attacks" (charges) |
| 16 | `MOVEMENT` | FX-18 | draughts' "+movement for N ticks" | design/07 |

Skill kinds decide what stays and how (design/03): a **stance** is instant and one at a time (a new
stance ends the held one, whatever its source); an **enchantment** stays on an ally, a **hex** on a
foe (both "removable": no MVP skill removes them; removal would be a kind of its own, **P**, not
catalogued until a source names it); a **preparation** modifies the holder's own attacks; a
**glyph** the next spell. A **shout** is instant, cannot be interrupted, and **alerts every pack
within 8 tiles** (design/18: "a shout, or a fight, within 8 tiles"; design/04, earshot).

### 3.5 Control and placement

| Id | Kind | Parameters | Rule | Sources |
|---|---|---|---|---|
| 17 | `INTERRUPT` | — | ends the target's activation in progress (§5.7) | **P**: Champion, Beguiler (design/05, design/03). No MVP skill interrupts by this kind; in the MVP an interrupt is a knock-down (§5.7) |
| 18 | `TRAP` | the trap's effects are the skill's other entries | places a trap on the target tile; when a foe of the placer **enters** it, the other entries apply to that foe, once (FX-14) | Snare; the Trapper (design/05) |

**No displacement exists.** No design document names a push, a pull or a teleport; a knock-down
does not move its target. **No summon exists in the MVP**: the Lord's "calls reinforcements" and the
Gravecaller's minions (design/05, design/03) need an id space (FX-20).

### 3.6 Post-MVP kinds named by the documents, catalogued for closure

| Id | Kind | Named by | What is still missing |
|---|---|---|---|
| 19 | `REVIVE` | design/07, rare potions: "revive once in the expedition" | FX-18: when it triggers (at 0 health, automatically?) and with how much |
| 20 | `REVEAL_FLOOR` | design/07, rare potions | FX-18: the reveal bound (≤ 3 chunks an action, design/02) |
| 21 | `ON_SKILL_USE` | design/05, Hexer: "punishes skill spam" | a hex that deals its value when the holder starts a skill; values and shape DES-06's |
| 22 | `SUMMON` | design/05 (Lord), design/03 (Gravecaller) | FX-20: entity ids |
| — | Paladin "protects the lord", Beguiler "illusions" | design/05, design/03 | **not catalogued**: no document says what they do. They wait for their design (FX-20) |

## 4. The catalogue: passive effects (modifiers, attributes, set bonuses, weapons)

Passive effects are read, never scheduled. Most are **flattened into the snapshot** at entry
(`MemberStats`, `MemberKit`, ENG-01 §3.2: equipment cannot change during an expedition, design/15);
the others are tested at the moment they matter. A `MODIFIER`'s `effect` field is one of these ids.

| Id | Passive | Unit, bounds | When it acts | Sources |
|---|---|---|---|---|
| 40 | `MAX_HEALTH` | ± health | snapshot | design/15: suffix of Fortitude +30, insignias +15/10/5, runes +30…+50 and −35/−75; "damage with a drawback" is 44 |
| 41 | `ARMOR` | + armor | snapshot; with a guard (3, 4), at each hit | design/15: +4…+5; insignia +10 while in a stance / while enchanted; shield rating; personalisation +10 % of a rating |
| 42 | `ARMOR_VS` | + armor against a damage type | at each hit | design/15: +4…+7 against a type; class innate +20 physical (heavy), +30 elemental (medium). FX-23 |
| 43 | `MAX_ENERGY`, `ENERGY_REGEN` | ± energy, ± pips | snapshot | design/15 (light armor's innate), Wellspring (design/03), "−5 energy" drawback, energy-on-hit's regeneration cost |
| 44 | `DAMAGE_PERCENT` | ± percent; `guard` | at each attack (X-5) | inscription "+15 % while health above 50 %", conditional damage +10…+15 %, "+15 % damage, −5 energy" |
| 45 | `HEALTH_REGEN` | ± pips | snapshot, summed in step 3 | life steal's cost (design/15) |
| 46 | `DAMAGE_TYPE` | a damage type | snapshot | design/15: damage type change; staff "by attribute" (design/04) |
| 47 | `PENETRATION` | percent (FX-9) | at each attack | design/15 "+2…+4 %, always"; Might, on attack skills (design/03) |
| 48 | `LIFE_STEAL_ON_HIT` | health a hit | at each weapon hit (kind 4's rule) | design/15 |
| 49 | `ENERGY_ON_HIT` | energy a hit | at each weapon hit | design/15 |
| 50 | `CONDITION_DURATION` | percent, for one condition | at each condition the holder inflicts (`effective_duration`, capped +50 %) | prefix "Rending: bleeding you inflict lasts 33 % longer" |
| 51 | `ENCHANT_DURATION` | percent | at each enchantment the holder casts | +10…+20 % (design/15) |
| 52 | `KNOCKDOWN_FLAT` | + ticks | at each knock-down inflicted (flat, capped +3) | set bonus "knock-downs you inflict last 1 tick longer" |
| 53 | `ADRENALINE_EVERY_N` | N | at each weapon hit (the `hits` counter) | "every 10th to 5th hit gives double adrenaline" |
| 54 | `QUICK_CAST_EVERY_N` | N, one attribute | at each spell of that attribute (the `casts` counter): 1 tick less, **never below 1** (design/03: "minimum 1 tick for anything with a non-zero activation") | design/15 |
| 55 | `ATTRIBUTE` | ± ranks | snapshot (the bar's ranks) | runes +1…+3; "only the highest rune of an attribute counts, every penalty counts" (design/15) |
| 56 | `ENERGY_COST` | − energy of one profession's skills | at each skill start, never below 0 | Fieldcraft (design/03) |
| 57 | `HALVE_FIRST_HEAVY_HIT` | once an instance | at a hit (FX-19) | set bonus of *Hob-breaker* (design/15) |
| 58 | `BASE_DAMAGE_PERCENT` | + percent of the weapon's base | snapshot | personalisation +20 % (design/15) |
| 59 | `HEAL_BONUS`, `ACTIVATION_PERCENT`, `ENERGY_ON_DEATH` | — | **P** | Grace, Quickness, Harvest (design/03) |
| 60 | `CASTE_ARMOR`, `ATTACK_SPEED` | — | **P** | affixes *Scarred*, *Rabid* (design/05) |

**Weapons and arcs are rules, not entries** (design/04): the axe's +25 % from the rear-side and back
arcs and the critical +40 % are percents of X-5; flank ignores blocks; the maul's 2 ticks and the
bow's line of sight are the weapon's. A goblin's weapon is its caste's (`CASTE.weapon`).

## 5. The resolution order

### 5.1 The clock, deadlines and counting

design/02 runs a world tick in five steps. This document numbers them and adds step 0:

| Step | What | Order between actors |
|---|---|---|
| 0 | The clock advances: `clock = T`, the number of this tick | — |
| 1 | Activations whose deadline is `T` resolve (§5.7) | ascending entity id: members (0–7) first, then goblins |
| 2 | Awake goblins act (design/04, *Goblin AI*) | ascending entity id; each sees the state the previous ones left |
| 3 | Conditions, regeneration and degeneration (§5.6) | every member and every awake goblin, ascending entity id; each actor's change depends only on its own state, so the order does not change the result |
| 4 | Durations and recharges end (nothing is written: a deadline at or below the clock reads as ended) | — |
| 5 | Defeat and objective checks (§5.8) | — |

Between two ticks the clock reads `c`, the last tick run; the adventurer's action is applied there
(the **action phase**; design/02: "apply the adventurer's action, then run `n` world ticks").

**Counting (⟨C⟩, with FX-1 and FX-2).** A timer counts the executions of **the step that consumes
it**, starting with the first one after it is set:

| Timer | Consumed by | Set at clock reading `x` (action phase: `x = c`; in a tick: `x = T`) | Stored deadline | Active / due when |
|---|---|---|---|---|
| Timed effect, condition, of `d` ticks | step 4 | `t₀` = the first tick whose step 4 it meets: `c + 1` in the action phase, `T` in steps 1–3 | `D = t₀ + d − 1` | at any point of tick `T′` with `T′ ≤ D`; in the action phase at clock `c` with `c < D` |
| Activation of `n` ticks | step 1 | the first tick whose step 1 comes after it: `c + 1` in the action phase, `T + 1` if started in step 2 of tick `T` | `A = first + n − 1` | resolves in step 1 of tick `A` |
| Recharge of `r` ticks | step 4, from the end of the activation (FX-2) | `t₀` as for a timed effect, taken where the activation ends (its resolution, its interruption, or its use for an instant skill) | `R = t₀ + r − 1` | usable in the action phase at clock `c ≥ R` (a goblin: in step 2 of tick `T′ > R`) |

So a condition of `d` ticks degenerates exactly `d` times (in steps 3), whether it was applied in the
action phase or by a goblin in step 2; a 1-tick spell of the adventurer resolves in step 1 of its
action's first tick; a goblin's 3-tick wind-up started in step 2 of tick `T` resolves in step 1 of
`T + 3`, after the adventurer's next **three** actions (design/04: "exactly three actions"). An
effect that "ends now" (a cure, a spent block) gets `D = x`, which is no longer active in the next
test. Deadlines stay below `MAX_CLOCK` by ENG-01's `LAST_TICK`.

### 5.2 The adventurer's action

In the action phase, in this order (design/02, *Executing a batch*; design/04, *Actions*):

1. **Legality**, against the state as it is: the list of design/02 (tile blocked, out of range or
   of sight, not enough energy or adrenaline, recharging, a second turn or instant skill between two
   ticks, acting while knocked down, an item not in the belt; an attack skill without its weapon,
   design/03). An illegal action is invalid: the batch stops, nothing of it runs.
2. **Costs are paid** at once (⟨C⟩): energy after reductions (kind 56, a glyph), adrenaline; the
   glyph is consumed.
3. **Facing** is set (design/04): toward the moved-to tile, the attack's or the targeted skill's
   target. ⟨C⟩ For a target not adjacent, the direction of the first step of the hex line to it.
4. **Resolution.** A move, a weapon attack, an attack skill without activation (FX-5), a potion
   and an instant skill resolve **now**, with the rules of §5.3–§5.5. A skill with activation `n ≥ 1`
   starts its activation (§5.1): it resolves in step 1 of its `n`-th tick.
5. **Then `n` world ticks run**, `n` the action's tick cost (design/04; Crippled makes a move cost 2).

### 5.3 One hit: the order inside an attack or a damaging effect

For one source, one target and one damaging entry (a weapon attack, an attack skill, `DAMAGE`):

1. **Arc** (design/04): the tile the source stands on, or, at range, the tile the line of sight
   arrives from, taken in the target's arcs around its facing. Knocked down or asleep: critical from
   any arc.
2. **Miss, block, evade** (§5.4). If the attack is stopped, **nothing else of it applies** (no damage,
   no on-hit effect, no adrenaline, not a hit).
3. **Armor** = the target's armor (snapshot or caste) + `ARMOR` effects + guarded armor (41) +
   `ARMOR_VS` of the damage type; then penetration: `armor − ⌊armor × p / 100⌋`, `p` the sum of the
   source's penetration percents (47, 11, 12, capped at 100; FX-9); never below 0 (D-140).
4. **Damage** = `⌊base × table(strength − armor) / 2^16⌋`, then the **sum** of every percent (critical
   +40, axe +25, weakness −33, `DAMAGE_PERCENT` whose guard holds; never below −100) applied once,
   truncated; clamped to [0, 65,535] (D-140). Then FX-19's halving, if held.
5. **Apply**: `health = health − damage`, saturated at 0.
6. **On-hit effects, target side**, only if the target is still above 0: the entry's other effects
   (target-major, §2.1), `ON_ATTACK_CONDITION`, life steal (kind 4), the interrupt of a knock-down
   (§5.7).
7. **On-hit effects, source side**, for any hit, the target dead or not: adrenaline (+1 strike, or +2
   on the `hits` counter's `N`-th hit, 53), `ENERGY_ON_HIT`, the counters; the target's +¼ strike if
   alive.
8. **Death** of the target at 0 (§5.8). A goblin hit while asleep or on watch notices: its pack is
   engaged (design/18); a hit is also "a fight" for the alert of packs within 8 tiles.

Several targets (an area) run steps 1–8 for each, in ascending tile index; the source's side (step
7) accumulates in that order, which fixes the counters.

### 5.4 Block, evasion, miss, and what a hit is

| Case | Result | From |
|---|---|---|
| The target holds `BLOCK` with charges, the attack comes from its front or front-side arc | blocked; one charge spent | design/03 (Brace), design/04 (arcs) |
| Same, from the rear-side (flank) or the back | not blocked; **no charge spent** (the block is "ignored") | design/04 |
| The target is knocked down | FX-7: recommendation, it cannot block | — |
| A spell | cannot be blocked or evaded (only attacks are: design/03 names attacks) | design/03, design/04 |
| `EVADE` (melee) against a melee attack | evaded; from the rear-side or back: FX-11 | design/03 (Sidestep) |
| Blind (P) | an attack misses unless the target is on the attacker's front tile | design/04 |
| The target is asleep | the first hit cannot be blocked (design/04); a goblin asleep holds no stance anyway | design/04 |

**A hit** (FX-10) is an attack or a damaging entry that reaches its target and is not blocked,
evaded or missed, whatever damage it deals (0 included). Degeneration, life steal and a trap's
entries are not hits. Hits count for adrenaline, for Dazed (P) and for mining's interrupt
(design/17: "interrupted by any hit taken").

### 5.5 Conditions and timed effects applied, refreshed, stacked

- **Different conditions stack** on one actor (each has its own deadline; their pips are summed,
  §5.6). The **same** condition does not stack: reapplying it **refreshes** (design/04). FX-6: the
  recommended refresh is `D = max(D_old, D_new)` (a shorter reapplication does not shorten it);
  the other reading replaces the deadline.
- Knocked down does not stack with itself and is not refreshed while held (§3.2).
- A duration inflicted is `effective_duration(base, percent, flat)` (ENG-01 §3.1): the source's
  `CONDITION_DURATION` for that condition, `ENCHANT_DURATION` for an enchantment, `KNOCKDOWN_FLAT`.
- **Timed effects** (§3.4) are held in effect slots: a member has 4 (`MemberEffects`), a goblin 1
  (`GoblinTimers`). The same skill again refreshes its slot (FX-6's rule) and resets its charges; a
  new stance takes the held stance's slot. A new effect with every slot taken: FX-13.
- A dead goblin takes no condition and no effect.

### 5.6 Step 3: regeneration and degeneration

For each member and each **awake** goblin, ascending entity id:

1. health pips = health regeneration of the snapshot (or the caste's) + active `REGENERATION`
   effects − 3 (Bleeding) − 4 (Poison) − 7 (Burning), each counted once if active; **the sum is
   clamped to [−10, +10]** (design/03), then × 2 health; health clamped to [0, max].
2. energy += its regeneration in thirds (1 pip = 1 energy every 3 ticks; design/03), clamped to
   [0, max].
3. An actor brought to 0 here dies (§5.8), after every actor of the step has been processed.

**A frozen goblin does not run step 3** (design/02: outside the awake set, goblins are frozen). Its
deadlines are on the instance clock, so a condition that ends while it is frozen is lost, not
delayed (D-02; ⟨C⟩ as a reading).

### 5.7 Activation and interrupts

- An activation resolves in step 1 of its deadline tick (§5.1; FX-1). At resolution the skill's
  target must still be legal (in range, in sight, alive): ⟨C⟩ if not, the skill does nothing and its
  costs stay paid (as an interrupt).
- **What interrupts** an activation in progress: `INTERRUPT` (P); **a knock-down** (design/14's
  quest *The brute at the bridge*: "interrupt its wind-up" with Skullring, a knock-down); a hit
  while Dazed, for a spell (P); a hit, for mining (design/17). A shout cannot be interrupted
  (design/03); instant skills have no activation to interrupt.
- **What an interrupted activation spends and keeps** (design/04): the energy stays paid, the skill
  goes on recharge (from the interruption: FX-2), its effects do not happen, a glyph consumed at its
  start stays consumed. Adrenaline: FX-4. The adventurer's remaining ticks: FX-3.
- A goblin whose activation resolves in step 1 has acted for this tick: it does not act again in
  step 2 (⟨C⟩; design/04: "once per elapsed tick").
- A goblin killed before its deadline never resolves its activation.

### 5.8 Zero health, deaths, defeat

- **A goblin at 0 health dies at once**, at the step of §5.3 or §5.6 that brought it there: its AI
  state becomes dead (its record is its remains, ENG-01), it leaves the awake set, it no longer
  acts, takes effects, blocks a tile for movement (⟨C⟩: remains do not block, design/04 "walking on
  loot picks it up") or resolves an activation. `GoblinKilled` is emitted in resolution order, and
  kill credit goes to the source's member through the contributors' function (M-4).
- **Simultaneous deaths** are ordered by the resolution order: an area in tile order (§2.1), step 3
  in entity-id order. Nothing of the MVP reacts to a death (Harvest is **P**), so the order only
  fixes the events' order and the source's counters.
- **The adventurer at 0**: FX-8. Recommendation: in the action phase and in steps 1–2 (sequential),
  the moment a member's health reaches 0 it is defeated and **the tick stops** there; in step 3 the
  step completes for every actor (a goblin killed by degeneration in that step still dies and
  counts), then the tick stops. Health at 0 is never raised again (no heal on a defeated member).
  Step 5 writes the status (design/02: *Defeated*).
- Objective checks (step 5) read the state after the tick; a tick stopped by defeat still records
  the kills made before the stop (D-04: progress is kept).

## 6. Edges (D-140)

Every case a player can reach, with its result. "Invalid" means the action is refused (design/02:
the batch stops there, no revert); everything else runs.

| Edge | Result |
|---|---|
| Energy after reductions below 0 | 0 |
| Activation after reductions below 1 for a non-instant skill | 1 (design/03, D-31) |
| Scaled value or duration with a rank above 12 (runes reach about 16, design/15) | ⟨C⟩ the rank is **capped at 12** for scaling; the scale is defined between 0 and 12 only (design/03: "linear between rank 0 and rank 12") |
| Effective duration | `effective_duration`'s caps (+50 %, +3 flat), never above `MAX_DURATION` (ENG-01) |
| Heal above max health; energy above max | clamped |
| Health pips beyond ±10 | clamped (design/03) |
| Armor below 0 after penetration; penetration percents above 100 | 0; 100 |
| Percent sum below −100 | −100 (D-140): damage 0 |
| Damage outside [0, 65,535] | nearest bound (D-140) |
| A 0-damage hit | still a hit (§5.4) |
| Life steal from a target with less health than its value | the target's health (kind 4) |
| A condition cured that is not held; a condition applied to a dead goblin | nothing |
| Knocked down applied to the knocked down | nothing (design/04) |
| The adventurer knocked down | FX-7: recommendation, the only legal action is Wait |
| A skill's target dead, out of range or out of sight at resolution | nothing happens, costs stay paid (§5.7) |
| An area with no actor on its tiles | nothing; costs paid; a shout still alerts |
| A block with 0 charges left | the effect has ended (§3.4) |
| A new stance while one is held | the new one replaces it |
| All effect slots taken | FX-13 |
| A trap placed where the chunk holds 3 objects; on an occupied tile; on a wall | FX-14: recommendation, the skill is invalid on that tile |
| A glyph and an interrupted spell | consumed at the spell's start |
| Adrenaline beyond its cap | FX-12 |
| Two actors' activations due in the same step 1 | entity-id order; a goblin killed by an earlier one does not resolve |
| An effect on a goblin outside the window | none can reach it: every shape is centred inside the window and radius ≤ 3 is proposed only with FX-21 |
| A goblin whose own tile is not marked occupied | cannot happen (design/04): asserted |

## 7. What CBT-01 freezes from this document

- **Enumerations with stable ids**: effect kinds (§3, ids 1–22), passive kinds (§4, ids 40–60),
  conditions (§3.2, 1–9), damage types (§3.1, 1–9), shapes (§2.1), guards (§2.2), targets, skill
  kinds (design/03's order: Attack, Spell, Hex, Enchantment, Stance, Shout, Signet, Preparation,
  Trap, Glyph).
- **The effect entry** of §2 inside `SKILL` (3 entries), `ITEM`'s potion effect (1 entry, rank-free),
  `MODIFIER`'s effect (a passive id, value range, guard), `ARMOR_SET`'s two bonuses (passive ids).
- **The pipeline's functions**, pure (state in, state out), in the order of §5: `apply_action`,
  `tick` (steps 0–5), `resolve_hit` (§5.3), `apply_entry`, `regenerate` (§5.6), `interrupt` (§5.7),
  `kill` (§5.8), with the counting of §5.1.
- The additions to ENG-01's records listed in FX-24, once decided.

### 7.1 The caste sheet's shape (DES-06 fills the values)

| Field | Type | Notes |
|---|---|---|
| caste id, tier | `u16`, 1–6 | design/05 |
| AI profile | `swarm`, `kite`, `flank`, `support`, `brute`, `caster`, `boss` | design/05 |
| health multiplier | percent | on `100 + 20 × (level − 1)` (design/05: "same formulas as adventurers") |
| armor; armor vs physical, vs elemental | `u8` each | FX-23 for per-type bonuses |
| weapon | a `BASE` id (damage, damage type, ticks, range) | design/04 |
| energy, energy regeneration | `u8`, pips | a caster goblin pays energy like an adventurer (design/05: "same skill system") |
| 4 skills, **in priority order** | `SKILL` ids | design/04: "first usable skill in its priority list" |
| attribute rank of its skills | 0–12 | scales its entries (§2); by level or fixed, DES-06's |
| flee threshold | percent of max health | `swarm`: 30 % (design/05) |
| loot table, boss flag | ids | ENG-01 `CASTE` |
| movement | tiles a move | **P**: Wolf rider (FX-20) |
| boss phases | health thresholds → skill sets | **P** (`boss` profile) |

## 8. Coverage: every source the documents name, and its kinds

| Source | Document | Kinds (§3, §4) |
|---|---|---|
| Cleave | design/03 | 2 |
| Rending Cut | design/03 | 6 (Bleeding, duration scaled) |
| Skullring | design/03 | 6 (Knocked down, 2 ticks); interrupts (§5.7) |
| Second Wind | design/03 | 3, 3 guarded `HOLDER_BELOW_HALF` (FX-17) |
| Brace | design/03 | 13 (stance) |
| Warcry | design/03 | 11 (shout: alerts within 8) |
| Aimed Shot | design/03 | 2 (FX-5) |
| Hamstring Shot | design/03 | 6 (Crippled) |
| Venom Coat | design/03 | 15 (Poison, 24; preparation) |
| Snare | design/03 | 18 + 6 (Crippled) + 1 (FX-14) |
| Field Dressing | design/03 | 3, 7 (Bleeding) |
| Sidestep | design/03 | 14 (stance; FX-11) |
| Ember Bolt | design/03 | 1 (fire) |
| Cinder Ring | design/03 | 1 (fire, `ADJACENT`, foes), 6 (Burning) |
| Rime Shard | design/03 | 1 (cold), 6 (Crippled: FX-16) |
| Stone Skin | design/03 | 10 (enchantment) |
| Static Lash | design/03 | 1 (lightning), 12 (25 %) |
| Deep Draw | design/03 | 9 (glyph) |
| Might, Fieldcraft, Wellspring | design/03 | 47, 56, 43 |
| Grace, Harvest, Quickness | design/03 | 59 (**P**) |
| The five MVP conditions; Dazed, Blind, Weakness, Deep wound | design/04, design/09 | §3.2 (P for the last four) |
| Arcs, critical, flank, axe, maul, bow, staff | design/04 | rules of §5.3; 46 |
| Adrenaline, energy, regeneration | design/04, design/03 | rules of §3.3, §5.6 |
| Runt, Slinger | design/05 | weapon only (AI: flee, lowest armor) |
| Skirmisher | design/05 | 6 (Bleeding) through its skills |
| Shaman | design/05 | 3 on allies; "shields": 10 (FX-20) |
| Hobgoblin | design/05, design/04 | an attack skill with activation 3 (FX-5), 1 |
| Trapper, Wolf rider, Hexer, Champion, Paladin, Lord | design/05 (**P**) | 18, 6; 6 (Knocked down), movement (FX-20); 21, 8; 13/14, 17, adrenaline; 3, "protects" (FX-20); shout to allies (`ALLY` within 8: FX-21), 22 |
| Affixes *Scarred*, *Rabid* | design/05 (**P**) | 60 |
| Restoratives: heal over time, remove a condition, restore energy | design/07 | 5, 7, 8 |
| Draughts: +armor, +health regeneration, +movement | design/07 | 10, 5, 16 (FX-18) |
| Oils: a condition for N attacks | design/07 | 15 (charges) |
| Bombs: area damage or a condition on a tile | design/07 | 1 or 6, `DISC_1` or `SINGLE`, `TILE` (FX-18) |
| Rare: revive, reveal the floor | design/07 (**P**) | 19, 20 (FX-18) |
| Prefix: condition duration +33 % | design/15 | 50 |
| Damage type change | design/15 | 46 |
| Life steal with a health-regeneration cost | design/15 | 48, 45 |
| Energy on hit with an energy-regeneration cost | design/15 | 49, 43 |
| Health +10…+30; armor +4…+5; armor vs a type +4…+7 | design/15 | 40, 41, 42 |
| Enchantment duration +10…+20 % | design/15 | 51 |
| Conditional damage +10…+15 %; +15 % damage −5 energy | design/15 | 44 (guarded), 44 + 43 |
| +2…+4 % armor penetration; double adrenaline every N; quicker cast every N | design/15 | 47, 53, 54 |
| Insignias: health; +10 armor in a stance / enchanted | design/15 | 40; 41 guarded |
| Runes: +1…+3 attribute, −35/−75 health; +30…+50 health | design/15 | 55, 40 |
| Personalisation | design/15 | 58; 41 |
| *Hob-breaker*: knock-downs +1 tick; the first attack under 50 % halved | design/15 | 52; 57 (FX-19) |
| Traps of the terrain | design/18 | 18 (FX-14) |
| Veins: mining, interrupted by a hit | design/17, design/18 | §5.4, §5.7 (not an effect: an activation of `mine`) |
| The Rift Heart | design/17 | a caste (Skirmisher, Shaman, Hobgoblin in the MVP): its skills; no effect of its own |
| Shouts and fights alerting packs within 8 | design/18 | shout rule (§3.4); §5.3 step 8 |
| Chests, remains, nodes, collectors, levers, braziers, landmarks | design/18, design/15 | **not effects**: Fate actions or objectives, outside this catalogue |

## 9. Escalations (open; the project manager decides, D-150)

The questions, options and recommendations are in the task's report and are summarised here so
that the document stands alone. Until decided, CBT-01 freezes the recommendation only where the
project manager says so.

| # | Question | Recommendation |
|---|---|---|
| FX-0 | The ⟨C⟩ conventions of this document | as written |
| FX-1 | An activation resolves in step 1 of its `n`-th tick (design/02) or at the end of it (design/04's words)? | step 1 (design/02's order) |
| FX-2 | A recharge counts from the end of the activation or from the use? | from the end of the activation (resolution or interruption) |
| FX-3 | The adventurer interrupted: do the action's remaining ticks run? | yes, all `n` run |
| FX-4 | An interrupted adrenaline skill: adrenaline spent? | spent, like energy |
| FX-5 | An attack skill's tick cost and landing | ticks = max(weapon's, activation); lands at once without activation, at resolution with one |
| FX-6 | Refresh: `max(old, new)` or replace? | `max` |
| FX-7 | Knocked down: what may the adventurer do; can the knocked down block? | only Wait; cannot block |
| FX-8 | The adventurer at 0 mid-tick | §5.8 |
| FX-9 | Penetration: flat (design/04's formula) or percent (every numbered source)? | percent, summed, capped at 100 |
| FX-10 | What is a hit | §5.4 |
| FX-11 | Does flank ignore Sidestep's evasion? | yes, as a block |
| FX-12 | Adrenaline's cap; "out of combat" | cap: the highest adrenaline cost on the bar; out of combat: no goblin engaged with the member |
| FX-13 | Effect slots full | the new effect replaces the one with the earliest deadline |
| FX-14 | Traps: terrain traps' effect, lifetime, single trigger, full chunk, the param | a `SKILL` id per trap feature; until triggered or the instance closes; once; invalid when full |
| FX-15 | A crippled goblin | moves, then skips its next act |
| FX-16 | Rime Shard's slow is Crippled? | yes |
| FX-17 | Second Wind's "more" | a second `HEAL` guarded `HOLDER_BELOW_HALF` |
| FX-18 | Potions: "+movement", revive, reveal the floor, bombs' target | report |
| FX-19 | The set bonus's halving and D-140's sum | after the sum, on the final damage |
| FX-20 | Shaman "shields", Paladin "protects", summons, Wolf rider's speed | report |
| FX-21 | Areas of radius 2 and 3 | none in MVP content; ENG-01 §9.2's bound first |
| FX-22 | Storage of the four post-MVP conditions | report |
| FX-23 | Shadow and holy; armor against one damage type | report |
| FX-24 | Additions to ENG-01's records | report |
