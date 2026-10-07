//! The Registry's checks of an authored zone (ENG-08 deliverable 2, AC-3): the sample passes every
//! one, and each case of `map-format/checks.json`'s `registry` table, the same mutation of the
//! sample, is refused with its code, as the converter refuses it (`map-format/tests`).

use grimworld_logic::models::chunk::{Object, object};
use grimworld_logic::models::location::kind as location_kind;
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{Quota, kind as quota};
use grimworld_logic::models::set_piece::SetPack;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use spk16::checks::ZoneAssert;
use spk16::records::Bridge;
use spk16::zone_chunk::ZoneChunk;
use crate::fixtures::{Zone, ZoneTrait, load};

/// Every check of every record of the sample, as each write reads them.
fn check(z: @Zone) {
    ZoneAssert::assert_floor_rectangle(z.location);
    ZoneAssert::assert_set(*z.chunk_set, *z.location.width, *z.location.height);
    ZoneAssert::assert_candidates(z.sets(), *z.chunk_set);
    ZoneAssert::assert_quotas(z.quotas, *z.chunk_set, z.sets(), z.hearts.span());
    for entry in z.chunks.span() {
        let (chunk, record, _) = *entry;
        ZoneAssert::assert_outline(chunk, record.walls, *z.chunk_set, z.mask(chunk));
        ZoneAssert::assert_chunk(@record, chunk, z.sets(), z.quotas);
    }
    for entry in z.bridges.span() {
        let (chunk, k, bridge) = *entry;
        ZoneAssert::assert_bridge(@bridge, k, chunk, @z.chunk(chunk));
    }
    ZoneAssert::assert_entry(z.location, @z.chunk(*z.location.entry_chunk));
    for entry in z.gates.span() {
        let (id, gate) = *entry;
        ZoneAssert::assert_gate(id, @gate, @z.chunk(gate.anchor_chunk));
    }
}

fn first_wall(record: @ZoneChunk) -> u8 {
    BoardTrait::nth(*record.walls, 0)
}

/// The record's chunk replaced.
fn with_chunk(ref z: Zone, chunk: u8, record: ZoneChunk) {
    let mut chunks = array![];
    for entry in z.chunks.span() {
        let (at, old, parts) = *entry;
        chunks.append((at, if at == chunk {
            record
        } else {
            old
        }, parts));
    }
    z.chunks = chunks;
}

fn bridge(z: @Zone) -> (u8, u8, Bridge) {
    *z.bridges[0]
}

