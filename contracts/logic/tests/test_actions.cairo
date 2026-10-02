// The wire format of a played batch (docs/architecture/ENG-01-interfaces.md, *play*).
use grimworld_logic::actions::{Action, decode_batch, encode_action, encode_batch};
use grimworld_logic::types::Target;

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
    let word = encode_batch(actions.span()).unwrap();
    assert(decode_batch(word).unwrap() == actions, 'round trip');
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
    let word = encode_batch(actions.span()).unwrap();
    let two_128: felt252 = 0x100000000000000000000000000000000;
    let expected: felt252 = 6
        + 0 * 0x10
        + (3 + 9 * 8) * 0x10000000 // bit 28
        + (4 + 2 * 8 + 64 + 300 * 128) * 0x10000000000000 // bit 52
        + (5 + 8 + 8 * 32) * 0x10000000000000000000 // bit 76
        + (6 + 5 * 8) * 0x10000000000000000000000000 // bit 100
        + 2 * two_128;
    assert(word == expected, 'layout');
    assert(encode_action(Action::Turn(3)) == Some(1 + 3 * 8), 'turn');
}

// One encoding per batch: counts out of 1-10, bits beyond the count, bad arguments are refused.
#[test]
#[available_gas(l2_gas: 99624)] // ceil(1.05 × 94880 measured)
fn test_batch_refusals() {
    assert(encode_batch(array![].span()).is_none(), 'empty encoded');
    let mut eleven = ten();
    eleven.append(Action::Wait);
    assert(encode_batch(eleven.span()).is_none(), 'eleven encoded');
    assert(decode_batch(0).is_none(), 'count 0');
    assert(decode_batch(11).is_none(), 'count 11');
    // One Wait, and a stray bit after it.
    assert(decode_batch(1 + 2 * 0x10 + 0x10000000).is_none(), 'stray bit');
    // A move in direction 6.
    assert(decode_batch(1 + 6 * 8 * 0x10).is_none(), 'direction 6');
    // Kind 7 does not exist.
    assert(decode_batch(1 + 7 * 0x10).is_none(), 'kind 7');
    // Wait with an argument.
    assert(decode_batch(1 + (2 + 8) * 0x10).is_none(), 'wait argument');
}

// The encoder refuses what the decoder refuses: a direction above 5, a bar slot above 7, a belt
// slot above 3 (fix loop 1, F-10); one bad action refuses the whole batch.
#[test]
#[available_gas(l2_gas: 34409)] // ceil(1.05 × 32770 measured)
fn test_encoder_refusals() {
    assert(encode_action(Action::Move(6)).is_none(), 'move 6');
    assert(encode_action(Action::Turn(255)).is_none(), 'turn 255');
    assert(encode_action(Action::Skill((8, Target::Entity(1)))).is_none(), 'skill slot 8');
    assert(encode_action(Action::Item((4, 1))).is_none(), 'belt slot 4');
    assert(encode_action(Action::Move(5)).is_some(), 'move 5');
    assert(encode_action(Action::Skill((7, Target::Tile(0xFFFF)))).is_some(), 'skill slot 7');
    assert(encode_action(Action::Item((3, 0xFFFF))).is_some(), 'belt slot 3');
    let batch = array![Action::Wait, Action::Item((4, 8))];
    assert(encode_batch(batch.span()).is_none(), 'batch with a bad action');
}
