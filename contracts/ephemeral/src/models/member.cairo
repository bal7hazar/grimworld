//! An adventurer inside an instance: eight felts under `(slot, member)` (M-1, M-3). The first four
//! change during play; the last four are the snapshot taken at entry (ADR-0001) and the account
//! that controls the adventurer (M-6). Layouts: docs/architecture/ENG-01-interfaces.md, *Member*.

use grimworld_logic::packing::{
    P112, P120, P16, P24, P28, P32, P40, P52, P56, P64, P8, P80, P84, P96, byte_at, field, fits,
    join, low_field, split, u16_at, u32_at,
};
use grimworld_logic::snapshot::{MemberBar, MemberKit, MemberStats};
use grimworld_logic::types::MAX_CLOCK;
use starknet::ContractAddress;
use crate::helpers::stored::Stored;

/// Member status (`MemberState.status`).
pub const INSIDE: u8 = 0;
pub const DOWN: u8 = 1;
pub const GONE: u8 = 2;
/// Energy is stored in thirds (design/03, *Pips*).
pub const ENERGY_THIRDS: u16 = 3;

pub mod errors {
    /// A gate action by anyone but the member's controller (M-6, ENG-01 §1.2).
    pub const NOT_CONTROLLER: felt252 = 'not controller';
    /// A held effect's charges above 63, rank above 15, or belt slot above 3 (design/19 §7.2).
    pub const CHARGES: felt252 = 'packing: charges above 63';
    pub const RANK: felt252 = 'packing: rank above 15';
    pub const BELT_SLOT: felt252 = 'packing: belt slot above 3';
}

#[generate_trait]
pub impl MemberAssert of MemberAssertTrait {
    /// A gate action's caller is the member's controller (M-6, ENG-01 §1.2): a revert, not a
    /// refusal of the game.
    #[inline(always)]
    fn assert_controller(controller: ContractAddress, caller: ContractAddress) {
        assert(controller == caller, errors::NOT_CONTROLLER);
    }
}

#[generate_trait]
pub impl MemberStateImpl of MemberStateTrait {
    /// The member at clock 0 of a new generation (ENG-01 §2.1, F-12): on the entrance tile,
    /// health and energy at their maxima from the snapshot, no adrenaline, inside, the counters and
    /// flags 0; the belt's counts are the reserve's, the only thing that carries (D-141, E-20).
    /// Facing: 0 until ENG-05 knows the entrance's side (design/18: "away from the entrance").
    fn entering(
        adventurer: u32, x: u8, y: u8, max_health: u16, max_energy: u8, belt: [u8; 4],
    ) -> MemberState {
        MemberState {
            adventurer,
            x,
            y,
            facing: 0,
            status: INSIDE,
            health: max_health,
            energy: max_energy.into() * ENERGY_THIRDS,
            adrenaline: 0,
            hits: 0,
            casts: 0,
            belt,
            flags: 0,
            casts_2: 0,
        }
    }

    /// `(max health, max energy)` of a stored `MemberStats` word (bits 0-15, 16-23), without
    /// unpacking the other eighteen fields.
    fn maxima(stats: felt252) -> (u16, u8) {
        let (low, _) = split(stats);
        (low_field(low, P16.try_into().unwrap()).try_into().unwrap(), byte_at(low, P16))
    }
}

/// The stored words of a member's timers, effects and recharges entering a new generation (ENG-01
/// §2.1, F-12, F-14), written as they are stored: `empty_member_timers` packed (no activation, no
/// condition: `LIVE + 255`), and no effect or recharge (`LIVE`). Pinned against the packers by
/// `test_empty_words`.
pub const EMPTY_TIMERS: felt252 = 0x4000000000000000000000000000000000000000000000000000000000000ff;
pub const EMPTY_EFFECTS: felt252 =
    0x400000000000000000000000000000000000000000000000000000000000000;
pub const EMPTY_RECHARGES: felt252 =
    0x400000000000000000000000000000000000000000000000000000000000000;

