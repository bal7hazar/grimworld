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
    Effect, GONE, INSIDE, MemberEffects, MemberState, MemberTimers, NO_SLOT, Recharges,
    empty_member_timers,
};
use grimworld_ephemeral::systems::instances::Instances::Event;
use grimworld_ephemeral::systems::instances::{
    IInstancesDispatcher, IInstancesDispatcherTrait, IInstancesSafeDispatcher,
    IInstancesSafeDispatcherTrait, InstanceView,
};
use grimworld_logic::content::{GATE, LOCATION, REGION};
use grimworld_logic::fate::{ENTRY, derive, domain};
use grimworld_logic::interface::{
    IInstanceEntryDispatcher, IInstanceEntryDispatcherTrait, IInstanceEntrySafeDispatcher,
    IInstanceEntrySafeDispatcherTrait, facts,
};
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::snapshot::{Snapshot, SnapshotTrait, TaskEntry, TaskPage};
use grimworld_logic::types::{Outcome, Refusal, instance_id};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, load,
    map_entry_address, spy_events, start_cheat_caller_address, store,
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
            core::panic_with_felt252('double: records')
        }
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, Span<felt252>) {
            core::panic_with_felt252('double: bundle')
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
                    (belt % 0x100).try_into().unwrap(), ((belt / 0x100) % 0x100).try_into().unwrap(),
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
    source: u16, destination: u16, anchor: (u8, u8), entry: (u8, u8), kind: u8, rank: u8, quest: u32,
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
    let class = declare("Instances").unwrap().contract_class();
    let (instances, _) = class
        .deploy(@array![ADMIN, hub.into(), registry.into(), fate.into()])
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
    World { instances, registry, fate, hub }
}

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
        .create(adventurer, addr(who), gate, snapshot(), tasks(count))
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

// ---- storage keys (ENG-01 §3.2) -----------------------------------------------------------------

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
    StorePacking::unpack(read(world.instances, key(selector!("placements"), array![adventurer.into()])))
}

// ---- create -------------------------------------------------------------------------------------

// An adventurer's first entry: a new slot, generation 1, every word of §2.1 written for clock 0,
// the entry draw under `poseidon(id, 0, ENTRY)`. Write set (ENG-01 §9.3, first entry, cold): the
// placement, header, entropy, revealed, quotas, the member's 8 words and ⌈16 / 4⌉ = 4 task pages
// new (19 − 2: the entry chunk's 2 words are ENG-05's reveal), `next_slot` overwritten.
#[test]
#[available_gas(l2_gas: 33212563)] // ceil(1.05 × 31631012 measured)
fn test_create_first_entry() {
    let world = setup();
    let keys = watched();
    let before = values(world.instances, keys.span());
    let mut spy = spy_events();
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    let id = entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot(), tasks(16));
    println!("gas create, first entry, 16 tasks (doubles): {}", gas - get_available_gas());
    assert(id == instance_id(1, 1), 'slot 1, generation 1');
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (17, 1, 0), 'writes: 17 new, 1 overwritten');

    let header = header_of(world, 1);
    let expected = Header {
        generation: 1,
        sequence: 0,
        clock: 0,
        location: ZONE,
        status: OPEN,
        members: 1,
        tasks: 16,
        revealed_count: 0,
        roster_count: 0,
        flags: 0,
        entry_chunk: 0,
        entry_tile: 105,
        gate: INTO_ZONE,
    };
    assert(header == expected, 'header');
    let draw = domain(id.into(), 0, ENTRY);
    let entropy = read(world.instances, key(selector!("entropy"), array![1]));
    assert(entropy == derive(poseidon_hash_span(array![WORD, draw].span()), draw, 0), 'entry draw');
    assert(draws(world) == 1, 'one draw');
    assert(read(world.instances, key(selector!("revealed"), array![1])) == LIVE, 'nothing revealed');
    let quotas: Quotas = StorePacking::unpack(
        read(world.instances, key(selector!("quotas"), array![1])),
    );
    assert(quotas == Quotas { target: 0, open_edges: 0, left: [0; 14] }, 'a zone: N = 0');
    assert(placement_of(world, HERO) == Placement { slot: 1, generation: 1, member: 0, inside: 1 }, 'placement');
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
    assert(page.entries == [*tasks(16)[12], *tasks(16)[13], *tasks(16)[14], *tasks(16)[15]], 'page 3');

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

