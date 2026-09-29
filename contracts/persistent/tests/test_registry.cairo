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
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait, IRegistryAdminSafeDispatcher,
    IRegistryAdminSafeDispatcherTrait, NOT_ADMIN, NOT_IMPLEMENTED, NOT_LIVE, NOT_NEXT, NO_PARENT,
    OUTLINE_CHUNK, PART_COUNT, TOO_MANY, ZERO_ADMIN, ZERO_ID,
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

fn live(value: felt252) -> felt252 {
    LIVE + value
}

fn one(value: felt252) -> Span<felt252> {
    array![live(value)].span()
}

fn two(a: felt252, b: felt252) -> Span<felt252> {
    array![live(a), b].span()
}

fn three(a: felt252, b: felt252, c: felt252) -> Span<felt252> {
    array![live(a), b, c].span()
}

fn version(r: Registry) -> u32 {
    r.read.content_version()
}

// --- set_record: what it writes -----------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 4655207)] // ceil(1.05 × 4433530 measured)
fn test_set_record_new_sequential() {
    let r = deploy();
    assert(r.admin.last_id(LOCATION) == 0, 'none yet');
    r.admin.set_record(LOCATION, 1, two(5, 6));
    assert(r.admin.last_id(LOCATION) == 1, 'last id 1');
    assert(r.read.record(LOCATION, 1) == two(5, 6), 'read back');
    r.admin.set_record(LOCATION, 2, two(7, 0));
    assert(r.admin.last_id(LOCATION) == 2, 'last id 2');
    assert(r.read.record(LOCATION, 2) == two(7, 0), 'a part of 0');
    assert(r.admin.last_id(GATE) == 0, 'other kinds apart');
}

// An existing record's values change (design/01 rule 2: ids are append-only, values are not).
#[test]
#[available_gas(l2_gas: 4776240)] // ceil(1.05 × 4548800 measured)
fn test_set_record_existing_changes() {
    let r = deploy();
    r.admin.set_record(LOCATION, 1, two(5, 6));
    r.admin.set_record(LOCATION, 2, two(7, 8));
    r.admin.set_record(LOCATION, 1, two(9, 0));
    assert(r.read.record(LOCATION, 1) == two(9, 0), 'changed');
    assert(r.read.record(LOCATION, 2) == two(7, 8), 'the other kept');
    assert(r.admin.last_id(LOCATION) == 2, 'last id kept');
}

// Composite kinds (`OUTLINE`, `SHOP`): any id whose parent exists; `last_id` stays 0.
#[test]
#[available_gas(l2_gas: 7582586)] // ceil(1.05 × 7221510 measured)
#[feature("safe_dispatcher")]
fn test_set_record_composite_needs_parent() {
    let r = deploy();
    // Location 2 does not exist yet: its outline and a shop of hub 2 are refused.
    let refused = r.safe.set_record(OUTLINE, 2 * 256 + 255, one(1));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'outline without location');
    let refused = r.safe.set_record(SHOP, 2 * 16 + 1, two(1, 0));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'shop without hub');
    r.admin.set_record(LOCATION, 1, two(0, 0));
    r.admin.set_record(LOCATION, 2, two(0, 0));
    r.admin.set_record(OUTLINE, 2 * 256 + 255, one(1));
    r.admin.set_record(OUTLINE, 2 * 256 + 16, one(2));
    r.admin.set_record(SHOP, 2 * 16 + 1, two(3, 4));
    assert(r.read.record(OUTLINE, 2 * 256 + 255) == one(1), 'chunk set');
    assert(r.read.record(OUTLINE, 2 * 256 + 16) == one(2), 'border mask');
    assert(r.read.record(SHOP, 2 * 16 + 1) == two(3, 4), 'shop');
    assert(r.admin.last_id(OUTLINE) == 0 && r.admin.last_id(SHOP) == 0, 'composite: last id 0');
    // Location 3 still does not exist.
    let refused = r.safe.set_record(OUTLINE, 3 * 256 + 255, one(1));
    assert(*refused.unwrap_err().at(0) == NO_PARENT, 'outline of location 3');
}

