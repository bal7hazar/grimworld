//! The hexagon's generation with margins, SPK-7's steps on the shape of D-165.
//!
//! No layout with a constant row stride holds the 9-9-11 hexagon in one felt (307 bits at least,
//! `geometry.py`), and the automaton's neighbour planes and the component's dilation need one. So
//! the chunk is generated on two half-boards in axial coordinates with the stride 19, where a
//! neighbour is a constant shift (`+-1`, `+-19`, `+18`, `-18`) and no parity flag is needed: S
//! holds rows 0-9 at `19 r + q`, N rows 7-16 at `19 (r - 7) + q`. S is right on rows 0-8 and N on
//! rows 8-16; after each step `sync` copies S's rows 7-8 into N and N's row 9 into S (one piece
//! each way: the halves share the stride). At the end the halves are packed into the chunk's 251
//! bits, one piece a row (`PACK`).
//!
//! The steps are SPK-7's (`rect.cairo`): a base at the biome's density; each side copied from a
//! generated neighbour, closed on the border, or drawn (1 or 2 openings, D-22), corners wall; lines
//! from every opening to a spine (row 8, q = 9 and q + r = 17 through the centre), each of one
//! constant length; 2 passes of the automaton with the ring as margins; the component of the
//! centre. Differences imposed by the shape: six sides; two long sides (row 0, row 16) are copied
//! as one piece of the neighbour's felt, the four short ones gathered tile by tile (their tiles
//! are one per row in both chunks, at no common shift).

use core::poseidon::hades_permutation;
use hexx::board::bits::{Bits, TWO_POW_128};
use crate::automaton::AutomatonTrait;
use crate::tables::{
    COPY_MINUS_U_MASK, COPY_MINUS_U_SHIFT, COPY_PLUS_U_MASK, COPY_PLUS_U_SHIFT, GATHER_MINUS_R,
    GATHER_MINUS_UR, GATHER_PLUS_R, GATHER_PLUS_UR, INV_18, INV_19, LINE_DOWN, LINE_HIGHER_Q,
    LINE_LOWER_Q, LINE_UP, LOW19, N_CENTRE, N_INTERIOR, N_ROW9, N_ROWS78, N_SPINE, PACK,
    SIDE_MINUS_R, SIDE_MINUS_U, SIDE_MINUS_UR, SIDE_PLUS_R, SIDE_PLUS_U, SIDE_PLUS_UR, SYNC_DOWN,
    SYNC_UP, S_CENTRE, S_INTERIOR, S_ROW9, S_ROWS78, S_SPINE,
};
use crate::types::{Biome, HexSides, Side};

/// Passes of the automaton.
pub const PASSES: u8 = 2;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// 2^18 and 2^19.
const POW_18: felt252 = 0x40000;
const POW_19: felt252 = 0x80000;

