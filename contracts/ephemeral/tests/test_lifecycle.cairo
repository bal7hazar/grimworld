// ENG-06: the instance lifecycle on `Instances` (design/02 *Expedition lifecycle*; ENG-01 §2.1,
// §4.1, §6, §9.3). `create` and `set_controller` are called as the registered hub; the registry,
// the randomness provider and the hub's results are doubles here (the real `Registry`, `TxHashFate`
// and `Hub` live in `grimworld_persistent`, which this package does not depend on; the node probe
// `contracts/tools/lifecycle_probe.py` runs the real ones together). Write sets are counted over
// the keys a test watches (`load` before and after).
use core::poseidon::poseidon_hash_span;
use core::testing::get_available_gas;
use grimworld_ephemeral::events::{InstanceClosed, InstanceEntered, Refused};
use grimworld_ephemeral::models::instance::errors::{
    ALREADY_INSIDE, NOT_HUB, NOT_INSIDE, NO_GATE, NO_LOCATION, NO_MAP, TOO_MANY_TASKS,
};
use grimworld_ephemeral::models::instance::{Header, OPEN, Placement, Quotas, RETURNED, SEALED};
use grimworld_ephemeral::models::member::errors::NOT_CONTROLLER;
use grimworld_ephemeral::models::member::{
    Effect, GONE, INSIDE, MemberEffects, MemberState, MemberTimers, MemberTimersTrait, NO_SLOT,
    Recharges,
};
use grimworld_ephemeral::systems::instances::Instances::Event;
use grimworld_ephemeral::systems::instances::{
    IInstancesDispatcher, IInstancesDispatcherTrait, IInstancesSafeDispatcher,
    IInstancesSafeDispatcherTrait, InstanceView,
};
use grimworld_logic::content::{GATE, LOCATION, OUTLINE, PACK, QUOTAS, REGION, SPAWN_TABLE};
use grimworld_logic::fate::{ENTRY, EntropyTrait, derive, domain};
use grimworld_logic::interface::{
    IInstanceEntryDispatcher, IInstanceEntryDispatcherTrait, IInstanceEntrySafeDispatcher,
    IInstanceEntrySafeDispatcherTrait, facts,
};
use grimworld_logic::models::caste::{CasteRecord, WeaponTrait};
use grimworld_logic::models::chunk::{FeaturesStorePacking, Terrain, TerrainStorePacking, object};
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::outline::{CHUNK_SET, OutlineRecord, OutlineTrait};
use grimworld_logic::models::pack::{Pack, PackCaste, PackRecord};
use grimworld_logic::models::quotas::{Quota, QuotaSet, QuotaSetRecord, kind as quota_kind};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable, SpawnTableRecord};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::snapshot::{Snapshot, SnapshotTrait, TaskEntry, TaskPage};
use grimworld_logic::types::reveal::board::BoardTrait;
use grimworld_logic::types::reveal::outline::OutlineTrait as FloorTrait;
use grimworld_logic::types::reveal::placement::PlacementTrait as QuotaPlacementTrait;
use grimworld_logic::types::reveal::{Progress, ProgressTrait, RevealTrait, Site};
use grimworld_logic::types::{ChunkKind, Outcome, Refusal, instance_id};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, EventSpyTrait,
    EventsFilterTrait, declare, load, map_entry_address, spy_events, start_cheat_caller_address,
    store,
};
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

// ---- doubles ------------------------------------------------------------------------------------

#[starknet::interface]
pub trait IRecords<T> {
    fn set(ref self: T, kind: u8, id: u32, parts: Span<felt252>);
}

/// Answers `record` as `Registry` does: `parts(kind)` felts, zeros for a record never written.
#[starknet::contract]
mod RegistryDouble {
    use grimworld_logic::content::parts;
    use grimworld_logic::interface::IRegistryRead;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        records: Map<(u8, u32, u8), felt252>,
    }

    #[abi(embed_v0)]
    impl RecordsImpl of super::IRecords<ContractState> {
        fn set(ref self: ContractState, kind: u8, id: u32, parts: Span<felt252>) {
            let mut part: u8 = 0;
            for felt in parts {
                self.records.write((kind, id, part), *felt);
                part += 1;
            }
        }
    }

    #[abi(embed_v0)]
    impl ReadImpl of IRegistryRead<ContractState> {
        fn record(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            let mut out = array![];
            for part in 0..parts(kind) {
                out.append(self.records.read((kind, id, part)));
            }
            out.span()
        }
        fn records(self: @ContractState, kind: u8, ids: Span<u32>) -> Span<felt252> {
            let mut out = array![];
            for id in ids {
                for part in 0..parts(kind) {
                    out.append(self.records.read((kind, *id, part)));
                }
            }
            out.span()
        }
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, u32, Span<felt252>) {
            let mut out = array![];
            for request in requests {
                let (kind, id) = *request;
                for part in 0..parts(kind) {
                    out.append(self.records.read((kind, id, part)));
                }
            }
            (0, 0, out.span())
        }
        fn content_version(self: @ContractState) -> u32 {
            0
        }
    }
}

#[starknet::interface]
pub trait IDraws<T> {
    fn draws(self: @T) -> u32;
}

/// `fate(domain)` = `poseidon(WORD, domain)`, and the number of draws made.
#[starknet::contract]
mod FateDouble {
    use core::poseidon::poseidon_hash_span;
    use grimworld_logic::interface::IFate;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        draws: u32,
    }

    #[abi(embed_v0)]
    impl FateImpl of IFate<ContractState> {
        fn fate(ref self: ContractState, domain: felt252) -> felt252 {
            self.draws.write(self.draws.read() + 1);
            poseidon_hash_span(array![super::WORD, domain].span())
        }
    }

    #[abi(embed_v0)]
    impl DrawsImpl of super::IDraws<ContractState> {
        fn draws(self: @ContractState) -> u32 {
            self.draws.read()
        }
    }
}

/// The last report `Instances` sent, as the hub received it.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Reported {
    pub count: u32,
    pub instance_id: u64,
    pub adventurer: u32,
    pub outcome: u8,
    pub hub: u16,
    pub facts: u32,
    pub location: u16,
    pub next: u64,
    pub belt: [u8; 4],
}

#[starknet::interface]
pub trait IReports<T> {
    fn last(self: @T) -> Reported;
}

#[starknet::contract]
mod HubDouble {
    use grimworld_logic::interface::{IResults, Results};
    use grimworld_logic::types::Outcome;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::Reported;

    #[storage]
    struct Storage {
        count: u32,
        instance_id: u64,
        adventurer: u32,
        outcome: u8,
        hub: u16,
        facts: u32,
        location: u16,
        next: u64,
        belt: felt252,
    }

    #[abi(embed_v0)]
    impl ResultsImpl of IResults<ContractState> {
        fn report(ref self: ContractState, results: Results) {
            assert(results.contributors.len() == 1, 'double: one contributor');
            assert(results.experience == 0 && results.gold == 0, 'double: no loot');
            self.count.write(self.count.read() + 1);
            self.instance_id.write(results.instance_id);
            self.adventurer.write(*results.contributors[0]);
            self
                .outcome
                .write(
                    match results.outcome {
                        Outcome::Open => 0,
                        Outcome::Returned => 1,
                        Outcome::Defeated => 2,
                        Outcome::Moved => 3,
                    },
                );
            self.hub.write(results.hub);
            self.facts.write(results.facts);
            self.location.write(results.location);
            self.next.write(results.next);
            let [a, b, c, d] = results.belt;
            self
                .belt
                .write(a.into() + b.into() * 0x100 + c.into() * 0x10000 + d.into() * 0x1000000);
        }
        fn barter(ref self: ContractState, adventurer_id: u32, collector: u16) -> bool {
            false
        }
    }

    #[abi(embed_v0)]
    impl ReportsImpl of super::IReports<ContractState> {
        fn last(self: @ContractState) -> Reported {
            let belt: u32 = self.belt.read().try_into().unwrap();
            Reported {
                count: self.count.read(),
                instance_id: self.instance_id.read(),
                adventurer: self.adventurer.read(),
                outcome: self.outcome.read(),
                hub: self.hub.read(),
                facts: self.facts.read(),
                location: self.location.read(),
                next: self.next.read(),
                belt: [
                    (belt % 0x100).try_into().unwrap(),
                    ((belt / 0x100) % 0x100).try_into().unwrap(),
                    ((belt / 0x10000) % 0x100).try_into().unwrap(),
                    (belt / 0x1000000).try_into().unwrap(),
                ],
            }
        }
    }
}

// ---- the world of these tests -------------------------------------------------------------------

pub const WORD: felt252 = 'fate word';
const ADMIN: felt252 = 0xad;
const ALICE: felt252 = 0xa11ce;
const BOB: felt252 = 0xb0b;
const HERO: u32 = 7;
const OTHER: u32 = 8;

// Locations: 1 the town, 2 the zone (entered at chunk 0, tile 105: (0, 7)), 3 and 4 the dungeon's
// floors (entered at chunk 112, tile 112: (112, 112)), 5 a sealed Red Rift floor.
const TOWN: u16 = 1;
const ZONE: u16 = 2;
const FLOOR_1: u16 = 3;
const RIFT: u16 = 5;
// Gates: 1 town → zone; 2 zone → town (hub gate, anchored on the zone's entry tile); 3 zone →
// floor 1 (anchored away from the entry); 6 zone → floor 1 anchored on the entry; 7 to 11 and 13
// the refused ones, each anchored on the entry; 12 town → the sealed Rift.
const INTO_ZONE: u16 = 1;
const ZONE_TO_TOWN: u16 = 2;
const FAR_LINK: u16 = 3;
const FLOOR_TO_ZONE: u16 = 4;
const LINK_HERE: u16 = 6;
const RANKED: u16 = 7;
const QUESTED: u16 = 8;
const FLOOR_GATE: u16 = 9;
const RIFT_GATE: u16 = 10;
const LINK_TO_TOWN: u16 = 11;
const INTO_SEALED: u16 = 12;
const TO_NOWHERE: u16 = 13;

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

#[derive(Copy, Drop)]
struct World {
    instances: ContractAddress,
    registry: ContractAddress,
    fate: ContractAddress,
    hub: ContractAddress,
}

