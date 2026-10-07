//! The costs of ENG-10a deliverable 3, each a pair: `test_pair_<group>_<what>` less its base
//! `test_base_<group>` (`pairs.py`), two tests that differ by the measured call alone (CBT-02d's
//! method, as SPK-16). At `create`: the outline's draw, with the hosts; the library call; the new
//! slots. A reveal: one chunk and a whole floor on ENG-05's engine and on the changed one.

use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::Terrain;
use grimworld_logic::types::reveal as eng05;
use grimworld_logic::types::reveal::board::BoardTrait;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use spk17::engine::placement::PlacementTrait;
use spk17::engine::{ProgressTrait, RevealTrait};
use spk17::library::{
    IFloorLibraryDispatcherTrait, IFloorLibraryLibraryDispatcher, ISlotsDispatcher,
    ISlotsDispatcherTrait,
};
use spk17::outline::OutlineTrait;
use crate::fixtures::{ENTRY, INSTANCE, chunks, create, eng05_site, floor_site};

const ENTROPY: felt252 = 'spk17 cost';

// ---- At `create`, in memory: the outline, then the hosts ----

/// The inputs: the seeds, the bare site and its plan.
fn inputs(n: u8) -> (felt252, felt252, (felt252, felt252)) {
    let outline_seed = OutlineTrait::seed(ENTROPY, INSTANCE);
    let hosts_seed = EntropyTrait::hosts(ENTROPY, INSTANCE);
    let bare = floor_site(n, OutlineTrait::draw(ENTRY, 1, 15, 15, 0), array![].span());
    let progress = ProgressTrait::new(@bare, ENTROPY);
    (outline_seed, hosts_seed, PlacementTrait::plan(@bare, progress.left.span()))
}

#[test]
fn test_base_outline() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
}

#[test]
fn test_pair_outline_draw_6() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let outline = OutlineTrait::draw(ENTRY, 6, 15, 15, outline_seed);
    assert(outline.chunks != 0, 'drawn');
}

#[test]
fn test_pair_outline_draw_12() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let outline = OutlineTrait::draw(ENTRY, 12, 15, 15, outline_seed);
    assert(outline.chunks != 0, 'drawn');
}

#[test]
fn test_pair_outline_winding_12() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let outline = OutlineTrait::draw_winding(ENTRY, 12, 15, 15, outline_seed);
    assert(outline.chunks != 0, 'drawn');
}

#[test]
fn test_pair_outline_frontier_12() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let outline = OutlineTrait::draw_frontier(ENTRY, 12, 15, 15, outline_seed);
    assert(outline.chunks != 0, 'drawn');
}

/// What `create` computes for a floor of 12 (the winding law, D-223): the outline, its layers by
/// distance, the hosts (the exit and the Heart first, then the vein), the entry chunk's mask.
#[test]
fn test_pair_outline_floor_12() {
    let (outline_seed, hosts_seed, plan) = inputs(12);
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let outline = OutlineTrait::draw_winding(ENTRY, 12, 15, 15, outline_seed);
    let layers = outline.layers(ENTRY);
    let hosts = PlacementTrait::hosts(
        outline.chunks, 15, 15, plan, array![].span(), hosts_seed, layers.span(),
    )
        .span();
    let mask = PlacementTrait::with_hosts(0, hosts, ENTRY);
    assert(mask != 0, 'drawn');
}

// ---- A zone's hosts: origin/main's `PlacementTrait::hosts` against the spike's (review t-0089)
// ----

/// A zone's plan: 15 × 15, a vein (3), a collector (2), a Heart (1).
fn zone_plan() -> (felt252, felt252) {
    let vein: felt252 = 3 + 0x100 * 3;
    let collector: felt252 = 2 + 0x100 * 4 + 0x10000 * 1;
    let heart: felt252 = 1 + 0x100 * 2 + 0x10000 * 3;
    (vein + collector * 0x100000000 + heart * 0x10000000000000000, 0)
}

#[test]
fn test_base_hosts_zone() {
    let plan = zone_plan();
    let seed = EntropyTrait::hosts(ENTROPY, INSTANCE);
    assert(plan != (0, 0) && seed != 0, 'inputs');
}

#[test]
fn test_pair_hosts_zone_main() {
    let plan = zone_plan();
    let seed = EntropyTrait::hosts(ENTROPY, INSTANCE);
    assert(plan != (0, 0) && seed != 0, 'inputs');
    let hosts = eng05::placement::PlacementTrait::hosts(0, 15, 15, plan, array![].span(), seed);
    assert(hosts.len() == 3, 'drawn');
}

