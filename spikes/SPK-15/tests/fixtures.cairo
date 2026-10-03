// Fixtures copied from `contracts/logic/tests/test_tick.cairo` at main `d4b5cdc` (SPK-15's base),
// unchanged but for `pub` (this crate's benchmarks share them) and the `use` lines: the member's
// and the goblins' words from ENG-01's offsets, the MVP's widest content, CBT-02d's term worlds
// (the bound's costliest state) and load's costliest words, the representative tick. `opaque` is
// CBT-04's (`types/world/fixtures.cairo` at `b5f4069`).
use grimworld_logic::models::goblin::{Goblin, GoblinTrait, GoblinWords};
use grimworld_logic::models::member::{Member, MemberTickTrait, MemberTrait, MemberWords};
use grimworld_logic::types::combat::{activation, skill_kind};
use grimworld_logic::types::tick::{
    CasteSheet, Content, ContentTrait, NO_SLOT, PotionSheet, Sheets, SkillSheet, ai, status,
};
use grimworld_logic::types::world::{Actor, Rules, Words, World, WorldTrait};

/// Keeps a value from the compiler's constant folding, so that the path under test runs.
#[inline(never)]
pub fn opaque<T, +Drop<T>>(value: T) -> T {
    value
}

pub const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
/// Castes of the fixtures; caste `c`'s skills are `20 + 4 c + slot`.
pub const HOB: u16 = 1;
pub const RUNT: u16 = 2;
pub const SMASH: u16 = 24;

/// `2^n` (fixtures only: the benchmarks subtract the fixtures' cost).
pub fn two(n: u32) -> felt252 {
    let mut p: felt252 = 1;
    for _ in 0..n {
        p *= 2;
    }
    p
}

/// A member's hot fields and derived ones.
#[derive(Copy, Drop)]
pub struct MemberSpec {
    pub health: u16,
    pub energy: u16,
    pub adrenaline: u16,
    pub flags: u8,
    pub status: u8,
    /// Bleeding, poison, burning, knocked.
    pub conditions: [u32; 4],
    /// `(carrier, potion, deadline, rank)` of each effect slot.
    pub effects: [(u16, bool, u32, u8); 4],
    pub effect_regen: [i8; 4],
    pub health_regen: i8,
    pub energy_regen: u8,
}

