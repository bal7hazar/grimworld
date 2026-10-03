// FND-05: the provider's address (and the other registered contracts) is configuration that only
// the administrator sets (ADR-0007, *Access control*); `set_admin` hands the role over. The storage
// is read with `load`: no view exposes it (ENG-01 §9.3).
use grimworld_persistent::systems::hub::{
    IHubAdminDispatcher, IHubAdminDispatcherTrait, IHubAdminSafeDispatcher,
    IHubAdminSafeDispatcherTrait, NOT_ADMIN, ZERO_ADMIN,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ADMIN: felt252 = 0xad;
const OTHER: felt252 = 0xbad;

fn deploy_hub() -> ContractAddress {
    let class = declare("Hub").unwrap().contract_class();
    let (address, _) = class.deploy(@array![ADMIN, 2, 3, 4, 5]).unwrap();
    address
}

// (admin, registry, instances, market, fate, flatten) as stored.
fn stored(hub: ContractAddress) -> (felt252, felt252, felt252, felt252, felt252, felt252) {
    (
        *load(hub, selector!("admin"), 1).at(0),
        *load(hub, selector!("registry"), 1).at(0),
        *load(hub, selector!("instances"), 1).at(0),
        *load(hub, selector!("market"), 1).at(0),
        *load(hub, selector!("fate"), 1).at(0),
        *load(hub, selector!("flatten"), 1).at(0),
    )
}

#[test]
#[available_gas(l2_gas: 5712651)] // ceil(1.05 × 5440620 measured)
fn test_hub_set_contracts_by_admin() {
    let hub = deploy_hub();
    start_cheat_caller_address(hub, ADMIN.try_into().unwrap());
    IHubAdminDispatcher { contract_address: hub }
        .set_contracts(
            0x12.try_into().unwrap(),
            0x13.try_into().unwrap(),
            0x14.try_into().unwrap(),
            0x15.try_into().unwrap(),
            0x16.try_into().unwrap(),
        );
    assert(stored(hub) == (ADMIN, 0x12, 0x13, 0x14, 0x15, 0x16), 'set by the admin');
}

#[test]
#[available_gas(l2_gas: 4510454)] // ceil(1.05 × 4295670 measured)
#[feature("safe_dispatcher")]
fn test_hub_set_contracts_refused_to_others() {
    let hub = deploy_hub();
    start_cheat_caller_address(hub, OTHER.try_into().unwrap());
    let result = IHubAdminSafeDispatcher { contract_address: hub }
        .set_contracts(
            0x12.try_into().unwrap(),
            0x13.try_into().unwrap(),
            0x14.try_into().unwrap(),
            0x15.try_into().unwrap(),
            0x16.try_into().unwrap(),
        );
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    assert(stored(hub) == (ADMIN, 2, 3, 4, 5, 0), 'unchanged');
}

// The role moves: the new administrator sets the provider, the former one no longer can.
#[test]
#[available_gas(l2_gas: 6491825)] // ceil(1.05 × 6182690 measured)
#[feature("safe_dispatcher")]
fn test_hub_set_admin_hands_over() {
    let hub = deploy_hub();
    let safe = IHubAdminSafeDispatcher { contract_address: hub };
    start_cheat_caller_address(hub, ADMIN.try_into().unwrap());
    IHubAdminDispatcher { contract_address: hub }.set_admin(0xad2.try_into().unwrap());
    let result = safe
        .set_contracts(
            2.try_into().unwrap(),
            3.try_into().unwrap(),
            4.try_into().unwrap(),
            0x66.try_into().unwrap(),
            0x67.try_into().unwrap(),
        );
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'former admin refused');
    let result = safe.set_admin(ADMIN.try_into().unwrap());
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'former admin cannot take back');
    stop_cheat_caller_address(hub);
    start_cheat_caller_address(hub, 0xad2.try_into().unwrap());
    safe
        .set_contracts(
            2.try_into().unwrap(),
            3.try_into().unwrap(),
            4.try_into().unwrap(),
            0x66.try_into().unwrap(),
            0x67.try_into().unwrap(),
        )
        .unwrap();
    assert(stored(hub) == (0xad2, 2, 3, 4, 0x66, 0x67), 'the new admin sets');
}

#[test]
#[available_gas(l2_gas: 4714605)] // ceil(1.05 × 4490100 measured)
#[feature("safe_dispatcher")]
fn test_hub_set_admin_refused() {
    let hub = deploy_hub();
    let safe = IHubAdminSafeDispatcher { contract_address: hub };
    start_cheat_caller_address(hub, OTHER.try_into().unwrap());
    assert(
        *safe.set_admin(OTHER.try_into().unwrap()).unwrap_err().at(0) == NOT_ADMIN,
        'others refused',
    );
    stop_cheat_caller_address(hub);
    start_cheat_caller_address(hub, ADMIN.try_into().unwrap());
    assert(*safe.set_admin(0.try_into().unwrap()).unwrap_err().at(0) == ZERO_ADMIN, 'zero refused');
    assert(stored(hub) == (ADMIN, 2, 3, 4, 5, 0), 'unchanged');
}
