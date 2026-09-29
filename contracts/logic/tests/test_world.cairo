// The world's record layouts (ENG-03; docs/architecture/ENG-01-interfaces.md §3.5): every field
// round-trips at its maximum, sits at its documented bit, and a value wider than its field is
// refused.
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::world::{
    CHUNK_SET, DUNGEON, GATE_FLOOR, Gate, Location, Outline, Region, ZONE, outline_id, pack_gate,
    pack_location, pack_outline, pack_region, unpack_gate, unpack_location, unpack_outline,
    unpack_region,
};

const TWO_128: felt252 = 0x100000000000000000000000000000000;

fn location_max() -> Location {
    Location {
        kind: 0xFF,
        region: 0xFFFF,
        biome: 0xFF,
        level_min: 0xFF,
        level_max: 0xFF,
        rank: 0xFF,
        width: 15,
        height: 15,
        target: 0xFF,
        floors: 0xFF,
        next_floor: 0xFFFF,
        spawn_table: 0xFFFF,
        sealed: true,
        entry_chunk: 224,
        entry_tile: 224,
        set_pieces: Lanes16 {
            lanes: [
                0xFFFF, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0xFFFF,
            ],
        },
    }
}

fn location_zero() -> Location {
    Location {
        kind: 0,
        region: 0,
        biome: 0,
        level_min: 0,
        level_max: 0,
        rank: 0,
        width: 0,
        height: 0,
        target: 0,
        floors: 0,
        next_floor: 0,
        spawn_table: 0,
        sealed: false,
        entry_chunk: 0,
        entry_tile: 0,
        set_pieces: Lanes16 { lanes: [0; 15] },
    }
}

fn gate_max() -> Gate {
    Gate {
        source: 0xFFFF,
        destination: 0xFFFF,
        anchor_chunk: 224,
        anchor_tile: 224,
        entry_chunk: 224,
        entry_tile: 224,
        kind: 0xFF,
        rank: 0xFF,
        quest: 0xFFFFFFFF,
    }
}

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_region_round_trip() {
    let region = Region { town: 0xFFFF, book: 2, first_location: 0xFFFF, name: 'Fifteen letters' };
    assert(unpack_region(pack_region(region)) == region, 'round trip');
    let zero = Region { town: 0, book: 0, first_location: 0, name: 0 };
    assert(pack_region(zero) == LIVE, 'empty is LIVE');
    assert(unpack_region(pack_region(zero)) == zero, 'zero round trip');
    // Bits: town 0, book 16, first location 32, name 128.
    let one = pack_region(Region { town: 1, book: 1, first_location: 1, name: 1 });
    assert(one == 1 + 0x10000 + 0x100000000 + TWO_128 + LIVE, 'bits');
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'region: name too long')]
fn test_region_name_too_long() {
    pack_region(Region { town: 1, book: 0, first_location: 1, name: 'Sixteen letters!' });
}

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_location_round_trip() {
    let top = location_max();
    let (a, b) = pack_location(top);
    assert(unpack_location(a, b) == top, 'round trip');
    let zero = location_zero();
    let (a, b) = pack_location(zero);
    assert(a == LIVE && b == LIVE, 'empty is LIVE');
    assert(unpack_location(a, b) == zero, 'zero round trip');
}

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_location_bits() {
    let mut value = location_zero();
    value.kind = 1;
    value.region = 1;
    value.biome = 1;
    value.level_min = 1;
    value.level_max = 1;
    value.rank = 1;
    value.width = 1;
    value.height = 1;
    value.target = 1;
    value.floors = 1;
    value.next_floor = 1;
    value.spawn_table = 1;
    value.sealed = true;
    value.entry_chunk = 1;
    value.entry_tile = 1;
    let (a, _) = pack_location(value);
    // type 0 · region 8 · biome 24 · level min 32 · level max 40 · rank 48 · width 56 · height 64
    // · N 72 · floors 80 · next floor 88 · spawn table 104 · sealed 120 · entry chunk 128 · entry
    // tile 136.
    let low: felt252 = 0x1000100010101010101010101000101;
    assert(a == low + TWO_128 + 0x100 * TWO_128 + LIVE, 'bits');
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'location: width')]
fn test_location_width_refused() {
    let mut value = location_zero();
    value.width = 16;
    pack_location(value);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'location: height')]
