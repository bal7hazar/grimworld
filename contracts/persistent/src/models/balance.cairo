//! Balances (design/07: everything counted, not slotted): pages of seven `u32` lanes (`Lanes32`)
//! under `(owner key, page)`, item `7 page + lane` (docs/architecture/ENG-01-interfaces.md, *Hub
//! storage*). A page is read and written as its stored word, changed lane by lane by arithmetic;
//! a page never written reads 0 and is written with `LIVE`.

use grimworld_logic::packing::{LIVE, P32, P64, P96, low_field, split, u32_at};
use super::account::AdventurerListTrait;

/// Items on a page: lane `item % 7` of page `item / 7`.
pub const ITEMS_PER_PAGE: u32 = 7;

pub mod errors {
    /// A debit larger than the balance (the belt's reserve at entry: the pack must hold it).
    pub const NOT_ENOUGH: felt252 = 'balance: not enough';
    /// A credit past a `u32`.
    pub const OVERFLOW: felt252 = 'balance: overflow';
}

#[generate_trait]
pub impl BalanceImpl of BalanceTrait {
    /// `(page, lane)` of an item.
    #[inline(always)]
    fn at(item: u32) -> (u32, u8) {
        let (page, lane) = DivRem::div_rem(item, ITEMS_PER_PAGE.try_into().unwrap());
        (page, lane.try_into().unwrap())
    }

    /// The balance in lane `lane` (0 to 6) of a stored page.
    fn amount(page: felt252, lane: u8) -> u32 {
        let (low, high) = split(page);
        match lane {
            0 => low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            1 => u32_at(low, P32),
            2 => u32_at(low, P64),
            3 => u32_at(low, P96),
            4 => low_field(high, P32.try_into().unwrap()).try_into().unwrap(),
            5 => u32_at(high, P32),
            6 => u32_at(high, P64),
            _ => core::panic_with_felt252('lane above 6'),
        }
    }

    /// The stored page with `amount` more in `lane`; `LIVE` set on a page never written. Returns
    /// the page and whether the lane was empty before (a pack lane filled, `pack_lanes`).
    fn credit(page: felt252, lane: u8, amount: u32) -> (felt252, bool) {
        let before = Self::amount(page, lane);
        let total: u64 = before.into() + amount.into();
        assert(total <= 0xFFFFFFFF, errors::OVERFLOW);
        let base = if page == 0 {
            LIVE
        } else {
            page
        };
        (base + amount.into() * AdventurerListTrait::unit(lane), before == 0 && amount != 0)
    }

    /// The stored page with `amount` less in `lane`, refused if the lane holds less. Returns the
    /// page and whether the lane is empty after (a pack lane emptied).
    fn debit(page: felt252, lane: u8, amount: u32) -> (felt252, bool) {
        let before = Self::amount(page, lane);
        assert(before >= amount, errors::NOT_ENOUGH);
        (page - amount.into() * AdventurerListTrait::unit(lane), before != 0 && before == amount)
    }

    /// The belt's slots as balance changes: one `(item, count)` per distinct item, the counts of
    /// slots holding the same item summed (ENG-01 §6: one debit or credit of their sum); a slot
    /// carrying nothing is skipped. At most 4 entries.
    fn merge(items: [u32; 4], counts: [u8; 4]) -> Array<(u32, u32)> {
        let mut out: Array<(u32, u32)> = array![];
        let items = items.span();
        let counts = counts.span();
        for i in 0..4_u32 {
            let item = *items[i];
            let mut total: u32 = 0;
            let mut first = true;
            for j in 0..4_u32 {
                if *items[j] == item && *counts[j] != 0 {
                    if j < i {
                        first = false;
                    }
                    total += (*counts[j]).into();
                }
            }
            if first && *counts[i] != 0 {
                out.append((item, total));
            }
        }
        out
    }
}