// An outline's chunk is a chunk of the location (below 225) or 255, its chunk set.
#[test]
#[available_gas(l2_gas: 4411575)] // ceil(1.05 × 4201500 measured)
#[feature("safe_dispatcher")]
fn test_set_record_outline_chunk_refused() {
    let r = deploy();
    r.admin.set_record(LOCATION, 1, two(0, 0));
    let refused = r.safe.set_record(OUTLINE, 256 + 225, one(1));
    assert(*refused.unwrap_err().at(0) == OUTLINE_CHUNK, 'chunk 225');
    let refused = r.safe.set_record(OUTLINE, 256 + 254, one(1));
    assert(*refused.unwrap_err().at(0) == OUTLINE_CHUNK, 'chunk 254');
    r.admin.set_record(OUTLINE, 256 + 224, one(1));
    r.admin.set_record(OUTLINE, 256 + 255, one(1));
}

// `TASK` and `QUEST` take quiver's ids: any non-zero id.
#[test]
#[available_gas(l2_gas: 3848975)] // ceil(1.05 × 3665690 measured)
fn test_set_record_quiver_ids() {
    let r = deploy();
    r.admin.set_record(TASK, 0x12345, one(1));
    r.admin.set_record(QUEST, 0xFFFFFFFF, two(1, 2));
    assert(r.read.record(TASK, 0x12345) == one(1), 'task');
    assert(r.read.record(QUEST, 0xFFFFFFFF) == two(1, 2), 'quest');
    assert(r.admin.last_id(TASK) == 0 && r.admin.last_id(QUEST) == 0, 'last id 0');
}

// --- set_record: its refusals (AC-1) ------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1316732)] // ceil(1.05 × 1254030 measured)
#[feature("safe_dispatcher")]
fn test_set_record_refused_to_others() {
    let r = deploy();
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    let refused = r.safe.set_record(REGION, 1, one(1));
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    assert(r.admin.last_id(REGION) == 0 && version(r) == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 1701578)] // ceil(1.05 × 1620550 measured)
#[feature("safe_dispatcher")]
fn test_set_record_part_count_refused() {
    let r = deploy();
    let refused = r.safe.set_record(LOCATION, 1, one(1));
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'too few');
    let refused = r.safe.set_record(LOCATION, 1, three(1, 2, 3));
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'too many');
    let refused = r.safe.set_record(REGION, 1, array![].span());
    assert(*refused.unwrap_err().at(0) == PART_COUNT, 'empty');
    assert(r.admin.last_id(LOCATION) == 0 && version(r) == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 1268988)] // ceil(1.05 × 1208560 measured)
#[feature("safe_dispatcher")]
fn test_set_record_unknown_kind_refused() {
    let r = deploy();
    let refused = r.safe.set_record(0, 1, one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 0');
    let refused = r.safe.set_record(26, 1, one(1));
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'kind 26');
    let refused = r.safe_read.record(26, 1);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'read kind 26');
    let refused = r.safe.last_id(0);
    assert(*refused.unwrap_err().at(0) == UNKNOWN_KIND, 'last id kind 0');
}

#[test]
#[available_gas(l2_gas: 2160459)] // ceil(1.05 × 2057580 measured)
#[feature("safe_dispatcher")]
fn test_set_record_not_live_refused() {
    let r = deploy();
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
    assert(r.admin.last_id(REGION) == 0 && version(r) == 0, 'nothing written');
}

#[test]
#[available_gas(l2_gas: 1212078)] // ceil(1.05 × 1154360 measured)
#[feature("safe_dispatcher")]
fn test_set_record_id_zero_refused() {
    let r = deploy();
    let refused = r.safe.set_record(REGION, 0, one(1));
    assert(*refused.unwrap_err().at(0) == ZERO_ID, 'sequential');
    let refused = r.safe.set_record(TASK, 0, one(1));
    assert(*refused.unwrap_err().at(0) == ZERO_ID, 'composite');
}

// Sequential kinds are append-only: a new id is `last_id + 1`, never a gap.
#[test]
#[available_gas(l2_gas: 3370028)] // ceil(1.05 × 3209550 measured)
#[feature("safe_dispatcher")]
fn test_set_record_not_next_refused() {
    let r = deploy();
    let refused = r.safe.set_record(GATE, 2, one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'first is 1');
    r.admin.set_record(GATE, 1, one(1));
    let refused = r.safe.set_record(GATE, 3, one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'a gap');
    let refused = r.safe.set_record(GATE, 0xFFFFFFFF, one(1));
    assert(*refused.unwrap_err().at(0) == NOT_NEXT, 'far');
    assert(r.admin.last_id(GATE) == 1 && version(r) == 1, 'only gate 1');
}

