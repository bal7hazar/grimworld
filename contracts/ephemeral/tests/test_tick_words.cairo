// CBT-02: the world tick runs on the stored words (`grimworld_logic::types::tick`), whose offsets
// it repeats from ENG-01. These tests pin them against this package's packers, which own the
// layouts: every field the tick loads reads what the packer wrote, every field it stores lands
// where the unpacker reads it, and no other field moves. The constants it mirrors are these.
use grimworld_ephemeral::models::goblin::{
    ALERTED, ASLEEP, DEAD, ENGAGED, FLEEING, GoblinState, GoblinTimers, LOOTED, RETURNING, WATCH,
};
use grimworld_ephemeral::models::member::{
    DOWN, Effect, GONE, INSIDE, MemberEffects, MemberState, MemberTimers, NO_SLOT, Recharges, flag,
};
use grimworld_logic::models::goblin::{GoblinTrait, GoblinWords};
use grimworld_logic::models::member::{MemberTrait, MemberWords};
use grimworld_logic::snapshot::{MemberBar, MemberKit, MemberStats};
use grimworld_logic::types::combat::activation;
use grimworld_logic::types::tick::{
    CasteSheet, Content, ContentTrait, PotionSheet, SkillSheet, ai, flag as tick_flag, status,
};
use grimworld_logic::types::world::{Idle, TickTrait, WorldTrait};
use starknet::storage_access::StorePacking;

/// The member's bar is 301, 300, 7–12: `load` reads each skill's adrenaline cost (its cap).
fn bar_skills() -> Array<SkillSheet> {
    let mut skills = array![
        SkillSheet {
            id: 300,
            kind: 4,
            adrenaline: 0,
            activation: 1,
            recharge: 9,
            regen0: 1,
            regen12: 5,
            ..Default::default(),
        },
        SkillSheet {
            id: 301,
            kind: 1,
            adrenaline: 5,
            activation: 0,
            recharge: 4,
            regen0: 0,
            regen12: 0,
            ..Default::default(),
        },
    ];
    for id in 7..13_u16 {
        skills.append(SkillSheet { id, kind: 2, ..Default::default() });
    }
    skills
}

fn content() -> Content {
    Content {
        skills: bar_skills().span(),
        potions: array![PotionSheet { id: 4000, regen: -2, ..Default::default() }].span(),
        castes: array![
            CasteSheet {
                id: 12,
                health: 120,
                health_regen: 13,
                energy: 40,
                energy_regen: 3,
                weapon_ticks: 2,
                skills: [301, 300, 0, 0],
                ..Default::default(),
            },
        ]
            .span(),
    }
}

fn member_words() -> (MemberState, MemberTimers, MemberEffects, Recharges, MemberWords) {
    let state = MemberState {
        adventurer: 0xABCDEF,
        x: 101,
        y: 77,
        facing: 4,
        status: INSIDE,
        health: 321,
        energy: 44,
        adrenaline: 17,
        hits: 3,
        casts: 2,
        belt: [1, 2, 3, 4],
        flags: flag::TURNED + flag::HIT + flag::HALVED,
        casts_2: 1,
    };
    let timers = MemberTimers {
        act_slot: 6,
        act_target: 0x1234,
        act_tile: 1,
        act_deadline: 0xFFFFFF0,
        bleeding: 11,
        poison: 12,
        burning: 13,
        crippled: 14,
        knocked: 15,
    };
    let effects = MemberEffects {
        effects: [
            Effect { skill: 300, charges: 5, potion: false, deadline: 90, rank: 12 },
            Effect { skill: 2, charges: 0, potion: true, deadline: 0xFFFFFFF, rank: 0 },
            Default::default(),
            Effect { skill: 301, charges: 63, potion: false, deadline: 7, rank: 15 },
        ],
    };
    let recharges = Recharges { deadlines: [1, 2, 3, 4, 5, 6, 7, 0xFFFFFFF] };
    let stats = MemberStats {
        max_health: 480, max_energy: 25, energy_regen: 3, health_regen: 12, ..Default::default(),
    };
    let bar = MemberBar {
        skills: [301, 300, 7, 8, 9, 10, 11, 12],
        elite_slot: 255,
        damage: [0; 6],
        penetration: [0; 3],
        quick_cast: [Default::default(), Default::default()],
        armor: 0,
    };
    let kit = MemberKit { belt: [3999, 4001, 4000, 4002], ..Default::default() };
    let words = MemberWords {
        state: StorePacking::pack(state),
        timers: StorePacking::pack(timers),
        effects: StorePacking::pack(effects),
        recharges: StorePacking::pack(recharges),
        stats: StorePacking::pack(stats),
        bar: StorePacking::pack(bar),
        kit: StorePacking::pack(kit),
    };
    (state, timers, effects, recharges, words)
}

