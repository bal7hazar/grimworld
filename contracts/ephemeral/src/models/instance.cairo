//! The records of an instance as a whole, keyed by its slot (M-1), and the placement of an
//! adventurer. Layouts: docs/architecture/ENG-01-interfaces.md, *Instances storage*. Every record
//! carries `LIVE` (bit 250), so that a slot reused by the next instance is never 0.

use grimworld_logic::packing::{
    N16, N32, N8, P112, P120, P16, P24, P32, P40, P48, P64, P72, P8, P96, byte_at, join, low_field,
    peel, split, u16_at, u32_at,
};
use grimworld_logic::types::Refusal;
use grimworld_logic::types::reveal::Progress;

/// The reverts of `Instances`' lifecycle (ENG-06). A refusal of the game (a gate action that
/// cannot run) is not a revert: it emits `Refused` and changes nothing (design/02).
pub mod errors {
    /// `create`, `set_controller` called by anyone but the registered hub (ENG-01 §1.2).
    pub const NOT_HUB: felt252 = 'not hub';
    /// `create` for an adventurer already in an instance (design/02: at most one).
    pub const ALREADY_INSIDE: felt252 = 'already inside';
    /// `set_controller` for an adventurer in no instance.
    pub const NOT_INSIDE: felt252 = 'not inside';
    /// More task entries than a snapshot holds (D-131).
    pub const TOO_MANY_TASKS: felt252 = 'too many tasks';
    /// `create` through a gate or to a location the registry does not hold.
    pub const NO_GATE: felt252 = 'no gate';
    pub const NO_LOCATION: felt252 = 'no location';
    /// `create` to a hub: a town or an outpost is not an instance (design/01).
    pub const NO_MAP: felt252 = 'location without a map';
}

/// `Header.flags` bit 0: a sealed Red Rift, no travel back (design/17).
pub const SEALED: u8 = 1;

#[generate_trait]
pub impl PlacementImpl of PlacementTrait {
    /// Inside the instance `(slot, generation)`, as its first member (one in the MVP, M-3).
    fn new(slot: u32, generation: u32) -> Placement {
        Placement { slot, generation, member: 0, inside: 1 }
    }

    /// Whether it places the adventurer inside the instance `(slot, generation)`.
    fn is_in(self: @Placement, slot: u32, generation: u32) -> bool {
        *self.inside != 0 && *self.slot == slot && *self.generation == generation
    }
}

#[generate_trait]
pub impl PlacementAssert of PlacementAssertTrait {
    /// `create`: the adventurer is in no instance (design/02: at most one).
    #[inline(always)]
    fn assert_outside(self: @Placement) {
        assert(*self.inside == 0, errors::ALREADY_INSIDE);
    }

    /// `set_controller`: the adventurer is in an instance.
    #[inline(always)]
    fn assert_inside(self: @Placement) {
        assert(*self.inside != 0, errors::NOT_INSIDE);
    }
}

#[generate_trait]
pub impl HeaderImpl of HeaderTrait {
    /// The header of a new generation (ENG-01 §2.1): sequence 0, clock 0, open, one member, the
    /// tasks snapshotted, nothing revealed, the roster empty (its stale lanes masked by the count),
    /// the entrance and the gate.
    fn new(
        generation: u32,
        location: u16,
        tasks: u8,
        sealed: bool,
        entry_chunk: u8,
        entry_tile: u8,
        gate: u16,
    ) -> Header {
        Header {
            generation,
            sequence: 0,
            clock: 0,
            location,
            status: OPEN,
            members: 1,
            tasks,
            revealed_count: 0,
            roster_count: 0,
            flags: if sealed {
                SEALED
            } else {
                0
            },
            entry_chunk,
            entry_tile,
            gate,
        }
    }

    #[inline(always)]
    fn is_sealed(self: @Header) -> bool {
        *self.flags & SEALED != 0
    }
}