// --- the content version (AC-2) -----------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 9012371)] // ceil(1.05 × 8583210 measured)
fn test_version_rises_per_changed_record() {
    let r = deploy();
    assert(version(r) == 0, '0 at deployment');
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
    assert(version(r) == 1, 'new record: +1');
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
    assert(version(r) == 1, 'same values: +0');
    r.admin.set_record(BOOK, 1, three(1, 2, 4));
    assert(version(r) == 2, 'one part: +1');
    r.admin.set_record(BOOK, 1, three(5, 6, 7));
    assert(version(r) == 3, 'three parts: +1');
    r.admin.set_record(BOOK, 1, three(5, 6, 7));
    assert(version(r) == 3, 'same again: +0');
    // A part set back to 0 is a change.
    r.admin.set_record(BOOK, 1, three(5, 0, 7));
    assert(version(r) == 4, 'to zero: +1');
    // Composite kinds likewise.
    r.admin.set_record(LOCATION, 1, two(0, 0));
    assert(version(r) == 5, 'location: +1');
    r.admin.set_record(OUTLINE, 256 + 255, one(9));
    assert(version(r) == 6, 'new outline: +1');
    r.admin.set_record(OUTLINE, 256 + 255, one(9));
    assert(version(r) == 6, 'same outline: +0');
    r.admin.set_record(OUTLINE, 256 + 255, one(8));
    assert(version(r) == 7, 'changed outline: +1');
}

#[test]
#[available_gas(l2_gas: 7560651)] // ceil(1.05 × 7200620 measured)
fn test_bundle_version_and_order() {
    let r = deploy();
    r.admin.set_record(REGION, 1, one(1));
    r.admin.set_record(LOCATION, 1, two(2, 3));
    r.admin.set_record(BOOK, 1, three(4, 5, 6));
    let (v, records) = r
        .read
        .bundle(array![(BOOK, 1), (REGION, 1), (LOCATION, 2), (LOCATION, 1)].span());
    assert(v == 3, 'version');
    // In the order asked; location 2 is missing: two zeros.
    let expected = array![live(4), 5, 6, live(1), 0, 0, live(2), 3];
    assert(records == expected.span(), 'records in order');
    r.admin.set_record(REGION, 1, one(7));
    let (v, records) = r.read.bundle(array![(REGION, 1)].span());
    assert(v == 4 && records == one(7), 'after a change');
    let (v, records) = r.read.bundle(array![].span());
    assert(v == 4 && records.len() == 0, 'no request');
}

// A record never written reads as `parts(kind)` zeros: part 0 is 0, the record does not exist.
#[test]
#[available_gas(l2_gas: 3105963)] // ceil(1.05 × 2958060 measured)
fn test_missing_record_reads_zeros() {
    let r = deploy();
    assert(r.read.record(BOOK, 1) == array![0, 0, 0].span(), 'record');
    assert(r.read.records(REGION, array![1, 2].span()) == array![0, 0].span(), 'records');
    r.admin.set_record(REGION, 1, one(1));
    assert(r.read.records(REGION, array![2, 1].span()) == array![0, live(1)].span(), 'mixed');
}

#[test]
#[available_gas(l2_gas: 5043266)] // ceil(1.05 × 4803110 measured)
#[feature("safe_dispatcher")]
fn test_reads_bounded() {
    let r = deploy();
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
#[available_gas(l2_gas: 3180188)] // ceil(1.05 × 3028750 measured)
#[feature("safe_dispatcher")]
fn test_set_admin_hands_over() {
    let r = deploy();
    r.admin.set_admin(OTHER.try_into().unwrap());
    let refused = r.safe.set_record(REGION, 1, one(1));
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'former admin');
    let refused = r.safe.set_admin(ADMIN.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'former admin, set_admin');
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    r.admin.set_record(REGION, 1, one(1));
    assert(r.admin.last_id(REGION) == 1, 'new admin writes');
}

