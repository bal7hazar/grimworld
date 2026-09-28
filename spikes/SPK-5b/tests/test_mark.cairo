use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use spk5b::mark::{IMarkDispatcher, IMarkDispatcherTrait, Mark};
use starknet::ContractAddress;

fn deploy() -> IMarkDispatcher {
    let class = declare("Mark").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IMarkDispatcher { contract_address: address }
}

#[test]
#[available_gas(l2_gas: 1057718)] // ceil(1.05 × 1007350 measured); includes declare and deploy
fn test_mark_writes_the_value() {
    let mark = deploy();
    assert(mark.get() == 0, 'not zero at start');
    mark.mark(42);
    assert(mark.get() == 42, 'value not written');
}

#[test]
#[available_gas(l2_gas: 1023855)] // ceil(1.05 × 975100 measured); includes declare and deploy
fn test_mark_emits_marked() {
    let mark = deploy();
    let owner: ContractAddress = 'owner'.try_into().unwrap();
    let mut spy = spy_events();
    start_cheat_caller_address(mark.contract_address, owner);
    mark.mark(7);
    stop_cheat_caller_address(mark.contract_address);
    spy
        .assert_emitted(
            @array![(mark.contract_address, Mark::Event::Marked(Mark::Marked { owner, value: 7 }))],
        );
}
