// CBT-02: the world tick's pipeline (design/02 *The tick*, design/19 §5). The worked examples of
// design/19 §10 whose steps are the pipeline's (10.1's step 3, 10.2, 10.3, 10.5, 10.6, 10.9),
// every rule of the steps one by one, determinism, and the cost of a tick on representative and
// worst states, against the expedition's target of 1,469,435 L2 gas a tick inside a batch
// (docs/architecture/cost-budget.md §2, D-159). The words are built here from ENG-01's offsets;
// the ephemeral package's `test_tick_words` pins `load` and `store` against its packers.
use grimworld_logic::content::Record;
use grimworld_logic::interface::{ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::index::{Caste, Item, Skill};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class as item_class};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::tick::{GoblinTickTrait, Idle, MemberTickTrait, Rules, TickTrait, WorldTrait};
use grimworld_logic::types::MAX_CLOCK;
use grimworld_logic::types::combat::{activation, skill_kind, weapon};
use grimworld_logic::types::effect::{EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::tick::{
    Actor, CasteSheet, CasteSheetTrait, Content, Goblin, GoblinTrait, GoblinWords, Member,
    MemberTrait, MemberWords, NO_SLOT, PotionSheet, PotionSheetTrait, SkillSheet, SkillSheetTrait,
    Words, WordsTrait, World, WorldStoreTrait, ai, flag, status,
};
use snforge_std::{DeclareResultTrait, declare};

const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
/// Castes of the fixtures; caste `c`'s skills are `20 + 4 c + slot`.
const HOB: u16 = 1;
const RUNT: u16 = 2;
const SMASH: u16 = 24;

/// `2^n` (fixtures only: the benchmarks subtract the fixtures' cost).
fn two(n: u32) -> felt252 {
    let mut p: felt252 = 1;
    for _ in 0..n {
        p *= 2;
    }
    p
}

/// A member's hot fields and derived ones.
#[derive(Copy, Drop)]
struct MemberSpec {
    health: u16,
    energy: u16,
    adrenaline: u16,
    flags: u8,
    status: u8,
    /// Bleeding, poison, burning, knocked.
    conditions: [u32; 4],
    /// `(carrier, potion, deadline, rank)` of each effect slot.
    effects: [(u16, bool, u32, u8); 4],
    effect_regen: [i8; 4],
    health_regen: i8,
    energy_regen: u8,
}

#[generate_trait]
impl FixtureImpl of Fixture {
    fn spec() -> MemberSpec {
        MemberSpec {
            health: 400,
            energy: 30,
            adrenaline: 0,
            flags: 0,
            status: status::INSIDE,
            conditions: [0; 4],
            effects: [(0, false, 0, 0); 4],
            effect_regen: [0; 4],
            health_regen: 0,
            energy_regen: 2,
        }
    }

    /// The words of a member (ENG-01 §3.2 offsets): max health 480, max energy 20, no activation,
    /// bar 1–8, belt items 100–103.
    fn member_words(spec: MemberSpec) -> MemberWords {
        let state = LIVE
            + spec.status.into() * two(56)
            + spec.health.into() * two(64)
            + spec.energy.into() * two(80)
            + spec.adrenaline.into() * two(96)
            + spec.flags.into() * two(160);
        let [bleeding, poison, burning, knocked] = spec.conditions;
        let timers = LIVE
            + NO_SLOT.into()
            + bleeding.into() * two(64)
            + poison.into() * two(96)
            + burning.into() * two(128)
            + knocked.into() * two(192);
        let mut effects = LIVE;
        let bases = [0_u32, 56, 128, 184];
        let mut k = 0;
        for (carrier, potion, deadline, rank) in spec.effects.span() {
            let base = *bases.span()[k];
            let tag: felt252 = if *potion {
                1
            } else {
                0
            };
            effects += (*carrier).into() * two(base)
                + tag * two(base + 23)
                + (*deadline).into() * two(base + 24)
                + (*rank).into() * two(base + 52);
            k += 1;
        }
        let mut bar = LIVE;
        for slot in 0..8_u32 {
            bar += (slot + 1).into() * two(16 * slot);
        }
        let regen: i32 = spec.health_regen.into() + 10;
        let regen: felt252 = regen.into();
        let stats = LIVE
            + 480
            + 20 * two(16)
            + spec.energy_regen.into() * two(24)
            + regen * two(32);
        let kit = LIVE + 100 + 101 * two(32) + 102 * two(64) + 103 * two(96);
        MemberWords { state, timers, effects, recharges: LIVE, stats, bar, kit }
    }

    /// The member of `spec`, its derived fields as the spec gives them.
    fn member(spec: MemberSpec) -> Member {
        let [bleeding, poison, burning, knocked] = spec.conditions;
        let [(_, _, d0, _), (_, _, d1, _), (_, _, d2, _), (_, _, d3, _)] = spec.effects;
        Member {
            status: spec.status,
            health: spec.health,
            energy: spec.energy,
            adrenaline: spec.adrenaline,
            flags: spec.flags,
            act_slot: NO_SLOT,
            act_target: 0,
            act_tile: 0,
            act_deadline: 0,
            bleeding,
            poison,
            burning,
            knocked,
            effect_deadlines: [d0, d1, d2, d3],
            effect_regen: spec.effect_regen,
            max_health: 480,
            max_energy: 60,
            health_regen: spec.health_regen,
            energy_regen: spec.energy_regen,
            words: Self::member_words(spec),
        }
    }

    /// An awake, Engaged goblin of `caste` at level 10: health 100 of 280, no activation (the
    /// caste's multiplier is 100 %, its energy 10: 30 thirds, 1 pip).
    fn goblin(entity: u16, caste: u16) -> Goblin {
        Goblin {
            entity,
            awake: true,
            ai: ai::ENGAGED,
            health: 100,
            energy: 0,
            adrenaline: 0,
            caste,
            act_slot: activation::NONE,
            act_target: 0,
            act_deadline: 0,
            bleeding: 0,
            poison: 0,
            burning: 0,
            knocked: 0,
            effect_deadline: 0,
            effect_regen: 0,
            max_health: 280,
            health_regen: 0,
            max_energy: 30,
            energy_regen: 1,
            state: LIVE
                + ai::ENGAGED.into() * two(24)
                + 100 * two(32)
                + caste.into() * two(64)
                + 10 * two(80),
            timers: LIVE + activation::NONE.into(),
        }
    }

    fn skill(id: u16, kind: u8, activation: u16, recharge: u16) -> SkillSheet {
        SkillSheet { id, kind, activation, recharge, regen0: 0, regen12: 0 }
    }

    /// A caste of multiplier 100 %, no regeneration, 10 energy regenerating 1 pip, weapon cost
    /// `k`, skills `20 + 4 id + slot`.
    fn caste(id: u16, k: u8) -> CasteSheet {
        let first = 20 + 4 * id;
        CasteSheet {
            id,
            health: 100,
            health_regen: 10,
            energy: 10,
            energy_regen: 1,
            weapon_ticks: k,
            skills: [first, first + 1, first + 2, first + 3],
        }
    }

    /// The bar (1: an attack, recharge 5; 2: Cinder Ring, 2 / 12; 3–8: spells, recharge 10) and
    /// the castes' skills (slot 0: an attack skill, activation 3, recharge 10; slot 1: an attack
    /// skill, 1 / 6; slot 2: a spell 2 / 8; slot 3: a shout), one potion.
    fn content() -> Content {
        let mut skills = array![
            Self::skill(1, skill_kind::ATTACK, 0, 5), Self::skill(2, skill_kind::SPELL, 2, 12),
        ];
        for id in 3..9_u16 {
            skills.append(Self::skill(id, skill_kind::SPELL, 1, 10));
        }
        for caste in 1..3_u16 {
            let first = 20 + 4 * caste;
            skills.append(Self::skill(first, skill_kind::ATTACK, 3, 10));
            skills.append(Self::skill(first + 1, skill_kind::ATTACK, 1, 6));
            skills.append(Self::skill(first + 2, skill_kind::SPELL, 2, 8));
            skills.append(Self::skill(first + 3, skill_kind::SHOUT, 0, 20));
        }
        Content {
            skills: skills.span(),
            potions: array![PotionSheet { id: 101, regen: 3 }].span(),
            castes: array![Self::caste(HOB, 1), Self::caste(RUNT, 2)].span(),
        }
    }

    fn world(clock: u32, members: Array<Member>, goblins: Array<Goblin>) -> World {
        World { clock, members, goblins, killed: array![], defeated: false }
    }

    fn only(clock: u32, goblin: Goblin) -> World {
        Self::world(clock, array![Self::member(Self::spec())], array![goblin])
    }
}

fn activation_of(goblin: @Goblin) -> (u8, u16, u32) {
    (*goblin.act_slot, *goblin.act_target, *goblin.act_deadline)
}

/// Test rules: record every hook's call; optionally take the member to 0 at an act.
#[derive(Drop, Default)]
struct Script {
    acts: Array<(u32, u16)>,
    resolved: Array<(u32, Actor, u8)>,
    kill_member_at: u32,
}

impl ScriptRules of Rules<Script> {
    fn perceive(ref self: Script, ref world: World) {}
    fn resolve(
        ref self: Script, ref world: World, content: @Content, actor: Actor, slot: u8, target: u16,
    ) {
        self.resolved.append((world.clock, actor, slot));
    }
    fn act(ref self: Script, ref world: World, content: @Content, index: u32) {
        self.acts.append((world.clock, *world.goblins.at(index).entity));
        if world.clock == self.kill_member_at {
            let mut member = *world.members.at(0);
            member.health = 0;
            world.set_member(0, member);
        }
    }
    fn objectives(ref self: Script, ref world: World) {}
}

fn run(ref world: World, ticks: u8) {
    let mut rules = Idle {};
    TickTrait::run(ref world, @Fixture::content(), ticks, ref rules);
}

// design/19 §10.3, the degeneration: Poisoned to 72, Bleeding to 77 from step 2 of tick 70,
// regeneration 0. Ticks 70–72 lose 14 each (−7 pips), ticks 73–75 lose 6 (−3): 60 in all.
#[test]
#[available_gas(l2_gas: 6421670)] // ceil(1.05 × 6115876 measured)
fn test_example_condition_degeneration() {
    let mut spec = Fixture::spec();
    spec.conditions = [77, 72, 0, 0];
    let member = Fixture::member(spec);
    let mut world = Fixture::world(69, array![member], array![Fixture::goblin(17, HOB)]);
    run(ref world, 3);
    assert(*world.members.at(0).health == 400 - 42, 'ticks 70-72: -14 each');
    run(ref world, 3);
    assert(*world.members.at(0).health == 400 - 60, 'ticks 73-75: -6 each');
    assert(world.clock == 75, 'clock');
}

// design/19 §10.1, step 3 of ticks 42–44: goblin 24 Burning to 44, health regeneration 0, goes
// 87 → 73 → 59 → 45; tick 45 changes nothing.
#[test]
#[available_gas(l2_gas: 6091674)] // ceil(1.05 × 5801594 measured)
fn test_example_burning_goblin() {
    let mut goblin = Fixture::goblin(24, HOB);
    goblin.health = 87;
    goblin.burning = 44;
    let mut world = Fixture::only(41, goblin);
    run(ref world, 1);
    assert(*world.goblins.at(0).health == 73, 'tick 42');
    run(ref world, 2);
    assert(*world.goblins.at(0).health == 45, 'tick 44');
    run(ref world, 1);
    assert(*world.goblins.at(0).health == 45, 'tick 45: burning over');
}

// design/19 §10.2: the smash started in step 2 of tick 50 (activation 3: A = 53); Skullring in
// the action phase at clock 51 knocks the Hobgoblin down to 53 and interrupts it at t0 = 52: the
// field goes to none, R = 61. It skips ticks 52 and 53, acts at 54; the smash is usable in step 2
// of tick 62 (T > R).
#[test]
#[available_gas(l2_gas: 6188461)] // ceil(1.05 × 5893772 measured)
fn test_example_interrupt() {
    let content = Fixture::content();
    let caste = Fixture::caste(HOB, 1);
    let mut goblin = Fixture::goblin(40, HOB);
    goblin.start(0, 0, 3, 50);
    assert(activation_of(@goblin) == (0, 0, 53), 'A = 53');
    // Clock 51: the knock-down (t0 = 52, D = 53) interrupts.
    goblin.knocked = 53;
    goblin.interrupt(52, @caste, @content);
    assert(activation_of(@goblin) == (activation::NONE, 0, 0), 'field none');
    assert(goblin.recharge(0) == 61, 'R = 61');
    let mut world = Fixture::only(51, goblin);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @content, 3, ref rules);
    assert(rules.acts.span() == array![(54, 40)].span(), 'acts again at 54 only');
    assert(rules.resolved.len() == 0, 'no resolution');
    // A recovery is not an activation: an interrupt changes nothing.
    let mut goblin = Fixture::goblin(40, HOB);
    goblin.recover(3, 60);
    let before = goblin;
    goblin.interrupt(61, @caste, @content);
    assert(goblin == before, 'recovery kept');
}

