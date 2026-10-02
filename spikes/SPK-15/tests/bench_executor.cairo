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
use grimworld_logic::models::member::{Member, MemberWordsTrait};
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
#[available_gas(l2_gas: 14369177)] // ceil(1.05 × 13684930 measured)
fn test_executor_fixture() {
    let (world, sheets) = state();
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14405643)] // ceil(1.05 × 13719660 measured)
fn test_pair_executor_member_round_trip() {
    let (mut world, sheets) = state();
    let mut member: Member = world.member(opaque(0));
    member.health -= 1;
    world.set_member(opaque(0), member);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14484687)] // ceil(1.05 × 13794940 measured)
fn test_pair_executor_awake_round_trip() {
    let (mut world, sheets) = state();
    let mut goblin: Goblin = world.goblin(opaque(99));
    goblin.health -= 1;
    world.set_goblin(opaque(99), goblin);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 15015179)] // ceil(1.05 × 14300170 measured)
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
#[available_gas(l2_gas: 14423252)] // ceil(1.05 × 13736430 measured)
fn test_executor_gather_fixture() {
    let (world, sheets) = state();
    let goblin = opaque(world.goblin(99));
    let member = opaque(world.member(0));
    opaque(@goblin);
    opaque(@member);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14686189)] // ceil(1.05 × 13986846 measured)
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
#[available_gas(l2_gas: 14724661)] // ceil(1.05 × 14023486 measured)
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
#[available_gas(l2_gas: 14935963)] // ceil(1.05 × 14224726 measured)
fn test_pair_executor_goblin_hit() {
    let (mut world, sheets) = state();
    let outcome = ExecutorTrait::goblin_hit(ref world, opaque(99), opaque(50), @sheets);
    opaque(outcome);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 16942443)] // ceil(1.05 × 16135660 measured)
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

// The same bomb on 3 targets (D2′, fix loop 1 note 7): the difference with 7 is 4 targets' own
// part; the rest (one rebuild, the member's round trip, the kit's read) is the bomb's fixed part.
#[test]
#[available_gas(l2_gas: 15350108)] // ceil(1.05 × 14619150 measured)
fn test_pair_executor_bomb_flushed_3() {
    let (mut world, sheets) = state();
    let targets = array![0, 1, 2].span();
    let kills = ExecutorTrait::bomb_flushed(
        ref world, opaque(targets), opaque(condition::BURNING), opaque(3), opaque(50), @sheets,
    );
    opaque(kills);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 16501391)] // ceil(1.05 × 15715610 measured)
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
#[available_gas(l2_gas: 34919850)] // ceil(1.05 × 33257000 measured)
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
#[available_gas(l2_gas: 14504742)] // ceil(1.05 × 13814040 measured)
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
#[available_gas(l2_gas: 14563437)] // ceil(1.05 × 13869940 measured)
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
#[available_gas(l2_gas: 14414642)] // ceil(1.05 × 13728230 measured)
fn test_executor_entry_fixture() {
    let (world, sheets) = state();
    opaque(entry_bits());
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14448158)] // ceil(1.05 × 13760150 measured)
fn test_pair_executor_entry() {
    let (world, sheets) = state();
    let entry = EntryTrait::unpack(opaque(entry_bits()));
    opaque(entry);
    opaque(@world);
    opaque(@sheets);
}

// The outcome is a hit that lands (the gather builds legal inputs): not a cost test.
#[test]
#[available_gas(l2_gas: 14928980)] // ceil(1.05 × 14218076 measured)
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
#[available_gas(l2_gas: 14663607)] // ceil(1.05 × 13965340 measured)
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
#[available_gas(l2_gas: 14679672)] // ceil(1.05 × 13980640 measured)
fn test_executor_guarded_fixture() {
    let (world, sheets, goblin, member, guard) = guarded_state();
    opaque(@world);
    opaque(@goblin);
    opaque(@member);
    opaque(guard);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14705414)] // ceil(1.05 × 14005156 measured)
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
#[available_gas(l2_gas: 14614856)] // ceil(1.05 × 13918910 measured)
fn test_executor_hit_guarded_fixture() {
    let (world, sheets) = state();
    let guard = opaque(GatherTrait::guard(@world.member(0), 50));
    opaque(guard);
    opaque(@world);
    opaque(@sheets);
}

