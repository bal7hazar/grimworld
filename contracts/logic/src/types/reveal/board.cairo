//! The board steps of a reveal (design/18's order, ADR-0006 *Joining chunks*), on `hexx`
//! 0.1.0-rc.2. A chunk is the 15 × 15 board of `hexx`, in **its** sense: bit `15 row + column` is
//! 1 for a **floor** tile (the inverse of `Terrain`'s walls), pointy-top odd-r, `+1` West, `+15`
//! North; `odd` when the chunk's local row 0 is a global odd row (`cy` odd, ADR-0006 §4).
//!
//! - **Base** (`base`): a word's random bitmaps combined to the biome's density, interior only.
//! - **Smoothing with the margins** (`smooth`): `CaverTrait::smooth` (N-1), the automaton B4/S2
//!   for the biome's generations, the ring frozen to the sides already decided (copied from the
//!   revealed neighbours, closed, or drawn), each row with its global parity.
//! - **Edges and openings** (`copy`, `lines`, `anchor_line`): a side facing a revealed neighbour
//!   copies that neighbour's facing tiles (the same index across the seam: hex neighbours whatever
//!   the parity, `SeamTrait::is_open_across` holds it in the tests); every open ring tile and every
//!   anchor is joined to the **spine** (row 7 and column 7 of the interior) by a straight line
//!   (SPK-7's choice, kept: a row and a column of an odd-r board are connected).
//! - **The cut by the outline** (`cut`): `CutTrait::cut` (N-4), `grid & mask`, the ring kept.
//! - **Reachability** (`component`): `CaverTrait::keep_component` (N-1) from the centre, so that
//!   every open tile is reachable from every opening (each opening's line reaches the spine, which
//!   holds the centre). `keep_component` floods the even layout: an odd chunk is flooded one row up
//!   on a 15 × 16 board, where its rows have their global parity.
//! - **Within 2 of a tile** (`near`): `HexagonTrait::hexagon` (N-6), the same row shift for an odd
//!   chunk.
//!
//! **Corners are always wall** (D-134): no step opens one (`SIDES` holds no corner, `lines` and the
//! spine lie in the interior, an anchor on a corner is not opened).
//!
//! `u256` is the pair of limbs of a bitmap for `hexx`'s `Bits` (written reason: a `felt252` has no
//! bitwise operation, docs/CAIRO.md §4, as `types::window`). No `u256` arithmetic.

use core::poseidon::hades_permutation;
use hexx::board::bits::Bits;
use hexx::board::cut::CutTrait;
use hexx::board::hexagon::HexagonTrait;
use hexx::board::map::HexMapTrait;
use hexx::generators::caver::CaverTrait;
use crate::models::location::biome;

/// The 225 tiles.
pub const BOARD: felt252 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
/// The 169 tiles inside the ring.
pub const INTERIOR: felt252 = 0x1fff3ffe7ffcfff9fff3ffe7ffcfff9fff3ffe7ffcfff9fff0000;
/// The 13 tiles of each side that are not a corner, by ENG-01's order of the edges: West (column
/// 14, `hexx`'s `Side::West`), East (column 0), South (row 0), North (row 14).
pub const WEST: felt252 = 0x20004000800100020004000800100020004000800100020000000;
pub const EAST: felt252 = 0x8001000200040008001000200040008001000200040008000;
pub const SOUTH: felt252 = 0x3ffe;
pub const NORTH: felt252 = 0xfff80000000000000000000000000000000000000000000000000000;
/// Row 7 and column 7 of the interior.
pub const SPINE: felt252 = 0x4000800100020004000807ffc02000400080010002000400000;
/// The centre `(7, 7)`, on the spine: the flood's source.
pub const CENTRE: u8 = 112;
/// An East opening's line, columns 1 to 7 of its row.
const LINE_EAST: felt252 = 0xfe;
/// A South opening's line, rows 1 to 7 of its column.
const LINE_SOUTH: felt252 = 0x200040008001000200040008000;
/// Rows 0 to 6 of column 0: a North opening's line, once moved down to row 7.
const COLUMN_7: felt252 = 0x40008001000200040008001;
/// Row 0, the 15 bits the shift of an odd chunk adds below it.
const ROW_0: felt252 = 0x7fff;
/// 2^15 and 2^-15: a row up, a row down.
const ROW_UP: felt252 = 0x8000;
/// 2^14, 2^210: from column 0 to column 14, from row 0 to row 14.
const P14: felt252 = 0x4000;
const P210: felt252 = 0x40000000000000000000000000000000000000000000000000000;
/// Generations of the automaton, every biome (tuned on a model of `hexx`'s B4/S2: one generation
/// after the base gives each biome's walkable share; `test_biome_shares` holds it on the code).
pub const GENERATIONS: u8 = 1;
/// The non-corner ring tiles, side by side (South, North, East, West), for the openings' list.
const RING: [u8; 52] = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221,
    222, 223, 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 29, 44, 59, 74, 89, 104, 119,
    134, 149, 164, 179, 194, 209,
];
/// Set bits of each byte.
const BYTE_COUNTS: [u8; 256] = [
    0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4, 1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 1,
    2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 1, 2,
    2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 2, 3, 3,
    4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7, 1, 2, 2, 3,
    2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 2, 3, 3, 4, 3,
    4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7, 2, 3, 3, 4, 3, 4,
    4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7, 3, 4, 4, 5, 4, 5, 5,
    6, 4, 5, 5, 6, 5, 6, 6, 7, 4, 5, 5, 6, 5, 6, 6, 7, 5, 6, 6, 7, 6, 7, 7, 8,
];

