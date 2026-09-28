//! Part 1's system tests, on the native contracts. The budget covers the whole test (declare,
//! deploy, setup and action); the action alone is read from the trace
//! (`--trace-components contract-name gas`), see the report.

use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use spk2n::fixtures::{
    DEEP, MAZE, QUEUE, QUEUE_1, QUEUE_5, QUEUE_EMPTY, QUEUE_LENGTH, SEALED, SERPENT, START_X,
    START_Y, WEST, WORST, WORST_PACKED,
};
use spk2n::systems::hub::{IHubDispatcher, IHubDispatcherTrait};
use spk2n::systems::instances::{
    FELT, IInstancesDispatcher, IInstancesDispatcherTrait, PACKED, SLOTS,
};
use starknet::ContractAddress;

fn player() -> ContractAddress {
    'player'.try_into().unwrap()
}

#[derive(Copy, Drop)]
struct Game {
    hub: IHubDispatcher,
    instances: IInstancesDispatcher,
}

fn deploy() -> Game {
    let admin: felt252 = player().into();
    let (hub, _) = declare("Hub").unwrap().contract_class().deploy(@array![admin]).unwrap();
    let (instances, _) = declare("Instances")
        .unwrap()
        .contract_class()
        .deploy(@array![admin])
        .unwrap();
    let game = Game {
        hub: IHubDispatcher { contract_address: hub },
        instances: IInstancesDispatcher { contract_address: instances },
    };
    start_cheat_caller_address(hub, player());
    game.hub.set_instances(instances);
    stop_cheat_caller_address(hub);
    start_cheat_caller_address(instances, player());
    game.instances.set_hub(hub);
    stop_cheat_caller_address(instances);
    game
}

/// The player (also the admin) calls the instances contract only: calls it makes keep their
/// real caller.
fn as_player_instances(game: Game) {
    start_cheat_caller_address(game.instances.contract_address, player());
}

fn as_player_hub(game: Game) {
    start_cheat_caller_address(game.hub.contract_address, player());
}

fn done(game: Game) {
    stop_cheat_caller_address(game.instances.contract_address);
    stop_cheat_caller_address(game.hub.contract_address);
}

// ---------------------------------------------------------------------------------------------
// Worst-case tick
//
// Instances (fix loop 1, C-2): the controlled pair against part 1 runs unchecked (part 1's
// systems check no owner) on the same storage (one felt per goblin = part 1's packed goblin
// model); the checked runs are the production form; SLOTS is a layout experiment.

const WORST_FELT_CHECKED: u32 = 7;
const WORST_SLOTS_CHECKED: u32 = 15;
const WORST_PACKED_CHECKED: u32 = 16;
const QUEUE_SLOTS_CHECKED: u32 = 17;
const QUEUE_CHECKED: u32 = 18;
const QUEUE_5_CHECKED: u32 = 19;
const QUEUE_1_CHECKED: u32 = 20;
const QUEUE_EMPTY_CHECKED: u32 = 21;
const QUEUE_PACKED: u32 = 8;
const QUEUE_5_PACKED: u32 = 9;
const QUEUE_1_PACKED: u32 = 10;
const SERPENT_CHECKED: u32 = 25;

#[test]
#[available_gas(l2_gas: 49642587)] // ceil(1.05 × 47278654 measured)
fn test_tick_worst_case() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    let mut before = array![];
    let mut id: u32 = 1;
    while id != 9 {
        before.append(game.instances.goblin_felt(WORST, id));
        id += 1;
    }
    game.instances.attack(WORST, 1, FELT, false);
    done(game);
    let instance = game.instances.instance(WORST);
    assert!(instance.clock == 1);
    let a0 = game.instances.goblin_felt(WORST, 1);
    let a1 = game.instances.goblin_felt(WORST, 2);
    // Goblin 1 was hit by the sword and burns; goblins 1 and 2 hit back and stay
    assert!(a0.health < *before[0].health);
    assert!(a0.x == *before[0].x && a1.x == *before[1].x);
    // The 6 far goblins each stepped closer
    let mut id: u32 = 3;
    while id != 9 {
        let after = game.instances.goblin_felt(WORST, id);
        let b = before[id - 1];
        assert!(after.x != *b.x || after.y != *b.y, "goblin {} idle", id);
        id += 1;
    }
    let adventurer = game.instances.adventurer(WORST);
    assert!(adventurer.health < 480 - 10);
    assert!(adventurer.x == START_X && adventurer.y == START_Y);
}

