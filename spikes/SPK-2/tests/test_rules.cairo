//! The rules in memory, without the world.

use spk2::fixtures::{PILLARS, QUEUE, adventurer, queue_goblins, window};
use spk2::rules::{damage, hex_distance, neighbour, window_origin, world_tick};

#[test]
#[available_gas(l2_gas: 28009378)] // ceil(1.05 × 26675598 measured)
fn test_queue_scenario_in_memory() {
    let mut hero = adventurer(QUEUE, 1, false);
    let mut goblins = queue_goblins(QUEUE);
    let mut clock: u32 = 0;
    while clock != 10 {
        let (x, y) = neighbour(hero.x, hero.y, 3);
        hero.x = x;
        hero.y = y;
        let (ox, oy, _) = window_origin(x, y);
        let (next, hit) = world_tick(ref hero, goblins.span(), window(PILLARS, ox, oy), clock);
        goblins = next;
        assert!(!hit, "tick {} hit", clock);
        // Every goblin keeps up: awake (inside the window's interior), never adjacent
        for g in goblins.span() {
            let d = hex_distance(hero.x, hero.y, *g.x, *g.y);
            assert!(d >= 2, "tick {} goblin {} adjacent", clock, *g.id);
            assert!(
                *g.x > ox && *g.x - ox <= 13 && *g.y > oy && *g.y - oy <= 14,
                "tick {} goblin {} left the window",
                clock,
                *g.id,
            );
        }
        clock += 1;
    }
}

#[test]
#[available_gas(l2_gas: 35406)] // ceil(1.05 × 33720 measured)
fn test_damage_table() {
    // 2^(0/40) = 1: base damage; +40 strength doubles it; -40 halves it; clamped at -160 and +80
    assert!(damage(18, 60, 60) == 18);
    assert!(damage(18, 100, 60) == 36);
    assert!(damage(18, 60, 100) == 9);
    assert!(damage(16, 0, 200) == 1);
    assert!(damage(16, 0, 250) == 1);
    assert!(damage(16, 200, 0) == 64);
}

#[test]
#[available_gas(l2_gas: 14721)] // ceil(1.05 × 14020 measured)
fn test_hex_distance() {
    assert!(hex_distance(20, 21, 19, 21) == 1);
    assert!(hex_distance(20, 21, 20, 20) == 1);
    assert!(hex_distance(20, 21, 21, 20) == 1);
    assert!(hex_distance(20, 21, 18, 20) == 3);
    assert!(hex_distance(20, 21, 17, 19) == 4);
    assert!(hex_distance(20, 21, 17, 23) == 4);
}
