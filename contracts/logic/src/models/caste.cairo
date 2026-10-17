//! `CASTE`: its constructor, its checks and its record (layout: `models::index::Caste`). The
//! caste sheet's shape (design/19 §7.3); DES-06 fills the values. A goblin's stats, weapon and
//! skills are read from it: no `BASE` read.

use crate::helpers::packing::{
    P104, P12, P16, P24, P32, P36, P40, P48, P8, P80, P88, P96, PackingTrait,
};
use crate::types::combat::{damage, weapon};
use crate::types::content::{CASTE, Record};
pub use super::index::{Caste, Weapon};

/// The widest tier (design/05).
pub const LAST_TIER: u8 = 6;
/// The widest caste energy: stored in thirds in a `u8` of `GoblinState` (85 × 3 = 255).
pub const MAX_ENERGY: u8 = 85;
/// Health regeneration is stored + 10: 0–20 for −10…+10 pips.
pub const MAX_HEALTH_REGEN: u8 = 20;
/// design/20 DS-18 (D-160): the health multiplier, percent; energy regeneration, pips; weapon
/// damage; the flee threshold, percent; a skill's adrenaline, strikes.
pub const MAX_HEALTH_PERCENT: u16 = 1000;
pub const MAX_ENERGY_REGEN: u8 = 10;
pub const MAX_WEAPON_DAMAGE: u16 = 255;
pub const MAX_FLEE: u8 = 100;
pub const MAX_SKILL_ADRENALINE: u8 = 63;

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
    pub const HEALTH: felt252 = 'caste: health above 1000 %';
    pub const ENERGY_REGEN: felt252 = 'caste: energy regen above 10';
    pub const WEAPON_DAMAGE: felt252 = 'caste: weapon damage above 255';
    pub const FLEE: felt252 = 'caste: flee above 100';
    pub const SKILL_ADRENALINE: felt252 = 'caste: skill adrenaline';
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

    /// Its 32 bits (`WeaponAssert::assert_valid`).
    fn pack(self: @Weapon) -> u128 {
        self.assert_valid();
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
pub impl WeaponAssert of WeaponAssertTrait {
    /// Class, damage type, ticks and range fit 4 bits each.
    #[inline(always)]
    fn assert_valid(self: @Weapon) {
        assert(
            *self.class < 16 && *self.damage_type < 16 && *self.ticks < 16 && *self.range < 16,
            errors::WEAPON,
        );
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
    /// Every field fits its layout: armor per type 6 bits, rank 4 bits, energy at most 85; and,
    /// checked at `pack` since design/20's capacity proof rests on them (D-160): health
    /// regeneration 0–20, −10…+10 pips (DS-29), a health multiplier ≤ 1,000 %, energy
    /// regeneration ≤ 10 pips, weapon damage ≤ 255 and a flee threshold ≤ 100 % (DS-18).
    #[inline(always)]
    fn assert_valid(self: @Caste) {
        for vs in self.armor_vs.span() {
            assert(*vs < 64, errors::ARMOR_VS);
        }
        assert(*self.rank < 16, errors::RANK);
        assert(*self.energy <= MAX_ENERGY, errors::ENERGY);
        assert(*self.health_regen <= MAX_HEALTH_REGEN, errors::HEALTH_REGEN);
        assert(*self.health <= MAX_HEALTH_PERCENT, errors::HEALTH);
        assert(*self.energy_regen <= MAX_ENERGY_REGEN, errors::ENERGY_REGEN);
        assert(*self.weapon.damage <= MAX_WEAPON_DAMAGE, errors::WEAPON_DAMAGE);
        assert(*self.flee <= MAX_FLEE, errors::FLEE);
    }

    /// DS-18 across records: the adrenaline cost of each skill the caste names is at most 63
    /// strikes (a goblin's field holds 252 quarters, design/19 §5.12), or it could never be used.
    /// `skills` are the records of the caste's skill ids.
    fn assert_skills(skills: Span<super::index::Skill>) {
        for skill in skills {
            assert(*skill.adrenaline <= MAX_SKILL_ADRENALINE, errors::SKILL_ADRENALINE);
        }
    }

    /// The content pipeline's checks: `assert_valid`, tier 1–6, a weapon of a class and a damage
    /// type that exist.
    fn assert_legal(self: @Caste) {
        self.assert_valid();
        assert(*self.tier >= 1 && *self.tier <= LAST_TIER, errors::TIER);
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
        array![PackingTrait::join(low, high), PackingTrait::join(skills, 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Caste {
        let (low, high) = PackingTrait::split(*parts[0]);
        let (skills, _) = PackingTrait::split(*parts[1]);
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

/// The record's unit tests (CBT-01, design/19 §7.3; design/20 §6 tests 6 and 9, D-160): it
/// round-trips at its bounds, sits at its documented bits, and refuses a field beyond its width or
/// design/20's bound.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::models::skill::{Skill, SkillAssert, SkillRecord, SkillTrait};
    use crate::types::combat::{damage, skill_kind, weapon};
    use crate::types::content::{CASTE, KindTrait, Record};
    use crate::types::effect::target;
    use super::{Caste, CasteAssert, CasteRecord, CasteTrait, WeaponTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// The castes these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        /// Every field at its widest that packs: the layout's width, or design/20's bound where
        /// `assert_valid` checks one (DS-18: health 1,000 %, energy regeneration 10, weapon damage
        /// 255, flee 100; DS-29: health regeneration 20).
        fn caste_max() -> Caste {
            CasteTrait::new(
                0xFF,
                0xFF,
                1000,
                20,
                0xFF,
                [63, 1, 2, 3, 4, 5, 6, 7, 63],
                WeaponTrait::new(15, 255, 15, 15, 15),
                85,
                10,
                [0xFFFF, 2, 3, 0xFFFF],
                15,
                100,
                0xFFFF,
                true,
            )
        }

        /// A caste at design/20's bounds (DS-18, DS-29): multiplier 1,000 %, energy 85,
        /// regeneration 10 pips, weapon damage 255, flee 100, health regeneration 20.
        fn caste_at_bounds() -> Caste {
            CasteTrait::new(
                6,
                1,
                1000,
                20,
                40,
                [0; 9],
                WeaponTrait::new(weapon::MAUL, 255, damage::BLUNT, 2, 1),
                85,
                10,
                [1, 0, 0, 0],
                15,
                100,
                0,
                false,
            )
        }

        fn skill_of(adrenaline: u8) -> Skill {
            SkillTrait::new(
                1,
                1,
                skill_kind::ATTACK,
                0,
                adrenaline,
                1,
                5,
                1,
                target::FOE,
                false,
                [Default::default(); 3],
            )
        }
    }

    // §7.3: `CASTE`, 2 parts, 243 bits over 4 limbs, no field straddling one.
    #[test]
    #[available_gas(l2_gas: 649583)] // ceil(1.05 × 618650 measured)
    fn test_caste_round_trip() {
        let top = Fixture::caste_max();
        let packed = top.pack();
        assert(packed.len() == KindTrait::parts(CASTE).into(), 'parts');
        assert(Record::<Caste>::unpack(packed) == top, 'top round trip');
        let zero = CasteTrait::new(
            0, 0, 0, 0, 0, [0; 9], Default::default(), 0, 0, [0; 4], 0, 0, 0, false,
        );
        assert(zero.pack() == array![LIVE, LIVE].span(), 'empty is LIVE');
        let one = CasteTrait::new(
            0,
            0,
            0,
            0,
            0,
            [0; 9],
            WeaponTrait::new(1, 0, 0, 0, 1),
            0,
            0,
            [0, 0, 0, 1],
            1,
            0,
            1,
            true,
        );
        let parts = one.pack();
        // Weapon class at 48, its range at 76, rank at 104, boss at 108; loot table at 182; skill 3
        // at part 1's bit 48.
        let low = 0x1000000000000
            + 0x10000000000000000000
            + 0x100000000000000000000000000
            + 0x1000000000000000000000000000;
        let two_182: felt252 = TWO_128 * 0x40000000000000;
        assert(*parts[0] == low + two_182 + LIVE, 'part 0 bits');
        assert(*parts[1] == 0x1000000000000 + LIVE, 'part 1 bits');
        // Armor against type 9 at 128 + 48.
        let vs = CasteTrait::new(
            0,
            0,
            0,
            0,
            0,
            [0, 0, 0, 0, 0, 0, 0, 0, 1],
            Default::default(),
            0,
            0,
            [0; 4],
            0,
            0,
            0,
            false,
        );
        assert(*vs.pack()[0] == TWO_128 * 0x1000000000000 + LIVE, 'vs 9 at 176');
        let goblin = CasteTrait::new(
            1,
            1,
            100,
            10,
            40,
            [0; 9],
            WeaponTrait::new(weapon::AXE, 12, damage::SLASHING, 1, 1),
            20,
            2,
            [1, 0, 0, 0],
            6,
            30,
            1,
            false,
        );
        goblin.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'caste: energy above 85')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_energy_refused() {
        let top = Fixture::caste_max();
        Caste { energy: 86, ..top }.pack();
    }

    #[test]
    #[should_panic(expected: 'caste: armor vs above 63')]
    #[available_gas(l2_gas: 122283)] // ceil(1.05 × 116460 measured)
    fn test_caste_armor_vs_refused() {
        let top = Fixture::caste_max();
        Caste { armor_vs: [64, 0, 0, 0, 0, 0, 0, 0, 0], ..top }.pack();
    }

    #[test]
    #[should_panic(expected: 'caste: rank')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_rank_refused() {
        let top = Fixture::caste_max();
        Caste { rank: 16, ..top }.pack();
    }

    #[test]
    #[should_panic(expected: 'caste: weapon field')]
    #[available_gas(l2_gas: 45087)] // ceil(1.05 × 42940 measured)
    fn test_caste_weapon_refused() {
        let top = Fixture::caste_max();
        Caste { weapon: WeaponTrait::new(16, 0, 0, 0, 0), ..top }.pack();
    }

    #[test]
    #[should_panic(expected: 'caste: health regen')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_health_regen_refused() {
        let top = Fixture::caste_max();
        Caste { tier: 1, health_regen: 21, weapon: WeaponTrait::new(1, 1, 1, 1, 1), ..top }
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'caste: health above 1000 %')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_multiplier_1001_refused() {
        let caste = Caste { health: 1001, ..Fixture::caste_at_bounds() };
        Record::<Caste>::pack(@caste);
    }

    #[test]
    #[should_panic(expected: 'caste: energy regen above 10')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_energy_regen_refused() {
        let caste = Caste { energy_regen: 11, ..Fixture::caste_at_bounds() };
        Record::<Caste>::pack(@caste);
    }

    #[test]
    #[should_panic(expected: 'caste: weapon damage above 255')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_weapon_damage_refused() {
        let caste = Caste {
            weapon: WeaponTrait::new(weapon::MAUL, 256, damage::BLUNT, 2, 1),
            ..Fixture::caste_at_bounds(),
        };
        Record::<Caste>::pack(@caste);
    }

    #[test]
    #[should_panic(expected: 'caste: flee above 100')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_flee_refused() {
        let caste = Caste { flee: 101, ..Fixture::caste_at_bounds() };
        Record::<Caste>::pack(@caste);
    }

    #[test]
    #[should_panic(expected: 'caste: skill adrenaline')]
    #[available_gas(l2_gas: 49413)] // ceil(1.05 × 47060 measured)
    fn test_caste_skill_of_64_strikes_refused() {
        CasteAssert::assert_skills(array![Fixture::skill_of(63), Fixture::skill_of(64)].span());
    }

    // §6 test 9 (DS-29): a caste's health regeneration 21 is refused at `pack`;
    // `MemberStatsTrait::pack` refuses 21 and accepts 20. The tick's extremes:
    // `test_tick::test_regeneration_extremes`.
    #[test]
    #[should_panic(expected: 'caste: health regen')]
    #[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
    fn test_caste_health_regen_21_refused_at_pack() {
        let caste = Caste { health_regen: 21, ..Fixture::caste_at_bounds() };
        Record::<Caste>::pack(@caste);
    }
}
