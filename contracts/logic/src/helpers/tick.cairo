//! The arithmetic a tick shares between members and goblins (CBT-02; design/19 §5.1, §5.7, §5.8,
//! §5.12), scoped in `TickMathTrait` (docs/CAIRO.md §7, `helpers/`: what belongs to no entity),
//! and the checks of its inputs in `TickAssert`.

use crate::types::combat::condition;
use crate::types::tick::{ADRENALINE_DECAY, HEALTH_PER_PIP, MAX_PIPS};

pub mod errors {
    pub const CONDITION: felt252 = 'tick: condition not stored';
    pub const DURATION: felt252 = 'tick: duration below 1';
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
    #[inline(always)]
    fn cured(old: u32, t0: u32) -> u32 {
        if old >= t0 {
            t0 - 1
        } else {
            old
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
