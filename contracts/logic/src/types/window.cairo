//! The game's geometry on the window (ENG-02, D-173): the board of a tick (design/02, 15 columns ×
//! 16 rows, assembled at each tick by ENG-07, never stored), and what the rules ask of it, on
//! `hexx` 0.1.0-rc.1. A value type with its behaviour, as `World`: it sits in `types/` (CAIRO.md
//! §7, D-147). This trait is frozen: the executor (CBT-05a) consumes it.
//!
//! **Positions.** A tile of the window is its position `15 y + x` (`hexx`'s layout: pointy-top,
//! odd-r offset, `+1` is West, `+15` is North; `x` below 15, `y` below 16), the window's own index,
//! 0 to 239. A facing is a direction `0..=5`: East, North-East, North-West, West, South-West,
//! South-East (`actions`, the map library's order, `hexx::board::direction::Direction`'s indices).
//!
//! **The rules** (design/04 *Ranges*, *Line of sight*, *Facing and arcs*; design/19 §2.3, §5.3
//! step 3, §5.5 step 1, §5.6):
//! - `sight`: a fixed integer hex line between the two tiles; walls block, actors do not (an actor
//!   is not in the window's walls), a wall at either end included (D-174, with the edges below,
//!   written into design/19 §6). When the line
//!   passes exactly between two tiles, the lower tile index is taken. `hexx`'s line (N-5) has this
//!   rule: element `i` of the line is the tile nearest `A + (i / N)(B − A)`, at a tie the smaller
//!   row, and on the same row the smaller column (`LineTrait::line`, `HexTrait::line_to`); the
//!   tests hold it against an oracle written from design/04's sentence alone (`Oracle::line`). The
//!   arc and the facing read only the line's first step, computed in constant time by the same
//!   rule (`WindowInternal::step`), held against the same oracle.
//! - `reach`: the target of an action within its range (design/04's table, `range`: touch 1,
//!   ranged 6) and in sight, at every range: design/04 requires sight for ranged 6, and adjacent
//!   tiles have no tile between them, so for touch it only refuses a wall at an end. No MVP target
//!   has a range of 2 to 5; such a range would need sight too. A radius that needs no sight
//!   (alert, earshot) is a `distance`.
//! - `arc`: the arc of the target's facing in which the hit arrives: the source's tile when
//!   adjacent, at range the tile the line of sight arrives from (the tile of the line next to the
//!   target), in `d` front, `d ± 1` front-side, `d ± 2` rear-side, `d + 3` back.
//! - `front`: whether the target stands on the source's front tile (Blind's miss, §5.6).
//! - `facing`: the facing an action turns to (§5.3 step 3): toward the moved-to tile or the
//!   target; for a target not adjacent, the direction of the first step of the hex line.
//! - The arguments come in one order: the acting tile, then the other tile, then a facing
//!   (`arc(source, target, facing)`, `front(source, target, facing)`, `facing(from, to, facing)`).
//! - `shape`: a shape's tiles from a centre (§2.3: `SINGLE`, `RING_1`, `DISC_1`, `DISC_2`,
//!   `DISC_3`, by hex distance), as a bitmap of the window: bit `p` is the tile `p`, so its order
//!   is ascending tile index, the order of the executor's actor list (§5.14 step 4). A tile
//!   outside the window is skipped; a wall holds no actor and is skipped. `tiles` lists a bitmap's
//!   positions in that order.
//!
//! **Edges (D-140).** A rule never panics on a legal action:
//! - a position outside the window (240 and up): no sight, no reach, no arc, not in front, the
//!   facing unchanged, an empty shape, the distance `FAR` (255, above every range);
//! - the same tile: in sight unless it is a wall (no tile between), no arc (a hit never comes from
//!   the target's own tile: two actors never share one), not in front, the facing unchanged, a
//!   shape as any other;
//! - a line that leaves the window between two of its tiles (at a tie on a row of the edge, the
//!   lower index may be the column `−1`): no sight, as a wall (`hexx` D-27). Sight has radius 6
//!   around the adventurer and the window's ring is 7 tiles away (design/02): a line between two
//!   tiles within 6 of the adventurer never leaves the window. The arc and the facing need only
//!   the line's first step, a direction, which needs no board: they are defined there too;
//! - a wall at either end of the line: no sight (an actor never stands on a wall; a tile target can
//!   be one).
//! A facing above 5 or a shape id outside 1–5 is a stored value the pipeline refuses: asserted.
//! A window holds no bit at or above 240: its field is private, made through `WindowTrait::new`
//! (asserted) or `Serde` (refused).
//!
//! **`u256`** is used only to split a bitmap of the window into its two limbs (written reason, as
//! `packing`'s: a `felt252` has no bitwise operation, and the `felt252 → u256` conversion is the
//! split and its range proof; `hexx`'s `Bits` takes the limbs): in `sight`, `shape`, `tiles` and
//! `WindowAssert::assert_valid_open`. No `u256` arithmetic.
//!
//! **Cost** (ENG-01 §9.2, this lot's row): one call is the difference between the snforge totals
//! of `tests::test_cost_*_twice` and `_once` (its inputs opaque to the compiler; each figure holds
//! 2,440 of the benchmark's own, three opaque inputs and the check, `test_cost_overhead_*`).
//! `sight` 22,176 (`hexx`'s table path, any pair within 6, both ends tested); `reach` 34,216;
//! `distance` 16,230; `arc` 25,140 adjacent, 25,240 at range or on the window's ring (the line's
//! first step in constant time); `front` 11,850; `facing` 22,500
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
/// The distance of a position outside the window: above every range (design/04's widest is 8).
pub const FAR: u8 = 255;

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
/// unrevealed or void chunk is wall, design/02). Bits 240 and up are 0: the field is private, so a
/// window is made only through `WindowTrait::new`, which checks it, or deserialized through the
/// same check (`WindowSerde`); `WindowTrait::open` reads it.
#[derive(Copy, Drop, PartialEq, Debug)]
pub struct Window {
    open: felt252,
}

