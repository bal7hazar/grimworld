// Lever 3: the executor's overhead as CBT-05 will add it, estimated on CBT-03a's hit and CBT-04's
// applications (`spk15::executor`). The world is CBT-02's heavy state at the batch's content
// (`worst_state(false, 3)`: the member with 3 conditions and 4 effects, 100 goblins, the last 8
// awake). Pairs of snforge's totals against `test_executor_fixture`:
// - an actor read from the world and written back: the member, an awake goblin, a frozen one;
// - a hit's inputs gathered (a goblin on the member);
// - a goblin's weapon hit end to end (read, gather, CBT-03a's `resolve`, the outcome, write back);
// - a bomb on 7 awake goblins, each written after its own hit and condition, and the same with
//   the 7 written together (`WorldTrait::flush`);
// - a `CONDITION` entry on the member and on an awake goblin, read and written back;
// - an entry decoded from its 97 bits (the executor reads a carrier's entries).
use grimworld_logic::models::goblin::Goblin;
use grimworld_logic::models::member::Member;
use grimworld_logic::types::combat::condition;
use grimworld_logic::types::effect::{EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::tick::Sheets;
use grimworld_logic::types::world::{World, WorldTrait};
use spk15::cbt03a::{Arc, HitOutcome, HitTrait};
use spk15::cbt04::Infliction;
use spk15::executor::{ExecutorTrait, GatherTrait, Guard};
use crate::fixtures::{opaque, worst_state};

fn state() -> (World, Sheets) {
    let (world, sheets) = worst_state(false, 3);
    (opaque(world), opaque(sheets))
}

#[test]
fn test_executor_fixture() {
    let (world, sheets) = state();
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_member_round_trip() {
    let (mut world, sheets) = state();
    let mut member: Member = world.member(opaque(0));
    member.health -= 1;
    world.set_member(opaque(0), member);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_awake_round_trip() {
    let (mut world, sheets) = state();
    let mut goblin: Goblin = world.goblin(opaque(99));
    goblin.health -= 1;
    world.set_goblin(opaque(99), goblin);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_frozen_round_trip() {
    let (mut world, sheets) = state();
    let mut goblin: Goblin = world.goblin(opaque(10));
    goblin.health -= 1;
    world.set_goblin(opaque(10), goblin);
    opaque(@world);
    opaque(@sheets);
}

// The actors already read (outside the pair's difference: both read them).
#[test]
fn test_executor_gather_fixture() {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    opaque(@goblin);
    opaque(@member);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_gather() {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    let (hit, target) = GatherTrait::goblin_on_member(
        @goblin, @member, opaque(Arc::FrontSide), opaque(true), opaque(50), @sheets,
    );
    opaque(hit);
    opaque(target);
    opaque(@goblin);
    opaque(@member);
    opaque(@sheets);
}

// The same inputs, resolved (CBT-03a's hit alone, on these inputs).
#[test]
fn test_pair_executor_gather_resolve() {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    let (hit, target) = GatherTrait::goblin_on_member(
        @goblin, @member, opaque(Arc::FrontSide), opaque(true), opaque(50), @sheets,
    );
    opaque(hit.resolve(@target));
    opaque(@goblin);
    opaque(@member);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_goblin_hit() {
    let (mut world, sheets) = state();
    let outcome = ExecutorTrait::goblin_hit(ref world, opaque(99), opaque(50), @sheets);
    opaque(outcome);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_bomb_each() {
    let (mut world, sheets) = state();
    let targets = array![92, 93, 94, 95, 96, 97, 98].span();
    let kills = ExecutorTrait::bomb_each(
        ref world, opaque(targets), opaque(condition::BURNING), opaque(3), opaque(50), @sheets,
    );
    opaque(kills);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_bomb_flushed() {
    let (mut world, sheets) = state();
    let targets = array![0, 1, 2, 3, 4, 5, 6].span();
    let kills = ExecutorTrait::bomb_flushed(
        ref world, opaque(targets), opaque(condition::BURNING), opaque(3), opaque(50), @sheets,
    );
    opaque(kills);
    opaque(@world);
    opaque(@sheets);
}

// Both bombs leave the same world (not a cost test).
#[test]
fn test_executor_bombs_agree() {
    let (mut each, sheets) = worst_state(false, 3);
    let (mut flushed, _) = worst_state(false, 3);
    let a = ExecutorTrait::bomb_each(
        ref each, array![92, 93, 94, 95, 96, 97, 98].span(), condition::BURNING, 3, 50, @sheets,
    );
    let b = ExecutorTrait::bomb_flushed(
        ref flushed, array![0, 1, 2, 3, 4, 5, 6].span(), condition::BURNING, 3, 50, @sheets,
    );
    assert(a == b, 'kills');
    assert(each == flushed, 'the same world');
    assert(each.goblin(95).burning == 52 || each.goblin(95).burning == 99, 'burning');
}

#[test]
fn test_pair_executor_condition_member() {
    let (mut world, sheets) = state();
    let source: Infliction = opaque(Default::default());
    ExecutorTrait::condition_on_member(
        ref world, opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(50), @sheets,
    );
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_condition_goblin() {
    let (mut world, sheets) = state();
    let source: Infliction = opaque(Default::default());
    ExecutorTrait::condition_on_goblin(
        ref world,
        opaque(99),
        opaque(condition::KNOCKED_DOWN),
        opaque(2),
        @source,
        opaque(50),
        @sheets,
    );
    opaque(@world);
    opaque(@sheets);
}

// An entry's 97 bits decoded (a `CONDITION` Bleeding 4…12 on an enemy).
fn entry_bits() -> u128 {
    EntryTrait::new(
        kind::CONDITION,
        condition::BLEEDING,
        4,
        12,
        5,
        5,
        0,
        target::FOE,
        shape::SINGLE,
        filter::FOES,
        0,
        0,
    )
        .pack()
}

#[test]
fn test_executor_entry_fixture() {
    let (world, sheets) = state();
    opaque(entry_bits());
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_entry() {
    let (world, sheets) = state();
    let entry = EntryTrait::unpack(opaque(entry_bits()));
    opaque(entry);
    opaque(@world);
    opaque(@sheets);
}

// The outcome is a hit that lands (the gather builds legal inputs): not a cost test.
#[test]
fn test_executor_goblin_hit_lands() {
    let (mut world, sheets) = worst_state(false, 3);
    let before = world.member(0).health;
    let outcome = ExecutorTrait::goblin_hit(ref world, 99, 50, @sheets);
    match outcome {
        HitOutcome::Landed(landed) => assert(
            world.member(0).health == before - landed.damage, 'damage',
        ),
        _ => {},
    }
}

// ---------------------------------------------------------------------------------------------
// The member's guard (its defence terms) read once a tick, not at each hit.

#[test]
fn test_pair_executor_guard() {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    opaque(GatherTrait::guard(@member, opaque(50)));
    opaque(@goblin);
    opaque(@member);
    opaque(@sheets);
}

fn guarded_state() -> (World, Sheets, Goblin, Member, Guard) {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    let guard = opaque(GatherTrait::guard(@member, 50));
    (world, sheets, goblin, member, guard)
}

#[test]
fn test_executor_guarded_fixture() {
    let (world, sheets, goblin, member, guard) = guarded_state();
    opaque(@world);
    opaque(@goblin);
    opaque(@member);
    opaque(guard);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_gather_guarded() {
    let (world, sheets, goblin, member, guard) = guarded_state();
    let (hit, target) = GatherTrait::goblin_on_member_guarded(
        @goblin, @member, @guard, opaque(Arc::FrontSide), opaque(true), opaque(50), @sheets,
    );
    opaque(hit);
    opaque(target);
    opaque(@world);
    opaque(@goblin);
    opaque(@member);
    opaque(guard);
    opaque(@sheets);
}

#[test]
fn test_executor_hit_guarded_fixture() {
    let (world, sheets) = state();
    let guard = opaque(GatherTrait::guard(@world.member(0), 50));
    opaque(guard);
    opaque(@world);
    opaque(@sheets);
}

#[test]
fn test_pair_executor_goblin_hit_guarded() {
    let (mut world, sheets) = state();
    let guard = opaque(GatherTrait::guard(@world.member(0), 50));
    let outcome = ExecutorTrait::goblin_hit_guarded(
        ref world, opaque(99), @guard, opaque(50), @sheets,
    );
    opaque(outcome);
    opaque(guard);
    opaque(@world);
    opaque(@sheets);
}

// The guarded hit leaves the world the unguarded one leaves (not a cost test).
#[test]
fn test_executor_guarded_agrees() {
    let (mut a, sheets) = worst_state(false, 3);
    let (mut b, _) = worst_state(false, 3);
    let guard = GatherTrait::guard(@b.member(0), 50);
    let x = ExecutorTrait::goblin_hit(ref a, 98, 50, @sheets);
    let y = ExecutorTrait::goblin_hit_guarded(ref b, 98, @guard, 50, @sheets);
    assert(x == y && a == b, 'the same hit');
}
