//! The measured entrypoints on a deployed contract: the worst-case tick with the window assembled at
//! each tick (A, D-120) and with a stored window (B, rejected, for comparison), waiting and moving;
//! reveals of 1 and 3 chunks per biome. Each measured test has a setup-only baseline.

use origami_hexmap::helpers::bits::Bits;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use spk7::boards::{CAPPED_MOVES, CAPPED_TERRAIN};
use spk7::contract::{IMapDispatcher, IMapDispatcherTrait, STAY};
use spk7::fixtures::{REVEAL_CHUNKS, worst_adventurer, worst_origin};
use spk7::tables::{COL_EAST, COL_WEST, ROW_NORTH, ROW_SOUTH};
use spk7::window::Layers;
use super::helpers::has;

/// East: from the tile West of the worst-case tile onto it.
const EAST: u8 = 0;

fn deploy() -> IMapDispatcher {
    let class = declare("Instances").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IMapDispatcher { contract_address: address }
}

/// The goblins after the worst-case tick, from boards.py.
fn expected_goblins() -> Array<(u8, u8)> {
    let (ox, oy) = worst_origin();
    let mut out = array![];
    for to in CAPPED_MOVES.span() {
        out.append((ox + *to % 15, oy + *to / 15));
    }
    out
}

/// The window's occupancy after the tick, and the chunks agree with it.
fn check_after(map: IMapDispatcher, instance: u32) {
    assert!(map.goblins(instance) == expected_goblins());
    assert!(map.adventurer(instance) == worst_adventurer());
    let mut expected: felt252 = 0;
    for to in CAPPED_MOVES.span() {
        expected += Bits::pow(*to);
    }
    // Chunks (2, 3), (2, 4), (3, 3), (3, 4) hold the goblins at their new tiles
    let (ox, oy) = worst_origin();
    let mut found: felt252 = 0;
    for (cx, cy) in array![(2_u8, 3_u8), (2, 4), (3, 3), (3, 4)] {
        let layers = map.chunk(instance, cx, cy);
        let mut tile: u8 = 0;
        while tile != 225 {
            if has(layers.occupied, tile) {
                let (x, y) = (cx * 15 + tile % 15, cy * 15 + tile / 15);
                found += Bits::pow((y - oy) * 15 + (x - ox));
            }
            tile += 1;
        }
    }
    assert!(found == expected);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_setup_baseline() {
    let map = deploy();
    map.setup_worst_case(1, false, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_worst_case_wait() {
    let map = deploy();
    map.setup_worst_case(1, false, false);
    map.act(1, STAY);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_worst_case_move() {
    let map = deploy();
    map.setup_worst_case(1, true, false);
    map.act(1, EAST);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_stored_setup_baseline() {
    let map = deploy();
    map.setup_worst_case(1, false, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_stored_worst_case_wait() {
    let map = deploy();
    map.setup_worst_case(1, false, true);
    map.act_stored(1, STAY);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_stored_worst_case_move() {
    let map = deploy();
    map.setup_worst_case(1, true, true);
    map.act_stored(1, EAST);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_act_every_variant_moves_the_goblins() {
    // A and B, waiting and moving: the same goblins, chunks and window afterwards
    let map = deploy();
    map.setup_worst_case(1, false, false);
    map.setup_worst_case(2, true, false);
    map.setup_worst_case(3, false, true);
    map.setup_worst_case(4, true, true);
    map.act(1, STAY);
    map.act(2, EAST);
    map.act_stored(3, STAY);
    map.act_stored(4, EAST);
    let (ox, oy) = worst_origin();
    for instance in array![1_u32, 2, 3, 4] {
        check_after(map, instance);
    }
    // B: the stored window is the one at the adventurer, written back
    for instance in array![3_u32, 4] {
        let (origin, window) = map.stored_window(instance);
        assert!(origin == ox.into() + oy.into() * 256);
        assert!(window.terrain == CAPPED_TERRAIN);
        let mut expected: felt252 = 0;
        for to in CAPPED_MOVES.span() {
            expected += Bits::pow(*to);
        }
        assert!(window.occupied == expected);
    }
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'move: tile blocked')]
fn test_act_refuses_a_blocked_tile() {
    // West of the goblin on local (5, 8) of the worst window, global (42, 60): stepping East
    // onto it is refused
    let map = deploy();
    map.setup_worst_case(1, false, false);
    assert!(map.goblins(1).span()[4] == @(42, 60));
    map.setup_adventurer(1, 43, 60);
    map.act(1, EAST);
}

// --- Reveal -----------------------------------------------------------------------------------------

/// Reveal the L (3 chunks) or its chunk A alone, after the setup case.
fn reveal(biome: u8, case: u8, three: bool) -> (IMapDispatcher, Array<(u8, u8)>) {
    let map = deploy();
    map.setup_reveal(1, biome, case);
    let chunks = if three {
        array![*REVEAL_CHUNKS.span()[0], *REVEAL_CHUNKS.span()[1], *REVEAL_CHUNKS.span()[2]]
    } else {
        array![*REVEAL_CHUNKS.span()[0]]
    };
    map.reveal(1, chunks.clone());
    (map, chunks)
}

fn cut(value: felt252, mask: felt252) -> felt252 {
    let a: u256 = value.into();
    let b: u256 = mask.into();
    Bits::to_felt(a & b)
}

/// Seams: every chunk revealed by the call agrees with its 4 neighbours when they are known.
fn check_seams(map: IMapDispatcher, revealed: Span<(u8, u8)>) {
    for (cx, cy) in revealed {
        let (cx, cy) = (*cx, *cy);
        let me = map.chunk(1, cx, cy).terrain;
        assert!(me != 0);
        let west = map.chunk(1, cx + 1, cy).terrain;
        let east = map.chunk(1, cx - 1, cy).terrain;
        let north = map.chunk(1, cx, cy + 1).terrain;
        let south = map.chunk(1, cx, cy - 1).terrain;
        if west != 0 {
            assert!(cut(me, COL_WEST) == cut(west, COL_EAST) * Bits::pow(14));
        }
        if east != 0 {
            assert!(cut(me, COL_EAST) * Bits::pow(14) == cut(east, COL_WEST));
        }
        if north != 0 {
            assert!(cut(me, ROW_NORTH) == cut(north, ROW_SOUTH) * Bits::pow(210));
        }
        if south != 0 {
            assert!(cut(me, ROW_SOUTH) * Bits::pow(210) == cut(south, ROW_NORTH));
        }
    }
}

fn baseline(biome: u8, case: u8) {
    let map = deploy();
    map.setup_reveal(1, biome, case);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_baseline_open() {
    baseline(2, 0);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_baseline_around() {
    baseline(2, 1);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_baseline_known() {
    baseline(2, 2);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_open_meadow() {
    reveal(0, 0, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_open_forest() {
    reveal(1, 0, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_open_cave() {
    reveal(2, 0, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_open_ruin() {
    reveal(3, 0, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_known_meadow() {
    reveal(0, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_known_forest() {
    reveal(1, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_known_cave() {
    reveal(2, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_one_known_ruin() {
    reveal(3, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_open_meadow() {
    reveal(0, 0, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_open_forest() {
    reveal(1, 0, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_open_cave() {
    reveal(2, 0, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_open_ruin() {
    reveal(3, 0, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_around_meadow() {
    reveal(0, 1, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_around_forest() {
    reveal(1, 1, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_around_cave() {
    reveal(2, 1, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_three_around_ruin() {
    reveal(3, 1, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'reveal: chunk already revealed')]
fn test_reveal_refuses_a_known_chunk() {
    let map = deploy();
    map.setup_reveal(1, 2, 2);
    map.reveal(1, array![(3, 2)]);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'reveal: more than 3 chunks')]
fn test_reveal_refuses_four_chunks() {
    let map = deploy();
    map.setup_reveal(1, 2, 0);
    map.reveal(1, array![(0, 0), (1, 0), (0, 1), (1, 1)]);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_window_view_is_layers() {
    let map = deploy();
    map.setup_worst_case(1, false, true);
    let (_, window) = map.stored_window(1);
    assert!(window != Layers { terrain: 0, occupied: 0 });
}

fn check_reveals(biome: u8) {
    for (case, three) in array![(0_u8, false), (2, false), (0, true), (1, true)] {
        let (map, chunks) = reveal(biome, case, three);
        check_seams(map, chunks.span());
    }
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_seams_meadow() {
    check_reveals(0);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_seams_forest() {
    check_reveals(1);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_seams_cave() {
    check_reveals(2);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_reveal_seams_ruin() {
    check_reveals(3);
}
