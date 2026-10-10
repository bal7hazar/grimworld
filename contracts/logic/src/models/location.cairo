//! `LOCATION`: its constructor, its checks and its record (layout: `models::index::Location`).

use crate::content::{LOCATION, Record};
use crate::packing::{
    Lanes16, P104, P120, P16, P24, P32, P40, P48, P56, P64, P72, P8, P80, P88, join, pack_lanes16,
    split, unpack_lanes16,
};
pub use super::index::Location;

/// Location types (design/01 *Location types*; design/17 Rifts; design/06 promotion trials).
pub mod kind {
    pub const TOWN: u8 = 1;
    pub const OUTPOST: u8 = 2;
    pub const ZONE: u8 = 3;
    pub const DUNGEON: u8 = 4;
    pub const ELITE: u8 = 5;
    pub const RIFT: u8 = 6;
    pub const TRIAL: u8 = 7;
}

/// Biomes (design/18 *Biomes*, in the order of its table).
pub mod biome {
    pub const MEADOW: u8 = 1;
    pub const FOREST: u8 = 2;
    pub const CAVE: u8 = 3;
    pub const RUIN: u8 = 4;
}

/// The map's format (`Location.map`, part 0 bits 144–151; ENG-08's marker, D-215 ruling 7).
pub mod map {
    /// Generated at reveal (ADR-0006 §2): dungeons, and a zone not authored (the fallback).
    pub const GENERATED: u8 = 0;
    /// Authored with the map editor, format version 1 (D-214): `ZONE_CHUNK`, `CANDIDATES`.
    pub const AUTHORED: u8 = 1;
}

/// Chunks of a location, and tiles of a chunk: an index is below this (15 × 15, ADR-0006).
pub const INDEX_BOUND: u8 = 225;
/// A width or height in chunks is below this: 4 bits, at most 15 (ENG-01 §3.2).
const SIDE_BOUND: u8 = 16;

pub mod errors {
    pub const WIDTH: felt252 = 'location: width';
    pub const HEIGHT: felt252 = 'location: height';
    pub const ENTRY_CHUNK: felt252 = 'location: entry chunk';
    pub const ENTRY_TILE: felt252 = 'location: entry tile';
    /// A map format this reader does not know (ENG-09).
    pub const MAP: felt252 = 'location: map';
    /// A dungeon floor whose rectangle is not larger than its `N` (R-28, ENG-R1c's bound 4).
    pub const FLOOR_RECTANGLE: felt252 = 'location: floor rectangle';
    /// An authored zone's band of more than 255 levels (R-39, audit t-0131).
    pub const LEVEL_BAND: felt252 = 'zone: level band';
}

#[generate_trait]
pub impl LocationImpl of LocationTrait {
    fn new(
        kind: u8,
        region: u16,
        biome: u8,
        level_min: u8,
        level_max: u8,
        rank: u8,
        width: u8,
        height: u8,
        target: u8,
        floors: u8,
        next_floor: u16,
        spawn_table: u16,
        sealed: bool,
        entry_chunk: u8,
        entry_tile: u8,
        set_pieces: Lanes16,
    ) -> Location {
        Location {
            kind,
            region,
            biome,
            level_min,
            level_max,
            rank,
            width,
            height,
            target,
            floors,
            next_floor,
            spawn_table,
            sealed,
            entry_chunk,
            entry_tile,
            set_pieces,
            map: map::GENERATED,
        }
    }

    /// The location with its map's format (`map::AUTHORED` for a zone drawn with the editor).
    fn with_map(self: Location, map: u8) -> Location {
        Location { map, ..self }
    }

    /// Whether its terrain is authored (D-214): read from the registry, never generated.
    #[inline(always)]
    fn authored(self: @Location) -> bool {
        *self.map == map::AUTHORED
    }

    /// The global tile `(x, y)` of tile `15 row + column` of chunk `15 cy + cx`: `x = 15 cx +
    /// column`, `y = 15 cy + row`, both below 225 (ENG-01 §3.2).
    #[inline(always)]
    fn position(chunk: u8, tile: u8) -> (u8, u8) {
        let side: NonZero<u8> = 15;
        let (cy, cx) = DivRem::div_rem(chunk, side);
        let (row, column) = DivRem::div_rem(tile, side);
        (cx * 15 + column, cy * 15 + row)
    }

    /// A location with a map, played in an instance (design/01 *Location types*): not a town nor
    /// an outpost, which are hubs.
    #[inline(always)]
    fn has_map(self: @Location) -> bool {
        *self.kind != kind::TOWN && *self.kind != kind::OUTPOST
    }
}

