//! The store (D-143, D-147; ENG-R1a on the pattern of `quiver_quest` 0.2.0, D-167): the only
//! access to the persistent package's storage, `get_x` and `set_x` per model, and focused reads and
//! writes where a path needs less than the model.
//!
//! **`Hub`'s store is `HubStore`**, implemented on `Hub`'s contract state: a call is
//! `self.get_core(adventurer_id)` inside the contract, with nothing built and nothing looked up at
//! run time, as `quiver_quest`'s store is implemented on its component's state. Every storage
//! variable of `Hub` (ENG-01 §3.3) is read and written here, and nowhere else; `Hub`'s systems
//! hold models, never a storage path or an offset.
//!
//! **Models and stored words.** A model whose paths need all of it is read and written through
//! its `StorePacking` (the configuration, the counters, gold, items, the snapshot, the rules
//! epoch, known skills, the account list's pages when read). The hot words that a path reads a few
//! fields of, or changes one field of, are read and written as **stored models** (`StoredCore`,
//! `StoredPlace`, `StoredRecord`, `StoredBuild`): the word as stored, typed, its fields read and
//! changed by the arithmetic their models pin against the packers (ENG-04's audit F-5: "preserving
//! packed arithmetic where justified"; the measured costs are in `models::adventurer`). The
//! balance pages and the account list's insertion and swap removal change lanes of a stored page
//! the same way, here. A slot never written reads 0 as a stored word, which the views return as
//! such (`IHubViews::account`, `IHubViews::adventurer`, frozen by ENG-01).
//!
//! **Tracking** (docs/CAIRO.md §7, D-149): a tracked model implements `Tracked`, which fixes at
//! compile time the one event its `set_x` emits on every write. **No model of `Hub` is tracked**:
//! the indexer reads ENG-01's events (D-149), and none of them matches the writes of one model.
//! `AdventurerLocated` is the nearest: it follows a write of `AdventurerPlace`, but not every one
//! (creation and a move to the next instance write the place and emit nothing, D-03), so the
//! systems keep emitting it where they did, after the write. `TitleDisplayed` is emitted and never
//! stored (T-1). So every `set_x` here is the write alone, and none emits.
//!
//! **`Registry`'s storage** is ENG-R1b's: `StoreTrait` keeps its two path methods until then.

