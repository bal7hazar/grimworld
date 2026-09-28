//! N-1, N-2: generation of a chunk given its margins, at reveal (ADR-0006 §2, design/18).
//!
//! A chunk is 15 x 15, one felt. Its outer ring is the seam (docs/needs/hexmap.md point 1): the
//! side facing a chunk already generated is **copied** from that chunk's facing edge, a side on the
//! border of the location is **closed**, any other side is **drawn** here (1 or 2 openings) and
//! frozen (D-22). Corners are always wall: they are the only tiles that touch a diagonal chunk.
//! The 13 x 13 interior evolves, in the order of design/18:
//! 1. base: the random word's bits at the biome's density;
//! 2. connections: every opening joined to a spine (row 7 and column 7) by a straight line, one
//!    field product per side; a column of an odd-r board is connected, a row too;
//! 3. smoothing: 2 synchronous passes of a cellular automaton that counts the ring (the margins) as
//!    neighbours; the rule is the biome's; lines and spine are then restored;
//! 4. the component of the centre is kept (bit-parallel flood): every walkable tile is reachable
//!    from every opening, so every chunk is reachable (ADR-0006 § Joining chunks).
//! A chunk starting on an odd global row has its row parities swapped: the parity flag of point 2,
//! two constants here (`CHUNK_EVEN[1]`, the dilation's `even` mask).
//!
//! Bitmaps of 225 bits are one felt; set operations go through their two `u128` limbs and the
//! bitwise builtin (`Bits::bitwise`, one application for AND, XOR and OR). `u256` is only that pair
//! of limbs (docs/CAIRO.md §4, written reason): `u252` has no limb access.

use core::poseidon::hades_permutation;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::{Dilation, DilationTrait};
use crate::tables::{
    CHUNK_EVEN, CHUNK_INTERIOR, COL_EAST, COL_WEST, DOWN, LINE_EAST, LINE_NORTH, LINE_SOUTH,
    LINE_WEST, LOW30, ROW_NORTH, ROW_SOUTH, SPINE, UP,
};

/// Centre of a chunk, (7, 7): the flood of step 4 starts there (it lies on the spine).
pub const CENTRE: u8 = 112;
/// Passes of the automaton (step 3).
pub const PASSES: u8 = 2;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

/// A location's biome (design/18 *Biomes*): density of the base and rule of the automaton, chosen
/// by `tune.py` for the walkable share of the interior.
///
/// | Biome | Base | Born / survives | Share (design/18) |
/// |---|---|---|---|
/// | Meadow | 5/8: `a \| (b & c)` | 4+ / 3+ | 80–90 % |
/// | Forest | 5/8: `a \| (b & c)` | 4+ / 4+ | 60–70 % |
/// | Cave | 1/2: `a` | 5+ / 4+ | 45–55 % |
/// | Ruin | 3/8: `a & (b \| c)` | 4+ / 4+ | 40–50 % |
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Biome {
    Meadow,
    Forest,
    Cave,
    Ruin,
}

/// One side of a chunk at generation.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Side {
    /// No generated neighbour: 1 or 2 openings are drawn, then frozen (D-22).
    Open,
    /// The border of the location: closed (gates are not in this spike).
    Border,
    /// A generated neighbour, its terrain: its facing edge is copied.
    Copy: felt252,
}

/// The four sides, in the library's direction names: East is `x - 1`, West `x + 1`, South
/// `y - 1`, North `y + 1` (docs/needs/hexmap.md point 3).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Sides {
    pub east: Side,
    pub west: Side,
    pub south: Side,
    pub north: Side,
}

pub impl U8IntoBiome of TryInto<u8, Biome> {
    fn try_into(self: u8) -> Option<Biome> {
        match self {
            0 => Some(Biome::Meadow),
            1 => Some(Biome::Forest),
            2 => Some(Biome::Cave),
            3 => Some(Biome::Ruin),
            _ => None,
        }
    }
}

