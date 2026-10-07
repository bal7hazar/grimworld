//! The reveal of an authored chunk (ENG-08 deliverables 3 and 4; built by ENG-09): its walkable
//! plane copied into the instance's chunk (ruling 2), its authored objects as they are, and what
//! stays random, every draw taken at entry from a domain of its own (ADR-0002 rule 2):
//!
//! - **the quotas' hosts** (ruling 3): each quota's `count` chunks among its candidates
//!   (`CANDIDATES`), drawn once at `create` from `derive(entropy, domain(instance, 226, REVEAL),
//!   0)`, ENG-05's law (`PlacementTrait::subset`, D-220's complement draw; draw `t` reads
//!   `poseidon(seed, t)`); the hosted quota lays its object, or the Heart's pack, on the tile its
//!   candidate names. ENG-05's generated hosts use counter 225, the chunks' words 0–224.
//! - **each spawn point's level and count** (ruling 4): from `derive(entropy, domain(instance,
//!   256 + chunk, REVEAL), 0)`: the level uniform in the zone's band, the template's offset added
//!   and held in it; the count in the template's bounds, at least one, the goblins on walkable
//!   tiles within 2 (`Placement::pack`, ENG-05's). A Heart's pack takes the band's top (D-208).
//!
//! No value read here depends on which chunks were revealed before, or in what order: the entropy
//! is fixed at entry, every word is keyed by the chunk, and the hosts are drawn once (D-208).

use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::{REVEAL, derive, domain};
use grimworld_logic::models::chunk::{Features, Object, PackPlacement, Terrain, object};
use grimworld_logic::models::quotas::{QuotaSet, kind as quota};
use grimworld_logic::types::reveal::Site;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use grimworld_logic::types::reveal::placement::{Placement, PlacementTrait};
use hexx::board::rng::{Rng, RngTrait};
use crate::checks::odd;
use crate::zone_chunk::{QUOTAS, ZoneChunk, ZoneChunkTrait};

/// The counters of the authored draws in `domain(instance, counter, REVEAL)`: the chunks' words
/// take 0–224 and ENG-05's hosts 225.
pub const HOSTS_COUNTER: felt252 = 226;
pub const SPAWN_BASE: felt252 = 256;

#[generate_trait]
pub impl AuthoredImpl of AuthoredTrait {
    /// The seed of the hosts' draw.
    fn hosts_seed(entropy: felt252, instance: felt252) -> felt252 {
        derive(entropy, domain(instance, HOSTS_COUNTER, REVEAL), 0)
    }

    /// The word of a chunk's spawn points.
    fn spawn_word(entropy: felt252, instance: felt252, chunk: u8) -> felt252 {
        derive(entropy, domain(instance, SPAWN_BASE + chunk.into(), REVEAL), 0)
    }

    /// Each quota's hosts among its candidates (`candidates[i]`, a chunk set), one bitmap a quota
    /// in order, 0 for a quota with no count: at `create`, once.
    fn hosts(quotas: @QuotaSet, candidates: Span<felt252>, seed: felt252) -> Array<felt252> {
        let mut out: Array<felt252> = array![];
        let mut t: felt252 = 0;
        let mut i: u32 = 0;
        for entry in quotas.quotas.span() {
            if *entry.kind == 0 || *entry.count == 0 || i >= candidates.len() {
                out.append(0);
                i += 1;
                continue;
            }
            let allowed = *candidates[i];
            let left = BoardTrait::count(allowed);
            let count = *entry.count;
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

    /// The chunk's two words, as `Instances` stores them (ENG-01 §3.2): the terrain copied from
    /// the record (no edge: a zone), then the objects (authored first, then the hosted quotas'),
    /// then the packs (the Hearts', then the spawn points').
    fn reveal(
        site: @Site,
        chunk: u8,
        record: @ZoneChunk,
        hosts: Span<felt252>,
        entropy: felt252,
        instance: felt252,
    ) -> (Terrain, Features) {
        let walls = *record.walls;
        let mut placement = Placement {
            packs: array![],
            objects: array![],
            allowed: BoardTrait::minus(BOARD, walls),
            placed: 0,
            odd: odd(chunk),
            level: 0,
        };
        // [Compute] The objects: the authored ones, then each hosted quota's on its candidate tile
        for item in record.objects.span() {
            if *item.kind != 0 {
                placement.objects.append(*item);
                placement.allowed -= BoardTrait::pow(*item.tile);
            }
        }
        let mut hearts: Array<(u16, u8)> = array![];
        let mut i: u8 = 0;
        while i != QUOTAS {
            if i.into() < hosts.len() && BoardTrait::has(*hosts[i.into()], chunk) {
                let entry = *site.quotas.quotas.span()[i.into()];
                let tile = record.tile(i);
                if entry.kind == quota::HEART {
                    hearts.append((entry.param, tile));
                } else {
                    let kind = if entry.kind == quota::VEIN {
                        object::VEIN
                    } else if entry.kind == quota::COLLECTOR {
                        object::COLLECTOR
                    } else {
                        object::LANDMARK
                    };
                    placement.objects.append(Object { tile, kind, state: 0, param: entry.param });
                    placement.allowed -= BoardTrait::pow(tile);
                }
                placement.placed += BoardTrait::pow(i).try_into().unwrap();
            }
            i += 1;
        }
        // [Compute] The packs: each Heart at the band's top (D-208), then the spawn points at the
        // level drawn for the chunk
        let mut rng: Rng = RngTrait::new(Self::spawn_word(entropy, instance, chunk));
        let span: u8 = *site.level_max - *site.level_min + 1;
        let level = *site.level_min + rng.draw_byte(span.try_into().unwrap());
        placement.level = *site.level_max;
        for heart in hearts.span() {
            let (template, tile) = *heart;
            placement.pack(ref rng, site, template, Option::Some(tile));
        }
        placement.level = level;
        for spawn in record.spawns.span() {
            if *spawn.template != 0 {
                placement.pack(ref rng, site, *spawn.template, Option::Some(*spawn.tile));
            }
        }
        let terrain = Terrain { walls, edges: 0 };
        let mut packs = placement.packs.span();
        let p0 = match packs.pop_front() {
            Option::Some(pack) => *pack,
            Option::None => Default::default(),
        };
        let p1: PackPlacement = match packs.pop_front() {
            Option::Some(pack) => *pack,
            Option::None => Default::default(),
        };
        let mut objects = placement.objects.span();
        let mut out: Array<Object> = array![];
        for _ in 0..3_u8 {
            match objects.pop_front() {
                Option::Some(item) => out.append(*item),
                Option::None => out.append(Default::default()),
            }
        }
        let features = Features {
            packs: [p0, p1], objects: [*out[0], *out[1], *out[2]], touched: 0,
        };
        (terrain, features)
    }
}
