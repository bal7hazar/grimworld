//! N-8: one flood for many walkers, with extra obstacles (docs/needs/hexmap.md point 5, rule (a);
//! design/02 *Simulation budget*; design/04 *Goblin AI*; D-127).
//!
//! One breadth-first flood from the adventurer on the window, on the occupancy frozen at the start
//! of the tick (the goblins are obstacles), stopped after `limit` layers (the tick passes 15, D-127).
//! Each awake goblin, in ascending id order, steps to its free neighbour one layer closer, lowest
//! tile index on ties, filtered by the occupancy **as it is now**; else to a free neighbour of its
//! own layer; else it holds. A goblin the flood did not reach holds its position.
//!
//! The layer is the library's hex dilation (`origami_hexmap` 1.8.0, `DilationTrait::dilate`) on
//! the window's layout (15 x 16, origin on an even global row). `u256` is the pair of limbs the
//! bitwise builtin works on (docs/CAIRO.md §4, written reason).

use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::{Dilation, DilationTrait};
use crate::tables::{AROUND_EVEN, AROUND_ODD, DOWN, UP, WINDOW_EVEN_HIGH, WINDOW_EVEN_LOW};

/// Depth of the tick's flood (D-127).
pub const FLOOD_LAYERS: u8 = 15;
/// No limit: more layers than the window's interior has tiles (182).
pub const UNLIMITED: u8 = 255;
const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// 256^j: the byte of goblin `j` in the packed distances.
const BYTE: [felt252; 8] = [
    0x1, 0x100, 0x10000, 0x1000000, 0x100000000, 0x10000000000, 0x1000000000000,
    0x100000000000000,
];

/// The flood (N-8).
/// # Arguments
/// * `free` - Walkable interior tiles of the window, minus the occupancy at the start of the tick,
///   minus the adventurer's tile
/// * `start` - The adventurer's local tile
/// * `goblins` - The awake goblins' local tiles, in ascending id order, at most 8
/// * `limit` - The most layers computed (`FLOOD_LAYERS` in the tick, `UNLIMITED` for the oracle)
/// # Returns
/// * The layers (layer `k` holds the tiles at distance `k`, layer 0 the start) and the distance of
///   each goblin, one byte each (0: not reached)
pub fn shared_flood(
    free: felt252, start: u8, goblins: Span<u8>, limit: u8,
) -> (Span<u256>, felt252) {
    let step = Dilation {
        even_low: WINDOW_EVEN_LOW, even_high: WINDOW_EVEN_HIGH, up: UP, down: DOWN,
    };
    // [Compute] The goblins still to reach
    let mut targets: felt252 = 0;
    for goblin in goblins {
        targets += Bits::pow(*goblin);
    }
    let pending: u256 = targets.into();
    let mut pending_low = pending.low;
    let mut pending_high = pending.high;
    let first = Bits::pow(start);
    let frontier: u256 = first.into();
    let mut layers: Array<u256> = array![frontier];
    let mut felt = first;
    let mut low = frontier.low;
    let mut high = frontier.high;
    let free: u256 = free.into();
    let mut free_low = free.low;
    let mut free_high = free.high;
    let mut distances: felt252 = 0;
    let mut distance: u8 = 0;
    // [Compute] At most `limit` layers, and at most 182 (the interior): the frontier runs out first
    while felt != 0 && distance != limit {
        distance += 1;
        let (near_low, near_high) = step.dilate(low, high, felt);
        let (next_low, _, _) = Bits::bitwise(near_low, free_low);
        let (next_high, _, _) = Bits::bitwise(near_high, free_high);
        free_low -= next_low;
        free_high -= next_high;
        low = next_low;
        high = next_high;
        felt = low.into() + high.into() * TWO_POW_128;
        layers.append(u256 { low, high });
        // [Compute] Goblins next to this layer's frontier are at `distance`
        let (hit_low, _, _) = Bits::bitwise(near_low, pending_low);
        let (hit_high, _, _) = Bits::bitwise(near_high, pending_high);
        if hit_low != 0 || hit_high != 0 {
            let hits = u256 { low: hit_low, high: hit_high };
            let mut j: usize = 0;
            for goblin in goblins {
                if Bits::get(hits, *goblin) {
                    distances += distance.into() * *BYTE.span()[j];
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

/// Distance of goblin `j` in the packed distances.
#[inline(always)]
pub fn distance_of(distances: felt252, j: usize) -> u8 {
    let wide: u256 = distances.into();
    let byte: u128 = (*BYTE.span()[j]).try_into().unwrap();
    ((wide.low / byte) % 256).try_into().unwrap()
}

/// The 6 neighbour bits of an interior tile of the window.
#[inline(always)]
pub fn around(index: u8) -> felt252 {
    let (_, rem) = DivRem::div_rem(index, 30);
    if rem < 15 {
        Bits::pow(index) * AROUND_EVEN
    } else {
        Bits::pow(index) * AROUND_ODD
    }
}

/// Lowest set bit of a non-empty set, as a felt.
#[inline(always)]
fn lowest(set: u256) -> felt252 {
    if set.low != 0 {
        let (rest, _, _) = Bits::bitwise(set.low, set.low - 1);
        (set.low - rest).into()
    } else {
        let (rest, _, _) = Bits::bitwise(set.high, set.high - 1);
        (set.high - rest).into() * TWO_POW_128
    }
}

/// The tile of the neighbour bit `bit` of the interior tile `index`.
#[inline(always)]
fn identify(index: u8, bit: felt252) -> u8 {
    let power = Bits::pow(index);
    if bit == power * INV_2 {
        return index - 1;
    }
    if bit == power * 2 {
        return index + 1;
    }
    let (_, rem) = DivRem::div_rem(index, 30);
    if rem < 15 {
        // Even row: +W - 1, +W, -W, -W - 1
        if bit == power * UP {
            index + 14
        } else if bit == power * UP * 2 {
            index + 15
        } else if bit == power * DOWN * 2 {
            index - 15
        } else {
            index - 16
        }
    } else {
        // Odd row: +W, +W + 1, -W + 1, -W
        if bit == power * UP * 2 {
            index + 15
        } else if bit == power * UP * 4 {
            index + 16
        } else if bit == power * DOWN * 4 {
            index - 14
        } else {
            index - 15
        }
    }
}

/// A goblin's step under rule (a).
/// # Arguments
/// * `index` - The goblin's local tile, interior, at `distance >= 2`
/// * `distance` - Its distance to the adventurer
/// * `layers` - The flood's layers
/// * `occupied` - The occupancy now (goblins that moved this tick included)
/// # Returns
/// * The new local tile, `None` if it holds
pub fn step(index: u8, distance: u8, layers: Span<u256>, occupied: u256) -> Option<u8> {
    let near: u256 = around(index).into();
    let closer = Bits::and(near, *layers[(distance - 1).into()]);
    let blocked = Bits::and(closer, occupied);
    let candidates = u256 { low: closer.low - blocked.low, high: closer.high - blocked.high };
    if candidates.low != 0 || candidates.high != 0 {
        return Some(identify(index, lowest(candidates)));
    }
    if distance.into() >= layers.len() {
        return None;
    }
    let same = Bits::and(near, *layers[distance.into()]);
    let blocked = Bits::and(same, occupied);
    let candidates = u256 { low: same.low - blocked.low, high: same.high - blocked.high };
    if candidates.low != 0 || candidates.high != 0 {
        return Some(identify(index, lowest(candidates)));
    }
    None
}
