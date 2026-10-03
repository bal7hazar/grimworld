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
use grimworld_logic::content::Record;
use grimworld_logic::helpers::signed::SignedTrait;
use grimworld_logic::interface::{ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher};
use grimworld_logic::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::goblin::{Goblin, GoblinTickTrait, GoblinTrait, GoblinWords};
use grimworld_logic::models::index::{Caste, Skill};
use grimworld_logic::models::member::{Member, MemberTickTrait, MemberTrait, MemberWords};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::types::MAX_CLOCK;
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 62684444)] // ceil(1.05 × 59699470 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14355002)] // ceil(1.05 × 13671430 measured)
fn test_cost_fixture_worst() {
    let (world, content) = worst_state(true, 3);
    assert(world.goblin_count() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14356787)] // ceil(1.05 × 13673130 measured)
fn test_cost_fixture_worst_batch() {
    let (world, content) = worst_state(false, 1);
    assert(world.goblin_count() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 16623117)] // ceil(1.05 × 15831540 measured)
fn test_cost_fixture_worst_words() {
    let (words, content) = worst_words();
    assert(words.goblins.len() == 100 && content.skills.len() == 38, 'worst');
}

#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 7751226)] // ceil(1.05 × 7382120 measured)
fn test_cost_fixture_representative() {
    let (world, content) = representative();
    assert(world.goblin_count() == 8 && content.castes.len() == 2, 'representative');
}

// Cost: one representative tick, the pipeline alone (Idle rules).
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 8488701)] // ceil(1.05 × 8084477 measured)
fn test_cost_tick_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.clock == 50, 'one tick');
}

// Cost: a batch's 10 representative ticks, the pipeline alone: a trace, not a bound.
#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 15171828)] // ceil(1.05 × 14449360 measured)
fn test_cost_batch_representative() {
    let (mut world, content) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @content, 10, ref rules);
    assert(world.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 7997126)] // ceil(1.05 × 7616310 measured)
fn test_cost_fixture_representative_words() {
    let (world, content) = representative();
    let words = world.store();
    assert(words.goblins.len() == 8 && content.castes.len() == 2, 'representative');
}

// A batch's 10 representative ticks through one library call: load, ticks, store, the call.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19303095)] // ceil(1.05 × 18383900 measured)
fn test_cost_library_call_batch_representative() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = representative();
    let words = library.run(world.store(), content_of(@content), board(), executor(), 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 8007531)] // ceil(1.05 × 7626220 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15991220)] // ceil(1.05 × 15229733 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 7037993)] // ceil(1.05 × 6702850 measured)
fn test_cost_fixture_worst_8() {
    let (world, _) = worst_of(true, 3, 8);
    assert(world.goblin_count() == 8, 'eight');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 8574241)] // ceil(1.05 × 8165943 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 31580756)] // ceil(1.05 × 30076910 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 44550860)] // ceil(1.05 × 42429390 measured)
fn test_cost_load_store_worst() {
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let (world, _) = words.load(@content);
    let words = world.store();
    assert(words == expected, 'the round trip keeps every word');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 33241604)] // ceil(1.05 × 31658670 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 12964182)] // ceil(1.05 × 12346840 measured)
fn test_cost_awake_100() {
    let (mut world, distances) = candidates();
    TickTrait::awake(ref world, distances);
    assert(world.goblin(92).awake && !world.goblin(91).awake, 'the 8 nearest');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 8205624)] // ceil(1.05 × 7814880 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 13496291)] // ceil(1.05 × 12853610 measured)
fn test_cost_awake_none() {
    awake_tick(array![].span(), 0, at_end(8));
}

// The prior set at the array's end, kept.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15249990)] // ceil(1.05 × 14523800 measured)
fn test_cost_awake_end_kept() {
    awake_tick(at_end(8), 0, at_end(8));
}

// The prior set at the array's start, replaced by the last 8.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15249066)] // ceil(1.05 × 14522920 measured)
fn test_cost_awake_start_replaced() {
    awake_tick(at_start(8), 0, at_end(8));
}

// The prior set spread across the array, replaced by the last 8.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15232067)] // ceil(1.05 × 14506730 measured)
fn test_cost_awake_spread_replaced() {
    awake_tick(at_spread(), 0, at_end(8));
}

// The prior set at the array's start, kept (the distances rising).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15197123)] // ceil(1.05 × 14473450 measured)
fn test_cost_awake_start_kept() {
    awake_tick(at_start(8), 1, at_start(8));
}

// The prior set at the array's end, replaced by the first 8 (the distances rising).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15196199)] // ceil(1.05 × 14472570 measured)
fn test_cost_awake_end_replaced() {
    awake_tick(at_end(8), 1, at_start(8));
}

// The prior set spread across the array, kept (nearest).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15227730)] // ceil(1.05 × 14502600 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 18520226)] // ceil(1.05 × 17638310 measured)
fn test_cost_pair_term_fixture() {
    let (_world, _sheets) = term_world(seven_then(C, L), at_end(8), false, 1, 1);
}

// The same, and its tick with the bound's rules.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20098740)] // ceil(1.05 × 19141657 measured)
fn test_cost_pair_term_tick() {
    let (mut world, sheets) = term_world(seven_then(C, L), at_end(8), false, 1, 1);
    let mut rules: Acts = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The state of 8 activating goblins, its fixture alone.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 18521664)] // ceil(1.05 × 17639680 measured)
