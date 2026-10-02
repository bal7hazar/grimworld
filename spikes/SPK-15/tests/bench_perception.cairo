// Perception (ENG-07's step 0), fix loop 1 (findings 1 and 4): the awake set's selection over 100
// candidates, every one Alerted and alive, in four states, on three representations and two
// selections, each a pair against its representation's fixture:
// - `main`: main's `TickTrait::awake` on main's `World` (as it stands);
// - `decoded_scan`: the same code copied verbatim (`spk15::perception`), on the same goblins: it
//   checks the copy against main;
// - `decoded_single`: main's representation with the one-pass selection: **L4 alone**;
// - `lazy_scan`: the frozen goblins kept as words with main's 8 scans: **L1 alone**;
// - `lazy_single`: the words with the one-pass selection: **L1 and L4 together**.
// The states: `formed` (no prior set, distances falling: the last 8 woken, each decoded with L1);
// `kept_end` (the last 8 awake and kept); `kept_start` (the first 8 awake and kept, distances
// rising: ENG-01 §9.2's maximum for main, 4,663,510); `replaced` (the first 8 awake, distances
// falling: all 8 put to sleep, encoded with L1, and the last 8 woken, decoded with L1).
use grimworld_logic::models::goblin::{Goblin, GoblinTrait, GoblinWords};
use grimworld_logic::types::tick::{ContentTrait, Index, Sheets};
use grimworld_logic::types::world::{TickTrait, Words, World, WorldTrait};
use spk15::perception::{Decoded, DecodedTrait};
use spk15::words::{Lazy, LazyTrait};
use crate::fixtures::{goblin_words, worst_content};

const FORMED: u8 = 0;
const KEPT_END: u8 = 1;
const KEPT_START: u8 = 2;
const REPLACED: u8 = 3;

/// The 100 candidates' words, the prior set of `state` awake.
fn candidate_words(state: u8) -> Array<GoblinWords> {
    let mut words = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let awake = if state == KEPT_END {
            i >= 92
        } else if state == KEPT_START || state == REPLACED {
            i < 8
        } else {
            false
        };
        words.append(goblin_words(8 + i, awake, 280, 0, 0));
        i += 1;
    }
    words
}

/// Falling along the array (the last 8 nearest), or rising for `KEPT_START` (the first 8).
fn distances(state: u8) -> Span<u16> {
    let mut distances = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let distance = if state == KEPT_START {
            100 + i
        } else {
            200 - i
        };
        distances.append(distance);
        i += 1;
    }
    distances.span()
}

fn decoded_goblins(state: u8) -> Array<Goblin> {
    let (sheets, mut index) = worst_content(3).index();
    let mut goblins = array![];
    for words in candidate_words(state) {
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
    }
    goblins
}

fn main_state(state: u8) -> (World, Span<u16>) {
    (WorldTrait::new(49, array![], decoded_goblins(state), array![], false), distances(state))
}

fn decoded_state(state: u8) -> (Decoded, Span<u16>) {
    (DecodedTrait::new(decoded_goblins(state)), distances(state))
}

fn lazy_state(state: u8) -> (Lazy, Sheets, Index, Span<u16>) {
    let words = Words {
        clock: 49,
        members: array![],
        goblins: candidate_words(state),
        killed: array![],
        defeated: false,
    };
    let (lazy, sheets, index) = LazyTrait::lazy_load(words, @worst_content(3));
    (lazy, sheets, index, distances(state))
}

