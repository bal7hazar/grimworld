//! `SKILL`: its constructor, its checks and its record (layout: `models::index::Skill`).

use crate::content::{Record, SKILL};
use crate::durations::MAX_BASE_DURATION;
use crate::packing::{P16, P24, P32, P40, P56, P72, P8, P80, join, split};
use crate::types::combat::skill_kind;
use crate::types::effect::{Carrier, Entry, EntryAssert, EntryTrait};
pub use super::index::Skill;

const P82: u128 = 0x400000000000000000000;

pub mod errors {
    pub const TARGET: felt252 = 'skill: target';
    pub const DURATION: felt252 = 'skill: duration';
    // The content pipeline's checks (`assert_legal`).
    pub const KIND: felt252 = 'skill: kind';
}

#[generate_trait]
pub impl SkillImpl of SkillTrait {
    fn new(
        profession: u8,
        attribute: u8,
        kind: u8,
        energy: u8,
        adrenaline: u8,
        activation: u16,
        recharge: u16,
        range: u8,
        target: u8,
        elite: bool,
        entries: [Entry; 3],
    ) -> Skill {
        Skill {
            profession,
            attribute,
            kind,
            energy,
            adrenaline,
            activation,
            recharge,
            range,
            target,
            elite,
            entries,
        }
    }

    /// An attack skill: its action is a weapon hit carrying it (design/19 §3.4).
    #[inline(always)]
    fn is_attack(self: @Skill) -> bool {
        *self.kind == skill_kind::ATTACK
    }

    /// `(profession, elite)` of a record's part 0, its entries left packed: what `set_build`
    /// checks of each skill on the bar. The header is 83 bits: the quotient by 2^82 is the elite
    /// bit.
    fn profile(part: felt252) -> (u8, bool) {
        let (header, _) = split(part);
        let (elite, rest) = DivRem::div_rem(header, P82.try_into().unwrap());
        let (_, profession) = DivRem::div_rem(rest, P8.try_into().unwrap());
        (profession.try_into().unwrap(), elite != 0)
    }

    /// Its entry count: the index of the last non-empty entry, 0 to 3 (design/19 §2.1).
    fn count(self: @Skill) -> u8 {
        let [a, b, c] = *self.entries;
        if !c.is_empty() {
            3
        } else if !b.is_empty() {
            2
        } else if !a.is_empty() {
            1
        } else {
            0
        }
    }
}

#[generate_trait]
pub impl SkillAssert of SkillAssertTrait {
    /// The header fits its layout: target 2 bits; activation and recharge at most
    /// `MAX_BASE_DURATION` (the registry's writer refuses more, ENG-01 §3.1).
    #[inline(always)]
    fn assert_valid(self: @Skill) {
        assert(*self.target < 4, errors::TARGET);
        let max: u32 = MAX_BASE_DURATION;
        assert(
            (*self.activation).into() <= max && (*self.recharge).into() <= max, errors::DURATION,
        );
    }

    /// The content pipeline's checks (design/19 §5.14, X-1): a kind of the MVP (the Seal of
    /// Capture is deferred, FX-26) and a legal carrier.
    fn assert_legal(self: @Skill) {
        self.assert_valid();
        assert(*self.kind >= skill_kind::ATTACK && *self.kind <= skill_kind::SKILL, errors::KIND);
        let carrier = if self.is_attack() {
            Carrier::Attack
        } else {
            Carrier::Skill
        };
        let [a, b, c] = *self.entries;
        EntryAssert::assert_carrier(array![a, b, c].span(), carrier);
    }
}

pub impl SkillRecord of Record<Skill> {
    const KIND: u8 = SKILL;

    fn pack(self: @Skill) -> Span<felt252> {
        self.assert_valid();
        let header: u128 = (*self.profession).into()
            + (*self.attribute).into() * P8
            + (*self.kind).into() * P16
            + (*self.energy).into() * P24
            + (*self.adrenaline).into() * P32
            + (*self.activation).into() * P40
            + (*self.recharge).into() * P56
            + (*self.range).into() * P72
            + (*self.target).into() * P80
            + if *self.elite {
                P82
            } else {
                0
            };
        let [a, b, c] = self.entries;
        array![join(header, a.pack()), join(b.pack(), c.pack())].span()
    }

    fn unpack(parts: Span<felt252>) -> Skill {
        let (header, a) = split(*parts[0]);
        let (b, c) = split(*parts[1]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (header, profession) = DivRem::div_rem(header, s8);
        let (header, attribute) = DivRem::div_rem(header, s8);
        let (header, kind) = DivRem::div_rem(header, s8);
        let (header, energy) = DivRem::div_rem(header, s8);
        let (header, adrenaline) = DivRem::div_rem(header, s8);
        let (header, activation) = DivRem::div_rem(header, s16);
        let (header, recharge) = DivRem::div_rem(header, s16);
        let (header, range) = DivRem::div_rem(header, s8);
        let (elite, target) = DivRem::div_rem(header, 4);
        Skill {
            profession: profession.try_into().unwrap(),
            attribute: attribute.try_into().unwrap(),
            kind: kind.try_into().unwrap(),
            energy: energy.try_into().unwrap(),
            adrenaline: adrenaline.try_into().unwrap(),
            activation: activation.try_into().unwrap(),
            recharge: recharge.try_into().unwrap(),
            range: range.try_into().unwrap(),
            target: target.try_into().unwrap(),
            elite: elite != 0,
            entries: [EntryTrait::unpack(a), EntryTrait::unpack(b), EntryTrait::unpack(c)],
        }
    }
}
