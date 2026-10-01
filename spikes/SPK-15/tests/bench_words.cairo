// Lever 1: the frozen goblins kept as words (`spk15::words`). Pairs of snforge's totals:
// - load and store, once a call, on CBT-02b's costliest words (`load_words(1)`: 100 goblins, each
//   holding a retained effect, the last 8 awake; main's `test_cost_load_bound` and its fixture),
//   main's `WordsTrait::load` + `WorldStoreTrait::store` against `LazyTrait::load` + `store`, each
//   checking the round trip returns the words it was given; and on the representative words (8
//   goblins, all awake);
// - perception (`awake`, ENG-07's step 0) over 100 candidates: main's `TickTrait::awake` on loaded
//   goblins against `LazyTrait::awake` on words, the set formed from none (8 goblins woken: each is
//   decoded) and kept (the usual tick);
// - a hook touching a frozen goblin (§9.2: up to 6 an action): main's `goblin` + `set_goblin` (the
//   100-goblin array rebuilt) against `LazyTrait::goblin` + `set_frozen`.
use grimworld_logic::models::goblin::{GoblinTrait, GoblinWords};
use grimworld_logic::types::tick::{ContentTrait, Index, Sheets};
use grimworld_logic::types::world::{
    TickTrait, Words, WordsTrait, World, WorldStoreTrait, WorldTrait,
};
use spk15::words::{Lazy, LazyTrait, SelectionTrait};
use crate::fixtures::{goblin_words, load_words, opaque, representative, worst_content};

// ---------------------------------------------------------------------------------------------
// Load and store, the costliest words.

#[test]
fn test_words_bound_fixture() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

#[test]
fn test_pair_words_bound_main() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let (world, _) = WordsTrait::load(words, @content);
    assert(WorldStoreTrait::store(world) == expected, 'round trip');
}

#[test]
fn test_pair_words_bound_lazy() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let (lazy, _sheets, _index) = LazyTrait::lazy_load(words, @content);
    assert(lazy.lazy_store() == expected, 'round trip');
}

// The representative words: 8 goblins, all awake (nothing frozen to keep).
fn representative_words() -> (Words, grimworld_logic::types::tick::Content) {
    let (world, sheets) = representative();
    (WorldStoreTrait::store(world), crate::fixtures::content_of(@sheets))
}

#[test]
fn test_words_representative_fixture() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    assert(words.goblins.len() == expected.goblins.len() && content.castes.len() == 2, 'twice');
}

#[test]
fn test_pair_words_representative_main() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    let (world, _) = WordsTrait::load(words, @content);
    assert(WorldStoreTrait::store(world) == expected, 'round trip');
}

#[test]
fn test_pair_words_representative_lazy() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    let (lazy, _sheets, _index) = LazyTrait::lazy_load(words, @content);
    assert(lazy.lazy_store() == expected, 'round trip');
}

// ---------------------------------------------------------------------------------------------
// Perception over 100 candidates: every one Alerted and alive, at distances falling along the
// array (main's `candidates`), so that each of the 8 scans updates its minimum at every element.

fn candidate_words(prior: bool) -> Array<GoblinWords> {
    let mut words = array![];
    let mut i: u16 = 0;
    while i < 100 {
        words.append(goblin_words(8 + i, prior && i >= 92, 280, 0, 0));
        i += 1;
    }
    words
}

fn distances() -> Span<u16> {
    let mut distances = array![];
    let mut i: u16 = 0;
    while i < 100 {
        distances.append(200 - i);
        i += 1;
    }
    distances.span()
}

/// Main's world of 100 loaded goblins, the last 8 awake with `prior`.
fn main_candidates(prior: bool) -> (World, Span<u16>) {
    let (sheets, mut index) = worst_content(3).index();
    let mut goblins = array![];
    for words in candidate_words(prior) {
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
    }
    (WorldTrait::new(49, array![], goblins, array![], false), distances())
}

/// The lazy world of the same words, its index kept.
fn lazy_candidates(prior: bool) -> (Lazy, Sheets, Index, Span<u16>) {
    let words = Words {
        clock: 49,
        members: array![],
        goblins: candidate_words(prior),
        killed: array![],
        defeated: false,
    };
    let content = worst_content(3);
    let (lazy, sheets, index) = LazyTrait::lazy_load(words, @content);
    (lazy, sheets, index, distances())
}