#[generate_trait]
pub impl HexChunkGenImpl of HexChunkGenTrait {
    /// Generate a hexagonal chunk.
    /// # Arguments
    /// * `word` - The random word
    /// * `biome` - The location's biome
    /// * `sides` - What each side faces
    /// # Returns
    /// * The terrain, 251 bits (`HexChunkTrait::index`): walkable interior tiles, plus the open
    ///   tiles of the ring
    fn generate(word: felt252, biome: Biome, sides: HexSides) -> felt252 {
        // [Compute] 1. Base: three random words per half
        let (a, b, c) = hades_permutation(word, 0, 2);
        let fill_s = Self::fill(a, b, c, biome, S_INTERIOR);
        let (a, b, c) = hades_permutation(word, 2, 2);
        let fill_n = Self::fill(a, b, c, biome, N_INTERIOR);
        // [Compute] Ring: each side copied, closed or drawn
        let (draw, _, _) = hades_permutation(word, 1, 2);
        let draw: u256 = draw.into();
        let mut bits = draw.low;
        let minus_u = Self::long(
            sides.minus_u, COPY_MINUS_U_MASK, COPY_MINUS_U_SHIFT, SIDE_MINUS_U.span(), ref bits,
        );
        let plus_u = Self::long(
            sides.plus_u, COPY_PLUS_U_MASK, COPY_PLUS_U_SHIFT, SIDE_PLUS_U.span(), ref bits,
        );
        let plus_r = Self::short(sides.plus_r, GATHER_PLUS_R.span(), SIDE_PLUS_R.span(), ref bits);
        let minus_r = Self::short(
            sides.minus_r, GATHER_MINUS_R.span(), SIDE_MINUS_R.span(), ref bits,
        );
        let plus_ur = Self::short(
            sides.plus_ur, GATHER_PLUS_UR.span(), SIDE_PLUS_UR.span(), ref bits,
        );
        let minus_ur = Self::short(
            sides.minus_ur, GATHER_MINUS_UR.span(), SIDE_MINUS_UR.span(), ref bits,
        );
        let ring_s = minus_u + plus_r + minus_ur;
        let ring_n = plus_u + minus_r + plus_ur;
        // [Compute] 2. Lines from the openings to the spine; the groups may cross: OR
        let lines_s = Bits::or(
            Bits::or((minus_u * LINE_UP).into(), (plus_r * LINE_LOWER_Q).into()),
            Bits::or((minus_ur * LINE_HIGHER_Q).into(), S_SPINE),
        );
        let lines_n = Bits::or(
            Bits::or((plus_u * LINE_DOWN).into(), (minus_r * LINE_HIGHER_Q).into()),
            Bits::or((plus_ur * LINE_LOWER_Q).into(), N_SPINE),
        );
        // [Compute] The margins of each half: its ring and the other half's in the overlap
        let (margin_s, margin_n) = Self::sync(ring_s, ring_n);
        // [Compute] 3. Smoothing, with the ring as margins
        let (mut grid_s, mut grid_n) = Self::sync(
            Bits::to_felt(Bits::or(fill_s, lines_s)), Bits::to_felt(Bits::or(fill_n, lines_n)),
        );
        let mut pass = PASSES;
        while pass != 0 {
            pass -= 1;
            let next_s = Self::smooth(grid_s.into(), margin_s, S_INTERIOR, biome);
            let next_n = Self::smooth(grid_n.into(), margin_n, N_INTERIOR, biome);
            let (s, n) = Self::sync(Bits::to_felt(next_s), Bits::to_felt(next_n));
            grid_s = s;
            grid_n = n;
        }
        let (grid_s, grid_n) = Self::sync(
            Bits::to_felt(Bits::or(grid_s.into(), lines_s)),
            Bits::to_felt(Bits::or(grid_n.into(), lines_n)),
        );
        // [Return] 4. The component of the centre, and the ring, packed
        let (kept_s, kept_n) = Self::component(grid_s, grid_n);
        Self::pack(kept_s + ring_s, kept_n + ring_n)
    }

    /// The base of one half at the biome's density, cut to its interior.
    #[inline(always)]
    fn fill(a: felt252, b: felt252, c: felt252, biome: Biome, interior: u256) -> u256 {
        let a: u256 = a.into();
        let b: u256 = b.into();
        let c: u256 = c.into();
        let fill = match biome {
            Biome::Meadow => Bits::or(a, Bits::and(b, c)),
            Biome::Forest => Bits::or(a, Bits::and(b, c)),
            Biome::Cave => a,
            Biome::Ruin => Bits::and(a, Bits::or(b, c)),
        };
        Bits::and(fill, interior)
    }

    /// 1 or 2 openings among a side's non-corner tiles (their half bits), 9 random bits used.
    #[inline(always)]
    fn draw(tiles: Span<u8>, ref bits: u128) -> felt252 {
        let count: u128 = tiles.len().into();
        let (rest, two) = DivRem::div_rem(bits, 2);
        let (rest, first) = DivRem::div_rem(rest, 16);
        let (rest, second) = DivRem::div_rem(rest, 16);
        bits = rest;
        let first: u32 = (first % count).try_into().unwrap();
        let second: u32 = (second % count).try_into().unwrap();
        let one = Bits::pow(*tiles[first]);
        if two == 0 || second == first {
            one
        } else {
            one + Bits::pow(*tiles[second])
        }
    }

