//! The part of a tick SPK-7 measures, in memory: the goblins of the window act on one shared flood
//! (N-8) and their moves update the occupied layers of the chunks (R-5, ADR-0006 §4: "moving writes
//! the occupied bit of the chunk left and of the chunk entered"). Combat, conditions and the
//! adventurer's own action are SPK-2's: a goblin at distance 1 only counts as an attack here.

use origami_hexmap::helpers::bits::Bits;
use crate::flood::{distance_of, shared_flood, step};
use crate::window::{Layers, WIDTH};

/// Most awake goblins (design/02 *Simulation budget*).
pub const MAX_AWAKE: u32 = 8;

pub mod errors {
    pub const TICK_TOO_MANY: felt252 = 'tick: too many goblins';
    pub const TICK_OUTSIDE: felt252 = 'tick: chunk not in window';
}

/// A goblin's move, in global coordinates.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Move {
    pub goblin: u32,
    pub from_x: u8,
    pub from_y: u8,
    pub to_x: u8,
    pub to_y: u8,
}

/// The occupied layers of the (up to) 4 chunks under the window, in the order of
/// `window::assemble_window`: slot `2 (cx - cx0) + (cy - cy0)`. `dirty` has bit `k` set when slot
/// `k` changed and must be written.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct ChunkOccupancy {
    pub cx0: u8,
    pub cy0: u8,
    pub slots: (felt252, felt252, felt252, felt252),
    pub dirty: u8,
}

/// The slot of the chunk holding a global tile, and the tile's bit in it.
#[inline(always)]
pub fn locate(cx0: u8, cy0: u8, x: u8, y: u8) -> (u8, felt252) {
    let (cx, lx) = DivRem::div_rem(x, WIDTH.try_into().unwrap());
    let (cy, ly) = DivRem::div_rem(y, WIDTH.try_into().unwrap());
    assert(cx >= cx0 && cy >= cy0 && cx - cx0 < 2 && cy - cy0 < 2, errors::TICK_OUTSIDE);
    (2 * (cx - cx0) + (cy - cy0), Bits::pow(WIDTH * ly + lx))
}

#[inline(always)]
fn add(ref chunks: ChunkOccupancy, slot: u8, value: felt252) {
    let (s0, s1, s2, s3) = chunks.slots;
    chunks
        .slots =
            match slot {
                0 => (s0 + value, s1, s2, s3),
                1 => (s0, s1 + value, s2, s3),
                2 => (s0, s1, s2 + value, s3),
                _ => (s0, s1, s2, s3 + value),
            };
    let flag: u8 = match slot {
        0 => 1,
        1 => 2,
        2 => 4,
        _ => 8,
    };
    chunks.dirty = chunks.dirty | flag;
}

/// Item 4: a goblin's move updates the occupied bit of the chunk it leaves and of the chunk it
/// enters, the same chunk or two.
/// # Returns
/// * Whether the move crossed from one chunk to another
pub fn move_goblin(ref chunks: ChunkOccupancy, from_x: u8, from_y: u8, to_x: u8, to_y: u8) -> bool {
    let (from, from_bit) = locate(chunks.cx0, chunks.cy0, from_x, from_y);
    let (to, to_bit) = locate(chunks.cx0, chunks.cy0, to_x, to_y);
    add(ref chunks, from, -from_bit);
    add(ref chunks, to, to_bit);
    from != to
}

/// The goblins act on the window (rule (a), D-127).
/// # Arguments
/// * `origin_x`, `origin_y` - The window's origin
/// * `centre` - The adventurer's local tile
/// * `window` - The assembled window (terrain with its ring as wall, occupancy)
/// * `goblins` - Global tiles of the instance's goblins, ascending id; those in the window's
///   interior are awake (at most 8)
/// * `limit` - Depth of the flood
/// # Returns
/// * The goblins' tiles after the tick, their moves, the number of goblins adjacent (attacks), and
///   the window's occupancy after the tick
pub fn world_tick(
    origin_x: u8, origin_y: u8, centre: u8, window: Layers, goblins: Span<(u8, u8)>, limit: u8,
) -> (Array<(u8, u8)>, Array<Move>, u8, felt252) {
    // [Compute] Awake goblins: those in the window's interior
    let mut tiles: Array<u8> = array![];
    for (x, y) in goblins {
        if let Some(tile) = local(origin_x, origin_y, *x, *y) {
            tiles.append(tile);
        }
    }
    assert(tiles.len() <= MAX_AWAKE, errors::TICK_TOO_MANY);
    let tiles = tiles.span();
    // [Compute] One flood from the adventurer on the occupancy frozen now
    let terrain: u256 = window.terrain.into();
    let occupied: u256 = window.occupied.into();
    let busy = Bits::and(terrain, occupied);
    let free = window.terrain - Bits::to_felt(busy) - Bits::pow(centre);
    let (layers, distances) = if tiles.len() == 0 {
        (array![].span(), 0)
    } else {
        shared_flood(free, centre, tiles, limit)
    };
    // [Compute] Goblins act in ascending id order, on the occupancy as it is now
    let mut current = window.occupied;
    let mut next: Array<(u8, u8)> = array![];
    let mut moves: Array<Move> = array![];
    let mut attacks: u8 = 0;
    let mut awake: usize = 0;
    let mut id: u32 = 0;
    for (x, y) in goblins {
        let (x, y) = (*x, *y);
        id += 1;
        let mut position = (x, y);
        if let Some(tile) = local(origin_x, origin_y, x, y) {
            let distance = distance_of(distances, awake);
            awake += 1;
            if distance == 1 {
                attacks += 1;
            } else if distance > 1 {
                if let Some(to) = step(tile, distance, layers, current.into()) {
                    current = current - Bits::pow(tile) + Bits::pow(to);
                    let (ly, lx) = DivRem::div_rem(to, WIDTH.try_into().unwrap());
                    let (to_x, to_y) = (origin_x + lx, origin_y + ly);
                    moves.append(Move { goblin: id, from_x: x, from_y: y, to_x, to_y });
                    position = (to_x, to_y);
                }
            }
        }
        next.append(position);
    }
    (next, moves, attacks, current)
}

/// Local tile of a global tile if it lies in the window's interior.
#[inline(always)]
fn local(origin_x: u8, origin_y: u8, x: u8, y: u8) -> Option<u8> {
    if x <= origin_x || y <= origin_y {
        return None;
    }
    let lx = x - origin_x;
    let ly = y - origin_y;
    if lx > 13 || ly > 14 {
        return None;
    }
    Some(ly * WIDTH + lx)
}

/// Apply the moves of a tick to the chunks' occupied layers (item 4).
/// # Returns
/// * The number of moves that crossed from one chunk to another
pub fn apply_moves(ref chunks: ChunkOccupancy, moves: Span<Move>) -> u8 {
    let mut crossed: u8 = 0;
    for m in moves {
        if move_goblin(ref chunks, *m.from_x, *m.from_y, *m.to_x, *m.to_y) {
            crossed += 1;
        }
    }
    crossed
}
