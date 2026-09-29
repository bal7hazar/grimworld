# [Opus 5.5] DES-06 — Caste sheets, and the per-source bounds of every statistic

## Summary

The new `docs/design/20-castes.md` (Draft v0.1) now holds three things.

1. **Per-source bounds (§1).** Each statistic that design/19 §7.2 and §7.3 lists now has:
   - a signed bound for each source: the build, the armor class, the 5 held-item modifier slots, 5 insignias, 5 runes, 2 set bonuses, personalisation, effects, the caste;
   - a total, checked against the field that stores it.

   Every total fits its field or is escalated (DS-2, DS-3, DS-5). The section can be used on its own by CBT-02 and by CBT-01's validators.
2. **Caste sheets (§2–§4).**
   - The five MVP castes are in CBT-01's `CASTE` shape, with initial values, their reasoning and a hits-to-kill check.
   - Three boss/Heart records. The Hobgoblin's phases are designed; how they are stored is escalated as DS-14.
   - Skills and priority lists. Two skills come from design/03 (Rending Cut, Stone Skin). Two new ones are built from the catalogue (Mend Kin, Overhead Smash).
   - The six post-MVP castes are filled in as far as the catalogue allows.
3. **Escalations and tests.** DS-1 to DS-19 each have options and a recommendation (§5). §6 lists the acceptance tests the validators and the flattening owe (D-157 G).

D-157 B, C and E are written in:
- B: the quick-cast modifier's slot is the inscription.
- C: `DAMAGE_TYPE` goes on the prefix.
- E: `ADRENALINE_DECAY` = 1, now in design/19 §5.8 and FX-12.

Pull request: https://github.com/bal7hazar/grimworld/pull/179. Every CI check passed; `indexer-node` was skipped by its filter. The brief names Opus 5.5, and my system prompt says I am Opus 5.5.

## Files changed

- `docs/design/20-castes.md` (new): the bounds, the sheets, the skills, the escalations, the tests.
- `docs/design/05-bestiary.md`: one cross-reference to design/20.
- `docs/design/19-effects.md`:
  - a cross-reference after §7.3;
  - `ADRENALINE_DECAY` = 1 in §5.8 and in FX-12's row (D-157 E).

## Commands run

```
git push -u origin HEAD                       → new branch docs/des-06-caste-sheets
gh pr create --base main …                    → https://github.com/bal7hazar/grimworld/pull/179
gh pr checks 179 --watch --interval 30        → cairo (contracts) pass 1m41s, tooling pass 1m55s, client pass,
                                                every spike pass; indexer-node skipping
python3 (scratch script, deleted, not committed): design/03's points and ranks by level, and §2.4's check
  level 3 → 10 points, rank 4; level 6 → 25, rank 6; level 10 (+ Tin) → 60, rank 9; level 15 (+ Tin, Copper) → 125, rank 12
  runt L3 H=70 sword 3.9 hits; slinger L3 H=56 3.1; skirmisher L6 H=140 9.2; shaman L10 H=168 7.2; hobgoblin L15 H=570 31.7
```

## Cost

— (no Cairo).

## The bounds table (summary of design/20 §1)

