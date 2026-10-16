//! Passive effects (design/19 §4): read, never scheduled; one id is one statistic. A `MODIFIER`
//! carries two, a benefit and a cost; an `ARMOR_SET` bonus is one. They are flattened into the
//! snapshot at entry, losslessly (§7.2).
//!
//! Layout of a passive, 53 bits: id 0–7 · param 8–15 · guard 16–18 · scope 19–20 · min
//! 21–36 ·
//! max 37–52 (`min` and `max` signed, two's complement). The cost of a modifier is fixed (`min =
//! max`); the benefit's rolled value is the item's `ItemMods` byte. Id 0 is no passive.

use crate::helpers::packing::{P16, P8};
use crate::helpers::signed::SignedTrait;
use super::combat::{condition, damage};
use super::effect::{guard, scope};

/// Passive ids 40–65 (§4), numbered after the effect kinds.
/// 61–65 have no MVP source (**P**).
pub mod id {
    pub const NONE: u8 = 0;
    pub const MAX_HEALTH: u8 = 40;
    /// Signed; guard 0, 3 or 4 (a guarded one −18…+18, F-20).
    pub const ARMOR: u8 = 41;
    /// `param` a damage type.
    pub const ARMOR_VS: u8 = 42;
    pub const MAX_ENERGY: u8 = 43;
    pub const ENERGY_REGEN: u8 = 44;
    pub const HEALTH_REGEN: u8 = 45;
    /// `param` a damage type; never summed (FX-43).
    pub const DAMAGE_TYPE: u8 = 46;
    /// Percent −18…+18; guard 0 or 1; a scope.
    pub const DAMAGE_PERCENT: u8 = 47;
    /// Percent 0…36; a scope.
    pub const PENETRATION: u8 = 48;
    pub const LIFE_STEAL_ON_HIT: u8 = 49;
    pub const ENERGY_ON_HIT: u8 = 50;
    /// `param` a condition; percent.
    pub const CONDITION_DURATION: u8 = 51;
    pub const ENCHANT_DURATION: u8 = 52;
    /// + ticks, at most 3.
    pub const KNOCKDOWN_FLAT: u8 = 53;
    /// N 1…255: the lowest counts (FX-43).
    pub const ADRENALINE_EVERY_N: u8 = 54;
    /// `param` an attribute; N 1…255.
    pub const QUICK_CAST_EVERY_N: u8 = 55;
    /// `param` an attribute; ± ranks.
    pub const ATTRIBUTE: u8 = 56;
    /// `param` a profession; − energy.
    pub const ENERGY_COST: u8 = 57;
    pub const HALVE_FIRST_HEAVY_HIT: u8 = 58;
    pub const BASE_DAMAGE_PERCENT: u8 = 59;
    pub const RATING_PERCENT: u8 = 60;
    pub const HEAL_BONUS: u8 = 61;
    pub const ACTIVATION_PERCENT: u8 = 62;
    pub const ENERGY_ON_DEATH: u8 = 63;
    pub const CASTE_ARMOR: u8 = 64;
    pub const ATTACK_SPEED: u8 = 65;
    pub const FIRST: u8 = 40;
    /// The last passive of the MVP: 61–65 have no rule.
    pub const LAST_MVP: u8 = 60;
    pub const LAST: u8 = 65;
}

/// A `DAMAGE_PERCENT` or guarded `ARMOR` passive is bounded to −18…+18, a `PENETRATION` to
/// 0…36: at most 7 held, so their sums fit an `i8` (−126…126) and a `u8` (≤ 252) (§7.2).
pub const MAX_DAMAGE_PERCENT: i16 = 18;
pub const MAX_GUARDED_ARMOR: i16 = 18;
pub const MAX_PENETRATION: i16 = 36;
/// An unguarded `ARMOR` passive is bounded to −255…+255 (§7.2).
pub const MAX_ARMOR: i16 = 255;
/// The three hit classes a scope-bearing sum is kept for (design/19 §5.4, §7.2): a plain weapon
/// hit, an attack skill's hit, a spell's hit; the index of `MemberBar`'s sums.
pub const HIT_WEAPON: u8 = 0;
pub const HIT_ATTACK_SKILL: u8 = 1;
pub const HIT_SPELL: u8 = 2;
/// `ADRENALINE_EVERY_N`'s N is 1…255 (§4).
pub const MAX_EVERY_N: i16 = 255;
/// Professions: design/03's six, ids 1–6 (`ENERGY_COST`'s `param`).
pub const LAST_PROFESSION: u8 = 6;

