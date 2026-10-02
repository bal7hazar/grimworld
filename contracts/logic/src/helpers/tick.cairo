//! The arithmetic a tick shares between members and goblins (CBT-02; design/19 §5.1, §5.7, §5.8,
//! §5.12), scoped in `TickMathTrait` (docs/CAIRO.md §7, `helpers/`: what belongs to no entity),
//! and the checks of its inputs in `TickAssert`.

use crate::types::combat::condition;
use crate::types::tick::{ADRENALINE_DECAY, CRIPPLED_MOVE_TICKS, HEALTH_PER_PIP, MAX_PIPS};

pub mod errors {
    pub const CONDITION: felt252 = 'tick: condition not stored';
    pub const DURATION: felt252 = 'tick: duration below 1';
    /// Knocked down goes through `knock`, conditions 1–4 through `apply` (SPK-15's L2, D-172).
    pub const KNOCK: felt252 = 'tick: knock-down is knock';
}

#[generate_trait]
pub impl TickMathImpl of TickMathTrait {
    /// A condition inflicted at `t0` for `d ≥ 1` ticks over `old`: `max(old, t0 + d − 1)`
    /// (FX-6).
    #[inline(always)]
    fn refreshed(old: u32, t0: u32, d: u32) -> u32 {
        TickAssert::assert_duration(d);
        let deadline = t0 + d - 1;
        if deadline > old {
            deadline
        } else {
            old
        }
    }

    /// A cure at `t0` over `old`: `t0 − 1` if the condition is held at `t0`, else unchanged.
    /// `t0 ≥ 1`: every caller's `t0` is `c + 1` or a tick `T ≥ 1` (§5.1), never 0.
    #[inline(always)]
    fn cured(old: u32, t0: u32) -> u32 {
        if old >= t0 {
            t0 - 1
        } else {
            old
        }
    }

    /// A condition of deadline `deadline` held at `t0` (§5.1: `t0 ≤ D`; `t0` = `c + 1` in the
    /// action phase at clock `c`, `T` in a tick).
    #[inline(always)]
    fn held(deadline: u32, t0: u32) -> bool {
        t0 <= deadline
    }

    /// The ticks a move of one tile costs at `t0` (§3.2, FX-15): 2 while Crippled (deadline
    /// `crippled`) unless a `MOVEMENT` effect is held (FX-18), else 1.
    #[inline(always)]
    fn move_ticks(crippled: u32, t0: u32, movement: bool) -> u8 {
        if t0 <= crippled && !movement {
            CRIPPLED_MOVE_TICKS
        } else {
            1
        }
    }

    #[inline(always)]
    fn min16(a: u16, b: u16) -> u16 {
        if a < b {
            a
        } else {
            b
        }
    }

    /// The pips of the degenerating conditions active at `t` (§5.8 step 1): −3 Bleeding, −4
    /// Poison, −7 Burning (`types::combat::condition`).
    #[inline(always)]
    fn degeneration(bleeding: u32, poison: u32, burning: u32, t: u32) -> i32 {
        let mut pips = 0;
        if t <= bleeding {
            pips -= 3;
        }
        if t <= poison {
            pips -= 4;
        }
        if t <= burning {
            pips -= 7;
        }
        pips
    }

    /// A held effect's pips while it lasts (`t ≤ deadline`).
    #[inline(always)]
    fn effect_pips(pips: i8, deadline: u32, t: u32) -> i32 {
        if pips != 0 && t <= deadline {
            pips.into()
        } else {
            0
        }
    }

    /// `health + 2 × clamp(pips, −10, 10)`, clamped to `[0, max]` (§5.8 step 1; X-3: the pip
    /// sum is signed).
    fn heal(health: u16, pips: i32, max: u16) -> u16 {
        let pips = if pips > MAX_PIPS {
            MAX_PIPS
        } else if pips < -MAX_PIPS {
            -MAX_PIPS
        } else {
            pips
        };
        let change = HEALTH_PER_PIP * pips;
        if change < 0 {
            let loss: u16 = (-change).try_into().unwrap();
            if loss >= health {
                0
            } else {
                health - loss
            }
        } else {
            let next: u32 = health.into() + change.try_into().unwrap();
            if next > max.into() {
                max
            } else {
                next.try_into().unwrap()
            }
        }
    }

    /// Adrenaline less `ADRENALINE_DECAY`, floored at 0 (FX-12, D-157 E).
    #[inline(always)]
    fn decay(adrenaline: u16) -> u16 {
        if adrenaline < ADRENALINE_DECAY {
            0
        } else {
            adrenaline - ADRENALINE_DECAY
        }
    }

    /// `R = t₀ + r − 1` (§5.1; FX-2): `t₀` is at least 1, the first tick.
    #[inline(always)]
    fn recharge_deadline(t0: u32, r: u16) -> u32 {
        t0 + r.into() - 1
    }

