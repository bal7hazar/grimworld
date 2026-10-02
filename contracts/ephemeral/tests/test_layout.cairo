// The storage records of `Instances` are what docs/architecture/ENG-01-interfaces.md says: each
// record's size in slots and the bit offsets of every packed record, LIVE included. The variables'
// names and keys (their addresses) are checked in `store::layout_tests`; the tests of one model
// alone are in its module (D-167, ENG-R1b).
use grimworld_ephemeral::models::chunk::{Chunk, Features, Object, PackPlacement, Terrain};
use grimworld_ephemeral::models::goblin::{
    Goblin, GoblinState, GoblinTimers, MAX_ADRENALINE, empty_goblin_timers,
};
use grimworld_ephemeral::models::instance::Header;
use grimworld_ephemeral::models::member::{
    DeadlinesTrait, Effect, Member, MemberEffects, MemberState, MemberTimers, MemberTimersTrait,
    NO_SLOT, Recharges, flag,
};
use grimworld_logic::packing::LIVE;
use grimworld_logic::types::combat::activation;
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

// Records of several slots: a member is 8, a chunk 2, a goblin 2.
#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_record_sizes() {
    assert(starknet::Store::<Member>::size() == 8, 'member: 8 slots');
    assert(starknet::Store::<Chunk>::size() == 2, 'chunk: 2 slots');
    assert(starknet::Store::<Goblin>::size() == 2, 'goblin: 2 slots');
    assert(starknet::Store::<Header>::size() == 1, 'header: 1 slot');
}

#[test]
#[available_gas(l2_gas: 365873)] // ceil(1.05 × 348450 measured)
fn test_chunk_layout() {
    // Every tile a wall, every edge open: bit 228 is the last one used.
    let all: felt252 = 0x200000000000000000000000000000000000000000000000000000000 - 1;
    let terrain = Terrain { walls: all, edges: 15 };
    let word = StorePacking::<Terrain, felt252>::pack(terrain);
    assert(StorePacking::<Terrain, felt252>::unpack(word) == terrain, 'terrain trip');
    let edge = Terrain { walls: 0, edges: 1 };
    assert(StorePacking::<Terrain, felt252>::pack(edge) == all + 1 + LIVE, 'edges at bit 225');

    let pack = PackPlacement {
        tile: 224, template: 0xFFFF, level: 28, count: 5, offsets: 0x1FFFFFF, alert: 7,
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
// gas: raised, CBT-01: design/19 section 7.2's fields in the words
#[available_gas(l2_gas: 353409)] // ceil(1.05 × 336580 measured)
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
        effect_charges: 63,
        effect_rank: 15,
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

// Fix loop 1, F-9: every field narrower than its Cairo type is refused when too wide, at its
// boundary; nothing spills into a neighbouring lane.
#[test]
#[available_gas(l2_gas: 328272)] // ceil(1.05 × 312640 measured)
fn test_deadline_boundaries() {
    let max: u32 = 0xFFFFFFF;
    assert(
        DeadlinesTrait::pack(max, 0, 0, max) == 0xFFFFFFF + 0xFFFFFFF * 0x1000000000000000000000,
        'lanes',
    );
    let timers = MemberTimers { knocked: max, ..Default::default() };
    let word = StorePacking::<MemberTimers, felt252>::pack(timers);
    assert(StorePacking::<MemberTimers, felt252>::unpack(word) == timers, 'MAX_CLOCK fits');
    let pack = PackPlacement { count: 15, offsets: 0x1FFFFFF, alert: 7, ..Default::default() };
    let features = Features {
        packs: [pack, Default::default()],
        objects: [Default::default(), Default::default(), Default::default()],
        touched: 0,
    };
    let word = StorePacking::<Features, felt252>::pack(features);
    assert(StorePacking::<Features, felt252>::unpack(word) == features, 'widest pack');
}

#[test]
#[should_panic(expected: 'packing: deadline above 2^28')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_goblin_deadline_above_28_bits_refused() {
    let timers = GoblinTimers { poison: 0x10000000, ..Default::default() };
    StorePacking::<GoblinTimers, felt252>::pack(timers);
}

#[test]
#[should_panic(expected: 'packing: offsets above 25 bits')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_pack_offsets_refused() {
    let pack = PackPlacement { offsets: 0x2000000, ..Default::default() };
    let features = Features {
        packs: [pack, Default::default()],
        objects: [Default::default(), Default::default(), Default::default()],
        touched: 0,
    };
    StorePacking::<Features, felt252>::pack(features);
}

#[test]
#[should_panic(expected: 'packing: walls above bit 224')]
#[available_gas(l2_gas: 10385)] // ceil(1.05 × 9890 measured)
fn test_walls_above_224_refused() {
    let walls: felt252 = 0x200000000000000000000000000000000000000000000000000000000; // 2^225
    StorePacking::<Terrain, felt252>::pack(Terrain { walls, edges: 0 });
}