fn test_cost_pair_activating_fixture() {
    let (_world, _sheets) = term_world(all_of(A, 8), at_end(8), false, 1, 1);
}

// The same, and its tick with the bound's rules.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19342841)] // ceil(1.05 × 18421753 measured)
fn test_cost_pair_activating_tick() {
    let (mut world, sheets) = term_world(all_of(A, 8), at_end(8), false, 1, 1);
    let mut rules: Acts = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The representative state, its fixture alone.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 7750176)] // ceil(1.05 × 7381120 measured)
fn test_cost_pair_representative_fixture() {
    let (_world, _sheets) = representative();
}

// The same, and one tick with the lot's rules.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 8487021)] // ceil(1.05 × 8082877 measured)
fn test_cost_pair_representative_tick() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The same, and one tick through `run`.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 8498613)] // ceil(1.05 × 8093917 measured)
fn test_cost_pair_representative_run_one() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
}

// The same, and ten ticks through `run`.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15170148)] // ceil(1.05 × 14447760 measured)
fn test_cost_pair_representative_run_ten() {
    let (mut world, sheets) = representative();
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 10, ref rules);
}

// The awake selection's straight-line part, the same way: the costliest prior set (at the array's
// start, kept) and none.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 10271888)] // ceil(1.05 × 9782750 measured)
fn test_cost_pair_awake_start_kept_fixture() {
    let (_world, _distances) = awake_state(at_start(8), 1);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15067301)] // ceil(1.05 × 14349810 measured)
fn test_cost_pair_awake_start_kept() {
    let (mut world, distances) = awake_state(at_start(8), 1);
    TickTrait::awake(ref world, distances);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 8641973)] // ceil(1.05 × 8230450 measured)
fn test_cost_pair_awake_none_fixture() {
    let (_world, _distances) = awake_state(array![].span(), 0);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 13365629)] // ceil(1.05 × 12729170 measured)
fn test_cost_pair_awake_none() {
    let (mut world, distances) = awake_state(array![].span(), 0);
    TickTrait::awake(ref world, distances);
}

// `Busy`'s first tick (8 conclusions and the member's), for `tick<Busy>`'s straight-line part.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14354162)] // ceil(1.05 × 13670630 measured)
fn test_cost_pair_busy_fixture() {
    let (_world, _sheets) = worst_state(false, 1);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15922932)] // ceil(1.05 × 15164697 measured)
fn test_cost_pair_busy_tick() {
    let (mut world, sheets) = worst_state(false, 1);
    let mut rules: Busy = Default::default();
    TickTrait::tick(ref world, @sheets, ref rules);
}

// The ten ticks of the run above, each measured alone ("gas representative tick").
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 16110570)] // ceil(1.05 × 15343400 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 29089267)] // ceil(1.05 × 27704063 measured)
fn test_cost_library_baseline() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (words, content) = worst_words();
    let (mut world, sheets) = words.load(@content);
    let mut rules = Idle {};
    TickTrait::run(ref world, @sheets, 1, ref rules);
    let words = world.store();
    assert(words.clock == 50, 'one tick');
}

// A fixture artefact, not the tick's cost (CBT-05a, route (c)): every goblin of this fixture
// stands on one tile, so each carrier's call to ExecutorLibrary carries them all. The tick's
// cost is ENG-01 §9.2's line (26,422,703 a worst tick).
#[test]
// gas: raised, CBT-05a, route (c): each call carries every goblin (a fixture artefact)
#[available_gas(l2_gas: 835954852)] // ceil(1.05 × 796147478 measured)
fn test_cost_library_call() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let words = library.run(words, content, board(), executor(), 1);
    assert(words.clock == 50, 'one tick');
}

// Ten ticks through one library call over the busy state: the class runs its own rules (`Idle`
// until CBT-05 and ENG-07), so after the opening tick the goblins fall quiet. A trace of the call
// at the array's bound, not a bound (the tick's is CBT-02b's, below).
// A fixture artefact, not the tick's cost (CBT-05a, route (c)): every goblin of this fixture
// stands on one tile, so each carrier's call to ExecutorLibrary carries them all. The tick's
// cost is ENG-01 §9.2's line (26,422,703 a worst tick).
#[test]
// gas: raised, CBT-05a, route (c): each call carries every goblin (a fixture artefact)
#[available_gas(l2_gas: 844148703)] // ceil(1.05 × 803951145 measured)
fn test_cost_library_call_batch() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (world, content) = worst_state(false, 1);
    let words = library.run(world.store(), content_of(@content), board(), executor(), 10);
    assert(words.clock == 59, 'ten ticks');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 16631423)] // ceil(1.05 × 15839450 measured)
fn test_cost_library_baseline_batch() {
    let _class = declare("TickLibrary").unwrap().contract_class();
    let (world, _content) = worst_state(false, 1);
    let words = world.store();
    assert(words.clock == 49, 'declared');
}

