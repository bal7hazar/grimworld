// The storage records of `Hub` and `Market` are what docs/architecture/ENG-01-interfaces.md says:
// each record's size in slots, the bit offsets of every packed record, LIVE included, and the
// market key. The variables' names and keys are checked in each contract's `layout_tests`.
use grimworld_logic::packing::LIVE;
use grimworld_persistent::models::account::{Account, AccountRecord, VAULT, owner_key};
use grimworld_persistent::models::adventurer::{Adventurer, AdventurerCore, AdventurerPlace, Build};
use grimworld_persistent::models::item::{
    Gold, Grimoire, GrimoireState, Item, ItemBase, ItemMods, Modifier, Pairs, RiftBoard,
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
#[available_gas(l2_gas: 321395)] // ceil(1.05 × 306090 measured)
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
#[available_gas(l2_gas: 340694)] // ceil(1.05 × 324470 measured)
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
#[available_gas(l2_gas: 206871)] // ceil(1.05 × 197020 measured)
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
