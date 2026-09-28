//! Benchmarks in memory, on the worst cases: what each function costs without storage. Each has a
//! baseline that builds the same inputs without the call: the call costs the difference of the two
//! tests' L2 gas (docs/research/SPK-7-chunked-maps.md).

use origami_hexmap::helpers::bits::Bits;
use spk7::boards::{CAPPED_GOBLINS, CAPPED_TERRAIN, DEEP_GOBLINS, DEEP_TERRAIN};
use spk7::chunk::{Biome, Side, Sides, generate_chunk};
use spk7::fixtures::{WORST_CX0, WORST_CY0, worst_chunks, worst_goblins, worst_origin};
use spk7::flood::{FLOOD_LAYERS, UNLIMITED, shared_flood};
use spk7::sight::line_of_sight;
use spk7::tick::{ChunkOccupancy, apply_moves, move_goblin, world_tick};
use spk7::window::{Layers, assemble_window};
use super::helpers::random_bits;

// --- Assembly (N-3)
// -------------------------------------------------------------------------------

fn four_chunks() -> (u8, u8, Array<Layers>) {
    let (origin_x, origin_y) = worst_origin();
    let mut layers: Array<Layers> = array![];
    for (_, _, chunk) in worst_chunks() {
        layers.append(chunk);
    }
    (origin_x, origin_y, layers)
}

fn two_chunks() -> (u8, u8, Array<Layers>) {
    let (origin_x, origin_y, four) = four_chunks();
    (origin_x - 7, origin_y, array![*four[0], *four[1]])
}

#[test]
#[available_gas(l2_gas: 11515928)] // ceil(1.05 × 10967550 measured)
fn bench_assemble_4_chunks_baseline() {
    let (origin_x, origin_y, chunks) = four_chunks();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 4);
}

#[test]
#[available_gas(l2_gas: 11584949)] // ceil(1.05 × 11033284 measured)
fn bench_assemble_4_chunks() {
    let (origin_x, origin_y, chunks) = four_chunks();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 4);
    let window = assemble_window(origin_x, origin_y, chunks.span());
    assert!(window.terrain == CAPPED_TERRAIN);
}

#[test]
#[available_gas(l2_gas: 11516421)] // ceil(1.05 × 10968020 measured)
fn bench_assemble_2_chunks_baseline() {
    let (origin_x, origin_y, chunks) = two_chunks();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 2);
}

#[test]
#[available_gas(l2_gas: 11553560)] // ceil(1.05 × 11003390 measured)
fn bench_assemble_2_chunks() {
    let (origin_x, origin_y, chunks) = two_chunks();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 2);
    let window = assemble_window(origin_x, origin_y, chunks.span());
    assert!(window.terrain != 0);
}

// --- Shared flood (N-8) on the winding boards
// ---------------------------------------------------------

fn free_of(terrain: felt252, goblins: Span<u8>) -> felt252 {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += Bits::pow(*goblin);
    }
    terrain - occupied - Bits::pow(112)
}

