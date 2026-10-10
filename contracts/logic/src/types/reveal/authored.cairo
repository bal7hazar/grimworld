//! The reveal of an authored zone (D-214, D-215; ENG-08's format, built by ENG-09). Its terrain is
//! not generated: each chunk's walkable plane is copied from its `ZONE_CHUNK` record into the
//! instance's chunk (D-215 ruling 2), with its authored objects as they are. What stays random,
//! every draw from a domain of its own taken at entry (ADR-0002 rule 2):
//!
//! - **the quotas' hosts** (ruling 3): each quota's `count` chunks among its candidates
//!   (`CANDIDATES`), drawn once at `create` from `EntropyTrait::authored_hosts` (counter 226),
//!   ENG-05's law (draw `t` reads `poseidon(seed, t)`, D-220's complement draw,
//!   `PlacementTrait::subset`); a hosted quota lays its object, or the Heart's pack, on the tile
//!   its candidate names. A snapshot's task quota places nothing in an authored zone (its
//!   landmarks are the author's; D-221).
//! - **each chunk's level, and each spawn point's count** (ruling 4): from
//!   `EntropyTrait::spawns` (counter `256 + chunk`): one level a chunk, uniform in the zone's band,
//!   which every spawn point of the chunk takes, its template's offset added and held in the band;
//!   each point's count in its template's bounds, at least one, its goblins on walkable tiles of
//!   the interior within 2 (`Placement::pack`, ENG-05's). A Heart's pack takes the band's top
//!   (D-208).
//!
//! **Order-free** (D-208): no value read here depends on which chunks were revealed before, or in
//! what order. The entropy is fixed at entry, every chunk's word is keyed by the chunk, the hosts
//! are drawn once and stored, and nothing a reveal returns is read by another reveal.
//!
//! The tiles allowed for the packs are the chunk's floor **within the interior** (rows and
//! columns 1 to 13), so that `Placement::near`'s precondition holds on an authored plane (review
//! t-0101): R-14 keeps every authored placement there.

use core::poseidon::poseidon_hash_span;
use hexx::board::rng::{Rng, RngTrait};
use crate::fate::EntropyTrait;
use crate::models::chunk::{Object, Terrain, object};
use crate::models::quotas::{QuotaSet, kind as quota};
use crate::models::set_piece::{SetPack, SetPiece};
use crate::models::zone_chunk::{QUOTAS, ZoneChunk, ZoneChunkTrait};
use super::board::{BOARD, BoardTrait, INTERIOR};
use super::placement::{Placement, PlacementTrait};
use super::{Progress, RevealTrait, Revealed, Site};

#[generate_trait]
pub impl AuthoredImpl of AuthoredTrait {
    /// Each location quota's hosts among its candidates (`candidates[i]`, a chunk set), one bitmap
    /// a quota in order (6), 0 for a quota with no count: at `create`, once, from `seed`
    /// (`EntropyTrait::authored_hosts`). R-13 keeps each count at most its candidates, R-30 the
    /// draws at most 640 together.
    #[inline(never)]
    fn hosts(quotas: @QuotaSet, candidates: Span<felt252>, seed: felt252) -> Array<felt252> {
        let mut out: Array<felt252> = array![];
        let mut t: felt252 = 0;
        let mut i: u32 = 0;
        for entry in quotas.quotas.span() {
            let count = *entry.count;
            if *entry.kind == 0 || count == 0 {
                out.append(0);
                i += 1;
                continue;
            }
            let allowed = *candidates[i];
            let left = BoardTrait::count(allowed);
            let wide: u16 = count.into() * 2;
            let draws: u8 = if count >= left {
                0
            } else if wide > left.into() {
                left - count
            } else {
                count
            };
            let mut indices: Array<u8> = array![];
            let mut k: u8 = 0;
            while k != draws {
                let word: u256 = poseidon_hash_span([seed, t].span()).into();
                t += 1;
                let bound: u128 = (left - k).into();
                let (_, j) = DivRem::div_rem(word.low, bound.try_into().unwrap());
                indices.append(j.try_into().unwrap());
                k += 1;
            }
            out.append(PlacementTrait::subset(allowed, left, count, indices.span()));
            i += 1;
        }
        out
    }

