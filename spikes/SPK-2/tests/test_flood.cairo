//! The bit-parallel flood and step against a plain, obviously correct version (docs/CAIRO.md §2,
//! *Oracles*): a scalar queue BFS over coordinates, one tile at a time.

use core::dict::{Felt252Dict, Felt252DictTrait};
use spk2::board::{FLOOD_LAYERS, UNLIMITED, distance_of, flood, has, pow, step};
use spk2::fixtures::{
    CAPPED_GOBLINS, CAPPED_TERRAIN, COMB, DEEP_GOBLINS, DEEP_TERRAIN, MAZE_GOBLINS, MAZE_TERRAIN,
    PILLARS, SEALED_GOBLINS, SEALED_TERRAIN, window,
};

const W: u8 = 15;
const H: u8 = 16;

/// Neighbours of a local tile, written from the direction table of the library's README.
fn neighbours(index: u8) -> Array<u8> {
    let x = index % W;
    let y = index / W;
    let mut out: Array<(u8, u8)> = array![];
    // East and West
    if x > 0 {
        out.append((x - 1, y));
    }
    if x < W - 1 {
        out.append((x + 1, y));
    }
    let (left, right) = if y % 2 == 0 {
        // Even row: North and South neighbours at x - 1 and x
        (x.into() - 1_i16, x.into())
    } else {
        // Odd row: at x and x + 1
        (x.into(), x.into() + 1_i16)
    };
    for dy in array![-1_i16, 1].span() {
        let ny: i16 = y.into() + *dy;
        if ny >= 0 && ny < H.into() {
            for nx in array![left, right].span() {
                if *nx >= 0 && *nx < W.into() {
                    out.append(((*nx).try_into().unwrap(), ny.try_into().unwrap()));
                }
            }
        }
    }
    let mut tiles: Array<u8> = array![];
    for (nx, ny) in out {
        tiles.append(ny * W + nx);
    }
    tiles
}

/// Scalar BFS from `start` over `free`: distance + 1 of every tile reached, 0 elsewhere.
fn reference(free: felt252, start: u8) -> Felt252Dict<u8> {
    let open: u256 = free.into();
    let mut distances: Felt252Dict<u8> = Default::default();
    distances.insert(start.into(), 1);
    let mut queue: Array<u8> = array![start];
    while let Option::Some(current) = queue.pop_front() {
        let next = distances.get(current.into()) + 1;
        for tile in neighbours(current) {
            if has(open, tile) && distances.get(tile.into()) == 0 {
                distances.insert(tile.into(), next);
                queue.append(tile);
            }
        }
    }
    distances
}

/// Distance of a goblin: one more than its closest neighbour, 0 if none is reached.
fn reference_goblin(ref distances: Felt252Dict<u8>, tile: u8) -> u8 {
    let mut best: u8 = 0;
    for neighbour in neighbours(tile) {
        let d = distances.get(neighbour.into());
        if d != 0 && (best == 0 || d < best) {
            best = d;
        }
    }
    best
}

/// Scalar step: the lowest free neighbour at distance `d − 1`, else at `d`, else none.
fn reference_step(
    ref distances: Felt252Dict<u8>, tile: u8, distance: u8, occupied: felt252,
) -> Option<u8> {
    let occupied: u256 = occupied.into();
    for wanted in array![distance - 1, distance].span() {
        let mut best: Option<u8> = Option::None;
        for neighbour in neighbours(tile) {
            // distances hold distance + 1
            if distances.get(neighbour.into()) == *wanted + 1 && !has(occupied, neighbour) {
                best = match best {
                    Option::Some(b) => if neighbour < b {
                        Option::Some(neighbour)
                    } else {
                        Option::Some(b)
                    },
                    Option::None => Option::Some(neighbour),
                };
            }
        }
        if best.is_some() {
            return best;
        }
    }
    Option::None
}

