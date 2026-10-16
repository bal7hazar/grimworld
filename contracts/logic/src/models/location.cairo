//! `LOCATION`: its constructor, its checks and its record (layout: `models::index::Location`).

use crate::helpers::packing::{
    Lanes16, Lanes16Trait, P104, P120, P16, P24, P32, P40, P48, P56, P64, P72, P8, P80, P88,
    PackingTrait,
};
use crate::types::content::{LOCATION, Record};
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
/// The fewest chunks of a dungeon floor, its `N` (CM-9: 6 to 12; R-40). The most is
/// `types::reveal::outline::MAX_CHUNKS`, `Registry`'s own check.
pub const MIN_FLOOR: u8 = 6;

pub mod errors {
    pub const WIDTH: felt252 = 'location: width';
    pub const HEIGHT: felt252 = 'location: height';
    pub const ENTRY_CHUNK: felt252 = 'location: entry chunk';
    pub const ENTRY_TILE: felt252 = 'location: entry tile';
    /// A map format this reader does not know (ENG-09).
    pub const MAP: felt252 = 'location: map';
    /// A dungeon floor whose rectangle is not larger than its `N` (R-28, ENG-R1c's bound 4).
    pub const FLOOR_RECTANGLE: felt252 = 'location: floor rectangle';
    /// A dungeon floor of fewer than `MIN_FLOOR` chunks (R-40, ENG-R1c's bound 5).
    pub const FLOOR_FEW: felt252 = 'location: floor under 6 chunks';
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
    fn assert_band(self: @Location) {
        assert(*self.level_min != 0 || *self.level_max != 255, errors::LEVEL_BAND);
    }

    /// `Registry`'s check of a `LOCATION` write, for a dungeon floor (`N` > 0, the engine's
    /// `SiteTrait::emerging`, whatever the kind): R-40 (ENG-R1c's bound 5, review t-0099 note 5),
    /// at least `MIN_FLOOR` chunks, else its exit and its Heart may find no layer beyond the
    /// entry and stay owed; R-28 (ENG-R1c's bound 4, built by ENG-09; re-audits t-0075 and
    /// t-0077, minor 3), its `width × height` above its `N`, else its last chunks can be walled
    /// in (ADR-0006 *Outlines*). A location without `N` is not a floor: nothing to check.
    fn assert_floor(self: @Location) {
        let target = *self.target;
        if target != 0 {
            assert(target >= MIN_FLOOR, errors::FLOOR_FEW);
            let area: u16 = (*self.width).into() * (*self.height).into();
            assert(area > target.into(), errors::FLOOR_RECTANGLE);
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
        array![PackingTrait::join(low, high), Lanes16Trait::pack(*self.set_pieces)].span()
    }

    fn unpack(parts: Span<felt252>) -> Location {
        let (low, high) = PackingTrait::split(*parts[0]);
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
            set_pieces: Lanes16Trait::unpack(*parts[1]),
            map: map.try_into().unwrap(),
        }
    }
}

/// The record's unit tests (ENG-03, ENG-01 §3.5; ENG-06): every field round-trips at its maximum,
/// sits at its documented bit, and a value wider than its field is refused; a tile of a chunk as a
/// global position, and which locations have a map.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::{LIVE, Lanes16};
    use crate::types::content::{Record, exists};
    use super::{Location, LocationTrait, kind, kind as location_kind};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// The records these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        fn location_max() -> Location {
            LocationTrait::new(
                0xFF,
                0xFFFF,
                0xFF,
                0xFF,
                0xFF,
                0xFF,
                15,
                15,
                0xFF,
                0xFF,
                0xFFFF,
                0xFFFF,
                true,
                224,
                224,
                Lanes16 { lanes: [0xFFFF, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0xFFFF] },
            )
        }

        fn location_zero() -> Location {
            LocationTrait::new(
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, 0, 0, Lanes16 { lanes: [0; 15] },
            )
        }
    }

    #[test]
    #[available_gas(l2_gas: 755286)] // ceil(1.05 × 719320 measured)
    fn test_location_round_trip() {
        let top = Fixture::location_max();
        let parts = top.pack();
        assert(parts.len() == 2, 'two parts');
        assert(Record::<Location>::unpack(parts) == top, 'round trip');
        let zero = Fixture::location_zero();
        let parts = zero.pack();
        assert(parts == array![LIVE, LIVE].span(), 'empty is LIVE');
        assert(Record::<Location>::unpack(parts) == zero, 'zero round trip');
    }

    #[test]
    #[available_gas(l2_gas: 240776)] // ceil(1.05 × 229310 measured)
    fn test_location_bits() {
        let value = LocationTrait::new(
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, true, 1, 1, Lanes16 { lanes: [0; 15] },
        );
        let parts = value.pack();
        // type 0 · region 8 · biome 24 · level min 32 · level max 40 · rank 48 · width 56 ·
        // height 64 · N 72 · floors 80 · next floor 88 · spawn table 104 · sealed 120 · entry
        // chunk 128 · entry tile 136.
        let low: felt252 = 0x1000100010101010101010101000101;
        assert(*parts[0] == low + TWO_128 + 0x100 * TWO_128 + LIVE, 'bits');
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'location: width')]
    fn test_location_width_refused() {
        let mut value = Fixture::location_zero();
        value.width = 16;
        value.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'location: height')]
    fn test_location_height_refused() {
        let mut value = Fixture::location_zero();
        value.height = 16;
        value.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'location: entry chunk')]
    fn test_location_entry_chunk_refused() {
        let mut value = Fixture::location_zero();
        value.entry_chunk = 225;
        value.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'location: entry tile')]
    fn test_location_entry_tile_refused() {
        let mut value = Fixture::location_zero();
        value.entry_tile = 225;
        value.pack();
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_position() {
        assert(LocationTrait::position(0, 0) == (0, 0), 'origin');
        assert(LocationTrait::position(0, 105) == (0, 7), 'row 7');
        assert(LocationTrait::position(16, 110) == (20, 22), 'chunk (1, 1)');
        assert(LocationTrait::position(112, 112) == (112, 112), 'the centre');
        assert(LocationTrait::position(224, 224) == (224, 224), 'the far corner');
    }

    #[test]
    #[available_gas(l2_gas: 26387)] // ceil(1.05 × 25130 measured)
    fn test_has_map() {
        let place = |kind: u8| {
            LocationTrait::new(
                kind, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, false, 0, 0, Lanes16 { lanes: [0; 15] },
            )
        };
        assert(
            !place(location_kind::TOWN).has_map() && !place(location_kind::OUTPOST).has_map(),
            'hubs',
        );
        for kind in array![
            location_kind::ZONE, location_kind::DUNGEON, location_kind::ELITE, location_kind::RIFT,
            location_kind::TRIAL,
        ] {
            assert(place(kind).has_map(), 'an instance');
        }
        assert(!exists(array![0, 5].span()) && exists(array![1, 0].span()), 'exists: part 0');
    }
}
