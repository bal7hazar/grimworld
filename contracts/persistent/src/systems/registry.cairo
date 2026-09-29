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
    /// Writes one record: exactly `parts(kind)` felts, part 0 with `LIVE` set. A sequential kind's
    /// new id must be `last_id + 1` (append-only, design/01 rule 2); a composite kind's id must
    /// name an existing parent (`content::is_sequential`). An existing id's values may change.
    fn set_record(ref self: T, kind: u8, id: u32, record: Span<felt252>);
    /// The highest id of a sequential kind; 0 for a composite kind.
    fn last_id(self: @T, kind: u8) -> u32;
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Registry {
    use grimworld_logic::interface::IRegistryRead;
    use grimworld_logic::packing::Counter;
    use starknet::storage::{Map, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use super::{NOT_IMPLEMENTED, VERSION};

    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        /// `(kind, id, part)` → one felt of the record.
        pub records: Map<(u8, u32, u8), felt252>,
        /// Highest id of each sequential kind (`content::is_sequential`); 0 for composite kinds.
        pub last_ids: Map<u8, Counter>,
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
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> Span<felt252> {
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

/// The storage layout of `Registry` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address.
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use super::Registry;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    #[available_gas(l2_gas: 57981)] // ceil(1.05 × 55220 measured)
    fn test_registry_storage_addresses() {
        let state = @Registry::contract_state_for_testing();
        assert(
            address_of(
                state.records.entry((2, 5, 1)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("records"), array![2, 5, 1].span()),
            'records',
        );
        assert(
            address_of(
                state.last_ids.entry(2).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("last_ids"), array![2].span()),
            'last_ids',
        );
    }
}
