//! `CANDIDATES`: its id, its checks and its record (layout: `models::index::Candidates`; ENG-01
//! §3.5, built by ENG-09). Which chunks of an authored zone are candidates of each quota (D-215
//! ruling 3), so that the draw at entry reads two records, not every chunk; the tile of each
//! candidate is in its `ZONE_CHUNK`.

use crate::content::{CANDIDATES, Record};
use crate::packing::LIVE;
use crate::types::reveal::board::BoardTrait;
pub use super::index::Candidates;

/// 2^225: a chunk set is below it.
const P225: u256 = 0x2000000000000000000000000000000000000000000000000000000000;

pub mod errors {
    pub const ABOVE_224: felt252 = 'candidates: above bit 224';
    /// R-31: a candidate chunk outside the zone's chunk set.
    pub const OUTSIDE: felt252 = 'candidates: outside the set';
}

#[generate_trait]
pub impl CandidatesImpl of CandidatesTrait {
    /// The record's id: `location × 2 + k`, `k` 0 for quotas 0–2, 1 for 3–5.
    #[inline(always)]
    fn id(location: u16, k: u8) -> u32 {
        location.into() * 2 + k.into()
    }
}

#[generate_trait]
pub impl CandidatesAssert of CandidatesAssertTrait {
    /// R-31, at a `CANDIDATES` write (it reads the chunk set; a chunk set's rewrite reads both
    /// `CANDIDATES` records the other way): every candidate chunk in the zone.
    fn assert_within(sets: Span<felt252>, chunk_set: felt252) {
        for set in sets {
            assert(BoardTrait::minus(*set, chunk_set) == 0, errors::OUTSIDE);
        }
    }
}

pub impl CandidatesRecord of Record<Candidates> {
    const KIND: u8 = CANDIDATES;

    /// Three chunk sets, each below 2^225, `LIVE` in every part.
    fn pack(self: @Candidates) -> Span<felt252> {
        let mut out: Array<felt252> = array![];
        for set in self.sets.span() {
            let wide: u256 = (*set).into();
            assert(wide < P225, errors::ABOVE_224);
            out.append(*set + LIVE);
        }
        out.span()
    }

    /// A part without `LIVE` (a record never written) reads as no candidate.
    fn unpack(parts: Span<felt252>) -> Candidates {
        Candidates { sets: [set(*parts[0]), set(*parts[1]), set(*parts[2])] }
    }
}

/// A part's chunk set: the part without `LIVE`, 0 for a part never written.
#[inline(always)]
fn set(part: felt252) -> felt252 {
    if part == 0 {
        0
    } else {
        part - LIVE
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use super::{Candidates, CandidatesAssert, CandidatesRecord, CandidatesTrait};

    #[test]
    fn test_candidates_round_trip() {
        let record = Candidates { sets: [3, 0, 0x1000000000000000000000000000000000000000000000000000000000] };
        let parts = record.pack();
        assert(*parts[1] == LIVE, 'empty part live');
        assert(CandidatesRecord::unpack(parts) == record, 'round trip');
        assert(CandidatesRecord::unpack(array![0, 0, 0].span()).sets == [0, 0, 0], 'never written');
        assert(CandidatesTrait::id(7, 1) == 15, 'id');
    }

    #[test]
    #[should_panic(expected: 'candidates: outside the set')]
    fn test_candidates_outside_refused() {
        CandidatesAssert::assert_within(array![1, 6].span(), 3);
    }
}