// Fix loop 3, F-14: empty timers are "no activation" (slot 255) and zero deadlines, not LIVE alone
// (slot 0 would name bar slot 0). Their packed words are pinned.
#[test]
// gas: raised, CBT-01: design/19 section 7.2's fields in the words
#[available_gas(l2_gas: 212174)] // ceil(1.05 × 202070 measured)
fn test_empty_timers_packed() {
    let member = MemberTimersTrait::empty();
    assert(member.act_slot == NO_SLOT, 'member: no slot');
    assert(StorePacking::<MemberTimers, felt252>::pack(member) == LIVE + 255, 'member word');
    let goblin = empty_goblin_timers();
    assert(StorePacking::<GoblinTimers, felt252>::pack(goblin) == LIVE + 255, 'goblin word');
    let effects = MemberEffects { effects: [Default::default(); 4] };
    assert(StorePacking::<MemberEffects, felt252>::pack(effects) == LIVE, 'empty effects');
    let recharges = Recharges { deadlines: [0; 8] };
    assert(StorePacking::<Recharges, felt252>::pack(recharges) == LIVE, 'empty recharges');
}

// design/19 §7.2 (CBT-01): what the combat adds to the words ENG-06 writes. `MemberState`:
// `casts_2` at 168, the flags "hit this tick" (bit 3) and "halving spent" (bit 4). An effect
// slot: charges 0–63 at slot bit 16, the potion tag at 23, the rank at 52. `GoblinTimers`: the
// effect's charges at 240 and rank at 246. The empty words keep their packed values.
#[test]
#[available_gas(l2_gas: 731441)] // ceil(1.05 × 696610 measured)
fn test_combat_fields_layout() {
    let casts = MemberState { casts_2: 1, ..Default::default() };
    let two_168: felt252 = TWO_128 * 0x10000000000;
    assert(StorePacking::<MemberState, felt252>::pack(casts) == two_168 + LIVE, 'casts_2 at 168');
    let flags = MemberState { flags: flag::HIT + flag::HALVED, ..Default::default() };
    let two_160: felt252 = TWO_128 * 0x100000000;
    assert(
        StorePacking::<MemberState, felt252>::pack(flags) == two_160 * 0x18 + LIVE, 'flags 3, 4',
    );
    assert(flag::TURNED == 1 && flag::INSTANT == 2, 'frozen flags');

    let slot = |effect: Effect| -> felt252 {
        let empty: Effect = Default::default();
        StorePacking::<
            MemberEffects, felt252,
        >::pack(MemberEffects { effects: [effect, empty, empty, empty] })
            - LIVE
    };
    assert(slot(Effect { charges: 1, ..Default::default() }) == 0x10000, 'charges at 16');
    assert(slot(Effect { potion: true, ..Default::default() }) == 0x800000, 'potion at 23');
    assert(slot(Effect { deadline: 1, ..Default::default() }) == 0x1000000, 'deadline at 24');
    assert(slot(Effect { rank: 1, ..Default::default() }) == 0x10000000000000, 'rank at 52');
    // The fourth slot's rank is the word's bits 236–239.
    let last = Effect { rank: 15, deadline: 0xFFFFFFF, ..Default::default() };
    let empty: Effect = Default::default();
    let word = StorePacking::<
        MemberEffects, felt252,
    >::pack(MemberEffects { effects: [empty, empty, empty, last] });
    let effects = StorePacking::<MemberEffects, felt252>::unpack(word);
    assert(effects == MemberEffects { effects: [empty, empty, empty, last] }, 'last slot trip');

    let charges = GoblinTimers { effect_charges: 1, ..Default::default() };
    let two_240: felt252 = TWO_128 * 0x10000000000000000000000000000;
    assert(
        StorePacking::<GoblinTimers, felt252>::pack(charges) == two_240 + LIVE, 'charges at 240',
    );
    let rank = GoblinTimers { effect_rank: 1, ..Default::default() };
    assert(
        StorePacking::<GoblinTimers, felt252>::pack(rank) == two_240 * 0x40 + LIVE, 'rank at 246',
    );
    assert(empty_goblin_timers().act_slot == activation::NONE, 'none is 255');
    assert(activation::NONE == 255 && activation::RECOVERING == 254, 'frozen states');
    assert(MAX_ADRENALINE == 252, '63 strikes');
}

#[test]
#[should_panic(expected: 'packing: charges above 63')]
#[available_gas(l2_gas: 27552)] // ceil(1.05 × 26240 measured)
fn test_goblin_effect_charges_refused() {
    let timers = GoblinTimers { effect_charges: 64, ..Default::default() };
    StorePacking::<GoblinTimers, felt252>::pack(timers);
}

#[test]
#[should_panic(expected: 'packing: rank above 15')]
#[available_gas(l2_gas: 27552)] // ceil(1.05 × 26240 measured)
fn test_goblin_effect_rank_refused() {
    let timers = GoblinTimers { effect_rank: 16, ..Default::default() };
    StorePacking::<GoblinTimers, felt252>::pack(timers);
}