    /// One authored chunk composed (`HostsLibrary`, where the records are read): as a `SetPiece`,
    /// its plane; its objects, the authored ones then each hosted quota's on its candidate tile
    /// (a quota with something `left` whose host bitmap holds the chunk), each on a walkable tile
    /// of the interior not yet taken (D-140: else not laid, the quota kept owed); its packs to lay,
    /// each hosted Heart then the spawn points, at most 2 (R-15). With `marks`: bits 0–5 the
    /// object quotas laid; bits `16 + 4 j`, pack `j`'s Heart quota plus one (0: a spawn point).
    #[inline(never)]
    fn compose(
        site: @Site, left: Span<u8>, chunk: u8, record: @ZoneChunk, hosts: Span<felt252>,
    ) -> (SetPiece, u32) {
        let walls = *record.walls;
        let mut free = BoardTrait::minus(INTERIOR, walls);
        let mut objects: Array<Object> = array![];
        for item in record.objects.span() {
            if *item.kind != 0 {
                objects.append(*item);
                free = BoardTrait::minus(free, BoardTrait::pow(*item.tile));
            }
        }
        let mut packs: Array<SetPack> = array![];
        let mut marks: u32 = 0;
        let mut i: u8 = 0;
        while i != QUOTAS {
            let index: u32 = i.into();
            if *left[index] != 0 && BoardTrait::has(*hosts[index], chunk) {
                let entry = *site.quotas.quotas.span()[index];
                let tile = record.tile(i);
                if entry.kind == quota::HEART {
                    if packs.len() < 2 {
                        let shift: u32 = if packs.len() == 0 {
                            0x10000
                        } else {
                            0x100000
                        };
                        marks += (index + 1) * shift;
                        packs.append(SetPack { tile, template: entry.param });
                    }
                } else if objects.len() < 3 && tile < 225 && BoardTrait::has(free, tile) {
                    let kind = if entry.kind == quota::VEIN {
                        object::VEIN
                    } else if entry.kind == quota::COLLECTOR {
                        object::COLLECTOR
                    } else {
                        object::LANDMARK
                    };
                    objects.append(Object { tile, kind, state: 0, param: entry.param });
                    free = BoardTrait::minus(free, BoardTrait::pow(tile));
                    marks += PlacementTrait::bit(i).into();
                }
            }
            i += 1;
        }
        for spawn in record.spawns.span() {
            if *spawn.template != 0 && packs.len() < 2 {
                packs.append(*spawn);
            }
        }
        while packs.len() < 2 {
            packs.append(Default::default());
        }
        while objects.len() < 3 {
            objects.append(Default::default());
        }
        let piece = SetPiece {
            walls,
            packs: [*packs[0], *packs[1]],
            objects: [*objects[0], *objects[1], *objects[2]],
        };
        (piece, marks)
    }

    /// Reveals the chunks of `pieces` in order (`(chunk, piece, marks)`, `pieces`), each that is
    /// revealable now (`RevealTrait::revealable`: inside the zone's chunk set, not yet revealed),
    /// and records it in `progress`: the terrain copied (no edge: a zone), the objects as composed,
    /// then the packs, the chunk's level drawn first from its own word, each Heart at the band's
    /// top (D-208), each spawn point at that level (`RevealLibrary`).
    #[inline(never)]
    fn lay(
        site: @Site, ref progress: Progress, instance_id: felt252, pieces: Span<(u8, SetPiece, u32)>,
    ) -> Array<Revealed> {
        let mut out: Array<Revealed> = array![];
        for entry in pieces {
            let (chunk, piece, marks) = *entry;
            if !RevealTrait::revealable(site, @progress, array![].span(), chunk) {
                continue;
            }
            let mut placement = Placement {
                packs: array![],
                objects: array![],
                allowed: BoardTrait::minus(INTERIOR, piece.walls),
                placed: (marks % 0x10000).try_into().unwrap(),
                odd: (chunk / 15) % 2 == 1,
                level: 0,
            };
            for item in piece.objects.span() {
                if *item.kind != 0 {
                    placement.objects.append(*item);
                    placement
                        .allowed = BoardTrait::minus(placement.allowed, BoardTrait::pow(*item.tile));
                }
            }
            let mut rng: Rng = RngTrait::new(
                EntropyTrait::spawns(progress.entropy, instance_id, chunk),
            );
            let low = *site.level_min;
            let high = *site.level_max;
            let level = if high > low {
                low + rng.draw_byte((high - low + 1).try_into().unwrap())
            } else {
                low
            };
            let mut heart = marks / 0x10000;
            for pack in piece.packs.span() {
                let (rest, q) = DivRem::div_rem(heart, 0x10);
                heart = rest;
                if *pack.template != 0 {
                    placement.level = if q != 0 {
                        high
                    } else {
                        level
                    };
                    if placement.pack(ref rng, site, *pack.template, Some(*pack.tile)) && q != 0 {
                        placement.placed += PlacementTrait::bit((q - 1).try_into().unwrap());
                    }
                }
            }
            let features = RevealTrait::features(placement.packs.span(), placement.objects.span());
            progress.left = PlacementTrait::spend(progress.left, placement.placed);
            progress.revealed += BoardTrait::pow(chunk);
            progress.count += 1;
            out.append(Revealed { chunk, terrain: Terrain { walls: piece.walls, edges: 0 }, features });
        }
        out
    }

