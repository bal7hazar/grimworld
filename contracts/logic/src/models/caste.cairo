//! `CASTE`: its constructor, its checks and its record (layout: `models::index::Caste`). The
//! caste sheet's shape (design/19 §7.3); DES-06 fills the values. A goblin's stats, weapon and
//! skills are read from it: no `BASE` read.

use crate::content::{CASTE, Record};
use crate::packing::{
    P104, P12, P16, P24, P32, P36, P40, P48, P8, P80, P88, P96, join, split,
};
use crate::types::combat::{damage, weapon};
pub use super::index::{Caste, Weapon};

/// The widest tier (design/05).
pub const LAST_TIER: u8 = 6;
/// The widest caste energy: stored in thirds in a `u8` of `GoblinState` (85 × 3 = 255).
pub const MAX_ENERGY: u8 = 85;
/// Health regeneration is stored + 10: 0–20 for −10…+10 pips.
pub const MAX_HEALTH_REGEN: u8 = 20;

const P6: u128 = 0x40;
const P18: u128 = 0x40000;
const P20: u128 = 0x100000;
const P28: u128 = 0x10000000;
const P30: u128 = 0x40000000;
const P42: u128 = 0x40000000000;
const P54: u128 = 0x40000000000000;
const P108: u128 = 0x1000000000000000000000000000;

pub mod errors {
    pub const WEAPON: felt252 = 'caste: weapon field';
    pub const ARMOR_VS: felt252 = 'caste: armor vs above 63';
    pub const RANK: felt252 = 'caste: rank';
    pub const ENERGY: felt252 = 'caste: energy above 85';
    // The content pipeline's checks (`assert_legal`).
    pub const TIER: felt252 = 'caste: tier';
    pub const HEALTH_REGEN: felt252 = 'caste: health regen';
    pub const WEAPON_CLASS: felt252 = 'caste: weapon class';
    pub const DAMAGE_TYPE: felt252 = 'caste: damage type';
}

#[generate_trait]
pub impl WeaponImpl of WeaponTrait {
    fn new(class: u8, damage: u16, damage_type: u8, ticks: u8, range: u8) -> Weapon {
        Weapon { class, damage, damage_type, ticks, range }
    }

    /// Its 32 bits; refuses a class, type, ticks or range above 15 (4 bits each).
    fn pack(self: @Weapon) -> u128 {
        assert(
            *self.class < 16 && *self.damage_type < 16 && *self.ticks < 16 && *self.range < 16,
            errors::WEAPON,
        );
        (*self.class).into()
            + (*self.damage).into() * 0x10
            + (*self.damage_type).into() * P20
            + (*self.ticks).into() * P24
            + (*self.range).into() * P28
    }

    fn unpack(bits: u128) -> Weapon {
        let (bits, class) = DivRem::div_rem(bits, 0x10);
        let (bits, damage) = DivRem::div_rem(bits, P16.try_into().unwrap());
        let (bits, damage_type) = DivRem::div_rem(bits, 0x10);
        let (range, ticks) = DivRem::div_rem(bits, 0x10);
        Weapon {
            class: class.try_into().unwrap(),
            damage: damage.try_into().unwrap(),
            damage_type: damage_type.try_into().unwrap(),
            ticks: ticks.try_into().unwrap(),
            range: range.try_into().unwrap(),
        }
    }
}

#[generate_trait]
pub impl CasteImpl of CasteTrait {
    fn new(
        tier: u8,
        ai: u8,
        health: u16,
        health_regen: u8,
        armor: u8,
        armor_vs: [u8; 9],
        weapon: Weapon,
        energy: u8,
        energy_regen: u8,
        skills: [u16; 4],
        rank: u8,
        flee: u8,
        loot_table: u16,
        boss: bool,
    ) -> Caste {
        Caste {
            tier,
            ai,
            health,
            health_regen,
            armor,
            armor_vs,
            weapon,
            energy,
            energy_regen,
            skills,
            rank,
            flee,
            loot_table,
            boss,
        }
    }
}

#[generate_trait]
pub impl CasteAssert of CasteAssertTrait {
    /// Every field fits its layout: armor per type 6 bits, rank 4 bits, energy at most 85.
    #[inline(always)]
    fn assert_valid(self: @Caste) {
        for vs in self.armor_vs.span() {
            assert(*vs < 64, errors::ARMOR_VS);
        }
        assert(*self.rank < 16, errors::RANK);
        assert(*self.energy <= MAX_ENERGY, errors::ENERGY);
    }