#[test]
#[available_gas(l2_gas: 2854803)] // ceil(1.05 × 2718860 measured)
#[feature("safe_dispatcher")]
fn test_set_admin_refused() {
    let r = deploy();
    start_cheat_caller_address(r.address, OTHER.try_into().unwrap());
    let refused = r.safe.set_admin(OTHER.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_ADMIN, 'not admin');
    start_cheat_caller_address(r.address, ADMIN.try_into().unwrap());
    let refused = r.safe.set_admin(0.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == ZERO_ADMIN, 'zero');
    r.admin.set_record(REGION, 1, one(1));
}

#[test]
#[available_gas(l2_gas: 859131)] // ceil(1.05 × 818220 measured)
#[feature("safe_dispatcher")]
fn test_upgrade_stub() {
    let r = deploy();
    let refused = r.safe.upgrade(0x1234.try_into().unwrap());
    assert(*refused.unwrap_err().at(0) == NOT_IMPLEMENTED, 'stub');
}

// --- gas (AC-5): each call alone is in `snforge test --gas-report`; see GAS.md ------------------

/// `count` 3-part records (`BOOK`, the widest kind) written straight into storage, and the version.
fn stored_books(r: Registry, count: u32) -> Array<(u8, u32)> {
    let mut requests: Array<(u8, u32)> = array![];
    for id in 1..count + 1 {
        for part in 0..3_u8 {
            store(
                r.address,
                map_entry_address(
                    selector!("records"), array![BOOK.into(), id.into(), part.into()].span(),
                ),
                array![live(id.into())].span(),
            );
        }
        requests.append((BOOK, id));
    }
    store(r.address, selector!("content_version"), array![5].span());
    requests
}

// The baseline of the tests below: the deployment alone.
#[test]
#[available_gas(l2_gas: 748902)] // ceil(1.05 × 713240 measured)
fn test_gas_deploy() {
    deploy();
}

// `set_record` of a new 3-part record: 3 record slots, `last_id` and the version, all new
// (ENG-01 §10: 5 N / 0 O).
#[test]
#[available_gas(l2_gas: 3379026)] // ceil(1.05 × 3218120 measured)
fn test_gas_set_record_new() {
    let r = deploy();
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
}

// `set_record` changing a 3-part record: its 3 parts and the version overwritten (ENG-01 §10:
// 0 N / 5 O, which counts `last_id` too; a changed record does not write it).
#[test]
#[available_gas(l2_gas: 3950993)] // ceil(1.05 × 3762850 measured)
fn test_gas_set_record_changed() {
    let r = deploy();
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
    r.admin.set_record(BOOK, 1, three(4, 5, 6));
}

// `set_record` of the same values: 3 reads, nothing written, the version kept.
#[test]
#[available_gas(l2_gas: 3695024)] // ceil(1.05 × 3519070 measured)
fn test_gas_set_record_unchanged() {
    let r = deploy();
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
    r.admin.set_record(BOOK, 1, three(1, 2, 3));
}

// `records` against `bundle` for the same record: the difference is the version's read.
#[test]
#[available_gas(l2_gas: 2773302)] // ceil(1.05 × 2641240 measured)
fn test_gas_records_1() {
    let r = deploy();
    stored_books(r, 1);
    assert(r.read.records(BOOK, array![1].span()).len() == 3, '3 felts');
}

#[test]
#[available_gas(l2_gas: 2795930)] // ceil(1.05 × 2662790 measured)
fn test_gas_bundle_1() {
    let r = deploy();
    let requests = stored_books(r, 1);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 3, '1 record');
}

#[test]
#[available_gas(l2_gas: 16043318)] // ceil(1.05 × 15279350 measured)
fn test_gas_bundle_10() {
    let r = deploy();
    let requests = stored_books(r, 10);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 30, '10 records');
}

// The bound: 32 records of 3 parts, 96 slots and the version (ENG-01 §9.3: at most 97 reads).
#[test]
#[available_gas(l2_gas: 48425822)] // ceil(1.05 × 46119830 measured)
fn test_gas_bundle_32() {
    let r = deploy();
    let requests = stored_books(r, 32);
    let (v, records) = r.read.bundle(requests.span());
    assert(v == 5 && records.len() == 96, '32 records');
}
