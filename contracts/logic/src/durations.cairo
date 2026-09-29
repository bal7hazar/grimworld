//! Effective durations after modifiers (ENG-01 fix loop 2, F-9). design/15's modifiers lengthen
//! what the registry holds: conditions inflicted +33 % (a prefix), enchantments +10 to +20 %
//! (a suffix or an insignia), a set bonus +1 tick (knock-downs). Whatever they add, a deadline
//! `clock + effective` must stay at or below `MAX_CLOCK`, and `LAST_TICK` assumes an effective
//! duration of at most `MAX_DURATION`. The rule:
//! - the registry holds base durations, recharges and activations of at most `MAX_BASE_DURATION`;
//! - the percent bonuses that apply to one duration are summed and capped at
//!   `MAX_DURATION_BONUS_PERCENT` (50 %, above the MVP's largest, +33 %);
//! - the flat bonuses are summed and capped at `MAX_DURATION_FLAT` (3 ticks);
//! - then `base × (100 + percent) / 100 + flat ≤ MAX_DURATION`, the maximum being exactly it.

use crate::types::MAX_DURATION;

/// The widest base duration the registry may hold: `⌊(MAX_DURATION − 3) × 100 / 150⌋`.
pub const MAX_BASE_DURATION: u32 = 43688;
/// The cap on the summed percent bonuses of one duration.
pub const MAX_DURATION_BONUS_PERCENT: u32 = 50;
/// The cap on the summed flat bonuses of one duration, in ticks.
pub const MAX_DURATION_FLAT: u32 = 3;

/// The duration after modifiers. The registry's writer refuses a base above
/// `MAX_BASE_DURATION`; the bonuses are clamped here, so the result never passes `MAX_DURATION`.
pub fn effective_duration(base: u32, bonus_percent: u32, flat: u32) -> u32 {
    assert(base <= MAX_BASE_DURATION, 'duration: base above the cap');
    let percent = if bonus_percent > MAX_DURATION_BONUS_PERCENT {
        MAX_DURATION_BONUS_PERCENT
    } else {
        bonus_percent
    };
    let flat = if flat > MAX_DURATION_FLAT {
        MAX_DURATION_FLAT
    } else {
        flat
    };
    let (scaled, _) = DivRem::div_rem(base * (100 + percent), 100);
    let effective = scaled + flat;
    assert(effective <= MAX_DURATION, 'duration: above MAX_DURATION');
    effective
}
