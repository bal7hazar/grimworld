// CBT-08a: what `set_build` reads of the registry. `BASE`'s fields it lays out (slot, hands, from
// bit 0 of part 0), the readers of a `SKILL`'s and an `ITEM`'s part 0 against the full unpack (the
// oracle), and design/03's attribute counts.
use grimworld_logic::content::Record;
use grimworld_logic::models::base::{Base, BaseAssert, BaseRecord, BaseTrait, slot};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class as item_class};
use grimworld_logic::models::skill::{Skill, SkillRecord, SkillTrait};
use grimworld_logic::packing::LIVE;
use grimworld_logic::professions::ProfessionTrait;

#[test]
#[available_gas(l2_gas: 1000000)]
fn test_base_round_trip() {
    let maul = BaseTrait::new(slot::WEAPON, 2);
    assert(Record::unpack(maul.pack()) == maul, 'round trip');
    assert(maul.is_two_handed() && !BaseTrait::new(slot::WEAPON, 1).is_two_handed(), 'hands');
    let feet = BaseTrait::new(slot::FEET, 0);
    assert(feet.pack() == array![7 + LIVE, LIVE].span(), 'bits: slot 0');
    assert(*maul.pack()[0] == 1 + 2 * 0x100 + LIVE, 'bits: hands 8');
    // A record never written unpacks as slot 0: no slot.
    assert(Record::<Base>::unpack(array![0, 0].span()).slot == 0, 'none');
    for s in slot::WEAPON..slot::LAST + 1 {
        let hands = if s == slot::WEAPON {
            1
        } else {
            0
        };
        BaseTrait::new(s, hands).assert_valid();
    }
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'base: slot')]
fn test_base_slot_refused() {
    BaseTrait::new(slot::LAST + 1, 0).pack();
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'base: slot')]
fn test_base_no_slot_refused() {
    BaseTrait::new(0, 0).pack();
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'base: hands')]
fn test_base_weapon_hands_refused() {
    BaseTrait::new(slot::WEAPON, 3).pack();
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'base: hands')]
fn test_base_armor_hands_refused() {
    BaseTrait::new(slot::OFF_HAND, 1).pack();
}

#[test]
#[available_gas(l2_gas: 5000000)]
fn test_skill_profile_and_item_class() {
    for profession in array![1_u8, 6, 0xFF] {
        for elite in array![false, true] {
            let skill = SkillTrait::new(
                profession, 0xFF, 0xFF, 0xFF, 0xFF, 1000, 1000, 0xFF, 3, elite,
                [Default::default(); 3],
            );
            let parts = skill.pack();
            let full: Skill = Record::unpack(parts);
            assert(SkillTrait::profile(*parts[0]) == (full.profession, full.elite), 'profile');
        }
    }
    for class in array![item_class::INGREDIENT, item_class::POTION, item_class::FAILED_BREW] {
        let item = ItemTrait::new(class, 0xFFFF, 0xFF, 0xFFFFFFFF, 0xFF, Default::default(), 0, 0);
        assert(ItemTrait::class_of(*item.pack()[0]) == class, 'class');
    }
    assert(ItemTrait::class_of(0) == 0, 'no record');
}

// design/03's attribute counts: 26 in all (D-157).
#[test]
#[available_gas(l2_gas: 200000)]
fn test_profession_attributes() {
    let mut total: u8 = 0;
    for id in 1..7_u8 {
        total += ProfessionTrait::attributes(id);
    }
    assert(total == 26, '26 attributes');
    assert(ProfessionTrait::attributes(1) == 5, 'vanguard');
    assert(ProfessionTrait::attributes(2) == 4, 'warden');
    assert(ProfessionTrait::attributes(3) == 5, 'arcanist');
}

#[test]
#[available_gas(l2_gas: 100000)]
#[should_panic(expected: 'bad profession')]
fn test_profession_attributes_none() {
    ProfessionTrait::attributes(0);
}
