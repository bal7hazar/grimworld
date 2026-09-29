//! The snapshot an instance takes of an adventurer at entry (ADR-0001: the ephemeral domain never
//! reads persistent state during play), and the task ids it will report (D-131). The persistent
//! contract builds them, the ephemeral contract stores them in the member's record; both use these
//! layouts, which is why they live in the shared package. Bit offsets are in
//! docs/architecture/ENG-01-interfaces.md, *Member*.
//!
//! design/19 §7.2 (FX-24, D-155) flattens every passive the rules read into these three words,
//! losslessly, with **0 new slots**: `MemberBar`'s free high limb takes the damage and penetration
//! sums, the quick-cast pairs and the unguarded armor; `MemberKit`'s high limb is repacked;
//! `MemberStats` holds the armor against each damage type where the single armor, the physical and
//! elemental armors and the single penetration were.

use crate::helpers::signed::SignedTrait;
use crate::packing::{
    P104, P108, P112, P120, P12, P16, P20, P24, P32, P40, P48, P56, P64, P72, P8, P80, P84, P88,
    P96, byte_at, field, fits, join, low_field, split, u16_at,
};
use crate::professions::ProfessionTrait;

/// The widest unguarded armor (design/19 §7.2, F-20; F-21 settled by CBT-01): the weighted rating
/// of the five pieces (each `u8`, weights summing to 1: at most 255) and the shield's (`u8`, 255),
/// each raised by personalisation's +10 % of its rating (`RATING_PERCENT`, design/15 D-48: at most
/// ⌊255 × 10 / 100⌋ = 25 each), and at most 37 unguarded `ARMOR` passives of −255…+255: `255 + 25 +
/// 255 + 25 + 37 × 255 = 9,995 < 32,767`. The two 255 limits are the ratings before
/// personalisation. An `i16` holds it.
pub const MAX_UNGUARDED_ARMOR: i16 = 9995;

const P92: u128 = 0x100000000000000000000000;

pub mod errors {
    pub const ARMOR_VS: felt252 = 'snapshot: armor vs above 63';
    pub const ARMOR: felt252 = 'snapshot: armor above bound';
    pub const QUICK_CAST: felt252 = 'snapshot: quick-cast attribute';
    pub const CONDITION: felt252 = 'snapshot: condition';
    pub const PERCENT: felt252 = 'snapshot: percent above 63';
    pub const KNOCKDOWN: felt252 = 'snapshot: knock-down above 3';
}

/// What the build and the equipment give, fixed for the instance (design/03, design/15).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberStats {
    pub max_health: u16,
    pub max_energy: u8,
    /// Energy regeneration, in pips.
    pub energy_regen: u8,
    /// Health regeneration in pips, plus 10 (0 to 20 for −10 to +10 pips).
    pub health_regen: u8,
    /// `ARMOR_VS` per damage type, index `type − 1`, 6 bits each, saturated at 63 (FX-23): types 1–2
    /// at bits 48 and 54, types 3–9 at `200 + 6 (type − 3)`.
    pub armor_vs: [u8; 9],
    pub level: u8,
    pub profession: u8,
    pub primary_rank: u8,
    /// The weapon's class, `types::combat::weapon` (design/19 §7.2).
    pub weapon: u8,
    pub weapon_damage: u8,
    pub weapon_ticks: u8,
    pub weapon_range: u8,
    pub weapon_strength: u8,
    /// The rank of the attribute of each bar skill, 4 bits each (skill `i` at bits `4 i`).
    pub ranks: u32,
    pub damage_type: u8,
    pub requirement_met: u8,
    /// Set bonuses in effect, one bit each.
    pub set_bonuses: u16,
}

pub fn pack_stats(s: MemberStats) -> felt252 {
    let [v1, v2, v3, v4, v5, v6, v7, v8, v9] = s.armor_vs;
    for vs in s.armor_vs.span() {
        fits((*vs).into(), 0x40, errors::ARMOR_VS);
    }
    let low: u128 = s.max_health.into()
        + s.max_energy.into() * P16
        + s.energy_regen.into() * P24
        + s.health_regen.into() * P32
        + v1.into() * P48
        + v2.into() * 0x40000000000000
        + s.level.into() * P64
        + s.profession.into() * P72
        + s.primary_rank.into() * P80
        + s.weapon.into() * P88
        + s.weapon_damage.into() * P96
        + s.weapon_ticks.into() * P104
        + s.weapon_range.into() * P112
        + s.weapon_strength.into() * P120;
    let high: u128 = s.ranks.into()
        + s.damage_type.into() * P32
        + s.requirement_met.into() * P48
        + s.set_bonuses.into() * P56
        + v3.into() * P72
        + v4.into() * 0x40000000000000000000
        + v5.into() * P84
        + v6.into() * 0x40000000000000000000000
        + v7.into() * P96
        + v8.into() * 0x40000000000000000000000000
        + v9.into() * P108;
    join(low, high)
}