#[test]
fn test_sample_passes_every_check() {
    let z = load();
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: set outside rectangle')]
fn test_refuse_set_outside() {
    let mut z = load();
    z.chunk_set += BoardTrait::pow(3);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: count above members')]
fn test_refuse_count_above_members() {
    let mut z = load();
    let [_, q1, q2, q3, q4, q5] = z.quotas.quotas;
    z.quotas.quotas = [Quota { kind: quota::COLLECTOR, param: 1, count: 6 }, q1, q2, q3, q4, q5];
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: count above candidates')]
fn test_refuse_count_above_candidates() {
    let mut z = load();
    let [_, q1, q2, q3, q4, q5] = z.quotas.quotas;
    z.quotas.quotas = [Quota { kind: quota::COLLECTOR, param: 1, count: 3 }, q1, q2, q3, q4, q5];
    check(@z);
}

#[test]
#[should_panic(expected: 'zone chunk: tile not floor')]
fn test_refuse_spawn_on_wall() {
    let mut z = load();
    let mut record = z.chunk(1);
    let [s0, s1] = record.spawns;
    record.spawns = [SetPack { tile: first_wall(@record), ..s0 }, s1];
    with_chunk(ref z, 1, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone chunk: object')]
fn test_refuse_object_kind() {
    let mut z = load();
    let mut record = z.chunk(0);
    let [o0, o1, o2] = record.objects;
    assert(o0.kind == object::LANDMARK, 'the landmark');
    record.objects = [Object { kind: object::VEIN, ..o0 }, o1, o2];
    with_chunk(ref z, 0, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone chunk: empty with a value')]
fn test_refuse_empty_with_value() {
    let mut z = load();
    let mut record = z.chunk(0);
    let [t0, _, t2, t3, t4, t5] = record.tiles;
    record.tiles = [t0, 5, t2, t3, t4, t5];
    with_chunk(ref z, 0, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone chunk: tile taken')]
fn test_refuse_tile_taken() {
    let mut z = load();
    let mut record = z.chunk(2);
    let [s0, _] = record.spawns;
    let [o0, o1, o2] = record.objects;
    assert(o0.kind == object::CHEST, 'the chest');
    record.objects = [Object { tile: s0.tile, ..o0 }, o1, o2];
    with_chunk(ref z, 2, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone chunk: over its caps')]
fn test_refuse_over_caps() {
    let mut z = load();
    let mut record = z.chunk(2);
    // The first two floor tiles no placement takes
    let mut taken: felt252 = 0;
    for spawn in record.spawns.span() {
        if *spawn.template != 0 {
            taken += BoardTrait::pow(*spawn.tile);
        }
    }
    for item in record.objects.span() {
        if *item.kind != 0 {
            taken += BoardTrait::pow(*item.tile);
        }
    }
    let sets = z.sets();
    let mut i: u32 = 0;
    for tile in record.tiles.span() {
        if BoardTrait::has(*sets[i], 2) {
            taken += BoardTrait::pow(*tile);
        }
        i += 1;
    }
    let free = BoardTrait::minus(BoardTrait::minus(BOARD, record.walls), taken);
    let [o0, _, _] = record.objects;
    record
        .objects =
            [
                o0,
                Object { tile: BoardTrait::nth(free, 0), kind: object::CHEST, state: 0, param: 0 },
                Object { tile: BoardTrait::nth(free, 1), kind: object::CHEST, state: 0, param: 0 },
            ];
    with_chunk(ref z, 2, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: gate anchor not floor')]
fn test_refuse_gate_anchor_not_floor() {
    let mut z = load();
    let wall = first_wall(@z.chunk(16));
    let mut gates = array![];
    for entry in z.gates.span() {
        let (id, mut gate) = *entry;
        if id == 3 {
            gate.anchor_tile = wall;
        }
        gates.append((id, gate));
    }
    z.gates = gates;
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: mask disagrees')]
fn test_refuse_mask_disagrees() {
    let mut z = load();
    let mut record = z.chunk(2);
    assert(BoardTrait::has(record.walls, 14), 'outside the mask');
    record.walls -= BoardTrait::pow(14);
    with_chunk(ref z, 2, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: chunk not in the set')]
fn test_refuse_chunk_not_in_set() {
    let mut z = load();
    z.chunk_set -= BoardTrait::pow(0);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: gate not indexed')]
fn test_refuse_gate_not_indexed() {
    let mut z = load();
    let mut record = z.chunk(16);
    record.gates = [0, 0];
    with_chunk(ref z, 16, record);
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: entry not floor')]
fn test_refuse_entry_not_floor() {
    let mut z = load();
    z.location.entry_tile = first_wall(@z.chunk(0));
    check(@z);
}

/// Review t-0084's scenario (minor 1): `QUOTAS` written while quota 0 has two candidate chunks
/// (count 2 passes R-13), then `CANDIDATES` rewritten with one: the `CANDIDATES` write re-runs
/// R-13.
#[test]
#[should_panic(expected: 'zone: count above candidates')]
fn test_refuse_candidates_rewrite_count() {
    let mut z = load();
    let [_, q1, q2, q3, q4, q5] = z.quotas.quotas;
    z.quotas.quotas = [Quota { kind: quota::COLLECTOR, param: 1, count: 2 }, q1, q2, q3, q4, q5];
    ZoneAssert::assert_quotas(@z.quotas, z.chunk_set, z.sets(), z.hearts.span());
    let [_, c1, c2] = z.candidates;
    z.candidates = [BoardTrait::pow(16), c1, c2];
    let chunks = array![(1, z.chunk(1)), (16, z.chunk(16))];
    ZoneAssert::assert_candidates_write(
        z.sets(), z.chunk_set, Option::Some(@z.quotas), z.hearts.span(), chunks.span(),
    );
}

/// `CANDIDATES` rewritten without chunk 1 for quota 0 (its count still met by chunk 16): chunk 1's
/// record keeps a candidate tile for a quota that no longer names it, R-14 re-run on it.
#[test]
#[should_panic(expected: 'zone chunk: empty with a value')]
fn test_refuse_candidates_rewrite_tile() {
    let mut z = load();
    let [c0, c1, c2] = z.candidates;
    assert(BoardTrait::has(c0, 1), 'chunk 1 named');
    z.candidates = [c0 - BoardTrait::pow(1), c1, c2];
    let chunks = array![(1, z.chunk(1))];
    ZoneAssert::assert_candidates_write(
        z.sets(), z.chunk_set, Option::Some(@z.quotas), z.hearts.span(), chunks.span(),
    );
}

/// The raiders' `PACK` rewritten with every minimum 0 while quota 2, a Heart, names it.
#[test]
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_pack_rewrite_heart() {
    let empty = Pack {
        castes: [
            PackCaste { caste: 1, min: 0, max: 2 }, PackCaste { caste: 2, min: 0, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    ZoneAssert::assert_pack_write(@empty, true);
}

#[test]
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_heart_template() {
    let mut z = load();
    let empty = Pack {
        castes: [
            PackCaste { caste: 3, min: 0, max: 2 }, Default::default(), Default::default(),
            Default::default(), Default::default(),
        ],
        level: 0,
    };
    z.hearts = array![Option::None, Option::None, Option::Some(empty)];
    check(@z);
}

#[test]
#[should_panic(expected: 'location: floor rectangle')]
fn test_refuse_floor_rectangle() {
    let mut z = load();
    z.location.kind = location_kind::DUNGEON;
    z.location.target = 6;
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: quota kind')]
fn test_refuse_quota_kind() {
    let mut z = load();
    let [q0, q1, q2, q3, q4, q5] = z.quotas.quotas;
    z.quotas.quotas = [q0, Quota { kind: quota::EXIT, ..q1 }, q2, q3, q4, q5];
    check(@z);
}

#[test]
#[should_panic(expected: 'zone: quota draws')]
fn test_refuse_quota_draws() {
    let z = load();
    let all = spk16::checks::rectangle(15, 15);
    let quotas = grimworld_logic::models::quotas::QuotaSet {
        quotas: [
            Quota { kind: quota::COLLECTOR, param: 1, count: 112 },
            Quota { kind: quota::VEIN, param: 0, count: 112 },
            Quota { kind: quota::LANDMARK, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 1, count: 112 },
            Quota { kind: quota::LANDMARK, param: 2, count: 112 },
        ],
    };
    let (_, raiders) = *crate::fixtures::templates()[0];
    let hearts = array![
        Option::None, Option::None, Option::None, Option::Some(raiders), Option::Some(raiders),
        Option::None,
    ];
    let _ = z.chunk_set;
    ZoneAssert::assert_quotas(
        @quotas, all, array![all, all, all, all, all, all].span(), hearts.span(),
    );
}

#[test]
#[should_panic(expected: 'candidates: outside the set')]
fn test_refuse_candidates_outside() {
    let mut z = load();
    let [c0, c1, c2] = z.candidates;
    z.candidates = [c0 + BoardTrait::pow(3), c1, c2];
    check(@z);
}

#[test]
#[should_panic(expected: 'bridge: deck empty')]
fn test_refuse_bridge_deck() {
    let z = load();
    let (chunk, k, b) = bridge(@z);
    ZoneAssert::assert_bridge(@Bridge { deck: 0, ..b }, k, chunk, @z.chunk(chunk));
}

#[test]
#[should_panic(expected: 'bridge: end')]
fn test_refuse_bridge_end() {
    let z = load();
    let (chunk, k, b) = bridge(@z);
    let (a, _) = b.ends;
    ZoneAssert::assert_bridge(@Bridge { ends: (a, a), ..b }, k, chunk, @z.chunk(chunk));
}

#[test]
#[should_panic(expected: 'bridge: end not floor')]
fn test_refuse_bridge_floor() {
    let z = load();
    let (chunk, k, b) = bridge(@z);
    let (_, e) = b.ends;
    let wall = first_wall(@z.chunk(chunk));
    ZoneAssert::assert_bridge(@Bridge { ends: (wall, e), ..b }, k, chunk, @z.chunk(chunk));
}

#[test]
#[should_panic(expected: 'bridge: end not by the deck')]
fn test_refuse_bridge_apart() {
    let z = load();
    let (chunk, k, b) = bridge(@z);
    let (_, e) = b.ends;
    let floor = BoardTrait::nth(BoardTrait::minus(BOARD, z.chunk(chunk).walls), 0);
    ZoneAssert::assert_bridge(@Bridge { ends: (floor, e), ..b }, k, chunk, @z.chunk(chunk));
}

#[test]
#[should_panic(expected: 'bridge: index')]
fn test_refuse_bridge_index() {
    let z = load();
    let (chunk, _, b) = bridge(@z);
    ZoneAssert::assert_bridge(@b, 1, chunk, @z.chunk(chunk));
}
