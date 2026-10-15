//! `MemberStats`, the first of the member's three snapshot words: what the build and the
//! equipment give, fixed for the instance; its layout, its checks and its packing (bit offsets in
//! docs/architecture/ENG-01-interfaces.md, *Member*; the words are ENG-01's frozen ones, pinned by
//! the ephemeral package's `test_tick_words`).

use crate::helpers::packing::{
    P104, P108, P112, P120, P16, P24, P32, P40, P48, P56, P64, P72, P8, P80, P84, P88, P96,
    PackingTrait,
};

/// 2^114: `MemberStats`' bit 242 in its high limb (the quick-cast slots 4–7).
const P114: u128 = 0x40000000000000000000000000000;

pub mod errors {
    pub const HEALTH_REGEN: felt252 = 'snapshot: health regen';
    pub const ARMOR_VS: felt252 = 'snapshot: armor vs above 63';
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
    /// The quick-cast pairs each bar slot's skill counts for (CBT-05f, D-157 A: the skill's global
    /// attribute against the pair's build-local index): slot `i`'s pair `p` at bit `2 i + p`;
    /// slots 0–3 at bits 168–175, slots 4–7 at 242–249.
    pub quick_cast_slots: u16,
    /// The bar slots whose attack skill names an attribute other than the weapon's (CBT-05f,
    /// design/19 §3.4's skill kinds: "needs the weapon of its attribute"), slot `i` at bit
    /// `40 + i`.
    pub weapon_required: u8,
}

#[generate_trait]
pub impl MemberStatsImpl of MemberStatsTrait {
    fn pack(s: MemberStats) -> felt252 {
        s.assert_valid();
        let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = s.armor_vs;
        let low: u128 = s.max_health.into()
            + s.max_energy.into() * P16
            + s.energy_regen.into() * P24
            + s.health_regen.into() * P32
            + s.weapon_required.into() * P40
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
        let (slots_high, slots_low) = DivRem::div_rem(s.quick_cast_slots, 0x100);
        let high: u128 = s.ranks.into()
            + s.damage_type.into() * P32
            + slots_low.into() * P40
            + s.requirement_met.into() * P48
            + s.set_bonuses.into() * P56
            + v3.into() * P72
            + v4.into() * 0x40000000000000000000
            + v5.into() * P84
            + v6.into() * 0x40000000000000000000000
            + v7.into() * P96
            + v8.into() * 0x40000000000000000000000000
            + v9.into() * P108
            + slots_high.into() * P114;
        PackingTrait::join(low, high)
    }

    fn unpack(word: felt252) -> MemberStats {
        let (low, high) = PackingTrait::split(word);
        let b8: NonZero<u128> = P8.try_into().unwrap();
        let b16: NonZero<u128> = P16.try_into().unwrap();
        let b6: NonZero<u128> = 0x40;
        let (low, max_health) = DivRem::div_rem(low, b16);
        let (low, max_energy) = DivRem::div_rem(low, b8);
        let (low, energy_regen) = DivRem::div_rem(low, b8);
        let (low, health_regen) = DivRem::div_rem(low, b8);
        let (low, weapon_required) = DivRem::div_rem(low, b8);
        let (low, v1) = DivRem::div_rem(low, b6);
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
        let (high, slots_low) = DivRem::div_rem(high, b8);
        let (high, requirement_met) = DivRem::div_rem(high, b8);
        let (high, set_bonuses) = DivRem::div_rem(high, b16);
        let (high, v3) = DivRem::div_rem(high, b6);
        let (high, v4) = DivRem::div_rem(high, b6);
        let (high, v5) = DivRem::div_rem(high, b6);
        let (high, v6) = DivRem::div_rem(high, b6);
        let (high, v7) = DivRem::div_rem(high, b6);
        let (high, v8) = DivRem::div_rem(high, b6);
        let (slots_high, v9) = DivRem::div_rem(high, b6);
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
            quick_cast_slots: (slots_low + slots_high * 0x100).try_into().unwrap(),
            weapon_required: weapon_required.try_into().unwrap(),
        }
    }
}

pub impl MemberStatsStorePacking of starknet::storage_access::StorePacking<MemberStats, felt252> {
    fn pack(value: MemberStats) -> felt252 {
        MemberStatsTrait::pack(value)
    }
    fn unpack(value: felt252) -> MemberStats {
        MemberStatsTrait::unpack(value)
    }
}

/// Every field of the word fits its layout (docs/CAIRO.md §7: checks in `Assert` impls);
/// `MemberStatsTrait::pack` calls it.
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

#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use super::{MemberStats, MemberStatsTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    // DS-29: `MemberStatsTrait::pack` accepts a health regeneration of 20 and refuses 21.
    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 117632)] // ceil(1.05 × 112030 measured)
    fn test_stats_health_regen_20_packs() {
        MemberStatsTrait::pack(MemberStats { health_regen: 20, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: health regen')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_stats_health_regen_21_refused() {
        MemberStatsTrait::pack(MemberStats { health_regen: 21, ..Default::default() });
    }

    #[test]
    // gas: raised, CBT-05f: the attribute mappings in the flattening, its oracle and MemberStats
    #[available_gas(l2_gas: 866870)] // ceil(1.05 × 825590 measured)
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
            quick_cast_slots: 0xFFFF,
            weapon_required: 0xFF,
        };
        assert(MemberStatsTrait::unpack(MemberStatsTrait::pack(stats)) == stats, 'round trip');
        // CBT-05f: the weapon-required slots at 40–47; the quick-cast slots 0–3 at 168–175,
        // 4–7 at 242–249, below `LIVE`.
        let required = MemberStats { weapon_required: 1, ..Default::default() };
        assert(MemberStatsTrait::pack(required) == 0x10000000000 + LIVE, 'weapon required at 40');
        let quick = MemberStats { quick_cast_slots: 0x0101, ..Default::default() };
        let at168 = 0x1000000000000000000000000000000000000000000;
        let at242 = 0x4000000000000000000000000000000000000000000000000000000000000;
        assert(MemberStatsTrait::pack(quick) == at168 + at242 + LIVE, 'quick cast at 168, 242');
        let level = MemberStats { level: 1, ..Default::default() };
        assert(MemberStatsTrait::pack(level) == 0x10000000000000000 + LIVE, 'level at bit 64');
        let ranks = MemberStats { ranks: 1, ..Default::default() };
        assert(MemberStatsTrait::pack(ranks) == TWO_128 + LIVE, 'ranks at bit 128');
        // design/19 §7.2: `ARMOR_VS` types 1–2 at bits 48, 54; types 3–9 at 200 + 6 (type −
        // 3).
        let vs = MemberStats { armor_vs: [1, 1, 0, 0, 0, 0, 0, 0, 0], ..Default::default() };
        assert(
            MemberStatsTrait::pack(vs) == 0x1000000000000 + 0x40000000000000 + LIVE,
            'vs 1-2 at 48, 54',
        );
        let vs = MemberStats { armor_vs: [0, 0, 1, 0, 0, 0, 0, 0, 1], ..Default::default() };
        let at200 = 0x100000000000000000000000000000000000000000000000000;
        let at236 = 0x100000000000000000000000000000000000000000000000000000000000;
        assert(MemberStatsTrait::pack(vs) == at200 + at236 + LIVE, 'vs 3 at 200, 9 at 236');
    }

    #[test]
    #[should_panic(expected: 'snapshot: armor vs above 63')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_stats_armor_vs_refused() {
        MemberStatsTrait::pack(
            MemberStats { armor_vs: [0, 0, 0, 0, 0, 0, 0, 0, 64], ..Default::default() },
        );
    }
}
