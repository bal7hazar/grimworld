// The storage records of `Market` are what docs/architecture/ENG-01-interfaces.md says: each
// record's size in slots, the bit offsets of its packed records, LIVE included, and the market key.
// Here, not in `models::market`, until ENG-R1b moves `Market`'s tests beside its models (D-167: a
// lot moves the tests of the modules it touches, and ENG-R1a does not touch `models::market`). The
// records of `Hub` are checked in their models' tests (ENG-R1a), the variables' names and keys in
// `store::layout_tests` and `Market`'s `layout_tests`.
use grimworld_logic::packing::LIVE;
use grimworld_persistent::models::market::{
    BALANCE, EQUIPMENT, Lot, SellerPage, Trade, TradeHead, TradeMoney, market_key,
};
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_record_sizes() {
    assert(starknet::Store::<Trade>::size() == 5, 'trade: 5 slots');
    assert(starknet::Store::<Lot>::size() == 1, 'lot: 1 slot');
}

#[test]
#[available_gas(l2_gas: 197715)] // ceil(1.05 × 188300 measured)
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
