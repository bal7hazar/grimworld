//! Part 1's system tests, on the native contracts. The budget covers the whole test (declare,
//! deploy, setup and action); the action alone is read from the trace
//! (`--trace-components contract-name gas`), see the report.

use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use spk2n::fixtures::{
    QUEUE, QUEUE_1, QUEUE_5, QUEUE_EMPTY, QUEUE_LENGTH, START_X, START_Y, WEST, WORST, WORST_PACKED,
};
use spk2n::systems::hub::{IHubDispatcher, IHubDispatcherTrait};
use spk2n::systems::instances::{IInstancesDispatcher, IInstancesDispatcherTrait};
use starknet::ContractAddress;

/// One more instance for the one-felt-per-goblin layout.
const WORST_FELT: u32 = 7;

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

#[test]
#[available_gas(l2_gas: 59463636)] // ceil(1.05 × 56632034 measured)
fn test_tick_worst_case() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    let mut before = array![];
    let mut id: u32 = 1;
    while id != 9 {
        before.append(game.instances.goblin(WORST, id));
        id += 1;
    }
    game.instances.attack(WORST, 1);
    done(game);
    let instance = game.instances.instance(WORST);
    assert!(instance.clock == 1);
    let a0 = game.instances.goblin(WORST, 1);
    let a1 = game.instances.goblin(WORST, 2);
    // Goblin 1 was hit by the sword and burns; goblins 1 and 2 hit back and stay
    assert!(a0.health < *before[0].health);
    assert!(a0.x == *before[0].x && a1.x == *before[1].x);
    // The 6 far goblins each stepped closer
    let mut id: u32 = 3;
    while id != 9 {
        let after = game.instances.goblin(WORST, id);
        let b = before[id - 1];
        assert!(after.x != *b.x || after.y != *b.y, "goblin {} idle", id);
        id += 1;
    }
    let adventurer = game.instances.adventurer(WORST);
    assert!(adventurer.health < 480 - 10);
    assert!(adventurer.x == START_X && adventurer.y == START_Y);
}

#[test]
#[available_gas(l2_gas: 146111083)] // ceil(1.05 × 139153412 measured)
fn test_tick_worst_case_layouts() {
    // The same action on the three goblin layouts: the same outcome
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    game.instances.setup_worst_case(WORST_FELT, player());
    game.instances.setup_worst_case(WORST_PACKED, player());
    game.instances.attack(WORST, 1);
    game.instances.attack_felt(WORST_FELT, 1);
    game.instances.attack_packed(WORST_PACKED, 1);
    done(game);
    let mut id: u32 = 1;
    while id != 9 {
        let slots = game.instances.goblin(WORST, id);
        let felt = game.instances.goblin_felt(WORST_FELT, id);
        let packed = game.instances.goblin_packed(WORST_PACKED, id);
        assert!(slots.x == felt.x && slots.y == felt.y && slots.health == felt.health);
        assert!(slots.x == packed.x && slots.y == packed.y && slots.health == packed.health);
        id += 1;
    }
    let lhs = game.instances.adventurer(WORST);
    let rhs = game.instances.adventurer(WORST_PACKED);
    assert!(lhs.health == rhs.health && lhs.energy == rhs.energy);
}

#[test]
#[available_gas(l2_gas: 43658969)] // ceil(1.05 × 41579970 measured)
#[should_panic(expected: 'not the owner')]
fn test_tick_refuses_a_stranger() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_worst_case(WORST, player());
    done(game);
    game.instances.attack(WORST, 1);
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
#[available_gas(l2_gas: 86219163)] // ceil(1.05 × 82113488 measured)
fn test_queue_moves() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    let moved = game.instances.walk(QUEUE, west(10));
    done(game);
    assert!(moved == QUEUE_LENGTH, "stopped after {}", moved);
    let adventurer = game.instances.adventurer(QUEUE);
    assert!(adventurer.x == START_X + QUEUE_LENGTH);
    assert!(game.instances.instance(QUEUE).clock == QUEUE_LENGTH.into());
    let mut id: u32 = 1;
    while id != 9 {
        let goblin = game.instances.goblin(QUEUE, id);
        assert!(goblin.x > START_X + 3, "goblin {} left behind at {}", id, goblin.x);
        id += 1;
    }
}

#[test]
#[available_gas(l2_gas: 159066512)] // ceil(1.05 × 151491916 measured)
fn test_queue_moves_packed() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    game.instances.setup_queue(QUEUE_5, 8, player());
    assert!(game.instances.walk_packed(QUEUE, west(10)) == QUEUE_LENGTH);
    // The same outcome as the per-goblin layout
    assert!(game.instances.walk(QUEUE_5, west(10)) == QUEUE_LENGTH);
    done(game);
    let mut id: u32 = 1;
    while id != 9 {
        let packed = game.instances.goblin_packed(QUEUE, id);
        let slots = game.instances.goblin(QUEUE_5, id);
        assert!(packed.x == slots.x && packed.y == slots.y);
        id += 1;
    }
}

#[test]
#[available_gas(l2_gas: 124016036)] // ceil(1.05 × 118110510 measured)
fn test_queue_moves_packed_short() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_5, 8, player());
    game.instances.setup_queue(QUEUE_1, 8, player());
    assert!(game.instances.walk_packed(QUEUE_5, west(5)) == 5);
    assert!(game.instances.walk_packed(QUEUE_1, west(1)) == 1);
    done(game);
}

#[test]
#[available_gas(l2_gas: 75257642)] // ceil(1.05 × 71673944 measured)
fn test_queue_moves_5() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_5, 8, player());
    assert!(game.instances.walk(QUEUE_5, west(5)) == 5);
    done(game);
}

#[test]
#[available_gas(l2_gas: 69205496)] // ceil(1.05 × 65909996 measured)
fn test_queue_moves_1() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_1, 8, player());
    assert!(game.instances.walk(QUEUE_1, west(1)) == 1);
    done(game);
}

#[test]
#[available_gas(l2_gas: 26520669)] // ceil(1.05 × 25257780 measured)
fn test_queue_moves_no_goblin() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE_EMPTY, 0, player());
    assert!(game.instances.walk(QUEUE_EMPTY, west(10)) == QUEUE_LENGTH);
    done(game);
}

#[test]
#[available_gas(l2_gas: 65001737)] // ceil(1.05 × 61906416 measured)
fn test_queue_drops_an_invalid_move() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    // North-East of (20, 21) is a pillar (20, 22): the queue is dropped, nothing reverts
    assert!(game.instances.walk(QUEUE, array![1, WEST, WEST]) == 0);
    done(game);
    assert!(game.instances.instance(QUEUE).clock == 0);
}

#[test]
#[available_gas(l2_gas: 68472719)] // ceil(1.05 × 65212113 measured)
fn test_queue_stops_when_hit() {
    let game = deploy();
    as_player_instances(game);
    game.instances.setup_queue(QUEUE, 8, player());
    // East, next to goblin 1 (18, 21): it hits during the tick, the queue stops
    assert!(game.instances.walk(QUEUE, array![0, WEST, WEST]) == 1);
    done(game);
    assert!(game.instances.adventurer(QUEUE).health < 480);
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
