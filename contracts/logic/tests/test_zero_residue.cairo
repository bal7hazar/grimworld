// ENG-10b, **the zero-residue test** (acceptance A1 and A4; the merge gate's first part, the
// Overseer, 2026-10-07): a dungeon floor is created as `Instances::begin` creates it (the `Site` of
// the location, its outline, hosts and masks from `HostsLibrary::floor` called by `library_call`,
// the instance's entropy and id), then revealed through `RevealTrait::reveal` in seven orders, the
// entry first: by index, backward, nearest first, farthest first, two drawn, and **t-0077's
// forcing order** (the entry's first neighbour kept for the last reveal; review t-0088, minor 3).
// Every order must give the same chunk set (the outline), one exit and one Heart on the same chunks
// (in the farthest layer), the same exit-to-entry distance in chunks read back from the revealed
// edges (the farthest distance), the same edges in every chunk, **the same opening tiles on both
// sides of every seam** (review t-0090), and **the same walked distance in tiles from the entry
// tile to the exit's tile** (D-224; a bit-parallel walk, `walk`). Split by `N` and by entropies so
// that each test stays small (FND-23): 8 entropies at `N` = 6, 8 at `N` = 12, and review t-0088's
// major 1 as a fixture of its own (`test_zero_residue_piece_*`): floors whose farthest layer is one
// chunk, with a set piece of 2 packs and 3 objects listed before the exit and the Heart, both
// placed in every order. ENG-05's merged engine failed the same comparison (SPK-17,
// `test_zero_residue_on_eng05_*`: 5, 5, 5 and 6 of the six other orders differed on four floors of
// 12).
use core::dict::{Felt252Dict, Felt252DictTrait};
use core::poseidon::poseidon_hash_span;
use grimworld_logic::interface::{IHostsLibraryDispatcherTrait, IHostsLibraryLibraryDispatcher};
use grimworld_logic::models::chunk::{Features, Object, Terrain, object};
use grimworld_logic::models::location::biome;
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{Quota, QuotaSet, kind as quota};
use grimworld_logic::models::set_piece::{SetPack, SetPiece};
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable};
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait, INTERIOR};
use grimworld_logic::types::reveal::outline::{Outline, OutlineTrait};
use grimworld_logic::types::reveal::placement::{CORE, PlacementTrait};
use grimworld_logic::types::reveal::{Progress, ProgressTrait, RevealTrait, Revealed, Site};
use snforge_std::{DeclareResultTrait, declare};
use starknet::ClassHash;

const INSTANCE: felt252 = 0x100000001;
/// A dungeon's entry chunk, (7, 7) of its 15 × 15 rectangle, and its entry tile.
const ENTRY: u8 = 112;
/// The Heart's template: no spawn table names it, so its pack is the Heart.
const HEART: u16 = 3;
/// The set piece's id.
const PIECE: u16 = 9;