    /// The content pipeline's checks: tier 1–6, health regeneration 0–20 (−10…+10 pips), a
    /// weapon of a class and a damage type that exist.
    fn assert_legal(self: @Caste) {
        self.assert_valid();
        assert(*self.tier >= 1 && *self.tier <= LAST_TIER, errors::TIER);
        assert(*self.health_regen <= MAX_HEALTH_REGEN, errors::HEALTH_REGEN);
        let class = *self.weapon.class;
        assert(class >= weapon::SWORD && class <= weapon::LAST, errors::WEAPON_CLASS);
        let kind = *self.weapon.damage_type;
        assert(kind >= damage::SLASHING && kind <= damage::LAST, errors::DAMAGE_TYPE);
    }
}

pub impl CasteRecord of Record<Caste> {
    const KIND: u8 = CASTE;

    fn pack(self: @Caste) -> Span<felt252> {
        self.assert_valid();
        let low: u128 = (*self.tier).into()
            + (*self.ai).into() * P8
            + (*self.health).into() * P16
            + (*self.health_regen).into() * P32
            + (*self.armor).into() * P40
            + self.weapon.pack() * P48
            + (*self.energy).into() * P80
            + (*self.energy_regen).into() * P88
            + (*self.flee).into() * P96
            + (*self.rank).into() * P104
            + if *self.boss {
                P108
            } else {
                0
            };
        let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = *self.armor_vs;
        let high: u128 = v1.into()
            + v2.into() * P6
            + v3.into() * P12
            + v4.into() * P18
            + v5.into() * P24
            + v6.into() * P30
            + v7.into() * P36
            + v8.into() * P42
            + v9.into() * P48
            + (*self.loot_table).into() * P54;
        let [s0, s1, s2, s3] = *self.skills;
        let skills: u128 = s0.into() + s1.into() * P16 + s2.into() * P32 + s3.into() * P48;
        array![join(low, high), join(skills, 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Caste {
        let (low, high) = split(*parts[0]);
        let (skills, _) = split(*parts[1]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let s6: NonZero<u128> = P6.try_into().unwrap();
        let (low, tier) = DivRem::div_rem(low, s8);
        let (low, ai) = DivRem::div_rem(low, s8);
        let (low, health) = DivRem::div_rem(low, s16);
        let (low, health_regen) = DivRem::div_rem(low, s8);
        let (low, armor) = DivRem::div_rem(low, s8);
        let (low, weapon) = DivRem::div_rem(low, P32.try_into().unwrap());
        let (low, energy) = DivRem::div_rem(low, s8);
        let (low, energy_regen) = DivRem::div_rem(low, s8);
        let (low, flee) = DivRem::div_rem(low, s8);
        let (boss, rank) = DivRem::div_rem(low, 0x10);
        let (high, v1) = DivRem::div_rem(high, s6);
        let (high, v2) = DivRem::div_rem(high, s6);
        let (high, v3) = DivRem::div_rem(high, s6);
        let (high, v4) = DivRem::div_rem(high, s6);
        let (high, v5) = DivRem::div_rem(high, s6);
        let (high, v6) = DivRem::div_rem(high, s6);
        let (high, v7) = DivRem::div_rem(high, s6);
        let (high, v8) = DivRem::div_rem(high, s6);
        let (loot_table, v9) = DivRem::div_rem(high, s6);
        let (skills, s0) = DivRem::div_rem(skills, s16);
        let (skills, s1) = DivRem::div_rem(skills, s16);
        let (s3, s2) = DivRem::div_rem(skills, s16);
        Caste {
            tier: tier.try_into().unwrap(),
            ai: ai.try_into().unwrap(),
            health: health.try_into().unwrap(),
            health_regen: health_regen.try_into().unwrap(),
            armor: armor.try_into().unwrap(),
            armor_vs: [
                v1.try_into().unwrap(), v2.try_into().unwrap(), v3.try_into().unwrap(),
                v4.try_into().unwrap(), v5.try_into().unwrap(), v6.try_into().unwrap(),
                v7.try_into().unwrap(), v8.try_into().unwrap(), v9.try_into().unwrap(),
            ],
            weapon: WeaponTrait::unpack(weapon),
            energy: energy.try_into().unwrap(),
            energy_regen: energy_regen.try_into().unwrap(),
            skills: [
                s0.try_into().unwrap(), s1.try_into().unwrap(), s2.try_into().unwrap(),
                s3.try_into().unwrap(),
            ],
            rank: rank.try_into().unwrap(),
            flee: flee.try_into().unwrap(),
            loot_table: loot_table.try_into().unwrap(),
            boss: boss != 0,
        }
    }
}
