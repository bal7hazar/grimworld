//! `ZONE_CHUNK`: its id, its checks and its record (layout: `models::index::ZoneChunk`; ENG-01
//! §3.5, ENG-08's format, built by ENG-09). One chunk of an authored zone (D-214): its walkable
//! plane, copied into the instance's chunk at reveal (D-215 ruling 2), and its features: spawn
//! points (their level and count drawn at entry, ruling 4), objects, a candidate tile per quota
//! (ruling 3), its bridges' count and the gates anchored in it. The checks are the Registry's
//! (`RegistryAssert::assert_content`), one table with the converter's (`tools/map-format/
//! checks.json`).

use crate::content::{Record, ZONE_CHUNK};
use crate::packing::{P16, P24, P48, P80, join, peel, split};
use crate::types::reveal::board::{BOARD, BoardTrait, INTERIOR};
use super::chunk::{ObjectTrait, object};
use super::quotas::{QuotaSet, kind as quota};
use super::set_piece::SetPackBitsTrait;
pub use super::index::{Object, SetPack, ZoneChunk};

/// The quotas a chunk holds a candidate tile for (`QUOTAS`' 6).
pub const QUOTAS: u8 = 6;
/// Bridges a chunk can hold (4 bits).
pub const MAX_BRIDGES: u8 = 15;
/// A chunk's caps (E-3): objects and packs.
pub const MAX_OBJECTS: u8 = 3;
pub const MAX_PACKS: u8 = 2;
/// 2^97: a 225-bit plane's part in the high limb is below it (bits 128–224).
const P97: u128 = 0x2000000000000000000000000;

pub mod errors {
    pub const WALLS: felt252 = 'zone chunk: walls above 224';
    /// A reserved plane's flag set: format version 1 has none (ENG-01 §3.5).
    pub const RESERVED: felt252 = 'zone chunk: reserved plane';
    pub const BRIDGES: felt252 = 'zone chunk: bridges above 15';
    /// R-14: a placement on a wall, or outside the interior (the ring, rows and columns 0 and 14).
    pub const NOT_FLOOR: felt252 = 'zone chunk: tile not floor';
    /// R-14: an object of a kind an authored chunk does not hold, or not untouched.
    pub const OBJECT: felt252 = 'zone chunk: object';
    /// R-14: an empty entry with a value, or a candidate tile where `CANDIDATES` does not name
    /// the chunk.
    pub const EMPTY: felt252 = 'zone chunk: empty with a value';
    /// R-14: two placements on one tile.
    pub const TAKEN: felt252 = 'zone chunk: tile taken';
    /// R-15: more than E-3 allows once every candidate is counted.
    pub const CAPS: felt252 = 'zone chunk: over its caps';
    /// R-20: a tile outside its border chunk's mask that is not a wall.
    pub const MASK: felt252 = 'zone: mask disagrees';
    /// R-24: a chunk outside the zone's chunk set.
    pub const NOT_IN_SET: felt252 = 'zone: chunk not in the set';
    /// R-26: the entry tile not walkable.
    pub const ENTRY: felt252 = 'zone: entry not floor';
    /// R-18: a gate's anchor not walkable.
    pub const GATE_ANCHOR: felt252 = 'zone: gate anchor not floor';
    /// R-25: the anchor chunk does not name the gate.
    pub const GATE_INDEX: felt252 = 'zone: gate not indexed';
}

#[generate_trait]
pub impl ZoneChunkImpl of ZoneChunkTrait {
    /// The record's id: `location × 256 + chunk`, as `OUTLINE`.
    #[inline(always)]
    fn id(location: u16, chunk: u8) -> u32 {
        location.into() * 256 + chunk.into()
    }

    /// The candidate tile of quota `i`.
    #[inline(always)]
    fn tile(self: @ZoneChunk, i: u8) -> u8 {
        *self.tiles.span()[i.into()]
    }

    /// Whether `tile` is walkable: a tile of the chunk, not a wall.
    #[inline(always)]
    fn floor(self: @ZoneChunk, tile: u8) -> bool {
        tile < 225 && !BoardTrait::has(*self.walls, tile)
    }

    /// Whether the chunk names `gate` among the two it anchors.
    #[inline(always)]
    fn names(self: @ZoneChunk, gate: u16) -> bool {
        let [g0, g1] = *self.gates;
        gate != 0 && (g0 == gate || g1 == gate)
    }

