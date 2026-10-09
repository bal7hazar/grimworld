// CBT-02: the world tick's pipeline (design/02 *The tick*, design/19 §5): determinism, the cost of
// a tick on measured scenarios and at its upper bound (CBT-02b, CBT-02d, below), against the
// expedition's target of 1,469,435 L2 gas a tick inside a batch (docs/architecture/cost-budget.md
// §2, D-159), the library call, and CBT-02d's parity table. The pipeline's rules one by one and
// the worked examples of design/19 §10 are unit tests in their modules (D-167: `types::world`,
// `types::tick`, `models::goblin`, `models::member`); what stays here needs the benchmarks' states,
// a declared class, or both representations. The fixtures below repeat the modules' own
// (`types::world::fixtures`, a crate apart). The words are built here from ENG-01's offsets; the
// ephemeral package's `test_tick_words` pins `load` and `store` against its packers. COST-3
// (CBT-02b): "worst" in a fixture's or a test's name is the name of a measured scenario, not a
// claim that no state costs more; "upper bound" is kept for the derived result (REPORT.md, ENG-01
// §9.2).
use core::testing::get_available_gas;
use grimworld_logic::actions::Action;
use grimworld_logic::content::Record;
use grimworld_logic::helpers::signed::SignedTrait;
use grimworld_logic::interface::{
    ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher, ITrapLibraryDispatcherTrait,
};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::goblin::{Goblin, GoblinTickTrait, GoblinTrait, GoblinWords};
use grimworld_logic::models::index::{Caste, Skill};
use grimworld_logic::models::member::{Member, MemberTickTrait, MemberTrait, MemberWords};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::types::MAX_CLOCK;
use grimworld_logic::types::action::ActionTrait;
use grimworld_logic::types::combat::{activation, skill_kind, weapon};
use grimworld_logic::types::effect::{EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::executor::{Board, BoardTrait, ExecutorTrait};
use grimworld_logic::types::tick::{
    ABSENT, CasteSheet, CasteSheetTrait, Content, ContentTrait, IndexTrait, NO_SLOT, PotionSheet,
    PotionSheetTrait, Sheets, SheetsTrait, SkillSheet, SkillSheetTrait, ai, flag, status,
};
use grimworld_logic::types::window::WindowTrait;
use grimworld_logic::types::world::{
    Actor, Idle, Rules, TickTrait, Words, WordsTrait, World, WorldStoreTrait, WorldTrait,
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
            bar_at: 0x00070006000500040003000200010000,
            effect_at: 0xFFFFFFFFFFFFFFFF,
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
            caste_at: (caste - 1).into(),
            effect_at: ABSENT,
            state: LIVE
                + ai::ENGAGED.into() * two(24)
                + 100 * two(32)
                + caste.into() * two(64)
                + 10 * two(80),
            timers: LIVE + activation::NONE.into(),
        }
    }

    fn skill(id: u16, kind: u8, activation: u16, recharge: u16) -> SkillSheet {
        SkillSheet {
            id,
            kind,
            adrenaline: 0,
            activation,
            recharge,
            regen0: 0,
            regen12: 0,
            ..Default::default(),
        }
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
            ..Default::default(),
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
            potions: array![PotionSheet { id: 101, regen: 3, ..Default::default() }].span(),
            castes: array![Self::caste(HOB, 1), Self::caste(RUNT, 2)].span(),
        }
    }

    fn sheets() -> Sheets {
        Self::content().sheets()
    }

    fn world(clock: u32, members: Array<Member>, goblins: Array<Goblin>) -> World {
        WorldTrait::new(clock, members, goblins, array![], false)
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
        ref self: Script, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {
        self.resolved.append((world.clock, actor, slot));
    }
    fn act(ref self: Script, ref world: World, sheets: @Sheets, index: u32) {
        self.acts.append((world.clock, world.goblin(index).entity));
        if world.clock == self.kill_member_at {
            let mut member = world.member(0);
            member.health = 0;
            world.set_member(0, member);
        }
    }
    fn objectives(ref self: Script, ref world: World) {}
}

fn run(ref world: World, ticks: u8) {
    let mut rules = Idle {};
    TickTrait::run(ref world, @Fixture::sheets(), ticks, ref rules);
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
        let mut member = world.member(0);
        member.act_slot = 7;
        member.act_target = 8;
        member.act_deadline = world.clock;
        world.set_member(0, member);
    }
    fn resolve(
        ref self: Busy, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Busy, ref world: World, sheets: @Sheets, index: u32) {
        let mut goblin = world.goblin(index);
        goblin.start(0, 0, 1, world.clock);
        world.set_goblin(index, goblin);
    }
    fn objectives(ref self: Busy, ref world: World) {}
}

/// The words of a goblin of caste 5 at level 10 (ENG-01 §3.2 offsets): Alerted (not Engaged),
/// `health`, activating slot 0 due at `due` (0: none), the three degenerating conditions to
/// `until`, its effect skill 43 to `until` at rank 4.
fn goblin_words(entity: u16, awake: bool, health: u16, due: u32, until: u32) -> GoblinWords {
    // One goblin a tile (design/04; the cost audit of #334, F-2): goblin `e` on the window's
    // position `e − 7`, the member on position 0.
    let position: u16 = entity - 7;
    let tile: felt252 = (position % 15).into() + (position / 15).into() * 0x100;
    let state = LIVE + tile + ai::ALERTED.into() * B24 + health.into() * B32 + 5 * B64 + 10 * B80;
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
/// caste, 5, and its skills (40–43) come last in their lists: before CBT-02d every lookup scanned
/// the whole list; the index reads them at the cost of any other.
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
        PotionSheet { id: 100, regen: 1, ..Default::default() },
        PotionSheet { id: 101, regen: 2, ..Default::default() },
        PotionSheet { id: 102, regen: 1, ..Default::default() },
        PotionSheet { id: 103, regen: 2, ..Default::default() },
    ];
    Content { skills: skills.span(), potions: potions.span(), castes: castes.span() }
}

/// CBT-02's heavy scenario of a tick (AUD-182-7), a measured state, not a maximum (COST-3: the
/// upper bound is CBT-02b's, below), every actor loaded from its words so that the derived fields
/// agree with the stored ones:
/// - the goblin array at its bound, `MAX_GOBLINS` = 100 (before CBT-02d every pass was linear in
///   it; the steps now read the awake set alone), 8 of them awake (design/02), the 92 others
///   frozen; every one of the 100 holds a retained effect, so `load` reads its skill and scales
///   it for each (COST-1);
/// - each awake goblin concludes its activation (a recovery with `k = 3 ≥ n + 2`), the awake set
///   rebuilt;
/// - step 3 with every term: the 3 degenerating conditions and a regenerating effect on each awake
///   goblin; on the member, its 3 conditions, 4 regenerating effects (2 potions) and its own
///   activation concluding; no goblin Engaged, so the Engaged scan runs the whole awake set;
/// - with `dying`, every awake goblin dies in step 3 (8 kills recorded) and the member too (step
///   5's defeat rewrites the members).
/// With `dying` false and `k = 1`, the state `Busy` keeps busy over a batch (no death, no
/// recovery).
fn worst_state(dying: bool, k: u8) -> (World, Sheets) {
    worst_of(dying, k, 100)
}

/// `worst_state` with `count` goblins in the array, the last 8 awake.
fn worst_of(dying: bool, k: u8, count: u16) -> (World, Sheets) {
    let (sheets, mut index) = worst_content(k).index();
    let mut spec = Fixture::spec();
    spec.health = if dying {
        7
    } else {
        400
    };
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), ref index, @sheets);
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
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), sheets)
}

/// `worst_state`'s scenario as the words `Instances` would pass.
fn worst_words() -> (Words, Content) {
    let (world, sheets) = worst_state(true, 3);
    (world.store(), content_of(@sheets))
}

/// The content the sheets were built from, for the library call.
fn content_of(sheets: @Sheets) -> Content {
    Content { skills: *sheets.skills, potions: *sheets.potions, castes: *sheets.castes }
}

/// A representative tick: the member with one condition and one effect, 8 awake goblins of 2
/// castes fighting (no activation due, no condition), the content of two castes.
fn representative() -> (World, Sheets) {
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
    (Fixture::world(49, array![member], goblins), Fixture::sheets())
}

// Determinism (AC-2): the same state gives the same world, over 10 busy ticks.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 63378725)] // ceil(1.05 × 60360690 measured)
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14702142)] // ceil(1.05 × 14002040 measured)
fn test_cost_fixture_worst() {
    let (world, content) = worst_state(true, 3);
    assert(world.goblin_count() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14703927)] // ceil(1.05 × 14003740 measured)
fn test_cost_fixture_worst_batch() {
    let (world, content) = worst_state(false, 1);
    assert(world.goblin_count() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16970258)] // ceil(1.05 × 16162150 measured)
fn test_cost_fixture_worst_words() {
    let (words, content) = worst_words();
    assert(words.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 7757946)] // ceil(1.05 × 7388520 measured)
fn test_cost_fixture_representative() {
    let (world, content) = representative();
    assert(world.goblin_count() == 8 && content.castes.len() == 2, 'representative');
}

// Cost: one representative tick, the pipeline alone (Idle rules).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8495421)] // ceil(1.05 × 8090877 measured)
fn test_cost_tick_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50, 'one tick');
}

// Cost: a batch's 10 representative ticks, the pipeline alone: a trace, not a bound.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15178548)] // ceil(1.05 × 14455760 measured)
fn test_cost_batch_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8003846)] // ceil(1.05 × 7622710 measured)
fn test_cost_fixture_representative_words() {
    let (world, content) = representative();
    let words = world.store();
    assert(words.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// A batch's 10 representative ticks through one library call: load, ticks, store, the call.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 180302439)] // ceil(1.05 × 171716608 measured)
fn test_cost_library_call_batch_representative() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = representative();
    let words = ticks_of(library, world.store(), content_of(@content), board(), 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8014251)] // ceil(1.05 × 7632620 measured)
fn test_cost_library_baseline_representative() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = representative();
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// Cost: one tick of `worst_state`'s scenario, the pipeline alone: a measured state under the upper
// bound (CBT-02b, below), not the bound. CBT-02d prints the tick measured alone ("gas heavy tick"):
// the difference with the fixture also counts the checks below.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16338361)] // ceil(1.05 × 15560343 measured)
fn test_cost_tick_worst() {
    let (mut world, content) = worst_state(true, 3);
    let mut rules = Idle {};
    let before = get_available_gas();
    TickTrait::tick(ref world, @content, ref rules);
    println!("gas heavy tick: {}", before - get_available_gas());
    let goblin = @world.goblin(92);
    assert(*goblin.act_slot == activation::RECOVERING && goblin.recharge(0) == 59, 'concluded');
    assert(world.killed.len() == 8 && world.defeated, 'every death');
    assert(world.member(0).act_slot == NO_SLOT, 'member resolved');
}

// The same construction with only the 8 awake goblins in the array (no frozen candidate): what
// the array's bound adds is the difference with `test_cost_tick_worst`.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 7075362)] // ceil(1.05 × 6738440 measured)
fn test_cost_fixture_worst_8() {
    let (world, _) = worst_of(true, 3, 8);
    assert(world.goblin_count() == 8, 'eight');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8611610)] // ceil(1.05 × 8201533 measured)
fn test_cost_tick_worst_8() {
    let (mut world, content) = worst_of(true, 3, 8);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
}

// Cost: a busy 10-tick batch (weight 10), `Busy` keeping every awake goblin and the member
// resolving or acting at every tick: a measured scenario. CBT-02d measures each tick alone (printed
// "gas busy tick"): the ticks alternate between 8 conclusions and 8 acts, and in the latter each of
// `Busy`'s act hooks writes its goblin (its own work, the AI's in ENG-07, not the pipeline's).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 31927896)] // ceil(1.05 × 30407520 measured)
fn test_cost_batch_worst() {
    let (mut world, content) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    let mut k = 0;
    while k < 10_u8 {
        let before = get_available_gas();
        TickTrait::tick(ref world, @content, ref rules);
        println!("gas busy tick {}: {}", k, before - get_available_gas());
        k += 1;
    }
    assert(world.clock == 59 && !world.defeated, 'ten ticks');
}

// Cost, once per call: loading `worst_words`' 101 actors from their words and storing them back
// (a measured scenario; load and store's upper bound is `test_cost_load_bound`'s, CBT-02b).
// The round trip returns exactly the words it was given (quality 4): every member and goblin word,
// the clock, the kills. Its baseline builds the same two fixtures.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 45245141)] // ceil(1.05 × 43090610 measured)
fn test_cost_load_store_worst() {
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let (world, _) = words.load(@content);
    let words = world.store();
    assert(words == expected, 'the round trip keeps every word');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 33935885)] // ceil(1.05 × 32319890 measured)
fn test_cost_fixture_worst_words_twice() {
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

/// 100 candidates, every one eligible (Alerted, alive), at distances falling along the array: each
/// of the 8 selection scans updates its running minimum at every element, the costliest order.
fn candidates() -> (World, Span<u16>) {
    let (sheets, mut index) = worst_content(3).index();
    let mut goblins = array![];
    let mut distances = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let words = goblin_words(8 + i, false, 280, 0, 0);
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        distances.append(200 - i);
        i += 1;
    }
    (Fixture::world(49, array![], goblins), distances.span())
}

// COST-1: the awake set's selection (§5.2) at the candidate bound, `MAX_GOBLINS` = 100: the 8
// nearest are the array's last 8.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 13311743)] // ceil(1.05 × 12677850 measured)
fn test_cost_awake_100() {
    let (mut world, distances) = candidates();
    TickTrait::awake(ref world, distances);
    assert(world.goblin(92).awake && !world.goblin(91).awake, 'the 8 nearest');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8553185)] // ceil(1.05 × 8145890 measured)
fn test_cost_fixture_candidates() {
    let (world, distances) = candidates();
    assert(world.goblin_count() == 100 && distances.len() == 100, 'candidates');
}

// CBT-02d fix loop 1 (COST-2): the selection from a prior awake set of 8, so that both of its
// passes walk the set's runs. The prior set at the array's start, its end or spread across it;
// the distances either fall along the array (the costliest order of the scans: the 8 nearest are
// the last 8) or rise (the 8 nearest are the first 8), or put the spread set nearest. The
// selection is measured alone (printed "gas awake") and checked to keep or replace the set.

/// `candidates()` with the goblins at `prior` flagged awake, and distances `order`: 0 falling, 1
/// rising, 2 the `prior` goblins nearest (the others falling).
fn awake_state(prior: Span<u16>, order: u8) -> (World, Span<u16>) {
    let (sheets, mut index) = worst_content(3).index();
    let mut goblins = array![];
    let mut distances = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let mut awake = false;
        for p in prior {
            if *p == i {
                awake = true;
            }
        }
        let words = goblin_words(8 + i, awake, 280, 0, 0);
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        let distance = if order == 1 {
            100 + i
        } else if order == 2 && awake {
            1 + i / 16
        } else {
            200 - i
        };
        distances.append(distance);
        i += 1;
    }
    (Fixture::world(49, array![], goblins), distances.span())
}

/// The selection over `awake_state(prior, order)`, measured alone; then the set is `expected`.
fn awake_tick(prior: Span<u16>, order: u8, expected: Span<u16>) {
    let (mut world, distances) = awake_state(prior, order);
    assert(world.woken().len() == prior.len(), 'the prior set');
    let before = get_available_gas();
    TickTrait::awake(ref world, distances);
    println!("gas awake: {}", before - get_available_gas());
    let mut woken = array![];
    for index in expected {
        woken.append((*index).into());
    }
    assert(world.woken() == woken.span(), 'the new set');
}

// No prior set: the scans' costliest order (`test_cost_awake_100`'s state, measured alone).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 13843851)] // ceil(1.05 × 13184620 measured)
fn test_cost_awake_none() {
    awake_tick(array![].span(), 0, at_end(8));
}

// The prior set at the array's end, kept.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15597551)] // ceil(1.05 × 14854810 measured)
fn test_cost_awake_end_kept() {
    awake_tick(at_end(8), 0, at_end(8));
}

// The prior set at the array's start, replaced by the last 8.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15596627)] // ceil(1.05 × 14853930 measured)
fn test_cost_awake_start_replaced() {
    awake_tick(at_start(8), 0, at_end(8));
}

// The prior set spread across the array, replaced by the last 8.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15579627)] // ceil(1.05 × 14837740 measured)
fn test_cost_awake_spread_replaced() {
    awake_tick(at_spread(), 0, at_end(8));
}

// The prior set at the array's start, kept (the distances rising).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15544683)] // ceil(1.05 × 14804460 measured)
fn test_cost_awake_start_kept() {
    awake_tick(at_start(8), 1, at_start(8));
}

// The prior set at the array's end, replaced by the first 8 (the distances rising).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15543759)] // ceil(1.05 × 14803580 measured)
fn test_cost_awake_end_replaced() {
    awake_tick(at_end(8), 1, at_start(8));
}

