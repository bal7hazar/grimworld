//! The rectangle's generation with margins: SPK-7's `generate_chunk`
//! (`spikes/SPK-7/src/chunk.cairo`, measured there at 0.39-0.45 M on `origami_hexmap` 1.8.0), on
//! `hexx` at 93639f2c17e3, so that both shapes are measured on the same basis. The algorithm and
//! its steps are SPK-7's, unchanged: base, sides copied, closed or drawn, lines to a spine,
//! 2 passes of the automaton with the ring as margins, the component of the centre.

use core::poseidon::hades_permutation;
use hexx::board::bits::Bits;
use hexx::board::layout::{Dilation, DilationTrait};
use crate::automaton::AutomatonTrait;
use crate::tables::{
    RECT_COL_EAST, RECT_COL_WEST, RECT_DOWN, RECT_EVEN, RECT_INTERIOR, RECT_LINE_EAST,
    RECT_LINE_NORTH, RECT_LINE_SOUTH, RECT_LINE_WEST, RECT_LOW30, RECT_ROW_NORTH, RECT_ROW_SOUTH,
    RECT_SPINE, RECT_UP,
};
use crate::types::{Biome, RectSides, Side};

/// Centre of a chunk, (7, 7).
pub const CENTRE: u8 = 112;
/// Passes of the automaton.
pub const PASSES: u8 = 2;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

#[generate_trait]
pub impl RectChunkImpl of RectChunkTrait {
    /// Generate a 15 x 15 chunk (SPK-7).
    /// # Arguments
    /// * `word` - The random word
    /// * `biome` - The location's biome
    /// * `sides` - What each side faces
    /// * `odd` - Whether the chunk starts on an odd global row
    /// # Returns
    /// * The terrain: walkable interior tiles, plus the open tiles of the ring
    fn generate(word: felt252, biome: Biome, sides: RectSides, odd: bool) -> felt252 {
        // [Compute] 1. Base
        let (a, b, c) = hades_permutation(word, 0, 2);
        let a: u256 = a.into();
        let b: u256 = b.into();
        let c: u256 = c.into();
        let interior: u256 = RECT_INTERIOR.into();
        let fill = match biome {
            Biome::Meadow => Bits::or(a, Bits::and(b, c)),
            Biome::Forest => Bits::or(a, Bits::and(b, c)),
            Biome::Cave => a,
            Biome::Ruin => Bits::and(a, Bits::or(b, c)),
        };
        let fill = Bits::and(fill, interior);
        // [Compute] Ring
        let (draw, _, _) = hades_permutation(word, 1, 2);
        let draw: u256 = draw.into();
        let mut bits = draw.low;
        let east = Self::side(sides.east, RECT_COL_WEST, Bits::inv(14), 15, 0, ref bits);
        let west = Self::side(sides.west, RECT_COL_EAST, Bits::pow(14), 15, 14, ref bits);
        let south = Self::side(sides.south, RECT_ROW_NORTH, Bits::inv(210), 1, 0, ref bits);
        let north = Self::side(sides.north, RECT_ROW_SOUTH, Bits::pow(210), 1, 210, ref bits);
        let ring = east + west + south + north;
        // [Compute] 2. Lines to the spine
        let across: u256 = (east * RECT_LINE_EAST + west * RECT_LINE_WEST).into();
        let along: u256 = (south * RECT_LINE_SOUTH + north * RECT_LINE_NORTH).into();
        let lines = Bits::or(Bits::or(across, along), RECT_SPINE.into());
        // [Compute] 3. Smoothing, with the ring as margins
        let parity: u256 = (*RECT_EVEN.span()[if odd {
            1
        } else {
            0
        }]).into();
        let mut grid = Bits::or(fill, lines);
        let mut pass = PASSES;
        while pass != 0 {
            pass -= 1;
            grid = Self::smooth(grid, ring, parity, biome);
        }
        let grid = Bits::or(grid, lines);
        // [Return] 4. The component of the centre, and the ring
        Self::keep_component(grid, parity) + ring
    }

    /// The ring tiles of one side (SPK-7's `side`).
    #[inline(always)]
    fn side(
        side: Side, edge: felt252, shift: felt252, step: u8, base: u8, ref bits: u128,
    ) -> felt252 {
        match side {
            Side::Open => {
                let (rest, two) = DivRem::div_rem(bits, 2);
                let (rest, first) = DivRem::div_rem(rest, 16);
                let (rest, second) = DivRem::div_rem(rest, 16);
                bits = rest;
                let first: u8 = (first % 13 + 1).try_into().unwrap();
                let second: u8 = (second % 13 + 1).try_into().unwrap();
                let one = Bits::pow(base + step * first);
                if two == 0 || second == first {
                    one
                } else {
                    one + Bits::pow(base + step * second)
                }
            },
            Side::Border => 0,
            Side::Copy(terrain) => {
                let wide: u256 = terrain.into();
                let mask: u256 = edge.into();
                Bits::to_felt(Bits::and(wide, mask)) * shift
            },
        }
    }

    /// One pass of the automaton (SPK-7's `smooth`).
    #[inline]
    fn smooth(grid: u256, ring: felt252, even: u256, biome: Biome) -> u256 {
        let all = Bits::to_felt(grid) + ring;
        let wide: u256 = all.into();
        let parted = Bits::and(wide, even);
        let ge = Bits::to_felt(parted);
        let go = all - ge;
        let odd_low = wide.low - parted.low;
        let (drop_even, _, _) = Bits::bitwise(parted.low, RECT_LOW30);
        let (drop_odd, _, _) = Bits::bitwise(odd_low, RECT_LOW30);
        let ne = ge - drop_even.into();
        let no = go - drop_odd.into();
        let p1: u256 = (all + all).into();
        let p2: u256 = (all * INV_2).into();
        let p3: u256 = (all * 0x8000).into();
        let p4 = Bits::or((go * 0x10000).into(), (ge * 0x4000).into());
        let p5: u256 = ((ne + no) * Bits::inv(15)).into();
        let p6 = Bits::or((no * Bits::inv(14)).into(), (ne * Bits::inv(16)).into());
        let interior: u256 = RECT_INTERIOR.into();
        let low = AutomatonTrait::rule(
            grid.low, p1.low, p2.low, p3.low, p4.low, p5.low, p6.low, interior.low, biome,
        );
        let high = AutomatonTrait::rule(
            grid.high, p1.high, p2.high, p3.high, p4.high, p5.high, p6.high, interior.high, biome,
        );
        u256 { low, high }
    }

    /// The walkable tiles connected to the centre (SPK-7's `keep_component`).
    #[inline]
    fn keep_component(grid: u256, even: u256) -> felt252 {
        let step = Dilation {
            even_low: even.low, even_high: even.high, up: RECT_UP, down: RECT_DOWN,
        };
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
        Bits::to_felt(grid)
            - free_low.into()
            - free_high.into() * 0x100000000000000000000000000000000
    }
}
