//! `Hub`, the contract of the persistent domain's state (ADR-0001, ADR-0007): accounts,
//! adventurers, inventory and vault, progress, grimoire, Rifts, the hub's services, and the
//! receiving end of the results interface. ENG-01 freezes its interface, storage and events;
//! every entrypoint reverts with `'not implemented'` until its lot writes it.
//! docs/architecture/ENG-01-interfaces.md.

use grimworld_logic::types::InstanceId;
use starknet::{ClassHash, ContractAddress};

pub const VERSION: felt252 = 'grimworld-hub-1';
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';
/// The revert of an administrator's entrypoint called by anyone else (ADR-0007, *Access control*).
pub const NOT_ADMIN: felt252 = 'not admin';
/// `set_admin` to the zero address would leave the role to nobody.
pub const ZERO_ADMIN: felt252 = 'admin is zero';

/// `report` or `barter` called by anyone but the registered `Instances` (ADR-0007).
pub const NOT_INSTANCES: felt252 = 'not instances';

/// The region whose town a new adventurer starts in (D-144: region 1's town, read from the
/// registry's `REGION` record; design/01, design/09).
pub const START_REGION: u32 = 1;

/// What players call, in hubs. Every entrypoint that names an adventurer checks that the caller
/// owns the adventurer's account (ADR-0007, *Access control*), and that the adventurer is in a hub
/// (design/16: trade and services in hubs only).
#[starknet::interface]
pub trait IHub<T> {
    // Accounts and adventurers (ADR-0005, design/03)
    /// Creates the caller's account; returns its id.
    fn register(ref self: T) -> u32;
    /// A-7: ownership is a field the account changes; the adventurers stay.
    fn set_account_owner(ref self: T, account_id: u32, owner: ContractAddress);
    /// D-32: a name and a primary profession.
    fn create_adventurer(ref self: T, name: felt252, profession: u8) -> u32;
    /// D-33: frees the slot; its pack must be empty.
    fn delete_adventurer(ref self: T, adventurer_id: u32);

    // The build (design/03): bar, attributes, belt, equipment in one call, the stored layouts
    /// `build` is a `Build`, `belt` and `equipped` are `Lanes32`, all without `LIVE`.
    fn set_build(ref self: T, adventurer_id: u32, build: felt252, belt: felt252, equipped: felt252);

    // Travel (design/01, design/02, design/17)
    /// Through a gate of its hub: snapshot, task ids, the belt's potions debited from the pack (the
    /// reserve, credited back unused by the closing report), then `Instances.create`; returns the
    /// id.
    fn enter(ref self: T, adventurer_id: u32, gate: u16) -> InstanceId;
    /// Rift `index` of the account's board of the day (the first board action draws it).
    fn enter_rift(ref self: T, adventurer_id: u32, index: u8) -> InstanceId;
    /// Map travel to an unlocked hub.
    fn travel(ref self: T, adventurer_id: u32, hub: u16);

    // Quests (design/06, design/14; quiver_quest in storage mode, D-131, D-135)
    fn accept_quest(ref self: T, adventurer_id: u32, quest: u32);
    fn abandon_quest(ref self: T, adventurer_id: u32, quest: u32);
    /// Claims the rewards; hands in what a gathering or delivery quest asks; a trial promotes.
    fn claim_quest(ref self: T, adventurer_id: u32, quest: u32);
    /// One of the hub's three contracts of the day (design/14).
    fn accept_contract(ref self: T, adventurer_id: u32, index: u8);

    // Titles (design/13; quiver_achievement in event mode)
    fn claim_title(ref self: T, adventurer_id: u32, achievement: u32);
    /// Emits `TitleDisplayed`; nothing is stored (T-1).
    fn display_title(ref self: T, adventurer_id: u32, title: u16, tier: u8);

    // Services (design/03, design/07, design/15, design/17). `shop` is a registry `SHOP` id.
    fn buy_skill(ref self: T, adventurer_id: u32, skill: u16);
    fn buy(ref self: T, adventurer_id: u32, shop: u32, offer: u8, quantity: u32);
    /// Sell a balance (`entity` 0) or an equipment entity to the merchant.
    fn sell(ref self: T, adventurer_id: u32, item: u32, quantity: u32, entity: u32);
    fn craft(ref self: T, adventurer_id: u32, shop: u32, offer: u8);
    fn recycle(ref self: T, adventurer_id: u32, entity: u32);
    fn personalise(ref self: T, adventurer_id: u32, entity: u32);
    /// Fate: the modifiers are drawn here (design/15).
    fn identify(ref self: T, adventurer_id: u32, entity: u32);
    /// Fate without a stone: the item is destroyed one time in two.
    fn lift_modifier(ref self: T, adventurer_id: u32, entity: u32, slot: u8, stone: bool);
    fn set_modifier(ref self: T, adventurer_id: u32, entity: u32, component: u32, stone: bool);
    /// Fate on a pair never brewed; a known pair draws nothing (design/07).
    fn brew(ref self: T, adventurer_id: u32, a: u32, b: u32);
    /// Fate: one stillstone, one undiscovered recipe bound to one ingredient.
    fn buy_hint(ref self: T, adventurer_id: u32, book: u16);
    /// Moves up to 8 entities and 8 balances between the pack and the vault, and gold.
    fn stow(
        ref self: T,
        adventurer_id: u32,
        to_vault: bool,
        entities: Span<u32>,
        balances: Span<(u32, u32)>,
        gold: u64,
    );
}

