// The storage records of `Instances` are what docs/architecture/ENG-01-interfaces.md says: each
// record's size in slots and the bit offsets of every packed record, LIVE included. The variables'
// names and keys (their addresses) are checked in `systems::instances::layout_tests`.
use grimworld_ephemeral::models::chunk::{Chunk, Features, Object, PackPlacement, Terrain};
use grimworld_ephemeral::models::goblin::{Goblin, GoblinState, GoblinTimers};
use grimworld_ephemeral::models::instance::{Header, Placement, Quotas};
use grimworld_ephemeral::models::member::{
    Effect, Member, MemberEffects, MemberState, MemberTimers, Recharges,
};
use grimworld_logic::packing::LIVE;
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

// Records of several slots: a member is 8, a chunk 2, a goblin 2.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_record_sizes() {
    assert(starknet::Store::<Member>::size() == 8, 'member: 8 slots');
    assert(starknet::Store::<Chunk>::size() == 2, 'chunk: 2 slots');
    assert(starknet::Store::<Goblin>::size() == 2, 'goblin: 2 slots');
    assert(starknet::Store::<Header>::size() == 1, 'header: 1 slot');
}

#[test]
#[available_gas(l2_gas: 467166)] // ceil(1.05 × 444920 measured)
fn test_placement_and_header_layout() {
    let placement = Placement { slot: 0xFFFFFFFF, generation: 0xFFFFFFFF, member: 7, inside: 1 };
    let word = StorePacking::<Placement, felt252>::pack(placement);
    assert(StorePacking::<Placement, felt252>::unpack(word) == placement, 'placement trip');
    let inside = Placement { inside: 1, ..Default::default() };
    assert(
        StorePacking::<Placement, felt252>::pack(inside) == 0x1000000000000000000 + LIVE,
        'inside at bit 72',
    );

    let header = Header {
        generation: 0xFFFFFFFF,
        sequence: 1,
        clock: 0xFFFFFFF,
        location: 0xFFFF,
        status: 3,
        members: 1,
        tasks: 16,
        revealed_count: 225,
        roster_count: 30,
        flags: 1,
        entry_chunk: 224,
        entry_tile: 224,
        gate: 0xFFFF,
    };
    let word = StorePacking::<Header, felt252>::pack(header);
    assert(StorePacking::<Header, felt252>::unpack(word) == header, 'header trip');
    let one = Header { sequence: 1, tasks: 1, gate: 1, ..Default::default() };
    let expected = 0x100000000 + TWO_128 + 0x1000000000000 * TWO_128 + LIVE;
    assert(
        StorePacking::<Header, felt252>::pack(one) == expected, 'sequence 32 tasks 128 gate 176',
    );
    assert(StorePacking::<Header, felt252>::pack(Default::default()) == LIVE, 'never 0');

    let quotas = Quotas {
        target: 12, open_edges: 3, left: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0xFF],
    };
    let word = StorePacking::<Quotas, felt252>::pack(quotas);
    assert(StorePacking::<Quotas, felt252>::unpack(word) == quotas, 'quotas trip');
}

#[test]
#[available_gas(l2_gas: 475587)] // ceil(1.05 × 452940 measured)
fn test_member_layout() {
    let state = MemberState {
        adventurer: 0xFFFFFFFF,
        x: 224,
        y: 224,
        facing: 5,
        status: 2,
        health: 0xFFFF,
        energy: 0xFFFF,
        adrenaline: 0xFFFF,
        hits: 0xFF,
        casts: 0xFF,
        belt: [1, 2, 3, 0xFF],
        flags: 3,
    };
    let word = StorePacking::<MemberState, felt252>::pack(state);
    assert(StorePacking::<MemberState, felt252>::unpack(word) == state, 'state trip');
    let health = MemberState { health: 1, ..Default::default() };
    assert(
        StorePacking::<MemberState, felt252>::pack(health) == 0x10000000000000000 + LIVE,
        'health at bit 64',
    );

    let timers = MemberTimers {
        act_slot: 255,
        act_target: 0xFFFF,
        act_tile: 1,
        act_deadline: 0xFFFFFFF,
        bleeding: 1,
        poison: 2,
        burning: 3,
        crippled: 4,
        knocked: 0xFFFFFFF,
    };
    let word = StorePacking::<MemberTimers, felt252>::pack(timers);
    assert(StorePacking::<MemberTimers, felt252>::unpack(word) == timers, 'timers trip');
    let knocked = MemberTimers { knocked: 1, ..Default::default() };
    assert(
        StorePacking::<MemberTimers, felt252>::pack(knocked) == 0x10000000000000000 * TWO_128
            + LIVE,
        'knocked at bit 192',
    );

    let full = Effect { skill: 0xFFFF, charges: 0xFF, deadline: 0xFFFFFFF };
    let effects = MemberEffects {
        effects: [full, Effect { skill: 1, charges: 2, deadline: 3 }, full, full],
    };
    let word = StorePacking::<MemberEffects, felt252>::pack(effects);
    assert(StorePacking::<MemberEffects, felt252>::unpack(word) == effects, 'effects trip');

    let recharges = Recharges { deadlines: [0xFFFFFFF, 1, 2, 3, 4, 5, 6, 0xFFFFFFF] };
    let word = StorePacking::<Recharges, felt252>::pack(recharges);
    assert(StorePacking::<Recharges, felt252>::unpack(word) == recharges, 'recharges trip');
    let slot4 = Recharges { deadlines: [0, 0, 0, 0, 1, 0, 0, 0] };
    assert(StorePacking::<Recharges, felt252>::pack(slot4) == TWO_128 + LIVE, 'slot 4 at bit 128');
}

