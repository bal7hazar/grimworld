// ENG-03: `Registry` stores content as data (ENG-01 §3.5). The administrator writes records with
// `set_record`, which enforces the part count, `LIVE` in part 0, the content's checks of design/20
// (D-166: a record past its per-source bound is refused), and the allocation of ids
// (sequential: `last_id + 1`; composite: the parent exists); every changed record raises the
// content version by one, an unchanged rewrite does not (D-141). Everyone reads with `record`,
// `records` and `bundle`, which returns the version first. A record never written reads as zeros.
use grimworld_logic::content::{
    ARMOR_SET, BOOK, BRIDGE, CANDIDATES, CASTE, GATE, ITEM, LAST_KIND, LOCATION, MODIFIER, OUTLINE,
    PACK, QUEST, QUOTAS, REGION, Record, SET_PIECE, SHOP, SKILL, SPAWN_TABLE, TASK, ZONE_CHUNK,
    is_sequential, parts,
};
use grimworld_logic::interface::{
    IRegistryReadDispatcher, IRegistryReadDispatcherTrait, IRegistryReadSafeDispatcher,
    IRegistryReadSafeDispatcherTrait,
};
use grimworld_logic::models::armor_set::{ArmorSetRecord, ArmorSetTrait};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait, errors as caste_errors};
use grimworld_logic::models::chunk::Object;
use grimworld_logic::models::item::{
    ItemRecord, ItemTrait, class as item_class, errors as item_errors,
};
use grimworld_logic::models::location::{
    LocationRecord, LocationTrait, errors as location_errors, kind as location_kind,
};
use grimworld_logic::models::modifier::{
    ModifierRecord, ModifierTrait, errors as modifier_errors, slot as modifier_slot,
};
use grimworld_logic::models::pack::{PackCaste, PackRecord, PackTrait, errors as pack_errors};
use grimworld_logic::models::quotas::{
    Quota, QuotaSet, QuotaSetRecord, errors as quotas_errors, kind as quota_kind,
};
use grimworld_logic::models::set_piece::{
    SetPack, SetPieceRecord, SetPieceTrait, errors as set_piece_errors,
};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::models::spawn_table::{
    Spawn, SpawnTableRecord, SpawnTableTrait, errors as spawn_errors,
};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::types::combat::{condition, damage, skill_kind, weapon};
use grimworld_logic::types::effect::{
    Entry, EntryTrait, errors as entry_errors, filter, guard, kind, shape, target,
};
use grimworld_logic::types::passive::{
    Passive, PassiveTrait, Source, errors as passive_errors, id as passive_id,
};
use grimworld_persistent::systems::registry::errors::{
    FLOOR_SIZE, NOT_ADMIN, NOT_LIVE, NOT_NEXT, NO_PARENT, OUTLINE_CHUNK, PART_COUNT, TOO_MANY,
    ZERO_ADMIN, ZERO_ID,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait, IRegistryAdminSafeDispatcher,
    IRegistryAdminSafeDispatcherTrait, NOT_IMPLEMENTED,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, map_entry_address, start_cheat_caller_address,
    store,
};
use starknet::ContractAddress;

const ADMIN: felt252 = 0xad;
const OTHER: felt252 = 0xbad;
/// 2^251: the first value above `LIVE`'s bit.
const ABOVE_LIVE: felt252 = 0x800000000000000000000000000000000000000000000000000000000000000;
const UNKNOWN_KIND: felt252 = 'registry: unknown kind';

#[derive(Copy, Drop)]
struct Registry {
    address: ContractAddress,
    admin: IRegistryAdminDispatcher,
    safe: IRegistryAdminSafeDispatcher,
    read: IRegistryReadDispatcher,
    safe_read: IRegistryReadSafeDispatcher,
}

#[generate_trait]
impl RegistryFixture of Fixture {
    /// A registry deployed with `ADMIN`, the caller set to `ADMIN`.
    fn deploy() -> Registry {
        let class = declare("Registry").unwrap().contract_class();
        let (address, _) = class.deploy(@array![ADMIN]).unwrap();
        start_cheat_caller_address(address, ADMIN.try_into().unwrap());
        Registry {
            address,
            admin: IRegistryAdminDispatcher { contract_address: address },
            safe: IRegistryAdminSafeDispatcher { contract_address: address },
            read: IRegistryReadDispatcher { contract_address: address },
            safe_read: IRegistryReadSafeDispatcher { contract_address: address },
        }
    }

    /// The same, with the zone checks' class set: a `GATE` and a `QUOTAS` are refused without it
    /// (BND-01).
    fn deploy_checked() -> Registry {
        let r = Self::deploy();
        r.admin.set_zone_checks(*declare("ZoneChecks").unwrap().contract_class().class_hash);
        r
    }

    fn version(self: Registry) -> u32 {
        self.read.content_version()
    }

    /// The inputs version (D-169), as `bundle` returns it.
    fn inputs(self: Registry) -> u32 {
        let (_, inputs, _) = self.read.bundle(array![].span());
        inputs
    }

    /// `count` 3-part records (`BOOK`, the widest kind) written straight into storage, the content
    /// version 5 and the inputs version 7.
    fn books(self: Registry, count: u32) -> Array<(u8, u32)> {
        let mut requests: Array<(u8, u32)> = array![];
        for id in 1..count + 1 {
            for part in 0..3_u8 {
                store(
                    self.address,
                    map_entry_address(
                        selector!("records"), array![BOOK.into(), id.into(), part.into()].span(),
                    ),
                    array![Felts::live(id.into())].span(),
                );
            }
            requests.append((BOOK, id));
        }
        store(self.address, selector!("versions"), array![5 + 7 * 0x100000000].span());
        requests
    }
}

/// Records of one, two or three parts, `LIVE` set in part 0.
#[generate_trait]
impl FeltsImpl of Felts {
    fn live(value: felt252) -> felt252 {
        LIVE + value
    }

    fn one(value: felt252) -> Span<felt252> {
        array![Self::live(value)].span()
    }

    fn two(a: felt252, b: felt252) -> Span<felt252> {
        array![Self::live(a), b].span()
    }

    fn three(a: felt252, b: felt252, c: felt252) -> Span<felt252> {
        array![Self::live(a), b, c].span()
    }
}

// --- set_record: what it writes -----------------------------------------------------------------

#[test]
// gas: raised, ENG-09: the registry reads its zone checks' class at this kind's write (one slot)
#[available_gas(l2_gas: 5159868)] // ceil(1.05 × 4914160 measured)
fn test_set_record_new_sequential() {
    let r = Fixture::deploy();
    assert(r.admin.last_id(LOCATION) == 0, 'none yet');
    r.admin.set_record(LOCATION, 1, Felts::two(5, 6));
    assert(r.admin.last_id(LOCATION) == 1, 'last id 1');
    assert(r.read.record(LOCATION, 1) == Felts::two(5, 6), 'read back');
    r.admin.set_record(LOCATION, 2, Felts::two(7, 0));
    assert(r.admin.last_id(LOCATION) == 2, 'last id 2');
    assert(r.read.record(LOCATION, 2) == Felts::two(7, 0), 'a part of 0');
    assert(r.admin.last_id(GATE) == 0, 'other kinds apart');
}

// An existing record's values change (design/01 rule 2: ids are append-only, values are not).
#[test]
// gas: raised, ENG-10b: a LOCATION record's content check (N at most 12)
#[available_gas(l2_gas: 5355273)] // ceil(1.05 × 5100260 measured)
fn test_set_record_existing_changes() {
    let r = Fixture::deploy();
    r.admin.set_record(LOCATION, 1, Felts::two(5, 6));
    r.admin.set_record(LOCATION, 2, Felts::two(7, 8));
    r.admin.set_record(LOCATION, 1, Felts::two(9, 0));
    assert(r.read.record(LOCATION, 1) == Felts::two(9, 0), 'changed');
    assert(r.read.record(LOCATION, 2) == Felts::two(7, 8), 'the other kept');
    assert(r.admin.last_id(LOCATION) == 2, 'last id kept');
}

