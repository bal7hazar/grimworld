//! `MemberBar`, the second of the member's three snapshot words: the skill bar and, in its high
//! limb, the passives the rules read at each hit or cast (design/19 §7.2, FX-24), with its two
//! `QuickCast` pairs; their layout, checks and packing (bit offsets in
//! docs/architecture/ENG-01-interfaces.md, *Member*; pinned by the ephemeral package's
//! `test_tick_words`).

use crate::helpers::packing::{
    LimbTrait, P104, P112, P12, P16, P24, P32, P40, P48, P56, P64, P72, P8, P80, P96, PackingTrait,
};
use crate::helpers::signed::SignedTrait;

/// The widest unguarded armor (design/19 §7.2, F-20; F-21 settled by CBT-01): the weighted rating
/// of the five pieces (each `u8`, weights summing to 1: at most 255) and the shield's (`u8`, 255),
/// each raised by personalisation's +10 % of its rating (`RATING_PERCENT`, design/15 D-48: at most
/// ⌊255 × 10 / 100⌋ = 25 each), and at most 37 unguarded `ARMOR` passives of −255…+255:
/// `255 + 25 +
/// 255 + 25 + 37 × 255 = 9,995 < 32,767`. The two 255 limits are the ratings before
/// personalisation. An `i16` holds it.
pub const MAX_UNGUARDED_ARMOR: i16 = 9995;

const P92: u128 = 0x100000000000000000000000;

pub mod errors {
    pub const ARMOR: felt252 = 'snapshot: armor above bound';
    pub const QUICK_CAST: felt252 = 'snapshot: quick-cast attribute';
}

/// A quick-cast modifier held (`QUICK_CAST_EVERY_N`, design/19 §4, §5.12): its attribute (4
/// bits) and its N (8 bits; 0 for none). At most two are held, each with its own counter
/// (`MemberState.casts`, `casts_2`; FX-43).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct QuickCast {
    pub attribute: u8,
    pub every: u8,
}

/// The skill bar (8 skill ids, registry `u16`), locked for the expedition (design/03), and, in
/// its high limb, the passives the rules read at each hit or cast (design/19 §7.2, FX-24).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberBar {
    pub skills: [u16; 8],
    /// The slot of the elite skill, 255 for none (bits 128–135).
    pub elite_slot: u8,
    /// `DAMAGE_PERCENT` sums (bits 136–183), index `3 × guard + class`: guard `ALWAYS` 0 or
    /// `ABOVE_HALF` 1, hit class (`passive::HIT_*`) a plain weapon hit 0 (scopes `WEAPON`,
    /// `ALL`), an attack skill's hit 1 (`WEAPON`, `ATTACK_SKILL`, `ALL`: design/19 §5.4), a
    /// spell's hit 2 (`SPELL`, `ALL`). Each −126…+126.
    pub damage: [i8; 6],
    /// `PENETRATION` sums, percent, index the hit class as above (bits 184–207). Each ≤ 252,
    /// capped at 100 at use.
    pub penetration: [u8; 3],
    /// Two quick-cast modifiers, 12 bits each (bits 208–231).
    pub quick_cast: [QuickCast; 2],
    /// The unguarded armor, signed (bits 232–247), at most `MAX_UNGUARDED_ARMOR` either way.
    pub armor: i16,
}

#[generate_trait]
pub impl QuickCastImpl of QuickCastTrait {
    /// Its 12 bits: attribute 0–3 · N 4–11 (`QuickCastAssert::assert_valid`).
    fn pack(self: @QuickCast) -> u128 {
        self.assert_valid();
        (*self.attribute).into() + (*self.every).into() * 0x10
    }

    /// The pair of 12 bits.
    fn unpack(bits: u128) -> QuickCast {
        let (every, attribute) = DivRem::div_rem(bits, 0x10);
        QuickCast { attribute: attribute.try_into().unwrap(), every: every.try_into().unwrap() }
    }
}

#[generate_trait]
pub impl QuickCastAssert of QuickCastAssertTrait {
    /// The attribute fits 4 bits.
    #[inline(always)]
    fn assert_valid(self: @QuickCast) {
        assert(*self.attribute < 0x10, errors::QUICK_CAST);
    }
}

