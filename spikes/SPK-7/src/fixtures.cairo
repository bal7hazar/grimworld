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

/// Global tile of a local tile of the window at an origin.
fn global_at(origin_x: u8, origin_y: u8, tile: u8) -> (u8, u8) {
    let (ly, lx) = DivRem::div_rem(tile, WIDTH.try_into().unwrap());
    (origin_x + lx, origin_y + ly)
}

/// The goblins of the worst-case board placed at an origin, in global tiles, ascending id.
pub fn goblins_at(origin_x: u8, origin_y: u8) -> Array<(u8, u8)> {
    let mut out = array![];
    for tile in CAPPED_GOBLINS.span() {
        out.append(global_at(origin_x, origin_y, *tile));
    }
    out
}

/// The goblins of the worst case, in global tiles, ascending id.
pub fn worst_goblins() -> Array<(u8, u8)> {
    let (ox, oy) = worst_origin();
    goblins_at(ox, oy)
}

/// Chunks of a world holding the worst-case board at an origin, everything else wall; the goblins
/// in their occupied layers.
pub fn chunks_at(origin_x: u8, origin_y: u8, chunks: Span<(u8, u8)>) -> Array<(u8, u8, Layers)> {
    let terrain: u256 = CAPPED_TERRAIN.into();
    let mut goblins: felt252 = 0;
    for tile in CAPPED_GOBLINS.span() {
        goblins += Bits::pow(*tile);
    }
    let goblins: u256 = goblins.into();
    let mut slots: Array<(u8, u8, Layers)> = array![];
    for (cx, cy) in chunks {
        let (cx, cy) = (*cx, *cy);
        let mut layers = Layers { terrain: 0, occupied: 0 };
        let mut tile: u8 = 0;
        while tile != 240 {
            let (x, y) = global_at(origin_x, origin_y, tile);
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

/// The 4 chunks under the worst-case window, `(cx, cy, layers)`, in the window's order: the
/// window's terrain cut into them, everything else wall; the goblins in their occupied layers.
pub fn worst_chunks() -> Array<(u8, u8, Layers)> {
    let (ox, oy) = worst_origin();
    let (x0, y0) = (WORST_CX0, WORST_CY0);
    chunks_at(ox, oy, array![(x0, y0), (x0, y0 + 1), (x0 + 1, y0), (x0 + 1, y0 + 1)].span())
}

/// Fix loop 1: a move that changes the window's chunks. The worst-case board stands at origin
/// (37, 60) (chunks (2, 4), (2, 5), (3, 4), (3, 5)); the adventurer starts on (44, 66), an even
/// row, so its window's origin is (37, 58) (chunks (2, 3), (2, 4), (3, 3), (3, 4)), and steps
/// North-West onto (44, 67): the origin moves 2 rows and the chunk row changes.
pub const SHIFT_ORIGIN: (u8, u8) = (37, 60);
pub const SHIFT_START: (u8, u8) = (44, 66);
/// North-West.
pub const SHIFT_DIRECTION: u8 = 2;
/// The chunks of both windows.
pub const SHIFT_CHUNKS: [(u8, u8); 6] = [(2, 3), (2, 4), (2, 5), (3, 3), (3, 4), (3, 5)];
/// Moves pending in the stored window (B'): each of the 4 chunks under the old window marks a tile
/// the window knows is free (a goblin that left it), `(cx, cy, bit)`; chunks (2, 4) and (3, 4) also
/// miss the goblins that entered them. Writing the window back changes all 4.
/// Synthetic: these tiles are walls (three on the old window's frozen ring); valid ticks cannot
/// produce them. The case covers the write-back branch only (audit of PR 50, re-audit finding 3).
pub const SHIFT_GHOSTS: [(u8, u8, u8); 4] = [(2, 3, 205), (3, 3, 197), (2, 4, 7), (3, 4, 0)];

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
