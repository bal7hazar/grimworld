// The storage records of `Hub` and `Market` are what docs/architecture/ENG-01-interfaces.md says:
// each record's size in slots, the bit offsets of every packed record, LIVE included, and the
// market key. The variables' names and keys are checked in each contract's `layout_tests`.
use grimworld_logic::models::base::{BaseTrait, slot};
use grimworld_logic::packing::LIVE;
use grimworld_persistent::models::account::{Account, AccountRecord, PACK, VAULT, owner_key};
use grimworld_persistent::models::adventurer::{Adventurer, AdventurerCore, AdventurerPlace, Build};
use grimworld_persistent::models::item::{
    Gold, Grimoire, GrimoireState, IDENTIFIED, Item, ItemBase, ItemBaseTrait, ItemMods, Modifier,
    Pairs, RiftBoard,
};
use grimworld_persistent::models::market::{
    BALANCE, EQUIPMENT, Lot, SellerPage, Trade, TradeHead, TradeMoney, market_key,
};
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_record_sizes() {
    assert(starknet::Store::<Account>::size() == 2, 'account: 2 slots');
    assert(starknet::Store::<Adventurer>::size() == 6, 'adventurer: 6 slots');
    assert(starknet::Store::<Item>::size() == 2, 'item: 2 slots');
    assert(starknet::Store::<Grimoire>::size() == 3, 'grimoire: 3 slots');
    assert(starknet::Store::<Trade>::size() == 5, 'trade: 5 slots');
    assert(starknet::Store::<Lot>::size() == 1, 'lot: 1 slot');
}

#[test]
#[available_gas(l2_gas: 335066)] // ceil(1.05 × 319110 measured)
fn test_account_and_adventurer_layout() {
    let record = AccountRecord {
        slots: 3, adventurers: 2, highest_rank: 9, vault_panes: 4, lots: 20,
    };
    let word = StorePacking::<AccountRecord, felt252>::pack(record);
    assert(StorePacking::<AccountRecord, felt252>::unpack(word) == record, 'account trip');
    assert(owner_key(VAULT, 7) == 2 * 0x100000000 + 7, 'owner key');

    let core = AdventurerCore {
        account: 0xFFFFFFFF,
        experience: 140600,
        merit: 50000,
        level: 20,
        rank: 9,
        profession: 3,
        secondary: 6,
        unspent: 200,
        trials_first: 0x3FF,
        trials_tried: 0x3FF,
        status: 1,
        pack_lanes: 0xFFFF,
    };
    let word = StorePacking::<AdventurerCore, felt252>::pack(core);
    assert(StorePacking::<AdventurerCore, felt252>::unpack(word) == core, 'core trip');
    let rank = AdventurerCore { rank: 1, ..Default::default() };
    assert(
        StorePacking::<AdventurerCore, felt252>::pack(rank) == 0x100000000000000000000000000 + LIVE,
        'rank at bit 104',
    );

    let place = AdventurerPlace {
        instance: 0xFFFFFFFFFFFFFFFF,
        hub: 1,
        last_hub: 0xFFFF,
        inside: 1,
        unlocked: 0xFFFFFFFFFFFFFFFF,
    };
    let word = StorePacking::<AdventurerPlace, felt252>::pack(place);
    assert(StorePacking::<AdventurerPlace, felt252>::unpack(word) == place, 'place trip');

    let build = Build {
        bar: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], attributes: 0xFFFFFFFFF, elite_slot: 255,
    };
    let word = StorePacking::<Build, felt252>::pack(build);
    assert(StorePacking::<Build, felt252>::unpack(word) == build, 'build trip');
    let attributes = Build { bar: [0; 8], attributes: 1, elite_slot: 0 };
    assert(StorePacking::<Build, felt252>::pack(attributes) == TWO_128 + LIVE, 'attributes at 128');
}

