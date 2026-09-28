//! The measured states, written by the `setup` system for both snforge and Katana, so that the
//! two measure the same thing. Setup cost is not measured.

use crate::board::pow;
use crate::models::{Goblin, InstanceAdventurer};
use crate::tables::WIDTH;

/// Instances of the worst-case tick (goblin models, and the packed variant) and of the queues of
/// 10, 5 and 1 moves: each measured transaction starts from a fresh copy of its fixture.
pub const WORST: u32 = 1;
pub const WORST_PACKED: u32 = 5;
pub const QUEUE: u32 = 2;
pub const QUEUE_5: u32 = 3;
pub const QUEUE_1: u32 = 4;
/// A queue of 10 moves with no goblin: plain exploration.
pub const QUEUE_EMPTY: u32 = 6;
/// Terrains: walls in rows `y ≡ 2 (mod 4)` with a gap every 6 columns (a comb that forces
/// detours), or pillars at `x ≡ 0 (mod 4)` on those rows.
pub const COMB: u8 = 0;
pub const PILLARS: u8 = 1;

// Adversarial cases (fix loop 1, C-3), generated and checked by `adversarial.py`.

/// Instances of the tick on adversarial windows, and of the expensive valid queue.
pub const MAZE: u32 = 11;
pub const SEALED: u32 = 12;
pub const DEEP: u32 = 13;
pub const SERPENT: u32 = 14;
/// The auditor's corridor maze: 45 layers (goblin 2 at distance 44, goblins 3 to 8 unreachable).
pub const MAZE_TERRAIN: felt252 = 0xfff9fff00027ffc8001fff00027ffc8001fff00027ffc8001fff0000;
pub const MAZE_GOBLINS: [u8; 8] = [111, 16, 211, 213, 215, 217, 219, 221];
/// An unreachable target: the comb of the worst-case fixture, goblin 8 walled in: 13 layers
/// (the frontier is exhausted).
pub const SEALED_TERRAIN: felt252 = 0xfff9fff01047ff8ffe9ffe01047ffcfff9fff01047ffcfff9fff0000;
pub const SEALED_GOBLINS: [u8; 8] = [111, 97, 16, 28, 211, 223, 103, 151];
/// The deepest valid board found by the hill climb of `adversarial.py` (eccentricity 93 from the
/// adventurer, goblin 1 adjacent): 92 layers with its 8 goblins, one of them 91 steps away.
pub const DEEP_TERRAIN: felt252 = 0xedb136d300207dcd0c16e3227a5f04f5f00a03d7e4604c3697db0000;
pub const DEEP_GOBLINS: [u8; 8] = [113, 28, 61, 100, 101, 192, 193, 208];
/// Global terrain of the expensive queue: corridors on odd rows, walls on even rows with one gap
/// every 14 columns, alternating sides (a serpentine), and two sealed pockets on row 28.
pub const SERPENTINE: u8 = 2;
/// The adventurer of both instances stands at global (20, 21): window origin (13, 14), local
/// (7, 7).
pub const START_X: u8 = 20;
pub const START_Y: u8 = 21;
/// The queue moves West 10 times: window origins x = 13 to 23.
pub const QUEUE_LENGTH: u8 = 10;
pub const WEST: u8 = 3;

/// Whether a global tile is walkable.
pub fn walkable(kind: u8, x: u8, y: u8) -> bool {
    if kind == SERPENTINE {
        // Two pockets on row 28, sealed by row 27 below them and walls beside them
        if y == 28 && (x == 24 || x == 26) {
            return true;
        }
        if y == 27 && x >= 23 && x <= 26 {
            return false;
        }
        if y % 2 == 1 {
            return true;
        }
        let gap = if (y / 2) % 2 == 0 {
            0
        } else {
            7
        };
        return x % 14 == gap;
    }
    if y % 4 != 2 {
        return true;
    }
    if kind == COMB {
        x % 6 == 3
    } else {
        x % 4 != 0
    }
}

/// The terrain of the 15 × 16 window at an origin, ring as wall: what the assembly from chunks
/// would return (SPK-7). Loops over tiles: setup only.
pub fn window(kind: u8, origin_x: u8, origin_y: u8) -> felt252 {
    let mut terrain: felt252 = 0;
    let mut ly: u8 = 1;
    while ly != 15 {
        let mut lx: u8 = 1;
        while lx != 14 {
            if walkable(kind, origin_x + lx, origin_y + ly) {
                terrain += pow(ly * WIDTH + lx);
            }
            lx += 1;
        }
        ly += 1;
    }
    terrain
}

