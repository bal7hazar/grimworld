//! N-8: the shared flood and the steps of rule (a) against a scalar queue BFS, both row parities of
//! the adventurer, capped (D-127) and unlimited; the boards of boards.py and their expected figures.

use core::dict::{Felt252Dict, Felt252DictTrait};
use origami_hexmap::helpers::bits::Bits;
use spk7::boards::{
    CAPPED_DISTANCES, CAPPED_GOBLINS, CAPPED_MOVES, CAPPED_TERRAIN, DEEP_EVEN_LAYERS,
    DEEP_EVEN_TERRAIN, DEEP_GOBLINS, DEEP_LAYERS, DEEP_TERRAIN,
};
use spk7::flood::{FLOOD_LAYERS, UNLIMITED, distance_of, shared_flood, step};
use spk7::tables::WINDOW_INTERIOR;
use super::helpers::{W, has, neighbours, random_bits};

/// Scalar BFS from `start` over `free` (start excluded from it): distance + 1, 0 if not reached.
fn reference(free: felt252, start: u8) -> Felt252Dict<u8> {
    let mut distances: Felt252Dict<u8> = Default::default();
    distances.insert(start.into(), 1);
    let mut queue: Array<u8> = array![start];
    while let Some(current) = queue.pop_front() {
        let next = distances.get(current.into()) + 1;
        for (nx, ny) in neighbours(current % W, current / W, 16, false) {
            let tile = ny * W + nx;
            if has(free, tile) && distances.get(tile.into()) == 0 {
                distances.insert(tile.into(), next);
                queue.append(tile);
            }
        }
    }
    distances
}

/// A goblin's distance: one more than its closest reached neighbour, 0 if none.
fn reference_goblin(ref distances: Felt252Dict<u8>, tile: u8) -> u8 {
    let mut best: u8 = 0;
    for (nx, ny) in neighbours(tile % W, tile / W, 16, false) {
        let d = distances.get((ny * W + nx).into());
        if d != 0 && (best == 0 || d < best) {
            best = d;
        }
    }
    best
}

/// Scalar step: the lowest free neighbour at distance d - 1, else at d, within the layers computed.
fn reference_step(
    ref distances: Felt252Dict<u8>, tile: u8, distance: u8, occupied: felt252, depth: u8,
) -> Option<u8> {
    for wanted in array![distance - 1, distance] {
        if wanted >= depth {
            continue;
        }
        let mut best: Option<u8> = None;
        for (nx, ny) in neighbours(tile % W, tile / W, 16, false) {
            let n = ny * W + nx;
            if distances.get(n.into()) == wanted + 1 && !has(occupied, n) {
                best = match best {
                    Some(b) => if n < b {
                        Some(n)
                    } else {
                        Some(b)
                    },
                    None => Some(n),
                };
            }
        }
        if best.is_some() {
            return best;
        }
    }
    None
}

/// Check every layer, every goblin's distance and step against the references, under `limit`.
/// # Returns
/// * The number of layers (start included) and the steps
fn check(terrain: felt252, start: u8, goblins: Span<u8>, limit: u8) -> (u32, Array<Option<u8>>) {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += Bits::pow(*goblin);
    }
    let free = terrain - occupied - Bits::pow(start);
    let (layers, packed) = shared_flood(free, start, goblins, limit);
    let mut distances = reference(free, start);
    // [Check] Layer k holds exactly the tiles at distance k
    let mut index: u8 = 0;
    while index != 240 {
        let d = distances.get(index.into());
        let mut k: u32 = 0;
        while k != layers.len() {
            let expected = d != 0 && (d - 1).into() == k;
            assert!(Bits::get(*layers[k], index) == expected, "layer {} tile {}", k, index);
            k += 1;
        }
        index += 1;
    }
    assert!(layers.len() <= limit.into() + 1);
    // [Check] Distances (0 beyond the limit), then steps in ascending order on the current occupancy
    let depth: u8 = layers.len().try_into().unwrap();
    let mut current = occupied;
    let mut steps: Array<Option<u8>> = array![];
    let mut j: usize = 0;
    for goblin in goblins {
        let unlimited = reference_goblin(ref distances, *goblin);
        let expected = if unlimited <= limit {
            unlimited
        } else {
            0
        };
        let got = distance_of(packed, j);
        assert!(got == expected, "goblin {} distance {} expected {}", *goblin, got, expected);
        let mut moved: Option<u8> = None;
        if got > 1 {
            let expected_step = reference_step(ref distances, *goblin, got, current, depth);
            moved = step(*goblin, got, layers, current);
            assert!(moved == expected_step, "goblin {} step", *goblin);
            if let Some(to) = moved {
                current = current - Bits::pow(*goblin) + Bits::pow(to);
            }
        }
        steps.append(moved);
        j += 1;
    }
    (layers.len(), steps)
}

fn random_board(seed: felt252, keep: Span<u8>) -> felt252 {
    // Interior tiles walkable with probability 3/4, `keep` open
    let a: u256 = random_bits(seed, 240).into();
    let b: u256 = random_bits(seed + 1, 240).into();
    let interior: u256 = WINDOW_INTERIOR.into();
    let mut board = Bits::to_felt((a | b) & interior);
    for tile in keep {
        if !has(board, *tile) {
            board += Bits::pow(*tile);
        }
    }
    board
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_flood_capped_worst_case_matches_python() {
    // boards.py's capped worst case: 15 layers, 8 goblins reached, every one stepping
    let (depth, steps) = check(CAPPED_TERRAIN, 112, CAPPED_GOBLINS.span(), FLOOD_LAYERS);
    assert!(depth == 16);
    let mut j: usize = 0;
    for expected in CAPPED_MOVES.span() {
        assert!(*steps[j] == Some(*expected));
        j += 1;
    }
    // And the distances boards.py printed
    let mut occupied: felt252 = 0;
    for goblin in CAPPED_GOBLINS.span() {
        occupied += Bits::pow(*goblin);
    }
    let (_, packed) = shared_flood(
        CAPPED_TERRAIN - occupied - Bits::pow(112), 112, CAPPED_GOBLINS.span(), FLOOD_LAYERS,
    );
    let mut j: usize = 0;
    for expected in CAPPED_DISTANCES.span() {
        assert!(distance_of(packed, j) == *expected);
        j += 1;
    }
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_flood_deep_boards_every_limit() {
    // The deepest boards found: every limit agrees with the reference; unlimited runs to the end
    for limit in array![10_u8, 15, 20] {
        let (depth, _) = check(DEEP_TERRAIN, 112, DEEP_GOBLINS.span(), limit);
        assert!(depth == limit.into() + 1);
    }
    let (depth, _) = check(DEEP_TERRAIN, 112, DEEP_GOBLINS.span(), UNLIMITED);
    assert!(depth <= DEEP_LAYERS);
    let (depth, _) = check(DEEP_EVEN_TERRAIN, 127, array![].span(), UNLIMITED);
    assert!(depth == DEEP_EVEN_LAYERS + 1, "{}", depth);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_flood_random_boards_both_parities() {
    let mut seed: felt252 = 1;
    while seed != 7 {
        // Adventurer on local row 7 (odd global row) and 8 (even global row)
        let start: u8 = if seed == 2 || seed == 4 || seed == 6 {
            127
        } else {
            112
        };
        let goblins = array![16_u8, 28, 47, 100, 131, 170, 200, 208];
        let mut keep = goblins.clone();
        keep.append(start);
        let board = random_board(seed, keep.span());
        check(board, start, goblins.span(), UNLIMITED);
        check(board, start, goblins.span(), FLOOD_LAYERS);
        seed += 1;
    }
}
