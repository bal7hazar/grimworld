//! The costs of ENG-08 deliverable 3 (AC-4), each a pair: `test_pair_<group>_<what>` less its
//! base `test_base_<group>` (the longest group that prefixes it, `pairs.py`), two tests that differ
//! by the measured call alone (CBT-02d's method). `Registry` and the library are measured as they
//! are; a record of a proposed kind is written through an existing kind of its part count, each
//! proxy named: `ZONE_CHUNK` (2 parts) as `SET_PIECE`, `CANDIDATES` (3) as `BOOK`, `BRIDGE` (1) as
//! `OUTLINE`.

use grimworld_logic::content::{
    BOOK, CRITERION_REACH_LANDMARK, GATE, LOCATION, OUTLINE, QUOTAS, SET_PIECE,
};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
use grimworld_logic::models::chunk::Object;
use grimworld_logic::models::gate::GateRecord;
use grimworld_logic::models::location::LocationRecord;
use grimworld_logic::models::outline::{Outline, OutlineRecord};
use grimworld_logic::models::quotas::{Quota, QuotaSet, QuotaSetRecord, kind as quota};
use grimworld_logic::models::set_piece::{SetPack, SetPiece, SetPieceRecord};
use grimworld_logic::models::spawn_table::SpawnTable;
use grimworld_logic::packing::LIVE;
use grimworld_logic::snapshot::TaskEntry;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use grimworld_logic::types::reveal::placement::PlacementTrait;
use grimworld_logic::types::reveal::{ProgressTrait, Site};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use spk16::authored::AuthoredTrait;
use spk16::checks::{ZoneAssert, rectangle};
use spk16::library::{
    IAuthoredLibraryDispatcherTrait, IAuthoredLibraryLibraryDispatcher, IChunkSlotsDispatcher,
    IChunkSlotsDispatcherTrait,
};
use spk16::records::BridgeTrait;
use spk16::zone_chunk::ZoneChunkRecord;
use starknet::ContractAddress;
use crate::fixtures::{Zone, ZoneTrait, load, templates};

const ADMIN: felt252 = 'admin';
const INSTANCE: felt252 = 'instance 7';
const ENTROPY: felt252 = 'entropy';

#[derive(Copy, Drop)]
struct Registry {
    admin: IRegistryAdminDispatcher,
    read: IRegistryReadDispatcher,
}

fn registry() -> Registry {
    let class = declare("Registry").unwrap().contract_class();
    let (address, _) = class.deploy(@array![ADMIN]).unwrap();
    let admin: ContractAddress = ADMIN.try_into().unwrap();
    start_cheat_caller_address(address, admin);
    Registry {
        admin: IRegistryAdminDispatcher { contract_address: address },
        read: IRegistryReadDispatcher { contract_address: address },
    }
}

/// The `SET_PIECE` proxy of a `ZONE_CHUNK`: the sample's chunk 16's walls with its corners walled
/// (D-134 is `SetPieceAssert`'s), two packs and three objects on its interior floor.
fn piece(z: @Zone) -> SetPiece {
    let corners: felt252 = 0x100040000000000000000000000000000000000000000000000004001;
    let walls = BoardTrait::or(z.chunk(16).walls, corners);
    let interior: felt252 = 0x1fff3ffe7ffcfff9fff3ffe7ffcfff9fff3ffe7ffcfff9fff0000;
    let free = BoardTrait::and(BoardTrait::minus(BOARD, walls), interior);
    SetPiece {
        walls,
        packs: [
            SetPack { tile: BoardTrait::nth(free, 0), template: 1 },
            SetPack { tile: BoardTrait::nth(free, 1), template: 2 },
        ],
        objects: [
            Object { tile: BoardTrait::nth(free, 2), kind: 1, state: 0, param: 0 },
            Object { tile: BoardTrait::nth(free, 3), kind: 6, state: 0, param: 0x1234 },
            Object { tile: BoardTrait::nth(free, 4), kind: 7, state: 0, param: 0 },
        ],
    }
}

fn book(seed: felt252) -> Span<felt252> {
    array![seed + LIVE, seed * 3 + LIVE, seed * 5 + LIVE].span()
}

