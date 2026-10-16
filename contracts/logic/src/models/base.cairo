//! `BASE`: its constructor, its checks and its record (layout: `models::index::Base`). An
//! equipment base: the slot it is worn in and, for a weapon, its hands (design/15). The creator of
//! an item copies both into `ItemBase` (`ItemBaseTrait::new`, D-158).

use crate::helpers::packing::{LIVE, LimbTrait, P8, PackingTrait};
use crate::types::content::{BASE, Record};
pub use super::index::Base;

/// Equipment slots, in the order of `equipped`'s lanes, from 1 (ENG-01 §3.3).
pub mod slot {
    pub const WEAPON: u8 = 1;
    pub const OFF_HAND: u8 = 2;
    pub const CHEST: u8 = 3;
    pub const LEGS: u8 = 4;
    pub const HEAD: u8 = 5;
    pub const HANDS: u8 = 6;
    pub const FEET: u8 = 7;
    pub const LAST: u8 = 7;
}

pub mod errors {
    pub const SLOT: felt252 = 'base: slot';
    pub const HANDS: felt252 = 'base: hands';
}

#[generate_trait]
pub impl BaseImpl of BaseTrait {
    fn new(slot: u8, hands: u8) -> Base {
        Base { slot, hands }
    }

    /// A weapon held in both hands: nothing goes in the off-hand (design/15, *Weapons*).
    #[inline(always)]
    fn is_two_handed(self: @Base) -> bool {
        *self.hands == 2
    }
}

#[generate_trait]
pub impl BaseAssert of BaseAssertTrait {
    /// A known slot; hands 1 or 2 on a weapon, 0 elsewhere (design/15's table).
    fn assert_valid(self: @Base) {
        assert(*self.slot >= slot::WEAPON && *self.slot <= slot::LAST, errors::SLOT);
        if *self.slot == slot::WEAPON {
            assert(*self.hands == 1 || *self.hands == 2, errors::HANDS);
        } else {
            assert(*self.hands == 0, errors::HANDS);
        }
    }
}

pub impl BaseRecord of Record<Base> {
    const KIND: u8 = BASE;

    fn pack(self: @Base) -> Span<felt252> {
        self.assert_valid();
        array![PackingTrait::join((*self.slot).into() + (*self.hands).into() * P8, 0), LIVE].span()
    }

    fn unpack(parts: Span<felt252>) -> Base {
        let (low, _) = PackingTrait::split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let (low, slot) = DivRem::div_rem(low, s8);
        Base {
            slot: slot.try_into().unwrap(),
            hands: LimbTrait::low_field(low, s8).try_into().unwrap(),
        }
    }
}

/// The record's unit tests (CBT-08a): the fields of `BASE` that `set_build` lays out (slot, hands,
/// from bit 0 of part 0).
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::content::Record;
    use super::{Base, BaseAssert, BaseRecord, BaseTrait, slot};

    #[test]
    #[available_gas(l2_gas: 73448)] // ceil(1.05 × 69950 measured)
    fn test_base_round_trip() {
        let maul = BaseTrait::new(slot::WEAPON, 2);
        assert(Record::unpack(maul.pack()) == maul, 'round trip');
        assert(maul.is_two_handed() && !BaseTrait::new(slot::WEAPON, 1).is_two_handed(), 'hands');
        let feet = BaseTrait::new(slot::FEET, 0);
        assert(feet.pack() == array![7 + LIVE, LIVE].span(), 'bits: slot 0');
        assert(*maul.pack()[0] == 1 + 2 * 0x100 + LIVE, 'bits: hands 8');
        // A record never written unpacks as slot 0: no slot.
        assert(Record::<Base>::unpack(array![0, 0].span()).slot == 0, 'none');
        for s in slot::WEAPON..slot::LAST + 1 {
            let hands = if s == slot::WEAPON {
                1
            } else {
                0
            };
            BaseTrait::new(s, hands).assert_valid();
        }
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'base: slot')]
    fn test_base_slot_refused() {
        BaseTrait::new(slot::LAST + 1, 0).pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'base: slot')]
    fn test_base_no_slot_refused() {
        BaseTrait::new(0, 0).pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'base: hands')]
    fn test_base_weapon_hands_refused() {
        BaseTrait::new(slot::WEAPON, 3).pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'base: hands')]
    fn test_base_armor_hands_refused() {
        BaseTrait::new(slot::OFF_HAND, 1).pack();
    }
}
