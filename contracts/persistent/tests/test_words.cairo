// ENG-06: the stored words `Hub` changes by arithmetic, pinned against their packers (the oracle,
// docs/CAIRO.md §2): the place (entering, moving, located, unlocked), the core (`pack_lanes`,
// experience), the belt, the pages of balances.
use grimworld_logic::packing::{LIVE, Lanes32};
use grimworld_persistent::models::adventurer::{
    AdventurerCore, AdventurerCoreTrait, AdventurerPlace, AdventurerPlaceTrait, BeltTrait,
};
use grimworld_persistent::models::balance::BalanceTrait;
use starknet::storage_access::StorePacking;

fn pack_place(place: AdventurerPlace) -> felt252 {
    StorePacking::pack(place)
}

#[test]
#[available_gas(l2_gas: 2680404)] // ceil(1.05 × 2552765 measured)
fn test_place_words() {
    let start = AdventurerPlace { instance: 0, hub: 5, last_hub: 5, inside: 0, unlocked: 0x20 };
    let word = AdventurerPlaceTrait::new(5);
    assert(word == pack_place(start), 'new');
    assert(AdventurerPlaceTrait::fields(word) == (0, 5, 5, false), 'fields');

    let unlocked = AdventurerPlace { unlocked: 0x8000000000000021, ..start };
    let word = pack_place(unlocked);
    let id: u64 = 0xFFFFFFFF00000007;
    let inside = AdventurerPlace { instance: id, hub: 0, last_hub: 5, inside: 1, ..unlocked };
    let entered = AdventurerPlaceTrait::entered(word, id);
    assert(entered == pack_place(inside), 'entered');
    assert(AdventurerPlaceTrait::fields(entered) == (id, 0, 5, true), 'inside fields');

    let next: u64 = 0x100000008;
    let moved = AdventurerPlaceTrait::moved(entered, next);
    assert(moved == pack_place(AdventurerPlace { instance: next, ..inside }), 'moved');

    let located = AdventurerPlaceTrait::located(moved, 9);
    let back = AdventurerPlace { instance: 0, hub: 9, last_hub: 9, inside: 0, ..unlocked };
    assert(located == pack_place(back), 'located');
    assert(!AdventurerPlaceTrait::is_unlocked(located, 9), 'not yet');
    let opened = AdventurerPlaceTrait::unlocked(located, 9);
    assert(
        opened == pack_place(AdventurerPlace { unlocked: 0x8000000000000221, ..back }), 'unlock',
    );
    assert(AdventurerPlaceTrait::is_unlocked(opened, 9), 'unlocked');
    assert(AdventurerPlaceTrait::is_unlocked(opened, 63), 'bit 63');
    assert(!AdventurerPlaceTrait::is_unlocked(opened, 64), 'no hub 64');
    assert(AdventurerPlaceTrait::unlocked(opened, 9) == opened, 'twice');
    for hub in 0..64_u16 {
        let bit: u128 = AdventurerPlaceTrait::bit(hub);
        assert(bit == core::num::traits::Pow::pow(2_u128, hub.into()), 'bit table');
    }
}

#[test]
#[should_panic(expected: 'hub above 63')]
#[available_gas(l2_gas: 23783)] // ceil(1.05 × 22650 measured)
fn test_place_hub_above_63_refused() {
    AdventurerPlaceTrait::new(64);
}

#[test]
#[available_gas(l2_gas: 181598)] // ceil(1.05 × 172950 measured)
fn test_core_words() {
    let core = AdventurerCore {
        account: 3,
        experience: 100,
        level: 4,
        rank: 2,
        profession: 3,
        pack_lanes: 7,
        ..Default::default(),
    };
    let word: felt252 = StorePacking::pack(core);
    assert(AdventurerCoreTrait::profile(word) == (100, 4, 2, 3), 'profile');
    let changed = AdventurerCoreTrait::with_pack_lanes(word, 2, 5);
    assert(changed == StorePacking::pack(AdventurerCore { pack_lanes: 4, ..core }), 'lanes');
    let more = AdventurerCoreTrait::with_experience(word, 0xFFFFFFFF - 100);
    assert(more == StorePacking::pack(AdventurerCore { experience: 0xFFFFFFFF, ..core }), 'xp');
}

