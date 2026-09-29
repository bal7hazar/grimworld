//! The damage formula of design/04: `damage = base × 2^((strength − armor) / 40)`, with
//! `armor = target armor + bonus − penetration`, `2^(x/40)` read from a table for
//! `x ∈ [−160, +80]` (out-of-range values clamp), then the percent modifiers (critical +40,
//! weakness −33) applied with a truncating signed division.
//!
//! Spike choices, where design/04 is silent (see docs/research/SPK-4-parity.md, *Open questions*):
//! the table has 16 fractional bits, rounded to nearest; armor below zero is a panic (u16
//! underflow), not a clamp; a result that does not fit a u16 (or is negative) is a panic.

use crate::table::{POW2_X40, POW2_X40_SHIFT};

/// Lowest and highest `strength − armor` the table covers.
pub const X_LOW: i32 = -160;
pub const X_HIGH: i32 = 80;

/// Damage dealt by one hit.
/// # Arguments
/// * `base` - The base damage of the weapon or skill
/// * `strength` - The attacker's strength (weapon attack or spell)
/// * `armor` - The target's armor
/// * `bonus` - The target's armor bonus against the damage type
/// * `penetration` - The attacker's armor penetration
/// * `modifier` - The sum of percent modifiers (+40 critical, −33 weakness)
/// # Returns
/// * The damage
/// # Panics
/// * If `armor + bonus` overflows or `penetration` exceeds it (u16), if `base` times the factor
///   overflows a u32, if the result is negative or does not fit a u16
pub fn damage(base: u16, strength: u16, armor: u16, bonus: u16, penetration: u16, modifier: i16) -> u16 {
    let effective: u16 = armor + bonus - penetration;
    let x: i32 = strength.into() - effective.into();
    // [Compute] Clamp, then read the table: branch-free is not cheaper for two comparisons.
    let x = if x < X_LOW {
        X_LOW
    } else if x > X_HIGH {
        X_HIGH
    } else {
        x
    };
    let index: u32 = (x - X_LOW).try_into().unwrap();
    let factor: u32 = *POW2_X40.span()[index];
    let raw: u32 = (base.into() * factor) / POW2_X40_SHIFT;
    let raw: i32 = raw.try_into().unwrap();
    let modifier: i32 = modifier.into();
    let total: i32 = raw + raw * modifier / 100;
    total.try_into().unwrap()
}
