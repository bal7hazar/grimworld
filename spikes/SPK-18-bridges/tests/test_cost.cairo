//! The costs of ENG-08b deliverable 2: one call is the difference between `test_twice_<what>` and
//! `test_once_<what>` (`pairs.py`; ENG-02's method, `types/window.cairo`), the inputs opaque to
//! the compiler. The movement check on one level (the base: ENG-07's check as D-225 briefs it,
//! prototyped here) and on two, by case; the level's read and write beside a position's.

use spk18::level::{DECK, GROUND, GoblinPlaceTrait, MemberPlaceTrait, Place};
use spk18::movement::{Bridged, BridgedTrait, Ground, GroundTrait};
use crate::fixtures::{at, bench_ground, bench_plain, bench_road, deck, ends, opaque, opaque_word};

const WORD: felt252 = 0x40000000000000000000000abcdef0000000000000000000000000000000123;

// ---- The movement check ----

// One level: a walkable tile, East
#[test]
fn test_once_ground_step() {
    let board = bench_ground();
    assert(board.step(opaque(at(7, 8)), opaque(0)).is_some(), 'step');
}

#[test]
fn test_twice_ground_step() {
    let board = bench_ground();
    assert(board.step(opaque(at(7, 8)), opaque(0)).is_some(), 'step');
    assert(board.step(opaque(at(6, 8)), opaque(3)).is_some(), 'step');
}

// Two levels, no deck in the window (every generated chunk)
#[test]
fn test_once_bridged_none() {
    let board = bench_plain();
    assert(board.step(opaque(at(7, 8)), opaque(GROUND), opaque(0)).is_some(), 'step');
}

#[test]
fn test_twice_bridged_none() {
    let board = bench_plain();
    assert(board.step(opaque(at(7, 8)), opaque(GROUND), opaque(0)).is_some(), 'step');
    assert(board.step(opaque(at(6, 8)), opaque(GROUND), opaque(3)).is_some(), 'step');
}

// Two levels, a deck in the window, a ground step away from it (the longest ground path: the
// climb's and the cut's tests, then `Ground`'s)
#[test]
fn test_once_bridged_ground() {
    let board = bench_road();
    assert(board.step(opaque(at(3, 4)), opaque(GROUND), opaque(0)).is_some(), 'step');
}

#[test]
fn test_twice_bridged_ground() {
    let board = bench_road();
    assert(board.step(opaque(at(3, 4)), opaque(GROUND), opaque(0)).is_some(), 'step');
    assert(board.step(opaque(at(2, 4)), opaque(GROUND), opaque(3)).is_some(), 'step');
}

// The passage under the deck (East neighbour, West)
#[test]
fn test_once_bridged_under() {
    let board = bench_road();
    assert(board.step(opaque(at(6, 8)), opaque(GROUND), opaque(3)).is_some(), 'step');
}

#[test]
fn test_twice_bridged_under() {
    let board = bench_road();
    assert(board.step(opaque(at(6, 8)), opaque(GROUND), opaque(3)).is_some(), 'step');
    assert(board.step(opaque(deck()), opaque(GROUND), opaque(3)).is_some(), 'step');
}

// The climb (from the southern end, North-East)
#[test]
fn test_once_bridged_climb() {
    let board = bench_road();
    let (south, _) = ends();
    assert(board.step(opaque(south), opaque(GROUND), opaque(1)).is_some(), 'step');
}

#[test]
fn test_twice_bridged_climb() {
    let board = bench_road();
    let (south, north) = ends();
    assert(board.step(opaque(south), opaque(GROUND), opaque(1)).is_some(), 'step');
    assert(board.step(opaque(north), opaque(GROUND), opaque(5)).is_some(), 'step');
}

// The descent (from the deck to the northern end, then the southern one)
#[test]
fn test_once_bridged_descend() {
    let board = bench_road();
    assert(board.step(opaque(deck()), opaque(DECK), opaque(2)).is_some(), 'step');
}

#[test]
fn test_twice_bridged_descend() {
    let board = bench_road();
    assert(board.step(opaque(deck()), opaque(DECK), opaque(2)).is_some(), 'step');
    assert(board.step(opaque(deck()), opaque(DECK), opaque(4)).is_some(), 'step');
}

// The branch on "a deck in the window" taken by the caller, around the two checks: does the
// one-level path then cost the one-level check? (Sierra charges a branch's merge at its dearest
// side; the figure says whether a per-move branch saves anything.)
fn either(ground: @Ground, bridged: @Bridged, from: u8, level: u8, facing: u8) -> Option<(u8, u8)> {
    if *bridged.deck == 0 {
        match ground.step(from, facing) {
            Some(to) => Some((to, GROUND)),
            None => None,
        }
    } else {
        bridged.step(from, level, facing)
    }
}

#[test]
fn test_once_either_none() {
    let ground = bench_ground();
    let bridged = bench_plain();
    assert(
        either(@ground, @bridged, opaque(at(7, 8)), opaque(GROUND), opaque(0)).is_some(), 'step',
    );
}

