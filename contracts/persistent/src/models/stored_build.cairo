//! The three words `set_build` writes (`StoredBuild`): the `Build` word, the belt and the
//! equipment worn (`models::lanes::StoredLanes`), as the caller sends them with `LIVE` added, each
//! checked for its layout, and written as they are, without a packer: decoding and encoding them
//! would cost what the check already did. Only the store writes it
//! (`HubStoreTrait::set_adventurer_build`).

use grimworld_logic::packing::{LIVE, Lanes32, P12, P32, P36, P4, P96};
use starknet::storage_access::StorePacking;
use crate::helpers::BitTrait;
use super::adventurer::{BeltTrait, Build};
use super::lanes::{StoredLanes, StoredLanesTrait};

/// The three words `set_build` writes, as sent with `LIVE` added, each checked for its layout
/// (`StoredBuildTrait::new`) and written as it is, without a packer: the `Build` word, the belt
/// and the equipment worn as stored pages (`models::lanes::StoredLanes`).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct StoredBuild {
    pub build: felt252,
    pub belt: StoredLanes,
    pub equipped: StoredLanes,
}

/// The stored `Build` of a new adventurer: an empty bar, no attribute rank, `NO_ELITE`.
pub const NEW_BUILD: felt252 = 0x4000000000000000000ff000000000000000000000000000000000000000000;

#[generate_trait]
pub impl StoredBuildImpl of StoredBuildTrait {
    /// The words `set_build` received, each checked for its layout in this order: the build, the
    /// belt, the equipment (`StoredBuildAssert`).
    #[inline(always)]
    fn new(build: felt252, belt: felt252, equipped: felt252) -> StoredBuild {
        StoredBuild {
            build: StoredBuildAssert::assert_build_layout(build),
            belt: StoredLanes { word: StoredBuildAssert::assert_belt_layout(belt) },
            equipped: StoredLanes { word: StoredBuildAssert::assert_equipped_layout(equipped) },
        }
    }

    /// The bar, the attributes and the elite slot.
    #[inline(always)]
    fn build(self: @StoredBuild) -> Build {
        StorePacking::unpack(*self.build)
    }

    /// The belt's `(items, counts)`.
    #[inline(always)]
    fn belt(self: @StoredBuild) -> ([u32; 4], [u8; 4]) {
        BeltTrait::read(self.belt)
    }

    /// The entities worn, by lane.
    #[inline(always)]
    fn equipped(self: @StoredBuild) -> Lanes32 {
        self.equipped.decoded()
    }
}

pub mod errors {
    /// A bit outside the fields of `Build`, `belt` or `equipped` (they come without `LIVE`).
    pub const BUILD_LAYOUT: felt252 = 'build: layout';
    pub const BELT_LAYOUT: felt252 = 'belt: layout';
    pub const EQUIPPED_LAYOUT: felt252 = 'equipped: layout';
}

/// The layouts of the words `set_build` receives (ENG-01 §3.3, §4.3), each returned as stored.
#[generate_trait]
pub impl StoredBuildAssert of StoredBuildAssertTrait {
    /// The word of a `Build` sent without `LIVE`; a bit outside its fields (164-167, 176 and up)
    /// is refused.
    fn assert_build_layout(build: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(build);
        let (above, _) = DivRem::div_rem(high, P36.try_into().unwrap());
        assert(above < P12 && above % P4 == 0, errors::BUILD_LAYOUT);
        build + LIVE
    }

    /// The word of a belt sent without `LIVE`: lanes 5 and 6 are empty.
    fn assert_belt_layout(belt: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(belt);
        assert(high < P32, errors::BELT_LAYOUT);
        belt + LIVE
    }

    /// The word of `equipped` sent without `LIVE`: nothing above lane 6.
    fn assert_equipped_layout(equipped: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(equipped);
        assert(high < P96, errors::EQUIPPED_LAYOUT);
        equipped + LIVE
    }
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{LIVE, Lanes32};
    use starknet::storage_access::StorePacking;
    use super::StoredBuildTrait;
    use super::super::adventurer::Build;

    // The words `set_build` receives, as stored: `LIVE` added, each read back as its model.
    #[test]
    #[available_gas(l2_gas: 189609)] // ceil(1.05 × 180580 measured)
    fn test_stored_build() {
        let build = Build { bar: [3, 0, 0, 0, 0, 0, 0, 9], attributes: 0x21, elite_slot: 7 };
        let counts: u32 = 0xFF + 0x2 * 0x100;
        let belt = Lanes32 { lanes: [8, 15, 0, 0, counts, 0, 0] };
        let equipped = Lanes32 { lanes: [1, 0, 2, 0, 0, 0, 0xFFFFFFFF] };
        let build_word: felt252 = StorePacking::pack(build);
        let belt_word: felt252 = StorePacking::pack(belt);
        let equipped_word: felt252 = StorePacking::pack(equipped);
        let sent = StoredBuildTrait::new(build_word - LIVE, belt_word - LIVE, equipped_word - LIVE);
        assert(sent.build == build_word && sent.build() == build, 'build');
        assert(
            sent.belt.word == belt_word && sent.belt() == ([8, 15, 0, 0], [0xFF, 2, 0, 0]), 'belt',
        );
        assert(sent.equipped.word == equipped_word && sent.equipped() == equipped, 'equipped');
    }
}