fn location(
    kind: u8, width: u8, target: u8, sealed: bool, entry_chunk: u8, entry_tile: u8,
) -> Span<felt252> {
    LocationTrait::new(
        kind,
        1,
        1,
        1,
        3,
        0,
        width,
        width,
        target,
        0,
        0,
        0,
        sealed,
        entry_chunk,
        entry_tile,
        Lanes16 { lanes: [0; 15] },
    )
        .pack()
}

fn gate(
    source: u16,
    destination: u16,
    anchor: (u8, u8),
    entry: (u8, u8),
    kind: u8,
    rank: u8,
    quest: u32,
) -> Span<felt252> {
    let (anchor_chunk, anchor_tile) = anchor;
    let (entry_chunk, entry_tile) = entry;
    GateTrait::new(
        source, destination, anchor_chunk, anchor_tile, entry_chunk, entry_tile, kind, rank, quest,
    )
        .pack()
}

fn setup() -> World {
    let class = declare("RegistryDouble").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![]).unwrap();
    let class = declare("FateDouble").unwrap().contract_class();
    let (fate, _) = class.deploy(@array![]).unwrap();
    let class = declare("HubDouble").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![]).unwrap();
    let reveal = declare("RevealLibrary").unwrap().contract_class();
    let hosts = declare("HostsLibrary").unwrap().contract_class();
    let traps = declare("TrapLibrary").unwrap().contract_class();
    let class = declare("Instances").unwrap().contract_class();
    let (instances, _) = class
        .deploy(
            @array![
                ADMIN, hub.into(), registry.into(), fate.into(), (*reveal.class_hash).into(),
                (*hosts.class_hash).into(), (*traps.class_hash).into(),
            ],
        )
        .unwrap();

    let records = IRecordsDispatcher { contract_address: registry };
    records.set(REGION, 1, RegionTrait::new(TOWN, 0, ZONE, 'Test Region').pack());
    records.set(LOCATION, 1, location(location_kind::TOWN, 0, 0, false, 0, 0));
    records.set(LOCATION, 2, location(location_kind::ZONE, 3, 0, false, 0, 105));
    records.set(LOCATION, 3, location(location_kind::DUNGEON, 15, 6, false, 112, 112));
    records.set(LOCATION, 4, location(location_kind::DUNGEON, 15, 8, false, 112, 112));
    records.set(LOCATION, 5, location(location_kind::RIFT, 15, 6, true, 112, 112));
    let here = (0, 105);
    let centre = (112, 112);
    records.set(GATE, 1, gate(TOWN, ZONE, (0, 0), here, gate_kind::HUB, 0, 0));
    records.set(GATE, 2, gate(ZONE, TOWN, here, (0, 0), gate_kind::HUB, 0, 0));
    records.set(GATE, 3, gate(ZONE, FLOOR_1, (16, 110), centre, gate_kind::LINK, 0, 0));
    records.set(GATE, 4, gate(FLOOR_1, ZONE, centre, (16, 110), gate_kind::LINK, 0, 0));
    records.set(GATE, 5, gate(FLOOR_1, 4, (0, 0), centre, gate_kind::FLOOR, 0, 0));
    records.set(GATE, 6, gate(ZONE, FLOOR_1, here, centre, gate_kind::LINK, 0, 0));
    records.set(GATE, 7, gate(ZONE, TOWN, here, (0, 0), gate_kind::HUB, 1, 0));
    records.set(GATE, 8, gate(ZONE, FLOOR_1, here, centre, gate_kind::LINK, 0, 9));
    records.set(GATE, 9, gate(ZONE, FLOOR_1, here, centre, gate_kind::FLOOR, 0, 0));
    records.set(GATE, 10, gate(ZONE, RIFT, here, centre, gate_kind::RIFT, 0, 0));
    records.set(GATE, 11, gate(ZONE, TOWN, here, (0, 0), gate_kind::LINK, 0, 0));
    records.set(GATE, 12, gate(TOWN, RIFT, (0, 0), centre, gate_kind::HUB, 0, 0));
    records.set(GATE, 13, gate(ZONE, 9, here, centre, gate_kind::LINK, 0, 0));
    // ENG-05: into the zone at chunk 16's tile 16 (`(16, 16)`), next to its South-East corner:
    // sight touches chunks 0, 1, 15 and 16.
    records.set(GATE, 14, gate(TOWN, ZONE, (0, 0), (16, 16), gate_kind::HUB, 0, 0));
    // ENG-07: into the zone on chunk 16's tile 32 (`(17, 17)`), a floor tile of its terrain.
    records.set(GATE, 15, gate(TOWN, ZONE, (0, 0), (16, 32), gate_kind::HUB, 0, 0));
    World { instances, registry, fate, hub }
}

/// The snapshot of the tests; `create` receives its packed words (`words`, D-168).
fn snapshot() -> Snapshot {
    SnapshotTrait::new(3, 1, [11, 12, 0, 0, 0, 0, 0, 0], 255, [41, 42, 0, 0], [2, 1, 0, 0])
}

fn tasks(count: u32) -> Span<TaskEntry> {
    let mut out = array![];
    for i in 0..count {
        out.append(TaskEntry { task: 100 + i, kind: 1, param: (200 + i).try_into().unwrap() });
    }
    out.span()
}

/// `create` as the hub, for `who`'s adventurer.
fn create(world: World, adventurer: u32, who: felt252, gate: u16, count: u32) -> u64 {
    start_cheat_caller_address(world.instances, world.hub);
    IInstanceEntryDispatcher { contract_address: world.instances }
        .create(adventurer, addr(who), gate, snapshot().words(), tasks(count))
}

fn play(world: World, who: felt252) -> IInstancesDispatcher {
    start_cheat_caller_address(world.instances, addr(who));
    IInstancesDispatcher { contract_address: world.instances }
}

fn try_play(world: World, who: felt252) -> IInstancesSafeDispatcher {
    start_cheat_caller_address(world.instances, addr(who));
    IInstancesSafeDispatcher { contract_address: world.instances }
}

fn reports(world: World) -> Reported {
    IReportsDispatcher { contract_address: world.hub }.last()
}

fn draws(world: World) -> u32 {
    IDrawsDispatcher { contract_address: world.fate }.draws()
}

fn refused<T, +Drop<T>>(result: Result<T, Array<felt252>>, message: felt252) {
    match result {
        Result::Ok(_) => core::panic_with_felt252('should be refused'),
        Result::Err(data) => assert(*data.at(0) == message, *data.at(0)),
    }
}

// ---- storage keys (ENG-01 §3.2)
// -----------------------------------------------------------------

fn key(name: felt252, keys: Array<felt252>) -> felt252 {
    map_entry_address(name, keys.span())
}
fn member_word(slot: u32, word: felt252) -> felt252 {
    key(selector!("members"), array![slot.into(), 0]) + word
}
fn read(target: ContractAddress, at: felt252) -> felt252 {
    *load(target, at, 1).at(0)
}
fn write(target: ContractAddress, at: felt252, value: felt252) {
    store(target, at, array![value].span());
}

/// Every key of slot 1 and 2 an entry can reach, the two adventurers' placements, `next_slot`,
/// chunk and goblin words of the entry chunks.
fn watched() -> Array<felt252> {
    let mut keys = array![
        selector!("next_slot"), key(selector!("placements"), array![HERO.into()]),
        key(selector!("placements"), array![OTHER.into()]),
    ];
    for slot in 1..3_u32 {
        let s: felt252 = slot.into();
        keys.append(key(selector!("headers"), array![s]));
        keys.append(key(selector!("entropy"), array![s]));
        keys.append(key(selector!("revealed"), array![s]));
        keys.append(key(selector!("quotas"), array![s]));
        for page in 0..4_u8 {
            keys.append(key(selector!("tasks"), array![s, page.into()]));
            keys.append(key(selector!("roster"), array![s, page.into()]));
        }
        for word in 0..8_u8 {
            keys.append(member_word(slot, word.into()));
        }
        for chunk in array![0, 16, 112] {
            keys.append(key(selector!("chunks"), array![s, chunk]));
            keys.append(key(selector!("chunks"), array![s, chunk]) + 1);
        }
    }
    keys
}

fn values(target: ContractAddress, keys: Span<felt252>) -> Array<felt252> {
    let mut out = array![];
    for at in keys {
        out.append(read(target, *at));
    }
    out
}

/// `(new, overwritten, zeroed)` between two reads of the same keys.
fn changes(before: Span<felt252>, after: Span<felt252>) -> (u32, u32, u32) {
    let (mut new, mut old, mut zeroed) = (0_u32, 0_u32, 0_u32);
    for i in 0..before.len() {
        let (b, a) = (*before.at(i), *after.at(i));
        if b != a {
            if b == 0 {
                new += 1;
            } else if a == 0 {
                zeroed += 1;
            } else {
                old += 1;
            }
        }
    }
    (new, old, zeroed)
}

fn header_of(world: World, slot: u32) -> Header {
    StorePacking::unpack(read(world.instances, key(selector!("headers"), array![slot.into()])))
}
fn state_of(world: World, slot: u32) -> MemberState {
    StorePacking::unpack(read(world.instances, member_word(slot, 0)))
}
fn placement_of(world: World, adventurer: u32) -> Placement {
    StorePacking::unpack(
        read(world.instances, key(selector!("placements"), array![adventurer.into()])),
    )
}

// ---- create -------------------------------------------------------------------------------------

