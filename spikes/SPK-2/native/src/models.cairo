//! Native storage structs (ADR-0007, docs/CAIRO.md §4, §5): the same fields as part 1's models,
//! so that the pure logic copied from part 1 compiles unchanged, and explicit packing into felts.
//! Keys are not stored: they are the storage map's keys, restored on unpacking.
//!
//! `u256` is used only to split a felt into its two `u128` limbs for unpacking (written reason:
//! the cheapest split available on Cairo 2.19 without `origami_hexmap`'s `u252`).

// ---------------------------------------------------------------------------------------------
// Ephemeral domain

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct InstanceAdventurer {
    pub instance_id: u32,
    pub adventurer: u32,
    pub x: u8,
    pub y: u8,
    pub facing: u8,
    pub health: u16,
    pub max_health: u16,
    pub energy: u16,
    pub max_energy: u16,
    pub armor: u8,
    pub strength: u8,
    pub damage: u8,
    pub regeneration: u8,
    pub energy_regeneration: u8,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Goblin {
    pub instance_id: u32,
    pub id: u32,
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

/// Variant "one storage struct per goblin", mirroring part 1's one model per goblin: the
/// default `Store` layout, one slot per field (11 slots).
#[derive(Copy, Drop, Serde, Debug, PartialEq, starknet::Store)]
pub struct GoblinSlots {
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

/// Variant "goblins packed per instance": 8 goblins, one felt each (`pack_goblin`), in
/// consecutive slots under one key.
#[derive(Copy, Drop, Serde, Debug, starknet::Store)]
pub struct GoblinPack {
    pub g0: felt252,
    pub g1: felt252,
    pub g2: felt252,
    pub g3: felt252,
    pub g4: felt252,
    pub g5: felt252,
    pub g6: felt252,
    pub g7: felt252,
}

/// An instance's fields besides its owner and its entry draw.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Instance {
    pub id: u32,
    pub clock: u32,
    pub location: u32,
    pub adventurer: u32,
    pub goblins: u8,
}

// ---------------------------------------------------------------------------------------------
// Persistent domain

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Adventurer {
    pub id: u32,
    pub level: u8,
    pub experience: u32,
    pub gold: u32,
    pub hub: u32,
    pub instance: u32,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Book {
    pub id: u32,
    pub ingredients: u8,
    pub rarities: u32,
    pub masks: u128,
    pub recipes: u16,
    pub ingredient: u32,
    pub potion: u32,
    pub failed: u32,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Grimoire {
    pub adventurer: u32,
    pub book: u32,
    pub known: u16,
    pub remaining: u64,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Quest {
    pub id: u32,
    pub hub: u32,
    pub level: u8,
    pub target: u16,
    pub experience: u32,
    pub gold: u32,
    pub item: u32,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Location {
    pub id: u32,
    pub hub: u32,
    pub level: u8,
    pub x: u8,
    pub y: u8,
}

// ---------------------------------------------------------------------------------------------
// Packing

const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const B8: NonZero<u128> = 0x100;
const B16: NonZero<u128> = 0x10000;
const B32: NonZero<u128> = 0x100000000;
const B64: NonZero<u128> = 0x10000000000000000;

#[inline(always)]
fn join(low: u128, high: u128) -> felt252 {
    low.into() + high.into() * TWO_POW_128
}

/// Goblin, low limb: x 0-7, y 8-15, facing 16-23, health 24-39, armor 40-47, strength 48-55,
/// damage 56-63, regeneration 64-71, bleeding 72-103; high limb: poison 0-31, burning 32-63.
pub fn pack_goblin(goblin: @Goblin) -> felt252 {
    let low: u128 = (*goblin.x).into()
        + (*goblin.y).into() * 0x100
        + (*goblin.facing).into() * 0x10000
        + (*goblin.health).into() * 0x1000000
        + (*goblin.armor).into() * 0x10000000000
        + (*goblin.strength).into() * 0x1000000000000
        + (*goblin.damage).into() * 0x100000000000000
        + (*goblin.regeneration).into() * 0x10000000000000000
        + (*goblin.bleeding).into() * 0x1000000000000000000;
    let high: u128 = (*goblin.poison).into() + (*goblin.burning).into() * 0x100000000;
    join(low, high)
}

pub fn unpack_goblin(instance_id: u32, id: u32, packed: felt252) -> Goblin {
    let wide: u256 = packed.into();
    let (rest, x) = DivRem::div_rem(wide.low, B8);
    let (rest, y) = DivRem::div_rem(rest, B8);
    let (rest, facing) = DivRem::div_rem(rest, B8);
    let (rest, health) = DivRem::div_rem(rest, B16);
    let (rest, armor) = DivRem::div_rem(rest, B8);
    let (rest, strength) = DivRem::div_rem(rest, B8);
    let (rest, damage) = DivRem::div_rem(rest, B8);
    let (bleeding, regeneration) = DivRem::div_rem(rest, B8);
    let (burning, poison) = DivRem::div_rem(wide.high, B32);
    Goblin {
        instance_id,
        id,
        x: x.try_into().unwrap(),
        y: y.try_into().unwrap(),
        facing: facing.try_into().unwrap(),
        health: health.try_into().unwrap(),
        armor: armor.try_into().unwrap(),
        strength: strength.try_into().unwrap(),
        damage: damage.try_into().unwrap(),
        regeneration: regeneration.try_into().unwrap(),
        bleeding: bleeding.try_into().unwrap(),
        poison: poison.try_into().unwrap(),
        burning: burning.try_into().unwrap(),
    }
}

pub fn to_slots(goblin: @Goblin) -> GoblinSlots {
    GoblinSlots {
        x: *goblin.x,
        y: *goblin.y,
        facing: *goblin.facing,
        health: *goblin.health,
        armor: *goblin.armor,
        strength: *goblin.strength,
        damage: *goblin.damage,
        regeneration: *goblin.regeneration,
        bleeding: *goblin.bleeding,
        poison: *goblin.poison,
        burning: *goblin.burning,
    }
}

pub fn from_slots(instance_id: u32, id: u32, slots: GoblinSlots) -> Goblin {
    Goblin {
        instance_id,
        id,
        x: slots.x,
        y: slots.y,
        facing: slots.facing,
        health: slots.health,
        armor: slots.armor,
        strength: slots.strength,
        damage: slots.damage,
        regeneration: slots.regeneration,
        bleeding: slots.bleeding,
        poison: slots.poison,
        burning: slots.burning,
    }
}

/// Adventurer in an instance, low limb (128 bits exactly): x, y, facing, health, max_health,
/// energy, max_energy, armor, strength, damage, regeneration, energy_regeneration; high limb:
/// bleeding, poison, burning.
pub fn pack_adventurer(a: @InstanceAdventurer) -> felt252 {
    let low: u128 = (*a.x).into()
        + (*a.y).into() * 0x100
        + (*a.facing).into() * 0x10000
        + (*a.health).into() * 0x1000000
        + (*a.max_health).into() * 0x10000000000
        + (*a.energy).into() * 0x100000000000000
        + (*a.max_energy).into() * 0x1000000000000000000
        + (*a.armor).into() * 0x10000000000000000000000
        + (*a.strength).into() * 0x1000000000000000000000000
        + (*a.damage).into() * 0x100000000000000000000000000
        + (*a.regeneration).into() * 0x10000000000000000000000000000
        + (*a.energy_regeneration).into() * 0x1000000000000000000000000000000;
    let high: u128 = (*a.bleeding).into()
        + (*a.poison).into() * 0x100000000
        + (*a.burning).into() * 0x10000000000000000;
    join(low, high)
}

pub fn unpack_adventurer(instance_id: u32, adventurer: u32, packed: felt252) -> InstanceAdventurer {
    let wide: u256 = packed.into();
    let (rest, x) = DivRem::div_rem(wide.low, B8);
    let (rest, y) = DivRem::div_rem(rest, B8);
    let (rest, facing) = DivRem::div_rem(rest, B8);
    let (rest, health) = DivRem::div_rem(rest, B16);
    let (rest, max_health) = DivRem::div_rem(rest, B16);
    let (rest, energy) = DivRem::div_rem(rest, B16);
    let (rest, max_energy) = DivRem::div_rem(rest, B16);
    let (rest, armor) = DivRem::div_rem(rest, B8);
    let (rest, strength) = DivRem::div_rem(rest, B8);
    let (rest, damage) = DivRem::div_rem(rest, B8);
    let (energy_regeneration, regeneration) = DivRem::div_rem(rest, B8);
    let (rest, bleeding) = DivRem::div_rem(wide.high, B32);
    let (burning, poison) = DivRem::div_rem(rest, B32);
    InstanceAdventurer {
        instance_id,
        adventurer,
        x: x.try_into().unwrap(),
        y: y.try_into().unwrap(),
        facing: facing.try_into().unwrap(),
        health: health.try_into().unwrap(),
        max_health: max_health.try_into().unwrap(),
        energy: energy.try_into().unwrap(),
        max_energy: max_energy.try_into().unwrap(),
        armor: armor.try_into().unwrap(),
        strength: strength.try_into().unwrap(),
        damage: damage.try_into().unwrap(),
        regeneration: regeneration.try_into().unwrap(),
        energy_regeneration: energy_regeneration.try_into().unwrap(),
        bleeding: bleeding.try_into().unwrap(),
        poison: poison.try_into().unwrap(),
        burning: burning.try_into().unwrap(),
    }
}

/// Instance: clock 0-31, location 32-63, adventurer 64-95, goblins 96-103.
pub fn pack_instance(i: @Instance) -> u128 {
    (*i.clock).into()
        + (*i.location).into() * 0x100000000
        + (*i.adventurer).into() * 0x10000000000000000
        + (*i.goblins).into() * 0x1000000000000000000000000
}

pub fn unpack_instance(id: u32, packed: u128) -> Instance {
    let (rest, clock) = DivRem::div_rem(packed, B32);
    let (rest, location) = DivRem::div_rem(rest, B32);
    let (goblins, adventurer) = DivRem::div_rem(rest, B32);
    Instance {
        id,
        clock: clock.try_into().unwrap(),
        location: location.try_into().unwrap(),
        adventurer: adventurer.try_into().unwrap(),
        goblins: goblins.try_into().unwrap(),
    }
}

/// Adventurer (persistent): experience 0-31, gold 32-63, hub 64-95, instance 96-127, level in
/// the high limb.
pub fn pack_hero(a: @Adventurer) -> felt252 {
    let low: u128 = (*a.experience).into()
        + (*a.gold).into() * 0x100000000
        + (*a.hub).into() * 0x10000000000000000
        + (*a.instance).into() * 0x1000000000000000000000000;
    join(low, (*a.level).into())
}

pub fn unpack_hero(id: u32, packed: felt252) -> Adventurer {
    let wide: u256 = packed.into();
    let (rest, experience) = DivRem::div_rem(wide.low, B32);
    let (rest, gold) = DivRem::div_rem(rest, B32);
    let (instance, hub) = DivRem::div_rem(rest, B32);
    Adventurer {
        id,
        level: wide.high.try_into().unwrap(),
        experience: experience.try_into().unwrap(),
        gold: gold.try_into().unwrap(),
        hub: hub.try_into().unwrap(),
        instance: instance.try_into().unwrap(),
    }
}

/// Book: the masks in one slot (`u128`), the rest in another: ingredients 0-7, rarities 8-39,
/// recipes 40-55, ingredient 56-87, potion 88-119 (low limb); failed (high limb).
pub fn pack_book_meta(b: @Book) -> felt252 {
    let low: u128 = (*b.ingredients).into()
        + (*b.rarities).into() * 0x100
        + (*b.recipes).into() * 0x10000000000
        + (*b.ingredient).into() * 0x100000000000000
        + (*b.potion).into() * 0x10000000000000000000000;
    join(low, (*b.failed).into())
}

pub fn unpack_book(id: u32, meta: felt252, masks: u128) -> Book {
    let wide: u256 = meta.into();
    let (rest, ingredients) = DivRem::div_rem(wide.low, B8);
    let (rest, rarities) = DivRem::div_rem(rest, B32);
    let (rest, recipes) = DivRem::div_rem(rest, B16);
    let (potion, ingredient) = DivRem::div_rem(rest, B32);
    Book {
        id,
        ingredients: ingredients.try_into().unwrap(),
        rarities: rarities.try_into().unwrap(),
        masks,
        recipes: recipes.try_into().unwrap(),
        ingredient: ingredient.try_into().unwrap(),
        potion: potion.try_into().unwrap(),
        failed: wide.high.try_into().unwrap(),
    }
}

/// Grimoire: remaining 0-63, known 64-79.
pub fn pack_grimoire(g: @Grimoire) -> u128 {
    (*g.remaining).into() + (*g.known).into() * 0x10000000000000000
}

pub fn unpack_grimoire(adventurer: u32, book: u32, packed: u128) -> Grimoire {
    let (known, remaining) = DivRem::div_rem(packed, B64);
    Grimoire {
        adventurer,
        book,
        known: known.try_into().unwrap(),
        remaining: remaining.try_into().unwrap(),
    }
}

/// Quest: hub 0-31, level 32-39, target 40-55, experience 56-87, gold 88-119 (low); item (high).
pub fn pack_quest(q: @Quest) -> felt252 {
    let low: u128 = (*q.hub).into()
        + (*q.level).into() * 0x100000000
        + (*q.target).into() * 0x10000000000
        + (*q.experience).into() * 0x100000000000000
        + (*q.gold).into() * 0x10000000000000000000000;
    join(low, (*q.item).into())
}

pub fn unpack_quest(id: u32, packed: felt252) -> Quest {
    let wide: u256 = packed.into();
    let (rest, hub) = DivRem::div_rem(wide.low, B32);
    let (rest, level) = DivRem::div_rem(rest, B8);
    let (rest, target) = DivRem::div_rem(rest, B16);
    let (gold, experience) = DivRem::div_rem(rest, B32);
    Quest {
        id,
        hub: hub.try_into().unwrap(),
        level: level.try_into().unwrap(),
        target: target.try_into().unwrap(),
        experience: experience.try_into().unwrap(),
        gold: gold.try_into().unwrap(),
        item: wide.high.try_into().unwrap(),
    }
}

/// Location: hub 0-31, level 32-39, x 40-47, y 48-55.
pub fn pack_location(l: @Location) -> u64 {
    (*l.hub).into()
        + (*l.level).into() * 0x100000000
        + (*l.x).into() * 0x10000000000
        + (*l.y).into() * 0x1000000000000
}

pub fn unpack_location(id: u32, packed: u64) -> Location {
    let wide: u128 = packed.into();
    let (rest, hub) = DivRem::div_rem(wide, B32);
    let (rest, level) = DivRem::div_rem(rest, B8);
    let (y, x) = DivRem::div_rem(rest, B8);
    Location {
        id,
        hub: hub.try_into().unwrap(),
        level: level.try_into().unwrap(),
        x: x.try_into().unwrap(),
        y: y.try_into().unwrap(),
    }
}
