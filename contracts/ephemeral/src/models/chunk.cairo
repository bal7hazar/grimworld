//! A revealed chunk: two felts under `(slot, chunk)`, both written at its reveal (ADR-0006,
//! D-136). Occupancy is not stored: it is the tiles of the goblins and adventurers in the window,
//! derived at each tick (ENG-01, *Chunks*). Layouts: docs/architecture/ENG-01-interfaces.md.

use grimworld_logic::packing::{
    LIVE, P16, P24, P32, P36, P64, P8, P96, TWO_POW_128, byte_at, field, join, low_field, split,
    u16_at,
};

/// 2^97: the part of the walls above bit 128, in the high limb.
const P97: u128 = 0x2000000000000000000000000;
/// 2^225, where the edges start.
const P225: felt252 = 0x200000000000000000000000000000000000000000000000000000000;

/// Walls of the 225 tiles (bit `15 row + column`, 1 = wall) and, for a dungeon chunk, its four
/// edges (bits 225-228: 1 open, 0 border; West, East, South, North), decided at its reveal.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Terrain {
    pub walls: felt252,
    pub edges: u8,
}

pub impl TerrainStorePacking of starknet::storage_access::StorePacking<Terrain, felt252> {
    fn pack(value: Terrain) -> felt252 {
        value.walls + value.edges.into() * P225 + LIVE
    }
    fn unpack(value: felt252) -> Terrain {
        let (low, high) = split(value);
        let (edges, walls_high) = DivRem::div_rem(high, P97.try_into().unwrap());
        Terrain {
            walls: low.into() + walls_high.into() * TWO_POW_128,
            edges: low_field(edges, P8.try_into().unwrap()).try_into().unwrap(),
        }
    }
}

/// A pack placed at reveal (design/05, design/18): its goblins are derived from it until they
/// leave their first state (the chunk's `touched` bits).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct PackPlacement {
    /// bits 0-7: the pack's tile in the chunk; 0 with `count` 0 is no pack
    pub tile: u8,
    /// bits 8-23: the pack template (registry)
    pub template: u16,
    /// bits 24-31: its level
    pub level: u8,
    /// bits 32-35: goblins in it, 0 to 5
    pub count: u8,
    /// bits 36-60: each goblin's tile as one of the 19 tiles within 2 of the pack's, 5 bits each
    pub offsets: u32,
}

/// An object placed at reveal (design/18). Kinds: 0 none, 1 chest, 2 vein, 3 gathering node,
/// 4 trap, 5 collector, 6 landmark, 7 lever or brazier.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Object {
    /// bits 0-7
    pub tile: u8,
    /// bits 8-11
    pub kind: u8,
    /// bits 12-15: 0 untouched; 1 used (opened, mined, gathered, revealed, activated)
    pub state: u8,
    /// bits 16-31: its registry id (collector, landmark) or level (chest)
    pub param: u16,
}

/// Packs at bits 0 and 64 (low limb), objects at bits 128, 160, 192, `touched` at bits 224-239.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Features {
    pub packs: [PackPlacement; 2],
    pub objects: [Object; 3],
    /// Bit `k`: goblin `k` of this chunk has a record (it left its first state).
    pub touched: u16,
}

fn pack_pack(p: PackPlacement) -> u128 {
    p.tile.into()
        + p.template.into() * P8
        + p.level.into() * P24
        + p.count.into() * P32
        + p.offsets.into() * P36
}

fn unpack_pack(bits: u128) -> PackPlacement {
    PackPlacement {
        tile: low_field(bits, P8.try_into().unwrap()).try_into().unwrap(),
        template: u16_at(bits, P8),
        level: byte_at(bits, P24),
        count: field(bits, P32, 0x10).try_into().unwrap(),
        offsets: field(bits, P36, 0x2000000).try_into().unwrap(),
    }
}

fn pack_object(o: Object) -> u128 {
    o.tile.into() + o.kind.into() * P8 + o.state.into() * 0x1000 + o.param.into() * P16
}

fn unpack_object(bits: u128) -> Object {
    Object {
        tile: low_field(bits, P8.try_into().unwrap()).try_into().unwrap(),
        kind: field(bits, P8, 0x10).try_into().unwrap(),
        state: field(bits, 0x1000, 0x10).try_into().unwrap(),
        param: u16_at(bits, P16),
    }
}

pub impl FeaturesStorePacking of starknet::storage_access::StorePacking<Features, felt252> {
    fn pack(value: Features) -> felt252 {
        let [p0, p1] = value.packs;
        let [o0, o1, o2] = value.objects;
        join(
            pack_pack(p0) + pack_pack(p1) * P64,
            pack_object(o0)
                + pack_object(o1) * P32
                + pack_object(o2) * P64
                + value.touched.into() * P96,
        )
    }
    fn unpack(value: felt252) -> Features {
        let (low, high) = split(value);
        let s32: NonZero<u128> = P32.try_into().unwrap();
        let (p1, p0) = DivRem::div_rem(low, P64.try_into().unwrap());
        let (rest, o0) = DivRem::div_rem(high, s32);
        let (rest, o1) = DivRem::div_rem(rest, s32);
        let (touched, o2) = DivRem::div_rem(rest, s32);
        Features {
            packs: [unpack_pack(p0), unpack_pack(p1)],
            objects: [unpack_object(o0), unpack_object(o1), unpack_object(o2)],
            touched: touched.try_into().unwrap(),
        }
    }
}

/// The two consecutive slots of a revealed chunk.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Chunk {
    pub terrain: Terrain,
    pub features: Features,
}