// The library call runs the pipeline: the same words as a direct run.
// A fixture artefact, not the tick's cost (CBT-05a, route (c)): every goblin of this fixture
// stands on one tile, so each carrier's call to ExecutorLibrary carries them all. The tick's
// cost is ENG-01 §9.2's line (26,422,703 a worst tick).
#[test]
// gas: raised, CBT-05a, route (c): each call carries every goblin (a fixture artefact)
#[available_gas(l2_gas: 875616563)] // ceil(1.05 × 833920536 measured)
fn test_library_matches_pipeline() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words();
    let (expected, _) = worst_words();
    let words = library.run(words, content, board(), executor(), 3);
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 431298)] // ceil(1.05 × 410760 measured)
fn test_cost_sheets() {
    let (skill, caste) = records();
    let sheet = SkillSheetTrait::read(5, skill);
    let caste_sheet = CasteSheetTrait::read(1, caste);
    assert(sheet.recharge == 12 && sheet.regen(12) == 6, 'skill sheet');
    assert(caste_sheet.weapon_ticks == 2 && caste_sheet.max_health(20) == 720, 'caste sheet');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 757512)] // ceil(1.05 × 721440 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 76444919)] // ceil(1.05 × 72804684 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15699219)] // ceil(1.05 × 14951637 measured)
fn test_cost_bound_eight_lapses() {
    let (mut world, content) = branch_world_n(B_LAPSE, true, true, 8);
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8, 'eight deaths');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14395626)] // ceil(1.05 × 13710120 measured)
fn test_cost_bound_eight_lapses_fixture() {
    let (world, content) = branch_world_n(B_LAPSE, true, true, 8);
    assert(world.clock == 49 && content.skills.len() == 38, 'fixture');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14608948)] // ceil(1.05 × 13913283 measured)
fn test_cost_bound_base() {
    branch_tick(B_NONE, false, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14370584)] // ceil(1.05 × 13686270 measured)
fn test_cost_bound_base_fixture() {
    branch_fixture(B_NONE, false, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14587055)] // ceil(1.05 × 13892433 measured)
fn test_cost_bound_base_member_alive() {
    branch_tick(B_NONE, false, false);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14370689)] // ceil(1.05 × 13686370 measured)
fn test_cost_bound_base_member_alive_fixture() {
    branch_fixture(B_NONE, false, false);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14733614)] // ceil(1.05 × 14032013 measured)
fn test_cost_bound_conclude_recover() {
    branch_tick(B_CONCLUDE_RECOVER, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14373965)] // ceil(1.05 × 13689490 measured)
fn test_cost_bound_conclude_recover_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14733509)] // ceil(1.05 × 14031913 measured)
fn test_cost_bound_conclude_recover_alive() {
    branch_tick(B_CONCLUDE_RECOVER, false, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14374070)] // ceil(1.05 × 13689590 measured)
fn test_cost_bound_conclude_recover_alive_fixture() {
    branch_fixture(B_CONCLUDE_RECOVER, false, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14735623)] // ceil(1.05 × 14033926 measured)
fn test_cost_bound_conclude_clear() {
    branch_tick(B_CONCLUDE_CLEAR, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14374269)] // ceil(1.05 × 13689780 measured)
fn test_cost_bound_conclude_clear_fixture() {
    branch_fixture(B_CONCLUDE_CLEAR, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14755132)] // ceil(1.05 × 14052506 measured)
fn test_cost_bound_lapse() {
    branch_tick(B_LAPSE, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14374973)] // ceil(1.05 × 13690450 measured)
fn test_cost_bound_lapse_fixture() {
    branch_fixture(B_LAPSE, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14714245)] // ceil(1.05 × 14013566 measured)
fn test_cost_bound_recovery_end() {
    branch_tick(B_RECOVERY_END, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14375676)] // ceil(1.05 × 13691120 measured)
fn test_cost_bound_recovery_end_fixture() {
    branch_fixture(B_RECOVERY_END, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14688527)] // ceil(1.05 × 13989073 measured)
fn test_cost_bound_activating() {
    branch_tick(B_ACTIVATING, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14376275)] // ceil(1.05 × 13691690 measured)
fn test_cost_bound_activating_fixture() {
    branch_fixture(B_ACTIVATING, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14692825)] // ceil(1.05 × 13993166 measured)
fn test_cost_bound_free() {
    branch_tick(B_FREE, true, true);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 14376380)] // ceil(1.05 × 13691790 measured)
fn test_cost_bound_free_fixture() {
    branch_fixture(B_FREE, true, true);
}


// CBT-02d: a read through the index costs the same wherever the record lies: the first skill and
// the last, the first caste and the last, in the same content. The fixture builds the index.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 1356999)] // ceil(1.05 × 1292380 measured)
fn test_cost_index_skill_first() {
    let (_, mut index) = branch_content(3).index();
    assert(index.skill(1) == 0, 'first');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 1357209)] // ceil(1.05 × 1292580 measured)
fn test_cost_index_skill_last() {
    let (_, mut index) = branch_content(3).index();
    assert(index.skill(43) == 37, 'last');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 1356999)] // ceil(1.05 × 1292380 measured)
fn test_cost_index_caste_first() {
    let (_, mut index) = branch_content(3).index();
    assert(index.caste(1) == 0, 'first');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 1357209)] // ceil(1.05 × 1292580 measured)