// An adventurer's first entry: a new slot, generation 1, every word of §2.1 written for clock 0,
// the entry draw under `poseidon(id, 0, ENTRY)`, then the entry reveal (ENG-05): sight from the
// entry tile (column 0, row 7 of chunk 0) touches chunk 0 alone (its East is outside the zone).
// Write set (ENG-01 §9.3, first entry, cold): the placement, header, entropy, revealed, quotas,
// the member's 8 words, ⌈16 / 4⌉ = 4 task pages and the entry chunk's 2 words new: 19;
// `next_slot` overwritten.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 41259225)] // ceil(1.05 × 39294500 measured)
fn test_create_first_entry() {
    let world = setup();
    let keys = watched();
    let before = values(world.instances, keys.span());
    let mut spy = spy_events();
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    let id = entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot().words(), tasks(16));
    println!("gas create, first entry, 16 tasks (doubles): {}", gas - get_available_gas());
    assert(id == instance_id(1, 1), 'slot 1, generation 1');
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (19, 1, 0), 'writes: 19 new, 1 overwritten');

    let header = header_of(world, 1);
    let expected = Header {
        generation: 1,
        sequence: 0,
        clock: 0,
        location: ZONE,
        status: OPEN,
        members: 1,
        tasks: 16,
        revealed_count: 1,
        roster_count: 0,
        flags: 0,
        entry_chunk: 0,
        entry_tile: 105,
        gate: INTO_ZONE,
    };
    assert(header == expected, 'header');
    let draw = domain(id.into(), 0, ENTRY);
    let entropy = read(world.instances, key(selector!("entropy"), array![1]));
    // The entry draw alone: a reveal feeds nothing (audit #348, major 1).
    assert(entropy == derive(poseidon_hash_span(array![WORD, draw].span()), draw, 0), 'entry draw');
    assert(draws(world) == 1, 'one draw');
    assert(
        read(world.instances, key(selector!("revealed"), array![1])) == LIVE + 1,
        'chunk 0 revealed',
    );
    let quotas: Quotas = StorePacking::unpack(
        read(world.instances, key(selector!("quotas"), array![1])),
    );
    assert(quotas == Quotas { target: 0, open_edges: 0, left: [0; 14] }, 'a zone: N = 0');
    assert(
        placement_of(world, HERO) == Placement { slot: 1, generation: 1, member: 0, inside: 1 },
        'placement',
    );
    assert(read(world.instances, selector!("next_slot")) == 2 + LIVE, 'next slot');

    let snap = snapshot();
    let state = state_of(world, 1);
    let entering = MemberState {
        adventurer: HERO,
        x: 0,
        y: 7,
        facing: 0,
        status: INSIDE,
        health: 140,
        energy: 60,
        adrenaline: 0,
        hits: 0,
        casts: 0,
        belt: [2, 1, 0, 0],
        flags: 0,
        casts_2: 0,
    };
    assert(state == entering, 'member state');
    assert(read(world.instances, member_word(1, 1)) == LIVE + NO_SLOT.into(), 'timers empty');
    assert(read(world.instances, member_word(1, 2)) == LIVE, 'effects empty');
    assert(read(world.instances, member_word(1, 3)) == LIVE, 'recharges empty');
    assert(read(world.instances, member_word(1, 4)) == StorePacking::pack(snap.stats), 'stats');
    assert(read(world.instances, member_word(1, 5)) == StorePacking::pack(snap.bar), 'bar');
    assert(read(world.instances, member_word(1, 6)) == StorePacking::pack(snap.kit), 'kit');
    assert(read(world.instances, member_word(1, 7)) == ALICE, 'controller');
    let page: TaskPage = StorePacking::unpack(
        read(world.instances, key(selector!("tasks"), array![1, 3])),
    );
    assert(
        page.entries == [*tasks(16)[12], *tasks(16)[13], *tasks(16)[14], *tasks(16)[15]], 'page 3',
    );

    spy
        .assert_emitted(
            @array![
                (
                    world.instances,
                    Event::InstanceEntered(
                        InstanceEntered {
                            instance_id: id, adventurer_id: HERO, location: ZONE, gate: INTO_ZONE,
                        },
                    ),
                ),
            ],
        );
    assert(
        play(world, ALICE).placement(HERO) == (id, 0, true)
            && play(world, ALICE).placement(OTHER) == (0, 0, false),
        'placement view',
    );
}

// The same with no task: no task page is written (19 − 4 = 15 new).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 36843476)] // ceil(1.05 × 35089024 measured)
fn test_create_without_tasks() {
    let world = setup();
    let keys = watched();
    let before = values(world.instances, keys.span());
    create(world, HERO, ALICE, INTO_ZONE, 0);
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (15, 1, 0), 'writes: 15 new, 1 overwritten');
    assert(header_of(world, 1).tasks == 0, 'no task');
}

// A later entry reuses the slot: generation + 1, `next_slot` untouched, every key already written
// (ENG-01 §9.3, later entry, initialised: 0 new).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 62494063)] // ceil(1.05 × 59518155 measured)
fn test_create_reuses_the_slot() {
    let world = setup();
    let first = create(world, HERO, ALICE, INTO_ZONE, 16);
    play(world, ALICE).travel_back(first, HERO, 0);
    let keys = watched();
    let before = values(world.instances, keys.span());
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    let second = entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot().words(), tasks(16));
    println!("gas create, later entry, 16 tasks (doubles): {}", gas - get_available_gas());
    assert(second == instance_id(1, 2), 'slot 1, generation 2');
    let after = values(world.instances, keys.span());
    let (new, _, zeroed) = changes(before.span(), after.span());
    assert(new == 0 && zeroed == 0, 'nothing new, nothing zeroed');
    assert(read(world.instances, selector!("next_slot")) == 2 + LIVE, 'no new slot');
    // A second adventurer takes the next slot.
    assert(create(world, OTHER, BOB, INTO_ZONE, 0) == instance_id(2, 1), 'slot 2');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 45005735)] // ceil(1.05 × 42862604 measured)
fn test_create_refusals() {
    let world = setup();
    let entry = IInstanceEntrySafeDispatcher { contract_address: world.instances };
    start_cheat_caller_address(world.instances, addr(ALICE));
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot().words(), tasks(0)), NOT_HUB);
    start_cheat_caller_address(world.instances, world.hub);
    #[feature("safe_dispatcher")]
    refused(
        entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot().words(), tasks(17)), TOO_MANY_TASKS,
    );
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), 99, snapshot().words(), tasks(0)), NO_GATE);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), TO_NOWHERE, snapshot().words(), tasks(0)), NO_LOCATION);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), ZONE_TO_TOWN, snapshot().words(), tasks(0)), NO_MAP);
    assert(draws(world) == 0, 'no draw');
    create(world, HERO, ALICE, INTO_ZONE, 0);
    #[feature("safe_dispatcher")]
    refused(
        entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot().words(), tasks(0)), ALREADY_INSIDE,
    );
}

// A sealed destination sets the header's flag (design/17).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 38326974)] // ceil(1.05 × 36501880 measured)
fn test_create_sealed() {
    let world = setup();
    create(world, HERO, ALICE, INTO_SEALED, 0);
    let header = header_of(world, 1);
    assert(header.flags == SEALED && header.location == RIFT, 'sealed rift');
    let quotas: Quotas = StorePacking::unpack(
        read(world.instances, key(selector!("quotas"), array![1])),
    );
    assert(quotas.target == 6, 'N of the floor');
}

// ---- generation isolation (AC-2, ENG-01 §2.1)
// ---------------------------------------------------

/// Stale data in every word of slot 1 that an earlier generation could have left.
fn fill_slot(world: World) {
    let junk = LIVE + 0x3fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    let s: felt252 = 1;
    write(world.instances, key(selector!("entropy"), array![s]), junk);
    write(world.instances, key(selector!("revealed"), array![s]), junk);
    write(world.instances, key(selector!("quotas"), array![s]), junk);
    for page in 0..4_u8 {
        write(world.instances, key(selector!("tasks"), array![s, page.into()]), junk);
        let full = Lanes16 {
            lanes: [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114],
        };
        write(
            world.instances,
            key(selector!("roster"), array![s, page.into()]),
            StorePacking::pack(full),
        );
    }
    let stale_timers = MemberTimers {
        act_slot: 3,
        act_target: 9,
        act_tile: 0,
        act_deadline: 70,
        bleeding: 71,
        poison: 72,
        burning: 73,
        crippled: 74,
        knocked: 75,
    };
    write(world.instances, member_word(1, 0), junk);
    write(world.instances, member_word(1, 1), StorePacking::pack(stale_timers));
    let effect = Effect { skill: 5, charges: 2, deadline: 90, ..Default::default() };
    write(
        world.instances,
        member_word(1, 2),
        StorePacking::pack(MemberEffects { effects: [effect; 4] }),
    );
    write(world.instances, member_word(1, 3), StorePacking::pack(Recharges { deadlines: [80; 8] }));
    // The snapshot's words (stats, bar, kit) and the controller: the earlier expedition's.
    write(world.instances, member_word(1, 4), junk);
    write(world.instances, member_word(1, 5), junk);
    write(world.instances, member_word(1, 6), junk);
    write(world.instances, member_word(1, 7), ALICE);
    for chunk in array![0, 16, 112] {
        write(world.instances, key(selector!("chunks"), array![s, chunk]), junk);
        write(world.instances, key(selector!("chunks"), array![s, chunk]) + 1, junk);
    }
}

