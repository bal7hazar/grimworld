//! `ITEM`: its constructor, its checks and its record (layout: `models::index::Item`). Counted
//! goods: ingredients, materials, potions, trophies, stones, quest items, failed brews. A potion
//! carries one effect entry (design/19 §5.14), a bomb its range and strength (FX-18, FX-28).

use crate::content::{ITEM, Record};
use crate::packing::{P16, P24, P32, P64, P8, join, low_field, split};
use crate::types::effect::{Carrier, ENTRY_BOUND, EntryAssert, EntryTrait};
pub use super::index::Item;

/// Item classes, in the order of ENG-01 §3.5's list.
pub mod class {
    pub const INGREDIENT: u8 = 1;
    pub const MATERIAL: u8 = 2;
    pub const POTION: u8 = 3;
    pub const TROPHY: u8 = 4;
    pub const STILLSTONE: u8 = 5;
    pub const HEARTSTONE: u8 = 6;
    pub const QUEST: u8 = 7;
    pub const FAILED_BREW: u8 = 8;
    pub const LAST: u8 = 8;
}

const P105: u128 = 0x200000000000000000000000000;

pub mod errors {
    // The content pipeline's checks (`assert_legal`).
    pub const CLASS: felt252 = 'item: class';
    pub const NOT_POTION: felt252 = 'item: entry not a potion';
    pub const NO_ENTRY: felt252 = 'item: potion without entry';
}

#[generate_trait]
pub impl ItemImpl of ItemTrait {
    fn new(
        class: u8,
        region: u16,
        rarity: u8,
        value: u32,
        book_index: u8,
        entry: crate::types::effect::Entry,
        range: u8,
        strength: u8,
    ) -> Item {
        Item { class, region, rarity, value, book_index, entry, range, strength }
    }

    /// The class of a record's part 0, the rest left packed: what `set_build` checks of a belt
    /// item.
    #[inline(always)]
    fn class_of(part: felt252) -> u8 {
        let (low, _) = split(part);
        low_field(low, P8.try_into().unwrap()).try_into().unwrap()
    }

    #[inline(always)]
    fn is_potion(self: @Item) -> bool {
        *self.class == class::POTION
    }
}

#[generate_trait]
pub impl ItemAssert of ItemAssertTrait {
    /// The content pipeline's checks: a known class; a potion has one legal, unscaled entry
    /// (design/19 §2.2, §5.14); any other class has none.
    fn assert_legal(self: @Item) {
        assert(*self.class >= class::INGREDIENT && *self.class <= class::LAST, errors::CLASS);
        if self.is_potion() {
            assert(!self.entry.is_empty(), errors::NO_ENTRY);
            EntryAssert::assert_carrier(array![*self.entry].span(), Carrier::Potion);
        } else {
            // The empty entry, every field 0 (design/19 §2.1), not only its kind.
            assert(self.entry.is_empty(), errors::NOT_POTION);
            self.entry.assert_legal();
        }
    }
}

pub impl ItemRecord of Record<Item> {
    const KIND: u8 = ITEM;

    fn pack(self: @Item) -> Span<felt252> {
        let low: u128 = (*self.class).into()
            + (*self.region).into() * P8
            + (*self.rarity).into() * P24
            + (*self.value).into() * P32
            + (*self.book_index).into() * P64;
        let high: u128 = self.entry.pack()
            + (*self.range).into() * ENTRY_BOUND
            + (*self.strength).into() * P105;
        array![join(low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Item {
        let (low, high) = split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let (low, class) = DivRem::div_rem(low, s8);
        let (low, region) = DivRem::div_rem(low, P16.try_into().unwrap());
        let (low, rarity) = DivRem::div_rem(low, s8);
        let (book_index, value) = DivRem::div_rem(low, P32.try_into().unwrap());
        let (high, entry) = DivRem::div_rem(high, ENTRY_BOUND.try_into().unwrap());
        let (strength, range) = DivRem::div_rem(high, s8);
        Item {
            class: class.try_into().unwrap(),
            region: region.try_into().unwrap(),
            rarity: rarity.try_into().unwrap(),
            value: value.try_into().unwrap(),
            book_index: book_index.try_into().unwrap(),
            entry: EntryTrait::unpack(entry),
            range: range.try_into().unwrap(),
            strength: strength.try_into().unwrap(),
        }
    }
}