// Composite kinds (`OUTLINE`, `SHOP`): any id whose parent exists; `last_id` stays 0.
#[test]
// gas: raised, ENG-09: the registry reads its zone checks' class at this kind's write (one slot)
#[available_gas(l2_gas: 8375861)] // ceil(1.05 × 7977010 measured)
#[feature("safe_dispatcher")]
fn test_set_record_composite_needs_parent() {
    let r = Fixture::deploy();
    // Location 2 does not exist yet: its outline and a shop of hub 2 are refused.
    let refused = r.safe.set_record(OUTLINE, 2 * 256 + 255, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'outline without location');
    let refused = r.safe.set_record(SHOP, 2 * 16 + 1, Felts::two(1, 0));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'shop without hub');
    r.admin.set_record(LOCATION, 1, Felts::two(0, 0));
    r.admin.set_record(LOCATION, 2, Felts::two(0, 0));
    r.admin.set_record(OUTLINE, 2 * 256 + 255, Felts::one(1));
    r.admin.set_record(OUTLINE, 2 * 256 + 16, Felts::one(2));
    r.admin.set_record(SHOP, 2 * 16 + 1, Felts::two(3, 4));
    assert(r.read.record(OUTLINE, 2 * 256 + 255) == Felts::one(1), 'chunk set');
    assert(r.read.record(OUTLINE, 2 * 256 + 16) == Felts::one(2), 'border mask');
    assert(r.read.record(SHOP, 2 * 16 + 1) == Felts::two(3, 4), 'shop');
    assert(r.admin.last_id(OUTLINE) == 0 && r.admin.last_id(SHOP) == 0, 'composite: last id 0');
    // Location 3 still does not exist.
    let refused = r.safe.set_record(OUTLINE, 3 * 256 + 255, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'outline of location 3');
}

// `QUOTAS` is keyed by its location's id (D-145): one record per location, refused while that
// location does not exist; `last_id` stays 0.
#[test]
// gas: raised, BND-01: the quotas written with the zone checks set
#[available_gas(l2_gas: 12801294)] // ceil(1.05 × 12191708 measured)
#[feature("safe_dispatcher")]
fn test_set_record_quotas_keyed_by_location() {
    let r = Fixture::deploy_checked();
    let refused = r.safe.set_record(QUOTAS, 1, quotas_of(1));
    // With the zone checks set (a quota set is refused without them), `ZoneChecks` answers before
    // the parent check: a location that does not exist has no members
    let code = *refused.unwrap_err().at(0);
    assert(code == 'zone: count above members', code);
    r.admin.set_record(LOCATION, 1, floor(4, 4, 6));
    r.admin.set_record(LOCATION, 2, floor(4, 4, 6));
    // Location 2's quotas first: ids are not in order, they are the locations'.
    r.admin.set_record(QUOTAS, 2, quotas_of(7));
    r.admin.set_record(QUOTAS, 1, quotas_of(8));
    assert(r.read.record(QUOTAS, 2) == quotas_of(7), 'quotas of location 2');
    assert(r.read.record(QUOTAS, 1) == quotas_of(8), 'quotas of location 1');
    assert(r.admin.last_id(QUOTAS) == 0, 'composite: last id 0');
    let refused = r.safe.set_record(QUOTAS, 3, quotas_of(1));
    assert(*refused.unwrap_err().at(0) == 'zone: count above members', 'location 3');
}

// An outline's chunk is a chunk of the location (below 225) or 255, its chunk set.
#[test]
// gas: raised, ENG-09: the registry reads its zone checks' class at this kind's write (one slot)
#[available_gas(l2_gas: 5419323)] // ceil(1.05 × 5161260 measured)
#[feature("safe_dispatcher")]
fn test_set_record_outline_chunk_refused() {
    let r = Fixture::deploy();
    r.admin.set_record(LOCATION, 1, Felts::two(0, 0));
    let refused = r.safe.set_record(OUTLINE, 256 + 225, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == OUTLINE_CHUNK, 'chunk 225');
    let refused = r.safe.set_record(OUTLINE, 256 + 254, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == OUTLINE_CHUNK, 'chunk 254');
    r.admin.set_record(OUTLINE, 256 + 224, Felts::one(1));
    r.admin.set_record(OUTLINE, 256 + 255, Felts::one(1));
}

// `TASK` and `QUEST` take the administrator's quiver ids as they are: any non-zero id (D-145; that
// the quiver id exists is the content pipeline's check).
#[test]
// gas: raised, ENG-05: the registry's content checks of the four new kinds (a longer dispatch)
#[available_gas(l2_gas: 3969819)] // ceil(1.05 × 3780780 measured)
fn test_set_record_quiver_ids() {
    let r = Fixture::deploy();
    r.admin.set_record(TASK, 0x12345, Felts::one(1));
    r.admin.set_record(QUEST, 0xFFFFFFFF, Felts::two(1, 2));
    assert(r.read.record(TASK, 0x12345) == Felts::one(1), 'task');
    assert(r.read.record(QUEST, 0xFFFFFFFF) == Felts::two(1, 2), 'quest');
    assert(r.admin.last_id(TASK) == 0 && r.admin.last_id(QUEST) == 0, 'last id 0');
}

// --- set_record: its refusals (AC-1) ------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1710387)] // ceil(1.05 × 1628940 measured)
#[feature("safe_dispatcher")]
fn test_set_record_refused_to_others() {
    let r = Fixture::deploy();
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    let refused = r.safe.set_record(REGION, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    assert(r.admin.last_id(REGION) == 0 && r.version() == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 2833803)] // ceil(1.05 × 2698860 measured)
#[feature("safe_dispatcher")]
fn test_set_record_part_count_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(LOCATION, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'too few');
    let refused = r.safe.set_record(LOCATION, 1, Felts::three(1, 2, 3));
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'too many');
    let refused = r.safe.set_record(REGION, 1, array![].span());
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'empty');
    assert(r.admin.last_id(LOCATION) == 0 && r.version() == 0, 'nothing written');
}

#[test]
// gas: raised, ENG-05: the registry's content checks of the four new kinds (a longer dispatch)
#[available_gas(l2_gas: 1286828)] // ceil(1.05 × 1225550 measured)
#[feature("safe_dispatcher")]
fn test_set_record_unknown_kind_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(0, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 0');
    let refused = r.safe.set_record(LAST_KIND + 1, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 29');
    let refused = r.safe_read.record(LAST_KIND + 1, 1);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'read kind 29');
    let refused = r.safe.last_id(0);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'last id kind 0');
}

#[test]
// gas: raised, ENG-09: the registry reads its zone checks' class at this kind's write (one slot)
#[available_gas(l2_gas: 4242809)] // ceil(1.05 × 4040770 measured)
#[feature("safe_dispatcher")]
fn test_set_record_not_live_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(REGION, 1, array![0].span());
    assert(*refused.unwrap_err().at(0) == NOT_LIVE, 'zero');
    let refused = r.safe.set_record(REGION, 1, array![0x1234].span());
    assert(*refused.unwrap_err().at(0) == NOT_LIVE, 'no LIVE');
    let refused = r.safe.set_record(REGION, 1, array![ABOVE_LIVE + LIVE].span());
    assert(*refused.unwrap_err().at(0) == NOT_LIVE, 'bit 251');
    let refused = r.safe.set_record(REGION, 1, array![-1].span());
    assert(*refused.unwrap_err().at(0) == NOT_LIVE, 'the largest felt');
    // `LIVE` in part 1 does not make part 0 live.
    let refused = r.safe.set_record(LOCATION, 1, array![1, LIVE].span());
    assert(*refused.unwrap_err().at(0) == NOT_LIVE, 'LIVE in part 1');
    assert(r.admin.last_id(REGION) == 0 && r.version() == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 1958177)] // ceil(1.05 × 1864930 measured)
#[feature("safe_dispatcher")]
fn test_set_record_id_zero_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(REGION, 0, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == ZERO_ID, 'sequential');
    let refused = r.safe.set_record(TASK, 0, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == ZERO_ID, 'composite');
}

