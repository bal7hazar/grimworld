//! `ZONE_CHUNK` (proposed, kind 26): one chunk of an authored zone, as ENG-08 proposes it for
//! ENG-09 (ENG-01 §3.5). Composite, keyed by the location and the chunk as `OUTLINE`
//! (`location × 256 + chunk`); two parts, so `bundle`'s bound ("at most 3 parts each") holds.
//!
//! - Part 0, **the walkable plane** (D-215 ruling 1): bit `15 row + column`, 1 = wall, the
//!   convention of `Terrain` and `SET_PIECE`; a tile outside the zone's mask is wall (R-20).
//!   Bits 225–249 are reserved planes' flags, 0 in format version 1; `LIVE` at 250.
//! - Part 1, **the features**, `SET_PIECE`'s part 1 extended in the free bits of its high limb:
//!   spawn points `i` of 2 (tile 0–7 · template 8–23) at `24 i`; objects at 48, 80 and 128,
//!   each in `Object`'s 32-bit layout (§3.2, state 0); the candidate tile of quota `i` of 6 at
//!   `160 + 8 i`, meaningful where the zone's `CANDIDATES` names this chunk for quota `i` (0
//!   elsewhere); the bridges this chunk holds 208–211 (`BRIDGE` records `0 … count − 1`); the
//!   gates anchored here, two `GATE` ids at 212 and 228 (0 none); 244–249 free. `LIVE` at 250.
//!
//! The spike's prototype: ENG-09 moves it to `grimworld_logic::models::zone_chunk`.

use grimworld_logic::models::chunk::{Object, ObjectTrait, object};
use grimworld_logic::models::set_piece::{SetPack, SetPackBitsTrait};
use grimworld_logic::packing::{P16, P24, P48, P80, join, peel, split};

/// The proposed kind (ENG-01 §3.5): the next after `COUNTER` (25).
pub const ZONE_CHUNK: u8 = 26;
/// Quotas a location holds (`QUOTAS`, 6 entries).
pub const QUOTAS: u8 = 6;
/// Gates a chunk can anchor.
pub const GATES: u8 = 2;
/// Bridges a chunk can hold (4 bits).
pub const MAX_BRIDGES: u8 = 15;
/// 2^97: the walls' part in the high limb is below it (bits 128–224).
const P97: u128 = 0x2000000000000000000000000;

pub mod errors {
    pub const WALLS: felt252 = 'zone chunk: walls above 224';
    pub const RESERVED: felt252 = 'zone chunk: reserved plane';
    pub const BRIDGES: felt252 = 'zone chunk: bridges above 15';
    pub const EMPTY: felt252 = 'zone chunk: empty with a value';
}

#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct ZoneChunk {
    /// The walkable plane, bit `15 row + column`, 1 = wall.
    pub walls: felt252,
    pub spawns: [SetPack; 2],
    pub objects: [Object; 3],
    /// The candidate tile of each quota, where `CANDIDATES` names this chunk (0 elsewhere).
    pub tiles: [u8; 6],
    pub bridges: u8,
    /// The `GATE` ids anchored in this chunk (0 none).
    pub gates: [u16; 2],
}

#[generate_trait]
pub impl ZoneChunkImpl of ZoneChunkTrait {
    /// The record's id: `location × 256 + chunk`, as `OUTLINE`.
    fn id(location: u16, chunk: u8) -> u32 {
        location.into() * 256 + chunk.into()
    }

    /// The candidate tile of quota `i`.
    fn tile(self: @ZoneChunk, i: u8) -> u8 {
        *self.tiles.span()[i.into()]
    }
}

/// The record's parts, and back (the layout of the module doc).
#[generate_trait]
pub impl ZoneChunkRecord of ZoneChunkRecordTrait {
    fn pack(self: @ZoneChunk) -> Span<felt252> {
        let walls: u256 = (*self.walls).into();
        assert(walls.high < P97, errors::WALLS);
        assert(*self.bridges <= MAX_BRIDGES, errors::BRIDGES);
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
        // shift is now 2^80 (bit 208)
        high += (*self.bridges).into() * shift;
        let [g0, g1] = *self.gates;
        high += g0.into() * shift * 0x10;
        high += g1.into() * shift * 0x100000;
        array![join(walls.low, walls.high), join(low, high)].span()
    }

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

/// An object kind an authored zone's chunk holds (`chunk.cairo`'s `object`): chest, node, terrain
/// trap, landmark, lever. A vein and a collector are a quota's (drawn among candidates); an exit
/// is a dungeon's; a placed trap is an actor's.
pub fn authored_object(kind: u8) -> bool {
    kind == object::CHEST
        || kind == object::NODE
        || kind == object::TRAP
        || kind == object::LANDMARK
        || kind == object::LEVER
}
