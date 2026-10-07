//! The spike's fixtures: a dungeon floor at `create` (its outline, its hosts, its masks), its
//! reveal in a given order on the changed engine, ENG-05's floor for the negative control, and the
//! outcome of a floor once revealed (what the zero-residue test compares).

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::{Features, Object, Terrain, object};
use grimworld_logic::models::location::biome;
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{Quota, QuotaSet, kind as quota};
use grimworld_logic::models::set_piece::{SetPack, SetPiece};
use grimworld_logic::types::reveal::board::{BOARD, INTERIOR};
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
        (
            3,
            Pack {
                castes: [
                    PackCaste { caste: 4, min: 1, max: 2 }, Default::default(), Default::default(),
                    Default::default(), Default::default(),
                ],
                level: 0,
            },
        ),
    ]
        .span()
}

/// The Heart's template: no spawn table names it, so its pack is the Heart.
pub const HEART: u16 = 3;
/// The set piece's id.
pub const PIECE: u16 = 9;

pub fn spawn() -> SpawnTable {
    SpawnTable {
        spawns: [
            Spawn { template: 1, weight: 3 }, Spawn { template: 2, weight: 1 }, Default::default(),
            Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        density: 160,
    }
}

/// A floor's quotas: the exit (quota 0), a vein, the Heart (template `HEART`).
pub fn quotas() -> QuotaSet {
    QuotaSet {
        quotas: [
            Quota { kind: quota::EXIT, param: 5, count: 1 },
            Quota { kind: quota::VEIN, param: 0, count: 1 },
            Quota { kind: quota::HEART, param: HEART, count: 1 }, Default::default(),
            Default::default(), Default::default(),
        ],
    }
}

/// Review t-0088's case: a set piece of 2 packs and 3 objects listed **before** the exit and the
/// Heart (then a vein).
pub fn piece_quotas() -> QuotaSet {
    QuotaSet {
        quotas: [
            Quota { kind: quota::SET_PIECE, param: PIECE, count: 1 },
            Quota { kind: quota::EXIT, param: 5, count: 1 },
            Quota { kind: quota::HEART, param: HEART, count: 1 },
            Quota { kind: quota::VEIN, param: 0, count: 1 }, Default::default(), Default::default(),
        ],
    }
}

/// The set piece: its interior all floor, 2 packs and 3 objects off the spine.
pub fn piece() -> Span<(u16, SetPiece)> {
    let set = SetPiece {
        walls: BOARD - INTERIOR,
        packs: [SetPack { tile: 64, template: 1 }, SetPack { tile: 160, template: 2 }],
        objects: [
            Object { tile: 70, kind: object::CHEST, state: 0, param: 0 },
            Object { tile: 154, kind: object::LEVER, state: 0, param: 0 },
            Object { tile: 94, kind: object::CHEST, state: 0, param: 0 },
        ],
    };
    array![(PIECE, set)].span()
}

/// The changed engine's dungeon floor of `n` chunks with its outline and masks.
pub fn floor_site(n: u8, outline: Outline, masks: Span<(u8, felt252)>) -> Site {
    floor_site_with(n, outline, masks, false)
}

/// The same, with review t-0088's set piece before the exit and the Heart when `with_piece`.
pub fn floor_site_with(
    n: u8, outline: Outline, masks: Span<(u8, felt252)>, with_piece: bool,
) -> Site {
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
        quotas: if with_piece {
            piece_quotas()
        } else {
            quotas()
        },
        tasks: array![].span(),
        spawn: spawn(),
        packs: packs(),
        pieces: if with_piece {
            piece()
        } else {
            array![].span()
        },
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

/// What `create` computes for a floor of `n` chunks from `entropy` (the winding law, D-223): the
/// outline, its farthest chunks, the hosts (the exit and the Heart first, in the farthest layer with
/// room), and every chunk's mask with its hosts.
pub fn create(entropy: felt252, n: u8) -> Floor {
    create_with(entropy, n, false)
}

pub fn create_with(entropy: felt252, n: u8, with_piece: bool) -> Floor {
    let outline = OutlineTrait::draw_winding(
        ENTRY, n, 15, 15, OutlineTrait::seed(entropy, INSTANCE),
    );
    let (far, depth) = outline.far(ENTRY);
    let layers = outline.layers(ENTRY);
    let bare = floor_site_with(n, outline, array![].span(), with_piece);
    let progress = ProgressTrait::new(@bare, entropy);
    let plan = PlacementTrait::plan(@bare, progress.left.span());
    let hosts = PlacementTrait::hosts(
        outline.chunks,
        15,
        15,
        plan,
        bare.pieces,
        EntropyTrait::hosts(entropy, INSTANCE),
        layers.span(),
    )
        .span();
    let mut masks: Array<(u8, felt252)> = array![];
    for chunk in chunks(outline.chunks) {
        masks.append((chunk, PlacementTrait::with_hosts(0, hosts, chunk)));
    }
    Floor {
        site: floor_site_with(n, outline, masks.span(), with_piece), outline, far, depth, hosts,
    }
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
/// revealed, the exit's chunk (255 when none) and how many exits, the Heart's chunk and how many
/// Hearts (packs of `HEART`), the edges of every chunk (a sum of hashes, a set), the exit's distance
/// in chunks from the entry through the revealed edges (255 when not reached).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Outcome {
    pub revealed: felt252,
    pub exit: u8,
    pub exits: u8,
    pub heart: u8,
    pub hearts: u8,
    pub edges: felt252,
    pub distance: u8,
}

/// The outcome of revealed chunks, and the walked distance in tiles from the entry tile to the
/// exit's tile (review t-0088, minor 2; 65535 when there is no exit or no path): not compared, a
/// figure.
pub fn outcome(revealed: felt252, rows: Span<(u8, Terrain, Features)>) -> (Outcome, u32) {
    let mut exit: u8 = 255;
    let mut exit_tile: u8 = 0;
    let mut exits: u8 = 0;
    let mut heart: u8 = 255;
    let mut hearts: u8 = 0;
    let mut edges: felt252 = 0;
    let mut seams: Array<(u8, u8)> = array![];
    let mut walls: Felt252Dict<felt252> = Default::default();
    for entry in rows {
        let (chunk, terrain, features) = *entry;
        for item in features.objects.span() {
            if *item.kind == object::EXIT {
                exit = chunk;
                exit_tile = *item.tile;
                exits += 1;
            }
        }
        for pack in features.packs.span() {
            if *pack.count != 0 && *pack.template == HEART {
                heart = chunk;
                hearts += 1;
            }
        }
        edges += poseidon_hash_span([chunk.into(), terrain.edges.into()].span());
        seams.append((chunk, terrain.edges));
        walls.insert(chunk.into(), terrain.walls);
    }
    let walked = OutlineTrait::from_edges(seams.span());
    let distance = if exit == 255 {
        255
    } else {
        walked.distance(ENTRY, exit)
    };
    let tiles = if exit == 255 {
        65535
    } else {
        walk(ref walls, revealed, 112, 112, exit, exit_tile)
    };
    (Outcome { revealed, exit, exits, heart, hearts, edges, distance }, tiles)
}

/// A chunk's tile `(x, y)`, global: `15 cx + column`, `15 cy + row`.
fn global(chunk: u8, tile: u8) -> (u32, u32) {
    let (cy, cx) = DivRem::div_rem(chunk, 15);
    let (row, column) = DivRem::div_rem(tile, 15);
    (15 * cx.into() + column.into(), 15 * cy.into() + row.into())
}

/// The walked distance in tiles from the entry chunk's tile `from` to `chunk`'s tile `to`, on the
/// revealed floor; 65535 when not reached. A breadth-first walk, bit-parallel: each chunk's layer grows
/// by `BoardTrait::dilate` (the engine's hex neighbours with the chunk's row parity) within its floor,
/// and the layer's ring tiles cross the seams one by one, by their global neighbours (odd-r: an even
/// global row's northern and southern neighbours are `x − 1` and `x`, an odd row's `x` and `x + 1`;
/// a corner is wall, so no step reaches a diagonal chunk).
pub fn walk(
    ref walls: Felt252Dict<felt252>, revealed: felt252, entry: u8, from: u8, chunk: u8, to: u8,
) -> u32 {
    let members = chunks(revealed);
    let mut reached: Felt252Dict<felt252> = Default::default();
    let mut layer: Felt252Dict<felt252> = Default::default();
    reached.insert(entry.into(), BoardTrait::pow(from));
    layer.insert(entry.into(), BoardTrait::pow(from));
    let mut d: u32 = 0;
    let mut found: u32 = 65535;
    let mut moving = true;
    while found == 65535 && moving {
        if BoardTrait::has(reached.get(chunk.into()), to) {
            found = d;
            break;
        }
        let mut next: Felt252Dict<felt252> = Default::default();
        for c in members.span() {
            let c = *c;
            let front = layer.get(c.into());
            if front != 0 {
                let (cy, _) = DivRem::div_rem(c, 15);
                let odd = cy % 2 == 1;
                let floor = BOARD - walls.get(c.into());
                let grown = BoardTrait::and(BoardTrait::dilate(front, odd), floor);
                next.insert(c.into(), BoardTrait::or(next.get(c.into()), grown));
                // [Compute] Across the seams: the layer's ring tiles, one by one
                for tile in chunks(BoardTrait::minus(front, INTERIOR)) {
                    let (x, y) = global(c, tile);
                    let (lo, hi) = if y % 2 == 0 {
                        (x + 255, x + 256)
                    } else {
                        (x + 256, x + 257)
                    };
                    let around: Array<(u32, u32)> = array![
                        (x + 257, y + 1), (x + 255, y + 1), (lo, y + 2), (hi, y + 2), (lo, y),
                        (hi, y),
                    ];
                    for entry in around {
                        let (sx, sy) = entry;
                        if sx >= 256 && sy >= 1 && sx - 256 < 225 && sy - 1 < 225 {
                            let (nx, ny) = (sx - 256, sy - 1);
                            let other: u8 = (15 * (ny / 15) + nx / 15).try_into().unwrap();
                            if other != c && BoardTrait::has(revealed, other) {
                                let t: u8 = (15 * (ny % 15) + nx % 15).try_into().unwrap();
                                if !BoardTrait::has(walls.get(other.into()), t) {
                                    next
                                        .insert(
                                            other.into(),
                                            BoardTrait::or(
                                                next.get(other.into()), BoardTrait::pow(t),
                                            ),
                                        );
                                }
                            }
                        }
                    }
                }
            }
        }
        // [Compute] The new layer: what was not reached yet
        moving = false;
        for c in members.span() {
            let c = *c;
            let fresh = BoardTrait::minus(next.get(c.into()), reached.get(c.into()));
            layer.insert(c.into(), fresh);
            if fresh != 0 {
                moving = true;
                reached.insert(c.into(), BoardTrait::or(reached.get(c.into()), fresh));
            }
        }
        d += 1;
    }
    found
}

/// The changed engine's outcome.
pub fn fixed_outcome(progress: @Progress, out: Span<Revealed>) -> (Outcome, u32) {
    let mut rows: Array<(u8, Terrain, Features)> = array![];
    for entry in out {
        rows.append((*entry.chunk, *entry.terrain, *entry.features));
    }
    outcome(*progress.revealed, rows.span())
}

/// ENG-05's outcome.
pub fn eng05_outcome(progress: @eng05::Progress, out: Span<eng05::Revealed>) -> (Outcome, u32) {
    let mut rows: Array<(u8, Terrain, Features)> = array![];
    for entry in out {
        rows.append((*entry.chunk, *entry.terrain, *entry.features));
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