#[generate_trait]
pub impl MemberBarImpl of MemberBarTrait {
    fn pack(b: MemberBar) -> felt252 {
        let [s0, s1, s2, s3, s4, s5, s6, s7] = b.skills;
        let [d0, d1, d2, d3, d4, d5] = b.damage;
        let [p0, p1, p2] = b.penetration;
        let [q0, q1] = b.quick_cast;
        b.assert_valid();
        let low: u128 = s0.into()
            + s1.into() * P16
            + s2.into() * P32
            + s3.into() * P48
            + s4.into() * P64
            + s5.into() * P80
            + s6.into() * P96
            + s7.into() * P112;
        let high: u128 = b.elite_slot.into()
            + SignedTrait::bits8(d0) * P8
            + SignedTrait::bits8(d1) * P16
            + SignedTrait::bits8(d2) * P24
            + SignedTrait::bits8(d3) * P32
            + SignedTrait::bits8(d4) * P40
            + SignedTrait::bits8(d5) * P48
            + p0.into() * P56
            + p1.into() * P64
            + p2.into() * P72
            + q0.pack() * P80
            + q1.pack() * P92
            + SignedTrait::bits16(b.armor) * P104;
        PackingTrait::join(low, high)
    }

    fn unpack(word: felt252) -> MemberBar {
        let (low, high) = PackingTrait::split(word);
        let b16: NonZero<u128> = P16.try_into().unwrap();
        let b8: NonZero<u128> = P8.try_into().unwrap();
        let b12: NonZero<u128> = P12.try_into().unwrap();
        let (low, s0) = DivRem::div_rem(low, b16);
        let (low, s1) = DivRem::div_rem(low, b16);
        let (low, s2) = DivRem::div_rem(low, b16);
        let (low, s3) = DivRem::div_rem(low, b16);
        let (low, s4) = DivRem::div_rem(low, b16);
        let (low, s5) = DivRem::div_rem(low, b16);
        let (s7, s6) = DivRem::div_rem(low, b16);
        let (high, elite_slot) = DivRem::div_rem(high, b8);
        let (high, d0) = DivRem::div_rem(high, b8);
        let (high, d1) = DivRem::div_rem(high, b8);
        let (high, d2) = DivRem::div_rem(high, b8);
        let (high, d3) = DivRem::div_rem(high, b8);
        let (high, d4) = DivRem::div_rem(high, b8);
        let (high, d5) = DivRem::div_rem(high, b8);
        let (high, p0) = DivRem::div_rem(high, b8);
        let (high, p1) = DivRem::div_rem(high, b8);
        let (high, p2) = DivRem::div_rem(high, b8);
        let (high, q0) = DivRem::div_rem(high, b12);
        let (high, q1) = DivRem::div_rem(high, b12);
        let armor = LimbTrait::low_field(high, b16);
        MemberBar {
            skills: [
                s0.try_into().unwrap(), s1.try_into().unwrap(), s2.try_into().unwrap(),
                s3.try_into().unwrap(), s4.try_into().unwrap(), s5.try_into().unwrap(),
                s6.try_into().unwrap(), s7.try_into().unwrap(),
            ],
            elite_slot: elite_slot.try_into().unwrap(),
            damage: [
                SignedTrait::from8(d0), SignedTrait::from8(d1), SignedTrait::from8(d2),
                SignedTrait::from8(d3), SignedTrait::from8(d4), SignedTrait::from8(d5),
            ],
            penetration: [p0.try_into().unwrap(), p1.try_into().unwrap(), p2.try_into().unwrap()],
            quick_cast: [QuickCastTrait::unpack(q0), QuickCastTrait::unpack(q1)],
            armor: SignedTrait::from16(armor),
        }
    }
}

pub impl MemberBarStorePacking of starknet::storage_access::StorePacking<MemberBar, felt252> {
    fn pack(value: MemberBar) -> felt252 {
        MemberBarTrait::pack(value)
    }
    fn unpack(value: felt252) -> MemberBar {
        MemberBarTrait::unpack(value)
    }
}

/// Every field of the word fits its layout (docs/CAIRO.md §7: checks in `Assert` impls);
/// `MemberBarTrait::pack` calls it.
#[generate_trait]
pub impl MemberBarAssert of MemberBarAssertTrait {
    /// The unguarded armor within ±`MAX_UNGUARDED_ARMOR` (F-21); the quick-cast pairs
    /// (`QuickCastAssert`, checked as they pack).
    #[inline(always)]
    fn assert_valid(self: @MemberBar) {
        let armor = *self.armor;
        assert(armor >= -MAX_UNGUARDED_ARMOR && armor <= MAX_UNGUARDED_ARMOR, errors::ARMOR);
    }
}

