//! `2^(x/40)` in fixed point, for the damage formula of design/04, which multiplies the base
//! damage by `2^((strength − armor) / 40)`. The table is generated once
//! (`contracts/tools/exp2_table.py`, D-140) for the contracts and the client: 241 entries, `x ∈
//! [−160, +80]`, 16 fractional bits, each rounded to nearest. No floating point, no
//! exponentiation at run time, no `u256`.
//!
//! Representation, by measured gas (docs/reports, ENG-02a): a constant `[u32; 241]` read through a
//! span costs about 1270 l2 gas above the bare call, whatever the index; a `match` of 241 arms
//! about 1370; four `u32` lanes per `u128` about 8310 (a division and a remainder per lookup).

use super::exp2_table::EXP2_X40;

/// Lowest `x` of the table; a lower one clamps to it.
pub const X_LOW: i32 = -160;
/// Highest `x` of the table; a higher one clamps to it.
pub const X_HIGH: i32 = 80;
/// The fixed point: 2^16 is 1.0.
pub const SHIFT: u32 = 65536;
/// Number of entries: `X_HIGH − X_LOW + 1`.
pub const LEN: u32 = 241;

pub mod errors {
    pub const OUT_OF_RANGE: felt252 = 'exp2: x out of range';
}

pub trait Exp2 {
    /// `round(2^16 × 2^(x/40))`, with `x` clamped to `[−160, +80]` (D-140: a legal action never
    /// panics, however far apart strength and armor are).
    fn at(x: i32) -> u32;
}

pub impl Exp2Impl of Exp2 {
    #[inline(always)]
    fn at(x: i32) -> u32 {
        // [Compute] Two comparisons and one addition: branch-free is not cheaper.
        let index: u32 = if x < X_LOW {
            0
        } else if x > X_HIGH {
            LEN - 1
        } else {
            (x - X_LOW).try_into().unwrap()
        };
        *EXP2_X40.span().at(index)
    }
}

#[generate_trait]
pub impl Exp2Assert of AssertTrait {
    /// For a caller that must not clamp: `x` is inside the table.
    fn assert_covered(x: i32) {
        assert(X_LOW <= x && x <= X_HIGH, errors::OUT_OF_RANGE);
    }
}
