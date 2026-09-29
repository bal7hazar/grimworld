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
    /// - `QUICK_CAST_EVERY_N`: "held only on the weapon and the off-hand": their slot types
    ///   (prefix, suffix, inscription). "The pipeline gives it one slot type": which one the
    ///   document does not say, so every quick-cast modifier of the content shares one
    ///   (`ModifierAssert::assert_catalogue`), whichever it is (escalated);
    /// - `CONDITION_DURATION`: "one prefix, on the weapon only";
    /// - `DAMAGE_TYPE`: "a `DAMAGE_TYPE` modifier on the weapon, the only slot type the pipeline
    ///   gives it": a weapon's slot type (prefix, suffix, inscription), one for the whole content
    ///   (`assert_catalogue`); which one, and the weapon-only rule for a suffix or an
    ///   inscription, which the off-hand also has, are escalated;
    /// - `RATING_PERCENT`: personalisation only, never a record: §7.2's armor bound counts it
    ///   apart from the 37 `ARMOR` passives (F-21);
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
        } else if id == id::QUICK_CAST_EVERY_N || id == id::DAMAGE_TYPE {
            held_slot
        } else if id == id::CONDITION_DURATION {
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

    /// A cost is fixed: `min = max` (design/15, Q-4).
    #[inline(always)]
    fn assert_fixed(self: @Passive) {
        assert(*self.min == *self.max, errors::FIXED);
    }
}
