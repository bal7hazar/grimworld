//! A goblin in a world tick (CBT-02; design/19 §5, §7.2): its stored words, as `Instances` passes
//! them to the tick's library call, and its view inside the call (`models::index::GoblinWords`,
//! `Goblin`). Its behaviour: loading the hot fields once and storing them back as deltas
//! (`GoblinTrait`), the fields read and written in the words directly (`GoblinWordsTrait`), the
//! activation's rules (`GoblinTickTrait`) and the lifecycle's (`GoblinLifecycleTrait`). The words'
//! layouts are the ephemeral package's, which owns the storage; the offsets below are ENG-01's
//! frozen ones, pinned by the ephemeral package's `test_tick_words`.

use crate::helpers::tick::{TickAssert, TickMathTrait};
use crate::packing::{
    P112, P16, P24, P28, P32, P52, P56, P64, P8, P80, P84, field, low_field, split,
};
use crate::types::combat::{activation, condition, skill_kind};
use crate::types::tick::{
    CasteSheet, CasteSheetTrait, Content, ContentTrait, Held, MAX_GOBLIN_ADRENALINE, REGEN_OFFSET,
    SkillSheetTrait, ai, errors,
};

pub use super::index::{Goblin, GoblinWords};

const F8: felt252 = 0x100;
const F24: felt252 = 0x1000000;
const F32: felt252 = 0x100000000;
const F48: felt252 = 0x1000000000000;
const F52: felt252 = 0x10000000000000;
const F56: felt252 = 0x100000000000000;
const F80: felt252 = 0x100000000000000000000;
const F128: felt252 = 0x100000000000000000000000000000000;
const F156: felt252 = 0x1000000000000000000000000000000000000000;
const F184: felt252 = 0x10000000000000000000000000000000000000000000000;
const F212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const P108: u128 = 0x1000000000000000000000000000;
const P118: u128 = 0x400000000000000000000000000000;
const F108: felt252 = 0x1000000000000000000000000000;
const F240: felt252 = 0x1000000000000000000000000000000000000000000000000000000000000;
const F246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

#[generate_trait]
pub impl GoblinImpl of GoblinTrait {
    /// The hot fields of a goblin's words, in `Goblin`'s order (ai … effect deadline), and its
    /// level and effect `(skill, rank)`.
    fn hot(
        state: felt252, timers: felt252,
    ) -> (u8, u16, u8, u8, u16, u8, u16, u32, u32, u32, u32, u32, u32, u8, u16, u8) {
        let (low, _) = split(state);
        let (tlow, thigh) = split(timers);
        (
            field(low, P24, P8).try_into().unwrap(),
            field(low, P32, P16).try_into().unwrap(),
            field(low, 0x1000000000000, P8).try_into().unwrap(),
            field(low, P56, P8).try_into().unwrap(),
            field(low, P64, P16).try_into().unwrap(),
            low_field(tlow, P8.try_into().unwrap()).try_into().unwrap(),
            field(tlow, P8, P16).try_into().unwrap(),
            field(tlow, P24, P28).try_into().unwrap(),
            field(tlow, P52, P28).try_into().unwrap(),
            field(tlow, P80, P28).try_into().unwrap(),
            low_field(thigh, P28.try_into().unwrap()).try_into().unwrap(),
            field(thigh, P56, P28).try_into().unwrap(),
            field(thigh, P84, P28).try_into().unwrap(),
            field(low, P80, P8).try_into().unwrap(),
            field(tlow, P108, P16).try_into().unwrap(),
            field(thigh, P118, 0x10).try_into().unwrap(),
        )
    }