// Sequential kinds are append-only: a new id is `last_id + 1`, never a gap.
#[test]
// gas: raised, ENG-09: the registry reads its zone checks' class at this kind's write (one slot)
#[available_gas(l2_gas: 4352009)] // ceil(1.05 × 4144770 measured)
#[feature("safe_dispatcher")]
fn test_set_record_not_next_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(REGION, 2, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'first is 1');
    r.admin.set_record(REGION, 1, Felts::one(1));
    let refused = r.safe.set_record(REGION, 3, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'a gap');
    let refused = r.safe.set_record(REGION, 0xFFFFFFFF, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'far');
    assert(r.admin.last_id(REGION) == 1 && r.version() == 1, 'only region 1');
}

// --- the content version (AC-2) -----------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 9593766)] // ceil(1.05 × 9136920 measured)
fn test_version_rises_per_changed_record() {
    let r = Fixture::deploy();
    assert(r.version() == 0, '0 at deployment');
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    assert(r.version() == 1, 'new record: +1');
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    assert(r.version() == 1, 'same values: +0');
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 4));
    assert(r.version() == 2, 'one part: +1');
    r.admin.set_record(BOOK, 1, Felts::three(5, 6, 7));
    assert(r.version() == 3, 'three parts: +1');
    r.admin.set_record(BOOK, 1, Felts::three(5, 6, 7));
    assert(r.version() == 3, 'same again: +0');
    // A part set back to 0 is a change.
    r.admin.set_record(BOOK, 1, Felts::three(5, 0, 7));
    assert(r.version() == 4, 'to zero: +1');
    // Composite kinds likewise.
    r.admin.set_record(LOCATION, 1, Felts::two(0, 0));
    assert(r.version() == 5, 'location: +1');
    r.admin.set_record(OUTLINE, 256 + 255, Felts::one(9));
    assert(r.version() == 6, 'new outline: +1');
    r.admin.set_record(OUTLINE, 256 + 255, Felts::one(9));
    assert(r.version() == 6, 'same outline: +0');
    r.admin.set_record(OUTLINE, 256 + 255, Felts::one(8));
    assert(r.version() == 7, 'changed outline: +1');
}

#[test]
#[available_gas(l2_gas: 7925411)] // ceil(1.05 × 7548010 measured)
fn test_bundle_version_and_order() {
    let r = Fixture::deploy();
    r.admin.set_record(REGION, 1, Felts::one(1));
    r.admin.set_record(LOCATION, 1, Felts::two(2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(4, 5, 6));
    let (v, inputs, records) = r
        .read
        .bundle(array![(BOOK, 1), (REGION, 1), (LOCATION, 2), (LOCATION, 1)].span());
    assert(v == 3 && inputs == 0, 'version');
    // In the order asked; location 2 is missing: two zeros.
    let expected = array![Felts::live(4), 5, 6, Felts::live(1), 0, 0, Felts::live(2), 3];
    assert(records == expected.span(), 'records in order');
    r.admin.set_record(REGION, 1, Felts::one(7));
    let (v, _, records) = r.read.bundle(array![(REGION, 1)].span());
    assert(v == 4 && records == Felts::one(7), 'after a change');
    let (v, _, records) = r.read.bundle(array![].span());
    assert(v == 4 && records.len() == 0, 'no request');
}

// ENG-10b (CM-9; D-223, ruling 5): a dungeon floor holds at most 12 chunks. A `LOCATION` whose
// `N` (bits 72–79 of part 0) is 12 is accepted, 13 refused, the record kept. Its rectangle, 15 ×
// 15 (width at bit 56, height at 64), is larger than `N` (R-28, ENG-R1c-1).
#[test]
#[available_gas(l2_gas: 4419190)] // ceil(1.05 × 4208752 measured)
#[feature("safe_dispatcher")]
fn test_set_record_floor_size() {
    let r = Fixture::deploy();
    let n: felt252 = 0x1000000000000000000;
    let square: felt252 = 15 * 0x100000000000000 + 15 * 0x10000000000000000;
    assert_accepted(try_write(r, LOCATION, Felts::two(square + 12 * n, 0)));
    assert_refused(r.safe.set_record(LOCATION, 1, Felts::two(square + 13 * n, 0)), FLOOR_SIZE);
    assert_refused(try_write(r, LOCATION, Felts::two(square + 255 * n, 0)), FLOOR_SIZE);
    assert(r.read.record(LOCATION, 1) == Felts::two(square + 12 * n, 0), 'location kept');
}

/// A dungeon floor of `N` chunks in a `width × height` rectangle, entered at chunk 0.
fn floor(width: u8, height: u8, target: u8) -> Span<felt252> {
    LocationTrait::new(
        location_kind::DUNGEON,
        1,
        1,
        1,
        3,
        0,
        width,
        height,
        target,
        1,
        0,
        0,
        false,
        0,
        112,
        Lanes16 { lanes: [0; 15] },
    )
        .pack()
}

// R-40 and R-28 (ENG-R1c-1's bounds 5 and 4; review t-0099 note 5, re-audits t-0075 and t-0077,
// minor 3), on the `LOCATION` write alone, with no zone checks: a dungeon floor's `N` at least 6,
// its rectangle's area above `N`. The 4 × 3 sweep (area 12, where t-0077's floor closed at 11 of
// 12): `N` 1 to 5 refused (5, the last below 6), 6 to 11 accepted (11, the last below the area),
// 12 refused, the record kept as it was. `N` 0 is no floor: nothing is checked, even with no
// rectangle.
#[test]
#[available_gas(l2_gas: 25059000)] // ceil(1.05 × 23865714 measured)
#[feature("safe_dispatcher")]
fn test_set_record_floor_bounds() {
    let r = Fixture::deploy();
    assert_accepted(try_write(r, LOCATION, floor(0, 0, 0)));
    for n in 1..13_u8 {
        let result = try_write(r, LOCATION, floor(4, 3, n));
        if n < 6 {
            assert_refused(result, location_errors::FLOOR_FEW);
        } else if n < 12 {
            assert_accepted(result);
        } else {
            assert_refused(result, location_errors::FLOOR_RECTANGLE);
        }
    }
    assert(r.admin.last_id(LOCATION) == 7, 'six floors written');
    // A rewrite that shrinks the rectangle to `N` is refused, the floor kept
    assert_refused(
        r.safe.set_record(LOCATION, 7, floor(4, 3, 12)), location_errors::FLOOR_RECTANGLE,
    );
    assert_refused(
        r.safe.set_record(LOCATION, 7, floor(3, 3, 11)), location_errors::FLOOR_RECTANGLE,
    );
    assert(r.read.record(LOCATION, 7) == floor(4, 3, 11), 'floor kept');
    // Whatever the kind: `N` makes a floor (`SiteTrait::emerging`)
    let rift = LocationTrait::new(
        location_kind::RIFT,
        1,
        1,
        1,
        3,
        0,
        2,
        2,
        6,
        0,
        0,
        0,
        false,
        0,
        0,
        Lanes16 { lanes: [0; 15] },
    );
    assert_refused(try_write(r, LOCATION, rift.pack()), location_errors::FLOOR_RECTANGLE);
}

/// An ingredient worth `value`: an `ITEM` record, not a potion.
fn ingredient_of(value: u32) -> Span<felt252> {
    ItemTrait::new(item_class::INGREDIENT, 1, 0, value, 0, Default::default(), 0, 0).pack()
}

/// A prefix of `value` maximum health: a `MODIFIER` record.
fn prefix_of(value: i16) -> Span<felt252> {
    let (_, record) = source_record(fixed(passive_id::MAX_HEALTH, 0, value), Source::Prefix);
    record
}

// D-169: the inputs version rises only for a changed record of a kind the flattening reads
// (`SKILL`, `ITEM`, `MODIFIER`) that existed before: a rewrite of each moves it by one, an
// identical rewrite and a new id do not; no record of another kind moves it, new or rewritten.
// The content version rises for every changed record, as before.
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 25753140)] // ceil(1.05 × 24526800 measured)
fn test_inputs_version_per_kind() {
    let r = Fixture::deploy();
    let none: [Entry; 3] = [Default::default(); 3];
    // New ids of the input kinds: the content version moves, the inputs version does not.
    r.admin.set_record(SKILL, 1, skill_of(4, none));
    r.admin.set_record(ITEM, 1, ingredient_of(1));
    r.admin.set_record(MODIFIER, 1, prefix_of(10));
    assert(r.version() == 3 && r.inputs() == 0, 'new inputs: +0');
    // Rewrites of each input kind: +1 each; identical rewrites: +0.
    r.admin.set_record(SKILL, 1, skill_of(5, none));
    assert(r.version() == 4 && r.inputs() == 1, 'skill rewritten: +1');
    r.admin.set_record(SKILL, 1, skill_of(5, none));
    assert(r.version() == 4 && r.inputs() == 1, 'same skill: +0');
    r.admin.set_record(ITEM, 1, ingredient_of(2));
    assert(r.version() == 5 && r.inputs() == 2, 'item rewritten: +1');
    r.admin.set_record(ITEM, 1, ingredient_of(2));
    assert(r.version() == 5 && r.inputs() == 2, 'same item: +0');
    r.admin.set_record(MODIFIER, 1, prefix_of(20));
    assert(r.version() == 6 && r.inputs() == 3, 'modifier rewritten: +1');
    r.admin.set_record(MODIFIER, 1, prefix_of(20));
    assert(r.version() == 6 && r.inputs() == 3, 'same modifier: +0');
    // Other kinds, new and rewritten, sequential and composite: the inputs version stays.
    r.admin.set_record(LOCATION, 1, Felts::two(1, 2));
    r.admin.set_record(LOCATION, 1, Felts::two(3, 4));
    r.admin.set_record(REGION, 1, Felts::one(1));
    r.admin.set_record(REGION, 1, Felts::one(2));
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(4, 5, 6));
    r.admin.set_record(QUEST, 9, Felts::two(1, 2));
    r.admin.set_record(QUEST, 9, Felts::two(3, 4));
    r.admin.set_record(SHOP, 16 + 1, Felts::two(1, 2));
    r.admin.set_record(SHOP, 16 + 1, Felts::two(3, 4));
    let (_, set) = source_record(fixed(passive_id::MAX_HEALTH, 0, 10), Source::SetBonus);
    r.admin.set_record(ARMOR_SET, 1, set);
    let (_, set) = source_record(fixed(passive_id::MAX_HEALTH, 0, 20), Source::SetBonus);
    r.admin.set_record(ARMOR_SET, 1, set);
    assert(r.version() == 18 && r.inputs() == 3, 'other kinds: +0');
}