// A slot another generation used, with stale data in every word: the new instance shows nothing of
// it, through the view and through the stored words its gates reach.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 59848773)] // ceil(1.05 × 56998831 measured)
fn test_generation_isolation() {
    let world = setup();
    let first = create(world, HERO, ALICE, INTO_ZONE, 16);
    play(world, ALICE).travel_back(first, HERO, 0);
    fill_slot(world);
    // The stale header says 60 goblins in the roster and 200 chunks revealed.
    let stale = Header { roster_count: 60, revealed_count: 200, ..header_of(world, 1) };
    write(world.instances, key(selector!("headers"), array![1]), StorePacking::pack(stale));

    // The reused slot is entered with another snapshot (an Arcanist of level 5, another bar,
    // another belt) and another controller (the account changed owner between expeditions).
    let other = SnapshotTrait::new(
        5, 3, [21, 22, 23, 24, 25, 26, 27, 28], 1, [51, 52, 53, 54], [4, 3, 2, 1],
    );
    start_cheat_caller_address(world.instances, world.hub);
    let second = IInstanceEntryDispatcher { contract_address: world.instances }
        .create(HERO, addr(BOB), INTO_ZONE, other.words(), tasks(1));
    let view = play(world, BOB).instance_state(second);
    let header = header_of(world, 1);
    assert(header.generation == 2 && header.roster_count == 0, 'roster count reset');
    assert(header.revealed_count == 1 && header.tasks == 1, 'counts reset, entry revealed');
    assert(view.revealed == LIVE + 1, 'only the entry chunk');
    let quotas: Quotas = StorePacking::unpack(view.quotas);
    assert(quotas == Quotas { target: 0, open_edges: 0, left: [0; 14] }, 'quotas fresh');
    assert(
        view.entropy != LIVE + 0x3fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        'entropy fresh',
    );
    assert(view.tasks.len() == 1, 'one task page');
    let page: TaskPage = StorePacking::unpack(*view.tasks[0]);
    assert(
        page.entries == [*tasks(1)[0], Default::default(), Default::default(), Default::default()],
        'task page rewritten',
    );
    assert(view.roster.len() == 0, 'no roster page');
    assert(view.goblins.len() == 0 && view.chunks.len() == 0, 'no chunk, no goblin');
    // Every one of the member's eight words is the new generation's.
    let entering = MemberState {
        adventurer: HERO,
        x: 0,
        y: 7,
        facing: 0,
        status: INSIDE,
        health: 180,
        energy: 90,
        adrenaline: 0,
        hits: 0,
        casts: 0,
        belt: [4, 3, 2, 1],
        flags: 0,
        casts_2: 0,
    };
    let expected: Array<felt252> = array![
        StorePacking::pack(entering), StorePacking::pack(MemberTimersTrait::empty()), LIVE, LIVE,
        StorePacking::pack(other.stats), StorePacking::pack(other.bar),
        StorePacking::pack(other.kit), BOB,
    ];
    assert(view.members == expected.span(), 'eight words, new generation');
    for word in 0..8_u8 {
        assert(
            read(world.instances, member_word(1, word.into())) == *expected[word.into()], 'stored',
        );
    }

    // The roster through the masked read: ENG-07 appends one goblin; the view shows that entry
    // and zeros in the fourteen lanes the earlier generation left full.
    let one = Header { roster_count: 1, ..header };
    write(world.instances, key(selector!("headers"), array![1]), StorePacking::pack(one));
    let full = Lanes16 {
        lanes: [120, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114],
    };
    write(world.instances, key(selector!("roster"), array![1, 0]), StorePacking::pack(full));
    let view = play(world, ALICE).instance_state(second);
    assert(view.roster.len() == 1, 'one roster page');
    let mut lanes = array![120_u16];
    for _ in 1..15_u8 {
        lanes.append(0);
    }
    let masked: Lanes16 = StorePacking::unpack(*view.roster[0]);
    assert(masked.lanes.span() == lanes.span(), 'masked lanes');

    // The earlier generation's id answers nothing.
    let old = play(world, ALICE).instance_state(first);
    let empty = InstanceView {
        instance_id: first,
        header: 0,
        entropy: 0,
        revealed: 0,
        quotas: 0,
        tasks: array![].span(),
        members: array![].span(),
        roster: array![].span(),
        goblins: array![].span(),
        chunks: array![].span(),
    };
    assert(old == empty, 'old id: nothing');
    assert(
        play(world, ALICE).instance_state(0) == InstanceView { instance_id: 0, ..empty }, 'id 0',
    );

    // The earlier expedition's controller cannot act in the new generation; the new one can.
    #[feature("safe_dispatcher")]
    refused(try_play(world, ALICE).travel_back(second, HERO, 0), NOT_CONTROLLER);
    #[feature("safe_dispatcher")]
    refused(try_play(world, ALICE).leave(second, HERO, 0, ZONE_TO_TOWN), NOT_CONTROLLER);
    play(world, BOB).travel_back(second, HERO, 0);
    let report = reports(world);
    assert(report.instance_id == second && report.outcome == 1, 'the new controller acts');
    assert(report.belt == [4, 3, 2, 1], 'the new belt');
}

// ---- leave, travel back -------------------------------------------------------------------------

// Through the zone's hub gate, on its anchor (the entry tile): Returned, the town reached and
// unlocked, the belt's counts reported (ENG-01 §9.3: header, member state, placement: 0 new, 3
// overwritten; `InstanceClosed`; one report).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 42832151)] // ceil(1.05 × 40792524 measured)
fn test_leave_to_a_hub() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    let keys = watched();
    let before = values(world.instances, keys.span());
    let mut spy = spy_events();
    let instances = play(world, ALICE);
    let gas = get_available_gas();
    assert(instances.leave(id, HERO, 0, ZONE_TO_TOWN) == 0, 'no next instance');
    println!("gas leave to a hub (doubles): {}", gas - get_available_gas());
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (0, 3, 0), 'writes: 3 overwritten');
    assert(header_of(world, 1).status == RETURNED, 'returned');
    assert(state_of(world, 1).status == GONE, 'member gone');
    assert(placement_of(world, HERO).inside == 0, 'not inside');
    let expected = Reported {
        count: 1,
        instance_id: id,
        adventurer: HERO,
        outcome: 1,
        hub: TOWN,
        facts: facts::HUB_REACHED,
        location: TOWN,
        next: 0,
        belt: [2, 1, 0, 0],
    };
    assert(reports(world) == expected, 'report');
    spy
        .assert_emitted(
            @array![
                (
                    world.instances,
                    Event::InstanceClosed(
                        InstanceClosed { instance_id: id, outcome: Outcome::Returned },
                    ),
                ),
            ],
        );
    assert(draws(world) == 1, 'no draw at a hub gate');
}

// Through a link to the dungeon's first floor: this instance closes (Moved) and the next enters in
// the same slot, generation 2, in the same invocation, with its entry draw. Nothing of the member
// carries but the belt's reserve (D-141, E-20; E-13's F-12 case): its conditions, effects,
// recharges and activation, set before leaving, are gone. Write set (ENG-01 §9.3, moved): header,
// entropy, revealed, quotas, the 4 transient member words, the placement: 9 overwritten; and the
// entry reveal (ENG-05): floor 1's entry chunk 112, its 2 words new in this slot.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 65659249)] // ceil(1.05 × 62532618 measured)
fn test_leave_to_a_location() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 5);
    let busy = MemberTimers {
        act_slot: 2,
        act_target: 30,
        act_tile: 0,
        act_deadline: 9,
        bleeding: 11,
        poison: 12,
        burning: 13,
        crippled: 14,
        knocked: 15,
    };
    write(world.instances, member_word(1, 1), StorePacking::pack(busy));
    let effect = Effect { skill: 4, charges: 1, deadline: 20, ..Default::default() };
    write(
        world.instances,
        member_word(1, 2),
        StorePacking::pack(MemberEffects { effects: [effect; 4] }),
    );
    write(world.instances, member_word(1, 3), StorePacking::pack(Recharges { deadlines: [25; 8] }));
    // Half the health gone, a potion drunk, adrenaline built: none of it carries but the belt.
    let hurt = MemberState {
        health: 70, energy: 10, adrenaline: 8, belt: [1, 1, 0, 0], hits: 3, ..state_of(world, 1),
    };
    write(world.instances, member_word(1, 0), StorePacking::pack(hurt));
    let header = Header { sequence: 12, clock: 40, ..header_of(world, 1) };
    write(world.instances, key(selector!("headers"), array![1]), StorePacking::pack(header));

    let keys = watched();
    let before = values(world.instances, keys.span());
    let mut spy = spy_events();
    let instances = play(world, ALICE);
    let gas = get_available_gas();
    let next = instances.leave(id, HERO, 12, LINK_HERE);
    println!("gas leave to a location (doubles): {}", gas - get_available_gas());
    assert(next == instance_id(1, 2), 'next: slot 1, generation 2');
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (2, 9, 0), 'writes: 2 new, 9 changed');
    assert(header_of(world, 1).revealed_count == 1, 'the entry chunk revealed');
    assert(
        read(world.instances, key(selector!("revealed"), array![1])) == LIVE
            + 0x10000000000000000000000000000,
        'chunk 112 alone',
    );

    let header = header_of(world, 1);
    assert(header.generation == 2 && header.location == FLOOR_1 && header.status == OPEN, 'next');
    assert(header.sequence == 0 && header.clock == 0 && header.tasks == 5, 'clock 0, tasks kept');
    assert(header.gate == LINK_HERE && header.entry_chunk == 112, 'entered by the link');
    let state = state_of(world, 1);
    assert(state.x == 112 && state.y == 112, 'on the entry tile');
    assert(state.health == 140 && state.energy == 60 && state.adrenaline == 0, 'restored');
    assert(state.belt == [1, 1, 0, 0] && state.hits == 0, 'only the belt carries');
    assert(read(world.instances, member_word(1, 1)) == LIVE + NO_SLOT.into(), 'timers reset');
    assert(read(world.instances, member_word(1, 2)) == LIVE, 'effects reset');
    assert(read(world.instances, member_word(1, 3)) == LIVE, 'recharges reset');
    let quotas: Quotas = StorePacking::unpack(
        read(world.instances, key(selector!("quotas"), array![1])),
    );
    assert(quotas.target == 6, 'N of floor 1');
    assert(
        placement_of(world, HERO) == Placement { slot: 1, generation: 2, member: 0, inside: 1 },
        'placement',
    );
    let draw = domain(next.into(), 0, ENTRY);
    let entropy = read(world.instances, key(selector!("entropy"), array![1]));
    assert(entropy == derive(poseidon_hash_span(array![WORD, draw].span()), draw, 0), 'entry draw');
    assert(draws(world) == 2, 'one more draw');
    let expected = Reported {
        count: 1,
        instance_id: id,
        adventurer: HERO,
        outcome: 3,
        hub: 0,
        facts: 0,
        location: 0,
        next,
        belt: [0; 4],
    };
    assert(reports(world) == expected, 'report: moved');
    spy
        .assert_emitted(
            @array![
                (
                    world.instances,
                    Event::InstanceClosed(
                        InstanceClosed { instance_id: id, outcome: Outcome::Moved },
                    ),
                ),
                (
                    world.instances,
                    Event::InstanceEntered(
                        InstanceEntered {
                            instance_id: next,
                            adventurer_id: HERO,
                            location: FLOOR_1,
                            gate: LINK_HERE,
                        },
                    ),
                ),
            ],
        );
    // The next instance goes on: back to the zone through the floor's entrance, then home.
    let back = play(world, ALICE).leave(next, HERO, 0, FLOOR_TO_ZONE);
    assert(back == instance_id(1, 3), 'generation 3');
    let state = state_of(world, 1);
    // Chunk 16 is (1, 1); tile 110 is row 7, column 5.
    assert(state.x == 20 && state.y == 22, 'at the far link');
    play(world, ALICE).travel_back(back, HERO, 0);
    assert(reports(world).outcome == 1, 'returned');
}

