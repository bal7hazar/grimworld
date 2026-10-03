//! `SET_PIECE`: its constructor, its checks and its record (layout: `models::index::SetPiece`). An
//! authored chunk laid by a quota (ADR-0006 *Set pieces*): the reveal keeps its interior and
//! placements and joins its ring like any chunk's (`types::reveal`).

use crate::content::{Record, SET_PIECE};
use crate::packing::{P16, P24, P48, P8, P80, join, peel, split};
use crate::types::reveal::board::BoardTrait;
use super::chunk::{ObjectTrait, errors as chunk_errors, object};
pub use super::index::{Object, SetPack, SetPiece};

/// 2^97: the walls' part in the high limb is below it (bits 128–224).
const P97: u128 = 0x2000000000000000000000000;
/// The four corner tiles, always wall (D-134).
const CORNERS: felt252 = 0x100040000000000000000000000000000000000000000000000004001;

pub mod errors {
    /// A corner tile that is not wall (D-134: a chunk's corners are always wall).
    pub const CORNER: felt252 = 'set piece: corner not wall';
    /// A pack's or an object's tile on the ring or on a wall.
    pub const TILE: felt252 = 'set piece: tile not floor';
    /// An object of an unknown kind, a placed trap, or not untouched.
    pub const OBJECT: felt252 = 'set piece: object';
    /// An absent pack or object with a value.
    pub const EMPTY: felt252 = 'set piece: empty with a value';
}

#[generate_trait]
pub impl SetPieceImpl of SetPieceTrait {
    fn new(walls: felt252, packs: [SetPack; 2], objects: [Object; 3]) -> SetPiece {
        SetPiece { walls, packs, objects }
    }
}

/// Its bits in a record's limb, and back (the field order of the record's layout).
#[generate_trait]
pub impl SetPackBits of SetPackBitsTrait {
    #[inline(never)]
    fn bits(pack: @SetPack) -> u128 {
        (*pack.tile).into() + (*pack.template).into() * P8
    }

    #[inline(never)]
    fn peel(ref rest: u128) -> SetPack {
        let tile = peel(ref rest, P8.try_into().unwrap());
        let template = peel(ref rest, P16.try_into().unwrap());
        SetPack { tile: tile.try_into().unwrap(), template: template.try_into().unwrap() }
    }
}

#[generate_trait]
pub impl SetPieceAssert of SetPieceAssertTrait {
    /// `Registry`'s content check (ENG-05, after CBT-05a): its corners wall (D-134); every pack
    /// (a template) and every object (a kind) on a floor tile of the interior, the ring being the
    /// reveal's to join; an object of a kind authored chunks hold (1 chest … 8 exit; a placed trap
    /// is an actor's), untouched; an absent pack or object all zeros. That a template, collector or
    /// landmark exists is the content pipeline's (OPS-01).
    fn assert_legal(self: @SetPiece) {
        let walls = *self.walls;
        assert(BoardTrait::and(walls, CORNERS) == CORNERS, errors::CORNER);
        for pack in self.packs.span() {
            if *pack.template == 0 {
                assert(*pack.tile == 0, errors::EMPTY);
            } else {
                Self::assert_floor(walls, *pack.tile);
            }
        }
        for item in self.objects.span() {
            if *item.kind == 0 {
                assert(*item.tile == 0 && *item.state == 0 && *item.param == 0, errors::EMPTY);
            } else {
                assert(*item.kind <= object::EXIT && *item.state == 0, errors::OBJECT);
                Self::assert_floor(walls, *item.tile);
            }
        }
    }

    /// `tile` is inside the ring (row and column 1 to 13) and not a wall.
    fn assert_floor(walls: felt252, tile: u8) {
        let (row, column) = DivRem::div_rem(tile, 15);
        assert(
            tile < 225 && row != 0 && row != 14 && column != 0 && column != 14
                && !BoardTrait::has(walls, tile),
            errors::TILE,
        );
    }
}

pub impl SetPieceRecord of Record<SetPiece> {
    const KIND: u8 = SET_PIECE;

    fn pack(self: @SetPiece) -> Span<felt252> {
        let walls: u256 = (*self.walls).into();
        assert(walls.high < P97, chunk_errors::WALLS);
        let [p0, p1] = self.packs;
        let [o0, o1, o2] = self.objects;
        let low = SetPackBitsTrait::bits(p0)
            + SetPackBitsTrait::bits(p1) * P24
            + o0.bits() * P48
            + o1.bits() * P80;
        array![join(walls.low, walls.high), join(low, o2.bits())].span()
    }

