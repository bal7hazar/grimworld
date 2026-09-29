// ENG-02a: the fixed-point table of 2^(x/40) (design/04 *Damage formula*, D-140).
//
// `expected` is not read from the generator's output: it was computed with another method,
// `round_half_even(Decimal(2) ** (Decimal(x) / 40) × 65536)` at 80 digits, and equals the
// generator's table entry for entry (the script that produced it asserted it).
use grimworld_logic::helpers::exp2::{Exp2, Exp2Assert, LEN, SHIFT, X_HIGH, X_LOW};

fn expected() -> Array<u32> {
    array![
        4096, 4168, 4240, 4315, 4390, 4467, 4545, 4624, 4705, 4787, 4871, 4956, 5043, 5131, 5221,
        5312, 5405, 5499, 5595, 5693, 5793, 5894, 5997, 6102, 6208, 6317, 6427, 6540, 6654, 6770,
        6889, 7009, 7132, 7256, 7383, 7512, 7643, 7777, 7913, 8051, 8192, 8335, 8481, 8629, 8780,
        8933, 9090, 9248, 9410, 9575, 9742, 9912, 10086, 10262, 10441, 10624, 10809, 10998, 11191,
        11386, 11585, 11788, 11994, 12203, 12417, 12634, 12855, 13079, 13308, 13541, 13777, 14018,
        14263, 14512, 14766, 15024, 15287, 15554, 15826, 16103, 16384, 16670, 16962, 17258, 17560,
        17867, 18179, 18497, 18820, 19149, 19484, 19825, 20171, 20524, 20882, 21247, 21619, 21997,
        22381, 22772, 23170, 23575, 23988, 24407, 24834, 25268, 25709, 26159, 26616, 27081, 27554,
        28036, 28526, 29025, 29532, 30048, 30574, 31108, 31652, 32205, 32768, 33341, 33924, 34517,
        35120, 35734, 36358, 36994, 37641, 38298, 38968, 39649, 40342, 41047, 41765, 42495, 43238,
        43993, 44762, 45545, 46341, 47151, 47975, 48814, 49667, 50535, 51419, 52317, 53232, 54162,
        55109, 56072, 57052, 58050, 59064, 60097, 61147, 62216, 63304, 64410, 65536, 66682, 67847,
        69033, 70240, 71468, 72717, 73988, 75281, 76597, 77936, 79298, 80684, 82095, 83530, 84990,
        86475, 87987, 89525, 91090, 92682, 94302, 95950, 97628, 99334, 101070, 102837, 104635,
        106464, 108324, 110218, 112145, 114105, 116099, 118129, 120194, 122295, 124432, 126607,
        128820, 131072, 133363, 135694, 138066, 140479, 142935, 145433, 147976, 150562, 153194,
        155872, 158596, 161369, 164189, 167059, 169979, 172951, 175974, 179050, 182179, 185364,
        188604, 191901, 195255, 198668, 202141, 205674, 209269, 212927, 216649, 220436, 224289,
        228210, 232199, 236257, 240387, 244589, 248864, 253214, 257641, 262144,
    ]
}

// Every x of the table, and 40 beyond each end (the clamp), against the independent values.
#[test]
#[available_gas(l2_gas: 3046890)] // ceil(1.05 × 2901800 measured)
fn test_every_entry_and_clamp() {
    let expected = expected();
    assert(expected.len() == LEN, 'expected length');
    let mut x: i32 = -200;
    loop {
        if x > 120 {
            break;
        }
        let inside = if x < X_LOW {
            X_LOW
        } else if x > X_HIGH {
            X_HIGH
        } else {
            x
        };
        let index: u32 = (inside - X_LOW).try_into().unwrap();
        assert(Exp2::at(x) == *expected.at(index), 'exp2 entry');
        x += 1;
    }
}

// The octaves are exact: 2^k at x = 40k, for k from -4 to +2.
#[test]
#[available_gas(l2_gas: 25158)] // ceil(1.05 × 23960 measured)
fn test_octaves_exact() {
    assert(Exp2::at(-160) == SHIFT / 16, '2^-4');
    assert(Exp2::at(-120) == SHIFT / 8, '2^-3');
    assert(Exp2::at(-80) == SHIFT / 4, '2^-2');
    assert(Exp2::at(-40) == SHIFT / 2, '2^-1');
    assert(Exp2::at(0) == SHIFT, '2^0');
    assert(Exp2::at(40) == SHIFT * 2, '2^1');
    assert(Exp2::at(80) == SHIFT * 4, '2^2');
}

// Out of range clamps, at both ends, however far.
#[test]
#[available_gas(l2_gas: 21893)] // ceil(1.05 × 20850 measured)
fn test_clamp_ends() {
    assert(Exp2::at(-161) == Exp2::at(-160), 'below clamps');
    assert(Exp2::at(-65535) == 4096, 'far below clamps');
    assert(Exp2::at(81) == Exp2::at(80), 'above clamps');
    assert(Exp2::at(65535) == 262144, 'far above clamps');
}

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_assert_covered() {
    Exp2Assert::assert_covered(-160);
    Exp2Assert::assert_covered(0);
    Exp2Assert::assert_covered(80);
}

#[test]
#[should_panic(expected: 'exp2: x out of range')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_assert_covered_above_refused() {
    Exp2Assert::assert_covered(81);
}

#[test]
#[should_panic(expected: 'exp2: x out of range')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_assert_covered_below_refused() {
    Exp2Assert::assert_covered(-161);
}

// Benchmark: one lookup, the way the damage formula calls it (a computed x, not a literal).
#[inline(never)]
fn opaque(x: i32) -> i32 {
    x
}

#[test]
#[available_gas(l2_gas: 20118)] // ceil(1.05 × 19160 measured)
fn test_bench_lookup() {
    let x: i32 = opaque(-37);
    assert(Exp2::at(x) == 34517, 'lookup');
}