pub mod errors {
    pub const GUARD: felt252 = 'passive: guard';
    pub const SCOPE: felt252 = 'passive: scope';
    // The content pipeline's checks (`assert_legal`, `assert_source`).
    pub const ID: felt252 = 'passive: id';
    pub const NOT_MVP: felt252 = 'passive: id after the MVP';
    pub const EMPTY: felt252 = 'passive: none with a field';
    pub const RANGE: felt252 = 'passive: min above max';
    pub const VALUE: felt252 = 'passive: value out of bounds';
    pub const PARAM: felt252 = 'passive: param';
    pub const FIXED: felt252 = 'passive: cost not fixed';
    pub const SOURCE: felt252 = 'passive: not on this source';
    pub const CONTRIBUTION: felt252 = 'passive: source adds too much';
    pub const SOURCE_BOUND: felt252 = 'passive: per-source bound';
}

/// The per-source bounds of design/20 §1.3 (DS-1, D-160), `[lo, hi]` for what one source adds to
/// a statistic; `None` where the row gives none (the statistic is bounded otherwise, or is not
/// held by that source: `PassiveTrait::allows`). Initial content bounds; BAL-01 sets values under
/// them. A free function: a constant table by passive and source, which a trait would not make
/// clearer (docs/CAIRO.md §7).
/// - Row 1, max health: held slots 0…+30, an insignia ≤ 15 (the chest's; the piece's own, 15 /
/// 10
///   / 5, needs the insignia record to name its piece: DS-23, CNT-01), a rune and a set bonus
///   −75…+50.
/// - Rows 2–4: max energy −5…+5 (held, set bonus); energy regeneration and health
/// regeneration
///   −1…0 on a held slot, −1…+1 on a set bonus.
/// - Row 7: armor against a type 0…+7, any source. Row 8: an attribute +1…+3, runes only.
/// - Rows 13, 14: life steal 0…+5, energy on hit 0…+1, held slots only.
/// - Rows 15–17 (DS-5's content bounds): condition duration ≤ 33 (a prefix), enchantment
///   duration ≤ 20, knock-down ≤ 1; the flattening saturates the sums anyway (50, 50, 3).
pub fn source_bound(id: u8, source: Source) -> Option<(i32, i32)> {
    let held_slot = source == Source::Prefix
        || source == Source::Suffix
        || source == Source::Inscription;
    if id == id::MAX_HEALTH {
        if held_slot {
            Option::Some((0, 30))
        } else if source == Source::Insignia {
            Option::Some((0, 15))
        } else {
            Option::Some((-75, 50))
        }
    } else if id == id::MAX_ENERGY {
        Option::Some((-5, 5))
    } else if id == id::ENERGY_REGEN || id == id::HEALTH_REGEN {
        if held_slot {
            Option::Some((-1, 0))
        } else {
            Option::Some((-1, 1))
        }
    } else if id == id::ARMOR_VS {
        Option::Some((0, 7))
    } else if id == id::ATTRIBUTE {
        Option::Some((1, 3))
    } else if id == id::LIFE_STEAL_ON_HIT {
        Option::Some((0, 5))
    } else if id == id::ENERGY_ON_HIT {
        Option::Some((0, 1))
    } else if id == id::CONDITION_DURATION {
        Option::Some((0, 33))
    } else if id == id::ENCHANT_DURATION {
        Option::Some((0, 20))
    } else if id == id::KNOCKDOWN_FLAT {
        Option::Some((0, 1))
    } else {
        Option::None
    }
}

/// Where a passive is held (design/15, design/19 §4, §7.2): one of an item's five modifier slot
/// types (`models::modifier::slot`, same order), or an armor set's bonus.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Source {
    /// Weapons (not wands).
    Prefix,
    /// Weapons, shields, foci.
    Suffix,
    /// Everything held: the weapon and the off-hand.
    Inscription,
    /// One per armor piece.
    Insignia,
    /// One per armor piece.
    Rune,
    /// One of the two bonuses of the one set that can reach 3 pieces of 5.
    SetBonus,
}

/// One passive effect (§4).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Passive {
    /// `id::NONE`, or 40–65.
    pub id: u8,
    /// By id: a damage type, a condition, an attribute, a profession.
    pub param: u8,
    /// `guard::ALWAYS`, `ABOVE_HALF` (`DAMAGE_PERCENT`), `IN_STANCE` or `ENCHANTED` (`ARMOR`).
    pub guard: u8,
    /// `scope::WEAPON` … `ALL`, for `DAMAGE_PERCENT` and `PENETRATION`.
    pub scope: u8,
    /// The value range, signed; `min = max` for a cost.
    pub min: i16,
    pub max: i16,
}

const P19: u128 = 0x80000;
const P21: u128 = 0x200000;
const P37: u128 = 0x2000000000;
/// A passive is below 2^53.
pub const PASSIVE_BOUND: u128 = 0x20000000000000;
/// 2^53: the second passive of a limb.
pub const P53: u128 = PASSIVE_BOUND;

#[generate_trait]
pub impl PassiveImpl of PassiveTrait {
    fn new(id: u8, param: u8, guard: u8, scope: u8, min: i16, max: i16) -> Passive {
        Passive { id, param, guard, scope, min, max }
    }