#[generate_trait]
pub impl BoardImpl of BoardTrait {
    /// The side mask of edge `side` (0 West, 1 East, 2 South, 3 North).
    #[inline(always)]
    fn side(side: u8) -> felt252 {
        match side {
            0 => WEST,
            1 => EAST,
            2 => SOUTH,
            _ => NORTH,
        }
    }

    /// The floor of a chunk's walls: the board less the walls.
    #[inline(always)]
    fn floor(walls: felt252) -> felt252 {
        BOARD - walls
    }

    /// The base of a word at the biome's density (design/18 *Biomes*), interior only: from five
    /// random bitmaps `a … e` (two permutations of the word), meadow `a | (b & c)` (5/8), forest
    /// `a & (b | c | d | e)` (15/32), cave `a & (b | c)` (3/8), ruin `a & (b | (c & d))` (5/16).
    fn base(word: felt252, biome: u8) -> felt252 {
        let (a, b, c) = hades_permutation(word, 0, 2);
        let a: u256 = a.into();
        let b: u256 = b.into();
        let c: u256 = c.into();
        let fill = if biome == biome::MEADOW {
            Bits::or(a, Bits::and(b, c))
        } else if biome == biome::CAVE {
            Bits::and(a, Bits::or(b, c))
        } else {
            let (d, e, _) = hades_permutation(word, 1, 2);
            let d: u256 = d.into();
            if biome == biome::FOREST {
                let e: u256 = e.into();
                Bits::and(a, Bits::or(Bits::or(b, c), Bits::or(d, e)))
            } else {
                Bits::and(a, Bits::or(b, Bits::and(c, d)))
            }
        };
        Bits::to_felt(Bits::and(fill, INTERIOR.into()))
    }

    /// The tiles of side `side` that face the open tiles of a revealed neighbour's facing side
    /// (`floor`, the neighbour's floor): the same index across the seam, corners excluded.
    fn copy(side: u8, floor: felt252) -> felt252 {
        let wide: u256 = floor.into();
        match side {
            // The West neighbour's East side, column 0 to column 14.
            0 => Bits::to_felt(Bits::and(wide, EAST.into())) * P14,
            // The East neighbour's West side, column 14 to column 0 (exact: every bit at ≥ 14).
            1 => Bits::to_felt(Bits::and(wide, WEST.into())) * Bits::inv(14),
            // The South neighbour's North side, row 14 to row 0.
            2 => Bits::to_felt(Bits::and(wide, NORTH.into())) * Bits::inv(210),
            // The North neighbour's South side, row 0 to row 14.
            _ => Bits::to_felt(Bits::and(wide, SOUTH.into())) * P210,
        }
    }

    /// The lines from every open ring tile to the spine, and the spine: products of each side's
    /// openings, which are disjoint on a side, joined by OR across sides (two lines may cross).
    fn lines(ring: felt252) -> felt252 {
        let wide: u256 = ring.into();
        let east = Bits::to_felt(Bits::and(wide, EAST.into())) * LINE_EAST;
        let west = Bits::to_felt(Bits::and(wide, WEST.into())) * Bits::inv(7) * 0x7f;
        let south = Bits::to_felt(Bits::and(wide, SOUTH.into())) * LINE_SOUTH;
        let north = Bits::to_felt(Bits::and(wide, NORTH.into())) * Bits::inv(105) * COLUMN_7;
        let across = Bits::or(east.into(), west.into());
        let along = Bits::or(south.into(), north.into());
        Bits::to_felt(Bits::or(Bits::or(across, along), SPINE.into()))
    }

