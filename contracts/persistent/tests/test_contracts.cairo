// The persistent contracts declare and deploy; their entrypoints are stubs that revert with
// 'not implemented'. The MVP's randomness provider gives `poseidon(tx hash, domain)` and refuses
// mainnet at deployment and at every call (ADR-0002).
use core::poseidon::poseidon_hash_span;
use grimworld_logic::interface::{IFateDispatcher, IFateDispatcherTrait};
use grimworld_persistent::systems::fate::REFUSED;
use grimworld_persistent::systems::hub::{
    IHubAdminDispatcher, IHubAdminDispatcherTrait, IHubSafeDispatcher, IHubSafeDispatcherTrait,
    NOT_IMPLEMENTED, VERSION as HUB_VERSION,
};
use grimworld_persistent::systems::market::{
    IMarketAdminDispatcher, IMarketAdminDispatcherTrait, VERSION as MARKET_VERSION,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait, VERSION as REGISTRY_VERSION,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_chain_id, cheat_transaction_hash,
    declare, start_cheat_chain_id_global,
};

#[test]
#[available_gas(l2_gas: 4318755)] // ceil(1.05 × 4113100 measured)
fn test_hub_deploys_and_stubs_revert() {
    let class = declare("Hub").unwrap().contract_class();
    let (address, _) = class.deploy(@array![1, 2, 3, 4, 5]).unwrap();
    assert(IHubAdminDispatcher { contract_address: address }.version() == HUB_VERSION, 'version');
    // `set_build` is implemented since CBT-08a; `buy_skill` is still a stub.
    #[feature("safe_dispatcher")]
    let bought = IHubSafeDispatcher { contract_address: address }.buy_skill(1, 1);
    assert(*bought.unwrap_err().at(0) == NOT_IMPLEMENTED, 'buy_skill is a stub');
}

#[test]
#[available_gas(l2_gas: 3992919)] // ceil(1.05 × 3802780 measured)
fn test_market_and_registry_deploy() {
    let class = declare("Market").unwrap().contract_class();
    let (market, _) = class.deploy(@array![1, 2, 3]).unwrap();
    assert(
        IMarketAdminDispatcher { contract_address: market }.version() == MARKET_VERSION, 'market',
    );
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![1]).unwrap();
    assert(
        IRegistryAdminDispatcher { contract_address: registry }.version() == REGISTRY_VERSION,
        'registry',
    );
}

#[test]
#[available_gas(l2_gas: 406260)] // ceil(1.05 × 386914 measured)
fn test_fate_word() {
    let class = declare("TxHashFate").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    cheat_transaction_hash(address, 0x1234, CheatSpan::TargetCalls(1));
    let word = IFateDispatcher { contract_address: address }.fate('loot');
    assert(word == poseidon_hash_span(array![0x1234, 'loot'].span()), 'poseidon(hash, domain)');
}

#[test]
#[available_gas(l2_gas: 396660)] // ceil(1.05 × 377771 measured)
fn test_fate_refuses_mainnet_calls() {
    let class = declare("TxHashFate").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    cheat_chain_id(address, 'SN_MAIN', CheatSpan::TargetCalls(1));
    let safe = grimworld_logic::interface::IFateSafeDispatcher { contract_address: address };
    #[feature("safe_dispatcher")]
    let word = grimworld_logic::interface::IFateSafeDispatcherTrait::fate(safe, 'loot');
    assert(*word.unwrap_err().at(0) == REFUSED, 'mainnet refused');
}

#[test]
#[available_gas(l2_gas: 276444)] // ceil(1.05 × 263280 measured)
fn test_fate_refuses_mainnet_deployment() {
    let class = declare("TxHashFate").unwrap().contract_class();
    start_cheat_chain_id_global('SN_MAIN');
    let deployed = class.deploy(@array![]);
    assert(*deployed.unwrap_err().at(0) == REFUSED, 'mainnet deployment refused');
}
