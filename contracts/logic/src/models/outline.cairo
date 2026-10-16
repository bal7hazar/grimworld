//! `OUTLINE`: its id, its constructor, its checks and its record (layout:
//! `models::index::Outline`).

use crate::helpers::packing::PackingTrait;
use crate::types::content::{OUTLINE, Record};
use crate::types::reveal::board::BoardTrait;
pub use super::index::Outline;

/// The chunk of an outline id that names the zone's chunk set (ADR-0006, *Outlines*).
pub const CHUNK_SET: u8 = 255;
/// Bits of an outline: 225 (chunks of a location, or tiles of a chunk), 97 of them in the high
/// limb.
const HIGH_BOUND: u128 = 0x2000000000000000000000000; // 2^97

pub mod errors {
    pub const ABOVE_BIT_224: felt252 = 'outline: above bit 224';
    /// R-11: a chunk of the set outside the location's rectangle.
    pub const OUTSIDE: felt252 = 'zone: set outside rectangle';
}

#[generate_trait]
pub impl OutlineImpl of OutlineTrait {
    fn new(low: u128, high: u128) -> Outline {
        Outline { low, high }
    }

    /// The id of an outline record: `location × 256 + chunk`, `CHUNK_SET` for the chunk set.
    fn id(location: u16, chunk: u8) -> u32 {
        location.into() * 256 + chunk.into()
    }

    /// The outline's bitmap, bit `15 cy + cx` or `15 row + column`.
    #[inline(always)]
    fn bits(self: @Outline) -> felt252 {
        (*self.low).into() + (*self.high).into() * 0x100000000000000000000000000000000
    }

    /// The chunks of a `width × height` rectangle, bit `15 cy + cx`.
    fn rectangle(width: u8, height: u8) -> felt252 {
        let row = BoardTrait::pow(width) - 1;
        let mut out: felt252 = 0;
        let mut cy: u8 = 0;
        while cy != height {
            out += row * BoardTrait::pow(15 * cy);
            cy += 1;
        }
        out
    }
}

#[generate_trait]
pub impl OutlineAssert of OutlineAssertTrait {
    #[inline(always)]
    fn assert_valid(self: @Outline) {
        assert(*self.high < HIGH_BOUND, errors::ABOVE_BIT_224);
    }

    /// R-11 (ENG-R1c's bound 1, built by ENG-09), at a chunk set's write (it reads `LOCATION`; a
    /// `LOCATION` rewrite reads the chunk set the other way): every chunk of `chunk_set` within the
    /// `width × height` rectangle.
    fn assert_within(chunk_set: felt252, width: u8, height: u8) {
        let inside = OutlineTrait::rectangle(width, height);
        assert(BoardTrait::minus(chunk_set, inside) == 0, errors::OUTSIDE);
    }
}

pub impl OutlineRecord of Record<Outline> {
    const KIND: u8 = OUTLINE;

    fn pack(self: @Outline) -> Span<felt252> {
        self.assert_valid();
        array![PackingTrait::join(*self.low, *self.high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Outline {
        let (low, high) = PackingTrait::split(*parts[0]);
        Outline { low, high }
    }
}

/// The record's unit tests (ENG-03, ENG-01 §3.5): all 225 bits round-trip, and a bit above 224 is
/// refused.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::models::location::kind;
    use crate::types::content::Record;
    use super::{CHUNK_SET, Outline, OutlineTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 22292)] // ceil(1.05 × 21230 measured)
    fn test_outline_round_trip() {
        // All 225 bits set: 128 in the low limb, 97 in the high one.
        let full = OutlineTrait::new(
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 0x1FFFFFFFFFFFFFFFFFFFFFFFF,
        );
        assert(Record::<Outline>::unpack(full.pack()) == full, 'round trip');
        let empty = OutlineTrait::new(0, 0);
        assert(empty.pack() == array![LIVE].span(), 'empty is LIVE');
        assert(Record::<Outline>::unpack(array![LIVE].span()) == empty, 'empty round trip');
        // Bit 128 is the high limb's bit 0.
        assert(*OutlineTrait::new(0, 1).pack()[0] == TWO_128 + LIVE, 'bit 128');
        assert(OutlineTrait::id(2, CHUNK_SET) == 767, 'chunk set id');
        assert(OutlineTrait::id(0xFFFF, 224) == 0xFFFFE0, 'border chunk id');
        assert(kind::ZONE != kind::DUNGEON, 'kinds');
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'outline: above bit 224')]
    fn test_outline_above_bit_224_refused() {
        OutlineTrait::new(0, 0x2000000000000000000000000).pack();
    }
}
