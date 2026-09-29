// Packing rules (docs/architecture/ENG-01-interfaces.md, *Packing*): two limbs, LIVE at bit 250,
// lanes, bitmaps; the snapshot's and the task pages' layouts; identifiers.
use grimworld_logic::content::{LAST_KIND, parts};
use grimworld_logic::packing::{
    Bitmap, Lanes16, Lanes32, LIVE, pack_lanes16, pack_lanes32, unpack_lanes16, unpack_lanes32,
};
use grimworld_logic::snapshot::{
    MemberBar, MemberKit, MemberStats, TaskEntry, TaskPage, pack_bar, pack_kit, pack_stats,
    pack_task_page, unpack_bar, unpack_kit, unpack_stats, unpack_task_page,
};
use grimworld_logic::types::{goblin_entity, instance_id, instance_parts};
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

#[test]
#[available_gas(l2_gas: 116676)] // ceil(1.05 × 111120 measured)
fn test_lanes32() {
    let lanes = Lanes32 { lanes: [1, 2, 3, 0xFFFFFFFF, 5, 6, 0xFFFFFFFF] };
    let word = pack_lanes32(lanes);
    assert(unpack_lanes32(word) == lanes, 'round trip');
    let one = pack_lanes32(Lanes32 { lanes: [0, 0, 0, 0, 1, 0, 0] });
    assert(one == TWO_128 + LIVE, 'lane 4 at bit 128');
    assert(pack_lanes32(Lanes32 { lanes: [0; 7] }) == LIVE, 'empty is LIVE, not 0');
    assert(unpack_lanes32(0) == Lanes32 { lanes: [0; 7] }, 'unwritten is empty');
}

#[test]
#[available_gas(l2_gas: 450482)] // ceil(1.05 × 429030 measured)
fn test_lanes16() {
    let lanes = Lanes16 {
        lanes: [1, 2, 3, 4, 5, 6, 7, 0xFFFF, 9, 10, 11, 12, 13, 14, 0xFFFF],
    };
    assert(unpack_lanes16(pack_lanes16(lanes)) == lanes, 'round trip');
    let mut one = [0_u16; 15];
    let [a, b, c, d, e, f, g, h, _, j, k, l, m, n, o] = one;
    one = [a, b, c, d, e, f, g, h, 1, j, k, l, m, n, o];
    assert(pack_lanes16(Lanes16 { lanes: one }) == TWO_128 + LIVE, 'lane 8 at bit 128');
}

#[test]
#[available_gas(l2_gas: 19100)] // ceil(1.05 × 18190 measured)
fn test_bitmap() {
    let top: felt252 = 0x200000000000000000000000000000000000000000000000000000000000000; // 2^249
    let bitmap = Bitmap { bits: top + 1 };
    let word = StorePacking::<Bitmap, felt252>::pack(bitmap);
    assert(word == top + 1 + LIVE, 'LIVE above bit 249');
    assert(StorePacking::<Bitmap, felt252>::unpack(word) == bitmap, 'round trip');
}

#[test]
#[available_gas(l2_gas: 317657)] // ceil(1.05 × 302530 measured)
fn test_stats_layout() {
    let stats = MemberStats {
        max_health: 0xFFFF,
        max_energy: 1,
        energy_regen: 2,
        health_regen: 3,
        armor: 4,
        armor_physical: 5,
        armor_elemental: 6,
        level: 7,
        profession: 8,
        primary_rank: 9,
        weapon: 10,
        weapon_damage: 11,
        weapon_ticks: 12,
        weapon_range: 13,
        weapon_strength: 0xFF,
        ranks: 0xFFFFFFFF,
        damage_type: 14,
        penetration: 15,
        requirement_met: 1,
        set_bonuses: 0xFFFF,
    };
    assert(unpack_stats(pack_stats(stats)) == stats, 'round trip');
    let level = MemberStats { level: 1, ..Default::default() };
    assert(pack_stats(level) == 0x10000000000000000 + LIVE, 'level at bit 64');
    let ranks = MemberStats { ranks: 1, ..Default::default() };
    assert(pack_stats(ranks) == TWO_128 + LIVE, 'ranks at bit 128');
}

#[test]
#[available_gas(l2_gas: 222600)] // ceil(1.05 × 212000 measured)
fn test_bar_and_kit_layout() {
    let bar = MemberBar { skills: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], elite_slot: 255 };
    assert(unpack_bar(pack_bar(bar)) == bar, 'bar round trip');
    let bar = MemberBar { skills: [0, 0, 0, 0, 0, 0, 0, 1], elite_slot: 0 };
    assert(pack_bar(bar) == 0x10000000000000000000000000000 + LIVE, 'skill 7 at bit 112');
    let kit = MemberKit {
        belt: [1, 2, 3, 0xFFFFFFFF],
        conditional_damage: 1,
        conditional_threshold: 2,
        life_steal: 3,
        energy_on_hit: 4,
        condition_duration: 5,
        enchantment_duration: 6,
        double_adrenaline_every: 7,
        quick_cast_every: 8,
        health_bonus: 0xFFFF,
    };
    assert(unpack_kit(pack_kit(kit)) == kit, 'kit round trip');
    let kit = MemberKit { health_bonus: 1, ..Default::default() };
    assert(pack_kit(kit) == 0x10000000000000000 * TWO_128 + LIVE, 'health bonus at bit 192');
}

#[test]
#[available_gas(l2_gas: 149132)] // ceil(1.05 × 142030 measured)
fn test_task_page_layout() {
    let full = TaskEntry { task: 0xFFFFFFFF, kind: 0xFF, param: 0xFFFF };
    let page = TaskPage {
        entries: [full, TaskEntry { task: 1, kind: 2, param: 3 }, full, full],
    };
    assert(unpack_task_page(pack_task_page(page)) == page, 'round trip');
    let second = TaskPage {
        entries: [
            Default::default(), TaskEntry { task: 1, kind: 0, param: 0 }, Default::default(),
            TaskEntry { task: 0, kind: 1, param: 0 },
        ],
    };
    // Entry 1 at bit 56; entry 3 at bit 184, its kind at bit 216.
    let expected = 0x100000000000000 + 0x100000000 * 0x100000000000000 * TWO_128 + LIVE;
    assert(pack_task_page(second) == expected, 'offsets');
}

#[test]
#[available_gas(l2_gas: 20003)] // ceil(1.05 × 19050 measured)
fn test_identifiers() {
    let id = instance_id(7, 3);
    assert(id == 7 * 0x100000000 + 3, 'instance id');
    assert(instance_parts(id) == (7, 3), 'parts');
    assert(goblin_entity(0, 0) == 8, 'first goblin');
    assert(goblin_entity(224, 9) == 8 + 16 * 224 + 9, 'last goblin');
    assert(parts(2) == 2 && parts(15) == 3 && parts(LAST_KIND) == 1, 'parts per kind');
}
