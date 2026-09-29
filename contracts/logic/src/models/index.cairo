//! The world's registry records, together (D-143, docs/CAIRO.md §7): `REGION`, `LOCATION`,
//! `GATE` and both forms of `OUTLINE` (design/01 *World structure*, ADR-0006 *Outlines*;
//! docs/architecture/ENG-01-interfaces.md §3.5, where every width is justified). Each model's file
//! holds its constructor, its checks, its errors and its packing into the record's parts
//! (`content::Record`), which follows the packing rules: no field straddles bit 128, `LIVE` at bit
//! 250 in part 0, a value wider than its field refused.
//!
//! Widths:
//! - a content id is a `u16`, as every registry id the frozen layouts hold (`Header.location`,
//!   the bar's skills, a pack's template);
//! - a quest is quiver's id, a `u32` (the registry's id space);
//! - a level, a rank, a count of floors or chunks is a `u8`;
//! - a location is at most 15 × 15 chunks (ENG-01 §3.2): its width and height are 1 to 15, a
//! chunk
//!   index `15 cy + cx` and a tile index in a chunk `15 row + column` are below 225.

use crate::packing::Lanes16;

/// `REGION`, 1 part (design/01 *Horizontal scaling*).
/// town 0–15 · book 16–31 · first location 32–47 · name 128–247 (a short string of at
/// most 15 characters) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Region {
    /// The region's town, a `LOCATION` of kind `TOWN`.
    pub town: u16,
    /// Its alchemy book (`BOOK`; design/07); 0 for none.
    pub book: u16,
    /// The first of its locations (design/01: "list of locations").
    pub first_location: u16,
    /// A short string of at most 15 characters.
    pub name: felt252,
}

/// `LOCATION`, 2 parts (design/01, design/17, design/18, ADR-0006).
/// Part 0: type 0–7 · region 8–23 · biome 24–31 · level min 32–39 · level max 40–47
/// · rank required 48–55 · width 56–63 · height 64–71 (chunks, 1–15) · `N` 72–79 ·
/// floors 80–87 · next floor 88–103 · spawn table 104–119 · sealed 120–127 · entry
/// chunk 128–135 · entry tile 136–143 · `LIVE`.
/// Part 1: the set pieces, up to 15 `SET_PIECE` ids (`Lanes16`, 0 for none) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Location {
    /// `location::kind::TOWN` … `TRIAL`.
    pub kind: u8,
    pub region: u16,
    /// `location::biome::MEADOW` … `RUIN`.
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

/// `GATE`, 1 part (design/01 *Connectivity*, ADR-0006: a gate is an anchor on the outline).
/// source 0–15 · destination 16–31 · source anchor chunk 32–39, tile 40–47 · destination
/// entry chunk 48–55, tile 56–63 · kind 64–71 · rank required 72–79 · quest required
/// 80–111 · `LIVE`.
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
    /// `gate::kind::HUB` … `RIFT`.
    pub kind: u8,
    /// The rank required (0 none).
    pub rank: u8,
    /// The quest required (quiver's id; 0 none).
    pub quest: u32,
}

/// `OUTLINE`, 1 part, both forms (ADR-0006, *Outlines*): at id `Outline::id(location,
/// CHUNK_SET)` the zone's chunk set, bit `15 cy + cx`; at id `Outline::id(location, chunk)` the
/// tile mask of a border chunk, bit `15 row + column` (1: the tile belongs to the zone). Bits
/// 0–127 in `low`, 128–224 in `high` · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Outline {
    pub low: u128,
    pub high: u128,
}
