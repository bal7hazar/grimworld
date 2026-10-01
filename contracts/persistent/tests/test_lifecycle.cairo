// ENG-06: the hub's side of the instance lifecycle (design/02 *Expedition lifecycle*, design/01
// *Connectivity*; ENG-01 §6, §9.3, §10; D-141 E-15, D-144): `enter` (the gate's requirements,
// the belt's reserve, the snapshot), `travel`, the settlement `report`, and the start hub read from
// the registry. CBT-02e (D-168): `enter` copies the snapshot `set_build` stored and refuses a
// missing or stale one; the tests that are not about the build store one as `set_build` does
// (`put_snapshot`), and those below `enter_after_set_build` take the real path. `Registry` is the
// real one; `Instances` is a double that records what `create`
// receives (the real one is in `grimworld_ephemeral`, which this package does not depend on; the
// node probe `contracts/tools/lifecycle_probe.py` runs both). Write sets are counted over the keys
// a test watches (`load` before and after).
use core::testing::get_available_gas;
use grimworld_logic::content::{GATE, ITEM, LOCATION, MODIFIER, QUEST, REGION, SKILL};
use grimworld_logic::interface::{
    IRegistryReadDispatcher, IRegistryReadDispatcherTrait, IResultsDispatcher,
    IResultsDispatcherTrait, IResultsSafeDispatcher, IResultsSafeDispatcherTrait, Results, facts,
};
use grimworld_logic::models::gate::{
    GateRecord, GateTrait, errors as gate_errors, kind as gate_kind,
};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class as item_class};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::packing::{LIVE, Lanes16, Lanes32};
use grimworld_logic::snapshot::{SnapshotTrait, SnapshotWords, unpack_bar, unpack_kit, unpack_stats};
use grimworld_logic::types::passive::{PassiveTrait, id as passive_id};
use grimworld_logic::types::{Outcome, instance_id};
use grimworld_persistent::events::AdventurerLocated;
use grimworld_persistent::models::account::{OwnerTrait, PACK};
use grimworld_persistent::models::adventurer::errors::{
    ADVENTURER_DELETED, NOT_IN_HUB, NOT_OWNER, NO_ADVENTURER, NO_START_REGION,
};
use grimworld_persistent::models::adventurer::{AdventurerCore, AdventurerPlace};
use grimworld_persistent::models::balance::errors::NOT_ENOUGH;
use grimworld_persistent::models::item::Gold;
use grimworld_persistent::models::snapshot::errors::{MISSING, STALE};
use grimworld_persistent::models::snapshot::{RULES_EPOCHS, STALE_MARK, StoredSnapshotTrait};
use grimworld_persistent::models::stored_build::NEW_BUILD;
use grimworld_persistent::models::stored_core::errors::EXPERIENCE_OVERFLOW;
use grimworld_persistent::models::stored_place::StoredPlaceTrait;
use grimworld_persistent::models::stored_place::errors::{
    HUB_ABOVE_63, NOT_ITS_INSTANCE, NOT_UNLOCKED,
};
use grimworld_persistent::systems::hub::Hub::Event;
use grimworld_persistent::systems::hub::{
    IHubAdminDispatcher, IHubAdminDispatcherTrait, IHubDispatcher, IHubDispatcherTrait,
    IHubSafeDispatcher, IHubSafeDispatcherTrait, NOT_INSTANCES,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use grimworld_persistent::types::results::errors as results_errors;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, load,
    map_entry_address, spy_events, start_cheat_caller_address, store,
};
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

/// What `create` received, as the double kept it.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Created {
    pub count: u32,
    pub adventurer: u32,
    pub controller: ContractAddress,
    pub gate: u16,
    pub snapshot: SnapshotWords,
    pub tasks: u32,
}

#[starknet::interface]
pub trait ICreated<T> {
    fn created(self: @T) -> Created;
}

/// Stands in for `Instances.create`: only the registered hub may call it; it keeps its arguments
/// and returns `instance_id(1, n)` for its `n`-th call.
#[starknet::contract]
mod EntryDouble {
    use grimworld_logic::interface::IInstanceEntry;
    use grimworld_logic::snapshot::{SnapshotWords, TaskEntry};
    use grimworld_logic::types::{InstanceId, instance_id};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::Created;

    #[storage]
    struct Storage {
        hub: ContractAddress,
        count: u32,
        adventurer: u32,
        controller: ContractAddress,
        gate: u16,
        tasks: u32,
        stats: felt252,
        bar: felt252,
        kit: felt252,
        belt: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, hub: ContractAddress) {
        self.hub.write(hub);
    }

    #[abi(embed_v0)]
    impl EntryImpl of IInstanceEntry<ContractState> {
        fn create(
            ref self: ContractState,
            adventurer_id: u32,
            controller: ContractAddress,
            gate: u16,
            snapshot: SnapshotWords,
            tasks: Span<TaskEntry>,
        ) -> InstanceId {
            assert(get_caller_address() == self.hub.read(), 'double: not the hub');
            let count = self.count.read() + 1;
            self.count.write(count);
            self.adventurer.write(adventurer_id);
            self.controller.write(controller);
            self.gate.write(gate);
            self.tasks.write(tasks.len());
            self.stats.write(snapshot.stats);
            self.bar.write(snapshot.bar);
            self.kit.write(snapshot.kit);
            let [a, b, c, d] = snapshot.belt_counts;
            self
                .belt
                .write(a.into() + b.into() * 0x100 + c.into() * 0x10000 + d.into() * 0x1000000);
            instance_id(1, count)
        }
        fn set_controller(
            ref self: ContractState, adventurer_id: u32, controller: ContractAddress,
        ) {}
    }

