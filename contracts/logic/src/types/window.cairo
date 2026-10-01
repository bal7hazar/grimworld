//! The game's geometry on the window (ENG-02, D-173): the board of a tick (design/02, 15 columns ×
//! 16 rows, assembled at each tick by ENG-07, never stored), and what the rules ask of it, on
//! `hexx` 0.1.0-rc.1. A value type with its behaviour, as `World`: it sits in `types/` (CAIRO.md §7,
//! D-147). This trait is frozen: the executor (CBT-05a) consumes it.
//!
//! **Positions.** A tile of the window is its position `15 y + x` (`hexx`'s layout: pointy-top,
//! odd-r offset, `+1` is West, `+15` is North; `x` below 15, `y` below 16), the window's own index,
//! 0 to 239. A facing is a direction `0..=5`: East, North-East, North-West, West, South-West,
//! South-East (`actions`, the map library's order, `hexx::board::direction::Direction`'s indices).
//!
//! **The rules** (design/04 *Ranges*, *Line of sight*, *Facing and arcs*; design/19 §2.3, §5.3
//! step 3, §5.5 step 1, §5.6):
//! - `sight`: a fixed integer hex line between the two tiles; walls block, actors do not (an actor
//!   is not in the window's walls); the two ends are not tested. When the line passes exactly
//!   between two tiles, the lower tile index is taken. `hexx`'s line (N-5) has this rule: element
//!   `i` of the line is the tile nearest `A + (i / N)(B − A)`, at a tie the smaller row, and on the
//!   same row the smaller column (`LineTrait::line`, `HexTrait::line_to`); the tests hold it against
//!   an oracle written from design/04's sentence alone (`Oracle::line`). The arc and the facing
//!   read only the line's first step, computed in constant time by the same rule
//!   (`WindowInternal::step`), held against the same oracle.
//! - `reach`: the target of an action within its range (design/04's table, `range`: touch 1, ranged
//!   6) and in sight. Adjacent tiles have no tile between them: touch is never blocked. A radius
//!   that needs no sight (alert, earshot) is a `distance`.
//! - `arc`: the arc of the target's facing in which the hit arrives: the source's tile when
//!   adjacent, at range the tile the line of sight arrives from (the tile of the line next to the
//!   target), in `d` front, `d ± 1` front-side, `d ± 2` rear-side, `d + 3` back.
//! - `front`: whether the target stands on the source's front tile (Blind's miss, §5.6).
//! - `facing`: the facing an action turns to (§5.3 step 3): toward the moved-to tile or the target;
//!   a target not adjacent, the direction of the first step of the hex line.
//! - `shape`: a shape's tiles from a centre (§2.3: `SINGLE`, `RING_1`, `DISC_1`, `DISC_2`,
//!   `DISC_3`, by hex distance), as a bitmap of the window: bit `p` is the tile `p`, so its order is
//!   ascending tile index, the order of the executor's actor list (§5.14 step 4). A tile outside the
//!   window is skipped; a wall holds no actor and is skipped. `tiles` lists a bitmap's positions in
//!   that order.
//!
//! **Edges (D-140).** A rule never panics on a legal action:
//! - a position outside the window (240 and up): no sight, no reach, no arc, not in front, the
//!   facing unchanged, an empty shape;
//! - the same tile: in sight (no tile between), no arc (a hit never comes from the target's own
//!   tile: two actors never share one), not in front, the facing unchanged, a shape as any other;
//! - a line that leaves the window between two of its tiles (at a tie on a row of the edge, the
//!   lower index may be the column `−1`): no sight, as a wall (`hexx` D-27). Sight has radius 6
//!   around the adventurer and the window's ring is 7 tiles away (design/02): a line between two
//!   tiles within 6 of the adventurer never leaves the window. The arc and the facing need only
//!   the line's first step, a direction, which needs no board: they are defined there too;
//! - a wall at an end of the line: not tested (an actor never stands on a wall).
//! A facing above 5 or a shape id outside 1–5 is a stored value the pipeline refuses: asserted.
//!
//! **Cost** (ENG-01 §9.2, this lot's row): one call is the difference between the snforge totals
//! of `tests::test_cost_*_twice` and `_once` (its inputs opaque to the compiler; each figure holds
//! about 2,440 of the benchmark's own, three opaque inputs and the check). `sight` 19,726 (`hexx`'s
//! table path, any pair within 6); `reach` 32,176; `arc` 25,140 adjacent, 25,240 at range or on
//! the window's ring (the line's first step in constant time); `front` 11,850; `facing` 22,500
//! on every path; `shape` `DISC_1` 14,656 away from the window's ring, 69,926 on it, `DISC_3`
//! 137,106; `tiles` of 7 tiles 57,151.

use core::num::traits::Zero;
use hexx::board::bits::Bits;
use hexx::board::direction::{Arc as BoardArc, Direction, DirectionTrait};
use hexx::board::layout::LayoutTrait;
use hexx::board::line::LineTrait;
use hexx::board::map::HexMap;
use crate::types::combat::Arc;
use crate::types::effect::shape;

/// The window's columns, rows and tiles (design/02, D-120).
pub const WIDTH: u8 = 15;
pub const HEIGHT: u8 = 16;
pub const SIZE: u8 = 240;

/// The ranges of design/04's table, in tiles (hex distance).
pub mod range {
    /// Melee, touch skills.
    pub const TOUCH: u8 = 1;
    /// Small area effects.
    pub const NEARBY: u8 = 2;
    /// Large area effects.
    pub const AREA: u8 = 3;
    /// Goblin perception (design/18).
    pub const ALERT: u8 = 5;
    /// Bows, spells: requires line of sight.
    pub const RANGED: u8 = 6;
    /// Shouts, pack alert propagation.
    pub const EARSHOT: u8 = 8;
}

pub mod errors {
    pub const OPEN: felt252 = 'window: open above 240';
    pub const FACING: felt252 = 'window: facing';
    pub const SHAPE: felt252 = 'window: shape';
}

/// `2^112`: the high limb of a bitmap of the window is below it.
const HIGH_LIMIT: u128 = 0x10000000000000000000000000000;
/// 2, as a divisor.
const TWO: NonZero<u8> = 2;
/// 15 and 30, as divisors.
const FIFTEEN: NonZero<u8> = 15;
const THIRTY: NonZero<u8> = 30;
/// 131, the smallest modulus under which the powers `2^0 … 2^127` are distinct.
const PRIME: NonZero<u128> = 131;
/// `p` at index `2^p mod 131`, for `p` below 128 (255 where no power lands).
const LOG2_MOD_131: [u8; 131] = [
    255, 0, 1, 72, 2, 46, 73, 96, 3, 14, 47, 56, 74, 18, 97, 118, 4, 43, 15, 35, 48, 38, 57, 23, 75,
    92, 19, 86, 98, 51, 119, 29, 5, 255, 44, 12, 16, 41, 36, 90, 49, 126, 39, 124, 58, 60, 24, 105,
    76, 62, 93, 115, 20, 26, 87, 102, 99, 107, 52, 82, 120, 78, 30, 110, 6, 64, 255, 71, 45, 95, 13,
    55, 17, 117, 42, 34, 37, 22, 91, 85, 50, 28, 127, 11, 40, 89, 125, 123, 59, 104, 61, 114, 25,
    101, 106, 81, 77, 109, 63, 70, 94, 54, 116, 33, 21, 84, 27, 10, 88, 122, 103, 113, 100, 80, 108,
    69, 53, 32, 83, 9, 121, 112, 79, 68, 31, 8, 111, 67, 7, 66, 65,
];
/// The six neighbours of an interior tile as relative offsets summed in the field (`hexx`'s
/// `LayoutTrait::neighbor_mask` on the width 15; an offset `−k` is `2^−k`): an odd row
/// `{−1, +1, +15, +16, −15, −14}`, an even row `{−1, +1, +14, +15, −16, −15}`.
const AROUND_ODD: felt252 = 0x3ffd000000000087f9a00000000000000000000000000000000000000018003;
const AROUND_EVEN: felt252 = 0x3ffe800000000087fcd0000000000000000000000000000000000000000c003;

