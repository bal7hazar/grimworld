//! Placeholder contract of the ephemeral domain: one view, no storage, no access control (ENG-01).

/// Version of the placeholder contract, returned by `version`.
pub const VERSION: felt252 = 'grimworld-ephemeral-0';

#[starknet::interface]
pub trait IEphemeral<T> {
    /// Placeholder view, so that the class can be declared, deployed and called.
    fn version(self: @T) -> felt252;
}

#[starknet::contract]
pub mod Ephemeral {
    use super::VERSION;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl EphemeralImpl of super::IEphemeral<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
    }
}
