//! Balances (design/07: everything counted, not slotted): pages of seven `u32` lanes under
//! `(owner key, page)`, item `7 page + lane` (docs/architecture/ENG-01-interfaces.md, *Hub
//! storage*). A page is read and written as its stored model (`models::lanes::StoredLanes`), the
//! lanes a change touches read and changed one by one: a path changes one or two of a page's seven
//! balances, so decoding the page is what it saves (docs/CAIRO.md §1). A page never written reads
//! 0 and is written with `LIVE`.

use super::lanes::{StoredLanes, StoredLanesTrait};

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

    /// The page with `amount` more in `lane`, refused past a `u32`. Returns the page and whether
    /// the lane was empty before (a pack lane filled, `pack_lanes`).
    fn credit(page: StoredLanes, lane: u8, amount: u32) -> (StoredLanes, bool) {
        let before = page.get(lane);
        BalanceAssert::assert_credit(before, amount);
        (page.added(lane, amount), before == 0 && amount != 0)
    }

    /// The page with `amount` less in `lane`, refused if the lane holds less. Returns the page
    /// and whether the lane is empty after (a pack lane emptied).
    fn debit(page: StoredLanes, lane: u8, amount: u32) -> (StoredLanes, bool) {
        let before = page.get(lane);
        BalanceAssert::assert_debit(before, amount);
        (page.removed(lane, amount), before != 0 && before == amount)
    }

    /// Page `page` with every change of `changes` that falls on it, from the `first`-th on (the
    /// earlier ones fall on other pages), credited (`credit`) or debited, in their order. Returns
    /// the page, and the lanes filled and emptied. Bound: the changes, at most 12 (ENG-01 §4.5).
    fn apply(
        page: StoredLanes, at: u32, changes: Span<(u32, u32)>, first: u32, credit: bool,
    ) -> (StoredLanes, u16, u16) {
        let (mut page, mut filled, mut emptied) = (page, 0_u16, 0_u16);
        for j in first..changes.len() {
            let (item, amount) = *changes[j];
            let (item_page, lane) = Self::at(item);
            if item_page != at {
                continue;
            }
            if credit {
                let (next, lane_filled) = Self::credit(page, lane, amount);
                page = next;
                if lane_filled {
                    filled += 1;
                }
            } else {
                let (next, lane_emptied) = Self::debit(page, lane, amount);
                page = next;
                if lane_emptied {
                    emptied += 1;
                }
            }
        }
        (page, filled, emptied)
    }

    /// Whether the `i`-th change is the first of `changes` on its page: the pages to read, once
    /// each, in the order of their first change.
    fn first_on_page(changes: Span<(u32, u32)>, i: u32) -> bool {
        let (item, _) = *changes[i];
        let (page, _) = Self::at(item);
        for j in 0..i {
            let (earlier, _) = *changes[j];
            let (earlier_page, _) = Self::at(earlier);
            if earlier_page == page {
                return false;
            }
        }
        true
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
    use grimworld_logic::packing::Lanes32;
    use starknet::storage_access::StorePacking;
    use super::BalanceTrait;
    use super::super::lanes::StoredLanes;

    fn stored(page: Lanes32) -> StoredLanes {
        StoredLanes { word: StorePacking::pack(page) }
    }

    #[test]
    #[available_gas(l2_gas: 172368)] // ceil(1.05 × 164160 measured)
    fn test_balance_pages() {
        assert(BalanceTrait::at(0) == (0, 0) && BalanceTrait::at(13) == (1, 6), 'at');
        assert(BalanceTrait::at(0xFFFFFFFF) == (0x24924924, 3), 'at the top');
        let page = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
        let word = stored(page);
        // A credit on a page never written sets `LIVE`, and fills its lane.
        let (credited, filled) = BalanceTrait::credit(StoredLanes { word: 0 }, 4, 9);
        assert(credited == stored(Lanes32 { lanes: [0, 0, 0, 0, 9, 0, 0] }), 'fresh page');
        assert(filled, 'filled');
        let (credited, filled) = BalanceTrait::credit(word, 6, 1);
        let expected = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFF] };
        assert(credited == stored(expected) && !filled, 'credit to the top');
        let (debited, emptied) = BalanceTrait::debit(word, 0, 1);
        let expected = Lanes32 { lanes: [0, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
        assert(debited == stored(expected) && emptied, 'debit to 0');
        let (debited, emptied) = BalanceTrait::debit(word, 1, 5);
        let expected = Lanes32 { lanes: [1, 0xFFFFFFFA, 3, 0, 5, 6, 0xFFFFFFFE] };
        assert(debited == stored(expected) && !emptied, 'partial debit');
        let (unchanged, emptied) = BalanceTrait::debit(word, 3, 0);
        assert(unchanged == word && !emptied, 'nothing debited');
    }

    // A page's changes applied together, the other pages' skipped; the first change of a page.
    #[test]
    #[available_gas(l2_gas: 140889)] // ceil(1.05 × 134180 measured)
    fn test_apply() {
        let changes = array![(1, 3), (8, 2), (1, 4), (15, 0)].span();
        let (page, filled, emptied) = BalanceTrait::apply(
            StoredLanes { word: 0 }, 0, changes, 0, true,
        );
        assert(page == stored(Lanes32 { lanes: [0, 7, 0, 0, 0, 0, 0] }), 'page 0');
        assert((filled, emptied) == (1, 0), 'one filled');
        let (page, _, emptied) = BalanceTrait::apply(page, 0, array![(1, 7)].span(), 0, false);
        assert(page == stored(Lanes32 { lanes: [0; 7] }) && emptied == 1, 'emptied');
        assert(BalanceTrait::first_on_page(changes, 1), 'page 1 first');
        assert(!BalanceTrait::first_on_page(changes, 2), 'page 0 again');
    }

    #[test]
    #[should_panic(expected: 'balance: not enough')]
    #[available_gas(l2_gas: 38756)] // ceil(1.05 × 36910 measured)
    fn test_debit_too_much_refused() {
        BalanceTrait::debit(stored(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] }), 2, 4);
    }

    #[test]
    #[should_panic(expected: 'balance: overflow')]
    #[available_gas(l2_gas: 39071)] // ceil(1.05 × 37210 measured)
    fn test_credit_overflow_refused() {
        BalanceTrait::credit(stored(Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 0xFFFFFFFF] }), 6, 1);
    }

    // The belt's slots merged: one change per distinct item, counts summed, empty slots skipped.
    #[test]
    #[available_gas(l2_gas: 536267)] // ceil(1.05 × 510730 measured)
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