    #[abi(embed_v0)]
    impl CreatedImpl of super::ICreated<ContractState> {
        fn created(self: @ContractState) -> Created {
            let belt: u32 = self.belt.read().try_into().unwrap();
            Created {
                count: self.count.read(),
                adventurer: self.adventurer.read(),
                controller: self.controller.read(),
                gate: self.gate.read(),
                snapshot: SnapshotWords {
                    stats: self.stats.read(),
                    bar: self.bar.read(),
                    kit: self.kit.read(),
                    belt_counts: [
                        (belt % 0x100).try_into().unwrap(),
                        ((belt / 0x100) % 0x100).try_into().unwrap(),
                        ((belt / 0x10000) % 0x100).try_into().unwrap(),
                        (belt / 0x1000000).try_into().unwrap(),
                    ],
                },
                tasks: self.tasks.read(),
            }
        }
    }
}

const ADMIN: felt252 = 0xad;
const ALICE: felt252 = 0xa11ce;
const BOB: felt252 = 0xb0b;
const VANGUARD: u8 = 1;
const TOWN: u16 = 1;
const ZONE: u16 = 2;
const OUTPOST: u16 = 4;
// Gates: 1 town → zone (a hub gate); 2 zone → town (not in a hub); 3 a floor gate and 4 a Rift
// gate from the town; 5 a rank, 6 a quest; 7 a link from the town to the floor.
const INTO_ZONE: u16 = 1;

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

#[derive(Copy, Drop)]
struct World {
    hub: ContractAddress,
    registry: ContractAddress,
    instances: ContractAddress,
}

fn location(kind: u8, width: u8, entry_tile: u8) -> Span<felt252> {
    LocationTrait::new(
        kind,
        1,
        1,
        1,
        3,
        0,
        width,
        width,
        0,
        0,
        0,
        0,
        false,
        0,
        entry_tile,
        Lanes16 { lanes: [0; 15] },
    )
        .pack()
}

fn gate(source: u16, destination: u16, kind: u8, rank: u8, quest: u32) -> Span<felt252> {
    GateTrait::new(source, destination, 0, 0, 0, 105, kind, rank, quest).pack()
}

fn setup_with_town(town: u16) -> World {
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![ADMIN]).unwrap();
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![ADMIN, registry.into(), 3, 4, 5]).unwrap();
    let class = declare("EntryDouble").unwrap().contract_class();
    let (instances, _) = class.deploy(@array![hub.into()]).unwrap();
    let flatten = *declare("FlattenLibrary").unwrap().contract_class().class_hash;
    start_cheat_caller_address(hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: hub }
        .set_contracts(registry, instances, addr(4), addr(5), flatten);

    start_cheat_caller_address(registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    admin.set_record(REGION, 1, RegionTrait::new(town, 0, ZONE, 'Test Region').pack());
    admin.set_record(LOCATION, 1, location(location_kind::TOWN, 0, 0));
    admin.set_record(LOCATION, 2, location(location_kind::ZONE, 3, 105));
    admin.set_record(LOCATION, 3, location(location_kind::DUNGEON, 15, 112));
    admin.set_record(LOCATION, 4, location(location_kind::OUTPOST, 0, 0));
    admin.set_record(GATE, 1, gate(TOWN, ZONE, gate_kind::HUB, 0, 0));
    admin.set_record(GATE, 2, gate(ZONE, TOWN, gate_kind::HUB, 0, 0));
    admin.set_record(GATE, 3, gate(TOWN, ZONE, gate_kind::FLOOR, 0, 0));
    admin.set_record(GATE, 4, gate(TOWN, ZONE, gate_kind::RIFT, 0, 0));
    admin.set_record(GATE, 5, gate(TOWN, ZONE, gate_kind::HUB, 1, 0));
    admin.set_record(GATE, 6, gate(TOWN, ZONE, gate_kind::HUB, 0, 7));
    admin.set_record(GATE, 7, gate(TOWN, 3, gate_kind::LINK, 0, 0));
    World { hub, registry, instances }
}

fn setup() -> World {
    setup_with_town(TOWN)
}

fn act(world: World, who: felt252) -> IHubDispatcher {
    start_cheat_caller_address(world.hub, addr(who));
    IHubDispatcher { contract_address: world.hub }
}

fn try_act(world: World, who: felt252) -> IHubSafeDispatcher {
    start_cheat_caller_address(world.hub, addr(who));
    IHubSafeDispatcher { contract_address: world.hub }
}

/// Alice's account and one Vanguard: adventurer 1, with a snapshot (`put_snapshot`).
fn adventurer(world: World) -> u32 {
    let hub = act(world, ALICE);
    hub.register();
    let id = hub.create_adventurer('Aldric', VANGUARD);
    put_snapshot(world, id, [0; 4]);
    id
}

/// The snapshot of `id` as `set_build` stores it (D-168): a level 1 Vanguard's without equipment
/// (`SnapshotTrait::new`), its kit naming the belt's `items`, sealed with the flattening epoch
/// (`epoch`). Returns its words.
fn put_snapshot(world: World, id: u32, items: [u32; 4]) -> SnapshotWords {
    let words = SnapshotTrait::new(1, VANGUARD, [0; 8], 255, items, [0; 4]).words();
    let key = snapshot_key(id);
    write(world.hub, key, words.stats);
    write(world.hub, key + 1, words.bar);
    write(world.hub, key + 2, StoredSnapshotTrait::seal(words.kit, epoch(world)));
    words
}

/// The flattening epoch a snapshot stored now is sealed with (D-169): the registry's inputs
/// version and `Hub`'s rules epoch.
fn epoch(world: World) -> u64 {
    let registry = IRegistryReadDispatcher { contract_address: world.registry };
    let (_, inputs, _) = registry.bundle(array![].span());
    let rules: u16 = read(world.hub, selector!("rules_epoch")).try_into().unwrap();
    StoredSnapshotTrait::epoch(inputs, rules)
}

