//! `AccountRecord` as stored (`StoredRecord`): one word, the model's packer layout with `LIVE`
//! (`models::account`). `create_adventurer`, `delete_adventurer` and `set_account_owner` read its
//! two counts and change one by an addition, where the packer decodes and encodes five fields
//! (measured in ENG-R1a, l2 gas: about 20,000 to unpack and 18,000 to pack). The model and its
//! packer stay the layout and the oracle: each method is pinned against the packer in the tests.
//! It owns no check: a free slot is the account's (`AccountAssert::assert_free_slot`). Only the
//! store reads and writes it (`HubStoreTrait::get_account_record`).

use grimworld_logic::packing::{P8, byte_at, low_field, split};

/// `AccountRecord` as stored, one word: the paths read its two counts and change one by an
/// addition, where the packer decodes and encodes five fields (about 20,000 and 18,000 l2 gas,
/// measured in ENG-R1a). Each method is pinned against the packer in the tests (the oracle,
/// docs/CAIRO.md §2). Only the store reads and writes it.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct StoredRecord {
    pub word: felt252,
}

/// The stored `AccountRecord` of a new account: `START_SLOTS` slots, nothing else, `LIVE`.
const NEW_RECORD: felt252 = 0x400000000000000000000000000000000000000000000000000000000000003;
/// One more adventurer, added to a stored `AccountRecord` (its field at bit 8).
const ONE_ADVENTURER: felt252 = 0x100;

#[generate_trait]
pub impl StoredRecordImpl of StoredRecordTrait {
    /// The record of a new account.
    #[inline(always)]
    fn new() -> StoredRecord {
        StoredRecord { word: NEW_RECORD }
    }

    /// `(slots, adventurers)`, without decoding the other fields.
    fn counts(self: @StoredRecord) -> (u8, u8) {
        let (low, _) = split(*self.word);
        (low_field(low, P8.try_into().unwrap()).try_into().unwrap(), byte_at(low, P8))
    }

    /// One adventurer more (fewer than its slots ≤ 255: `AccountAssert::assert_free_slot`).
    #[inline(always)]
    fn with_adventurer(self: StoredRecord) -> StoredRecord {
        StoredRecord { word: self.word + ONE_ADVENTURER }
    }

    /// One adventurer less (it has at least one).
    #[inline(always)]
    fn without_adventurer(self: StoredRecord) -> StoredRecord {
        StoredRecord { word: self.word - ONE_ADVENTURER }
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::super::account::{AccountRecord, START_SLOTS};
    use super::{StoredRecord, StoredRecordTrait};

    // The stored record of a new account, its counts, one adventurer more or less, against the
    // packer.
    #[test]
    #[available_gas(l2_gas: 113022)] // ceil(1.05 × 107640 measured)
    fn test_record_words() {
        let new = AccountRecord { slots: START_SLOTS, ..Default::default() };
        assert(StoredRecordTrait::new().word == StorePacking::pack(new), 'new');
        let more = AccountRecord {
            slots: 9, adventurers: 5, highest_rank: 4, vault_panes: 2, lots: 7,
        };
        let stored = StoredRecord { word: StorePacking::pack(more) };
        assert(stored.counts() == (9, 5), 'slots and count');
        let one_more = AccountRecord { adventurers: 6, ..more };
        assert(stored.with_adventurer().word == StorePacking::pack(one_more), 'one more');
        let one_less = AccountRecord { adventurers: 4, ..more };
        assert(stored.without_adventurer().word == StorePacking::pack(one_less), 'one less');
        assert(StorePacking::<AccountRecord, felt252>::unpack(stored.word) == more, 'record trip');
    }
}
