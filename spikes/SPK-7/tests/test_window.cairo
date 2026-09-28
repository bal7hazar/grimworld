//! AC-1: the assembly equals a plain tile-by-tile assembly on every overlap case (2 and 4 chunks,
//! every offset in the chunk, both row parities of the adventurer); an odd origin is refused.

use spk7::window::{CENTRE_EVEN, CENTRE_ODD, Layers, assemble_window, window_chunks, window_origin};
use super::helpers::{W, has, random_bits};

/// The oracle: every tile of the window looked up in its chunk, one at a time; the ring is wall.
fn assemble_plain(origin_x: u8, origin_y: u8, chunks: Span<(u8, u8, Layers)>) -> Layers {
    let mut terrain: felt252 = 0;
    let mut occupied: felt252 = 0;
    let mut ly: u8 = 0;
    let mut power: felt252 = 1;
    while ly != 16 {
        let mut lx: u8 = 0;
        while lx != W {
            let (x, y) = (origin_x + lx, origin_y + ly);
            let (cx, cy) = (x / W, y / W);
            let bit = W * (y % W) + x % W;
            for (kx, ky, layers) in chunks {
                if *kx == cx && *ky == cy {
                    let ring = lx == 0 || lx == W - 1 || ly == 0 || ly == 15;
                    if !ring && has(*layers.terrain, bit) {
                        terrain += power;
                    }
                    if has(*layers.occupied, bit) {
                        occupied += power;
                    }
                }
            }
            power *= 2;
            lx += 1;
        }
        ly += 1;
    }
    Layers { terrain, occupied }
}

/// Random chunks around a window origin, in the window's order; the list for the oracle.
fn chunks_at(origin_x: u8, origin_y: u8, seed: felt252) -> (Array<Layers>, Array<(u8, u8, Layers)>) {
    let (cx0, cy0, dx, _) = window_chunks(origin_x, origin_y);
    let mut ordered: Array<Layers> = array![];
    let mut listed: Array<(u8, u8, Layers)> = array![];
    let columns: u8 = if dx == 0 {
        1
    } else {
        2
    };
    let mut i: u8 = 0;
    while i != columns {
        let mut j: u8 = 0;
        while j != 2 {
            let key = seed + (i * 2 + j).into();
            let layers = Layers {
                terrain: random_bits(key, 225), occupied: random_bits(key + 'OCC', 225),
            };
            ordered.append(layers);
            listed.append((cx0 + i, cy0 + j, layers));
            j += 1;
        }
        i += 1;
    }
    (ordered, listed)
}

/// Every offset `(dx, dy)` of the given columns, for an adventurer on an odd then an even global
/// row: both give the same even origin (ADR-0006 §4: local rows 7 and 8).
fn check_offsets(dx_from: u8, dx_to: u8) {
    let mut dx = dx_from;
    while dx != dx_to {
        let mut dy: u8 = 0;
        while dy != W {
            // Chunk row 2 or 3, whichever makes the origin even
            let cy0: u8 = if dy % 2 == 0 {
                2
            } else {
                3
            };
            let (origin_x, origin_y) = (2 * W + dx, cy0 * W + dy);
            let (x, y_odd, y_even) = (origin_x + 7, origin_y + 7, origin_y + 8);
            assert!(window_origin(x, y_odd) == (origin_x, origin_y, CENTRE_ODD));
            assert!(window_origin(x, y_even) == (origin_x, origin_y, CENTRE_EVEN));
            let (ordered, listed) = chunks_at(origin_x, origin_y, (dx * 16 + dy).into());
            let window = assemble_window(origin_x, origin_y, ordered.span());
            let expected = assemble_plain(origin_x, origin_y, listed.span());
            assert!(window == expected, "dx {} dy {}", dx, dy);
            dy += 1;
        }
        dx += 1;
    }
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_assemble_matches_oracle_2_chunks() {
    check_offsets(0, 1);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_assemble_matches_oracle_4_chunks_east() {
    check_offsets(1, 8);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_assemble_matches_oracle_4_chunks_west() {
    check_offsets(8, 15);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'window: odd origin')]
fn test_assemble_refuses_odd_origin() {
    let (ordered, _) = chunks_at(30, 31, 1);
    assemble_window(30, 31, ordered.span());
}

#[test]
#[available_gas(l2_gas: 4000000000)]
#[should_panic(expected: 'window: wrong chunk count')]
fn test_assemble_refuses_missing_chunks() {
    let (ordered, _) = chunks_at(30, 30, 1);
    assemble_window(31, 30, ordered.span());
}
