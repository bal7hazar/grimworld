//! Pages of seven `u32` lanes (`Lanes32`, `grimworld_logic::packing`): lanes 0-3 in the low limb,
//! 4-6 in the high limb, 32 bits each, `LIVE` at bit 250. `Hub` keeps several things in such
//! pages (ENG-01 §3.3): an account's list of adventurers, the balances of an owner, the equipment
//! of a pack, what an adventurer wears, its belt.
//!
//! `StoredLanes` is a page as stored, one word, the paths changing one or two lanes of it by an
//! addition: `Lanes32`'s packer decodes and encodes seven lanes (16,000 and 22,000 l2 gas, measured
//! in ENG-R1a) where a lane costs a division or a multiplication. Each method is pinned against the
//! packer in the tests (the oracle, docs/CAIRO.md §2). Only the store reads and writes it.

use grimworld_logic::packing::{
    LIVE, Lanes32, P32, P64, P96, low_field, split, u32_at, unpack_lanes32,
};

pub mod errors {
    /// A lane of a page is 0 to 6.
    pub const LANE_ABOVE_6: felt252 = 'lane above 6';
}

/// The lanes of a decoded page.
#[generate_trait]
pub impl LanesImpl of LanesTrait {
    /// What one unit of lane `lane` (0 to 6) adds to a stored page: a table (docs/CAIRO.md §3).
    fn unit(lane: u8) -> felt252 {
        match lane {
            0 => 0x1,
            1 => 0x100000000,
            2 => 0x10000000000000000,
            3 => 0x1000000000000000000000000,
            4 => 0x100000000000000000000000000000000,
            5 => 0x10000000000000000000000000000000000000000,
            6 => 0x1000000000000000000000000000000000000000000000000,
            _ => LanesAssert::lane_above_6(),
        }
    }

    /// Lane `lane` (0 to 6).
    fn get(self: @Lanes32, lane: u8) -> u32 {
        let [a, b, c, d, e, f, g] = *self.lanes;
        match lane {
            0 => a,
            1 => b,
            2 => c,
            3 => d,
            4 => e,
            5 => f,
            6 => g,
            _ => LanesAssert::lane_above_6(),
        }
    }

    /// The page with lane `lane` (0 to 6) set to `value`.
    fn set(self: @Lanes32, lane: u8, value: u32) -> Lanes32 {
        let [a, b, c, d, e, f, g] = *self.lanes;
        let lanes = match lane {
            0 => [value, b, c, d, e, f, g],
            1 => [a, value, c, d, e, f, g],
            2 => [a, b, value, d, e, f, g],
            3 => [a, b, c, value, e, f, g],
            4 => [a, b, c, d, value, f, g],
            5 => [a, b, c, d, e, value, g],
            6 => [a, b, c, d, e, f, value],
            _ => LanesAssert::lane_above_6(),
        };
        Lanes32 { lanes }
    }
}

#[generate_trait]
pub impl LanesAssert of LanesAssertTrait {
    /// The refusal of a lane above 6 (ENG-04's audit F-6): the last arm of a match on a lane,
    /// which never returns.
    fn lane_above_6() -> core::never {
        core::panic_with_felt252(errors::LANE_ABOVE_6)
    }
}

/// A `Lanes32` page as stored, one word: 0 for a page never written.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct StoredLanes {
    pub word: felt252,
}

/// One felt in storage, the word as it is: no packer runs on a read or a write (ENG-R1b: `Hub`
/// declares its storage with the stored models, ENG-R1a's note 4).
pub impl StoredLanesStorePacking of starknet::storage_access::StorePacking<StoredLanes, felt252> {
    #[inline(always)]
    fn pack(value: StoredLanes) -> felt252 {
        value.word
    }

    #[inline(always)]
    fn unpack(value: felt252) -> StoredLanes {
        StoredLanes { word: value }
    }
}

#[generate_trait]
pub impl StoredLanesImpl of StoredLanesTrait {
    /// An empty page, `LIVE` alone: the page an append starts when it begins one.
    #[inline(always)]
    fn new() -> StoredLanes {
        StoredLanes { word: LIVE }
    }

    /// Lane `lane` (0 to 6), the six others not decoded.
    fn get(self: @StoredLanes, lane: u8) -> u32 {
        let (low, high) = split(*self.word);
        match lane {
            0 => low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            1 => u32_at(low, P32),
            2 => u32_at(low, P64),
            3 => u32_at(low, P96),
            4 => low_field(high, P32.try_into().unwrap()).try_into().unwrap(),
            5 => u32_at(high, P32),
            6 => u32_at(high, P64),
            _ => LanesAssert::lane_above_6(),
        }
    }

