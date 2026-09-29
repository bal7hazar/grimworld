//! One goblin step on the window of D-120: 15 columns × 16 rows of pointy-top hexes, origin on an
//! even row, odd rows shifted right, tile `15 row + col`, one felt per layer with bit i for tile i
//! (SPK-7's conventions). The goblin steps to its free neighbour nearest to the target, ties by
//! lowest tile index (design/04 *Goblin AI*); it holds when no free neighbour is nearer than its own
//! tile, or when it already stands next to the target. The distance is the hex distance: the
//! shared flood of design/02 is out of this spike's scope.
//!
//! Layers are felts, read through a u256 view (docs/CAIRO.md §4, written reason: 240 tiles do not
//! fit a u128, and a felt has no bitwise operation; the view is the one `origami_hexmap`'s `u252`
//! takes). The occupied layer is updated by felt arithmetic, `occupied − 2^from + 2^to`: a goblin
//! whose own tile is not marked occupied makes it wrap modulo the field prime, as the chain would.

use crate::table::{POW2_FELT, POW2_U128};

pub const WIDTH: u8 = 15;
pub const HEIGHT: u8 = 16;
pub const TILES: u8 = 240;

pub mod errors {
    pub const TILE_OUTSIDE: felt252 = 'board: tile outside window';
}

/// Whether tile `tile` (< 240) is set in `layer`.
#[inline(always)]
fn has(layer: u256, tile: u8) -> bool {
    if tile < 128 {
        layer.low & *POW2_U128.span()[tile.into()] != 0
    } else {
        layer.high & *POW2_U128.span()[(tile - 128).into()] != 0
    }
}

/// Axial coordinates `(q, r)` of a tile (odd-r offset to axial).
#[inline(always)]
fn axial(tile: u8) -> (i16, i16) {
    let (row, col) = DivRem::div_rem(tile, WIDTH.try_into().unwrap());
    let q: i16 = col.into() - (row / 2).into();
    (q, row.into())
}

#[inline(always)]
fn abs(x: i16) -> i16 {
    if x < 0 {
        -x
    } else {
        x
    }
}

/// Hex distance between two tiles.
pub fn distance(a: u8, b: u8) -> u8 {
    let (qa, ra) = axial(a);
    let (qb, rb) = axial(b);
    let dq = qa - qb;
    let dr = ra - rb;
    let d: i16 = (abs(dq) + abs(dr) + abs(dq + dr)) / 2;
    d.try_into().unwrap()
}

/// Consider `n` as the goblin's next tile.
#[inline(always)]
fn consider(
    n: u8, target: u8, walkable: u256, occupied: u256, goblin: u8, ref best: u8, ref best_d: u8,
) {
    if !has(walkable, n) || has(occupied, n) {
        return;
    }
    let d = distance(n, target);
    if d < best_d || (d == best_d && best != goblin && n < best) {
        best = n;
        best_d = d;
    }
}

/// One step of a goblin toward a target.
/// # Arguments
/// * `walkable` - The window's walkable tiles
/// * `occupied` - The window's occupied tiles (actors), the goblin's own included
/// * `goblin` - The goblin's tile
/// * `target` - The target's tile
/// # Returns
/// * The goblin's new tile, and the occupied layer after the step
/// # Panics
/// * If a tile is outside the window
pub fn goblin_step(walkable: felt252, occupied: felt252, goblin: u8, target: u8) -> (u8, felt252) {
    assert(goblin < TILES && target < TILES, errors::TILE_OUTSIDE);
    let here = distance(goblin, target);
    if here <= 1 {
        return (goblin, occupied);
    }
    let w: u256 = walkable.into();
    let o: u256 = occupied.into();
    let (row, col) = DivRem::div_rem(goblin, WIDTH.try_into().unwrap());
    let odd = row % 2 == 1;
    let mut best = goblin;
    let mut best_d = here;
    // [Compute] The six neighbours, those inside the window: E, W on the row; the two above and
    // the two below sit at columns (col − 1, col) on an even row and (col, col + 1) on an odd one.
    if col + 1 < WIDTH {
        consider(goblin + 1, target, w, o, goblin, ref best, ref best_d);
    }
    if col > 0 {
        consider(goblin - 1, target, w, o, goblin, ref best, ref best_d);
    }
    let (left_ok, right_ok, left, right) = if odd {
        (true, col + 1 < WIDTH, 0_u8, 1_u8)
    } else {
        (col > 0, true, 1_u8, 0_u8)
    };
    // `left` is subtracted from the column and `right` added, so the pair is (col − left,
    // col + right).
    if row > 0 {
        let up = goblin - WIDTH;
        if left_ok {
            consider(up - left, target, w, o, goblin, ref best, ref best_d);
        }
        if right_ok {
            consider(up + right, target, w, o, goblin, ref best, ref best_d);
        }
    }
    if row + 1 < HEIGHT {
        let down = goblin + WIDTH;
        if left_ok {
            consider(down - left, target, w, o, goblin, ref best, ref best_d);
        }
        if right_ok {
            consider(down + right, target, w, o, goblin, ref best, ref best_d);
        }
    }
    if best == goblin {
        return (goblin, occupied);
    }
    let occupied = occupied - *POW2_FELT.span()[goblin.into()] + *POW2_FELT.span()[best.into()];
    (best, occupied)
}
