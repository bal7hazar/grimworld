//! `Registry`: content as data (pillar 6, design/01 *Horizontal scaling*), read by every contract
//! and by the client. One uniform store: a record of kind `k` is `parts(k)` felts under
//! `(k, id, part)` (`grimworld_logic::content`). Written by the administrator role only (ADR-0007;
//! who holds it is Q-08). ENG-01 froze the interface and storage; ENG-03 wrote the checks.
//!
//! A record that was never written reads as `parts(kind)` zeros: part 0 is 0, which is how every
//! reader tells a missing record (a written record has `LIVE` in part 0).

use core::pedersen::pedersen;
use starknet::storage_access::{
    StorageAddress, storage_address_from_base, storage_base_address_from_felt252,
};
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};

pub const VERSION: felt252 = 'grimworld-registry-1';
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';

pub mod errors {
    /// An administrator's entrypoint called by anyone else (ADR-0007, *Access control*).
    pub const NOT_ADMIN: felt252 = 'not admin';
    /// `set_admin` to the zero address would leave the role to nobody.
    pub const ZERO_ADMIN: felt252 = 'admin is zero';
    /// `set_record`'s refusals (ENG-01 §3.5, §4.5).
    pub const PART_COUNT: felt252 = 'registry: part count';
    pub const NOT_LIVE: felt252 = 'registry: part 0 not live';
    pub const ZERO_ID: felt252 = 'registry: id zero';
    pub const NOT_NEXT: felt252 = 'registry: id not next';
    pub const NO_PARENT: felt252 = 'registry: no parent';
    pub const OUTLINE_CHUNK: felt252 = 'registry: outline chunk';
    /// `records` and `bundle` past their bound (ENG-01 §4.5).
    pub const TOO_MANY: felt252 = 'registry: too many records';
}

#[starknet::interface]
pub trait IRegistryAdmin<T> {
    fn version(self: @T) -> felt252;
    /// Writes one record: exactly `parts(kind)` felts, part 0 with `LIVE` set. A sequential kind's
    /// new id must be `last_id + 1` (append-only, design/01 rule 2); a composite kind's id must
    /// name an existing parent (`content::is_sequential`). An existing id's values may change.
    /// Every changed record raises the content version by one (D-141, E-5): a batch computed under
    /// the earlier content is then refused by `play` (`Stop::Version`).
    fn set_record(ref self: T, kind: u8, id: u32, record: Span<felt252>);
    /// The highest id of a sequential kind; 0 for a composite kind.
    fn last_id(self: @T, kind: u8) -> u32;
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

/// The parts of a record in `records`, read and written at their address without hashing the
/// whole key for each part. The map hashes its key's members in order, a Pedersen chain from the
/// variable's selector: `h(h(h(selector, kind), id), part)`. `key` is the record's two links,
/// computed once; `address` adds the part's (tested against the map's own addresses:
/// `test_part_address_is_the_maps`).
#[generate_trait]
pub impl PartsImpl of Parts {
    #[inline(always)]
    fn key(kind: u8, id: u32) -> felt252 {
        pedersen(pedersen(selector!("records"), kind.into()), id.into())
    }

    #[inline(always)]
    fn address(key: felt252, part: u8) -> StorageAddress {
        storage_address_from_base(storage_base_address_from_felt252(pedersen(key, part.into())))
    }

    #[inline(always)]
    fn read(address: StorageAddress) -> felt252 {
        storage_read_syscall(0, address).unwrap_syscall()
    }

    #[inline(always)]
    fn write(address: StorageAddress, value: felt252) {
        storage_write_syscall(0, address, value).unwrap_syscall()
    }
}

#[starknet::contract]
pub mod Registry {
    use core::num::traits::Zero;
    use grimworld_logic::content::{LOCATION, MAX_READ, OUTLINE, SHOP, is_sequential, parts};
    use grimworld_logic::interface::IRegistryRead;
    use grimworld_logic::models::location::INDEX_BOUND;
    use grimworld_logic::models::outline::CHUNK_SET;
    use grimworld_logic::packing::{Counter, LIVE_HIGH};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use super::{NOT_IMPLEMENTED, Parts, VERSION, errors};

    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        /// `(kind, id, part)` → one felt of the record.
        pub records: Map<(u8, u32, u8), felt252>,
        /// Highest id of each sequential kind (`content::is_sequential`); 0 for composite kinds.
        pub last_ids: Map<u8, Counter>,
        /// The content version (D-141, E-5): 0 at deployment, raised by one by every
        /// changed record (`set_record`, automatically, no admin setter); returned by `bundle`.
        pub content_version: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
    }

