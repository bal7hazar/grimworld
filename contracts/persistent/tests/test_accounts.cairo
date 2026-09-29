// ENG-04: accounts and adventurers on `Hub` (design/03, D-32, D-33; ADR-0005; ENG-01 §1.2, §3.3,
// §9.3, §10). Every refusal has its test; the write sets are counted over the keys a test watches
// (`load` before and after); the ownership helper is tested through `delete_adventurer`, the one
// entrypoint of this lot that names an adventurer. `Instances.set_controller` is ENG-06's: a
// double stands in its place and records the controller it is given.
use core::num::traits::Pow;
use core::testing::get_available_gas;
use grimworld_logic::packing::Lanes32;
use grimworld_logic::professions::{ARCANIST, VANGUARD, WARDEN, is_playable};
use grimworld_persistent::models::account::{
    AccountRecord, NEW_RECORD, ONE_ADVENTURER, PACK, START_SLOTS, lane_at, lane_unit, owner_key,
    slots_and_count, with_lane,
};
use grimworld_persistent::models::adventurer::{
    ACTIVE, AdventurerCore, AdventurerPlace, Build, DELETED, DELETED_MARK, EMPTY_LANES, NEW_BUILD,
    NO_ELITE, core_fields, is_inside, new_core,
};
use grimworld_persistent::models::item::Gold;
use grimworld_persistent::systems::hub::{
    ADVENTURER_DELETED, BAD_PROFESSION, EMPTY_NAME, HAS_ACCOUNT, IHubAdminDispatcher,
    IHubAdminDispatcherTrait, IHubDispatcher, IHubDispatcherTrait, IHubSafeDispatcher,
    IHubSafeDispatcherTrait, IHubViewsDispatcher, IHubViewsDispatcherTrait, NEW_PLACE,
    NOT_ACCOUNT_OWNER, NOT_IN_HUB, NOT_OWNER, NO_ACCOUNT, NO_ADVENTURER, NO_FREE_SLOT,
    OWNER_HAS_ACCOUNT, PACK_HOLDS_EQUIPMENT, PACK_HOLDS_GOLD, PACK_HOLDS_ITEMS, START_HUB,
    START_UNLOCKED, WEARS_EQUIPMENT, ZERO_OWNER,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, map_entry_address,
    start_cheat_caller_address, store,
};
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

/// Stands in for `Instances.set_controller` (ENG-06's): only the registered hub may call it, as
/// ENG-01 §1.2 says; it records the controller, one word per adventurer as the member's is.
#[starknet::interface]
pub trait IDoubleViews<T> {
    fn controller(self: @T, adventurer_id: u32) -> ContractAddress;
}

#[starknet::contract]
mod InstancesDouble {
    use grimworld_logic::interface::IInstanceEntry;
    use grimworld_logic::snapshot::{Snapshot, TaskEntry};
    use grimworld_logic::types::InstanceId;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        hub: ContractAddress,
        controllers: Map<u32, ContractAddress>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, hub: ContractAddress) {
        self.hub.write(hub);
    }

    #[abi(embed_v0)]
    impl EntryImpl of IInstanceEntry<ContractState> {
        fn create(
            ref self: ContractState,
            adventurer_id: u32,
            controller: ContractAddress,
            gate: u16,
            snapshot: Snapshot,
            tasks: Span<TaskEntry>,
        ) -> InstanceId {
            core::panic_with_felt252('double: no create')
        }
        fn set_controller(ref self: ContractState, adventurer_id: u32, controller: ContractAddress) {
            assert(get_caller_address() == self.hub.read(), 'double: not the hub');
            self.controllers.entry(adventurer_id).write(controller);
        }
    }

    #[abi(embed_v0)]
    impl ViewsImpl of super::IDoubleViews<ContractState> {
        fn controller(self: @ContractState, adventurer_id: u32) -> ContractAddress {
            self.controllers.entry(adventurer_id).read()
        }
    }
}

