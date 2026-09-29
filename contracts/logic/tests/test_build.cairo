// D-160 (design/20 §6): the acceptance tests the validators and the production flattening owe
// before any production snapshot. Tests 1 to 7 and 9 are here or in `test_tick`, `test_capacity`,
// `test_durations` and the ephemeral `test_layout` (each named below); test 8 (a hit's percents)
// is the damage formula's, CBT-03's, and test 10's counters are CBT-05's.
use grimworld_logic::content::Record;
use grimworld_logic::helpers::exp2::Exp2;
use grimworld_logic::models::armor_set::{ArmorSetAssert, ArmorSetTrait};
use grimworld_logic::models::caste::{CasteAssert, CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::index::{Caste, Skill};
use grimworld_logic::models::modifier::{ModifierAssert, ModifierTrait, slot};
use grimworld_logic::models::skill::SkillTrait;
use grimworld_logic::snapshot::{HeldPassive, Loadout, MemberStats, SnapshotBuildTrait, pack_stats};
use grimworld_logic::types::combat::{condition, damage, skill_kind, weapon};
use grimworld_logic::types::effect::{Carrier, EntryAssert, EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::passive::{Passive, PassiveTrait, Source, id};
use grimworld_logic::types::tick::CasteSheetTrait;

/// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
const PRIMARY: u8 = 13;
const OTHER: u8 = 14;

fn passive(id: u8, param: u8, value: i16) -> Passive {
    PassiveTrait::new(id, param, 0, 0, value, value)
}

fn held(passive: Passive, source: Source, instance: u8, modifier: u32) -> HeldPassive {
    HeldPassive { passive, source, instance, modifier, benefit: true }
}

fn cost(passive: Passive, source: Source, instance: u8, modifier: u32) -> HeldPassive {
    HeldPassive { passive, source, instance, modifier, benefit: false }
}

/// A level-20 build of `profession`: 12 points in its primary, 10 in another, a sword
/// (damage 18 at requirement, ticks 1, range 1) of the other attribute, strength cap 75.
fn loadout(profession: u8, level: u8) -> Loadout {
    Loadout {
        level,
        profession,
        points: array![(PRIMARY, 12), (OTHER, 10)].span(),
        bar_attributes: [PRIMARY, OTHER, 0, 0, 0, 0, 0, 0],
        skills: [1, 2, 0, 0, 0, 0, 0, 0],
        elite_slot: 255,
        weapon: weapon::SWORD,
        weapon_damage: 18,
        weapon_ticks: 1,
        weapon_range: 1,
        damage_type: damage::SLASHING,
        weapon_attribute: OTHER,
        requirement_met: 1,
        personalised: false,
        strength_cap: 75,
        rating: 0,
        set_bonuses: 0,
        belt: [0; 4],
        belt_counts: [0; 4],
    }
}

/// The 17 sources of design/20 §1.2, instances 0–16: a prefix, 2 suffixes, 2 inscriptions, 5
/// insignias, 5 runes, 2 set bonuses.
fn sources() -> Span<Source> {
    array![
        Source::Prefix, Source::Suffix, Source::Suffix, Source::Inscription, Source::Inscription,
        Source::Insignia, Source::Insignia, Source::Insignia, Source::Insignia, Source::Insignia,
        Source::Rune, Source::Rune, Source::Rune, Source::Rune, Source::Rune, Source::SetBonus,
        Source::SetBonus,
    ]
        .span()
}

/// One passive on each source of `on` (a subset of the 17), instance `i`, modifier id `100 + i`.
fn everywhere(p: Passive, on: Span<Source>) -> Array<HeldPassive> {
    let mut all = array![];
    let mut i: u8 = 0;
    for source in sources() {
        let mut take = false;
        for kind in on {
            if *kind == *source {
                take = true;
            }
        }
        if take {
            all.append(held(p, *source, i, 100 + i.into()));
        }
        i += 1;
    }
    all
}

fn held_slots() -> Span<Source> {
    array![Source::Prefix, Source::Suffix, Source::Inscription].span()
}

fn fits(p: Passive, source: Source) -> bool {
    p.allows(source) && PassiveTrait::fits_source(array![p].span(), source)
}

// §6 test 1: for each row of §1.3 under B, a source at its bound passes, a unit beyond is
// refused, a source that may not hold the passive is refused, and a modifier's benefit and cost are
// summed.
#[test]
#[available_gas(l2_gas: 1897833)] // ceil(1.05 × 1807460 measured)
fn test_per_source_bounds() {
    // (id, param, source, lo, hi)
    let rows = array![
        (id::MAX_HEALTH, 0, Source::Prefix, 0_i16, 30_i16),
        (id::MAX_HEALTH, 0, Source::Insignia, 0, 15), (id::MAX_HEALTH, 0, Source::Rune, -75, 50),
        (id::MAX_HEALTH, 0, Source::SetBonus, -75, 50), (id::MAX_ENERGY, 0, Source::Suffix, -5, 5),
        (id::MAX_ENERGY, 0, Source::SetBonus, -5, 5),
        (id::ENERGY_REGEN, 0, Source::Inscription, -1, 0),
        (id::ENERGY_REGEN, 0, Source::SetBonus, -1, 1),
        (id::HEALTH_REGEN, 0, Source::Prefix, -1, 0),
        (id::HEALTH_REGEN, 0, Source::SetBonus, -1, 1),
        (id::ARMOR_VS, damage::FIRE, Source::Rune, 0, 7),
        (id::ATTRIBUTE, PRIMARY, Source::Rune, 1, 3),
        (id::LIFE_STEAL_ON_HIT, 0, Source::Suffix, 0, 5),
        (id::ENERGY_ON_HIT, 0, Source::Prefix, 0, 1),
        (id::CONDITION_DURATION, condition::POISON, Source::Prefix, 0, 33),
        (id::ENCHANT_DURATION, 0, Source::Insignia, 0, 20),
        (id::KNOCKDOWN_FLAT, 0, Source::SetBonus, 0, 1),
    ];
    for (i, param, source, lo, hi) in rows {
        assert(fits(passive(i, param, lo), source), 'at lo');
        assert(fits(passive(i, param, hi), source), 'at hi');
        assert(!fits(passive(i, param, hi + 1), source), 'above hi');
        assert(!fits(passive(i, param, lo - 1), source), 'below lo');
    }
    // Sources that may not hold them (DS-4; rows 2–4, 8, 13, 14).
    let refused = array![
        (id::ENERGY_COST, Source::Prefix), (id::ENERGY_COST, Source::SetBonus),
        (id::BASE_DAMAGE_PERCENT, Source::Prefix), (id::BASE_DAMAGE_PERCENT, Source::Rune),
        (id::ATTRIBUTE, Source::Insignia), (id::ATTRIBUTE, Source::Prefix),
        (id::LIFE_STEAL_ON_HIT, Source::SetBonus), (id::ENERGY_ON_HIT, Source::Rune),
        (id::MAX_ENERGY, Source::Insignia), (id::MAX_ENERGY, Source::Rune),
        (id::ENERGY_REGEN, Source::Rune), (id::HEALTH_REGEN, Source::Insignia),
    ];
    for (i, source) in refused {
        assert(!passive(i, 0, 0).allows(source), 'source refused');
    }
    // A modifier's benefit and cost on one statistic are summed: +50 and −75 on a rune, −25.
    let pair = array![passive(id::MAX_HEALTH, 0, 50), passive(id::MAX_HEALTH, 0, -75)];
    assert(PassiveTrait::fits_source(pair.span(), Source::Rune), 'summed within');
    let pair = array![passive(id::MAX_HEALTH, 0, 30), passive(id::MAX_HEALTH, 0, 30)];
    assert(!PassiveTrait::fits_source(pair.span(), Source::Prefix), 'summed above');
    // Two types of armor are two statistics: 7 + 7.
    let pair = array![passive(id::ARMOR_VS, 1, 7), passive(id::ARMOR_VS, 2, 7)];
    assert(PassiveTrait::fits_source(pair.span(), Source::Rune), 'per type');
}

// §6 test 1, through the validators: a modifier a unit beyond its bound is refused.
#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 144470)] // ceil(1.05 × 137590 measured)
fn test_modifier_beyond_bound_refused() {
    ModifierTrait::new(slot::PREFIX, passive(id::MAX_HEALTH, 0, 31), Default::default())
        .assert_legal();
}

#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 35249)] // ceil(1.05 × 33570 measured)
fn test_set_bonus_beyond_bound_refused() {
    let knock = passive(id::KNOCKDOWN_FLAT, 0, 2);
    ArmorSetTrait::new([1, 2, 3, 4, 5], [knock, knock]).assert_legal();
}

// §6 test 2: max health 1,020 (DS-23's insignias 15 / 10 / 5, D-160): level 20, five +30 held
// slots, insignias 15, 10, 5, 5, 5, five +50 health runes of distinct ids, two +50 set bonuses.
// The final maximum is `max_health`; `health_bonus` is freed (DS-3).
#[test]
#[available_gas(l2_gas: 7143213)] // ceil(1.05 × 6803060 measured)
fn test_extremal_max_health() {
    let mut all = everywhere(passive(id::MAX_HEALTH, 0, 30), held_slots());
    let insignias = [15_i16, 10, 5, 5, 5];
    let mut k: u8 = 0;
    for value in insignias.span() {
        all.append(held(passive(id::MAX_HEALTH, 0, *value), Source::Insignia, 5 + k, 200));
        k += 1;
    }
    for held_passive in everywhere(
        passive(id::MAX_HEALTH, 0, 50), array![Source::Rune, Source::SetBonus].span(),
    ) {
        all.append(held_passive);
    }
    let snapshot = SnapshotBuildTrait::build(@loadout(1, 20), all.span());
    assert(snapshot.stats.max_health == 1020, 'max health 1,020');
    assert(snapshot.kit.health_bonus == 0, 'health bonus freed');
}

// §6 test 2: max energy 130 (DS-7): an Arcanist at Wellspring 15 (12 points and a +3 rune: ranks
// 15, DS-8) in light armor, five held slots and two set bonuses at +5: 30 + 45 + 20 + 35.
#[test]
#[available_gas(l2_gas: 3003189)] // ceil(1.05 × 2860180 measured)
fn test_extremal_max_energy_and_rank() {
    let mut all = everywhere(
        passive(id::MAX_ENERGY, 0, 5),
        array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
    );
    all.append(held(passive(id::ATTRIBUTE, PRIMARY, 3), Source::Rune, 10, 300));
    let snapshot = SnapshotBuildTrait::build(@loadout(3, 20), all.span());
    assert(snapshot.stats.max_energy == 130, 'max energy 130');
    assert(snapshot.stats.primary_rank == 15, 'rank 15');
    // The bar's ranks: slot 0 the primary (15), slot 1 the other (10), 4 bits each.
    assert(snapshot.stats.ranks == 15 + 10 * 16, 'bar ranks');
    // Light armor's +1 pip (DS-7): 4 + 1.
    assert(snapshot.stats.energy_regen == 5, 'energy regen');
    assert(snapshot.stats.health_regen == 10, 'health regen');
}

// §6 test 2: weapon damage 32, a personalised maul at requirement (27 × 120 / 100, DS-4); the
// strength is 5 × the weapon attribute's rank capped by level (DS-9): 50, and 40 under a cap of
// 40.
#[test]
#[available_gas(l2_gas: 611205)] // ceil(1.05 × 582100 measured)
fn test_extremal_weapon() {
    let maul = Loadout {
        weapon: weapon::MAUL,
        weapon_damage: 27,
        weapon_ticks: 2,
        personalised: true,
        ..loadout(1, 20),
    };
    let snapshot = SnapshotBuildTrait::build(@maul, array![].span());
    assert(snapshot.stats.weapon_damage == 32, 'weapon damage 32');
    assert(snapshot.stats.weapon_strength == 50, '5 x 10');
    let capped = Loadout { strength_cap: 40, ..maul };
    let snapshot = SnapshotBuildTrait::build(@capped, array![].span());
    assert(snapshot.stats.weapon_strength == 40, 'capped by level');
}

// §6 test 2, "each other field ≤ its envelope": every source at its widest on every other row.
#[test]
#[available_gas(l2_gas: 11646737)] // ceil(1.05 × 11092130 measured)
fn test_other_fields_within_envelopes() {
    let mut all = array![];
    let mut i: u8 = 0;
    for source in sources() {
        let s = *source;
        let modifier: u32 = 100 + i.into();
        if s == Source::Prefix || s == Source::Suffix || s == Source::Inscription {
            all.append(held(passive(id::LIFE_STEAL_ON_HIT, 0, 5), s, i, modifier));
            all.append(cost(passive(id::ENERGY_REGEN, 0, -1), s, i, modifier));
        } else if s == Source::SetBonus {
            all.append(held(passive(id::HEALTH_REGEN, 0, 1), s, i, modifier));
        } else {
            all.append(held(passive(id::ARMOR_VS, damage::FIRE, 7), s, i, modifier));
            all.append(cost(passive(id::ARMOR_VS, damage::COLD, 7), s, i, modifier));
        }
        i += 1;
    }
    let snapshot = SnapshotBuildTrait::build(@loadout(3, 20), all.span());
    assert(snapshot.kit.life_steal == 25, 'life steal 25');
    // 4 + 1 (light) − 5 = 0, the floor.
    assert(snapshot.stats.energy_regen == 0, 'energy regen 0');
    assert(snapshot.stats.health_regen == 12, 'health regen +2');
    let [_, _, _, fire, cold, _, _, _, _] = snapshot.stats.armor_vs;
    // 10 sources at 7: 70, saturated at 63 (FX-23).
    assert(fire == 63 && cold == 63, 'armor vs 10 x 7 saturated');
}

// §6 test 3: the floors (DS-2), level 1 with every cost at its bound: refused.
#[test]
#[should_panic(expected: 'build: max health below 1')]
#[available_gas(l2_gas: 2334665)] // ceil(1.05 × 2223490 measured)
fn test_floor_max_health_refused() {
    // Runes: +5 armor and −75 health; set bonuses −75: 100 − 375 − 150.
    let mut all = array![];
    let mut i: u8 = 10;
    while i < 15 {
        all.append(held(passive(id::ARMOR, 0, 5), Source::Rune, i, 400));
        all.append(cost(passive(id::MAX_HEALTH, 0, -75), Source::Rune, i, 400));
        i += 1;
    }
    all.append(held(passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 15, 0));
    all.append(held(passive(id::MAX_HEALTH, 0, -75), Source::SetBonus, 16, 0));
    SnapshotBuildTrait::build(@loadout(1, 1), all.span());
}

#[test]
#[should_panic(expected: 'build: max energy below 0')]
#[available_gas(l2_gas: 1905992)] // ceil(1.05 × 1815230 measured)
fn test_floor_max_energy_refused() {
    // A Vanguard's 20, five held slots and two set bonuses at −5: −15.
    let all = everywhere(
        passive(id::MAX_ENERGY, 0, -5),
        array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
    );
    SnapshotBuildTrait::build(@loadout(1, 1), all.span());
}

#[test]
#[should_panic(expected: 'build: energy regen below 0')]
#[available_gas(l2_gas: 1920576)] // ceil(1.05 × 1829120 measured)
fn test_floor_energy_regen_refused() {
    // A Vanguard's 2 pips, five held slots and two set bonuses at −1: −5.
    let all = everywhere(
        passive(id::ENERGY_REGEN, 0, -1),
        array![Source::Prefix, Source::Suffix, Source::Inscription, Source::SetBonus].span(),
    );
    SnapshotBuildTrait::build(@loadout(1, 1), all.span());
}

// §6 test 4 (DS-5): enchantment 340 → 50 (17 sources at 20), knock-down 4 → 3, armor against a
// type 149 → 63 (a Warden's +30 elemental and 17 sources at 7). Condition duration 65,534 → 50:
// `test_capacity::test_same_condition_capped`.
#[test]
#[available_gas(l2_gas: 16035044)] // ceil(1.05 × 15271470 measured)
fn test_saturation() {
    let all = everywhere(passive(id::ENCHANT_DURATION, 0, 20), sources());
    let snapshot = SnapshotBuildTrait::build(@loadout(2, 20), all.span());
    assert(snapshot.kit.enchantment_duration == 50, 'enchantment 340 -> 50');
    let all = everywhere(
        passive(id::KNOCKDOWN_FLAT, 0, 1), array![Source::Suffix, Source::Inscription].span(),
    );
    let snapshot = SnapshotBuildTrait::build(@loadout(2, 20), all.span());
    assert(snapshot.kit.knockdown == 3, 'knock-down 4 -> 3');
    let all = everywhere(passive(id::ARMOR_VS, damage::FIRE, 7), sources());
    let snapshot = SnapshotBuildTrait::build(@loadout(2, 20), all.span());
    let [_, _, _, fire, _, _, _, _, _] = snapshot.stats.armor_vs;
    assert(fire == 63, 'armor vs 149 -> 63');
}

// §6 test 5 (FX-43, D-157 D): two health runes of one modifier id count once; of two ids, both.
#[test]
#[available_gas(l2_gas: 1930194)] // ceil(1.05 × 1838280 measured)
fn test_rune_identity() {
    let rune = passive(id::MAX_HEALTH, 0, 50);
    let same = array![held(rune, Source::Rune, 10, 7), held(rune, Source::Rune, 11, 7)];
    let snapshot = SnapshotBuildTrait::build(@loadout(1, 20), same.span());
    assert(snapshot.stats.max_health == 480 + 50, 'one id: once');
    let two = array![held(rune, Source::Rune, 10, 7), held(rune, Source::Rune, 11, 8)];
    let snapshot = SnapshotBuildTrait::build(@loadout(1, 20), two.span());
    assert(snapshot.stats.max_health == 480 + 100, 'two ids: both');
}

// The flattening refuses a build that is not one: a sixth rune, a source of two kinds.
#[test]
#[should_panic(expected: 'build: too many of a source')]
#[available_gas(l2_gas: 1261817)] // ceil(1.05 × 1201730 measured)
fn test_sixth_rune_refused() {
    let mut all = array![];
    let mut i: u8 = 0;
    while i < 6 {
        all.append(held(passive(id::ARMOR, 0, 5), Source::Rune, i, 1));
        i += 1;
    }
    SnapshotBuildTrait::build(@loadout(1, 20), all.span());
}

#[test]
#[should_panic(expected: 'build: one source, one kind')]
#[available_gas(l2_gas: 268286)] // ceil(1.05 × 255510 measured)
fn test_instance_of_two_kinds_refused() {
    let all = array![
        held(passive(id::ARMOR, 0, 5), Source::Rune, 0, 1),
        held(passive(id::ARMOR, 0, 5), Source::Insignia, 0, 1),
    ];
    SnapshotBuildTrait::build(@loadout(1, 20), all.span());
}

/// A caste at design/20's bounds (DS-18, DS-29): multiplier 1,000 %, energy 85, regeneration 10
/// pips, weapon damage 255, flee 100, health regeneration 20.
fn caste_at_bounds() -> Caste {
    CasteTrait::new(
        6,
        1,
        1000,
        20,
        40,
        [0; 9],
        WeaponTrait::new(weapon::MAUL, 255, damage::BLUNT, 2, 1),
        85,
        10,
        [1, 0, 0, 0],
        15,
        100,
        0,
        false,
    )
}

fn skill_of(adrenaline: u8) -> Skill {
    SkillTrait::new(
        1,
        1,
        skill_kind::ATTACK,
        0,
        adrenaline,
        1,
        5,
        1,
        target::FOE,
        false,
        [Default::default(); 3],
    )
}

// §6 test 6: `m` = 1,000 at level 255 gives 51,800 (a `u16` of `GoblinState`); energy 85 is 255
// thirds (a `u8`); a skill of 63 strikes is usable. It packs.
#[test]
#[available_gas(l2_gas: 236355)] // ceil(1.05 × 225100 measured)
fn test_caste_at_bounds() {
    let caste = caste_at_bounds();
    caste.assert_legal();
    let parts = Record::<Caste>::pack(@caste);
    let sheet = CasteSheetTrait::read(1, parts);
    let health: u16 = sheet.max_health(255).try_into().unwrap();
    assert(health == 51800, 'health 51,800');
    let energy: u8 = (sheet.energy * 3).try_into().unwrap();
    assert(energy == 255, 'energy 255 thirds');
    CasteAssert::assert_skills(array![skill_of(63)].span());
}

#[test]
#[should_panic(expected: 'caste: health above 1000 %')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_multiplier_1001_refused() {
    let caste = Caste { health: 1001, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: energy regen above 10')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_energy_regen_refused() {
    let caste = Caste { energy_regen: 11, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: weapon damage above 255')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_weapon_damage_refused() {
    let caste = Caste {
        weapon: WeaponTrait::new(weapon::MAUL, 256, damage::BLUNT, 2, 1), ..caste_at_bounds(),
    };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: flee above 100')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_flee_refused() {
    let caste = Caste { flee: 101, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: skill adrenaline')]
#[available_gas(l2_gas: 57635)] // ceil(1.05 × 54890 measured)
fn test_caste_skill_of_64_strikes_refused() {
    CasteAssert::assert_skills(array![skill_of(63), skill_of(64)].span());
}

// §6 test 9 (DS-29): a caste's health regeneration 21 is refused at `pack`; `pack_stats` refuses
// 21 and accepts 20. The tick's extremes: `test_tick::test_regeneration_extremes`.
#[test]
#[should_panic(expected: 'caste: health regen')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_health_regen_21_refused_at_pack() {
    let caste = Caste { health_regen: 21, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[available_gas(l2_gas: 113117)] // ceil(1.05 × 107730 measured)
fn test_stats_health_regen_20_packs() {
    pack_stats(MemberStats { health_regen: 20, ..Default::default() });
}

#[test]
#[should_panic(expected: 'snapshot: health regen')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_stats_health_regen_21_refused() {
    pack_stats(MemberStats { health_regen: 21, ..Default::default() });
}

// §6 test 7: one hit's product in a `u64` (§1.6): B's base 33,022 at x = 80 and A's 163,836.
#[test]
#[available_gas(l2_gas: 18638)] // ceil(1.05 × 17750 measured)
fn test_one_hit_product() {
    let table: u64 = Exp2::at(80).into();
    assert(33022 * table == 8656519168, 'B: < 2^34');
    assert(163836 * table == 42948624384, 'A: < 2^36');
}

// §6 test 7, DS-20: a second `ATTACK_BONUS` on one carrier is refused.
#[test]
#[should_panic(expected: 'carrier: two attack bonuses')]
#[available_gas(l2_gas: 162351)] // ceil(1.05 × 154620 measured)
fn test_second_attack_bonus_refused() {
    let bonus = EntryTrait::new(
        kind::ATTACK_BONUS, 0, 5, 5, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    EntryAssert::assert_carrier(array![bonus, bonus, Default::default()].span(), Carrier::Attack);
}
