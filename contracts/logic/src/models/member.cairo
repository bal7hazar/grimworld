//! A member in a world tick (CBT-02; design/19 §5, §7.2): its stored words, as `Instances` passes
//! them to the tick's library call, and its view inside the call (`models::index::MemberWords`,
//! `Member`). Its behaviour: loading the hot fields once and storing them back as deltas
//! (`MemberTrait`), the fields read and written in the words directly (`MemberWordsTrait`), the
//! activation's rules (`MemberTickTrait`) and the lifecycle's (`MemberLifecycleTrait`). The words'
//! layouts are the ephemeral package's, which owns the storage; the offsets below are ENG-01's
//! frozen ones, pinned by the ephemeral package's `test_tick_words`.

use crate::helpers::signed::SignedTrait;
use crate::helpers::tick::{TickAssert, TickMathTrait, errors as tick_errors};
use crate::packing::{
    N16, N2, N28, N32, N56, N7, N8, P112, P120, P16, P20, P24, P28, P32, P40, P48, P52, P56, P64,
    P72, P8, P80, P84, P96, field, limbs, peel,
};
use crate::types::combat::{condition, damage, skill_kind};
use crate::types::infliction::{Infliction, InflictionTrait};
use crate::types::tick::{
    ABSENT_LANE, ENERGY_THIRDS, Held, Index, IndexTrait, NO_SLOT, REGEN_OFFSET, Sheets, SkillSheet,
    SkillSheetTrait, flag, status,
};

pub use super::index::{Member, MemberWords};

const F8: felt252 = 0x100;
const F24: felt252 = 0x1000000;
const F28: felt252 = 0x10000000;
const F32: felt252 = 0x100000000;
const F40: felt252 = 0x10000000000;
const F56: felt252 = 0x100000000000000;
const F64: felt252 = 0x10000000000000000;
const F84: felt252 = 0x1000000000000000000000;
const F96: felt252 = 0x1000000000000000000000000;
const F128: felt252 = 0x100000000000000000000000000000000;
const F156: felt252 = 0x1000000000000000000000000000000000000000;
const F160: felt252 = 0x10000000000000000000000000000000000000000;
const F184: felt252 = 0x10000000000000000000000000000000000000000000000;
const F192: felt252 = 0x1000000000000000000000000000000000000000000000000;
const F212: felt252 = 0x100000000000000000000000000000000000000000000000000000;
const F112: felt252 = 0x10000000000000000000000000000;
const F48: felt252 = 0x1000000000000;
const F120: felt252 = 0x1000000000000000000000000000000;
const F168: felt252 = 0x1000000000000000000000000000000000000000000;
/// `MemberState`'s belt counts, 8 bits a slot from bit 128.
const BELT_LANES: [felt252; 4] = [
    F128, 0x10000000000000000000000000000000000, 0x1000000000000000000000000000000000000,
    0x100000000000000000000000000000000000000,
];
/// 2^92: the second quick-cast pair in `MemberBar`'s high limb.
const P92: u128 = 0x100000000000000000000000;
/// `Member.bar_at`'s lanes: bar slot `s`'s position at bits `16 s` (CBT-02d: one `u128`, where
/// eight `u32` made each copy of a member 7 felts longer).
const BAR_LANES: [u128; 8] = [1, P16, P32, 0x1000000000000, P64, P80, P96, P112];
/// `MemberStats`' bar ranks, 4 bits a slot from its high limb's bit 0.
const RANK_LANES: [u128; 8] = [1, 0x10, 0x100, 0x1000, 0x10000, 0x100000, 0x1000000, 0x10000000];
/// `MemberBar`'s `DAMAGE_PERCENT` sums by class, from its high limb's bit 8 (136 − 128).
const PASSIVE_LANES: [u128; 3] = [P8, P16, P24];
/// `MemberStats`' `ARMOR_VS` of types 3–9, from its high limb's bit 72 (200 − 128).
const VS_LANES: [u128; 7] = [P72, P78, P84, P90, P96, P102, P108];
const N88: NonZero<u128> = 0x10000000000000000000000;
const P26: u128 = 0x4000000;
const P54: u128 = 0x40000000000000;
const P74: u128 = 0x4000000000000000000;
const P78: u128 = 0x40000000000000000000;
const P90: u128 = 0x40000000000000000000000;
const P102: u128 = 0x40000000000000000000000000;
const P104: u128 = 0x100000000000000000000000000;
const P108: u128 = 0x1000000000000000000000000000;

pub mod errors {
    /// An effect's `REGENERATION` pips beyond an `i8` (the kind's bound is ±10).
    pub const REGEN: felt252 = 'member: regeneration above i8';
}

