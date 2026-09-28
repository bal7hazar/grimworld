//! The rules the measured actions run, in memory: damage, conditions, hex geometry, and one
//! world tick (design/02 *The tick*). Nothing here reads or writes storage.

use crate::board::{distance_of, flood, pow, step};
use crate::models::{Goblin, InstanceAdventurer};
use crate::tables::{DAMAGE, DAMAGE_MAX_INDEX, DAMAGE_OFFSET, WIDTH};

/// Radius of sight (ADR-0006 §4).
pub const SIGHT: u8 = 6;
/// Health regeneration and degeneration are capped at ±10 pips; 1 pip = 2 health per tick
/// (design/03 *Pips*).
const MAX_PIPS: u8 = 10;
/// Degeneration of the conditions, in pips (design/04 *Conditions*).
const BLEEDING: u8 = 3;
const POISON: u8 = 4;
const BURNING: u8 = 7;
/// Most awake goblins (design/02 *Simulation budget*).
pub const MAX_AWAKE: u32 = 8;

/// `base × 2^((strength − armor) / 40)`, from the lookup table, clamped to `[−160, +80]`
/// (design/04 *Damage formula*).
#[inline(always)]
pub fn damage(base: u8, strength: u8, armor: u8) -> u16 {
    let lhs: u16 = strength.into() + DAMAGE_OFFSET;
    let rhs: u16 = armor.into();
    let index = if lhs <= rhs {
        0
    } else if lhs - rhs > DAMAGE_MAX_INDEX {
        DAMAGE_MAX_INDEX
    } else {
        lhs - rhs
    };
    let factor: u32 = *DAMAGE.span()[index.into()];
    let base: u32 = base.into();
    ((base * factor) / 0x10000).try_into().unwrap()
}

/// Health after one tick of regeneration minus degeneration, capped at ±10 pips.
#[inline(always)]
pub fn regenerate(health: u16, max: u16, regeneration: u8, degeneration: u8) -> u16 {
    if regeneration >= degeneration {
        let pips = regeneration - degeneration;
        let pips: u16 = if pips > MAX_PIPS {
            MAX_PIPS.into()
        } else {
            pips.into()
        };
        let next = health + 2 * pips;
        if next > max {
            max
        } else {
            next
        }
    } else {
        let pips = degeneration - regeneration;
        let pips: u16 = if pips > MAX_PIPS {
            MAX_PIPS.into()
        } else {
            pips.into()
        };
        if health > 2 * pips {
            health - 2 * pips
        } else {
            0
        }
    }
}

/// Degeneration of the active conditions at `clock`, in pips.
#[inline(always)]
pub fn degeneration(clock: u32, bleeding: u32, poison: u32, burning: u32) -> u8 {
    let mut pips = 0;
    if clock < bleeding {
        pips += BLEEDING;
    }
    if clock < poison {
        pips += POISON;
    }
    if clock < burning {
        pips += BURNING;
    }
    pips
}

/// Hex distance between two global tiles (odd-r, `q = x − ⌊y/2⌋`).
pub fn hex_distance(x1: u8, y1: u8, x2: u8, y2: u8) -> u8 {
    let lhs = x2 + y1 / 2;
    let rhs = x1 + y2 / 2;
    let (dq, dq_negative) = if lhs >= rhs {
        (lhs - rhs, false)
    } else {
        (rhs - lhs, true)
    };
    let (dr, dr_negative) = if y2 >= y1 {
        (y2 - y1, false)
    } else {
        (y1 - y2, true)
    };
    if dq_negative == dr_negative {
        dq + dr
    } else if dq > dr {
        dq
    } else {
        dr
    }
}

/// Global neighbour in a direction: East, NorthEast, NorthWest, West, SouthWest, SouthEast.
pub fn neighbour(x: u8, y: u8, direction: u8) -> (u8, u8) {
    let odd = y % 2 == 1;
    match direction {
        0 => (x - 1, y),
        1 => if odd {
            (x, y + 1)
        } else {
            (x - 1, y + 1)
        },
        2 => if odd {
            (x + 1, y + 1)
        } else {
            (x, y + 1)
        },
        3 => (x + 1, y),
        4 => if odd {
            (x + 1, y - 1)
        } else {
            (x, y - 1)
        },
        _ => if odd {
            (x, y - 1)
        } else {
            (x - 1, y - 1)
        },
    }
}

/// Origin of the window that follows an adventurer (ADR-0006 §4): the adventurer on local
/// column 7, on local row 7 when its global row is odd and 8 when even; the origin row is even.
/// # Returns
/// * The origin and the adventurer's local tile
#[inline(always)]
pub fn window_origin(x: u8, y: u8) -> (u8, u8, u8) {
    if y % 2 == 1 {
        (x - 7, y - 7, 7 * WIDTH + 7)
    } else {
        (x - 7, y - 8, 8 * WIDTH + 7)
    }
}