fn test_location_height_refused() {
    let mut value = location_zero();
    value.height = 16;
    pack_location(value);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'location: entry chunk')]
fn test_location_entry_chunk_refused() {
    let mut value = location_zero();
    value.entry_chunk = 225;
    pack_location(value);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'location: entry tile')]
fn test_location_entry_tile_refused() {
    let mut value = location_zero();
    value.entry_tile = 225;
    pack_location(value);
}

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_gate_round_trip() {
    let top = gate_max();
    assert(unpack_gate(pack_gate(top)) == top, 'round trip');
    let gate = Gate {
        source: 3,
        destination: 4,
        anchor_chunk: 0,
        anchor_tile: 0,
        entry_chunk: 112,
        entry_tile: 112,
        kind: GATE_FLOOR,
        rank: 0,
        quest: 0,
    };
    assert(unpack_gate(pack_gate(gate)) == gate, 'a floor gate');
    // source 0 · destination 16 · anchor chunk 32, tile 40 · entry chunk 48, tile 56 · kind 64 ·
    // rank 72 · quest 80; nothing in the high limb.
    let one = pack_gate(
        Gate {
            source: 1,
            destination: 1,
            anchor_chunk: 1,
            anchor_tile: 1,
            entry_chunk: 1,
            entry_tile: 1,
            kind: 1,
            rank: 1,
            quest: 1,
        },
    );
    assert(one == 0x101010101010100010001 + LIVE, 'bits');
    assert(pack_gate(gate_max()) == 0xFFFFFFFFFFFFE0E0E0E0FFFFFFFF + LIVE, 'maximum below bit 112');
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'gate: anchor chunk')]
fn test_gate_anchor_chunk_refused() {
    let mut gate = gate_max();
    gate.anchor_chunk = 225;
    pack_gate(gate);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'gate: anchor tile')]
fn test_gate_anchor_tile_refused() {
    let mut gate = gate_max();
    gate.anchor_tile = 225;
    pack_gate(gate);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'gate: entry chunk')]
fn test_gate_entry_chunk_refused() {
    let mut gate = gate_max();
    gate.entry_chunk = 225;
    pack_gate(gate);
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'gate: entry tile')]
fn test_gate_entry_tile_refused() {
    let mut gate = gate_max();
    gate.entry_tile = 225;
    pack_gate(gate);
}

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_outline_round_trip() {
    // All 225 bits set: 128 in the low limb, 97 in the high one.
    let full = Outline {
        low: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, high: 0x1FFFFFFFFFFFFFFFFFFFFFFFF,
    };
    assert(unpack_outline(pack_outline(full)) == full, 'round trip');
    let empty = Outline { low: 0, high: 0 };
    assert(pack_outline(empty) == LIVE, 'empty is LIVE');
    assert(unpack_outline(LIVE) == empty, 'empty round trip');
    // Bit 128 is the high limb's bit 0.
    assert(pack_outline(Outline { low: 0, high: 1 }) == TWO_128 + LIVE, 'bit 128');
    assert(outline_id(2, CHUNK_SET) == 767, 'chunk set id');
    assert(outline_id(0xFFFF, 224) == 0xFFFFE0, 'border chunk id');
    assert(ZONE != DUNGEON, 'kinds');
}

#[test]
#[available_gas(l2_gas: 1000000)]
#[should_panic(expected: 'outline: above bit 224')]
fn test_outline_above_bit_224_refused() {
    pack_outline(Outline { low: 0, high: 0x2000000000000000000000000 });
}
