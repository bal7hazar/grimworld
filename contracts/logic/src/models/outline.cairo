//! `OUTLINE`: its id, its constructor, its checks and its record (layout:
//! `models::index::Outline`).

use crate::content::{OUTLINE, Record};
use crate::packing::{join, split};
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
        array![join(*self.low, *self.high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Outline {
        let (low, high) = split(*parts[0]);
        Outline { low, high }
    }
}
