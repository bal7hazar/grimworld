// The design levers' measured terms (priced in the report, never decided here):
// - fewer goblins awake (design/02's 8, D-133, D-141): the tick's costliest state with `n` awake,
//   `n − 1` conclusions clearing the field then a lapse (CBT-02d's maximum at 8, re-proved by its
//   enumeration), measured as pairs with the bound's rules (`Acts`): 8 reproduces CBT-02d's
//   1,475,797; 6 and 4 price the rule;
// - fewer goblins in the call (a smaller simulation window, design/18; `MAX_GOBLINS` = the
//   window's 40 and the roster's 60): load and store at 100, 60 and 40 goblins, main's and with
//   the frozen goblins kept as words.
use grimworld_logic::models::goblin::GoblinWords;
use grimworld_logic::types::tick::Content;
use grimworld_logic::types::world::{TickTrait, Words, WordsTrait, WorldStoreTrait};
use spk15::words::LazyTrait;
use crate::fixtures::{
    Acts, C, L, at_end, goblin_words, load_content, member_effect_words, term_world,
};

/// `n − 1` conclusions clearing the field, then a lapse.
fn costliest(n: u32) -> Span<u8> {
    let mut branches = array![];
    if n == 0 {
        return branches.span();
    }
    for _ in 1..n {
        branches.append(C);
    }
    branches.append(L);
    branches.span()
}

fn awake_fixture(n: u16) {
    let (_world, _sheets) = term_world(costliest(n.into()), at_end(n), false, 1, 1);
}

fn awake_tick(n: u16) {
    let (mut world, sheets) = term_world(costliest(n.into()), at_end(n), false, 1, 1);
    let mut rules: Acts = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

#[test]
fn test_design_awake_8_fixture() {
    awake_fixture(8);
}

#[test]
fn test_pair_design_awake_8() {
    awake_tick(8);
}

#[test]
fn test_design_awake_6_fixture() {
    awake_fixture(6);
}

#[test]
fn test_pair_design_awake_6() {
    awake_tick(6);
}

#[test]
fn test_design_awake_4_fixture() {
    awake_fixture(4);
}

#[test]
fn test_pair_design_awake_4() {
    awake_tick(4);
}

#[test]
fn test_design_awake_0_fixture() {
    awake_fixture(0);
}

#[test]
fn test_pair_design_awake_0() {
    awake_tick(0);
}

// ---------------------------------------------------------------------------------------------
// Load and store at `count` goblins (load's costliest words, the last 8 awake).

fn words_of(count: u16) -> (Words, Content) {
    let mut goblins: Array<GoblinWords> = array![];
    let mut i: u16 = 0;
    while i < count {
        goblins.append(goblin_words(8 + i, i + 8 >= count, 280, 0, 99));
        i += 1;
    }
    let words = Words {
        clock: 49,
        members: array![member_effect_words(false)],
        goblins,
        killed: array![],
        defeated: false,
    };
    (words, load_content())
}

fn window_fixture(count: u16) {
    let (words, content) = words_of(count);
    let (expected, _) = words_of(count);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

fn window_main(count: u16) {
    let (words, content) = words_of(count);
    let (expected, _) = words_of(count);
    let (world, _) = WordsTrait::load(words, @content);
    assert(WorldStoreTrait::store(world) == expected, 'round trip');
}

fn window_lazy(count: u16) {
    let (words, content) = words_of(count);
    let (expected, _) = words_of(count);
    let (lazy, _sheets, _index) = LazyTrait::lazy_load(words, @content);
    assert(lazy.lazy_store() == expected, 'round trip');
}

#[test]
fn test_design_window_100_fixture() {
    window_fixture(100);
}

#[test]
fn test_pair_design_window_100_main() {
    window_main(100);
}

#[test]
fn test_pair_design_window_100_lazy() {
    window_lazy(100);
}

#[test]
fn test_design_window_60_fixture() {
    window_fixture(60);
}

#[test]
fn test_pair_design_window_60_main() {
    window_main(60);
}

#[test]
fn test_pair_design_window_60_lazy() {
    window_lazy(60);
}

#[test]
fn test_design_window_40_fixture() {
    window_fixture(40);
}

#[test]
fn test_pair_design_window_40_main() {
    window_main(40);
}

#[test]
fn test_pair_design_window_40_lazy() {
    window_lazy(40);
}