    /// The tiles its authored content stands on (R-37): its spawn points, objects and candidate
    /// tiles (R-14 keeps every one in the interior, so a candidate tile 0 is none).
    fn content(self: @ZoneChunk) -> felt252 {
        let mut tiles: felt252 = 0;
        for spawn in self.spawns.span() {
            if *spawn.template != 0 {
                tiles = BoardTrait::or(tiles, BoardTrait::pow(*spawn.tile));
            }
        }
        for item in self.objects.span() {
            if *item.kind != 0 {
                tiles = BoardTrait::or(tiles, BoardTrait::pow(*item.tile));
            }
        }
        for tile in self.tiles.span() {
            if *tile != 0 {
                tiles = BoardTrait::or(tiles, BoardTrait::pow(*tile));
            }
        }
        tiles
    }
}

/// An object kind an authored chunk holds (`chunk::object`): chest, node, terrain trap, landmark,
/// lever. A vein and a collector are a quota's (drawn among candidates); an exit is a dungeon's; a
/// placed trap is an actor's.
#[inline(always)]
pub fn authored_object(kind: u8) -> bool {
    kind == object::CHEST
        || kind == object::NODE
        || kind == object::TRAP
        || kind == object::LANDMARK
        || kind == object::LEVER
}

#[generate_trait]
pub impl ZoneChunkAssert of ZoneChunkAssertTrait {
    /// The packer's bounds: the plane below bit 225, at most 15 bridges.
    #[inline(always)]
    fn assert_valid(self: @ZoneChunk) {
        let walls: u256 = (*self.walls).into();
        assert(walls.high < P97, errors::WALLS);
        assert(*self.bridges <= MAX_BRIDGES, errors::BRIDGES);
    }

    /// R-14 and R-15, at a `ZONE_CHUNK` write (it reads `CANDIDATES` and `QUOTAS`; a `CANDIDATES`
    /// write re-runs it on each chunk whose candidacy changed, a `QUOTAS` write that changes a
    /// kind on its candidates' chunks): its spawn points, objects and candidate tiles on walkable
    /// tiles of the interior (a pack's goblins are laid within 2 of its tile, `Placement::near`'s
    /// precondition), none two on one tile; an object of a kind an authored chunk holds,
    /// untouched; an empty entry all zeros, and a candidate tile 0 where `candidates` (the six
    /// quotas' chunk sets) does not name the chunk; within E-3 with every candidate counted (an
    /// object quota's against 3 objects, a Heart's against 2 packs), so that any draw at entry
    /// fits. D-134's corners are not read (D-215 ruling 5: lifted for authored chunks, R-16).
    fn assert_legal(self: @ZoneChunk, chunk: u8, candidates: Span<felt252>, quotas: @QuotaSet) {
        let walls = *self.walls;
        let mut taken: felt252 = 0;
        let mut packs: u8 = 0;
        let mut objects: u8 = 0;
        for spawn in self.spawns.span() {
            if *spawn.template == 0 {
                assert(*spawn.tile == 0, errors::EMPTY);
            } else {
                Self::take(walls, ref taken, *spawn.tile);
                packs += 1;
            }
        }
        for item in self.objects.span() {
            if *item.kind == 0 {
                assert(*item.tile == 0 && *item.state == 0 && *item.param == 0, errors::EMPTY);
            } else {
                assert(authored_object(*item.kind) && *item.state == 0, errors::OBJECT);
                Self::take(walls, ref taken, *item.tile);
                objects += 1;
            }
        }
        let mut i: u8 = 0;
        while i != QUOTAS {
            let tile = self.tile(i);
            if BoardTrait::has(*candidates[i.into()], chunk) {
                Self::take(walls, ref taken, tile);
                if *quotas.quotas.span()[i.into()].kind == quota::HEART {
                    packs += 1;
                } else {
                    objects += 1;
                }
            } else {
                assert(tile == 0, errors::EMPTY);
            }
            i += 1;
        }
        assert(packs <= MAX_PACKS && objects <= MAX_OBJECTS, errors::CAPS);
    }

    /// `tile` walkable, in the interior and not yet taken; then taken.
    #[inline(always)]
    fn take(walls: felt252, ref taken: felt252, tile: u8) {
        assert(
            tile < 225 && BoardTrait::has(INTERIOR, tile) && !BoardTrait::has(walls, tile),
            errors::NOT_FLOOR,
        );
        assert(!BoardTrait::has(taken, tile), errors::TAKEN);
        taken += BoardTrait::pow(tile);
    }

    /// R-24 and R-20, at a `ZONE_CHUNK` write (it reads the chunk set and its tile mask; the mask's
    /// `OUTLINE` write reads the `ZONE_CHUNK` the other way, a chunk set's rewrite every chunk it
    /// drops): the chunk is in the set, and every tile outside its mask is a wall (`mask` 0: a
    /// whole chunk).
    fn assert_outline(self: @ZoneChunk, chunk: u8, chunk_set: felt252, mask: felt252) {
        assert(BoardTrait::has(chunk_set, chunk), errors::NOT_IN_SET);
        Self::assert_mask(*self.walls, mask);
    }

