//! Each measured action on its fixture. The budget covers the whole test (world, setup and
//! action); the action alone is read from the trace (`--trace-components gas`), see the report.

use dojo::model::ModelStorage;
use dojo::world::{WorldStorage, WorldStorageTrait};
use dojo_snf_test::{
    ContractDef, ContractDefTrait, NamespaceDef, TestResource, WorldStorageTestTrait,
    get_default_caller_address, set_caller_address, spawn_test_world,
};
use spk2::fixtures::{
    QUEUE, QUEUE_1, QUEUE_5, QUEUE_LENGTH, START_X, START_Y, WEST, WORST, WORST_PACKED,
};
use spk2::models::{
    Adventurer, Balance, Discovery, Goblin, Grimoire, Instance, InstanceAdventurer, Pack,
    QuestLog, unpack_goblin,
};
use spk2::systems::brew::{IBrewDispatcher, IBrewDispatcherTrait};
use spk2::systems::hub::{IHubDispatcher, IHubDispatcherTrait};
use spk2::systems::queue_moves::{IQueueMovesDispatcher, IQueueMovesDispatcherTrait};
use spk2::systems::setup::{ISetupDispatcher, ISetupDispatcherTrait};
use spk2::systems::tick_worst_case::{ITickWorstCaseDispatcher, ITickWorstCaseDispatcherTrait};

fn namespace_def() -> NamespaceDef {
    NamespaceDef {
        namespace: "spk2",
        resources: [
            TestResource::Model("Instance"), TestResource::Model("InstanceAdventurer"),
            TestResource::Model("Goblin"), TestResource::Model("Window"),
            TestResource::Model("Adventurer"), TestResource::Model("Balance"),
            TestResource::Model("Book"), TestResource::Model("Grimoire"),
            TestResource::Model("Discovery"), TestResource::Model("Quest"),
            TestResource::Model("QuestLog"), TestResource::Model("Location"),
            TestResource::Model("Counter"), TestResource::Model("Pack"),
            TestResource::Contract("setup"),
            TestResource::Contract("tick_worst_case"), TestResource::Contract("queue_moves"),
            TestResource::Contract("brew"), TestResource::Contract("hub"),
        ]
            .span(),
    }
}

fn contract_defs() -> Span<ContractDef> {
    let writer = [dojo::utils::bytearray_hash(@"spk2")].span();
    [
        ContractDefTrait::new(@"spk2", @"setup").with_writer_of(writer),
        ContractDefTrait::new(@"spk2", @"tick_worst_case").with_writer_of(writer),
        ContractDefTrait::new(@"spk2", @"queue_moves").with_writer_of(writer),
        ContractDefTrait::new(@"spk2", @"brew").with_writer_of(writer),
        ContractDefTrait::new(@"spk2", @"hub").with_writer_of(writer),
    ]
        .span()
}

fn world() -> WorldStorage {
    let mut world = spawn_test_world([namespace_def()].span());
    world.sync_perms_and_inits(contract_defs());
    set_caller_address(get_default_caller_address());
    world
}

fn address(world: @WorldStorage, name: @ByteArray) -> starknet::ContractAddress {
    let (address, _) = world.dns(name).unwrap();
    address
}

fn setup(world: @WorldStorage) -> ISetupDispatcher {
    ISetupDispatcher { contract_address: address(world, @"setup") }
}

fn goblins(world: @WorldStorage, instance_id: u32) -> Array<Goblin> {
    let mut out: Array<Goblin> = array![];
    let mut id: u32 = 1;
    while id != 9 {
        out.append(world.read_model((instance_id, id)));
        id += 1;
    }
    out
}

// ---------------------------------------------------------------------------------------------
// Worst-case tick

fn tick(world: @WorldStorage) -> ITickWorstCaseDispatcher {
    ITickWorstCaseDispatcher { contract_address: address(world, @"tick_worst_case") }
}

fn queue(world: @WorldStorage) -> IQueueMovesDispatcher {
    IQueueMovesDispatcher { contract_address: address(world, @"queue_moves") }
}

