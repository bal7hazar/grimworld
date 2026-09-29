//! Tests of the logic under test, with their gas budgets (docs/CAIRO.md §2). The benchmarks are
//! the most expensive paths: a damage with every operation, a goblin step that weighs all six
//! neighbours.

use crate::board::{distance, goblin_step};
use crate::damage::damage;
use crate::exec::run;
use crate::table::POW2_FELT;

// Every tile walkable, nothing occupied.
const OPEN: felt252 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

#[test]
#[available_gas(l2_gas: 21767)]
fn damage_equal_strength_and_armor_is_base() {
    assert_eq!(damage(100, 60, 60, 0, 0, 0), 100);
}

#[test]
#[available_gas(l2_gas: 28161)]
fn damage_forty_more_armor_halves() {
    assert_eq!(damage(100, 20, 60, 0, 0, 0), 50);
    assert_eq!(damage(100, 60, 20, 0, 0, 0), 200);
}

#[test]
#[available_gas(l2_gas: 25536)]
fn damage_clamps_to_the_table() {
    // x = -500 clamps to -160: 1/16; x = +500 clamps to +80: 4.
    assert_eq!(damage(160, 0, 500, 0, 0, 0), 10);
    assert_eq!(damage(160, 500, 0, 0, 0, 0), 640);
}

#[test]
#[available_gas(l2_gas: 21767)]
fn damage_penetration_and_bonus() {
    // armor 60 + 20 - 40 = 40 = strength.
    assert_eq!(damage(77, 40, 60, 20, 40, 0), 77);
}

#[test]
#[available_gas(l2_gas: 35007)]
fn damage_modifiers_truncate_toward_zero() {
    // 101 + 101 * 40 / 100 = 101 + 40 = 141; 101 - 101 * 33 / 100 = 101 - 33 = 68 (the floor
    // would be -34, giving 67).
    assert_eq!(damage(101, 60, 60, 0, 0, 40), 141);
    assert_eq!(damage(101, 60, 60, 0, 0, -33), 68);
}

#[test]
#[should_panic]
#[available_gas(l2_gas: 16086)]
fn damage_armor_underflow_panics() {
    damage(100, 60, 10, 0, 11, 0);
}

#[test]
#[should_panic]
#[available_gas(l2_gas: 20486)]
fn damage_product_overflow_panics() {
    // 65535 × 4 × 2^16 does not fit a u32.
    damage(65535, 200, 0, 0, 0, 0);
}

#[test]
#[should_panic]
#[available_gas(l2_gas: 23909)]
fn damage_negative_result_panics() {
    damage(100, 60, 60, 0, 0, -101);
}

#[test]
#[available_gas(l2_gas: 14406)]
fn distance_on_the_window() {
    assert_eq!(distance(0, 0), 0);
    assert_eq!(distance(0, 14), 14);
    // (0, 0) to (0, 15): 15 rows down, 7 columns of drift toward the left edge.
    assert_eq!(distance(0, 225), 15);
    assert_eq!(distance(14, 225), 21);
}

#[test]
// gas: raised, the ring of ADR-0006 §4 is now wall (SPK-4 fix loop 1)
#[available_gas(l2_gas: 67531)]
fn goblin_steps_toward_the_target() {
    // Goblin at (7, 8) = 127, target at (7, 2) = 37: its upper neighbours (6, 7) = 111 and
    // (7, 7) = 112 are both at distance 5; the lowest tile wins.
    let (tile, occupied) = goblin_step(OPEN, 0, 127, 37);
    assert_eq!(distance(127, 37), 6);
    assert_eq!(tile, 111);
    // The goblin's own tile was not marked: the layer wraps modulo the field prime.
    assert_eq!(occupied, 0 - bit(127) + bit(111));
}

fn bit(tile: u32) -> felt252 {
    *POW2_FELT.span()[tile]
}

#[test]
// gas: raised, the ring of ADR-0006 §4 is now wall (SPK-4 fix loop 1)
#[available_gas(l2_gas: 68550)]
fn goblin_avoids_occupied_and_walls() {
    // 111 occupied, 112 a wall: no free neighbour is nearer; the goblin holds.
    let walkable = OPEN - bit(112);
    let occupied = bit(111) + bit(127);
    let (tile, after) = goblin_step(walkable, occupied, 127, 37);
    assert_eq!(tile, 127);
    assert_eq!(after, occupied);
}

#[test]
#[available_gas(l2_gas: 49935)]
fn goblin_on_the_ring_holds() {
    // (14, 0) = 14 is on the ring: not simulated, whatever the target.
    let (tile, after) = goblin_step(OPEN, bit(14), 14, 127);
    assert_eq!(tile, 14);
    assert_eq!(after, bit(14));
}

#[test]
#[available_gas(l2_gas: 66765)]
fn goblin_never_steps_onto_the_ring() {
    // Goblin at (2, 1) = 17, target at (1, 0) = 1: the ring tile (2, 0) = 2 and the interior tile
    // (1, 1) = 16 are both at distance 1; the ring is wall, so 16, though 2 is the lower tile.
    let (tile, _) = goblin_step(OPEN, bit(17), 17, 1);
    assert_eq!(tile, 16);
}

#[test]
// gas: raised, the ring of ADR-0006 §4 is now wall (SPK-4 fix loop 1)
#[available_gas(l2_gas: 19103)]
fn goblin_next_to_the_target_holds() {
    let (tile, _) = goblin_step(OPEN, 0, 127, 128);
    assert_eq!(tile, 127);
}

#[test]
#[should_panic(expected: 'board: tile outside window')]
#[available_gas(l2_gas: 16296)]
fn goblin_outside_the_window_panics() {
    goblin_step(OPEN, 0, 240, 0);
}

/// Benchmark: a damage with every operation (bonus, penetration, a negative modifier).
#[test]
#[available_gas(l2_gas: 25190)]
fn bench_damage() {
    // armor 120 + 40 − 30 = 130, x = 20, factor round(2^0.5 × 2^16) = 92682:
    // 1999 × 92682 / 2^16 = 2827, then 2827 + trunc(2827 × −33 / 100) = 2827 − 932.
    assert_eq!(damage(1999, 150, 120, 40, 30, -33), 1895);
}

/// Benchmark: a goblin step that weighs all six neighbours, all free, and moves.
#[test]
// gas: raised, the ring of ADR-0006 §4 is now wall (SPK-4 fix loop 1)
#[available_gas(l2_gas: 65778)]
fn bench_goblin_step() {
    let (tile, _) = goblin_step(OPEN, bit(127), 127, 37);
    assert_eq!(tile, 111);
}

#[test]
#[available_gas(l2_gas: 34052)]
fn exec_decodes_a_damage_case() {
    let r = run(array![0, 101, 60, 60, 0, 0, -33].span());
    assert_eq!(r, array![68]);
}

#[test]
#[should_panic(expected: 'exec: empty case')]
#[available_gas(l2_gas: 16296)]
fn exec_rejects_an_empty_case() {
    run(array![].span());
}

#[test]
#[should_panic]
#[available_gas(l2_gas: 17766)]
fn exec_rejects_an_argument_outside_its_type() {
    run(array![0, 65536, 60, 60, 0, 0, 0].span());
}
