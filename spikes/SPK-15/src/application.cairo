//! Lever 2: what one condition's application costs on the member (CBT-04: 108,100) and on a goblin
//! (76,820), and what writing its field in place, or a tick's applications together, would save.
//!
//! CBT-04's `apply` (`cbt04`) calls, each a function that takes the whole actor by reference (the
//! member is 34 felts, a goblin 24): `is_alive`, `inflict` (`condition`, then `set_condition`, each
//! a chain of five branches, Crippled's read from and written to the words), `duration`
//! (`effective_duration`), and on a knock-down `interrupt` (the bar slot's sheet, `set_recharge`,
//! `clear`). Sierra charges a function without a loop its costliest path: every application pays
//! the knock-down's interrupt and Crippled's word, whatever the condition.
//!
//! The alternatives below give the same results (`tests/bench_application.cairo` checks each
//! against CBT-04's on every condition):
//! - `apply_in_place`: one function, every step inlined, the deadline written to its field by one
//!   branch; Crippled's word read once;
//! - `apply_split`: `apply_in_place` for conditions 1–4 and `knock` for Knocked down, the
//! executor
//!   calling the one its entry names (CBT-05 dispatches on the entry's kind and parameter anyway);
//! - `Afflictions`: a tick's applications on one actor gathered (the maximum of each deadline, the
//!   first knock-down's `t0`), written once (`flush_member`, `flush_goblin`).

use grimworld_logic::durations::effective_duration;
use grimworld_logic::helpers::tick::TickMathTrait;
use grimworld_logic::models::goblin::{Goblin, GoblinTickTrait, GoblinTrait, GoblinWordsTrait};
use grimworld_logic::models::member::{Member, MemberTickTrait, MemberWordsTrait};
use grimworld_logic::packing::{P32, field, limbs};
use grimworld_logic::types::combat::condition;
use grimworld_logic::types::effect::MAX_VALUE_DURATION;
use grimworld_logic::types::tick::{Sheets, status};
use crate::cbt04::Infliction;

/// `MemberTimers` bit 160, Crippled's offset in the member's words.
const F160: felt252 = 0x10000000000000000000000000000000000000000;

/// The duration of CBT-04's `InflictionTrait::duration`, inlined.
#[inline(always)]
fn duration(source: @Infliction, condition: u8, v: i32) -> u32 {
    let base: u32 = if v < 1 {
        1
    } else if v > MAX_VALUE_DURATION {
        MAX_VALUE_DURATION.try_into().unwrap()
    } else {
        v.try_into().unwrap()
    };
    let percent: u32 = if condition == *source.condition {
        (*source.percent).into()
    } else {
        0
    };
    let flat: u32 = if condition == condition::KNOCKED_DOWN {
        (*source.knockdown).into()
    } else {
        0
    };
    effective_duration(base, percent, flat)
}

/// `max(old, t0 + d − 1)` (FX-6), `d ≥ 1` by construction (`duration` is at least 1).
#[inline(always)]
fn refreshed(old: u32, t0: u32, d: u32) -> u32 {
    let deadline = t0 + d - 1;
    if deadline > old {
        deadline
    } else {
        old
    }
}

#[generate_trait]
pub impl MemberApplicationImpl of MemberApplicationTrait {
    /// CBT-04's application, every step inlined: the same checks and results.
    fn apply_in_place(
        ref self: Member, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if self.status != status::INSIDE || self.health == 0 {
            return;
        }
        let d = duration(source, condition, v);
        if condition == condition::BLEEDING {
            self.bleeding = refreshed(self.bleeding, t0, d);
        } else if condition == condition::POISON {
            self.poison = refreshed(self.poison, t0, d);
        } else if condition == condition::BURNING {
            self.burning = refreshed(self.burning, t0, d);
        } else if condition == condition::CRIPPLED {
            let (_, high) = limbs(self.words.timers);
            let old: u32 = field(high, P32, P32).try_into().unwrap();
            let new = refreshed(old, t0, d);
            self.words.timers += TickMathTrait::delta(old.into(), new.into(), F160);
        } else {
            assert(condition == condition::KNOCKED_DOWN, 'tick: condition not stored');
            self.knocked = refreshed(self.knocked, t0, d);
            self.interrupt(t0, sheets);
        }
    }

    /// Conditions 1–4 only (the executor calls `knock` for Knocked down).
    fn apply_split(ref self: Member, condition: u8, v: i32, source: @Infliction, t0: u32) {
        if self.status != status::INSIDE || self.health == 0 {
            return;
        }
        let d = duration(source, condition, v);
        if condition == condition::BLEEDING {
            self.bleeding = refreshed(self.bleeding, t0, d);
        } else if condition == condition::POISON {
            self.poison = refreshed(self.poison, t0, d);
        } else if condition == condition::BURNING {
            self.burning = refreshed(self.burning, t0, d);
        } else {
            assert(condition == condition::CRIPPLED, 'tick: condition not stored');
            let (_, high) = limbs(self.words.timers);
            let old: u32 = field(high, P32, P32).try_into().unwrap();
            let new = refreshed(old, t0, d);
            self.words.timers += TickMathTrait::delta(old.into(), new.into(), F160);
        }
    }

