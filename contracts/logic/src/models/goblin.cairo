//! A goblin in a world tick (CBT-02; design/19 §5, §7.2): its stored words, as `Instances` passes
//! them to the tick's library call, and its view inside the call (`models::index::GoblinWords`,
//! `Goblin`). Its behaviour: loading the hot fields once and storing them back as deltas
//! (`GoblinTrait`), the fields read and written in the words directly (`GoblinWordsTrait`), the
//! activation's rules (`GoblinTickTrait`) and the lifecycle's (`GoblinLifecycleTrait`). The words'
//! layouts are the ephemeral package's, which owns the storage; the offsets below are ENG-01's
//! frozen ones, pinned by the ephemeral package's `test_tick_words`.

use crate::helpers::tick::{TickAssert, TickMathTrait, errors as tick_errors};
use crate::packing::{
    N16, N24, N28, N56, N6, N8, P108, P16, P28, P56, P8, P80, P84, field, limbs, peel,
};
use crate::types::combat::{activation, condition, skill_kind};
use crate::types::infliction::{Infliction, InflictionTrait};
use crate::types::tick::{
    ABSENT, CasteSheetTrait, Held, Index, IndexTrait, Kit, MISSING, REGEN_OFFSET, Sheets,
    SheetsTrait, SkillSheetTrait, ai,
};

pub use super::index::{Goblin, GoblinWords};

const F8: felt252 = 0x100;
const F24: felt252 = 0x1000000;
const F28: felt252 = 0x10000000;
const F32: felt252 = 0x100000000;
const F52: felt252 = 0x10000000000000;
const F80: felt252 = 0x100000000000000000000;
const F128: felt252 = 0x100000000000000000000000000000000;
const F156: felt252 = 0x1000000000000000000000000000000000000000;
const F184: felt252 = 0x10000000000000000000000000000000000000000000000;
const F212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const N112: NonZero<u128> = 0x10000000000000000000000000000;
const F108: felt252 = 0x1000000000000000000000000000;
/// The hot regions `store` rewrites: `GoblinState` 24–63 (AI state … adrenaline) and
/// `GoblinTimers` 0–107 (the activation, bleeding, poison).
const N40: NonZero<u128> = 0x10000000000;
const N108: NonZero<u128> = 0x1000000000000000000000000000;
const F240: felt252 = 0x1000000000000000000000000000000000000000000000000000000000000;
const F246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

pub mod errors {
    /// An effect's `REGENERATION` pips beyond an `i8` (the kind's bound is ±10).
    pub const REGEN: felt252 = 'goblin: regeneration above i8';
    pub const NO_SKILL: felt252 = 'tick: skill not in content';
}

#[generate_trait]
pub impl GoblinAssert of GoblinAssertTrait {
    /// An effect's `REGENERATION` pips fit an `i8` (design/19 §3.1 bounds the kind to ±10).
    #[inline(always)]
    fn assert_pips(pips: i32) {
        assert(pips >= -128 && pips <= 127, errors::REGEN);
    }

    /// Its caste's skills are all in the content (the kit found each, `IndexTrait::kit`).
    #[inline(always)]
    fn assert_kit(kit: @Kit) {
        let [a, b, c, d] = *kit.skills;
        assert(a != MISSING && b != MISSING && c != MISSING && d != MISSING, errors::NO_SKILL);
    }
}

#[generate_trait]
pub impl GoblinImpl of GoblinTrait {
    /// The hot fields of a goblin's words, in `Goblin`'s order (ai … effect deadline), and its
    /// level and effect `(skill, rank)`. Each limb is read in one pass from its low bits, one
    /// division a field (CBT-02b, lever (b)).
    fn hot(
        state: felt252, timers: felt252,
    ) -> (u8, u16, u8, u8, u16, u8, u16, u32, u32, u32, u32, u32, u32, u8, u16, u8) {
        let (low, _) = limbs(state);
        // Bits 0–23 (position, facing) are not read.
        let (mut rest, _) = DivRem::div_rem(low, N24);
        let ai = peel(ref rest, N8);
        let health = peel(ref rest, N16);
        let energy = peel(ref rest, N8);
        let adrenaline = peel(ref rest, N8);
        let caste = peel(ref rest, N16);
        let level = peel(ref rest, N8);
        let (tlow, thigh) = limbs(timers);
        let mut rest = tlow;
        let act_slot = peel(ref rest, N8);
        let act_target = peel(ref rest, N16);
        let act_deadline = peel(ref rest, N28);
        let bleeding = peel(ref rest, N28);
        let poison = peel(ref rest, N28);
        let effect = peel(ref rest, N16);
        let mut rest = thigh;
        let burning = peel(ref rest, N28);
        let _crippled = peel(ref rest, N28);
        let knocked = peel(ref rest, N28);
        let effect_deadline = peel(ref rest, N28);
        let _charges = peel(ref rest, N6);
        // What is left is the rank, bits 246–249: `LIVE` is removed and nothing lies above.
        (
            ai.try_into().unwrap(),
            health.try_into().unwrap(),
            energy.try_into().unwrap(),
            adrenaline.try_into().unwrap(),
            caste.try_into().unwrap(),
            act_slot.try_into().unwrap(),
            act_target.try_into().unwrap(),
            act_deadline.try_into().unwrap(),
            bleeding.try_into().unwrap(),
            poison.try_into().unwrap(),
            burning.try_into().unwrap(),
            knocked.try_into().unwrap(),
            effect_deadline.try_into().unwrap(),
            level.try_into().unwrap(),
            effect.try_into().unwrap(),
            rest.try_into().unwrap(),
        )
    }