#[generate_trait]
pub impl LocationAssert of LocationAssertTrait {
    /// A chunk index of a location, or a tile index of a chunk: below 225.
    #[inline(always)]
    fn assert_index(index: u8, message: felt252) {
        assert(index < INDEX_BOUND, message);
    }

    /// Width and height fit 4 bits (1–15 chunks); the entry is a chunk and a tile of it.
    #[inline(always)]
    fn assert_valid(self: @Location) {
        assert(*self.width < SIDE_BOUND, errors::WIDTH);
        assert(*self.height < SIDE_BOUND, errors::HEIGHT);
        Self::assert_index(*self.entry_chunk, errors::ENTRY_CHUNK);
        Self::assert_index(*self.entry_tile, errors::ENTRY_TILE);
        assert(*self.map <= map::AUTHORED, errors::MAP);
    }

    /// R-39 (audit t-0131), at an authored zone's `LOCATION` write: its level band at most 255
    /// levels, so that a chunk's level, drawn uniformly in it with a byte's bound, never overflows
    /// (D-140). A generated zone's levels are not drawn so (`PlacementTrait::level`).
    /// R-28 (ENG-R1c's bound 4, built by ENG-09): a dungeon floor's `width × height` above its
    /// `N`, else its last chunks can be walled in (ADR-0006 *Outlines*). `Registry`'s check of a
    /// `LOCATION` write.
    fn assert_band(self: @Location) {
        assert(*self.level_min != 0 || *self.level_max != 255, errors::LEVEL_BAND);
    }

    /// R-28 (see above).
    fn assert_floor_rectangle(self: @Location) {
        if *self.kind == kind::DUNGEON {
            let area: u16 = (*self.width).into() * (*self.height).into();
            assert(area > (*self.target).into(), errors::FLOOR_RECTANGLE);
        }
    }
}

pub impl LocationRecord of Record<Location> {
    const KIND: u8 = LOCATION;

    fn pack(self: @Location) -> Span<felt252> {
        self.assert_valid();
        let sealed: u128 = if *self.sealed {
            1
        } else {
            0
        };
        let low: u128 = (*self.kind).into()
            + (*self.region).into() * P8
            + (*self.biome).into() * P24
            + (*self.level_min).into() * P32
            + (*self.level_max).into() * P40
            + (*self.rank).into() * P48
            + (*self.width).into() * P56
            + (*self.height).into() * P64
            + (*self.target).into() * P72
            + (*self.floors).into() * P80
            + (*self.next_floor).into() * P88
            + (*self.spawn_table).into() * P104
            + sealed * P120;
        let high: u128 = (*self.entry_chunk).into()
            + (*self.entry_tile).into() * P8
            + (*self.map).into() * P16;
        array![join(low, high), pack_lanes16(*self.set_pieces)].span()
    }

    fn unpack(parts: Span<felt252>) -> Location {
        let (low, high) = split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (low, kind) = DivRem::div_rem(low, s8);
        let (low, region) = DivRem::div_rem(low, s16);
        let (low, biome) = DivRem::div_rem(low, s8);
        let (low, level_min) = DivRem::div_rem(low, s8);
        let (low, level_max) = DivRem::div_rem(low, s8);
        let (low, rank) = DivRem::div_rem(low, s8);
        let (low, width) = DivRem::div_rem(low, s8);
        let (low, height) = DivRem::div_rem(low, s8);
        let (low, target) = DivRem::div_rem(low, s8);
        let (low, floors) = DivRem::div_rem(low, s8);
        let (low, next_floor) = DivRem::div_rem(low, s16);
        let (sealed, spawn_table) = DivRem::div_rem(low, s16);
        let (high, entry_chunk) = DivRem::div_rem(high, s8);
        let (map, entry_tile) = DivRem::div_rem(high, s8);
        Location {
            kind: kind.try_into().unwrap(),
            region: region.try_into().unwrap(),
            biome: biome.try_into().unwrap(),
            level_min: level_min.try_into().unwrap(),
            level_max: level_max.try_into().unwrap(),
            rank: rank.try_into().unwrap(),
            width: width.try_into().unwrap(),
            height: height.try_into().unwrap(),
            target: target.try_into().unwrap(),
            floors: floors.try_into().unwrap(),
            next_floor: next_floor.try_into().unwrap(),
            spawn_table: spawn_table.try_into().unwrap(),
            sealed: sealed != 0,
            entry_chunk: entry_chunk.try_into().unwrap(),
            entry_tile: entry_tile.try_into().unwrap(),
            set_pieces: unpack_lanes16(*parts[1]),
            map: map.try_into().unwrap(),
        }
    }
}