fn main_fixture(state: u8) {
    let (world, distances) = main_state(state);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

fn main_pair(state: u8) {
    let (mut world, distances) = main_state(state);
    TickTrait::awake(ref world, distances);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

fn decoded_fixture(state: u8) {
    let (decoded, distances) = decoded_state(state);
    assert(decoded.goblins.len() == 100 && distances.len() == 100, 'fixture');
}

fn decoded_scan(state: u8) {
    let (mut decoded, distances) = decoded_state(state);
    decoded.awake_scan(distances);
    assert(decoded.goblins.len() == 100 && distances.len() == 100, 'fixture');
}

fn decoded_single(state: u8) {
    let (mut decoded, distances) = decoded_state(state);
    decoded.awake_single(distances);
    assert(decoded.goblins.len() == 100 && distances.len() == 100, 'fixture');
}

fn lazy_fixture(state: u8) {
    let (lazy, _sheets, _index, distances) = lazy_state(state);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

fn lazy_scan(state: u8) {
    let (mut lazy, sheets, mut index, distances) = lazy_state(state);
    lazy.awake(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

fn lazy_single(state: u8) {
    let (mut lazy, sheets, mut index, distances) = lazy_state(state);
    lazy.awake_single(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

/// Every variant chooses main's set, its values and its flags; with words, every goblin is stored
/// as the words it came with, its flag as main's (not a cost test).
fn agree(state: u8) {
    let (mut world, distances) = main_state(state);
    TickTrait::awake(ref world, distances);
    let mut scan = DecodedTrait::new(decoded_goblins(state));
    scan.awake_scan(distances);
    let mut single = DecodedTrait::new(decoded_goblins(state));
    single.awake_single(distances);
    let (mut lazy, sheets, mut index, _) = lazy_state(state);
    lazy.awake(distances, ref index, @sheets);
    let (mut lazy1, sheets1, mut index1, _) = lazy_state(state);
    lazy1.awake_single(distances, ref index1, @sheets1);
    let woken = world.woken();
    assert(scan.woken == woken && single.woken == woken, 'decoded: the same set');
    assert(lazy.woken == woken && lazy1.woken == woken, 'words: the same set');
    let mut i = 0;
    while i < 100 {
        let expected = world.goblin(i);
        assert(scan.goblin(i) == expected && single.goblin(i) == expected, 'decoded: values');
        assert(*lazy.words[i].awake == expected.awake, 'words: flags');
        assert(*lazy1.words[i].awake == expected.awake, 'words single: flags');
        i += 1;
    }
    let mut k = 0;
    for i in woken {
        let expected = world.goblin(*i);
        assert(*lazy.awake[k] == expected && *lazy1.awake[k] == expected, 'words: values');
        k += 1;
    }
    let before = candidate_words(state);
    let stored = lazy1.lazy_store();
    let mut i = 0;
    while i < 100 {
        assert(*stored.goblins[i].state == *before[i].state, 'words: stored unchanged');
        assert(*stored.goblins[i].awake == world.goblin(i).awake, 'words: flags stored');
        i += 1;
    }
}

// ---------------------------------------------------------------------------------------------
// Formed.

#[test]
#[available_gas(l2_gas: 8840118)] // ceil(1.05 × 8419160 measured)
fn test_perc_main_formed_fixture() {
    main_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 13565139)] // ceil(1.05 × 12919180 measured)
fn test_pair_perc_main_formed() {
    main_pair(FORMED);
}

#[test]
#[available_gas(l2_gas: 8828285)] // ceil(1.05 × 8407890 measured)
fn test_perc_decoded_formed_fixture() {
    decoded_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 13549841)] // ceil(1.05 × 12904610 measured)
fn test_pair_perc_decoded_scan_formed() {
    decoded_scan(FORMED);
}

#[test]
#[available_gas(l2_gas: 11983283)] // ceil(1.05 × 11412650 measured)
fn test_pair_perc_decoded_single_formed() {
    decoded_single(FORMED);
}

#[test]
#[available_gas(l2_gas: 3050450)] // ceil(1.05 × 2905190 measured)
fn test_perc_lazy_formed_fixture() {
    lazy_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 8740599)] // ceil(1.05 × 8324380 measured)
fn test_pair_perc_lazy_scan_formed() {
    lazy_scan(FORMED);
}

#[test]
#[available_gas(l2_gas: 6819561)] // ceil(1.05 × 6494820 measured)
fn test_pair_perc_lazy_single_formed() {
    lazy_single(FORMED);
}

#[test]
#[available_gas(l2_gas: 69728096)] // ceil(1.05 × 66407710 measured)
fn test_perc_agree_formed() {
    agree(FORMED);
}

// ---------------------------------------------------------------------------------------------
// Kept, the set at the array's end.

#[test]
#[available_gas(l2_gas: 8874191)] // ceil(1.05 × 8451610 measured)
fn test_perc_main_kept_end_fixture() {
    main_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 13661792)] // ceil(1.05 × 13011230 measured)
fn test_pair_perc_main_kept_end() {
    main_pair(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 8862357)] // ceil(1.05 × 8440340 measured)
fn test_perc_decoded_kept_end_fixture() {
    decoded_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 13646493)] // ceil(1.05 × 12996660 measured)
fn test_pair_perc_decoded_scan_kept_end() {
    decoded_scan(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 12079935)] // ceil(1.05 × 11504700 measured)
fn test_pair_perc_decoded_single_kept_end() {
    decoded_single(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 3547194)] // ceil(1.05 × 3378280 measured)
fn test_perc_lazy_kept_end_fixture() {
    lazy_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 8901050)] // ceil(1.05 × 8477190 measured)
fn test_pair_perc_lazy_scan_kept_end() {
    lazy_scan(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 7011764)] // ceil(1.05 × 6677870 measured)
fn test_pair_perc_lazy_single_kept_end() {
    lazy_single(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 70387139)] // ceil(1.05 × 67035370 measured)
fn test_perc_agree_kept_end() {
    agree(KEPT_END);
}

// ---------------------------------------------------------------------------------------------
// Kept, the set at the array's start, distances rising (ENG-01's maximum for main).

#[test]
#[available_gas(l2_gas: 8929085)] // ceil(1.05 × 8503890 measured)
fn test_perc_main_kept_start_fixture() {
    main_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 13724708)] // ceil(1.05 × 13071150 measured)