const ADMIN: felt252 = 0xad;
const ALICE: felt252 = 0xa11ce;
const BOB: felt252 = 0xb0b;
const CAROL: felt252 = 0xca201;
const NAME: felt252 = 'Aldric';

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

/// `Hub`, with the double registered as its `Instances`.
fn setup() -> (ContractAddress, ContractAddress) {
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![ADMIN, 2, 3, 4, 5]).unwrap();
    let class = declare("InstancesDouble").unwrap().contract_class();
    let (double, _) = class.deploy(@array![hub.into()]).unwrap();
    start_cheat_caller_address(hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: hub }.set_contracts(addr(2), double, addr(4), addr(5));
    (hub, double)
}

fn act(hub: ContractAddress, who: felt252) -> IHubDispatcher {
    start_cheat_caller_address(hub, addr(who));
    IHubDispatcher { contract_address: hub }
}

fn try_act(hub: ContractAddress, who: felt252) -> IHubSafeDispatcher {
    start_cheat_caller_address(hub, addr(who));
    IHubSafeDispatcher { contract_address: hub }
}

fn views(hub: ContractAddress) -> IHubViewsDispatcher {
    IHubViewsDispatcher { contract_address: hub }
}

fn refused<T, +Drop<T>>(result: Result<T, Array<felt252>>, message: felt252) {
    match result {
        Result::Ok(_) => core::panic_with_felt252('should be refused'),
        Result::Err(data) => assert(*data.at(0) == message, *data.at(0)),
    }
}

/// An account for `who`, with `count` adventurers.
fn with_adventurers(hub: ContractAddress, who: felt252, count: u8) -> (u32, Array<u32>) {
    let hub_ = act(hub, who);
    let account = hub_.register();
    let mut ids = array![];
    for _ in 0..count {
        ids.append(hub_.create_adventurer(NAME, VANGUARD));
    }
    (account, ids)
}

// Storage addresses (ENG-01 §3.3).
fn adventurer_word(id: u32, word: felt252) -> felt252 {
    map_entry_address(selector!("adventurers"), array![id.into()].span()) + word
}
fn account_word(id: u32, word: felt252) -> felt252 {
    map_entry_address(selector!("accounts"), array![id.into()].span()) + word
}
fn list_page(account: u32, page: u8) -> felt252 {
    map_entry_address(selector!("account_adventurers"), array![account.into(), page.into()].span())
}
fn account_of_key(owner: felt252) -> felt252 {
    map_entry_address(selector!("account_of"), array![owner].span())
}

fn read(target: ContractAddress, key: felt252) -> felt252 {
    *load(target, key, 1).at(0)
}
fn write(target: ContractAddress, key: felt252, value: felt252) {
    store(target, key, array![value].span());
}

fn core_of(hub: ContractAddress, id: u32) -> AdventurerCore {
    StorePacking::unpack(read(hub, adventurer_word(id, 0)))
}
fn set_core(hub: ContractAddress, id: u32, core: AdventurerCore) {
    write(hub, adventurer_word(id, 0), StorePacking::pack(core));
}
fn record_of(hub: ContractAddress, account: u32) -> AccountRecord {
    StorePacking::unpack(read(hub, account_word(account, 1)))
}
/// More slots than an account starts with: no entrypoint of the MVP sells them yet (design/03).
fn set_slots(hub: ContractAddress, account: u32, slots: u8) {
    let record = AccountRecord { slots, ..record_of(hub, account) };
    write(hub, account_word(account, 1), StorePacking::pack(record));
}
/// The adventurer inside an instance, as `enter` (ENG-06) will leave it.
fn put_inside(hub: ContractAddress, id: u32) {
    let place: AdventurerPlace = StorePacking::unpack(read(hub, adventurer_word(id, 1)));
    let inside = AdventurerPlace { instance: 0x100000001, hub: 0, inside: 1, ..place };
    write(hub, adventurer_word(id, 1), StorePacking::pack(inside));
}

