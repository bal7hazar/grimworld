//! Plain, obviously correct helpers of the oracles: coordinates one tile at a time.

use core::poseidon::hades_permutation;
use origami_hexmap::helpers::bits::Bits;

pub const W: u8 = 15;

/// Whether bit `index` of a bitmap is set.
pub fn has(value: felt252, index: u8) -> bool {
    Bits::get(value.into(), index)
}

/// The neighbours of `(x, y)` on a board of width 15 and height `height`, written from the direction
/// table of the library (odd-r: an odd row's North and South neighbours are at x and x + 1, an even
/// row's at x - 1 and x). `flip`: local row 0 is an odd global row.
pub fn neighbours(x: u8, y: u8, height: u8, flip: bool) -> Array<(u8, u8)> {
    let mut out: Array<(u8, u8)> = array![];
    if x > 0 {
        out.append((x - 1, y));
    }
    if x < W - 1 {
        out.append((x + 1, y));
    }
    let odd = (y % 2 == 1) != flip;
    let (left, right): (i16, i16) = if odd {
        (x.into(), x.into() + 1)
    } else {
        (x.into() - 1, x.into())
    };
    for dy in array![-1_i16, 1].span() {
        let ny: i16 = y.into() + *dy;
        if ny >= 0 && ny < height.into() {
            for nx in array![left, right].span() {
                if *nx >= 0 && *nx < W.into() {
                    out.append(((*nx).try_into().unwrap(), ny.try_into().unwrap()));
                }
            }
        }
    }
    out
}

/// Pseudo-random bits below 2^size.
pub fn random_bits(seed: felt252, size: u8) -> felt252 {
    let (a, _, _) = hades_permutation(seed, 'RANDOM', 2);
    let wide: u256 = a.into();
    let mask: u256 = (Bits::pow(size) - 1).into();
    Bits::to_felt(wide & mask)
}

/// Number of set bits.
pub fn count(value: felt252) -> u32 {
    Bits::popcount(value.into()).into()
}
