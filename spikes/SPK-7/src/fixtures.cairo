//! The measured states, built the same way for snforge and for the local node. Loops over tiles:
//! setup only, never measured.

use origami_hexmap::helpers::bits::Bits;
use crate::boards::{CAPPED_DX, CAPPED_DY, CAPPED_GOBLINS, CAPPED_TERRAIN};
use crate::chunk::{Biome, Side, Sides, generate_chunk};
use crate::window::{Layers, WIDTH};

/// The worst-case tick's window: its lowest chunk is (2, 3), its offsets in it are those
/// `boards.py` chose (dx = CAPPED_DX, dy = CAPPED_DY), so the origin is (30 + dx, 45 + dy), an even
/// row; the adventurer stands on local (7, 7), an odd global row.
pub const WORST_CX0: u8 = 2;
pub const WORST_CY0: u8 = 3;

/// The window's origin and the adventurer's global tile in the worst case.
pub fn worst_origin() -> (u8, u8) {
    (WORST_CX0 * WIDTH + CAPPED_DX, WORST_CY0 * WIDTH + CAPPED_DY)
}

pub fn worst_adventurer() -> (u8, u8) {
    let (ox, oy) = worst_origin();
    (ox + 7, oy + 7)
}

/// Global tile of a local tile of the worst-case window.
fn global(tile: u8) -> (u8, u8) {
    let (ox, oy) = worst_origin();
    let (ly, lx) = DivRem::div_rem(tile, WIDTH.try_into().unwrap());
    (ox + lx, oy + ly)
}

/// The goblins of the worst case, in global tiles, ascending id.
pub fn worst_goblins() -> Array<(u8, u8)> {
    let mut out = array![];
    for tile in CAPPED_GOBLINS.span() {
        out.append(global(*tile));
    }
    out
}

/// The 4 chunks under the worst-case window, `(cx, cy, layers)`, in the window's order: the
/// window's terrain cut into them, everything else wall; the goblins in their occupied layers.
pub fn worst_chunks() -> Array<(u8, u8, Layers)> {
    let terrain: u256 = CAPPED_TERRAIN.into();
    let mut goblins: felt252 = 0;
    for tile in CAPPED_GOBLINS.span() {
        goblins += Bits::pow(*tile);
    }
    let goblins: u256 = goblins.into();
    let mut slots: Array<(u8, u8, Layers)> = array![];
    for (dx, dy) in array![(0_u8, 0_u8), (0, 1), (1, 0), (1, 1)] {
        let (cx, cy) = (WORST_CX0 + dx, WORST_CY0 + dy);
        let mut layers = Layers { terrain: 0, occupied: 0 };
        let mut tile: u8 = 0;
        while tile != 240 {
            let (x, y) = global(tile);
            let (tx, lx) = DivRem::div_rem(x, WIDTH.try_into().unwrap());
            let (ty, ly) = DivRem::div_rem(y, WIDTH.try_into().unwrap());
            if tx == cx && ty == cy {
                let bit = Bits::pow(WIDTH * ly + lx);
                if Bits::get(terrain, tile) {
                    layers.terrain += bit;
                }
                if Bits::get(goblins, tile) {
                    layers.occupied += bit;
                }
            }
            tile += 1;
        }
        slots.append((cx, cy, layers));
    }
    slots
}

/// The reveal fixture: 3 chunks in an L, A = (2, 2), B = (3, 2), C = (2, 3) (C on an odd chunk
/// row: the parity flag), in a location of 7 x 7 chunks. What sight of radius 6 can touch at once
/// is a 2 x 2 block of chunks, so 3 new chunks form an L.
pub const REVEAL_CHUNKS: [(u8, u8); 3] = [(2, 2), (3, 2), (2, 3)];
/// The 7 chunks around the L, revealed first in the case "every neighbour known".
pub const REVEAL_AROUND: [(u8, u8); 7] = [(1, 2), (2, 1), (4, 2), (3, 1), (3, 3), (1, 3), (2, 4)];
/// Size of the reveal fixture's location, in chunks.
pub const LOCATION: u8 = 7;

/// Terrain of a neighbour of the reveal fixture: a chunk generated with every side drawn.
pub fn neighbour_terrain(biome: Biome, cx: u8, cy: u8) -> felt252 {
    let sides = Sides { east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open };
    let (_, odd) = DivRem::div_rem(cy, 2);
    generate_chunk('NEIGHBOUR' + cx.into() * 256 + cy.into(), biome, sides, odd == 1)
}
