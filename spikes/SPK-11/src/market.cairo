// SPK-11 throwaway: the smallest contract whose events are shaped like the game's indexed ones
// (docs/research/SPK-11-indexer.md §1): a lot posted on the auction house, a lot closed (sold or
// withdrawn), an adventurer located in a hub. No gold moves and nobody's ownership is checked: the
// spike is about the events and the indexer, not the market's rules (design/16, ENG-01).
#[starknet::interface]
pub trait IMarket<T> {
    /// Posts `quantity` of `item` at `price` (per lot); returns the lot id. Emits `LotPosted`.
    fn post(ref self: T, item: u32, quantity: u16, price: u64) -> u64;
    /// The same write as `post`, without the event: measurement only (the gas of the event is
    /// the difference). It breaks the completeness invariant on purpose: the indexer's
    /// reconciliation must detect it (docs/research/SPK-11-indexer.md §6).
    fn post_silent(ref self: T, item: u32, quantity: u16, price: u64) -> u64;
    /// Buys an open lot. Emits `LotClosed { sold: true }`.
    fn buy(ref self: T, lot: u64);
    /// Withdraws an open lot. Emits `LotClosed { sold: false }`.
    fn withdraw(ref self: T, lot: u64);
    /// The same write as `withdraw`, without the event: measurement only.
    fn withdraw_silent(ref self: T, lot: u64);
    /// Places the adventurer in `hub` (0: in no hub). Emits `AdventurerLocated`.
    fn locate(ref self: T, adventurer: u32, hub: u16);
    /// `locate` without the event (nothing else is written): measurement only.
    fn locate_silent(ref self: T, adventurer: u32, hub: u16);
    /// Sets the lot counter, so that the next lot id is `count + 1`: test only, to reach the
    /// boundaries of u64 ids. Emits `LotCountSet`, so the counter never changes unannounced.
    fn skip_lots(ref self: T, count: u64);
    /// The lot: (item, quantity, price, open).
    fn lot(self: @T, lot: u64) -> (u32, u16, u64, bool);
    /// The number of lot ids handed out: the indexer's reconciliation reads it.
    fn lot_count(self: @T) -> u64;
}

#[starknet::contract]
pub mod Market {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    // A lot, packed in one felt: price (64 bits) | quantity (16) | item (32) | open (1).
    #[storage]
    struct Storage {
        lots: Map<u64, felt252>,
        lot_count: u64,
    }

    const OPEN: u128 = 0x1;
    const ITEM: u128 = 0x2; // 2^1
    const QUANTITY: u128 = 0x200000000; // 2^33
    const PRICE: u128 = 0x2000000000000; // 2^49

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LotPosted: LotPosted,
        LotClosed: LotClosed,
        AdventurerLocated: AdventurerLocated,
        LotCountSet: LotCountSet,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LotCountSet {
        pub count: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LotPosted {
        #[key]
        pub item: u32,
        pub lot: u64,
        pub quantity: u16,
        pub price: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LotClosed {
        #[key]
        pub lot: u64,
        pub sold: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdventurerLocated {
        #[key]
        pub hub: u16,
        pub adventurer: u32,
    }

    fn pack(item: u32, quantity: u16, price: u64) -> felt252 {
        let packed: u128 = OPEN
            + item.into() * ITEM
            + quantity.into() * QUANTITY
            + price.into() * PRICE;
        packed.into()
    }

    fn unpack(packed: felt252) -> (u32, u16, u64, bool) {
        let packed: u128 = packed.try_into().unwrap();
        let (rest, open) = DivRem::div_rem(packed, 2_u128.try_into().unwrap());
        let (rest, item) = DivRem::div_rem(rest, 0x100000000_u128.try_into().unwrap());
        let (price, quantity) = DivRem::div_rem(rest, 0x10000_u128.try_into().unwrap());
        (
            item.try_into().unwrap(),
            quantity.try_into().unwrap(),
            price.try_into().unwrap(),
            open == 1,
        )
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn store_lot(ref self: ContractState, item: u32, quantity: u16, price: u64) -> u64 {
            let lot = self.lot_count.read() + 1;
            self.lot_count.write(lot);
            self.lots.write(lot, pack(item, quantity, price));
            lot
        }

        fn close(ref self: ContractState, lot: u64) {
            let packed = self.lots.read(lot);
            let (_, _, _, open) = unpack(packed);
            assert(open, 'lot not open');
            self.lots.write(lot, packed - 1);
        }
    }

    #[abi(embed_v0)]
    impl MarketImpl of super::IMarket<ContractState> {
        fn post(ref self: ContractState, item: u32, quantity: u16, price: u64) -> u64 {
            let lot = self.store_lot(item, quantity, price);
            self.emit(LotPosted { item, lot, quantity, price });
            lot
        }

        fn post_silent(ref self: ContractState, item: u32, quantity: u16, price: u64) -> u64 {
            self.store_lot(item, quantity, price)
        }

        fn buy(ref self: ContractState, lot: u64) {
            self.close(lot);
            self.emit(LotClosed { lot, sold: true });
        }

        fn withdraw(ref self: ContractState, lot: u64) {
            self.close(lot);
            self.emit(LotClosed { lot, sold: false });
        }

        fn withdraw_silent(ref self: ContractState, lot: u64) {
            self.close(lot);
        }

        fn locate(ref self: ContractState, adventurer: u32, hub: u16) {
            self.emit(AdventurerLocated { hub, adventurer });
        }

        fn locate_silent(ref self: ContractState, adventurer: u32, hub: u16) {}

        fn skip_lots(ref self: ContractState, count: u64) {
            self.lot_count.write(count);
            self.emit(LotCountSet { count });
        }

        fn lot(self: @ContractState, lot: u64) -> (u32, u16, u64, bool) {
            unpack(self.lots.read(lot))
        }

        fn lot_count(self: @ContractState) -> u64 {
            self.lot_count.read()
        }
    }
}