// design/19 §10.5: goblin 30 starts a 3-tick activation in step 2 of tick 100 (A = 103, recharge
// 10); it is frozen from tick 103 to 106 and nothing of it changes; awake at 107, its activation
// has lapsed at 103: none, R = 112, and it acts in step 2 of 107.
#[test]
#[available_gas(l2_gas: 11763438)] // ceil(1.05 × 11203274 measured)
fn test_example_lapse() {
    let mut goblin = Fixture::goblin(30, HOB);
    goblin.start(0, 0, 3, 100);
    goblin.awake = false;
    goblin.health = 50;
    goblin.bleeding = 105;
    let frozen = goblin;
    let mut world = Fixture::only(102, goblin);
    run(ref world, 4);
    assert(*world.goblins.at(0) == frozen, 'frozen: nothing read or written');
    let mut goblin = *world.goblins.at(0);
    goblin.awake = true;
    world.set_goblin(0, goblin);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @Fixture::content(), 1, ref rules);
    let goblin = world.goblins.at(0);
    assert(activation_of(goblin) == (activation::NONE, 0, 0), 'lapsed');
    assert(goblin.recharge(0) == 112, 'R = 103 + 10 - 1');
    assert(*goblin.health == 50, 'bleeding lost while frozen');
    assert(rules.resolved.len() == 0, 'a lapse does not resolve');
    assert(rules.acts.span() == array![(107, 30)].span(), 'acts at 107');
    // A later recharge already stored is kept.
    let mut goblin = Fixture::goblin(30, HOB);
    goblin.start(0, 0, 3, 100);
    goblin.set_recharge(0, 200);
    let mut world = Fixture::only(106, goblin);
    run(ref world, 1);
    assert(world.goblins.at(0).recharge(0) == 200, 'later recharge kept');
}