// Travel back: Returned to the last hub (the hub settles `hub` 0 as its last one, D-04).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 41035604)] // ceil(1.05 × 39081527 measured)
fn test_travel_back() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    let keys = watched();
    let before = values(world.instances, keys.span());
    let instances = play(world, ALICE);
    let gas = get_available_gas();
    instances.travel_back(id, HERO, 0);
    println!("gas travel_back (doubles): {}", gas - get_available_gas());
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (0, 3, 0), 'writes: 3 overwritten');
    let expected = Reported {
        count: 1,
        instance_id: id,
        adventurer: HERO,
        outcome: 1,
        hub: 0,
        facts: 0,
        location: 0,
        next: 0,
        belt: [2, 1, 0, 0],
    };
    assert(reports(world) == expected, 'report: last hub');
    assert(header_of(world, 1).status == RETURNED, 'returned');
}

/// A refusal: `Refused` with `reason`, nothing changed, nothing drawn, nothing reported.
fn assert_refused(world: World, id: u64, from: u32, sequence: u32, reason: Refusal, gate: u16) {
    let keys = watched();
    let before = values(world.instances, keys.span());
    let (drawn, reported) = (draws(world), reports(world).count);
    let mut spy = spy_events();
    if gate == 0 {
        play(world, ALICE).travel_back(id, HERO, from);
    } else {
        assert(play(world, ALICE).leave(id, HERO, from, gate) == 0, 'refused: 0');
    }
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (0, 0, 0), 'nothing changed');
    assert(draws(world) == drawn && reports(world).count == reported, 'no draw, no report');
    spy
        .assert_emitted(
            @array![
                (
                    world.instances,
                    Event::Refused(
                        Refused { instance_id: id, adventurer_id: HERO, from, sequence, reason },
                    ),
                ),
            ],
        );
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 42686589)] // ceil(1.05 × 40653894 measured)
fn test_refused_sequence() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    let instances = play(world, ALICE);
    let gas = get_available_gas();
    instances.leave(id, HERO, 5, ZONE_TO_TOWN);
    println!("gas leave refused on the sequence: {}", gas - get_available_gas());
    assert_refused(world, id, 1, 0, Refusal::Sequence, ZONE_TO_TOWN);
    assert_refused(world, id, 3, 0, Refusal::Sequence, 0);
}

// An id of an earlier generation, and an instance already closed.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 51735549)] // ceil(1.05 × 49271951 measured)
fn test_refused_closed() {
    let world = setup();
    let first = create(world, HERO, ALICE, INTO_ZONE, 0);
    play(world, ALICE).travel_back(first, HERO, 0);
    assert_refused(world, first, 0, 0, Refusal::Closed, ZONE_TO_TOWN);
    let second = create(world, HERO, ALICE, INTO_ZONE, 0);
    assert_refused(world, first, 0, 0, Refusal::Closed, 0);
    assert(second != first, 'another generation');
}

// The adventurer is not in that instance (another's, in another slot), or is down.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 54576216)] // ceil(1.05 × 51977348 measured)
fn test_refused_absent() {
    let world = setup();
    create(world, HERO, ALICE, INTO_ZONE, 0);
    let theirs = create(world, OTHER, BOB, INTO_ZONE, 0);
    // Alice controls HERO, not OTHER: naming OTHER's instance with HERO is absent.
    assert_refused(world, theirs, 0, 0, Refusal::Absent, ZONE_TO_TOWN);
    let down = MemberState { status: 1, ..state_of(world, 1) };
    write(world.instances, member_word(1, 0), StorePacking::pack(down));
    assert_refused(world, instance_id(1, 1), 0, 0, Refusal::Absent, 0);
}

// Every gate that cannot be taken from where the member stands (design/02: "the gate is
// reachable"), before any draw.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 70621356)] // ceil(1.05 × 67258434 measured)
fn test_refused_gate() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    // No such gate; a gate of another location (the town's); off its anchor; a floor gate (a
    // dungeon's exit is a quota object, ENG-05); a Rift gate; a rank; a quest; a link into a
    // town; a link to a location the registry does not hold.
    for gate in array![
        99, INTO_ZONE, FAR_LINK, FLOOR_GATE, RIFT_GATE, RANKED, QUESTED, LINK_TO_TOWN, TO_NOWHERE,
    ] {
        assert_refused(world, id, 0, 0, Refusal::Gate, gate);
    }
}

// A sealed Red Rift: no travel back (design/17).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 41874455)] // ceil(1.05 × 39880433 measured)
fn test_refused_sealed() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_SEALED, 0);
    assert_refused(world, id, 0, 0, Refusal::Sealed, 0);
}

// Only the member's controller acts (M-6): a revert, not a refusal of the game.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 37620980)] // ceil(1.05 × 35829504 measured)
fn test_not_controller() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    #[feature("safe_dispatcher")]
    refused(try_play(world, BOB).leave(id, HERO, 0, ZONE_TO_TOWN), NOT_CONTROLLER);
    #[feature("safe_dispatcher")]
    refused(try_play(world, BOB).travel_back(id, HERO, 0), NOT_CONTROLLER);
    // An adventurer that never entered has no controller.
    #[feature("safe_dispatcher")]
    refused(try_play(world, BOB).travel_back(id, 99, 0), NOT_CONTROLLER);
}

// ---- set_controller -----------------------------------------------------------------------------

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 42596054)] // ceil(1.05 × 40567670 measured)
fn test_set_controller() {
    let world = setup();
    let entry = IInstanceEntrySafeDispatcher { contract_address: world.instances };
    start_cheat_caller_address(world.instances, world.hub);
    #[feature("safe_dispatcher")]
    refused(entry.set_controller(HERO, addr(BOB)), NOT_INSIDE);
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    start_cheat_caller_address(world.instances, addr(ALICE));
    #[feature("safe_dispatcher")]
    refused(entry.set_controller(HERO, addr(BOB)), NOT_HUB);

    let keys = watched();
    let before = values(world.instances, keys.span());
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    entry.set_controller(HERO, addr(BOB));
    println!("gas set_controller: {}", gas - get_available_gas());
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'one word');
    assert(read(world.instances, member_word(1, 7)) == BOB, 'controller');
    #[feature("safe_dispatcher")]
    refused(try_play(world, ALICE).travel_back(id, HERO, 0), NOT_CONTROLLER);
    play(world, BOB).travel_back(id, HERO, 0);
    assert(reports(world).outcome == 1, 'the new owner plays');
}

// ---- the entry reveal (ENG-05)
// --------------------------------------------------------------------

/// The zone with its content: its chunk set (0, 1, 2, 15, 16), chunk 16's tile mask (rows 0–9,
/// then columns 0–9), the collector's quota, a spawn table of one template.
fn zone_content(world: World) -> felt252 {
    let records = IRecordsDispatcher { contract_address: world.registry };
    let zone = LocationTrait::new(
        location_kind::ZONE,
        1,
        1,
        1,
        3,
        0,
        3,
        2,
        0,
        0,
        0,
        1,
        false,
        0,
        105,
        Lanes16 { lanes: [0; 15] },
    );
    records.set(LOCATION, ZONE.into(), zone.pack());
    records
        .set(
            OUTLINE,
            OutlineTrait::id(ZONE, CHUNK_SET),
            OutlineRecord::pack(@OutlineTrait::new(0x18007, 0)),
        );
    let mask = OutlineTrait::new(0xffffffffffffffffffffffffffffffff, 0xffc1ff83ff07fe0ffffffff);
    records.set(OUTLINE, OutlineTrait::id(ZONE, 16), OutlineRecord::pack(@mask));
    records.set(QUOTAS, ZONE.into(), QuotaSetRecord::pack(@camp()));
    records.set(SPAWN_TABLE, 1, SpawnTableRecord::pack(@table()));
    records.set(PACK, 1, PackRecord::pack(@template()));
    mask.low.into() + mask.high.into() * 0x100000000000000000000000000000000
}

fn camp() -> QuotaSet {
    QuotaSet {
        quotas: [
            Quota { kind: quota_kind::COLLECTOR, param: 1, count: 1 }, Default::default(),
            Default::default(), Default::default(), Default::default(), Default::default(),
        ],
    }
}

