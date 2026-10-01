// Lever 2: one condition's application, taken apart, and its alternatives. Each `test_pair_*`
// differs from its `*_base` by its call alone: the difference of snforge's totals is the call's
// cost, its straight-line part included. The bases are CBT-04's own (`condition_cost_state` in
// `models::member` and `models::goblin` at `b5f4069`): an activation to interrupt, a condition
// held.
// The costliest path is a knock-down interrupting the activation; Sierra charges it to every
// application of a function without a loop, whatever the condition.
use grimworld_logic::helpers::tick::TickMathTrait;
use grimworld_logic::models::goblin::{
    Goblin, GoblinLifecycleTrait, GoblinTickTrait, GoblinWordsTrait,
};
use grimworld_logic::models::member::{Member, MemberLifecycleTrait, MemberTickTrait};
use grimworld_logic::types::combat::condition;
use grimworld_logic::types::tick::{Sheets, ai};
use spk15::application::{
    Afflictions, AfflictionsTrait, GoblinApplicationTrait, MemberApplicationTrait,
};
use spk15::cbt04::{Cbt04GoblinTrait, Cbt04MemberTrait, Infliction, InflictionTrait};
use crate::fixtures::{Fixture, HOB, opaque};

fn member_state() -> (Member, Sheets) {
    let mut member = opaque(Fixture::member(Fixture::spec()));
    member.start(opaque(2), 9, 2, opaque(200));
    member.bleeding = opaque(205);
    (member, opaque(Fixture::sheets()))
}

fn goblin_state() -> (Goblin, Sheets) {
    let mut goblin = opaque(Fixture::goblin(40, HOB));
    goblin.start(opaque(0), 0, 3, opaque(50));
    goblin.bleeding = opaque(55);
    (goblin, opaque(Fixture::sheets()))
}

// ---------------------------------------------------------------------------------------------
// The member: CBT-04's 108,100 reproduced, then taken apart.

#[test]
#[available_gas(l2_gas: 5222784)] // ceil(1.05 × 4974080 measured)
fn test_member_base() {
    let (member, _sheets) = member_state();
    opaque(member);
}

// CBT-04's pair (`test_cost_member_apply_knockdown`): the source's `Infliction` read from the
// member's kit, then `apply`.
#[test]
#[available_gas(l2_gas: 5336289)] // ceil(1.05 × 5082180 measured)
fn test_pair_member_cbt04_apply() {
    let (mut member, sheets) = member_state();
    let source = opaque(member.infliction());
    member.apply(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(201), @sheets);
    opaque(member);
}

