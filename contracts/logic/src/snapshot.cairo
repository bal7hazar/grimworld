//! The snapshot an instance takes of an adventurer at entry (ADR-0001: the ephemeral domain never
//! reads persistent state during play), and the task ids it will report (D-131). The persistent
//! contract builds them, the ephemeral contract stores them in the member's record; both use these
//! layouts, which is why they live in the shared package. Bit offsets are in
//! docs/architecture/ENG-01-interfaces.md, *Member*.
//!
//! design/19 §7.2 (FX-24, D-155) flattens every passive the rules read into these three words,
//! losslessly, with **0 new slots**: `MemberBar`'s free high limb takes the damage and penetration
//! sums, the quick-cast pairs and the unguarded armor; `MemberKit`'s high limb is repacked;
//! `MemberStats` holds the armor against each damage type where the single armor, the physical and
//! elemental armors and the single penetration were.

use crate::durations::MAX_DURATION_BONUS_PERCENT;
use crate::helpers::signed::SignedTrait;
use crate::models::base::slot as base_slot;
use crate::models::index::Modifier;
use crate::models::modifier::{ModifierRecord, ModifierTrait};
use crate::packing::{
    P104, P108, P112, P12, P120, P16, P20, P24, P32, P40, P48, P56, P64, P72, P8, P80, P84, P88,
    P96, join, low_field, split,
};
use crate::professions::ProfessionTrait;
use crate::types::effect::guard;
use crate::types::passive::{Passive, Source, id};

/// The widest unguarded armor (design/19 §7.2, F-20; F-21 settled by CBT-01): the weighted rating
/// of the five pieces (each `u8`, weights summing to 1: at most 255) and the shield's (`u8`, 255),
/// each raised by personalisation's +10 % of its rating (`RATING_PERCENT`, design/15 D-48: at most
/// ⌊255 × 10 / 100⌋ = 25 each), and at most 37 unguarded `ARMOR` passives of −255…+255:
/// `255 + 25 +
/// 255 + 25 + 37 × 255 = 9,995 < 32,767`. The two 255 limits are the ratings before
/// personalisation. An `i16` holds it.
pub const MAX_UNGUARDED_ARMOR: i16 = 9995;

const P92: u128 = 0x100000000000000000000000;

pub mod errors {
    pub const ARMOR_VS: felt252 = 'snapshot: armor vs above 63';
    pub const ARMOR: felt252 = 'snapshot: armor above bound';
    pub const QUICK_CAST: felt252 = 'snapshot: quick-cast attribute';
    pub const CONDITION: felt252 = 'snapshot: condition';
    pub const PERCENT: felt252 = 'snapshot: percent above 63';
    pub const KNOCKDOWN: felt252 = 'snapshot: knock-down above 3';
    pub const CONDITIONS: felt252 = 'snapshot: two conditions';
    pub const HEALTH_REGEN: felt252 = 'snapshot: health regen';
    // The production flattening's (`BuildAssert`, `SnapshotBuildTrait::build`).
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
    // The items worn (`WornAssert`, `WornTrait::held`; CBT-02c's wiring, D-168).
    /// A modifier on the item that the registry does not hold.
    pub const NO_MODIFIER: felt252 = 'item: no such modifier';
    /// An insignia made for another piece than the one it is worn on (DS-23, D-160).
    pub const INSIGNIA_PIECE: felt252 = 'item: insignia piece';
    /// A modifier in a slot of another type than its record's (ENG-01 §3.3).
    pub const SLOT_TYPE: felt252 = 'item: modifier slot type';
    /// A benefit's rolled value outside its record's range (design/19 §4).
    pub const VALUE: felt252 = 'item: modifier value';
}

/// Every field of the three snapshot words fits its layout (docs/CAIRO.md §7: checks in
/// `Assert` impls); the packers call them.
#[generate_trait]
pub impl MemberStatsAssert of MemberStatsAssertTrait {
    /// Each `ARMOR_VS` fits 6 bits; health regeneration 0–20, −10…+10 pips (DS-29, D-160).
    #[inline(always)]
    fn assert_valid(self: @MemberStats) {
        assert(*self.health_regen <= 20, errors::HEALTH_REGEN);
        let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = *self.armor_vs;
        assert(
            v1 < 64
                && v2 < 64
                && v3 < 64
                && v4 < 64
                && v5 < 64
                && v6 < 64
                && v7 < 64
                && v8 < 64
                && v9 < 64,
            errors::ARMOR_VS,
        );
    }
}

#[generate_trait]
pub impl MemberBarAssert of MemberBarAssertTrait {
    /// The unguarded armor within ±`MAX_UNGUARDED_ARMOR` (F-21); the quick-cast pairs
    /// (`QuickCastAssert`, checked as they pack).
    #[inline(always)]
    fn assert_valid(self: @MemberBar) {
        let armor = *self.armor;
        assert(armor >= -MAX_UNGUARDED_ARMOR && armor <= MAX_UNGUARDED_ARMOR, errors::ARMOR);
    }
}

#[generate_trait]
pub impl MemberKitAssert of MemberKitAssertTrait {
    /// Condition 4 bits, the two percents 6 bits, knock-down 2 bits.
    #[inline(always)]
    fn assert_valid(self: @MemberKit) {
        assert(*self.condition < 0x10, errors::CONDITION);
        assert(*self.condition_duration < 0x40, errors::PERCENT);
        assert(*self.enchantment_duration < 0x40, errors::PERCENT);
        assert(*self.knockdown < 4, errors::KNOCKDOWN);
    }

    /// The kit holds one condition's duration ("one prefix"): the passives name at most one.
    fn assert_one_condition(held: Span<Passive>) {
        let mut condition: u8 = 0;
        for passive in held {
            if *passive.id == id::CONDITION_DURATION {
                assert(condition == 0 || condition == *passive.param, errors::CONDITIONS);
                condition = *passive.param;
            }
        }
    }
}

/// What the build and the equipment give, fixed for the instance (design/03, design/15).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberStats {
    pub max_health: u16,
    pub max_energy: u8,
    /// Energy regeneration, in pips.
    pub energy_regen: u8,
    /// Health regeneration in pips, plus 10 (0 to 20 for −10 to +10 pips).
    pub health_regen: u8,
    /// `ARMOR_VS` per damage type, index `type − 1`, 6 bits each, saturated at 63 (FX-23): types
    /// 1–2 at bits 48 and 54, types 3–9 at `200 + 6 (type − 3)`.
    pub armor_vs: [u8; 9],
    pub level: u8,
    pub profession: u8,
    pub primary_rank: u8,
    /// The weapon's class, `types::combat::weapon` (design/19 §7.2).
    pub weapon: u8,
    pub weapon_damage: u8,
    pub weapon_ticks: u8,
    pub weapon_range: u8,
    pub weapon_strength: u8,
    /// The rank of the attribute of each bar skill, 4 bits each (skill `i` at bits `4 i`).
    pub ranks: u32,
    pub damage_type: u8,
    pub requirement_met: u8,
    /// Set bonuses in effect, one bit each.
    pub set_bonuses: u16,
}

pub fn pack_stats(s: MemberStats) -> felt252 {
    s.assert_valid();
    let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = s.armor_vs;
    let low: u128 = s.max_health.into()
        + s.max_energy.into() * P16
        + s.energy_regen.into() * P24
        + s.health_regen.into() * P32
        + v1.into() * P48
        + v2.into() * 0x40000000000000
        + s.level.into() * P64
        + s.profession.into() * P72
        + s.primary_rank.into() * P80
        + s.weapon.into() * P88
        + s.weapon_damage.into() * P96
        + s.weapon_ticks.into() * P104
        + s.weapon_range.into() * P112
        + s.weapon_strength.into() * P120;
    let high: u128 = s.ranks.into()
        + s.damage_type.into() * P32
        + s.requirement_met.into() * P48
        + s.set_bonuses.into() * P56
        + v3.into() * P72
        + v4.into() * 0x40000000000000000000
        + v5.into() * P84
        + v6.into() * 0x40000000000000000000000
        + v7.into() * P96
        + v8.into() * 0x40000000000000000000000000
        + v9.into() * P108;
    join(low, high)
}