fn refused<T, +Drop<T>>(result: Result<T, Array<felt252>>, message: felt252) {
    match result {
        Result::Ok(_) => core::panic_with_felt252('should be refused'),
        Result::Err(data) => assert(*data.at(0) == message, *data.at(0)),
    }
}

// Storage keys (ENG-01 §3.3).
fn adventurer_word(id: u32, word: felt252) -> felt252 {
    map_entry_address(selector!("adventurers"), array![id.into()].span()) + word
}
fn pack_page(id: u32, page: u32) -> felt252 {
    map_entry_address(selector!("balances"), array![OwnerTrait::key(PACK, id), page.into()].span())
}
fn snapshot_key(id: u32) -> felt252 {
    map_entry_address(selector!("snapshots"), array![id.into()].span())
}
fn gold_key(id: u32) -> felt252 {
    map_entry_address(selector!("gold"), array![OwnerTrait::key(PACK, id)].span())
}
fn read(target: ContractAddress, key: felt252) -> felt252 {
    *load(target, key, 1).at(0)
}
fn write(target: ContractAddress, key: felt252, value: felt252) {
    store(target, key, array![value].span());
}

fn watched(id: u32) -> Array<felt252> {
    let mut keys = array![gold_key(id)];
    for word in 0..6_u8 {
        keys.append(adventurer_word(id, word.into()));
    }
    for page in 0..20_u32 {
        keys.append(pack_page(id, page));
    }
    keys
}
fn values(target: ContractAddress, keys: Span<felt252>) -> Array<felt252> {
    let mut out = array![];
    for key in keys {
        out.append(read(target, *key));
    }
    out
}
/// `(new, overwritten, zeroed)`.
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

fn place_of(world: World, id: u32) -> AdventurerPlace {
    StorePacking::unpack(read(world.hub, adventurer_word(id, 1)))
}
fn core_of(world: World, id: u32) -> AdventurerCore {
    StorePacking::unpack(read(world.hub, adventurer_word(id, 0)))
}
fn created(world: World) -> Created {
    ICreatedDispatcher { contract_address: world.instances }.created()
}

/// The belt of `id`: items and counts (lane 4), as `set_build` will store it.
fn set_belt(world: World, id: u32, items: [u32; 4], counts: [u8; 4]) {
    let [a, b, c, d] = items;
    let [w, x, y, z] = counts;
    let lane4: u32 = w.into() + x.into() * 0x100 + y.into() * 0x10000 + z.into() * 0x1000000;
    let belt = Lanes32 { lanes: [a, b, c, d, lane4, 0, 0] };
    write(world.hub, adventurer_word(id, 3), StorePacking::pack(belt));
}
/// `amount` of `item` in the pack of `id`, and `pack_lanes` counting it.
fn give(world: World, id: u32, item: u32, amount: u32) {
    let page = item / 7;
    let stored = read(world.hub, pack_page(id, page));
    let mut lanes: Lanes32 = if stored == 0 {
        Lanes32 { lanes: [0; 7] }
    } else {
        StorePacking::unpack(stored)
    };
    let mut out = array![];
    for lane in 0..7_u32 {
        out.append(if lane == item % 7 {
            amount
        } else {
            *lanes.lanes.span()[lane]
        });
    }
    lanes = Lanes32 { lanes: [*out[0], *out[1], *out[2], *out[3], *out[4], *out[5], *out[6]] };
    write(world.hub, pack_page(id, page), StorePacking::pack(lanes));
    let core = core_of(world, id);
    write(
        world.hub,
        adventurer_word(id, 0),
        StorePacking::pack(AdventurerCore { pack_lanes: core.pack_lanes + 1, ..core }),
    );
}
fn balance(world: World, id: u32, item: u32) -> u32 {
    let stored = read(world.hub, pack_page(id, item / 7));
    if stored == 0 {
        return 0;
    }
    let lanes: Lanes32 = StorePacking::unpack(stored);
    *lanes.lanes.span()[item % 7]
}

fn results(instance: u64, id: u32, outcome: Outcome) -> Results {
    Results {
        instance_id: instance,
        contributors: array![id].span(),
        experience: 0,
        gold: 0,
        balances: array![].span(),
        equipment: array![].span(),
        tasks: array![].span(),
        facts: 0,
        location: 0,
        outcome,
        hub: 0,
        next: 0,
        belt: [0; 4],
    }
}
/// `report` as the registered `Instances`.
fn report(world: World, results: Results) {
    start_cheat_caller_address(world.hub, world.instances);
    IResultsDispatcher { contract_address: world.hub }.report(results);
}
fn try_report(world: World, results: Results) -> Result<(), Array<felt252>> {
    start_cheat_caller_address(world.hub, world.instances);
    #[feature("safe_dispatcher")]
    let result = IResultsSafeDispatcher { contract_address: world.hub }.report(results);
    result
}

// ---- the start hub (D-144) ----------------------------------------------------------------------

// A new adventurer stands in region 1's town, read from the registry, unlocked.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 28753704)] // ceil(1.05 × 27384480 measured)
fn test_start_hub_from_the_registry() {
    let world = setup_with_town(OUTPOST);
    let id = adventurer(world);
    let place = place_of(world, id);
    let expected = AdventurerPlace {
        instance: 0, hub: OUTPOST, last_hub: OUTPOST, inside: 0, unlocked: 0x10,
    };
    assert(place == expected, 'in region 1s town');
    assert(read(world.hub, adventurer_word(id, 1)) == StoredPlaceTrait::new(OUTPOST).word, 'word');
}

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 30741795)] // ceil(1.05 × 29277900 measured)
fn test_start_hub_refusals() {
    // No region 1 in the registry.
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![ADMIN]).unwrap();
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![ADMIN, registry.into(), 3, 4, 5]).unwrap();
    start_cheat_caller_address(hub, addr(ALICE));
    IHubDispatcher { contract_address: hub }.register();
    #[feature("safe_dispatcher")]
    refused(
        IHubSafeDispatcher { contract_address: hub }.create_adventurer('A', VANGUARD),
        NO_START_REGION,
    );
    // A town whose id `unlocked` cannot hold.
    let world = setup_with_town(64);
    let hub = act(world, ALICE);
    hub.register();
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).create_adventurer('A', VANGUARD), HUB_ABOVE_63);
}