    /// R-20 alone: every tile outside `mask` is a wall (`mask` 0: a whole chunk).
    fn assert_mask(walls: felt252, mask: felt252) {
        if mask != 0 {
            let outside = BoardTrait::minus(BOARD, mask);
            assert(BoardTrait::minus(outside, walls) == 0, errors::MASK);
        }
    }

    /// R-26, at `LOCATION`'s write with the marker (it reads the entry chunk's `ZONE_CHUNK`) and at
    /// that chunk's write (it reads `LOCATION`): the entry tile walkable.
    #[inline(always)]
    fn assert_entry(self: @ZoneChunk, tile: u8) {
        assert(self.floor(tile), errors::ENTRY);
    }

    /// R-18 and R-25, at a `GATE` write whose source is an authored zone (it reads the anchor
    /// chunk's `ZONE_CHUNK`; that chunk's rewrite re-runs both for the gates it names, and refuses
    /// to drop one that anchors there): the anchor walkable, and the chunk names the gate among
    /// the two it anchors, which is the registry's index of a zone's gates.
    fn assert_gate(self: @ZoneChunk, gate: u16, tile: u8) {
        assert(self.floor(tile), errors::GATE_ANCHOR);
        assert(self.names(gate), errors::GATE_INDEX);
    }
}

pub impl ZoneChunkRecord of Record<ZoneChunk> {
    const KIND: u8 = ZONE_CHUNK;

    fn pack(self: @ZoneChunk) -> Span<felt252> {
        self.assert_valid();
        let walls: u256 = (*self.walls).into();
        let [p0, p1] = self.spawns;
        let [o0, o1, o2] = self.objects;
        let low = SetPackBitsTrait::bits(p0)
            + SetPackBitsTrait::bits(p1) * P24
            + o0.bits() * P48
            + o1.bits() * P80;
        let mut high: u128 = o2.bits();
        let mut shift: u128 = 0x100000000; // bit 160 − 128
        for tile in self.tiles.span() {
            high += (*tile).into() * shift;
            shift *= 0x100;
        }
        // `shift` is 2^80 here: bit 208
        high += (*self.bridges).into() * shift;
        let [g0, g1] = *self.gates;
        high += g0.into() * shift * 0x10;
        high += g1.into() * shift * 0x100000;
        array![join(walls.low, walls.high), join(low, high)].span()
    }

