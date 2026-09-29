// `Instances` declares and deploys; its entrypoints are stubs that revert with 'not implemented'
// until their lots write them. Also the probe of a call between contracts (ENG-01, *Registry
// reads*): the same eight records read directly, then through one more contract.
use grimworld_ephemeral::probes::{
    ICallProbeDispatcher, ICallProbeDispatcherTrait, IEventProbeDispatcher,
    IEventProbeDispatcherTrait,
};
use grimworld_ephemeral::systems::instances::{
    IInstancesAdminDispatcher, IInstancesAdminDispatcherTrait, IInstancesSafeDispatcher,
    IInstancesSafeDispatcherTrait, NOT_IMPLEMENTED, VERSION,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

fn deploy_instances() -> ContractAddress {
    let class = declare("Instances").unwrap().contract_class();
    let (address, _) = class.deploy(@array![1, 2, 3, 4]).unwrap();
    address
}

#[test]
// gas: raised, CBT-01: the snapshot carries design/19 section 7.2's passives (FX-24), a larger Serde and packing at create
#[available_gas(l2_gas: 2783508)] // ceil(1.05 × 2650960 measured)
fn test_instances_deploys_and_stubs_revert() {
    let address = deploy_instances();
    assert(IInstancesAdminDispatcher { contract_address: address }.version() == VERSION, 'version');
    let safe = IInstancesSafeDispatcher { contract_address: address };
    #[feature("safe_dispatcher")]
    let played = safe.play(0x100000001, 1, 0, 3, 1);
    assert(*played.unwrap_err().at(0) == NOT_IMPLEMENTED, 'play is a stub');
}

fn two_probes() -> (ICallProbeDispatcher, ICallProbeDispatcher) {
    let class = declare("CallProbe").unwrap().contract_class();
    let (a, _) = class.deploy(@array![]).unwrap();
    let (b, _) = class.deploy(@array![]).unwrap();
    let b = ICallProbeDispatcher { contract_address: b };
    for key in 0..8_u32 {
        b.set(key, key.into() + 1);
    }
    (ICallProbeDispatcher { contract_address: a }, b)
}

// Eight records read by one call to their contract (the baseline of the pair).
#[test]
#[available_gas(l2_gas: 5349960)] // ceil(1.05 × 5095200 measured)
fn test_probe_read_direct() {
    let (_, b) = two_probes();
    assert(b.records(0, 8).len() == 8, 'eight');
}

// The same eight records through one more contract: the difference with the baseline is the
// price of one call between contracts (snforge's meter).
#[test]
#[available_gas(l2_gas: 5473766)] // ceil(1.05 × 5213110 measured)
fn test_probe_read_through_a_call() {
    let (a, b) = two_probes();
    assert(a.records_of(b.contract_address, 0, 8).len() == 8, 'eight');
}

fn event_probe() -> IEventProbeDispatcher {
    let class = declare("EventProbe").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IEventProbeDispatcher { contract_address: address }
}

// Fix loop 1, F-7: the price of the per-action events, as the difference between the same call
// with and without them (snforge's meter). The baseline: no event.
#[test]
#[available_gas(l2_gas: 296793)] // ceil(1.05 × 282660 measured)
fn test_probe_events_none() {
    event_probe().fire(0, 0);
}

// Eight `GoblinKilled` (a batch's worst kills at one tick).
#[test]
#[available_gas(l2_gas: 773409)] // ceil(1.05 × 736580 measured)
fn test_probe_events_eight_killed() {
    event_probe().fire(8, 0);
}

// Four `ChunkRevealed` (a batch's most reveals: weight 10 allows 4 chunks).
#[test]
#[available_gas(l2_gas: 464993)] // ceil(1.05 × 442850 measured)
fn test_probe_events_four_revealed() {
    event_probe().fire(0, 4);
}