    /// An interior anchor's line, along its row to column 7 (the spine).
    fn anchor_line(tile: u8) -> felt252 {
        let (row, column) = DivRem::div_rem(tile, 15);
        let (low, high) = if column < 7 {
            (column, 7)
        } else {
            (7, column)
        };
        Bits::pow(row * 15) * (Bits::pow(high + 1) - Bits::pow(low))
    }

    /// One pass of `CaverTrait::smooth` per generation, the ring held (N-1).
    #[inline(always)]
    fn smooth(grid: felt252, odd: bool) -> felt252 {
        CaverTrait::smooth(grid, 15, 15, GENERATIONS, 0, odd)
    }

    /// `grid` cut by a zone's tile mask (N-4): what is outside the mask is wall, the ring included.
    #[inline(always)]
    fn cut(grid: felt252, mask: felt252) -> felt252 {
        HexMapTrait::new(grid, 15, 15, 0).cut(mask).grid
    }

    /// The interior floor connected to `root` (an interior floor tile): `keep_component` (N-1) on
    /// the chunk, or one row up on a 15 × 16 board for an odd chunk.
    fn component(interior: felt252, root: u8, odd: bool) -> felt252 {
        if odd {
            CaverTrait::keep_component(interior * ROW_UP, 15, 16, root + 15) * Bits::inv(15)
        } else {
            CaverTrait::keep_component(interior, 15, 15, root)
        }
    }

    /// The tiles within 2 of `tile` (N-6), the chunk's row parity honoured.
    fn near(tile: u8, odd: bool) -> felt252 {
        if odd {
            let shifted = HexMapTrait::new(0, 15, 16, 0).hexagon(tile + 15, 2);
            let below: u256 = shifted.into();
            let row: u256 = ROW_0.into();
            (shifted - Bits::to_felt(Bits::and(below, row))) * Bits::inv(15)
        } else {
            HexMapTrait::new(0, 15, 15, 0).hexagon(tile, 2)
        }
    }

    /// The tiles within 2 of every open ring tile and of `anchors` (already in `ring` when they
    /// lie on it).
    fn near_openings(ring: felt252, anchors: Span<u8>, odd: bool) -> felt252 {
        let wide: u256 = ring.into();
        let mut near: u256 = 0;
        for tile in RING.span() {
            if Bits::get(wide, *tile) {
                near = Bits::or(near, Self::near(*tile, odd).into());
            }
        }
        for tile in anchors {
            near = Bits::or(near, Self::near(*tile, odd).into());
        }
        Bits::to_felt(near)
    }

    /// The number of set bits.
    #[inline(always)]
    fn count(bits: felt252) -> u8 {
        Bits::popcount(bits.into())
    }

    /// The index of the `n`-th set bit of `bits` (`n` below `count(bits)`): the limb, then the
    /// byte by a table of byte counts, then the bit; at most 16 bytes and 8 bits.
    fn nth(bits: felt252, n: u8) -> u8 {
        let wide: u256 = bits.into();
        let mut left = n;
        let low = Bits::popcount_small(wide.low);
        let (mut limb, mut index) = if left < low {
            (wide.low, 0_u8)
        } else {
            left -= low;
            (wide.high, 128_u8)
        };
        let counts = BYTE_COUNTS.span();
        let mut byte: u8 = 0;
        loop {
            let (rest, value) = Bits::low_byte(limb);
            let here = *counts[value.into()];
            if left < here {
                byte = value;
                break;
            }
            left -= here;
            limb = rest;
            index += 8;
        }
        loop {
            let (rest, bit) = DivRem::div_rem(byte, 2);
            if bit == 1 {
                if left == 0 {
                    break;
                }
                left -= 1;
            }
            byte = rest;
            index += 1;
        }
        index
    }

    /// Whether `tile` is set in `bits`.
    #[inline(always)]
    fn has(bits: felt252, tile: u8) -> bool {
        Bits::get(bits.into(), tile)
    }

    /// `a & b`.
    #[inline(always)]
    fn and(a: felt252, b: felt252) -> felt252 {
        Bits::to_felt(Bits::and(a.into(), b.into()))
    }

    /// `a | b`.
    #[inline(always)]
    fn or(a: felt252, b: felt252) -> felt252 {
        Bits::to_felt(Bits::or(a.into(), b.into()))
    }

    /// `a & !b`.
    #[inline(always)]
    fn minus(a: felt252, b: felt252) -> felt252 {
        a - Self::and(a, b)
    }
}

#[cfg(test)]
mod tests {
    use hexx::board::bits::Bits;
    use hexx::board::seams::{SeamTrait, Side};
    use super::{BOARD, BoardTrait, CENTRE, EAST, INTERIOR, NORTH, SOUTH, SPINE, WEST};