    /// `compose` then `lay`, in one place (the tests; `HostsLibrary` composes and `RevealLibrary`
    /// lays): `records`, the chunks' `ZONE_CHUNK`s; `hosts`, each quota's host chunks.
    fn reveal(
        site: @Site,
        ref progress: Progress,
        instance_id: felt252,
        records: Span<(u8, ZoneChunk)>,
        hosts: Span<felt252>,
        chunks: Span<u8>,
    ) -> Array<Revealed> {
        let left = progress.left;
        let pieces = Self::pieces(site, left.span(), records, hosts, chunks);
        Self::lay(site, ref progress, instance_id, pieces)
    }

    /// One piece a chunk of `chunks`, in order: its record composed (`compose`), or all wall for a
    /// chunk without one (the content pipeline writes every chunk, ENG-01 §3.5).
    #[inline(never)]
    fn pieces(
        site: @Site,
        left: Span<u8>,
        records: Span<(u8, ZoneChunk)>,
        hosts: Span<felt252>,
        chunks: Span<u8>,
    ) -> Span<(u8, SetPiece, u32)> {
        let mut out: Array<(u8, SetPiece, u32)> = array![];
        for chunk in chunks {
            let mut piece = SetPiece {
                walls: BOARD, packs: [Default::default(); 2], objects: [Default::default(); 3],
            };
            let mut marks: u32 = 0;
            for entry in records {
                let (at, record) = *entry;
                if at == *chunk {
                    let (composed, laid) = Self::compose(site, left, at, @record, hosts);
                    piece = composed;
                    marks = laid;
                }
            }
            out.append((*chunk, piece, marks));
        }
        out.span()
    }
}

#[cfg(test)]
mod tests {
    use crate::fate::EntropyTrait;
    use crate::models::chunk::{Features, Object, object};
    use crate::models::pack::{Pack, PackCaste};
    use crate::models::quotas::{Quota, QuotaSet, kind as quota};
    use crate::models::set_piece::SetPack;
    use crate::models::spawn_table::SpawnTable;
    use crate::models::zone_chunk::ZoneChunk;
    use crate::types::reveal::board::{BOARD, INTERIOR};
    use crate::types::reveal::{Progress, ProgressTrait, Revealed, Site};
    use super::AuthoredTrait;

    const INSTANCE: felt252 = 7;

    /// A 3 × 1 authored zone, its chunk set chunks 0 and 1 (chunk 2 void): a vein among both, a
    /// Heart in chunk 1 only, the band 2 to 6.
    fn site() -> Site {
        Site {
            target: 0,
            biome: 1,
            level_min: 2,
            level_max: 6,
            width: 3,
            height: 1,
            entry_chunk: 0,
            chunk_set: 3,
            west: 0,
            north: 0,
            masks: array![].span(),
            anchors: array![].span(),
            quotas: QuotaSet {
                quotas: [
                    Quota { kind: quota::VEIN, param: 0, count: 1 },
                    Quota { kind: quota::HEART, param: 1, count: 1 }, Default::default(),
                    Default::default(), Default::default(), Default::default(),
                ],
            },
            tasks: array![].span(),
            spawn: SpawnTable { spawns: [Default::default(); 7], density: 0 },
            packs: array![
                (
                    1,
                    Pack {
                        castes: [
                            PackCaste { caste: 1, min: 1, max: 2 },
                            PackCaste { caste: 2, min: 1, max: 3 }, Default::default(),
                            Default::default(), Default::default(),
                        ],
                        level: 0,
                    },
                ),
            ]
                .span(),
            pieces: array![].span(),
        }
    }

    fn candidates() -> Span<felt252> {
        array![3, 2, 0, 0, 0, 0].span()
    }

    /// Chunk 0: a spawn point and a chest; chunk 1: none; both their interior floor. Candidate
    /// tiles: the vein's at 100 in both, the Heart's at 112 in chunk 1.
    fn records() -> Span<(u8, ZoneChunk)> {
        let walls = BOARD - INTERIOR;
        array![
            (
                0,
                ZoneChunk {
                    walls,
                    spawns: [SetPack { tile: 32, template: 1 }, Default::default()],
                    objects: [
                        Object { tile: 40, kind: object::CHEST, state: 0, param: 0 },
                        Default::default(), Default::default(),
                    ],
                    tiles: [100, 0, 0, 0, 0, 0],
                    bridges: 0,
                    gates: [0, 0],
                },
            ),
            (
                1,
                ZoneChunk {
                    walls,
                    spawns: [Default::default(), Default::default()],
                    objects: [Default::default(), Default::default(), Default::default()],
                    tiles: [100, 112, 0, 0, 0, 0],
                    bridges: 0,
                    gates: [0, 0],
                },
            ),
        ]
            .span()
    }

