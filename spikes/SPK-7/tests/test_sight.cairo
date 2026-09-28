//! AC-2: line of sight is symmetric and equals a plain version on every ordered pair of interior
//! tiles of the window within 6 of each other (14,708 pairs).

use origami_hexmap::helpers::bits::Bits;
use spk7::boards::DEEP_TERRAIN;
use spk7::sight::{between_mask, line_of_sight};
use super::helpers::W;

/// Axial coordinates, shifted by +8 on q so that they stay positive in the window.
fn axial(tile: u8) -> (i32, i32) {
    let (x, y): (i32, i32) = ((tile % W).into(), (tile / W).into());
    (x - y / 2 + 8, y)
}

fn distance(a: u8, b: u8) -> i32 {
    let (q1, r1) = axial(a);
    let (q2, r2) = axial(b);
    let (dq, dr) = (q2 - q1, r2 - r1);
    let mut best = if dq < 0 {
        -dq
    } else {
        dq
    };
    let adr = if dr < 0 {
        -dr
    } else {
        dr
    };
    if adr > best {
        best = adr;
    }
    let s = dq + dr;
    let s = if s < 0 {
        -s
    } else {
        s
    };
    if s > best {
        best = s;
    }
    best
}

/// The plain version: each of the N - 1 points of the line, in exact multiples of 1/N, rounded
/// to the nearest of the 4 lattice tiles around it by the squared Euclidean distance of cube
/// coordinates, ties to the lower tile index.
fn between_plain(a: u8, b: u8) -> felt252 {
    let n = distance(a, b);
    let (q1, r1) = axial(a);
    let (q2, r2) = axial(b);
    let mut mask: felt252 = 0;
    let mut i: i32 = 1;
    while i < n {
        let q = q1 * (n - i) + q2 * i;
        let r = r1 * (n - i) + r2 * i;
        let (fq, fr) = (q / n, r / n);
        let mut best_d: i32 = -1;
        let mut best_tile: i32 = 0;
        for cq in array![fq, fq + 1] {
            for cr in array![fr, fr + 1] {
                let dq = q - n * cq;
                let dr = r - n * cr;
                let ds = dq + dr;
                let d2 = dq * dq + dr * dr + ds * ds;
                let tile = cr * 15 + cq - 8 + cr / 2;
                if best_d == -1 || d2 < best_d || (d2 == best_d && tile < best_tile) {
                    best_d = d2;
                    best_tile = tile;
                }
            }
        }
        let tile: u8 = best_tile.try_into().unwrap();
        let power = Bits::pow(tile);
        let wide: u256 = mask.into();
        if !Bits::get(wide, tile) {
            mask += power;
        }
        i += 1;
    }
    mask
}

fn interior(tile: u8) -> bool {
    let (x, y) = (tile % W, tile / W);
    x >= 1 && x <= 13 && y >= 1 && y <= 14
}

/// Every ordered pair from sources on rows `from..to` to interior tiles within 6.
fn check_rows(from: u8, to: u8) -> u32 {
    let mut pairs: u32 = 0;
    let mut a: u8 = from * W;
    while a != to * W {
        if interior(a) {
            let mut b: u8 = 16;
            while b != 224 {
                if interior(b) && distance(a, b) <= 6 {
                    let mask = between_mask(a, b);
                    assert!(mask == between_plain(a, b), "{} -> {}", a, b);
                    assert!(mask == between_mask(b, a), "{} <-> {}", a, b);
                    let open: u256 = DEEP_TERRAIN.into();
                    let wide: u256 = mask.into();
                    assert!(line_of_sight(a, b, DEEP_TERRAIN) == ((wide & open) == wide));
                    pairs += 1;
                }
                b += 1;
            }
        }
        a += 1;
    }
    pairs
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_line_of_sight_rows_1_to_4() {
    check_rows(1, 5);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_line_of_sight_rows_5_to_8() {
    check_rows(5, 9);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_line_of_sight_rows_9_to_11() {
    check_rows(9, 12);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_line_of_sight_rows_12_to_14() {
    check_rows(12, 15);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_line_of_sight_values() {
    // Adjacent tiles see each other through nothing; a wall between blocks; actors do not
    let terrain = DEEP_TERRAIN;
    assert!(between_mask(112, 113) == 0);
    assert!(line_of_sight(112, 113, 0));
    // (7, 7) to (9, 7): (8, 7) between
    assert!(between_mask(112, 114) == Bits::pow(113));
    assert!(line_of_sight(112, 114, Bits::pow(113)));
    assert!(!line_of_sight(112, 114, terrain - (if Bits::get(terrain.into(), 113) {
        Bits::pow(113)
    } else {
        0
    })));
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'los: beyond range')]
fn test_line_of_sight_beyond_range() {
    // (1, 7) to (8, 7): 7 apart
    between_mask(106, 113);
}