// A record never written reads as `parts(kind)` zeros: part 0 is 0, the record does not exist.
#[test]
#[available_gas(l2_gas: 3216623)] // ceil(1.05 × 3063450 measured)
fn test_missing_record_reads_zeros() {
    let r = Fixture::deploy();
    assert(r.read.record(BOOK, 1) == array![0, 0, 0].span(), 'record');
    assert(r.read.records(REGION, array![1, 2].span()) == array![0, 0].span(), 'records');
    r.admin.set_record(REGION, 1, Felts::one(1));
    assert(
        r.read.records(REGION, array![2, 1].span()) == array![0, Felts::live(1)].span(), 'mixed',
    );
}

#[test]
#[available_gas(l2_gas: 5488109)] // ceil(1.05 × 5226770 measured)
#[feature("safe_dispatcher")]
fn test_reads_bounded() {
    let r = Fixture::deploy();
    let mut ids: Array<u32> = array![];
    let mut requests: Array<(u8, u32)> = array![];
    for i in 1..33_u32 {
        ids.append(i);
        requests.append((REGION, i));
    }
    assert(r.read.records(REGION, ids.span()).len() == 32, '32 records');
    let (_, _, records) = r.read.bundle(requests.span());
    assert(records.len() == 32, '32 requests');
    ids.append(33);
    requests.append((REGION, 33));
    let refused = r.safe_read.records(REGION, ids.span());
    assert(*refused.unwrap_err().at(0) == TOO_MANY, 'records: 33');
    let refused = r.safe_read.bundle(requests.span());
    assert(*refused.unwrap_err().at(0) == TOO_MANY, 'bundle: 33');
}

// --- the administrator --------------------------------------------------------------------------

// The role moves: the new administrator writes, the former one no longer can.
#[test]
#[available_gas(l2_gas: 3662589)] // ceil(1.05 × 3488180 measured)
#[feature("safe_dispatcher")]
fn test_set_admin_hands_over() {
    let r = Fixture::deploy();
    r.admin.set_admin(OTHER.try_into().unwrap());
    let refused = r.safe.set_record(REGION, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'former admin');
    let refused = r.safe.set_admin(ADMIN.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'former admin, set_admin');
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    r.admin.set_record(REGION, 1, Felts::one(1));
    assert(r.admin.last_id(REGION) == 1, 'new admin writes');
}

#[test]
#[available_gas(l2_gas: 2946248)] // ceil(1.05 × 2805950 measured)
#[feature("safe_dispatcher")]
fn test_set_admin_refused() {
    let r = Fixture::deploy();
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    let refused = r.safe.set_admin(OTHER.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    start_cheat_caller_address(r.address, ADMIN.try_into().unwrap());
    let refused = r.safe.set_admin(0.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == ZERO_ADMIN, 'zero');
    r.admin.set_record(REGION, 1, Felts::one(1));
}

#[test]
#[available_gas(l2_gas: 866450)] // ceil(1.05 × 825190 measured)
#[feature("safe_dispatcher")]
fn test_upgrade_stub() {
    let r = Fixture::deploy();
    let refused = r.safe.upgrade(0x1234.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_IMPLEMENTED, 'stub');
}

// --- gas (AC-5): each call alone is in `snforge test --gas-report`; see GAS.md ------------------

// The baseline of the tests below: the deployment alone.
#[test]
#[available_gas(l2_gas: 756557)] // ceil(1.05 × 720530 measured)
fn test_gas_deploy() {
    Fixture::deploy();
}

// `set_record` of a new 3-part record: 3 record slots, `last_id` and the version, all new
// (ENG-01 §10: 5 N / 0 O).
#[test]
#[available_gas(l2_gas: 3473831)] // ceil(1.05 × 3308410 measured)
fn test_gas_set_record_new() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
}

// `set_record` changing a 3-part record: its 3 parts and the version overwritten (ENG-01 §10:
// 0 N / 5 O, which counts `last_id` too; a changed record does not write it).
#[test]
#[available_gas(l2_gas: 4092417)] // ceil(1.05 × 3897540 measured)
fn test_gas_set_record_changed() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(4, 5, 6));
}

// `set_record` of the same values: 3 reads, nothing written, the version kept.
#[test]
#[available_gas(l2_gas: 3804192)] // ceil(1.05 × 3623040 measured)
fn test_gas_set_record_unchanged() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
}

// `records` against `bundle` for the same record: the difference is the version's read.
#[test]
#[available_gas(l2_gas: 2782301)] // ceil(1.05 × 2649810 measured)
fn test_gas_records_1() {
    let r = Fixture::deploy();
    r.books(1);
    assert(r.read.records(BOOK, array![1].span()).len() == 3, '3 felts');
}

#[test]
#[available_gas(l2_gas: 2817738)] // ceil(1.05 × 2683560 measured)
fn test_gas_bundle_1() {
    let r = Fixture::deploy();
    let requests = r.books(1);
    let (v, inputs, records) = r.read.bundle(requests.span());
    assert(v == 5 && inputs == 7 && records.len() == 3, '1 record');
}

#[test]
#[available_gas(l2_gas: 16067016)] // ceil(1.05 × 15301920 measured)
fn test_gas_bundle_10() {
    let r = Fixture::deploy();
    let requests = r.books(10);
    let (v, inputs, records) = r.read.bundle(requests.span());
    assert(v == 5 && inputs == 7 && records.len() == 30, '10 records');
}

