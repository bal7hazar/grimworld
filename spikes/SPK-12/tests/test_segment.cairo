// SPK-12: the proved segment's properties, and its L2 gas against the Cairo steps `prove.py`
// measures for the same runs (`scarb execute`): what a tick's computation costs in each unit.
use core::poseidon::poseidon_hash_span;
use core::testing::get_available_gas;
use grimworld_logic::types::world::{Words, WorldStoreTrait};
use spk12::fixtures::{content_of, representative, worst_of};
use spk12::segment::{BUSY, IDLE, run, segment};

fn felts<T, +Serde<T>, +Drop<T>>(value: @T) -> Array<felt252> {
    let mut out = array![];
    value.serialize(ref out);
    out
}

fn representative_args() -> (Array<felt252>, Array<felt252>) {
    let (world, sheets) = representative();
    (felts(@world.store()), felts(@content_of(@sheets)))
}

fn busy_args() -> (Array<felt252>, Array<felt252>) {
    let (world, sheets) = worst_of(false, 1, 100);
    (felts(@world.store()), felts(@content_of(@sheets)))
}

fn decode(mut felts: Span<felt252>) -> Words {
    Serde::deserialize(ref felts).unwrap()
}

// Two segments of 5 ticks give the 10-tick segment's words, and the first's OUT_HASH is the
// second's IN_HASH: segments chain by their public outputs alone (slingfall's chunk binding).
#[test]
#[available_gas(l2_gas: 41428596)] // ceil(1.05 × 39455805 measured)
fn test_segments_chain() {
    let (words, content) = representative_args();
    let whole = segment(words.clone(), content.clone(), IDLE, 10);
    let (_, sheets) = representative();
    let half = run(decode(words.span()), @content_of(@sheets), IDLE, 5);
    let half_felts = felts(@half);
    let first = segment(words.clone(), content.clone(), IDLE, 5);
    let second = segment(half_felts.clone(), content.clone(), IDLE, 5);
    assert(*first[4] == poseidon_hash_span(half_felts.span()), 'first out is the half');
    assert(*second[0] == *first[4], 'second in is first out');
    assert(*second[4] == *whole[4], 'two halves make the whole');
    assert(*whole[0] == poseidon_hash_span(words.span()), 'in hash');
    assert(*whole[1] == poseidon_hash_span(content.span()), 'content hash');
    assert(*whole[3] == 10 && *whole[5] == 59 && *whole[6] == 0, 'ten ticks, alive');
}

// The busy state ends in the member's defeat at clock 89 (40 ticks): `run` stops there, whatever
// the count asked.
#[test]
#[available_gas(l2_gas: 68874801)] // ceil(1.05 × 65595048 measured)
fn test_busy_stops_at_defeat() {
    let (words, content) = busy_args();
    let out = segment(words, content, BUSY, 1000);
    assert(*out[5] == 89 && *out[6] == 1, 'defeated at 89');
}

// Unknown rules are refused.
#[test]
#[should_panic(expected: 'segment: rules')]
#[available_gas(l2_gas: 9390458)] // ceil(1.05 × 8943293 measured)
fn test_unknown_rules() {
    let (words, content) = representative_args();
    segment(words, content, 2, 1);
}

// The L2 gas of `run` (load, the ticks, store) for the runs `prove.py --steps-only` counts in Cairo
// steps with `scarb execute` (README, *Steps and L2 gas*): printed "gas run <scenario> <ticks>".
fn gas_of_run(words: Span<felt252>, content: Span<felt252>, rules: felt252, ticks: u32) -> u128 {
    let mut input = content;
    let content = Serde::deserialize(ref input).unwrap();
    let state = decode(words);
    let before = get_available_gas();
    let out = run(state, @content, rules, ticks);
    let gas = before - get_available_gas();
    assert(out.clock >= 49, 'ran');
    gas
}

#[test]
#[available_gas(l2_gas: 209879943)] // ceil(1.05 × 199885660 measured)
fn test_cost_run_ticks() {
    let (words, content) = representative_args();
    for ticks in array![0_u32, 1, 10, 100] {
        let gas = gas_of_run(words.span(), content.span(), IDLE, ticks);
        println!("gas run representative {}: {}", ticks, gas);
    }
    let (words, content) = busy_args();
    for ticks in array![0_u32, 1, 10, 40] {
        let gas = gas_of_run(words.span(), content.span(), BUSY, ticks);
        println!("gas run busy {}: {}", ticks, gas);
    }
}
