// Packing rules (docs/architecture/ENG-01-interfaces.md, *Packing*): two limbs, LIVE at bit 250,
// lanes, bitmaps; the snapshot's and the task pages' layouts; identifiers.
use grimworld_logic::content::{LAST_KIND, parts};
use grimworld_logic::packing::{
    Bitmap, Counter, LIVE, Lanes16, Lanes32, join, pack_lanes16, pack_lanes32, unpack_lanes16,
    unpack_lanes32,
};
use grimworld_logic::snapshot::{
    MAX_UNGUARDED_ARMOR, MemberBar, MemberKit, MemberStats, QuickCast, TaskEntry, TaskPage,
    pack_bar, pack_kit, pack_stats, pack_task_page, unpack_bar, unpack_kit, unpack_stats,
    unpack_task_page,
};
use grimworld_logic::types::{goblin_entity, instance_id, instance_parts};
use starknet::storage_access::StorePacking;

const TWO_128: felt252 = 0x100000000000000000000000000000000;

#[test]
#[available_gas(l2_gas: 116267)] // ceil(1.05 × 110730 measured)
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
#[available_gas(l2_gas: 451511)] // ceil(1.05 × 430010 measured)
fn test_lanes16() {
    let lanes = Lanes16 { lanes: [1, 2, 3, 4, 5, 6, 7, 0xFFFF, 9, 10, 11, 12, 13, 14, 0xFFFF] };
    assert(unpack_lanes16(pack_lanes16(lanes)) == lanes, 'round trip');
    let mut one = [0_u16; 15];
    let [a, b, c, d, e, f, g, h, _, j, k, l, m, n, o] = one;
    one = [a, b, c, d, e, f, g, h, 1, j, k, l, m, n, o];
    assert(pack_lanes16(Lanes16 { lanes: one }) == TWO_128 + LIVE, 'lane 8 at bit 128');
}

#[test]
#[available_gas(l2_gas: 21221)] // ceil(1.05 × 20210 measured)
fn test_bitmap() {
    let top: felt252 = 0x200000000000000000000000000000000000000000000000000000000000000; // 2^249
    let bitmap = Bitmap { bits: top + 1 };
    let word = StorePacking::<Bitmap, felt252>::pack(bitmap);
    assert(word == top + 1 + LIVE, 'LIVE above bit 249');
    assert(StorePacking::<Bitmap, felt252>::unpack(word) == bitmap, 'round trip');
}

#[test]
// gas: raised, CBT-01: nine armors by damage type (FX-23, FX-24)
#[available_gas(l2_gas: 579516)] // ceil(1.05 × 551920 measured)
fn test_stats_layout() {
    let stats = MemberStats {
        max_health: 0xFFFF,
        max_energy: 1,
        energy_regen: 2,
        health_regen: 3,
        armor_vs: [63, 1, 2, 3, 4, 5, 6, 7, 63],
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
        requirement_met: 1,
        set_bonuses: 0xFFFF,
    };
    assert(unpack_stats(pack_stats(stats)) == stats, 'round trip');
    let level = MemberStats { level: 1, ..Default::default() };
    assert(pack_stats(level) == 0x10000000000000000 + LIVE, 'level at bit 64');
    let ranks = MemberStats { ranks: 1, ..Default::default() };
    assert(pack_stats(ranks) == TWO_128 + LIVE, 'ranks at bit 128');
    // design/19 §7.2: `ARMOR_VS` types 1–2 at bits 48, 54; types 3–9 at 200 + 6 (type − 3).
    let vs = MemberStats { armor_vs: [1, 1, 0, 0, 0, 0, 0, 0, 0], ..Default::default() };
    assert(pack_stats(vs) == 0x1000000000000 + 0x40000000000000 + LIVE, 'vs 1-2 at 48, 54');
    let vs = MemberStats { armor_vs: [0, 0, 1, 0, 0, 0, 0, 0, 1], ..Default::default() };
    let at200 = 0x100000000000000000000000000000000000000000000000000;
    let at236 = 0x100000000000000000000000000000000000000000000000000000000000;
    assert(pack_stats(vs) == at200 + at236 + LIVE, 'vs 3 at 200, 9 at 236');
}