#[test]
fn test_twice_either_none() {
    let ground = bench_ground();
    let bridged = bench_plain();
    assert(
        either(@ground, @bridged, opaque(at(7, 8)), opaque(GROUND), opaque(0)).is_some(), 'step',
    );
    assert(
        either(@ground, @bridged, opaque(at(6, 8)), opaque(GROUND), opaque(3)).is_some(), 'step',
    );
}

#[test]
fn test_once_either_climb() {
    let ground = bench_ground();
    let bridged = bench_road();
    let (south, _) = ends();
    assert(either(@ground, @bridged, opaque(south), opaque(GROUND), opaque(1)).is_some(), 'step');
}

#[test]
fn test_twice_either_climb() {
    let ground = bench_ground();
    let bridged = bench_road();
    let (south, north) = ends();
    assert(either(@ground, @bridged, opaque(south), opaque(GROUND), opaque(1)).is_some(), 'step');
    assert(either(@ground, @bridged, opaque(north), opaque(GROUND), opaque(5)).is_some(), 'step');
}

// ---- The level in a position ----

#[test]
fn test_once_member_place() {
    let place = MemberPlaceTrait::place(opaque_word(WORD));
    assert(place.facing == 0, 'read');
}

#[test]
fn test_twice_member_place() {
    let place = MemberPlaceTrait::place(opaque_word(WORD));
    assert(place.facing == 0, 'read');
    let place = MemberPlaceTrait::place(opaque_word(WORD + 1));
    assert(place.facing == 0, 'read');
}

#[test]
fn test_once_member_place_level() {
    let place = MemberPlaceTrait::place_level(opaque_word(WORD));
    assert(place.level == GROUND, 'read');
}

#[test]
fn test_twice_member_place_level() {
    let place = MemberPlaceTrait::place_level(opaque_word(WORD));
    assert(place.level == GROUND, 'read');
    let place = MemberPlaceTrait::place_level(opaque_word(WORD + 1));
    assert(place.level == GROUND, 'read');
}

fn moves() -> (Place, Place) {
    (
        Place { x: opaque(10), y: opaque(20), facing: opaque(0), level: opaque(GROUND) },
        Place { x: opaque(11), y: opaque(20), facing: opaque(3), level: opaque(DECK) },
    )
}

#[test]
fn test_once_member_moved() {
    let (from, to) = moves();
    assert(MemberPlaceTrait::moved(opaque_word(WORD), from, to) != 0, 'write');
}

#[test]
fn test_twice_member_moved() {
    let (from, to) = moves();
    assert(MemberPlaceTrait::moved(opaque_word(WORD), from, to) != 0, 'write');
    assert(MemberPlaceTrait::moved(opaque_word(WORD + 1), to, from) != 0, 'write');
}

#[test]
fn test_once_member_moved_level() {
    let (from, to) = moves();
    assert(MemberPlaceTrait::moved_level(opaque_word(WORD), from, to) != 0, 'write');
}

#[test]
fn test_twice_member_moved_level() {
    let (from, to) = moves();
    assert(MemberPlaceTrait::moved_level(opaque_word(WORD), from, to) != 0, 'write');
    assert(MemberPlaceTrait::moved_level(opaque_word(WORD + 1), to, from) != 0, 'write');
}

#[test]
fn test_once_goblin_place() {
    let place = GoblinPlaceTrait::place(opaque_word(WORD));
    assert(place.facing == 0, 'read');
}

#[test]
fn test_twice_goblin_place() {
    let place = GoblinPlaceTrait::place(opaque_word(WORD));
    assert(place.facing == 0, 'read');
    let place = GoblinPlaceTrait::place(opaque_word(WORD + 1));
    assert(place.facing == 0, 'read');
}

#[test]
fn test_once_goblin_place_level() {
    let place = GoblinPlaceTrait::place_level(opaque_word(WORD));
    assert(place.level == GROUND, 'read');
}

#[test]
fn test_twice_goblin_place_level() {
    let place = GoblinPlaceTrait::place_level(opaque_word(WORD));
    assert(place.level == GROUND, 'read');
    let place = GoblinPlaceTrait::place_level(opaque_word(WORD + 1));
    assert(place.level == GROUND, 'read');
}

#[test]
fn test_once_goblin_moved() {
    let (from, to) = moves();
    assert(GoblinPlaceTrait::moved(opaque_word(WORD), from, to) != 0, 'write');
}

#[test]
fn test_twice_goblin_moved() {
    let (from, to) = moves();
    assert(GoblinPlaceTrait::moved(opaque_word(WORD), from, to) != 0, 'write');
    assert(GoblinPlaceTrait::moved(opaque_word(WORD + 1), to, from) != 0, 'write');
}

#[test]
fn test_once_goblin_moved_level() {
    let (from, to) = moves();
    assert(GoblinPlaceTrait::moved_level(opaque_word(WORD), from, to) != 0, 'write');
}

#[test]
fn test_twice_goblin_moved_level() {
    let (from, to) = moves();
    assert(GoblinPlaceTrait::moved_level(opaque_word(WORD), from, to) != 0, 'write');
    assert(GoblinPlaceTrait::moved_level(opaque_word(WORD + 1), to, from) != 0, 'write');
}