#[test]
// gas: raised, D-158: `ItemBase` gains slot and hands, packed and unpacked in the round trip
#[available_gas(l2_gas: 367584)] // ceil(1.05 × 350080 measured)
fn test_item_grimoire_rift_layout() {
    let base = ItemBase {
        base: 0xFFFF,
        requirement: 9,
        rarity: 4,
        level: 28,
        flags: 15,
        look: 0xFFFF,
        set: 0xFFFF,
        owner_kind: 3,
        owner: 0xFFFFFFFF,
        slot: 15,
        hands: 15,
    };
    let word = StorePacking::<ItemBase, felt252>::pack(base);
    assert(StorePacking::<ItemBase, felt252>::unpack(word) == base, 'base trip');
    let owner = ItemBase { owner: 1, ..Default::default() };
    assert(
        StorePacking::<ItemBase, felt252>::pack(owner) == 0x10000000000000000000000 + LIVE,
        'owner at bit 88',
    );

    let full = Modifier { id: 0xFFFF, value: 0xFF };
    let mods = ItemMods { mods: [full, Modifier { id: 1, value: 2 }, full, full, full] };
    let word = StorePacking::<ItemMods, felt252>::pack(mods);
    assert(StorePacking::<ItemMods, felt252>::unpack(word) == mods, 'mods trip');

    let state = GrimoireState {
        known: 0xFFFF, remaining: 0xFFFFFFFFFFFF, hints: 0xFFFFFFFFFFFFFFFF,
    };
    let word = StorePacking::<GrimoireState, felt252>::pack(state);
    assert(StorePacking::<GrimoireState, felt252>::unpack(word) == state, 'grimoire trip');
    let pairs = Pairs {
        low: 0x1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
    };
    let word = StorePacking::<Pairs, felt252>::pack(pairs);
    assert(StorePacking::<Pairs, felt252>::unpack(word) == pairs, 'pairs trip');

    let gold = Gold { amount: 0xFFFFFFFFFFFFFFFF };
    let word = StorePacking::<Gold, felt252>::pack(gold);
    assert(StorePacking::<Gold, felt252>::unpack(word) == gold, 'gold trip');
    assert(StorePacking::<Gold, felt252>::pack(Gold { amount: 0 }) == LIVE, 'no gold is not 0');

    let board = RiftBoard { day: 20725, cleared: 0x1F, rifts: [1, 2, 3, 4, 0xFFFF] };
    let word = StorePacking::<RiftBoard, felt252>::pack(board);
    assert(StorePacking::<RiftBoard, felt252>::unpack(word) == board, 'rift trip');
}

#[test]
#[available_gas(l2_gas: 207449)] // ceil(1.05 × 197570 measured)
fn test_market_layout() {
    let lot = Lot {
        price: 0xFFFFFFFFFFFFFFFF,
        expiry: 0xFFFFFFFFFFFFFFFF,
        seller: 0xFFFFFFFF,
        lot_size: 100,
        state: 4,
        kind: EQUIPMENT,
        item: 0xFFFFFFFF,
        market: 0xFFFF,
    };
    let word = StorePacking::<Lot, felt252>::pack(lot);
    assert(StorePacking::<Lot, felt252>::unpack(word) == lot, 'lot trip');
    let seller = Lot { seller: 1, ..Default::default() };
    assert(StorePacking::<Lot, felt252>::pack(seller) == TWO_128 + LIVE, 'seller at bit 128');

    let page = SellerPage { lots: [1, 0xFFFFFFFFFFFFFFFF, 3], count: 20 };
    let word = StorePacking::<SellerPage, felt252>::pack(page);
    assert(StorePacking::<SellerPage, felt252>::unpack(word) == page, 'seller page trip');

    let head = TradeHead {
        inviter: 1,
        invited_account: 2,
        invited: 3,
        state: 1,
        confirmations: 3,
        revision: 0xFF,
        opened_at: 0xFFFFFFFFFFFFFFFF,
    };
    let word = StorePacking::<TradeHead, felt252>::pack(head);
    assert(StorePacking::<TradeHead, felt252>::unpack(word) == head, 'trade head trip');

    let money = TradeMoney {
        gold: 0xFFFFFFFFFFFFFFFF, item0: 1, amount0: 2, item1: 0xFFFFFFFF, amount1: 0xFFFFFFFF,
    };
    let word = StorePacking::<TradeMoney, felt252>::pack(money);
    assert(StorePacking::<TradeMoney, felt252>::unpack(word) == money, 'money trip');

    // SPK-11 *scope 5*: balances by item id; equipment by base, requirement, rarity, identified;
    // boss items one key each.
    assert(market_key(BALANCE, 77, 0, 0, 0, false, false) == 77, 'balance key');
    assert(
        market_key(EQUIPMENT, 5, 12, 9, 3, true, false) == 0x10000000000
            + 12 * 0x10000
            + 9 * 0x100
            + 3 * 2
            + 1,
        'equipment key',
    );
    assert(market_key(EQUIPMENT, 5, 40, 9, 4, true, true) == 0x20000000000 + 40, 'boss key');
}