    fn reveal(entropy: felt252, chunks: Span<u8>) -> (Progress, Array<Revealed>) {
        let site = site();
        let mut progress = ProgressTrait::new(@site, entropy);
        let hosts = AuthoredTrait::hosts(
            @site.quotas, candidates(), EntropyTrait::authored_hosts(entropy, INSTANCE),
        );
        let out = AuthoredTrait::reveal(
            @site, ref progress, INSTANCE, records(), hosts.span(), chunks,
        );
        (progress, out)
    }

    fn chunk_of(out: @Array<Revealed>, chunk: u8) -> Revealed {
        let mut found: Option<Revealed> = None;
        for entry in out.span() {
            if *entry.chunk == chunk {
                found = Some(*entry);
            }
        }
        found.unwrap()
    }

    // D-208: the chunks revealed in either order, or one by one, give the same words and the same
    // progress, over 8 entropies.
    #[test]
    fn test_authored_reveal_order_free() {
        let mut entropy: felt252 = 0x1234;
        for _ in 0..8_u8 {
            let (first, a) = reveal(entropy, array![0, 1].span());
            let (second, b) = reveal(entropy, array![1, 0].span());
            assert(first == second, 'progress');
            assert(chunk_of(@a, 0) == chunk_of(@b, 0) && chunk_of(@a, 1) == chunk_of(@b, 1), 'words');
            entropy = entropy * 31 + 17;
        }
    }

    // Each quota placed exactly its count, on its candidate tile; the Heart at the band's top
    // (D-208); the spawn point at a level in the band; chunk 2 (void) not revealed.
    #[test]
    fn test_authored_reveal_places_as_drawn() {
        let mut entropy: felt252 = 0x77;
        for _ in 0..8_u8 {
            let (progress, out) = reveal(entropy, array![0, 1, 2].span());
            assert(out.len() == 2 && progress.count == 2 && progress.revealed == 3, 'revealed');
            assert(*progress.left.span()[0] == 0 && *progress.left.span()[1] == 0, 'spent');
            let mut veins: u8 = 0;
            for chunk in out.span() {
                let features: Features = *chunk.features;
                assert(*chunk.terrain.walls == BOARD - INTERIOR, 'plane copied');
                for item in features.objects.span() {
                    if *item.kind == object::VEIN {
                        assert(*item.tile == 100, 'vein on its tile');
                        veins += 1;
                    }
                }
            }
            assert(veins == 1, 'one vein');
            let [heart, _] = chunk_of(@out, 1).features.packs;
            assert(heart.tile == 112 && heart.level == 6 && heart.count >= 2, 'heart');
            let [spawn, _] = chunk_of(@out, 0).features.packs;
            assert(spawn.tile == 32 && spawn.level >= 2 && spawn.level <= 6, 'spawn');
            let [chest, _, _] = chunk_of(@out, 0).features.objects;
            assert(chest.kind == object::CHEST && chest.tile == 40, 'chest kept');
            entropy = entropy * 31 + 17;
        }
    }

    // A chunk of the set without its record (the content pipeline writes every chunk) is all wall.
    #[test]
    fn test_authored_reveal_missing_record() {
        let site = site();
        let mut progress = ProgressTrait::new(@site, 5);
        let out = AuthoredTrait::reveal(
            @site, ref progress, INSTANCE, array![].span(), array![0, 0].span(), array![1].span(),
        );
        assert(out.len() == 1 && *out[0].terrain.walls == BOARD, 'wall');
        assert(progress.revealed == 2, 'revealed');
    }

    // The draws' domains (ENG-08's Q6): the hosts at counter 226, a chunk's spawn points at 256 +
    // chunk: none is a chunk's word (0–224), the generated hosts' (225) nor the outline's (227).
    #[test]
    fn test_authored_domains_apart() {
        let e = 0xabc;
        let hosts = EntropyTrait::authored_hosts(e, INSTANCE);
        assert(hosts != EntropyTrait::hosts(e, INSTANCE), 'hosts');
        assert(hosts != EntropyTrait::outline(e, INSTANCE), 'outline');
        assert(hosts == EntropyTrait::word(e, INSTANCE, 226), 'counter 226');
        for chunk in 0..225_u8 {
            let word = EntropyTrait::spawns(e, INSTANCE, chunk);
            assert(word != EntropyTrait::word(e, INSTANCE, chunk), 'a chunk word');
            assert(word != hosts, 'the hosts');
        }
    }
}