// The prior set spread across the array, kept (nearest).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15575291)] // ceil(1.05 × 14833610 measured)
fn test_cost_awake_spread_kept() {
    awake_tick(at_spread(), 2, at_spread());
}

// CBT-02d fix loop 1 (COST-1): what a figure measured inside a test misses, and `TickTrait::run`'s
// own loop.
//
// **A call measured alone misses its straight-line part.** Sierra charges a function's code
// outside its loops when its caller withdraws gas, before the call runs; `get_available_gas` around
// the call sees only what the callee's loops withdraw, and the refunds of its cheaper branches.
// So `TickTrait::tick` measured alone (the "gas tick" figures of the terms) is short of the truth
// by one constant for each monomorphization, the costliest straight-line path of `tick<R>`,
// whatever the state. The pairs below measure it as snforge's totals, two tests that differ by the
// call alone and check nothing: `tick<Acts>` on two term states (the bound's rules), `tick<Idle>`
// on the representative state (the batch's rules).
//
// **`run`'s loop.** Each of its iterations checks `k < ticks && !world.defeated`, calls `tick` and
// counts; the run's last check ends it. Measured with the pairs too: ten ticks through `run`,
// against the same ten ticks each measured alone plus the constant above.

// The costliest state of the bound, its fixture alone.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 18911792)] // ceil(1.05 × 18011230 measured)
fn test_cost_pair_term_fixture() {
    let (_world, _sheets) = term_world(seven_then(C, L), at_end(8), false, 1, 1);
}

// The same, and its tick with the bound's rules.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20490306)] // ceil(1.05 × 19514577 measured)
fn test_cost_pair_term_tick() {
    let (mut world, sheets) = term_world(seven_then(C, L), at_end(8), false, 1, 1);
    let mut rules: Acts = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The state of 8 activating goblins, its fixture alone.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 18913230)] // ceil(1.05 × 18012600 measured)
fn test_cost_pair_activating_fixture() {
    let (_world, _sheets) = term_world(all_of(A, 8), at_end(8), false, 1, 1);
}

// The same, and its tick with the bound's rules.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 19734407)] // ceil(1.05 × 18794673 measured)
fn test_cost_pair_activating_tick() {
    let (mut world, sheets) = term_world(all_of(A, 8), at_end(8), false, 1, 1);
    let mut rules: Acts = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The representative state, its fixture alone.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 7756896)] // ceil(1.05 × 7387520 measured)
fn test_cost_pair_representative_fixture() {
    let (_world, _sheets) = representative();
}

// The same, and one tick with the lot's rules.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8493741)] // ceil(1.05 × 8089277 measured)
fn test_cost_pair_representative_tick() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The same, and one tick through `run`.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8505333)] // ceil(1.05 × 8100317 measured)
fn test_cost_pair_representative_run_one() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
}

// The same, and ten ticks through `run`.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15176868)] // ceil(1.05 × 14454160 measured)
fn test_cost_pair_representative_run_ten() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 10, ref rules);
}

// The awake selection's straight-line part, the same way: the costliest prior set (at the array's
// start, kept) and none.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 10619448)] // ceil(1.05 × 10113760 measured)
fn test_cost_pair_awake_start_kept_fixture() {
    let (_world, _distances) = awake_state(at_start(8), 1);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15414861)] // ceil(1.05 × 14680820 measured)
fn test_cost_pair_awake_start_kept() {
    let (mut world, distances) = awake_state(at_start(8), 1);
    TickTrait::awake(ref world, distances);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 8989533)] // ceil(1.05 × 8561460 measured)
fn test_cost_pair_awake_none_fixture() {
    let (_world, _distances) = awake_state(array![].span(), 0);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 13713189)] // ceil(1.05 × 13060180 measured)
fn test_cost_pair_awake_none() {
    let (mut world, distances) = awake_state(array![].span(), 0);
    TickTrait::awake(ref world, distances);
}

// `Busy`'s first tick (8 conclusions and the member's), for `tick<Busy>`'s straight-line part.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14701302)] // ceil(1.05 × 14001240 measured)
fn test_cost_pair_busy_fixture() {
    let (_world, _sheets) = worst_state(false, 1);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16270073)] // ceil(1.05 × 15495307 measured)
fn test_cost_pair_busy_tick() {
    let (mut world, sheets) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The ten ticks of the run above, each measured alone ("gas representative tick").
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16117290)] // ceil(1.05 × 15349800 measured)
fn test_cost_run_ticks_alone() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    let mut k = 0;
    while k < 10_u8 {
        let before = get_available_gas();
        TickTrait::tick(ref world, @sheets, ref rules);
        println!("gas representative tick {}: {}", k, before - get_available_gas());
        k += 1;
    }
    assert(world.clock == 59, 'ten ticks');
}

// Cost of the library call (AC-3): the baseline declares the class and runs the call's body (load,
// one tick of `worst_state`'s scenario, store) in the test's own code; the next test runs it
// through `library_call`.
// The difference is the call: its syscall and the words and content through calldata and back.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 29436407)] // ceil(1.05 × 28034673 measured)
fn test_cost_library_baseline() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words();
    let (mut world, sheets) = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    assert(words.clock == 50, 'one tick');
}

// Not the tick's cost (CBT-05a, route (c)): each concluding carrier of this fixture calls
// ExecutorLibrary (one goblin a tile since F-2; the figures before were fixture artefacts). The
// tick's cost is ENG-01 §9.2's measured line (45,999,941 the worst tick, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 70209197)] // ceil(1.05 × 66865901 measured)
fn test_cost_library_call() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let words = ticks_of(library, words, content, board(), 1);
    assert(words.clock == 50, 'one tick');
}

// Ten ticks through one library call over the busy state: the class runs its own rules (`Idle`
// until CBT-05 and ENG-07), so after the opening tick the goblins fall quiet. A trace of the call
// at the array's bound, not a bound (the tick's is CBT-02b's, below).
// Not the tick's cost (CBT-05a, route (c)): each concluding carrier of this fixture calls
// ExecutorLibrary (one goblin a tile since F-2; the figures before were fixture artefacts). The
// tick's cost is ENG-01 §9.2's measured line (45,999,941 the worst tick, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 367013087)] // ceil(1.05 × 349536273 measured)
fn test_cost_library_call_batch() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = worst_state(false, 1);
    let words = ticks_of(library, world.store(), content_of(@content), board(), 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16978563)] // ceil(1.05 × 16170060 measured)
fn test_cost_library_baseline_batch() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = worst_state(false, 1);
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// The library call runs the pipeline: the same words as a direct run.
// Not the tick's cost (CBT-05a, route (c)): each concluding carrier of this fixture calls
// ExecutorLibrary (one goblin a tile since F-2; the figures before were fixture artefacts). The
// tick's cost is ENG-01 §9.2's measured line (45,999,941 the worst tick, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 389007912)] // ceil(1.05 × 370483725 measured)
fn test_library_matches_pipeline() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let words = ticks_of(library, words, content, board(), 3);
    let (mut world, sheets) = expected.load(@content);
    let mut rules = ExecutorTrait::new(board());
    TickTrait::run(ref world, @sheets, 3, ref rules);
    assert(words == world.store(), 'the call runs the pipeline');
}

// The content's price, per record, once per batch (D-145): a `SKILL` and a `CASTE` read into their
// sheets from their parts. The baseline packs them only; the unpacked path is the oracle's.
#[test]
#[available_gas(l2_gas: 344757)] // ceil(1.05 × 328340 measured)
fn test_cost_sheets_baseline() {
    let (skill, caste) = records();
    assert(skill.len() == 2 && caste.len() == 2, 'parts');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 433839)] // ceil(1.05 × 413180 measured)
fn test_cost_sheets() {
    let (skill, caste) = records();
    let sheet = SkillSheetTrait::read(5, skill);
    let caste_sheet = CasteSheetTrait::read(1, caste);
    assert(sheet.recharge == 12 && sheet.regen(12) == 6, 'skill sheet');
    assert(caste_sheet.weapon_ticks == 2 && caste_sheet.max_health(20) == 720, 'caste sheet');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 757932)] // ceil(1.05 × 721840 measured)
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
fn branch_world(branch: u8, dying: bool, member_dying: bool) -> (World, Sheets) {
    branch_world_n(branch, dying, member_dying, 1)
}

/// `branch_world` with the last `n` goblins all taking `branch`.
fn branch_world_n(branch: u8, dying: bool, member_dying: bool, n: u16) -> (World, Sheets) {
    let k = if branch == B_CONCLUDE_CLEAR {
        1
    } else {
        3
    };
    let (sheets, mut index) = branch_content(k).index();
    let mut spec = Fixture::spec();
    spec.health = if member_dying {
        7
    } else {
        400
    };
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), ref index, @sheets);
    member.start(7, 8, 1, 49);
    let health: u16 = if dying {
        1
    } else {
        280
    };
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 - n {
        let words = goblin_words(8 + i, false, 280, 0, 99);
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
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
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), sheets)
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 78324996)] // ceil(1.05 × 74595234 measured)
fn test_branch_worlds_take_their_branch() {
    let content = branch_content(3).sheets();
    let mut rules: Script = Default::default();
    let (mut world, _) = branch_world(B_CONCLUDE_RECOVER, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.goblin(99).act_slot == activation::RECOVERING, 'recover');
    assert(rules.resolved.len() == 2 && rules.acts.len() == 0, 'resolved');
    let (mut world, _) = branch_world(B_LAPSE, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.goblin(99).recharge(3) == 45 + 20 - 1, 'lapsed');
    let (mut world, _) = branch_world(B_RECOVERY_END, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.goblin(99).act_slot == activation::NONE, 'recovery ended');
    let (mut world, _) = branch_world(B_ACTIVATING, true, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.killed.len() == 1 && world.goblin(99).act_slot == 3, 'busy, died');
    let content = branch_content(1).sheets();
    let (mut world, _) = branch_world(B_CONCLUDE_CLEAR, false, false);
    TickTrait::run(ref world, @content, 1, ref rules);
    assert(world.goblin(99).act_slot == activation::NONE, 'cleared');
}

// 8 goblins all lapsing, dying: a lapse's term with eight goblins (CBT-02b's per-goblin terms).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16060409)] // ceil(1.05 × 15295627 measured)
fn test_cost_bound_eight_lapses() {
    let (mut world, content) = branch_world_n(B_LAPSE, true, true, 8);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8, 'eight deaths');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14756816)] // ceil(1.05 × 14054110 measured)
fn test_cost_bound_eight_lapses_fixture() {
    let (world, content) = branch_world_n(B_LAPSE, true, true, 8);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14972195)] // ceil(1.05 × 14259233 measured)
fn test_cost_bound_base() {
    branch_tick(B_NONE, false, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14733831)] // ceil(1.05 × 14032220 measured)
fn test_cost_bound_base_fixture() {
    branch_fixture(B_NONE, false, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14950303)] // ceil(1.05 × 14238383 measured)
fn test_cost_bound_base_member_alive() {
    branch_tick(B_NONE, false, false);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14733936)] // ceil(1.05 × 14032320 measured)
fn test_cost_bound_base_member_alive_fixture() {
    branch_fixture(B_NONE, false, false);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15096862)] // ceil(1.05 × 14377963 measured)
fn test_cost_bound_conclude_recover() {
    branch_tick(B_CONCLUDE_RECOVER, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14737212)] // ceil(1.05 × 14035440 measured)
fn test_cost_bound_conclude_recover_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15096757)] // ceil(1.05 × 14377863 measured)
fn test_cost_bound_conclude_recover_alive() {
    branch_tick(B_CONCLUDE_RECOVER, false, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14737317)] // ceil(1.05 × 14035540 measured)
fn test_cost_bound_conclude_recover_alive_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, false, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15098870)] // ceil(1.05 × 14379876 measured)
fn test_cost_bound_conclude_clear() {
    branch_tick(B_CONCLUDE_CLEAR, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14737517)] // ceil(1.05 × 14035730 measured)
fn test_cost_bound_conclude_clear_fixture() {
    branch_fixture(B_CONCLUDE_CLEAR, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15118379)] // ceil(1.05 × 14398456 measured)
fn test_cost_bound_lapse() {
    branch_tick(B_LAPSE, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14738220)] // ceil(1.05 × 14036400 measured)
fn test_cost_bound_lapse_fixture() {
    branch_fixture(B_LAPSE, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15077492)] // ceil(1.05 × 14359516 measured)
fn test_cost_bound_recovery_end() {
    branch_tick(B_RECOVERY_END, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14738924)] // ceil(1.05 × 14037070 measured)
fn test_cost_bound_recovery_end_fixture() {
    branch_fixture(B_RECOVERY_END, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15051775)] // ceil(1.05 × 14335023 measured)
fn test_cost_bound_activating() {
    branch_tick(B_ACTIVATING, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14739522)] // ceil(1.05 × 14037640 measured)
fn test_cost_bound_activating_fixture() {
    branch_fixture(B_ACTIVATING, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15056072)] // ceil(1.05 × 14339116 measured)
fn test_cost_bound_free() {
    branch_tick(B_FREE, true, true);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14739627)] // ceil(1.05 × 14037740 measured)
fn test_cost_bound_free_fixture() {
    branch_fixture(B_FREE, true, true);
}


// CBT-02d: a read through the index costs the same wherever the record lies: the first skill and
// the last, the first caste and the last, in the same content. The fixture builds the index.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 1388919)] // ceil(1.05 × 1322780 measured)
fn test_cost_index_skill_first() {
    let (_, mut index) = branch_content(3).index();
    assert(index.skill(1) == 0, 'first');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 1389129)] // ceil(1.05 × 1322980 measured)
fn test_cost_index_skill_last() {
    let (_, mut index) = branch_content(3).index();
    assert(index.skill(43) == 37, 'last');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 1388919)] // ceil(1.05 × 1322780 measured)
fn test_cost_index_caste_first() {
    let (_, mut index) = branch_content(3).index();
    assert(index.caste(1) == 0, 'first');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 1389129)] // ceil(1.05 × 1322980 measured)
fn test_cost_index_caste_last() {
    let (_, mut index) = branch_content(3).index();
    assert(index.caste(5) == 4, 'last');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 1388804)] // ceil(1.05 × 1322670 measured)
fn test_cost_index_fixture() {
    let (sheets, _) = branch_content(3).index();
    assert(sheets.skills.len() == 38, 'fixture');
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 6557250)] // ceil(1.05 × 6245000 measured)
fn test_cost_load_member_skills() {
    let (sheets, mut index) = branch_content(3).index();
    let words = member_effect_words(false);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, ref index, @sheets);
    assert(member.max_health == 480, 'loaded');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 6548535)] // ceil(1.05 × 6236700 measured)
fn test_cost_load_member_potions() {
    let (sheets, mut index) = branch_content(3).index();
    let words = member_effect_words(true);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, ref index, @sheets);
    assert(member.max_health == 480, 'loaded');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 6250283)] // ceil(1.05 × 5952650 measured)
fn test_cost_load_member_skills_fixture() {
    let (sheets, _) = branch_content(3).index();
    let words = member_effect_words(false);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 6249548)] // ceil(1.05 × 5951950 measured)
fn test_cost_load_member_potions_fixture() {
    let (sheets, _) = branch_content(3).index();
    let words = member_effect_words(true);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
}

// The audit's permutation (skills 40 and 42 exchanged: before CBT-02d every conclusion's lookup
// went 2 further; through the kits' positions it costs the same) measured under the tick's upper
// bound.
fn permuted(content: Content) -> Content {
    let mut forty: SkillSheet = Default::default();
    let mut forty_two: SkillSheet = Default::default();
    for sheet in content.skills {
        if *sheet.id == 40 {
            forty = *sheet;
        } else if *sheet.id == 42 {
            forty_two = *sheet;
        }
    }
    let mut skills = array![];
    for sheet in content.skills {
        let mut sheet = *sheet;
        if sheet.id == 40 {
            sheet = forty_two;
        } else if sheet.id == 42 {
            sheet = forty;
        }
        skills.append(sheet);
    }
    Content { skills: skills.span(), ..content }
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 17965861)] // ceil(1.05 × 17110343 measured)
fn test_cost_tick_worst_permuted() {
    let (mut world, sheets) = worst_state(true, 3);
    let content = permuted(content_of(@sheets)).sheets();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16431293)] // ceil(1.05 × 15648850 measured)
fn test_cost_fixture_worst_permuted() {
    let (world, sheets) = worst_state(true, 3);
    let content = permuted(content_of(@sheets)).sheets();
    assert(world.goblin_count() == 100 && content.skills.len() == 38, 'worst');
}

