// The design levers' measured terms (priced in the report, never decided here):
// - fewer goblins awake (design/02's 8, D-133, D-141): the tick's costliest state with `n` awake,
//   `n − 1` conclusions clearing the field then a lapse (CBT-02d's maximum at 8, re-proved by its
//   enumeration), measured as pairs with the bound's rules (`Acts`): 8 reproduces CBT-02d's
//   1,475,797; 6 and 4 price the rule;
// - fewer goblins in the call (a smaller simulation window, design/18; `MAX_GOBLINS` = the
//   window's 40 and the roster's 60): load and store at 100, 60 and 40 goblins, main's and with
//   the frozen goblins kept as words.
use grimworld_logic::models::goblin::GoblinWords;
use grimworld_logic::types::tick::{Content, Sheets};
use grimworld_logic::types::world::{Idle, TickTrait, Words, WordsTrait, World, WorldStoreTrait};
use spk15::words::LazyTrait;
use crate::fixtures::{
    Acts, C, Fixture, L, at_end, goblin_words, load_content, member_effect_words, term_world,
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
#[available_gas(l2_gas: 18520121)] // ceil(1.05 × 17638210 measured)
fn test_design_awake_8_fixture() {
    awake_fixture(8);
}

#[test]
#[available_gas(l2_gas: 20100777)] // ceil(1.05 × 19143597 measured)
fn test_pair_design_awake_8() {
    awake_tick(8);
}

#[test]
#[available_gas(l2_gas: 17569346)] // ceil(1.05 × 16732710 measured)
fn test_design_awake_6_fixture() {
    awake_fixture(6);
}

#[test]
#[available_gas(l2_gas: 18750828)] // ceil(1.05 × 17857931 measured)
fn test_pair_design_awake_6() {
    awake_tick(6);
}

#[test]
#[available_gas(l2_gas: 16618571)] // ceil(1.05 × 15827210 measured)
fn test_design_awake_4_fixture() {
    awake_fixture(4);
}

#[test]
#[available_gas(l2_gas: 17447667)] // ceil(1.05 × 16616825 measured)
fn test_pair_design_awake_4() {
    awake_tick(4);
}

#[test]
#[available_gas(l2_gas: 14714637)] // ceil(1.05 × 14013940 measured)
fn test_design_awake_0_fixture() {
    awake_fixture(0);
}

#[test]
#[available_gas(l2_gas: 14962136)] // ceil(1.05 × 14249653 measured)
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
#[available_gas(l2_gas: 12031688)] // ceil(1.05 × 11458750 measured)
fn test_design_window_100_fixture() {
    window_fixture(100);
}

#[test]
#[available_gas(l2_gas: 23344545)] // ceil(1.05 × 22232900 measured)
fn test_pair_design_window_100_main() {
    window_main(100);
}

#[test]
#[available_gas(l2_gas: 15774350)] // ceil(1.05 × 15023190 measured)
fn test_pair_design_window_100_lazy() {
    window_lazy(100);
}

#[test]
#[available_gas(l2_gas: 11632688)] // ceil(1.05 × 11078750 measured)
fn test_design_window_60_fixture() {
    window_fixture(60);
}

#[test]
#[available_gas(l2_gas: 18986205)] // ceil(1.05 × 18082100 measured)
fn test_pair_design_window_60_main() {
    window_main(60);
}

#[test]
#[available_gas(l2_gas: 14720150)] // ceil(1.05 × 14019190 measured)
fn test_pair_design_window_60_lazy() {
    window_lazy(60);
}

#[test]
#[available_gas(l2_gas: 11433188)] // ceil(1.05 × 10888750 measured)
fn test_design_window_40_fixture() {
    window_fixture(40);
}

#[test]
#[available_gas(l2_gas: 16807035)] // ceil(1.05 × 16006700 measured)
fn test_pair_design_window_40_main() {
    window_main(40);
}

#[test]
#[available_gas(l2_gas: 14193050)] // ceil(1.05 × 13517190 measured)
fn test_pair_design_window_40_lazy() {
    window_lazy(40);
}

// ---------------------------------------------------------------------------------------------
// The representative tick (CBT-02's: the member with one condition and one effect, goblins of 2
// castes fighting, `Idle`) with 8, 6 and 4 goblins awake: the awake count's lever on it.

fn representative_of(n: u16) -> (World, Sheets) {
    let mut spec = Fixture::spec();
    spec.conditions = [99, 0, 0, 0];
    spec.effects = [(5, false, 99, 8), (0, false, 0, 0), (0, false, 0, 0), (0, false, 0, 0)];
    let member = Fixture::member(spec);
    let mut goblins = array![];
    let mut k: u16 = 0;
    while k < n {
        goblins.append(Fixture::goblin(8 + 16 * k, 1 + k % 2));
        k += 1;
    }
    (Fixture::world(49, array![member], goblins), Fixture::sheets())
}

fn representative_fixture(n: u16) {
    let (_world, _sheets) = representative_of(n);
}

fn representative_tick(n: u16) {
    let (mut world, sheets) = representative_of(n);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @sheets, ref rules);
}

#[test]
#[available_gas(l2_gas: 7751405)] // ceil(1.05 × 7382290 measured)
fn test_design_representative_8_fixture() {
    representative_fixture(8);
}

#[test]
#[available_gas(l2_gas: 8489615)] // ceil(1.05 × 8085347 measured)
fn test_pair_design_representative_8() {
    representative_tick(8);
}

#[test]
#[available_gas(l2_gas: 7157756)] // ceil(1.05 × 6816910 measured)
fn test_design_representative_6_fixture() {
    representative_fixture(6);
}

#[test]
#[available_gas(l2_gas: 7749611)] // ceil(1.05 × 7380581 measured)
fn test_pair_design_representative_6() {
    representative_tick(6);
}

#[test]
#[available_gas(l2_gas: 6564107)] // ceil(1.05 × 6251530 measured)
fn test_design_representative_4_fixture() {
    representative_fixture(4);
}

#[test]
#[available_gas(l2_gas: 7009606)] // ceil(1.05 × 6675815 measured)
fn test_pair_design_representative_4() {
    representative_tick(4);
}
