//! Plain, obviously correct helpers of the oracles.

use core::poseidon::hades_permutation;
use hexx::board::bits::Bits;

/// Whether bit `index` of a bitmap is set.
pub fn has(value: felt252, index: u8) -> bool {
    Bits::get(value.into(), index)
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

/// Whether a local axial tile is in the chunk anchored at (0, 0), from the definition.
pub fn member(q: i32, r: i32) -> bool {
    0 <= r && r <= 16 && 0 <= q && q <= 18 && 8 <= q + r && q + r <= 26
}
