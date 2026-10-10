//! `Registry`: content as data (pillar 6, design/01 *Horizontal scaling*), read by every contract
//! and by the client. One uniform store: a record of kind `k` is `parts(k)` felts under
//! `(k, id, part)` (`grimworld_logic::content`). Written by the administrator role only (ADR-0007;
//! who holds it is Q-08). ENG-01 froze the interface and storage; ENG-03 wrote the checks.
//!
//! A record that was never written reads as `parts(kind)` zeros: part 0 is 0, which is how every
//! reader tells a missing record (a written record has `LIVE` in part 0).

use grimworld_logic::content::{ITEM, MODIFIER, SKILL};
use starknet::{ClassHash, ContractAddress};

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
    /// A `ZONE_CHUNK` or `BRIDGE` id whose chunk is not below 225 (ENG-09).
    pub const CHUNK: felt252 = 'registry: chunk';
    /// An authored zone's record before `set_zone_checks` (ENG-09).
    pub const NO_ZONE_CHECKS: felt252 = 'registry: no zone checks';
    /// `set_zone_checks` with the zero class hash.
    pub const ZONE_CHECKS_ZERO: felt252 = 'registry: zone checks zero';
    /// A `LOCATION` whose dungeon floor holds more than 12 chunks (ENG-10b, CM-9).
    pub const FLOOR_SIZE: felt252 = 'registry: floor over 12 chunks';
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
    /// The class of an authored zone's checks (`ZoneChecks`, ENG-09; administrator only, never 0):
    /// `set_record` runs them by `library_call` on the records of an authored zone and on the
    /// rules they share with other records. Until it is set, an authored zone's records are
    /// refused (`'registry: no zone checks'`).
    fn set_zone_checks(ref self: T, class_hash: ClassHash);
    fn upgrade(ref self: T, class_hash: ClassHash);
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
        ARMOR_SET, BRIDGE, CANDIDATES, CASTE, GATE, ITEM, LOCATION, MAX_READ, MODIFIER, OUTLINE,
        PACK, QUOTAS, SET_PIECE, SHOP, SKILL, SPAWN_TABLE, ZONE_CHUNK, is_sequential, parts,
    };
    use grimworld_logic::interface::IRegistryRead;
    use grimworld_logic::models::armor_set::{ArmorSetAssert, ArmorSetRecord};
    use grimworld_logic::models::caste::{
        CasteAssert, CasteRecord, MAX_SKILL_ADRENALINE, errors as caste_errors,
    };
    use grimworld_logic::models::item::{ItemAssert, ItemRecord};
    use grimworld_logic::models::location::{
        INDEX_BOUND, LocationAssert, LocationRecord, errors as location_errors, map,
    };
    use grimworld_logic::models::modifier::{ModifierAssert, ModifierRecord};
    use grimworld_logic::models::outline::CHUNK_SET;
    use grimworld_logic::models::pack::{PackAssert, PackRecord};
    use grimworld_logic::models::quotas::{QuotaBoundsAssert, QuotaSetAssert, QuotaSetRecord};
    use grimworld_logic::models::set_piece::{SetPieceAssert, SetPieceRecord};
    use grimworld_logic::models::skill::{SkillAssert, SkillRecord};
    use grimworld_logic::models::spawn_table::{SpawnTableAssert, SpawnTableRecord};
    use grimworld_logic::packing::{Counter, LIVE_HIGH};
    use grimworld_logic::types::reveal::outline::MAX_CHUNKS;
    use starknet::storage::{Map, StorageMapReadAccess};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::models::versions::{Versions, VersionsTrait};
    use crate::store::RegistryStoreTrait;
    use crate::systems::zone::{IZoneChecksDispatcherTrait, IZoneChecksLibraryDispatcher};
    use super::{Inputs, NOT_IMPLEMENTED, VERSION, errors};

    /// ENG-01 §3.5's layout (`store::registry_layout_tests`), read and written only by the store
    /// (`RegistryStoreTrait`), but for the content's checks (`RegistryAssert::assert_content`; the
    /// store's module doc says why).
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
        /// How many Heart quotas name each `PACK` template, every location's (ENG-R1c-1; an
        /// authored zone's alone before): while it is not 0, the template is refused empty at its
        /// fewest or at its most (R-27 across records, in either order of writes; ENG-09).
        /// Written by `ZoneChecks` in this contract's context.
        pub heart_packs: Map<u32, u32>,
        /// The entry chunks of the gates that lead to each location, one bit each (R-41 across
        /// records: a `LOCATION` write's rectangle holds them; ENG-R1c-1), and how many gates
        /// enter each `(location, chunk)`, so that a bit is cleared when its last gate leaves.
        /// Written by `ZoneChecks` in this contract's context.
        pub gate_entries: Map<u32, felt252>,
        pub gate_entry_counts: Map<(u32, u8), u32>,
        /// The class of an authored zone's checks (`ZoneChecks`, ENG-09), called by
        /// `library_call` in this contract's context; 0 until the administrator sets it, and while
        /// it is 0 no authored zone's record can be written.
        pub zone_checks: ClassHash,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.set_administrator(admin);
    }

    #[abi(embed_v0)]
    impl RegistryReadImpl of IRegistryRead<ContractState> {
        /// `parts(kind)` felts; zeros for a record never written.
        fn record(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            let mut out: Array<felt252> = array![];
            self.read_record_into(kind, id, parts(kind), ref out);
            out.span()
        }
        /// The records of `ids`, one after the other, `parts(kind)` felts each.
        fn records(self: @ContractState, kind: u8, ids: Span<u32>) -> Span<felt252> {
            RegistryAssert::assert_bound(ids.len());
            let count = parts(kind);
            let mut out: Array<felt252> = array![];
            for id in ids {
                self.read_record_into(kind, *id, count, ref out);
            }
            out.span()
        }
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, u32, Span<felt252>) {
            RegistryAssert::assert_bound(requests.len());
            let mut out: Array<felt252> = array![];
            for request in requests {
                let (kind, id) = *request;
                self.read_record_into(kind, id, parts(kind), ref out);
            }
            let versions = self.get_versions();
            (versions.content, versions.inputs, out.span())
        }
        fn content_version(self: @ContractState) -> u32 {
            self.get_versions().content
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
                let last = self.get_last_id(kind);
                let id_wide: u64 = id.into();
                if id_wide == last + 1 {
                    // A new id: none of its keys was ever written (ids are never reused, records
                    // never zeroed), so there is nothing to read or compare.
                    self.name_skills(kind, id, record);
                    self.index(kind, id, record);
                    self.set_new_record(kind, id, record);
                    self.set_last_id(kind, id_wide);
                    self.raise_versions(false);
                    return;
                }
                RegistryAssert::assert_existing(id_wide, last);
            } else {
                self.assert_parent(kind, id);
            }
            self.name_skills(kind, id, record);
            self.index(kind, id, record);
            if self.update_record(kind, id, record) {
                self.raise_versions(Inputs::includes(kind));
            }
        }
        fn last_id(self: @ContractState, kind: u8) -> u32 {
            parts(kind);
            self.get_last_id(kind).try_into().unwrap()
        }
        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            self.assert_admin();
            RegistryAssert::assert_new_admin(admin);
            self.set_administrator(admin);
        }
        fn set_zone_checks(ref self: ContractState, class_hash: ClassHash) {
            self.assert_admin();
            assert(class_hash.is_non_zero(), errors::ZONE_CHECKS_ZERO);
            self.set_zone_class(class_hash);
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
            assert(get_caller_address() == self.get_administrator(), errors::NOT_ADMIN);
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
        /// - the chunk reveal's records (ENG-05): `QUOTAS`, `SPAWN_TABLE`, `PACK` and `SET_PIECE`,
        ///   each its model's `assert_legal` (kinds known and empty entries empty; a pack of at
        ///   most 5 at its fewest, E-3; a set piece's corners wall, D-134, and its placements on
        ///   its interior's floor). That the ids they name exist is the content pipeline's
        ///   (OPS-01).
        /// - `LOCATION`: a dungeon floor's `N` at most 12 (`MAX_CHUNKS`, CM-9; ENG-10b: the outline
        ///   drawn at `create` and its bit-parallel walks assume it), at least 6 (R-40) and below
        ///   its rectangle's area (R-28; `LocationAssert::assert_floor`, ENG-R1c-1); a map format
        ///   it knows.
        /// - an authored zone's records (ENG-01 §3.5's R-table, ENG-09), and the rules a generated
        ///   zone, a dungeon floor or a gate shares with other records (R-11, R-12, R-27, R-30,
        ///   R-41; ENG-R1c-1): every rule between two records at the write of either, against the
        ///   other when it exists (`ZoneAssert`), once the zone checks' class is set.
        /// Every other kind has no bound of design/20.
        fn assert_content(self: @ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind == LOCATION {
                let location = LocationRecord::unpack(record);
                assert(location.target <= MAX_CHUNKS, errors::FLOOR_SIZE);
                location.assert_floor();
                assert(location.map <= map::AUTHORED, location_errors::MAP);
                self.assert_zone(kind, id, record, location.map == map::AUTHORED);
            } else if kind == OUTLINE || kind == GATE || kind == QUOTAS {
                if kind == QUOTAS {
                    QuotaSetRecord::unpack(record).assert_legal();
                }
                self.assert_zone(kind, id, record, false);
            } else if kind == ZONE_CHUNK || kind == CANDIDATES || kind == BRIDGE {
                self.assert_zone(kind, id, record, true);
            } else if kind == MODIFIER {
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
            } else if kind == SPAWN_TABLE {
                SpawnTableRecord::unpack(record).assert_legal();
            } else if kind == PACK {
                let pack = PackRecord::unpack(record);
                pack.assert_legal();
                if self.get_heart_count(id) != 0 {
                    QuotaBoundsAssert::assert_heart(@pack);
                }
            } else if kind == SET_PIECE {
                SetPieceRecord::unpack(record).assert_legal();
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

        /// An authored zone's checks (ENG-01 §3.5's R-table, ENG-09), in `ZoneChecks` by
        /// `library_call`, in this contract's context: for a record of an authored zone (`own`: its
        /// own kinds, or a `LOCATION` with the marker) the class must be set; for the other kinds
        /// their rules shared with an authored zone run once it is (before, no authored zone can
        /// exist).
        fn assert_zone(self: @ContractState, kind: u8, id: u32, record: Span<felt252>, own: bool) {
            let checks = self.get_zone_class();
            if checks.is_zero() {
                assert(!own, errors::NO_ZONE_CHECKS);
                return;
            }
            IZoneChecksLibraryDispatcher { class_hash: checks }.check(kind, id, record);
        }

        /// A sequential id that is not new must exist: at most `last_id` (ids are append-only).
        #[inline(always)]
        fn assert_existing(id: u64, last: u64) {
            assert(id <= last, errors::NOT_NEXT);
        }

        /// A composite id names an existing parent: `QUOTAS` its location (the same id, D-145),
        /// `OUTLINE` a location (and a chunk below 225, or 255), `SHOP` a location as its hub (its
        /// existence only: that it is a town or an outpost is the content pipeline's check).
        /// `ZONE_CHUNK` a location and a chunk below 225, `BRIDGE` a location and a chunk below
        /// 225, `CANDIDATES` a location (ENG-09). `TASK` and `QUEST` take the administrator's
        /// quiver ids as they are (D-145): that a quiver id exists is the content pipeline's check
        /// (OPS-01).
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
            } else if kind == ZONE_CHUNK {
                let (location, chunk) = DivRem::div_rem(id, 256);
                assert(chunk < INDEX_BOUND.into(), errors::CHUNK);
                self.assert_exists(LOCATION, location);
            } else if kind == BRIDGE {
                let (location, rest) = DivRem::div_rem(id, 4096);
                assert(rest / 16 < INDEX_BOUND.into(), errors::CHUNK);
                self.assert_exists(LOCATION, location);
            } else if kind == CANDIDATES {
                self.assert_exists(LOCATION, id / 2);
            }
        }

        /// A record exists when its part 0 is not 0 (ENG-01 §3.5).
        #[inline(always)]
        fn assert_exists(self: @ContractState, kind: u8, id: u32) {
            assert(self.has_record(kind, id), errors::NO_PARENT);
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
            let old: [u16; 4] = if self.has_record(CASTE, id) {
                let mut out = array![];
                self.read_record_into(CASTE, id, parts(CASTE), ref out);
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
                        let count = self.get_caste_count(s.into());
                        self.set_caste_count(s.into(), count + now - before);
                    }
                }
            }
        }

        /// A `QUOTAS` or a `GATE` written (after every check): `ZoneChecks` moves the counts of
        /// `heart_packs` (R-27's reverse check, ENG-09) and the gates' entries (`gate_entries`,
        /// R-41's, ENG-R1c-1) when the class is set.
        fn index(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind != QUOTAS && kind != GATE {
                return;
            }
            let checks = self.get_zone_class();
            if checks.is_non_zero() {
                IZoneChecksLibraryDispatcher { class_hash: checks }.index(kind, id, record);
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

        /// Appends the `count` parts of `(kind, id)` to `out`, through the store: the content's
        /// checks' read (`assert_content`), kept by this name while ENG-05 and CBT-05b add checks
        /// there.
        #[inline(always)]
        fn read_into(self: @ContractState, kind: u8, id: u32, count: u8, ref out: Array<felt252>) {
            self.read_record_into(kind, id, count, ref out)
        }

        /// The content version raised by one (D-141), and the inputs version with it when the
        /// record changed is an `input` of the flattening (D-169): one read and one write of one
        /// slot.
        #[inline(always)]
        fn raise_versions(ref self: ContractState, input: bool) {
            let versions = self.get_versions().raised(input);
            self.set_versions(versions);
        }
    }
}

