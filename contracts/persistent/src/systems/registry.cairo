//! `Registry`: content as data (pillar 6, design/01 *Horizontal scaling*), read by every contract
//! and by the client. One uniform store: a record of kind `k` is `parts(k)` felts under
//! `(k, id, part)` (`grimworld_logic::content`). Written by the administrator role only (ADR-0007;
//! who holds it is Q-08). ENG-01 froze the interface and storage; ENG-03 wrote the checks.
//!
//! A record that was never written reads as `parts(kind)` zeros: part 0 is 0, which is how every
//! reader tells a missing record (a written record has `LIVE` in part 0).

use core::pedersen::pedersen;
use grimworld_logic::content::{ITEM, MODIFIER, SKILL};
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
    /// the earlier content is then refused by `play` (`Stop::Version`). A changed record of a kind
    /// the flattening reads that existed before (`Inputs::includes`) also raises the inputs
    /// version (D-169): the snapshots stored under the earlier one are then refused by `enter`.
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

/// The record kinds the snapshot's flattening reads (D-169): a changed record of one of them
/// raises the inputs version, which stales every stored snapshot. They are the kinds of
/// `Hub.set_build`'s one `bundle` call, whose records decide the stored words or their acceptance:
/// - `SKILL`: each bar skill's profession and elite flag (`BuildAssert::assert_skill`,
///   `assert_one_elite`);
/// - `ITEM`: each belt item's class, a potion (`BeltAssert::assert_potion`);
/// - `MODIFIER`: each worn modifier's slot type, benefit, cost, source and piece, flattened into
///   the words (`WornTrait::held`).
/// No other kind is read: `BASE`'s slot and hands are copied into the item at its creation
/// (D-158), and `Build::loadout` lays out no weapon statistic and no set bonus, so neither `BASE`
/// nor `ARMOR_SET` is read; the level is the adventurer's, the profession's values are constants
/// (`ProfessionTrait`). A lot that makes `set_build` read another kind adds it here.
///
/// A **new** id of these kinds raises nothing: `set_build` refuses a missing skill, potion or
/// modifier (`NO_SKILL`, `NOT_A_POTION`, `NO_MODIFIER`), ids are never reused and part 0
/// never returns to 0 (`LIVE`), so no stored snapshot names an id written after it.
#[generate_trait]
pub impl InputsImpl of Inputs {
    #[inline(always)]
    fn includes(kind: u8) -> bool {
        kind == SKILL || kind == ITEM || kind == MODIFIER
    }
}

