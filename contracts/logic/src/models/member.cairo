//! A member in a world tick (CBT-02; design/19 §5, §7.2): its stored words, as `Instances` passes
//! them to the tick's library call, and its view inside the call (`models::index::MemberWords`,
//! `Member`). Its behaviour: loading the hot fields once and storing them back as deltas
//! (`MemberTrait`), the fields read and written in the words directly (`MemberWordsTrait`), the
//! activation's rules (`MemberTickTrait`) and the lifecycle's (`MemberLifecycleTrait`). The words'
//! layouts are the ephemeral package's, which owns the storage; the offsets below are ENG-01's
//! frozen ones, pinned by the ephemeral package's `test_tick_words`.

use crate::helpers::tick::{TickAssert, TickMathTrait};
use crate::packing::{
    P112, P16, P24, P28, P32, P52, P56, P64, P8, P80, P84, P96, field, low_field, split,
};
use crate::types::combat::{condition, skill_kind};
use crate::types::tick::{
    Content, ContentTrait, ENERGY_THIRDS, Held, NO_SLOT, REGEN_OFFSET, SkillSheetTrait, errors,
};

pub use super::index::{Member, MemberWords};

const F8: felt252 = 0x100;
const F24: felt252 = 0x1000000;
const F28: felt252 = 0x10000000;
const F32: felt252 = 0x100000000;
const F56: felt252 = 0x100000000000000;
const F64: felt252 = 0x10000000000000000;
const F80: felt252 = 0x100000000000000000000;
const F84: felt252 = 0x1000000000000000000000;
const F96: felt252 = 0x1000000000000000000000000;
const F128: felt252 = 0x100000000000000000000000000000000;
const F156: felt252 = 0x1000000000000000000000000000000000000000;
const F160: felt252 = 0x10000000000000000000000000000000000000000;
const F184: felt252 = 0x10000000000000000000000000000000000000000000000;
const F192: felt252 = 0x1000000000000000000000000000000000000000000000000;
const F212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const F112: felt252 = 0x10000000000000000000000000000;

#[generate_trait]
pub impl MemberImpl of MemberTrait {
    /// The `(limb is high, shift)` of a member's recharge slot 0–7 and its felt shift.
    #[inline(always)]
    fn recharge_at(slot: u8) -> (bool, u128, felt252) {
        if slot == 0 {
            (false, 1, 1)
        } else if slot == 1 {
            (false, P28, F28)
        } else if slot == 2 {
            (false, P56, F56)
        } else if slot == 3 {
            (false, P84, F84)
        } else if slot == 4 {
            (true, 1, F128)
        } else if slot == 5 {
            (true, P28, F156)
        } else if slot == 6 {
            (true, P56, F184)
        } else {
            (true, P84, F212)
        }
    }

    /// The `(limb is high, shift, felt shift)` of a member's effect slot 0–3 (bits 0, 56, 128,
    /// 184).
    #[inline(always)]
    fn effect_at(slot: u8) -> (bool, u128, felt252) {
        if slot == 0 {
            (false, 1, 1)
        } else if slot == 1 {
            (false, P56, F56)
        } else if slot == 2 {
            (true, 1, F128)
        } else {
            (true, P56, F184)
        }
    }

    /// The hot fields of a member's words, in `Member`'s order (status … knocked).
    fn hot(words: @MemberWords) -> (u8, u16, u16, u16, u8, u8, u16, u8, u32, u32, u32, u32, u32) {
        let (low, high) = split(*words.state);
        let (tlow, thigh) = split(*words.timers);
        (
            field(low, P56, P8).try_into().unwrap(),
            field(low, P64, P16).try_into().unwrap(),
            field(low, P80, P16).try_into().unwrap(),
            field(low, P96, P16).try_into().unwrap(),
            field(high, P32, P8).try_into().unwrap(),
            low_field(tlow, P8.try_into().unwrap()).try_into().unwrap(),
            field(tlow, P8, P16).try_into().unwrap(),
            field(tlow, P24, P8).try_into().unwrap(),
            field(tlow, P32, P32).try_into().unwrap(),
            field(tlow, P64, P32).try_into().unwrap(),
            field(tlow, P96, P32).try_into().unwrap(),
            low_field(thigh, P32.try_into().unwrap()).try_into().unwrap(),
            field(thigh, P64, P32).try_into().unwrap(),
        )
    }