/// The keys a write-set test watches: every key the four entrypoints could reach for accounts 1-3,
/// adventurers 1-10 and the three players, and their neighbours.
fn watched() -> Array<felt252> {
    let mut keys = array![
        selector!("admin"), selector!("registry"), selector!("instances"), selector!("market"),
        selector!("fate"), selector!("next_account"), selector!("next_adventurer"),
        selector!("next_item"), account_of_key(ALICE), account_of_key(BOB), account_of_key(CAROL),
    ];
    for account in 1..4_u32 {
        keys.append(account_word(account, 0));
        keys.append(account_word(account, 1));
        for page in 0..3_u8 {
            keys.append(list_page(account, page));
        }
        keys.append(map_entry_address(selector!("vaults"), array![account.into(), 0].span()));
        keys.append(map_entry_address(selector!("rift_boards"), array![account.into()].span()));
    }
    for id in 1..11_u32 {
        for word in 0..6_u8 {
            keys.append(adventurer_word(id, word.into()));
        }
        keys.append(map_entry_address(selector!("packs"), array![id.into(), 0].span()));
        keys.append(map_entry_address(selector!("gold"), array![owner_key(PACK, id)].span()));
    }
    keys
}

fn snapshot(hub: ContractAddress, keys: Span<felt252>) -> Array<felt252> {
    let mut values = array![];
    for key in keys {
        values.append(read(hub, *key));
    }
    values
}

/// `(new, overwritten, zeroed)`: keys 0 before and not after, changed from one value to another,
/// changed to 0.
fn changes(before: Span<felt252>, after: Span<felt252>) -> (u32, u32, u32) {
    let (mut new, mut old, mut zeroed) = (0_u32, 0_u32, 0_u32);
    for i in 0..before.len() {
        let (b, a) = (*before.at(i), *after.at(i));
        if b != a {
            if b == 0 {
                new += 1;
            } else if a == 0 {
                zeroed += 1;
            } else {
                old += 1;
            }
        }
    }
    (new, old, zeroed)
}

// ---- the stored words written by arithmetic, against the packers (the oracle, CAIRO §2) --------

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_stored_words() {
    let record = AccountRecord { slots: START_SLOTS, ..Default::default() };
    assert(NEW_RECORD == StorePacking::pack(record), 'new record');
    let more = AccountRecord { slots: 9, adventurers: 5, highest_rank: 4, vault_panes: 2, lots: 7 };
    let word: felt252 = StorePacking::pack(more);
    assert(slots_and_count(word) == (9, 5), 'slots and count');
    let one_more = AccountRecord { adventurers: 6, ..more };
    assert(word + ONE_ADVENTURER == StorePacking::pack(one_more), 'one adventurer');

    let core = AdventurerCore {
        account: 0xFFFFFFFF, level: 1, profession: ARCANIST, status: ACTIVE, ..Default::default()
    };
    assert(new_core(0xFFFFFFFF, ARCANIST) == StorePacking::pack(core), 'new core');
    let full = AdventurerCore {
        account: 0x12345678,
        experience: 0xFFFFFFFF,
        merit: 0xFFFFFFFF,
        level: 255,
        rank: 255,
        profession: 255,
        secondary: 255,
        unspent: 0xFFFF,
        trials_first: 0xFFFF,
        trials_tried: 0xFFFF,
        status: ACTIVE,
        pack_lanes: 0xFFFF,
    };
    let word: felt252 = StorePacking::pack(full);
    assert(core_fields(word) == (0x12345678, ACTIVE, 0xFFFF), 'core fields');
    let deleted: felt252 = StorePacking::pack(AdventurerCore { status: DELETED, ..full });
    assert(word + DELETED_MARK == deleted, 'deleted mark');
    assert(core_fields(deleted) == (0x12345678, DELETED, 0xFFFF), 'deleted fields');

    let place = AdventurerPlace {
        instance: 0, hub: START_HUB, last_hub: START_HUB, inside: 0, unlocked: START_UNLOCKED,
    };
    assert(NEW_PLACE == StorePacking::pack(place), 'new place');
    assert(!is_inside(NEW_PLACE), 'new: in a hub');
    let inside: felt252 = StorePacking::pack(
        AdventurerPlace { instance: 0xFFFFFFFFFFFFFFFF, hub: 0, inside: 1, ..place },
    );
    assert(is_inside(inside), 'inside');
    let build = Build { bar: [0; 8], attributes: 0, elite_slot: NO_ELITE };
    assert(NEW_BUILD == StorePacking::pack(build), 'new build');
    assert(EMPTY_LANES == StorePacking::pack(Lanes32 { lanes: [0; 7] }), 'empty lanes');

    let page = Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] };
    let word: felt252 = StorePacking::pack(page);
    for lane in 0..7_u8 {
        let expected = Lanes32 { lanes: with_lane(page, lane, 0xFFFFFFFF).lanes };
        let changed = word + (0xFFFFFFFF - lane_at(page, lane)).into() * lane_unit(lane);
        assert(changed == StorePacking::pack(expected), 'lane unit');
    }
}