/// The board of a tick: bit `p` of `open` is 1 when the tile `p` is walkable, 0 for a wall (an
/// unrevealed or void chunk is wall, design/02). Bits 240 and up are 0.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Window {
    pub open: felt252,
}

/// A move between two tiles in `q` and `r` (`GeometryTrait::to_axial`): magnitudes and signs.
#[derive(Copy, Drop)]
struct Delta {
    q: u8,
    q_negative: bool,
    r: u8,
    r_negative: bool,
}

#[generate_trait]
pub impl WindowImpl of WindowTrait {
    /// The window of an assembled board.
    fn new(open: felt252) -> Window {
        WindowAssert::assert_valid_open(open);
        Window { open }
    }

    /// Whether a position is a tile of the window.
    #[inline(always)]
    fn inside(position: u8) -> bool {
        position < SIZE
    }

    /// The hex distance between two tiles of the window (walls ignored).
    fn distance(from: u8, to: u8) -> u8 {
        WindowInternal::length(WindowInternal::delta(from, to))
    }

    /// Whether `from` sees `to`: every tile strictly between them on the line is walkable, at a tie
    /// the lower tile index (design/04). False when either is outside the window or the line leaves
    /// it.
    fn sight(self: @Window, from: u8, to: u8) -> bool {
        if !(Self::inside(from) && Self::inside(to)) {
            return false;
        }
        WindowInternal::map(*self.open).line_of_sight(from, to)
    }

    /// Whether `to` is within `range` of `from` and in its sight (design/04: ranged 6 requires line
    /// of sight; touch, at 1, has no tile between).
    fn reach(self: @Window, from: u8, to: u8, range: u8) -> bool {
        if !(Self::inside(from) && Self::inside(to)) {
            return false;
        }
        if WindowInternal::length(WindowInternal::delta(from, to)) > range {
            return false;
        }
        WindowInternal::map(*self.open).line_of_sight(from, to)
    }

    /// The arc of the target's facing a hit from `source` arrives from (§5.5 step 1): the source's
    /// tile when adjacent, else the tile the line of sight arrives from, that is the first step of
    /// the line from the target (the line is symmetric). `None` for the same tile or a position
    /// outside the window. Walls are not read: the caller checked `reach` first.
    fn arc(source: u8, target: u8, facing: u8) -> Option<Arc> {
        let facing = WindowAssert::facing(facing);
        if !(Self::inside(source) && Self::inside(target)) || source == target {
            return None;
        }
        let direction = WindowInternal::step(WindowInternal::delta(target, source));
        Some(
            match direction.arc(facing) {
                BoardArc::Front => Arc::Front,
                BoardArc::FrontSide => Arc::FrontSide,
                BoardArc::RearSide => Arc::RearSide,
                BoardArc::Back => Arc::Back,
            },
        )
    }

    /// Whether `target` stands on the front tile of `source` facing `facing` (§5.6, Blind).
    fn front(source: u8, facing: u8, target: u8) -> bool {
        let facing = WindowAssert::facing(facing);
        if !(Self::inside(source) && Self::inside(target)) {
            return false;
        }
        LayoutTrait::neighbor(WIDTH, HEIGHT, source, facing) == Some(target)
    }

    /// The facing of an actor on `from` after an action toward `to` (§5.3 step 3): the direction
    /// of `to` when adjacent, else of the first step of the hex line; `facing` unchanged for the
    /// same tile or a position outside the window.
    fn facing(from: u8, to: u8, facing: u8) -> u8 {
        WindowAssert::facing(facing);
        if !(Self::inside(from) && Self::inside(to)) || from == to {
            return facing;
        }
        WindowInternal::step(WindowInternal::delta(from, to)).into()
    }

    /// The tiles of a shape (`effect::shape`) centred on `centre`, clipped to the window and to its
    /// walls: bit `p` for the tile `p`, ascending tile index. Empty for a centre outside the window.
    fn shape(self: @Window, shape: u8, centre: u8) -> felt252 {
        if !Self::inside(centre) {
            WindowAssert::assert_valid_shape(shape);
            return 0;
        }
        let tiles = if shape == shape::SINGLE {
            Bits::pow(centre)
        } else if shape == shape::RING_1 {
            WindowInternal::neighbours(centre, 0)
        } else if shape == shape::DISC_1 {
            WindowInternal::neighbours(centre, 1)
        } else if shape == shape::DISC_2 {
            WindowInternal::disc(centre, 2)
        } else if shape == shape::DISC_3 {
            WindowInternal::disc(centre, 3)
        } else {
            core::panic_with_felt252(errors::SHAPE)
        };
        let tiles: u256 = tiles.into();
        Bits::to_felt(Bits::and(tiles, (*self.open).into()))
    }

    /// The positions of a bitmap of the window, ascending.
    fn tiles(mask: felt252) -> Span<u8> {
        let wide: u256 = mask.into();
        let mut tiles: Array<u8> = array![];
        WindowInternal::limb(ref tiles, wide.low, 0);
        WindowInternal::limb(ref tiles, wide.high, 128);
        tiles.span()
    }
}

#[generate_trait]
impl WindowInternal of WindowInternalTrait {
    /// The `hexx` map of the window.
    #[inline(always)]
    fn map(open: felt252) -> HexMap {
        HexMap { width: WIDTH, height: HEIGHT, grid: open, seed: 0 }
    }

    /// `(q + 7, r)` of a tile, `q = x − ⌊y/2⌋`, `r = y` (`GeometryTrait::to_axial`), shifted so
    /// that it is never negative: one division by 30 gives `⌊y/2⌋` and the column.
    #[inline(always)]
    fn axial(position: u8) -> (u8, u8) {
        let (pair, rest) = DivRem::div_rem(position, THIRTY);
        if rest < WIDTH {
            (rest + 7 - pair, pair + pair)
        } else {
            (rest - WIDTH + 7 - pair, pair + pair + 1)
        }
    }

    /// The move from `from` to `to` in `q` and `r` as magnitudes and signs, on `u8` (no signed
    /// arithmetic: `GeometryTrait::distance`'s way).
    #[inline(always)]
    fn delta(from: u8, to: u8) -> Delta {
        let (q_from, r_from) = Self::axial(from);
        let (q_to, r_to) = Self::axial(to);
        let (q, q_negative) = if q_to >= q_from {
            (q_to - q_from, false)
        } else {
            (q_from - q_to, true)
        };
        let (r, r_negative) = if r_to >= r_from {
            (r_to - r_from, false)
        } else {
            (r_from - r_to, true)
        };
        Delta { q, q_negative, r, r_negative }
    }

    /// `|ds| = |dq + dr|`: the sum of the magnitudes when `dq` and `dr` have one sign, else their
    /// difference.
    #[inline(always)]
    fn s(delta: Delta) -> u8 {
        if delta.q_negative == delta.r_negative {
            delta.q + delta.r
        } else if delta.q > delta.r {
            delta.q - delta.r
        } else {
            delta.r - delta.q
        }
    }

    /// The hex distance of a move: `max(|dq|, |dr|, |ds|)`.
    #[inline(always)]
    fn length(delta: Delta) -> u8 {
        if delta.q_negative == delta.r_negative {
            delta.q + delta.r
        } else if delta.q > delta.r {
            delta.q
        } else {
            delta.r
        }
    }