pub fn unpack_stats(word: felt252) -> MemberStats {
    let (low, high) = split(word);
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let b6: NonZero<u128> = 0x40;
    let (low, max_health) = DivRem::div_rem(low, b16);
    let (low, max_energy) = DivRem::div_rem(low, b8);
    let (low, energy_regen) = DivRem::div_rem(low, b8);
    let (low, health_regen) = DivRem::div_rem(low, b8);
    // Bits 40–47 are free (the single armor moved to `MemberBar`, FX-24).
    let (low, v1) = DivRem::div_rem(low / P8, b6);
    let (low, v2) = DivRem::div_rem(low, b6);
    // Bits 60–63 are free.
    let (low, level) = DivRem::div_rem(low / 0x10, b8);
    let (low, profession) = DivRem::div_rem(low, b8);
    let (low, primary_rank) = DivRem::div_rem(low, b8);
    let (low, weapon) = DivRem::div_rem(low, b8);
    let (low, weapon_damage) = DivRem::div_rem(low, b8);
    let (low, weapon_ticks) = DivRem::div_rem(low, b8);
    let (weapon_strength, weapon_range) = DivRem::div_rem(low, b8);
    let (high, ranks) = DivRem::div_rem(high, P32.try_into().unwrap());
    let (high, damage_type) = DivRem::div_rem(high, b8);
    // Bits 168–175 are free (the single penetration moved to `MemberBar`, FX-24).
    let (high, requirement_met) = DivRem::div_rem(high / P8, b8);
    let (high, set_bonuses) = DivRem::div_rem(high, b16);
    let (high, v3) = DivRem::div_rem(high, b6);
    let (high, v4) = DivRem::div_rem(high, b6);
    let (high, v5) = DivRem::div_rem(high, b6);
    let (high, v6) = DivRem::div_rem(high, b6);
    let (high, v7) = DivRem::div_rem(high, b6);
    let (v9, v8) = DivRem::div_rem(high, b6);
    MemberStats {
        max_health: max_health.try_into().unwrap(),
        max_energy: max_energy.try_into().unwrap(),
        energy_regen: energy_regen.try_into().unwrap(),
        health_regen: health_regen.try_into().unwrap(),
        armor_vs: [
            v1.try_into().unwrap(), v2.try_into().unwrap(), v3.try_into().unwrap(),
            v4.try_into().unwrap(), v5.try_into().unwrap(), v6.try_into().unwrap(),
            v7.try_into().unwrap(), v8.try_into().unwrap(), v9.try_into().unwrap(),
        ],
        level: level.try_into().unwrap(),
        profession: profession.try_into().unwrap(),
        primary_rank: primary_rank.try_into().unwrap(),
        weapon: weapon.try_into().unwrap(),
        weapon_damage: weapon_damage.try_into().unwrap(),
        weapon_ticks: weapon_ticks.try_into().unwrap(),
        weapon_range: weapon_range.try_into().unwrap(),
        weapon_strength: weapon_strength.try_into().unwrap(),
        ranks: ranks.try_into().unwrap(),
        damage_type: damage_type.try_into().unwrap(),
        requirement_met: requirement_met.try_into().unwrap(),
        set_bonuses: set_bonuses.try_into().unwrap(),
    }
}

pub impl MemberStatsStorePacking of starknet::storage_access::StorePacking<MemberStats, felt252> {
    fn pack(value: MemberStats) -> felt252 {
        pack_stats(value)
    }
    fn unpack(value: felt252) -> MemberStats {
        unpack_stats(value)
    }
}

/// A quick-cast modifier held (`QUICK_CAST_EVERY_N`, design/19 §4, §5.12): its attribute (4
/// bits) and its N (8 bits; 0 for none). At most two are held, each with its own counter
/// (`MemberState.casts`, `casts_2`; FX-43).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct QuickCast {
    pub attribute: u8,
    pub every: u8,
}

/// The skill bar (8 skill ids, registry `u16`), locked for the expedition (design/03), and, in
/// its high limb, the passives the rules read at each hit or cast (design/19 §7.2, FX-24).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberBar {
    pub skills: [u16; 8],
    /// The slot of the elite skill, 255 for none (bits 128–135).
    pub elite_slot: u8,
    /// `DAMAGE_PERCENT` sums (bits 136–183), index `3 × guard + class`: guard `ALWAYS` 0 or
    /// `ABOVE_HALF` 1, hit class (`passive::HIT_*`) a plain weapon hit 0 (scopes `WEAPON`,
    /// `ALL`), an attack skill's hit 1 (`WEAPON`, `ATTACK_SKILL`, `ALL`: design/19 §5.4), a
    /// spell's hit 2 (`SPELL`, `ALL`). Each −126…+126.
    pub damage: [i8; 6],
    /// `PENETRATION` sums, percent, index the hit class as above (bits 184–207). Each ≤ 252,
    /// capped at 100 at use.
    pub penetration: [u8; 3],
    /// Two quick-cast modifiers, 12 bits each (bits 208–231).
    pub quick_cast: [QuickCast; 2],
    /// The unguarded armor, signed (bits 232–247), at most `MAX_UNGUARDED_ARMOR` either way.
    pub armor: i16,
}

#[generate_trait]
pub impl QuickCastImpl of QuickCastTrait {
    /// Its 12 bits: attribute 0–3 · N 4–11 (`QuickCastAssert::assert_valid`).
    fn pack(self: @QuickCast) -> u128 {
        self.assert_valid();
        (*self.attribute).into() + (*self.every).into() * 0x10
    }

    /// The pair of 12 bits.
    fn unpack(bits: u128) -> QuickCast {
        let (every, attribute) = DivRem::div_rem(bits, 0x10);
        QuickCast { attribute: attribute.try_into().unwrap(), every: every.try_into().unwrap() }
    }
}

#[generate_trait]
pub impl QuickCastAssert of QuickCastAssertTrait {
    /// The attribute fits 4 bits.
    #[inline(always)]
    fn assert_valid(self: @QuickCast) {
        assert(*self.attribute < 0x10, errors::QUICK_CAST);
    }
}

pub fn pack_bar(b: MemberBar) -> felt252 {
    let [s0, s1, s2, s3, s4, s5, s6, s7] = b.skills;
    let [d0, d1, d2, d3, d4, d5] = b.damage;
    let [p0, p1, p2] = b.penetration;
    let [q0, q1] = b.quick_cast;
    b.assert_valid();
    let low: u128 = s0.into()
        + s1.into() * P16
        + s2.into() * P32
        + s3.into() * P48
        + s4.into() * P64
        + s5.into() * P80
        + s6.into() * P96
        + s7.into() * P112;
    let high: u128 = b.elite_slot.into()
        + SignedTrait::bits8(d0) * P8
        + SignedTrait::bits8(d1) * P16
        + SignedTrait::bits8(d2) * P24
        + SignedTrait::bits8(d3) * P32
        + SignedTrait::bits8(d4) * P40
        + SignedTrait::bits8(d5) * P48
        + p0.into() * P56
        + p1.into() * P64
        + p2.into() * P72
        + q0.pack() * P80
        + q1.pack() * P92
        + SignedTrait::bits16(b.armor) * P104;
    join(low, high)
}

pub fn unpack_bar(word: felt252) -> MemberBar {
    let (low, high) = split(word);
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b12: NonZero<u128> = P12.try_into().unwrap();
    let (low, s0) = DivRem::div_rem(low, b16);
    let (low, s1) = DivRem::div_rem(low, b16);
    let (low, s2) = DivRem::div_rem(low, b16);
    let (low, s3) = DivRem::div_rem(low, b16);
    let (low, s4) = DivRem::div_rem(low, b16);
    let (low, s5) = DivRem::div_rem(low, b16);
    let (s7, s6) = DivRem::div_rem(low, b16);
    let (high, elite_slot) = DivRem::div_rem(high, b8);
    let (high, d0) = DivRem::div_rem(high, b8);
    let (high, d1) = DivRem::div_rem(high, b8);
    let (high, d2) = DivRem::div_rem(high, b8);
    let (high, d3) = DivRem::div_rem(high, b8);
    let (high, d4) = DivRem::div_rem(high, b8);
    let (high, d5) = DivRem::div_rem(high, b8);
    let (high, p0) = DivRem::div_rem(high, b8);
    let (high, p1) = DivRem::div_rem(high, b8);
    let (high, p2) = DivRem::div_rem(high, b8);
    let (high, q0) = DivRem::div_rem(high, b12);
    let (high, q1) = DivRem::div_rem(high, b12);
    let armor = low_field(high, b16);
    MemberBar {
        skills: [
            s0.try_into().unwrap(), s1.try_into().unwrap(), s2.try_into().unwrap(),
            s3.try_into().unwrap(), s4.try_into().unwrap(), s5.try_into().unwrap(),
            s6.try_into().unwrap(), s7.try_into().unwrap(),
        ],
        elite_slot: elite_slot.try_into().unwrap(),
        damage: [
            SignedTrait::from8(d0), SignedTrait::from8(d1), SignedTrait::from8(d2),
            SignedTrait::from8(d3), SignedTrait::from8(d4), SignedTrait::from8(d5),
        ],
        penetration: [p0.try_into().unwrap(), p1.try_into().unwrap(), p2.try_into().unwrap()],
        quick_cast: [QuickCastTrait::unpack(q0), QuickCastTrait::unpack(q1)],
        armor: SignedTrait::from16(armor),
    }
}

pub impl MemberBarStorePacking of starknet::storage_access::StorePacking<MemberBar, felt252> {
    fn pack(value: MemberBar) -> felt252 {
        pack_bar(value)
    }
    fn unpack(value: felt252) -> MemberBar {
        unpack_bar(value)
    }
}

/// The belt (4 potion item ids) and the modifiers of the equipment, flattened at entry
/// (design/15: equipment cannot change during an expedition; design/19 §7.2, FX-24). High limb,
/// 75 bits: life steal 128–135 · energy on hit 136–143 · condition 144–147 · its duration
/// percent 148–153 · enchantment duration percent 154–159 · double adrenaline every N hits
/// 160–167 ·
/// health bonus 168–183 · armor in a stance 184–191 · armor enchanted 192–199 (signed) ·
/// knock-down ticks 200–201 · halving 202.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberKit {
    pub belt: [u32; 4],
    /// `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT`.
    pub life_steal: u8,
    pub energy_on_hit: u8,
    /// `CONDITION_DURATION`: its condition (4 bits; 0 none) and percent (6 bits). One prefix, on
    /// the weapon only.
    pub condition: u8,
    pub condition_duration: u8,
    /// `ENCHANT_DURATION` percent (6 bits).
    pub enchantment_duration: u8,
    /// `ADRENALINE_EVERY_N`: the lowest N held (FX-43); 0 none.
    pub double_adrenaline_every: u8,
    /// `MAX_HEALTH` from the equipment.
    pub health_bonus: u16,
    /// The guarded `ARMOR` sums, signed, each −126…+126 (F-20): `IN_STANCE`, `ENCHANTED`.
    pub armor_stance: i8,
    pub armor_enchanted: i8,
    /// `KNOCKDOWN_FLAT`, 0–3 ticks.
    pub knockdown: u8,
    /// `HALVE_FIRST_HEAVY_HIT` held.
    pub halving: bool,
}