pub fn unpack_stats(word: felt252) -> MemberStats {
    let (low, high) = split(word);
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let b32: NonZero<u128> = P32.try_into().unwrap();
    let six = 0x40;
    MemberStats {
        max_health: low_field(low, b16).try_into().unwrap(),
        max_energy: byte_at(low, P16),
        energy_regen: byte_at(low, P24),
        health_regen: byte_at(low, P32),
        armor_vs: [
            field(low, P48, six).try_into().unwrap(),
            field(low, 0x40000000000000, six).try_into().unwrap(),
            field(high, P72, six).try_into().unwrap(),
            field(high, 0x40000000000000000000, six).try_into().unwrap(),
            field(high, P84, six).try_into().unwrap(),
            field(high, 0x40000000000000000000000, six).try_into().unwrap(),
            field(high, P96, six).try_into().unwrap(),
            field(high, 0x40000000000000000000000000, six).try_into().unwrap(),
            field(high, P108, six).try_into().unwrap(),
        ],
        level: byte_at(low, P64),
        profession: byte_at(low, P72),
        primary_rank: byte_at(low, P80),
        weapon: byte_at(low, P88),
        weapon_damage: byte_at(low, P96),
        weapon_ticks: byte_at(low, P104),
        weapon_range: byte_at(low, P112),
        weapon_strength: byte_at(low, P120),
        ranks: low_field(high, b32).try_into().unwrap(),
        damage_type: byte_at(high, P32),
        requirement_met: byte_at(high, P48),
        set_bonuses: u16_at(high, P56),
    }
}

pub impl MemberStatsStorePacking of starknet::storage_access::StorePacking<MemberStats, felt252> {
    fn pack(value: MemberStats) -> felt252 {
        pack_stats(value)
    }
    fn unpack(value: felt252) -> MemberStats {
        unpack_stats(value)
    }
}

/// A quick-cast modifier held (`QUICK_CAST_EVERY_N`, design/19 §4, §5.12): its attribute (4
/// bits) and its N (8 bits; 0 for none). At most two are held, each with its own counter
/// (`MemberState.casts`, `casts_2`; FX-43).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct QuickCast {
    pub attribute: u8,
    pub every: u8,
}

/// The skill bar (8 skill ids, registry `u16`), locked for the expedition (design/03), and, in
/// its high limb, the passives the rules read at each hit or cast (design/19 §7.2, FX-24).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberBar {
    pub skills: [u16; 8],
    /// The slot of the elite skill, 255 for none (bits 128–135).
    pub elite_slot: u8,
    /// `DAMAGE_PERCENT` sums (bits 136–183), index `3 × guard + scope`: guard `ALWAYS` 0 or
    /// `ABOVE_HALF` 1, scope `WEAPON` 0 (a plain weapon hit), `ATTACK_SKILL` 1, `SPELL` 2 (a
    /// passive of scope `ALL` adds to the three). Each −126…+126.
    pub damage: [i8; 6],
    /// `PENETRATION` sums, percent, index the scope as above (bits 184–207). Each ≤ 252, capped
    /// at 100 at use.
    pub penetration: [u8; 3],
    /// Two quick-cast modifiers, 12 bits each (bits 208–231).
    pub quick_cast: [QuickCast; 2],
    /// The unguarded armor, signed (bits 232–247), at most `MAX_UNGUARDED_ARMOR` either way.
    pub armor: i16,
}

fn pack_quick_cast(q: QuickCast) -> u128 {
    fits(q.attribute.into(), 0x10, errors::QUICK_CAST);
    q.attribute.into() + q.every.into() * 0x10
}

fn unpack_quick_cast(bits: u128) -> QuickCast {
    let (every, attribute) = DivRem::div_rem(bits, 0x10);
    QuickCast { attribute: attribute.try_into().unwrap(), every: every.try_into().unwrap() }
}

