//! `BASE`: its constructor, its checks and its record (layout: `models::index::Base`). An
//! equipment base: the slot it is worn in and, for a weapon, its hands (design/15).

use crate::content::{BASE, Record};
use crate::packing::{LIVE, P8, join, low_field, split};
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
        array![join((*self.slot).into() + (*self.hands).into() * P8, 0), LIVE].span()
    }

    fn unpack(parts: Span<felt252>) -> Base {
        let (low, _) = split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let (low, slot) = DivRem::div_rem(low, s8);
        Base {
            slot: slot.try_into().unwrap(), hands: low_field(low, s8).try_into().unwrap(),
        }
    }
}