fn table() -> SpawnTable {
    SpawnTable {
        spawns: [
            Spawn { template: 1, weight: 1 }, Default::default(), Default::default(),
            Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        density: 200,
    }
}

fn template() -> Pack {
    Pack {
        castes: [
            PackCaste { caste: 1, min: 1, max: 2 }, PackCaste { caste: 2, min: 1, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    }
}

// `create` reveals every chunk sight touches from the entry tile (Open question 3): entering the
// zone through the floor's link, on chunk 16's tile 110 (`(20, 22)`), sight touches chunk 16 and
// chunk 15. The words stored are the engine's, called directly on the same content (`Instances`
// reads it as `RevealTrait` expects); the header counts 2; no `ChunkRevealed` (ENG-01 §5, Open
// question 6); `instance_region` tells void, not yet revealed and revealed apart.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 54812808)] // ceil(1.05 × 52202674 measured)
fn test_entry_reveal_through_the_engine() {
    let world = setup();
    let mask = zone_content(world);
    let mut spy = spy_events();
    start_cheat_caller_address(world.instances, world.hub);
    let id = IInstanceEntryDispatcher { contract_address: world.instances }
        .create(HERO, addr(ALICE), FLOOR_TO_ZONE, snapshot().words(), tasks(3));
    // The engine on the same content, the zone's hosts above the masks (D-208).
    let mut site = Site {
        target: 0,
        biome: 1,
        level_min: 1,
        level_max: 3,
        width: 3,
        height: 2,
        entry_chunk: 16,
        chunk_set: 0x18007,
        west: 0,
        north: 0,
        masks: array![(16, mask), (15, 0)].span(),
        anchors: array![(16, 110)].span(),
        quotas: camp(),
        tasks: tasks(3),
        spawn: table(),
        packs: array![(1, template())].span(),
        pieces: array![].span(),
    };
    let draw = domain(id.into(), 0, ENTRY);
    let entropy = derive(poseidon_hash_span(array![WORD, draw].span()), draw, 0);
    let mut progress = ProgressTrait::new(@site, entropy);
    let (low, high) = QuotaPlacementTrait::plan(@site, progress.left.span());
    let hosts = QuotaPlacementTrait::hosts(
        site.chunk_set,
        site.width,
        site.height,
        (low, high),
        site.pieces,
        EntropyTrait::hosts(entropy, id.into()),
    );
    site
        .masks =
            array![
                (16, QuotaPlacementTrait::with_hosts(mask, hosts.span(), 16)),
                (15, QuotaPlacementTrait::with_hosts(0, hosts.span(), 15)),
            ]
        .span();
    let mut quota: felt252 = 0;
    let mut stored: u8 = 0;
    for host in hosts.span() {
        assert(read(world.instances, key(selector!("hosts"), array![1, quota])) == *host, 'hosts');
        if *host != 0 {
            stored += 1;
        }
        quota += 1;
    }
    assert(stored != 0, 'a quota hosted');
    let revealed = RevealTrait::reveal(
        @site, ref progress, id.into(), array![].span(), array![16, 15].span(),
    );
    assert(revealed.len() == 2, 'two chunks');
    for chunk in revealed.span() {
        let at = key(selector!("chunks"), array![1, (*chunk.chunk).into()]);
        assert(read(world.instances, at) == StorePacking::pack(*chunk.terrain), 'terrain');
        assert(read(world.instances, at + 1) == StorePacking::pack(*chunk.features), 'features');
    }
    let header = header_of(world, 1);
    assert(header.revealed_count == 2 && header.entry_chunk == 16, 'two revealed');
    let view = play(world, ALICE).instance_state(id);
    assert(view.revealed == LIVE + progress.revealed, 'revealed set');
    assert(view.entropy == progress.entropy, 'entropy fed');
    let quotas: Quotas = StorePacking::unpack(view.quotas);
    assert(quotas.left == progress.left, 'quotas');
    // `InstanceEntered` alone.
    let events = spy.get_events().emitted_by(world.instances);
    assert(events.events.len() == 1, 'no ChunkRevealed');
    // The views: chunks 0–15, then 16–31.
    let region = play(world, ALICE).instance_region(id, 0, 16);
    assert(region.len() == 16, 'a page');
    assert(
        *region[0].kind == ChunkKind::Unrevealed && *region[2].kind == ChunkKind::Unrevealed,
        'in the set',
    );
    assert(*region[3].kind == ChunkKind::Void && *region[14].kind == ChunkKind::Void, 'beyond');
    assert(*region[15].kind == ChunkKind::Revealed, 'chunk 15');
    assert(*region[0].terrain == 0 && *region[0].features == 0, 'unrevealed: no word');
    let region = play(world, ALICE).instance_region(id, 16, 16);
    assert(*region[0].kind == ChunkKind::Revealed, 'chunk 16');
    assert(
        *region[0].terrain == read(world.instances, key(selector!("chunks"), array![1, 16])),
        'its words',
    );
    assert(*region[1].kind == ChunkKind::Void, 'outside the outline');
    // A stale id answers nothing.
    assert(play(world, ALICE).instance_region(id + 1, 0, 16).len() == 0, 'stale');
}

// `instance_region` refuses a page above 16 (`REGION_PAGE`).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 35073764)] // ceil(1.05 × 33403584 measured)
#[feature("safe_dispatcher")]
fn test_region_page_bound() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_ZONE, 0);
    refused(try_play(world, ALICE).instance_region(id, 0, 17), 'region: page above 16');
}

/// The dungeon floor's quotas of the tests below: an exit, a Heart (template 1), a vein.
fn floor_quotas() -> QuotaSet {
    QuotaSet {
        quotas: [
            Quota { kind: quota_kind::EXIT, param: 5, count: 1 },
            Quota { kind: quota_kind::HEART, param: 1, count: 1 },
            Quota { kind: quota_kind::VEIN, param: 0, count: 1 }, Default::default(),
            Default::default(), Default::default(),
        ],
    }
}

/// The chunks of `set`, by index.
fn chunks_of(set: felt252) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let count = BoardTrait::count(set);
    let mut i: u8 = 0;
    while i != count {
        out.append(BoardTrait::nth(set, i));
        i += 1;
    }
    out
}

/// Reveals `order` from `progress` one chunk a call on `site`, every revealed chunk known
/// (`known` holds those revealed before): the chunks' terrains and features, a sum of hashes (a
/// set), the exit's chunk and the progress after.
fn reveal_rest(
    site: @Site, progress: Progress, id: felt252, known: Span<(u8, Terrain)>, order: Span<u8>,
) -> (felt252, u8, Progress) {
    let mut progress = progress;
    let mut terrains: Array<(u8, Terrain)> = array![];
    for entry in known {
        terrains.append(*entry);
    }
    let mut words: felt252 = 0;
    let mut exit: u8 = 255;
    for chunk in order {
        let out = RevealTrait::reveal(
            site, ref progress, id, terrains.span(), array![*chunk].span(),
        );
        for r in out {
            terrains.append((r.chunk, r.terrain));
            words +=
                poseidon_hash_span(
                    [r.chunk.into(), StorePacking::pack(r.terrain), StorePacking::pack(r.features)]
                        .span(),
                );
            for item in r.features.objects.span() {
                if *item.kind == object::EXIT {
                    exit = r.chunk;
                }
            }
        }
    }
    (words, exit, progress)
}

// ENG-10b (acceptance A2): a dungeon floor entered (`create` through the zone's link): `begin`
// draws its outline and hosts once (`HostsLibrary::floor`) and stores them; they equal the pure
// draw from its entry draw (`OutlineTrait::draw` from `EntropyTrait::outline`, `PlacementTrait::
// hosts` over its layers from `EntropyTrait::hosts`). The entry chunk alone is revealed, the open
// edges 0; the views tell the outline's chunks (not yet revealed) from the void around them. The
// engine on the stored state then reveals the rest in two orders, by index and backward: the same
// words in every chunk, one exit, on a chunk of the farthest layer.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 77290398)] // ceil(1.05 × 73609902 measured)
fn test_entry_reveal_of_a_dungeon() {
    let world = setup();
    let records = IRecordsDispatcher { contract_address: world.registry };
    records.set(QUOTAS, FLOOR_1.into(), QuotaSetRecord::pack(@floor_quotas()));
    records.set(PACK, 1, PackRecord::pack(@template()));
    let id = create(world, HERO, ALICE, FAR_LINK, 0);
    let draw = domain(id.into(), 0, ENTRY);
    let entropy = derive(poseidon_hash_span(array![WORD, draw].span()), draw, 0);
    // [Check] The stored outline: the pure draw
    let outline = FloorTrait::draw(112, 6, 15, 15, EntropyTrait::outline(entropy, id.into()));
    assert(
        read(world.instances, key(selector!("outline"), array![1, 0])) == outline.chunks,
        'outline: its chunks',
    );
    assert(
        read(world.instances, key(selector!("outline"), array![1, 1])) == outline.west,
        'outline: its West seams',
    );
    assert(
        read(world.instances, key(selector!("outline"), array![1, 2])) == outline.north,
        'outline: its North seams',
    );
    // [Check] The stored hosts: the pure draw, the exit and the Heart among the farthest chunks
    let mut site = Site {
        target: 6,
        biome: 1,
        level_min: 1,
        level_max: 3,
        width: 15,
        height: 15,
        entry_chunk: 112,
        chunk_set: outline.chunks,
        west: outline.west,
        north: outline.north,
        masks: array![].span(),
        anchors: array![(112, 112)].span(),
        quotas: floor_quotas(),
        tasks: tasks(0),
        spawn: SpawnTable { spawns: [Default::default(); 7], density: 0 },
        packs: array![(1, template())].span(),
        pieces: array![].span(),
    };
    let progress = ProgressTrait::new(@site, entropy);
    let hosts = QuotaPlacementTrait::floor_hosts(
        outline.chunks,
        QuotaPlacementTrait::plan(@site, progress.left.span()),
        site.pieces,
        EntropyTrait::hosts(entropy, id.into()),
        outline.layers(112).span(),
    );
    let (far, _) = outline.far(112);
    let mut quota: felt252 = 0;
    for host in hosts.span() {
        assert(read(world.instances, key(selector!("hosts"), array![1, quota])) == *host, 'hosts');
        quota += 1;
    }
    assert(BoardTrait::and(*hosts[0], far) == *hosts[0] && *hosts[0] != 0, 'the exit far');
    assert(BoardTrait::and(*hosts[1], far) == *hosts[1] && *hosts[1] != 0, 'the Heart far');
    // [Check] The entry chunk alone, as the engine reveals it on the stored state
    let mut masks: Array<(u8, felt252)> = array![];
    for chunk in chunks_of(outline.chunks) {
        masks.append((chunk, QuotaPlacementTrait::with_hosts(0, hosts.span(), chunk)));
    }
    site.masks = masks.span();
    let mut entry = ProgressTrait::new(@site, entropy);
    let first = RevealTrait::reveal(
        @site, ref entry, id.into(), array![].span(), array![112].span(),
    );
    let terrain: Terrain = StorePacking::unpack(
        read(world.instances, key(selector!("chunks"), array![1, 112])),
    );
    assert(first.len() == 1 && *first[0].terrain == terrain, 'the entry chunk');
    let header = header_of(world, 1);
    assert(header.revealed_count == 1, 'the entry chunk alone');
    let quotas: Quotas = StorePacking::unpack(
        read(world.instances, key(selector!("quotas"), array![1])),
    );
    assert(quotas.target == 6 && quotas.open_edges == 0, 'N, no open edges');
    assert(quotas.left == entry.left, 'quotas left');
    // [Check] The views: the outline's chunks not revealed, the others void
    let region = play(world, ALICE).instance_region(id, 96, 16);
    let mut i: u8 = 0;
    for chunk in region {
        let index = 96 + i;
        let expected = if index == 112 {
            ChunkKind::Revealed
        } else if BoardTrait::has(outline.chunks, index) {
            ChunkKind::Unrevealed
        } else {
            ChunkKind::Void
        };
        assert(*chunk.kind == expected, 'the outline in the views');
        i += 1;
    }
    // [Check] The rest in two orders: the same words, one exit at the farthest
    let mut rest: Array<u8> = array![];
    for chunk in chunks_of(outline.chunks) {
        if chunk != 112 {
            rest.append(chunk);
        }
    }
    let mut backward: Array<u8> = array![];
    let mut k = rest.len();
    while k != 0 {
        k -= 1;
        backward.append(*rest[k]);
    }
    let known = array![(112, terrain)];
    let (words, exit, after) = reveal_rest(@site, entry, id.into(), known.span(), rest.span());
    let (again, exit_again, _) = reveal_rest(
        @site, entry, id.into(), known.span(), backward.span(),
    );
    assert(words == again && exit == exit_again, 'the same in both orders');
    assert(BoardTrait::has(far, exit), 'one exit at the farthest');
    assert(after.revealed == outline.chunks && after.left == [0; 14], 'the floor whole');
}

