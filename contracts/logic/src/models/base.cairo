//! `BASE`: its constructors, its checks and its record (layout: `models::index::Base`). An
//! equipment base: the slot it is worn in and, for a weapon, its hands and its statistics
//! (design/15). The creator of an item copies the slot, the hands and the weapon at the item's
//! requirement into `ItemBase` (`ItemBaseTrait::new`, D-158).

use crate::helpers::packing::{LIVE, LimbTrait, P16, P24, P32, P40, P48, P56, P64, P8, PackingTrait};
use crate::models::loadout::MAX_WEAPON_BASE_DAMAGE;
use crate::types::combat::{damage, weapon};
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

/// The highest requirement (design/15, *Requirement*: 0 to 9; the damage stops growing at 9).
pub const MAX_REQUIREMENT: u8 = 9;

pub mod errors {
    pub const SLOT: felt252 = 'base: slot';
    pub const HANDS: felt252 = 'base: hands';
    // A weapon's statistics (WPN-01).
    pub const CLASS: felt252 = 'base: weapon class';
    /// Its damage at requirement 9 below the one at 0, or above `MAX_WEAPON_BASE_DAMAGE`.
    pub const DAMAGE: felt252 = 'base: weapon damage';
    pub const TICKS: felt252 = 'base: weapon ticks';
    pub const DAMAGE_TYPE: felt252 = 'base: damage type';
    pub const ATTRIBUTE: felt252 = 'base: weapon attribute';
    /// Weapon statistics on a base of another slot.
    pub const NOT_A_WEAPON: felt252 = 'base: stats off a weapon';
}

/// A weapon's statistics as an item holds them (design/15, *Weapons*): its base's, the damage
/// taken at the item's requirement (`BaseTrait::at`). All 0 for an item that is not a weapon, and
/// for no weapon worn. `ItemBase` stores them at bits 128–175 (`WeaponTrait::pack`), 8 bits each
/// in this order; the loadout reads them from the weapon worn.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Weapon {
    pub class: u8,
    pub damage: u8,
    pub ticks: u8,
    pub range: u8,
    pub damage_type: u8,
    pub attribute: u8,
}

#[generate_trait]
pub impl WeaponImpl of WeaponTrait {
    /// Its six fields, 8 bits each from bit 0: 48 bits.
    fn pack(self: @Weapon) -> u128 {
        (*self.class).into()
            + (*self.damage).into() * P8
            + (*self.ticks).into() * P16
            + (*self.range).into() * P24
            + (*self.damage_type).into() * P32
            + (*self.attribute).into() * P40
    }

    /// The six fields from bit 0 of `bits`, one division a field.
    fn unpack(bits: u128) -> Weapon {
        let mut rest = bits;
        let s8: NonZero<u128> = P8.try_into().unwrap();
        Weapon {
            class: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            damage: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            ticks: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            range: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            damage_type: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            attribute: LimbTrait::low_field(rest, s8).try_into().unwrap(),
        }
    }
}

#[generate_trait]
pub impl BaseImpl of BaseTrait {
    /// A base that is not a weapon (an off-hand, a piece of armor): no hands, no statistics.
    fn new(slot: u8, hands: u8) -> Base {
        Base {
            slot,
            hands,
            class: 0,
            damage_0: 0,
            damage_9: 0,
            ticks: 0,
            range: 0,
            damage_type: 0,
            attribute: 0,
        }
    }

    /// A weapon's base (design/15, *Weapons*): worn in the weapon slot.
    fn weapon(
        hands: u8,
        class: u8,
        damage_0: u8,
        damage_9: u8,
        ticks: u8,
        range: u8,
        damage_type: u8,
        attribute: u8,
    ) -> Base {
        Base {
            slot: slot::WEAPON,
            hands,
            class,
            damage_0,
            damage_9,
            ticks,
            range,
            damage_type,
            attribute,
        }
    }