/// The flattening's input kinds (D-169): `SKILL`, `ITEM` and `MODIFIER`, and none of the 22 others.
/// This guards the current list only (a change of it must change this test); that the list is what
/// `Hub.set_build` asks the registry for is `test_build::test_set_build_requests_the_input_kinds`.
#[cfg(test)]
mod inputs_tests {
    use grimworld_logic::content::{ITEM, LAST_KIND, MODIFIER, SKILL};
    use super::Inputs;

    #[test]
    // gas: raised, ENG-09: three more kinds to loop over (LAST_KIND 28)
    #[available_gas(l2_gas: 115815)] // ceil(1.05 × 110300 measured)
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
    use crate::store::RegistryStoreTrait;
    use super::Registry;
    use super::Registry::InternalTrait;

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_version_cost_baseline() {
        let state = Registry::contract_state_for_testing();
        let _ = @state;
    }

    // `bundle`'s part of the versions: one read of one slot, unpacked into the two (D-169).
    #[test]
    #[available_gas(l2_gas: 37989)] // ceil(1.05 × 36180 measured)
    fn test_version_cost_read() {
        let state = @Registry::contract_state_for_testing();
        assert(state.get_versions().content == 0, 'version 0');
    }

    // `set_record`'s part, when the record changed: the read and the write of the raise.
    #[test]
    #[available_gas(l2_gas: 524633)] // ceil(1.05 × 499650 measured)
    fn test_version_cost_raise() {
        let mut state = Registry::contract_state_for_testing();
        state.raise_versions(false);
    }

    // `set_record`'s part when the changed record is an input of the flattening (D-169): both
    // versions raised in the same write; against `test_version_cost_raise`, the added cost.
    #[test]
    #[available_gas(l2_gas: 525998)] // ceil(1.05 × 500950 measured)
    fn test_version_cost_raise_input() {
        let mut state = Registry::contract_state_for_testing();
        state.raise_versions(true);
    }

    // The baseline of the next one: a version already written.
    #[test]
    #[available_gas(l2_gas: 435992)] // ceil(1.05 × 415230 measured)
    fn test_version_cost_stored_baseline() {
        let state = Registry::contract_state_for_testing();
        store(test_address(), selector!("versions"), array![7].span());
        let _ = @state;
    }

    // Every raise after the first: the slot holds a version, the write overwrites it.
    #[test]
    #[available_gas(l2_gas: 533264)] // ceil(1.05 × 507870 measured)
    fn test_version_cost_raise_again() {
        let mut state = Registry::contract_state_for_testing();
        store(test_address(), selector!("versions"), array![7].span());
        state.raise_versions(false);
    }
}