    /// Its 53 bits (`PassiveAssert::assert_valid`).
    fn pack(self: @Passive) -> u128 {
        self.assert_valid();
        (*self.id).into()
            + (*self.param).into() * P8
            + (*self.guard).into() * P16
            + (*self.scope).into() * P19
            + SignedTrait::bits16(*self.min) * P21
            + SignedTrait::bits16(*self.max) * P37
    }

    /// The passive of 53 bits.
    fn unpack(bits: u128) -> Passive {
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (bits, id) = DivRem::div_rem(bits, s8);
        let (bits, param) = DivRem::div_rem(bits, s8);
        let (bits, guard) = DivRem::div_rem(bits, 8);
        let (bits, scope) = DivRem::div_rem(bits, 4);
        let (max, min) = DivRem::div_rem(bits, s16);
        Passive {
            id: id.try_into().unwrap(),
            param: param.try_into().unwrap(),
            guard: guard.try_into().unwrap(),
            scope: scope.try_into().unwrap(),
            min: SignedTrait::from16(min),
            max: SignedTrait::from16(max),
        }
    }

    /// Two passives in one limb of 106 bits: `first` at bit 0, `second` at bit 53 (a
    /// `MODIFIER`'s benefit and cost, an `ARMOR_SET`'s two bonuses).
    fn pack_pair(first: @Passive, second: @Passive) -> u128 {
        first.pack() + second.pack() * P53
    }

    fn unpack_pair(bits: u128) -> (Passive, Passive) {
        let (second, first) = DivRem::div_rem(bits, P53.try_into().unwrap());
        (Self::unpack(first), Self::unpack(second))
    }

    /// Whether it applies to hits of `class` (`HIT_WEAPON`, `HIT_ATTACK_SKILL`, `HIT_SPELL`, the
    /// three sums `MemberBar` stores per scope-bearing passive): design/19 §5.4 — a plain weapon
    /// hit takes `WEAPON`; an attack skill is a `WEAPON` hit "then also `ATTACK_SKILL` for
    /// scopes"; a spell takes `SPELL`; `ALL` applies to the three.
    fn applies_to(self: @Passive, class: u8) -> bool {
        let s = *self.scope;
        s == scope::ALL
            || (class == HIT_WEAPON && s == scope::WEAPON)
            || (class == HIT_ATTACK_SKILL && (s == scope::WEAPON || s == scope::ATTACK_SKILL))
            || (class == HIT_SPELL && s == scope::SPELL)
    }

    /// Whether `self` and `other`, held by one source, name two things a field that holds one
    /// cannot keep: two `QUICK_CAST_EVERY_N` (a source is one of the 2 pairs, §7.2), two
    /// `CONDITION_DURATION` of different conditions (the kit holds one condition and its
    /// percent: "one prefix"), two `DAMAGE_TYPE` of different types ("never summed": one type).
    fn conflicts(self: @Passive, other: @Passive) -> bool {
        let id = *self.id;
        if id != *other.id {
            return false;
        }
        id == id::QUICK_CAST_EVERY_N
            || ((id == id::CONDITION_DURATION || id == id::DAMAGE_TYPE)
                && *self.param != *other.param)
    }

    /// Whether the passives one source holds stay within design/20 §1.3's per-source bounds
    /// (`source_bound`): for each bounded passive present, the range its source adds to its
    /// statistic (same id, same param) lies within the row's `[lo, hi]`.
    ///
    /// Each passive alone lies within `[lo, hi]` too (AUD-182-2, -3): the flattening counts a
    /// health rune's benefit once per modifier id and takes the highest attribute rune, so a
    /// benefit and a cost that cancel within the bound must not be able to escape it separately.
    /// With both, any selection of one benefit and every cost of `n` sources lies within
    /// `n × [lo, hi]`, the envelope design/20 §1.3 sums (`test_build::test_capacity_proof`).
    fn fits_source(passives: Span<Passive>, source: Source) -> bool {
        for passive in passives {
            let id = *passive.id;
            if let Option::Some((lo, hi)) = source_bound(id, source) {
                let min: i32 = (*passive.min).into();
                let max: i32 = (*passive.max).into();
                if min < lo || max > hi {
                    return false;
                }
                let mut low: i32 = 0;
                let mut high: i32 = 0;
                for other in passives {
                    if *other.id == id && *other.param == *passive.param {
                        low += (*other.min).into();
                        high += (*other.max).into();
                    }
                }
                if low < lo || high > hi {
                    return false;
                }
            }
        }
        true
    }

    /// The range `(low, high)` that the passives of one source add to the sum of `id` and
    /// `guard` for hits of `class` (every class for a passive without a scope).
    fn contribution(passives: Span<Passive>, id: u8, guard: u8, class: u8) -> (i32, i32) {
        let mut low: i32 = 0;
        let mut high: i32 = 0;
        for passive in passives {
            if *passive.id == id && *passive.guard == guard && passive.applies_to(class) {
                low += (*passive.min).into();
                high += (*passive.max).into();
            }
        }
        (low, high)
    }