    /// A weapon held in both hands: nothing goes in the off-hand (design/15, *Weapons*).
    #[inline(always)]
    fn is_two_handed(self: @Base) -> bool {
        *self.hands == 2
    }

    /// The weapon an item of this base holds at `requirement` (design/15, *Requirement*): the
    /// damage grows from requirement 0 to 9 by equal steps, rounded down, and stops at 9. All 0
    /// for a base that is not a weapon.
    fn at(self: @Base, requirement: u8) -> Weapon {
        let requirement: u16 = if requirement > MAX_REQUIREMENT {
            MAX_REQUIREMENT.into()
        } else {
            requirement.into()
        };
        let low: u16 = (*self.damage_0).into();
        let high: u16 = (*self.damage_9).into();
        let damage = low + (high - low) * requirement / MAX_REQUIREMENT.into();
        Weapon {
            class: *self.class,
            damage: damage.try_into().unwrap(),
            ticks: *self.ticks,
            range: *self.range,
            damage_type: *self.damage_type,
            attribute: *self.attribute,
        }
    }
}

/// What the creator of an item copies from a `BASE` record (D-158), read from its part 0 without
/// decoding the record: `Hub`'s path (`HubStoreTrait::create_item`), pinned against
/// `BaseRecord::unpack` and `BaseTrait::at` in the tests.
#[generate_trait]
pub impl BasePartImpl of BasePartTrait {
    /// `(slot, hands, weapon)` of part 0, the weapon at `requirement` packed as
    /// `WeaponTrait::pack` lays it out: the class, the damage at the requirement, then bits 40–71
    /// as they are (ticks, range, damage type, attribute).
    fn copied(part: felt252, requirement: u8) -> (u8, u8, u128) {
        let (low, _) = PackingTrait::split(part);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let (rest, slot) = DivRem::div_rem(low, s8);
        let (rest, hands) = DivRem::div_rem(rest, s8);
        let (rest, class) = DivRem::div_rem(rest, s8);
        let (rest, low_damage) = DivRem::div_rem(rest, s8);
        let (rest, high_damage) = DivRem::div_rem(rest, s8);
        let requirement: u128 = if requirement > MAX_REQUIREMENT {
            MAX_REQUIREMENT.into()
        } else {
            requirement.into()
        };
        let damage = low_damage + (high_damage - low_damage) * requirement / 9;
        (
            slot.try_into().unwrap(),
            hands.try_into().unwrap(),
            class + damage * P8 + LimbTrait::low_field(rest, P32.try_into().unwrap()) * P16,
        )
    }
}

#[generate_trait]
pub impl BaseAssert of BaseAssertTrait {
    /// A known slot; hands 1 or 2 on a weapon, 0 elsewhere (design/15's table). A weapon has a
    /// class, a damage that does not fall from requirement 0 to 9 and stays within the
    /// flattening's bound, at least one tick, a damage type and an attribute; any other base has
    /// no statistic.
    fn assert_valid(self: @Base) {
        assert(*self.slot >= slot::WEAPON && *self.slot <= slot::LAST, errors::SLOT);
        if *self.slot == slot::WEAPON {
            assert(*self.hands == 1 || *self.hands == 2, errors::HANDS);
            assert(*self.class >= weapon::SWORD && *self.class <= weapon::LAST, errors::CLASS);
            assert(
                *self.damage_0 <= *self.damage_9 && *self.damage_9 <= MAX_WEAPON_BASE_DAMAGE,
                errors::DAMAGE,
            );
            assert(*self.ticks != 0, errors::TICKS);
            assert(
                *self.damage_type >= damage::SLASHING && *self.damage_type <= damage::LAST,
                errors::DAMAGE_TYPE,
            );
            assert(*self.attribute != 0, errors::ATTRIBUTE);
        } else {
            assert(*self.hands == 0, errors::HANDS);
            assert(
                *self.class == 0
                    && *self.damage_0 == 0
                    && *self.damage_9 == 0
                    && *self.ticks == 0
                    && *self.range == 0
                    && *self.damage_type == 0
                    && *self.attribute == 0,
                errors::NOT_A_WEAPON,
            );
        }
    }
}

