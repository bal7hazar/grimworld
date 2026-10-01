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
#[available_gas(l2_gas: 8631935)] // ceil(1.05 × 8220890 measured)
fn test_perc_main_formed_fixture() {
    main_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 13458207)] // ceil(1.05 × 12817340 measured)
fn test_pair_perc_main_formed() {
    main_pair(FORMED);
}

#[test]
#[available_gas(l2_gas: 8624406)] // ceil(1.05 × 8213720 measured)
fn test_perc_decoded_formed_fixture() {
    decoded_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 13447214)] // ceil(1.05 × 12806870 measured)
fn test_pair_perc_decoded_scan_formed() {
    decoded_scan(FORMED);
}

#[test]
#[available_gas(l2_gas: 11880656)] // ceil(1.05 × 11314910 measured)
fn test_pair_perc_decoded_single_formed() {
    decoded_single(FORMED);
}

#[test]
#[available_gas(l2_gas: 2575398)] // ceil(1.05 × 2452760 measured)
fn test_perc_lazy_formed_fixture() {
    lazy_fixture(FORMED);
}

#[test]
#[available_gas(l2_gas: 8242679)] // ceil(1.05 × 7850170 measured)
fn test_pair_perc_lazy_scan_formed() {
    lazy_scan(FORMED);
}

#[test]
#[available_gas(l2_gas: 6321641)] // ceil(1.05 × 6020610 measured)
fn test_pair_perc_lazy_single_formed() {
    lazy_single(FORMED);
}

#[test]
#[available_gas(l2_gas: 68889923)] // ceil(1.05 × 65609450 measured)
fn test_perc_agree_formed() {
    agree(FORMED);
}

// ---------------------------------------------------------------------------------------------
// Kept, the set at the array's end.

#[test]
#[available_gas(l2_gas: 8668527)] // ceil(1.05 × 8255740 measured)
fn test_perc_main_kept_end_fixture() {
    main_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 13557380)] // ceil(1.05 × 12911790 measured)
fn test_pair_perc_main_kept_end() {
    main_pair(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 8660999)] // ceil(1.05 × 8248570 measured)
fn test_perc_decoded_kept_end_fixture() {
    decoded_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 13546386)] // ceil(1.05 × 12901320 measured)
fn test_pair_perc_decoded_scan_kept_end() {
    decoded_scan(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 11979828)] // ceil(1.05 × 11409360 measured)
fn test_pair_perc_decoded_single_kept_end() {
    decoded_single(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 3091211)] // ceil(1.05 × 2944010 measured)
fn test_perc_lazy_kept_end_fixture() {
    lazy_fixture(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 8408169)] // ceil(1.05 × 8007780 measured)
fn test_pair_perc_lazy_scan_kept_end() {
    lazy_scan(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 6518883)] // ceil(1.05 × 6208460 measured)
fn test_pair_perc_lazy_single_kept_end() {
    lazy_single(KEPT_END);
}

#[test]
#[available_gas(l2_gas: 69566606)] // ceil(1.05 × 66253910 measured)
fn test_perc_agree_kept_end() {
    agree(KEPT_END);
}

// ---------------------------------------------------------------------------------------------
// Kept, the set at the array's start, distances rising (ENG-01's maximum for main).

#[test]
#[available_gas(l2_gas: 8723421)] // ceil(1.05 × 8308020 measured)
fn test_perc_main_kept_start_fixture() {
    main_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 13620296)] // ceil(1.05 × 12971710 measured)
fn test_pair_perc_main_kept_start() {
    main_pair(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 8715893)] // ceil(1.05 × 8300850 measured)
fn test_perc_decoded_kept_start_fixture() {
    decoded_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 13609302)] // ceil(1.05 × 12961240 measured)
fn test_pair_perc_decoded_scan_kept_start() {
    decoded_scan(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 11427402)] // ceil(1.05 × 10883240 measured)
fn test_pair_perc_decoded_single_kept_start() {
    decoded_single(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 3146105)] // ceil(1.05 × 2996290 measured)
fn test_perc_lazy_kept_start_fixture() {
    lazy_fixture(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 8367723)] // ceil(1.05 × 7969260 measured)
fn test_pair_perc_lazy_scan_kept_start() {
    lazy_scan(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 5863095)] // ceil(1.05 × 5583900 measured)
fn test_pair_perc_lazy_single_kept_start() {
    lazy_single(KEPT_START);
}

#[test]
#[available_gas(l2_gas: 68467487)] // ceil(1.05 × 65207130 measured)
fn test_perc_agree_kept_start() {
    agree(KEPT_START);
}

// ---------------------------------------------------------------------------------------------
// Replaced: the first 8 put to sleep, the last 8 woken.

#[test]
#[available_gas(l2_gas: 8732976)] // ceil(1.05 × 8317120 measured)
fn test_perc_main_replaced_fixture() {
    main_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 13620905)] // ceil(1.05 × 12972290 measured)
fn test_pair_perc_main_replaced() {
    main_pair(REPLACED);
}

#[test]
#[available_gas(l2_gas: 8725448)] // ceil(1.05 × 8309950 measured)
fn test_perc_decoded_replaced_fixture() {
    decoded_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 13609911)] // ceil(1.05 × 12961820 measured)
fn test_pair_perc_decoded_scan_replaced() {
    decoded_scan(REPLACED);
}

#[test]
#[available_gas(l2_gas: 12043353)] // ceil(1.05 × 11469860 measured)
fn test_pair_perc_decoded_single_replaced() {
    decoded_single(REPLACED);
}

#[test]
#[available_gas(l2_gas: 3155660)] // ceil(1.05 × 3005390 measured)
fn test_perc_lazy_replaced_fixture() {
    lazy_fixture(REPLACED);
}

#[test]
#[available_gas(l2_gas: 8960448)] // ceil(1.05 × 8533760 measured)
fn test_pair_perc_lazy_scan_replaced() {
    lazy_scan(REPLACED);
}

#[test]
#[available_gas(l2_gas: 7071162)] // ceil(1.05 × 6734440 measured)
fn test_pair_perc_lazy_single_replaced() {
    lazy_single(REPLACED);
}

#[test]
#[available_gas(l2_gas: 70926188)] // ceil(1.05 × 67548750 measured)
fn test_perc_agree_replaced() {
    agree(REPLACED);
}
