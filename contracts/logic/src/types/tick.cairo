//! The state a world tick reads and writes, and the content it reads (CBT-02; design/19 §5,
//! §7.2).
//!
//! **Words in, words out.** The library call takes and returns the stored words (`Words`): a
//! member's four words that change in play (`MemberState`, `MemberTimers`, `MemberEffects`,
//! `Recharges`, ENG-01 §3.2) with the three snapshot words it reads, a goblin's two
//! (`GoblinState`, `GoblinTimers`), as `Instances` reads and writes them. Inside the call, each
//! actor's **hot fields** (what the ticks read and write) are unpacked once (`load`) into a small
//! struct, the ticks work on them, and they are written back into the words as deltas (`store`).
//! Measured (CBT-02's report): the words alone cost a limb split per read, a struct of every field
//! cost its copies; this is the cheapest of the three.
//!
//! The words' layouts are the ephemeral package's (it owns the storage); the offsets below are
//! ENG-01's frozen ones, and the ephemeral package's tests pin `load` and `store` against its
//! packers (`test_tick_words`).
//!
//! Beside the hot fields, each actor carries what the tick derives **once per call** from the
//! snapshot and the content (D-145: content read once per batch, kept in memory): its maxima, its
//! regeneration, and each held effect's `REGENERATION` pips at its rank. The executor (CBT-05)
//! sets an effect's pips and deadline when it holds one.

use crate::helpers::signed::SignedTrait;
use crate::models::caste::Caste;
use crate::models::index::{Item, Skill};
use crate::packing::{
    P112, P16, P24, P28, P32, P40, P52, P56, P64, P72, P8, P80, P84, P88, P96, field, low_field,
    split,
};
use crate::types::effect::{EntryTrait, kind};

/// Adrenaline lost a tick out of combat, in quarter strikes (design/19 §5.8, FX-12): a code
/// constant until BAL-01, **1** by D-157 E.
pub const ADRENALINE_DECAY: u16 = 1;
/// Health pips are clamped to ±10 (design/03, *Pips*); one pip is 2 health a tick.
pub const MAX_PIPS: i32 = 10;
pub const HEALTH_PER_PIP: i32 = 2;
/// Energy is in thirds (design/03: one pip is one energy every 3 ticks).
pub const ENERGY_THIRDS: u16 = 3;
/// Stored health regeneration is its pips + 10 (`MemberStats.health_regen`, `Caste.health_regen`).
pub const REGEN_OFFSET: i32 = 10;
/// A goblin's adrenaline field holds at most 63 strikes, in quarters (design/19 §5.12).
pub const MAX_GOBLIN_ADRENALINE: u8 = 252;
/// No member activation (`MemberTimers.act_slot`, ENG-01).
pub const NO_SLOT: u8 = 255;

/// `MemberState.status` (ENG-01 §3.2).
pub mod status {
    pub const INSIDE: u8 = 0;
    pub const DOWN: u8 = 1;
    pub const GONE: u8 = 2;
}

/// `GoblinState.ai` (ENG-01 §3.2, design/04).
pub mod ai {
    pub const ASLEEP: u8 = 0;
    pub const WATCH: u8 = 1;
    pub const ALERTED: u8 = 2;
    pub const ENGAGED: u8 = 3;
    pub const FLEEING: u8 = 4;
    pub const RETURNING: u8 = 5;
    pub const DEAD: u8 = 6;
    pub const LOOTED: u8 = 7;
}

/// `MemberState.flags`: what happened "since the last tick" (ENG-01 §3.2) and "hit this tick"
/// (design/19 §7.2, §5.10), which a tick's step 0 clears; `HALVED` is spent once an instance.
pub mod flag {
    pub const TURNED: u8 = 1;
    pub const INSTANT: u8 = 2;
    pub const HIT: u8 = 8;
    pub const HALVED: u8 = 16;
    /// The flags step 0 keeps.
    pub const KEPT: u8 = 0xFF - TURNED - INSTANT - HIT;
}

// Felt shifts `2^bit` for the writes (a table, docs/CAIRO.md §3).
const F8: felt252 = 0x100;
const F24: felt252 = 0x1000000;
const F28: felt252 = 0x10000000;
const F32: felt252 = 0x100000000;
const F48: felt252 = 0x1000000000000;
const F52: felt252 = 0x10000000000000;
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
/// `2^108` in the low limb (a goblin's effect skill) and `2^118` in the high limb (its rank).
const P108: u128 = 0x1000000000000000000000000000;
const P118: u128 = 0x400000000000000000000000000000;

