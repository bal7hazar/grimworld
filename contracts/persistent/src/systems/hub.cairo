//! `Hub`, the contract of the persistent domain's state (ADR-0001, ADR-0007): accounts,
//! adventurers, inventory and vault, progress, grimoire, Rifts, the hub's services, and the
//! receiving end of the results interface. ENG-01 freezes its interface, storage and events;
//! every entrypoint reverts with `'not implemented'` until its lot writes it.
//! docs/architecture/ENG-01-interfaces.md.

use core::num::traits::Zero;
use grimworld_logic::types::InstanceId;
use starknet::{ClassHash, ContractAddress};

pub const VERSION: felt252 = 'grimworld-hub-1';
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';
pub use errors::{NOT_ADMIN, NOT_INSTANCES, ZERO_ADMIN};

/// The refusals of `Hub`'s access control (ADR-0007, *Access control*).
pub mod errors {
    /// An administrator's entrypoint called by anyone else.
    pub const NOT_ADMIN: felt252 = 'not admin';
    /// `set_admin` to the zero address would leave the role to nobody.
    pub const ZERO_ADMIN: felt252 = 'admin is zero';
    /// `report` or `barter` called by anyone but the registered `Instances`.
    pub const NOT_INSTANCES: felt252 = 'not instances';
}

/// The checks of `Hub`'s callers that are not an adventurer's owner (those are
/// `AdventurerAssert::assert_owned_in_hub`'s).
#[generate_trait]
pub impl HubAssert of HubAssertTrait {
    /// The caller is the administrator.
    #[inline(always)]
    fn assert_admin(caller: ContractAddress, admin: ContractAddress) {
        assert(caller == admin, errors::NOT_ADMIN);
    }

    /// A new administrator is not the zero address.
    #[inline(always)]
    fn assert_admin_not_zero(admin: ContractAddress) {
        assert(admin.is_non_zero(), errors::ZERO_ADMIN);
    }

