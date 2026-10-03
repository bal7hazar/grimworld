//! The executor (CBT-05a; design/19 §5.14): one layer owns a carrier's entries. Every carrier, a
//! weapon attack, an attack skill, any other skill, a potion, a trap's payload, resolves here:
//! its entries are read, their guards evaluated once (FX-40), its target sets taken now, CBT-03a's
//! hit run first on each actor of the hit's set, the other entries applied in entry order (CBT-04's
//! conditions, heal, life steal, energy, holding effects through §5.7), the counters and
//! adrenaline moved (§5.12), and a goblin at 0 killed in resolution order (§5.13). The hit
//! (`types::hit`)
//! resolves one hit and never iterates entries.
//!
//! A value type with its behaviour, as `World`: it sits in `types/` (docs/CAIRO.md §7, D-147). The
//! pipeline's step-1 hook `Rules::resolve` calls it for an activation that concludes (`Executor`,
//! the rules of the tick's library class); the action phase (CBT-05b) and the AI's acts (ENG-07)
//! call `ExecutorTrait::execute` for an immediate carrier.
//!
//! **Geometry is ENG-02's** (`types::window`): the arc a weapon hit arrives from, the front tile
//! and every shape's tiles come from `WindowTrait` on the tick's `Board` (the window and where it
//! lies on the location: ENG-07 assembles it, D-120). An actor's position is its tile's in the
//! window; the actor list is ascending position, X-7's exception.
//!
//! **SPK-15's lever L3** (D-172), each part apart so that its pair measures it (`Levers`):
//! - the member's defence (its armor terms, its `BLOCK`, its `EVADE`, its stance and enchantment:
//!   SPK-15's "guard") read once a tick (`Cache`) and updated whenever the executor holds, spends
//!   or ends an effect on it (`Levers::spent`, `Levers::held`): a block's charge spent mid-tick
//!   reaches the next hit (`test_guard_two_hits`);
//! - a carrier's awake goblins written back in one rebuild of the awake set (`WorldTrait::flush`);
//! - the skills' entries decoded once a call into the sheets (`Sheets.entries`).
//! `Levered` is the executor; `Naive` reads the defence at each hit, writes each goblin after its
//! own and decodes each entry at its use: the pairs of `tests` measure each part against it.
//!
//! **Readings this lot fixed where the design is silent** (each in the report, reversible):
//! - a source never hits itself (no friendly fire, §2.3): it is left out of its own hit's set;
//! - of two `BLOCK` effects held, the lowest slot's charges are spent first;
//! - a holding entry whose duration at its rank is 0 or less and that carries no charges does not
//!   stay (§2.1: "0 = it does not stay"); `BLOCK`'s charges are its value, so a `BLOCK` of
//!   duration 0 does not stay;
//! - a goblin's weapon strength is `5 × its caste's rank`, uncapped (design/20 §2.4's assumption,
//!   DS-9: the level cap's curve is BAL-01's);
//! - a goblin hit while asleep or on watch notices: its AI state becomes Engaged (§5.5 step 9);
//!   its pack's `alert` bits and the packs within 8 tiles are chunk features, ENG-07's.

use core::dict::{Felt252Dict, Felt252DictTrait};
use hexx::board::bits::Bits;
use starknet::ClassHash;
use crate::durations::effective_duration;
use crate::interface::{IExecutorLibraryDispatcherTrait, IExecutorLibraryLibraryDispatcher};
use crate::models::goblin::{
    Goblin, GoblinConditionTrait, GoblinLifecycleTrait, GoblinPlaceTrait, GoblinTrait,
    GoblinWordsTrait,
};
use crate::models::member::{
    Member, MemberConditionTrait, MemberLifecycleTrait, MemberSnapshotTrait, MemberTrait,
    MemberWordsTrait,
};
use crate::types::combat::{Arc, HitClass, condition, skill_kind};
use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, scope, shape, target};
use crate::types::hit::{Hit, HitOutcome, HitTarget, HitTrait, MAX_BLOCK};
use crate::types::infliction::Infliction;
use crate::types::tick::{
    ABSENT, ABSENT_LANE, CasteSheetTrait, Content, ENERGY_THIRDS, Held, Index, Sheets,
    SkillSheetTrait, ai, flag,
};
use crate::types::window::{FAR, HEIGHT, WIDTH, Window, WindowTrait, range};
use crate::types::world::{Actor, Pending, Rules, Words, World, WorldTrait};
use crate::types::{FIRST_GOBLIN, MAX_CLOCK};

/// A value's bounds at play (design/19 §6: a value outside its kind's bounds is clamped).
const MAX_VALUE: i32 = 32767;
const MAX_ENERGY_VALUE: i32 = 255;
const MAX_PERCENT: i32 = 100;
const MAX_ARMOR_EFFECT: i32 = 255;
/// The bit of an actor's membership mask for the carrier's hit; entries 1–3 are bits 1, 2, 4.
const HIT_BIT: u8 = 8;
/// The keys of `subcontent`'s dictionary: a skill's id; a caste's + `CASTE_KEY`; a potion's +
/// `POTION_KEY` (the content index's own offsets).
const CASTE_KEY: felt252 = 0x10000;
const POTION_KEY: felt252 = 0x100000000;

pub mod errors {
    pub const ADDRESS: felt252 = 'executor: no such actor';
}

/// The board of a tick (ENG-07 assembles it, D-120): the window and the location's tile at its
/// position 0. A tile `(x, y)` of the location is the window's position `15 (y − y0) + (x −
/// x0)`, the location's axis orientation kept (ENG-02's note to ENG-07); outside it, `FAR`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Board {
    pub window: Window,
    pub x: u8,
    pub y: u8,
}

/// A carrier the executor runs (§5.14's dispatch).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Carrier {
    /// A weapon attack: no entry, an implicit weapon hit on the attacked entity.
    Weapon,
    /// A skill: its position in `Sheets.skills` and the source's rank in it (0–15).
    Skill: (u32, u8),
    /// A potion: its position in `Sheets.potions` and the belt slot it was drunk from (its held
    /// effect's carrier, FX-42).
    Potion: (u32, u8),
}

/// What an execution did.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Executed {
    /// The carrier ran (its actor list may have been empty: carrier-level effects only).
    Ran,
    /// A `TRAP` carrier whose `TRAP` entry's guard held: the trap is placed on the target tile,
    /// outside any actor iteration (§5.14 step 2; the placement is CBT-05b's, §5.11).
    Place,
    /// A `TRAP` carrier whose guard was false: nothing placed, the payload not run.
    Skipped,
    /// The target was not legal at resolution (§5.9): nothing happened, the costs stay paid.
    Illegal,
}

/// An actor's terms a hit on it reads that change only when an effect is held, spent or ended
/// (design/19 §5.5 step 3, §5.6), and its stance and enchantment (the guards `IN_STANCE`,
/// `ENCHANTED`): SPK-15's "guard". Read once a tick for the member (`Cache`, L3).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Defence {
    /// The unguarded armor (the snapshot's signed value, or the caste's).
    pub armor: i16,
    /// Its `ARMOR` effects, summed, each clamped to 0…255.
    pub effects: u16,
    /// Its guarded `ARMOR` sums (F-20).
    pub stance: i8,
    pub enchanted: i8,
    /// It holds a stance; it holds an enchantment.
    pub in_stance: bool,
    pub is_enchanted: bool,
    /// The charges of the `BLOCK` it holds (the lowest slot's), its slot; 0 none.
    pub block: u8,
    pub block_slot: u8,
    /// It holds `EVADE`.
    pub evade: bool,
}

/// The member's defence kept for the tick (L3): valid for `member` at `t` while `at == t + 1`.
/// The hits the executor ran at `t`, counted (the 15 of ENG-01 §9.2 is a derivation; this is the
/// count).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Cache {
    pub defence: Defence,
    pub member: u32,
    pub at: u32,
    pub hits: u32,
    pub hits_at: u32,
}

/// A carrier's source terms of its hit (§5.4), gathered once a carrier.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Offence {
    pub class: HitClass,
    pub weapon: u8,
    pub melee: bool,
    pub strength: u16,
    pub base: u32,
    pub percent: i16,
    pub above: i16,
    pub penetration: u16,
    pub damage_type: u8,
    /// `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT` (a member's weapon hits).
    pub steal: u8,
    pub energy: u8,
}

/// What a carrier's entries apply with: its source's rank, what the source adds to the conditions
/// and enchantments it inflicts, the carrier's held effect's identity.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Context {
    pub rank: u8,
    pub infliction: Infliction,
    pub enchant: u8,
    /// The skill's kind (0 for a potion or a weapon attack).
    pub skill_kind: u8,
    /// The held effect's carrier: a skill id, or a belt slot with `potion`.
    pub carrier: u16,
    pub potion: bool,
    /// Its position in `Sheets.skills` or `Sheets.potions` (`ABSENT` for a weapon attack).
    pub at: u32,
    /// The class of its hit for the passives' sums (`MemberBar`'s: 0 a plain weapon attack, 1 an
    /// attack skill, 2 a spell; 3 none: a bomb, a trap).
    pub scope: u8,
    pub t: u32,
}

/// One hit's geometry and source terms: the arc and the front tile come from the positions and
/// facings (ENG-02).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Shot {
    pub hit: bool,
    pub offence: Offence,
    pub source_at: u8,
    pub source_facing: u8,
    pub target_at: u8,
}

/// The executor's levers (SPK-15's L3), one impl each way, so that a pair of tests measures each.
pub trait Levers<L> {
    /// Entry `k` of the skill at `at`.
    fn entry(self: @L, sheets: @Sheets, at: u32, k: u32) -> Entry;
    /// The potion's entry at `at`.
    fn potion_entry(self: @L, sheets: @Sheets, at: u32) -> Entry;
    /// The defence of member `index` at `t`.
    fn defence(
        self: @L, ref cache: Cache, member: @Member, index: u32, t: u32, sheets: @Sheets,
    ) -> Defence;
    /// Member `index` spent a block's charge.
    fn spent(self: @L, ref cache: Cache, index: u32);
    /// An effect was held on member `index`.
    fn held(self: @L, ref cache: Cache, index: u32);
    /// The awake goblins a carrier reaches are written back in one rebuild.
    fn gathers(self: @L) -> bool;
}

/// The executor with SPK-15's L3.
#[derive(Copy, Drop, Default)]
pub struct Levered {}

/// The executor without it: the pairs' base.
#[derive(Copy, Drop, Default)]
pub struct Naive {}

pub impl LeveredLevers of Levers<Levered> {
    #[inline(always)]
    fn entry(self: @Levered, sheets: @Sheets, at: u32, k: u32) -> Entry {
        *(*sheets.entries)[3 * at + k]
    }

    #[inline(always)]
    fn potion_entry(self: @Levered, sheets: @Sheets, at: u32) -> Entry {
        *(*sheets.potion_entries)[at]
    }

    fn defence(
        self: @Levered, ref cache: Cache, member: @Member, index: u32, t: u32, sheets: @Sheets,
    ) -> Defence {
        if cache.at == t + 1 && cache.member == index {
            return cache.defence;
        }
        let defence = DefenceTrait::member(member, t, sheets, self);
        cache.defence = defence;
        cache.member = index;
        cache.at = t + 1;
        defence
    }

    fn spent(self: @Levered, ref cache: Cache, index: u32) {
        if cache.member == index && cache.at != 0 {
            let mut defence = cache.defence;
            defence.block -= 1;
            cache.defence = defence;
        }
    }

    fn held(self: @Levered, ref cache: Cache, index: u32) {
        if cache.member == index {
            cache.at = 0;
        }
    }

    #[inline(always)]
    fn gathers(self: @Levered) -> bool {
        true
    }
}

pub impl NaiveLevers of Levers<Naive> {
    #[inline(always)]
    fn entry(self: @Naive, sheets: @Sheets, at: u32, k: u32) -> Entry {
        (*sheets.skills)[at].entry(k)
    }

    #[inline(always)]
    fn potion_entry(self: @Naive, sheets: @Sheets, at: u32) -> Entry {
        EntryTrait::unpack(*(*sheets.potions)[at].entry)
    }

    fn defence(
        self: @Naive, ref cache: Cache, member: @Member, index: u32, t: u32, sheets: @Sheets,
    ) -> Defence {
        DefenceTrait::member(member, t, sheets, self)
    }

    fn spent(self: @Naive, ref cache: Cache, index: u32) {}

    fn held(self: @Naive, ref cache: Cache, index: u32) {}

    #[inline(always)]
    fn gathers(self: @Naive) -> bool {
        false
    }
}

#[generate_trait]
pub impl BoardImpl of BoardTrait {
    fn new(window: Window, x: u8, y: u8) -> Board {
        Board { window, x, y }
    }

    /// The window's position of the location's tile `(x, y)`; `FAR` outside the window.
    #[inline(always)]
    fn position(self: @Board, x: u8, y: u8) -> u8 {
        if x < *self.x || y < *self.y {
            return FAR;
        }
        let dx = x - *self.x;
        let dy = y - *self.y;
        if dx >= WIDTH || dy >= HEIGHT {
            return FAR;
        }
        WIDTH * dy + dx
    }

    /// The window's position of a location's tile `x + 256 y`.
    #[inline(always)]
    fn tile(self: @Board, tile: u16) -> u8 {
        let (y, x) = DivRem::div_rem(tile, 256);
        self.position(x.try_into().unwrap(), y.try_into().unwrap())
    }
}

#[generate_trait]
pub impl DefenceImpl of DefenceTrait {
    /// The member's defence at `t`: its armor terms from its words, each of its four held effects'
    /// holding entry at the slot's rank (`ARMOR`, `BLOCK`, `EVADE`), and whether a stance or an
    /// enchantment is held.
    #[inline(never)]
    fn member<L, +Levers<L>>(member: @Member, t: u32, sheets: @Sheets, lever: @L) -> Defence {
        let (armor, stance, enchanted) = member.armor();
        let mut defence = Defence { armor, stance, enchanted, block_slot: 0, ..Default::default() };
        let mut slot: u8 = 0;
        while slot < 4 {
            let held = member.effect_of(slot);
            let at = member.effect_position(slot);
            if held.deadline >= t && at != ABSENT_LANE {
                let at: u32 = at.try_into().unwrap();
                Self::add(ref defence, @held, at, slot, sheets, lever);
            }
            slot += 1;
        }
        defence
    }

    /// A goblin's defence at `t`: its caste's armor and its one held effect.
    #[inline(never)]
    fn goblin<L, +Levers<L>>(goblin: @Goblin, t: u32, sheets: @Sheets, lever: @L) -> Defence {
        let caste = (*sheets.castes)[*goblin.caste_at];
        let mut defence = Defence { armor: (*caste.armor).into(), ..Default::default() };
        let held = goblin.effect_of();
        if held.deadline >= t && *goblin.effect_at != ABSENT {
            Self::add(ref defence, @held, *goblin.effect_at, 0, sheets, lever);
        }
        defence
    }

    /// What one held effect adds: its holding entry's `ARMOR`, `BLOCK`, `EVADE`; its carrier a
    /// stance or an enchantment.
    #[inline(never)]
    fn add<L, +Levers<L>>(
        ref defence: Defence, held: @Held, at: u32, slot: u8, sheets: @Sheets, lever: @L,
    ) {
        let entry = ExecutorTrait::holding(lever, sheets, *held.potion, at);
        let k = entry.kind;
        if k == kind::ARMOR {
            let v = ExecutorTrait::clamp(entry.value(*held.rank), 0, MAX_ARMOR_EFFECT);
            defence.effects += v.try_into().unwrap();
        } else if k == kind::BLOCK {
            if defence.block == 0 && *held.charges > 0 {
                defence.block = *held.charges;
                defence.block_slot = slot;
            }
        } else if k == kind::EVADE {
            defence.evade = true;
        }
        if !*held.potion {
            let skill_kind = *(*sheets.skills)[at].kind;
            if skill_kind == skill_kind::STANCE {
                defence.in_stance = true;
            } else if skill_kind == skill_kind::ENCHANTMENT {
                defence.is_enchanted = true;
            }
        }
    }
}