// The bound: 32 records of 3 parts, 96 slots and the version (ENG-01 §9.3: at most 97 reads).
#[test]
#[available_gas(l2_gas: 48454140)] // ceil(1.05 × 46146800 measured)
fn test_gas_bundle_32() {
    let r = Fixture::deploy();
    let requests = r.books(32);
    let (v, inputs, records) = r.read.bundle(requests.span());
    assert(v == 5 && inputs == 7 && records.len() == 96, '32 records');
}

/// A record of `kind` without bounds of design/20: `parts(kind)` felts, `value` in each, `LIVE` in
/// part 0. `CASTE` and `ARMOR_SET`, which the registry checks, take a legal record of `value`.
fn plain_of(kind: u8, value: felt252) -> Span<felt252> {
    if kind == CASTE {
        return caste_at_bounds(value.try_into().unwrap());
    }
    if kind == ARMOR_SET {
        let bonus = fixed(passive_id::MAX_HEALTH, 0, value.try_into().unwrap());
        let (_, record) = source_record(bonus, Source::SetBonus);
        return record;
    }
    // The chunk reveal's kinds (ENG-05), which the registry checks too.
    if kind == QUOTAS {
        return quotas_of(value.try_into().unwrap());
    }
    if kind == SET_PIECE {
        return piece_of(value.try_into().unwrap(), 112, 100);
    }
    // A template of at least one goblin at its fewest (R-42, BND-01)
    if kind == PACK {
        return pack_of(
            PackCaste { caste: 1, min: 1, max: value.try_into().unwrap() }, Default::default(),
        );
    }
    let mut out = array![LIVE + value];
    for _ in 1..parts(kind) {
        out.append(value);
    }
    out.span()
}

/// `QUOTAS` of one exit through gate `gate`, once: a legal record (ENG-05).
fn quotas_of(gate: u16) -> Span<felt252> {
    QuotaSet {
        quotas: [
            Quota { kind: quota_kind::EXIT, param: gate, count: 1 }, Default::default(),
            Default::default(), Default::default(), Default::default(), Default::default(),
        ],
    }
        .pack()
}

/// A `SET_PIECE` walled on its ring, open inside, a pack of `template` on `pack` and a collector on
/// `object` (ENG-05).
fn piece_of(template: u16, pack: u8, object: u8) -> Span<felt252> {
    let ring: felt252 = 0x1fffe000c00180030006000c00180030006000c00180030006000ffff;
    SetPieceTrait::new(
        ring,
        [SetPack { tile: pack, template }, Default::default()],
        [
            Object { tile: object, kind: 5, state: 0, param: 1 }, Default::default(),
            Default::default(),
        ],
    )
        .pack()
}

/// The id a new record of `kind` takes: the next one of a sequential kind; for a composite kind,
/// one under location 1 (`QUOTAS` its own id, `OUTLINE` its chunk set, `SHOP` its service 1) or
/// a quiver id (`TASK`, `QUEST`).
fn next_id(r: Registry, kind: u8) -> u32 {
    if is_sequential(kind) {
        r.admin.last_id(kind) + 1
    } else if kind == QUOTAS {
        1
    } else if kind == OUTLINE {
        256 + 255
    } else if kind == SHOP {
        16 + 1
    } else {
        9
    }
}

// D-169 (fix loop 1, quality 2): every one of the 22 kinds that is not an input of the
// flattening, written new and then changed, leaves the inputs version where it was, while the
// content version rises twice for each. Kinds in order, so that `LOCATION` 1 exists before the
// composite kinds that name it.
#[test]
#[available_gas(l2_gas: 56201786)] // ceil(1.05 × 53525510 measured)
fn test_inputs_version_every_other_kind() {
    let r = Fixture::deploy();
    let mut others: u32 = 0;
    for kind in 1..LAST_KIND + 1 {
        // The authored zone's own kinds (ENG-09) need an authored zone and its checks, and a gate
        // and a quota set the checks' class (BND-01): their writes are `test_zone`'s
        if kind == SKILL
            || kind == ITEM
            || kind == MODIFIER
            || kind == ZONE_CHUNK
            || kind == BRIDGE
            || kind == CANDIDATES
            || kind == GATE
            || kind == QUOTAS {
            continue;
        }
        let id = next_id(r, kind);
        let before = r.version();
        r.admin.set_record(kind, id, plain_of(kind, 1));
        r.admin.set_record(kind, id, plain_of(kind, 2));
        assert(r.version() == before + 2, 'new and changed: +2');
        assert(r.inputs() == 0, 'inputs version unchanged');
        others += 1;
    }
    assert(others == 20, 'the 20 other kinds');
}

// --- set_record: the content's checks (D-166; design/20 §1.3–§1.5, §6 test 1)
// -------------------
//
// Every per-source bound of design/20 that belongs to one record is checked once, when the
// administrator writes it: at its bound a record is accepted, one unit beyond it is refused.

/// A passive of fixed value `value` (a cost's shape; a benefit at one value).
fn fixed(id: u8, param: u8, value: i16) -> Passive {
    PassiveTrait::new(id, param, 0, 0, value, value)
}

/// The record that makes `passive` one source of `source`: a modifier of that slot type (an
/// insignia made for the chest), or a set's first bonus.
fn source_record(passive: Passive, source: Source) -> (u8, Span<felt252>) {
    let none: Passive = Default::default();
    match source {
        Source::Prefix => (
            MODIFIER, ModifierTrait::new(modifier_slot::PREFIX, passive, none).pack(),
        ),
        Source::Suffix => (
            MODIFIER, ModifierTrait::new(modifier_slot::SUFFIX, passive, none).pack(),
        ),
        Source::Inscription => (
            MODIFIER, ModifierTrait::new(modifier_slot::INSCRIPTION, passive, none).pack(),
        ),
        Source::Insignia => (
            MODIFIER, ModifierTrait::insignia(base_slot::CHEST, passive, none).pack(),
        ),
        Source::Rune => (MODIFIER, ModifierTrait::new(modifier_slot::RUNE, passive, none).pack()),
        Source::SetBonus => (
            ARMOR_SET, ArmorSetTrait::new([1, 2, 3, 4, 5], [passive, none]).pack(),
        ),
    }
}

/// Writes the record at the next id of its kind; `Ok` when accepted (the id is then taken).
#[feature("safe_dispatcher")]
fn try_write(r: Registry, kind: u8, record: Span<felt252>) -> Result<(), Array<felt252>> {
    let id = r.admin.last_id(kind) + 1;
    r.safe.set_record(kind, id, record)
}

fn assert_accepted(result: Result<(), Array<felt252>>) {
    match result {
        Result::Ok(()) => {},
        Result::Err(data) => core::panic_with_felt252(*data.at(0)),
    }
}

fn assert_refused(result: Result<(), Array<felt252>>, message: felt252) {
    match result {
        Result::Ok(()) => core::panic_with_felt252('should be refused'),
        Result::Err(data) => assert(*data.at(0) == message, *data.at(0)),
    }
}

