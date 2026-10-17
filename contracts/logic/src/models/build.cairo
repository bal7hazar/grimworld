//! The production flattening (design/19 §4, §7.2; design/20 §1, D-160): a build's loadout
//! (`models::loadout`) and the passives it holds (`models::held_passive`, from the items worn,
//! `models::worn`) into the snapshot's three words (`models::snapshot`). `FlattenLibrary` runs it
//! for `Hub.set_build` (D-168).
//!
//! design/19 §7.2 (FX-24, D-155) flattens every passive the rules read into these three words,
//! losslessly, with **0 new slots**: `MemberBar`'s free high limb takes the damage and penetration
//! sums, the quick-cast pairs and the unguarded armor; `MemberKit`'s high limb is repacked;
//! `MemberStats` holds the armor against each damage type where the single armor, the physical and
//! elemental armors and the single penetration were.

use crate::helpers::duration::MAX_DURATION_BONUS_PERCENT;
use crate::helpers::packing::{P16, P32, P48, P64, P80};
use crate::models::base::slot as base_slot;
use crate::models::held_passive::HeldPassive;
use crate::models::loadout::Loadout;
use crate::models::member_bar::{MemberBar, MemberBarTrait, QuickCast};
use crate::models::member_kit::{MemberKit, MemberKitTrait, saturate};
use crate::models::member_stats::{MemberStats, MemberStatsTrait};
use crate::models::snapshot::Snapshot;
use crate::models::worn::{Worn, WornTrait};
use crate::types::effect::guard;
use crate::types::hit::HitTrait;
use crate::types::passive::{Source, id};
use crate::types::profession::ProfessionTrait;

pub mod errors {
    // The production flattening's (`BuildAssert`, `FlattenAssert`, `SnapshotBuildTrait::build`).
    pub const SOURCE_COUNT: felt252 = 'build: too many of a source';
    pub const ORDER: felt252 = 'build: instances out of order';
    pub const MAX_HEALTH: felt252 = 'build: max health below 1';
    pub const MAX_ENERGY: felt252 = 'build: max energy below 0';
    pub const ENERGY_REGEN: felt252 = 'build: energy regen below 0';
    pub const POINTS: felt252 = 'build: points above 12';
    pub const WEAPON_DAMAGE: felt252 = 'build: weapon damage above 27';
    pub const RATING: felt252 = 'build: rating above 560';
    pub const QUICK_CAST_ATTRIBUTE: felt252 = 'build: quick-cast attribute';
    pub const OVERFLOW: felt252 = 'build: sum outside its field';
    pub const PIECE_TWICE: felt252 = 'build: two insignias a piece';
}

// The production flattening (design/19 §4, §7.2; design/20 §1, D-160): the build and the
// passives it holds into the snapshot's three words. design/20's capacity proof rests on the
// registry's refusals of each record (the per-source bounds, D-166) and on the sums' checks made
// here, linear in the passives. For `Hub.set_build`, whose checks refuse a build, and `Hub.enter`,
// which builds its snapshot through it; not wired yet: with it `Hub`'s class passes ENG-01 §1.3's
// 50 % (CBT-02c's report; D-166 (b), the project manager's). No production snapshot before
// (D-160).

/// Armor against a type saturates at 63 (6 bits, FX-23).
pub const MAX_ARMOR_VS: u32 = 63;
/// The knock-down's flat bonus saturates at 3 ticks (`helpers::duration::MAX_DURATION_FLAT`, DS-5).
pub const MAX_KNOCKDOWN: u32 = 3;
/// Ranks go up to 15 (DS-8: design/15's "about 16" reads 15).
pub const MAX_RANK: u8 = 15;
/// Weapon strength is 5 × the rank of the weapon's attribute, capped by level (design/04, DS-9).
pub const STRENGTH_PER_RANK: u16 = 5;
/// Personalisation: +20 % to the weapon's base damage (design/15 D-48), the only source of
/// `BASE_DAMAGE_PERCENT` (DS-4).
pub const PERSONALISED_DAMAGE_PERCENT: u32 = 120;
/// The weighted rating of the pieces and the shield, personalised (F-21: 255 + 25 + 255 + 25).
pub const MAX_RATING: u16 = 560;
/// Attribute points give a rank of at most 12 (design/03; design/20 §1.2's build B).
pub const MAX_POINTS_RANK: u8 = 12;
/// A weapon's base damage at its requirement, at most the maul's 27 (design/15; design/20 row 9).
pub const MAX_WEAPON_BASE_DAMAGE: u8 = 27;
/// DS-7 (D-160) bounds *Wellspring* at 3 energy a rank and light armor at +20 energy and +1 pip.
/// BAL-01 sets the values; until then the bounds are used, as `ADRENALINE_DECAY` is (escalated).
pub const WELLSPRING_ENERGY_PER_RANK: i32 = 3;
pub const LIGHT_ENERGY: i32 = 20;
pub const LIGHT_ENERGY_REGEN: i32 = 1;
/// design/15's armor classes' innate armor: heavy +20 against physical damage (types 1–3), medium
/// +30 against elemental (4–7); light gives energy (above).
pub const HEAVY_VS_PHYSICAL: u32 = 20;
pub const MEDIUM_VS_ELEMENTAL: u32 = 30;

/// The most instances of each source an adventurer holds (design/20 §1.2): a prefix, 2 suffixes,
/// 2 inscriptions, 5 insignias, 5 runes, 2 set bonuses. A free function: a table.
pub fn max_instances(source: Source) -> u8 {
    match source {
        Source::Prefix => 1,
        Source::Suffix => 2,
        Source::Inscription => 2,
        Source::Insignia => 5,
        Source::Rune => 5,
        Source::SetBonus => 2,
    }
}

/// The instances counted per source, one 16-bit lane each in the order of `Source`, each lane
/// starting at `2^15 − 1 − max_instances`: a lane passes `max_instances` exactly when its bit
/// 15 is set (`COUNTS_OVER`). Instances are numbered upward in a `u8`, so a lane counts at most 256
/// and never carries into the next.
const COUNTS_START: u128 = 0x7ffd7ffa7ffa7ffd7ffd7ffe;
const COUNTS_OVER: u128 = 0x800080008000800080008000;

// The first pass sums every additive passive into three words of signed 16-bit lanes
// (docs/CAIRO.md §3: arithmetic, one multiplication and one addition a word), each lane biased by
// `2^15` from the start. Lane `k` is `2^(16 k)`. Every sum lies within ±32,767 under design/20
// §1.3's envelope B (the widest, the unguarded armor, within ±8,720), so no lane borrows from or
// carries into the next.
// - The statistics: 0 max health (a health rune's benefit apart), 1 max energy, 2 energy
//   regeneration, 3 health regeneration, 4 unguarded armor, 5 armor in a stance, 6 armor
//   enchanted, 7 life steal, 8 energy on hit, 9 condition duration, 10 enchantment duration,
//   11 knock-down.
// - The hits: the damage percents, lane `3 × guard + class` (0–5), and the penetrations, lane
//   `6 + class` (design/19 §7.2's `MemberBar` order).
// - The types: the armor against each damage type, lane `type − 1`.
const L1: felt252 = 0x10000;
const L2: felt252 = 0x100000000;
const L3: felt252 = 0x1000000000000;
const L4: felt252 = 0x10000000000000000;
const L5: felt252 = 0x100000000000000000000;
const L6: felt252 = 0x1000000000000000000000000;
const L7: felt252 = 0x10000000000000000000000000000;
const L8: felt252 = 0x100000000000000000000000000000000;
const L9: felt252 = 0x1000000000000000000000000000000000000;
const L10: felt252 = 0x10000000000000000000000000000000000000000;
const L11: felt252 = 0x100000000000000000000000000000000000000000000;
const STATISTICS: u32 = 12;
const HITS: u32 = 9;
const TYPES: u32 = 9;
/// `2^15` in each of 12 lanes: the bias that keeps every lane of a signed sum non-negative.
const BIAS: felt252 = 0x800080008000800080008000800080008000800080008000;
const HALF: i32 = 0x8000;
/// The innate armor of the heavy class (types 1–3, `HEAVY_VS_PHYSICAL` each) and of the medium
/// class (types 4–7, `MEDIUM_VS_ELEMENTAL` each), in the types' lanes (design/15).
const HEAVY_LANES: felt252 = 20 * (1 + L1 + L2);
const MEDIUM_LANES: felt252 = 30 * (L3 + L4 + L5 + L6);

#[generate_trait]
pub impl BuildAssert of BuildAssertTrait {
    /// DS-2 (D-160): max health at least 1, max energy and energy regeneration at least 0; the
    /// build is refused below (`set_build`).
    fn assert_floors(health: i32, energy: i32, energy_regen: i32) {
        assert(health >= 1, errors::MAX_HEALTH);
        assert(energy >= 0, errors::MAX_ENERGY);
        assert(energy_regen >= 0, errors::ENERGY_REGEN);
    }

    /// The build's own bounds design/20 §1 sums from (B, row 9, F-21): each attribute's points
    /// give a rank of at most 12, the weapon's base damage at most 27, the rating at most 560.
    fn assert_loadout(loadout: @Loadout) {
        for (_, points) in *loadout.points {
            assert(*points <= MAX_POINTS_RANK, errors::POINTS);
        }
        assert(*loadout.weapon_damage <= MAX_WEAPON_BASE_DAMAGE, errors::WEAPON_DAMAGE);
        assert(*loadout.rating <= MAX_RATING, errors::RATING);
    }

    /// At most design/20 §1.2's count of each source (`COUNTS_OVER`).
    #[inline(always)]
    fn assert_counts(counts: u128) {
        assert(counts & COUNTS_OVER == 0, errors::SOURCE_COUNT);
    }