    /// A long side (row 0 or row 16): drawn, closed, or the neighbour's facing row, one piece.
    #[inline(always)]
    fn long(side: Side, mask: u256, shift: felt252, tiles: Span<u8>, ref bits: u128) -> felt252 {
        match side {
            Side::Open => Self::draw(tiles, ref bits),
            Side::Border => 0,
            Side::Copy(terrain) => Bits::to_felt(Bits::and(terrain.into(), mask)) * shift,
        }
    }

    /// A short side: drawn, closed, or the neighbour's facing tiles gathered one by one (7).
    #[inline(always)]
    fn short(side: Side, gather: Span<(u8, u8)>, tiles: Span<u8>, ref bits: u128) -> felt252 {
        match side {
            Side::Open => Self::draw(tiles, ref bits),
            Side::Border => 0,
            Side::Copy(terrain) => {
                let wide: u256 = terrain.into();
                let mut ring: felt252 = 0;
                for pair in gather {
                    let (from, to) = *pair;
                    if Bits::get(wide, from) {
                        ring += Bits::pow(to);
                    }
                }
                ring
            },
        }
    }

    /// Copy S's rows 7-8 into N and N's row 9 into S: one piece each way.
    #[inline]
    fn sync(s: felt252, n: felt252) -> (felt252, felt252) {
        let wide_s: u256 = s.into();
        let wide_n: u256 = n.into();
        let rows78 = Bits::to_felt(Bits::and(wide_s, S_ROWS78));
        let old78 = Bits::to_felt(Bits::and(wide_n, N_ROWS78));
        let row9 = Bits::to_felt(Bits::and(wide_n, N_ROW9));
        let old9 = Bits::to_felt(Bits::and(wide_s, S_ROW9));
        (s - old9 + row9 * SYNC_UP, n - old78 + rows78 * SYNC_DOWN)
    }

    /// One pass of the automaton on a half: the six neighbour planes are field products of the
    /// grid and its margins (exact: bit 0 of a half is never a tile, and the planes that look
    /// North drop the half's first row, whose targets lie outside it).
    #[inline]
    fn smooth(grid: u256, margin: felt252, interior: u256, biome: Biome) -> u256 {
        let all = Bits::to_felt(grid) + margin;
        let wide: u256 = all.into();
        let (first, _, _) = Bits::bitwise(wide.low, LOW19);
        let dropped = all - first.into();
        // (q - 1, r), (q + 1, r), (q, r - 1), (q + 1, r - 1), (q, r + 1), (q - 1, r + 1)
        let p1: u256 = (all + all).into();
        let p2: u256 = (all * INV_2).into();
        let p3: u256 = (all * POW_19).into();
        let p4: u256 = (all * POW_18).into();
        let p5: u256 = (dropped * INV_19).into();
        let p6: u256 = (dropped * INV_18).into();
        let low = AutomatonTrait::rule(
            grid.low, p1.low, p2.low, p3.low, p4.low, p5.low, p6.low, interior.low, biome,
        );
        let high = AutomatonTrait::rule(
            grid.high, p1.high, p2.high, p3.high, p4.high, p5.high, p6.high, interior.high, biome,
        );
        u256 { low, high }
    }

    /// A frontier and its neighbours on a half: with the pairs `P = f | 2f`, the neighbours on
    /// the next row are `P 2^18` and on the previous row `P 2^-19` (first row dropped), plus
    /// `f / 2`.
    #[inline(always)]
    fn dilate(frontier: felt252) -> u256 {
        let pairs = Bits::or(frontier.into(), (frontier + frontier).into());
        let felt = Bits::to_felt(pairs);
        let (first, _, _) = Bits::bitwise(pairs.low, LOW19);
        let up: u256 = (felt * POW_18).into();
        let down: u256 = ((felt - first.into()) * INV_19).into();
        let half: u256 = (frontier * INV_2).into();
        Bits::or(Bits::or(pairs, up), Bits::or(down, half))
    }

