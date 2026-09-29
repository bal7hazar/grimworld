//! `OUTLINE`: its id, its constructor, its checks and its record (layout:
//! `models::index::Outline`).

use crate::content::{OUTLINE, Record};
use crate::packing::{join, split};
pub use super::index::Outline;

/// The chunk of an outline id that names the zone's chunk set (ADR-0006, *Outlines*).
pub const CHUNK_SET: u8 = 255;
/// Bits of an outline: 225 (chunks of a location, or tiles of a chunk), 97 of them in the high
/// limb.
const HIGH_BOUND: u128 = 0x2000000000000000000000000; // 2^97

pub mod errors {
    pub const ABOVE_BIT_224: felt252 = 'outline: above bit 224';
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
}

#[generate_trait]
pub impl OutlineAssert of OutlineAssertTrait {
    #[inline(always)]
    fn assert_valid(self: @Outline) {
        assert(*self.high < HIGH_BOUND, errors::ABOVE_BIT_224);
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