    /// The first step of design/04's line along a move that is not zero: the neighbour nearest the
    /// point `(dq, dr, ds) / N` (element 1 of the line), `N` the distance. An axis of largest
    /// magnitude moves by its sign; of the two others (both of the opposite sign) the larger moves.
    /// When they are equal the point lies exactly between two tiles and the lower tile index is
    /// taken: if `r` is the largest, both candidates are on one row and the smaller `q` is the
    /// smaller column; otherwise they are on two rows and the lower row is taken. In `q` and `r`
    /// the six directions are East `(−1, 0)`, North-East `(−1, 1)`, North-West `(0, 1)`, West
    /// `(1, 0)`, South-West `(1, −1)`, South-East `(0, −1)`.
    fn step(delta: Delta) -> Direction {
        let (q, r, s) = (delta.q, delta.r, Self::s(delta));
        let (move_q, move_r) = if r >= q && r >= s {
            // [Compute] `r` moves; `q` too when it is the larger of `q` and `s`, or at a tie when
            // it decreases
            (q > s || (q == s && delta.q_negative), true)
        } else if q >= s {
            // [Compute] `q` moves; `r` too when it is the larger of `r` and `s`, or at a tie when
            // it decreases
            (true, r > s || (r == s && delta.r_negative))
        } else {
            // [Compute] `s` moves; then `r` when it is the larger of `q` and `r`, or at a tie
            // when it decreases, else `q`
            let move_r = r > q || (r == q && delta.r_negative);
            (!move_r, move_r)
        };
        if !move_r {
            if delta.q_negative {
                Direction::East
            } else {
                Direction::West
            }
        } else if !delta.r_negative {
            if move_q {
                Direction::NorthEast
            } else {
                Direction::NorthWest
            }
        } else if move_q {
            Direction::SouthWest
        } else {
            Direction::SouthEast
        }
    }

    /// The tiles of `DISC_1` (`with_centre` 1) or `RING_1` (0): for an interior centre (columns
    /// 1–13, rows 1–14) one product, `2^c × (M + with_centre)`, `M` the field sum of the relative
    /// offsets of the centre's row parity (`hexx`'s `neighbor_mask` on the width 15, its constant
    /// written out); on the window's ring, the rows of `disc`.
    #[inline(always)]
    fn neighbours(centre: u8, with_centre: felt252) -> felt252 {
        let (y, x) = DivRem::div_rem(centre, FIFTEEN);
        if x == 0 || y == 0 || x == WIDTH - 1 || y == HEIGHT - 1 {
            return Self::disc(centre, 1) - Bits::pow(centre) + with_centre * Bits::pow(centre);
        }
        let (_, odd) = DivRem::div_rem(y, TWO);
        let offsets = if odd == 1 {
            AROUND_ODD
        } else {
            AROUND_EVEN
        };
        Bits::pow(centre) * (offsets + with_centre)
    }

    /// The tiles within `radius` (1 to 3) of `centre` (hex distance), clipped to the window: one
    /// row segment per row `y' = y + dr`. With `q = x − ⌊y/2⌋` (`GeometryTrait::to_axial`), the
    /// tiles of the row at distance at most `R` have `dq` in `[max(−R, −R − dr), min(R, R − dr)]`,
    /// that is the columns `x + dq + ⌊y'/2⌋ − ⌊y/2⌋`. Computed on `u8` shifted by `R` and `2R` (no
    /// negative value): row `k = dr + R` in `0..=2R`, columns `+ 2R`. At most 7 rows.
    fn disc(centre: u8, radius: u8) -> felt252 {
        let (y, x) = DivRem::div_rem(centre, FIFTEEN);
        let (half, _) = DivRem::div_rem(y, TWO);
        let double = radius + radius;
        let edge = WIDTH - 1 + double;
        let mut tiles: felt252 = 0;
        let mut k: u8 = 0;
        while k <= double {
            // [Check] The row `y + k − R` in the window
            let shifted = y + k;
            if shifted >= radius && shifted < HEIGHT + radius {
                let row = shifted - radius;
                let (row_half, _) = DivRem::div_rem(row, TWO);
                // [Compute] `x + ⌊y'/2⌋ − ⌊y/2⌋ + R`, then `dq + R` in
                // `[max(0, R − k), min(2R, 3R − k)]`
                let start = x + row_half + radius - half;
                let low = if k < radius {
                    radius - k
                } else {
                    0
                };
                let high = if k > radius {
                    double + radius - k
                } else {
                    double
                };
                let (first, last) = (start + low, start + high);
                // [Compute] Clipped to the columns `2R..=14 + 2R`
                if last >= double && first <= edge {
                    let first = if first < double {
                        0
                    } else {
                        first - double
                    };
                    let last = if last > edge {
                        WIDTH - 1
                    } else {
                        last - double
                    };
                    let base = row * WIDTH;
                    tiles += Bits::pow(base + last + 1) - Bits::pow(base + first);
                }
            }
            k += 1;
        }
        tiles
    }

    /// Appends the positions of one limb, ascending: the lowest set bit `2^p`, `p` read from
    /// `LOG2_MOD_131` at `2^p mod 131`, then cleared.
    fn limb(ref tiles: Array<u8>, value: u128, offset: u8) {
        let log2 = LOG2_MOD_131.span();
        let mut rest = value;
        while rest.is_non_zero() {
            let cleared = rest & (rest - 1);
            let (_, key) = DivRem::div_rem(rest - cleared, PRIME);
            let key: u32 = key.try_into().unwrap();
            tiles.append(offset + *log2.at(key));
            rest = cleared;
        }
    }
}

#[generate_trait]
pub impl WindowAssert of WindowAssertTrait {
    /// No bit at or above 240.
    fn assert_valid_open(open: felt252) {
        let wide: u256 = open.into();
        assert(wide.high < HIGH_LIMIT, errors::OPEN);
    }

    /// A shape id of `effect::shape`.
    fn assert_valid_shape(shape: u8) {
        assert(shape >= shape::SINGLE && shape <= shape::DISC_3, errors::SHAPE);
    }

    /// The direction of a facing `0..=5`.
    #[inline(always)]
    fn facing(facing: u8) -> Direction {
        match facing.try_into() {
            Some(direction) => direction,
            None => core::panic_with_felt252(errors::FACING),
        }
    }
}

#[cfg(test)]
mod tests {
    use hexx::board::bits::Bits;
    use hexx::board::layout::LayoutTrait;
    use hexx::board::line::LineTrait;
    use hexx::board::map::HexMap;
    use crate::types::combat::Arc;
    use crate::types::effect::shape;
    use super::{HEIGHT, SIZE, WIDTH, Window, WindowTrait, range};

    /// Every tile walkable: `2^240 − 1`.
    const OPEN: felt252 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// The position of `(x, y)`.
    fn at(x: u8, y: u8) -> u8 {
        y * WIDTH + x
    }

    fn open() -> Window {
        WindowTrait::new(OPEN)
    }

    /// The window with walls on `walls`.
    fn walled(walls: Span<u8>) -> Window {
        let mut open = OPEN;
        for wall in walls {
            open -= hexx::board::bits::Bits::pow(*wall);
        }
        WindowTrait::new(open)
    }

    // ---- Oracles, written from the design's sentences ------------------------------------------

    #[generate_trait]
    impl Oracle of OracleTrait {
        /// `(q, r)` of a tile, `q = x − ⌊y/2⌋` (any integer column, `−1` and `15` included).
        fn axial(x: i32, y: i32) -> (i32, i32) {
            (x - Self::floor(y, 2), y)
        }

        fn floor(a: i32, n: i32) -> i32 {
            let q = a / n;
            if a % n != 0 && a < 0 {
                q - 1
            } else {
                q
            }
        }

        fn abs(a: i32) -> i32 {
            if a < 0 {
                -a
            } else {
                a
            }
        }

        fn distance(from: u8, to: u8) -> i32 {
            let (q1, r1) = Self::axial((from % WIDTH).into(), (from / WIDTH).into());
            let (q2, r2) = Self::axial((to % WIDTH).into(), (to / WIDTH).into());
            let (dq, dr) = (q2 - q1, r2 - r1);
            let s = Self::abs(dq + dr);
            let m = if Self::abs(dq) > Self::abs(dr) {
                Self::abs(dq)
            } else {
                Self::abs(dr)
            };
            if s > m {
                s
            } else {
                m
            }
        }

