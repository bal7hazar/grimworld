//! `GATE`: its constructor, its checks and its record (layout: `models::index::Gate`).

use crate::content::{GATE, Record};
use crate::packing::{P16, P32, P40, P48, P56, P64, P72, P8, P80, join, split};
use crate::types::reveal::board::BoardTrait;
pub use super::index::Gate;
use super::location::{LocationAssert, LocationTrait};
use super::outline::OutlineTrait;

/// Gate kinds (ENG-01 §3.5).
pub mod kind {
    pub const HUB: u8 = 1;
    pub const LINK: u8 = 2;
    pub const FLOOR: u8 = 3;
    pub const RIFT: u8 = 4;
}

pub mod errors {
    pub const ANCHOR_CHUNK: felt252 = 'gate: anchor chunk';
    pub const ANCHOR_TILE: felt252 = 'gate: anchor tile';
    pub const ENTRY_CHUNK: felt252 = 'gate: entry chunk';
    pub const ENTRY_TILE: felt252 = 'gate: entry tile';
    /// R-41: an entry chunk outside its destination's `width × height` rectangle.
    pub const ENTRY_OUTSIDE: felt252 = 'gate: entry outside rectangle';
    // `Hub.enter`'s refusals of a gate (design/01 *Connectivity*, ENG-06).
    /// No `GATE` record under that id.
    pub const NONE: felt252 = 'gate: none';
    /// The gate does not stand in the hub the adventurer is in.
    pub const NOT_HERE: felt252 = 'gate: not in this hub';
    /// A floor gate (from a dungeon floor only) or a Rift gate (`enter_rift`).
    pub const KIND: felt252 = 'gate: kind';
    /// The adventurer's guild rank is below the gate's.
    pub const RANK: felt252 = 'gate: rank';
    /// The gate requires a quest: quiver's quests are not embedded yet (E-14).
    pub const QUEST: felt252 = 'gate: quest';
}

#[generate_trait]
pub impl GateImpl of GateTrait {
    fn new(
        source: u16,
        destination: u16,
        anchor_chunk: u8,
        anchor_tile: u8,
        entry_chunk: u8,
        entry_tile: u8,
        kind: u8,
        rank: u8,
        quest: u32,
    ) -> Gate {
        Gate {
            source,
            destination,
            anchor_chunk,
            anchor_tile,
            entry_chunk,
            entry_tile,
            kind,
            rank,
            quest,
        }
    }

    /// Its anchor as a global tile `(x, y)` of its source location.
    #[inline(always)]
    fn anchor(self: @Gate) -> (u8, u8) {
        LocationTrait::position(*self.anchor_chunk, *self.anchor_tile)
    }

    /// Where it leads, as a global tile `(x, y)` of its destination.
    #[inline(always)]
    fn entry(self: @Gate) -> (u8, u8) {
        LocationTrait::position(*self.entry_chunk, *self.entry_tile)
    }

    /// Whether an adventurer standing on `(x, y)` in `location` can leave through it (design/02
    /// *Ending an expedition*: "walk into a hub gate"; ENG-06): it stands in that location, the
    /// adventurer is on its anchor, and it is a hub gate or a link. A floor gate is refused (a
    /// dungeon's exit is a quota object, placed by ENG-05's generation, ADR-0006), a Rift gate is
    /// `enter_rift`'s lot's. A gate that requires a rank or a quest is refused too: the snapshot
    /// holds no guild rank, and quiver's quests are not embedded (E-14).
    fn can_leave(self: @Gate, location: u16, x: u8, y: u8) -> bool {
        *self.source == location
            && (*self.kind == kind::HUB || *self.kind == kind::LINK)
            && *self.rank == 0
            && *self.quest == 0
            && self.anchor() == (x, y)
    }
}

#[generate_trait]
pub impl GateAssert of GateAssertTrait {
    /// `Hub.enter`'s checks of a gate (design/01 *Connectivity*): it stands in the adventurer's
    /// hub, it is a hub gate or a link, and the adventurer meets its requirements. A quest
    /// requirement is refused whatever the adventurer holds until quiver's quests are embedded
    /// (E-14).
    fn assert_enterable(self: @Gate, hub: u16, rank: u8) {
        assert(*self.source == hub, errors::NOT_HERE);
        assert(*self.kind == kind::HUB || *self.kind == kind::LINK, errors::KIND);
        assert(rank >= *self.rank, errors::RANK);
        assert(*self.quest == 0, errors::QUEST);
    }

    /// The anchor and the entry are chunks of their locations and tiles of those chunks.
    #[inline(always)]
    fn assert_valid(self: @Gate) {
        LocationAssert::assert_index(*self.anchor_chunk, errors::ANCHOR_CHUNK);
        LocationAssert::assert_index(*self.anchor_tile, errors::ANCHOR_TILE);
        LocationAssert::assert_index(*self.entry_chunk, errors::ENTRY_CHUNK);
        LocationAssert::assert_index(*self.entry_tile, errors::ENTRY_TILE);
    }

    /// R-41 (ENG-R1c's bound 6, review t-0099 note 5), at a `GATE` write whose destination has a
    /// map: its entry chunk within the destination's `width × height` rectangle, else a dungeon
    /// floor's outline grows from outside it (`OutlineTrait::draw` checks only the far sides) and
    /// its frontier can come out empty (a draw of 0, D-140).
    #[inline(always)]
    fn assert_entry(self: @Gate, width: u8, height: u8) {
        Self::assert_entries(BoardTrait::pow(*self.entry_chunk), width, height);
    }

    /// R-41 for every gate at once: `entries`, the entry chunks of the gates that lead to a
    /// location, within its rectangle (a `LOCATION` write's reverse check, `Registry`'s
    /// `gate_entries`).
    fn assert_entries(entries: felt252, width: u8, height: u8) {
        let inside = OutlineTrait::rectangle(width, height);
        assert(BoardTrait::minus(entries, inside) == 0, errors::ENTRY_OUTSIDE);
    }
}

pub impl GateRecord of Record<Gate> {
    const KIND: u8 = GATE;

    fn pack(self: @Gate) -> Span<felt252> {
        self.assert_valid();
        let low: u128 = (*self.source).into()
            + (*self.destination).into() * P16
            + (*self.anchor_chunk).into() * P32
            + (*self.anchor_tile).into() * P40
            + (*self.entry_chunk).into() * P48
            + (*self.entry_tile).into() * P56
            + (*self.kind).into() * P64
            + (*self.rank).into() * P72
            + (*self.quest).into() * P80;
        array![join(low, 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Gate {
        let (low, _) = split(*parts[0]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (low, source) = DivRem::div_rem(low, s16);
        let (low, destination) = DivRem::div_rem(low, s16);
        let (low, anchor_chunk) = DivRem::div_rem(low, s8);
        let (low, anchor_tile) = DivRem::div_rem(low, s8);
        let (low, entry_chunk) = DivRem::div_rem(low, s8);
        let (low, entry_tile) = DivRem::div_rem(low, s8);
        let (low, kind) = DivRem::div_rem(low, s8);
        let (quest, rank) = DivRem::div_rem(low, s8);
        Gate {
            source: source.try_into().unwrap(),
            destination: destination.try_into().unwrap(),
            anchor_chunk: anchor_chunk.try_into().unwrap(),
            anchor_tile: anchor_tile.try_into().unwrap(),
            entry_chunk: entry_chunk.try_into().unwrap(),
            entry_tile: entry_tile.try_into().unwrap(),
            kind: kind.try_into().unwrap(),
            rank: rank.try_into().unwrap(),
            quest: quest.try_into().unwrap(),
        }
    }
}