#[test]
fn test_pair_hosts_zone_spike() {
    let plan = zone_plan();
    let seed = EntropyTrait::hosts(ENTROPY, INSTANCE);
    assert(plan != (0, 0) && seed != 0, 'inputs');
    let hosts = PlacementTrait::hosts(0, 15, 15, plan, array![].span(), seed, array![].span());
    assert(hosts.len() == 3, 'drawn');
}

/// The same masks for a zone, both copies.
#[test]
fn test_hosts_zone_unchanged() {
    let plan = zone_plan();
    let seed = EntropyTrait::hosts(ENTROPY, INSTANCE);
    let main = eng05::placement::PlacementTrait::hosts(0, 15, 15, plan, array![].span(), seed);
    let spike = PlacementTrait::hosts(0, 15, 15, plan, array![].span(), seed, array![].span());
    assert(main == spike, 'a zone unchanged');
}

// ---- At `create`, the library call ----

#[test]
fn test_base_library() {
    let class_hash = *declare("FloorLibrary").unwrap().contract_class().class_hash;
    let (outline_seed, hosts_seed, plan) = inputs(12);
    let library = IFloorLibraryLibraryDispatcher { class_hash };
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let _ = library;
}

#[test]
fn test_pair_library_floor_12() {
    let class_hash = *declare("FloorLibrary").unwrap().contract_class().class_hash;
    let (outline_seed, hosts_seed, plan) = inputs(12);
    let library = IFloorLibraryLibraryDispatcher { class_hash };
    assert(outline_seed != hosts_seed && plan != (0, 0), 'inputs');
    let (outline, hosts, masks) = library
        .floor(
            ENTRY,
            12,
            15,
            15,
            plan,
            array![].span(),
            array![ENTRY].span(),
            outline_seed,
            hosts_seed,
        );
    assert(outline.chunks != 0 && hosts.len() != 0 && masks.len() == 1, 'drawn');
}

// ---- At `create`, the new slots: the outline's three felts and three hosts' bitmaps ----

fn slots() -> ISlotsDispatcher {
    let class = declare("Slots").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    ISlotsDispatcher { contract_address: address }
}

#[test]
fn test_base_slots() {
    let store = slots();
    let floor = create(ENTROPY, 12);
    store.nothing(1, floor.outline, floor.hosts);
}

#[test]
fn test_pair_slots_write() {
    let store = slots();
    let floor = create(ENTROPY, 12);
    store.write(1, floor.outline, floor.hosts);
}

/// ENG-10a's layout: the two felts.
#[test]
fn test_base_slots_packed() {
    let store = slots();
    let floor = create(ENTROPY, 12);
    let word = floor.outline.pack(floor.hosts);
    store.nothing_packed(1, floor.outline.chunks, word);
}

#[test]
fn test_pair_slots_packed_write() {
    let store = slots();
    let floor = create(ENTROPY, 12);
    let word = floor.outline.pack(floor.hosts);
    store.write_packed(1, floor.outline.chunks, word);
}

// ---- The layout in memory: packed at `create`, unpacked at each invocation that reveals ----

#[test]
fn test_base_layout() {
    let floor = create(ENTROPY, 12);
    assert(floor.hosts.len() != 0, 'fixture');
}

#[test]
fn test_pair_layout_pack() {
    let floor = create(ENTROPY, 12);
    assert(floor.hosts.len() != 0, 'fixture');
    let word = floor.outline.pack(floor.hosts);
    assert(word != 0, 'packed');
}

#[test]
fn test_base_layout_packed() {
    let floor = create(ENTROPY, 12);
    let word = floor.outline.pack(floor.hosts);
    assert(word != 0, 'fixture');
}

#[test]
fn test_pair_layout_packed_unpack() {
    let floor = create(ENTROPY, 12);
    let word = floor.outline.pack(floor.hosts);
    assert(word != 0, 'fixture');
    let (outline, hosts) = OutlineTrait::unpack(floor.outline.chunks, word);
    assert(outline.chunks != 0 && hosts.len() == 14, 'unpacked');
}

// ---- A reveal: ENG-05's engine against the changed one, N = 12 ----

