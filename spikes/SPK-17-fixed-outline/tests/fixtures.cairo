//! The spike's fixtures: a dungeon floor at `create` (its outline, its hosts, its masks), its
//! reveal in a given order on the changed engine, ENG-05's floor for the negative control, and the
//! outcome of a floor once revealed (what the zero-residue test compares).

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::{Object, Terrain, object};
use grimworld_logic::models::location::biome;
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{Quota, QuotaSet, kind as quota};
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable};
use grimworld_logic::types::reveal as eng05;
use grimworld_logic::types::reveal::board::BoardTrait;
use spk17::engine::placement::PlacementTrait;
use spk17::engine::{Progress, ProgressTrait, RevealTrait, Revealed, Site};
use spk17::outline::{Outline, OutlineTrait};

pub const INSTANCE: felt252 = 0x100000001;
/// A dungeon's entry chunk, (7, 7) of its 15 × 15 rectangle (ENG-01 §3.2).
pub const ENTRY: u8 = 112;

pub fn packs() -> Span<(u16, Pack)> {
    array![
        (
            1,
            Pack {
                castes: [
                    PackCaste { caste: 1, min: 1, max: 2 }, PackCaste { caste: 2, min: 1, max: 3 },
                    Default::default(), Default::default(), Default::default(),
                ],
                level: 0,
            },
        ),
        (
            2,
            Pack {
                castes: [
                    PackCaste { caste: 3, min: 1, max: 1 }, Default::default(), Default::default(),
                    Default::default(), Default::default(),
                ],
                level: 2,
            },
        ),
    ]
        .span()
}

pub fn spawn() -> SpawnTable {
    SpawnTable {
        spawns: [
            Spawn { template: 1, weight: 3 }, Spawn { template: 2, weight: 1 }, Default::default(),
            Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        density: 160,
    }
}

/// A floor's quotas: the exit (quota 0), a vein, the Heart (template 2).
pub fn quotas() -> QuotaSet {
    QuotaSet {
        quotas: [
            Quota { kind: quota::EXIT, param: 5, count: 1 },
            Quota { kind: quota::VEIN, param: 0, count: 1 },
            Quota { kind: quota::HEART, param: 2, count: 1 }, Default::default(),
            Default::default(), Default::default(),
        ],
    }
}

/// The changed engine's dungeon floor of `n` chunks with its outline and masks.
pub fn floor_site(n: u8, outline: Outline, masks: Span<(u8, felt252)>) -> Site {
    Site {
        target: n,
        biome: biome::CAVE,
        level_min: 3,
        level_max: 5,
        width: 15,
        height: 15,
        entry_chunk: ENTRY,
        chunk_set: outline.chunks,
        west: outline.west,
        north: outline.north,
        masks,
        anchors: array![(ENTRY, 112)].span(),
        quotas: quotas(),
        tasks: array![].span(),
        spawn: spawn(),
        packs: packs(),
        pieces: array![].span(),
    }
}

/// ENG-05's dungeon floor of `n` chunks (its outline emerging).
pub fn eng05_site(n: u8) -> eng05::Site {
    eng05::Site {
        target: n,
        biome: biome::CAVE,
        level_min: 3,
        level_max: 5,
        width: 15,
        height: 15,
        entry_chunk: ENTRY,
        chunk_set: 0,
        masks: array![].span(),
        anchors: array![(ENTRY, 112)].span(),
        quotas: quotas(),
        tasks: array![].span(),
        spawn: spawn(),
        packs: packs(),
        pieces: array![].span(),
    }
}

#[derive(Drop)]
pub struct Floor {
    pub site: Site,
    pub outline: Outline,
    pub far: felt252,
    pub depth: u8,
    pub hosts: Span<felt252>,
}

/// What `create` computes for a floor of `n` chunks from `entropy`: the outline, its farthest
/// chunks, the hosts (the exit and the Heart among them), and every chunk's mask with its hosts.
pub fn create(entropy: felt252, n: u8) -> Floor {
    let outline = OutlineTrait::draw(ENTRY, n, 15, 15, OutlineTrait::seed(entropy, INSTANCE));
    let (far, depth) = outline.far(ENTRY);
    let bare = floor_site(n, outline, array![].span());
    let progress = ProgressTrait::new(@bare, entropy);
    let plan = PlacementTrait::plan(@bare, progress.left.span());
    let hosts = PlacementTrait::hosts(
        outline.chunks, 15, 15, plan, bare.pieces, EntropyTrait::hosts(entropy, INSTANCE), far,
    )
        .span();
    let mut masks: Array<(u8, felt252)> = array![];
    for chunk in chunks(outline.chunks) {
        masks.append((chunk, PlacementTrait::with_hosts(0, hosts, chunk)));
    }
    Floor { site: floor_site(n, outline, masks.span()), outline, far, depth, hosts }
}

/// The chunks of `set`, by index.
pub fn chunks(set: felt252) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let count = BoardTrait::count(set);
    let mut i: u8 = 0;
    while i != count {
        out.append(BoardTrait::nth(set, i));
        i += 1;
    }
    out
}