/// Generate a chunk (N-1, N-2).
/// # Arguments
/// * `word` - The random word drawn at reveal (a stand-in for `fate(domain)`)
/// * `biome` - The location's biome
/// * `sides` - What each side faces
/// * `odd` - Whether the chunk starts on an odd global row (its chunk row is odd)
/// # Returns
/// * The terrain: walkable interior tiles, plus the open tiles of the ring
pub fn generate_chunk(word: felt252, biome: Biome, sides: Sides, odd: bool) -> felt252 {
    // [Compute] 1. Base: three random bitmaps, combined to the biome's density
    let (a, b, c) = hades_permutation(word, 0, 2);
    let a: u256 = a.into();
    let b: u256 = b.into();
    let c: u256 = c.into();
    let interior: u256 = CHUNK_INTERIOR.into();
    let fill = match biome {
        Biome::Meadow => or(a, and(b, c)),
        Biome::Forest => or(a, and(b, c)),
        Biome::Cave => a,
        Biome::Ruin => and(a, or(b, c)),
    };
    let fill = and(fill, interior);
    // [Compute] Ring: each side copied, closed or drawn
    let (draw, _, _) = hades_permutation(word, 1, 2);
    let draw: u256 = draw.into();
    let mut bits = draw.low;
    let east = side(sides.east, COL_WEST, Bits::inv(14), 15, 0, ref bits);
    let west = side(sides.west, COL_EAST, Bits::pow(14), 15, 14, ref bits);
    let south = side(sides.south, ROW_NORTH, Bits::inv(210), 1, 0, ref bits);
    let north = side(sides.north, ROW_SOUTH, Bits::pow(210), 1, 210, ref bits);
    let ring = east + west + south + north;
    // [Compute] 2. Lines from the openings to the spine: East and West lines are disjoint, and so
    // are South and North ones; the two groups and the spine may cross
    let across: u256 = (east * LINE_EAST + west * LINE_WEST).into();
    let along: u256 = (south * LINE_SOUTH + north * LINE_NORTH).into();
    let lines = or(or(across, along), SPINE.into());
    // [Compute] 3. Smoothing, with the ring as margins
    let parity: u256 = (*CHUNK_EVEN.span()[if odd {
        1
    } else {
        0
    }])
        .into();
    let mut grid = or(fill, lines);
    let mut pass = PASSES;
    while pass != 0 {
        pass -= 1;
        grid = smooth(grid, ring, parity, biome);
    }
    let grid = or(grid, lines);
    // [Return] 4. The component of the centre, and the ring
    keep_component(grid, parity) + ring
}

/// The ring tiles of one side.
/// # Arguments
/// * `side` - What the side faces
/// * `edge` - The neighbour's facing edge (mask)
/// * `shift` - The product that moves that edge onto this side
/// * `step` - 2^step between two tiles of this side: 15 for a column, 1 for a row
/// * `base` - The index of the side's tile 0
/// * `bits` - Random bits, 8 consumed by a drawn side
#[inline(always)]
fn side(side: Side, edge: felt252, shift: felt252, step: u8, base: u8, ref bits: u128) -> felt252 {
    match side {
        Side::Open => {
            // [Compute] 1 or 2 openings among the 13 non-corner tiles, 4 bits each
            let (rest, first) = DivRem::div_rem(bits, 16);
            let (rest, second) = DivRem::div_rem(rest, 16);
            bits = rest;
            let first: u8 = (first % 13 + 1).try_into().unwrap();
            let second: u8 = (second % 13 + 1).try_into().unwrap();
            let one = Bits::pow(base + step * first);
            if second == first {
                one
            } else {
                one + Bits::pow(base + step * second)
            }
        },
        Side::Border => 0,
        Side::Copy(terrain) => {
            let wide: u256 = terrain.into();
            let mask: u256 = edge.into();
            let (low, _, _) = Bits::bitwise(wide.low, mask.low);
            let (high, _, _) = Bits::bitwise(wide.high, mask.high);
            Bits::to_felt(u256 { low, high }) * shift
        },
    }
}

#[inline(always)]
fn and(lhs: u256, rhs: u256) -> u256 {
    Bits::and(lhs, rhs)
}

#[inline(always)]
fn or(lhs: u256, rhs: u256) -> u256 {
    Bits::or(lhs, rhs)
}

