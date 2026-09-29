//! `TxHashFate`: the MVP's randomness provider (ADR-0002, D-110), behind `IFate`. Its word is
//! `poseidon(transaction hash, domain)`: steerable by whoever sends the transaction, the accepted
//! weakness of the MVP. It refuses mainnet, at deployment and at every call (ADR-0002: "a
//! deployment check refuses the provisional provider on mainnet"). Version 1 replaces the address,
//! not the game's code.

/// Starknet mainnet's chain id.
pub const SN_MAIN: felt252 = 'SN_MAIN';
pub const REFUSED: felt252 = 'fate: not on mainnet';

#[starknet::contract]
pub mod TxHashFate {
    use core::poseidon::poseidon_hash_span;
    use grimworld_logic::interface::IFate;
    use starknet::get_tx_info;
    use super::{REFUSED, SN_MAIN};

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {
        assert(get_tx_info().unbox().chain_id != SN_MAIN, REFUSED);
    }

    #[abi(embed_v0)]
    impl FateImpl of IFate<ContractState> {
        fn fate(ref self: ContractState, domain: felt252) -> felt252 {
            let info = get_tx_info().unbox();
            assert(info.chain_id != SN_MAIN, REFUSED);
            poseidon_hash_span(array![info.transaction_hash, domain].span())
        }
    }
}