pub fn pack_bar(b: MemberBar) -> felt252 {
    let [s0, s1, s2, s3, s4, s5, s6, s7] = b.skills;
    let [d0, d1, d2, d3, d4, d5] = b.damage;
    let [p0, p1, p2] = b.penetration;
    let [q0, q1] = b.quick_cast;
    assert(b.armor >= -MAX_UNGUARDED_ARMOR && b.armor <= MAX_UNGUARDED_ARMOR, errors::ARMOR);
    let low: u128 = s0.into()
        + s1.into() * P16
        + s2.into() * P32
        + s3.into() * P48
        + s4.into() * P64
        + s5.into() * P80
        + s6.into() * P96
        + s7.into() * P112;
    let high: u128 = b.elite_slot.into()
        + SignedTrait::bits8(d0) * P8
        + SignedTrait::bits8(d1) * P16
        + SignedTrait::bits8(d2) * P24
        + SignedTrait::bits8(d3) * P32
        + SignedTrait::bits8(d4) * P40
        + SignedTrait::bits8(d5) * P48
        + p0.into() * P56
        + p1.into() * P64
        + p2.into() * P72
        + pack_quick_cast(q0) * P80
        + pack_quick_cast(q1) * P92
        + SignedTrait::bits16(b.armor) * P104;
    join(low, high)
}

pub fn unpack_bar(word: felt252) -> MemberBar {
    let (low, high) = split(word);
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b12: NonZero<u128> = P12.try_into().unwrap();
    let (low, s0) = DivRem::div_rem(low, b16);
    let (low, s1) = DivRem::div_rem(low, b16);
    let (low, s2) = DivRem::div_rem(low, b16);
    let (low, s3) = DivRem::div_rem(low, b16);
    let (low, s4) = DivRem::div_rem(low, b16);
    let (low, s5) = DivRem::div_rem(low, b16);
    let (s7, s6) = DivRem::div_rem(low, b16);
    let (high, elite_slot) = DivRem::div_rem(high, b8);
    let (high, d0) = DivRem::div_rem(high, b8);
    let (high, d1) = DivRem::div_rem(high, b8);
    let (high, d2) = DivRem::div_rem(high, b8);
    let (high, d3) = DivRem::div_rem(high, b8);
    let (high, d4) = DivRem::div_rem(high, b8);
    let (high, d5) = DivRem::div_rem(high, b8);
    let (high, p0) = DivRem::div_rem(high, b8);
    let (high, p1) = DivRem::div_rem(high, b8);
    let (high, p2) = DivRem::div_rem(high, b8);
    let (high, q0) = DivRem::div_rem(high, b12);
    let (high, q1) = DivRem::div_rem(high, b12);
    let armor = low_field(high, b16);
    MemberBar {
        skills: [
            s0.try_into().unwrap(), s1.try_into().unwrap(), s2.try_into().unwrap(),
            s3.try_into().unwrap(), s4.try_into().unwrap(), s5.try_into().unwrap(),
            s6.try_into().unwrap(), s7.try_into().unwrap(),
        ],
        elite_slot: elite_slot.try_into().unwrap(),
        damage: [
            SignedTrait::from8(d0), SignedTrait::from8(d1), SignedTrait::from8(d2),
            SignedTrait::from8(d3), SignedTrait::from8(d4), SignedTrait::from8(d5),
        ],
        penetration: [p0.try_into().unwrap(), p1.try_into().unwrap(), p2.try_into().unwrap()],
        quick_cast: [unpack_quick_cast(q0), unpack_quick_cast(q1)],
        armor: SignedTrait::from16(armor),
    }
}

pub impl MemberBarStorePacking of starknet::storage_access::StorePacking<MemberBar, felt252> {
    fn pack(value: MemberBar) -> felt252 {
        pack_bar(value)
    }
    fn unpack(value: felt252) -> MemberBar {
        unpack_bar(value)
    }
}