// ---------------------------------------------------------------------------------------------
// CBT-02b (D-163; COST-1a to COST-1c): the tick's upper bound, proved term by term.
//
// **What can vary.** Sierra charges a function that has no loop and calls none the gas of its
// costliest path, whatever path runs: a branch there cannot change the cost. A function with a
// loop, or calling one, pays the path it takes. A tick's cost, load and store's, and the sheets'
// therefore vary only with their loops: how many times each runs and which path each iteration
// takes (CBT-02d: no lookup scans a list any more; a read through the index costs the same
// wherever the record lies). The tests below
// - show the first rule on every arithmetic branch the audits named (`test_cost_path_*`: one
//   goblin's and one member's step 3 on every path, `store`, `line`; each group measures the same);
// - measure each loop's iterations on their costliest paths, at the counts' bounds: the tick's
//   step 1 branches with 0, 1 and 8 awake goblins and their mixes (`test_cost_term_*`, the tick
//   alone measured in the test), load and store
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

    goblin.health = opaque(health);
    goblin.energy = opaque(energy);
    goblin.ai = opaque(state);
    goblin.adrenaline = opaque(adrenaline);
    // R3: the regeneration is the caste's (sheet `health_regen` = pips + 10).
    let mut caste = Fixture::caste(HOB, 1);
    let pips: i32 = regen.into();
    caste.health_regen = (pips + 10).try_into().unwrap();
    let content = Content {
        skills: Fixture::content().skills, potions: array![].span(), castes: array![caste].span(),
    };
    let sheets = content.sheets();
    goblin.caste_at = 0;
    goblin.regenerate(opaque(50), @sheets);
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_below() {
    assert(regenerate_goblin(99, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_below_dead() {
    assert(regenerate_goblin(99, 2, 99, 0, 15, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in −10…−1.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_down() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_down_dead() {
    assert(regenerate_goblin(99, 2, 99, 5, 10, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in 0…10.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_up() {
    assert(regenerate_goblin(0, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_up_full() {
    assert(regenerate_goblin(0, 2, 99, 0, 278, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips above 10 (clamped).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_above() {
    assert(regenerate_goblin(0, 10, 99, 10, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_above_full() {
    assert(regenerate_goblin(0, 10, 99, 10, 270, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no effect pips.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_effect_zero() {
    assert(regenerate_goblin(99, 0, 99, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, an effect over.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_effect_over() {
    assert(regenerate_goblin(99, 2, 40, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, energy to its max.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_energy_capped() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 30, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no adrenaline to decay.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_adrenaline_zero() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 0) <= 280, 'health');
}

// A goblin's step 3, Engaged: no decay.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 721812)] // ceil(1.05 × 687440 measured)
fn test_cost_path_goblin_engaged() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ENGAGED, 5) <= 280, 'health');
}

// COST-1a: every path of one member's step 3 costs the same.

// A member's step 3, the pips below −10 (clamped), health lost.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_below() {
    assert(regenerate_member(99, 2, 99, -10, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to 0.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_below_dead() {
    assert(regenerate_member(99, 2, 99, -10, 15, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips in −10…−1.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_down() {
    assert(regenerate_member(99, 2, 99, -2, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to 0.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_down_dead() {
    assert(regenerate_member(99, 2, 99, -2, 10, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips in 0…10.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_up() {
    assert(regenerate_member(0, 2, 99, 0, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_up_full() {
    assert(regenerate_member(0, 2, 99, 0, 478, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the pips above 10 (clamped).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_above() {
    assert(regenerate_member(0, 3, 99, 5, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the same, health to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_above_full() {
    assert(regenerate_member(0, 3, 99, 5, 475, 30, false, 5) <= 480, 'health');
}

// A member's step 3, no effect pips (the effects' block skipped).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_effects_zero() {
    assert(regenerate_member(99, 0, 99, 6, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, the effects over.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_effects_over() {
    assert(regenerate_member(99, 2, 40, 6, 100, 30, false, 5) <= 480, 'health');
}

// A member's step 3, energy to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_energy_capped() {
    assert(regenerate_member(99, 2, 99, -2, 100, 59, false, 5) <= 480, 'health');
}

// A member's step 3, no adrenaline to decay.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
fn test_cost_path_member_adrenaline_zero() {
    assert(regenerate_member(99, 2, 99, -2, 100, 30, false, 0) <= 480, 'health');
}

// A member's step 3, in combat: no decay.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 4923104)] // ceil(1.05 × 4688670 measured)
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
#[available_gas(l2_gas: 603047)] // ceil(1.05 × 574330 measured)
fn test_cost_path_goblin_store_same() {
    let words = Fixture::goblin(9, RUNT).state;
    assert(store_goblin(ai::ENGAGED, 100, 0, activation::NONE, 0) == words, 'same');
}

#[test]
#[available_gas(l2_gas: 603047)] // ceil(1.05 × 574330 measured)
fn test_cost_path_goblin_store_changed() {
    let words = Fixture::goblin(9, RUNT).state;
    assert(store_goblin(ai::DEAD, 0, 3, activation::RECOVERING, 60) != words, 'changed');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 9776750)] // ceil(1.05 × 9311190 measured)
fn test_cost_path_member_store_same() {
    let words = Fixture::member_words(Fixture::spec());
    assert(store_member(status::INSIDE, 400, 30, 0, NO_SLOT, 0).state == words.state, 'same');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 9776750)] // ceil(1.05 × 9311190 measured)
fn test_cost_path_member_store_changed() {
    let words = Fixture::member_words(Fixture::spec());
    assert(store_member(status::DOWN, 0, 3, 3, 4, 60).state != words.state, 'changed');
}

// `EntryTrait::line` has no loop: an effect's pips at a rank cost the same rising or falling
// (the signed division's branches).
#[test]
#[available_gas(l2_gas: 14606)] // ceil(1.05 × 13910 measured)
fn test_cost_path_line_rising() {
    assert(EntryTrait::line(opaque(2), opaque(6), opaque(8)) == 4, 'rising');
}

#[test]
#[available_gas(l2_gas: 14606)] // ceil(1.05 × 13910 measured)
fn test_cost_path_line_falling() {
    assert(EntryTrait::line(opaque(6), opaque(-10), opaque(9)) == -6, 'falling');
}

// COST-BOUND (CBT-02b fix loop 1): step 1's branches, taken by 0, 1 and 8 awake goblins of the
// 100-goblin array, and their mixes, every state built by one builder (`term_world`) and measured
// the same way: the tick alone, `get_available_gas` around `TickTrait::tick` (printed "gas tick"),
// so that neither a fixture nor the checks after the tick enter a figure. Each test then checks
// that every awake goblin took its named branch and died in step 3 (quality 3), and that each
// goblin free in step 2 acted there (CBT-02d: the rules record the acts, `Acts`). REPORT.md and
// ENG-01 §9.2 derive the terms and the bound from these figures. Since CBT-02d the steps read and
// write the awake set alone, so a rebuild's cost follows the set's size, not the array's: the terms
// are taken at the set's bound, 8 (the "eight" states against each other and the mixes). CBT-02d
// fix loop 1: "gas tick" is the tick measured alone, short of the truth by `tick<Acts>`'s
// straight-line part, one constant (79,540, `test_cost_pair_*` below): the differences between
// states are exact, and the bound adds the constant.

/// Step 1's branches CBT-02 did not measure: a lapse whose later recharge is kept, a recovery that
/// runs on, an awake goblin already dead, a free goblin knocked down.
const B_LAPSE_KEEP: u8 = 7;
const B_RECOVERING: u8 = 8;
const B_DEAD: u8 = 9;
const B_KNOCKED: u8 = 10;

const B184: felt252 = 0x10000000000000000000000000000000000000000000000;

/// The words of an awake goblin taking `branch` in the tick of 50 (the clock at 49): at 1 health,
/// dying in step 3 (at 280 with `survive`); its activation field, a later recharge kept, dead,
/// knocked down, as the branch needs.
fn term_words(entity: u16, branch: u8, survive: bool) -> GoblinWords {
    let health = if survive {
        280
    } else {
        1
    };
    let (slot, due) = if branch == B_CONCLUDE_RECOVER || branch == B_CONCLUDE_CLEAR {
        (3, 50)
    } else if branch == B_LAPSE || branch == B_LAPSE_KEEP {
        (3, 45)
    } else if branch == B_RECOVERY_END {
        (activation::RECOVERING, 48)
    } else if branch == B_ACTIVATING {
        (3, 55)
    } else if branch == B_RECOVERING {
        (activation::RECOVERING, 55)
    } else {
        (activation::NONE, 0)
    };
    let mut words = goblin_words_at(entity, true, health, slot, due, 99);
    if branch == B_LAPSE_KEEP {
        // Slot 3's recharge at 100, later than the lapse's 45 + 20 − 1.
        words.state += 100 * B212;
    } else if branch == B_DEAD {
        words.state += (ai::DEAD - ai::ALERTED).into() * B24;
    } else if branch == B_KNOCKED {
        words.timers += 60 * B184;
    }
    words
}

/// The 100-goblin array, each frozen goblin holding a retained effect; the awake ones at indexes
/// `at`, taking `branches`; the member concluding bar slot 7 and dying (step 5's defeat);
/// `members` copies of it (M-3); the content `branch_content(k)`: `k = 3` for a conclusion into a
/// recovery, 1 for one clearing the field (no other branch reads `k`).
fn term_world(
    branches: Span<u8>, at: Span<u16>, survive: bool, k: u8, members: u32,
) -> (World, Sheets) {
    let (sheets, mut index) = branch_content(k).index();
    let mut spec = Fixture::spec();
    spec.health = 7;
    spec.conditions = [99, 99, 99, 0];
    spec.effects = [(7, false, 99, 12), (8, false, 99, 12), (2, true, 99, 0), (3, true, 99, 0)];
    let mut member = MemberTrait::load(Fixture::member_words(spec), ref index, @sheets);
    member.start(7, 8, 1, 49);
    let mut all = array![];
    for _ in 0..members {
        all.append(member);
    }
    let mut goblins = array![];
    let mut i: u16 = 0;
    while i < 100 {
        let mut words = goblin_words(8 + i, false, 280, 0, 99);
        let mut k = 0;
        while k < at.len() {
            if *at[k] == i {
                words = term_words(8 + i, *branches[k], survive);
            }
            k += 1;
        }
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        i += 1;
    }
    (Fixture::world(49, all, goblins), sheets)
}

/// The indexes of `n` awake goblins: at the array's end, at its start, or spread across it.
fn at_end(n: u16) -> Span<u16> {
    let mut at = array![];
    let mut i = 100 - n;
    while i < 100 {
        at.append(i);
        i += 1;
    }
    at.span()
}

fn at_start(n: u16) -> Span<u16> {
    let mut at = array![];
    let mut i = 0;
    while i < n {
        at.append(i);
        i += 1;
    }
    at.span()
}

fn at_spread() -> Span<u16> {
    array![5, 17, 29, 41, 53, 65, 77, 89].span()
}

/// `n` times `branch`.
fn all_of(branch: u8, n: u32) -> Span<u8> {
    let mut branches = array![];
    for _ in 0..n {
        branches.append(branch);
    }
    branches.span()
}

/// Seven times `first`, then `last`.
fn seven_then(first: u8, last: u8) -> Span<u8> {
    let mut branches = array![];
    for _ in 0..7_u8 {
        branches.append(first);
    }
    branches.append(last);
    branches.span()
}

/// What `branch` leaves on a goblin after the tick of 50: `(activation slot, its deadline, slot
/// 3's recharge)` (skill 43, activation 1, recharge 20: a conclusion at 50 recharges to 69, a lapse
/// dated 45 to 64; a recovery of `k = 3` runs to 51).
fn after(branch: u8) -> (u8, u32, u32) {
    if branch == B_CONCLUDE_RECOVER {
        (activation::RECOVERING, 51, 69)
    } else if branch == B_CONCLUDE_CLEAR {
        (activation::NONE, 0, 69)
    } else if branch == B_LAPSE {
        (activation::NONE, 0, 64)
    } else if branch == B_LAPSE_KEEP {
        (activation::NONE, 0, 100)
    } else if branch == B_ACTIVATING {
        (3, 55, 0)
    } else if branch == B_RECOVERING {
        (activation::RECOVERING, 55, 0)
    } else {
        (activation::NONE, 0, 0)
    }
}

/// One tick of `term_world`, measured alone and printed; then every awake goblin is checked to
/// have taken its branch (its field, its deadline, its recharge) and died in step 3 (survived with
/// `survive`), an awake goblin already dead to be untouched, a knocked-down one to stay so, the
/// kills to be those deaths, the member down.
fn term_tick(branches: Span<u8>, at: Span<u16>, survive: bool, k: u8, members: u32) -> u128 {
    let (mut world, content) = term_world(branches, at, survive, k, members);
    let mut rules: Acts = Default::default();
    let before = get_available_gas();
    TickTrait::tick(ref world, @content, ref rules);
    let used = before - get_available_gas();
    println!("gas tick: {}", used);
    let mut deaths = 0;
    let mut free = 0;
    let mut i = 0;
    while i < branches.len() {
        let branch = *branches[i];
        let index: u32 = (*at[i]).into();
        let goblin = @world.goblin(index);
        let (slot, deadline, recharge) = after(branch);
        assert(*goblin.act_slot == slot && *goblin.act_deadline == deadline, 'branch: field');
        assert(goblin.recharge(3) == recharge, 'branch: recharge');
        // CBT-02d (CBT-02b's quality re-audit): a goblin free in step 2 acted, at its turn (a free
        // one, and one whose lapse or recovery step 1 ended); no other did.
        if branch == B_FREE
            || branch == B_LAPSE
            || branch == B_LAPSE_KEEP
            || branch == B_RECOVERY_END {
            assert(*rules.acts[free] == index, 'branch: acted in step 2');
            free += 1;
        }
        if branch == B_DEAD {
            assert(*goblin.ai == ai::DEAD && *goblin.health == 1, 'branch: dead untouched');
        } else if survive {
            assert(goblin.is_alive() && *goblin.health > 1, 'branch: survived');
        } else {
            assert(*goblin.ai == ai::DEAD && *goblin.health == 0, 'branch: died in step 3');
            deaths += 1;
        }
        if branch == B_KNOCKED {
            assert(*goblin.knocked == 60, 'branch: knocked down');
        }
        i += 1;
    }
    assert(rules.acts.len() == free, 'branch: only the free act');
    assert(world.killed.len() == deaths, 'branch: the deaths');
    assert(world.defeated && world.member(0).status == status::DOWN, 'branch: member down');
    used
}

/// The measured tick's rules (CBT-02d): `Idle`'s, but step 2's hook records each goblin that acts,
/// so that a free goblin's branch is proved to reach it. The record is an append a goblin that
/// acts: the free branch's term counts it, a little above what `Idle` costs.
#[derive(Drop, Default)]
struct Acts {
    acts: Array<u32>,
}

impl ActsRules of Rules<Acts> {
    fn perceive(ref self: Acts, ref world: World) {}
    fn resolve(
        ref self: Acts, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Acts, ref world: World, sheets: @Sheets, index: u32) {
        self.acts.append(index);
    }
    fn objectives(ref self: Acts, ref world: World) {}
}

// No goblin awake: the base (the member concluding and dying; the array not read).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15406108)] // ceil(1.05 × 14672483 measured)
fn test_cost_term_none() {
    term_tick(array![].span(), array![].span(), false, 1, 1);
}

// The same with the content of a conclusion into a recovery: `k` changes nothing else.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15406108)] // ceil(1.05 × 14672483 measured)
fn test_cost_term_none_k3() {
    term_tick(array![].span(), array![].span(), false, 3, 1);
}

// The base with two members (M-3): what the second member adds.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15600308)] // ceil(1.05 × 14857436 measured)
fn test_cost_term_none_two_members() {
    term_tick(array![].span(), array![].span(), false, 1, 2);
}

// CBT-02d fix loop 1 (COST-3): the base with four and eight members (M-3 allows 8). Each member's
// conclusion rebuilds the members' array, so a member adds more the more there are.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16041441)] // ceil(1.05 × 15277562 measured)
fn test_cost_term_none_four_members() {
    term_tick(array![].span(), array![].span(), false, 1, 4);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 17141622)] // ceil(1.05 × 16325354 measured)
fn test_cost_term_none_eight_members() {
    term_tick(array![].span(), array![].span(), false, 1, 8);
}

// One goblin: concluding into a recovery.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16043416)] // ceil(1.05 × 15279443 measured)
fn test_cost_term_one_conclude_recover() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 1), at_end(1), false, 3, 1);
}

// Eight goblins: concluding into a recovery.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20852678)] // ceil(1.05 × 19859693 measured)
fn test_cost_term_eight_conclude_recover() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 8), at_end(8), false, 3, 1);
}

// One goblin: concluding, the field cleared.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16045424)] // ceil(1.05 × 15281356 measured)
fn test_cost_term_one_conclude_clear() {
    term_tick(all_of(B_CONCLUDE_CLEAR, 1), at_end(1), false, 1, 1);
}

// Eight goblins: concluding, the field cleared.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20868747)] // ceil(1.05 × 19874997 measured)
fn test_cost_term_eight_conclude_clear() {
    term_tick(all_of(B_CONCLUDE_CLEAR, 8), at_end(8), false, 1, 1);
}

// One goblin: a lapse.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16065794)] // ceil(1.05 × 15300756 measured)
fn test_cost_term_one_lapse() {
    term_tick(all_of(B_LAPSE, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a lapse.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20635395)] // ceil(1.05 × 19652757 measured)
fn test_cost_term_eight_lapse() {
    term_tick(all_of(B_LAPSE, 8), at_end(8), false, 1, 1);
}

// One goblin: a lapse, the later recharge kept.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16066193)] // ceil(1.05 × 15301136 measured)
fn test_cost_term_one_lapse_keep() {
    term_tick(all_of(B_LAPSE_KEEP, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a lapse, the later recharge kept.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20638587)] // ceil(1.05 × 19655797 measured)
fn test_cost_term_eight_lapse_keep() {
    term_tick(all_of(B_LAPSE_KEEP, 8), at_end(8), false, 1, 1);
}

// One goblin: a recovery over.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16024886)] // ceil(1.05 × 15261796 measured)
fn test_cost_term_one_recovery_end() {
    term_tick(all_of(B_RECOVERY_END, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a recovery over.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20301138)] // ceil(1.05 × 19334417 measured)
fn test_cost_term_eight_recovery_end() {
    term_tick(all_of(B_RECOVERY_END, 8), at_end(8), false, 1, 1);
}

// One goblin: activating, busy.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15996922)] // ceil(1.05 × 15235163 measured)
fn test_cost_term_one_activating() {
    term_tick(all_of(B_ACTIVATING, 1), at_end(1), false, 1, 1);
}

// Eight goblins: activating, busy.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20125343)] // ceil(1.05 × 19166993 measured)
fn test_cost_term_eight_activating() {
    term_tick(all_of(B_ACTIVATING, 8), at_end(8), false, 1, 1);
}

// One goblin: a recovery running on.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15997331)] // ceil(1.05 × 15235553 measured)
fn test_cost_term_one_recovering() {
    term_tick(all_of(B_RECOVERING, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a recovery running on.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20128619)] // ceil(1.05 × 19170113 measured)
fn test_cost_term_eight_recovering() {
    term_tick(all_of(B_RECOVERING, 8), at_end(8), false, 1, 1);
}

// One goblin: free, acting in step 2.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16002164)] // ceil(1.05 × 15240156 measured)
fn test_cost_term_one_free() {
    term_tick(all_of(B_FREE, 1), at_end(1), false, 1, 1);
}

// Eight goblins: free, acting in step 2.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20167284)] // ceil(1.05 × 19206937 measured)
fn test_cost_term_eight_free() {
    term_tick(all_of(B_FREE, 8), at_end(8), false, 1, 1);
}

// One goblin: free but knocked down.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15997531)] // ceil(1.05 × 15235743 measured)
fn test_cost_term_one_knocked() {
    term_tick(all_of(B_KNOCKED, 1), at_end(1), false, 1, 1);
}

// Eight goblins: free but knocked down.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20130215)] // ceil(1.05 × 19171633 measured)
fn test_cost_term_eight_knocked() {
    term_tick(all_of(B_KNOCKED, 8), at_end(8), false, 1, 1);
}

// One goblin: awake and already dead.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 15970504)] // ceil(1.05 × 15210003 measured)
fn test_cost_term_one_dead() {
    term_tick(all_of(B_DEAD, 1), at_end(1), false, 1, 1);
}

// Eight goblins: awake and already dead.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 19913999)] // ceil(1.05 × 18965713 measured)
fn test_cost_term_eight_dead() {
    term_tick(all_of(B_DEAD, 8), at_end(8), false, 1, 1);
}

// One goblin concluding into a recovery, surviving step 3.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16043710)] // ceil(1.05 × 15279723 measured)
fn test_cost_term_one_conclude_recover_surviving() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 1), at_end(1), true, 3, 1);
}

// The costliest mix: 7 conclusions, then a lapse whose write the end of step 1 rebuilds.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20884697)] // ceil(1.05 × 19890187 measured)
fn test_cost_term_mix_clear_lapse() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_end(8), false, 1, 1);
}

// The same, the awake goblins at the array's start.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20879919)] // ceil(1.05 × 19885637 measured)
fn test_cost_term_mix_clear_lapse_start() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_start(8), false, 1, 1);
}

// The same, the awake goblins spread across the array.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20867487)] // ceil(1.05 × 19873797 measured)
fn test_cost_term_mix_clear_lapse_spread() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_spread(), false, 1, 1);
}

// Swap: 7 conclusions, then an activating goblin.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20774885)] // ceil(1.05 × 19785604 measured)
fn test_cost_term_mix_clear_activating() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_ACTIVATING), at_end(8), false, 1, 1);
}

// Swap: 7 conclusions, then a recovery over.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20843789)] // ceil(1.05 × 19851227 measured)
fn test_cost_term_mix_clear_recovery_end() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_RECOVERY_END), at_end(8), false, 1, 1);
}

// Swap: 7 activating goblins, then a lapse.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20233717)] // ceil(1.05 × 19270206 measured)
fn test_cost_term_mix_activating_lapse() {
    term_tick(seven_then(B_ACTIVATING, B_LAPSE), at_end(8), false, 1, 1);
}

// A lapse first, then 7 conclusions: its write goes with the first conclusion's rebuild.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20832900)] // ceil(1.05 × 19840857 measured)
fn test_cost_term_mix_lapse_first() {
    term_tick(
        array![
            B_LAPSE, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR,
            B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR,
        ]
            .span(),
        at_end(8),
        false,
        1,
        1,
    );
}

// CBT-02d: the model at 8 awake goblins (REPORT.md, ENG-01 §9.2) against more states. Each state
// is the awake set's 8 branches, in the set's order (`C` a conclusion clearing the field, `A`
// activating, `L` a lapse, `R` a recovery over).
fn term_mix(branches: Array<u8>) {
    term_tick(branches.span(), at_end(8), false, 1, 1);
}

const C: u8 = B_CONCLUDE_CLEAR;
const A: u8 = B_ACTIVATING;
const L: u8 = B_LAPSE;
const R: u8 = B_RECOVERY_END;

// A conclusion first in the set, the others activating.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20199550)] // ceil(1.05 × 19237666 measured)
fn test_cost_term_set_c_first() {
    term_mix(array![C, A, A, A, A, A, A, A]);
}

// A conclusion in the middle of the set.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20202532)] // ceil(1.05 × 19240506 measured)
fn test_cost_term_set_c_middle() {
    term_mix(array![A, A, A, C, A, A, A, A]);
}

// A conclusion last in the set.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20202532)] // ceil(1.05 × 19240506 measured)
fn test_cost_term_set_c_last() {
    term_mix(array![A, A, A, A, A, A, A, C]);
}

// An activating goblin first, 7 conclusions after it.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20764070)] // ceil(1.05 × 19775304 measured)
fn test_cost_term_set_a_then_c() {
    term_mix(array![A, C, C, C, C, C, C, C]);
}

// Two conclusions, then activating goblins.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20291974)] // ceil(1.05 × 19325689 measured)
fn test_cost_term_set_cc_first() {
    term_mix(array![C, C, A, A, A, A, A, A]);
}

// Six conclusions, then two lapses (two writes left for the end of step 1).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20834654)] // ceil(1.05 × 19842527 measured)
fn test_cost_term_set_c6_ll() {
    term_mix(array![C, C, C, C, C, C, L, L]);
}

// Six conclusions, an activating goblin, a lapse.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20778476)] // ceil(1.05 × 19789024 measured)
fn test_cost_term_set_c6_al() {
    term_mix(array![C, C, C, C, C, C, A, L]);
}

// Six conclusions, a lapse, an activating goblin.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20778476)] // ceil(1.05 × 19789024 measured)
fn test_cost_term_set_c6_la() {
    term_mix(array![C, C, C, C, C, C, L, A]);
}

// Six conclusions, a recovery over, a lapse.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20793746)] // ceil(1.05 × 19803567 measured)
fn test_cost_term_set_c6_rl() {
    term_mix(array![C, C, C, C, C, C, R, L]);
}

// A lapse between two conclusions: its write goes with the next conclusion's.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20829918)] // ceil(1.05 × 19838017 measured)
fn test_cost_term_set_c_l_c6() {
    term_mix(array![C, L, C, C, C, C, C, C]);
}

// A recovery over between two conclusions.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20789010)] // ceil(1.05 × 19799057 measured)
fn test_cost_term_set_c_r_c6() {
    term_mix(array![C, R, C, C, C, C, C, C]);
}

// Two lapses between two conclusions: both writes go with the next conclusion's.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20793672)] // ceil(1.05 × 19803497 measured)
fn test_cost_term_set_c_ll_c5() {
    term_mix(array![C, L, L, C, C, C, C, C]);
}

// A lapse first, the others activating.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20219920)] // ceil(1.05 × 19257066 measured)
fn test_cost_term_set_l_first() {
    term_mix(array![L, A, A, A, A, A, A, A]);
}

// A lapse in the middle, the others activating.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20219920)] // ceil(1.05 × 19257066 measured)
fn test_cost_term_set_l_middle() {
    term_mix(array![A, A, A, L, A, A, A, A]);
}

// Two lapses last, the others activating.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20276098)] // ceil(1.05 × 19310569 measured)
fn test_cost_term_set_a6_ll() {
    term_mix(array![A, A, A, A, A, A, L, L]);
}

// COST-1a: load and store, once per call, on their costliest paths (CBT-02d: through the index).
// The index: every list at its bound (38 skills, 5 castes, 4 potions), each caste's kit finding
// its four skills and raising its cap at each (costs 1 to 4 strikes); the cap's clamp at 252 is
// not reachable (DS-18: a caste skill costs at most 63 strikes, `CasteAssert::assert_skills`). A
// goblin's load has no loop: its caste and its effect (skill 43) read through the index, the
// costlier path (a goblin without an effect reads one id less). The member's: its four effects on
// the skill path (the potion path costs less, `test_cost_load_member_*`), its bar's eight skills
// each raising its cap (costs 1 to 8). `store` has no loop (`test_cost_path_*_store_*`). A read
// through the index costs the same wherever the record lies (`test_cost_index_*`): nothing is
// charged beyond the measure.

/// `branch_content(3)` with increasing adrenaline costs: the bar's skills 1–8 cost 1–8 strikes,
/// each caste's four skills 1–4, so that every step of an adrenaline cap's loop raises it.
fn load_content() -> Content {
    let content = branch_content(3);
    let mut skills = array![];
    for sheet in content.skills {
        let mut sheet = *sheet;
        if sheet.id <= 8 {
            sheet.adrenaline = sheet.id.try_into().unwrap();
        } else if sheet.id >= 24 && sheet.id <= 43 {
            sheet.adrenaline = ((sheet.id - 24) % 4 + 1).try_into().unwrap();
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 24011568)] // ceil(1.05 × 22868160 measured)
fn test_cost_load_bound() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let (world, _) = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 12699026)] // ceil(1.05 × 12094310 measured)
fn test_cost_load_bound_fixture() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

// The same with two members (M-3): what each member adds.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 34081404)] // ceil(1.05 × 32458480 measured)
fn test_cost_load_bound_two_members() {
    let (words, content) = load_words(2);
    let (expected, _) = load_words(2);
    let (world, _) = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 22425911)] // ceil(1.05 × 21358010 measured)
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 56060)] // ceil(1.05 × 53390 measured)
fn test_cost_sheet_skill_regen_first() {
    assert(read_skill([kind::REGENERATION, kind::DAMAGE, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the second.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 59472)] // ceil(1.05 × 56640 measured)
fn test_cost_sheet_skill_regen_second() {
    assert(read_skill([kind::DAMAGE, kind::REGENERATION, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 62885)] // ceil(1.05 × 59890 measured)
fn test_cost_sheet_skill_regen_third() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third, negative.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 64145)] // ceil(1.05 × 61090 measured)
fn test_cost_sheet_skill_regen_third_negative() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], -3, -10) == -3, 'regen');
}

// A skill's sheet, its `REGENERATION`: none of three entries.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 54894)] // ceil(1.05 × 52280 measured)
fn test_cost_sheet_skill_none() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::DAMAGE], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: an empty second entry.
#[test]
// gas: raised, CBT-05b: the skill sheet reads the header's energy and profession
#[available_gas(l2_gas: 50715)] // ceil(1.05 × 48300 measured)
fn test_cost_sheet_skill_damage_then_empty() {
    assert(read_skill([kind::DAMAGE, kind::EMPTY, kind::EMPTY], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: no entry.
#[test]
// gas: raised, CBT-05b: the skill sheet reads the header's energy and profession
#[available_gas(l2_gas: 47093)] // ceil(1.05 × 44850 measured)
fn test_cost_sheet_skill_empty() {
    assert(read_skill([kind::EMPTY, kind::EMPTY, kind::EMPTY], 2, 6) == 0, 'regen');
}

#[test]
#[available_gas(l2_gas: 17052)] // ceil(1.05 × 16240 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 29096)] // ceil(1.05 × 27710 measured)
fn test_cost_sheet_potion_regen() {
    assert(
        PotionSheetTrait::read(opaque(7), potion_parts(kind::REGENERATION, 3)).regen == 3, 'regen',
    );
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 29096)] // ceil(1.05 × 27710 measured)
fn test_cost_sheet_potion_regen_negative() {
    assert(
        PotionSheetTrait::read(opaque(7), potion_parts(kind::REGENERATION, -3)).regen == -3,
        'regen',
    );
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 28886)] // ceil(1.05 × 27510 measured)
fn test_cost_sheet_potion_damage() {
    assert(PotionSheetTrait::read(opaque(7), potion_parts(kind::DAMAGE, 3)).regen == 0, 'none');
}

#[test]
#[available_gas(l2_gas: 12432)] // ceil(1.05 × 11840 measured)
fn test_cost_sheet_potion_fixture() {
    assert(potion_parts(kind::REGENERATION, 3).len() == 1, 'parts');
}

// A caste's sheet (no loop).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 388175)] // ceil(1.05 × 369690 measured)
fn test_cost_sheet_caste() {
    let (_, caste) = records();
    assert(CasteSheetTrait::read(opaque(1), opaque(caste)).weapon_ticks == 2, 'caste');
}

#[test]
#[available_gas(l2_gas: 344967)] // ceil(1.05 × 328540 measured)
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

// Not the tick's cost (CBT-05a, route (c)): each concluding carrier of this fixture calls
// ExecutorLibrary (one goblin a tile since F-2; the figures before were fixture artefacts). The
// tick's cost is ENG-01 §9.2's measured line (45,999,941 the worst tick, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 49875059)] // ceil(1.05 × 47500056 measured)
fn test_cost_library_call_kills() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_kills();
    let words = ticks_of(library, words, content, board(), 1);
    assert(words.killed.len() == 100, 'every goblin once');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 29795665)] // ceil(1.05 × 28376823 measured)
fn test_cost_library_baseline_kills() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_kills();
    let (mut world, sheets) = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    assert(words.killed.len() == 100, 'every goblin once');
}

/// `worst_words` with its member twice (M-3: members 0–7).
fn worst_words_two() -> (Words, Content) {
    let (words, content) = worst_words();
    let member = *words.members.at(0);
    (Words { members: array![member, member], ..words }, content)
}

// Not the tick's cost (CBT-05a, route (c)): each concluding carrier of this fixture calls
// ExecutorLibrary (one goblin a tile since F-2; the figures before were fixture artefacts). The
// tick's cost is ENG-01 §9.2's measured line (45,999,941 the worst tick, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 83041881)] // ceil(1.05 × 79087505 measured)
fn test_cost_library_call_two_members() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_two();
    let words = ticks_of(library, words, content, board(), 1);
    assert(words.members.len() == 2, 'two members');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 29955383)] // ceil(1.05 × 28528936 measured)
fn test_cost_library_baseline_two_members() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_two();
    let (mut world, sheets) = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    assert(words.members.len() == 2, 'two members');
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
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 44230910)] // ceil(1.05 × 42124676 measured)
fn test_cost_library_call_all_dead() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_all_dead();
    let words = ticks_of(library, words, content, board(), 1);
    assert(words.killed.len() == 100, 'each goblin once');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 28780735)] // ceil(1.05 × 27410223 measured)
fn test_cost_library_baseline_all_dead() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words_all_dead();
    let (mut world, sheets) = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    assert(words.killed.len() == 100, 'each goblin once');
}

// ---------------------------------------------------------------------------------------------
// CBT-02d's parity table (AC-1): the pipeline's results on the existing fixtures, hashed (Poseidon
// over the words the pipeline leaves, the clock, the kills and the defeat, and the hooks the rules
// recorded). The hashes were taken on the representation before CBT-02d (every goblin in one array
// of 23-felt structs, the content looked up by id at every load) and pin the new one's results:
// the same states, the same rules, the same words.

fn digest(world: World, extra: Span<felt252>) -> felt252 {
    let mut out = array![];
    world.store().serialize(ref out);
    out.append_span(extra);
    core::poseidon::poseidon_hash_span(out.span())
}

fn script_digest(world: World, rules: Script) -> felt252 {
    let mut extra = array![];
    rules.acts.serialize(ref extra);
    rules.resolved.serialize(ref extra);
    digest(world, extra.span())
}

fn scripted(mut world: World, content: @Sheets, ticks: u8) -> felt252 {
    let mut rules: Script = Default::default();
    TickTrait::run(ref world, content, ticks, ref rules);
    script_digest(world, rules)
}

/// The worked examples and the rules' tests, their states and rules as those tests build them.
fn parity_examples() -> Array<felt252> {
    let content = Fixture::sheets();
    let mut out = array![];
    // §10.3, the degeneration.
    let mut spec = Fixture::spec();
    spec.conditions = [77, 72, 0, 0];
    let world = Fixture::world(69, array![Fixture::member(spec)], array![Fixture::goblin(17, HOB)]);
    out.append(scripted(world, @content, 6));
    // §10.1, a burning goblin.
    let mut goblin = Fixture::goblin(24, HOB);
    goblin.health = 87;
    goblin.burning = 44;
    out.append(scripted(Fixture::only(41, goblin), @content, 4));
    // §10.2, an interrupt.
    let mut goblin = Fixture::goblin(40, HOB);
    goblin.start(0, 0, 3, 50);
    goblin.knocked = 53;
    goblin.interrupt(52, @content);
    out.append(scripted(Fixture::only(51, goblin), @content, 3));
    // §10.5, a lapse: frozen four ticks, then awake.
    let mut goblin = Fixture::goblin(30, HOB);
    goblin.start(0, 0, 3, 100);
    goblin.awake = false;
    goblin.health = 50;
    goblin.bleeding = 105;
    let mut world = Fixture::only(102, goblin);
    run(ref world, 4);
    let mut goblin = world.goblin(0);
    goblin.awake = true;
    world.set_goblin(0, goblin);
    out.append(scripted(world, @content, 1));
    let mut goblin = Fixture::goblin(30, HOB);
    goblin.start(0, 0, 3, 100);
    goblin.set_recharge(0, 200);
    out.append(scripted(Fixture::only(106, goblin), @content, 1));
    // §10.9, an activated attack's cost.
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.recover(2, 50);
    out.append(scripted(Fixture::only(50, goblin), @content, 2));
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.start(1, 0, 1, 50);
    out.append(scripted(Fixture::only(50, goblin), @content, 2));
    let k3 = Content {
        castes: array![Fixture::caste(HOB, 1), Fixture::caste(RUNT, 3)].span(),
        ..Fixture::content(),
    }
        .sheets();
    let mut goblin = Fixture::goblin(9, RUNT);
    goblin.start(1, 0, 1, 50);
    out.append(scripted(Fixture::only(50, goblin), @k3, 3));
    // §10.1 and §10.6, a member's activation.
    let mut member = Fixture::member(Fixture::spec());
    member.start(1, 57, 2, 40);
    out.append(scripted(Fixture::world(40, array![member], array![]), @content, 2));
    // §5.8, regeneration.
    let mut skills = array![
        SkillSheet {
            id: 1,
            kind: skill_kind::SPELL,
            adrenaline: 0,
            activation: 0,
            recharge: 0,
            regen0: 2,
            regen12: 6,
            ..Default::default(),
        },
    ];
    for id in 2..9_u16 {
        skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
    }
    let regen = Content {
        skills: skills.span(),
        potions: array![PotionSheet { id: 101, regen: 3, ..Default::default() }].span(),
        castes: array![].span(),
    };
    let mut spec = Fixture::spec();
    spec
        .effects =
            [(1, false, 10, 12), (1, true, MAX_CLOCK, 0), (1, false, 4, 12), (0, false, 0, 0)];
    spec.energy = 55;
    spec.health_regen = 1;
    spec.energy_regen = 4;
    let (regen, mut index) = regen.index();
    let member = MemberTrait::load(Fixture::member_words(spec), ref index, @regen);
    out.append(scripted(Fixture::world(4, array![member], array![]), @regen, 2));
    let mut spec = Fixture::spec();
    spec.health = 479;
    spec.health_regen = 10;
    out.append(scripted(Fixture::world(0, array![Fixture::member(spec)], array![]), @content, 1));
    // Step 3's extremes.
    let mut spec = Fixture::spec();
    spec.health_regen = -10;
    spec.effect_regen = [-10; 4];
    spec.effects = [(1, false, 99, 0); 4];
    spec.conditions = [99, 99, 99, 0];
    out.append(scripted(Fixture::world(0, array![Fixture::member(spec)], array![]), @content, 1));
    let mut spec = Fixture::spec();
    spec.health = 300;
    spec.health_regen = 10;
    spec.effect_regen = [10; 4];
    spec.effects = [(1, false, 99, 0); 4];
    out.append(scripted(Fixture::world(0, array![Fixture::member(spec)], array![]), @content, 1));
    // Adrenaline decay.
    let mut spec = Fixture::spec();
    spec.adrenaline = 5;
    let mut alerted = Fixture::goblin(8, HOB);
    alerted.ai = ai::ALERTED;
    alerted.adrenaline = 1;
    let mut frozen_engaged = Fixture::goblin(9, HOB);
    frozen_engaged.awake = false;
    let world = Fixture::world(0, array![Fixture::member(spec)], array![alerted, frozen_engaged]);
    out.append(scripted(world, @content, 2));
    let mut engaged = Fixture::goblin(8, HOB);
    engaged.adrenaline = 4;
    let world = Fixture::world(0, array![Fixture::member(spec)], array![engaged]);
    out.append(scripted(world, @content, 1));
    // Deaths in step 3, then the executor's kill.
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
    run(ref world, 2);
    world.kill(2);
    world.kill(2);
    out.append(digest(world, array![].span()));
    // Defeat, in step 3 and in step 2.
    let mut spec = Fixture::spec();
    spec.health = 6;
    spec.conditions = [9, 9, 9, 0];
    out.append(scripted(Fixture::world(0, array![Fixture::member(spec)], array![]), @content, 3));
    let mut a = Fixture::goblin(8, HOB);
    a.health = 50;
    a.bleeding = 9;
    let b = Fixture::goblin(9, HOB);
    let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], array![a, b]);
    let mut rules: Script = Default::default();
    rules.kill_member_at = 1;
    TickTrait::run(ref world, @content, 2, ref rules);
    out.append(script_digest(world, rules));
    // Who acts.
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
    let world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
    out.append(scripted(world, @content, 2));
    // The flags.
    let mut spec = Fixture::spec();
    spec.flags = flag::TURNED + flag::INSTANT + flag::HIT + flag::HALVED;
    out.append(scripted(Fixture::world(0, array![Fixture::member(spec)], array![]), @content, 1));
    // The awake set, then a tick.
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
    TickTrait::awake(ref world, array![1, 1, 5, 3, 3, 9, 2, 3, 4, 3, 6].span());
    out.append(scripted(world, @content, 2));
    // The member down before the tick.
    let mut spec = Fixture::spec();
    spec.health = 0;
    let mut goblin = Fixture::goblin(8, HOB);
    goblin.bleeding = 99;
    let world = Fixture::world(49, array![Fixture::member(spec)], array![goblin]);
    out.append(scripted(world, @content, 3));
    out
}

/// The benchmarks' states: the representative batch, CBT-02's heavy tick, `Busy`'s batch, the
/// load's costliest words, the kills, two members, the awake selection over 100 candidates.
fn parity_states() -> Array<felt252> {
    let mut out = array![];
    let (world, content) = representative();
    out.append(scripted(world, @content, 10));
    let (world, content) = worst_state(true, 3);
    out.append(scripted(world, @content, 1));
    let (world, content) = worst_of(true, 3, 8);
    out.append(scripted(world, @content, 1));
    let (mut world, content) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    TickTrait::run(ref world, @content, 10, ref rules);
    out.append(digest(world, array![].span()));
    let (words, content) = load_words(1);
    let (world, sheets) = words.load(@content);
    out.append(scripted(world, @sheets, 1));
    let (words, content) = worst_words_kills();
    let (world, sheets) = words.load(@content);
    out.append(scripted(world, @sheets, 1));
    let (words, content) = worst_words_two();
    let (world, sheets) = words.load(@content);
    out.append(scripted(world, @sheets, 1));
    let (mut world, distances) = candidates();
    TickTrait::awake(ref world, distances);
    out.append(scripted(world, @worst_content(3).sheets(), 2));
    out
}

fn term_digest(branches: Span<u8>, at: Span<u16>, survive: bool, k: u8, members: u32) -> felt252 {
    let (world, content) = term_world(branches, at, survive, k, members);
    scripted(world, @content, 1)
}

/// The weapon cost of a branch's content: 1 for a conclusion clearing the field, else 3.
fn k_of(branch: u8) -> u8 {
    if branch == B_CONCLUDE_CLEAR {
        1
    } else {
        3
    }
}

/// Every branch of step 1 taken by one awake goblin; the base, with one and two members; a
/// survivor.
fn parity_terms_one() -> Array<felt252> {
    let mut out = array![];
    out.append(term_digest(array![].span(), array![].span(), false, 1, 1));
    out.append(term_digest(array![].span(), array![].span(), false, 1, 2));
    for branch in 1..11_u8 {
        out.append(term_digest(all_of(branch, 1), at_end(1), false, k_of(branch), 1));
    }
    out.append(term_digest(all_of(B_CONCLUDE_RECOVER, 1), at_end(1), true, 3, 1));
    out
}

/// Every branch taken by eight awake goblins.
fn parity_terms_eight() -> Array<felt252> {
    let mut out = array![];
    for branch in 1..11_u8 {
        out.append(term_digest(all_of(branch, 8), at_end(8), false, k_of(branch), 1));
    }
    out
}

/// The mixes of branches, the costliest at three placements.
fn parity_terms_mixed() -> Array<felt252> {
    let mut out = array![];
    let mix = seven_then(B_CONCLUDE_CLEAR, B_LAPSE);
    out.append(term_digest(mix, at_end(8), false, 1, 1));
    out.append(term_digest(mix, at_start(8), false, 1, 1));
    out.append(term_digest(mix, at_spread(), false, 1, 1));
    out.append(term_digest(seven_then(B_CONCLUDE_CLEAR, B_ACTIVATING), at_end(8), false, 1, 1));
    out.append(term_digest(seven_then(B_CONCLUDE_CLEAR, B_RECOVERY_END), at_end(8), false, 1, 1));
    out.append(term_digest(seven_then(B_ACTIVATING, B_LAPSE), at_end(8), false, 3, 1));
    let first = array![
        B_LAPSE, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR,
        B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR, B_CONCLUDE_CLEAR,
    ];
    out.append(term_digest(first.span(), at_end(8), false, 1, 1));
    out
}

/// Each case's hash against the one the representation before CBT-02d gave; re-taken once by
/// CBT-05a when the fixtures gave each goblin its own tile (the cost audit of #334, F-2: the words
/// hashed carry the position), checked equal with the positions zeroed at that commit.
fn check(digests: Span<felt252>, expected: Span<felt252>) {
    assert(digests.len() == expected.len(), 'parity: the cases');
    let mut i = 0;
    for digest in digests {
        if *digest != *expected[i] {
            println!("parity: case {} differs", i);
        }
        assert(*digest == *expected[i], 'parity: a result moved');
        i += 1;
    }
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 138649976)] // ceil(1.05 × 132047596 measured)
fn test_parity_examples() {
    let expected = array![
        1241239600139814297445332189267579437395556034260927953445438187785428878731,
        491717564647083686894055142658152103720224761551139940084970406250512277846,
        3279354350096061797672110377414646121550019867768224401483363015248632403870,
        83824577866241555736452047896067232811119888308199248696069757999218338843,
        3181341630533443102889018483946007907540995978223971023322942914042873787001,
        2586313296703552823193594313852174495102426775065760629887616998179214029507,
        2282094649473355371114114019674337843111945168566928552033171932999753110715,
        903416554857088170097693242839874924587443961869280753302820931050691423178,
        36816074613476127739194688687361647858952182761094686373073532436844626909,
        578299332572586597861253641443536109702505773854295383591492880389142847899,
        2256981156959556821140546821485115600311245454586228425009447030319208542273,
        2002548036566857385627003582764042318200407604042384761949088270124994837581,
        1687685766588233095728758727432648551106488922145377264927484828051984820318,
        607213395876240693311469384551087878148168016217732081155760531034260965242,
        891777736309743493325478634454341459091768690012685325243590989484595176054,
        2933140010559893209433732273596883974226591012891511291573945804947483340308,
        3569151246204370127189098609633852058304810835945494873622362819867673589044,
        3172806269214616740873881451656776072551644801186086110487524010356007479437,
        2538373200902374196645501793894615009434001110123875393181816749730969080654,
        1574109686732086378521569676370240047520439259817296123398255027621323721654,
        2092477404879913529660556085007281953094978727880571781133569368787650641652,
        377493575383891479358179621635677024782546422683899913320429701904083862605,
    ];
    check(parity_examples().span(), expected.span());
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 183606176)] // ceil(1.05 × 174863024 measured)
fn test_parity_states() {
    let expected = array![
        66295114118071479459692970620146523881576091136849489442811860794139663220,
        808422254243259305840304007192953190570462588589555851527360096323524280134,
        1562186334722086418794275886745872927941055543107018119596060415278450572351,
        295399596692219204516051653795587539389394577102401082652067649159716880434,
        439083406005192959298043225307314616152890940397256647856484438139925370554,
        73287514594659960351089047476225634273791689893107856364339595328214538127,
        672680495394139033065139172651255376436422202887688089913912883213982738,
        655218035378556033694747075122745594573863938720241866706354387721645146505,
    ];
    check(parity_states().span(), expected.span());
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 249572466)] // ceil(1.05 × 237688062 measured)
fn test_parity_terms_one() {
    let expected = array![
        3038755871554351985509578304603922128981991713350037726200715711668783036078,
        2390267439041613580292175067155718416986082322101661109002376790803246254762,
        1055802584482405271093899595010580580653618145027575177474460778286406724907,
        140997757383240654257187850256527151336762656580290816999988035351526037647,
        1550146487006184777674087130078780108861858839225551415693046141337121060206,
        3000944188458659557852553919439759593451333884090877217505913575528358419954,
        958347345670750575144752480880292934757348978277952291997779621529030583426,
        3000944188458659557852553919439759593451333884090877217505913575528358419954,
        2901465040800497629709066572878720157134385070623909553822840889136292252763,
        1398129606302398168371537113535614590887429125419253691181278995264326048167,
        1574127088032828288997064300282737979204227246352899238496857812692829010321,
        3229579640699399341668646575686735669814858765266248342283769751082534094116,
        2765035817719631134698385506113413930744617616572862413416551091584261272447,
    ];
    check(parity_terms_one().span(), expected.span());
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 235258884)] // ceil(1.05 × 224056080 measured)
fn test_parity_terms_eight() {
    let expected = array![
        1808371299317739356955277762182254020355613512078900379947700298413305354772,
        1389807536523082212550662442957446196238419454932274218797270027939059136868,
        902841071752934107945215011121051080154160284451668309995126000319248301421,
        1641292372929327539745070677606918789936085680229117120712311003490521667178,
        3207944635339513361575546103073032495697939215932135823638739454615802563196,
        1641292372929327539745070677606918789936085680229117120712311003490521667178,
        1183040122373310544210024907162599652808578602451064147666755717875658272090,
        2404426831637612310345493071506344510622956763018367271806387133970456750371,
        1254615115529063358619643491225183810307575748337925269938194755890448243009,
        3500926107291528816115360811725439760092008636757520683653937626418709972405,
    ];
    check(parity_terms_eight().span(), expected.span());
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 167457269)] // ceil(1.05 × 159483113 measured)
fn test_parity_terms_mixed() {
    let expected = array![
        3456503857176978450510507868394441494222831065116789317693612010392171537615,
        2074571354771343534831302062651387188341960647999230892147038797106811705912,
        2770701094563789559767424222642857161775939071428306894284100455416310174638,
        2339933191205360864781844478841897196662027880592601433147974605674537649106,
        429922995581156223717121047600835788176215337578929749548430656218172255077,
        1199420404553182624446564920822483066274570582284161552460626750024335536034,
        3181526588172973680219134105997191070994012937899146268664908348034237568484,
    ];
    check(parity_terms_mixed().span(), expected.span());
}

