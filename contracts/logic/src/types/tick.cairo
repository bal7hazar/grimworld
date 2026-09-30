//! The value types and constants of a world tick (CBT-02; design/19 §5, §7.2): a held effect as
//! its word stores it, the content's sheets, the encodings ENG-01 froze. The actors' words and
//! their in-call view are models (`models::member`, `models::goblin`); the world and the pipeline
//! are `types::world`.
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
use crate::packing::{N16, N32, N4, N8, limbs, peel};
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
        let (header, first) = limbs(*parts[0]);
        let (second, third) = limbs(*parts[1]);
        let mut regen0 = 0;
        let mut regen12 = 0;
        for entry in array![first, second, third] {
            let mut rest = entry;
            let entry_kind = peel(ref rest, N8);
            if entry_kind == kind::EMPTY.into() {
                break;
            }
            if entry_kind == kind::REGENERATION.into() {
                // Bits 8–15, then `v0` and `v12`.
                let _ = peel(ref rest, N8);
                regen0 = SignedTrait::from16(peel(ref rest, N16));
                regen12 = SignedTrait::from16(peel(ref rest, N16));
                break;
            }
        }
        // The header: profession and attribute 0–15, kind, energy, adrenaline, activation,
        // recharge.
        let (mut rest, _) = DivRem::div_rem(header, N16);
        let kind = peel(ref rest, N8);
        let _energy = peel(ref rest, N8);
        let adrenaline = peel(ref rest, N8);
        let activation = peel(ref rest, N16);
        let recharge = peel(ref rest, N16);
        SkillSheet {
            id,
            kind: kind.try_into().unwrap(),
            adrenaline: adrenaline.try_into().unwrap(),
            activation: activation.try_into().unwrap(),
            recharge: recharge.try_into().unwrap(),
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
        let (_, entry) = limbs(*parts[0]);
        let mut rest = entry;
        let regen = if peel(ref rest, N8) == kind::REGENERATION.into() {
            let _ = peel(ref rest, N8);
            SignedTrait::from16(peel(ref rest, N16))
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
        let (low, _) = limbs(*parts[0]);
        let (skills, _) = limbs(*parts[1]);
        // Tier and AI profile 0–15, the health multiplier, its regeneration; the armor and the
        // weapon's class, damage and type 40–71; its ticks, its range; energy and its
        // regeneration.
        let (mut rest, _) = DivRem::div_rem(low, N16);
        let health = peel(ref rest, N16);
        let health_regen = peel(ref rest, N8);
        let _ = peel(ref rest, N32);
        let weapon_ticks = peel(ref rest, N4);
        let _range = peel(ref rest, N4);
        let energy = peel(ref rest, N8);
        let energy_regen = peel(ref rest, N8);
        let mut rest = skills;
        let first = peel(ref rest, N16);
        let second = peel(ref rest, N16);
        let third = peel(ref rest, N16);
        let fourth = peel(ref rest, N16);
        CasteSheet {
            id,
            health: health.try_into().unwrap(),
            health_regen: health_regen.try_into().unwrap(),
            energy: energy.try_into().unwrap(),
            energy_regen: energy_regen.try_into().unwrap(),
            weapon_ticks: weapon_ticks.try_into().unwrap(),
            skills: [
                first.try_into().unwrap(), second.try_into().unwrap(), third.try_into().unwrap(),
                fourth.try_into().unwrap(),
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