    /// The caller is the registered `Instances`.
    #[inline(always)]
    fn assert_instances(caller: ContractAddress, instances: ContractAddress) {
        assert(caller == instances, errors::NOT_INSTANCES);
    }
}

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
    use grimworld_logic::content::{GATE, MODIFIER, REGION, exists};
    use grimworld_logic::interface::{
        IFlattenLibraryDispatcherTrait, IFlattenLibraryLibraryDispatcher, IInstanceEntryDispatcher,
        IInstanceEntryDispatcherTrait, IRegistryReadDispatcher, IRegistryReadDispatcherTrait,
        IResults, Results, facts,
    };
    use grimworld_logic::models::gate::{Gate, GateAssert, GateRecord};
    use grimworld_logic::models::item::ItemTrait;
    use grimworld_logic::models::region::{Region, RegionRecord};
    use grimworld_logic::models::skill::SkillTrait;
    use grimworld_logic::packing::{Bitmap, Counter, Lanes32};
    use grimworld_logic::professions::ProfessionAssert;
    use grimworld_logic::types::{InstanceId, Outcome};
    use starknet::storage::Map;
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::events::{
        AdventurerLocated, DungeonCleared, RankReached, TitleDisplayed, TrialPassed,
    };
    use crate::models::account::{Account, AccountAssert, OwnerTrait, StoredRecordTrait};
    use crate::models::adventurer::{
        Adventurer, AdventurerAssert, AdventurerTrait, BeltAssert, BeltTrait, BuildAssert,
        BuildTrait, EquippedAssert, NO_ELITE, StoredBuildTrait, StoredCore, StoredCoreTrait,
        StoredPlace, StoredPlaceTrait,
    };
    use crate::models::balance::BalanceTrait;
    use crate::models::item::{
        Equipment, Gold, Grimoire, Item, ItemBaseAssert, ItemBaseTrait, RiftBoard,
    };
    use crate::models::rules_epoch::{RulesEpoch, RulesEpochTrait};
    use crate::models::snapshot::{StoredSnapshot, StoredSnapshotAssert, StoredSnapshotTrait};
    use crate::store::HubStoreTrait;
    use crate::types::results::{ResultsAssert, ResultsTrait};
    use super::{HubAssert, NOT_IMPLEMENTED, START_REGION, VERSION};

    /// docs/architecture/ENG-01-interfaces.md, *Hub storage*. quiver's components (quests,
    /// achievements) add their own storage when ARC's packages are embedded. Read and written only
    /// through the store (`crate::store::HubStore`).
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
        /// The rules epoch (D-169, `models::rules_epoch`): how many times `set_contracts` changed
        /// `flatten` or `registry`, modulo 512 (9 bits of the stored kit word); 0 at deployment. A
        /// stored snapshot carries the one it was flattened under, and `enter` refuses another.
        pub rules_epoch: RulesEpoch,
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
        self.initialize(admin, registry, instances, market, fate);
    }

    #[abi(embed_v0)]
    impl HubImpl of super::IHub<ContractState> {
        /// One account per address, with its three slots (D-33). Writes (ENG-01 §9.3): the
        /// account's two words and `account_of[caller]` new, `next_account` overwritten.
        fn register(ref self: ContractState) -> u32 {
            let caller = get_caller_address();
            AccountAssert::assert_no_account(self.get_account_id(caller));
            let account_id = self.new_account_id();
            self.set_account(account_id, caller, StoredRecordTrait::new());
            self.set_account_id(caller, account_id);
            account_id
        }

        /// A-7: the current owner hands the account over; the adventurers stay. The old owner's
        /// `account_of` is zeroed (E-19). An adventurer inside an instance gets the new owner as
        /// controller (ENG-01 §1.2). Bound: the account's adventurers, at most its slots (one page
        /// of seven, ENG-01 §4.5).
        fn set_account_owner(ref self: ContractState, account_id: u32, owner: ContractAddress) {
            let caller = get_caller_address();
            let (current, record) = self.get_account(account_id);
            AccountAssert::assert_transfer(current, caller, owner, self.get_account_id(owner));
            self.set_owner(account_id, owner);
            self.set_account_id(owner, account_id);
            self.set_account_id(caller, 0);

            let (_, count) = record.counts();
            if count == 0 {
                return;
            }
            let instances = IInstanceEntryDispatcher { contract_address: self.get_instances() };
            for adventurer_id in self.get_adventurer_ids(account_id, count) {
                if self.get_place(*adventurer_id).is_inside() {
                    instances.set_controller(*adventurer_id, owner);
                }
            }
        }

        /// D-32: a name and a primary profession; placed in region 1's town, read from the
        /// registry (D-144: one `record` call), unlocked, at level 1, rank Wood.
        /// Writes (ENG-01 §9.3): the adventurer's six words new, its lane of the account's list
        /// (new on a page's first lane), the account's record and `next_adventurer` overwritten.
        fn create_adventurer(ref self: ContractState, name: felt252, profession: u8) -> u32 {
            let account_id = self.get_account_id(get_caller_address());
            AccountAssert::assert_has_account(account_id);
            AdventurerAssert::assert_valid_name(name);
            ProfessionAssert::assert_playable(profession);
            let record = self.get_account_record(account_id);
            let (slots, count) = record.counts();
            AccountAssert::assert_free_slot(slots, count);

            let adventurer_id = self.new_adventurer_id();
            let (core, place, build) = AdventurerTrait::new(
                account_id, profession, self.start_hub(),
            );
            self.set_adventurer(adventurer_id, core, place, build, name);
            self.add_adventurer_id(account_id, count, adventurer_id);
            self.set_account_record(account_id, record.with_adventurer());
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
            let (_, _, pack_lanes) = core.fields();
            AdventurerAssert::assert_emptied(
                pack_lanes,
                self.holds_equipment(adventurer_id),
                self.wears_equipment(adventurer_id),
                @self.get_gold(OwnerTrait::pack(adventurer_id)),
            );
            let record = self.get_account_record(account_id);
            let (_, count) = record.counts();
            self.remove_adventurer_id(account_id, count, adventurer_id);
            self.set_account_record(account_id, record.without_adventurer());
            self.set_core(adventurer_id, core.deleted());
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
            let (_, level, rank, primary) = core.profile();
            let secondary = core.secondary();
            let sent = StoredBuildTrait::new(build, belt, equipped);
            let value = sent.build();
            value.assert_attributes(primary, secondary, level, rank);
            value.assert_distinct();
            let (items, counts) = sent.belt();
            BeltAssert::assert_counts(items, counts);
            let entities = sent.equipped().lanes.span();
            EquippedAssert::assert_distinct(entities);

            // What the registry is asked, in order: the bar's skills, the belt's distinct items,
            // the distinct modifiers worn.
            let known = self.knows_skills(adventurer_id, value.bar.span());
            let mut requests = value.request();
            let skills = requests.len();
            BeltTrait::request(items, ref requests);
            let belt_items = requests.len();
            let pack = OwnerTrait::pack(adventurer_id);
            for (item, count) in BalanceTrait::merge(items, counts) {
                BeltAssert::assert_held(self.get_balance(pack, item), count);
            }
            let Equipment { bases, worn, modifiers, personalised } = self.get_equipment(entities);
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
                contract_address: self.get_registry(),
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
                class_hash: self.get_flatten(),
            }
                .words(loadout, worn.span(), modifiers.span(), parts.slice(at, parts.len() - at));

            self.set_adventurer_build(adventurer_id, sent);
            let epoch = StoredSnapshotTrait::epoch(inputs, self.get_rules_epoch().value);
            self.set_snapshot(adventurer_id, StoredSnapshotTrait::new(stats, bar, kit, epoch));
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
            let (_, hub, _, _) = place.fields();
            let (_, level, rank, _) = core.profile();
            let (_, inputs, parts) = IRegistryReadDispatcher {
                contract_address: self.get_registry(),
            }
                .bundle(array![(GATE, gate.into())].span());
            AdventurerAssert::assert_gate(exists(parts));
            let record: Gate = GateRecord::unpack(parts);
            record.assert_enterable(hub, rank);

            let stored = self.get_snapshot(adventurer_id);
            let epoch = StoredSnapshotTrait::epoch(inputs, self.get_rules_epoch().value);
            StoredSnapshotAssert::assert_fresh(stored.kit, epoch);
            StoredSnapshotAssert::assert_level(stored.stats, level);
            let (items, counts) = self.get_belt(adventurer_id);
            let snapshot = stored.words(epoch, counts);

            let reserve = BalanceTrait::merge(items, counts);
            let (_, emptied) = self
                .change_balances(OwnerTrait::pack(adventurer_id), reserve.span(), false);
            if emptied != 0 {
                self.set_core(adventurer_id, core.with_pack_lanes(0, emptied));
            }
            let instance = IInstanceEntryDispatcher { contract_address: self.get_instances() }
                .create(adventurer_id, get_caller_address(), gate, snapshot, array![].span());
            self.set_place(adventurer_id, place.entered(instance));
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
            AdventurerAssert::assert_unlocked(@place, hub);
            self.set_place(adventurer_id, place.located(hub));
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
            self.get_account_id(owner)
        }
        /// The record as stored (0 for an account that does not exist), and the ids of its
        /// adventurers not deleted, in the list's order.
        fn account(self: @ContractState, account_id: u32) -> (ContractAddress, felt252, Span<u32>) {
            let (owner, record) = self.get_account(account_id);
            let (_, count) = record.counts();
            (owner, record.word, self.get_adventurer_ids(account_id, count))
        }
        /// The six words as stored (six 0 for an id never created); a deleted adventurer keeps
        /// its words, `DELETED` in `core.status`.
        fn adventurer(self: @ContractState, adventurer_id: u32) -> Span<felt252> {
            self.get_adventurer_words(adventurer_id)
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
            HubAssert::assert_instances(get_caller_address(), self.get_instances());
            results.assert_settled();
            let adventurer_id = *results.contributors[0];
            let place = self.get_place(adventurer_id);
            AdventurerAssert::assert_in_instance(@place, results.instance_id);

            let mut credit = if results.closes() {
                let (items, _) = self.get_belt(adventurer_id);
                BalanceTrait::merge(items, results.belt)
            } else {
                array![]
            };
            for balance in results.balances {
                credit.append(*balance);
            }
            let pack = OwnerTrait::pack(adventurer_id);
            let (filled, _) = self.change_balances(pack, credit.span(), true);
            if filled != 0 || results.experience != 0 {
                let core = self.get_core(adventurer_id).with_pack_lanes(filled, 0);
                self.set_core(adventurer_id, core.with_experience(results.experience));
            }
            if results.gold != 0 {
                let gold = self.get_gold(pack);
                self.set_gold(pack, Gold { amount: gold.amount + results.gold });
            }
            if results.experience != 0 {
                for other in results.contributors.slice(1, results.contributors.len() - 1) {
                    let core = self.get_core(*other);
                    self.set_core(*other, core.with_experience(results.experience));
                }
            }

            match results.outcome {
                Outcome::Open => {},
                Outcome::Moved => self.set_place(adventurer_id, place.moved(results.next)),
                _ => {
                    let (_, _, last_hub, _) = place.fields();
                    let hub = if results.hub != 0 {
                        results.hub
                    } else {
                        last_hub
                    };
                    let mut located = place.located(hub);
                    if results.facts & facts::HUB_REACHED != 0 {
                        located = located.unlocked(results.location);
                    }
                    self.set_place(adventurer_id, located);
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
        /// ENG-01 §1.3). A class hash or a registry other than the stored ones raises the rules
        /// epoch (D-169: the configuration the flattening depends on), which stales every stored
        /// snapshot; the same two leave it. Administrator only.
        fn set_contracts(
            ref self: ContractState,
            registry: ContractAddress,
            instances: ContractAddress,
            market: ContractAddress,
            fate: ContractAddress,
            flatten: ClassHash,
        ) {
            HubAssert::assert_admin(get_caller_address(), self.get_administrator());
            let moves = RulesEpochTrait::moves(
                flatten, self.get_flatten(), registry, self.get_registry(),
            );
            self.set_registered(registry, instances, market, fate, flatten);
            if moves {
                self.set_rules_epoch(self.get_rules_epoch().next());
            }
        }
        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            HubAssert::assert_admin(get_caller_address(), self.get_administrator());
            HubAssert::assert_admin_not_zero(admin);
            self.set_administrator(admin);
        }
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        /// The check of every entrypoint that names an adventurer (ADR-0007, *Access control*;
        /// ENG-01 §1.2): three reads (`core` and `place`, the account's owner), then
        /// `AdventurerAssert::assert_owned_in_hub`, one refusal per case. Returns `(account id,
        /// core, place)`.
        fn owned_in_hub(
            self: @ContractState, adventurer_id: u32,
        ) -> (u32, StoredCore, StoredPlace) {
            let (core, place) = self.get_core_place(adventurer_id);
            let (account_id, status, _) = core.fields();
            let owner = self.get_owner(account_id);
            AdventurerAssert::assert_owned_in_hub(
                account_id, status, @place, owner, get_caller_address(),
            );
            (account_id, core, place)
        }

        /// Region 1's town (D-144), read from the registry: one `record` call. Refuses when the
        /// region is missing; a town id of 64 or more when it is placed (`unlocked` holds bits
        /// 0-63).
        fn start_hub(self: @ContractState) -> u16 {
            let parts = IRegistryReadDispatcher { contract_address: self.get_registry() }
                .record(REGION, START_REGION);
            AdventurerAssert::assert_start_region(exists(parts));
            let region: Region = RegionRecord::unpack(parts);
            region.town
        }
    }
}