    /// The walkable tiles connected to the centre, a flood on both halves, synced each layer.
    fn component(grid_s: felt252, grid_n: felt252) -> (felt252, felt252) {
        let mut front_s = Bits::pow(S_CENTRE);
        let mut front_n = Bits::pow(N_CENTRE);
        let mut free_s: u256 = (grid_s - front_s).into();
        let mut free_n: u256 = (grid_n - front_n).into();
        loop {
            if front_s == 0 && front_n == 0 {
                break;
            }
            let next_s = Bits::to_felt(Bits::and(Self::dilate(front_s), free_s));
            let next_n = Bits::to_felt(Bits::and(Self::dilate(front_n), free_n));
            let (next_s, next_n) = Self::sync(next_s, next_n);
            free_s = (Bits::to_felt(free_s) - next_s).into();
            free_n = (Bits::to_felt(free_n) - next_n).into();
            front_s = next_s;
            front_n = next_n;
        }
        (grid_s - Bits::to_felt(free_s), grid_n - Bits::to_felt(free_n))
    }

    /// The halves packed into the chunk's 251 bits: rows 0-8 from S, 9-16 from N.
    fn pack(s: felt252, n: felt252) -> felt252 {
        let wide_s: u256 = s.into();
        let wide_n: u256 = n.into();
        let mut dense: felt252 = 0;
        let mut r: u32 = 0;
        for row in PACK.span() {
            let (mask_low, mask_high, shift) = *row;
            let source = if r <= 8 {
                wide_s
            } else {
                wide_n
            };
            let (low, _, _) = Bits::bitwise(source.low, mask_low);
            let (high, _, _) = Bits::bitwise(source.high, mask_high);
            dense += (low.into() + high.into() * TWO_POW_128) * shift;
            r += 1;
        }
        dense
    }
}

// Generation: its steps against tile-by-tile versions, the invariants of whole chunks, the
// rectangle's.
#[cfg(test)]
mod tests {
    use hexx::board::bits::Bits;
    use crate::hexchunk::HexChunkTrait;
    use crate::hexgen::HexChunkGenTrait;
    use crate::rect::RectChunkTrait;
    use crate::tables::{
        DENSE_MINUS_R, DENSE_MINUS_U, DENSE_MINUS_UR, DENSE_PLUS_R, DENSE_PLUS_U, DENSE_PLUS_UR,
        FACING_MINUS_R, FACING_MINUS_U, FACING_MINUS_UR, FACING_PLUS_R, FACING_PLUS_U,
        FACING_PLUS_UR,
    };
    use crate::testing::{count, has, member, random_bits};
    use crate::types::{Biome, HexSides, RectSides, Side};

    // --- Plain helpers on the dense chunk
    // ------------------------------------------------------------

    fn is_ring(q: i32, r: i32) -> bool {
        r == 0 || r == 16 || q == 0 || q == 18 || q + r == 8 || q + r == 26
    }

    fn bit(q: i32, r: i32) -> u8 {
        HexChunkTrait::index(q.try_into().unwrap(), r.try_into().unwrap())
    }

    fn neighbours(q: i32, r: i32) -> Array<(i32, i32)> {
        array![(q + 1, r), (q - 1, r), (q, r + 1), (q, r - 1), (q + 1, r - 1), (q - 1, r + 1)]
    }

