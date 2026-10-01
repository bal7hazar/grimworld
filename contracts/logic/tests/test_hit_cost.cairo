// CBT-03a: the cost of one hit (design/19 §5.5 steps 1–4) and the most a tick can add.
//
// `HitTrait::resolve` has no loop and calls no function but the table's lookup: Sierra charges such
// a function its costliest path whatever path runs (ENG-01 §9.2, *How the bound is proved*), so
// one hit costs the same on every path (`test_cost_hit_paths` checks it, within its loop's own
// match).
// The pairs measure it as snforge's totals of two tests that differ by the hit alone and check
// nothing else (`test_cost_pair_*`, as CBT-02d did): the straight-line part that
// `get_available_gas` around a call misses is in them. Kept in `tests/` as a benchmark (D-167).
//
// The most hits a tick can compute (design/19 §5.1–§5.2, ENG-01 §9.2): each of the 8 awake
// goblins makes at most one hit a tick (a weapon attack, an attack skill or a trap its move enters;
// a goblin whose activation resolves in step 1 does not act in step 2), and the member's carrier
// reaches at most 6 goblins (Cinder Ring, `RING_1`; `DISC_1` is a potion's, an action of the action
// phase, FX-35): 8 + 6 = 14.
use core::testing::get_available_gas;
use grimworld_logic::types::combat::{HitClass, weapon};
use grimworld_logic::types::hit::{Arc, Hit, HitOutcome, HitTarget, HitTrait, MAX_BASE};

/// The hits a tick can compute at most: 8 awake goblins and an area of 6.
const HITS_PER_TICK: u32 = 14;

/// The costliest path: a weapon hit that lands, with an axe from the back on a target whose every
/// armor term and guard counts, penetration, both percent sums, and FX-19's halving triggering.
fn costliest() -> (Hit, HitTarget) {
    (
        Hit {
            class: HitClass::Weapon,
            weapon: weapon::AXE,
            melee: true,
            arc: Arc::Back,
            in_front: false,
            strength: 75,
            base: MAX_BASE,
            percent: 18,
            percent_above_half: 18,
            penetration: 30,
            health: 480,
            max_health: 480,
            weakened: true,
            blind: false,
        },
        HitTarget {
            armor: 120,
            armor_effects: 30,
            armor_stance: 10,
            armor_enchanted: 10,
            in_stance: true,
            enchanted: true,
            armor_vs: 20,
            block: 3,
            evade: true,
            knocked_down: true,
            asleep: false,
            halve: true,
            health: 30000,
            max_health: 50000,
        },
    )
}

// The pair's base: the inputs built, no hit.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_cost_pair_hit_none() {
    let (hit, target) = costliest();
    assert(hit.base == MAX_BASE && target.halve, 'inputs');
}

// The pair's other half: the same, and one hit on the costliest path.
#[test]
#[available_gas(l2_gas: 63189)] // ceil(1.05 × 60180 measured)
fn test_cost_pair_hit_one() {
    let (hit, target) = costliest();
    assert(hit.base == MAX_BASE && target.halve, 'inputs');
    let outcome = one(@hit, @target);
    match outcome {
        HitOutcome::Landed(landed) => assert(landed.critical && landed.halved, 'costliest path'),
        _ => core::panic_with_felt252('landed'),
    }
}

/// `n` hits of `hit` on `target`, the loop alone (`get_available_gas` around it: each iteration
/// withdraws its body, the call included); the outcomes that landed. Never inlined: inlined into a
/// test, its constant inputs would let the compiler fold the hit away, which no executor's inputs
/// allow (measured: a constant blocked hit "cost" 1,106).
#[inline(never)]
fn hits(hit: @Hit, target: @HitTarget, n: u32) -> (u128, u32) {
    let mut landed: u32 = 0;
    let before = get_available_gas();
    for _ in 0..n {
        if let HitOutcome::Landed(_) = hit.resolve(target) {
            landed += 1;
        }
    }
    (before - get_available_gas(), landed)
}

/// One hit, never inlined (the pair's call).
#[inline(never)]
fn one(hit: @Hit, target: @HitTarget) -> HitOutcome {
    hit.resolve(target)
}

/// One hit's withdrawal inside a loop: `(hits(n + 1) − hits(1)) / n`, the loop's own entry apart.
fn each(hit: @Hit, target: @HitTarget) -> u128 {
    let (more, _) = hits(hit, target, 3);
    let (single, _) = hits(hit, target, 1);
    (more - single) / 2
}

// A tick's most hits, 14, on the costliest path.
#[test]
#[available_gas(l2_gas: 1081395)] // ceil(1.05 × 1029900 measured)
fn test_cost_hits_per_tick() {
    let (hit, target) = costliest();
    let (used, landed) = hits(@hit, @target, HITS_PER_TICK);
    println!("{} hits: {}; one hit in a loop: {}", HITS_PER_TICK, used, each(@hit, @target));
    assert(landed == HITS_PER_TICK, 'every hit landed');
}

// Every path is charged the same (the claim above, checked): a blocked hit, an evaded one, a missed
// one, a spell and a bomb cost what a landed weapon hit costs.
#[test]
#[available_gas(l2_gas: 1960602)] // ceil(1.05 × 1867240 measured)
fn test_cost_hit_paths() {
    let (hit, target) = costliest();
    let landed = each(@hit, @target);
    let front = Hit { arc: Arc::Front, ..hit };
    let open = HitTarget { knocked_down: false, ..target };
    let blocked = each(@front, @open);
    let evaded = each(@hit, @open);
    let blind = Hit { blind: true, ..hit };
    let missed = each(@blind, @target);
    let spell = each(@Hit { class: HitClass::Spell, ..hit }, @target);
    let bomb = each(@Hit { class: HitClass::Item, ..hit }, @target);
    println!(
        "one hit: landed {}, blocked {}, evaded {}, missed {}, spell {}, bomb {}",
        landed,
        blocked,
        evaded,
        missed,
        spell,
        bomb,
    );
    assert(one(@front, @open) == HitOutcome::Blocked, 'blocked');
    assert(one(@hit, @open) == HitOutcome::Evaded, 'evaded');
    assert(one(@blind, @target) == HitOutcome::Missed, 'missed');
    // The loop's own body branches on the outcome: the paths differ by its match alone, at most
    // 110 measured, under 1 %.
    let mut low = landed;
    let mut high = landed;
    for cost in array![blocked, evaded, missed, spell, bomb] {
        if cost < low {
            low = cost;
        }
        if cost > high {
            high = cost;
        }
    }
    println!("one hit, every path: {} to {}", low, high);
    assert((high - low) * 100 <= low, 'one charge on every path');
}