/// Check the flood's layers, the goblins' distances and their steps against the references.
fn check(terrain: felt252, start: u8, goblins: Span<u8>) {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += pow(*goblin);
    }
    let free = terrain - occupied - pow(start);
    // [Check] Full flood (no goblin): every layer equals the tiles at that distance
    let (layers, _) = flood(free, start, array![].span(), UNLIMITED);
    let mut distances = reference(free + pow(start), start);
    let mut index: u8 = 0;
    while index != W * H {
        let d = distances.get(index.into());
        let mut k: u32 = 0;
        while k != layers.len() {
            let expected = d != 0 && (d - 1).into() == k;
            assert!(has(*layers[k], index) == expected, "layer {} tile {}", k, index);
            k += 1;
        }
        index += 1;
    }
    // [Check] Goblins: distances, then steps in ascending order on the current occupancy
    let (layers, packed) = flood(free, start, goblins, UNLIMITED);
    let mut current = occupied;
    let mut j: usize = 0;
    for goblin in goblins {
        let expected = reference_goblin(ref distances, *goblin);
        let got = distance_of(packed, j);
        assert!(got == expected, "goblin {} distance {} expected {}", *goblin, got, expected);
        if got > 1 {
            let expected_step = reference_step(ref distances, *goblin, got, current);
            let got_step = match step(*goblin, got, layers, current.into()) {
                Option::Some((to, _)) => Option::Some(to),
                Option::None => Option::None,
            };
            assert!(got_step == expected_step, "goblin {} step", *goblin);
            if let Option::Some(to) = got_step {
                current = current - pow(*goblin) + pow(to);
            }
        }
        j += 1;
    }
}

/// A pseudo-random board: interior tiles walkable with probability about 3/4, `keep` open.
fn random_board(seed: u64, keep: Span<u8>) -> felt252 {
    let mut state = seed;
    let mut board: felt252 = 0;
    let mut y: u8 = 1;
    while y != H - 1 {
        let mut x: u8 = 1;
        while x != W - 1 {
            state = (state * 1103515245 + 12345) % 0x80000000;
            let tile = y * W + x;
            let mut kept = false;
            for k in keep {
                if *k == tile {
                    kept = true;
                }
            }
            if kept || (state / 0x10000000) % 4 != 0 {
                board += pow(tile);
            }
            x += 1;
        }
        y += 1;
    }
    board
}

#[test]
#[available_gas(l2_gas: 127854991)] // ceil(1.05 × 121766658 measured)
fn test_flood_matches_reference_on_the_fixtures() {
    // Worst-case window: adventurer local (7, 7) = 112, goblins as in fixtures::worst_goblins
    let goblins = array![111_u8, 97, 16, 28, 211, 223, 103, 151];
    check(window(COMB, 13, 14), 112, goblins.span());
    // Queue window at its start
    let goblins = array![110_u8, 126, 96, 141, 81, 140, 80, 34];
    check(window(PILLARS, 13, 14), 112, goblins.span());
}

#[test]
#[available_gas(l2_gas: 398230026)] // ceil(1.05 × 379266691 measured)
fn test_flood_matches_reference_on_random_boards() {
    let mut seed: u64 = 1;
    while seed != 7 {
        // Adventurer on local row 7 (odd global row) and row 8 (even global row)
        let start: u8 = if seed % 2 == 0 {
            112
        } else {
            127
        };
        let goblins = array![16_u8, 28, 47, 100, 131, 170, 200, 223];
        let mut keep = goblins.clone();
        keep.append(start);
        check(random_board(seed, keep.span()), start, goblins.span());
        seed += 1;
    }
}

#[test]
#[available_gas(l2_gas: 3137088)] // ceil(1.05 × 2987702 measured)
fn test_flood_goblin_walled_in_is_unreachable() {
    // Goblin at local (1, 1) = 16 with its 3 interior neighbours walled: distance 0, no step
    let terrain = window(PILLARS, 13, 14) - pow(17) - pow(31) - pow(32);
    let free = terrain - pow(16) - pow(112);
    let (layers, packed) = flood(free, 112, array![16].span(), UNLIMITED);
    assert!(distance_of(packed, 0) == 0);
    assert!(layers.len() > 1);
}

