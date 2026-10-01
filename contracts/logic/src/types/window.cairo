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
//!   an oracle written from design/04's sentence alone (`Oracle::line`).
//! - `reach`: within a range of design/04's table (`range`) and in sight. Adjacent tiles have no
//!   tile between them: touch is never blocked.
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
//!   lower index may be the column `−1`): no sight, as a wall (`hexx` D-27); no arc. Sight has
//!   radius 6 around the adventurer and the window's ring is 7 tiles away (design/02): a line
//!   between two tiles within 6 of the adventurer never leaves the window. The facing takes the
//!   first step of the unbounded line (`HexTrait::line_to`), which needs no board;
//! - a wall at an end of the line: not tested (an actor never stands on a wall).
//! A facing above 5 or a shape id outside 1–5 is a stored value the pipeline refuses: asserted.
//!
//! **Cost** (ENG-01 §9.2, this lot's row): measured by `tests::test_cost_*`, each call alone
//! between two reads of `get_available_gas` (GAS.md has the totals).

use core::num::traits::Zero;
use hexx::board::bits::Bits;
use hexx::board::direction::{Arc as BoardArc, Direction, DirectionTrait};
use hexx::board::geometry::GeometryTrait;
use hexx::board::layout::LayoutTrait;
use hexx::board::line::LineTrait;
use hexx::board::map::HexMap;
use hexx::hex::{HexImpl, HexTrait};
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
/// 15, as a divisor.
const FIFTEEN: NonZero<u8> = 15;

