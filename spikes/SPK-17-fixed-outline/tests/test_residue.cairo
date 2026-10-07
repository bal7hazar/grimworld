//! **The zero-residue test** (ENG-10a deliverable 2; ENG-10b's merge gate, the Overseer,
//! 2026-10-07): for a set of entropies, every required order of the reveals gives the same chunk
//! set, the same exit chunk and the same exit-to-entry distance in chunks (and the same edges, one
//! exit and one Heart, in the outline's farthest layer). ENG-10b keeps it as `test_zero_residue` on
//! the real path. The required orders: by index, backward, nearest first, farthest first, two
//! drawn, and **t-0077's forcing order** (the entry's first neighbour kept for the last reveal;
//! review t-0088, minor 3). Review t-0088's major 1 is a fixture of its own
//! (`test_zero_residue_piece_*`):
//! floors whose farthest layer is one chunk, with a set piece of 2 packs and 3 objects listed
//! before the exit and the Heart.
//!
//! **The tiles** (review t-0088, minor 2; D-224): the walked distance in tiles from the entry tile
//! to the exit's tile is compared too: a seam's openings are drawn from the seam's own stream
//! (D-224), so no order moves them. Before D-224 (the openings drawn by whichever of a seam's
//! chunks was revealed first) it moved by up to 24 tiles over the orders of one floor (`a2d740b`'s
//! run).
//!
//! **The same assertions on ENG-05's engine** (`test_zero_residue_on_eng05_*`, a floor a test): the
//! seven orders as strategies over what ENG-05 makes revealable, the comparison of `zero_residue`
//! applied; it fails there, and each test asserts that it does. `test_residue_eng05` prints the
//! honest order against the forcing one (the residue's figure).

use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::Terrain;
use grimworld_logic::types::reveal as eng05;
use grimworld_logic::types::reveal::board::BoardTrait;
use hexx::board::rng::RngTrait;
use spk17::outline::OutlineTrait;
use crate::fixtures::{
    ENTRY, INSTANCE, Outcome, chunks, create_with, eng05_outcome, eng05_site, fixed_outcome,
    hosts_old, reveal_in_order, shuffled,
};

/// The required orders of one floor, the entry first in each, as `create` reveals it.
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
    // t-0077's forcing order: `X`, the entry's first neighbour, revealed last
    let x = *layers[1][0];
    let mut forcing = array![ENTRY];
    for c in rest.span() {
        if *c != x {
            forcing.append(*c);
        }
    }
    forcing.append(x);
    let drawn_1 = shuffled(ascending.span(), poseidon_hash_span([entropy, 'order 1'].span()));
    let drawn_2 = shuffled(ascending.span(), poseidon_hash_span([entropy, 'order 2'].span()));
    array![ascending, descending, nearest, farthest, drawn_1, drawn_2, forcing]
}

/// ENG-10b's gate on the spike's engine, over `floors` floors of `n` chunks from the entropies
/// counted from `first`; with review t-0088's set piece when `piece`, keeping only the floors whose
/// farthest layer is one chunk. Returns the largest spread of the walked tile distance, entry tile
/// to exit tile, over the orders of one floor.
fn zero_residue(n: u8, first: u32, floors: u32, piece: bool) -> u32 {
    let mut spread: u32 = 0;
    let mut done: u32 = 0;
    let mut i: u32 = first;
    while done != floors {
        let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
        i += 1;
        let floor = create_with(entropy, n, piece);
        if piece && BoardTrait::count(floor.far) != 1 {
            continue;
        }
        done += 1;
        if piece {
            // Review t-0089, note 2: where the set piece went (quota 0), never on the farthest
            // chunk, which the exit and the Heart took first
            let at = *floor.hosts[0];
            assert(at != 0, 'the set piece hosted');
            assert(BoardTrait::and(at, floor.far) == 0, 'the set piece off the far chunk');
            println!(
                "floor {} (N = {}): the set piece on chunk {}", i - 1, n, BoardTrait::nth(at, 0),
            );
        }
        let mut reference: Option<Outcome> = Option::None;
        let mut low: u32 = 65535;
        let mut high: u32 = 0;
        for order in orders(@floor.outline, entropy) {
            let (progress, out) = reveal_in_order(@floor.site, entropy, order.span());
            let (got, tiles) = fixed_outcome(@progress, out.span());
            assert(progress.count == n, 'every chunk revealed');
            assert(got.revealed == floor.outline.chunks, 'the outline revealed');
            assert(got.exits == 1, 'one exit');
            assert(got.hearts == 1, 'one Heart');
            assert(BoardTrait::has(floor.far, got.exit), 'the exit at the farthest');
            assert(BoardTrait::has(floor.far, got.heart), 'the Heart at the farthest');
            assert(got.distance == floor.depth, 'its distance the depth');
            assert(tiles != 65535, 'the exit reached');
            // D-224: the walk in tiles too, the openings drawn by their seam
            if low != 65535 {
                assert(tiles == low, 'the same walk in tiles');
            }
            match reference {
                Option::None => { reference = Option::Some(got); },
                Option::Some(first) => { assert(got == first, 'the same in every order'); },
            }
            if tiles < low {
                low = tiles;
            }
            if tiles > high {
                high = tiles;
            }
        }
        println!("floor {} (N = {}): the exit at {} to {} tiles", i - 1, n, low, high);
        if high - low > spread {
            spread = high - low;
        }
    }
    println!("N = {}: the largest spread in tiles over the orders of a floor: {}", n, spread);
    spread
}