/// Layers of the flood on a board with its goblins, up to `limit` layers.
fn depth_with(terrain: felt252, goblins: Span<u8>, limit: felt252) -> u32 {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += pow(*goblin);
    }
    let (layers, _) = flood(terrain - occupied - pow(112), 112, goblins, limit);
    layers.len()
}

/// Layers of the unlimited flood on a board with its goblins.
fn depth(terrain: felt252, goblins: Span<u8>) -> u32 {
    depth_with(terrain, goblins, UNLIMITED)
}

/// The capped flood (D-127) against the scalar reference: every layer it computes equals the
/// tiles at that distance, it computes at most 15 distances, and a goblin farther than 15 steps
/// is not reached (distance 0: it holds its position).
fn check_capped(terrain: felt252, start: u8, goblins: Span<u8>) {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += pow(*goblin);
    }
    let free = terrain - occupied - pow(start);
    let mut distances = reference(free + pow(start), start);
    let (layers, packed) = flood(free, start, goblins, FLOOD_LAYERS);
    assert!(layers.len() <= 16, "{} layers", layers.len());
    let mut index: u8 = 0;
    while index != W * H {
        let d = distances.get(index.into());
        let mut k: u32 = 0;
        while k != layers.len() {
            let expected = d != 0 && (d - 1).into() == k;
            assert!(has(*layers[k], index) == expected, "layer {} tile {}", k, index);
            k += 1;
        }
        index += 1;
    }
    let mut j: usize = 0;
    for goblin in goblins {
        let unlimited = reference_goblin(ref distances, *goblin);
        let expected = if unlimited <= 15 {
            unlimited
        } else {
            0
        };
        let got = distance_of(packed, j);
        assert!(got == expected, "goblin {} distance {} expected {}", *goblin, got, expected);
        j += 1;
    }
}

#[test]
#[available_gas(l2_gas: 226476584)] // ceil(1.05 × 215691984 measured)
fn test_flood_capped_matches_reference() {
    // Fix loop 2, D-127: the worst case under the cap (all 15 layers, 8 goblins reached), the
    // deepest board (92 layers unlimited), the corridor maze and the part 1 fixture
    check_capped(CAPPED_TERRAIN, 112, CAPPED_GOBLINS.span());
    check_capped(DEEP_TERRAIN, 112, DEEP_GOBLINS.span());
    check_capped(MAZE_TERRAIN, 112, MAZE_GOBLINS.span());
    check_capped(window(COMB, 13, 14), 112, array![111_u8, 97, 16, 28, 211, 223, 103, 151].span());
    assert!(depth_with(CAPPED_TERRAIN, CAPPED_GOBLINS.span(), FLOOD_LAYERS) == 16);
    assert!(depth_with(DEEP_TERRAIN, DEEP_GOBLINS.span(), FLOOD_LAYERS) == 16);
    assert!(depth(CAPPED_TERRAIN, CAPPED_GOBLINS.span()) == 16);
}

#[test]
#[available_gas(l2_gas: 453394693)] // ceil(1.05 × 431804469 measured)
fn test_flood_matches_reference_on_adversarial_boards() {
    // Fix loop 1, C-3: the corridor maze, an unreachable target, the deepest board found; the
    // numbers of layers are adversarial.py's
    check(MAZE_TERRAIN, 112, MAZE_GOBLINS.span());
    check(SEALED_TERRAIN, 112, SEALED_GOBLINS.span());
    check(DEEP_TERRAIN, 112, DEEP_GOBLINS.span());
    assert!(depth(MAZE_TERRAIN, MAZE_GOBLINS.span()) == 45);
    assert!(depth(SEALED_TERRAIN, SEALED_GOBLINS.span()) == 13);
    assert!(depth(DEEP_TERRAIN, DEEP_GOBLINS.span()) == 92);
}