#[test]
#[available_gas(l2_gas: 14949550)] // ceil(1.05 × 14237666 measured)
fn test_pair_executor_goblin_hit_guarded() {
    let (mut world, sheets) = state();
    let mut guard = opaque(GatherTrait::guard(@world.member(0), 50));
    let outcome = ExecutorTrait::goblin_hit_guarded(
        ref world, opaque(99), ref guard, opaque(50), @sheets,
    );
    opaque(outcome);
    opaque(guard);
    opaque(@world);
    opaque(@sheets);
}

// The guarded hit leaves the world the unguarded one leaves (not a cost test).
#[test]
#[available_gas(l2_gas: 31318258)] // ceil(1.05 × 29826912 measured)
fn test_executor_guarded_agrees() {
    let (mut a, sheets) = worst_state(false, 3);
    let (mut b, _) = worst_state(false, 3);
    let mut guard = GatherTrait::guard(@b.member(0), 50);
    let x = ExecutorTrait::goblin_hit(ref a, 98, 50, @sheets);
    let y = ExecutorTrait::goblin_hit_guarded(ref b, 98, ref guard, 50, @sheets);
    assert(x == y && a == b, 'the same hit');
}

/// `worst_state`'s world, the member holding a `BLOCK` of 1 charge in effect slot 0 and no potion
/// (an `EVADE` in this estimate's model), so that a blocked hit is followed by one that lands.
fn blocking() -> (World, Sheets) {
    let (mut world, sheets) = worst_state(false, 3);
    let mut member = world.member(0);
    let mut held = member.effect_of(0);
    held.charges = 1;
    member.set_effect(0, held, 0);
    member.set_effect(2, Default::default(), 0);
    member.set_effect(3, Default::default(), 0);
    world.set_member(0, member);
    (world, sheets)
}

// Fix loop 1, finding 3: two goblins hit the member from the front in one tick; the first is
// blocked and spends the one charge, the second lands. Read once and updated at the block, the
// guard gives the outcomes the guard read at each hit gives, and the same world; read once and not
// updated, the second hit would be blocked too.
#[test]
#[available_gas(l2_gas: 32818170)] // ceil(1.05 × 31255400 measured)
fn test_executor_guard_two_hits() {
    let (mut each, sheets) = blocking();
    let (mut once, _) = blocking();
    let a1 = ExecutorTrait::goblin_hit(ref each, 98, 50, @sheets);
    let b1 = ExecutorTrait::goblin_hit(ref each, 99, 50, @sheets);
    let mut guard = GatherTrait::guard(@once.member(0), 50);
    assert(guard.block == 1 && guard.block_slot == 0, 'one charge');
    let stale = guard;
    let a2 = ExecutorTrait::goblin_hit_guarded(ref once, 98, ref guard, 50, @sheets);
    assert(guard.block == 0, 'the guard spent it');
    let b2 = ExecutorTrait::goblin_hit_guarded(ref once, 99, ref guard, 50, @sheets);
    assert(a1 == HitOutcome::Blocked && a2 == HitOutcome::Blocked, 'A blocked');
    match b1 {
        HitOutcome::Landed(_) => {},
        _ => core::panic_with_felt252('B lands'),
    }
    assert(b2 == b1, 'B the same');
    assert(each == once, 'the same world');
    assert(each.member(0).effect_of(0).charges == 0, 'the charge spent');
    // The guard not updated: B, at the same state, would be blocked.
    let goblin = once.goblin(99);
    let member = once.member(0);
    let (hit, target) = GatherTrait::goblin_on_member_guarded(
        @goblin, @member, @stale, Arc::FrontSide, true, 50, @sheets,
    );
    assert(hit.resolve(@target) == HitOutcome::Blocked, 'a stale guard blocks B');
}