/// A member's stored words, in and out of the call: the four that change in play, and the
/// snapshot's `MemberStats`, `MemberBar`, `MemberKit`, read only.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberWords {
    pub state: felt252,
    pub timers: felt252,
    pub effects: felt252,
    pub recharges: felt252,
    pub stats: felt252,
    pub bar: felt252,
    pub kit: felt252,
}

/// A goblin's stored words, in and out of the call, with its entity id and whether it is in the
/// tick's awake set (design/19 §5.2; not stored).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct GoblinWords {
    pub entity: u16,
    pub awake: bool,
    pub state: felt252,
    pub timers: felt252,
}

/// What crosses the library call: the clock, the members (ascending entity id), the goblins the
/// ticks may touch (ascending entity id), the goblins killed in resolution order (`GoblinKilled`)
/// and whether the adventurer was defeated.
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct Words {
    pub clock: u32,
    pub members: Array<MemberWords>,
    pub goblins: Array<GoblinWords>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

/// A member inside the call: its hot fields, what it derives once, and its words (the recharges
/// are read and written in `words.recharges` directly: only at an activation's end).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Member {
    pub status: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u16,
    /// In quarter strikes.
    pub adrenaline: u16,
    pub flags: u8,
    /// The bar slot activated (`NO_SLOT` for none), its target, whether it is a tile, `A`.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_tile: u8,
    pub act_deadline: u32,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub knocked: u32,
    /// Each effect slot's deadline (read only in the ticks) and `REGENERATION` pips.
    pub effect_deadlines: [u32; 4],
    pub effect_regen: [i8; 4],
    pub max_health: u16,
    /// In thirds.
    pub max_energy: u16,
    /// Pips, signed.
    pub health_regen: i8,
    /// Pips: thirds a tick.
    pub energy_regen: u8,
    /// Its adrenaline gains' cap in quarters: the highest adrenaline cost on its bar (design/19
    /// §5.12, FX-12), derived once.
    pub adrenaline_cap: u16,
    pub words: MemberWords,
}

/// A goblin inside the call: its hot fields, what it derives once, and its words (the recharges
/// are read and written in `state` directly).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Goblin {
    pub entity: u16,
    pub awake: bool,
    pub ai: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u8,
    /// In quarter strikes.
    pub adrenaline: u8,
    pub caste: u16,
    /// The activation field (§5.2): a caste skill 0–3 with `A`, `activation::RECOVERING` with
    /// `B`, or `activation::NONE`; its target.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_deadline: u32,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub knocked: u32,
    pub effect_deadline: u32,
    pub effect_regen: i8,
    pub max_health: u16,
    /// Pips, signed.
    pub health_regen: i8,
    /// In thirds.
    pub max_energy: u8,
    pub energy_regen: u8,
    /// Its adrenaline gains' cap in quarters: its caste skills' highest cost, at most the field's
    /// 252 (design/19 §5.12), derived once.
    pub adrenaline_cap: u8,
    pub state: felt252,
    pub timers: felt252,
}

/// A held effect as its word stores it (design/19 §5.7, §7.2): its carrier (a skill id, or with
/// `potion` a belt slot 0–3), its charges (0–63), its deadline (`MAX_CLOCK` for a charge-only
/// effect) and the source's rank at application (0–15).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Held {
    pub carrier: u16,
    pub potion: bool,
    pub charges: u8,
    pub deadline: u32,
    pub rank: u8,
}

/// What the ticks run over, inside the call.
#[derive(Drop, Debug, PartialEq)]
pub struct World {
    pub clock: u32,
    pub members: Array<Member>,
    pub goblins: Array<Goblin>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

/// An actor of the world, by its index in `World.members` or `World.goblins`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Actor {
    Member: u32,
    Goblin: u32,
}

/// The fields of a `SKILL` a tick reads: kind, activation, recharge, and its `REGENERATION`
/// entry's line (0, 0 without one).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct SkillSheet {
    pub id: u16,
    pub kind: u8,
    /// Its adrenaline cost, in strikes (the caps of §5.12).
    pub adrenaline: u8,
    pub activation: u16,
    pub recharge: u16,
    pub regen0: i16,
    pub regen12: i16,
}

/// The field of a potion (`ITEM`) a tick reads: its `REGENERATION` pips (potions do not scale).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct PotionSheet {
    pub id: u32,
    pub regen: i16,
}