/// What changes at every tick.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberState {
    /// bits 0-31
    pub adventurer: u32,
    /// bits 32-39, 40-47: global tile
    pub x: u8,
    pub y: u8,
    /// bits 48-55: 0 to 5
    pub facing: u8,
    /// bits 56-63: `INSIDE`, `DOWN` (defeated), `GONE` (left)
    pub status: u8,
    /// bits 64-79
    pub health: u16,
    /// bits 80-95: in thirds of energy (design/03, pips)
    pub energy: u16,
    /// bits 96-111: in quarters of a strike (design/04)
    pub adrenaline: u16,
    /// bits 112-119: hits landed, for "every Nth hit" modifiers (design/15)
    pub hits: u8,
    /// bits 120-127: spells cast, for the first quick-cast modifier (`MemberBar.quick_cast[0]`)
    pub casts: u8,
    /// bits 128-159: potions left in each belt slot, 8 bits each
    pub belt: [u8; 4],
    /// bits 160-167: `flag::TURNED`, `INSTANT`, `HIT`, `HALVED` (design/19 §7.2)
    pub flags: u8,
    /// bits 168-175: spells cast, for the second quick-cast modifier (design/19 §5.12, FX-43)
    pub casts_2: u8,
}

/// `MemberState.flags` (ENG-01 §3.2; design/19 §7.2 adds bits 3 and 4).
pub mod flag {
    /// Turned since the last tick.
    pub const TURNED: u8 = 1;
    /// An instant skill used since the last tick.
    pub const INSTANT: u8 = 2;
    /// Hit this tick (§5.5 step 5; `mine` stops on it, §5.10).
    pub const HIT: u8 = 8;
    /// `HALVE_FIRST_HEAVY_HIT` spent (FX-19).
    pub const HALVED: u8 = 16;
}

pub impl MemberStateStorePacking of starknet::storage_access::StorePacking<MemberState, felt252> {
    fn pack(value: MemberState) -> felt252 {
        let [b0, b1, b2, b3] = value.belt;
        let low: u128 = value.adventurer.into()
            + value.x.into() * P32
            + value.y.into() * 0x10000000000
            + value.facing.into() * 0x1000000000000
            + value.status.into() * P56
            + value.health.into() * P64
            + value.energy.into() * P80
            + value.adrenaline.into() * P96
            + value.hits.into() * P112
            + value.casts.into() * P120;
        let high: u128 = b0.into()
            + b1.into() * P8
            + b2.into() * P16
            + b3.into() * P24
            + value.flags.into() * P32
            + value.casts_2.into() * P40;
        join(low, high)
    }
    fn unpack(value: felt252) -> MemberState {
        let (low, high) = split(value);
        MemberState {
            adventurer: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            x: byte_at(low, P32),
            y: byte_at(low, 0x10000000000),
            facing: byte_at(low, 0x1000000000000),
            status: byte_at(low, P56),
            health: u16_at(low, P64),
            energy: u16_at(low, P80),
            adrenaline: u16_at(low, P96),
            hits: byte_at(low, P112),
            casts: byte_at(low, P120),
            belt: [
                low_field(high, P8.try_into().unwrap()).try_into().unwrap(), byte_at(high, P8),
                byte_at(high, P16), byte_at(high, P24),
            ],
            flags: byte_at(high, P32),
            casts_2: byte_at(high, P40),
        }
    }
}

/// No activation (`act_slot`).
pub const NO_SLOT: u8 = 255;

/// Activation and conditions, as deadlines on the instance clock (D-02, M-2); 0 is none.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberTimers {
    /// bits 0-7: the bar slot being activated, `NO_SLOT` for none
    pub act_slot: u8,
    /// bits 8-23: its target, an entity id or a tile (M-5)
    pub act_target: u16,
    /// bits 24-31: 1 when the target is a tile
    pub act_tile: u8,
    /// bits 32-63: the tick it resolves at
    pub act_deadline: u32,
    /// bits 64-95, 96-127, 128-159, 160-191, 192-223: the MVP's five conditions (design/09)
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub crippled: u32,
    pub knocked: u32,
}