// The same with no task: no task page is written (17 − 4 = 13 new).
#[test]
#[available_gas(l2_gas: 29150107)] // ceil(1.05 × 27762006 measured)
fn test_create_without_tasks() {
    let world = setup();
    let keys = watched();
    let before = values(world.instances, keys.span());
    create(world, HERO, ALICE, INTO_ZONE, 0);
    let after = values(world.instances, keys.span());
    assert(changes(before.span(), after.span()) == (13, 1, 0), 'writes: 13 new, 1 overwritten');
    assert(header_of(world, 1).tasks == 0, 'no task');
}

// A later entry reuses the slot: generation + 1, `next_slot` untouched, every key already written
// (ENG-01 §9.3, later entry, initialised: 0 new).
#[test]
#[available_gas(l2_gas: 46165761)] // ceil(1.05 × 43967391 measured)
fn test_create_reuses_the_slot() {
    let world = setup();
    let first = create(world, HERO, ALICE, INTO_ZONE, 16);
    play(world, ALICE).travel_back(first, HERO, 0);
    let keys = watched();
    let before = values(world.instances, keys.span());
    start_cheat_caller_address(world.instances, world.hub);
    let entry = IInstanceEntryDispatcher { contract_address: world.instances };
    let gas = get_available_gas();
    let second = entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot(), tasks(16));
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
#[available_gas(l2_gas: 34202518)] // ceil(1.05 × 32573826 measured)
fn test_create_refusals() {
    let world = setup();
    let entry = IInstanceEntrySafeDispatcher { contract_address: world.instances };
    start_cheat_caller_address(world.instances, addr(ALICE));
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot(), tasks(0)), NOT_HUB);
    start_cheat_caller_address(world.instances, world.hub);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot(), tasks(17)), TOO_MANY_TASKS);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), 99, snapshot(), tasks(0)), NO_GATE);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), TO_NOWHERE, snapshot(), tasks(0)), NO_LOCATION);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), ZONE_TO_TOWN, snapshot(), tasks(0)), NO_MAP);
    assert(draws(world) == 0, 'no draw');
    create(world, HERO, ALICE, INTO_ZONE, 0);
    #[feature("safe_dispatcher")]
    refused(entry.create(HERO, addr(ALICE), INTO_ZONE, snapshot(), tasks(0)), ALREADY_INSIDE);
}

// A sealed destination sets the header's flag (design/17).
#[test]
#[available_gas(l2_gas: 27125381)] // ceil(1.05 × 25833696 measured)
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

// ---- generation isolation (AC-2, ENG-01 §2.1) ---------------------------------------------------

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
        write(world.instances, key(selector!("roster"), array![s, page.into()]), StorePacking::pack(full));
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
    let effect = Effect { skill: 5, charges: 2, deadline: 90 };
    write(world.instances, member_word(1, 2), StorePacking::pack(MemberEffects { effects: [effect; 4] }));
    write(world.instances, member_word(1, 3), StorePacking::pack(Recharges { deadlines: [80; 8] }));
    for chunk in array![0, 16, 112] {
        write(world.instances, key(selector!("chunks"), array![s, chunk]), junk);
        write(world.instances, key(selector!("chunks"), array![s, chunk]) + 1, junk);
    }
}

// A slot another generation used, with stale data in every word: the new instance shows nothing of
// it, through the view and through the stored words its gates reach.
#[test]
#[available_gas(l2_gas: 43985671)] // ceil(1.05 × 41891115 measured)
fn test_generation_isolation() {
    let world = setup();
    let first = create(world, HERO, ALICE, INTO_ZONE, 16);
    play(world, ALICE).travel_back(first, HERO, 0);
    fill_slot(world);
    // The stale header says 60 goblins in the roster and 200 chunks revealed.
    let stale = Header { roster_count: 60, revealed_count: 200, ..header_of(world, 1) };
    write(world.instances, key(selector!("headers"), array![1]), StorePacking::pack(stale));

    let second = create(world, HERO, ALICE, INTO_ZONE, 1);
    let view = play(world, ALICE).instance_state(second);
    let header = header_of(world, 1);
    assert(header.generation == 2 && header.roster_count == 0, 'roster count reset');
    assert(header.revealed_count == 0 && header.tasks == 1, 'counts reset');
    assert(view.revealed == LIVE, 'nothing revealed');
    let quotas: Quotas = StorePacking::unpack(view.quotas);
    assert(quotas == Quotas { target: 0, open_edges: 0, left: [0; 14] }, 'quotas fresh');
    assert(view.entropy != LIVE + 0x3fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 'entropy fresh');
    assert(view.tasks.len() == 1, 'one task page');
    let page: TaskPage = StorePacking::unpack(*view.tasks[0]);
    assert(page.entries == [*tasks(1)[0], Default::default(), Default::default(), Default::default()], 'task page rewritten');
    assert(view.roster.len() == 0, 'no roster page');
    assert(view.goblins.len() == 0 && view.chunks.len() == 0, 'no chunk, no goblin');
    assert(view.members.len() == 8, 'one member');
    let state: MemberState = StorePacking::unpack(*view.members[0]);
    assert(state.adventurer == HERO && state.health == 140 && state.status == INSIDE, 'state fresh');
    let timers: MemberTimers = StorePacking::unpack(*view.members[1]);
    assert(timers == empty_member_timers(), 'timers fresh');
    assert(*view.members[2] == LIVE && *view.members[3] == LIVE, 'effects, recharges fresh');

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
    assert(play(world, ALICE).instance_state(0) == InstanceView { instance_id: 0, ..empty }, 'id 0');
}