/// The source's `ON_ATTACK_CONDITION`s held at `t` (§5.5 step 7), gathered once a carrier: each
/// `(condition, value)`, the slots holding charges (bit `2^slot`), what it adds to conditions.
#[derive(Drop, Debug, PartialEq)]
pub struct OnAttack {
    pub conditions: Span<(u8, i32)>,
    pub charged: u8,
    pub infliction: Infliction,
}

/// What the source gains from one actor's turn: its weapon hit landed (step 8's source side), the
/// health it stole (`LIFE_STEAL`, `LIFE_STEAL_ON_HIT`).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Gain {
    pub landed: bool,
    pub stolen: u16,
}

/// One entry other than the hit, ready to apply (the views rework, R2): its kind, its `param`,
/// its value at the source's rank clamped to its kind's bounds (§6), and for a holding entry the
/// `Held` it puts (§5.7) and whether its carrier is a stance. Built once a carrier, not generic;
/// kind 0 for an entry that applies nothing (a hit, a modifier, a `TRAP`, a holding entry that
/// does not stay).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Op {
    pub kind: u8,
    pub param: u8,
    pub v: i32,
    pub held: Held,
    pub stance: bool,
}

/// What a hit reads of its target, read once (the views rework): its defence, facing, armor
/// against the hit's type, its state.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Struck {
    pub defence: Defence,
    pub facing: u8,
    pub armor_vs: u8,
    pub knocked: bool,
    pub asleep: bool,
    pub halves: bool,
    pub health: u16,
    pub max_health: u16,
}

/// What the executor reads and writes of an actor, a member or a goblin (design/19 §5.5–§5.7,
/// §5.12): one generic executor for both, monomorphized.
pub trait Body<T> {
    fn health(self: @T) -> u16;
    fn max_health(self: @T) -> u16;
    fn alive(self: @T) -> bool;
    fn is_member(self: @T) -> bool;
    /// Its tile and facing on the location.
    fn place(self: @T) -> (u8, u8, u8);
    /// Knocked down at `t`: critical from any arc, neither blocks nor evades (FX-7).
    fn knocked(self: @T, t: u32) -> bool;
    /// Asleep (a goblin): critical from any arc, its first hit neither blocked nor evaded (D-179).
    fn asleep(self: @T) -> bool;
    /// Holds `HALVE_FIRST_HEAVY_HIT`, not spent (FX-19).
    fn halves(self: @T) -> bool;
    fn armor_vs(self: @T, damage_type: u8, sheets: @Sheets) -> u8;
    /// Its defence at `t` (a member's through the lever's cache).
    fn defence<L, +Levers<L>>(
        self: @T, lever: @L, ref cache: Cache, actor: Actor, t: u32, sheets: @Sheets,
    ) -> Defence;
    /// Its hit's source terms for `context`'s carrier (§5.4).
    fn offence<L, +Levers<L>>(
        self: @T,
        lever: @L,
        class: HitClass,
        entry: @Entry,
        bonus: u32,
        penetration: u16,
        context: @Context,
        sheets: @Sheets,
    ) -> Offence;
    /// What it adds to the conditions and enchantments it inflicts.
    fn infliction(self: @T) -> Infliction;
    fn enchant_percent(self: @T) -> u8;
    /// `health = health ⊖ damage`.
    fn wound(ref self: T, damage: u16);
    /// `health = min(max, health + v)`, nothing on a dead actor.
    fn heal(ref self: T, v: u16);
    /// `clamp(energy + v, 0, max)`, `v` in energy, stored in thirds.
    fn energize(ref self: T, v: i32, sheets: @Sheets);
    /// A hit taken (§5.5 steps 5, 8, 9): a member's "hit this tick" flag; +1 quarter strike if
    /// alive; a goblin asleep or on watch notices.
    fn struck(ref self: T, sheets: @Sheets);
    /// A weapon hit landed (§5.12): adrenaline and the `hits` counter.
    fn landed(ref self: T, sheets: @Sheets);
    /// FX-19's halving spent.
    fn halved(ref self: T);
    /// Condition 1–5 for the value `v` at `t` (Knocked down through `knock`, CBT-04).
    fn inflict(ref self: T, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets);
    fn cure(ref self: T, condition: u8, t: u32);
    /// A holding effect through §5.7, its carrier at `at`.
    #[inline(never)]
    fn hold(ref self: T, held: Held, at: u32, stance: bool, t: u32, sheets: @Sheets);
    /// Its effect slots: 4 for a member, 1 for a goblin.
    fn slots(self: @T) -> u8;
    /// Effect slot `slot` and its carrier's position (`ABSENT` for none).
    fn effect(self: @T, slot: u8) -> (Held, u32);
    /// One charge of slot `slot` spent at `t`; at 0 the effect ends (`D = t − 1`).
    fn spend(ref self: T, slot: u8, t: u32);
}

pub impl MemberBody of Body<Member> {
    #[inline(always)]
    fn health(self: @Member) -> u16 {
        *self.health
    }

    #[inline(always)]
    fn max_health(self: @Member) -> u16 {
        *self.max_health
    }

    #[inline(always)]
    fn alive(self: @Member) -> bool {
        self.is_alive()
    }

    #[inline(always)]
    fn is_member(self: @Member) -> bool {
        true
    }

    fn place(self: @Member) -> (u8, u8, u8) {
        MemberSnapshotTrait::place(self)
    }

    fn knocked(self: @Member, t: u32) -> bool {
        self.takes_critical(t)
    }

    #[inline(always)]
    fn asleep(self: @Member) -> bool {
        false
    }

    fn halves(self: @Member) -> bool {
        MemberSnapshotTrait::halves(self)
    }

    fn armor_vs(self: @Member, damage_type: u8, sheets: @Sheets) -> u8 {
        MemberSnapshotTrait::armor_vs(self, damage_type)
    }

    fn defence<L, +Levers<L>>(
        self: @Member, lever: @L, ref cache: Cache, actor: Actor, t: u32, sheets: @Sheets,
    ) -> Defence {
        let index = match actor {
            Actor::Member(i) => i,
            Actor::Goblin(_) => core::panic_with_felt252(errors::ADDRESS),
        };
        lever.defence(ref cache, self, index, t, sheets)
    }

    fn offence<L, +Levers<L>>(
        self: @Member,
        lever: @L,
        class: HitClass,
        entry: @Entry,
        bonus: u32,
        penetration: u16,
        context: @Context,
        sheets: @Sheets,
    ) -> Offence {
        let scope = *context.scope;
        let (percent, above, sum) = if scope < 3 {
            self.passives(scope)
        } else {
            (0, 0, 0)
        };
        let held = ExecutorTrait::penetration(lever, self, scope, *context.t, sheets);
        let penetration = sum + held + penetration;
        if class == HitClass::Weapon {
            let (weapon, damage, range, strength, damage_type, met) = self.weapon();
            let (steal, energy) = self.on_hit();
            return Offence {
                class,
                weapon,
                melee: range == range::TOUCH,
                strength: strength.into(),
                base: HitTrait::weapon_base(damage, met, bonus.try_into().unwrap()),
                percent,
                above,
                penetration,
                damage_type,
                steal,
                energy,
            };
        }
        let strength = if class == HitClass::Item {
            (*(*sheets.potions)[*context.at].strength).into()
        } else {
            HitTrait::level_strength(self.level())
        };
        ExecutorTrait::spell(class, strength, entry, percent, above, penetration, context)
    }

    fn infliction(self: @Member) -> Infliction {
        MemberWordsTrait::infliction(self)
    }

    fn enchant_percent(self: @Member) -> u8 {
        MemberSnapshotTrait::enchant_percent(self)
    }

    fn wound(ref self: Member, damage: u16) {
        self.health = if damage >= self.health {
            0
        } else {
            self.health - damage
        };
    }

    fn heal(ref self: Member, v: u16) {
        if !self.is_alive() {
            return;
        }
        let health: u32 = self.health.into() + v.into();
        let max: u32 = self.max_health.into();
        self.health = if health > max {
            self.max_health
        } else {
            health.try_into().unwrap()
        };
    }

    fn energize(ref self: Member, v: i32, sheets: @Sheets) {
        let energy: i32 = self.energy.into() + v * ENERGY_THIRDS.into();
        let max: i32 = self.max_energy.into();
        self.energy = ExecutorTrait::clamp(energy, 0, max).try_into().unwrap();
    }

    fn struck(ref self: Member, sheets: @Sheets) {
        self.flags = self.flags | flag::HIT;
        self.take_hit();
    }

    fn landed(ref self: Member, sheets: @Sheets) {
        self.land_weapon_hit();
    }

    fn halved(ref self: Member) {
        self.flags = self.flags | flag::HALVED;
    }

    fn inflict(
        ref self: Member, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets,
    ) {
        if condition == condition::KNOCKED_DOWN {
            self.knock(v, source, t, sheets);
        } else {
            self.apply(condition, v, source, t);
        }
    }

    fn cure(ref self: Member, condition: u8, t: u32) {
        // CBT-04's review: the executor never cures a member at 0 or down.
        if self.is_alive() {
            MemberLifecycleTrait::cure(ref self, condition, t);
        }
    }


    #[inline(never)]
    fn hold(ref self: Member, held: Held, at: u32, stance: bool, t: u32, sheets: @Sheets) {
        if self.is_alive() {
            MemberLifecycleTrait::hold(ref self, held, at, stance, t, sheets);
        }
    }

    #[inline(always)]
    fn slots(self: @Member) -> u8 {
        4
    }

    fn effect(self: @Member, slot: u8) -> (Held, u32) {
        let at = self.effect_position(slot);
        let at = if at == ABSENT_LANE {
            ABSENT
        } else {
            at.try_into().unwrap()
        };
        (self.effect_of(slot), at)
    }

    fn spend(ref self: Member, slot: u8, t: u32) {
        let mut held = self.effect_of(slot);
        if held.charges == 0 {
            return;
        }
        held.charges -= 1;
        if held.charges == 0 {
            held.deadline = t - 1;
        }
        let [r0, r1, r2, r3] = self.effect_regen;
        let pips = *[r0, r1, r2, r3].span()[slot.into()];
        self.set_effect(slot, held, pips);
    }
}

pub impl GoblinBody of Body<Goblin> {
    #[inline(always)]
    fn health(self: @Goblin) -> u16 {
        *self.health
    }

    #[inline(always)]
    fn max_health(self: @Goblin) -> u16 {
        *self.max_health
    }

    #[inline(always)]
    fn alive(self: @Goblin) -> bool {
        self.is_alive() && *self.health > 0
    }

    #[inline(always)]
    fn is_member(self: @Goblin) -> bool {
        false
    }

    fn place(self: @Goblin) -> (u8, u8, u8) {
        GoblinPlaceTrait::place(self)
    }

    fn knocked(self: @Goblin, t: u32) -> bool {
        self.takes_critical(t)
    }

    #[inline(always)]
    fn asleep(self: @Goblin) -> bool {
        *self.ai == ai::ASLEEP
    }

    #[inline(always)]
    fn halves(self: @Goblin) -> bool {
        false
    }

    fn armor_vs(self: @Goblin, damage_type: u8, sheets: @Sheets) -> u8 {
        (*sheets.castes)[*self.caste_at].armor_vs(damage_type)
    }

    fn defence<L, +Levers<L>>(
        self: @Goblin, lever: @L, ref cache: Cache, actor: Actor, t: u32, sheets: @Sheets,
    ) -> Defence {
        DefenceTrait::goblin(self, t, sheets, lever)
    }

    fn offence<L, +Levers<L>>(
        self: @Goblin,
        lever: @L,
        class: HitClass,
        entry: @Entry,
        bonus: u32,
        penetration: u16,
        context: @Context,
        sheets: @Sheets,
    ) -> Offence {
        let caste = (*sheets.castes)[*self.caste_at];
        let held = ExecutorTrait::penetration(lever, self, *context.scope, *context.t, sheets);
        let penetration = held + penetration;
        if class == HitClass::Weapon {
            // design/20 §2.4: a goblin hits at `5 × its caste's rank`, its damage flat (DS-18
            // bounds it to 255); the level cap's curve is BAL-01's (DS-9).
            return Offence {
                class,
                weapon: *caste.weapon,
                melee: *caste.weapon_range == range::TOUCH,
                strength: HitTrait::weapon_strength(*caste.rank, 255),
                base: HitTrait::weapon_base(*caste.weapon_damage, true, bonus.try_into().unwrap()),
                percent: 0,
                above: 0,
                penetration,
                damage_type: *caste.damage_type,
                steal: 0,
                energy: 0,
            };
        }
        let strength = HitTrait::level_strength(self.level());
        ExecutorTrait::spell(class, strength, entry, 0, 0, penetration, context)
    }

    #[inline(always)]
    fn infliction(self: @Goblin) -> Infliction {
        Default::default()
    }

    #[inline(always)]
    fn enchant_percent(self: @Goblin) -> u8 {
        0
    }

    fn wound(ref self: Goblin, damage: u16) {
        self.health = if damage >= self.health {
            0
        } else {
            self.health - damage
        };
    }

    fn heal(ref self: Goblin, v: u16) {
        if !self.is_alive() || self.health == 0 {
            return;
        }
        let health: u32 = self.health.into() + v.into();
        let max: u32 = self.max_health.into();
        self.health = if health > max {
            self.max_health
        } else {
            health.try_into().unwrap()
        };
    }

    fn energize(ref self: Goblin, v: i32, sheets: @Sheets) {
        let energy: i32 = self.energy.into() + v * ENERGY_THIRDS.into();
        let max: i32 = self.max_energy(sheets).into();
        self.energy = ExecutorTrait::clamp(energy, 0, max).try_into().unwrap();
    }

    fn struck(ref self: Goblin, sheets: @Sheets) {
        self.take_hit(sheets);
        // §5.5 step 9: a goblin hit while asleep or on watch notices (D-179: so only its first
        // hit finds it asleep).
        if self.health > 0 && (self.ai == ai::ASLEEP || self.ai == ai::WATCH) {
            self.ai = ai::ENGAGED;
        }
    }

    fn landed(ref self: Goblin, sheets: @Sheets) {
        self.land_weapon_hit(sheets);
    }

    #[inline(always)]
    fn halved(ref self: Goblin) {}

    fn inflict(
        ref self: Goblin, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets,
    ) {
        if condition == condition::KNOCKED_DOWN {
            self.knock(v, source, t, sheets);
        } else {
            self.apply(condition, v, source, t);
        }
    }

    fn cure(ref self: Goblin, condition: u8, t: u32) {
        GoblinLifecycleTrait::cure(ref self, condition, t);
    }


    #[inline(never)]
    fn hold(ref self: Goblin, held: Held, at: u32, stance: bool, t: u32, sheets: @Sheets) {
        // A goblin's slot holds a skill (ENG-01 §3.2): a potion's effect does not stay on it.
        if !held.potion {
            GoblinLifecycleTrait::hold(ref self, held, at, t, sheets);
        }
    }

    #[inline(always)]
    fn slots(self: @Goblin) -> u8 {
        1
    }

    fn effect(self: @Goblin, slot: u8) -> (Held, u32) {
        (self.effect_of(), *self.effect_at)
    }

    fn spend(ref self: Goblin, slot: u8, t: u32) {
        let mut held = self.effect_of();
        if held.charges == 0 {
            return;
        }
        held.charges -= 1;
        if held.charges == 0 {
            held.deadline = t - 1;
        }
        let pips = self.effect_regen;
        self.set_effect(held, pips);
    }
}

/// An actor of either kind, one type (CBT-05a's rework, route (c)): the executor's generic code
/// (`run`, `on`, `strike`, `entries`, the actor list) is compiled once for it, not once for a
/// member and once for a goblin; each method dispatches to the kind's own.
#[derive(Copy, Drop, Debug, PartialEq)]
pub enum Unit {
    M: Member,
    G: Goblin,
}