#[generate_trait]
pub impl MemberAssert of MemberAssertTrait {
    /// An effect's `REGENERATION` pips fit an `i8` (design/19 §3.1 bounds the kind to ±10).
    #[inline(always)]
    fn assert_pips(pips: i32) {
        assert(pips >= -128 && pips <= 127, errors::REGEN);
    }
}

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

    /// The hot fields of a member's words, in `Member`'s order (status … knocked). Each limb is
    /// read in one pass from its low bits, one division a field (CBT-02b, lever (b)).
    fn hot(words: @MemberWords) -> (u8, u16, u16, u16, u8, u8, u16, u8, u32, u32, u32, u32, u32) {
        let (low, high) = limbs(*words.state);
        // Bits 0–55 (the adventurer, position, facing) are not read.
        let (mut rest, _) = DivRem::div_rem(low, N56);
        let status = peel(ref rest, N8);
        let health = peel(ref rest, N16);
        let energy = peel(ref rest, N16);
        let adrenaline = peel(ref rest, N16);
        let (above, _) = DivRem::div_rem(high, N32);
        let (_, flags) = DivRem::div_rem(above, N8);
        let (tlow, thigh) = limbs(*words.timers);
        let mut rest = tlow;
        let act_slot = peel(ref rest, N8);
        let act_target = peel(ref rest, N16);
        let act_tile = peel(ref rest, N8);
        let act_deadline = peel(ref rest, N32);
        let bleeding = peel(ref rest, N32);
        // What is left is poison, bits 96–127, the limb's top.
        let poison = rest;
        let mut rest = thigh;
        let burning = peel(ref rest, N32);
        let _crippled = peel(ref rest, N32);
        let knocked = peel(ref rest, N32);
        (
            status.try_into().unwrap(),
            health.try_into().unwrap(),
            energy.try_into().unwrap(),
            adrenaline.try_into().unwrap(),
            flags.try_into().unwrap(),
            act_slot.try_into().unwrap(),
            act_target.try_into().unwrap(),
            act_tile.try_into().unwrap(),
            act_deadline.try_into().unwrap(),
            bleeding.try_into().unwrap(),
            poison.try_into().unwrap(),
            burning.try_into().unwrap(),
            knocked.try_into().unwrap(),
        )
    }

    /// A member from its words, with what it derives once: the maxima and regeneration of
    /// `MemberStats`, each held effect's deadline and `REGENERATION` pips (a skill's at the slot's
    /// rank, a potion's through the belt of `MemberKit`), its bar's positions in the content and
    /// its adrenaline cap (CBT-02d: the index reads each id once).
    fn load(words: MemberWords, ref index: Index, sheets: @Sheets) -> Member {
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
        let (mut stats, _) = limbs(words.stats);
        let max_health = peel(ref stats, N16);
        let max_energy = peel(ref stats, N8);
        let energy_regen = peel(ref stats, N8);
        let health_regen: i32 = peel(ref stats, N8).try_into().unwrap();
        let (elow, ehigh) = limbs(words.effects);
        // The four effects of 56 bits at 0 and 56 of each limb.
        let (above, first) = DivRem::div_rem(elow, N56);
        let (_, second) = DivRem::div_rem(above, N56);
        let (above, third) = DivRem::div_rem(ehigh, N56);
        let (_, fourth) = DivRem::div_rem(above, N56);
        let (belt, _) = limbs(words.kit);
        let mut deadlines: Array<u32> = array![];
        let mut regen: Array<i8> = array![];
        let mut effect_at: u128 = 0;
        let mut lane: u32 = 0;
        for effect in array![first, second, third, fourth] {
            let mut rest = effect;
            let carrier: u16 = peel(ref rest, N16).try_into().unwrap();
            // The charges and the free bit 22.
            let _ = peel(ref rest, N7);
            let potion = peel(ref rest, N2);
            deadlines.append(peel(ref rest, N28).try_into().unwrap());
            // What is left is the rank, bits 52–55 of the effect.
            let rank: u8 = rest.try_into().unwrap();
            // The potion tag first: with it, the carrier is a belt slot 0–3, slot 0 included
            // (ENG-01 §3.2; AUD-182-1). Without it, skill 0 is an empty slot.
            let shift = *BAR_LANES.span()[lane];
            let pips: i32 = if potion == 1 {
                let id = field(belt, *[1, P32, P64, P96].span()[carrier.into()], P32);
                let at = index.potion(id.try_into().unwrap());
                effect_at += at.into() * shift;
                (*(*sheets.potions)[at].regen).into()
            } else if carrier == 0 {
                effect_at += ABSENT_LANE * shift;
                0
            } else {
                let at = index.skill(carrier);
                effect_at += at.into() * shift;
                (*sheets.skills)[at].regen(rank)
            };
            MemberAssert::assert_pips(pips);
            regen.append(pips.try_into().unwrap());
            lane += 1;
        }
        // The bar's highest adrenaline cost, in quarters (§5.12).
        let (bar, _) = limbs(words.bar);
        let mut cap: u16 = 0;
        let mut rest = bar;
        let mut bar_at: u128 = 0;
        for shift in BAR_LANES.span() {
            let skill = peel(ref rest, N16);
            if skill == 0 {
                bar_at += ABSENT_LANE * *shift;
                continue;
            }
            let at = index.skill(skill.try_into().unwrap());
            bar_at += at.into() * *shift;
            let cost: u16 = (*(*sheets.skills)[at].adrenaline).into() * 4;
            if cost > cap {
                cap = cost;
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
            max_health: max_health.try_into().unwrap(),
            max_energy: max_energy.try_into().unwrap() * ENERGY_THIRDS,
            health_regen: (health_regen - REGEN_OFFSET).try_into().unwrap(),
            energy_regen: energy_regen.try_into().unwrap(),
            adrenaline_cap: cap,
            bar_at,
            effect_at,
            words,
        }
    }

    /// Its words, the hot fields written back (the effects word is the executor's to write). The
    /// hot fields lie in five regions of the words; each is rewritten whole, by the difference
    /// between its new value and the one the words hold (CBT-02b, lever (b): seven divisions,
    /// where a field at a time took twenty-six). `MemberTimers`' low limb is hot throughout.
    fn store(self: @Member) -> MemberWords {
        let words = *self.words;
        let (low, high) = limbs(words.state);
        let (above, _) = DivRem::div_rem(low, N56);
        let (_, old) = DivRem::div_rem(above, N56);
        let new: felt252 = (*self.status).into()
            + (*self.health).into() * F8
            + (*self.energy).into() * F24
            + (*self.adrenaline).into() * F40;
        let (above, _) = DivRem::div_rem(high, N32);
        let (_, old_flags) = DivRem::div_rem(above, N8);
        let state = words.state
            + (new - old.into()) * F56
            + ((*self.flags).into() - old_flags.into()) * F160;
        let (tlow, thigh) = limbs(words.timers);
        let new_low: felt252 = (*self.act_slot).into()
            + (*self.act_target).into() * F8
            + (*self.act_tile).into() * F24
            + (*self.act_deadline).into() * F32
            + (*self.bleeding).into() * F64
            + (*self.poison).into() * F96;
        let (above, old_burning) = DivRem::div_rem(thigh, N32);
        let (above, _) = DivRem::div_rem(above, N32);
        let (_, old_knocked) = DivRem::div_rem(above, N32);
        let timers = words.timers
            + (new_low - tlow.into())
            + ((*self.burning).into() - old_burning.into()) * F128
            + ((*self.knocked).into() - old_knocked.into()) * F192;
        MemberWords { state, timers, ..words }
    }

    /// The recharge deadline of bar slot 0–7.
    fn recharge(self: @Member, slot: u8) -> u32 {
        let (low, high) = limbs(*self.words.recharges);
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

    /// 1 if the member is inside at 0 health (the adventurer at 0, FX-8), else 0: what it adds
    /// to the world's count of members down.
    #[inline(always)]
    fn downs(self: @Member) -> u32 {
        if *self.status == status::INSIDE && *self.health == 0 {
            1
        } else {
            0
        }
    }

    /// Alive: inside, above 0 health (an actor the executor's entries reach, §5.14).
    #[inline(always)]
    fn is_alive(self: @Member) -> bool {
        *self.status == status::INSIDE && *self.health > 0
    }

    /// The skill id of bar slot 0–7 (`MemberBar`).
    #[inline(always)]
    fn skill(self: @Member, slot: u8) -> u16 {
        Self::bar_skill(*self.words.bar, slot)
    }

    /// The skill id of bar slot 0–7 in a `MemberBar` word (ENG-07: the content a batch reads is
    /// listed from the words, before any member is loaded).
    #[inline(always)]
    fn bar_skill(bar: felt252, slot: u8) -> u16 {
        let (low, _) = limbs(bar);
        let shift = *[1, P16, P32, 0x1000000000000, P64, P80, P96, P112].span()[slot.into()];
        field(low, shift, P16).try_into().unwrap()
    }

    /// The position in the content of bar slot 0–7's skill (`ABSENT_LANE` for an empty slot).
    #[inline(always)]
    fn position(self: @Member, slot: u8) -> u128 {
        field(*self.bar_at, *BAR_LANES.span()[slot.into()], P16)
    }

    /// The position in the content of effect slot 0–3's carrier: a skill's in `Sheets.skills`, a
    /// potion's in `Sheets.potions` (`ABSENT_LANE` for an empty slot).
    #[inline(always)]
    fn effect_position(self: @Member, slot: u8) -> u128 {
        field(*self.effect_at, *BAR_LANES.span()[slot.into()], P16)
    }

    /// The sheet of bar slot 0–7's skill, at its position (CBT-02d).
    #[inline(always)]
    fn sheet(self: @Member, slot: u8, sheets: @Sheets) -> @SkillSheet {
        (*sheets.skills)[self.position(slot).try_into().unwrap()]
    }
}

/// The fields of a member's words that are not hot: written only by the lifecycle rules
/// (`MemberTickTrait`, `MemberLifecycleTrait`), in the words directly, as the recharges are.
#[generate_trait]
pub impl MemberWordsImpl of MemberWordsTrait {
    /// Crippled's deadline (`MemberTimers` bits 160–191).
    fn crippled(self: @Member) -> u32 {
        let (_, high) = limbs(*self.words.timers);
        field(high, P32, P32).try_into().unwrap()
    }

    fn set_crippled(ref self: Member, deadline: u32) {
        let old = self.crippled();
        self.words.timers += TickMathTrait::delta(old.into(), deadline.into(), F160);
    }

    /// The `hits` counter (`MemberState` bits 112–119, design/19 §5.12).
    fn hits(self: @Member) -> u8 {
        let (low, _) = limbs(*self.words.state);
        field(low, P112, P8).try_into().unwrap()
    }

    fn set_hits(ref self: Member, hits: u8) {
        let old = self.hits();
        self.words.state += TickMathTrait::delta(old.into(), hits.into(), F112);
    }

    /// `ADRENALINE_EVERY_N`'s lowest N (`MemberKit` bits 160–167); 0 for none.
    fn double_every(self: @Member) -> u8 {
        let (_, high) = limbs(*self.words.kit);
        field(high, P32, P8).try_into().unwrap()
    }

    /// What it adds to the conditions it inflicts (`MemberKit` high limb: `CONDITION_DURATION`'s
    /// condition at 144–147 and percent at 148–153, `KNOCKDOWN_FLAT` at 200–201; design/19
    /// §5.7).
    fn infliction(self: @Member) -> Infliction {
        let (_, high) = limbs(*self.words.kit);
        Infliction {
            condition: field(high, P16, 0x10).try_into().unwrap(),
            percent: field(high, P20, 0x40).try_into().unwrap(),
            knockdown: field(high, P72, 4).try_into().unwrap(),
        }
    }

    /// Moves it to the location's tile `(x, y)` facing `facing` (`MemberState` 32–55; ENG-07's
    /// Move).
    fn set_place(ref self: Member, x: u8, y: u8, facing: u8) {
        let (ox, oy, old_facing) = MemberSnapshotTrait::place(@self);
        let old: felt252 = ox.into() + oy.into() * F8 + old_facing.into() * 0x10000;
        let new: felt252 = x.into() + y.into() * F8 + facing.into() * 0x10000;
        self.words.state += (new - old) * F32;
    }

    /// Its facing (`MemberState` 48–55), which the action phase turns (design/19 §5.3 step 3).
    fn set_facing(ref self: Member, facing: u8) {
        let (_, _, old) = MemberSnapshotTrait::place(@self);
        self.words.state += TickMathTrait::delta(old.into(), facing.into(), F48);
    }

    /// Quick-cast counter `k` (0: `MemberState.casts` 120–127; 1: `casts_2` 168–175; §5.12).
    fn casts(self: @Member, k: u8) -> u8 {
        let (low, high) = limbs(*self.words.state);
        let value = if k == 0 {
            field(low, P120, P8)
        } else {
            field(high, P40, P8)
        };
        value.try_into().unwrap()
    }

    fn set_casts(ref self: Member, k: u8, casts: u8) {
        let old = self.casts(k);
        let shift = if k == 0 {
            F120
        } else {
            F168
        };
        self.words.state += TickMathTrait::delta(old.into(), casts.into(), shift);
    }

    /// The count left in belt slot 0–3 (`MemberState` 128 + 8 slot).
    fn belt_count(self: @Member, slot: u8) -> u8 {
        let (_, high) = limbs(*self.words.state);
        field(high, *[1, P8, P16, P24].span()[slot.into()], P8).try_into().unwrap()
    }

    fn set_belt_count(ref self: Member, slot: u8, count: u8) {
        let old = self.belt_count(slot);
        self
            .words
            .state +=
                TickMathTrait::delta(old.into(), count.into(), *BELT_LANES.span()[slot.into()]);
    }

    /// The potion item of belt slot 0–3 (`MemberKit` bits `32 slot`).
    fn belt_item(self: @Member, slot: u16) -> u32 {
        Self::kit_item(*self.words.kit, slot)
    }

    /// The potion item of belt slot 0–3 in a `MemberKit` word.
    #[inline(always)]
    fn kit_item(kit: felt252, slot: u16) -> u32 {
        let (low, _) = limbs(kit);
        field(low, *[1, P32, P64, P96].span()[slot.into()], P32).try_into().unwrap()
    }

    /// The held effect of slot 0–3, as the word stores it.
    fn effect_of(self: @Member, slot: u8) -> Held {
        Self::held(*self.words.effects, slot)
    }

    /// The held effect of slot 0–3 in a `MemberEffects` word.
    fn held(effects: felt252, slot: u8) -> Held {
        let (low, high) = limbs(effects);
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

/// The fields of a member's words its hits and the executor's guards read (CBT-05a; ENG-01 §3.2,
/// design/19 §7.2 offsets): read in the words at each use, never written in play.
#[generate_trait]
pub impl MemberSnapshotImpl of MemberSnapshotTrait {
    /// Its tile and facing (`MemberState` x 32–39, y 40–47, facing 48–55).
    fn place(self: @Member) -> (u8, u8, u8) {
        let (low, _) = limbs(*self.words.state);
        let (mut rest, _) = DivRem::div_rem(low, N32);
        let x = peel(ref rest, N8);
        let y = peel(ref rest, N8);
        let facing = peel(ref rest, N8);
        (x.try_into().unwrap(), y.try_into().unwrap(), facing.try_into().unwrap())
    }

    /// Its level (`MemberStats` 64–71).
    fn level(self: @Member) -> u8 {
        let (low, _) = limbs(*self.words.stats);
        field(low, P64, P8).try_into().unwrap()
    }

    /// Its primary profession and its primary attribute's rank (`MemberStats` 72–79, 80–87).
    fn primary(self: @Member) -> (u8, u8) {
        let (low, _) = limbs(*self.words.stats);
        (field(low, P72, P8).try_into().unwrap(), field(low, P80, P8).try_into().unwrap())
    }

    /// Its weapon's tick cost `k` (`MemberStats` 104–111), at least 1 (design/04).
    fn weapon_ticks(self: @Member) -> u8 {
        let (low, _) = limbs(*self.words.stats);
        let k: u8 = field(low, P104, P8).try_into().unwrap();
        if k == 0 {
            1
        } else {
            k
        }
    }

    /// Its two quick-cast pairs (`MemberBar` 208–219, 220–231: the attribute's build-local
    /// index 4 bits, N 8 bits; design/19 §5.12, D-157 A), `(attribute, N)` each.
    fn quick_casts(self: @Member) -> [(u8, u8); 2] {
        let (_, high) = limbs(*self.words.bar);
        let first = field(high, P80, 0x1000);
        let second = field(high, P92, 0x1000);
        let (n0, a0) = DivRem::div_rem(first, 0x10);
        let (n1, a1) = DivRem::div_rem(second, 0x10);
        [
            (a0.try_into().unwrap(), n0.try_into().unwrap()),
            (a1.try_into().unwrap(), n1.try_into().unwrap()),
        ]
    }

    /// Its weapon (`MemberStats`): class 88–95, damage 96–103, range 112–119, strength
    /// 120–127 (the snapshot's `5 × rank` capped, `HitTrait::weapon_strength`), damage type
    /// 160–167, requirement met 176–183.
    fn weapon(self: @Member) -> (u8, u8, u8, u8, u8, bool) {
        let (low, high) = limbs(*self.words.stats);
        let (mut rest, _) = DivRem::div_rem(low, N88);
        let class = peel(ref rest, N8);
        let damage = peel(ref rest, N8);
        let _ticks = peel(ref rest, N8);
        let range = peel(ref rest, N8);
        let strength = rest;
        let damage_type = field(high, P32, P8);
        let met = field(high, P48, P8);
        (
            class.try_into().unwrap(),
            damage.try_into().unwrap(),
            range.try_into().unwrap(),
            strength.try_into().unwrap(),
            damage_type.try_into().unwrap(),
            met != 0,
        )
    }

    /// The rank of bar slot 0–7's skill (`MemberStats` 128 + 4 slot, 0–15).
    fn rank(self: @Member, slot: u8) -> u8 {
        let (_, high) = limbs(*self.words.stats);
        field(high, *RANK_LANES.span()[slot.into()], 0x10).try_into().unwrap()
    }

    /// Its `DAMAGE_PERCENT` sums of class `s` (0 plain weapon, 1 attack skill, 2 spell), unguarded
    /// and `ABOVE_HALF`, and its `PENETRATION` sum of the class (`MemberBar` 136 + 8 (3 g + s),
    /// 184 + 8 s; design/19 §7.2).
    fn passives(self: @Member, s: u8) -> (i16, i16, u16) {
        let (_, high) = limbs(*self.words.bar);
        let shift = *PASSIVE_LANES.span()[s.into()];
        let always = SignedTrait::from8(field(high, shift, P8));
        let above = SignedTrait::from8(field(high, shift * P24, P8));
        let penetration = field(high, shift * P48, P8);
        (always.into(), above.into(), penetration.try_into().unwrap())
    }

    /// Its unguarded armor (`MemberBar` 232–247, signed) and its guarded sums in a stance and
    /// enchanted (`MemberKit` 184–191, 192–199, signed; F-20).
    fn armor(self: @Member) -> (i16, i8, i8) {
        let (_, bar) = limbs(*self.words.bar);
        let (_, kit) = limbs(*self.words.kit);
        (
            SignedTrait::from16(field(bar, P104, P16)),
            SignedTrait::from8(field(kit, P56, P8)),
            SignedTrait::from8(field(kit, P64, P8)),
        )
    }

    /// Its `ARMOR_VS` of damage type 1–9 (`MemberStats` 48 + 6 (t − 1) for 1–2, 200 + 6 (t
    /// − 3)
    /// for 3–9; FX-23); 0 for none.
    fn armor_vs(self: @Member, damage_type: u8) -> u8 {
        if damage_type == 0 || damage_type > damage::LAST {
            return 0;
        }
        let (low, high) = limbs(*self.words.stats);
        let vs = if damage_type <= 2 {
            field(low, *[P48, P54].span()[(damage_type - 1).into()], 0x40)
        } else {
            field(high, *VS_LANES.span()[(damage_type - 3).into()], 0x40)
        };
        vs.try_into().unwrap()
    }

    /// `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT` (`MemberKit` 128–135, 136–143).
    fn on_hit(self: @Member) -> (u8, u8) {
        let (_, high) = limbs(*self.words.kit);
        let mut rest = high;
        let steal = peel(ref rest, N8);
        let energy = peel(ref rest, N8);
        (steal.try_into().unwrap(), energy.try_into().unwrap())
    }

    /// `ENCHANT_DURATION`'s percent (`MemberKit` 154–159).
    fn enchant_percent(self: @Member) -> u8 {
        let (_, high) = limbs(*self.words.kit);
        field(high, P26, 0x40).try_into().unwrap()
    }

    /// It holds `HALVE_FIRST_HEAVY_HIT` (`MemberKit` 202) and has not spent it (`flag::HALVED`).
    fn halves(self: @Member) -> bool {
        let (_, high) = limbs(*self.words.kit);
        field(high, P74, 2) == 1 && *self.flags & flag::HALVED == 0
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
    fn use_instant(ref self: Member, slot: u8, c: u32, sheets: @Sheets) {
        let r = *self.sheet(slot, sheets).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(c + 1, r));
    }

    /// Step 1 at `A`: the activation ends; its recharge counts from `A` (FX-2); returns its slot
    /// and target for the executor.
    fn conclude(ref self: Member, sheets: @Sheets) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let r = *self.sheet(slot, sheets).recharge;
        self.set_recharge(slot, TickMathTrait::recharge_deadline(self.act_deadline, r));
        self.clear();
        (slot, target)
    }

    /// Interrupted at `t₀` (§5.9: `c + 1` in the action phase, `T` in a tick): no effect, the
    /// recharge counts from `t₀` (FX-2). Nothing without an activation.
    fn interrupt(ref self: Member, t0: u32, sheets: @Sheets) {
        if self.act_slot == NO_SLOT {
            return;
        }
        let r = *self.sheet(self.act_slot, sheets).recharge;
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

    /// `CURE` at `t0` (§3.2): a duration of 0, `D = t0 − 1`; an absent condition, nothing. No
    /// alive check, unlike `MemberConditionTrait::apply`: the executor reaches living actors only
    /// (§5.14), and a member at 0 never acts again (FX-8), so its caller guards it.
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

    /// A holding effect applied at tick or clock `t` (§5.7), `stance` if its carrier is a stance,
    /// `at` its carrier's position in the content (a skill's, or a potion's: CBT-05a, no lookup
    /// by id); returns its slot. In order:
    /// 1. its carrier held (FX-42: the skill id, or a potion's item id through its belt slot):
    ///    the application with the later deadline is kept whole, the new one on a tie (FX-30);
    /// 2. else a stance while one is held: it takes that slot;
    /// 3. else the lowest free slot (never held, or its deadline passed);
    /// 4. else eviction: the earliest deadline, ties the lowest slot (FX-13).
    /// An effect ends by its deadline: one whose charges reach 0 is ended by the executor with a
    /// deadline of `t − 1`.
    fn hold(ref self: Member, held: Held, at: u32, stance: bool, t: u32, sheets: @Sheets) -> u8 {
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
                        self.put(slot, held, at, sheets);
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
                if old.deadline >= t && !old.potion && old.carrier != 0 {
                    let position = self.effect_position(slot);
                    if position != ABSENT_LANE
                        && *(*sheets.skills)[position
                            .try_into()
                            .unwrap()]
                            .kind == skill_kind::STANCE {
                        self.put(slot, held, at, sheets);
                        return slot;
                    }
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
                self.put(slot, held, at, sheets);
                return slot;
            }
            if deadline < earliest_deadline {
                earliest = slot;
                earliest_deadline = deadline;
            }
            slot += 1;
        }
        self.put(earliest, held, at, sheets);
        earliest
    }

    /// Writes `held` in `slot` with its pips and its carrier's position `at`: a potion's sheet,
    /// a skill's at its rank.
    fn put(ref self: Member, slot: u8, held: Held, at: u32, sheets: @Sheets) {
        let pips: i32 = if held.potion {
            (*(*sheets.potions)[at].regen).into()
        } else {
            (*sheets.skills)[at].regen(held.rank)
        };
        MemberAssert::assert_pips(pips);
        self.set_effect(slot, held, pips.try_into().unwrap());
        let shift = *BAR_LANES.span()[slot.into()];
        let old = self.effect_position(slot);
        self.effect_at = self.effect_at - old * shift + at.into() * shift;
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

/// The five conditions' rules on a member (CBT-04; design/19 §3.2, §5.2, §5.6, §5.7, §5.9),
/// for the executor (CBT-05), the hit (CBT-03a, through booleans) and movement (ENG-07). Every `t0`
/// is the tick the rule acts at: `c + 1` in the action phase at clock `c`, `T` in a tick (§5.1).
#[generate_trait]
pub impl MemberConditionImpl of MemberConditionTrait {
    /// A `CONDITION` entry (or an `ON_ATTACK_CONDITION`'s) applied at `t0`: condition 1–4 for
    /// the value `v`, through the source's `Infliction` (`effective_duration`), refreshed by
    /// `max` (FX-6); nothing on a member not alive. Knocked down is `knock`'s: the executor
    /// dispatches on the entry's condition (SPK-15's L2, D-172). Written in place: one branch
    /// writes the condition's field, Crippled's word read once; no call but the inlined ones, so
    /// no application pays the knock-down's interrupt (a function without a loop is charged its
    /// costliest path).
    fn apply(ref self: Member, condition: u8, v: i32, source: @Infliction, t0: u32) {
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
            // `MemberWordsTrait::crippled`, read here: bits 160–191 of `MemberTimers`.
            let (_, high) = limbs(self.words.timers);
            let old: u32 = field(high, P32, P32).try_into().unwrap();
            let new = TickMathTrait::refreshed(old, t0, d);
            self.words.timers += TickMathTrait::delta(old.into(), new.into(), F160);
        }
    }

    /// Knocked down for the value `v` at `t0` (its `CONDITION` entry, or an
    /// `ON_ATTACK_CONDITION`'s), through the source's `Infliction` (`KNOCKDOWN_FLAT`), refreshed
    /// by `max` (FX-31); nothing on a member not alive. It interrupts the activation (§5.9):
    /// energy stays paid, the recharge counts from `t0`, no effect (FX-2, FX-4). A knock-down
    /// that does not lengthen a held one interrupts too; it finds no activation (a knocked-down
    /// member's only action is Wait, FX-7, and the first knock-down interrupted the activation).
    fn knock(ref self: Member, v: i32, source: @Infliction, t0: u32, sheets: @Sheets) {
        if !self.is_alive() {
            return;
        }
        let d = source.duration(condition::KNOCKED_DOWN, v);
        self.knocked = TickMathTrait::refreshed(self.knocked, t0, d);
        self.interrupt(t0, sheets);
    }

    /// Condition 1–5 held at `t0` (`t0 ≤ D`).
    #[inline(always)]
    fn holds(self: @Member, condition: u8, t0: u32) -> bool {
        TickMathTrait::held(self.condition(condition), t0)
    }

    /// Not knocked down at `t0`: an action other than Wait is legal (§5.2, FX-7).
    #[inline(always)]
    fn can_act(self: @Member, t0: u32) -> bool {
        !TickMathTrait::held(*self.knocked, t0)
    }

    /// Knocked down at `t0`: a weapon hit on it is critical from any arc (§3.2), for CBT-03a.
    #[inline(always)]
    fn takes_critical(self: @Member, t0: u32) -> bool {
        TickMathTrait::held(*self.knocked, t0)
    }

    /// Not knocked down at `t0`: it may block or evade (§5.6, FX-7), for CBT-03a.
    #[inline(always)]
    fn can_defend(self: @Member, t0: u32) -> bool {
        !TickMathTrait::held(*self.knocked, t0)
    }

    /// The ticks its move of one tile costs at `t0`: 2 while Crippled, unless `movement` (a
    /// `MOVEMENT` effect held, FX-18), else 1 (§3.2, §5.3 step 5), for ENG-07.
    #[inline(always)]
    fn move_ticks(self: @Member, t0: u32, movement: bool) -> u8 {
        TickMathTrait::move_ticks(self.crippled(), t0, movement)
    }
}

/// A member's unit tests (CBT-02, CBT-02d, CBT-04; D-167): its load and store, its decoder, its
/// lifecycle rules, its conditions' rules, its checks.
#[cfg(test)]
mod tests {
    use crate::types::combat::{condition, skill_kind};
    use crate::types::infliction::{Infliction, InflictionTrait};
    use crate::types::tick::{ABSENT_LANE, Content, ContentTrait, NO_SLOT, Sheets, flag, status};
    use crate::types::world::fixtures::{Fixture, LIVE, opaque, two};
    use super::{
        Member, MemberAssert, MemberConditionTrait, MemberLifecycleTrait, MemberTickTrait,
        MemberTrait, MemberWordsTrait,
    };

    /// A member whose kit holds "Rending" (`CONDITION_DURATION` Bleeding +33 %) and
    /// *Hob-breaker*'s `KNOCKDOWN_FLAT` +1.
    fn rending() -> Member {
        let mut words = Fixture::member_words(Fixture::spec());
        words.kit += condition::BLEEDING.into() * two(144) + 33 * two(148) + two(200);
        Fixture::load_member(words, @Fixture::content())
    }

    // CBT-04, applying (§5.7, §3.2's `CONDITION`): the kit's passives read in the words; Rending
    // Cut's Bleeding 20 at t0 = 10 lasts 26 ticks (D = 35), Poison 20 takes no percent (D = 29),
    // Skullring's Knocked down 2 takes the flat +1 (D = 12); every condition 1–5 lands in its
    // field and survives the words.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 7674555)] // ceil(1.05 × 7309100 measured)
    fn test_member_apply() {
        let sheets = Fixture::sheets();
        let mut member = rending();
        let source = member.infliction();
        assert(
            source == Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 },
            'kit read',
        );
        member.apply(condition::BLEEDING, 20, @source, 10);
        member.apply(condition::POISON, 20, @source, 10);
        member.apply(condition::BURNING, 3, @source, 10);
        member.apply(condition::CRIPPLED, 4, @source, 10);
        member.knock(2, @source, 10, @sheets);
        assert(member.bleeding == 35 && member.poison == 29 && member.burning == 12, 'pips');
        assert(member.crippled() == 13 && member.knocked == 12, 'crippled, knocked');
        let again = Fixture::load_member(member.store(), @Fixture::content());
        assert(again.bleeding == 35 && again.crippled() == 13 && again.knocked == 12, 'stored');
        assert(again.holds(condition::BURNING, 12) && !again.holds(condition::BURNING, 13), 'D');
    }

    // FX-6, FX-31 (§6): applied again while held, at an equal duration and a smaller one, the
    // deadline is kept; at a larger, refreshed; Knocked down likewise; a value of 0 is clamped
    // to 1 (§6), never a cure. A cure of an absent condition changes nothing.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5543192)] // ceil(1.05 × 5279230 measured)
    fn test_member_apply_refresh() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut member = Fixture::member(Fixture::spec());
        member.apply(condition::POISON, 8, @none, 70);
        member.apply(condition::POISON, 8, @none, 70);
        assert(member.poison == 77, 'equal: kept');
        member.apply(condition::POISON, 2, @none, 74);
        assert(member.poison == 77, 'smaller: kept');
        member.apply(condition::POISON, 0, @none, 77);
        assert(member.poison == 77, '0 is 1 tick, not a cure');
        member.knock(2, @none, 52, @sheets);
        member.knock(1, @none, 53, @sheets);
        assert(member.knocked == 53, 'knock-down: max');
        member.knock(3, @none, 53, @sheets);
        assert(member.knocked == 55, 'knock-down refreshed');
        let before = member;
        member.cure(condition::BURNING, 60);
        assert(member == before, 'absent cure: nothing');
    }

    // Nothing applies to a member not alive (§5.14: the entries reach living actors): at 0
    // health, or down.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5344469)] // ceil(1.05 × 5089970 measured)
    fn test_member_apply_not_alive() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut member = Fixture::member(Fixture::spec());
        member.health = 0;
        member.apply(condition::BLEEDING, 5, @none, 10);
        assert(member.bleeding == 0, 'at 0: nothing');
        member.health = 10;
        member.status = status::DOWN;
        member.knock(5, @none, 10, @sheets);
        assert(member.knocked == 0, 'down: nothing');
    }

    // §5.9, design/19 §10.6: the spell started at clock 200 (activation 2, A = 202); a goblin's
    // knock-down in step 2 of tick 201 interrupts it: the field goes to none, the recharge
    // counts from t0 = 201 (R = 201 + 10 − 1 = 210), energy stays paid. Without an activation a
    // knock-down changes nothing but its deadline.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 15205512)] // ceil(1.05 × 14481440 measured)
    fn test_member_knockdown_interrupts() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut member = Fixture::member(Fixture::spec());
        member.start(2, 9, 2, 200);
        assert(member.act_deadline == 202, 'A = 202');
        member.knock(2, @none, 201, @sheets);
        assert(member.act_slot == NO_SLOT && member.act_deadline == 0, 'interrupted');
        assert(member.recharge(2) == 210 && member.energy == 30, 'R = 210, energy paid');
        assert(member.knocked == 202, 'D = 202');
        let mut idle = Fixture::member(Fixture::spec());
        idle.knock(2, @none, 201, @sheets);
        let mut expected = Fixture::member(Fixture::spec());
        expected.knocked = 202;
        assert(idle == expected, 'no activation: deadline only');
    }

    // §3.2 row 5 (§5.2, §5.6, FX-7): knocked down to D = 53, the adventurer's only action is
    // Wait in the action phase at clocks 51 and 52 (t0 = c + 1 ≤ 53), any at 53; a weapon hit
    // on it is critical from any arc and it neither blocks nor evades through tick 53.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 4878395)] // ceil(1.05 × 4646090 measured)
    fn test_member_knocked_predicates() {
        let mut member = Fixture::member(Fixture::spec());
        member.knocked = 53;
        assert(!member.can_act(51 + 1) && !member.can_act(52 + 1), 'only Wait');
        assert(member.can_act(53 + 1), 'acts at clock 53');
        assert(member.takes_critical(53) && !member.can_defend(53), 'tick 53: exposed');
        assert(!member.takes_critical(54) && member.can_defend(54), 'tick 54: not');
    }

    // §3.2 row 4 (FX-15, FX-18): Crippled to D = 62, a move at clock 61 (t0 = 62) costs 2 ticks;
    // at clock 62 (t0 = 63), 1; with a `MOVEMENT` effect, 1.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 4915460)] // ceil(1.05 × 4681390 measured)
    fn test_member_crippled_move() {
        let mut member = Fixture::member(Fixture::spec());
        assert(member.move_ticks(10, false) == 1, 'not crippled');
        member.set_crippled(62);
        assert(member.move_ticks(61 + 1, false) == 2, 'crippled: 2');
        assert(member.move_ticks(62 + 1, false) == 1, 'over: 1');
        assert(member.move_ticks(61 + 1, true) == 1, 'movement: 1');
    }

    /// CBT-04's application before SPK-15's L2 (fix loop 2, D-172), kept as the oracle of the
    /// in-place `apply` and `knock` (docs/CAIRO.md §2): the lifecycle's `inflict`, then the
    /// interrupt on a knock-down.
    fn oracle(
        ref member: Member, condition: u8, v: i32, source: @Infliction, t0: u32, sheets: @Sheets,
    ) {
        if !member.is_alive() {
            return;
        }
        member.inflict(condition, t0, source.duration(condition, v));
        if condition == condition::KNOCKED_DOWN {
            member.interrupt(t0, sheets);
        }
    }

    // L2's equivalence (fix loop 2): `apply` (conditions 1–4) and `knock` give the oracle's
    // member on every condition, at the values 1, 20, 0 (clamped to 1) and 40,000 (clamped to
    // 32,767), with "Rending" and without a passive, activating or not, a condition held to be
    // kept or raised, alive or not (at 0 health, down).
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 37639067)] // ceil(1.05 × 35846730 measured)
    fn test_member_apply_matches_oracle() {
        let sheets = Fixture::sheets();
        let rending = Infliction { condition: condition::BLEEDING, percent: 33, knockdown: 1 };
        let none: Infliction = Default::default();
        let (activating, _) = condition_cost_state();
        let mut held = Fixture::member(Fixture::spec());
        held.poison = 230;
        held.knocked = 230;
        held.set_crippled(230);
        let mut zero = activating;
        zero.health = 0;
        let mut down = activating;
        down.status = status::DOWN;
        let states = array![activating, held, zero, down];
        let conditions = array![
            condition::BLEEDING, condition::POISON, condition::BURNING, condition::CRIPPLED,
            condition::KNOCKED_DOWN,
        ];
        for state in states.span() {
            for c in conditions.span() {
                for v in array![1_i32, 20, 0, 40000].span() {
                    for source in array![rending, none].span() {
                        let mut expected = *state;
                        oracle(ref expected, *c, *v, source, 201, @sheets);
                        let mut member = *state;
                        if *c == condition::KNOCKED_DOWN {
                            member.knock(*v, source, 201, @sheets);
                        } else {
                            member.apply(*c, *v, source, 201);
                        }
                        assert(member == expected, 'as the oracle');
                    }
                }
            }
        }
    }

    // `apply` refuses Knocked down: the executor sends it to `knock` (a dispatch error, not a
    // legal action's outcome).
    #[test]
    #[should_panic(expected: 'tick: knock-down is knock')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 4885923)] // ceil(1.05 × 4653260 measured)
    fn test_member_apply_knockdown_refused() {
        let mut member = Fixture::member(Fixture::spec());
        let none: Infliction = Default::default();
        member.apply(condition::KNOCKED_DOWN, 2, @none, 10);
    }

    // The Sonnet run's note (fix loop 2): a knock-down that does not lengthen a held one still
    // interrupts, and finds nothing to interrupt (a knocked-down member's only action is Wait).
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5410986)] // ceil(1.05 × 5153320 measured)
    fn test_member_knock_refresh_not_longer() {
        let sheets = Fixture::sheets();
        let none: Infliction = Default::default();
        let mut member = Fixture::member(Fixture::spec());
        member.knocked = 60;
        let before = member;
        member.knock(2, @none, 55, @sheets);
        assert(member == before, 'nothing: kept, no activation');
    }

    // The cost of the rules (CBT-04, AC-4; fix loop 2), by pairs: each test differs from
    // `test_cost_member_condition_base` by its call alone, so the difference of snforge's totals
    // is the call's cost. An application's source is given (an executor reads a member's kit
    // once a carrier, `test_cost_member_infliction`, and a goblin source has none). `knock`'s
    // costliest path is an interrupt of an activation; `apply`'s is Crippled's word. The other
    // paths, measured to show that each function is charged one cost whatever path runs: a
    // knock-down on a member without an activation that does not lengthen a held one, and an
    // application on a member not alive.
    fn condition_cost_state() -> (Member, Sheets) {
        let mut member = opaque(Fixture::member(Fixture::spec()));
        member.start(opaque(2), 9, 2, opaque(200));
        member.bleeding = opaque(205);
        (member, opaque(Fixture::sheets()))
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5383182)] // ceil(1.05 × 5126840 measured)
    fn test_cost_member_condition_base() {
        let (member, _sheets) = condition_cost_state();
        opaque(member);
    }

    // The base of the pairs that give a source.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5384022)] // ceil(1.05 × 5127640 measured)
    fn test_cost_member_source_base() {
        let (member, _sheets) = condition_cost_state();
        let _source: Infliction = opaque(Default::default());
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5403132)] // ceil(1.05 × 5145840 measured)
    fn test_cost_member_infliction() {
        let (member, _sheets) = condition_cost_state();
        opaque(member.infliction());
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5443274)] // ceil(1.05 × 5184070 measured)
    fn test_cost_member_knock() {
        let (mut member, sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        member.knock(opaque(2), @source, opaque(201), @sheets);
        opaque(member);
    }

    // The other paths' bases: no activation and a longer knock-down held; at 0 health.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5385492)] // ceil(1.05 × 5129040 measured)
    fn test_cost_member_idle_base() {
        let (mut member, _sheets) = condition_cost_state();
        member.clear();
        member.knocked = opaque(230);
        let _source: Infliction = opaque(Default::default());
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5385492)] // ceil(1.05 × 5129040 measured)
    fn test_cost_member_zero_base() {
        let (mut member, _sheets) = condition_cost_state();
        member.health = opaque(0);
        let _source: Infliction = opaque(Default::default());
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5443694)] // ceil(1.05 × 5184470 measured)
    fn test_cost_member_knock_idle() {
        let (mut member, sheets) = condition_cost_state();
        member.clear();
        member.knocked = opaque(230);
        let source: Infliction = opaque(Default::default());
        member.knock(opaque(2), @source, opaque(201), @sheets);
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5418137)] // ceil(1.05 × 5160130 measured)
    fn test_cost_member_apply_crippled() {
        let (mut member, _sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        member.apply(opaque(condition::CRIPPLED), opaque(20), @source, opaque(201));
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5418137)] // ceil(1.05 × 5160130 measured)
    fn test_cost_member_apply_bleeding() {
        let (mut member, _sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        member.apply(opaque(condition::BLEEDING), opaque(20), @source, opaque(201));
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5418557)] // ceil(1.05 × 5160530 measured)
    fn test_cost_member_apply_not_alive() {
        let (mut member, _sheets) = condition_cost_state();
        member.health = opaque(0);
        let source: Infliction = opaque(Default::default());
        member.apply(opaque(condition::CRIPPLED), opaque(20), @source, opaque(201));
        opaque(member);
    }

    // The pre-L2 application, the oracle, as a pair: what L2 saves on a knock-down.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5480601)] // ceil(1.05 × 5219620 measured)
    fn test_cost_member_oracle() {
        let (mut member, sheets) = condition_cost_state();
        let source: Infliction = opaque(Default::default());
        oracle(
            ref member, opaque(condition::KNOCKED_DOWN), opaque(2), @source, opaque(201), @sheets,
        );
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5422064)] // ceil(1.05 × 5163870 measured)
    fn test_cost_member_cure() {
        let (mut member, _sheets) = condition_cost_state();
        member.cure(opaque(condition::BLEEDING), opaque(201));
        opaque(member);
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5394869)] // ceil(1.05 × 5137970 measured)
    fn test_cost_member_predicates() {
        let (member, _sheets) = condition_cost_state();
        let t = opaque(201);
        opaque(member.can_act(t));
        opaque(member.takes_critical(t));
        opaque(member.can_defend(t));
        opaque(member.move_ticks(t, opaque(false)));
        opaque(member);
    }

    // `load` reads the hot fields of the words and derives the rest; `store` writes them back as
    // deltas, every other bit kept: a round trip is the identity, a change lands where it belongs.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 11247380)] // ceil(1.05 × 10711790 measured)
    fn test_member_load_store() {
        let mut spec = Fixture::spec();
        spec.conditions = [11, 12, 13, 14];
        spec.adrenaline = 7;
        spec.flags = flag::HALVED;
        let words = Fixture::member_words(spec);
        let content = Fixture::content();
        let member = Fixture::load_member(words, @content);
        assert(member == Fixture::member(spec), 'load reads the words');
        assert(member.store() == words, 'round trip');
        let mut member = member;
        member.health = 1;
        member.knocked = 99;
        member.start(3, 17, 2, 70);
        let words = member.store();
        let again = Fixture::load_member(words, @content);
        assert(again == super::Member { words, ..member }, 'store writes the fields');
    }

    // CBT-02d: the bar's positions in the content, found once at the load; an empty slot holds
    // none.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 6050258)] // ceil(1.05 × 5762150 measured)
    fn test_member_bar_positions() {
        let mut words = Fixture::member_words(Fixture::spec());
        // Bar slot 7 empty, slot 0 skill 8: the content lists 8 first.
        words.bar = LIVE + 8 + 2 * two(16) + 3 * two(32) + 4 * two(48) + 5 * two(64);
        words.bar += 6 * two(80) + 7 * two(96);
        let mut skills = array![Fixture::skill(8, skill_kind::SPELL, 1, 10)];
        for id in 1..8_u16 {
            skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
        }
        let content = Content {
            skills: skills.span(), potions: array![].span(), castes: array![].span(),
        };
        let member = Fixture::load_member(words, @content);
        let mut positions = array![];
        for slot in 0..8_u8 {
            positions.append(member.position(slot));
        }
        assert(positions == array![0, 2, 3, 4, 5, 6, 7, ABSENT_LANE], 'positions');
        assert(*member.sheet(0, @content.sheets()).id == 8, 'its sheet');
    }

    // AUD-182-9: the words' decoder is the member's own (`MemberTrait::hot`).
    #[test]
    #[available_gas(l2_gas: 4906986)] // ceil(1.05 × 4673320 measured)
    fn test_member_hot() {
        let mut spec = Fixture::spec();
        spec.conditions = [11, 12, 13, 14];
        let words = Fixture::member_words(spec);
        let (status, health, _, _, _, slot, _, _, _, bleeding, _, _, knocked) = MemberTrait::hot(
            @words,
        );
        assert(status == status::INSIDE && health == 400 && slot == NO_SLOT, 'member');
        assert(bleeding == 11 && knocked == 14, 'member timers');
    }

    // AUD-182-6, conditions (§5.7, FX-6, FX-31; design/19 §10.3): Bleeding to 77, inflicted again
    // at 74 for 8 ticks, refreshes to 81; for 2 ticks, keeps 77 (`max`, not a replacement);
    // Knocked down likewise; Crippled lives in the words; a cure at 76 gives 75; an absent
    // condition is untouched.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5693174)] // ceil(1.05 × 5422070 measured)
    fn test_member_conditions() {
        let mut member = Fixture::member(Fixture::spec());
        member.inflict(condition::BLEEDING, 70, 8);
        assert(member.bleeding == 77, 'D = 70 + 8 - 1');
        member.inflict(condition::BLEEDING, 74, 2);
        assert(member.bleeding == 77, 'max keeps 77');
        member.inflict(condition::BLEEDING, 74, 8);
        assert(member.bleeding == 81, 'refreshed to 81');
        member.inflict(condition::KNOCKED_DOWN, 52, 2);
        member.inflict(condition::KNOCKED_DOWN, 52, 1);
        assert(member.knocked == 53, 'knock-down refreshed');
        member.inflict(condition::CRIPPLED, 60, 3);
        assert(member.crippled() == 62, 'crippled in the words');
        let words = member.store();
        let again = Fixture::load_member(words, @Fixture::content());
        assert(again.crippled() == 62 && again.bleeding == 81, 'stored');
        member.cure(condition::BLEEDING, 76);
        assert(member.bleeding == 75, 'cured: D = 75');
        member.cure(condition::POISON, 76);
        assert(member.poison == 0, 'absent: nothing');
    }

    // AUD-182-6, held effects (§5.7; design/19 §10.4): four effects held and no stance; Sidestep
    // at clock 80 (`t₀` 81, `D` 86) evicts the earliest deadline, 85, ties to the lowest slot:
    // Warcry in slot 1. Brace at 82, a stance while one is held, takes Sidestep's slot.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 8446830)] // ceil(1.05 × 8044600 measured)
    fn test_hold_eviction_and_stance() {
        let content = Fixture::hold_content();
        let sheets = content.sheets();
        let mut spec = Fixture::spec();
        spec
            .effects =
                [(11, false, 90, 12), (12, false, 85, 12), (13, false, 85, 12), (3, true, 100, 0)];
        let mut member = Fixture::load_member(Fixture::member_words(spec), @content);
        let slot = member.hold(Fixture::held(14, false, 86, 12), 11, true, 81, @sheets);
        assert(slot == 1 && member.effect_of(1) == Fixture::held(14, false, 86, 12), 'evicted');
        let slot = member.hold(Fixture::held(15, false, 90, 12), 12, true, 83, @sheets);
        assert(slot == 1 && member.effect_of(1).carrier == 15, 'stance replaces stance');
        assert(member.effect_regen == [0, 1, 0, 4], 'pips follow');
        assert(member.effect_deadlines == [90, 90, 85, 100], 'deadlines follow');
        // A free slot (a deadline passed) is taken before any eviction, the lowest first.
        let slot = member.hold(Fixture::held(12, false, 95, 12), 9, false, 86, @sheets);
        assert(slot == 2, 'lowest free slot');
        // The words round-trip what was held.
        let again = Fixture::load_member(member.store(), @content);
        assert(again.effect_of(2) == Fixture::held(12, false, 95, 12), 'stored');
    }

    // AUD-182-6, refresh (FX-30, FX-42): the same carrier keeps the later deadline, whole; the new
    // one on a tie; two belt slots holding the same potion item are one carrier.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 8087846)] // ceil(1.05 × 7702710 measured)
    fn test_hold_refresh() {
        let content = Fixture::hold_content();
        let sheets = content.sheets();
        let mut spec = Fixture::spec();
        spec.effects = [(11, false, 90, 4), (0, false, 0, 0), (0, false, 0, 0), (0, false, 0, 0)];
        let mut member = Fixture::load_member(Fixture::member_words(spec), @content);
        member.hold(Fixture::held(11, false, 88, 12), 8, false, 81, @sheets);
        assert(member.effect_of(0) == Fixture::held(11, false, 90, 4), 'earlier: kept');
        member.hold(Fixture::held(11, false, 90, 12), 8, false, 81, @sheets);
        assert(member.effect_of(0) == Fixture::held(11, false, 90, 12), 'tie: the new one');
        member.hold(Fixture::held(11, false, 95, 7), 8, false, 81, @sheets);
        assert(member.effect_of(0) == Fixture::held(11, false, 95, 7), 'later: replaced whole');
        // Belt slots 0 and 2 hold one item: one carrier.
        let mut words = member.store();
        words.kit = LIVE + 100 + 101 * two(32) + 100 * two(64) + 103 * two(96);
        let mut member = Fixture::load_member(words, @content);
        let first = member.hold(Fixture::held(0, true, 99, 0), 0, false, 81, @sheets);
        let second = member.hold(Fixture::held(2, true, 120, 0), 0, false, 81, @sheets);
        assert(first == 1 && second == 1, 'same potion, same slot');
        assert(member.effect_of(1) == Fixture::held(2, true, 120, 0), 'later potion kept');
    }

    // AUD-182-6, adrenaline gain (§5.12, FX-12): 4 quarters a weapon hit landed, 8 on every N-th
    // hit (`hits` resets at N), 1 a hit taken; each gain capped at the bar's highest adrenaline
    // cost (6 strikes: 24 quarters).
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 5776449)] // ceil(1.05 × 5501380 measured)
    fn test_member_adrenaline_gain() {
        let mut skills = array![];
        for id in 1..9_u16 {
            let mut sheet = Fixture::skill(id, skill_kind::ATTACK, 0, 0);
            sheet.adrenaline = if id == 2 {
                6
            } else {
                0
            };
            skills.append(sheet);
        }
        let content = Content {
            skills: skills.span(), potions: array![].span(), castes: array![].span(),
        };
        let mut words = Fixture::member_words(Fixture::spec());
        // `ADRENALINE_EVERY_N` = 3 in the kit (bits 160–167).
        words.kit += 3 * two(160);
        let mut member = Fixture::load_member(words, @content);
        assert(member.adrenaline_cap == 24, 'cap: 6 strikes');
        member.land_weapon_hit();
        member.land_weapon_hit();
        assert(member.adrenaline == 8 && member.hits() == 2, 'two hits: 8');
        member.land_weapon_hit();
        assert(member.adrenaline == 16 && member.hits() == 0, 'third doubled, reset');
        member.take_hit();
        assert(member.adrenaline == 17, 'a hit taken: 1');
        member.land_weapon_hit();
        member.land_weapon_hit();
        assert(member.adrenaline == 24, 'capped at 24');
    }

    #[test]
    #[should_panic(expected: 'member: regeneration above i8')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_member_assert_pips() {
        MemberAssert::assert_pips(128);
    }
}