/// The board of a tick: bit `p` of `open` is 1 when the tile `p` is walkable, 0 for a wall (an
/// unrevealed or void chunk is wall, design/02). Bits 240 and up are 0.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Window {
    pub open: felt252,
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
    #[inline(always)]
    fn distance(from: u8, to: u8) -> u8 {
        GeometryTrait::distance(WIDTH, from, to)
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
        if Self::distance(from, to) > range {
            return false;
        }
        WindowInternal::map(*self.open).line_of_sight(from, to)
    }

    /// The arc of the target's facing a hit from `source` arrives from (§5.5 step 1): the source's
    /// tile when adjacent, else the tile the line of sight arrives from. `None` for the same tile,
    /// a position outside the window, or a line that leaves it. Walls are not read: the caller
    /// checked `reach` first.
    fn arc(source: u8, target: u8, facing: u8) -> Option<Arc> {
        let facing = WindowAssert::facing(facing);
        if !(Self::inside(source) && Self::inside(target)) || source == target {
            return None;
        }
        let direction = if Self::distance(source, target) == 1 {
            LayoutTrait::neighbor_direction(WIDTH, HEIGHT, target, source)?
        } else {
            WindowInternal::map(0).approach(source, target)?
        };
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
        if Self::distance(from, to) == 1 {
            return LayoutTrait::neighbor_direction(WIDTH, HEIGHT, from, to).unwrap().into();
        }
        // [Compute] The line is symmetric: the tile before `from` on the line from `to` is the
        // first step from `from`
        if let Some(direction) = WindowInternal::map(0).approach(to, from) {
            return direction.into();
        }
        // [Compute] The line leaves the window: its first step, on the unbounded line
        let start = GeometryTrait::index_to_hex(WIDTH, from);
        let line = start.line_to(GeometryTrait::index_to_hex(WIDTH, to));
        let step = (*line.at(1)).const_sub(start);
        let mut index: u8 = 0;
        for neighbor in HexImpl::NEIGHBORS_COORDS.span() {
            if *neighbor == step {
                break;
            }
            index += 1;
        }
        index
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
            WindowInternal::disc(centre, 1) - Bits::pow(centre)
        } else if shape == shape::DISC_1 {
            WindowInternal::disc(centre, 1)
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

    /// The tiles within `radius` of `centre` (hex distance), clipped to the window: one row segment
    /// per row `y + dr`. With `q = x − ⌊y/2⌋` (`GeometryTrait::to_axial`), the tiles of the row at
    /// distance at most `R` have `dq` in `[max(−R, −R − dr), min(R, R − dr)]`, that is the columns
    /// `x + dq + ⌊y'/2⌋ − ⌊y/2⌋`. At most 7 rows.
    fn disc(centre: u8, radius: u8) -> felt252 {
        let (y, x) = DivRem::div_rem(centre, FIFTEEN);
        let (half, _) = DivRem::div_rem(y, TWO);
        let (x, y, half, radius): (i16, i16, i16, i16) = (
            x.into(), y.into(), half.into(), radius.into(),
        );
        let mut tiles: felt252 = 0;
        let mut dr = -radius;
        while dr <= radius {
            let row = y + dr;
            if row >= 0 && row < HEIGHT.into() {
                let shift = x + row / 2 - half;
                let low = if dr < 0 {
                    -radius - dr
                } else {
                    -radius
                };
                let high = if dr > 0 {
                    radius - dr
                } else {
                    radius
                };
                let (first, last) = (shift + low, shift + high);
                let first = if first < 0 {
                    0
                } else {
                    first
                };
                let last = if last >= WIDTH.into() {
                    WIDTH.into() - 1
                } else {
                    last
                };
                if first <= last {
                    let base: u8 = (row * WIDTH.into()).try_into().unwrap();
                    let (first, last): (u8, u8) = (
                        first.try_into().unwrap(), last.try_into().unwrap(),
                    );
                    tiles += Bits::pow(base + last + 1) - Bits::pow(base + first);
                }
            }
            dr += 1;
        }
        tiles
    }

    /// Appends the positions of one limb, ascending: the lowest set bit, found by halving the
    /// range it lies in (7 comparisons), then cleared.
    fn limb(ref tiles: Array<u8>, value: u128, offset: u8) {
        let mut rest = value;
        while rest.is_non_zero() {
            let cleared = rest & (rest - 1);
            let mut bit = rest - cleared;
            let mut position = offset;
            if bit >= 0x10000000000000000 {
                bit /= 0x10000000000000000;
                position += 64;
            }
            if bit >= 0x100000000 {
                bit /= 0x100000000;
                position += 32;
            }
            if bit >= 0x10000 {
                bit /= 0x10000;
                position += 16;
            }
            if bit >= 0x100 {
                bit /= 0x100;
                position += 8;
            }
            if bit >= 0x10 {
                bit /= 0x10;
                position += 4;
            }
            if bit >= 0x4 {
                bit /= 0x4;
                position += 2;
            }
            if bit >= 0x2 {
                position += 1;
            }
            tiles.append(position);
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
                        assert!(WindowTrait::arc(from, to, 0).is_none(), "arc out {} {}", from, to);
                    },
                }
            }
            to += 1;
        }
    }

    // ---- Line of sight -----------------------------------------------------------------------

    /// AC-2: `hexx`'s line is design/04's, ties included, from both row parities at the centre.
    #[test]
    #[available_gas(l2_gas: 1000000000)]
    fn test_line_against_oracle_centre() {
        check_from(at(7, 7));
        check_from(at(7, 8));
    }

    /// The same at the window's corners and edges, where a line can leave it.
    #[test]
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 1000000000)]
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
        assert!(!open().reach(at(7, 8), SIZE, range::EARSHOT));
        assert!(open().reach(at(0, 0), at(8, 0), range::EARSHOT));
        assert!(!open().reach(at(0, 0), at(9, 0), range::EARSHOT));
        assert!(range::NEARBY == 2 && range::AREA == 3 && range::ALERT == 5);
    }

    // ---- Arcs, front, facing -----------------------------------------------------------------

    /// AC-2: each arc, for a source on each of the six neighbours and each of the six facings, on
    /// both row parities.
    #[test]
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 1000000000)]
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
        assert!(WindowTrait::arc(at(0, 2), at(0, 0), 0).is_none());
    }

    /// "On the front tile": only the neighbour in the facing's direction.
    #[test]
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 100000)]
    #[should_panic(expected: 'window: facing')]
    fn test_facing_invalid() {
        WindowTrait::facing(at(7, 8), at(8, 8), 6);
    }

    #[test]
    #[available_gas(l2_gas: 100000)]
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
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_0() {
        check_shapes(0, 40);
    }

    #[test]
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_1() {
        check_shapes(40, 80);
    }

    #[test]
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_2() {
        check_shapes(80, 120);
    }

    #[test]
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_3() {
        check_shapes(120, 160);
    }

    #[test]
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_4() {
        check_shapes(160, 200);
    }

    #[test]
    #[available_gas(l2_gas: 4000000000)]
    fn test_shapes_every_centre_5() {
        check_shapes(200, 240);
    }

    /// Counts in the open, at the corners and edges; walls skipped; the centre a wall.
    #[test]
    #[available_gas(l2_gas: 1000000000)]
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
    #[available_gas(l2_gas: 100000)]
    #[should_panic(expected: 'window: shape')]
    fn test_shape_invalid() {
        open().shape(6, at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 100000)]
    #[should_panic(expected: 'window: shape')]
    fn test_shape_zero() {
        open().shape(0, at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 100000)]
    #[should_panic(expected: 'window: open above 240')]
    fn test_window_bits_above() {
        WindowTrait::new(OPEN + 1);
    }

    /// `tiles` lists every set bit, ascending, across both limbs.
    #[test]
    #[available_gas(l2_gas: 100000000)]
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
}