pub impl MemberTimersStorePacking of starknet::storage_access::StorePacking<MemberTimers, felt252> {
    fn pack(value: MemberTimers) -> felt252 {
        for deadline in array![
            value.act_deadline, value.bleeding, value.poison, value.burning, value.crippled,
            value.knocked,
        ] {
            assert(deadline <= MAX_CLOCK, 'packing: deadline > MAX_CLOCK');
        }
        let low: u128 = value.act_slot.into()
            + value.act_target.into() * P8
            + value.act_tile.into() * P24
            + value.act_deadline.into() * P32
            + value.bleeding.into() * P64
            + value.poison.into() * P96;
        let high: u128 = value.burning.into()
            + value.crippled.into() * P32
            + value.knocked.into() * P64;
        join(low, high)
    }
    fn unpack(value: felt252) -> MemberTimers {
        let (low, high) = split(value);
        MemberTimers {
            act_slot: low_field(low, P8.try_into().unwrap()).try_into().unwrap(),
            act_target: u16_at(low, P8),
            act_tile: byte_at(low, P24),
            act_deadline: u32_at(low, P32),
            bleeding: u32_at(low, P64),
            poison: u32_at(low, P96),
            burning: low_field(high, P32.try_into().unwrap()).try_into().unwrap(),
            crippled: u32_at(high, P32),
            knocked: u32_at(high, P64),
        }
    }
}

/// A held effect on a member: a stance, an enchantment, a preparation, a glyph, a hex, a potion's
/// (design/19 §5.7, §7.2). 56 bits: skill 0-15 · charges 16-21 · (bit 22 free) · potion tag 23
/// ·
/// deadline 24-51 · rank 52-55. Its carrier is the skill id, or with the tag the belt slot 0-3
/// whose potion item is the carrier (FX-42).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Effect {
    /// The skill (registry id) that set it; 0 for none. With `potion`, the belt slot 0-3.
    pub skill: u16,
    /// Charges left, 0-63 (a block's, an oil's).
    pub charges: u8,
    /// The potion tag: `skill` is a belt slot.
    pub potion: bool,
    /// The tick it ends at (`MAX_CLOCK` for a charge-only effect, design/19 §3.4).
    pub deadline: u32,
    /// The source's rank at application, 0-15 (§5.7).
    pub rank: u8,
}

#[generate_trait]
pub impl EffectAssert of EffectAssertTrait {
    /// Charges fit 6 bits, the rank 4; with the potion tag, the skill field is a belt slot 0-3.
    #[inline(always)]
    fn assert_valid(self: @Effect) {
        assert(*self.charges < 0x40, errors::CHARGES);
        assert(*self.rank < 0x10, errors::RANK);
        assert(!*self.potion || *self.skill < 4, errors::BELT_SLOT);
    }
}

/// Up to four effects, 56 bits each, at bits 0, 56, 128, 184.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberEffects {
    pub effects: [Effect; 4],
}

fn pack_effect(e: Effect) -> u128 {
    assert(e.deadline <= MAX_CLOCK, 'packing: deadline > MAX_CLOCK');
    e.assert_valid();
    let tag: u128 = if e.potion {
        0x800000
    } else {
        0
    };
    e.skill.into() + e.charges.into() * P16 + tag + e.deadline.into() * P24 + e.rank.into() * P52
}

fn unpack_effect(bits: u128) -> Effect {
    Effect {
        skill: low_field(bits, P16.try_into().unwrap()).try_into().unwrap(),
        charges: field(bits, P16, 0x40).try_into().unwrap(),
        potion: field(bits, 0x800000, 2) == 1,
        deadline: field(bits, P24, P28).try_into().unwrap(),
        rank: field(bits, P52, 0x10).try_into().unwrap(),
    }
}

pub impl MemberEffectsStorePacking of starknet::storage_access::StorePacking<
    MemberEffects, felt252,
> {
    fn pack(value: MemberEffects) -> felt252 {
        let [a, b, c, d] = value.effects;
        join(pack_effect(a) + pack_effect(b) * P56, pack_effect(c) + pack_effect(d) * P56)
    }
    fn unpack(value: felt252) -> MemberEffects {
        let (low, high) = split(value);
        let s56: NonZero<u128> = P56.try_into().unwrap();
        let (b, a) = DivRem::div_rem(low, s56);
        let (d, c) = DivRem::div_rem(high, s56);
        MemberEffects {
            effects: [unpack_effect(a), unpack_effect(b), unpack_effect(c), unpack_effect(d)],
        }
    }
}