#[generate_trait]
pub impl FixtureImpl of Fixture {
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
            effect_at: 0xFFFFFFFF,
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

pub fn goblin_words(entity: u16, awake: bool, health: u16, due: u32, until: u32) -> GoblinWords {
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
pub const B24: felt252 = 0x1000000;
pub const B32: felt252 = 0x100000000;
pub const B52: felt252 = 0x10000000000000;
pub const B64: felt252 = 0x10000000000000000;
pub const B80: felt252 = 0x100000000000000000000;
pub const B108: felt252 = 0x1000000000000000000000000000;
pub const B128: felt252 = 0x100000000000000000000000000000000;
pub const B212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
pub const B246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

/// The content at the MVP's widest (design/19 §7.2: `C = 5`, `T = 10`): the bar's 8 skills (7 and
/// 8 regenerating 3 pips), 10 terrain traps' skills, the 5 castes' 20; 4 potions. The goblins'
/// caste, 5, and its skills (40–43) come last in their lists: before CBT-02d every lookup scanned
/// the whole list; the index reads them at the cost of any other.

pub fn worst_content(k: u8) -> Content {
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
pub fn worst_state(dying: bool, k: u8) -> (World, Sheets) {
    worst_of(dying, k, 100)
}

/// `worst_state` with `count` goblins in the array, the last 8 awake.
pub fn worst_of(dying: bool, k: u8, count: u16) -> (World, Sheets) {
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

/// The content the sheets were built from, for the library call.
pub fn content_of(sheets: @Sheets) -> Content {
    Content { skills: *sheets.skills, potions: *sheets.potions, castes: *sheets.castes }
}

/// A representative tick: the member with one condition and one effect, 8 awake goblins of 2
/// castes fighting (no activation due, no condition), the content of two castes.
pub fn representative() -> (World, Sheets) {
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

/// Step 1's branches of one awake goblin (design/19 §5.2).
pub const B_NONE: u8 = 0;
pub const B_CONCLUDE_RECOVER: u8 = 1;
pub const B_CONCLUDE_CLEAR: u8 = 2;
pub const B_LAPSE: u8 = 3;
pub const B_RECOVERY_END: u8 = 4;
pub const B_ACTIVATING: u8 = 5;
pub const B_FREE: u8 = 6;

/// `goblin_words` with its activation field's slot: a caste skill 0–3 due at `due`, or
/// `activation::RECOVERING` until `due`, or none.
pub fn goblin_words_at(
    entity: u16, awake: bool, health: u16, slot: u8, due: u32, until: u32,
) -> GoblinWords {
    let mut words = goblin_words(entity, awake, health, 0, until);
    words.timers += slot.into() - activation::NONE.into() + due.into() * B24;
    words
}

/// `worst_content(k)` with skill 43, the list's last, an attack skill of activation 1: the branch
/// goblin concludes it (slot 3) and holds it as its effect, so each of its lookups ends its list.
pub fn branch_content(k: u8) -> Content {
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

pub fn member_effect_words(potions: bool) -> MemberWords {
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

/// Step 1's branches CBT-02 did not measure: a lapse whose later recharge is kept, a recovery that
/// runs on, an awake goblin already dead, a free goblin knocked down.
pub const B_LAPSE_KEEP: u8 = 7;
pub const B_RECOVERING: u8 = 8;
pub const B_DEAD: u8 = 9;
pub const B_KNOCKED: u8 = 10;

pub const B184: felt252 = 0x10000000000000000000000000000000000000000000000;

/// The words of an awake goblin taking `branch` in the tick of 50 (the clock at 49): at 1 health,
/// dying in step 3 (at 280 with `survive`); its activation field, a later recharge kept, dead,
/// knocked down, as the branch needs.
pub fn term_words(entity: u16, branch: u8, survive: bool) -> GoblinWords {
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
pub fn term_world(
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
pub fn at_end(n: u16) -> Span<u16> {
    let mut at = array![];
    let mut i = 100 - n;
    while i < 100 {
        at.append(i);
        i += 1;
    }
    at.span()
}

pub fn at_start(n: u16) -> Span<u16> {
    let mut at = array![];
    let mut i = 0;
    while i < n {
        at.append(i);
        i += 1;
    }
    at.span()
}

pub fn at_spread() -> Span<u16> {
    array![5, 17, 29, 41, 53, 65, 77, 89].span()
}

/// `n` times `branch`.
pub fn all_of(branch: u8, n: u32) -> Span<u8> {
    let mut branches = array![];
    for _ in 0..n {
        branches.append(branch);
    }
    branches.span()
}

/// Seven times `first`, then `last`.
pub fn seven_then(first: u8, last: u8) -> Span<u8> {
    let mut branches = array![];
    for _ in 0..7_u8 {
        branches.append(first);
    }
    branches.append(last);
    branches.span()
}


/// so that a free goblin's branch is proved to reach it. The record is an append a goblin that
/// acts: the free branch's term counts it, a little above what `Idle` costs.
#[derive(Drop, Default)]
pub struct Acts {
    pub acts: Array<u32>,
}

pub impl ActsRules of Rules<Acts> {
    fn perceive(ref self: Acts, ref world: World) {}
    fn resolve(
        ref self: Acts, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Acts, ref world: World, sheets: @Sheets, index: u32) {
        self.acts.append(index);
    }
    fn objectives(ref self: Acts, ref world: World) {}
}

pub const C: u8 = B_CONCLUDE_CLEAR;
pub const A: u8 = B_ACTIVATING;
pub const L: u8 = B_LAPSE;
pub const R: u8 = B_RECOVERY_END;

/// `branch_content(3)` with increasing adrenaline costs: the bar's skills 1–8 cost 1–8 strikes,
/// each caste's four skills 1–4, so that every step of an adrenaline cap's loop raises it.
pub fn load_content() -> Content {
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
pub fn load_words(members: u32) -> (Words, Content) {
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
