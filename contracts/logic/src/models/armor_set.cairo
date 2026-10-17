//! `ARMOR_SET`: its constructor, its checks and its record (layout: `models::index::ArmorSet`).
//! Five pieces and two bonuses, the first with 3 pieces worn, both with 5 (design/15 D-45); a
//! bonus is one passive (design/19 §4).

use crate::helpers::packing::{P16, P32, P48, P64, PackingTrait};
use crate::types::content::{ARMOR_SET, Record};
use crate::types::passive::{Passive, PassiveAssert, PassiveTrait, Source};
pub use super::index::ArmorSet;

/// Pieces worn for each bonus (design/15 D-45).
pub const FIRST_BONUS_PIECES: u8 = 3;
pub const SECOND_BONUS_PIECES: u8 = 5;

#[generate_trait]
pub impl ArmorSetImpl of ArmorSetTrait {
    fn new(pieces: [u16; 5], bonuses: [Passive; 2]) -> ArmorSet {
        ArmorSet { pieces, bonuses }
    }
}

#[generate_trait]
pub impl ArmorSetAssert of ArmorSetAssertTrait {
    /// The content pipeline's checks: both bonuses legal and allowed on a set bonus
    /// (`PassiveTrait::allows`, design/19 §7.2). Two bonuses of one statistic are two of the
    /// "2 set bonuses" §7.2 counts; a `KNOCKDOWN_FLAT` sum is capped at 3 at use (ENG-01 §3.1),
    /// so the snapshot's 2 bits hold it saturated. Each bonus, one source, within design/20's
    /// per-source bounds (DS-1).
    fn assert_legal(self: @ArmorSet) {
        let [first, second] = *self.bonuses;
        first.assert_source(Source::SetBonus);
        second.assert_source(Source::SetBonus);
        PassiveAssert::assert_source_bounds(array![first].span(), Source::SetBonus);
        PassiveAssert::assert_source_bounds(array![second].span(), Source::SetBonus);
    }
}

pub impl ArmorSetRecord of Record<ArmorSet> {
    const KIND: u8 = ARMOR_SET;

    fn pack(self: @ArmorSet) -> Span<felt252> {
        let [a, b, c, d, e] = *self.pieces;
        let low: u128 = a.into()
            + b.into() * P16
            + c.into() * P32
            + d.into() * P48
            + e.into() * P64;
        let [first, second] = *self.bonuses;
        array![PackingTrait::join(low, PassiveTrait::pack_pair(@first, @second))].span()
    }

    fn unpack(parts: Span<felt252>) -> ArmorSet {
        let (low, high) = PackingTrait::split(*parts[0]);
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (low, a) = DivRem::div_rem(low, s16);
        let (low, b) = DivRem::div_rem(low, s16);
        let (low, c) = DivRem::div_rem(low, s16);
        let (e, d) = DivRem::div_rem(low, s16);
        let (first, second) = PassiveTrait::unpack_pair(high);
        ArmorSet {
            pieces: [
                a.try_into().unwrap(), b.try_into().unwrap(), c.try_into().unwrap(),
                d.try_into().unwrap(), e.try_into().unwrap(),
            ],
            bonuses: [first, second],
        }
    }
}

/// The record's unit tests (CBT-01, design/19 §7.2; design/20 §6 test 1, D-160): it round-trips
/// at its bounds, and its validators refuse a bonus a set may not hold or one beyond its source's
/// bound.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::combat::condition;
    use crate::types::content::{ARMOR_SET, KindTrait, Record};
    use crate::types::passive::{Passive, PassiveAssert, PassiveTrait, id};
    use super::{ArmorSet, ArmorSetAssert, ArmorSetRecord, ArmorSetTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// The passives these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        fn passive_max() -> Passive {
            PassiveTrait::new(0xFF, 0xFF, 7, 3, -32768, 32767)
        }

        fn passive(id: u8, param: u8, value: i16) -> Passive {
            PassiveTrait::new(id, param, 0, 0, value, value)
        }

        fn quick_cast() -> Passive {
            PassiveTrait::new(id::QUICK_CAST_EVERY_N, 4, 0, 0, 5, 5)
        }
    }

    // §7.2: `ARMOR_SET`, 1 part: 5 piece bases low, 2 bonuses high.
    #[test]
    #[available_gas(l2_gas: 256683)] // ceil(1.05 × 244460 measured)
    fn test_armor_set_round_trip() {
        let top = ArmorSetTrait::new(
            [0xFFFF, 2, 3, 4, 0xFFFF], [Fixture::passive_max(), Fixture::passive_max()],
        );
        let packed = top.pack();
        assert(packed.len() == KindTrait::parts(ARMOR_SET).into(), 'parts');
        assert(Record::<ArmorSet>::unpack(packed) == top, 'top round trip');
        let p: Passive = Default::default();
        let bits = ArmorSetTrait::new([0, 0, 0, 0, 1], [p, Passive { id: 1, ..p }]).pack();
        let two_181: felt252 = TWO_128 * 0x20000000000000;
        assert(*bits[0] == 0x10000000000000000 + two_181 + LIVE, 'bits');
        // *Hob-breaker* (design/15): knock-downs +1 tick, then the halving.
        let hob = ArmorSetTrait::new(
            [1, 2, 3, 4, 5],
            [
                PassiveTrait::new(id::KNOCKDOWN_FLAT, 0, 0, 0, 1, 1),
                PassiveTrait::new(id::HALVE_FIRST_HEAVY_HIT, 0, 0, 0, 0, 0),
            ],
        );
        hob.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_quick_cast_set_bonus_refused() {
        ArmorSetTrait::new([1, 2, 3, 4, 5], [Fixture::quick_cast(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_condition_duration_set_bonus_refused() {
        let rending = Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33);
        ArmorSetTrait::new([1, 2, 3, 4, 5], [rending, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_type_set_bonus_refused() {
        let fire = Fixture::passive(id::DAMAGE_TYPE, 4, 0);
        ArmorSetTrait::new([1, 2, 3, 4, 5], [fire, Default::default()]).assert_legal();
    }

    // CBT-2's sums without a capacity rule are ruled by design/20 (D-160): life steal on hit is
    // held on held slots only (row 13), so a set's bonus is refused.
    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_life_steal_set_bonus_refused() {
        let steal = Fixture::passive(id::LIFE_STEAL_ON_HIT, 0, 5);
        ArmorSetTrait::new([1, 2, 3, 4, 5], [steal, steal]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: per-source bound')]
    #[available_gas(l2_gas: 20916)] // ceil(1.05 × 19920 measured)
    fn test_set_bonus_beyond_bound_refused() {
        let knock = Fixture::passive(id::KNOCKDOWN_FLAT, 0, 2);
        ArmorSetTrait::new([1, 2, 3, 4, 5], [knock, knock]).assert_legal();
    }
}