// design/20 §1.3's rows under envelope B (DS-1, DS-5, DS-7): for each, a record at `lo` and at
// `hi` is accepted, one at `hi + 1` is refused with the per-source bound, and one at `lo − 1` is
// refused (by the bound, or by the passive's own range where that is non-negative).
#[test]
#[available_gas(l2_gas: 78449039)] // ceil(1.05 × 74713370 measured)
#[feature("safe_dispatcher")]
fn test_set_record_per_source_bounds() {
    let r = Fixture::deploy();
    // (id, param, source, lo, hi)
    let rows = array![
        (passive_id::MAX_HEALTH, 0, Source::Prefix, 0_i16, 30_i16),
        (passive_id::MAX_HEALTH, 0, Source::Insignia, 0, 15),
        (passive_id::MAX_HEALTH, 0, Source::Rune, -75, 50),
        (passive_id::MAX_HEALTH, 0, Source::SetBonus, -75, 50),
        (passive_id::MAX_ENERGY, 0, Source::Suffix, -5, 5),
        (passive_id::MAX_ENERGY, 0, Source::SetBonus, -5, 5),
        (passive_id::ENERGY_REGEN, 0, Source::Inscription, -1, 0),
        (passive_id::ENERGY_REGEN, 0, Source::SetBonus, -1, 1),
        (passive_id::HEALTH_REGEN, 0, Source::Prefix, -1, 0),
        (passive_id::HEALTH_REGEN, 0, Source::SetBonus, -1, 1),
        (passive_id::ARMOR_VS, damage::FIRE, Source::Rune, 0, 7),
        (passive_id::ATTRIBUTE, 13, Source::Rune, 1, 3),
        (passive_id::LIFE_STEAL_ON_HIT, 0, Source::Suffix, 0, 5),
        (passive_id::ENERGY_ON_HIT, 0, Source::Prefix, 0, 1),
        (passive_id::CONDITION_DURATION, condition::POISON, Source::Prefix, 0, 33),
        (passive_id::ENCHANT_DURATION, 0, Source::Insignia, 0, 20),
        (passive_id::KNOCKDOWN_FLAT, 0, Source::SetBonus, 0, 1),
    ];
    for (id, param, source, lo, hi) in rows {
        let (kind, record) = source_record(fixed(id, param, lo), source);
        assert_accepted(try_write(r, kind, record));
        let (kind, record) = source_record(fixed(id, param, hi), source);
        assert_accepted(try_write(r, kind, record));
        let (kind, record) = source_record(fixed(id, param, hi + 1), source);
        assert_refused(try_write(r, kind, record), passive_errors::SOURCE_BOUND);
        let (kind, record) = source_record(fixed(id, param, lo - 1), source);
        let refused = try_write(r, kind, record);
        assert(refused.is_err(), 'below lo accepted');
        let message = *refused.unwrap_err().at(0);
        assert(
            message == passive_errors::SOURCE_BOUND || message == passive_errors::VALUE, message,
        );
    }
    // A modifier's benefit and cost on one statistic are summed: +50 and −75 on a rune pass, +30
    // and +30 on a prefix are refused.
    let rune = ModifierTrait::new(
        modifier_slot::RUNE,
        fixed(passive_id::MAX_HEALTH, 0, 50),
        fixed(passive_id::MAX_HEALTH, 0, -75),
    );
    assert_accepted(try_write(r, MODIFIER, rune.pack()));
    let prefix = ModifierTrait::new(
        modifier_slot::PREFIX,
        fixed(passive_id::MAX_HEALTH, 0, 30),
        fixed(passive_id::MAX_HEALTH, 0, 30),
    );
    assert_refused(try_write(r, MODIFIER, prefix.pack()), passive_errors::SOURCE_BOUND);
    // A benefit's range, not only its top: 10…31 on a prefix is refused.
    let wide = PassiveTrait::new(passive_id::MAX_HEALTH, 0, 0, 0, 10, 31);
    let (kind, record) = source_record(wide, Source::Prefix);
    assert_refused(try_write(r, kind, record), passive_errors::SOURCE_BOUND);
    // An existing record rewritten past its bound is refused as a new one is.
    let (_, record) = source_record(fixed(passive_id::MAX_HEALTH, 0, 31), Source::Prefix);
    assert_refused(r.safe.set_record(MODIFIER, 1, record), passive_errors::SOURCE_BOUND);
}

// DS-4 and design/19 §7.2: the passives a source may not hold are refused on it.
#[test]
#[available_gas(l2_gas: 10460016)] // ceil(1.05 × 9961920 measured)
fn test_set_record_sources_refused() {
    let r = Fixture::deploy();
    let refused = array![
        (passive_id::ENERGY_COST, 1, Source::Prefix),
        (passive_id::ENERGY_COST, 1, Source::SetBonus),
        (passive_id::BASE_DAMAGE_PERCENT, 0, Source::Rune),
        (passive_id::RATING_PERCENT, 0, Source::Insignia),
        (passive_id::ATTRIBUTE, 13, Source::Prefix),
        (passive_id::LIFE_STEAL_ON_HIT, 0, Source::SetBonus),
        (passive_id::ENERGY_ON_HIT, 0, Source::Rune), (passive_id::MAX_ENERGY, 0, Source::Insignia),
        (passive_id::QUICK_CAST_EVERY_N, 13, Source::Suffix),
        (passive_id::DAMAGE_TYPE, damage::FIRE, Source::Suffix),
        (passive_id::CONDITION_DURATION, condition::POISON, Source::Inscription),
    ];
    for (id, param, source) in refused {
        let value = if id == passive_id::ENERGY_COST || id == passive_id::DAMAGE_TYPE {
            0
        } else {
            1
        };
        let (kind, record) = source_record(fixed(id, param, value), source);
        assert_refused(try_write(r, kind, record), passive_errors::SOURCE);
    }
    // One source adds to a hit's sum no more than one passive may (§7.2): +18 and +1 on weapon
    // hits.
    let damage = ModifierTrait::new(
        modifier_slot::PREFIX,
        PassiveTrait::new(passive_id::DAMAGE_PERCENT, 0, 0, 0, 18, 18),
        PassiveTrait::new(passive_id::DAMAGE_PERCENT, 0, 0, 0, 1, 1),
    );
    assert_refused(try_write(r, MODIFIER, damage.pack()), passive_errors::CONTRIBUTION);
    assert(r.admin.last_id(MODIFIER) == 0 && r.admin.last_id(ARMOR_SET) == 0, 'none written');
}

// DS-23: an insignia names its piece, and its health is within the piece's 15 / 10 / 5.
#[test]
#[available_gas(l2_gas: 7798581)] // ceil(1.05 × 7427220 measured)
fn test_set_record_insignia_pieces() {
    let r = Fixture::deploy();
    let none: Passive = Default::default();
    let health = |value: i16| fixed(passive_id::MAX_HEALTH, 0, value);
    let legs = ModifierTrait::insignia(base_slot::LEGS, health(10), none);
    assert_accepted(try_write(r, MODIFIER, legs.pack()));
    let legs = ModifierTrait::insignia(base_slot::LEGS, health(11), none);
    assert_refused(try_write(r, MODIFIER, legs.pack()), modifier_errors::PIECE_HEALTH);
    let head = ModifierTrait::insignia(base_slot::HEAD, health(5), none);
    assert_accepted(try_write(r, MODIFIER, head.pack()));
    let feet = ModifierTrait::insignia(base_slot::FEET, health(3), health(3));
    assert_refused(try_write(r, MODIFIER, feet.pack()), modifier_errors::PIECE_HEALTH);
    let nowhere = ModifierTrait::new(modifier_slot::INSIGNIA, health(5), none);
    assert_refused(try_write(r, MODIFIER, nowhere.pack()), modifier_errors::PIECE);
    let weapon = ModifierTrait::insignia(base_slot::WEAPON, health(5), none);
    assert_refused(try_write(r, MODIFIER, weapon.pack()), modifier_errors::PIECE);
}

/// A caste at design/20's bounds (DS-18, DS-29): multiplier 1,000 %, energy 85, regeneration 10
/// pips, weapon damage 255, flee 100, health regeneration 20, tier 6, rank 15, armor 63 against
/// every type; its first skill `skill`.
fn caste_at_bounds(skill: u16) -> Span<felt252> {
    caste_naming([skill, 0, 0, 0])
}

/// The caste at bounds, naming `skills`.
fn caste_naming(skills: [u16; 4]) -> Span<felt252> {
    CasteTrait::new(
        6,
        1,
        1000,
        20,
        40,
        [63; 9],
        WeaponTrait::new(weapon::MAUL, 255, damage::BLUNT, 2, 1),
        85,
        10,
        skills,
        15,
        100,
        0,
        false,
    )
        .pack()
}

