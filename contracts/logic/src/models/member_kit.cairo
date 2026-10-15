//! `MemberKit`, the third of the member's three snapshot words: the belt and the modifiers of the
//! equipment, flattened at entry; its layout, checks and packing (bit offsets in
//! docs/architecture/ENG-01-interfaces.md, *Member*; pinned by the ephemeral package's
//! `test_tick_words`), and the flattening of its condition.

use crate::helpers::duration::MAX_DURATION_BONUS_PERCENT;
use crate::helpers::packing::{P16, P20, P32, P40, P56, P64, P72, P8, P96, PackingTrait};
use crate::helpers::signed::SignedTrait;
use crate::types::passive::{Passive, id};

pub mod errors {
    pub const CONDITION: felt252 = 'snapshot: condition';
    pub const PERCENT: felt252 = 'snapshot: percent above 63';
    pub const KNOCKDOWN: felt252 = 'snapshot: knock-down above 3';
    pub const CONDITIONS: felt252 = 'snapshot: two conditions';
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

/// The kit's word, and the snapshot builder's flattening of the kit (design/19 §4, §7.2). ENG-06
/// builds the rest of the snapshot with design/15's formulas; the rules here are the ones a
/// flattening defect was found in (CBT-9).
#[generate_trait]
pub impl MemberKitImpl of MemberKitTrait {
    fn pack(k: MemberKit) -> felt252 {
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
        PackingTrait::join(low, high)
    }

    fn unpack(word: felt252) -> MemberKit {
        let (low, high) = PackingTrait::split(word);
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

pub impl MemberKitStorePacking of starknet::storage_access::StorePacking<MemberKit, felt252> {
    fn pack(value: MemberKit) -> felt252 {
        MemberKitTrait::pack(value)
    }
    fn unpack(value: felt252) -> MemberKit {
        MemberKitTrait::unpack(value)
    }
}

/// Every field of the word fits its layout (docs/CAIRO.md §7: checks in `Assert` impls);
/// `MemberKitTrait::pack` calls it.
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

/// A sum flattened wide, then saturated at its field's cap (DS-5, FX-23). A free function: the
/// arithmetic of one field, no type owns it.
pub fn saturate(sum: u32, cap: u32) -> u32 {
    if sum > cap {
        cap
    } else {
        sum
    }
}

#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::combat::condition;
    use crate::types::passive::{Passive, PassiveTrait, id};
    use super::{MemberKit, MemberKitTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    fn passive(id: u8, param: u8, value: i16) -> Passive {
        PassiveTrait::new(id, param, 0, 0, value, value)
    }

    #[test]
    #[available_gas(l2_gas: 389991)] // ceil(1.05 × 371420 measured)
    fn test_kit_layout() {
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
        assert(MemberKitTrait::unpack(MemberKitTrait::pack(kit)) == kit, 'kit round trip');
        let kit = MemberKit { health_bonus: 1, ..Default::default() };
        assert(
            MemberKitTrait::pack(kit) == 0x10000000000 * TWO_128 + LIVE, 'health bonus at bit 168',
        );
    }

    // The kit's high limb (design/19 §7.2): 75 bits, each field at its bit; the narrow ones
    // refused when wider.
    #[test]
    #[available_gas(l2_gas: 638684)] // ceil(1.05 × 608270 measured)
    fn test_kit_passives_layout() {
        let bit = |kit: MemberKit| -> felt252 {
            MemberKitTrait::pack(kit) - LIVE
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
        let word = MemberKitTrait::pack(top);
        assert(MemberKitTrait::unpack(word) == top, 'top round trip');
        // 75 bits: the high limb's highest set bit is 202.
        let wide: u256 = word.into();
        assert(wide.high - 0x4000000000000000000000000000000 < 0x8000000000000000000, 'within 75');
    }

    #[test]
    #[should_panic(expected: 'snapshot: knock-down above 3')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_kit_knockdown_refused() {
        MemberKitTrait::pack(MemberKit { knockdown: 4, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: percent above 63')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_kit_percent_refused() {
        MemberKitTrait::pack(MemberKit { enchantment_duration: 64, ..Default::default() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: condition')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_kit_condition_refused() {
        MemberKitTrait::pack(MemberKit { condition: 16, ..Default::default() });
    }

    // CBT-9, DS-5 (design/20 §6 test 4): `MemberKitTrait::condition_duration` sums wide, then
    // saturates at 50: envelope A's 65,534 gives 50 (the builder's sum, without the validators
    // that now forbid it). Moved from `test_capacity` (D-167, CBT-02c fix loop 1).
    #[test]
    #[available_gas(l2_gas: 32739)] // ceil(1.05 × 31180 measured)
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
    #[available_gas(l2_gas: 22922)] // ceil(1.05 × 21830 measured)
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
