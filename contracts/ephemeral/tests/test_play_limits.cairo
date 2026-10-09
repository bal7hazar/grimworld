// ENG-07b: `play`'s limits on goblin records (ENG-01 E-16 and E-1, D-141; E-21), the packs'
// `alert` bits written back (ENG-01 §3.2, design/18) and a changed goblin dropped from the batch's
// world once written (t-0111's note). Each rule is played as one batch in one world and as single
// batches of the actions the batch played in a twin world built the same way: the words (the
// member, the header, the revealed set, each chunk's words and its goblin records) and the events
// are equal (design/02: a batch is its actions sent as single batches). The registry, the
// randomness and the hub are `test_lifecycle`'s doubles, declared by name.
use grimworld_ephemeral::models::instance::Header;
use grimworld_ephemeral::models::member::MemberState;
use grimworld_ephemeral::systems::instances::{IInstancesDispatcher, IInstancesDispatcherTrait};
use grimworld_logic::actions::Action;
use grimworld_logic::content::{CASTE, GATE, LOCATION, PACK, REGION};
use grimworld_logic::interface::{IInstanceEntryDispatcher, IInstanceEntryDispatcherTrait};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::chunk::{FeaturesStorePacking, Terrain, TerrainStorePacking};
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::index::{Features, PackPlacement};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::pack::{Pack, PackCaste, PackRecord};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::snapshot::{Snapshot, SnapshotTrait, TaskEntry};
use grimworld_logic::types::tick::ai;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait, EventsFilterTrait, declare, load,
    map_entry_address, spy_events, start_cheat_caller_address, store,
};
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

/// `test_lifecycle`'s `RegistryDouble`, by its selector.
#[starknet::interface]
trait IRecords<T> {
    fn set(ref self: T, kind: u8, id: u32, parts: Span<felt252>);
}

const ADMIN: felt252 = 0xad;
const TOWN: u16 = 1;
const ZONE: u16 = 2;
/// The `Stop` variants `BatchPlayed` carries.
const STOP_NONE: felt252 = 0;
const STOP_WEIGHT: felt252 = 3;

#[derive(Copy, Drop)]
struct World {
    instances: ContractAddress,
    registry: ContractAddress,
    hub: ContractAddress,
    id: u64,
}

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

