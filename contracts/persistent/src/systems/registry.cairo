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
    use grimworld_logic::models::bridge::{
        Bridge, BridgeAssert, BridgeRecord, errors as bridge_errors,
    };
    use grimworld_logic::models::candidates::{CandidatesAssert, CandidatesRecord};
    use grimworld_logic::models::caste::{
        CasteAssert, CasteRecord, MAX_SKILL_ADRENALINE, errors as caste_errors,
    };
    use grimworld_logic::models::gate::GateRecord;
    use grimworld_logic::models::item::{ItemAssert, ItemRecord};
    use grimworld_logic::models::location::{
        INDEX_BOUND, Location, LocationRecord, LocationTrait, errors as location_errors, map,
    };
    use grimworld_logic::models::modifier::{ModifierAssert, ModifierRecord};
    use grimworld_logic::models::outline::{
        CHUNK_SET, OutlineAssert, OutlineRecord, OutlineTrait,
    };
    use grimworld_logic::models::pack::{Pack, PackAssert, PackRecord};
    use grimworld_logic::models::quotas::{
        QuotaBoundsAssert, QuotaSet, QuotaSetAssert, QuotaSetRecord, kind as quota_kind,
    };
    use grimworld_logic::models::set_piece::{SetPieceAssert, SetPieceRecord};
    use grimworld_logic::models::skill::{SkillAssert, SkillRecord};
    use grimworld_logic::models::spawn_table::{SpawnTableAssert, SpawnTableRecord};
    use grimworld_logic::models::zone_chunk::{
        ZoneChunk, ZoneChunkAssert, ZoneChunkRecord, ZoneChunkTrait, errors as chunk_errors,
    };
    use grimworld_logic::packing::{Counter, LIVE_HIGH};
    use grimworld_logic::types::reveal::board::BoardTrait;
    use grimworld_logic::types::reveal::outline::MAX_CHUNKS;
    use starknet::storage::{Map, StorageMapReadAccess};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::models::versions::{Versions, VersionsTrait};
    use crate::store::RegistryStoreTrait;
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
        /// How many Heart quotas of authored zones name each `PACK` template: while it is not 0,
        /// the template is refused empty at its fewest or at its most (R-27 across records, in
        /// either order of writes; ENG-09).
        pub heart_packs: Map<u32, u32>,
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
                    self.name_hearts(kind, id, record);
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
            self.name_hearts(kind, id, record);
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
        ///   drawn at `create` and its bit-parallel walks assume it); a map format it knows.
        /// - an authored zone's records (ENG-01 §3.5's R-table, ENG-09): every rule between two
        ///   records at the write of either, against the other when it exists (`ZoneAssert`).
        /// Every other kind has no bound of design/20.
        fn assert_content(self: @ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind == LOCATION {
                let location = LocationRecord::unpack(record);
                assert(location.target <= MAX_CHUNKS, errors::FLOOR_SIZE);
                assert(location.map <= map::AUTHORED, location_errors::MAP);
                self.assert_location(id, @location);
            } else if kind == OUTLINE {
                self.assert_outline(id, OutlineRecord::unpack(record).bits());
            } else if kind == ZONE_CHUNK {
                self.assert_zone_chunk(id, @ZoneChunkRecord::unpack(record));
            } else if kind == CANDIDATES {
                self.assert_candidates(id, CandidatesRecord::unpack(record).sets);
            } else if kind == BRIDGE {
                self.assert_bridge(id, @BridgeRecord::unpack(record));
            } else if kind == GATE {
                self.assert_gate(id, record);
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
            } else if kind == QUOTAS {
                let quotas = QuotaSetRecord::unpack(record);
                quotas.assert_legal();
                self.assert_quotas(id, @quotas);
            } else if kind == SPAWN_TABLE {
                SpawnTableRecord::unpack(record).assert_legal();
            } else if kind == PACK {
                let pack = PackRecord::unpack(record);
                pack.assert_legal();
                if self.heart_packs.read(id) != 0 {
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

        /// A sequential id that is not new must exist: at most `last_id` (ids are append-only).
        #[inline(always)]
        fn assert_existing(id: u64, last: u64) {
            assert(id <= last, errors::NOT_NEXT);
        }

        /// A composite id names an existing parent: `QUOTAS` its location (the same id, D-145),
        /// `OUTLINE` a location (and a chunk below 225, or 255), `SHOP` a location as its hub (its
        /// existence only: that it is a town or an outpost is the content pipeline's check).
        /// `ZONE_CHUNK` a location and a chunk below 225, `BRIDGE` a location and a chunk below 225,
        /// `CANDIDATES` a location (ENG-09). `TASK` and `QUEST` take the administrator's quiver ids
        /// as they are (D-145): that a quiver id exists is the content pipeline's check (OPS-01).
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


    /// The content's checks of an authored zone's records (ENG-01 §3.5's R-table; ENG-08's
    /// format, built by ENG-09; the same cases as `tools/map-format/checks.json`, which the
    /// converter and the editor refuse with the same codes). **Every rule between two records is
    /// checked at the write of either, against the other when it exists** (CBT-02c's precedent,
    /// DS-18), so that no order of writes and no rewrite lets a breach through; the converter's
    /// order (`LOCATION` with the marker, the chunk set, `CANDIDATES`, `QUOTAS`, the masks, each
    /// `ZONE_CHUNK` and its `BRIDGE`s, the `GATE`s) only makes each write find what it checks
    /// against. The records of an authored zone's own kinds (`ZONE_CHUNK`, `CANDIDATES`, `BRIDGE`)
    /// are checked whatever the marker; the rules on kinds every location has (`QUOTAS`' bounds,
    /// the chunk set's R-11, the entry's R-26) bind a zone with the marker, and the `LOCATION`
    /// write that sets it re-runs them (ENG-R1c applies the shared bounds to generated zones).
    /// The administrator pays them once; no player's call makes them again. Each read goes
    /// through the store; nothing is written.
    #[generate_trait]
    pub impl ZoneAssert of ZoneAssertTrait {
        /// A record's parts as stored (zeros for none).
        fn parts_of(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            let mut out = array![];
            self.read_into(kind, id, parts(kind), ref out);
            out.span()
        }

        /// The location `id`, when it is an authored zone (a zone with the marker).
        fn authored(self: @ContractState, id: u32) -> Option<Location> {
            let record = self.parts_of(LOCATION, id);
            if *record[0] == 0 {
                return None;
            }
            let location = LocationRecord::unpack(record);
            if location.target == 0 && location.authored() {
                Some(location)
            } else {
                None
            }
        }

        /// The zone's chunk set as the reveal reads it: its `OUTLINE`, or the whole rectangle
        /// without one.
        fn chunk_set(self: @ContractState, location: u32, width: u8, height: u8) -> felt252 {
            let record = self.parts_of(OUTLINE, location * 256 + CHUNK_SET.into());
            if *record[0] == 0 {
                OutlineTrait::rectangle(width, height)
            } else {
                OutlineRecord::unpack(record).bits()
            }
        }

        /// The six quotas' candidate sets (0 where no `CANDIDATES` part holds them).
        fn candidates(self: @ContractState, location: u32) -> Span<felt252> {
            let [c0, c1, c2] = CandidatesRecord::unpack(
                self.parts_of(CANDIDATES, location * 2),
            )
                .sets;
            let [c3, c4, c5] = CandidatesRecord::unpack(
                self.parts_of(CANDIDATES, location * 2 + 1),
            )
                .sets;
            array![c0, c1, c2, c3, c4, c5].span()
        }

        fn quotas(self: @ContractState, location: u32) -> Option<QuotaSet> {
            let record = self.parts_of(QUOTAS, location);
            if *record[0] == 0 {
                None
            } else {
                Some(QuotaSetRecord::unpack(record))
            }
        }

        fn zone_chunk(self: @ContractState, location: u32, chunk: u8) -> Option<ZoneChunk> {
            let record = self.parts_of(ZONE_CHUNK, location * 256 + chunk.into());
            if *record[0] == 0 {
                None
            } else {
                Some(ZoneChunkRecord::unpack(record))
            }
        }

        fn bridge(self: @ContractState, location: u32, chunk: u8, k: u8) -> Option<Bridge> {
            let record = self.parts_of(BRIDGE, location * 4096 + chunk.into() * 16 + k.into());
            if *record[0] == 0 {
                None
            } else {
                Some(BridgeRecord::unpack(record))
            }
        }

        /// R-12, R-13, R-27, R-29 and R-30 (`QuotaBoundsAssert::assert_bounds`) of an authored
        /// zone's quotas, against its chunk set's members, its candidates and the Heart templates.
        fn assert_bounds(
            self: @ContractState, quotas: @QuotaSet, members: felt252, candidates: Span<felt252>,
        ) {
            let mut hearts: Array<Option<Pack>> = array![];
            for entry in quotas.quotas.span() {
                let mut pack = None;
                if *entry.kind == quota_kind::HEART {
                    let record = self.parts_of(PACK, (*entry.param).into());
                    if *record[0] != 0 {
                        pack = Some(PackRecord::unpack(record));
                    }
                }
                hearts.append(pack);
            }
            quotas.assert_bounds(BoardTrait::count(members), Some(candidates), hearts.span());
        }

        /// The tiles of chunk `chunk` that bear authored content besides its own placements: the
        /// anchors of the gates it names that anchor there, and the entry when it is the entry
        /// chunk (R-37).
        fn anchors(
            self: @ContractState, location: u32, chunk: u8, record: @ZoneChunk, entry: Option<u8>,
        ) -> felt252 {
            let mut tiles: felt252 = match entry {
                Some(tile) => BoardTrait::pow(tile),
                None => 0,
            };
            for gate in record.gates.span() {
                if *gate != 0 {
                    let parts = self.parts_of(GATE, (*gate).into());
                    if *parts[0] != 0 {
                        let value = GateRecord::unpack(parts);
                        if value.source.into() == location && value.anchor_chunk == chunk {
                            tiles = BoardTrait::or(tiles, BoardTrait::pow(value.anchor_tile));
                        }
                    }
                }
            }
            tiles
        }

        /// The entry tile when `chunk` is an authored zone's entry chunk.
        fn entry(self: @ContractState, location: u32, chunk: u8) -> Option<u8> {
            match self.authored(location) {
                Some(zone) => if zone.entry_chunk == chunk {
                    Some(zone.entry_tile)
                } else {
                    None
                },
                None => None,
            }
        }

        /// A `LOCATION` write that leaves or makes it an authored zone: R-11 against its stored
        /// chunk set (the rectangle may shrink); R-26 and R-37 against its entry chunk's record
        /// and bridges; R-12, R-13, R-27, R-29 and R-30 against its stored `QUOTAS`.
        fn assert_location(self: @ContractState, id: u32, location: @Location) {
            if *location.target != 0 || !location.authored() {
                return;
            }
            let set = self.parts_of(OUTLINE, id * 256 + CHUNK_SET.into());
            if *set[0] != 0 {
                OutlineAssert::assert_within(
                    OutlineRecord::unpack(set).bits(), *location.width, *location.height,
                );
            }
            let chunk = *location.entry_chunk;
            if let Some(record) = self.zone_chunk(id, chunk) {
                record.assert_entry(*location.entry_tile);
                let tile = BoardTrait::pow(*location.entry_tile);
                for k in 0..record.bridges {
                    if let Some(bridge) = self.bridge(id, chunk, k) {
                        bridge.assert_clear(tile);
                    }
                }
            }
            if let Some(quotas) = self.quotas(id) {
                let members = self.chunk_set(id, *location.width, *location.height);
                self.assert_bounds(@quotas, members, self.candidates(id));
            }
        }

        /// An `OUTLINE` write. The chunk set (an authored zone's): R-11 within the rectangle, R-12
        /// and R-30 against `QUOTAS` (its members); whatever the marker, R-31 against both
        /// `CANDIDATES` and R-24 against every chunk it drops (none may hold a `ZONE_CHUNK`). A
        /// border chunk's mask: R-20 against that chunk's `ZONE_CHUNK`.
        fn assert_outline(self: @ContractState, id: u32, bits: felt252) {
            let (location, chunk) = DivRem::div_rem(id, 256);
            if chunk != CHUNK_SET.into() {
                if chunk < INDEX_BOUND.into() {
                    let chunk: u8 = chunk.try_into().unwrap();
                    if let Some(record) = self.zone_chunk(location, chunk) {
                        ZoneChunkAssert::assert_mask(record.walls, bits);
                    }
                }
                return;
            }
            let candidates = self.candidates(location);
            CandidatesAssert::assert_within(candidates, bits);
            if let Some(zone) = self.authored(location) {
                OutlineAssert::assert_within(bits, zone.width, zone.height);
                if let Some(quotas) = self.quotas(location) {
                    self.assert_bounds(@quotas, bits, candidates);
                }
            }
            let old = self.parts_of(OUTLINE, id);
            let before = if *old[0] == 0 {
                let zone = LocationRecord::unpack(self.parts_of(LOCATION, location));
                OutlineTrait::rectangle(zone.width, zone.height)
            } else {
                OutlineRecord::unpack(old).bits()
            };
            let mut dropped = BoardTrait::minus(before, bits);
            while dropped != 0 {
                let chunk = BoardTrait::nth(dropped, 0);
                dropped -= BoardTrait::pow(chunk);
                assert(self.zone_chunk(location, chunk).is_none(), chunk_errors::NOT_IN_SET);
            }
        }

        /// A `QUOTAS` write of an authored zone: R-12, R-13, R-27, R-29 and R-30 against its chunk
        /// set, `CANDIDATES` and Heart templates; R-15 again on the candidate chunks of every quota
        /// whose kind changed (an object quota counts against 3 objects, a Heart against 2 packs).
        fn assert_quotas(self: @ContractState, id: u32, quotas: @QuotaSet) {
            let Some(zone) = self.authored(id) else {
                return;
            };
            let candidates = self.candidates(id);
            let members = self.chunk_set(id, zone.width, zone.height);
            self.assert_bounds(quotas, members, candidates);
            let before: QuotaSet = match self.quotas(id) {
                Some(stored) => stored,
                None => QuotaSet { quotas: [Default::default(); 6] },
            };
            let mut changed: felt252 = 0;
            for i in 0..6_u32 {
                if *before.quotas.span()[i].kind != *quotas.quotas.span()[i].kind {
                    changed = BoardTrait::or(changed, *candidates[i]);
                }
            }
            self.assert_chunks(id, changed, candidates, quotas);
        }

        /// R-14 and R-15 on every chunk of `chunks` that holds a `ZONE_CHUNK`.
        fn assert_chunks(
            self: @ContractState,
            location: u32,
            chunks: felt252,
            candidates: Span<felt252>,
            quotas: @QuotaSet,
        ) {
            let mut left = chunks;
            while left != 0 {
                let chunk = BoardTrait::nth(left, 0);
                left -= BoardTrait::pow(chunk);
                if let Some(record) = self.zone_chunk(location, chunk) {
                    record.assert_legal(chunk, candidates, quotas);
                }
            }
        }

        /// A `CANDIDATES` write (`sets`: quotas `3 k` to `3 k + 2`): R-31 against the chunk set;
        /// R-12, R-13, R-27, R-29 and R-30 against an authored zone's `QUOTAS`; R-14 and R-15
        /// again on each chunk whose candidacy changed.
        fn assert_candidates(self: @ContractState, id: u32, sets: [felt252; 3]) {
            let (location, k) = DivRem::div_rem(id, 2);
            let zone = self.parts_of(LOCATION, location);
            if *zone[0] == 0 {
                return;
            }
            let zone = LocationRecord::unpack(zone);
            let [s0, s1, s2] = sets;
            let stored = self.candidates(location);
            let mut candidates: Array<felt252> = array![];
            let mut changed: felt252 = 0;
            let mut i: u32 = 0;
            for old in stored {
                let new = if i / 3 != k {
                    *old
                } else if i % 3 == 0 {
                    s0
                } else if i % 3 == 1 {
                    s1
                } else {
                    s2
                };
                let moved = BoardTrait::minus(BoardTrait::or(*old, new), BoardTrait::and(*old, new));
                changed = BoardTrait::or(changed, moved);
                candidates.append(new);
                i += 1;
            }
            let candidates = candidates.span();
            let members = self.chunk_set(location, zone.width, zone.height);
            CandidatesAssert::assert_within(array![s0, s1, s2].span(), members);
            let quotas: QuotaSet = match self.quotas(location) {
                Some(quotas) => {
                    if self.authored(location).is_some() {
                        self.assert_bounds(@quotas, members, candidates);
                    }
                    quotas
                },
                None => QuotaSet { quotas: [Default::default(); 6] },
            };
            self.assert_chunks(location, changed, candidates, @quotas);
        }

        /// A `ZONE_CHUNK` write: R-24 (in the chunk set), R-20 (its mask), R-14 and R-15 (its
        /// placements, against `CANDIDATES` and `QUOTAS`), R-26 (the entry chunk of an authored
        /// zone); R-18 again for each gate it names that anchors here, and R-25: a gate it no
        /// longer names may not anchor here; R-35: its count may not drop below a written
        /// `BRIDGE`; R-34 and R-37 again for each of its bridges.
        fn assert_zone_chunk(self: @ContractState, id: u32, record: @ZoneChunk) {
            let (location, chunk) = DivRem::div_rem(id, 256);
            let zone = self.parts_of(LOCATION, location);
            if *zone[0] == 0 || chunk >= INDEX_BOUND.into() {
                return;
            }
            let zone = LocationRecord::unpack(zone);
            let chunk: u8 = chunk.try_into().unwrap();
            let mask = self.parts_of(OUTLINE, id);
            let mask = if *mask[0] == 0 {
                0
            } else {
                OutlineRecord::unpack(mask).bits()
            };
            record.assert_outline(chunk, self.chunk_set(location, zone.width, zone.height), mask);
            let quotas: QuotaSet = match self.quotas(location) {
                Some(quotas) => quotas,
                None => QuotaSet { quotas: [Default::default(); 6] },
            };
            record.assert_legal(chunk, self.candidates(location), @quotas);
            let entry = self.entry(location, chunk);
            if let Some(tile) = entry {
                record.assert_entry(tile);
            }
            // The gates: those it names anchored on its floor, none it drops anchored here
            for gate in record.gates.span() {
                if *gate != 0 {
                    let parts = self.parts_of(GATE, (*gate).into());
                    if *parts[0] != 0 {
                        let value = GateRecord::unpack(parts);
                        if value.source.into() == location && value.anchor_chunk == chunk {
                            record.assert_gate(*gate, value.anchor_tile);
                        }
                    }
                }
            }
            let (dropped, count): ([u16; 2], u8) = match self.zone_chunk(location, chunk) {
                Some(old) => (old.gates, old.bridges),
                None => ([0, 0], 0),
            };
            for gate in dropped.span() {
                if *gate != 0 && !record.names(*gate) {
                    let parts = self.parts_of(GATE, (*gate).into());
                    if *parts[0] != 0 {
                        let value = GateRecord::unpack(parts);
                        assert(
                            value.source.into() != location || value.anchor_chunk != chunk,
                            chunk_errors::GATE_INDEX,
                        );
                    }
                }
            }
            // The bridges: none past the new count, each below it still on floor and clear
            let mut k = *record.bridges;
            while k < count {
                assert(self.bridge(location, chunk, k).is_none(), bridge_errors::INDEX);
                k += 1;
            }
            let anchors = self.anchors(location, chunk, record, entry);
            let odd = (chunk / 15) % 2 == 1;
            for k in 0..*record.bridges {
                if let Some(bridge) = self.bridge(location, chunk, k) {
                    bridge.assert_on(k, record, odd);
                    bridge.assert_clear(anchors);
                }
            }
        }

        /// A `BRIDGE` write: R-33 (a deck, two distinct ends off it); against its chunk's
        /// `ZONE_CHUNK` (none: no bridge, R-35), R-35, R-34 extended to the deck and R-37, the
        /// gates anchored there and the entry included.
        fn assert_bridge(self: @ContractState, id: u32, bridge: @Bridge) {
            bridge.assert_legal();
            let (location, rest) = DivRem::div_rem(id, 4096);
            let (chunk, k) = DivRem::div_rem(rest, 16);
            if chunk >= INDEX_BOUND.into() {
                return;
            }
            let chunk: u8 = chunk.try_into().unwrap();
            let k: u8 = k.try_into().unwrap();
            let Some(record) = self.zone_chunk(location, chunk) else {
                core::panic_with_felt252(bridge_errors::INDEX)
            };
            bridge.assert_on(k, @record, (chunk / 15) % 2 == 1);
            let entry = self.entry(location, chunk);
            bridge.assert_clear(self.anchors(location, chunk, @record, entry));
        }

        /// A `GATE` write anchored in a chunk that holds a `ZONE_CHUNK`: R-18 (the anchor
        /// walkable), R-25 (the chunk names the gate) and R-37 (not on a bridge).
        fn assert_gate(self: @ContractState, id: u32, record: Span<felt252>) {
            let gate = GateRecord::unpack(record);
            let location: u32 = gate.source.into();
            let Some(chunk) = self.zone_chunk(location, gate.anchor_chunk) else {
                return;
            };
            chunk.assert_gate(id.try_into().unwrap(), gate.anchor_tile);
            let tile = BoardTrait::pow(gate.anchor_tile);
            for k in 0..chunk.bridges {
                if let Some(bridge) = self.bridge(location, gate.anchor_chunk, k) {
                    bridge.assert_clear(tile);
                }
            }
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

        /// A `QUOTAS` of an authored zone, or a `LOCATION` that gains or loses the marker, written
        /// (after every check): the counts of `heart_packs` move from the Heart templates the stored
        /// quotas named (when the zone was authored) to those the new ones name (when it is), as
        /// `name_skills` does for DS-18 (R-27's reverse check, ENG-09).
        fn name_hearts(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            let (old, new) = if kind == QUOTAS {
                if !self.authored(id).is_some() {
                    return;
                }
                (self.quotas(id), Some(QuotaSetRecord::unpack(record)))
            } else if kind == LOCATION {
                let was = self.authored(id).is_some();
                let new = LocationRecord::unpack(record);
                let now = new.target == 0 && new.authored();
                if was == now {
                    return;
                }
                let quotas = self.quotas(id);
                if was {
                    (quotas, None)
                } else {
                    (None, quotas)
                }
            } else {
                return;
            };
            if let Some(quotas) = old {
                for entry in quotas.quotas.span() {
                    if *entry.kind == quota_kind::HEART {
                        let count = self.get_heart_count((*entry.param).into());
                        self.set_heart_count((*entry.param).into(), count - 1);
                    }
                }
            }
            if let Some(quotas) = new {
                for entry in quotas.quotas.span() {
                    if *entry.kind == quota_kind::HEART {
                        let count = self.get_heart_count((*entry.param).into());
                        self.set_heart_count((*entry.param).into(), count + 1);
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
    #[available_gas(l2_gas: 104255)] // ceil(1.05 × 99290 measured)
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