/// The fields of a `CASTE` a tick reads (design/19 §7.3).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct CasteSheet {
    pub id: u16,
    /// Health multiplier, percent.
    pub health: u16,
    /// Pips + 10.
    pub health_regen: u8,
    pub energy: u8,
    pub energy_regen: u8,
    /// Its weapon's tick cost `k` (FX-15).
    pub weapon_ticks: u8,
    pub skills: [u16; 4],
}

/// The content of a batch, read once (D-145): the skills of the bars, of the goblins' castes and
/// of held effects; the belt's potions; the goblins' castes.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Content {
    pub skills: Span<SkillSheet>,
    pub potions: Span<PotionSheet>,
    pub castes: Span<CasteSheet>,
}

pub mod errors {
    pub const NO_SKILL: felt252 = 'tick: skill not in content';
    pub const NO_CASTE: felt252 = 'tick: caste not in content';
    pub const NO_POTION: felt252 = 'tick: potion not in content';
    pub const REGEN: felt252 = 'tick: regeneration above i8';
}

/// `(new − old) × shift`: the delta that rewrites a field in place, its neighbours untouched.
#[inline(always)]
fn delta(old: u128, new: u128, shift: felt252) -> felt252 {
    (new.into() - old.into()) * shift
}


/// The `(limb is high, shift)` of a member's recharge slot 0–7 and its felt shift.
#[inline(always)]
fn member_recharge_at(slot: u8) -> (bool, u128, felt252) {
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

#[generate_trait]
pub impl MemberImpl of MemberTrait {
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
            + delta(status.into(), (*self.status).into(), F56)
            + delta(health.into(), (*self.health).into(), F64)
            + delta(energy.into(), (*self.energy).into(), F80)
            + delta(adrenaline.into(), (*self.adrenaline).into(), F96)
            + delta(flags.into(), (*self.flags).into(), F160);
        let timers = words.timers
            + delta(act_slot.into(), (*self.act_slot).into(), 1)
            + delta(act_target.into(), (*self.act_target).into(), F8)
            + delta(act_tile.into(), (*self.act_tile).into(), F24)
            + delta(act_deadline.into(), (*self.act_deadline).into(), F32)
            + delta(bleeding.into(), (*self.bleeding).into(), F64)
            + delta(poison.into(), (*self.poison).into(), F96)
            + delta(burning.into(), (*self.burning).into(), F128)
            + delta(knocked.into(), (*self.knocked).into(), F192);
        MemberWords { state, timers, ..words }
    }

    /// The recharge deadline of bar slot 0–7.
    fn recharge(self: @Member, slot: u8) -> u32 {
        let (low, high) = split(*self.words.recharges);
        let (upper, shift, _) = member_recharge_at(slot);
        let limb = if upper {
            high
        } else {
            low
        };
        field(limb, shift, P28).try_into().unwrap()
    }

    fn set_recharge(ref self: Member, slot: u8, deadline: u32) {
        let (_, _, shift) = member_recharge_at(slot);
        let old = self.recharge(slot);
        self.words.recharges += delta(old.into(), deadline.into(), shift);
    }

    /// The skill id of bar slot 0–7 (`MemberBar`).
    #[inline(always)]
    fn skill(self: @Member, slot: u8) -> u16 {
        let (low, _) = split(*self.words.bar);
        let shift = *[1, P16, P32, 0x1000000000000, P64, P80, P96, P112].span()[slot.into()];
        field(low, shift, P16).try_into().unwrap()
    }
}


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
            + delta(ai.into(), (*self.ai).into(), F24)
            + delta(health.into(), (*self.health).into(), F32)
            + delta(energy.into(), (*self.energy).into(), F48)
            + delta(adrenaline.into(), (*self.adrenaline).into(), F56);
        let timers = *self.timers
            + delta(act_slot.into(), (*self.act_slot).into(), 1)
            + delta(act_target.into(), (*self.act_target).into(), F8)
            + delta(act_deadline.into(), (*self.act_deadline).into(), F24)
            + delta(bleeding.into(), (*self.bleeding).into(), F52)
            + delta(poison.into(), (*self.poison).into(), F80)
            + delta(burning.into(), (*self.burning).into(), F128)
            + delta(knocked.into(), (*self.knocked).into(), F184)
            + delta(effect_deadline.into(), (*self.effect_deadline).into(), F212);
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
        self.state += delta(old.into(), deadline.into(), shift);
    }
}

#[generate_trait]
pub impl WordsImpl of WordsTrait {
    /// The world of the call: every actor loaded once (D-145).
    fn load(self: Words, content: @Content) -> World {
        let mut members = array![];
        for words in self.members {
            members.append(MemberTrait::load(words, content));
        }
        let mut goblins = array![];
        for words in self.goblins {
            goblins.append(GoblinTrait::load(words, content));
        }
        World { clock: self.clock, members, goblins, killed: self.killed, defeated: self.defeated }
    }
}