#[test]
fn test_awake_main_fixture() {
    let (world, distances) = main_candidates(false);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_pair_awake_main_formed() {
    let (mut world, distances) = main_candidates(false);
    TickTrait::awake(ref world, distances);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_awake_main_kept_fixture() {
    let (world, distances) = main_candidates(true);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_pair_awake_main_kept() {
    let (mut world, distances) = main_candidates(true);
    TickTrait::awake(ref world, distances);
    assert(world.goblin_count() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_awake_lazy_fixture() {
    let (lazy, _sheets, _index, distances) = lazy_candidates(false);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_pair_awake_lazy_formed() {
    let (mut lazy, sheets, mut index, distances) = lazy_candidates(false);
    lazy.awake(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_awake_lazy_kept_fixture() {
    let (lazy, _sheets, _index, distances) = lazy_candidates(true);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_pair_awake_lazy_kept() {
    let (mut lazy, sheets, mut index, distances) = lazy_candidates(true);
    lazy.awake(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

// Both selections choose the same set, the same flags, the same values (not a cost test).
#[test]
fn test_awake_lazy_matches_main() {
    for prior in array![false, true] {
        let (mut world, distances) = main_candidates(prior);
        TickTrait::awake(ref world, distances);
        let (mut lazy, sheets, mut index, _) = lazy_candidates(prior);
        lazy.awake(distances, ref index, @sheets);
        assert(lazy.woken == world.woken(), 'the same set');
        let mut k = 0;
        for i in lazy.woken {
            assert(*lazy.awake[k] == world.goblin(*i), 'the same values');
            k += 1;
        }
        let mut i = 0;
        while i < 100 {
            assert(*lazy.words[i].awake == world.goblin(i).awake, 'the same flags');
            i += 1;
        }
    }
    // A goblin put to sleep is encoded back: the 8 nearest change.
    let (mut lazy, sheets, mut index, _) = lazy_candidates(true);
    let mut far = array![];
    let mut i: u16 = 0;
    while i < 100 {
        far.append(100 + i);
        i += 1;
    }
    lazy.awake(far.span(), ref index, @sheets);
    assert(lazy.woken == array![0, 1, 2, 3, 4, 5, 6, 7].span(), 'replaced');
    let stored = lazy.lazy_store();
    assert(!*stored.goblins[99].awake && *stored.goblins[0].awake, 'flags stored');
    assert(*stored.goblins[99].state == *candidate_words(true)[99].state, 'asleep: its words');
}

// ---------------------------------------------------------------------------------------------
// A hook touching a frozen goblin (index 10 of 100), its health changed.

#[test]
fn test_touch_main_fixture() {
    let (words, content) = load_words(1);
    let (world, sheets) = WordsTrait::load(words, @content);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_touch_main() {
    let (words, content) = load_words(1);
    let (mut world, sheets) = WordsTrait::load(words, @content);
    let mut goblin = world.goblin(opaque(10));
    goblin.health -= 1;
    world.set_goblin(opaque(10), goblin);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_touch_lazy_fixture() {
    let (words, content) = load_words(1);
    let (lazy, sheets, _index) = LazyTrait::lazy_load(words, @content);
    opaque(@lazy);
    opaque(@sheets);
}

#[test]
fn test_pair_touch_lazy() {
    let (words, content) = load_words(1);
    let (mut lazy, sheets, mut index) = LazyTrait::lazy_load(words, @content);
    let mut goblin = lazy.thaw(opaque(10), ref index, @sheets);
    goblin.health -= 1;
    lazy.set_frozen(opaque(10), goblin);
    opaque(@lazy);
    opaque(@sheets);
}

// ---------------------------------------------------------------------------------------------
// The selection alone (ENG-07's step 0, either representation): main's 8 scans of the 100 keys
// against one pass, on the costliest order (distances falling: each scan updates its minimum at
// every key; each key of the single pass is inserted).

fn keys() -> Span<u32> {
    let mut keys = array![];
    let mut i: u32 = 0;
    while i < 100 {
        keys.append((200 - i) * 0x10000 + 8 + i);
        i += 1;
    }
    keys.span()
}

#[test]
fn test_selection_fixture() {
    let keys = opaque(keys());
    opaque(keys);
}

#[test]
fn test_pair_selection_scan() {
    let keys = opaque(keys());
    opaque(SelectionTrait::scan(keys));
    opaque(keys);
}

#[test]
fn test_pair_selection_single() {
    let keys = opaque(keys());
    opaque(SelectionTrait::single(keys));
    opaque(keys);
}

// Both selections agree: the costliest order, rising, none eligible, fewer than 8, a mix (not a
// cost test).
#[test]
fn test_selection_agrees() {
    let none: u32 = 0xFFFFFFFF;
    let mut rising = array![];
    let mut few = array![];
    let mut nothing = array![];
    let mut mixed = array![];
    let mut i: u32 = 0;
    while i < 100 {
        rising.append((10 + i) * 0x10000 + 8 + i);
        few.append(if i % 30 == 0 {
            (50 + i) * 0x10000 + 8 + i
        } else {
            none
        });
        nothing.append(none);
        mixed.append(((i * 37) % 101) * 0x10000 + 8 + i);
        i += 1;
    }
    for case in array![keys(), rising.span(), few.span(), nothing.span(), mixed.span()] {
        assert(SelectionTrait::scan(case) == SelectionTrait::single(case), 'the same selection');
    }
    assert(SelectionTrait::single(few.span()) == (4, 140 * 0x10000 + 98), 'fewer than 8');
}

// The lazy world's single-pass perception, from the AI states kept at load.
#[test]
fn test_pair_awake_single_formed() {
    let (mut lazy, sheets, mut index, distances) = lazy_candidates(false);
    lazy.awake_single(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_pair_awake_single_kept() {
    let (mut lazy, sheets, mut index, distances) = lazy_candidates(true);
    lazy.awake_single(distances, ref index, @sheets);
    assert(lazy.words.len() == 100 && distances.len() == 100, 'fixture');
}

#[test]
fn test_awake_single_matches_main() {
    for prior in array![false, true] {
        let (mut world, distances) = main_candidates(prior);
        TickTrait::awake(ref world, distances);
        let (mut lazy, sheets, mut index, _) = lazy_candidates(prior);
        lazy.awake_single(distances, ref index, @sheets);
        assert(lazy.woken == world.woken(), 'the same set');
        let mut k = 0;
        for i in lazy.woken {
            assert(*lazy.awake[k] == world.goblin(*i), 'the same values');
            k += 1;
        }
    }
}