#[test]
// gas: raised, CBT-01: design/19's passives in the bar and the kit (FX-24)
#[available_gas(l2_gas: 398213)] // ceil(1.05 × 379250 measured)
fn test_bar_and_kit_layout() {
    let bar = MemberBar {
        skills: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], elite_slot: 255, ..Fixture::empty_bar(),
    };
    assert(unpack_bar(pack_bar(bar)) == bar, 'bar round trip');
    let bar = MemberBar { skills: [0, 0, 0, 0, 0, 0, 0, 1], elite_slot: 0, ..Fixture::empty_bar() };
    assert(pack_bar(bar) == 0x10000000000000000000000000000 + LIVE, 'skill 7 at bit 112');
    let kit = MemberKit {
        belt: [1, 2, 3, 0xFFFFFFFF],
        life_steal: 3,
        energy_on_hit: 4,
        condition: 15,
        condition_duration: 63,
        enchantment_duration: 63,
        double_adrenaline_every: 0xFF,
        health_bonus: 0xFFFF,
        armor_stance: -128,
        armor_enchanted: 127,
        knockdown: 3,
        halving: true,
    };
    assert(unpack_kit(pack_kit(kit)) == kit, 'kit round trip');
    let kit = MemberKit { health_bonus: 1, ..Default::default() };
    assert(pack_kit(kit) == 0x10000000000 * TWO_128 + LIVE, 'health bonus at bit 168');
}

#[test]
#[available_gas(l2_gas: 148985)] // ceil(1.05 × 141890 measured)
fn test_task_page_layout() {
    let full = TaskEntry { task: 0xFFFFFFFF, kind: 0xFF, param: 0xFFFF };
    let page = TaskPage { entries: [full, TaskEntry { task: 1, kind: 2, param: 3 }, full, full] };
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

// Fix loop 1: a counter is never 0 in storage (F-4); a high limb that would reach LIVE, or a
// bitmap above bit 249, is refused (F-9).
#[test]
#[available_gas(l2_gas: 18900)] // ceil(1.05 × 18000 measured)
fn test_counter_never_zero() {
    let zero = StorePacking::<Counter, felt252>::pack(Counter { value: 0 });
    assert(zero == LIVE, 'zero is LIVE');
    let max = Counter { value: 0xFFFFFFFFFFFFFFFF };
    let word = StorePacking::<Counter, felt252>::pack(max);
    assert(StorePacking::<Counter, felt252>::unpack(word) == max, 'round trip');
    assert(join(0, 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0, 'widest high limb');
}

#[test]
#[should_panic(expected: 'packing: high limb overflow')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_join_refuses_live_overflow() {
    join(0, 0x4000000000000000000000000000000);
}

#[test]
#[should_panic(expected: 'packing: bitmap above bit 249')]
#[available_gas(l2_gas: 18606)] // ceil(1.05 × 17720 measured)
fn test_bitmap_above_249_refused() {
    let bit250: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
    StorePacking::<Bitmap, felt252>::pack(Bitmap { bits: bit250 });
}

#[generate_trait]
impl FixtureImpl of Fixture {
    /// A bar with no skill and every passive sum 0, the unguarded armor 0.
    fn empty_bar() -> MemberBar {
        MemberBar {
            skills: [0; 8],
            elite_slot: 0,
            damage: [0; 6],
            penetration: [0; 3],
            quick_cast: [Default::default(); 2],
            armor: 0,
        }
    }
}

// design/19 §7.2 (FX-24): the bar's high limb holds the elite slot 128, the damage sums 136–183
// (signed), the penetration sums 184–207, the quick-cast pairs 208–231 and the unguarded armor
// 232–247 (signed); each round-trips at both ends and sits at its bit.
#[test]
#[available_gas(l2_gas: 838415)] // ceil(1.05 × 798490 measured)
fn test_bar_passives_layout() {
    let top = MemberBar {
        skills: [0xFFFF; 8],
        elite_slot: 255,
        damage: [127, -128, 126, -126, 1, -1],
        penetration: [255, 0, 252],
        quick_cast: [QuickCast { attribute: 15, every: 255 }, QuickCast { attribute: 1, every: 5 }],
        armor: -MAX_UNGUARDED_ARMOR,
    };
    assert(unpack_bar(pack_bar(top)) == top, 'top round trip');
    let top = MemberBar { armor: MAX_UNGUARDED_ARMOR, ..top };
    assert(unpack_bar(pack_bar(top)) == top, 'armor max round trip');
    let bit = |bar: MemberBar| -> felt252 {
        pack_bar(bar) - LIVE
    };
    let empty = Fixture::empty_bar();
    let two_136: felt252 = TWO_128 * 0x100;
    assert(bit(MemberBar { damage: [1, 0, 0, 0, 0, 0], ..empty }) == two_136, 'damage at 136');
    assert(
        bit(MemberBar { damage: [-1, 0, 0, 0, 0, 0], ..empty }) == two_136 * 0xFF, 'signed damage',
    );
    let two_184: felt252 = TWO_128 * 0x100000000000000;
    assert(bit(MemberBar { penetration: [1, 0, 0], ..empty }) == two_184, 'penetration at 184');
    let two_208: felt252 = TWO_128 * 0x100000000000000000000;
    let one = QuickCast { attribute: 1, every: 0 };
    assert(
        bit(MemberBar { quick_cast: [one, Default::default()], ..empty }) == two_208, 'qc at 208',
    );
    let two_232: felt252 = TWO_128 * 0x100000000000000000000000000;
    assert(bit(MemberBar { armor: 1, ..empty }) == two_232, 'armor at 232');
    assert(bit(MemberBar { armor: -1, ..empty }) == two_232 * 0xFFFF, 'armor signed');
}

// F-21: the unguarded armor is bounded by 9,995 either way; a wider value is refused.
#[test]
#[should_panic(expected: 'snapshot: armor above bound')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_bar_armor_above_bound_refused() {
    pack_bar(MemberBar { armor: MAX_UNGUARDED_ARMOR + 1, ..Fixture::empty_bar() });
}