// ---- register ----------------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_register() {
    let (hub, _) = setup();
    let keys = watched();
    let before = snapshot(hub, keys.span());
    let hub_ = act(hub, ALICE);
    let gas = get_available_gas();
    let account = hub_.register();
    println!("gas register: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    // ENG-01 §9.3: the account's two words and `account_of` new, `next_account` overwritten.
    assert(changes(before.span(), after.span()) == (3, 1, 0), 'writes 3 N / 1 O');
    assert(account == 1, 'first account');
    assert(views(hub).account_of(addr(ALICE)) == 1, 'account_of');
    let (owner, word, ids) = views(hub).account(1);
    assert(owner == addr(ALICE), 'owner');
    let record: AccountRecord = StorePacking::unpack(word);
    assert(record == AccountRecord { slots: 3, ..Default::default() }, 'three slots');
    assert(word == read(hub, account_word(1, 1)), 'record as stored');
    assert(ids.len() == 0, 'no adventurer');
    assert(act(hub, BOB).register() == 2, 'second account');
    assert(views(hub).account_of(addr(CAROL)) == 0, 'no account: 0');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_register_twice_refused() {
    let (hub, _) = setup();
    act(hub, ALICE).register();
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).register(), HAS_ACCOUNT);
}

// ---- create_adventurer -------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_create_adventurer() {
    let (hub, _) = setup();
    let hub_ = act(hub, ALICE);
    hub_.register();
    let keys = watched();

    // Cold: the list's page is written for the first time.
    let before = snapshot(hub, keys.span());
    start_cheat_caller_address(hub, addr(ALICE));
    let gas = get_available_gas();
    let id = hub_.create_adventurer(NAME, WARDEN);
    println!("gas create_adventurer cold: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    assert(changes(before.span(), after.span()) == (7, 2, 0), 'cold: 7 N / 2 O');

    // Initialised: the page exists.
    let before = snapshot(hub, keys.span());
    let gas = get_available_gas();
    let second = hub_.create_adventurer('Brenna', ARCANIST);
    println!("gas create_adventurer initialised: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    assert(changes(before.span(), after.span()) == (6, 3, 0), 'initialised: 6 N / 3 O');

    assert(id == 1 && second == 2, 'ids');
    let expected = AdventurerCore {
        account: 1, level: 1, profession: WARDEN, status: ACTIVE, ..Default::default()
    };
    assert(core_of(hub, id) == expected, 'core');
    let words = views(hub).adventurer(id);
    assert(words.len() == 6, 'six words');
    let place: AdventurerPlace = StorePacking::unpack(*words.at(1));
    let at_start = AdventurerPlace {
        instance: 0, hub: START_HUB, last_hub: START_HUB, inside: 0, unlocked: START_UNLOCKED,
    };
    assert(place == at_start, 'in the town hub');
    assert(START_UNLOCKED == 2_u64.pow(START_HUB.into()), 'bit START_HUB');
    let build: Build = StorePacking::unpack(*words.at(2));
    assert(build == Build { bar: [0; 8], attributes: 0, elite_slot: NO_ELITE }, 'build');
    let empty: Lanes32 = StorePacking::unpack(*words.at(3));
    assert(empty.lanes == [0; 7], 'belt');
    let empty: Lanes32 = StorePacking::unpack(*words.at(4));
    assert(empty.lanes == [0; 7], 'equipped');
    assert(*words.at(5) == NAME, 'name');
    for i in 0..6_u8 {
        assert(*words.at(i.into()) == read(hub, adventurer_word(id, i.into())), 'as stored');
    }
    let (_, word, ids) = views(hub).account(1);
    let record: AccountRecord = StorePacking::unpack(word);
    assert(record.adventurers == 2, 'two adventurers');
    assert(ids == array![1, 2].span(), 'listed');
    assert(views(hub).adventurer(99) == array![0, 0, 0, 0, 0, 0].span(), 'never created');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_playable_professions() {
    assert(!is_playable(0), 'none');
    assert(is_playable(VANGUARD) && is_playable(WARDEN) && is_playable(ARCANIST), 'the MVP three');
    assert(VANGUARD == 1 && WARDEN == 2 && ARCANIST == 3, 'design/03 order');
    assert(!is_playable(4) && !is_playable(255), 'not in the MVP');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_create_without_account_refused() {
    let (hub, _) = setup();
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).create_adventurer(NAME, VANGUARD), NO_ACCOUNT);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_create_empty_name_refused() {
    let (hub, _) = setup();
    act(hub, ALICE).register();
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).create_adventurer(0, VANGUARD), EMPTY_NAME);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_create_bad_profession_refused() {
    let (hub, _) = setup();
    act(hub, ALICE).register();
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).create_adventurer(NAME, 0), BAD_PROFESSION);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).create_adventurer(NAME, 4), BAD_PROFESSION);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_create_no_free_slot_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 3);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).create_adventurer(NAME, VANGUARD), NO_FREE_SLOT);
}

