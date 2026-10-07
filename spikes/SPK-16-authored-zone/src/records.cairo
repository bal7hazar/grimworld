//! The other records an authored zone adds (proposed for ENG-01 §3.5, built by ENG-09), and the
//! `LOCATION` marker.
//!
//! - `BRIDGE` (kind 27, D-217's reserved bridge plane): one bridge lying in one chunk; composite id
//!   `location × 4096 + chunk × 16 + k`, `k` below its chunk's bridge count; one part: the deck,
//!   bit `15 row + column` (1 = a deck tile), 0–224 · end A 225–232 · end B 233–240 ·
//!   241–249 free · `LIVE`. A one-tile deck with its two ends is valid. Its rules (movement,
//!   sight, combat, traps, the window) are ENG-08b's: the reveal does not read it in format version
//!   1.
//! - `CANDIDATES` (kind 28, D-215 ruling 3): which chunks are candidates of each quota, so that the
//!   draw at entry reads two records, not every chunk; id `location × 2 + k`; three parts, part
//!   `j` the chunk set of quota `3 k + j`, bit `15 cy + cx`, 0–224. The tile of each candidate is
//!   in its `ZONE_CHUNK`.
//! - The `LOCATION` marker: part 0, bits 144–151, the map's format (0 generated, as every
//! location
//!   today; 1 authored, format version 1). `LocationRecord::unpack` reads the entry tile as the
//!   rest of the high limb today: ENG-09 bounds it to 8 bits and reads the marker beside it.

use grimworld_logic::packing::{LIVE, join, split};

pub const BRIDGE: u8 = 27;
pub const CANDIDATES: u8 = 28;
/// The marker's values.
pub const GENERATED: u8 = 0;
pub const AUTHORED: u8 = 1;
/// 2^144 − 2^128 = 2^16 in the high limb: the marker's place.
const MARKER_SHIFT: u128 = 0x10000;
/// 2^97: a 225-bit plane's part in the high limb is below it.
const P97: u128 = 0x2000000000000000000000000;

pub mod errors {
    pub const DECK_ABOVE_224: felt252 = 'bridge: deck above bit 224';
    pub const DECK_EMPTY: felt252 = 'bridge: deck empty';
    pub const END: felt252 = 'bridge: end';
    pub const SET_ABOVE_224: felt252 = 'candidates: above bit 224';
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Bridge {
    pub deck: felt252,
    pub ends: (u8, u8),
}

#[generate_trait]
pub impl BridgeImpl of BridgeTrait {
    fn id(location: u16, chunk: u8, k: u8) -> u32 {
        location.into() * 4096 + chunk.into() * 16 + k.into()
    }

    fn pack(self: @Bridge) -> Span<felt252> {
        let deck: u256 = (*self.deck).into();
        assert(deck.high < P97, errors::DECK_ABOVE_224);
        let (a, b) = *self.ends;
        let high = deck.high + (a.into() + b.into() * 0x100) * P97;
        array![join(deck.low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Bridge {
        let (low, high) = split(*parts[0]);
        let (ends, deck_high) = DivRem::div_rem(high, P97.try_into().unwrap());
        let (b, a) = DivRem::div_rem(ends, 0x100);
        Bridge {
            deck: low.into() + deck_high.into() * 0x100000000000000000000000000000000,
            ends: (a.try_into().unwrap(), (b % 0x100).try_into().unwrap()),
        }
    }
}

#[generate_trait]
pub impl CandidatesImpl of CandidatesTrait {
    fn id(location: u16, k: u8) -> u32 {
        location.into() * 2 + k.into()
    }

    /// Three chunk sets, each below 2^225, `LIVE` in every part.
    fn pack(sets: [felt252; 3]) -> Span<felt252> {
        let mut out: Array<felt252> = array![];
        for set in sets.span() {
            let wide: u256 = (*set).into();
            assert(wide.high < P97, errors::SET_ABOVE_224);
            out.append(*set + LIVE);
        }
        out.span()
    }

    fn unpack(parts: Span<felt252>) -> [felt252; 3] {
        [*parts[0] - LIVE, *parts[1] - LIVE, *parts[2] - LIVE]
    }
}

#[generate_trait]
pub impl MarkerImpl of MarkerTrait {
    /// The map's format a `LOCATION`'s part 0 carries.
    fn read(part0: felt252) -> u8 {
        let (_, high) = split(part0);
        let (above, _) = DivRem::div_rem(high, MARKER_SHIFT.try_into().unwrap());
        let (_, marker) = DivRem::div_rem(above, 0x100);
        marker.try_into().unwrap()
    }

    /// Part 0 with its marker set (the field 0 before).
    fn write(part0: felt252, marker: u8) -> felt252 {
        part0 + (marker.into() * MARKER_SHIFT.into()) * 0x100000000000000000000000000000000
    }
}
