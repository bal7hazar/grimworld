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

use crate::constants::MAX_ACTIONS;
use crate::helpers::packing::{P24, TWO_POW_128};
use crate::types::{Target, Tile};

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

/// One action's 24 bits.
#[generate_trait]
pub impl ActionCodeImpl of ActionCodeTrait {
    /// The 24 bits of an action; `None` for a direction above 5, a bar slot above 7 or a belt slot
    /// above 3: the encoder refuses what the decoder would refuse, so that no out-of-range value
    /// spills into a neighbouring field (ENG-01 fix loop 1, F-10).
    fn encode(action: Action) -> Option<u32> {
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
    fn decode(code: u32) -> Option<Action> {
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
}

/// The batch felt.
#[generate_trait]
pub impl BatchImpl of BatchTrait {
    /// The batch felt of 1 to 10 actions; `None` for an empty or longer batch, or an action out of
    /// range.
    fn encode(actions: Span<Action>) -> Option<felt252> {
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
            let code: u128 = match ActionCodeTrait::encode(*action) {
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
    fn decode(batch: felt252) -> Option<Array<Action>> {
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
            match ActionCodeTrait::decode(code.try_into().unwrap()) {
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
}

/// The wire format's unit tests (docs/architecture/ENG-01-interfaces.md, *play*).
#[cfg(test)]
mod tests {
    use crate::types::Target;
    use super::{Action, ActionCodeTrait, BatchTrait};

    fn ten() -> Array<Action> {
        array![
            Action::Move(0), Action::Turn(5), Action::Wait, Action::Attack(0xFFFF),
            Action::Skill((7, Target::Tile(0xFFFF))), Action::Item((3, 0xFFFF)),
            Action::Interact(0xE0E0), Action::Skill((0, Target::Entity(9))), Action::Move(5),
            Action::Attack(8),
        ]
    }

    // Every kind, every argument at its widest, ten actions: decoding gives them back in order.
    #[test]
    #[available_gas(l2_gas: 378557)] // ceil(1.05 × 360530 measured)
    fn test_batch_round_trip() {
        let actions = ten();
        let word = BatchTrait::encode(actions.span()).unwrap();
        assert(BatchTrait::decode(word).unwrap() == actions, 'round trip');
    }

    // The layout pinned: count at bits 0-3, action i at 4 + 24 i (i < 5), then 128 + 24 (i - 5).
    #[test]
    #[available_gas(l2_gas: 118419)] // ceil(1.05 × 112780 measured)
    fn test_batch_layout() {
        // Move East = 0; Attack 9 = 3 + 9 × 8; Skill slot 2 on tile 300 = 4 + 2 × 8 + 64 + 300 ×
        // 128;
        // Item slot 1 on entity 8 = 5 + 8 + 8 × 32; Interact tile 5 = 6 + 5 × 8; Wait = 2.
        let actions = array![
            Action::Move(0), Action::Attack(9), Action::Skill((2, Target::Tile(300))),
            Action::Item((1, 8)), Action::Interact(5), Action::Wait,
        ];
        let word = BatchTrait::encode(actions.span()).unwrap();
        let two_128: felt252 = 0x100000000000000000000000000000000;
        let expected: felt252 = 6
            + 0 * 0x10
            + (3 + 9 * 8) * 0x10000000 // bit 28
            + (4 + 2 * 8 + 64 + 300 * 128) * 0x10000000000000 // bit 52
            + (5 + 8 + 8 * 32) * 0x10000000000000000000 // bit 76
            + (6 + 5 * 8) * 0x10000000000000000000000000 // bit 100
            + 2 * two_128;
        assert(word == expected, 'layout');
        assert(ActionCodeTrait::encode(Action::Turn(3)) == Some(1 + 3 * 8), 'turn');
    }

    // One encoding per batch: counts out of 1-10, bits beyond the count, bad arguments are refused.
    #[test]
    #[available_gas(l2_gas: 99624)] // ceil(1.05 × 94880 measured)
    fn test_batch_refusals() {
        assert(BatchTrait::encode(array![].span()).is_none(), 'empty encoded');
        let mut eleven = ten();
        eleven.append(Action::Wait);
        assert(BatchTrait::encode(eleven.span()).is_none(), 'eleven encoded');
        assert(BatchTrait::decode(0).is_none(), 'count 0');
        assert(BatchTrait::decode(11).is_none(), 'count 11');
        // One Wait, and a stray bit after it.
        assert(BatchTrait::decode(1 + 2 * 0x10 + 0x10000000).is_none(), 'stray bit');
        // A move in direction 6.
        assert(BatchTrait::decode(1 + 6 * 8 * 0x10).is_none(), 'direction 6');
        // Kind 7 does not exist.
        assert(BatchTrait::decode(1 + 7 * 0x10).is_none(), 'kind 7');
        // Wait with an argument.
        assert(BatchTrait::decode(1 + (2 + 8) * 0x10).is_none(), 'wait argument');
    }

    // The encoder refuses what the decoder refuses: a direction above 5, a bar slot above 7, a belt
    // slot above 3 (fix loop 1, F-10); one bad action refuses the whole batch.
    #[test]
    #[available_gas(l2_gas: 34409)] // ceil(1.05 × 32770 measured)
    fn test_encoder_refusals() {
        assert(ActionCodeTrait::encode(Action::Move(6)).is_none(), 'move 6');
        assert(ActionCodeTrait::encode(Action::Turn(255)).is_none(), 'turn 255');
        assert(
            ActionCodeTrait::encode(Action::Skill((8, Target::Entity(1)))).is_none(),
            'skill slot 8',
        );
        assert(ActionCodeTrait::encode(Action::Item((4, 1))).is_none(), 'belt slot 4');
        assert(ActionCodeTrait::encode(Action::Move(5)).is_some(), 'move 5');
        assert(
            ActionCodeTrait::encode(Action::Skill((7, Target::Tile(0xFFFF)))).is_some(),
            'skill slot 7',
        );
        assert(ActionCodeTrait::encode(Action::Item((3, 0xFFFF))).is_some(), 'belt slot 3');
        let batch = array![Action::Wait, Action::Item((4, 8))];
        assert(BatchTrait::encode(batch.span()).is_none(), 'batch with a bad action');
    }
}
