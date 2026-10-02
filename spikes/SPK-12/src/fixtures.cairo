//! CBT-02's benchmark states, copied from `contracts/logic/tests/test_tick.cairo` at 2a8304d (main
//! at the spike's base, e9b8cef): `Fixture` (its `spec`, `member_words`, `member`, `goblin`,
//! `skill`, `caste`, `content`, `sheets`, `world`), `goblin_words` and its powers of two,
//! `worst_content`, `worst_of`, `representative`, `content_of` and the `Busy` rules, unchanged but
//! for visibility.
//! A crate apart cannot import a test file, hence the copy.

use grimworld_logic::models::goblin::{Goblin, GoblinTickTrait, GoblinTrait, GoblinWords};
use grimworld_logic::models::member::{Member, MemberTickTrait, MemberTrait, MemberWords};
use grimworld_logic::types::combat::{activation, skill_kind};
use grimworld_logic::types::tick::{
    CasteSheet, Content, ContentTrait, NO_SLOT, PotionSheet, Sheets, SkillSheet, ai, status,
};
use grimworld_logic::types::world::{Actor, Rules, World, WorldTrait};

pub const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
pub const HOB: u16 = 1;
pub const RUNT: u16 = 2;

/// `2^n`.
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
            words: Self::member_words(spec),
        }
    }

    /// An awake, Engaged goblin of `caste` at level 10: health 100 of 280, no activation.
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
            caste_at: (caste - 1).into(),
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

    fn sheets() -> Sheets {
        Self::content().sheets()
    }

    fn world(clock: u32, members: Array<Member>, goblins: Array<Goblin>) -> World {
        WorldTrait::new(clock, members, goblins, array![], false)
    }
}

/// Rules that keep every actor busy (AUD-182-7): the member's activation restarted in step 0, every
/// goblin free to act starting a 1-tick activation.
#[derive(Drop, Default)]
pub struct Busy {}

pub impl BusyRules of Rules<Busy> {
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

/// The words of a goblin of caste 5 at level 10 (ENG-01 §3.2 offsets).
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

const B24: felt252 = 0x1000000;
const B32: felt252 = 0x100000000;
const B52: felt252 = 0x10000000000000;
const B64: felt252 = 0x10000000000000000;
const B80: felt252 = 0x100000000000000000000;
const B108: felt252 = 0x1000000000000000000000000000;
const B128: felt252 = 0x100000000000000000000000000000000;
const B212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const B246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

/// The content at the MVP's widest (design/19 §7.2): the castes' weapons cost `k` ticks.
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
        PotionSheet { id: 100, regen: 1 }, PotionSheet { id: 101, regen: 2 },
        PotionSheet { id: 102, regen: 1 }, PotionSheet { id: 103, regen: 2 },
    ];
    Content { skills: skills.span(), potions: potions.span(), castes: castes.span() }
}

/// CBT-02's heavy scenario (`worst_state` is `worst_of(dying, k, 100)`): 100 goblins, the last 8
/// awake, every actor loaded from its words.
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
            goblin_words(8 + i, false, 280, 0, 99)
        };
        goblins.append(GoblinTrait::load(words, ref index, @sheets));
        i += 1;
    }
    (Fixture::world(49, array![member], goblins), sheets)
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

/// The content the sheets were built from, for the library call.
pub fn content_of(sheets: @Sheets) -> Content {
    Content { skills: *sheets.skills, potions: *sheets.potions, castes: *sheets.castes }
}
