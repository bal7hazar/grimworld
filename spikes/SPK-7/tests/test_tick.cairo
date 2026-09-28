//! Item 4 (R-5): a goblin's move updates the occupied bit of the chunk it leaves and of the chunk
//! it enters; the worst-case window assembled from its 4 chunks is the board of boards.py, and the
//! tick on it moves the goblins as the Python model says, some across chunks.

use origami_hexmap::helpers::bits::Bits;
use spk7::boards::{CAPPED_CROSSINGS, CAPPED_GOBLINS, CAPPED_MOVES, CAPPED_TERRAIN};
use spk7::fixtures::{WORST_CX0, WORST_CY0, worst_chunks, worst_goblins, worst_origin};
use spk7::flood::FLOOD_LAYERS;
use spk7::tick::{ChunkOccupancy, apply_moves, move_goblin, world_tick};
use spk7::window::{Layers, assemble_window};

fn empty() -> ChunkOccupancy {
    ChunkOccupancy { cx0: 2, cy0: 3, slots: (0, 0, 0, 0), dirty: 0 }
}

#[test]
#[available_gas(l2_gas: 24556)] // ceil(1.05 × 23386 measured)
fn test_move_within_a_chunk() {
    // Chunk (2, 3) holds global (30..44, 45..59); a goblin at (31, 46) steps West to (32, 46)
    let mut chunks = empty();
    let (from, to) = (Bits::pow(15 * 1 + 1), Bits::pow(15 * 1 + 2));
    chunks.slots = (from, 0, 0, 0);
    assert!(!move_goblin(ref chunks, 31, 46, 32, 46));
    assert!(chunks.slots == (to, 0, 0, 0));
    assert!(chunks.dirty == 1);
}

#[test]
#[available_gas(l2_gas: 33960)] // ceil(1.05 × 32342 measured)
fn test_move_across_chunks() {
    // West across x = 45: chunk (2, 3) to chunk (3, 3), slot 0 to slot 2
    let mut chunks = empty();
    chunks.slots = (Bits::pow(15 * 4 + 14), 0, 0, 0);
    assert!(move_goblin(ref chunks, 44, 49, 45, 49));
    assert!(chunks.slots == (0, 0, Bits::pow(15 * 4), 0));
    assert!(chunks.dirty == 5);
    // North across y = 60: chunk (3, 3) to chunk (3, 4), slot 2 to slot 3
    chunks.dirty = 0;
    chunks.slots = (0, 0, Bits::pow(15 * 14 + 3), 0);
    assert!(move_goblin(ref chunks, 48, 59, 48, 60));
    assert!(chunks.slots == (0, 0, 0, Bits::pow(3)));
    assert!(chunks.dirty == 12);
}

#[test]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
#[should_panic(expected: 'tick: chunk not in window')]
fn test_move_outside_the_window_chunks() {
    let mut chunks = empty();
    move_goblin(ref chunks, 29, 46, 30, 46);
}

#[test]
#[available_gas(l2_gas: 13256359)] // ceil(1.05 × 12625103 measured)
fn test_worst_case_tick_in_memory() {
    let (origin_x, origin_y) = worst_origin();
    let mut layers: Array<Layers> = array![];
    let mut slots: Array<felt252> = array![];
    for (_, _, chunk) in worst_chunks() {
        layers.append(chunk);
        slots.append(chunk.occupied);
    }
    // [Check] The window assembled from the 4 chunks is the board, with the goblins as occupancy
    let window = assemble_window(origin_x, origin_y, layers.span());
    let mut occupied: felt252 = 0;
    for tile in CAPPED_GOBLINS.span() {
        occupied += Bits::pow(*tile);
    }
    assert!(window == Layers { terrain: CAPPED_TERRAIN, occupied });
    // [Check] The tick: every goblin steps where the Python model says
    let goblins = worst_goblins();
    let (next, moves, attacks, after) = world_tick(
        origin_x, origin_y, 112, window, goblins.span(), FLOOD_LAYERS,
    );
    assert!(attacks == 0 && moves.len() == 8);
    let mut expected: felt252 = 0;
    let mut j: usize = 0;
    for to in CAPPED_MOVES.span() {
        expected += Bits::pow(*to);
        let (x, y) = *next[j];
        assert!(x == origin_x + *to % 15 && y == origin_y + *to / 15);
        j += 1;
    }
    assert!(after == expected);
    // [Check] Chunks: the moves cross as boards.py counted, and the occupancy follows
    let mut chunks = ChunkOccupancy {
        cx0: WORST_CX0,
        cy0: WORST_CY0,
        slots: (*slots[0], *slots[1], *slots[2], *slots[3]),
        dirty: 0,
    };
    let crossed = apply_moves(ref chunks, moves.span());
    assert!(crossed == CAPPED_CROSSINGS);
    let (s0, s1, s2, s3) = chunks.slots;
    let moved = assemble_window(
        origin_x,
        origin_y,
        array![
            Layers { terrain: CAPPED_TERRAIN, occupied: s0 }, Layers { terrain: 0, occupied: s1 },
            Layers { terrain: 0, occupied: s2 }, Layers { terrain: 0, occupied: s3 },
        ]
            .span(),
    );
    assert!(moved.occupied == expected);
}
