//! `KIT`: its checks and its record (layout: `models::index::Kit`). What a new adventurer of a
//! profession receives at `create_adventurer` (D-309): a purse priced from the starter skills the
//! record names, and its starter weapon. Content, not code (pillar 6): a later kit is a seed
//! change, with no new class.

use crate::helpers::packing::{LimbTrait, P16, PackingTrait};
use crate::types::content::{KIT, Record};
use crate::types::profession::PROFESSIONS;
pub use super::index::Kit;

/// Starter skills a kit names at most (design/03, *MVP starter skills*: six per profession).
pub const SKILLS: u8 = 6;

pub mod errors {
    /// An id that is not a profession's (1 to `PROFESSIONS`).
    pub const PROFESSION: felt252 = 'kit: not a profession';
    /// A skill after an empty one.
    pub const GAP: felt252 = 'kit: gap';
    /// A skill named twice.
    pub const DUPLICATE: felt252 = 'kit: skill twice';
    // The registry's checks against other records.
    /// A skill the registry does not hold.
    pub const NO_SKILL: felt252 = 'kit: no skill';
    /// A skill of another profession than the kit's.
    pub const SKILL_PROFESSION: felt252 = 'kit: skill of another prof';
    /// A weapon that is no `BASE` of the weapon slot.
    pub const NO_WEAPON: felt252 = 'kit: weapon not a weapon base';
}

#[generate_trait]
pub impl KitImpl of KitTrait {
    fn new(weapon: u16, skills: [u16; 6]) -> Kit {
        Kit { weapon, skills }
    }

    /// The starter skills it names, 0 to `SKILLS`: they are packed from the first.
    fn count(self: @Kit) -> u8 {
        let mut count: u8 = 0;
        for skill in self.skills.span() {
            if *skill != 0 {
                count += 1;
            }
        }
        count
    }
}

#[generate_trait]
pub impl KitAssert of KitAssertTrait {
    /// `Registry`'s content check: the id is a profession's, its skills are packed from the first
    /// and none is named twice. That they exist and are of the profession is checked by the
    /// registry against their records.
    fn assert_legal(self: @Kit, id: u32) {
        assert(id >= 1 && id <= PROFESSIONS.into(), errors::PROFESSION);
        let skills = self.skills.span();
        let mut ended = false;
        for i in 0..skills.len() {
            let skill = *skills[i];
            if skill == 0 {
                ended = true;
                continue;
            }
            assert(!ended, errors::GAP);
            for j in 0..i {
                assert(*skills[j] != skill, errors::DUPLICATE);
            }
        }
    }
}

pub impl KitRecord of Record<Kit> {
    const KIND: u8 = KIT;

    fn pack(self: @Kit) -> Span<felt252> {
        let mut low: u128 = 0;
        let mut shift: u128 = 1;
        for skill in self.skills.span() {
            shift *= P16;
            low += (*skill).into() * shift;
        }
        array![PackingTrait::join(low + (*self.weapon).into(), 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Kit {
        let (mut low, _) = PackingTrait::split(*parts[0]);
        let size: NonZero<u128> = P16.try_into().unwrap();
        let weapon = LimbTrait::peel(ref low, size).try_into().unwrap();
        let mut skills: Array<u16> = array![];
        for _ in 0..SKILLS {
            skills.append(LimbTrait::peel(ref low, size).try_into().unwrap());
        }
        let s = skills.span();
        Kit { weapon, skills: [*s[0], *s[1], *s[2], *s[3], *s[4], *s[5]] }
    }
}

#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::content::Record;
    use super::{KitAssert, KitRecord, KitTrait};

    #[test]
    fn test_kit_bits_and_round_trip() {
        let kit = KitTrait::new(0xabcd, [1, 2, 3, 0x1234, 5, 0xffff]);
        let parts = kit.pack();
        assert(parts.len() == 1, 'one part');
        let bits: u256 = (*parts[0] - LIVE).into();
        assert(bits.low % 0x10000 == 0xabcd, 'weapon at 0');
        assert((bits.low / 0x10000) % 0x10000 == 1, 'skill 1 at 16');
        assert(bits.low / 0x10000000000000000000000000000 == 0xffff, 'skill 6 at 96');
        assert(KitRecord::unpack(parts) == kit, 'round trip');
        assert(kit.count() == 6, 'six');
        assert(KitTrait::new(0, [7, 8, 0, 0, 0, 0]).count() == 2, 'two');
        let empty = KitTrait::new(0, [0; 6]);
        assert(KitRecord::unpack(empty.pack()) == empty, 'empty round trip');
    }

    #[test]
    fn test_kit_legal() {
        KitTrait::new(1, [1, 2, 3, 4, 5, 6]).assert_legal(1);
        KitTrait::new(0, [9, 0, 0, 0, 0, 0]).assert_legal(6);
        KitTrait::new(0, [0; 6]).assert_legal(3);
    }

    #[test]
    #[should_panic(expected: 'kit: not a profession')]
    fn test_kit_not_a_profession() {
        KitTrait::new(0, [0; 6]).assert_legal(7);
    }

    #[test]
    #[should_panic(expected: 'kit: gap')]
    fn test_kit_gap() {
        KitTrait::new(0, [1, 0, 2, 0, 0, 0]).assert_legal(1);
    }

    #[test]
    #[should_panic(expected: 'kit: skill twice')]
    fn test_kit_duplicate() {
        KitTrait::new(0, [1, 2, 1, 0, 0, 0]).assert_legal(1);
    }
}