// ---- enter --------------------------------------------------------------------------------------

// Through a gate of its hub: the snapshot from its level and profession (design/03: 100 health at
// level 1, a Vanguard's 20 energy, 2 pips, armor 80), the owner as controller, no task yet (E-14);
// placed inside, `AdventurerLocated` in no hub. Writes: `place` only (no belt).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 41988072)] // ceil(1.05 × 39988640 measured)
fn test_enter() {
    let world = setup();
    let id = adventurer(world);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let mut spy = spy_events();
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    let instance = hub.enter(id, INTO_ZONE);
    println!("gas enter, no belt (Instances a double): {}", gas - get_available_gas());
    assert(instance == instance_id(1, 1), 'instance id');
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace { instance, hub: 0, last_hub: TOWN, inside: 1, unlocked: 0x2 };
    assert(place_of(world, id) == expected, 'inside');
    let base = SnapshotTrait::new(1, VANGUARD, [0; 8], 255, [0; 4], [0; 4]);
    assert(base.stats.max_health == 100 && base.stats.max_energy == 20, 'base stats');
    assert(base.stats.energy_regen == 2 && base.bar.armor == 80, 'vanguard');
    // The stored words, copied (D-168).
    let snapshot = base.words();
    let got = created(world);
    let expected = Created {
        count: 1, adventurer: id, controller: addr(ALICE), gate: INTO_ZONE, snapshot, tasks: 0,
    };
    assert(got == expected, 'create received');
    spy
        .assert_emitted(
            @array![
                (world.hub, Event::AdventurerLocated(AdventurerLocated { hub: 0, adventurer: id })),
            ],
        );
    // A link from a hub is a gate too.
    let hub = act(world, ALICE);
    let second = hub.create_adventurer('Brenna', VANGUARD);
    put_snapshot(world, second, [0; 4]);
    let hub = act(world, ALICE);
    assert(hub.enter(second, 7) == instance_id(1, 2), 'through a link');
}

// The belt's reserve, the worst case (ENG-01 §6, §9.3): four items on four pages, each lane
// emptied. Four pages, `core` (`pack_lanes` 4 → 0) and `place`: 6 overwritten.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 39497850)] // ceil(1.05 × 37617000 measured)
fn test_enter_reserves_the_belt() {
    let world = setup();
    let id = adventurer(world);
    set_belt(world, id, [7, 15, 22, 29], [3, 2, 1, 5]);
    put_snapshot(world, id, [7, 15, 22, 29]);
    give(world, id, 7, 3);
    give(world, id, 15, 2);
    give(world, id, 22, 1);
    give(world, id, 29, 5);
    assert(core_of(world, id).pack_lanes == 4, 'four lanes');
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.enter(id, INTO_ZONE);
    println!(
        "gas enter, a belt of 4 pages emptied (Instances a double): {}", gas - get_available_gas(),
    );
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 6, 0), 'writes: 4 pages, core, place');
    for item in array![7, 15, 22, 29] {
        assert(balance(world, id, item) == 0, 'debited');
    }
    assert(core_of(world, id).pack_lanes == 0, 'lanes emptied');
    let snapshot = created(world).snapshot;
    let stored = SnapshotTrait::new(1, VANGUARD, [0; 8], 255, [7, 15, 22, 29], [3, 2, 1, 5]);
    assert(snapshot == stored.words(), 'the stored words');
    assert(unpack_kit(snapshot.kit).belt == [7, 15, 22, 29], 'belt');
    // Pages hold `LIVE` after the debit: never 0 again (ENG-01 §2.2).
    assert(read(world.hub, pack_page(id, 1)) == LIVE, 'page kept live');
}

// Two slots of the same item are one debit of their sum (ENG-01 §6); a lane left non-zero keeps
// `pack_lanes`. Writes: the page and `place`.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 35666631)] // ceil(1.05 × 33968220 measured)
fn test_enter_one_debit_per_item() {
    let world = setup();
    let id = adventurer(world);
    set_belt(world, id, [9, 0, 9, 0], [2, 0, 3, 0]);
    give(world, id, 9, 6);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    act(world, ALICE).enter(id, INTO_ZONE);
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 2, 0), 'writes: page, place');
    assert(balance(world, id, 9) == 1, 'one debit of 5');
    assert(core_of(world, id).pack_lanes == 1, 'lane kept');
}

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 48813597)] // ceil(1.05 × 46489140 measured)
fn test_enter_refusals() {
    let world = setup();
    let id = adventurer(world);
    set_belt(world, id, [9, 0, 0, 0], [5, 0, 0, 0]);
    give(world, id, 9, 4);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let cases = array![
        (BOB, id, INTO_ZONE, NOT_OWNER), (ALICE, 99, INTO_ZONE, NO_ADVENTURER),
        (ALICE, id, 99, gate_errors::NONE), (ALICE, id, 2, gate_errors::NOT_HERE),
        (ALICE, id, 3, gate_errors::KIND), (ALICE, id, 4, gate_errors::KIND),
        (ALICE, id, 5, gate_errors::RANK), (ALICE, id, 6, gate_errors::QUEST),
        (ALICE, id, INTO_ZONE, NOT_ENOUGH),
    ];
    for case in cases {
        let (who, adventurer, gate, message) = case;
        #[feature("safe_dispatcher")]
        refused(try_act(world, who).enter(adventurer, gate), message);
    }
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 0, 0), 'nothing changed');
    assert(created(world).count == 0, 'nothing created');

    // Already inside: the ownership check's "in a hub".
    give(world, id, 9, 5);
    act(world, ALICE).enter(id, INTO_ZONE);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), NOT_IN_HUB);
    // Deleted.
    let other = act(world, ALICE).create_adventurer('Brenna', VANGUARD);
    act(world, ALICE).delete_adventurer(other);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(other, INTO_ZONE), ADVENTURER_DELETED);
}

