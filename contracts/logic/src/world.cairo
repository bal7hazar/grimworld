//! The bit layouts of the world's registry records: `REGION`, `LOCATION`, `GATE` and both forms of
//! `OUTLINE` (design/01 *World structure*, ADR-0006 *Outlines*; docs/architecture/
//! ENG-01-interfaces.md §3.5, where every width is justified). Each record follows the packing
//! rules (`crate::packing`): no field straddles bit 128, `LIVE` at bit 250 in part 0, and every
//! packer refuses a value wider than its field.
//!
//! Widths:
//! - a content id is a `u16`, as every registry id the frozen layouts hold (`Header.location`,
//!   the bar's skills, a pack's template);
//! - a quest is quiver's id, a `u32` (the registry's id space);
//! - a level, a rank, a count of floors or chunks is a `u8`;
//! - a location is at most 15 × 15 chunks (ENG-01 §3.2): its width and height are 1 to 15, a chunk
//!   index `15 cy + cx` and a tile index in a chunk `15 row + column` are below 225.

use crate::packing::{
    Lanes16, P104, P120, P16, P24, P32, P4, P40, P48, P56, P64, P72, P8, P80, P88, fits, join,
    pack_lanes16, split, unpack_lanes16,
};

// Location types (design/01 *Location types*; design/17 Rifts; design/06 promotion trials).
pub const TOWN: u8 = 1;
pub const OUTPOST: u8 = 2;
pub const ZONE: u8 = 3;
pub const DUNGEON: u8 = 4;
pub const ELITE: u8 = 5;
pub const RIFT: u8 = 6;
pub const TRIAL: u8 = 7;

// Biomes (design/18 *Biomes*, in the order of its table).
pub const MEADOW: u8 = 1;
pub const FOREST: u8 = 2;
pub const CAVE: u8 = 3;
pub const RUIN: u8 = 4;

// Gate kinds (ENG-01 §3.5).
pub const GATE_HUB: u8 = 1;
pub const GATE_LINK: u8 = 2;
pub const GATE_FLOOR: u8 = 3;
pub const GATE_RIFT: u8 = 4;

/// Chunks of a location, and tiles of a chunk: an index is below this (15 × 15, ADR-0006).
pub const INDEX_BOUND: u8 = 225;
/// The chunk of an outline id that names the zone's chunk set (ADR-0006, *Outlines*).
pub const CHUNK_SET: u8 = 255;
/// Bits of an outline: 225 (chunks of a location, or tiles of a chunk), 97 of them in the high
/// limb.
const OUTLINE_HIGH: u128 = 0x2000000000000000000000000; // 2^97

/// The id of an outline record: `location × 256 + chunk`, `CHUNK_SET` for the chunk set.
pub fn outline_id(location: u16, chunk: u8) -> u32 {
    location.into() * 256 + chunk.into()
}

#[inline(always)]
fn index_fits(value: u8, message: felt252) {
    assert(value < INDEX_BOUND, message);
}

/// `REGION`, 1 part (design/01 *Horizontal scaling*).
/// town 0–15 · book 16–31 · first location 32–47 · name 128–247 (a short string of at most 15
/// characters) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Region {
    /// The region's town, a `LOCATION` of type `TOWN`.
    pub town: u16,
    /// Its alchemy book (`BOOK`; design/07); 0 for none.
    pub book: u16,
    /// The first of its locations (design/01: "list of locations").
    pub first_location: u16,
    /// A short string of at most 15 characters.
    pub name: felt252,
}

pub fn pack_region(value: Region) -> felt252 {
    let name: u128 = value.name.try_into().expect('region: name too long');
    fits(name, P120, 'region: name too long');
    join(value.town.into() + value.book.into() * P16 + value.first_location.into() * P32, name)
}