fn test_cost_index_caste_last() {
    let (_, mut index) = branch_content(3).index();
    assert(index.caste(5) == 4, 'last');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 1356884)] // ceil(1.05 × 1292270 measured)
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
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 6525330)] // ceil(1.05 × 6214600 measured)
fn test_cost_load_member_skills() {
    let (sheets, mut index) = branch_content(3).index();
    let words = member_effect_words(false);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, ref index, @sheets);
    assert(member.max_health == 480, 'loaded');
}

#[test]
// gas: raised, the fixture builds the content's index before the load (CBT-02d)
#[available_gas(l2_gas: 6516615)] // ceil(1.05 × 6206300 measured)
fn test_cost_load_member_potions() {
    let (sheets, mut index) = branch_content(3).index();
    let words = member_effect_words(true);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
    let member = MemberTrait::load(words, ref index, @sheets);
    assert(member.max_health == 480, 'loaded');
}

#[test]
// gas: raised, the fixture builds the content's index (CBT-02d)
#[available_gas(l2_gas: 6218363)] // ceil(1.05 × 5922250 measured)
fn test_cost_load_member_skills_fixture() {
    let (sheets, _) = branch_content(3).index();
    let words = member_effect_words(false);
    assert(words.state != 0 && sheets.skills.len() == 38, 'fixture');
}

#[test]
// gas: raised, the fixture builds the content's index (CBT-02d)
#[available_gas(l2_gas: 6217628)] // ceil(1.05 × 5921550 measured)
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
#[available_gas(l2_gas: 17528399)] // ceil(1.05 × 16693713 measured)
fn test_cost_tick_worst_permuted() {
    let (mut world, sheets) = worst_state(true, 3);
    let content = permuted(content_of(@sheets)).sheets();
    let mut rules = Idle {};
    TickTrait::tick(ref world, @content, ref rules);
    assert(world.killed.len() == 8 && world.defeated, 'every death');
}