    /// Whether `source` may hold it: only the restrictions design/19 §7.2 states.
    /// - `DAMAGE_PERCENT`, `PENETRATION`: "only the held items' slot types and set bonuses"
    ///   (prefix, suffix, inscription; the 7 × 18 and 7 × 36 bounds);
    /// - guarded `ARMOR`: "only in an insignia slot … or a set bonus";
    /// - `QUICK_CAST_EVERY_N`: the inscription (design/20 §1.8, D-157 B, D-160): "everything
    ///   held", the weapon and the off-hand, so at most the field's 2 pairs;
    /// - `CONDITION_DURATION`: "one prefix, on the weapon only";
    /// - `DAMAGE_TYPE`: the prefix (design/20 §1.8, D-157 C, D-160): the only slot type that
    /// exists
    ///   only on weapons, so no item-context check is needed;
    /// - `RATING_PERCENT`: personalisation only, never a record: §7.2's armor bound counts it
    ///   apart from the 37 `ARMOR` passives (F-21);
    /// - design/20 §1.3 (D-160): `ENERGY_COST` and `BASE_DAMAGE_PERCENT` on no record (DS-4:
    ///   *Fieldcraft* and personalisation only); `ATTRIBUTE` on runes only (DS-4);
    ///   `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT` on held slots only (rows 13, 14); `MAX_ENERGY`,
    ///   `ENERGY_REGEN`, `HEALTH_REGEN` on held slots and set bonuses (rows 2–4: insignias and
    ///   runes add 0);
    /// - every other passive: any source.
    fn allows(self: @Passive, source: Source) -> bool {
        let id = *self.id;
        let held_slot = source == Source::Prefix
            || source == Source::Suffix
            || source == Source::Inscription;
        if id == id::ENERGY_COST || id == id::BASE_DAMAGE_PERCENT {
            false
        } else if id == id::ATTRIBUTE {
            source == Source::Rune
        } else if id == id::LIFE_STEAL_ON_HIT || id == id::ENERGY_ON_HIT {
            held_slot
        } else if id == id::MAX_ENERGY || id == id::ENERGY_REGEN || id == id::HEALTH_REGEN {
            held_slot || source == Source::SetBonus
        } else if id == id::DAMAGE_PERCENT || id == id::PENETRATION {
            held_slot || source == Source::SetBonus
        } else if id == id::ARMOR && *self.guard != guard::ALWAYS {
            source == Source::Insignia || source == Source::SetBonus
        } else if id == id::QUICK_CAST_EVERY_N {
            source == Source::Inscription
        } else if id == id::DAMAGE_TYPE || id == id::CONDITION_DURATION {
            source == Source::Prefix
        } else if id == id::RATING_PERCENT {
            false
        } else {
            true
        }
    }
}

#[generate_trait]
pub impl PassiveAssert of PassiveAssertTrait {
    /// Every field fits its layout: guard 3 bits, scope 2.
    #[inline(always)]
    fn assert_valid(self: @Passive) {
        assert(*self.guard < 8, errors::GUARD);
        assert(*self.scope < 4, errors::SCOPE);
    }

