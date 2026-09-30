//! Gas of the window's assembly, hexagon against rectangle, on the basis of the library's N-3
//! benchmark (`hexx` 93639f2c17e3, `src/tests/bench_assembly.cairo`): two layers, the ring, a
//! `HexMap`; each figure is a test that calls twice less one that calls once, the second call on
//! the other layer's inputs, the inputs from one opaque call (`Inputs::get`).
//!
//! Rectangle: `AssemblyTrait::window` of the library, its worst case (4 chunks, `ox = oy = 7`,
//! odd chunk row), the library's own inputs. Hexagon: `HexWindowTrait::window` on the class with
//! the most pieces (origin tile bit 25: 32 runs over 4 chunks) and on a class with the most
//! chunks (bit 185: 28 runs over 6 chunks), the chunks not overlapped passed as `None`.

use hexx::board::assembly::{AssemblyTrait, Origin};
use spk14::pieces::{PIECES_185, PIECES_25};
use spk14::window::{HexOrigin, HexWindowTableTrait, HexWindowTrait};

const T0: felt252 = 0x5a3c1f0e7d2b4968a1c3e5f7092b4d6f8a1c3e5f7092b4d6f8a1c3e5f7092b4;
const T1: felt252 = 0x2f7e4d1c9b8a7f6e5d4c3b2a19087f6e5d4c3b2a19087f6e5d4c3b2a1908;
const T2: felt252 = 0x6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a09f8;
const T3: felt252 = 0x13579bdf02468ace13579bdf02468ace13579bdf02468ace13579bdf02468a;
const T4: felt252 = 0x7edcba9876543210fedcba9876543210fedcba9876543210fedcba98765432;
const T5: felt252 = 0x0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1;
const O0: felt252 = 0x1111111111111111111111111111111111111111111111111111111111111;
const O1: felt252 = 0x2222222222222222222222222222222222222222222222222222222222222;
const O2: felt252 = 0x4444444444444444444444444444444444444444444444444444444444444;
const O3: felt252 = 0x0888888888888888888888888888888888888888888888888888888888888;
const O4: felt252 = 0x3333333333333333333333333333333333333333333333333333333333333;
const O5: felt252 = 0x5555555555555555555555555555555555555555555555555555555555555;

#[derive(Copy, Drop)]
struct Bench {
    terrain: [Option<felt252>; 4],
    occupied: [Option<felt252>; 4],
    origin: Origin,
    hex_terrain: [Option<felt252>; 12],
    hex_occupied: [Option<felt252>; 12],
    hex_origin: HexOrigin,
    six_terrain: [Option<felt252>; 12],
    six_occupied: [Option<felt252>; 12],
    six_origin: HexOrigin,
    adventurer: (u8, u8),
    other: (u8, u8),
}

#[generate_trait]
impl Inputs of InputsTrait {
    #[inline(never)]
    fn get() -> Bench {
        Bench {
            terrain: [Some(T0), Some(T1), Some(T2), Some(T3)],
            occupied: [Some(O0), Some(O1), Some(O2), Some(O3)],
            origin: Origin { cx: 3, cy: 5, ox: 7, oy: 7 },
            // Bit 25 is tile (8, 2): slots 1, 2, 5, 6
            hex_terrain: [
                None, Some(T0), Some(T1), None, None, Some(T2), Some(T3), None, None, None, None,
                None,
            ],
            hex_occupied: [
                None, Some(O0), Some(O1), None, None, Some(O2), Some(O3), None, None, None, None,
                None,
            ],
            hex_origin: HexOrigin { a: 4, b: 3, q: 8, r: 2 },
            // Bit 185 is tile (15, 11): slots 1, 5, 6, 7, 10, 11
            six_terrain: [
                None, Some(T0), None, None, None, Some(T1), Some(T2), Some(T3), None, None,
                Some(T4), Some(T5),
            ],
            six_occupied: [
                None, Some(O0), None, None, None, Some(O1), Some(O2), Some(O3), None, None,
                Some(O4), Some(O5),
            ],
            six_origin: HexOrigin { a: 5, b: 3, q: 15, r: 11 },
            adventurer: (60, 90),
            other: (61, 89),
        }
    }
}

// Rectangle: the library's N-3, re-measured in this package

#[test]
#[inline(never)]
#[available_gas(l2_gas: 99188)] // ceil(1.05 × 94464 measured)
fn bench_rect_window_once() {
    let bench = Inputs::get();
    let (map, occupied) = AssemblyTrait::window(bench.terrain, bench.occupied, @bench.origin, 0);
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 166633)] // ceil(1.05 × 158698 measured)
fn bench_rect_window_twice() {
    let bench = Inputs::get();
    let (map, occupied) = AssemblyTrait::window(bench.terrain, bench.occupied, @bench.origin, 0);
    assert!(map.grid != 0 && occupied != 0);
    let (map, occupied) = AssemblyTrait::window(bench.occupied, bench.terrain, @bench.origin, 1);
    assert!(map.grid != 0 && occupied != 0);
}

