// D-145: where `bundle`'s price of about 36,000 L2 gas a slot goes, the call between contracts
// against the read itself (docs/decisions/2026-09-29-eng-03-registry.md, decision 2). A probe
// contract reads one-part `GATE` records from the real `Registry` through one call or several, and
// reads the same number of its own storage slots without any call. Every test has the same setup
// (a registry with eight gates, the probe); the probe's one call is measured with
// `get_available_gas` around it (printed), and the whole tests differ only by it. ENG-06's report
// derives the call's share and the read's share from these figures.
use core::testing::get_available_gas;
use grimworld_logic::content::GATE;
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IReadProbe<T> {
    /// Nothing: the price of calling the probe itself.
    fn nothing(self: @T, registry: ContractAddress);
    /// One call, one read: `content_version`.
    fn version(self: @T, registry: ContractAddress) -> u32;
    /// One call of `bundle` for gates `1 ..= count`: `count` slots and the version.
    fn bundle(self: @T, registry: ContractAddress, count: u32) -> u32;
    /// `count` calls of `record`, one gate each.
    fn calls(self: @T, registry: ContractAddress, count: u32) -> u32;
    /// `count` reads of the probe's own storage, no call.
    fn local(self: @T, count: u32) -> felt252;
}

#[starknet::contract]
mod ReadProbe {
    use grimworld_logic::content::GATE;
    use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess};

    #[storage]
    struct Storage {
        slots: Map<u32, felt252>,
    }

    #[abi(embed_v0)]
    impl ProbeImpl of super::IReadProbe<ContractState> {
        fn nothing(self: @ContractState, registry: ContractAddress) {}
        fn version(self: @ContractState, registry: ContractAddress) -> u32 {
            IRegistryReadDispatcher { contract_address: registry }.content_version()
        }
        fn bundle(self: @ContractState, registry: ContractAddress, count: u32) -> u32 {
            let mut requests = array![];
            for id in 1..count + 1 {
                requests.append((GATE, id));
            }
            let (_, parts) = IRegistryReadDispatcher { contract_address: registry }
                .bundle(requests.span());
            parts.len()
        }
        fn calls(self: @ContractState, registry: ContractAddress, count: u32) -> u32 {
            let registry = IRegistryReadDispatcher { contract_address: registry };
            let mut read = 0;
            for id in 1..count + 1 {
                read += registry.record(GATE, id).len();
            }
            read
        }
        fn local(self: @ContractState, count: u32) -> felt252 {
            let mut sum = 0;
            for key in 1..count + 1 {
                sum += self.slots.read(key);
            }
            sum
        }
    }
}

const ADMIN: felt252 = 0xad;

fn setup() -> (IReadProbeDispatcher, ContractAddress) {
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![ADMIN]).unwrap();
    start_cheat_caller_address(registry, ADMIN.try_into().unwrap());
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    for id in 1..9_u32 {
        let record = GateTrait::new(1, 2, 0, 0, 0, id.try_into().unwrap(), kind::HUB, 0, 0);
        admin.set_record(GATE, id, record.pack());
    }
    let class = declare("ReadProbe").unwrap().contract_class();
    let (probe, _) = class.deploy(@array![]).unwrap();
    (IReadProbeDispatcher { contract_address: probe }, registry)
}

#[test]
#[available_gas(l2_gas: 8649417)] // ceil(1.05 × 8237540 measured)
fn test_read_cost_baseline() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    probe.nothing(registry);
    println!("read cost, the probe alone: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8789519)] // ceil(1.05 × 8370970 measured)
fn test_read_cost_one_call_one_read() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    probe.version(registry);
    println!("read cost, a call reading the version: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8860005)] // ceil(1.05 × 8438100 measured)
fn test_read_cost_bundle_1() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    assert(probe.bundle(registry, 1) == 1, 'one part');
    println!("read cost, bundle of 1: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8916726)] // ceil(1.05 × 8492120 measured)
fn test_read_cost_bundle_2() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    assert(probe.bundle(registry, 2) == 2, 'two parts');
    println!("read cost, bundle of 2: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 9257052)] // ceil(1.05 × 8816240 measured)
fn test_read_cost_bundle_8() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    assert(probe.bundle(registry, 8) == 8, 'eight parts');
    println!("read cost, bundle of 8: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8993660)] // ceil(1.05 × 8565390 measured)
fn test_read_cost_two_calls() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    assert(probe.calls(registry, 2) == 2, 'two parts');
    println!("read cost, two calls of record: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 9961025)] // ceil(1.05 × 9486690 measured)
fn test_read_cost_eight_calls() {
    let (probe, registry) = setup();
    let gas = get_available_gas();
    assert(probe.calls(registry, 8) == 8, 'eight parts');
    println!("read cost, eight calls of record: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8690262)] // ceil(1.05 × 8276440 measured)
fn test_read_cost_local_1() {
    let (probe, _) = setup();
    let gas = get_available_gas();
    probe.local(1);
    println!("read cost, 1 local read: {}", gas - get_available_gas());
}

#[test]
#[available_gas(l2_gas: 8886959)] // ceil(1.05 × 8463770 measured)
fn test_read_cost_local_8() {
    let (probe, _) = setup();
    let gas = get_available_gas();
    probe.local(8);
    println!("read cost, 8 local reads: {}", gas - get_available_gas());
}
