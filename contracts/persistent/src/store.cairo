//! The store (D-143, D-147; ENG-R1a on the pattern of `quiver_quest` 0.2.0, D-167): the only
//! access to the persistent package's storage, `get_x` and `set_x` per model, and focused reads and
//! writes where a path needs less than the model.
//!
//! **`Hub`'s store is `HubStoreTrait`**, implemented on `Hub`'s contract state: a call is
//! `self.get_core(adventurer_id)` inside the contract, with nothing built and nothing looked up at
//! run time, as `quiver_quest`'s store is implemented on its component's state. Every storage
//! variable of `Hub` (ENG-01 §3.3) is read and written here, and nowhere else; `Hub`'s systems
//! hold models, never a storage path or an offset.
//!
//! **Models and stored words.** A model whose paths need all of it is read and written through
//! its `StorePacking` (the configuration, the counters, gold, items, the snapshot, the rules
//! epoch, known skills). The account list's pages are `StoredLanes` (below), read whole then
//! `.decoded()` for the list, changed a lane at a time on write. The hot words that a path reads a
//! few fields of, or changes one field of, are read and written as **stored models**, one file each
//! (`models::stored_core`, `stored_place`, `stored_record`, `stored_build`): the word as stored,
//! typed, its fields read and changed by the arithmetic the stored model pins against the model's
//! packer (ENG-04's audit F-5: "preserving packed arithmetic where justified"; each file's doc
//! gives the packer's measured cost). The pages of `Lanes32` changed or checked a lane at a time
//! (the account list on write, the balances, the pack's equipment page, what an adventurer wears,
//! its belt) are read and written as `StoredLanes` (`models::lanes`). The store holds no word
//! arithmetic, only reads, writes, their order and loop bookkeeping. A slot never written reads 0
//! as a stored word, which the views return as such (`IHubViews::account`, `IHubViews::adventurer`,
//! frozen by ENG-01).
//!
//! **Typed slots, where they hold the rule** (ENG-R1a's note 4, measured in ENG-R1b after
//! `Instances`' storage passed the rule). `Hub` declares `accounts` as `StoredAccount` (the owner,
//! the record as stored), `account_adventurers` and `packs` as `StoredLanes`, each a one-felt
//! `Store` (an identity `StorePacking`) at the address and in the layout the models had
//! (`layout_tests`, `test_account_slots`): their store methods do no address arithmetic, and a path
//! that reads or writes two slots of one account takes its sub-pointers once. **`adventurers` and
//! `balances` keep their models' declaration and the offset access** (`AdventurerWordTrait`,
//! `PageTrait`, `WordTrait` below): typed, they raised the expedition's path (ENG-R1b, l2 gas per
//! call: `enter` +300 without a belt and +3,940 with 4 belt pages, the closing `report` crediting 4
//! pages +3,940, `travel` +200; a balance page about +985, a single adventurer slot about +100),
//! which D-144 leaves to the project manager; the rule of ENG-R1b's *Scope* keeps them as they
//! were.
//!
//! **Tracking** (docs/CAIRO.md §7, D-147, D-149): **no model of `Hub` is tracked, so no `set_x`
//! here emits**. The indexer reads ENG-01's events, frozen (D-149), and none of them matches the
//! writes of one model: `AdventurerLocated` is the nearest, but it follows only some writes of
//! `AdventurerPlace` (creation and a move to the next instance write the place and emit nothing,
//! D-03), so the systems keep emitting it where they did, after the write; `TitleDisplayed` is
//! emitted and never stored (T-1). The lot that tracks a model adds quiver's mechanism
//! (`quiver_quest` 0.2.0's store): a trait `Tracked<M> { type Event; fn event(self: @M) -> Event }`
//! implemented by the tracked model alone, a consumer's constant per tracked model, and in that
//! model's `set_x` the write followed by `if Tracking::X { self.emit(Tracked::event(@x)) }`, with
//! a test per tracked model that its write emits and per untracked model that it does not. No
//! such trait is declared here until a model implements it: an empty one would record nothing a
//! build or a test could check.
//!
//! **Layers**: the store is implemented on `Hub`'s state, so it depends on `systems::hub`, which
//! depends on it, as `quiver_quest`'s store on its component's state; it serves `Hub` alone. The
//! test of `Hub`'s storage addresses (`layout_tests`) is here because the store is what reads and
//! writes them.
//!
//! **`Market`'s store is `MarketStoreTrait`**, on `Market`'s state the same way: only the
//! constructor writes `Market`'s storage until the lot that writes its entrypoints, so it holds
//! that path alone (ENG-R1b: no store method for a path no code takes). **No model of `Market` is
//! tracked**: its events (`LotPosted`, `LotClosed`, `TradeOpened`, `TradeClosed`) are emitted by no
//! code yet, and the lot that writes its entrypoints decides under D-149 (ENG-R1b, open question
//! 4).
//!
//! **`Registry`'s store is `RegistryStoreTrait`** (ENG-R1b, part 2), on `Registry`'s state the same
//! way: the administrator, the versions, `last_ids`, `caste_skills`, and a record's parts. Its
//! storage was already declared typed (`records` one felt a part, `last_ids` a `Counter`,
//! `versions` a `Versions`, `caste_skills` a `u32`), so no slot of it is at an offset and note 4
//! changes nothing there. **A record's parts are read and written at pre-hashed addresses**
//! (`PartsTrait`, below), not through the map: the record's two links are hashed once and each part
//! adds one, a measured saving (ENG-01 §3.5: `bundle` of 32 three-part records 4,045,220 →
//! 3,477,020), tested against the map's own addresses (`test_part_address_is_the_maps`). **No model
//! of `Registry` is tracked**: it emits no event (ENG-01 §5 has none for it). Its content's checks
//! (`RegistryAssert::assert_content`) still read `records` and `caste_skills` themselves: they are
//! ENG-05's and CBT-05b's while those lots add checks there, and move with `RegistryAssert`
//! (ENG-R1b, open question 2).