| Statistic (field) | Total | Fits |
|---|---|---|
| Max health (`MemberStats.max_health` u16) | −425…+1,055; equipment alone −525…+575 | top ✓; below 1 at low level → DS-2; `MemberKit.health_bonus` u16 unsigned → DS-3 |
| Max energy (`u8`) | −15…+130 | top ✓; below 0 → DS-2 |
| Energy regeneration (`u8` pips) | −5…+7 | unsigned field → DS-2 |
| Health regeneration, snapshot (pips + 10) | −7…+2; in play −61…+42 before the ±10 clamp | ✓ |
| Unguarded armor (`i16`) | ±9,995 (F-21) | ✓ |
| Guarded armor (2 × `i8`) | ±126 | ✓ |
| Armor at a hit | −10,247…+11,330 before the floor | `i32` ✓ |
| Armor per type (9 × 6 bits) | 149 | saturated at 63 (FX-23) ✓ |
| Attribute ranks (4 bits) | 0…15 | ✓ exactly; design/15's "about 16" → DS-8 |
| Weapon damage (`u8`) | 0…32 | ✓ |
| Strength (`u8`) | ≤ 75 | ✓; the level cap is undefined → DS-9 |
| Damage percents (6 × `i8`) / at a hit | ±126 / −159…+191 | ✓ |
| Penetration (3 × `u8`) | 0…252, capped 100 at use | ✓ |
| Life steal / energy on hit (`u8`) | 0…25 / 0…5 (proposed values, DS-6) | ✓ |
| Condition duration (6 bits) | 0…33 | ✓ with DS-5's bound |
| Enchantment duration (6 bits) | 0…40 on the inscription only | only with DS-5 (340 otherwise) |
| Knock-down (2 bits) | 0…2 on set bonuses only | only with DS-5 |
| Goblin health (`u16`) | ≤ 51,800 with a multiplier ≤ 1,000 % | ✓ with DS-18's check |
| Goblin adrenaline (`u8` ≤ 252) | skills ≤ 63 strikes | ✓ with DS-18's check |
| Goblin armor at a hit | 0…573 | ✓ |
| One hit's product `base × table` | < 2^34 | needs `u64` (note for CBT-02) |

## The sheets (summary of design/20 §2.2)

| | Runt | Slinger | Skirmisher | Shaman | Hobgoblin |
|---|---|---|---|---|---|
| tier / profile | 1 swarm | 1 kite | 2 flank | 3 support | 4 brute |
| health % / armor | 50 / 20 | 40 / 20 | 70 / 40 | 60 / 30 | 150 / 60 |
| armor vs type | — | +30 elemental | +20 physical | — | +20 physical |
| weapon | axe 17 slashing 1t r1 | bow 21 blunt 2t r6 | sword 18 slashing 1t r1 | staff 16 earth 2t r6 | maul 27 blunt 2t r1 |
| energy / regen | 0 / 0 | 0 / 0 | 20 / 2 | 30 / 4 | 20 / 2 |
| skills (priority) | — | — | Rending Cut | Mend Kin, Stone Skin | Overhead Smash |
| rank / flee | 4 / 30 | 4 / 0 | 6 / 0 | 9 / 0 | 12 / 0 |

Boss records: Skirmisher Heart 210 %, Shaman Heart 180 %, Hobgoblin boss 450 %, each with `boss = 1`.

The post-MVP castes are Trapper, Wolf rider, Hexer, Champion, Paladin and Lord. Each has a sheet, and the parts the catalogue cannot carry are named.

## Acceptance criteria

- [x] **AC-1**: design/20 §1.2 and §1.3 give, for every statistic, the per-source bounds (signed) and the total. Each total is checked against its field. The ones that don't fit are escalated: DS-2 (health, energy, energy regeneration below their floors), DS-3 (unsigned `health_bonus`), DS-5 (the kit's condition, enchantment and knock-down fields).
- [x] **AC-2**: design/20 §2.2 covers the five MVP castes and §2.5 the boss records, in CBT-01's field order and widths. §4 covers the six post-MVP castes. §2.1, §2.3 and §2.4 give the reasoning. The skills are design/03's, or new ones built only from design/19's kinds and legal under §5.14 (§3).
- [x] **AC-3**: every value or rule the documents leave open is marked "proposed" and listed in §5 (DS-1 to DS-19) with options and a recommendation. Nothing is decided.

## Deviations from the brief

- **design/19 got more than a cross-reference.** It also received the value of `ADRENALINE_DECAY` (one line in §5.8, one cell in FX-12). D-157 E assigns this to "BAL-01's first pass or DES-06, whichever comes first". The decision was already made; I only wrote it in.
- **The sheets carry initial numbers.** The brief says "initial values BAL-01 tunes", so they are labelled that way. None of them is a rule.
- **Two new goblin skills (Mend Kin, Overhead Smash) are defined as design content**, not seeded; CNT-01 seeds them. Skill and loot table ids are left to CNT-01.

## Escalations