// --- registration ------------------------------------------------------------------------------

#[test]
fn test_base_registry() {
    let z = load();
    let _piece = piece(@z);
    let _r = registry();
}

/// One `ZONE_CHUNK` written new (proxy: `SET_PIECE`, its `SetPieceAssert` included).
#[test]
fn test_pair_registry_chunk_new() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
}

/// One `CANDIDATES` written new (proxy: `BOOK`, 3 parts, no content check).
#[test]
fn test_pair_registry_candidates_new() {
    let z = load();
    let _piece = piece(@z);
    let r = registry();
    r.admin.set_record(BOOK, 1, book(7));
}

#[test]
fn test_base_registry_one() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
}

/// The same chunk rewritten, its features part changed (an object's param), its plane unchanged.
#[test]
fn test_pair_registry_one_rewrite() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
    let [o0, o1, o2] = piece.objects;
    let other = SetPiece { objects: [o0, o1, Object { param: 0x4321, ..o2 }], ..piece };
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@other));
}

#[test]
fn test_base_registry_location() {
    let z = load();
    let _piece = piece(@z);
    let r = registry();
    r.admin.set_record(LOCATION, 1, LocationRecord::pack(@z.location));
}

/// One `BRIDGE` written new (proxy: `OUTLINE`, 1 part, composite, its location read): the sample's
/// one-tile deck and its two ends (D-217's storage).
#[test]
fn test_pair_registry_location_bridge_new() {
    let z = load();
    let _piece = piece(@z);
    let r = registry();
    r.admin.set_record(LOCATION, 1, LocationRecord::pack(@z.location));
    let (_, _, bridge) = *z.bridges[0];
    r.admin.set_record(OUTLINE, 256 + 200, bridge.pack());
}

/// The largest zone the format allows: 225 chunk records in one test (a multicall's writes,
/// without the account's own share).
#[test]
fn test_pair_registry_225_chunks() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    let parts = SetPieceRecord::pack(@piece);
    for id in 1..226_u32 {
        r.admin.set_record(SET_PIECE, id, parts);
    }
}

/// The sample zone's 14 writes in the converter's order (`samples/zone.records.json`), the
/// proposed kinds through their proxies, the ids made sequential where the proxy's kind is.
#[test]
fn test_pair_registry_sample_zone() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    let parts = SetPieceRecord::pack(@piece);
    // LOCATION (id 1), the chunk set, CANDIDATES (BOOK), QUOTAS, the two masks
    r.admin.set_record(LOCATION, 1, LocationRecord::pack(@z.location));
    let set: u256 = z.chunk_set.into();
    r
        .admin
        .set_record(
            OUTLINE, 255 + 256, OutlineRecord::pack(@Outline { low: set.low, high: set.high }),
        );
    r.admin.set_record(BOOK, 1, book(7));
    r.admin.set_record(QUOTAS, 1, QuotaSetRecord::pack(@z.quotas));
    for entry in z.masks.span() {
        let (chunk, mask) = *entry;
        let wide: u256 = mask.into();
        r
            .admin
            .set_record(
                OUTLINE,
                256 + chunk.into(),
                OutlineRecord::pack(@Outline { low: wide.low, high: wide.high }),
            );
    }
    // The five chunks (SET_PIECE), the bridge (OUTLINE, a chunk with no mask), the two gates
    for id in 1..6_u32 {
        r.admin.set_record(SET_PIECE, id, parts);
    }
    let (_, _, bridge) = *z.bridges[0];
    r.admin.set_record(OUTLINE, 256 + 200, bridge.pack());
    let mut id: u32 = 1;
    for entry in z.gates.span() {
        let (_, gate) = *entry;
        r.admin.set_record(GATE, id, GateRecord::pack(@gate));
        id += 1;
    }
}

// --- the Registry's checks of a chunk, in memory
// --------------------------------------------------

#[test]
fn test_base_memory() {
    let z = load();
    let _site = z.site();
    let _record = z.chunk(16);
}

