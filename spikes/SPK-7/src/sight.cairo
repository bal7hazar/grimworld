//! N-5: line of sight (design/04 *Ranges*, docs/needs/hexmap.md point 6, D-24).
//!
//! The game's rule: the integer hex line between two tiles, `N` = their hex distance, the `N - 1`
//! points `a + (b - a) i / N` each rounded to the nearest tile centre, ties to the lower tile
//! index; walls block, actors do not; only the tiles strictly between the two ends are tested.
//! The rule is symmetric and invariant under translation (a tie between two tiles is decided by
//! their row, then their column), so the tiles between two tiles depend only on their axial
//! offset `(dq, dr)` and, once converted to the window's odd-r indices, on the parity of the
//! source's row. `tables.cairo` holds them for every offset within 6 (the ranged range, which is
//! also sight), anchored at (7, 8) and (7, 7): one lookup, one exact shift, one AND.

use origami_hexmap::helpers::bits::Bits;
use crate::tables::{LOS_EVEN, LOS_ODD};

/// Longest line the tables hold (design/04: ranged range 6, sight 6).
pub const RANGE: u8 = 6;
/// Anchors of the tables: (7, 8) on an even row, (7, 7) on an odd row.
const ANCHOR_EVEN: u8 = 127;
const ANCHOR_ODD: u8 = 112;

pub mod errors {
    pub const LOS_BEYOND_RANGE: felt252 = 'los: beyond range';
}

/// The tiles strictly between two interior tiles of the window within 6 of each other.
/// # Panics
/// * If the tiles are more than 6 apart
pub fn between_mask(from: u8, to: u8) -> felt252 {
    let (y1, x1) = DivRem::div_rem(from, 15);
    let (y2, x2) = DivRem::div_rem(to, 15);
    let (h1, odd) = DivRem::div_rem(y1, 2);
    let (h2, _) = DivRem::div_rem(y2, 2);
    // [Compute] Axial offset plus 6: dq = (x2 - y2 / 2) - (x1 - y1 / 2), dr = y2 - y1
    let qa = x2 + h1 + RANGE;
    let qb = x1 + h2;
    let ra = y2 + RANGE;
    assert(qa >= qb && ra >= y1, errors::LOS_BEYOND_RANGE);
    let dq = qa - qb;
    let dr = ra - y1;
    // [Check] |dq| <= 6, |dr| <= 6, |dq + dr| <= 6
    let sum = dq + dr;
    assert(dq <= 12 && dr <= 12 && sum >= 6 && sum <= 18, errors::LOS_BEYOND_RANGE);
    let index: u32 = (dr * 13 + dq).into();
    // [Return] The anchored mask, shifted to the source
    let (mask, anchor) = if odd == 0 {
        (*LOS_EVEN.span()[index], ANCHOR_EVEN)
    } else {
        (*LOS_ODD.span()[index], ANCHOR_ODD)
    };
    if from >= anchor {
        mask * Bits::pow(from - anchor)
    } else {
        mask * Bits::inv(anchor - from)
    }
}

/// Whether `from` sees `to` on `terrain` (N-5): every tile strictly between them is walkable.
/// # Arguments
/// * `from`, `to` - Interior tiles of the window, at most 6 apart
/// * `terrain` - The window's walkable tiles
#[inline]
pub fn line_of_sight(from: u8, to: u8, terrain: felt252) -> bool {
    let mask = between_mask(from, to);
    let wide: u256 = mask.into();
    let open: u256 = terrain.into();
    let (low, _, _) = Bits::bitwise(wide.low, open.low);
    let (high, _, _) = Bits::bitwise(wide.high, open.high);
    low == wide.low && high == wide.high
}
