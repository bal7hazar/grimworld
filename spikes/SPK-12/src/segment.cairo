//! The proved program: a deterministic segment of world ticks, from the stored words to the stored
//! words, as `TickLibrary.run` does (contracts/logic/src/systems/tick.cairo), with the rules named
//! by the caller. Its arguments are private (witness); its public output is a binding header in the
//! manner of slingfall's chunk binding (docs/proving.md, *Chunk binding*): the hashes of the words
//! it ran on, of the content, of the words it returns, so that segments chain by their hashes
//! alone.

use core::poseidon::poseidon_hash_span;
use grimworld_logic::types::tick::Content;
use grimworld_logic::types::world::{Idle, TickTrait, Words, WordsTrait, WorldStoreTrait};
use crate::fixtures::{Busy, content_of, representative, worst_of};

/// `rules` of `segment`: the pipeline alone (`Idle`, what `TickLibrary` runs today) or `Busy`.
pub const IDLE: felt252 = 0;
pub const BUSY: felt252 = 1;

/// CBT-02's scenarios (`fixture`'s argument).
pub const REPRESENTATIVE: felt252 = 0;
pub const WORST: felt252 = 1;
pub const BUSY_BATCH: felt252 = 2;

/// The header `segment` returns: `[IN_HASH, CONTENT_HASH, rules, ticks asked, OUT_HASH, clock
/// after, defeated]`, the hashes Poseidon over the argument's felts without the length prefix.
pub fn header(
    words: Span<felt252>,
    content: Span<felt252>,
    rules: felt252,
    ticks: u32,
    out: Span<felt252>,
    clock: u32,
    defeated: bool,
) -> Array<felt252> {
    array![
        poseidon_hash_span(words), poseidon_hash_span(content), rules, ticks.into(),
        poseidon_hash_span(out), clock.into(), defeated.into(),
    ]
}

/// The proved segment. `words`: the `Serde` felts of one `Words`; `content`: those of one
/// `Content`; `rules`: `IDLE` or `BUSY`; `ticks`: how many ticks to run.
pub fn segment(
    words: Array<felt252>, content: Array<felt252>, rules: felt252, ticks: u32,
) -> Array<felt252> {
    let mut input = words.span();
    let state: Words = Serde::deserialize(ref input).expect('segment: words');
    assert(input.is_empty(), 'segment: words');
    let mut input = content.span();
    let sheets_of: Content = Serde::deserialize(ref input).expect('segment: content');
    assert(input.is_empty(), 'segment: content');
    let out = run(state, @sheets_of, rules, ticks);
    let mut felts = array![];
    out.serialize(ref felts);
    header(words.span(), content.span(), rules, ticks, felts.span(), out.clock, out.defeated)
}

/// Loads `words`, runs up to `ticks` ticks under `rules` (stopping after a defeat), in runs of at
/// most 255 (`TickTrait::run` counts in `u8`), stores.
pub fn run(words: Words, content: @Content, rules: felt252, ticks: u32) -> Words {
    let (mut world, sheets) = words.load(content);
    let mut left = ticks;
    while left > 0 && !world.defeated {
        let now: u8 = if left > 255 {
            255
        } else {
            left.try_into().unwrap()
        };
        left -= now.into();
        if rules == IDLE {
            let mut idle = Idle {};
            TickTrait::run(ref world, @sheets, now, ref idle);
        } else {
            assert(rules == BUSY, 'segment: rules');
            let mut busy: Busy = Default::default();
            TickTrait::run(ref world, @sheets, now, ref busy);
        }
    }
    world.store()
}

/// The arguments of `segment` for `scenario` but its tick count: `[len(words), words…,
/// len(content), content…, rules]`.
pub fn fixture(scenario: felt252) -> Array<felt252> {
    let (world, sheets, rules) = if scenario == REPRESENTATIVE {
        let (world, sheets) = representative();
        (world, sheets, IDLE)
    } else if scenario == WORST {
        let (world, sheets) = worst_of(true, 3, 100);
        (world, sheets, IDLE)
    } else {
        assert(scenario == BUSY_BATCH, 'fixture: scenario');
        let (world, sheets) = worst_of(false, 1, 100);
        (world, sheets, BUSY)
    };
    let mut words = array![];
    world.store().serialize(ref words);
    let mut content = array![];
    content_of(@sheets).serialize(ref content);
    let mut args = array![words.len().into()];
    args.append_span(words.span());
    args.append(content.len().into());
    args.append_span(content.span());
    args.append(rules);
    args
}