    /// The content pipeline's checks of one passive (§4, §7.2), only what the document states:
    /// id 0 has every field 0; otherwise the id is one of the MVP's; its `param` is in the
    /// enumeration its id names (a damage type 1–9, a condition 1–9, a profession 1–6; an
    /// attribute is any `u8`, its id space not being settled: escalated), else 0; a guard only on
    /// `ARMOR` (3, 4) and `DAMAGE_PERCENT` (1); a scope 0–3 only on `DAMAGE_PERCENT` and
    /// `PENETRATION`; `min ≤ max` within the range §4 and §7.2 state: `DAMAGE_PERCENT` and
    /// guarded `ARMOR` ±18, unguarded `ARMOR` ±255, `PENETRATION` 0…36, `ADRENALINE_EVERY_N`
    /// 1…255, `QUICK_CAST_EVERY_N` 0…255 (8 bits), non-positive for `ENERGY_COST` (§4: "−
    /// energy";
    /// §5.3: "energy after reductions"), non-negative for what §4 or ENG-01 §3.1
    /// gives as a plus (`ARMOR_VS` "+ armor", `KNOCKDOWN_FLAT` "+ ticks", the duration percents'
    /// "bonuses"), 0 for a passive without a value (`DAMAGE_TYPE`, `HALVE_FIRST_HEAVY_HIT`). An
    /// aggregate the snapshot saturates (`ARMOR_VS` at 63, FX-23) bounds no single passive.
    fn assert_legal(self: @Passive) {
        let id = *self.id;
        if id == id::NONE {
            assert(*self == Default::default(), errors::EMPTY);
            return;
        }
        assert(id >= id::FIRST && id <= id::LAST, errors::ID);
        assert(id <= id::LAST_MVP, errors::NOT_MVP);
        let p = *self.param;
        let param_ok = if id == id::ARMOR_VS || id == id::DAMAGE_TYPE {
            p >= damage::SLASHING && p <= damage::LAST
        } else if id == id::CONDITION_DURATION {
            p >= condition::BLEEDING && p <= condition::LAST
        } else if id == id::QUICK_CAST_EVERY_N || id == id::ATTRIBUTE {
            true
        } else if id == id::ENERGY_COST {
            p >= 1 && p <= LAST_PROFESSION
        } else {
            p == 0
        };
        assert(param_ok, errors::PARAM);
        let g = *self.guard;
        let guard_ok = if id == id::ARMOR {
            g == guard::ALWAYS || g == guard::IN_STANCE || g == guard::ENCHANTED
        } else if id == id::DAMAGE_PERCENT {
            g == guard::ALWAYS || g == guard::ABOVE_HALF
        } else {
            g == guard::ALWAYS
        };
        assert(guard_ok, errors::GUARD);
        if id == id::DAMAGE_PERCENT || id == id::PENETRATION {
            assert(*self.scope <= scope::ALL, errors::SCOPE);
        } else {
            assert(*self.scope == scope::WEAPON, errors::SCOPE);
        }
        assert(*self.min <= *self.max, errors::RANGE);
        let (low, high) = if id == id::DAMAGE_PERCENT {
            (-MAX_DAMAGE_PERCENT, MAX_DAMAGE_PERCENT)
        } else if id == id::ARMOR && g != guard::ALWAYS {
            (-MAX_GUARDED_ARMOR, MAX_GUARDED_ARMOR)
        } else if id == id::ARMOR {
            (-MAX_ARMOR, MAX_ARMOR)
        } else if id == id::PENETRATION {
            (0, MAX_PENETRATION)
        } else if id == id::ADRENALINE_EVERY_N {
            (1, MAX_EVERY_N)
        } else if id == id::QUICK_CAST_EVERY_N {
            (0, MAX_EVERY_N)
        } else if id == id::ARMOR_VS
            || id == id::KNOCKDOWN_FLAT
            || id == id::CONDITION_DURATION
            || id == id::ENCHANT_DURATION {
            (0, 32767)
        } else if id == id::ENERGY_COST {
            (-32768, 0)
        } else if id == id::DAMAGE_TYPE || id == id::HALVE_FIRST_HEAVY_HIT {
            (0, 0)
        } else {
            (-32768, 32767)
        };
        assert(*self.min >= low && *self.max <= high, errors::VALUE);
    }

    /// Legal, and held by a source that may hold it (`PassiveTrait::allows`); id 0 by any.
    fn assert_source(self: @Passive, source: Source) {
        self.assert_legal();
        assert(*self.id == id::NONE || self.allows(source), errors::SOURCE);
    }

    /// The passives one source holds (a modifier's benefit and cost) add to each sum §7.2 bounds
    /// by counting sources no more than one passive may: for `DAMAGE_PERCENT` per guard and hit
    /// class, −18…+18; for `PENETRATION` per hit class, 0…36; for guarded `ARMOR` per guard,
    /// −18…+18. So each of the 7 sources adds at most what §7.2's 7 × 18 and 7 × 36 count,
    /// whatever the scopes: an attack skill's sum takes both `WEAPON` and `ATTACK_SKILL` (§5.4).
    /// A source's two passives in different sums, or whose total stays within the bound, pass.
    fn assert_contributions(passives: Span<Passive>) {
        let within = |id: u8, guard: u8, class: u8, bound_low: i32, bound_high: i32| {
            let (low, high) = PassiveTrait::contribution(passives, id, guard, class);
            assert(low >= bound_low && high <= bound_high, errors::CONTRIBUTION);
        };
        let damage: i32 = MAX_DAMAGE_PERCENT.into();
        let pierce: i32 = MAX_PENETRATION.into();
        let guarded: i32 = MAX_GUARDED_ARMOR.into();
        for class in array![HIT_WEAPON, HIT_ATTACK_SKILL, HIT_SPELL] {
            within(id::DAMAGE_PERCENT, guard::ALWAYS, class, -damage, damage);
            within(id::DAMAGE_PERCENT, guard::ABOVE_HALF, class, -damage, damage);
            within(id::PENETRATION, guard::ALWAYS, class, 0, pierce);
        }
        within(id::ARMOR, guard::IN_STANCE, HIT_WEAPON, -guarded, guarded);
        within(id::ARMOR, guard::ENCHANTED, HIT_WEAPON, -guarded, guarded);
    }

    /// The per-source bounds of design/20 §1.3 (DS-1, D-160; envelope B): the passives one source
    /// holds (a modifier's benefit and cost, a set bonus alone) add to each bounded statistic
    /// (per param for `ARMOR_VS`, `ATTRIBUTE` and `CONDITION_DURATION`) no more than its row
    /// allows. `PassiveTrait::fits_source` is the predicate.
    fn assert_source_bounds(passives: Span<Passive>, source: Source) {
        assert(PassiveTrait::fits_source(passives, source), errors::SOURCE_BOUND);
    }

