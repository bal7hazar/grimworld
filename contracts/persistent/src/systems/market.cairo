//! `Market`: the auction house and direct trades (design/16), a contract of its own so that the
//! hub's class stays under the size limit (ADR-0007). It holds lots and trades; the goods stay in
//! the hub, escrowed through `IHubMarket`. ENG-01 freezes its interface, storage and events; every
//! entrypoint reverts with `'not implemented'` until its lot writes it.

use starknet::{ClassHash, ContractAddress};

pub const VERSION: felt252 = 'grimworld-market-1';
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';

#[starknet::interface]
pub trait IMarket<T> {
    /// A lot of 1, 10 or 100 of a balance (`kind` 0, `item` its id) or one equipment entity
    /// (`kind` 1). Tin rank or above, 10 + rank lots per account, 2 % fee never refunded;
    /// emits `LotPosted`; returns the lot id (the next of `lot_count`).
    fn post_lot(
        ref self: T, adventurer_id: u32, kind: u8, item: u32, lot_size: u8, price: u64,
    ) -> u64;
    /// Pays `price` (it must be the asked one) into the seller's vault; the goods go to the buyer's
    /// vault. Refused when expired or not open (the "lost race", design/16). Emits `LotClosed`.
    fn buy_lot(ref self: T, adventurer_id: u32, lot: u64, price: u64);
    /// The seller takes an open lot back. Emits `LotClosed`.
    fn withdraw_lot(ref self: T, adventurer_id: u32, lot: u64);
    /// Anyone returns an expired lot to its seller's vault (lazy expiry). Emits `LotClosed`.
    fn return_lot(ref self: T, lot: u64);

    /// Opens a trade with an account whose adventurer is in the same hub; emits `TradeOpened`;
    /// returns the trade id (the next of `trade_count`).
    fn open_trade(ref self: T, adventurer_id: u32, invited: u32) -> u64;
    /// Puts one side (`goods`: a `Lanes32` of equipment; `money`: a `TradeMoney`); resets both
    /// confirmations and raises the revision.
    fn set_trade_side(ref self: T, adventurer_id: u32, trade: u64, goods: felt252, money: felt252);
    /// Confirms the revision seen; the second confirmation swaps everything, all or nothing.
    fn confirm_trade(ref self: T, adventurer_id: u32, trade: u64, revision: u8);
    /// The invited account declines (emits `TradeClosed` 1).
    fn decline_trade(ref self: T, trade: u64);
    /// The inviter cancels (emits `TradeClosed` 2).
    fn cancel_trade(ref self: T, adventurer_id: u32, trade: u64);

    /// `Lot`, in its stored layout.
    fn lot(self: @T, lot: u64) -> felt252;
    /// Lots ever posted: the last lot id (SPK-11 §6: the indexer checks it before serving).
    fn lot_count(self: @T) -> u64;
    /// Lots open now (SPK-11 §6: detects a close without `LotClosed`).
    fn open_lot_count(self: @T) -> u64;
    fn lots_of(self: @T, account_id: u32) -> Span<u64>;
    /// The five words of `Trade`, in order.
    fn trade(self: @T, trade: u64) -> Span<felt252>;
    /// Trades ever opened: the last trade id (SPK-11 §6).
    fn trade_count(self: @T) -> u64;
}

#[starknet::interface]
pub trait IMarketAdmin<T> {
    fn version(self: @T) -> felt252;
    fn set_contracts(ref self: T, hub: ContractAddress, registry: ContractAddress);
    fn set_admin(ref self: T, admin: ContractAddress);
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Market {
    use starknet::storage::{Map, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use crate::events::{LotClosed, LotPosted, TradeClosed, TradeOpened};
    use crate::models::market::{Lot, SellerPage, Trade};
    use super::{NOT_IMPLEMENTED, VERSION};

    /// docs/architecture/ENG-01-interfaces.md, *Market storage*.
    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        pub hub: ContractAddress,
        pub registry: ContractAddress,
        pub lot_count: u64,
        pub open_lot_count: u64,
        pub lots: Map<u64, Lot>,
        /// `(account, page)`: its open lots, three per page, the count on page 0.
        pub seller_lots: Map<(u32, u8), SellerPage>,
        pub trade_count: u64,
        /// Five slots each.
        pub trades: Map<u64, Trade>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LotPosted: LotPosted,
        LotClosed: LotClosed,
        TradeOpened: TradeOpened,
        TradeClosed: TradeClosed,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        hub: ContractAddress,
        registry: ContractAddress,
    ) {
        self.admin.write(admin);
        self.hub.write(hub);
        self.registry.write(registry);
    }

    #[abi(embed_v0)]
    impl MarketImpl of super::IMarket<ContractState> {
        fn post_lot(
            ref self: ContractState,
            adventurer_id: u32,
            kind: u8,
            item: u32,
            lot_size: u8,
            price: u64,
        ) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn buy_lot(ref self: ContractState, adventurer_id: u32, lot: u64, price: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn withdraw_lot(ref self: ContractState, adventurer_id: u32, lot: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn return_lot(ref self: ContractState, lot: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn open_trade(ref self: ContractState, adventurer_id: u32, invited: u32) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_trade_side(
            ref self: ContractState, adventurer_id: u32, trade: u64, goods: felt252, money: felt252,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn confirm_trade(ref self: ContractState, adventurer_id: u32, trade: u64, revision: u8) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn decline_trade(ref self: ContractState, trade: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn cancel_trade(ref self: ContractState, adventurer_id: u32, trade: u64) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn lot(self: @ContractState, lot: u64) -> felt252 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn lot_count(self: @ContractState) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn open_lot_count(self: @ContractState) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn lots_of(self: @ContractState, account_id: u32) -> Span<u64> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn trade(self: @ContractState, trade: u64) -> Span<felt252> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn trade_count(self: @ContractState) -> u64 {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl MarketAdminImpl of super::IMarketAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
        fn set_contracts(ref self: ContractState, hub: ContractAddress, registry: ContractAddress) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }
}

/// The storage layout of `Market` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address.
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use super::Market;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    #[test]
    #[available_gas(l2_gas: 65909)] // ceil(1.05 × 62770 measured)
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