/// A town and a zone of 3 × 3 chunks entered from the town (gate 1, chunk 0's tile 105); caste 1
/// (no skill, an axe) and pack template 1 (1 to 5 of caste 1); `Instances` with every play class;
/// adventurer 7 of `alice` entered (slot 1).
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
    records.set(LOCATION, 1, location(location_kind::TOWN, 0));
    records.set(LOCATION, 2, location(location_kind::ZONE, 3));
    records.set(GATE, 1, GateTrait::new(TOWN, ZONE, 0, 0, 0, 105, gate_kind::HUB, 0, 0).pack());
    let caste = CasteTrait::new(
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
    records.set(CASTE, 1, CasteRecord::pack(@caste));
    let one = PackCaste { caste: 1, min: 1, max: 5 };
    let pack = Pack {
        castes: [
            one, Default::default(), Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    records.set(PACK, 1, PackRecord::pack(@pack));
    let world = World { instances, registry, hub, id: 0 };
    play_classes(world);
    World { id: create(world), ..world }
}

fn location(kind: u8, width: u8) -> Span<felt252> {
    LocationTrait::new(
        kind, 1, 1, 1, 3, 0, width, width, 0, 0, 0, 0, false, 0, 105, Lanes16 { lanes: [0; 15] },
    )
        .pack()
}

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
    let parts = grimworld_logic::models::skill::SkillRecord::pack(@skill);
    records.set(grimworld_logic::content::SKILL, 11, parts);
    records.set(grimworld_logic::content::SKILL, 12, parts);
}

/// `create` as the hub, for adventurer 7 of `alice`, through gate 1: slot 1.
fn create(world: World) -> u64 {
    start_cheat_caller_address(world.instances, world.hub);
    let snapshot: Snapshot = SnapshotTrait::new(
        3, 1, [11, 12, 0, 0, 0, 0, 0, 0], 255, [41, 42, 0, 0], [2, 1, 0, 0],
    );
    let tasks: Array<TaskEntry> = array![];
    IInstanceEntryDispatcher { contract_address: world.instances }
        .create(7, addr('alice'), 1, snapshot.words(), tasks.span())
}

fn play(world: World) -> IInstancesDispatcher {
    start_cheat_caller_address(world.instances, addr('alice'));
    IInstancesDispatcher { contract_address: world.instances }
}

fn batch(actions: Span<Action>) -> felt252 {
    grimworld_logic::actions::encode_batch(actions).unwrap()
}

// ---- storage keys (ENG-01 §3.2) ----------------------------------------------------------------

fn key(name: felt252, keys: Array<felt252>) -> felt252 {
    map_entry_address(name, keys.span())
}
fn read(target: ContractAddress, at: felt252) -> felt252 {
    *load(target, at, 1).at(0)
}
fn write(target: ContractAddress, at: felt252, value: felt252) {
    store(target, at, array![value].span());
}
fn member_word() -> felt252 {
    key(selector!("members"), array![1, 0])
}
fn chunk_key(chunk: u8) -> felt252 {
    key(selector!("chunks"), array![1, chunk.into()])
}
fn goblin_key(entity: u16) -> felt252 {
    key(selector!("goblins"), array![1, entity.into()])
}
fn header_of(world: World) -> Header {
    StorePacking::unpack(read(world.instances, key(selector!("headers"), array![1])))
}

/// `2^n`.
fn two(n: u32) -> felt252 {
    let mut value: felt252 = 1;
    let mut k = 0;
    while k < n {
        value *= 2;
        k += 1;
    }
    value
}

/// Every chunk of the zone revealed and walkable, no pack, no record; the member on `(x, y)`.
fn open_zone(world: World, x: u8, y: u8) {
    let terrain: felt252 = StorePacking::pack(Terrain { walls: 0, edges: 0 });
    let features: felt252 = StorePacking::pack(
        Features { packs: [Default::default(); 2], objects: [Default::default(); 3], touched: 0 },
    );
    let mut revealed: felt252 = 0;
    for chunk in array![0_u8, 1, 2, 15, 16, 17, 30, 31, 32] {
        write(world.instances, chunk_key(chunk), terrain);
        write(world.instances, chunk_key(chunk) + 1, features);
        revealed += two(chunk.into());
    }
    write(world.instances, key(selector!("revealed"), array![1]), LIVE + revealed);
    let state: MemberState = StorePacking::unpack(read(world.instances, member_word()));
    write(world.instances, member_word(), StorePacking::pack(MemberState { x, y, ..state }));
}

/// `chunk`'s packs: `counts` goblins of template 1 at level 1, the pack's tile `tiles` (local),
/// its goblins on `OFFSETS` 7 to 11 (the pack's row, `dq` −2 to 2), its `alert`, `touched`.
fn put_packs(world: World, chunk: u8, counts: [u8; 2], tiles: [u8; 2], alert: u8, touched: u16) {
    let [c0, c1] = counts;
    let [t0, t1] = tiles;
    let offsets = 7 + 8 * 32 + 9 * 1024 + 10 * 32768 + 11 * 1048576;
    let first = PackPlacement { tile: t0, template: 1, level: 1, count: c0, offsets, alert };
    let second = PackPlacement { tile: t1, template: 1, level: 1, count: c1, offsets, alert };
    let features = Features {
        packs: [first, if c1 > 0 {
            second
        } else {
            Default::default()
        }],
        objects: [Default::default(); 3],
        touched,
    };
    write(world.instances, chunk_key(chunk) + 1, StorePacking::pack(features));
}

/// A goblin record of caste 1 at level 1: its tile, AI state, adrenaline; health 100, no timer.
fn put_goblin(world: World, entity: u16, x: u8, y: u8, state: u8, adrenaline: u8) {
    let word = LIVE
        + x.into()
        + y.into() * two(8)
        + state.into() * two(24)
        + 100 * two(32)
        + adrenaline.into() * two(56)
        + two(64)
        + two(80);
    write(world.instances, goblin_key(entity), word);
    write(world.instances, goblin_key(entity) + 1, LIVE + 255);
}

/// The words a batch writes: the member's state, the header, the revealed set, each of `chunks`'
/// two words and its ten goblin records' words.
fn snapshot_of(world: World, chunks: Span<u8>) -> Array<felt252> {
    let mut out = array![
        read(world.instances, member_word()),
        read(world.instances, key(selector!("headers"), array![1])),
        read(world.instances, key(selector!("revealed"), array![1])),
    ];
    for chunk in chunks {
        out.append(read(world.instances, chunk_key(*chunk)));
        out.append(read(world.instances, chunk_key(*chunk) + 1));
        let mut k: u16 = 0;
        while k < 10 {
            let at = goblin_key(8 + 16 * (*chunk).into() + k);
            out.append(read(world.instances, at));
            out.append(read(world.instances, at + 1));
            k += 1;
        }
    }
    out
}

/// The `BatchPlayed` of the calls spied: the last one's `(played, stop)`, and the events of
/// `GoblinKilled` and `ChunkRevealed` in order.
fn events(ref spy: snforge_std::EventSpy, world: World) -> (felt252, felt252, Array<felt252>) {
    let mut out = array![];
    let mut played = (0, 0);
    for (_, event) in spy.get_events().emitted_by(world.instances).events.span() {
        if event.keys.len() == 2 && event.data.len() == 7 {
            played = (*event.data[2], *event.data[3]);
        } else if event.keys.len() == 2 && event.data.len() != 3 {
            out.append(*event.keys[1]);
            for felt in event.data.span() {
                out.append(*felt);
            }
        }
    }
    let (count, stop) = played;
    (count, stop, out)
}

/// The world of a test: entered, then `prepare`d (0 E-16's, 1 E-1's and the alert's, 2 the drop's).
fn world_of(which: u8) -> World {
    let world = setup();
    if which == 0 {
        prepare_cap(world);
    } else if which == 1 {
        prepare_alert(world);
    } else {
        prepare_drop(world);
    }
    world
}

/// `actions` played as one batch in one world, then in a twin world its first `played` actions
/// as single batches; both worlds' words over `chunks`, the batch's `(played, stop)`, and the
/// batch's world.
fn twin(
    which: u8, actions: Span<Action>, chunks: Span<u8>,
) -> (Array<felt252>, Array<felt252>, felt252, felt252, World) {
    let one = world_of(which);
    let mut spy = spy_events();
    play(one).play(one.id, 7, 0, 0, batch(actions));
    let (played, stop, events_one) = events(ref spy, one);
    let words_one = snapshot_of(one, chunks);
    let two = world_of(which);
    let mut spy = spy_events();
    let count: u32 = played.try_into().unwrap();
    let mut sequence: u32 = 0;
    for action in actions.slice(0, count) {
        play(two).play(two.id, 7, sequence, 0, batch(array![*action].span()));
        sequence = header_of(two).sequence;
    }
    let (_, _, events_two) = events(ref spy, two);
    let words_two = snapshot_of(two, chunks);
    assert(events_one == events_two, 'batch = singles: events');
    (words_one, words_two, played, stop, one)
}

// ---- E-16: at most 16 goblin records an invocation, its first action excepted (E-21) -----------

/// Four packs of five goblins with records (chunks 16 and 31), asleep, one of each two tiles from
/// `(21, 30)` and three from the member on `(22, 30)`: a Move to `(21, 30)` wakes the four, their
/// twenty goblins engaged in one tick (twenty records, the packs' goblins having records).
fn prepare_cap(world: World) {
    open_zone(world, 22, 30);
    put_packs(world, 16, [5, 5], [0, 0], 0, 0x3ff);
    put_packs(world, 31, [5, 5], [0, 0], 0, 0x3ff);
    let near: Array<(u8, u8)> = array![(19, 29), (20, 28), (19, 31), (20, 32)];
    let mut p: u32 = 0;
    for chunk in array![16_u16, 31] {
        let mut k: u16 = 0;
        while k < 10 {
            let entity = 8 + 16 * chunk + k;
            let (x, y) = if k % 5 == 0 {
                *near[p + (k / 5).into()]
            } else {
                let row: u8 = if chunk == 16 {
                    16
                } else {
                    40
                };
                ((15 + k).try_into().unwrap(), row + 2 * (k / 5).try_into().unwrap())
            };
            put_goblin(world, entity, x, y, ai::ASLEEP, 0);
            k += 1;
        }
        p += 2;
    }
}

/// How many of the twenty goblins of `prepare_cap` are Engaged.
fn engaged(world: World) -> u32 {
    let mut count = 0;
    for chunk in array![16_u16, 31] {
        let mut k: u16 = 0;
        while k < 10 {
            let state: u256 = read(world.instances, goblin_key(8 + 16 * chunk + k)).into();
            if (state.low / 0x1000000) % 0x100 == ai::ENGAGED.into() {
                count += 1;
            }
            k += 1;
        }
    }
    count
}

// A Turn, then the Move that engages twenty goblins with records: the Move would pass 16, so the
// batch stops before it (`Stop::Weight`), the Turn played and nothing of the Move kept, as the
// Turn sent alone. Then the Move as the next batch's first action runs whatever it changes (E-21).
#[test]
#[available_gas(l2_gas: 267185463)] // ceil(1.05 × 254462345 measured)
fn test_play_records_cap() {
    let actions = array![Action::Turn(1), Action::Move(0)];
    let (words_one, words_two, played, stop, one) = twin(
        0, actions.span(), array![15, 16, 17, 30, 31, 32].span(),
    );
    assert(played == 1 && stop == STOP_WEIGHT, 'stopped before the Move');
    assert(words_one == words_two, 'batch = singles: words');
    let state: MemberState = StorePacking::unpack(read(one.instances, member_word()));
    assert(state.x == 22 && state.y == 30 && engaged(one) == 0, 'nothing of the Move');
    let mut spy = spy_events();
    play(one).play(one.id, 7, 1, 0, batch(array![Action::Move(0)].span()));
    let (played, stop, _) = events(ref spy, one);
    let count = engaged(one);
    println!("E-21: the Move alone engages {} goblins with records", count);
    assert(played == 1 && stop == STOP_NONE && count > 16, 'a first action runs');
}

// ---- E-1 and the packs' alert bits -------------------------------------------------------------

/// Chunk 16's two packs, asleep, without records: five on `(17..21, 22)` and four on
/// `(21..24, 24)`, the member on `(24, 22)`. A Move to `(23, 22)` wakes both (each has a goblin
/// two tiles away): nine goblins Engaged, the eight nearest awake and acting (eight first
/// records), the ninth, `(17, 22)` (pack 0's goblin 0), six tiles away, engaged and nothing else.
fn prepare_alert(world: World) {
    open_zone(world, 24, 22);
    put_packs(world, 16, [5, 4], [7 * 15 + 4, 9 * 15 + 8], 0, 0);
}

// A Move and two Waits: the Move's eight first records weigh 8 more (E-1), so the weight left
// holds one Wait (10 − 1 − 8), and the batch stops before the second (`Stop::Weight`), as the
// two actions sent alone. The goblin engaged and nothing else has no record: its pack's `alert`
// bits are Engaged (ENG-01 §3.2), which the single batches derive it from.
#[test]
#[available_gas(l2_gas: 351119649)] // ceil(1.05 × 334399665 measured)
fn test_play_first_records_and_alert() {
    let actions = array![Action::Move(0), Action::Wait, Action::Wait];
    let (words_one, words_two, played, stop, one) = twin(
        1, actions.span(), array![15, 16, 17, 30, 31, 32].span(),
    );
    println!("E-1: played {} stop {}", played, stop);
    assert(played == 2 && stop == STOP_WEIGHT, 'the first records weigh');
    assert(words_one == words_two, 'batch = singles: words');
    let features: Features = StorePacking::unpack(read(one.instances, chunk_key(16) + 1));
    let [first, _] = features.packs;
    println!("alert {} touched {}", first.alert, features.touched);
    assert(first.alert == ai::ENGAGED, 'the pack engaged');
    assert(features.touched & 1 == 0, 'goblin 0 has no record');
    assert(read(one.instances, goblin_key(8 + 16 * 16)) == 0, 'no record written');
}

// ---- t-0111's note: a changed goblin of a chunk the area leaves
// ----------------------------------

/// A goblin with a record on chunk 15's `(14, 22)`, on watch, its adrenaline 40, seven tiles from
/// the member on `(21, 22)`: in the window, awake, it does not act but its adrenaline decays (a
/// change, at home).
fn prepare_drop(world: World) {
    open_zone(world, 20, 22);
    put_packs(world, 15, [1, 0], [7 * 15 + 14, 0], 0, 1);
    put_goblin(world, 8 + 16 * 15, 14, 22, ai::WATCH, 40);
}

// Ten Moves West from `(20, 22)` into chunk 17: the goblin changes on the first tick, then the
// area moves to the 3 × 3 around chunk 17, which chunk 15 is not part of: the goblin, changed and
// home, is written back and leaves the batch's world, as each single batch writes it. Its
// adrenaline decays once, as in the single batches: a goblin awake at the last tick and outside
// the window since does not take the fast path's ticks awake (`SegmentTrait::idle`).
#[test]
#[available_gas(l2_gas: 238867453)] // ceil(1.05 × 227492812 measured)
fn test_play_changed_goblin_dropped() {
    let mut actions = array![];
    let mut k: u8 = 0;
    while k < 10 {
        actions.append(Action::Move(3));
        k += 1;
    }
    let (words_one, words_two, played, stop, one) = twin(
        2, actions.span(), array![15, 16, 17].span(),
    );
    assert(played == 10 && stop == STOP_NONE, 'ten moves');
    assert(words_one == words_two, 'batch = singles: words');
    let state: u256 = read(one.instances, goblin_key(8 + 16 * 15)).into();
    let adrenaline = (state.low / 0x100000000000000) % 0x100;
    println!("the goblin's adrenaline: {}", adrenaline);
    assert(adrenaline < 40, 'the goblin changed');
}