/// The belt (4 potion item ids) and the modifiers of the equipment, flattened at entry
/// (design/15: equipment cannot change during an expedition; design/19 §7.2, FX-24). High limb,
/// 75 bits: life steal 128–135 · energy on hit 136–143 · condition 144–147 · its duration percent
/// 148–153 · enchantment duration percent 154–159 · double adrenaline every N hits 160–167 ·
/// health bonus 168–183 · armor in a stance 184–191 · armor enchanted 192–199 (signed) ·
/// knock-down ticks 200–201 · halving 202.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberKit {
    pub belt: [u32; 4],
    /// `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT`.
    pub life_steal: u8,
    pub energy_on_hit: u8,
    /// `CONDITION_DURATION`: its condition (4 bits; 0 none) and percent (6 bits). One prefix, on
    /// the weapon only.
    pub condition: u8,
    pub condition_duration: u8,
    /// `ENCHANT_DURATION` percent (6 bits).
    pub enchantment_duration: u8,
    /// `ADRENALINE_EVERY_N`: the lowest N held (FX-43); 0 none.
    pub double_adrenaline_every: u8,
    /// `MAX_HEALTH` from the equipment.
    pub health_bonus: u16,
    /// The guarded `ARMOR` sums, signed, each −126…+126 (F-20): `IN_STANCE`, `ENCHANTED`.
    pub armor_stance: i8,
    pub armor_enchanted: i8,
    /// `KNOCKDOWN_FLAT`, 0–3 ticks.
    pub knockdown: u8,
    /// `HALVE_FIRST_HEAVY_HIT` held.
    pub halving: bool,
}

pub fn pack_kit(k: MemberKit) -> felt252 {
    fits(k.condition.into(), 0x10, errors::CONDITION);
    fits(k.condition_duration.into(), 0x40, errors::PERCENT);
    fits(k.enchantment_duration.into(), 0x40, errors::PERCENT);
    fits(k.knockdown.into(), 4, errors::KNOCKDOWN);
    let [b0, b1, b2, b3] = k.belt;
    let low: u128 = b0.into() + b1.into() * P32 + b2.into() * P64 + b3.into() * P96;
    let high: u128 = k.life_steal.into()
        + k.energy_on_hit.into() * P8
        + k.condition.into() * P16
        + k.condition_duration.into() * P20
        + k.enchantment_duration.into() * 0x4000000
        + k.double_adrenaline_every.into() * P32
        + k.health_bonus.into() * P40
        + SignedTrait::bits8(k.armor_stance) * P56
        + SignedTrait::bits8(k.armor_enchanted) * P64
        + k.knockdown.into() * P72
        + if k.halving {
            0x4000000000000000000
        } else {
            0
        };
    join(low, high)
}

pub fn unpack_kit(word: felt252) -> MemberKit {
    let (low, high) = split(word);
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b32: NonZero<u128> = P32.try_into().unwrap();
    let (low, b0) = DivRem::div_rem(low, b32);
    let (low, b1) = DivRem::div_rem(low, b32);
    let (b3, b2) = DivRem::div_rem(low, b32);
    let (high, life_steal) = DivRem::div_rem(high, b8);
    let (high, energy_on_hit) = DivRem::div_rem(high, b8);
    let (high, condition) = DivRem::div_rem(high, 0x10);
    let (high, condition_duration) = DivRem::div_rem(high, 0x40);
    let (high, enchantment_duration) = DivRem::div_rem(high, 0x40);
    let (high, double_adrenaline_every) = DivRem::div_rem(high, b8);
    let (high, health_bonus) = DivRem::div_rem(high, P16.try_into().unwrap());
    let (high, armor_stance) = DivRem::div_rem(high, b8);
    let (high, armor_enchanted) = DivRem::div_rem(high, b8);
    let (halving, knockdown) = DivRem::div_rem(high, 4);
    MemberKit {
        belt: [
            b0.try_into().unwrap(), b1.try_into().unwrap(), b2.try_into().unwrap(),
            b3.try_into().unwrap(),
        ],
        life_steal: life_steal.try_into().unwrap(),
        energy_on_hit: energy_on_hit.try_into().unwrap(),
        condition: condition.try_into().unwrap(),
        condition_duration: condition_duration.try_into().unwrap(),
        enchantment_duration: enchantment_duration.try_into().unwrap(),
        double_adrenaline_every: double_adrenaline_every.try_into().unwrap(),
        health_bonus: health_bonus.try_into().unwrap(),
        armor_stance: SignedTrait::from8(armor_stance),
        armor_enchanted: SignedTrait::from8(armor_enchanted),
        knockdown: knockdown.try_into().unwrap(),
        halving: halving != 0,
    }
}

pub impl MemberKitStorePacking of starknet::storage_access::StorePacking<MemberKit, felt252> {
    fn pack(value: MemberKit) -> felt252 {
        pack_kit(value)
    }
    fn unpack(value: felt252) -> MemberKit {
        unpack_kit(value)
    }
}