#[test]
#[available_gas(l2_gas: 15993831)] // ceil(1.05 × 15232220 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_below() {
    assert(regenerate_goblin(99, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_below_dead() {
    assert(regenerate_goblin(99, 2, 99, 0, 15, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in −10…−1.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_down() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to 0.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_down_dead() {
    assert(regenerate_goblin(99, 2, 99, 5, 10, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips in 0…10.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_up() {
    assert(regenerate_goblin(0, 2, 99, 0, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_up_full() {
    assert(regenerate_goblin(0, 2, 99, 0, 278, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the pips above 10 (clamped).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_above() {
    assert(regenerate_goblin(0, 10, 99, 10, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, the same, health to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_above_full() {
    assert(regenerate_goblin(0, 10, 99, 10, 270, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no effect pips.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_effect_zero() {
    assert(regenerate_goblin(99, 0, 99, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, an effect over.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_effect_over() {
    assert(regenerate_goblin(99, 2, 40, 7, 100, 0, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, energy to its max.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_energy_capped() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 30, ai::ALERTED, 5) <= 280, 'health');
}

// A goblin's step 3, no adrenaline to decay.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
fn test_cost_path_goblin_adrenaline_zero() {
    assert(regenerate_goblin(99, 2, 99, 5, 100, 0, ai::ALERTED, 0) <= 280, 'health');
}

// A goblin's step 3, Engaged: no decay.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 715092)] // ceil(1.05 × 681040 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15040487)] // ceil(1.05 × 14324273 measured)
fn test_cost_term_none() {
    term_tick(array![].span(), array![].span(), false, 1, 1);
}

// The same with the content of a conclusion into a recovery: `k` changes nothing else.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15040487)] // ceil(1.05 × 14324273 measured)
fn test_cost_term_none_k3() {
    term_tick(array![].span(), array![].span(), false, 3, 1);
}

// The base with two members (M-3): what the second member adds.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15234688)] // ceil(1.05 × 14509226 measured)
fn test_cost_term_none_two_members() {
    term_tick(array![].span(), array![].span(), false, 1, 2);
}

// CBT-02d fix loop 1 (COST-3): the base with four and eight members (M-3 allows 8). Each member's
// conclusion rebuilds the members' array, so a member adds more the more there are.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15675820)] // ceil(1.05 × 14929352 measured)
fn test_cost_term_none_four_members() {
    term_tick(array![].span(), array![].span(), false, 1, 4);
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 16776002)] // ceil(1.05 × 15977144 measured)
fn test_cost_term_none_eight_members() {
    term_tick(array![].span(), array![].span(), false, 1, 8);
}

// One goblin: concluding into a recovery.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15674561)] // ceil(1.05 × 14928153 measured)
fn test_cost_term_one_conclude_recover() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 1), at_end(1), false, 3, 1);
}

// Eight goblins: concluding into a recovery.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20461112)] // ceil(1.05 × 19486773 measured)
fn test_cost_term_eight_conclude_recover() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 8), at_end(8), false, 3, 1);
}

// One goblin: concluding, the field cleared.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15676570)] // ceil(1.05 × 14930066 measured)
fn test_cost_term_one_conclude_clear() {
    term_tick(all_of(B_CONCLUDE_CLEAR, 1), at_end(1), false, 1, 1);
}

// Eight goblins: concluding, the field cleared.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20477181)] // ceil(1.05 × 19502077 measured)
fn test_cost_term_eight_conclude_clear() {
    term_tick(all_of(B_CONCLUDE_CLEAR, 8), at_end(8), false, 1, 1);
}

// One goblin: a lapse.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15696940)] // ceil(1.05 × 14949466 measured)
fn test_cost_term_one_lapse() {
    term_tick(all_of(B_LAPSE, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a lapse.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20243829)] // ceil(1.05 × 19279837 measured)
fn test_cost_term_eight_lapse() {
    term_tick(all_of(B_LAPSE, 8), at_end(8), false, 1, 1);
}

// One goblin: a lapse, the later recharge kept.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15697339)] // ceil(1.05 × 14949846 measured)
fn test_cost_term_one_lapse_keep() {
    term_tick(all_of(B_LAPSE_KEEP, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a lapse, the later recharge kept.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20247021)] // ceil(1.05 × 19282877 measured)
fn test_cost_term_eight_lapse_keep() {
    term_tick(all_of(B_LAPSE_KEEP, 8), at_end(8), false, 1, 1);
}

// One goblin: a recovery over.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15656032)] // ceil(1.05 × 14910506 measured)
fn test_cost_term_one_recovery_end() {
    term_tick(all_of(B_RECOVERY_END, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a recovery over.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19909572)] // ceil(1.05 × 18961497 measured)
fn test_cost_term_eight_recovery_end() {
    term_tick(all_of(B_RECOVERY_END, 8), at_end(8), false, 1, 1);
}

// One goblin: activating, busy.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15628067)] // ceil(1.05 × 14883873 measured)
fn test_cost_term_one_activating() {
    term_tick(all_of(B_ACTIVATING, 1), at_end(1), false, 1, 1);
}

// Eight goblins: activating, busy.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19733777)] // ceil(1.05 × 18794073 measured)
fn test_cost_term_eight_activating() {
    term_tick(all_of(B_ACTIVATING, 8), at_end(8), false, 1, 1);
}

// One goblin: a recovery running on.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15628477)] // ceil(1.05 × 14884263 measured)
fn test_cost_term_one_recovering() {
    term_tick(all_of(B_RECOVERING, 1), at_end(1), false, 1, 1);
}

// Eight goblins: a recovery running on.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19737053)] // ceil(1.05 × 18797193 measured)
fn test_cost_term_eight_recovering() {
    term_tick(all_of(B_RECOVERING, 8), at_end(8), false, 1, 1);
}

// One goblin: free, acting in step 2.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15633310)] // ceil(1.05 × 14888866 measured)
fn test_cost_term_one_free() {
    term_tick(all_of(B_FREE, 1), at_end(1), false, 1, 1);
}

// Eight goblins: free, acting in step 2.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19775718)] // ceil(1.05 × 18834017 measured)
fn test_cost_term_eight_free() {
    term_tick(all_of(B_FREE, 8), at_end(8), false, 1, 1);
}

// One goblin: free but knocked down.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15628676)] // ceil(1.05 × 14884453 measured)
fn test_cost_term_one_knocked() {
    term_tick(all_of(B_KNOCKED, 1), at_end(1), false, 1, 1);
}

// Eight goblins: free but knocked down.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19738649)] // ceil(1.05 × 18798713 measured)
fn test_cost_term_eight_knocked() {
    term_tick(all_of(B_KNOCKED, 8), at_end(8), false, 1, 1);
}

// One goblin: awake and already dead.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15601649)] // ceil(1.05 × 14858713 measured)
fn test_cost_term_one_dead() {
    term_tick(all_of(B_DEAD, 1), at_end(1), false, 1, 1);
}

// Eight goblins: awake and already dead.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19522433)] // ceil(1.05 × 18592793 measured)
fn test_cost_term_eight_dead() {
    term_tick(all_of(B_DEAD, 8), at_end(8), false, 1, 1);
}

// One goblin concluding into a recovery, surviving step 3.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 15674855)] // ceil(1.05 × 14928433 measured)
fn test_cost_term_one_conclude_recover_surviving() {
    term_tick(all_of(B_CONCLUDE_RECOVER, 1), at_end(1), true, 3, 1);
}

// The costliest mix: 7 conclusions, then a lapse whose write the end of step 1 rebuilds.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20493131)] // ceil(1.05 × 19517267 measured)
fn test_cost_term_mix_clear_lapse() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_end(8), false, 1, 1);
}

// The same, the awake goblins at the array's start.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20491692)] // ceil(1.05 × 19515897 measured)
fn test_cost_term_mix_clear_lapse_start() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_start(8), false, 1, 1);
}

// The same, the awake goblins spread across the array.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20475921)] // ceil(1.05 × 19500877 measured)
fn test_cost_term_mix_clear_lapse_spread() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_LAPSE), at_spread(), false, 1, 1);
}

// Swap: 7 conclusions, then an activating goblin.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20383319)] // ceil(1.05 × 19412684 measured)
fn test_cost_term_mix_clear_activating() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_ACTIVATING), at_end(8), false, 1, 1);
}

// Swap: 7 conclusions, then a recovery over.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20452223)] // ceil(1.05 × 19478307 measured)
fn test_cost_term_mix_clear_recovery_end() {
    term_tick(seven_then(B_CONCLUDE_CLEAR, B_RECOVERY_END), at_end(8), false, 1, 1);
}

// Swap: 7 activating goblins, then a lapse.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19842151)] // ceil(1.05 × 18897286 measured)
fn test_cost_term_mix_activating_lapse() {
    term_tick(seven_then(B_ACTIVATING, B_LAPSE), at_end(8), false, 1, 1);
}

// A lapse first, then 7 conclusions: its write goes with the first conclusion's rebuild.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20441334)] // ceil(1.05 × 19467937 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19807984)] // ceil(1.05 × 18864746 measured)
fn test_cost_term_set_c_first() {
    term_mix(array![C, A, A, A, A, A, A, A]);
}

// A conclusion in the middle of the set.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19810966)] // ceil(1.05 × 18867586 measured)
fn test_cost_term_set_c_middle() {
    term_mix(array![A, A, A, C, A, A, A, A]);
}

// A conclusion last in the set.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19810966)] // ceil(1.05 × 18867586 measured)
fn test_cost_term_set_c_last() {
    term_mix(array![A, A, A, A, A, A, A, C]);
}

// An activating goblin first, 7 conclusions after it.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20372504)] // ceil(1.05 × 19402384 measured)
fn test_cost_term_set_a_then_c() {
    term_mix(array![A, C, C, C, C, C, C, C]);
}

// Two conclusions, then activating goblins.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19900408)] // ceil(1.05 × 18952769 measured)
fn test_cost_term_set_cc_first() {
    term_mix(array![C, C, A, A, A, A, A, A]);
}

// Six conclusions, then two lapses (two writes left for the end of step 1).
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20443088)] // ceil(1.05 × 19469607 measured)
fn test_cost_term_set_c6_ll() {
    term_mix(array![C, C, C, C, C, C, L, L]);
}

// Six conclusions, an activating goblin, a lapse.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20386910)] // ceil(1.05 × 19416104 measured)
fn test_cost_term_set_c6_al() {
    term_mix(array![C, C, C, C, C, C, A, L]);
}

// Six conclusions, a lapse, an activating goblin.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20386910)] // ceil(1.05 × 19416104 measured)
fn test_cost_term_set_c6_la() {
    term_mix(array![C, C, C, C, C, C, L, A]);
}

// Six conclusions, a recovery over, a lapse.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20402180)] // ceil(1.05 × 19430647 measured)
fn test_cost_term_set_c6_rl() {
    term_mix(array![C, C, C, C, C, C, R, L]);
}

// A lapse between two conclusions: its write goes with the next conclusion's.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20438352)] // ceil(1.05 × 19465097 measured)
fn test_cost_term_set_c_l_c6() {
    term_mix(array![C, L, C, C, C, C, C, C]);
}

// A recovery over between two conclusions.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20397444)] // ceil(1.05 × 19426137 measured)
fn test_cost_term_set_c_r_c6() {
    term_mix(array![C, R, C, C, C, C, C, C]);
}

// Two lapses between two conclusions: both writes go with the next conclusion's.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 20402106)] // ceil(1.05 × 19430577 measured)
fn test_cost_term_set_c_ll_c5() {
    term_mix(array![C, L, L, C, C, C, C, C]);
}

// A lapse first, the others activating.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19828354)] // ceil(1.05 × 18884146 measured)
fn test_cost_term_set_l_first() {
    term_mix(array![L, A, A, A, A, A, A, A]);
}

// A lapse in the middle, the others activating.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19828354)] // ceil(1.05 × 18884146 measured)
fn test_cost_term_set_l_middle() {
    term_mix(array![A, A, A, L, A, A, A, A]);
}

// Two lapses last, the others activating.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 19884532)] // ceil(1.05 × 18937649 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 23252607)] // ceil(1.05 × 22145340 measured)
fn test_cost_load_bound() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    let (world, _) = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 11940065)] // ceil(1.05 × 11371490 measured)
fn test_cost_load_bound_fixture() {
    let (words, content) = load_words(1);
    let (expected, _) = load_words(1);
    assert(words.goblins.len() == expected.goblins.len() && content.skills.len() == 38, 'twice');
}

// The same with two members (M-3): what each member adds.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 33322443)] // ceil(1.05 × 31735660 measured)
fn test_cost_load_bound_two_members() {
    let (words, content) = load_words(2);
    let (expected, _) = load_words(2);
    let (world, _) = words.load(@content);
    assert(world.store() == expected, 'round trip');
}

#[test]
// gas: raised, Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost
#[available_gas(l2_gas: 21666950)] // ceil(1.05 × 20635190 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 53519)] // ceil(1.05 × 50970 measured)
fn test_cost_sheet_skill_regen_first() {
    assert(read_skill([kind::REGENERATION, kind::DAMAGE, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the second.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 56931)] // ceil(1.05 × 54220 measured)
fn test_cost_sheet_skill_regen_second() {
    assert(read_skill([kind::DAMAGE, kind::REGENERATION, kind::DAMAGE], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 60344)] // ceil(1.05 × 57470 measured)
fn test_cost_sheet_skill_regen_third() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], 2, 6) == 2, 'regen');
}

// A skill's sheet, its `REGENERATION`: the third, negative.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 61604)] // ceil(1.05 × 58670 measured)
fn test_cost_sheet_skill_regen_third_negative() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::REGENERATION], -3, -10) == -3, 'regen');
}