#[test]
#[available_gas(l2_gas: 329091)] // ceil(1.05 × 313420 measured)
fn test_chunk_layout() {
    // Every tile a wall, every edge open: bit 228 is the last one used.
    let all: felt252 = 0x200000000000000000000000000000000000000000000000000000000 - 1;
    let terrain = Terrain { walls: all, edges: 15 };
    let word = StorePacking::<Terrain, felt252>::pack(terrain);
    assert(StorePacking::<Terrain, felt252>::unpack(word) == terrain, 'terrain trip');
    let edge = Terrain { walls: 0, edges: 1 };
    assert(StorePacking::<Terrain, felt252>::pack(edge) == all + 1 + LIVE, 'edges at bit 225');

    let pack = PackPlacement {
        tile: 224, template: 0xFFFF, level: 28, count: 5, offsets: 0x1FFFFFF,
    };
    let object = Object { tile: 224, kind: 7, state: 1, param: 0xFFFF };
    let features = Features {
        packs: [pack, pack], objects: [object, object, object], touched: 0x3FF,
    };
    let word = StorePacking::<Features, felt252>::pack(features);
    assert(StorePacking::<Features, felt252>::unpack(word) == features, 'features trip');
    let touched = Features {
        packs: [Default::default(), Default::default()],
        objects: [Default::default(), Default::default(), Default::default()],
        touched: 1,
    };
    assert(
        StorePacking::<Features, felt252>::pack(touched) == 0x1000000000000000000000000 * TWO_128
            + LIVE,
        'touched at bit 224',
    );
}

#[test]
#[available_gas(l2_gas: 318623)] // ceil(1.05 × 303450 measured)
fn test_goblin_layout() {
    let state = GoblinState {
        x: 224,
        y: 224,
        facing: 5,
        ai: 7,
        health: 0xFFFF,
        energy: 0xFF,
        adrenaline: 0xFF,
        caste: 0xFFFF,
        level: 28,
        target: 0xFFFF,
        memory_x: 224,
        memory_y: 224,
        flags: 0xFF,
        recharges: [0xFFFFFFF, 1, 2, 0xFFFFFFF],
    };
    let word = StorePacking::<GoblinState, felt252>::pack(state);
    assert(StorePacking::<GoblinState, felt252>::unpack(word) == state, 'state trip');
    let caste = GoblinState { caste: 1, ..Default::default() };
    assert(
        StorePacking::<GoblinState, felt252>::pack(caste) == 0x10000000000000000 + LIVE,
        'caste at bit 64',
    );

    let timers = GoblinTimers {
        act_slot: 255,
        act_target: 0xFFFF,
        act_deadline: 0xFFFFFFF,
        bleeding: 0xFFFFFFF,
        poison: 0xFFFFFFF,
        effect_skill: 0xFFFF,
        burning: 1,
        crippled: 2,
        knocked: 3,
        effect_deadline: 0xFFFFFFF,
    };
    let word = StorePacking::<GoblinTimers, felt252>::pack(timers);
    assert(StorePacking::<GoblinTimers, felt252>::unpack(word) == timers, 'timers trip');
    let effect = GoblinTimers { effect_skill: 1, ..Default::default() };
    assert(
        StorePacking::<GoblinTimers, felt252>::pack(effect) == 0x1000000000000000000000000000
            + LIVE,
        'effect skill at bit 108',
    );
}
