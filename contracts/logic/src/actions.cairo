//! The actions of a played batch and their wire format: the whole batch in one felt of calldata
//! (docs/architecture/ENG-01-interfaces.md, *play*). A felt of calldata costs 5,120 L2 gas
//! (FND-04), so 10 actions in one felt save about 29 felts (148,480) against one felt per field.
//!
//! Layout of the batch felt (no `LIVE`: it is calldata, never stored):
//! - bits 0 to 3: the count, 1 to 10;
//! - actions 0 to 4 at bits `4 + 24 i` (low limb, up to bit 123);
//! - actions 5 to 9 at bits `128 + 24 (i − 5)` (high limb, up to bit 247).
//!
//! Layout of one action, 24 bits: the kind in bits 0 to 2, then
//! - Move, Turn: the direction (0 East, 1 North-East, 2 North-West, 3 West, 4 South-West,
//!   5 South-East, the map library's order) in bits 3 to 5;
//! - Wait: nothing;
//! - Attack: the target entity in bits 3 to 18;
//! - Skill: the bar slot (0 to 7) in bits 3 to 5, 1 in bit 6 when the target is a tile, the target
//!   (entity or tile) in bits 7 to 22;
//! - Item: the belt slot (0 to 3) in bits 3 to 4, the target entity in bits 5 to 20;
//! - Interact: the tile in bits 3 to 18 (objects that draw nothing: levers, braziers, nodes).

use crate::packing::{P24, TWO_POW_128};
use crate::types::{MAX_ACTIONS, Target, Tile};

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Action {
    Move: u8,
    Turn: u8,
    Wait,
    Attack: u16,
    Skill: (u8, Target),
    Item: (u8, u16),
    Interact: Tile,
}

const K_MOVE: u32 = 0;
const K_TURN: u32 = 1;
const K_WAIT: u32 = 2;
const K_ATTACK: u32 = 3;
const K_SKILL: u32 = 4;
const K_ITEM: u32 = 5;
const K_INTERACT: u32 = 6;

/// The 24 bits of an action; `None` for a direction above 5, a bar slot above 7 or a belt slot
/// above 3: the encoder refuses what the decoder would refuse, so that no out-of-range value
/// spills into a neighbouring field (ENG-01 fix loop 1, F-10).
pub fn encode_action(action: Action) -> Option<u32> {
    match action {
        Action::Move(d) => if d > 5 {
            None
        } else {
            Some(K_MOVE + d.into() * 8)
        },
        Action::Turn(d) => if d > 5 {
            None
        } else {
            Some(K_TURN + d.into() * 8)
        },
        Action::Wait => Some(K_WAIT),
        Action::Attack(entity) => Some(K_ATTACK + entity.into() * 8),
        Action::Skill((
            slot, target,
        )) => {
            if slot > 7 {
                return None;
            }
            let (flag, value): (u32, u32) = match target {
                Target::Entity(e) => (0, e.into()),
                Target::Tile(t) => (1, t.into()),
            };
            Some(K_SKILL + slot.into() * 8 + flag * 64 + value * 128)
        },
        Action::Item((slot, entity)) => if slot > 3 {
            None
        } else {
            Some(K_ITEM + slot.into() * 8 + entity.into() * 32)
        },
        Action::Interact(tile) => Some(K_INTERACT + tile.into() * 8),
    }
}

/// `None` for a kind or an argument out of range.
pub fn decode_action(code: u32) -> Option<Action> {
    let (arg, kind) = DivRem::div_rem(code, 8);
    if kind == K_MOVE || kind == K_TURN {
        if arg > 5 {
            return None;
        }
        let d: u8 = arg.try_into().unwrap();
        return if kind == K_MOVE {
            Some(Action::Move(d))
        } else {
            Some(Action::Turn(d))
        };
    }
    if kind == K_WAIT {
        return if arg == 0 {
            Some(Action::Wait)
        } else {
            None
        };
    }
    if kind == K_ATTACK || kind == K_INTERACT {
        let value: u16 = match arg.try_into() {
            Some(v) => v,
            None => { return None; },
        };
        return if kind == K_ATTACK {
            Some(Action::Attack(value))
        } else {
            Some(Action::Interact(value))
        };
    }
    if kind == K_SKILL {
        let (rest, slot) = DivRem::div_rem(arg, 8);
        let (value, flag) = DivRem::div_rem(rest, 2);
        let value: u16 = match value.try_into() {
            Some(v) => v,
            None => { return None; },
        };
        let target = if flag == 0 {
            Target::Entity(value)
        } else {
            Target::Tile(value)
        };
        return Some(Action::Skill((slot.try_into().unwrap(), target)));
    }
    if kind == K_ITEM {
        let (value, slot) = DivRem::div_rem(arg, 4);
        let value: u16 = match value.try_into() {
            Some(v) => v,
            None => { return None; },
        };
        return Some(Action::Item((slot.try_into().unwrap(), value)));
    }
    None
}

/// The batch felt of 1 to 10 actions; `None` for an empty or longer batch, or an action out of
/// range.
pub fn encode_batch(actions: Span<Action>) -> Option<felt252> {
    let count = actions.len();
    if count == 0 || count > MAX_ACTIONS.into() {
        return None;
    }
    let mut low: u128 = count.into();
    let mut high: u128 = 0;
    let mut factor: u128 = 0x10;
    let mut i: u32 = 0;
    for action in actions {
        if i == 5 {
            factor = 1;
        }
        let code: u128 = match encode_action(*action) {
            Some(code) => code.into(),
            None => { return None; },
        };
        if i < 5 {
            low += code * factor;
        } else {
            high += code * factor;
        }
        factor *= P24;
        i += 1;
    }
    Some(low.into() + high.into() * TWO_POW_128)
}

/// The actions of a batch felt, in order; `None` for a count of 0 or above 10, a malformed
/// action, or bits set beyond the count (a batch has one encoding).
pub fn decode_batch(batch: felt252) -> Option<Array<Action>> {
    let wide: u256 = batch.into();
    let (mut rest, count) = DivRem::div_rem(wide.low, 0x10);
    if count == 0 || count > MAX_ACTIONS.into() {
        return None;
    }
    let s24: NonZero<u128> = P24.try_into().unwrap();
    let mut high = wide.high;
    let mut out: Array<Action> = array![];
    let mut i: u128 = 0;
    let mut valid = true;
    while i != count {
        if i == 5 {
            if rest != 0 {
                valid = false;
                break;
            }
            rest = high;
            high = 0;
        }
        let (next, code) = DivRem::div_rem(rest, s24);
        match decode_action(code.try_into().unwrap()) {
            Some(action) => out.append(action),
            None => {
                valid = false;
                break;
            },
        }
        rest = next;
        i += 1;
    }
    if !valid || rest != 0 || high != 0 {
        return None;
    }
    Some(out)
}