    /// A goblin from its words, with what it derives once from its caste (`content`) and level:
    /// its maxima, regeneration and its effect's `REGENERATION` pips.
    fn load(words: GoblinWords, content: @Content) -> Goblin {
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
        let sheet = content.caste(caste);
        let regen: i32 = (*sheet.health_regen).into();
        let effect_regen: i32 = if effect == 0 {
            0
        } else {
            content.skill(effect).regen(rank)
        };
        // Its caste skills' highest adrenaline cost, in quarters, at most 252 (§5.12; DS-18
        // bounds a caste skill at 63 strikes).
        let mut cap: u16 = 0;
        for skill in sheet.skills.span() {
            if *skill != 0 {
                let cost: u16 = (*content.skill(*skill).adrenaline).into() * 4;
                if cost > cap {
                    cap = cost;
                }
            }
        }
        if cap > MAX_GOBLIN_ADRENALINE.into() {
            cap = MAX_GOBLIN_ADRENALINE.into();
        }
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
            effect_regen: effect_regen.try_into().expect(errors::REGEN),
            max_health: sheet.max_health(level).try_into().unwrap(),
            health_regen: (regen - REGEN_OFFSET).try_into().unwrap(),
            max_energy: *sheet.energy * 3,
            energy_regen: *sheet.energy_regen,
            adrenaline_cap: cap.try_into().unwrap(),
            state: words.state,
            timers: words.timers,
        }
    }

    /// Its words, the hot fields written back (its effect's skill, charges and rank are the
    /// executor's to write).
    fn store(self: @Goblin) -> GoblinWords {
        let (
            ai,
            health,
            energy,
            adrenaline,
            _,
            act_slot,
            act_target,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
            effect_deadline,
            _,
            _,
            _,
        ) =
            Self::hot(
            *self.state, *self.timers,
        );
        let state = *self.state
            + TickMathTrait::delta(ai.into(), (*self.ai).into(), F24)
            + TickMathTrait::delta(health.into(), (*self.health).into(), F32)
            + TickMathTrait::delta(energy.into(), (*self.energy).into(), F48)
            + TickMathTrait::delta(adrenaline.into(), (*self.adrenaline).into(), F56);
        let timers = *self.timers
            + TickMathTrait::delta(act_slot.into(), (*self.act_slot).into(), 1)
            + TickMathTrait::delta(act_target.into(), (*self.act_target).into(), F8)
            + TickMathTrait::delta(act_deadline.into(), (*self.act_deadline).into(), F24)
            + TickMathTrait::delta(bleeding.into(), (*self.bleeding).into(), F52)
            + TickMathTrait::delta(poison.into(), (*self.poison).into(), F80)
            + TickMathTrait::delta(burning.into(), (*self.burning).into(), F128)
            + TickMathTrait::delta(knocked.into(), (*self.knocked).into(), F184)
            + TickMathTrait::delta(effect_deadline.into(), (*self.effect_deadline).into(), F212);
        GoblinWords { entity: *self.entity, awake: *self.awake, state, timers }
    }

    /// Alive: neither dead nor looted.
    #[inline(always)]
    fn is_alive(self: @Goblin) -> bool {
        *self.ai < ai::DEAD
    }

    /// The recharge deadline of caste skill 0–3.
    fn recharge(self: @Goblin, slot: u8) -> u32 {
        let (_, high) = split(*self.state);
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
        let (_, high) = split(*self.timers);
        field(high, P28, P28).try_into().unwrap()
    }

    fn set_crippled(ref self: Goblin, deadline: u32) {
        let old = self.crippled();
        self.timers += TickMathTrait::delta(old.into(), deadline.into(), F156);
    }

    /// Its one held effect (a skill; a goblin holds no potion); its deadline is the hot field.
    fn effect_of(self: @Goblin) -> Held {
        let (low, high) = split(*self.timers);
        Held {
            carrier: field(low, P108, P16).try_into().unwrap(),
            potion: false,
            charges: field(high, P112, 0x40).try_into().unwrap(),
            deadline: *self.effect_deadline,
            rank: field(high, P118, 0x10).try_into().unwrap(),
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
    fn use_instant(ref self: Goblin, slot: u8, t: u32, caste: @CasteSheet, content: @Content) {
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(t, r));
    }

    /// Step 1 at `A`: the activation ends, its recharge counts from `A` (FX-2); an attack skill
    /// whose weapon costs `k ≥ n + 2` recovers until `B = A + k − n − 1` (FX-15, §10.9).
    /// Returns its slot and target for the executor.
    fn conclude(ref self: Goblin, caste: @CasteSheet, content: @Content) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let a = self.act_deadline;
        let skill = content.skill(*caste.skills.span()[slot.into()]);
        self.set_recharge(slot, TickMathTrait::recharge_deadline(a, *skill.recharge));
        let k: u32 = (*caste.weapon_ticks).into();
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
    fn lapse(ref self: Goblin, caste: @CasteSheet, content: @Content) {
        let slot = self.act_slot;
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        let deadline = TickMathTrait::recharge_deadline(self.act_deadline, r);
        if deadline > self.recharge(slot) {
            self.set_recharge(slot, deadline);
        }
        self.clear();
    }

    /// Interrupted at `t₀` (§5.9): the field goes to none, the recharge counts from `t₀`
    /// (FX-2). Nothing unless activating (a recovery is not an activation).
    fn interrupt(ref self: Goblin, t0: u32, caste: @CasteSheet, content: @Content) {
        let slot = self.act_slot;
        if slot > activation::LAST_SLOT {
            return;
        }
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(t0, r));
        self.clear();
    }

    /// Step 3 at tick `t` (§5.8) for an awake goblin alive: health by its caste's pips, its
    /// effect's and its conditions'; energy by the caste's pips in thirds; adrenaline decay when
    /// not Engaged (D-157 E).
    fn regenerate(ref self: Goblin, t: u32) {
        let mut pips: i32 = self.health_regen.into()
            + TickMathTrait::degeneration(self.bleeding, self.poison, self.burning, t)
            + TickMathTrait::effect_pips(self.effect_regen, self.effect_deadline, t);
        self.health = TickMathTrait::heal(self.health, pips, self.max_health);
        let energy: u16 = self.energy.into() + self.energy_regen.into();
        self
            .energy =
                if energy > self.max_energy.into() {
                    self.max_energy
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

    fn cure(ref self: Goblin, condition: u8, t0: u32) {
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
    fn hold(ref self: Goblin, held: Held, t: u32, content: @Content) {
        if !self.is_alive() {
            return;
        }
        let old = self.effect_of();
        if old.deadline >= t && old.carrier == held.carrier && held.deadline < old.deadline {
            return;
        }
        let pips: i32 = content.skill(held.carrier).regen(held.rank);
        self.set_effect(held, pips.try_into().unwrap());
    }

    /// Adrenaline gained, in quarters (§5.12), capped at its caste's cap (at most 252).
    fn gain_adrenaline(ref self: Goblin, quarters: u8) {
        if self.adrenaline < self.adrenaline_cap {
            let gained: u16 = self.adrenaline.into() + quarters.into();
            let cap: u16 = self.adrenaline_cap.into();
            self.adrenaline = TickMathTrait::min16(gained, cap).try_into().unwrap();
        }
    }

    /// A weapon hit landed: 4 quarters (no `hits` counter: a member's modifier).
    fn land_weapon_hit(ref self: Goblin) {
        self.gain_adrenaline(4);
    }

    /// A hit taken while alive: 1 quarter.
    fn take_hit(ref self: Goblin) {
        if self.is_alive() && self.health > 0 {
            self.gain_adrenaline(1);
        }
    }
}