/// `record` with `delta` added to part 0: a field raised past what `pack` accepts, as a
/// hand-made record would carry it.
fn raised(record: Span<felt252>, delta: felt252) -> Span<felt252> {
    array![*record[0] + delta, *record[1]].span()
}

fn skill_of(adrenaline: u8, entries: [Entry; 3]) -> Span<felt252> {
    SkillTrait::new(1, 1, skill_kind::ATTACK, 0, adrenaline, 1, 5, 1, target::FOE, false, entries)
        .pack()
}

// DS-18, DS-29: a caste record at its bounds is accepted; one unit beyond any is refused; the
// skills it names are at most 63 strikes (across records).
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 16525352)] // ceil(1.05 × 15738430 measured)
fn test_set_record_caste_bounds() {
    let r = Fixture::deploy();
    assert_accepted(try_write(r, SKILL, skill_of(63, [Default::default(); 3])));
    assert_accepted(try_write(r, SKILL, skill_of(64, [Default::default(); 3])));
    assert_accepted(try_write(r, CASTE, caste_at_bounds(1)));
    assert_refused(try_write(r, CASTE, caste_at_bounds(2)), caste_errors::SKILL_ADRENALINE);
    let at_bounds = caste_at_bounds(1);
    // Health 1,001 % (bit 16), health regeneration 21 (bit 32), weapon damage 256 (bit 52),
    // energy 86 (bit 80), energy regeneration 11 (bit 88), flee 101 (bit 96); tier 7 and tier 0.
    // The rank (15) and the armor per type (63) are at their fields' widest: a unit more is not a
    // record's value but the next field's bit.
    let beyond = array![
        (0x10000, caste_errors::HEALTH), (0x100000000, caste_errors::HEALTH_REGEN),
        (0x10000000000000, caste_errors::WEAPON_DAMAGE),
        (0x100000000000000000000, caste_errors::ENERGY),
        (0x10000000000000000000000, caste_errors::ENERGY_REGEN),
        (0x1000000000000000000000000, caste_errors::FLEE), (1, caste_errors::TIER),
        (-6, caste_errors::TIER),
    ];
    for (delta, message) in beyond {
        assert_refused(try_write(r, CASTE, raised(at_bounds, delta)), message);
    }
    assert(r.admin.last_id(CASTE) == 1, 'one caste written');
}

// DS-20 (§6 test 7): a second `ATTACK_BONUS` on one carrier is refused; a potion's entry is a
// legal, unscaled carrier (design/19 §5.14).
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 8801783)] // ceil(1.05 × 8382650 measured)
fn test_set_record_carriers() {
    let r = Fixture::deploy();
    let bonus = EntryTrait::new(
        kind::ATTACK_BONUS, 0, 5, 5, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    assert_accepted(
        try_write(r, SKILL, skill_of(4, [bonus, Default::default(), Default::default()])),
    );
    assert_refused(
        try_write(r, SKILL, skill_of(4, [bonus, bonus, Default::default()])),
        entry_errors::TWO_ATTACK_BONUSES,
    );
    let heal = EntryTrait::new(
        kind::HEAL, 0, 20, 20, 0, 0, 0, target::SELF, shape::SINGLE, 0, 0, 0,
    );
    let potion = |entry: Entry| ItemTrait::new(item_class::POTION, 1, 1, 10, 0, entry, 0, 0).pack();
    assert_accepted(try_write(r, ITEM, potion(heal)));
    assert_refused(try_write(r, ITEM, potion(Default::default())), item_errors::NO_ENTRY);
    assert_refused(try_write(r, ITEM, potion(Entry { v12: 40, ..heal })), entry_errors::NOT_SCALED);
    let ingredient = ItemTrait::new(item_class::INGREDIENT, 1, 1, 1, 0, heal, 0, 0).pack();
    assert_refused(try_write(r, ITEM, ingredient), item_errors::NOT_POTION);
}

// CBT-05a (CBT-04's carried item): a `CONDITION`, `CURE` or `ON_ATTACK_CONDITION` naming one of
// the conditions after the MVP (6–9, FX-22) is refused by `set_record`, a skill's entry or a
// potion's; the MVP's five are accepted (the skill is `skill_of`'s attack: every entry `FOE`,
// `SINGLE`).
#[test]
#[available_gas(l2_gas: 19030631)] // ceil(1.05 × 18124410 measured)
fn test_set_record_conditions_after_the_mvp() {
    let r = Fixture::deploy();
    let none: Entry = Default::default();
    let inflict = |
        c: u8,
    | EntryTrait::new(
        kind::CONDITION, c, 3, 3, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    let cure = |
        c: u8,
    | EntryTrait::new(kind::CURE, c, 0, 0, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0);
    let coat = |
        c: u8,
    | EntryTrait::new(
        kind::ON_ATTACK_CONDITION, c, 24, 24, 10, 10, 0, target::FOE, shape::SINGLE, 0, 0, 0,
    );
    assert_accepted(
        try_write(r, SKILL, skill_of(4, [inflict(condition::KNOCKED_DOWN), none, none])),
    );
    assert_accepted(try_write(r, SKILL, skill_of(4, [cure(condition::CRIPPLED), none, none])));
    for c in condition::DAZED..condition::LAST + 1 {
        for entry in array![inflict(c), cure(c), coat(c)] {
            assert_refused(
                try_write(r, SKILL, skill_of(4, [entry, none, none])),
                entry_errors::CONDITION_NOT_MVP,
            );
        }
    }
    let potion = |entry: Entry| ItemTrait::new(item_class::POTION, 1, 1, 10, 0, entry, 0, 0).pack();
    assert_refused(
        try_write(r, ITEM, potion(cure(condition::BLIND))), entry_errors::CONDITION_NOT_MVP,
    );
}

// CBT-05a, option (ii): `set_record` refuses the kinds and entry guards the MVP's content does
// not use (`LIFE_STEAL`, `INTERRUPT`; guards `ABOVE_HALF`, `IN_STANCE`, `ENCHANTED`), in a skill
// and in a potion; `BELOW_HALF` (Second Wind) is accepted.
#[test]
#[available_gas(l2_gas: 9672569)] // ceil(1.05 × 9211970 measured)
fn test_set_record_deferred_kinds_and_guards() {
    let r = Fixture::deploy();
    let none: Entry = Default::default();
    let on_foe = |
        k: u8, v: i16, g: u8,
    | EntryTrait::new(k, 0, v, v, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, g, 0);
    assert_accepted(
        try_write(r, SKILL, skill_of(4, [on_foe(kind::HEAL, 20, guard::BELOW_HALF), none, none])),
    );
    assert_refused(
        try_write(r, SKILL, skill_of(4, [on_foe(kind::LIFE_STEAL, 20, 0), none, none])),
        entry_errors::KIND_DEFERRED,
    );
    assert_refused(
        try_write(r, SKILL, skill_of(4, [on_foe(kind::INTERRUPT, 0, 0), none, none])),
        entry_errors::KIND_DEFERRED,
    );
    for g in array![guard::ABOVE_HALF, guard::IN_STANCE, guard::ENCHANTED] {
        assert_refused(
            try_write(r, SKILL, skill_of(4, [on_foe(kind::HEAL, 20, g), none, none])),
            entry_errors::GUARD_DEFERRED,
        );
    }
    let potion = |entry: Entry| ItemTrait::new(item_class::POTION, 1, 1, 10, 0, entry, 0, 0).pack();
    assert_refused(
        try_write(r, ITEM, potion(on_foe(kind::LIFE_STEAL, 20, 0))), entry_errors::KIND_DEFERRED,
    );
}

// DS-18 whatever the order of writes (CBT-02c fix loop 2, the review's major): the registry counts
// the castes that name each skill (`caste_skills`) and refuses a skill above 63 strikes while one
// does. The caste first, naming skill 1 before it exists: skill 1 at 64 is refused, at 63
// accepted; then rewritten from 63 to 64, refused. The skill first at 64: the caste naming it is
// refused (`test_set_record_caste_bounds`). A skill no caste names takes 64.
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 12135942)] // ceil(1.05 × 11558040 measured)
#[feature("safe_dispatcher")]
fn test_set_record_caste_skills_either_order() {
    let r = Fixture::deploy();
    let none = [Default::default(); 3];
    assert_accepted(try_write(r, CASTE, caste_at_bounds(1)));
    assert_refused(try_write(r, SKILL, skill_of(64, none)), caste_errors::SKILL_ADRENALINE);
    assert(r.admin.last_id(SKILL) == 0, 'skill 1 not written');
    assert_accepted(try_write(r, SKILL, skill_of(63, none)));
    assert_refused(r.safe.set_record(SKILL, 1, skill_of(64, none)), caste_errors::SKILL_ADRENALINE);
    assert_accepted(r.safe.set_record(SKILL, 1, skill_of(62, none)));
    assert_accepted(try_write(r, SKILL, skill_of(64, none)));
    assert(r.admin.last_id(SKILL) == 2, 'skill 2, named by none, at 64');
}