// The entry that creates a floor (D-144; ENG-10b, A7): `create` into floor 1 with its quotas (the
// outline, the hosts, the three outline slots and the hosts written, the entry chunk revealed), to
// read next to `test_cost_create_reveals`' zone entries (the node's figures: `lifecycle_probe.py`).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 42393805)] // ceil(1.05 × 40375052 measured)
fn test_cost_create_floor() {
    let world = setup();
    let records = IRecordsDispatcher { contract_address: world.registry };
    records.set(QUOTAS, FLOOR_1.into(), QuotaSetRecord::pack(@floor_quotas()));
    records.set(PACK, 1, PackRecord::pack(@template()));
    start_cheat_caller_address(world.instances, world.hub);
    let gas = get_available_gas();
    IInstanceEntryDispatcher { contract_address: world.instances }
        .create(HERO, addr(ALICE), FAR_LINK, snapshot().words(), tasks(0));
    let spent = gas - get_available_gas();
    assert(header_of(world, 1).revealed_count == 1, 'the entry chunk');
    println!("gas create, a dungeon floor of 6 with an exit, a Heart and a vein: {}", spent);
}

// The entry reveal as the invocation's difference (ENG-05 *Budget lines*): `create` into the zone
// revealing 1 chunk (the entry tile on column 0), 2 (the floor's link, chunk 16's tile 110) and 4
// (chunk 16's tile 16, next to a corner), each the adventurer's first entry (cold: every chunk's
// two words new); `create` revealing 1 a later entry (the slot's words overwritten).
fn create_gas(gate: u16, chunks: u8) -> u128 {
    let world = setup();
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    entry.create(HERO, addr(ALICE), gate, snapshot().words(), tasks(0));
    let spent = gas - get_available_gas();
    assert(header_of(world, 1).revealed_count == chunks, 'chunks revealed');
    spent
}

/// `create` into the test zone (2 chunks revealed), its content as `zone_content` writes it, with
/// the camp's quota or with none: `begin`'s zone block (the plan, `HostsLibrary`'s call, the hosts
/// written) runs only with a quota (D-210).
fn create_gas_zone(quotas: bool) -> u128 {
    let world = setup();
    zone_content(world);
    if !quotas {
        let none = QuotaSet { quotas: [Default::default(); 6] };
        IRecordsDispatcher { contract_address: world.registry }
            .set(QUOTAS, ZONE.into(), QuotaSetRecord::pack(@none));
    }
    start_cheat_caller_address(world.instances, world.hub);
    let gas = get_available_gas();
    IInstanceEntryDispatcher { contract_address: world.instances }
        .create(HERO, addr(ALICE), FLOOR_TO_ZONE, snapshot().words(), tasks(0));
    let spent = gas - get_available_gas();
    // The hosts written with a quota, none without (the review t-0078, note 3)
    let mut written: u8 = 0;
    let mut quota: felt252 = 0;
    while quota != 14 {
        if read(world.instances, key(selector!("hosts"), array![1, quota])) != 0 {
            written += 1;
        }
        quota += 1;
    }
    assert(written == if quotas {
        1
    } else {
        0
    }, 'hosts written with a quota only');
    spent
}

// D-210 (review note 5 at 46d7d89): `begin`'s cost with and without the zone block, on the same
// zone; the difference also holds the collector's placement when a host is revealed.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 88024779)] // ceil(1.05 × 83833122 measured)
fn test_cost_create_zone_block() {
    println!("gas create, zone with a quota (the zone block): {}", create_gas_zone(true));
    println!("gas create, zone without a quota (no zone block): {}", create_gas_zone(false));
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 116237132)] // ceil(1.05 × 110702030 measured)
fn test_cost_create_reveals() {
    println!("gas create revealing 1 chunk: {}", create_gas(INTO_ZONE, 1));
    println!("gas create revealing 2 chunks: {}", create_gas(FLOOR_TO_ZONE, 2));
    println!("gas create revealing 4 chunks: {}", create_gas(14, 4));
}

// ---- ENG-07: `play` (D-233 to D-236) ------------------------------------------------------------
// `Instances.play` calls `PlayLibrary` in its context; the segment runs in `SegmentLibrary`, a tick
// with a fight in `TickLibrary`. The member's bar skills (11, 12) and belt potions (41, 42) are
// registered so that its load finds them.

fn play_classes(world: World) {
    let classes: Array<starknet::ClassHash> = array![
        *declare("PlayLibrary").unwrap().contract_class().class_hash,
        *declare("TickLibrary").unwrap().contract_class().class_hash,
        *declare("AiLibrary").unwrap().contract_class().class_hash,
        *declare("ActionLibrary").unwrap().contract_class().class_hash,
        *declare("ExecutorLibrary").unwrap().contract_class().class_hash,
        *declare("SegmentLibrary").unwrap().contract_class().class_hash,
    ];
    start_cheat_caller_address(world.instances, addr(ADMIN));
    let admin = grimworld_ephemeral::systems::instances::IInstancesAdminDispatcher {
        contract_address: world.instances,
    };
    let mut key: u8 = 0;
    for class in classes {
        grimworld_ephemeral::systems::instances::IInstancesAdminDispatcherTrait::set_play_class(
            admin, key, class,
        );
        key += 1;
    }
    let records = IRecordsDispatcher { contract_address: world.registry };
    let skill = grimworld_logic::models::skill::SkillTrait::new(
        1, 1, 1, 0, 0, 0, 0, 1, 1, false, [Default::default(); 3],
    );
    records
        .set(
            grimworld_logic::content::SKILL,
            11,
            grimworld_logic::models::skill::SkillRecord::pack(@skill),
        );
    records
        .set(
            grimworld_logic::content::SKILL,
            12,
            grimworld_logic::models::skill::SkillRecord::pack(@skill),
        );
}

fn batch(actions: Span<grimworld_logic::actions::Action>) -> felt252 {
    grimworld_logic::actions::encode_batch(actions).unwrap()
}

/// The `BatchPlayed` of the call: `(played, stop, sequence, clock)`, the stop as its variant index.
fn batch_played(
    ref spy: snforge_std::EventSpy, world: World,
) -> (felt252, felt252, felt252, felt252) {
    let events = spy.get_events().emitted_by(world.instances);
    let mut found = (0, 0, 0, 0);
    for (_, event) in events.events.span() {
        if event.keys.len() == 2 && event.data.len() == 7 {
            found = (*event.data[2], *event.data[3], *event.data[4], *event.data[5]);
        }
    }
    found
}

// Two Moves (West, then East back) from a floor tile: each one tick on the fast path, the facing
// the direction, the sequence and the clock moved by two, `BatchPlayed` with no stop (A2, A3).
#[test]
#[available_gas(l2_gas: 59208302)] // ceil(1.05 × 56388859 measured)
fn test_play_moves() {
    let world = setup();
    play_classes(world);
    let id = create(world, 7, 'alice', 15, 0);
    let mut spy = spy_events();
    let actions = array![
        grimworld_logic::actions::Action::Move(3), grimworld_logic::actions::Action::Move(0),
    ];
    play(world, 'alice').play(id, 7, 0, 0, batch(actions.span()));
    let (played, stop, sequence, clock) = batch_played(ref spy, world);
    assert(played == 2 && stop == 0 && sequence == 2 && clock == 2, 'two moves');
    let header = header_of(world, 1);
    let after = state_of(world, 1);
    assert(header.sequence == 2 && header.clock == 2, 'header');
    assert(after.x == 17 && after.y == 17 && after.facing == 0, 'back, facing East');
}

// A Move into a wall is illegal: the batch stops there, the two Moves before it kept (A2, A3).
#[test]
#[available_gas(l2_gas: 59268558)] // ceil(1.05 × 56446245 measured)
fn test_play_move_blocked() {
    let world = setup();
    play_classes(world);
    let id = create(world, 7, 'alice', 15, 0);
    let mut spy = spy_events();
    let actions = array![
        grimworld_logic::actions::Action::Move(3), grimworld_logic::actions::Action::Move(5),
        grimworld_logic::actions::Action::Move(5),
    ];
    play(world, 'alice').play(id, 7, 0, 0, batch(actions.span()));
    let (played, stop, sequence, _) = batch_played(ref spy, world);
    let after = state_of(world, 1);
    assert(played == 2 && stop == 2 && sequence == 2, 'stopped invalid');
    assert(after.x == 18 && after.y == 16, 'two moves kept');
}

// A stale sequence, a different content version and an Interact (Open question 6) run nothing.
#[test]
#[available_gas(l2_gas: 60701301)] // ceil(1.05 × 57810762 measured)
fn test_play_refusals() {
    let world = setup();
    play_classes(world);
    let id = create(world, 7, 'alice', 15, 0);
    let mut spy = spy_events();
    let one = batch(array![grimworld_logic::actions::Action::Wait].span());
    play(world, 'alice').play(id, 7, 3, 0, one);
    let (played, stop, _, _) = batch_played(ref spy, world);
    assert(played == 0 && stop == 1, 'sequence');
    play(world, 'alice').play(id, 7, 0, 9, one);
    let (played, stop, _, _) = batch_played(ref spy, world);
    assert(played == 0 && stop == 6, 'version');
    play(world, 'alice')
        .play(id, 7, 0, 0, batch(array![grimworld_logic::actions::Action::Interact(0)].span()));
    let (played, stop, _, _) = batch_played(ref spy, world);
    assert(played == 0 && stop == 2, 'interact refused');
    assert(header_of(world, 1).sequence == 0, 'nothing ran');
}

// ---- t-0109: a batch is its actions sent as single batches (design/02, ENG-01 E-13 item 5) ----
// Major 1 and minor 4: between segments the area moves with the goblins of its new chunks. Each
// walk is played as one batch in one world and as single batches in a twin world built the same
// way; the words (the member, the header, the revealed set, the chunks' words, every goblin record
// of the chunks around) and the events (`GoblinKilled`, `ChunkRevealed`) are equal.

const PACK_ZONE: u16 = 6;
const INTO_PACK_ZONE: u16 = 16;