use core::pedersen::pedersen;
use grimworld_logic::packing::{Bitmap, Counter, Lanes32};
use starknet::storage::{
    StorageAsPointer, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    SubPointersForward, SubPointersMutForward,
};
use starknet::storage_access::{
    StorageAddress, StorageBaseAddress, Store, storage_address_from_base,
    storage_base_address_from_felt252,
};
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use crate::models::account::{AdventurerListAssert, AdventurerListTrait};
use crate::models::adventurer::{KnownSkillsTrait, WORDS};
use crate::models::balance::BalanceTrait;
use crate::models::item::{Equipment, EquipmentTrait, Gold};
use crate::models::lanes::{LanesTrait, StoredLanes, StoredLanesTrait};
use crate::models::rules_epoch::RulesEpoch;
use crate::models::snapshot::StoredSnapshot;
use crate::models::stored_build::StoredBuild;
use crate::models::stored_core::StoredCore;
use crate::models::stored_place::StoredPlace;
use crate::models::stored_record::StoredRecord;
use crate::models::versions::Versions;
use crate::systems::hub::Hub::ContractState as HubState;
use crate::systems::market::Market::ContractState as MarketState;
use crate::systems::registry::Registry::ContractState as RegistryState;

#[generate_trait]
pub impl HubStoreImpl of HubStoreTrait {
    // Configuration: one slot each (`models::rules_epoch` says why no model gathers them).
    //

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

    // Id counters (`Counter`, kept with `LIVE`)

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