/// The executor's class (route (c), CBT-05a), declared once a test.
fn executor() -> starknet::ClassHash {
    *declare("ExecutorLibrary").unwrap().contract_class().class_hash
}

/// The goblins' acts' class (ENG-07) and the traps' (D-222).
fn ai_class() -> starknet::ClassHash {
    *declare("AiLibrary").unwrap().contract_class().class_hash
}

/// `TickLibrary`'s ticks with the classes of the tests, the ground none (ENG-07, D-235).
fn ticks_of(
    library: ITickLibraryLibraryDispatcher, words: Words, content: Content, board: Board, n: u8,
) -> Words {
    let (words, _) = library.ticks(words, content, board, classes(), 10, array![], n);
    words
}

fn classes() -> grimworld_logic::types::play::Classes {
    grimworld_logic::types::play::Classes {
        executor: executor(),
        ai: ai_class(),
        trap: trap(),
        action: *declare("ActionLibrary").unwrap().contract_class().class_hash,
        tick: *declare("TickLibrary").unwrap().contract_class().class_hash,
    }
}

fn trap() -> starknet::ClassHash {
    *declare("TrapLibrary").unwrap().contract_class().class_hash
}

/// The board of the library's calls (CBT-05a): an open window at the location's origin. The
/// fixtures' actors stand at (0, 0) and conclude no carrier that reaches another actor.
fn board() -> Board {
    // Every one of the 240 positions open.
    BoardTrait::new(
        WindowTrait::new(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff), 0, 0,
    )
}