// ---- delete_adventurer -------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_frees_the_slot_and_marks_the_record() {
    let (hub, _) = setup();
    let (_, ids) = with_adventurers(hub, ALICE, 3);
    let keys = watched();
    let words = views(hub).adventurer(1);

    let before = snapshot(hub, keys.span());
    let hub_ = act(hub, ALICE);
    let gas = get_available_gas();
    hub_.delete_adventurer(*ids.at(0));
    println!("gas delete_adventurer, one page: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    // core, the record, the list's page (the hole and the last lane on one page): nothing zeroed.
    assert(changes(before.span(), after.span()) == (0, 3, 0), 'one page: 0 N / 3 O');

    // The record stays, marked; only `status` changed.
    let marked = views(hub).adventurer(1);
    let core = core_of(hub, 1);
    assert(core.status == DELETED, 'marked');
    let unmarked: AdventurerCore = StorePacking::unpack(*words.at(0));
    assert(AdventurerCore { status: ACTIVE, ..core } == unmarked, 'core kept');
    for i in 1..6_u32 {
        assert(*marked.at(i) == *words.at(i), 'words kept');
    }
    // The last id moved into the hole.
    let (_, _, listed) = views(hub).account(1);
    assert(listed == array![3, 2].span(), 'swap removal');
    // The slot is reusable; the id is not.
    assert(hub_.create_adventurer('Cedric', ARCANIST) == 4, 'a new id');
    let (_, _, listed) = views(hub).account(1);
    assert(listed == array![3, 2, 4].span(), 'slot reused');
    assert(record_of(hub, 1).adventurers == 3, 'three again');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_the_last_listed() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 3);
    act(hub, ALICE).delete_adventurer(3);
    let (_, _, listed) = views(hub).account(1);
    assert(listed == array![1, 2].span(), 'last removed');
    act(hub, ALICE).delete_adventurer(1);
    act(hub, ALICE).delete_adventurer(2);
    let (_, _, listed) = views(hub).account(1);
    assert(listed.len() == 0, 'empty');
    assert(read(hub, list_page(1, 0)) != 0, 'page kept LIVE');
}