/// The adventurer of a fixture: a level-20 Vanguard with a sword (design/03, design/04).
pub fn adventurer(instance_id: u32, adventurer: u32, conditions: bool) -> InstanceAdventurer {
    let until = if conditions {
        20
    } else {
        0
    };
    InstanceAdventurer {
        instance_id,
        adventurer,
        x: START_X,
        y: START_Y,
        facing: 0,
        health: 480,
        max_health: 480,
        energy: 60,
        max_energy: 75,
        armor: 80,
        strength: 60,
        damage: 18,
        regeneration: 2,
        energy_regeneration: 3,
        bleeding: until,
        poison: until,
        burning: 0,
    }
}

fn goblin(instance_id: u32, id: u32, x: u8, y: u8, burning: u32) -> Goblin {
    Goblin {
        instance_id,
        id,
        x,
        y,
        facing: 0,
        health: 200,
        armor: 60,
        strength: 40,
        damage: 17,
        regeneration: 0,
        bleeding: 0,
        poison: 0,
        burning,
    }
}

/// Worst-case tick: 2 goblins adjacent (they attack), 6 at the far corners and sides of the
/// window, behind the comb's walls (the flood runs to its deepest layer); all burning.
pub fn worst_goblins(i: u32) -> Array<Goblin> {
    array![
        goblin(i, 1, 19, 21, 20), // East of the adventurer
        goblin(i, 2, 20, 20, 20), // South-East
        goblin(i, 3, 14, 15, 20), // local (1, 1)
        goblin(i, 4, 26, 15, 20), // local (13, 1)
        goblin(i, 5, 14, 28, 20), // local (1, 14)
        goblin(i, 6, 26, 28, 20), // local (13, 14)
        goblin(i, 7, 26, 20, 20), // local (13, 6)
        goblin(i, 8, 14, 24, 20) // local (1, 10)
    ]
}

/// Terrain and goblins of an adversarial tick; the window's origin is (13, 14), goblins at
/// global (13 + x, 14 + y) of their local tile, all burning as in the worst-case fixture.
pub fn board(i: u32) -> (felt252, Array<Goblin>) {
    let (terrain, tiles) = if i == MAZE {
        (MAZE_TERRAIN, MAZE_GOBLINS.span())
    } else if i == SEALED {
        (SEALED_TERRAIN, SEALED_GOBLINS.span())
    } else {
        (DEEP_TERRAIN, DEEP_GOBLINS.span())
    };
    let mut goblins: Array<Goblin> = array![];
    let mut id: u32 = 1;
    for tile in tiles {
        goblins.append(goblin(i, id, 13 + *tile % WIDTH, 14 + *tile / WIDTH, 20));
        id += 1;
    }
    (terrain, goblins)
}

/// The expensive valid queue (serpentine terrain): goblin 1 follows 2 tiles behind; goblins 2 to
/// 5, behind it in the one-tile corridor, are walled off by it (rule (a)) and fall behind; goblins
/// 6 and 7 sit in sealed pockets 7 rows away, never in sight, awake for the 10 ticks. With a goblin
/// unreachable, every tick's flood runs until the frontier is exhausted.
pub fn serpent_goblins(i: u32) -> Array<Goblin> {
    array![
        goblin(i, 1, 18, 21, 0), goblin(i, 2, 17, 21, 0), goblin(i, 3, 16, 21, 0),
        goblin(i, 4, 15, 21, 0), goblin(i, 5, 14, 21, 0), goblin(i, 6, 24, 28, 0),
        goblin(i, 7, 26, 28, 0),
    ]
}

/// Queue: 8 goblins in sight behind an adventurer walking West, none adjacent: 7 in an arc 2
/// tiles away, the 8th 6 tiles away on the flank. A goblin behind the arc is walled off by it
/// under rule (a) and falls out of the window; this start keeps all 8 awake for the 10 ticks
/// (found by a search over start tiles in memory).
pub fn queue_goblins(i: u32) -> Array<Goblin> {
    array![
        goblin(i, 1, 18, 21, 0), goblin(i, 2, 19, 22, 0), goblin(i, 3, 19, 20, 0),
        goblin(i, 4, 19, 23, 0), goblin(i, 5, 19, 19, 0), goblin(i, 6, 18, 23, 0),
        goblin(i, 7, 18, 19, 0), goblin(i, 8, 17, 16, 0),
    ]
}