/// R-14, R-15, R-20, R-24 on the sample's fullest chunk (16: a spawn point, a lever, two
/// candidates, a gate, a mask).
#[test]
fn test_pair_memory_check_chunk() {
    let z = load();
    let _site = z.site();
    let record = z.chunk(16);
    ZoneAssert::assert_outline(16, record.walls, z.chunk_set, z.mask(16));
    ZoneAssert::assert_chunk(@record, 16, z.sets(), @z.quotas);
}

/// R-12, R-13, R-27, R-29, R-30 at the `QUOTAS` write.
#[test]
fn test_pair_memory_check_quotas() {
    let z = load();
    let _site = z.site();
    let _record = z.chunk(16);
    ZoneAssert::assert_quotas(@z.quotas, z.chunk_set, z.sets(), z.hearts.span());
}

// --- the reveal of an authored chunk, in memory -----------------------------------------------

#[test]
fn test_base_reveal() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let _hosts = z.sets();
    let _keep = (site, parts);
}

/// Chunk 16's record decoded (`ZoneChunkRecord::unpack`).
#[test]
fn test_pair_reveal_decode() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let _hosts = z.sets();
    let _keep = (site, ZoneChunkRecord::unpack(parts));
}

/// Chunk 16 revealed with every candidate hosted (its worst: a Heart, a collector, a spawn point
/// of the raiders, a lever), the record decoded inside.
#[test]
fn test_pair_reveal_chunk_16() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let hosts = z.sets();
    let record = ZoneChunkRecord::unpack(parts);
    let _words = AuthoredTrait::reveal(@site, 16, @record, hosts, ENTROPY, INSTANCE);
}

/// The worst authored chunk E-3 allows: two spawn points of the raiders (2 to 5 goblins), three
/// objects, the record decoded inside.
#[test]
fn test_pair_reveal_worst() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let _hosts = z.sets();
    let mut record = ZoneChunkRecord::unpack(parts);
    let free = BoardTrait::minus(BOARD, record.walls);
    record
        .spawns =
            [
                SetPack { tile: BoardTrait::nth(free, 40), template: 1 },
                SetPack { tile: BoardTrait::nth(free, 120), template: 1 },
            ];
    record
        .objects =
            [
                Object { tile: BoardTrait::nth(free, 10), kind: 1, state: 0, param: 0 },
                Object { tile: BoardTrait::nth(free, 80), kind: 3, state: 0, param: 0 },
                Object { tile: BoardTrait::nth(free, 150), kind: 7, state: 0, param: 0 },
            ];
    record.tiles = [0, 0, 0, 0, 0, 0];
    let parts = ZoneChunkRecord::pack(@record);
    let record = ZoneChunkRecord::unpack(parts);
    let _words = AuthoredTrait::reveal(@site, 16, @record, array![].span(), ENTROPY, INSTANCE);
}

/// The same worst chunk without its decode (to tell the decode from the placement).
#[test]
fn test_base_reveal_worst_fixture() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let _hosts = z.sets();
    let mut record = ZoneChunkRecord::unpack(parts);
    let free = BoardTrait::minus(BOARD, record.walls);
    record
        .spawns =
            [
                SetPack { tile: BoardTrait::nth(free, 40), template: 1 },
                SetPack { tile: BoardTrait::nth(free, 120), template: 1 },
            ];
    record
        .objects =
            [
                Object { tile: BoardTrait::nth(free, 10), kind: 1, state: 0, param: 0 },
                Object { tile: BoardTrait::nth(free, 80), kind: 3, state: 0, param: 0 },
                Object { tile: BoardTrait::nth(free, 150), kind: 7, state: 0, param: 0 },
            ];
    record.tiles = [0, 0, 0, 0, 0, 0];
    let parts = ZoneChunkRecord::pack(@record);
    let _record = ZoneChunkRecord::unpack(parts);
}

/// Chunk 0 revealed with nothing hosted (the entry chunk: a landmark, no pack).
#[test]
fn test_pair_reveal_chunk_0() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let _hosts = z.sets();
    let (_, _, entry) = *z.chunks[0];
    let record = ZoneChunkRecord::unpack(entry);
    let _keep = parts;
    let _words = AuthoredTrait::reveal(@site, 0, @record, array![].span(), ENTROPY, INSTANCE);
}

// --- the draws at entry ------------------------------------------------------------------------