#[generate_trait]
pub impl HeaderAssert of HeaderAssertTrait {
    /// The checks of a gate action (`leave`, `travel_back`) once its caller controls the member,
    /// before any registry read or draw (design/02 *The chain's answer*; ADR-0002 rule 3), in this
    /// order: the instance is the slot's current generation and open (`Closed`); the adventurer is
    /// inside it and not down (`Absent`); the sequence is the instance's (`Sequence`). `None`: it
    /// may run. A refusal is not a revert.
    fn refusal(
        self: @Header,
        generation: u32,
        placement: @Placement,
        slot: u32,
        member_status: u8,
        sequence: u32,
    ) -> Option<Refusal> {
        if *self.generation != generation || *self.status != OPEN {
            return Option::Some(Refusal::Closed);
        }
        if !placement.is_in(slot, generation) || member_status != super::member::INSIDE {
            return Option::Some(Refusal::Absent);
        }
        if *self.sequence != sequence {
            return Option::Some(Refusal::Sequence);
        }
        Option::None
    }
}

#[generate_trait]
pub impl QuotasImpl of QuotasTrait {
    /// A new generation's quotas before its first reveal: the location's target number of chunks
    /// `N` (0 in a zone), nothing left to place. `create` writes them after the entry reveal
    /// (`from_progress`).
    fn new(target: u8) -> Quotas {
        Quotas { target, open_edges: 0, left: [0; 14] }
    }

    /// The reveal's progress (ENG-05, `types::reveal::Progress`) of an instance whose quotas are
    /// these, with its revealed set, its header's count and its entropy.
    fn progress(self: @Quotas, revealed: felt252, count: u8, entropy: felt252) -> Progress {
        Progress { revealed, count, open_edges: *self.open_edges, left: *self.left, entropy }
    }

    /// The quotas after a reveal's progress, `N` unchanged.
    fn from_progress(target: u8, progress: @Progress) -> Quotas {
        Quotas { target, open_edges: *progress.open_edges, left: *progress.left }
    }
}

/// Where an adventurer's instances live: its reusable slot, the generation of its last instance,
/// its member index there, and whether it is inside now. Keyed by adventurer id: it is the
/// adventurer's reference to an instance (design/02, D-02), not instance state.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Placement {
    /// bits 0-31
    pub slot: u32,
    /// bits 32-63
    pub generation: u32,
    /// bits 64-71
    pub member: u8,
    /// bits 72-79: 1 inside, 0 not
    pub inside: u8,
}

pub impl PlacementStorePacking of starknet::storage_access::StorePacking<Placement, felt252> {
    fn pack(value: Placement) -> felt252 {
        join(
            value.slot.into()
                + value.generation.into() * P32
                + value.member.into() * P64
                + value.inside.into() * P72,
            0,
        )
    }
    fn unpack(value: felt252) -> Placement {
        let (mut low, _) = split(value);
        Placement {
            slot: peel(ref low, N32).try_into().unwrap(),
            generation: peel(ref low, N32).try_into().unwrap(),
            member: peel(ref low, N8).try_into().unwrap(),
            inside: peel(ref low, N8).try_into().unwrap(),
        }
    }
}

/// Status of an instance (`Header.status`).
pub const OPEN: u8 = 0;
pub const RETURNED: u8 = 1;
pub const DEFEATED: u8 = 2;
pub const MOVED: u8 = 3;

/// The head of an instance: every other record of the slot is reached through it, so rewriting it
/// at entry makes the previous instance's records unreachable.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Header {
    /// bits 0-31: the instance id's generation; 0 means the slot never held an instance.
    pub generation: u32,
    /// bits 32-63: actions executed (design/02).
    pub sequence: u32,
    /// bits 64-95: the instance clock, in ticks, at most `MAX_CLOCK` (D-02, M-2).
    pub clock: u32,
    /// bits 96-111: the location (registry id).
    pub location: u16,
    /// bits 112-119: `OPEN`, `RETURNED`, `DEFEATED` or `MOVED`.
    pub status: u8,
    /// bits 120-127: members (adventurers) in the instance, 1 in the MVP (M-3).
    pub members: u8,
    /// bits 128-135: task entries snapshotted at entry (D-131), at most 16.
    pub tasks: u8,
    /// bits 136-143: chunks revealed.
    pub revealed_count: u8,
    /// bits 144-151: goblins in the roster (displaced from their spawn).
    pub roster_count: u8,
    /// bits 152-159: bit 0 sealed (Red Rift: no travel back, design/17).
    pub flags: u8,
    /// bits 160-167: the chunk of the entrance.
    pub entry_chunk: u8,
    /// bits 168-175: the tile of the entrance in that chunk.
    pub entry_tile: u8,
    /// bits 176-191: the gate the instance was entered by.
    pub gate: u16,
}