    /// Instances are numbered upward, so that none is counted twice: a passive of an earlier
    /// instance than `next − 1` is refused.
    #[inline(always)]
    fn assert_order(instance: u16, next: u16) {
        assert(instance >= next, errors::ORDER);
    }

    /// DS-23 (D-160): one insignia a piece. `pieces` holds the pieces counted so far, a bit each,
    /// and `bit` is this insignia's.
    #[inline(always)]
    fn assert_piece(pieces: u8, bit: u8) {
        assert(pieces & bit == 0, errors::PIECE_TWICE);
    }

    /// At most two quick-cast pairs (`MemberBar.quick_cast`).
    #[inline(always)]
    fn assert_pairs(count: u32) {
        assert(count <= 2, errors::QUICK_CAST_ATTRIBUTE);
    }
}

#[generate_trait]
impl FlattenAssert of FlattenAssertTrait {
    /// A quick-cast pair's attribute is a build-local index of 4 bits (D-157 A).
    #[inline(always)]
    fn assert_index(index: u8) {
        assert(index < 16, errors::QUICK_CAST_ATTRIBUTE);
    }

    /// A quick-cast pair names an attribute the build holds: reached when none of `points` is it.
    #[inline(always)]
    fn assert_held() -> core::never {
        core::panic_with_felt252(errors::QUICK_CAST_ATTRIBUTE)
    }
}

#[generate_trait]
impl FlattenImpl of FlattenTrait {
    /// The 16-bit lane of `source` in the counts (`COUNTS_START`).
    fn count_lane(source: Source) -> u128 {
        match source {
            Source::Prefix => 1,
            Source::Suffix => P16,
            Source::Inscription => P32,
            Source::Insignia => P48,
            Source::Rune => P64,
            Source::SetBonus => P80,
        }
    }

    /// What one unit of the passive adds to the three words of sums, `(statistics, hits,
    /// types)`: its lane in one of them (above). A hit's lanes are the classes its scope applies
    /// to (design/19 §5.4, `PassiveTrait::applies_to`): a weapon scope takes a plain weapon hit
    /// and an attack skill's, an attack skill scope the latter, a spell scope a spell's, `ALL`
    /// the three. A health rune's benefit, counted apart, and the passives that are not summed
    /// add nothing.
    fn lanes(held: @HeldPassive) -> (felt252, felt252, felt252) {
        let p = *held.passive;
        let id = p.id;
        if id == id::ARMOR_VS {
            return (0, 0, *[1, L1, L2, L3, L4, L5, L6, L7, L8].span()[(p.param - 1).into()]);
        }
        if id == id::DAMAGE_PERCENT || id == id::PENETRATION {
            let classes = *[1 + L1, L1, L2, 1 + L1 + L2].span()[p.scope.into()];
            let first = if id == id::PENETRATION {
                L6
            } else if p.guard == guard::ABOVE_HALF {
                L3
            } else {
                1
            };
            return (0, classes * first, 0);
        }
        if id == id::ARMOR {
            return (*[L4, 0, 0, L5, L6].span()[p.guard.into()], 0, 0);
        }
        if id == id::MAX_HEALTH {
            if *held.source == Source::Rune && *held.benefit {
                return (0, 0, 0);
            }
            return (1, 0, 0);
        }
        if id < id::MAX_ENERGY || id > id::KNOCKDOWN_FLAT {
            return (0, 0, 0);
        }
        // Ids 43–53: max energy … knock-down.
        (*[L1, L2, L3, 0, 0, 0, L7, L8, L9, L10, L11].span()[(id - id::MAX_ENERGY).into()], 0, 0)
    }

    /// The `count` signed 16-bit lanes of a word of sums (`BIAS` included).
    fn decode(word: felt252, count: u32) -> Array<i32> {
        let wide: u256 = word.into();
        let mut limb = wide.low;
        let mut out: Array<i32> = array![];
        for i in 0..count {
            if i == 8 {
                limb = wide.high;
            }
            let (rest, lane) = DivRem::div_rem(limb, P16.try_into().unwrap());
            let lane: i32 = lane.try_into().unwrap();
            out.append(lane - HALF);
            limb = rest;
        }
        out
    }

    /// The build-local index of `attribute` (its position in `points`, D-157 A), which a
    /// quick-cast pair names; refused when the build has no such attribute.
    fn local_index(points: Span<(u8, u8)>, attribute: u8) -> u8 {
        let mut index: u8 = 0;
        for (a, _) in points {
            if *a == attribute {
                FlattenAssert::assert_index(index);
                return index;
            }
            index += 1;
        }
        FlattenAssert::assert_held()
    }

    /// The bar's attribute mappings (CBT-05f), which no other word holds: the quick-cast pairs
    /// each slot's skill counts for, its global attribute against the global attributes `pairs`
    /// name (D-157 A: the pairs store build-local indices), slot `i`'s pair `p` at bit `2 i + p`;
    /// and the slots whose attack skill names an attribute other than the weapon's (design/19
    /// §3.4), slot `i` at bit `i`. A slot of attribute 0 (none) counts for no pair.
    fn mappings(loadout: @Loadout, pairs: [u8; 2]) -> (u16, u8) {
        let [g0, g1] = pairs;
        let mut attacks = *loadout.bar_attacks;
        if g0 == 0 && g1 == 0 && attacks == 0 {
            return (0, 0);
        }
        let weapon = *loadout.weapon_attribute;
        let mut slots: u32 = 0;
        let mut required: u32 = 0;
        let mut bit: u32 = 1;
        let mut slot_bit: u32 = 1;
        for attribute in loadout.bar_attributes.span() {
            let a = *attribute;
            if a != 0 && a == g0 {
                slots += bit;
            }
            if a != 0 && a == g1 {
                slots += 2 * bit;
            }
            if attacks % 2 == 1 && a != weapon {
                required += slot_bit;
            }
            attacks /= 2;
            bit *= 4;
            slot_bit *= 2;
        }
        (slots.try_into().unwrap(), required.try_into().unwrap())
    }

    /// The rank of `attribute` (0: none): the build's points plus the highest `ATTRIBUTE` rune for
    /// it (design/15; runes only, DS-4), at most 15 (DS-8). `runes` are `(instance, attribute,
    /// value)` in the order held, one instance's adjacent; a rune's contribution is the sum of
    /// its passives for the attribute (AUD-182-3). Registration bounds each passive and each
    /// rune's sum to 1…3, so a running sum only grows and its peak is the highest rune.
    fn rank(points: Span<(u8, u8)>, runes: Span<(u8, u8, i32)>, attribute: u8) -> u8 {
        if attribute == 0 {
            return 0;
        }
        let mut rank: i32 = 0;
        for (a, p) in points {
            if *a == attribute {
                rank = (*p).into();
            }
        }
        let mut best: i32 = 0;
        let mut sum: i32 = 0;
        let mut current: u16 = 256;
        for (instance, a, value) in runes {
            if *a == attribute {
                let instance: u16 = (*instance).into();
                if instance != current {
                    current = instance;
                    sum = 0;
                }
                sum += *value;
                if sum > best {
                    best = sum;
                }
            }
        }
        // Points ≤ 12 (`BuildAssert`) and a rune ≤ 3: at most 15 (DS-8).
        fit(rank + best)
    }

    /// Max health from the health runes' benefits: each modifier id once, at its highest value
    /// (FX-43, D-157 D). At most 5 runes (the counts), so at most 25 comparisons.
    fn rune_health(runes: Span<(u32, i32)>) -> i32 {
        let mut total: i32 = 0;
        let mut i: u32 = 0;
        for (modifier, value) in runes {
            let mut first = true;
            let mut highest = *value;
            let mut j: u32 = 0;
            for (other, v) in runes {
                if *other == *modifier {
                    if j < i {
                        first = false;
                    }
                    if *v > highest {
                        highest = *v;
                    }
                }
                j += 1;
            }
            if first {
                total += highest;
            }
            i += 1;
        }
        total
    }
}

/// An `i32` sum into its field, or refused: design/20 §1 proves each fits under the registry's
/// refusals and the counts, so a failure here is a broken proof, never a legal build. A free
/// function: a conversion generic over every field's type, which no type owns.
fn fit<T, +TryInto<i32, T>>(value: i32) -> T {
    value.try_into().expect(errors::OVERFLOW)
}