// ---- Route (c), behaviour and cost (CBT-05a, the review of #334)
// ----------------------------------
// `TickLibrary` runs each carrier through `ExecutorLibrary` with a sub-world (every member, the
// source, the addressed goblin; a carrier wider than `SINGLE` or on a `TILE` also the goblins
// within one tile of the source or the address, a `SINGLE` one none, option (3)'s lever (3)). These
// tests spread the goblins so that the sub-world is a strict subset and the source's sub-index
// differs from its index, and compare the library's words with the in-process executor's.

/// The member's tile in the window: (7, 7), position 112.
const AT: u8 = 112;

fn place(position: u8) -> felt252 {
    let x: felt252 = (position % 15).into();
    let y: felt252 = (position / 15).into();
    x + y * two(8)
}

/// The fixtures' member at `AT`, level 20 (spell strength 60), health `health`.
fn member_at(health: u16) -> Member {
    let mut spec = Fixture::spec();
    spec.health = health;
    let mut member = Fixture::member(spec);
    member.words.state += place(AT) * two(32);
    member.words.stats += 20 * two(64);
    member
}

/// A goblin of caste HOB at `position`, health `health`, awake if `awake`.
fn goblin_at(entity: u16, position: u8, health: u16, awake: bool) -> Goblin {
    let mut goblin = Fixture::goblin(entity, HOB);
    goblin.state += place(position);
    goblin.health = health;
    goblin.awake = awake;
    goblin
}