fn packs() -> Span<(u16, Pack)> {
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
            HEART,
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

/// A floor's quotas: the exit (quota 0), a vein, the Heart (template `HEART`); with review t-0088's
/// set piece of 2 packs and 3 objects listed **before** the exit and the Heart when `piece`.
fn quotas(piece: bool) -> QuotaSet {
    if piece {
        QuotaSet {
            quotas: [
                Quota { kind: quota::SET_PIECE, param: PIECE, count: 1 },
                Quota { kind: quota::EXIT, param: 5, count: 1 },
                Quota { kind: quota::HEART, param: HEART, count: 1 },
                Quota { kind: quota::VEIN, param: 0, count: 1 }, Default::default(),
                Default::default(),
            ],
        }
    } else {
        QuotaSet {
            quotas: [
                Quota { kind: quota::EXIT, param: 5, count: 1 },
                Quota { kind: quota::VEIN, param: 0, count: 1 },
                Quota { kind: quota::HEART, param: HEART, count: 1 }, Default::default(),
                Default::default(), Default::default(),
            ],
        }
    }
}

/// The set piece: its interior all floor, 2 packs and 3 objects off the spine.
fn pieces(piece: bool) -> Span<(u16, SetPiece)> {
    if !piece {
        return array![].span();
    }
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

/// The location's `Site` as `Instances::site` reads it for a dungeon floor of `n` chunks: no
/// outline yet, no mask (a dungeon has none, ENG-10b's brief, ruling 11).
fn location(n: u8, piece: bool) -> Site {
    Site {
        target: n,
        biome: biome::CAVE,
        level_min: 3,
        level_max: 5,
        width: 15,
        height: 15,
        entry_chunk: ENTRY,
        chunk_set: 0,
        west: 0,
        north: 0,
        masks: array![].span(),
        anchors: array![(ENTRY, 112)].span(),
        quotas: quotas(piece),
        tasks: array![].span(),
        spawn: SpawnTable {
            spawns: [
                Spawn { template: 1, weight: 3 }, Spawn { template: 2, weight: 1 },
                Default::default(), Default::default(), Default::default(), Default::default(),
                Default::default(),
            ],
            density: 160,
        },
        packs: packs(),
        pieces: pieces(piece),
    }
}

#[derive(Drop)]
struct Floor {
    site: Site,
    outline: Outline,
    far: felt252,
    depth: u8,
    hosts: Span<felt252>,
}

/// A floor as `Instances::begin` creates it from `entropy`: `HostsLibrary::floor` (the class
/// `hosts`) gives the outline, the hosts and the mask of the entry chunk (the chunk sight touches
/// from the entry tile), and the `Site` takes them as `begin` does; every other chunk of the
/// outline gets its hosts above its mask from the same hosts (`with_hosts`), as an invocation that
/// reveals in a dungeon sets them.
fn create(hosts: ClassHash, entropy: felt252, n: u8, piece: bool) -> Floor {
    let mut site = location(n, piece);
    let progress = ProgressTrait::new(@site, entropy);
    let plan = PlacementTrait::plan(@site, progress.left.span());
    let (outline, drawn, entry) = IHostsLibraryLibraryDispatcher { class_hash: hosts }
        .floor(ENTRY, n, 15, 15, plan, site.pieces, array![ENTRY].span(), entropy, INSTANCE);
    let mut masks: Array<(u8, felt252)> = array![];
    for chunk in chunks(outline.chunks) {
        masks.append((chunk, PlacementTrait::with_hosts(0, drawn, chunk)));
    }
    assert(entry == array![(ENTRY, PlacementTrait::with_hosts(0, drawn, ENTRY))].span(), 'mask');
    site.chunk_set = outline.chunks;
    site.west = outline.west;
    site.north = outline.north;
    site.masks = masks.span();
    let (far, depth) = outline.far(ENTRY);
    Floor { site, outline, far, depth, hosts: drawn }
}

/// The chunks of `set`, by index.
fn chunks(set: felt252) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let count = BoardTrait::count(set);
    let mut i: u8 = 0;
    while i != count {
        out.append(BoardTrait::nth(set, i));
        i += 1;
    }
    out
}

/// Reveals `order` one chunk a call, every revealed chunk known.
fn reveal_in_order(site: @Site, entropy: felt252, order: Span<u8>) -> (Progress, Array<Revealed>) {
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

/// What a revealed floor shows, whatever the order: the chunks revealed, the exit's chunk and
/// tile (255 when none) and how many exits, the Heart's chunk and how many Hearts (packs of
/// `HEART`), the edges and the ring's floor (its opening tiles) of every chunk (sums of hashes,
/// sets), the exit's distance in chunks from the entry through the revealed edges (255 when not
/// reached), the walked distance in tiles from the entry tile to the exit's (65535 when none).
#[derive(Copy, Drop, Debug, PartialEq)]
struct Outcome {
    revealed: felt252,
    exit: u8,
    exit_tile: u8,
    exits: u8,
    heart: u8,
    hearts: u8,
    edges: felt252,
    rings: felt252,
    distance: u8,
    tiles: u32,
}

fn outcome(progress: @Progress, out: Span<Revealed>) -> Outcome {
    let mut exit: u8 = 255;
    let mut exit_tile: u8 = 255;
    let mut exits: u8 = 0;
    let mut heart: u8 = 255;
    let mut hearts: u8 = 0;
    let mut edges: felt252 = 0;
    let mut rings: felt252 = 0;
    let mut set: felt252 = 0;
    let mut west: felt252 = 0;
    let mut north: felt252 = 0;
    let mut walls: Felt252Dict<felt252> = Default::default();
    for entry in out {
        let chunk = *entry.chunk;
        let terrain = *entry.terrain;
        let features: Features = *entry.features;
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
        let ring = BoardTrait::minus(BOARD - terrain.walls, INTERIOR);
        rings += poseidon_hash_span([chunk.into(), ring].span());
        walls.insert(chunk.into(), terrain.walls);
        // The outline read back from the edges (West, East, South, North)
        set = BoardTrait::or(set, BoardTrait::pow(chunk));
        let e = terrain.edges;
        if e % 2 == 1 {
            west = BoardTrait::or(west, BoardTrait::pow(chunk));
        }
        if (e / 2) % 2 == 1 {
            west = BoardTrait::or(west, BoardTrait::pow(chunk - 1));
        }
        if (e / 4) % 2 == 1 {
            north = BoardTrait::or(north, BoardTrait::pow(chunk - 15));
        }
        if (e / 8) % 2 == 1 {
            north = BoardTrait::or(north, BoardTrait::pow(chunk));
        }
    }
    let walked = Outline { chunks: set, west, north };
    let (distance, tiles) = if exit == 255 {
        (255, 65535)
    } else {
        (
            walked.distance(ENTRY, exit),
            walk(ref walls, *progress.revealed, ENTRY, 112, exit, exit_tile),
        )
    };
    Outcome {
        revealed: *progress.revealed,
        exit,
        exit_tile,
        exits,
        heart,
        hearts,
        edges,
        rings,
        distance,
        tiles,
    }
}

/// A chunk's tile `(x, y)`, global: `15 cx + column`, `15 cy + row`.
fn global(chunk: u8, tile: u8) -> (u32, u32) {
    let (cy, cx) = DivRem::div_rem(chunk, 15);
    let (row, column) = DivRem::div_rem(tile, 15);
    (15 * cx.into() + column.into(), 15 * cy.into() + row.into())
}

/// The walked distance in tiles from the entry chunk's tile `from` to `chunk`'s tile `to`, on the
/// revealed floor; 65535 when not reached (SPK-17's `fixtures::walk`). A breadth-first walk,
/// bit-parallel: each chunk's layer grows by `BoardTrait::dilate` (the engine's hex neighbours with
/// the chunk's row parity) within its floor, and the layer's ring tiles cross the seams one by one,
/// by their global neighbours (odd-r: an even global row's northern and southern neighbours are
/// `x − 1` and `x`, an odd row's `x` and `x + 1`; a corner is wall, so no step reaches a diagonal
/// chunk).
fn walk(
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

/// A permutation of `items` drawn from `seed` (Fisher–Yates), its first item kept first.
fn shuffled(items: Span<u8>, seed: felt252) -> Array<u8> {
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

/// The seven required orders of one floor, the entry first in each, as `create` reveals it: by
/// index, backward, nearest first, farthest first, two drawn, t-0077's forcing order.
fn orders(outline: @Outline, entropy: felt252) -> Array<Array<u8>> {
    let mut rest: Array<u8> = array![];
    for c in chunks(*outline.chunks) {
        if c != ENTRY {
            rest.append(c);
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
    // By distance through the open seams (`layers`: the farthest first, the entry's left out)
    let layers = outline.layers(ENTRY);
    let mut nearest = array![ENTRY];
    let mut d = layers.len();
    while d != 0 {
        d -= 1;
        for c in chunks(*layers[d]) {
            nearest.append(c);
        }
    }
    let mut farthest = array![ENTRY];
    for layer in layers.span() {
        for c in chunks(*layer) {
            farthest.append(c);
        }
    }
    // t-0077's forcing order: `X`, the entry's first neighbour, revealed last
    let x = *chunks(*layers[layers.len() - 1])[0];
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

/// The gate over `floors` floors of `n` chunks from the entropies counted from `first`; with
/// review t-0088's set piece when `piece`, keeping only the floors whose farthest layer is one
/// chunk. Prints each floor's walk in tiles.
fn zero_residue(n: u8, first: u32, floors: u32, piece: bool) {
    let hosts = *declare("HostsLibrary").unwrap().contract_class().class_hash;
    let mut done: u32 = 0;
    let mut i: u32 = first;
    while done != floors {
        let entropy = poseidon_hash_span(['eng10b residue', i.into()].span());
        i += 1;
        let floor = create(hosts, entropy, n, piece);
        if piece && BoardTrait::count(floor.far) != 1 {
            continue;
        }
        done += 1;
        if piece {
            // Review t-0089, note 2: the set piece (quota 0) hosted, never on the farthest chunk,
            // which the exit and the Heart took first
            let at = *floor.hosts[0];
            assert(at != 0, 'the set piece hosted');
            assert(BoardTrait::and(at, floor.far) == 0, 'the set piece off the far chunk');
        }
        let mut reference: Option<Outcome> = Option::None;
        for order in orders(@floor.outline, entropy) {
            let (progress, out) = reveal_in_order(@floor.site, entropy, order.span());
            let got = outcome(@progress, out.span());
            assert(progress.count == n, 'every chunk revealed');
            assert(got.revealed == floor.outline.chunks, 'the outline revealed');
            assert(got.exits == 1, 'one exit');
            assert(got.hearts == 1, 'one Heart');
            assert(BoardTrait::has(floor.far, got.exit), 'the exit at the farthest');
            assert(BoardTrait::has(floor.far, got.heart), 'the Heart at the farthest');
            assert(BoardTrait::has(CORE, got.exit_tile), 'the exit on the core');
            assert(got.distance == floor.depth, 'its distance the depth');
            assert(got.tiles != 65535, 'the exit reached');
            match reference {
                Option::None => { reference = Option::Some(got); },
                Option::Some(first) => { assert(got == first, 'the same in every order'); },
            }
        }
        let got = reference.unwrap();
        println!(
            "floor {} (N = {}): exit chunk {} at {} chunks, {} tiles; Heart chunk {}",
            i - 1,
            n,
            got.exit,
            got.distance,
            got.tiles,
            got.heart,
        );
    }
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n6_0() {
    zero_residue(6, 0, 4, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n6_1() {
    zero_residue(6, 4, 4, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n12_0() {
    zero_residue(12, 0, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n12_1() {
    zero_residue(12, 2, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n12_2() {
    zero_residue(12, 4, 2, false);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_n12_3() {
    zero_residue(12, 6, 2, false);
}

// Review t-0088's major 1 (A4): a farthest layer of one chunk, a set piece (2 packs, 3 objects)
// listed before the exit and the Heart; both placed, in every order.
#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_piece_n6() {
    zero_residue(6, 100, 4, true);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn test_zero_residue_piece_n12() {
    zero_residue(12, 100, 2, true);
}