#[generate_trait]
pub impl SnapshotBuildImpl of SnapshotBuildTrait {
    /// The production snapshot of a build and the passives it holds (design/19 §4, §7.2;
    /// design/20 §1.3, D-160), linear in the passives (D-166): one pass for the sums, one for
    /// the passives that are not summed.
    ///
    /// Every passive comes from a record the registry accepted (`ModifierAssert::assert_legal`,
    /// `ArmorSetAssert::assert_legal`: its source, its range and the per-source bounds of
    /// design/20 §1.3, DS-1, DS-4, DS-5, DS-23), a benefit at a value its record's range allows;
    /// the passives of one instance adjacent, instances numbered upward (the caller builds them
    /// so: CBT-02c's wiring numbers a modifier `5 × lane + slot`). What a record cannot break is
    /// not checked again; what a sum can break is:
    /// - the counts of each source (§1.2), and one insignia a piece (DS-23);
    /// - the build's own bounds (`assert_loadout`), and a quick-cast pair's attribute in the
    ///   build;
    /// - DS-2's floors, then each sum into its field (`fit`).
    ///
    /// The sums:
    /// - Max health: `100 + 20 (L − 1)` + equipment (rune identity), refused below 1 (DS-2); the
    ///   final maximum is `max_health`, `MemberKit.health_bonus` is freed and 0 (DS-3).
    /// - Max energy: the profession's + *Wellspring* (3 a primary rank, the Arcanist's) + light
    ///   armor's 20 + equipment, refused below 0 (DS-2, DS-7). Energy regeneration: the
    ///   profession's + light armor's 1 + equipment, refused below 0 (DS-2).
    /// - Health regeneration: 10 + equipment, 0–20 (DS-29, checked at pack).
    /// - Armor against each type: the class's innate + equipment, saturated at 63 (row 7: at most
    ///   30 + 17 × 7 = 149 before).
    /// - Ranks: points + the highest rune, ≤ 15 (DS-4, DS-8); the primary's and each bar skill's.
    /// - Weapon damage: personalised +20 % (DS-4); strength `min(5 × rank, cap)` (DS-9).
    /// - The duration percents saturated at 50, the knock-down at 3 (DS-5).
    /// - The rest as design/19 §7.2 flattens it: damage percents per guard and hit class (each
    ///   within ±126) and penetration per hit class (≤ 252), guarded and unguarded armor,
    ///   quick-cast pairs, the lowest N, life steal, energy on hit.
    /// - The bar's attribute mappings (CBT-05f, `FlattenTrait::mappings`): each slot's quick-cast
    ///   pairs, and its attack skill's weapon requirement.
    fn build(loadout: @Loadout, held: Span<HeldPassive>) -> Snapshot {
        BuildAssert::assert_loadout(loadout);
        // The sums, and the counts: a new instance is numbered above the last.
        let mut counts: u128 = COUNTS_START;
        let mut next: u16 = 0;
        let mut pieces: u8 = 0;
        let mut statistics: felt252 = BIAS;
        let mut hits: felt252 = BIAS;
        let mut types: felt252 = BIAS;
        for h in held {
            let instance: u16 = (*h.instance).into();
            if instance + 1 != next {
                BuildAssert::assert_order(instance, next);
                next = instance + 1;
                counts += FlattenTrait::count_lane(*h.source);
                if *h.source == Source::Insignia {
                    let bit: u8 = *[1, 2, 4, 8, 16].span()[(*h.piece - base_slot::CHEST).into()];
                    BuildAssert::assert_piece(pieces, bit);
                    pieces += bit;
                }
            }
            let value: felt252 = (*h.passive.max).into();
            let (s, t, u) = FlattenTrait::lanes(h);
            statistics += value * s;
            hits += value * t;
            types += value * u;
        }
        BuildAssert::assert_counts(counts);

        // The passives that are not summed.
        let mut health_runes: Array<(u32, i32)> = array![];
        let mut attribute_runes: Array<(u8, u8, i32)> = array![];
        let mut pairs: Array<QuickCast> = array![];
        let mut globals: Array<u8> = array![];
        let mut every: u8 = 0;
        let mut halving = false;
        let mut damage_type = *loadout.damage_type;
        let mut condition: u8 = 0;
        for h in held {
            let p = *h.passive;
            let id = p.id;
            let value: i32 = p.max.into();
            if id == id::MAX_HEALTH {
                if *h.source == Source::Rune && *h.benefit {
                    health_runes.append((*h.modifier, value));
                }
            } else if id == id::ATTRIBUTE {
                attribute_runes.append((*h.instance, p.param, value));
            } else if id == id::QUICK_CAST_EVERY_N {
                let attribute = FlattenTrait::local_index(*loadout.points, p.param);
                pairs.append(QuickCast { attribute, every: fit(value) });
                globals.append(p.param);
            } else if id == id::ADRENALINE_EVERY_N {
                let n: u8 = fit(value);
                if every == 0 || n < every {
                    every = n;
                }
            } else if id == id::DAMAGE_TYPE {
                damage_type = p.param;
            } else if id == id::CONDITION_DURATION {
                condition = p.param;
            } else if id == id::HALVE_FIRST_HEAVY_HIT {
                halving = true;
            }
        }
        BuildAssert::assert_pairs(pairs.len());
        while pairs.len() < 2 {
            pairs.append(Default::default());
            globals.append(0);
        }
        let (quick_cast_slots, weapon_required) = FlattenTrait::mappings(
            loadout, [*globals[0], *globals[1]],
        );

        let level: i32 = (*loadout.level).into();
        let profession = *loadout.profession;
        let points = *loadout.points;
        let runes = attribute_runes.span();
        let primary = match points.get(0) {
            Option::Some(entry) => {
                let (attribute, _) = *entry.unbox();
                attribute
            },
            Option::None => 0,
        };
        let primary_rank = FlattenTrait::rank(points, runes, primary);

        // Maxima and regeneration, signed, with DS-2's floors.
        let sums = FlattenTrait::decode(statistics, STATISTICS);
        let health = 100
            + 20 * (level - 1)
            + *sums[0]
            + FlattenTrait::rune_health(health_runes.span());
        let mut energy = *sums[1] + ProfessionTrait::energy(profession).into();
        let mut energy_regen = *sums[2] + ProfessionTrait::energy_regen(profession).into();
        if profession == 3 {
            // Light armor and *Wellspring* (DS-7).
            energy += WELLSPRING_ENERGY_PER_RANK * primary_rank.into() + LIGHT_ENERGY;
            energy_regen += LIGHT_ENERGY_REGEN;
        }
        BuildAssert::assert_floors(health, energy, energy_regen);

        // Armor against each type: the class's innate, then saturated (FX-23).
        let innate = if profession == 1 {
            HEAVY_LANES
        } else if profession == 2 {
            MEDIUM_LANES
        } else {
            0
        };
        let mut armor_vs: Array<u8> = array![];
        for sum in FlattenTrait::decode(types + innate, TYPES) {
            armor_vs.append(saturate(fit(sum), MAX_ARMOR_VS).try_into().unwrap());
        }
        let vs = armor_vs.span();
        let hits = FlattenTrait::decode(hits, HITS);

        // Ranks of the bar's attributes, 4 bits each.
        let mut ranks: u32 = 0;
        for attribute in loadout.bar_attributes.span() {
            ranks = ranks / 16 + FlattenTrait::rank(points, runes, *attribute).into() * 0x10000000;
        }

        // The weapon (DS-4, DS-9).
        let mut weapon_damage: u32 = (*loadout.weapon_damage).into();
        if *loadout.personalised {
            weapon_damage = weapon_damage * PERSONALISED_DAMAGE_PERCENT / 100;
        }
        // One copy of the rule (CBT-05a, carried from CBT-03a): the hit's.
        let strength = HitTrait::weapon_strength(
            FlattenTrait::rank(points, runes, *loadout.weapon_attribute), *loadout.strength_cap,
        );
        let rating: i32 = (*loadout.rating).into();
        Snapshot {
            stats: MemberStats {
                max_health: fit(health),
                max_energy: fit(energy),
                energy_regen: fit(energy_regen),
                health_regen: fit(10 + *sums[3]),
                armor_vs: [*vs[0], *vs[1], *vs[2], *vs[3], *vs[4], *vs[5], *vs[6], *vs[7], *vs[8]],
                level: *loadout.level,
                profession,
                primary_rank,
                weapon: *loadout.weapon,
                weapon_damage: weapon_damage.try_into().expect(errors::OVERFLOW),
                weapon_ticks: *loadout.weapon_ticks,
                weapon_range: *loadout.weapon_range,
                weapon_strength: strength.try_into().unwrap(),
                ranks,
                damage_type,
                requirement_met: *loadout.requirement_met,
                set_bonuses: *loadout.set_bonuses,
                quick_cast_slots,
                weapon_required,
            },
            bar: MemberBar {
                skills: *loadout.skills,
                elite_slot: *loadout.elite_slot,
                damage: [
                    fit(*hits[0]), fit(*hits[1]), fit(*hits[2]), fit(*hits[3]), fit(*hits[4]),
                    fit(*hits[5]),
                ],
                penetration: [fit(*hits[6]), fit(*hits[7]), fit(*hits[8])],
                quick_cast: [*pairs[0], *pairs[1]],
                armor: fit(rating + *sums[4]),
            },
            kit: MemberKit {
                belt: *loadout.belt,
                life_steal: fit(*sums[7]),
                energy_on_hit: fit(*sums[8]),
                condition,
                condition_duration: saturate(fit(*sums[9]), MAX_DURATION_BONUS_PERCENT)
                    .try_into()
                    .unwrap(),
                enchantment_duration: saturate(fit(*sums[10]), MAX_DURATION_BONUS_PERCENT)
                    .try_into()
                    .unwrap(),
                double_adrenaline_every: every,
                // Freed (DS-3): the final maximum is `max_health`.
                health_bonus: 0,
                armor_stance: fit(*sums[5]),
                armor_enchanted: fit(*sums[6]),
                knockdown: saturate(fit(*sums[11]), MAX_KNOCKDOWN).try_into().unwrap(),
                halving,
            },
            belt_counts: *loadout.belt_counts,
        }
    }

    /// The snapshot's three words, packed (`stats`, `bar`, `kit`), of a build and the items it
    /// wears: the passives they hold (`WornTrait::held`), then the flattening (`build`). What
    /// `FlattenLibrary` returns to `Hub.set_build`, which stores them with the adventurer (D-168).
    /// The belt's counts are not in them: `Hub.enter` takes them from the belt it debits.
    fn words(
        loadout: @Loadout, worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>,
    ) -> (felt252, felt252, felt252) {
        let held = WornTrait::held(worn, ids, records);
        let snapshot = Self::build(loadout, held.span());
        (
            MemberStatsTrait::pack(snapshot.stats),
            MemberBarTrait::pack(snapshot.bar),
            MemberKitTrait::pack(snapshot.kit),
        )
    }
}