    /// Refuses a reserved plane's flag (a reader of format version 1).
    fn unpack(parts: Span<felt252>) -> ZoneChunk {
        let (low, high) = split(*parts[0]);
        let (reserved, walls_high) = DivRem::div_rem(high, P97.try_into().unwrap());
        assert(reserved == 0, errors::RESERVED);
        let walls: felt252 = low.into() + walls_high.into() * 0x100000000000000000000000000000000;
        let (mut low, mut high) = split(*parts[1]);
        let p0 = SetPackBitsTrait::peel(ref low);
        let p1 = SetPackBitsTrait::peel(ref low);
        let s32: NonZero<u128> = 0x100000000;
        let s8: NonZero<u128> = 0x100;
        let o0 = ObjectTrait::from_bits(peel(ref low, s32));
        let o1 = ObjectTrait::from_bits(peel(ref low, s32));
        let o2 = ObjectTrait::from_bits(peel(ref high, s32));
        let t0 = peel(ref high, s8);
        let t1 = peel(ref high, s8);
        let t2 = peel(ref high, s8);
        let t3 = peel(ref high, s8);
        let t4 = peel(ref high, s8);
        let t5 = peel(ref high, s8);
        let bridges = peel(ref high, 0x10);
        let g0 = peel(ref high, P16.try_into().unwrap());
        let g1 = peel(ref high, P16.try_into().unwrap());
        ZoneChunk {
            walls,
            spawns: [p0, p1],
            objects: [o0, o1, o2],
            tiles: [
                t0.try_into().unwrap(), t1.try_into().unwrap(), t2.try_into().unwrap(),
                t3.try_into().unwrap(), t4.try_into().unwrap(), t5.try_into().unwrap(),
            ],
            bridges: bridges.try_into().unwrap(),
            gates: [g0.try_into().unwrap(), g1.try_into().unwrap()],
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::models::chunk::object;
    use crate::models::quotas::{Quota, QuotaSet, kind as quota};
    use crate::packing::LIVE;
    use crate::types::reveal::board::BoardTrait;
    use super::{Object, SetPack, ZoneChunk, ZoneChunkAssert, ZoneChunkRecord, ZoneChunkTrait};

    fn sample() -> ZoneChunk {
        ZoneChunk {
            walls: 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffff - BoardTrait::pow(16)
                - BoardTrait::pow(17)
                - BoardTrait::pow(18)
                - BoardTrait::pow(19)
                - BoardTrait::pow(112),
            spawns: [SetPack { tile: 16, template: 0xabcd }, Default::default()],
            objects: [
                Object { tile: 17, kind: object::CHEST, state: 0, param: 3 }, Default::default(),
                Object { tile: 18, kind: object::LEVER, state: 0, param: 0x1234 },
            ],
            tiles: [0, 0, 19, 0, 0, 112],
            bridges: 15,
            gates: [0xffff, 7],
        }
    }

    fn quotas() -> QuotaSet {
        QuotaSet {
            quotas: [
                Default::default(), Default::default(),
                Quota { kind: quota::HEART, param: 1, count: 1 }, Default::default(),
                Default::default(), Quota { kind: quota::VEIN, param: 0, count: 1 },
            ],
        }
    }

    #[test]
    #[available_gas(l2_gas: 334656)] // ceil(1.05 × 318720 measured)
    fn test_zone_chunk_bits_and_round_trip() {
        let record = sample();
        let parts = record.pack();
        assert(*parts[0] == record.walls + LIVE, 'plane');
        let wide: u256 = (*parts[1] - LIVE).into();
        assert(wide.low % 0x1000000 == 16 + 0xabcd * 0x100, 'spawn 0');
        assert((wide.low / 0x1000000000000) % 0x100000000 == 17 + 0x100 + 3 * 0x10000, 'object 0');
        assert(wide.high % 0x100000000 == 18 + 0x700 + 0x1234 * 0x10000, 'object 2');
        assert((wide.high / 0x100000000) % 0x1000000000000 == 112 * 0x10000000000 + 19 * 0x10000, 'tiles');
        assert((wide.high / 0x100000000000000000000) % 0x10 == 15, 'bridges');
        assert((wide.high / 0x1000000000000000000000) % 0x10000 == 0xffff, 'gate 0');
        assert((wide.high / 0x10000000000000000000000000) % 0x10000 == 7, 'gate 1');
        assert(ZoneChunkRecord::unpack(parts) == record, 'round trip');
    }

    #[test]
    #[available_gas(l2_gas: 279353)] // ceil(1.05 × 266050 measured)
    #[should_panic(expected: 'zone chunk: reserved plane')]
    fn test_zone_chunk_reserved_refused() {
        let parts = sample().pack();
        ZoneChunkRecord::unpack(array![*parts[0] + BoardTrait::pow(225), *parts[1]].span());
    }

    #[test]
    #[available_gas(l2_gas: 134547)] // ceil(1.05 × 128140 measured)
    #[should_panic(expected: 'zone chunk: walls above 224')]
    fn test_zone_chunk_walls_refused() {
        ZoneChunk { walls: BoardTrait::pow(225), ..sample() }.pack();
    }

    #[test]
    #[available_gas(l2_gas: 681559)] // ceil(1.05 × 649103 measured)
    fn test_zone_chunk_legal_and_content() {
        let record = sample();
        let candidates = array![0, 0, BoardTrait::pow(4), 0, 0, BoardTrait::pow(4)].span();
        record.assert_legal(4, candidates, @quotas());
        let content = BoardTrait::pow(16)
            + BoardTrait::pow(17)
            + BoardTrait::pow(18)
            + BoardTrait::pow(19)
            + BoardTrait::pow(112);
        assert(record.content() == content, 'content');
        assert(record.names(7) && record.names(0xffff) && !record.names(0), 'names');
    }

    #[test]
    #[available_gas(l2_gas: 106925)] // ceil(1.05 × 101833 measured)
    #[should_panic(expected: 'zone chunk: tile not floor')]
    fn test_zone_chunk_ring_refused() {
        // Tile 14 is on the ring (column 14): floor, but not of the interior
        let record = ZoneChunk {
            walls: sample().walls - BoardTrait::pow(14),
            spawns: [SetPack { tile: 14, template: 1 }, Default::default()],
            ..sample()
        };
        record.assert_legal(4, array![0, 0, BoardTrait::pow(4), 0, 0, BoardTrait::pow(4)].span(), @quotas());
    }

    #[test]
    #[available_gas(l2_gas: 525802)] // ceil(1.05 × 500763 measured)
    #[should_panic(expected: 'zone chunk: over its caps')]
    fn test_zone_chunk_caps_refused() {
        let record = ZoneChunk {
            objects: [
                Object { tile: 17, kind: object::CHEST, state: 0, param: 3 },
                Object { tile: 16, kind: object::NODE, state: 0, param: 0 },
                Object { tile: 18, kind: object::LEVER, state: 0, param: 0x1234 },
            ],
            spawns: [Default::default(), Default::default()],
            ..sample()
        };
        record.assert_legal(4, array![0, 0, BoardTrait::pow(4), 0, 0, BoardTrait::pow(4)].span(), @quotas());
    }
}
