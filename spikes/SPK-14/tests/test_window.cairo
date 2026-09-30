//! AC-3: the window assembled from hexagonal chunks equals a direct construction on every origin
//! class (the 251 positions of the origin in its chunk; an even global row fixes the chunk's
//! parity), both layers; `origin` locates the window of an adventurer on either row parity.

use spk14::hexchunk::HexChunkTrait;
use spk14::window::{HexOrigin, HexWindowTrait};
use super::helpers::{has, member, random_bits};

/// Lattice steps of the 12 slots, `slot = 4 da + db + 1`.
fn step(slot: u8) -> (i32, i32) {
    let (da, db) = DivRem::div_rem(slot, 4);
    (da.into(), db.into() - 1)
}

/// The oracle: every tile of the window looked up in the one slot whose chunk holds it, by the
/// definition of the hexagon (no rounding, no walk); the ring of the terrain is wall.
fn window_plain(
    x0: i32, y0: i32, a0: i32, b0: i32, terrain: Span<felt252>, occupied: Span<felt252>,
) -> (felt252, felt252) {
    let mut grid: felt252 = 0;
    let mut occ: felt252 = 0;
    let mut power: felt252 = 1;
    let mut ly: i32 = 0;
    while ly != 16 {
        let mut lx: i32 = 0;
        while lx != 15 {
            let (q, r) = HexChunkTrait::axial(x0 + lx, y0 + ly);
            let mut slot: u8 = 0;
            let mut found = false;
            while slot != 12 {
                let (da, db) = step(slot);
                let (a, b) = (a0 + da, b0 + db);
                let lq = q + 9 * a - 19 * b;
                let lr = r - 17 * a + 8 * b;
                if member(lq, lr) {
                    assert!(!found);
                    found = true;
                    let bit = HexChunkTrait::index(lq.try_into().unwrap(), lr.try_into().unwrap());
                    let ring = lx == 0 || lx == 14 || ly == 0 || ly == 15;
                    if !ring && has(*terrain[slot.into()], bit) {
                        grid += power;
                    }
                    if has(*occupied[slot.into()], bit) {
                        occ += power;
                    }
                }
                slot += 1;
            }
            assert!(found, "tile ({}, {}) in no slot", lx, ly);
            power *= 2;
            lx += 1;
        }
        ly += 1;
    }
    (grid, occ)
}

/// The global offset origin of the window whose origin is tile `bit` of its chunk, the chunk at
/// lattice `(a0, b0)` = `(4 + r mod 2, 3)`, so that the origin's global row is even.
fn placement(bit: u8) -> (i32, i32, HexOrigin) {
    let (q, r) = HexChunkTrait::tile(bit);
    let (_, odd) = DivRem::div_rem(r, 2);
    let a0: i32 = 4 + odd.into();
    let b0: i32 = 3;
    let aq = -9 * a0 + 19 * b0 + q.into();
    let ar = 17 * a0 - 8 * b0 + r.into();
    // Offset x = q + floor(r / 2), r >= 0 here
    let x0 = aq + ar / 2;
    (x0, ar, HexOrigin { a: a0, b: b0, q, r })
}

fn check_classes(from: u8, to: u8) {
    let mut bit = from;
    while bit != to {
        let (x0, y0, origin) = placement(bit);
        assert!(y0 % 2 == 0);
        // The adventurer's window on an odd and an even row: the same origin
        let x: u8 = (x0 + 7).try_into().unwrap();
        assert!(HexWindowTrait::origin(x, (y0 + 7).try_into().unwrap()) == origin, "bit {}", bit);
        assert!(HexWindowTrait::origin(x, (y0 + 8).try_into().unwrap()) == origin, "bit {}", bit);
        let mut terrain: Array<felt252> = array![];
        let mut occupied: Array<felt252> = array![];
        let mut slot: u8 = 0;
        while slot != 12 {
            let seed: felt252 = bit.into() * 16 + slot.into();
            terrain.append(random_bits(seed, 251));
            occupied.append(random_bits(seed + 'OCC', 251));
            slot += 1;
        }
        let (grid, occ) = window_plain(x0, y0, origin.a, origin.b, terrain.span(), occupied.span());
        let t = terrain.span();
        let o = occupied.span();
        let (map, got) = HexWindowTrait::window(
            [
                Some(*t[0]), Some(*t[1]), Some(*t[2]), Some(*t[3]), Some(*t[4]), Some(*t[5]),
                Some(*t[6]), Some(*t[7]), Some(*t[8]), Some(*t[9]), Some(*t[10]), Some(*t[11]),
            ],
            [
                Some(*o[0]), Some(*o[1]), Some(*o[2]), Some(*o[3]), Some(*o[4]), Some(*o[5]),
                Some(*o[6]), Some(*o[7]), Some(*o[8]), Some(*o[9]), Some(*o[10]), Some(*o[11]),
            ],
            @origin,
            0,
        );
        assert!(map.grid == grid, "terrain, bit {}", bit);
        assert!(got == occ, "occupied, bit {}", bit);
        bit += 1;
    }
}

#[test]
fn test_window_matches_plain_0_to_63() {
    check_classes(0, 63);
}

#[test]
fn test_window_matches_plain_63_to_126() {
    check_classes(63, 126);
}

#[test]
fn test_window_matches_plain_126_to_189() {
    check_classes(126, 189);
}

#[test]
fn test_window_matches_plain_189_to_251() {
    check_classes(189, 251);
}

#[test]
fn test_window_void_chunks_are_wall() {
    // The 6-chunk class with its chunks void except the origin's: only its tiles are set
    let (x0, y0, origin) = placement(185);
    let full: felt252 = random_bits('FULL', 251);
    let terrain: Array<felt252> = array![0, full, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let (grid, occ) = window_plain(x0, y0, origin.a, origin.b, terrain.span(), terrain.span());
    let (map, got) = HexWindowTrait::window(
        [None, Some(full), None, None, None, None, None, None, None, None, None, None],
        [None, Some(full), None, None, None, None, None, None, None, None, None, None],
        @origin,
        0,
    );
    assert!(map.grid == grid && got == occ);
}
