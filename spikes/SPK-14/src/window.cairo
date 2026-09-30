//! The 15 x 16 window of D-120 assembled from hexagonal chunks, on the basis of the library's
//! N-3 (`hexx::board::assembly`, `AssemblyTrait::window`): two layers, the ring of the terrain
//! imposed as wall, a `HexMap` returned.
//!
//! A chunk's rows are 11 to 19 bits long, the window's 15, so a chunk no longer moves into the
//! window by one shift: each window row takes 1 to 3 runs of chunk rows (32 at most, over up to 6
//! chunks: `geometry.py`), each one mask of limbs from a table, one AND per limb and one field
//! product by a power of two or its inverse. The walk follows the window's left column up the
//! chunks, one row at a time (a loop of 16 rows, bounded; the runs of a row, at most 3).
//!
//! Chunks are passed in 12 slots, `4 da + db + 1` for the lattice step `(da, db)` from the chunk
//! of the origin; 8 of them can be read (`geometry.py`, `check_plan`): `(0, -1)`, `(0, 0)`,
//! `(0, 1)`, `(1, 0)`, `(1, 1)`, `(1, 2)`, `(2, 1)`, `(2, 2)`. A void or unrevealed chunk is
//! `None` (D-134, D-136), assembled as wall without a read.

use hexx::board::bits::{Bits, TWO_POW_128};
use hexx::board::map::{HexMap, HexMapTrait};
use crate::hexchunk::HexChunkTrait;
use crate::tables::{
    BELOW128, BELOW_HIGH, BELOW_LOW, ROW, WINDOW_INTERIOR_HIGH, WINDOW_INTERIOR_LOW,
};

/// Width of the window.
pub const WIDTH: u8 = 15;
/// Rows of the window.
pub const HEIGHT: u8 = 16;
/// The slot of the chunk of the origin, `(0, 0)`.
pub const ORIGIN_SLOT: u8 = 1;
/// Slots of the chunks of a window.
pub const SLOTS: u32 = 12;

pub mod errors {
    pub const HEXWINDOW_ODD_ORIGIN: felt252 = 'HexWindow: odd origin';
}

/// The origin of a window: the chunk that holds its tile (lattice `(a, b)`) and the tile in it.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct HexOrigin {
    pub a: i32,
    pub b: i32,
    pub q: u8,
    pub r: u8,
}

#[generate_trait]
pub impl HexWindowImpl of HexWindowTrait {
    /// The origin of the window of an adventurer at global offset `(x, y)`: `(x - 7, y - 7)`
    /// when `y` is odd, `(x - 7, y - 8)` when even (D-120), located in its chunk.
    fn origin(x: u8, y: u8) -> HexOrigin {
        let (_, odd) = DivRem::div_rem(y, 2);
        let ox: i32 = x.into() - 7;
        let oy: i32 = y.into() - 8 + odd.into();
        let (q, r) = HexChunkTrait::axial(ox, oy);
        let located = HexChunkTrait::locate(q, r);
        HexOrigin { a: located.a, b: located.b, q: located.q, r: located.r }
    }

    /// The lattice coordinates of the chunk in a slot.
    fn chunk(self: @HexOrigin, slot: u8) -> (i32, i32) {
        let (da, db) = DivRem::div_rem(slot, 4);
        let da: i32 = da.into();
        let db: i32 = db.into();
        (*self.a + da, *self.b + db - 1)
    }