/// Views (the client's reads, SPK-11 class V). Words are in their stored layout.
#[starknet::interface]
pub trait IHubViews<T> {
    fn account_of(self: @T, owner: ContractAddress) -> u32;
    /// `(owner, AccountRecord, adventurer ids)`.
    fn account(self: @T, account_id: u32) -> (ContractAddress, felt252, Span<u32>);
    /// The six words of `Adventurer`, in order.
    fn adventurer(self: @T, adventurer_id: u32) -> Span<felt252>;
    fn known_skills(self: @T, adventurer_id: u32) -> Span<felt252>;
    /// "Distinct" counters of titles (T-2), by registry `COUNTER` id: at most 32 ids a call (one
    /// read each), in the order asked; an unwritten counter is 0.
    fn counters(self: @T, adventurer_id: u32, counters: Span<u16>) -> Span<felt252>;
    /// Balance pages (`Lanes32`, item `7 page + lane`) of an owner key (`models::account`): at most
    /// 32 pages a call (one read each), in the order asked; an unwritten page is empty. The client
    /// asks for the pages of the items it knows of (the registry lists them); no view enumerates
    /// an owner's pages.
    fn balances(self: @T, owner: felt252, pages: Span<u32>) -> Span<felt252>;
    fn gold(self: @T, owner: felt252) -> u64;
    /// `(ItemBase, ItemMods)`.
    fn item(self: @T, entity: u32) -> (felt252, felt252);
    fn pack(self: @T, adventurer_id: u32) -> Span<u32>;
    /// The account's equipment in the vault: 4 pages a pane, at most 8 panes (32 reads).
    fn vault(self: @T, account_id: u32) -> Span<u32>;
    /// `(GrimoireState, Pairs, Pairs)`.
    fn grimoire(self: @T, adventurer_id: u32, book: u16) -> (felt252, felt252, felt252);
    fn rift_board(self: @T, account_id: u32) -> felt252;
    /// quiver's held quests and their progress (D-135: at most 4).
    fn quests(self: @T, adventurer_id: u32) -> Span<felt252>;
}

/// Called by the registered `Market` only (design/16: the hub holds every item; the market
/// escrows through it).
#[starknet::interface]
pub trait IHubMarket<T> {
    /// `(account, highest rank, hub)` of an adventurer whose account the caller of the market owns.
    fn seller(self: @T, adventurer_id: u32, caller: ContractAddress) -> (u32, u8, u16);
    /// From the adventurer's pack into escrow for `lot`. `kind`: 0 a balance, 1 an entity.
    fn escrow(ref self: T, adventurer_id: u32, lot: u64, kind: u8, item: u32, quantity: u32);
    /// From escrow of `lot` to an account's vault.
    fn release(ref self: T, lot: u64, account_id: u32, kind: u8, item: u32, quantity: u32);
    /// Gold between owner keys (a purchase, the listing fee: `to` 0 burns it).
    fn transfer_gold(ref self: T, from: felt252, to: felt252, amount: u64);
    /// A direct trade, all or nothing: each side is `(goods: Lanes32, money: TradeMoney)`.
    fn exchange(
        ref self: T, a: u32, b: u32, a_side: (felt252, felt252), b_side: (felt252, felt252),
    );
}