#[test]
#[available_gas(l2_gas: 235708505)] // ceil(1.05 × 224484290 measured)
fn test_tick_worst_case_layouts() {
    // The same action on every layout, checked or not: the same outcome.
    // Calls, in order: FELT checked, SLOTS checked, PACKED unchecked, PACKED checked.
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    game.instances.setup_worst_case(WORST_FELT_CHECKED, player());
    game.instances.setup_worst_case(WORST_SLOTS_CHECKED, player());
    game.instances.setup_worst_case(WORST_PACKED, player());
    game.instances.setup_worst_case(WORST_PACKED_CHECKED, player());
    game.instances.attack(WORST, 1, FELT, false);
    game.instances.attack(WORST_FELT_CHECKED, 1, FELT, true);
    game.instances.attack(WORST_SLOTS_CHECKED, 1, SLOTS, true);
    game.instances.attack(WORST_PACKED, 1, PACKED, false);
    game.instances.attack(WORST_PACKED_CHECKED, 1, PACKED, true);
    done(game);
    let mut id: u32 = 1;
    while id != 9 {
        let felt = game.instances.goblin_felt(WORST, id);
        for other in array![
            game.instances.goblin_felt(WORST_FELT_CHECKED, id),
            game.instances.goblin(WORST_SLOTS_CHECKED, id),
            game.instances.goblin_packed(WORST_PACKED, id),
            game.instances.goblin_packed(WORST_PACKED_CHECKED, id),
        ] {
            assert!(felt.x == other.x && felt.y == other.y && felt.health == other.health);
        }
        id += 1;
    }
    let lhs = game.instances.adventurer(WORST);
    let rhs = game.instances.adventurer(WORST_PACKED_CHECKED);
    assert!(lhs.health == rhs.health && lhs.energy == rhs.energy);
}

#[test]
#[available_gas(l2_gas: 44366784)] // ceil(1.05 × 42254080 measured)
#[should_panic(expected: 'not the owner')]
fn test_tick_refuses_a_stranger() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    done(game);
    game.instances.attack(WORST, 1, FELT, true);
}

// ---------------------------------------------------------------------------------------------
// Queues of 10, 5 and 1 moves

fn west(n: u32) -> Array<u8> {
    let mut moves = array![];
    let mut i = 0;
    while i != n {
        moves.append(WEST);
        i += 1;
    }
    moves
}

#[test]
#[available_gas(l2_gas: 90161892)] // ceil(1.05 × 85868468 measured)
fn test_queue_moves() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    let moved = game.instances.walk(QUEUE, west(10), FELT, false);
    done(game);
    assert!(moved == QUEUE_LENGTH, "stopped after {}", moved);
    let adventurer = game.instances.adventurer(QUEUE);
    assert!(adventurer.x == START_X + QUEUE_LENGTH);
    assert!(game.instances.instance(QUEUE).clock == QUEUE_LENGTH.into());
    let mut id: u32 = 1;
    while id != 9 {
        let goblin = game.instances.goblin_felt(QUEUE, id);
        assert!(goblin.x > START_X + 3, "goblin {} left behind at {}", id, goblin.x);
        id += 1;
    }
}

#[test]
#[available_gas(l2_gas: 80709641)] // ceil(1.05 × 76866324 measured)
fn test_queue_moves_5() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_5, 8, player());
    assert!(game.instances.walk(QUEUE_5, west(5), FELT, false) == 5);
    done(game);
}

#[test]
#[available_gas(l2_gas: 75079595)] // ceil(1.05 × 71504376 measured)
fn test_queue_moves_1() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_1, 8, player());
    assert!(game.instances.walk(QUEUE_1, west(1), FELT, false) == 1);
    done(game);
}

