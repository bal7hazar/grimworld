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
//! - **Within 2 of the openings** (`near_openings`): two hex dilations of the openings' set
//!   (`dilate`, bit-parallel with the row parity, ring tiles included), equal to the union of
//!   `HexagonTrait::hexagon`s of radius 2 (N-6), which the tests hold it against. `hexagon`'s table
//!   path is not called: its tables and loop path cost `RevealLibrary` about 1,900 CASM felts (D-200).
//!
//! **Corners are always wall** (D-134): no step opens one (`SIDES` holds no corner, `lines` and the
//! spine lie in the interior, an anchor on a corner is not opened).
//!
//! `u256` is the pair of limbs of a bitmap for `hexx`'s `Bits` (written reason: a `felt252` has no
//! bitwise operation, docs/CAIRO.md §4, as `types::window`). No `u256` arithmetic.

use core::poseidon::hades_permutation;
use hexx::board::bits::Bits;
use hexx::board::cut::CutTrait;
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
/// The local even rows (0, 2, … 14) and the local odd ones.
const EVEN_ROWS: felt252 = 0x1fffc0007fff0001fffc0007fff0001fffc0007fff0001fffc0007fff;
const ODD_ROWS: felt252 = 0x3fff8000fffe0003fff8000fffe0003fff8000fffe0003fff8000;
/// The board without column 0, without column 14, without row 0.
const NOT_COLUMN_0: felt252 = 0x1fffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffe;
const NOT_COLUMN_14: felt252 = 0xfffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff;
const NOT_ROW_0: felt252 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffff8000;
/// 2^15 and 2^-15: a row up, a row down.
const ROW_UP: felt252 = 0x8000;
/// `2^−k` in the field, for the exact shifts down.
const INV_1: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
const INV_7: felt252 = 0x7f0000000000010de0000000000000000000000000000000000000000000001;
const INV_14: felt252 = 0x7ffe00000000010ffbc00000000000000000000000000000000000000000001;
const INV_15: felt252 = 0x7fff00000000010ffde00000000000000000000000000000000000000000001;
const INV_16: felt252 = 0x7fff80000000010ffef00000000000000000000000000000000000000000001;
const INV_105: felt252 = 0x800000000000010fffffffffffbfffffffffffff78000000000000000000001;
const INV_210: felt252 = 0x22000000000000483ffffffffffffffffffffffffffffffffe0000000000;
/// 2^14, 2^210: from column 0 to column 14, from row 0 to row 14.
const P14: felt252 = 0x4000;
const P210: felt252 = 0x40000000000000000000000000000000000000000000000000000;
/// Generations of the automaton, every biome (tuned on a model of `hexx`'s B4/S2: one generation
/// after the base gives each biome's walkable share; `test_biome_shares` holds it on the code).
pub const GENERATIONS: u8 = 1;

#[generate_trait]
pub impl BoardImpl of BoardTrait {
    /// `2^i`, `i` below 251.
    #[inline(always)]
    fn pow(i: u8) -> felt252 {
        if i < 128 {
            Self::pow128(i).into()
        } else {
            Self::pow128(i - 128).into() * 0x100000000000000000000000000000000
        }
    }