// Fix loop 1, F-9: fields narrower than their type are refused when too wide.
#[test]
#[should_panic(expected: 'packing: attributes above 36 b')]
#[available_gas(l2_gas: 43418)] // ceil(1.05 × 41350 measured)
fn test_attributes_above_36_bits_refused() {
    StorePacking::<
        Build, felt252,
    >::pack(Build { bar: [0; 8], attributes: 0x1000000000, elite_slot: 0 });
}

#[test]
#[should_panic(expected: 'packing: pairs 25-48 overflow')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_pairs_overflow_refused() {
    StorePacking::<Pairs, felt252>::pack(Pairs { low: 0, high: 0x1000000000000000000000000000000 });
}

// CBT-08a, D-158: `ItemBase.slot` at bit 120 and `hands` at 124, 4 bits each, copied from the
// `BASE` record by the constructor every creator of an item calls.
#[test]
#[available_gas(l2_gas: 189693)] // ceil(1.05 × 180660 measured)
fn test_item_slot_and_hands() {
    let one = ItemBase { slot: 1, ..Default::default() };
    assert(
        StorePacking::<ItemBase, felt252>::pack(one) == 0x1000000000000000000000000000000 + LIVE,
        'slot at bit 120',
    );
    let two = ItemBase { hands: 1, ..Default::default() };
    assert(
        StorePacking::<ItemBase, felt252>::pack(two) == 0x10000000000000000000000000000000 + LIVE,
        'hands at bit 124',
    );
    let maul = BaseTrait::new(slot::WEAPON, 2);
    let item = ItemBaseTrait::new(7, @maul, 9, 1, 20, IDENTIFIED, 3, 0, PACK, 5);
    let expected = ItemBase {
        base: 7,
        requirement: 9,
        rarity: 1,
        level: 20,
        flags: IDENTIFIED,
        look: 3,
        set: 0,
        owner_kind: PACK,
        owner: 5,
        slot: slot::WEAPON,
        hands: 2,
    };
    assert(item == expected, 'copied from the base');
    assert(item.is_two_handed(), 'two hands');
    let feet = ItemBaseTrait::new(8, @BaseTrait::new(slot::FEET, 0), 0, 0, 1, 0, 0, 0, PACK, 5);
    assert(feet.slot == slot::FEET && feet.hands == 0 && !feet.is_two_handed(), 'feet');
    let word = StorePacking::<ItemBase, felt252>::pack(item);
    assert(StorePacking::<ItemBase, felt252>::unpack(word) == item, 'round trip');
}

#[test]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
#[should_panic(expected: 'packing: slot above 4 b')]
fn test_item_slot_too_wide() {
    StorePacking::<ItemBase, felt252>::pack(ItemBase { slot: 16, ..Default::default() });
}

#[test]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
#[should_panic(expected: 'packing: hands above 4 b')]
fn test_item_hands_too_wide() {
    StorePacking::<ItemBase, felt252>::pack(ItemBase { hands: 16, ..Default::default() });
}