/// One synchronous pass of the automaton on the interior, the ring counted as neighbours (the
/// margins). Plane `k` holds, at each tile, the tile of its `k`-th neighbour; they are field
/// products of the grid, exact: the corners are wall (bit 0 is clear for the West plane) and the
/// planes that look North drop rows 0 and 1 first (targets on row 0 are ring, never evolved).
/// # Arguments
/// * `grid` - The walkable interior tiles
/// * `ring` - The open ring tiles
/// * `even` - The rows on even global rows
/// * `biome` - The rule
/// # Returns
/// * The next walkable interior tiles
#[inline]
pub fn smooth(grid: u256, ring: felt252, even: u256, biome: Biome) -> u256 {
    let all = Bits::to_felt(grid) + ring;
    let wide: u256 = all.into();
    // [Compute] Split by global row parity
    let parted = and(wide, even);
    let ge = Bits::to_felt(parted);
    let go = all - ge;
    let odd_low = wide.low - parted.low;
    // [Compute] The same without rows 0 and 1, for the planes that look North
    let (drop_even, _, _) = Bits::bitwise(parted.low, LOW30);
    let (drop_odd, _, _) = Bits::bitwise(odd_low, LOW30);
    let ne = ge - drop_even.into();
    let no = go - drop_odd.into();
    // [Compute] The 6 neighbour planes: East, West, the two South, the two North
    let p1: u256 = (all + all).into();
    let p2: u256 = (all * INV_2).into();
    let p3: u256 = (all * 0x8000).into();
    let p4: u256 = (go * 0x10000 + ge * 0x4000).into();
    let p5: u256 = ((ne + no) * Bits::inv(15)).into();
    let p6: u256 = (no * Bits::inv(14) + ne * Bits::inv(16)).into();
    let interior: u256 = CHUNK_INTERIOR.into();
    let low = rule(grid.low, p1.low, p2.low, p3.low, p4.low, p5.low, p6.low, interior.low, biome);
    let high = rule(
        grid.high, p1.high, p2.high, p3.high, p4.high, p5.high, p6.high, interior.high, biome,
    );
    u256 { low, high }
}

/// The rule on one limb: the neighbours counted bit-sliced (`count = 4 b2 + 2 b1 + b0`), then the
/// biome's born and survive thresholds, cut to the interior.
#[inline(always)]
fn rule(
    grid: u128, a: u128, b: u128, c: u128, d: u128, e: u128, f: u128, inside: u128, biome: Biome,
) -> u128 {
    // [Compute] Two full adders, then the weight-1 half adder and the weight-2 full adder
    let (ab, x, _) = Bits::bitwise(a, b);
    let (xc, s1, _) = Bits::bitwise(x, c);
    let (de, y, _) = Bits::bitwise(d, e);
    let (yf, s2, _) = Bits::bitwise(y, f);
    let (c0, b0, _) = Bits::bitwise(s1, s2);
    let (both, either, _) = Bits::bitwise(ab + xc, de + yf);
    let (carry, b1, _) = Bits::bitwise(either, c0);
    let b2 = both + carry;
    // [Compute] Thresholds
    let next = match biome {
        // Born with 4+, survives with 3+: (grid & (b2 | b1 & b0)) | b2
        Biome::Meadow => {
            let (pair, _, _) = Bits::bitwise(b1, b0);
            let (_, _, three) = Bits::bitwise(b2, pair);
            let (stay, _, _) = Bits::bitwise(grid, three);
            let (_, _, next) = Bits::bitwise(stay, b2);
            next
        },
        // Born and survives with 4+
        Biome::Forest => b2,
        // Born with 5+, survives with 4+: (grid & b2) | (b2 & (b1 | b0))
        Biome::Cave => {
            let (_, _, one) = Bits::bitwise(b1, b0);
            let (five, _, _) = Bits::bitwise(b2, one);
            let (stay, _, _) = Bits::bitwise(grid, b2);
            let (_, _, next) = Bits::bitwise(stay, five);
            next
        },
        Biome::Ruin => b2,
    };
    let (next, _, _) = Bits::bitwise(next, inside);
    next
}

/// The walkable tiles connected to the centre, a flood with the library's hex dilation on the
/// chunk's parity (the `even` mask of the dilation is the parity flag). At most 169 layers (the
/// interior).
/// # Arguments
/// * `grid` - The walkable interior tiles, the centre among them
/// * `even` - The rows on even global rows
#[inline]
pub fn keep_component(grid: u256, even: u256) -> felt252 {
    let step = Dilation { even_low: even.low, even_high: even.high, up: UP, down: DOWN };
    let centre: u256 = Bits::pow(CENTRE).into();
    let mut low = centre.low;
    let mut high = centre.high;
    let mut free_low = grid.low - low;
    let mut free_high = grid.high - high;
    loop {
        let felt: felt252 = low.into() + high.into() * 0x100000000000000000000000000000000;
        if felt == 0 {
            break;
        }
        let (next_low, next_high) = step.dilate(low, high, felt);
        let (next_low, _, _) = Bits::bitwise(next_low, free_low);
        let (next_high, _, _) = Bits::bitwise(next_high, free_high);
        free_low -= next_low;
        free_high -= next_high;
        low = next_low;
        high = next_high;
    }
    Bits::to_felt(grid) - free_low.into() - free_high.into() * 0x100000000000000000000000000000000
}