pub impl HeaderStorePacking of starknet::storage_access::StorePacking<Header, felt252> {
    fn pack(value: Header) -> felt252 {
        let low: u128 = value.generation.into()
            + value.sequence.into() * P32
            + value.clock.into() * P64
            + value.location.into() * P96
            + value.status.into() * P112
            + value.members.into() * P120;
        let high: u128 = value.tasks.into()
            + value.revealed_count.into() * P8
            + value.roster_count.into() * P16
            + value.flags.into() * P24
            + value.entry_chunk.into() * P32
            + value.entry_tile.into() * P40
            + value.gate.into() * P48;
        join(low, high)
    }
    fn unpack(value: felt252) -> Header {
        let (mut low, mut high) = split(value);
        Header {
            generation: peel(ref low, N32).try_into().unwrap(),
            sequence: peel(ref low, N32).try_into().unwrap(),
            clock: peel(ref low, N32).try_into().unwrap(),
            location: peel(ref low, N16).try_into().unwrap(),
            status: peel(ref low, N8).try_into().unwrap(),
            members: peel(ref low, N8).try_into().unwrap(),
            tasks: peel(ref high, N8).try_into().unwrap(),
            revealed_count: peel(ref high, N8).try_into().unwrap(),
            roster_count: peel(ref high, N8).try_into().unwrap(),
            flags: peel(ref high, N8).try_into().unwrap(),
            entry_chunk: peel(ref high, N8).try_into().unwrap(),
            entry_tile: peel(ref high, N8).try_into().unwrap(),
            gate: peel(ref high, N16).try_into().unwrap(),
        }
    }
}

/// The counters of generation that span chunks (ADR-0006, *Constraints without a plan*): a
/// dungeon's target size and open edges, and what each quota has left to place. Quotas are
/// numbered as the location's registry list, then the snapshotted tasks' quotas.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Quotas {
    /// bits 0-7: `N`, the chunks a dungeon floor reveals (6 to 12, by grade); 0 for a zone.
    pub target: u8,
    /// bits 8-15: open edges of a dungeon's frontier.
    pub open_edges: u8,
    /// bits 16-127: left to place of quota `i` at bits `16 + 8 i`.
    pub left: [u8; 14],
}

pub impl QuotasStorePacking of starknet::storage_access::StorePacking<Quotas, felt252> {
    fn pack(value: Quotas) -> felt252 {
        let mut low: u128 = value.target.into() + value.open_edges.into() * P8;
        let mut factor: u128 = P16;
        for left in value.left.span() {
            low += (*left).into() * factor;
            if factor != P120 {
                factor *= P8;
            }
        }
        join(low, 0)
    }
    fn unpack(value: felt252) -> Quotas {
        let (low, _) = split(value);
        let b8: NonZero<u128> = P8.try_into().unwrap();
        let (rest, target) = DivRem::div_rem(low, b8);
        let (mut rest, open_edges) = DivRem::div_rem(rest, b8);
        let mut left: Array<u8> = array![];
        for _ in 0..14_u8 {
            let (next, value) = DivRem::div_rem(rest, b8);
            left.append(value.try_into().unwrap());
            rest = next;
        }
        Quotas {
            target: target.try_into().unwrap(),
            open_edges: open_edges.try_into().unwrap(),
            left: [
                *left[0], *left[1], *left[2], *left[3], *left[4], *left[5], *left[6], *left[7],
                *left[8], *left[9], *left[10], *left[11], *left[12], *left[13],
            ],
        }
    }
}

/// Roster pages hold fifteen entity ids each; entry `e` is lane `e % 15` of page `e / 15`.
pub const ROSTER_LANES: u8 = 15;