/// The tiles around `centre`, ascending.
fn ring(centre: u8) -> Span<u8> {
    let open = WindowTrait::new(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    WindowTrait::tiles(open.shape(shape::RING_1, centre))
}

/// The fixtures' content with: bar skill 2, Cinder Ring (fire 80 and Burning 3 on `RING_1`, `SELF`,
/// `FOES`); caste HOB's weapon `damage` at rank 15 and range `range`; caste skill 25, an attack
/// skill of activation 1 (the implicit weapon hit).
fn route_content(damage: u8, range: u8) -> Content {
    let base = Fixture::content();
    let fire = EntryTrait::new(
        kind::DAMAGE, 4, 80, 80, 0, 0, 0, target::SELF, shape::RING_1, filter::FOES, 0, 0,
    );
    let burn = EntryTrait::new(
        kind::CONDITION, 3, 3, 3, 0, 0, 0, target::SELF, shape::RING_1, filter::FOES, 0, 0,
    );
    let mut skills = array![];
    for sheet in base.skills {
        let mut sheet = *sheet;
        if sheet.id == 2 {
            sheet.entry1 = fire.pack();
            sheet.entry2 = burn.pack();
        }
        skills.append(sheet);
    }
    let mut castes = array![];
    for caste in base.castes {
        let mut caste = *caste;
        if caste.id == HOB {
            caste.weapon = weapon::SWORD;
            caste.weapon_damage = damage;
            caste.damage_type = 1;
            caste.weapon_range = range;
            caste.rank = 15;
        }
        castes.append(caste);
    }
    Content { skills: skills.span(), potions: base.potions, castes: castes.span() }
}

/// One tick through `TickLibrary` (route (c)) and the same tick in process with the in-class
/// executor: their words must agree.
fn agree(words: Words, content: Content) -> Words {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (mut world, sheets) = words.clone().load(@content);
    let out = ticks_of(library, words, content, board(), 1);
    let mut rules = ExecutorTrait::new(board());
    TickTrait::run(ref world, @sheets, 1, ref rules);
    assert(out == world.store(), 'route (c) = in process');
    out
}

// The member's Cinder Ring concludes at tick 41 and kills goblins 9 and 10 (adjacent, 50 health;
// 80 at x = 60 is 226), in tile order, which the sub-world reaches; goblins 8 and 11 are far and
// stay out of the call. The library's words equal the in-process executor's.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 25283808)] // ceil(1.05 × 24079817 measured)
fn test_route_c_kills_in_order() {
    let tiles = ring(AT);
    let mut member = member_at(400);
    member.start(1, 0, 1, 40);
    let goblins = array![
        goblin_at(8, 0, 100, false), goblin_at(9, *tiles[0], 50, true),
        goblin_at(10, *tiles[2], 50, true), goblin_at(11, 230, 100, false),
    ];
    let words = Fixture::world(40, array![member], goblins).store();
    let out = agree(words, route_content(30, 1));
    assert(out.killed.span() == array![9, 10].span(), 'killed in tile order');
    assert(!out.defeated, 'not defeated');
}

// Goblin 10 (index 2; goblin 8, far, holds index 0) concludes its attack skill on the member at
// tick 41: its sub-index in the call is 1, not 2. Its weapon hit (255 at rank 15, strength 75)
// downs the member at 10 health: the tick stops, defeated. The words agree.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 16326406)] // ceil(1.05 × 15548958 measured)
fn test_route_c_source_sub_index_and_defeat() {
    let tiles = ring(AT);
    let mut source = goblin_at(10, *tiles[1], 100, true);
    source.start(1, 0, 1, 40);
    let goblins = array![goblin_at(8, 230, 100, false), goblin_at(9, *tiles[0], 100, true), source];
    let words = Fixture::world(40, array![member_at(10)], goblins).store();
    let out = agree(words, route_content(255, 1));
    assert(out.defeated, 'defeated');
    assert(out.killed.len() == 0, 'no kill');
}

// Lever (1)'s potion branch (the delta review of #334): the member holds belt slot 1's potion
// (item 101) as an effect, and the content lists potion 100 before it, which no load needs, so the
// call's trimmed content keeps 101 alone, at another position. Goblin 9 concludes its attack skill
// on the member at tick 41; the member's regeneration reads the potion. The words agree.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 20223854)] // ceil(1.05 × 19260813 measured)
fn test_route_c_potion_effect() {
    let tiles = ring(AT);
    let mut spec = Fixture::spec();
    spec.health = 400;
    spec.effects = [(1, true, 99, 0), (0, false, 0, 0), (0, false, 0, 0), (0, false, 0, 0)];
    let mut member = Fixture::member(spec);
    member.words.state += place(AT) * two(32);
    member.words.stats += 20 * two(64);
    let mut source = goblin_at(9, *tiles[0], 100, true);
    source.start(1, 0, 1, 40);
    let goblins = array![goblin_at(8, 230, 100, false), source];
    let words = Fixture::world(40, array![member], goblins).store();
    let base = route_content(30, 1);
    let potions = array![
        PotionSheet { id: 100, regen: 7, ..Default::default() },
        PotionSheet { id: 101, regen: 3, ..Default::default() },
    ];
    let content = Content { skills: base.skills, potions: potions.span(), castes: base.castes };
    let out = agree(words, content);
    assert(!out.defeated && out.killed.len() == 0, 'member hit, alive');
    assert(out.members.len() == 1, 'one member');
}

/// The representative worst tick (the review of #334, ENG-01 §9.2): 13 goblins within one tile of
/// the member or of each other, the member's ring of 6 and 7 at distance 2; 8 of them awake, each
/// concluding its attack skill on the member at tick 41 with a reach of 6 (all legal). Each call
/// carries the member and its source alone (lever (3); before it, the goblins within one tile of
/// its source or of the member too).
fn worst_tick() -> (World, Sheets, grimworld_logic::types::tick::Index) {
    let inner = ring(AT);
    let mut outer: Array<u8> = array![];
    let mut position: u8 = 0;
    while position < 240 && outer.len() < 7 {
        if WindowTrait::distance(position, AT) == 2 {
            outer.append(position);
        }
        position += 1;
    }
    let mut goblins = array![];
    let mut entity: u16 = 8;
    let mut awake: u32 = 0;
    for tile in inner {
        let mut goblin = goblin_at(entity, *tile, 250, true);
        goblin.start(1, 0, 1, 40);
        goblins.append(goblin);
        entity += 1;
        awake += 1;
    }
    for tile in outer.span() {
        let wake = awake < 8;
        let mut goblin = goblin_at(entity, *tile, 250, wake);
        if wake {
            goblin.start(1, 0, 1, 40);
            awake += 1;
        }
        goblins.append(goblin);
        entity += 1;
    }
    let words = Fixture::world(40, array![member_at(480)], goblins).store();
    let content = route_content(5, 6);
    let (world, sheets, index) = words.indexed(@content);
    (world, sheets, index)
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 13275816)] // ceil(1.05 × 12643634 measured)
fn test_cost_route_c_tick_fixture() {
    let (world, sheets, _) = worst_tick();
    assert(opaque(world.goblin_count()) == 13 && sheets.skills.len() > 0, 'fixture');
}

// The worst tick in process with the in-class executor (route (a)'s shape): the pair's base.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 26209348)] // ceil(1.05 × 24961283 measured)
fn test_cost_route_c_tick_in_class() {
    let (mut world, sheets, _) = worst_tick();
    let mut rules = ExecutorTrait::new(board());
    TickTrait::tick(ref world, @sheets, ref rules);
    assert(rules.cache.hits == 8, 'eight hits');
}

// The same tick through route (c): `TickLibrary`'s hook builds each sub-world, calls
// `ExecutorLibrary` and loads back what returns, 8 times.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 50625470)] // ceil(1.05 × 48214733 measured)
fn test_cost_route_c_tick() {
    let (mut world, sheets, index) = worst_tick();
    let content = route_content(5, 6);
    let mut rules = grimworld_logic::types::executor::Delegate {
        board: board(),
        cache: Default::default(),
        executor: executor(),
        content,
        index,
        placed: array![],
        ground: array![],
        ai: ai_class(),
        trap: trap(),
        level: 10,
        frozen: 0,
        listed: 0,
    };
    TickTrait::tick(ref world, @sheets, ref rules);
    assert(rules.cache.hits == 8 && !world.defeated, 'eight hits');
}

// ---- The representative worst, through `TickLibrary` (the cost audit of #334, F-1) --------------
// The member at `AT`; 8 awake goblins one per tile, its ring of 6 and 2 behind (design/04, ENG-01
// §9.2); the worst content (38 skills, 4 potions, 5 castes), caste 1's weapon of reach 6 so that
// every goblin's attack is legal. Scenarios, one tick unless said: 0 idle; 1 the 8 goblins each
// conclude an attack skill on the member; 2 the member concludes Cinder Ring on its ring; 3 one
// goblin 3 tiles away concludes on the member with 13 goblins around them (its 6 neighbours and
// the member's 6): after lever (3) its call carries only it and the member, so the scenario
// measures that the carrier's cost does not grow with its neighbours; 4 scenario 3's state idle; 5
// scenarios 1 and 2 in the same tick (the member's activation and the 8 goblins' conclude
// together).

fn rep_content() -> Content {
    let base = worst_content(1);
    let fire = EntryTrait::new(
        kind::DAMAGE, 4, 80, 80, 0, 0, 0, target::SELF, shape::RING_1, filter::FOES, 0, 0,
    );
    let burn = EntryTrait::new(
        kind::CONDITION, 3, 3, 3, 0, 0, 0, target::SELF, shape::RING_1, filter::FOES, 0, 0,
    );
    let mut skills = array![];
    for sheet in base.skills {
        let mut sheet = *sheet;
        if sheet.id == 2 {
            sheet.kind = skill_kind::SPELL;
            sheet.entry1 = fire.pack();
            sheet.entry2 = burn.pack();
        }
        skills.append(sheet);
    }
    let mut castes = array![];
    for caste in base.castes {
        let mut caste = *caste;
        caste.weapon = weapon::BOW;
        caste.weapon_damage = 5;
        caste.damage_type = 2;
        caste.weapon_range = 6;
        caste.rank = 15;
        castes.append(caste);
    }
    Content { skills: skills.span(), potions: base.potions, castes: castes.span() }
}

fn rep_words(scenario: u8) -> Words {
    let mut member = member_at(480);
    if scenario == 2 || scenario == 5 {
        member.start(1, 0, 1, 40);
    }
    let mut goblins = array![];
    let mut entity: u16 = 8;
    if scenario == 3 || scenario == 4 {
        // The member's ring of 6 (frozen but alive), and around a source 3 tiles away its 6
        // neighbours (frozen) and the source itself, awake.
        let source = AT + 3;
        let mut tiles: Array<u8> = array![];
        for tile in ring(AT) {
            tiles.append(*tile);
        }
        for tile in ring(source) {
            tiles.append(*tile);
        }
        tiles.append(source);
        // Ascending positions, ascending entities.
        let sorted = ascending_u8(tiles.span());
        for tile in sorted {
            let own = *tile == source;
            let mut goblin = goblin_at(entity, *tile, 250, own);
            if own && scenario == 3 {
                goblin.start(0, 0, 1, 40);
            }
            goblins.append(goblin);
            entity += 1;
        }
    } else {
        let mut tiles: Array<u8> = array![];
        for tile in ring(AT) {
            tiles.append(*tile);
        }
        let mut position: u8 = 0;
        let mut behind: u32 = 0;
        while position < 240 && behind < 2 {
            if WindowTrait::distance(position, AT) == 2 {
                tiles.append(position);
                behind += 1;
            }
            position += 1;
        }
        for tile in ascending_u8(tiles.span()) {
            let mut goblin = goblin_at(entity, *tile, 250, true);
            if scenario == 1 || scenario == 5 {
                goblin.start(0, 0, 1, 40);
            }
            goblins.append(goblin);
            entity += 1;
        }
    }
    Fixture::world(40, array![member], goblins).store()
}

/// `tiles` ascending (a selection: at most 13).
fn ascending_u8(tiles: Span<u8>) -> Span<u8> {
    let mut sorted: Array<u8> = array![];
    let mut last: u16 = 0;
    let mut first = true;
    while sorted.len() < tiles.len() {
        let mut least: u16 = 0x100;
        for tile in tiles {
            let t: u16 = (*tile).into();
            if (first || t > last) && t < least {
                least = t;
            }
        }
        sorted.append(least.try_into().unwrap());
        last = least;
        first = false;
    }
    sorted.span()
}

fn rep_run(scenario: u8, ticks: u8) -> Words {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let executor = executor();
    ticks_of(library, rep_words(scenario), rep_content(), board(), ticks)
}

/// A fixture: the same arguments and classes, no call.
fn rep_fixture(scenario: u8) {
    let class = declare("TickLibrary").unwrap().contract_class();
    let _ = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _ = executor();
    let words = rep_words(scenario);
    let content = rep_content();
    assert(opaque(words.goblins.len()) > 0 && content.skills.len() == 38, 'fixture');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 10195463)] // ceil(1.05 × 9709964 measured)
fn test_cost_rep_fixture() {
    rep_fixture(0);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 11090760)] // ceil(1.05 × 10562628 measured)
fn test_cost_rep_far_fixture() {
    rep_fixture(4);
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 24361326)] // ceil(1.05 × 23201262 measured)
fn test_cost_rep_idle() {
    let words = rep_run(0, 1);
    assert(words.members.len() == 1, 'ran');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 51017698)] // ceil(1.05 × 48588283 measured)
fn test_cost_rep_goblins() {
    let words = rep_run(1, 1);
    assert(!words.defeated, 'eight carriers');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 33986741)] // ceil(1.05 × 32368324 measured)
fn test_cost_rep_member() {
    let words = rep_run(2, 1);
    assert(words.killed.len() == 0, 'no kill');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 60645433)] // ceil(1.05 × 57757555 measured)
fn test_cost_rep_all() {
    let words = rep_run(5, 1);
    assert(!words.defeated && words.killed.len() == 0, 'nine carriers');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 26565595)] // ceil(1.05 × 25300566 measured)
fn test_cost_rep_far() {
    let words = rep_run(3, 1);
    assert(words.goblins.len() == 13, 'thirteen');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 26565794)] // ceil(1.05 × 25300756 measured)
fn test_cost_rep_far_idle() {
    let words = rep_run(4, 1);
    assert(words.goblins.len() == 13, 'thirteen');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 185978910)] // ceil(1.05 × 177122771 measured)
fn test_cost_rep_batch() {
    let words = rep_run(1, 10);
    assert(words.clock == 50, 'ten ticks');
}

// ---- The action phase with a bomb (CBT-05b; ENG-01 §9.2, D-207) --------------------------------
// Scenario 1's state (8 awake goblins, one a tile, each concluding its attack skill on the member
// at tick 41) and the worst content, the member's belt slot 0 a bomb: fire 30 on `DISC_1` around
// a tile (`TILE`, `FOES`), range 6, strength 20 (FX-28, FX-35). The action phase runs in process
// with `TickLibrary`'s rules (`Delegate`): the bomb's carrier, and each goblin's in the tick,
// through `ExecutorLibrary`. Each figure less `test_cost_bomb_fixture`.

