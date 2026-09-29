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
    );
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Hub {
    use core::num::traits::Zero;
    use grimworld_logic::interface::{IResults, Results};
    use grimworld_logic::packing::{Bitmap, Counter, Lanes32};
    use grimworld_logic::types::InstanceId;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::events::{
        AdventurerLocated, DungeonCleared, RankReached, TitleDisplayed, TrialPassed,
    };
    use crate::models::account::Account;
    use crate::models::adventurer::Adventurer;
    use crate::models::item::{Gold, Grimoire, Item, RiftBoard};
    use super::{NOT_IMPLEMENTED, VERSION};

    /// docs/architecture/ENG-01-interfaces.md, *Hub storage*. quiver's components (quests,
    /// achievements) add their own storage when ARC's packages are embedded.
    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        pub registry: ContractAddress,
        pub instances: ContractAddress,
        pub market: ContractAddress,
        pub fate: ContractAddress,
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
        fn register(ref self: ContractState) -> u32 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_account_owner(ref self: ContractState, account_id: u32, owner: ContractAddress) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn create_adventurer(ref self: ContractState, name: felt252, profession: u8) -> u32 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn delete_adventurer(ref self: ContractState, adventurer_id: u32) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_build(
            ref self: ContractState,
            adventurer_id: u32,
            build: felt252,
            belt: felt252,
            equipped: felt252,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn enter(ref self: ContractState, adventurer_id: u32, gate: u16) -> InstanceId {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn enter_rift(ref self: ContractState, adventurer_id: u32, index: u8) -> InstanceId {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn travel(ref self: ContractState, adventurer_id: u32, hub: u16) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
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
        fn account_of(self: @ContractState, owner: ContractAddress) -> u32 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn account(self: @ContractState, account_id: u32) -> (ContractAddress, felt252, Span<u32>) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn adventurer(self: @ContractState, adventurer_id: u32) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
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
        fn report(ref self: ContractState, results: Results) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
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
        /// The registered contracts, the randomness provider among them: configuration, never a
        /// constant of the code (ADR-0001, ADR-0002). Administrator only.
        fn set_contracts(
            ref self: ContractState,
            registry: ContractAddress,
            instances: ContractAddress,
            market: ContractAddress,
            fate: ContractAddress,
        ) {
            assert(get_caller_address() == self.admin.read(), super::NOT_ADMIN);
            self.registry.write(registry);
            self.instances.write(instances);
            self.market.write(market);
            self.fate.write(fate);
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
    #[available_gas(l2_gas: 270669)] // ceil(1.05 × 257780 measured)
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
    }
}