/// **Masking, not rewriting** (fix loop 2, F-13): every read of a roster page, internal or in a
/// view, goes through this. Lanes of entries at or beyond `header.roster_count` are zeroed, so a
/// lane an earlier generation left (the count was reset at entry, the page was not rewritten) is
/// never read as an entry and never returned. No raw page leaves the contract unmasked.
#[generate_trait]
pub impl RosterImpl of RosterTrait {
    /// Page `index` of the roster, its lanes at or beyond `count` zeroed.
    fn mask(
        page: grimworld_logic::packing::Lanes16, index: u8, count: u8,
    ) -> grimworld_logic::packing::Lanes16 {
        let first: u16 = index.into() * ROSTER_LANES.into();
        let count: u16 = count.into();
        let mut out: Array<u16> = array![];
        let mut entry = first;
        for lane in page.lanes.span() {
            out.append(if entry < count {
                *lane
            } else {
                0
            });
            entry += 1;
        }
        grimworld_logic::packing::Lanes16 {
            lanes: [
                *out[0], *out[1], *out[2], *out[3], *out[4], *out[5], *out[6], *out[7], *out[8],
                *out[9], *out[10], *out[11], *out[12], *out[13], *out[14],
            ],
        }
    }
}

/// The instance's records are what docs/architecture/ENG-01-interfaces.md says: the bit offsets of
/// `Placement`, `Header` and `Quotas`, `LIVE` included, and the roster's masking (F-13). Here since
/// ENG-R1b (D-167).
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{LIVE, Lanes16};
    use starknet::storage_access::StorePacking;
    use super::{Header, Placement, Quotas, RosterTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 458157)] // ceil(1.05 × 436340 measured)
    fn test_placement_and_header_layout() {
        let placement = Placement {
            slot: 0xFFFFFFFF, generation: 0xFFFFFFFF, member: 7, inside: 1,
        };
        let word = StorePacking::<Placement, felt252>::pack(placement);
        assert(StorePacking::<Placement, felt252>::unpack(word) == placement, 'placement trip');
        let inside = Placement { inside: 1, ..Default::default() };
        assert(
            StorePacking::<Placement, felt252>::pack(inside) == 0x1000000000000000000 + LIVE,
            'inside at bit 72',
        );

        let header = Header {
            generation: 0xFFFFFFFF,
            sequence: 1,
            clock: 0xFFFFFFF,
            location: 0xFFFF,
            status: 3,
            members: 1,
            tasks: 16,
            revealed_count: 225,
            roster_count: 30,
            flags: 1,
            entry_chunk: 224,
            entry_tile: 224,
            gate: 0xFFFF,
        };
        let word = StorePacking::<Header, felt252>::pack(header);
        assert(StorePacking::<Header, felt252>::unpack(word) == header, 'header trip');
        let one = Header { sequence: 1, tasks: 1, gate: 1, ..Default::default() };
        let expected = 0x100000000 + TWO_128 + 0x1000000000000 * TWO_128 + LIVE;
        assert(
            StorePacking::<Header, felt252>::pack(one) == expected,
            'sequence 32 tasks 128 gate 176',
        );
        assert(StorePacking::<Header, felt252>::pack(Default::default()) == LIVE, 'never 0');

        let quotas = Quotas {
            target: 12, open_edges: 3, left: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0xFF],
        };
        let word = StorePacking::<Quotas, felt252>::pack(quotas);
        assert(StorePacking::<Quotas, felt252>::unpack(word) == quotas, 'quotas trip');
    }

    // Fix loop 2, F-13: an earlier generation filled page 0; the new one has one entry. Masked, the
    // page shows that entry and zeros elsewhere; page 1 shows zeros; with 16 entries page 1 keeps
    // its lane 0 only.
    #[test]
    #[available_gas(l2_gas: 336830)] // ceil(1.05 × 320790 measured)
    fn test_roster_masking() {
        let stale = Lanes16 {
            lanes: [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115],
        };
        let masked = RosterTrait::mask(stale, 0, 1);
        assert(
            masked == Lanes16 { lanes: [101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
            'one entry',
        );
        assert(RosterTrait::mask(stale, 1, 1) == Lanes16 { lanes: [0; 15] }, 'page 1 empty');
        assert(RosterTrait::mask(stale, 0, 0) == Lanes16 { lanes: [0; 15] }, 'count 0');
        assert(RosterTrait::mask(stale, 0, 60) == stale, 'full page kept');
        let page1 = RosterTrait::mask(stale, 1, 16);
        assert(
            page1 == Lanes16 { lanes: [101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }, 'entry 15',
        );
    }
}