pub impl BaseRecord of Record<Base> {
    const KIND: u8 = BASE;

    fn pack(self: @Base) -> Span<felt252> {
        self.assert_valid();
        let low = (*self.slot).into()
            + (*self.hands).into() * P8
            + (*self.class).into() * P16
            + (*self.damage_0).into() * P24
            + (*self.damage_9).into() * P32
            + (*self.ticks).into() * P40
            + (*self.range).into() * P48
            + (*self.damage_type).into() * P56
            + (*self.attribute).into() * P64;
        array![PackingTrait::join(low, 0), LIVE].span()
    }

    fn unpack(parts: Span<felt252>) -> Base {
        let (low, _) = PackingTrait::split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let mut rest = low;
        let slot = LimbTrait::peel(ref rest, s8).try_into().unwrap();
        let hands = LimbTrait::peel(ref rest, s8).try_into().unwrap();
        Base {
            slot,
            hands,
            class: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            damage_0: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            damage_9: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            ticks: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            range: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            damage_type: LimbTrait::peel(ref rest, s8).try_into().unwrap(),
            attribute: LimbTrait::low_field(rest, s8).try_into().unwrap(),
        }
    }
}

/// The record's unit tests (CBT-08a, WPN-01): the fields of `BASE` from bit 0 of part 0 (slot,
/// hands, then a weapon's statistics), and an item's weapon at its requirement.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::combat::{damage, weapon};
    use crate::types::content::Record;
    use super::{Base, BaseAssert, BasePartTrait, BaseRecord, BaseTrait, Weapon, WeaponTrait, slot};

    /// design/15's axe and bow (Axes 3, Archery 7: the seed's attribute ids).
    fn axe() -> Base {
        BaseTrait::weapon(1, weapon::AXE, 9, 17, 1, 1, damage::SLASHING, 3)
    }
    fn bow() -> Base {
        BaseTrait::weapon(2, weapon::BOW, 11, 21, 2, 6, damage::PIERCING, 7)
    }

    #[test]
    fn test_base_round_trip() {
        let maul = BaseTrait::weapon(2, weapon::MAUL, 13, 27, 2, 1, damage::BLUNT, 4);
        assert(Record::unpack(maul.pack()) == maul, 'round trip');
        assert(Record::unpack(bow().pack()) == bow(), 'bow round trip');
        assert(maul.is_two_handed() && !axe().is_two_handed(), 'hands');
        let feet = BaseTrait::new(slot::FEET, 0);
        assert(feet.pack() == array![7 + LIVE, LIVE].span(), 'bits: slot 0');
        assert(Record::unpack(feet.pack()) == feet, 'armor round trip');
        // slot 0, hands 8, class 16, damage at 0 24 and at 9 32, ticks 40, range 48, type 56,
        // attribute 64.
        let bits: u256 = (*axe().pack()[0] - LIVE).into();
        assert(
            bits.low == 1
                + 0x100
                + 0x20000
                + 0x9000000
                + 0x1100000000
                + 0x10000000000
                + 0x1000000000000
                + 0x100000000000000
                + 0x30000000000000000,
            'bits: the axe',
        );
        // A record never written unpacks as slot 0: no slot.
        assert(Record::<Base>::unpack(array![0, 0].span()).slot == 0, 'none');
        for s in slot::OFF_HAND..slot::LAST + 1 {
            BaseTrait::new(s, 0).assert_valid();
        }
        axe().assert_valid();
    }

    // design/15: the damage grows from requirement 0 to 9, rounded down, and stops at 9; the
    // other statistics are the base's.
    #[test]
    fn test_base_weapon_at_requirement() {
        let at_0 = Weapon {
            class: weapon::AXE,
            damage: 9,
            ticks: 1,
            range: 1,
            damage_type: damage::SLASHING,
            attribute: 3,
        };
        assert(axe().at(0) == at_0, 'axe at 0');
        assert(axe().at(9) == Weapon { damage: 17, ..at_0 }, 'axe at 9');
        assert(axe().at(4) == Weapon { damage: 9 + 8 * 4 / 9, ..at_0 }, 'axe at 4: 12');
        assert(axe().at(200) == axe().at(9), 'stops at 9');
        assert(bow().at(0).damage == 11 && bow().at(9).damage == 21, 'bow');
        assert(BaseTrait::new(slot::CHEST, 0).at(5) == Default::default(), 'not a weapon');
        for requirement in array![0_u8, 3, 4, 9, 12] {
            for base in array![axe(), bow(), BaseTrait::new(slot::CHEST, 0)] {
                let copied = BasePartTrait::copied(*base.pack()[0], requirement);
                assert(copied == (base.slot, base.hands, base.at(requirement).pack()), 'copied');
            }
        }
        let packed = bow().at(3).pack();
        assert(WeaponTrait::unpack(packed) == bow().at(3), 'weapon round trip');
        assert(
            packed == 4
                + 14 * 0x100
                + 2 * 0x10000
                + 6 * 0x1000000
                + 2 * 0x100000000
                + 7 * 0x10000000000,
            'weapon bits',
        );
    }

    #[test]
    #[should_panic(expected: 'base: slot')]
    fn test_base_slot_refused() {
        BaseTrait::new(slot::LAST + 1, 0).pack();
    }

    #[test]
    #[should_panic(expected: 'base: slot')]
    fn test_base_no_slot_refused() {
        BaseTrait::new(0, 0).pack();
    }

    #[test]
    #[should_panic(expected: 'base: hands')]
    fn test_base_weapon_hands_refused() {
        BaseTrait::weapon(3, weapon::AXE, 9, 17, 1, 1, damage::SLASHING, 3).pack();
    }

    #[test]
    #[should_panic(expected: 'base: hands')]
    fn test_base_armor_hands_refused() {
        BaseTrait::new(slot::OFF_HAND, 1).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon class')]
    fn test_base_weapon_class_refused() {
        BaseTrait::weapon(1, weapon::LAST + 1, 9, 17, 1, 1, damage::SLASHING, 3).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon class')]
    fn test_base_weapon_without_class_refused() {
        BaseTrait::new(slot::WEAPON, 1).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon damage')]
    fn test_base_weapon_damage_falling_refused() {
        BaseTrait::weapon(1, weapon::AXE, 17, 9, 1, 1, damage::SLASHING, 3).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon damage')]
    fn test_base_weapon_damage_above_27_refused() {
        BaseTrait::weapon(2, weapon::MAUL, 13, 28, 2, 1, damage::BLUNT, 4).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon ticks')]
    fn test_base_weapon_ticks_refused() {
        BaseTrait::weapon(1, weapon::AXE, 9, 17, 0, 1, damage::SLASHING, 3).pack();
    }

    #[test]
    #[should_panic(expected: 'base: damage type')]
    fn test_base_weapon_damage_type_refused() {
        BaseTrait::weapon(1, weapon::AXE, 9, 17, 1, 1, damage::LAST + 1, 3).pack();
    }

    #[test]
    #[should_panic(expected: 'base: weapon attribute')]
    fn test_base_weapon_attribute_refused() {
        BaseTrait::weapon(1, weapon::AXE, 9, 17, 1, 1, damage::SLASHING, 0).pack();
    }

    #[test]
    #[should_panic(expected: 'base: stats off a weapon')]
    fn test_base_armor_stats_refused() {
        Base { class: weapon::SWORD, ..BaseTrait::new(slot::CHEST, 0) }.pack();
    }
}
