//! Algorithms alone, in memory, on the worst cases: what the computation costs without storage.
//! Each measured test has a baseline that builds the same inputs without the call; the cost of
//! the call is the difference of the two tests' L2 gas (`get_available_gas` differences are not
//! reliable: gas is withdrawn in chunks).

use spk2n::alchemy::{REGION_1_PAIRS, REGION_1_REMAINING, discover};
use spk2n::board::{flood, pow};
use spk2n::fixtures::{COMB, WORST, adventurer, window, worst_goblins};
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
