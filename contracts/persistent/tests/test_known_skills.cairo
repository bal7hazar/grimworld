// HUB-ROWS (#472's review, note 1): `KnownSkillsTrait::learned` sets a skill's bit whatever the
// page holds. `buy_skill` refuses a known skill before it calls `learned`, but the function itself
// must be right on its own: a bit already set stays set and the page does not change.
use grimworld_logic::helpers::packing::Bitmap;
use grimworld_persistent::models::adventurer::KnownSkillsTrait;

/// A page that knows bits 3, 127, 128 and 249 (both limbs, and the last bit of a page).
fn page() -> Bitmap {
    let mut page = Bitmap { bits: 0 };
    for bit in array![3_u8, 127, 128, 249] {
        page = KnownSkillsTrait::learned(page, bit);
    }
    page
}

#[test]
#[available_gas(l2_gas: 210057)] // ceil(1.05 × 200054 measured)
fn test_learned_a_known_bit_leaves_the_page_unchanged() {
    let before = page();
    for bit in array![3_u8, 127, 128, 249] {
        assert(KnownSkillsTrait::knows(@before, bit), 'known');
        assert(KnownSkillsTrait::learned(before, bit) == before, 'page changed');
    }
}

#[test]
#[available_gas(l2_gas: 810645)] // ceil(1.05 × 772042 measured)
fn test_learned_a_clear_bit_sets_only_that_bit() {
    let before = page();
    for bit in array![0_u8, 4, 126, 129, 248] {
        assert(!KnownSkillsTrait::knows(@before, bit), 'clear');
        let after = KnownSkillsTrait::learned(before, bit);
        assert(KnownSkillsTrait::knows(@after, bit), 'bit set');
        assert(KnownSkillsTrait::count(@after, 250) == 5, 'one more');
        for kept in array![3_u8, 127, 128, 249] {
            assert(KnownSkillsTrait::knows(@after, kept), 'kept');
        }
    }
}