        /// design/04's line, by its sentence: element `i` of `N` is the tile nearest the point
        /// `A + (i / N)(B − A)` (the tile whose hexagon holds it: in cube coordinates
        /// `max(|Δq − Δr|, |Δr − Δs|, |Δs − Δq|) ≤ 1`); when the point lies exactly between two
        /// tiles, the lower tile index (the smaller row, then the smaller column). Returns the
        /// tiles strictly between the ends in order, `None` when a chosen tile is outside the
        /// window.
        fn line(from: u8, to: u8) -> Option<Array<u8>> {
            let n = Self::distance(from, to);
            let (qa, ra) = Self::axial((from % WIDTH).into(), (from / WIDTH).into());
            let (qb, rb) = Self::axial((to % WIDTH).into(), (to / WIDTH).into());
            let mut tiles: Array<u8> = array![];
            let mut i = 1;
            while i < n {
                // The point, scaled by `N`
                let pq = n * qa + i * (qb - qa);
                let pr = n * ra + i * (rb - ra);
                let ps = -pq - pr;
                let (q0, r0) = (Self::floor(pq, n), Self::floor(pr, n));
                // Candidates in ascending index: rows, then columns (`x = q + ⌊r/2⌋` grows with q)
                let mut chosen: Option<(i32, i32)> = None;
                let mut r = r0 - 1;
                while r <= r0 + 2 && chosen.is_none() {
                    let mut q = q0 - 2;
                    while q <= q0 + 2 {
                        let (dq, dr) = (pq - n * q, pr - n * r);
                        let ds = ps - n * (-q - r);
                        if Self::abs(dq - dr) <= n
                            && Self::abs(dr - ds) <= n
                            && Self::abs(ds - dq) <= n {
                            chosen = Some((q + Self::floor(r, 2), r));
                            break;
                        }
                        q += 1;
                    }
                    r += 1;
                }
                let (x, y) = chosen.unwrap();
                if x < 0 || x >= WIDTH.into() || y < 0 || y >= HEIGHT.into() {
                    return None;
                }
                let (x, y): (u8, u8) = (x.try_into().unwrap(), y.try_into().unwrap());
                tiles.append(at(x, y));
                i += 1;
            }
            Some(tiles)
        }

        /// The direction from `from` to its neighbour `to`, by the offsets of design/02's
        /// directions on the odd-r layout.
        fn direction(from: u8, to: u8) -> u8 {
            let mut d: u8 = 0;
            loop {
                assert(d < 6, 'oracle: not adjacent');
                if LayoutTrait::neighbor(WIDTH, HEIGHT, from, d.try_into().unwrap()) == Some(to) {
                    break d;
                }
                d += 1;
            }
        }

        /// design/04's arcs: `(d − facing) mod 6` is 0 front, 1 or 5 front-side, 2 or 4
        /// rear-side, 3 back.
        fn arc(direction: u8, facing: u8) -> Arc {
            let turn = (direction + 6 - facing) % 6;
            if turn == 0 {
                Arc::Front
            } else if turn == 1 || turn == 5 {
                Arc::FrontSide
            } else if turn == 3 {
                Arc::Back
            } else {
                Arc::RearSide
            }
        }

        /// The tiles within `radius` of `centre`, by testing every tile of the window.
        fn disc(centre: u8, radius: u8) -> felt252 {
            let mut tiles: felt252 = 0;
            let mut p: u8 = 0;
            while p != SIZE {
                if Self::distance(centre, p) <= radius.into() {
                    tiles += hexx::board::bits::Bits::pow(p);
                }
                p += 1;
            }
            tiles
        }
    }

    /// The oracle's line as a bitmap.
    fn mask(tiles: Span<u8>) -> felt252 {
        let mut mask: felt252 = 0;
        for tile in tiles {
            mask += hexx::board::bits::Bits::pow(*tile);
        }
        mask
    }

    /// Every pair from `from` to the tiles within 6: `hexx`'s line is the oracle's, both
    /// ways; the arc at range is the arc of the oracle's last tile, for each facing; the facing
    /// toward the target is the direction of the oracle's first tile.
    fn check_from(from: u8) {
        let map = HexMap { width: WIDTH, height: HEIGHT, grid: OPEN, seed: 0 };
        let mut to: u8 = 0;
        while to != SIZE {
            let n = Oracle::distance(from, to);
            assert!(WindowTrait::distance(from, to).into() == n, "distance {} {}", from, to);
            if n >= 2 && n <= 6 {
                match Oracle::line(from, to) {
                    Some(tiles) => {
                        let tiles = tiles.span();
                        assert!(map.line(from, to) == Some(mask(tiles)), "line {} {}", from, to);
                        assert!(map.line(to, from) == Some(mask(tiles)), "back {} {}", from, to);
                        let last = *tiles.at(tiles.len() - 1);
                        let first = *tiles.at(0);
                        let into = Oracle::direction(to, last);
                        let mut facing: u8 = 0;
                        while facing != 6 {
                            let arc = WindowTrait::arc(from, to, facing);
                            assert!(arc == Some(Oracle::arc(into, facing)), "arc {} {}", from, to);
                            facing += 1;
                        }
                        let turned = WindowTrait::facing(from, to, 0);
                        assert!(turned == Oracle::direction(from, first), "facing {} {}", from, to);
                    },
                    None => {
                        assert!(map.line(from, to).is_none(), "out {} {}", from, to);
                        assert!(!open().sight(from, to), "sight out {} {}", from, to);
                    },
                }
            }
            to += 1;
        }
    }

    // ---- Line of sight -----------------------------------------------------------------------

    /// AC-2: `hexx`'s line is design/04's, ties included, from both row parities at the centre.
    #[test]
    #[available_gas(l2_gas: 251973246)] // ceil(1.05 × 239974520 measured)
    fn test_line_against_oracle_centre() {
        check_from(at(7, 7));
        check_from(at(7, 8));
    }

    /// The same at the window's corners and edges, where a line can leave it.
    #[test]
    #[available_gas(l2_gas: 469602893)] // ceil(1.05 × 447240850 measured)
    fn test_line_against_oracle_edges() {
        check_from(at(0, 0));
        check_from(at(14, 15));
        check_from(at(0, 8));
        check_from(at(14, 7));
        check_from(at(7, 0));
        check_from(at(7, 15));
        check_from(at(1, 1));
        check_from(at(13, 14));
    }

    /// The tie cases of the line: a point exactly between two tiles takes the lower index.
    #[test]
    #[available_gas(l2_gas: 1274314)] // ceil(1.05 × 1213632 measured)
    fn test_line_ties() {
        let map = HexMap { width: WIDTH, height: HEIGHT, grid: OPEN, seed: 0 };
        // Two rows up, same column on an even row: between (7, 9) 142 and (6, 9) 141, 141
        assert!(map.line(at(7, 8), at(7, 10)) == Some(Bits::pow(at(6, 9))));
        // From an odd row: (7, 7) → (7, 9) passes between (8, 8) 128 and (7, 8) 127, 127
        assert!(map.line(at(7, 7), at(7, 9)) == Some(Bits::pow(at(7, 8))));
        // Δq = 2, Δr = −1, (7, 8) → (8, 7): between (8, 8) 128 and (7, 7) 112, the row below
        assert!(map.line(at(7, 8), at(8, 7)) == Some(Bits::pow(at(7, 7))));
        // The reverse direction takes the same tile (the rule does not depend on the order)
        assert!(map.line(at(8, 7), at(7, 8)) == Some(Bits::pow(at(7, 7))));
        // Δq = 1, Δr = 1, (7, 8) → (8, 9): between (8, 8) 128 and (7, 9) 142, row 8
        assert!(map.line(at(7, 8), at(8, 9)) == Some(Bits::pow(at(8, 8))));
        // Distance 4 along a tie axis: two ties, each to the lower index (the oracle's tiles)
        let tiles = Oracle::line(at(7, 8), at(7, 12)).unwrap();
        assert!(map.line(at(7, 8), at(7, 12)) == Some(mask(tiles.span())));
        assert!(tiles.span() == array![at(6, 9), at(7, 10), at(6, 11)].span());
        // Distance 6 along a tie axis: three ties
        let tiles = Oracle::line(at(7, 2), at(7, 8)).unwrap();
        assert!(map.line(at(7, 2), at(7, 8)) == Some(mask(tiles.span())));
        assert!(tiles.len() == 5);
        // A wall on the tile the tie takes blocks; a wall on the other tile does not
        assert!(!walled(array![at(6, 9)].span()).sight(at(7, 8), at(7, 10)));
        assert!(walled(array![at(7, 9)].span()).sight(at(7, 8), at(7, 10)));
        // At the window's East edge the lower index is the column −1: the line leaves the window
        assert!(map.line(at(0, 0), at(0, 2)).is_none());
        assert!(!open().sight(at(0, 0), at(0, 2)));
    }