    // Accounts: `account_of[owner]`, then `accounts[id]`, two slots (owner, record)

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
        let slots = self.accounts.entry(account_id).sub_pointers();
        (slots.owner.read(), slots.record.read())
    }

    /// A new account's two slots, its owner then its record, under one address.
    fn set_account(
        ref self: HubState, account_id: u32, owner: ContractAddress, record: StoredRecord,
    ) {
        let slots = self.accounts.entry(account_id).sub_pointers_mut();
        slots.owner.write(owner);
        slots.record.write(record)
    }

    /// The account's record as stored, one read: 0 for an account never registered.
    #[inline(always)]
    fn get_account_record(self: @HubState, account_id: u32) -> StoredRecord {
        self.accounts.entry(account_id).record.read()
    }

    #[inline(always)]
    fn set_account_record(ref self: HubState, account_id: u32, record: StoredRecord) {
        self.accounts.entry(account_id).record.write(record)
    }

    // The account's list of adventurers: `account_adventurers[(account, page)]`, a `Lanes32` of
    // seven ids, its length `AccountRecord.adventurers` (`models::account`)

    /// The first `count` ids of the list, in order: each page read once. Bound: the account's
    /// adventurers, at most its slots.
    fn get_adventurer_ids(self: @HubState, account_id: u32, count: u8) -> Span<u32> {
        let mut ids: Array<u32> = array![];
        let mut page_ids = Lanes32 { lanes: [0; 7] };
        let mut i: u8 = 0;
        while i != count {
            let (page, lane) = AdventurerListTrait::at(i);
            if lane == 0 {
                page_ids = self.account_adventurers.entry((account_id, page)).read().decoded();
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
        let entry = self.account_adventurers.entry((account_id, page));
        let ids = if lane == 0 {
            StoredLanesTrait::new()
        } else {
            entry.read()
        };
        entry.write(ids.added(lane, adventurer_id))
    }

    /// Removes `adventurer_id` from a list of `count` ids by a swap: the last id moves into its
    /// lane, the last lane is cleared. The last page is read first; the scan for the adventurer
    /// reads each earlier page once, and writes the page of the hole (when not the last) before
    /// the last page. Refused if the scan reaches the last id without meeting it (ENG-04's audit
    /// F-6: `AdventurerListAssert`). Bound: the account's adventurers.
    fn remove_adventurer_id(ref self: HubState, account_id: u32, count: u8, adventurer_id: u32) {
        let last = count - 1;
        let (last_page, last_lane) = AdventurerListTrait::at(last);
        let last_entry = self.account_adventurers.entry((account_id, last_page));
        let last_stored = last_entry.read();
        let last_ids = last_stored.decoded();
        let last_id = last_ids.get(last_lane);
        let mut last_new = last_stored.removed(last_lane, last_id);
        if last_id != adventurer_id {
            let mut i: u8 = 0;
            let mut ids = last_ids;
            let mut entry = last_entry;
            let mut stored = last_stored;
            loop {
                AdventurerListAssert::assert_listed(i, last);
                let (page, lane) = AdventurerListTrait::at(i);
                if lane == 0 && page != last_page {
                    entry = self.account_adventurers.entry((account_id, page));
                    stored = entry.read();
                    ids = stored.decoded();
                } else if lane == 0 {
                    ids = last_ids;
                }
                if ids.get(lane) == adventurer_id {
                    if page == last_page {
                        last_new = last_new.replaced(lane, adventurer_id, last_id);
                    } else {
                        entry.write(stored.replaced(lane, adventurer_id, last_id));
                    }
                    break;
                }
                i += 1;
            }
        }
        last_entry.write(last_new)
    }

    // Adventurers: `adventurers[id]`, six slots (core, place, build, belt, equipped, name).
    //

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
        base.set_word(BELT, build.belt.word);
        base.set_word(EQUIPPED, build.equipped.word);
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

    /// The belt as stored, one read (`BeltTrait::read` decodes its items and counts).
    #[inline(always)]
    fn get_belt(self: @HubState, adventurer_id: u32) -> StoredLanes {
        StoredLanes { word: self.adventurer_word(adventurer_id, BELT) }
    }

    /// What it wears as stored, one read.
    #[inline(always)]
    fn get_equipped(self: @HubState, adventurer_id: u32) -> StoredLanes {
        StoredLanes { word: self.adventurer_word(adventurer_id, EQUIPPED) }
    }

    /// The build in design/03's sense, `set_build`'s three slots: the bar and the attributes, the
    /// belt, the equipment, the words as sent with `LIVE`.
    fn set_adventurer_build(ref self: HubState, adventurer_id: u32, build: StoredBuild) {
        let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
        base.set_word(BUILD, build.build);
        base.set_word(BELT, build.belt.word);
        base.set_word(EQUIPPED, build.equipped.word);
    }

    // Known skills: `known_skills[(adventurer, page)]`, a `Bitmap` of 250 skill ids

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

    // Balances: `balances[(owner key, page)]`, a `Lanes32` of seven `u32`

    /// The balance of `item` held by `owner`: one lane of its page as stored, the six other lanes
    /// not decoded.
    fn get_balance(self: @HubState, owner: felt252, item: u32) -> u32 {
        let (page, lane) = BalanceTrait::at(item);
        StoredLanes { word: self.balance_page(owner, page).word(0) }.get(lane)
    }

    /// Credits (`credit`) or debits the balances of `owner` by `(item, amount)` changes: each page
    /// read once, changed by all its changes (`BalanceTrait::apply`) and written once, in the order
    /// of each page's first change (at most 12 changes: a belt of 4 and 8 balances, ENG-01 §4.5).
    /// Returns `(lanes filled, lanes emptied)` for `core.pack_lanes`. Refuses a debit the owner
    /// cannot pay.
    fn change_balances(
        ref self: HubState, owner: felt252, changes: Span<(u32, u32)>, credit: bool,
    ) -> (u16, u16) {
        let (mut filled, mut emptied) = (0_u16, 0_u16);
        for i in 0..changes.len() {
            if !BalanceTrait::first_on_page(changes, i) {
                continue;
            }
            let (item, _) = *changes[i];
            let (page, _) = BalanceTrait::at(item);
            let entry = self.balance_page(owner, page);
            let (stored, page_filled, page_emptied) = BalanceTrait::apply(
                StoredLanes { word: entry.word(0) }, page, changes, i, credit,
            );
            entry.set_word(0, stored.word);
            filled += page_filled;
            emptied += page_emptied;
        }
        (filled, emptied)
    }

    // Gold: `gold[owner key]`

    #[inline(always)]
    fn get_gold(self: @HubState, owner: felt252) -> Gold {
        self.gold.entry(owner).read()
    }

    #[inline(always)]
    fn set_gold(ref self: HubState, owner: felt252, gold: Gold) {
        self.gold.entry(owner).write(gold)
    }

    // Equipment: `items[entity]`, two slots (base, mods); `packs[(adventurer, page)]`, a
    // `Lanes32` of entities

    /// Page `page` of the equipment in its pack as stored, one read.
    #[inline(always)]
    fn get_pack_page(self: @HubState, adventurer_id: u32, page: u8) -> StoredLanes {
        self.packs.entry((adventurer_id, page)).read()
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

    // The snapshot `set_build` flattened: `snapshots[adventurer]`, three slots (D-168)

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
pub impl MarketStoreImpl of MarketStoreTrait {
    /// The constructor's writes: the administrator, the hub, the registry, and the three counters
    /// at their `LIVE` zero, so that the first posting and the first trade overwrite.
    fn initialize(
        ref self: MarketState,
        admin: ContractAddress,
        hub: ContractAddress,
        registry: ContractAddress,
    ) {
        self.admin.write(admin);
        self.hub.write(hub);
        self.registry.write(registry);
        self.lot_count.write(Counter { value: 0 });
        self.open_lot_count.write(Counter { value: 0 });
        self.trade_count.write(Counter { value: 0 });
    }
}

#[generate_trait]
pub impl RegistryStoreImpl of RegistryStoreTrait {
    // Configuration: the administrator, one slot

    #[inline(always)]
    fn get_administrator(self: @RegistryState) -> ContractAddress {
        self.admin.read()
    }

    /// The constructor's write, and `set_admin`'s.
    #[inline(always)]
    fn set_administrator(ref self: RegistryState, admin: ContractAddress) {
        self.admin.write(admin)
    }

    // Versions: `versions`, one slot, the content and inputs versions; 0 at deployment

    /// Read by `bundle`, `content_version` and `set_record`.
    #[inline(always)]
    fn get_versions(self: @RegistryState) -> Versions {
        self.versions.read()
    }

    /// Written by `set_record`, a changed record.
    #[inline(always)]
    fn set_versions(ref self: RegistryState, versions: Versions) {
        self.versions.write(versions)
    }

    // Allocation: `last_ids[kind]`, a `Counter`

    /// The highest id of a sequential kind; 0 for a composite kind or a kind never written.
    #[inline(always)]
    fn get_last_id(self: @RegistryState, kind: u8) -> u64 {
        self.last_ids.entry(kind).read().value
    }

    #[inline(always)]
    fn set_last_id(ref self: RegistryState, kind: u8, id: u64) {
        self.last_ids.entry(kind).write(Counter { value: id })
    }

    // `caste_skills[skill]`: how many `CASTE` records name the skill

    #[inline(always)]
    fn get_caste_count(self: @RegistryState, skill: u32) -> u32 {
        self.caste_skills.entry(skill).read()
    }

    #[inline(always)]
    fn set_caste_count(ref self: RegistryState, skill: u32, count: u32) {
        self.caste_skills.entry(skill).write(count)
    }

    // `zone_checks`: the class of an authored zone's checks (`ZoneChecks`, ENG-09), one slot

    /// Read by `set_record` for the records an authored zone's checks concern.
    #[inline(always)]
    fn get_zone_class(self: @RegistryState) -> ClassHash {
        self.zone_checks.read()
    }

    /// Written by `set_zone_checks`.
    #[inline(always)]
    fn set_zone_class(ref self: RegistryState, class_hash: ClassHash) {
        self.zone_checks.write(class_hash)
    }

    // `heart_packs[template]`: how many Heart quotas of authored zones name the template (R-27),
    // written by `ZoneChecks` in `Registry`'s context


    #[inline(always)]
    fn get_heart_count(self: @RegistryState, template: u32) -> u32 {
        self.heart_packs.entry(template).read()
    }

    // Records: `records[(kind, id, part)]`, one felt a part, `parts(kind)` parts

    /// Whether the record exists: its part 0 is not 0 (ENG-01 §3.5), one read.
    #[inline(always)]
    fn has_record(self: @RegistryState, kind: u8, id: u32) -> bool {
        self.records.entry((kind, id, 0)).read() != 0
    }

    /// Appends the `count` parts of `(kind, id)` to `out`; zeros for a record never written.
    #[inline(always)]
    fn read_record_into(
        self: @RegistryState, kind: u8, id: u32, count: u8, ref out: Array<felt252>,
    ) {
        let key = PartsTrait::key(kind, id);
        for part in 0..count {
            out.append(PartsTrait::read(PartsTrait::address(key, part)));
        }
    }

    /// A new id's parts: none of its keys was ever written (ids are never reused, records never
    /// zeroed), so nothing is read and a part that is 0 is not written.
    #[inline(always)]
    fn set_new_record(ref self: RegistryState, kind: u8, id: u32, record: Span<felt252>) {
        let key = PartsTrait::key(kind, id);
        let mut part: u8 = 0;
        for felt in record {
            if *felt != 0 {
                PartsTrait::write(PartsTrait::address(key, part), *felt);
            }
            part += 1;
        }
    }

    /// The writer's change detection: each part compared with the stored felt, only the parts
    /// that differ written. Whether any did, which raises the versions once.
    #[inline(always)]
    fn update_record(ref self: RegistryState, kind: u8, id: u32, record: Span<felt252>) -> bool {
        let key = PartsTrait::key(kind, id);
        let mut changed = false;
        let mut part: u8 = 0;
        for felt in record {
            let address = PartsTrait::address(key, part);
            if PartsTrait::read(address) != *felt {
                PartsTrait::write(address, *felt);
                changed = true;
            }
            part += 1;
        }
        changed
    }
}

/// The parts of a record in `Registry.records`, read and written at their address without hashing
/// the whole key for each part. The map hashes its key's members in order, a Pedersen chain from
/// the variable's selector: `h(h(h(selector, kind), id), part)`. `key` is the record's two links,
/// computed once; `address` adds the part's (tested against the map's own addresses:
/// `test_part_address_is_the_maps`). A measured saving kept in the store (the module's doc).
#[generate_trait]
impl PartsImpl of PartsTrait {
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

/// Offsets of the words of `Adventurer` from its address: `adventurers` keeps the offset access;
/// typed, each slot read cost about +100 l2 gas on the expedition's path (the module's doc,
/// ENG-R1b).
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

/// The addresses of the balance pages the store reads and writes as stored words: `balances`
/// keeps the offset access, typed slots measured at about +985 l2 gas a page on `enter` and the
/// closing `report` (the module's doc, ENG-R1b).
#[generate_trait]
impl PageImpl of PageTrait {
    /// Page `page` of the owner's balances.
    #[inline(always)]
    fn balance_page(self: @HubState, owner: felt252, page: u32) -> StorageBaseAddress {
        self.balances.entry((owner, page)).as_ptr().__storage_pointer_address__
    }
}

/// One stored word of a record, read or written as stored: what a stored model holds (see the
/// module's doc).
#[generate_trait]
impl WordImpl of WordTrait {
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
    #[available_gas(l2_gas: 277641)] // ceil(1.05 × 264420 measured)
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

/// The storage layout of `Market` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address. Here since ENG-R1b, as `Hub`'s.
#[cfg(test)]
mod market_layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use crate::systems::market::Market;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    #[available_gas(l2_gas: 57792)] // ceil(1.05 × 55040 measured)
    fn test_market_storage_addresses() {
        let state = @Market::contract_state_for_testing();
        assert(
            address_of(
                state.lots.entry(5).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("lots"), array![5].span()),
            'lots',
        );
        assert(
            address_of(
                state.seller_lots.entry((7, 0)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("seller_lots"), array![7, 0].span()),
            'seller_lots',
        );
        assert(
            address_of(
                state.trades.entry(3).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("trades"), array![3].span()),
            'trades',
        );
    }
}

/// `Market`'s constructor through the store: the configuration, and the counters at `LIVE`.
#[cfg(test)]
mod market_tests {
    use grimworld_logic::packing::{Counter, LIVE};
    use starknet::storage::StoragePointerReadAccess;
    use starknet::storage_access::StorePacking;
    use crate::systems::market::Market;
    use super::MarketStoreTrait;

    #[test]
    #[available_gas(l2_gas: 3106142)] // ceil(1.05 × 2958230 measured)
    fn test_market_initialize() {
        let mut state = Market::contract_state_for_testing();
        state.initialize(1.try_into().unwrap(), 2.try_into().unwrap(), 3.try_into().unwrap());
        assert(state.admin.read() == 1.try_into().unwrap(), 'admin');
        assert(state.hub.read() == 2.try_into().unwrap(), 'hub');
        assert(state.registry.read() == 3.try_into().unwrap(), 'registry');
        let zero: felt252 = StorePacking::pack(Counter { value: 0 });
        assert(zero == LIVE, 'the LIVE zero');
        assert(state.lot_count.read() == Counter { value: 0 }, 'lots');
        assert(state.open_lot_count.read() == Counter { value: 0 }, 'open lots');
        assert(state.trade_count.read() == Counter { value: 0 }, 'trades');
    }
}

/// The store's methods across several slots, on `Hub`'s state: the account list's insertion and
/// swap removal, the balance pages, the words the views return as stored.
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{LIVE, Lanes32};
    use starknet::storage::{
        StorageAsPointer, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::storage_access::{Store, StorePacking};
    use starknet::{ContractAddress, SyscallResultTrait};
    use crate::models::account::{Account, AccountRecord};
    use crate::models::adventurer::{
        Adventurer, AdventurerCore, AdventurerPlace, AdventurerTrait, Build,
    };
    use crate::models::lanes::StoredLanesTrait;
    use crate::models::stored_build::StoredBuildTrait;
    use crate::models::stored_record::StoredRecordTrait;
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
    // gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
    // gas: raised, ENG-R1b: account_adventurers declared with typed slots (note 4)
    #[available_gas(l2_gas: 3426045)] // ceil(1.05 × 3262900 measured)
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
    // gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
    // gas: raised, ENG-R1b: account_adventurers declared with typed slots (note 4)
    #[available_gas(l2_gas: 742991)] // ceil(1.05 × 707610 measured)
    fn test_remove_not_listed_refused() {
        let mut state = Hub::contract_state_for_testing();
        state.add_adventurer_id(1, 0, 11);
        state.add_adventurer_id(1, 1, 12);
        state.remove_adventurer_id(1, 2, 99);
    }

    // A page read once and written once whatever its changes; lanes filled and emptied counted.
    #[test]
    // gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
    #[available_gas(l2_gas: 2286123)] // ceil(1.05 × 2177260 measured)
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
    #[available_gas(l2_gas: 99908)] // ceil(1.05 × 95150 measured)
    fn test_change_balances_refused() {
        let mut state = Hub::contract_state_for_testing();
        state.change_balances(0x100000005, array![(1, 1)].span(), false);
    }

    // The store's word offsets (`CORE` to `NAME`) against the derived `Store` of `Adventurer`: an
    // adventurer written through the typed path reads back through the store's words, and one
    // written through the store reads back through the typed path.
    #[test]
    // gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
    #[available_gas(l2_gas: 7581840)] // ceil(1.05 × 7220800 measured)
    fn test_adventurer_offsets() {
        let mut state = Hub::contract_state_for_testing();
        let adventurer = Adventurer {
            core: AdventurerCore { account: 3, experience: 77, level: 4, ..Default::default() },
            place: AdventurerPlace { instance: 9, hub: 0, last_hub: 2, inside: 1, unlocked: 6 },
            build: Build { bar: [1, 2, 0, 0, 0, 0, 0, 0], attributes: 0x21, elite_slot: 1 },
            belt: Lanes32 { lanes: [8, 15, 0, 0, 0x0201, 0, 0] },
            equipped: Lanes32 { lanes: [11, 0, 12, 0, 0, 0, 0] },
            name: 'Cedric',
        };
        state.adventurers.entry(5).write(adventurer);
        let core: felt252 = StorePacking::pack(adventurer.core);
        let place: felt252 = StorePacking::pack(adventurer.place);
        let build: felt252 = StorePacking::pack(adventurer.build);
        let belt: felt252 = StorePacking::pack(adventurer.belt);
        let equipped: felt252 = StorePacking::pack(adventurer.equipped);
        assert(state.get_core(5).word == core, 'core');
        assert(state.get_place(5).word == place, 'place');
        assert(state.get_core_place(5) == (state.get_core(5), state.get_place(5)), 'core, place');
        assert(state.get_belt(5).word == belt, 'belt');
        assert(state.get_equipped(5).word == equipped, 'equipped');
        let words = array![core, place, build, belt, equipped, 'Cedric'];
        assert(state.get_adventurer_words(5) == words.span(), 'six words');

        let (new_core, new_place, new_build) = AdventurerTrait::new(3, 1, 2);
        state.set_adventurer(6, new_core, new_place, new_build, 'Brenna');
        let read = state.adventurers.entry(6).read();
        assert(StorePacking::pack(read.core) == new_core.word, 'typed core');
        assert(StorePacking::pack(read.place) == new_place.word, 'typed place');
        assert(StorePacking::pack(read.build) == new_build.build, 'typed build');
        assert(StorePacking::pack(read.belt) == new_build.belt.word, 'typed belt');
        assert(StorePacking::pack(read.equipped) == new_build.equipped.word, 'typed equipped');
        assert(read.name == 'Brenna', 'typed name');
        state
            .set_adventurer_build(
                6, StoredBuildTrait::new(build - LIVE, belt - LIVE, equipped - LIVE),
            );
        let read = state.adventurers.entry(6).read();
        assert(read.build == adventurer.build && read.belt == adventurer.belt, 'typed set_build');
        assert(read.equipped == adventurer.equipped, 'typed equipped after');
    }

    // The views' words as stored: 0 where nothing was written, the stored models otherwise.
    #[test]
    // gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
    // gas: raised, ENG-R1b: accounts declared with typed slots (note 4)
    #[available_gas(l2_gas: 4060875)] // ceil(1.05 × 3867500 measured)
    fn test_words_as_stored() {
        let mut state = Hub::contract_state_for_testing();
        assert(state.get_adventurer_words(5) == array![0, 0, 0, 0, 0, 0].span(), 'never created');
        assert(state.get_account_record(3).word == 0, 'never registered');
        let (core, place, build) = AdventurerTrait::new(3, 1, 2);
        state.set_adventurer(5, core, place, build, 'Brenna');
        let words = array![core.word, place.word, build.build, LIVE, LIVE, 'Brenna'];
        assert(build.belt.word == LIVE && build.equipped.word == LIVE, 'empty pages');
        assert(state.get_adventurer_words(5) == words.span(), 'six words');
        assert(state.get_core(5) == core && state.get_place(5) == place, 'core, place');
        assert(state.get_equipped(5).is_empty() && state.get_pack_page(5, 0).is_empty(), 'nothing');
        assert(state.get_belt(5) == build.belt, 'belt');
        state.set_account_record(3, StoredRecordTrait::new());
        assert(state.get_account_record(3) == StoredRecordTrait::new(), 'record');
    }

    // `StoredAccount`'s slots against `Account`'s derived `Store`: an account written as the model
    // reads back through the store, and one written through the store reads back as the model.
    #[test]
    #[available_gas(l2_gas: 2213169)] // ceil(1.05 × 2107780 measured)
    fn test_account_slots() {
        let mut state = Hub::contract_state_for_testing();
        let owner: ContractAddress = 0xa11ce.try_into().unwrap();
        let record = AccountRecord {
            slots: 3, adventurers: 2, highest_rank: 1, vault_panes: 1, lots: 0,
        };
        let base = state.accounts.entry(3).as_ptr().__storage_pointer_address__;
        Store::<Account>::write(0, base, Account { owner, record }).unwrap_syscall();
        let (read_owner, stored) = state.get_account(3);
        assert(read_owner == owner && state.get_owner(3) == owner, 'owner');
        assert(stored.word == StorePacking::pack(record), 'record');
        assert(state.get_account_record(3) == stored, 'record alone');
        state.set_account(4, owner, stored);
        let base = state.accounts.entry(4).as_ptr().__storage_pointer_address__;
        let read = Store::<Account>::read(0, base).unwrap_syscall();
        assert(read.owner == owner && read.record == record, 'typed account');
    }
}

/// The storage layout of `Registry` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address. Here since ENG-R1b, as `Hub`'s.
#[cfg(test)]
mod registry_layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use crate::systems::registry::Registry;
    use super::PartsTrait;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    // gas: raised, ENG-09: two more variables laid out (heart_packs, zone_checks)
    #[available_gas(l2_gas: 79412)] // ceil(1.05 × 75630 measured)
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
        assert(
            address_of(
                state.heart_packs.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("heart_packs"), array![7].span()),
            'heart_packs',
        );
        assert(
            address_of(
                state.zone_checks.as_ptr().__storage_pointer_address__,
            ) == selector!("zone_checks"),
            'zone_checks',
        );
    }

    // The oracle of `PartsTrait::key` and `PartsTrait::address`: the map's own address, for the
    // widest keys.
    #[test]
    #[available_gas(l2_gas: 178112)] // ceil(1.05 × 169630 measured)
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
            let got: felt252 = PartsTrait::address(PartsTrait::key(kind, id), part).into();
            assert(got == expected, 'part address');
        }
    }
}


/// The writer's change detection, apart from the version (ENG-03 fix loop 1, F-3): a stored
/// 3-part record rewritten through `update_record` (read, compare, write what differs) against the
/// same rewrite made blind (every part written, nothing read). Identical values and changed values
/// each have their own matched pair; none of these raises the version.
#[cfg(test)]
mod registry_detection_cost_tests {
    use grimworld_logic::content::BOOK;
    use grimworld_logic::packing::LIVE;
    use snforge_std::{map_entry_address, store, test_address};
    use crate::systems::registry::Registry;
    use super::{PartsTrait, RegistryStoreTrait};

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
            let key = PartsTrait::key(BOOK, 1);
            let mut part: u8 = 0;
            for felt in record {
                PartsTrait::write(PartsTrait::address(key, part), *felt);
                part += 1;
            }
        }
    }

    // The baseline of the four below: the record stored, nothing else.
    #[test]
    #[available_gas(l2_gas: 1344746)] // ceil(1.05 × 1280710 measured)
    fn test_detection_cost_stored_baseline() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
    }

    #[test]
    #[available_gas(l2_gas: 1577814)] // ceil(1.05 × 1502680 measured)
    fn test_detection_cost_identical_blind() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
        Book::write_blind(Book::stored());
    }

    #[test]
    #[available_gas(l2_gas: 1467690)] // ceil(1.05 × 1397800 measured)
    fn test_detection_cost_identical() {
        let mut state = Registry::contract_state_for_testing();
        Book::store();
        assert(!state.update_record(BOOK, 1, Book::stored()), 'no change');
    }

    #[test]
    #[available_gas(l2_gas: 1577814)] // ceil(1.05 × 1502680 measured)
    fn test_detection_cost_changed_blind() {
        let _state = Registry::contract_state_for_testing();
        Book::store();
        Book::write_blind(Book::changed());
    }

    #[test]
    #[available_gas(l2_gas: 1658990)] // ceil(1.05 × 1579990 measured)
    fn test_detection_cost_changed() {
        let mut state = Registry::contract_state_for_testing();
        Book::store();
        assert(state.update_record(BOOK, 1, Book::changed()), 'changed');
    }
}

