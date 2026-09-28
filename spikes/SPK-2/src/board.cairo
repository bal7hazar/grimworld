//! The window board and its flood, bit-parallel.
//!
//! `origami_hexmap` 1.8.0 does not build on Cairo 2.13 (see the report), so this is a plain
//! bitboard flood of our own, on the library's conventions: pointy-top, odd-r, tile `(x, y)` is
//! bit `15 y + x`, `+1` is West, `+15` is North, the ring is wall. Neighbour shifts are exact field
//! products under the border invariant (only interior tiles are ever dilated); set operations run
//! on the two `u128` limbs with the bitwise builtin.
//!
//! `u256` here is only the pair of limbs of a 240-bit board: the cheapest form for `&` and `|`
//! while `u252` is not available (docs/CAIRO.md §4, written reason).

use core::integer::Bitwise;
use crate::tables::{AROUND_EVEN, AROUND_ODD, DOWN, EVEN_HIGH, EVEN_LOW, INV_2, POW, UP, WIDTH};

/// AND, XOR and OR of two limbs in one application of the bitwise builtin (the corelib keeps
/// this libfunc private; `origami_hexmap` declares it the same way).
pub extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

pub const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
/// 256^j, the byte of goblin `j` in a packed distance word.
const BYTE: [u128; 8] = [
    0x1, 0x100, 0x10000, 0x1000000, 0x100000000, 0x10000000000, 0x1000000000000, 0x100000000000000,
];

#[inline(always)]
pub fn pow(index: u8) -> felt252 {
    *POW.span()[index.into()]
}

#[inline(always)]
pub fn to_felt(value: u256) -> felt252 {
    value.low.into() + value.high.into() * TWO_POW_128
}

#[inline(always)]
pub fn and(lhs: u256, rhs: u256) -> u256 {
    let (low, _, _) = bitwise(lhs.low, rhs.low);
    let (high, _, _) = bitwise(lhs.high, rhs.high);
    u256 { low, high }
}

/// Whether bit `index` of a board is set.
#[inline(always)]
pub fn has(board: u256, index: u8) -> bool {
    let bit: u256 = pow(index).into();
    let hit = and(board, bit);
    hit.low != 0 || hit.high != 0
}

/// The frontier and all its neighbours (frontier: interior tiles only).
#[inline(always)]
pub fn dilate(low: u128, high: u128, felt: felt252) -> (u128, u128) {
    // [Compute] Frontier and its West neighbours, split by row parity
    let double: u256 = (felt + felt).into();
    let (_, _, pairs_low) = bitwise(low, double.low);
    let (_, _, pairs_high) = bitwise(high, double.high);
    let (even_low, _, _) = bitwise(pairs_low, EVEN_LOW);
    let (even_high, _, _) = bitwise(pairs_high, EVEN_HIGH);
    let pairs: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128;
    let even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
    let rows = pairs + pairs - even;
    // [Compute] North, South and East neighbours: one field product each
    let up: u256 = (rows * UP).into();
    let down: u256 = (rows * DOWN).into();
    let east: u256 = (felt * INV_2).into();
    let (_, _, side_low) = bitwise(pairs_low, east.low);
    let (_, _, side_high) = bitwise(pairs_high, east.high);
    let (_, _, vertical_low) = bitwise(up.low, down.low);
    let (_, _, vertical_high) = bitwise(up.high, down.high);
    let (_, _, low) = bitwise(side_low, vertical_low);
    let (_, _, high) = bitwise(side_high, vertical_high);
    (low, high)
}

/// The 6 neighbour bits of an interior tile.
#[inline(always)]
pub fn around(index: u8) -> felt252 {
    let (_, rem) = DivRem::div_rem(index, 30);
    if rem < WIDTH {
        pow(index) * AROUND_EVEN
    } else {
        pow(index) * AROUND_ODD
    }
}

/// Depth of the tick's flood (D-127: design/02 *Simulation budget*, design/04 *Goblin AI*,
/// ADR-0006 §4): a goblin with no way to the adventurer within 15 steps holds its position.
pub const FLOOD_LAYERS: felt252 = 15;
/// No limit: more layers than the interior has tiles (182). For the oracle tests.
pub const UNLIMITED: felt252 = 255;

