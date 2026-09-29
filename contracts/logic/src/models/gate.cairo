//! `GATE`: its constructor, its checks and its record (layout: `models::index::Gate`).

use crate::content::{GATE, Record};
use crate::packing::{P16, P32, P40, P48, P56, P64, P72, P8, P80, join, split};
pub use super::index::Gate;
use super::location::LocationAssert;

/// Gate kinds (ENG-01 §3.5).
pub mod kind {
    pub const HUB: u8 = 1;
    pub const LINK: u8 = 2;
    pub const FLOOR: u8 = 3;
    pub const RIFT: u8 = 4;
}

pub mod errors {
    pub const ANCHOR_CHUNK: felt252 = 'gate: anchor chunk';
    pub const ANCHOR_TILE: felt252 = 'gate: anchor tile';
    pub const ENTRY_CHUNK: felt252 = 'gate: entry chunk';
    pub const ENTRY_TILE: felt252 = 'gate: entry tile';
}

#[generate_trait]
pub impl GateImpl of GateTrait {
    fn new(
        source: u16,
        destination: u16,
        anchor_chunk: u8,
        anchor_tile: u8,
        entry_chunk: u8,
        entry_tile: u8,
        kind: u8,
        rank: u8,
        quest: u32,
    ) -> Gate {
        Gate {
            source,
            destination,
            anchor_chunk,
            anchor_tile,
            entry_chunk,
            entry_tile,
            kind,
            rank,
            quest,
        }
    }
}

#[generate_trait]
pub impl GateAssert of GateAssertTrait {
    /// The anchor and the entry are chunks of their locations and tiles of those chunks.
    #[inline(always)]
    fn assert_valid(self: @Gate) {
        LocationAssert::assert_index(*self.anchor_chunk, errors::ANCHOR_CHUNK);
        LocationAssert::assert_index(*self.anchor_tile, errors::ANCHOR_TILE);
        LocationAssert::assert_index(*self.entry_chunk, errors::ENTRY_CHUNK);
        LocationAssert::assert_index(*self.entry_tile, errors::ENTRY_TILE);
    }
}

pub impl GateRecord of Record<Gate> {
    const KIND: u8 = GATE;

    fn pack(self: @Gate) -> Span<felt252> {
        self.assert_valid();
        let low: u128 = (*self.source).into()
            + (*self.destination).into() * P16
            + (*self.anchor_chunk).into() * P32
            + (*self.anchor_tile).into() * P40
            + (*self.entry_chunk).into() * P48
            + (*self.entry_tile).into() * P56
            + (*self.kind).into() * P64
            + (*self.rank).into() * P72
            + (*self.quest).into() * P80;
        array![join(low, 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Gate {
        let (low, _) = split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (low, source) = DivRem::div_rem(low, s16);
        let (low, destination) = DivRem::div_rem(low, s16);
        let (low, anchor_chunk) = DivRem::div_rem(low, s8);
        let (low, anchor_tile) = DivRem::div_rem(low, s8);
        let (low, entry_chunk) = DivRem::div_rem(low, s8);
        let (low, entry_tile) = DivRem::div_rem(low, s8);
        let (low, kind) = DivRem::div_rem(low, s8);
        let (quest, rank) = DivRem::div_rem(low, s8);
        Gate {
            source: source.try_into().unwrap(),
            destination: destination.try_into().unwrap(),
            anchor_chunk: anchor_chunk.try_into().unwrap(),
            anchor_tile: anchor_tile.try_into().unwrap(),
            entry_chunk: entry_chunk.try_into().unwrap(),
            entry_tile: entry_tile.try_into().unwrap(),
            kind: kind.try_into().unwrap(),
            rank: rank.try_into().unwrap(),
            quest: quest.try_into().unwrap(),
        }
    }
}
