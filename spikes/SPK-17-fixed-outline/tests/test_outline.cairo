//! The outline's properties (`spk17::outline`): over many entropies and each `N`, the floor holds
//! exactly `N` chunks with its entry, is connected through its open seams, has seams between its
//! own chunks only, and is the same draw twice; its farthest chunks are not the entry. Prints the
//! farthest distance's spread (the exit's distance on an honest floor, now fixed at entry).

use core::poseidon::poseidon_hash_span;
use grimworld_logic::types::reveal::board::BoardTrait;
use spk17::outline::{Outline, OutlineTrait};
use crate::fixtures::{ENTRY, INSTANCE, chunks};

fn check(outline: @Outline, n: u8) -> u8 {
    let set = *outline.chunks;
    assert(BoardTrait::count(set) == n, 'N chunks');
    assert(BoardTrait::has(set, ENTRY), 'the entry in it');
    // Seams between two chunks of the floor, on one row for West
    for c in chunks(*outline.west) {
        let (_, cx) = DivRem::div_rem(c, 15);
        assert(cx != 14, 'west seam on the row');
        assert(BoardTrait::has(set, c) && BoardTrait::has(set, c + 1), 'west seam inside');
    }
    for c in chunks(*outline.north) {
        assert(BoardTrait::has(set, c) && BoardTrait::has(set, c + 15), 'north seam inside');
    }
    // Connected: every chunk reached through the open seams
    for c in chunks(set) {
        assert(outline.distance(ENTRY, c) != 255, 'connected');
    }
    let (far, depth) = outline.far(ENTRY);
    assert(far != 0 && !BoardTrait::has(far, ENTRY), 'far not the entry');
    assert(depth >= 1 && depth <= n - 1, 'depth in [1, N-1]');
    for c in chunks(far) {
        assert(outline.distance(ENTRY, c) == depth, 'far at the depth');
    }
    depth
}

fn sweep(n: u8, seeds: u32) {
    let mut low: u8 = 255;
    let mut high: u8 = 0;
    let mut sum: u32 = 0;
    let mut i: u32 = 0;
    while i != seeds {
        let entropy = poseidon_hash_span(['spk17 outline', i.into()].span());
        let seed = OutlineTrait::seed(entropy, INSTANCE);
        let outline = OutlineTrait::draw(ENTRY, n, 15, 15, seed);
        assert(outline == OutlineTrait::draw(ENTRY, n, 15, 15, seed), 'the same draw');
        let depth = check(@outline, n);
        if depth < low {
            low = depth;
        }
        if depth > high {
            high = depth;
        }
        sum += depth.into();
        i += 1;
    }
    println!("N = {}: the farthest distance over {} entropies: min {}, max {}, sum {}", n, seeds, low, high, sum);
}

#[test]
fn test_outline_n6() {
    sweep(6, 64);
}

#[test]
fn test_outline_n9() {
    sweep(9, 64);
}

#[test]
fn test_outline_n12() {
    sweep(12, 64);
}

/// A rectangle smaller than `N`: the floor is the whole rectangle (no panic, D-140).
#[test]
fn test_outline_small_rectangle() {
    let outline = OutlineTrait::draw(0, 12, 3, 2, 'seed');
    assert(outline.chunks == OutlineTrait::rectangle(3, 2), 'the whole rectangle');
    for c in chunks(outline.chunks) {
        assert(outline.distance(0, c) != 255, 'connected');
    }
}
