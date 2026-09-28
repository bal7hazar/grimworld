//! N-3: the window of ADR-0006 §4 and D-120, assembled from the chunks at each tick.
//!
//! A chunk is 15 x 15 (one felt per layer), the window 15 columns x 16 rows (one felt per layer),
//! both row-major with bit `15 y + x` (origami_hexmap's convention). The window always overlaps
//! 2 rows of chunks and 1 or 2 columns: 2 or 4 chunks. Window and chunk share the width, so a piece
//! of a chunk moves into the window by one shift of `15 dy + dx` bits. Per chunk and per layer:
//! one mask, the product of a column table and a row table (`tables.cairo`), one AND, one field
//! product by a power of two or its inverse (exact: the masked bits land inside the window). No
//! loop, over rows or anything else.

use origami_hexmap::helpers::bits::Bits;
use crate::tables::{COLS_FROM, COLS_TO, ROWS_FROM, ROWS_TO, WINDOW_INTERIOR};

/// Width of a chunk and of the window; height of a chunk.
pub const WIDTH: u8 = 15;
/// Rows of the window (D-120).
pub const HEIGHT: u8 = 16;
/// Local tile of the adventurer on an odd global row, (7, 7), and on an even one, (7, 8).
pub const CENTRE_ODD: u8 = 112;
pub const CENTRE_EVEN: u8 = 127;

pub mod errors {
    pub const WINDOW_ODD_ORIGIN: felt252 = 'window: odd origin';
    pub const WINDOW_CHUNKS: felt252 = 'window: wrong chunk count';
}

/// The two layers of a chunk or of a window: walkable tiles and occupied tiles.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Layers {
    pub terrain: felt252,
    pub occupied: felt252,
}

/// Origin of the window that follows an adventurer at global `(x, y)` (ADR-0006 §4): the
/// adventurer on local column 7, on local row 7 when its global row is odd and 8 when it is even,
/// so that the origin's row is even. The adventurer must stand at `x >= 7`, `y >= 8`.
/// # Returns
/// * The origin `(x, y)` and the adventurer's local tile
#[inline]
pub fn window_origin(x: u8, y: u8) -> (u8, u8, u8) {
    let (_, odd) = DivRem::div_rem(y, 2);
    if odd == 1 {
        (x - 7, y - 7, CENTRE_ODD)
    } else {
        (x - 7, y - 8, CENTRE_EVEN)
    }
}

/// The chunks the window at an origin overlaps.
/// # Returns
/// * The lowest chunk `(cx0, cy0)` and the origin's offsets `(dx, dy)` in it: 2 chunks
///   `(cx0, cy0)`, `(cx0, cy0 + 1)` when `dx = 0`, else also `(cx0 + 1, cy0)`, `(cx0 + 1, cy0 + 1)`
#[inline]
pub fn window_chunks(origin_x: u8, origin_y: u8) -> (u8, u8, u8, u8) {
    let (cx0, dx) = DivRem::div_rem(origin_x, WIDTH.try_into().unwrap());
    let (cy0, dy) = DivRem::div_rem(origin_y, WIDTH.try_into().unwrap());
    (cx0, cy0, dx, dy)
}

/// `layer & mask`, moved into the window by the field product `shift`.
#[inline(always)]
fn piece(layer: u256, mask: u256, shift: felt252) -> felt252 {
    let (low, _, _) = Bits::bitwise(layer.low, mask.low);
    let (high, _, _) = Bits::bitwise(layer.high, mask.high);
    Bits::to_felt(u256 { low, high }) * shift
}

