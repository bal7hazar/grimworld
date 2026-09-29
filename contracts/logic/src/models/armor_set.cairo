//! `ARMOR_SET`: its constructor, its checks and its record (layout: `models::index::ArmorSet`).
//! Five pieces and two bonuses, the first with 3 pieces worn, both with 5 (design/15 D-45); a
//! bonus is one passive (design/19 §4).

use crate::content::{ARMOR_SET, Record};
use crate::packing::{P16, P32, P48, P64, join, split};
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
    /// so the snapshot's 2 bits hold it saturated.
    fn assert_legal(self: @ArmorSet) {
        let [first, second] = *self.bonuses;
        first.assert_source(Source::SetBonus);
        second.assert_source(Source::SetBonus);
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
        array![join(low, PassiveTrait::pack_pair(@first, @second))].span()
    }

    fn unpack(parts: Span<felt252>) -> ArmorSet {
        let (low, high) = split(*parts[0]);
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
