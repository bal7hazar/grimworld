//! A goblin that left its first state: two felts under `(slot, entity)` (M-1, M-5). A goblin
//! still asleep or on watch at its spawn has no record: it is derived from its chunk's pack
//! placement (ENG-01, *Goblins*). Layouts: docs/architecture/ENG-01-interfaces.md, *Goblin*.

use grimworld_logic::packing::{
    P104, P108, P112, P120, P16, P24, P28, P32, P48, P52, P56, P64, P8, P80, P88, byte_at, field,
    fits, join, low_field, split, u16_at,
};
use grimworld_logic::types::combat::activation;
use crate::models::member::DeadlinesTrait;

/// Bit 118 of the high limb (bit 246 of the word): the effect's rank.
const P118: u128 = 0x400000000000000000000000000000;

/// AI states (design/04), `GoblinState.ai`.
pub const ASLEEP: u8 = 0;
pub const WATCH: u8 = 1;
pub const ALERTED: u8 = 2;
pub const ENGAGED: u8 = 3;
pub const FLEEING: u8 = 4;
pub const RETURNING: u8 = 5;
/// Dead: its record is its remains (design/07, D-50).
pub const DEAD: u8 = 6;
/// Dead, and its remains looted.
pub const LOOTED: u8 = 7;

pub mod errors {
    /// Its effect's charges above 63, or rank above 15 (design/19 §7.2).
    pub const CHARGES: felt252 = 'packing: charges above 63';
    pub const RANK: felt252 = 'packing: rank above 15';
}

/// A goblin's adrenaline field holds at most 63 strikes, in quarters (design/19 §5.12).
pub const MAX_ADRENALINE: u8 = 252;

/// What changes when it acts.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct GoblinState {
    /// bits 0-7, 8-15: global tile (its remains' tile once dead)
    pub x: u8,
    pub y: u8,
    /// bits 16-23
    pub facing: u8,
    /// bits 24-31: `ASLEEP` … `LOOTED`
    pub ai: u8,
    /// bits 32-47
    pub health: u16,
    /// bits 48-55: in thirds of energy (a caste's energy is at most 85); bits 56-63: in quarters
    /// of a strike, at most `MAX_ADRENALINE` (design/19 §7.2, §5.12)
    pub energy: u8,
    pub adrenaline: u8,
    /// bits 64-79: its caste (registry), bits 80-87: its level; copied from the pack so that a
    /// tick needs no registry read to know them
    pub caste: u16,
    pub level: u8,
    /// bits 88-103: the entity it targets (M-3: chosen among a list of adventurers)
    pub target: u16,
    /// bits 104-111, 112-119: the last tile its target was seen at
    pub memory_x: u8,
    pub memory_y: u8,
    /// bits 120-127: reserved flags
    pub flags: u8,
    /// bits 128-239: recharge deadlines of its caste's four skills, 28 bits each
    pub recharges: [u32; 4],
}

pub impl GoblinStateStorePacking of starknet::storage_access::StorePacking<GoblinState, felt252> {
    fn pack(value: GoblinState) -> felt252 {
        let [r0, r1, r2, r3] = value.recharges;
        let low: u128 = value.x.into()
            + value.y.into() * P8
            + value.facing.into() * P16
            + value.ai.into() * P24
            + value.health.into() * P32
            + value.energy.into() * P48
            + value.adrenaline.into() * P56
            + value.caste.into() * P64
            + value.level.into() * P80
            + value.target.into() * P88
            + value.memory_x.into() * P104
            + value.memory_y.into() * P112
            + value.flags.into() * P120;
        join(low, DeadlinesTrait::pack(r0, r1, r2, r3))
    }
    fn unpack(value: felt252) -> GoblinState {
        let (low, high) = split(value);
        let (r0, r1, r2, r3) = DeadlinesTrait::unpack(high);
        GoblinState {
            x: low_field(low, P8.try_into().unwrap()).try_into().unwrap(),
            y: byte_at(low, P8),
            facing: byte_at(low, P16),
            ai: byte_at(low, P24),
            health: u16_at(low, P32),
            energy: byte_at(low, P48),
            adrenaline: byte_at(low, P56),
            caste: u16_at(low, P64),
            level: byte_at(low, P80),
            target: u16_at(low, P88),
            memory_x: byte_at(low, P104),
            memory_y: byte_at(low, P112),
            flags: byte_at(low, P120),
            recharges: [r0, r1, r2, r3],
        }
    }
}