    /// Every lane, decoded once: what a scan over the page reads.
    #[inline(always)]
    fn decoded(self: @StoredLanes) -> Lanes32 {
        unpack_lanes32(*self.word)
    }

    /// Whether every lane is 0: a page never written (0), or `LIVE` alone.
    #[inline(always)]
    fn is_empty(self: @StoredLanes) -> bool {
        *self.word == 0 || *self.word == LIVE
    }

    /// `amount` more in lane `lane`, `LIVE` set on a page never written. The caller keeps the
    /// lane within a `u32` (`BalanceAssert::assert_credit`, or a lane that was 0).
    #[inline(always)]
    fn added(self: StoredLanes, lane: u8, amount: u32) -> StoredLanes {
        let base = if self.word == 0 {
            LIVE
        } else {
            self.word
        };
        StoredLanes { word: base + amount.into() * LanesTrait::unit(lane) }
    }

    /// `amount` less in lane `lane`; the caller knows the lane holds it.
    #[inline(always)]
    fn removed(self: StoredLanes, lane: u8, amount: u32) -> StoredLanes {
        StoredLanes { word: self.word - amount.into() * LanesTrait::unit(lane) }
    }

    /// Lane `lane`, which holds `from`, set to `to`.
    #[inline(always)]
    fn replaced(self: StoredLanes, lane: u8, from: u32, to: u32) -> StoredLanes {
        let delta: felt252 = to.into() - from.into();
        StoredLanes { word: self.word + delta * LanesTrait::unit(lane) }
    }
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{LIVE, Lanes32};
    use starknet::storage_access::StorePacking;
    use super::{LanesTrait, StoredLanes, StoredLanesTrait};

    fn stored(page: Lanes32) -> StoredLanes {
        StoredLanes { word: StorePacking::pack(page) }
    }

    // Each lane's unit, `get` and `set`, against the packer.
    #[test]
    #[available_gas(l2_gas: 258594)] // ceil(1.05 × 246280 measured)
    fn test_lanes() {
        let page = Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] };
        let word: felt252 = StorePacking::pack(page);
        for lane in 0..7_u8 {
            let expected = page.set(lane, 0xFFFFFFFF);
            let changed = word + (0xFFFFFFFF - page.get(lane)).into() * LanesTrait::unit(lane);
            assert(changed == StorePacking::pack(expected), 'lane unit');
            assert(expected.get(lane) == 0xFFFFFFFF, 'set then get');
        }
    }

    #[test]
    #[should_panic(expected: 'lane above 6')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_lane_above_6_refused() {
        Lanes32 { lanes: [0; 7] }.get(7);
    }

    #[test]
    #[should_panic(expected: 'lane above 6')]
    #[available_gas(l2_gas: 10700)] // ceil(1.05 × 10190 measured)
    fn test_stored_lane_above_6_refused() {
        StoredLanesTrait::new().get(7);
    }

    // The stored page's lanes, additions, removals and replacements, against the packer.
    #[test]
    #[available_gas(l2_gas: 297276)] // ceil(1.05 × 283120 measured)
    fn test_stored_lanes() {
        let page = Lanes32 { lanes: [1, 0xFFFFFFFF, 3, 0, 5, 6, 0xFFFFFFFE] };
        let word = stored(page);
        for lane in 0..7_u8 {
            assert(word.get(lane) == page.get(lane), 'get');
        }
        assert(word.decoded() == page, 'decoded');
        // An addition to a page never written sets `LIVE`.
        let fresh = StoredLanes { word: 0 }.added(4, 9);
        assert(fresh == stored(Lanes32 { lanes: [0, 0, 0, 0, 9, 0, 0] }), 'fresh page');
        assert(StoredLanesTrait::new().added(0, 11) == fresh.added(0, 11).removed(4, 9), 'new');
        assert(word.added(6, 1) == stored(page.set(6, 0xFFFFFFFF)), 'added');
        assert(word.removed(1, 5) == stored(page.set(1, 0xFFFFFFFA)), 'removed');
        assert(word.removed(0, 1) == stored(page.set(0, 0)), 'removed to 0');
        assert(word.replaced(2, 3, 0xFFFFFFFF) == stored(page.set(2, 0xFFFFFFFF)), 'up');
        assert(word.replaced(1, 0xFFFFFFFF, 7) == stored(page.set(1, 7)), 'down');
        assert(StoredLanesTrait::new() == stored(Lanes32 { lanes: [0; 7] }), 'empty is LIVE');
        assert(StoredLanes { word: 0 }.is_empty() && StoredLanesTrait::new().is_empty(), 'empty');
        assert(!fresh.is_empty() && !word.is_empty(), 'not empty');
        assert(StoredLanesTrait::new().word == LIVE, 'live');
    }
}
