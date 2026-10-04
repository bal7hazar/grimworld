// FND-05: the provider's address (and the hub and registry) is configuration that only the
// administrator sets (ADR-0007, *Access control*); `set_admin` hands the role over. The storage is
// read with `load`: no view exposes it (ENG-01 §9.3).
use grimworld_ephemeral::systems::instances::{
    IInstancesAdminDispatcher, IInstancesAdminDispatcherTrait, IInstancesAdminSafeDispatcher,
    IInstancesAdminSafeDispatcherTrait, NOT_ADMIN, ZERO_ADMIN,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ADMIN: felt252 = 0xad;
const OTHER: felt252 = 0xbad;

fn deploy_instances() -> ContractAddress {
    let class = declare("Instances").unwrap().contract_class();
    let (address, _) = class.deploy(@array![ADMIN, 2, 3, 4, 5, 6]).unwrap();
    address
}

// (admin, hub, registry, fate, reveal, hosts_library) as stored.
fn stored(instances: ContractAddress) -> (felt252, felt252, felt252, felt252, felt252, felt252) {
    (
        *load(instances, selector!("admin"), 1).at(0),
        *load(instances, selector!("hub"), 1).at(0),
        *load(instances, selector!("registry"), 1).at(0),
        *load(instances, selector!("fate"), 1).at(0),
        *load(instances, selector!("reveal"), 1).at(0),
        *load(instances, selector!("hosts_library"), 1).at(0),
    )
}

#[test]
// gas: raised, ENG-05: D-210, HostsLibrary wired into Instances
#[available_gas(l2_gas: 4240341)] // ceil(1.05 × 4038420 measured)
fn test_instances_set_contracts_by_admin() {
    let instances = deploy_instances();
    start_cheat_caller_address(instances, ADMIN.try_into().unwrap());
    IInstancesAdminDispatcher { contract_address: instances }
        .set_contracts(
            0x12.try_into().unwrap(),
            0x13.try_into().unwrap(),
            0x14.try_into().unwrap(),
            0x15.try_into().unwrap(),
            0x16.try_into().unwrap(),
        );
    assert(stored(instances) == (ADMIN, 0x12, 0x13, 0x14, 0x15, 0x16), 'set by the admin');
}

#[test]
// gas: raised, ENG-05: D-210, HostsLibrary wired into Instances
#[available_gas(l2_gas: 3978744)] // ceil(1.05 × 3789280 measured)
#[feature("safe_dispatcher")]
fn test_instances_set_contracts_refused_to_others() {
    let instances = deploy_instances();
    start_cheat_caller_address(instances, OTHER.try_into().unwrap());
    let result = IInstancesAdminSafeDispatcher { contract_address: instances }
        .set_contracts(
            0x12.try_into().unwrap(),
            0x13.try_into().unwrap(),
            0x14.try_into().unwrap(),
            0x15.try_into().unwrap(),
            0x16.try_into().unwrap(),
        );
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    assert(stored(instances) == (ADMIN, 2, 3, 4, 5, 6), 'unchanged');
}

// The role moves: the new administrator sets the provider, the former one no longer can.
#[test]
// gas: raised, ENG-05: D-210, HostsLibrary wired into Instances
#[available_gas(l2_gas: 4965881)] // ceil(1.05 × 4729410 measured)
#[feature("safe_dispatcher")]
fn test_instances_set_admin_hands_over() {
    let instances = deploy_instances();
    let safe = IInstancesAdminSafeDispatcher { contract_address: instances };
    start_cheat_caller_address(instances, ADMIN.try_into().unwrap());
    IInstancesAdminDispatcher { contract_address: instances }.set_admin(0xad2.try_into().unwrap());
    let result = safe
        .set_contracts(
            2.try_into().unwrap(),
            3.try_into().unwrap(),
            0x66.try_into().unwrap(),
            5.try_into().unwrap(),
            6.try_into().unwrap(),
        );
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'former admin refused');
    let result = safe.set_admin(ADMIN.try_into().unwrap());
    assert(*result.unwrap_err().at(0) == NOT_ADMIN, 'former admin cannot take back');
    stop_cheat_caller_address(instances);
    start_cheat_caller_address(instances, 0xad2.try_into().unwrap());
    safe
        .set_contracts(
            2.try_into().unwrap(),
            3.try_into().unwrap(),
            0x66.try_into().unwrap(),
            5.try_into().unwrap(),
            6.try_into().unwrap(),
        )
        .unwrap();
    assert(stored(instances) == (0xad2, 2, 3, 0x66, 5, 6), 'the new admin sets');
}

#[test]
// gas: raised, ENG-05: D-210, HostsLibrary wired into Instances
#[available_gas(l2_gas: 4236530)] // ceil(1.05 × 4034790 measured)
#[feature("safe_dispatcher")]
fn test_instances_set_admin_refused() {
    let instances = deploy_instances();
    let safe = IInstancesAdminSafeDispatcher { contract_address: instances };
    start_cheat_caller_address(instances, OTHER.try_into().unwrap());
    assert(
        *safe.set_admin(OTHER.try_into().unwrap()).unwrap_err().at(0) == NOT_ADMIN,
        'others refused',
    );
    stop_cheat_caller_address(instances);
    start_cheat_caller_address(instances, ADMIN.try_into().unwrap());
    assert(*safe.set_admin(0.try_into().unwrap()).unwrap_err().at(0) == ZERO_ADMIN, 'zero refused');
    assert(stored(instances) == (ADMIN, 2, 3, 4, 5, 6), 'unchanged');
}