// A skill's sheet, its `REGENERATION`: none of three entries.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 52353)] // ceil(1.05 × 49860 measured)
fn test_cost_sheet_skill_none() {
    assert(read_skill([kind::DAMAGE, kind::DAMAGE, kind::DAMAGE], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: an empty second entry.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 48174)] // ceil(1.05 × 45880 measured)
fn test_cost_sheet_skill_damage_then_empty() {
    assert(read_skill([kind::DAMAGE, kind::EMPTY, kind::EMPTY], 2, 6) == 0, 'regen');
}

// A skill's sheet, its `REGENERATION`: no entry.
#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 44552)] // ceil(1.05 × 42430 measured)
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

// A fixture artefact, not the tick's cost (CBT-05a, route (c)): every goblin of this fixture
// stands on one tile, so each carrier's call to ExecutorLibrary carries them all. The tick's
// cost is ENG-01 §9.2's line (26,422,703 a worst tick).
#[test]
// gas: raised, CBT-05a, route (c): each call carries every goblin (a fixture artefact)
#[available_gas(l2_gas: 103470757)] // ceil(1.05 × 98543578 measured)
fn test_cost_library_call_kills() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_kills();
    let words = library.run(words, content, board(), executor(), 1);
    assert(words.killed.len() == 100, 'every goblin once');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 29448524)] // ceil(1.05 × 28046213 measured)
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