fn bomb_content() -> Content {
    let base = rep_content();
    let bomb = EntryTrait::new(
        kind::DAMAGE, 4, 30, 30, 0, 0, 0, target::TILE, shape::DISC_1, filter::FOES, 0, 0,
    );
    let mut potions = array![
        PotionSheet { id: 100, regen: 0, entry: bomb.pack(), range: 6, strength: 20 },
    ];
    for potion in base.potions.slice(1, base.potions.len() - 1) {
        potions.append(*potion);
    }
    Content { skills: base.skills, potions: potions.span(), castes: base.castes }
}

/// The ring tile around `AT` whose `DISC_1` holds the most goblins of scenario 1, as a location
/// tile `x + 256 y` (the board at the origin), and how many goblins its `DISC_1` holds.
fn bomb_tile() -> (u16, u32) {
    let mut goblins: Array<u8> = array![];
    for tile in ring(AT) {
        goblins.append(*tile);
    }
    let mut position: u8 = 0;
    let mut behind: u32 = 0;
    while position < 240 && behind < 2 {
        if WindowTrait::distance(position, AT) == 2 {
            goblins.append(position);
            behind += 1;
        }
        position += 1;
    }
    let mut best: u8 = 0;
    let mut most: u32 = 0;
    for centre in ring(AT) {
        let mut count = 0;
        for goblin in goblins.span() {
            if WindowTrait::distance(*goblin, *centre) <= 1 {
                count += 1;
            }
        }
        if count > most {
            most = count;
            best = *centre;
        }
    }
    ((best % 15).into() + 256 * (best / 15).into(), most)
}

fn bomb_state() -> (World, Sheets, grimworld_logic::types::executor::Delegate) {
    let mut words = rep_words(1);
    let mut member = *words.members[0];
    // Belt slot 0: one bomb (`MemberState` 128–135).
    member.state += two(128);
    words.members = array![member];
    let content = bomb_content();
    let (world, sheets, index) = words.indexed(@content);
    let rules = grimworld_logic::types::executor::Delegate {
        board: board(),
        cache: Default::default(),
        executor: executor(),
        content,
        index,
        placed: array![],
        ground: array![],
        ai: ai_class(),
        trap: trap(),
        level: 10,
        frozen: 0,
        listed: 0,
    };
    (world, sheets, rules)
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14567136)] // ceil(1.05 × 13873462 measured)
fn test_cost_bomb_fixture() {
    let (world, sheets, rules) = bomb_state();
    let _ = bomb_tile();
    assert(opaque(world.goblin_count()) == 8 && sheets.potions.len() == 4, 'fixture');
    let _ = rules;
}

// The action phase's floor: a Wait (legality only).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 14614785)] // ceil(1.05 × 13918842 measured)
fn test_cost_bomb_wait() {
    let (mut world, sheets, mut rules) = bomb_state();
    let _ = bomb_tile();
    let ticks = ActionTrait::act(ref world, @sheets, ref rules, 0, Action::Wait);
    assert(ticks == Ok(1), 'wait');
}

// The bomb alone: legality, the belt, facing, its carrier through `ExecutorLibrary`.
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 23584972)] // ceil(1.05 × 22461878 measured)
fn test_cost_bomb_action() {
    let (mut world, sheets, mut rules) = bomb_state();
    let (tile, most) = bomb_tile();
    let ticks = ActionTrait::act(ref world, @sheets, ref rules, 0, Action::Item((0, tile)));
    assert(ticks == Ok(1) && rules.cache.hits == most && most >= 3, 'bomb');
}

// The 8 goblins' tick alone, the same state (its pair).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 51734111)] // ceil(1.05 × 49270581 measured)
fn test_cost_bomb_goblins() {
    let (mut world, sheets, mut rules) = bomb_state();
    let _ = bomb_tile();
    TickTrait::run(ref world, @sheets, 1, ref rules);
    assert(rules.cache.hits == 8 && !world.defeated, 'eight carriers');
}

// The bomb and its tick: the action phase, then the 8 goblin carriers (the task's measure, D-207).
#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 60747852)] // ceil(1.05 × 57855097 measured)
fn test_cost_bomb_tick() {
    let (mut world, sheets, mut rules) = bomb_state();
    let (tile, most) = bomb_tile();
    let ticks = ActionTrait::act(ref world, @sheets, ref rules, 0, Action::Item((0, tile)))
        .unwrap();
    TickTrait::run(ref world, @sheets, ticks, ref rules);
    assert(rules.cache.hits == most + 8 && !world.defeated, 'bomb, then eight');
}

// The same through `TickLibrary::act` (D-222): the whole call, its fixture the same arguments and
// classes without the call. `act_wait` against `rep_idle` (one idle tick through `run`) prices the
// action phase's entrypoint per action.
fn act_words() -> Words {
    let mut words = rep_words(1);
    let mut member = *words.members[0];
    member.state += two(128);
    words.members = array![member];
    words
}

#[test]
#[available_gas(l2_gas: 12672568)] // ceil(1.05 × 12069112 measured)
fn test_cost_act_fixture() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let _ = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _ = executor();
    let words = act_words();
    let content = bomb_content();
    let (tile, _) = bomb_tile();
    assert(opaque(words.goblins.len()) > 0 && content.potions.len() == 4 && tile > 0, 'fixture');
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 66164508)] // ceil(1.05 × 63013817 measured)
fn test_cost_act_bomb() {
    let (tile, _) = bomb_tile();
    let words = act_then_ticks(act_words(), Action::Item((0, tile)));
    assert(words.clock == 41, 'bomb, one tick');
}

/// The action through `ActionLibrary` (D-233), then its ticks through `TickLibrary` (the segment
/// that chains the two is ENG-07's, not built yet: two calls here).
fn act_then_ticks(words: Words, action: Action) -> Words {
    let class = declare("ActionLibrary").unwrap().contract_class();
    let library = grimworld_logic::interface::IActionLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let content = bomb_content();
    let (words, _, ticks) = grimworld_logic::interface::IActionLibraryDispatcherTrait::act(
        library, words, content, board(), executor(), array![], action,
    );
    let ticks = match ticks {
        Ok(ticks) => ticks,
        Err(_) => core::panic_with_felt252('illegal'),
    };
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    ticks_of(library, words, content, board(), ticks)
}

#[test]
// gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
#[available_gas(l2_gas: 30345546)] // ceil(1.05 × 28900520 measured)
fn test_cost_act_wait() {
    let (tile, _) = bomb_tile();
    let _ = tile;
    let words = act_then_ticks(rep_words(0), Action::Wait);
    assert(words.clock == 41, 'wait, one tick');
}

// ---- A trap's trigger through `TrapLibrary` (D-222) --------------------------------------------
// A terrain trap (kind 4) on the member's tile, its `param` the worst content's skill 2 (fire 80,
// Burning 3): the member enters it; the call carries the member alone, the worst content and the
// chunk's features. Less its fixture: the same arguments and class, no call.

fn trap_args() -> (Words, Content, Array<(u8, grimworld_logic::models::chunk::Features)>) {
    let words = Words {
        clock: 40,
        members: array![member_at(480).store()],
        goblins: array![],
        killed: array![],
        defeated: false,
    };
    let terrain = grimworld_logic::models::chunk::Object {
        tile: AT, kind: grimworld_logic::models::chunk::object::TRAP, state: 0, param: 2,
    };
    let features = grimworld_logic::models::chunk::Features {
        objects: [terrain, Default::default(), Default::default()],
        ..grimworld_logic::models::chunk::FeaturesTrait::empty(),
    };
    (words, rep_content(), array![(0, features)])
}

#[test]
#[available_gas(l2_gas: 5809997)] // ceil(1.05 × 5533330 measured)
fn test_cost_trap_class_fixture() {
    let class = declare("TrapLibrary").unwrap().contract_class();
    let _ = grimworld_logic::interface::ITrapLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let (words, content, ground) = trap_args();
    assert(
        opaque(words.members.len()) == 1 && content.skills.len() == 38 && ground.len() == 1,
        'fixture',
    );
}

#[test]
#[available_gas(l2_gas: 9540480)] // ceil(1.05 × 9086171 measured)
fn test_cost_trap_class() {
    let class = declare("TrapLibrary").unwrap().contract_class();
    let library = grimworld_logic::interface::ITrapLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let (words, content, ground) = trap_args();
    let (out, ground, triggered) = library.trigger(words, content, board(), ground, 0, AT, 10);
    let (_, features) = *ground.at(0);
    let [used, _, _] = features.objects;
    assert(triggered && used.state == 1 && out.members.len() == 1, 'triggered');
}

// ---- ENG-07: the act hook's class (`AiLibrary`), its call measured as a pair (D-225) -----------
// Scenario 0's state (the member at `AT`, 8 awake goblins one a tile: its ring of 6 and 2 behind),
// every goblin in AI state `state`. Returning (5) goblins are awake, free and do nothing: the call
// alone. Engaged (3) ones each attack the member with their weapon of reach 6 through
// `ExecutorLibrary`. Busy ones (recovering until tick 100) make no call (D-225).

fn ai_words(state: u8, busy: bool) -> Words {
    ai_words_of(state, busy, false)
}

/// The same, every caste skill recharging until tick 100 when `recharging`: each Engaged goblin
/// attacks with its weapon.
fn ai_words_of(state: u8, busy: bool, recharging: bool) -> Words {
    let words = rep_words(0);
    let mut goblins = array![];
    for goblin in words.goblins.span() {
        let mut goblin = *goblin;
        goblin.state = goblin.state + (state.into() - ai::ENGAGED.into()) * two(24);
        if busy {
            goblin.timers = goblin.timers - 1 + 100 * two(24);
        }
        if recharging {
            goblin.state = goblin.state + 100 * (two(128) + two(156) + two(184) + two(212));
        }
        goblins.append(goblin);
    }
    Words { goblins, ..words }
}

fn ai_call(state: u8) -> Words {
    ai_call_of(ai_words(state, false))
}

fn ai_call_of(words: Words) -> Words {
    let class = declare("AiLibrary").unwrap().contract_class();
    let library = grimworld_logic::interface::IAiLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let (out, _) = grimworld_logic::interface::IAiLibraryDispatcherTrait::act(
        library, words, rep_content(), board(), executor(), trap(), array![], 10, 0, 0, 0,
    );
    out
}

#[test]
#[available_gas(l2_gas: 10460084)] // ceil(1.05 × 9961984 measured)
fn test_cost_ai_fixture() {
    let class = declare("AiLibrary").unwrap().contract_class();
    let _ = grimworld_logic::interface::IAiLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let _ = executor();
    let _ = trap();
    let words = ai_words(5, false);
    let content = rep_content();
    assert(opaque(words.goblins.len()) == 8 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 14643676)] // ceil(1.05 × 13946358 measured)
fn test_cost_ai_call_returning() {
    let out = ai_call(5);
    assert(out.goblins.len() == 8, 'eight');
}

#[test]
#[available_gas(l2_gas: 17987137)] // ceil(1.05 × 17130606 measured)
fn test_cost_ai_call_engaged() {
    let out = ai_call(ai::ENGAGED);
    assert(out.goblins.len() == 8 && !out.defeated, 'eight attacks');
}

fn ai_tick(state: u8, busy: bool) -> Words {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    ticks_of(library, ai_words(state, busy), rep_content(), board(), 1)
}

#[test]
#[available_gas(l2_gas: 16470833)] // ceil(1.05 × 15686507 measured)
fn test_cost_ai_tick_busy() {
    let words = ai_tick(5, true);
    assert(words.clock == 41, 'one tick');
}

#[test]
#[available_gas(l2_gas: 21274317)] // ceil(1.05 × 20261254 measured)
fn test_cost_ai_tick_returning() {
    let words = ai_tick(5, false);
    assert(words.clock == 41, 'one tick');
}

#[test]
#[available_gas(l2_gas: 24609630)] // ceil(1.05 × 23437742 measured)
fn test_cost_ai_tick_engaged() {
    let words = ai_tick(ai::ENGAGED, false);
    assert(words.clock == 41, 'one tick');
}


#[test]
#[available_gas(l2_gas: 58364292)] // ceil(1.05 × 55585040 measured)
fn test_cost_ai_call_attacks() {
    let before = ai_words_of(ai::ENGAGED, false, true);
    let state = (*before.members[0]).state;
    let out = ai_call_of(before);
    assert((*out.members[0]).state != state, 'eight attacks');
}

#[test]
#[available_gas(l2_gas: 17820300)] // ceil(1.05 × 16971714 measured)
fn test_cost_ai_fixture_attacks() {
    let class = declare("AiLibrary").unwrap().contract_class();
    let _ = grimworld_logic::interface::IAiLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let _ = executor();
    let _ = trap();
    let words = ai_words_of(ai::ENGAGED, false, true);
    let content = rep_content();
    assert(opaque(words.goblins.len()) == 8 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 62498506)] // ceil(1.05 × 59522386 measured)
fn test_cost_ai_tick_attacks() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let words = ticks_of(library, ai_words_of(ai::ENGAGED, false, true), rep_content(), board(), 1);
    assert(words.clock == 41, 'one tick');
}

// ---- ENG-07 (D-235): the segment, its fast path, an exploration batch and a fight batch --------
// The segment runs in process here (as `PlayLibrary` runs it), with every class it calls declared:
// `TickLibrary` for the ticks with a fight, `AiLibrary`, `ActionLibrary`, `ExecutorLibrary`,
// `TrapLibrary`. The area: 3 × 3 chunks, every one revealed and walkable. Each figure less its
// fixture (the same arguments and classes, no segment).

fn open_area() -> grimworld_logic::types::play::Area {
    let mut known: felt252 = 0;
    let mut chunks: Array<(u8, felt252)> = array![];
    let all = two(225) - 1;
    for chunk in array![0_u8, 1, 2, 15, 16, 17, 30, 31, 32] {
        known += two(chunk.into());
        chunks.append((chunk, all));
    }
    grimworld_logic::types::play::Area {
        width: 3, height: 3, known, revealed: known, chunks: chunks.span(),
    }
}

fn segment_of(words: Words, actions: Span<Action>) -> (Words, grimworld_logic::types::play::Done) {
    let content = rep_content();
    let classes = classes();
    let area = open_area();
    let (mut world, sheets, index) = words.indexed(@content);
    let mut rules = grimworld_logic::types::executor::Delegate {
        board: board(),
        cache: Default::default(),
        executor: classes.executor,
        content,
        index,
        placed: array![],
        ground: array![],
        ai: classes.ai,
        trap: classes.trap,
        level: 10,
        frozen: 0,
        listed: 0,
    };
    let done = grimworld_logic::types::play::SegmentTrait::run(
        ref world, @sheets, ref rules, @area, @classes, actions, 0, 10,
    );
    (world.store(), done)
}

/// Ten Moves, East then West in turn: no goblin, every tick on the fast path.
fn exploration() -> (Words, Span<Action>) {
    let words = Fixture::world(40, array![member_at(400)], array![]).store();
    let mut actions = array![];
    let mut k: u8 = 0;
    while k < 10 {
        actions.append(Action::Move(if k % 2 == 0 {
            0
        } else {
            3
        }));
        k += 1;
    }
    (words, actions.span())
}

/// Ten weapon attacks of the member on goblins 10, 11 and 12 (on its ring), the 8 goblins Engaged
/// around it, each attacking with its weapon (its skills recharging): every tick has a fight.
fn fight() -> (Words, Span<Action>) {
    let mut words = ai_words_of(ai::ENGAGED, false, true);
    // The member's weapon (the executor's tests' melee one): class 1, damage 27, range 1,
    // strength 60, slashing, its requirement met.
    let mut member = *words.members[0];
    member.stats += two(88) + 27 * two(96) + two(112) + 60 * two(120) + two(160) + two(176);
    words.members = array![member];
    (words, attacks())
}

/// The same, the member's health and max health raised from 480 to 20,000 (`MemberState` 64–79,
/// `MemberStats` 0–15) so that it stands
/// through the ten ticks: the batch whole.
fn fight_whole() -> (Words, Span<Action>) {
    let (mut words, actions) = fight();
    let mut member = *words.members[0];
    member.state += 19520 * two(64);
    member.stats += 19520;
    words.members = array![member];
    (words, actions)
}

fn attacks() -> Span<Action> {
    let mut actions = array![];
    let mut k: u8 = 0;
    // Goblin 10 falls to 4 hits: then 11, then 12, each on the member's ring.
    while k < 10 {
        actions.append(Action::Attack(10 + (k / 4).into()));
        k += 1;
    }
    actions.span()
}

fn segment_fixture(words: Words, actions: Span<Action>) {
    let _ = classes();
    let area = open_area();
    let content = rep_content();
    assert(
        opaque(words.members.len()) == 1
            && actions.len() == 10
            && area.chunks.len() == 9
            && content.skills.len() == 38,
        'fixture',
    );
}

#[test]
#[available_gas(l2_gas: 6491772)] // ceil(1.05 × 6182640 measured)
fn test_cost_segment_exploration_fixture() {
    let (words, actions) = exploration();
    segment_fixture(words, actions);
}

