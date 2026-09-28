//! Algorithms alone, in memory, on the worst cases: what the computation costs without storage.
//! Each measured test has a baseline that builds the same inputs without the call; the cost of
//! the call is the difference of the two tests' L2 gas (`get_available_gas` differences are not
//! reliable: gas is withdrawn in chunks).

use spk2n::alchemy::{REGION_1_PAIRS, REGION_1_REMAINING, discover};
use spk2n::board::{flood, pow};
use spk2n::fixtures::{
    COMB, DEEP, DEEP_GOBLINS, DEEP_TERRAIN, MAZE, MAZE_GOBLINS, MAZE_TERRAIN, SEALED,
    SEALED_GOBLINS, SEALED_TERRAIN, WORST, adventurer, board, window, worst_goblins,
};
use spk2n::models::{Book, Grimoire};
use spk2n::rules::world_tick;

fn book() -> Book {
    Book {
        id: 1,
        ingredients: 10,
        rarities: spk2n::alchemy::REGION_1_RARITIES,
        masks: spk2n::alchemy::REGION_1_MASKS,
        recipes: spk2n::alchemy::REGION_1_RECIPES,
        ingredient: 100,
        potion: 200,
        failed: 300,
    }
}

fn flood_inputs() -> (felt252, Span<u8>) {
    let terrain = window(COMB, 13, 14);
    let goblins = array![111_u8, 97, 16, 28, 211, 223, 103, 151];
    let mut occupied: felt252 = 0;
    for goblin in goblins.span() {
        occupied += pow(*goblin);
    }
    (terrain - occupied - pow(112), goblins.span())
}

#[test]
#[available_gas(l2_gas: 1272936)] // ceil(1.05 × 1212320 measured)
fn bench_flood_baseline() {
    let (free, goblins) = flood_inputs();
    assert!(free != 0 && goblins.len() == 8);
}

#[test]
#[available_gas(l2_gas: 2001660)] // ceil(1.05 × 1906342 measured)
fn bench_flood_worst_case() {
    let (free, goblins) = flood_inputs();
    let (layers, distances) = flood(free, 112, goblins);
    assert!(free != 0 && goblins.len() == 8);
    assert!(layers.len() == 12 && distances != 0);
}

#[test]
#[available_gas(l2_gas: 1268778)] // ceil(1.05 × 1208360 measured)
fn bench_world_tick_baseline() {
    let hero = adventurer(WORST, 1, true);
    let goblins = worst_goblins(WORST);
    let terrain = window(COMB, 13, 14);
    assert!(hero.health != 0 && goblins.len() == 8 && terrain != 0);
}

#[test]
#[available_gas(l2_gas: 2588391)] // ceil(1.05 × 2465134 measured)
fn bench_world_tick_worst_case() {
    let mut hero = adventurer(WORST, 1, true);
    let goblins = worst_goblins(WORST);
    let terrain = window(COMB, 13, 14);
    assert!(hero.health != 0 && goblins.len() == 8 && terrain != 0);
    let (next, hit) = world_tick(ref hero, goblins.span(), terrain, 0);
    assert!(hit && next.len() == 8);
}

// Adversarial boards (fix loop 1, C-3): the flood and the whole world tick, each with a baseline.

fn board_inputs(terrain: felt252, goblins: Span<u8>) -> felt252 {
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        occupied += pow(*goblin);
    }
    terrain - occupied - pow(112)
}

#[test]
#[available_gas(l2_gas: 42420)] // ceil(1.05 × 40400 measured)
fn bench_flood_maze_baseline() {
    let free = board_inputs(MAZE_TERRAIN, MAZE_GOBLINS.span());
    assert!(free != 0);
}