/// The flattening's unit tests (D-167): design/20 §6's extremal builds, floors, saturations and
/// counts, each compared with the oracle, CBT-02's flattening: every sum a plain pass over the
/// passives per statistic, obviously correct and quadratic (docs/CAIRO.md §2, *Oracles*). The
/// validators' tests (the per-source bounds, the records) are in the records' and
/// `types::passive`'s modules, the capacity proof in `tests/test_build.cairo`, and the registry's
/// refusals in the persistent package's `tests/test_registry.cairo`.
#[cfg(test)]
pub mod tests {
    use crate::helpers::duration::MAX_DURATION_BONUS_PERCENT;
    use crate::models::base::slot as base_slot;
    use crate::models::held_passive::HeldPassive;
    use crate::models::loadout::Loadout;
    use crate::models::member_bar::{MemberBar, MemberBarTrait, QuickCast};
    use crate::models::member_kit::{MemberKit, MemberKitTrait, saturate};
    use crate::models::member_stats::{MemberStats, MemberStatsTrait};
    use crate::models::snapshot::{Snapshot, SnapshotTrait};
    use crate::models::snapshot_words::SnapshotWords;
    use crate::models::worn::WornTrait;
    use crate::models::worn::tests::WornFixture;
    use crate::types::combat::{condition, damage, weapon};
    use crate::types::effect::{guard, scope};
    use crate::types::passive::{
        HIT_ATTACK_SKILL, HIT_SPELL, HIT_WEAPON, Passive, PassiveTrait, Source, id,
    };
    use crate::types::profession::ProfessionTrait;
    use super::{
        BuildAssert, HEAVY_VS_PHYSICAL, LIGHT_ENERGY, LIGHT_ENERGY_REGEN, MAX_ARMOR_VS,
        MAX_KNOCKDOWN, MEDIUM_VS_ELEMENTAL, PERSONALISED_DAMAGE_PERCENT, STRENGTH_PER_RANK,
        SnapshotBuildTrait, WELLSPRING_ENERGY_PER_RANK, errors, fit,
    };

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// CBT-02's sums, the oracle's.
    #[generate_trait]
    impl Oracle of OracleTrait {
        /// `2^n`.
        fn bit(n: u32) -> u32 {
            let mut out: u32 = 1;
            for _ in 0..n {
                out *= 2;
            }
            out
        }

        /// The sum of the passives `id` (any param).
        fn total(held: Span<HeldPassive>, id: u8) -> i32 {
            let mut total: i32 = 0;
            for h in held {
                if *h.passive.id == id {
                    total += (*h.passive.max).into();
                }
            }
            total
        }

        /// The sum of the passives `id` of `param`.
        fn total_param(held: Span<HeldPassive>, id: u8, param: u8) -> i32 {
            let mut total: i32 = 0;
            for h in held {
                if *h.passive.id == id && *h.passive.param == param {
                    total += (*h.passive.max).into();
                }
            }
            total
        }

        /// The sum of the passives `id` of `guard` that apply to hits of `class` (design/19 §5.4).
        fn total_scoped(held: Span<HeldPassive>, id: u8, guard: u8, class: u8) -> i32 {
            let mut total: i32 = 0;
            for h in held {
                if *h.passive.id == id && *h.passive.guard == guard && h.passive.applies_to(class) {
                    total += (*h.passive.max).into();
                }
            }
            total
        }

        /// Max health from the equipment (design/20 §1.3 row 1): every `MAX_HEALTH` passive, but a
        /// rune's benefit counts once per modifier id, the highest (FX-43, D-157 D).
        fn health(held: Span<HeldPassive>) -> i32 {
            let mut total: i32 = 0;
            let mut i: u32 = 0;
            for h in held {
                if *h.passive.id == id::MAX_HEALTH {
                    let value: i32 = (*h.passive.max).into();
                    if *h.source == Source::Rune && *h.benefit {
                        // Counted by the first rune of its id, at the highest value of the id.
                        let mut first = true;
                        let mut highest = value;
                        let mut j: u32 = 0;
                        for other in held {
                            if *other.source == Source::Rune
                                && *other.benefit
                                && *other.passive.id == id::MAX_HEALTH
                                && *other.modifier == *h.modifier {
                                if j < i {
                                    first = false;
                                }
                                let v: i32 = (*other.passive.max).into();
                                if v > highest {
                                    highest = v;
                                }
                            }
                            j += 1;
                        }
                        if first {
                            total += highest;
                        }
                    } else {
                        total += value;
                    }
                }
                i += 1;
            }
            total
        }

        /// The rank of `attribute` (0: none): the build's points plus the highest `ATTRIBUTE` rune
        /// for it (design/15; runes only, DS-4), at most 15 (DS-8).
        fn rank(points: Span<(u8, u8)>, held: Span<HeldPassive>, attribute: u8) -> u8 {
            if attribute == 0 {
                return 0;
            }
            let mut rank: u8 = 0;
            for (a, p) in points {
                if *a == attribute {
                    rank = *p;
                }
            }
            // Each rune's contribution to the attribute is the sum of its `ATTRIBUTE` passives for
            // it (DS-1 bounds that sum to 1…3); the highest rune counts (AUD-182-3).
            let mut rune: i32 = 0;
            for h in held {
                if *h.passive.id == id::ATTRIBUTE && *h.passive.param == attribute {
                    let mut contribution: i32 = 0;
                    for other in held {
                        if *other.instance == *h.instance
                            && *other.passive.id == id::ATTRIBUTE
                            && *other.passive.param == attribute {
                            contribution += (*other.passive.max).into();
                        }
                    }
                    if contribution > rune {
                        rune = contribution;
                    }
                }
            }
            // Points ≤ 12 (`BuildAssert`) and a rune ≤ 3: at most 15 (DS-8).
            let rank: i32 = rank.into() + rune;
            fit(rank)
        }
    }


