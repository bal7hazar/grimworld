//! N-1, N-2: the generator's automaton and flood against plain versions on both row parities, the
//! seams (copied edges, corners, openings, border), connectivity, determinism, and the walkable
//! share of each biome (design/18).

use core::dict::{Felt252Dict, Felt252DictTrait};
use origami_hexmap::helpers::bits::Bits;
use spk7::chunk::{Biome, Side, Sides, generate_chunk, keep_component, smooth};
use spk7::tables::{CHUNK_EVEN, CHUNK_INTERIOR, COL_EAST, COL_WEST, ROW_NORTH, ROW_SOUTH};
use super::helpers::{W, count, has, neighbours, random_bits};

const BIOMES: [Biome; 4] = [Biome::Meadow, Biome::Forest, Biome::Cave, Biome::Ruin];

fn thresholds(biome: Biome) -> (u8, u8) {
    // (born, survive)
    match biome {
        Biome::Meadow => (4, 3),
        Biome::Forest => (4, 4),
        Biome::Cave => (5, 4),
        Biome::Ruin => (4, 4),
    }
}

fn even(odd: bool) -> u256 {
    (*CHUNK_EVEN.span()[if odd {
        1
    } else {
        0
    }]).into()
}

/// The automaton one tile at a time.
fn smooth_plain(grid: felt252, ring: felt252, odd: bool, biome: Biome) -> felt252 {
    let (born, survive) = thresholds(biome);
    let all = grid + ring;
    let mut next: felt252 = 0;
    let mut y: u8 = 1;
    while y != 14 {
        let mut x: u8 = 1;
        while x != 14 {
            let mut n: u8 = 0;
            for (nx, ny) in neighbours(x, y, 15, odd) {
                if has(all, ny * W + nx) {
                    n += 1;
                }
            }
            let index = y * W + x;
            let alive = has(grid, index);
            if (alive && n >= survive) || (!alive && n >= born) {
                next += Bits::pow(index);
            }
            x += 1;
        }
        y += 1;
    }
    next
}

/// Breadth first from `from` over `open`, one tile at a time: the tiles reached.
fn reach_plain(open: felt252, from: u8, odd: bool) -> felt252 {
    let mut seen: Felt252Dict<bool> = Default::default();
    seen.insert(from.into(), true);
    let mut queue: Array<u8> = array![from];
    let mut reached = Bits::pow(from);
    while let Some(tile) = queue.pop_front() {
        for (nx, ny) in neighbours(tile % W, tile / W, 15, odd) {
            let next = ny * W + nx;
            if has(open, next) && !seen.get(next.into()) {
                seen.insert(next.into(), true);
                reached += Bits::pow(next);
                queue.append(next);
            }
        }
    }
    reached
}

fn cut(value: felt252, mask: felt252) -> felt252 {
    let a: u256 = value.into();
    let b: u256 = mask.into();
    Bits::to_felt(a & b)
}

#[test]
#[available_gas(l2_gas: 694647293)] // ceil(1.05 × 661568850 measured)
fn test_smooth_matches_oracle_both_parities() {
    let mut seed: felt252 = 1;
    while seed != 5 {
        let grid = cut(random_bits(seed, 225), CHUNK_INTERIOR);
        // A ring with tiles on every side, corners excluded
        let ring = cut(random_bits(seed + 100, 225), COL_EAST + COL_WEST + ROW_SOUTH + ROW_NORTH);
        for biome in BIOMES.span() {
            for odd in array![false, true] {
                let next = smooth(grid.into(), ring, even(odd), *biome);
                let expected = smooth_plain(grid, ring, odd, *biome);
                assert!(Bits::to_felt(next) == expected, "seed {} odd {}", seed, odd);
            }
        }
        seed += 1;
    }
}

#[test]
#[available_gas(l2_gas: 80415275)] // ceil(1.05 × 76585976 measured)
fn test_keep_component_matches_oracle_both_parities() {
    let mut seed: felt252 = 1;
    while seed != 7 {
        let grid = cut(random_bits(seed, 225), CHUNK_INTERIOR);
        let grid = grid - cut(grid, Bits::pow(112)) + Bits::pow(112);
        for odd in array![false, true] {
            let got = keep_component(grid.into(), even(odd));
            assert!(got == reach_plain(grid, 112, odd), "seed {} odd {}", seed, odd);
        }
        seed += 1;
    }
}

/// Ring tiles of a side of a terrain.
fn edge(terrain: felt252, mask: felt252) -> felt252 {
    cut(terrain, mask)
}

