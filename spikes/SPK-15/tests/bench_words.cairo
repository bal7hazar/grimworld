// Lever 1: the frozen goblins kept as words (`spk15::words`). Pairs of snforge's totals:
// - load and store, once a call, on CBT-02b's costliest words (`load_words(1)`: 100 goblins, each
//   holding a retained effect, the last 8 awake; main's `test_cost_load_bound` and its fixture),
//   main's `WordsTrait::load` + `WorldStoreTrait::store` against `LazyTrait::load` + `store`, each
//   checking the round trip returns the words it was given; and on the representative words (8
//   goblins, all awake);
// - perception (ENG-07's step 0) is measured in `bench_perception.cairo` (fix loop 1);
// - a hook touching a frozen goblin (§9.2: up to 6 an action): main's `goblin` + `set_goblin` (the
//   100-goblin array rebuilt) against `LazyTrait::goblin` + `set_frozen`.
use grimworld_logic::types::tick::ContentTrait;
use grimworld_logic::types::world::{Words, WordsTrait, WorldStoreTrait, WorldTrait};
use spk15::words::{LazyTrait, SelectionTrait};
use crate::fixtures::{load_content, load_words, opaque, representative};

// ---------------------------------------------------------------------------------------------
// The content's index, once a call (lever 4): the dictionary of positions and the castes' kits,
// on load's content (38 skills, 5 castes, 4 potions), its dictionary squashed at the end.

#[test]
#[available_gas(l2_gas: 557760)] // ceil(1.05 × 531200 measured)
fn test_index_fixture() {
    let content = opaque(load_content());
    opaque(content);
}

#[test]
#[available_gas(l2_gas: 1142831)] // ceil(1.05 × 1088410 measured)
fn test_pair_index() {
    let content = opaque(load_content());
    let (sheets, _index) = content.index();
    opaque(sheets);
    opaque(content);
}

// ---------------------------------------------------------------------------------------------
// Load and store, the costliest words.

#[test]
#[available_gas(l2_gas: 11737026)] // ceil(1.05 × 11178120 measured)
fn test_words_bound_fixture() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

#[test]
#[available_gas(l2_gas: 22836020)] // ceil(1.05 × 21748590 measured)
fn test_pair_words_bound_main() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let (world, _) = WordsTrait::load(words, @content);
    assert(WorldStoreTrait::store(world) == expected, 'round trip');
}

#[test]
#[available_gas(l2_gas: 15022413)] // ceil(1.05 × 14307060 measured)
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
#[available_gas(l2_gas: 15656550)] // ceil(1.05 × 14911000 measured)
fn test_words_representative_fixture() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    assert(words.goblins.len() == expected.goblins.len() && content.castes.len() == 2, 'twice');
}

#[test]
#[available_gas(l2_gas: 17013455)] // ceil(1.05 × 16203290 measured)
fn test_pair_words_representative_main() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    let (world, _) = WordsTrait::load(words, @content);
    assert(WorldStoreTrait::store(world) == expected, 'round trip');
}

#[test]
#[available_gas(l2_gas: 17047632)] // ceil(1.05 × 16235840 measured)
fn test_pair_words_representative_lazy() {
    let (words, content) = representative_words();
    let (expected, _) = representative_words();
    let (lazy, _sheets, _index) = LazyTrait::lazy_load(words, @content);
    assert(lazy.lazy_store() == expected, 'round trip');
}

// ---------------------------------------------------------------------------------------------
// A hook touching a frozen goblin (index 10 of 100), its health changed.

#[test]
#[available_gas(l2_gas: 14290343)] // ceil(1.05 × 13609850 measured)
fn test_touch_main_fixture() {
    let (words, content) = load_words(1);
    let (world, sheets) = WordsTrait::load(words, @content);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14998536)] // ceil(1.05 × 14284320 measured)
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
#[available_gas(l2_gas: 8306718)] // ceil(1.05 × 7911160 measured)
fn test_touch_lazy_fixture() {
    let (words, content) = load_words(1);
    let (lazy, sheets, _index) = LazyTrait::lazy_load(words, @content);
    opaque(@lazy);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 8808324)] // ceil(1.05 × 8388880 measured)
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
#[available_gas(l2_gas: 436811)] // ceil(1.05 × 416010 measured)
fn test_selection_fixture() {
    let keys = opaque(keys());
    opaque(keys);
}

#[test]
#[available_gas(l2_gas: 3126963)] // ceil(1.05 × 2978060 measured)
fn test_pair_selection_scan() {
    let keys = opaque(keys());
    opaque(SelectionTrait::scan(keys));
    opaque(keys);
}

#[test]
#[available_gas(l2_gas: 1561497)] // ceil(1.05 × 1487140 measured)
fn test_pair_selection_single() {
    let keys = opaque(keys());
    opaque(SelectionTrait::single(keys));
    opaque(keys);
}

// Both selections agree: the costliest order, rising, none eligible, fewer than 8, a mix (not a
// cost test).
#[test]
#[available_gas(l2_gas: 15164300)] // ceil(1.05 × 14442190 measured)
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
