// FIX-02: `play`'s content rounds read the skill of every unused terrain trap of the chunks they
// load (design/19 §5.11: a terrain trap object's `param` is a `SKILL`). The skill below is held by
// no member and no goblin: only the trap's object names it. The registry, the randomness and the
// hub are `test_lifecycle`'s doubles, declared by name.
use grimworld_ephemeral::models::member::MemberState;
use grimworld_ephemeral::systems::instances::{IInstancesDispatcher, IInstancesDispatcherTrait};
use grimworld_logic::actions::Action;
use grimworld_logic::content::{CASTE, GATE, LOCATION, PACK, REGION, SKILL};
use grimworld_logic::interface::{IInstanceEntryDispatcher, IInstanceEntryDispatcherTrait};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::chunk::{FeaturesStorePacking, Terrain, TerrainStorePacking};
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::chunk::object;
use grimworld_logic::models::index::{Features, Object, PackPlacement};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::types::combat::{damage, skill_kind};
use grimworld_logic::types::effect::{Entry, EntryTrait, filter, kind, shape, target};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::pack::{Pack, PackCaste, PackRecord};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::snapshot::{Snapshot, SnapshotTrait, TaskEntry};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, map_entry_address,
    start_cheat_caller_address, store,
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
        *declare("GoblinsLibrary").unwrap().contract_class().class_hash,
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


/// The terrain trap's skill: no member's, no caste's.
const TRAP_SKILL: u32 = 70;

/// The chunk 16 words of the trap: kind 4 (a terrain trap), state `state`, `param` its skill, on
/// local tile 111 `(6, 7)`, i.e. global `(21, 22)`.
fn put_trap(world: World, state: u8, param: u16) {
    let trap = Object { tile: 111, kind: object::TRAP, state, param };
    let features = Features {
        packs: [Default::default(); 2],
        objects: [trap, Default::default(), Default::default()],
        touched: 0,
    };
    write(world.instances, chunk_key(16) + 1, StorePacking::pack(features));
}

fn trap_of(world: World) -> Object {
    let features: Features = StorePacking::unpack(read(world.instances, chunk_key(16) + 1));
    *features.objects.span()[0]
}

/// The trap skill the registry holds: a `TRAP` entry, then an earth payload on a foe.
fn register_trap_skill(world: World, id: u32) {
    let none: Entry = Default::default();
    let trap = EntryTrait::new(kind::TRAP, 0, 0, 0, 0, 0, 0, target::TILE, shape::SINGLE, 0, 0, 0);
    let earth = EntryTrait::new(
        kind::DAMAGE, damage::EARTH, 10, 40, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    let skill = SkillTrait::new(1, 1, skill_kind::TRAP, 0, 0, 0, 0, 3, 1, false, [trap, earth, none]);
    IRecordsDispatcher { contract_address: world.registry }
        .set(SKILL, id, SkillRecord::pack(@skill));
}

fn health(world: World) -> u16 {
    let state: MemberState = StorePacking::unpack(read(world.instances, member_word()));
    state.health
}

// The adventurer on (22, 22) walks West onto a live terrain trap on (21, 22) whose skill (70) is
// held by nobody else: the trap fires (used, the earth payload hurts the member).
#[test]
#[available_gas(l2_gas: 54871651)] // ceil(1.05 × 52258715 measured)
fn test_terrain_trap_fires() {
    let world = setup();
    open_zone(world, 22, 22);
    register_trap_skill(world, TRAP_SKILL);
    put_trap(world, 0, TRAP_SKILL.try_into().unwrap());
    let before = health(world);
    play(world).play(world.id, 7, 0, 0, batch(array![Action::Move(0)].span()));
    let state: MemberState = StorePacking::unpack(read(world.instances, member_word()));
    assert(state.x == 21 && state.y == 22, 'moved onto the trap');
    assert(trap_of(world).state == 1, 'the trap is used');
    assert(health(world) < before, 'the payload hurt the member');
}

// A terrain trap whose skill the registry lacks refuses the batch (`Stop::Invalid`, nothing ran),
// as a goblin the registry cannot load does: never a silently inert trap.
#[test]
#[available_gas(l2_gas: 44727755)] // ceil(1.05 × 42597861 measured)
fn test_terrain_trap_skill_missing_refuses() {
    let world = setup();
    open_zone(world, 22, 22);
    put_trap(world, 0, 71);
    play(world).play(world.id, 7, 0, 0, batch(array![Action::Move(0)].span()));
    let state: MemberState = StorePacking::unpack(read(world.instances, member_word()));
    assert(state.x == 22 && state.y == 22, 'nothing ran');
    assert(trap_of(world).state == 0, 'the trap is unused');
}

// A generated terrain trap has no skill (`param` 0, `reveal::placement`): it asks the registry for
// nothing and stays inert, the member walking over it.
#[test]
#[available_gas(l2_gas: 51843986)] // ceil(1.05 × 49375224 measured)
fn test_terrain_trap_without_skill_is_inert() {
    let world = setup();
    open_zone(world, 22, 22);
    put_trap(world, 0, 0);
    play(world).play(world.id, 7, 0, 0, batch(array![Action::Move(0)].span()));
    let state: MemberState = StorePacking::unpack(read(world.instances, member_word()));
    assert(state.x == 21 && state.y == 22, 'moved');
    assert(trap_of(world).state == 0, 'the trap is unused');
}

// The bound of the bundle: 9 chunks of the area, 3 objects each, 27 distinct skills (below
// `MAX_READ` = 32; `GoblinsLibrary` reads 32 a call anyway). The trap under the member's step
// fires.
#[test]
#[available_gas(l2_gas: 102869125)] // ceil(1.05 × 97970595 measured)
fn test_terrain_trap_widest_area() {
    let world = setup();
    open_zone(world, 22, 22);
    let chunks: Array<u8> = array![0, 1, 2, 15, 16, 17, 30, 31, 32];
    let mut id: u16 = 100;
    for chunk in chunks {
        let mut objects = array![];
        let mut k: u8 = 0;
        while k < 3 {
            // Chunk 16's first trap is the one the Move enters: tile 111.
            let tile = if chunk == 16 && k == 0 {
                111
            } else {
                k
            };
            register_trap_skill(world, id.into());
            objects.append(Object { tile, kind: object::TRAP, state: 0, param: id });
            id += 1;
            k += 1;
        }
        let features = Features {
            packs: [Default::default(); 2],
            objects: [*objects[0], *objects[1], *objects[2]],
            touched: 0,
        };
        write(world.instances, chunk_key(chunk) + 1, StorePacking::pack(features));
    }
    let before = health(world);
    play(world).play(world.id, 7, 0, 0, batch(array![Action::Move(0)].span()));
    assert(trap_of(world).state == 1, 'the trap is used');
    assert(health(world) < before, 'the payload hurt the member');
}
