use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
};
use spk11::market::{IMarketDispatcher, IMarketDispatcherTrait, Market};

fn deploy() -> IMarketDispatcher {
    let class = declare("Market").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IMarketDispatcher { contract_address: address }
}

// Every budget includes declare and deploy of the class inside the test.

#[test]
#[available_gas(l2_gas: 1539405)] // ceil(1.05 × 1466100 measured)
fn test_post_stores_and_emits() {
    let market = deploy();
    let mut spy = spy_events();
    let lot = market.post(7, 3, 250);
    assert(lot == 1, 'first lot is 1');
    assert(market.lot(1) == (7, 3, 250, true), 'lot not stored');
    spy
        .assert_emitted(
            @array![
                (
                    market.contract_address,
                    Market::Event::LotPosted(
                        Market::LotPosted { item: 7, lot: 1, quantity: 3, price: 250 },
                    ),
                ),
            ],
        );
}

#[test]
#[available_gas(l2_gas: 1425134)] // ceil(1.05 × 1357270 measured)
fn test_post_silent_stores_the_same() {
    let market = deploy();
    let lot = market.post_silent(7, 3, 250);
    assert(lot == 1, 'first lot is 1');
    assert(market.lot(1) == (7, 3, 250, true), 'lot not stored');
}

#[test]
#[available_gas(l2_gas: 1477697)] // ceil(1.05 × 1407330 measured)
fn test_post_packs_the_largest_values() {
    let market = deploy();
    market.post(0xffffffff, 0xffff, 0xffffffffffffffff);
    assert(market.lot(1) == (0xffffffff, 0xffff, 0xffffffffffffffff, true), 'packing');
}

#[test]
#[available_gas(l2_gas: 1764977)] // ceil(1.05 × 1680930 measured)
fn test_buy_closes_and_emits() {
    let market = deploy();
    market.post(7, 3, 250);
    let mut spy = spy_events();
    market.buy(1);
    assert(market.lot(1) == (7, 3, 250, false), 'lot still open');
    spy
        .assert_emitted(
            @array![
                (
                    market.contract_address,
                    Market::Event::LotClosed(Market::LotClosed { lot: 1, sold: true }),
                ),
            ],
        );
}

#[test]
#[available_gas(l2_gas: 1619615)] // ceil(1.05 × 1542490 measured)
fn test_withdraw_closes_and_emits() {
    let market = deploy();
    market.post(7, 3, 250);
    let mut spy = spy_events();
    market.withdraw(1);
    spy
        .assert_emitted(
            @array![
                (
                    market.contract_address,
                    Market::Event::LotClosed(Market::LotClosed { lot: 1, sold: false }),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'lot not open')]
#[available_gas(l2_gas: 1736301)] // ceil(1.05 × 1653620 measured)
fn test_buy_twice_fails() {
    let market = deploy();
    market.post(7, 3, 250);
    market.buy(1);
    market.buy(1);
}

#[test]
#[should_panic(expected: 'lot not open')]
#[available_gas(l2_gas: 361421)] // ceil(1.05 × 344210 measured)
fn test_buy_unknown_lot_fails() {
    let market = deploy();
    market.buy(1);
}

#[test]
#[available_gas(l2_gas: 388112)] // ceil(1.05 × 369630 measured)
fn test_locate_emits() {
    let market = deploy();
    let mut spy = spy_events();
    market.locate(42, 3);
    spy
        .assert_emitted(
            @array![
                (
                    market.contract_address,
                    Market::Event::AdventurerLocated(
                        Market::AdventurerLocated { hub: 3, adventurer: 42 },
                    ),
                ),
            ],
        );
}

#[test]
#[available_gas(l2_gas: 1669668)] // ceil(1.05 × 1590160 measured)
fn test_withdraw_silent_closes_without_event() {
    let market = deploy();
    market.post(7, 3, 250);
    market.withdraw_silent(1);
    assert(market.lot(1) == (7, 3, 250, false), 'lot still open');
}

#[test]
#[available_gas(l2_gas: 292971)] // ceil(1.05 × 279020 measured)
fn test_locate_silent_does_nothing() {
    let market = deploy();
    market.locate_silent(42, 3);
}

#[test]
#[available_gas(l2_gas: 2134997)] // ceil(1.05 × 2033330 measured)
fn test_skip_lots_announces_and_moves_the_counter() {
    let market = deploy();
    let mut spy = spy_events();
    market.skip_lots(0xfffffffffffffffe);
    assert(market.lot_count() == 0xfffffffffffffffe, 'counter not set');
    let lot = market.post(7, 1, 0xffffffffffffffff);
    assert(lot == 0xffffffffffffffff, 'largest lot id');
    assert(market.lot(lot) == (7, 1, 0xffffffffffffffff, true), 'largest lot');
    market.buy(lot);
    spy
        .assert_emitted(
            @array![
                (
                    market.contract_address,
                    Market::Event::LotCountSet(Market::LotCountSet { count: 0xfffffffffffffffe }),
                ),
                (
                    market.contract_address,
                    Market::Event::LotClosed(Market::LotClosed { lot, sold: true }),
                ),
            ],
        );
}

#[test]
#[available_gas(l2_gas: 2119898)] // ceil(1.05 × 2018950 measured)
fn test_lot_count_counts_every_lot() {
    let market = deploy();
    market.post(7, 1, 1);
    market.post_silent(7, 1, 1);
    assert(market.lot_count() == 2, 'two lots');
}