/// The recharge deadline of each bar slot, 28 bits each (the clock never passes `MAX_CLOCK`):
/// slots 0-3 at bits 0, 28, 56, 84; slots 4-7 at bits 128, 156, 184, 212.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Recharges {
    pub deadlines: [u32; 8],
}

/// Four 28-bit deadlines in one limb; a value of 2^28 or more is refused (it would corrupt the
/// next lane).
pub fn pack_four28(a: u32, b: u32, c: u32, d: u32) -> u128 {
    fits(a.into(), P28, 'packing: deadline above 2^28');
    fits(b.into(), P28, 'packing: deadline above 2^28');
    fits(c.into(), P28, 'packing: deadline above 2^28');
    fits(d.into(), P28, 'packing: deadline above 2^28');
    a.into() + b.into() * P28 + c.into() * P56 + d.into() * P84
}

pub fn unpack_four28(bits: u128) -> (u32, u32, u32, u32) {
    let s28: NonZero<u128> = P28.try_into().unwrap();
    let (rest, a) = DivRem::div_rem(bits, s28);
    let (rest, b) = DivRem::div_rem(rest, s28);
    let (rest, c) = DivRem::div_rem(rest, s28);
    let (_, d) = DivRem::div_rem(rest, s28);
    (a.try_into().unwrap(), b.try_into().unwrap(), c.try_into().unwrap(), d.try_into().unwrap())
}

pub impl RechargesStorePacking of starknet::storage_access::StorePacking<Recharges, felt252> {
    fn pack(value: Recharges) -> felt252 {
        let [a, b, c, d, e, f, g, h] = value.deadlines;
        join(pack_four28(a, b, c, d), pack_four28(e, f, g, h))
    }
    fn unpack(value: felt252) -> Recharges {
        let (low, high) = split(value);
        let (a, b, c, d) = unpack_four28(low);
        let (e, f, g, h) = unpack_four28(high);
        Recharges { deadlines: [a, b, c, d, e, f, g, h] }
    }
}

/// The eight consecutive slots of a member (`Store` layout: field `i` at offset `i`), as models:
/// the layout and the packers' oracle. `Instances` declares its storage with `StoredMember`, the
/// same slots typed as stored words.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Member {
    pub state: MemberState,
    pub timers: MemberTimers,
    pub effects: MemberEffects,
    pub recharges: Recharges,
    pub stats: MemberStats,
    pub bar: MemberBar,
    pub kit: MemberKit,
    /// The account allowed to play this member (M-6: "the caller controls this adventurer"),
    /// from the persistent domain at entry, updated by `set_controller`.
    pub controller: ContractAddress,
}

/// A member's eight slots as `Instances` declares them (ENG-R1b): `Member`'s slots in its order, at
/// the same addresses, each the word of its model as stored (`helpers::stored`). The store reads
/// and writes a slot typed and needs no offset: the state and the controller through their models,
/// the other six as words (the view returns all eight as stored, `begin` writes the empty transient
/// words as constants, `create` writes the snapshot's three words as `Hub` stored them, D-168).
/// Pinned against `Member` by the store's `test_member_slots`.
#[derive(Copy, Drop, starknet::Store)]
pub struct StoredMember {
    pub state: Stored<MemberState>,
    pub timers: Stored<MemberTimers>,
    pub effects: Stored<MemberEffects>,
    pub recharges: Stored<Recharges>,
    pub stats: Stored<MemberStats>,
    pub bar: Stored<MemberBar>,
    pub kit: Stored<MemberKit>,
    pub controller: ContractAddress,
}

/// The timers of a member entering a new generation (fix loop 3, F-14): no activation
/// (`act_slot` = `NO_SLOT`, target 0, not a tile, deadline 0) and no condition (every deadline 0).
/// Stored, it is `LIVE + 255`, not `LIVE` alone: `act_slot` 0 would name bar slot 0.
pub fn empty_member_timers() -> MemberTimers {
    MemberTimers { act_slot: NO_SLOT, ..Default::default() }
}
