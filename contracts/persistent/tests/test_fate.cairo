// FND-05: the MVP's provider, deployed (ADR-0002). `fate` is deterministic per transaction and
// domain; values come from its word through `derive`, distinct per domain and index; anyone may
// call it and gets only `poseidon(tx hash, domain)`, whoever calls; the game reads the provider at
// the address of its configuration.
use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::{CHEST, LOOT, PURPOSES, derive, domain};
use grimworld_logic::interface::{IFateDispatcher, IFateDispatcherTrait};
use grimworld_persistent::systems::hub::{IHubAdminDispatcher, IHubAdminDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, start_cheat_caller_address,
    start_cheat_transaction_hash, start_cheat_transaction_hash_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn deploy_fate() -> IFateDispatcher {
    let class = declare("TxHashFate").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    IFateDispatcher { contract_address: address }
}

// The same transaction and domain give the same word, however many times it is asked; another
// domain, or another transaction, gives another word.
#[test]
#[available_gas(l2_gas: 996144)] // ceil(1.05 × 948708 measured)
fn test_fate_deterministic_per_transaction_and_domain() {
    let fate = deploy_fate();
    let loot = domain(0x100000001, 4, LOOT);
    start_cheat_transaction_hash(fate.contract_address, 0x7a);
    let word = fate.fate(loot);
    assert(word == fate.fate(loot), 'same tx, same domain');
    assert(word == poseidon_hash_span(array![0x7a, loot].span()), 'poseidon(hash, domain)');
    assert(word != fate.fate(domain(0x100000001, 4, CHEST)), 'another purpose');
    assert(word != fate.fate(domain(0x100000001, 5, LOOT)), 'another sequence');
    start_cheat_transaction_hash(fate.contract_address, 0x7b);
    assert(word != fate.fate(loot), 'another transaction');
}

// One transaction, one word per purpose, four values each through `derive`: all distinct.
#[test]
// gas: raised, ENG-05: one more purpose to derive (the reveal's)
#[available_gas(l2_gas: 4229493)] // ceil(1.05 × 4028088 measured)
fn test_fate_values_distinct_through_derive() {
    let fate = deploy_fate();
    start_cheat_transaction_hash(fate.contract_address, 0x7a);
    let mut values = array![];
    for purpose in PURPOSES.span() {
        let d = domain(0x100000001, 4, *purpose);
        let word = fate.fate(d);
        for index in 0..4_u32 {
            values.append(derive(word, d, index));
        }
    }
    let values = values.span();
    for i in 0..values.len() {
        for j in (i + 1)..values.len() {
            assert(*values.at(i) != *values.at(j), 'distinct');
        }
    }
}

// Anyone may call `fate`: it has no state, so a call changes nothing and consumes nothing, and the
// caller does not enter the word. What a caller gets is `poseidon(tx hash, domain)` for the domain
// it passes, which the sender of the transaction can compute without calling (the accepted
// weakness, ADR-0002 rule 7). A game contract draws under `poseidon(subject, counter, purpose)`:
// another purpose, subject or counter is another input to Poseidon, hence another word; and the
// same domain in another transaction is another word (the test above).
#[test]
#[available_gas(l2_gas: 770404)] // ceil(1.05 × 733718 measured)
fn test_fate_anyone_gets_only_their_domain() {
    let fate = deploy_fate();
    start_cheat_transaction_hash_global(0x7a);
    let loot = domain(0x100000001, 4, LOOT);
    start_cheat_caller_address(fate.contract_address, 0xbad.try_into().unwrap());
    let theirs = fate.fate(loot);
    stop_cheat_caller_address(fate.contract_address);
    start_cheat_caller_address(fate.contract_address, 0x1c.try_into().unwrap());
    assert(fate.fate(loot) == theirs, 'caller does not enter');
    assert(theirs == poseidon_hash_span(array![0x7a, loot].span()), 'nothing but hash and domain');
}

// The game reaches the provider through its configuration: the address the administrator set in
// `Hub` is the provider called.
#[test]
#[available_gas(l2_gas: 5246615)] // ceil(1.05 × 4996776 measured)
fn test_fate_at_the_configured_address() {
    let fate = deploy_fate();
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![0xad, 2, 3, 4, 5]).unwrap();
    start_cheat_caller_address(hub, 0xad.try_into().unwrap());
    IHubAdminDispatcher { contract_address: hub }
        .set_contracts(
            2.try_into().unwrap(),
            3.try_into().unwrap(),
            4.try_into().unwrap(),
            fate.contract_address,
            0.try_into().unwrap(),
        );
    let configured: ContractAddress = (*load(hub, selector!("fate"), 1).at(0)).try_into().unwrap();
    assert(configured == fate.contract_address, 'configured');
    start_cheat_transaction_hash_global(0x7a);
    let loot = domain(1, 0, LOOT);
    assert(
        IFateDispatcher { contract_address: configured }.fate(loot) == fate.fate(loot),
        'the configured provider',
    );
}