    /// `2^i` as a `u128`, `i` below 128: a `match`, read in constant time (a constant table is
    /// copied whole at each read in Sierra).
    fn pow128(i: u8) -> u128 {
        match i {
            0 => 0x1,
            1 => 0x2,
            2 => 0x4,
            3 => 0x8,
            4 => 0x10,
            5 => 0x20,
            6 => 0x40,
            7 => 0x80,
            8 => 0x100,
            9 => 0x200,
            10 => 0x400,
            11 => 0x800,
            12 => 0x1000,
            13 => 0x2000,
            14 => 0x4000,
            15 => 0x8000,
            16 => 0x10000,
            17 => 0x20000,
            18 => 0x40000,
            19 => 0x80000,
            20 => 0x100000,
            21 => 0x200000,
            22 => 0x400000,
            23 => 0x800000,
            24 => 0x1000000,
            25 => 0x2000000,
            26 => 0x4000000,
            27 => 0x8000000,
            28 => 0x10000000,
            29 => 0x20000000,
            30 => 0x40000000,
            31 => 0x80000000,
            32 => 0x100000000,
            33 => 0x200000000,
            34 => 0x400000000,
            35 => 0x800000000,
            36 => 0x1000000000,
            37 => 0x2000000000,
            38 => 0x4000000000,
            39 => 0x8000000000,
            40 => 0x10000000000,
            41 => 0x20000000000,
            42 => 0x40000000000,
            43 => 0x80000000000,
            44 => 0x100000000000,
            45 => 0x200000000000,
            46 => 0x400000000000,
            47 => 0x800000000000,
            48 => 0x1000000000000,
            49 => 0x2000000000000,
            50 => 0x4000000000000,
            51 => 0x8000000000000,
            52 => 0x10000000000000,
            53 => 0x20000000000000,
            54 => 0x40000000000000,
            55 => 0x80000000000000,
            56 => 0x100000000000000,
            57 => 0x200000000000000,
            58 => 0x400000000000000,
            59 => 0x800000000000000,
            60 => 0x1000000000000000,
            61 => 0x2000000000000000,
            62 => 0x4000000000000000,
            63 => 0x8000000000000000,
            64 => 0x10000000000000000,
            65 => 0x20000000000000000,
            66 => 0x40000000000000000,
            67 => 0x80000000000000000,
            68 => 0x100000000000000000,
            69 => 0x200000000000000000,
            70 => 0x400000000000000000,
            71 => 0x800000000000000000,
            72 => 0x1000000000000000000,
            73 => 0x2000000000000000000,
            74 => 0x4000000000000000000,
            75 => 0x8000000000000000000,
            76 => 0x10000000000000000000,
            77 => 0x20000000000000000000,
            78 => 0x40000000000000000000,
            79 => 0x80000000000000000000,
            80 => 0x100000000000000000000,
            81 => 0x200000000000000000000,
            82 => 0x400000000000000000000,
            83 => 0x800000000000000000000,
            84 => 0x1000000000000000000000,
            85 => 0x2000000000000000000000,
            86 => 0x4000000000000000000000,
            87 => 0x8000000000000000000000,
            88 => 0x10000000000000000000000,
            89 => 0x20000000000000000000000,
            90 => 0x40000000000000000000000,
            91 => 0x80000000000000000000000,
            92 => 0x100000000000000000000000,
            93 => 0x200000000000000000000000,
            94 => 0x400000000000000000000000,
            95 => 0x800000000000000000000000,
            96 => 0x1000000000000000000000000,
            97 => 0x2000000000000000000000000,
            98 => 0x4000000000000000000000000,
            99 => 0x8000000000000000000000000,
            100 => 0x10000000000000000000000000,
            101 => 0x20000000000000000000000000,
            102 => 0x40000000000000000000000000,
            103 => 0x80000000000000000000000000,
            104 => 0x100000000000000000000000000,
            105 => 0x200000000000000000000000000,
            106 => 0x400000000000000000000000000,
            107 => 0x800000000000000000000000000,
            108 => 0x1000000000000000000000000000,
            109 => 0x2000000000000000000000000000,
            110 => 0x4000000000000000000000000000,
            111 => 0x8000000000000000000000000000,
            112 => 0x10000000000000000000000000000,
            113 => 0x20000000000000000000000000000,
            114 => 0x40000000000000000000000000000,
            115 => 0x80000000000000000000000000000,
            116 => 0x100000000000000000000000000000,
            117 => 0x200000000000000000000000000000,
            118 => 0x400000000000000000000000000000,
            119 => 0x800000000000000000000000000000,
            120 => 0x1000000000000000000000000000000,
            121 => 0x2000000000000000000000000000000,
            122 => 0x4000000000000000000000000000000,
            123 => 0x8000000000000000000000000000000,
            124 => 0x10000000000000000000000000000000,
            125 => 0x20000000000000000000000000000000,
            126 => 0x40000000000000000000000000000000,
            _ => 0x80000000000000000000000000000000,
        }
    }

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
            1 => Bits::to_felt(Bits::and(wide, WEST.into())) * INV_14,
            // The South neighbour's North side, row 14 to row 0.
            2 => Bits::to_felt(Bits::and(wide, NORTH.into())) * INV_210,
            // The North neighbour's South side, row 0 to row 14.
            _ => Bits::to_felt(Bits::and(wide, SOUTH.into())) * P210,
        }
    }

    /// The lines from every open ring tile to the spine, and the spine: products of each side's
    /// openings, which are disjoint on a side, joined by OR across sides (two lines may cross).
    fn lines(ring: felt252) -> felt252 {
        let wide: u256 = ring.into();
        let east = Bits::to_felt(Bits::and(wide, EAST.into())) * LINE_EAST;
        let west = Bits::to_felt(Bits::and(wide, WEST.into())) * INV_7 * 0x7f;
        let south = Bits::to_felt(Bits::and(wide, SOUTH.into())) * LINE_SOUTH;
        let north = Bits::to_felt(Bits::and(wide, NORTH.into())) * INV_105 * COLUMN_7;
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
        Self::pow(row * 15) * (Self::pow(high + 1) - Self::pow(low))
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
    /// the chunk, or one row up on a 15 × 16 board for an odd chunk. One call site, so that the
    /// class holds one copy of the flood.
    fn component(interior: felt252, root: u8, odd: bool) -> felt252 {
        let (grid, height, from, back) = if odd {
            (interior * ROW_UP, 16, root + 15, INV_15)
        } else {
            (interior, 15, root, 1)
        };
        CaverTrait::keep_component(grid, 15, height, from) * back
    }

    /// `tiles` and their hex neighbours on the chunk, ring included (`hexx`'s odd-r layout with the
    /// global parity: a globally even row's northern and southern neighbours are `x − 1` and `x`, an
    /// odd row's `x` and `x + 1`). Each shift is a field product of tiles masked so that it never
    /// crosses a side; the shifted sets are joined by OR, as two of them may meet.
    fn dilate(tiles: felt252, odd: bool) -> felt252 {
        let wide: u256 = tiles.into();
        let (even_rows, odd_rows) = if odd {
            (ODD_ROWS, EVEN_ROWS)
        } else {
            (EVEN_ROWS, ODD_ROWS)
        };
        let evens = Bits::and(wide, even_rows.into());
        let odds = Bits::and(wide, odd_rows.into());
        let not_first: u256 = NOT_COLUMN_0.into();
        let not_last: u256 = NOT_COLUMN_14.into();
        let up: u256 = NOT_ROW_0.into();
        // [Compute] Along the row: West (`+1`) and East (`−1`)
        let west = Bits::to_felt(Bits::and(wide, not_last)) * 2;
        let east = Bits::to_felt(Bits::and(wide, not_first)) * INV_1;
        // [Compute] North: `x` from every row, `x − 1` from the even rows, `x + 1` from the odd
        let north = Bits::or(
            (tiles * ROW_UP).into(),
            Bits::or(
                (Bits::to_felt(Bits::and(evens, not_first)) * P14).into(),
                (Bits::to_felt(Bits::and(odds, not_last)) * 0x10000).into(),
            ),
        );
        // [Compute] South, from every row but row 0
        let rows = Bits::and(wide, up);
        let south = Bits::or(
            (Bits::to_felt(rows) * INV_15).into(),
            Bits::or(
                (Bits::to_felt(Bits::and(Bits::and(evens, up), not_first)) * INV_16).into(),
                (Bits::to_felt(Bits::and(Bits::and(odds, up), not_last)) * INV_14).into(),
            ),
        );
        // The northern products may pass row 14: the board cuts them.
        let around = Bits::or(Bits::or(west.into(), east.into()), Bits::or(north, south));
        Bits::to_felt(Bits::and(Bits::or(around, wide), BOARD.into()))
    }

    /// The tiles within 2 of every open ring tile and of `anchors` (already in `ring` when they
    /// lie on it): two dilations.
    fn near_openings(ring: felt252, anchors: Span<u8>, odd: bool) -> felt252 {
        let mut tiles = ring;
        for tile in anchors {
            tiles = Self::or(tiles, Self::pow(*tile));
        }
        Self::dilate(Self::dilate(tiles, odd), odd)
    }

    /// The number of set bits.
    #[inline(never)]
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
        let mut byte: u8 = 0;
        loop {
            let (rest, value) = Bits::low_byte(limb);
            let here = Bits::popcount_small(value.into());
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
    #[inline(never)]
    fn has(bits: felt252, tile: u8) -> bool {
        Self::has_wide(bits.into(), tile)
    }

    /// Whether `tile` is set in a bitmap already split into its limbs: one AND on its limb.
    #[inline(never)]
    fn has_wide(bits: u256, tile: u8) -> bool {
        if tile < 128 {
            bits.low & Self::pow128(tile) != 0
        } else {
            bits.high & Self::pow128(tile - 128) != 0
        }
    }

    /// `a & b`.
    #[inline(never)]
    fn and(a: felt252, b: felt252) -> felt252 {
        Bits::to_felt(Bits::and(a.into(), b.into()))
    }

    /// `a | b`.
    #[inline(never)]
    fn or(a: felt252, b: felt252) -> felt252 {
        Bits::to_felt(Bits::or(a.into(), b.into()))
    }

    /// `a & !b`.
    #[inline(never)]
    fn minus(a: felt252, b: felt252) -> felt252 {
        a - Self::and(a, b)
    }
}

#[cfg(test)]
mod tests {
    use hexx::board::bits::Bits;
    use hexx::board::hexagon::HexagonTrait;
    use hexx::board::map::HexMapTrait;
    use hexx::board::seams::{SeamTrait, Side};
    use super::{BOARD, BoardTrait, CENTRE, EAST, INTERIOR, NORTH, SOUTH, SPINE, WEST};

    fn at(column: u8, row: u8) -> u8 {
        row * 15 + column
    }

    // The sides against `hexx`'s seams (N-2): `Side::West` is column 14, `East` column 0, `South`
    // row 0, `North` row 14, ENG-01's edge order West, East, South, North; corners excluded.
    #[test]
    #[available_gas(l2_gas: 84690)] // ceil(1.05 × 80657 measured)
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
    #[available_gas(l2_gas: 311103)] // ceil(1.05 × 296288 measured)
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
    #[available_gas(l2_gas: 42099)] // ceil(1.05 × 40094 measured)
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
    #[available_gas(l2_gas: 20363816)] // ceil(1.05 × 19394110 measured)
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

    /// The tiles within 2 of `tile` by `hexx`'s hexagon (N-6), an odd chunk a row up on 15 × 16.
    fn hexagon(tile: u8, odd: bool) -> felt252 {
        if odd {
            let shifted = HexMapTrait::new(0, 15, 16, 0).hexagon(tile + 15, 2);
            let row: felt252 = 0x7fff;
            (shifted - BoardTrait::and(shifted, row)) * Bits::inv(15)
        } else {
            HexMapTrait::new(0, 15, 15, 0).hexagon(tile, 2)
        }
    }

    fn near(tile: u8, odd: bool) -> felt252 {
        BoardTrait::near_openings(Bits::pow(tile), array![].span(), odd)
    }

    // Two dilations against `hexx`'s hexagon of radius 2, from every tile of the chunk, both
    // parities; and from several tiles at once, the union.
    #[test]
    #[available_gas(l2_gas: 74551095)] // ceil(1.05 × 71001042 measured)
    fn test_dilation_against_hexagons() {
        let mut tile: u8 = 0;
        while tile != 225 {
            assert(near(tile, false) == hexagon(tile, false), 'even');
            assert(near(tile, true) == hexagon(tile, true), 'odd');
            tile += 1;
        }
        let tiles = Bits::pow(0) + Bits::pow(29) + Bits::pow(112) + Bits::pow(223);
        let union = BoardTrait::or(
            BoardTrait::or(hexagon(0, true), hexagon(29, true)),
            BoardTrait::or(hexagon(112, true), hexagon(223, true)),
        );
        assert(BoardTrait::near_openings(tiles, array![].span(), true) == union, 'union');
    }

    // Within 2 of a tile: 19 tiles inside, fewer on the ring; an odd chunk's rows shifted.
    #[test]
    #[available_gas(l2_gas: 1036455)] // ceil(1.05 × 987100 measured)
    fn test_near() {
        assert(BoardTrait::count(near(CENTRE, false)) == 19, 'even');
        assert(BoardTrait::count(near(CENTRE, true)) == 19, 'odd');
        assert(near(CENTRE, false) != near(CENTRE, true), 'parities');
        assert(BoardTrait::count(near(at(0, 7), true)) == 11, 'east side, global even');
        assert(BoardTrait::count(near(at(7, 0), true)) == 12, 'south side');
        assert(BoardTrait::count(near(at(0, 7), false)) == 13, 'east side, global odd');
    }
}
