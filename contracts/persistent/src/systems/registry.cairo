//! `Registry`: content as data (pillar 6, design/01 *Horizontal scaling*), read by every contract
//! and by the client. One uniform store: a record of kind `k` is `parts(k)` felts under
//! `(k, id, part)` (`grimworld_logic::content`). Written by the administrator role only (ADR-0007;
//! who holds it is Q-08). ENG-01 freezes the interface and storage; ENG-03 writes the checks.

use starknet::{ClassHash, ContractAddress};

pub const VERSION: felt252 = 'grimworld-registry-1';
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';

#[starknet::interface]
pub trait IRegistryAdmin<T> {
    fn version(self: @T) -> felt252;
    /// Writes one record: exactly `parts(kind)` felts. A new id must be the next of its kind
    /// (append-only, design/01 rule 2); an existing id's values may change.
    fn set_record(ref self: T, kind: u8, id: u32, record: Span<felt252>);
    /// The highest id of a kind.
    fn last_id(self: @T, kind: u8) -> u32;
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Registry {
    use grimworld_logic::interface::IRegistryRead;
    use starknet::storage::{Map, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use super::{NOT_IMPLEMENTED, VERSION};

    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        /// `(kind, id, part)` → one felt of the record.
        pub records: Map<(u8, u32, u8), felt252>,
        /// Highest id of each kind.
        pub last_ids: Map<u8, u32>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
    }

    #[abi(embed_v0)]
    impl RegistryReadImpl of IRegistryRead<ContractState> {
        fn record(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn records(self: @ContractState, kind: u8, ids: Span<u32>) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl RegistryAdminImpl of super::IRegistryAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
        fn set_record(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn last_id(self: @ContractState, kind: u8) -> u32 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }
}