// CBT-08a: the belt `set_build` stores is the one `enter` reserves; the bar and the elite slot
// reach the snapshot; once inside, the build is locked (design/03).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 49512502)] // ceil(1.05 × 47154763 measured)
fn test_enter_after_set_build() {
    let world = setup();
    let id = adventurer(world);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    for item in 1..9_u32 {
        let class = if item == 8 {
            item_class::POTION
        } else {
            item_class::INGREDIENT
        };
        // A potion heals its holder, the legal carrier the registry requires (D-166).
        let entry = if class == item_class::POTION {
            grimworld_logic::types::effect::Entry {
                kind: grimworld_logic::types::effect::kind::HEAL,
                v0: 20,
                v12: 20,
                target: grimworld_logic::types::effect::target::SELF,
                shape: grimworld_logic::types::effect::shape::SINGLE,
                ..Default::default(),
            }
        } else {
            Default::default()
        };
        admin.set_record(ITEM, item, ItemTrait::new(class, 1, 0, 1, 0, entry, 0, 0).pack());
    }
    admin
        .set_record(
            SKILL,
            1,
            SkillTrait::new(VANGUARD, 1, 1, 5, 0, 1, 8, 1, 1, true, [Default::default(); 3]).pack(),
        );
    write(
        world.hub,
        map_entry_address(selector!("known_skills"), array![id.into(), 0].span()),
        0x2 + LIVE,
    );
    give(world, id, 8, 5);
    let belt: felt252 = StorePacking::pack(Lanes32 { lanes: [0, 8, 0, 0, 0x300, 0, 0] });
    // Skill 1 in slot 1 (bits 16-31), the elite slot 1 (bits 168-175).
    let build = 0x10000 + 0x10000000000 * 0x100000000000000000000000000000000;
    act(world, ALICE).set_build(id, build, belt - LIVE, 0);
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(balance(world, id, 8) == 2, 'reserve debited');
    let snapshot = created(world).snapshot;
    assert(unpack_kit(snapshot.kit).belt == [0, 8, 0, 0], 'belt');
    assert(snapshot.belt_counts == [0, 3, 0, 0], 'counts');
    let bar = unpack_bar(snapshot.bar);
    assert(bar.skills == [0, 1, 0, 0, 0, 0, 0, 0] && bar.elite_slot == 1, 'bar');
    // The words `set_build` stored, copied (D-168).
    let key = snapshot_key(id);
    let stored = SnapshotWords {
        stats: read(world.hub, key),
        bar: read(world.hub, key + 1),
        kit: StoredSnapshotTrait::kit(read(world.hub, key + 2), epoch(world)),
        belt_counts: [0, 3, 0, 0],
    };
    assert(snapshot == stored, 'the stored words');
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).set_build(id, build, belt - LIVE, 0), NOT_IN_HUB);
}

/// The build of a new adventurer, as the client sends it (`NEW_BUILD` without `LIVE`).
const EMPTY_BUILD: felt252 = NEW_BUILD - LIVE;

// CBT-02e (D-168 2): `enter` refuses an adventurer whose snapshot `set_build` never stored,
// changing nothing; after `set_build`, it enters.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 37513543)] // ceil(1.05 × 35727183 measured)
fn test_enter_refuses_a_missing_snapshot() {
    let world = setup();
    let hub = act(world, ALICE);
    hub.register();
    let id = hub.create_adventurer('Aldric', VANGUARD);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), MISSING);
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 0, 0), 'nothing changed');
    assert(created(world).count == 0, 'nothing created');
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered after set_build');
}

// D-168 2: every way a stored snapshot goes stale is refused by `enter`, and `set_build` clears
// it: a record the flattening reads changed (the inputs version moves, D-169), a level up
// (GLD-01's, written here with `store`), and the stale mark (what the entrypoints of the report's
// staleness table write). The snapshot finally copied is the level-2 one.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 47464833)] // ceil(1.05 × 45204602 measured)
fn test_enter_refuses_a_stale_snapshot() {
    let world = setup();
    let id = adventurer(world);
    let admin = registry_admin(world);
    admin.set_record(ITEM, 1, ingredient_of(1));
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    // A record the flattening reads changed after `set_build`.
    admin.set_record(ITEM, 1, ingredient_of(2));
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    // A level up.
    let core = core_of(world, id);
    write(
        world.hub, adventurer_word(id, 0), StorePacking::pack(AdventurerCore { level: 2, ..core }),
    );
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    // The mark.
    write(world.hub, snapshot_key(id) + 2, STALE_MARK);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    assert(created(world).count == 0, 'nothing created');
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    act(world, ALICE).enter(id, INTO_ZONE);
    let snapshot = created(world).snapshot;
    assert(unpack_stats(snapshot.stats).level == 2, 'the level-2 snapshot');
    assert(unpack_stats(snapshot.stats).max_health == 120, '100 + 20');
}

fn registry_admin(world: World) -> IRegistryAdminDispatcher {
    start_cheat_caller_address(world.registry, addr(ADMIN));
    IRegistryAdminDispatcher { contract_address: world.registry }
}

/// An ingredient worth `value`: an `ITEM` record.
fn ingredient_of(value: u32) -> Span<felt252> {
    ItemTrait::new(item_class::INGREDIENT, 1, 0, value, 0, Default::default(), 0, 0).pack()
}

