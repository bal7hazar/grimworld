// Fix loop 2, F-9: the effective duration after modifiers never passes MAX_DURATION.
use grimworld_logic::durations::{
    MAX_BASE_DURATION, MAX_DURATION_BONUS_PERCENT, MAX_DURATION_FLAT, effective_duration,
};
use grimworld_logic::types::{LAST_TICK, MAX_CLOCK, MAX_DURATION, MAX_WEIGHT_TICKS};

// The widest base with every bonus at its cap is exactly MAX_DURATION; bonuses beyond the caps
// are clamped; design/15's +33 % on a condition of 20 ticks gives 26.
#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_effective_duration_maximum() {
    assert(
        effective_duration(
            MAX_BASE_DURATION, MAX_DURATION_BONUS_PERCENT, MAX_DURATION_FLAT,
        ) == MAX_DURATION,
        'maximum is MAX_DURATION',
    );
    assert(effective_duration(MAX_BASE_DURATION, 500, 90) == MAX_DURATION, 'bonuses clamped');
    assert(effective_duration(20, 33, 0) == 26, 'rending +33 %');
    assert(effective_duration(2, 0, 1) == 3, 'set bonus +1 tick');
    // design/20 §6 test 10: a duration carried as a value, at its widest, gives 49,153.
    assert(effective_duration(32767, 50, 3) == 49153, 'value duration widest');
    // The last clock an action may start at, plus its ticks and the longest duration, is the cap.
    assert(LAST_TICK + MAX_WEIGHT_TICKS + MAX_DURATION == MAX_CLOCK, 'LAST_TICK');
}

#[test]
#[should_panic(expected: 'duration: base above the cap')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_base_above_cap_refused() {
    effective_duration(MAX_BASE_DURATION + 1, 0, 0);
}