/// Assemble the window at an origin from the chunks it overlaps (N-3).
/// # Arguments
/// * `origin_x`, `origin_y` - The window's global origin; the row must be even
/// * `chunks` - The layers of the chunks, in the order `(cx0, cy0)`, `(cx0, cy0 + 1)`, then when
///   `dx != 0` `(cx0 + 1, cy0)`, `(cx0 + 1, cy0 + 1)` (see `window_chunks`)
/// # Returns
/// * The window: terrain with the ring imposed as wall, occupied tiles as they are
/// # Panics
/// * If the origin's row is odd (a different hex grid from the map), or the chunk count is wrong
pub fn assemble_window(origin_x: u8, origin_y: u8, chunks: Span<Layers>) -> Layers {
    // [Check] Even origin
    let (_, odd) = DivRem::div_rem(origin_y, 2);
    assert(odd == 0, errors::WINDOW_ODD_ORIGIN);
    let (_, _, dx, dy) = window_chunks(origin_x, origin_y);
    // [Compute] Rows kept: `dy..14` of the lower chunks, `0..dy` of the upper ones
    let rows_low = *ROWS_FROM.span()[dy.into()];
    let rows_high = *ROWS_TO.span()[dy.into()];
    // [Compute] Shifts: lower pieces move down by 15 dy + dx, upper ones up by 15 (15 - dy) - dx
    let row = WIDTH * dy;
    let low_shift = Bits::inv(row + dx);
    let high_shift = Bits::pow(225 - row) * Bits::inv(dx);
    let cols = *COLS_FROM.span()[dx.into()];
    let mask_low: u256 = (cols * rows_low).into();
    let mask_high: u256 = (cols * rows_high).into();
    let lower = *chunks[0];
    let upper = *chunks[1];
    let lower_terrain: u256 = lower.terrain.into();
    let lower_occupied: u256 = lower.occupied.into();
    let upper_terrain: u256 = upper.terrain.into();
    let upper_occupied: u256 = upper.occupied.into();
    let mut terrain = piece(lower_terrain, mask_low, low_shift)
        + piece(upper_terrain, mask_high, high_shift);
    let mut occupied = piece(lower_occupied, mask_low, low_shift)
        + piece(upper_occupied, mask_high, high_shift);
    if dx == 0 {
        assert(chunks.len() == 2, errors::WINDOW_CHUNKS);
    } else {
        // [Compute] Columns `0..dx - 1` of the chunks to the West move by 15 - dx the other way
        assert(chunks.len() == 4, errors::WINDOW_CHUNKS);
        let cols = *COLS_TO.span()[dx.into()];
        let mask_low: u256 = (cols * rows_low).into();
        let mask_high: u256 = (cols * rows_high).into();
        let side = Bits::pow(WIDTH - dx);
        let low_shift = side * Bits::inv(row);
        let high_shift = side * Bits::pow(225 - row);
        let lower = *chunks[2];
        let upper = *chunks[3];
        let lower_terrain: u256 = lower.terrain.into();
        let lower_occupied: u256 = lower.occupied.into();
        let upper_terrain: u256 = upper.terrain.into();
        let upper_occupied: u256 = upper.occupied.into();
        terrain += piece(lower_terrain, mask_low, low_shift)
            + piece(upper_terrain, mask_high, high_shift);
        occupied += piece(lower_occupied, mask_low, low_shift)
            + piece(upper_occupied, mask_high, high_shift);
    }
    // [Return] The ring imposed as wall
    let wide: u256 = terrain.into();
    let ring: u256 = WINDOW_INTERIOR.into();
    let (low, _, _) = Bits::bitwise(wide.low, ring.low);
    let (high, _, _) = Bits::bitwise(wide.high, ring.high);
    Layers { terrain: Bits::to_felt(u256 { low, high }), occupied }
}

/// `chunk` with its part under the window replaced by the window's.
#[inline(always)]
fn put_back(chunk: felt252, window: u256, mask: felt252, shift: felt252, back: felt252) -> felt252 {
    let seen: u256 = (mask * shift).into();
    let (low, _, _) = Bits::bitwise(window.low, seen.low);
    let (high, _, _) = Bits::bitwise(window.high, seen.high);
    let piece = Bits::to_felt(u256 { low, high }) * back;
    let wide: u256 = chunk.into();
    let mask: u256 = mask.into();
    let (low, _, _) = Bits::bitwise(wide.low, mask.low);
    let (high, _, _) = Bits::bitwise(wide.high, mask.high);
    chunk - Bits::to_felt(u256 { low, high }) + piece
}

/// The inverse of `assemble_window` for one layer: the window's tiles written back into the chunks
/// under it (the stored window of variant B', which writes its occupancy back when it moves).
/// # Arguments
/// * `origin_x`, `origin_y` - The window's origin
/// * `window` - The window's layer
/// * `chunks` - The same layer of the chunks under it, in the window's order (4 slots, the last two
///   unused when `dx = 0`)
/// # Returns
/// * The chunks' layer with the window's tiles in place
pub fn scatter_window(
    origin_x: u8, origin_y: u8, window: felt252, chunks: (felt252, felt252, felt252, felt252),
) -> (felt252, felt252, felt252, felt252) {
    let (_, _, dx, dy) = window_chunks(origin_x, origin_y);
    let (s0, s1, s2, s3) = chunks;
    let window: u256 = window.into();
    let rows_low = *ROWS_FROM.span()[dy.into()];
    let rows_high = *ROWS_TO.span()[dy.into()];
    let row = WIDTH * dy;
    let cols = *COLS_FROM.span()[dx.into()];
    let s0 = put_back(s0, window, cols * rows_low, Bits::inv(row + dx), Bits::pow(row + dx));
    let s1 = put_back(
        s1,
        window,
        cols * rows_high,
        Bits::pow(225 - row) * Bits::inv(dx),
        Bits::inv(225 - row) * Bits::pow(dx),
    );
    if dx == 0 {
        return (s0, s1, s2, s3);
    }
    let cols = *COLS_TO.span()[dx.into()];
    let side = Bits::pow(WIDTH - dx);
    let back = Bits::inv(WIDTH - dx);
    let s2 = put_back(s2, window, cols * rows_low, side * Bits::inv(row), back * Bits::pow(row));
    let s3 = put_back(
        s3, window, cols * rows_high, side * Bits::pow(225 - row), back * Bits::inv(225 - row),
    );
    (s0, s1, s2, s3)
}