    #[abi(embed_v0)]
    impl RegistryReadImpl of IRegistryRead<ContractState> {
        /// `parts(kind)` felts; zeros for a record never written.
        fn record(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            let mut out: Array<felt252> = array![];
            self.read_into(kind, id, parts(kind), ref out);
            out.span()
        }
        /// The records of `ids`, one after the other, `parts(kind)` felts each.
        fn records(self: @ContractState, kind: u8, ids: Span<u32>) -> Span<felt252> {
            RegistryAssert::assert_bound(ids.len());
            let count = parts(kind);
            let mut out: Array<felt252> = array![];
            for id in ids {
                self.read_into(kind, *id, count, ref out);
            }
            out.span()
        }
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, Span<felt252>) {
            RegistryAssert::assert_bound(requests.len());
            let mut out: Array<felt252> = array![];
            for request in requests {
                let (kind, id) = *request;
                self.read_into(kind, id, parts(kind), ref out);
            }
            (self.content_version.read(), out.span())
        }
        fn content_version(self: @ContractState) -> u32 {
            self.content_version.read()
        }
    }

    #[abi(embed_v0)]
    impl RegistryAdminImpl of super::IRegistryAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
        /// A change is told by comparing each part with the stored felt: only the parts that
        /// differ are written, and the version is raised once if any did. A rewrite of the same
        /// values writes nothing and leaves the version as it was.
        fn set_record(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            self.assert_admin();
            RegistryAssert::assert_record(kind, id, record);
            if is_sequential(kind) {
                let last = self.last_ids.read(kind).value;
                let id_wide: u64 = id.into();
                if id_wide == last + 1 {
                    // A new id: none of its keys was ever written (ids are never reused, records
                    // never zeroed), so there is nothing to read or compare.
                    let key = Parts::key(kind, id);
                    let mut part: u8 = 0;
                    for felt in record {
                        if *felt != 0 {
                            Parts::write(Parts::address(key, part), *felt);
                        }
                        part += 1;
                    }
                    self.last_ids.write(kind, Counter { value: id_wide });
                    self.raise_version();
                    return;
                }
                RegistryAssert::assert_existing(id_wide, last);
            } else {
                self.assert_parent(kind, id);
            }
            let key = Parts::key(kind, id);
            let mut changed = false;
            let mut part: u8 = 0;
            for felt in record {
                let address = Parts::address(key, part);
                if Parts::read(address) != *felt {
                    Parts::write(address, *felt);
                    changed = true;
                }
                part += 1;
            }
            if changed {
                self.raise_version();
            }
        }
        fn last_id(self: @ContractState, kind: u8) -> u32 {
            parts(kind);
            self.last_ids.read(kind).value.try_into().unwrap()
        }
        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            self.assert_admin();
            assert(admin.is_non_zero(), errors::ZERO_ADMIN);
            self.admin.write(admin);
        }
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    /// The writer's and the readers' checks (ENG-01 §3.5, §4.5), in the order `set_record` makes
    /// them: the administrator, the kind, the part count, the id, `LIVE`, then the allocation.
    #[generate_trait]
    pub impl RegistryAssert of RegistryAssertTrait {
        #[inline(always)]
        fn assert_admin(self: @ContractState) {
            assert(get_caller_address() == self.admin.read(), errors::NOT_ADMIN);
        }

        /// A known kind, exactly `parts(kind)` felts, a non-zero id, and part 0 with `LIVE` and
        /// nothing above it. `u256` only to split part 0 into its limbs, the cheapest split on
        /// Cairo 2.19 (as `packing::split`).
        #[inline(always)]
        fn assert_record(kind: u8, id: u32, record: Span<felt252>) {
            let count = parts(kind);
            assert(record.len() == count.into(), errors::PART_COUNT);
            assert(id != 0, errors::ZERO_ID);
            let wide: u256 = (*record.at(0)).into();
            let (live, _) = DivRem::div_rem(wide.high, LIVE_HIGH.try_into().unwrap());
            assert(live == 1, errors::NOT_LIVE);
        }

        /// A sequential id that is not new must exist: at most `last_id` (ids are append-only).
        #[inline(always)]
        fn assert_existing(id: u64, last: u64) {
            assert(id <= last, errors::NOT_NEXT);
        }

        /// A composite id names an existing parent: `OUTLINE` a location (and a chunk below 225, or
        /// 255), `SHOP` a hub. `TASK` and `QUEST` take quiver's ids: quiver's records are not in
        /// this contract, so nothing is checked beyond a non-zero id (ENG-03 report, escalation).
        #[inline(always)]
        fn assert_parent(self: @ContractState, kind: u8, id: u32) {
            if kind == OUTLINE {
                let (location, chunk) = DivRem::div_rem(id, 256);
                assert(
                    chunk < INDEX_BOUND.into() || chunk == CHUNK_SET.into(), errors::OUTLINE_CHUNK,
                );
                self.assert_exists(LOCATION, location);
            } else if kind == SHOP {
                self.assert_exists(LOCATION, id / 16);
            }
        }

        /// A record exists when its part 0 is not 0 (ENG-01 §3.5).
        #[inline(always)]
        fn assert_exists(self: @ContractState, kind: u8, id: u32) {
            assert(self.records.read((kind, id, 0)) != 0, errors::NO_PARENT);
        }

        #[inline(always)]
        fn assert_bound(count: u32) {
            assert(count <= MAX_READ, errors::TOO_MANY);
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        /// Appends the `count` parts of `(kind, id)` to `out`.
        #[inline(always)]
        fn read_into(self: @ContractState, kind: u8, id: u32, count: u8, ref out: Array<felt252>) {
            let key = Parts::key(kind, id);
            for part in 0..count {
                out.append(Parts::read(Parts::address(key, part)));
            }
        }
        /// The content version, raised by one (D-141): one read and one write of one slot.
        #[inline(always)]
        fn raise_version(ref self: ContractState) {
            self.content_version.write(self.content_version.read() + 1);
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
    use super::{Parts, Registry};

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
        assert(
            address_of(
                state.content_version.as_ptr().__storage_pointer_address__,
            ) == selector!("content_version"),
            'content_version',
        );
    }

    // The oracle of `Parts::key` and `Parts::address`: the map's own address, for the widest keys.
    #[test]
    #[available_gas(l2_gas: 186228)] // ceil(1.05 × 177360 measured)
    fn test_part_address_is_the_maps() {
        let state = @Registry::contract_state_for_testing();
        let cases: Array<(u8, u32, u8)> = array![
            (1, 1, 0), (2, 5, 1), (15, 7, 2), (25, 0xFFFFFFFF, 0), (3, 0xFFFFFF, 0),
        ];
        for case in cases {
            let (kind, id, part) = case;
            let expected: felt252 = address_of(
                state.records.entry((kind, id, part)).as_ptr().__storage_pointer_address__,
            );
            let got: felt252 = Parts::address(Parts::key(kind, id), part).into();
            assert(got == expected, 'part address');
        }
    }
}

/// The content version's own cost, apart from everything else (ENG-03, for ENG-06 and ENG-07):
/// the same state, with and without the version's read, and with and without its raise. The cost
/// is the difference between a probe and its baseline (see GAS.md).
#[cfg(test)]
mod version_cost_tests {
    use snforge_std::{store, test_address};
    use starknet::storage::StoragePointerReadAccess;
    use super::Registry;
    use super::Registry::InternalTrait;

    #[test]
    #[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
    fn test_version_cost_baseline() {
        let state = Registry::contract_state_for_testing();
        let _ = @state;
    }

    // `bundle`'s part of the version: one read of one slot.
    #[test]
    #[available_gas(l2_gas: 36383)] // ceil(1.05 × 34650 measured)
    fn test_version_cost_read() {
        let state = @Registry::contract_state_for_testing();
        assert(state.content_version.read() == 0, 'version 0');
    }

    // `set_record`'s part, when the record changed: the read and the write of the raise.
    #[test]
    #[available_gas(l2_gas: 507066)] // ceil(1.05 × 482920 measured)
    fn test_version_cost_raise() {
        let mut state = Registry::contract_state_for_testing();
        state.raise_version();
    }

    // The baseline of the next one: a version already written.
    #[test]
    #[available_gas(l2_gas: 444087)] // ceil(1.05 × 422940 measured)
    fn test_version_cost_stored_baseline() {
        let state = Registry::contract_state_for_testing();
        store(test_address(), selector!("content_version"), array![7].span());
        let _ = @state;
    }

    // Every raise after the first: the slot holds a version, the write overwrites it.
    #[test]
    #[available_gas(l2_gas: 514647)] // ceil(1.05 × 490140 measured)
    fn test_version_cost_raise_again() {
        let mut state = Registry::contract_state_for_testing();
        store(test_address(), selector!("content_version"), array![7].span());
        state.raise_version();
    }
}
