//! `AdventurerCore` as stored (`StoredCore`): one word, the model's packer layout with `LIVE`
//! (`models::adventurer`). The paths that need a few of its fields, or change one, read and change
//! the word by arithmetic, where the packer decodes and encodes every field (measured in ENG-R1a,
//! l2 gas: 42,000 to unpack and 41,000 to pack; a field read is one or two divisions, a change one
//! addition). The model and its packer stay the layout and the oracle: each method is pinned
//! against the packer in the tests. Only the store reads and writes it (`HubStore::get_core`).

use grimworld_logic::packing::{
    LIVE, P104, P112, P120, P32, P48, P56, P96, byte_at, low_field, split, u16_at, u32_at,
};
use super::adventurer::AdventurerAssert;

/// `AdventurerCore` as stored, one word.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct StoredCore {
    pub word: felt252,
}

const LEVEL_ONE: felt252 = 0x1000000000000000000000000;
const PROFESSION_UNIT: felt252 = 0x10000000000000000000000000000;
/// Added to a stored `AdventurerCore` whose status is `ACTIVE`, it becomes `DELETED` (bit 176).
const DELETED_MARK: felt252 = 0x100000000000000000000000000000000000000000000;
/// `AdventurerCore.pack_lanes` (bit 184) and `experience` (bit 32) as units of the stored word.
const PACK_LANES_UNIT: felt252 = 0x10000000000000000000000000000000000000000000000;
const EXPERIENCE_UNIT: felt252 = 0x100000000;
#[generate_trait]
pub impl StoredCoreImpl of StoredCoreTrait {
    /// The core of a new adventurer: its account, level 1, its profession, every other field 0
    /// (`ACTIVE`).
    #[inline(always)]
    fn new(account: u32, profession: u8) -> StoredCore {
        StoredCore { word: LIVE + account.into() + LEVEL_ONE + profession.into() * PROFESSION_UNIT }
    }

    /// `(account, status, pack_lanes)`, without decoding the others.
    fn fields(self: @StoredCore) -> (u32, u8, u16) {
        let (low, high) = split(*self.word);
        (
            low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            byte_at(high, P48),
            u16_at(high, P56),
        )
    }

    /// `(experience, level, rank, profession)`.
    fn profile(self: @StoredCore) -> (u32, u8, u8, u8) {
        let (low, _) = split(*self.word);
        (u32_at(low, P32), byte_at(low, P96), byte_at(low, P104), byte_at(low, P112))
    }

    /// The secondary profession (0: none yet; design/03, at Copper rank).
    fn secondary(self: @StoredCore) -> u8 {
        let (low, _) = split(*self.word);
        byte_at(low, P120)
    }

    /// Marked `DELETED` (it is `ACTIVE`), every other field kept: an adventurer is never zeroed
    /// (D-33).
    #[inline(always)]
    fn deleted(self: StoredCore) -> StoredCore {
        StoredCore { word: self.word + DELETED_MARK }
    }

    /// `filled` pack lanes more and `emptied` fewer (`pack_lanes`, bits 184-199): the balance
    /// changes that fill or empty a lane keep it (ENG-01 fix loop 1, F-5).
    #[inline(always)]
    fn with_pack_lanes(self: StoredCore, filled: u16, emptied: u16) -> StoredCore {
        StoredCore {
            word: self.word + filled.into() * PACK_LANES_UNIT - emptied.into() * PACK_LANES_UNIT,
        }
    }

    /// `amount` experience more (bits 32-63), refused past a `u32`. What a level needs is
    /// design/03's rule for a later lot: the level is not raised here (escalated in ENG-06's
    /// report).
    fn with_experience(self: StoredCore, amount: u32) -> StoredCore {
        let (experience, _, _, _) = self.profile();
        AdventurerAssert::assert_experience(experience, amount);
        StoredCore { word: self.word + amount.into() * EXPERIENCE_UNIT }
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::super::adventurer::{ACTIVE, AdventurerCore, DELETED};
    use super::{StoredCore, StoredCoreTrait};

    fn stored_core(model: AdventurerCore) -> StoredCore {
        StoredCore { word: StorePacking::pack(model) }
    }

    // The core's fields, the deletion mark, pack lanes and experience, against the packer.
    #[test]
    #[available_gas(l2_gas: 302159)] // ceil(1.05 × 287770 measured)
    fn test_core_words() {
        let full = AdventurerCore {
            account: 0x12345678,
            experience: 0xFFFFFFFF,
            merit: 0xFFFFFFFF,
            level: 255,
            rank: 255,
            profession: 255,
            secondary: 255,
            unspent: 0xFFFF,
            trials_first: 0xFFFF,
            trials_tried: 0xFFFF,
            status: ACTIVE,
            pack_lanes: 0xFFFF,
        };
        let stored = stored_core(full);
        assert(stored.fields() == (0x12345678, ACTIVE, 0xFFFF), 'core fields');
        let deleted = stored_core(AdventurerCore { status: DELETED, ..full });
        assert(stored.deleted() == deleted, 'deleted mark');
        assert(deleted.fields() == (0x12345678, DELETED, 0xFFFF), 'deleted fields');
        assert(stored.secondary() == 255, 'secondary');

        let some = AdventurerCore {
            account: 3,
            experience: 100,
            level: 4,
            rank: 2,
            profession: 3,
            pack_lanes: 7,
            ..Default::default(),
        };
        let stored = stored_core(some);
        assert(stored.profile() == (100, 4, 2, 3), 'profile');
        assert(
            stored.with_pack_lanes(2, 5) == stored_core(AdventurerCore { pack_lanes: 4, ..some }),
            'lanes',
        );
        let more = stored.with_experience(0xFFFFFFFF - 100);
        assert(more == stored_core(AdventurerCore { experience: 0xFFFFFFFF, ..some }), 'xp');
    }

    #[test]
    #[should_panic(expected: 'experience overflow')]
    #[available_gas(l2_gas: 77910)] // ceil(1.05 × 74200 measured)
    fn test_experience_overflow_refused() {
        stored_core(AdventurerCore { experience: 100, ..Default::default() })
            .with_experience(0xFFFFFFFF - 99);
    }
}