pub impl UnitBody of Body<Unit> {
    fn health(self: @Unit) -> u16 {
        match self {
            Unit::M(m) => MemberBody::health(m),
            Unit::G(g) => GoblinBody::health(g),
        }
    }

    fn max_health(self: @Unit) -> u16 {
        match self {
            Unit::M(m) => MemberBody::max_health(m),
            Unit::G(g) => GoblinBody::max_health(g),
        }
    }

    fn alive(self: @Unit) -> bool {
        match self {
            Unit::M(m) => MemberBody::alive(m),
            Unit::G(g) => GoblinBody::alive(g),
        }
    }

    fn is_member(self: @Unit) -> bool {
        match self {
            Unit::M(m) => MemberBody::is_member(m),
            Unit::G(g) => GoblinBody::is_member(g),
        }
    }

    fn place(self: @Unit) -> (u8, u8, u8) {
        match self {
            Unit::M(m) => MemberBody::place(m),
            Unit::G(g) => GoblinBody::place(g),
        }
    }

    fn knocked(self: @Unit, t: u32) -> bool {
        match self {
            Unit::M(m) => MemberBody::knocked(m, t),
            Unit::G(g) => GoblinBody::knocked(g, t),
        }
    }

    fn asleep(self: @Unit) -> bool {
        match self {
            Unit::M(m) => MemberBody::asleep(m),
            Unit::G(g) => GoblinBody::asleep(g),
        }
    }

    fn halves(self: @Unit) -> bool {
        match self {
            Unit::M(m) => MemberBody::halves(m),
            Unit::G(g) => GoblinBody::halves(g),
        }
    }

    fn armor_vs(self: @Unit, damage_type: u8, sheets: @Sheets) -> u8 {
        match self {
            Unit::M(m) => MemberBody::armor_vs(m, damage_type, sheets),
            Unit::G(g) => GoblinBody::armor_vs(g, damage_type, sheets),
        }
    }

    fn infliction(self: @Unit) -> Infliction {
        match self {
            Unit::M(m) => MemberBody::infliction(m),
            Unit::G(g) => GoblinBody::infliction(g),
        }
    }

    fn enchant_percent(self: @Unit) -> u8 {
        match self {
            Unit::M(m) => MemberBody::enchant_percent(m),
            Unit::G(g) => GoblinBody::enchant_percent(g),
        }
    }

    fn slots(self: @Unit) -> u8 {
        match self {
            Unit::M(m) => MemberBody::slots(m),
            Unit::G(g) => GoblinBody::slots(g),
        }
    }

    fn effect(self: @Unit, slot: u8) -> (Held, u32) {
        match self {
            Unit::M(m) => MemberBody::effect(m, slot),
            Unit::G(g) => GoblinBody::effect(g, slot),
        }
    }

    fn defence<L, +Levers<L>>(
        self: @Unit, lever: @L, ref cache: Cache, actor: Actor, t: u32, sheets: @Sheets,
    ) -> Defence {
        match self {
            Unit::M(m) => MemberBody::defence(m, lever, ref cache, actor, t, sheets),
            Unit::G(g) => GoblinBody::defence(g, lever, ref cache, actor, t, sheets),
        }
    }

    fn offence<L, +Levers<L>>(
        self: @Unit,
        lever: @L,
        class: HitClass,
        entry: @Entry,
        bonus: u32,
        penetration: u16,
        context: @Context,
        sheets: @Sheets,
    ) -> Offence {
        match self {
            Unit::M(m) => MemberBody::offence(
                m, lever, class, entry, bonus, penetration, context, sheets,
            ),
            Unit::G(g) => GoblinBody::offence(
                g, lever, class, entry, bonus, penetration, context, sheets,
            ),
        }
    }

    fn wound(ref self: Unit, damage: u16) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::wound(ref m, damage);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::wound(ref g, damage);
                Unit::G(g)
            },
        };
    }

    fn heal(ref self: Unit, v: u16) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::heal(ref m, v);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::heal(ref g, v);
                Unit::G(g)
            },
        };
    }

    fn energize(ref self: Unit, v: i32, sheets: @Sheets) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::energize(ref m, v, sheets);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::energize(ref g, v, sheets);
                Unit::G(g)
            },
        };
    }

    fn struck(ref self: Unit, sheets: @Sheets) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::struck(ref m, sheets);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::struck(ref g, sheets);
                Unit::G(g)
            },
        };
    }

    fn landed(ref self: Unit, sheets: @Sheets) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::landed(ref m, sheets);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::landed(ref g, sheets);
                Unit::G(g)
            },
        };
    }

    fn halved(ref self: Unit) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::halved(ref m);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::halved(ref g);
                Unit::G(g)
            },
        };
    }

    fn inflict(
        ref self: Unit, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets,
    ) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::inflict(ref m, condition, v, source, t, sheets);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::inflict(ref g, condition, v, source, t, sheets);
                Unit::G(g)
            },
        };
    }

    fn cure(ref self: Unit, condition: u8, t: u32) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::cure(ref m, condition, t);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::cure(ref g, condition, t);
                Unit::G(g)
            },
        };
    }

    fn hold(ref self: Unit, held: Held, at: u32, stance: bool, t: u32, sheets: @Sheets) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::hold(ref m, held, at, stance, t, sheets);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::hold(ref g, held, at, stance, t, sheets);
                Unit::G(g)
            },
        };
    }

    fn spend(ref self: Unit, slot: u8, t: u32) {
        self = match self {
            Unit::M(mut m) => {
                MemberBody::spend(ref m, slot, t);
                Unit::M(m)
            },
            Unit::G(mut g) => {
                GoblinBody::spend(ref g, slot, t);
                Unit::G(g)
            },
        };
    }
}

/// The rules of the tick's library class (ENG-01 §1.3): step 1's hook runs the executor on the
/// activation that concluded; the others are ENG-07's (perception, the AI, the objectives). A
/// `TRAP` carrier whose guard held is recorded in `placed` (the address, the source), for the
/// placement (§5.11, CBT-05b).
#[derive(Drop)]
pub struct Executor {
    pub board: Board,
    pub cache: Cache,
    pub placed: Array<(u16, Actor)>,
}

pub impl ExecutorRules of Rules<Executor> {
    fn perceive(ref self: Executor, ref world: World) {}

    fn resolve(
        ref self: Executor, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {
        let lever = Levered {};
        let mut cache = self.cache;
        let board = self.board;
        let executed = ExecutorTrait::conclude(
            @lever, ref cache, ref world, sheets, @board, actor, slot, target,
        );
        self.cache = cache;
        if executed == Executed::Place {
            self.placed.append((target, actor));
        }
    }

    fn act(ref self: Executor, ref world: World, sheets: @Sheets, index: u32) {}

    fn objectives(ref self: Executor, ref world: World) {}
}

/// The rules of the tick's library class under route (c) (the project manager, 2026-10-02,
/// option (2)): step 1's hook calls the executor's own class, `ExecutorLibrary`, once a carrier,
/// with the words of the actors the carrier can reach: every member, the source, the addressed
/// goblin, and the goblins within one tile of the source or of the address (the MVP's shapes are
/// of radius 1 at most: `SINGLE`, `RING_1`, `DISC_1`; `DISC_2` and `DISC_3` are refused, FX-21).
/// The returned words are loaded again through the call's index and put back in the world; the
/// kills are appended in resolution order. Perception, the AI and the objectives are ENG-07's.
#[derive(Destruct)]
pub struct Delegate {
    pub board: Board,
    pub cache: Cache,
    pub executor: ClassHash,
    pub content: Content,
    pub index: Index,
    pub placed: Array<(u16, Actor)>,
}

pub impl DelegateRules of Rules<Delegate> {
    fn perceive(ref self: Delegate, ref world: World) {}

    fn resolve(
        ref self: Delegate, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {
        let board = self.board;
        // §5.9 in this class: the slot's carrier, and its target still legal (else nothing, the
        // costs stay paid); the carrier itself runs behind the call.
        let lever = Levered {};
        let carrier = ExecutorTrait::carrier(@world, sheets, actor, slot);
        if !ExecutorTrait::legal(@lever, @world, sheets, @board, actor, carrier, target) {
            return;
        }
        // §5.14 step 2 before any sub-world: a `TRAP` carrier places its trap if its guard
        // holds (CBT-05b writes the object), and nothing else runs (CBT-05a's review).
        if let Carrier::Skill((at, _)) = carrier {
            let first = lever.entry(sheets, at, 0);
            if first.kind == kind::TRAP {
                let entries = array![first].span();
                let held = match actor {
                    Actor::Member(i) => ExecutorTrait::guards(@world.member(i), entries),
                    Actor::Goblin(i) => ExecutorTrait::guards(@world.goblin(i), entries),
                };
                if held & 1 == 1 {
                    self.placed.append((target, actor));
                }
                return;
            }
        }
        let (addressing, _) = ExecutorTrait::addressing(@lever, @world, sheets, actor, carrier);
        // The source's and the address's positions.
        let source_at = match actor {
            Actor::Member(i) => {
                let (x, y, _) = MemberSnapshotTrait::place(@world.member(i));
                board.position(x, y)
            },
            Actor::Goblin(i) => {
                let (x, y, _) = GoblinPlaceTrait::place(@world.goblin(i));
                board.position(x, y)
            },
        };
        // The address by the carrier's addressing: a tile, an entity, or the source itself.
        let mut addressed: Option<u32> = None;
        let address_at = if addressing == target::TILE {
            board.tile(target)
        } else if addressing == target::SELF {
            source_at
        } else {
            match ExecutorTrait::actor(@world, target) {
                Some(Actor::Member(i)) => {
                    let (x, y, _) = MemberSnapshotTrait::place(@world.member(i));
                    board.position(x, y)
                },
                Some(Actor::Goblin(i)) => {
                    addressed = Some(i);
                    let (x, y, _) = GoblinPlaceTrait::place(@world.goblin(i));
                    board.position(x, y)
                },
                None => source_at,
            }
        };
        // The goblins the carrier can reach, ascending index (so ascending entity id). Option
        // (3)'s lever (3): a carrier whose entries are all `SINGLE` and none `TILE` (a weapon hit
        // too) reads its source and the addressed entity alone (`actors`), so carries no other.
        let wide = ExecutorTrait::wide(@lever, sheets, carrier);
        let mut picked: Array<u32> = array![];
        let mut sub = actor;
        for (i, state) in world.alive() {
            let (x, y, _) = GoblinPlaceTrait::at(state);
            let at = board.position(x, y);
            let own = actor == Actor::Goblin(i);
            let near = wide
                && (WindowTrait::distance(at, source_at) <= 1
                    || WindowTrait::distance(at, address_at) <= 1);
            if own || addressed == Some(i) || near {
                if own {
                    sub = Actor::Goblin(picked.len());
                }
                picked.append(i);
            }
        }
        let mut members = array![];
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            members.append(world.member(m).store());
            m += 1;
        }
        let mut goblins = array![];
        for i in picked.span() {
            goblins.append(world.goblin(*i).store());
        }
        let words = Words {
            clock: world.clock, members, goblins, killed: array![], defeated: false,
        };
        // Option (3)'s lever (1): only the records the sub-world's loads need.
        let content = ExecutorTrait::subcontent(@world, picked.span(), @self.content);
        // The carrier's skill at its position in the trimmed content (the class loads that one).
        let carrier = match carrier {
            Carrier::Skill((
                at, rank,
            )) => {
                let id = *self.content.skills[at].id;
                let mut moved = 0;
                let mut k = 0;
                for sheet in content.skills {
                    if *sheet.id == id {
                        moved = k;
                    }
                    k += 1;
                }
                Carrier::Skill((moved, rank))
            },
            other => other,
        };
        let library = IExecutorLibraryLibraryDispatcher { class_hash: self.executor };
        let (out, cache, place) = library
            .execute(words, content, board, self.cache, sub, carrier, target, world.clock);
        self.cache = cache;
        if place {
            self.placed.append((target, actor));
        }
        let mut m = 0;
        for words in out.members {
            let member = MemberTrait::load(words, ref self.index, sheets);
            world.set_member(m, member);
            m += 1;
        }
        let mut k = 0;
        for words in out.goblins {
            let goblin = GoblinTrait::load(words, ref self.index, sheets);
            world.set_goblin(*picked[k], goblin);
            k += 1;
        }
        for entity in out.killed {
            world.killed.append(entity);
        }
    }

    fn act(ref self: Delegate, ref world: World, sheets: @Sheets, index: u32) {}

    fn objectives(ref self: Delegate, ref world: World) {}
}

#[generate_trait]
pub impl ExecutorImpl of ExecutorTrait {
    /// The executor's rules on `board`.
    fn new(board: Board) -> Executor {
        Executor { board, cache: Default::default(), placed: array![] }
    }

    /// Step 1 (§5.9): the activation of `actor`'s `slot` on `address` concluded (the pipeline set
    /// its recharge and cleared its field). Its target must still be legal (`legal`): if not,
    /// nothing happens and the costs stay paid. Else the carrier runs at `T`.
    fn conclude<L, +Levers<L>, +Drop<L>>(
        lever: @L,
        ref cache: Cache,
        ref world: World,
        sheets: @Sheets,
        board: @Board,
        actor: Actor,
        slot: u8,
        address: u16,
    ) -> Executed {
        let t = world.clock;
        let carrier = Self::carrier(@world, sheets, actor, slot);
        if !Self::legal(lever, @world, sheets, board, actor, carrier, address) {
            return Executed::Illegal;
        }
        Self::execute(lever, ref cache, ref world, sheets, board, actor, carrier, address, t)
    }

    /// The records of `content` the loads of every member and of the goblins at `picked` need
    /// (option (3)'s lever (1), CBT-05a): a member's bar skills, its held effects' skills and the
    /// potions of its held potion effects; a goblin's caste, the caste's four skills and its held
    /// effect's skill. One dictionary of the needed keys, then one pass over each list.
    fn subcontent(world: @World, picked: Span<u32>, content: @Content) -> Content {
        let mut needed: Felt252Dict<bool> = Default::default();
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            let member = world.member(m);
            let mut slot: u8 = 0;
            while slot < 8 {
                needed.insert(member.skill(slot).into(), true);
                slot += 1;
            }
            let mut slot: u8 = 0;
            while slot < 4 {
                let held = member.effect_of(slot);
                if held.potion {
                    needed.insert(member.belt_item(held.carrier).into() + POTION_KEY, true);
                } else {
                    needed.insert(held.carrier.into(), true);
                }
                slot += 1;
            }
            m += 1;
        }
        for i in picked {
            let goblin = world.goblin(*i);
            needed.insert(goblin.caste.into() + CASTE_KEY, true);
            needed.insert(goblin.effect_of().carrier.into(), true);
            let [a, b, c, d] = *(*content.castes)[goblin.caste_at].skills;
            needed.insert(a.into(), true);
            needed.insert(b.into(), true);
            needed.insert(c.into(), true);
            needed.insert(d.into(), true);
        }
        let mut skills = array![];
        for sheet in *content.skills {
            if needed.get((*sheet.id).into()) {
                skills.append(*sheet);
            }
        }
        let mut potions = array![];
        for sheet in *content.potions {
            if needed.get((*sheet.id).into() + POTION_KEY) {
                potions.append(*sheet);
            }
        }
        let mut castes = array![];
        for sheet in *content.castes {
            if needed.get((*sheet.id).into() + CASTE_KEY) {
                castes.append(*sheet);
            }
        }
        Content { skills: skills.span(), potions: potions.span(), castes: castes.span() }
    }

    /// The carrier of `actor`'s activation `slot`: a member's bar skill at its rank, a goblin's
    /// caste skill at its caste's rank.
    fn carrier(world: @World, sheets: @Sheets, actor: Actor, slot: u8) -> Carrier {
        match actor {
            Actor::Member(i) => {
                let member = world.member(i);
                let at: u32 = member.position(slot).try_into().unwrap();
                Carrier::Skill((at, member.rank(slot)))
            },
            Actor::Goblin(i) => {
                let goblin = world.goblin(i);
                let kit = (*sheets.kits)[goblin.caste_at];
                let at = *kit.skills.span()[slot.into()];
                Carrier::Skill((at, *(*sheets.castes)[goblin.caste_at].rank))
            },
        }
    }

