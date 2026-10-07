//! D-134's corner walls (ENG-08 ruling 5, AC-6). The readers of a chunk's corners in the code, by
//! search (README *Corners*): the generation (`types/reveal.cairo` `corner`, `board.cairo`'s
//! `SIDES` and the reveal's invariant test) and `SetPieceAssert` (`set_piece.cairo`). None in the
//! window's rules, the tick, the flood or `Instances`. These tests hold what that means for an
//! authored chunk: its checks accept open corners and its reveal keeps them; the window's rules
//! read walls, and a corner is a tile like any other there.

use grimworld_logic::models::chunk::Object;
use grimworld_logic::models::set_piece::{SetPack, SetPiece, SetPieceAssert};
use grimworld_logic::types::effect::shape;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use grimworld_logic::types::window::WindowTrait;
use spk16::authored::AuthoredTrait;
use spk16::checks::ZoneAssert;
use spk16::zone_chunk::ZoneChunk;
use crate::fixtures::{ZoneTrait, load};

/// The four corner tiles (`set_piece.cairo`'s `CORNERS`).
const CORNERS: felt252 = 0x100040000000000000000000000000000000000000000000000004001;

/// A chunk whose only walls are its ring but its four corners: every corner open.
fn open_corners() -> felt252 {
    let mut ring: felt252 = 0;
    let mut i: u8 = 0;
    while i != 15 {
        ring = BoardTrait::or(ring, BoardTrait::pow(i)); // row 0
        ring = BoardTrait::or(ring, BoardTrait::pow(210 + i)); // row 14
        ring = BoardTrait::or(ring, BoardTrait::pow(15 * i)); // column 0
        ring = BoardTrait::or(ring, BoardTrait::pow(15 * i + 14)); // column 14
        i += 1;
    }
    BoardTrait::minus(ring, CORNERS)
}

fn chunk(walls: felt252) -> ZoneChunk {
    ZoneChunk {
        walls,
        spawns: [Default::default(), Default::default()],
        objects: [Default::default(), Default::default(), Default::default()],
        tiles: [0, 0, 0, 0, 0, 0],
        bridges: 0,
        gates: [0, 0],
    }
}

#[test]
fn test_authored_corners_accepted_and_kept() {
    let z = load();
    let walls = open_corners();
    let record = ZoneChunk {
        objects: [
            Object { tile: 0, kind: 1, state: 0, param: 0 }, Default::default(), Default::default(),
        ],
        ..chunk(walls),
    };
    // A chest on corner 0: an authored chunk's corner is a tile like any other
    ZoneAssert::assert_chunk(@record, 1, array![].span(), @z.quotas);
    let (terrain, features) = AuthoredTrait::reveal(
        @z.site(), 1, @record, array![].span(), 'e', 'i',
    );
    assert(BoardTrait::and(terrain.walls, CORNERS) == 0, 'corners kept open');
    let [o0, _, _] = features.objects;
    assert(o0.tile == 0, 'the chest on the corner');
}

#[test]
#[should_panic(expected: 'set piece: corner not wall')]
fn test_set_piece_still_reads_corners() {
    // Ruling 5 keeps D-134 for generated chunks and set pieces
    let piece = SetPiece {
        walls: open_corners(),
        packs: [SetPack { tile: 0, template: 0 }, SetPack { tile: 0, template: 0 }],
        objects: [Default::default(), Default::default(), Default::default()],
    };
    piece.assert_legal();
}

/// The window's rules (ENG-02) on a chunk's rows, every tile open: an open corner is seen like any
/// tile and a disc around it holds it; walled, it blocks. The rules read the walls only.
#[test]
fn test_window_reads_walls_not_corners() {
    let open = BOARD;
    let window = WindowTrait::new(open);
    assert(window.sight(112, 0), 'an open corner is seen');
    assert(window.sight(112, 224), 'every open corner');
    assert(BoardTrait::has(window.shape(shape::DISC_1, 0), 0), 'a disc holds it');
    let walled = WindowTrait::new(BoardTrait::minus(open, CORNERS));
    assert(!walled.sight(112, 0), 'a wall corner blocks');
}