    #[generate_trait]
    pub impl BuildFixtureImpl of BuildFixture {
        /// CBT-02's flattening of a legal build, the oracle.
        fn oracle(loadout: @Loadout, held: Span<HeldPassive>) -> Snapshot {
            let level: i32 = (*loadout.level).into();
            let profession = *loadout.profession;
            let light = profession == 3;
            let primary = match (*loadout.points).get(0) {
                Option::Some(entry) => {
                    let (attribute, _) = *entry.unbox();
                    attribute
                },
                Option::None => 0,
            };
            let primary_rank = Oracle::rank(*loadout.points, held, primary);

            // Maxima and regeneration, signed, with DS-2's floors.
            let health = 100 + 20 * (level - 1) + Oracle::health(held);
            let base_energy: i32 = ProfessionTrait::energy(profession).into();
            let wellspring = if light {
                WELLSPRING_ENERGY_PER_RANK * primary_rank.into()
            } else {
                0
            };
            let light_energy = if light {
                LIGHT_ENERGY
            } else {
                0
            };
            let energy = base_energy
                + wellspring
                + light_energy
                + Oracle::total(held, id::MAX_ENERGY);
            let base_regen: i32 = ProfessionTrait::energy_regen(profession).into();
            let light_regen = if light {
                LIGHT_ENERGY_REGEN
            } else {
                0
            };
            let energy_regen = base_regen + light_regen + Oracle::total(held, id::ENERGY_REGEN);
            BuildAssert::assert_floors(health, energy, energy_regen);
            let health_regen = 10 + Oracle::total(held, id::HEALTH_REGEN);

            // Armor against each type: the class's innate, then saturated (FX-23).
            let mut armor_vs: Array<u8> = array![];
            for t in 1..10_u8 {
                let innate = if profession == 1 && t <= damage::BLUNT {
                    HEAVY_VS_PHYSICAL
                } else if profession == 2 && t >= damage::FIRE && t <= damage::EARTH {
                    MEDIUM_VS_ELEMENTAL
                } else {
                    0
                };
                let sum: u32 = innate + fit(Oracle::total_param(held, id::ARMOR_VS, t));
                armor_vs.append(saturate(sum, MAX_ARMOR_VS).try_into().unwrap());
            }

            // Ranks of the bar's attributes, 4 bits each.
            let mut ranks: u64 = 0;
            let mut shift: u64 = 1;
            for attribute in loadout.bar_attributes.span() {
                ranks += Oracle::rank(*loadout.points, held, *attribute).into() * shift;
                shift *= 16;
            }
            let ranks: u32 = ranks.try_into().unwrap();

            // The weapon (DS-4, DS-9).
            let mut weapon_damage: u32 = (*loadout.weapon_damage).into();
            if *loadout.personalised {
                weapon_damage = weapon_damage * PERSONALISED_DAMAGE_PERCENT / 100;
            }
            let strength: u16 = STRENGTH_PER_RANK
                * Oracle::rank(*loadout.points, held, *loadout.weapon_attribute).into();
            let cap: u16 = (*loadout.strength_cap).into();
            let strength = if strength > cap {
                cap
            } else {
                strength
            };
            let mut damage_type = *loadout.damage_type;
            let mut replaced = false;
            for h in held {
                if *h.passive.id == id::DAMAGE_TYPE {
                    damage_type = *h.passive.param;
                    replaced = true;
                }
            }

            // Quick-cast pairs: the attribute's build-local index (D-157 A).
            let mut pairs: Array<QuickCast> = array![];
            for h in held {
                if *h.passive.id == id::QUICK_CAST_EVERY_N {
                    let mut index: u32 = 16;
                    let mut k: u32 = 0;
                    for (attribute, _) in *loadout.points {
                        if *attribute == *h.passive.param && index == 16 {
                            index = k;
                        }
                        k += 1;
                    }
                    pairs
                        .append(
                            QuickCast {
                                attribute: index.try_into().unwrap(),
                                every: fit((*h.passive.max).into()),
                            },
                        );
                }
            }
            while pairs.len() < 2 {
                pairs.append(Default::default());
            }

            // The attribute mappings (CBT-05f): a slot counts for a pair whose passive names its
            // attribute (not 0); an attack skill of another attribute than the weapon's needs it.
            let mut named: Array<u8> = array![];
            for h in held {
                if *h.passive.id == id::QUICK_CAST_EVERY_N {
                    named.append(*h.passive.param);
                }
            }
            let mut quick_cast_slots: u16 = 0;
            let mut weapon_required: u8 = 0;
            let mut slot: u32 = 0;
            for attribute in loadout.bar_attributes.span() {
                let mut p: u32 = 0;
                for param in named.span() {
                    if *attribute != 0 && *attribute == *param {
                        quick_cast_slots += Oracle::bit(2 * slot + p).try_into().unwrap();
                    }
                    p += 1;
                }
                let attacks: u32 = (*loadout.bar_attacks).into();
                let attack = attacks / Oracle::bit(slot) % 2 == 1;
                if attack && *attribute != *loadout.weapon_attribute {
                    weapon_required += Oracle::bit(slot).try_into().unwrap();
                }
                slot += 1;
            }

            let mut every: u8 = 0;
            for h in held {
                if *h.passive.id == id::ADRENALINE_EVERY_N {
                    let n: u8 = fit((*h.passive.max).into());
                    if every == 0 || n < every {
                        every = n;
                    }
                }
            }
            let mut halving = false;
            for h in held {
                if *h.passive.id == id::HALVE_FIRST_HEAVY_HIT {
                    halving = true;
                }
            }
            let mut conditions: Array<Passive> = array![];
            for h in held {
                conditions.append(*h.passive);
            }
            let (condition, condition_duration) = MemberKitTrait::condition_duration(
                conditions.span(),
            );
            let rating: i32 = (*loadout.rating).into();
            let d = |guard: u8, class: u8| -> i8 {
                fit(Oracle::total_scoped(held, id::DAMAGE_PERCENT, guard, class))
            };
            let p = |class: u8| -> u8 {
                fit(Oracle::total_scoped(held, id::PENETRATION, guard::ALWAYS, class))
            };
            let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = [
                *armor_vs[0], *armor_vs[1], *armor_vs[2], *armor_vs[3], *armor_vs[4], *armor_vs[5],
                *armor_vs[6], *armor_vs[7], *armor_vs[8],
            ];
            Snapshot {
                stats: MemberStats {
                    max_health: fit(health),
                    max_energy: fit(energy),
                    energy_regen: fit(energy_regen),
                    health_regen: fit(health_regen),
                    armor_vs: [v1, v2, v3, v4, v5, v6, v7, v8, v9],
                    level: *loadout.level,
                    profession,
                    primary_rank,
                    weapon: *loadout.weapon,
                    weapon_damage: weapon_damage.try_into().expect(errors::OVERFLOW),
                    weapon_ticks: *loadout.weapon_ticks,
                    weapon_range: *loadout.weapon_range,
                    weapon_strength: strength.try_into().unwrap(),
                    ranks,
                    damage_type,
                    requirement_met: *loadout.requirement_met,
                    set_bonuses: *loadout.set_bonuses,
                    quick_cast_slots,
                    weapon_required,
                },
                bar: MemberBar {
                    skills: *loadout.skills,
                    elite_slot: *loadout.elite_slot,
                    damage: [
                        d(guard::ALWAYS, HIT_WEAPON), d(guard::ALWAYS, HIT_ATTACK_SKILL),
                        d(guard::ALWAYS, HIT_SPELL), d(guard::ABOVE_HALF, HIT_WEAPON),
                        d(guard::ABOVE_HALF, HIT_ATTACK_SKILL), d(guard::ABOVE_HALF, HIT_SPELL),
                    ],
                    penetration: [p(HIT_WEAPON), p(HIT_ATTACK_SKILL), p(HIT_SPELL)],
                    quick_cast: [*pairs[0], *pairs[1]],
                    armor: fit(rating + Oracle::total_scoped(held, id::ARMOR, guard::ALWAYS, 0)),
                },
                kit: MemberKit {
                    belt: *loadout.belt,
                    life_steal: fit(Oracle::total(held, id::LIFE_STEAL_ON_HIT)),
                    energy_on_hit: fit(Oracle::total(held, id::ENERGY_ON_HIT)),
                    condition,
                    condition_duration,
                    enchantment_duration: saturate(
                        fit(Oracle::total(held, id::ENCHANT_DURATION)), MAX_DURATION_BONUS_PERCENT,
                    )
                        .try_into()
                        .unwrap(),
                    double_adrenaline_every: every,
                    // Freed (DS-3): the final maximum is `max_health`.
                    health_bonus: 0,
                    armor_stance: fit(
                        Oracle::total_scoped(held, id::ARMOR, guard::IN_STANCE, HIT_WEAPON),
                    ),
                    armor_enchanted: fit(
                        Oracle::total_scoped(held, id::ARMOR, guard::ENCHANTED, HIT_WEAPON),
                    ),
                    knockdown: saturate(fit(Oracle::total(held, id::KNOCKDOWN_FLAT)), MAX_KNOCKDOWN)
                        .try_into()
                        .unwrap(),
                    halving,
                },
                belt_counts: *loadout.belt_counts,
            }
        }

        fn passive(id: u8, param: u8, value: i16) -> Passive {
            PassiveTrait::new(id, param, 0, 0, value, value)
        }

        fn scoped(id: u8, guard: u8, scope: u8, value: i16) -> Passive {
            PassiveTrait::new(id, 0, guard, scope, value, value)
        }

        /// The piece an insignia of instance 5–9 is worn on: chest, legs, head, hands, feet (the
        /// order of `sources()`); 0 for every other source.
        fn piece(source: Source, instance: u8) -> u8 {
            if source == Source::Insignia && instance >= 5 {
                base_slot::CHEST + (instance - 5)
            } else if source == Source::Insignia {
                base_slot::CHEST
            } else {
                0
            }
        }

        fn held(passive: Passive, source: Source, instance: u8, modifier: u32) -> HeldPassive {
            HeldPassive {
                passive,
                source,
                instance,
                modifier,
                benefit: true,
                piece: Self::piece(source, instance),
            }
        }

        fn cost(passive: Passive, source: Source, instance: u8, modifier: u32) -> HeldPassive {
            HeldPassive {
                passive,
                source,
                instance,
                modifier,
                benefit: false,
                piece: Self::piece(source, instance),
            }
        }

        /// A level-`level` build of `profession`: 12 points in its primary, 10 in another, a sword
        /// (damage 18 at requirement, ticks 1, range 1) of the other attribute, strength cap 75.
        fn loadout(profession: u8, level: u8) -> Loadout {
            Loadout {
                level,
                profession,
                points: array![(PRIMARY, 12), (OTHER, 10)].span(),
                bar_attributes: [PRIMARY, OTHER, 0, 0, 0, 0, 0, 0],
                bar_attacks: 0,
                skills: [1, 2, 0, 0, 0, 0, 0, 0],
                elite_slot: 255,
                weapon: weapon::SWORD,
                weapon_damage: 18,
                weapon_ticks: 1,
                weapon_range: 1,
                damage_type: damage::SLASHING,
                weapon_attribute: OTHER,
                requirement_met: 1,
                personalised: false,
                strength_cap: 75,
                rating: 0,
                set_bonuses: 0,
                belt: [0; 4],
                belt_counts: [0; 4],
            }
        }

        /// The 17 sources of design/20 §1.2, instances 0–16: a prefix, 2 suffixes, 2
        /// inscriptions, 5 insignias, 5 runes, 2 set bonuses.
        fn sources() -> Span<Source> {
            array![
                Source::Prefix, Source::Suffix, Source::Suffix, Source::Inscription,
                Source::Inscription, Source::Insignia, Source::Insignia, Source::Insignia,
                Source::Insignia, Source::Insignia, Source::Rune, Source::Rune, Source::Rune,
                Source::Rune, Source::Rune, Source::SetBonus, Source::SetBonus,
            ]
                .span()
        }

        /// One passive on each source of `on` (a subset of the 17), instance `i`, modifier id
        /// `100 + i`.
        fn everywhere(p: Passive, on: Span<Source>) -> Array<HeldPassive> {
            let mut all = array![];
            let mut i: u8 = 0;
            for source in Self::sources() {
                let mut take = false;
                for kind in on {
                    if *kind == *source {
                        take = true;
                    }
                }
                if take {
                    all.append(Self::held(p, *source, i, 100 + i.into()));
                }
                i += 1;
            }
            all
        }

        fn held_slots() -> Span<Source> {
            array![Source::Prefix, Source::Suffix, Source::Inscription].span()
        }

        /// The flattening, checked against the oracle on the same build.
        fn flatten(loadout: @Loadout, held: Span<HeldPassive>) -> Snapshot {
            let snapshot = SnapshotBuildTrait::build(loadout, held);
            assert(snapshot == Self::oracle(loadout, held), 'differs from the oracle');
            snapshot
        }

