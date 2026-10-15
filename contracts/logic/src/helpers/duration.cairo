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

use crate::constants::MAX_DURATION;

/// The widest base duration the registry may hold: `⌊(MAX_DURATION − 3) × 100 / 150⌋`.
pub const MAX_BASE_DURATION: u32 = 43688;
/// The cap on the summed percent bonuses of one duration.
pub const MAX_DURATION_BONUS_PERCENT: u32 = 50;
/// The cap on the summed flat bonuses of one duration, in ticks.
pub const MAX_DURATION_FLAT: u32 = 3;

pub mod errors {
    /// A base duration above `MAX_BASE_DURATION`.
    pub const BASE_ABOVE_CAP: felt252 = 'duration: base above the cap';
    /// An effective duration above `MAX_DURATION`.
    pub const ABOVE_MAX: felt252 = 'duration: above MAX_DURATION';
}

#[generate_trait]
pub impl DurationImpl of DurationTrait {
    /// The duration after modifiers. The registry's writer refuses a base above
    /// `MAX_BASE_DURATION`; the bonuses are clamped here, so the result never passes
    /// `MAX_DURATION`.
    fn effective_duration(base: u32, bonus_percent: u32, flat: u32) -> u32 {
        DurationAssert::assert_base(base);
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
        DurationAssert::assert_effective(effective);
        effective
    }
}

#[generate_trait]
pub impl DurationAssert of DurationAssertTrait {
    /// Refuses a base duration above `MAX_BASE_DURATION`.
    #[inline(always)]
    fn assert_base(base: u32) {
        assert(base <= MAX_BASE_DURATION, errors::BASE_ABOVE_CAP);
    }

    /// Refuses an effective duration above `MAX_DURATION`.
    #[inline(always)]
    fn assert_effective(effective: u32) {
        assert(effective <= MAX_DURATION, errors::ABOVE_MAX);
    }
}

// Fix loop 2, F-9: the effective duration after modifiers never passes MAX_DURATION.
#[cfg(test)]
mod tests {
    use crate::constants::{LAST_TICK, MAX_CLOCK, MAX_DURATION, MAX_WEIGHT_TICKS};
    use super::{DurationTrait, MAX_BASE_DURATION, MAX_DURATION_BONUS_PERCENT, MAX_DURATION_FLAT};

    // The widest base with every bonus at its cap is exactly MAX_DURATION; bonuses beyond the caps
    // are clamped; design/15's +33 % on a condition of 20 ticks gives 26.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_effective_duration_maximum() {
        assert(
            DurationTrait::effective_duration(
                MAX_BASE_DURATION, MAX_DURATION_BONUS_PERCENT, MAX_DURATION_FLAT,
            ) == MAX_DURATION,
            'maximum is MAX_DURATION',
        );
        assert(
            DurationTrait::effective_duration(MAX_BASE_DURATION, 500, 90) == MAX_DURATION,
            'bonuses clamped',
        );
        assert(DurationTrait::effective_duration(20, 33, 0) == 26, 'rending +33 %');
        assert(DurationTrait::effective_duration(2, 0, 1) == 3, 'set bonus +1 tick');
        // design/20 §6 test 10: a duration carried as a value, at its widest, gives 49,153.
        assert(DurationTrait::effective_duration(32767, 50, 3) == 49153, 'value duration widest');
        // The last clock an action may start at, plus its ticks and the longest duration, is the
        // cap.
        assert(LAST_TICK + MAX_WEIGHT_TICKS + MAX_DURATION == MAX_CLOCK, 'LAST_TICK');
    }

    #[test]
    #[should_panic(expected: 'duration: base above the cap')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_base_above_cap_refused() {
        DurationTrait::effective_duration(MAX_BASE_DURATION + 1, 0, 0);
    }
}