#[starknet::interface]
pub trait IHubAdmin<T> {
    fn version(self: @T) -> felt252;
    fn set_contracts(
        ref self: T,
        registry: ContractAddress,
        instances: ContractAddress,
        market: ContractAddress,
        fate: ContractAddress,
        flatten: ClassHash,
    );
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Hub {
    use core::num::traits::Zero;
    use grimworld_logic::content::{GATE, ITEM, MODIFIER, REGION, SKILL, exists};
    use grimworld_logic::interface::{
        IFlattenLibraryDispatcherTrait, IFlattenLibraryLibraryDispatcher, IInstanceEntryDispatcher,
        IInstanceEntryDispatcherTrait, IRegistryReadDispatcher, IRegistryReadDispatcherTrait,
        IResults, Results, facts,
    };
    use grimworld_logic::models::gate::{Gate, GateAssert, GateRecord, errors as gate_errors};
    use grimworld_logic::models::item::ItemTrait;
    use grimworld_logic::models::region::{Region, RegionRecord};
    use grimworld_logic::models::skill::SkillTrait;
    use grimworld_logic::packing::{Bitmap, Counter, Lanes32, unpack_lanes32};
    use grimworld_logic::professions::ProfessionAssert;
    use grimworld_logic::snapshot::Worn;
    use grimworld_logic::types::{InstanceId, Outcome};
    use starknet::storage::{
        Map, StorageAsPointer, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::storage_access::{StorageBaseAddress, Store, StorePacking};
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::events::{
        AdventurerLocated, DungeonCleared, RankReached, TitleDisplayed, TrialPassed,
    };
    use crate::models::account::{
        Account, AccountAssert, AccountRecord, AccountRecordTrait, AdventurerListTrait,
        IDS_PER_PAGE, NEW_RECORD, PACK, RECORD_WORD, owner_key,
    };
    use crate::models::adventurer::{
        Adventurer, AdventurerAssert, AdventurerCoreTrait, AdventurerPlaceTrait, BELT_WORD,
        BUILD_WORD, BeltAssert, BeltTrait, Build, BuildAssert, BuildTrait, CORE_WORD, EMPTY_LANES,
        EQUIPPED_WORD, EquippedAssert, KnownSkillsTrait, NAME_WORD, NEW_BUILD, NO_ELITE, PLACE_WORD,
    };
    use crate::models::balance::BalanceTrait;
    use crate::models::item::{
        Gold, Grimoire, Item, ItemBase, ItemBaseAssert, ItemBaseTrait, ItemMods, ItemModsTrait,
        PERSONALISED, RiftBoard,
    };
    use crate::models::snapshot::{StoredSnapshot, StoredSnapshotAssert, StoredSnapshotTrait};
    use crate::store::StoreTrait;
    use crate::types::results::{ResultsAssert, ResultsTrait};
    use super::{NOT_IMPLEMENTED, NOT_INSTANCES, START_REGION, VERSION};

    /// docs/architecture/ENG-01-interfaces.md, *Hub storage*. quiver's components (quests,
    /// achievements) add their own storage when ARC's packages are embedded.
    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        pub registry: ContractAddress,
        pub instances: ContractAddress,
        pub market: ContractAddress,
        pub fate: ContractAddress,
        /// `FlattenLibrary`'s class hash (ENG-01 §1.3, D-168): `set_build` calls it by
        /// `library_call`.
        pub flatten: ClassHash,
        /// The rules epoch (D-169): how many times `set_contracts` changed `flatten`, modulo
        /// `RULES_EPOCHS` (512, 9 bits of the stored kit word); 0 at deployment. A stored snapshot
        /// carries the one it was flattened under, and `enter` refuses another.
        pub rules_epoch: u16,
        pub next_account: Counter,
        pub next_adventurer: Counter,
        pub next_item: Counter,
        pub account_of: Map<ContractAddress, u32>,
        /// Two slots each: owner, record.
        pub accounts: Map<u32, Account>,
        /// `(account, page)`: its adventurer ids, seven per page.
        pub account_adventurers: Map<(u32, u8), Lanes32>,
        /// Six slots each.
        pub adventurers: Map<u32, Adventurer>,
        /// `(adventurer, page)`: bit per skill id, 250 per page.
        pub known_skills: Map<(u32, u8), Bitmap>,
        /// `(adventurer, counter)`: "distinct" bitmaps of titles (T-2).
        pub counters: Map<(u32, u16), Bitmap>,
        /// `(account, counter)`: the same for account titles.
        pub account_counters: Map<(u32, u16), Bitmap>,
        /// `(adventurer, book)`: three slots each.
        pub grimoires: Map<(u32, u16), Grimoire>,
        /// `(owner key, page)`: seven balances of `u32` per page, item `7 page + lane`.
        pub balances: Map<(felt252, u32), Lanes32>,
        pub gold: Map<felt252, Gold>,
        /// Two slots each, by entity id.
        pub items: Map<u32, Item>,
        /// `(adventurer, page)`: equipment entities in the pack, seven per page (design/15: 20
        /// slots, +5 per bag).
        pub packs: Map<(u32, u8), Lanes32>,
        /// `(account, page)`: equipment entities in the vault, seven per page (25 per pane).
        pub vaults: Map<(u32, u8), Lanes32>,
        pub rift_boards: Map<u32, RiftBoard>,
        /// Three slots each, by adventurer id: the snapshot `set_build` flattened, which `enter`
        /// copies (D-168; `models::snapshot`).
        pub snapshots: Map<u32, StoredSnapshot>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        AdventurerLocated: AdventurerLocated,
        TitleDisplayed: TitleDisplayed,
        TrialPassed: TrialPassed,
        DungeonCleared: DungeonCleared,
        RankReached: RankReached,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
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

    #[abi(embed_v0)]
    impl HubImpl of super::IHub<ContractState> {
        /// One account per address, with its three slots (D-33). Writes (ENG-01 §9.3): the
        /// account's two words and `account_of[caller]` new, `next_account` overwritten.
        fn register(ref self: ContractState) -> u32 {
            let caller = get_caller_address();
            AccountAssert::assert_no_account(self.account_of.entry(caller).read());
            let next = self.next_account.read().value;
            let account_id: u32 = next.try_into().unwrap();
            self.next_account.write(Counter { value: next + 1 });
            let account = self.accounts.entry(account_id);
            account.owner.write(caller);
            account.as_ptr().__storage_pointer_address__.set_word(RECORD_WORD, NEW_RECORD);
            self.account_of.entry(caller).write(account_id);
            account_id
        }

        /// A-7: the current owner hands the account over; the adventurers stay. The old owner's
        /// `account_of` is zeroed (E-19). An adventurer inside an instance gets the new owner as
        /// controller (ENG-01 §1.2). Bound: the account's adventurers, at most its slots (one page
        /// of seven, ENG-01 §4.5).
        fn set_account_owner(ref self: ContractState, account_id: u32, owner: ContractAddress) {
            let caller = get_caller_address();
            let account = self.accounts.entry(account_id);
            AccountAssert::assert_transfer(
                account.owner.read(), caller, owner, self.account_of.entry(owner).read(),
            );
            account.owner.write(owner);
            self.account_of.entry(owner).write(account_id);
            self.account_of.entry(caller).write(0);

            let record = account.as_ptr().__storage_pointer_address__.word(RECORD_WORD);
            let (_, count) = AccountRecordTrait::counts(record);
            if count == 0 {
                return;
            }
            let instances = IInstanceEntryDispatcher { contract_address: self.instances.read() };
            let mut ids = Lanes32 { lanes: [0; 7] };
            let mut i: u8 = 0;
            while i != count {
                let (page, lane) = DivRem::div_rem(i, IDS_PER_PAGE.try_into().unwrap());
                if lane == 0 {
                    ids = self.account_adventurers.entry((account_id, page)).read();
                }
                let adventurer_id = ids.get(lane);
                let base = self
                    .adventurers
                    .entry(adventurer_id)
                    .as_ptr()
                    .__storage_pointer_address__;
                if AdventurerPlaceTrait::is_inside(base.word(PLACE_WORD)) {
                    instances.set_controller(adventurer_id, owner);
                }
                i += 1;
            }
        }

        /// D-32: a name and a primary profession; placed in region 1's town, read from the
        /// registry (D-144: one `record` call), unlocked, at level 1, rank Wood.
        /// Writes (ENG-01 §9.3): the adventurer's six words new, its lane of the account's list
        /// (new on a page's first lane), the account's record and `next_adventurer` overwritten.
        /// The words are written as stored, without the packers (pinned by `test_stored_words`).
        fn create_adventurer(ref self: ContractState, name: felt252, profession: u8) -> u32 {
            let account_id = self.account_of.entry(get_caller_address()).read();
            AccountAssert::assert_has_account(account_id);
            AdventurerAssert::assert_valid_name(name);
            ProfessionAssert::assert_playable(profession);
            let account = self.accounts.entry(account_id).as_ptr().__storage_pointer_address__;
            let record = account.word(RECORD_WORD);
            let (slots, count) = AccountRecordTrait::counts(record);
            AccountAssert::assert_free_slot(slots, count);

            let next = self.next_adventurer.read().value;
            let adventurer_id: u32 = next.try_into().unwrap();
            self.next_adventurer.write(Counter { value: next + 1 });
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            base.set_word(CORE_WORD, AdventurerCoreTrait::new(account_id, profession));
            base.set_word(PLACE_WORD, AdventurerPlaceTrait::new(self.start_hub()));
            base.set_word(BUILD_WORD, NEW_BUILD);
            base.set_word(BELT_WORD, EMPTY_LANES);
            base.set_word(EQUIPPED_WORD, EMPTY_LANES);
            base.set_word(NAME_WORD, name);

            // The list is compact: the lanes from its length on are 0, so the new id is added to
            // its lane, and a page's first lane is written without reading the page.
            let (page, lane) = DivRem::div_rem(count, IDS_PER_PAGE.try_into().unwrap());
            let list = self
                .account_adventurers
                .entry((account_id, page))
                .as_ptr()
                .__storage_pointer_address__;
            let ids = if lane == 0 {
                EMPTY_LANES
            } else {
                list.word(0)
            };
            list.set_word(0, ids + adventurer_id.into() * AdventurerListTrait::unit(lane));
            account.set_word(RECORD_WORD, AccountRecordTrait::with_adventurer(record));
            adventurer_id
        }

        /// D-33: frees the slot once the pack is empty. "Its inventory emptied", each checked by
        /// one read, without scanning (`AdventurerAssert::assert_emptied`): the pack's balances
        /// (`core.pack_lanes` = 0), its equipment (the compact list's first page is empty), what it
        /// wears (`equipped` all 0), its gold (0). The belt names potion items; the potions
        /// themselves are pack balances. The adventurer's record is never zeroed: `core.status` =
        /// `DELETED` marks it, and its id is never reused. Writes (ENG-01 §9.3): `core`, the
        /// account's record, the list's hole and last pages, all overwritten (one page while the
        /// account has seven adventurers or fewer).
        fn delete_adventurer(ref self: ContractState, adventurer_id: u32) {
            let (account_id, core, _) = self.owned_in_hub(adventurer_id);
            let (_, _, pack_lanes) = AdventurerCoreTrait::fields(core);
            let pack_page = self
                .packs
                .entry((adventurer_id, 0))
                .as_ptr()
                .__storage_pointer_address__;
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            let gold = self
                .gold
                .entry(owner_key(PACK, adventurer_id))
                .as_ptr()
                .__storage_pointer_address__;
            AdventurerAssert::assert_emptied(
                pack_lanes, pack_page.word(0), base.word(EQUIPPED_WORD), gold.word(0),
            );

            // The swap removal: the last id moves into the hole, the last lane is cleared. Bound:
            // the account's adventurers.
            let account = self.accounts.entry(account_id).as_ptr().__storage_pointer_address__;
            let record = account.word(RECORD_WORD);
            let (_, count) = AccountRecordTrait::counts(record);
            let last = count - 1;
            let per_page: NonZero<u8> = IDS_PER_PAGE.try_into().unwrap();
            let (last_page, last_lane) = DivRem::div_rem(last, per_page);
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
                    assert(i != last, 'not in the account list');
                    let (page, lane) = DivRem::div_rem(i, per_page);
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
            last_list.set_word(0, last_new);
            account.set_word(RECORD_WORD, AccountRecordTrait::without_adventurer(record));
            base.set_word(CORE_WORD, AdventurerCoreTrait::deleted(core));
        }
        /// The build in one call (design/03; ENG-01 §4.3), in a hub (the build is locked inside),
        /// every rule checked before anything is written. The bar: each skill known, in the
        /// registry, of the primary or the secondary profession, none twice, at most one elite
        /// and `elite_slot` naming it. The attributes: `BuildAssert::assert_attributes`. The belt:
        /// potions of the registry, a count only with an item, the pack holding each item's summed
        /// count (the reserve `enter` debits). The equipment: each entity in the adventurer's
        /// pack, wearable, worn in its lane's slot, no off-hand beside a weapon held in both
        /// hands: the slot and the hands are the item's own, copied from its `BASE` at creation
        /// (D-158), so no base is read. Then the snapshot's flattening (D-160, CBT-02b) with
        /// every check of design/20's capacity proof: DS-2's floors, DS-23's insignia pieces, the
        /// counts and per-source bounds of the modifiers worn. Reads: the ownership check's 3
        /// words, the known-skills pages of the bar, the pack pages of the belt's items (at most
        /// 4), each equipped entity's `ItemBase` and `ItemMods` (at most 7 each); one
        /// `Registry.bundle` call for the skills, the belt's items and the distinct modifiers worn
        /// (at most 12 + 15 = 27 records for a build design/20 §1.2 allows, none when all are
        /// empty; more than `MAX_READ` is refused by the registry). Writes (ENG-01 §9.3): `build`,
        /// `belt`, `equipped`, overwritten, the words sent plus `LIVE`.
        fn set_build(
            ref self: ContractState,
            adventurer_id: u32,
            build: felt252,
            belt: felt252,
            equipped: felt252,
        ) {
            let (_, core, _) = self.owned_in_hub(adventurer_id);
            let (_, level, rank, primary) = AdventurerCoreTrait::profile(core);
            let secondary = AdventurerCoreTrait::secondary(core);
            let build_word = BuildAssert::assert_layout(build);
            let belt_word = BeltAssert::assert_layout(belt);
            let equipped_word = EquippedAssert::assert_layout(equipped);

            let value: Build = StorePacking::unpack(build_word);
            value.assert_attributes(primary, secondary, level, rank);
            value.assert_distinct();
            let (items, counts) = BeltTrait::read(belt_word);
            BeltAssert::assert_counts(items, counts);
            let entities = unpack_lanes32(equipped_word).lanes.span();
            EquippedAssert::assert_distinct(entities);

            // What the registry is asked, in order: the bar's skills, the belt's distinct items.
            let mut requests: Array<(u8, u32)> = array![];
            let mut known: Array<bool> = array![];
            let (mut page, mut page_word) = (0_u8, 0);
            let mut read = false;
            for skill in value.bar.span() {
                let skill = *skill;
                if skill == 0 {
                    continue;
                }
                let (at, bit) = KnownSkillsTrait::at(skill);
                if !read || at != page {
                    page = at;
                    page_word = self
                        .known_skills
                        .entry((adventurer_id, page))
                        .as_ptr()
                        .__storage_pointer_address__
                        .word(0);
                    read = true;
                }
                known.append(KnownSkillsTrait::knows(page_word, bit));
                requests.append((SKILL, skill.into()));
            }
            let skills = requests.len();
            let slots = items.span();
            for i in 0..4_u32 {
                let item = *slots[i];
                if item == 0 {
                    continue;
                }
                let mut first = true;
                for j in 0..i {
                    if *slots[j] == item {
                        first = false;
                    }
                }
                if first {
                    requests.append((ITEM, item));
                }
            }
            let belt_items = requests.len();
            let pack = owner_key(PACK, adventurer_id);
            for entry in BalanceTrait::merge(items, counts) {
                let (item, count) = entry;
                let (page, lane) = BalanceTrait::at(item);
                let word = self
                    .balances
                    .entry((pack, page))
                    .as_ptr()
                    .__storage_pointer_address__
                    .word(0);
                BeltAssert::assert_held(BalanceTrait::amount(word, lane), count);
            }
            let (bases, worn, modifiers, personalised) = self.equipment(entities);
            let mut two_handed = false;
            for (lane, item) in bases.span() {
                item.assert_wearable(adventurer_id);
                EquippedAssert::assert_slot(*item.slot, *lane);
                if *lane == 0 {
                    two_handed = item.is_two_handed();
                }
            }
            EquippedAssert::assert_hands(two_handed, *entities[1]);
            for id in modifiers.span() {
                requests.append((MODIFIER, (*id).into()));
            }

            // One registry call, even for an empty build: the inputs version the snapshot is
            // computed under (D-168 2, D-169).
            let (_, inputs, parts) = IRegistryReadDispatcher {
                contract_address: self.registry.read(),
            }
                .bundle(requests.span());
            let mut at: u32 = 0;
            let mut elite = NO_ELITE;
            let mut slot: u8 = 0;
            let mut k: u32 = 0;
            for skill in value.bar.span() {
                if *skill != 0 {
                    let part = *parts[at];
                    let (profession, is_elite) = SkillTrait::profile(part);
                    BuildAssert::assert_skill(*known[k], part != 0, profession, primary, secondary);
                    if is_elite {
                        BuildAssert::assert_one_elite(elite);
                        elite = slot;
                    }
                    at += 2;
                    k += 1;
                }
                slot += 1;
            }
            value.assert_elite_slot(elite);
            for _ in skills..belt_items {
                let part = *parts[at];
                BeltAssert::assert_potion(part != 0, ItemTrait::class_of(part));
                at += 1;
            }

            // The snapshot's flattening, once, in `FlattenLibrary` (D-168), with every check of
            // design/20's capacity proof (D-160): a build it refuses is refused here.
            let loadout = value.loadout(level, primary, personalised, items, counts);
            let (stats, bar, kit) = IFlattenLibraryLibraryDispatcher {
                class_hash: self.flatten.read(),
            }
                .words(loadout, worn.span(), modifiers.span(), parts.slice(at, parts.len() - at));

            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            base.set_word(BUILD_WORD, build_word);
            base.set_word(BELT_WORD, belt_word);
            base.set_word(EQUIPPED_WORD, equipped_word);
            StoreTrait::set_snapshot(
                self.snapshots.entry(adventurer_id),
                StoredSnapshotTrait::new(
                    stats, bar, kit, StoredSnapshotTrait::epoch(inputs, self.rules_epoch.read()),
                ),
            );
        }
        /// Through a gate of the hub the adventurer is in (design/02 *Entering*, ENG-01 §6): the
        /// ownership check, the gate from the registry and its requirements, the stored snapshot
        /// checked fresh, the belt's reserve debited from the pack, then `Instances.create`, which
        /// makes the entry draw. Every check comes before the call: a refusal reverts, drawing
        /// nothing and changing nothing. The snapshot is the one `set_build` flattened and stored
        /// (D-168), copied, never recomputed: refused when there is none (`snapshot: missing`) or
        /// when it is stale (`snapshot: stale`): marked, of another flattening epoch (the
        /// registry's inputs version and the rules epoch, D-169), or of another level than the
        /// adventurer's; the client sends `set_build` first. Reads besides the ownership check:
        /// `rules_epoch`, the snapshot's 3 words, `belt`, the pack pages of the belt's items.
        /// Writes (ENG-01 §9.3): the pack pages of the belt's items (at most 4, overwritten),
        /// `core` when a pack lane falls to 0, `place`. Calls: `Registry.bundle` (the gate and the
        /// inputs version), `Instances.create`. Task ids: none until quiver's quests are embedded
        /// (E-14).
        fn enter(ref self: ContractState, adventurer_id: u32, gate: u16) -> InstanceId {
            let (_, core, place) = self.owned_in_hub(adventurer_id);
            let (_, hub, _, _) = AdventurerPlaceTrait::fields(place);
            let (_, level, rank, _) = AdventurerCoreTrait::profile(core);
            let (_, inputs, parts) = IRegistryReadDispatcher {
                contract_address: self.registry.read(),
            }
                .bundle(array![(GATE, gate.into())].span());
            assert(exists(parts), gate_errors::NONE);
            let record: Gate = GateRecord::unpack(parts);
            record.assert_enterable(hub, rank);

            let stored = StoreTrait::get_snapshot(self.snapshots.entry(adventurer_id));
            let epoch = StoredSnapshotTrait::epoch(inputs, self.rules_epoch.read());
            StoredSnapshotAssert::assert_fresh(stored.kit, epoch);
            StoredSnapshotAssert::assert_level(stored.stats, level);
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            let (items, counts) = BeltTrait::read(base.word(BELT_WORD));
            let snapshot = stored.words(epoch, counts);

            let reserve = BalanceTrait::merge(items, counts);
            let (_, emptied) = self.change_pack(adventurer_id, reserve.span(), false);
            if emptied != 0 {
                base.set_word(CORE_WORD, AdventurerCoreTrait::with_pack_lanes(core, 0, emptied));
            }
            let instance = IInstanceEntryDispatcher { contract_address: self.instances.read() }
                .create(adventurer_id, get_caller_address(), gate, snapshot, array![].span());
            base.set_word(PLACE_WORD, AdventurerPlaceTrait::entered(place, instance));
            self.emit(AdventurerLocated { hub: 0, adventurer: adventurer_id });
            instance
        }
        fn enter_rift(ref self: ContractState, adventurer_id: u32, index: u8) -> InstanceId {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        /// Map travel to an unlocked hub (design/01 *Connectivity*), which becomes its last hub.
        /// Writes `place`; no registry read (ENG-01 §10: 0 calls).
        fn travel(ref self: ContractState, adventurer_id: u32, hub: u16) {
            let (_, _, place) = self.owned_in_hub(adventurer_id);
            AdventurerAssert::assert_unlocked(place, hub);
            self
                .adventurers
                .entry(adventurer_id)
                .as_ptr()
                .__storage_pointer_address__
                .set_word(PLACE_WORD, AdventurerPlaceTrait::located(place, hub));
            self.emit(AdventurerLocated { hub, adventurer: adventurer_id });
        }
        fn accept_quest(ref self: ContractState, adventurer_id: u32, quest: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn abandon_quest(ref self: ContractState, adventurer_id: u32, quest: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn claim_quest(ref self: ContractState, adventurer_id: u32, quest: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn accept_contract(ref self: ContractState, adventurer_id: u32, index: u8) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn claim_title(ref self: ContractState, adventurer_id: u32, achievement: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn display_title(ref self: ContractState, adventurer_id: u32, title: u16, tier: u8) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn buy_skill(ref self: ContractState, adventurer_id: u32, skill: u16) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn buy(ref self: ContractState, adventurer_id: u32, shop: u32, offer: u8, quantity: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn sell(
            ref self: ContractState, adventurer_id: u32, item: u32, quantity: u32, entity: u32,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn craft(ref self: ContractState, adventurer_id: u32, shop: u32, offer: u8) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn recycle(ref self: ContractState, adventurer_id: u32, entity: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn personalise(ref self: ContractState, adventurer_id: u32, entity: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn identify(ref self: ContractState, adventurer_id: u32, entity: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn lift_modifier(
            ref self: ContractState, adventurer_id: u32, entity: u32, slot: u8, stone: bool,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_modifier(
            ref self: ContractState, adventurer_id: u32, entity: u32, component: u32, stone: bool,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn brew(ref self: ContractState, adventurer_id: u32, a: u32, b: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn buy_hint(ref self: ContractState, adventurer_id: u32, book: u16) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn stow(
            ref self: ContractState,
            adventurer_id: u32,
            to_vault: bool,
            entities: Span<u32>,
            balances: Span<(u32, u32)>,
            gold: u64,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl HubViewsImpl of super::IHubViews<ContractState> {
        /// 0: the address owns no account.
        fn account_of(self: @ContractState, owner: ContractAddress) -> u32 {
            self.account_of.entry(owner).read()
        }
        /// The record as stored (0 for an account that does not exist), and the ids of its
        /// adventurers not deleted, in the list's order.
        fn account(self: @ContractState, account_id: u32) -> (ContractAddress, felt252, Span<u32>) {
            let account = self.accounts.entry(account_id);
            let base = account.as_ptr().__storage_pointer_address__;
            let word = base.word(RECORD_WORD);
            let record: AccountRecord = StorePacking::unpack(word);
            let mut ids: Array<u32> = array![];
            let mut page_ids = Lanes32 { lanes: [0; 7] };
            let mut i: u8 = 0;
            while i != record.adventurers {
                let (page, lane) = DivRem::div_rem(i, IDS_PER_PAGE.try_into().unwrap());
                if lane == 0 {
                    page_ids = self.account_adventurers.entry((account_id, page)).read();
                }
                ids.append(page_ids.get(lane));
                i += 1;
            }
            (account.owner.read(), word, ids.span())
        }
        /// The six words as stored (six 0 for an id never created); a deleted adventurer keeps
        /// its words, `DELETED` in `core.status`.
        fn adventurer(self: @ContractState, adventurer_id: u32) -> Span<felt252> {
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            let mut words: Array<felt252> = array![];
            for offset in 0..6_u8 {
                words.append(base.word(offset));
            }
            words.span()
        }
        fn known_skills(self: @ContractState, adventurer_id: u32) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn counters(
            self: @ContractState, adventurer_id: u32, counters: Span<u16>,
        ) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn balances(self: @ContractState, owner: felt252, pages: Span<u32>) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn gold(self: @ContractState, owner: felt252) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn item(self: @ContractState, entity: u32) -> (felt252, felt252) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn pack(self: @ContractState, adventurer_id: u32) -> Span<u32> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn vault(self: @ContractState, account_id: u32) -> Span<u32> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn grimoire(
            self: @ContractState, adventurer_id: u32, book: u16,
        ) -> (felt252, felt252, felt252) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn rift_board(self: @ContractState, account_id: u32) -> felt252 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn quests(self: @ContractState, adventurer_id: u32) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl ResultsImpl of IResults<ContractState> {
        /// The settlement of an instance's results (ENG-01 §6), `Instances` only. The first
        /// contributor must be inside that instance. Applies what the models hold: the belt's
        /// reserve credited back to the pack when the report closes the member's presence, on
        /// return and on defeat alike (D-141, E-15), with the balances as one pass over their
        /// pages; the placement (in a hub: the one reported, else its last hub, D-04; or the next
        /// instance through a gate); a hub reached, unlocked; gold; experience to every
        /// contributor. Refuses what has no model yet (`types::results`). Writes (ENG-01 §9.3):
        /// the pack pages (at most 4 for the belt, overwritten), `core` when a lane fills or
        /// experience changes, `place` when it closes or moves, `gold` when gold comes.
        fn report(ref self: ContractState, results: Results) {
            assert(get_caller_address() == self.instances.read(), NOT_INSTANCES);
            results.assert_settled();
            let adventurer_id = *results.contributors[0];
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            let place = base.word(PLACE_WORD);
            AdventurerAssert::assert_in_instance(place, results.instance_id);

            let mut credit = if results.closes() {
                let (items, _) = BeltTrait::read(base.word(BELT_WORD));
                BalanceTrait::merge(items, results.belt)
            } else {
                array![]
            };
            for balance in results.balances {
                credit.append(*balance);
            }
            let (filled, _) = self.change_pack(adventurer_id, credit.span(), true);
            if filled != 0 || results.experience != 0 {
                let core = AdventurerCoreTrait::with_pack_lanes(base.word(CORE_WORD), filled, 0);
                base
                    .set_word(
                        CORE_WORD, AdventurerCoreTrait::with_experience(core, results.experience),
                    );
            }
            if results.gold != 0 {
                let entry = self.gold.entry(owner_key(PACK, adventurer_id));
                entry.write(Gold { amount: entry.read().amount + results.gold });
            }
            if results.experience != 0 {
                for other in results.contributors.slice(1, results.contributors.len() - 1) {
                    let other = self.adventurers.entry(*other).as_ptr().__storage_pointer_address__;
                    other
                        .set_word(
                            CORE_WORD,
                            AdventurerCoreTrait::with_experience(
                                other.word(CORE_WORD), results.experience,
                            ),
                        );
                }
            }

            match results.outcome {
                Outcome::Open => {},
                Outcome::Moved => base
                    .set_word(PLACE_WORD, AdventurerPlaceTrait::moved(place, results.next)),
                _ => {
                    let (_, _, last_hub, _) = AdventurerPlaceTrait::fields(place);
                    let hub = if results.hub != 0 {
                        results.hub
                    } else {
                        last_hub
                    };
                    let mut located = AdventurerPlaceTrait::located(place, hub);
                    if results.facts & facts::HUB_REACHED != 0 {
                        located = AdventurerPlaceTrait::unlocked(located, results.location);
                    }
                    base.set_word(PLACE_WORD, located);
                    self.emit(AdventurerLocated { hub, adventurer: adventurer_id });
                },
            }
        }
        fn barter(ref self: ContractState, adventurer_id: u32, collector: u16) -> bool {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl HubMarketImpl of super::IHubMarket<ContractState> {
        fn seller(
            self: @ContractState, adventurer_id: u32, caller: ContractAddress,
        ) -> (u32, u8, u16) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn escrow(
            ref self: ContractState,
            adventurer_id: u32,
            lot: u64,
            kind: u8,
            item: u32,
            quantity: u32,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn release(
            ref self: ContractState, lot: u64, account_id: u32, kind: u8, item: u32, quantity: u32,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn transfer_gold(ref self: ContractState, from: felt252, to: felt252, amount: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn exchange(
            ref self: ContractState,
            a: u32,
            b: u32,
            a_side: (felt252, felt252),
            b_side: (felt252, felt252),
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl HubAdminImpl of super::IHubAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
        /// The registered contracts, the randomness provider among them, and `FlattenLibrary`'s
        /// class hash (D-168): configuration, never a constant of the code (ADR-0001, ADR-0002,
        /// ENG-01 §1.3). A class hash other than the stored one raises the rules epoch (D-169), which
        /// stales every stored snapshot; the same one leaves it. Administrator only.
        fn set_contracts(
            ref self: ContractState,
            registry: ContractAddress,
            instances: ContractAddress,
            market: ContractAddress,
            fate: ContractAddress,
            flatten: ClassHash,
        ) {
            assert(get_caller_address() == self.admin.read(), super::NOT_ADMIN);
            self.registry.write(registry);
            self.instances.write(instances);
            self.market.write(market);
            self.fate.write(fate);
            if flatten != self.flatten.read() {
                self.flatten.write(flatten);
                self.rules_epoch.write(StoredSnapshotTrait::next_rules(self.rules_epoch.read()));
            }
        }
        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            assert(get_caller_address() == self.admin.read(), super::NOT_ADMIN);
            assert(admin.is_non_zero(), super::ZERO_ADMIN);
            self.admin.write(admin);
        }
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    /// One stored word of a record, read or written as stored, without unpacking (docs/CAIRO.md
    /// §1): the entrypoints below change a few fields of a record by arithmetic. Until the store
    /// of D-143 (ARC-06, ENG-R1) takes over every access to storage.
    #[generate_trait]
    impl WordImpl of WordTrait {
        /// Word `offset` of the record at `self`.
        fn word(self: StorageBaseAddress, offset: u8) -> felt252 {
            Store::<felt252>::read_at_offset(0, self, offset).unwrap_syscall()
        }

        fn set_word(self: StorageBaseAddress, offset: u8, value: felt252) {
            Store::<felt252>::write_at_offset(0, self, offset, value).unwrap_syscall()
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        /// The check of every entrypoint that names an adventurer (ADR-0007, *Access control*;
        /// ENG-01 §1.2): three reads (`core`, the account's owner, `place`), then
        /// `AdventurerAssert::assert_owned_in_hub`, one refusal per case. Returns `(account id,
        /// core, place)`, the two words as stored, for the entrypoint to unpack what it needs.
        fn owned_in_hub(self: @ContractState, adventurer_id: u32) -> (u32, felt252, felt252) {
            let base = self.adventurers.entry(adventurer_id).as_ptr().__storage_pointer_address__;
            let core = base.word(CORE_WORD);
            let (account_id, status, _) = AdventurerCoreTrait::fields(core);
            let owner = self.accounts.entry(account_id).owner.read();
            let place = base.word(PLACE_WORD);
            AdventurerAssert::assert_owned_in_hub(
                account_id, status, place, owner, get_caller_address(),
            );
            (account_id, core, place)
        }

        /// The items worn (`entities`, `equipped`'s lanes): each one's lane and `ItemBase`, for
        /// the equipment's checks, and as the flattening reads it (`Worn`, with its `ItemMods`:
        /// two reads an item); the distinct modifier ids they hold in the order met; whether the
        /// weapon is personalised (`ItemBase.flags`). Bound: 7 lanes, 5 modifiers an item.
        fn equipment(
            self: @ContractState, entities: Span<u32>,
        ) -> (Array<(u32, ItemBase)>, Array<Worn>, Array<u16>, bool) {
            let mut bases = array![];
            let mut worn = array![];
            let mut modifiers: Array<u16> = array![];
            let mut personalised = false;
            for lane in 0..7_u32 {
                let entity = *entities[lane];
                if entity == 0 {
                    continue;
                }
                let base = self.items.entry(entity).as_ptr().__storage_pointer_address__;
                let item: ItemBase = StorePacking::unpack(base.word(0));
                let mods: ItemMods = StorePacking::unpack(base.word(1));
                let item_worn = mods.worn(lane.try_into().unwrap(), item.slot);
                for id in item_worn.ids.span() {
                    let id = *id;
                    if id == 0 {
                        continue;
                    }
                    let mut seen = false;
                    for other in modifiers.span() {
                        if *other == id {
                            seen = true;
                        }
                    }
                    if !seen {
                        modifiers.append(id);
                    }
                }
                if lane == 0 {
                    personalised = item.flags & PERSONALISED != 0;
                }
                bases.append((lane, item));
                worn.append(item_worn);
            }
            (bases, worn, modifiers, personalised)
        }

        /// Region 1's town (D-144), read from the registry: one `record` call. Refuses when the
        /// region is missing; a town id of 64 or more when it is placed (`unlocked` holds bits
        /// 0-63).
        fn start_hub(self: @ContractState) -> u16 {
            let parts = IRegistryReadDispatcher { contract_address: self.registry.read() }
                .record(REGION, START_REGION);
            AdventurerAssert::assert_start_region(exists(parts));
            let region: Region = RegionRecord::unpack(parts);
            region.town
        }

        /// Credits (`credit`) or debits the adventurer's pack by `(item, amount)` changes, each
        /// page read once and written once, however many changes it holds (at most 12: a belt of
        /// 4 and 8 balances, ENG-01 §4.5). Returns `(lanes filled, lanes emptied)` for
        /// `core.pack_lanes`. Refuses a debit the pack cannot pay.
        fn change_pack(
            ref self: ContractState, adventurer_id: u32, changes: Span<(u32, u32)>, credit: bool,
        ) -> (u16, u16) {
            let owner = owner_key(PACK, adventurer_id);
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
    }
}

/// The storage layout of `Hub` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address.
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use super::Hub;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    // gas: raised, CBT-02f: the layout checks rules_epoch's address too
    #[available_gas(l2_gas: 285443)] // ceil(1.05 × 271850 measured)
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