        /// The widest build design/20 §1.2 counts, each passive on one of the flattening's
        /// costliest paths: 17 sources, 32 passives. The held slots: a damage percent on all hits
        /// (two-level lanes) and an energy regeneration cost (the table's path); the insignias: an
        /// enchantment duration (the table) and a guarded armor cost; the runes: five health runes
        /// of distinct ids (their identity pass, 25 comparisons) and an attribute cost (each rank a
        /// pass over them); the set bonuses: a knock-down, the table's last entry. The loadout's
        /// eight bar skills and its weapon name the rune's attribute.
        fn widest() -> (Loadout, Array<HeldPassive>) {
            let mut all = array![];
            let mut i: u8 = 0;
            for source in Self::sources() {
                let s = *source;
                let modifier: u32 = 100 + i.into();
                if s == Source::Prefix || s == Source::Suffix || s == Source::Inscription {
                    all
                        .append(
                            Self::held(
                                Self::scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, 1),
                                s,
                                i,
                                modifier,
                            ),
                        );
                    all.append(Self::cost(Self::passive(id::ENERGY_REGEN, 0, 0), s, i, modifier));
                } else if s == Source::Insignia {
                    all
                        .append(
                            Self::held(Self::passive(id::ENCHANT_DURATION, 0, 1), s, i, modifier),
                        );
                    all
                        .append(
                            Self::cost(
                                PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, 1, 1),
                                s,
                                i,
                                modifier,
                            ),
                        );
                } else if s == Source::Rune {
                    all.append(Self::held(Self::passive(id::MAX_HEALTH, 0, 1), s, i, modifier));
                    all.append(Self::cost(Self::passive(id::ATTRIBUTE, OTHER, 1), s, i, modifier));
                } else {
                    all.append(Self::held(Self::passive(id::KNOCKDOWN_FLAT, 0, 1), s, i, modifier));
                }
                i += 1;
            }
            let build = Loadout { bar_attributes: [OTHER; 8], ..Self::loadout(3, 20) };
            (build, all)
        }
    }

    /// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
    const PRIMARY: u8 = 13;
    const OTHER: u8 = 14;

    // design/20 §6 test 2 (AUD-182-2), the extremal builds at the envelope: every source that
    // may hold a statistic at its per-source maximum (and, where no floor refuses it, its
    // minimum) flattens without overflow, to exactly the envelope.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 13722359)] // ceil(1.05 × 13068913 measured)
    fn test_envelope_builds() {
        // Held slots at 30, insignias at their pieces' 15 / 10 / 5 / 5 / 5 (DS-23), runes and
        // set bonuses at 50.
        let mut all = BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_HEALTH, 0, 30), BuildFixture::held_slots(),
        );
        let mut k: u8 = 0;
        for value in array![15_i16, 10, 5, 5, 5] {
            all
                .append(
                    BuildFixture::held(
                        BuildFixture::passive(id::MAX_HEALTH, 0, value),
                        Source::Insignia,
                        5 + k,
                        200,
                    ),
                );
            k += 1;
        }
        for h in BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_HEALTH, 0, 50),
            array![Source::Rune, Source::SetBonus].span(),
        ) {
            all.append(h);
        }
        let top = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        assert(top.stats.max_health == 1020, 'max health 1,020');
        let low = BuildFixture::flatten(
            @BuildFixture::loadout(3, 20),
            BuildFixture::everywhere(
                BuildFixture::passive(id::HEALTH_REGEN, 0, -1),
                array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus]
                    .span(),
            )
                .span(),
        );
        assert(low.stats.health_regen == 3, 'health regen 3');
        let high = BuildFixture::flatten(
            @BuildFixture::loadout(3, 20),
            BuildFixture::everywhere(
                BuildFixture::passive(id::HEALTH_REGEN, 0, 1), array![Source::SetBonus].span(),
            )
                .span(),
        );
        assert(high.stats.health_regen == 12, 'health regen 12');
        let steal = BuildFixture::flatten(
            @BuildFixture::loadout(3, 20),
            BuildFixture::everywhere(
                BuildFixture::passive(id::LIFE_STEAL_ON_HIT, 0, 5), BuildFixture::held_slots(),
            )
                .span(),
        );
        assert(steal.kit.life_steal == 25, 'life steal 25');
        let hit = BuildFixture::flatten(
            @BuildFixture::loadout(3, 20),
            BuildFixture::everywhere(
                BuildFixture::passive(id::ENERGY_ON_HIT, 0, 1), BuildFixture::held_slots(),
            )
                .span(),
        );
        assert(hit.kit.energy_on_hit == 5, 'energy on hit 5');
        let regen = BuildFixture::flatten(
            @BuildFixture::loadout(3, 20),
            BuildFixture::everywhere(
                BuildFixture::passive(id::ENERGY_REGEN, 0, 1), array![Source::SetBonus].span(),
            )
                .span(),
        );
        assert(regen.stats.energy_regen == 7, 'energy regen 7');
    }

    // §6 test 2: max health 1,020 (DS-23's insignias 15 / 10 / 5, D-160): level 20, five +30
    // held slots, insignias 15, 10, 5, 5, 5, five +50 health runes of distinct ids, two +50 set
    // bonuses. The final maximum is `max_health`; `health_bonus` is freed (DS-3).
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 4498807)] // ceil(1.05 × 4284578 measured)
    fn test_extremal_max_health() {
        let mut all = BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_HEALTH, 0, 30), BuildFixture::held_slots(),
        );
        let insignias = [15_i16, 10, 5, 5, 5];
        let mut k: u8 = 0;
        for value in insignias.span() {
            all
                .append(
                    BuildFixture::held(
                        BuildFixture::passive(id::MAX_HEALTH, 0, *value),
                        Source::Insignia,
                        5 + k,
                        200,
                    ),
                );
            k += 1;
        }
        for held_passive in BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_HEALTH, 0, 50),
            array![Source::Rune, Source::SetBonus].span(),
        ) {
            all.append(held_passive);
        }
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        assert(snapshot.stats.max_health == 1020, 'max health 1,020');
        assert(snapshot.kit.health_bonus == 0, 'health bonus freed');
    }

    // §6 test 2: max energy 130 (DS-7): an Arcanist at Wellspring 15 (12 points and a +3 rune:
    // ranks 15, DS-8) in light armor, five held slots and two set bonuses at +5: 30 + 45 + 20 +
    // 35.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 2701349)] // ceil(1.05 × 2572713 measured)
    fn test_extremal_max_energy_and_rank() {
        let mut all = BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_ENERGY, 0, 5), BuildFixture::held_slots(),
        );
        all
            .append(
                BuildFixture::held(
                    BuildFixture::passive(id::ATTRIBUTE, PRIMARY, 3), Source::Rune, 10, 300,
                ),
            );
        for h in BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_ENERGY, 0, 5), array![Source::SetBonus].span(),
        ) {
            all.append(h);
        }
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(3, 20), all.span());
        assert(snapshot.stats.max_energy == 130, 'max energy 130');
        assert(snapshot.stats.primary_rank == 15, 'rank 15');
        // The bar's ranks: slot 0 the primary (15), slot 1 the other (10), 4 bits each.
        assert(snapshot.stats.ranks == 15 + 10 * 16, 'bar ranks');
        // Light armor's +1 pip (DS-7): 4 + 1.
        assert(snapshot.stats.energy_regen == 5, 'energy regen');
        assert(snapshot.stats.health_regen == 10, 'health regen');
    }

    // The ranks of all eight bar slots at 15 fill `MemberStats.ranks`' 32 bits (4 bits a slot).
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 1413608)] // ceil(1.05 × 1346293 measured)
    fn test_ranks_of_every_bar_slot() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::ATTRIBUTE, PRIMARY, 3), Source::Rune, 10, 300,
            ),
        ];
        let build = Loadout { bar_attributes: [PRIMARY; 8], ..BuildFixture::loadout(3, 20) };
        let snapshot = BuildFixture::flatten(@build, all.span());
        assert(snapshot.stats.ranks == 0xffffffff, 'eight ranks of 15');
    }

    // §6 test 2: weapon damage 32, a personalised maul at requirement (27 × 120 / 100, DS-4); the
    // strength is 5 × the weapon attribute's rank capped by level (DS-9): 50, and 40 under a cap
    // of 40.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 2013392)] // ceil(1.05 × 1917516 measured)
    fn test_extremal_weapon() {
        let maul = Loadout {
            weapon: weapon::MAUL,
            weapon_damage: 27,
            weapon_ticks: 2,
            personalised: true,
            ..BuildFixture::loadout(1, 20),
        };
        let snapshot = BuildFixture::flatten(@maul, array![].span());
        assert(snapshot.stats.weapon_damage == 32, 'weapon damage 32');
        assert(snapshot.stats.weapon_strength == 50, '5 x 10');
        let capped = Loadout { strength_cap: 40, ..maul };
        let snapshot = BuildFixture::flatten(@capped, array![].span());
        assert(snapshot.stats.weapon_strength == 40, 'capped by level');
    }

    // §6 test 2, "each other field ≤ its envelope": every source at its widest on every other
    // row.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 5898678)] // ceil(1.05 × 5617788 measured)
    fn test_other_fields_within_envelopes() {
        let mut all = array![];
        let mut i: u8 = 0;
        for source in BuildFixture::sources() {
            let s = *source;
            let modifier: u32 = 100 + i.into();
            if s == Source::Prefix || s == Source::Suffix || s == Source::Inscription {
                all
                    .append(
                        BuildFixture::held(
                            BuildFixture::passive(id::LIFE_STEAL_ON_HIT, 0, 5), s, i, modifier,
                        ),
                    );
                all
                    .append(
                        BuildFixture::cost(
                            BuildFixture::passive(id::ENERGY_REGEN, 0, -1), s, i, modifier,
                        ),
                    );
            } else if s == Source::SetBonus {
                all
                    .append(
                        BuildFixture::held(
                            BuildFixture::passive(id::HEALTH_REGEN, 0, 1), s, i, modifier,
                        ),
                    );
            } else {
                all
                    .append(
                        BuildFixture::held(
                            BuildFixture::passive(id::ARMOR_VS, damage::FIRE, 7), s, i, modifier,
                        ),
                    );
                all
                    .append(
                        BuildFixture::cost(
                            BuildFixture::passive(id::ARMOR_VS, damage::COLD, 7), s, i, modifier,
                        ),
                    );
            }
            i += 1;
        }
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(3, 20), all.span());
        assert(snapshot.kit.life_steal == 25, 'life steal 25');
        // 4 + 1 (light) − 5 = 0, the floor.
        assert(snapshot.stats.energy_regen == 0, 'energy regen 0');
        assert(snapshot.stats.health_regen == 12, 'health regen +2');
        let [_, _, _, fire, cold, _, _, _, _] = snapshot.stats.armor_vs;
        // 10 sources at 7: 70, saturated at 63 (FX-23).
        assert(fire == 63 && cold == 63, 'armor vs 10 x 7 saturated');
    }

    // The signed lanes against the oracle (D-166): every hit lane at its widest, negative beside
    // positive, so that a lane that borrows from its neighbour would show; the three armors at
    // their widest, negative beside positive; health, energy and regeneration negative.
    // Damage: the prefix −18 above half on weapon hits (lanes 3 and 4), a suffix +18 always on
    // attack skills (lane 1), the other −18 always on spells (lane 2), the inscriptions +18 and
    // −18 always on all hits (0–2), the set bonuses +18 above half on spells (lane 5).
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 3941993)] // ceil(1.05 × 3754279 measured)
    fn test_lanes_against_the_oracle() {
        let all = array![
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ABOVE_HALF, scope::WEAPON, -18),
                Source::Prefix,
                0,
                1,
            ),
            BuildFixture::cost(
                BuildFixture::scoped(id::PENETRATION, guard::ALWAYS, scope::WEAPON, 36),
                Source::Prefix,
                0,
                1,
            ),
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ATTACK_SKILL, 18),
                Source::Suffix,
                1,
                2,
            ),
            BuildFixture::cost(BuildFixture::passive(id::MAX_ENERGY, 0, -5), Source::Suffix, 1, 2),
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::SPELL, -18),
                Source::Suffix,
                2,
                3,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::HEALTH_REGEN, 0, -1), Source::Suffix, 2, 3,
            ),
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, 18),
                Source::Inscription,
                3,
                4,
            ),
            BuildFixture::cost(
                BuildFixture::scoped(id::PENETRATION, guard::ALWAYS, scope::SPELL, 36),
                Source::Inscription,
                3,
                4,
            ),
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, -18),
                Source::Inscription,
                4,
                5,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::ENERGY_REGEN, 0, -1), Source::Inscription, 4, 5,
            ),
            BuildFixture::held(
                PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, 18, 18),
                Source::Insignia,
                5,
                6,
            ),
            BuildFixture::cost(
                PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, -18, -18),
                Source::Insignia,
                5,
                6,
            ),
            BuildFixture::held(
                PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, -255),
                Source::Insignia,
                6,
                7,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::ENCHANT_DURATION, 0, 20), Source::Insignia, 6, 7,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::ARMOR_VS, damage::SLASHING, 7), Source::Rune, 10, 8,
            ),
            BuildFixture::cost(
                PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, -255), Source::Rune, 10, 8,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::ARMOR_VS, damage::HOLY, 7), Source::Rune, 11, 9,
            ),
            BuildFixture::cost(BuildFixture::passive(id::MAX_HEALTH, 0, -75), Source::Rune, 11, 9),
            BuildFixture::held(
                BuildFixture::scoped(id::DAMAGE_PERCENT, guard::ABOVE_HALF, scope::SPELL, 18),
                Source::SetBonus,
                15,
                0,
            ),
            BuildFixture::held(
                PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, 18, 18),
                Source::SetBonus,
                16,
                0,
            ),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        // Lanes: [weapon, attack skill, spell] always, then above half.
        assert(snapshot.bar.damage == [0, 18, -18, -18, -18, 18], 'damage lanes');
        assert(snapshot.bar.penetration == [36, 36, 36], 'penetration lanes');
        assert(snapshot.bar.armor == -510, 'unguarded armor');
        assert(snapshot.kit.armor_stance == 18 && snapshot.kit.armor_enchanted == 0, 'guarded');
        assert(snapshot.stats.max_health == 480 - 75, 'max health');
        let [slashing, _, _, _, _, _, _, _, holy] = snapshot.stats.armor_vs;
        assert(slashing == 27 && holy == 7, 'armor vs: 20 + 7, 7');
    }

    // §6 test 3: the floors (DS-2), level 1 with every cost at its bound: refused.
    #[test]
    #[should_panic(expected: 'build: max health below 1')]
    #[available_gas(l2_gas: 566993)] // ceil(1.05 × 539993 measured)
    fn test_floor_max_health_refused() {
        // Runes: +5 armor and −75 health; set bonuses −75: 100 − 375 − 150.
        let mut all = array![];
        let mut i: u8 = 10;
        while i < 15 {
            all
                .append(
                    BuildFixture::held(
                        BuildFixture::passive(id::ARMOR, 0, 5), Source::Rune, i, 400,
                    ),
                );
            all
                .append(
                    BuildFixture::cost(
                        BuildFixture::passive(id::MAX_HEALTH, 0, -75), Source::Rune, i, 400,
                    ),
                );
            i += 1;
        }
        all
            .append(
                BuildFixture::held(
                    BuildFixture::passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 15, 0,
                ),
            );
        all
            .append(
                BuildFixture::held(
                    BuildFixture::passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 16, 0,
                ),
            );
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 1), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: max energy below 0')]
    #[available_gas(l2_gas: 772499)] // ceil(1.05 × 735713 measured)
    fn test_floor_max_energy_refused() {
        // A Vanguard's 20, five held slots and two set bonuses at −5: −15.
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::MAX_ENERGY, 0, -5),
            array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
        );
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 1), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: energy regen below 0')]
    #[available_gas(l2_gas: 772499)] // ceil(1.05 × 735713 measured)
    fn test_floor_energy_regen_refused() {
        // A Vanguard's 2 pips, five held slots and two set bonuses at −1: −5.
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::ENERGY_REGEN, 0, -1),
            array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
        );
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 1), all.span());
    }

    // §6 test 4 (DS-5): enchantment 340 → 50 (17 sources at 20), knock-down 4 → 3, armor
    // against a type 149 → 63 (a Warden's +30 elemental and 17 sources at 7). Condition duration
    // 65,534 → 50: `test_same_condition_capped`, below.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 12143421)] // ceil(1.05 × 11565162 measured)
    fn test_saturation() {
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::ENCHANT_DURATION, 0, 20), BuildFixture::sources(),
        );
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(2, 20), all.span());
        assert(snapshot.kit.enchantment_duration == 50, 'enchantment 340 -> 50');
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::KNOCKDOWN_FLAT, 0, 1),
            array![Source::Suffix, Source::Inscription].span(),
        );
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(2, 20), all.span());
        assert(snapshot.kit.knockdown == 3, 'knock-down 4 -> 3');
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::ARMOR_VS, damage::FIRE, 7), BuildFixture::sources(),
        );
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(2, 20), all.span());
        let [_, _, _, fire, _, _, _, _, _] = snapshot.stats.armor_vs;
        assert(fire == 63, 'armor vs 149 -> 63');
        // A prefix's condition duration, benefit and cost of one condition, summed: 20 + 13,
        // the prefix's bound 33 (DS-5); one prefix, so no legal build reaches the saturation.
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::CONDITION_DURATION, condition::POISON, 20),
                Source::Prefix,
                0,
                1,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::CONDITION_DURATION, condition::POISON, 13),
                Source::Prefix,
                0,
                1,
            ),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(2, 20), all.span());
        assert(snapshot.kit.condition == condition::POISON, 'condition');
        assert(snapshot.kit.condition_duration == 33, 'condition 20 + 13');
    }

    // §6 test 5 (FX-43, D-157 D): two health runes of one modifier id count once; of two ids,
    // both.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 2669117)] // ceil(1.05 × 2542016 measured)
    fn test_rune_identity() {
        let rune = BuildFixture::passive(id::MAX_HEALTH, 0, 50);
        let same = array![
            BuildFixture::held(rune, Source::Rune, 10, 7),
            BuildFixture::held(rune, Source::Rune, 11, 7),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), same.span());
        assert(snapshot.stats.max_health == 480 + 50, 'one id: once');
        let two = array![
            BuildFixture::held(rune, Source::Rune, 10, 7),
            BuildFixture::held(rune, Source::Rune, 11, 8),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), two.span());
        assert(snapshot.stats.max_health == 480 + 100, 'two ids: both');
    }

    // AUD-182-2: three runes of one modifier id (+50 health, −75 health): the benefit counts
    // once, every cost counts (FX-43): 480 + 50 − 225.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 2009378)] // ceil(1.05 × 1913693 measured)
    fn test_repeated_rune_id() {
        let benefit = BuildFixture::passive(id::MAX_HEALTH, 0, 50);
        let price = BuildFixture::passive(id::MAX_HEALTH, 0, -75);
        let mut all = array![];
        let mut i: u8 = 10;
        while i < 13 {
            all.append(BuildFixture::held(benefit, Source::Rune, i, 9));
            all.append(BuildFixture::cost(price, Source::Rune, i, 9));
            i += 1;
        }
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        assert(snapshot.stats.max_health == 480 + 50 - 225, 'benefit once, costs all');
    }

    // AUD-182-3: a rune's contribution to an attribute is its passives' sum: +1 and +2 on one
    // rune give 3, so 12 points reach 15.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 1569722)] // ceil(1.05 × 1494973 measured)
    fn test_rune_attribute_contribution() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::ATTRIBUTE, PRIMARY, 1), Source::Rune, 10, 7,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::ATTRIBUTE, PRIMARY, 2), Source::Rune, 10, 7,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::ATTRIBUTE, PRIMARY, 2), Source::Rune, 11, 8,
            ),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(3, 20), all.span());
        assert(snapshot.stats.primary_rank == 15, '12 + (1 + 2)');
    }

    // The counts of design/20 §1.2 at their bounds, the 17 sources: accepted; one more of a
    // source: refused.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 4528186)] // ceil(1.05 × 4312558 measured)
    fn test_counts_at_bounds() {
        let all = BuildFixture::everywhere(
            BuildFixture::passive(id::ARMOR, 0, 1), BuildFixture::sources(),
        );
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        assert(snapshot.bar.armor == 17, '17 sources');
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 270116)] // ceil(1.05 × 257253 measured)
    fn test_sixth_rune_refused() {
        let mut all = array![];
        let mut i: u8 = 0;
        while i < 6 {
            all
                .append(
                    BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::Rune, i, 1),
                );
            i += 1;
        }
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 186211)] // ceil(1.05 × 177343 measured)
    fn test_second_prefix_refused() {
        let all = array![
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::Prefix, 0, 1),
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::Prefix, 5, 1),
        ];
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 203746)] // ceil(1.05 × 194043 measured)
    fn test_third_set_bonus_refused() {
        let all = array![
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::SetBonus, 15, 0),
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::SetBonus, 16, 0),
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::SetBonus, 17, 0),
        ];
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), all.span());
    }

    // Instances are numbered upward, so that none is counted twice: a passive of an earlier
    // instance after a later one is refused.
    #[test]
    #[should_panic(expected: 'build: instances out of order')]
    #[available_gas(l2_gas: 189238)] // ceil(1.05 × 180226 measured)
    fn test_instances_out_of_order_refused() {
        let all = array![
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::Rune, 11, 1),
            BuildFixture::held(BuildFixture::passive(id::ARMOR, 0, 5), Source::Rune, 10, 1),
        ];
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), all.span());
    }

    // DS-23: one insignia a piece.
    #[test]
    #[should_panic(expected: 'build: two insignias a piece')]
    #[available_gas(l2_gas: 191635)] // ceil(1.05 × 182509 measured)
    fn test_two_insignias_on_a_piece_refused() {
        let mut first = BuildFixture::held(
            BuildFixture::passive(id::MAX_HEALTH, 0, 5), Source::Insignia, 5, 200,
        );
        let mut second = BuildFixture::held(
            BuildFixture::passive(id::MAX_HEALTH, 0, 5), Source::Insignia, 6, 200,
        );
        first.piece = base_slot::HEAD;
        second.piece = base_slot::HEAD;
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), array![first, second].span());
    }

    // A quick-cast pair names an attribute of the build (D-157 A): its index; one the build does
    // not hold is refused.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 1438178)] // ceil(1.05 × 1369693 measured)
    fn test_quick_cast_pairs() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::QUICK_CAST_EVERY_N, OTHER, 4), Source::Inscription, 3, 1,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::QUICK_CAST_EVERY_N, PRIMARY, 9),
                Source::Inscription,
                4,
                2,
            ),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        let [first, second] = snapshot.bar.quick_cast;
        assert(first == QuickCast { attribute: 1, every: 4 }, 'other: index 1');
        assert(second == QuickCast { attribute: 0, every: 9 }, 'primary: index 0');
    }

    // CBT-05f: each bar slot counts for the pairs of its skill's attribute (slot `i`'s pair `p` at
    // bit `2 i + p`; an empty slot, attribute 0, for none); an attack skill of another attribute
    // than the weapon's (the sword's, OTHER) needs its weapon. Without pairs, no slot counts.
    #[test]
    #[available_gas(l2_gas: 2699284)] // ceil(1.05 × 2570746 measured)
    fn test_attribute_mappings() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::QUICK_CAST_EVERY_N, OTHER, 4), Source::Inscription, 3, 1,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::QUICK_CAST_EVERY_N, PRIMARY, 9),
                Source::Inscription,
                4,
                2,
            ),
        ];
        let build = Loadout {
            bar_attributes: [PRIMARY, OTHER, OTHER, 0, 0, 0, 0, PRIMARY],
            bar_attacks: 0x83,
            ..BuildFixture::loadout(1, 20),
        };
        let snapshot = BuildFixture::flatten(@build, all.span());
        // Slot 0 pair 1, slots 1 and 2 pair 0, slot 7 pair 1.
        assert(snapshot.stats.quick_cast_slots == 0x2 + 0x4 + 0x10 + 0x8000, 'quick-cast slots');
        // Attacks on 0 (PRIMARY), 1 (OTHER, the weapon's), 7 (PRIMARY).
        assert(snapshot.stats.weapon_required == 0x81, 'weapon required');
        let snapshot = BuildFixture::flatten(@build, array![].span());
        assert(snapshot.stats.quick_cast_slots == 0, 'no pair');
        assert(snapshot.stats.weapon_required == 0x81, 'kept without pairs');
    }

    #[test]
    #[should_panic(expected: 'build: quick-cast attribute')]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 195671)] // ceil(1.05 × 186353 measured)
    fn test_quick_cast_attribute_not_held_refused() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::QUICK_CAST_EVERY_N, 99, 4), Source::Inscription, 3, 1,
            ),
        ];
        SnapshotBuildTrait::build(@BuildFixture::loadout(1, 20), all.span());
    }

    // The passives that are not summed: the lowest N, the damage type, halving.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 1576757)] // ceil(1.05 × 1501673 measured)
    fn test_passives_not_summed() {
        let all = array![
            BuildFixture::held(
                BuildFixture::passive(id::DAMAGE_TYPE, damage::FIRE, 0), Source::Prefix, 0, 1,
            ),
            BuildFixture::cost(
                BuildFixture::passive(id::ADRENALINE_EVERY_N, 0, 9), Source::Prefix, 0, 1,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::ADRENALINE_EVERY_N, 0, 5), Source::Suffix, 1, 2,
            ),
            BuildFixture::held(
                BuildFixture::passive(id::HALVE_FIRST_HEAVY_HIT, 0, 0), Source::Rune, 10, 3,
            ),
        ];
        let snapshot = BuildFixture::flatten(@BuildFixture::loadout(1, 20), all.span());
        assert(snapshot.stats.damage_type == damage::FIRE, 'damage type');
        assert(snapshot.kit.double_adrenaline_every == 5, 'the lowest N');
        assert(snapshot.kit.halving, 'halving');
    }


    // ---- the flattening's cost (docs/CAIRO.md §2: a benchmark on the worst case)
    // ----------------

    // The baseline of the two below: the widest build's inputs, not flattened.
    #[test]
    #[available_gas(l2_gas: 294483)] // ceil(1.05 × 280460 measured)
    fn test_cost_build_baseline() {
        let (build, all) = BuildFixture::widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
    }

    // The flattening of the widest build (D-166): this test less the baseline.
    #[test]
    #[available_gas(l2_gas: 2003325)] // ceil(1.05 × 1907928 measured)
    fn test_cost_build_widest() {
        let (build, all) = BuildFixture::widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
        let snapshot = SnapshotBuildTrait::build(@build, all.span());
        assert(snapshot.stats.max_health == 480 + 5, 'five runes');
    }

    // CBT-02's flattening of the same build, for the comparison (its checks not included).
    #[test]
    #[available_gas(l2_gas: 11516001)] // ceil(1.05 × 10967620 measured)
    fn test_cost_oracle_widest() {
        let (build, all) = BuildFixture::widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
        let snapshot = BuildFixture::oracle(@build, all.span());
        assert(snapshot.stats.max_health == 480 + 5, 'five runes');
    }

    // The same build flattened and compared with the oracle.
    #[test]
    #[available_gas(l2_gas: 13293208)] // ceil(1.05 × 12660198 measured)
    fn test_widest_against_the_oracle() {
        let (build, all) = BuildFixture::widest();
        let snapshot = BuildFixture::flatten(@build, all.span());
        assert(snapshot.stats.ranks == 0xbbbbbbbb, 'eight ranks of 10 + 1');
        assert(snapshot.kit.knockdown == 2 && snapshot.kit.enchantment_duration == 5, 'kit');
    }

    // The fixed part of the flattening: a build that holds no passive, and CBT-02's on the same.
    #[test]
    #[available_gas(l2_gas: 395654)] // ceil(1.05 × 376813 measured)
    fn test_cost_build_empty() {
        let snapshot = SnapshotBuildTrait::build(@BuildFixture::loadout(3, 20), array![].span());
        assert(snapshot.stats.max_health == 480, 'no passive');
    }

    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 373506)] // ceil(1.05 × 355720 measured)
    fn test_cost_oracle_empty() {
        let snapshot = BuildFixture::oracle(@BuildFixture::loadout(3, 20), array![].span());
        assert(snapshot.stats.max_health == 480, 'no passive');
    }

    // The words are the flattening's, packed: of the passives held, and of no item at all.
    #[test]
    #[available_gas(l2_gas: 4034340)] // ceil(1.05 × 3842228 measured)
    fn test_words_are_the_flattening() {
        let (ids, records) = WornFixture::worn_records();
        let build = BuildFixture::loadout(1, 20);
        let (stats, bar, kit) = SnapshotBuildTrait::words(
            @build, WornFixture::worn_items(), ids, records,
        );
        let held_passives = WornTrait::held(WornFixture::worn_items(), ids, records);
        let snapshot = SnapshotBuildTrait::build(@build, held_passives.span());
        assert(
            SnapshotWords { stats, bar, kit, belt_counts: build.belt_counts } == snapshot.words(),
            'words',
        );
        assert(MemberKitTrait::unpack(kit).life_steal == 8, 'life steal 5 + 3');
        let (stats, bar, kit) = SnapshotBuildTrait::words(
            @build, array![].span(), array![].span(), array![].span(),
        );
        let empty = SnapshotBuildTrait::build(@build, array![].span());
        assert(stats == MemberStatsTrait::pack(empty.stats), 'empty stats');
        assert(bar == MemberBarTrait::pack(empty.bar), 'empty bar');
        assert(kit == MemberKitTrait::pack(empty.kit), 'empty kit');
    }
}
