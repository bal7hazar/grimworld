//! Lots of the auction house and direct trades (design/16; SPK-11 §6). Ids come from counters
//! with views (`lot_count`, `trade_count`), so that the indexer detects a missing event.
//! Layouts: docs/architecture/ENG-01-interfaces.md, *Market storage*.

use grimworld_logic::packing::{
    Lanes32, P104, P112, P32, P40, P48, P56, P64, P8, P88, P96, byte_at, join, low_field, split,
    u16_at, u32_at,
};

/// Lot states (`Lot.state`).
pub const LOT_OPEN: u8 = 1;
pub const LOT_SOLD: u8 = 2;
pub const LOT_WITHDRAWN: u8 = 3;
pub const LOT_RETURNED: u8 = 4;

/// What a lot sells (`Lot.kind`): a balance (item id) or an equipment entity.
pub const BALANCE: u8 = 0;
pub const EQUIPMENT: u8 = 1;

/// A lot, in one felt; its goods are escrowed by the hub while it is open (design/16).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Lot {
    /// bits 0-63: the price, gold
    pub price: u64,
    /// bits 64-127: the block time it expires at (design/16: 7 days)
    pub expiry: u64,
    /// bits 128-159: the seller's account
    pub seller: u32,
    /// bits 160-167: 1, 10 or 100 (equipment: 1)
    pub lot_size: u8,
    /// bits 168-175: `LOT_OPEN` … `LOT_RETURNED`
    pub state: u8,
    /// bits 176-183: `BALANCE` or `EQUIPMENT`
    pub kind: u8,
    /// bits 184-215: the item id, or the equipment entity
    pub item: u32,
    /// bits 216-231: the market (one world market, id 1; design/16 keeps the id for later)
    pub market: u16,
}

pub impl LotStorePacking of starknet::storage_access::StorePacking<Lot, felt252> {
    fn pack(value: Lot) -> felt252 {
        join(
            value.price.into() + value.expiry.into() * P64,
            value.seller.into()
                + value.lot_size.into() * P32
                + value.state.into() * P40
                + value.kind.into() * P48
                + value.item.into() * P56
                + value.market.into() * P88,
        )
    }
    fn unpack(value: felt252) -> Lot {
        let (low, high) = split(value);
        let (expiry, price) = DivRem::div_rem(low, P64.try_into().unwrap());
        Lot {
            price: price.try_into().unwrap(),
            expiry: expiry.try_into().unwrap(),
            seller: low_field(high, P32.try_into().unwrap()).try_into().unwrap(),
            lot_size: byte_at(high, P32),
            state: byte_at(high, P40),
            kind: byte_at(high, P48),
            item: u32_at(high, P56),
            market: u16_at(high, P88),
        }
    }
}

/// An account's open lots ("my lots" is a view call, SPK-11): three lot ids per page, the count
/// of open lots on page 0 (bits 192-199).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct SellerPage {
    pub lots: [u64; 3],
    pub count: u8,
}

pub impl SellerPageStorePacking of starknet::storage_access::StorePacking<SellerPage, felt252> {
    fn pack(value: SellerPage) -> felt252 {
        let [a, b, c] = value.lots;
        join(a.into() + b.into() * P64, c.into() + value.count.into() * P64)
    }
    fn unpack(value: felt252) -> SellerPage {
        let (low, high) = split(value);
        let (b, a) = DivRem::div_rem(low, P64.try_into().unwrap());
        let (count, c) = DivRem::div_rem(high, P64.try_into().unwrap());
        SellerPage {
            lots: [a.try_into().unwrap(), b.try_into().unwrap(), c.try_into().unwrap()],
            count: low_field(count, P8.try_into().unwrap()).try_into().unwrap(),
        }
    }
}

/// Trade states (`TradeHead.state`) and the outcomes of `TradeClosed`.
pub const TRADE_OPEN: u8 = 1;
pub const TRADE_DONE: u8 = 0;
pub const TRADE_DECLINED: u8 = 1;
pub const TRADE_CANCELLED: u8 = 2;

#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct TradeHead {
    /// bits 0-31: the adventurer who opened it
    pub inviter: u32,
    /// bits 32-63: the account invited (the key of `TradeOpened`)
    pub invited_account: u32,
    /// bits 64-95: the invited adventurer, once it has put its side
    pub invited: u32,
    /// bits 96-103: `TRADE_OPEN`, or closed (0)
    pub state: u8,
    /// bits 104-111: bit 0 the inviter confirmed, bit 1 the invited one
    pub confirmations: u8,
    /// bits 112-119: +1 at every change of a side; a confirmation names the revision it saw
    pub revision: u8,
    /// bits 128-191: the block time it was opened at (expiry: 10 minutes later)
    pub opened_at: u64,
}

pub impl TradeHeadStorePacking of starknet::storage_access::StorePacking<TradeHead, felt252> {
    fn pack(value: TradeHead) -> felt252 {
        join(
            value.inviter.into()
                + value.invited_account.into() * P32
                + value.invited.into() * P64
                + value.state.into() * P96
                + value.confirmations.into() * P104
                + value.revision.into() * P112,
            value.opened_at.into(),
        )
    }
    fn unpack(value: felt252) -> TradeHead {
        let (low, high) = split(value);
        TradeHead {
            inviter: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            invited_account: u32_at(low, P32),
            invited: u32_at(low, P64),
            state: byte_at(low, P96),
            confirmations: byte_at(low, P104),
            revision: byte_at(low, P112),
            opened_at: low_field(high, P64.try_into().unwrap()).try_into().unwrap(),
        }
    }
}

