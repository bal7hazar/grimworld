// ENG-06: the hub's side of the instance lifecycle (design/02 *Expedition lifecycle*, design/01
// *Connectivity*; ENG-01 §6, §9.3, §10; D-141 E-15, D-144): `enter` (the gate's requirements, the
// belt's reserve, the snapshot), `travel`, the settlement `report`, and the start hub read from the
// registry. `Registry` is the real one; `Instances` is a double that records what `create` receives
// (the real one is in `grimworld_ephemeral`, which this package does not depend on; the node probe
// `contracts/tools/lifecycle_probe.py` runs both). Write sets are counted over the keys a test
// watches (`load` before and after).
use grimworld_logic::content::{GATE, LOCATION, REGION};
use grimworld_logic::interface::{IResultsDispatcher, IResultsDispatcherTrait, IResultsSafeDispatcher, IResultsSafeDispatcherTrait, Results, facts};
use grimworld_logic::models::gate::errors as gate_errors;
use grimworld_logic::models::gate::{GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::packing::{LIVE, Lanes16, Lanes32};
use grimworld_logic::snapshot::{Snapshot, SnapshotTrait};
use grimworld_logic::types::{Outcome, instance_id};
use grimworld_persistent::events::AdventurerLocated;
use grimworld_persistent::models::account::{PACK, owner_key};
use grimworld_persistent::models::adventurer::errors::{
    ADVENTURER_DELETED, EXPERIENCE_OVERFLOW, HUB_ABOVE_63, NOT_IN_HUB, NOT_ITS_INSTANCE, NOT_OWNER,
    NOT_UNLOCKED, NO_ADVENTURER, NO_START_REGION,
};
use grimworld_persistent::models::adventurer::{AdventurerCore, AdventurerPlace, AdventurerPlaceTrait};
use grimworld_persistent::models::balance::errors::NOT_ENOUGH;
use grimworld_persistent::models::item::Gold;
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
    pub snapshot: Snapshot,
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
    use grimworld_logic::snapshot::{Snapshot, TaskEntry};
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
        snapshot: felt252,
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
            snapshot: Snapshot,
            tasks: Span<TaskEntry>,
        ) -> InstanceId {
            assert(get_caller_address() == self.hub.read(), 'double: not the hub');
            let count = self.count.read() + 1;
            self.count.write(count);
            self.adventurer.write(adventurer_id);
            self.controller.write(controller);
            self.gate.write(gate);
            self.tasks.write(tasks.len());
            self.stats.write(starknet::storage_access::StorePacking::pack(snapshot.stats));
            self.bar.write(starknet::storage_access::StorePacking::pack(snapshot.bar));
            self.kit.write(starknet::storage_access::StorePacking::pack(snapshot.kit));
            let [a, b, c, d] = snapshot.belt_counts;
            self.belt.write(a.into() + b.into() * 0x100 + c.into() * 0x10000 + d.into() * 0x1000000);
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
                snapshot: Snapshot {
                    stats: starknet::storage_access::StorePacking::unpack(self.stats.read()),
                    bar: starknet::storage_access::StorePacking::unpack(self.bar.read()),
                    kit: starknet::storage_access::StorePacking::unpack(self.kit.read()),
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
// Gates: 1 town → zone (a hub gate); 2 zone → town (not in a hub); 3 a floor gate and 4 a Rift gate
// from the town; 5 a rank, 6 a quest; 7 a link from the town to the floor.
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
        kind, 1, 1, 1, 3, 0, width, width, 0, 0, 0, 0, false, 0, entry_tile,
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
    start_cheat_caller_address(hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: hub }.set_contracts(registry, instances, addr(4), addr(5));

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

/// Alice's account and one Vanguard: adventurer 1.
fn adventurer(world: World) -> u32 {
    let hub = act(world, ALICE);
    hub.register();
    hub.create_adventurer('Aldric', VANGUARD)
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
    map_entry_address(selector!("balances"), array![owner_key(PACK, id), page.into()].span())
}
fn gold_key(id: u32) -> felt252 {
    map_entry_address(selector!("gold"), array![owner_key(PACK, id)].span())
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
#[available_gas(l2_gas: 100000000)]
fn test_start_hub_from_the_registry() {
    let world = setup_with_town(OUTPOST);
    let id = adventurer(world);
    let place = place_of(world, id);
    let expected = AdventurerPlace {
        instance: 0, hub: OUTPOST, last_hub: OUTPOST, inside: 0, unlocked: 0x10,
    };
    assert(place == expected, 'in region 1s town');
    assert(read(world.hub, adventurer_word(id, 1)) == AdventurerPlaceTrait::new(OUTPOST), 'word');
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn test_start_hub_refusals() {
    // No region 1 in the registry.
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![ADMIN]).unwrap();
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![ADMIN, registry.into(), 3, 4, 5]).unwrap();
    start_cheat_caller_address(hub, addr(ALICE));
    IHubDispatcher { contract_address: hub }.register();
    #[feature("safe_dispatcher")]
    refused(IHubSafeDispatcher { contract_address: hub }.create_adventurer('A', VANGUARD), NO_START_REGION);
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
#[available_gas(l2_gas: 100000000)]
fn test_enter() {
    let world = setup();
    let id = adventurer(world);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let mut spy = spy_events();
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    assert(instance == instance_id(1, 1), 'instance id');
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace { instance, hub: 0, last_hub: TOWN, inside: 1, unlocked: 0x2 };
    assert(place_of(world, id) == expected, 'inside');
    let snapshot = SnapshotTrait::new(1, VANGUARD, [0; 8], 255, [0; 4], [0; 4]);
    assert(snapshot.stats.max_health == 100 && snapshot.stats.max_energy == 20, 'base stats');
    assert(snapshot.stats.energy_regen == 2 && snapshot.stats.armor == 80, 'vanguard');
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
    assert(hub.enter(second, 7) == instance_id(1, 2), 'through a link');
}

// The belt's reserve, the worst case (ENG-01 §6, §9.3): four items on four pages, each lane
// emptied. Four pages, `core` (`pack_lanes` 4 → 0) and `place`: 6 overwritten.
#[test]
#[available_gas(l2_gas: 100000000)]
fn test_enter_reserves_the_belt() {
    let world = setup();
    let id = adventurer(world);
    set_belt(world, id, [7, 15, 22, 29], [3, 2, 1, 5]);
    give(world, id, 7, 3);
    give(world, id, 15, 2);
    give(world, id, 22, 1);
    give(world, id, 29, 5);
    assert(core_of(world, id).pack_lanes == 4, 'four lanes');
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    act(world, ALICE).enter(id, INTO_ZONE);
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 6, 0), 'writes: 4 pages, core, place');
    for item in array![7, 15, 22, 29] {
        assert(balance(world, id, item) == 0, 'debited');
    }
    assert(core_of(world, id).pack_lanes == 0, 'lanes emptied');
    let snapshot = created(world).snapshot;
    assert(snapshot.kit.belt == [7, 15, 22, 29] && snapshot.belt_counts == [3, 2, 1, 5], 'belt');
    // Pages hold `LIVE` after the debit: never 0 again (ENG-01 §2.2).
    assert(read(world.hub, pack_page(id, 1)) == LIVE, 'page kept live');
}

// Two slots of the same item are one debit of their sum (ENG-01 §6); a lane left non-zero keeps
// `pack_lanes`. Writes: the page and `place`.
#[test]
#[available_gas(l2_gas: 100000000)]
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
#[available_gas(l2_gas: 100000000)]
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

// ---- travel -------------------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 100000000)]
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
    act(world, ALICE).travel(id, TOWN);
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace { instance: 0, hub: TOWN, last_hub: TOWN, inside: 0, unlocked: 0x12 };
    assert(place_of(world, id) == expected, 'in the town');
    spy
        .assert_emitted(
            @array![
                (world.hub, Event::AdventurerLocated(AdventurerLocated { hub: TOWN, adventurer: id })),
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
#[available_gas(l2_gas: 100000000)]
fn test_report_returned_through_a_hub_gate() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    let mut spy = spy_events();
    report(
        world,
        Results {
            hub: OUTPOST,
            facts: facts::HUB_REACHED,
            location: OUTPOST,
            belt: [1, 2, 1, 4],
            ..results(instance, id, Outcome::Returned),
        },
    );
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
#[available_gas(l2_gas: 100000000)]
fn test_report_to_the_last_hub() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    report(world, Results { belt: [3, 0, 0, 0], ..results(instance, id, Outcome::Returned) });
    let expected = AdventurerPlace { instance: 0, hub: TOWN, last_hub: TOWN, inside: 0, unlocked: 0x2 };
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
                (world.hub, Event::AdventurerLocated(AdventurerLocated { hub: TOWN, adventurer: id })),
            ],
        );
}