/// Activation, conditions and one effect, as 28-bit deadlines (0 is none).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct GoblinTimers {
    /// bits 0-7: the activation field (design/19 §5.2): the caste skill being activated (0-3),
    /// `activation::RECOVERING` (254) or `activation::NONE` (255)
    pub act_slot: u8,
    /// bits 8-23: its target entity or tile
    pub act_target: u16,
    /// bits 24-51: the activation's deadline `A`, or the recovery's `B`
    pub act_deadline: u32,
    /// bits 52-79, 80-107
    pub bleeding: u32,
    pub poison: u32,
    /// bits 108-123: the skill of its one effect (a shaman's enchantment, a hex), 0 for none
    pub effect_skill: u16,
    /// bits 128-155, 156-183, 184-211
    pub burning: u32,
    pub crippled: u32,
    pub knocked: u32,
    /// bits 212-239
    pub effect_deadline: u32,
    /// bits 240-245: its effect's charges, 0-63; bits 246-249: the source's rank at application,
    /// 0-15 (design/19 §7.2)
    pub effect_charges: u8,
    pub effect_rank: u8,
}

pub impl GoblinTimersStorePacking of starknet::storage_access::StorePacking<GoblinTimers, felt252> {
    fn pack(value: GoblinTimers) -> felt252 {
        fits(value.act_deadline.into(), P28, 'packing: deadline above 2^28');
        fits(value.bleeding.into(), P28, 'packing: deadline above 2^28');
        fits(value.poison.into(), P28, 'packing: deadline above 2^28');
        let low: u128 = value.act_slot.into()
            + value.act_target.into() * P8
            + value.act_deadline.into() * P24
            + value.bleeding.into() * P52
            + value.poison.into() * P80
            + value.effect_skill.into() * P108;
        value.assert_valid();
        let high = DeadlinesTrait::pack(
            value.burning, value.crippled, value.knocked, value.effect_deadline,
        )
            + value.effect_charges.into() * P112
            + value.effect_rank.into() * P118;
        join(low, high)
    }
    fn unpack(value: felt252) -> GoblinTimers {
        let (low, high) = split(value);
        let (effect, timers) = DivRem::div_rem(high, P112.try_into().unwrap());
        let (burning, crippled, knocked, effect_deadline) = DeadlinesTrait::unpack(timers);
        let (effect_rank, effect_charges) = DivRem::div_rem(effect, 0x40);
        GoblinTimers {
            act_slot: low_field(low, P8.try_into().unwrap()).try_into().unwrap(),
            act_target: u16_at(low, P8),
            act_deadline: field(low, P24, P28).try_into().unwrap(),
            bleeding: field(low, P52, P28).try_into().unwrap(),
            poison: field(low, P80, P28).try_into().unwrap(),
            effect_skill: u16_at(low, P108),
            burning,
            crippled,
            knocked,
            effect_deadline,
            effect_charges: effect_charges.try_into().unwrap(),
            effect_rank: effect_rank.try_into().unwrap(),
        }
    }
}

#[generate_trait]
pub impl GoblinTimersAssert of GoblinTimersAssertTrait {
    /// The effect's charges fit 6 bits, its rank 4 (design/19 §7.2).
    #[inline(always)]
    fn assert_valid(self: @GoblinTimers) {
        assert(*self.effect_charges < 0x40, errors::CHARGES);
        assert(*self.effect_rank < 0x10, errors::RANK);
    }
}

/// The two consecutive slots of a goblin record.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Goblin {
    pub state: GoblinState,
    pub timers: GoblinTimers,
}

/// The timers of a goblin's first record (fix loop 3, F-14): no activation (`act_slot` 255, target
/// 0, deadline 0), no condition, no effect. Stored, it is `LIVE + 255`.
#[generate_trait]
pub impl GoblinTimersImpl of GoblinTimersTrait {
    fn empty() -> GoblinTimers {
        GoblinTimers { act_slot: activation::NONE, ..Default::default() }
    }
}
