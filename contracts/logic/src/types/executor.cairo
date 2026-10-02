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

use hexx::board::bits::Bits;
use crate::durations::effective_duration;
use crate::models::goblin::{
    Goblin, GoblinConditionTrait, GoblinLifecycleTrait, GoblinPlaceTrait, GoblinTickTrait,
    GoblinTrait, GoblinWordsTrait,
};
use crate::models::member::{
    Member, MemberConditionTrait, MemberLifecycleTrait, MemberSnapshotTrait, MemberTickTrait,
    MemberTrait, MemberWordsTrait,
};
use crate::types::combat::{Arc, HitClass, condition, skill_kind};
use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, scope, shape, target};
use crate::types::hit::{Hit, HitOutcome, HitTarget, HitTrait, MAX_BLOCK};
use crate::types::infliction::Infliction;
use crate::types::tick::{
    ABSENT, ABSENT_LANE, CasteSheetTrait, ENERGY_THIRDS, Held, Sheets, SkillSheetTrait, ai, flag,
};
use crate::types::window::{FAR, HEIGHT, WIDTH, Window, WindowTrait, range};
use crate::types::world::{Actor, Pending, Rules, World, WorldTrait};
use crate::types::{FIRST_GOBLIN, MAX_CLOCK};

/// A value's bounds at play (design/19 §6: a value outside its kind's bounds is clamped).
const MAX_VALUE: i32 = 32767;
const MAX_ENERGY_VALUE: i32 = 255;
const MAX_PERCENT: i32 = 100;
const MAX_ARMOR_EFFECT: i32 = 255;
/// The bit of an actor's membership mask for the carrier's hit; entries 1–3 are bits 1, 2, 4.
const HIT_BIT: u8 = 8;

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
#[derive(Copy, Drop, Debug, PartialEq, Default)]
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
#[derive(Copy, Drop, Debug, PartialEq, Default)]
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
    fn energize(ref self: T, v: i32);
    /// A hit taken (§5.5 steps 5, 8, 9): a member's "hit this tick" flag; +1 quarter strike if
    /// alive; a goblin asleep or on watch notices.
    fn struck(ref self: T);
    /// A weapon hit landed (§5.12): adrenaline and the `hits` counter.
    fn landed(ref self: T);
    /// FX-19's halving spent.
    fn halved(ref self: T);
    /// Condition 1–5 for the value `v` at `t` (Knocked down through `knock`, CBT-04).
    fn inflict(ref self: T, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets);
    fn cure(ref self: T, condition: u8, t: u32);
    fn interrupt(ref self: T, t: u32, sheets: @Sheets);
    /// A holding effect through §5.7, its carrier at `at`.
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

    fn energize(ref self: Member, v: i32) {
        let energy: i32 = self.energy.into() + v * ENERGY_THIRDS.into();
        let max: i32 = self.max_energy.into();
        self.energy = ExecutorTrait::clamp(energy, 0, max).try_into().unwrap();
    }

    fn struck(ref self: Member) {
        self.flags = self.flags | flag::HIT;
        self.take_hit();
    }

    fn landed(ref self: Member) {
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

    fn interrupt(ref self: Member, t: u32, sheets: @Sheets) {
        if self.is_alive() {
            MemberTickTrait::interrupt(ref self, t, sheets);
        }
    }

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

    fn energize(ref self: Goblin, v: i32) {
        let energy: i32 = self.energy.into() + v * ENERGY_THIRDS.into();
        let max: i32 = self.max_energy.into();
        self.energy = ExecutorTrait::clamp(energy, 0, max).try_into().unwrap();
    }

    fn struck(ref self: Goblin) {
        self.take_hit();
        // §5.5 step 9: a goblin hit while asleep or on watch notices (D-179: so only its first
        // hit finds it asleep).
        if self.health > 0 && (self.ai == ai::ASLEEP || self.ai == ai::WATCH) {
            self.ai = ai::ENGAGED;
        }
    }

    fn landed(ref self: Goblin) {
        self.land_weapon_hit();
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

    fn interrupt(ref self: Goblin, t: u32, sheets: @Sheets) {
        if self.is_alive() {
            GoblinTickTrait::interrupt(ref self, t, sheets);
        }
    }

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
        let carrier = match actor {
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
        };
        if !Self::legal(lever, @world, sheets, board, actor, carrier, address) {
            return Executed::Illegal;
        }
        Self::execute(lever, ref cache, ref world, sheets, board, actor, carrier, address, t)
    }

    /// Whether `carrier`'s target is legal for `source` now (§5.9 at resolution; the action's
    /// legality, §5.3, is CBT-05b's): an entity it addresses is alive and in reach (the skill's
    /// range, a weapon's or an attack skill's: the weapon's; ENG-02's `reach`, before any arc); a
    /// tile it addresses is in reach. A carrier addressing its source is always legal.
    fn legal<L, +Levers<L>>(
        lever: @L,
        world: @World,
        sheets: @Sheets,
        board: @Board,
        source: Actor,
        carrier: Carrier,
        address: u16,
    ) -> bool {
        let (addressing, reach) = match carrier {
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
        };
        if addressing == target::SELF {
            return true;
        }
        let from = Self::position(world, board, source);
        let to = if addressing == target::TILE {
            board.tile(address)
        } else {
            match Self::actor(world, address) {
                Some(actor) => {
                    if !Self::alive(world, actor) {
                        return false;
                    }
                    Self::position(world, board, actor)
                },
                None => { return false; },
            }
        };
        board.window.reach(from, to, reach)
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
        match source {
            Actor::Member(i) => {
                let mut member = world.member(i);
                let (executed, pending) = Self::run(
                    lever,
                    ref cache,
                    ref world,
                    sheets,
                    board,
                    ref member,
                    source,
                    carrier,
                    address,
                    t,
                );
                if pending.len() > 0 {
                    world.flush(Self::sorted(pending));
                }
                world.set_member(i, member);
                executed
            },
            Actor::Goblin(i) => {
                let mut goblin = world.goblin(i);
                let (executed, mut pending) = Self::run(
                    lever,
                    ref cache,
                    ref world,
                    sheets,
                    board,
                    ref goblin,
                    source,
                    carrier,
                    address,
                    t,
                );
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
                executed
            },
        }
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
        let held = Self::guards(lever, ref cache, @source, actor, entries, t, sheets);
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
        let list = Self::actors(@world, board, @source, actor, entries, damage, address);
        let offence = if damage.is_some() {
            source.offence(lever, class, @hit_entry, bonus, penetration, @context, sheets)
        } else {
            Self::spell(class, 0, @hit_entry, 0, 0, 0, @context)
        };
        let (_, _, source_facing) = source.place();
        let source_at = Self::position(@world, board, actor);
        // 5. Each actor, in order.
        let mut pending: Pending = array![];
        for (position, target, bits) in list {
            let bits = *bits;
            if *target == actor {
                let stolen = Self::entries(
                    lever, ref cache, ref source, actor, entries, bits, held, @context, sheets,
                );
                source.heal(stolen);
                continue;
            }
            let shot = Shot {
                hit: bits & HIT_BIT != 0 && hit_held,
                offence,
                source_at,
                source_facing,
                target_at: *position,
            };
            match *target {
                Actor::Member(i) => {
                    let mut member = world.member(i);
                    Self::on(
                        lever,
                        ref cache,
                        ref source,
                        ref member,
                        *target,
                        @shot,
                        entries,
                        bits,
                        held,
                        @context,
                        sheets,
                    );
                    world.set_member(i, member);
                },
                Actor::Goblin(i) => {
                    let mut goblin = world.goblin(i);
                    Self::on(
                        lever,
                        ref cache,
                        ref source,
                        ref goblin,
                        *target,
                        @shot,
                        entries,
                        bits,
                        held,
                        @context,
                        sheets,
                    );
                    if goblin.is_alive() && goblin.health == 0 {
                        // §5.13: it dies at once, in resolution order.
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
        // 6. Carrier-level effects: a shout's alert is ENG-07's (packs are chunk features); a
        // glyph and the `casts` counters are §5.3's (CBT-05b).
        (Executed::Ran, pending)
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
        let strength = HitTrait::level_strength(level);
        match entrant {
            Actor::Member(i) => {
                let mut member = world.member(i);
                if Self::trap(
                    lever, ref cache, ref member, entrant, hit, strength, @context, sheets,
                ) {
                    let _ = Self::entries(
                        lever,
                        ref cache,
                        ref member,
                        entrant,
                        entries,
                        bits,
                        held,
                        @context,
                        sheets,
                    );
                }
                world.set_member(i, member);
            },
            Actor::Goblin(i) => {
                let mut goblin = world.goblin(i);
                if Self::trap(
                    lever, ref cache, ref goblin, entrant, hit, strength, @context, sheets,
                ) {
                    let _ = Self::entries(
                        lever,
                        ref cache,
                        ref goblin,
                        entrant,
                        entries,
                        bits,
                        held,
                        @context,
                        sheets,
                    );
                }
                if goblin.is_alive() && goblin.health == 0 {
                    goblin.ai = ai::DEAD;
                    world.killed.append(goblin.entity);
                }
                world.set_goblin(i, goblin);
            },
        }
    }

    /// A trap's hit on the entrant, if its payload holds one whose guard held: never blocked or
    /// evaded (§5.6), no arc; returns whether the entrant is alive after it.
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
    /// holds it, in entry order, if it is alive and their guard held. Life stolen heals the source.
    fn on<
        L, +Levers<L>, +Drop<L>, S, +Body<S>, +Drop<S>, +Copy<S>, T, +Body<T>, +Drop<T>, +Copy<T>,
    >(
        lever: @L,
        ref cache: Cache,
        ref source: S,
        ref target: T,
        actor: Actor,
        shot: @Shot,
        entries: Span<Entry>,
        bits: u8,
        held: u8,
        context: @Context,
        sheets: @Sheets,
    ) {
        if *shot.hit {
            if !Self::hit(lever, ref cache, ref source, ref target, actor, shot, context, sheets) {
                return;
            }
        }
        let stolen = Self::entries(
            lever, ref cache, ref target, actor, entries, bits, held, context, sheets,
        );
        source.heal(stolen);
    }

    /// §5.5: the hit on `target`, then, for a weapon hit, steps 7 and 8 on both sides. Returns
    /// false if it was stopped (blocked, evaded, missed).
    fn hit<
        L, +Levers<L>, +Drop<L>, S, +Body<S>, +Drop<S>, +Copy<S>, T, +Body<T>, +Drop<T>, +Copy<T>,
    >(
        lever: @L,
        ref cache: Cache,
        ref source: S,
        ref target: T,
        actor: Actor,
        shot: @Shot,
        context: @Context,
        sheets: @Sheets,
    ) -> bool {
        let t = *context.t;
        let offence = *shot.offence;
        let landed = Self::strike(
            lever,
            ref cache,
            ref target,
            actor,
            shot,
            source.health(),
            source.max_health(),
            t,
            sheets,
        );
        if !landed {
            return false;
        }
        if offence.class != HitClass::Weapon {
            return true;
        }
        // 7. Target-side, the target alive: the source's `ON_ATTACK_CONDITION`s; its
        // `LIFE_STEAL_ON_HIT`.
        let infliction = source.infliction();
        let mut charged: u8 = 0;
        let mut slot: u8 = 0;
        let slots = source.slots();
        while slot < slots {
            let (effect, at) = source.effect(slot);
            if effect.deadline >= t && at != ABSENT {
                let entry = Self::holding(lever, sheets, effect.potion, at);
                if entry.kind == kind::ON_ATTACK_CONDITION {
                    if target.alive() {
                        target
                            .inflict(entry.param, entry.value(effect.rank), @infliction, t, sheets);
                    }
                    if effect.charges > 0 {
                        charged += Self::bit(slot.into());
                    }
                }
            }
            slot += 1;
        }
        if offence.steal > 0 && target.alive() {
            let stolen = Self::min16(offence.steal.into(), target.health());
            target.wound(stolen);
            source.heal(stolen);
        }
        // 8. Source-side, whether the target lives or not: each charge spent, adrenaline and
        // `hits`, `ENERGY_ON_HIT`.
        let mut slot: u8 = 0;
        while charged != 0 {
            if charged & 1 == 1 {
                source.spend(slot, t);
            }
            charged /= 2;
            slot += 1;
        }
        source.landed();
        if offence.energy > 0 {
            source.energize(offence.energy.into());
        }
        true
    }

    /// §5.5 steps 1–5 and the target's part of 8 and 9 on `target`, the source's health given
    /// (the `ABOVE_HALF` damage passives): the arc and the front tile from ENG-02 for a weapon hit,
    /// CBT-03a's `resolve`, a block's charge spent, the damage applied, FX-19's halving spent, the
    /// hit recorded. Returns whether it landed.
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
        let offence = *shot.offence;
        let defence = target.defence(lever, ref cache, actor, t, sheets);
        let weapon = offence.class == HitClass::Weapon;
        let (arc, in_front) = if weapon {
            let (_, _, facing) = target.place();
            let arc = match WindowTrait::arc(*shot.source_at, *shot.target_at, facing) {
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
            armor_vs: target.armor_vs(offence.damage_type, sheets),
            block,
            evade: defence.evade,
            knocked_down: target.knocked(t),
            asleep: target.asleep(),
            halve: weapon && target.halves(),
            health: target.health(),
            max_health: target.max_health(),
        };
        if cache.hits_at != t + 1 {
            cache.hits = 0;
            cache.hits_at = t + 1;
        }
        cache.hits += 1;
        match hit.resolve(@struck) {
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
                target.struck();
                true
            },
            _ => false,
        }
    }

    /// The entries other than the hit on `target`, in entry order (§5.14 step 5): those whose set
    /// holds it (`bits`) and whose guard held (`held`), while it is alive. Returns the health its
    /// `LIFE_STEAL` took, which the caller gives the source.
    fn entries<L, +Levers<L>, +Drop<L>, T, +Body<T>, +Drop<T>, +Copy<T>>(
        lever: @L,
        ref cache: Cache,
        ref target: T,
        actor: Actor,
        entries: Span<Entry>,
        bits: u8,
        held: u8,
        context: @Context,
        sheets: @Sheets,
    ) -> u16 {
        let t = *context.t;
        let mut stolen: u16 = 0;
        let mut bit: u8 = 1;
        for entry in entries {
            if bits & held & bit != 0 {
                if !target.alive() {
                    break;
                }
                let entry_kind = *entry.kind;
                if entry_kind == kind::HEAL {
                    let v = Self::clamp(entry.value(*context.rank), 0, MAX_VALUE);
                    target.heal(v.try_into().unwrap());
                } else if entry_kind == kind::LIFE_STEAL {
                    let v = Self::clamp(entry.value(*context.rank), 0, MAX_VALUE);
                    let s = Self::min16(v.try_into().unwrap(), target.health());
                    target.wound(s);
                    stolen += s;
                } else if entry_kind == kind::CONDITION {
                    let v = entry.value(*context.rank);
                    target.inflict(*entry.param, v, context.infliction, t, sheets);
                } else if entry_kind == kind::CURE {
                    target.cure(*entry.param, t);
                } else if entry_kind == kind::ENERGY {
                    let v = entry.value(*context.rank);
                    target.energize(Self::clamp(v, -MAX_ENERGY_VALUE, MAX_ENERGY_VALUE));
                } else if entry_kind == kind::INTERRUPT {
                    target.interrupt(t, sheets);
                } else if entry.is_holding() {
                    Self::hold(ref target, entry, context, sheets);
                    if let Actor::Member(i) = actor {
                        lever.held(ref cache, i);
                    }
                }
            }
            bit *= 2;
        }
        stolen
    }

    /// A holding entry on `target` (§5.7): its duration at the source's rank (an enchantment's
    /// through `ENCHANT_DURATION`), its charges (a `BLOCK`'s are its value, 1…63; an
    /// `ON_ATTACK_CONDITION`'s its field), its deadline `t + d − 1`, or `MAX_CLOCK` for a
    /// charge-only effect (§3.4); one that neither lasts nor has charges does not stay.
    fn hold<T, +Body<T>, +Drop<T>>(
        ref target: T, entry: @Entry, context: @Context, sheets: @Sheets,
    ) {
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
            return;
        };
        let held = Held {
            carrier: *context.carrier, potion: *context.potion, charges, deadline, rank,
        };
        let stance = *context.skill_kind == skill_kind::STANCE;
        target.hold(held, *context.at, stance, t, sheets);
    }

    /// The carrier's entries, packed from the first (§2.1), what they apply with, and whether it
    /// has an implicit weapon hit (a weapon attack, an attack skill).
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
    /// holds for its subject, the source.
    fn guards<L, +Levers<L>, S, +Body<S>>(
        lever: @L,
        ref cache: Cache,
        source: @S,
        actor: Actor,
        entries: Span<Entry>,
        t: u32,
        sheets: @Sheets,
    ) -> u8 {
        let mut needed = false;
        for entry in entries {
            if *entry.guard != guard::ALWAYS {
                needed = true;
            }
        }
        let defence = if needed {
            source.defence(lever, ref cache, actor, t, sheets)
        } else {
            Default::default()
        };
        let health: u32 = source.health().into();
        let max: u32 = source.max_health().into();
        let mut held: u8 = 0;
        let mut bit: u8 = 1;
        for entry in entries {
            let g = *entry.guard;
            let holds = if g == guard::ALWAYS {
                true
            } else if g == guard::ABOVE_HALF {
                health * 2 > max
            } else if g == guard::BELOW_HALF {
                health * 2 < max
            } else if g == guard::IN_STANCE {
                defence.in_stance
            } else if g == guard::ENCHANTED {
                defence.is_enchanted
            } else {
                false
            };
            if holds {
                held += bit;
            }
            bit *= 2;
        }
        held
    }

    /// The hit modifiers whose guard held (§5.14 step 3): `ATTACK_BONUS` (its value clamped to
    /// 0…32,767, CBT-03a's carried item) and `HIT_PENETRATION` (0…100).
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
    fn actors<S, +Body<S>>(
        world: @World,
        board: @Board,
        source: @S,
        actor: Actor,
        entries: Span<Entry>,
        damage: Option<u32>,
        address: u16,
    ) -> Span<(u8, Actor, u8)> {
        let source_at = Self::position(world, board, actor);
        let mut addressed: Option<Actor> = None;
        let mut addressed_at: u8 = FAR;
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
                addressed = Some(a);
                addressed_at = Self::position(world, board, a);
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
                let mask = board.window.shape(*entry.shape, centre);
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
            let mask = board.window.shape(shape::SINGLE, addressed_at);
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
            if Self::alive(world, actor) {
                candidates.append((source_at, actor, member_source));
            }
            if let Some(a) = addressed {
                if a != actor && Self::alive(world, a) {
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

    /// Whether the actor is alive (a member inside above 0, a goblin not dead).
    fn alive(world: @World, actor: Actor) -> bool {
        match actor {
            Actor::Member(i) => world.member(i).is_alive(),
            Actor::Goblin(i) => {
                let goblin = world.goblin(i);
                goblin.is_alive() && goblin.health > 0
            },
        }
    }

    /// The actor's position in the window.
    fn position(world: @World, board: @Board, actor: Actor) -> u8 {
        let (x, y) = match actor {
            Actor::Member(i) => {
                let (x, y, _) = MemberSnapshotTrait::place(@world.member(i));
                (x, y)
            },
            Actor::Goblin(i) => {
                let (x, y, _) = GoblinPlaceTrait::place(@world.goblin(i));
                (x, y)
            },
        };
        board.position(x, y)
    }

    /// The range of the source's weapon (design/04: touch 1, ranged 6).
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
