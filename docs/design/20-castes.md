# 20 — Caste sheets, and the per-source bounds of every statistic

> Status: **Draft v0.1** (DES-06, D-157 G, D-159). Numbers in the sheets are **initial values**
> BAL-01 tunes with the balance simulator. Bounds marked **proposed** are this document's
> recommendations, escalated as **DS-n** (§5) for the project manager; everything else is read from
> the document cited. Nothing here changes a rule of design/19.
>
> **Why a new document and not an amendment of design/05.** design/05 is the bestiary's principle
> (castes, packs, profiles) and stays short; the sheets are CBT-01's record shape filled field by
> field, and the bounds concern the adventurer as much as the goblins. They are read by CBT-01's
> follow-ups, CBT-02, ENG-07, BAL-01 and CNT-01, as design/19 is read beside design/04.

**Order.** §1 is the bounds, usable on its own by CBT-02 and CBT-01's validators before the sheets.
§2 the caste sheets of the MVP, §3 their skills and priority lists, §4 the castes after the MVP, §5
the escalations, §6 the acceptance tests the validators and the flattening owe.

## 1. The per-source bounds (D-157 G)

A **statistic** is a quantity an actor carries and a rule reads (design/19 §7.2 and §7.3). A
**source** is one thing that can add to it. A **per-source bound** is the range `[lo, hi]` one source
can add, **signed** where a source can subtract; the **total** is the sum of the bounds of every
source an actor can hold at once. A total must fit the field that stores it (the snapshot's words,
ENG-01 §3.2 as CBT-01 repacked them), or be computed at use in a width that holds it.

### 1.1 The sources, and how many an adventurer holds at once

| Code | Source | At once | From |
|---|---|---:|---|
| **B** | The build: level (1–20), primary profession, attribute ranks 0–12 | 1 | design/03 |
| **C** | The armor class's innate bonus | 1 | design/15 *Rating* |
| **H** | A **held-item** modifier slot: the weapon's prefix, suffix, inscription; the off-hand's suffix, inscription (a wand has no prefix; a two-handed weapon has no off-hand) | **5** | design/15 *Modifier slots* |
| **I** | An insignia, one per armor piece | **5** | design/15 *Insignias and runes* |
| **R** | A rune, one per armor piece | **5** | same |
| **S** | A set bonus (one set can reach 3 of 5 pieces) | **2** | design/15 D-45 |
| **P** | Personalisation: +20 % weapon base damage, +10 % of a rating | weapon, shield, 5 pieces | design/15 D-48 |
| **E** | Effects held in play (a member: 4 slots; a goblin: 1), conditions (5 in the MVP), instant effects | — | design/19 §3, §7.2 |
| **K** | A goblin's caste sheet, with its level | 1 | design/19 §7.3 |

A modifier carries a **benefit and a cost** (design/19 §4): a source's contribution to a statistic is
the **sum of its passives on that statistic**, and the bound applies to that sum (as
`PassiveAssert::assert_contributions` already does for damage, penetration and guarded armor). A boss
piece's fixed insignia and rune (design/15 D-45) occupy the I and R rows. So an adventurer holds at
most **17 passive sources**: 5 H + 5 I + 5 R + 2 S.

**"Proposed"** below means a document names no value or no restriction and this document recommends
one (DS-1). A source not listed on a row adds **0**: the pipeline refuses that passive on it.

### 1.2 The adventurer's snapshot