#[test]
#[should_panic(expected: 'experience overflow')]
#[available_gas(l2_gas: 78288)] // ceil(1.05 × 74560 measured)
fn test_experience_overflow_refused() {
    let word: felt252 = StorePacking::pack(
        AdventurerCore { experience: 100, ..Default::default() },
    );
    AdventurerCoreTrait::with_experience(word, 0xFFFFFFFF - 99);
}

#[test]
#[available_gas(l2_gas: 90479)] // ceil(1.05 × 86170 measured)
fn test_belt_word() {
    let counts: u32 = 0xFF + 0x2 * 0x100 + 0x3 * 0x10000 + 0x80 * 0x1000000;
    let belt = Lanes32 { lanes: [0xFFFFFFFF, 2, 3, 0x12345678, counts, 0, 0] };
    let (items, amounts) = BeltTrait::read(StorePacking::pack(belt));
    assert(items == [0xFFFFFFFF, 2, 3, 0x12345678], 'items');
    assert(amounts == [0xFF, 2, 3, 0x80], 'counts');
    assert(BeltTrait::read(0) == ([0; 4], [0; 4]), 'never written');
}

#[test]
#[available_gas(l2_gas: 292026)] // ceil(1.05 × 278120 measured)
fn test_balance_pages() {
    assert(BalanceTrait::at(0) == (0, 0) && BalanceTrait::at(13) == (1, 6), 'at');
    assert(BalanceTrait::at(0xFFFFFFFF) == (0x24924924, 3), 'at the top');
    let page = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
    let word: felt252 = StorePacking::pack(page);
    for lane in 0..7_u8 {
        assert(BalanceTrait::amount(word, lane) == *page.lanes.span()[lane.into()], 'amount');
    }
    // A credit on a page never written sets `LIVE`, and fills its lane.
    let (credited, filled) = BalanceTrait::credit(0, 4, 9);
    assert(credited == StorePacking::pack(Lanes32 { lanes: [0, 0, 0, 0, 9, 0, 0] }), 'fresh page');
    assert(filled, 'filled');
    let (credited, filled) = BalanceTrait::credit(word, 6, 1);
    let expected = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFF] };
    assert(credited == StorePacking::pack(expected) && !filled, 'credit to the top');
    let (debited, emptied) = BalanceTrait::debit(word, 0, 1);
    let expected = Lanes32 { lanes: [0, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
    assert(debited == StorePacking::pack(expected) && emptied, 'debit to 0');
    let (debited, emptied) = BalanceTrait::debit(word, 1, 5);
    let expected = Lanes32 { lanes: [1, 0xFFFFFFFA, 3, 0, 5, 6, 0xFFFFFFFE] };
    assert(debited == StorePacking::pack(expected) && !emptied, 'partial debit');
    let (unchanged, emptied) = BalanceTrait::debit(word, 3, 0);
    assert(unchanged == word && !emptied, 'nothing debited');
    assert(StorePacking::pack(Lanes32 { lanes: [0; 7] }) == LIVE, 'an empty page is live');
}

#[test]
#[should_panic(expected: 'balance: not enough')]
#[available_gas(l2_gas: 47355)] // ceil(1.05 × 45100 measured)
fn test_debit_too_much_refused() {
    let word: felt252 = StorePacking::pack(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] });
    BalanceTrait::debit(word, 2, 4);
}

#[test]
#[should_panic(expected: 'balance: overflow')]
#[available_gas(l2_gas: 47670)] // ceil(1.05 × 45400 measured)
fn test_credit_overflow_refused() {
    let word: felt252 = StorePacking::pack(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 0xFFFFFFFF] });
    BalanceTrait::credit(word, 6, 1);
}

// The belt's slots merged: one change per distinct item, counts summed, empty slots skipped.
#[test]
#[available_gas(l2_gas: 544488)] // ceil(1.05 × 518560 measured)
fn test_belt_merge() {
    assert(BalanceTrait::merge([4, 9, 4, 4], [1, 2, 3, 0]) == array![(4, 4), (9, 2)], 'merged');
    assert(BalanceTrait::merge([4, 4, 4, 4], [0, 0, 0, 5]) == array![(4, 5)], 'last slot');
    assert(BalanceTrait::merge([1, 2, 3, 4], [0; 4]) == array![], 'empty belt');
    assert(
        BalanceTrait::merge(
            [1, 2, 3, 4], [255; 4],
        ) == array![(1, 255), (2, 255), (3, 255), (4, 255)],
        'four items',
    );
}