// A fixture artefact, not the tick's cost (CBT-05a, route (c)): every goblin of this fixture
// stands on one tile, so each carrier's call to ExecutorLibrary carries them all. The tick's
// cost is ENG-01 §9.2's line (26,422,703 a worst tick).
#[test]
// gas: raised, CBT-05a, route (c): each call carries every goblin (a fixture artefact)
#[available_gas(l2_gas: 932517909)] // ceil(1.05 × 888112294 measured)
fn test_cost_library_call_two_members() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_two();
    let words = library.run(words, content, board(), executor(), 1);
    assert(words.members.len() == 2, 'two members');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 29608243)] // ceil(1.05 × 28198326 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 36696320)] // ceil(1.05 × 34948876 measured)
fn test_cost_library_call_all_dead() {
    let class = declare("TickLibrary").unwrap().contract_class();
    let library = ITickLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (words, content) = worst_words_all_dead();
    let words = library.run(words, content, board(), executor(), 1);
    assert(words.killed.len() == 100, 'each goblin once');
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 28433594)] // ceil(1.05 × 27079613 measured)
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

/// Each case's hash against the one the representation before CBT-02d gave.
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 138619736)] // ceil(1.05 × 132018796 measured)
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
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 181430523)] // ceil(1.05 × 172790974 measured)
fn test_parity_states() {
    let expected = array![
        66295114118071479459692970620146523881576091136849489442811860794139663220,
        818192087882419130412640452740579700817728367218241546515805066039749692743,
        2906164216761644532907114827085773083743798371616189745023773186502236529649,
        2613397554918266076825081268910489855062313516592916183374861504364664828908,
        2298920669945134706615672635496912081439368038756335941565106089387303402734,
        697695773267079789808853862635067569637746281765491970940063751435004344342,
        753256446473327071213823043884469167763738236257836741801423926569548893429,
        2167237727178921241778715351040650571144958650522743856062303552623326371335,
    ];
    check(parity_states().span(), expected.span());
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 244783825)] // ceil(1.05 × 233127452 measured)
fn test_parity_terms_one() {
    let expected = array![
        88087899950557960678794964014890056200459421389235559457401630463246604284,
        3579561893237392100038923530669381334989704862963200918198113192795527606886,
        2567228037492565523363386772544580452948188342943467954539007093421866396459,
        2912085704647302411354154677808699324450637052819509186428231974860872925057,
        433728905142926763847193419405653048457548304248634131207632820686103497468,
        2033346563660364008792322982179064364376401217183603600798956396365900579134,
        1249100349568056774094539997767552458500908577533013347860470997306826367504,
        2033346563660364008792322982179064364376401217183603600798956396365900579134,
        891191391904939947100891592741596371153250298472982675948188109234020004337,
        3112680036695512405674054925354465360586176898873616806369648439981786239926,
        1672640494903947382382267510994679190517231905690503933633620198094781814072,
        630241381706957817328858465464406209916783855088746342540356238819133309139,
        1134850821367488419383656841196072864013414594968230892252060344947998097459,
    ];
    check(parity_terms_one().span(), expected.span());
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 231343224)] // ceil(1.05 × 220326880 measured)
fn test_parity_terms_eight() {
    let expected = array![
        2121333299619063147913285746205207917883134567401573317101663845783484896436,
        599268691462812653467081228824803315194703295356781843380239879958356481493,
        121588814585967634366285767176815376419103130041297977422131092009062460392,
        2910551669979255134056396293675564154868246984207346922499563435233818195554,
        2891821211414996803827012556194696439884861292227313665264508143637619802305,
        2910551669979255134056396293675564154868246984207346922499563435233818195554,
        1609730803116411593211745486417407844307954119460764620517071958157052486672,
        1816821286769248378503520828288867372310126870686729059281766238675924149260,
        200890224080408962118036520475000037907869055607390301074377674017660260183,
        3004372021678339891596254004570985572933057602128654812115063414994757262309,
    ];
    check(parity_terms_eight().span(), expected.span());
}

