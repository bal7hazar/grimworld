//! **The zero-residue test** (ENG-10a deliverable 2; ENG-10b's merge gate, the Overseer,
//! 2026-10-07): for a set of entropies, every order of the reveals gives the same chunk set, the
//! same exit chunk and the same exit-to-entry distance (and the same edges, one exit, at the
//! outline's farthest distance). ENG-10b keeps it as `test_zero_residue` on the real path.
//!
//! **The negative control** (`test_residue_eng05`): the same comparison on ENG-05's engine as
//! merged, an honest order against t-0077's forcing order, finds the residue the test is there to
//! catch, measured: the figures are printed.

use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::Terrain;
use grimworld_logic::types::reveal as eng05;
use grimworld_logic::types::reveal::board::BoardTrait;
use hexx::board::rng::RngTrait;
use spk17::outline::OutlineTrait;
use crate::fixtures::{
    ENTRY, INSTANCE, Outcome, chunks, create, eng05_outcome, eng05_site, fixed_outcome,
    reveal_in_order, shuffled,
};

/// The orders of one floor: by index, backward, nearest first, farthest first (the entry's
/// neighbours last, t-0077's lever), and two drawn; the entry first in each, as `create` reveals it.
fn orders(outline: @spk17::outline::Outline, entropy: felt252) -> Array<Array<u8>> {
    let all = chunks(*outline.chunks);
    let mut rest: Array<u8> = array![];
    for c in all.span() {
        if *c != ENTRY {
            rest.append(*c);
        }
    }
    let mut ascending = array![ENTRY];
    let mut descending = array![ENTRY];
    for c in rest.span() {
        ascending.append(*c);
    }
    let mut k = rest.len();
    while k != 0 {
        k -= 1;
        descending.append(*rest[k]);
    }
    // By distance through the open seams
    let mut layers: Array<Array<u8>> = array![];
    let (_, depth) = outline.far(ENTRY);
    let mut d: u8 = 0;
    while d <= depth {
        let mut layer: Array<u8> = array![];
        for c in rest.span() {
            if outline.distance(ENTRY, *c) == d {
                layer.append(*c);
            }
        }
        layers.append(layer);
        d += 1;
    }
    let mut nearest = array![ENTRY];
    for layer in layers.span() {
        for c in layer.span() {
            nearest.append(*c);
        }
    }
    let mut farthest = array![ENTRY];
    let mut d = layers.len();
    while d != 0 {
        d -= 1;
        for c in layers[d].span() {
            farthest.append(*c);
        }
    }
    let drawn_1 = shuffled(ascending.span(), poseidon_hash_span([entropy, 'order 1'].span()));
    let drawn_2 = shuffled(ascending.span(), poseidon_hash_span([entropy, 'order 2'].span()));
    array![ascending, descending, nearest, farthest, drawn_1, drawn_2]
}

/// ENG-10b's gate on the spike's engine: `seeds` entropies from `first`, floors of `n` chunks.
fn zero_residue(n: u8, first: u32, seeds: u32) {
    let mut i: u32 = first;
    while i != first + seeds {
        let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
        let floor = create(entropy, n);
        let mut reference: Option<Outcome> = Option::None;
        for order in orders(@floor.outline, entropy) {
            let (progress, out) = reveal_in_order(@floor.site, entropy, order.span());
            let got = fixed_outcome(@progress, out.span());
            assert(progress.count == n, 'every chunk revealed');
            assert(got.revealed == floor.outline.chunks, 'the outline revealed');
            assert(got.exits == 1, 'one exit');
            assert(BoardTrait::has(floor.far, got.exit), 'the exit at the farthest');
            assert(got.distance == floor.depth, 'its distance the depth');
            match reference {
                Option::None => { reference = Option::Some(got); },
                Option::Some(first) => { assert(got == first, 'the same in every order'); },
            }
        }
        i += 1;
    }
}

#[test]
fn test_zero_residue_n6() {
    zero_residue(6, 0, 8);
}

#[test]
fn test_zero_residue_n12_0() {
    zero_residue(12, 0, 4);
}

#[test]
fn test_zero_residue_n12_1() {
    zero_residue(12, 4, 4);
}