#[test]
#[available_gas(l2_gas: 42420)] // ceil(1.05 × 40400 measured)
fn bench_flood_deep_baseline() {
    let free = free_of(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
}

#[test]
#[available_gas(l2_gas: 374283)] // ceil(1.05 × 356460 measured)
fn bench_flood_deep_10() {
    let free = free_of(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(free, 112, DEEP_GOBLINS.span(), 10);
    assert!(layers.len() == 11);
}

#[test]
#[available_gas(l2_gas: 508746)] // ceil(1.05 × 484520 measured)
fn bench_flood_deep_15() {
    let free = free_of(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(free, 112, DEEP_GOBLINS.span(), FLOOD_LAYERS);
    assert!(layers.len() == 16);
}

#[test]
#[available_gas(l2_gas: 643209)] // ceil(1.05 × 612580 measured)
fn bench_flood_deep_20() {
    let free = free_of(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(free, 112, DEEP_GOBLINS.span(), 20);
    assert!(layers.len() == 21);
}

#[test]
#[available_gas(l2_gas: 2498168)] // ceil(1.05 × 2379207 measured)
fn bench_flood_deep_unlimited() {
    let free = free_of(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(free, 112, DEEP_GOBLINS.span(), UNLIMITED);
    println!("unlimited flood on the deep board: {} layers", layers.len());
    assert!(layers.len() > 21);
}

#[test]
#[available_gas(l2_gas: 42420)] // ceil(1.05 × 40400 measured)
fn bench_flood_capped_baseline() {
    let free = free_of(CAPPED_TERRAIN, CAPPED_GOBLINS.span());
    assert!(free != 0);
}

#[test]
#[available_gas(l2_gas: 691819)] // ceil(1.05 × 658875 measured)
fn bench_flood_capped() {
    let free = free_of(CAPPED_TERRAIN, CAPPED_GOBLINS.span());
    assert!(free != 0);
    let (layers, distances) = shared_flood(free, 112, CAPPED_GOBLINS.span(), FLOOD_LAYERS);
    assert!(layers.len() == 16 && distances != 0);
}

// --- The tick in memory: goblins (N-8 and rule (a)), then the chunks (item 4)
// ---------------------

fn tick_inputs() -> (u8, u8, Array<Layers>, Array<(u8, u8)>, ChunkOccupancy, Layers) {
    let (origin_x, origin_y, chunks) = four_chunks();
    let mut occupied: felt252 = 0;
    for tile in CAPPED_GOBLINS.span() {
        occupied += Bits::pow(*tile);
    }
    let window = Layers { terrain: CAPPED_TERRAIN, occupied };
    let goblins = worst_goblins();
    let occupancy = ChunkOccupancy {
        cx0: WORST_CX0,
        cy0: WORST_CY0,
        slots: (
            (*chunks[0]).occupied,
            (*chunks[1]).occupied,
            (*chunks[2]).occupied,
            (*chunks[3]).occupied,
        ),
        dirty: 0,
    };
    (origin_x, origin_y, chunks, goblins, occupancy, window)
}

#[test]
#[available_gas(l2_gas: 11585049)] // ceil(1.05 × 11033380 measured)
fn bench_tick_baseline() {
    let (origin_x, origin_y, chunks, goblins, occupancy, window) = tick_inputs();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 4 && goblins.len() == 8);
    assert!(occupancy.dirty == 0 && window.terrain != 0);
}

#[test]
#[available_gas(l2_gas: 12776334)] // ceil(1.05 × 12167937 measured)
fn bench_tick_goblins() {
    // The window already assembled: the flood and the 8 steps
    let (origin_x, origin_y, chunks, goblins, occupancy, window) = tick_inputs();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 4 && goblins.len() == 8);
    assert!(occupancy.dirty == 0 && window.terrain != 0);
    let (_, moves, _, _) = world_tick(
        origin_x, origin_y, 112, window, goblins.span(), FLOOD_LAYERS,
    );
    assert!(moves.len() == 8);
}

#[test]
#[available_gas(l2_gas: 13097311)] // ceil(1.05 × 12473629 measured)
fn bench_tick_full() {
    // Assembly, flood, steps, and the chunks' occupied layers updated
    let (origin_x, origin_y, chunks, goblins, occupancy, window) = tick_inputs();
    assert!(origin_x != 0 && origin_y != 0 && chunks.len() == 4 && goblins.len() == 8);
    assert!(occupancy.dirty == 0 && window.terrain != 0);
    let mut occupancy = occupancy;
    let window = assemble_window(origin_x, origin_y, chunks.span());
    let (_, moves, _, _) = world_tick(
        origin_x, origin_y, 112, window, goblins.span(), FLOOD_LAYERS,
    );
    let crossed = apply_moves(ref occupancy, moves.span());
    assert!(moves.len() == 8 && crossed != 0 && occupancy.dirty == 15);
}

#[test]
#[available_gas(l2_gas: 15635)] // ceil(1.05 × 14890 measured)
fn bench_move_goblin_baseline() {
    let chunks = ChunkOccupancy {
        cx0: 2, cy0: 3, slots: (Bits::pow(15 * 4 + 14), 0, 0, 0), dirty: 0,
    };
    assert!(chunks.dirty == 0);
}

#[test]
#[available_gas(l2_gas: 21647)] // ceil(1.05 × 20616 measured)
fn bench_move_goblin_across() {
    let mut chunks = ChunkOccupancy {
        cx0: 2, cy0: 3, slots: (Bits::pow(15 * 4 + 14), 0, 0, 0), dirty: 0,
    };
    assert!(chunks.dirty == 0);
    assert!(move_goblin(ref chunks, 44, 49, 45, 49));
}

// --- Generation (N-1, N-2)
// ---------------------------------------------------------------------------

fn neighbours() -> (felt252, felt252, felt252, felt252) {
    (random_bits(1, 225), random_bits(2, 225), random_bits(3, 225), random_bits(4, 225))
}

fn copied(n: (felt252, felt252, felt252, felt252)) -> Sides {
    let (e, w, s, north) = n;
    Sides {
        east: Side::Copy(e), west: Side::Copy(w), south: Side::Copy(s), north: Side::Copy(north),
    }
}

fn drawn() -> Sides {
    Sides { east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open }
}

#[test]
#[available_gas(l2_gas: 54735)] // ceil(1.05 × 52128 measured)
fn bench_generate_baseline() {
    let n = neighbours();
    let sides = copied(n);
    assert!(sides != drawn());
}

fn bench(biome: Biome, copy: bool) {
    let n = neighbours();
    let sides = copied(n);
    assert!(sides != drawn());
    let sides = if copy {
        sides
    } else {
        drawn()
    };
    let terrain = generate_chunk('BENCH', biome, sides, false);
    assert!(terrain != 0);
}

#[test]
#[available_gas(l2_gas: 477423)] // ceil(1.05 × 454688 measured)
fn bench_generate_meadow_copy() {
    bench(Biome::Meadow, true);
}

#[test]
#[available_gas(l2_gas: 524570)] // ceil(1.05 × 499590 measured)
fn bench_generate_meadow_open() {
    bench(Biome::Meadow, false);
}

#[test]
#[available_gas(l2_gas: 465024)] // ceil(1.05 × 442880 measured)
fn bench_generate_forest_copy() {
    bench(Biome::Forest, true);
}

#[test]
#[available_gas(l2_gas: 505536)] // ceil(1.05 × 481462 measured)
fn bench_generate_forest_open() {
    bench(Biome::Forest, false);
}

#[test]
#[available_gas(l2_gas: 473714)] // ceil(1.05 × 451156 measured)
fn bench_generate_cave_copy() {
    bench(Biome::Cave, true);
}

#[test]
#[available_gas(l2_gas: 514225)] // ceil(1.05 × 489738 measured)
fn bench_generate_cave_open() {
    bench(Biome::Cave, false);
}

#[test]
#[available_gas(l2_gas: 464604)] // ceil(1.05 × 442480 measured)
fn bench_generate_ruin_copy() {
    bench(Biome::Ruin, true);
}

#[test]
#[available_gas(l2_gas: 508434)] // ceil(1.05 × 484222 measured)
fn bench_generate_ruin_open() {
    bench(Biome::Ruin, false);
}

// --- Line of sight (N-5)
// -------------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn bench_line_of_sight_baseline() {
    let terrain = DEEP_TERRAIN;
    assert!(terrain != 0);
}

#[test]
#[available_gas(l2_gas: 24608)] // ceil(1.05 × 23436 measured)
fn bench_line_of_sight() {
    // (7, 7) to a tile 6 away, (13, 7): 5 tiles between
    let terrain = DEEP_TERRAIN;
    assert!(terrain != 0);
    let seen = line_of_sight(112, 118, terrain);
    assert!(seen || !seen);
}

#[test]
#[available_gas(l2_gas: 512841)] // ceil(1.05 × 488420 measured)
fn bench_flood_capped_no_goblins() {
    let free = free_of(CAPPED_TERRAIN, CAPPED_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(free, 112, array![].span(), FLOOD_LAYERS);
    assert!(layers.len() == 16);
}

#[test]
#[available_gas(l2_gas: 517433)] // ceil(1.05 × 492793 measured)
fn bench_flood_capped_one_goblin() {
    let free = free_of(CAPPED_TERRAIN, CAPPED_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = shared_flood(
        free, 112, array![*CAPPED_GOBLINS.span()[2]].span(), FLOOD_LAYERS,
    );
    assert!(layers.len() == 16);
}