Each one's options and recommendation are in design/20 §5. In short:
- **DS-1**: adopt the "proposed" per-source bounds as pipeline checks.
- **DS-2**: `set_build` should refuse a build with max health < 1, max energy < 0 or energy regeneration < 0.
- **DS-3**: free or sign `MemberKit.health_bonus`.
- **DS-4**: restrict `ENERGY_COST`, `BASE_DAMAGE_PERCENT` and `ATTRIBUTE` (runes only) to their sources. The snapshot has no field for them from other records.
- **DS-5**: bounds for condition duration, enchantment duration and knock-down, so that `enter` cannot panic on a legal record.
- **DS-6**: values for life steal and energy on hit.
- **DS-7**: bounds for Wellspring, the light armor, Might and Fieldcraft.
- **DS-8**: the attribute cap is 15, not "about 16".
- **DS-9**: strength's level cap is undefined.
- **DS-10**: ids for the AI profiles.
- **DS-11**: how level scales a goblin's armor and damage.
- **DS-12**: one rank per caste.
- **DS-13**: boss records and their multiplier.
- **DS-14**: boss phases have no field. Recommendation: none in the MVP, and a 24-bit field in `CASTE` part 1 later.
- **DS-15**: when a goblin's skill counts as "usable".
- **DS-16**: what blocks the post-MVP castes, including **FX-32, the Hexer's trigger**. Recommendation: defer it with the Hexer.
- **DS-17**: the goblin-only skills' profession.
- **DS-18**: checks the caste record lacks (multiplier ≤ 1,000 %, adrenaline ≤ 63 strikes, and others).
- **DS-19**: the Slinger's weapon class.

**Note for CBT-02:** one hit's `base × table(x)` needs a `u64` (design/20 §1.4).

**Glossary terms for the project manager (CONTEXT §5):**
- **caste sheet**: a caste's `CASTE` record;
- **per-source bound**: what one source may add to a statistic;
- **Heart**: the boss of a Rift (design/17 uses the word without a glossary entry);
- **boss record**: a caste's boss variant, its own `CASTE` record.

## Open questions

- Whether the bounds should be checked per record (DS-1 (a)) or only at flattening. The choice decides whether CBT-01's follow-up or CBT-02 owns §6's tests 1 and 3.

## Fix loop 1

The `[GPT-6-Astra]` audit 1 of PR 179 at `8bb57a4` was a **FAIL**: four majors (DES06-1 to DES06-4) and two minors (DES06-5, DES06-6). I merged `origin/main` first; it had not moved since `dba0368` ("Already up to date"). The fix is commit `cd2fc36`, which makes `docs/design/20-castes.md` Draft v0.2 and changes only that file. PR: https://github.com/bal7hazar/grimworld/pull/179. CI on `cd2fc36`: every check passed; `indexer-node` was skipped by its filter.

### How the totals are recounted

Every statistic now shows two envelopes, with the arithmetic:
- **A: CBT-01 today.** Every combination its validators accept, read from the code: `PassiveAssert::{assert_legal, allows, assert_contributions}`, `ModifierAssert::{assert_legal, assert_catalogue}`, `ArmorSetAssert`, `EntryAssert::{assert_legal, assert_carrier}` and `CasteAssert`, against the snapshot's field widths.
- **B: proposed.** The same, with DS-1's per-source bounds.

Where a total can't actually be reached, an attainable figure from a legal build is shown beside it.

The count of sources is corrected:
- 1 prefix, 2 suffixes, 2 inscriptions, 5 insignias, 5 runes and 2 set bonuses: **17 sources**.
- Each modifier holds 2 passives, which may name the same statistic. That gives 15 × 2 + 2 = **32 passives**.
- CBT-01's F-21 counted 37. That was an over-count, and its conclusion (±9,995) still holds: the recount gives −8,160…+8,720.

Under A, **rows 1–4, 7–9, 13–17 and 20 and goblin G1 do not fit their fields**. A statistic open to any source takes 32 × 32,767 = 1,048,544 under A. That is why DS-1 (per-source checks) and DS-5 (saturation) must be decided before the production flattening (§1.7).

### The findings