#[test]
#[available_gas(l2_gas: 40429683)] // ceil(1.05 × 38504460 measured)
fn test_queue_moves_no_goblin() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_EMPTY, 0, player());
    assert!(game.instances.walk(QUEUE_EMPTY, west(10), FELT, false) == QUEUE_LENGTH);
    done(game);
}

#[test]
#[available_gas(l2_gas: 274067355)] // ceil(1.05 × 261016528 measured)
fn test_queue_moves_checked() {
    // Production form: calls in order 10, 5, 1 moves, 10 moves without goblin
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_CHECKED, 8, player());
    game.instances.setup_queue(QUEUE_5_CHECKED, 8, player());
    game.instances.setup_queue(QUEUE_1_CHECKED, 8, player());
    game.instances.setup_queue(QUEUE_EMPTY_CHECKED, 0, player());
    assert!(game.instances.walk(QUEUE_CHECKED, west(10), FELT, true) == QUEUE_LENGTH);
    assert!(game.instances.walk(QUEUE_5_CHECKED, west(5), FELT, true) == 5);
    assert!(game.instances.walk(QUEUE_1_CHECKED, west(1), FELT, true) == 1);
    assert!(game.instances.walk(QUEUE_EMPTY_CHECKED, west(10), FELT, true) == QUEUE_LENGTH);
    done(game);
}

#[test]
#[available_gas(l2_gas: 236572863)] // ceil(1.05 × 225307488 measured)
fn test_queue_moves_packed() {
    // Goblins packed per instance, checked: calls in order 10, 5, 1 moves
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_PACKED, 8, player());
    game.instances.setup_queue(QUEUE_5_PACKED, 8, player());
    game.instances.setup_queue(QUEUE_1_PACKED, 8, player());
    assert!(game.instances.walk(QUEUE_PACKED, west(10), PACKED, true) == QUEUE_LENGTH);
    assert!(game.instances.walk(QUEUE_5_PACKED, west(5), PACKED, true) == 5);
    assert!(game.instances.walk(QUEUE_1_PACKED, west(1), PACKED, true) == 1);
    done(game);
}

#[test]
#[available_gas(l2_gas: 185997742)] // ceil(1.05 × 177140706 measured)
fn test_queue_moves_slots() {
    // Layout experiment: one storage struct per goblin, 11 slots each, checked
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_SLOTS_CHECKED, 8, player());
    game.instances.setup_queue(QUEUE, 8, player());
    assert!(game.instances.walk(QUEUE_SLOTS_CHECKED, west(10), SLOTS, true) == QUEUE_LENGTH);
    assert!(game.instances.walk(QUEUE, west(10), FELT, false) == QUEUE_LENGTH);
    done(game);
    let mut id: u32 = 1;
    while id != 9 {
        let slots = game.instances.goblin(QUEUE_SLOTS_CHECKED, id);
        let felt = game.instances.goblin_felt(QUEUE, id);
        assert!(slots.x == felt.x && slots.y == felt.y);
        id += 1;
    }
}

#[test]
#[available_gas(l2_gas: 73871297)] // ceil(1.05 × 70353616 measured)
fn test_queue_drops_an_invalid_move() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    // North-East of (20, 21) is a pillar (20, 22): the queue is dropped, nothing reverts
    assert!(game.instances.walk(QUEUE, array![1, WEST, WEST], FELT, true) == 0);
    done(game);
    assert!(game.instances.instance(QUEUE).clock == 0);
}

#[test]
#[available_gas(l2_gas: 75231779)] // ceil(1.05 × 71649313 measured)
fn test_queue_stops_when_hit() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    // East, next to goblin 1 (18, 21): it hits during the tick, the queue stops
    assert!(game.instances.walk(QUEUE, array![0, WEST, WEST], FELT, true) == 1);
    done(game);
    assert!(game.instances.adventurer(QUEUE).health < 480);
}

// ---------------------------------------------------------------------------------------------
// Adversarial cases (fix loop 1, C-3), as part 1: controlled (one felt per goblin, unchecked)

