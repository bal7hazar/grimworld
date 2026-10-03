//! `QUOTAS`: its constructor, its checks and its record (layout: `models::index::QuotaSet`). A
//! location's quotas (ADR-0006 kind 2): what its chunks must hold in total, placed by sampling
//! without replacement at each reveal (`types::reveal`). Id = the location's (D-145).

use crate::content::{QUOTAS, Record};
use crate::packing::{P16, P24, P32, P64, P8, P96, join, peel, split};
pub use super::index::{Quota, QuotaSet};

/// Quota kinds (ADR-0006 *Quotas*, design/17, design/18).
pub mod kind {
    /// A dungeon floor's exit: an object (`chunk::object::EXIT`), its `param` the floor gate.
    pub const EXIT: u8 = 1;
    /// A Rift's Heart (design/17): a pack, its `param` the `PACK` template.
    pub const HEART: u8 = 2;
    /// A stillstone vein (design/17): an object.
    pub const VEIN: u8 = 3;
    /// A collector's camp (design/18): an object, its `param` the `COLLECTOR`.
    pub const COLLECTOR: u8 = 4;
    /// A landmark (design/14, design/18): an object, its `param` the `LANDMARK`.
    pub const LANDMARK: u8 = 5;
    /// An authored chunk (ADR-0006 *Set pieces*): its `param` the `SET_PIECE`.
    pub const SET_PIECE: u8 = 6;
    /// The last kind.
    pub const LAST: u8 = 6;
}

/// Quotas of a location.
pub const COUNT: u8 = 6;

pub mod errors {
    pub const KIND: felt252 = 'quotas: kind';
}

#[generate_trait]
pub impl QuotaSetImpl of QuotaSetTrait {
    fn new(quotas: [Quota; 6]) -> QuotaSet {
        QuotaSet { quotas }
    }
}

#[generate_trait]
pub impl QuotaSetAssert of QuotaSetAssertTrait {
    /// Every kind is 0 (none) or a quota kind.
    fn assert_valid(self: @QuotaSet) {
        for quota in self.quotas.span() {
            assert(*quota.kind <= kind::LAST, errors::KIND);
        }
    }
}

/// Its bits in a record's limb, and back (the field order of the record's layout).
#[generate_trait]
pub impl QuotaBits of QuotaBitsTrait {
    #[inline(never)]
    fn bits(quota: @Quota) -> u128 {
        (*quota.kind).into() + (*quota.param).into() * P8 + (*quota.count).into() * P24
    }

    #[inline(never)]
    fn peel(ref rest: u128) -> Quota {
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let kind = peel(ref rest, s8);
        let param = peel(ref rest, P16.try_into().unwrap());
        let count = peel(ref rest, s8);
        Quota {
            kind: kind.try_into().unwrap(),
            param: param.try_into().unwrap(),
            count: count.try_into().unwrap(),
        }
    }
}

pub impl QuotaSetRecord of Record<QuotaSet> {
    const KIND: u8 = QUOTAS;

    fn pack(self: @QuotaSet) -> Span<felt252> {
        self.assert_valid();
        let [q0, q1, q2, q3, q4, q5] = self.quotas;
        let low = QuotaBitsTrait::bits(q0)
            + QuotaBitsTrait::bits(q1) * P32
            + QuotaBitsTrait::bits(q2) * P64
            + QuotaBitsTrait::bits(q3) * P96;
        let high = QuotaBitsTrait::bits(q4) + QuotaBitsTrait::bits(q5) * P32;
        array![join(low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> QuotaSet {
        let (mut low, mut high) = split(*parts[0]);
        let q0 = QuotaBitsTrait::peel(ref low);
        let q1 = QuotaBitsTrait::peel(ref low);
        let q2 = QuotaBitsTrait::peel(ref low);
        let q3 = QuotaBitsTrait::peel(ref low);
        let q4 = QuotaBitsTrait::peel(ref high);
        let q5 = QuotaBitsTrait::peel(ref high);
        QuotaSet { quotas: [q0, q1, q2, q3, q4, q5] }
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use super::{Quota, QuotaSet, QuotaSetRecord, QuotaSetTrait, kind};

    #[test]
    #[available_gas(l2_gas: 161574)] // ceil(1.05 × 153880 measured)
    fn test_quotas_bits_and_round_trip() {
        let exit = Quota { kind: kind::EXIT, param: 0xabcd, count: 0x12 };
        let last = Quota { kind: kind::SET_PIECE, param: 0x1234, count: 0xff };
        let set = QuotaSetTrait::new(
            [
                exit, Default::default(), Default::default(), Default::default(),
                Default::default(), last,
            ],
        );
        let parts = set.pack();
        let quota_bits = 1 + 0xabcd * 0x100 + 0x12 * 0x1000000;
        let last_bits: felt252 = 6 + 0x1234 * 0x100 + 0xff * 0x1000000;
        assert(
            *parts[0] == quota_bits
                + last_bits * 0x100000000000000000000000000000000 * 0x100000000
                + LIVE,
            'bits',
        );
        assert(QuotaSetRecord::unpack(parts) == set, 'round trip');
    }

    #[test]
    #[should_panic(expected: 'quotas: kind')]
    #[available_gas(l2_gas: 91476)] // ceil(1.05 × 87120 measured)
    fn test_quotas_kind_refused() {
        let wrong = Quota { kind: 7, param: 0, count: 1 };
        let set = QuotaSet {
            quotas: [
                wrong, Default::default(), Default::default(), Default::default(),
                Default::default(), Default::default(),
            ],
        };
        set.pack();
    }
}