| # | Fix |
|---|---|
| DES06-1 (major) | §1.6: CBT-01's `assert_carrier` accepts up to 3 `ATTACK_BONUS` entries on an attack skill. See the hit-product table below. Test §6.7 is updated. How several bonuses combine is escalated as **DS-20 ★**; the recommendation is at most one per carrier, which gives 8,656,519,168 < 2^34 |
| DES06-2 (major) | §1.4: at a hit, the `ALWAYS` and `ABOVE_HALF` buckets both count. See the percent table below. It stays per-guard, the validators' own rule; **DS-24** escalates the alternative of a bound across guards. Test §6.8 is added |
| DES06-3 (major) | §1.2 lists every source with its count. See the inventory list below. §1.4 adds the in-play quantities with their intermediate widths: health, energy, energy cost, health regeneration, adrenaline, armor, penetration and percent at a hit |
| DES06-4 (major) | Every sheet is now complete. See the sheets list below |
| DES06-5 (minor) | §2.4 is recomputed with integer arithmetic and the checked-in table, including type armor on both sides. See the multipliers list below |
| DES06-6 (minor) | The "widest build" fixture is withdrawn. §6.2 now has one legal extremal build per statistic, and every other field is tested as an inequality against its envelope. See the attainable-values list below |

**The hit product (DES06-1):**

| Case | Base | `base × table(x)` | Bound |
|---|---:|---:|---|
| A, goblin | 65,535 + 3 × 32,767 = 163,836 | at `x = 80`: 42,948,624,384 | < 2^36 |
| B, goblin damage ≤ 255 | 98,556 | at `x = 75` (`table` 240,387): 23,691,581,172 | < 2^35 |

A `u64` holds every case; no `u256` is needed. After `>> 16` the value is ≤ 655,344, then × 381 gives 249,686,064.

**Damage percent at a hit (DES06-2):**
- Passives: 5 × 36 + 2 × 18 = **±216**.
- With critical +40 and axe +25: **+281**. With Weakness −33: **−249**.
- It fits `i16`, and is floored at −100.

**The source inventory (DES06-3):**
- The primary attributes: *Might*, *Fieldcraft* and *Wellspring* now have numeric bounds (≤ 15, ≤ 15 and ≤ 45) under DS-7 ★.
- Light armor's innate energy bonus.
- Glyphs: `NEXT_SPELL_COST`, up to 4 held, which could reach 1,020; how several combine is **DS-21 ★**.
- Bomb strength: `ITEM.strength`, ≤ 255.
- Goblin spell and trap strength: 3 × 255 = 765, computed in `i32`.
- `HIT_PENETRATION`: up to 3 per carrier.
- Effect counts: 4 for a member, 1 for a goblin.
- Instant entries.

**The sheets (DES06-4):**
- The six post-MVP sheets now have `health_regen` and `loot_table`.
- Their skills are named and parameterised in §3.2, each checked at rank 15: Trample, Disrupting Chop (`INTERRUPT`), Gnawing Rot, Sap Will, Rally the Nest, and Nest Call, the boss's phase-2 shout.
- **The Champion is now complete.** Kind 17 is legal in CBT-01; design/19 marks it P only because the MVP has no source for it.
- Each remaining gap is an escalation that says what it needs: Trapper **DS-16**, Wolf rider **DS-25**, Hexer's trigger **DS-26**, Paladin's protection **DS-27**, Lord's summon **DS-28**.
- Stone Skin's missing armor value is **DS-22**.