// design/19 §10.9: a weapon of cost k = 2 in step 2 of tick 50. A plain attack recovers to
// B = 51 and acts again at 52; an attack skill with activation 1 resolves at 51, does not act in
// 51, has no recovery (k < n + 2) and acts at 52; with k = 3 it recovers to B = 52 and acts at 53.
#[test]
#[available_gas(l2_gas: 17215972)] // ceil(1.05 × 16396163 measured)
fn test_example_activated_attack_cost() {
    let content = Fixture::content();
    // Plain attack, k = 2.
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.recover(2, 50);
    assert(activation_of(@goblin) == (activation::RECOVERING, 0, 51), 'B = 51');
    let mut world = Fixture::only(50, goblin);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @content, 2, ref rules);
    assert(rules.acts.span() == array![(52, 9)].span(), 'plain: acts at 52');
    assert(activation_of(world.goblins.at(0)) == (activation::NONE, 0, 0), 'recovery cleared');
    // Attack skill with activation 1 (caste 2's slot 1), k = 2.
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.start(1, 0, 1, 50);
    let mut world = Fixture::only(50, goblin);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @content, 2, ref rules);
    assert(rules.resolved.span() == array![(51, Actor::Goblin(0), 1)].span(), 'resolves at 51');
    assert(rules.acts.span() == array![(52, 9)].span(), 'n = 1, k = 2: acts at 52');
    assert(world.goblins.at(0).recharge(1) == 56, 'R = 51 + 6 - 1');
    // The same with k = 3: recovering to B = 52, acts at 53 = 50 + max(3, 2).
    let content = Content {
        castes: array![Fixture::caste(HOB, 1), Fixture::caste(RUNT, 3)].span(), ..content,
    };
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.start(1, 0, 1, 50);
    let mut world = Fixture::only(50, goblin);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(activation_of(world.goblins.at(0)) == (activation::RECOVERING, 0, 52), 'B = 52');
    TickTrait::run(ref world, @content, 2, ref rules);
    assert(rules.acts.span() == array![(53, 9)].span(), 'n = 1, k = 3: acts at 53');
}