#[test]
fn test_zero_residue_n6_0() {
    zero_residue(6, 0, 4, false);
}

#[test]
fn test_zero_residue_n6_1() {
    zero_residue(6, 4, 4, false);
}

#[test]
fn test_zero_residue_n12_0() {
    zero_residue(12, 0, 2, false);
}

#[test]
fn test_zero_residue_n12_1() {
    zero_residue(12, 2, 2, false);
}

#[test]
fn test_zero_residue_n12_2() {
    zero_residue(12, 4, 2, false);
}

#[test]
fn test_zero_residue_n12_3() {
    zero_residue(12, 6, 2, false);
}

/// Review t-0088's major 1: a farthest layer of one chunk, a set piece (2 packs, 3 objects) listed
/// before the exit and the Heart; both placed, in every order.
#[test]
fn test_zero_residue_piece_n6() {
    zero_residue(6, 100, 4, true);
}

#[test]
fn test_zero_residue_piece_n12() {
    zero_residue(12, 100, 2, true);
}

/// Review t-0089, note 2: the set-piece fixture with c240f76's order (the list's, the farthest
/// layer only): over the floors of 6 chunks whose farthest layer is one chunk, from entropy 100,
/// some leave the exit or the Heart with no host there; the new order hosts both on every one of
/// them.
#[test]
fn test_piece_old_order() {
    let mut floors: u32 = 0;
    let mut failing: u32 = 0;
    let mut i: u32 = 100;
    while floors != 32 {
        let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
        i += 1;
        let (old, far) = hosts_old(entropy, 6);
        if BoardTrait::count(far) != 1 {
            continue;
        }
        floors += 1;
        let new = create_with(entropy, 6, true);
        assert(*new.hosts[1] != 0 && *new.hosts[2] != 0, 'the new order hosts both');
        if *old[1] == 0 || *old[2] == 0 {
            failing += 1;
            println!(
                "floor {}: the old order leaves the exit {} and the Heart {} (0: no host)",
                i - 1,
                *old[1],
                *old[2],
            );
        }
    }
    println!("the old order fails on {} of {} floors; the new one on none", failing, floors);
    assert(failing != 0, 'the old order fails');
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

/// A chunk's distance in chunks to the entry chunk (`|dcx| + |dcy|`).
fn manhattan(chunk: u8) -> u8 {
    let (cy, cx) = DivRem::div_rem(chunk, 15);
    let dx = if cx > 7 {
        cx - 7
    } else {
        7 - cx
    };
    let dy = if cy > 7 {
        cy - 7
    } else {
        7 - cy
    };
    dx + dy
}

pub mod order {
    pub const ASCENDING: u8 = 0;
    pub const DESCENDING: u8 = 1;
    pub const NEAREST: u8 = 2;
    pub const FARTHEST: u8 = 3;
    pub const DRAWN_1: u8 = 4;
    pub const DRAWN_2: u8 = 5;
    pub const FORCING: u8 = 6;
}

/// ENG-05's floor revealed by one of the seven orders, as a strategy over what ENG-05 makes
/// revealable at each step (its outline emerges, so no list of chunks is fixed in advance): the
/// lowest or highest index, the nearest or farthest from the entry chunk, a drawn one, or t-0077's
/// forcing order (keep `X`, the lowest open neighbour of the entry, for the `N`-th reveal; avoid
/// the chunks whose `u` hits the exit; reveal `X` when nothing else can be).
fn eng05_floor(entropy: felt252, n: u8, strategy: u8) -> Outcome {
    let site = eng05_site(n);
    let mut progress = eng05::ProgressTrait::new(@site, entropy);
    let mut known: Array<(u8, Terrain)> = array![];
    let mut out: Array<eng05::Revealed> = array![];
    let mut next: Option<u8> = Option::Some(ENTRY);
    let mut kept: u8 = 255;
    let force = strategy == order::FORCING;
    let mut step: felt252 = 0;
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
        step += 1;
        next =
            if !force {
                if others.len() == 0 {
                    Option::None
                } else if strategy == order::ASCENDING {
                    Option::Some(*others[0])
                } else if strategy == order::DESCENDING {
                    Option::Some(*others[others.len() - 1])
                } else if strategy == order::NEAREST || strategy == order::FARTHEST {
                    let mut pick = *others[0];
                    for c in others.span() {
                        let closer = manhattan(*c) < manhattan(pick);
                        let farther = manhattan(*c) > manhattan(pick);
                        if (strategy == order::NEAREST && closer)
                            || (strategy == order::FARTHEST && farther) {
                            pick = *c;
                        }
                    }
                    Option::Some(pick)
                } else {
                    let word: u256 = poseidon_hash_span([entropy, strategy.into(), step].span())
                        .into();
                    let bound: u128 = others.len().into();
                    let (_, j) = DivRem::div_rem(word.low, bound.try_into().unwrap());
                    Option::Some(*others[j.try_into().unwrap()])
                }
            } else {
                let mut pick: Option<u8> = Option::None;
                // `X` as the `N`-th chunk, where the exit still owed is forced
                if kept != 255 && progress.count
                    + 1 == n
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
    let (got, _) = eng05_outcome(@progress, out.span());
    got
}

/// Review t-0088, minor 3: `zero_residue`'s comparison (the same chunk set, exit chunk and distance
/// in chunks in every order) with the seven orders, once on ENG-05's merged engine, `N` = 12, on
/// the four entropies of `test_zero_residue_n12_0` and `_1`, a floor a test: it fails there. Prints
/// the orders whose outcome differs from the first; returns how many.
fn on_eng05(i: u32) -> u32 {
    let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
    let first = eng05_floor(entropy, 12, order::ASCENDING);
    let mut differ: u32 = 0;
    let mut strategy: u8 = 1;
    while strategy != 7 {
        let got = eng05_floor(entropy, 12, strategy);
        if got.revealed != first.revealed
            || got.exit != first.exit
            || got.distance != first.distance {
            println!(
                "ENG-05, entropy {}: order {} differs (exit {} at {}, against {} at {})",
                i,
                strategy,
                got.exit,
                got.distance,
                first.exit,
                first.distance,
            );
            differ += 1;
        }
        strategy += 1;
    }
    println!("ENG-05, entropy {}: {} of 6 orders differ from the first", i, differ);
    differ
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_zero_residue_on_eng05_0() {
    assert(on_eng05(0) != 0, 'it fails on ENG-05');
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_zero_residue_on_eng05_1() {
    assert(on_eng05(1) != 0, 'it fails on ENG-05');
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_zero_residue_on_eng05_2() {
    assert(on_eng05(2) != 0, 'it fails on ENG-05');
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_zero_residue_on_eng05_3() {
    assert(on_eng05(3) != 0, 'it fails on ENG-05');
}

/// The residue on ENG-05's engine, measured: over 8 entropies at `N` = 12, the exit's distance on
/// the honest order and on the forcing order.
#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_residue_eng05() {
    let mut differ: u32 = 0;
    let mut gain: u32 = 0;
    let mut ones: u32 = 0;
    let mut i: u32 = 0;
    while i != 8 {
        let entropy = poseidon_hash_span(['spk17 residue', i.into()].span());
        let honest = eng05_floor(entropy, 12, order::ASCENDING);
        let forced = eng05_floor(entropy, 12, order::FORCING);
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
        "ENG-05: {} of 8 floors differ; the forcing order's exit at 1 chunk on {}; {} chunks gained in all",
        differ,
        ones,
        gain,
    );
    assert(differ != 0, 'ENG-05 shows the residue');
    assert(ones != 0, 'the exit forced at 1');
}
