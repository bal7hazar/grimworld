//! `GATE`: its constructor, its checks and its record (layout: `models::index::Gate`).

use crate::helpers::packing::{P16, P32, P40, P48, P56, P64, P72, P8, P80, PackingTrait};
use crate::types::content::{GATE, Record};
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
    /// `Hub.enter`: the gate is in the registry (`Registry.bundle` returns its parts zero
    /// otherwise).
    fn assert_exists(exists: bool) {
        assert(exists, errors::NONE);
    }

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
        array![PackingTrait::join(low, 0)].span()
    }

    fn unpack(parts: Span<felt252>) -> Gate {
        let (low, _) = PackingTrait::split(*parts[0]);
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

/// The record's unit tests (ENG-03, ENG-01 §3.5; ENG-06): every field round-trips at its maximum,
/// sits at its documented bit, and a value wider than its field is refused; the gate an adventurer
/// can leave by, and the hub's checks of a gate.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::types::content::Record;
    use super::{Gate, GateAssert, GateRecord, GateTrait, kind, kind as gate_kind};

    /// The records these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        fn gate_max() -> Gate {
            GateTrait::new(0xFFFF, 0xFFFF, 224, 224, 224, 224, 0xFF, 0xFF, 0xFFFFFFFF)
        }
    }

    #[test]
    #[available_gas(l2_gas: 201443)] // ceil(1.05 × 191850 measured)
    fn test_gate_round_trip() {
        let top = Fixture::gate_max();
        assert(Record::<Gate>::unpack(top.pack()) == top, 'round trip');
        let gate = GateTrait::new(3, 4, 0, 0, 112, 112, gate_kind::FLOOR, 0, 0);
        assert(Record::<Gate>::unpack(gate.pack()) == gate, 'a floor gate');
        // source 0 · destination 16 · anchor chunk 32, tile 40 · entry chunk 48, tile 56 · kind
        // 64 ·
        // rank 72 · quest 80; nothing in the high limb.
        let one = GateTrait::new(1, 1, 1, 1, 1, 1, 1, 1, 1).pack();
        assert(*one[0] == 0x101010101010100010001 + LIVE, 'bits');
        assert(*top.pack()[0] == 0xFFFFFFFFFFFFE0E0E0E0FFFFFFFF + LIVE, 'maximum below bit 112');
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'gate: anchor chunk')]
    fn test_gate_anchor_chunk_refused() {
        let mut gate = Fixture::gate_max();
        gate.anchor_chunk = 225;
        gate.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'gate: anchor tile')]
    fn test_gate_anchor_tile_refused() {
        let mut gate = Fixture::gate_max();
        gate.anchor_tile = 225;
        gate.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'gate: entry chunk')]
    fn test_gate_entry_chunk_refused() {
        let mut gate = Fixture::gate_max();
        gate.entry_chunk = 225;
        gate.pack();
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'gate: entry tile')]
    fn test_gate_entry_tile_refused() {
        let mut gate = Fixture::gate_max();
        gate.entry_tile = 225;
        gate.pack();
    }

    // A gate is left from its source, on its anchor, when it is a hub gate or a link with no
    // requirement.
    #[test]
    #[available_gas(l2_gas: 56973)] // ceil(1.05 × 54260 measured)
    fn test_can_leave() {
        let gate = GateTrait::new(2, 1, 0, 105, 0, 0, kind::HUB, 0, 0);
        assert(gate.anchor() == (0, 7) && gate.entry() == (0, 0), 'anchor, entry');
        assert(gate.can_leave(2, 0, 7), 'on the anchor');
        assert(!gate.can_leave(3, 0, 7), 'another location');
        assert(!gate.can_leave(2, 1, 7) && !gate.can_leave(2, 0, 8), 'next to it');
        let link = GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 0, 0);
        assert(link.can_leave(2, 0, 7), 'a link');
        for refused in array![
            GateTrait::new(2, 3, 0, 105, 112, 112, kind::FLOOR, 0, 0),
            GateTrait::new(2, 3, 0, 105, 112, 112, kind::RIFT, 0, 0),
            GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 1, 0),
            GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 0, 4),
        ] {
            assert(!refused.can_leave(2, 0, 7), 'refused');
        }
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_enterable() {
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 3, 0).assert_enterable(1, 3);
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::LINK, 0, 0).assert_enterable(1, 0);
    }

    #[test]
    #[should_panic(expected: 'gate: not in this hub')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_enterable_elsewhere() {
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 0, 0).assert_enterable(4, 0);
    }

    #[test]
    #[should_panic(expected: 'gate: kind')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_enterable_floor() {
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::FLOOR, 0, 0).assert_enterable(1, 0);
    }

    #[test]
    #[should_panic(expected: 'gate: rank')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_enterable_rank() {
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 3, 0).assert_enterable(1, 2);
    }

    #[test]
    #[should_panic(expected: 'gate: quest')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_enterable_quest() {
        GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 0, 5).assert_enterable(1, 9);
    }
}