// Through a gate to a location: still inside, in the next instance; nothing credited (the reserve
// carries). Writes: `place`.
#[test]
#[available_gas(l2_gas: 100000000)]
fn test_report_moved() {
    let world = setup();
    let (id, instance) = inside_with_a_belt(world);
    let next = instance_id(1, 2);
    refused(
        try_report(world, Results { next, belt: [1, 0, 0, 0], ..results(instance, id, Outcome::Moved) }),
        results_errors::BELT,
    );
    let keys = watched(id);
    let before = values(world.hub, keys.span());
    report(world, Results { next, ..results(instance, id, Outcome::Moved) });
    let after = values(world.hub, keys.span());
    assert(changes(before.span(), after.span()) == (0, 1, 0), 'writes: place');
    let expected = AdventurerPlace { instance: next, hub: 0, last_hub: TOWN, inside: 1, unlocked: 0x2 };
    assert(place_of(world, id) == expected, 'in the next instance');
    // The next report names the next instance.
    refused(try_report(world, results(instance, id, Outcome::Returned)), NOT_ITS_INSTANCE);
    report(world, results(next, id, Outcome::Returned));
}

// What the models hold today is applied: experience to every contributor, gold and balances to the
// first one's pack (a lane filled counts in `pack_lanes`).
#[test]
#[available_gas(l2_gas: 100000000)]
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
    write(world.hub, adventurer_word(id, 0), StorePacking::pack(AdventurerCore { experience: 0xFFFFFFF0, ..core }));
    refused(
        try_report(world, Results { experience: 0x10, ..results(instance, id, Outcome::Open) }),
        EXPERIENCE_OVERFLOW,
    );
}

