//! The Registry's content checks of an authored zone's records (ENG-08 deliverable 2), as the
//! `...Assert` rules ENG-09 adds to `RegistryAssert::assert_content`. Each takes what its record's
//! write reads; the ids are CLI-09 §5's (R-1 … R-20) and ENG-08's (R-21 …), one table with the
//! converter's refusals (`map-format/checks.json`). A rule between two records is checked at the
//! write of either, against the other when it exists, so the order of the writes never lets one
//! through (CBT-02c's precedent); ENG-08's README gives the order the converter writes in.

use grimworld_logic::models::gate::Gate;
use grimworld_logic::models::location::{Location, kind as location_kind};
use grimworld_logic::models::pack::{Pack, PackTrait};
use grimworld_logic::models::quotas::{QuotaSet, kind as quota};
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use crate::records::Bridge;
use crate::zone_chunk::{QUOTAS, ZoneChunk, ZoneChunkTrait, authored_object};

/// The most draws a zone's location quotas ask together at entry (D-220), each pass drawing
/// `min(count, members − count)`: 640, so that with the snapshot's eight task quotas the worst
/// plan measures 95,799,175 L2 gas (`test_pair_plan_bound_hosts`), against 99,673,404 at ENG-05's
/// six passes of 112 (672 draws) with the tasks, 0.33 % under D-220's 100,000,000.
pub const MAX_DRAWS: u16 = 640;
/// A chunk's caps (E-3): objects and packs.
pub const MAX_OBJECTS: u8 = 3;
pub const MAX_PACKS: u8 = 2;

pub mod errors {
    pub const SET_OUTSIDE: felt252 = 'zone: set outside rectangle'; // R-11
    pub const ABOVE_MEMBERS: felt252 = 'zone: count above members'; // R-12
    pub const ABOVE_CANDIDATES: felt252 = 'zone: count above candidates'; // R-13
    pub const NOT_FLOOR: felt252 = 'zone chunk: tile not floor'; // R-14
    pub const OBJECT: felt252 = 'zone chunk: object'; // R-14
    pub const EMPTY: felt252 = 'zone chunk: empty with a value'; // R-14
    pub const TAKEN: felt252 = 'zone chunk: tile taken'; // R-14
    pub const CAPS: felt252 = 'zone chunk: over its caps'; // R-15
    pub const GATE_ANCHOR: felt252 = 'zone: gate anchor not floor'; // R-18
    pub const MASK: felt252 = 'zone: mask disagrees'; // R-20
    pub const NOT_IN_SET: felt252 = 'zone: chunk not in the set'; // R-24
    pub const GATE_INDEX: felt252 = 'zone: gate not indexed'; // R-25
    pub const ENTRY: felt252 = 'zone: entry not floor'; // R-26
    pub const HEART: felt252 = 'zone: heart template'; // R-27
    pub const FLOOR_RECTANGLE: felt252 = 'location: floor rectangle'; // R-28
    pub const QUOTA_KIND: felt252 = 'zone: quota kind'; // R-29
    pub const DRAWS: felt252 = 'zone: quota draws'; // R-30
    pub const CANDIDATES_OUTSIDE: felt252 = 'candidates: outside the set'; // R-31
    pub const BRIDGE_DECK: felt252 = 'bridge: deck empty'; // R-33
    pub const BRIDGE_END: felt252 = 'bridge: end'; // R-33
    pub const BRIDGE_FLOOR: felt252 = 'bridge: end not floor'; // R-34
    pub const BRIDGE_APART: felt252 = 'bridge: end not by the deck'; // R-34
    pub const BRIDGE_INDEX: felt252 = 'bridge: index'; // R-35
}

/// The chunks of a `width × height` rectangle, bit `15 cy + cx`.
pub fn rectangle(width: u8, height: u8) -> felt252 {
    let row = BoardTrait::pow(width) - 1;
    let mut out: felt252 = 0;
    let mut cy: u8 = 0;
    while cy != height {
        out += row * BoardTrait::pow(15 * cy);
        cy += 1;
    }
    out
}

/// A tile of the chunk that is walkable: below 225 and not a wall.
#[inline(always)]
fn floor(walls: felt252, tile: u8) -> bool {
    tile < 225 && !BoardTrait::has(walls, tile)
}