#[starknet::contract]
pub mod Registry {
    use core::num::traits::Zero;
    use grimworld_logic::content::{
        ARMOR_SET, CASTE, ITEM, LOCATION, MAX_READ, MODIFIER, OUTLINE, QUOTAS, SHOP, SKILL,
        is_sequential, parts,
    };
    use grimworld_logic::interface::IRegistryRead;
    use grimworld_logic::models::armor_set::{ArmorSetAssert, ArmorSetRecord};
    use grimworld_logic::models::caste::{
        CasteAssert, CasteRecord, MAX_SKILL_ADRENALINE, errors as caste_errors,
    };
    use grimworld_logic::models::item::{ItemAssert, ItemRecord};
    use grimworld_logic::models::location::INDEX_BOUND;
    use grimworld_logic::models::modifier::{ModifierAssert, ModifierRecord};
    use grimworld_logic::models::outline::CHUNK_SET;
    use grimworld_logic::models::skill::{SkillAssert, SkillRecord};
    use grimworld_logic::packing::{Counter, LIVE_HIGH};
    use crate::models::versions::{Versions, VersionsTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use super::{Inputs, NOT_IMPLEMENTED, Parts, VERSION, errors};

    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        /// `(kind, id, part)` → one felt of the record.
        pub records: Map<(u8, u32, u8), felt252>,
        /// Highest id of each sequential kind (`content::is_sequential`); 0 for composite kinds.
        pub last_ids: Map<u8, Counter>,
        /// The content version (D-141, E-5) and the inputs version (D-169), one slot
        /// (`models::versions`): 0 at deployment, raised by `set_record`, automatically, no admin
        /// setter; returned by `bundle`.
        pub versions: Versions,
        /// How many `CASTE` records name each skill id (a caste naming it twice counts twice):
        /// while it is not 0, the skill is refused above 63 strikes (DS-18 across records, in
        /// either order of writes; CBT-02c fix loop 2).
        pub caste_skills: Map<u32, u32>,
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
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, u32, Span<felt252>) {
            RegistryAssert::assert_bound(requests.len());
            let mut out: Array<felt252> = array![];
            for request in requests {
                let (kind, id) = *request;
                self.read_into(kind, id, parts(kind), ref out);
            }
            let versions = self.versions.read();
            (versions.content, versions.inputs, out.span())
        }
        fn content_version(self: @ContractState) -> u32 {
            self.versions.read().content
        }
    }

    #[abi(embed_v0)]
    impl RegistryAdminImpl of super::IRegistryAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
        /// A change is told by comparing each part with the stored felt: only the parts that
        /// differ are written, and the versions are raised once if any did, in one write. A
        /// rewrite of the same values writes nothing and leaves both versions as they were. A new
        /// id raises the content version only: no stored snapshot can name it (`Inputs`).
        fn set_record(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            self.assert_admin();
            RegistryAssert::assert_record(kind, id, record);
            self.assert_content(kind, id, record);
            if is_sequential(kind) {
                let last = self.last_ids.read(kind).value;
                let id_wide: u64 = id.into();
                if id_wide == last + 1 {
                    // A new id: none of its keys was ever written (ids are never reused, records
                    // never zeroed), so there is nothing to read or compare.
                    self.name_skills(kind, id, record);
                    let key = Parts::key(kind, id);
                    let mut part: u8 = 0;
                    for felt in record {
                        if *felt != 0 {
                            Parts::write(Parts::address(key, part), *felt);
                        }
                        part += 1;
                    }
                    self.last_ids.write(kind, Counter { value: id_wide });
                    self.raise_versions(false);
                    return;
                }
                RegistryAssert::assert_existing(id_wide, last);
            } else {
                self.assert_parent(kind, id);
            }
            self.name_skills(kind, id, record);
            if self.update(kind, id, record) {
                self.raise_versions(Inputs::includes(kind));
            }
        }
        fn last_id(self: @ContractState, kind: u8) -> u32 {
            parts(kind);
            self.last_ids.read(kind).value.try_into().unwrap()
        }
        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            self.assert_admin();
            RegistryAssert::assert_new_admin(admin);
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

        /// `set_admin` never hands the role to the zero address, which would leave it to nobody.
        #[inline(always)]
        fn assert_new_admin(admin: ContractAddress) {
            assert(admin.is_non_zero(), errors::ZERO_ADMIN);
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

        /// The content's checks of one record (D-166; design/20 §1.3–§1.5, §5), made once,
        /// when the administrator writes it, so that no player's call makes them again:
        /// - `MODIFIER` (a prefix, a suffix, an inscription, an insignia, a rune):
        ///   `ModifierAssert::assert_legal`, its passives legal on its slot type (DS-4), their sum
        ///   within design/20's per-source bounds (DS-1, DS-5), an insignia's health within its
        ///   piece's (DS-23);
        /// - `ARMOR_SET`: each bonus legal on a set bonus and within its bounds (DS-1, DS-5);
        /// - `SKILL` and a potion's `ITEM`: their entries a legal carrier, one `ATTACK_BONUS` at
        ///   most (DS-20);
        /// - `CASTE`: `CasteAssert::assert_legal` (DS-18, DS-29), and the adrenaline of each skill
        ///   it names that the registry holds at most 63 strikes (DS-18, across records);
        /// - DS-18 in the other order: a `SKILL` above 63 strikes is refused while a caste names
        ///   its id (`caste_skills`), whether the skill is new or rewritten.
        /// Every other kind has no bound of design/20.
        fn assert_content(self: @ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind == MODIFIER {
                ModifierRecord::unpack(record).assert_legal();
            } else if kind == ARMOR_SET {
                ArmorSetRecord::unpack(record).assert_legal();
            } else if kind == SKILL {
                let skill = SkillRecord::unpack(record);
                skill.assert_legal();
                if skill.adrenaline > MAX_SKILL_ADRENALINE {
                    assert(self.caste_skills.read(id) == 0, caste_errors::SKILL_ADRENALINE);
                }
            } else if kind == ITEM {
                ItemRecord::unpack(record).assert_legal();
            } else if kind == CASTE {
                let caste = CasteRecord::unpack(record);
                caste.assert_legal();
                let mut skills = array![];
                for skill in caste.skills.span() {
                    if *skill != 0 && self.records.read((SKILL, (*skill).into(), 0)) != 0 {
                        let mut out = array![];
                        self.read_into(SKILL, (*skill).into(), parts(SKILL), ref out);
                        skills.append(SkillRecord::unpack(out.span()));
                    }
                }
                CasteAssert::assert_skills(skills.span());
            }
        }

        /// A sequential id that is not new must exist: at most `last_id` (ids are append-only).
        #[inline(always)]
        fn assert_existing(id: u64, last: u64) {
            assert(id <= last, errors::NOT_NEXT);
        }

        /// A composite id names an existing parent: `QUOTAS` its location (the same id, D-145),
        /// `OUTLINE` a location (and a chunk below 225, or 255), `SHOP` a location as its hub (its
        /// existence only: that it is a town or an outpost is the content pipeline's check).
        /// `TASK` and `QUEST` take the administrator's quiver ids as they are (D-145): that a
        /// quiver id exists is the content pipeline's check (OPS-01).
        #[inline(always)]
        fn assert_parent(self: @ContractState, kind: u8, id: u32) {
            if kind == QUOTAS {
                self.assert_exists(LOCATION, id);
            } else if kind == OUTLINE {
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
        /// A `CASTE` written (after every check): the counts of `caste_skills` move from the
        /// skills its stored record named to those the new one names; only the counts that
        /// change are written (a rewrite naming the same skills writes none). At most 8 skill
        /// ids, so at most 8 counts.
        fn name_skills(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind != CASTE {
                return;
            }
            let new = CasteRecord::unpack(record).skills;
            let old: [u16; 4] = if self.records.read((CASTE, id, 0)) != 0 {
                let mut out = array![];
                self.read_into(CASTE, id, parts(CASTE), ref out);
                CasteRecord::unpack(out.span()).skills
            } else {
                [0; 4]
            };
            let (old, new) = (old.span(), new.span());
            let mut seen: Array<u16> = array![];
            for skill in array![old, new].span() {
                for s in *skill {
                    let s = *s;
                    if s == 0 || Self::times(seen.span(), s) != 0 {
                        continue;
                    }
                    seen.append(s);
                    let (before, now) = (Self::times(old, s), Self::times(new, s));
                    if before != now {
                        let count = self.caste_skills.read(s.into());
                        self.caste_skills.write(s.into(), count + now - before);
                    }
                }
            }
        }

        /// How many times `skill` is in `skills`.
        #[inline(always)]
        fn times(skills: Span<u16>, skill: u16) -> u32 {
            let mut n: u32 = 0;
            for s in skills {
                if *s == skill {
                    n += 1;
                }
            }
            n
        }

        /// Appends the `count` parts of `(kind, id)` to `out`.
        #[inline(always)]
        fn read_into(self: @ContractState, kind: u8, id: u32, count: u8, ref out: Array<felt252>) {
            let key = Parts::key(kind, id);
            for part in 0..count {
                out.append(Parts::read(Parts::address(key, part)));
            }
        }
        /// The writer's change detection: each part compared with the stored felt, only the parts
        /// that differ written. Whether any did, which raises the version once.
        #[inline(always)]
        fn update(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) -> bool {
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
            changed
        }
        /// The content version raised by one (D-141), and the inputs version with it when the
        /// record changed is an `input` of the flattening (D-169): one read and one write of one
        /// slot.
        #[inline(always)]
        fn raise_versions(ref self: ContractState, input: bool) {
            self.versions.write(self.versions.read().raised(input));
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
    // gas: raised, CBT-02c fix loop 2: the layout checks caste_skills' address too
    #[available_gas(l2_gas: 72755)] // ceil(1.05 × 69290 measured)
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
                state.versions.as_ptr().__storage_pointer_address__,
            ) == selector!("versions"),
            'versions',
        );
        assert(
            address_of(
                state.caste_skills.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("caste_skills"), array![7].span()),
            'caste_skills',
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

/// The flattening's input kinds (D-169): `SKILL`, `ITEM` and `MODIFIER`, and none of the 22 others.
#[cfg(test)]
mod inputs_tests {
    use grimworld_logic::content::{ITEM, LAST_KIND, MODIFIER, SKILL};
    use super::Inputs;

    #[test]
    #[available_gas(l2_gas: 112350)] // ceil(1.05 × 107000 measured)
    fn test_flattening_inputs() {
        for kind in 1..LAST_KIND + 1 {
            let expected = kind == SKILL || kind == ITEM || kind == MODIFIER;
            assert(Inputs::includes(kind) == expected, 'input kinds');
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

    // `bundle`'s part of the versions: one read of one slot, unpacked into the two (D-169).
    #[test]
    // gas: raised, CBT-02f: the slot holds the content and inputs versions, unpacked at the read
    #[available_gas(l2_gas: 39785)] // ceil(1.05 × 37890 measured)
    fn test_version_cost_read() {
        let state = @Registry::contract_state_for_testing();
        assert(state.versions.read().content == 0, 'version 0');
    }

    // `set_record`'s part, when the record changed: the read and the write of the raise.
    #[test]
    #[available_gas(l2_gas: 507066)] // ceil(1.05 × 482920 measured)
    fn test_version_cost_raise() {
        let mut state = Registry::contract_state_for_testing();
        state.raise_versions(false);
    }

    // `set_record`'s part when the changed record is an input of the flattening (D-169): both
    // versions raised in the same write; against `test_version_cost_raise`, the added cost.
    #[test]
    #[available_gas(l2_gas: 512169)] // ceil(1.05 × 487780 measured)
    fn test_version_cost_raise_input() {
        let mut state = Registry::contract_state_for_testing();
        state.raise_versions(true);
    }

    // The baseline of the next one: a version already written.
    #[test]
    #[available_gas(l2_gas: 444087)] // ceil(1.05 × 422940 measured)
    fn test_version_cost_stored_baseline() {
        let state = Registry::contract_state_for_testing();
        store(test_address(), selector!("versions"), array![7].span());
        let _ = @state;
    }

    // Every raise after the first: the slot holds a version, the write overwrites it.
    #[test]
    #[available_gas(l2_gas: 514647)] // ceil(1.05 × 490140 measured)
    fn test_version_cost_raise_again() {
        let mut state = Registry::contract_state_for_testing();
        store(test_address(), selector!("versions"), array![7].span());
        state.raise_versions(false);
    }
}

/// The writer's change detection, apart from the version (ENG-03 fix loop 1, F-3): a stored
/// 3-part record rewritten through `update` (read, compare, write what differs) against the same
/// rewrite made blind (every part written, nothing read). Identical values and changed values
/// each have their own matched pair; none of these raises the version.
#[cfg(test)]
mod detection_cost_tests {
    use grimworld_logic::content::BOOK;
    use grimworld_logic::packing::LIVE;
    use snforge_std::{map_entry_address, store, test_address};
    use super::Registry::InternalTrait;
    use super::{Parts, Registry};

    /// Book 1, stored with parts `(LIVE + 1, 2, 3)`.
    #[generate_trait]
    impl BookFixture of Book {
        fn store() {
            let parts = Self::stored();
            for part in 0..3_u8 {
                store(
                    test_address(),
                    map_entry_address(
                        selector!("records"), array![BOOK.into(), 1, part.into()].span(),
                    ),
                    array![*parts[part.into()]].span(),
                );
            }
        }

        fn stored() -> Span<felt252> {
            array![LIVE + 1, 2, 3].span()
        }

        fn changed() -> Span<felt252> {
            array![LIVE + 4, 5, 6].span()
        }

        /// Every part written, nothing read or compared: a writer without change detection.
        fn write_blind(record: Span<felt252>) {
            let key = Parts::key(BOOK, 1);
            let mut part: u8 = 0;
            for felt in record {
                Parts::write(Parts::address(key, part), *felt);
                part += 1;
            }
        }
    }

    // The baseline of the four below: the record stored, nothing else.
    #[test]
    #[available_gas(l2_gas: 1352841)] // ceil(1.05 × 1288420 measured)
    fn test_detection_cost_stored_baseline() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
    }

    #[test]
    #[available_gas(l2_gas: 1538681)] // ceil(1.05 × 1465410 measured)
    fn test_detection_cost_identical_blind() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
        Book::write_blind(Book::stored());
    }

    #[test]
    #[available_gas(l2_gas: 1456907)] // ceil(1.05 × 1387530 measured)
    fn test_detection_cost_identical() {
        let mut state = Registry::contract_state_for_testing();
        Book::store();
        assert(!state.update(BOOK, 1, Book::stored()), 'no change');
    }

    #[test]
    #[available_gas(l2_gas: 1538681)] // ceil(1.05 × 1465410 measured)
    fn test_detection_cost_changed_blind() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
        Book::write_blind(Book::changed());
    }

    #[test]
    #[available_gas(l2_gas: 1600956)] // ceil(1.05 × 1524720 measured)
    fn test_detection_cost_changed() {
        let mut state = Registry::contract_state_for_testing();
        Book::store();
        assert(state.update(BOOK, 1, Book::changed()), 'changed');
    }
}