    /// Whether `carrier`'s target is legal for `source` now (§5.9 at resolution; the action's
    /// legality, §5.3, is CBT-05b's): an entity it addresses is alive and in reach (the skill's
    /// range, a weapon's or an attack skill's: the weapon's; ENG-02's `reach`, before any arc); a
    /// tile it addresses is in reach. A carrier addressing its source is always legal.
    #[inline(never)]
    fn legal<L, +Levers<L>>(
        lever: @L,
        world: @World,
        sheets: @Sheets,
        board: @Board,
        source: Actor,
        carrier: Carrier,
        address: u16,
    ) -> bool {
        let (addressing, reach) = Self::addressing(lever, world, sheets, source, carrier);
        if addressing == target::SELF {
            return true;
        }
        let (_, from) = Self::locate(world, board, source);
        let to = if addressing == target::TILE {
            board.tile(address)
        } else {
            match Self::actor(world, address) {
                Some(actor) => {
                    let (alive, at) = Self::locate(world, board, actor);
                    if !alive {
                        return false;
                    }
                    at
                },
                None => { return false; },
            }
        };
        board.window.reach(from, to, reach)
    }

    /// What `carrier` addresses (`target::SELF`, `FOE`, `ALLY`, `TILE`: its first entry's, an
    /// attack's foe) and the reach its target must be in (the skill's range, a weapon's or an
    /// attack skill's: the weapon's). The address is read by its entry, never by its value: a
    /// `TILE` address is never taken for an entity (CBT-05a's review).
    fn addressing<L, +Levers<L>>(
        lever: @L, world: @World, sheets: @Sheets, source: Actor, carrier: Carrier,
    ) -> (u8, u8) {
        match carrier {
            Carrier::Weapon => (target::FOE, Self::weapon_range(world, sheets, source)),
            Carrier::Skill((
                at, _,
            )) => {
                let sheet = (*sheets.skills)[at];
                if *sheet.kind == skill_kind::ATTACK {
                    (target::FOE, Self::weapon_range(world, sheets, source))
                } else {
                    (lever.entry(sheets, at, 0).target, *sheet.range)
                }
            },
            Carrier::Potion((
                at, _,
            )) => (lever.potion_entry(sheets, at).target, *(*sheets.potions)[at].range),
        }
    }

    /// Whether `carrier` can reach an actor other than its source and the addressed entity: an
    /// entry whose shape is not `SINGLE` or whose target is `TILE` (`actors`' own rule). A weapon
    /// hit cannot.
    fn wide<L, +Levers<L>>(lever: @L, sheets: @Sheets, carrier: Carrier) -> bool {
        let mut entries = array![];
        match carrier {
            Carrier::Weapon => {},
            Carrier::Skill((
                at, _,
            )) => {
                for k in 0..3_u32 {
                    let entry = lever.entry(sheets, at, k);
                    if entry.is_empty() {
                        break;
                    }
                    entries.append(entry);
                }
            },
            Carrier::Potion((at, _)) => entries.append(lever.potion_entry(sheets, at)),
        }
        let mut wide = false;
        for entry in entries {
            if entry.shape != shape::SINGLE || entry.target == target::TILE {
                wide = true;
            }
        }
        wide
    }

    /// Runs `carrier` of `source` on `address` (an entity id, or a location's tile `x + 256 y` for
    /// a `TILE` carrier) at `t` (`c + 1` in the action phase, `T` in a tick): §5.14 steps 1–6.
    fn execute<L, +Levers<L>, +Drop<L>>(
        lever: @L,
        ref cache: Cache,
        ref world: World,
        sheets: @Sheets,
        board: @Board,
        source: Actor,
        carrier: Carrier,
        address: u16,
        t: u32,
    ) -> Executed {
        let mut unit = match source {
            Actor::Member(i) => Unit::M(world.member(i)),
            Actor::Goblin(i) => Unit::G(world.goblin(i)),
        };
        let (executed, mut pending) = Self::run(
            lever, ref cache, ref world, sheets, board, ref unit, source, carrier, address, t,
        );
        match unit {
            Unit::M(member) => {
                if pending.len() > 0 {
                    world.flush(Self::sorted(pending));
                }
                if let Actor::Member(i) = source {
                    world.set_member(i, member);
                }
            },
            Unit::G(goblin) => {
                let i = match source {
                    Actor::Goblin(i) => i,
                    Actor::Member(_) => core::panic_with_felt252(errors::ADDRESS),
                };
                // The source joins its carrier's one rebuild (L3).
                let gathered = if lever.gathers() && goblin.awake {
                    world.position(i)
                } else {
                    None
                };
                match gathered {
                    Some(k) => {
                        pending.append((k, goblin));
                        world.flush(Self::sorted(pending));
                    },
                    None => {
                        if pending.len() > 0 {
                            world.flush(Self::sorted(pending));
                        }
                        world.set_goblin(i, goblin);
                    },
                }
            },
        }
        executed
    }

    /// §5.14 for a source of type `S`, held apart from the world until the carrier ends; returns
    /// the awake goblins it changed, for the caller's one rebuild (L3), the source not among them.
    fn run<L, +Levers<L>, +Drop<L>, S, +Body<S>, +Drop<S>, +Copy<S>>(
        lever: @L,
        ref cache: Cache,
        ref world: World,
        sheets: @Sheets,
        board: @Board,
        ref source: S,
        actor: Actor,
        carrier: Carrier,
        address: u16,
        t: u32,
    ) -> (Executed, Pending) {
        let (entries, context, weapon_hit) = Self::read(lever, sheets, @source, carrier, t);
        let entries = entries.span();
        // 1. Guards, once, from the state now (FX-40; subject the source).
        let held = Self::guards(@source, entries);
        let ops = Self::ops(entries, @context);
        // 2. Placement: the payload waits for the trigger.
        if entries.len() > 0 && *entries[0].kind == kind::TRAP {
            let executed = if held & 1 == 1 {
                Executed::Place
            } else {
                Executed::Skipped
            };
            return (executed, array![]);
        }
        // 3. Hit modifiers whose guard held; the hit (an implicit weapon hit, index 3, or the
        // `DAMAGE` entry's) and whether its guard held.
        let (bonus, penetration) = Self::modifiers(entries, held, context.rank);
        let mut damage: Option<u32> = if weapon_hit {
            Some(3)
        } else {
            None
        };
        let mut k: u32 = 0;
        for entry in entries {
            if *entry.kind == kind::DAMAGE {
                damage = Some(k);
            }
            k += 1;
        }
        let (hit_held, class, hit_entry) = match damage {
            Some(k) => if k == 3 {
                (true, HitClass::Weapon, Default::default())
            } else {
                let class = if context.scope == 2 {
                    HitClass::Spell
                } else {
                    HitClass::Item
                };
                (held & Self::bit(k) != 0, class, *entries[k])
            },
            None => (false, HitClass::Spell, Default::default()),
        };
        // 4. The target sets, all taken now: the actor list in ascending position.
        let (x, y, source_facing) = source.place();
        let source_at = board.position(x, y);
        let list = Self::actors(@world, board, @source, actor, source_at, entries, damage, address);
        let offence = if damage.is_some() {
            source.offence(lever, class, @hit_entry, bonus, penetration, @context, sheets)
        } else {
            Self::spell(class, 0, @hit_entry, 0, 0, 0, @context)
        };
        // The source's side of its weapon hit, gathered once (the source is never the target of
        // its own hit): the target-side code is then compiled once a target type, not a pair.
        let attack = if class == HitClass::Weapon {
            Self::attack(lever, @source, t, sheets)
        } else {
            OnAttack { conditions: array![].span(), charged: 0, infliction: context.infliction }
        };
        let health = source.health();
        let max_health = source.max_health();
        let mut gain = Gain { landed: false, stolen: 0 };
        // 5. Each actor, in order.
        let mut pending: Pending = array![];
        for (position, target, bits) in list {
            let bits = *bits;
            if *target == actor {
                Self::entries(
                    lever, ref cache, ref source, actor, ops, bits, held, @context, sheets,
                );
                continue;
            }
            let shot = Shot {
                hit: bits & HIT_BIT != 0 && hit_held,
                offence,
                source_at,
                source_facing,
                target_at: *position,
            };
            let mut unit = match *target {
                Actor::Member(i) => Unit::M(world.member(i)),
                Actor::Goblin(i) => Unit::G(world.goblin(i)),
            };
            let got = Self::on(
                lever,
                ref cache,
                ref unit,
                *target,
                @shot,
                @attack,
                health,
                max_health,
                ops,
                bits,
                held,
                @context,
                sheets,
            );
            gain = Gain { landed: gain.landed || got.landed, stolen: gain.stolen + got.stolen };
            Self::put(ref world, lever, ref pending, *target, unit);
        }
        // §5.5 step 8, the source's side of its weapon hit, whether the target lives or not: each
        // charge spent, adrenaline and `hits`, `ENERGY_ON_HIT`; and the health it stole.
        if gain.landed {
            let mut charged = attack.charged;
            let mut slot: u8 = 0;
            while charged != 0 {
                if charged & 1 == 1 {
                    source.spend(slot, t);
                }
                charged /= 2;
                slot += 1;
            }
            source.landed(sheets);
            if offence.energy > 0 {
                source.energize(offence.energy.into(), sheets);
            }
        }
        source.heal(gain.stolen);
        // 6. Carrier-level effects: a shout's alert is ENG-07's (packs are chunk features); a
        // glyph and the `casts` counters are §5.3's (CBT-05b).
        (Executed::Ran, pending)
    }

    /// An actor back in the world after its turn: a member written; a goblin at 0 dies at once,
    /// in resolution order (§5.13), and is written with its carrier's one rebuild if it is awake
    /// (L3), else at once.
    #[inline(never)]
    fn put<L, +Levers<L>>(
        ref world: World, lever: @L, ref pending: Pending, actor: Actor, unit: Unit,
    ) {
        match unit {
            Unit::M(member) => { if let Actor::Member(i) = actor {
                world.set_member(i, member);
            } },
            Unit::G(mut goblin) => {
                let i = match actor {
                    Actor::Goblin(i) => i,
                    Actor::Member(_) => core::panic_with_felt252(errors::ADDRESS),
                };
                if goblin.is_alive() && goblin.health == 0 {
                    goblin.ai = ai::DEAD;
                    world.killed.append(goblin.entity);
                }
                let gathered = if lever.gathers() && goblin.awake {
                    world.position(i)
                } else {
                    None
                };
                match gathered {
                    Some(k) => pending.append((k, goblin)),
                    None => world.set_goblin(i, goblin),
                }
            },
        }
    }

    /// A trap's trigger (§5.11, §5.14): its payload (`payload`, the skill at that position
    /// without its `TRAP` entry) on the entrant alone, class `TRAP`, at strength `3 × level`
    /// (FX-28), with the guards `held` (bit `k` for entry `k`, evaluated by `guards` on the trap's
    /// source; a terrain trap's entries carry none) and the source's `infliction`.
    fn trigger<L, +Levers<L>, +Drop<L>>(
        lever: @L,
        ref cache: Cache,
        ref world: World,
        sheets: @Sheets,
        payload: u32,
        rank: u8,
        level: u8,
        held: u8,
        infliction: Infliction,
        entrant: Actor,
        t: u32,
    ) {
        let sheet = (*sheets.skills)[payload];
        let mut entries = array![];
        for k in 0..3_u32 {
            let entry = lever.entry(sheets, payload, k);
            if entry.is_empty() {
                break;
            }
            entries.append(entry);
        }
        let entries = entries.span();
        let context = Context {
            rank,
            infliction,
            enchant: 0,
            skill_kind: *sheet.kind,
            carrier: *sheet.id,
            potion: false,
            at: payload,
            scope: 3,
            t,
        };
        // Every entry's set is the entrant, whatever its addressing (§5.14); the `TRAP` entry
        // is no operation, and the hit is the `DAMAGE` entry's.
        let mut bits: u8 = 0;
        let mut hit: Option<Entry> = None;
        let mut k: u32 = 0;
        for entry in entries {
            if *entry.kind == kind::DAMAGE {
                if held & Self::bit(k) != 0 {
                    hit = Some(*entry);
                }
            } else {
                bits += Self::bit(k);
            }
            k += 1;
        }
        let ops = Self::ops(entries, @context);
        let strength = HitTrait::level_strength(level);
        let mut unit = match entrant {
            Actor::Member(i) => Unit::M(world.member(i)),
            Actor::Goblin(i) => Unit::G(world.goblin(i)),
        };
        if Self::trap(lever, ref cache, ref unit, entrant, hit, strength, @context, sheets) {
            Self::entries(lever, ref cache, ref unit, entrant, ops, bits, held, @context, sheets);
        }
        // Written at once: a trap's one entrant is no carrier's rebuild.
        let mut none: Pending = array![];
        Self::put(ref world, @Naive {}, ref none, entrant, unit);
    }

    /// A trap's hit on the entrant, if its payload holds one whose guard held: never blocked or
    /// evaded (§5.6), no arc; returns whether the entrant is alive after it.
    #[inline(never)]
    fn trap<L, +Levers<L>, +Drop<L>, T, +Body<T>, +Drop<T>, +Copy<T>>(
        lever: @L,
        ref cache: Cache,
        ref target: T,
        actor: Actor,
        hit: Option<Entry>,
        strength: u16,
        context: @Context,
        sheets: @Sheets,
    ) -> bool {
        if let Some(entry) = hit {
            let offence = Self::spell(HitClass::Trap, strength, @entry, 0, 0, 0, context);
            let shot = Shot {
                hit: true, offence, source_at: FAR, source_facing: 0, target_at: FAR,
            };
            let _ = Self::strike(
                lever, ref cache, ref target, actor, @shot, 0, 0, *context.t, sheets,
            );
        }
        target.alive()
    }

    /// One actor other than the source: the hit first, if it is in the hit's set and the hit's
    /// guard held (§5.5); stopped, nothing else of the carrier; then the other entries whose set
    /// holds it, in entry order, if it is alive and their guard held. Returns what the source
    /// gains (its weapon hit landed, the health stolen), which the caller gives it.
    #[inline(never)]
    fn on<L, +Levers<L>, +Drop<L>, T, +Body<T>, +Drop<T>, +Copy<T>>(
        lever: @L,
        ref cache: Cache,
        ref target: T,
        actor: Actor,
        shot: @Shot,
        attack: @OnAttack,
        health: u16,
        max_health: u16,
        ops: Span<Op>,
        bits: u8,
        held: u8,
        context: @Context,
        sheets: @Sheets,
    ) -> Gain {
        let mut gain = Gain { landed: false, stolen: 0 };
        if *shot.hit {
            let t = *context.t;
            if !Self::strike(
                lever, ref cache, ref target, actor, shot, health, max_health, t, sheets,
            ) {
                return gain;
            }
            if (*shot.offence).class == HitClass::Weapon {
                // §5.5 step 7, target-side, the target alive: the source's
                // `ON_ATTACK_CONDITION`s; its `LIFE_STEAL_ON_HIT`.
                gain.landed = true;
                for (condition, v) in *attack.conditions {
                    if target.alive() {
                        target.inflict(*condition, *v, attack.infliction, t, sheets);
                    }
                }
                let steal = (*shot.offence).steal;
                if steal > 0 && target.alive() {
                    let stolen = Self::min16(steal.into(), target.health());
                    target.wound(stolen);
                    gain.stolen += stolen;
                }
            }
        }
        Self::entries(lever, ref cache, ref target, actor, ops, bits, held, context, sheets);
        gain
    }

