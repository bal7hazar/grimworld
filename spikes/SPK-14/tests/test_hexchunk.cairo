//! AC-3: the indexing of the hexagonal chunk is a bijection onto 0..250, and `locate` finds the
//! chunk of every tile.

use spk14::hexchunk::{HexChunkTrait, TILES};
use super::helpers::member;

#[test]
fn test_index_is_a_bijection() {
    // Every tile of the definition, row by row, has the next bit: the map is onto 0..250 and
    // one-to-one; `tile` inverts it
    let mut next: u16 = 0;
    let mut r: i32 = 0;
    while r != 17 {
        let mut q: i32 = 0;
        while q != 19 {
            if member(q, r) {
                let (qq, rr): (u8, u8) = (q.try_into().unwrap(), r.try_into().unwrap());
                let bit = HexChunkTrait::index(qq, rr);
                assert!(bit.into() == next, "tile ({}, {})", q, r);
                assert!(HexChunkTrait::tile(bit) == (qq, rr));
                assert!(HexChunkTrait::inside(q, r));
                next += 1;
            } else {
                assert!(!HexChunkTrait::inside(q, r));
            }
            q += 1;
        }
        r += 1;
    }
    assert!(next == TILES.into());
}

#[test]
fn test_corners_and_live_bit() {
    // The six corners: the ends of rows 0, 8 and 16; bit 250 is one of them
    assert!(HexChunkTrait::index(8, 0) == 0);
    assert!(HexChunkTrait::index(18, 0) == 10);
    assert!(HexChunkTrait::index(0, 8) == 116);
    assert!(HexChunkTrait::index(18, 8) == 134);
    assert!(HexChunkTrait::index(0, 16) == 240);
    assert!(HexChunkTrait::index(10, 16) == 250);
}

#[test]
#[should_panic(expected: 'HexChunk: tile outside')]
fn test_index_refuses_outside() {
    HexChunkTrait::index(7, 0);
}

/// The chunk of a tile by trying every lattice point near it: the plain oracle of `locate`.
fn locate_plain(q: i32, r: i32) -> (i32, i32, i32, i32) {
    let mut found: Array<(i32, i32, i32, i32)> = array![];
    // The band below lies in chunks with |a|, |b| <= 3
    let mut a: i32 = -4;
    while a != 5 {
        let mut b: i32 = -4;
        while b != 5 {
            let lq = q + 9 * a - 19 * b;
            let lr = r - 17 * a + 8 * b;
            if member(lq, lr) {
                found.append((a, b, lq, lr));
            }
            b += 1;
        }
        a += 1;
    }
    assert!(found.len() == 1, "tile ({}, {}) in {} chunks", q, r, found.len());
    *found[0]
}

#[test]
fn test_locate_matches_plain() {
    // A band of tiles across several chunks, both signs of the lattice coordinates
    let mut y: i32 = -20;
    while y != 40 {
        let mut x: i32 = -20;
        while x != 40 {
            let (q, r) = HexChunkTrait::axial(x, y);
            let located = HexChunkTrait::locate(q, r);
            let (a, b, lq, lr) = locate_plain(q, r);
            assert!(located.a == a && located.b == b, "({}, {})", x, y);
            assert!(located.q.into() == lq && located.r.into() == lr);
            x += 3;
        }
        y += 1;
    }
}