/// ENG-01 §9.3's worst case: the hole and the last id on two pages (an account of eight).
#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_across_pages() {
    let (hub, _) = setup();
    act(hub, ALICE).register();
    set_slots(hub, 1, 8);
    let hub_ = act(hub, ALICE);
    for _ in 0..8_u8 {
        hub_.create_adventurer(NAME, VANGUARD);
    }
    let keys = watched();
    let before = snapshot(hub, keys.span());
    start_cheat_caller_address(hub, addr(ALICE));
    let gas = get_available_gas();
    hub_.delete_adventurer(2);
    println!("gas delete_adventurer, two pages: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 4, 0), 'two pages: 0 N / 4 O');
    let (_, _, listed) = views(hub).account(1);
    assert(listed == array![1, 8, 3, 4, 5, 6, 7].span(), 'eighth into the hole');
}

// The ownership helper, each case (through `delete_adventurer`).

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_helper_no_adventurer() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(2), NO_ADVENTURER);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(0), NO_ADVENTURER);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_helper_not_owner() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    with_adventurers(hub, BOB, 1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, BOB).delete_adventurer(1), NOT_OWNER);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, CAROL).delete_adventurer(1), NOT_OWNER);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_helper_deleted() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 2);
    act(hub, ALICE).delete_adventurer(1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), ADVENTURER_DELETED);
    let (_, _, listed) = views(hub).account(1);
    assert(listed == array![2].span(), 'deleted once');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_helper_not_in_a_hub() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    put_inside(hub, 1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), NOT_IN_HUB);
}

// "Its inventory emptied" (design/03, D-33), each part.

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_pack_balances_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    set_core(hub, 1, AdventurerCore { pack_lanes: 1, ..core_of(hub, 1) });
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), PACK_HOLDS_ITEMS);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_pack_equipment_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    let page = map_entry_address(selector!("packs"), array![1, 0].span());
    write(hub, page, StorePacking::pack(Lanes32 { lanes: [77, 0, 0, 0, 0, 0, 0] }));
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), PACK_HOLDS_EQUIPMENT);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_equipped_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    let worn = Lanes32 { lanes: [0, 0, 0, 0, 0, 0, 78] };
    write(hub, adventurer_word(1, 4), StorePacking::pack(worn));
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), WEARS_EQUIPMENT);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_pack_gold_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    let key = map_entry_address(selector!("gold"), array![owner_key(PACK, 1)].span());
    write(hub, key, StorePacking::pack(Gold { amount: 1 }));
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), PACK_HOLDS_GOLD);
}

/// A pack emptied again (its lanes, pages and gold kept `LIVE` at 0) does not stop deletion.
#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_delete_after_the_pack_was_emptied() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    let page = map_entry_address(selector!("packs"), array![1, 0].span());
    write(hub, page, StorePacking::pack(Lanes32 { lanes: [0; 7] }));
    let key = map_entry_address(selector!("gold"), array![owner_key(PACK, 1)].span());
    write(hub, key, StorePacking::pack(Gold { amount: 0 }));
    act(hub, ALICE).delete_adventurer(1);
    assert(core_of(hub, 1).status == DELETED, 'deleted');
}