#[test]
#[available_gas(l2_gas: 64153252)] // ceil(1.05 × 61098335 measured)
fn test_tick_worst_case() {
    let world = world();
    setup(@world).worst_case(WORST);
    let before = goblins(@world, WORST);
    tick(@world).attack(WORST, 1);
    let after = goblins(@world, WORST);
    let adventurer: InstanceAdventurer = world.read_model((WORST, 1_u32));
    let instance: Instance = world.read_model(WORST);
    assert!(instance.clock == 1);
    // Goblin 1 was hit by the sword and burns; goblins 1 and 2 hit back and stay
    assert!(after[0].health < before[0].health);
    assert!(after[0].x == before[0].x && after[1].x == before[1].x);
    // The 6 far goblins each stepped closer
    let mut j: usize = 2;
    while j != 8 {
        assert!(after[j].x != before[j].x || after[j].y != before[j].y, "goblin {} idle", j + 1);
        j += 1;
    }
    // Two hits and 7 pips of bleeding and poison, minus 2 of regeneration
    assert!(adventurer.health < 480 - 10);
    assert!(adventurer.x == START_X && adventurer.y == START_Y);
}

#[test]
#[available_gas(l2_gas: 80290051)] // ceil(1.05 × 76466715 measured)
fn test_tick_worst_case_packed() {
    // The same action with the goblins in one model: the same outcome
    let world = world();
    setup(@world).worst_case(WORST);
    setup(@world).worst_case(WORST_PACKED);
    tick(@world).attack(WORST, 1);
    tick(@world).attack_packed(WORST_PACKED, 1);
    let pack: Pack = world.read_model(WORST_PACKED);
    let mut j: usize = 0;
    for goblin in goblins(@world, WORST) {
        let packed = unpack_goblin(WORST, goblin.id, *pack.goblins.span()[j]);
        assert!(packed == goblin, "goblin {} differs", j + 1);
        j += 1;
    }
    let lhs: InstanceAdventurer = world.read_model((WORST, 1_u32));
    let rhs: InstanceAdventurer = world.read_model((WORST_PACKED, 1_u32));
    assert!(lhs.health == rhs.health && lhs.energy == rhs.energy);
}

// ---------------------------------------------------------------------------------------------
// Queues of 10, 5 and 1 moves

#[test]
#[available_gas(l2_gas: 91921192)] // ceil(1.05 × 87543992 measured)
fn test_queue_moves() {
    let world = world();
    setup(@world).queue(QUEUE);
    let moves = array![WEST, WEST, WEST, WEST, WEST, WEST, WEST, WEST, WEST, WEST];
    let done = queue(@world).walk(QUEUE, moves);
    assert!(done == QUEUE_LENGTH, "stopped after {}", done);
    let adventurer: InstanceAdventurer = world.read_model((QUEUE, 1_u32));
    assert!(adventurer.x == START_X + QUEUE_LENGTH);
    let instance: Instance = world.read_model(QUEUE);
    assert!(instance.clock == QUEUE_LENGTH.into());
    // All 8 goblins followed and are still in the window (awake at every tick)
    for goblin in goblins(@world, QUEUE) {
        assert!(goblin.x > START_X + 3, "goblin {} left behind at {}", goblin.id, goblin.x);
    }
}

#[test]
#[available_gas(l2_gas: 76502876)] // ceil(1.05 × 72859881 measured)
fn test_queue_moves_5() {
    let world = world();
    setup(@world).queue(QUEUE_5);
    let done = queue(@world).walk(QUEUE_5, array![WEST, WEST, WEST, WEST, WEST]);
    assert!(done == 5);
}

#[test]
#[available_gas(l2_gas: 69986403)] // ceil(1.05 × 66653717 measured)
fn test_queue_moves_1() {
    let world = world();
    setup(@world).queue(QUEUE_1);
    let done = queue(@world).walk(QUEUE_1, array![WEST]);
    assert!(done == 1);
}

