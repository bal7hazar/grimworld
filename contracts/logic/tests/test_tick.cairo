// CBT-02: the world tick's pipeline (design/02 *The tick*, design/19 §5). The worked examples of
// design/19 §10 whose steps are the pipeline's (10.1's step 3, 10.2, 10.3, 10.5, 10.6, 10.9),
// every rule of the steps one by one, determinism, and the cost of a tick on measured scenarios
// and at its upper bound (CBT-02b, below), against the expedition's target of 1,469,435 L2 gas a
// tick inside a batch (docs/architecture/cost-budget.md §2, D-159). The words are built here from
// ENG-01's offsets; the ephemeral package's `test_tick_words` pins `load` and `store` against its
// packers. COST-3 (CBT-02b): "worst" in a fixture's or a test's name is the name of a measured
// scenario, not a claim that no state costs more; "upper bound" is kept for the derived result
// (REPORT.md, ENG-01 §9.2).
use grimworld_logic::content::Record;
use grimworld_logic::helpers::signed::SignedTrait;
use grimworld_logic::interface::{ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::goblin::{
    Goblin, GoblinAssert, GoblinLifecycleTrait, GoblinTickTrait, GoblinTrait, GoblinWords,
    GoblinWordsTrait,
};
use grimworld_logic::models::index::{Caste, Item, Skill};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class as item_class};
use grimworld_logic::models::member::{
    Member, MemberAssert, MemberLifecycleTrait, MemberTickTrait, MemberTrait, MemberWords,
    MemberWordsTrait,
};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::types::MAX_CLOCK;
use grimworld_logic::types::combat::{activation, condition, skill_kind, weapon};
use grimworld_logic::types::effect::{EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::tick::{
    CasteSheet, CasteSheetTrait, Content, ContentTrait, Held, NO_SLOT, PotionSheet,
    PotionSheetTrait, SkillSheet, SkillSheetTrait, ai, flag, status,
};
use grimworld_logic::types::world::{
    Actor, Idle, Rules, TickTrait, Words, WordsTrait, World, WorldAssert, WorldStoreTrait,
    WorldTrait,
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
            adrenaline_cap: 0,
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
            adrenaline_cap: 0,
            state: LIVE
                + ai::ENGAGED.into() * two(24)
                + 100 * two(32)
                + caste.into() * two(64)
                + 10 * two(80),
            timers: LIVE + activation::NONE.into(),
        }
    }

    fn skill(id: u16, kind: u8, activation: u16, recharge: u16) -> SkillSheet {
        SkillSheet { id, kind, adrenaline: 0, activation, recharge, regen0: 0, regen12: 0 }
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
#[available_gas(l2_gas: 15553205)] // ceil(1.05 × 14812576 measured)
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
    // Skill 1 regenerates 2…6 pips; the bar's other skills (2–8) are read for its adrenaline
    // cap.
    let mut skills = array![
        SkillSheet {
            id: 1,
            kind: skill_kind::SPELL,
            adrenaline: 0,
            activation: 0,
            recharge: 0,
            regen0: 2,
            regen12: 6,
        },
    ];
    for id in 2..9_u16 {
        skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
    }
    let content = Content {
        skills: skills.span(),
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
#[available_gas(l2_gas: 11246141)] // ceil(1.05 × 10710610 measured)
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
                adrenaline: 0,
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

/// Rules that keep every actor busy (AUD-182-7): step 0 restarts the member's activation to resolve
/// in step 1 of every tick (an action phase starting one before each tick); every goblin free to
/// act starts a 1-tick activation, which resolves in step 1 of the next tick. With a weapon cost of
/// 1 there is no recovery, so each awake goblin alternately resolves and acts, and every tick
/// rewrites each of them: the most work the pipeline's own steps can do, tick after tick.
#[derive(Drop, Default)]
struct Busy {}

impl BusyRules of Rules<Busy> {
    fn perceive(ref self: Busy, ref world: World) {
        let mut member = *world.members.at(0);
        member.act_slot = 7;
        member.act_target = 8;
        member.act_deadline = world.clock;
        world.set_member(0, member);
    }
    fn resolve(
        ref self: Busy, ref world: World, content: @Content, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Busy, ref world: World, content: @Content, index: u32) {
        let mut goblin = *world.goblins.at(index);
        goblin.start(0, 0, 1, world.clock);
        world.set_goblin(index, goblin);
    }
    fn objectives(ref self: Busy, ref world: World) {}
}

/// The words of a goblin of caste 5 at level 10 (ENG-01 §3.2 offsets): Alerted (not Engaged),
/// `health`, activating slot 0 due at `due` (0: none), the three degenerating conditions to
/// `until`, its effect skill 43 to `until` at rank 4.
fn goblin_words(entity: u16, awake: bool, health: u16, due: u32, until: u32) -> GoblinWords {
    let state = LIVE + ai::ALERTED.into() * B24 + health.into() * B32 + 5 * B64 + 10 * B80;
    let act: felt252 = if due == 0 {
        activation::NONE.into()
    } else {
        due.into() * B24
    };
    let effect: felt252 = if until == 0 {
        0
    } else {
        43 * B108 + 4 * B246
    };
    let timers = LIVE + act + until.into() * (B52 + B80 + B128 + B212) + effect;
    GoblinWords { entity, awake, state, timers }
}

// Powers of two for the fixtures above (cheap to build: the benchmarks subtract their fixtures).
const B24: felt252 = 0x1000000;
const B32: felt252 = 0x100000000;
const B52: felt252 = 0x10000000000000;
const B64: felt252 = 0x10000000000000000;
const B80: felt252 = 0x100000000000000000000;
const B108: felt252 = 0x1000000000000000000000000000;
const B128: felt252 = 0x100000000000000000000000000000000;
const B212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const B246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

/// The content at the MVP's widest (design/19 §7.2: `C = 5`, `T = 10`): the bar's 8 skills (7 and
/// 8 regenerating 3 pips), 10 terrain traps' skills, the 5 castes' 20; 4 potions. The goblins'
/// caste, 5, and its skills (40–43) come last in their lists, so every lookup scans the whole
/// list.
/// The castes' weapons cost `k` ticks.
fn worst_content(k: u8) -> Content {
    let mut skills = array![];
    for id in 1..9_u16 {
        let mut sheet = Fixture::skill(id, skill_kind::SPELL, 2, 10);
        sheet.adrenaline = 2;
        if id >= 7 {
            sheet.regen0 = 3;
            sheet.regen12 = 3;
        }
        skills.append(sheet);
    }
    for id in 60..70_u16 {
        skills.append(Fixture::skill(id, skill_kind::TRAP, 0, 0));
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
        castes.append(Fixture::caste(caste, k));
    }
    let potions = array![
        PotionSheet { id: 100, regen: 1 }, PotionSheet { id: 101, regen: 2 },
        PotionSheet { id: 102, regen: 1 }, PotionSheet { id: 103, regen: 2 },
    ];
    Content { skills: skills.span(), potions: potions.span(), castes: castes.span() }
}

/// CBT-02's heavy scenario of a tick (AUD-182-7), a measured state, not a maximum (COST-3: the
/// upper bound is CBT-02b's, below), every actor loaded from its words so that the derived fields
/// agree with the stored ones:
/// - the goblin array at its bound, `MAX_GOBLINS` = 100 (every pass is linear in it), 8 of them
///   awake (design/02), the 92 others frozen; every one of the 100 holds a retained effect, so
///   `load` looks up its skill (at the list's end) and scales it for each (COST-1);
/// - each awake goblin concludes its activation (a recovery with `k = 3 ≥ n + 2`) at the end of
///   the content's lists, the array rebuilt;
/// - step 3 with every term: the 3 degenerating conditions and a regenerating effect on each awake
///   goblin; on the member, its 3 conditions, 4 regenerating effects (2 potions) and its own
///   activation concluding; no goblin Engaged, so the Engaged scan runs the whole awake set;
/// - with `dying`, every awake goblin dies in step 3 (8 kills recorded) and the member too (step
///   5's defeat rewrites the members).
/// With `dying` false and `k = 1`, the state `Busy` keeps busy over a batch (no death, no
/// recovery).
fn worst_state(dying: bool, k: u8) -> (World, Content) {
    worst_of(dying, k, 100)
}

/// `worst_state` with `count` goblins in the array, the last 8 awake.
fn worst_of(dying: bool, k: u8, count: u16) -> (World, Content) {
    let content = worst_content(k);
    let mut spec = Fixture::spec();
    spec.health = if dying {
        7
    } else {
        400
    };
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    member.start(7, 8, 1, 49);
    let health: u16 = if dying {
        1
    } else {
        280
    };
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < count {
        let awake = i + 8 >= count;
        let words = if awake {
            goblin_words(8 + i, true, health, 50, 99)
        } else {
            // Frozen, but loaded: its retained effect is looked up like an awake one's (COST-1).
            goblin_words(8 + i, false, 280, 0, 99)
        };
        goblins.append(GoblinTrait::load(words, @content));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), content)
}

/// `worst_state`'s scenario as the words `Instances` would pass.
fn worst_words() -> (Words, Content) {
    let (world, content) = worst_state(true, 3);
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

// Determinism (AC-2): the same state gives the same world, over 10 busy ticks.
#[test]
#[available_gas(l2_gas: 291918732)] // ceil(1.05 × 278017840 measured)
fn test_deterministic() {
    let (mut a, content) = worst_state(false, 1);
    let (mut b, _) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    TickTrait::run(ref a, @content, 10, ref rules);
    TickTrait::run(ref b, @content, 10, ref rules);
    assert(a == b, 'same state, same world');
    assert(a.clock == 59, 'ten ticks');
}

// The fixtures' own cost, subtracted from the benchmarks below.
#[test]
#[available_gas(l2_gas: 58639760)] // ceil(1.05 × 55847390 measured)
fn test_cost_fixture_worst() {
    let (world, content) = worst_state(true, 3);
    assert(world.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
#[available_gas(l2_gas: 58640379)] // ceil(1.05 × 55847980 measured)
fn test_cost_fixture_worst_batch() {
    let (world, content) = worst_state(false, 1);
    assert(world.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
#[available_gas(l2_gas: 60727884)] // ceil(1.05 × 57836080 measured)
fn test_cost_fixture_worst_words() {
    let (words, content) = worst_words();
    assert(words.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
#[available_gas(l2_gas: 7264877)] // ceil(1.05 × 6918930 measured)
fn test_cost_fixture_representative() {
    let (world, content) = representative();
    assert(world.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// Cost: one representative tick, the pipeline alone (Idle rules).
#[test]
#[available_gas(l2_gas: 7924925)] // ceil(1.05 × 7547547 measured)
fn test_cost_tick_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50, 'one tick');
}

// Cost: a batch's 10 representative ticks, the pipeline alone: a trace, not a bound.
#[test]
#[available_gas(l2_gas: 13911629)] // ceil(1.05 × 13249170 measured)
fn test_cost_batch_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59, 'ten ticks');
}

#[test]
#[available_gas(l2_gas: 7460355)] // ceil(1.05 × 7105100 measured)
fn test_cost_fixture_representative_words() {
    let (world, content) = representative();
    let words = world.store();
    assert(words.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// A batch's 10 representative ticks through one library call: load, ticks, store, the call.
#[test]
#[available_gas(l2_gas: 17140946)] // ceil(1.05 × 16324710 measured)
fn test_cost_library_call_batch_representative() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = representative();
    let words = library.run(world.store(), content, 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
#[available_gas(l2_gas: 7471391)] // ceil(1.05 × 7115610 measured)
fn test_cost_library_baseline_representative() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = representative();
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// Cost: one tick of `worst_state`'s scenario, the pipeline alone: a measured state under the upper
// bound (CBT-02b, below), not the bound.
#[test]
#[available_gas(l2_gas: 67784318)] // ceil(1.05 × 64556493 measured)
fn test_cost_tick_worst() {
    let (mut world, content) = worst_state(true, 3);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    let goblin = world.goblins.at(92);
    assert(*goblin.act_slot == activation::RECOVERING && goblin.recharge(0) == 59, 'concluded');
    assert(world.killed.len() == 8 && world.defeated, 'every death');
    assert(*world.members.at(0).act_slot == NO_SLOT, 'member resolved');
}

// The same construction with only the 8 awake goblins in the array (no frozen candidate): what
// the array's bound adds is the difference with `test_cost_tick_worst`.
#[test]
#[available_gas(l2_gas: 9658205)] // ceil(1.05 × 9198290 measured)
fn test_cost_fixture_worst_8() {
    let (world, _) = worst_of(true, 3, 8);
    assert(world.goblins.len() == 8, 'eight');
}

#[test]
#[available_gas(l2_gas: 12020887)] // ceil(1.05 × 11448463 measured)
fn test_cost_tick_worst_8() {
    let (mut world, content) = worst_of(true, 3, 8);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
}

// Cost: a busy 10-tick batch (weight 10), `Busy` keeping every awake goblin and the member
// resolving or acting at every tick: a measured scenario; every tick of a batch is under the tick's
// upper bound (CBT-02b, below).
#[test]
#[available_gas(l2_gas: 145237523)] // ceil(1.05 × 138321450 measured)
fn test_cost_batch_worst() {
    let (mut world, content) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59 && !world.defeated, 'ten ticks');
}

// Cost, once per call: loading `worst_words`' 101 actors from their words and storing them back
// (a measured scenario; load and store's upper bound is `test_cost_load_bound`'s, CBT-02b).
// The round trip returns exactly the words it was given (quality 4): every member and goblin word,
// the clock, the kills. Its baseline builds the same two fixtures.
#[test]
#[available_gas(l2_gas: 177249020)] // ceil(1.05 × 168808590 measured)
fn test_cost_load_store_worst() {
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let world = words.load(@content);
    let words = world.store();
    assert(words == expected, 'the round trip keeps every word');
}

#[test]
#[available_gas(l2_gas: 121443063)] // ceil(1.05 × 115660060 measured)
fn test_cost_fixture_worst_words_twice() {
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

/// 100 candidates, every one eligible (Alerted, alive), at distances falling along the array: each
/// of the 8 selection scans updates its running minimum at every element, the costliest order.
fn candidates() -> (World, Span<u16>) {
    let content = worst_content(3);
    let mut goblins = array![];
    let mut distances = array![];
    let mut i: u16 = 0;
    while i < 100 {
        goblins.append(GoblinTrait::load(goblin_words(8 + i, false, 280, 0, 0), @content));
        distances.append(200 - i);
        i += 1;
    }
    (Fixture::world(49, array![], goblins), distances.span())
}

// COST-1: the awake set's selection (§5.2) at the candidate bound, `MAX_GOBLINS` = 100: the 8
// nearest are the array's last 8.
#[test]
#[available_gas(l2_gas: 48294729)] // ceil(1.05 × 45994980 measured)
fn test_cost_awake_100() {
    let (mut world, distances) = candidates();
    TickTrait::awake(ref world, distances);
    assert(*world.goblins.at(92).awake && !*world.goblins.at(91).awake, 'the 8 nearest');
}

#[test]
#[available_gas(l2_gas: 43816595)] // ceil(1.05 × 41730090 measured)
fn test_cost_fixture_candidates() {
    let (world, distances) = candidates();
    assert(world.goblins.len() == 100 && distances.len() == 100, 'candidates');
}

// Cost of the library call (AC-3): the baseline declares the class and runs the call's body (load,
// one tick of `worst_state`'s scenario, store) in the test's own code; the next test runs it
// through `library_call`.
// The difference is the call: its syscall and the words and content through calldata and back.
#[test]
#[available_gas(l2_gas: 125276522)] // ceil(1.05 × 119310973 measured)
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
#[available_gas(l2_gas: 127983443)] // ceil(1.05 × 121888993 measured)
fn test_cost_library_call() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let words = library.run(words, content, 1);
    assert(words.clock == 50, 'one tick');
}

// Ten ticks through one library call over the busy state: the class runs its own rules (`Idle`
// until CBT-05 and ENG-07), so after the opening tick the goblins fall quiet. A trace of the call
// at the array's bound, not a bound (the tick's is CBT-02b's, below).
#[test]
#[available_gas(l2_gas: 153660906)] // ceil(1.05 × 146343720 measured)
fn test_cost_library_call_batch() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = worst_state(false, 1);
    let words = library.run(world.store(), content, 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
#[available_gas(l2_gas: 60736946)] // ceil(1.05 × 57844710 measured)
fn test_cost_library_baseline_batch() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = worst_state(false, 1);
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// The library call runs the pipeline: the same words as a direct run.
#[test]
#[available_gas(l2_gas: 253654261)] // ceil(1.05 × 241575486 measured)
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
#[available_gas(l2_gas: 1359740)] // ceil(1.05 × 1294990 measured)
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
#[available_gas(l2_gas: 424284)] // ceil(1.05 × 404080 measured)
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

// AUD-182-5 (design/19 §5.11, §5.13, FX-8): a member already at 0 when the tick begins (a trap on
// its move, in the action phase) stops it at once: the clock does not advance, no goblin acts,
// nothing regenerates, and step 5's defeat and objectives run.
#[test]
#[available_gas(l2_gas: 5276576)] // ceil(1.05 × 5025310 measured)
fn test_member_down_before_the_tick() {
    let mut spec = Fixture::spec();
    spec.health = 0;
    let mut goblin = Fixture::goblin(8, HOB);
    goblin.bleeding = 99;
    let mut world = Fixture::world(49, array![Fixture::member(spec)], array![goblin]);
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, @Fixture::content(), 3, ref rules);
    assert(rules.acts.len() == 0, 'no goblin acts');
    assert(world.clock == 49, 'the clock stays');
    assert(*world.goblins.at(0).health == 100, 'no step 3');
    assert(world.defeated && *world.members.at(0).status == status::DOWN, 'defeat ran');
}

// AUD-182-6, conditions (§5.7, FX-6, FX-31; design/19 §10.3): Bleeding to 77, inflicted again at
// 74 for 8 ticks, refreshes to 81; for 2 ticks, keeps 77 (`max`, not a replacement); Knocked down
// likewise; Crippled lives in the words; a cure at 76 gives 75; an absent condition is untouched;
// a dead goblin takes nothing.
#[test]
#[available_gas(l2_gas: 5877764)] // ceil(1.05 × 5597870 measured)
fn test_conditions_refresh_and_cure() {
    let mut member = Fixture::member(Fixture::spec());
    member.inflict(condition::BLEEDING, 70, 8);
    assert(member.bleeding == 77, 'D = 70 + 8 - 1');
    member.inflict(condition::BLEEDING, 74, 2);
    assert(member.bleeding == 77, 'max keeps 77');
    member.inflict(condition::BLEEDING, 74, 8);
    assert(member.bleeding == 81, 'refreshed to 81');
    member.inflict(condition::KNOCKED_DOWN, 52, 2);
    member.inflict(condition::KNOCKED_DOWN, 52, 1);
    assert(member.knocked == 53, 'knock-down refreshed');
    member.inflict(condition::CRIPPLED, 60, 3);
    assert(member.crippled() == 62, 'crippled in the words');
    let words = member.store();
    let again = MemberTrait::load(words, @Fixture::content());
    assert(again.crippled() == 62 && again.bleeding == 81, 'stored');
    member.cure(condition::BLEEDING, 76);
    assert(member.bleeding == 75, 'cured: D = 75');
    member.cure(condition::POISON, 76);
    assert(member.poison == 0, 'absent: nothing');
    let mut dead = Fixture::goblin(8, HOB);
    dead.ai = ai::DEAD;
    dead.inflict(condition::POISON, 10, 5);
    assert(dead.poison == 0, 'a dead goblin takes nothing');
    let mut goblin = Fixture::goblin(9, HOB);
    goblin.inflict(condition::CRIPPLED, 10, 5);
    goblin.inflict(condition::POISON, 10, 5);
    assert(goblin.crippled() == 14 && goblin.poison == 14, 'goblin conditions');
}

/// Skills of design/19 §10.4: Stone Skin 11 (an enchantment), Warcry 12 (a shout), Venom Coat 13
/// (a preparation), Sidestep 14 and Brace 15 (stances), and the bar's 1–8.
fn hold_content() -> Content {
    let mut skills = array![];
    for id in 1..9_u16 {
        skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
    }
    skills.append(Fixture::skill(11, skill_kind::ENCHANTMENT, 1, 10));
    skills.append(Fixture::skill(12, skill_kind::SHOUT, 0, 10));
    skills.append(Fixture::skill(13, skill_kind::PREPARATION, 0, 10));
    skills.append(Fixture::skill(14, skill_kind::STANCE, 0, 10));
    let mut brace = Fixture::skill(15, skill_kind::STANCE, 0, 10);
    brace.regen0 = 1;
    brace.regen12 = 1;
    skills.append(brace);
    Content {
        skills: skills.span(),
        potions: array![
            PotionSheet { id: 100, regen: 1 }, PotionSheet { id: 101, regen: 2 },
            PotionSheet { id: 102, regen: 3 }, PotionSheet { id: 103, regen: 4 },
        ]
            .span(),
        castes: array![].span(),
    }
}

fn held(carrier: u16, potion: bool, deadline: u32, rank: u8) -> Held {
    Held { carrier, potion, charges: 0, deadline, rank }
}

// AUD-182-6, held effects (§5.7; design/19 §10.4): four effects held and no stance; Sidestep at
// clock 80 (`t₀` 81, `D` 86) evicts the earliest deadline, 85, ties to the lowest slot: Warcry in
// slot 1. Brace at 82, a stance while one is held, takes Sidestep's slot.
#[test]
#[available_gas(l2_gas: 7546266)] // ceil(1.05 × 7186920 measured)
fn test_hold_eviction_and_stance() {
    let content = hold_content();
    let mut spec = Fixture::spec();
    spec
        .effects =
            [(11, false, 90, 12), (12, false, 85, 12), (13, false, 85, 12), (3, true, 100, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    let slot = member.hold(held(14, false, 86, 12), true, 81, @content);
    assert(slot == 1 && member.effect_of(1) == held(14, false, 86, 12), 'Warcry evicted');
    let slot = member.hold(held(15, false, 90, 12), true, 83, @content);
    assert(slot == 1 && member.effect_of(1).carrier == 15, 'stance replaces stance');
    assert(member.effect_regen == [0, 1, 0, 4], 'pips follow');
    assert(member.effect_deadlines == [90, 90, 85, 100], 'deadlines follow');
    // A free slot (a deadline passed) is taken before any eviction, the lowest first.
    let slot = member.hold(held(12, false, 95, 12), false, 86, @content);
    assert(slot == 2, 'lowest free slot');
    // The words round-trip what was held.
    let again = MemberTrait::load(member.store(), @content);
    assert(again.effect_of(2) == held(12, false, 95, 12), 'stored');
}

// AUD-182-6, refresh (FX-30, FX-42): the same carrier keeps the later deadline, whole; the new one
// on a tie; two belt slots holding the same potion item are one carrier.
#[test]
#[available_gas(l2_gas: 7417326)] // ceil(1.05 × 7064120 measured)
fn test_hold_refresh() {
    let content = hold_content();
    let mut spec = Fixture::spec();
    spec.effects = [(11, false, 90, 4), (0, false, 0, 0), (0, false, 0, 0), (0, false, 0, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    member.hold(held(11, false, 88, 12), false, 81, @content);
    assert(member.effect_of(0) == held(11, false, 90, 4), 'earlier: kept');
    member.hold(held(11, false, 90, 12), false, 81, @content);
    assert(member.effect_of(0) == held(11, false, 90, 12), 'tie: the new one');
    member.hold(held(11, false, 95, 7), false, 81, @content);
    assert(member.effect_of(0) == held(11, false, 95, 7), 'later: replaced whole');
    // Belt slots 0 and 2 hold one item: one carrier.
    let mut words = member.store();
    words.kit = LIVE + 100 + 101 * two(32) + 100 * two(64) + 103 * two(96);
    let mut member = MemberTrait::load(words, @content);
    let first = member.hold(held(0, true, 99, 0), false, 81, @content);
    let second = member.hold(held(2, true, 120, 0), false, 81, @content);
    assert(first == 1 && second == 1, 'same potion, same slot');
    assert(member.effect_of(1) == held(2, true, 120, 0), 'later potion kept');
    // A goblin's one slot: refreshed by its carrier, replaced by another.
    let mut goblin = Fixture::goblin(8, HOB);
    goblin.hold(held(11, false, 50, 3), 40, @content);
    goblin.hold(held(11, false, 45, 3), 40, @content);
    assert(goblin.effect_of().deadline == 50, 'goblin keeps the later');
    goblin.hold(held(15, false, 44, 12), 40, @content);
    assert(goblin.effect_of() == held(15, false, 44, 12) && goblin.effect_regen == 1, 'replaced');
}

// AUD-182-6, adrenaline gain (§5.12, FX-12): 4 quarters a weapon hit landed, 8 on every N-th hit
// (`hits` resets at N), 1 a hit taken; each gain capped at the bar's highest adrenaline cost (6
// strikes: 24 quarters); a goblin's at its caste's, at most 252.
#[test]
#[available_gas(l2_gas: 6104333)] // ceil(1.05 × 5813650 measured)
fn test_adrenaline_gain() {
    let mut skills = array![];
    for id in 1..9_u16 {
        let mut sheet = Fixture::skill(id, skill_kind::ATTACK, 0, 0);
        sheet.adrenaline = if id == 2 {
            6
        } else {
            0
        };
        skills.append(sheet);
    }
    skills.append(Fixture::skill(24, skill_kind::ATTACK, 1, 10));
    let mut heavy = Fixture::skill(25, skill_kind::ATTACK, 0, 0);
    heavy.adrenaline = 63;
    skills.append(heavy);
    skills.append(Fixture::skill(26, skill_kind::SPELL, 1, 10));
    skills.append(Fixture::skill(27, skill_kind::SHOUT, 0, 10));
    let content = Content {
        skills: skills.span(),
        potions: array![].span(),
        castes: array![Fixture::caste(HOB, 1)].span(),
    };
    let mut words = Fixture::member_words(Fixture::spec());
    // `ADRENALINE_EVERY_N` = 3 in the kit (bits 160–167).
    words.kit += 3 * two(160);
    let mut member = MemberTrait::load(words, @content);
    assert(member.adrenaline_cap == 24, 'cap: 6 strikes');
    member.land_weapon_hit();
    member.land_weapon_hit();
    assert(member.adrenaline == 8 && member.hits() == 2, 'two hits: 8');
    member.land_weapon_hit();
    assert(member.adrenaline == 16 && member.hits() == 0, 'third doubled, reset');
    member.take_hit();
    assert(member.adrenaline == 17, 'a hit taken: 1');
    member.land_weapon_hit();
    member.land_weapon_hit();
    assert(member.adrenaline == 24, 'capped at 24');
    // A goblin of caste 1, whose skill 25 costs 63 strikes: its cap is the field's 252.
    let goblin_words = GoblinWords {
        entity: 8, awake: true, state: Fixture::goblin(8, HOB).state, timers: LIVE + 255,
    };
    let mut goblin = GoblinTrait::load(goblin_words, @content);
    assert(goblin.adrenaline_cap == 252, 'goblin cap 252');
    goblin.adrenaline = 250;
    goblin.land_weapon_hit();
    assert(goblin.adrenaline == 252, 'goblin capped');
    goblin.ai = ai::DEAD;
    goblin.adrenaline = 0;
    goblin.take_hit();
    assert(goblin.adrenaline == 0, 'dead: nothing');
}

// AUD-182-9: the words' decoders are the entities' own (`MemberTrait::hot`, `GoblinTrait::hot`).
#[test]
#[available_gas(l2_gas: 5241800)] // ceil(1.05 × 4992190 measured)
fn test_hot_decoders() {
    let mut spec = Fixture::spec();
    spec.conditions = [11, 12, 13, 14];
    let words = Fixture::member_words(spec);
    let (status, health, _, _, _, slot, _, _, _, bleeding, _, _, knocked) = MemberTrait::hot(
        @words,
    );
    assert(status == status::INSIDE && health == 400 && slot == NO_SLOT, 'member');
    assert(bleeding == 11 && knocked == 14, 'member timers');
    let goblin = Fixture::goblin(8, RUNT);
    let (state_ai, health, _, _, caste, slot, _, _, _, _, _, _, _, level, _, _) = GoblinTrait::hot(
        goblin.state, goblin.timers,
    );
    assert(state_ai == ai::ENGAGED && health == 100 && caste == RUNT, 'goblin');
    assert(slot == activation::NONE && level == 10, 'goblin timers');
}

// ---------------------------------------------------------------------------------------------
// COST-1 (CBT-02's fix loop 3, kept by CBT-02b): the terms of a tick's cost, each measured apart.
// A lookup's cost grows with the record's position: one more comparison in each content list. The
// base: the tick with no awake goblin (the member concluding and dying, the 100-goblin array).
// Each branch of step 1 a single awake goblin can take, its lookups at the end of their lists,
// dying and surviving. CBT-02b adds the branches and the eight-goblin states it lacked, and sums
// the terms into the upper bound (below; REPORT.md).

/// Step 1's branches of one awake goblin (design/19 §5.2).
const B_NONE: u8 = 0;
const B_CONCLUDE_RECOVER: u8 = 1;
const B_CONCLUDE_CLEAR: u8 = 2;
const B_LAPSE: u8 = 3;
const B_RECOVERY_END: u8 = 4;
const B_ACTIVATING: u8 = 5;
const B_FREE: u8 = 6;

/// `goblin_words` with its activation field's slot: a caste skill 0–3 due at `due`, or
/// `activation::RECOVERING` until `due`, or none.
fn goblin_words_at(
    entity: u16, awake: bool, health: u16, slot: u8, due: u32, until: u32,
) -> GoblinWords {
    let mut words = goblin_words(entity, awake, health, 0, until);
    words.timers += slot.into() - activation::NONE.into() + due.into() * B24;
    words
}

/// `worst_content(k)` with skill 43, the list's last, an attack skill of activation 1: the branch
/// goblin concludes it (slot 3) and holds it as its effect, so each of its lookups ends its list.
fn branch_content(k: u8) -> Content {
    let content = worst_content(k);
    let mut skills = array![];
    for sheet in content.skills {
        let mut sheet = *sheet;
        if sheet.id == 43 {
            sheet.kind = skill_kind::ATTACK;
        }
        skills.append(sheet);
    }
    Content { skills: skills.span(), ..content }
}

/// The member of `worst_state` (concluding bar slot 7 at 50, three conditions, four effects),
/// dying or not; the 100-goblin array, all frozen but the last, which takes `branch` (none for
/// `B_NONE`), dying or not.
fn branch_world(branch: u8, dying: bool, member_dying: bool) -> (World, Content) {
    branch_world_n(branch, dying, member_dying, 1)
}

/// `branch_world` with the last `n` goblins all taking `branch`.
fn branch_world_n(branch: u8, dying: bool, member_dying: bool, n: u16) -> (World, Content) {
    let k = if branch == B_CONCLUDE_CLEAR {
        1
    } else {
        3
    };
    let content = branch_content(k);
    let mut spec = Fixture::spec();
    spec.health = if member_dying {
        7
    } else {
        400
    };
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    member.start(7, 8, 1, 49);
    let health: u16 = if dying {
        1
    } else {
        280
    };
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 - n {
        goblins.append(GoblinTrait::load(goblin_words(8 + i, false, 280, 0, 99), @content));
        i += 1;
    }
    let (awake, slot, due) = if branch == B_NONE {
        (false, activation::NONE, 0)
    } else if branch == B_CONCLUDE_RECOVER || branch == B_CONCLUDE_CLEAR {
        (true, 3, 50)
    } else if branch == B_LAPSE {
        (true, 3, 45)
    } else if branch == B_RECOVERY_END {
        (true, activation::RECOVERING, 48)
    } else if branch == B_ACTIVATING {
        (true, 3, 55)
    } else {
        (true, activation::NONE, 0)
    };
    while i < 100 {
        let words = goblin_words_at(8 + i, awake, health, slot, due, 99);
        goblins.append(GoblinTrait::load(words, @content));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), content)
}

fn branch_tick(branch: u8, dying: bool, member_dying: bool) {
    let (mut world, content) = branch_world(branch, dying, member_dying);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50, 'one tick');
}

fn branch_fixture(branch: u8, dying: bool, member_dying: bool) {
    let (world, content) = branch_world(branch, dying, member_dying);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

// Each branch is the one named (not a cost test).
#[test]
#[available_gas(l2_gas: 310127490)] // ceil(1.05 × 295359514 measured)
fn test_branch_worlds_take_their_branch() {
    let content = branch_content(3);
    let mut rules: Script = Default::default();
    let (mut world, _) = branch_world(B_CONCLUDE_RECOVER, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(*world.goblins.at(99).act_slot == activation::RECOVERING, 'recover');
    assert(rules.resolved.len() == 2 && rules.acts.len() == 0, 'resolved');
    let (mut world, _) = branch_world(B_LAPSE, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.goblins.at(99).recharge(3) == 45 + 20 - 1, 'lapsed');
    let (mut world, _) = branch_world(B_RECOVERY_END, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(*world.goblins.at(99).act_slot == activation::NONE, 'recovery ended');
    let (mut world, _) = branch_world(B_ACTIVATING, true, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.killed.len() == 1 && *world.goblins.at(99).act_slot == 3, 'busy, died');
    let content = branch_content(1);
    let (mut world, _) = branch_world(B_CONCLUDE_CLEAR, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(*world.goblins.at(99).act_slot == activation::NONE, 'cleared');
}

// 8 goblins all lapsing, dying: a lapse's term with eight goblins (CBT-02b's per-goblin terms).
#[test]
#[available_gas(l2_gas: 63418863)] // ceil(1.05 × 60398917 measured)
fn test_cost_bound_eight_lapses() {
    let (mut world, content) = branch_world_n(B_LAPSE, true, true, 8);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8, 'eight deaths');
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_lapses_fixture() {
    let (world, content) = branch_world_n(B_LAPSE, true, true, 8);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 59741665)] // ceil(1.05 × 56896823 measured)
fn test_cost_bound_base() {
    branch_tick(B_NONE, false, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_base_fixture() {
    branch_fixture(B_NONE, false, true);
}

#[test]
#[available_gas(l2_gas: 59731721)] // ceil(1.05 × 56887353 measured)
fn test_cost_bound_base_member_alive() {
    branch_tick(B_NONE, false, false);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_base_member_alive_fixture() {
    branch_fixture(B_NONE, false, false);
}

#[test]
#[available_gas(l2_gas: 61970059)] // ceil(1.05 × 59019103 measured)
fn test_cost_bound_conclude_recover() {
    branch_tick(B_CONCLUDE_RECOVER, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_conclude_recover_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, true, true);
}

#[test]
#[available_gas(l2_gas: 61969849)] // ceil(1.05 × 59018903 measured)
fn test_cost_bound_conclude_recover_alive() {
    branch_tick(B_CONCLUDE_RECOVER, false, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_conclude_recover_alive_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, false, true);
}

#[test]
#[available_gas(l2_gas: 61971080)] // ceil(1.05 × 59020076 measured)
fn test_cost_bound_conclude_clear() {
    branch_tick(B_CONCLUDE_CLEAR, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_conclude_clear_fixture() {
    branch_fixture(B_CONCLUDE_CLEAR, true, true);
}

#[test]
#[available_gas(l2_gas: 61980194)] // ceil(1.05 × 59028756 measured)
fn test_cost_bound_lapse() {
    branch_tick(B_LAPSE, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_lapse_fixture() {
    branch_fixture(B_LAPSE, true, true);
}

#[test]
#[available_gas(l2_gas: 61834685)] // ceil(1.05 × 58890176 measured)
fn test_cost_bound_recovery_end() {
    branch_tick(B_RECOVERY_END, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_recovery_end_fixture() {
    branch_fixture(B_RECOVERY_END, true, true);
}

#[test]
#[available_gas(l2_gas: 61184186)] // ceil(1.05 × 58270653 measured)
fn test_cost_bound_activating() {
    branch_tick(B_ACTIVATING, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_activating_fixture() {
    branch_fixture(B_ACTIVATING, true, true);
}

#[test]
#[available_gas(l2_gas: 61191119)] // ceil(1.05 × 58277256 measured)
fn test_cost_bound_free() {
    branch_tick(B_FREE, true, true);
}

#[test]
#[available_gas(l2_gas: 58588173)] // ceil(1.05 × 55798260 measured)
fn test_cost_bound_free_fixture() {
    branch_fixture(B_FREE, true, true);
}

// One more comparison in each content list: a lookup of the last record against the first, in
// the same content (38 skills, 5 castes, 4 potions); the difference over the positions between.
#[test]
#[available_gas(l2_gas: 317079)] // ceil(1.05 × 301980 measured)
fn test_cost_scan_skill_first() {
    let content = branch_content(3);
    assert(*content.skill(1).id == 1, 'first');
}

#[test]
#[available_gas(l2_gas: 401384)] // ceil(1.05 × 382270 measured)
fn test_cost_scan_skill_last() {
    let content = branch_content(3);
    assert(*content.skill(43).id == 43, 'last');
}

#[test]
#[available_gas(l2_gas: 317709)] // ceil(1.05 × 302580 measured)
fn test_cost_scan_caste_first() {
    let content = branch_content(3);
    assert(*content.caste(1).id == 1, 'first');
}

#[test]
#[available_gas(l2_gas: 328083)] // ceil(1.05 × 312460 measured)
fn test_cost_scan_caste_last() {
    let content = branch_content(3);
    assert(*content.caste(5).id == 5, 'last');
}

#[test]
#[available_gas(l2_gas: 316029)] // ceil(1.05 × 300980 measured)
fn test_cost_scan_potion_first() {
    let content = branch_content(3);
    assert(*content.potion(100).id == 100, 'first');
}

#[test]
#[available_gas(l2_gas: 321290)] // ceil(1.05 × 305990 measured)
fn test_cost_scan_potion_last() {
    let content = branch_content(3);
    assert(*content.potion(103).id == 103, 'last');
}

/// A member's words whose four effects are the content's last four skills (40–43, positions
/// 35–38) or its four potions (belt slots 0–3, items 100–103), for the load's two effect
/// branches.
fn member_effect_words(potions: bool) -> MemberWords {
    let mut spec = Fixture::spec();
    spec
        .effects =
            if potions {
                [(0, true, 99, 0), (1, true, 99, 0), (2, true, 99, 0), (3, true, 99, 0)]
            } else {
                [(40, false, 99, 12), (41, false, 99, 12), (42, false, 99, 12), (43, false, 99, 12)]
            };
    Fixture::member_words(spec)
}

#[test]
#[available_gas(l2_gas: 5814396)] // ceil(1.05 × 5537520 measured)
fn test_cost_load_member_skills() {
    let content = branch_content(3);
    let words = member_effect_words(false);
    assert(words.state != 0 && content.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, @content);
    assert(member.max_health == 480, 'loaded');
}

#[test]
#[available_gas(l2_gas: 5488455)] // ceil(1.05 × 5227100 measured)
fn test_cost_load_member_potions() {
    let content = branch_content(3);
    let words = member_effect_words(true);
    assert(words.state != 0 && content.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, @content);
    assert(member.max_health == 480, 'loaded');
}

#[test]
#[available_gas(l2_gas: 5174705)] // ceil(1.05 × 4928290 measured)
fn test_cost_load_member_skills_fixture() {
    let content = branch_content(3);
    let words = member_effect_words(false);
    assert(words.state != 0 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 5173970)] // ceil(1.05 × 4927590 measured)
fn test_cost_load_member_potions_fixture() {
    let content = branch_content(3);
    let words = member_effect_words(true);
    assert(words.state != 0 && content.skills.len() == 38, 'fixture');
}

// The audit's permutation (skills 40 and 42 exchanged, so every conclusion's lookup goes 2 further)
// measured under the tick's upper bound (CBT-02b, REPORT.md).
fn permuted(content: Content) -> Content {
    let mut skills = array![];
    for sheet in content.skills {
        let mut sheet = *sheet;
        if sheet.id == 40 {
            sheet = *content.skill(42);
        } else if sheet.id == 42 {
            sheet = *content.skill(40);
        }
        skills.append(sheet);
    }
    Content { skills: skills.span(), ..content }
}

#[test]
#[available_gas(l2_gas: 68181386)] // ceil(1.05 × 64934653 measured)
fn test_cost_tick_worst_permuted() {
    let (mut world, content) = worst_state(true, 3);
    let content = permuted(content);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
}

#[test]
#[available_gas(l2_gas: 59022285)] // ceil(1.05 × 56211700 measured)
fn test_cost_fixture_worst_permuted() {
    let (world, content) = worst_state(true, 3);
    let content = permuted(content);
    assert(world.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

// The quality minor (fix loop 3): the checks are the Assert impls', with their errors.
#[test]
#[should_panic(expected: 'tick: too many goblins')]
#[available_gas(l2_gas: 29072463)] // ceil(1.05 × 27688060 measured)
fn test_world_assert_goblins() {
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 101 {
        goblins.append(Fixture::goblin(8 + i, HOB));
        i += 1;
    }
    let world = Fixture::world(0, array![], goblins);
    world.assert_goblins();
}

#[test]
#[should_panic(expected: 'tick: one distance a goblin')]
#[available_gas(l2_gas: 297969)] // ceil(1.05 × 283780 measured)
fn test_world_assert_distances() {
    let world = Fixture::world(0, array![], array![Fixture::goblin(8, HOB)]);
    world.assert_distances(array![].span());
}

#[test]
#[should_panic(expected: 'member: regeneration above i8')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_member_assert_pips() {
    MemberAssert::assert_pips(128);
}

#[test]
#[should_panic(expected: 'goblin: regeneration above i8')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_goblin_assert_pips() {
    GoblinAssert::assert_pips(-129);
}

// ---------------------------------------------------------------------------------------------
// CBT-02b (D-163; COST-1a to COST-1c): the tick's upper bound, proved term by term.
//
// **What can vary.** Sierra charges a function that has no loop and calls none the gas of its
// costliest path, whatever path runs: a branch there cannot change the cost. A function with a
// loop, or calling one, pays the path it takes. A tick's cost, load and store's, and the sheets'
// therefore vary only with their loops: how many times each runs, which path each iteration
// takes, and how far each lookup scans its list. The tests below
// - show the first rule on every arithmetic branch the audits named (`test_cost_path_*`: one
//   goblin's and one member's step 3 on every path, `store`, `line`; each group measures the same);
// - measure each loop's iterations on their costliest paths, at the counts' bounds: the tick's
//   step 1 branches with 1 and 8 awake goblins (`test_cost_bound_*`), load and store
//   (`test_cost_load_bound`), the sheets (`test_cost_sheet_*`), the library call's lists
//   (`test_cost_library_*`).
// REPORT.md and ENG-01 §9.2 sum them.

/// Keeps a value from the compiler's constant folding, so that the path under test runs.
#[inline(never)]
fn opaque<T, +Drop<T>>(value: T) -> T {
    value
}

/// One goblin's step 3 (`GoblinTickTrait::regenerate`, no loop): its three degenerating
/// conditions to `until`, its effect's pips until `effect_until`, its regeneration, health, energy,
/// AI state and adrenaline; max health 280, max energy 30, energy regeneration 1, tick 50.
fn regenerate_goblin(
    until: u32,
    effect: i8,
    effect_until: u32,
    regen: i8,
    health: u16,
    energy: u8,
    state: u8,
    adrenaline: u8,
) -> u16 {
    let mut goblin = opaque(Fixture::goblin(8, HOB));
    goblin.bleeding = opaque(until);
    goblin.poison = opaque(until);
    goblin.burning = opaque(until);
    goblin.effect_regen = opaque(effect);
    goblin.effect_deadline = opaque(effect_until);
    goblin.health_regen = opaque(regen);
    goblin.health = opaque(health);
    goblin.energy = opaque(energy);
    goblin.ai = opaque(state);
    goblin.adrenaline = opaque(adrenaline);
    goblin.regenerate(opaque(50));
    goblin.health
}

/// One member's step 3 (`MemberTickTrait::regenerate`, no loop): its conditions to `until`, its
/// four effects' pips until `effect_until`, its regeneration, health, energy, whether the awake
/// set is engaged and its adrenaline; max health 480, max energy 60 thirds, regeneration 2.
fn regenerate_member(
    until: u32,
    effect: i8,
    effect_until: u32,
    regen: i8,
    health: u16,
    energy: u16,
    engaged: bool,
    adrenaline: u16,
) -> u16 {
    let mut member = opaque(Fixture::member(Fixture::spec()));
    member.bleeding = opaque(until);
    member.poison = opaque(until);
    member.burning = opaque(until);
    member.effect_regen = opaque([effect; 4]);
    member.effect_deadlines = opaque([effect_until; 4]);
    member.health_regen = opaque(regen);
    member.health = opaque(health);
    member.energy = opaque(energy);
    member.adrenaline = opaque(adrenaline);
    member.regenerate(opaque(50), opaque(engaged));
    member.health
}

// COST-1a: every path of one goblin's step 3 costs the same.

// A goblin's step 3, the pips below −10 (clamped), health lost.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_below() {
    assert(regenerate_goblin(99, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_below_dead() {
    assert(regenerate_goblin(99, 2, 99, 0, 15, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in −10…−1.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_down() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_down_dead() {
    assert(regenerate_goblin(99, 2, 99, 5, 10, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in 0…10.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_up() {
    assert(regenerate_goblin(0, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_up_full() {
    assert(regenerate_goblin(0, 2, 99, 0, 278, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips above 10 (clamped).
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_above() {
    assert(regenerate_goblin(0, 10, 99, 10, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_above_full() {
    assert(regenerate_goblin(0, 10, 99, 10, 270, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no effect pips.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_effect_zero() {
    assert(regenerate_goblin(99, 0, 99, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, an effect over.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_effect_over() {
    assert(regenerate_goblin(99, 2, 40, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, energy to its max.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_energy_capped() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 30, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no adrenaline to decay.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_adrenaline_zero() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 0) <= 280, 'health');
}

// A goblin's step 3, Engaged: no decay.
#[test]
#[available_gas(l2_gas: 332042)] // ceil(1.05 × 316230 measured)
fn test_cost_path_goblin_engaged() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ENGAGED, 5) <= 280, 'health');
}

// COST-1a: every path of one member's step 3 costs the same.

// A member's step 3, the pips below −10 (clamped), health lost.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_below() {
    assert(regenerate_member(99, 2, 99, -10, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to 0.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_below_dead() {
    assert(regenerate_member(99, 2, 99, -10, 15, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips in −10…−1.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_down() {
    assert(regenerate_member(99, 2, 99, -2, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to 0.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_down_dead() {
    assert(regenerate_member(99, 2, 99, -2, 10, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips in 0…10.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_up() {
    assert(regenerate_member(0, 2, 99, 0, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to its max.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_up_full() {
    assert(regenerate_member(0, 2, 99, 0, 478, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips above 10 (clamped).
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_above() {
    assert(regenerate_member(0, 3, 99, 5, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to its max.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_above_full() {
    assert(regenerate_member(0, 3, 99, 5, 475, 30, false, 5) <= 480, 'health');
}

// A member's step 3, no effect pips (the effects' block skipped).
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_effects_zero() {
    assert(regenerate_member(99, 0, 99, 6, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the effects over.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_effects_over() {
    assert(regenerate_member(99, 2, 40, 6, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, energy to its max.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_energy_capped() {
    assert(regenerate_member(99, 2, 99, -2, 100, 59, false, 5) <= 480, 'health');
}

// A member's step 3, no adrenaline to decay.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_adrenaline_zero() {
    assert(regenerate_member(99, 2, 99, -2, 100, 30, false, 0) <= 480, 'health');
}

// A member's step 3, in combat: no decay.
#[test]
#[available_gas(l2_gas: 4930149)] // ceil(1.05 × 4695380 measured)
fn test_cost_path_member_engaged() {
    assert(regenerate_member(99, 2, 99, -2, 100, 30, true, 5) <= 480, 'health');
}

// `store` has no loop: a goblin's and a member's words cost the same written back unchanged or
// changed in every hot field.
fn store_goblin(state: u8, health: u16, small: u8, slot: u8, deadline: u32) -> felt252 {
    let mut goblin = opaque(Fixture::goblin(9, RUNT));
    goblin.ai = opaque(state);
    goblin.health = opaque(health);
    goblin.energy = opaque(small);
    goblin.adrenaline = opaque(small);
    goblin.act_slot = opaque(slot);
    goblin.act_target = opaque(small.into());
    goblin.act_deadline = opaque(deadline);
    goblin.bleeding = opaque(deadline);
    goblin.poison = opaque(deadline);
    goblin.burning = opaque(deadline);
    goblin.knocked = opaque(deadline);
    goblin.effect_deadline = opaque(deadline);
    goblin.store().state
}

fn store_member(
    state: u8, health: u16, energy: u16, small: u16, slot: u8, deadline: u32,
) -> MemberWords {
    let mut member = opaque(Fixture::member(Fixture::spec()));
    member.status = opaque(state);
    member.health = opaque(health);
    member.energy = opaque(energy);
    member.adrenaline = opaque(small);
    member.flags = opaque(small.try_into().unwrap());
    member.act_slot = opaque(slot);
    member.act_target = opaque(small);
    member.act_tile = opaque(small.try_into().unwrap());
    member.act_deadline = opaque(deadline);
    member.bleeding = opaque(deadline);
    member.poison = opaque(deadline);
    member.burning = opaque(deadline);
    member.knocked = opaque(deadline);
    member.store()
}

#[test]
#[available_gas(l2_gas: 612108)] // ceil(1.05 × 582960 measured)
fn test_cost_path_goblin_store_same() {
    let words = Fixture::goblin(9, RUNT).state;
    assert(store_goblin(ai::ENGAGED, 100, 0, activation::NONE, 0) == words, 'same');
}

#[test]
#[available_gas(l2_gas: 612108)] // ceil(1.05 × 582960 measured)
fn test_cost_path_goblin_store_changed() {
    let words = Fixture::goblin(9, RUNT).state;
    assert(store_goblin(ai::DEAD, 0, 3, activation::RECOVERING, 60) != words, 'changed');
}

#[test]
#[available_gas(l2_gas: 9784131)] // ceil(1.05 × 9318220 measured)
fn test_cost_path_member_store_same() {
    let words = Fixture::member_words(Fixture::spec());
    assert(store_member(status::INSIDE, 400, 30, 0, NO_SLOT, 0).state == words.state, 'same');
}

#[test]
#[available_gas(l2_gas: 9784131)] // ceil(1.05 × 9318220 measured)
fn test_cost_path_member_store_changed() {
    let words = Fixture::member_words(Fixture::spec());
    assert(store_member(status::DOWN, 0, 3, 3, 4, 60).state != words.state, 'changed');
}

// `EntryTrait::line` has no loop: an effect's pips at a rank cost the same rising or falling
// (the signed division's branches).
#[test]
#[available_gas(l2_gas: 22701)] // ceil(1.05 × 21620 measured)
fn test_cost_path_line_rising() {
    assert(EntryTrait::line(opaque(2), opaque(6), opaque(8)) == 4, 'rising');
}

#[test]
#[available_gas(l2_gas: 22701)] // ceil(1.05 × 21620 measured)
fn test_cost_path_line_falling() {
    assert(EntryTrait::line(opaque(6), opaque(-10), opaque(9)) == -6, 'falling');
}

// COST-1a: step 1's branches, each taken by 1 and by 8 awake goblins in the 100-goblin array, every
// goblin dying in step 3, the member concluding and dying (`branch_world_n`). CBT-02's single-
// goblin tests (`test_cost_bound_*` above) give the branches it named; these add the four it did
// not, and the eight-goblin states. Per goblin, `(T(8) − T(1)) / 7`; what a tick pays once (step
// 3's rebuild, step 1's last one) is `T(1) − base −` that.

/// Step 1's branches CBT-02 did not measure: a lapse whose later recharge is kept, a recovery that
/// runs on, an awake goblin already dead, a free goblin knocked down.
const B_LAPSE_KEEP: u8 = 7;
const B_RECOVERING: u8 = 8;
const B_DEAD: u8 = 9;
const B_KNOCKED: u8 = 10;

const B184: felt252 = 0x10000000000000000000000000000000000000000000000;

/// `branch_world_n(branch, true, true, n)` for every branch: the last `n` of the 100 goblins take
/// it and die in step 3, the member concludes bar slot 7 and dies.
fn bound_world(branch: u8, n: u16) -> (World, Content) {
    if branch < B_LAPSE_KEEP {
        return branch_world_n(branch, true, true, n);
    }
    let content = branch_content(3);
    let mut spec = Fixture::spec();
    spec.health = 7;
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    member.start(7, 8, 1, 49);
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 - n {
        goblins.append(GoblinTrait::load(goblin_words(8 + i, false, 280, 0, 99), @content));
        i += 1;
    }
    while i < 100 {
        let mut words = if branch == B_LAPSE_KEEP {
            goblin_words_at(8 + i, true, 1, 3, 45, 99)
        } else if branch == B_RECOVERING {
            goblin_words_at(8 + i, true, 1, activation::RECOVERING, 55, 99)
        } else {
            goblin_words_at(8 + i, true, 1, activation::NONE, 0, 99)
        };
        if branch == B_LAPSE_KEEP {
            // Slot 3's recharge at 100, later than the lapse's 45 + 20 − 1.
            words.state += 100 * B212;
        } else if branch == B_DEAD {
            words.state += (ai::DEAD - ai::ALERTED).into() * B24;
        } else if branch == B_KNOCKED {
            words.timers += 60 * B184;
        }
        goblins.append(GoblinTrait::load(words, @content));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), content)
}

fn bound_tick(branch: u8, n: u16) {
    let (mut world, content) = bound_world(branch, n);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50 && world.defeated, 'one tick');
}

fn bound_fixture(branch: u8, n: u16) {
    let (world, content) = bound_world(branch, n);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

// One goblin: a lapse, the later recharge kept.
#[test]
#[available_gas(l2_gas: 62015254)] // ceil(1.05 × 59062146 measured)
fn test_cost_bound_lapse_keep() {
    bound_tick(B_LAPSE_KEEP, 1);
}

#[test]
#[available_gas(l2_gas: 58640306)] // ceil(1.05 × 55847910 measured)
fn test_cost_bound_lapse_keep_fixture() {
    bound_fixture(B_LAPSE_KEEP, 1);
}

// One goblin: a recovery running on.
#[test]
#[available_gas(l2_gas: 61238923)] // ceil(1.05 × 58322783 measured)
fn test_cost_bound_recovering() {
    bound_tick(B_RECOVERING, 1);
}

#[test]
#[available_gas(l2_gas: 58641314)] // ceil(1.05 × 55848870 measured)
fn test_cost_bound_recovering_fixture() {
    bound_fixture(B_RECOVERING, 1);
}

// One goblin: an awake goblin already dead.
#[test]
#[available_gas(l2_gas: 61217324)] // ceil(1.05 × 58302213 measured)
fn test_cost_bound_dead() {
    bound_tick(B_DEAD, 1);
}

#[test]
#[available_gas(l2_gas: 58640925)] // ceil(1.05 × 55848500 measured)
fn test_cost_bound_dead_fixture() {
    bound_fixture(B_DEAD, 1);
}

// One goblin: a free goblin knocked down.
#[test]
#[available_gas(l2_gas: 61239028)] // ceil(1.05 × 58322883 measured)
fn test_cost_bound_knocked() {
    bound_tick(B_KNOCKED, 1);
}

#[test]
#[available_gas(l2_gas: 58641314)] // ceil(1.05 × 55848870 measured)
fn test_cost_bound_knocked_fixture() {
    bound_fixture(B_KNOCKED, 1);
}

// Eight goblins: concluding into a recovery.
#[test]
#[available_gas(l2_gas: 67774973)] // ceil(1.05 × 64547593 measured)
fn test_cost_bound_eight_conclude_recover() {
    bound_tick(B_CONCLUDE_RECOVER, 8);
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_conclude_recover_fixture() {
    bound_fixture(B_CONCLUDE_RECOVER, 8);
}

// Eight goblins: concluding, the field cleared.
#[test]
#[available_gas(l2_gas: 67783146)] // ceil(1.05 × 64555377 measured)
fn test_cost_bound_eight_conclude_clear() {
    bound_tick(B_CONCLUDE_CLEAR, 8);
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_conclude_clear_fixture() {
    bound_fixture(B_CONCLUDE_CLEAR, 8);
}

// Eight goblins: a recovery over.
#[test]
#[available_gas(l2_gas: 62255967)] // ceil(1.05 × 59291397 measured)
fn test_cost_bound_eight_recovery_end() {
    bound_tick(B_RECOVERY_END, 8);
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_recovery_end_fixture() {
    bound_fixture(B_RECOVERY_END, 8);
}

// Eight goblins: activating, busy.
#[test]
#[available_gas(l2_gas: 61487993)] // ceil(1.05 × 58559993 measured)
fn test_cost_bound_eight_activating() {
    bound_tick(B_ACTIVATING, 8);
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_activating_fixture() {
    bound_fixture(B_ACTIVATING, 8);
}

// Eight goblins: free, acting in step 2.
#[test]
#[available_gas(l2_gas: 61543458)] // ceil(1.05 × 58612817 measured)
fn test_cost_bound_eight_free() {
    bound_tick(B_FREE, 8);
}

#[test]
#[available_gas(l2_gas: 58596993)] // ceil(1.05 × 55806660 measured)
fn test_cost_bound_eight_free_fixture() {
    bound_fixture(B_FREE, 8);
}

// Eight goblins: a lapse, the later recharge kept.
#[test]
#[available_gas(l2_gas: 63325854)] // ceil(1.05 × 60310337 measured)
fn test_cost_bound_eight_lapse_keep() {
    bound_tick(B_LAPSE_KEEP, 8);
}

#[test]
#[available_gas(l2_gas: 58649640)] // ceil(1.05 × 55856800 measured)
fn test_cost_bound_eight_lapse_keep_fixture() {
    bound_fixture(B_LAPSE_KEEP, 8);
}

// Eight goblins: a recovery running on.
#[test]
#[available_gas(l2_gas: 61551224)] // ceil(1.05 × 58620213 measured)
fn test_cost_bound_eight_recovering() {
    bound_tick(B_RECOVERING, 8);
}

#[test]
#[available_gas(l2_gas: 58657704)] // ceil(1.05 × 55864480 measured)
fn test_cost_bound_eight_recovering_fixture() {
    bound_fixture(B_RECOVERING, 8);
}

// Eight goblins: awake and already dead.
#[test]
#[available_gas(l2_gas: 61378436)] // ceil(1.05 × 58455653 measured)
fn test_cost_bound_eight_dead() {
    bound_tick(B_DEAD, 8);
}

#[test]
#[available_gas(l2_gas: 58654596)] // ceil(1.05 × 55861520 measured)
fn test_cost_bound_eight_dead_fixture() {
    bound_fixture(B_DEAD, 8);
}

// Eight goblins: free and knocked down.
#[test]
#[available_gas(l2_gas: 61552064)] // ceil(1.05 × 58621013 measured)
fn test_cost_bound_eight_knocked() {
    bound_tick(B_KNOCKED, 8);
}

#[test]
#[available_gas(l2_gas: 58657704)] // ceil(1.05 × 55864480 measured)
fn test_cost_bound_eight_knocked_fixture() {
    bound_fixture(B_KNOCKED, 8);
}

// COST-1a: load and store, once per call, on their costliest paths. A goblin's load: its caste
// (the last), its effect (skill 43, the last), its four caste skills each looked up and each
// raising its adrenaline cap (costs 1 to 4 strikes); the cap's clamp at 252 is not reachable
// (DS-18: a caste skill costs at most 63 strikes, `CasteAssert::assert_skills`). The member's:
// its four effects on the skill path (the content's last four skills; the potion path costs less,
// `test_cost_load_member_*`), its bar's eight skills each raising its cap (costs 1 to 8). `store`
// has no loop (`test_cost_path_*_store_*`). The lookups not at their list's end are charged as
// full scans in REPORT.md.

/// `branch_content(3)` with increasing adrenaline costs: the bar's skills 1–8 cost 1–8 strikes,
/// caste 5's skills 40–43 cost 1–4, so that every step of an adrenaline cap's loop raises it.
fn load_content() -> Content {
    let content = branch_content(3);
    let mut skills = array![];
    for sheet in content.skills {
        let mut sheet = *sheet;
        if sheet.id <= 8 {
            sheet.adrenaline = sheet.id.try_into().unwrap();
        } else if sheet.id >= 40 {
            sheet.adrenaline = (sheet.id - 39).try_into().unwrap();
        }
        skills.append(sheet);
    }
    Content { skills: skills.span(), ..content }
}

/// The words of load's costliest paths: `members` members with the content's last four skills as
/// their effects and their bar 1–8; 100 goblins of caste 5, each holding skill 43, the last 8
/// awake.
fn load_words(members: u32) -> (Words, Content) {
    let content = load_content();
    let mut all = array![];
    for _ in 0..members {
        all.append(member_effect_words(false));
    }
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 {
        goblins.append(goblin_words(8 + i, i >= 92, 280, 0, 99));
        i += 1;
    }
    (Words { clock: 49, members: all, goblins, killed: array![], defeated: false }, content)
}

// Load and store of the costliest words, the round trip checked.
#[test]
#[available_gas(l2_gas: 67779149)] // ceil(1.05 × 64551570 measured)
fn test_cost_load_bound() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let world = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
#[available_gas(l2_gas: 11639208)] // ceil(1.05 × 11084960 measured)
fn test_cost_load_bound_fixture() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

// The same with two members (M-3): what each member adds.
#[test]
#[available_gas(l2_gas: 78180365)] // ceil(1.05 × 74457490 measured)
fn test_cost_load_bound_two_members() {
    let (words, content) = load_words(2);
    let (expected, _) = load_words(2);
    let world = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
#[available_gas(l2_gas: 21366093)] // ceil(1.05 × 20348660 measured)
fn test_cost_load_bound_two_members_fixture() {
    let (words, content) = load_words(2);
    let (expected, _) = load_words(2);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

// COST-1c: a sheet read from its record's parts, per record kind, on every path of its loop.
// `SkillSheetTrait::read` scans the entries until the `REGENERATION` one or an empty one.
// `PotionSheetTrait::read` and `CasteSheetTrait::read` have no loop.

/// A `SKILL`'s two parts (`models::skill` layout): a spell's header and three entries of `kinds`,
/// each holding `v0` and `v12` where a `REGENERATION` holds them.
fn skill_parts(kinds: [u8; 3], v0: i16, v12: i16) -> Span<felt252> {
    let [a, b, c] = kinds;
    let line: felt252 = (SignedTrait::bits16(v0) * 0x10000 + SignedTrait::bits16(v12) * 0x100000000)
        .into();
    let header: felt252 = skill_kind::SPELL.into() * 0x10000
        + 2 * 0x100000000
        + 1 * 0x10000000000
        + 12 * 0x100000000000000;
    let first = LIVE + header + (a.into() + line) * B128;
    let second = LIVE + b.into() + line + (c.into() + line) * B128;
    opaque(array![first, second].span())
}

fn read_skill(kinds: [u8; 3], v0: i16, v12: i16) -> i16 {
    let sheet = SkillSheetTrait::read(opaque(5), skill_parts(kinds, v0, v12));
    assert(sheet.recharge == 12 && sheet.activation == 1, 'header');
    sheet.regen0
}

// A skill's sheet, its `REGENERATION`: the first entry.
#[test]
#[available_gas(l2_gas: 59231)] // ceil(1.05 × 56410 measured)
fn test_cost_sheet_skill_regen_first() {
    assert(read_skill([kind::REGENERATION, kind::DAMAGE, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the second.
#[test]
#[available_gas(l2_gas: 62643)] // ceil(1.05 × 59660 measured)
fn test_cost_sheet_skill_regen_second() {
    assert(read_skill([kind::DAMAGE, kind::REGENERATION, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third.
#[test]
#[available_gas(l2_gas: 66056)] // ceil(1.05 × 62910 measured)
fn test_cost_sheet_skill_regen_third() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third, negative.
#[test]
#[available_gas(l2_gas: 67358)] // ceil(1.05 × 64150 measured)
fn test_cost_sheet_skill_regen_third_negative() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], -3, -10) == -3, 'regen');
}

// A skill's sheet, its `REGENERATION`: none of three entries.
#[test]
#[available_gas(l2_gas: 58527)] // ceil(1.05 × 55740 measured)
fn test_cost_sheet_skill_none() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::DAMAGE], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: an empty second entry.
#[test]
#[available_gas(l2_gas: 53256)] // ceil(1.05 × 50720 measured)
fn test_cost_sheet_skill_damage_then_empty() {
    assert(read_skill([kind::DAMAGE, kind::EMPTY, kind::EMPTY], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: no entry.
#[test]
#[available_gas(l2_gas: 49634)] // ceil(1.05 × 47270 measured)
fn test_cost_sheet_skill_empty() {
    assert(read_skill([kind::EMPTY, kind::EMPTY, kind::EMPTY], 2, 6) == 0, 'regen');
}

#[test]
#[available_gas(l2_gas: 25148)] // ceil(1.05 × 23950 measured)
fn test_cost_sheet_skill_fixture() {
    assert(skill_parts([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], 2, 6).len() == 2, 'parts');
}

/// A potion's part (`models::item` layout): its entry of `entry_kind` in the high limb, holding
/// `v0`.
fn potion_parts(entry_kind: u8, v0: i16) -> Span<felt252> {
    let entry: felt252 = entry_kind.into() + (SignedTrait::bits16(v0) * 0x10000).into();
    opaque(array![LIVE + 3 + entry * B128].span())
}

// A potion's sheet: a `REGENERATION`, positive or negative, or another entry.
#[test]
#[available_gas(l2_gas: 32624)] // ceil(1.05 × 31070 measured)
fn test_cost_sheet_potion_regen() {
    assert(
        PotionSheetTrait::read(opaque(7), potion_parts(kind::REGENERATION, 3)).regen == 3, 'regen',
    );
}

#[test]
#[available_gas(l2_gas: 32624)] // ceil(1.05 × 31070 measured)
fn test_cost_sheet_potion_regen_negative() {
    assert(
        PotionSheetTrait::read(opaque(7), potion_parts(kind::REGENERATION, -3)).regen == -3,
        'regen',
    );
}

#[test]
#[available_gas(l2_gas: 32414)] // ceil(1.05 × 30870 measured)
fn test_cost_sheet_potion_damage() {
    assert(PotionSheetTrait::read(opaque(7), potion_parts(kind::DAMAGE, 3)).regen == 0, 'none');
}

#[test]
#[available_gas(l2_gas: 20654)] // ceil(1.05 × 19670 measured)
fn test_cost_sheet_potion_fixture() {
    assert(potion_parts(kind::REGENERATION, 3).len() == 1, 'parts');
}

// A caste's sheet (no loop).
#[test]
#[available_gas(l2_gas: 383387)] // ceil(1.05 × 365130 measured)
fn test_cost_sheet_caste() {
    let (_, caste) = records();
    assert(CasteSheetTrait::read(opaque(1), opaque(caste)).weapon_ticks == 2, 'caste');
}

#[test]
#[available_gas(l2_gas: 353063)] // ceil(1.05 × 336250 measured)
fn test_cost_sheet_caste_fixture() {
    let (_, caste) = records();
    assert(opaque(caste).len() == 2, 'parts');
}

// COST-1b: the library call with every list at its bound. `killed` crosses the call both ways: the
// kills of the action phase come in, step 3's are added. Each goblin dies once, so the list holds
// at most `MAX_GOBLINS` entries each way; here the 92 frozen goblins came in dead (their words
// dead), and the 8 awake die: 92 in, 100 out.

/// `worst_words` with the 92 frozen goblins killed in the action phase.
fn worst_words_kills() -> (Words, Content) {
    let (words, content) = worst_words();
    let mut goblins = array![];
    let mut killed = array![];
    for goblin in words.goblins.span() {
        let mut goblin = *goblin;
        if !goblin.awake {
            goblin.state += (ai::DEAD - ai::ALERTED).into() * B24;
            killed.append(goblin.entity);
        }
        goblins.append(goblin);
    }
    (Words { goblins, killed, ..words }, content)
}

#[test]
#[available_gas(l2_gas: 129089482)] // ceil(1.05 × 122942363 measured)
fn test_cost_library_call_kills() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_kills();
    let words = library.run(words, content, 1);
    assert(words.killed.len() == 100, 'every goblin once');
}

#[test]
#[available_gas(l2_gas: 125632210)] // ceil(1.05 × 119649723 measured)
fn test_cost_library_baseline_kills() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_kills();
    let mut world = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 1, ref rules);
    let words = world.store();
    assert(words.killed.len() == 100, 'every goblin once');
}

/// `worst_words` with its member twice (M-3: members 0–7).
fn worst_words_two() -> (Words, Content) {
    let (words, content) = worst_words();
    let member = *words.members.at(0);
    (Words { members: array![member, member], ..words }, content)
}

#[test]
#[available_gas(l2_gas: 128579227)] // ceil(1.05 × 122456406 measured)
fn test_cost_library_call_two_members() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_two();
    let words = library.run(words, content, 1);
    assert(words.members.len() == 2, 'two members');
}

#[test]
#[available_gas(l2_gas: 125853427)] // ceil(1.05 × 119860406 measured)
fn test_cost_library_baseline_two_members() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_two();
    let mut world = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 1, ref rules);
    let words = world.store();
    assert(words.members.len() == 2, 'two members');
}

// The tick's base with two members: what each member adds to it.
fn base_two_members() -> (World, Content) {
    let (world, content) = branch_world(B_NONE, false, true);
    let member = *world.members.at(0);
    (World { members: array![member, member], ..world }, content)
}

#[test]
#[available_gas(l2_gas: 59939582)] // ceil(1.05 × 57085316 measured)
fn test_cost_bound_base_two_members() {
    let (mut world, content) = base_two_members();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50 && world.defeated, 'one tick');
}

#[test]
#[available_gas(l2_gas: 58603787)] // ceil(1.05 × 55813130 measured)
fn test_cost_bound_base_two_members_fixture() {
    let (world, content) = base_two_members();
    assert(world.members.len() == 2 && content.skills.len() == 38, 'fixture');
}

// More than 8 awake goblins is not a state of the game (design/02): the tick refuses it.
#[test]
#[should_panic(expected: 'tick: more than 8 awake')]
#[available_gas(l2_gas: 7768355)] // ceil(1.05 × 7398433 measured)
fn test_world_assert_awake() {
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 9 {
        goblins.append(Fixture::goblin(8 + i, HOB));
        i += 1;
    }
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
    run(ref world, 1);
}

// The costliest mix of step 1's branches, which the terms above give (REPORT.md): 7 conclusions
// (the field cleared, the costliest conclusion) and a lapse last, whose write the end of step 1
// puts in the array in a rebuild of its own; every goblin dying, the member concluding and dying.
// The awake goblins at the array's end, or at its start.
fn mixed_world(first: bool) -> (World, Content) {
    let content = branch_content(1);
    let mut spec = Fixture::spec();
    spec.health = 7;
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), @content);
    member.start(7, 8, 1, 49);
    let from: u16 = if first {
        0
    } else {
        92
    };
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let words = if i < from || i >= from + 8 {
            goblin_words(8 + i, false, 280, 0, 99)
        } else if i < from + 7 {
            goblin_words_at(8 + i, true, 1, 3, 50, 99)
        } else {
            goblin_words_at(8 + i, true, 1, 3, 45, 99)
        };
        goblins.append(GoblinTrait::load(words, @content));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), content)
}

#[test]
#[available_gas(l2_gas: 67959819)] // ceil(1.05 × 64723637 measured)
fn test_cost_bound_mixed_last() {
    let (mut world, content) = mixed_world(false);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
    assert(world.goblins.at(99).recharge(3) == 45 + 20 - 1, 'the lapse last');
}

#[test]
#[available_gas(l2_gas: 58752173)] // ceil(1.05 × 55954450 measured)
fn test_cost_bound_mixed_last_fixture() {
    let (world, content) = mixed_world(false);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 68041383)] // ceil(1.05 × 64801317 measured)
fn test_cost_bound_mixed_first() {
    let (mut world, content) = mixed_world(true);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
    assert(world.goblins.at(7).recharge(3) == 45 + 20 - 1, 'the lapse last');
}

#[test]
#[available_gas(l2_gas: 58833747)] // ceil(1.05 × 56032140 measured)
fn test_cost_bound_mixed_first_fixture() {
    let (world, content) = mixed_world(true);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

/// `worst_words` with every goblin killed in the action phase: 100 kills in, 100 out, the most the
/// list holds (each goblin once).
fn worst_words_all_dead() -> (Words, Content) {
    let (words, content) = worst_words();
    let mut goblins = array![];
    let mut killed = array![];
    for goblin in words.goblins.span() {
        let mut goblin = *goblin;
        goblin.state += (ai::DEAD - ai::ALERTED).into() * B24;
        killed.append(goblin.entity);
        goblins.append(goblin);
    }
    (Words { goblins, killed, ..words }, content)
}

#[test]
#[available_gas(l2_gas: 122644834)] // ceil(1.05 × 116804603 measured)
fn test_cost_library_call_all_dead() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_all_dead();
    let words = library.run(words, content, 1);
    assert(words.killed.len() == 100, 'each goblin once');
}

#[test]
#[available_gas(l2_gas: 119154970)] // ceil(1.05 × 113480923 measured)
fn test_cost_library_baseline_all_dead() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_all_dead();
    let mut world = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 1, ref rules);
    let words = world.store();
    assert(words.killed.len() == 100, 'each goblin once');
}