/// Gold and up to two balances one side puts in.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct TradeMoney {
    /// bits 0-63
    pub gold: u64,
    /// bits 64-95, 96-127: first balance
    pub item0: u32,
    pub amount0: u32,
    /// bits 128-159, 160-191: second balance
    pub item1: u32,
    pub amount1: u32,
}

pub impl TradeMoneyStorePacking of starknet::storage_access::StorePacking<TradeMoney, felt252> {
    fn pack(value: TradeMoney) -> felt252 {
        join(
            value.gold.into() + value.item0.into() * P64 + value.amount0.into() * P96,
            value.item1.into() + value.amount1.into() * P32,
        )
    }
    fn unpack(value: felt252) -> TradeMoney {
        let (low, high) = split(value);
        TradeMoney {
            gold: low_field(low, P64.try_into().unwrap()).try_into().unwrap(),
            item0: u32_at(low, P64),
            amount0: u32_at(low, P96),
            item1: low_field(high, P32.try_into().unwrap()).try_into().unwrap(),
            amount1: u32_at(high, P32),
        }
    }
}

/// One side: up to seven equipment entities, gold and two balances.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct TradeSide {
    pub goods: Lanes32,
    pub money: TradeMoney,
}

/// Five consecutive slots under a trade id.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Trade {
    pub head: TradeHead,
    pub inviter: TradeSide,
    pub invited: TradeSide,
}

#[generate_trait]
pub impl LotImpl of LotTrait {
    /// The market key of SPK-11 (*scope 5*), one felt, frozen with `LotPosted`:
    /// - a balance: its item id;
    /// - equipment: `2^40 + base × 2^16 + requirement × 2^8 + rarity × 2 + identified`;
    /// - a boss item: `2^41 + base` (each boss item is its own key).
    fn market_key(
        kind: u8, item: u32, base: u16, requirement: u8, rarity: u8, identified: bool, boss: bool,
    ) -> felt252 {
        if kind == BALANCE {
            return item.into();
        }
        if boss {
            return 0x20000000000 + base.into();
        }
        let flag: felt252 = if identified {
            1
        } else {
            0
        };
        0x10000000000
            + base.into() * 0x10000
            + requirement.into() * 0x100
            + rarity.into() * 2
            + flag
    }
}

/// The records of `Market` are what docs/architecture/ENG-01-interfaces.md says: each record's size
/// in slots, the bit offsets of its packed records, `LIVE` included, and the market key. Here since
/// ENG-R1b (D-167); the variables' names and keys are checked in `store::market_layout_tests`.
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::LIVE;
    use starknet::storage_access::StorePacking;
    use super::{BALANCE, EQUIPMENT, Lot, LotTrait, SellerPage, Trade, TradeHead, TradeMoney};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_record_sizes() {
        assert(starknet::Store::<Trade>::size() == 5, 'trade: 5 slots');
        assert(starknet::Store::<Lot>::size() == 1, 'lot: 1 slot');
    }

    #[test]
    #[available_gas(l2_gas: 197715)] // ceil(1.05 × 188300 measured)
    fn test_market_layout() {
        let lot = Lot {
            price: 0xFFFFFFFFFFFFFFFF,
            expiry: 0xFFFFFFFFFFFFFFFF,
            seller: 0xFFFFFFFF,
            lot_size: 100,
            state: 4,
            kind: EQUIPMENT,
            item: 0xFFFFFFFF,
            market: 0xFFFF,
        };
        let word = StorePacking::<Lot, felt252>::pack(lot);
        assert(StorePacking::<Lot, felt252>::unpack(word) == lot, 'lot trip');
        let seller = Lot { seller: 1, ..Default::default() };
        assert(StorePacking::<Lot, felt252>::pack(seller) == TWO_128 + LIVE, 'seller at bit 128');

        let page = SellerPage { lots: [1, 0xFFFFFFFFFFFFFFFF, 3], count: 20 };
        let word = StorePacking::<SellerPage, felt252>::pack(page);
        assert(StorePacking::<SellerPage, felt252>::unpack(word) == page, 'seller page trip');

        let head = TradeHead {
            inviter: 1,
            invited_account: 2,
            invited: 3,
            state: 1,
            confirmations: 3,
            revision: 0xFF,
            opened_at: 0xFFFFFFFFFFFFFFFF,
        };
        let word = StorePacking::<TradeHead, felt252>::pack(head);
        assert(StorePacking::<TradeHead, felt252>::unpack(word) == head, 'trade head trip');

        let money = TradeMoney {
            gold: 0xFFFFFFFFFFFFFFFF, item0: 1, amount0: 2, item1: 0xFFFFFFFF, amount1: 0xFFFFFFFF,
        };
        let word = StorePacking::<TradeMoney, felt252>::pack(money);
        assert(StorePacking::<TradeMoney, felt252>::unpack(word) == money, 'money trip');

        // SPK-11 *scope 5*: balances by item id; equipment by base, requirement, rarity,
        // identified;
        // boss items one key each.
        assert(LotTrait::market_key(BALANCE, 77, 0, 0, 0, false, false) == 77, 'balance key');
        assert(
            LotTrait::market_key(EQUIPMENT, 5, 12, 9, 3, true, false) == 0x10000000000
                + 12 * 0x10000
                + 9 * 0x100
                + 3 * 2
                + 1,
            'equipment key',
        );
        assert(
            LotTrait::market_key(EQUIPMENT, 5, 40, 9, 4, true, true) == 0x20000000000 + 40,
            'boss key',
        );
    }
}