/// `Registry`'s store on its state: a new record's parts (a 0 part not written, so it reads 0),
/// existence, the counters, the administrator and the versions.
#[cfg(test)]
mod registry_tests {
    use grimworld_logic::content::BOOK;
    use grimworld_logic::packing::LIVE;
    use starknet::storage::{StorageMapReadAccess, StoragePointerReadAccess};
    use crate::models::versions::VersionsTrait;
    use crate::systems::registry::Registry;
    use super::RegistryStoreTrait;

    #[test]
    #[available_gas(l2_gas: 4138869)] // ceil(1.05 × 3941780 measured)
    fn test_registry_store() {
        let mut state = Registry::contract_state_for_testing();
        assert(!state.has_record(BOOK, 1), 'never written');
        state.set_new_record(BOOK, 1, array![LIVE + 1, 0, 3].span());
        assert(state.has_record(BOOK, 1), 'written');
        assert(state.records.read((BOOK, 1, 1)) == 0, 'a 0 part');
        let mut out = array![];
        state.read_record_into(BOOK, 1, 3, ref out);
        assert(out == array![LIVE + 1, 0, 3], 'parts');
        assert(state.update_record(BOOK, 1, array![LIVE + 1, 2, 3].span()), 'changed');
        assert(state.records.read((BOOK, 1, 1)) == 2, 'part 1');
        state.set_last_id(BOOK, 1);
        assert(state.get_last_id(BOOK) == 1 && state.last_ids.read(BOOK).value == 1, 'last id');
        state.set_caste_count(7, 2);
        assert(state.get_caste_count(7) == 2 && state.caste_skills.read(7) == 2, 'caste count');
        state.set_administrator(5.try_into().unwrap());
        assert(state.get_administrator() == state.admin.read(), 'admin');
        state.set_versions(state.get_versions().raised(true));
        let versions = state.get_versions();
        assert(versions.content == 1 && versions.inputs == 1, 'versions');
    }
}
