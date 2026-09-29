//! Passive effects (design/19 §4): read, never scheduled; one id is one statistic. A `MODIFIER`
//! carries two, a benefit and a cost; an `ARMOR_SET` bonus is one. They are flattened into the
//! snapshot at entry, losslessly (§7.2).
//!
//! Layout of a passive, 53 bits: id 0–7 · param 8–15 · guard 16–18 · scope 19–20 · min 21–36 ·
//! max 37–52 (`min` and `max` signed, two's complement). The cost of a modifier is fixed (`min =
//! max`); the benefit's rolled value is the item's `ItemMods` byte. Id 0 is no passive.

use crate::helpers::signed::SignedTrait;
use crate::packing::{P16, P8};
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
/// `KNOCKDOWN_FLAT` is at most 3 ticks (2 bits in `MemberKit`).
pub const MAX_KNOCKDOWN_FLAT: i16 = 3;
/// `CONDITION_DURATION` and `ENCHANT_DURATION` percents fit 6 bits in `MemberKit`.
pub const MAX_DURATION_PERCENT: i16 = 63;

pub mod errors {
    pub const GUARD: felt252 = 'passive: guard';
    pub const SCOPE: felt252 = 'passive: scope';
    // The content pipeline's checks (`assert_legal`).
    pub const ID: felt252 = 'passive: id';
    pub const NOT_MVP: felt252 = 'passive: id after the MVP';
    pub const EMPTY: felt252 = 'passive: none with a field';
    pub const RANGE: felt252 = 'passive: min above max';
    pub const VALUE: felt252 = 'passive: value out of bounds';
    pub const FIXED: felt252 = 'passive: cost not fixed';
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

    /// Its 53 bits; refuses a guard wider than 3 bits or a scope wider than 2.
    fn pack(self: @Passive) -> u128 {
        assert(*self.guard < 8, errors::GUARD);
        assert(*self.scope < 4, errors::SCOPE);
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
}

#[generate_trait]
pub impl PassiveAssert of PassiveAssertTrait {
    /// The content pipeline's checks of one passive (§4, §7.2): id 0 has every field 0;
    /// otherwise the id is one of the MVP's, `min ≤ max`, a guard only on `ARMOR` (3 or 4) and
    /// `DAMAGE_PERCENT` (1), a scope only on `DAMAGE_PERCENT` and `PENETRATION`, and the bounds
    /// §7.2 states for the sums the snapshot stores.
    fn assert_legal(self: @Passive) {
        let id = *self.id;
        if id == id::NONE {
            assert(*self == Default::default(), errors::EMPTY);
            return;
        }
        assert(id >= id::FIRST && id <= id::LAST, errors::ID);
        assert(id <= id::LAST_MVP, errors::NOT_MVP);
        assert(*self.min <= *self.max, errors::RANGE);
        let g = *self.guard;
        if id == id::ARMOR {
            assert(g == guard::ALWAYS || g == guard::IN_STANCE || g == guard::ENCHANTED, errors::GUARD);
        } else if id == id::DAMAGE_PERCENT {
            assert(g == guard::ALWAYS || g == guard::ABOVE_HALF, errors::GUARD);
        } else {
            assert(g == guard::ALWAYS, errors::GUARD);
        }
        if id != id::DAMAGE_PERCENT && id != id::PENETRATION {
            assert(*self.scope == scope::WEAPON, errors::SCOPE);
        }
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
        } else if id == id::CONDITION_DURATION || id == id::ENCHANT_DURATION {
            (0, MAX_DURATION_PERCENT)
        } else if id == id::ADRENALINE_EVERY_N || id == id::QUICK_CAST_EVERY_N {
            (1, 255)
        } else {
            (-32768, 32767)
        };
        assert(*self.min >= low && *self.max <= high, errors::VALUE);
    }

    /// A cost is fixed: `min = max` (design/15, Q-4).
    #[inline(always)]
    fn assert_fixed(self: @Passive) {
        assert(*self.min == *self.max, errors::FIXED);
    }
}
