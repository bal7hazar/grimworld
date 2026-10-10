//! `QUOTAS`: its constructor, its checks and its record (layout: `models::index::QuotaSet`). A
//! location's quotas (ADR-0006 kind 2): what its chunks must hold in total, placed by sampling
//! without replacement at each reveal (`types::reveal`); an authored zone's (D-214) among the
//! author's candidates, drawn at entry (D-215 ruling 3, ENG-08). Id = the location's (D-145).

use crate::content::{QUOTAS, Record};
use crate::packing::{P16, P24, P32, P64, P8, P96, join, peel, split};
use crate::types::reveal::board::BoardTrait;
use super::pack::{Pack, PackTrait};
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
/// The most draws a zone's location quotas ask together at entry (R-30, D-220, D-221), each pass
/// drawing `min(count, members − count)`: 640, so that with the snapshot's eight task quotas the
/// worst plan measures 95,799,175 L2 gas (SPK-16, `test_pair_plan_bound_hosts`), under D-220's
/// 100,000,000.
pub const MAX_DRAWS: u16 = 640;

pub mod errors {
    pub const KIND: felt252 = 'quotas: kind';
    /// A quota of kind 0 (none) with a param or a count.
    pub const EMPTY: felt252 = 'quotas: empty with a value';
    /// A quota that places nothing (count 0).
    pub const COUNT: felt252 = 'quotas: count 0';
    /// R-12: a count above the zone's members.
    pub const ABOVE_MEMBERS: felt252 = 'zone: count above members';
    /// R-13: an authored zone's count above its candidates.
    pub const ABOVE_CANDIDATES: felt252 = 'zone: count above candidates';
    /// R-27: a Heart whose template is missing, or empty at its fewest or at its most.
    pub const HEART: felt252 = 'zone: heart template';
    /// R-29: an exit or a set piece in an authored zone.
    pub const KIND_AUTHORED: felt252 = 'zone: quota kind';
    /// R-30: more than `MAX_DRAWS` draws together.
    pub const DRAWS: felt252 = 'zone: quota draws';
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

    /// `Registry`'s content check (ENG-05, after CBT-05a): every kind known, a quota of kind 0
    /// empty (no param, no count), a quota a count of at least 1. That a param names an existing
    /// gate, template, collector, landmark or set piece is the content pipeline's (OPS-01).
    fn assert_legal(self: @QuotaSet) {
        self.assert_valid();
        for quota in self.quotas.span() {
            if *quota.kind == 0 {
                assert(*quota.param == 0 && *quota.count == 0, errors::EMPTY);
            } else {
                assert(*quota.count != 0, errors::COUNT);
            }
        }
    }
}

/// The content bounds of a zone's quotas (ENG-R1c's, built once by ENG-09 and shared: ENG-01
/// §3.5's R-12, R-13, R-27, R-29, R-30). `Registry` applies them to an authored zone at its
/// `QUOTAS`, chunk set, `CANDIDATES` and `LOCATION` writes; ENG-R1c applies them to generated
/// zones.
#[generate_trait]
pub impl QuotaBoundsAssert of QuotaBoundsAssertTrait {
    /// In order, quota by quota: R-29, an authored zone's kinds (no exit, no set piece, which a
    /// zone's author does not place); R-12, each count at most the zone's `members`; R-13, for an
    /// authored zone (`candidates`, the six quotas' chunk sets), at most its candidates; R-27, a
    /// Heart's template (`hearts[i]`, the `PACK` read, `None` when missing) at least 1 at its
    /// fewest and at its most; then R-30, the draws of every pass at most `MAX_DRAWS` together, a
    /// pass drawing among the members (generated) or the candidates (authored).
    fn assert_bounds(
        self: @QuotaSet, members: u8, candidates: Option<Span<felt252>>, hearts: Span<Option<Pack>>,
    ) {
        let mut draws: u16 = 0;
        let mut i: u32 = 0;
        for entry in self.quotas.span() {
            let what = *entry.kind;
            if what != 0 {
                let count = *entry.count;
                let mut left = members;
                if let Some(sets) = candidates {
                    assert(what != kind::EXIT && what != kind::SET_PIECE, errors::KIND_AUTHORED);
                    assert(count <= members, errors::ABOVE_MEMBERS);
                    left = BoardTrait::count(*sets[i]);
                    assert(count <= left, errors::ABOVE_CANDIDATES);
                } else {
                    assert(count <= members, errors::ABOVE_MEMBERS);
                }
                draws += Self::draws(count, left).into();
                if what == kind::HEART {
                    match *hearts[i] {
                        Some(pack) => {
                            let (low, high) = pack.bounds();
                            assert(low >= 1 && high >= 1, errors::HEART);
                        },
                        None => core::panic_with_felt252(errors::HEART),
                    }
                }
            }
            i += 1;
        }
        assert(draws <= MAX_DRAWS, errors::DRAWS);
    }

    /// The draws of one pass (D-220's complement draw, `PlacementTrait::subset`): none when the
    /// count takes every member, else the smaller of the subset and its complement.
    #[inline(always)]
    fn draws(count: u8, left: u8) -> u8 {
        if count >= left {
            0
        } else if count.into() * 2_u16 > left.into() {
            left - count
        } else {
            count
        }
    }

    /// R-27's reverse check, at a `PACK` write that a Heart quota of an authored zone names
    /// (`Registry` keeps a count of them per template, as `caste_skills`): the template still at
    /// least 1 at its fewest and at its most.
    #[inline(always)]
    fn assert_heart(pack: @Pack) {
        let (low, high) = pack.bounds();
        assert(low >= 1 && high >= 1, errors::HEART);
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
    use super::{Quota, QuotaSet, QuotaSetAssert, QuotaSetRecord, QuotaSetTrait, kind};

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

    fn set(first: Quota) -> QuotaSet {
        QuotaSet {
            quotas: [
                first, Default::default(), Default::default(), Default::default(),
                Default::default(), Default::default(),
            ],
        }
    }

    #[test]
    #[available_gas(l2_gas: 62496)] // ceil(1.05 × 59520 measured)
    fn test_quotas_legal() {
        set(Quota { kind: kind::EXIT, param: 5, count: 1 }).assert_legal();
        set(Default::default()).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'quotas: empty with a value')]
    #[available_gas(l2_gas: 23300)] // ceil(1.05 × 22190 measured)
    fn test_quotas_empty_with_a_count_refused() {
        set(Quota { kind: 0, param: 0, count: 2 }).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'quotas: count 0')]
    #[available_gas(l2_gas: 24423)] // ceil(1.05 × 23260 measured)
    fn test_quotas_count_zero_refused() {
        set(Quota { kind: kind::VEIN, param: 0, count: 0 }).assert_legal();
    }
}