pub fn pack_kit(k: MemberKit) -> felt252 {
    k.assert_valid();
    let [b0, b1, b2, b3] = k.belt;
    let low: u128 = b0.into() + b1.into() * P32 + b2.into() * P64 + b3.into() * P96;
    let high: u128 = k.life_steal.into()
        + k.energy_on_hit.into() * P8
        + k.condition.into() * P16
        + k.condition_duration.into() * P20
        + k.enchantment_duration.into() * 0x4000000
        + k.double_adrenaline_every.into() * P32
        + k.health_bonus.into() * P40
        + SignedTrait::bits8(k.armor_stance) * P56
        + SignedTrait::bits8(k.armor_enchanted) * P64
        + k.knockdown.into() * P72
        + if k.halving {
            0x4000000000000000000
        } else {
            0
        };
    join(low, high)
}

pub fn unpack_kit(word: felt252) -> MemberKit {
    let (low, high) = split(word);
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b32: NonZero<u128> = P32.try_into().unwrap();
    let (low, b0) = DivRem::div_rem(low, b32);
    let (low, b1) = DivRem::div_rem(low, b32);
    let (b3, b2) = DivRem::div_rem(low, b32);
    let (high, life_steal) = DivRem::div_rem(high, b8);
    let (high, energy_on_hit) = DivRem::div_rem(high, b8);
    let (high, condition) = DivRem::div_rem(high, 0x10);
    let (high, condition_duration) = DivRem::div_rem(high, 0x40);
    let (high, enchantment_duration) = DivRem::div_rem(high, 0x40);
    let (high, double_adrenaline_every) = DivRem::div_rem(high, b8);
    let (high, health_bonus) = DivRem::div_rem(high, P16.try_into().unwrap());
    let (high, armor_stance) = DivRem::div_rem(high, b8);
    let (high, armor_enchanted) = DivRem::div_rem(high, b8);
    let (halving, knockdown) = DivRem::div_rem(high, 4);
    MemberKit {
        belt: [
            b0.try_into().unwrap(), b1.try_into().unwrap(), b2.try_into().unwrap(),
            b3.try_into().unwrap(),
        ],
        life_steal: life_steal.try_into().unwrap(),
        energy_on_hit: energy_on_hit.try_into().unwrap(),
        condition: condition.try_into().unwrap(),
        condition_duration: condition_duration.try_into().unwrap(),
        enchantment_duration: enchantment_duration.try_into().unwrap(),
        double_adrenaline_every: double_adrenaline_every.try_into().unwrap(),
        health_bonus: health_bonus.try_into().unwrap(),
        armor_stance: SignedTrait::from8(armor_stance),
        armor_enchanted: SignedTrait::from8(armor_enchanted),
        knockdown: knockdown.try_into().unwrap(),
        halving: halving != 0,
    }
}

/// The snapshot builder's flattening of the kit (design/19 §4, §7.2). ENG-06 builds the rest of
/// the snapshot with design/15's formulas; the rules here are the ones a flattening defect was
/// found in (CBT-9).
#[generate_trait]
pub impl MemberKitImpl of MemberKitTrait {
    /// `CONDITION_DURATION` held: `(condition, percent)`, `(0, 0)` for none. Summed **per
    /// condition** (§4, FX-43: a prefix's benefit and cost may name the same one, 33 + 10 = 43),
    /// then capped at `MAX_DURATION_BONUS_PERCENT` (ENG-01 §3.1). The kit holds one condition
    /// ("one prefix"): two conditions are refused, as the validators refuse them on one source.
    /// Summed wide (`u32`), then saturated at 50 (DS-5): design/20 §6 test 4's 65,534 gives 50.
    fn condition_duration(held: Span<Passive>) -> (u8, u8) {
        MemberKitAssert::assert_one_condition(held);
        let mut condition: u8 = 0;
        let mut percent: u32 = 0;
        for passive in held {
            if *passive.id == id::CONDITION_DURATION {
                condition = *passive.param;
                let value: i32 = (*passive.max).into();
                percent += value.try_into().unwrap();
            }
        }
        (condition, saturate(percent, MAX_DURATION_BONUS_PERCENT).try_into().unwrap())
    }
}

/// A sum flattened wide, then saturated at its field's cap (DS-5, FX-23). A free function: the
/// arithmetic of one field, no type owns it.
pub fn saturate(sum: u32, cap: u32) -> u32 {
    if sum > cap {
        cap
    } else {
        sum
    }
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
/// The knock-down's flat bonus saturates at 3 ticks (`durations::MAX_DURATION_FLAT`, DS-5).
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


/// A passive the build holds (design/20 §1.2). Its value is `passive.max`: a benefit's rolled
/// value (the caller writes the roll in), a cost's fixed one. `instance` numbers its source: the
/// passives of one instance are one modifier on one item (its benefit and cost), or one set bonus.
/// `modifier` is the `MODIFIER` record's id (0 for a set bonus): health runes of one id count
/// once (FX-43, D-157 D).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct HeldPassive {
    pub passive: Passive,
    pub source: Source,
    pub instance: u8,
    pub modifier: u32,
    /// A modifier's benefit, not its cost; a set bonus is a benefit.
    pub benefit: bool,
    /// The armor piece its item is worn on (`base::slot::CHEST` … `FEET`) for an insignia, which
    /// bounds its health (DS-23); 0 for every other source.
    pub piece: u8,
}

/// What the flattening reads besides the passives (design/03, design/15).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Loadout {
    pub level: u8,
    /// A primary profession of the MVP (1–3).
    pub profession: u8,
    /// The build's attribute points by attribute id, the primary first (design/03). A
    /// quick-cast pair's attribute is its index here, the build-local index of D-157 A.
    pub points: Span<(u8, u8)>,
    /// The attribute of each bar skill (0 for an empty slot), for `MemberStats.ranks`.
    pub bar_attributes: [u8; 8],
    pub skills: [u16; 8],
    pub elite_slot: u8,
    /// The weapon: class, damage at its requirement (before personalisation), ticks, range, type,
    /// attribute, whether the requirement is met, whether it is personalised.
    pub weapon: u8,
    pub weapon_damage: u8,
    pub weapon_ticks: u8,
    pub weapon_range: u8,
    pub damage_type: u8,
    pub weapon_attribute: u8,
    pub requirement_met: u8,
    pub personalised: bool,
    /// design/04's level cap on weapon strength (DS-9); its curve is BAL-01's (escalated).
    pub strength_cap: u8,
    /// The weighted rating of the pieces and the shield, personalised (design/15, F-21).
    pub rating: u16,
    pub set_bonuses: u16,
    pub belt: [u32; 4],
    pub belt_counts: [u8; 4],
}

/// An item worn, as `Hub.set_build` reads it (ENG-01 §3.3): its lane of `equipped` (0 the weapon
/// … 6 the feet), its slot (`base::slot`, copied from its `BASE` at creation, D-158), and its
/// `ItemMods`: the modifier id and the rolled value of each slot type in order (prefix, suffix,
/// inscription, insignia, rune), id 0 for an empty slot.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Worn {
    pub lane: u8,
    pub slot: u8,
    pub ids: [u16; 5],
    pub values: [u8; 5],
}

#[generate_trait]
pub impl WornImpl of WornTrait {
    /// The passives the worn items hold, for the flattening (design/19 §4, §7.2; design/20 §1.2):
    /// each modifier's benefit, its value the item's rolled byte, and its cost, fixed by its
    /// record; their source the record's slot type; one instance a modifier, numbered
    /// `5 × lane + slot`, so upward; an insignia's piece the item's slot (DS-23). `ids` are the
    /// distinct modifier ids the items hold and `records` their `MODIFIER` records, one part each,
    /// in the same order (`Hub.set_build` asks the registry for them once, however many items
    /// hold one). Bound: 7 items, 5 modifiers an item, 15 records.
    fn held(worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>) -> Array<HeldPassive> {
        let mut modifiers: Array<Modifier> = array![];
        for part in records {
            WornAssert::assert_exists(*part);
            modifiers.append(ModifierRecord::unpack(array![*part].span()));
        }
        let modifiers = modifiers.span();
        let mut out: Array<HeldPassive> = array![];
        for item in worn {
            let first = *item.lane * 5;
            let values = item.values.span();
            let mut slot: u8 = 0;
            for id in item.ids.span() {
                let id = *id;
                if id != 0 {
                    let mut k = 0;
                    while *ids[k] != id {
                        k += 1;
                    }
                    let record = modifiers[k];
                    let value = *values[slot.into()];
                    WornAssert::assert_slot(*record.slot, slot);
                    WornAssert::assert_value(value, record.benefit);
                    let source = record.source().unwrap();
                    let piece = if source == Source::Insignia {
                        WornAssert::assert_piece(*record.piece, *item.slot);
                        *item.slot
                    } else {
                        0
                    };
                    let instance = first + slot;
                    let benefit = Passive { max: value.into(), ..*record.benefit };
                    out
                        .append(
                            HeldPassive {
                                passive: benefit,
                                source,
                                instance,
                                modifier: id.into(),
                                benefit: true,
                                piece,
                            },
                        );
                    if record.has_cost() {
                        out
                            .append(
                                HeldPassive {
                                    passive: *record.cost,
                                    source,
                                    instance,
                                    modifier: id.into(),
                                    benefit: false,
                                    piece,
                                },
                            );
                    }
                }
                slot += 1;
            }
        }
        out
    }
}