#[test]
#[available_gas(l2_gas: 68804432)] // ceil(1.05 × 65528030 measured)
fn test_queue_drops_an_invalid_move() {
    let world = world();
    setup(@world).queue(QUEUE);
    // North-East of (20, 21) is a pillar (20, 22): the queue is dropped, nothing reverts
    let done = queue(@world).walk(QUEUE, array![1, WEST, WEST]);
    assert!(done == 0);
    let instance: Instance = world.read_model(QUEUE);
    assert!(instance.clock == 0);
}

#[test]
#[available_gas(l2_gas: 70702120)] // ceil(1.05 × 67335352 measured)
fn test_queue_stops_when_hit() {
    let world = world();
    setup(@world).queue(QUEUE);
    // East, next to goblin 1 (18, 21): it hits during the tick, the queue stops
    let done = queue(@world).walk(QUEUE, array![0, WEST, WEST]);
    assert!(done == 1);
    let adventurer: InstanceAdventurer = world.read_model((QUEUE, 1_u32));
    assert!(adventurer.health < 480);
}

// ---------------------------------------------------------------------------------------------
// Brewing

fn brew(world: @WorldStorage) -> IBrewDispatcher {
    IBrewDispatcher { contract_address: address(world, @"brew") }
}

#[test]
#[available_gas(l2_gas: 43722608)] // ceil(1.05 × 41640579 measured)
fn test_brew_signed_discovers() {
    let world = world();
    setup(@world).alchemy();
    // Ingredients 8 and 9 are R + R: the signature holds exactly one recipe, found at once
    let result = brew(@world).brew(1, 1, 8, 9);
    assert!(result == 2 + 11, "R + R gives recipe 11, got {}", result);
    let grimoire: Grimoire = world.read_model((1_u32, 1_u32));
    assert!(grimoire.known == 0x800);
    let discovery: Discovery = world.read_model((1_u32, 1_u32, 16 * 8 + 9_u8));
    assert!(discovery.result == result);
    let ingredient: Balance = world.read_model((1_u32, 108_u32));
    assert!(ingredient.amount == 9);
}

#[test]
#[available_gas(l2_gas: 43117506)] // ceil(1.05 × 41064291 measured)
fn test_brew_unsigned_discovers() {
    let world = world();
    setup(@world).alchemy();
    let result = brew(@world).brew_unsigned(2, 1, 8, 9);
    assert!(result != 0);
    let grimoire: Grimoire = world.read_model((2_u32, 1_u32));
    assert!(grimoire.remaining == 44);
}

#[test]
#[available_gas(l2_gas: 46910669)] // ceil(1.05 × 44676827 measured)
fn test_brew_known_pair() {
    let world = world();
    setup(@world).alchemy();
    let first = brew(@world).brew(1, 1, 0, 5);
    let second = brew(@world).brew(1, 1, 0, 5);
    assert!(first == second);
    let grimoire: Grimoire = world.read_model((1_u32, 1_u32));
    // C + U: one untried pair less, once
    assert!(grimoire.remaining == 0x01_06_0a_03_0e_0a);
}

// ---------------------------------------------------------------------------------------------
// Hub actions of a day

fn hub(world: @WorldStorage) -> IHubDispatcher {
    IHubDispatcher { contract_address: address(world, @"hub") }
}

#[test]
#[available_gas(l2_gas: 45313173)] // ceil(1.05 × 43155402 measured)
fn test_hub_day() {
    let world = world();
    setup(@world).hub();
    let hub = hub(@world);
    hub.accept_quest(3, 1);
    let log: QuestLog = world.read_model((3_u32, 1_u32));
    assert!(log.status == 1);
    hub.claim_quest(3, 2);
    let log: QuestLog = world.read_model((3_u32, 2_u32));
    assert!(log.status == 2);
    let id = hub.enter(3, 10);
    assert!(id == 101);
    let adventurer: Adventurer = world.read_model(3_u32);
    assert!(adventurer.instance == 101 && adventurer.experience == 1500);
    let instance: Instance = world.read_model(101_u32);
    assert!(instance.entry_draw != 0);
    hub.leave(3);
    let adventurer: Adventurer = world.read_model(3_u32);
    assert!(adventurer.instance == 0);
    let instance: Instance = world.read_model(101_u32);
    assert!(instance.adventurer == 0);
}