#[test]
fn test_base_hosts() {
    let z = load();
    let _sets = z.sets();
}

/// The sample's three quotas drawn among their candidates.
#[test]
fn test_pair_hosts_sample() {
    let z = load();
    let sets = z.sets();
    let _hosts = AuthoredTrait::hosts(
        @z.quotas, sets, AuthoredTrait::hosts_seed(ENTROPY, INSTANCE),
    );
}

/// The worst draw among candidates R-15 allows on 15 × 15: three object quotas and two Hearts,
/// each 112 of 225 candidates (five passes of 112 draws; a chunk is a candidate of at most three
/// object quotas and two Hearts).
#[test]
fn test_pair_hosts_worst_authored() {
    let z = load();
    let _sets = z.sets();
    let all = rectangle(15, 15);
    let quotas = QuotaSet {
        quotas: [
            Quota { kind: quota::COLLECTOR, param: 1, count: 112 },
            Quota { kind: quota::VEIN, param: 0, count: 112 },
            Quota { kind: quota::LANDMARK, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 2, count: 112 }, Default::default(),
        ],
    };
    let sets = array![all, all, all, all, all, 0].span();
    let hosts = AuthoredTrait::hosts(@quotas, sets, AuthoredTrait::hosts_seed(ENTROPY, INSTANCE));
    assert(BoardTrait::count(*hosts[4]) == 112, 'five passes');
}

/// R-30's bound on the authored path (review t-0084, note 4): six quotas among 225 candidates
/// each, five of 112 and one of 80, 640 draws (the draw alone: R-15 would refuse six all-chunk
/// quotas in a real zone, so this is an upper bound of what R-30 lets through).
#[test]
fn test_pair_hosts_bound_authored() {
    let z = load();
    let _sets = z.sets();
    let all = rectangle(15, 15);
    let quotas = QuotaSet {
        quotas: [
            Quota { kind: quota::COLLECTOR, param: 1, count: 112 },
            Quota { kind: quota::VEIN, param: 0, count: 112 },
            Quota { kind: quota::LANDMARK, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 2, count: 112 },
            Quota { kind: quota::LANDMARK, param: 2, count: 80 },
        ],
    };
    let sets = array![all, all, all, all, all, all].span();
    let hosts = AuthoredTrait::hosts(@quotas, sets, AuthoredTrait::hosts_seed(ENTROPY, INSTANCE));
    assert(BoardTrait::count(*hosts[5]) == 80, 'six passes');
}

// --- D-220: ENG-05's generated hosts, the worst legal plan with the snapshot's tasks -------------