// A caste rewritten moves the counts: naming skill 1 twice, then once, skill 1 stays bound;
// naming skill 2 instead, skill 1 is released (64 accepted) and skill 2 bound. Two castes naming
// one skill: it stays bound until neither does.
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 21413847)] // ceil(1.05 × 20394140 measured)
#[feature("safe_dispatcher")]
fn test_set_record_caste_rewrite_moves_the_bound() {
    let r = Fixture::deploy();
    let none = [Default::default(); 3];
    assert_accepted(try_write(r, SKILL, skill_of(10, none)));
    assert_accepted(try_write(r, SKILL, skill_of(10, none)));
    assert_accepted(try_write(r, CASTE, caste_naming([1, 1, 0, 0])));
    assert_accepted(r.safe.set_record(CASTE, 1, caste_naming([1, 0, 0, 0])));
    assert_refused(r.safe.set_record(SKILL, 1, skill_of(64, none)), caste_errors::SKILL_ADRENALINE);
    assert_accepted(r.safe.set_record(CASTE, 1, caste_naming([2, 0, 0, 0])));
    assert_accepted(r.safe.set_record(SKILL, 1, skill_of(64, none)));
    assert_refused(r.safe.set_record(SKILL, 2, skill_of(64, none)), caste_errors::SKILL_ADRENALINE);
    assert_accepted(try_write(r, CASTE, caste_naming([0, 0, 0, 2])));
    assert_accepted(r.safe.set_record(CASTE, 1, caste_naming([0, 0, 0, 0])));
    assert_refused(r.safe.set_record(SKILL, 2, skill_of(64, none)), caste_errors::SKILL_ADRENALINE);
    assert_accepted(r.safe.set_record(CASTE, 2, caste_naming([0, 0, 0, 0])));
    assert_accepted(r.safe.set_record(SKILL, 2, skill_of(64, none)));
}

// --- set_record: the chunk reveal's records (ENG-05, after CBT-05a)
// -------------------------------------------------------------------
//
// `QUOTAS`, `SPAWN_TABLE`, `PACK` and `SET_PIECE` are their models' `assert_legal` when written:
// a legal record is accepted, each illegal shape refused with its error, nothing written.

fn quota_set(first: Quota) -> Span<felt252> {
    QuotaSetRecord::pack(
        @QuotaSet {
            quotas: [
                first, Default::default(), Default::default(), Default::default(),
                Default::default(), Default::default(),
            ],
        },
    )
}

fn spawn_table(first: Spawn, density: u8) -> Span<felt252> {
    SpawnTableRecord::pack(
        @SpawnTableTrait::new(
            [
                first, Default::default(), Default::default(), Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
            density,
        ),
    )
}

fn pack_of(a: PackCaste, b: PackCaste) -> Span<felt252> {
    PackRecord::pack(
        @PackTrait::new([a, b, Default::default(), Default::default(), Default::default()], 0),
    )
}

#[test]
// gas: raised, BND-01: the quotas written with the zone checks set
#[available_gas(l2_gas: 23081853)] // ceil(1.05 × 21982717 measured)
#[feature("safe_dispatcher")]
fn test_set_record_reveal_records() {
    let r = Fixture::deploy_checked();
    r.admin.set_record(LOCATION, 1, floor(4, 4, 6));
    // QUOTAS
    r.admin.set_record(QUOTAS, 1, quotas_of(5));
    assert_refused(
        r.safe.set_record(QUOTAS, 1, quota_set(Quota { kind: 0, param: 3, count: 0 })),
        quotas_errors::EMPTY,
    );
    assert_refused(
        r
            .safe
            .set_record(QUOTAS, 1, quota_set(Quota { kind: quota_kind::VEIN, param: 0, count: 0 })),
        quotas_errors::COUNT,
    );
    // A kind past the last: the packer refuses it, so it is written as its felt (kind 7, count 1).
    assert_refused(
        r.safe.set_record(QUOTAS, 1, array![LIVE + 7 + 0x1000000].span()), quotas_errors::KIND,
    );
    assert(r.read.record(QUOTAS, 1) == quotas_of(5), 'quotas kept');
    // SPAWN_TABLE
    assert_accepted(try_write(r, SPAWN_TABLE, spawn_table(Spawn { template: 1, weight: 3 }, 128)));
    assert_refused(
        try_write(r, SPAWN_TABLE, spawn_table(Spawn { template: 0, weight: 3 }, 0)),
        spawn_errors::EMPTY,
    );
    assert_refused(
        try_write(r, SPAWN_TABLE, spawn_table(Spawn { template: 1, weight: 0 }, 64)),
        spawn_errors::WEIGHT,
    );
    assert(r.admin.last_id(SPAWN_TABLE) == 1, 'one table');
    // PACK
    let none: PackCaste = Default::default();
    assert_accepted(
        try_write(
            r,
            PACK,
            pack_of(PackCaste { caste: 1, min: 2, max: 3 }, PackCaste { caste: 2, min: 3, max: 9 }),
        ),
    );
    assert_refused(
        try_write(
            r,
            PACK,
            pack_of(PackCaste { caste: 1, min: 1, max: 1 }, PackCaste { caste: 0, min: 0, max: 2 }),
        ),
        pack_errors::EMPTY,
    );
    assert_refused(try_write(r, PACK, pack_of(none, none)), pack_errors::NO_CASTE);
    // R-42: a fewest of 0 (BND-01); one caste at 0 is legal while another holds a minimum
    assert_refused(
        try_write(
            r,
            PACK,
            pack_of(PackCaste { caste: 1, min: 0, max: 3 }, PackCaste { caste: 2, min: 0, max: 2 }),
        ),
        pack_errors::NO_FEWEST,
    );
    assert_accepted(
        try_write(
            r,
            PACK,
            pack_of(PackCaste { caste: 1, min: 0, max: 3 }, PackCaste { caste: 2, min: 1, max: 2 }),
        ),
    );
    assert_refused(
        try_write(
            r,
            PACK,
            pack_of(PackCaste { caste: 1, min: 3, max: 3 }, PackCaste { caste: 2, min: 3, max: 4 }),
        ),
        pack_errors::SIZE,
    );
    assert(r.admin.last_id(PACK) == 2, 'two templates');
    // SET_PIECE: legal; a pack on the ring; an object on the ring; a corner open
    assert_accepted(try_write(r, SET_PIECE, piece_of(1, 112, 100)));
    assert_refused(try_write(r, SET_PIECE, piece_of(1, 105, 100)), set_piece_errors::TILE);
    assert_refused(try_write(r, SET_PIECE, piece_of(1, 112, 7)), set_piece_errors::TILE);
    let open = SetPieceTrait::new(
        0x1fffe000c00180030006000c00180030006000c00180030006000fffe,
        [Default::default(), Default::default()],
        [Default::default(), Default::default(), Default::default()],
    );
    assert_refused(try_write(r, SET_PIECE, SetPieceRecord::pack(@open)), set_piece_errors::CORNER);
    assert(r.admin.last_id(SET_PIECE) == 1, 'one set piece');
}
