//! Balances (design/07: everything counted, not slotted): pages of seven `u32` lanes (`Lanes32`)
//! under `(owner key, page)`, item `7 page + lane` (docs/architecture/ENG-01-interfaces.md, *Hub
//! storage*). The store (`HubStore::get_balance`, `HubStore::change_balances`) reads and writes a
//! page as its stored word, changed lane by lane by the arithmetic below, since a page holds seven
//! balances and a path changes one or two of them: unpacking and packing the page is what it saves
//! (docs/CAIRO.md §1; ENG-04's audit F-5 keeps packed arithmetic where it is justified). A page
//! never written reads 0 and is written with `LIVE`.

use grimworld_logic::packing::{LIVE, P32, P64, P96, low_field, split, u32_at};
use super::account::{AdventurerListAssert, AdventurerListTrait};

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
            _ => AdventurerListAssert::lane_above_6(),
        }
    }

    /// The stored page with `amount` more in `lane`; `LIVE` set on a page never written. Returns
    /// the page and whether the lane was empty before (a pack lane filled, `pack_lanes`).
    fn credit(page: felt252, lane: u8, amount: u32) -> (felt252, bool) {
        let before = Self::amount(page, lane);
        BalanceAssert::assert_credit(before, amount);
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
        BalanceAssert::assert_debit(before, amount);
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

#[generate_trait]
pub impl BalanceAssert of BalanceAssertTrait {
    /// A credit keeps the balance within a `u32`.
    #[inline(always)]
    fn assert_credit(before: u32, amount: u32) {
        let total: u64 = before.into() + amount.into();
        assert(total <= 0xFFFFFFFF, errors::OVERFLOW);
    }

    /// A debit takes no more than the balance holds.
    #[inline(always)]
    fn assert_debit(before: u32, amount: u32) {
        assert(before >= amount, errors::NOT_ENOUGH);
    }
}

// ENG-06: the pages as stored words, changed by arithmetic, against the packer (the oracle,
// docs/CAIRO.md §2).
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{LIVE, Lanes32};
    use starknet::storage_access::StorePacking;
    use super::BalanceTrait;

    #[test]
    #[available_gas(l2_gas: 297843)] // ceil(1.05 × 283660 measured)
    fn test_balance_pages() {
        assert(BalanceTrait::at(0) == (0, 0) && BalanceTrait::at(13) == (1, 6), 'at');
        assert(BalanceTrait::at(0xFFFFFFFF) == (0x24924924, 3), 'at the top');
        let page = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
        let word: felt252 = StorePacking::pack(page);
        for lane in 0..7_u8 {
            assert(BalanceTrait::amount(word, lane) == *page.lanes.span()[lane.into()], 'amount');
        }
        // A credit on a page never written sets `LIVE`, and fills its lane.
        let (credited, filled) = BalanceTrait::credit(0, 4, 9);
        assert(
            credited == StorePacking::pack(Lanes32 { lanes: [0, 0, 0, 0, 9, 0, 0] }), 'fresh page',
        );
        assert(filled, 'filled');
        let (credited, filled) = BalanceTrait::credit(word, 6, 1);
        let expected = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFF] };
        assert(credited == StorePacking::pack(expected) && !filled, 'credit to the top');
        let (debited, emptied) = BalanceTrait::debit(word, 0, 1);
        let expected = Lanes32 { lanes: [0, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
        assert(debited == StorePacking::pack(expected) && emptied, 'debit to 0');
        let (debited, emptied) = BalanceTrait::debit(word, 1, 5);
        let expected = Lanes32 { lanes: [1, 0xFFFFFFFA, 3, 0, 5, 6, 0xFFFFFFFE] };
        assert(debited == StorePacking::pack(expected) && !emptied, 'partial debit');
        let (unchanged, emptied) = BalanceTrait::debit(word, 3, 0);
        assert(unchanged == word && !emptied, 'nothing debited');
        assert(StorePacking::pack(Lanes32 { lanes: [0; 7] }) == LIVE, 'an empty page is live');
    }

    #[test]
    #[should_panic(expected: 'balance: not enough')]
    #[available_gas(l2_gas: 46977)] // ceil(1.05 × 44740 measured)
    fn test_debit_too_much_refused() {
        let word: felt252 = StorePacking::pack(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] });
        BalanceTrait::debit(word, 2, 4);
    }

    #[test]
    #[should_panic(expected: 'balance: overflow')]
    #[available_gas(l2_gas: 47292)] // ceil(1.05 × 45040 measured)
    fn test_credit_overflow_refused() {
        let word: felt252 = StorePacking::pack(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 0xFFFFFFFF] });
        BalanceTrait::credit(word, 6, 1);
    }

    #[test]
    #[should_panic(expected: 'lane above 6')]
    #[available_gas(l2_gas: 18039)] // ceil(1.05 × 17180 measured)
    fn test_balance_lane_above_6_refused() {
        BalanceTrait::amount(0, 7);
    }

    // The belt's slots merged: one change per distinct item, counts summed, empty slots skipped.
    #[test]
    #[available_gas(l2_gas: 544488)] // ceil(1.05 × 518560 measured)
    fn test_belt_merge() {
        assert(BalanceTrait::merge([4, 9, 4, 4], [1, 2, 3, 0]) == array![(4, 4), (9, 2)], 'merged');
        assert(BalanceTrait::merge([4, 4, 4, 4], [0, 0, 0, 5]) == array![(4, 5)], 'last slot');
        assert(BalanceTrait::merge([1, 2, 3, 4], [0; 4]) == array![], 'empty belt');
        assert(
            BalanceTrait::merge(
                [1, 2, 3, 4], [255; 4],
            ) == array![(1, 255), (2, 255), (3, 255), (4, 255)],
            'four items',
        );
    }
}