/// The revealable chunks of ENG-05's floor now, by index, `but` left out.
fn revealable(
    site: @eng05::Site, progress: @eng05::Progress, known: Span<(u8, Terrain)>, but: u8,
) -> Array<u8> {
    let near = BoardTrait::minus(OutlineTrait::around(*progress.revealed), *progress.revealed);
    let mut out: Array<u8> = array![];
    for c in chunks(BoardTrait::and(near, OutlineTrait::rectangle(15, 15))) {
        if c != but && eng05::RevealTrait::revealable(site, progress, known, c) {
            out.append(c);
        }
    }
    out
}

/// The exit's draw `u` of a chunk on ENG-05's floor (quota 0, the first draw of its quotas'
/// stream): the chunk takes the exit without forcing when `u < 1`.
fn exit_u(entropy: felt252, chunk: u8, n: u8) -> u128 {
    let word = EntropyTrait::word(entropy, INSTANCE, chunk);
    let mut rng = RngTrait::new(RngTrait::mix(word, 2));
    let bound: u128 = n.into();
    rng.draw(bound.try_into().unwrap())
}

/// ENG-05's floor revealed honestly (the lowest revealable index each time) or by t-0077's
/// forcing order (`force`: keep `X`, the lowest open neighbour of the entry, for last; avoid the
/// chunks whose `u` hits the exit; reveal `X` when nothing else can be).
fn eng05_floor(entropy: felt252, n: u8, force: bool) -> Outcome {
    let site = eng05_site(n);
    let mut progress = eng05::ProgressTrait::new(@site, entropy);
    let mut known: Array<(u8, Terrain)> = array![];
    let mut out: Array<eng05::Revealed> = array![];
    let mut next: Option<u8> = Option::Some(ENTRY);
    let mut kept: u8 = 255;
    while let Option::Some(chunk) = next {
        let revealed = eng05::RevealTrait::reveal(
            @site, ref progress, INSTANCE, known.span(), array![chunk].span(),
        );
        for entry in revealed {
            known.append((entry.chunk, entry.terrain));
            out.append(entry);
        }
        if force && kept == 255 {
            let first = revealable(@site, @progress, known.span(), 255);
            if first.len() != 0 {
                kept = *first[0];
            }
        }
        let others = revealable(@site, @progress, known.span(), kept);
        next =
            if !force {
                if others.len() == 0 {
                    Option::None
                } else {
                    Option::Some(*others[0])
                }
            } else {
                let mut pick: Option<u8> = Option::None;
                // `X` as the `N`-th chunk, where the exit still owed is forced
                if kept != 255
                    && progress.count + 1 == n
                    && eng05::RevealTrait::revealable(@site, @progress, known.span(), kept) {
                    pick = Option::Some(kept);
                }
                for c in others.span() {
                    if pick.is_none() && exit_u(entropy, *c, n) != 0 {
                        pick = Option::Some(*c);
                    }
                }
                if pick.is_none() && others.len() != 0 {
                    pick = Option::Some(*others[0]);
                }
                if pick.is_none()
                    && kept != 255
                    && eng05::RevealTrait::revealable(@site, @progress, known.span(), kept) {
                    pick = Option::Some(kept);
                }
                pick
            };
    }
    eng05_outcome(@progress, out.span())
}

/// The residue on ENG-05's engine, measured: over 8 entropies at `N` = 12, the exit's distance on
/// the honest order and on the forcing order. The comparison of `zero_residue` fails there.
#[test]
fn test_residue_eng05() {
    let mut differ: u32 = 0;
    let mut gain: u32 = 0;
    let mut ones: u32 = 0;
    let mut i: u32 = 0;
    while i != 8 {
        let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
        let honest = eng05_floor(entropy, 12, false);
        let forced = eng05_floor(entropy, 12, true);
        println!(
            "ENG-05, entropy {}: honest exit {} at {} ({} exits); forcing order exit {} at {} ({} exits)",
            i,
            honest.exit,
            honest.distance,
            honest.exits,
            forced.exit,
            forced.distance,
            forced.exits,
        );
        if honest.exit != forced.exit || honest.distance != forced.distance {
            differ += 1;
        }
        if forced.distance == 1 {
            ones += 1;
        }
        if honest.distance != 255 && forced.distance < honest.distance {
            gain += (honest.distance - forced.distance).into();
        }
        i += 1;
    }
    println!(
        "ENG-05: {} of 8 floors differ; the forcing order's exit at 1 chunk on {}; chunks gained against the honest order in all {}",
        differ,
        ones,
        gain,
    );
    assert(differ != 0, 'ENG-05 shows the residue');
    assert(ones != 0, 'the exit forced at 1');
}