// design/19 §10.1 and §10.6, a member's activation: Cinder Ring (activation 2, recharge 12)
// started at clock 40 resolves in step 1 of 42 with R = 53; the spell of §10.6 started at clock
// 200 with activation 2 (after the quick-cast bonus) and interrupted in step 2 of 201 recharges
// from 201.
#[test]
#[available_gas(l2_gas: 15570467)] // ceil(1.05 × 14829016 measured)
fn test_example_member_activation() {
    let content = Fixture::content();
    let mut member = Fixture::member(Fixture::spec());
    member.start(1, 57, 2, 40);
    assert(member.act_slot == 1 && member.act_target == 57 && member.act_deadline == 42, 'A = 42');
    let mut world = Fixture::world(40, array![member], array![]);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(rules.resolved.len() == 0, 'not at 41');
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(rules.resolved.span() == array![(42, Actor::Member(0), 1)].span(), 'resolves at 42');
    let member = world.members.at(0);
    assert(*member.act_slot == NO_SLOT && *member.act_deadline == 0, 'cleared');
    assert(member.recharge(1) == 53, 'R = 53');
    // §10.6: interrupted at 201.
    let mut member = Fixture::member(Fixture::spec());
    member.start(3, 0, 2, 200);
    assert(member.act_deadline == 202, 'A = 202');
    member.interrupt(201, @content);
    assert(member.act_slot == NO_SLOT, 'interrupted');
    assert(member.recharge(3) == 210, 'R = 201 + 10 - 1');
    // An instant skill used at clock 60 recharges from 61; an activation below 1 is 1 (§6).
    let mut member = Fixture::member(Fixture::spec());
    member.use_instant(0, 60, @content);
    assert(member.recharge(0) == 65, 'R = 61 + 5 - 1');
    member.start(2, 0, 0, 60);
    assert(member.act_deadline == 61, 'activation at least 1');
    // Every recharge slot is its own lane.
    for slot in 0..8_u8 {
        member.set_recharge(slot, 1000 + slot.into());
    }
    for slot in 0..8_u8 {
        assert(member.recharge(slot) == 1000 + slot.into(), 'recharge lanes');
    }
}

// §5.8: regeneration from the snapshot and held effects while they last, pips clamped to +10;
// energy in thirds up to its max. `MemberTrait::load` derives an effect's pips once: a skill's at
// its rank, a potion's through its belt slot.
#[test]
#[available_gas(l2_gas: 10426415)] // ceil(1.05 × 9929919 measured)
fn test_regeneration() {
    let content = Content {
        skills: array![
            SkillSheet {
                id: 1, kind: skill_kind::SPELL, activation: 0, recharge: 0, regen0: 2, regen12: 6,
            },
        ]
            .span(),
        potions: array![PotionSheet { id: 101, regen: 3 }].span(),
        castes: array![].span(),
    };
    let mut spec = Fixture::spec();
    spec
        .effects =
            [(1, false, 10, 12), (1, true, MAX_CLOCK, 0), (1, false, 4, 12), (0, false, 0, 0)];
    spec.energy = 55;
    spec.health_regen = 1;
    spec.energy_regen = 4;
    let member = MemberTrait::load(Fixture::member_words(spec), @content);
    assert(member.effect_regen == [6, 3, 6, 0], 'effect pips');
    assert(member.effect_deadlines == [10, MAX_CLOCK, 4, 0], 'effect deadlines');
    assert(member.max_health == 480 && member.max_energy == 60, 'maxima');
    assert(member.health_regen == 1 && member.energy_regen == 4, 'regeneration');
    let mut world = Fixture::world(4, array![member], array![]);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 1, ref rules);
    let after = world.members.at(0);
    assert(*after.health == 400 + 2 * 10, '1 + 6 + 3 pips');
    assert(*after.energy == 59, 'energy +4 thirds');
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(*world.members.at(0).energy == 60, 'energy at its max');
    // Near max health: clamped.
    let mut spec = Fixture::spec();
    spec.health = 479;
    spec.health_regen = 10;
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
    run(ref world, 1);
    assert(*world.members.at(0).health == 480, 'max health');
}

// `load` reads the hot fields of the words and derives the rest; `store` writes them back as
// deltas, every other bit kept: a round trip is the identity, a change lands where it belongs.
#[test]
#[available_gas(l2_gas: 10889414)] // ceil(1.05 × 10370870 measured)
fn test_load_store() {
    let mut spec = Fixture::spec();
    spec.conditions = [11, 12, 13, 14];
    spec.adrenaline = 7;
    spec.flags = flag::HALVED;
    let words = Fixture::member_words(spec);
    let content = Fixture::content();
    let member = MemberTrait::load(words, @content);
    assert(member == Fixture::member(spec), 'load reads the words');
    assert(member.store() == words, 'round trip');
    let mut member = member;
    member.health = 1;
    member.knocked = 99;
    member.start(3, 17, 2, 70);
    let words = member.store();
    let again = MemberTrait::load(words, @content);
    assert(again == Member { words, ..member }, 'store writes the fields');
    // A goblin: caste 2, level 10.
    let goblin = Fixture::goblin(9, RUNT);
    let words = GoblinWords { entity: 9, awake: true, state: goblin.state, timers: goblin.timers };
    let loaded = GoblinTrait::load(words, @content);
    assert(loaded == goblin, 'goblin load');
    let mut changed = loaded;
    changed.health = 3;
    changed.poison = 88;
    changed.effect_deadline = 90;
    changed.start(2, 8, 2, 70);
    changed.set_recharge(3, 500);
    let back = GoblinTrait::load(changed.store(), @content);
    assert(back.state == changed.store().state, 'goblin state');
    assert(back.health == 3 && back.poison == 88 && back.effect_deadline == 90, 'goblin fields');
    assert(activation_of(@back) == (2, 8, 72) && back.recharge(3) == 500, 'goblin timers');
}

