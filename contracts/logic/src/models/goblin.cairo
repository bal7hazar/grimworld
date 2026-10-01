//! A goblin in a world tick (CBT-02; design/19 §5, §7.2): its stored words, as `Instances` passes
//! them to the tick's library call, and its view inside the call (`models::index::GoblinWords`,
//! `Goblin`). Its behaviour: loading the hot fields once and storing them back as deltas
//! (`GoblinTrait`), the fields read and written in the words directly (`GoblinWordsTrait`), the
//! activation's rules (`GoblinTickTrait`) and the lifecycle's (`GoblinLifecycleTrait`). The words'
//! layouts are the ephemeral package's, which owns the storage; the offsets below are ENG-01's
//! frozen ones, pinned by the ephemeral package's `test_tick_words`.

use crate::helpers::tick::{TickAssert, TickMathTrait};
use crate::packing::{N16, N24, N28, N56, N6, N8, P108, P16, P28, P56, P84, field, limbs, peel};
use crate::types::combat::{activation, condition, skill_kind};
use crate::types::tick::{
    CasteSheetTrait, Held, Index, IndexTrait, Kit, MISSING, REGEN_OFFSET, Sheets, SheetsTrait,
    SkillSheetTrait, ai,
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
        let regen: i32 = (*sheet.health_regen).into();
        let effect_regen: i32 = if effect == 0 {
            0
        } else {
            (*sheets.skills)[index.skill(effect)].regen(rank)
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
            health_regen: (regen - REGEN_OFFSET).try_into().unwrap(),
            max_energy: *sheet.energy * 3,
            energy_regen: *sheet.energy_regen,
            adrenaline_cap: *kit.cap,
            caste_at,
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
    fn hold(ref self: Goblin, held: Held, t: u32, sheets: @Sheets) {
        if !self.is_alive() {
            return;
        }
        let old = self.effect_of();
        if old.deadline >= t && old.carrier == held.carrier && held.deadline < old.deadline {
            return;
        }
        let pips: i32 = sheets.skill(held.carrier).regen(held.rank);
        GoblinAssert::assert_pips(pips);
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

/// A goblin's unit tests (CBT-02, CBT-02d; D-167): its load and store, its decoder, its lifecycle
/// rules, its checks.
#[cfg(test)]
mod tests {
    use crate::types::combat::{activation, condition, skill_kind};
    use crate::types::tick::{CasteSheet, Content, ContentTrait, SkillSheet, ai};
    use crate::types::world::fixtures::{Fixture, HOB, LIVE, RUNT, SMASH, activation_of, two};
    use super::{
        GoblinAssert, GoblinLifecycleTrait, GoblinTickTrait, GoblinTrait, GoblinWords,
        GoblinWordsTrait,
    };

    // A goblin's derived fields: max health from the adventurer's formula times its caste's
    // multiplier (design/03, design/05), its regeneration, its effect's pips at its rank; its
    // caste's position and cap, its kit's.
    #[test]
    #[available_gas(l2_gas: 908639)] // ceil(1.05 × 865370 measured)
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
        assert(goblin.max_health == 720 && goblin.health_regen == 2, 'health');
        assert(goblin.max_energy == 60 && goblin.energy_regen == 2, 'energy');
        assert(goblin.effect_regen == 3 && !goblin.awake, 'effect');
        assert(goblin.caste_at == 1 && goblin.adrenaline_cap == 20, 'its kit');
    }

    // `load` reads the hot fields of the words and derives the rest; `store` writes them back as
    // deltas, every other bit kept: a round trip is the identity, a change lands where it belongs.
    #[test]
    #[available_gas(l2_gas: 1072145)] // ceil(1.05 × 1021090 measured)
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
    #[available_gas(l2_gas: 454724)] // ceil(1.05 × 433070 measured)
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
    #[available_gas(l2_gas: 341334)] // ceil(1.05 × 325080 measured)
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
    #[available_gas(l2_gas: 613484)] // ceil(1.05 × 584270 measured)
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
    #[available_gas(l2_gas: 707606)] // ceil(1.05 × 673910 measured)
    fn test_goblin_hold() {
        let sheets = Fixture::hold_content().sheets();
        let mut goblin = Fixture::goblin(8, HOB);
        goblin.hold(Fixture::held(11, false, 50, 3), 40, @sheets);
        goblin.hold(Fixture::held(11, false, 45, 3), 40, @sheets);
        assert(goblin.effect_of().deadline == 50, 'goblin keeps the later');
        goblin.hold(Fixture::held(15, false, 44, 12), 40, @sheets);
        let replaced = goblin.effect_of() == Fixture::held(15, false, 44, 12);
        assert(replaced && goblin.effect_regen == 1, 'replaced');
    }

    // AUD-182-6, adrenaline (§5.12, FX-12): a goblin's gains capped at its caste's, at most 252;
    // a dead goblin gains nothing.
    #[test]
    #[available_gas(l2_gas: 486182)] // ceil(1.05 × 463030 measured)
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
        assert(goblin.adrenaline_cap == 252, 'goblin cap 252');
        goblin.adrenaline = 250;
        goblin.land_weapon_hit();
        assert(goblin.adrenaline == 252, 'goblin capped');
        goblin.ai = ai::DEAD;
        goblin.adrenaline = 0;
        goblin.take_hit();
        assert(goblin.adrenaline == 0, 'dead: nothing');
    }

    #[test]
    #[should_panic(expected: 'goblin: regeneration above i8')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_goblin_assert_pips() {
        GoblinAssert::assert_pips(-129);
    }
}