    /// A goblin from its words, with what it derives once from its caste and level: its maxima,
    /// regeneration and its effect's `REGENERATION` pips; its caste's position and its adrenaline
    /// cap, its caste's kit's (CBT-02d: the index reads each id once, where a lookup scanned the
    /// content's lists for the caste, the effect and the four caste skills).
    fn load(words: GoblinWords, ref index: Index, sheets: @Sheets) -> Goblin {
        let (
            ai,
            health,
            energy,
            adrenaline,
            caste,
            act_slot,
            act_target,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
            effect_deadline,
            level,
            effect,
            rank,
        ) =
            Self::hot(
            words.state, words.timers,
        );
        let caste_at = index.caste(caste);
        let sheet = (*sheets.castes)[caste_at];
        let kit = (*sheets.kits)[caste_at];
        GoblinAssert::assert_kit(kit);
        let (effect_at, effect_regen) = if effect == 0 {
            (ABSENT, 0)
        } else {
            let at = index.skill(effect);
            (at, (*sheets.skills)[at].regen(rank))
        };
        GoblinAssert::assert_pips(effect_regen);
        Goblin {
            entity: words.entity,
            awake: words.awake,
            ai,
            health,
            energy,
            adrenaline,
            caste,
            act_slot,
            act_target,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
            effect_deadline,
            effect_regen: effect_regen.try_into().unwrap(),
            max_health: sheet.max_health(level).try_into().unwrap(),
            caste_at,
            effect_at,
            state: words.state,
            timers: words.timers,
        }
    }

    /// Its words, the hot fields written back (its effect's skill, charges and rank are the
    /// executor's to write). The hot fields lie in four regions of the words; each region is
    /// rewritten whole, by the difference between its new value and the one the words hold
    /// (CBT-02b, lever (b): six divisions, where a field at a time took twenty-six).
    fn store(self: @Goblin) -> GoblinWords {
        let (low, _) = limbs(*self.state);
        let (above, _) = DivRem::div_rem(low, N24);
        let (_, old) = DivRem::div_rem(above, N40);
        let new: felt252 = (*self.ai).into()
            + (*self.health).into() * F8
            + (*self.energy).into() * F24
            + (*self.adrenaline).into() * F32;
        let state = *self.state + (new - old.into()) * F24;
        let (tlow, thigh) = limbs(*self.timers);
        let (_, old_low) = DivRem::div_rem(tlow, N108);
        let new_low: felt252 = (*self.act_slot).into()
            + (*self.act_target).into() * F8
            + (*self.act_deadline).into() * F24
            + (*self.bleeding).into() * F52
            + (*self.poison).into() * F80;
        let (above, old_burning) = DivRem::div_rem(thigh, N28);
        let (above, _) = DivRem::div_rem(above, N28);
        let (_, old_tail) = DivRem::div_rem(above, N56);
        let new_tail: felt252 = (*self.knocked).into() + (*self.effect_deadline).into() * F28;
        let timers = *self.timers
            + (new_low - old_low.into())
            + ((*self.burning).into() - old_burning.into()) * F128
            + (new_tail - old_tail.into()) * F184;
        GoblinWords { entity: *self.entity, awake: *self.awake, state, timers }
    }

    /// Alive: neither dead nor looted.
    /// Its caste's health regeneration, signed pips (`Caste.health_regen` − 10).
    #[inline(always)]
    fn health_regen(self: @Goblin, sheets: @Sheets) -> i8 {
        let regen: i32 = (*(*sheets.castes)[*self.caste_at].health_regen).into();
        (regen - REGEN_OFFSET).try_into().unwrap()
    }

    /// Its caste's max energy, in thirds.
    #[inline(always)]
    fn max_energy(self: @Goblin, sheets: @Sheets) -> u8 {
        *(*sheets.castes)[*self.caste_at].energy * 3
    }

    /// Its caste's energy regeneration, thirds a tick.
    #[inline(always)]
    fn energy_regen(self: @Goblin, sheets: @Sheets) -> u8 {
        *(*sheets.castes)[*self.caste_at].energy_regen
    }

    /// Its caste's adrenaline cap, in quarters (its kit's).
    #[inline(always)]
    fn adrenaline_cap(self: @Goblin, sheets: @Sheets) -> u8 {
        *(*sheets.kits)[*self.caste_at].cap
    }

    #[inline(always)]
    fn is_alive(self: @Goblin) -> bool {
        *self.ai < ai::DEAD
    }

    /// The recharge deadline of caste skill 0–3.
    fn recharge(self: @Goblin, slot: u8) -> u32 {
        let (_, high) = limbs(*self.state);
        field(high, *[1, P28, P56, P84].span()[slot.into()], P28).try_into().unwrap()
    }

    fn set_recharge(ref self: Goblin, slot: u8, deadline: u32) {
        let shift = *[F128, F156, F184, F212].span()[slot.into()];
        let old = self.recharge(slot);
        self.state += TickMathTrait::delta(old.into(), deadline.into(), shift);
    }
}

/// The fields of a goblin's words that are not hot, written by the lifecycle rules.
#[generate_trait]
pub impl GoblinWordsImpl of GoblinWordsTrait {
    /// Crippled's deadline (`GoblinTimers` bits 156–183).
    fn crippled(self: @Goblin) -> u32 {
        let (_, high) = limbs(*self.timers);
        field(high, P28, P28).try_into().unwrap()
    }

    fn set_crippled(ref self: Goblin, deadline: u32) {
        let old = self.crippled();
        self.timers += TickMathTrait::delta(old.into(), deadline.into(), F156);
    }

    /// Its one held effect (a skill; a goblin holds no potion); its deadline is the hot field.
    fn effect_of(self: @Goblin) -> Held {
        let (low, high) = limbs(*self.timers);
        let (tail, _) = DivRem::div_rem(high, N112);
        // Bits 240–245 the charges, 246–249 the rank: nothing lies above it once `LIVE` is off.
        let (rank, charges) = DivRem::div_rem(tail, N6);
        Held {
            carrier: field(low, P108, P16).try_into().unwrap(),
            potion: false,
            charges: charges.try_into().unwrap(),
            deadline: *self.effect_deadline,
            rank: rank.try_into().unwrap(),
        }
    }