#[generate_trait]
pub impl WorldStoreImpl of WorldStoreTrait {
    /// The words of the world, every actor's hot fields written back.
    fn store(self: World) -> Words {
        let mut members = array![];
        for member in self.members.span() {
            members.append(member.store());
        }
        let mut goblins = array![];
        for goblin in self.goblins.span() {
            goblins.append(goblin.store());
        }
        Words { clock: self.clock, members, goblins, killed: self.killed, defeated: self.defeated }
    }
}

#[generate_trait]
pub impl SkillSheetImpl of SkillSheetTrait {
    /// The sheet of skill `id`: its holding entry is its one `REGENERATION` if any (§5.14: at most
    /// one holding entry per carrier).
    fn new(id: u16, skill: @Skill) -> SkillSheet {
        let mut regen0 = 0;
        let mut regen12 = 0;
        for entry in skill.entries.span() {
            if *entry.kind == kind::REGENERATION {
                regen0 = *entry.v0;
                regen12 = *entry.v12;
            }
        }
        SkillSheet {
            id,
            kind: *skill.kind,
            adrenaline: *skill.adrenaline,
            activation: *skill.activation,
            recharge: *skill.recharge,
            regen0,
            regen12,
        }
    }

    /// The sheet of skill `id` read from its record's 2 parts (`models::skill` layout): only the
    /// header's kind, activation and recharge, and the entries' kinds until the `REGENERATION`
    /// one or an empty entry. `new` on the unpacked record is its oracle.
    fn read(id: u16, parts: Span<felt252>) -> SkillSheet {
        let (header, first) = split(*parts[0]);
        let (second, third) = split(*parts[1]);
        let mut regen0 = 0;
        let mut regen12 = 0;
        for entry in array![first, second, third] {
            let entry_kind = low_field(entry, P8.try_into().unwrap());
            if entry_kind == kind::EMPTY.into() {
                break;
            }
            if entry_kind == kind::REGENERATION.into() {
                regen0 = SignedTrait::from16(field(entry, P16, P16));
                regen12 = SignedTrait::from16(field(entry, P32, P16));
                break;
            }
        }
        SkillSheet {
            id,
            kind: field(header, P16, P8).try_into().unwrap(),
            adrenaline: field(header, P32, P8).try_into().unwrap(),
            activation: field(header, P40, P16).try_into().unwrap(),
            recharge: field(header, P56, P16).try_into().unwrap(),
            regen0,
            regen12,
        }
    }

    /// Its `REGENERATION` pips at `rank` (§2.2).
    #[inline(always)]
    fn regen(self: @SkillSheet, rank: u8) -> i32 {
        EntryTrait::line(*self.regen0, *self.regen12, rank)
    }
}

#[generate_trait]
pub impl PotionSheetImpl of PotionSheetTrait {
    fn new(id: u32, item: @Item) -> PotionSheet {
        let regen = if *item.entry.kind == kind::REGENERATION {
            *item.entry.v0
        } else {
            0
        };
        PotionSheet { id, regen }
    }

    /// The sheet of potion `id` read from its record's part (`models::item` layout: the entry in
    /// the high limb); `new` on the unpacked record is its oracle.
    fn read(id: u32, parts: Span<felt252>) -> PotionSheet {
        let (_, entry) = split(*parts[0]);
        let regen = if low_field(entry, P8.try_into().unwrap()) == kind::REGENERATION.into() {
            SignedTrait::from16(field(entry, P16, P16))
        } else {
            0
        };
        PotionSheet { id, regen }
    }
}

#[generate_trait]
pub impl CasteSheetImpl of CasteSheetTrait {
    fn new(id: u16, caste: @Caste) -> CasteSheet {
        CasteSheet {
            id,
            health: *caste.health,
            health_regen: *caste.health_regen,
            energy: *caste.energy,
            energy_regen: *caste.energy_regen,
            weapon_ticks: *caste.weapon.ticks,
            skills: *caste.skills,
        }
    }

