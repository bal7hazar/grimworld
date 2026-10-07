//! ADR-0008's rules 1–3 on the spike's check: the level kept beside the position, the climb, the
//! walk along the deck, the descent, the passage under, the cut, the railings, the two levels'
//! occupancy apart, and the check with no deck equal to the one-level check on every tile.

use hexx::board::direction::Direction;
use spk18::level::{DECK, GROUND, GoblinPlaceTrait, MemberPlaceTrait, Place};
use spk18::movement::{BridgedTrait, GroundTrait};
use crate::fixtures::{at, deck, ends, long, next, plain, river, road};

/// A stored word: `LIVE`, bits 136–159 set (`0xabcdef`) and the low bits `0x123`.
const WORD: felt252 = 0x40000000000000000000000abcdef0000000000000000000000000000000123;

#[test]
fn test_member_level_round_trip() {
    let from = Place { x: 0, y: 0, facing: 0, level: GROUND };
    let to = Place { x: 120, y: 37, facing: 4, level: DECK };
    let base = WORD - 0x123;
    let word = MemberPlaceTrait::moved_level(base, from, to);
    assert(MemberPlaceTrait::place_level(word) == to, 'member: deck');
    // Today's read sees the same tile and facing, and leaves the level out
    assert(MemberPlaceTrait::place(word) == Place { level: GROUND, ..to }, 'member: today');
    // Back to the ground: the word is the one before the move but for the tile
    let back = Place { level: GROUND, ..to };
    let word = MemberPlaceTrait::moved_level(word, to, back);
    assert(MemberPlaceTrait::place_level(word) == back, 'member: ground');
    assert(word == MemberPlaceTrait::moved(base, from, back), 'member: no other bit');
}

#[test]
fn test_goblin_level_round_trip() {
    let from = GoblinPlaceTrait::place_level(WORD);
    assert(from == Place { x: 0x23, y: 0x1, facing: 0, level: GROUND }, 'goblin: read');
    let to = Place { x: 200, y: 224, facing: 5, level: DECK };
    let word = GoblinPlaceTrait::moved_level(WORD, from, to);
    assert(GoblinPlaceTrait::place_level(word) == to, 'goblin: deck');
    assert(GoblinPlaceTrait::place(word) == Place { level: GROUND, ..to }, 'goblin: today');
    let word = GoblinPlaceTrait::moved_level(word, to, from);
    assert(word == WORD, 'goblin: back');
}

#[test]
fn test_no_deck_is_one_level() {
    // With no deck in the window, the two-level check is the one-level check, on every tile and
    // in every direction
    let (bridged, ground) = plain();
    for tile in 0..240_u8 {
        for facing in 0..6_u8 {
            let one = ground.step(tile, facing);
            let two = bridged.step(tile, GROUND, facing);
            match one {
                Some(to) => assert(two == Some((to, GROUND)), 'same move'),
                None => assert(two.is_none(), 'same refusal'),
            }
        }
    }
}

#[test]
fn test_climb_and_descend() {
    let board = road([].span(), [].span());
    let (south, north) = ends();
    // From the southern end, North-East onto the deck: the climb
    assert(board.step(south, GROUND, 1) == Some((deck(), DECK)), 'climb from south');
    // From the northern end, South-East onto the deck
    assert(board.step(north, GROUND, 5) == Some((deck(), DECK)), 'climb from north');
    // On the deck, down to either end
    assert(board.step(deck(), DECK, 2) == Some((north, GROUND)), 'descend north');
    assert(board.step(deck(), DECK, 4) == Some((south, GROUND)), 'descend south');
}

#[test]
fn test_railings() {
    // On the deck, every direction but the two ends is refused, the ground beneath walkable or not
    let road = road([].span(), [].span());
    let river = river();
    for facing in array![0_u8, 1, 3, 5] {
        assert(road.step(deck(), DECK, facing).is_none(), 'road: railing');
        assert(river.step(deck(), DECK, facing).is_none(), 'river: railing');
    }
}

#[test]
fn test_under() {
    // Over a road, the deck's tile is passed under from its other neighbours
    let board = road([].span(), [].span());
    let east = next(deck(), Direction::East);
    let west = next(deck(), Direction::West);
    assert(board.step(east, GROUND, 3) == Some((deck(), GROUND)), 'under from east');
    assert(board.step(deck(), GROUND, 3) == Some((west, GROUND)), 'under to west');
    // Over a river, the ground beneath is a wall
    assert(river().step(east, GROUND, 3).is_none(), 'river: no under');
    // The climb is still there
    let (south, _) = ends();
    assert(river().step(south, GROUND, 1) == Some((deck(), DECK)), 'river: climb');
}

#[test]
fn test_cut() {
    // Under the deck, the step to an end is refused: that edge is the climb's
    let board = road([].span(), [].span());
    assert(board.step(deck(), GROUND, 4).is_none(), 'cut south');
    assert(board.step(deck(), GROUND, 2).is_none(), 'cut north');
}

#[test]
fn test_levels_occupied_apart() {
    let (south, _) = ends();
    let east = next(deck(), Direction::East);
    // Someone on the deck: the climb is refused, the passage under is not
    let board = road([].span(), [deck()].span());
    assert(board.step(south, GROUND, 1).is_none(), 'deck taken');
    assert(board.step(east, GROUND, 3) == Some((deck(), GROUND)), 'under while aloft');
    // Someone under the deck: the climb is not refused, the passage under is
    let board = road([deck()].span(), [].span());
    assert(board.step(south, GROUND, 1) == Some((deck(), DECK)), 'climb while under');
    assert(board.step(east, GROUND, 3).is_none(), 'under taken');
    // An end taken: the descent to it is refused
    let board = road([south].span(), [].span());
    assert(board.step(deck(), DECK, 4).is_none(), 'end taken');
}

#[test]
fn test_along_a_long_deck() {
    let (board, second, north) = long();
    let (south, _) = ends();
    assert(board.step(south, GROUND, 1) == Some((deck(), DECK)), 'climb');
    assert(board.step(deck(), DECK, 1) == Some((second, DECK)), 'along');
    assert(board.step(second, DECK, 2) == Some((north, GROUND)), 'descend');
    assert(board.step(second, DECK, 4) == Some((deck(), DECK)), 'back along');
    // The southern end is not next to the second tile: no descent there
    assert(board.step(second, DECK, 0).is_none(), 'railing');
}

#[test]
fn test_ring_and_window_edge() {
    // A Move off the window is refused on both checks
    let (bridged, ground) = plain();
    assert(ground.step(at(0, 0), 4).is_none(), 'off the window');
    assert(bridged.step(at(0, 0), GROUND, 4).is_none(), 'off the window, two');
}

#[test]
#[should_panic(expected: 'movement: facing')]
fn test_facing_refused() {
    let (bridged, _) = plain();
    let _ = bridged.step(at(7, 7), GROUND, 6);
}