// The same with a source given (the kit read once a carrier, not once an application).
#[test]
#[available_gas(l2_gas: 5318334)] // ceil(1.05 × 5065080 measured)
fn test_pair_member_cbt04_apply_given() {
    let (mut member, sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    member.apply(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(201), @sheets);
    opaque(member);
}

// Its parts, each alone: the kit's read; the duration; main's `inflict`; main's `interrupt`.
#[test]
#[available_gas(l2_gas: 5242755)] // ceil(1.05 × 4993100 measured)
fn test_pair_member_part_infliction() {
    let (member, _sheets) = member_state();
    opaque(member.infliction());
    opaque(member);
}

#[test]
#[available_gas(l2_gas: 5236697)] // ceil(1.05 × 4987330 measured)
fn test_pair_member_part_duration() {
    let (member, _sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    opaque(source.duration(opaque(condition::KNOCKED_DOWN), opaque(2)));
    opaque(member);
}

#[test]
#[available_gas(l2_gas: 5262495)] // ceil(1.05 × 5011900 measured)
fn test_pair_member_part_inflict() {
    let (mut member, _sheets) = member_state();
    member.inflict(opaque(condition::KNOCKED_DOWN), opaque(201), opaque(2));
    opaque(member);
}

#[test]
#[available_gas(l2_gas: 5262579)] // ceil(1.05 × 5011980 measured)
fn test_pair_member_part_interrupt() {
    let (mut member, sheets) = member_state();
    member.interrupt(opaque(201), @sheets);
    opaque(member);
}

// The cost of handing the member to a function and back: a call that does nothing with it.
#[inline(never)]
fn touch(ref member: Member) {
    member.health = member.health;
}

#[test]
#[available_gas(l2_gas: 5226564)] // ceil(1.05 × 4977680 measured)
fn test_pair_member_part_call() {
    let (mut member, _sheets) = member_state();
    touch(ref member);
    opaque(member);
}

// The alternatives: every step inlined, in place.
#[test]
#[available_gas(l2_gas: 5282823)] // ceil(1.05 × 5031260 measured)
fn test_pair_member_in_place() {
    let (mut member, sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    member
        .apply_in_place(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(201), @sheets);
    opaque(member);
}

// Conditions 1–4 apart from the knock-down: Crippled, the costliest of the four.
#[test]
#[available_gas(l2_gas: 5256321)] // ceil(1.05 × 5006020 measured)
fn test_pair_member_split() {
    let (mut member, _sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    member.apply_split(opaque(condition::CRIPPLED), opaque(20), @source, opaque(201));
    opaque(member);
}

#[test]
#[available_gas(l2_gas: 5280828)] // ceil(1.05 × 5029360 measured)
fn test_pair_member_knock() {
    let (mut member, sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    member.knock(opaque(2), @source, opaque(201), @sheets);
    opaque(member);
}

// A degenerating condition only (Bleeding, Poison, Burning: the MVP's commonest, FX-22).
#[test]
#[available_gas(l2_gas: 5248194)] // ceil(1.05 × 4998280 measured)
fn test_pair_member_hot() {
    let (mut member, _sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    member.apply_hot(opaque(condition::BLEEDING), opaque(20), @source, opaque(201));
    opaque(member);
}

// Gathered: one application added; the gathered applications written (every condition, a
// knock-down).
#[test]
#[available_gas(l2_gas: 5245989)] // ceil(1.05 × 4996180 measured)
fn test_pair_member_gather_add() {
    let (member, _sheets) = member_state();
    let source: Infliction = opaque(Default::default());
    let mut gathered: Afflictions = opaque(Default::default());
    gathered.add(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(201));
    opaque(gathered);
    opaque(member);
}

#[test]
#[available_gas(l2_gas: 5279621)] // ceil(1.05 × 5028210 measured)
fn test_pair_member_gather_flush() {
    let (mut member, sheets) = member_state();
    let gathered = opaque(
        Afflictions {
            bleeding: 220, poison: 220, burning: 220, crippled: 220, knocked: 202, knocked_at: 201,
        },
    );
    gathered.flush_member(ref member, @sheets);
    opaque(member);
}

// ---------------------------------------------------------------------------------------------
// The goblin: CBT-04's 76,820, then its parts and the alternative.

#[test]
#[available_gas(l2_gas: 621243)] // ceil(1.05 × 591660 measured)
fn test_goblin_base() {
    let (goblin, _sheets) = goblin_state();
    opaque(goblin);
}

#[test]
#[available_gas(l2_gas: 701904)] // ceil(1.05 × 668480 measured)
fn test_pair_goblin_cbt04_apply() {
    let (mut goblin, sheets) = goblin_state();
    let source: Infliction = opaque(Default::default());
    goblin.apply(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(52), @sheets);
    opaque(goblin);
}

#[test]
#[available_gas(l2_gas: 656408)] // ceil(1.05 × 625150 measured)
fn test_pair_goblin_part_inflict() {
    let (mut goblin, _sheets) = goblin_state();
    goblin.inflict(opaque(condition::KNOCKED_DOWN), opaque(52), opaque(2));
    opaque(goblin);
}

#[test]
#[available_gas(l2_gas: 651851)] // ceil(1.05 × 620810 measured)
fn test_pair_goblin_part_interrupt() {
    let (mut goblin, sheets) = goblin_state();
    goblin.interrupt(opaque(52), @sheets);
    opaque(goblin);
}

#[inline(never)]
fn touch_goblin(ref goblin: Goblin) {
    goblin.health = goblin.health;
}

#[test]
#[available_gas(l2_gas: 623973)] // ceil(1.05 × 594260 measured)
fn test_pair_goblin_part_call() {
    let (mut goblin, _sheets) = goblin_state();
    touch_goblin(ref goblin);
    opaque(goblin);
}

#[test]
#[available_gas(l2_gas: 671538)] // ceil(1.05 × 639560 measured)
fn test_pair_goblin_in_place() {
    let (mut goblin, sheets) = goblin_state();
    let source: Infliction = opaque(Default::default());
    goblin.apply_in_place(opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(52), @sheets);
    opaque(goblin);
}

#[test]
#[available_gas(l2_gas: 684338)] // ceil(1.05 × 651750 measured)
fn test_pair_goblin_gather_flush() {
    let (mut goblin, sheets) = goblin_state();
    let gathered = opaque(
        Afflictions {
            bleeding: 70, poison: 70, burning: 70, crippled: 70, knocked: 53, knocked_at: 52,
        },
    );
    gathered.flush_goblin(ref goblin, @sheets);
    opaque(goblin);
}

// ---------------------------------------------------------------------------------------------
// The alternatives give CBT-04's results: every condition 1–5, a refresh kept and one raised, the
// knock-down's interrupt, the kit's percent and flat ticks, a member not alive.

fn rending() -> Infliction {
    Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 }
}

#[test]
#[available_gas(l2_gas: 343402385)] // ceil(1.05 × 327049890 measured)
fn test_alternatives_match_cbt04_member() {
    let sheets = Fixture::sheets();
    let source = rending();
    let conditions = array![
        condition::BLEEDING, condition::POISON, condition::BURNING, condition::CRIPPLED,
        condition::KNOCKED_DOWN,
    ];
    for c in conditions.span() {
        for v in array![1_i32, 20, 0].span() {
            let (mut expected, _) = member_state();
            expected.apply(*c, *v, @source, 201, @sheets);
            let (mut in_place, _) = member_state();
            in_place.apply_in_place(*c, *v, @source, 201, @sheets);
            assert(in_place == expected, 'in place');
            let (mut split, _) = member_state();
            if *c == condition::KNOCKED_DOWN {
                split.knock(*v, @source, 201, @sheets);
            } else {
                split.apply_split(*c, *v, @source, 201);
            }
            assert(split == expected, 'split');
            let (mut gathered_member, _) = member_state();
            let mut gathered: Afflictions = Default::default();
            gathered.add(*c, *v, @source, 201);
            gathered.flush_member(ref gathered_member, @sheets);
            assert(gathered_member == expected, 'gathered');
        }
    }
    // Two applications of the same condition gathered: the later deadline, as two applies.
    let (mut expected, _) = member_state();
    expected.apply(condition::POISON, 8, @source, 201, @sheets);
    expected.apply(condition::POISON, 3, @source, 203, @sheets);
    expected.apply(condition::KNOCKED_DOWN, 2, @source, 201, @sheets);
    expected.apply(condition::KNOCKED_DOWN, 4, @source, 203, @sheets);
    let (mut member, _) = member_state();
    let mut gathered: Afflictions = Default::default();
    gathered.add(condition::POISON, 8, @source, 201);
    gathered.add(condition::POISON, 3, @source, 203);
    gathered.add(condition::KNOCKED_DOWN, 2, @source, 201);
    gathered.add(condition::KNOCKED_DOWN, 4, @source, 203);
    gathered.flush_member(ref member, @sheets);
    assert(member == expected, 'gathered twice');
    // Not alive: nothing.
    let (mut down, _) = member_state();
    down.health = 0;
    let before = down;
    down.apply_in_place(condition::BURNING, 5, @source, 201, @sheets);
    assert(down == before, 'not alive');
    // The hot path agrees on the degenerating conditions.
    let (mut hot, _) = member_state();
    hot.apply_hot(condition::POISON, 20, @source, 201);
    let (mut expected, _) = member_state();
    expected.apply(condition::POISON, 20, @source, 201, @sheets);
    assert(hot == expected, 'hot');
    // The refresh rule itself is main's: `max(D_old, t0 + d − 1)`.
    assert(TickMathTrait::refreshed(205, 201, 2) == 205, 'kept');
    assert(source.duration(condition::BLEEDING, 20) == 26, 'percent');
}

#[test]
#[available_gas(l2_gas: 26356502)] // ceil(1.05 × 25101430 measured)
fn test_alternatives_match_cbt04_goblin() {
    let sheets = Fixture::sheets();
    let source = rending();
    let conditions = array![
        condition::BLEEDING, condition::POISON, condition::BURNING, condition::CRIPPLED,
        condition::KNOCKED_DOWN,
    ];
    // Fix loop 1, note 8: every condition at the values 1, 20 and 0 (clamped to 1), alive and dead.
    for c in conditions.span() {
        for v in array![1_i32, 20, 0].span() {
            for dead in array![false, true].span() {
                let (mut base, _) = goblin_state();
                if *dead {
                    base.ai = ai::DEAD;
                    base.health = 0;
                }
                let mut expected = base;
                expected.apply(*c, *v, @source, 52, @sheets);
                let mut in_place = base;
                in_place.apply_in_place(*c, *v, @source, 52, @sheets);
                assert(in_place == expected, 'in place');
                let mut gathered_goblin = base;
                let mut gathered: Afflictions = Default::default();
                gathered.add(*c, *v, @source, 52);
                gathered.flush_goblin(ref gathered_goblin, @sheets);
                assert(gathered_goblin == expected, 'gathered');
                if *dead {
                    assert(expected == base, 'dead: nothing');
                }
            }
        }
    }
    let (goblin, _) = goblin_state();
    assert(goblin.crippled() == 0, 'fixture');
}