    fn unpack(parts: Span<felt252>) -> SetPiece {
        let (low, high) = split(*parts[0]);
        let walls: felt252 = low.into() + high.into() * 0x100000000000000000000000000000000;
        let (mut low, high) = split(*parts[1]);
        let p0 = SetPackBitsTrait::peel(ref low);
        let p1 = SetPackBitsTrait::peel(ref low);
        let s32: NonZero<u128> = 0x100000000;
        let o0 = ObjectTrait::from_bits(peel(ref low, s32));
        let o1 = ObjectTrait::from_bits(peel(ref low, s32));
        SetPiece { walls, packs: [p0, p1], objects: [o0, o1, ObjectTrait::from_bits(high)] }
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use super::{Object, SetPack, SetPieceAssert, SetPieceRecord, SetPieceTrait};

    #[test]
    #[available_gas(l2_gas: 164178)] // ceil(1.05 × 156360 measured)
    fn test_set_piece_bits_and_round_trip() {
        let walls = 0x1fffffffffffffffffffffffff00000000000000000000000000000ff;
        let piece = SetPieceTrait::new(
            walls,
            [SetPack { tile: 0x70, template: 0xabcd }, SetPack { tile: 0x71, template: 1 }],
            [
                Object { tile: 0x72, kind: 5, state: 0, param: 0x1234 }, Default::default(),
                Object { tile: 0x73, kind: 6, state: 0, param: 0xbeef },
            ],
        );
        let parts = piece.pack();
        assert(*parts[0] == walls + LIVE, 'walls');
        let low: felt252 = 0x70
            + 0xabcd * 0x100
            + 0x71 * 0x1000000
            + 0x1 * 0x100000000
            + (0x72 + 5 * 0x100 + 0x1234 * 0x10000) * 0x1000000000000;
        let high: felt252 = 0x73 + 6 * 0x100 + 0xbeef * 0x10000;
        assert(*parts[1] == low + high * 0x100000000000000000000000000000000 + LIVE, 'placements');
        assert(SetPieceRecord::unpack(parts) == piece, 'round trip');
    }

    /// Walls on the ring and on the block of rows 2–4, columns 2–4; a pack and a collector inside.
    fn arena(pack: u8, item: Object) -> super::SetPiece {
        let ring: felt252 = 0x1fffe000c00180030006000c00180030006000c00180030006000ffff;
        let mut walls: felt252 = ring;
        let mut row: u8 = 2;
        while row != 5 {
            walls += crate::types::reveal::board::BoardTrait::pow(row * 15 + 2) * 7;
            row += 1;
        }
        SetPieceTrait::new(
            walls,
            [SetPack { tile: pack, template: 1 }, Default::default()],
            [item, Default::default(), Default::default()],
        )
    }

    #[test]
    #[available_gas(l2_gas: 117015)] // ceil(1.05 × 111442 measured)
    fn test_set_piece_legal() {
        arena(112, Object { tile: 100, kind: 5, state: 0, param: 3 }).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'set piece: tile not floor')]
    #[available_gas(l2_gas: 77584)] // ceil(1.05 × 73889 measured)
    fn test_set_piece_pack_on_a_wall_refused() {
        // Tile 47 (row 3, column 2) is in the wall block.
        arena(47, Object { tile: 100, kind: 5, state: 0, param: 3 }).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'set piece: tile not floor')]
    #[available_gas(l2_gas: 106977)] // ceil(1.05 × 101882 measured)
    fn test_set_piece_object_on_the_ring_refused() {
        arena(112, Object { tile: 105, kind: 6, state: 0, param: 1 }).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'set piece: object')]
    #[available_gas(l2_gas: 83810)] // ceil(1.05 × 79819 measured)
    fn test_set_piece_placed_trap_refused() {
        arena(112, Object { tile: 100, kind: 9, state: 0, param: 1 }).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'set piece: corner not wall')]
    #[available_gas(l2_gas: 53368)] // ceil(1.05 × 50826 measured)
    fn test_set_piece_open_corner_refused() {
        let piece = arena(112, Default::default());
        let open = super::SetPiece { walls: piece.walls - 1, ..piece };
        open.assert_legal();
    }
}