// What has no model yet is refused rather than dropped; the bounds of ENG-01 §4.5; the caller.
#[test]
#[available_gas(l2_gas: 100000000)]
fn test_report_refusals() {
    let world = setup();
    let id = adventurer(world);
    let instance = act(world, ALICE).enter(id, INTO_ZONE);
    start_cheat_caller_address(world.hub, addr(ALICE));
    #[feature("safe_dispatcher")]
    refused(IResultsSafeDispatcher { contract_address: world.hub }.report(results(instance, id, Outcome::Open)), NOT_INSTANCES);
    let nine = array![id, id, id, id, id, id, id, id, id].span();
    let balances = array![(1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1)];
    let cases = array![
        (Results { contributors: array![].span(), ..results(instance, id, Outcome::Open) }, results_errors::CONTRIBUTORS),
        (Results { contributors: nine, ..results(instance, id, Outcome::Open) }, results_errors::CONTRIBUTORS),
        (Results { balances: balances.span(), ..results(instance, id, Outcome::Open) }, results_errors::BALANCES),
        (Results { equipment: array![1].span(), ..results(instance, id, Outcome::Open) }, results_errors::EQUIPMENT),
        (Results { tasks: array![(1, 1)].span(), ..results(instance, id, Outcome::Open) }, results_errors::TASKS),
        (Results { facts: facts::DUNGEON_CLEARED, ..results(instance, id, Outcome::Open) }, results_errors::FACTS),
        (Results { belt: [1, 0, 0, 0], ..results(instance, id, Outcome::Open) }, results_errors::BELT),
        (Results { instance_id: instance + 1, ..results(instance, id, Outcome::Open) }, NOT_ITS_INSTANCE),
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
