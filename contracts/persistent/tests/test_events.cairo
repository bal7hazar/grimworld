// The nine events of the indexer (SPK-11 §1) have the keys and data of
// docs/architecture/ENG-01-interfaces.md: the selector of the name first, then the declared keys;
// the data in the declared order.
use grimworld_persistent::events::{
    AdventurerLocated, DungeonCleared, LotClosed, LotPosted, RankReached, TitleDisplayed,
    TradeClosed, TradeOpened, TrialPassed,
};
use grimworld_persistent::systems::hub::Hub;
use grimworld_persistent::systems::market::Market;

fn hub(event: Hub::Event) -> (Array<felt252>, Array<felt252>) {
    let mut keys = array![];
    let mut data = array![];
    starknet::Event::append_keys_and_data(@event, ref keys, ref data);
    (keys, data)
}

fn market(event: Market::Event) -> (Array<felt252>, Array<felt252>) {
    let mut keys = array![];
    let mut data = array![];
    starknet::Event::append_keys_and_data(@event, ref keys, ref data);
    (keys, data)
}

#[test]
#[available_gas(l2_gas: 85712)] // ceil(1.05 × 81630 measured)
fn test_hub_events() {
    let (keys, data) = hub(
        Hub::Event::AdventurerLocated(AdventurerLocated { hub: 3, adventurer: 9 }),
    );
    assert(keys == array![selector!("AdventurerLocated"), 3], 'located keys');
    assert(data == array![9], 'located data');

    let (keys, data) = hub(
        Hub::Event::TitleDisplayed(TitleDisplayed { adventurer: 9, title: 4, tier: 2 }),
    );
    assert(keys == array![selector!("TitleDisplayed"), 9], 'title keys');
    assert(data == array![4, 2], 'title data');

    let (keys, data) = hub(
        Hub::Event::TrialPassed(TrialPassed { adventurer: 9, rank: 1, first_attempt: true }),
    );
    assert(keys == array![selector!("TrialPassed"), 9], 'trial keys');
    assert(data == array![1, 1], 'trial data');

    let (keys, data) = hub(
        Hub::Event::DungeonCleared(DungeonCleared { adventurer: 9, dungeon: 6 }),
    );
    assert(keys == array![selector!("DungeonCleared"), 9], 'dungeon keys');
    assert(data == array![6], 'dungeon data');

    let (keys, data) = hub(Hub::Event::RankReached(RankReached { adventurer: 9, rank: 2 }));
    assert(keys == array![selector!("RankReached"), 9], 'rank keys');
    assert(data == array![2], 'rank data');
}

#[test]
#[available_gas(l2_gas: 82698)] // ceil(1.05 × 78760 measured)
fn test_market_events() {
    let (keys, data) = market(
        Market::Event::LotPosted(
            LotPosted {
                market_key: 77,
                lot_size: 10,
                lot: 0xFFFFFFFFFFFFFFFF,
                price: 500,
                expiry: 1000,
                equipment: 0,
                modifiers: 0,
            },
        ),
    );
    assert(keys == array![selector!("LotPosted"), 77, 10], 'posted keys');
    assert(data == array![0xFFFFFFFFFFFFFFFF, 500, 1000, 0, 0], 'posted data');

    let (keys, data) = market(Market::Event::LotClosed(LotClosed { lot: 5, sold: true }));
    assert(keys == array![selector!("LotClosed"), 5], 'closed keys');
    assert(data == array![1], 'closed data');

    let (keys, data) = market(
        Market::Event::TradeOpened(TradeOpened { invited: 12, trade: 3, inviter: 9 }),
    );
    assert(keys == array![selector!("TradeOpened"), 12], 'opened keys');
    assert(data == array![3, 9], 'opened data');

    let (keys, data) = market(Market::Event::TradeClosed(TradeClosed { trade: 3, outcome: 1 }));
    assert(keys == array![selector!("TradeClosed"), 3], 'trade closed keys');
    assert(data == array![1], 'trade closed data');
}
