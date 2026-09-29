//! The snapshot an instance takes of an adventurer at entry (ADR-0001: the ephemeral domain never
//! reads persistent state during play), and the task ids it will report (D-131). The persistent
//! contract builds them, the ephemeral contract stores them in the member's record; both use these
//! layouts, which is why they live in the shared package. Bit offsets are in
//! docs/architecture/ENG-01-interfaces.md, *Member*.

use crate::packing::{
    P104, P112, P120, P16, P24, P32, P40, P48, P56, P64, P72, P8, P80, P88, P96, byte_at, join,
    low_field, split, u16_at,
};

/// What the build and the equipment give, fixed for the instance (design/03, design/15).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberStats {
    pub max_health: u16,
    pub max_energy: u8,
    /// Energy regeneration, in pips.
    pub energy_regen: u8,
    /// Health regeneration in pips, plus 10 (0 to 20 for −10 to +10 pips).
    pub health_regen: u8,
    pub armor: u8,
    pub armor_physical: u8,
    pub armor_elemental: u8,
    pub level: u8,
    pub profession: u8,
    pub primary_rank: u8,
    pub weapon: u8,
    pub weapon_damage: u8,
    pub weapon_ticks: u8,
    pub weapon_range: u8,
    pub weapon_strength: u8,
    /// The rank of the attribute of each bar skill, 4 bits each (skill `i` at bits `4 i`).
    pub ranks: u32,
    pub damage_type: u8,
    pub penetration: u8,
    pub requirement_met: u8,
    /// Set bonuses in effect, one bit each.
    pub set_bonuses: u16,
}

pub fn pack_stats(s: MemberStats) -> felt252 {
    let low: u128 = s.max_health.into()
        + s.max_energy.into() * P16
        + s.energy_regen.into() * P24
        + s.health_regen.into() * P32
        + s.armor.into() * P40
        + s.armor_physical.into() * P48
        + s.armor_elemental.into() * P56
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
        + s.penetration.into() * P40
        + s.requirement_met.into() * P48
        + s.set_bonuses.into() * P56;
    join(low, high)
}

pub fn unpack_stats(word: felt252) -> MemberStats {
    let (low, high) = split(word);
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let b32: NonZero<u128> = P32.try_into().unwrap();
    MemberStats {
        max_health: low_field(low, b16).try_into().unwrap(),
        max_energy: byte_at(low, P16),
        energy_regen: byte_at(low, P24),
        health_regen: byte_at(low, P32),
        armor: byte_at(low, P40),
        armor_physical: byte_at(low, P48),
        armor_elemental: byte_at(low, P56),
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
        penetration: byte_at(high, P40),
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

/// The skill bar (8 skill ids, registry `u16`), locked for the expedition (design/03).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberBar {
    pub skills: [u16; 8],
    /// The slot of the elite skill, 255 for none.
    pub elite_slot: u8,
}

pub fn pack_bar(b: MemberBar) -> felt252 {
    let [s0, s1, s2, s3, s4, s5, s6, s7] = b.skills;
    let low: u128 = s0.into()
        + s1.into() * P16
        + s2.into() * P32
        + s3.into() * P48
        + s4.into() * P64
        + s5.into() * P80
        + s6.into() * P96
        + s7.into() * P112;
    join(low, b.elite_slot.into())
}

pub fn unpack_bar(word: felt252) -> MemberBar {
    let (low, high) = split(word);
    let b16: NonZero<u128> = P16.try_into().unwrap();
    let (low, s0) = DivRem::div_rem(low, b16);
    let (low, s1) = DivRem::div_rem(low, b16);
    let (low, s2) = DivRem::div_rem(low, b16);
    let (low, s3) = DivRem::div_rem(low, b16);
    let (low, s4) = DivRem::div_rem(low, b16);
    let (low, s5) = DivRem::div_rem(low, b16);
    let (s7, s6) = DivRem::div_rem(low, b16);
    MemberBar {
        skills: [
            s0.try_into().unwrap(), s1.try_into().unwrap(), s2.try_into().unwrap(),
            s3.try_into().unwrap(), s4.try_into().unwrap(), s5.try_into().unwrap(),
            s6.try_into().unwrap(), s7.try_into().unwrap(),
        ],
        elite_slot: low_field(high, P8.try_into().unwrap()).try_into().unwrap(),
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
/// (design/15: equipment cannot change during an expedition).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct MemberKit {
    pub belt: [u32; 4],
    pub conditional_damage: u8,
    pub conditional_threshold: u8,
    pub life_steal: u8,
    pub energy_on_hit: u8,
    pub condition_duration: u8,
    pub enchantment_duration: u8,
    pub double_adrenaline_every: u8,
    pub quick_cast_every: u8,
    pub health_bonus: u16,
}

pub fn pack_kit(k: MemberKit) -> felt252 {
    let [b0, b1, b2, b3] = k.belt;
    let low: u128 = b0.into() + b1.into() * P32 + b2.into() * P64 + b3.into() * P96;
    let high: u128 = k.conditional_damage.into()
        + k.conditional_threshold.into() * P8
        + k.life_steal.into() * P16
        + k.energy_on_hit.into() * P24
        + k.condition_duration.into() * P32
        + k.enchantment_duration.into() * P40
        + k.double_adrenaline_every.into() * P48
        + k.quick_cast_every.into() * P56
        + k.health_bonus.into() * P64;
    join(low, high)
}

pub fn unpack_kit(word: felt252) -> MemberKit {
    let (low, high) = split(word);
    let b8: NonZero<u128> = P8.try_into().unwrap();
    let b32: NonZero<u128> = P32.try_into().unwrap();
    let (low, b0) = DivRem::div_rem(low, b32);
    let (low, b1) = DivRem::div_rem(low, b32);
    let (b3, b2) = DivRem::div_rem(low, b32);
    let (high, conditional_damage) = DivRem::div_rem(high, b8);
    let (high, conditional_threshold) = DivRem::div_rem(high, b8);
    let (high, life_steal) = DivRem::div_rem(high, b8);
    let (high, energy_on_hit) = DivRem::div_rem(high, b8);
    let (high, condition_duration) = DivRem::div_rem(high, b8);
    let (high, enchantment_duration) = DivRem::div_rem(high, b8);
    let (high, double_adrenaline_every) = DivRem::div_rem(high, b8);
    let (health_bonus, quick_cast_every) = DivRem::div_rem(high, b8);
    MemberKit {
        belt: [
            b0.try_into().unwrap(), b1.try_into().unwrap(), b2.try_into().unwrap(),
            b3.try_into().unwrap(),
        ],
        conditional_damage: conditional_damage.try_into().unwrap(),
        conditional_threshold: conditional_threshold.try_into().unwrap(),
        life_steal: life_steal.try_into().unwrap(),
        energy_on_hit: energy_on_hit.try_into().unwrap(),
        condition_duration: condition_duration.try_into().unwrap(),
        enchantment_duration: enchantment_duration.try_into().unwrap(),
        double_adrenaline_every: double_adrenaline_every.try_into().unwrap(),
        quick_cast_every: quick_cast_every.try_into().unwrap(),
        health_bonus: health_bonus.try_into().unwrap(),
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
    /// Potions carried in each belt slot.
    pub belt_counts: [u8; 4],
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
        task: task.try_into().unwrap(), kind: kind.try_into().unwrap(),
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