    /// The interior and ring masks of the dense chunk.
    fn masks() -> (felt252, felt252) {
        let mut interior: felt252 = 0;
        let mut ring: felt252 = 0;
        let mut r: i32 = 0;
        while r != 17 {
            let mut q: i32 = 0;
            while q != 19 {
                if member(q, r) {
                    if is_ring(q, r) {
                        ring += Bits::pow(bit(q, r));
                    } else {
                        interior += Bits::pow(bit(q, r));
                    }
                }
                q += 1;
            }
            r += 1;
        }
        (interior, ring)
    }

    /// A dense layer split into the two half-boards, tile by tile.
    fn halves(dense: felt252) -> (felt252, felt252) {
        let mut s: felt252 = 0;
        let mut n: felt252 = 0;
        let mut r: i32 = 0;
        while r != 17 {
            let mut q: i32 = 0;
            while q != 19 {
                if member(q, r) && has(dense, bit(q, r)) {
                    if r <= 9 {
                        s += Bits::pow((19 * r + q).try_into().unwrap());
                    }
                    if r >= 7 {
                        n += Bits::pow((19 * (r - 7) + q).try_into().unwrap());
                    }
                }
                q += 1;
            }
            r += 1;
        }
        (s, n)
    }

    /// One pass of the automaton, tile by tile: each interior tile counts its walkable neighbours
    /// (interior and ring).
    fn smooth_plain(grid: felt252, ring: felt252, biome: Biome) -> felt252 {
        let all = grid + ring;
        let mut next: felt252 = 0;
        let mut r: i32 = 0;
        while r != 17 {
            let mut q: i32 = 0;
            while q != 19 {
                if member(q, r) && !is_ring(q, r) {
                    let mut n: u8 = 0;
                    for (nq, nr) in neighbours(q, r) {
                        if has(all, bit(nq, nr)) {
                            n += 1;
                        }
                    }
                    let alive = has(grid, bit(q, r));
                    let (born, survive) = match biome {
                        Biome::Meadow => (4, 3),
                        Biome::Forest => (4, 4),
                        Biome::Cave => (5, 4),
                        Biome::Ruin => (4, 4),
                    };
                    if (alive && n >= survive) || (!alive && n >= born) {
                        next += Bits::pow(bit(q, r));
                    }
                }
                q += 1;
            }
            r += 1;
        }
        next
    }

    /// The tiles of `walkable` reachable from the centre, a plain breadth-first search.
    fn reach_plain(walkable: felt252) -> felt252 {
        let centre = bit(9, 8);
        if !has(walkable, centre) {
            return 0;
        }
        let mut seen: felt252 = Bits::pow(centre);
        let mut queue: Array<(i32, i32)> = array![(9, 8)];
        let mut head: u32 = 0;
        while head != queue.len() {
            let (q, r) = *queue[head];
            head += 1;
            for (nq, nr) in neighbours(q, r) {
                if member(nq, nr) {
                    let b = bit(nq, nr);
                    if has(walkable, b) && !has(seen, b) {
                        seen += Bits::pow(b);
                        queue.append((nq, nr));
                    }
                }
            }
        }
        seen
    }

    // --- The steps against their oracles
    // -------------------------------------------------------------

    #[test]
    #[available_gas(l2_gas: 241540378)] // ceil(1.05 × 230038455 measured)
    fn test_smooth_matches_plain() {
        let (interior, ring_mask) = masks();
        let wide_interior: u256 = interior.into();
        let wide_ring: u256 = ring_mask.into();
        let (interior_s, interior_n) = halves(interior);
        let mut seed: felt252 = 1;
        let biomes = array![Biome::Meadow, Biome::Forest, Biome::Cave, Biome::Ruin];
        for biome in biomes {
            let grid = Bits::to_felt(Bits::and(random_bits(seed, 251).into(), wide_interior));
            let ring = Bits::to_felt(Bits::and(random_bits(seed + 1, 251).into(), wide_ring));
            let expected = smooth_plain(grid, ring, biome);
            let (grid_s, grid_n) = halves(grid);
            let (margin_s, margin_n) = halves(ring);
            let next_s = HexChunkGenTrait::smooth(
                grid_s.into(), margin_s, interior_s.into(), biome,
            );
            let next_n = HexChunkGenTrait::smooth(
                grid_n.into(), margin_n, interior_n.into(), biome,
            );
            let (s, n) = HexChunkGenTrait::sync(Bits::to_felt(next_s), Bits::to_felt(next_n));
            assert!(HexChunkGenTrait::pack(s, n) == expected, "{:?}", biome);
            // The sync leaves both halves equal on the overlap
            assert!(halves(HexChunkGenTrait::pack(s, n)) == (s, n));
            seed += 2;
        }
    }