    /// The sheet of caste `id` read from its record's 2 parts (`models::caste` layout: the
    /// weapon's ticks at bit 72); `new` on the unpacked record is its oracle.
    fn read(id: u16, parts: Span<felt252>) -> CasteSheet {
        let (low, _) = split(*parts[0]);
        let (skills, _) = split(*parts[1]);
        CasteSheet {
            id,
            health: field(low, P16, P16).try_into().unwrap(),
            health_regen: field(low, P32, P8).try_into().unwrap(),
            energy: field(low, P80, P8).try_into().unwrap(),
            energy_regen: field(low, P88, P8).try_into().unwrap(),
            weapon_ticks: field(low, P72, 0x10).try_into().unwrap(),
            skills: [
                low_field(skills, P16.try_into().unwrap()).try_into().unwrap(),
                field(skills, P16, P16).try_into().unwrap(),
                field(skills, P32, P16).try_into().unwrap(),
                field(skills, 0x1000000000000, P16).try_into().unwrap(),
            ],
        }
    }

    /// A goblin's max health at `level`: the adventurer's formula (design/03, `100 + 20 × (level
    /// − 1)`) times the caste's multiplier in percent (design/05, design/19 §7.3), truncated.
    #[inline(always)]
    fn max_health(self: @CasteSheet, level: u8) -> u32 {
        let base: u32 = 80 + 20 * level.into();
        base * (*self.health).into() / 100
    }
}

#[generate_trait]
pub impl ContentImpl of ContentTrait {
    /// The sheet of skill `id`. The content holds every skill the batch can need (design/19 §7.2,
    /// the registry reads), so a missing one is the caller's error.
    fn skill(self: @Content, id: u16) -> @SkillSheet {
        for sheet in *self.skills {
            if *sheet.id == id {
                return sheet;
            }
        }
        core::panic_with_felt252(errors::NO_SKILL)
    }

    fn potion(self: @Content, id: u32) -> @PotionSheet {
        for sheet in *self.potions {
            if *sheet.id == id {
                return sheet;
            }
        }
        core::panic_with_felt252(errors::NO_POTION)
    }

    fn caste(self: @Content, id: u16) -> @CasteSheet {
        for sheet in *self.castes {
            if *sheet.id == id {
                return sheet;
            }
        }
        core::panic_with_felt252(errors::NO_CASTE)
    }
}

// Felt shifts of the cold fields the lifecycle rules write in the words.
const F108: felt252 = 0x1000000000000000000000000000;
const F112: felt252 = 0x10000000000000000000000000000;
const F240: felt252 = 0x1000000000000000000000000000000000000000000000000000000000000;
const F246: felt252 = 0x40000000000000000000000000000000000000000000000000000000000000;

/// The `(limb is high, shift, felt shift)` of a member's effect slot 0–3 (bits 0, 56, 128, 184).
/// A free function: a table.
#[inline(always)]
fn member_effect_at(slot: u8) -> (bool, u128, felt252) {
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

#[inline(always)]
fn tag(potion: bool) -> u128 {
    if potion {
        1
    } else {
        0
    }
}

/// The fields of a member's words that are not hot: written only by the lifecycle rules
/// (`tick::MemberTickTrait`), in the words directly, as the recharges are.
#[generate_trait]
pub impl MemberWordsImpl of MemberWordsTrait {
    /// Crippled's deadline (`MemberTimers` bits 160–191).
    fn crippled(self: @Member) -> u32 {
        let (_, high) = split(*self.words.timers);
        field(high, P32, P32).try_into().unwrap()
    }

    fn set_crippled(ref self: Member, deadline: u32) {
        let old = self.crippled();
        self.words.timers += delta(old.into(), deadline.into(), F160);
    }

    /// The `hits` counter (`MemberState` bits 112–119, design/19 §5.12).
    fn hits(self: @Member) -> u8 {
        let (low, _) = split(*self.words.state);
        field(low, P112, P8).try_into().unwrap()
    }

    fn set_hits(ref self: Member, hits: u8) {
        let old = self.hits();
        self.words.state += delta(old.into(), hits.into(), F112);
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
        let (upper, shift, _) = member_effect_at(slot);
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
        let (_, _, base) = member_effect_at(slot);
        self.words.effects += delta(old.carrier.into(), held.carrier.into(), base)
            + delta(old.charges.into(), held.charges.into(), base * 0x10000)
            + delta(tag(old.potion), tag(held.potion), base * 0x800000)
            + delta(old.deadline.into(), held.deadline.into(), base * 0x1000000)
            + delta(old.rank.into(), held.rank.into(), base * 0x10000000000000);
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
        self.timers += delta(old.into(), deadline.into(), F156);
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
        self.timers += delta(old.carrier.into(), held.carrier.into(), F108)
            + delta(old.charges.into(), held.charges.into(), F240)
            + delta(old.rank.into(), held.rank.into(), F246);
        self.effect_deadline = held.deadline;
        self.effect_regen = pips;
    }
}