#[test]
#[available_gas(l2_gas: 1333578)] // ceil(1.05 × 1270074 measured)
fn bench_flood_maze() {
    let free = board_inputs(MAZE_TERRAIN, MAZE_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = flood(free, 112, MAZE_GOBLINS.span());
    assert!(layers.len() == 45);
}

#[test]
#[available_gas(l2_gas: 42420)] // ceil(1.05 × 40400 measured)
fn bench_flood_sealed_baseline() {
    let free = board_inputs(SEALED_TERRAIN, SEALED_GOBLINS.span());
    assert!(free != 0);
}

#[test]
#[available_gas(l2_gas: 726019)] // ceil(1.05 × 691446 measured)
fn bench_flood_sealed() {
    let free = board_inputs(SEALED_TERRAIN, SEALED_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = flood(free, 112, SEALED_GOBLINS.span());
    assert!(layers.len() == 13);
}

#[test]
#[available_gas(l2_gas: 42420)] // ceil(1.05 × 40400 measured)
fn bench_flood_deep_baseline() {
    let free = board_inputs(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
}

#[test]
#[available_gas(l2_gas: 2932430)] // ceil(1.05 × 2792790 measured)
fn bench_flood_deep() {
    let free = board_inputs(DEEP_TERRAIN, DEEP_GOBLINS.span());
    assert!(free != 0);
    let (layers, _) = flood(free, 112, DEEP_GOBLINS.span());
    assert!(layers.len() == 92);
}

fn tick_baseline(i: u32) {
    let hero = adventurer(i, 1, true);
    let (terrain, goblins) = board(i);
    assert!(hero.health != 0 && goblins.len() == 8 && terrain != 0);
}

fn tick_on(i: u32) {
    let mut hero = adventurer(i, 1, true);
    let (terrain, goblins) = board(i);
    assert!(hero.health != 0 && goblins.len() == 8 && terrain != 0);
    let (next, _) = world_tick(ref hero, goblins.span(), terrain, 0);
    assert!(next.len() == 8);
}

#[test]
#[available_gas(l2_gas: 84872)] // ceil(1.05 × 80830 measured)
fn bench_world_tick_maze_baseline() {
    tick_baseline(MAZE);
}

#[test]
#[available_gas(l2_gas: 1781789)] // ceil(1.05 × 1696941 measured)
fn bench_world_tick_maze() {
    tick_on(MAZE);
}

#[test]
#[available_gas(l2_gas: 85187)] // ceil(1.05 × 81130 measured)
fn bench_world_tick_sealed_baseline() {
    tick_baseline(SEALED);
}

#[test]
#[available_gas(l2_gas: 1323852)] // ceil(1.05 × 1260811 measured)
fn bench_world_tick_sealed() {
    tick_on(SEALED);
}

#[test]
#[available_gas(l2_gas: 85187)] // ceil(1.05 × 81130 measured)
fn bench_world_tick_deep_baseline() {
    tick_baseline(DEEP);
}

#[test]
#[available_gas(l2_gas: 3525465)] // ceil(1.05 × 3357585 measured)
fn bench_world_tick_deep() {
    tick_on(DEEP);
}

// Discovery of the pair (0, 5), C + U, the same word for both variants. Word 1 finds a recipe
// with both, word 0x2c fails with both (checked in the tests).

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn bench_discover_baseline() {
    let book = book();
    let signed = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_REMAINING };
    let unsigned = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_PAIRS };
    assert!(book.ingredients == 10 && signed.known == 0 && unsigned.known == 0);
}

#[test]
#[available_gas(l2_gas: 77612)] // ceil(1.05 × 73916 measured)
fn bench_discover_signed_found() {
    let book = book();
    let mut grimoire = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_REMAINING };
    assert!(discover(@book, ref grimoire, 0, 5, 1, true).is_some());
}

#[test]
#[available_gas(l2_gas: 36526)] // ceil(1.05 × 34786 measured)
fn bench_discover_unsigned_found() {
    let book = book();
    let mut grimoire = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_PAIRS };
    assert!(discover(@book, ref grimoire, 0, 5, 1, false).is_some());
}

#[test]
#[available_gas(l2_gas: 57683)] // ceil(1.05 × 54936 measured)
fn bench_discover_signed_failed() {
    let book = book();
    let mut grimoire = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_REMAINING };
    assert!(discover(@book, ref grimoire, 0, 5, 0x2c, true).is_none());
}

#[test]
#[available_gas(l2_gas: 29029)] // ceil(1.05 × 27646 measured)
fn bench_discover_unsigned_failed() {
    let book = book();
    let mut grimoire = Grimoire { adventurer: 1, book: 1, known: 0, remaining: REGION_1_PAIRS };
    assert!(discover(@book, ref grimoire, 0, 5, 0x2c, false).is_none());
}