    /// A member from its words, with what it derives once: the maxima and regeneration of
    /// `MemberStats`, each held effect's deadline and `REGENERATION` pips (a skill's at the slot's
    /// rank, a potion's through the belt of `MemberKit`).
    fn load(words: MemberWords, content: @Content) -> Member {
        let (
            status,
            health,
            energy,
            adrenaline,
            flags,
            act_slot,
            act_target,
            act_tile,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
        ) =
            Self::hot(
            @words,
        );
        let (low, _) = split(words.stats);
        let health_regen: i32 = field(low, P32, P8).try_into().unwrap();
        let (elow, ehigh) = split(words.effects);
        let (belt, _) = split(words.kit);
        let mut deadlines: Array<u32> = array![];
        let mut regen: Array<i8> = array![];
        for (limb, shift) in array![(elow, 1), (elow, P56), (ehigh, 1), (ehigh, P56)] {
            let carrier: u16 = field(limb, shift, P16).try_into().unwrap();
            deadlines.append(field(limb, shift * P24, P28).try_into().unwrap());
            // The potion tag first: with it, the carrier is a belt slot 0–3, slot 0 included
            // (ENG-01 §3.2; AUD-182-1). Without it, skill 0 is an empty slot.
            let pips: i32 = if field(limb, shift * 0x800000, 2) == 1 {
                let id = field(belt, *[1, P32, P64, P96].span()[carrier.into()], P32);
                (*content.potion(id.try_into().unwrap()).regen).into()
            } else if carrier == 0 {
                0
            } else {
                content.skill(carrier).regen(field(limb, shift * P52, 0x10).try_into().unwrap())
            };
            regen.append(pips.try_into().expect(errors::REGEN));
        }
        // The bar's highest adrenaline cost, in quarters (§5.12).
        let (bar, _) = split(words.bar);
        let mut cap: u16 = 0;
        let mut rest = bar;
        for _ in 0..8_u8 {
            let (next, skill) = DivRem::div_rem(rest, P16.try_into().unwrap());
            rest = next;
            if skill != 0 {
                let cost: u16 = (*content.skill(skill.try_into().unwrap()).adrenaline).into() * 4;
                if cost > cap {
                    cap = cost;
                }
            }
        }
        Member {
            status,
            health,
            energy,
            adrenaline,
            flags,
            act_slot,
            act_target,
            act_tile,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
            effect_deadlines: [*deadlines[0], *deadlines[1], *deadlines[2], *deadlines[3]],
            effect_regen: [*regen[0], *regen[1], *regen[2], *regen[3]],
            max_health: low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
            max_energy: field(low, P16, P8).try_into().unwrap() * ENERGY_THIRDS,
            health_regen: (health_regen - REGEN_OFFSET).try_into().unwrap(),
            energy_regen: field(low, P24, P8).try_into().unwrap(),
            adrenaline_cap: cap,
            words,
        }
    }

    /// Its words, the hot fields written back (the effects word is the executor's to write).
    fn store(self: @Member) -> MemberWords {
        let (
            status,
            health,
            energy,
            adrenaline,
            flags,
            act_slot,
            act_target,
            act_tile,
            act_deadline,
            bleeding,
            poison,
            burning,
            knocked,
        ) =
            Self::hot(
            self.words,
        );
        let words = *self.words;
        let state = words.state
            + TickMathTrait::delta(status.into(), (*self.status).into(), F56)
            + TickMathTrait::delta(health.into(), (*self.health).into(), F64)
            + TickMathTrait::delta(energy.into(), (*self.energy).into(), F80)
            + TickMathTrait::delta(adrenaline.into(), (*self.adrenaline).into(), F96)
            + TickMathTrait::delta(flags.into(), (*self.flags).into(), F160);
        let timers = words.timers
            + TickMathTrait::delta(act_slot.into(), (*self.act_slot).into(), 1)
            + TickMathTrait::delta(act_target.into(), (*self.act_target).into(), F8)
            + TickMathTrait::delta(act_tile.into(), (*self.act_tile).into(), F24)
            + TickMathTrait::delta(act_deadline.into(), (*self.act_deadline).into(), F32)
            + TickMathTrait::delta(bleeding.into(), (*self.bleeding).into(), F64)
            + TickMathTrait::delta(poison.into(), (*self.poison).into(), F96)
            + TickMathTrait::delta(burning.into(), (*self.burning).into(), F128)
            + TickMathTrait::delta(knocked.into(), (*self.knocked).into(), F192);
        MemberWords { state, timers, ..words }
    }

