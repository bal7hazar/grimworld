//! `REGION`: its constructor, its checks and its record (layout: `models::index::Region`).

use crate::helpers::packing::{P120, P16, P32, PackingTrait};
use crate::types::content::{REGION, Record};
pub use super::index::Region;

pub mod errors {
    pub const NAME: felt252 = 'region: name too long';
}

#[generate_trait]
pub impl RegionImpl of RegionTrait {
    fn new(town: u16, book: u16, first_location: u16, name: felt252) -> Region {
        Region { town, book, first_location, name }
    }
}

#[generate_trait]
pub impl RegionAssert of RegionAssertTrait {
    /// The name fits its field: a short string of at most 15 characters (bits 128–247).
    #[inline(always)]
    fn assert_valid(self: @Region) -> u128 {
        let name: u128 = (*self.name).try_into().expect(errors::NAME);
        assert(name < P120, errors::NAME);
        name
    }
}

pub impl RegionRecord of Record<Region> {
    const KIND: u8 = REGION;

    fn pack(self: @Region) -> Span<felt252> {
        let name = self.assert_valid();
        let low: u128 = (*self.town).into()
            + (*self.book).into() * P16
            + (*self.first_location).into() * P32;
        array![PackingTrait::join(low, name)].span()
    }

    fn unpack(parts: Span<felt252>) -> Region {
        let (low, name) = PackingTrait::split(*parts[0]);
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (low, town) = DivRem::div_rem(low, s16);
        let (low, book) = DivRem::div_rem(low, s16);
        let (_, first) = DivRem::div_rem(low, s16);
        Region {
            town: town.try_into().unwrap(),
            book: book.try_into().unwrap(),
            first_location: first.try_into().unwrap(),
            name: name.into(),
        }
    }
}

/// The record's unit tests (ENG-03, ENG-01 §3.5): it round-trips, sits at its documented bits, and
/// refuses a name too long.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::content::Record;
    use super::{Region, RegionTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 82877)] // ceil(1.05 × 78930 measured)
    fn test_region_round_trip() {
        let region = RegionTrait::new(0xFFFF, 2, 0xFFFF, 'Fifteen letters');
        assert(Record::unpack(region.pack()) == region, 'round trip');
        let zero = RegionTrait::new(0, 0, 0, 0);
        assert(zero.pack() == array![LIVE].span(), 'empty is LIVE');
        assert(Record::<Region>::unpack(zero.pack()) == zero, 'zero round trip');
        // Bits: town 0, book 16, first location 32, name 128.
        let one = RegionTrait::new(1, 1, 1, 1).pack();
        assert(*one[0] == 1 + 0x10000 + 0x100000000 + TWO_128 + LIVE, 'bits');
    }

    #[test]
    #[available_gas(l2_gas: 17598)] // ceil(1.05 × 16760 measured)
    #[should_panic(expected: 'region: name too long')]
    fn test_region_name_too_long() {
        RegionTrait::new(1, 0, 1, 'Sixteen letters!').pack();
    }
}
