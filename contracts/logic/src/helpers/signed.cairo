//! Signed fields in two's complement (design/19 §2.1, §7.2, X-3): an `i8` in 8 bits, an `i16` in
//! 16. A packer adds the bits at the field's offset; an unpacker reads them back. Scoped in a trait
//! (docs/CAIRO.md §7): no model owns the encoding, every signed field of the game uses it.

const P8: i32 = 0x100;
const P16: i32 = 0x10000;

#[generate_trait]
pub impl SignedImpl of SignedTrait {
    /// The 8 bits of an `i8`: `v` if `v ≥ 0`, else `2^8 + v`.
    #[inline(always)]
    fn bits8(value: i8) -> u128 {
        let wide: i32 = value.into();
        if wide < 0 {
            (wide + P8).try_into().unwrap()
        } else {
            wide.try_into().unwrap()
        }
    }

    /// The `i8` of 8 bits (`bits` below 2^8).
    #[inline(always)]
    fn from8(bits: u128) -> i8 {
        let wide: i32 = bits.try_into().unwrap();
        if wide >= 0x80 {
            (wide - P8).try_into().unwrap()
        } else {
            wide.try_into().unwrap()
        }
    }

    /// The 16 bits of an `i16`: `v` if `v ≥ 0`, else `2^16 + v`.
    #[inline(always)]
    fn bits16(value: i16) -> u128 {
        let wide: i32 = value.into();
        if wide < 0 {
            (wide + P16).try_into().unwrap()
        } else {
            wide.try_into().unwrap()
        }
    }

    /// The `i16` of 16 bits (`bits` below 2^16).
    #[inline(always)]
    fn from16(bits: u128) -> i16 {
        let wide: i32 = bits.try_into().unwrap();
        if wide >= 0x8000 {
            (wide - P16).try_into().unwrap()
        } else {
            wide.try_into().unwrap()
        }
    }
}

/// Two's complement at both ends (CBT-01).
#[cfg(test)]
mod tests {
    use super::SignedTrait;

    // Two's complement at both ends.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_signed_ends() {
        assert(SignedTrait::bits8(-128) == 0x80 && SignedTrait::bits8(127) == 0x7F, 'i8 bits');
        assert(SignedTrait::from8(0x80) == -128 && SignedTrait::from8(0xFF) == -1, 'i8 back');
        assert(SignedTrait::bits16(-32768) == 0x8000 && SignedTrait::bits16(-1) == 0xFFFF, 'i16');
        assert(
            SignedTrait::from16(0x7FFF) == 32767 && SignedTrait::from16(0x8000) == -32768, 'back',
        );
    }
}
