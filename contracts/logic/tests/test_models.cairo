// The world's record models (ENG-03, D-143; docs/architecture/ENG-01-interfaces.md §3.5): every
// field round-trips at its maximum through the record's parts, sits at its documented bit, and a
// value wider than its field is refused.
use grimworld_logic::content::Record;
use grimworld_logic::models::gate::{Gate, GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::location::{Location, LocationRecord, LocationTrait, kind};
use grimworld_logic::models::outline::{CHUNK_SET, Outline, OutlineRecord, OutlineTrait};
use grimworld_logic::models::region::{Region, RegionRecord, RegionTrait};
use grimworld_logic::packing::{LIVE, Lanes16};

const TWO_128: felt252 = 0x100000000000000000000000000000000;

/// The records these tests start from.
#[generate_trait]
impl FixtureImpl of Fixture {
    fn location_max() -> Location {
        LocationTrait::new(
            0xFF,
            0xFFFF,
            0xFF,
            0xFF,
            0xFF,
            0xFF,
            15,
            15,
            0xFF,
            0xFF,
            0xFFFF,
            0xFFFF,
            true,
            224,
            224,
            Lanes16 { lanes: [0xFFFF, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0xFFFF] },
        )
    }

    fn location_zero() -> Location {
        LocationTrait::new(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, 0, 0, Lanes16 { lanes: [0; 15] },
        )
    }

    fn gate_max() -> Gate {
        GateTrait::new(0xFFFF, 0xFFFF, 224, 224, 224, 224, 0xFF, 0xFF, 0xFFFFFFFF)
    }
}

#[test]
#[available_gas(l2_gas: 82877)] // ceil(1.05 × 78930 measured)
fn test_region_round_trip() {
    let region = RegionTrait::new(0xFFFF, 2, 0xFFFF, 'Fifteen letters');
    assert(Record::unpack(region.pack()) == region, 'round trip');
    let zero = RegionTrait::new(0, 0, 0, 0);
    assert(zero.pack() == array![LIVE].span(), 'empty is LIVE');
    assert(Record::<Region>::unpack(zero.pack()) == zero, 'zero round trip');
    // Bits: town 0, book 16, first location 32, name 128.
    let one = RegionTrait::new(1, 1, 1, 1).pack();
    assert(*one[0] == 1 + 0x10000 + 0x100000000 + TWO_128 + LIVE, 'bits');
}

#[test]
#[available_gas(l2_gas: 17598)] // ceil(1.05 × 16760 measured)
#[should_panic(expected: 'region: name too long')]
fn test_region_name_too_long() {
    RegionTrait::new(1, 0, 1, 'Sixteen letters!').pack();
}

#[test]
#[available_gas(l2_gas: 755286)] // ceil(1.05 × 719320 measured)
fn test_location_round_trip() {
    let top = Fixture::location_max();
    let parts = top.pack();
    assert(parts.len() == 2, 'two parts');
    assert(Record::<Location>::unpack(parts) == top, 'round trip');
    let zero = Fixture::location_zero();
    let parts = zero.pack();
    assert(parts == array![LIVE, LIVE].span(), 'empty is LIVE');
    assert(Record::<Location>::unpack(parts) == zero, 'zero round trip');
}

#[test]
#[available_gas(l2_gas: 240776)] // ceil(1.05 × 229310 measured)
fn test_location_bits() {
    let value = LocationTrait::new(
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, true, 1, 1, Lanes16 { lanes: [0; 15] },
    );
    let parts = value.pack();
    // type 0 · region 8 · biome 24 · level min 32 · level max 40 · rank 48 · width 56 ·
    // height 64 · N 72 · floors 80 · next floor 88 · spawn table 104 · sealed 120 · entry
    // chunk 128 · entry tile 136.
    let low: felt252 = 0x1000100010101010101010101000101;
    assert(*parts[0] == low + TWO_128 + 0x100 * TWO_128 + LIVE, 'bits');
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'location: width')]
fn test_location_width_refused() {
    let mut value = Fixture::location_zero();
    value.width = 16;
    value.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'location: height')]
fn test_location_height_refused() {
    let mut value = Fixture::location_zero();
    value.height = 16;
    value.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'location: entry chunk')]
fn test_location_entry_chunk_refused() {
    let mut value = Fixture::location_zero();
    value.entry_chunk = 225;
    value.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'location: entry tile')]
fn test_location_entry_tile_refused() {
    let mut value = Fixture::location_zero();
    value.entry_tile = 225;
    value.pack();
}

#[test]
#[available_gas(l2_gas: 201443)] // ceil(1.05 × 191850 measured)
fn test_gate_round_trip() {
    let top = Fixture::gate_max();
    assert(Record::<Gate>::unpack(top.pack()) == top, 'round trip');
    let gate = GateTrait::new(3, 4, 0, 0, 112, 112, gate_kind::FLOOR, 0, 0);
    assert(Record::<Gate>::unpack(gate.pack()) == gate, 'a floor gate');
    // source 0 · destination 16 · anchor chunk 32, tile 40 · entry chunk 48, tile 56 · kind 64
    // ·
    // rank 72 · quest 80; nothing in the high limb.
    let one = GateTrait::new(1, 1, 1, 1, 1, 1, 1, 1, 1).pack();
    assert(*one[0] == 0x101010101010100010001 + LIVE, 'bits');
    assert(*top.pack()[0] == 0xFFFFFFFFFFFFE0E0E0E0FFFFFFFF + LIVE, 'maximum below bit 112');
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'gate: anchor chunk')]
fn test_gate_anchor_chunk_refused() {
    let mut gate = Fixture::gate_max();
    gate.anchor_chunk = 225;
    gate.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'gate: anchor tile')]
fn test_gate_anchor_tile_refused() {
    let mut gate = Fixture::gate_max();
    gate.anchor_tile = 225;
    gate.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'gate: entry chunk')]
fn test_gate_entry_chunk_refused() {
    let mut gate = Fixture::gate_max();
    gate.entry_chunk = 225;
    gate.pack();
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'gate: entry tile')]
fn test_gate_entry_tile_refused() {
    let mut gate = Fixture::gate_max();
    gate.entry_tile = 225;
    gate.pack();
}

#[test]
#[available_gas(l2_gas: 22292)] // ceil(1.05 × 21230 measured)
fn test_outline_round_trip() {
    // All 225 bits set: 128 in the low limb, 97 in the high one.
    let full = OutlineTrait::new(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 0x1FFFFFFFFFFFFFFFFFFFFFFFF);
    assert(Record::<Outline>::unpack(full.pack()) == full, 'round trip');
    let empty = OutlineTrait::new(0, 0);
    assert(empty.pack() == array![LIVE].span(), 'empty is LIVE');
    assert(Record::<Outline>::unpack(array![LIVE].span()) == empty, 'empty round trip');
    // Bit 128 is the high limb's bit 0.
    assert(*OutlineTrait::new(0, 1).pack()[0] == TWO_128 + LIVE, 'bit 128');
    assert(OutlineTrait::id(2, CHUNK_SET) == 767, 'chunk set id');
    assert(OutlineTrait::id(0xFFFF, 224) == 0xFFFFE0, 'border chunk id');
    assert(kind::ZONE != kind::DUNGEON, 'kinds');
}

#[test]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
#[should_panic(expected: 'outline: above bit 224')]
fn test_outline_above_bit_224_refused() {
    OutlineTrait::new(0, 0x2000000000000000000000000).pack();
}