#[test]
// gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
#[available_gas(l2_gas: 164719646)] // ceil(1.05 × 156875853 measured)
fn test_parity_terms_mixed() {
    let expected = array![
        27992153565252449929902520995596670114029068624090995673201924444728575957,
        3106687891589951335204801563655212505762174296790971771797177050293919044653,
        2793289906036307173993654288333319208163955455842056704257748431531148475402,
        829081272877034207383686717374503514167686565867885275763425410260734276763,
        409805861387747913415738105721913034229628692213750613121443509321194602875,
        2873271243383038176927594926366083624367330016323570349714795423920882569300,
        1893901237981330943186718663857116933347588528450890899926102793009466032819,
    ];
    check(parity_terms_mixed().span(), expected.span());
}

/// The executor's class (route (c), CBT-05a), declared once a test.
fn executor() -> starknet::ClassHash {
    *declare("ExecutorLibrary").unwrap().contract_class().class_hash
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
// source, the addressed goblin, the goblins within one tile of the source or the address). These
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
    let out = library.run(words, content, board(), executor(), 1);
    let mut rules = ExecutorTrait::new(board());
    TickTrait::run(ref world, @sheets, 1, ref rules);
    assert(out == world.store(), 'route (c) = in process');
    out
}

// The member's Cinder Ring concludes at tick 41 and kills goblins 9 and 10 (adjacent, 50 health;
// 80 at x = 60 is 226), in tile order, which the sub-world reaches; goblins 8 and 11 are far and
// stay out of the call. The library's words equal the in-process executor's.
#[test]
#[available_gas(l2_gas: 900000000)]
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
#[available_gas(l2_gas: 900000000)]
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

/// The representative worst tick (the review of #334, ENG-01 §9.2): 13 goblins within one tile of
/// the member or of each other, the member's ring of 6 and 7 at distance 2; 8 of them awake, each
/// concluding its attack skill on the member at tick 41 with a reach of 6 (all legal), so each
/// call carries the member and the goblins within one tile of its source or of the member.
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
#[available_gas(l2_gas: 900000000)]
fn test_cost_route_c_tick_fixture() {
    let (world, sheets, _) = worst_tick();
    assert(opaque(world.goblin_count()) == 13 && sheets.skills.len() > 0, 'fixture');
}

// The worst tick in process with the in-class executor (route (a)'s shape): the pair's base.
#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_route_c_tick_in_class() {
    let (mut world, sheets, _) = worst_tick();
    let mut rules = ExecutorTrait::new(board());
    TickTrait::tick(ref world, @sheets, ref rules);
    assert(rules.cache.hits == 8, 'eight hits');
}

// The same tick through route (c): `TickLibrary`'s hook builds each sub-world, calls
// `ExecutorLibrary` and loads back what returns, 8 times.
#[test]
#[available_gas(l2_gas: 900000000)]
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
    };
    TickTrait::tick(ref world, @sheets, ref rules);
    assert(rules.cache.hits == 8 && !world.defeated, 'eight hits');
}

// ---- The representative worst, through `TickLibrary` (the cost audit of #334, F-1) --------------
// The member at `AT`; 8 awake goblins one per tile, its ring of 6 and 2 behind (design/04, ENG-01
// §9.2); the worst content (38 skills, 4 potions, 5 castes), caste 1's weapon of reach 6 so that
// every goblin's attack is legal. Scenarios, one tick unless said: 0 idle; 1 the 8 goblins each
// conclude an attack skill on the member; 2 the member concludes Cinder Ring on its ring; 3 one
// goblin 3 tiles away concludes on the member, reaching 13 goblins (its 6 neighbours and the
// member's 6); 4 scenario 3's state idle.

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
    if scenario == 2 {
        member.start(1, 0, 1, 40);
    }
    let mut goblins = array![];
    let mut entity: u16 = 8;
    if scenario >= 3 {
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
            if scenario == 1 {
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
    library.run(rep_words(scenario), rep_content(), board(), executor, ticks)
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
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_fixture() {
    rep_fixture(0);
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_far_fixture() {
    rep_fixture(4);
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_idle() {
    let words = rep_run(0, 1);
    assert(words.members.len() == 1, 'ran');
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_goblins() {
    let words = rep_run(1, 1);
    assert(!words.defeated, 'eight carriers');
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_member() {
    let words = rep_run(2, 1);
    assert(words.killed.len() == 0, 'no kill');
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_far() {
    let words = rep_run(3, 1);
    assert(words.goblins.len() == 13, 'thirteen');
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_far_idle() {
    let words = rep_run(4, 1);
    assert(words.goblins.len() == 13, 'thirteen');
}

#[test]
#[available_gas(l2_gas: 900000000)]
fn test_cost_rep_batch() {
    let words = rep_run(1, 10);
    assert(words.clock == 50, 'ten ticks');
}
