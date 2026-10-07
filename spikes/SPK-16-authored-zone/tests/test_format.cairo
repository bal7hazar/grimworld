//! The format (ENG-08 AC-2, AC-7): the proposed records pack and unpack, bit by bit; the
//! converter's output decodes to the sample's fields and packs back to the same felts.

use grimworld_logic::models::chunk::Object;
use grimworld_logic::models::set_piece::SetPack;
use grimworld_logic::packing::LIVE;
use spk16::records::{AUTHORED, Bridge, BridgeTrait, CandidatesTrait, GENERATED, MarkerTrait};
use spk16::zone_chunk::{ZoneChunk, ZoneChunkRecord, ZoneChunkTrait};
use crate::fixtures::{ZONE, load};

const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;

fn record() -> ZoneChunk {
    ZoneChunk {
        walls: 0x1fffffffffffffffffffffffff00000000000000000000000000000ff,
        spawns: [SetPack { tile: 0x70, template: 0xabcd }, SetPack { tile: 0x71, template: 1 }],
        objects: [
            Object { tile: 0x72, kind: 1, state: 0, param: 0x1234 }, Default::default(),
            Object { tile: 0x73, kind: 6, state: 0, param: 0xbeef },
        ],
        tiles: [0x10, 0, 0x20, 0, 0, 0xe0],
        bridges: 15,
        gates: [0x1111, 0xffff],
    }
}

#[test]
fn test_zone_chunk_bits_and_round_trip() {
    let chunk = record();
    let parts = ZoneChunkRecord::pack(@chunk);
    assert(parts.len() == 2, 'two parts');
    assert(*parts[0] == chunk.walls + LIVE, 'walls');
    let low: felt252 = 0x70
        + 0xabcd * 0x100
        + 0x71 * 0x1000000
        + 0x1 * 0x100000000
        + (0x72 + 1 * 0x100 + 0x1234 * 0x10000) * 0x1000000000000;
    // high limb: object 2 at 0, the tiles at 32 + 8 i, bridges at 80, gates at 84 and 100
    let high: felt252 = (0x73 + 6 * 0x100 + 0xbeef * 0x10000)
        + 0x10 * 0x100000000
        + 0x20 * 0x1000000000000
        + 0xe0 * 0x1000000000000000000
        + 15 * 0x100000000000000000000
        + 0x1111 * 0x1000000000000000000000
        + 0xffff * 0x10000000000000000000000000;
    assert(*parts[1] == low + high * TWO_POW_128 + LIVE, 'features');
    assert(ZoneChunkRecord::unpack(parts) == chunk, 'round trip');
    assert(chunk.tile(5) == 0xe0, 'tile of quota 5');
    assert(ZoneChunkTrait::id(2, 16) == 2 * 256 + 16, 'id');
}

#[test]
#[should_panic(expected: 'zone chunk: reserved plane')]
fn test_zone_chunk_reserved_plane_refused() {
    let parts = ZoneChunkRecord::pack(@record());
    // A bit of the reserved planes (225-249) set: format 1 reads none
    let raised = *parts[0] + 0x200000000000000000000000000000000000000000000000000000000;
    ZoneChunkRecord::unpack(array![raised, *parts[1]].span());
}

#[test]
#[should_panic(expected: 'zone chunk: walls above 224')]
fn test_zone_chunk_wide_walls_refused() {
    let mut chunk = record();
    chunk.walls = 0x200000000000000000000000000000000000000000000000000000000;
    ZoneChunkRecord::pack(@chunk);
}

#[test]
fn test_bridge_bits_and_round_trip() {
    // A one-tile deck (tile 112) and its two ends (D-217's smallest bridge)
    let one = Bridge { deck: 0x10000000000000000000000000000, ends: (111, 113) };
    let parts = one.pack();
    let ends: felt252 = 111 + 113 * 0x100;
    let expected = one.deck
        + ends * 0x200000000000000000000000000000000000000000000000000000000
        + LIVE;
    assert(*parts[0] == expected, 'bits');
    assert(BridgeTrait::unpack(parts) == one, 'round trip');
    assert(BridgeTrait::id(ZONE, 15, 2) == 2 * 4096 + 15 * 16 + 2, 'id');
}

#[test]
fn test_candidates_and_marker() {
    let sets = [0x10003, 0, 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffff];
    let parts = CandidatesTrait::pack(sets);
    assert(parts.len() == 3 && *parts[1] == LIVE, 'three parts');
    assert(CandidatesTrait::unpack(parts) == sets, 'round trip');
    let part0: felt252 = 0x1234 + 0x0569 * TWO_POW_128 + LIVE;
    assert(MarkerTrait::read(part0) == GENERATED, 'today: generated');
    let marked = MarkerTrait::write(part0, AUTHORED);
    assert(MarkerTrait::read(marked) == AUTHORED, 'authored');
    assert(marked - part0 == 0x10000 * TWO_POW_128, 'bit 144');
}

/// The converter's output (`samples/zone.golden.json`): each chunk's fields pack to the felts the
/// converter wrote, and those felts unpack to the fields.
#[test]
fn test_golden_decodes_to_the_sample() {
    let z = load();
    assert(z.chunks.len() == 5, 'five chunks');
    assert(z.marker == AUTHORED, 'marked authored');
    assert(z.location.width == 3 && z.location.height == 2, 'the 3 x 2 zone');
    assert(z.location.entry_chunk == 0 && z.location.entry_tile == 105, 'the seed entry');
    // The seed's chunk set: chunks 0, 1, 2, 15, 16
    assert(z.chunk_set == 0x18007, 'the chunk set');
    for entry in z.chunks.span() {
        let (_, fields, parts) = *entry;
        let packed = ZoneChunkRecord::pack(@fields);
        assert(*packed[0] == *parts[0] && *packed[1] == *parts[1], 'packs as the converter');
        assert(ZoneChunkRecord::unpack(parts) == fields, 'unpacks to the fields');
    }
    let (chunk, k, bridge) = *z.bridges[0];
    assert(chunk == 15 && k == 0, 'the bridge in chunk 15');
    assert(bridge.deck != 0, 'its deck');
}