#[test]
#[available_gas(l2_gas: 17515590)] // ceil(1.05 × 16681514 measured)
fn test_cost_segment_exploration() {
    let (words, actions) = exploration();
    let (out, done) = segment_of(words, actions);
    println!("exploration: played {} weight {} clock {}", done.played, done.weight, out.clock);
    assert(done.played == 10 && out.clock == 50, 'ten moves');
}

#[test]
#[available_gas(l2_gas: 19468958)] // ceil(1.05 × 18541864 measured)
fn test_cost_segment_fight_fixture() {
    let (words, actions) = fight();
    segment_fixture(words, actions);
}

#[test]
#[available_gas(l2_gas: 217826994)] // ceil(1.05 × 207454280 measured)
fn test_cost_segment_fight() {
    let (words, actions) = fight();
    let (out, done) = segment_of(words, actions);
    println!(
        "fight: played {} weight {} clock {} defeated {} killed {} illegal {:?}",
        done.played,
        done.weight,
        out.clock,
        out.defeated,
        out.killed.len(),
        done.illegal,
    );
    assert(done.played > 0, 'played');
}

// D-235: the fast path and `TickLibrary` on the same ticks give the same words (the events a batch
// emits are read from them: the kills, the defeat). The member bleeding, a goblin frozen outside
// the window; three ticks each way.
#[test]
#[available_gas(l2_gas: 12284284)] // ceil(1.05 × 11699318 measured)
fn test_segment_fast_path_equals_tick_library() {
    let mut member = member_at(400);
    member.bleeding = 45;
    let mut far = Fixture::goblin(8, HOB);
    far.state += 100 + 100 * two(8);
    far.awake = false;
    let words = Fixture::world(40, array![member], array![far]).store();
    let content = rep_content();
    let (mut world, sheets) = words.clone().load(@content);
    let mut idle = Idle {};
    TickTrait::run(ref world, @sheets, 3, ref idle);
    let fast = world.store();
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let slow = ticks_of(library, words, content, board(), 3);
    assert(fast == slow, 'fast path differs');
    assert(fast.clock == 43, 'three ticks');
}

#[test]
#[available_gas(l2_gas: 19562954)] // ceil(1.05 × 18631384 measured)
fn test_cost_segment_fight_whole_fixture() {
    let (words, actions) = fight_whole();
    segment_fixture(words, actions);
}

#[test]
#[available_gas(l2_gas: 527545587)] // ceil(1.05 × 502424368 measured)
fn test_cost_segment_fight_whole() {
    let (words, actions) = fight_whole();
    let (out, done) = segment_of(words, actions);
    println!(
        "fight whole: played {} weight {} clock {} defeated {} killed {} illegal {:?}",
        done.played,
        done.weight,
        out.clock,
        out.defeated,
        out.killed.len(),
        done.illegal,
    );
    assert(done.played > 0, 'played');
}

// D-233 #4 (b): the member's activation (Cinder Ring, scenario 2's: fire 80 and Burning 3 on its
// ring) lands in step 1 of the tick in which the 8 Engaged goblins, their skills recharging, attack
// it with their weapons in step 2 (the ring's goblins at 250 health survive the ring). One tick
// through `TickLibrary`, less the same arguments without the call.
fn landing_words() -> Words {
    let mut words = ai_words_of(ai::ENGAGED, false, true);
    let mut member = *words.members[0];
    // Its activation field (`MemberTimers`), as scenario 2 starts it: due at tick 41.
    member.timers = (*rep_words(2).members[0]).timers;
    words.members = array![member];
    words
}

#[test]
#[available_gas(l2_gas: 27245598)] // ceil(1.05 × 25948188 measured)
fn test_cost_landing_fixture() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let _ = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _ = classes();
    let words = landing_words();
    let content = rep_content();
    assert(opaque(words.goblins.len()) == 8 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 81594778)] // ceil(1.05 × 77709312 measured)
fn test_cost_landing() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let words = ticks_of(library, landing_words(), rep_content(), board(), 1);
    println!(
        "landing: clock {} defeated {} killed {}", words.clock, words.defeated, words.killed.len(),
    );
    assert(words.clock == 41, 'one tick');
}

// ---- Lever 1 (CBT-05d; the project manager, 2026-10-07): at most 4 goblins attack a tick -------
// A measure, not the rule: the fight batch's state with only goblins 8 to 11 attacking (Engaged,
// skills recharging); goblins 12 to 15 stay awake, alive and free but do nothing (Returning), as
// the cap would leave them, and they are the member's targets (12, 13, 14 × 3 each, 15), so the 4
// attackers stand through the batch. The cap's own selection is not built: its cost is not in.

fn lever_words(health: u16) -> Words {
    let (words, _) = fight();
    let mut goblins = array![];
    let mut k: u32 = 0;
    for goblin in words.goblins.span() {
        let mut goblin = *goblin;
        if k >= 4 {
            goblin.state = goblin.state + 2 * two(24);
        }
        goblins.append(goblin);
        k += 1;
    }
    let mut member = *words.members[0];
    if health > 480 {
        member.state += (health - 480).into() * two(64);
        member.stats += (health - 480).into();
    }
    Words { goblins, members: array![member], ..words }
}

fn lever_actions() -> Span<Action> {
    let mut actions = array![];
    let mut k: u8 = 0;
    while k < 10 {
        actions.append(Action::Attack(12 + (k / 3).into()));
        k += 1;
    }
    actions.span()
}

#[test]
#[available_gas(l2_gas: 19695201)] // ceil(1.05 × 18757334 measured)
fn test_cost_lever_fixture() {
    segment_fixture(lever_words(480), lever_actions());
}

#[test]
#[available_gas(l2_gas: 19784472)] // ceil(1.05 × 18842354 measured)
fn test_cost_lever_fixture_whole() {
    segment_fixture(lever_words(20000), lever_actions());
}

#[test]
#[available_gas(l2_gas: 284662893)] // ceil(1.05 × 271107517 measured)
fn test_cost_lever_batch_real() {
    let (out, done) = segment_of(lever_words(480), lever_actions());
    println!(
        "lever real: played {} clock {} defeated {} killed {} illegal {:?}",
        done.played,
        out.clock,
        out.defeated,
        out.killed.len(),
        done.illegal,
    );
    assert(done.played > 0, 'played');
}

#[test]
#[available_gas(l2_gas: 403496105)] // ceil(1.05 × 384282004 measured)
fn test_cost_lever_batch_whole() {
    let (out, done) = segment_of(lever_words(20000), lever_actions());
    println!(
        "lever whole: played {} clock {} defeated {} killed {} illegal {:?}",
        done.played,
        out.clock,
        out.defeated,
        out.killed.len(),
        done.illegal,
    );
    assert(done.played > 0, 'played');
}

// The tick alone: one tick through `TickLibrary`, the 4 goblins attacking, no action of the member.
#[test]
#[available_gas(l2_gas: 19111779)] // ceil(1.05 × 18201694 measured)
fn test_cost_lever_tick_fixture() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let _ = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _ = classes();
    let words = lever_words(480);
    let content = rep_content();
    assert(opaque(words.goblins.len()) == 8 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 46814765)] // ceil(1.05 × 44585490 measured)
fn test_cost_lever_tick() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let words = ticks_of(library, lever_words(480), rep_content(), board(), 1);
    assert(words.clock == 41, 'one tick');
}

// The same tick with the 8 attacking (the uncapped fight's), for the pair.
#[test]
#[available_gas(l2_gas: 18931515)] // ceil(1.05 × 18030014 measured)
fn test_cost_lever_tick_uncapped_fixture() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let _ = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let _ = classes();
    let (words, _) = fight();
    let content = rep_content();
    assert(opaque(words.goblins.len()) == 8 && content.skills.len() == 38, 'fixture');
}

#[test]
#[available_gas(l2_gas: 63588647)] // ceil(1.05 × 60560616 measured)
fn test_cost_lever_tick_uncapped() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, _) = fight();
    let words = ticks_of(library, words, rep_content(), board(), 1);
    assert(words.clock == 41, 'one tick');
}

// The attackers' cap (`MAX_ATTACKERS`, CBT-05d's lever 1): the 8 Engaged goblins of the fight, each
// able to attack with its weapon, make as many attacks as the cap allows and never more; with the
// constant (8, no cap until the owner sets it, R-2) all 8 attack.
fn cap_step(cap: u8) -> u8 {
    let (words, _) = fight();
    let content = rep_content();
    let classes = classes();
    let (mut world, sheets, index) = words.indexed(@content);
    world.clock += 1;
    let mut rules = grimworld_logic::types::executor::Delegate {
        board: board(),
        cache: Default::default(),
        executor: classes.executor,
        content,
        index,
        placed: array![],
        ground: array![],
        ai: classes.ai,
        trap: classes.trap,
        level: 10,
        frozen: 0,
        listed: 0,
    };
    let (_, attacks) = grimworld_logic::types::ai::AiTrait::capped(
        ref world, @sheets, ref rules, 0, cap,
    );
    attacks
}

#[test]
#[available_gas(l2_gas: 123735656)] // ceil(1.05 × 117843481 measured)
fn test_attackers_cap() {
    assert(cap_step(4) == 4, 'four attack');
    assert(cap_step(1) == 1, 'one attacks');
    let all = cap_step(grimworld_logic::types::ai::MAX_ATTACKERS);
    assert(all <= grimworld_logic::types::ai::MAX_ATTACKERS && all == 8, 'eight attack');
}

// The window of the segment (ADR-0006 §4): the adventurer at (16, 16), on chunks every one
// walkable, stands on local (7, 8) (an even row) and its six neighbours are open.
#[test]
#[available_gas(l2_gas: 11950292)] // ceil(1.05 × 11381230 measured)
fn test_segment_window_open() {
    let mut member = member_at(400);
    member.words.state += 0; // placed below
    let mut spec = Fixture::spec();
    spec.health = 400;
    let mut m = Fixture::member(spec);
    m.words.state += 16 * two(32) + 16 * two(40);
    let world = Fixture::world(40, array![m], array![]);
    let area = open_area();
    let board = grimworld_logic::types::play::SegmentTrait::board(@area, @world);
    let (x, y, _) = grimworld_logic::models::member::MemberSnapshotTrait::place(@world.member(0));
    let at = board.position(x, y);
    println!("board x {} y {} at {} open {}", board.x, board.y, at, board.window.open());
    assert(at == 15 * 8 + 7, 'local (7, 8)');
    let mut d: u8 = 0;
    while d < 6 {
        let to = hexx::board::layout::LayoutTrait::neighbor(
            15, 16, at, grimworld_logic::types::window::WindowAssert::direction(d),
        )
            .unwrap();
        assert(board.window.near(shape::SINGLE, to) != 0, 'neighbour open');
        d += 1;
    }
}

// D-236 #3: the batch's call to `SegmentLibrary`, with the whole words, against the same segment in
// process (`segment_of`): the exploration batch and the whole fight batch, each less its fixture.
fn segment_call(
    words: Words, actions: Span<Action>,
) -> (Words, grimworld_logic::types::play::Done) {
    let class = declare("SegmentLibrary").unwrap().contract_class();
    let library = grimworld_logic::interface::ISegmentLibraryLibraryDispatcher {
        class_hash: *class.class_hash,
    };
    let (out, _, done) = grimworld_logic::interface::ISegmentLibraryDispatcherTrait::segment(
        library, words, rep_content(), open_area(), classes(), 10, array![], actions, 0, 10,
    );
    (out, done)
}

#[test]
#[available_gas(l2_gas: 6504068)] // ceil(1.05 × 6194350 measured)
fn test_cost_segment_call_exploration_fixture() {
    let _ = declare("SegmentLibrary").unwrap().contract_class();
    let (words, actions) = exploration();
    segment_fixture(words, actions);
}

#[test]
#[available_gas(l2_gas: 18986304)] // ceil(1.05 × 18082194 measured)
fn test_cost_segment_call_exploration() {
    let (words, actions) = exploration();
    let (out, done) = segment_call(words, actions);
    assert(done.played == 10 && out.clock == 50, 'ten moves');
}

#[test]
#[available_gas(l2_gas: 19576299)] // ceil(1.05 × 18644094 measured)
fn test_cost_segment_call_fight_fixture() {
    let _ = declare("SegmentLibrary").unwrap().contract_class();
    let (words, actions) = fight_whole();
    segment_fixture(words, actions);
}

#[test]
#[available_gas(l2_gas: 529038582)] // ceil(1.05 × 503846268 measured)
fn test_cost_segment_call_fight() {
    let (words, actions) = fight_whole();
    let (out, done) = segment_call(words, actions);
    assert(done.played == 10 && out.clock == 50, 'ten attacks');
}

// t-0109, minor 2: a Turn refused for weight writes nothing. Ten Waits spend the weight, then a
// Turn: the segment stops for weight, 10 played, the member's facing unchanged.
#[test]
fn test_segment_turn_heavy() {
    let (words, _) = exploration();
    let before: u256 = (*words.members[0]).state.into();
    let mut actions = array![];
    let mut k: u8 = 0;
    while k < 10 {
        actions.append(Action::Wait);
        k += 1;
    }
    actions.append(Action::Turn(4));
    let (out, done) = segment_of(words, actions.span());
    assert(done.heavy && done.played == 10 && done.weight == 0, 'stopped for weight');
    // The facing, `MemberState` 48–55.
    let after: u256 = (*out.members[0]).state.into();
    let facing = |state: u256| (state.low / 0x1000000000000) % 0x100;
    assert(facing(after) == facing(before), 'facing unchanged');
}

// D-238 (the project manager, 2026-10-09): with 60 goblins away from their spawn chunk, a goblin
// whose step would leave its spawn chunk does not leave it (its act is a Wait); with 59 it steps.
// The board's origin at the location's (0, 8): chunk 0's last row is the window's row 6. The
// goblin, chunk 0's (entity 8), Engaged on (7, 14), the member on (7, 17): its step toward the
// member enters chunk 15. The 60 (or 59) others, of chunks 1 to 6, stand far outside the window,
// away from theirs. A 2-tick run equals two 1-tick runs (a batch and its singles).
fn roster_world(away: u16) -> (World, Sheets) {
    let mut member = member_at(400);
    member.words.state = member.words.state - place(AT) * two(32) + (7 + 17 * 256) * two(32);
    let mut goblins = array![];
    let mut first = Fixture::goblin(8, HOB);
    // Its skills recharging until tick 100: its act is a step.
    first.state += 7 + 14 * two(8) + 100 * (two(128) + two(156) + two(184) + two(212));
    goblins.append(first);
    let mut n: u16 = 0;
    while n < away {
        let mut goblin = Fixture::goblin(8 + 16 * (1 + n / 10) + n % 10, HOB);
        goblin.awake = false;
        goblin.state += 100 + 100 * two(8);
        goblins.append(goblin);
        n += 1;
    }
    let world = Fixture::world(40, array![member], goblins);
    (world, Fixture::sheets())
}

fn roster_run(away: u16, splits: u8) -> Words {
    let (mut world, sheets) = roster_world(away);
    let board = BoardTrait::new(
        WindowTrait::new(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff), 0, 8,
    );
    if splits == 1 {
        let mut rules = ExecutorTrait::new(board);
        TickTrait::run(ref world, @sheets, 2, ref rules);
        return world.store();
    }
    let mut rules = ExecutorTrait::new(board);
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    let (mut world, sheets) = words.load(@Fixture::content());
    let mut rules = ExecutorTrait::new(board);
    TickTrait::run(ref world, @sheets, 1, ref rules);
    world.store()
}

fn first_place(words: @Words) -> (u8, u8) {
    let state: u256 = (*words.goblins[0].state).into();
    ((state.low % 256).try_into().unwrap(), ((state.low / 256) % 256).try_into().unwrap())
}

#[test]
fn test_roster_full_holds() {
    let full = roster_run(60, 1);
    let (x, y) = first_place(@full);
    assert(y == 14 && x == 7, 'held in its chunk');
    assert(full == roster_run(60, 2), 'batch = singles');
}

#[test]
fn test_roster_free_steps() {
    let free = roster_run(59, 1);
    let (_, y) = first_place(@free);
    assert(y >= 15, 'left its chunk');
    assert(free == roster_run(59, 2), 'batch = singles');
}

// D-238: how often the representative fight reaches 60 (expected never): its 8 goblins away from
// their spawn chunk at the batch's end.
#[test]
fn test_fight_roster_count() {
    let (words, actions) = fight_whole();
    let (out, _) = segment_of(words, actions);
    let mut away: u32 = 0;
    for goblin in out.goblins.span() {
        let state: u256 = (*goblin.state).into();
        let x: u32 = (state.low % 256).try_into().unwrap();
        let y: u32 = ((state.low / 256) % 256).try_into().unwrap();
        let spawn: u32 = ((*goblin.entity).into() - 8) / 16;
        if (y / 15) * 15 + x / 15 != spawn {
            away += 1;
        }
    }
    println!("fight: goblins away from their spawn chunk {}", away);
    assert(away < 60, 'never 60');
}

