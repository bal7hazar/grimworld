//! A position's level (ADR-0008 rule 1): one bit beside the position, in the word that holds the
//! position today, so that a level costs **no new slot** and a move writes the word it writes
//! anyway. `GROUND` (0) is every tile's level but a deck's; `DECK` (1) only on a bridge's deck.
//!
//! The bits (ENG-01 §3.2's free bits, proposed for the bookkeeping):
//! - `MemberState`: x 32–39 · y 40–47 · facing 48–55 (today) · **level 176** (bits
//!   176–249 are free after `casts_2` 168–175);
//! - `GoblinState`: x 0–7 · y 8–15 · facing 16–23 (today) · **level 240**, **the
//!   memory's level 241** (bits 240–249 are free after the recharges 128–239).
//!
//! `place` and `moved` are today's reads and writes of a position (`MemberSnapshotTrait::place`,
//! `GoblinSnapshotTrait::place` and `set_facing`'s delta, on the word); `place_level` and
//! `moved_level` add the level. The spike's costs are the differences (`tests/test_cost.cairo`).

use grimworld_logic::packing::{N32, N8, P112, P48, field, limbs, peel};

/// The level of every tile but a deck's.
pub const GROUND: u8 = 0;
/// The level of an actor on a bridge's deck.
pub const DECK: u8 = 1;

/// `MemberState`'s x, y, facing and level as field shifts.
const M_X: felt252 = 0x100000000;
const M_Y: felt252 = 0x10000000000;
const M_FACING: felt252 = 0x1000000000000;
const M_LEVEL: felt252 = 0x100000000000000000000000000000000000000000000;
/// `GoblinState`'s.
const G_X: felt252 = 0x1;
const G_Y: felt252 = 0x100;
const G_FACING: felt252 = 0x10000;
const G_LEVEL: felt252 = 0x1000000000000000000000000000000000000000000000000000000000000;

/// A position: a global tile, a facing, a level.
#[derive(Copy, Drop, PartialEq, Debug)]
pub struct Place {
    pub x: u8,
    pub y: u8,
    pub facing: u8,
    pub level: u8,
}

#[generate_trait]
pub impl MemberPlaceImpl of MemberPlaceTrait {
    /// Today's read: x, y, facing (`MemberSnapshotTrait::place`); the level is not read.
    fn place(state: felt252) -> Place {
        let (low, _) = limbs(state);
        let (mut rest, _) = DivRem::div_rem(low, N32);
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        Place {
            x: x.try_into().unwrap(),
            y: y.try_into().unwrap(),
            facing: facing.try_into().unwrap(),
            level: GROUND,
        }
    }

    /// The read with the level (bit 176, the high limb's bit 48).
    fn place_level(state: felt252) -> Place {
        let (low, high) = limbs(state);
        let (mut rest, _) = DivRem::div_rem(low, N32);
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        Place {
            x: x.try_into().unwrap(),
            y: y.try_into().unwrap(),
            facing: facing.try_into().unwrap(),
            level: field(high, P48, 2).try_into().unwrap(),
        }
    }

    /// Today's write of a move: x, y and facing rewritten in place by their deltas.
    fn moved(state: felt252, from: Place, to: Place) -> felt252 {
        state
            + delta(from.x, to.x, M_X)
            + delta(from.y, to.y, M_Y)
            + delta(from.facing, to.facing, M_FACING)
    }

    /// The write with the level.
    fn moved_level(state: felt252, from: Place, to: Place) -> felt252 {
        Self::moved(state, from, to) + delta(from.level, to.level, M_LEVEL)
    }
}

#[generate_trait]
pub impl GoblinPlaceImpl of GoblinPlaceTrait {
    /// Today's read: x, y, facing (`GoblinState` 0–23).
    fn place(state: felt252) -> Place {
        let (low, _) = limbs(state);
        let mut rest = low;
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        Place {
            x: x.try_into().unwrap(),
            y: y.try_into().unwrap(),
            facing: facing.try_into().unwrap(),
            level: GROUND,
        }
    }

    /// The read with the level (bit 240, the high limb's bit 112).
    fn place_level(state: felt252) -> Place {
        let (low, high) = limbs(state);
        let mut rest = low;
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        Place {
            x: x.try_into().unwrap(),
            y: y.try_into().unwrap(),
            facing: facing.try_into().unwrap(),
            level: field(high, P112, 2).try_into().unwrap(),
        }
    }

    /// Today's write of a move.
    fn moved(state: felt252, from: Place, to: Place) -> felt252 {
        state
            + delta(from.x, to.x, G_X)
            + delta(from.y, to.y, G_Y)
            + delta(from.facing, to.facing, G_FACING)
    }

    /// The write with the level.
    fn moved_level(state: felt252, from: Place, to: Place) -> felt252 {
        Self::moved(state, from, to) + delta(from.level, to.level, G_LEVEL)
    }
}

/// `(new − old) × shift` (`TickMathTrait::delta` on `u8` fields).
#[inline(always)]
fn delta(old: u8, new: u8, shift: felt252) -> felt252 {
    let old: felt252 = old.into();
    let new: felt252 = new.into();
    (new - old) * shift
}