    /// The recharge deadline of bar slot 0–7.
    fn recharge(self: @Member, slot: u8) -> u32 {
        let (low, high) = split(*self.words.recharges);
        let (upper, shift, _) = Self::recharge_at(slot);
        let limb = if upper {
            high
        } else {
            low
        };
        field(limb, shift, P28).try_into().unwrap()
    }

    fn set_recharge(ref self: Member, slot: u8, deadline: u32) {
        let (_, _, shift) = Self::recharge_at(slot);
        let old = self.recharge(slot);
        self.words.recharges += TickMathTrait::delta(old.into(), deadline.into(), shift);
    }

    /// The skill id of bar slot 0–7 (`MemberBar`).
    #[inline(always)]
    fn skill(self: @Member, slot: u8) -> u16 {
        let (low, _) = split(*self.words.bar);
        let shift = *[1, P16, P32, 0x1000000000000, P64, P80, P96, P112].span()[slot.into()];
        field(low, shift, P16).try_into().unwrap()
    }
}

/// The fields of a member's words that are not hot: written only by the lifecycle rules
/// (`MemberTickTrait`, `MemberLifecycleTrait`), in the words directly, as the recharges are.
#[generate_trait]
pub impl MemberWordsImpl of MemberWordsTrait {
    /// Crippled's deadline (`MemberTimers` bits 160–191).
    fn crippled(self: @Member) -> u32 {
        let (_, high) = split(*self.words.timers);
        field(high, P32, P32).try_into().unwrap()
    }

    fn set_crippled(ref self: Member, deadline: u32) {
        let old = self.crippled();
        self.words.timers += TickMathTrait::delta(old.into(), deadline.into(), F160);
    }

    /// The `hits` counter (`MemberState` bits 112–119, design/19 §5.12).
    fn hits(self: @Member) -> u8 {
        let (low, _) = split(*self.words.state);
        field(low, P112, P8).try_into().unwrap()
    }

    fn set_hits(ref self: Member, hits: u8) {
        let old = self.hits();
        self.words.state += TickMathTrait::delta(old.into(), hits.into(), F112);
    }

    /// `ADRENALINE_EVERY_N`'s lowest N (`MemberKit` bits 160–167); 0 for none.
    fn double_every(self: @Member) -> u8 {
        let (_, high) = split(*self.words.kit);
        field(high, P32, P8).try_into().unwrap()
    }

    /// The potion item of belt slot 0–3 (`MemberKit` bits `32 slot`).
    fn belt_item(self: @Member, slot: u16) -> u32 {
        let (low, _) = split(*self.words.kit);
        field(low, *[1, P32, P64, P96].span()[slot.into()], P32).try_into().unwrap()
    }

    /// The held effect of slot 0–3, as the word stores it.
    fn effect_of(self: @Member, slot: u8) -> Held {
        let (low, high) = split(*self.words.effects);
        let (upper, shift, _) = MemberTrait::effect_at(slot);
        let limb = if upper {
            high
        } else {
            low
        };
        Held {
            carrier: field(limb, shift, P16).try_into().unwrap(),
            charges: field(limb, shift * P16, 0x40).try_into().unwrap(),
            potion: field(limb, shift * 0x800000, 2) == 1,
            deadline: field(limb, shift * P24, P28).try_into().unwrap(),
            rank: field(limb, shift * P52, 0x10).try_into().unwrap(),
        }
    }

    /// Writes `held` in slot 0–3, with its `REGENERATION` pips (the hot fields follow).
    fn set_effect(ref self: Member, slot: u8, held: Held, pips: i8) {
        let old = self.effect_of(slot);
        let (_, _, base) = MemberTrait::effect_at(slot);
        self.words.effects += TickMathTrait::delta(old.carrier.into(), held.carrier.into(), base)
            + TickMathTrait::delta(old.charges.into(), held.charges.into(), base * 0x10000)
            + TickMathTrait::delta(
                TickMathTrait::tag(old.potion), TickMathTrait::tag(held.potion), base * 0x800000,
            )
            + TickMathTrait::delta(old.deadline.into(), held.deadline.into(), base * 0x1000000)
            + TickMathTrait::delta(old.rank.into(), held.rank.into(), base * 0x10000000000000);
        let [d0, d1, d2, d3] = self.effect_deadlines;
        let [r0, r1, r2, r3] = self.effect_regen;
        let d = held.deadline;
        let (deadlines, regen) = if slot == 0 {
            ([d, d1, d2, d3], [pips, r1, r2, r3])
        } else if slot == 1 {
            ([d0, d, d2, d3], [r0, pips, r2, r3])
        } else if slot == 2 {
            ([d0, d1, d, d3], [r0, r1, pips, r3])
        } else {
            ([d0, d1, d2, d], [r0, r1, r2, pips])
        };
        self.effect_deadlines = deadlines;
        self.effect_regen = regen;
    }
}

