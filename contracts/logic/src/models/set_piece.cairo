//! `SET_PIECE`: its constructor, its checks and its record (layout: `models::index::SetPiece`). An
//! authored chunk laid by a quota (ADR-0006 *Set pieces*): the reveal keeps its interior and
//! placements and joins its ring like any chunk's (`types::reveal`).

use crate::content::{Record, SET_PIECE};
use crate::packing::{P16, P24, P48, P8, P80, join, peel, split};
use super::chunk::{ObjectTrait, errors as chunk_errors};
pub use super::index::{Object, SetPack, SetPiece};

/// 2^97: the walls' part in the high limb is below it (bits 128–224).
const P97: u128 = 0x2000000000000000000000000;

#[generate_trait]
pub impl SetPieceImpl of SetPieceTrait {
    fn new(walls: felt252, packs: [SetPack; 2], objects: [Object; 3]) -> SetPiece {
        SetPiece { walls, packs, objects }
    }
}

/// Its bits in a record's limb, and back (the field order of the record's layout).
#[generate_trait]
pub impl SetPackBits of SetPackBitsTrait {
    #[inline(always)]
    fn bits(pack: @SetPack) -> u128 {
        (*pack.tile).into() + (*pack.template).into() * P8
    }

    #[inline(always)]
    fn peel(ref rest: u128) -> SetPack {
        let tile = peel(ref rest, P8.try_into().unwrap());
        let template = peel(ref rest, P16.try_into().unwrap());
        SetPack { tile: tile.try_into().unwrap(), template: template.try_into().unwrap() }
    }
}

pub impl SetPieceRecord of Record<SetPiece> {
    const KIND: u8 = SET_PIECE;

    fn pack(self: @SetPiece) -> Span<felt252> {
        let walls: u256 = (*self.walls).into();
        assert(walls.high < P97, chunk_errors::WALLS);
        let [p0, p1] = self.packs;
        let [o0, o1, o2] = self.objects;
        let low = SetPackBitsTrait::bits(p0) + SetPackBitsTrait::bits(p1) * P24 + o0.bits() * P48 + o1.bits() * P80;
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
    use super::{Object, SetPack, SetPieceRecord, SetPieceTrait};

    #[test]
    #[available_gas(l2_gas: 1500000)]
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
        let low: felt252 = 0x70 + 0xabcd * 0x100 + 0x71 * 0x1000000 + 0x1 * 0x100000000
            + (0x72 + 5 * 0x100 + 0x1234 * 0x10000) * 0x1000000000000;
        let high: felt252 = 0x73 + 6 * 0x100 + 0xbeef * 0x10000;
        assert(*parts[1] == low + high * 0x100000000000000000000000000000000 + LIVE, 'placements');
        assert(SetPieceRecord::unpack(parts) == piece, 'round trip');
    }
}