    /// Assemble both layers of the window.
    /// # Arguments
    /// * `terrain`, `occupied` - The layers of the chunks, by slot; `None` for a chunk that is
    ///   void, not revealed or not overlapped
    /// * `origin` - The origin; its global row must be even (the caller's `origin` makes it so)
    /// * `seed` - The seed of the returned map
    /// # Returns
    /// * The map of 15 x 16 whose grid is the terrain, its ring wall, and the occupancy
    fn window(
        terrain: [Option<felt252>; 12],
        occupied: [Option<felt252>; 12],
        origin: @HexOrigin,
        seed: felt252,
    ) -> (HexMap, felt252) {
        let terrain = HexWindowInternal::limbs(terrain);
        let occupied = HexWindowInternal::limbs(occupied);
        let terrain = terrain.span();
        let occupied = occupied.span();
        let mut grid: felt252 = 0;
        let mut occ: felt252 = 0;
        // [Compute] The walk: (slot, q, r) is the window's left tile on row j
        let mut slot = ORIGIN_SLOT;
        let mut q = *origin.q;
        let mut r = *origin.r;
        let mut j: u8 = 0;
        let mut row: u8 = 0;
        while j != HEIGHT {
            // [Compute] The runs of this row, West to East in the index
            let mut s = slot;
            let mut cr = r;
            let mut done: u8 = 0;
            // The first run starts at the left tile, the next ones at the start of their row
            let mut fresh = false;
            loop {
                let (first, top, bottom) = *ROW.span()[cr.into()];
                let (cq, start) = if fresh {
                    (bottom, first)
                } else {
                    (q, first + q - bottom)
                };
                let available = top - cq + 1;
                let left = WIDTH - done;
                let n = if available < left {
                    available
                } else {
                    left
                };
                let end = start + n;
                let target = row + done;
                let (t_low, t_high) = *terrain[s.into()];
                let (o_low, o_high) = *occupied[s.into()];
                if cr < 8 {
                    // Rows 0-7 lie in the low limb (bits 0-115)
                    let mask = *BELOW128.span()[end.into()] - *BELOW128.span()[start.into()];
                    let shift = HexWindowInternal::shift(target, start);
                    let (t, _, _) = Bits::bitwise(t_low, mask);
                    let (o, _, _) = Bits::bitwise(o_low, mask);
                    grid += t.into() * shift;
                    occ += o.into() * shift;
                } else if cr > 8 {
                    // Rows 9-16 lie in the high limb (bits 135-250): 2^128 folded in the shift
                    let from = start - 128;
                    let mask = *BELOW128.span()[(end - 128).into()] - *BELOW128.span()[from.into()];
                    let shift = HexWindowInternal::shift(target, from);
                    let (t, _, _) = Bits::bitwise(t_high, mask);
                    let (o, _, _) = Bits::bitwise(o_high, mask);
                    grid += t.into() * shift;
                    occ += o.into() * shift;
                } else {
                    // Row 8 (bits 116-134) straddles the limbs
                    let mask_low = *BELOW_LOW.span()[end.into()] - *BELOW_LOW.span()[start.into()];
                    let mask_high = *BELOW_HIGH.span()[end.into()]
                        - *BELOW_HIGH.span()[start.into()];
                    let shift = HexWindowInternal::shift(target, start);
                    grid += HexWindowInternal::piece(t_low, t_high, mask_low, mask_high) * shift;
                    occ += HexWindowInternal::piece(o_low, o_high, mask_low, mask_high) * shift;
                }
                done += n;
                if done == WIDTH {
                    break;
                }
                // [Compute] The next chunk East: through q = 18 up to row 8 (+T_R), else
                // through q + r = 26 (+(T_U + T_R))
                if cr <= 8 {
                    s += 1;
                    cr += 8;
                } else {
                    s += 5;
                    cr -= 9;
                }
                fresh = true;
            }
            // [Compute] The next left tile: (q, r + 1) from an even row, (q - 1, r + 1) from an
            // odd one; out of the chunk through q + r = 26, the North row or q = 0
            let (_, odd) = DivRem::div_rem(j, 2);
            if q + r + 1 - odd > 26 {
                slot += 5;
                q = q - odd - 10;
                r = r - 8;
            } else if r == 16 {
                slot += 4;
                q = q + 9 - odd;
                r = 0;
            } else if q < odd {
                slot -= 1;
                q = q + 19 - odd;
                r = r - 7;
            } else {
                q -= odd;
                r += 1;
            }
            j += 1;
            row += WIDTH;
        }
        // [Return] The ring of the terrain is wall
        let wide: u256 = grid.into();
        let (low, _, _) = Bits::bitwise(wide.low, WINDOW_INTERIOR_LOW);
        let (high, _, _) = Bits::bitwise(wide.high, WINDOW_INTERIOR_HIGH);
        let grid: felt252 = low.into() + high.into() * TWO_POW_128;
        (HexMapTrait::new(grid, WIDTH, HEIGHT, seed), occ)
    }
}