    #[test]
    #[available_gas(l2_gas: 247652492)] // ceil(1.05 × 235859516 measured)
    fn test_component_matches_plain() {
        let (interior, _) = masks();
        let wide_interior: u256 = interior.into();
        let mut seed: felt252 = 100;
        let mut round: u8 = 0;
        while round != 6 {
            // Dense enough to connect, sparse enough to leave pockets
            let a: u256 = random_bits(seed, 251).into();
            let b: u256 = random_bits(seed + 1, 251).into();
            let centre: u256 = Bits::pow(bit(9, 8)).into();
            let grid = Bits::to_felt(Bits::or(Bits::and(Bits::or(a, b), wide_interior), centre));
            let expected = reach_plain(grid);
            let (s, n) = halves(grid);
            let (kept_s, kept_n) = HexChunkGenTrait::component(s, n);
            assert!(HexChunkGenTrait::pack(kept_s, kept_n) == expected, "round {}", round);
            assert!(count(expected) > 1);
            seed += 2;
            round += 1;
        }
    }

    // --- Whole chunks
    // --------------------------------------------------------------------------------

    fn sides_all(side: Side) -> HexSides {
        HexSides {
            minus_u: side, plus_u: side, plus_r: side, minus_r: side, plus_ur: side, minus_ur: side,
        }
    }

    fn corners_wall(terrain: felt252) {
        for b in array![0_u8, 10, 116, 134, 240, 250] {
            assert!(!has(terrain, b), "corner {}", b);
        }
    }

    fn open_count(terrain: felt252, tiles: Span<u8>) -> u32 {
        let mut n: u32 = 0;
        for b in tiles {
            if has(terrain, *b) {
                n += 1;
            }
        }
        n
    }

    fn check_chunk(terrain: felt252) {
        corners_wall(terrain);
        assert!(has(terrain, bit(9, 8)), "centre");
        assert!(reach_plain(terrain) == terrain, "every walkable tile reachable");
        assert!(terrain != 0);
    }