// design/20 §6 test 9 (DES06-7, DS-29): step 3's pip sum at its extremes computes without
// overflow and clamps to ±10: −10 (the field at 0), four −10 effects and the three conditions
// give −64, 20 health lost; +10 and four +10 effects give +50, 20 health gained.
#[test]
#[available_gas(l2_gas: 10129063)] // ceil(1.05 × 9646726 measured)
fn test_regeneration_extremes() {
    let mut spec = Fixture::spec();
    spec.health_regen = -10;
    spec.effect_regen = [-10; 4];
    spec.effects = [(1, false, 99, 0); 4];
    spec.conditions = [99, 99, 99, 0];
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
    run(ref world, 1);
    assert(*world.members.at(0).health == 380, '-64 pips: -20');
    let mut spec = Fixture::spec();
    spec.health = 300;
    spec.health_regen = 10;
    spec.effect_regen = [10; 4];
    spec.effects = [(1, false, 99, 0); 4];
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
    run(ref world, 1);
    assert(*world.members.at(0).health == 320, '+50 pips: +20');
}

// A goblin's derived fields: max health from the adventurer's formula times its caste's
// multiplier (design/03, design/05), its regeneration, its effect's pips at its rank.
#[test]
#[available_gas(l2_gas: 789285)] // ceil(1.05 × 751700 measured)
fn test_goblin_load() {
    let caste = CasteSheet {
        id: 3,
        health: 150,
        health_regen: 12,
        energy: 20,
        energy_regen: 2,
        weapon_ticks: 2,
        skills: [SMASH, 0, 0, 0],
    };
    let content = Content {
        skills: array![
            SkillSheet {
                id: SMASH,
                kind: skill_kind::SPELL,
                activation: 0,
                recharge: 0,
                regen0: 1,
                regen12: 4,
            },
        ]
            .span(),
        potions: array![].span(),
        castes: array![caste].span(),
    };
    // Level 20, caste 3; its effect is skill 24 at rank 8: 1 + 3 × 8 / 12 = 3.
    let state = LIVE + 3 * two(64) + 20 * two(80);
    let timers = LIVE + 255 + SMASH.into() * two(108) + 8 * two(246);
    let goblin = GoblinTrait::load(
        GoblinWords { entity: 77, awake: false, state, timers }, @content,
    );
    assert(goblin.max_health == 720 && goblin.health_regen == 2, 'health');
    assert(goblin.max_energy == 60 && goblin.energy_regen == 2, 'energy');
    assert(goblin.effect_regen == 3 && !goblin.awake, 'effect');
}

// §5.8 step 3, FX-12, D-157 E: out of combat (no goblin of the awake set Engaged) a member loses
// 1 quarter strike a tick, floored at 0; a goblin not Engaged too; an Engaged one keeps it.
#[test]
#[available_gas(l2_gas: 11399985)] // ceil(1.05 × 10857128 measured)
fn test_adrenaline_decay() {
    let mut spec = Fixture::spec();
    spec.adrenaline = 5;
    let mut alerted = Fixture::goblin(8, HOB);
    alerted.ai = ai::ALERTED;
    alerted.adrenaline = 1;
    let mut frozen_engaged = Fixture::goblin(9, HOB);
    frozen_engaged.awake = false;
    let mut world = Fixture::world(
        0, array![Fixture::member(spec)], array![alerted, frozen_engaged],
    );
    run(ref world, 2);
    assert(*world.members.at(0).adrenaline == 3, 'member: -1 a tick');
    assert(*world.goblins.at(0).adrenaline == 0, 'goblin: floored at 0');
    // In combat: an awake goblin is Engaged.
    let mut engaged = Fixture::goblin(8, HOB);
    engaged.adrenaline = 4;
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![engaged]);
    run(ref world, 1);
    assert(*world.members.at(0).adrenaline == 5, 'member in combat keeps');
    assert(*world.goblins.at(0).adrenaline == 4, 'engaged goblin keeps');
}

// §5.13: goblins at 0 in step 3 die after every actor of the step, in id order; a dead goblin is
// no longer touched. Goblin energy regenerates in thirds up to the caste's.
#[test]
#[available_gas(l2_gas: 6545520)] // ceil(1.05 × 6233828 measured)
fn test_deaths_in_step_3() {
    let mut a = Fixture::goblin(8, HOB);
    a.health = 10;
    a.burning = 5;
    let mut b = Fixture::goblin(12, HOB);
    b.health = 14;
    b.burning = 5;
    b.bleeding = 5;
    let mut c = Fixture::goblin(20, HOB);
    c.energy = 29;
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], array![a, b, c]);
    run(ref world, 1);
    assert(world.killed.span() == array![8, 12].span(), 'killed in id order');
    assert(*world.goblins.at(0).ai == ai::DEAD && *world.goblins.at(1).ai == ai::DEAD, 'dead');
    assert(*world.goblins.at(0).health == 0, 'at 0');
    assert(*world.goblins.at(2).energy == 30, 'energy at 10 x 3');
    let dead = *world.goblins.at(0);
    run(ref world, 1);
    assert(world.killed.len() == 2 && *world.goblins.at(0) == dead, 'dead untouched');
    // The executor's kill: at once, once.
    world.kill(2);
    world.kill(2);
    assert(world.killed.span() == array![8, 12, 20].span(), 'kill once');
    assert(*world.goblins.at(2).health == 0 && !world.goblins.at(2).is_alive(), 'killed');
}

