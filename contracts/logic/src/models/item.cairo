//! `ITEM`: its constructor, its checks and its record (layout: `models::index::Item`). Counted
//! goods: ingredients, materials, potions, trophies, stones, quest items, failed brews. A potion
//! carries one effect entry (design/19 §5.14), a bomb its range and strength (FX-18, FX-28).

use crate::helpers::packing::{LimbTrait, P16, P24, P32, P64, P8, PackingTrait};
use crate::types::content::{ITEM, Record};
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
        let (low, _) = PackingTrait::split(part);
        LimbTrait::low_field(low, P8.try_into().unwrap()).try_into().unwrap()
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
        array![PackingTrait::join(low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Item {
        let (low, high) = PackingTrait::split(*parts[0]);
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

/// The record's unit tests (CBT-01, design/19 §7.2): a potion carries one entry, a bomb its range
/// and strength; a non-potion's entry is the empty entry (CBT-5).
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::combat::damage;
    use crate::types::content::{ITEM, KindTrait, Record};
    use crate::types::effect::{Entry, EntryTrait, filter, kind, shape, target};
    use super::{Item, ItemTrait, class};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// The entries these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        /// Under `ALLIES`: the caster is its own ally, and under `FOES` a `SELF` entry takes nobody
        /// (R-45).
        fn on_self(kind: u8) -> Entry {
            Entry {
                kind,
                target: target::SELF,
                shape: shape::SINGLE,
                filter: filter::ALLIES,
                ..Default::default(),
            }
        }

        /// Every field of an entry at its widest.
        fn entry_max() -> Entry {
            EntryTrait::new(0xFF, 0xFF, -32768, 32767, 43688, 43688, 63, 3, 7, 1, 7, 3)
        }
    }

    // §7.2: `ITEM`, 1 part; a potion carries one entry, a bomb its range and strength.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 482234)] // ceil(1.05 × 459270 measured)
    fn test_item_round_trip() {
        let top = ItemTrait::new(
            0xFF, 0xFFFF, 0xFF, 0xFFFFFFFF, 0xFF, Fixture::entry_max(), 0xFF, 0xFF,
        );
        let packed = top.pack();
        assert(packed.len() == KindTrait::parts(ITEM).into(), 'parts');
        assert(Record::<Item>::unpack(packed) == top, 'top round trip');
        let e: Entry = Default::default();
        let zero = ItemTrait::new(0, 0, 0, 0, 0, e, 0, 0);
        assert(zero.pack() == array![LIVE].span(), 'empty is LIVE');
        // Bits: region 8, value 32, book index 64; the entry at 128, range 225, strength 233.
        let low = ItemTrait::new(0, 1, 0, 1, 1, e, 0, 0);
        assert(*low.pack()[0] == 0x100 + 0x100000000 + 0x10000000000000000 + LIVE, 'low bits');
        let high = ItemTrait::new(0, 0, 0, 0, 0, Entry { kind: 1, ..e }, 1, 1);
        let two_225: felt252 = TWO_128 * 0x2000000000000000000000000;
        let expected = TWO_128 + two_225 + two_225 * 0x100 + LIVE;
        assert(*high.pack()[0] == expected, 'high bits');
        // A bomb: fire damage on a disc around a tile (FX-18, FX-35).
        let fire = Entry {
            kind: kind::DAMAGE,
            param: damage::FIRE,
            v0: 40,
            v12: 40,
            target: target::TILE,
            shape: shape::DISC_1,
            ..e,
        };
        let bomb = ItemTrait::new(class::POTION, 1, 1, 10, 0, fire, 4, 60);
        bomb.assert_legal();
        ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, e, 0, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: scales')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 77910)] // ceil(1.05 × 74200 measured)
    fn test_item_scaled_potion_refused() {
        let heal = Entry { v0: 10, v12: 20, ..Fixture::on_self(kind::HEAL) };
        ItemTrait::new(class::POTION, 1, 1, 1, 0, heal, 0, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'item: entry not a potion')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_item_entry_not_a_potion_refused() {
        let heal = Entry { v0: 10, v12: 10, ..Fixture::on_self(kind::HEAL) };
        ItemTrait::new(class::TROPHY, 1, 1, 1, 0, heal, 0, 0).assert_legal();
    }

    // CBT-5: a non-potion's entry is the empty entry, every field 0.
    #[test]
    #[should_panic(expected: 'entry: empty with a field')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_ingredient_with_a_stray_field_refused() {
        let stray = Entry { v0: 1, ..Default::default() };
        ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, stray, 0, 0).assert_legal();
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_ingredient_empty_entry_accepted() {
        ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, Default::default(), 0, 0).assert_legal();
    }
}
