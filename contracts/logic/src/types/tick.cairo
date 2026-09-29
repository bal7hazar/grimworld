//! The state a world tick reads and writes, and the content it reads, as value types (CBT-02;
//! design/19 §5, §7.2). The stored words are the ephemeral package's (`MemberState`,
//! `MemberTimers`, `MemberEffects`, `Recharges`, `GoblinState`, `GoblinTimers`): the caller
//! (`play`, ENG-07) reads them once, converts them into these, runs the ticks in one library call
//! and writes back what changed. Only the fields the pipeline reads or writes are here; a field it
//! does not know is left as stored. The constants below mirror ENG-01's frozen encodings, and the
//! ephemeral package's tests pin them against its own (`test_tick_constants`).
//!
//! The content a tick needs is read **once per batch** and kept in memory (D-145): the sheets below
//! are the few fields of a `SKILL`, an `ITEM` and a `CASTE` the pipeline reads, extracted once per
//! batch from the records the caller read.

use crate::models::caste::Caste;
use crate::models::index::{Item, Skill};
use crate::types::combat::activation;
use crate::types::effect::{EntryTrait, kind};

/// Adrenaline lost a tick out of combat, in quarter strikes (design/19 §5.8, FX-12): a code
/// constant until BAL-01, **1** by D-157 E.
pub const ADRENALINE_DECAY: u16 = 1;
/// Health pips are clamped to ±10 (design/03, *Pips*); one pip is 2 health a tick.
pub const MAX_PIPS: i32 = 10;
pub const HEALTH_PER_PIP: i32 = 2;
/// Energy is in thirds (design/03: one pip is one energy every 3 ticks).
pub const ENERGY_THIRDS: u16 = 3;
/// Stored regeneration is its pips + 10 (`MemberStats.health_regen`, `Caste.health_regen`).
pub const REGEN_OFFSET: i32 = 10;

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

/// `MemberState.flags` the tick clears at its step 0: what happened "since the last tick" (ENG-01
/// §3.2) and "hit this tick" (design/19 §7.2, §5.10).
pub mod flag {
    pub const TURNED: u8 = 1;
    pub const INSTANT: u8 = 2;
    pub const HIT: u8 = 8;
    pub const HALVED: u8 = 16;
    /// The flags a tick's step 0 keeps: all but `TURNED`, `INSTANT` and `HIT` (`HALVED` is spent
    /// once an instance).
    pub const KEPT: u8 = 0xFF - TURNED - INSTANT - HIT;
}

/// No member activation (`MemberTimers.act_slot`, ENG-01).
pub const NO_SLOT: u8 = 255;

/// The five MVP conditions' deadlines on the instance clock (design/19 §3.2, `MemberTimers`,
/// `GoblinTimers`); 0 is none. A condition is active in tick `T` while `T ≤ D` (§5.1).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Conditions {
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub crippled: u32,
    pub knocked: u32,
}

/// A held effect (design/19 §5.7, §7.2): its carrier (a skill id, or with `potion` a belt slot
/// 0–3), its charges, its deadline (`MAX_CLOCK` for a charge-only effect) and the source's rank at
/// application. `carrier` 0 is none.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Held {
    pub carrier: u16,
    pub potion: bool,
    pub charges: u8,
    pub deadline: u32,
    pub rank: u8,
}

/// A member as a tick reads and writes it (`MemberState`, `MemberTimers`, `MemberEffects`,
/// `Recharges`), with the snapshot fields it reads (`MemberStats`, `MemberBar`, `MemberKit`).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Member {
    /// Its entity id, 0–7 (M-5).
    pub entity: u8,
    pub status: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u16,
    /// In quarter strikes.
    pub adrenaline: u16,
    pub flags: u8,
    /// The bar slot being activated (`NO_SLOT` for none), its target and its deadline `A`.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_deadline: u32,
    pub conditions: Conditions,
    pub effects: [Held; 4],
    /// Each bar slot's recharge deadline `R`.
    pub recharges: [u32; 8],
    // The snapshot, read only.
    pub max_health: u16,
    pub max_energy: u8,
    /// Pips + 10.
    pub health_regen: u8,
    /// Pips.
    pub energy_regen: u8,
    /// The bar's skill ids (`MemberBar.skills`) and the belt's potion item ids (`MemberKit.belt`).
    pub bar: [u16; 8],
    pub belt: [u32; 4],
}

/// A goblin as a tick reads and writes it (`GoblinState`, `GoblinTimers`).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Goblin {
    pub entity: u16,
    /// In the tick's awake set (design/19 §5.2): set at step 0, not stored.
    pub awake: bool,
    pub ai: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u8,
    /// In quarter strikes.
    pub adrenaline: u8,
    pub caste: u16,
    pub level: u8,
    /// The activation field (§5.2): a caste skill 0–3, `activation::RECOVERING` or
    /// `activation::NONE`; its target; its deadline `A` or `B`.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_deadline: u32,
    pub conditions: Conditions,
    pub effect: Held,
    /// Its caste skills' recharge deadlines.
    pub recharges: [u32; 4],
}

/// The fields of a `SKILL` a tick reads: its kind, activation and recharge, and its
/// `REGENERATION` entry's line (0, 0 without one).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct SkillSheet {
    pub id: u16,
    pub kind: u8,
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
/// of held effects; the belt's potions; the castes of the goblins.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Content {
    pub skills: Span<SkillSheet>,
    pub potions: Span<PotionSheet>,
    pub castes: Span<CasteSheet>,
}

/// What a tick runs over: the clock, the members (ascending entity id), the goblins it may touch
/// (ascending entity id; those in the awake set have `awake`), the goblins killed so far in
/// resolution order (`GoblinKilled`), and whether the adventurer was defeated.
#[derive(Drop, Serde, Debug, PartialEq)]
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
            activation: *skill.activation,
            recharge: *skill.recharge,
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

#[generate_trait]
pub impl ConditionsImpl of ConditionsTrait {
    /// The health pips of the degenerating conditions active at tick `t` (§5.8 step 1):
    /// −3 Bleeding, −4 Poison, −7 Burning.
    #[inline(always)]
    fn pips(self: @Conditions, t: u32) -> i32 {
        let mut pips = 0;
        if t <= *self.bleeding {
            pips -= 3;
        }
        if t <= *self.poison {
            pips -= 4;
        }
        if t <= *self.burning {
            pips -= 7;
        }
        pips
    }

    /// Knocked down at tick `t`.
    #[inline(always)]
    fn knocked(self: @Conditions, t: u32) -> bool {
        t <= *self.knocked
    }
}

#[generate_trait]
pub impl GoblinImpl of GoblinTrait {
    /// Alive: neither dead nor looted.
    #[inline(always)]
    fn is_alive(self: @Goblin) -> bool {
        *self.ai < ai::DEAD
    }

    /// Activating: a caste skill in its activation field.
    #[inline(always)]
    fn is_activating(self: @Goblin) -> bool {
        *self.act_slot <= activation::LAST_SLOT
    }
}