#[generate_trait]
pub impl MemberTickImpl of MemberTickTrait {
    /// An activation of `n` ticks started in the action phase at clock `c` (§5.1, §5.3 step 4):
    /// `A = c + n`, `n` at least 1 (§6).
    fn start(ref self: Member, slot: u8, target: u16, n: u16, c: u32) {
        let n: u32 = if n == 0 {
            1
        } else {
            n.into()
        };
        self.act_slot = slot;
        self.act_target = target;
        self.act_tile = 0;
        self.act_deadline = c + n;
    }

    /// An instant skill of the bar's `slot` used in the action phase at clock `c`: its recharge
    /// counts from `t₀ = c + 1` (§5.1).
    fn use_instant(ref self: Member, slot: u8, c: u32, content: @Content) {
        let r = *content.skill(self.skill(slot)).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(c + 1, r));
    }

    /// Step 1 at `A`: the activation ends; its recharge counts from `A` (FX-2); returns its slot
    /// and target for the executor.
    fn conclude(ref self: Member, content: @Content) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let r = *content.skill(self.skill(slot)).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(self.act_deadline, r));
        self.clear();
        (slot, target)
    }

    /// Interrupted at `t₀` (§5.9: `c + 1` in the action phase, `T` in a tick): no effect, the
    /// recharge counts from `t₀` (FX-2). Nothing without an activation.
    fn interrupt(ref self: Member, t0: u32, content: @Content) {
        if self.act_slot == NO_SLOT {
            return;
        }
        let r = *content.skill(self.skill(self.act_slot)).recharge;
        self.set_recharge(self.act_slot, TickMathTrait::recharge_deadline(t0, r));
        self.clear();
    }

    /// Step 3 at tick `t` (§5.8) for a member inside and alive: health by its pips (the
    /// snapshot's, its `REGENERATION` effects', the conditions'; clamped to ±10, × 2), energy by
    /// its pips in thirds, adrenaline decay out of combat (D-157 E).
    fn regenerate(ref self: Member, t: u32, engaged: bool) {
        let mut pips: i32 = self.health_regen.into()
            + TickMathTrait::degeneration(self.bleeding, self.poison, self.burning, t);
        let [r0, r1, r2, r3] = self.effect_regen;
        if r0 != 0 || r1 != 0 || r2 != 0 || r3 != 0 {
            let [d0, d1, d2, d3] = self.effect_deadlines;
            pips += TickMathTrait::effect_pips(r0, d0, t)
                + TickMathTrait::effect_pips(r1, d1, t)
                + TickMathTrait::effect_pips(r2, d2, t)
                + TickMathTrait::effect_pips(r3, d3, t);
        }
        self.health = TickMathTrait::heal(self.health, pips, self.max_health);
        let energy = self.energy + self.energy_regen.into();
        self.energy = if energy > self.max_energy {
            self.max_energy
        } else {
            energy
        };
        if !engaged {
            self.adrenaline = TickMathTrait::decay(self.adrenaline);
        }
    }

    fn clear(ref self: Member) {
        self.act_slot = NO_SLOT;
        self.act_target = 0;
        self.act_tile = 0;
        self.act_deadline = 0;
    }
}

/// The lifecycle rules of design/19 §5.7 and §5.12 on a member (AUD-182-6): conditions inflicted
/// and cured, held effects held, refreshed and replaced, adrenaline gained. The executor (CBT-05)
/// calls them; the durations it passes are after `durations::effective_duration`.
#[generate_trait]
pub impl MemberLifecycleImpl of MemberLifecycleTrait {
    /// Condition `condition` (1–5, the MVP's: FX-22) inflicted at `t0` for `d ≥ 1` ticks: `D =
    /// t0 + d − 1`; held already, it refreshes to `max(D_old, D)` (FX-6; Knocked down too,
    /// FX-31).
    fn inflict(ref self: Member, condition: u8, t0: u32, d: u32) {
        let old = self.condition(condition);
        self.set_condition(condition, TickMathTrait::refreshed(old, t0, d));
    }