// §5.13, FX-8: the adventurer at 0 in step 3 is down at step 5 and the run stops; at 0 in step 2
// the tick stops at once (no later act, no step 3) and step 5 still runs.
#[test]
#[available_gas(l2_gas: 10753238)] // ceil(1.05 × 10241179 measured)
fn test_defeat() {
    let mut spec = Fixture::spec();
    spec.health = 6;
    spec.conditions = [9, 9, 9, 0];
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
    run(ref world, 3);
    let member = world.members.at(0);
    assert(*member.health == 0 && *member.status == status::DOWN, 'down');
    assert(world.defeated && world.clock == 1, 'stopped after the tick');
    // At 0 in step 2 (goblin 8's act): goblin 9 does not act, nobody regenerates.
    let mut a = Fixture::goblin(8, HOB);
    a.health = 50;
    a.bleeding = 9;
    let b = Fixture::goblin(9, HOB);
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], array![a, b]);
    let mut rules: Script = Default::default();
    rules.kill_member_at = 1;
    TickTrait::run(ref world, @Fixture::content(), 2, ref rules);
    assert(rules.acts.span() == array![(1, 8)].span(), 'stopped at once');
    assert(*world.goblins.at(0).health == 50, 'no step 3');
    assert(world.defeated && *world.members.at(0).status == status::DOWN, 'step 5 ran');
}

// Step 2 (§5.2): a knocked-down goblin, a busy one (activating, recovering), a frozen one and a
// dead one do not act; the others act in ascending id order.
#[test]
#[available_gas(l2_gas: 7526095)] // ceil(1.05 × 7167709 measured)
fn test_who_acts() {
    let mut knocked = Fixture::goblin(8, HOB);
    knocked.knocked = 1;
    let mut activating = Fixture::goblin(9, HOB);
    activating.start(0, 0, 3, 0);
    let mut recovering = Fixture::goblin(10, HOB);
    recovering.recover(3, 0);
    let mut frozen = Fixture::goblin(11, HOB);
    frozen.awake = false;
    let mut dead = Fixture::goblin(12, HOB);
    dead.ai = ai::DEAD;
    let goblins = array![
        knocked, activating, recovering, frozen, dead, Fixture::goblin(13, HOB),
        Fixture::goblin(14, RUNT),
    ];
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @Fixture::content(), 1, ref rules);
    assert(rules.acts.span() == array![(1, 13), (1, 14)].span(), 'acts');
}

// Step 0: the flags "since the last tick" and "hit this tick" clear; `HALVED` stays.
#[test]
#[available_gas(l2_gas: 5071745)] // ceil(1.05 × 4830233 measured)
fn test_flags_cleared() {
    let mut spec = Fixture::spec();
    spec.flags = flag::TURNED + flag::INSTANT + flag::HIT + flag::HALVED;
    let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
    run(ref world, 1);
    assert(*world.members.at(0).flags == flag::HALVED, 'flags');
}

// Step 0's awake set (§5.2, design/02): the 8 nearest goblins alive and not asleep, ties by lowest
// id; an asleep or dead goblin never.
#[test]
#[available_gas(l2_gas: 8643275)] // ceil(1.05 × 8231690 measured)
fn test_awake_set() {
    let mut goblins = array![];
    for entity in 8..19_u16 {
        let mut goblin = Fixture::goblin(entity, HOB);
        goblin.awake = false;
        if entity == 8 {
            goblin.ai = ai::ASLEEP;
        } else if entity == 9 {
            goblin.ai = ai::DEAD;
        }
        goblins.append(goblin);
    }
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
    // Entities 8–18 at distances 1, 1, 5, 3, 3, 9, 2, 3, 4, 3, 6.
    TickTrait::awake(ref world, array![1, 1, 5, 3, 3, 9, 2, 3, 4, 3, 6].span());
    let mut awake = array![];
    for goblin in world.goblins.span() {
        if *goblin.awake {
            awake.append(*goblin.entity);
        }
    }
    // Candidates by (distance, id): 14 (2), 11, 12, 15, 17 (3), 16 (4), 10 (5), 18 (6), 13 (9).
    assert(awake.span() == array![10, 11, 12, 14, 15, 16, 17, 18].span(), 'nearest 8');
}

// ---------------------------------------------------------------------------------------------
// Determinism and cost.

/// The worst state of a tick (design/02: 8 awake goblins; the member; conditions and activations
/// running): the member holds 4 `REGENERATION` effects (2 potions), the 3 degenerating conditions
/// and an activation due; each of the 8 goblins, from 5 castes (the MVP's widest, design/19 §7.2),
/// has the 3 degenerating conditions and a `REGENERATION` effect; 4 resolve an activation (2 into
/// a recovery), 2 lapse, 2 finish a recovery; the content holds the 8 bar skills and the castes'
/// 20, the goblins' last (the longest lookups), and 4 potions.
fn worst() -> (World, Content) {
    let mut skills = array![];
    for id in 1..9_u16 {
        let mut sheet = Fixture::skill(id, skill_kind::SPELL, 2, 10);
        sheet.regen0 = 3;
        sheet.regen12 = 3;
        skills.append(sheet);
    }
    let mut castes = array![];
    for caste in 1..6_u16 {
        let first = 20 + 4 * caste;
        skills.append(Fixture::skill(first, skill_kind::ATTACK, 1, 10));
        skills.append(Fixture::skill(first + 1, skill_kind::SPELL, 2, 8));
        skills.append(Fixture::skill(first + 2, skill_kind::ATTACK, 3, 12));
        let mut last = Fixture::skill(first + 3, skill_kind::ENCHANTMENT, 1, 20);
        last.regen0 = 2;
        last.regen12 = 2;
        skills.append(last);
        castes.append(Fixture::caste(caste, 3));
    }
    let potions = array![
        PotionSheet { id: 100, regen: 1 }, PotionSheet { id: 101, regen: 2 },
        PotionSheet { id: 102, regen: 1 }, PotionSheet { id: 103, regen: 2 },
    ];
    let mut spec = Fixture::spec();
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    spec.effect_regen = [3, 3, 1, 2];
    let mut member = Fixture::member(spec);
    member.start(7, 8, 1, 49);
    let mut goblins = array![];
    let mut k: u16 = 0;
    while k < 8 {
        let caste = 1 + k % 5;
        let mut goblin = Fixture::goblin(8 + 16 * k, caste);
        goblin.health = 400;
        goblin.max_health = 400;
        goblin.bleeding = 99;
        goblin.poison = 99;
        goblin.burning = 99;
        goblin.effect_deadline = 99;
        goblin.effect_regen = 2;
        goblin.timers += (20 + 4 * caste + 3).into() * two(108) + 4 * two(246);
        if k < 4 {
            // Resolves at 50: slot 0 (activation 1, k = 3 ≥ n + 2) recovers, slot 2 does not.
            goblin.start((k % 2).try_into().unwrap() * 2, 0, 1, 49);
        } else if k < 6 {
            goblin.start(1, 0, 2, 40);
        } else {
            goblin.recover(3, 47);
        }
        goblins.append(goblin);
        k += 1;
    }
    let content = Content { skills: skills.span(), potions: potions.span(), castes: castes.span() };
    (Fixture::world(49, array![member], goblins), content)
}

