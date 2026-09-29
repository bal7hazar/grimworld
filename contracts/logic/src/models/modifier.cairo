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
    // The content pipeline's checks (`assert_legal`, `assert_catalogue`).
    pub const SLOT: felt252 = 'modifier: slot';
    pub const NO_BENEFIT: felt252 = 'modifier: no benefit';
    pub const TWICE: felt252 = 'modifier: counted twice';
    pub const QUICK_CAST_SLOTS: felt252 = 'modifier: quick-cast slots';
    pub const DAMAGE_TYPE_SLOTS: felt252 = 'modifier: damage type slots';
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

    /// Whether its benefit or its cost is the passive `id`.
    #[inline(always)]
    fn holds(self: @Modifier, id: u8) -> bool {
        *self.benefit.id == id || *self.cost.id == id
    }

    /// Where its passives are held: its slot type (`slot::PREFIX` … `RUNE`); `None` for any
    /// other value (`ModifierAssert::assert_slot` refuses it).
    fn source(self: @Modifier) -> Option<Source> {
        match *self.slot {
            0 => Option::None,
            1 => Option::Some(Source::Prefix),
            2 => Option::Some(Source::Suffix),
            3 => Option::Some(Source::Inscription),
            4 => Option::Some(Source::Insignia),
            5 => Option::Some(Source::Rune),
            _ => Option::None,
        }
    }
}

#[generate_trait]
pub impl ModifierAssert of ModifierAssertTrait {
    /// A known slot type, 1–5.
    #[inline(always)]
    fn assert_slot(self: @Modifier) {
        assert(*self.slot >= slot::PREFIX && *self.slot <= slot::LAST, errors::SLOT);
    }

    /// The content pipeline's checks of one modifier: a known slot type; a benefit, and a fixed
    /// cost or none, each legal and allowed on that slot type (`PassiveTrait::allows`,
    /// design/19 §7.2), the cost included; the benefit and the cost do not add to one sum the
    /// snapshot bounds by counting sources (`PassiveTrait::shares_sum`: by statistic, guard and
    /// scope), since one slot is one source.
    fn assert_legal(self: @Modifier) {
        self.assert_slot();
        let source = self.source().unwrap();
        assert(*self.benefit.id != id::NONE, errors::NO_BENEFIT);
        self.benefit.assert_source(source);
        self.cost.assert_source(source);
        self.cost.assert_fixed();
        assert(!self.benefit.shares_sum(self.cost), errors::TWICE);
    }

    /// The content pipeline's checks across every `MODIFIER` of the content, each legal: "the
    /// pipeline gives [`QUICK_CAST_EVERY_N`, `DAMAGE_TYPE`] one slot type" (design/19 §4,
    /// §7.2), so all the modifiers holding one of them share a slot type. Which one is not
    /// settled (escalated); with any, at most 2 quick-cast pairs and one damage type per held
    /// item are held.
    fn assert_catalogue(modifiers: Span<Modifier>) {
        let mut quick_cast: u8 = 0;
        let mut damage_type: u8 = 0;
        for modifier in modifiers {
            modifier.assert_legal();
            let slot = *modifier.slot;
            if modifier.holds(id::QUICK_CAST_EVERY_N) {
                assert(quick_cast == 0 || quick_cast == slot, errors::QUICK_CAST_SLOTS);
                quick_cast = slot;
            }
            if modifier.holds(id::DAMAGE_TYPE) {
                assert(damage_type == 0 || damage_type == slot, errors::DAMAGE_TYPE_SLOTS);
                damage_type = slot;
            }
        }
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