use grimworld_logic::packing::{Bitmap, Counter, LIVE, Lanes32, unpack_lanes32};
use starknet::storage::{
    Mutable, StorageAsPointer, StoragePath, StoragePathEntry, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::storage_access::{StorageBaseAddress, Store};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use crate::models::account::{AdventurerListAssert, AdventurerListTrait, StoredRecord};
use crate::models::adventurer::{
    BeltTrait, KnownSkillsTrait, StoredBuild, StoredCore, StoredPlace, WORDS,
};
use crate::models::balance::BalanceTrait;
use crate::models::item::{Equipment, EquipmentTrait, Gold};
use crate::models::rules_epoch::RulesEpoch;
use crate::models::snapshot::StoredSnapshot;
use crate::models::versions::Versions;
use crate::systems::hub::Hub::ContractState as HubState;

/// A model the indexer tracks: `Event` is what its `set_x` emits on every write, with the model's
/// keys and new values. The list of the impls of this trait is the list of tracked models (D-130):
/// empty for `Hub` (see the module's doc).
pub trait Tracked<M> {
    type Event;
    fn event(self: @M) -> Self::Event;
}

#[generate_trait]
pub impl HubStoreImpl of HubStoreTrait {
    // Configuration: one slot each (`models::rules_epoch` says why no model gathers them).
    // Untracked

    /// The constructor's writes: the administrator, the four registered contracts, the three id
    /// counters at 1 (`flatten` and the rules epoch stay 0 until `set_contracts`).
    fn initialize(
        ref self: HubState,
        admin: ContractAddress,
        registry: ContractAddress,
        instances: ContractAddress,
        market: ContractAddress,
        fate: ContractAddress,
    ) {
        self.admin.write(admin);
        self.registry.write(registry);
        self.instances.write(instances);
        self.market.write(market);
        self.fate.write(fate);
        self.next_account.write(Counter { value: 1 });
        self.next_adventurer.write(Counter { value: 1 });
        self.next_item.write(Counter { value: 1 });
    }

    #[inline(always)]
    fn get_administrator(self: @HubState) -> ContractAddress {
        self.admin.read()
    }

    #[inline(always)]
    fn set_administrator(ref self: HubState, admin: ContractAddress) {
        self.admin.write(admin)
    }

    #[inline(always)]
    fn get_registry(self: @HubState) -> ContractAddress {
        self.registry.read()
    }

    #[inline(always)]
    fn get_instances(self: @HubState) -> ContractAddress {
        self.instances.read()
    }

    /// `FlattenLibrary`'s class hash (D-168).
    #[inline(always)]
    fn get_flatten(self: @HubState) -> ClassHash {
        self.flatten.read()
    }

    /// `set_contracts`' writes, in its order.
    fn set_registered(
        ref self: HubState,
        registry: ContractAddress,
        instances: ContractAddress,
        market: ContractAddress,
        fate: ContractAddress,
        flatten: ClassHash,
    ) {
        self.registry.write(registry);
        self.instances.write(instances);
        self.market.write(market);
        self.fate.write(fate);
        self.flatten.write(flatten);
    }

    /// `Hub.rules_epoch` (D-169), one slot; 0 at deployment.
    #[inline(always)]
    fn get_rules_epoch(self: @HubState) -> RulesEpoch {
        self.rules_epoch.read()
    }

    #[inline(always)]
    fn set_rules_epoch(ref self: HubState, epoch: RulesEpoch) {
        self.rules_epoch.write(epoch)
    }

    // Id counters (`Counter`, kept with `LIVE`). Untracked

    /// A new account's id: `next_account` read, then written one more.
    #[inline(always)]
    fn new_account_id(ref self: HubState) -> u32 {
        let next = self.next_account.read().value;
        self.next_account.write(Counter { value: next + 1 });
        next.try_into().unwrap()
    }

    /// A new adventurer's id: `next_adventurer` read, then written one more.
    #[inline(always)]
    fn new_adventurer_id(ref self: HubState) -> u32 {
        let next = self.next_adventurer.read().value;
        self.next_adventurer.write(Counter { value: next + 1 });
        next.try_into().unwrap()
    }

    // Accounts: `account_of[owner]`, then `accounts[id]`, two slots (owner, record). Untracked

    /// The account `owner` holds; 0 for none.
    #[inline(always)]
    fn get_account_id(self: @HubState, owner: ContractAddress) -> u32 {
        self.account_of.entry(owner).read()
    }

    #[inline(always)]
    fn set_account_id(ref self: HubState, owner: ContractAddress, account_id: u32) {
        self.account_of.entry(owner).write(account_id)
    }

    /// The account's owner alone, one read: the ownership check needs no more.
    #[inline(always)]
    fn get_owner(self: @HubState, account_id: u32) -> ContractAddress {
        self.accounts.entry(account_id).owner.read()
    }

    #[inline(always)]
    fn set_owner(ref self: HubState, account_id: u32, owner: ContractAddress) {
        self.accounts.entry(account_id).owner.write(owner)
    }

    /// The account's owner and its record as stored, the two slots under one address: what
    /// `set_account_owner` and the view read. The record is 0 for an account never registered.
    fn get_account(self: @HubState, account_id: u32) -> (ContractAddress, StoredRecord) {
        let account = self.accounts.entry(account_id);
        let record = account.as_ptr().__storage_pointer_address__.word(1);
        (account.owner.read(), StoredRecord { word: record })
    }

    /// A new account's two slots, its owner then its record, under one address.
    fn set_account(
        ref self: HubState, account_id: u32, owner: ContractAddress, record: StoredRecord,
    ) {
        let account = self.accounts.entry(account_id);
        account.owner.write(owner);
        account.as_ptr().__storage_pointer_address__.set_word(1, record.word)
    }

    /// The account's record as stored, one read: 0 for an account never registered.
    #[inline(always)]
    fn get_account_record(self: @HubState, account_id: u32) -> StoredRecord {
        StoredRecord {
            word: self.accounts.entry(account_id).as_ptr().__storage_pointer_address__.word(1),
        }
    }

    #[inline(always)]
    fn set_account_record(ref self: HubState, account_id: u32, record: StoredRecord) {
        self
            .accounts
            .entry(account_id)
            .as_ptr()
            .__storage_pointer_address__
            .set_word(1, record.word)
    }

    // The account's list of adventurers: `account_adventurers[(account, page)]`, a `Lanes32` of
    // seven ids, its length `AccountRecord.adventurers` (`models::account`). Untracked

    /// The first `count` ids of the list, in order: each page read once. Bound: the account's
    /// adventurers, at most its slots.
    fn get_adventurer_ids(self: @HubState, account_id: u32, count: u8) -> Span<u32> {
        let mut ids: Array<u32> = array![];
        let mut page_ids = Lanes32 { lanes: [0; 7] };
        let mut i: u8 = 0;
        while i != count {
            let (page, lane) = AdventurerListTrait::at(i);
            if lane == 0 {
                page_ids = self.account_adventurers.entry((account_id, page)).read();
            }
            ids.append(page_ids.get(lane));
            i += 1;
        }
        ids.span()
    }

    /// Appends `adventurer_id` to a list of `count` ids. The list is compact, so the lanes from
    /// its length on are 0: the new id is added to lane `count % 7`, and a page's first lane is
    /// written without reading the page.
    fn add_adventurer_id(ref self: HubState, account_id: u32, count: u8, adventurer_id: u32) {
        let (page, lane) = AdventurerListTrait::at(count);
        let list = self
            .account_adventurers
            .entry((account_id, page))
            .as_ptr()
            .__storage_pointer_address__;
        let ids = if lane == 0 {
            LIVE
        } else {
            list.word(0)
        };
        list.set_word(0, ids + adventurer_id.into() * AdventurerListTrait::unit(lane))
    }

    /// Removes `adventurer_id` from a list of `count` ids by a swap: the last id moves into its
    /// lane, the last lane is cleared. The last page is read first; the scan for the adventurer
    /// reads each earlier page once, and writes the page of the hole (when not the last) before
    /// the last page. Refused if the scan reaches the last id without meeting it (ENG-04's audit
    /// F-6: `AdventurerListAssert`). Bound: the account's adventurers.
    fn remove_adventurer_id(ref self: HubState, account_id: u32, count: u8, adventurer_id: u32) {
        let last = count - 1;
        let (last_page, last_lane) = AdventurerListTrait::at(last);
        let last_list = self
            .account_adventurers
            .entry((account_id, last_page))
            .as_ptr()
            .__storage_pointer_address__;
        let last_word = last_list.word(0);
        let last_ids = unpack_lanes32(last_word);
        let last_id = last_ids.get(last_lane);
        let mut last_new = last_word - last_id.into() * AdventurerListTrait::unit(last_lane);
        if last_id != adventurer_id {
            let moved: felt252 = last_id.into() - adventurer_id.into();
            let mut i: u8 = 0;
            let mut ids = last_ids;
            let mut list = last_list;
            let mut list_word = last_word;
            loop {
                AdventurerListAssert::assert_listed(i, last);
                let (page, lane) = AdventurerListTrait::at(i);
                if lane == 0 && page != last_page {
                    list = self
                        .account_adventurers
                        .entry((account_id, page))
                        .as_ptr()
                        .__storage_pointer_address__;
                    list_word = list.word(0);
                    ids = unpack_lanes32(list_word);
                } else if lane == 0 {
                    ids = last_ids;
                }
                if ids.get(lane) == adventurer_id {
                    let delta = moved * AdventurerListTrait::unit(lane);
                    if page == last_page {
                        last_new += delta;
                    } else {
                        list.set_word(0, list_word + delta);
                    }
                    break;
                }
                i += 1;
            }
        }
        last_list.set_word(0, last_new)
    }

    // Adventurers: `adventurers[id]`, six slots (core, place, build, belt, equipped, name).
    // Untracked (`AdventurerLocated` stays the systems', see the module's doc)

    /// Writes the six slots of a new adventurer (`AdventurerTrait::new`), in their order.
    fn set_adventurer(
        ref self: HubState,
        adventurer_id: u32,
        core: StoredCore,
        place: StoredPlace,
        build: StoredBuild,
        name: felt252,
    ) {
        let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
        base.set_word(CORE, core.word);
        base.set_word(PLACE, place.word);
        base.set_word(BUILD, build.build);
        base.set_word(BELT, build.belt);
        base.set_word(EQUIPPED, build.equipped);
        base.set_word(NAME, name);
    }

    /// The six words as stored, for the view that returns them so (`IHubViews::adventurer`,
    /// ENG-01): six 0 for an id never created.
    fn get_adventurer_words(self: @HubState, adventurer_id: u32) -> Span<felt252> {
        let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
        let mut words: Array<felt252> = array![];
        for offset in 0..WORDS {
            words.append(base.word(offset));
        }
        words.span()
    }

    /// The core and the place as stored, under one address: the two words of the ownership check
    /// (`Hub`'s `owned_in_hub`), which every entrypoint naming an adventurer reads.
    fn get_core_place(self: @HubState, adventurer_id: u32) -> (StoredCore, StoredPlace) {
        let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
        (StoredCore { word: base.word(CORE) }, StoredPlace { word: base.word(PLACE) })
    }

    /// The core as stored, one read.
    #[inline(always)]
    fn get_core(self: @HubState, adventurer_id: u32) -> StoredCore {
        StoredCore { word: self.adventurer_word(adventurer_id, CORE) }
    }

    #[inline(always)]
    fn set_core(ref self: HubState, adventurer_id: u32, core: StoredCore) {
        self.set_adventurer_word(adventurer_id, CORE, core.word)
    }

    /// The place as stored, one read.
    #[inline(always)]
    fn get_place(self: @HubState, adventurer_id: u32) -> StoredPlace {
        StoredPlace { word: self.adventurer_word(adventurer_id, PLACE) }
    }

    #[inline(always)]
    fn set_place(ref self: HubState, adventurer_id: u32, place: StoredPlace) {
        self.set_adventurer_word(adventurer_id, PLACE, place.word)
    }

    /// The belt's `(items, counts)`, one read: the four items and their counts of the seven lanes.
    #[inline(always)]
    fn get_belt(self: @HubState, adventurer_id: u32) -> ([u32; 4], [u8; 4]) {
        BeltTrait::read(self.adventurer_word(adventurer_id, BELT))
    }

    /// Whether it wears anything: `equipped` holds an entity (a word other than 0 or `LIVE`).
    #[inline(always)]
    fn wears_equipment(self: @HubState, adventurer_id: u32) -> bool {
        !WordTrait::is_empty(self.adventurer_word(adventurer_id, EQUIPPED))
    }

    /// The build in design/03's sense, `set_build`'s three slots: the bar and the attributes, the
    /// belt, the equipment, the words as sent with `LIVE`.
    fn set_adventurer_build(ref self: HubState, adventurer_id: u32, build: StoredBuild) {
        let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
        base.set_word(BUILD, build.build);
        base.set_word(BELT, build.belt);
        base.set_word(EQUIPPED, build.equipped);
    }

    // Known skills: `known_skills[(adventurer, page)]`, a `Bitmap` of 250 skill ids. Untracked

    #[inline(always)]
    fn get_known_skills(self: @HubState, adventurer_id: u32, page: u8) -> Bitmap {
        self.known_skills.entry((adventurer_id, page)).read()
    }

    /// Whether the adventurer knows each skill of `bar` that is not empty, in slot order:
    /// each `known_skills` page read once while consecutive skills share it. Bound: 8 slots.
    fn knows_skills(self: @HubState, adventurer_id: u32, bar: Span<u16>) -> Array<bool> {
        let mut known: Array<bool> = array![];
        let (mut page, mut bits) = (0_u8, Bitmap { bits: 0 });
        let mut read = false;
        for skill in bar {
            let skill = *skill;
            if skill == 0 {
                continue;
            }
            let (at, bit) = KnownSkillsTrait::at(skill);
            if !read || at != page {
                page = at;
                bits = self.get_known_skills(adventurer_id, page);
                read = true;
            }
            known.append(KnownSkillsTrait::knows(@bits, bit));
        }
        known
    }

    // Balances: `balances[(owner key, page)]`, a `Lanes32` of seven `u32`. Untracked

    /// The balance of `item` held by `owner`: one lane of one page, read as its stored word
    /// (`BalanceTrait::amount`), the six other lanes not decoded.
    fn get_balance(self: @HubState, owner: felt252, item: u32) -> u32 {
        let (page, lane) = BalanceTrait::at(item);
        let word = self.balances.entry((owner, page)).as_ptr().__storage_pointer_address__.word(0);
        BalanceTrait::amount(word, lane)
    }

    /// Credits (`credit`) or debits the balances of `owner` by `(item, amount)` changes, each page
    /// read once and written once, however many changes it holds (at most 12: a belt of 4 and 8
    /// balances, ENG-01 §4.5), in the order of each page's first change; the pages as stored words
    /// changed by `BalanceTrait`'s arithmetic. Returns `(lanes filled, lanes emptied)` for
    /// `core.pack_lanes`. Refuses a debit the owner cannot pay.
    fn change_balances(
        ref self: HubState, owner: felt252, changes: Span<(u32, u32)>, credit: bool,
    ) -> (u16, u16) {
        let (mut filled, mut emptied) = (0_u16, 0_u16);
        let count = changes.len();
        for i in 0..count {
            let (item, _) = *changes[i];
            let (page, _) = BalanceTrait::at(item);
            let mut first = true;
            for j in 0..i {
                let (earlier, _) = *changes[j];
                let (earlier_page, _) = BalanceTrait::at(earlier);
                if earlier_page == page {
                    first = false;
                }
            }
            if !first {
                continue;
            }
            let entry = self.balances.entry((owner, page)).as_ptr().__storage_pointer_address__;
            let mut word = entry.word(0);
            for j in i..count {
                let (other, amount) = *changes[j];
                let (other_page, lane) = BalanceTrait::at(other);
                if other_page != page {
                    continue;
                }
                if credit {
                    let (next, lane_filled) = BalanceTrait::credit(word, lane, amount);
                    word = next;
                    if lane_filled {
                        filled += 1;
                    }
                } else {
                    let (next, lane_emptied) = BalanceTrait::debit(word, lane, amount);
                    word = next;
                    if lane_emptied {
                        emptied += 1;
                    }
                }
            }
            entry.set_word(0, word);
        }
        (filled, emptied)
    }

    // Gold: `gold[owner key]`. Untracked

    #[inline(always)]
    fn get_gold(self: @HubState, owner: felt252) -> Gold {
        self.gold.entry(owner).read()
    }

    #[inline(always)]
    fn set_gold(ref self: HubState, owner: felt252, gold: Gold) {
        self.gold.entry(owner).write(gold)
    }

    // Equipment: `items[entity]`, two slots (base, mods); `packs[(adventurer, page)]`, a
    // `Lanes32` of entities. Untracked

    /// Whether its pack holds equipment: page 0 of the compact list holds an entity (a word other
    /// than 0 or `LIVE`).
    #[inline(always)]
    fn holds_equipment(self: @HubState, adventurer_id: u32) -> bool {
        let page = self.packs.entry((adventurer_id, 0)).as_ptr().__storage_pointer_address__;
        !WordTrait::is_empty(page.word(0))
    }

    /// The items worn, `entities` being `equipped`'s lanes: each non-empty lane's item read (two
    /// slots) and added to the equipment in lane order. Bound: 7 lanes.
    fn get_equipment(self: @HubState, entities: Span<u32>) -> Equipment {
        let mut equipment = EquipmentTrait::new();
        for lane in 0..7_u32 {
            let entity = *entities[lane];
            if entity != 0 {
                equipment.add(lane, self.items.entry(entity).read());
            }
        }
        equipment
    }

    // The snapshot `set_build` flattened: `snapshots[adventurer]`, three slots (D-168). Untracked

    /// A slot never written reads 0 (`StoredSnapshotAssert::assert_fresh`).
    #[inline(always)]
    fn get_snapshot(self: @HubState, adventurer_id: u32) -> StoredSnapshot {
        self.snapshots.entry(adventurer_id).read()
    }

    #[inline(always)]
    fn set_snapshot(ref self: HubState, adventurer_id: u32, snapshot: StoredSnapshot) {
        self.snapshots.entry(adventurer_id).write(snapshot)
    }
}

#[generate_trait]
pub impl StoreImpl of StoreTrait {
    /// `Registry.versions`, one slot: the content and inputs versions; 0 at deployment. Read by
    /// `bundle`, `content_version` and `set_record`.
    #[inline(always)]
    fn get_versions(path: StoragePath<Versions>) -> Versions {
        path.read()
    }

    /// Writes `Registry.versions` (`set_record`, a changed record). Untracked: no event.
    #[inline(always)]
    fn set_versions(path: StoragePath<Mutable<Versions>>, versions: Versions) {
        path.write(versions)
    }
}

/// Offsets of the words of `Adventurer` from its address.
const CORE: u8 = 0;
const PLACE: u8 = 1;
const BUILD: u8 = 2;
const BELT: u8 = 3;
const EQUIPPED: u8 = 4;
const NAME: u8 = 5;

/// One word of an adventurer, as stored.
#[generate_trait]
impl AdventurerWordImpl of AdventurerWordTrait {
    #[inline(always)]
    fn adventurer_word(self: @HubState, adventurer_id: u32, offset: u8) -> felt252 {
        self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__.word(offset)
    }

    #[inline(always)]
    fn set_adventurer_word(ref self: HubState, adventurer_id: u32, offset: u8, value: felt252) {
        self
            .adventurers
            .entry(adventurer_id)
            .as_ptr()
            .__storage_pointer_address__
            .set_word(offset, value)
    }
}

/// One stored word of a record, read or written as stored, without unpacking (see the module's
/// doc).
#[generate_trait]
impl WordImpl of WordTrait {
    /// A word whose fields are all 0: never written (0), or `LIVE` alone.
    #[inline(always)]
    fn is_empty(word: felt252) -> bool {
        word == 0 || word == LIVE
    }

    /// Word `offset` of the record at `self`.
    #[inline(always)]
    fn word(self: StorageBaseAddress, offset: u8) -> felt252 {
        Store::<felt252>::read_at_offset(0, self, offset).unwrap_syscall()
    }

    #[inline(always)]
    fn set_word(self: StorageBaseAddress, offset: u8, value: felt252) {
        Store::<felt252>::write_at_offset(0, self, offset, value).unwrap_syscall()
    }
}

/// The storage layout of `Hub` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address. Here since ENG-R1a: the store is what reads and
/// writes them.
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use crate::systems::hub::Hub;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    // gas: raised, CBT-02e: the layout checks the snapshots' and flatten's addresses
    #[available_gas(l2_gas: 285758)] // ceil(1.05 × 272150 measured)
    fn test_hub_storage_addresses() {
        let state = @Hub::contract_state_for_testing();
        assert(
            address_of(
                state
                    .account_of
                    .entry(0x123_felt252.try_into().unwrap())
                    .as_ptr()
                    .__storage_pointer_address__,
            ) == map_entry_address(selector!("account_of"), array![0x123].span()),
            'account_of',
        );
        assert(
            address_of(
                state.accounts.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("accounts"), array![7].span()),
            'accounts',
        );
        assert(
            address_of(
                state.account_adventurers.entry((7, 1)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("account_adventurers"), array![7, 1].span()),
            'account_adventurers',
        );
        assert(
            address_of(
                state.adventurers.entry(9).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("adventurers"), array![9].span()),
            'adventurers',
        );
        assert(
            address_of(
                state.known_skills.entry((9, 0)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("known_skills"), array![9, 0].span()),
            'known_skills',
        );
        assert(
            address_of(
                state.counters.entry((9, 4)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("counters"), array![9, 4].span()),
            'counters',
        );
        assert(
            address_of(
                state.account_counters.entry((7, 4)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("account_counters"), array![7, 4].span()),
            'account_counters',
        );
        assert(
            address_of(
                state.grimoires.entry((9, 1)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("grimoires"), array![9, 1].span()),
            'grimoires',
        );
        assert(
            address_of(
                state.balances.entry((0x100000009, 3)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("balances"), array![0x100000009, 3].span()),
            'balances',
        );
        assert(
            address_of(
                state.gold.entry(0x200000007).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("gold"), array![0x200000007].span()),
            'gold',
        );
        assert(
            address_of(
                state.items.entry(55).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("items"), array![55].span()),
            'items',
        );
        assert(
            address_of(
                state.packs.entry((9, 2)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("packs"), array![9, 2].span()),
            'packs',
        );
        assert(
            address_of(
                state.vaults.entry((7, 3)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("vaults"), array![7, 3].span()),
            'vaults',
        );
        assert(
            address_of(
                state.rift_boards.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("rift_boards"), array![7].span()),
            'rift_boards',
        );
        assert(
            address_of(
                state.snapshots.entry(9).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("snapshots"), array![9].span()),
            'snapshots',
        );
        assert(
            address_of(state.flatten.as_ptr().__storage_pointer_address__) == selector!("flatten"),
            'flatten',
        );
        assert(
            address_of(
                state.rules_epoch.as_ptr().__storage_pointer_address__,
            ) == selector!("rules_epoch"),
            'rules_epoch',
        );
    }
}

/// The store's methods across several slots, on `Hub`'s state: the account list's insertion and
/// swap removal, the balance pages, the words the views return as stored.
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::LIVE;
    use crate::models::account::StoredRecordTrait;
    use crate::models::adventurer::AdventurerTrait;
    use crate::systems::hub::Hub;
    use super::HubStoreTrait;

    fn ids(state: @Hub::ContractState, count: u8) -> Array<u32> {
        let mut out = array![];
        for id in state.get_adventurer_ids(1, count) {
            out.append(*id);
        }
        out
    }

    // Nine ids on two pages; removals of a hole on the first page, of the last id, of a hole on
    // the final page.
    #[test]
    #[available_gas(l2_gas: 3068762)] // ceil(1.05 × 2922630 measured)
    fn test_list_insert_and_swap_removal() {
        let mut state = Hub::contract_state_for_testing();
        for i in 0..9_u8 {
            state.add_adventurer_id(1, i, 11 + i.into());
        }
        assert(ids(@state, 9) == array![11, 12, 13, 14, 15, 16, 17, 18, 19], 'appended');
        state.remove_adventurer_id(1, 9, 12);
        assert(ids(@state, 8) == array![11, 19, 13, 14, 15, 16, 17, 18], 'hole on page 0');
        state.remove_adventurer_id(1, 8, 18);
        assert(ids(@state, 7) == array![11, 19, 13, 14, 15, 16, 17], 'the last');
        state.remove_adventurer_id(1, 7, 13);
        assert(ids(@state, 6) == array![11, 19, 17, 14, 15, 16], 'hole on the final page');
        // The cleared lanes are 0, and the emptied page keeps `LIVE`.
        assert(ids(@state, 7) == array![11, 19, 17, 14, 15, 16, 0], 'cleared lane');
        state.add_adventurer_id(1, 6, 20);
        assert(ids(@state, 7) == array![11, 19, 17, 14, 15, 16, 20], 'appended again');
    }

    #[test]
    #[should_panic(expected: 'not in the account list')]
    #[available_gas(l2_gas: 701831)] // ceil(1.05 × 668410 measured)
    fn test_remove_not_listed_refused() {
        let mut state = Hub::contract_state_for_testing();
        state.add_adventurer_id(1, 0, 11);
        state.add_adventurer_id(1, 1, 12);
        state.remove_adventurer_id(1, 2, 99);
    }

    // A page read once and written once whatever its changes; lanes filled and emptied counted.
    #[test]
    #[available_gas(l2_gas: 2143523)] // ceil(1.05 × 2041450 measured)
    fn test_change_balances() {
        let mut state = Hub::contract_state_for_testing();
        let owner = 0x100000005;
        let (filled, emptied) = state
            .change_balances(owner, array![(1, 3), (8, 2), (1, 4), (15, 0)].span(), true);
        assert((filled, emptied) == (2, 0), 'filled');
        assert(state.get_balance(owner, 1) == 7, 'item 1');
        assert(state.get_balance(owner, 8) == 2, 'item 8');
        assert(state.get_balance(owner, 15) == 0, 'item 15');
        let (filled, emptied) = state.change_balances(owner, array![(1, 7), (8, 1)].span(), false);
        assert((filled, emptied) == (0, 1), 'emptied');
        assert(state.get_balance(owner, 1) == 0 && state.get_balance(owner, 8) == 1, 'debited');
    }

    #[test]
    #[should_panic(expected: 'balance: not enough')]
    #[available_gas(l2_gas: 98280)] // ceil(1.05 × 93600 measured)
    fn test_change_balances_refused() {
        let mut state = Hub::contract_state_for_testing();
        state.change_balances(0x100000005, array![(1, 1)].span(), false);
    }

    // The views' words as stored: 0 where nothing was written, the stored models otherwise.
    #[test]
    #[available_gas(l2_gas: 3814020)] // ceil(1.05 × 3632400 measured)
    fn test_words_as_stored() {
        let mut state = Hub::contract_state_for_testing();
        assert(state.get_adventurer_words(5) == array![0, 0, 0, 0, 0, 0].span(), 'never created');
        assert(state.get_account_record(3).word == 0, 'never registered');
        let (core, place, build) = AdventurerTrait::new(3, 1, 2);
        state.set_adventurer(5, core, place, build, 'Brenna');
        let words = array![core.word, place.word, build.build, LIVE, LIVE, 'Brenna'];
        assert(state.get_adventurer_words(5) == words.span(), 'six words');
        assert(state.get_core(5) == core && state.get_place(5) == place, 'core, place');
        assert(!state.wears_equipment(5) && !state.holds_equipment(5), 'nothing');
        state.set_account_record(3, StoredRecordTrait::new());
        assert(state.get_account_record(3) == StoredRecordTrait::new(), 'record');
    }
}