#[generate_trait]
pub impl WornAssert of WornAssertTrait {
    /// A modifier an item holds is a record of the registry (its part 0 is not 0).
    #[inline(always)]
    fn assert_exists(part: felt252) {
        assert(part != 0, errors::NO_MODIFIER);
    }

    /// A modifier sits in the slot of its record's type: `ItemMods`' five slots are the five
    /// slot types in order (`modifier::slot::PREFIX` … `RUNE`, ENG-01 §3.3), so an item holds at
    /// most one of each. `position` is the slot's, from 0.
    #[inline(always)]
    fn assert_slot(slot_type: u8, position: u8) {
        assert(slot_type == position + 1, errors::SLOT_TYPE);
    }

    /// The benefit's rolled value lies within its record's range (design/19 §4): the per-source
    /// bounds the registry checked on the record (D-166) then bound it.
    #[inline(always)]
    fn assert_value(value: u8, benefit: @Passive) {
        let value: i16 = value.into();
        assert(value >= *benefit.min && value <= *benefit.max, errors::VALUE);
    }

    /// DS-23 (D-160): an insignia is worn on the piece its record names (`base::slot::CHEST` …
    /// `FEET`), the item's slot.
    #[inline(always)]
    fn assert_piece(piece: u8, slot: u8) {
        assert(piece == slot, errors::INSIGNIA_PIECE);
    }
}

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
                assert(index < 16, errors::QUICK_CAST_ATTRIBUTE);
                return index;
            }
            index += 1;
        }
        core::panic_with_felt252(errors::QUICK_CAST_ATTRIBUTE)
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
                assert(instance >= next, errors::ORDER);
                next = instance + 1;
                counts += FlattenTrait::count_lane(*h.source);
                if *h.source == Source::Insignia {
                    let bit: u8 = *[1, 2, 4, 8, 16].span()[(*h.piece - base_slot::CHEST).into()];
                    assert(pieces & bit == 0, errors::PIECE_TWICE);
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
        assert(pairs.len() <= 2, errors::QUICK_CAST_ATTRIBUTE);
        while pairs.len() < 2 {
            pairs.append(Default::default());
        }

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
        let strength: u16 = STRENGTH_PER_RANK
            * FlattenTrait::rank(points, runes, *loadout.weapon_attribute).into();
        let cap: u16 = (*loadout.strength_cap).into();
        let strength = if strength > cap {
            cap
        } else {
            strength
        };
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
        (pack_stats(snapshot.stats), pack_bar(snapshot.bar), pack_kit(snapshot.kit))
    }
}

pub impl MemberKitStorePacking of starknet::storage_access::StorePacking<MemberKit, felt252> {
    fn pack(value: MemberKit) -> felt252 {
        pack_kit(value)
    }
    fn unpack(value: felt252) -> MemberKit {
        unpack_kit(value)
    }
}

/// What the persistent contract hands to the ephemeral one at entry (the snapshot).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Snapshot {
    pub stats: MemberStats,
    pub bar: MemberBar,
    pub kit: MemberKit,
    /// Potions carried in each belt slot: debited from the pack in the entry transaction (the
    /// reserve), credited back unused by the closing report (`Results.belt`).
    pub belt_counts: [u8; 4],
}

/// Health at level 1, and what each level above adds (design/03, *Base stats*).
pub const BASE_HEALTH: u16 = 100;
pub const HEALTH_PER_LEVEL: u16 = 20;
/// `MemberStats.health_regen` is the pips plus 10: no regeneration nor degeneration.
pub const NO_HEALTH_REGEN: u8 = 10;

#[generate_trait]
pub impl SnapshotImpl of SnapshotTrait {
    /// The snapshot of an adventurer without equipment, from its level and primary profession
    /// (ENG-06): health, energy, regeneration and armor (design/03); its bar, elite slot and belt
    /// copied; what equipment, attribute ranks and set bonuses add, 0. The tests' snapshot:
    /// `Hub.enter` copies the one `set_build` stored (`from_words`, D-168).
    fn new(
        level: u8,
        profession: u8,
        skills: [u16; 8],
        elite_slot: u8,
        belt: [u32; 4],
        belt_counts: [u8; 4],
    ) -> Snapshot {
        let stats = MemberStats {
            max_health: BASE_HEALTH + HEALTH_PER_LEVEL * (level.into() - 1),
            max_energy: ProfessionTrait::energy(profession),
            energy_regen: ProfessionTrait::energy_regen(profession),
            health_regen: NO_HEALTH_REGEN,
            level,
            profession,
            ..Default::default(),
        };
        // The class's armor is the unguarded armor, in `MemberBar` since FX-24 (design/19 §7.2).
        let armor: u8 = ProfessionTrait::armor(profession);
        Snapshot {
            stats,
            bar: MemberBar {
                skills,
                elite_slot,
                damage: [0; 6],
                penetration: [0; 3],
                quick_cast: [Default::default(); 2],
                armor: armor.into(),
            },
            kit: MemberKit { belt, ..Default::default() },
            belt_counts,
        }
    }

    /// The snapshot of the three packed words `SnapshotBuildTrait::words` gave (D-168) and the
    /// belt's counts.
    fn from_words(
        stats: felt252, bar: felt252, kit: felt252, belt_counts: [u8; 4],
    ) -> Snapshot {
        Snapshot {
            stats: unpack_stats(stats), bar: unpack_bar(bar), kit: unpack_kit(kit), belt_counts,
        }
    }
}

/// One task an instance reports (D-131): the quiver task id and what counts toward it, which the
/// instance can check without reading the persistent domain.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct TaskEntry {
    pub task: u32,
    /// `criteria` of docs/architecture/ENG-01-interfaces.md: 1 kill a caste, 2 reach a landmark,
    /// 3 clear a dungeon, 4 reveal a whole zone, 5 loot remains, 6 mine, 7 activate objects.
    pub kind: u8,
    /// The registry id the kind counts (a caste, a landmark, a location).
    pub param: u16,
}

/// Four tasks per stored page: at bits 0 and 56 (low limb), 128 and 184 (high limb).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct TaskPage {
    pub entries: [TaskEntry; 4],
}

fn pack_task(t: TaskEntry) -> u128 {
    t.task.into() + t.kind.into() * P32 + t.param.into() * P40
}

fn unpack_task(bits: u128) -> TaskEntry {
    let (rest, task) = DivRem::div_rem(bits, P32.try_into().unwrap());
    let (param, kind) = DivRem::div_rem(rest, P8.try_into().unwrap());
    TaskEntry {
        task: task.try_into().unwrap(),
        kind: kind.try_into().unwrap(),
        param: param.try_into().unwrap(),
    }
}

pub fn pack_task_page(p: TaskPage) -> felt252 {
    let [a, b, c, d] = p.entries;
    join(pack_task(a) + pack_task(b) * P56, pack_task(c) + pack_task(d) * P56)
}

pub fn unpack_task_page(word: felt252) -> TaskPage {
    let (low, high) = split(word);
    let s56: NonZero<u128> = P56.try_into().unwrap();
    let (b, a) = DivRem::div_rem(low, s56);
    let (d, c) = DivRem::div_rem(high, s56);
    TaskPage { entries: [unpack_task(a), unpack_task(b), unpack_task(c), unpack_task(d)] }
}

pub impl TaskPageStorePacking of starknet::storage_access::StorePacking<TaskPage, felt252> {
    fn pack(value: TaskPage) -> felt252 {
        pack_task_page(value)
    }
    fn unpack(value: felt252) -> TaskPage {
        unpack_task_page(value)
    }
}

/// The flattening's unit tests (D-167): design/20 §6's extremal builds, floors, saturations and
/// counts, each compared with the oracle, CBT-02's flattening: every sum a plain pass over the
/// passives per statistic, obviously correct and quadratic (docs/CAIRO.md §2, *Oracles*). The
/// validators' tests (the per-source bounds, the records) are in `tests/test_build.cairo`, and the
/// registry's refusals in the persistent package's `tests/test_registry.cairo`.
#[cfg(test)]
mod tests {
    use crate::durations::MAX_DURATION_BONUS_PERCENT;
    use crate::models::base::slot as base_slot;
    use crate::packing::LIVE;
    use crate::professions::ProfessionTrait;
    use crate::types::combat::{condition, damage, weapon};
    use crate::types::effect::{guard, scope};
    use crate::types::passive::{
        HIT_ATTACK_SKILL, HIT_SPELL, HIT_WEAPON, Passive, PassiveTrait, Source, id,
    };
    use super::{
        BuildAssert, HEAVY_VS_PHYSICAL, HeldPassive, LIGHT_ENERGY, LIGHT_ENERGY_REGEN, Loadout,
        MAX_ARMOR_VS, MAX_KNOCKDOWN, MAX_UNGUARDED_ARMOR, MEDIUM_VS_ELEMENTAL, MemberBar, MemberKit,
        MemberKitTrait, MemberStats, PERSONALISED_DAMAGE_PERCENT, QuickCast, STRENGTH_PER_RANK,
        Snapshot, SnapshotBuildTrait, TaskEntry, TaskPage, WELLSPRING_ENERGY_PER_RANK, errors, fit,
        pack_bar, pack_kit, pack_stats, pack_task_page, saturate, unpack_bar, unpack_kit,
        unpack_stats, unpack_task_page,
    };

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// CBT-02's sums, the oracle's.
    #[generate_trait]
    impl Oracle of OracleTrait {
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
        let energy = base_energy + wellspring + light_energy + Oracle::total(held, id::MAX_ENERGY);
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
        let (condition, condition_duration) = MemberKitTrait::condition_duration(conditions.span());
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