    fn check_copied(ours: Span<u8>, theirs: Span<u8>, terrain: felt252, neighbour: felt252) {
        let mut i: u32 = 0;
        while i != ours.len() {
            assert!(has(terrain, *ours[i]) == has(neighbour, *theirs[i]), "copied tile {}", i);
            i += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 440409413)] // ceil(1.05 × 419437536 measured)
    fn test_generate_open_border_and_copy() {
        let biomes = array![Biome::Meadow, Biome::Forest, Biome::Cave, Biome::Ruin];
        let mut word: felt252 = 'HEX';
        for biome in biomes {
            // Six sides drawn: 1 or 2 openings each
            let open = HexChunkGenTrait::generate(word, biome, sides_all(Side::Open));
            check_chunk(open);
            assert!(open == HexChunkGenTrait::generate(word, biome, sides_all(Side::Open)));
            for side in array![
                DENSE_MINUS_U.span(), DENSE_PLUS_U.span(), DENSE_PLUS_R.span(),
                DENSE_MINUS_R.span(), DENSE_PLUS_UR.span(), DENSE_MINUS_UR.span(),
            ] {
                let n = open_count(open, side);
                assert!(n == 1 || n == 2, "openings {}", n);
            }
            // Six sides closed
            let closed = HexChunkGenTrait::generate(word + 1, biome, sides_all(Side::Border));
            check_chunk(closed);
            let (_, ring) = masks();
            assert!(Bits::and(closed.into(), ring.into()) == 0);
            // Six sides copied from six generated neighbours: each side equals its neighbour's
            // facing side under the maps of generation.py
            let n1 = HexChunkGenTrait::generate(word + 2, biome, sides_all(Side::Open));
            let n2 = HexChunkGenTrait::generate(word + 3, biome, sides_all(Side::Open));
            let n3 = HexChunkGenTrait::generate(word + 4, biome, sides_all(Side::Open));
            let n4 = HexChunkGenTrait::generate(word + 5, biome, sides_all(Side::Open));
            let n5 = HexChunkGenTrait::generate(word + 6, biome, sides_all(Side::Open));
            let n6 = HexChunkGenTrait::generate(word + 7, biome, sides_all(Side::Open));
            let sides = HexSides {
                minus_u: Side::Copy(n1),
                plus_u: Side::Copy(n2),
                plus_r: Side::Copy(n3),
                minus_r: Side::Copy(n4),
                plus_ur: Side::Copy(n5),
                minus_ur: Side::Copy(n6),
            };
            let copied = HexChunkGenTrait::generate(word + 8, biome, sides);
            check_chunk(copied);
            check_copied(DENSE_MINUS_U.span(), FACING_MINUS_U.span(), copied, n1);
            check_copied(DENSE_PLUS_U.span(), FACING_PLUS_U.span(), copied, n2);
            check_copied(DENSE_PLUS_R.span(), FACING_PLUS_R.span(), copied, n3);
            check_copied(DENSE_MINUS_R.span(), FACING_MINUS_R.span(), copied, n4);
            check_copied(DENSE_PLUS_UR.span(), FACING_PLUS_UR.span(), copied, n5);
            check_copied(DENSE_MINUS_UR.span(), FACING_MINUS_UR.span(), copied, n6);
            word += 16;
        }
    }

    #[test]
    #[available_gas(l2_gas: 105496808)] // ceil(1.05 × 100473150 measured)
    fn test_generate_shares() {
        // Walkable share of the interior over 16 words per biome, in thousandths, beside the
        // rectangle's on the same words (printed for the report; design/18's ranges in SPK-7)
        let (interior, _) = masks();
        let wide_interior: u256 = interior.into();
        let rect_interior: u256 = crate::tables::RECT_INTERIOR.into();
        let biomes = array![Biome::Meadow, Biome::Forest, Biome::Cave, Biome::Ruin];
        let rect_sides = RectSides {
            east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open,
        };
        for biome in biomes {
            let mut hex: u32 = 0;
            let mut rect: u32 = 0;
            let mut i: felt252 = 0;
            while i != 16 {
                let t = HexChunkGenTrait::generate('SHARE' + i, biome, sides_all(Side::Open));
                hex += count(Bits::to_felt(Bits::and(t.into(), wide_interior)));
                let t = RectChunkTrait::generate('SHARE' + i, biome, rect_sides, false);
                rect += count(Bits::to_felt(Bits::and(t.into(), rect_interior)));
                i += 1;
            }
            println!(
                "share {:?}: hexagon {} rectangle {}",
                biome,
                hex * 1000 / (16 * 199),
                rect * 1000 / (16 * 169),
            );
        }
    }

    #[test]
    #[available_gas(l2_gas: 1583920)] // ceil(1.05 × 1508495 measured)
    fn test_rect_generate_deterministic_corners_wall() {
        let sides = RectSides {
            east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open,
        };
        let a = RectChunkTrait::generate('RECT', Biome::Cave, sides, false);
        assert!(a == RectChunkTrait::generate('RECT', Biome::Cave, sides, false));
        for b in array![0_u8, 14, 210, 224] {
            assert!(!has(a, b));
        }
        let b = RectChunkTrait::generate('RECT', Biome::Cave, sides, true);
        assert!(b != 0 && has(b, 112));
    }
}
