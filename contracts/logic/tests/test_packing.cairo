// Packing rules (docs/architecture/ENG-01-interfaces.md, *Packing*): two limbs, LIVE at bit 250,
// lanes, bitmaps; identifiers. The snapshot's and the task pages' layouts are `snapshot.cairo`'s
// unit tests (D-167).
use grimworld_logic::content::{LAST_KIND, parts};
use grimworld_logic::packing::{
    Bitmap, Counter, LIVE, Lanes16, Lanes32, join, pack_lanes16, pack_lanes32, unpack_lanes16,
    unpack_lanes32,
};
use grimworld_logic::types::{goblin_entity, instance_id, instance_parts};
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

#[test]
#[available_gas(l2_gas: 108045)] // ceil(1.05 × 102900 measured)
fn test_lanes32() {
    let lanes = Lanes32 { lanes: [1, 2, 3, 0xFFFFFFFF, 5, 6, 0xFFFFFFFF] };
    let word = pack_lanes32(lanes);
    assert(unpack_lanes32(word) == lanes, 'round trip');
    let one = pack_lanes32(Lanes32 { lanes: [0, 0, 0, 0, 1, 0, 0] });
    assert(one == TWO_128 + LIVE, 'lane 4 at bit 128');
    assert(pack_lanes32(Lanes32 { lanes: [0; 7] }) == LIVE, 'empty is LIVE, not 0');
    assert(unpack_lanes32(0) == Lanes32 { lanes: [0; 7] }, 'unwritten is empty');
}

#[test]
#[available_gas(l2_gas: 443289)] // ceil(1.05 × 422180 measured)
fn test_lanes16() {
    let lanes = Lanes16 { lanes: [1, 2, 3, 4, 5, 6, 7, 0xFFFF, 9, 10, 11, 12, 13, 14, 0xFFFF] };
    assert(unpack_lanes16(pack_lanes16(lanes)) == lanes, 'round trip');
    let mut one = [0_u16; 15];
    let [a, b, c, d, e, f, g, h, _, j, k, l, m, n, o] = one;
    one = [a, b, c, d, e, f, g, h, 1, j, k, l, m, n, o];
    assert(pack_lanes16(Lanes16 { lanes: one }) == TWO_128 + LIVE, 'lane 8 at bit 128');
}

#[test]
#[available_gas(l2_gas: 12999)] // ceil(1.05 × 12380 measured)
fn test_bitmap() {
    let top: felt252 = 0x200000000000000000000000000000000000000000000000000000000000000; // 2^249
    let bitmap = Bitmap { bits: top + 1 };
    let word = StorePacking::<Bitmap, felt252>::pack(bitmap);
    assert(word == top + 1 + LIVE, 'LIVE above bit 249');
    assert(StorePacking::<Bitmap, felt252>::unpack(word) == bitmap, 'round trip');
}

#[test]
#[available_gas(l2_gas: 11781)] // ceil(1.05 × 11220 measured)
fn test_identifiers() {
    let id = instance_id(7, 3);
    assert(id == 7 * 0x100000000 + 3, 'instance id');
    assert(instance_parts(id) == (7, 3), 'parts');
    assert(goblin_entity(0, 0) == 8, 'first goblin');
    assert(goblin_entity(224, 9) == 8 + 16 * 224 + 9, 'last goblin');
    assert(parts(2) == 2 && parts(15) == 3 && parts(LAST_KIND) == 1, 'parts per kind');
}

// Fix loop 1: a counter is never 0 in storage (F-4); a high limb that would reach LIVE, or a
// bitmap above bit 249, is refused (F-9).
#[test]
#[available_gas(l2_gas: 10679)] // ceil(1.05 × 10170 measured)
fn test_counter_never_zero() {
    let zero = StorePacking::<Counter, felt252>::pack(Counter { value: 0 });
    assert(zero == LIVE, 'zero is LIVE');
    let max = Counter { value: 0xFFFFFFFFFFFFFFFF };
    let word = StorePacking::<Counter, felt252>::pack(max);
    assert(StorePacking::<Counter, felt252>::unpack(word) == max, 'round trip');
    assert(join(0, 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0, 'widest high limb');
}

#[test]
#[should_panic(expected: 'packing: high limb overflow')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_join_refuses_live_overflow() {
    join(0, 0x4000000000000000000000000000000);
}

#[test]
#[should_panic(expected: 'packing: bitmap above bit 249')]
#[available_gas(l2_gas: 10385)] // ceil(1.05 × 9890 measured)
fn test_bitmap_above_249_refused() {
    let bit250: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
    StorePacking::<Bitmap, felt252>::pack(Bitmap { bits: bit250 });
}
