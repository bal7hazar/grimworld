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
#[available_gas(l2_gas: 1539720)] // ceil(1.05 × 1466400 measured)
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
#[available_gas(l2_gas: 1478012)] // ceil(1.05 × 1407630 measured)
fn test_post_packs_the_largest_values() {
    let market = deploy();
    market.post(0xffffffff, 0xffff, 0xffffffffffffffff);
    assert(market.lot(1) == (0xffffffff, 0xffff, 0xffffffffffffffff, true), 'packing');
}

#[test]
#[available_gas(l2_gas: 1764137)] // ceil(1.05 × 1680130 measured)
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
#[available_gas(l2_gas: 1618775)] // ceil(1.05 × 1541690 measured)
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
#[available_gas(l2_gas: 1734296)] // ceil(1.05 × 1651710 measured)
fn test_buy_twice_fails() {
    let market = deploy();
    market.post(7, 3, 250);
    market.buy(1);
    market.buy(1);
}

#[test]
#[should_panic(expected: 'lot not open')]
#[available_gas(l2_gas: 360255)] // ceil(1.05 × 343100 measured)
fn test_buy_unknown_lot_fails() {
    let market = deploy();
    market.buy(1);
}

#[test]
#[available_gas(l2_gas: 386642)] // ceil(1.05 × 368230 measured)
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