pub fn unpack_region(word: felt252) -> Region {
    let (low, name) = split(word);
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

/// `LOCATION`, 2 parts (design/01, design/17, design/18, ADR-0006).
/// Part 0: type 0–7 · region 8–23 · biome 24–31 · level min 32–39 · level max 40–47 · rank
/// required 48–55 · width 56–63 · height 64–71 (chunks, 1–15) · `N` 72–79 · floors 80–87 · next
/// floor 88–103 · spawn table 104–119 · sealed 120–127 · entry chunk 128–135 · entry tile 136–143
/// · `LIVE`.
/// Part 1: the set pieces, up to 15 `SET_PIECE` ids (`Lanes16`, 0 for none) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Location {
    /// `TOWN` … `TRIAL`.
    pub kind: u8,
    pub region: u16,
    /// `MEADOW` … `RUIN`.
    pub biome: u8,
    /// The level band of its goblins (design/01: "levels within the zone's band").
    pub level_min: u8,
    pub level_max: u8,
    /// The rank required to enter (0 none; design/06, design/17).
    pub rank: u8,
    /// Its extent in chunks, 1 to 15 each (ENG-01 §3.2).
    pub width: u8,
    pub height: u8,
    /// A dungeon floor's target number of chunks, 6 to 12 (ADR-0006); 0 for a zone.
    pub target: u8,
    /// The floors of its dungeon (design/01: D1 has 3; design/17: up to 5).
    pub floors: u8,
    /// The location of the next floor; 0 on the last floor and outside dungeons.
    pub next_floor: u16,
    pub spawn_table: u16,
    /// A sealed Red Rift: no travel back (design/17).
    pub sealed: bool,
    /// Where an adventurer enters: chunk `15 cy + cx`, tile `15 row + column`.
    pub entry_chunk: u8,
    pub entry_tile: u8,
    /// The authored chunks its quotas may place (ADR-0006, *Set pieces*).
    pub set_pieces: Lanes16,
}

pub fn pack_location(value: Location) -> (felt252, felt252) {
    let width: u128 = value.width.into();
    let height: u128 = value.height.into();
    fits(width, P4, 'location: width');
    fits(height, P4, 'location: height');
    index_fits(value.entry_chunk, 'location: entry chunk');
    index_fits(value.entry_tile, 'location: entry tile');
    let sealed: u128 = if value.sealed {
        1
    } else {
        0
    };
    let low: u128 = value.kind.into()
        + value.region.into() * P8
        + value.biome.into() * P24
        + value.level_min.into() * P32
        + value.level_max.into() * P40
        + value.rank.into() * P48
        + width * P56
        + height * P64
        + value.target.into() * P72
        + value.floors.into() * P80
        + value.next_floor.into() * P88
        + value.spawn_table.into() * P104
        + sealed * P120;
    let high: u128 = value.entry_chunk.into() + value.entry_tile.into() * P8;
    (join(low, high), pack_lanes16(value.set_pieces))
}

pub fn unpack_location(part0: felt252, part1: felt252) -> Location {
    let (low, high) = split(part0);
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
    let (entry_tile, entry_chunk) = DivRem::div_rem(high, s8);
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
        set_pieces: unpack_lanes16(part1),
    }
}

/// `GATE`, 1 part (design/01 *Connectivity*, ADR-0006: a gate is an anchor on the outline).
/// source 0–15 · destination 16–31 · source anchor chunk 32–39, tile 40–47 · destination entry
/// chunk 48–55, tile 56–63 · kind 64–71 · rank required 72–79 · quest required 80–111 · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Gate {
    pub source: u16,
    pub destination: u16,
    /// Where the gate stands in the source location (0 and 0 in a hub, which has no map).
    pub anchor_chunk: u8,
    pub anchor_tile: u8,
    /// Where it leads in the destination (0 and 0 into a hub).
    pub entry_chunk: u8,
    pub entry_tile: u8,
    /// `GATE_HUB` … `GATE_RIFT`.
    pub kind: u8,
    /// The rank required (0 none).
    pub rank: u8,
    /// The quest required (quiver's id; 0 none).
    pub quest: u32,
}

pub fn pack_gate(value: Gate) -> felt252 {
    index_fits(value.anchor_chunk, 'gate: anchor chunk');
    index_fits(value.anchor_tile, 'gate: anchor tile');
    index_fits(value.entry_chunk, 'gate: entry chunk');
    index_fits(value.entry_tile, 'gate: entry tile');
    let low: u128 = value.source.into()
        + value.destination.into() * P16
        + value.anchor_chunk.into() * P32
        + value.anchor_tile.into() * P40
        + value.entry_chunk.into() * P48
        + value.entry_tile.into() * P56
        + value.kind.into() * P64
        + value.rank.into() * P72
        + value.quest.into() * P80;
    join(low, 0)
}

pub fn unpack_gate(word: felt252) -> Gate {
    let (low, _) = split(word);
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

/// `OUTLINE`, 1 part, both forms (ADR-0006, *Outlines*): at id `outline_id(location, CHUNK_SET)`
/// the zone's chunk set, bit `15 cy + cx`; at id `outline_id(location, chunk)` the tile mask of a
/// border chunk, bit `15 row + column` (1: the tile belongs to the zone). Bits 0–127 in `low`,
/// 128–224 in `high` · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Outline {
    pub low: u128,
    pub high: u128,
}

pub fn pack_outline(value: Outline) -> felt252 {
    fits(value.high, OUTLINE_HIGH, 'outline: above bit 224');
    join(value.low, value.high)
}

pub fn unpack_outline(word: felt252) -> Outline {
    let (low, high) = split(word);
    Outline { low, high }
}
