//! Generation of a hexagonal chunk: its steps against plain tile-by-tile versions (one pass of the
//! automaton, the component), and the invariants of whole chunks (corners wall, sides closed,
//! drawn or copied as asked, every walkable tile reachable from the centre, determinism). The
//! rectangle (SPK-7's generator on `hexx`): determinism and wall corners, as SPK-7 tested the rest.

use hexx::board::bits::Bits;
use spk14::hexchunk::HexChunkTrait;
use spk14::hexgen::HexChunkGenTrait;
use spk14::rect::RectChunkTrait;
use spk14::tables::{
    DENSE_MINUS_R, DENSE_MINUS_U, DENSE_MINUS_UR, DENSE_PLUS_R, DENSE_PLUS_U, DENSE_PLUS_UR,
    FACING_MINUS_R, FACING_MINUS_U, FACING_MINUS_UR, FACING_PLUS_R, FACING_PLUS_U, FACING_PLUS_UR,
};
use spk14::types::{Biome, HexSides, RectSides, Side};
use super::helpers::{count, has, member, random_bits};

// --- Plain helpers on the dense chunk ------------------------------------------------------------

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

// --- The steps against their oracles -------------------------------------------------------------

#[test]
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
        let next_s = HexChunkGenTrait::smooth(grid_s.into(), margin_s, interior_s.into(), biome);
        let next_n = HexChunkGenTrait::smooth(grid_n.into(), margin_n, interior_n.into(), biome);
        let (s, n) = HexChunkGenTrait::sync(Bits::to_felt(next_s), Bits::to_felt(next_n));
        assert!(HexChunkGenTrait::pack(s, n) == expected, "{:?}", biome);
        // The sync leaves both halves equal on the overlap
        assert!(halves(HexChunkGenTrait::pack(s, n)) == (s, n));
        seed += 2;
    }
}

#[test]
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

// --- Whole chunks --------------------------------------------------------------------------------

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
fn test_generate_open_border_and_copy() {
    let biomes = array![Biome::Meadow, Biome::Forest, Biome::Cave, Biome::Ruin];
    let mut word: felt252 = 'HEX';
    for biome in biomes {
        // Six sides drawn: 1 or 2 openings each
        let open = HexChunkGenTrait::generate(word, biome, sides_all(Side::Open));
        check_chunk(open);
        assert!(open == HexChunkGenTrait::generate(word, biome, sides_all(Side::Open)));
        for side in array![
            DENSE_MINUS_U.span(), DENSE_PLUS_U.span(), DENSE_PLUS_R.span(), DENSE_MINUS_R.span(),
            DENSE_PLUS_UR.span(), DENSE_MINUS_UR.span(),
        ] {
            let n = open_count(open, side);
            assert!(n == 1 || n == 2, "openings {}", n);
        }
        // Six sides closed
        let closed = HexChunkGenTrait::generate(word + 1, biome, sides_all(Side::Border));
        check_chunk(closed);
        let (_, ring) = masks();
        assert!(Bits::and(closed.into(), ring.into()) == 0);
        // Six sides copied from six generated neighbours: each side equals its neighbour's facing
        // side under the maps of generation.py
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
fn test_generate_shares() {
    // Walkable share of the interior over 16 words per biome, in thousandths, beside the
    // rectangle's on the same words (printed for the report; design/18's ranges in SPK-7)
    let (interior, _) = masks();
    let wide_interior: u256 = interior.into();
    let rect_interior: u256 = spk14::tables::RECT_INTERIOR.into();
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