// The constants the tick mirrors are this package's.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_tick_constants() {
    assert(status::INSIDE == INSIDE && status::DOWN == DOWN && status::GONE == GONE, 'status');
    assert(ai::ASLEEP == ASLEEP && ai::WATCH == WATCH && ai::ALERTED == ALERTED, 'ai');
    assert(ai::ENGAGED == ENGAGED && ai::FLEEING == FLEEING && ai::RETURNING == RETURNING, 'ai');
    assert(ai::DEAD == DEAD && ai::LOOTED == LOOTED, 'ai');
    assert(tick_flag::TURNED == flag::TURNED && tick_flag::INSTANT == flag::INSTANT, 'flags');
    assert(tick_flag::HIT == flag::HIT && tick_flag::HALVED == flag::HALVED, 'flags');
    assert(grimworld_logic::types::tick::NO_SLOT == NO_SLOT, 'no slot');
}

// A member: `load` reads every hot field the packers wrote, the snapshot's maxima and
// regeneration, the effects' deadlines and pips; `store` writes the changed fields where the
// unpackers read them, and every other field of the four words is kept.
#[test]
// gas: raised, the load reads through the content's index, built first (CBT-02d)
#[available_gas(l2_gas: 1384488)] // ceil(1.05 × 1318560 measured)
fn test_tick_words_member() {
    let (state, timers, effects, recharges, words) = member_words();
    let (sheets, mut index) = content().index();
    let mut member = MemberTrait::load(words, ref index, @sheets);
    assert(member.status == INSIDE && member.health == 321, 'state');
    assert(member.energy == 44 && member.adrenaline == 17 && member.flags == state.flags, 'state');
    assert(member.act_slot == 6 && member.act_target == 0x1234 && member.act_tile == 1, 'act');
    assert(member.act_deadline == 0xFFFFFF0, 'deadline');
    assert(member.bleeding == 11 && member.poison == 12, 'conditions');
    assert(member.burning == 13 && member.knocked == 15, 'conditions');
    assert(member.effect_deadlines == [90, 0xFFFFFFF, 0, 7], 'effect deadlines');
    // Skill 300 at rank 12: 5; belt slot 2 holds item 4000: −2; skill 301: 0.
    assert(member.effect_regen == [5, -2, 0, 0], 'effect pips');
    assert(member.max_health == 480 && member.max_energy == 75, 'maxima');
    assert(member.health_regen == 2 && member.energy_regen == 3, 'regeneration');
    assert(member.skill(0) == 301 && member.skill(7) == 12, 'bar');
    for slot in 0..8_u8 {
        assert(member.recharge(slot) == *recharges.deadlines.span()[slot.into()], 'recharges');
    }
    assert(member.store() == words, 'unchanged: same words');
    // Every hot field changed, and a recharge.
    member.status = DOWN;
    member.health = 0;
    member.energy = 75;
    member.adrenaline = 0;
    member.flags = flag::HALVED;
    member.act_slot = NO_SLOT;
    member.act_target = 0;
    member.act_tile = 0;
    member.act_deadline = 0;
    member.bleeding = 0xFFFFFFF;
    member.poison = 0;
    member.burning = 1;
    member.knocked = 99;
    member.set_recharge(5, 777);
    let stored = member.store();
    let state_after: MemberState = StorePacking::unpack(stored.state);
    assert(
        state_after == MemberState {
            status: DOWN, health: 0, energy: 75, adrenaline: 0, flags: flag::HALVED, ..state,
        },
        'state stored',
    );
    let timers_after: MemberTimers = StorePacking::unpack(stored.timers);
    assert(
        timers_after == MemberTimers {
            act_slot: NO_SLOT,
            act_target: 0,
            act_tile: 0,
            act_deadline: 0,
            bleeding: 0xFFFFFFF,
            poison: 0,
            burning: 1,
            knocked: 99,
            ..timers,
        },
        'timers stored',
    );
    let recharges_after: Recharges = StorePacking::unpack(stored.recharges);
    assert(recharges_after.deadlines == [1, 2, 3, 4, 5, 777, 7, 0xFFFFFFF], 'recharge stored');
    assert(stored.effects == words.effects && stored.stats == words.stats, 'others kept');
    let effects_after: MemberEffects = StorePacking::unpack(stored.effects);
    assert(effects_after == effects, 'effects kept');
}