fn test_pair_perc_main_kept_start() {
    main_pair(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 8917251)] // ceil(1.05 × 8492620 measured)
fn test_perc_decoded_kept_start_fixture() {
    decoded_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 13709409)] // ceil(1.05 × 13056580 measured)
fn test_pair_perc_decoded_scan_kept_start() {
    decoded_scan(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 11527509)] // ceil(1.05 × 10978580 measured)
fn test_pair_perc_decoded_single_kept_start() {
    decoded_single(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 3602088)] // ceil(1.05 × 3430560 measured)
fn test_perc_lazy_kept_start_fixture() {
    lazy_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 8860604)] // ceil(1.05 × 8438670 measured)
fn test_pair_perc_lazy_scan_kept_start() {
    lazy_scan(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 6355976)] // ceil(1.05 × 6053310 measured)
fn test_pair_perc_lazy_single_kept_start() {
    lazy_single(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 69288020)] // ceil(1.05 × 65988590 measured)
fn test_perc_agree_kept_start() {
    agree(KEPT_START);
}

// ---------------------------------------------------------------------------------------------
// Replaced: the first 8 put to sleep, the last 8 woken.

#[test]
#[available_gas(l2_gas: 8938640)] // ceil(1.05 × 8512990 measured)
fn test_perc_main_replaced_fixture() {
    main_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 13725317)] // ceil(1.05 × 13071730 measured)
fn test_pair_perc_main_replaced() {
    main_pair(REPLACED);
}

#[test]
#[available_gas(l2_gas: 8926806)] // ceil(1.05 × 8501720 measured)
fn test_perc_decoded_replaced_fixture() {
    decoded_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 13710018)] // ceil(1.05 × 13057160 measured)
fn test_pair_perc_decoded_scan_replaced() {
    decoded_scan(REPLACED);
}

#[test]
#[available_gas(l2_gas: 12143460)] // ceil(1.05 × 11565200 measured)
fn test_pair_perc_decoded_single_replaced() {
    decoded_single(REPLACED);
}

#[test]
#[available_gas(l2_gas: 3611643)] // ceil(1.05 × 3439660 measured)
fn test_perc_lazy_replaced_fixture() {
    lazy_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 9436781)] // ceil(1.05 × 8987410 measured)
fn test_pair_perc_lazy_scan_replaced() {
    lazy_scan(REPLACED);
}

#[test]
#[available_gas(l2_gas: 7547495)] // ceil(1.05 × 7188090 measured)
fn test_pair_perc_lazy_single_replaced() {
    lazy_single(REPLACED);
}

#[test]
#[available_gas(l2_gas: 71713625)] // ceil(1.05 × 68298690 measured)
fn test_perc_agree_replaced() {
    agree(REPLACED);
}
