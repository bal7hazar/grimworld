//! CBT-04's conditions' rules, copied for measurement (SPK-15's brief: never by editing the branch).
//!
//! Sources, branch `feat/cbt-04-conditions` at commit `b5f4069` (PR #228):
//! - `contracts/logic/src/types/infliction.cairo`: `Infliction`, `InflictionTrait::duration`,
//!   whole (its tests left out);
//! - `contracts/logic/src/models/member.cairo`: `MemberTrait::is_alive`,
//!   `MemberWordsTrait::infliction`, `MemberConditionTrait` (`apply` and the predicates);
//! - `contracts/logic/src/models/goblin.cairo`: `GoblinConditionTrait` (`apply` and the predicates);
//! - `contracts/logic/src/helpers/tick.cairo`: `TickMathTrait::held`, `move_ticks`, and
//!   `types/tick.cairo`'s `CRIPPLED_MOVE_TICKS`.
//! The bodies are unchanged; only the traits' names gather what the branch spread over its
//! modules (`Cbt04MemberTrait`, `Cbt04GoblinTrait`, `Cbt04MathTrait`), so that they sit beside
//! main's own traits on `Member` and `Goblin` without a clash.

use grimworld_logic::durations::effective_duration;
use grimworld_logic::models::goblin::{Goblin, GoblinLifecycleTrait, GoblinTickTrait, GoblinTrait};
use grimworld_logic::models::member::{
    Member, MemberLifecycleTrait, MemberTickTrait, MemberWordsTrait,
};
use grimworld_logic::packing::{P16, P20, P72, field, limbs};
use grimworld_logic::types::combat::condition;
use grimworld_logic::types::effect::MAX_VALUE_DURATION;
use grimworld_logic::types::tick::{Sheets, status};

/// A crippled actor's move of one tile, in ticks (design/19 §3.2, FX-15).
pub const CRIPPLED_MOVE_TICKS: u8 = 2;

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
    /// Knocked down (§5.7). Never panics: the base stays below `MAX_BASE_DURATION`.
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

#[generate_trait]
pub impl Cbt04MathImpl of Cbt04MathTrait {
    /// A condition of deadline `deadline` held at `t0` (§5.1: `t0 ≤ D`).
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
}

/// CBT-04's rules on a member (`MemberTrait::is_alive`, `MemberWordsTrait::infliction`,
/// `MemberConditionTrait`).
#[generate_trait]
pub impl Cbt04MemberImpl of Cbt04MemberTrait {
    /// Alive: inside, above 0 health (an actor the executor's entries reach, §5.14).
    #[inline(always)]
    fn is_alive(self: @Member) -> bool {
        *self.status == status::INSIDE && *self.health > 0
    }

    /// What it adds to the conditions it inflicts (`MemberKit` high limb: `CONDITION_DURATION`'s
    /// condition at 144–147 and percent at 148–153, `KNOCKDOWN_FLAT` at 200–201; design/19
    /// §5.7).
    fn infliction(self: @Member) -> Infliction {
        let (_, high) = limbs(*self.words.kit);
        Infliction {
            condition: field(high, P16, 0x10).try_into().unwrap(),
            percent: field(high, P20, 0x40).try_into().unwrap(),
            knockdown: field(high, P72, 4).try_into().unwrap(),
        }
    }

    /// A `CONDITION` entry (or an `ON_ATTACK_CONDITION`'s) applied at `t0`: condition 1–5 for
    /// the value `v`, through the source's `Infliction` (`effective_duration`), refreshed by
    /// `max` (FX-6, FX-31); nothing on a member not alive. Knocked down interrupts its activation
    /// (§5.9): energy stays paid, the recharge counts from `t0`, no effect (FX-2, FX-4).
    fn apply(
        ref self: Member, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if !self.is_alive() {
            return;
        }
        self.inflict(condition, t0, source.duration(condition, v));
        if condition == condition::KNOCKED_DOWN {
            self.interrupt(t0, sheets);
        }
    }

    /// Condition 1–5 held at `t0` (`t0 ≤ D`).
    #[inline(always)]
    fn holds(self: @Member, condition: u8, t0: u32) -> bool {
        Cbt04MathTrait::held(self.condition(condition), t0)
    }

    /// Not knocked down at `t0`: an action other than Wait is legal (§5.2, FX-7).
    #[inline(always)]
    fn can_act(self: @Member, t0: u32) -> bool {
        !Cbt04MathTrait::held(*self.knocked, t0)
    }

    /// Knocked down at `t0`: a weapon hit on it is critical from any arc (§3.2), for CBT-03a.
    #[inline(always)]
    fn takes_critical(self: @Member, t0: u32) -> bool {
        Cbt04MathTrait::held(*self.knocked, t0)
    }

    /// Not knocked down at `t0`: it may block or evade (§5.6, FX-7), for CBT-03a.
    #[inline(always)]
    fn can_defend(self: @Member, t0: u32) -> bool {
        !Cbt04MathTrait::held(*self.knocked, t0)
    }

    /// The ticks its move of one tile costs at `t0`: 2 while Crippled, unless `movement`, else 1.
    #[inline(always)]
    fn move_ticks(self: @Member, t0: u32, movement: bool) -> u8 {
        Cbt04MathTrait::move_ticks(self.crippled(), t0, movement)
    }
}

/// CBT-04's rules on a goblin (`GoblinConditionTrait`).
#[generate_trait]
pub impl Cbt04GoblinImpl of Cbt04GoblinTrait {
    /// A `CONDITION` entry (or an `ON_ATTACK_CONDITION`'s) applied at `t0`: condition 1–5 for
    /// the value `v`, through the source's `Infliction` (`effective_duration`), refreshed by
    /// `max` (FX-6, FX-31); a dead goblin takes nothing. Knocked down interrupts its activation
    /// (§5.9): its field goes to none, the recharge counts from `t0`; a recovery is kept.
    fn apply(
        ref self: Goblin, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if !self.is_alive() {
            return;
        }
        self.inflict(condition, t0, source.duration(condition, v));
        if condition == condition::KNOCKED_DOWN {
            self.interrupt(t0, sheets);
        }
    }

    /// Knocked down at `t0`: a weapon hit on it is critical from any arc (§3.2), for CBT-03a.
    #[inline(always)]
    fn takes_critical(self: @Goblin, t0: u32) -> bool {
        Cbt04MathTrait::held(*self.knocked, t0)
    }

    /// Not knocked down at `t0`: it may block or evade (§5.6, FX-7), for CBT-03a.
    #[inline(always)]
    fn can_defend(self: @Goblin, t0: u32) -> bool {
        !Cbt04MathTrait::held(*self.knocked, t0)
    }
}
