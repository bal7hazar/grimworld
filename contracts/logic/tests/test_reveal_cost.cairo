// ENG-05: the cost of a reveal in memory (docs/CAIRO.md §2: benchmarks on the worst case, "a
// reveal of 3 chunks"), each test less its baseline (`test_cost_reveal_baseline`, the same content
// and progress built, nothing revealed). Benchmarks of several modules' code together, kept apart
// from the engine's unit tests (D-167).
//
// - worst: a chunk with no revealed neighbour (four sides drawn, 1 or 2 openings each), every quota
//   due (left at the chunks left: an exit, a vein and a collector, three objects, and a Heart's
//   pack), the spawn table's two slots full of 5-goblin packs, the objects by frequency drawn;
// - typical: a chunk with two sides known, the content of a zone (one collector to place over the
//   chunk set), the spawn table at its density;
// - three: the worst content, three chunks in one call, each knowing the ones before it;
// - the library call: `RevealLibrary` by `library_call`, one chunk, against the same reveal direct.
use grimworld_logic::interface::{IRevealLibraryDispatcherTrait, IRevealLibraryLibraryDispatcher};
use grimworld_logic::models::chunk::Terrain;
use grimworld_logic::models::location::biome;
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{Quota, QuotaSet, kind as quota};
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable};
use grimworld_logic::types::reveal::{Progress, ProgressTrait, RevealTrait, Site};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};

const INSTANCE: felt252 = 0x100000001;

fn packs() -> Span<(u16, Pack)> {
    let five = Pack {
        castes: [
            PackCaste { caste: 1, min: 2, max: 2 }, PackCaste { caste: 2, min: 3, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    array![(1, five), (2, five)].span()
}

/// A 3 × 3 zone (`kind`'s biome), its centre chunk 16 to reveal; `heavy`: every quota due and the
/// spawn table always full.
fn site(kind: u8, heavy: bool) -> Site {
    let (quotas, density) = if heavy {
        (
            QuotaSet {
                quotas: [
                    Quota { kind: quota::EXIT, param: 5, count: 9 },
                    Quota { kind: quota::VEIN, param: 0, count: 9 },
                    Quota { kind: quota::COLLECTOR, param: 1, count: 9 },
                    Quota { kind: quota::HEART, param: 2, count: 9 }, Default::default(),
                    Default::default(),
                ],
            },
            255,
        )
    } else {
        (
            QuotaSet {
                quotas: [
                    Quota { kind: quota::COLLECTOR, param: 1, count: 1 }, Default::default(),
                    Default::default(), Default::default(), Default::default(), Default::default(),
                ],
            },
            128,
        )
    };
    Site {
        target: 0,
        biome: kind,
        level_min: 1,
        level_max: 5,
        width: 3,
        height: 3,
        entry_chunk: 0,
        chunk_set: 0,
        west: 0,
        north: 0,
        masks: array![].span(),
        anchors: array![].span(),
        quotas,
        tasks: array![].span(),
        spawn: SpawnTable {
            spawns: [
                Spawn { template: 1, weight: 1 }, Default::default(), Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
            density,
        },
        packs: packs(),
        pieces: array![].span(),
    }
}

fn progress(site: @Site) -> Progress {
    ProgressTrait::new(site, 'cost')
}

/// The terrain of chunk 1 (South of 16) and 15 (East of 16), revealed first: the typical case's
/// known sides.
fn known(site: @Site) -> Span<(u8, Terrain)> {
    let mut progress = progress(site);
    let out = RevealTrait::reveal(
        site, ref progress, INSTANCE, array![].span(), array![1, 15].span(),
    );
    array![(1, *out[0].terrain), (15, *out[1].terrain)].span()
}

#[test]
#[available_gas(l2_gas: 203774)] // ceil(1.05 × 194070 measured)
fn test_cost_reveal_baseline() {
    let site = site(biome::CAVE, true);
    let _progress = progress(@site);
}

#[test]
#[available_gas(l2_gas: 4140705)] // ceil(1.05 × 3943528 measured)
fn test_cost_reveal_worst_meadow() {
    let site = site(biome::MEADOW, true);
    let mut progress = progress(@site);
    RevealTrait::reveal(@site, ref progress, INSTANCE, array![].span(), array![16].span());
}

#[test]
#[available_gas(l2_gas: 4263115)] // ceil(1.05 × 4060109 measured)
fn test_cost_reveal_worst_forest() {
    let site = site(biome::FOREST, true);
    let mut progress = progress(@site);
    RevealTrait::reveal(@site, ref progress, INSTANCE, array![].span(), array![16].span());
}

#[test]
#[available_gas(l2_gas: 4247823)] // ceil(1.05 × 4045545 measured)
fn test_cost_reveal_worst_cave() {
    let site = site(biome::CAVE, true);
    let mut progress = progress(@site);
    RevealTrait::reveal(@site, ref progress, INSTANCE, array![].span(), array![16].span());
}

#[test]
#[available_gas(l2_gas: 4153813)] // ceil(1.05 × 3956012 measured)
fn test_cost_reveal_worst_ruin() {
    let site = site(biome::RUIN, true);
    let mut progress = progress(@site);
    RevealTrait::reveal(@site, ref progress, INSTANCE, array![].span(), array![16].span());
}

// The typical case's baseline: its known sides revealed, nothing more.
#[test]
#[available_gas(l2_gas: 4960036)] // ceil(1.05 × 4723843 measured)
fn test_cost_reveal_typical_baseline() {
    let site = site(biome::FOREST, false);
    let _known = known(@site);
    let _progress = progress(@site);
}

#[test]
#[available_gas(l2_gas: 7790490)] // ceil(1.05 × 7419514 measured)
fn test_cost_reveal_typical() {
    let site = site(biome::FOREST, false);
    let known = known(@site);
    let mut progress = progress(@site);
    progress.revealed = 2 + 0x8000;
    progress.count = 2;
    RevealTrait::reveal(@site, ref progress, INSTANCE, known, array![16].span());
}

#[test]
#[available_gas(l2_gas: 11487948)] // ceil(1.05 × 10940902 measured)
fn test_cost_reveal_three() {
    let site = site(biome::CAVE, true);
    let mut progress = progress(@site);
    let out = RevealTrait::reveal(
        @site, ref progress, INSTANCE, array![].span(), array![16, 17, 31].span(),
    );
    assert(out.len() == 3, 'three');
}

#[test]
#[available_gas(l2_gas: 4260118)] // ceil(1.05 × 4057255 measured)
fn test_cost_library_baseline() {
    let _class = declare("RevealLibrary").unwrap().contract_class();
    let site = site(biome::CAVE, true);
    let mut progress = progress(@site);
    RevealTrait::reveal(@site, ref progress, INSTANCE, array![].span(), array![16].span());
}

#[test]
#[available_gas(l2_gas: 4831854)] // ceil(1.05 × 4601765 measured)
fn test_cost_library_call() {
    let class = declare("RevealLibrary").unwrap().contract_class();
    let library = IRevealLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let site = site(biome::CAVE, true);
    let progress = progress(@site);
    let (_, out) = library.reveal(site, progress, INSTANCE, array![].span(), array![16].span());
    assert(out.len() == 1, 'one');
}