// ---- set_account_owner -------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner() {
    let (hub, double) = setup();
    with_adventurers(hub, ALICE, 2);
    let keys = watched();
    let before = snapshot(hub, keys.span());
    let hub_ = act(hub, ALICE);
    let gas = get_available_gas();
    hub_.set_account_owner(1, addr(BOB));
    println!("gas set_account_owner, none inside: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    // The owner word overwritten, `account_of[BOB]` new, `account_of[ALICE]` zeroed (E-19).
    assert(changes(before.span(), after.span()) == (1, 1, 1), 'writes 1 N / 1 O / 1 zeroed');
    assert(read(hub, account_of_key(ALICE)) == 0, 'old entry zeroed');
    assert(views(hub).account_of(addr(BOB)) == 1, 'moved');
    assert(views(hub).account_of(addr(ALICE)) == 0, 'old owner: none');
    let (owner, _, listed) = views(hub).account(1);
    assert(owner == addr(BOB), 'new owner');
    assert(listed == array![1, 2].span(), 'adventurers stay');
    let double_ = IDoubleViewsDispatcher { contract_address: double };
    assert(double_.controller(1) == addr(0) && double_.controller(2) == addr(0), 'none inside');

    // The old owner lost the adventurers; the new one has them.
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).delete_adventurer(1), NOT_OWNER);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).set_account_owner(1, addr(CAROL)), NOT_ACCOUNT_OWNER);
    act(hub, BOB).delete_adventurer(1);
    act(hub, BOB).create_adventurer(NAME, WARDEN);
    // E-19: the old owner may hold an account again.
    assert(act(hub, ALICE).register() == 2, 'old owner registers again');
}

/// ENG-01 §9.3 and §10's worst case: seven adventurers inside, each one's controller moved.
#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner_seven_inside() {
    let (hub, double) = setup();
    act(hub, ALICE).register();
    set_slots(hub, 1, 7);
    let hub_ = act(hub, ALICE);
    for _ in 0..7_u8 {
        hub_.create_adventurer(NAME, VANGUARD);
    }
    for id in 1..8_u32 {
        put_inside(hub, id);
    }
    let keys = watched();
    let before = snapshot(hub, keys.span());
    let mut controllers = array![];
    for id in 1..8_u32 {
        controllers.append(map_entry_address(selector!("controllers"), array![id.into()].span()));
    }
    let double_before = snapshot(double, controllers.span());
    start_cheat_caller_address(hub, addr(ALICE));
    let gas = get_available_gas();
    hub_.set_account_owner(1, addr(BOB));
    println!("gas set_account_owner, seven inside: {}", gas - get_available_gas());
    let after = snapshot(hub, keys.span());
    let double_after = snapshot(double, controllers.span());
    assert(changes(before.span(), after.span()) == (1, 1, 1), 'hub: 1 N / 1 O / 1 zeroed');
    // The double's first write of each is new; `Instances`' member word is overwritten (§9.3).
    assert(changes(double_before.span(), double_after.span()) == (7, 0, 0), 'seven controllers');
    let double_ = IDoubleViewsDispatcher { contract_address: double };
    for id in 1..8_u32 {
        assert(double_.controller(id) == addr(BOB), 'controller moved');
    }
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner_only_those_inside() {
    let (hub, double) = setup();
    with_adventurers(hub, ALICE, 3);
    put_inside(hub, 2);
    act(hub, ALICE).delete_adventurer(1);
    act(hub, ALICE).set_account_owner(1, addr(CAROL));
    let double_ = IDoubleViewsDispatcher { contract_address: double };
    assert(double_.controller(2) == addr(CAROL), 'inside: moved');
    assert(double_.controller(1) == addr(0), 'deleted: not listed');
    assert(double_.controller(3) == addr(0), 'in a hub: nothing');
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner_wrong_caller_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, BOB).set_account_owner(1, addr(BOB)), NOT_ACCOUNT_OWNER);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, BOB).set_account_owner(7, addr(CAROL)), NOT_ACCOUNT_OWNER);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner_to_an_account_holder_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    act(hub, BOB).register();
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).set_account_owner(1, addr(BOB)), OWNER_HAS_ACCOUNT);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).set_account_owner(1, addr(ALICE)), OWNER_HAS_ACCOUNT);
}

#[test]
#[available_gas(l2_gas: 1000000000)]
fn test_set_account_owner_to_zero_refused() {
    let (hub, _) = setup();
    with_adventurers(hub, ALICE, 1);
    #[feature("safe_dispatcher")]
    refused(try_act(hub, ALICE).set_account_owner(1, addr(0)), ZERO_OWNER);
}