/// The worst state as the words `Instances` would pass.
fn worst_words() -> (Words, Content) {
    let (world, content) = worst();
    (world.store(), content)
}

/// A representative tick: the member with one condition and one effect, 8 awake goblins of 2
/// castes fighting (no activation due, no condition), the content of two castes.
fn representative() -> (World, Content) {
    let mut spec = Fixture::spec();
    spec.conditions = [99, 0, 0, 0];
    spec.effects = [(5, false, 99, 8), (0, false, 0, 0), (0, false, 0, 0), (0, false, 0, 0)];
    let member = Fixture::member(spec);
    let mut goblins = array![];
    let mut k: u16 = 0;
    while k < 8 {
        goblins.append(Fixture::goblin(8 + 16 * k, 1 + k % 2));
        k += 1;
    }
    (Fixture::world(49, array![member], goblins), Fixture::content())
}

// Determinism (AC-2): the same state gives the same world, over 10 ticks of the worst state.
#[test]
#[available_gas(l2_gas: 38337974)] // ceil(1.05 × 36512356 measured)
fn test_deterministic() {
    let (mut a, content) = worst();
    let (mut b, _) = worst();
    let mut rules = Idle {};
    TickTrait::run(ref a, @content, 10, ref rules);
    TickTrait::run(ref b, @content, 10, ref rules);
    assert(a == b, 'same state, same world');
    assert(a.clock == 59, 'ten ticks');
}

// The fixtures' own cost, subtracted from the benchmarks below.
#[test]
#[available_gas(l2_gas: 11211879)] // ceil(1.05 × 10677980 measured)
fn test_cost_fixture_worst() {
    let (world, content) = worst();
    assert(world.goblins.len() == 8 && content.skills.len() == 28, 'worst');
}

#[test]
#[available_gas(l2_gas: 11837322)] // ceil(1.05 × 11273640 measured)
fn test_cost_fixture_worst_words() {
    let (words, content) = worst_words();
    assert(words.goblins.len() == 8 && content.skills.len() == 28, 'worst');
}

#[test]
#[available_gas(l2_gas: 7259522)] // ceil(1.05 × 6913830 measured)
fn test_cost_fixture_representative() {
    let (world, content) = representative();
    assert(world.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// Cost: one representative tick, the pipeline alone (Idle rules).
#[test]
#[available_gas(l2_gas: 7908282)] // ceil(1.05 × 7531697 measured)
fn test_cost_tick_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50, 'one tick');
}

// Cost: a batch's 10 representative ticks, the pipeline alone.
#[test]
#[available_gas(l2_gas: 13793399)] // ceil(1.05 × 13136570 measured)
fn test_cost_batch_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59, 'ten ticks');
}

#[test]
#[available_gas(l2_gas: 7882781)] // ceil(1.05 × 7507410 measured)
fn test_cost_fixture_representative_words() {
    let (world, content) = representative();
    let words = world.store();
    assert(words.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// A batch's 10 representative ticks through one library call: load, ticks, store, the call.
#[test]
#[available_gas(l2_gas: 16536692)] // ceil(1.05 × 15749230 measured)
fn test_cost_library_call_batch_representative() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = representative();
    let words = library.run(world.store(), content, 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
#[available_gas(l2_gas: 7893816)] // ceil(1.05 × 7517920 measured)
fn test_cost_library_baseline_representative() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = representative();
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// Cost: one worst tick, the pipeline alone (Idle rules).
#[test]
#[available_gas(l2_gas: 13093659)] // ceil(1.05 × 12470151 measured)
fn test_cost_tick_worst() {
    let (mut world, content) = worst();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(*world.goblins.at(0).act_slot == activation::RECOVERING, 'slot 0 recovers');
    assert(world.goblins.at(4).recharge(1) == 49, 'lapsed at 42');
    assert(*world.members.at(0).act_slot == NO_SLOT, 'member resolved');
}

// Cost: a batch's 10 worst ticks (weight 10), the pipeline alone.
#[test]
#[available_gas(l2_gas: 19103184)] // ceil(1.05 × 18193508 measured)
fn test_cost_batch_worst() {
    let (mut world, content) = worst();
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59, 'ten ticks');
}

// Cost, once per call: loading the worst state's actors from their words and storing them back.
#[test]
#[available_gas(l2_gas: 13838685)] // ceil(1.05 × 13179700 measured)
fn test_cost_load_store_worst() {
    let (words, content) = worst_words();
    let world = words.load(@content);
    let words = world.store();
    assert(words.goblins.len() == 8, 'stored');
}

// Cost of the library call (AC-3): the baseline declares the class and runs the call's body (load,
// one worst tick, store) in the test's own code; the next test runs it through `library_call`.
// The difference is the call: its syscall and the words and content through calldata and back.
#[test]
#[available_gas(l2_gas: 15721032)] // ceil(1.05 × 14972411 measured)
fn test_cost_library_baseline() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words();
    let mut world = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 1, ref rules);
    let words = world.store();
    assert(words.clock == 50, 'one tick');
}