/// A Vanguard skill of `adrenaline`: a `SKILL` record.
fn skill_of(adrenaline: u8) -> Span<felt252> {
    SkillTrait::new(VANGUARD, 1, 1, 5, adrenaline, 1, 8, 1, 1, false, [Default::default(); 3])
        .pack()
}

/// A prefix of `value` maximum health: a `MODIFIER` record.
fn prefix_of(value: i16) -> Span<felt252> {
    let benefit = PassiveTrait::new(passive_id::MAX_HEALTH, 0, 0, 0, value, value);
    ModifierTrait::new(modifier_slot::PREFIX, benefit, Default::default()).pack()
}

/// `Hub.set_contracts` as the administrator: the registered contracts as `setup` left them, and
/// `flatten` as the flattening's class.
fn set_flatten(world: World, flatten: felt252) {
    start_cheat_caller_address(world.hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: world.hub }
        .set_contracts(
            world.registry, world.instances, addr(4), addr(5), flatten.try_into().unwrap(),
        );
}

fn flatten_of(world: World) -> felt252 {
    read(world.hub, selector!("flatten"))
}

fn rules_of(world: World) -> felt252 {
    read(world.hub, selector!("rules_epoch"))
}

// D-169 (AC-1): a rewrite of each kind the flattening reads (`SKILL`, `ITEM`, `MODIFIER`) stales
// the stored snapshot, and `set_build` clears it. The records were new before the first
// `set_build`.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 52563622)] // ceil(1.05 × 50060592 measured)
fn test_enter_refuses_after_an_input_rewritten() {
    let world = setup();
    let id = adventurer(world);
    let admin = registry_admin(world);
    admin.set_record(SKILL, 1, skill_of(4));
    admin.set_record(ITEM, 1, ingredient_of(1));
    admin.set_record(MODIFIER, 1, prefix_of(10));
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    let rewrites = array![
        (SKILL, skill_of(5)), (ITEM, ingredient_of(2)), (MODIFIER, prefix_of(20)),
    ];
    for (kind, record) in rewrites {
        admin.set_record(kind, 1, record);
        #[feature("safe_dispatcher")]
        refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
        act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    }
    assert(created(world).count == 0, 'nothing created');
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered after set_build');
}

// D-169 (AC-1): records the flattening does not read, new or rewritten (a gate, a quest, a
// location), and new ids of the kinds it reads, stale nothing: `enter` copies the snapshot
// `set_build` stored before them, without a second `set_build`.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 45727231)] // ceil(1.05 × 43549743 measured)
fn test_enter_after_other_records_changed() {
    let world = setup();
    let id = adventurer(world);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    let stored = read(world.hub, snapshot_key(id) + 2);
    let admin = registry_admin(world);
    admin.set_record(GATE, 8, gate(TOWN, ZONE, gate_kind::HUB, 0, 0));
    admin.set_record(GATE, 7, gate(TOWN, 3, gate_kind::LINK, 1, 0));
    admin.set_record(QUEST, 9, array![LIVE + 1, 2].span());
    admin.set_record(LOCATION, 5, location(location_kind::ZONE, 3, 105));
    admin.set_record(LOCATION, 4, location(location_kind::OUTPOST, 1, 0));
    admin.set_record(SKILL, 1, skill_of(4));
    admin.set_record(ITEM, 1, ingredient_of(1));
    admin.set_record(MODIFIER, 1, prefix_of(10));
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered');
    assert(read(world.hub, snapshot_key(id) + 2) == stored, 'the same snapshot');
}

// D-169 (AC-2): `set_contracts` with another flattening class raises the rules epoch and stales
// the stored snapshot; setting the class back raises it again (still stale); `set_build` under the
// class clears it; the same class set again raises nothing and stales nothing.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 41678045)] // ceil(1.05 × 39693376 measured)
fn test_enter_refuses_after_a_new_rules_class() {
    let world = setup();
    let id = adventurer(world);
    let flatten = flatten_of(world);
    assert(rules_of(world) == 1, 'the first class: 1');
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    set_flatten(world, flatten + 1);
    assert(rules_of(world) == 2, 'another class: +1');
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    set_flatten(world, flatten);
    assert(rules_of(world) == 3, 'back: +1');
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);

    set_flatten(world, flatten);
    assert(rules_of(world) == 3, 'the same class: +0');
    assert(created(world).count == 0, 'nothing created');
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered');
}

// D-169 (AC-2): the rules epoch's wrap. At 511, the highest of its 9 bits, a new class takes it
// to 0, and a snapshot flattened at 511 is stale under 0; `set_build` clears it.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 39993982)] // ceil(1.05 × 38089506 measured)
fn test_enter_after_the_rules_epoch_wraps() {
    let world = setup();
    let id = adventurer(world);
    let flatten = flatten_of(world);
    write(world.hub, selector!("rules_epoch"), (RULES_EPOCHS - 1).into());
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    set_flatten(world, flatten + 1);
    assert(rules_of(world) == 0, '511 wraps to 0');
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    set_flatten(world, flatten);
    assert(rules_of(world) == 1, '0 to 1');
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered');
}

/// `Hub.set_contracts` as the administrator, with `registry` as the registry and the rest as
/// `setup` left them.
fn set_registry(world: World, registry: ContractAddress) {
    start_cheat_caller_address(world.hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: world.hub }
        .set_contracts(
            registry, world.instances, addr(4), addr(5), flatten_of(world).try_into().unwrap(),
        );
}