/// The content of the packs: caste 1 (no skill, a melee weapon), pack template 1 (1 to 3 of caste
/// 1); a zone of 3 × 3 chunks whose spawn table places pack 1 at the densest, entered on chunk 0's
/// tile (7, 7); `missing` caste 99 not registered, named by template 2.
fn pack_content(world: World) {
    let records = IRecordsDispatcher { contract_address: world.registry };
    let caste = grimworld_logic::models::caste::CasteTrait::new(
        1,
        0,
        100,
        10,
        0,
        [0; 9],
        WeaponTrait::new(grimworld_logic::types::combat::weapon::AXE, 10, 1, 1, 1),
        0,
        0,
        [0; 4],
        0,
        0,
        0,
        false,
    );
    records.set(grimworld_logic::content::CASTE, 1, CasteRecord::pack(@caste));
    let one = PackCaste { caste: 1, min: 1, max: 3 };
    let pack = Pack {
        castes: [
            one, Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    records.set(PACK, 1, PackRecord::pack(@pack));
    let ghost = PackCaste { caste: 99, min: 1, max: 1 };
    let pack = Pack {
        castes: [
            ghost, Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    records.set(PACK, 2, PackRecord::pack(@pack));
    let spawn = Spawn { template: 1, weight: 1 };
    let table = SpawnTable {
        spawns: [
            spawn, Default::default(), Default::default(), Default::default(), Default::default(),
            Default::default(), Default::default(),
        ],
        density: 255,
    };
    records.set(SPAWN_TABLE, 1, SpawnTableRecord::pack(@table));
    let zone = LocationTrait::new(
        location_kind::ZONE,
        1,
        1,
        1,
        3,
        0,
        3,
        3,
        0,
        0,
        0,
        1,
        false,
        0,
        112,
        Lanes16 { lanes: [0; 15] },
    );
    records.set(LOCATION, PACK_ZONE.into(), zone.pack());
    records
        .set(
            GATE,
            INTO_PACK_ZONE.into(),
            gate(TOWN, PACK_ZONE, (0, 0), (0, 112), gate_kind::HUB, 0, 0),
        );
}

fn chunk_key(slot: u32, chunk: u8) -> felt252 {
    key(selector!("chunks"), array![slot.into(), chunk.into()])
}

/// Chunk `chunk` of slot 1 revealed, every tile walkable (its features kept).
fn open_chunk(world: World, chunk: u8) {
    let terrain: felt252 = StorePacking::pack(Terrain { walls: 0, edges: 0 });
    write(world.instances, chunk_key(1, chunk), terrain);
    let at = key(selector!("revealed"), array![1]);
    let bits: u256 = (read(world.instances, at) - LIVE).into();
    let mut bit: u256 = 1;
    let mut k: u8 = 0;
    while k < chunk {
        bit *= 2;
        k += 1;
    }
    if bits & bit == 0 {
        write(world.instances, at, read(world.instances, at) + bit.try_into().unwrap());
    }
}

/// The member of slot 1 on the tile `(x, y)`.
fn put_member(world: World, x: u8, y: u8) {
    let at = member_word(1, 0);
    let state: MemberState = StorePacking::unpack(read(world.instances, at));
    write(world.instances, at, StorePacking::pack(MemberState { x, y, ..state }));
}

/// The words a batch writes: the member's state, the header, the revealed set, each chunk's two
/// words and its ten goblin records' words, for `chunks`.
fn snapshot_of(world: World, chunks: Span<u8>) -> Array<felt252> {
    let mut out = array![
        read(world.instances, member_word(1, 0)),
        read(world.instances, key(selector!("headers"), array![1])),
        read(world.instances, key(selector!("revealed"), array![1])),
    ];
    for chunk in chunks {
        out.append(read(world.instances, chunk_key(1, *chunk)));
        out.append(read(world.instances, chunk_key(1, *chunk) + 1));
        let mut k: u16 = 0;
        while k < 10 {
            let entity: u16 = 8 + 16 * (*chunk).into() + k;
            let at = key(selector!("goblins"), array![1, entity.into()]);
            out.append(read(world.instances, at));
            out.append(read(world.instances, at + 1));
            k += 1;
        }
    }
    out
}

/// The events of `GoblinKilled` and `ChunkRevealed` (two keys and not seven data felts), in order.
fn kills_and_reveals(ref spy: snforge_std::EventSpy, world: World) -> Array<felt252> {
    let mut out = array![];
    for (_, event) in spy.get_events().emitted_by(world.instances).events.span() {
        if event.keys.len() == 2 && event.data.len() != 7 && event.data.len() != 3 {
            out.append(*event.keys[1]);
            for felt in event.data.span() {
                out.append(*felt);
            }
        }
    }
    out
}

/// Plays `moves` as one batch, then in a twin world as one batch a move, from the same start;
/// returns both worlds' words and events.
fn twin(
    which: u8, gate: u16, moves: Span<grimworld_logic::actions::Action>, chunks: Span<u8>,
) -> (Array<felt252>, Array<felt252>, Array<felt252>, Array<felt252>) {
    let one = setup();
    play_classes(one);
    pack_content(one);
    let id = create(one, 7, 'alice', gate, 0);
    prepare(which, one);
    let mut spy = spy_events();
    play(one, 'alice').play(id, 7, 0, 0, batch(moves));
    let events_one = kills_and_reveals(ref spy, one);
    let words_one = snapshot_of(one, chunks);
    let two = setup();
    play_classes(two);
    pack_content(two);
    let id = create(two, 7, 'alice', gate, 0);
    prepare(which, two);
    let mut spy = spy_events();
    let mut sequence: u32 = 0;
    for action in moves {
        play(two, 'alice').play(id, 7, sequence, 0, batch(array![*action].span()));
        sequence = header_of(two, 1).sequence;
    }
    let events_two = kills_and_reveals(ref spy, two);
    let words_two = snapshot_of(two, chunks);
    (words_one, words_two, events_one, events_two)
}

/// The twins' start: 0 the reveal walk's, 1 the ten Moves'.
fn prepare(which: u8, world: World) {
    if which == 0 {
        prepare_reveal(world);
    } else {
        prepare_walk(world);
    }
}

fn prepare_reveal(world: World) {
    open_chunk(world, 0);
}

// A walk West (the window's `+x`) from chunk 0's (7, 7): at (9, 7) sight touches chunk 1, which the
// reveal generates with the spawn table's packs; then back to (7, 7).
#[test]
#[available_gas(l2_gas: 266187318)] // ceil(1.05 × 253511731 measured)
fn test_play_batch_equals_singles_reveal() {
    let moves = array![
        grimworld_logic::actions::Action::Move(3), grimworld_logic::actions::Action::Move(3),
        grimworld_logic::actions::Action::Move(3), grimworld_logic::actions::Action::Move(0),
        grimworld_logic::actions::Action::Move(0), grimworld_logic::actions::Action::Move(0),
    ];
    let (words_one, words_two, events_one, events_two) = twin(
        0, INTO_PACK_ZONE, moves.span(), array![0, 1, 15, 16].span(),
    );
    // Chunk 1 revealed, holding a pack (its features' first pack, count at bits 32–35)
    let features: u256 = (*words_one[3 + 22 + 1]).into();
    let count = (features.low / 0x100000000) % 0x10;
    println!("reveal: chunk 1's first pack holds {} goblins", count);
    assert(count > 0, 'chunk 1 holds a pack');
    assert(words_one == words_two, 'batch = singles: words');
    assert(events_one == events_two, 'batch = singles: events');
}

fn prepare_walk(world: World) {
    for chunk in array![0_u8, 1, 2, 15, 16, 17, 30, 31, 32] {
        open_chunk(world, chunk);
    }
    // An alerted pack of 3 on chunk 15's East edge (its tile (13, 7), global (13, 22)), every
    // goblin within 2 of it: it enters the window as the adventurer nears x = 20, then walks to it
    let pack = grimworld_logic::models::index::PackPlacement {
        tile: 7 * 15 + 13,
        template: 1,
        level: 1,
        count: 3,
        offsets: 9 + 8 * 32 + 10 * 1024,
        alert: 2,
    };
    let features = grimworld_logic::models::index::Features {
        packs: [pack, Default::default()], objects: [Default::default(); 3], touched: 0,
    };
    write(world.instances, chunk_key(1, 15) + 1, StorePacking::pack(features));
    put_member(world, 30, 22);
}

// Ten Moves toward lower `x` (East) from chunk 17's first column, (30, 22): the area moves when the
// adventurer enters chunk 16, so chunk 15's alerted pack is in the batch's world from there and
// walks toward it, as in each single batch (minor 4; without the area's move the batch would not
// hold it, and the words would differ).
#[test]
#[available_gas(l2_gas: 314943237)] // ceil(1.05 × 299945940 measured)
fn test_play_batch_equals_singles_ten_east() {
    let mut moves = array![];
    let mut k: u8 = 0;
    while k < 10 {
        moves.append(grimworld_logic::actions::Action::Move(0));
        k += 1;
    }
    let (words_one, words_two, events_one, events_two) = twin(
        1, 1, moves.span(), array![0, 1, 2, 15, 16, 17].span(),
    );
    assert(words_one == words_two, 'batch = singles: words');
    assert(events_one == events_two, 'batch = singles: events');
}

fn prepare_ghost(world: World) {
    prepare_walk(world);
    let pack = grimworld_logic::models::index::PackPlacement {
        tile: 7 * 15 + 13, template: 2, level: 1, count: 1, offsets: 9, alert: 0,
    };
    let features = grimworld_logic::models::index::Features {
        packs: [pack, Default::default()], objects: [Default::default(); 3], touched: 0,
    };
    write(world.instances, chunk_key(1, 15) + 1, StorePacking::pack(features));
    put_member(world, 20, 22);
}

// t-0109, note 5: a goblin whose caste the registry does not hold refuses the batch
// (`Stop::Invalid`), nothing run.
#[test]
#[available_gas(l2_gas: 59413860)] // ceil(1.05 × 56584628 measured)
fn test_play_unloadable_goblin_refused() {
    let world = setup();
    play_classes(world);
    pack_content(world);
    let id = create(world, 7, 'alice', 1, 0);
    prepare_ghost(world);
    let mut spy = spy_events();
    play(world, 'alice')
        .play(id, 7, 0, 0, batch(array![grimworld_logic::actions::Action::Wait].span()));
    let (played, stop, sequence, _) = batch_played(ref spy, world);
    assert(played == 0 && stop == 2 && sequence == 0, 'refused, nothing run');
}