    /// A cost is fixed: `min = max` (design/15, Q-4).
    #[inline(always)]
    fn assert_fixed(self: @Passive) {
        assert(*self.min == *self.max, errors::FIXED);
    }
}

/// The passive's unit tests (CBT-01 and its fix loops, design/19 §4 and §7.2; design/20 §6 test
/// 1, D-160): 53 bits round-trip, and the pipeline's checks accept exactly the params, scopes,
/// values and sources design/19 and design/20 allow.
#[cfg(test)]
mod tests {
    use crate::types::combat::{condition, damage};
    use crate::types::effect::{guard, scope};
    use super::{Passive, PassiveAssert, PassiveTrait, Source, id};

    /// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
    const PRIMARY: u8 = 13;

    /// The passives these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        fn passive_max() -> Passive {
            PassiveTrait::new(0xFF, 0xFF, 7, 3, -32768, 32767)
        }

        fn passive(id: u8, param: u8, value: i16) -> Passive {
            PassiveTrait::new(id, param, 0, 0, value, value)
        }

        fn fits(p: Passive, source: Source) -> bool {
            p.allows(source) && PassiveTrait::fits_source(array![p].span(), source)
        }
    }

    // §4: 53 bits; signed range; two in a limb of 106.
    #[test]
    #[available_gas(l2_gas: 293045)] // ceil(1.05 × 279090 measured)
    fn test_passive_round_trip() {
        let top = Fixture::passive_max();
        let bits = top.pack();
        assert(bits < 0x20000000000000, '53 bits');
        assert(PassiveTrait::unpack(bits) == top, 'top round trip');
        let at = |passive: Passive| -> u128 {
            passive.pack()
        };
        let p: Passive = Default::default();
        assert(at(Passive { id: 1, ..p }) == 1, 'id at 0');
        assert(at(Passive { param: 1, ..p }) == 0x100, 'param at 8');
        assert(at(Passive { guard: 1, ..p }) == 0x10000, 'guard at 16');
        assert(at(Passive { scope: 1, ..p }) == 0x80000, 'scope at 19');
        assert(at(Passive { min: 1, ..p }) == 0x200000, 'min at 21');
        assert(at(Passive { max: 1, ..p }) == 0x2000000000, 'max at 37');
        assert(at(Passive { min: -1, ..p }) == 0xFFFF * 0x200000, 'signed min');
        let other = PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, -18, 18);
        let pair = PassiveTrait::pack_pair(@top, @other);
        assert(pair < 0x400000000000000000000000000, '106 bits');
        assert(PassiveTrait::unpack_pair(pair) == (top, other), 'pair round trip');
    }

    #[test]
    #[should_panic(expected: 'passive: guard')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_guard_refused() {
        Passive { guard: 8, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'passive: scope')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_scope_refused() {
        Passive { scope: 4, ..Default::default() }.pack();
    }

    // §4, §7.2: the pipeline's bounds on the passives the snapshot sums.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_passive_legal() {
        let damage = PassiveTrait::new(
            id::DAMAGE_PERCENT, 0, guard::ABOVE_HALF, scope::ALL, 10, 18,
        );
        damage.assert_legal();
        PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, -18, 10).assert_legal();
        PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, 255).assert_legal();
        PassiveTrait::new(id::PENETRATION, 0, 0, scope::WEAPON, 2, 4).assert_legal();
        PassiveTrait::new(id::KNOCKDOWN_FLAT, 0, 0, 0, 1, 1).assert_legal();
        PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, -75, -75).assert_legal();
        let none: Passive = Default::default();
        none.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_damage_percent_bound_refused() {
        PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, 0, 10, 19).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_guarded_armor_bound_refused() {
        PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, -19, 10).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: guard')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_guard_not_its_refused() {
        PassiveTrait::new(id::DAMAGE_PERCENT, 0, guard::BELOW_HALF, 0, 1, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: scope')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_scope_not_its_refused() {
        PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, scope::SPELL, 1, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: id after the MVP')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_passive_post_mvp_refused() {
        PassiveTrait::new(id::CASTE_ARMOR, 0, 0, 0, 1, 1).assert_legal();
    }

    // CBT-1: each passive's `param` lies in the enumeration its id names (fix loop 2: an attribute
    // is any `u8`, its id space not being settled; see `test_capacity`).
    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_armor_vs_type_255_refused() {
        Fixture::passive(id::ARMOR_VS, 255, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_armor_vs_type_0_refused() {
        Fixture::passive(id::ARMOR_VS, 0, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_type_10_refused() {
        Fixture::passive(id::DAMAGE_TYPE, 10, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_condition_duration_condition_10_refused() {
        Fixture::passive(id::CONDITION_DURATION, 10, 33).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_energy_cost_profession_7_refused() {
        Fixture::passive(id::ENERGY_COST, 7, -2).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_param_on_max_health_refused() {
        Fixture::passive(id::MAX_HEALTH, 1, 30).assert_legal();
    }

    // CBT-1: a scope above 3 is refused by the pipeline's check, not only by the packer.
    #[test]
    #[should_panic(expected: 'passive: scope')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_percent_scope_4_refused() {
        PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, 4, 1, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: scope')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_penetration_scope_4_refused() {
        PassiveTrait::new(id::PENETRATION, 0, 0, 4, 1, 1).assert_legal();
    }

    // CBT-1: values within what §4 and §7.2 state (fix loop 2: a saturated aggregate bounds no
    // single passive; see `test_capacity`).
    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_armor_vs_negative_refused() {
        Fixture::passive(id::ARMOR_VS, 1, -1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_type_with_a_value_refused() {
        Fixture::passive(id::DAMAGE_TYPE, 4, 1).assert_legal();
    }

    // CBT-1: the ends of every domain are accepted.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_passive_domains_accepted() {
        Fixture::passive(id::ARMOR_VS, 1, 0).assert_legal();
        Fixture::passive(id::ARMOR_VS, 9, 63).assert_legal();
        Fixture::passive(id::DAMAGE_TYPE, 1, 0).assert_legal();
        Fixture::passive(id::DAMAGE_TYPE, 9, 0).assert_legal();
        Fixture::passive(id::CONDITION_DURATION, 1, 0).assert_legal();
        Fixture::passive(id::CONDITION_DURATION, 9, 63).assert_legal();
        PassiveTrait::new(id::QUICK_CAST_EVERY_N, 0, 0, 0, 1, 1).assert_legal();
        PassiveTrait::new(id::QUICK_CAST_EVERY_N, 15, 0, 0, 255, 255).assert_legal();
        Fixture::passive(id::ATTRIBUTE, 15, -3).assert_legal();
        Fixture::passive(id::ENERGY_COST, 1, -2).assert_legal();
        Fixture::passive(id::ENERGY_COST, 6, -2).assert_legal();
        Fixture::passive(id::LIFE_STEAL_ON_HIT, 0, 255).assert_legal();
        Fixture::passive(id::RATING_PERCENT, 0, 10).assert_legal();
        Fixture::passive(id::HALVE_FIRST_HEAVY_HIT, 0, 0).assert_legal();
        PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, scope::ALL, -18, 18).assert_legal();
        PassiveTrait::new(id::PENETRATION, 0, 0, scope::ALL, 0, 36).assert_legal();
    }

    // AUD-182-4: quick cast on a prefix or a suffix, the damage type on a suffix or an inscription,
    // are refused, even in a catalogue that uses only that slot type.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_undecided_slot_types_refused() {
        let quick = Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 5);
        let fire = Fixture::passive(id::DAMAGE_TYPE, 4, 0);
        assert(!quick.allows(Source::Prefix) && !quick.allows(Source::Suffix), 'quick cast');
        assert(quick.allows(Source::Inscription), 'quick cast on inscription');
        assert(!fire.allows(Source::Suffix) && !fire.allows(Source::Inscription), 'damage type');
        assert(fire.allows(Source::Prefix), 'damage type on prefix');
    }

    // CBT-7: an attribute's id space is not settled (escalated): any `u8` is accepted.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_attribute_ids_accepted() {
        Fixture::passive(id::ATTRIBUTE, 255, 1).assert_legal();
        Fixture::passive(id::ATTRIBUTE, 16, -2).assert_legal();
        Fixture::passive(id::QUICK_CAST_EVERY_N, 16, 5).assert_legal();
        Fixture::passive(id::QUICK_CAST_EVERY_N, 255, 0).assert_legal();
    }

    // CBT-1: no single passive is bounded by an aggregate the snapshot saturates or caps; a plus
    // stays a plus (§4: "+ armor", "+ ticks"; ENG-01 §3.1's percent bonuses).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_saturated_values_accepted() {
        Fixture::passive(id::ARMOR_VS, 1, 64).assert_legal();
        Fixture::passive(id::ARMOR_VS, 9, 32767).assert_legal();
        Fixture::passive(id::KNOCKDOWN_FLAT, 0, 4).assert_legal();
        Fixture::passive(id::ENCHANT_DURATION, 0, 64).assert_legal();
        Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 64).assert_legal();
        Fixture::passive(id::ARMOR_VS, 1, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_negative_knockdown_refused() {
        Fixture::passive(id::KNOCKDOWN_FLAT, 0, -1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_negative_enchant_duration_refused() {
        Fixture::passive(id::ENCHANT_DURATION, 0, -1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_adrenaline_every_0_refused() {
        Fixture::passive(id::ADRENALINE_EVERY_N, 0, 0).assert_legal();
    }

    // CBT-1 (fix loop 3): `ENERGY_COST` is "− energy" (§4), a reduction (§5.3): 0 or below.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_energy_cost_non_positive_accepted() {
        Fixture::passive(id::ENERGY_COST, 2, -1).assert_legal();
        Fixture::passive(id::ENERGY_COST, 2, 0).assert_legal();
        PassiveTrait::new(id::ENERGY_COST, 6, 0, 0, -32768, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_energy_cost_positive_refused() {
        Fixture::passive(id::ENERGY_COST, 2, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_energy_cost_range_crossing_zero_refused() {
        PassiveTrait::new(id::ENERGY_COST, 2, 0, 0, -1, 1).assert_legal();
    }

    // §6 test 1: for each row of §1.3 under B, a source at its bound passes, a unit beyond is
    // refused, a source that may not hold the passive is refused, and a modifier's benefit and cost
    // are summed.
    #[test]
    #[available_gas(l2_gas: 1716257)] // ceil(1.05 × 1634530 measured)
    fn test_per_source_bounds() {
        // (id, param, source, lo, hi)
        let rows = array![
            (id::MAX_HEALTH, 0, Source::Prefix, 0_i16, 30_i16),
            (id::MAX_HEALTH, 0, Source::Insignia, 0, 15),
            (id::MAX_HEALTH, 0, Source::Rune, -75, 50),
            (id::MAX_HEALTH, 0, Source::SetBonus, -75, 50),
            (id::MAX_ENERGY, 0, Source::Suffix, -5, 5),
            (id::MAX_ENERGY, 0, Source::SetBonus, -5, 5),
            (id::ENERGY_REGEN, 0, Source::Inscription, -1, 0),
            (id::ENERGY_REGEN, 0, Source::SetBonus, -1, 1),
            (id::HEALTH_REGEN, 0, Source::Prefix, -1, 0),
            (id::HEALTH_REGEN, 0, Source::SetBonus, -1, 1),
            (id::ARMOR_VS, damage::FIRE, Source::Rune, 0, 7),
            (id::ATTRIBUTE, PRIMARY, Source::Rune, 1, 3),
            (id::LIFE_STEAL_ON_HIT, 0, Source::Suffix, 0, 5),
            (id::ENERGY_ON_HIT, 0, Source::Prefix, 0, 1),
            (id::CONDITION_DURATION, condition::POISON, Source::Prefix, 0, 33),
            (id::ENCHANT_DURATION, 0, Source::Insignia, 0, 20),
            (id::KNOCKDOWN_FLAT, 0, Source::SetBonus, 0, 1),
        ];
        for (i, param, source, lo, hi) in rows {
            assert(Fixture::fits(Fixture::passive(i, param, lo), source), 'at lo');
            assert(Fixture::fits(Fixture::passive(i, param, hi), source), 'at hi');
            assert(!Fixture::fits(Fixture::passive(i, param, hi + 1), source), 'above hi');
            assert(!Fixture::fits(Fixture::passive(i, param, lo - 1), source), 'below lo');
        }
        // Sources that may not hold them (DS-4; rows 2–4, 8, 13, 14).
        let refused = array![
            (id::ENERGY_COST, Source::Prefix), (id::ENERGY_COST, Source::SetBonus),
            (id::BASE_DAMAGE_PERCENT, Source::Prefix), (id::BASE_DAMAGE_PERCENT, Source::Rune),
            (id::ATTRIBUTE, Source::Insignia), (id::ATTRIBUTE, Source::Prefix),
            (id::LIFE_STEAL_ON_HIT, Source::SetBonus), (id::ENERGY_ON_HIT, Source::Rune),
            (id::MAX_ENERGY, Source::Insignia), (id::MAX_ENERGY, Source::Rune),
            (id::ENERGY_REGEN, Source::Rune), (id::HEALTH_REGEN, Source::Insignia),
        ];
        for (i, source) in refused {
            assert(!Fixture::passive(i, 0, 0).allows(source), 'source refused');
        }
        // A modifier's benefit and cost on one statistic are summed: +50 and −75 on a rune,
        // −25.
        let pair = array![
            Fixture::passive(id::MAX_HEALTH, 0, 50), Fixture::passive(id::MAX_HEALTH, 0, -75),
        ];
        assert(PassiveTrait::fits_source(pair.span(), Source::Rune), 'summed within');
        let pair = array![
            Fixture::passive(id::MAX_HEALTH, 0, 30), Fixture::passive(id::MAX_HEALTH, 0, 30),
        ];
        assert(!PassiveTrait::fits_source(pair.span(), Source::Prefix), 'summed above');
        // Two types of armor are two statistics: 7 + 7.
        let pair = array![
            Fixture::passive(id::ARMOR_VS, 1, 7), Fixture::passive(id::ARMOR_VS, 2, 7),
        ];
        assert(PassiveTrait::fits_source(pair.span(), Source::Rune), 'per type');
    }
}
