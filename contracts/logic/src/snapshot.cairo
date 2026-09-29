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
use crate::packing::{
    P104, P108, P112, P12, P120, P16, P20, P24, P32, P40, P48, P56, P64, P72, P8, P80, P84, P88,
    P96, join, low_field, split,
};
use crate::professions::ProfessionTrait;
use crate::types::combat::damage;
use crate::types::effect::guard;
use crate::types::passive::{
    HIT_ATTACK_SKILL, HIT_SPELL, HIT_WEAPON, Passive, PassiveAssert, PassiveTrait, Source, id,
};

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
        let mut condition: u8 = 0;
        let mut percent: u32 = 0;
        for passive in held {
            if *passive.id == id::CONDITION_DURATION {
                assert(condition == 0 || condition == *passive.param, errors::CONDITIONS);
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
// passives it holds into the snapshot's three words, every restriction of design/20's capacity
// proof checked first. Built before any production snapshot (D-160); `set_build` and `enter` wire
// it (persistent package: escalated in CBT-02's report).

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
/// DS-7 (D-160) bounds *Wellspring* at 3 energy a rank and light armor at +20 energy and +1 pip.
/// BAL-01 sets the values; until then the bounds are used, as `ADRENALINE_DECAY` is (escalated).
pub const WELLSPRING_ENERGY_PER_RANK: i32 = 3;
pub const LIGHT_ENERGY: i32 = 20;
pub const LIGHT_ENERGY_REGEN: i32 = 1;
/// design/15's armor classes' innate armor: heavy +20 against physical damage (types 1–3), medium
/// +30 against elemental (4–7); light gives energy (above).
pub const HEAVY_VS_PHYSICAL: u32 = 20;
pub const MEDIUM_VS_ELEMENTAL: u32 = 30;

pub mod build_errors {
    pub const SOURCE_COUNT: felt252 = 'build: too many of a source';
    pub const INSTANCE: felt252 = 'build: one source, one kind';
    pub const INSTANCE_SIZE: felt252 = 'build: passives of a source';
    pub const TWICE: felt252 = 'build: counted twice';
    pub const MAX_HEALTH: felt252 = 'build: max health below 1';
    pub const MAX_ENERGY: felt252 = 'build: max energy below 0';
    pub const ENERGY_REGEN: felt252 = 'build: energy regen below 0';
    pub const RANK: felt252 = 'build: rank above 15';
    pub const RATING: felt252 = 'build: rating above 560';
    pub const QUICK_CAST: felt252 = 'build: quick-cast attribute';
    pub const DAMAGE_TYPE: felt252 = 'build: two damage types';
    pub const OVERFLOW: felt252 = 'build: sum outside its field';
}

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

/// The most instances of each source an adventurer holds (design/20 §1.2): a prefix, 2 suffixes,
/// 2 inscriptions, 5 insignias, 5 runes, 2 set bonuses. A free function: a table.
fn max_instances(source: Source) -> u8 {
    match source {
        Source::Prefix => 1,
        Source::Suffix => 2,
        Source::Inscription => 2,
        Source::Insignia => 5,
        Source::Rune => 5,
        Source::SetBonus => 2,
    }
}

#[generate_trait]
pub impl BuildAssert of BuildAssertTrait {
    /// The flattening's checks of the whole build (DS-1, D-160): each passive legal on its
    /// source; each instance one source of one kind, of at most 2 passives (a set bonus 1),
    /// within the contributions and per-source bounds and naming nothing twice; at most §1.2's
    /// count of each source. The sums §1 proves then fit their fields.
    fn assert_sources(held: Span<HeldPassive>) {
        let mut counts: Array<(Source, u8)> = array![];
        let mut i = 0;
        for current in held {
            current.passive.assert_source(*current.source);
            // The first passive of its instance checks the instance.
            let mut first = true;
            let mut j = 0;
            while j < i {
                if *held[j].instance == *current.instance {
                    first = false;
                    break;
                }
                j += 1;
            }
            if first {
                let mut passives: Array<Passive> = array![];
                for other in held {
                    if *other.instance == *current.instance {
                        assert(*other.source == *current.source, build_errors::INSTANCE);
                        passives.append(*other.passive);
                    }
                }
                let size = if *current.source == Source::SetBonus {
                    1
                } else {
                    2
                };
                assert(passives.len() <= size, build_errors::INSTANCE_SIZE);
                let passives = passives.span();
                if passives.len() == 2 {
                    assert(!passives[0].conflicts(passives[1]), build_errors::TWICE);
                }
                PassiveAssert::assert_contributions(passives);
                PassiveAssert::assert_source_bounds(passives, *current.source);
                counts.append((*current.source, 1));
            }
            i += 1;
        }
        let counts = counts.span();
        for source in array![
            Source::Prefix, Source::Suffix, Source::Inscription, Source::Insignia, Source::Rune,
            Source::SetBonus,
        ] {
            let mut n: u8 = 0;
            for (kind, one) in counts {
                if *kind == source {
                    n += *one;
                }
            }
            assert(n <= max_instances(source), build_errors::SOURCE_COUNT);
        }
    }
}

#[generate_trait]
impl HeldSums of HeldSumsTrait {
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

    /// The rank of `attribute` (0: none): the build's points plus the highest `ATTRIBUTE` rune for
    /// it (design/15; runes only, DS-4), at most 15 (DS-8).
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
        let mut rune: i16 = 0;
        for h in held {
            if *h.passive.id == id::ATTRIBUTE
                && *h.passive.param == attribute
                && *h.passive.max > rune {
                rune = *h.passive.max;
            }
        }
        let rank: u16 = rank.into() + rune.try_into().unwrap();
        assert(rank <= MAX_RANK.into(), build_errors::RANK);
        rank.try_into().unwrap()
    }
}

/// An `i32` sum into its field, or refused: design/20 §1 proves each fits once `BuildAssert`
/// passed, so a failure here is a broken proof, never a legal build.
fn fit<T, +TryInto<i32, T>>(value: i32) -> T {
    value.try_into().expect(build_errors::OVERFLOW)
}

#[generate_trait]
pub impl SnapshotBuildImpl of SnapshotBuildTrait {
    /// The production snapshot of a build and the passives it holds (design/19 §4, §7.2;
    /// design/20 §1.3, D-160): the checks of `BuildAssert` first, then the sums, each into its
    /// field.
    /// - Max health: `100 + 20 (L − 1)` + equipment (rune identity), refused below 1 (DS-2); the
    ///   final maximum is `max_health`, `MemberKit.health_bonus` is freed and 0 (DS-3).
    /// - Max energy: the profession's + *Wellspring* (3 a primary rank, the Arcanist's) + light
    ///   armor's 20 + equipment, refused below 0 (DS-2, DS-7). Energy regeneration: the
    ///   profession's + light armor's 1 + equipment, refused below 0 (DS-2).
    /// - Health regeneration: 10 + equipment, 0–20 (DS-29, checked at pack).
    /// - Armor against each type: the class's innate + equipment, summed wide, saturated at 63.
    /// - Ranks: points + the highest rune, ≤ 15 (DS-4, DS-8); the primary's and each bar skill's.
    /// - Weapon damage: personalised +20 % (DS-4); strength `min(5 × rank, cap)` (DS-9).
    /// - The duration percents saturated at 50, the knock-down at 3, after wide summation (DS-5).
    /// - The rest as design/19 §7.2 flattens it: damage and penetration sums per guard and class,
    ///   guarded and unguarded armor, quick-cast pairs, the lowest N, life steal, energy on hit.
    fn build(loadout: @Loadout, held: Span<HeldPassive>) -> Snapshot {
        BuildAssert::assert_sources(held);
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
        let primary_rank = HeldSums::rank(*loadout.points, held, primary);

        // Maxima and regeneration, signed, with DS-2's floors.
        let health = 100 + 20 * (level - 1) + HeldSums::health(held);
        assert(health >= 1, build_errors::MAX_HEALTH);
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
            + HeldSums::total(held, id::MAX_ENERGY);
        assert(energy >= 0, build_errors::MAX_ENERGY);
        let base_regen: i32 = ProfessionTrait::energy_regen(profession).into();
        let light_regen = if light {
            LIGHT_ENERGY_REGEN
        } else {
            0
        };
        let energy_regen = base_regen + light_regen + HeldSums::total(held, id::ENERGY_REGEN);
        assert(energy_regen >= 0, build_errors::ENERGY_REGEN);
        let health_regen = 10 + HeldSums::total(held, id::HEALTH_REGEN);

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
            let sum: u32 = innate + fit(HeldSums::total_param(held, id::ARMOR_VS, t));
            armor_vs.append(saturate(sum, MAX_ARMOR_VS).try_into().unwrap());
        }

        // Ranks of the bar's attributes, 4 bits each.
        let mut ranks: u64 = 0;
        let mut shift: u64 = 1;
        for attribute in loadout.bar_attributes.span() {
            ranks += HeldSums::rank(*loadout.points, held, *attribute).into() * shift;
            shift *= 16;
        }
        let ranks: u32 = ranks.try_into().unwrap();

        // The weapon (DS-4, DS-9).
        let mut weapon_damage: u32 = (*loadout.weapon_damage).into();
        if *loadout.personalised {
            weapon_damage = weapon_damage * PERSONALISED_DAMAGE_PERCENT / 100;
        }
        let strength: u16 = STRENGTH_PER_RANK
            * HeldSums::rank(*loadout.points, held, *loadout.weapon_attribute).into();
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
                assert(!replaced || damage_type == *h.passive.param, build_errors::DAMAGE_TYPE);
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
                assert(index < 16, build_errors::QUICK_CAST);
                pairs
                    .append(
                        QuickCast {
                            attribute: index.try_into().unwrap(),
                            every: fit((*h.passive.max).into()),
                        },
                    );
            }
        }
        assert(pairs.len() <= 2, build_errors::QUICK_CAST);
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
        assert(*loadout.rating <= MAX_RATING, build_errors::RATING);
        let rating: i32 = (*loadout.rating).into();
        let d = |guard: u8, class: u8| -> i8 {
            fit(HeldSums::total_scoped(held, id::DAMAGE_PERCENT, guard, class))
        };
        let p = |class: u8| -> u8 {
            fit(HeldSums::total_scoped(held, id::PENETRATION, guard::ALWAYS, class))
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
                weapon_damage: weapon_damage.try_into().expect(build_errors::OVERFLOW),
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
                armor: fit(rating + HeldSums::total_scoped(held, id::ARMOR, guard::ALWAYS, 0)),
            },
            kit: MemberKit {
                belt: *loadout.belt,
                life_steal: fit(HeldSums::total(held, id::LIFE_STEAL_ON_HIT)),
                energy_on_hit: fit(HeldSums::total(held, id::ENERGY_ON_HIT)),
                condition,
                condition_duration,
                enchantment_duration: saturate(
                    fit(HeldSums::total(held, id::ENCHANT_DURATION)), MAX_DURATION_BONUS_PERCENT,
                )
                    .try_into()
                    .unwrap(),
                double_adrenaline_every: every,
                // Freed (DS-3): the final maximum is `max_health`.
                health_bonus: 0,
                armor_stance: fit(
                    HeldSums::total_scoped(held, id::ARMOR, guard::IN_STANCE, HIT_WEAPON),
                ),
                armor_enchanted: fit(
                    HeldSums::total_scoped(held, id::ARMOR, guard::ENCHANTED, HIT_WEAPON),
                ),
                knockdown: saturate(fit(HeldSums::total(held, id::KNOCKDOWN_FLAT)), MAX_KNOCKDOWN)
                    .try_into()
                    .unwrap(),
                halving,
            },
            belt_counts: *loadout.belt_counts,
        }
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
    /// The snapshot of an adventurer at entry, from what its models hold today (ENG-06): its
    /// level and primary profession give health, energy, regeneration and armor (design/03); its
    /// bar, elite slot and belt are copied. What equipment, attribute ranks and set bonuses would
    /// add is 0: no entrypoint can yet equip an item or spend a point (`set_build` is a later
    /// lot's), and design/15's formulas are that lot's.
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