    fn at(column: u8, row: u8) -> u8 {
        row * 15 + column
    }

    // The sides against `hexx`'s seams (N-2): `Side::West` is column 14, `East` column 0, `South`
    // row 0, `North` row 14, ENG-01's edge order West, East, South, North; corners excluded.
    #[test]
    #[available_gas(l2_gas: 75723)] // ceil(1.05 × 72117 measured)
    fn test_sides_against_seams() {
        let corners = 1 + Bits::pow(14) + Bits::pow(210) + Bits::pow(224);
        let sides = [Side::West, Side::East, Side::South, Side::North];
        let mut i: u8 = 0;
        for side in sides.span() {
            let full = SeamTrait::side(15, 15, *side);
            assert(BoardTrait::side(i) == BoardTrait::minus(full, corners), 'side');
            i += 1;
        }
        assert(WEST + EAST + SOUTH + NORTH + INTERIOR + corners == BOARD, 'partition');
        assert(BoardTrait::has(SPINE, CENTRE), 'centre on the spine');
    }

    // An opening's line reaches the spine, a straight run of floor along its row or column.
    #[test]
    #[available_gas(l2_gas: 267969)] // ceil(1.05 × 255208 measured)
    fn test_lines_reach_the_spine() {
        let ring = Bits::pow(at(0, 3)) + Bits::pow(at(14, 11)) + Bits::pow(at(4, 0))
            + Bits::pow(at(9, 14));
        let lines = BoardTrait::lines(ring);
        let mut column: u8 = 1;
        while column != 8 {
            assert(BoardTrait::has(lines, at(column, 3)), 'east line');
            assert(BoardTrait::has(lines, at(column + 6, 11)), 'west line');
            assert(BoardTrait::has(lines, at(4, column)), 'south line');
            assert(BoardTrait::has(lines, at(9, column + 6)), 'north line');
            column += 1;
        }
        assert(BoardTrait::and(lines, INTERIOR) == lines, 'interior only');
        assert(BoardTrait::anchor_line(at(3, 5)) == Bits::pow(at(3, 5)) * 0x1f, 'anchor west');
        assert(BoardTrait::anchor_line(at(11, 5)) == Bits::pow(at(7, 5)) * 0x1f, 'anchor east');
    }

    // A neighbour's facing tiles land on the same index of this chunk's side.
    #[test]
    #[available_gas(l2_gas: 47286)] // ceil(1.05 × 45034 measured)
    fn test_copy_faces_the_neighbour() {
        let floor = Bits::pow(at(0, 4)) + Bits::pow(at(14, 6)) + Bits::pow(at(3, 14))
            + Bits::pow(at(8, 0)) + Bits::pow(at(7, 7));
        assert(BoardTrait::copy(0, floor) == Bits::pow(at(14, 4)), 'west');
        assert(BoardTrait::copy(1, floor) == Bits::pow(at(0, 6)), 'east');
        assert(BoardTrait::copy(2, floor) == Bits::pow(at(3, 0)), 'south');
        assert(BoardTrait::copy(3, floor) == Bits::pow(at(8, 14)), 'north');
    }

    // `nth` against a scan of the bits.
    #[test]
    #[available_gas(l2_gas: 11238714)] // ceil(1.05 × 10703537 measured)
    fn test_nth_against_a_scan() {
        let bits = INTERIOR - SPINE + Bits::pow(224) + 1;
        let total = BoardTrait::count(bits);
        let mut n: u8 = 0;
        let mut tile: u8 = 0;
        while n != total {
            while !BoardTrait::has(bits, tile) {
                tile += 1;
            }
            assert(BoardTrait::nth(bits, n) == tile, 'nth');
            tile += 1;
            n += 1;
        }
    }

    // Within 2 of a tile: 19 tiles inside, fewer on the ring; an odd chunk's rows shifted.
    #[test]
    #[available_gas(l2_gas: 196804)] // ceil(1.05 × 187432 measured)
    fn test_near() {
        assert(BoardTrait::count(BoardTrait::near(CENTRE, false)) == 19, 'even');
        assert(BoardTrait::count(BoardTrait::near(CENTRE, true)) == 19, 'odd');
        assert(BoardTrait::near(CENTRE, false) != BoardTrait::near(CENTRE, true), 'parities');
        assert(BoardTrait::count(BoardTrait::near(at(0, 7), true)) == 11, 'east side, global even');
        assert(BoardTrait::count(BoardTrait::near(at(7, 0), true)) == 12, 'south side');
        assert(BoardTrait::count(BoardTrait::near(at(0, 7), false)) == 13, 'east side, global odd');
    }
}
