//! Stand-in for `fate(domain)` (ADR-0002, D-110 provisional source): the transaction hash,
//! hashed with the domain. Hubs only: no rule inside an instance calls it.

use core::poseidon::poseidon_hash_span;
use starknet::get_tx_info;

pub fn fate(domain: felt252) -> felt252 {
    let hash = get_tx_info().unbox().transaction_hash;
    poseidon_hash_span([hash, domain].span())
}