/// Invariants of a generated chunk, whatever its sides.
fn check_chunk(terrain: felt252, odd: bool) {
    // [Check] Corners are wall
    for corner in array![0_u8, 14, 210, 224] {
        assert!(!has(terrain, corner), "corner {}", corner);
    }
    assert!(terrain == cut(terrain, Bits::pow(225) - 1));
    // [Check] Every walkable tile, ring included, is reachable from the centre
    assert!(has(terrain, 112));
    assert!(reach_plain(terrain, 112, odd) == terrain, "not connected");
}

fn opened(value: felt252) -> u32 {
    count(value)
}

#[test]
#[available_gas(l2_gas: 639727310)] // ceil(1.05 × 609264104 measured)
fn test_generate_open_border_and_copy() {
    let open = Sides { east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open };
    for biome in BIOMES.span() {
        for odd in array![false, true] {
            let a = generate_chunk('A', *biome, open, odd);
            check_chunk(a, odd);
            // [Check] Every drawn side has 1 or 2 openings
            for mask in array![COL_EAST, COL_WEST, ROW_SOUTH, ROW_NORTH] {
                let n = opened(edge(a, mask));
                assert!(n == 1 || n == 2, "openings {}", n);
            }
            // [Check] Border sides are closed
            let closed = Sides {
                east: Side::Border, west: Side::Open, south: Side::Border, north: Side::Open,
            };
            let b = generate_chunk('B', *biome, closed, odd);
            check_chunk(b, odd);
            assert!(edge(b, COL_EAST) == 0 && edge(b, ROW_SOUTH) == 0);
            // [Check] Copied sides: the chunk West of `a` copies a's West edge onto its East edge
            let west = generate_chunk(
                'C',
                *biome,
                Sides {
                    east: Side::Copy(a), west: Side::Open, south: Side::Border, north: Side::Open,
                },
                odd,
            );
            check_chunk(west, odd);
            assert!(edge(west, COL_EAST) * Bits::pow(14) == edge(a, COL_WEST));
            // [Check] The chunk North of `a` (the other parity) copies a's North edge
            let north = generate_chunk(
                'D',
                *biome,
                Sides {
                    east: Side::Open, west: Side::Open, south: Side::Copy(a), north: Side::Open,
                },
                !odd,
            );
            check_chunk(north, !odd);
            assert!(edge(north, ROW_SOUTH) * Bits::pow(210) == edge(a, ROW_NORTH));
            // [Check] East and South copies, the other way
            let other = generate_chunk(
                'E',
                *biome,
                Sides {
                    east: Side::Open,
                    west: Side::Copy(west),
                    south: Side::Open,
                    north: Side::Copy(north),
                },
                odd,
            );
            check_chunk(other, odd);
            assert!(edge(other, COL_WEST) == edge(west, COL_EAST) * Bits::pow(14));
            assert!(edge(other, ROW_NORTH) == edge(north, ROW_SOUTH) * Bits::pow(210));
            // [Check] Deterministic, and the word matters
            assert!(generate_chunk('A', *biome, open, odd) == a);
            assert!(generate_chunk('Z', *biome, open, odd) != a);
        }
    }
}

/// Walkable share of the interior over `n` words, in thousandths.
fn share(biome: Biome, n: u32) -> u32 {
    let open = Sides { east: Side::Open, west: Side::Open, south: Side::Open, north: Side::Open };
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    while i != n {
        let terrain = generate_chunk(i.into() + 'SHARE', biome, open, i % 2 == 1);
        total += count(cut(terrain, CHUNK_INTERIOR));
        i += 1;
    }
    total * 1000 / (169 * n)
}

#[test]
#[available_gas(l2_gas: 60883770)] // ceil(1.05 × 57984542 measured)
fn test_generate_biome_shares() {
    // design/18 Biomes: meadow 80-90 %, forest 60-70 %, cave 45-55 %, ruin 40-50 %, on average
    let meadow = share(Biome::Meadow, 32);
    let forest = share(Biome::Forest, 32);
    let cave = share(Biome::Cave, 32);
    let ruin = share(Biome::Ruin, 32);
    println!(
        "shares (thousandths): meadow {} forest {} cave {} ruin {}", meadow, forest, cave, ruin,
    );
    assert!(meadow >= 800 && meadow <= 900, "meadow {}", meadow);
    assert!(forest >= 600 && forest <= 700, "forest {}", forest);
    assert!(cave >= 450 && cave <= 550, "cave {}", cave);
    assert!(ruin >= 400 && ruin <= 500, "ruin {}", ruin);
}