/// ENG-05's floor with its entry revealed, and the lowest revealable chunk next.
fn eng05_entry() -> (eng05::Site, eng05::Progress, Array<(u8, Terrain)>, u8) {
    let site = eng05_site(12);
    let mut progress = eng05::ProgressTrait::new(@site, ENTROPY);
    let out = eng05::RevealTrait::reveal(
        @site, ref progress, INSTANCE, array![].span(), array![ENTRY].span(),
    );
    let mut known: Array<(u8, Terrain)> = array![];
    for entry in out {
        known.append((entry.chunk, entry.terrain));
    }
    let mut next: u8 = 255;
    for c in array![ENTRY + 1, ENTRY - 1, ENTRY - 15, ENTRY + 15] {
        if next == 255 && eng05::RevealTrait::revealable(@site, @progress, known.span(), c) {
            next = c;
        }
    }
    (site, progress, known, next)
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_base_reveal_eng05() {
    let (_, progress, _, next) = eng05_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
}

#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_pair_reveal_eng05_one() {
    let (site, mut progress, known, next) = eng05_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
    let out = eng05::RevealTrait::reveal(
        @site, ref progress, INSTANCE, known.span(), array![next].span(),
    );
    assert(out.len() == 1, 'revealed');
}

/// The rest of the floor, the lowest revealable index each time, until `N`.
#[test]
// ENG-10b (#385) replaced ENG-05's emerging engine in `grimworld_logic`, which this spike reads by
// path: this test measured that engine; its figures are in `snforge-test-output-{1,2}.txt`
// (41d9009).
#[ignore]
fn test_pair_reveal_eng05_floor() {
    let (site, mut progress, known, next) = eng05_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
    let mut known = known;
    let mut more = true;
    while more {
        more = false;
        let near = BoardTrait::minus(OutlineTrait::around(progress.revealed), progress.revealed);
        let mut pick: u8 = 255;
        for c in chunks(BoardTrait::and(near, OutlineTrait::rectangle(15, 15))) {
            if pick == 255 && eng05::RevealTrait::revealable(@site, @progress, known.span(), c) {
                pick = c;
            }
        }
        if pick != 255 {
            let out = eng05::RevealTrait::reveal(
                @site, ref progress, INSTANCE, known.span(), array![pick].span(),
            );
            for entry in out {
                known.append((entry.chunk, entry.terrain));
            }
            more = true;
        }
    }
    println!("ENG-05 floor: {} chunks revealed", progress.count);
}

/// The changed engine's floor (`create` as ENG-10b computes it) with its entry revealed, and its
/// lowest chunk through an open seam of the entry next.
fn fixed_entry() -> (crate::fixtures::Floor, spk17::engine::Progress, Array<(u8, Terrain)>, u8) {
    let floor = create(ENTROPY, 12);
    let mut progress = ProgressTrait::new(@floor.site, ENTROPY);
    let out = RevealTrait::reveal(
        @floor.site, ref progress, INSTANCE, array![].span(), array![ENTRY].span(),
    );
    let mut known: Array<(u8, Terrain)> = array![];
    for entry in out {
        known.append((entry.chunk, entry.terrain));
    }
    let mut next: u8 = 255;
    for c in chunks(floor.outline.chunks) {
        if next == 255 && floor.outline.distance(ENTRY, c) == 1 {
            next = c;
        }
    }
    (floor, progress, known, next)
}

#[test]
fn test_base_reveal_fixed() {
    let (_, progress, _, next) = fixed_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
}

#[test]
fn test_pair_reveal_fixed_one() {
    let (floor, mut progress, known, next) = fixed_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
    let out = RevealTrait::reveal(
        @floor.site, ref progress, INSTANCE, known.span(), array![next].span(),
    );
    assert(out.len() == 1, 'revealed');
}

/// The rest of the floor, by index.
#[test]
fn test_pair_reveal_fixed_floor() {
    let (floor, mut progress, known, next) = fixed_entry();
    assert(progress.count == 1 && next != 255, 'fixture');
    let mut known = known;
    for c in chunks(floor.outline.chunks) {
        if c != ENTRY {
            let out = RevealTrait::reveal(
                @floor.site, ref progress, INSTANCE, known.span(), array![c].span(),
            );
            for entry in out {
                known.append((entry.chunk, entry.terrain));
            }
        }
    }
    assert(progress.count == 12, 'the floor');
}

#[test]
fn test_entropy_word_apart() {
    // The outline's counter is no chunk's, nor the hosts' (225) nor an authored zone's (226)
    let seed = OutlineTrait::seed(ENTROPY, INSTANCE);
    let mut chunk: u32 = 0;
    while chunk != 227 {
        assert(seed != EntropyTrait::word(ENTROPY, INSTANCE, chunk.try_into().unwrap()), 'apart');
        chunk += 1;
    }
    assert(seed != poseidon_hash_span([ENTROPY].span()), 'apart');
}
