//! `BRIDGE`: its id, its checks and its record (layout: `models::index::Bridge`; ENG-01 §3.5,
//! ADR-0008, built by ENG-09). One bridge of an authored zone, lying in one chunk (D-217, R-36);
//! one level (D-227): its deck is walkable ground over water in the chunk's plane (the converter
//! writes it so), and no rule of play reads the record, which the client draws.

use crate::content::{BRIDGE, Record};
use crate::packing::{join, split};
use crate::types::reveal::board::BoardTrait;
use super::zone_chunk::{ZoneChunk, ZoneChunkTrait};
pub use super::index::Bridge;

/// 2^97: a 225-bit plane's part in the high limb is below it (bits 128–224).
const P97: u128 = 0x2000000000000000000000000;

pub mod errors {
    pub const DECK_ABOVE_224: felt252 = 'bridge: deck above bit 224';
    /// R-33: no deck tile.
    pub const DECK_EMPTY: felt252 = 'bridge: deck empty';
    /// R-33: an end that is not a tile, on the deck, or both ends one tile.
    pub const END: felt252 = 'bridge: end';
    /// R-34: an end not walkable.
    pub const END_NOT_FLOOR: felt252 = 'bridge: end not floor';
    /// R-34: an end next to no deck tile.
    pub const APART: felt252 = 'bridge: end not by the deck';
    /// R-34 extended (ADR-0008 rule 1): a deck tile not walkable.
    pub const DECK_NOT_FLOOR: felt252 = 'bridge: deck not floor';
    /// R-35: an index not below its chunk's count.
    pub const INDEX: felt252 = 'bridge: index';
    /// R-37 (ADR-0008 rule 5): authored content on a deck or an end.
    pub const TAKEN: felt252 = 'bridge: tile taken';
}

#[generate_trait]
pub impl BridgeImpl of BridgeTrait {
    /// The record's id: `location × 4096 + chunk × 16 + k`.
    #[inline(always)]
    fn id(location: u16, chunk: u8, k: u8) -> u32 {
        location.into() * 4096 + chunk.into() * 16 + k.into()
    }

    /// Its deck and both ends.
    fn tiles(self: @Bridge) -> felt252 {
        let (a, b) = *self.ends;
        BoardTrait::or(BoardTrait::or(*self.deck, BoardTrait::pow(a)), BoardTrait::pow(b))
    }
}

#[generate_trait]
pub impl BridgeAssert of BridgeAssertTrait {
    /// R-33, at a `BRIDGE` write (the record alone): a deck, and two distinct ends, tiles of the
    /// chunk, off the deck. A one-tile deck with its two ends is valid (D-217, CLI-09e §1).
    fn assert_legal(self: @Bridge) {
        let deck = *self.deck;
        assert(deck != 0, errors::DECK_EMPTY);
        let (a, b) = *self.ends;
        assert(
            a < 225 && b < 225 && a != b && !BoardTrait::has(deck, a) && !BoardTrait::has(deck, b),
            errors::END,
        );
    }

    /// R-35, R-34 (extended to the deck) and R-37, at a `BRIDGE` write (it reads its chunk's
    /// `ZONE_CHUNK`; that chunk's rewrite re-runs them for each of its bridges): `k` below the
    /// chunk's count; each end walkable and next to a deck tile; every deck tile walkable; no
    /// spawn point, object or candidate tile of the chunk on the deck or an end. `odd`: whether the
    /// chunk's row 0 is a globally odd row (ADR-0006 §4).
    fn assert_on(self: @Bridge, k: u8, record: @ZoneChunk, odd: bool) {
        assert(k < *record.bridges, errors::INDEX);
        let (a, b) = *self.ends;
        assert(record.floor(a) && record.floor(b), errors::END_NOT_FLOOR);
        let near = BoardTrait::dilate(*self.deck, odd);
        assert(BoardTrait::has(near, a) && BoardTrait::has(near, b), errors::APART);
        assert(BoardTrait::and(*self.deck, *record.walls) == 0, errors::DECK_NOT_FLOOR);
        self.assert_clear(record.content());
    }

    /// R-37 against `tiles` (authored content: the chunk's placements, a gate's anchor, the
    /// entry): none on the deck or an end.
    #[inline(always)]
    fn assert_clear(self: @Bridge, tiles: felt252) {
        assert(BoardTrait::and(self.tiles(), tiles) == 0, errors::TAKEN);
    }
}

pub impl BridgeRecord of Record<Bridge> {
    const KIND: u8 = BRIDGE;

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

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use crate::types::reveal::board::BoardTrait;
    use super::{Bridge, BridgeAssert, BridgeRecord, BridgeTrait};

    #[test]
    fn test_bridge_bits_and_round_trip() {
        let bridge = Bridge { deck: BoardTrait::pow(224) + BoardTrait::pow(3), ends: (2, 0xe0) };
        let parts = bridge.pack();
        let wide: u256 = (*parts[0] - LIVE).into();
        assert(wide.high / 0x2000000000000000000000000 == 2 + 0xe0 * 0x100, 'ends');
        assert(BridgeRecord::unpack(parts) == bridge, 'round trip');
        assert(BridgeTrait::id(2, 16, 3) == 2 * 4096 + 16 * 16 + 3, 'id');
        bridge.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'bridge: end')]
    fn test_bridge_end_on_the_deck_refused() {
        Bridge { deck: BoardTrait::pow(3), ends: (3, 4) }.assert_legal();
    }
}
