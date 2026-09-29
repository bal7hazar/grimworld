//! `REGION`: its constructor, its checks and its record (layout: `models::index::Region`).

use crate::content::{REGION, Record};
use crate::packing::{P120, P16, P32, join, split};
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
        array![join(low, name)].span()
    }

    fn unpack(parts: Span<felt252>) -> Region {
        let (low, name) = split(*parts[0]);
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