#[test]
#[available_gas(l2_gas: 16560822)] // ceil(1.05 × 15772211 measured)
fn test_cost_library_call() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let words = library.run(words, content, 1);
    assert(words.clock == 50, 'one tick');
}

// The batch's 10 worst ticks through one library call (one call per invocation, ENG-01 §1.3).
#[test]
#[available_gas(l2_gas: 22585257)] // ceil(1.05 × 21509768 measured)
fn test_cost_library_call_batch() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let words = library.run(words, content, 10);
    assert(words.clock == 59, 'ten ticks');
}

// The library call runs the pipeline: the same words as a direct run.
#[test]
#[available_gas(l2_gas: 35207191)] // ceil(1.05 × 33530658 measured)
fn test_library_matches_pipeline() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let words = library.run(words, content, 3);
    let mut world = expected.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 3, ref rules);
    assert(words == world.store(), 'the call runs the pipeline');
}

// The sheets read from a record's parts (only the fields the tick reads) agree with the sheets of
// the fully unpacked record, their oracle: a regeneration in entry 1 or 2, falling with rank or
// negative, none; a potion with and without one; a caste.
#[test]
#[available_gas(l2_gas: 1382420)] // ceil(1.05 × 1316590 measured)
fn test_sheets_read_oracle() {
    let (skill, caste) = records();
    let unpacked: Skill = Record::<Skill>::unpack(skill);
    assert(SkillSheetTrait::read(5, skill) == SkillSheetTrait::new(5, @unpacked), 'skill');
    let unpacked: Caste = Record::<Caste>::unpack(caste);
    assert(CasteSheetTrait::read(1, caste) == CasteSheetTrait::new(1, @unpacked), 'caste');
    let damage = EntryTrait::new(
        kind::DAMAGE, 4, 10, 40, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    let decay = EntryTrait::new(
        kind::REGENERATION, 0, 4, -10, 5, 5, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    let none: grimworld_logic::types::effect::Entry = Default::default();
    for entries in array![[damage, decay, none], [damage, none, none]] {
        let skill = SkillTrait::new(
            1, 1, skill_kind::HEX, 10, 0, 2, 20, 5, target::FOE, false, entries,
        );
        let parts = Record::<Skill>::pack(@skill);
        assert(SkillSheetTrait::read(9, parts) == SkillSheetTrait::new(9, @skill), 'skill entries');
    }
    let tonic = EntryTrait::new(
        kind::REGENERATION, 0, -3, -3, 8, 8, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    let bomb = EntryTrait::new(
        kind::DAMAGE, 4, 30, 30, 0, 0, 0, target::TILE, shape::DISC_1, filter::FOES, 0, 0,
    );
    for entry in array![tonic, bomb] {
        let item = ItemTrait::new(item_class::POTION, 1, 1, 10, 0, entry, 3, 20);
        let parts = Record::<Item>::pack(@item);
        assert(PotionSheetTrait::read(7, parts) == PotionSheetTrait::new(7, @item), 'potion');
    }
}

// The content's price, per record, once per batch (D-145): a `SKILL` and a `CASTE` read into their
// sheets from their parts. The baseline packs them only; the unpacked path is the oracle's.
#[test]
#[available_gas(l2_gas: 350385)] // ceil(1.05 × 333700 measured)
fn test_cost_sheets_baseline() {
    let (skill, caste) = records();
    assert(skill.len() == 2 && caste.len() == 2, 'parts');
}

#[test]
#[available_gas(l2_gas: 436475)] // ceil(1.05 × 415690 measured)
fn test_cost_sheets() {
    let (skill, caste) = records();
    let sheet = SkillSheetTrait::read(5, skill);
    let caste_sheet = CasteSheetTrait::read(1, caste);
    assert(sheet.recharge == 12 && sheet.regen(12) == 6, 'skill sheet');
    assert(caste_sheet.weapon_ticks == 2 && caste_sheet.max_health(20) == 720, 'caste sheet');
}

#[test]
#[available_gas(l2_gas: 562464)] // ceil(1.05 × 535680 measured)
fn test_cost_sheets_unpacked() {
    let (skill, caste) = records();
    let skill: Skill = Record::<Skill>::unpack(skill);
    let caste: Caste = Record::<Caste>::unpack(caste);
    let sheet = SkillSheetTrait::new(5, @skill);
    let caste_sheet = CasteSheetTrait::new(1, @caste);
    assert(sheet.recharge == 12 && sheet.regen(12) == 6, 'skill sheet');
    assert(caste_sheet.weapon_ticks == 2 && caste_sheet.max_health(20) == 720, 'caste sheet');
}

/// A spell whose holding entry is a `REGENERATION` of 2…6 pips, and a caste of multiplier 150 %.
fn records() -> (Span<felt252>, Span<felt252>) {
    let regen = EntryTrait::new(
        kind::REGENERATION, 0, 2, 6, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    let skill = SkillTrait::new(
        1,
        1,
        skill_kind::SPELL,
        10,
        0,
        1,
        12,
        0,
        target::SELF,
        false,
        [regen, Default::default(), Default::default()],
    );
    let caste = CasteTrait::new(
        4,
        1,
        150,
        10,
        40,
        [0; 9],
        WeaponTrait::new(weapon::MAUL, 30, 3, 2, 1),
        10,
        1,
        [SMASH, 25, 26, 27],
        12,
        30,
        0,
        false,
    );
    (Record::<Skill>::pack(@skill), Record::<Caste>::pack(@caste))
}