/// One felt, `open`; deserializing refuses (`None`) a bitmap with a bit at or above 240, as `new`
/// asserts.
pub impl WindowSerde of Serde<Window> {
    fn serialize(self: @Window, ref output: Array<felt252>) {
        output.append(*self.open);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Window> {
        let open = *serialized.pop_front()?;
        // `u256`: the split of the felt is its range proof (module documentation)
        let wide: u256 = open.into();
        if wide.high < HIGH_LIMIT {
            Some(Window { open })
        } else {
            None
        }
    }
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

    /// The window's walkable bitmap.
    #[inline(always)]
    fn open(self: @Window) -> felt252 {
        *self.open
    }

    /// The hex distance between two tiles of the window (walls ignored); `FAR` (255, above every
    /// range) when either is outside the window, so that no range holds it.
    fn distance(from: u8, to: u8) -> u8 {
        if !(Self::inside(from) && Self::inside(to)) {
            return FAR;
        }
        WindowInternal::length(WindowInternal::delta(from, to))
    }

    /// Whether `from` sees `to`: both ends and every tile strictly between them on the line are
    /// walkable, at a tie the lower tile index (design/04). False when either is outside the window
    /// or the line leaves it.
    fn sight(self: @Window, from: u8, to: u8) -> bool {
        if !(Self::inside(from) && Self::inside(to)) {
            return false;
        }
        WindowInternal::seen(*self.open, from, to)
    }

    /// Whether `to` is within `range` of `from` and in its sight. Sight is checked at every range:
    /// design/04 requires it for ranged 6; at touch, 1, no tile lies between the two, so it refuses
    /// only a wall at an end; no MVP target has a range of 2 to 5, and one would need sight too.
    fn reach(self: @Window, from: u8, to: u8, range: u8) -> bool {
        if !(Self::inside(from) && Self::inside(to)) {
            return false;
        }
        if WindowInternal::length(WindowInternal::delta(from, to)) > range {
            return false;
        }
        WindowInternal::seen(*self.open, from, to)
    }

    /// The arc of the target's facing a hit from `source` arrives from (§5.5 step 1): the source's
    /// tile when adjacent, else the tile the line of sight arrives from, that is the first step of
    /// the line from the target (the line is symmetric). `None` for the same tile or a position
    /// outside the window. Walls are not read: the caller checked `reach` first.
    fn arc(source: u8, target: u8, facing: u8) -> Option<Arc> {
        let facing = WindowAssert::direction(facing);
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
    fn front(source: u8, target: u8, facing: u8) -> bool {
        let facing = WindowAssert::direction(facing);
        if !(Self::inside(source) && Self::inside(target)) {
            return false;
        }
        LayoutTrait::neighbor(WIDTH, HEIGHT, source, facing) == Some(target)
    }

    /// The facing of an actor on `from` after an action toward `to` (§5.3 step 3): the direction
    /// of `to` when adjacent, else of the first step of the hex line; `facing` unchanged for the
    /// same tile or a position outside the window.
    fn facing(from: u8, to: u8, facing: u8) -> u8 {
        WindowAssert::direction(facing);
        if !(Self::inside(from) && Self::inside(to)) || from == to {
            return facing;
        }
        WindowInternal::step(WindowInternal::delta(from, to)).into()
    }

    /// The tiles of a shape (`effect::shape`) centred on `centre`, clipped to the window and to its
    /// walls: bit `p` for the tile `p`, ascending tile index. Empty for a centre outside the
    /// window.
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
        // `u256`: the two limbs of the bitmaps for the bitwise builtin (module documentation)
        let tiles: u256 = tiles.into();
        Bits::to_felt(Bits::and(tiles, (*self.open).into()))
    }

    /// `shape` for the shapes the MVP's content uses (CBT-05a, option (2) of the project manager,
    /// 2026-10-02): `SINGLE`, `RING_1`, `DISC_1`, by the same rule. `DISC_2` and `DISC_3` have no
    /// MVP content (FX-21; the validators refuse them since CBT-01): an empty set here, so that the
    /// executor's class does not hold `disc`. The executor's one shape call.
    fn near(self: @Window, shape: u8, centre: u8) -> felt252 {
        if !Self::inside(centre) {
            return 0;
        }
        let tiles = if shape == shape::SINGLE {
            Bits::pow(centre)
        } else if shape == shape::RING_1 {
            WindowInternal::neighbours(centre, 0)
        } else if shape == shape::DISC_1 {
            WindowInternal::neighbours(centre, 1)
        } else {
            return 0;
        };
        // `u256`: the two limbs of the bitmaps for the bitwise builtin (module documentation)
        let tiles: u256 = tiles.into();
        Bits::to_felt(Bits::and(tiles, (*self.open).into()))
    }

    /// The positions of a bitmap of the window, ascending.
    fn tiles(mask: felt252) -> Span<u8> {
        // `u256`: the two limbs of the bitmap, each walked on its own (module documentation)
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

    /// Whether the line `from`–`to` (`hexx`'s `LineTrait::line`, the tiles strictly between) and
    /// both its ends are walkable: `M & open == M` for `M` the line and the ends. `false` when the
    /// line leaves the window.
    #[inline(always)]
    fn seen(open: felt252, from: u8, to: u8) -> bool {
        match Self::map(open).line(from, to) {
            Some(between) => {
                let ends = if from == to {
                    Bits::pow(from)
                } else {
                    Bits::pow(from) + Bits::pow(to)
                };
                // `u256`: the two limbs of the bitmaps for the bitwise builtin (module
                // documentation)
                let tiles: u256 = (between + ends).into();
                Bits::and(tiles, open.into()) == tiles
            },
            None => false,
        }
    }

    /// `(q + 7, r)` of a tile, `q = x − ⌊y/2⌋`, `r = y` (`GeometryTrait::to_axial`), shifted
    /// so that it is never negative: one division by 30 gives `⌊y/2⌋` and the column.
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
    /// 1–13, rows 1–14) one product, `2^c × (M + with_centre)`, `M` the field sum of the
    /// relative offsets of the centre's row parity (`hexx`'s `neighbor_mask` on the width 15, its
    /// constant written out); on the window's ring, the rows of `disc`.
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
    /// row segment per row `y' = y + dr`. With `q = x − ⌊y/2⌋` (`GeometryTrait::to_axial`),
    /// the tiles of the row at distance at most `R` have `dq` in `[max(−R, −R − dr), min(R, R
    /// − dr)]`, that is the columns `x + dq + ⌊y'/2⌋ − ⌊y/2⌋`. Computed on `u8` shifted
    /// by `R` and `2R`
    /// (no negative value): row `k = dr + R` in `0..=2R`, columns `+ 2R`. At most 7 rows.
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
        // `u256`: the split of the felt is its range proof (module documentation)
        let wide: u256 = open.into();
        assert(wide.high < HIGH_LIMIT, errors::OPEN);
    }

    /// A shape id of `effect::shape`.
    fn assert_valid_shape(shape: u8) {
        assert(shape >= shape::SINGLE && shape <= shape::LAST, errors::SHAPE);
    }

    /// The direction of a facing `0..=5`.
    #[inline(always)]
    fn direction(facing: u8) -> Direction {
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
    use super::{FAR, HEIGHT, SIZE, WIDTH, Window, WindowTrait, range};

    /// Every tile walkable: `2^240 − 1`.
    const OPEN: felt252 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// The helpers of the tests: positions, windows, the oracle checks, the benchmarks' inputs
    /// and the vector table's printing (scoped, CAIRO §7).
    #[generate_trait]
    impl Fixture of FixtureTrait {
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
                            assert!(
                                map.line(from, to) == Some(Self::mask(tiles)),
                                "line {} {}",
                                from,
                                to,
                            );
                            assert!(
                                map.line(to, from) == Some(Self::mask(tiles)),
                                "back {} {}",
                                from,
                                to,
                            );
                            let last = *tiles.at(tiles.len() - 1);
                            let first = *tiles.at(0);
                            let into = Oracle::direction(to, last);
                            let mut facing: u8 = 0;
                            while facing != 6 {
                                let arc = WindowTrait::arc(from, to, facing);
                                assert!(
                                    arc == Some(Oracle::arc(into, facing)), "arc {} {}", from, to,
                                );
                                facing += 1;
                            }
                            let turned = WindowTrait::facing(from, to, 0);
                            assert!(
                                turned == Oracle::direction(from, first), "facing {} {}", from, to,
                            );
                        },
                        None => {
                            assert!(map.line(from, to).is_none(), "out {} {}", from, to);
                            assert!(!Self::open().sight(from, to), "sight out {} {}", from, to);
                        },
                    }
                }
                to += 1;
            }
        }

        /// Each shape against the oracle disc, at every tile of the window (corners and edges
        /// included): clipped to the window. Split in six for snforge's step limit.
        fn check_shapes(first: u8, last: u8) {
            let window = Self::open();
            let mut centre: u8 = first;
            while centre != last {
                let one = Oracle::disc(centre, 1);
                let point = hexx::board::bits::Bits::pow(centre);
                assert!(window.shape(shape::SINGLE, centre) == point);
                assert!(window.shape(shape::DISC_1, centre) == one, "disc 1 {}", centre);
                assert!(window.shape(shape::RING_1, centre) == one - point, "ring {}", centre);
                assert!(
                    window.shape(shape::DISC_2, centre) == Oracle::disc(centre, 2), "{}", centre,
                );
                assert!(
                    window.shape(shape::DISC_3, centre) == Oracle::disc(centre, 3), "{}", centre,
                );
                centre += 1;
            }
        }

        /// A window with a few walls away from the lines measured, opaque to the compiler: a
        /// constant input would be folded at compile time (`hexx`'s benchmarks, `Inputs::get`).
        #[inline(never)]
        fn bench() -> Window {
            Self::walled(array![Self::at(1, 1), Self::at(13, 14), Self::at(2, 12)].span())
        }

        /// A value the compiler cannot fold.
        #[inline(never)]
        fn opaque(value: u8) -> u8 {
            value
        }

        /// The window of the vectors: walls on both sides of the centre and on a tie's tile.
        fn fixture() -> Window {
            Self::walled(
                array![
                    Self::at(9, 8), Self::at(6, 9), Self::at(5, 6), Self::at(8, 11),
                    Self::at(10, 5), Self::at(4, 10), Self::at(11, 9),
                ]
                    .span(),
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
            ref digest: Array<felt252>,
            ref id: u32,
            name: ByteArray,
            case: Span<felt252>,
            ok: Span<felt252>,
        ) {
            println!(
                "{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}",
                id,
                name,
                Self::hex(case),
                Self::hex(ok),
            );
            digest.append(core::poseidon::poseidon_hash_span(case));
            digest.append(core::poseidon::poseidon_hash_span(ok));
            id += 1;
        }
    }

    // ---- Oracles, written from the design's sentences ------------------------------------------

    #[generate_trait]
    impl Oracle of OracleTrait {
        /// `(q, r)` of a tile, `q = x − ⌊y/2⌋` (any integer column, `−1` and `15`
        /// included).
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
        /// `max(|Δq − Δr|, |Δr − Δs|, |Δs − Δq|) ≤ 1`); when the point lies exactly
        /// between two tiles, the lower tile index (the smaller row, then the smaller column).
        /// Returns the tiles strictly between the ends in order, `None` when a chosen tile is
        /// outside the window.
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
                // Candidates in ascending index: rows, then columns (`x = q + ⌊r/2⌋` grows with
                // q)
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
                tiles.append(Fixture::at(x, y));
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

    // ---- Line of sight -----------------------------------------------------------------------

    /// AC-2: `hexx`'s line is design/04's, ties included, from both row parities at the centre.
    #[test]
    // gas: raised, distance guards a position outside the window (fix loop 3)
    #[available_gas(l2_gas: 252301529)] // ceil(1.05 × 240287170 measured)
    fn test_line_against_oracle_centre() {
        Fixture::check_from(Fixture::at(7, 7));
        Fixture::check_from(Fixture::at(7, 8));
    }

    /// The same at the window's corners and edges, where a line can leave it.
    #[test]
    // gas: raised, sight tests both ends (fix loop 1); distance guards outside (fix loop 3)
    #[available_gas(l2_gas: 470943365)] // ceil(1.05 × 448517490 measured)
    fn test_line_against_oracle_edges() {
        Fixture::check_from(Fixture::at(0, 0));
        Fixture::check_from(Fixture::at(14, 15));
        Fixture::check_from(Fixture::at(0, 8));
        Fixture::check_from(Fixture::at(14, 7));
        Fixture::check_from(Fixture::at(7, 0));
        Fixture::check_from(Fixture::at(7, 15));
        Fixture::check_from(Fixture::at(1, 1));
        Fixture::check_from(Fixture::at(13, 14));
    }

    /// The tie cases of the line: a point exactly between two tiles takes the lower index.
    #[test]
    #[available_gas(l2_gas: 1261158)] // ceil(1.05 × 1201102 measured)
    fn test_line_ties() {
        let map = HexMap { width: WIDTH, height: HEIGHT, grid: OPEN, seed: 0 };
        // Two rows up, same column on an even row: between (7, 9) 142 and (6, 9) 141, 141
        assert!(
            map.line(Fixture::at(7, 8), Fixture::at(7, 10)) == Some(Bits::pow(Fixture::at(6, 9))),
        );
        // From an odd row: (7, 7) → (7, 9) passes between (8, 8) 128 and (7, 8) 127, 127
        assert!(
            map.line(Fixture::at(7, 7), Fixture::at(7, 9)) == Some(Bits::pow(Fixture::at(7, 8))),
        );
        // Δq = 2, Δr = −1, (7, 8) → (8, 7): between (8, 8) 128 and (7, 7) 112, the row below
        assert!(
            map.line(Fixture::at(7, 8), Fixture::at(8, 7)) == Some(Bits::pow(Fixture::at(7, 7))),
        );
        // The reverse direction takes the same tile (the rule does not depend on the order)
        assert!(
            map.line(Fixture::at(8, 7), Fixture::at(7, 8)) == Some(Bits::pow(Fixture::at(7, 7))),
        );
        // Δq = 1, Δr = 1, (7, 8) → (8, 9): between (8, 8) 128 and (7, 9) 142, row 8
        assert!(
            map.line(Fixture::at(7, 8), Fixture::at(8, 9)) == Some(Bits::pow(Fixture::at(8, 8))),
        );
        // Distance 4 along a tie axis: two ties, each to the lower index (the oracle's tiles)
        let tiles = Oracle::line(Fixture::at(7, 8), Fixture::at(7, 12)).unwrap();
        assert!(
            map.line(Fixture::at(7, 8), Fixture::at(7, 12)) == Some(Fixture::mask(tiles.span())),
        );
        assert!(
            tiles
                .span() == array![Fixture::at(6, 9), Fixture::at(7, 10), Fixture::at(6, 11)]
                .span(),
        );
        // Distance 6 along a tie axis: three ties
        let tiles = Oracle::line(Fixture::at(7, 2), Fixture::at(7, 8)).unwrap();
        assert!(
            map.line(Fixture::at(7, 2), Fixture::at(7, 8)) == Some(Fixture::mask(tiles.span())),
        );
        assert!(tiles.len() == 5);
        // A wall on the tile the tie takes blocks; a wall on the other tile does not
        assert!(
            !Fixture::walled(array![Fixture::at(6, 9)].span())
                .sight(Fixture::at(7, 8), Fixture::at(7, 10)),
        );
        assert!(
            Fixture::walled(array![Fixture::at(7, 9)].span())
                .sight(Fixture::at(7, 8), Fixture::at(7, 10)),
        );
        // At the window's East edge the lower index is the column −1: the line leaves the window
        assert!(map.line(Fixture::at(0, 0), Fixture::at(0, 2)).is_none());
        assert!(!Fixture::open().sight(Fixture::at(0, 0), Fixture::at(0, 2)));
    }

    /// Walls between the ends block, actors are not walls; walkable adjacent tiles and a walkable
    /// tile with itself see each other; a position outside the window sees nothing. A wall at an
    /// end is `test_sight_wall_at_an_end`'s.
    #[test]
    #[available_gas(l2_gas: 120337)] // ceil(1.05 × 114606 measured)
    fn test_sight() {
        let window = Fixture::walled(array![Fixture::at(9, 8)].span());
        // (7, 8) → (11, 8): the row, through (9, 8)
        assert!(!window.sight(Fixture::at(7, 8), Fixture::at(11, 8)));
        assert!(!window.sight(Fixture::at(11, 8), Fixture::at(7, 8)));
        assert!(Fixture::open().sight(Fixture::at(7, 8), Fixture::at(11, 8)));
        // Adjacent to the wall, the same tile
        assert!(window.sight(Fixture::at(8, 8), Fixture::at(10, 8)) == false);
        assert!(window.sight(Fixture::at(8, 8), Fixture::at(8, 9)));
        assert!(window.sight(Fixture::at(7, 8), Fixture::at(7, 8)));
        // Outside the window
        assert!(!Fixture::open().sight(SIZE, Fixture::at(7, 8)));
        assert!(!Fixture::open().sight(Fixture::at(7, 8), 255));
    }

    /// D-174: a wall at either end of the line blocks the sight, at range, adjacent and on the same
    /// tile.
    #[test]
    #[available_gas(l2_gas: 227386)] // ceil(1.05 × 216558 measured)
    fn test_sight_wall_at_an_end() {
        let window = Fixture::walled(array![Fixture::at(9, 8)].span());
        // At range, the wall at `to` and at `from`, both orders
        assert!(!window.sight(Fixture::at(6, 8), Fixture::at(9, 8)));
        assert!(!window.sight(Fixture::at(9, 8), Fixture::at(6, 8)));
        assert!(!window.sight(Fixture::at(9, 8), Fixture::at(12, 8)));
        assert!(!window.sight(Fixture::at(12, 8), Fixture::at(9, 8)));
        // Adjacent, and the same tile
        assert!(!window.sight(Fixture::at(8, 8), Fixture::at(9, 8)));
        assert!(!window.sight(Fixture::at(9, 8), Fixture::at(8, 8)));
        assert!(!window.sight(Fixture::at(9, 8), Fixture::at(9, 8)));
        // So `reach`: a touch on a wall is not in reach
        assert!(!window.reach(Fixture::at(8, 8), Fixture::at(9, 8), range::TOUCH));
        assert!(!window.reach(Fixture::at(9, 8), Fixture::at(8, 8), range::TOUCH));
        // Two neighbours of the wall, adjacent to each other, still see each other
        assert!(window.sight(Fixture::at(8, 8), Fixture::at(8, 9)));
        // A window of walls: nothing sees, not even a tile itself
        let closed = WindowTrait::new(0);
        assert!(!closed.sight(Fixture::at(7, 8), Fixture::at(8, 8)));
        assert!(!closed.sight(Fixture::at(7, 8), Fixture::at(7, 8)));
        assert!(!closed.sight(Fixture::at(7, 8), Fixture::at(9, 8)));
    }

    /// design/04's ranges: within the range and in sight.
    #[test]
    // gas: raised, sight tests both ends of the line (fix loop 1, a wall at either end blocks)
    #[available_gas(l2_gas: 126889)] // ceil(1.05 × 120846 measured)
    fn test_reach() {
        let window = Fixture::walled(array![Fixture::at(9, 8)].span());
        assert!(window.reach(Fixture::at(7, 8), Fixture::at(8, 8), range::TOUCH));
        assert!(!window.reach(Fixture::at(7, 8), Fixture::at(10, 8), range::TOUCH));
        assert!(Fixture::open().reach(Fixture::at(7, 8), Fixture::at(13, 8), range::RANGED));
        assert!(!Fixture::open().reach(Fixture::at(7, 8), Fixture::at(14, 8), range::RANGED));
        assert!(!window.reach(Fixture::at(7, 8), Fixture::at(11, 8), range::RANGED));
        // A wall next to the attacker does not stop a touch: no tile between
        assert!(window.reach(Fixture::at(8, 8), Fixture::at(8, 9), range::TOUCH));
        assert!(window.reach(Fixture::at(10, 8), Fixture::at(10, 9), range::TOUCH));
        assert!(Fixture::open().reach(Fixture::at(7, 8), Fixture::at(7, 8), range::TOUCH));
        assert!(!Fixture::open().reach(Fixture::at(7, 8), SIZE, range::RANGED));
        assert!(!Fixture::open().reach(SIZE, Fixture::at(7, 8), range::RANGED));
        // A radius without sight (alert, earshot) is a distance
        assert!(WindowTrait::distance(Fixture::at(0, 0), Fixture::at(8, 0)) <= range::EARSHOT);
        assert!(WindowTrait::distance(Fixture::at(0, 0), Fixture::at(9, 0)) > range::EARSHOT);
        assert!(range::NEARBY == 2 && range::AREA == 3 && range::ALERT == 5);
    }

    /// A position outside the window (240, 255) at either end or both: `FAR`, no panic, and no
    /// range holds it.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_distance_outside() {
        let centre = Fixture::at(7, 8);
        assert!(WindowTrait::distance(SIZE, centre) == FAR);
        assert!(WindowTrait::distance(centre, SIZE) == FAR);
        assert!(WindowTrait::distance(255, centre) == FAR);
        assert!(WindowTrait::distance(centre, 255) == FAR);
        assert!(WindowTrait::distance(SIZE, 255) == FAR);
        assert!(WindowTrait::distance(255, 255) == FAR);
        assert!(FAR > range::EARSHOT);
        // The last tile of the window is inside
        assert!(WindowTrait::distance(SIZE - 1, SIZE - 1) == 0);
        // (0, 0) to (14, 15): dq = 7, dr = 15, one sign
        assert!(WindowTrait::distance(0, SIZE - 1) == 22);
    }

    /// A window is made through `new` or `Serde`: one felt, a bit at or above 240 refused.
    #[test]
    #[available_gas(l2_gas: 45087)] // ceil(1.05 × 42940 measured)
    fn test_window_serde() {
        let window = Fixture::fixture();
        let mut felts: Array<felt252> = array![];
        window.serialize(ref felts);
        assert!(felts.span() == array![window.open()].span());
        let mut span = felts.span();
        assert!(Serde::<Window>::deserialize(ref span) == Some(window));
        let mut above = array![OPEN + 1].span();
        assert!(Serde::<Window>::deserialize(ref above).is_none());
        let mut empty = array![].span();
        assert!(Serde::<Window>::deserialize(ref empty).is_none());
    }

    // ---- Arcs, front, facing -----------------------------------------------------------------

    /// AC-2: each arc, for a source on each of the six neighbours and each of the six facings, on
    /// both row parities.
    #[test]
    #[available_gas(l2_gas: 2308824)] // ceil(1.05 × 2198880 measured)
    fn test_arc_melee() {
        let targets: [u8; 2] = [Fixture::at(7, 7), Fixture::at(7, 8)];
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
        assert!(WindowTrait::arc(Fixture::at(6, 8), Fixture::at(7, 8), 0) == Some(Arc::Front));
        assert!(WindowTrait::arc(Fixture::at(8, 8), Fixture::at(7, 8), 0) == Some(Arc::Back));
        // North-East (6, 9) front-side, North-West (7, 9) rear-side
        assert!(WindowTrait::arc(Fixture::at(6, 9), Fixture::at(7, 8), 0) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(Fixture::at(7, 9), Fixture::at(7, 8), 0) == Some(Arc::RearSide));
    }

    /// At range, the arc of the tile the line of sight arrives from: from straight East the front,
    /// from straight West the back, and across a tie the lower index's tile.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_arc_ranged() {
        // Target (7, 8) facing East (0); the line from (2, 8) arrives from (6, 8), East
        assert!(WindowTrait::arc(Fixture::at(2, 8), Fixture::at(7, 8), 0) == Some(Arc::Front));
        assert!(WindowTrait::arc(Fixture::at(13, 8), Fixture::at(7, 8), 0) == Some(Arc::Back));
        assert!(WindowTrait::arc(Fixture::at(13, 8), Fixture::at(7, 8), 3) == Some(Arc::Front));
        // (7, 10) → (7, 8) passes the tie at (6, 9), North-East of the target: front-side when
        // facing East, front when facing North-East; the other tile (7, 9) would be North-West
        assert!(WindowTrait::arc(Fixture::at(7, 10), Fixture::at(7, 8), 1) == Some(Arc::Front));
        assert!(WindowTrait::arc(Fixture::at(7, 10), Fixture::at(7, 8), 0) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(Fixture::at(7, 10), Fixture::at(7, 8), 2) == Some(Arc::FrontSide));
        assert!(WindowTrait::arc(Fixture::at(7, 10), Fixture::at(7, 8), 4) == Some(Arc::Back));
        // A wall on the line does not change the arc (the caller checks sight)
        // The edges: the same tile, outside, a line leaving the window
        assert!(WindowTrait::arc(Fixture::at(7, 8), Fixture::at(7, 8), 0).is_none());
        assert!(WindowTrait::arc(SIZE, Fixture::at(7, 8), 0).is_none());
        assert!(WindowTrait::arc(Fixture::at(7, 8), 250, 0).is_none());
        // A line leaving the window (no sight, so no hit): the arc of its first step from the
        // target, the column −1 at (−1, 1), North-East of (0, 0)
        assert!(WindowTrait::arc(Fixture::at(0, 2), Fixture::at(0, 0), 1) == Some(Arc::Front));
    }

    /// "On the front tile": only the neighbour in the facing's direction.
    #[test]
    #[available_gas(l2_gas: 1669784)] // ceil(1.05 × 1590270 measured)
    fn test_front() {
        let sources: [u8; 2] = [Fixture::at(7, 7), Fixture::at(7, 8)];
        for source in sources.span() {
            let source = *source;
            let mut facing: u8 = 0;
            while facing != 6 {
                let mut d: u8 = 0;
                while d != 6 {
                    let target = LayoutTrait::neighbor(WIDTH, HEIGHT, source, d.try_into().unwrap())
                        .unwrap();
                    assert!(WindowTrait::front(source, target, facing) == (d == facing));
                    d += 1;
                }
                facing += 1;
            }
            // Two tiles away in the facing's direction is not the front tile; nor the same tile
            assert!(!WindowTrait::front(source, source - 2, 0));
            assert!(!WindowTrait::front(source, source, 0));
        }
        // At the edge the front tile is outside the window: nothing is on it
        assert!(!WindowTrait::front(Fixture::at(0, 8), Fixture::at(14, 7), 0));
        assert!(!WindowTrait::front(SIZE, Fixture::at(7, 8), 0));
    }

    /// §5.3 step 3: toward the moved-to tile, toward an adjacent target, toward the first step of
    /// the line; unchanged for the same tile and outside the window.
    #[test]
    #[available_gas(l2_gas: 402633)] // ceil(1.05 × 383460 measured)
    fn test_facing() {
        // Each neighbour gives its direction, from both row parities
        let froms: [u8; 2] = [Fixture::at(7, 7), Fixture::at(7, 8)];
        for from in froms.span() {
            let from = *from;
            let mut d: u8 = 0;
            while d != 6 {
                let to = LayoutTrait::neighbor(WIDTH, HEIGHT, from, d.try_into().unwrap()).unwrap();
                assert!(WindowTrait::facing(from, to, (d + 3) % 6) == d);
                d += 1;
            }
        }
        // Straight West along the row
        assert!(WindowTrait::facing(Fixture::at(7, 8), Fixture::at(12, 8), 0) == 3);
        // Across a tie: (7, 8) → (7, 10), the first step is (6, 9), North-East
        assert!(WindowTrait::facing(Fixture::at(7, 8), Fixture::at(7, 10), 4) == 1);
        // The other way: (7, 10) → (7, 8), the first step is (6, 9), South-East of (7, 10)
        assert!(WindowTrait::facing(Fixture::at(7, 10), Fixture::at(7, 8), 4) == 5);
        // The same tile, outside: unchanged
        assert!(WindowTrait::facing(Fixture::at(7, 8), Fixture::at(7, 8), 4) == 4);
        assert!(WindowTrait::facing(Fixture::at(7, 8), SIZE, 2) == 2);
        // A line leaving the window: the first step of the unbounded line, toward the column −1
        // ((0, 0) → (0, 2): the tie takes (−1, 1), North-East of (0, 0))
        assert!(WindowTrait::facing(Fixture::at(0, 0), Fixture::at(0, 2), 3) == 1);
        // Back: (0, 2) → (0, 0) takes (−1, 1), South-East of (0, 2)
        assert!(WindowTrait::facing(Fixture::at(0, 2), Fixture::at(0, 0), 3) == 5);
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'window: facing')]
    fn test_facing_invalid() {
        WindowTrait::facing(Fixture::at(7, 8), Fixture::at(8, 8), 6);
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'window: facing')]
    fn test_arc_facing_invalid() {
        let _ = WindowTrait::arc(Fixture::at(8, 8), Fixture::at(7, 8), 7);
    }

    // ---- Shapes ------------------------------------------------------------------------------

    #[test]
    #[available_gas(l2_gas: 919405473)] // ceil(1.05 × 875624260 measured)
    fn test_shapes_every_centre_0() {
        Fixture::check_shapes(0, 40);
    }

    #[test]
    #[available_gas(l2_gas: 920783378)] // ceil(1.05 × 876936550 measured)
    fn test_shapes_every_centre_1() {
        Fixture::check_shapes(40, 80);
    }

    #[test]
    #[available_gas(l2_gas: 920848331)] // ceil(1.05 × 876998410 measured)
    fn test_shapes_every_centre_2() {
        Fixture::check_shapes(80, 120);
    }

    #[test]
    #[available_gas(l2_gas: 920928866)] // ceil(1.05 × 877075110 measured)
    fn test_shapes_every_centre_3() {
        Fixture::check_shapes(120, 160);
    }

    #[test]
    #[available_gas(l2_gas: 920932100)] // ceil(1.05 × 877078190 measured)
    fn test_shapes_every_centre_4() {
        Fixture::check_shapes(160, 200);
    }

    #[test]
    #[available_gas(l2_gas: 919408560)] // ceil(1.05 × 875627200 measured)
    fn test_shapes_every_centre_5() {
        Fixture::check_shapes(200, 240);
    }

    /// Counts in the open, at the corners and edges; walls skipped; the centre a wall.
    // CBT-05a: `near` is `shape` for the MVP's three shapes at every centre, and empty for the
    // radii FX-21 defers.
    #[test]
    #[available_gas(l2_gas: 100000000)]
    fn test_near_agrees() {
        let window = Fixture::walled(array![17, 112, 200].span());
        for centre in 0..240_u8 {
            for s in 1..4_u8 {
                assert(window.near(s, centre) == window.shape(s, centre), 'near = shape');
            }
            assert(window.near(4, centre) == 0 && window.near(5, centre) == 0, 'deferred');
        }
    }

    #[test]
    #[available_gas(l2_gas: 1454972)] // ceil(1.05 × 1385687 measured)
    fn test_shapes_edges() {
        let window = Fixture::open();
        let count = |mask: felt252| WindowTrait::tiles(mask).len();
        assert!(count(window.shape(shape::SINGLE, Fixture::at(7, 8))) == 1);
        assert!(count(window.shape(shape::RING_1, Fixture::at(7, 8))) == 6);
        assert!(count(window.shape(shape::DISC_1, Fixture::at(7, 8))) == 7);
        assert!(count(window.shape(shape::DISC_2, Fixture::at(7, 8))) == 19);
        assert!(count(window.shape(shape::DISC_3, Fixture::at(7, 8))) == 37);
        // The corner (0, 0): East and the row below are outside
        assert!(
            WindowTrait::tiles(
                window.shape(shape::DISC_1, Fixture::at(0, 0)),
            ) == array![Fixture::at(0, 0), Fixture::at(1, 0), Fixture::at(0, 1)]
                .span(),
        );
        assert!(count(window.shape(shape::RING_1, Fixture::at(14, 15))) == 2);
        assert!(count(window.shape(shape::DISC_1, Fixture::at(14, 0))) == 4);
        assert!(count(window.shape(shape::DISC_1, Fixture::at(0, 15))) == 4);
        assert!(count(window.shape(shape::DISC_3, Fixture::at(0, 0))) == 12);
        assert!(count(window.shape(shape::DISC_1, Fixture::at(0, 8))) == 4);
        // Walls hold no actor
        let walls = Fixture::walled(
            array![Fixture::at(8, 8), Fixture::at(6, 9), Fixture::at(7, 8)].span(),
        );
        assert!(
            WindowTrait::tiles(
                walls.shape(shape::DISC_1, Fixture::at(7, 8)),
            ) == array![Fixture::at(6, 7), Fixture::at(7, 7), Fixture::at(6, 8), Fixture::at(7, 9)]
                .span(),
        );
        assert!(walls.shape(shape::SINGLE, Fixture::at(7, 8)) == 0);
        // A centre outside the window: nothing
        assert!(window.shape(shape::DISC_3, SIZE) == 0);
        assert!(window.shape(shape::SINGLE, 255) == 0);
    }

    #[test]
    #[available_gas(l2_gas: 10595)] // ceil(1.05 × 10090 measured)
    #[should_panic(expected: 'window: shape')]
    fn test_shape_invalid() {
        Fixture::open().shape(6, Fixture::at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 10595)] // ceil(1.05 × 10090 measured)
    #[should_panic(expected: 'window: shape')]
    fn test_shape_zero() {
        Fixture::open().shape(0, Fixture::at(7, 8));
    }

    #[test]
    #[available_gas(l2_gas: 10385)] // ceil(1.05 × 9890 measured)
    #[should_panic(expected: 'window: open above 240')]
    fn test_window_bits_above() {
        WindowTrait::new(OPEN + 1);
    }

    /// `tiles` lists every set bit, ascending, across both limbs.
    #[test]
    #[available_gas(l2_gas: 2473686)] // ceil(1.05 × 2355891 measured)
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

    #[test]
    // gas: raised, sight tests both ends of the line (fix loop 1, a wall at either end blocks)
    #[available_gas(l2_gas: 45934)] // ceil(1.05 × 43746 measured)
    fn test_cost_sight_once() {
        let window = Fixture::bench();
        assert!(
            window.sight(Fixture::opaque(Fixture::at(7, 2)), Fixture::opaque(Fixture::at(7, 8))),
        );
    }

    #[test]
    // gas: raised, sight tests both ends of the line (fix loop 1, a wall at either end blocks)
    #[available_gas(l2_gas: 69219)] // ceil(1.05 × 65922 measured)
    fn test_cost_sight_twice() {
        let window = Fixture::bench();
        assert!(
            window.sight(Fixture::opaque(Fixture::at(7, 2)), Fixture::opaque(Fixture::at(7, 8))),
        );
        assert!(
            window.sight(Fixture::opaque(Fixture::at(7, 8)), Fixture::opaque(Fixture::at(7, 2))),
        );
    }

    #[test]
    // gas: raised, sight tests both ends of the line (fix loop 1, a wall at either end blocks)
    #[available_gas(l2_gas: 58481)] // ceil(1.05 × 55696 measured)
    fn test_cost_reach_once() {
        let window = Fixture::bench();
        assert!(
            window
                .reach(
                    Fixture::opaque(Fixture::at(7, 2)),
                    Fixture::opaque(Fixture::at(7, 8)),
                    Fixture::opaque(range::RANGED),
                ),
        );
    }

    #[test]
    // gas: raised, sight tests both ends of the line (fix loop 1, a wall at either end blocks)
    #[available_gas(l2_gas: 94408)] // ceil(1.05 × 89912 measured)
    fn test_cost_reach_twice() {
        let window = Fixture::bench();
        assert!(
            window
                .reach(
                    Fixture::opaque(Fixture::at(7, 2)),
                    Fixture::opaque(Fixture::at(7, 8)),
                    Fixture::opaque(range::RANGED),
                ),
        );
        assert!(
            window
                .reach(
                    Fixture::opaque(Fixture::at(7, 8)),
                    Fixture::opaque(Fixture::at(7, 2)),
                    Fixture::opaque(range::RANGED),
                ),
        );
    }

    #[test]
    #[available_gas(l2_gas: 33653)] // ceil(1.05 × 32050 measured)
    fn test_cost_arc_melee_once() {
        assert!(
            WindowTrait::arc(
                Fixture::opaque(Fixture::at(8, 8)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(0),
            ) == Some(Arc::Back),
        );
    }

    #[test]
    #[available_gas(l2_gas: 60050)] // ceil(1.05 × 57190 measured)
    fn test_cost_arc_melee_twice() {
        assert!(
            WindowTrait::arc(
                Fixture::opaque(Fixture::at(8, 8)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(0),
            ) == Some(Arc::Back),
        );
        assert!(
            WindowTrait::arc(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(8, 8)),
                Fixture::opaque(0),
            ) == Some(Arc::Front),
        );
    }

    #[test]
    #[available_gas(l2_gas: 33653)] // ceil(1.05 × 32050 measured)
    fn test_cost_arc_ranged_once() {
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 2)),
            Fixture::opaque(Fixture::at(7, 8)),
            Fixture::opaque(0),
        );
        assert!(arc == Some(Arc::FrontSide));
    }

    #[test]
    #[available_gas(l2_gas: 60155)] // ceil(1.05 × 57290 measured)
    fn test_cost_arc_ranged_twice() {
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 2)),
            Fixture::opaque(Fixture::at(7, 8)),
            Fixture::opaque(0),
        );
        assert!(arc == Some(Arc::FrontSide));
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 8)),
            Fixture::opaque(Fixture::at(7, 2)),
            Fixture::opaque(0),
        );
        assert!(arc == Some(Arc::FrontSide));
    }

    /// A target on the window's ring: its neighbours one direction at a time (`hexx`'s
    /// `edge_neighbors`).
    #[test]
    #[available_gas(l2_gas: 33653)] // ceil(1.05 × 32050 measured)
    fn test_cost_arc_ring_once() {
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 9)),
            Fixture::opaque(Fixture::at(7, 15)),
            Fixture::opaque(0),
        );
        assert!(arc == Some(Arc::FrontSide));
    }

    #[test]
    #[available_gas(l2_gas: 60155)] // ceil(1.05 × 57290 measured)
    fn test_cost_arc_ring_twice() {
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 9)),
            Fixture::opaque(Fixture::at(7, 15)),
            Fixture::opaque(0),
        );
        assert!(arc == Some(Arc::FrontSide));
        let arc = WindowTrait::arc(
            Fixture::opaque(Fixture::at(7, 9)),
            Fixture::opaque(Fixture::at(7, 15)),
            Fixture::opaque(3),
        );
        assert!(arc == Some(Arc::RearSide));
    }

    /// The benchmark's own share of a call: three opaque inputs and the check, measured alone.
    #[test]
    #[available_gas(l2_gas: 9713)] // ceil(1.05 × 9250 measured)
    fn test_cost_overhead_once() {
        assert!(Fixture::opaque(1) + Fixture::opaque(2) + Fixture::opaque(3) == 6);
    }

    #[test]
    #[available_gas(l2_gas: 12275)] // ceil(1.05 × 11690 measured)
    fn test_cost_overhead_twice() {
        assert!(Fixture::opaque(1) + Fixture::opaque(2) + Fixture::opaque(3) == 6);
        assert!(Fixture::opaque(3) + Fixture::opaque(2) + Fixture::opaque(1) == 6);
    }

    /// `distance` at range 6 (the hit's `melee` input, CBT-05a): one cost on every path.
    #[test]
    // gas: raised, distance guards a position outside the window (fix loop 3)
    #[available_gas(l2_gas: 24192)] // ceil(1.05 × 23040 measured)
    fn test_cost_distance_once() {
        let distance = WindowTrait::distance(
            Fixture::opaque(Fixture::at(7, 2)), Fixture::opaque(Fixture::at(7, 8)),
        );
        assert!(distance == Fixture::opaque(6));
    }

    #[test]
    // gas: raised, distance guards a position outside the window (fix loop 3)
    #[available_gas(l2_gas: 41234)] // ceil(1.05 × 39270 measured)
    fn test_cost_distance_twice() {
        let distance = WindowTrait::distance(
            Fixture::opaque(Fixture::at(7, 2)), Fixture::opaque(Fixture::at(7, 8)),
        );
        assert!(distance == Fixture::opaque(6));
        let distance = WindowTrait::distance(
            Fixture::opaque(Fixture::at(7, 8)), Fixture::opaque(Fixture::at(7, 2)),
        );
        assert!(distance == Fixture::opaque(6));
    }

    #[test]
    #[available_gas(l2_gas: 19593)] // ceil(1.05 × 18660 measured)
    fn test_cost_front_once() {
        assert!(
            WindowTrait::front(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(1),
            ),
        );
    }

    #[test]
    #[available_gas(l2_gas: 32036)] // ceil(1.05 × 30510 measured)
    fn test_cost_front_twice() {
        assert!(
            WindowTrait::front(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(1),
            ),
        );
        assert!(
            WindowTrait::front(
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(4),
            ),
        );
    }

    #[test]
    #[available_gas(l2_gas: 30776)] // ceil(1.05 × 29310 measured)
    fn test_cost_facing_melee_once() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(0),
            ) == 1,
        );
    }

    #[test]
    #[available_gas(l2_gas: 54401)] // ceil(1.05 × 51810 measured)
    fn test_cost_facing_melee_twice() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(0),
            ) == 1,
        );
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(6, 9)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(0),
            ) == 4,
        );
    }

    #[test]
    #[available_gas(l2_gas: 30776)] // ceil(1.05 × 29310 measured)
    fn test_cost_facing_ranged_once() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(7, 2)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(0),
            ) == 1,
        );
    }

    #[test]
    #[available_gas(l2_gas: 54401)] // ceil(1.05 × 51810 measured)
    fn test_cost_facing_ranged_twice() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(7, 2)),
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(0),
            ) == 1,
        );
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(7, 8)),
                Fixture::opaque(Fixture::at(7, 2)),
                Fixture::opaque(0),
            ) == 5,
        );
    }

    /// The fallback of a line that leaves the window: the unbounded line.
    #[test]
    #[available_gas(l2_gas: 30776)] // ceil(1.05 × 29310 measured)
    fn test_cost_facing_outside_once() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(0, 0)),
                Fixture::opaque(Fixture::at(0, 2)),
                Fixture::opaque(3),
            ) == 1,
        );
    }

    #[test]
    #[available_gas(l2_gas: 54401)] // ceil(1.05 × 51810 measured)
    fn test_cost_facing_outside_twice() {
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(0, 0)),
                Fixture::opaque(Fixture::at(0, 2)),
                Fixture::opaque(3),
            ) == 1,
        );
        assert!(
            WindowTrait::facing(
                Fixture::opaque(Fixture::at(0, 2)),
                Fixture::opaque(Fixture::at(0, 0)),
                Fixture::opaque(3),
            ) == 5,
        );
    }

    #[test]
    #[available_gas(l2_gas: 38038)] // ceil(1.05 × 36226 measured)
    fn test_cost_shape_disc_1_once() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 8))) != 0,
        );
    }

    #[test]
    #[available_gas(l2_gas: 53427)] // ceil(1.05 × 50882 measured)
    fn test_cost_shape_disc_1_twice() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 8))) != 0,
        );
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 7))) != 0,
        );
    }

    /// A bomb's `DISC_1` on the window's ring: the rows of `disc`.
    #[test]
    #[available_gas(l2_gas: 82043)] // ceil(1.05 × 78136 measured)
    fn test_cost_shape_disc_1_ring_once() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 15))) != 0,
        );
    }

    #[test]
    #[available_gas(l2_gas: 155466)] // ceil(1.05 × 148062 measured)
    fn test_cost_shape_disc_1_ring_twice() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 15))) != 0,
        );
        assert!(
            window.shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(0, 7))) != 0,
        );
    }

    #[test]
    #[available_gas(l2_gas: 166610)] // ceil(1.05 × 158676 measured)
    fn test_cost_shape_disc_3_once() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_3), Fixture::opaque(Fixture::at(7, 8))) != 0,
        );
    }

    #[test]
    #[available_gas(l2_gas: 310572)] // ceil(1.05 × 295782 measured)
    fn test_cost_shape_disc_3_twice() {
        let window = Fixture::bench();
        assert!(
            window.shape(Fixture::opaque(shape::DISC_3), Fixture::opaque(Fixture::at(7, 8))) != 0,
        );
        assert!(
            window.shape(Fixture::opaque(shape::DISC_3), Fixture::opaque(Fixture::at(7, 7))) != 0,
        );
    }

    /// The seven tiles of a `DISC_1`, listed.
    #[test]
    #[available_gas(l2_gas: 97826)] // ceil(1.05 × 93167 measured)
    fn test_cost_tiles_7_once() {
        let disc = Fixture::bench()
            .shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 8)));
        assert!(WindowTrait::tiles(disc).len() == 7);
    }

    #[test]
    #[available_gas(l2_gas: 157834)] // ceil(1.05 × 150318 measured)
    fn test_cost_tiles_7_twice() {
        let disc = Fixture::bench()
            .shape(Fixture::opaque(shape::DISC_1), Fixture::opaque(Fixture::at(7, 8)));
        assert!(WindowTrait::tiles(disc).len() == 7);
        assert!(WindowTrait::tiles(disc).len() == 7);
    }

    // ---- The vector table for the TypeScript mirror (D-140, SPK-4) ---------------------------

    // AC-4: the vector table, printed one JSON line per case (`{"id", "fn", "case", "ok"}`), in two
    // parts, each with a digest of its cases and outcomes: a change to a rule or to the cases fails
    // here until `contracts/logic/vectors/window.jsonl` is regenerated, and
    // `vectors/check.py` fails while the committed file differs from what these print
    // (`vectors/README.md`).
    #[test]
    // gas: raised, more cases (an odd-row target, from on a wall), both ends, distance's guard
    #[available_gas(l2_gas: 1265854713)] // ceil(1.05 × 1205575917 measured)
    fn test_vectors() {
        let window = Fixture::fixture();
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        // `sight` and `reach` (range 6): from both row parities to every tile within 7, and the
        // edges (outside, a line leaving the window, the same tile)
        let mut pairs: Array<(u8, u8)> = array![];
        let froms: [u8; 2] = [Fixture::at(7, 8), Fixture::at(7, 7)];
        for from in froms.span() {
            let mut to: u8 = 0;
            while to != SIZE {
                if WindowTrait::distance(*from, to) <= 7 {
                    pairs.append((*from, to));
                }
                to += 1;
            }
        }
        pairs.append((Fixture::at(0, 0), Fixture::at(0, 2)));
        pairs.append((Fixture::at(0, 2), Fixture::at(0, 0)));
        pairs.append((Fixture::at(14, 15), Fixture::at(14, 13)));
        pairs.append((SIZE, Fixture::at(7, 8)));
        pairs.append((Fixture::at(7, 8), 255));
        // `from` on a wall of the fixture (D-174): at range, adjacent, the same tile
        pairs.append((Fixture::at(9, 8), Fixture::at(7, 8)));
        pairs.append((Fixture::at(9, 8), Fixture::at(10, 8)));
        pairs.append((Fixture::at(9, 8), Fixture::at(9, 8)));
        pairs.append((Fixture::at(6, 9), Fixture::at(3, 9)));
        pairs.append((Fixture::at(6, 9), Fixture::at(7, 9)));
        pairs.append((Fixture::at(5, 6), Fixture::at(5, 6)));
        for (from, to) in pairs.span() {
            let (from, to) = (*from, *to);
            let case = array![window.open, from.into(), to.into()];
            let ok = array![window.sight(from, to).into()];
            Fixture::emit(ref digest, ref id, "sight", case.span(), ok.span());
            let case = array![window.open, from.into(), to.into(), range::RANGED.into()];
            let ok = array![window.reach(from, to, range::RANGED).into()];
            Fixture::emit(ref digest, ref id, "reach", case.span(), ok.span());
        }
        // `arc` and `facing`: every source within 6 of the targets (7, 8), an even row, and (7, 7),
        // an odd one, the facing turning with the source; the edges
        let mut triples: Array<(u8, u8, u8)> = array![];
        let mut k: u8 = 0;
        let targets: [u8; 2] = [Fixture::at(7, 8), Fixture::at(7, 7)];
        for target in targets.span() {
            let mut source: u8 = 0;
            while source != SIZE {
                if WindowTrait::distance(source, *target) <= 6 {
                    triples.append((source, *target, k % 6));
                    k += 1;
                }
                source += 1;
            }
        }
        triples.append((Fixture::at(0, 2), Fixture::at(0, 0), 0));
        triples.append((Fixture::at(0, 0), Fixture::at(0, 2), 3));
        triples.append((SIZE, Fixture::at(7, 8), 1));
        triples.append((Fixture::at(7, 8), Fixture::at(7, 15), 2));
        for (source, target, facing) in triples.span() {
            let (source, target, facing) = (*source, *target, *facing);
            let case = array![source.into(), target.into(), facing.into()];
            let mut ok: Array<felt252> = array![];
            WindowTrait::arc(source, target, facing).serialize(ref ok);
            Fixture::emit(ref digest, ref id, "arc", case.span(), ok.span());
            let ok = array![WindowTrait::facing(source, target, facing).into()];
            Fixture::emit(ref digest, ref id, "facing", case.span(), ok.span());
        }
        let digest = core::poseidon::poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(id == PART_1, 'vectors: part 1 moved');
        assert(digest == DIGEST_0, 'vectors moved: regenerate');
    }

    /// The table's second part, its ids following the first's (snforge's step limit splits it).
    #[test]
    // gas: raised, front's outside neighbour as 240; distance outside cases and guard (fix loop 3)
    #[available_gas(l2_gas: 438945576)] // ceil(1.05 × 418043405 measured)
    fn test_vectors_1() {
        let window = Fixture::fixture();
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_1;
        // `front`: every neighbour and facing, at the centre and on the edge (a neighbour outside
        // the window is the position 240)
        let sources: [u8; 2] = [Fixture::at(7, 8), Fixture::at(0, 7)];
        for source in sources.span() {
            let mut facing: u8 = 0;
            while facing != 6 {
                let mut d: u8 = 0;
                while d != 6 {
                    let target =
                        match LayoutTrait::neighbor(WIDTH, HEIGHT, *source, d.try_into().unwrap()) {
                        Some(target) => target,
                        None => SIZE,
                    };
                    let case = array![(*source).into(), target.into(), facing.into()];
                    let ok = array![WindowTrait::front(*source, target, facing).into()];
                    Fixture::emit(ref digest, ref id, "front", case.span(), ok.span());
                    d += 1;
                }
                facing += 1;
            }
        }
        // `distance`: from the centre (an odd and an even row) and a corner to every tile of the
        // window
        let froms: [u8; 3] = [Fixture::at(7, 7), Fixture::at(7, 8), Fixture::at(0, 0)];
        for from in froms.span() {
            let mut to: u8 = 0;
            while to != SIZE {
                let case = array![(*from).into(), to.into()];
                let ok = array![WindowTrait::distance(*from, to).into()];
                Fixture::emit(ref digest, ref id, "distance", case.span(), ok.span());
                to += 1;
            }
        }
        // ... and a position outside the window at either end or both: `FAR`
        let outside: [(u8, u8); 4] = [
            (SIZE, Fixture::at(7, 8)), (Fixture::at(7, 8), 255), (SIZE, 255), (255, SIZE),
        ];
        for (from, to) in outside.span() {
            let case = array![(*from).into(), (*to).into()];
            let ok = array![WindowTrait::distance(*from, *to).into()];
            Fixture::emit(ref digest, ref id, "distance", case.span(), ok.span());
        }
        // `shape`: each shape at the corners, the edges, the centre and next to walls
        let centres: [u8; 11] = [
            Fixture::at(0, 0), Fixture::at(14, 0), Fixture::at(0, 15), Fixture::at(14, 15),
            Fixture::at(0, 8), Fixture::at(14, 7), Fixture::at(7, 0), Fixture::at(7, 15),
            Fixture::at(7, 8), Fixture::at(8, 8), Fixture::at(1, 1),
        ];
        let mut id_shape: u8 = shape::SINGLE;
        while id_shape <= shape::DISC_3 {
            for centre in centres.span() {
                let case = array![window.open, id_shape.into(), (*centre).into()];
                let ok = array![window.shape(id_shape, *centre)];
                Fixture::emit(ref digest, ref id, "shape", case.span(), ok.span());
            }
            id_shape += 1;
        }
        let digest = core::poseidon::poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_1, 'vectors moved: regenerate');
    }

    /// The cases of the first part; the second's first id.
    const PART_1: u32 = 1214;
    const DIGEST_0: felt252 =
        2027939412732297496338127652314768997524597226589897860129522502247018952946;
    const DIGEST_1: felt252 =
        2034462196832439640469718342796814804113743281669768041046952646849445135712;
}