/// ENG-05's mixed plan (`mixed` in `types/reveal.cairo`): three object quotas, two Hearts and a
/// set piece on 15 × 15, the last one of `last` (112: the worst legal plan; 80: 640 draws, the
/// bound ENG-08 proposes).
fn generated(tasks: u32, last: u8) -> Site {
    let quotas = QuotaSet {
        quotas: [
            Quota { kind: quota::COLLECTOR, param: 1, count: 112 },
            Quota { kind: quota::VEIN, param: 0, count: 112 },
            Quota { kind: quota::EXIT, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 1, count: 112 },
            Quota { kind: quota::HEART, param: 2, count: 112 },
            Quota { kind: quota::SET_PIECE, param: 9, count: last },
        ],
    };
    let mut entries: Array<TaskEntry> = array![];
    for k in 0..tasks {
        entries.append(TaskEntry { task: k + 1, kind: CRITERION_REACH_LANDMARK, param: 1 });
    }
    Site {
        target: 0,
        biome: 1,
        level_min: 1,
        level_max: 5,
        width: 15,
        height: 15,
        entry_chunk: 0,
        chunk_set: 0,
        masks: array![].span(),
        anchors: array![].span(),
        quotas,
        tasks: entries.span(),
        spawn: SpawnTable {
            spawns: [
                Default::default(), Default::default(), Default::default(), Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
            density: 0,
        },
        packs: templates(),
        pieces: array![].span(),
    }
}

#[test]
fn test_base_plan_tasks() {
    let site = generated(8, 112);
    let start = ProgressTrait::new(@site, 'worst');
    let _plan = PlacementTrait::plan(@site, start.left.span());
}

/// ENG-05's worst legal plan (`test_hosts_worst_half`: six passes of 112) with the snapshot's
/// eight landmark tasks, each a quota of one (D-220's bound read with the tasks).
#[test]
fn test_pair_plan_tasks_hosts() {
    let site = generated(8, 112);
    let start = ProgressTrait::new(@site, 'worst');
    let plan = PlacementTrait::plan(@site, start.left.span());
    let hosts = PlacementTrait::hosts(0, 15, 15, plan, array![].span(), 'worst');
    assert(hosts.len() == 14, 'fourteen quotas');
}

#[test]
fn test_base_plan_none() {
    let site = generated(0, 112);
    let start = ProgressTrait::new(@site, 'worst');
    let _plan = PlacementTrait::plan(@site, start.left.span());
}

/// The same without the tasks: ENG-05's figure, the call alone.
#[test]
fn test_pair_plan_none_hosts() {
    let site = generated(0, 112);
    let start = ProgressTrait::new(@site, 'worst');
    let plan = PlacementTrait::plan(@site, start.left.span());
    let _hosts = PlacementTrait::hosts(0, 15, 15, plan, array![].span(), 'worst');
}

#[test]
fn test_base_plan_bound() {
    let site = generated(8, 80);
    let start = ProgressTrait::new(@site, 'worst');
    let _plan = PlacementTrait::plan(@site, start.left.span());
}

/// The worst plan the proposed bound (R-30, 640 draws over the location's quotas) lets through,
/// with the eight tasks.
#[test]
fn test_pair_plan_bound_hosts() {
    let site = generated(8, 80);
    let start = ProgressTrait::new(@site, 'worst');
    let plan = PlacementTrait::plan(@site, start.left.span());
    let _hosts = PlacementTrait::hosts(0, 15, 15, plan, array![].span(), 'worst');
}

// --- reads, the copy into the instance, the library call ----------------------------------------

#[test]
fn test_base_read() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
    r.admin.set_record(BOOK, 1, book(7));
    let _none = r.read.bundle(array![].span());
}

/// One 2-part chunk record in `create`'s `bundle` (its slots, beside the call `Instances` makes).
#[test]
fn test_pair_read_chunk() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
    r.admin.set_record(BOOK, 1, book(7));
    let _one = r.read.bundle(array![(SET_PIECE, 1)].span());
}

/// The chunk and a 3-part `CANDIDATES` in one `bundle` (what `create` adds in a zone with quotas).
#[test]
fn test_pair_read_chunk_and_candidates() {
    let z = load();
    let piece = piece(@z);
    let r = registry();
    r.admin.set_record(SET_PIECE, 1, SetPieceRecord::pack(@piece));
    r.admin.set_record(BOOK, 1, book(7));
    let _two = r.read.bundle(array![(SET_PIECE, 1), (BOOK, 1)].span());
}

#[test]
fn test_base_slots() {
    let class = declare("ChunkSlots").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    let slots = IChunkSlotsDispatcher { contract_address: address };
    slots.nothing(3, 16, 'terrain' + LIVE, 'features' + LIVE);
}

/// The chunk's two words written into new slots (ruling 2's copy).
#[test]
fn test_pair_slots_write() {
    let class = declare("ChunkSlots").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    let slots = IChunkSlotsDispatcher { contract_address: address };
    slots.write(3, 16, 'terrain' + LIVE, 'features' + LIVE);
}

#[test]
fn test_base_library() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let hosts = z.sets();
    let class = declare("AuthoredLibrary").unwrap().contract_class();
    let _keep = (site, parts, hosts, *class.class_hash);
}

/// `Instances`' library call of chunk 16's reveal, as `RevealLibrary` is called (the syscall, the
/// `Site` and the words through calldata), the same reveal as `test_pair_reveal_chunk_16` inside.
#[test]
fn test_pair_library_reveal() {
    let z = load();
    let site = z.site();
    let (_, _, parts) = *z.chunks[4];
    let hosts = z.sets();
    let class = declare("AuthoredLibrary").unwrap().contract_class();
    let library = IAuthoredLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _words = library.reveal(site, 16, parts, hosts, ENTROPY, INSTANCE);
}
