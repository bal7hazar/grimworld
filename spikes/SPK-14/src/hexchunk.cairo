//! The hexagonal chunk of D-165: sides 9-9-11-9-9-11, 251 tiles, one felt a layer.
//!
//! Axial coordinates of the library (`q = x - floor(y / 2)`, `r = y`, `+y` North). The chunk
//! anchored at axial (0, 0) holds the tiles `0 <= r <= 16`, `0 <= q <= 18`, `8 <= q + r <= 26`:
//! 17 rows of 11 to 19 tiles, the long sides of 11 on rows 0 (South) and 16 (North). Its bits go
//! row by row from the South, each row by increasing `q`: `bit = FIRST[r] + q - QLO[r]`.
//! Chunks tile the plane on the lattice `a T_U + b T_R`, `T_U = (-9, 17)`, `T_R = (19, -8)`
//! (determinant 251); a chunk's six neighbours are `+-T_U`, `+-T_R`, `+-(T_U + T_R)`.

use crate::tables::{FIRST, QHI, QLO, TILE};

/// Tiles of a chunk.
pub const TILES: u8 = 251;
/// Rows of a chunk.
pub const ROWS: u8 = 17;
/// 251 · 64: keeps the rounded lattice coordinates' numerators non-negative.
const OFFSET: felt252 = 16064;

pub mod errors {
    pub const HEXCHUNK_OUTSIDE: felt252 = 'HexChunk: tile outside';
    pub const HEXCHUNK_INVALID_BIT: felt252 = 'HexChunk: invalid bit';
    pub const HEXCHUNK_NOT_FOUND: felt252 = 'HexChunk: chunk not found';
}

/// A tile located in its chunk: the chunk's lattice coordinates and the tile's local axial
/// coordinates.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Located {
    pub a: i32,
    pub b: i32,
    pub q: u8,
    pub r: u8,
}

#[generate_trait]
pub impl HexChunkImpl of HexChunkTrait {
    /// The bit of a local tile.
    /// # Panics
    /// * If the tile is not in the chunk
    #[inline]
    fn index(q: u8, r: u8) -> u8 {
        assert(r < ROWS, errors::HEXCHUNK_OUTSIDE);
        let low = *QLO.span()[r.into()];
        assert(q >= low && q <= *QHI.span()[r.into()], errors::HEXCHUNK_OUTSIDE);
        *FIRST.span()[r.into()] + q - low
    }

    /// The local tile of a bit, `(q, r)`.
    #[inline]
    fn tile(bit: u8) -> (u8, u8) {
        assert(bit < TILES, errors::HEXCHUNK_INVALID_BIT);
        let packed = *TILE.span()[bit.into()];
        let (r, q) = DivRem::div_rem(packed, 32);
        (q.try_into().unwrap(), r.try_into().unwrap())
    }

    /// Whether a local axial tile is in the chunk.
    #[inline(always)]
    fn inside(q: i32, r: i32) -> bool {
        r >= 0 && r <= 16 && q >= 0 && q <= 18 && q + r >= 8 && q + r <= 26
    }

    /// The axial coordinates of an offset tile (odd-r, the library's convention).
    #[inline(always)]
    fn axial(x: i32, y: i32) -> (i32, i32) {
        // floor(y / 2) for any sign: shifted to a non-negative value of the same parity
        let half: i32 = ((y + 512) / 2) - 256;
        (x - half, y)
    }

    /// The chunk that holds an axial tile, and the tile in it: the lattice coordinates rounded
    /// from the inverse matrix about the chunk's centre (9, 8), then at most one translation
    /// (checked on every tile of 256 x 256 by `geometry.py`, `check_locate`).
    fn locate(q: i32, r: i32) -> Located {
        // [Compute] Rounded lattice coordinates, on felts shifted to non-negative values:
        // a = round((8 (q - 9) + 19 (r - 8)) / 251), b = round((17 (q - 9) + 9 (r - 8)) / 251),
        // each + 64
        let q: felt252 = q.into();
        let r: felt252 = r.into();
        let na: u32 = (8 * q + 19 * r - 224 + 125 + OFFSET).try_into().unwrap();
        let nb: u32 = (17 * q + 9 * r - 225 + 125 + OFFSET).try_into().unwrap();
        let (a, _) = DivRem::div_rem(na, 251);
        let (b, _) = DivRem::div_rem(nb, 251);
        let a: felt252 = a.into() - 64;
        let b: felt252 = b.into() - 64;
        // [Compute] The tile in that chunk, + 32 on both coordinates
        let lq: u8 = (q + 9 * a - 19 * b + 32).try_into().unwrap();
        let lr: u8 = (r - 17 * a + 8 * b + 32).try_into().unwrap();
        let (da, db, lq, lr) = Self::enter(lq, lr);
        Located {
            a: (a + da).try_into().unwrap(),
            b: (b + db).try_into().unwrap(),
            q: lq - 32,
            r: lr - 32,
        }
    }

    /// Whether a local tile, + 32 on both coordinates, is in the chunk.
    #[inline(always)]
    fn inside_shifted(q: u8, r: u8) -> bool {
        let sum = q + r;
        r >= 32 && r <= 48 && q >= 32 && q <= 50 && sum >= 72 && sum <= 90
    }

    /// A local tile (+ 32) just outside the chunk brought into the neighbour that holds it.
    /// # Returns
    /// * The lattice step `(da, db)` and the tile (+ 32) in that chunk
    fn enter(q: u8, r: u8) -> (felt252, felt252, u8, u8) {
        if Self::inside_shifted(q, r) {
            return (0, 0, q, r);
        }
        if Self::inside_shifted(q + 9, r - 17) {
            return (1, 0, q + 9, r - 17);
        }
        if Self::inside_shifted(q + 19, r - 8) {
            return (0, -1, q + 19, r - 8);
        }
        if Self::inside_shifted(q + 10, r + 9) {
            return (-1, -1, q + 10, r + 9);
        }
        if Self::inside_shifted(q - 10, r - 9) {
            return (1, 1, q - 10, r - 9);
        }
        if Self::inside_shifted(q - 19, r + 8) {
            return (0, 1, q - 19, r + 8);
        }
        assert(Self::inside_shifted(q - 9, r + 17), errors::HEXCHUNK_NOT_FOUND);
        (-1, 0, q - 9, r + 17)
    }
}