#[generate_trait]
pub impl HexWindowTableImpl of HexWindowTableTrait {
    /// `HexWindowTrait::window` with every piece of the origin's class precomputed
    /// (`PIECES_<class>`, generated by `gen_tables.py` from the same walk): per piece one lookup,
    /// the mask and the shift given. The floor of the per-piece work. All 251 classes hold 7,824
    /// pieces, 39,120 felts: as one const they do not compile, so only the benchmark's classes
    /// are generated and the caller passes its class's table.
    fn window(
        terrain: [Option<felt252>; 12],
        occupied: [Option<felt252>; 12],
        pieces: Span<(u8, u8, u128, u128, felt252)>,
        seed: felt252,
    ) -> (HexMap, felt252) {
        let terrain = HexWindowInternal::limbs(terrain);
        let occupied = HexWindowInternal::limbs(occupied);
        let terrain = terrain.span();
        let occupied = occupied.span();
        let mut grid: felt252 = 0;
        let mut occ: felt252 = 0;
        for piece in pieces {
            let (slot, kind, mask_low, mask_high, shift) = *piece;
            let (t_low, t_high) = *terrain[slot.into()];
            let (o_low, o_high) = *occupied[slot.into()];
            if kind == 0 {
                let (t, _, _) = Bits::bitwise(t_low, mask_low);
                let (o, _, _) = Bits::bitwise(o_low, mask_low);
                grid += t.into() * shift;
                occ += o.into() * shift;
            } else if kind == 1 {
                let (t, _, _) = Bits::bitwise(t_high, mask_high);
                let (o, _, _) = Bits::bitwise(o_high, mask_high);
                grid += t.into() * shift;
                occ += o.into() * shift;
            } else {
                grid += HexWindowInternal::piece(t_low, t_high, mask_low, mask_high) * shift;
                occ += HexWindowInternal::piece(o_low, o_high, mask_low, mask_high) * shift;
            }
        }
        let wide: u256 = grid.into();
        let (low, _, _) = Bits::bitwise(wide.low, WINDOW_INTERIOR_LOW);
        let (high, _, _) = Bits::bitwise(wide.high, WINDOW_INTERIOR_HIGH);
        let grid: felt252 = low.into() + high.into() * TWO_POW_128;
        (HexMapTrait::new(grid, WIDTH, HEIGHT, seed), occ)
    }
}

#[generate_trait]
impl HexWindowInternal of HexWindowInternalTrait {
    /// The limbs of every slot, `(0, 0)` for a void one (not read).
    #[inline(always)]
    fn limbs(chunks: [Option<felt252>; 12]) -> [(u128, u128); 12] {
        let [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11] = chunks;
        [
            Self::wide(c0), Self::wide(c1), Self::wide(c2), Self::wide(c3), Self::wide(c4),
            Self::wide(c5), Self::wide(c6), Self::wide(c7), Self::wide(c8), Self::wide(c9),
            Self::wide(c10), Self::wide(c11),
        ]
    }

    #[inline(always)]
    fn wide(chunk: Option<felt252>) -> (u128, u128) {
        match chunk {
            Option::Some(chunk) => {
                let wide: u256 = chunk.into();
                (wide.low, wide.high)
            },
            Option::None => (0, 0),
        }
    }

    /// The field product that moves bit `from` to bit `to`.
    #[inline(always)]
    fn shift(to: u8, from: u8) -> felt252 {
        if to >= from {
            Bits::pow(to - from)
        } else {
            Bits::inv(from - to)
        }
    }

    /// A run of a chunk as a felt: one AND per limb.
    #[inline(always)]
    fn piece(low: u128, high: u128, mask_low: u128, mask_high: u128) -> felt252 {
        let (low, _, _) = Bits::bitwise(low, mask_low);
        let (high, _, _) = Bits::bitwise(high, mask_high);
        low.into() + high.into() * TWO_POW_128
    }
}
