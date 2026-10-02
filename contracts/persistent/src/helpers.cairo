//! Pure functions: bitmap, packer, seeder, math (ENG-01 and after).

/// `2^n` for `n` below 16 and the powers `2^(16 k)`: two small tables whose product is any power
/// of a limb (docs/CAIRO.md §3: a table, not a loop).
const LOW: [u128; 16] = [
    0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000,
    0x8000,
];
const HIGH: [u128; 8] = [
    0x1, 0x10000, 0x100000000, 0x1000000000000, 0x10000000000000000, 0x100000000000000000000,
    0x1000000000000000000000000, 0x10000000000000000000000000000,
];

/// Bits of a limb.
#[generate_trait]
pub impl BitImpl of BitTrait {
    /// `2^n`, for `n` below 128.
    #[inline(always)]
    fn pow2(n: u8) -> u128 {
        let (k, r) = DivRem::div_rem(n, 16);
        *LOW.span()[r.into()] * *HIGH.span()[k.into()]
    }

    /// The two limbs of a word a caller sends without `LIVE`, bit 250 kept: `packing::split`
    /// removes it, and so would accept a caller's bit 250 as `LIVE`. `u256` for `split`'s reason:
    /// the cheapest split of a felt on Cairo 2.19 (grimworld_logic::packing).
    #[inline(always)]
    fn limbs(word: felt252) -> (u128, u128) {
        let wide: u256 = word.into();
        (wide.low, wide.high)
    }

    /// Whether bit `n` (below 128) of `limb` is set.
    #[inline(always)]
    fn is_set(limb: u128, n: u8) -> bool {
        let (above, _) = DivRem::div_rem(limb, Self::pow2(n).try_into().unwrap());
        above % 2 == 1
    }
}

// CBT-08a: powers of two and bits, against a plain loop (the oracle, docs/CAIRO.md §2).
#[cfg(test)]
mod tests {
    use grimworld_logic::packing::LIVE;
    use super::BitTrait;

    #[test]
    #[available_gas(l2_gas: 4157360)] // ceil(1.05 × 3959390 measured)
    fn test_pow2_and_bits() {
        let mut expected: u128 = 1;
        for n in 0..128_u8 {
            assert(BitTrait::pow2(n) == expected, 'pow2');
            assert(BitTrait::is_set(expected, n), 'set');
            assert(!BitTrait::is_set(~expected, n), 'clear');
            if n != 127 {
                expected *= 2;
            }
        }
        assert(BitTrait::limbs(LIVE + 5) == (5, 0x4000000000000000000000000000000), 'LIVE kept');
    }
}