// D-169 (fix loop 1, security note 2): `set_contracts` with another registry raises the rules
// epoch, as another class does, and stales the stored snapshot; setting the registry back raises
// it again (still stale: the gate is read from the registry first, so the refusal is seen with
// the original one); the same registry and class set again raise nothing, and after `set_build`
// the adventurer enters.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 41192483)] // ceil(1.05 × 39230936 measured)
fn test_enter_refuses_after_a_new_registry() {
    let world = setup();
    let id = adventurer(world);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    assert(rules_of(world) == 1, 'the first configuration: 1');
    let (other, _) = declare("Registry").unwrap().contract_class().deploy(@array![ADMIN]).unwrap();
    set_registry(world, other);
    assert(rules_of(world) == 2, 'another registry: +1');
    set_registry(world, world.registry);
    assert(rules_of(world) == 3, 'back: +1');
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
    set_registry(world, world.registry);
    assert(rules_of(world) == 3, 'the same two: +0');
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'entered');
}

// D-169 (fix loop 1, security note 1): the limitation of the 9-bit epoch, shown. A snapshot
// flattened at epoch 1 is stale after one change of the class, and still stale after 511; after
// exactly 512 changes the epoch is 1 again and `enter` accepts it, though the class changed 512
// times since `set_build`. An administrator-only path (ENG-01 §3.3).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 337526546)] // ceil(1.05 × 321453853 measured)
fn test_rules_epoch_full_cycle_reads_fresh() {
    let world = setup();
    let id = adventurer(world);
    let flatten = flatten_of(world);
    act(world, ALICE).set_build(id, EMPTY_BUILD, 0, 0);
    assert(rules_of(world) == 1, 'flattened at 1');
    for change in 1..RULES_EPOCHS + 1 {
        set_flatten(world, flatten + (change % 2).into());
        if change == 1 || change == RULES_EPOCHS - 1 {
            #[feature("safe_dispatcher")]
            refused(try_act(world, ALICE).enter(id, INTO_ZONE), STALE);
        }
    }
    assert(rules_of(world) == 1, '512 changes: 1 again');
    assert(flatten_of(world) == flatten, 'the original class');
    act(world, ALICE).enter(id, INTO_ZONE);
    assert(created(world).count == 1, 'accepted after 512');
}

// ---- travel -------------------------------------------------------------------------------------

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 37411886)] // ceil(1.05 × 35630367 measured)
fn test_travel() {
    let world = setup();
    let id = adventurer(world);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).travel(id, OUTPOST), NOT_UNLOCKED);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).travel(id, 64), NOT_UNLOCKED);
    #[feature("safe_dispatcher")]
    refused(try_act(world, BOB).travel(id, TOWN), NOT_OWNER);
    // The outpost reached through a hub gate is unlocked.
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    #[feature("safe_dispatcher")]
    refused(try_act(world, ALICE).travel(id, TOWN), NOT_IN_HUB);
    report(
        world,
        Results {
            hub: OUTPOST,
            facts: facts::HUB_REACHED,
            location: OUTPOST,
            ..results(instance, id, Outcome::Returned),
        },
    );
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let mut spy = spy_events();
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.travel(id, TOWN);
    println!("gas travel: {}", gas - get_available_gas());
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace {
        instance: 0, hub: TOWN, last_hub: TOWN, inside: 0, unlocked: 0x12,
    };
    assert(place_of(world, id) == expected, 'in the town');
    spy
        .assert_emitted(
            @array![
                (
                    world.hub,
                    Event::AdventurerLocated(AdventurerLocated { hub: TOWN, adventurer: id }),
                ),
            ],
        );
    act(world, ALICE).travel(id, OUTPOST);
    assert(place_of(world, id).hub == OUTPOST, 'map travel');
}

// ---- report -------------------------------------------------------------------------------------

/// Adventurer 1 inside, with a belt of four items on four pages reserved.
fn inside_with_a_belt(world: World) -> (u32, u64) {
    let id = adventurer(world);
    set_belt(world, id, [7, 15, 22, 29], [3, 2, 1, 5]);
    put_snapshot(world, id, [7, 15, 22, 29]);
    give(world, id, 7, 3);
    give(world, id, 15, 2);
    give(world, id, 22, 1);
    give(world, id, 29, 5);
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    (id, instance)
}

// Returned through a hub gate: the hub reached and unlocked, the belt's unused counts back in the
// pack (ENG-01 §6), `AdventurerLocated`. Writes: 4 pages, `core` (`pack_lanes`), `place`.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 40121077)] // ceil(1.05 × 38210549 measured)
fn test_report_returned_through_a_hub_gate() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let mut spy = spy_events();
    let returned = Results {
        hub: OUTPOST,
        facts: facts::HUB_REACHED,
        location: OUTPOST,
        belt: [1, 2, 1, 4],
        ..results(instance, id, Outcome::Returned),
    };
    start_cheat_caller_address(world.hub, world.instances);
    let gas = get_available_gas();
    IResultsDispatcher { contract_address: world.hub }.report(returned);
    println!("gas report, returned, 4 pages credited: {}", gas - get_available_gas());
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 6, 0), 'writes: 4 pages, core, place');
    let expected = AdventurerPlace {
        instance: 0, hub: OUTPOST, last_hub: OUTPOST, inside: 0, unlocked: 0x12,
    };
    assert(place_of(world, id) == expected, 'in the outpost, unlocked');
    assert(balance(world, id, 7) == 1 && balance(world, id, 15) == 2, 'credited back');
    assert(balance(world, id, 22) == 1 && balance(world, id, 29) == 4, 'consumed is gone');
    assert(core_of(world, id).pack_lanes == 4, 'four lanes filled');
    spy
        .assert_emitted(
            @array![
                (
                    world.hub,
                    Event::AdventurerLocated(AdventurerLocated { hub: OUTPOST, adventurer: id }),
                ),
            ],
        );
}