    /// Writes its one effect, with its `REGENERATION` pips.
    fn set_effect(ref self: Goblin, held: Held, pips: i8) {
        let old = self.effect_of();
        self.timers += TickMathTrait::delta(old.carrier.into(), held.carrier.into(), F108)
            + TickMathTrait::delta(old.charges.into(), held.charges.into(), F240)
            + TickMathTrait::delta(old.rank.into(), held.rank.into(), F246);
        self.effect_deadline = held.deadline;
        self.effect_regen = pips;
    }
}

/// The fields of a goblin's words its hits read (CBT-05a; ENG-01 §3.2 offsets).
#[generate_trait]
pub impl GoblinPlaceImpl of GoblinPlaceTrait {
    /// Its tile and facing (`GoblinState` x 0–7, y 8–15, facing 16–23).
    #[inline(always)]
    fn place(self: @Goblin) -> (u8, u8, u8) {
        Self::at(*self.state)
    }

    /// The tile and facing a `GoblinState` word holds.
    fn at(state: felt252) -> (u8, u8, u8) {
        let (low, _) = limbs(state);
        let mut rest = low;
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        (x.try_into().unwrap(), y.try_into().unwrap(), facing.try_into().unwrap())
    }

    /// Its level (`GoblinState` 80–87, the pack's).
    fn level(self: @Goblin) -> u8 {
        let (low, _) = limbs(*self.state);
        field(low, P80, P8).try_into().unwrap()
    }
}

#[generate_trait]
pub impl GoblinTickImpl of GoblinTickTrait {
    /// Step 2 of `T`: a caste skill with activation `n ≥ 1` starts, `A = T + n` (§5.2).
    fn start(ref self: Goblin, slot: u8, target: u16, n: u16, t: u32) {
        let n: u32 = if n == 0 {
            1
        } else {
            n.into()
        };
        self.act_slot = slot;
        self.act_target = target;
        self.act_deadline = t + n;
    }

    /// Step 2 of `T`: an act of tick cost `k` that lands now (a weapon attack, an instant attack
    /// skill, a crippled move of cost 2): recovering until `B = T + k − 1` if `k > 1` (FX-15).
    fn recover(ref self: Goblin, k: u8, t: u32) {
        if k > 1 {
            self.act_slot = activation::RECOVERING;
            self.act_target = 0;
            self.act_deadline = t + k.into() - 1;
        }
    }

    /// An instant caste skill of `slot` used in step 2 of `T`: its recharge counts from `T`.
    fn use_instant(ref self: Goblin, slot: u8, t: u32, sheets: @Sheets) {
        let r = *sheets.caste_skill(self.caste_at, slot).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(t, r));
    }

    /// Step 1 at `A`: the activation ends, its recharge counts from `A` (FX-2); an attack skill
    /// whose weapon costs `k ≥ n + 2` recovers until `B = A + k − n − 1` (FX-15, §10.9).
    /// Returns its slot and target for the executor.
    fn conclude(ref self: Goblin, sheets: @Sheets) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let a = self.act_deadline;
        let kit = (*sheets.kits)[self.caste_at];
        let skill = (*sheets.skills)[*kit.skills.span()[slot.into()]];
        self.set_recharge(slot, TickMathTrait::recharge_deadline(a, *skill.recharge));
        let k: u32 = (*kit.weapon_ticks).into();
        let n: u32 = (*skill.activation).into();
        if *skill.kind == skill_kind::ATTACK && k >= n + 2 {
            self.act_slot = activation::RECOVERING;
            self.act_target = 0;
            self.act_deadline = a + k - n - 1;
        } else {
            self.clear();
        }
        (slot, target)
    }

    /// Step 1 of `T > A` for a goblin frozen at `A` (FX-29): the activation lapsed at `A`, as an
    /// interrupt dated `A`; its recharge `A + r − 1` is kept if a later one is stored.
    fn lapse(ref self: Goblin, sheets: @Sheets) {
        let slot = self.act_slot;
        let r = *sheets.caste_skill(self.caste_at, slot).recharge;
        let deadline = TickMathTrait::recharge_deadline(self.act_deadline, r);
        if deadline > self.recharge(slot) {
            self.set_recharge(slot, deadline);
        }
        self.clear();
    }

    /// Interrupted at `t₀` (§5.9): the field goes to none, the recharge counts from `t₀`
    /// (FX-2). Nothing unless activating (a recovery is not an activation).
    fn interrupt(ref self: Goblin, t0: u32, sheets: @Sheets) {
        let slot = self.act_slot;
        if slot > activation::LAST_SLOT {
            return;
        }
        let r = *sheets.caste_skill(self.caste_at, slot).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(t0, r));
        self.clear();
    }

    /// Step 3 at tick `t` (§5.8) for an awake goblin alive: health by its caste's pips, its
    /// effect's and its conditions'; energy by the caste's pips in thirds; adrenaline decay when
    /// not Engaged (D-157 E).
    fn regenerate(ref self: Goblin, t: u32, sheets: @Sheets) {
        let mut pips: i32 = self.health_regen(sheets).into()
            + TickMathTrait::degeneration(self.bleeding, self.poison, self.burning, t)
            + TickMathTrait::effect_pips(self.effect_regen, self.effect_deadline, t);
        self.health = TickMathTrait::heal(self.health, pips, self.max_health);
        let energy: u16 = self.energy.into() + self.energy_regen(sheets).into();
        let max = self.max_energy(sheets);
        self.energy = if energy > max.into() {
            max
        } else {
            energy.try_into().unwrap()
        };
        if self.ai != ai::ENGAGED {
            let decayed = TickMathTrait::decay(self.adrenaline.into());
            self.adrenaline = decayed.try_into().unwrap();
        }
    }

    fn clear(ref self: Goblin) {
        self.act_slot = activation::NONE;
        self.act_target = 0;
        self.act_deadline = 0;
    }
}

