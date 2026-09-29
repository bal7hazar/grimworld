# 20 — Caste sheets, and the per-source bounds of every statistic

> Status: **Draft v0.3** (DES-06, D-157 G, D-159). v0.3, fix loop 2 of `[GPT-6-Astra]`'s re-audit:
> - DES06-7: the health-regeneration proofs now count what CBT-01's packers accept, which is the whole
>   `u8`, not the 0–20 encoding. The check CBT-01 would have to add is escalated as DS-29;
> - DES06-4: every value of every caste skill is specified or escalated (DS-30 to DS-33 for Warcry,
>   Second Wind, Snare and Brace; DS-22 extended to Stone Skin's range);
> - DES06-3: the rest of the state is inventoried (§1.5): charges, held ranks, counters, effective
>   durations and deadlines, weapon ticks and range, skill headers;
> - DES06-6: the extremal builds are valid. Energy 130 comes from a sword and an off-hand; health's
>   fixture depends on DS-23.
>
> v0.2, fix loop 1 of `[GPT-6-Astra]`'s audit (DES06-1 to DES06-6):
> - every total is recounted from CBT-01's code, both what its validators accept today and what the
>   proposed bounds allow, with the arithmetic shown;
> - the hit base counts every `ATTACK_BONUS`, and the percent sum at a hit counts both guards;
> - the source inventory is complete (primary attributes, glyphs, bombs, effects and their counts);
> - the sheets are complete, and each part of a deferred caste that cannot be carried yet is an
>   escalation that says what it needs;
> - the multipliers are recomputed with type armor and integer arithmetic;
> - the "widest build" fixture is withdrawn.
>
> Numbers in the sheets are **initial values**, which BAL-01 tunes with the balance simulator. A bound
> marked **proposed** is this document's recommendation and is escalated as **DS-n** (§5) to the
> project manager. Everything else is read from the source cited. Nothing here changes a rule of
> design/19.
>
> **Why a new document and not an amendment of design/05.** design/05 states the bestiary's
> principles (castes, packs, profiles) and stays short. The sheets fill CBT-01's record shape field
> by field, and the bounds concern the adventurer as much as the goblins. CBT-01's follow-ups,
> CBT-02 to CBT-05, ENG-07, BAL-01 and CNT-01 read it the way design/19 is read beside design/04.

**Order.**
- §1: the bounds. They can be used on their own by CBT-02 and by CBT-01's validators.
- §2: the MVP's caste sheets.
- §3: their skills and priority lists.
- §4: the castes after the MVP.
- §5: the escalations. **★ marks those CBT-02 or ENG-07 needs first.**
- §6: the acceptance tests.

## 1. The per-source bounds (D-157 G)

### 1.1 Words and method

- A **statistic** is a quantity that an actor carries and that a rule reads (design/19 §7.2, §7.3).
- A **source** is one thing that can add to a statistic.
- A **per-source bound** is the range `[lo, hi]` that one source can add. It is signed wherever a
  source can subtract. It applies to **the sum of the source's passives on that statistic**: a
  modifier's benefit and cost together, as `PassiveAssert::assert_contributions` already does for
  three sums.

Each statistic gets two envelopes and, where the two differ, an attainable figure:

| Envelope | What it counts |
|---|---|
| **A, CBT-01 today** | Every combination that CBT-01's validators accept today (`PassiveAssert::assert_legal`, `allows`, `assert_contributions`; `ModifierAssert::assert_legal`, `assert_catalogue`; `ArmorSetAssert`; `EntryAssert::assert_legal`, `assert_carrier`; `CasteAssert`), over the sources of §1.2, and the width of the field that stores it |
| **B, proposed** | The same, with DS-1's per-source bounds of §1.3–§1.5 |
| **Attainable** | A legal build that reaches the value. Where it is below A or B, A and B are **conservative envelopes**, not targets (DES06-6) |

A total **fits** when the field holds every value of its envelope, or when a rule saturates the
total into the field. Where A does not fit and B does, the fix is DS-1, and the flattening must not
be written before it is decided.

### 1.2 The sources, and how many an actor holds at once

| Code | Source | At once | Passives | From |
|---|---|---:|---:|---|
| **B** | The build: level (1–20 in the MVP; `u8`), primary profession, attribute ranks 0–12 | 1 | — | design/03 |
| **C** | The armor class's innate bonus: heavy +20 against physical, medium +30 against elemental, light "+ energy and energy regeneration" (no value) | 1 | — | design/15 |
| **A** | The primary attribute, from the primary rank at use: *Might* (`PENETRATION`, attack skills), *Fieldcraft* (`ENERGY_COST`), *Wellspring* (`MAX_ENERGY`). design/03 gives no values | 1 | — | design/03, design/19 §4 |
| **Pf** | A prefix: weapons, not wands | **1** | 2 | design/15 |
| **Sf** | A suffix: weapons, shields, foci | **2** | 4 | same |
| **In** | An inscription: everything held | **2** | 4 | same |
| **I** | An insignia, one per armor piece | **5** | 10 | same |
| **R** | A rune, one per armor piece | **5** | 10 | same |
| **S** | A set bonus: one set can reach 3 of 5 pieces, which gives 2 bonuses | **2** | 2 | design/15 D-45 |
| **P** | Personalisation: +20 % to the weapon's base damage, +10 % of a rating. Not a record (`RATING_PERCENT` is refused on every source) | weapon, shield, 5 pieces | — | design/15 D-48 |
| **E** | Effects held in play: a member has **4** slots, a goblin **1** (design/19 §7.2). One holding entry per carrier (§5.14). A skill's and a potion's entries are counted alike | 4 / 1 | — | design/19 §3 |
| **Cd** | Conditions: 5 in the MVP | ≤ 5 | — | design/19 §3.2 |
| **X** | Instant entries: `HEAL`, `LIFE_STEAL`, `ENERGY`, `DAMAGE`. A skill holds up to **3 entries**, a potion **1** | per carrier | — | design/19 §2.1, §5.14 |
| **K** | A goblin's caste sheet and its level (`GoblinState`, `u8`) | 1 | — | design/19 §7.3 |

- **H** means the five held-item slots (Pf + Sf + In).
- Each modifier is a benefit and a cost, **2 passives**, and the two may name the same statistic.
  `conflicts` refuses this only for quick cast, and for condition duration or damage type with two
  different params.
- Boss pieces have fixed insignias and runes, which fill the I and R rows (design/15 D-45).

An adventurer therefore holds at most **17 passive sources**: 15 modifiers and 2 set bonuses. That is
**32 passives**: 15 × 2 + 2. CBT-01's F-21 counted 37, which is an over-count, and its conclusion
stands (row 5).

Passive ranges that CBT-01's `PassiveAssert::assert_legal` accepts, and the sources `allows`
permits:

| Passive | Value per passive | Sources | Per-source limit today |
|---|---|---|---|
| `DAMAGE_PERCENT` | −18…+18 | H, S | ±18 **per guard and hit class** |
| `PENETRATION` | 0…36 | H, S | 36 per hit class |
| `ARMOR`, guarded | −18…+18 | I, S | ±18 per guard |
| `ARMOR`, unguarded | −255…+255 | any | none (2 × 255 per modifier) |
| `ADRENALINE_EVERY_N` | 1…255 | any | the lowest counts |
| `QUICK_CAST_EVERY_N` | 0…255 | H, one slot type for the whole content | one per modifier |
| `ARMOR_VS`, `KNOCKDOWN_FLAT`, `CONDITION_DURATION`, `ENCHANT_DURATION` | 0…32,767 | any (`CONDITION_DURATION`: prefix only) | none |
| `ENERGY_COST` | −32,768…0 | any | none |
| `DAMAGE_TYPE`, `HALVE_FIRST_HEAVY_HIT` | 0 | H (one slot type) / any | — |
| `MAX_HEALTH`, `MAX_ENERGY`, `ENERGY_REGEN`, `HEALTH_REGEN`, `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT`, `ATTRIBUTE`, `BASE_DAMAGE_PERCENT` | −32,768…+32,767 | any | none |

So a statistic open to "any" source can take **32 × 32,767 = 1,048,544** upward and **32 × 32,768
= 1,048,576** downward under A.

### 1.3 The adventurer's snapshot

Each row gives the field, then the arithmetic under A and under B. The proposed per-source bounds
are B's.

| # | Statistic (field, width) | A: CBT-01 today | B: proposed per-source bounds → total | Attainable, and fit |
|---|---|---|---|---|
| 1 | **Max health** (`MemberStats.max_health`, `u16`, which `maxima` reads; `MemberKit.health_bonus`, `u16`) | B 100…480; 32 passives at ±32,767: **−1,048,476…+1,049,024**. ✗ both ends | B: `100 + 20 (L − 1)`, 100…480. H: 0…+30 each (design/15: +10 to +30) → 0…150. I: 0…+15 each → 0…75. R: −75…+50 each (design/15: health runes +30 to +50; the "−75 health" cost) → −375…+250. S: −75…+50 each → −150…+100. A health rune of one modifier id counts once (FX-43, D-157 D). **Equipment −525…+575; total −425…+1,055** | Top ✓ `u16`, **depending on DS-23**. Under DS-23 (b), one value per record: **1,055**, from level 20, five health runes of distinct ids, five 15-point insignias, five 30-point held slots (a one-handed weapon and a shield or focus) and two +50 bonuses. Under DS-23 (a), design/15's 15 / 10 / 5 by piece: insignias 15 + 10 + 3 × 5 = 40, so **1,020**. Bottom: **below 1** → DS-2 ★. `health_bonus` cannot hold −525 → DS-3 ★ |
| 2 | **Max energy** (`MemberStats.max_energy`, `u8`) | 20…30 + A + C (no values) + 32 passives: ✗ | B 20 / 25 / 30. *Wellspring* ≤ 3 a rank × 15 = 45 (proposed, DS-7 ★). C light ≤ +20 (proposed, DS-7). H, S: −5…+5 each (design/15: "−5 energy") → −35…+35 over 7. I, R: 0. **Total 20 − 35 = −15 … 30 + 45 + 20 + 35 = 130** | Envelope 130 ✓ `u8`; in play 390 thirds ✓ `u16`. The envelope is **attained**: anyone may hold any weapon (design/15), so an Arcanist with a sword and a shield or focus has all 5 held slots: 30 + 45 + 20 + 7 × 5 = **130**. (With a wand and a focus it has 4 held slots, 125; with a staff 3, 120.) Bottom: **below 0** → DS-2 ★ |
| 3 | **Energy regeneration** (`MemberStats.energy_regen`, `u8`, pips) | 32 passives: ✗ | B 2 / 3 / 4. C light 0…+1 (proposed, DS-7). H: −1…0 each (energy on hit's cost, DS-6) → −5…0. S: −1…+1 each → −2…+2. **Total 2 − 5 − 2 = −5 … 4 + 1 + 2 = 7** | 7 ✓. Bottom: **the field is unsigned** → DS-2 ★ |
| 4 | **Health regeneration**, snapshot part (`MemberStats.health_regen`, a `u8` read as pips + 10; the encoding means 0–20) | 32 passives, unbounded. **`MemberStatsAssert::assert_valid` checks only `armor_vs`**, so `pack_stats` accepts any byte 0…255, which is pips **−10…+245**. Example: one legal modifier gives +127 pips, and 137 packs. ✗ against the encoding's meaning; the byte itself fits | H: −1…0 each (life steal's cost, DS-6) → −5…0. S: −1…+1 each → −2…+2. **Total −7…+2**, encoded 3…12 | Under B ✓ (−10…+10). Under A the stored value can lie outside ±10; §1.4 counts that case, and **DS-29 ★** escalates the check CBT-01 would add |
| 5 | **Unguarded armor** (`MemberBar.armor`, `i16`; `pack_bar` refuses beyond ±9,995) | The pieces' weighted rating ≤ 255 and the shield's ≤ 255 (`u8` each), personalisation ⌊255 × 10 / 100⌋ = 25 on each: 560. 32 passives at ±255 → ±8,160. **Total −8,160…+8,720** | unchanged (the documents name +4…+5; no tighter bound is needed to fit) | ✓ within ±9,995 (F-21) |
| 6 | **Guarded armor**, in a stance and enchanted (`MemberKit`, 2 × `i8`) | I, S: ±18 per guard and source → 7 × 18 = **±126** each | unchanged | ✓ |
| 7 | **Armor per damage type**, × 9 (`MemberStats.armor_vs`, 6 bits, saturated at 63 by FX-23) | C ≤ 30 + 32 passives at 0…32,767 → **≤ 1,048,574** per type; saturated | 0…+7 each, any source (design/15: +4 to +7) → 30 + 17 × 7 = **149**; saturated | ✓ by saturation. The flattening sums in a `u32` (21 bits under A), then saturates |
| 8 | **Attribute rank** of each bar skill (`MemberStats.ranks`, 4 bits each) and the primary rank (`u8`) | B 0…12 + 32 passives at ±32,768 (the runes' "highest counts" rule says nothing of other sources) → ✗ both ends | R only (DS-4 ★), +1…+3 (design/15), the highest per attribute counts → **0…15** | 15 ✓ exactly. design/15's "about 16" → DS-8 ★ |
| 9 | **Weapon base damage** (`MemberStats.weapon_damage`, `u8`) | The base at requirement ≤ 27 (the maul, design/15); `BASE_DAMAGE_PERCENT` on any source, 32 × ±32,768 → ✗ | Personalisation only, +20 % (DS-4 ★) → ⌊27 × 120 / 100⌋ = **32** | 32 ✓, with a maul, which has no off-hand. A one-handed maximum is ⌊18 × 1.2⌋ = 21 |
| 10 | **Strength** (`MemberStats.weapon_strength`, `u8`; computed for the others) | Weapon: the field accepts 0…255. Spell and trap: 3 × level, the level a `u8` → ≤ 765. Bomb: `ITEM.strength`, `u8` → ≤ 255 | Weapon: 5 × rank ≤ 75, "capped by level" (the cap: DS-9 ★). Spell and trap: 3 × 20 = 60 in the MVP. Bomb ≤ 255 | Every strength is computed in `i32`; the exponent `strength − armor` is clamped to [−160, +80] (design/04) ✓ |
| 11 | **Damage percent** sums, × 6 (`MemberBar.damage`, `i8`, index guard × class) | H, S: ±18 per guard and class per source, 7 sources → **±126** per bucket | unchanged | ✓ |
| 12 | **Penetration** sums, × 3 (`MemberBar.penetration`, `u8`) | H, S: 0…36 per class per source → 7 × 36 = **252** | unchanged | ✓ |
| 13 | **Life steal on hit** (`MemberKit.life_steal`, `u8`) | 32 × ±32,768 → ✗ | H only, 0…+5 each (DS-6) → **0…25** | ✓ |
| 14 | **Energy on hit** (`MemberKit.energy_on_hit`, `u8`) | ✗ as row 13 | H only, 0…+1 each (DS-6) → **0…5** | ✓ |
| 15 | **Condition duration** (`MemberKit`: condition 4 bits, percent 6 bits) | Prefix only; its benefit and cost may both be `CONDITION_DURATION` of one condition → 2 × 32,767 = **65,534** → ✗ 63 | **Saturated at 50** when flattened: the runtime's own cap `MAX_DURATION_BONUS_PERCENT` (`durations.cairo`). Content bound 0…+33 (design/15) → DS-5 ★ | ✓ ≤ 63; lossless, since the rule caps at 50 anyway |
| 16 | **Enchantment duration** (`MemberKit`, 6 bits) | Any source, 32 × 32,767 → ✗ | Saturated at 50 (the same cap) → DS-5 ★ | ✓ |
| 17 | **Knock-down ticks** (`MemberKit.knockdown`, 2 bits) | Any source, 32 × 32,767 → ✗ | Saturated at 3: `MAX_DURATION_FLAT`, which `ArmorSetAssert` already assumes → DS-5 ★ | ✓ |
| 18 | **Double adrenaline every N** (`MemberKit`, `u8`) | 1…255 per passive; the lowest counts (FX-43) | unchanged | ✓ |
| 19 | **Quick cast**, 2 pairs (`MemberBar.quick_cast`: attribute 4 bits, N 8 bits) | One per modifier (`conflicts`); one slot type for the whole content (`assert_catalogue`): a prefix gives ≤ 1, a suffix or an inscription ≤ 2. The attribute is a local index 0…15 (D-157 A) | the inscription (D-157 B, §1.8) → ≤ 2 | ✓ |
| 20 | **Energy cost reduction** (`ENERGY_COST`; no snapshot field) | Any source, 32 × −32,768: **no field holds it** → ✗, lossy | *Fieldcraft* only, computed at use from the primary rank. Proposed ≤ 1 energy a rank → ≤ 15 (DS-7 ★). Records refuse it (DS-4 ★) | See §1.4, energy cost |
| 21 | **Halving**, **damage type**, **set bonuses** | 1 bit; one type (`conflicts` plus one slot type); 2 bonuses of one set | the prefix for `DAMAGE_TYPE` (D-157 C, §1.8) | ✓ |

### 1.4 In play: what the rules compute from the snapshot and the effects

| Quantity | Sources and counts | A | B | Width |
|---|---|---|---|---|
| **Health** (`MemberState`, `u16`) | ≤ max health; `HEAL` and `LIFE_STEAL` ≤ 32,767 per entry, 3 entries a carrier | ≤ 65,535 (the field) | ≤ 1,055 | sum in `u32`, then clamp to [0, max] ✓ |
| **Energy** (thirds, `u16`) | ≤ max energy × 3; `ENERGY` −255…+255 per entry (× 3 in thirds) | ≤ 765 | ≤ 390 | `i32`, clamp ✓ |
| **Energy cost at a skill's start** | the `SKILL` header's energy (`u8`, ≤ 255) − *Fieldcraft* − `NEXT_SPELL_COST` glyphs (0…255 each, a member holds ≤ 4 effects: ≤ 1,020 if they add, DS-21 ★) + `ENERGY_COST` records under A | unbounded below (*Fieldcraft* has no value; records add down to −1,048,576) … 255 | 0 − 15 − 1,020 = **−1,035** … 255 (with DS-7's 15) | `i32`, floored at 0 (design/19 §6) ✓ |
| **Health regeneration** (design/19 §5.8), a member (DES06-7) | The snapshot byte minus 10: under A, whatever `pack_stats` accepted, 0…255, so **−10…+245** (row 4); under B −7…+2. E: 4 `REGENERATION` at −10…+10 (`EntryAssert` bounds the kind). Cd: Bleeding −3, Poison −4, Burning −7 | −10 − 40 − 14 = **−64** … 245 + 40 = **+285** | **−61…+42** | **`i16`** (or `i32`), then clamp to ±10 ✓ under A and B. An `i8` holds B only: the counterexample is +127 pips packed as 137 plus four +10 effects = 167 |
| **Adrenaline** (quarters) | a member's cap is its bar's highest cost (a `SKILL` byte, ≤ 255 strikes); a goblin's gains are capped at 252 by §5.12 | member ≤ 1,020; goblin ≤ 252 | same | `u16` / `u8` ✓ |
| **Armor at a hit**, a member (§5.5 step 3) | row 5 + row 6 × 2 + E: 4 `ARMOR` at 0…255 + row 7 ≤ 63 | −8,160 − 252 … 8,720 + 252 + 1,020 + 63: **−8,412…+10,055**. Field-bound (±9,995): **−10,247…+11,330** | same | `i32`, floored at 0 ✓ |
| **Penetration at a hit**, percent (§5.5 step 3) | row 12 (≤ 252) + *Might* (attack skills) + E: 4 `PENETRATION` at 0…100 + `HIT_PENETRATION` 0…100, **up to 3 per carrier** (`assert_carrier` does not limit them), summed as §5.5 says | 252 + ? + 400 + 300 (*Might* unbounded) | 252 + 15 + 400 + 300 = **967** | `u16`, capped at 100 (FX-9) ✓ |
| **Damage percent at a hit**, one hit class (§5.5 step 4; DES06-2) | The `ALWAYS` bucket, plus the `ABOVE_HALF` bucket while that guard holds. A held modifier may put +18 in each guard (benefit and cost); a set bonus is one passive. Then rules: critical +40, axe +25; Weakness −33 (P) | passives: 5 × 36 + 2 × 18 = **±216** (the fields allow ±252). **Total −216 − 33 = −249 … 216 + 40 + 25 = +281** | same (DS-24) | `i16`, floored at −100 (D-140) ✓ |

### 1.5 A goblin

| # | Statistic (field, width) | A: CBT-01 today | B: proposed | Fit |
|---|---|---|---|---|
| G1 | **Max health** (computed), current health in `GoblinState` (`u16`) | `⌊(100 + 20 (L − 1)) × m / 100⌋` with `m` a `u16` and `L` a `u8`: 5,180 × 65,535 / 100 = **3,394,713** → ✗ | `m ≤ 1,000` (DS-18 ★) → 5,180 × 10 = **51,800** | ✓ under B; the product needs a `u32` (5,180 × 65,535 = 339,471,300 < 2^32) |
| G2 | **Energy** (`GoblinState`, thirds, `u8`) | caste ≤ 85 (`CasteAssert`) → 255 thirds; `ENERGY` ±255, clamped | same | ✓ |
| G3 | **Energy regeneration** (caste `u8`, pips) | ≤ 255 thirds a tick, added in a `u16` then clamped | ≤ 10 (DS-18) | ✓ |
| G4 | **Adrenaline** (`GoblinState`, quarters, ≤ 252) | gains capped at 252 by §5.12 | its skills cost ≤ 63 strikes, or they can never be used (DS-18: checked across the referenced skills) | ✓ |
| G5 | **Armor at a hit** | caste ≤ 255 + one `ARMOR` effect ≤ 255 + `ARMOR_VS` ≤ 63 = **0…573** | same | ✓ |
| G6 | **Health regeneration** (DES06-7) | The caste byte minus 10. `CasteAssert::assert_legal` checks ≤ 20, but that is the content pipeline's check, which the registry does not call (CBT-01's report). `assert_valid`, which `pack` calls, does not check it, so a packed record holds 0…255: **−10…+245**. Plus one `REGENERATION` −10…+10 and −14: **−34…+255** | with `assert_legal` run on every record (DS-29): −34…+20 | **`i16`**, then clamp to ±10 ✓ under both |
| G7 | **Weapon base damage** (caste `u16`) | ≤ 65,535 | ≤ 255 (DS-18) | §1.6 |
| G8 | **Rank** (4 bits) | 0…15 | same | ✓ |
| G9 | **Flee threshold** (`u8`) | 0…255 (above 100: always flees) | ≤ 100 (DS-18) | ✓ |
| G10 | **Strength** | weapon 5 × rank ≤ 75; spell and trap 3 × level ≤ 765 | same (DS-9) | `i32`, clamped exponent ✓ |

### 1.6 One hit's arithmetic (DES06-1)

**The base.** The base is a `DAMAGE` entry's value (≤ 32,767; one per carrier), or a weapon's damage
plus its carrier's `ATTACK_BONUS` entries. CBT-01's `assert_carrier` accepts **up to 3** of them on
an attack skill, each ≤ 32,767. design/19 §3.1 writes "base = weapon damage + `v`" for one entry;
summing several is the natural reading, and it is escalated as DS-20 ★.

| Case | Weapon | + `ATTACK_BONUS` | Base |
|---|---:|---:|---:|
| A, a goblin (caste `u16`) | 65,535 | 3 × 32,767 = 98,301 | **163,836** (< 2^18) |
| A, a member (`u8` field) | 255 | 98,301 | **98,556** |
| B, a goblin (≤ 255, DS-18) | 255 | 98,301 | **98,556** |
| B with DS-20's recommendation (one `ATTACK_BONUS` a carrier) | 255 | 32,767 | **33,022** |

**The exponent.** A weapon hit's strength is 5 × rank ≤ 75 by the rule, so `x ≤ 75`. The member's
`u8` field would accept up to 255, which clamps to 80. The checked-in table
(`helpers/exp2_table.cairo`) gives `table(75) = 240,387` and `table(80) = 262,144`.

| Case | `base × table(x)` | Bound |
|---|---:|---|
| A, conservative (163,836 at `x = 80`) | 42,948,624,384 | < 2^36 = 68,719,476,736 |
| B (98,556 at `x = 75`) | 23,691,581,172 | < 2^35 = 34,359,738,368 |
| B with DS-20 (33,022 at `x = 80`) | 8,656,519,168 | < 2^34 = 17,179,869,184 |
| A `DAMAGE` entry (32,767 at `x = 80`) | 8,589,672,448 | < 2^34 |

The product needs a **`u64`** in every case, and never a `u256`. After `>> 16` it is ≤ 655,344 (< 2^20).
The percent step then multiplies by at most `100 + 281 = 381`, giving ≤ 249,686,064 (< 2^28), divides
by 100, and clamps to [0, 65,535]. `100 + p ≥ 0` because the sum is floored at −100.

### 1.7 What the fields need, in one list

| Must be decided before the production flattening (CBT-02, ENG-07) | Why |
|---|---|
| DS-1 (per-source bounds as pipeline checks) | Rows 1–4, 8, 9, 13, 14, 20 do not fit under A |
| DS-2 (floors), DS-3 (`health_bonus`) | Rows 1–3's lower ends |
| DS-4 (sources with no field) | Rows 8, 9, 20 |
| DS-5 (saturation of the three duration fields) | Rows 15–17 |
| DS-18 (caste checks) | G1, G7 |
| DS-29 (health regeneration's encoding checked at pack) | Row 4, G6; the rules compute in `i16` either way |
| DS-20 (`ATTACK_BONUS` aggregation), DS-24 (percents across guards) | §1.6, §1.4 |

### 1.8 What D-157 left to this document

| # | D-157 | Written here |
|---|---|---|
| A | Attribute ids: a global id in content, a build-local index in the snapshot; **26** attributes | Row 19, and the skills below name design/03's attributes |
| B | Which slot type carries `QUICK_CAST_EVERY_N` ("whichever content names; DES-06 writes it") | **The inscription**: "everything held", the weapon and the off-hand, so ≤ 2 pairs, the field's count |
| C | `DAMAGE_TYPE`'s one slot type | **The prefix**: the only slot that exists only on weapons (design/15), so no item-context check is needed. A wand, which has no prefix, keeps its type by attribute |
| D | Health-rune identity by modifier id | Row 1 |
| E | `ADRENALINE_DECAY` = 1 quarter a tick until BAL-01 | design/19 §5.8 and FX-12 |

### 1.9 The rest of the state (DES06-3)

These are the quantities design/19 §7 and CBT-01's code carry that §1.3–§1.6 do not sum. They are
**not summed**: each is set whole, replaced, counted down or reset. The proof is the rule and the
field. No capacity failure was found.

| Quantity (field, width) | Bound, and why | Fit |
|---|---|---|
| **Charges of a held effect**: `MemberEffects` slot bits 16–21 and `GoblinTimers.effect_charges`, 6 bits | `BLOCK`'s `v` is 1…63, checked at ranks 0 and 15 (`EntryAssert::assert_legal`); the line between is monotone, so every rank 0–15 stays within 1…63. `ON_ATTACK_CONDITION`'s `charges` is a 6-bit field (`assert_valid`). Charges only go down (a spent block, a spent oil). A new application of the same carrier **replaces** the old one whole, never adds (§5.7, FX-30). `Effect::assert_valid` refuses ≥ 64 | 0…63 ✓ |
| **Rank held by an effect**: slot bits 52–55 and `GoblinTimers.effect_rank`, 4 bits | the source's rank at application: a member's 4-bit snapshot rank, or a caste's 4-bit rank; replaced whole with the effect | 0…15 ✓ |
| **Potion tag** and belt slot | tag 1 bit; with it set the skill field holds a belt slot, and `assert_valid` refuses ≥ 4 | ✓ |
| **Counters** `hits`, `casts`, `casts_2` (`MemberState`, `u8` each) | each increments to N ≤ 255 and resets to 0 at N (§5.12). N is the kit's or the bar's byte. The stored value is < N; the value before the reset is at most 255. With N = 0 the counter stays 0 | 0…255 ✓ |
| **Belt counts** (`MemberState`, 4 × `u8`) | set at entry from the reserve (a `u8` in `Snapshot.belt_counts`); only drops in play | ✓ |
| **Goblin activation field** (`GoblinTimers`, slot 8 bits) | 0–3 (a caste skill), 254 recovering, 255 none (§5.2) | ✓ |
| **Base durations** (entry `d0`, `d12`; `SKILL` activation and recharge) | ≤ `MAX_BASE_DURATION` = 43,688, checked by `assert_valid` at pack, and at rank 15 by `assert_legal` | `u16` ✓ |
| **Durations carried as values** (`CONDITION`, `ON_ATTACK_CONDITION`) | 1…32,767 at ranks 0 and 15 (§2.1) | `i16` ✓ |
| **Effective durations** (`durations::effective_duration`) | base × (100 + ≤ 50) / 100 + ≤ 3. A holding duration gives at most ⌊43,688 × 150 / 100⌋ + 3 = 65,532 + 3 = **65,535** = `MAX_DURATION`. A condition gives ⌊32,767 × 150 / 100⌋ + 3 = 49,150 + 3 = **49,153**. The function asserts ≤ `MAX_DURATION` | `u32` intermediate ✓ |
| **Deadlines** (effects, conditions, activations, recharges, recoveries: 28 bits) | `D = t₀ + d − 1`. An action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − MAX_DURATION − MAX_WEIGHT_TICKS` (`types.cairo`), so every deadline stays ≤ `MAX_CLOCK` = 2^28 − 1 = **268,435,455**. A charge-only effect stores `MAX_CLOCK` itself (§3.4) | 28 bits ✓ |
| **Activation after quick cast** | the header's activation − (≤ 2 counters' bonuses), floored at 1 for a non-instant skill (§5.12, FX-43) | ✓ |
| **Weapon ticks and range**: a member's (`MemberStats`, `u8` each), a caste's (4 bits each, `WeaponAssert`) | design/15: ticks 1–2, range 1–6. The sheets use 1–2 and 1–6 | ✓ (≤ 15 for a caste) |
| **An attack's tick cost** | `max(k, n + 1)`, with `k` ≤ 255 (member) or 15 (caste) and `n` ≤ 43,688 | `u32` ✓ |
| **`SKILL` header** | energy `u8`, adrenaline `u8` (strikes; a goblin can use ≤ 63, DS-18), range `u8`, target 2 bits | ✓ |
| **`ITEM`** | a bomb's range `u8`, strength `u8` (row 10) | ✓ |
| **A placed trap's `param`** (16 bits) | a member: 3 + 3 bits; a goblin: entity − 8 ≤ 3,593 < 4,096 in 12 bits + a 2-bit caste skill (design/19 §7.2) | ✓ |
| **A goblin's level and caste** (`GoblinState`, `u8`, `u16`) | copied from the pack's template | ✓ |

## 2. The caste sheets of the MVP

The MVP has five castes (design/09): Runt, Slinger, Skirmisher, Shaman and Hobgoblin. Each sheet is
CBT-01's `CASTE` (design/19 §7.3, `models::caste::Caste`), field by field. The values are **initial
values**, which BAL-01 tunes.

### 2.1 How the values are reasoned

- **Rank** (skills and weapon strength): the highest rank that design/03's adventurer at the tier's
  middle level can buy in one attribute. design/03 gives 5 points a level from 2 to 10, 10 from 11
  to 15 and 15 from 16 to 20, plus 15 at Tin and 15 at Copper; a tier is met from the guild rank
  design/05 gives it. Each tier's rank:
  - Tier 1 (levels 1–6): 10 points at level 3 → **4**.
  - Tier 2 (levels 3–10): 25 points at level 6 → **6**.
  - Tier 3 (levels 6–14, from Tin): 45 + 15 at level 10 → **9**.
  - Tier 4 (levels 10–20, from Copper): 95 + 30 at level 15 → **12**.
  - Tiers 5–6 (above level 20): 12 plus the rune's 3 that an adventurer reaches "with everything"
    (design/15), extrapolated (FX-0b) → **14** and **15**.

  One rank covers a caste's whole range (DS-12); §2.4 checks both ends.
- **Health multiplier**: chosen so that fodder dies in about 4 sword hits of an adventurer of its
  level, a melee goblin in about 10, a caster in about 7 (the "kill first" target) and the brute in
  about 30 (§2.4).
- **Armor**: the profession analogue's class (design/03: 80 / 70 / 60), lowered by tier; the fodder
  at 20. design/03 keeps an adventurer's armor flat by class until BAL-01 (D-148), and a caste's is
  flat for the same reason (DS-11).
- **Armor per damage type**: the analogue class's innate bonus (design/15). A Vanguard analogue gets
  +20 against physical (types 1–3), a Warden analogue +30 against elemental (4–7), a caster none.
- **Energy and regeneration**: the analogue's (design/03: Vanguard 20 / 2, Warden 25 / 3, casters
  30 / 4). A caste without skills gets **0 / 0**.
- **Weapon**: a class of design/15's table, with its damage at requirement 9 (design/04's
  midpoints), ticks and range. The damage type is the class's (design/04), or chosen where the class
  has none. The damage is flat whatever the level until DS-11 is decided.

### 2.2 The sheets

AI profiles are numbered in design/05's order (**proposed**, DS-10 ★): 1 `swarm`, 2 `kite`,
3 `flank`, 4 `support`, 5 `brute`, 6 `caster`, 7 `boss`. Weapon classes and damage types use
CBT-01's ids (`combat::weapon`, `combat::damage`).

| Field (bits) | Runt | Slinger | Skirmisher | Shaman | Hobgoblin |
|---|---|---|---|---|---|
| tier (8) | 1 | 1 | 2 | 3 | 4 |
| AI profile (8) | 1 `swarm` | 2 `kite` | 3 `flank` | 4 `support` | 5 `brute` |
| health multiplier, % (16) | 50 | 40 | 50 | 60 | 100 |
| health regeneration, pips (8, stored + 10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) |
| armor (8) | 20 | 20 | 40 | 30 | 60 |
| armor per type 1–9 (9 × 6) | 0 × 9 | 0, 0, 0, 30, 30, 30, 30, 0, 0 | 20, 20, 20, 0 × 6 | 0 × 9 | 20, 20, 20, 0 × 6 |
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
| loot table (16) | CNT-01 id | CNT-01 id | CNT-01 id | CNT-01 id | CNT-01 id |
| boss (1) | 0 | 0 | 0 | 0 | 0 |

Skill ids and loot table ids are content, which CNT-01 seeds. The names above are design/03's
skills and §3's new ones. Every value lies inside §1.5's bounds under B. v0.1 had Skirmisher 70 and
Hobgoblin 150; §2.4's recount with type armor lowered them.

### 2.3 Why each caste looks like this

- **Runt** (fodder melee, `swarm`, no analogue).
  - It has the **axe**. A swarm surrounds, and being surrounded is dangerous by geometry
    (design/04); the axe's +25 % from the rear arcs makes that true of runts without a rule of
    their own.
  - It fights with its weapon only (design/19 §8).
  - It flees below **30 %** when last of its pack (design/05's `swarm`). "Last of pack" is the
    profile's rule; the percent is the sheet's.
- **Slinger** (fodder ranged, `kite`, Warden analogue).
  - design/15 has no sling. The **bow** class gives its rules (range 6, two ticks, line of sight),
    and the stone gives the **blunt** type (DS-19).
  - It gets +30 against elemental from the Warden's medium class.
  - It fights with its weapon only.
  - "Targets lowest armor" is a target-selection rule of the profile over the members (M-3), not a
    sheet field.
- **Skirmisher** (melee, `flank`, Vanguard analogue).
  - It "applies Bleeding" with design/03's **Rending Cut** (a Blades attack, 5 / – / 8, Bleeding
    5…20).
  - Rending Cut needs the Blades weapon, the **sword** (design/19 §3.4: an attack skill needs the
    weapon of its attribute).
  - Flanking puts it in a rear-side arc, where blocks are ignored (design/04).
- **Shaman** (support caster, `support`, Cleric / Arcanist analogue).
  - design/03 says the Cleric comes first after the MVP "because goblin shamans already need most of
    its skills". So its heal is a Cleric skill (**Mend Kin**, Mending, §3.2).
  - Its "shields" are `ARMOR` (FX-20): design/03's **Stone Skin** cast on an ally. Its magnitude
    is DS-22.
  - It has the **staff** and **earth** damage. A caster's type is "by attribute" (design/04), and
    none of the shaman's attributes has one, so the type is chosen.
  - It heals first, then shields (§3.3).
- **Hobgoblin** (brute, `brute`, Vanguard analogue).
  - "Heavy hits with wind-up (telegraphed)": the **maul** and **Overhead Smash**, an attack skill
    with activation 3 (design/19 §8, §10.2).
  - Its act costs `max(2, 3 + 1) = 4` ticks (FX-5, FX-15). That gives the three ticks to step away,
    interrupt or brace that design/04 promises, and fits design/14's quest "interrupt its wind-up"
    with Skullring.

### 2.4 The check behind the multipliers (DES06-5)

The table is computed with integer arithmetic: `⌊base × table(x) / 2^16⌋` with the checked-in table,
`x` clamped, and hits rounded up. The assumptions:
- The adventurer is at the caste's lowest, middle and highest level, with §2.1's rank in the
  attribute used.
- Its sword does 18 with the requirement met (design/04), at strength 5 × rank, with no level cap
  (DS-9) and no personalisation.
- Its Ember Bolt does `15 + 45 r / 12`, truncated, at strength 3 × level.
- **The target's armor includes its type armor**: +20 against the slashing sword for the Skirmisher
  and the Hobgoblin, +30 against the fire bolt for the Slinger.
- Goblins hit with their flat weapon damage (DS-11) at strength 5 × caste rank. They hit a Vanguard
  at 80 + 20 against a physical weapon (its heavy class's innate bonus; the Shaman's earth is
  elemental, so 80), and an Arcanist at 60.
- There are no arcs, modifiers or skills.

| Caste | Level (rank) | Health | Sword hits | Ember Bolts | Its hit on a Vanguard | The Vanguard lasts | Its hit on an Arcanist | The Arcanist lasts |
|---|---|---:|---:|---:|---|---:|---|---:|
| Runt | 1 (0) / 3 (4) / 6 (6) | 50 / 70 / 100 | 5 / 4 / 5 | 5 / 3 / 3 | 4 a tick | 25 / 35 / 50 | 8 a tick | 13 / 18 / 25 |
| Slinger | 1 (0) / 3 (4) / 6 (6) | 40 / 56 / 80 | 4 / 4 / 4 | 7 / 4 / 4 | 5 per 2 ticks | 40 / 56 / 80 | 10 per 2 ticks | 20 / 28 / 40 |
| Skirmisher | 3 (4) / 6 (6) / 10 (8) | 70 / 100 / 140 | 8 / 10 / 12 | 5 / 4 / 4 | 5 a tick | 28 / 40 / 56 | 10 a tick | 14 / 20 / 28 |
| Shaman | 6 (8) / 10 (9) / 14 (12) | 120 / 168 / 216 | 6 / 8 / 8 | 4 / 4 / 3 | 8 per 2 ticks | 50 / 70 / 90 | 12 per 2 ticks | 34 / 48 / 60 |
| Hobgoblin | 10 (10) / 15 (12) / 20 (12) | 280 / 380 / 480 | 28 / 32 / 40 | 10 / 9 / 8 | 13 per 2 ticks | 44 / 60 / 74 | 27 per 2 ticks | 22 / 30 / 36 |

What the table shows, for BAL-01:
- The Slinger's +30 elemental makes a level-1 Arcanist need 7 bolts: the analogue's rule, visible.
- Goblins' damage does not grow with level until DS-11 is decided, so "lasts" grows with the
  adventurer's health alone.
- A pack multiplies the goblin columns.

### 2.5 Bosses and Hearts: separate records

A caste sheet has one `boss` bit, so **a boss is its own `CASTE` record**. The MVP needs:
- a boss Hobgoblin: the boss of D1 (design/01, design/14) and the Copper Rift's Heart (design/17);
- beside it, the pack Hobgoblin of the *Hob guard* and of design/14's "brute at the bridge";
- Hearts for the Wood (Skirmisher) and Tin (Shaman) grades.

**Proposed** (DS-13): a boss record is its caste's sheet with the health multiplier **× 3** and
`boss = 1`, and nothing else changed. Its guaranteed drop (design/07) comes from **its own loot table
id**, since its rewards differ from the pack caste's (the auditor's view). A Red Rift's misgraded
Heart (design/17) is the next grade's Heart record.

| Record | Of caste | Health % | boss | Loot table | Where |
|---|---|---:|:-:|---|---|
| Skirmisher Heart | Skirmisher | 150 | 1 | its own | Wood Rift |
| Shaman Heart | Shaman | 180 | 1 | its own | Tin Rift |
| Hobgoblin, boss | Hobgoblin | 300 | 1 | its own | D1's last floor; Copper Rift; the Iron-grade Heart of a Copper Red Rift, with its retinue (a pack) |

### 2.6 Boss phases

design/05's `boss` profile has "scripted phases by health thresholds"; design/19 §7.3 gives phases no
field (**P**, FX-20). The Hobgoblin's phases are designed below, whatever ends up carrying them:

| Phase | While | Priority list | What the player reads |
|---|---|---|---|
| 1 | health > 50 % | Overhead Smash, then the maul | the telegraphed wind-up, with three ticks to answer |
| 2 | health ≤ 50 % | **Nest Call** once (a shout, skill kind 6: it alerts every pack within 8 tiles, design/19 §3.4; no entry), then Overhead Smash | "the nest answers": reinforcements from packs already on the floor, without a summon |

How the phases are carried, and where the "once" is remembered, is **DS-14**.

## 3. The castes' skills and priority lists

### 3.1 design/03's skills a caste uses

| Skill | Caste | design/03 | Entries (design/19) | Missing |
|---|---|---|---|---|
| Rending Cut | Skirmisher | Blades, Attack, 5 / – / 8 | `CONDITION` Bleeding, `v` 5…20 (§2.1); range: the weapon's | — |
| Stone Skin | Shaman | Stone, Enchantment, 10 / 1 / 20, "+armor for 8…20 ticks" | `ARMOR`, `v` **?**, `d` 8…20; `ALLY`, `SINGLE`, `ALLIES` (the source included, M-5); range **?** | no armor value, no range → **DS-22** (proposed `v` 10…30, range 6) |
| Hamstring Shot | Trapper | Archery, Attack, 10 / 1 / 10, "Crippled for 3…12 ticks" | `CONDITION` Crippled, `v` 3…12; range: the bow's | — |
| Snare | Trapper | Trapping, Trap, 10 / 2 / 20, "Crippled + 10…40 damage to foes entering" | `TRAP` (`TILE`, `SINGLE`); `DAMAGE`, type **?**, 10…40; `CONDITION` Crippled, `v` **?** (design/19 §10.10's earth and 3 ticks are illustrative); range **?** | → **DS-32** |
| Cleave | Champion | Axes, Attack, 4 adrenaline, "+10…30 damage" | `ATTACK_BONUS` 10…30 | — |
| Brace | Champion, Paladin | Tactics, Stance, 5 / 0 / 15, "Block the next 1…3 attacks" | `BLOCK`, `v` 1…3, `d` **?** (`BLOCK` reads `d`, and 0 would not stay); `SELF` | no duration → **DS-33** |
| Warcry | Champion | Might, Shout, 5 / 0 / 20, "+armor penetration for 5…11 ticks" | `PENETRATION`, `v` **?**, `d` 5…11, scope `WEAPON` (FX-27); addressing **?** (the shouter only, or its allies) | no magnitude, no addressing → **DS-30** |
| Second Wind | Paladin, Lord | Tactics, `Skill`, 5 / 1 / 20, "Heal 40…140, more if below 50 % health" | `HEAL` 40…140; `HEAL` **?** guarded `BELOW_HALF` (FX-17 fixes the form, not the amount); `SELF` | no amount for "more" → **DS-31** |

A goblin's rank is its sheet's for every skill, whatever the skill's attribute (design/19 §2.2).
Every value of every caste skill is either given above and in §3.2, or escalated (DS-22, DS-30 to
DS-33). These values are also the adventurers' (design/03's starter skills), so CNT-01 needs them
either way.

### 3.2 New skills the castes need

These are built only from design/19's catalogue and are legal under §5.14 (`assert_carrier`). The
names are working names; values are rank 0…12, in design/03's format. CNT-01 seeds them as `SKILL`
records. Each is checked at rank 15 (FX-0b) against its kind's bounds.

| Skill | Profession, attribute, kind | Energy / activation / recharge | Entries | Why |
|---|---|---|---|---|
| **Mend Kin** | Cleric, Mending, Spell | 10 / 2 / 8, range 6 | `HEAL` 20…100 (rank 15: 120), `ALLY`, `SINGLE`, `ALLIES` | The Shaman "heals the pack" (design/05). As a spell it is interruptible, so the adventurer can stop it (design/04) |
| **Overhead Smash** | Vanguard, Mauls, Attack | 10 / 3 / 10 | `ATTACK_BONUS` 20…60 (rank 15: 70), `FOE`, `SINGLE`, `FOES`: **one** entry | design/19 §8 and §10.2: an attack skill with activation 3 |
| **Nest Call** | Vanguard, Tactics, Shout | 0 / 0 / 0 | none: its only effect is the shout's alert (carrier-level, §5.14 step 6) | The boss's phase 2 (§2.6, DS-14) |
| **Trample** | Vanguard, Axes, Attack | 6 adrenaline / – / – | `CONDITION` Knocked down, `v` 2 (both ranks) | Wolf rider (§4) |
| **Disrupting Chop** | Vanguard, Axes, Attack | 5 / 0 / 12 | `INTERRUPT` (kind 17), `FOE`, `SINGLE` | Champion (§4). Kind 17 is legal in CBT-01 (≤ `LAST_MVP` 18). design/19 marks it **P** only because the MVP has no source; its rule is §5.9 |
| **Gnawing Rot** | Gravecaller, Curses, Hex | 10 / 2 / 12, range 6 | `REGENERATION` −2…−5 (rank 15: −5), `d` 8…16, `FOE`, `SINGLE`, `FOES` | Hexer's hex (§4) |
| **Sap Will** | Beguiler, Dominion, Spell | 5 / 1 / 10, range 6 | `ENERGY` −5…−15 (rank 15: −17), `FOE`, `SINGLE`, `FOES` | Hexer's energy denial (§4) |
| **Rally the Nest** | Vanguard, Tactics, Shout | 10 / 0 / 20 | `PENETRATION` 10…25 % (rank 15: 28), `d` 6…12, scope `WEAPON`; `SELF`, `RING_1`, `ALLIES` (radius 1: FX-21) | Lord's buff (§4); the shout also alerts packs within 8 |

Adrenaline costs: Trample's 6 strikes, and design/03's Cleave (4) and Skullring (6), are ≤ 63
(DS-18).

### 3.3 Priority lists (design/04: position, then the first usable skill, else the weapon)

| Caste | Priority | Then |
|---|---|---|
| Runt | — | the axe on the nearest member |
| Slinger | — | the bow, from range |
| Skirmisher | Rending Cut | the sword |
| Shaman | Mend Kin on the lowest-health ally, then Stone Skin on an ally | the staff, from ≥ 3 tiles |
| Hobgoblin | Overhead Smash | the maul |
| Hobgoblin, boss | phase 1 as the Hobgoblin; phase 2: Nest Call once, then Overhead Smash | the maul |

What makes a skill **usable** for a goblin is not written anywhere: **DS-15 ★**.

## 4. The castes after the MVP

These are design/05's other six castes, in the same shape. **Every field of the record is filled.**
The parts the catalogue or the rules cannot carry yet are escalations, each naming what it needs.
None of these castes enters content before design/09's "after the MVP". Rank comes from §2.1;
health, armor and energy are reasoned as in §2.1.

| Field (bits) | Trapper | Wolf rider | Hexer | Champion | Paladin | Lord |
|---|---|---|---|---|---|---|
| tier (8) | 2 | 3 | 4 | 5 | 6 | 6 |
| AI profile (8) | 2 `kite` **provisional** (DS-16) | 3 `flank` | 6 `caster` | 3 `flank` | 5 `brute` | 7 `boss` |
| health % (16) | 60 | 100 | 80 | 150 | 200 | 300 |
| health regeneration (8, stored + 10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) | 0 (10) |
| armor (8) | 30 | 50 | 40 | 70 | 80 | 70 |
| armor per type 1–9 (9 × 6) | 0, 0, 0, 30, 30, 30, 30, 0, 0 | 20, 20, 20, 0 × 6 | 0 × 9 | 20, 20, 20, 0 × 6 | 20, 20, 20, 0 × 6 | 0 × 9 |
| weapon class / damage / type / ticks / range | 4 bow / 21 / 2 piercing / 2 / 6 | 2 axe / 17 / 1 slashing / 1 / 1 | 6 wand / 16 / 8 shadow / 2 / 6 | 2 axe / 17 / 1 slashing / 1 / 1 | 1 sword / 18 / 1 slashing / 1 / 1 | 1 sword / 18 / 1 slashing / 1 / 1 |
| energy / regeneration (8 + 8) | 25 / 3 | 20 / 2 | 30 / 4 | 20 / 2 | 25 / 3 | 30 / 4 |
| skills, priority (4 × 16) | Snare, Hamstring Shot | Trample | Gnawing Rot, Sap Will, **its trigger** (DS-26) | Disrupting Chop, Brace, Cleave, Warcry | Mend Kin, Second Wind, Brace, **its protection** (DS-27) | Rally the Nest, Second Wind, Nest Call, **reinforcements** (DS-28) |
| rank (4) | 6 | 9 | 12 | 14 | 15 | 15 |
| flee (8) | 0 | 0 | 0 | 0 | 0 | 0 |
| loot table (16) | CNT-01 id | CNT-01 id | CNT-01 id | CNT-01 id | CNT-01 id | CNT-01 id |
| boss (1) | 0 | 0 | 0 | 0 | 0 | 1 |

| Caste | Complete now? | What is missing, and what it needs |
|---|---|---|
| Trapper | Record complete; behaviour incomplete; Snare's values incomplete | "Places traps on chokepoints": no profile says where a trap goes. It needs a profile rule choosing the tile (**DS-16**). Snare's damage type, Crippled duration and range: **DS-32** |
| Wolf rider | Record complete; behaviour incomplete | "Moves 2 tiles per tick": movement is **P** (FX-20). It needs a movement field in `CASTE` and the flood's rule for a 2-tile step (**DS-25**) |
| Hexer | Two skills of three | "Punishes skill spam" is `ON_SKILL_USE` (21), a placeholder (FX-32). It needs the kind's rule: when it fires, on whom, and its entry fields (**DS-26**) |
| Champion | Record and behaviour complete (its interrupt is `INTERRUPT`, kind 17); **two skills' values incomplete** | Warcry's magnitude and addressing (**DS-30**); Brace's duration (**DS-33**) |
| Paladin | Three skills of four; two skills' values incomplete | "Protects the lord" is not catalogued (FX-20). It needs an ally-targeted skill and a priority rule, since Brace is a self-only stance (**DS-27**). Second Wind's "more" (**DS-31**); Brace's duration (**DS-33**) |
| Lord | Three skills of four; phases; one skill's values incomplete | The buff and a reinforcement by alert are carried. A **summon** needs `SUMMON` (22, **P**): its entry, the summoned caste, its entity ids and the awake bound (**DS-28**). Phases need DS-14. Second Wind's "more" (**DS-31**) |

Affixes (*Scarred*, *Rabid*: passives 64–65) are **P** (design/05, design/19 §4).

## 5. Escalations

Each escalation gives the question, the options, the recommendation, **the auditor's view (audit
2)** and the lot that needs it first. **★ = needed first by CBT-02 or ENG-07.** None is decided here.

| # | Question | Options | Recommendation | Auditor's view (audit 2) | First needed by |
|---|---|---|---|---|---|
| **DS-1** ★ | Per-source bounds: §1.3 rows 1–4, 7, 8, 9, 13–17, 20 and §1.5's G1 do not fit under A | (a) adopt B as the pipeline's checks (`PassiveAssert` per source kind, summing a source's benefit and cost; `CasteAssert`); (b) keep A and check totals only at flattening | **(a)**: a bound checked once per record, with the flattening's total checks as a second line | Agrees with per-source plus aggregate checks, after the inventory is completed and A's regeneration proof is corrected (both done in v0.3) | **CBT-02** (its bounds hook), CBT-01 follow-up |
| **DS-2** ★ | A build can reach max health < 1, max energy < 0 or energy regeneration < 0 (rows 1–3); the regeneration field is unsigned | (a) `set_build` refuses such a build (legality, in a hub); (b) the flattening clamps; (c) store energy regeneration signed (+ 10), an interface change | **(a)**, floors 1, 0 and 0, computed in signed intermediates before conversion | Agrees with signed computation, then rejection | **CBT-02** (regeneration reads it), CBT-08 |
| **DS-3** ★ | `MemberKit.health_bonus` is `u16`; the equipment's health sum is −525…+575 (B) | (a) write only the total in `MemberStats.max_health` and free the field; (b) make it `i16` | **(a)** | Prefers (a); (b) also fits without another word | **CBT-02** |
| **DS-4** ★ | Passives with no field outside their source: `ENERGY_COST`, `BASE_DAMAGE_PERCENT`, `ATTRIBUTE` | (a) refuse them on every record but their source: runes for `ATTRIBUTE`, none for the other two; (b) fold bounded values into existing fields with saturation, which needs its own approved bounds and semantics; (c) new fields | **(a)** for all three: it is the option B proves | Agrees with an explicit policy; B proves (a); (b) would need its own bounds | **CBT-02** |
| **DS-5** ★ | Condition duration, enchantment duration and knock-down overflow their kit fields under A | (a) per-source bounds (≤ 33 on the prefix, ≤ 20 on the inscription, ≤ 1 on set bonuses); (b) **saturate when flattening at the runtime's caps** (50 %, 50 %, 3 ticks, `durations.cairo`), summing in a wide integer first | **(b)**, with (a)'s values as the content bounds | Agrees with (b), with wide sums before saturation | **CBT-02** (durations, CBT-9) |
| **DS-6** | Life steal and energy on hit have no values in design/15 | (a) the baseline's +5 life steal with −1 health pip, and +1 energy with −1 energy pip, paired on one modifier, on held slots; (b) BAL-01 first | **(a)** as bounds; BAL-01 sets the values under them | Accepts the values and the pairing as initial limits | CNT-01, BAL-01 |
| **DS-7** ★ | The primary attributes and the light armor have no values | bounds: *Wellspring* ≤ 3 energy a rank (≤ 45); *Might* ≤ 1 % a rank (≤ 15, attack skills); *Fieldcraft* ≤ 1 energy a rank (≤ 15, Warden skills); light armor ≤ +20 energy, ≤ +1 pip. Values: BAL-01 | the bounds as written | Supplied and sufficient for B | **CBT-02** (max energy), CBT-03, CBT-05 |
| **DS-8** ★ | design/15 says "about 16 with everything"; the snapshot holds 0–15 | (a) 15, and design/15's text corrected after approval; (b) a fifth bit | **(a)** | Agrees | **CBT-02** |
| **DS-9** ★ | "Strength = 5 × rank, capped by level" (design/04): no formula for the cap | (a) no cap in the MVP, as an explicit decision; (b) `min(5 × rank, 3 × level + k)`; (c) BAL-01 sets it before CBT-03 | **(c)**; meanwhile (a) only if decided explicitly | Needs a decision before implementation; the uncapped balance figures are labelled assumptions | **CBT-02** (it writes `weapon_strength`), CBT-03 |
| **DS-10** ★ | AI profile ids: CBT-01's `ai` byte names none | 1–7 in design/05's order | adopt them | Agrees | **ENG-07** |
| **DS-11** ★ | design/05: "Level scales health, armor and damage"; only health has a formula | (a) armor flat (as D-148 for adventurers); damage **`⌊d × (380 + 80 × min(L − 1, 19)) / 1900⌋`**, one division at the end (20 % at level 1, 100 % from level 20, the dropped item's curve of design/15; `255 × 1,900 = 484,500` fits a `u32`); (b) armor and damage flat; (c) BAL-01 | **(a)**. That a goblin's weapon matches its drop is not an established rule, only the reason for the choice. §2.4's check uses **flat** damage, not this formula | Concrete enough to decide; keep the integer order and keep it apart from the flat-damage check (done) | **ENG-07** (spawned goblins' stats) |
| **DS-12** ★ | One rank per caste across its level range | (a) the middle level's (§2.1), with endpoint checks (§2.4); (b) rank derived from level; (c) one record per level band | **(a)** | Accepts, supported by the endpoint checks | **ENG-07** |
| **DS-13** | A boss is its own `CASTE` record; its multiplier | (a) the caste's sheet, health × 3, `boss = 1`, its own loot table; (b) tuned one by one | **(a)** | Agrees | CNT-01 |
| **DS-14** | Boss phases have no field (§7.3 **P**) | (a) no phases in the MVP; (b) a phase field in `CASTE` part 1's empty high limb (24 bits) plus 1 "once" bit in `GoblinTimers`' free bits 124–127; (c) a caste switch at the threshold | **(a)** for the MVP, **(b)** when the Lord comes | Agrees; (b) fits without another word | CNT-01; post-MVP |
| **DS-15** ★ | When a goblin's skill is **usable** (design/04) | (a) recharged, affordable, a legal target in range, and one whose state the skill changes: below max health for `HEAL`; for a holding entry, a target that does not hold the carrier, or holds it with a **deadline earlier** than the new application's, or an **equal** deadline with a lower rank or fewer charges than the new one (FX-30 replaces on a tie); (b) recharged and affordable only | **(a)** | Prefers state-sensitive usability, with equal-deadline replenishment specified (done) | **ENG-07** (the AI) |
| **DS-16** | The Trapper's profile: none says where a trap goes | (a) a profile 8 `trapper`: Snare on the tile at distance 2 on the member's shortest path to it, ties by lowest tile index; if that tile is not legal (FX-14), the next along the path, else no trap and kite; (b) `kite` with Snare on a neighbour of the member's tile; (c) defer | **(c)**, with (a) as the design when it comes | Agrees; the profile needs deterministic ties and a legal-tile fallback (added to (a)) | post-MVP |
| **DS-17** | Goblin-only skills carry a profession | (a) the analogue's; (b) a goblin profession | **(a)** | Agrees | CNT-01 |
| **DS-18** ★ | Checks the caste record lacks | health multiplier ≤ 1,000 %; energy regeneration ≤ 10; weapon damage ≤ 255; flee ≤ 100; the referenced skills' adrenaline ≤ 63 strikes, resolved across records by the pipeline | add them | Agrees, with cross-record validation | **ENG-07** (G1 under A overflows `GoblinState.health`), CBT-01 follow-up |
| **DS-19** | The Slinger's weapon | (a) the bow class, blunt; (b) a seventh class | **(a)** | Agrees | CNT-01 |
| **DS-20** ★ | Several `ATTACK_BONUS` entries on one attack skill (CBT-01 accepts up to 3) | (a) summed; (b) at most one a carrier (a pipeline check) | **(b)**; `u64` in either case | (b) is a reasonable explicit restriction; (a) is correctly bounded | CBT-03, **ENG-07** (its cost vectors) |
| **DS-21** ★ | Several `NEXT_SPELL_COST` glyphs held at once | (a) all add and are consumed at the next spell's start; (b) the earliest-deadline one; (c) a glyph replaces a held glyph | **(a)** | Accepts (a); 1,020 covers it | CBT-05 |
| **DS-22** | Stone Skin's armor value **and range** (design/03 gives neither) | (a) `ARMOR` 10…30 (rank 15: 35), range 6 (design/04's range for spells); (b) BAL-01 first | **(a)** as initial content | Accepts 10…30, checked through rank 15 | CNT-01 |
| **DS-23** | Insignias' health "15 / 10 / 5 by piece" (design/15) | (a) **keep 15 / 10 / 5** using the piece: an insignia record names its piece (a byte in `MODIFIER`'s free low limb), and whatever sets it on an item refuses a mismatch against `BASE.slot`; insignias total 40, max health's top 1,020; (b) one value a record, bounded at 15: a design change of design/15, envelope 75, top 1,055 | **(a)**: it keeps design/15, and `BASE.slot` already identifies the piece | Prefers (a); (b) would need to be justified as a design change | CNT-01, CBT-08 |
| **DS-24** | The damage percent at a hit counts both guards' buckets | (a) keep the per-guard bounds (±216; −249…+281 in `i16`); (b) bound a source across guards | **(a)** | Agrees | CBT-03 |
| **DS-25** | The Wolf rider moves 2 tiles a tick | a movement field (4 bits, part 1 high), plus rules for the intermediate tile (occupied, a trap on it) and the flood's 2-tile step; or defer | defer | Agrees; a field alone does not settle collision on the intermediate tile or trap triggering there (added) | post-MVP |
| **DS-26** | The Hexer's trigger, `ON_SKILL_USE` (FX-32) | (a) defer with the Hexer; (b) a holding hex: each skill its holder **starts** (§5.3 step 2) deals `v` damage to it, not a hit (like degeneration, no armor, no on-hit rules), `v`, `d` read | **(a)**, with (b) as the first design | Agrees; timing and damage semantics to be stated (stated in (b)) | post-MVP |
| **DS-27** | The Paladin "protects the lord" | (a) an ally-targeted catalogue skill, e.g. **Shield Kin** (Enchantment, `BLOCK` 1…3, `d` 8…15, `ALLY`, `SINGLE`, `ALLIES`), and a priority rule "the boss ally first"; (b) a new kind redirecting hits, a catalogue amendment | **(a)**. Brace is a self-only stance and cannot become an ally shield by target selection | Prefers (a) | post-MVP |
| **DS-28** | The Lord's reinforcements by summon | (a) the shout's alert only (carried now); (b) `SUMMON`: its entry, the caste, entity ids, placement, the awake bound | **(a)** until (b) is designed with FX-20 | Accepts (a) provisionally | post-MVP |
| **DS-29** ★ | **Health regeneration's encoding is not enforced** (DES06-7): `MemberStatsAssert::assert_valid` does not check `health_regen ≤ 20`, and `CasteAssert` checks it only in `assert_legal`, which the registry does not call. So a packed byte 0…255 (pips −10…+245) is accepted | (a) CBT-01 adds `health_regen ≤ 20` to `MemberStatsAssert::assert_valid` (`pack_stats`, at create and at a gate, never in play) and to `CasteAssert::assert_valid` (`pack`, the registry's write). The rules still compute in `i16`. (b) No check: the rules compute in `i16` and clamp (§1.4 proves −64…+285), but a stored +245 silently means "+10 always". (c) The flattening clamps to 0–20 and records are not checked | **(a)**. **Its cost**: two `u8` comparisons, one per packer, unmeasured, of the size of each of the nine `armor_vs < 64` comparisons `pack_stats` already makes. No new slot, no new read, nothing in a tick. The `i16` computation stays either way, as a second line | New in audit 2: use a wider intermediate, or reject or escalate values outside the encoding | **CBT-02** (regeneration, the flattening), **ENG-07** (goblin records), CBT-01 follow-up |
| **DS-30** | Warcry (design/03: "+armor penetration for 5…11 ticks"): no magnitude, no addressing | (a) `PENETRATION` 5…20 % (rank 15: 23), `d` 5…11, scope `WEAPON`, `SELF`, `SINGLE` (the shouter: the MVP has one adventurer); (b) the same on `SELF`, `RING_1`, `ALLIES` for allies; (c) BAL-01 first | **(a)** as initial content | — (new, from DES06-4) | CNT-01, BAL-01 |
| **DS-31** | Second Wind's "more if below 50 %" (FX-17 fixes a second guarded `HEAL`, not its amount) | (a) a second `HEAL` 20…70 (rank 15: 82), guard `BELOW_HALF`, half the first; (b) equal to the first; (c) BAL-01 first | **(a)** | — (new, from DES06-4) | CNT-01, BAL-01 |
| **DS-32** | Snare: its damage type, its Crippled duration and its range (design/03 gives damage 10…40 only; design/19 §10.10's earth and 3 ticks are illustrative) | (a) piercing (spikes), Crippled 3…8 ticks (rank 15: 9), range 1 (an adjacent tile, placed as the baseline's traps at the caster's feet); (b) earth, 3…8, range 6; (c) BAL-01 first | **(a)** | — (new, from DES06-4) | CNT-01, BAL-01 |
| **DS-33** | Brace's duration (design/03: "Block the next 1…3 attacks"; `BLOCK` reads `d`, and `d = 0` would not stay) | (a) `d` 8…15 (rank 15: 16); it also ends at 0 charges; (b) a long fixed `d` (e.g. 60) so that only charges end it; (c) BAL-01 first | **(a)** | — (new, from DES06-4) | CNT-01, BAL-01 |

## 6. Acceptance tests the validators and the flattening owe (D-157 G)

These are for CBT-01's follow-up (the validators) and CBT-02 (the production flattening). v0.1's
"widest build" fixture is withdrawn (DES06-6). Envelopes are tested as **inequalities**. Each
attainable maximum gets **its own legal build**.

1. **Per-source bounds.** For each row of §1.3 and §1.5 under B, a record at its per-source bound
   passes, one a unit beyond is refused, and a source kind that may not hold the passive is refused.
   A modifier whose benefit and cost name one statistic is checked on their sum.
2. **Extremal builds, one per statistic.** The flattened field equals the attainable value:
   - max health **1,020** under DS-23 (a) (insignias 15 / 10 / 5 on chest, legs and the three
     others), or **1,055** under DS-23 (b). Either way: level 20, a one-handed weapon and a shield,
     five +30 held slots, five +50 health runes of distinct ids, two +50 set bonuses. **The fixture
     depends on DS-23's decision**;
   - max energy **130**: an Arcanist at *Wellspring* 15 in light armor, holding a sword and a
     shield or focus (anyone may hold any weapon, design/15), five held slots and two set bonuses at
     +5;
   - weapon damage 32: a personalised maul at requirement 9;
   - ranks 15: 12 points and a +3 rune.

   Each other field is ≤ its envelope.
3. **Floors.** Level 1 with every cost at its bound, for max health, max energy and energy
   regeneration: refused or clamped, whichever DS-2 decides. Never a panic in `enter`.
4. **Saturation** (DS-5 (b)): condition duration 65,534 → 50, enchantment 340 → 50, knock-down
   4 → 3; armor against a type 149 → 63.
5. **Rune identity**: two health runes of one modifier id count once; of two ids, both count.
6. **A caste at its bounds**: `m` = 1,000 at level 255 gives 51,800; energy 85; a skill of 63
   strikes. It packs, and the goblin's health, energy and adrenaline fit `GoblinState`. `m` = 1,001
   is refused (DS-18).
7. **One hit**:
   - `base = 98,556` at `x = 75` computes 23,691,581,172 in a `u64` (`>> 16`: 361,504);
   - `base = 163,836` at `x = 80` computes 42,948,624,384 (while A holds);
   - with DS-20 (b), a second `ATTACK_BONUS` is refused.
8. **Percent at a hit**: the passives at +216 with critical and axe give +281; at −216 with Weakness
   they give −249, floored at −100.
9. **Health regeneration** (DES06-7):
   - today, a `MemberStats` with `health_regen = 137` (+127 pips) packs. With four +10
     `REGENERATION` effects, step 3's sum is 167 in the `i16`, and the clamp gives +10;
   - under DS-29 (a), `pack_stats` refuses 21 and accepts 20, and a caste with 21 is refused at
     `pack`;
   - the extremes −64 (field 0, four −10 effects, three conditions) and +285 compute without
     overflow.
10. **The state of §1.9**: an effect of 63 charges and rank 15 round-trips; 64 and 16 are refused.
    A counter at N − 1 = 254 with N = 255 reaches 255 and resets to 0.
    `effective_duration(43,688, 50, 3)` = 65,535; `effective_duration(32,767, 50, 3)` = 49,153.