    /// The source's `ON_ATTACK_CONDITION`s held at `t`: each one's condition and value at its rank,
    /// and the slots whose charges a landed weapon hit spends.
    #[inline(never)]
    fn attack<L, +Levers<L>, S, +Body<S>>(
        lever: @L, source: @S, t: u32, sheets: @Sheets,
    ) -> OnAttack {
        let mut conditions = array![];
        let mut charged: u8 = 0;
        let mut slot: u8 = 0;
        let slots = source.slots();
        while slot < slots {
            let (effect, at) = source.effect(slot);
            if effect.deadline >= t && at != ABSENT {
                let entry = Self::holding(lever, sheets, effect.potion, at);
                if entry.kind == kind::ON_ATTACK_CONDITION {
                    conditions.append((entry.param, entry.value(effect.rank)));
                    if effect.charges > 0 {
                        charged += Self::bit(slot.into());
                    }
                }
            }
            slot += 1;
        }
        OnAttack { conditions: conditions.span(), charged, infliction: source.infliction() }
    }

    /// §5.5 steps 1–5 and the target's part of 8 and 9 on `target`, the source's health given
    /// (the `ABOVE_HALF` damage passives): the target read once into a view (`Struck`), the hit
    /// resolved on the view (`resolve`, not generic), its outcome written back once. Returns
    /// whether it landed.
    #[inline(never)]
    fn strike<L, +Levers<L>, +Drop<L>, T, +Body<T>, +Drop<T>, +Copy<T>>(
        lever: @L,
        ref cache: Cache,
        ref target: T,
        actor: Actor,
        shot: @Shot,
        health: u16,
        max_health: u16,
        t: u32,
        sheets: @Sheets,
    ) -> bool {
        let defence = target.defence(lever, ref cache, actor, t, sheets);
        let (_, _, facing) = target.place();
        let view = Struck {
            defence,
            facing,
            armor_vs: target.armor_vs((*shot.offence).damage_type, sheets),
            knocked: target.knocked(t),
            asleep: target.asleep(),
            halves: target.halves(),
            health: target.health(),
            max_health: target.max_health(),
        };
        let outcome = Self::resolve(ref cache, shot, @view, health, max_health, t);
        match outcome {
            HitOutcome::Blocked => {
                target.spend(defence.block_slot, t);
                if let Actor::Member(i) = actor {
                    lever.spent(ref cache, i);
                }
                false
            },
            HitOutcome::Landed(landed) => {
                target.wound(landed.damage);
                if landed.halved {
                    target.halved();
                }
                target.struck(sheets);
                true
            },
            _ => false,
        }
    }

    /// The hit on a target's view (§5.5 steps 1–4, not generic): the arc and the front tile from
    /// ENG-02 for a weapon hit, the `Hit` and its `HitTarget`, CBT-03a's `resolve`; the hit
    /// counted.
    #[inline(never)]
    fn resolve(
        ref cache: Cache, shot: @Shot, view: @Struck, health: u16, max_health: u16, t: u32,
    ) -> HitOutcome {
        let offence = *shot.offence;
        let defence = *view.defence;
        let weapon = offence.class == HitClass::Weapon;
        let (arc, in_front) = if weapon {
            let arc = match WindowTrait::arc(*shot.source_at, *shot.target_at, *view.facing) {
                Some(arc) => arc,
                // Never on a legal hit (`legal` asked `reach` first): two actors never share a
                // tile, and a position outside the window has no reach.
                None => Arc::Front,
            };
            (arc, WindowTrait::front(*shot.source_at, *shot.target_at, *shot.source_facing))
        } else {
            (Arc::Front, false)
        };
        let hit = Hit {
            class: offence.class,
            weapon: offence.weapon,
            melee: offence.melee,
            arc,
            in_front,
            strength: offence.strength,
            base: offence.base,
            percent: offence.percent,
            percent_above_half: offence.above,
            penetration: offence.penetration,
            health,
            max_health,
            weakened: false,
            blind: false,
        };
        let block = if defence.block > MAX_BLOCK {
            MAX_BLOCK
        } else {
            defence.block
        };
        let struck = HitTarget {
            armor: defence.armor,
            armor_effects: defence.effects,
            armor_stance: defence.stance,
            armor_enchanted: defence.enchanted,
            in_stance: defence.in_stance,
            enchanted: defence.is_enchanted,
            armor_vs: *view.armor_vs,
            block,
            evade: defence.evade,
            knocked_down: *view.knocked,
            asleep: *view.asleep,
            halve: weapon && *view.halves,
            health: *view.health,
            max_health: *view.max_health,
        };
        if cache.hits_at != t + 1 {
            cache.hits = 0;
            cache.hits_at = t + 1;
        }
        cache.hits += 1;
        hit.resolve(@struck)
    }

    /// The entries other than the hit on `target`, in entry order (§5.14 step 5): those whose set
    /// holds it (`bits`) and whose guard held (`held`), while it is alive, each applied from its
    /// `Op`.
    #[inline(never)]
    fn entries<L, +Levers<L>, +Drop<L>, T, +Body<T>, +Drop<T>, +Copy<T>>(
        lever: @L,
        ref cache: Cache,
        ref target: T,
        actor: Actor,
        ops: Span<Op>,
        bits: u8,
        held: u8,
        context: @Context,
        sheets: @Sheets,
    ) {
        let t = *context.t;
        let mut bit: u8 = 1;
        for op in ops {
            if bits & held & bit != 0 && *op.kind != kind::EMPTY {
                if !target.alive() {
                    break;
                }
                let op_kind = *op.kind;
                if op_kind == kind::HEAL {
                    target.heal((*op.v).try_into().unwrap());
                } else if op_kind == kind::CONDITION {
                    target.inflict(*op.param, *op.v, context.infliction, t, sheets);
                } else if op_kind == kind::CURE {
                    target.cure(*op.param, t);
                } else if op_kind == kind::ENERGY {
                    target.energize(*op.v, sheets);
                } else {
                    target.hold(*op.held, *context.at, *op.stance, t, sheets);
                    if let Actor::Member(i) = actor {
                        lever.held(ref cache, i);
                    }
                }
            }
            bit *= 2;
        }
    }

    /// Each entry's `Op` (R2, not generic): the value clamped to its kind's bounds, a holding
    /// entry's `Held` (`hold`); kind 0 for what applies nothing on an actor.
    #[inline(never)]
    fn ops(entries: Span<Entry>, context: @Context) -> Span<Op> {
        let mut ops = array![];
        let none: Held = Default::default();
        for entry in entries {
            let entry_kind = *entry.kind;
            let rank = *context.rank;
            let op = if entry_kind == kind::HEAL {
                let v = Self::clamp(entry.value(rank), 0, MAX_VALUE);
                Op { kind: entry_kind, param: 0, v, held: none, stance: false }
            } else if entry_kind == kind::CONDITION {
                Op {
                    kind: entry_kind,
                    param: *entry.param,
                    v: entry.value(rank),
                    held: none,
                    stance: false,
                }
            } else if entry_kind == kind::CURE {
                Op { kind: entry_kind, param: *entry.param, v: 0, held: none, stance: false }
            } else if entry_kind == kind::ENERGY {
                let v = Self::clamp(entry.value(rank), -MAX_ENERGY_VALUE, MAX_ENERGY_VALUE);
                Op { kind: entry_kind, param: 0, v, held: none, stance: false }
            } else if entry.is_holding() {
                match Self::hold(entry, context) {
                    Some(held) => Op {
                        kind: entry_kind,
                        param: 0,
                        v: 0,
                        held,
                        stance: *context.skill_kind == skill_kind::STANCE,
                    },
                    None => Op { kind: kind::EMPTY, param: 0, v: 0, held: none, stance: false },
                }
            } else {
                Op { kind: kind::EMPTY, param: 0, v: 0, held: none, stance: false }
            };
            ops.append(op);
        }
        ops.span()
    }

    /// A holding entry's `Held` (§5.7): its duration at the source's rank (an enchantment's
    /// through `ENCHANT_DURATION`), its charges (a `BLOCK`'s are its value, 1…63; an
    /// `ON_ATTACK_CONDITION`'s its field), its deadline `t + d − 1`, or `MAX_CLOCK` for a
    /// charge-only effect (§3.4); `None` for one that neither lasts nor has charges: it does not
    /// stay.
    #[inline(never)]
    fn hold(entry: @Entry, context: @Context) -> Option<Held> {
        let t = *context.t;
        let rank = *context.rank;
        let mut d = entry.duration(rank);
        if *context.skill_kind == skill_kind::ENCHANTMENT && d > 0 {
            let effective = effective_duration(d.try_into().unwrap(), (*context.enchant).into(), 0);
            d = effective.try_into().unwrap();
        }
        let block = *entry.kind == kind::BLOCK;
        let charges: u8 = if block {
            Self::clamp(entry.value(rank), 1, MAX_BLOCK.into()).try_into().unwrap()
        } else {
            *entry.charges
        };
        let deadline = if d > 0 {
            t + d.try_into().unwrap() - 1
        } else if charges > 0 && !block {
            MAX_CLOCK
        } else {
            return None;
        };
        Some(Held { carrier: *context.carrier, potion: *context.potion, charges, deadline, rank })
    }

    /// The carrier's entries, packed from the first (§2.1), what they apply with, and whether it
    /// has an implicit weapon hit (a weapon attack, an attack skill).
    #[inline(never)]
    fn read<L, +Levers<L>, S, +Body<S>>(
        lever: @L, sheets: @Sheets, source: @S, carrier: Carrier, t: u32,
    ) -> (Array<Entry>, Context, bool) {
        let mut entries = array![];
        let infliction = source.infliction();
        let enchant = source.enchant_percent();
        match carrier {
            Carrier::Weapon => {
                let context = Context {
                    rank: 0,
                    infliction,
                    enchant,
                    skill_kind: 0,
                    carrier: 0,
                    potion: false,
                    at: ABSENT,
                    scope: 0,
                    t,
                };
                (entries, context, true)
            },
            Carrier::Skill((
                at, rank,
            )) => {
                let sheet = (*sheets.skills)[at];
                for k in 0..3_u32 {
                    let entry = lever.entry(sheets, at, k);
                    if entry.is_empty() {
                        break;
                    }
                    entries.append(entry);
                }
                let attack = *sheet.kind == skill_kind::ATTACK;
                let context = Context {
                    rank,
                    infliction,
                    enchant,
                    skill_kind: *sheet.kind,
                    carrier: *sheet.id,
                    potion: false,
                    at,
                    scope: if attack {
                        1
                    } else {
                        2
                    },
                    t,
                };
                (entries, context, attack)
            },
            Carrier::Potion((
                at, belt,
            )) => {
                let entry = lever.potion_entry(sheets, at);
                if !entry.is_empty() {
                    entries.append(entry);
                }
                let context = Context {
                    rank: 0,
                    infliction,
                    enchant,
                    skill_kind: 0,
                    carrier: belt.into(),
                    potion: true,
                    at,
                    scope: 3,
                    t,
                };
                (entries, context, false)
            },
        }
    }

    /// Every entry's guard, once, from the state now (§2.4, FX-40): bit `k` set if entry `k`'s
    /// holds for its subject, the source. The MVP's entries are guarded by `BELOW_HALF` at most
    /// (Second Wind); the validators refuse the others (CBT-05a, option (ii)), which hold nowhere.
    #[inline(never)]
    fn guards<S, +Body<S>>(source: @S, entries: Span<Entry>) -> u8 {
        let health: u32 = source.health().into();
        let max: u32 = source.max_health().into();
        let mut held: u8 = 0;
        let mut bit: u8 = 1;
        for entry in entries {
            let g = *entry.guard;
            if g == guard::ALWAYS || (g == guard::BELOW_HALF && health * 2 < max) {
                held += bit;
            }
            bit *= 2;
        }
        held
    }

    /// The hit modifiers whose guard held (§5.14 step 3): `ATTACK_BONUS` (its value clamped to
    /// 0…32,767, CBT-03a's carried item) and `HIT_PENETRATION` (0…100).
    #[inline(never)]
    fn modifiers(entries: Span<Entry>, held: u8, rank: u8) -> (u32, u16) {
        let mut bonus: u32 = 0;
        let mut penetration: u16 = 0;
        let mut bit: u8 = 1;
        for entry in entries {
            if held & bit != 0 {
                let entry_kind = *entry.kind;
                if entry_kind == kind::ATTACK_BONUS {
                    bonus = Self::clamp(entry.value(rank), 0, MAX_VALUE).try_into().unwrap();
                } else if entry_kind == kind::HIT_PENETRATION {
                    let v: u16 = Self::clamp(entry.value(rank), 0, MAX_PERCENT).try_into().unwrap();
                    penetration += v;
                }
            }
            bit *= 2;
        }
        (bonus, penetration)
    }

    /// The source terms of a hit that is not a weapon's: its strength (`3 × level`, a bomb's
    /// recipe), its base, the `DAMAGE` entry's value clamped to 0…32,767 (§6, CBT-03a's carried
    /// item), its type the entry's `param`.
    #[inline(never)]
    fn spell(
        class: HitClass,
        strength: u16,
        entry: @Entry,
        percent: i16,
        above: i16,
        penetration: u16,
        context: @Context,
    ) -> Offence {
        let base = Self::clamp(entry.value(*context.rank), 0, MAX_VALUE);
        Offence {
            class,
            weapon: 0,
            melee: false,
            strength,
            base: base.try_into().unwrap(),
            percent,
            above,
            penetration,
            damage_type: *entry.param,
            steal: 0,
            energy: 0,
        }
    }

    /// The source's `PENETRATION` effects held at `t` that apply to the hit's class (§3.4,
    /// §5.4): a plain weapon hit takes scopes `WEAPON` and `ALL`, an attack skill's also
    /// `ATTACK_SKILL`, a spell `SPELL` and `ALL`; a bomb or a trap none. Each 0…100.
    #[inline(never)]
    fn penetration<L, +Levers<L>, S, +Body<S>>(
        lever: @L, source: @S, class: u8, t: u32, sheets: @Sheets,
    ) -> u16 {
        if class == 3 {
            return 0;
        }
        let mut sum: u16 = 0;
        let mut slot: u8 = 0;
        let slots = source.slots();
        while slot < slots {
            let (effect, at) = source.effect(slot);
            if effect.deadline >= t && at != ABSENT {
                let entry = Self::holding(lever, sheets, effect.potion, at);
                if entry.kind == kind::PENETRATION {
                    let s = entry.scope;
                    let applies = s == scope::ALL
                        || (class == 2 && s == scope::SPELL)
                        || (class < 2 && s == scope::WEAPON)
                        || (class == 1 && s == scope::ATTACK_SKILL);
                    if applies {
                        let v: u16 = Self::clamp(entry.value(effect.rank), 0, MAX_PERCENT)
                            .try_into()
                            .unwrap();
                        sum += v;
                    }
                }
            }
            slot += 1;
        }
        sum
    }

    /// The holding entry of a held effect's carrier at `at` (§5.14: at most one a carrier); the
    /// empty entry if it has none.
    #[inline(never)]
    fn holding<L, +Levers<L>>(lever: @L, sheets: @Sheets, potion: bool, at: u32) -> Entry {
        if potion {
            return lever.potion_entry(sheets, at);
        }
        for k in 0..3_u32 {
            let entry = lever.entry(sheets, at, k);
            if entry.is_empty() {
                break;
            }
            if entry.is_holding() {
                return entry;
            }
        }
        Default::default()
    }