/// The same lifecycle rules on a goblin (§5.7, §5.12): a dead goblin takes nothing; its one slot
/// is refreshed by its carrier or replaced (FX-13); its gains capped at its caste's cap.
#[generate_trait]
pub impl GoblinLifecycleImpl of GoblinLifecycleTrait {
    fn inflict(ref self: Goblin, condition: u8, t0: u32, d: u32) {
        if !self.is_alive() {
            return;
        }
        let old = self.condition(condition);
        self.set_condition(condition, TickMathTrait::refreshed(old, t0, d));
    }

    /// `CURE` at `t0` (§3.2): a duration of 0, `D = t0 − 1`; an absent condition, or a dead
    /// goblin, nothing (§6).
    fn cure(ref self: Goblin, condition: u8, t0: u32) {
        if !self.is_alive() {
            return;
        }
        let old = self.condition(condition);
        self.set_condition(condition, TickMathTrait::cured(old, t0));
    }

    fn condition(self: @Goblin, condition: u8) -> u32 {
        TickAssert::assert_condition(condition);
        if condition == condition::BLEEDING {
            *self.bleeding
        } else if condition == condition::POISON {
            *self.poison
        } else if condition == condition::BURNING {
            *self.burning
        } else if condition == condition::CRIPPLED {
            self.crippled()
        } else {
            *self.knocked
        }
    }

    fn set_condition(ref self: Goblin, condition: u8, deadline: u32) {
        if condition == condition::BLEEDING {
            self.bleeding = deadline;
        } else if condition == condition::POISON {
            self.poison = deadline;
        } else if condition == condition::BURNING {
            self.burning = deadline;
        } else if condition == condition::CRIPPLED {
            self.set_crippled(deadline);
        } else {
            self.knocked = deadline;
        }
    }

    /// A holding effect on its one slot at `t` (§5.7): the same carrier held keeps the later
    /// deadline, the new one on a tie (FX-30); anything else replaces it (FX-13).
    fn hold(ref self: Goblin, held: Held, at: u32, t: u32, sheets: @Sheets) {
        if !self.is_alive() {
            return;
        }
        let old = self.effect_of();
        if old.deadline >= t && old.carrier == held.carrier && held.deadline < old.deadline {
            return;
        }
        let pips: i32 = (*sheets.skills)[at].regen(held.rank);
        GoblinAssert::assert_pips(pips);
        self.set_effect(held, pips.try_into().unwrap());
        self.effect_at = at;
    }

    /// Adrenaline gained, in quarters (§5.12), capped at its caste's cap (at most 252).
    fn gain_adrenaline(ref self: Goblin, quarters: u8, sheets: @Sheets) {
        let cap = self.adrenaline_cap(sheets);
        if self.adrenaline < cap {
            let gained: u16 = self.adrenaline.into() + quarters.into();
            let cap: u16 = cap.into();
            self.adrenaline = TickMathTrait::min16(gained, cap).try_into().unwrap();
        }
    }

    /// A weapon hit landed: 4 quarters (no `hits` counter: a member's modifier).
    fn land_weapon_hit(ref self: Goblin, sheets: @Sheets) {
        self.gain_adrenaline(4, sheets);
    }

    /// A hit taken while alive: 1 quarter.
    fn take_hit(ref self: Goblin, sheets: @Sheets) {
        if self.is_alive() && self.health > 0 {
            self.gain_adrenaline(1, sheets);
        }
    }
}

/// The five conditions' rules on a goblin (CBT-04; design/19 §3.2, §5.2, §5.6, §5.7, §5.9),
/// for the executor (CBT-05), the hit (CBT-03a, through booleans) and its AI's moves (ENG-07).
/// Every `t0` is the tick the rule acts at: `c + 1` in the action phase at clock `c`, `T` in a tick
/// (§5.1). Its source's `Infliction` is the inflicting source's: a member's kit, or none.
#[generate_trait]
pub impl GoblinConditionImpl of GoblinConditionTrait {
    /// A `CONDITION` entry (or an `ON_ATTACK_CONDITION`'s) applied at `t0`: condition 1–4 for
    /// the value `v`, through the source's `Infliction` (`effective_duration`), refreshed by
    /// `max` (FX-6); a dead goblin takes nothing. Knocked down is `knock`'s: the executor
    /// dispatches on the entry's condition (SPK-15's L2, D-172). Written in place, as the
    /// member's: one branch writes the condition's field, Crippled's word read once.
    fn apply(ref self: Goblin, condition: u8, v: i32, source: @Infliction, t0: u32) {
        if !self.is_alive() {
            return;
        }
        let d = source.duration(condition, v);
        if condition == condition::BLEEDING {
            self.bleeding = TickMathTrait::refreshed(self.bleeding, t0, d);
        } else if condition == condition::POISON {
            self.poison = TickMathTrait::refreshed(self.poison, t0, d);
        } else if condition == condition::BURNING {
            self.burning = TickMathTrait::refreshed(self.burning, t0, d);
        } else {
            assert(condition == condition::CRIPPLED, tick_errors::KNOCK);
            // `GoblinWordsTrait::crippled`, read here: bits 156–183 of `GoblinTimers`.
            let (_, high) = limbs(self.timers);
            let old: u32 = field(high, P28, P28).try_into().unwrap();
            let new = TickMathTrait::refreshed(old, t0, d);
            self.timers += TickMathTrait::delta(old.into(), new.into(), F156);
        }
    }

    /// Knocked down for the value `v` at `t0`, through the source's `Infliction`
    /// (`KNOCKDOWN_FLAT`), refreshed by `max` (FX-31); a dead goblin takes nothing. It interrupts
    /// the activation (§5.9): its field goes to none, the recharge counts from `t0`; a recovery
    /// is kept. A knock-down that does not lengthen a held one interrupts too; it finds no
    /// activation (a knocked-down goblin skips step 2, and the first knock-down interrupted it).
    fn knock(ref self: Goblin, v: i32, source: @Infliction, t0: u32, sheets: @Sheets) {
        if !self.is_alive() {
            return;
        }
        let d = source.duration(condition::KNOCKED_DOWN, v);
        self.knocked = TickMathTrait::refreshed(self.knocked, t0, d);
        self.interrupt(t0, sheets);
    }