#[test]
#[should_panic(expected: 'snapshot: armor above bound')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_bar_armor_below_bound_refused() {
    pack_bar(MemberBar { armor: -MAX_UNGUARDED_ARMOR - 1, ..Fixture::empty_bar() });
}

#[test]
#[should_panic(expected: 'snapshot: quick-cast attribute')]
#[available_gas(l2_gas: 85271)] // ceil(1.05 × 81210 measured)
fn test_bar_quick_cast_attribute_refused() {
    let wide = QuickCast { attribute: 16, every: 1 };
    pack_bar(MemberBar { quick_cast: [Default::default(), wide], ..Fixture::empty_bar() });
}

#[test]
#[should_panic(expected: 'snapshot: armor vs above 63')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_stats_armor_vs_refused() {
    pack_stats(MemberStats { armor_vs: [0, 0, 0, 0, 0, 0, 0, 0, 64], ..Default::default() });
}

// The kit's high limb (design/19 §7.2): 75 bits, each field at its bit; the narrow ones refused
// when wider.
#[test]
#[available_gas(l2_gas: 646905)] // ceil(1.05 × 616100 measured)
fn test_kit_passives_layout() {
    let bit = |kit: MemberKit| -> felt252 {
        pack_kit(kit) - LIVE
    };
    let k = MemberKit { ..Default::default() };
    assert(bit(MemberKit { life_steal: 1, ..k }) == TWO_128, 'life steal at 128');
    assert(bit(MemberKit { energy_on_hit: 1, ..k }) == TWO_128 * 0x100, 'energy at 136');
    assert(bit(MemberKit { condition: 1, ..k }) == TWO_128 * 0x10000, 'condition at 144');
    assert(bit(MemberKit { condition_duration: 1, ..k }) == TWO_128 * 0x100000, 'cond % at 148');
    assert(bit(MemberKit { enchantment_duration: 1, ..k }) == TWO_128 * 0x4000000, 'ench at 154');
    assert(bit(MemberKit { double_adrenaline_every: 1, ..k }) == TWO_128 * 0x100000000, 'N at 160');
    assert(bit(MemberKit { armor_stance: 1, ..k }) == TWO_128 * 0x100000000000000, 'stance 184');
    assert(bit(MemberKit { armor_stance: -1, ..k }) == TWO_128 * 0xFF00000000000000, 'signed');
    assert(bit(MemberKit { armor_enchanted: 1, ..k }) == TWO_128 * 0x10000000000000000, 'ench 192');
    assert(bit(MemberKit { knockdown: 1, ..k }) == TWO_128 * 0x1000000000000000000, 'kd at 200');
    assert(bit(MemberKit { halving: true, ..k }) == TWO_128 * 0x4000000000000000000, 'halving 202');
    let top = MemberKit {
        belt: [0xFFFFFFFF; 4],
        life_steal: 0xFF,
        energy_on_hit: 0xFF,
        condition: 15,
        condition_duration: 63,
        enchantment_duration: 63,
        double_adrenaline_every: 0xFF,
        health_bonus: 0xFFFF,
        armor_stance: 127,
        armor_enchanted: -128,
        knockdown: 3,
        halving: true,
    };
    let word = pack_kit(top);
    assert(unpack_kit(word) == top, 'top round trip');
    // 75 bits: the high limb's highest set bit is 202.
    let wide: u256 = word.into();
    assert(wide.high - 0x4000000000000000000000000000000 < 0x8000000000000000000, 'within 75');
}

#[test]
#[should_panic(expected: 'snapshot: knock-down above 3')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_kit_knockdown_refused() {
    pack_kit(MemberKit { knockdown: 4, ..Default::default() });
}

#[test]
#[should_panic(expected: 'snapshot: percent above 63')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_kit_percent_refused() {
    pack_kit(MemberKit { enchantment_duration: 64, ..Default::default() });
}

#[test]
#[should_panic(expected: 'snapshot: condition')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_kit_condition_refused() {
    pack_kit(MemberKit { condition: 16, ..Default::default() });
}
