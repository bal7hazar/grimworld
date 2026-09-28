use grimworld_ephemeral::systems::ephemeral::{
    IEphemeralDispatcher, IEphemeralDispatcherTrait, VERSION,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};

fn deploy() -> IEphemeralDispatcher {
    let class = declare("Ephemeral").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IEphemeralDispatcher { contract_address: address }
}

// Declares, deploys and calls the placeholder view.
#[test]
#[available_gas(l2_gas: 290997)] // ceil(1.05 × 277140 measured); includes declare and deploy
fn test_ephemeral_deploys_and_answers_version() {
    let ephemeral = deploy();
    assert(ephemeral.version() == VERSION, 'wrong version');
}