// ---- leave, travel back -------------------------------------------------------------------------

// Through the zone's hub gate, on its anchor (the entry tile): Returned, the town reached and
// unlocked, the belt's counts reported (ENG-01 §9.3: header, member state, placement: 0 new, 3
// overwritten; `InstanceClosed`; one report).
#[test]
#[available_gas(l2_gas: 34834250)] // ceil(1.05 × 33175476 measured)
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
                    Event::InstanceClosed(InstanceClosed { instance_id: id, outcome: Outcome::Returned }),
                ),
            ],
        );
    assert(draws(world) == 1, 'no draw at a hub gate');
}

// Through a link to the dungeon's first floor: this instance closes (Moved) and the next enters in
// the same slot, generation 2, in the same invocation, with its entry draw. Nothing of the member
// carries but the belt's reserve (D-141, E-20; E-13's F-12 case): its conditions, effects,
// recharges and activation, set before leaving, are gone. Write set (ENG-01 §9.3, moved): header,
// entropy, revealed, quotas, the 4 transient member words, the placement: 9 written, 0 new (the
// entry chunk's 2 words are ENG-05's).
#[test]
#[available_gas(l2_gas: 41077499)] // ceil(1.05 × 39121427 measured)
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
    let effect = Effect { skill: 4, charges: 1, deadline: 20 };
    write(world.instances, member_word(1, 2), StorePacking::pack(MemberEffects { effects: [effect; 4] }));
    write(world.instances, member_word(1, 3), StorePacking::pack(Recharges { deadlines: [25; 8] }));
    // Half the health gone, a potion drunk, adrenaline built: none of it carries but the belt.
    let hurt = MemberState { health: 70, energy: 10, adrenaline: 8, belt: [1, 1, 0, 0], hits: 3, ..state_of(world, 1) };
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
    // Nine keys written; the revealed set is written with the value it holds (empty: nothing was
    // revealed before ENG-05), which is no state change (ENG-01 §2.2, point 4): eight change.
    assert(changes(before.span(), after.span()) == (0, 8, 0), 'writes: 8 changed');

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
    assert(placement_of(world, HERO) == Placement { slot: 1, generation: 2, member: 0, inside: 1 }, 'placement');
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
                    Event::InstanceClosed(InstanceClosed { instance_id: id, outcome: Outcome::Moved }),
                ),
                (
                    world.instances,
                    Event::InstanceEntered(
                        InstanceEntered {
                            instance_id: next, adventurer_id: HERO, location: FLOOR_1, gate: LINK_HERE,
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
#[available_gas(l2_gas: 33060719)] // ceil(1.05 × 31486399 measured)
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
#[available_gas(l2_gas: 34670041)] // ceil(1.05 × 33019086 measured)
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
#[available_gas(l2_gas: 39958396)] // ceil(1.05 × 38055615 measured)
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
#[available_gas(l2_gas: 42150499)] // ceil(1.05 × 40143332 measured)
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
#[available_gas(l2_gas: 61435202)] // ceil(1.05 × 58509716 measured)
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
#[available_gas(l2_gas: 30522040)] // ceil(1.05 × 29068609 measured)
fn test_refused_sealed() {
    let world = setup();
    let id = create(world, HERO, ALICE, INTO_SEALED, 0);
    assert_refused(world, id, 0, 0, Refusal::Sealed, 0);
}

// Only the member's controller acts (M-6): a revert, not a refusal of the game.
#[test]
#[available_gas(l2_gas: 29364672)] // ceil(1.05 × 27966354 measured)
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
#[available_gas(l2_gas: 34572933)] // ceil(1.05 × 32926602 measured)
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
