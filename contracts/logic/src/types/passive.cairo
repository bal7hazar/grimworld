//! Passive effects (design/19 §4): read, never scheduled; one id is one statistic. A `MODIFIER`
//! carries two, a benefit and a cost; an `ARMOR_SET` bonus is one. They are flattened into the
//! snapshot at entry, losslessly (§7.2).
//!
//! Layout of a passive, 53 bits: id 0–7 · param 8–15 · guard 16–18 · scope 19–20 · min
//! 21–36 ·
//! max 37–52 (`min` and `max` signed, two's complement). The cost of a modifier is fixed (`min =
//! max`); the benefit's rolled value is the item's `ItemMods` byte. Id 0 is no passive.

use crate::helpers::signed::SignedTrait;
use crate::packing::{P16, P8};
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
/// `KNOCKDOWN_FLAT` is at most 3 ticks (2 bits in `MemberKit`), a set's two bonuses together.
pub const MAX_KNOCKDOWN_FLAT: i16 = 3;
/// `CONDITION_DURATION` and `ENCHANT_DURATION` percents fit 6 bits in `MemberKit`; an `ARMOR_VS`
/// fits 6 bits in `MemberStats` (FX-23).
pub const MAX_SIX_BITS: i16 = 63;
/// `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT` fit a `u8` of `MemberKit`.
pub const MAX_ON_HIT: i16 = 255;
/// Personalisation's rating bonus, +10 % (design/15 D-48): F-21's armor bound assumes it.
pub const MAX_RATING_PERCENT: i16 = 10;
/// A quick-cast or `ATTRIBUTE` passive's attribute fits 4 bits (`MemberBar`'s quick-cast pair).
pub const ATTRIBUTE_BOUND: u8 = 16;
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

    /// Whether the snapshot's capacity counts its sources (§7.2): `DAMAGE_PERCENT`,
    /// `PENETRATION` and guarded `ARMOR` (7 sources at most), `QUICK_CAST_EVERY_N` (2 at most),
    /// `CONDITION_DURATION` (one prefix), `KNOCKDOWN_FLAT` (3 ticks in 2 bits), `DAMAGE_TYPE`
    /// (never summed). Each source holds such a passive at most once.
    fn is_counted(self: @Passive) -> bool {
        let id = *self.id;
        id == id::DAMAGE_PERCENT
            || id == id::PENETRATION
            || (id == id::ARMOR && *self.guard != guard::ALWAYS)
            || id == id::QUICK_CAST_EVERY_N
            || id == id::CONDITION_DURATION
            || id == id::KNOCKDOWN_FLAT
            || id == id::DAMAGE_TYPE
    }

    /// Whether `source` may hold it (§7.2, design/15), so that no held set of passives breaks
    /// the snapshot's sums:
    /// - `DAMAGE_PERCENT`, `PENETRATION`: "only the held items' slot types and set bonuses"
    ///   (prefix, suffix, inscription; 7 sources at most);
    /// - guarded `ARMOR`: "only in an insignia slot … or a set bonus";
    /// - `QUICK_CAST_EVERY_N`: "held only on the weapon and the off-hand (… one slot type)": the
    ///   inscription, the one slot type both carry exactly once (the document names none:
    ///   escalated);
    /// - `CONDITION_DURATION`: "one prefix, on the weapon only";
    /// - `DAMAGE_TYPE`: "a `DAMAGE_TYPE` modifier on the weapon": a weapon's slot type, never an
    ///   armor slot or a set bonus (which of the three: escalated);
    /// - `KNOCKDOWN_FLAT`: a set bonus only (*Hob-breaker*; the 2-bit field holds one set's);
    /// - `BASE_DAMAGE_PERCENT`, `RATING_PERCENT`: personalisation only (the item's flag, D-48),
    ///   never a modifier or a set bonus (F-21's bound assumes +10 %);
    /// - every other passive: any source.
    fn allows(self: @Passive, source: Source) -> bool {
        let id = *self.id;
        let held_slot = source == Source::Prefix
            || source == Source::Suffix
            || source == Source::Inscription;
        if id == id::DAMAGE_PERCENT || id == id::PENETRATION {
            held_slot || source == Source::SetBonus
        } else if id == id::ARMOR && *self.guard != guard::ALWAYS {
            source == Source::Insignia || source == Source::SetBonus
        } else if id == id::QUICK_CAST_EVERY_N {
            source == Source::Inscription
        } else if id == id::CONDITION_DURATION {
            source == Source::Prefix
        } else if id == id::DAMAGE_TYPE {
            held_slot
        } else if id == id::KNOCKDOWN_FLAT {
            source == Source::SetBonus
        } else if id == id::BASE_DAMAGE_PERCENT || id == id::RATING_PERCENT {
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

    /// The content pipeline's checks of one passive (§4, §7.2): id 0 has every field 0;
    /// otherwise the id is one of the MVP's; its `param` is in the enumeration its id names (a
    /// damage type 1–9, a condition 1–9, an attribute that fits 4 bits, a profession 1–6),
    /// else 0; a guard only on `ARMOR` (3, 4) and `DAMAGE_PERCENT` (1); a scope 0–3 only on
    /// `DAMAGE_PERCENT` and `PENETRATION`; `min ≤ max`, within the id's range (the bounds §7.2
    /// states for the snapshot's sums, the fields' widths, 0 for a passive without a value).
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
            p < ATTRIBUTE_BOUND
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
        } else if id == id::KNOCKDOWN_FLAT {
            (0, MAX_KNOCKDOWN_FLAT)
        } else if id == id::ARMOR_VS || id == id::CONDITION_DURATION || id == id::ENCHANT_DURATION {
            (0, MAX_SIX_BITS)
        } else if id == id::LIFE_STEAL_ON_HIT || id == id::ENERGY_ON_HIT {
            (0, MAX_ON_HIT)
        } else if id == id::ADRENALINE_EVERY_N || id == id::QUICK_CAST_EVERY_N {
            (1, 255)
        } else if id == id::RATING_PERCENT {
            (0, MAX_RATING_PERCENT)
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

    /// A cost is fixed: `min = max` (design/15, Q-4).
    #[inline(always)]
    fn assert_fixed(self: @Passive) {
        assert(*self.min == *self.max, errors::FIXED);
    }
}
