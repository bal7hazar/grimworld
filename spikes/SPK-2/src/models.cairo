//! Throwaway models, shaped the way a real system would read and write them: one model per
//! entity, fields of the smallest integer, packed by Dojo (`IntrospectPacked`) into as few
//! storage slots as the fields need.
//!
//! Ephemeral domain (keyed by instance id, M-1): `Instance`, `InstanceAdventurer`, `Goblin`,
//! `Window`. Persistent domain: `Adventurer`, `Balance`, `Book`, `Grimoire`, `Discovery`, `Quest`,
//! `QuestLog`, `Location`, `Counter`. No model holds fields of both.

// ---------------------------------------------------------------------------------------------
// Ephemeral domain

/// One instance. Packed: 1 slot for the fields, 1 for the entry draw.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Instance {
    #[key]
    pub id: u32,
    pub clock: u32,
    pub location: u32,
    pub adventurer: u32,
    /// Goblins of the instance have ids 1..=goblins.
    pub goblins: u8,
    /// The entry draw (ADR-0002), through the `fate` stand-in.
    pub entry_draw: felt252,
}

/// The snapshot of the adventurer taken at entry, and its state in the instance. 1 slot.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug, PartialEq)]
#[dojo::model]
pub struct InstanceAdventurer {
    #[key]
    pub instance_id: u32,
    #[key]
    pub adventurer: u32,
    /// Global coordinates in the location.
    pub x: u8,
    pub y: u8,
    pub facing: u8,
    pub health: u16,
    pub max_health: u16,
    /// Energy, in thirds (design/03 *Pips*).
    pub energy: u16,
    pub max_energy: u16,
    pub armor: u8,
    /// Weapon strength, `5 × attribute rank` (design/04).
    pub strength: u8,
    pub damage: u8,
    /// Health regeneration and energy regeneration, in pips.
    pub regeneration: u8,
    pub energy_regeneration: u8,
    /// Condition deadlines, on the instance clock.
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
}

/// One goblin. 1 slot.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug, PartialEq)]
#[dojo::model]
pub struct Goblin {
    #[key]
    pub instance_id: u32,
    #[key]
    pub id: u32,
    /// Global coordinates in the location.
    pub x: u8,
    pub y: u8,
    pub facing: u8,
    pub health: u16,
    pub armor: u8,
    pub strength: u8,
    pub damage: u8,
    pub regeneration: u8,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
}

/// Stand-in for the window assembled from the chunks (SPK-7 measures the assembly): the
/// terrain of the 15 × 16 board at an origin, already assembled, read once per tick. The real
/// window is never stored (D-120). `origin = 256 × x + y`, `y` even.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Window {
    #[key]
    pub instance_id: u32,
    #[key]
    pub origin: u16,
    pub terrain: felt252,
}

// ---------------------------------------------------------------------------------------------
// Persistent domain

/// An adventurer. `instance` is 0 in a hub.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Adventurer {
    #[key]
    pub id: u32,
    pub owner: felt252,
    pub level: u8,
    pub experience: u32,
    pub gold: u32,
    pub hub: u32,
    pub instance: u32,
}

/// Items held by an owner (adventurer id), keyed by item id (Q-07: balances by owner and item).
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Balance {
    #[key]
    pub owner: u32,
    #[key]
    pub item: u32,
    pub amount: u32,
}

/// Registry: a book of alchemy (design/07). Ingredients are items `ingredient + i`, recipes are
/// potions `potion + r`, the failed brew is item `failed`.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Book {
    #[key]
    pub id: u32,
    pub ingredients: u8,
    /// Rarity of each ingredient, 2 bits each (0 C, 1 U, 2 R).
    pub rarities: u32,
    /// Recipes of each signature, 16 bits each, signature order C+C, C+U, U+U, C+R, U+R, R+R.
    pub masks: u128,
    /// Every recipe of the book.
    pub recipes: u16,
    pub ingredient: u32,
    pub potion: u32,
    pub failed: u32,
}

/// Per adventurer and book: discovered recipes and untried pairs (per signature, 8 bits each;
/// without signatures, the low byte counts every untried pair).
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Grimoire {
    #[key]
    pub adventurer: u32,
    #[key]
    pub book: u32,
    pub known: u16,
    pub remaining: u64,
}

/// The frozen result of a pair `a < b` (pair = 16 a + b): 0 untried, 1 failed, 2 + r recipe r.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Discovery {
    #[key]
    pub adventurer: u32,
    #[key]
    pub book: u32,
    #[key]
    pub pair: u8,
    pub result: u8,
}

/// Registry: a quest posted in a hub.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Quest {
    #[key]
    pub id: u32,
    pub hub: u32,
    pub level: u8,
    pub target: u16,
    pub experience: u32,
    pub gold: u32,
    pub item: u32,
}

/// An adventurer's progress on a quest: 0 none, 1 accepted, 2 claimed.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct QuestLog {
    #[key]
    pub adventurer: u32,
    #[key]
    pub quest: u32,
    pub status: u8,
    pub progress: u16,
}

/// Registry: a location entered through a gate of a hub.
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Location {
    #[key]
    pub id: u32,
    pub hub: u32,
    pub level: u8,
    /// Where the adventurer stands on entry.
    pub x: u8,
    pub y: u8,
}

/// Game-wide counters (instance ids).
#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
#[dojo::model]
pub struct Counter {
    #[key]
    pub id: felt252,
    pub value: u32,
}