**The multipliers (DES06-5):**
- Type armor counts on both sides: goblins +20/+30, and the Vanguard's +20 against physical.
- Each caste is checked at the ends and the middle of its level range.
- **Two initial values are lowered** so the stated targets still hold: Skirmisher 70 → **50** %, Hobgoblin 150 → **100** %. The boss records follow: Skirmisher Heart 150, Hobgoblin boss 300.
- Stated assumptions: requirement met, no level cap (DS-9), flat goblin damage (DS-11).
- The boss records now have their own loot tables (DS-13, the auditor's view).

**Attainable values (DES06-6):**
- Max energy 125 (wand and focus), not 130.
- Insignias: 15 / 10 / 5 by piece is not representable in a `MODIFIER`. This is **DS-23**; the envelope stays 75.

### Escalations after fix loop 1

The numbering is kept: DS-1 to DS-19, with DS-20 to DS-28 added. Each now carries the auditor's view and the first lot that needs it. The full table is design/20 §5.

**★ Needed first by CBT-02:**
- DS-1: per-source bounds.
- DS-2: floors.
- DS-3: `health_bonus`.
- DS-4: sources without a field.
- DS-5: **the recommendation changed to the auditor's**: saturate at the runtime's caps (50 %, 50 %, 3 ticks), which is lossless for the rule.
- DS-7: primary attributes.
- DS-8: rank 15.
- DS-9: the strength cap. The auditor asks for an explicit decision; the recommendation is BAL-01, with "no cap meanwhile" only if decided.

**★ Needed first by ENG-07:**
- DS-10: AI profile ids.
- DS-11: level scaling, now with an explicit damage formula, `⌊d × (20 + 80 × min(L − 1, 19) / 19) / 100⌋`.
- DS-12: one rank per caste.
- DS-15: usability, now with the refresh rule.
- DS-18: caste checks. The adrenaline check resolves the referenced skills.
- DS-20: `ATTACK_BONUS` aggregation (CBT-03 and ENG-07's cost vectors).

**Others:**
- CBT-03: DS-24.
- CBT-05: DS-21.
- CNT-01: DS-6, DS-13, DS-17, DS-19, DS-22, DS-23.
- Post-MVP: DS-14 (now counts the "once" state bit in `GoblinTimers`' free bits 124–127), DS-16, DS-25 to DS-28.

### Acceptance criteria after fix loop 1

- [x] **AC-1**: every statistic, including in-play quantities and the goblin's, has its per-source bounds under A and B and a total with arithmetic. Each total fits its field, is saturated by a stated rule, or is escalated (§1.3–§1.7).
- [x] **AC-2**:
  - Every caste has a complete record in CBT-01's shape (§2.2, §4).
  - Every skill is specified from the catalogue (§3.1–§3.2), except those escalated with what they need: DS-16, DS-22 and DS-25 to DS-28.
  - Values are reasoned and checked (§2.4).
- [x] **AC-3**: every value or rule the documents leave open is an escalation. Each has options, a recommendation, the auditor's view, and the lot that first needs it.

### Commands run in fix loop 1

```
git fetch origin && git merge --no-edit origin/main     → Already up to date (origin/main at dba0368)
python3 .des06_check.py 50 40 70 60 150                 → v0.1's values with type armor, integer arithmetic:
    Skirmisher L6 H=140 sword 12 → 12 hits; Hobgoblin L15 H=570 sword 12 → 48 hits (v0.1 said 9.2 and 31.7)
    Slinger L1 bolt 6 → 7 casts
python3 .des06_check.py 50 40 50 60 100                 → the values adopted (the §2.4 table)
    table(75) = 240387, table(80) = 262144
    98,556 × table(75) = 23691581172 < 2^35; 163,836 × table(80) = 42948624384 < 2^36, ≥ 2^35
python3 -c "…"                                          → 23691581172 >> 16 = 361504; 42948624384 >> 16 = 655344; × 381 = 249686064
git diff --check                                        → clean
git push                                                → 8bb57a4..cd2fc36
gh pr checks 179 --watch --interval 30                  → cairo (contracts) pass 1m45s, tooling pass 1m51s, client pass,
                                                          every spike pass; indexer-node skipping
```

The scratch script read the table from `contracts/logic/src/helpers/exp2_table.cairo`. It was deleted and not committed.

### Deviations in fix loop 1

- **Initial values changed**: Skirmisher and Hobgoblin health multipliers, and the boss records. The recount showed v0.1's targets were missed. They are still initial values for BAL-01.
- **New goblin skills are specified as design content** (§3.2), as in v0.1; CNT-01 seeds them.

## Fix loop 2

The `[GPT-6-Astra]` re-audit of PR 179 at `cd2fc36` was a **FAIL**:
- resolved: DES06-1, DES06-2 and DES06-5;
- partial: DES06-3 and DES06-6 (minor) and DES06-4 (major);
- new: **DES06-7** (major).

I merged `origin/main` first; it had not moved from `dba0368` ("Already up to date"). The fix is commit `f3706f3`, which makes `docs/design/20-castes.md` Draft v0.3; no other file changed. CI on `f3706f3`: every check passed; `indexer-node` was skipped by its filter. PR: https://github.com/bal7hazar/grimworld/pull/179.

### The findings

**DES06-7 (major): health regeneration under A.**

The proof now covers what CBT-01 accepts today. It no longer assumes a restriction CBT-01 does not enforce:
- `MemberStatsAssert::assert_valid` checks only `armor_vs`. So `pack_stats` accepts any `health_regen` byte 0…255, which means pips **−10…+245**.
- For goblins, `CasteAssert` checks ≤ 20 only in `assert_legal`, and the registry does not call it. So a packed caste also holds 0…255.

In play (§1.4, G6):
- **A member under A**: −10 − 40 − 14 = **−64** … 245 + 40 = **+285**.
- **A goblin under A**: **−34…+255**.
- Both are computed in **`i16`**, then clamped to ±10. An `i8` holds only B's −61…+42.
- The auditor's counterexample is now a test (§6.9): +127 pips packs as 137, and four +10 effects make 167.

The check CBT-01 would have to add is escalated as **DS-29 ★** (CBT-02, ENG-07):
- **The validator:** `health_regen ≤ 20` in `MemberStatsAssert::assert_valid` (`pack_stats`, at create and at a gate) and in `CasteAssert::assert_valid` (`pack`, the registry's write).
- **Its cost:** two `u8` comparisons, one per packer. Unmeasured; each is the size of one of the nine `armor_vs < 64` comparisons `pack_stats` already makes. No slot, no read, nothing in a tick.
- **Recommendation:** add the check, and keep the `i16` computation as a second line.

**DES06-4 (major): every caste skill value is specified or escalated.**
- §3.1 now lists every design/03 skill a caste uses, with its entries.
- The gaps are escalated with proposed values and the lot that needs them:
  - **DS-30**: Warcry's magnitude and addressing (proposed 5…20 %, `SELF`);
  - **DS-31**: Second Wind's "more" (a second `HEAL` 20…70, `BELOW_HALF`);
  - **DS-32**: Snare's damage type, Crippled duration and range (piercing, 3…8, range 1);
  - **DS-33**: Brace's duration, since `BLOCK` reads `d` (8…15);
  - **DS-22**, extended: Stone Skin's range (6), besides its value.
- Every value is checked at rank 15 (35, 23, 82, 9, 16).
- The completeness claims are corrected. The Champion's record and behaviour are complete, but Warcry and Brace are waiting on DS-30 and DS-33. The Paladin's and the Lord's rows name DS-31 and DS-33 too.
- These are also the adventurers' starter-skill values, so CNT-01 needs them either way.

**DES06-3 (minor): the rest of the state.**

A new **§1.9** proves each quantity from its rule and its field. None of them is summed:
- **effect charges**: 0…63; `BLOCK` is checked at ranks 0 and 15 on a monotone line, and a new application replaces the old one (FX-30), never adds;
- **held ranks**: 0…15;
- **the potion tag and belt slot**;
- **the counters** `hits`, `casts` and `casts_2`: < N ≤ 255, at most 255 before the reset;
- **belt counts**;
- **the goblin's activation states**;
- **base durations**: ≤ 43,688;
- **durations carried as values**: ≤ 32,767;
- **effective durations**: at most 65,535 in general and 49,153 for a condition;
- **deadlines**: ≤ `MAX_CLOCK` = 268,435,455 through `LAST_TICK`;
- **activation after quick cast**: ≥ 1;
- **weapon ticks and range**: bytes for a member, 4 bits for a caste; the design values are 1–2 and 1–6;
- **an attack's tick cost**;
- **the `SKILL` header, `ITEM`, a placed trap's `param`, and the goblin's level and caste.**

No capacity failure was found in any of them. Test §6.10 is added.

**DES06-6 (minor): the extremal builds.**
- **Max energy: the maximum is 130, and it is attainable.** Anyone may hold any weapon (design/15), so an Arcanist with a sword and a shield or focus has all 5 held slots. The fixture is changed accordingly.
- The health fixture now **depends on DS-23**: **1,020** if insignias keep 15 / 10 / 5 by piece, **1,055** with one value per record.

### Escalations after fix loop 2

Numbering is kept: DS-1 to DS-28, with DS-29 to DS-33 added. Every row now carries **audit 2's view**. Changes following the auditor:
- **DS-4:** the recommendation is (a) for all three passives, since B proves that option.
- **DS-5:** wide sums before saturating.
- **DS-11:** the formula is written with one division at the end, `⌊d × (380 + 80 × min(L − 1, 19)) / 1900⌋`, and kept apart from §2.4's flat-damage check.
- **DS-15:** equal-deadline replenishment is specified (FX-30).
- **DS-16:** deterministic path ties and a legal-tile fallback.
- **DS-23:** **the recommendation changed to the auditor's.** Keep 15 / 10 / 5 by naming the piece on the insignia record and checking it against `BASE.slot`.
- **DS-25:** the intermediate tile's collision and trap.
- **DS-26:** the trigger's timing and damage semantics are stated.
- **DS-27:** changed to an ally-targeted skill (Shield Kin, `BLOCK` on `ALLY`) plus a priority rule, since Brace is self-only.

**★ Needed first by CBT-02:** DS-1, 2, 3, 4, 5, 7, 8, 9, 29.
**★ Needed first by ENG-07:** DS-10, 11, 12, 15, 18, 20, 29.

The others:
- CBT-03: DS-24.
- CBT-05: DS-21.
- CNT-01 and BAL-01: DS-6, 13, 17, 19, 22, 23, 30–33.
- Post-MVP: DS-14, 16, 25–28.

### Acceptance criteria after fix loop 2

- [x] **AC-1**: every statistic, and every other state quantity (§1.9), has a bound proven against CBT-01's accepted values and field widths, under A and under B. Where A needs a check CBT-01 lacks, the check is escalated (DS-1, DS-5, DS-18, DS-29), never assumed.
- [x] **AC-2**: every caste has a complete record. Every skill value is specified (§3.1, §3.2) or escalated with a proposal: DS-22, DS-30 to DS-33, and the deferred mechanics DS-16 and DS-25 to DS-28.
- [x] **AC-3**: every open value or rule is an escalation. Each has options, a recommendation, audit 2's view, and the lot that first needs it.

### Commands run in fix loop 2

```
git fetch origin && git merge --no-edit origin/main   → Already up to date (origin/main at dba0368)
(source inspection) snapshot.cairo:43–59 MemberStatsAssert checks armor_vs only; models/caste.cairo:
    assert_valid checks armor_vs, rank, energy; assert_legal checks health_regen ≤ 20;
    types.cairo: MAX_CLOCK 0xFFFFFFF, MAX_DURATION 0xFFFF, LAST_TICK = MAX_CLOCK − MAX_DURATION − MAX_WEIGHT_TICKS;
    ephemeral member.cairo: Effect::assert_valid charges < 64, rank < 16, belt slot < 4
(arithmetic) rank 15: Stone Skin 10 + 20×15/12 = 35; Warcry 5 + 15×15/12 = 23; Second Wind extra 20 + 50×15/12 = 82;
    Snare Crippled 3 + 5×15/12 = 9; Brace d 8 + 7×15/12 = 16; ⌊43,688 × 150/100⌋ + 3 = 65,535; ⌊32,767 × 150/100⌋ + 3 = 49,153
git diff --check                                      → clean
git push                                              → cd2fc36..f3706f3
gh pr checks 179 --watch --interval 30                → cairo (contracts) pass 1m43s, tooling pass 1m56s, client pass,
                                                        every spike pass; indexer-node skipping
```

### Deviations in fix loop 2

None beyond the brief. Only `docs/design/20-castes.md` changed. The proposed skill values (DS-30 to DS-33, DS-22) are escalated initial content, not decisions.