    /// `CURE` at `t0` (§3.2): a duration of 0, `D = t0 − 1`; an absent condition, nothing.
    fn cure(ref self: Member, condition: u8, t0: u32) {
        let old = self.condition(condition);
        self.set_condition(condition, TickMathTrait::cured(old, t0));
    }

    /// The deadline of condition 1–5.
    fn condition(self: @Member, condition: u8) -> u32 {
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

    fn set_condition(ref self: Member, condition: u8, deadline: u32) {
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

    /// A holding effect applied at tick or clock `t` (§5.7), `stance` if its carrier is a stance;
    /// returns its slot. In order:
    /// 1. its carrier held (FX-42: the skill id, or a potion's item id through its belt slot):
    ///    the application with the later deadline is kept whole, the new one on a tie (FX-30);
    /// 2. else a stance while one is held: it takes that slot;
    /// 3. else the lowest free slot (never held, or its deadline passed);
    /// 4. else eviction: the earliest deadline, ties the lowest slot (FX-13).
    /// An effect ends by its deadline: one whose charges reach 0 is ended by the executor with a
    /// deadline of `t − 1`.
    fn hold(ref self: Member, held: Held, stance: bool, t: u32, content: @Content) -> u8 {
        let item = if held.potion {
            self.belt_item(held.carrier)
        } else {
            0
        };
        // 1. The same carrier.
        let mut slot: u8 = 0;
        while slot < 4 {
            let old = self.effect_of(slot);
            if old.deadline >= t && old.potion == held.potion {
                let same = if held.potion {
                    self.belt_item(old.carrier) == item
                } else {
                    old.carrier == held.carrier
                };
                if same {
                    if held.deadline >= old.deadline {
                        self.put(slot, held, item, content);
                    }
                    return slot;
                }
            }
            slot += 1;
        }
        // 2. A stance replaces the stance held.
        if stance {
            let mut slot: u8 = 0;
            while slot < 4 {
                let old = self.effect_of(slot);
                if old.deadline >= t
                    && !old.potion
                    && old.carrier != 0
                    && *content.skill(old.carrier).kind == skill_kind::STANCE {
                    self.put(slot, held, item, content);
                    return slot;
                }
                slot += 1;
            }
        }
        // 3. The lowest free slot; 4. else the earliest deadline, ties the lowest slot.
        let mut earliest: u8 = 0;
        let mut earliest_deadline: u32 = 0xFFFFFFFF;
        let mut slot: u8 = 0;
        while slot < 4 {
            let deadline = self.effect_of(slot).deadline;
            if deadline < t {
                self.put(slot, held, item, content);
                return slot;
            }
            if deadline < earliest_deadline {
                earliest = slot;
                earliest_deadline = deadline;
            }
            slot += 1;
        }
        self.put(earliest, held, item, content);
        earliest
    }

    /// Writes `held` in `slot` with its pips: a potion's through its item, a skill's at its rank.
    fn put(ref self: Member, slot: u8, held: Held, item: u32, content: @Content) {
        let pips: i32 = if held.potion {
            (*content.potion(item).regen).into()
        } else {
            content.skill(held.carrier).regen(held.rank)
        };
        self.set_effect(slot, held, pips.try_into().unwrap());
    }

    /// Adrenaline gained, in quarters (§5.12): capped at the member's cap (its bar's highest
    /// cost, FX-12); one already at or above it keeps what it has.
    fn gain_adrenaline(ref self: Member, quarters: u16) {
        if self.adrenaline < self.adrenaline_cap {
            let gained = self.adrenaline + quarters;
            self.adrenaline = TickMathTrait::min16(gained, self.adrenaline_cap);
        }
    }

    /// A weapon hit landed (§5.5 step 8, §5.12): 4 quarters, 8 on every `N`-th hit of
    /// `ADRENALINE_EVERY_N` (the `hits` counter resets at N; N = 0: it stays 0).
    fn land_weapon_hit(ref self: Member) {
        let every = self.double_every();
        let mut quarters: u16 = 4;
        if every > 0 {
            let hits = self.hits() + 1;
            if hits == every {
                quarters = 8;
                self.set_hits(0);
            } else {
                self.set_hits(hits);
            }
        }
        self.gain_adrenaline(quarters);
    }

    /// A hit taken while alive (§5.12): 1 quarter.
    fn take_hit(ref self: Member) {
        if self.health > 0 {
            self.gain_adrenaline(1);
        }
    }
}
