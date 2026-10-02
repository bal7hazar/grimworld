//! The unit tests' fixtures of the tick (D-167): a member and a goblin built from ENG-01's offsets,
//! a small content, the rules that record the hooks. Test code only (`#[cfg(test)]`); the
//! benchmarks in `tests/test_tick.cairo` keep their own copy, a crate apart.

use crate::models::goblin::{Goblin, GoblinTrait, GoblinWords};
use crate::models::member::{Member, MemberTrait, MemberWords};
use crate::types::combat::{activation, skill_kind};
use crate::types::tick::{
    ABSENT, CasteSheet, Content, ContentTrait, Held, NO_SLOT, PotionSheet, Sheets, SkillSheet, ai,
    status,
};
use crate::types::world::{Actor, Idle, Rules, TickTrait, World, WorldTrait};

pub const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
/// Castes of the fixtures; caste `c`'s skills are `20 + 4 c + slot`, at position `c − 1`.
pub const HOB: u16 = 1;
pub const RUNT: u16 = 2;
pub const SMASH: u16 = 24;

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

    /// The member of `spec`, its derived fields as the spec gives them; its bar 1–8 at the
    /// content's positions 0–7.
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
            health_regen: 0,
            max_energy: 30,
            energy_regen: 1,
            adrenaline_cap: 0,
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

    /// A member loaded from its words through `content`'s index.
    fn load_member(words: MemberWords, content: @Content) -> Member {
        let (sheets, mut index) = content.index();
        MemberTrait::load(words, ref index, @sheets)
    }

    /// A goblin loaded from its words through `content`'s index.
    fn load_goblin(words: GoblinWords, content: @Content) -> Goblin {
        let (sheets, mut index) = content.index();
        GoblinTrait::load(words, ref index, @sheets)
    }

    fn world(clock: u32, members: Array<Member>, goblins: Array<Goblin>) -> World {
        WorldTrait::new(clock, members, goblins, array![], false)
    }

    fn only(clock: u32, goblin: Goblin) -> World {
        Self::world(clock, array![Self::member(Self::spec())], array![goblin])
    }

    /// Skills of design/19 §10.4: Stone Skin 11 (an enchantment), Warcry 12 (a shout), Venom Coat
    /// 13 (a preparation), Sidestep 14 and Brace 15 (stances), and the bar's 1–8.
    fn hold_content() -> Content {
        let mut skills = array![];
        for id in 1..9_u16 {
            skills.append(Self::skill(id, skill_kind::SPELL, 1, 10));
        }
        skills.append(Self::skill(11, skill_kind::ENCHANTMENT, 1, 10));
        skills.append(Self::skill(12, skill_kind::SHOUT, 0, 10));
        skills.append(Self::skill(13, skill_kind::PREPARATION, 0, 10));
        skills.append(Self::skill(14, skill_kind::STANCE, 0, 10));
        let mut brace = Self::skill(15, skill_kind::STANCE, 0, 10);
        brace.regen0 = 1;
        brace.regen12 = 1;
        skills.append(brace);
        Content {
            skills: skills.span(),
            potions: array![
                PotionSheet { id: 100, regen: 1, ..Default::default() },
                PotionSheet { id: 101, regen: 2, ..Default::default() },
                PotionSheet { id: 102, regen: 3, ..Default::default() },
                PotionSheet { id: 103, regen: 4, ..Default::default() },
            ]
                .span(),
            castes: array![].span(),
        }
    }

    fn held(carrier: u16, potion: bool, deadline: u32, rank: u8) -> Held {
        Held { carrier, potion, charges: 0, deadline, rank }
    }
}

/// Keeps a value from the compiler's constant folding, so that the path under test runs.
#[inline(never)]
pub fn opaque<T, +Drop<T>>(value: T) -> T {
    value
}

pub fn activation_of(goblin: @Goblin) -> (u8, u16, u32) {
    (*goblin.act_slot, *goblin.act_target, *goblin.act_deadline)
}

/// Test rules: record every hook's call; optionally take the member to 0 at an act of tick
/// `kill_member_at` or at the first resolution (`kill_on_resolve`), or wake the goblin at index
/// `wake − 1` in step 0 (0: none).
#[derive(Drop, Default)]
pub struct Script {
    pub acts: Array<(u32, u16)>,
    pub resolved: Array<(u32, Actor, u8)>,
    pub kill_member_at: u32,
    pub kill_on_resolve: bool,
    pub wake: u32,
}

pub impl ScriptRules of Rules<Script> {
    fn perceive(ref self: Script, ref world: World) {
        if self.wake > 0 {
            let mut goblin = world.goblin(self.wake - 1);
            goblin.awake = true;
            world.set_goblin(self.wake - 1, goblin);
        }
    }
    fn resolve(
        ref self: Script, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {
        self.resolved.append((world.clock, actor, slot));
        if self.kill_on_resolve {
            let mut member = *world.members.at(0);
            member.health = 0;
            world.set_member(0, member);
        }
    }
    fn act(ref self: Script, ref world: World, sheets: @Sheets, index: u32) {
        self.acts.append((world.clock, world.goblin(index).entity));
        if world.clock == self.kill_member_at {
            let mut member = *world.members.at(0);
            member.health = 0;
            world.set_member(0, member);
        }
    }
    fn objectives(ref self: Script, ref world: World) {}
}

/// `ticks` ticks of the fixtures' content, `Idle`'s rules.
pub fn run(ref world: World, ticks: u8) {
    let mut rules = Idle {};
    TickTrait::run(ref world, @Fixture::sheets(), ticks, ref rules);
}