    /// Walls block, the ends are not tested, actors are not walls; the same tile and adjacent
    /// tiles always see each other; a position outside the window sees nothing.
    #[test]
    #[available_gas(l2_gas: 239312)] // ceil(1.05 × 227916 measured)
    fn test_sight() {
        let window = walled(array![at(9, 8)].span());
        // (7, 8) → (11, 8): the row, through (9, 8)
        assert!(!window.sight(at(7, 8), at(11, 8)));
        assert!(!window.sight(at(11, 8), at(7, 8)));
        assert!(open().sight(at(7, 8), at(11, 8)));
        // The wall at an end
        assert!(window.sight(at(9, 8), at(12, 8)));
        assert!(window.sight(at(6, 8), at(9, 8)));
        // Adjacent to the wall, the same tile
        assert!(window.sight(at(8, 8), at(10, 8)) == false);
        assert!(window.sight(at(8, 8), at(8, 9)));
        assert!(window.sight(at(9, 8), at(9, 8)));
        assert!(window.sight(at(7, 8), at(7, 8)));
        // Outside the window
        assert!(!open().sight(SIZE, at(7, 8)));
        assert!(!open().sight(at(7, 8), 255));
        // A window of walls: adjacent tiles still see each other, nothing further
        let closed = WindowTrait::new(0);
        assert!(closed.sight(at(7, 8), at(8, 8)));
        assert!(!closed.sight(at(7, 8), at(9, 8)));
    }

    /// design/04's ranges: within the range and in sight.
    #[test]
    #[available_gas(l2_gas: 130778)] // ceil(1.05 × 124550 measured)
    fn test_reach() {
        let window = walled(array![at(9, 8)].span());
        assert!(window.reach(at(7, 8), at(8, 8), range::TOUCH));
        assert!(!window.reach(at(7, 8), at(10, 8), range::TOUCH));
        assert!(open().reach(at(7, 8), at(13, 8), range::RANGED));
        assert!(!open().reach(at(7, 8), at(14, 8), range::RANGED));
        assert!(!window.reach(at(7, 8), at(11, 8), range::RANGED));
        // A wall next to the attacker does not stop a touch: no tile between
        assert!(window.reach(at(8, 8), at(9, 8), range::TOUCH));
        assert!(open().reach(at(7, 8), at(7, 8), range::TOUCH));
        assert!(!open().reach(at(7, 8), SIZE, range::RANGED));
        assert!(!open().reach(SIZE, at(7, 8), range::RANGED));
        // A radius without sight (alert, earshot) is a distance
        assert!(WindowTrait::distance(at(0, 0), at(8, 0)) <= range::EARSHOT);
        assert!(WindowTrait::distance(at(0, 0), at(9, 0)) > range::EARSHOT);
        assert!(range::NEARBY == 2 && range::AREA == 3 && range::ALERT == 5);
    }

    // ---- Arcs, front, facing -----------------------------------------------------------------

    /// AC-2: each arc, for a source on each of the six neighbours and each of the six facings, on
    /// both row parities.
    #[test]
    #[available_gas(l2_gas: 2316920)] // ceil(1.05 × 2206590 measured)
    fn test_arc_melee() {
        let targets: [u8; 2] = [at(7, 7), at(7, 8)];
        for target in targets.span() {
            let target = *target;
            let mut d: u8 = 0;
            while d != 6 {
                let source = LayoutTrait::neighbor(WIDTH, HEIGHT, target, d.try_into().unwrap())
                    .unwrap();
                let mut facing: u8 = 0;
                while facing != 6 {
                    let arc = WindowTrait::arc(source, target, facing);
                    assert!(arc == Some(Oracle::arc(d, facing)), "{} {} {}", target, d, facing);
                    facing += 1;
                }
                d += 1;
            }
        }
        // East-facing target at (7, 8): from (6, 8) the front, from (8, 8) the back
        assert!(WindowTrait::arc(at(6, 8), at(7, 8), 0) == Some(Arc::Front));
        assert!(WindowTrait::arc(at(8, 8), at(7, 8), 0) == Some(Arc::Back));
        // North-East (6, 9) front-side, North-West (7, 9) rear-side
        assert!(WindowTrait::arc(at(6, 9), at(7, 8), 0) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(at(7, 9), at(7, 8), 0) == Some(Arc::RearSide));
    }

    /// At range, the arc of the tile the line of sight arrives from: from straight East the front,
    /// from straight West the back, and across a tie the lower index's tile.
    #[test]
    #[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
    fn test_arc_ranged() {
        // Target (7, 8) facing East (0); the line from (2, 8) arrives from (6, 8), East
        assert!(WindowTrait::arc(at(2, 8), at(7, 8), 0) == Some(Arc::Front));
        assert!(WindowTrait::arc(at(13, 8), at(7, 8), 0) == Some(Arc::Back));
        assert!(WindowTrait::arc(at(13, 8), at(7, 8), 3) == Some(Arc::Front));
        // (7, 10) → (7, 8) passes the tie at (6, 9), North-East of the target: front-side when
        // facing East, front when facing North-East; the other tile (7, 9) would be North-West
        assert!(WindowTrait::arc(at(7, 10), at(7, 8), 1) == Some(Arc::Front));
        assert!(WindowTrait::arc(at(7, 10), at(7, 8), 0) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(at(7, 10), at(7, 8), 2) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(at(7, 10), at(7, 8), 4) == Some(Arc::Back));
        // A wall on the line does not change the arc (the caller checks sight)
        // The edges: the same tile, outside, a line leaving the window
        assert!(WindowTrait::arc(at(7, 8), at(7, 8), 0).is_none());
        assert!(WindowTrait::arc(SIZE, at(7, 8), 0).is_none());
        assert!(WindowTrait::arc(at(7, 8), 250, 0).is_none());
        // A line leaving the window (no sight, so no hit): the arc of its first step from the
        // target, the column −1 at (−1, 1), North-East of (0, 0)
        assert!(WindowTrait::arc(at(0, 2), at(0, 0), 1) == Some(Arc::Front));
    }

    /// "On the front tile": only the neighbour in the facing's direction.
    #[test]
    #[available_gas(l2_gas: 1678005)] // ceil(1.05 × 1598100 measured)
    fn test_front() {
        let sources: [u8; 2] = [at(7, 7), at(7, 8)];
        for source in sources.span() {
            let source = *source;
            let mut facing: u8 = 0;
            while facing != 6 {
                let mut d: u8 = 0;
                while d != 6 {
                    let target = LayoutTrait::neighbor(
                        WIDTH, HEIGHT, source, d.try_into().unwrap(),
                    )
                        .unwrap();
                    assert!(WindowTrait::front(source, facing, target) == (d == facing));
                    d += 1;
                }
                facing += 1;
            }
            // Two tiles away in the facing's direction is not the front tile; nor the same tile
            assert!(!WindowTrait::front(source, 0, source - 2));
            assert!(!WindowTrait::front(source, 0, source));
        }
        // At the edge the front tile is outside the window: nothing is on it
        assert!(!WindowTrait::front(at(0, 8), 0, at(14, 7)));
        assert!(!WindowTrait::front(SIZE, 0, at(7, 8)));
    }

