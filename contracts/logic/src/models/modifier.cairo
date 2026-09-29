//! `MODIFIER`: its constructor, its checks and its record (layout: `models::index::Modifier`). A
//! modifier carries two passives, a benefit and a cost (design/15 Q-4, design/19 §4).

use crate::content::{MODIFIER, Record};
use crate::packing::{P8, join, low_field, split};
use crate::types::passive::{Passive, PassiveAssert, PassiveTrait, Source, id};
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
    pub const TWICE: felt252 = 'modifier: counted twice';
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

    /// Where its passives are held: its slot type (`slot::PREFIX` … `RUNE`).
    fn source(self: @Modifier) -> Source {
        match *self.slot {
            0 => core::panic_with_felt252(errors::SLOT),
            1 => Source::Prefix,
            2 => Source::Suffix,
            3 => Source::Inscription,
            4 => Source::Insignia,
            5 => Source::Rune,
            _ => core::panic_with_felt252(errors::SLOT),
        }
    }
}

#[generate_trait]
pub impl ModifierAssert of ModifierAssertTrait {
    /// The content pipeline's checks: a known slot type; a benefit, and a fixed cost or none,
    /// each legal and allowed on that slot type (`PassiveTrait::allows`, design/19 §7.2), the
    /// cost included; a statistic whose sources the snapshot counts is held once, not as both
    /// benefit and cost.
    fn assert_legal(self: @Modifier) {
        let source = self.source();
        assert(*self.benefit.id != id::NONE, errors::NO_BENEFIT);
        self.benefit.assert_source(source);
        self.cost.assert_source(source);
        self.cost.assert_fixed();
        let twice = self.benefit.is_counted()
            && self.cost.is_counted()
            && *self.benefit.id == *self.cost.id;
        assert(!twice, errors::TWICE);
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
        Modifier { slot: low_field(low, P8.try_into().unwrap()).try_into().unwrap(), benefit, cost }
    }
}