// Hexagon: the class with the most pieces

#[test]
#[inline(never)]
#[available_gas(l2_gas: 946407)] // ceil(1.05 × 901340 measured)
fn bench_hex_window_once() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTrait::window(
        bench.hex_terrain, bench.hex_occupied, @bench.hex_origin, 0,
    );
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 1866533)] // ceil(1.05 × 1777650 measured)
fn bench_hex_window_twice() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTrait::window(
        bench.hex_terrain, bench.hex_occupied, @bench.hex_origin, 0,
    );
    assert!(map.grid != 0 && occupied != 0);
    let (map, occupied) = HexWindowTrait::window(
        bench.hex_occupied, bench.hex_terrain, @bench.hex_origin, 1,
    );
    assert!(map.grid != 0 && occupied != 0);
}

// Hexagon: a class with the most chunks

#[test]
#[inline(never)]
#[available_gas(l2_gas: 865392)] // ceil(1.05 × 824182 measured)
fn bench_hex_window_six_once() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTrait::window(
        bench.six_terrain, bench.six_occupied, @bench.six_origin, 0,
    );
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 1704501)] // ceil(1.05 × 1623334 measured)
fn bench_hex_window_six_twice() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTrait::window(
        bench.six_terrain, bench.six_occupied, @bench.six_origin, 0,
    );
    assert!(map.grid != 0 && occupied != 0);
    let (map, occupied) = HexWindowTrait::window(
        bench.six_occupied, bench.six_terrain, @bench.six_origin, 1,
    );
    assert!(map.grid != 0 && occupied != 0);
}

// Hexagon, table-driven: every piece precomputed per class

#[test]
#[inline(never)]
#[available_gas(l2_gas: 360858)] // ceil(1.05 × 343674 measured)
fn bench_table_window_once() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTableTrait::window(
        bench.hex_terrain, bench.hex_occupied, PIECES_25.span(), 0,
    );
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 694804)] // ceil(1.05 × 661718 measured)
fn bench_table_window_twice() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTableTrait::window(
        bench.hex_terrain, bench.hex_occupied, PIECES_25.span(), 0,
    );
    assert!(map.grid != 0 && occupied != 0);
    let (map, occupied) = HexWindowTableTrait::window(
        bench.hex_occupied, bench.hex_terrain, PIECES_25.span(), 1,
    );
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 331286)] // ceil(1.05 × 315510 measured)
fn bench_table_window_six_once() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTableTrait::window(
        bench.six_terrain, bench.six_occupied, PIECES_185.span(), 0,
    );
    assert!(map.grid != 0 && occupied != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 635660)] // ceil(1.05 × 605390 measured)
fn bench_table_window_six_twice() {
    let bench = Inputs::get();
    let (map, occupied) = HexWindowTableTrait::window(
        bench.six_terrain, bench.six_occupied, PIECES_185.span(), 0,
    );
    assert!(map.grid != 0 && occupied != 0);
    let (map, occupied) = HexWindowTableTrait::window(
        bench.six_occupied, bench.six_terrain, PIECES_185.span(), 1,
    );
    assert!(map.grid != 0 && occupied != 0);
}

// The origin: a tile to its chunk

#[test]
#[inline(never)]
#[available_gas(l2_gas: 34829)] // ceil(1.05 × 33170 measured)
fn bench_rect_origin_once() {
    let bench = Inputs::get();
    let (x, y) = bench.adventurer;
    assert!(AssemblyTrait::origin(x, y).cx == 3);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 38745)] // ceil(1.05 × 36900 measured)
fn bench_rect_origin_twice() {
    let bench = Inputs::get();
    let (x, y) = bench.adventurer;
    assert!(AssemblyTrait::origin(x, y).cx == 3);
    let (x, y) = bench.other;
    assert!(AssemblyTrait::origin(x, y).cx == 3);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 90668)] // ceil(1.05 × 86350 measured)
fn bench_hex_origin_once() {
    let bench = Inputs::get();
    let (x, y) = bench.adventurer;
    assert!(HexWindowTrait::origin(x, y).r < 17);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 150423)] // ceil(1.05 × 143260 measured)
fn bench_hex_origin_twice() {
    let bench = Inputs::get();
    let (x, y) = bench.adventurer;
    assert!(HexWindowTrait::origin(x, y).r < 17);
    let (x, y) = bench.other;
    assert!(HexWindowTrait::origin(x, y).r < 17);
}
