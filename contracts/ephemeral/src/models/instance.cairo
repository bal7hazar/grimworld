//! The records of an instance as a whole, keyed by its slot (M-1), and the placement of an
//! adventurer. Layouts: docs/architecture/ENG-01-interfaces.md, *Instances storage*. Every record
//! carries `LIVE` (bit 250), so that a slot reused by the next instance is never 0.

use grimworld_logic::packing::{
    P112, P120, P16, P24, P32, P40, P48, P64, P72, P8, P96, byte_at, join, low_field, split, u16_at,
    u32_at,
};

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
        let (low, _) = split(value);
        Placement {
            slot: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            generation: u32_at(low, P32),
            member: byte_at(low, P64),
            inside: byte_at(low, P72),
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
        let (low, high) = split(value);
        Header {
            generation: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            sequence: u32_at(low, P32),
            clock: u32_at(low, P64),
            location: u16_at(low, P96),
            status: byte_at(low, P112),
            members: byte_at(low, P120),
            tasks: low_field(high, P8.try_into().unwrap()).try_into().unwrap(),
            revealed_count: byte_at(high, P8),
            roster_count: byte_at(high, P16),
            flags: byte_at(high, P24),
            entry_chunk: byte_at(high, P32),
            entry_tile: byte_at(high, P40),
            gate: u16_at(high, P48),
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
pub fn mask_roster_page(
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
