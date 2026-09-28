use grimworld_persistent::systems::persistent::{
    IPersistentDispatcher, IPersistentDispatcherTrait, VERSION,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};

fn deploy() -> IPersistentDispatcher {
    let class = declare("Persistent").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IPersistentDispatcher { contract_address: address }
}

// Declares, deploys and calls the placeholder view.
#[test]
#[available_gas(l2_gas: 290997)] // ceil(1.05 × 277140 measured); includes declare and deploy
fn test_persistent_deploys_and_answers_version() {
    let persistent = deploy();
    assert(persistent.version() == VERSION, 'wrong version');
}