#[test]
#[available_gas(l2_gas: 131432088)] // ceil(1.05 × 125173417 measured)
fn test_tick_adversarial_boards() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_board(MAZE, player());
    game.instances.setup_board(SEALED, player());
    game.instances.setup_board(DEEP, player());
    game.instances.attack(MAZE, 1, FELT, false);
    game.instances.attack(SEALED, 1, FELT, false);
    game.instances.attack(DEEP, 1, FELT, false);
    done(game);
    for i in array![MAZE, SEALED, DEEP] {
        assert!(game.instances.instance(i).clock == 1);
    }
}

#[test]
#[available_gas(l2_gas: 148572373)] // ceil(1.05 × 141497498 measured)
fn test_queue_serpent() {
    // The expensive valid queue: 10 moves, no stop; calls in order unchecked, checked
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_serpent(SERPENT, player());
    game.instances.setup_serpent(SERPENT_CHECKED, player());
    assert!(game.instances.walk(SERPENT, west(10), FELT, false) == QUEUE_LENGTH);
    assert!(game.instances.walk(SERPENT_CHECKED, west(10), FELT, true) == QUEUE_LENGTH);
    done(game);
}

// ---------------------------------------------------------------------------------------------
// Brewing

#[test]
#[available_gas(l2_gas: 19393960)] // ceil(1.05 × 18470438 measured)
fn test_brew_signed_discovers() {
    let game = deploy();
    as_player_hub(game);
    game.hub.setup_alchemy(player());
    // Ingredients 8 and 9 are R + R: the signature holds exactly one recipe, found at once
    let result = game.hub.brew(1, 1, 8, 9);
    done(game);
    assert!(result == 2 + 11, "R + R gives recipe 11, got {}", result);
    assert!(game.hub.grimoire(1, 1).known == 0x800);
    assert!(game.hub.discovery(1, 1, 16 * 8 + 9) == result);
    assert!(game.hub.balance(1, 108) == 9);
}

#[test]
#[available_gas(l2_gas: 19040688)] // ceil(1.05 × 18133988 measured)
fn test_brew_unsigned_discovers() {
    let game = deploy();
    as_player_hub(game);
    game.hub.setup_alchemy(player());
    let result = game.hub.brew_unsigned(2, 1, 8, 9);
    done(game);
    assert!(result != 0);
    assert!(game.hub.grimoire(2, 1).remaining == 44);
}

#[test]
#[available_gas(l2_gas: 19681986)] // ceil(1.05 × 18744748 measured)
fn test_brew_known_pair() {
    let game = deploy();
    as_player_hub(game);
    game.hub.setup_alchemy(player());
    let first = game.hub.brew(1, 1, 0, 5);
    let second = game.hub.brew(1, 1, 0, 5);
    done(game);
    assert!(first == second);
    // C + U: one untried pair less, once
    assert!(game.hub.grimoire(1, 1).remaining == 0x01_06_0a_03_0e_0a);
}

// ---------------------------------------------------------------------------------------------
// Hub actions of a day

#[test]
#[available_gas(l2_gas: 11071581)] // ceil(1.05 × 10544362 measured)
fn test_hub_day() {
    let game = deploy();
    as_player_hub(game);
    game.hub.setup_hub(player());
    game.hub.accept_quest(3, 1);
    assert!(game.hub.quest_log(3, 1) == (1, 0));
    game.hub.claim_quest(3, 2);
    assert!(game.hub.quest_log(3, 2) == (2, 10));
    let id = game.hub.enter(3, 10);
    done(game);
    assert!(id == 101);
    let adventurer = game.hub.adventurer(3);
    assert!(adventurer.instance == 101 && adventurer.experience == 1500);
    assert!(game.instances.entry_draw(101) != 0);
    as_player_instances(game);
    game.instances.leave(101);
    done(game);
    assert!(game.hub.adventurer(3).instance == 0);
    assert!(game.instances.instance(101).adventurer == 0);
}

#[test]
#[available_gas(l2_gas: 3603926)] // ceil(1.05 × 3432310 measured)
#[should_panic(expected: 'not the instances')]
fn test_results_only_from_the_instances() {
    let game = deploy();
    as_player_hub(game);
    game.hub.apply_results(3, 0);
}
