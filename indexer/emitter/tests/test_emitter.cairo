// Each entrypoint emits exactly one event, whose raw keys and data are those of
// docs/architecture/ENG-01-interfaces.md §5 (the selector of the name first, then the declared
// keys; the data in the declared order), from the emitter's address.
use grimworld_indexer_emitter::hub::{IHubEmitterDispatcher, IHubEmitterDispatcherTrait};
use grimworld_indexer_emitter::market::{IMarketEmitterDispatcher, IMarketEmitterDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyTrait, declare, spy_events,
};
use starknet::ContractAddress;

const U64_MAX: u64 = 0xFFFFFFFFFFFFFFFF;

fn deploy(name: ByteArray) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

fn hub() -> IHubEmitterDispatcher {
    IHubEmitterDispatcher { contract_address: deploy("HubEmitter") }
}

fn market() -> IMarketEmitterDispatcher {
    IMarketEmitterDispatcher { contract_address: deploy("MarketEmitter") }
}

/// The one event the spy saw: from `from`, with exactly these keys and data.
fn assert_one(
    ref spy: EventSpy, from: ContractAddress, keys: Array<felt252>, data: Array<felt252>,
) {
    let events = spy.get_events().events;
    assert(events.len() == 1, 'one event');
    let (address, event) = events.at(0);
    assert(*address == from, 'emitter');
    assert(event.keys == @keys, 'keys');
    assert(event.data == @data, 'data');
}

#[test]
#[available_gas(l2_gas: 380594)] // ceil(1.05 × 362470 measured)
fn test_adventurer_located() {
    let hub = hub();
    let mut spy = spy_events();
    hub.adventurer_located(0xFFFF, 0xFFFFFFFF);
    assert_one(
        ref spy,
        hub.contract_address,
        array![selector!("AdventurerLocated"), 0xFFFF],
        array![0xFFFFFFFF],
    );
}

#[test]
#[available_gas(l2_gas: 380594)] // ceil(1.05 × 362470 measured)
fn test_adventurer_located_in_no_hub() {
    let hub = hub();
    let mut spy = spy_events();
    hub.adventurer_located(0, 9);
    assert_one(ref spy, hub.contract_address, array![selector!("AdventurerLocated"), 0], array![9]);
}

#[test]
#[available_gas(l2_gas: 391724)] // ceil(1.05 × 373070 measured)
fn test_title_displayed() {
    let hub = hub();
    let mut spy = spy_events();
    hub.title_displayed(9, 0xFFFF, 0xFF);
    assert_one(
        ref spy, hub.contract_address, array![selector!("TitleDisplayed"), 9], array![0xFFFF, 0xFF],
    );
}

#[test]
#[available_gas(l2_gas: 391766)] // ceil(1.05 × 373110 measured)
fn test_trial_passed() {
    let hub = hub();
    let mut spy = spy_events();
    hub.trial_passed(9, 3, true);
    assert_one(ref spy, hub.contract_address, array![selector!("TrialPassed"), 9], array![3, 1]);
}

#[test]
#[available_gas(l2_gas: 380699)] // ceil(1.05 × 362570 measured)
fn test_dungeon_cleared() {
    let hub = hub();
    let mut spy = spy_events();
    hub.dungeon_cleared(9, 6);
    assert_one(ref spy, hub.contract_address, array![selector!("DungeonCleared"), 9], array![6]);
}

#[test]
#[available_gas(l2_gas: 380594)] // ceil(1.05 × 362470 measured)
fn test_rank_reached() {
    let hub = hub();
    let mut spy = spy_events();
    hub.rank_reached(9, 2);
    assert_one(ref spy, hub.contract_address, array![selector!("RankReached"), 9], array![2]);
}

#[test]
#[available_gas(l2_gas: 440171)] // ceil(1.05 × 419210 measured)
fn test_lot_posted() {
    let market = market();
    let mut spy = spy_events();
    // Equipment: 2^40 + base 7 × 2^16 + requirement 12 × 2^8 + rarity 3 × 2 + identified.
    let key = 0x10000000000 + 7 * 0x10000 + 12 * 0x100 + 3 * 2 + 1;
    market.lot_posted(key, 1, U64_MAX, U64_MAX, U64_MAX, 0xFFFFFFFF, 0x1234);
    assert_one(
        ref spy,
        market.contract_address,
        array![selector!("LotPosted"), key, 1],
        array![U64_MAX.into(), U64_MAX.into(), U64_MAX.into(), 0xFFFFFFFF, 0x1234],
    );
}

#[test]
#[available_gas(l2_gas: 381371)] // ceil(1.05 × 363210 measured)
fn test_lot_closed() {
    let market = market();
    let mut spy = spy_events();
    market.lot_closed(5, false);
    assert_one(ref spy, market.contract_address, array![selector!("LotClosed"), 5], array![0]);
}

#[test]
#[available_gas(l2_gas: 392144)] // ceil(1.05 × 373470 measured)
fn test_trade_opened() {
    let market = market();
    let mut spy = spy_events();
    market.trade_opened(12, 3, 9);
    assert_one(
        ref spy, market.contract_address, array![selector!("TradeOpened"), 12], array![3, 9],
    );
}

#[test]
#[available_gas(l2_gas: 381014)] // ceil(1.05 × 362870 measured)
fn test_trade_closed() {
    let market = market();
    let mut spy = spy_events();
    market.trade_closed(3, 2);
    assert_one(ref spy, market.contract_address, array![selector!("TradeClosed"), 3], array![2]);
}