    /// §5.14 step 4: every set taken now, and the actors of their union, ascending position, each
    /// with the bits of the sets that hold it (entry `k`'s bit `2^k`, the hit's `HIT_BIT`). A set
    /// is its entry's shape on its centre (the source, the addressed entity, the tile), clipped
    /// to the window (ENG-02's `shape`), its actors those its filter takes, alive; the source is
    /// never in its own hit's set. A carrier whose entries are all `SINGLE` on its source or the
    /// addressed entity reads those two actors alone; any other scans the world.
    #[inline(never)]
    fn actors<S, +Body<S>>(
        world: @World,
        board: @Board,
        source: @S,
        actor: Actor,
        source_at: u8,
        entries: Span<Entry>,
        damage: Option<u32>,
        address: u16,
    ) -> Span<(u8, Actor, u8)> {
        let mut addressed: Option<Actor> = None;
        let mut addressed_at: u8 = FAR;
        let mut addressed_alive = false;
        let mut wide = false;
        let mut targets_entity = damage == Some(3);
        for entry in entries {
            let t = *entry.target;
            if t == target::FOE || t == target::ALLY {
                targets_entity = true;
            }
            if *entry.shape != shape::SINGLE || t == target::TILE {
                wide = true;
            }
        }
        if targets_entity {
            if let Some(a) = Self::actor(world, address) {
                let (alive, at) = Self::locate(world, board, a);
                addressed = Some(a);
                addressed_at = at;
                addressed_alive = alive;
            }
        }
        let tile_at = board.tile(address);
        // The sets: `(mask, filter, bits)`.
        let mut sets: Array<(felt252, u8, u8)> = array![];
        let mut union: u256 = 0;
        let mut k: u32 = 0;
        for entry in entries {
            let entry_kind = *entry.kind;
            if entry_kind != kind::TRAP && !entry.is_hit_modifier() {
                let t = *entry.target;
                let centre = if t == target::SELF {
                    source_at
                } else if t == target::TILE {
                    tile_at
                } else {
                    addressed_at
                };
                let mask = board.window.near(*entry.shape, centre);
                let bits = if entry_kind == kind::DAMAGE {
                    HIT_BIT
                } else {
                    Self::bit(k)
                };
                sets.append((mask, *entry.filter, bits));
                union = Bits::or(union, mask.into());
            }
            k += 1;
        }
        if damage == Some(3) {
            let mask = board.window.near(shape::SINGLE, addressed_at);
            sets.append((mask, filter::FOES, HIT_BIT));
            union = Bits::or(union, mask.into());
        }
        let member_source = source.is_member();
        // The candidates: `(position, actor, is a member)`.
        let mut candidates: Array<(u8, Actor, bool)> = array![];
        if wide {
            let mut i: u32 = 0;
            while i < world.member_count() {
                let member = world.member(i);
                if member.is_alive() {
                    let (x, y, _) = MemberSnapshotTrait::place(@member);
                    candidates.append((board.position(x, y), Actor::Member(i), true));
                }
                i += 1;
            }
            for (i, state) in world.alive() {
                let (x, y, _) = GoblinPlaceTrait::at(state);
                candidates.append((board.position(x, y), Actor::Goblin(i), false));
            }
        } else {
            if source.alive() {
                candidates.append((source_at, actor, member_source));
            }
            if let Some(a) = addressed {
                if a != actor && addressed_alive {
                    let is_member = match a {
                        Actor::Member(_) => true,
                        Actor::Goblin(_) => false,
                    };
                    candidates.append((addressed_at, a, is_member));
                }
            }
        }
        let sets = sets.span();
        let mut found: Array<(u8, Actor, u8)> = array![];
        for (position, candidate, is_member) in candidates {
            if position >= FAR || !Bits::get(union, position) {
                continue;
            }
            let foe = is_member != member_source;
            let mut bits: u8 = 0;
            for (mask, set_filter, bit) in sets {
                let takes = if *set_filter == filter::FOES {
                    foe
                } else {
                    !foe
                };
                let own_hit = *bit == HIT_BIT && candidate == actor;
                if takes && !own_hit && Bits::get((*mask).into(), position) {
                    bits = bits | *bit;
                }
            }
            if bits != 0 {
                found.append((position, candidate, bits));
            }
        }
        Self::ascending(found.span())
    }

    /// `list` in ascending position (a selection: at most the window's actors, each once).
    #[inline(never)]
    fn ascending(list: Span<(u8, Actor, u8)>) -> Span<(u8, Actor, u8)> {
        let mut sorted: Array<(u8, Actor, u8)> = array![];
        let mut last: u16 = 0;
        let mut first = true;
        let mut n = 0;
        while n < list.len() {
            let mut least: u16 = 0x100;
            let mut pick = 0;
            let mut i = 0;
            for item in list {
                let (position, _, _) = *item;
                let position: u16 = position.into();
                if (first || position > last) && position < least {
                    least = position;
                    pick = i;
                }
                i += 1;
            }
            sorted.append(*list[pick]);
            last = least;
            first = false;
            n += 1;
        }
        sorted.span()
    }

    /// Pending writes by ascending position in the awake set, as `WorldTrait::flush` takes them.
    #[inline(never)]
    fn sorted(pending: Pending) -> Pending {
        let list = pending.span();
        let mut sorted: Pending = array![];
        let mut last: u32 = 0;
        let mut first = true;
        let mut n = 0;
        while n < list.len() {
            let mut least: u32 = 0xFFFFFFFF;
            let mut pick = 0;
            let mut i = 0;
            for item in list {
                let (k, _) = item;
                if (first || *k > last) && *k < least {
                    least = *k;
                    pick = i;
                }
                i += 1;
            }
            sorted.append(*list[pick]);
            last = least;
            first = false;
            n += 1;
        }
        sorted
    }

    /// The actor of entity `entity`: a member 0–7 the world holds, or a goblin it holds.
    #[inline(never)]
    fn actor(world: @World, entity: u16) -> Option<Actor> {
        if entity < FIRST_GOBLIN {
            let i: u32 = entity.into();
            return if i < world.member_count() {
                Some(Actor::Member(i))
            } else {
                None
            };
        }
        match world.find(entity) {
            Some(i) => Some(Actor::Goblin(i)),
            None => None,
        }
    }

    /// Whether the actor is alive (a member inside above 0, a goblin not dead) and its position in
    /// the window: one read of it.
    #[inline(never)]
    fn locate(world: @World, board: @Board, actor: Actor) -> (bool, u8) {
        match actor {
            Actor::Member(i) => {
                let member = world.member(i);
                let (x, y, _) = MemberSnapshotTrait::place(@member);
                (member.is_alive(), board.position(x, y))
            },
            Actor::Goblin(i) => {
                let goblin = world.goblin(i);
                let (x, y, _) = GoblinPlaceTrait::place(@goblin);
                (goblin.is_alive() && goblin.health > 0, board.position(x, y))
            },
        }
    }

    /// The range of the source's weapon (design/04: touch 1, ranged 6).
    #[inline(never)]
    fn weapon_range(world: @World, sheets: @Sheets, source: Actor) -> u8 {
        match source {
            Actor::Member(i) => {
                let (_, _, range, _, _, _) = world.member(i).weapon();
                range
            },
            Actor::Goblin(i) => *(*sheets.castes)[world.goblin(i).caste_at].weapon_range,
        }
    }

    /// Entry `k`'s bit.
    #[inline(always)]
    fn bit(k: u32) -> u8 {
        *[1_u8, 2, 4, 8].span()[k]
    }

    #[inline(always)]
    fn clamp(v: i32, low: i32, high: i32) -> i32 {
        if v < low {
            low
        } else if v > high {
            high
        } else {
            v
        }
    }

    #[inline(always)]
    fn min16(a: u16, b: u16) -> u16 {
        if a < b {
            a
        } else {
            b
        }
    }
}