| # | Statistic (field, width) | Per-source bound | Total | Fits |
|---|---|---|---|---|
| 1 | **Max health** (`MemberStats.max_health`, `u16`; `maxima` reads it) | B: `100 + 20 (L − 1)`, 100…480 (design/03). H: 0…+30 (design/15: health +10 to +30). I: 0…+15 (design/15: +15/10/5 by piece). R: **−75…+50** (design/15: +30 to +50; the cost of "+3 attribute, −75 health"). S: −75…+50 (proposed, as a rune). A health rune of one kind counts once (FX-43, D-157 D) | **−425…+1,055** (L = 1 with 5 costly runes and 2 costly bonuses; L = 20 with every maximum). Equipment alone: **−525…+575** | top: ✓ (≤ 65,535). **Bottom: below 1 at low levels** → DS-2. `MemberKit.health_bonus` is `u16` and cannot hold the equipment's signed sum → DS-3 |
| 2 | **Max energy** (`MemberStats.max_energy`, `u8`; in play `MemberState` energy in thirds, `u16`) | B: profession 20/25/30 (design/03); *Wellspring* ≤ +3 per rank, rank ≤ 15: ≤ +45 (proposed; value BAL-01). C (light armor): 0…+20 (proposed; design/15 names "+ energy" without a value). H, S: −5…+5 (design/15: "−5 energy" as a cost; a benefit proposed at the same size). I, R: 0 | **−15…+130** | top: ✓ (≤ 255; 390 thirds ≤ `u16`). **Bottom: below 0** for a Vanguard with seven "−5 energy" costs → DS-2 |
| 3 | **Energy regeneration** (`MemberStats.energy_regen`, `u8`, pips) | B: profession 2/3/4 (design/03). C (light): 0…+1 (proposed). H: −1…0 (energy on hit's cost, design/15; −1 proposed). S: −1…+1 (proposed). I, R: 0 | **−5…+7** | top ✓. **Bottom: the field is unsigned** → DS-2 |
| 4 | **Health regeneration**, snapshot part (`MemberStats.health_regen`, `u8`, pips + 10, 0–20) | H: −1…0 (life steal's cost, design/15; −1 proposed). S: −1…+1 (proposed). Others 0 | **−7…+2** | ✓ (−10…+10) |
| 4′ | Health regeneration **in play** (design/19 §5.8, computed, then clamped to ±10) | the snapshot (row 4); E: 4 `REGENERATION` effects, −10…+10 each (§3.1); conditions −3, −4, −7 | **−61…+42** before the clamp | computed in `i8` (or wider) ✓ |
| 5 | **Unguarded armor** (`MemberBar.armor`, `i16`) | B/C: the weighted rating of the pieces, ≤ 255 (design/15's maximum is 80); the shield's rating ≤ 255 (design/15: 8→16). P: ≤ 25 on each (F-21). Every `ARMOR` passive: −255…+255 (validator, §7.2; design/15 names +4…+5) | **±9,995** (F-21, settled by CBT-01) | ✓ (`MAX_UNGUARDED_ARMOR`) |
| 6 | **Guarded armor**, in a stance / enchanted (`MemberKit`, 2 × `i8`) | I, S: −18…+18 each (§7.2; design/15 names +10) | **±126** each | ✓ |
| 5′ | Armor **at a hit** (design/19 §5.5 step 3) | rows 5, 6, 7 + E: 4 `ARMOR` effects, 0…255 each | **−10,247…+11,330** before D-140's floor at 0 | computed in `i32` ✓ |
| 7 | **Armor against a damage type**, × 9 (`MemberStats.armor_vs`, 6 bits each) | C: +20 physical, +30 elemental (design/15). Any source: 0…+7 (design/15: +4 to +7; proposed as the per-source bound) | 30 + 17 × 7 = 149 | **saturated at 63** by rule (FX-23) ✓ |
| 8 | **Attribute rank** of each bar skill (`MemberStats.ranks`, 4 bits each) and the primary rank (`u8`) | B: 0…12 (design/03). R: +1…+3 (design/15), **only the highest rune of an attribute counts**. H, I, S: 0 (proposed: design/15 names attribute bonuses only on runes, and dropped the weapon's) | **0…15** | ✓ exactly (4 bits). design/15's "about 16 with everything" → DS-8 |
| 9 | **Weapon base damage** (`MemberStats.weapon_damage`, `u8`) | the base at requirement ≤ 27 (the maul, design/15); ÷ 3 when the requirement is not met; P: +20 % (`BASE_DAMAGE_PERCENT`, personalisation only: DS-4) | **0…32** (⌊27 × 120 / 100⌋) | ✓ |
| 10 | **Strength** (`MemberStats.weapon_strength`, `u8`) | weapon: 5 × rank ≤ 75, "capped by level" (the cap: DS-9); spell and trap: 3 × level ≤ 60 | ≤ 75 | ✓; the exponent is clamped to [−160, +80] anyway |
| 11 | **Damage percent** sums, × 6 (`MemberBar.damage`, `i8`) | H, S: −18…+18 each (§7.2, validator) | **±126** | ✓ (settled) |
| 11′ | Damage percent **at a hit** | row 11 + critical +40 + axe +25 (design/04); Weakness −33 (P) | −159…+191 | computed in `i16` ✓, floored at −100 (D-140) |
| 12 | **Penetration** sums, × 3 (`MemberBar.penetration`, `u8`) | H, S: 0…36 each (§7.2) | **0…252** | ✓ (settled); at use + *Might* (primary rank, value BAL-01) + `PENETRATION` effects (0…100 each) + `HIT_PENETRATION` (0…100), capped at 100 |
| 13 | **Life steal on hit** (`MemberKit.life_steal`, `u8`) | H: 0…+5 (proposed: design/15 names the modifier, not its value; DS-6). Others 0 | **0…25** | ✓ |
| 14 | **Energy on hit** (`MemberKit.energy_on_hit`, `u8`) | H: 0…+1 (proposed, DS-6). Others 0 | **0…5** | ✓ |
| 15 | **Condition duration** (`MemberKit`: condition 4 bits, percent 6 bits) | the weapon's prefix only (§7.2): 0…+33 (design/15: "Rending", +33 %) | **0…33** | ✓ (≤ 63). The validator's 0…32,767 would let the kit's packer refuse at entry → DS-5 |
| 16 | **Enchantment duration** (`MemberKit`, 6 bits) | 0…+20 (design/15: +10 to +20 %) on **one slot type** (proposed: the inscription) | **0…40** (weapon and off-hand) | ✓ only with the restriction: on every source, 17 × 20 = 340 > 63 → DS-5 |
| 17 | **Knock-down ticks** (`MemberKit.knockdown`, 2 bits) | S only: 0…+1 (design/15: *Hob-breaker*'s 3 pieces) (proposed restriction) | **0…2** | ✓ (≤ 3); on every source it would not fit → DS-5 |
| 18 | **Double adrenaline every N** (`MemberKit`, `u8`) | any: N 1…255; **the lowest counts** (FX-43); design/15 names 10 to 5 | 1…255 | ✓ by rule |
| 19 | **Quick cast**, 2 pairs (`MemberBar.quick_cast`: attribute 4 bits, N 8 bits) | the **inscription** (D-157 B, written here: see §1.5); N 0…255 (design/15 names 5) | ≤ 2 pairs (weapon and off-hand) | ✓ by rule |
| 20 | **Energy cost** reduction (`ENERGY_COST`) | *Fieldcraft* only, from the primary rank at use (value BAL-01). No record: the snapshot has no field for it (DS-4) | cost after reductions ≥ 0 (design/19 §6) | ✓ |
| 21 | **Halving** (`MemberKit.halving`, 1 bit), **damage type** (`MemberStats.damage_type`), **set bonuses** (`u16` of bits) | one bit whatever the count; one type, never summed (FX-43); one set, 2 bonuses | — | ✓ by rule |

**What the in-play fields hold** (ENG-01 §3.2, `MemberState`): health `u16` ≤ max health ≤ 1,055;
energy in thirds `u16` ≤ 390; adrenaline in quarters `u16` ≤ 4 × 255 = 1,020 (the cap is the bar's
highest adrenaline cost, a `SKILL` byte); `hits` < N ≤ 255; `casts` < N ≤ 255. All fit.

### 1.3 A goblin

| # | Statistic (field, width) | Per-source bound | Total | Fits |
|---|---|---|---|---|
| G1 | **Max health**, computed; current health in `GoblinState` (`u16`) | K: `⌊(100 + 20 (L − 1)) × m / 100⌋`, `m` the caste's percent (design/05: "the same formulas as adventurers with a caste multiplier on health"); **`m` ≤ 1,000** (proposed) | at L = 255 (the level's `u8`): 5,180 × 10 = **51,800** | ✓ for any level; without a bound on `m`, `u16` overflows from `m` > 10,239 at L = 28 → DS-18 |
| G2 | **Energy** (`GoblinState`, thirds, `u8`) | K: ≤ 85 (§7.2, CBT-01 `MAX_ENERGY`); `ENERGY` effects −255…+255, clamped to [0, max] | ≤ 255 thirds | ✓ |
| G3 | **Energy regeneration** (caste `u8`, pips) | K: 0…10 (proposed) | ≤ 10 thirds a tick | ✓ |
| G4 | **Adrenaline** (`GoblinState`, quarters, `u8`, ≤ 252) | the cap: its skills' highest adrenaline cost, in quarters; **a caste's skills cost ≤ 63 strikes** (proposed pipeline check) | ≤ 252 | ✓ with the check; a `SKILL` byte allows 255 strikes → DS-18 |
| G5 | **Armor at a hit** | K: armor 0…255 (`u8`); E: one `ARMOR` effect 0…255; K: `ARMOR_VS` 0…63 | **0…573**, never negative | computed ✓ |
| G6 | **Health regeneration** | K: −10…+10 (stored + 10); E: one `REGENERATION` −10…+10; conditions −14 | −34…+20, clamped to ±10 | ✓ |
| G7 | **Weapon base damage** (caste `u16`) | K: ≤ **255** (proposed: the member's width, so that both hit paths share one arithmetic) | ≤ 255 | ✓ |
| G8 | **Rank** (caste, 4 bits) | K: 0…15 | 0…15 | ✓ |
| G9 | **Flee threshold** (caste `u8`, percent) | K: 0…100 (proposed; 0 = never flees on health) | ≤ 100 | ✓ |

### 1.4 One hit's arithmetic (for CBT-02)

The widest product of design/19 §5.5 step 4 is `base × table(x)`, with `table(+80) = 4 × 2^16 =
262,144` (2^18). `base` is a `DAMAGE` entry's value (≤ 32,767) or a weapon's damage (≤ 32 for a
member, ≤ 255 for a goblin) plus an `ATTACK_BONUS` (≤ 32,767): **≤ 33,022 < 2^16**. The product is
below **2^34**: it needs a `u64`, not a `u32`, and never a `u256`. Everything else in a hit fits `i32`.

### 1.5 What D-157 left to this document

| # | D-157 | Written here |
|---|---|---|
| A | Attribute ids: a global id in content, a build-local index in the snapshot; **26** attributes | Row 8 and the sheets use design/03's 26; the goblin skills below name design/03's attributes |
| B | Which slot type carries `QUICK_CAST_EVERY_N` ("whichever content names; DES-06 writes it") | **The inscription** ("everything held": weapon and off-hand, so ≤ 2 pairs, the field's count; §7.2) |
| C | `DAMAGE_TYPE`'s one slot type ("on the weapon") | **The prefix**: the only slot that exists only on weapons (design/15), so no item-context check is needed; a wand, which has no prefix, keeps its type by attribute. A weapon then carries either a type change or "Rending", as in the baseline |
| D | Health-rune identity by modifier id | Row 1 counts one health rune per modifier id |
| E | `ADRENALINE_DECAY` = 1 quarter a tick until BAL-01 | Written in design/19 §5.8 and FX-12 |

## 2. The caste sheets of the MVP

The MVP has five castes (design/09): Runt, Slinger, Skirmisher, Shaman, Hobgoblin. Each sheet is
CBT-01's `CASTE` (design/19 §7.3, `models::caste::Caste`), field by field. **Initial values**, tuned by
BAL-01.

### 2.1 How the values are reasoned

- **Rank** (skills and weapon strength): the highest rank design/03's adventurer at the tier's
  **middle level** can buy in one attribute (points: 5 per level from 2 to 10, 10 from 11 to 15, 15
  from 16 to 20, plus 15 at Tin and 15 at Copper; the rank cost table). Tier 1 (1–6, middle 3.5):
  10 points at level 3 → **4**. Tier 2 (3–10, 6.5): 25 at level 6 → **6**. Tier 3 (6–14, 10): 45 + 15 (Tin) → **9**.
  Tier 4 (10–20, 15): 95 + 30 → **12**. Tiers 5–6 above level 20: 12 plus the rune's 3 an
  adventurer reaches "with everything" (design/15), extrapolated (FX-0b): **14** and **15**.
- **Health multiplier**: fodder dies in about 3–4 weapon hits of an adventurer of its level, a melee
  in about 9, a caster in about 7 (the "kill first" target), the brute in about 30 (§2.4).
- **Armor**: the profession analogue's class (design/03: 80 / 70 / 60), lowered by tier; the fodder
  at 20. design/03 keeps an adventurer's armor flat by class until BAL-01 (D-148); a caste's armor is
  flat too, for the same reason (DS-11).
- **Armor per damage type**: the analogue's class innate (design/15): a Vanguard analogue +20 against
  physical (types 1–3), a Warden analogue +30 against elemental (4–7), a caster none.
- **Energy and regeneration**: the analogue's (design/03: Vanguard 20 / 2, Warden 25 / 3, casters
  30 / 4); **0 / 0** for a caste without skills.
- **Weapon**: a class of design/15's table, its damage at requirement 9 (design/04's midpoints), its
  ticks and range; the damage type the class's (design/04), or chosen where the class has none.

### 2.2 The sheets

AI profiles are numbered in design/05's order (**proposed**, DS-10): 1 `swarm`, 2 `kite`, 3 `flank`,
4 `support`, 5 `brute`, 6 `caster`, 7 `boss`. Weapon classes and damage types are CBT-01's ids
(`combat::weapon`, `combat::damage`).

| Field (bits) | Runt | Slinger | Skirmisher | Shaman | Hobgoblin |
|---|---|---|---|---|---|
| tier (8) | 1 | 1 | 2 | 3 | 4 |
| AI profile (8) | 1 `swarm` | 2 `kite` | 3 `flank` | 4 `support` | 5 `brute` |
| health multiplier, % (16) | 50 | 40 | 70 | 60 | 150 |
| health regeneration, pips (8, stored + 10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) |
| armor (8) | 20 | 20 | 40 | 30 | 60 |
| armor per type, 1–9 (9 × 6) | 0 × 9 | 0, 0, 0, 30, 30, 30, 30, 0, 0 | 20, 20, 20, 0 × 6 | 0 × 9 | 20, 20, 20, 0 × 6 |
| weapon class (4) | 2 axe | 4 bow | 1 sword | 5 staff | 3 maul |
| weapon damage (16) | 17 | 21 | 18 | 16 | 27 |
| damage type (4) | 1 slashing | 3 blunt | 1 slashing | 7 earth | 3 blunt |
| weapon ticks (4) | 1 | 2 | 1 | 2 | 2 |
| weapon range (4) | 1 | 6 | 1 | 6 | 1 |
| energy (8) | 0 | 0 | 20 | 30 | 20 |
| energy regeneration, pips (8) | 0 | 0 | 2 | 4 | 2 |
| skills, priority order (4 × 16) | — | — | Rending Cut | Mend Kin, Stone Skin | Overhead Smash |
| rank (4) | 4 | 4 | 6 | 9 | 12 |
| flee threshold, % (8) | 30 | 0 | 0 | 0 | 0 |
| loot table (16) | CNT-01 | CNT-01 | CNT-01 | CNT-01 | CNT-01 |
| boss (1) | 0 | 0 | 0 | 0 | 0 |

Skill ids and loot table ids are content (CNT-01 seeds them); the names above are design/03's
skills and §3's new ones. Every value lies inside §1.3's bounds.

### 2.3 Why each caste looks like this

- **Runt** (fodder melee, `swarm`, no analogue). The **axe**: a swarm surrounds, and being
  surrounded is dangerous by geometry (design/04); the axe's +25 % from the rear arcs makes that true
  of runts without a rule of their own. Weapon only (design/19 §8). It flees below **30 %** when last
  of its pack (design/05's `swarm`; "last of pack" is the profile's rule, the percent the sheet's).
- **Slinger** (fodder ranged, `kite`, Warden analogue). No sling exists in design/15: the **bow**
  class gives its rules (range 6, two ticks, line of sight), and the stone its **blunt** type (DS-19).
  +30 against elemental from the Warden's medium class. Weapon only. "Targets lowest armor" is a
  target-selection rule of the profile over the members (M-3), not a sheet field.
- **Skirmisher** (melee, `flank`, Vanguard analogue). "Applies Bleeding" with design/03's **Rending
  Cut** (Blades attack, 5 / – / 8, Bleeding 5…20), which needs the Blades weapon: the **sword**
  (design/19 §3.4: an attack skill needs the weapon of its attribute). Flanking puts it in a rear-side
  arc, where blocks are ignored (design/04).
- **Shaman** (support caster, `support`, Cleric / Arcanist analogue). design/03 says the Cleric comes
  first after the MVP "because goblin shamans already need most of its skills": its heal is a Cleric
  skill (**Mend Kin**, Mending, §3.2), and its "shields" are `ARMOR` (FX-20), design/03's **Stone
  Skin** cast on an ally. **Staff**, **earth** (a caster's type is "by attribute", design/04; the
  shaman's attributes have none, so the type is chosen). Heal first, then shield (§3.3).
- **Hobgoblin** (brute, `brute`, Vanguard analogue). "Heavy hits with wind-up (telegraphed)": the
  **maul** and **Overhead Smash**, an attack skill with activation 3 (design/19 §8, §10.2). Its act
  costs `max(2, 3 + 1) = 4` ticks (FX-5, FX-15): the three ticks to step away, interrupt or brace
  that design/04 promises, and design/14's quest "interrupt its wind-up" with Skullring.

### 2.4 The check behind the multipliers

Assumptions, stated: an adventurer at the tier's middle level (3, 3, 6, 10, 15), its rank from §2.1
in the attribute used, a sword of 18 (design/04) at strength 5 × rank, Ember Bolt at rank `r` (15 +
45 r / 12, strength 3 × level); goblins hitting a Vanguard's flat 80 (D-148); no arcs, no modifier,
no skill.

| Caste | Level | Health | Sword hits to kill | Ember Bolts | Its weapon on armor 80 | The adventurer lasts |
|---|---:|---:|---:|---:|---|---:|
| Runt | 3 | 70 | 3.9 | 2.8 | 6.4 a tick | 22 ticks |
| Slinger | 3 | 56 | 3.1 | 2.3 | 7.4 per 2 ticks | 38 ticks |
| Skirmisher | 6 | 140 | 9.2 | 5.5 | 7.6 a tick | 26 ticks |
| Shaman | 10 | 168 | 7.2 | 3.4 | 8.7 per 2 ticks | 64 ticks |
| Hobgoblin | 15 | 570 | 31.7 | 12.3 | 19.1 per 2 ticks | 40 ticks |

These are the targets BAL-01 starts from, not a balance: a pack of four runts deals four times a
runt, arcs and skills move every figure, and the simulator decides.

### 2.5 Bosses and Hearts: separate records

A caste sheet has one `boss` bit, so **a boss is its own `CASTE` record**: the MVP needs a boss
Hobgoblin (the boss of D1, design/01, design/14; the Copper Rift's Heart, design/17) beside the pack
Hobgoblin of the *Hob guard* and of design/14's "brute at the bridge", and Hearts for the Wood
(Skirmisher) and Tin (Shaman) grades. **Proposed** (DS-13): a boss record is its caste's sheet with
the health multiplier **× 3** and `boss = 1`, nothing else changed; its guaranteed drop is its loot
table's (design/07). A Red Rift's misgraded Heart (design/17) is the next grade's Heart record.

| Record | Of caste | Health % | boss | Where |
|---|---|---:|:-:|---|
| Skirmisher Heart | Skirmisher | 210 | 1 | Wood Rift |
| Shaman Heart | Shaman | 180 | 1 | Tin Rift |
| Hobgoblin, boss | Hobgoblin | 450 | 1 | D1's last floor; Copper Rift; the Iron-grade Heart of a Copper Red Rift (with its retinue: a pack) |

### 2.6 Boss phases

design/05's `boss` profile has "scripted phases by health thresholds"; design/19 §7.3 gives phases no
field (**P**, FX-20). The design of the Hobgoblin's phases, whatever carries them:

| Phase | While | Priority list | What the player reads |
|---|---|---|---|
| 1 | health > 50 % | Overhead Smash, then the maul | the telegraphed wind-up, three ticks to answer |
| 2 | health ≤ 50 % | a shout that alerts every pack within 8 tiles (skill kind 6, design/19 §3.4) once, then Overhead Smash | "the nest answers": reinforcements from packs already on the floor, without a summon |

How it is carried is **DS-14**; the recommendation keeps the MVP's boss on the `brute` profile, with
no phase, and records this table for the field that comes after.

## 3. The castes' skills and priority lists

### 3.1 design/03's skills a caste uses

| Skill | Caste | design/03 | Entries (design/19) |
|---|---|---|---|
| Rending Cut | Skirmisher | Blades, Attack, 5 / – / 8 | `CONDITION` Bleeding, `v` 5…20 (§2.1) |
| Stone Skin | Shaman | Stone, Enchantment, 10 / 1 / 20 | `ARMOR`, `ALLY`, `SINGLE`, `ALLIES` (the source included, M-5) |

A goblin's rank is its sheet's for every skill, whatever the skill's attribute (design/19 §2.2).

### 3.2 New skills the MVP's castes need

Built only from design/19's catalogue and legal under §5.14. Working names; values are rank 0…12, in
design/03's format. CNT-01 seeds them as `SKILL` records.

| Skill | Profession, attribute, kind | Cost | Entries | Why |
|---|---|---|---|---|
| **Mend Kin** | Cleric, Mending, Spell | 10 / 2 / 8, range 6 | `HEAL` 20…100, `ALLY`, `SINGLE`, `ALLIES` | the Shaman "heals the pack" (design/05); a spell, so interruptible: the adventurer can stop it (design/04) |
| **Overhead Smash** | Vanguard, Mauls, Attack | 10 / 3 / 10 | `ATTACK_BONUS` 20…60 (`FOE`, `SINGLE`) | design/19 §8 and §10.2: an attack skill with activation 3; recharge 10 as §10.2's example |

### 3.3 Priority lists (design/04: position, then the first usable skill, else the weapon)

| Caste | Priority | Then |
|---|---|---|
| Runt | — | the axe on the nearest member |
| Slinger | — | the bow, from range |
| Skirmisher | Rending Cut | the sword |
| Shaman | Mend Kin on the lowest-health ally, then Stone Skin on an ally | the staff, from ≥ 3 tiles |
| Hobgoblin | Overhead Smash | the maul |

What makes a skill **usable** for a goblin (an ally below max health for a heal, an ally without the
effect for a shield) is not written anywhere: **DS-15**.

## 4. The castes after the MVP

design/05's other six castes, in the same shape. Their fields are filled where the catalogue can
carry them; what it cannot is named, and they stay out of content until it can (design/09: after
the MVP). Rank from §2.1; health, armor and energy reasoned as in §2.1.

| Field | Trapper | Wolf rider | Hexer | Champion | Paladin | Lord |
|---|---|---|---|---|---|---|
| tier | 2 | 3 | 4 | 5 | 6 | 6 |
| AI profile | **none fits** (DS-16) | 3 `flank` | 6 `caster` | 3 `flank` | 5 `brute` | 7 `boss` |
| health % | 60 | 100 | 80 | 150 | 200 | 300 |
| armor | 30 | 50 | 40 | 70 | 80 | 70 |
| armor per type | +30 elemental | +20 physical | 0 | +20 physical | +20 physical | 0 |
| weapon (class, damage, type, ticks, range) | bow, 21, piercing, 2, 6 | axe, 17, slashing, 1, 1 | wand, 16, shadow, 2, 6 | axe, 17, slashing, 1, 1 | sword, 18, slashing, 1, 1 | sword, 18, slashing, 1, 1 |
| energy / regen | 25 / 3 | 20 / 2 | 30 / 4 | 20 / 2 | 25 / 3 | 30 / 4 |
| skills | Snare, Hamstring Shot | Trample | a hex, an energy drain, **its trigger** | Brace, Cleave, Warcry, **an interrupt** | Second Wind, Brace, **"protects the lord"** | a rally shout, **reinforcements** |
| rank | 6 | 9 | 12 | 14 | 15 | 15 |
| flee | 0 | 0 | 0 | 0 | 0 | 0 |
| boss | 0 | 0 | 0 | 0 | 0 | 1 |

- **Trapper**: design/03's Snare and Hamstring Shot, as they are. It "places traps on chokepoints":
  no profile of design/05 says where a trap goes.
- **Wolf rider**: **Trample** (Vanguard, Axes, Attack, 6 adrenaline: `CONDITION` Knocked down 2) is
  catalogued; "moves 2 tiles per tick" is not (movement **P**, FX-20).
- **Hexer**: a hex is catalogued as a holding `REGENERATION` of negative pips on a foe, energy denial
  as `ENERGY` with a negative value; "punishes skill spam" is `ON_SKILL_USE` (21), a placeholder
  whose behaviour design/19 left to this document (FX-32): **DS-16**.
- **Champion**: design/03's Brace, Cleave and Warcry fit its axe; `INTERRUPT` (17) is **P**.
- **Paladin**: Second Wind and Brace fit; "protects the lord" is not catalogued (FX-20).
- **Lord**: a rally is a shout with `PENETRATION` on `SELF`, `RING_1`, `ALLIES` (radius 1: FX-21);
  reinforcements are `SUMMON` (22, **P**); its phases are DS-14's.
- **Affixes** (*Scarred*, *Rabid*: passives 64–65) are **P** (design/05, design/19 §4).

## 5. Escalations

Each: the question, the options, the recommendation. None is decided here.

| # | Question | Options | Recommendation |
|---|---|---|---|
| **DS-1** | The per-source bounds §1 marks **proposed** (health on held slots, insignias, runes and set bonuses; max energy and regeneration; life steal, energy on hit; armor per type ≤ 7 a source; enchantment and knock-down restrictions; caste bounds) | (a) adopt §1 as the pipeline's checks (`PassiveAssert` per source kind, `CasteAssert`); (b) keep CBT-01's wider validators and check only the totals at flattening | **(a)**: a per-source bound is checked once per record, a total at every entry; (b) moves the refusal to the player's `set_build` |
| **DS-2** | A build can reach **max health < 1, max energy < 0, energy regeneration < 0** (§1.2 rows 1–3: costs at low level); the energy regeneration field is unsigned | (a) `set_build` refuses such a build (legality, in a hub; nothing changes in play since equipment is fixed); (b) the flattening clamps (a cost then costs nothing past the floor); (c) store energy regeneration signed like health (+ 10), an interface change | **(a)**, floors 1, 0, 0: no interface change, and a player sees why the build is refused. Energy degeneration has no MVP source to motivate (c) |
| **DS-3** | `MemberKit.health_bonus` is `u16`; the equipment's health sum is −525…+575 | (a) the flattening writes only the total in `MemberStats.max_health` (which `maxima` reads) and frees `health_bonus`; (b) make it `i16` (same 16 bits) | **(a)**: one place holds max health; (b) if a rule needs the equipment part apart (none does in design/19) |
| **DS-4** | Passives with no snapshot field if a record carries them: `ENERGY_COST` (only *Fieldcraft*'s), `BASE_DAMAGE_PERCENT` (personalisation's), `ATTRIBUTE` outside runes. `PassiveTrait::allows` lets any source hold them | (a) refuse them on every record but their source (`ATTRIBUTE`: runes; the other two: no record, like `RATING_PERCENT`); (b) add fields | **(a)**: every source named by design/15 and design/03 fits it |
| **DS-5** | Sums that break a kit field on the validators' current bounds: `CONDITION_DURATION` (0…32,767 on one prefix, 6 bits), `ENCHANT_DURATION` (any source, 6 bits), `KNOCKDOWN_FLAT` (any source, 2 bits) | (a) §1's bounds: ≤ 33 on the prefix; ≤ 20 on the inscription only; ≤ 1 on set bonuses only; (b) saturate at the field | **(a)**: the kit's packer refuses today, so a legal record could make `enter` panic |
| **DS-6** | Life steal and energy on hit: design/15 keeps the modifiers "as they are" without values | (a) the baseline's: +5 life steal with −1 health pip, +1 energy with −1 energy pip, on held slots; (b) BAL-01 first | **(a)** as the bounds, BAL-01 sets the values under them |
| **DS-7** | *Wellspring* per rank, the light armor's "+ energy and energy regeneration", *Might*'s and *Fieldcraft*'s per rank: no values | bounds proposed (≤ 3 energy a rank, ≤ +20 and +1 pip); values BAL-01 | the bounds as §1.2 gives them |
| **DS-8** | design/15: "attributes reach 12 by points and about 16 with everything"; the snapshot holds 4 bits (0–15) and runes give at most +3 | (a) 15, and design/15's "about 16" reads "15"; (b) a fifth bit, an interface change | **(a)**: no MVP source gives a sixteenth rank |
| **DS-9** | "Strength = 5 × rank, **capped by level**" (design/04): no document gives the cap | (a) no cap in the MVP (5 × 15 = 75 ≤ the exponent's range); (b) `min(5 × rank, 3 × level + k)`; (c) BAL-01 | **(c)**, with (a) until then: a goblin's rank is on its sheet, so without a cap a low-level goblin of a high rank would hit as hard as a high-level one |
| **DS-10** | AI profile ids: CBT-01's `ai` byte names no ids | 1–7 in design/05's order | adopt, frozen by the next CBT lot that reads them |
| **DS-11** | design/05: "Level scales health, armor and damage"; only health has a formula | (a) armor flat (as D-148 does for adventurers), damage on the dropped item's curve (design/15: ~20 % at level 1, the maximum from level 20); (b) armor and damage flat, only health scales; (c) BAL-01 | **(a)**: the goblin's weapon is the one it drops; flat armor until BAL-01 gives both sides a curve |
| **DS-12** | One rank per caste across its level range (tier 1: levels 1–6) | (a) as §2.1, the middle level's; (b) rank derived from the goblin's level by §2.1's table (no field); (c) one record per level band | **(a)** for the MVP; (b) if BAL-01 finds the ends of a range wrong |
| **DS-13** | A boss is its own `CASTE` record (one `boss` bit); its multiplier | (a) the caste's sheet, health × 3, `boss = 1`; (b) boss records tuned one by one | **(a)** as the initial value, BAL-01 per boss |
| **DS-14** | Boss phases have no field (§7.3 **P**, FX-20) | (a) no phases in the MVP: the Hobgoblin boss is a `brute` with `boss = 1`; (b) a phase field in `CASTE` part 1's empty high limb (2 phases × (threshold 8 + a 4-bit mask of its skills) = 24 bits, 0 new slots, a record change and an AI rule); (c) a caste switch at the threshold (the goblin's `caste` rewritten) | **(a)** for the MVP (design/14's lesson is the interrupt, which phase 1 teaches), **(b)** when the Lord comes |
| **DS-15** | When a goblin's skill is **usable** (design/04: "first usable skill"): a heal on a full-health ally, a shield on a shielded one, an attack skill out of range | (a) recharged, affordable, and a legal target whose state the skill changes (below max for `HEAL`, without the carrier for a holding entry, in range for the rest); (b) recharged and affordable only | **(a)**, written by the lot that implements the AI (CBT-04) |
| **DS-16** | Post-MVP castes: the Trapper's profile (none fits), the Wolf rider's movement, **the Hexer's trigger (FX-32)**, the Champion's interrupt, the Paladin's protection, the Lord's reinforcements | FX-32: (a) defer with the Hexer (post-MVP); (b) `ON_SKILL_USE` as a holding hex: each skill its holder starts deals `v` damage to it (not a hit, like degeneration) | **(a)** for all six: design/09 puts them after the MVP; (b) is the Hexer's first design when it comes |
| **DS-17** | Goblin-only skills (Mend Kin, Overhead Smash) carry a profession: capture and trainers read it | (a) the analogue's profession (Cleric, Vanguard), as design/03 foresees for shamans; (b) a "goblin" profession | **(a)**: no elite, so nothing is capturable in the MVP |
| **DS-18** | Checks the caste record lacks: health multiplier ≤ 1,000 %, energy regeneration ≤ 10, weapon damage ≤ 255, flee ≤ 100, its skills' adrenaline ≤ 63 strikes | add them to `CasteAssert::assert_legal` | add them (CBT-01's follow-up) |
| **DS-19** | The Slinger's weapon: design/15 has no sling | (a) the bow class, blunt; (b) a seventh weapon class | **(a)**: the class gives the rules, the type the stone |

## 6. Acceptance tests the validators and the flattening owe (D-157 G)

For CBT-01's follow-up (the validators) and CBT-02 (the production flattening):

1. For each row of §1.2 and §1.3, a record at the per-source bound passes and one a unit beyond is
   refused, on each source kind that may hold it, and a source kind that may not is refused.
2. The **widest build**: every source at its maximum (§1.2's upper totals), flattened, fits every
   field, and `maxima` reads 1,055 health and 130 energy.
3. The **narrowest build**: level 1, every cost at its bound: refused (DS-2's recommendation) or
   clamped, whichever the project manager decides; never a panic in `enter`.
4. Two health runes of one modifier id count once; of two ids, both.
5. A caste at the bounds of §1.3 (`m` = 1,000 at level 255; energy 85; adrenaline 63 strikes) packs,
   and its goblin's health, energy and adrenaline fit `GoblinState`.
6. A hit with `base = 33,022` at `x = +80` computes in `u64` without overflow.
