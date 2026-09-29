//! `MODIFIER`: its constructor, its checks and its record (layout: `models::index::Modifier`). A
//! modifier carries two passives, a benefit and a cost (design/15 Q-4, design/19 §4).

use crate::content::{MODIFIER, Record};
use crate::packing::{P8, join, low_field, split};
use crate::types::passive::{Passive, PassiveAssert, PassiveTrait, id};
pub use super::index::Modifier;

/// Slot types, in the order of `ItemMods`' five slots (ENG-01 §3.3, design/15).
pub mod slot {
    pub const PREFIX: u8 = 1;
    pub const SUFFIX: u8 = 2;
    pub const INSCRIPTION: u8 = 3;
    pub const INSIGNIA: u8 = 4;
    pub const RUNE: u8 = 5;
    pub const LAST: u8 = 5;
}

pub mod errors {
    // The content pipeline's checks (`assert_legal`).
    pub const SLOT: felt252 = 'modifier: slot';
    pub const NO_BENEFIT: felt252 = 'modifier: no benefit';
}

#[generate_trait]
pub impl ModifierImpl of ModifierTrait {
    fn new(slot: u8, benefit: Passive, cost: Passive) -> Modifier {
        Modifier { slot, benefit, cost }
    }

    /// Whether it has a cost (a cost id 0 is none).
    #[inline(always)]
    fn has_cost(self: @Modifier) -> bool {
        *self.cost.id != id::NONE
    }
}

#[generate_trait]
pub impl ModifierAssert of ModifierAssertTrait {
    /// The content pipeline's checks: a known slot type, a legal benefit, a legal fixed cost or
    /// none.
    fn assert_legal(self: @Modifier) {
        assert(*self.slot >= slot::PREFIX && *self.slot <= slot::LAST, errors::SLOT);
        assert(*self.benefit.id != id::NONE, errors::NO_BENEFIT);
        self.benefit.assert_legal();
        self.cost.assert_legal();
        self.cost.assert_fixed();
    }
}

pub impl ModifierRecord of Record<Modifier> {
    const KIND: u8 = MODIFIER;

    fn pack(self: @Modifier) -> Span<felt252> {
        array![join((*self.slot).into(), PassiveTrait::pack_pair(self.benefit, self.cost))].span()
    }

    fn unpack(parts: Span<felt252>) -> Modifier {
        let (low, high) = split(*parts[0]);
        let (benefit, cost) = PassiveTrait::unpack_pair(high);
        Modifier {
            slot: low_field(low, P8.try_into().unwrap()).try_into().unwrap(), benefit, cost,
        }
    }
}