#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use super::{MAX_UNGUARDED_ARMOR, MemberBar, MemberBarTrait, QuickCast};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 247223)] // ceil(1.05 × 235450 measured)
    fn test_bar_layout() {
        let bar = MemberBar {
            skills: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], elite_slot: 255, ..Fixture::empty_bar(),
        };
        assert(MemberBarTrait::unpack(MemberBarTrait::pack(bar)) == bar, 'bar round trip');
        let bar = MemberBar {
            skills: [0, 0, 0, 0, 0, 0, 0, 1], elite_slot: 0, ..Fixture::empty_bar(),
        };
        assert(
            MemberBarTrait::pack(bar) == 0x10000000000000000000000000000 + LIVE,
            'skill 7 at bit 112',
        );
    }

    #[generate_trait]
    impl FixtureImpl of Fixture {
        /// A bar with no skill and every passive sum 0, the unguarded armor 0.
        fn empty_bar() -> MemberBar {
            MemberBar {
                skills: [0; 8],
                elite_slot: 0,
                damage: [0; 6],
                penetration: [0; 3],
                quick_cast: [Default::default(); 2],
                armor: 0,
            }
        }
    }

    // design/19 §7.2 (FX-24): the bar's high limb holds the elite slot 128, the damage sums
    // 136–183 (signed), the penetration sums 184–207, the quick-cast pairs 208–231 and the
    // unguarded armor 232–247 (signed); each round-trips at both ends and sits at its bit.
    #[test]
    #[available_gas(l2_gas: 830193)] // ceil(1.05 × 790660 measured)
    fn test_bar_passives_layout() {
        let top = MemberBar {
            skills: [0xFFFF; 8],
            elite_slot: 255,
            damage: [127, -128, 126, -126, 1, -1],
            penetration: [255, 0, 252],
            quick_cast: [
                QuickCast { attribute: 15, every: 255 }, QuickCast { attribute: 1, every: 5 },
            ],
            armor: -MAX_UNGUARDED_ARMOR,
        };
        assert(MemberBarTrait::unpack(MemberBarTrait::pack(top)) == top, 'top round trip');
        let top = MemberBar { armor: MAX_UNGUARDED_ARMOR, ..top };
        assert(MemberBarTrait::unpack(MemberBarTrait::pack(top)) == top, 'armor max round trip');
        let bit = |bar: MemberBar| -> felt252 {
            MemberBarTrait::pack(bar) - LIVE
        };
        let empty = Fixture::empty_bar();
        let two_136: felt252 = TWO_128 * 0x100;
        assert(bit(MemberBar { damage: [1, 0, 0, 0, 0, 0], ..empty }) == two_136, 'damage at 136');
        assert(
            bit(MemberBar { damage: [-1, 0, 0, 0, 0, 0], ..empty }) == two_136 * 0xFF,
            'signed damage',
        );
        let two_184: felt252 = TWO_128 * 0x100000000000000;
        assert(bit(MemberBar { penetration: [1, 0, 0], ..empty }) == two_184, 'penetration at 184');
        let two_208: felt252 = TWO_128 * 0x100000000000000000000;
        let one = QuickCast { attribute: 1, every: 0 };
        assert(
            bit(MemberBar { quick_cast: [one, Default::default()], ..empty }) == two_208,
            'qc at 208',
        );
        let two_232: felt252 = TWO_128 * 0x100000000000000000000000000;
        assert(bit(MemberBar { armor: 1, ..empty }) == two_232, 'armor at 232');
        assert(bit(MemberBar { armor: -1, ..empty }) == two_232 * 0xFFFF, 'armor signed');
    }

    // F-21: the unguarded armor is bounded by 9,995 either way; a wider value is refused.
    #[test]
    #[should_panic(expected: 'snapshot: armor above bound')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_bar_armor_above_bound_refused() {
        MemberBarTrait::pack(MemberBar { armor: MAX_UNGUARDED_ARMOR + 1, ..Fixture::empty_bar() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: armor above bound')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_bar_armor_below_bound_refused() {
        MemberBarTrait::pack(MemberBar { armor: -MAX_UNGUARDED_ARMOR - 1, ..Fixture::empty_bar() });
    }

    #[test]
    #[should_panic(expected: 'snapshot: quick-cast attribute')]
    #[available_gas(l2_gas: 77175)] // ceil(1.05 × 73500 measured)
    fn test_bar_quick_cast_attribute_refused() {
        let wide = QuickCast { attribute: 16, every: 1 };
        MemberBarTrait::pack(
            MemberBar { quick_cast: [Default::default(), wide], ..Fixture::empty_bar() },
        );
    }
}
