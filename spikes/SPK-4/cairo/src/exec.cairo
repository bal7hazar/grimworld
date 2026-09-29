//! The executables: what the client (option b) and the vector generator run.
//!
//! A case is `[op, args...]`, its result a list of felts:
//! * `op = 0`, damage: `[base, strength, armor, bonus, penetration, modifier]` → `[damage]`
//! * `op = 1`, goblin step: `[walkable, occupied, goblin, target]` → `[tile, occupied]`
//! An argument outside its type (a u16 above 65535, an i16 outside [−32768, 32767] as a felt) is a
//! panic, as a transaction with that calldata would be.

use crate::board::goblin_step;
use crate::damage::damage;

pub mod errors {
    pub const UNKNOWN_OP: felt252 = 'exec: unknown op';
    pub const ARGUMENTS: felt252 = 'exec: wrong argument count';
}

/// Runs one case.
pub fn run(case: Span<felt252>) -> Array<felt252> {
    let op = *case[0];
    if op == 0 {
        assert(case.len() == 7, errors::ARGUMENTS);
        let d = damage(
            (*case[1]).try_into().unwrap(),
            (*case[2]).try_into().unwrap(),
            (*case[3]).try_into().unwrap(),
            (*case[4]).try_into().unwrap(),
            (*case[5]).try_into().unwrap(),
            (*case[6]).try_into().unwrap(),
        );
        array![d.into()]
    } else if op == 1 {
        assert(case.len() == 5, errors::ARGUMENTS);
        let (tile, occupied) = goblin_step(
            *case[1], *case[2], (*case[3]).try_into().unwrap(), (*case[4]).try_into().unwrap(),
        );
        array![tile.into(), occupied]
    } else {
        core::panic_with_felt252(errors::UNKNOWN_OP)
    }
}
