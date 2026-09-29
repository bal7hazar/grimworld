/// Emits the four events of `Market`, one per call, with the arguments as fields.
#[starknet::interface]
pub trait IMarketEmitter<T> {
    fn lot_posted(
        ref self: T,
        market_key: felt252,
        lot_size: u8,
        lot: u64,
        price: u64,
        expiry: u64,
        equipment: u32,
        modifiers: felt252,
    );
    fn lot_closed(ref self: T, lot: u64, sold: bool);
    fn trade_opened(ref self: T, invited: u32, trade: u64, inviter: u32);
    fn trade_closed(ref self: T, trade: u64, outcome: u8);
}

#[starknet::contract]
pub mod MarketEmitter {
    use grimworld_persistent::events::{LotClosed, LotPosted, TradeClosed, TradeOpened};

    #[storage]
    struct Storage {}

    /// The variants of `Market::Event`, in its order, over its event structs: the first key is the
    /// selector of the variant's name, as in `Market`.
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LotPosted: LotPosted,
        LotClosed: LotClosed,
        TradeOpened: TradeOpened,
        TradeClosed: TradeClosed,
    }

    #[abi(embed_v0)]
    impl MarketEmitterImpl of super::IMarketEmitter<ContractState> {
        fn lot_posted(
            ref self: ContractState,
            market_key: felt252,
            lot_size: u8,
            lot: u64,
            price: u64,
            expiry: u64,
            equipment: u32,
            modifiers: felt252,
        ) {
            self.emit(LotPosted { market_key, lot_size, lot, price, expiry, equipment, modifiers });
        }

        fn lot_closed(ref self: ContractState, lot: u64, sold: bool) {
            self.emit(LotClosed { lot, sold });
        }

        fn trade_opened(ref self: ContractState, invited: u32, trade: u64, inviter: u32) {
            self.emit(TradeOpened { invited, trade, inviter });
        }

        fn trade_closed(ref self: ContractState, trade: u64, outcome: u8) {
            self.emit(TradeClosed { trade, outcome });
        }
    }
}
