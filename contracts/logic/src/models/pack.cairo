//! `PACK`: its constructor, its checks and its record (layout: `models::index::Pack`). A pack
//! template (design/05): its castes with their count bounds and a level offset.
//!
//! **Which goblin is which caste** is derived from the template and the pack's `count` alone
//! (`PackTrait::caste`), since a placed pack stores only its template and count (ENG-01 §3.2):
//! each caste first takes its `min`, then the goblins left go to the castes in order, each up to
//! its `max`.

use crate::content::{PACK, Record};
use crate::helpers::signed::SignedTrait;
use crate::packing::{P16, P24, P32, P64, P8, P96, join, peel, split};
use crate::types::MAX_PACK_SIZE;
pub use super::index::{Pack, PackCaste};

pub mod errors {
    pub const BOUNDS: felt252 = 'pack: min above max';
    /// A caste entry of id 0 with bounds.
    pub const EMPTY: felt252 = 'pack: empty with bounds';
    /// A template that names no caste.
    pub const NO_CASTE: felt252 = 'pack: no caste';
    /// More goblins than a pack holds at its fewest (E-3: 5).
    pub const SIZE: felt252 = 'pack: min above 5';
    /// A template whose castes' minimums sum to 0 (R-42, BND-01): a pack of no goblin at its fewest.
    pub const NO_FEWEST: felt252 = 'pack: fewest is 0';
}

#[generate_trait]
pub impl PackImpl of PackTrait {
    fn new(castes: [PackCaste; 5], level: i8) -> Pack {
        Pack { castes, level }
    }

    /// The fewest and the most goblins it holds, the most at most `MAX_PACK_SIZE` (E-3).
    fn bounds(self: @Pack) -> (u8, u8) {
        let mut low: u16 = 0;
        let mut high: u16 = 0;
        for entry in self.castes.span() {
            if *entry.caste != 0 {
                low += (*entry.min).into();
                high += (*entry.max).into();
            }
        }
        let cap: u16 = MAX_PACK_SIZE.into();
        let high = if high > cap {
            cap
        } else {
            high
        };
        let low = if low > high {
            high
        } else {
            low
        };
        (low.try_into().unwrap(), high.try_into().unwrap())
    }

    /// The caste of goblin `k` of a pack of `count` (module doc); 0 beyond what the template
    /// holds.
    fn caste(self: @Pack, count: u8, k: u8) -> u16 {
        let (low, _) = self.bounds();
        let mut extra = if count > low {
            count - low
        } else {
            0
        };
        let mut seen: u8 = 0;
        let mut found: u16 = 0;
        for entry in self.castes.span() {
            if found == 0 && *entry.caste != 0 {
                let room = *entry.max - *entry.min;
                let more = if extra < room {
                    extra
                } else {
                    room
                };
                extra -= more;
                seen += *entry.min + more;
                if k < seen {
                    found = *entry.caste;
                }
            }
        }
        found
    }
}

#[generate_trait]
pub impl PackAssert of PackAssertTrait {
    fn assert_valid(self: @Pack) {
        for entry in self.castes.span() {
            assert(*entry.min <= *entry.max, errors::BOUNDS);
        }
    }

    /// `Registry`'s content check (ENG-05, after CBT-05a): `min ≤ max` for each caste, an entry
    /// without a caste has no bounds, the template names a caste, and its castes' minimums sum to
    /// at most 5 (E-3: a pack is at most 5 goblins; its maximum is held at 5 by `bounds`), and at
    /// least 1 (R-42, BND-01: the reveal reads a fewest of 0 as 1 when it draws the pack's size,
    /// so a template of 0 would say a fewest that no pack ever has). That a caste exists is the
    /// content pipeline's (OPS-01).
    fn assert_legal(self: @Pack) {
        self.assert_valid();
        let mut castes: u8 = 0;
        let mut low: u16 = 0;
        for entry in self.castes.span() {
            if *entry.caste == 0 {
                assert(*entry.min == 0 && *entry.max == 0, errors::EMPTY);
            } else {
                castes += 1;
                low += (*entry.min).into();
            }
        }
        assert(castes != 0, errors::NO_CASTE);
        assert(low <= MAX_PACK_SIZE.into(), errors::SIZE);
        assert(low != 0, errors::NO_FEWEST);
    }
}

/// Its bits in a record's limb, and back (the field order of the record's layout).
#[generate_trait]
pub impl PackCasteBits of PackCasteBitsTrait {
    #[inline(never)]
    fn bits(entry: @PackCaste) -> u128 {
        (*entry.caste).into() + (*entry.min).into() * P16 + (*entry.max).into() * P24
    }

    #[inline(never)]
    fn peel(ref rest: u128) -> PackCaste {
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let caste = peel(ref rest, P16.try_into().unwrap());
        let min = peel(ref rest, s8);
        let max = peel(ref rest, s8);
        PackCaste {
            caste: caste.try_into().unwrap(),
            min: min.try_into().unwrap(),
            max: max.try_into().unwrap(),
        }
    }
}

pub impl PackRecord of Record<Pack> {
    const KIND: u8 = PACK;

