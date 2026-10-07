//! The outline's properties (`spk17::outline`): over many entropies and each `N`, the floor holds
//! exactly `N` chunks with its entry, is connected through its open seams, has seams between its
//! own chunks only, and is the same draw twice; its farthest chunks are not the entry. Prints the
//! farthest distance's spread (the exit's distance on an honest floor, now fixed at entry).

use core::poseidon::poseidon_hash_span;
use grimworld_logic::types::reveal::board::BoardTrait;
use spk17::outline::{Outline, OutlineTrait};
use crate::fixtures::{ENTRY, INSTANCE, chunks, create};

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

fn sweep(n: u8, seeds: u32, winding: bool) {
    let mut low: u8 = 255;
    let mut high: u8 = 0;
    let mut sum: u32 = 0;
    let mut i: u32 = 0;
    while i != seeds {
        let entropy = poseidon_hash_span(['spk17 outline', i.into()].span());
        let seed = OutlineTrait::seed(entropy, INSTANCE);
        let outline = if winding {
            OutlineTrait::draw_winding(ENTRY, n, 15, 15, seed)
        } else {
            OutlineTrait::draw(ENTRY, n, 15, 15, seed)
        };
        let again = if winding {
            OutlineTrait::draw_winding(ENTRY, n, 15, 15, seed)
        } else {
            OutlineTrait::draw(ENTRY, n, 15, 15, seed)
        };
        assert(outline == again, 'the same draw');
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
    let label: ByteArray = if winding {
        " (winding)"
    } else {
        ""
    };
    println!(
        "N = {}{}: the farthest distance over {} entropies: min {}, max {}, sum {}",
        n,
        label,
        seeds,
        low,
        high,
        sum,
    );
}

#[test]
fn test_outline_n6() {
    sweep(6, 64, false);
}

#[test]
fn test_outline_n9() {
    sweep(9, 64, false);
}

#[test]
fn test_outline_n12() {
    sweep(12, 64, false);
}

#[test]
fn test_outline_winding_n6() {
    sweep(6, 64, true);
}

#[test]
fn test_outline_winding_n12() {
    sweep(12, 64, true);
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

/// The two stored felts give back the outline and every quota's hosts (`pack`, `unpack`).
#[test]
fn test_layout_round_trip() {
    let mut i: u32 = 0;
    while i != 8 {
        let entropy = poseidon_hash_span(['spk17 layout', i.into()].span());
        let floor = create(entropy, 12);
        let word = floor.outline.pack(floor.hosts);
        let (outline, hosts) = OutlineTrait::unpack(floor.outline.chunks, word);
        assert(outline == floor.outline, 'the outline back');
        let mut q: u32 = 0;
        for host in hosts.span() {
            let expected = if q < floor.hosts.len() {
                *floor.hosts[q]
            } else {
                0
            };
            assert(*host == expected, 'the hosts back');
            q += 1;
        }
        i += 1;
    }
}