    /// Condition 1–5 held at `t0` (`t0 ≤ D`).
    #[inline(always)]
    fn holds(self: @Goblin, condition: u8, t0: u32) -> bool {
        TickMathTrait::held(self.condition(condition), t0)
    }

    /// Not knocked down at `t`: it may act in step 2 (§5.2; the pipeline's step 2 reads the same,
    /// `TickTrait::act`).
    #[inline(always)]
    fn can_act(self: @Goblin, t: u32) -> bool {
        !TickMathTrait::held(*self.knocked, t)
    }

    /// Knocked down at `t0`: a weapon hit on it is critical from any arc (§3.2), for CBT-03a.
    #[inline(always)]
    fn takes_critical(self: @Goblin, t0: u32) -> bool {
        TickMathTrait::held(*self.knocked, t0)
    }

    /// Not knocked down at `t0`: it may block or evade (§5.6, FX-7), for CBT-03a.
    #[inline(always)]
    fn can_defend(self: @Goblin, t0: u32) -> bool {
        !TickMathTrait::held(*self.knocked, t0)
    }

    /// The ticks its move of one tile costs in step 2 of `t`: 2 while Crippled, unless `movement`
    /// (a `MOVEMENT` effect held, FX-18), else 1 (§3.2, FX-15). ENG-07 passes it to `recover`: a
    /// crippled move recovers until `B = T + 1` (§5.2).
    #[inline(always)]
    fn move_ticks(self: @Goblin, t: u32, movement: bool) -> u8 {
        TickMathTrait::move_ticks(self.crippled(), t, movement)
    }
}

/// A goblin's unit tests (CBT-02, CBT-02d, CBT-04; D-167): its load and store, its decoder, its
/// lifecycle rules, its conditions' rules, its checks.
#[cfg(test)]
mod tests {
    use crate::types::combat::{activation, condition, skill_kind};
    use crate::types::infliction::{Infliction, InflictionTrait};
    use crate::types::tick::{CasteSheet, Content, ContentTrait, Sheets, SkillSheet, ai};
    use crate::types::world::TickTrait;
    use crate::types::world::fixtures::{
        Fixture, HOB, LIVE, RUNT, SMASH, Script, activation_of, opaque, two,
    };
    use super::{
        Goblin, GoblinAssert, GoblinConditionTrait, GoblinLifecycleTrait, GoblinTickTrait,
        GoblinTrait, GoblinWords, GoblinWordsTrait,
    };