/// The tick's single flood (design/02 *Simulation budget*, docs/needs/hexmap.md point 5, rule
/// (a)): breadth first from the adventurer over `free`, the walkable interior tiles minus the
/// occupancy frozen at the start of the tick. Layer `k` is the set of tiles at distance `k`.
/// The flood stops as soon as every goblin has touched a layer, when the frontier runs out, or
/// after `limit` layers (D-127: the tick passes `FLOOD_LAYERS`); a goblin not touched by then is
/// unreachable for the tick (distance 0) and holds its position.
///
/// # Arguments
/// * `free` - Walkable interior tiles, not occupied at the start of the tick, adventurer excluded
/// * `start` - The adventurer's tile
/// * `goblins` - The tiles of the awake goblins, in ascending id order (at most 8)
/// * `limit` - The most layers (distances) computed; `UNLIMITED` runs to the end of the frontier
/// # Returns
/// * The layers, and the distance of each goblin packed one byte each (0: unreachable)
pub fn flood(free: felt252, start: u8, goblins: Span<u8>, limit: felt252) -> (Span<u256>, felt252) {
    let mut targets: felt252 = 0;
    for goblin in goblins {
        targets += pow(*goblin);
    }
    let first = pow(start);
    let mut layers: Array<u256> = array![first.into()];
    let mut felt = first;
    let frontier: u256 = first.into();
    let mut low = frontier.low;
    let mut high = frontier.high;
    let free_wide: u256 = free.into();
    let mut free_low = free_wide.low;
    let mut free_high = free_wide.high;
    let pending_wide: u256 = targets.into();
    let mut pending_low = pending_wide.low;
    let mut pending_high = pending_wide.high;
    let mut distances: felt252 = 0;
    let mut distance: felt252 = 0;
    while felt != 0 && distance != limit {
        distance += 1;
        let (next_low, next_high) = dilate(low, high, felt);
        // [Compute] Next layer, kept even when it is the last: the farthest goblin's fallback
        let (layer_low, _, _) = bitwise(next_low, free_low);
        let (layer_high, _, _) = bitwise(next_high, free_high);
        free_low -= layer_low;
        free_high -= layer_high;
        low = layer_low;
        high = layer_high;
        felt = low.into() + high.into() * TWO_POW_128;
        layers.append(u256 { low, high });
        // [Compute] Goblins touched by this layer are at `distance`
        let (hit_low, _, _) = bitwise(next_low, pending_low);
        let (hit_high, _, _) = bitwise(next_high, pending_high);
        if hit_low != 0 || hit_high != 0 {
            let hits = u256 { low: hit_low, high: hit_high };
            let mut j: usize = 0;
            for goblin in goblins {
                if has(hits, *goblin) {
                    distances += distance * (*BYTE.span()[j]).into();
                }
                j += 1;
            }
            pending_low -= hit_low;
            pending_high -= hit_high;
            if pending_low == 0 && pending_high == 0 {
                break;
            }
        }
    }
    (layers.span(), distances)
}

/// Distance of goblin `j` in a packed distance word.
#[inline(always)]
pub fn distance_of(distances: felt252, j: usize) -> u8 {
    let wide: u256 = distances.into();
    ((wide.low / *BYTE.span()[j]) % 256).try_into().unwrap()
}

/// Lowest set bit of a non-empty board, as a felt.
#[inline(always)]
fn lowest(set: u256) -> felt252 {
    if set.low != 0 {
        let (rest, _, _) = bitwise(set.low, set.low - 1);
        (set.low - rest).into()
    } else {
        let (rest, _, _) = bitwise(set.high, set.high - 1);
        (set.high - rest).into() * TWO_POW_128
    }
}

/// Tile and facing of the neighbour `bit` of `index` (interior); facing in direction order
/// East, NorthEast, NorthWest, West, SouthWest, SouthEast.
#[inline(always)]
fn identify(index: u8, bit: felt252) -> (u8, u8) {
    let power = pow(index);
    let (_, rem) = DivRem::div_rem(index, 30);
    if bit == power * INV_2 {
        return (index - 1, 0);
    }
    if bit == power * 2 {
        return (index + 1, 3);
    }
    if rem < WIDTH {
        // Even row: NE +W-1, NW +W, SW -W, SE -W-1
        if bit == power * UP {
            (index + WIDTH - 1, 1)
        } else if bit == power * UP * 2 {
            (index + WIDTH, 2)
        } else if bit == power * DOWN * 2 {
            (index - WIDTH, 4)
        } else {
            (index - WIDTH - 1, 5)
        }
    } else {
        // Odd row: NE +W, NW +W+1, SW -W+1, SE -W
        if bit == power * UP * 2 {
            (index + WIDTH, 1)
        } else if bit == power * UP * 4 {
            (index + WIDTH + 1, 2)
        } else if bit == power * DOWN * 4 {
            (index + 1 - WIDTH, 4)
        } else {
            (index - WIDTH, 5)
        }
    }
}

/// A goblin's step (docs/needs/hexmap.md point 5, rule (a)): its free neighbour closest to the
/// adventurer, the lowest tile index on ties; if none of the closer layer is free now, a free
/// neighbour of its own layer; else it stays.
///
/// # Arguments
/// * `index` - The goblin's tile, interior, at `distance` >= 2
/// * `distance` - Its distance to the adventurer
/// * `layers` - The flood's layers
/// * `occupied` - The current occupancy (goblins that already moved this tick included)
/// # Returns
/// * The new tile and the facing, `None` if it stays
pub fn step(index: u8, distance: u8, layers: Span<u256>, occupied: u256) -> Option<(u8, u8)> {
    let near: u256 = around(index).into();
    let closer = and(near, *layers[(distance - 1).into()]);
    let blocked = and(closer, occupied);
    let candidates = u256 { low: closer.low - blocked.low, high: closer.high - blocked.high };
    if candidates.low != 0 || candidates.high != 0 {
        return Option::Some(identify(index, lowest(candidates)));
    }
    let depth: u8 = layers.len().try_into().unwrap();
    if distance >= depth {
        return Option::None;
    }
    let same = and(near, *layers[distance.into()]);
    let blocked = and(same, occupied);
    let candidates = u256 { low: same.low - blocked.low, high: same.high - blocked.high };
    if candidates.low != 0 || candidates.high != 0 {
        return Option::Some(identify(index, lowest(candidates)));
    }
    Option::None
}