    /// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
    const PRIMARY: u8 = 13;
    const OTHER: u8 = 14;

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
            passive, source, instance, modifier, benefit: true, piece: piece(source, instance),
        }
    }

    fn cost(passive: Passive, source: Source, instance: u8, modifier: u32) -> HeldPassive {
        HeldPassive {
            passive, source, instance, modifier, benefit: false, piece: piece(source, instance),
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

    /// The 17 sources of design/20 §1.2, instances 0–16: a prefix, 2 suffixes, 2 inscriptions,
    /// 5 insignias, 5 runes, 2 set bonuses.
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
        for source in sources() {
            let mut take = false;
            for kind in on {
                if *kind == *source {
                    take = true;
                }
            }
            if take {
                all.append(held(p, *source, i, 100 + i.into()));
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
        assert(snapshot == oracle(loadout, held), 'differs from the oracle');
        snapshot
    }

    // design/20 §6 test 2 (AUD-182-2), the extremal builds at the envelope: every source that
    // may hold a statistic at its per-source maximum (and, where no floor refuses it, its
    // minimum) flattens without overflow, to exactly the envelope.
    #[test]
    #[available_gas(l2_gas: 12470119)] // ceil(1.05 × 11876303 measured)
    fn test_envelope_builds() {
        // Held slots at 30, insignias at their pieces' 15 / 10 / 5 / 5 / 5 (DS-23), runes and
        // set bonuses at 50.
        let mut all = everywhere(passive(id::MAX_HEALTH, 0, 30), held_slots());
        let mut k: u8 = 0;
        for value in array![15_i16, 10, 5, 5, 5] {
            all.append(held(passive(id::MAX_HEALTH, 0, value), Source::Insignia, 5 + k, 200));
            k += 1;
        }
        for h in everywhere(
            passive(id::MAX_HEALTH, 0, 50), array![Source::Rune, Source::SetBonus].span(),
        ) {
            all.append(h);
        }
        let top = flatten(@loadout(1, 20), all.span());
        assert(top.stats.max_health == 1020, 'max health 1,020');
        let low = flatten(
            @loadout(3, 20),
            everywhere(
                passive(id::HEALTH_REGEN, 0, -1),
                array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus]
                    .span(),
            )
                .span(),
        );
        assert(low.stats.health_regen == 3, 'health regen 3');
        let high = flatten(
            @loadout(3, 20),
            everywhere(passive(id::HEALTH_REGEN, 0, 1), array![Source::SetBonus].span()).span(),
        );
        assert(high.stats.health_regen == 12, 'health regen 12');
        let steal = flatten(
            @loadout(3, 20), everywhere(passive(id::LIFE_STEAL_ON_HIT, 0, 5), held_slots()).span(),
        );
        assert(steal.kit.life_steal == 25, 'life steal 25');
        let hit = flatten(
            @loadout(3, 20), everywhere(passive(id::ENERGY_ON_HIT, 0, 1), held_slots()).span(),
        );
        assert(hit.kit.energy_on_hit == 5, 'energy on hit 5');
        let regen = flatten(
            @loadout(3, 20),
            everywhere(passive(id::ENERGY_REGEN, 0, 1), array![Source::SetBonus].span()).span(),
        );
        assert(regen.stats.energy_regen == 7, 'energy regen 7');
    }

    // §6 test 2: max health 1,020 (DS-23's insignias 15 / 10 / 5, D-160): level 20, five +30
    // held slots, insignias 15, 10, 5, 5, 5, five +50 health runes of distinct ids, two +50 set
    // bonuses. The final maximum is `max_health`; `health_bonus` is freed (DS-3).
    #[test]
    #[available_gas(l2_gas: 4266253)] // ceil(1.05 × 4063098 measured)
    fn test_extremal_max_health() {
        let mut all = everywhere(passive(id::MAX_HEALTH, 0, 30), held_slots());
        let insignias = [15_i16, 10, 5, 5, 5];
        let mut k: u8 = 0;
        for value in insignias.span() {
            all.append(held(passive(id::MAX_HEALTH, 0, *value), Source::Insignia, 5 + k, 200));
            k += 1;
        }
        for held_passive in everywhere(
            passive(id::MAX_HEALTH, 0, 50), array![Source::Rune, Source::SetBonus].span(),
        ) {
            all.append(held_passive);
        }
        let snapshot = flatten(@loadout(1, 20), all.span());
        assert(snapshot.stats.max_health == 1020, 'max health 1,020');
        assert(snapshot.kit.health_bonus == 0, 'health bonus freed');
    }

    // §6 test 2: max energy 130 (DS-7): an Arcanist at Wellspring 15 (12 points and a +3 rune:
    // ranks 15, DS-8) in light armor, five held slots and two set bonuses at +5: 30 + 45 + 20 +
    // 35.
    #[test]
    #[available_gas(l2_gas: 2492861)] // ceil(1.05 × 2374153 measured)
    fn test_extremal_max_energy_and_rank() {
        let mut all = everywhere(passive(id::MAX_ENERGY, 0, 5), held_slots());
        all.append(held(passive(id::ATTRIBUTE, PRIMARY, 3), Source::Rune, 10, 300));
        for h in everywhere(passive(id::MAX_ENERGY, 0, 5), array![Source::SetBonus].span()) {
            all.append(h);
        }
        let snapshot = flatten(@loadout(3, 20), all.span());
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
    #[available_gas(l2_gas: 1230908)] // ceil(1.05 × 1172293 measured)
    fn test_ranks_of_every_bar_slot() {
        let all = array![held(passive(id::ATTRIBUTE, PRIMARY, 3), Source::Rune, 10, 300)];
        let build = Loadout { bar_attributes: [PRIMARY; 8], ..loadout(3, 20) };
        let snapshot = flatten(@build, all.span());
        assert(snapshot.stats.ranks == 0xffffffff, 'eight ranks of 15');
    }

    // §6 test 2: weapon damage 32, a personalised maul at requirement (27 × 120 / 100, DS-4); the
    // strength is 5 × the weapon attribute's rank capped by level (DS-9): 50, and 40 under a cap
    // of 40.
    #[test]
    #[available_gas(l2_gas: 1646344)] // ceil(1.05 × 1567946 measured)
    fn test_extremal_weapon() {
        let maul = Loadout {
            weapon: weapon::MAUL,
            weapon_damage: 27,
            weapon_ticks: 2,
            personalised: true,
            ..loadout(1, 20),
        };
        let snapshot = flatten(@maul, array![].span());
        assert(snapshot.stats.weapon_damage == 32, 'weapon damage 32');
        assert(snapshot.stats.weapon_strength == 50, '5 x 10');
        let capped = Loadout { strength_cap: 40, ..maul };
        let snapshot = flatten(@capped, array![].span());
        assert(snapshot.stats.weapon_strength == 40, 'capped by level');
    }

    // §6 test 2, "each other field ≤ its envelope": every source at its widest on every other
    // row.
    #[test]
    #[available_gas(l2_gas: 5609004)] // ceil(1.05 × 5341908 measured)
    fn test_other_fields_within_envelopes() {
        let mut all = array![];
        let mut i: u8 = 0;
        for source in sources() {
            let s = *source;
            let modifier: u32 = 100 + i.into();
            if s == Source::Prefix || s == Source::Suffix || s == Source::Inscription {
                all.append(held(passive(id::LIFE_STEAL_ON_HIT, 0, 5), s, i, modifier));
                all.append(cost(passive(id::ENERGY_REGEN, 0, -1), s, i, modifier));
            } else if s == Source::SetBonus {
                all.append(held(passive(id::HEALTH_REGEN, 0, 1), s, i, modifier));
            } else {
                all.append(held(passive(id::ARMOR_VS, damage::FIRE, 7), s, i, modifier));
                all.append(cost(passive(id::ARMOR_VS, damage::COLD, 7), s, i, modifier));
            }
            i += 1;
        }
        let snapshot = flatten(@loadout(3, 20), all.span());
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
    #[available_gas(l2_gas: 3694067)] // ceil(1.05 × 3518159 measured)
    fn test_lanes_against_the_oracle() {
        let all = array![
            held(
                scoped(id::DAMAGE_PERCENT, guard::ABOVE_HALF, scope::WEAPON, -18),
                Source::Prefix,
                0,
                1,
            ),
            cost(scoped(id::PENETRATION, guard::ALWAYS, scope::WEAPON, 36), Source::Prefix, 0, 1),
            held(
                scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ATTACK_SKILL, 18),
                Source::Suffix,
                1,
                2,
            ),
            cost(passive(id::MAX_ENERGY, 0, -5), Source::Suffix, 1, 2),
            held(
                scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::SPELL, -18), Source::Suffix, 2, 3,
            ),
            cost(passive(id::HEALTH_REGEN, 0, -1), Source::Suffix, 2, 3),
            held(
                scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, 18),
                Source::Inscription,
                3,
                4,
            ),
            cost(
                scoped(id::PENETRATION, guard::ALWAYS, scope::SPELL, 36), Source::Inscription, 3, 4,
            ),
            held(
                scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, -18),
                Source::Inscription,
                4,
                5,
            ),
            cost(passive(id::ENERGY_REGEN, 0, -1), Source::Inscription, 4, 5),
            held(
                PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, 18, 18),
                Source::Insignia,
                5,
                6,
            ),
            cost(
                PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, -18, -18),
                Source::Insignia,
                5,
                6,
            ),
            held(
                PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, -255),
                Source::Insignia,
                6,
                7,
            ),
            cost(passive(id::ENCHANT_DURATION, 0, 20), Source::Insignia, 6, 7),
            held(passive(id::ARMOR_VS, damage::SLASHING, 7), Source::Rune, 10, 8),
            cost(
                PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, -255), Source::Rune, 10, 8,
            ),
            held(passive(id::ARMOR_VS, damage::HOLY, 7), Source::Rune, 11, 9),
            cost(passive(id::MAX_HEALTH, 0, -75), Source::Rune, 11, 9),
            held(
                scoped(id::DAMAGE_PERCENT, guard::ABOVE_HALF, scope::SPELL, 18),
                Source::SetBonus,
                15,
                0,
            ),
            held(
                PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, 18, 18),
                Source::SetBonus,
                16,
                0,
            ),
        ];
        let snapshot = flatten(@loadout(1, 20), all.span());
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
    #[available_gas(l2_gas: 575110)] // ceil(1.05 × 547723 measured)
    fn test_floor_max_health_refused() {
        // Runes: +5 armor and −75 health; set bonuses −75: 100 − 375 − 150.
        let mut all = array![];
        let mut i: u8 = 10;
        while i < 15 {
            all.append(held(passive(id::ARMOR, 0, 5), Source::Rune, i, 400));
            all.append(cost(passive(id::MAX_HEALTH, 0, -75), Source::Rune, i, 400));
            i += 1;
        }
        all.append(held(passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 15, 0));
        all.append(held(passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 16, 0));
        SnapshotBuildTrait::build(@loadout(1, 1), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: max energy below 0')]
    #[available_gas(l2_gas: 780616)] // ceil(1.05 × 743443 measured)
    fn test_floor_max_energy_refused() {
        // A Vanguard's 20, five held slots and two set bonuses at −5: −15.
        let all = everywhere(
            passive(id::MAX_ENERGY, 0, -5),
            array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
        );
        SnapshotBuildTrait::build(@loadout(1, 1), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: energy regen below 0')]
    #[available_gas(l2_gas: 780616)] // ceil(1.05 × 743443 measured)
    fn test_floor_energy_regen_refused() {
        // A Vanguard's 2 pips, five held slots and two set bonuses at −1: −5.
        let all = everywhere(
            passive(id::ENERGY_REGEN, 0, -1),
            array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
        );
        SnapshotBuildTrait::build(@loadout(1, 1), all.span());
    }

    // §6 test 4 (DS-5): enchantment 340 → 50 (17 sources at 20), knock-down 4 → 3, armor
    // against a type 149 → 63 (a Warden's +30 elemental and 17 sources at 7). Condition duration
    // 65,534 → 50: `test_same_condition_capped`, below.
    #[test]
    #[available_gas(l2_gas: 11256097)] // ceil(1.05 × 10720092 measured)
    fn test_saturation() {
        let all = everywhere(passive(id::ENCHANT_DURATION, 0, 20), sources());
        let snapshot = flatten(@loadout(2, 20), all.span());
        assert(snapshot.kit.enchantment_duration == 50, 'enchantment 340 -> 50');
        let all = everywhere(
            passive(id::KNOCKDOWN_FLAT, 0, 1), array![Source::Suffix, Source::Inscription].span(),
        );
        let snapshot = flatten(@loadout(2, 20), all.span());
        assert(snapshot.kit.knockdown == 3, 'knock-down 4 -> 3');
        let all = everywhere(passive(id::ARMOR_VS, damage::FIRE, 7), sources());
        let snapshot = flatten(@loadout(2, 20), all.span());
        let [_, _, _, fire, _, _, _, _, _] = snapshot.stats.armor_vs;
        assert(fire == 63, 'armor vs 149 -> 63');
        // A prefix's condition duration, benefit and cost of one condition, summed: 20 + 13,
        // the prefix's bound 33 (DS-5); one prefix, so no legal build reaches the saturation.
        let all = array![
            held(passive(id::CONDITION_DURATION, condition::POISON, 20), Source::Prefix, 0, 1),
            cost(passive(id::CONDITION_DURATION, condition::POISON, 13), Source::Prefix, 0, 1),
        ];
        let snapshot = flatten(@loadout(2, 20), all.span());
        assert(snapshot.kit.condition == condition::POISON, 'condition');
        assert(snapshot.kit.condition_duration == 33, 'condition 20 + 13');
    }

    // §6 test 5 (FX-43, D-157 D): two health runes of one modifier id count once; of two ids,
    // both.
    #[test]
    #[available_gas(l2_gas: 2289973)] // ceil(1.05 × 2180926 measured)
    fn test_rune_identity() {
        let rune = passive(id::MAX_HEALTH, 0, 50);
        let same = array![held(rune, Source::Rune, 10, 7), held(rune, Source::Rune, 11, 7)];
        let snapshot = flatten(@loadout(1, 20), same.span());
        assert(snapshot.stats.max_health == 480 + 50, 'one id: once');
        let two = array![held(rune, Source::Rune, 10, 7), held(rune, Source::Rune, 11, 8)];
        let snapshot = flatten(@loadout(1, 20), two.span());
        assert(snapshot.stats.max_health == 480 + 100, 'two ids: both');
    }

    // AUD-182-2: three runes of one modifier id (+50 health, −75 health): the benefit counts
    // once, every cost counts (FX-43): 480 + 50 − 225.
    #[test]
    #[available_gas(l2_gas: 1811768)] // ceil(1.05 × 1725493 measured)
    fn test_repeated_rune_id() {
        let benefit = passive(id::MAX_HEALTH, 0, 50);
        let price = passive(id::MAX_HEALTH, 0, -75);
        let mut all = array![];
        let mut i: u8 = 10;
        while i < 13 {
            all.append(held(benefit, Source::Rune, i, 9));
            all.append(cost(price, Source::Rune, i, 9));
            i += 1;
        }
        let snapshot = flatten(@loadout(1, 20), all.span());
        assert(snapshot.stats.max_health == 480 + 50 - 225, 'benefit once, costs all');
    }

    // AUD-182-3: a rune's contribution to an attribute is its passives' sum: +1 and +2 on one
    // rune give 3, so 12 points reach 15.
    #[test]
    #[available_gas(l2_gas: 1380554)] // ceil(1.05 × 1314813 measured)
    fn test_rune_attribute_contribution() {
        let all = array![
            held(passive(id::ATTRIBUTE, PRIMARY, 1), Source::Rune, 10, 7),
            cost(passive(id::ATTRIBUTE, PRIMARY, 2), Source::Rune, 10, 7),
            held(passive(id::ATTRIBUTE, PRIMARY, 2), Source::Rune, 11, 8),
        ];
        let snapshot = flatten(@loadout(3, 20), all.span());
        assert(snapshot.stats.primary_rank == 15, '12 + (1 + 2)');
    }

    // The counts of design/20 §1.2 at their bounds, the 17 sources: accepted; one more of a
    // source: refused.
    #[test]
    #[available_gas(l2_gas: 4288492)] // ceil(1.05 × 4084278 measured)
    fn test_counts_at_bounds() {
        let all = everywhere(passive(id::ARMOR, 0, 1), sources());
        let snapshot = flatten(@loadout(1, 20), all.span());
        assert(snapshot.bar.armor == 17, '17 sources');
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 278107)] // ceil(1.05 × 264863 measured)
    fn test_sixth_rune_refused() {
        let mut all = array![];
        let mut i: u8 = 0;
        while i < 6 {
            all.append(held(passive(id::ARMOR, 0, 5), Source::Rune, i, 1));
            i += 1;
        }
        SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 194201)] // ceil(1.05 × 184953 measured)
    fn test_second_prefix_refused() {
        let all = array![
            held(passive(id::ARMOR, 0, 5), Source::Prefix, 0, 1),
            held(passive(id::ARMOR, 0, 5), Source::Prefix, 5, 1),
        ];
        SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    }

    #[test]
    #[should_panic(expected: 'build: too many of a source')]
    #[available_gas(l2_gas: 211736)] // ceil(1.05 × 201653 measured)
    fn test_third_set_bonus_refused() {
        let all = array![
            held(passive(id::ARMOR, 0, 5), Source::SetBonus, 15, 0),
            held(passive(id::ARMOR, 0, 5), Source::SetBonus, 16, 0),
            held(passive(id::ARMOR, 0, 5), Source::SetBonus, 17, 0),
        ];
        SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    }

    // Instances are numbered upward, so that none is counted twice: a passive of an earlier
    // instance after a later one is refused.
    #[test]
    #[should_panic(expected: 'build: instances out of order')]
    #[available_gas(l2_gas: 197228)] // ceil(1.05 × 187836 measured)
    fn test_instances_out_of_order_refused() {
        let all = array![
            held(passive(id::ARMOR, 0, 5), Source::Rune, 11, 1),
            held(passive(id::ARMOR, 0, 5), Source::Rune, 10, 1),
        ];
        SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    }

    // DS-23: one insignia a piece.
    #[test]
    #[should_panic(expected: 'build: two insignias a piece')]
    #[available_gas(l2_gas: 199625)] // ceil(1.05 × 190119 measured)
    fn test_two_insignias_on_a_piece_refused() {
        let mut first = held(passive(id::MAX_HEALTH, 0, 5), Source::Insignia, 5, 200);
        let mut second = held(passive(id::MAX_HEALTH, 0, 5), Source::Insignia, 6, 200);
        first.piece = base_slot::HEAD;
        second.piece = base_slot::HEAD;
        SnapshotBuildTrait::build(@loadout(1, 20), array![first, second].span());
    }

    // A quick-cast pair names an attribute of the build (D-157 A): its index; one the build does
    // not hold is refused.
    #[test]
    #[available_gas(l2_gas: 1122286)] // ceil(1.05 × 1068843 measured)
    fn test_quick_cast_pairs() {
        let all = array![
            held(passive(id::QUICK_CAST_EVERY_N, OTHER, 4), Source::Inscription, 3, 1),
            held(passive(id::QUICK_CAST_EVERY_N, PRIMARY, 9), Source::Inscription, 4, 2),
        ];
        let snapshot = flatten(@loadout(1, 20), all.span());
        let [first, second] = snapshot.bar.quick_cast;
        assert(first == QuickCast { attribute: 1, every: 4 }, 'other: index 1');
        assert(second == QuickCast { attribute: 0, every: 9 }, 'primary: index 0');
    }

    #[test]
    #[should_panic(expected: 'build: quick-cast attribute')]
    #[available_gas(l2_gas: 194327)] // ceil(1.05 × 185073 measured)
    fn test_quick_cast_attribute_not_held_refused() {
        let all = array![held(passive(id::QUICK_CAST_EVERY_N, 99, 4), Source::Inscription, 3, 1)];
        SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    }

    // The passives that are not summed: the lowest N, the damage type, halving.
    #[test]
    #[available_gas(l2_gas: 1383515)] // ceil(1.05 × 1317633 measured)
    fn test_passives_not_summed() {
        let all = array![
            held(passive(id::DAMAGE_TYPE, damage::FIRE, 0), Source::Prefix, 0, 1),
            cost(passive(id::ADRENALINE_EVERY_N, 0, 9), Source::Prefix, 0, 1),
            held(passive(id::ADRENALINE_EVERY_N, 0, 5), Source::Suffix, 1, 2),
            held(passive(id::HALVE_FIRST_HEAVY_HIT, 0, 0), Source::Rune, 10, 3),
        ];
        let snapshot = flatten(@loadout(1, 20), all.span());
        assert(snapshot.stats.damage_type == damage::FIRE, 'damage type');
        assert(snapshot.kit.double_adrenaline_every == 5, 'the lowest N');
        assert(snapshot.kit.halving, 'halving');
    }

    // DS-29: `pack_stats` accepts a health regeneration of 20 and refuses 21.
    #[test]
    #[available_gas(l2_gas: 113117)] // ceil(1.05 × 107730 measured)
    fn test_stats_health_regen_20_packs() {
        pack_stats(MemberStats { health_regen: 20, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: health regen')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_stats_health_regen_21_refused() {
        pack_stats(MemberStats { health_regen: 21, ..Default::default() });
    }

    #[test]
    // gas: raised, CBT-01: nine armors by damage type (FX-23, FX-24)
    #[available_gas(l2_gas: 581606)] // ceil(1.05 × 553910 measured)
    fn test_stats_layout() {
        let stats = MemberStats {
            max_health: 0xFFFF,
            max_energy: 1,
            energy_regen: 2,
            health_regen: 3,
            armor_vs: [63, 1, 2, 3, 4, 5, 6, 7, 63],
            level: 7,
            profession: 8,
            primary_rank: 9,
            weapon: 10,
            weapon_damage: 11,
            weapon_ticks: 12,
            weapon_range: 13,
            weapon_strength: 0xFF,
            ranks: 0xFFFFFFFF,
            damage_type: 14,
            requirement_met: 1,
            set_bonuses: 0xFFFF,
        };
        assert(unpack_stats(pack_stats(stats)) == stats, 'round trip');
        let level = MemberStats { level: 1, ..Default::default() };
        assert(pack_stats(level) == 0x10000000000000000 + LIVE, 'level at bit 64');
        let ranks = MemberStats { ranks: 1, ..Default::default() };
        assert(pack_stats(ranks) == TWO_128 + LIVE, 'ranks at bit 128');
        // design/19 §7.2: `ARMOR_VS` types 1–2 at bits 48, 54; types 3–9 at 200 + 6 (type −
        // 3).
        let vs = MemberStats { armor_vs: [1, 1, 0, 0, 0, 0, 0, 0, 0], ..Default::default() };
        assert(pack_stats(vs) == 0x1000000000000 + 0x40000000000000 + LIVE, 'vs 1-2 at 48, 54');
        let vs = MemberStats { armor_vs: [0, 0, 1, 0, 0, 0, 0, 0, 1], ..Default::default() };
        let at200 = 0x100000000000000000000000000000000000000000000000000;
        let at236 = 0x100000000000000000000000000000000000000000000000000000000000;
        assert(pack_stats(vs) == at200 + at236 + LIVE, 'vs 3 at 200, 9 at 236');
    }

    #[test]
    // gas: raised, CBT-01: design/19's passives in the bar and the kit (FX-24)
    #[available_gas(l2_gas: 398213)] // ceil(1.05 × 379250 measured)
    fn test_bar_and_kit_layout() {
        let bar = MemberBar {
            skills: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], elite_slot: 255, ..Fixture::empty_bar(),
        };
        assert(unpack_bar(pack_bar(bar)) == bar, 'bar round trip');
        let bar = MemberBar {
            skills: [0, 0, 0, 0, 0, 0, 0, 1], elite_slot: 0, ..Fixture::empty_bar(),
        };
        assert(pack_bar(bar) == 0x10000000000000000000000000000 + LIVE, 'skill 7 at bit 112');
        let kit = MemberKit {
            belt: [1, 2, 3, 0xFFFFFFFF],
            life_steal: 3,
            energy_on_hit: 4,
            condition: 15,
            condition_duration: 63,
            enchantment_duration: 63,
            double_adrenaline_every: 0xFF,
            health_bonus: 0xFFFF,
            armor_stance: -128,
            armor_enchanted: 127,
            knockdown: 3,
            halving: true,
        };
        assert(unpack_kit(pack_kit(kit)) == kit, 'kit round trip');
        let kit = MemberKit { health_bonus: 1, ..Default::default() };
        assert(pack_kit(kit) == 0x10000000000 * TWO_128 + LIVE, 'health bonus at bit 168');
    }

    #[test]
    #[available_gas(l2_gas: 148985)] // ceil(1.05 × 141890 measured)
    fn test_task_page_layout() {
        let full = TaskEntry { task: 0xFFFFFFFF, kind: 0xFF, param: 0xFFFF };
        let page = TaskPage {
            entries: [full, TaskEntry { task: 1, kind: 2, param: 3 }, full, full],
        };
        assert(unpack_task_page(pack_task_page(page)) == page, 'round trip');
        let second = TaskPage {
            entries: [
                Default::default(), TaskEntry { task: 1, kind: 0, param: 0 }, Default::default(),
                TaskEntry { task: 0, kind: 1, param: 0 },
            ],
        };
        // Entry 1 at bit 56; entry 3 at bit 184, its kind at bit 216.
        let expected = 0x100000000000000 + 0x100000000 * 0x100000000000000 * TWO_128 + LIVE;
        assert(pack_task_page(second) == expected, 'offsets');
    }

    #[generate_trait]
    impl FixtureImpl of Fixture {
        /// A bar with no skill and every passive sum 0, the unguarded armor 0.
        fn empty_bar() -> MemberBar {
            MemberBar {
                skills: [0; 8],
                elite_slot: 0,
                damage: [0; 6],
                penetration: [0; 3],
                quick_cast: [Default::default(); 2],
                armor: 0,
            }
        }
    }

    // design/19 §7.2 (FX-24): the bar's high limb holds the elite slot 128, the damage sums
    // 136–183 (signed), the penetration sums 184–207, the quick-cast pairs 208–231 and the
    // unguarded armor 232–247 (signed); each round-trips at both ends and sits at its bit.
    #[test]
    #[available_gas(l2_gas: 838415)] // ceil(1.05 × 798490 measured)
    fn test_bar_passives_layout() {
        let top = MemberBar {
            skills: [0xFFFF; 8],
            elite_slot: 255,
            damage: [127, -128, 126, -126, 1, -1],
            penetration: [255, 0, 252],
            quick_cast: [
                QuickCast { attribute: 15, every: 255 }, QuickCast { attribute: 1, every: 5 },
            ],
            armor: -MAX_UNGUARDED_ARMOR,
        };
        assert(unpack_bar(pack_bar(top)) == top, 'top round trip');
        let top = MemberBar { armor: MAX_UNGUARDED_ARMOR, ..top };
        assert(unpack_bar(pack_bar(top)) == top, 'armor max round trip');
        let bit = |bar: MemberBar| -> felt252 {
            pack_bar(bar) - LIVE
        };
        let empty = Fixture::empty_bar();
        let two_136: felt252 = TWO_128 * 0x100;
        assert(bit(MemberBar { damage: [1, 0, 0, 0, 0, 0], ..empty }) == two_136, 'damage at 136');
        assert(
            bit(MemberBar { damage: [-1, 0, 0, 0, 0, 0], ..empty }) == two_136 * 0xFF,
            'signed damage',
        );
        let two_184: felt252 = TWO_128 * 0x100000000000000;
        assert(bit(MemberBar { penetration: [1, 0, 0], ..empty }) == two_184, 'penetration at 184');
        let two_208: felt252 = TWO_128 * 0x100000000000000000000;
        let one = QuickCast { attribute: 1, every: 0 };
        assert(
            bit(MemberBar { quick_cast: [one, Default::default()], ..empty }) == two_208,
            'qc at 208',
        );
        let two_232: felt252 = TWO_128 * 0x100000000000000000000000000;
        assert(bit(MemberBar { armor: 1, ..empty }) == two_232, 'armor at 232');
        assert(bit(MemberBar { armor: -1, ..empty }) == two_232 * 0xFFFF, 'armor signed');
    }

    // F-21: the unguarded armor is bounded by 9,995 either way; a wider value is refused.
    #[test]
    #[should_panic(expected: 'snapshot: armor above bound')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_bar_armor_above_bound_refused() {
        pack_bar(MemberBar { armor: MAX_UNGUARDED_ARMOR + 1, ..Fixture::empty_bar() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: armor above bound')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_bar_armor_below_bound_refused() {
        pack_bar(MemberBar { armor: -MAX_UNGUARDED_ARMOR - 1, ..Fixture::empty_bar() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: quick-cast attribute')]
    #[available_gas(l2_gas: 85271)] // ceil(1.05 × 81210 measured)
    fn test_bar_quick_cast_attribute_refused() {
        let wide = QuickCast { attribute: 16, every: 1 };
        pack_bar(MemberBar { quick_cast: [Default::default(), wide], ..Fixture::empty_bar() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: armor vs above 63')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_stats_armor_vs_refused() {
        pack_stats(MemberStats { armor_vs: [0, 0, 0, 0, 0, 0, 0, 0, 64], ..Default::default() });
    }

    // The kit's high limb (design/19 §7.2): 75 bits, each field at its bit; the narrow ones
    // refused when wider.
    #[test]
    #[available_gas(l2_gas: 646905)] // ceil(1.05 × 616100 measured)
    fn test_kit_passives_layout() {
        let bit = |kit: MemberKit| -> felt252 {
            pack_kit(kit) - LIVE
        };
        let k = MemberKit { ..Default::default() };
        assert(bit(MemberKit { life_steal: 1, ..k }) == TWO_128, 'life steal at 128');
        assert(bit(MemberKit { energy_on_hit: 1, ..k }) == TWO_128 * 0x100, 'energy at 136');
        assert(bit(MemberKit { condition: 1, ..k }) == TWO_128 * 0x10000, 'condition at 144');
        assert(
            bit(MemberKit { condition_duration: 1, ..k }) == TWO_128 * 0x100000, 'cond % at 148',
        );
        assert(
            bit(MemberKit { enchantment_duration: 1, ..k }) == TWO_128 * 0x4000000, 'ench at 154',
        );
        assert(
            bit(MemberKit { double_adrenaline_every: 1, ..k }) == TWO_128 * 0x100000000, 'N at 160',
        );
        assert(
            bit(MemberKit { armor_stance: 1, ..k }) == TWO_128 * 0x100000000000000, 'stance 184',
        );
        assert(bit(MemberKit { armor_stance: -1, ..k }) == TWO_128 * 0xFF00000000000000, 'signed');
        assert(
            bit(MemberKit { armor_enchanted: 1, ..k }) == TWO_128 * 0x10000000000000000, 'ench 192',
        );
        assert(
            bit(MemberKit { knockdown: 1, ..k }) == TWO_128 * 0x1000000000000000000, 'kd at 200',
        );
        assert(
            bit(MemberKit { halving: true, ..k }) == TWO_128 * 0x4000000000000000000, 'halving 202',
        );
        let top = MemberKit {
            belt: [0xFFFFFFFF; 4],
            life_steal: 0xFF,
            energy_on_hit: 0xFF,
            condition: 15,
            condition_duration: 63,
            enchantment_duration: 63,
            double_adrenaline_every: 0xFF,
            health_bonus: 0xFFFF,
            armor_stance: 127,
            armor_enchanted: -128,
            knockdown: 3,
            halving: true,
        };
        let word = pack_kit(top);
        assert(unpack_kit(word) == top, 'top round trip');
        // 75 bits: the high limb's highest set bit is 202.
        let wide: u256 = word.into();
        assert(wide.high - 0x4000000000000000000000000000000 < 0x8000000000000000000, 'within 75');
    }

    #[test]
    #[should_panic(expected: 'snapshot: knock-down above 3')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_kit_knockdown_refused() {
        pack_kit(MemberKit { knockdown: 4, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: percent above 63')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_kit_percent_refused() {
        pack_kit(MemberKit { enchantment_duration: 64, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: condition')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_kit_condition_refused() {
        pack_kit(MemberKit { condition: 16, ..Default::default() });
    }

    // ---- the flattening's cost (docs/CAIRO.md §2: a benchmark on the worst case)
    // ----------------

    /// The widest build design/20 §1.2 counts, each passive on one of the flattening's costliest
    /// paths: 17 sources, 32 passives. The held slots: a damage percent on all hits (two-level
    /// lanes) and an energy regeneration cost (the table's path); the insignias: an enchantment
    /// duration (the table) and a guarded armor cost; the runes: five health runes of distinct
    /// ids (their identity pass, 25 comparisons) and an attribute cost (each rank a pass over
    /// them); the set bonuses: a knock-down, the table's last entry. The loadout's eight bar
    /// skills and its weapon name the rune's attribute.
    fn widest() -> (Loadout, Array<HeldPassive>) {
        let mut all = array![];
        let mut i: u8 = 0;
        for source in sources() {
            let s = *source;
            let modifier: u32 = 100 + i.into();
            if s == Source::Prefix || s == Source::Suffix || s == Source::Inscription {
                all
                    .append(
                        held(
                            scoped(id::DAMAGE_PERCENT, guard::ALWAYS, scope::ALL, 1),
                            s,
                            i,
                            modifier,
                        ),
                    );
                all.append(cost(passive(id::ENERGY_REGEN, 0, 0), s, i, modifier));
            } else if s == Source::Insignia {
                all.append(held(passive(id::ENCHANT_DURATION, 0, 1), s, i, modifier));
                all
                    .append(
                        cost(
                            PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, 1, 1),
                            s,
                            i,
                            modifier,
                        ),
                    );
            } else if s == Source::Rune {
                all.append(held(passive(id::MAX_HEALTH, 0, 1), s, i, modifier));
                all.append(cost(passive(id::ATTRIBUTE, OTHER, 1), s, i, modifier));
            } else {
                all.append(held(passive(id::KNOCKDOWN_FLAT, 0, 1), s, i, modifier));
            }
            i += 1;
        }
        let build = Loadout { bar_attributes: [OTHER; 8], ..loadout(3, 20) };
        (build, all)
    }

    // The baseline of the two below: the widest build's inputs, not flattened.
    #[test]
    #[available_gas(l2_gas: 302579)] // ceil(1.05 × 288170 measured)
    fn test_cost_build_baseline() {
        let (build, all) = widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
    }

    // The flattening of the widest build (D-166): this test less the baseline.
    #[test]
    #[available_gas(l2_gas: 2011441)] // ceil(1.05 × 1915658 measured)
    fn test_cost_build_widest() {
        let (build, all) = widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
        let snapshot = SnapshotBuildTrait::build(@build, all.span());
        assert(snapshot.stats.max_health == 480 + 5, 'five runes');
    }

    // CBT-02's flattening of the same build, for the comparison (its checks not included).
    #[test]
    #[available_gas(l2_gas: 11524223)] // ceil(1.05 × 10975450 measured)
    fn test_cost_oracle_widest() {
        let (build, all) = widest();
        assert(all.len() == 32 && build.level == 20, 'the widest build');
        let snapshot = oracle(@build, all.span());
        assert(snapshot.stats.max_health == 480 + 5, 'five runes');
    }

    // The same build flattened and compared with the oracle.
    #[test]
    #[available_gas(l2_gas: 13301325)] // ceil(1.05 × 12667928 measured)
    fn test_widest_against_the_oracle() {
        let (build, all) = widest();
        let snapshot = flatten(@build, all.span());
        assert(snapshot.stats.ranks == 0xbbbbbbbb, 'eight ranks of 10 + 1');
        assert(snapshot.kit.knockdown == 2 && snapshot.kit.enchantment_duration == 5, 'kit');
    }

    // The fixed part of the flattening: a build that holds no passive, and CBT-02's on the same.
    #[test]
    #[available_gas(l2_gas: 403645)] // ceil(1.05 × 384423 measured)
    fn test_cost_build_empty() {
        let snapshot = SnapshotBuildTrait::build(@loadout(3, 20), array![].span());
        assert(snapshot.stats.max_health == 480, 'no passive');
    }

    #[test]
    #[available_gas(l2_gas: 267509)] // ceil(1.05 × 254770 measured)
    fn test_cost_oracle_empty() {
        let snapshot = oracle(@loadout(3, 20), array![].span());
        assert(snapshot.stats.max_health == 480, 'no passive');
    }

    // CBT-9, DS-5 (design/20 §6 test 4): `MemberKitTrait::condition_duration` sums wide, then
    // saturates at 50: envelope A's 65,534 gives 50 (the builder's sum, without the validators
    // that now forbid it). Moved from `test_capacity` (D-167, CBT-02c fix loop 1).
    #[test]
    #[available_gas(l2_gas: 40961)] // ceil(1.05 × 39010 measured)
    fn test_same_condition_capped() {
        let wide = passive(id::CONDITION_DURATION, condition::POISON, 32767);
        assert(
            MemberKitTrait::condition_duration(
                array![wide, wide].span(),
            ) == (condition::POISON, 50),
            '65,534 saturated',
        );
        // None held: no condition.
        assert(MemberKitTrait::condition_duration(array![].span()) == (0, 0), 'none');
    }

    // CBT-9: two conditions are still refused, by the builder as by the validators.
    #[test]
    #[should_panic(expected: 'snapshot: two conditions')]
    #[available_gas(l2_gas: 31143)] // ceil(1.05 × 29660 measured)
    fn test_two_conditions_builder_refused() {
        MemberKitTrait::condition_duration(
            array![
                passive(id::CONDITION_DURATION, condition::BLEEDING, 33),
                passive(id::CONDITION_DURATION, condition::POISON, 10),
            ]
                .span(),
        );
    }
}