    // CBT-04, applying (§5.7): every condition 1–5 lands in its field and survives the words; a
    // member's kit lengthens its own condition and the knock-down (Bleeding 20 +33 %: 26 ticks,
    // D = 35; Knocked down 2 + 1: D = 12); no passive, the value itself.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 1386725)] // ceil(1.05 × 1320690 measured)
    fn test_goblin_apply() {
        let sheets = Fixture::sheets();
        let rending = Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 };
        let none: Infliction = Default::default();
        let mut goblin = Fixture::goblin(9, HOB);
        goblin.apply(condition::BLEEDING, 20, @rending, 10);
        goblin.apply(condition::POISON, 20, @rending, 10);
        goblin.apply(condition::BURNING, 3, @none, 10);
        goblin.apply(condition::CRIPPLED, 4, @none, 10);
        goblin.knock(2, @rending, 10, @sheets);
        assert(goblin.bleeding == 35 && goblin.poison == 29 && goblin.burning == 12, 'pips');
        assert(goblin.crippled() == 13 && goblin.knocked == 12, 'crippled, knocked');
        let words = goblin.store();
        let again = Fixture::load_goblin(words, @Fixture::content());
        assert(again.bleeding == 35 && again.crippled() == 13 && again.knocked == 12, 'stored');
        assert(again.holds(condition::CRIPPLED, 13) && !again.holds(condition::CRIPPLED, 14), 'D');
    }

    // FX-6, FX-31, §6: equal and smaller durations keep the deadline, a larger one refreshes;
    // a cure gives `t0 − 1`, an absent condition's cure nothing; a dead goblin takes nothing,
    // neither a condition nor a cure.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 1081626)] // ceil(1.05 × 1030120 measured)
    fn test_goblin_apply_refresh_cure() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut goblin = Fixture::goblin(9, HOB);
        goblin.apply(condition::BURNING, 3, @none, 42);
        goblin.apply(condition::BURNING, 3, @none, 42);
        goblin.apply(condition::BURNING, 1, @none, 43);
        assert(goblin.burning == 44, 'equal, smaller: kept');
        goblin.apply(condition::BURNING, 5, @none, 43);
        assert(goblin.burning == 47, 'larger: refreshed');
        goblin.cure(condition::BURNING, 45);
        assert(goblin.burning == 44, 'cured: t0 - 1');
        let before = goblin;
        goblin.cure(condition::POISON, 45);
        goblin.cure(condition::BURNING, 46);
        assert(goblin == before, 'absent: nothing');
        let mut dead = Fixture::goblin(8, HOB);
        dead.poison = 60;
        dead.ai = ai::DEAD;
        let remains = dead;
        dead.knock(2, @none, 50, @sheets);
        dead.cure(condition::POISON, 50);
        assert(dead == remains, 'dead: nothing');
    }

    // design/19 §10.2 through `apply`: the smash started in step 2 of tick 50 (A = 53); Skullring
    // at clock 51 knocks the Hobgoblin down for 2 ticks, t0 = 52: D = 53, the field none, R =
    // 52 + 10 − 1 = 61. A recovering goblin knocked down keeps its recovery (not an activation).
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 1099172)] // ceil(1.05 × 1046830 measured)
    fn test_goblin_knockdown_interrupts() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut goblin = Fixture::goblin(40, HOB);
        goblin.start(0, 0, 3, 50);
        goblin.knock(2, @none, 52, @sheets);
        assert(goblin.knocked == 53, 'D = 53');
        assert(activation_of(@goblin) == (activation::NONE, 0, 0), 'field none');
        assert(goblin.recharge(0) == 61, 'R = 61');
        let mut recovering = Fixture::goblin(41, HOB);
        recovering.recover(3, 60);
        recovering.knock(2, @none, 61, @sheets);
        assert(activation_of(@recovering) == (activation::RECOVERING, 0, 62), 'recovery kept');
    }

    // §3.2 row 5 (§5.2, §5.6, FX-7): knocked down to D = 53, it cannot act in step 2 of ticks
    // 52 and 53 and acts at 54; the pipeline's step 2, run over ticks 52 to 54, agrees (the
    // goblin acts at 54 alone: D and D + 1); through 53 a weapon hit on it is critical from any
    // arc and it neither blocks nor evades.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 6472696)] // ceil(1.05 × 6164472 measured)
    fn test_goblin_knocked_predicates() {
        let mut goblin = Fixture::goblin(40, HOB);
        goblin.knocked = 53;
        assert(!goblin.can_act(52) && !goblin.can_act(53) && goblin.can_act(54), 'acts at 54');
        let mut world = Fixture::only(51, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @Fixture::sheets(), 3, ref rules);
        assert(rules.acts.span() == array![(54, 40)].span(), 'the pipeline: at 54 only');
        assert(goblin.takes_critical(53) && !goblin.can_defend(53), 'tick 53: exposed');
        assert(!goblin.takes_critical(54) && goblin.can_defend(54), 'tick 54: not');
    }

    // §3.2 row 4, FX-15: Crippled to D = 62, its move in step 2 of tick 62 costs 2 ticks and it
    // recovers until B = 63 (it skips step 2 of tick 63); at 63, a move costs 1; with a
    // `MOVEMENT` effect, 1 (FX-18).
    #[test]
    #[available_gas(l2_gas: 330425)] // ceil(1.05 × 314690 measured)
    fn test_goblin_crippled_move() {
        let mut goblin = Fixture::goblin(9, RUNT);
        goblin.set_crippled(62);
        let k = goblin.move_ticks(62, false);
        assert(k == 2, 'crippled: 2');
        goblin.recover(k, 62);
        assert(activation_of(@goblin) == (activation::RECOVERING, 0, 63), 'B = 63');
        assert(goblin.move_ticks(63, false) == 1, 'over: 1');
        assert(goblin.move_ticks(62, true) == 1, 'movement: 1');
    }

    /// CBT-04's application before SPK-15's L2 (fix loop 2, D-172), kept as the oracle of the
    /// in-place `apply` and `knock` (docs/CAIRO.md §2).
    fn oracle(
        ref goblin: Goblin, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if !goblin.is_alive() {
            return;
        }
        goblin.inflict(condition, t0, source.duration(condition, v));
        if condition == condition::KNOCKED_DOWN {
            goblin.interrupt(t0, sheets);
        }
    }

    // L2's equivalence (fix loop 2): `apply` (conditions 1–4) and `knock` give the oracle's
    // goblin on every condition, at the values 1, 20, 0 and 40,000, with "Rending" and without,
    // activating, recovering, a condition held to be kept or raised, and dead.
    #[test]
    #[available_gas(l2_gas: 22929008)] // ceil(1.05 × 21837150 measured)
    fn test_goblin_apply_matches_oracle() {
        let sheets = Fixture::sheets();
        let rending = Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 };
        let none: Infliction = Default::default();
        let (activating, _) = condition_cost_state();
        let mut recovering = Fixture::goblin(41, HOB);
        recovering.recover(3, 50);
        let mut held = Fixture::goblin(42, HOB);
        held.poison = 80;
        held.knocked = 80;
        held.set_crippled(80);
        let mut dead = activating;
        dead.ai = ai::DEAD;
        dead.health = 0;
        let states = array![activating, recovering, held, dead];
        let conditions = array![
            condition::BLEEDING, condition::POISON, condition::BURNING, condition::CRIPPLED,
            condition::KNOCKED_DOWN,
        ];
        for state in states.span() {
            for c in conditions.span() {
                for v in array![1_i32, 20, 0, 40000].span() {
                    for source in array![rending, none].span() {
                        let mut expected = *state;
                        oracle(ref expected, *c, *v, source, 52, @sheets);
                        let mut goblin = *state;
                        if *c == condition::KNOCKED_DOWN {
                            goblin.knock(*v, source, 52, @sheets);
                        } else {
                            goblin.apply(*c, *v, source, 52);
                        }
                        assert(goblin == expected, 'as the oracle');
                    }
                }
            }
        }
    }

    #[test]
    #[should_panic(expected: 'tick: knock-down is knock')]
    #[available_gas(l2_gas: 290577)] // ceil(1.05 × 276740 measured)
    fn test_goblin_apply_knockdown_refused() {
        let mut goblin = Fixture::goblin(9, HOB);
        let none: Infliction = Default::default();
        goblin.apply(condition::KNOCKED_DOWN, 2, @none, 10);
    }

    // The Sonnet run's note (fix loop 2): a knock-down that does not lengthen a held one still
    // interrupts, and finds nothing to interrupt (a knocked-down goblin skips step 2).
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 803513)] // ceil(1.05 × 765250 measured)
    fn test_goblin_knock_refresh_not_longer() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut goblin = Fixture::goblin(9, HOB);
        goblin.knocked = 60;
        let before = goblin;
        goblin.knock(2, @none, 55, @sheets);
        assert(goblin == before, 'nothing: kept, no activation');
    }

    // The cost of the rules (CBT-04, AC-4; fix loop 2), by pairs: each test differs from its base
    // by its call alone, so the difference of snforge's totals is the call's cost. `knock`'s
    // costliest path is an interrupt of an activation; `apply`'s is Crippled's word. The other
    // paths show that each function is charged one cost whatever path runs.
    fn condition_cost_state() -> (Goblin, Sheets) {
        let mut goblin = opaque(Fixture::goblin(40, HOB));
        goblin.start(opaque(0), 0, 3, opaque(50));
        goblin.bleeding = opaque(55);
        (goblin, opaque(Fixture::sheets()))
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 778491)] // ceil(1.05 × 741420 measured)
    fn test_cost_goblin_condition_base() {
        let (goblin, _sheets) = condition_cost_state();
        opaque(goblin);
    }

    // The base of the pairs that give a source.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 779331)] // ceil(1.05 × 742220 measured)
    fn test_cost_goblin_source_base() {
        let (goblin, _sheets) = condition_cost_state();
        let _source: Infliction = opaque(Default::default());
        opaque(goblin);
    }

    // The other paths' bases: no activation and a longer knock-down held; dead.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 779751)] // ceil(1.05 × 742620 measured)
    fn test_cost_goblin_idle_base() {
        let (mut goblin, _sheets) = condition_cost_state();
        goblin.clear();
        goblin.knocked = opaque(80);
        let _source: Infliction = opaque(Default::default());
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 779751)] // ceil(1.05 × 742620 measured)
    fn test_cost_goblin_dead_base() {
        let (mut goblin, _sheets) = condition_cost_state();
        goblin.ai = opaque(ai::DEAD);
        let _source: Infliction = opaque(Default::default());
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 825720)] // ceil(1.05 × 786400 measured)
    fn test_cost_goblin_knock() {
        let (mut goblin, sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        goblin.knock(opaque(2), @source, opaque(52), @sheets);
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 826140)] // ceil(1.05 × 786800 measured)
    fn test_cost_goblin_knock_idle() {
        let (mut goblin, sheets) = condition_cost_state();
        goblin.clear();
        goblin.knocked = opaque(80);
        let source: Infliction = opaque(Default::default());
        goblin.knock(opaque(2), @source, opaque(52), @sheets);
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 808931)] // ceil(1.05 × 770410 measured)
    fn test_cost_goblin_apply_crippled() {
        let (mut goblin, _sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        goblin.apply(opaque(condition::CRIPPLED), opaque(20), @source, opaque(52));
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 808931)] // ceil(1.05 × 770410 measured)
    fn test_cost_goblin_apply_bleeding() {
        let (mut goblin, _sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        goblin.apply(opaque(condition::BLEEDING), opaque(20), @source, opaque(52));
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 809351)] // ceil(1.05 × 770810 measured)
    fn test_cost_goblin_apply_dead() {
        let (mut goblin, _sheets) = condition_cost_state();
        goblin.ai = opaque(ai::DEAD);
        let source: Infliction = opaque(Default::default());
        goblin.apply(opaque(condition::CRIPPLED), opaque(20), @source, opaque(52));
        opaque(goblin);
    }

    // The pre-L2 application, the oracle, as a pair: what L2 saves on a knock-down.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 856401)] // ceil(1.05 × 815620 measured)
    fn test_cost_goblin_oracle() {
        let (mut goblin, sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        oracle(
            ref goblin, opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(52), @sheets,
        );
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 810726)] // ceil(1.05 × 772120 measured)
    fn test_cost_goblin_cure() {
        let (mut goblin, _sheets) = condition_cost_state();
        goblin.cure(opaque(condition::BLEEDING), opaque(52));
        opaque(goblin);
    }

    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 788739)] // ceil(1.05 × 751180 measured)
    fn test_cost_goblin_predicates() {
        let (goblin, _sheets) = condition_cost_state();
        let t = opaque(52);
        opaque(goblin.takes_critical(t));
        opaque(goblin.can_defend(t));
        opaque(goblin.move_ticks(t, opaque(false)));
        opaque(goblin);
    }

    // A goblin's derived fields: max health from the adventurer's formula times its caste's
    // multiplier (design/03, design/05), its regeneration, its effect's pips at its rank; its
    // caste's position and cap, its kit's.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 1087002)] // ceil(1.05 × 1035240 measured)
    fn test_goblin_load() {
        let caste = CasteSheet {
            id: 3,
            health: 150,
            health_regen: 12,
            energy: 20,
            energy_regen: 2,
            weapon_ticks: 2,
            skills: [SMASH, 0, 0, 0],
            ..Default::default(),
        };
        let mut smash = Fixture::skill(SMASH, skill_kind::SPELL, 0, 0);
        smash.regen0 = 1;
        smash.regen12 = 4;
        smash.adrenaline = 5;
        let content = Content {
            skills: array![Fixture::skill(1, skill_kind::SPELL, 0, 0), smash].span(),
            potions: array![].span(),
            castes: array![Fixture::caste(HOB, 1), caste].span(),
        };
        // Level 20, caste 3; its effect is skill 24 at rank 8: 1 + 3 × 8 / 12 = 3.
        let state = LIVE + 3 * two(64) + 20 * two(80);
        let timers = LIVE + 255 + SMASH.into() * two(108) + 8 * two(246);
        let goblin = Fixture::load_goblin(
            GoblinWords { entity: 77, awake: false, state, timers }, @content,
        );
        let sheets = content.sheets();
        assert(goblin.max_health == 720 && goblin.health_regen(@sheets) == 2, 'health');
        assert(goblin.max_energy(@sheets) == 60 && goblin.energy_regen(@sheets) == 2, 'energy');
        assert(goblin.effect_regen == 3 && !goblin.awake, 'effect');
        assert(goblin.caste_at == 1 && goblin.adrenaline_cap(@sheets) == 20, 'its kit');
    }

    // `load` reads the hot fields of the words and derives the rest; `store` writes them back as
    // deltas, every other bit kept: a round trip is the identity, a change lands where it belongs.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 1368738)] // ceil(1.05 × 1303560 measured)
    fn test_goblin_load_store() {
        let content = Fixture::content();
        // Caste 2, level 10.
        let goblin = Fixture::goblin(9, RUNT);
        let words = GoblinWords {
            entity: 9, awake: true, state: goblin.state, timers: goblin.timers,
        };
        let loaded = Fixture::load_goblin(words, @content);
        assert(loaded == goblin, 'goblin load');
        let mut changed = loaded;
        changed.health = 3;
        changed.poison = 88;
        changed.effect_deadline = 90;
        changed.start(2, 8, 2, 70);
        changed.set_recharge(3, 500);
        let back = Fixture::load_goblin(changed.store(), @content);
        assert(back.state == changed.store().state, 'goblin state');
        assert(back.health == 3 && back.poison == 88 && back.effect_deadline == 90, 'fields');
        assert(activation_of(@back) == (2, 8, 72) && back.recharge(3) == 500, 'goblin timers');
    }

    // A caste skill missing from the content is refused when a goblin of the caste loads.
    #[test]
    #[should_panic(expected: 'tick: skill not in content')]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 463313)] // ceil(1.05 × 441250 measured)
    fn test_goblin_load_missing_skill() {
        let content = Content {
            skills: array![Fixture::skill(24, skill_kind::ATTACK, 3, 10)].span(),
            potions: array![].span(),
            castes: array![Fixture::caste(HOB, 1)].span(),
        };
        let goblin = Fixture::goblin(9, HOB);
        let words = GoblinWords {
            entity: 9, awake: true, state: goblin.state, timers: goblin.timers,
        };
        Fixture::load_goblin(words, @content);
    }

    // AUD-182-9: the words' decoder is the goblin's own (`GoblinTrait::hot`).
    #[test]
    #[available_gas(l2_gas: 332798)] // ceil(1.05 × 316950 measured)
    fn test_goblin_hot() {
        let goblin = Fixture::goblin(8, RUNT);
        let (state_ai, health, _, _, caste, slot, _, _, _, _, _, _, _, level, _, _) =
            GoblinTrait::hot(
            goblin.state, goblin.timers,
        );
        assert(state_ai == ai::ENGAGED && health == 100 && caste == RUNT, 'goblin');
        assert(slot == activation::NONE && level == 10, 'goblin timers');
    }

    // AUD-182-6, conditions (§5.7, FX-6): a dead goblin takes nothing; Crippled lives in the
    // words.
    #[test]
    #[available_gas(l2_gas: 603372)] // ceil(1.05 × 574640 measured)
    fn test_goblin_conditions() {
        let mut dead = Fixture::goblin(8, HOB);
        dead.ai = ai::DEAD;
        dead.inflict(condition::POISON, 10, 5);
        assert(dead.poison == 0, 'a dead goblin takes nothing');
        let mut goblin = Fixture::goblin(9, HOB);
        goblin.inflict(condition::CRIPPLED, 10, 5);
        goblin.inflict(condition::POISON, 10, 5);
        assert(goblin.crippled() == 14 && goblin.poison == 14, 'goblin conditions');
    }

    // AUD-182-6, a goblin's one slot (FX-30, FX-13): refreshed by its carrier, replaced by another.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 891576)] // ceil(1.05 × 849120 measured)
    fn test_goblin_hold() {
        let sheets = Fixture::hold_content().sheets();
        let mut goblin = Fixture::goblin(8, HOB);
        goblin.hold(Fixture::held(11, false, 50, 3), 8, 40, @sheets);
        goblin.hold(Fixture::held(11, false, 45, 3), 8, 40, @sheets);
        assert(goblin.effect_of().deadline == 50, 'goblin keeps the later');
        goblin.hold(Fixture::held(15, false, 44, 12), 12, 40, @sheets);
        let replaced = goblin.effect_of() == Fixture::held(15, false, 44, 12);
        assert(replaced && goblin.effect_regen == 1, 'replaced');
    }

    // AUD-182-6, adrenaline (§5.12, FX-12): a goblin's gains capped at its caste's, at most 252;
    // a dead goblin gains nothing.
    #[test]
    // gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once
    // a call) and the actors their positions
    #[available_gas(l2_gas: 660146)] // ceil(1.05 × 628710 measured)
    fn test_goblin_adrenaline_gain() {
        let mut heavy = Fixture::skill(25, skill_kind::ATTACK, 0, 0);
        heavy.adrenaline = 63;
        let skills: Array<SkillSheet> = array![
            Fixture::skill(24, skill_kind::ATTACK, 1, 10), heavy,
            Fixture::skill(26, skill_kind::SPELL, 1, 10),
            Fixture::skill(27, skill_kind::SHOUT, 0, 10),
        ];
        let content = Content {
            skills: skills.span(),
            potions: array![].span(),
            castes: array![Fixture::caste(HOB, 1)].span(),
        };
        // Caste 1, whose skill 25 costs 63 strikes: its cap is the field's 252.
        let words = GoblinWords {
            entity: 8, awake: true, state: Fixture::goblin(8, HOB).state, timers: LIVE + 255,
        };
        let mut goblin = Fixture::load_goblin(words, @content);
        let sheets = content.sheets();
        assert(goblin.adrenaline_cap(@sheets) == 252, 'goblin cap 252');
        goblin.adrenaline = 250;
        goblin.land_weapon_hit(@sheets);
        assert(goblin.adrenaline == 252, 'goblin capped');
        goblin.ai = ai::DEAD;
        goblin.adrenaline = 0;
        goblin.take_hit(@sheets);
        assert(goblin.adrenaline == 0, 'dead: nothing');
    }

    #[test]
    #[should_panic(expected: 'goblin: regeneration above i8')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_goblin_assert_pips() {
        GoblinAssert::assert_pips(-129);
    }
}