    /// `(new − old) × shift`: the delta that rewrites a field in place, its neighbours
    /// untouched.
    #[inline(always)]
    fn delta(old: u128, new: u128, shift: felt252) -> felt252 {
        (new.into() - old.into()) * shift
    }

    #[inline(always)]
    fn tag(potion: bool) -> u128 {
        if potion {
            1
        } else {
            0
        }
    }
}

#[generate_trait]
pub impl TickAssert of TickAssertTrait {
    /// A condition the words store: 1–5, the MVP's (design/19 §3.2; 6–9 need FX-22's word).
    #[inline(always)]
    fn assert_condition(condition: u8) {
        assert(
            condition >= condition::BLEEDING && condition <= condition::LAST_MVP, errors::CONDITION,
        );
    }

    /// A duration inflicted lasts at least 1 tick (a duration of 0 is a cure, §5.1).
    #[inline(always)]
    fn assert_duration(d: u32) {
        assert(d >= 1, errors::DURATION);
    }
}

/// The shared arithmetic's unit tests (CBT-04; D-167): §5.8's step 3 checked against the design
/// (the pips of each degenerating condition, their sum with the regeneration clamped to ±10, × 2,
/// health clamped to [0, max]), refresh and cure, a condition held to its deadline, Crippled's
/// move cost.
#[cfg(test)]
mod tests {
    use super::{TickAssert, TickMathTrait};

    // §3.2's rows 1–3 (§5.8 step 1): −3 Bleeding, −4 Poison, −7 Burning, summed
    // when stacked (§5.7: different conditions stack); held through `t = D`, not
    // after (a condition of `d` ticks degenerates `d` times, §5.1).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_degeneration_pips() {
        assert(TickMathTrait::degeneration(50, 0, 0, 50) == -3, 'bleeding -3');
        assert(TickMathTrait::degeneration(0, 50, 0, 50) == -4, 'poison -4');
        assert(TickMathTrait::degeneration(0, 0, 50, 50) == -7, 'burning -7');
        assert(TickMathTrait::degeneration(50, 50, 50, 50) == -14, 'stacked -14');
        assert(TickMathTrait::degeneration(49, 49, 49, 50) == 0, 'over at D + 1');
    }

    // §5.8 step 1: the pips summed (regeneration, effects, conditions), clamped to [−10, +10],
    // × 2, health clamped to [0, max]. Every condition with regeneration 0: −14 → −10, −20
    // health; with +5 regeneration and Burning: −2 → −4; a loss beyond the health → 0; a
    // gain beyond the max → the max.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_degeneration_heal() {
        let all = TickMathTrait::degeneration(60, 60, 60, 60);
        assert(TickMathTrait::heal(100, all, 480) == 80, 'clamped to -10: -20');
        let burning = 5 + TickMathTrait::degeneration(0, 0, 60, 60);
        assert(TickMathTrait::heal(100, burning, 480) == 96, '+5 - 7: -4');
        assert(TickMathTrait::heal(15, all, 480) == 0, 'floored at 0');
        assert(TickMathTrait::heal(479, 3, 480) == 480, 'capped at max');
        assert(TickMathTrait::heal(100, 14, 480) == 120, 'clamped to +10: +20');
    }

    // FX-6: a refresh keeps `max(D_old, D_new)`, at equal and smaller durations; a cure is a
    // duration of 0, `D = t0 − 1`, and leaves an absent condition alone (§3.2's `CURE`).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_refreshed_cured() {
        assert(TickMathTrait::refreshed(0, 70, 8) == 77, 'new: t0 + d - 1');
        assert(TickMathTrait::refreshed(77, 70, 8) == 77, 'equal: kept');
        assert(TickMathTrait::refreshed(77, 74, 2) == 77, 'smaller: kept');
        assert(TickMathTrait::refreshed(77, 74, 8) == 81, 'larger: refreshed');
        assert(TickMathTrait::cured(81, 76) == 75, 'cured: t0 - 1');
        assert(TickMathTrait::cured(75, 76) == 75, 'absent: nothing');
        assert(TickMathTrait::cured(0, 76) == 0, 'never held: nothing');
    }

    // §3.2 row 4 (FX-15, FX-18): a move costs 2 ticks while Crippled, 1 after its deadline or
    // with a `MOVEMENT` effect; `held` reads `t0 ≤ D`.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_move_ticks() {
        assert(TickMathTrait::move_ticks(62, 62, false) == 2, 'crippled: 2');
        assert(TickMathTrait::move_ticks(62, 63, false) == 1, 'over: 1');
        assert(TickMathTrait::move_ticks(62, 60, true) == 1, 'movement: 1');
        assert(TickMathTrait::held(62, 62) && !TickMathTrait::held(62, 63), 'held to D');
    }

    // A duration inflicted below 1 is refused: a duration of 0 is a cure (§5.1), never inflicted
    // (`InflictionTrait::duration` clamps a value to 1 first).
    #[test]
    #[should_panic(expected: 'tick: duration below 1')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_refreshed_zero_refused() {
        TickAssert::assert_duration(0);
    }
}
