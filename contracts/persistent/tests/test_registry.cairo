// ENG-03: `Registry` stores content as data (ENG-01 §3.5). The administrator writes records with
// `set_record`, which enforces the part count, `LIVE` in part 0, and the allocation of ids
// (sequential: `last_id + 1`; composite: the parent exists); every changed record raises the
// content version by one, an unchanged rewrite does not (D-141). Everyone reads with `record`,
// `records` and `bundle`, which returns the version first. A record never written reads as zeros.
use grimworld_logic::content::{BOOK, GATE, LOCATION, OUTLINE, QUEST, REGION, SHOP, TASK};
use grimworld_logic::interface::{
    IRegistryReadDispatcher, IRegistryReadDispatcherTrait, IRegistryReadSafeDispatcher,
    IRegistryReadSafeDispatcherTrait,
};
use grimworld_logic::packing::LIVE;
use grimworld_persistent::systems::registry::errors::{
    NOT_ADMIN, NOT_LIVE, NOT_NEXT, NO_PARENT, OUTLINE_CHUNK, PART_COUNT, TOO_MANY, ZERO_ADMIN,
    ZERO_ID,
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

    fn version(self: Registry) -> u32 {
        self.read.content_version()
    }

    /// `count` 3-part records (`BOOK`, the widest kind) written straight into storage, and the
    /// version 5.
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
        store(self.address, selector!("content_version"), array![5].span());
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
#[available_gas(l2_gas: 4625471)] // ceil(1.05 × 4405210 measured)
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
#[available_gas(l2_gas: 4697154)] // ceil(1.05 × 4473480 measured)
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
#[available_gas(l2_gas: 7418177)] // ceil(1.05 × 7064930 measured)
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

// An outline's chunk is a chunk of the location (below 225) or 255, its chunk set.
#[test]
#[available_gas(l2_gas: 4398303)] // ceil(1.05 × 4188860 measured)
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

// `TASK` and `QUEST` take quiver's ids: any non-zero id.
#[test]
#[available_gas(l2_gas: 3783791)] // ceil(1.05 × 3603610 measured)
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
#[available_gas(l2_gas: 1325657)] // ceil(1.05 × 1262530 measured)
#[feature("safe_dispatcher")]
fn test_set_record_refused_to_others() {
    let r = Fixture::deploy();
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    let refused = r.safe.set_record(REGION, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    assert(r.admin.last_id(REGION) == 0 && r.version() == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 1728353)] // ceil(1.05 × 1646050 measured)
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
#[available_gas(l2_gas: 1270458)] // ceil(1.05 × 1209960 measured)
#[feature("safe_dispatcher")]
fn test_set_record_unknown_kind_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(0, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 0');
    let refused = r.safe.set_record(26, 1, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 26');
    let refused = r.safe_read.record(26, 1);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'read kind 26');
    let refused = r.safe.last_id(0);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'last id kind 0');
}

#[test]
#[available_gas(l2_gas: 2205084)] // ceil(1.05 × 2100080 measured)
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
#[available_gas(l2_gas: 1229928)] // ceil(1.05 × 1171360 measured)
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
#[available_gas(l2_gas: 3396173)] // ceil(1.05 × 3234450 measured)
#[feature("safe_dispatcher")]
fn test_set_record_not_next_refused() {
    let r = Fixture::deploy();
    let refused = r.safe.set_record(GATE, 2, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'first is 1');
    r.admin.set_record(GATE, 1, Felts::one(1));
    let refused = r.safe.set_record(GATE, 3, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'a gap');
    let refused = r.safe.set_record(GATE, 0xFFFFFFFF, Felts::one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'far');
    assert(r.admin.last_id(GATE) == 1 && r.version() == 1, 'only gate 1');
}

// --- the content version (AC-2) -----------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 8777822)] // ceil(1.05 × 8359830 measured)
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
#[available_gas(l2_gas: 7482573)] // ceil(1.05 × 7126260 measured)
fn test_bundle_version_and_order() {
    let r = Fixture::deploy();
    r.admin.set_record(REGION, 1, Felts::one(1));
    r.admin.set_record(LOCATION, 1, Felts::two(2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(4, 5, 6));
    let (v, records) = r
        .read
        .bundle(array![(BOOK, 1), (REGION, 1), (LOCATION, 2), (LOCATION, 1)].span());
    assert(v == 3, 'version');
    // In the order asked; location 2 is missing: two zeros.
    let expected = array![Felts::live(4), 5, 6, Felts::live(1), 0, 0, Felts::live(2), 3];
    assert(records == expected.span(), 'records in order');
    r.admin.set_record(REGION, 1, Felts::one(7));
    let (v, records) = r.read.bundle(array![(REGION, 1)].span());
    assert(v == 4 && records == Felts::one(7), 'after a change');
    let (v, records) = r.read.bundle(array![].span());
    assert(v == 4 && records.len() == 0, 'no request');
}

// A record never written reads as `parts(kind)` zeros: part 0 is 0, the record does not exist.
#[test]
#[available_gas(l2_gas: 3090318)] // ceil(1.05 × 2943160 measured)
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
#[available_gas(l2_gas: 5061326)] // ceil(1.05 × 4820310 measured)
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
    let (_, records) = r.read.bundle(requests.span());
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
#[available_gas(l2_gas: 3188483)] // ceil(1.05 × 3036650 measured)
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
#[available_gas(l2_gas: 2854173)] // ceil(1.05 × 2718260 measured)
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
#[available_gas(l2_gas: 859131)] // ceil(1.05 × 818220 measured)
#[feature("safe_dispatcher")]
fn test_upgrade_stub() {
    let r = Fixture::deploy();
    let refused = r.safe.upgrade(0x1234.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_IMPLEMENTED, 'stub');
}

// --- gas (AC-5): each call alone is in `snforge test --gas-report`; see GAS.md ------------------

// The baseline of the tests below: the deployment alone.
#[test]
#[available_gas(l2_gas: 748902)] // ceil(1.05 × 713240 measured)
fn test_gas_deploy() {
    Fixture::deploy();
}

// `set_record` of a new 3-part record: 3 record slots, `last_id` and the version, all new
// (ENG-01 §10: 5 N / 0 O).
#[test]
#[available_gas(l2_gas: 3359496)] // ceil(1.05 × 3199520 measured)
fn test_gas_set_record_new() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
}

// `set_record` changing a 3-part record: its 3 parts and the version overwritten (ENG-01 §10:
// 0 N / 5 O, which counts `last_id` too; a changed record does not write it).
#[test]
#[available_gas(l2_gas: 3866489)] // ceil(1.05 × 3682370 measured)
fn test_gas_set_record_changed() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(4, 5, 6));
}

