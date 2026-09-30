//! Gas of a chunk's generation with margins, hexagon against rectangle (SPK-7's generator on
//! `hexx`), per biome, with every side drawn (`open`: SPK-7's worst case) and every side copied
//! from a generated neighbour (`copy`). Each figure is a test that generates twice less one that
//! generates once, the second on another word; the inputs (words, neighbours) come from one
//! opaque call, so that the difference holds the second generation only (N-3's method).

use spk14::hexgen::HexChunkGenTrait;
use spk14::rect::RectChunkTrait;
use spk14::types::{Biome, HexSides, RectSides, Side};

#[derive(Copy, Drop)]
struct Bench {
    first: felt252,
    second: felt252,
    hex_open: HexSides,
    hex_copy: HexSides,
    rect_open: RectSides,
    rect_copy: RectSides,
}

#[generate_trait]
impl Inputs of InputsTrait {
    #[inline(never)]
    fn get() -> Bench {
        let open = Side::Open;
        let hex_open = HexSides {
            minus_u: open, plus_u: open, plus_r: open, minus_r: open, plus_ur: open, minus_ur: open,
        };
        let rect_open = RectSides { east: open, west: open, south: open, north: open };
        let n = |word: felt252| Side::Copy(HexChunkGenTrait::generate(word, Biome::Cave, hex_open));
        let hex_copy = HexSides {
            minus_u: n('N1'),
            plus_u: n('N2'),
            plus_r: n('N3'),
            minus_r: n('N4'),
            plus_ur: n('N5'),
            minus_ur: n('N6'),
        };
        let m = |
            word: felt252,
        | Side::Copy(RectChunkTrait::generate(word, Biome::Cave, rect_open, false));
        let rect_copy = RectSides { east: m('M1'), west: m('M2'), south: m('M3'), north: m('M4') };
        Bench { first: 'FIRST', second: 'SECOND', hex_open, hex_copy, rect_open, rect_copy }
    }
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9186477)] // ceil(1.05 × 8749025 measured)
fn bench_generate_hex_meadow_open_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Meadow, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10227647)] // ceil(1.05 × 9740616 measured)
fn bench_generate_hex_meadow_open_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Meadow, bench.hex_open) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Meadow, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9352110)] // ceil(1.05 × 8906771 measured)
fn bench_generate_hex_meadow_copy_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Meadow, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10555942)] // ceil(1.05 × 10053278 measured)
fn bench_generate_hex_meadow_copy_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Meadow, bench.hex_copy) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Meadow, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9156913)] // ceil(1.05 × 8720869 measured)
fn bench_generate_hex_forest_open_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Forest, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10173497)] // ceil(1.05 × 9689044 measured)
fn bench_generate_hex_forest_open_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Forest, bench.hex_open) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Forest, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9326694)] // ceil(1.05 × 8882565 measured)
fn bench_generate_hex_forest_copy_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Forest, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10505110)] // ceil(1.05 × 10004866 measured)
fn bench_generate_hex_forest_copy_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Forest, bench.hex_copy) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Forest, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9176708)] // ceil(1.05 × 8739721 measured)
fn bench_generate_hex_cave_open_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Cave, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10262005)] // ceil(1.05 × 9773338 measured)
fn bench_generate_hex_cave_open_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Cave, bench.hex_open) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Cave, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9346488)] // ceil(1.05 × 8901417 measured)
fn bench_generate_hex_cave_copy_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Cave, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10544699)] // ceil(1.05 × 10042570 measured)
fn bench_generate_hex_cave_copy_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Cave, bench.hex_copy) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Cave, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9204782)] // ceil(1.05 × 8766459 measured)
fn bench_generate_hex_ruin_open_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Ruin, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10220316)] // ceil(1.05 × 9733634 measured)
fn bench_generate_hex_ruin_open_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Ruin, bench.hex_open) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Ruin, bench.hex_open) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9374353)] // ceil(1.05 × 8927955 measured)
fn bench_generate_hex_ruin_copy_once() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Ruin, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 10551719)] // ceil(1.05 × 10049256 measured)
fn bench_generate_hex_ruin_copy_twice() {
    let bench = Inputs::get();
    assert!(HexChunkGenTrait::generate(bench.first, Biome::Ruin, bench.hex_copy) != 0);
    assert!(HexChunkGenTrait::generate(bench.second, Biome::Ruin, bench.hex_copy) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8608740)] // ceil(1.05 × 8198800 measured)
fn bench_generate_rect_meadow_open_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Meadow, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9065633)] // ceil(1.05 × 8633936 measured)
fn bench_generate_rect_meadow_open_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Meadow, bench.rect_open, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Meadow, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8579765)] // ceil(1.05 × 8171204 measured)
fn bench_generate_rect_meadow_copy_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Meadow, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9010727)] // ceil(1.05 × 8581644 measured)
fn bench_generate_rect_meadow_copy_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Meadow, bench.rect_copy, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Meadow, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8593129)] // ceil(1.05 × 8183932 measured)
fn bench_generate_rect_forest_open_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Forest, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9034410)] // ceil(1.05 × 8604200 measured)
fn bench_generate_rect_forest_open_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Forest, bench.rect_open, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Forest, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8564153)] // ceil(1.05 × 8156336 measured)
fn bench_generate_rect_forest_copy_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Forest, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8979504)] // ceil(1.05 × 8551908 measured)
fn bench_generate_rect_forest_copy_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Forest, bench.rect_copy, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Forest, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8603026)] // ceil(1.05 × 8193358 measured)
fn bench_generate_rect_cave_open_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Cave, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9060841)] // ceil(1.05 × 8629372 measured)
fn bench_generate_rect_cave_open_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Cave, bench.rect_open, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Cave, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8574051)] // ceil(1.05 × 8165762 measured)
fn bench_generate_rect_cave_copy_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Cave, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9025555)] // ceil(1.05 × 8595766 measured)
fn bench_generate_rect_cave_copy_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Cave, bench.rect_copy, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Cave, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8618860)] // ceil(1.05 × 8208438 measured)
fn bench_generate_rect_ruin_open_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Ruin, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9085873)] // ceil(1.05 × 8653212 measured)
fn bench_generate_rect_ruin_open_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Ruin, bench.rect_open, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Ruin, bench.rect_open, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 8566946)] // ceil(1.05 × 8158996 measured)
fn bench_generate_rect_ruin_copy_once() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Ruin, bench.rect_copy, false) != 0);
}

#[test]
#[inline(never)]
#[available_gas(l2_gas: 9008028)] // ceil(1.05 × 8579074 measured)
fn bench_generate_rect_ruin_copy_twice() {
    let bench = Inputs::get();
    assert!(RectChunkTrait::generate(bench.first, Biome::Ruin, bench.rect_copy, false) != 0);
    assert!(RectChunkTrait::generate(bench.second, Biome::Ruin, bench.rect_copy, false) != 0);
}