// AUD-182-1: a potion's effect regenerates from each of the four belt slots, slot 0 included (its
// skill field 0 with the potion tag is a belt slot, not an empty slot): packed, loaded, ticked.
#[test]
#[available_gas(l2_gas: 3128415)] // ceil(1.05 × 2979442 measured), kept: 3007552 now
fn test_potion_regeneration_every_belt_slot() {
    let potions = array![
        PotionSheet { id: 4000, regen: 1, ..Default::default() },
        PotionSheet { id: 4001, regen: 2, ..Default::default() },
        PotionSheet { id: 4002, regen: 3, ..Default::default() },
        PotionSheet { id: 4003, regen: 4, ..Default::default() },
    ];
    let content = Content {
        skills: bar_skills().span(), potions: potions.span(), castes: array![].span(),
    };
    let (sheets, mut index) = content.index();
    let (state, _, _, recharges, words) = member_words();
    let timers = MemberTimers { act_slot: NO_SLOT, ..Default::default() };
    let kit = MemberKit { belt: [4000, 4001, 4002, 4003], ..Default::default() };
    for slot in 0..4_u16 {
        let effects = MemberEffects {
            effects: [
                Effect { skill: slot, charges: 0, potion: true, deadline: 90, rank: 0 },
                Default::default(), Default::default(), Default::default(),
            ],
        };
        let words = MemberWords {
            timers: StorePacking::pack(timers),
            effects: StorePacking::pack(effects),
            recharges: StorePacking::pack(recharges),
            kit: StorePacking::pack(kit),
            ..words,
        };
        let member = MemberTrait::load(words, ref index, @sheets);
        let pips: i8 = (slot + 1).try_into().unwrap();
        assert(member.effect_regen == [pips, 0, 0, 0], 'belt slot pips');
        let mut world = WorldTrait::new(10, array![member], array![], array![], false);
        let mut rules = Idle {};
        TickTrait::run(ref world, @sheets, 1, ref rules);
        // Health regeneration +2 pips (stored 12) and the potion's.
        let expected: u16 = state.health + 2 * (2 + slot + 1);
        assert(world.member(0).health == expected, 'belt slot regenerates');
    }
}

// A goblin: the same for its two words, its caste's derived fields and its effect's pips.
#[test]
// gas: raised, the load reads through the content's index, built first (CBT-02d)
#[available_gas(l2_gas: 613851)] // ceil(1.05 × 584620 measured)
fn test_tick_words_goblin() {
    let state = GoblinState {
        x: 200,
        y: 13,
        facing: 2,
        ai: ALERTED,
        health: 250,
        energy: 100,
        adrenaline: 252,
        caste: 12,
        level: 18,
        target: 0,
        memory_x: 9,
        memory_y: 10,
        flags: 0xA5,
        recharges: [0xFFFFFFF, 2, 3, 4],
    };
    let timers = GoblinTimers {
        act_slot: 1,
        act_target: 0xBEEF,
        act_deadline: 0xFFFFFF0,
        bleeding: 21,
        poison: 22,
        effect_skill: 300,
        burning: 23,
        crippled: 24,
        knocked: 25,
        effect_deadline: 26,
        effect_charges: 63,
        effect_rank: 6,
    };
    let words = GoblinWords {
        entity: 3593,
        awake: true,
        state: StorePacking::pack(state),
        timers: StorePacking::pack(timers),
    };
    let (sheets, mut index) = content().index();
    let mut goblin = GoblinTrait::load(words, ref index, @sheets);
    assert(goblin.entity == 3593 && goblin.awake && goblin.ai == ALERTED, 'identity');
    assert(goblin.health == 250 && goblin.energy == 100 && goblin.adrenaline == 252, 'state');
    assert(goblin.caste == 12 && goblin.act_slot == 1 && goblin.act_target == 0xBEEF, 'act');
    assert(goblin.act_deadline == 0xFFFFFF0, 'deadline');
    assert(goblin.bleeding == 21 && goblin.poison == 22 && goblin.burning == 23, 'conditions');
    assert(goblin.knocked == 25 && goblin.effect_deadline == 26, 'deadlines');
    // (80 + 20 × 18) × 120 / 100 = 528; skill 300 at rank 6: 1 + 4 × 6 / 12 = 3.
    assert(goblin.max_health == 528 && goblin.health_regen == 3, 'health');
    assert(goblin.max_energy == 120 && goblin.energy_regen == 3, 'energy');
    assert(goblin.effect_regen == 3, 'effect pips');
    for slot in 0..4_u8 {
        assert(goblin.recharge(slot) == *state.recharges.span()[slot.into()], 'recharges');
    }
    assert(goblin.store() == words, 'unchanged: same words');
    goblin.ai = DEAD;
    goblin.health = 0;
    goblin.energy = 0;
    goblin.adrenaline = 0;
    goblin.act_slot = activation::RECOVERING;
    goblin.act_target = 0;
    goblin.act_deadline = 5;
    goblin.bleeding = 0;
    goblin.poison = 0xFFFFFFF;
    goblin.burning = 0;
    goblin.knocked = 1;
    goblin.effect_deadline = 0;
    goblin.set_recharge(2, 999);
    let stored = goblin.store();
    let state_after: GoblinState = StorePacking::unpack(stored.state);
    assert(
        state_after == GoblinState {
            ai: DEAD,
            health: 0,
            energy: 0,
            adrenaline: 0,
            recharges: [0xFFFFFFF, 2, 999, 4],
            ..state,
        },
        'state stored',
    );
    let timers_after: GoblinTimers = StorePacking::unpack(stored.timers);
    assert(
        timers_after == GoblinTimers {
            act_slot: activation::RECOVERING,
            act_target: 0,
            act_deadline: 5,
            bleeding: 0,
            poison: 0xFFFFFFF,
            burning: 0,
            knocked: 1,
            effect_deadline: 0,
            ..timers,
        },
        'timers stored',
    );
}