/// Whether a chunk's row 0 is a globally odd row (ADR-0006 §4: `15 cy` is odd for an odd `cy`).
#[inline(always)]
pub fn odd(chunk: u8) -> bool {
    (chunk / 15) % 2 == 1
}

#[generate_trait]
pub impl ZoneAssert of ZoneAssertTrait {
    /// R-11, at the chunk set's `OUTLINE` write (it reads `LOCATION`): the chunk set lies within
    /// the `width × height` rectangle (ENG-R1c's bound, reused).
    fn assert_set(chunk_set: felt252, width: u8, height: u8) {
        let inside = rectangle(width, height);
        assert(BoardTrait::minus(chunk_set, inside) == 0, errors::SET_OUTSIDE);
    }

    /// R-24 and R-20, at a `ZONE_CHUNK` write (it reads the chunk set and its tile mask; the mask's
    /// `OUTLINE` write reads the `ZONE_CHUNK` the other way): the chunk is in the set, and every
    /// tile outside its mask is a wall (`mask` 0: a whole chunk).
    fn assert_outline(chunk: u8, walls: felt252, chunk_set: felt252, mask: felt252) {
        assert(BoardTrait::has(chunk_set, chunk), errors::NOT_IN_SET);
        if mask != 0 {
            let outside = BoardTrait::minus(BOARD, mask);
            assert(BoardTrait::minus(outside, walls) == 0, errors::MASK);
        }
    }

    /// R-14 and R-15, at a `ZONE_CHUNK` write (it reads `CANDIDATES` and `QUOTAS`): its spawn
    /// points, objects and candidate tiles on walkable tiles, none two on one tile; an object of a
    /// kind an authored chunk holds, untouched; an empty entry all zeros, and a candidate tile 0
    /// where `CANDIDATES` does not name the chunk; within E-3 with every candidate counted (an
    /// object quota's against 3 objects, a Heart's against 2 packs), so that any draw at entry
    /// fits. D-134's corners are not read (ruling 5: lifted for authored chunks).
    fn assert_chunk(record: @ZoneChunk, chunk: u8, candidates: Span<felt252>, quotas: @QuotaSet) {
        let walls = *record.walls;
        let mut taken: felt252 = 0;
        let mut packs: u8 = 0;
        let mut objects: u8 = 0;
        for spawn in record.spawns.span() {
            if *spawn.template == 0 {
                assert(*spawn.tile == 0, errors::EMPTY);
            } else {
                Self::take(walls, ref taken, *spawn.tile);
                packs += 1;
            }
        }
        for item in record.objects.span() {
            if *item.kind == 0 {
                assert(*item.tile == 0 && *item.state == 0 && *item.param == 0, errors::EMPTY);
            } else {
                assert(authored_object(*item.kind) && *item.state == 0, errors::OBJECT);
                Self::take(walls, ref taken, *item.tile);
                objects += 1;
            }
        }
        let mut i: u8 = 0;
        while i != QUOTAS {
            let tile = record.tile(i);
            let named = i.into() < candidates.len()
                && BoardTrait::has(*candidates[i.into()], chunk);
            if named {
                Self::take(walls, ref taken, tile);
                let kind = *quotas.quotas.span()[i.into()].kind;
                if kind == quota::HEART {
                    packs += 1;
                } else {
                    objects += 1;
                }
            } else {
                assert(tile == 0, errors::EMPTY);
            }
            i += 1;
        }
        assert(packs <= MAX_PACKS && objects <= MAX_OBJECTS, errors::CAPS);
    }

    #[inline(always)]
    fn take(walls: felt252, ref taken: felt252, tile: u8) {
        assert(floor(walls, tile), errors::NOT_FLOOR);
        assert(!BoardTrait::has(taken, tile), errors::TAKEN);
        taken += BoardTrait::pow(tile);
    }

    /// R-26, at `LOCATION`'s write with the marker (it reads the entry chunk's `ZONE_CHUNK`; that
    /// write reads `LOCATION` the other way): the entry tile walkable.
    fn assert_entry(location: @Location, entry: @ZoneChunk) {
        assert(floor(*entry.walls, *location.entry_tile), errors::ENTRY);
    }

    /// R-18 and R-25, at a `GATE` write whose source is an authored zone (it reads the anchor
    /// chunk's `ZONE_CHUNK`): the anchor walkable, and the chunk names the gate among the two it
    /// anchors, which is the registry's index of a location's gates (#348's deferred item).
    fn assert_gate(id: u16, gate: @Gate, anchor: @ZoneChunk) {
        assert(floor(*anchor.walls, *gate.anchor_tile), errors::GATE_ANCHOR);
        let [g0, g1] = *anchor.gates;
        assert(g0 == id || g1 == id, errors::GATE_INDEX);
    }