    /// §5.3 step 3: toward the moved-to tile, toward an adjacent target, toward the first step of
    /// the line; unchanged for the same tile and outside the window.
    #[test]
    #[available_gas(l2_gas: 410729)] // ceil(1.05 × 391170 measured)
    fn test_facing() {
        // Each neighbour gives its direction, from both row parities
        let froms: [u8; 2] = [at(7, 7), at(7, 8)];
        for from in froms.span() {
            let from = *from;
            let mut d: u8 = 0;
            while d != 6 {
                let to = LayoutTrait::neighbor(WIDTH, HEIGHT, from, d.try_into().unwrap())
                    .unwrap();
                assert!(WindowTrait::facing(from, to, (d + 3) % 6) == d);
                d += 1;
            }
        }
        // Straight West along the row
        assert!(WindowTrait::facing(at(7, 8), at(12, 8), 0) == 3);
        // Across a tie: (7, 8) → (7, 10), the first step is (6, 9), North-East
        assert!(WindowTrait::facing(at(7, 8), at(7, 10), 4) == 1);
        // The other way: (7, 10) → (7, 8), the first step is (6, 9), South-East of (7, 10)
        assert!(WindowTrait::facing(at(7, 10), at(7, 8), 4) == 5);
        // The same tile, outside: unchanged
        assert!(WindowTrait::facing(at(7, 8), at(7, 8), 4) == 4);
        assert!(WindowTrait::facing(at(7, 8), SIZE, 2) == 2);
        // A line leaving the window: the first step of the unbounded line, toward the column −1
        // ((0, 0) → (0, 2): the tie takes (−1, 1), North-East of (0, 0))
        assert!(WindowTrait::facing(at(0, 0), at(0, 2), 3) == 1);
        // Back: (0, 2) → (0, 0) takes (−1, 1), South-East of (0, 2)
        assert!(WindowTrait::facing(at(0, 2), at(0, 0), 3) == 5);
    }

    #[test]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    #[should_panic(expected: 'window: facing')]
    fn test_facing_invalid() {
        WindowTrait::facing(at(7, 8), at(8, 8), 6);
    }

    #[test]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    #[should_panic(expected: 'window: facing')]
    fn test_arc_facing_invalid() {
        let _ = WindowTrait::arc(at(8, 8), at(7, 8), 7);
    }

    // ---- Shapes ------------------------------------------------------------------------------

    /// Each shape against the oracle disc, at every tile of the window (corners and edges
    /// included): clipped to the window. Split in six for snforge's step limit.
    fn check_shapes(first: u8, last: u8) {
        let window = open();
        let mut centre: u8 = first;
        while centre != last {
            let one = Oracle::disc(centre, 1);
            let point = hexx::board::bits::Bits::pow(centre);
            assert!(window.shape(shape::SINGLE, centre) == point);
            assert!(window.shape(shape::DISC_1, centre) == one, "disc 1 {}", centre);
            assert!(window.shape(shape::RING_1, centre) == one - point, "ring {}", centre);
            assert!(window.shape(shape::DISC_2, centre) == Oracle::disc(centre, 2), "{}", centre);
            assert!(window.shape(shape::DISC_3, centre) == Oracle::disc(centre, 3), "{}", centre);
            centre += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 919413590)] // ceil(1.05 × 875631990 measured)
    fn test_shapes_every_centre_0() {
        check_shapes(0, 40);
    }

    #[test]
    #[available_gas(l2_gas: 920791494)] // ceil(1.05 × 876944280 measured)
    fn test_shapes_every_centre_1() {
        check_shapes(40, 80);
    }

    #[test]
    #[available_gas(l2_gas: 920856447)] // ceil(1.05 × 877006140 measured)
    fn test_shapes_every_centre_2() {
        check_shapes(80, 120);
    }

    #[test]
    #[available_gas(l2_gas: 920936982)] // ceil(1.05 × 877082840 measured)
    fn test_shapes_every_centre_3() {
        check_shapes(120, 160);
    }

    #[test]
    #[available_gas(l2_gas: 920940216)] // ceil(1.05 × 877085920 measured)
    fn test_shapes_every_centre_4() {
        check_shapes(160, 200);
    }

    #[test]
    #[available_gas(l2_gas: 919416677)] // ceil(1.05 × 875634930 measured)
    fn test_shapes_every_centre_5() {
        check_shapes(200, 240);
    }

    /// Counts in the open, at the corners and edges; walls skipped; the centre a wall.
    #[test]
    #[available_gas(l2_gas: 1463088)] // ceil(1.05 × 1393417 measured)
    fn test_shapes_edges() {
        let window = open();
        let count = |mask: felt252| WindowTrait::tiles(mask).len();
        assert!(count(window.shape(shape::SINGLE, at(7, 8))) == 1);
        assert!(count(window.shape(shape::RING_1, at(7, 8))) == 6);
        assert!(count(window.shape(shape::DISC_1, at(7, 8))) == 7);
        assert!(count(window.shape(shape::DISC_2, at(7, 8))) == 19);
        assert!(count(window.shape(shape::DISC_3, at(7, 8))) == 37);
        // The corner (0, 0): East and the row below are outside
        assert!(
            WindowTrait::tiles(window.shape(shape::DISC_1, at(0, 0))) == array![
                at(0, 0), at(1, 0), at(0, 1),
            ]
                .span(),
        );
        assert!(count(window.shape(shape::RING_1, at(14, 15))) == 2);
        assert!(count(window.shape(shape::DISC_1, at(14, 0))) == 4);
        assert!(count(window.shape(shape::DISC_1, at(0, 15))) == 4);
        assert!(count(window.shape(shape::DISC_3, at(0, 0))) == 12);
        assert!(count(window.shape(shape::DISC_1, at(0, 8))) == 4);
        // Walls hold no actor
        let walls = walled(array![at(8, 8), at(6, 9), at(7, 8)].span());
        assert!(
            WindowTrait::tiles(walls.shape(shape::DISC_1, at(7, 8))) == array![
                at(6, 7), at(7, 7), at(6, 8), at(7, 9),
            ]
                .span(),
        );
        assert!(walls.shape(shape::SINGLE, at(7, 8)) == 0);
        // A centre outside the window: nothing
        assert!(window.shape(shape::DISC_3, SIZE) == 0);
        assert!(window.shape(shape::SINGLE, 255) == 0);
    }

    #[test]
    #[available_gas(l2_gas: 18816)] // ceil(1.05 × 17920 measured)
    #[should_panic(expected: 'window: shape')]
    fn test_shape_invalid() {
        open().shape(6, at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 18816)] // ceil(1.05 × 17920 measured)
    #[should_panic(expected: 'window: shape')]
    fn test_shape_zero() {
        open().shape(0, at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 18606)] // ceil(1.05 × 17720 measured)
    #[should_panic(expected: 'window: open above 240')]
    fn test_window_bits_above() {
        WindowTrait::new(OPEN + 1);
    }

    /// `tiles` lists every set bit, ascending, across both limbs.
    #[test]
    #[available_gas(l2_gas: 2481803)] // ceil(1.05 × 2363621 measured)
    fn test_tiles() {
        assert!(WindowTrait::tiles(0).len() == 0);
        let tiles = WindowTrait::tiles(OPEN);
        assert!(tiles.len() == 240);
        let mut p: u32 = 0;
        while p != 240 {
            assert!((*tiles.at(p)).into() == p);
            p += 1;
        }
        let some = Bits::pow(0)
            + Bits::pow(63)
            + Bits::pow(64)
            + Bits::pow(127)
            + Bits::pow(128)
            + Bits::pow(200)
            + Bits::pow(239);
        assert!(WindowTrait::tiles(some) == array![0, 63, 64, 127, 128, 200, 239].span());
    }

