// CBT-08a: the helpers of `set_build`, against plain versions (the oracles, docs/CAIRO.md §2):
// powers of two and bits, the pages of known skills, design/03's attribute points and the
// build-local attribute indices (D-157 A).
use grimworld_logic::packing::{Bitmap, LIVE};
use grimworld_persistent::helpers::BitTrait;
use grimworld_persistent::models::adventurer::{BuildTrait, KnownSkillsTrait};
use starknet::storage_access::StorePacking;

#[test]
#[available_gas(l2_gas: 20000000)]
fn test_pow2_and_bits() {
    let mut expected: u128 = 1;
    for n in 0..128_u8 {
        assert(BitTrait::pow2(n) == expected, 'pow2');
        assert(BitTrait::is_set(expected, n), 'set');
        assert(!BitTrait::is_set(~expected, n), 'clear');
        if n != 127 {
            expected *= 2;
        }
    }
    assert(BitTrait::limbs(LIVE + 5) == (5, 0x4000000000000000000000000000000), 'LIVE kept');
}

// Bit `skill % 250` of page `skill / 250`, in both limbs.
#[test]
#[available_gas(l2_gas: 2000000)]
fn test_known_skills_bits() {
    assert(KnownSkillsTrait::at(0) == (0, 0), '0');
    assert(KnownSkillsTrait::at(249) == (0, 249), '249');
    assert(KnownSkillsTrait::at(250) == (1, 0), '250');
    assert(KnownSkillsTrait::at(63999) == (255, 249), 'last page');
    // Bits 0, 127, 128, 249.
    let bits: felt252 = 1
        + 0x80000000000000000000000000000000
        + 0x100000000000000000000000000000000
        + 0x200000000000000000000000000000000000000000000000000000000000000;
    let stored: felt252 = StorePacking::pack(Bitmap { bits });
    for bit in array![0_u8, 127, 128, 249] {
        assert(KnownSkillsTrait::knows(stored, bit), 'known');
    }
    for bit in array![1_u8, 126, 129, 248] {
        assert(!KnownSkillsTrait::knows(stored, bit), 'unknown');
    }
    assert(!KnownSkillsTrait::knows(0, 0), 'never written');
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'build: skill not known')]
fn test_known_skills_past_page_255() {
    KnownSkillsTrait::at(64000);
}

// design/03's points against its rule as a loop: 5 a level up to 10, 10 from 11 to 15, 15 from 16
// to 20, 15 at Tin and 15 at Copper.
#[test]
#[available_gas(l2_gas: 20000000)]
fn test_attribute_points() {
    let mut expected: u16 = 0;
    for level in 1..21_u8 {
        if level >= 2 {
            expected +=
                if level <= 10 {
                    5
                } else if level <= 15 {
                    10
                } else {
                    15
                };
        }
        assert(BuildTrait::points(level, 0) == expected, 'wood');
        assert(BuildTrait::points(level, 1) == expected + 15, 'tin');
        assert(BuildTrait::points(level, 9) == expected + 30, 'copper and above');
    }
    assert(BuildTrait::points(20, 2) == 200, '200 at level 20');
    assert(BuildTrait::points(255, 2) == 200, 'no level above 20');
}

// D-157 A: 0-4 the primary's attributes, 5-8 the secondary's without its primary attribute.
#[test]
#[available_gas(l2_gas: 5000000)]
fn test_attribute_indices() {
    for index in 0..9_u8 {
        // A Vanguard (5) with a Warden secondary (4, so 3 at 5-7).
        assert(BuildTrait::has_attribute(index, 1, 2) == (index != 8), 'vanguard, warden');
        // A Warden (4) alone.
        assert(BuildTrait::has_attribute(index, 2, 0) == (index < 4), 'warden alone');
        // An Arcanist (5) with a Vanguard secondary (5, so 4 at 5-8).
        assert(BuildTrait::has_attribute(index, 3, 1), 'arcanist, vanguard');
    }
}
