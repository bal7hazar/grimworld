//! What a source adds to the conditions it inflicts (CBT-04; design/19 §5.7): its
//! `CONDITION_DURATION` (one condition and its percent, the weapon's prefix) and its
//! `KNOCKDOWN_FLAT` (ticks), as the snapshot flattened them (`snapshot::MemberKit`; a member reads
//! them in its words, `MemberWordsTrait::infliction`). A goblin and a terrain trap hold none
//! (design/19 §7.3: a caste has no passive), `Default`. Not stored on its own: a value type.

use crate::durations::effective_duration;
use crate::types::combat::condition;
use crate::types::effect::MAX_VALUE_DURATION;

#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Infliction {
    /// `CONDITION_DURATION`'s condition, 0 for none.
    pub condition: u8,
    /// Its percent (6 bits; `effective_duration` caps it at 50).
    pub percent: u8,
    /// `KNOCKDOWN_FLAT`, ticks (2 bits; `effective_duration` caps it at 3).
    pub knockdown: u8,
}

#[generate_trait]
pub impl InflictionImpl of InflictionTrait {
    /// The duration of `condition` inflicted with the value `v` (a `CONDITION` entry's, or an
    /// `ON_ATTACK_CONDITION`'s, at the source's rank): `v` clamped to its kind's bounds 1…32,767
    /// (§6: at play, a value outside them is clamped), then `effective_duration` with the percent
    /// if the source's `CONDITION_DURATION` names this condition and the flat ticks if it is
    /// Knocked down (§5.7). Never panics: the base stays below `MAX_BASE_DURATION`. Inlined in
    /// each application (SPK-15's L2, D-172).
    #[inline(always)]
    fn duration(self: @Infliction, condition: u8, v: i32) -> u32 {
        let base: u32 = if v < 1 {
            1
        } else if v > MAX_VALUE_DURATION {
            MAX_VALUE_DURATION.try_into().unwrap()
        } else {
            v.try_into().unwrap()
        };
        let percent: u32 = if condition == *self.condition {
            (*self.percent).into()
        } else {
            0
        };
        let flat: u32 = if condition == condition::KNOCKED_DOWN {
            (*self.knockdown).into()
        } else {
            0
        };
        effective_duration(base, percent, flat)
    }
}

/// Its unit tests (D-167): the bonuses of §5.7 and the clamps of §6.
#[cfg(test)]
mod tests {
    use crate::types::combat::condition;
    use super::{Infliction, InflictionTrait};

    // A goblin's (no passive) duration is the value itself; the prefix's percent applies to its
    // condition only (design/03's Rending Cut, Bleeding 20 with "Rending" +33 %: 26), the
    // knock-down's ticks to Knocked down only (Skullring 2 with *Hob-breaker* +1: 3).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_infliction_duration() {
        let none: Infliction = Default::default();
        assert(none.duration(condition::BLEEDING, 20) == 20, 'no passive');
        let rending = Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 };
        assert(rending.duration(condition::BLEEDING, 20) == 26, 'its condition +33 %');
        assert(rending.duration(condition::POISON, 20) == 20, 'another: nothing');
        assert(rending.duration(condition::KNOCKED_DOWN, 2) == 3, 'knock-down +1');
        assert(rending.duration(condition::CRIPPLED, 2) == 2, 'flat: knock-down only');
    }

    // §6: a value outside its kind's bounds is clamped (0 → 1, a negative → 1,
    // 40,000 → 32,767); the bonuses at their caps (50 %, 3 ticks) above them; the
    // widest stays at 49,153, below `MAX_DURATION`.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_infliction_duration_edges() {
        let none: Infliction = Default::default();
        assert(none.duration(condition::POISON, 0) == 1, '0 -> 1');
        assert(none.duration(condition::POISON, -5) == 1, 'negative -> 1');
        assert(none.duration(condition::POISON, 40000) == 32767, 'above -> 32767');
        let wide = Infliction { condition: condition::KNOCKED_DOWN, percent: 63, knockdown: 3 };
        assert(wide.duration(condition::KNOCKED_DOWN, 10) == 18, '10 x 1.5 + 3');
        assert(wide.duration(condition::KNOCKED_DOWN, 32767) == 49153, 'the widest');
    }
}