// Travel back and defeat: `hub` 0 is the last hub (D-04); on defeat the belt comes back as on
// return (D-141, E-15).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 41210923)] // ceil(1.05 × 39248498 measured)
fn test_report_to_the_last_hub() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    report(world, Results { belt: [3, 0, 0, 0], ..results(instance, id, Outcome::Returned) });
    let expected = AdventurerPlace {
        instance: 0, hub: TOWN, last_hub: TOWN, inside: 0, unlocked: 0x2,
    };
    assert(place_of(world, id) == expected, 'travelled back');
    assert(balance(world, id, 7) == 3, 'credited');

    // The other potions were consumed: the next belt carries what the pack holds.
    set_belt(world, id, [7, 0, 0, 0], [3, 0, 0, 0]);
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    assert(balance(world, id, 7) == 0, 'reserved again');
    let mut spy = spy_events();
    report(world, Results { belt: [2, 0, 0, 0], ..results(instance, id, Outcome::Defeated) });
    assert(place_of(world, id) == expected, 'defeated: last hub');
    assert(balance(world, id, 7) == 2, 'credited on defeat');
    spy
        .assert_emitted(
            @array![
                (
                    world.hub,
                    Event::AdventurerLocated(AdventurerLocated { hub: TOWN, adventurer: id }),
                ),
            ],
        );
}

// Through a gate to a location: still inside, in the next instance; nothing credited (the reserve
// carries). Writes: `place`.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 40499355)] // ceil(1.05 × 38570814 measured)
fn test_report_moved() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    let next = instance_id(1, 2);
    refused(
        try_report(
            world, Results { next, belt: [1, 0, 0, 0], ..results(instance, id, Outcome::Moved) },
        ),
        results_errors::BELT,
    );
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    start_cheat_caller_address(world.hub, world.instances);
    let gas = get_available_gas();
    IResultsDispatcher { contract_address: world.hub }
        .report(Results { next, ..results(instance, id, Outcome::Moved) });
    println!("gas report, moved: {}", gas - get_available_gas());
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace {
        instance: next, hub: 0, last_hub: TOWN, inside: 1, unlocked: 0x2,
    };
    assert(place_of(world, id) == expected, 'in the next instance');
    // The next report names the next instance.
    refused(try_report(world, results(instance, id, Outcome::Returned)), NOT_ITS_INSTANCE);
    report(world, results(next, id, Outcome::Returned));
}

// What the models hold today is applied: experience to every contributor, gold and balances to the
// first one's pack (a lane filled counts in `pack_lanes`).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 39467340)] // ceil(1.05 × 37587942 measured)
fn test_report_open() {
    let world = setup();
    let id = adventurer(world);
    let other = act(world, ALICE).create_adventurer('Brenna', VANGUARD);
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    report(
        world,
        Results {
            contributors: array![id, other].span(),
            experience: 50,
            gold: 30,
            balances: array![(100, 4), (101, 1), (100, 2)].span(),
            ..results(instance, id, Outcome::Open),
        },
    );
    assert(core_of(world, id).experience == 50 && core_of(world, other).experience == 50, 'xp');
    let gold: Gold = StorePacking::unpack(read(world.hub, gold_key(id)));
    assert(gold.amount == 30, 'gold');
    assert(balance(world, id, 100) == 6 && balance(world, id, 101) == 1, 'balances');
    assert(core_of(world, id).pack_lanes == 2, 'two lanes filled');
    assert(place_of(world, id).inside == 1, 'still inside');
    let core = core_of(world, id);
    write(
        world.hub,
        adventurer_word(id, 0),
        StorePacking::pack(AdventurerCore { experience: 0xFFFFFFF0, ..core }),
    );
    refused(
        try_report(world, Results { experience: 0x10, ..results(instance, id, Outcome::Open) }),
        EXPERIENCE_OVERFLOW,
    );
}

// What has no model yet is refused rather than dropped; the bounds of ENG-01 §4.5; the caller.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 40267949)] // ceil(1.05 × 38350427 measured)
fn test_report_refusals() {
    let world = setup();
    let id = adventurer(world);
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    start_cheat_caller_address(world.hub, addr(ALICE));
    #[feature("safe_dispatcher")]
    refused(
        IResultsSafeDispatcher { contract_address: world.hub }
            .report(results(instance, id, Outcome::Open)),
        NOT_INSTANCES,
    );
    let nine = array![id, id, id, id, id, id, id, id, id].span();
    let balances = array![(1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1)];
    let cases = array![
        (
            Results { contributors: array![].span(), ..results(instance, id, Outcome::Open) },
            results_errors::CONTRIBUTORS,
        ),
        (
            Results { contributors: nine, ..results(instance, id, Outcome::Open) },
            results_errors::CONTRIBUTORS,
        ),
        (
            Results { balances: balances.span(), ..results(instance, id, Outcome::Open) },
            results_errors::BALANCES,
        ),
        (
            Results { equipment: array![1].span(), ..results(instance, id, Outcome::Open) },
            results_errors::EQUIPMENT,
        ),
        (
            Results { tasks: array![(1, 1)].span(), ..results(instance, id, Outcome::Open) },
            results_errors::TASKS,
        ),
        (
            Results { facts: facts::DUNGEON_CLEARED, ..results(instance, id, Outcome::Open) },
            results_errors::FACTS,
        ),
        (
            Results { belt: [1, 0, 0, 0], ..results(instance, id, Outcome::Open) },
            results_errors::BELT,
        ),
        (
            Results { instance_id: instance + 1, ..results(instance, id, Outcome::Open) },
            NOT_ITS_INSTANCE,
        ),
    ];
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    for case in cases {
        let (results, message) = case;
        refused(try_report(world, results), message);
    }
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 0, 0), 'nothing changed');
    // An adventurer in a hub has no instance to report.
    report(world, results(instance, id, Outcome::Returned));
    refused(try_report(world, results(instance, id, Outcome::Open)), NOT_ITS_INSTANCE);
}