/// The executor's unit tests (D-167): design/19 §10's worked examples to the unit (10.1, 10.2,
/// 10.4, 10.6–10.10), §5.14's steps and order, each kind of §3 the MVP's content uses, §5.7,
/// §5.12, §5.13, §6's edges for carriers, the guard (SPK-15's) across two hits, and L3's pairs:
/// each part levered alone against `Naive` (the totals of two tests that differ by the lever
/// alone).
#[cfg(test)]
mod tests {
    use snforge_std::{DeclareResultTrait, declare};
    use crate::interface::{IExecutorLibraryDispatcherTrait, IExecutorLibraryLibraryDispatcher};
    use crate::models::goblin::{
        Goblin, GoblinLifecycleTrait, GoblinTickTrait, GoblinTrait, GoblinWordsTrait,
    };
    use crate::models::member::{
        Member, MemberLifecycleTrait, MemberTickTrait, MemberTrait, MemberWordsTrait,
    };
    use crate::types::MAX_CLOCK;
    use crate::types::combat::{condition, damage, skill_kind, weapon};
    use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, scope, shape, target};
    use crate::types::tick::{
        Content, ContentTrait, Held, PotionSheet, Sheets, SkillSheet, ai, flag,
    };
    use crate::types::window::{Window, WindowTrait};
    use crate::types::world::fixtures::{Fixture, HOB, opaque, two};
    use crate::types::world::{Actor, World, WorldTrait};
    use super::{
        Board, BoardTrait, Cache, Carrier, DefenceTrait, Executed, ExecutorTrait, Levered, Levers,
        Naive,
    };

    // ---- Fixtures ------------------------------------------------------------------------------

    /// The member's tile: (7, 7), position 112, in the open window at the origin.
    const AT: u8 = 112;
    /// Ids of the tests' skills, appended to the fixtures' content (positions 16 on).
    const RING: u16 = 40;
    const SKULLRING: u16 = 41;
    const SIDESTEP: u16 = 42;
    const BRACE: u16 = 43;
    const CROSSING: u16 = 44;
    const SNARE: u16 = 45;
    const KNOCK: u16 = 46;
    const KINDS: u16 = 47;
    const SHIELD: u16 = 48;
    const STRIKE: u16 = 49;

    fn open() -> Window {
        WindowTrait::new(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
    }

    fn board() -> Board {
        BoardTrait::new(open(), 0, 0)
    }

    fn xy(position: u8) -> (u8, u8) {
        (position % 15, position / 15)
    }

    /// The tiles of `RING_1` around `centre`, ascending.
    fn ring(centre: u8) -> Span<u8> {
        WindowTrait::tiles(open().shape(shape::RING_1, centre))
    }

    fn entry(kind: u8, param: u8, v0: i16, v12: i16, t: u8, s: u8, f: u8) -> Entry {
        EntryTrait::new(kind, param, v0, v12, 0, 0, 0, t, s, f, 0, 0)
    }

    fn skill(id: u16, kind: u8, range: u8, entries: [Entry; 3]) -> SkillSheet {
        let [a, b, c] = entries;
        SkillSheet {
            id,
            kind,
            adrenaline: 0,
            activation: 1,
            recharge: 10,
            regen0: 0,
            regen12: 0,
            range,
            entry1: a.pack(),
            entry2: b.pack(),
            entry3: c.pack(),
        }
    }

    /// The fixtures' content (bar 1–8 at 0–7, castes 1 and 2 and their skills at 8–15), the
    /// tests'
    /// skills after, castes of armor `armor`, a sword of damage 30 (rank 12: strength 60), one
    /// potion per `potions`.
    fn content(armor: u8, potions: Span<PotionSheet>) -> Content {
        let base = Fixture::content();
        let none: Entry = Default::default();
        let mut skills = array![];
        skills.append_span(base.skills);
        let fire = entry(
            kind::DAMAGE, damage::FIRE, 80, 80, target::SELF, shape::RING_1, filter::FOES,
        );
        let burn = entry(
            kind::CONDITION, condition::BURNING, 3, 3, target::SELF, shape::RING_1, filter::FOES,
        );
        skills.append(skill(RING, skill_kind::SPELL, 0, [fire, burn, none]));
        let knock = entry(
            kind::CONDITION,
            condition::KNOCKED_DOWN,
            2,
            2,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
        );
        skills.append(skill(SKULLRING, skill_kind::ATTACK, 1, [knock, none, none]));
        let evade = EntryTrait::new(
            kind::EVADE, 1, 0, 0, 6, 6, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        skills.append(skill(SIDESTEP, skill_kind::STANCE, 0, [evade, none, none]));
        let block = EntryTrait::new(
            kind::BLOCK, 0, 1, 1, 10, 10, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        skills.append(skill(BRACE, skill_kind::STANCE, 0, [block, none, none]));
        let below = EntryTrait::new(
            kind::DAMAGE,
            damage::FIRE,
            50,
            50,
            0,
            0,
            0,
            target::SELF,
            shape::RING_1,
            filter::FOES,
            guard::BELOW_HALF,
            0,
        );
        let mend = entry(kind::HEAL, 0, 40, 40, target::SELF, shape::SINGLE, filter::ALLIES);
        skills.append(skill(CROSSING, skill_kind::SPELL, 0, [below, mend, none]));
        let trap = entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
        let earth = entry(
            kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let cripple = entry(
            kind::CONDITION, condition::CRIPPLED, 3, 3, target::FOE, shape::SINGLE, filter::FOES,
        );
        skills.append(skill(SNARE, skill_kind::TRAP, 3, [trap, earth, cripple]));
        skills.append(skill(KNOCK, skill_kind::ATTACK, 1, [knock, none, none]));
        let heal = entry(kind::HEAL, 0, 30, 30, target::SELF, shape::SINGLE, filter::ALLIES);
        let cure = entry(
            kind::CURE, condition::BLEEDING, 0, 0, target::SELF, shape::SINGLE, filter::ALLIES,
        );
        let energy = entry(kind::ENERGY, 0, 5, 5, target::SELF, shape::SINGLE, filter::ALLIES);
        skills.append(skill(KINDS, skill_kind::SKILL, 0, [heal, cure, energy]));
        let shield = EntryTrait::new(
            kind::ARMOR, 0, 30, 30, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        skills.append(skill(SHIELD, skill_kind::ENCHANTMENT, 0, [shield, none, none]));
        let pierce = entry(
            kind::HIT_PENETRATION, 0, 50, 50, target::FOE, shape::SINGLE, filter::FOES,
        );
        skills.append(skill(STRIKE, skill_kind::ATTACK, 1, [pierce, none, none]));
        let mut castes = array![];
        for caste in base.castes {
            castes
                .append(
                    crate::types::tick::CasteSheet {
                        armor,
                        weapon: weapon::SWORD,
                        weapon_damage: 30,
                        damage_type: damage::SLASHING,
                        weapon_range: 1,
                        rank: 12,
                        ..*caste,
                    },
                );
        }
        Content { skills: skills.span(), potions, castes: castes.span() }
    }

    fn sheets(armor: u8) -> Sheets {
        content(armor, array![].span()).sheets()
    }

    /// The position of skill `id` in `content`'s sheets.
    fn at(sheets: @Sheets, id: u16) -> u32 {
        let mut i = 0;
        for sheet in *sheets.skills {
            if *sheet.id == id {
                return i;
            }
            i += 1;
        }
        core::panic_with_felt252('no skill')
    }

    /// The fixtures' member at `position` facing `facing`, level 20, a weapon of `class`,
    /// damage 27, range 1, strength 60, type slashing, its requirement met.
    fn member(position: u8, facing: u8, class: u8) -> Member {
        let mut member = Fixture::member(Fixture::spec());
        place_member(ref member, position, facing);
        member.words.stats += 20 * two(64)
            + class.into() * two(88)
            + 27 * two(96)
            + 1 * two(112)
            + 60 * two(120)
            + damage::SLASHING.into() * two(160)
            + 1 * two(176);
        member
    }

    fn place_member(ref member: Member, position: u8, facing: u8) {
        let (x, y) = xy(position);
        member.words.state += x.into() * two(32) + y.into() * two(40) + facing.into() * two(48);
    }

    /// A fixtures' goblin of caste HOB at `position`, facing `facing`, health `health`.
    fn goblin(entity: u16, position: u8, facing: u8, health: u16) -> Goblin {
        let mut goblin = Fixture::goblin(entity, HOB);
        let (x, y) = xy(position);
        goblin.state += x.into() + y.into() * two(8) + facing.into() * two(16);
        goblin.health = health;
        if health > goblin.max_health {
            goblin.max_health = health;
        }
        goblin
    }

    /// The facing from `from` toward `to`.
    fn toward(from: u8, to: u8) -> u8 {
        WindowTrait::facing(from, to, 0)
    }

    fn levered() -> Levered {
        Levered {}
    }

    // ---- design/19 §10 ------------------------------------------------------------------------

    // §10.1: Cinder Ring (fire 80, Burning 3; `SELF`, `RING_1`, `FOES`) at tick 42 from the
    // Arcanist (level 20: strength 60) on goblins 57, 90 and 24 of armor 40 (x = 20: ⌊80 ×
    // 92,682 / 65,536⌋ = 113), in tile order: 57 (90 health) and 90 (100) die, `GoblinKilled` 57
    // then 90, Burning skipped on the dead; 24 goes 200 → 87 and burns to 44.
    #[test]
    #[available_gas(l2_gas: 12274320)] // ceil(1.05 × 11689828 measured)
    fn test_example_area_kills_two() {
        let sheets = sheets(40);
        let tiles = ring(AT);
        let goblins = array![
            goblin(24, *tiles[4], 0, 200), goblin(57, *tiles[0], 0, 90),
            goblin(90, *tiles[2], 0, 100),
        ];
        let mut world = Fixture::world(41, array![member(AT, 0, weapon::STAFF)], goblins);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, RING), 12));
        let executed = ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 42,
        );
        assert(executed == Executed::Ran, 'ran');
        assert(world.killed.span() == array![57, 90].span(), 'killed in tile order');
        let survivor = world.goblin(0);
        assert(survivor.health == 87, '200 - 113');
        assert(survivor.burning == 44, 'burning to 44');
        assert(world.goblin(1).burning == 0, 'nothing on the dead');
        assert(world.goblin(1).ai == ai::DEAD && world.goblin(2).ai == ai::DEAD, 'dead');
        assert(cache.hits == 3, 'three hits');
    }

    // §10.2: Skullring from the Hobgoblin's front tile at clock 51 (`t₀` 52): the implicit
    // weapon hit first (front arc, not critical: ⌊27 × 55,109 / 65,536⌋ = 22 at strength 60
    // against armor 70), then the knock-down (`D` 53) interrupts its smash (`A` 53): the field to
    // none, recharge 52 + 10 − 1 = 61. The adventurer +4 quarters, the Hobgoblin +1.
    #[test]
    #[available_gas(l2_gas: 10959012)] // ceil(1.05 × 10437154 measured)
    fn test_example_interrupt() {
        // R3: the Hobgoblin's cap is its caste's kit: its smash (24) costs 1 strike, 4 quarters.
        let base = content(70, array![].span());
        let mut skills = array![];
        for sheet in base.skills {
            let mut sheet = *sheet;
            if sheet.id == 24 {
                sheet.adrenaline = 1;
            }
            skills.append(sheet);
        }
        let sheets = Content { skills: skills.span(), ..base }.sheets();
        let front = *ring(AT)[0];
        let mut hob = goblin(40, front, toward(front, AT), 400);
        hob.start(0, 0, 3, 50);
        let mut adventurer = member(AT, toward(AT, front), weapon::MAUL);
        adventurer.adrenaline_cap = 24;
        let mut world = Fixture::world(51, array![adventurer], array![hob]);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, SKULLRING), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 40, 52,
        );
        let hob = world.goblin(0);
        assert(hob.health == 378, '400 - 22');
        assert(hob.knocked == 53, 'knocked to 53');
        assert(hob.act_slot == crate::types::combat::activation::NONE, 'interrupted');
        assert(hob.recharge(0) == 61, 'recharge 61');
        assert(hob.adrenaline == 1, 'hobgoblin +1');
        assert(world.member(0).adrenaline == 4, 'adventurer +4');
    }

    // §10.4: four effects held, none a stance; Sidestep (`EVADE`, `d` 6, a stance) at clock 80
    // evicts Warcry (deadlines 85 and 85: the lowest slot) into slot 1, `D` = 86, rank 12; Brace at
    // clock 82, a stance while one is held, takes slot 1.
    #[test]
    #[available_gas(l2_gas: 11308133)] // ceil(1.05 × 10769650 measured)
    fn test_example_eviction_and_stance() {
        let content = content(40, array![].span());
        let sheets = content.sheets();
        let mut spec = Fixture::spec();
        spec
            .effects =
                [(1, false, 90, 12), (2, false, 85, 12), (3, false, 85, 12), (4, false, 100, 12)];
        let mut adventurer = Fixture::load_member(Fixture::member_words(spec), @content);
        place_member(ref adventurer, AT, 0);
        let mut world = Fixture::world(80, array![adventurer], array![]);
        let mut cache: Cache = Default::default();
        let sidestep = Carrier::Skill((at(@sheets, SIDESTEP), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), sidestep, 0, 81,
        );
        let held = world.member(0).effect_of(1);
        assert(held.carrier == SIDESTEP && held.deadline == 86 && held.rank == 12, 'evicts warcry');
        let brace = Carrier::Skill((at(@sheets, BRACE), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), brace, 0, 83,
        );
        let held = world.member(0).effect_of(1);
        assert(held.carrier == BRACE && held.charges == 1, 'stance replaces stance');
        assert(world.member(0).effect_of(2).carrier == 3, 'others kept');
    }

    // §10.6: a goblin's knock-down in step 2 of tick 201 interrupts the Arcanist's spell (`A`
    // 202): no effect, the recharge from `t₀` = 201.
    #[test]
    #[available_gas(l2_gas: 10519157)] // ceil(1.05 × 10018244 measured)
    fn test_example_fifth_cast_interrupted() {
        let sheets = sheets(40);
        let front = *ring(AT)[0];
        let mut adventurer = member(AT, 0, weapon::STAFF);
        adventurer.start(2, 0, 2, 200);
        let foe = goblin(30, front, toward(front, AT), 100);
        let mut world = Fixture::world(201, array![adventurer], array![foe]);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, KNOCK), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Goblin(0), carrier, 0, 201,
        );
        let arcanist = world.member(0);
        assert(arcanist.act_slot == crate::types::tick::NO_SLOT, 'interrupted');
        assert(arcanist.recharge(2) == 210, 'recharge from 201');
        assert(arcanist.knocked == 202, 'knocked down');
    }

    // §10.7 (FX-40), with a `HEAL` on the source where the example has `LIFE_STEAL` (deferred,
    // option (ii)): `DAMAGE` 50 guarded `BELOW_HALF` on `RING_1`, then `HEAL` 40 on the source,
    // strength 60 = armor 60 (x = 0). In tile order A, the source, B: A 100 → 50; the source
    // heals 230 → 270, above half now; B is still hit, its guard read once: 100 → 50.
    #[test]
    #[available_gas(l2_gas: 11484699)] // ceil(1.05 × 10937808 measured)
    fn test_example_guard_crossing_half() {
        let sheets = sheets(60);
        let tiles = ring(AT);
        assert(*tiles[1] < AT && *tiles[4] > AT, 'tile order');
        let mut adventurer = member(AT, 0, weapon::STAFF);
        adventurer.health = 230;
        let foes = array![goblin(20, *tiles[1], 0, 100), goblin(21, *tiles[4], 0, 100)];
        let mut world = Fixture::world(9, array![adventurer], foes);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, CROSSING), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        assert(world.goblin(0).health == 50 && world.goblin(1).health == 50, 'both hit');
        assert(world.member(0).health == 270, 'healed across half');
    }

    // §10.9 through the pipeline: a goblin's attack skill of activation 1 started at 50 (`A` 51)
    // resolves in step 1 of 51 through the executor's hook: its weapon hit lands on the member.
    #[test]
    #[available_gas(l2_gas: 10780290)] // ceil(1.05 × 10266942 measured)
    fn test_example_activated_attack_resolves() {
        let content = content(40, array![].span());
        let sheets = content.sheets();
        let front = *ring(AT)[0];
        let mut foe = goblin(30, front, toward(front, AT), 100);
        foe.start(1, 0, 1, 50);
        let mut world = Fixture::world(50, array![member(AT, 0, weapon::SWORD)], array![foe]);
        let mut rules = ExecutorTrait::new(board());
        crate::types::world::TickTrait::tick(ref world, @sheets, ref rules);
        let hit = world.member(0);
        assert(hit.health < 400 && hit.flags & flag::HIT != 0, 'hit at 51');
        assert(rules.cache.hits == 1, 'one hit');
    }

    // §10.10, the trigger: goblin 44 (armor 40, 100 health) enters a Snare of member 0 (level 20:
    // strength 60, rank 12): the payload alone, class `TRAP`: ⌊40 × 92,682 / 65,536⌋ = 56, 100
    // →
    // 44; Crippled from 305 to 307. The placement first: the guard held, `Place`.
    #[test]
    #[available_gas(l2_gas: 9979158)] // ceil(1.05 × 9503960 measured)
    fn test_example_trap() {
        let sheets = sheets(40);
        let snare = at(@sheets, SNARE);
        let mut world = Fixture::world(
            301, array![member(AT, 0, weapon::STAFF)], array![goblin(44, 0, 0, 100)],
        );
        let mut cache: Cache = Default::default();
        let placed = ExecutorTrait::execute(
            @levered(),
            ref cache,
            ref world,
            @sheets,
            @board(),
            Actor::Member(0),
            Carrier::Skill((snare, 12)),
            7 + 256 * 9,
            302,
        );
        assert(placed == Executed::Place, 'placed');
        assert(world.goblin(0).health == 100, 'no actor at placement');
        ExecutorTrait::trigger(
            @levered(),
            ref cache,
            ref world,
            @sheets,
            snare,
            12,
            20,
            7,
            Default::default(),
            Actor::Goblin(0),
            305,
        );
        let foe = world.goblin(0);
        assert(foe.health == 44 && foe.crippled() == 307, 'triggered');
    }

    // ---- §5.14's order and edges
    // ----------------------------------------------------------------

    // SPK-15's guard across two hits in one tick (L3): the member's `BLOCK` of 1 charge, read
    // once, blocks goblin A's hit and is spent; goblin B's lands. The naive executor, reading it at
    // each hit, agrees.
    #[test]
    #[available_gas(l2_gas: 22082508)] // ceil(1.05 × 21030960 measured)
    fn test_guard_two_hits() {
        let content = content(40, array![].span());
        let sheets = content.sheets();
        let tiles = ring(AT);
        let brace = at(@sheets, BRACE);
        for naive in array![false, true] {
            let mut adventurer = member(AT, toward(AT, *tiles[0]), weapon::SWORD);
            adventurer
                .hold(
                    Held { carrier: BRACE, potion: false, charges: 1, deadline: 20, rank: 12 },
                    brace,
                    true,
                    10,
                    @sheets,
                );
            let a = goblin(30, *tiles[0], toward(*tiles[0], AT), 100);
            let b = goblin(31, *tiles[1], toward(*tiles[1], AT), 100);
            let mut world = Fixture::world(9, array![adventurer], array![a, b]);
            let mut cache: Cache = Default::default();
            for i in 0..2_u32 {
                if naive {
                    ExecutorTrait::execute(
                        @Naive {},
                        ref cache,
                        ref world,
                        @sheets,
                        @board(),
                        Actor::Goblin(i),
                        Carrier::Weapon,
                        0,
                        10,
                    );
                } else {
                    ExecutorTrait::execute(
                        @levered(),
                        ref cache,
                        ref world,
                        @sheets,
                        @board(),
                        Actor::Goblin(i),
                        Carrier::Weapon,
                        0,
                        10,
                    );
                }
                if i == 0 {
                    assert(world.member(0).health == 400, 'A blocked');
                }
            }
            assert(world.member(0).health < 400, 'B landed');
            assert(world.member(0).effect_of(0).charges == 0, 'charge spent');
        }
    }

    // A stopped hit stops the carrier on that actor (§5.5 step 2): Skullring blocked applies no
    // knock-down; the attack's adrenaline is not gained.
    #[test]
    #[available_gas(l2_gas: 10786204)] // ceil(1.05 × 10272575 measured)
    fn test_stopped_hit_stops_the_carrier() {
        let sheets = sheets(70);
        let front = *ring(AT)[0];
        let mut hob = goblin(40, front, toward(front, AT), 400);
        hob
            .hold(
                Held { carrier: BRACE, potion: false, charges: 2, deadline: 90, rank: 12 },
                at(@sheets, BRACE),
                50,
                @sheets,
            );
        let mut adventurer = member(AT, toward(AT, front), weapon::MAUL);
        adventurer.adrenaline_cap = 24;
        let mut world = Fixture::world(51, array![adventurer], array![hob]);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, SKULLRING), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 40, 52,
        );
        let hob = world.goblin(0);
        assert(hob.health == 400 && hob.knocked == 0, 'blocked: nothing');
        assert(hob.effect_of().charges == 1, 'a charge spent');
        assert(world.member(0).adrenaline == 0, 'no adrenaline');
    }

    // §5.9: a target dead or out of reach at resolution: nothing, `Illegal`.
    #[test]
    #[available_gas(l2_gas: 9870708)] // ceil(1.05 × 9400674 measured)
    fn test_target_illegal_at_resolution() {
        let sheets = sheets(40);
        let front = *ring(AT)[0];
        let mut dead = goblin(40, front, 0, 0);
        dead.ai = ai::DEAD;
        let far = goblin(41, AT + 45, 0, 100);
        let mut adventurer = member(AT, 0, weapon::SWORD);
        let world = Fixture::world(51, array![adventurer], array![dead, far]);
        let skull = Carrier::Skill((at(@sheets, SKULLRING), 12));
        assert(
            !ExecutorTrait::legal(
                @levered(), @world, @sheets, @board(), Actor::Member(0), skull, 40,
            ),
            'dead',
        );
        assert(
            !ExecutorTrait::legal(
                @levered(), @world, @sheets, @board(), Actor::Member(0), skull, 41,
            ),
            'out of reach',
        );
        assert(
            !ExecutorTrait::legal(
                @levered(), @world, @sheets, @board(), Actor::Member(0), skull, 99,
            ),
            'absent',
        );
        let ring = Carrier::Skill((at(@sheets, RING), 12));
        assert(
            ExecutorTrait::legal(@levered(), @world, @sheets, @board(), Actor::Member(0), ring, 0),
            'self',
        );
    }

    // A carrier with no actor (Cinder Ring alone): carrier-level effects only, nothing written.
    #[test]
    #[available_gas(l2_gas: 9891178)] // ceil(1.05 × 9420169 measured)
    fn test_carrier_without_actor() {
        let sheets = sheets(40);
        let mut world = Fixture::world(
            9, array![member(AT, 0, weapon::STAFF)], array![goblin(40, 0, 0, 100)],
        );
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, RING), 12));
        let executed = ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        assert(executed == Executed::Ran && world.goblin(0).health == 100, 'nothing');
        assert(cache.hits == 0, 'no hit');
    }

    // The instant kinds on the source (`HEAL` capped at max, `CURE`, `ENERGY` in thirds capped),
    // and never on a member at 0 (CBT-04's review): nothing cured or healed.
    #[test]
    #[available_gas(l2_gas: 16150585)] // ceil(1.05 × 15381509 measured)
    fn test_instant_kinds() {
        let sheets = sheets(40);
        let mut adventurer = member(AT, 0, weapon::STAFF);
        adventurer.health = 460;
        adventurer.energy = 50;
        adventurer.bleeding = 30;
        let mut world = Fixture::world(9, array![adventurer], array![]);
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, KINDS), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        let after = world.member(0);
        assert(after.health == 480, 'healed, capped');
        assert(after.bleeding == 9, 'cured: D = t - 1');
        assert(after.energy == 60, 'energy capped at max');
        let mut down = member(AT, 0, weapon::STAFF);
        down.health = 0;
        down.bleeding = 30;
        let mut world = Fixture::world(9, array![down], array![]);
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        assert(world.member(0).health == 0 && world.member(0).bleeding == 30, 'nothing at 0');
    }

    // A holding `ARMOR` (an enchantment: `ENCHANTED` holds) enters the member's defence once held:
    // the cache is updated at the hold (L3).
    #[test]
    #[available_gas(l2_gas: 10269557)] // ceil(1.05 × 9780530 measured)
    fn test_hold_updates_the_defence() {
        let sheets = sheets(40);
        let mut world = Fixture::world(9, array![member(AT, 0, weapon::STAFF)], array![]);
        let mut cache: Cache = Default::default();
        let lever = levered();
        let before = lever.defence(ref cache, @world.member(0), 0, 10, @sheets);
        assert(before.effects == 0 && !before.is_enchanted, 'none yet');
        let carrier = Carrier::Skill((at(@sheets, SHIELD), 12));
        ExecutorTrait::execute(
            @lever, ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        let after = lever.defence(ref cache, @world.member(0), 0, 10, @sheets);
        assert(after.effects == 30 && after.is_enchanted, 'armor held');
        assert(world.member(0).effect_of(0).deadline == 14, 'd 5 from 10');
    }

    // `HIT_PENETRATION` with the carrier's hit (Static Lash's kind on an attack): 50 % of armor 80
    // gone, so the hit at strength 60 meets 40.
    #[test]
    #[available_gas(l2_gas: 10742336)] // ceil(1.05 × 10230796 measured)
    fn test_hit_penetration() {
        let sheets = sheets(80);
        let front = *ring(AT)[0];
        let foe = goblin(40, front, toward(front, AT), 200);
        let mut world = Fixture::world(
            9, array![member(AT, toward(AT, front), weapon::SWORD)], array![foe],
        );
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, STRIKE), 12));
        ExecutorTrait::execute(
            @levered(), ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 40, 10,
        );
        // x = 60 − 40 = 20: ⌊27 × 92,682 / 65,536⌋ = 38.
        assert(world.goblin(0).health == 200 - 38, 'penetrated');
    }

    // §5.12: `ADRENALINE_EVERY_N` 2: the second weapon hit doubles (4, then 8), `hits` resets.
    #[test]
    #[available_gas(l2_gas: 12308174)] // ceil(1.05 × 11722070 measured)
    fn test_adrenaline_every_n() {
        let sheets = sheets(40);
        let front = *ring(AT)[0];
        let mut adventurer = member(AT, toward(AT, front), weapon::SWORD);
        adventurer.words.kit += 2 * two(160);
        adventurer.adrenaline_cap = 100;
        let foe = goblin(40, front, toward(front, AT), 400);
        let mut world = Fixture::world(9, array![adventurer], array![foe]);
        let mut cache: Cache = Default::default();
        ExecutorTrait::execute(
            @levered(),
            ref cache,
            ref world,
            @sheets,
            @board(),
            Actor::Member(0),
            Carrier::Weapon,
            40,
            10,
        );
        assert(world.member(0).adrenaline == 4 && world.member(0).hits() == 1, 'first');
        ExecutorTrait::execute(
            @levered(),
            ref cache,
            ref world,
            @sheets,
            @board(),
            Actor::Member(0),
            Carrier::Weapon,
            40,
            10,
        );
        assert(world.member(0).adrenaline == 12 && world.member(0).hits() == 0, 'doubled');
    }

    // D-179 through the executor: a sleeping goblin holding `EVADE` takes its first hit (critical)
    // and notices: Engaged.
    #[test]
    #[available_gas(l2_gas: 10732005)] // ceil(1.05 × 10220957 measured)
    fn test_asleep_first_hit() {
        let sheets = sheets(40);
        let front = *ring(AT)[0];
        let mut foe = goblin(40, front, toward(front, AT), 400);
        foe.ai = ai::ASLEEP;
        foe
            .hold(
                Held { carrier: SIDESTEP, potion: false, charges: 0, deadline: 90, rank: 12 },
                at(@sheets, SIDESTEP),
                5,
                @sheets,
            );
        let mut world = Fixture::world(
            9, array![member(AT, toward(AT, front), weapon::SWORD)], array![foe],
        );
        let mut cache: Cache = Default::default();
        ExecutorTrait::execute(
            @levered(),
            ref cache,
            ref world,
            @sheets,
            @board(),
            Actor::Member(0),
            Carrier::Weapon,
            40,
            10,
        );
        // Critical: ⌊38 × 140 / 100⌋ = 53 (x = 20).
        assert(world.goblin(0).health == 400 - 53, 'not evaded, critical');
        assert(world.goblin(0).ai == ai::ENGAGED, 'noticed');
    }

    // ---- L3's pairs ---------------------------------------------------------------------------
    // Each lever alone against the naive executor, on SPK-15's worst carriers: the member's area on
    // six awake goblins (entries and one rebuild), eight goblins' weapon hits on the member (the
    // defence). A pair is the snforge totals of two tests differing by the lever.

    #[derive(Copy, Drop, Default)]
    struct EntriesOnly {}
    #[derive(Copy, Drop, Default)]
    struct DefenceOnly {}
    #[derive(Copy, Drop, Default)]
    struct RebuildOnly {}

    impl EntriesOnlyLevers of Levers<EntriesOnly> {
        fn entry(self: @EntriesOnly, sheets: @Sheets, at: u32, k: u32) -> Entry {
            *(*sheets.entries)[3 * at + k]
        }
        fn potion_entry(self: @EntriesOnly, sheets: @Sheets, at: u32) -> Entry {
            *(*sheets.potion_entries)[at]
        }
        fn defence(
            self: @EntriesOnly,
            ref cache: Cache,
            member: @Member,
            index: u32,
            t: u32,
            sheets: @Sheets,
        ) -> super::Defence {
            DefenceTrait::member(member, t, sheets, self)
        }
        fn spent(self: @EntriesOnly, ref cache: Cache, index: u32) {}
        fn held(self: @EntriesOnly, ref cache: Cache, index: u32) {}
        fn gathers(self: @EntriesOnly) -> bool {
            false
        }
    }

    impl DefenceOnlyLevers of Levers<DefenceOnly> {
        fn entry(self: @DefenceOnly, sheets: @Sheets, at: u32, k: u32) -> Entry {
            Naive {}.entry(sheets, at, k)
        }
        fn potion_entry(self: @DefenceOnly, sheets: @Sheets, at: u32) -> Entry {
            Naive {}.potion_entry(sheets, at)
        }
        fn defence(
            self: @DefenceOnly,
            ref cache: Cache,
            member: @Member,
            index: u32,
            t: u32,
            sheets: @Sheets,
        ) -> super::Defence {
            Levered {}.defence(ref cache, member, index, t, sheets)
        }
        fn spent(self: @DefenceOnly, ref cache: Cache, index: u32) {
            Levered {}.spent(ref cache, index)
        }
        fn held(self: @DefenceOnly, ref cache: Cache, index: u32) {
            Levered {}.held(ref cache, index)
        }
        fn gathers(self: @DefenceOnly) -> bool {
            false
        }
    }

    impl RebuildOnlyLevers of Levers<RebuildOnly> {
        fn entry(self: @RebuildOnly, sheets: @Sheets, at: u32, k: u32) -> Entry {
            Naive {}.entry(sheets, at, k)
        }
        fn potion_entry(self: @RebuildOnly, sheets: @Sheets, at: u32) -> Entry {
            Naive {}.potion_entry(sheets, at)
        }
        fn defence(
            self: @RebuildOnly,
            ref cache: Cache,
            member: @Member,
            index: u32,
            t: u32,
            sheets: @Sheets,
        ) -> super::Defence {
            DefenceTrait::member(member, t, sheets, self)
        }
        fn spent(self: @RebuildOnly, ref cache: Cache, index: u32) {}
        fn held(self: @RebuildOnly, ref cache: Cache, index: u32) {}
        fn gathers(self: @RebuildOnly) -> bool {
            true
        }
    }

    /// The member's Cinder Ring on six awake goblins of 400 health (none dies), 8 awake in all.
    fn area_state() -> (World, Sheets) {
        let sheets = sheets(40);
        let tiles = ring(AT);
        let mut goblins = array![];
        let mut entity: u16 = 20;
        for tile in tiles {
            goblins.append(goblin(entity, *tile, 0, 400));
            entity += 1;
        }
        goblins.append(goblin(entity, 0, 0, 400));
        goblins.append(goblin(entity + 1, 1, 0, 400));
        (Fixture::world(9, array![member(AT, 0, weapon::STAFF)], goblins), sheets)
    }

    fn area<L, +Levers<L>, +Drop<L>>(lever: L) {
        let (mut world, sheets) = area_state();
        let mut cache: Cache = Default::default();
        let carrier = Carrier::Skill((at(@sheets, RING), 12));
        ExecutorTrait::execute(
            @lever, ref cache, ref world, @sheets, @board(), Actor::Member(0), carrier, 0, 10,
        );
        assert(cache.hits == 6, 'six hits');
    }

    /// Eight goblins around the member (six adjacent, two in reach of nothing) each hitting it with
    /// a weapon in turn: eight hits on one defence.
    fn hits_state() -> (World, Sheets) {
        let sheets = sheets(40);
        let tiles = ring(AT);
        let mut goblins = array![];
        let mut entity: u16 = 20;
        for tile in tiles {
            goblins.append(goblin(entity, *tile, toward(*tile, AT), 100));
            entity += 1;
        }
        let mut adventurer = member(AT, 0, weapon::SWORD);
        adventurer.health = 480;
        (Fixture::world(9, array![adventurer], goblins), sheets)
    }

    fn hits<L, +Levers<L>, +Drop<L>>(lever: L) {
        let (mut world, sheets) = hits_state();
        let mut cache: Cache = Default::default();
        for i in 0..6_u32 {
            ExecutorTrait::execute(
                @lever,
                ref cache,
                ref world,
                @sheets,
                @board(),
                Actor::Goblin(i),
                Carrier::Weapon,
                0,
                10,
            );
        }
        assert(cache.hits == 6, 'six hits');
    }

    #[test]
    #[available_gas(l2_gas: 11503626)] // ceil(1.05 × 10955834 measured)
    fn test_cost_area_fixture() {
        let (world, _) = area_state();
        assert(opaque(world.goblin_count()) == 8, 'fixture');
    }

    #[test]
    #[available_gas(l2_gas: 16289892)] // ceil(1.05 × 15514182 measured)
    fn test_cost_area_naive() {
        area(Naive {});
    }

    #[test]
    #[available_gas(l2_gas: 16214764)] // ceil(1.05 × 15442632 measured)
    fn test_cost_area_entries() {
        area(EntriesOnly {});
    }

    #[test]
    #[available_gas(l2_gas: 16197607)] // ceil(1.05 × 15426292 measured)
    fn test_cost_area_rebuild() {
        area(RebuildOnly {});
    }

    #[test]
    #[available_gas(l2_gas: 16130040)] // ceil(1.05 × 15361942 measured)
    fn test_cost_area_levered() {
        area(Levered {});
    }

    #[test]
    #[available_gas(l2_gas: 10921821)] // ceil(1.05 × 10401734 measured)
    fn test_cost_hits_fixture() {
        let (world, _) = hits_state();
        assert(opaque(world.goblin_count()) == 6, 'fixture');
    }

    #[test]
    #[available_gas(l2_gas: 18035737)] // ceil(1.05 × 17176892 measured)
    fn test_cost_hits_naive() {
        hits(Naive {});
    }

    #[test]
    #[available_gas(l2_gas: 16743975)] // ceil(1.05 × 15946642 measured)
    fn test_cost_hits_defence() {
        hits(DefenceOnly {});
    }

    #[test]
    #[available_gas(l2_gas: 16830978)] // ceil(1.05 × 16029502 measured)
    fn test_cost_hits_levered() {
        hits(Levered {});
    }

    // ---- Where a goblin's weapon hit goes (the parts, each six times on `hits_state`, less its
    // fixture) ----------------------------------------------------------------------------------

    // The source goblin read from the world and written back (one rebuild of the awake set).
    #[test]
    #[available_gas(l2_gas: 11461133)] // ceil(1.05 × 10915364 measured)
    fn test_cost_part_source() {
        let (mut world, _) = hits_state();
        for i in 0..6_u32 {
            let goblin = world.goblin(i);
            world.set_goblin(i, opaque(goblin));
        }
    }

    // The member target read and written back.
    #[test]
    #[available_gas(l2_gas: 11188910)] // ceil(1.05 × 10656104 measured)
    fn test_cost_part_member() {
        let (mut world, _) = hits_state();
        for _ in 0..6_u32 {
            let member = world.member(0);
            world.set_member(0, opaque(member));
        }
    }

    // §5.14 step 4: the actor list of an implicit weapon hit on the member.
    #[test]
    #[available_gas(l2_gas: 11922690)] // ceil(1.05 × 11354942 measured)
    fn test_cost_part_actors() {
        let (world, _) = hits_state();
        let tiles = ring(AT);
        for i in 0..6_u32 {
            let goblin = world.goblin(i);
            let list = ExecutorTrait::actors(
                @world, @board(), @goblin, Actor::Goblin(i), *tiles[i], array![].span(), Some(3), 0,
            );
            assert(list.len() == 1, 'the member');
        }
    }

    // The hit itself: the defence (kept), the geometry (`arc`, `front`), CBT-03a's `resolve`, the
    // damage and the hit recorded, on the member, with the goblins' offence.
    #[test]
    #[available_gas(l2_gas: 12900275)] // ceil(1.05 × 12285976 measured)
    fn test_cost_part_strike() {
        let (world, sheets) = hits_state();
        let tiles = ring(AT);
        let lever = levered();
        let mut cache: Cache = Default::default();
        let mut member = world.member(0);
        for i in 0..6_u32 {
            let goblin = world.goblin(i);
            let context = super::Context {
                rank: 12,
                infliction: Default::default(),
                enchant: 0,
                skill_kind: 0,
                carrier: 0,
                potion: false,
                at: crate::types::tick::ABSENT,
                scope: 0,
                t: 10,
            };
            let offence = super::Body::offence(
                @goblin,
                @lever,
                crate::types::combat::HitClass::Weapon,
                @Default::default(),
                0,
                0,
                @context,
                @sheets,
            );
            let shot = super::Shot {
                hit: true,
                offence,
                source_at: *tiles[i],
                source_facing: toward(*tiles[i], AT),
                target_at: AT,
            };
            ExecutorTrait::strike(
                @lever, ref cache, ref member, Actor::Member(0), @shot, 100, 280, 10, @sheets,
            );
        }
        assert(opaque(member.health) < 480, 'struck');
    }

    // ---- The own-class route (a library call a carrier), measured -----------------------------
    // A goblin's weapon hit through `ExecutorLibrary`: the words of the source and of the member,
    // and the sheets their loads need (the bar's 8 skills, the caste and its 4), in and out; six
    // calls less the fixture that builds the same arguments.

    fn class_args() -> (crate::types::world::Words, Content) {
        let (world, _) = hits_state();
        let words = crate::types::world::WorldStoreTrait::store(world);
        let full = content(40, array![].span());
        let mut skills = array![];
        for sheet in full.skills {
            if *sheet.id <= 8 || (*sheet.id >= 24 && *sheet.id <= 27) {
                skills.append(*sheet);
            }
        }
        let content = Content {
            skills: skills.span(), potions: array![].span(), castes: array![*full.castes[0]].span(),
        };
        (words, content)
    }

    /// The source goblin `i` and the member, alone.
    fn pair(words: @crate::types::world::Words, i: u32) -> crate::types::world::Words {
        crate::types::world::Words {
            clock: *words.clock,
            members: array![*words.members[0]],
            goblins: array![*words.goblins[i]],
            killed: array![],
            defeated: false,
        }
    }

    #[test]
    #[available_gas(l2_gas: 12810320)] // ceil(1.05 × 12200304 measured)
    fn test_cost_class_hits_fixture() {
        let (words, content) = class_args();
        for i in 0..6_u32 {
            let pair = pair(@words, i);
            assert(opaque(pair.goblins.len()) == 1 && content.skills.len() == 12, 'args');
        }
    }

    #[test]
    #[available_gas(l2_gas: 26060425)] // ceil(1.05 × 24819452 measured)
    fn test_cost_class_hits() {
        let class = declare("ExecutorLibrary").unwrap().contract_class();
        let library = IExecutorLibraryLibraryDispatcher { class_hash: *class.class_hash };
        let (words, content) = class_args();
        let mut cache: Cache = Default::default();
        let mut hit = 0;
        for i in 0..6_u32 {
            let pair = pair(@words, i);
            let (out, next, _) = library
                .execute(pair, content, board(), cache, Actor::Goblin(0), Carrier::Weapon, 0, 10);
            cache = next;
            if *out.members[0].state != *words.members[0].state {
                hit += 1;
            }
        }
        assert(cache.hits == 6 && hit == 6, 'six hits');
    }
}