    fn pack(self: @Pack) -> Span<felt252> {
        self.assert_valid();
        let [c0, c1, c2, c3, c4] = self.castes;
        let low = PackCasteBitsTrait::bits(c0)
            + PackCasteBitsTrait::bits(c1) * P32
            + PackCasteBitsTrait::bits(c2) * P64
            + PackCasteBitsTrait::bits(c3) * P96;
        let high = PackCasteBitsTrait::bits(c4) + SignedTrait::bits8(*self.level) * P32;
        array![join(low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> Pack {
        let (mut low, mut high) = split(*parts[0]);
        let c0 = PackCasteBitsTrait::peel(ref low);
        let c1 = PackCasteBitsTrait::peel(ref low);
        let c2 = PackCasteBitsTrait::peel(ref low);
        let c3 = PackCasteBitsTrait::peel(ref low);
        let c4 = PackCasteBitsTrait::peel(ref high);
        let level = peel(ref high, P8.try_into().unwrap());
        Pack { castes: [c0, c1, c2, c3, c4], level: SignedTrait::from8(level) }
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use super::{PackAssert, PackCaste, PackRecord, PackTrait};

    #[test]
    #[available_gas(l2_gas: 153195)] // ceil(1.05 × 145900 measured)
    fn test_pack_bits_and_round_trip() {
        let first = PackCaste { caste: 0xabcd, min: 1, max: 0x12 };
        let last = PackCaste { caste: 0x1234, min: 2, max: 0xff };
        let pack = PackTrait::new(
            [first, Default::default(), Default::default(), Default::default(), last], -3,
        );
        let parts = pack.pack();
        let high: felt252 = 0x1234 + 2 * 0x10000 + 0xff * 0x1000000 + 0xfd * 0x100000000;
        assert(
            *parts[0] == 0xabcd
                + 0x10000
                + 0x12 * 0x1000000
                + high * 0x100000000000000000000000000000000
                + LIVE,
            'bits',
        );
        assert(PackRecord::unpack(parts) == pack, 'round trip');
    }

    #[test]
    #[should_panic(expected: 'pack: min above max')]
    #[available_gas(l2_gas: 83370)] // ceil(1.05 × 79400 measured)
    fn test_pack_bounds_refused() {
        let wrong = PackCaste { caste: 1, min: 3, max: 2 };
        PackTrait::new(
            [wrong, Default::default(), Default::default(), Default::default(), Default::default()],
            0,
        )
            .pack();
    }

    // Each caste takes its `min`, then the rest in order up to each `max`; never above 5 (E-3).
    #[test]
    #[available_gas(l2_gas: 360623)] // ceil(1.05 × 343450 measured)
    fn test_pack_castes_of_a_count() {
        let pack = PackTrait::new(
            [
                PackCaste { caste: 7, min: 1, max: 2 }, PackCaste { caste: 8, min: 1, max: 4 },
                PackCaste { caste: 9, min: 0, max: 3 }, Default::default(), Default::default(),
            ],
            0,
        );
        assert(pack.bounds() == (2, 5), 'bounds');
        // count 2: 7, 8
        assert(pack.caste(2, 0) == 7 && pack.caste(2, 1) == 8 && pack.caste(2, 2) == 0, '2');
        // count 4: 7, 7, 8, 8
        assert(pack.caste(4, 1) == 7 && pack.caste(4, 2) == 8 && pack.caste(4, 3) == 8, '4');
        // count 5: 7, 7, 8, 8, 8
        assert(pack.caste(5, 4) == 8, '5');
    }

    fn template(first: PackCaste, second: PackCaste) -> super::Pack {
        PackTrait::new(
            [first, second, Default::default(), Default::default(), Default::default()], 0,
        )
    }

    #[test]
    #[available_gas(l2_gas: 34703)] // ceil(1.05 × 33050 measured)
    fn test_pack_legal() {
        template(PackCaste { caste: 1, min: 2, max: 3 }, PackCaste { caste: 2, min: 3, max: 9 })
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'pack: empty with bounds')]
    #[available_gas(l2_gas: 26471)] // ceil(1.05 × 25210 measured)
    fn test_pack_empty_with_bounds_refused() {
        template(PackCaste { caste: 1, min: 1, max: 1 }, PackCaste { caste: 0, min: 0, max: 2 })
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'pack: no caste')]
    #[available_gas(l2_gas: 36110)] // ceil(1.05 × 34390 measured)
    fn test_pack_no_caste_refused() {
        template(Default::default(), Default::default()).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'pack: fewest is 0')]
    #[available_gas(l2_gas: 34703)]
    fn test_pack_fewest_zero_refused() {
        template(PackCaste { caste: 1, min: 0, max: 3 }, PackCaste { caste: 2, min: 0, max: 9 })
            .assert_legal();
    }

    #[test]
    #[available_gas(l2_gas: 34703)]
    fn test_pack_fewest_one_legal() {
        template(PackCaste { caste: 1, min: 0, max: 3 }, PackCaste { caste: 2, min: 1, max: 9 })
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'pack: min above 5')]
    #[available_gas(l2_gas: 35858)] // ceil(1.05 × 34150 measured)
    fn test_pack_min_above_five_refused() {
        template(PackCaste { caste: 1, min: 3, max: 3 }, PackCaste { caste: 2, min: 3, max: 4 })
            .assert_legal();
    }
}