    /// R-31, at a `CANDIDATES` write (it reads the chunk set): every candidate chunk in the zone.
    fn assert_candidates(sets: Span<felt252>, chunk_set: felt252) {
        for set in sets {
            assert(BoardTrait::minus(*set, chunk_set) == 0, errors::CANDIDATES_OUTSIDE);
        }
    }

    /// R-29, R-12, R-13, R-27 and R-30, at a `QUOTAS` write of an authored zone (it reads the
    /// chunk set, `CANDIDATES` and the Heart's `PACK`): a kind an authored zone places (no exit,
    /// no set piece); each count at most the zone's members and its candidates; a Heart's
    /// template exists, at least 1 at its fewest and at its most; the draws of every pass, at
    /// most `MAX_DRAWS` together (D-220). `hearts`: the `PACK` read for each quota (`None` for a
    /// quota that is no Heart, or a template not in the registry).
    fn assert_quotas(
        quotas: @QuotaSet,
        chunk_set: felt252,
        candidates: Span<felt252>,
        hearts: Span<Option<Pack>>,
    ) {
        let members = BoardTrait::count(chunk_set);
        let mut draws: u16 = 0;
        let mut i: u32 = 0;
        for entry in quotas.quotas.span() {
            if *entry.kind != 0 {
                assert(
                    *entry.kind != quota::EXIT && *entry.kind != quota::SET_PIECE,
                    errors::QUOTA_KIND,
                );
                assert(*entry.count <= members, errors::ABOVE_MEMBERS);
                let set = if i < candidates.len() {
                    *candidates[i]
                } else {
                    0
                };
                let left = BoardTrait::count(set);
                assert(*entry.count <= left, errors::ABOVE_CANDIDATES);
                draws += Self::draws(*entry.count, left).into();
                if *entry.kind == quota::HEART {
                    match *hearts[i] {
                        Option::Some(pack) => {
                            let (low, high) = pack.bounds();
                            assert(low >= 1 && high >= 1, errors::HEART);
                        },
                        Option::None => { core::panic_with_felt252(errors::HEART); },
                    }
                }
            }
            i += 1;
        }
        assert(draws <= MAX_DRAWS, errors::DRAWS);
    }

    /// The draws of one pass (D-220's complement draw): none when the count takes every member,
    /// else the smaller of the subset and its complement.
    fn draws(count: u8, left: u8) -> u8 {
        if count >= left {
            0
        } else if count.into() * 2_u16 > left.into() {
            left - count
        } else {
            count
        }
    }

    /// R-28, at a dungeon floor's `LOCATION` write (ENG-R1c's bound): its rectangle larger than
    /// `N`, else its last chunks can be walled in (ADR-0006 *Outlines*).
    fn assert_floor_rectangle(location: @Location) {
        if *location.kind == location_kind::DUNGEON {
            let area: u16 = (*location.width).into() * (*location.height).into();
            assert(area > (*location.target).into(), errors::FLOOR_RECTANGLE);
        }
    }

    /// R-33, R-34 and R-35, at a `BRIDGE` write (it reads its chunk's `ZONE_CHUNK`): a deck, two
    /// distinct ends off the deck, each walkable and next to a deck tile; `k` below the chunk's
    /// bridge count. A one-tile deck with its two ends is valid (D-217).
    fn assert_bridge(bridge: @Bridge, k: u8, chunk: u8, record: @ZoneChunk) {
        let deck = *bridge.deck;
        assert(deck != 0, errors::BRIDGE_DECK);
        let (a, b) = *bridge.ends;
        assert(
            a < 225 && b < 225 && a != b && !BoardTrait::has(deck, a) && !BoardTrait::has(deck, b),
            errors::BRIDGE_END,
        );
        assert(k < *record.bridges, errors::BRIDGE_INDEX);
        let walls = *record.walls;
        assert(floor(walls, a) && floor(walls, b), errors::BRIDGE_FLOOR);
        let near = BoardTrait::dilate(deck, odd(chunk));
        assert(BoardTrait::has(near, a) && BoardTrait::has(near, b), errors::BRIDGE_APART);
    }
}