/// What the persistent contract hands to the ephemeral one at entry (the snapshot).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Snapshot {
    pub stats: MemberStats,
    pub bar: MemberBar,
    pub kit: MemberKit,
    /// Potions carried in each belt slot: debited from the pack in the entry transaction (the
    /// reserve), credited back unused by the closing report (`Results.belt`).
    pub belt_counts: [u8; 4],
}

/// Health at level 1, and what each level above adds (design/03, *Base stats*).
pub const BASE_HEALTH: u16 = 100;
pub const HEALTH_PER_LEVEL: u16 = 20;
/// `MemberStats.health_regen` is the pips plus 10: no regeneration nor degeneration.
pub const NO_HEALTH_REGEN: u8 = 10;

#[generate_trait]
pub impl SnapshotImpl of SnapshotTrait {
    /// The snapshot of an adventurer at entry, from what its models hold today (ENG-06): its
    /// level and primary profession give health, energy, regeneration and armor (design/03); its
    /// bar, elite slot and belt are copied. What equipment, attribute ranks and set bonuses would
    /// add is 0: no entrypoint can yet equip an item or spend a point (`set_build` is a later
    /// lot's), and design/15's formulas are that lot's.
    fn new(
        level: u8,
        profession: u8,
        skills: [u16; 8],
        elite_slot: u8,
        belt: [u32; 4],
        belt_counts: [u8; 4],
    ) -> Snapshot {
        let stats = MemberStats {
            max_health: BASE_HEALTH + HEALTH_PER_LEVEL * (level.into() - 1),
            max_energy: ProfessionTrait::energy(profession),
            energy_regen: ProfessionTrait::energy_regen(profession),
            health_regen: NO_HEALTH_REGEN,
            level,
            profession,
            ..Default::default(),
        };
        // The class's armor is the unguarded armor, in `MemberBar` since FX-24 (design/19 §7.2).
        let armor: u8 = ProfessionTrait::armor(profession);
        Snapshot {
            stats,
            bar: MemberBar {
                skills,
                elite_slot,
                damage: [0; 6],
                penetration: [0; 3],
                quick_cast: [Default::default(); 2],
                armor: armor.into(),
            },
            kit: MemberKit { belt, ..Default::default() },
            belt_counts,
        }
    }
}

/// One task an instance reports (D-131): the quiver task id and what counts toward it, which the
/// instance can check without reading the persistent domain.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct TaskEntry {
    pub task: u32,
    /// `criteria` of docs/architecture/ENG-01-interfaces.md: 1 kill a caste, 2 reach a landmark,
    /// 3 clear a dungeon, 4 reveal a whole zone, 5 loot remains, 6 mine, 7 activate objects.
    pub kind: u8,
    /// The registry id the kind counts (a caste, a landmark, a location).
    pub param: u16,
}

/// Four tasks per stored page: at bits 0 and 56 (low limb), 128 and 184 (high limb).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct TaskPage {
    pub entries: [TaskEntry; 4],
}

fn pack_task(t: TaskEntry) -> u128 {
    t.task.into() + t.kind.into() * P32 + t.param.into() * P40
}

fn unpack_task(bits: u128) -> TaskEntry {
    let (rest, task) = DivRem::div_rem(bits, P32.try_into().unwrap());
    let (param, kind) = DivRem::div_rem(rest, P8.try_into().unwrap());
    TaskEntry {
        task: task.try_into().unwrap(),
        kind: kind.try_into().unwrap(),
        param: param.try_into().unwrap(),
    }
}

pub fn pack_task_page(p: TaskPage) -> felt252 {
    let [a, b, c, d] = p.entries;
    join(pack_task(a) + pack_task(b) * P56, pack_task(c) + pack_task(d) * P56)
}

pub fn unpack_task_page(word: felt252) -> TaskPage {
    let (low, high) = split(word);
    let s56: NonZero<u128> = P56.try_into().unwrap();
    let (b, a) = DivRem::div_rem(low, s56);
    let (d, c) = DivRem::div_rem(high, s56);
    TaskPage { entries: [unpack_task(a), unpack_task(b), unpack_task(c), unpack_task(d)] }
}

pub impl TaskPageStorePacking of starknet::storage_access::StorePacking<TaskPage, felt252> {
    fn pack(value: TaskPage) -> felt252 {
        pack_task_page(value)
    }
    fn unpack(value: felt252) -> TaskPage {
        unpack_task_page(value)
    }
}