    // ---- Cost: one call is the difference between a test making it twice and once (hexx's
    // benchmarks), each on the worst case the rules reach: a hit at range 6 over a tie axis, a
    // target on the window's ring, a bomb's `DISC_1` away from the edges. Kept with the module's
    // tests: they need nothing deployed.

    /// A window with a few walls away from the lines measured, opaque to the compiler: a constant
    /// input would be folded at compile time (`hexx`'s benchmarks, `Inputs::get`).
    #[inline(never)]
    fn bench() -> Window {
        walled(array![at(1, 1), at(13, 14), at(2, 12)].span())
    }

    /// A value the compiler cannot fold.
    #[inline(never)]
    fn opaque(value: u8) -> u8 {
        value
    }

    #[test]
    #[available_gas(l2_gas: 50974)] // ceil(1.05 × 48546 measured)
    fn test_cost_sight_once() {
        let window = bench();
        assert!(window.sight(opaque(at(7, 2)), opaque(at(7, 8))));
    }

    #[test]
    #[available_gas(l2_gas: 71686)] // ceil(1.05 × 68272 measured)
    fn test_cost_sight_twice() {
        let window = bench();
        assert!(window.sight(opaque(at(7, 2)), opaque(at(7, 8))));
        assert!(window.sight(opaque(at(7, 8)), opaque(at(7, 2))));
    }

    #[test]
    #[available_gas(l2_gas: 64456)] // ceil(1.05 × 61386 measured)
    fn test_cost_reach_once() {
        let window = bench();
        assert!(window.reach(opaque(at(7, 2)), opaque(at(7, 8)), opaque(range::RANGED)));
    }

    #[test]
    #[available_gas(l2_gas: 98241)] // ceil(1.05 × 93562 measured)
    fn test_cost_reach_twice() {
        let window = bench();
        assert!(window.reach(opaque(at(7, 2)), opaque(at(7, 8)), opaque(range::RANGED)));
        assert!(window.reach(opaque(at(7, 8)), opaque(at(7, 2)), opaque(range::RANGED)));
    }

    #[test]
    #[available_gas(l2_gas: 41874)] // ceil(1.05 × 39880 measured)
    fn test_cost_arc_melee_once() {
        assert!(WindowTrait::arc(opaque(at(8, 8)), opaque(at(7, 8)), opaque(0)) == Some(Arc::Back));
    }

    #[test]
    #[available_gas(l2_gas: 68271)] // ceil(1.05 × 65020 measured)
    fn test_cost_arc_melee_twice() {
        assert!(WindowTrait::arc(opaque(at(8, 8)), opaque(at(7, 8)), opaque(0)) == Some(Arc::Back));
        assert!(
            WindowTrait::arc(opaque(at(7, 8)), opaque(at(8, 8)), opaque(0)) == Some(Arc::Front),
        );
    }

    #[test]
    #[available_gas(l2_gas: 41874)] // ceil(1.05 × 39880 measured)
    fn test_cost_arc_ranged_once() {
        let arc = WindowTrait::arc(opaque(at(7, 2)), opaque(at(7, 8)), opaque(0));
        assert!(arc == Some(Arc::FrontSide));
    }

    #[test]
    #[available_gas(l2_gas: 68376)] // ceil(1.05 × 65120 measured)
    fn test_cost_arc_ranged_twice() {
        let arc = WindowTrait::arc(opaque(at(7, 2)), opaque(at(7, 8)), opaque(0));
        assert!(arc == Some(Arc::FrontSide));
        let arc = WindowTrait::arc(opaque(at(7, 8)), opaque(at(7, 2)), opaque(0));
        assert!(arc == Some(Arc::FrontSide));
    }

    /// A target on the window's ring: its neighbours one direction at a time (`hexx`'s
    /// `edge_neighbors`).
    #[test]
    #[available_gas(l2_gas: 41874)] // ceil(1.05 × 39880 measured)
    fn test_cost_arc_ring_once() {
        let arc = WindowTrait::arc(opaque(at(7, 9)), opaque(at(7, 15)), opaque(0));
        assert!(arc == Some(Arc::FrontSide));
    }

    #[test]
    #[available_gas(l2_gas: 68376)] // ceil(1.05 × 65120 measured)
    fn test_cost_arc_ring_twice() {
        let arc = WindowTrait::arc(opaque(at(7, 9)), opaque(at(7, 15)), opaque(0));
        assert!(arc == Some(Arc::FrontSide));
        let arc = WindowTrait::arc(opaque(at(7, 9)), opaque(at(7, 15)), opaque(3));
        assert!(arc == Some(Arc::RearSide));
    }

    #[test]
    #[available_gas(l2_gas: 27815)] // ceil(1.05 × 26490 measured)
    fn test_cost_front_once() {
        assert!(WindowTrait::front(opaque(at(7, 8)), opaque(1), opaque(at(6, 9))));
    }

    #[test]
    #[available_gas(l2_gas: 40257)] // ceil(1.05 × 38340 measured)
    fn test_cost_front_twice() {
        assert!(WindowTrait::front(opaque(at(7, 8)), opaque(1), opaque(at(6, 9))));
        assert!(WindowTrait::front(opaque(at(6, 9)), opaque(4), opaque(at(7, 8))));
    }

    #[test]
    #[available_gas(l2_gas: 38997)] // ceil(1.05 × 37140 measured)
    fn test_cost_facing_melee_once() {
        assert!(WindowTrait::facing(opaque(at(7, 8)), opaque(at(6, 9)), opaque(0)) == 1);
    }

    #[test]
    #[available_gas(l2_gas: 62622)] // ceil(1.05 × 59640 measured)
    fn test_cost_facing_melee_twice() {
        assert!(WindowTrait::facing(opaque(at(7, 8)), opaque(at(6, 9)), opaque(0)) == 1);
        assert!(WindowTrait::facing(opaque(at(6, 9)), opaque(at(7, 8)), opaque(0)) == 4);
    }

    #[test]
    #[available_gas(l2_gas: 38997)] // ceil(1.05 × 37140 measured)
    fn test_cost_facing_ranged_once() {
        assert!(WindowTrait::facing(opaque(at(7, 2)), opaque(at(7, 8)), opaque(0)) == 1);
    }

    #[test]
    #[available_gas(l2_gas: 62622)] // ceil(1.05 × 59640 measured)
    fn test_cost_facing_ranged_twice() {
        assert!(WindowTrait::facing(opaque(at(7, 2)), opaque(at(7, 8)), opaque(0)) == 1);
        assert!(WindowTrait::facing(opaque(at(7, 8)), opaque(at(7, 2)), opaque(0)) == 5);
    }

    /// The fallback of a line that leaves the window: the unbounded line.
    #[test]
    #[available_gas(l2_gas: 38997)] // ceil(1.05 × 37140 measured)
    fn test_cost_facing_outside_once() {
        assert!(WindowTrait::facing(opaque(at(0, 0)), opaque(at(0, 2)), opaque(3)) == 1);
    }

    #[test]
    #[available_gas(l2_gas: 62622)] // ceil(1.05 × 59640 measured)
    fn test_cost_facing_outside_twice() {
        assert!(WindowTrait::facing(opaque(at(0, 0)), opaque(at(0, 2)), opaque(3)) == 1);
        assert!(WindowTrait::facing(opaque(at(0, 2)), opaque(at(0, 0)), opaque(3)) == 5);
    }