/// Packed key of a window stand-in.
#[inline(always)]
pub fn origin_key(x: u8, y: u8) -> u16 {
    x.into() * 256 + y.into()
}

/// Local tile of a goblin if it stands in the window's interior (then it is awake).
#[inline(always)]
fn local(goblin: @Goblin, origin_x: u8, origin_y: u8) -> Option<u8> {
    let x = *goblin.x;
    let y = *goblin.y;
    if *goblin.health == 0 || x <= origin_x || y <= origin_y {
        return Option::None;
    }
    let lx = x - origin_x;
    let ly = y - origin_y;
    if lx > 13 || ly > 14 {
        return Option::None;
    }
    Option::Some(ly * WIDTH + lx)
}

/// Bit `j` set when goblin `j` (in list order) is alive and in sight.
pub fn in_sight(adventurer: @InstanceAdventurer, goblins: Span<Goblin>) -> u16 {
    let mut seen: u16 = 0;
    let mut bit: u16 = 1;
    for goblin in goblins {
        if *goblin.health != 0
            && hex_distance(*adventurer.x, *adventurer.y, *goblin.x, *goblin.y) <= SIGHT {
            seen += bit;
        }
        bit *= 2;
    }
    seen
}

/// The adventurer's weapon attack on an adjacent goblin (tick cost 1, sword).
pub fn attack(ref adventurer: InstanceAdventurer, ref goblin: Goblin) {
    assert(
        hex_distance(adventurer.x, adventurer.y, goblin.x, goblin.y) == 1, 'target not adjacent',
    );
    assert(goblin.health != 0, 'target dead');
    let hit = damage(adventurer.damage, adventurer.strength, goblin.armor);
    goblin.health = if goblin.health > hit {
        goblin.health - hit
    } else {
        0
    };
}

/// One world tick (design/02): 2. awake goblins act in ascending id order, sharing one flood;
/// 3. conditions and regeneration; 5. defeat. Step 1 (activations) and step 4 (deadlines only,
/// nothing to decrease) cost nothing here.
///
/// # Arguments
/// * `adventurer` - The adventurer, updated
/// * `goblins` - The instance's goblins in ascending id order (at most 8)
/// * `terrain` - The window's walkable tiles at the adventurer's position (ring is wall)
/// * `clock` - The instance clock at this tick
/// # Returns
/// * The goblins after the tick, and whether a goblin hit the adventurer
pub fn world_tick(
    ref adventurer: InstanceAdventurer, goblins: Span<Goblin>, terrain: felt252, clock: u32,
) -> (Array<Goblin>, bool) {
    assert(goblins.len() <= MAX_AWAKE, 'too many goblins');
    let (origin_x, origin_y, centre) = window_origin(adventurer.x, adventurer.y);
    // [Compute] Awake goblins and the occupancy frozen at the start of the tick
    let mut tiles: Array<u8> = array![];
    let mut occupied: felt252 = 0;
    for goblin in goblins {
        if let Option::Some(tile) = local(goblin, origin_x, origin_y) {
            tiles.append(tile);
            occupied += pow(tile);
        }
    }
    let tiles = tiles.span();
    // [Compute] One flood from the adventurer, shared by all goblins
    let free = terrain - occupied - pow(centre);
    let (layers, distances) = flood(free, centre, tiles);
    // [Compute] Goblins act, in ascending id order
    let mut hit = false;
    let mut next: Array<Goblin> = array![];
    let mut awake: usize = 0;
    for goblin in goblins {
        let mut goblin = *goblin;
        if let Option::Some(tile) = local(@goblin, origin_x, origin_y) {
            let distance = distance_of(distances, awake);
            awake += 1;
            if distance == 1 {
                let blow = damage(goblin.damage, goblin.strength, adventurer.armor);
                adventurer.health = if adventurer.health > blow {
                    adventurer.health - blow
                } else {
                    0
                };
                hit = true;
            } else if distance > 1 {
                if let Option::Some((to, facing)) = step(tile, distance, layers, occupied.into()) {
                    occupied = occupied - pow(tile) + pow(to);
                    goblin.x = origin_x + to % WIDTH;
                    goblin.y = origin_y + to / WIDTH;
                    goblin.facing = facing;
                }
            }
            // [Compute] Conditions and regeneration of the goblin
            let degeneration = degeneration(clock, goblin.bleeding, goblin.poison, goblin.burning);
            goblin
                .health =
                    regenerate(goblin.health, 0xffff, goblin.regeneration, degeneration);
        }
        next.append(goblin);
    }
    // [Compute] Conditions and regeneration of the adventurer
    let degeneration = degeneration(
        clock, adventurer.bleeding, adventurer.poison, adventurer.burning,
    );
    adventurer
        .health =
            regenerate(
                adventurer.health, adventurer.max_health, adventurer.regeneration, degeneration,
            );
    let energy = adventurer.energy + adventurer.energy_regeneration.into();
    adventurer.energy = if energy > adventurer.max_energy {
        adventurer.max_energy
    } else {
        energy
    };
    (next, hit)
}