    /// Knocked down for the value `v` at `t0`, its activation interrupted (§5.9).
    fn knock(ref self: Member, v: i32, source: @Infliction, t0: u32, sheets: @Sheets) {
        if self.status != status::INSIDE || self.health == 0 {
            return;
        }
        let d = duration(source, condition::KNOCKED_DOWN, v);
        self.knocked = refreshed(self.knocked, t0, d);
        self.interrupt(t0, sheets);
    }

    /// One degenerating condition (1–3) only: the hot fields, no word read.
    fn apply_hot(ref self: Member, condition: u8, v: i32, source: @Infliction, t0: u32) {
        if self.status != status::INSIDE || self.health == 0 {
            return;
        }
        let d = duration(source, condition, v);
        if condition == condition::BLEEDING {
            self.bleeding = refreshed(self.bleeding, t0, d);
        } else if condition == condition::POISON {
            self.poison = refreshed(self.poison, t0, d);
        } else {
            assert(condition == condition::BURNING, 'tick: condition not stored');
            self.burning = refreshed(self.burning, t0, d);
        }
    }
}

#[generate_trait]
pub impl GoblinApplicationImpl of GoblinApplicationTrait {
    /// CBT-04's application on a goblin, every step inlined.
    fn apply_in_place(
        ref self: Goblin, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if !self.is_alive() {
            return;
        }
        let d = duration(source, condition, v);
        if condition == condition::BLEEDING {
            self.bleeding = refreshed(self.bleeding, t0, d);
        } else if condition == condition::POISON {
            self.poison = refreshed(self.poison, t0, d);
        } else if condition == condition::BURNING {
            self.burning = refreshed(self.burning, t0, d);
        } else if condition == condition::CRIPPLED {
            let old = self.crippled();
            self.set_crippled(refreshed(old, t0, d));
        } else {
            assert(condition == condition::KNOCKED_DOWN, 'tick: condition not stored');
            self.knocked = refreshed(self.knocked, t0, d);
            self.interrupt(t0, sheets);
        }
    }
}

/// A tick's applications on one actor, gathered: each condition's latest deadline (0 for none
/// applied) and the first knock-down's `t0` (0 for none). Refreshing is a maximum (FX-6), so the
/// applications commute; a knock-down interrupts at its own `t0`, which the first one fixes (a
/// later one finds no activation left).
#[derive(Copy, Drop, Default, Debug, PartialEq)]
pub struct Afflictions {
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub crippled: u32,
    pub knocked: u32,
    pub knocked_at: u32,
}

#[generate_trait]
pub impl AfflictionsImpl of AfflictionsTrait {
    /// One application gathered: condition 1–5 for the value `v` at `t0`.
    fn add(ref self: Afflictions, condition: u8, v: i32, source: @Infliction, t0: u32) {
        let deadline = t0 + duration(source, condition, v) - 1;
        if condition == condition::BLEEDING {
            if deadline > self.bleeding {
                self.bleeding = deadline;
            }
        } else if condition == condition::POISON {
            if deadline > self.poison {
                self.poison = deadline;
            }
        } else if condition == condition::BURNING {
            if deadline > self.burning {
                self.burning = deadline;
            }
        } else if condition == condition::CRIPPLED {
            if deadline > self.crippled {
                self.crippled = deadline;
            }
        } else {
            assert(condition == condition::KNOCKED_DOWN, 'tick: condition not stored');
            if deadline > self.knocked {
                self.knocked = deadline;
            }
            if self.knocked_at == 0 {
                self.knocked_at = t0;
            }
        }
    }

    /// Every gathered application written on the member at once (nothing if it is not alive).
    fn flush_member(self: @Afflictions, ref member: Member, sheets: @Sheets) {
        if member.status != status::INSIDE || member.health == 0 {
            return;
        }
        if *self.bleeding > member.bleeding {
            member.bleeding = *self.bleeding;
        }
        if *self.poison > member.poison {
            member.poison = *self.poison;
        }
        if *self.burning > member.burning {
            member.burning = *self.burning;
        }
        if *self.crippled != 0 {
            let old = member.crippled();
            if *self.crippled > old {
                member
                    .words
                    .timers += TickMathTrait::delta(old.into(), (*self.crippled).into(), F160);
            }
        }
        if *self.knocked_at != 0 {
            if *self.knocked > member.knocked {
                member.knocked = *self.knocked;
            }
            member.interrupt(*self.knocked_at, sheets);
        }
    }

    /// Every gathered application written on a goblin at once (nothing if it is dead).
    fn flush_goblin(self: @Afflictions, ref goblin: Goblin, sheets: @Sheets) {
        if !goblin.is_alive() {
            return;
        }
        if *self.bleeding > goblin.bleeding {
            goblin.bleeding = *self.bleeding;
        }
        if *self.poison > goblin.poison {
            goblin.poison = *self.poison;
        }
        if *self.burning > goblin.burning {
            goblin.burning = *self.burning;
        }
        if *self.crippled != 0 {
            let old = goblin.crippled();
            if *self.crippled > old {
                goblin.set_crippled(*self.crippled);
            }
        }
        if *self.knocked_at != 0 {
            if *self.knocked > goblin.knocked {
                goblin.knocked = *self.knocked;
            }
            goblin.interrupt(*self.knocked_at, sheets);
        }
    }
}