    #[test]
    #[available_gas(l2_gas: 46154)] // ceil(1.05 × 43956 measured)
    fn test_cost_shape_disc_1_once() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(7, 8))) != 0);
    }

    #[test]
    #[available_gas(l2_gas: 61543)] // ceil(1.05 × 58612 measured)
    fn test_cost_shape_disc_1_twice() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(7, 8))) != 0);
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(7, 7))) != 0);
    }

    /// A bomb's `DISC_1` on the window's ring: the rows of `disc`.
    #[test]
    #[available_gas(l2_gas: 90160)] // ceil(1.05 × 85866 measured)
    fn test_cost_shape_disc_1_ring_once() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(7, 15))) != 0);
    }

    #[test]
    #[available_gas(l2_gas: 163582)] // ceil(1.05 × 155792 measured)
    fn test_cost_shape_disc_1_ring_twice() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(7, 15))) != 0);
        assert!(window.shape(opaque(shape::DISC_1), opaque(at(0, 7))) != 0);
    }

    #[test]
    #[available_gas(l2_gas: 174727)] // ceil(1.05 × 166406 measured)
    fn test_cost_shape_disc_3_once() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_3), opaque(at(7, 8))) != 0);
    }

    #[test]
    #[available_gas(l2_gas: 318688)] // ceil(1.05 × 303512 measured)
    fn test_cost_shape_disc_3_twice() {
        let window = bench();
        assert!(window.shape(opaque(shape::DISC_3), opaque(at(7, 8))) != 0);
        assert!(window.shape(opaque(shape::DISC_3), opaque(at(7, 7))) != 0);
    }

    /// The seven tiles of a `DISC_1`, listed.
    #[test]
    #[available_gas(l2_gas: 105942)] // ceil(1.05 × 100897 measured)
    fn test_cost_tiles_7_once() {
        let disc = bench().shape(opaque(shape::DISC_1), opaque(at(7, 8)));
        assert!(WindowTrait::tiles(disc).len() == 7);
    }

    #[test]
    #[available_gas(l2_gas: 165951)] // ceil(1.05 × 158048 measured)
    fn test_cost_tiles_7_twice() {
        let disc = bench().shape(opaque(shape::DISC_1), opaque(at(7, 8)));
        assert!(WindowTrait::tiles(disc).len() == 7);
        assert!(WindowTrait::tiles(disc).len() == 7);
    }

    // ---- The vector table for the TypeScript mirror (D-140, SPK-4) ---------------------------

    /// The window of the vectors: walls on both sides of the centre and on a tie's tile.
    fn fixture() -> Window {
        walled(
            array![at(9, 8), at(6, 9), at(5, 6), at(8, 11), at(10, 5), at(4, 10), at(11, 9)].span(),
        )
    }

    fn hex(felts: Span<felt252>) -> ByteArray {
        let mut out: ByteArray = "[";
        let mut first = true;
        for felt in felts {
            if !first {
                out.append(@",");
            }
            first = false;
            let wide: u256 = (*felt).into();
            out.append(@format!("\"0x{:x}\"", wide));
        }
        out.append(@"]");
        out
    }

    /// Prints one vector and adds it to the digest.
    fn emit(
        ref digest: Array<felt252>, ref id: u32, name: ByteArray, case: Span<felt252>,
        ok: Span<felt252>,
    ) {
        println!("{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}", id, name, hex(case), hex(ok));
        digest.append(core::poseidon::poseidon_hash_span(case));
        digest.append(core::poseidon::poseidon_hash_span(ok));
        id += 1;
    }

    // AC-4: the vector table, printed one JSON line per case (`{"id", "fn", "case", "ok"}`), and
    // a digest of every case and outcome: a change to a rule or to the cases fails here until
    // `contracts/logic/vectors/window.jsonl` is regenerated (`vectors/README.md`).
    #[test]
    #[available_gas(l2_gas: 1236927329)] // ceil(1.05 × 1178026027 measured)
    fn test_vectors() {
        let window = fixture();
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        // `sight` and `reach` (range 6): from both row parities to every tile within 7, and the
        // edges (outside, a line leaving the window, the same tile)
        let mut pairs: Array<(u8, u8)> = array![];
        let froms: [u8; 2] = [at(7, 8), at(7, 7)];
        for from in froms.span() {
            let mut to: u8 = 0;
            while to != SIZE {
                if WindowTrait::distance(*from, to) <= 7 {
                    pairs.append((*from, to));
                }
                to += 1;
            }
        }
        pairs.append((at(0, 0), at(0, 2)));
        pairs.append((at(0, 2), at(0, 0)));
        pairs.append((at(14, 15), at(14, 13)));
        pairs.append((SIZE, at(7, 8)));
        pairs.append((at(7, 8), 255));
        for (from, to) in pairs.span() {
            let (from, to) = (*from, *to);
            let case = array![window.open, from.into(), to.into()];
            let ok = array![window.sight(from, to).into()];
            emit(ref digest, ref id, "sight", case.span(), ok.span());
            let case = array![window.open, from.into(), to.into(), range::RANGED.into()];
            let ok = array![window.reach(from, to, range::RANGED).into()];
            emit(ref digest, ref id, "reach", case.span(), ok.span());
        }
        // `arc` and `facing`: every source within 6 of the target (7, 8), the facing turning with
        // the source; the edges
        let mut triples: Array<(u8, u8, u8)> = array![];
        let mut k: u8 = 0;
        let mut source: u8 = 0;
        while source != SIZE {
            if WindowTrait::distance(source, at(7, 8)) <= 6 {
                triples.append((source, at(7, 8), k % 6));
                k += 1;
            }
            source += 1;
        }
        triples.append((at(0, 2), at(0, 0), 0));
        triples.append((at(0, 0), at(0, 2), 3));
        triples.append((SIZE, at(7, 8), 1));
        triples.append((at(7, 8), at(7, 15), 2));
        for (source, target, facing) in triples.span() {
            let (source, target, facing) = (*source, *target, *facing);
            let case = array![source.into(), target.into(), facing.into()];
            let mut ok: Array<felt252> = array![];
            WindowTrait::arc(source, target, facing).serialize(ref ok);
            emit(ref digest, ref id, "arc", case.span(), ok.span());
            let ok = array![WindowTrait::facing(source, target, facing).into()];
            emit(ref digest, ref id, "facing", case.span(), ok.span());
        }
        // `front`: every neighbour and facing, at the centre and on the edge
        let sources: [u8; 2] = [at(7, 8), at(0, 7)];
        for source in sources.span() {
            let mut facing: u8 = 0;
            while facing != 6 {
                let mut d: u8 = 0;
                while d != 6 {
                    let target = match LayoutTrait::neighbor(
                        WIDTH, HEIGHT, *source, d.try_into().unwrap(),
                    ) {
                        Some(target) => target,
                        None => *source - 1,
                    };
                    let case = array![(*source).into(), facing.into(), target.into()];
                    let ok = array![WindowTrait::front(*source, facing, target).into()];
                    emit(ref digest, ref id, "front", case.span(), ok.span());
                    d += 1;
                }
                facing += 1;
            }
        }
        // `shape`: each shape at the corners, the edges, the centre and next to walls
        let centres: [u8; 11] = [
            at(0, 0), at(14, 0), at(0, 15), at(14, 15), at(0, 8), at(14, 7), at(7, 0), at(7, 15),
            at(7, 8), at(8, 8), at(1, 1),
        ];
        let mut id_shape: u8 = shape::SINGLE;
        while id_shape <= shape::DISC_3 {
            for centre in centres.span() {
                let case = array![window.open, id_shape.into(), (*centre).into()];
                let ok = array![window.shape(id_shape, *centre)];
                emit(ref digest, ref id, "shape", case.span(), ok.span());
            }
            id_shape += 1;
        }
        let digest = core::poseidon::poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST, 'vectors moved: regenerate');
    }

    const DIGEST: felt252 =
        1283461057461396595697948945270057094381193406987776564841180296965294379408;
}