// `set_record` of the same values: 3 reads, nothing written, the version kept.
#[test]
#[available_gas(l2_gas: 3653423)] // ceil(1.05 × 3479450 measured)
fn test_gas_set_record_unchanged() {
    let r = Fixture::deploy();
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
    r.admin.set_record(BOOK, 1, Felts::three(1, 2, 3));
}

// `records` against `bundle` for the same record: the difference is the version's read.
#[test]
#[available_gas(l2_gas: 2756082)] // ceil(1.05 × 2624840 measured)
fn test_gas_records_1() {
    let r = Fixture::deploy();
    r.books(1);
    assert(r.read.records(BOOK, array![1].span()).len() == 3, '3 felts');
}

#[test]
#[available_gas(l2_gas: 2778710)] // ceil(1.05 × 2646390 measured)
fn test_gas_bundle_1() {
    let r = Fixture::deploy();
    let requests = r.books(1);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 3, '1 record');
}

#[test]
#[available_gas(l2_gas: 15857888)] // ceil(1.05 × 15102750 measured)
fn test_gas_bundle_10() {
    let r = Fixture::deploy();
    let requests = r.books(10);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 30, '10 records');
}

// The bound: 32 records of 3 parts, 96 slots and the version (ENG-01 §9.3: at most 97 reads).
#[test]
#[available_gas(l2_gas: 47829212)] // ceil(1.05 × 45551630 measured)
fn test_gas_bundle_32() {
    let r = Fixture::deploy();
    let requests = r.books(32);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 96, '32 records');
}