/// Reveals `order` one chunk a call on the changed engine, every revealed chunk known.
pub fn reveal_in_order(
    site: @Site, entropy: felt252, order: Span<u8>,
) -> (Progress, Array<Revealed>) {
    let mut progress = ProgressTrait::new(site, entropy);
    let mut known: Array<(u8, Terrain)> = array![];
    let mut out: Array<Revealed> = array![];
    for chunk in order {
        let revealed = RevealTrait::reveal(
            site, ref progress, INSTANCE, known.span(), array![*chunk].span(),
        );
        for entry in revealed {
            known.append((entry.chunk, entry.terrain));
            out.append(entry);
        }
    }
    (progress, out)
}

/// What a revealed floor shows, whatever the order (the zero-residue test's terms): the chunks
/// revealed, the exit's chunk (255 when none) and how many exits, the edges of every chunk (a sum
/// of hashes, a set), the exit's distance from the entry through the revealed edges (255 when not
/// reached).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Outcome {
    pub revealed: felt252,
    pub exit: u8,
    pub exits: u8,
    pub edges: felt252,
    pub distance: u8,
}

/// The outcome of revealed chunks given as `(chunk, terrain edges, exits in it)`.
pub fn outcome(revealed: felt252, chunks: Span<(u8, u8, u8)>) -> Outcome {
    let mut exit: u8 = 255;
    let mut exits: u8 = 0;
    let mut edges: felt252 = 0;
    let mut seams: Array<(u8, u8)> = array![];
    for entry in chunks {
        let (chunk, chunk_edges, count) = *entry;
        if count != 0 {
            exit = chunk;
            exits += count;
        }
        edges += poseidon_hash_span([chunk.into(), chunk_edges.into()].span());
        seams.append((chunk, chunk_edges));
    }
    let walked = OutlineTrait::from_edges(seams.span());
    let distance = if exit == 255 {
        255
    } else {
        walked.distance(ENTRY, exit)
    };
    Outcome { revealed, exit, exits, edges, distance }
}

/// The exits laid in a chunk's features.
pub fn exits_in(objects: Span<Object>) -> u8 {
    let mut count: u8 = 0;
    for item in objects {
        if *item.kind == object::EXIT {
            count += 1;
        }
    }
    count
}

/// The changed engine's outcome.
pub fn fixed_outcome(progress: @Progress, out: Span<Revealed>) -> Outcome {
    let mut rows: Array<(u8, u8, u8)> = array![];
    for entry in out {
        rows.append((*entry.chunk, *entry.terrain.edges, exits_in(entry.features.objects.span())));
    }
    outcome(*progress.revealed, rows.span())
}

/// ENG-05's outcome.
pub fn eng05_outcome(progress: @eng05::Progress, out: Span<eng05::Revealed>) -> Outcome {
    let mut rows: Array<(u8, u8, u8)> = array![];
    for entry in out {
        rows.append((*entry.chunk, *entry.terrain.edges, exits_in(entry.features.objects.span())));
    }
    outcome(*progress.revealed, rows.span())
}

/// A permutation of `items` drawn from `seed` (Fisher–Yates), its first item kept first.
pub fn shuffled(items: Span<u8>, seed: felt252) -> Array<u8> {
    let mut dict: Felt252Dict<u8> = Default::default();
    let n = items.len();
    let mut i: u32 = 0;
    while i != n {
        dict.insert(i.into(), *items[i]);
        i += 1;
    }
    let mut k: u32 = n;
    while k > 2 {
        k -= 1;
        // Swap item `k` with an item in `[1, k]`
        let word: u256 = poseidon_hash_span([seed, k.into()].span()).into();
        let bound: u128 = k.into();
        let (_, j) = DivRem::div_rem(word.low, bound.try_into().unwrap());
        let j: felt252 = (j + 1).try_into().unwrap();
        let a = dict.get(k.into());
        let b = dict.get(j);
        dict.insert(k.into(), b);
        dict.insert(j, a);
    }
    let mut out: Array<u8> = array![];
    let mut i: u32 = 0;
    while i != n {
        out.append(dict.get(i.into()));
        i += 1;
    }
    out
}
