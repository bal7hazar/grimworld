// D-160 (design/20 §6): the acceptance tests the validators owe before any production snapshot.
// Tests 1, 6, 7 and 9 are here or in `test_tick`, `test_capacity`, `test_durations` and the
// ephemeral `test_layout` (each named below); tests 2 to 5, the flattening's, are its unit tests
// (`snapshot.cairo`, D-167); the registry's refusals of the same records, when the administrator
// writes them (D-166), are the persistent package's `test_registry`. Test 8 (a hit's percents) is
// the damage formula's, CBT-03's, and test 10's counters are CBT-05's.
use grimworld_logic::content::Record;
use grimworld_logic::helpers::exp2::Exp2;
use grimworld_logic::models::armor_set::{ArmorSetAssert, ArmorSetTrait};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::caste::{CasteAssert, CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::index::{Caste, Skill};
use grimworld_logic::models::modifier::{
    Modifier, ModifierAssert, ModifierRecord, ModifierTrait, slot,
};
use grimworld_logic::models::skill::SkillTrait;
use grimworld_logic::snapshot::max_instances;
use grimworld_logic::types::combat::{condition, damage, skill_kind, weapon};
use grimworld_logic::types::effect::{Carrier, EntryAssert, EntryTrait, filter, kind, shape, target};
use grimworld_logic::types::passive::{Passive, PassiveTrait, Source, id, source_bound};
use grimworld_logic::types::tick::CasteSheetTrait;

/// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
const PRIMARY: u8 = 13;

fn passive(id: u8, param: u8, value: i16) -> Passive {
    PassiveTrait::new(id, param, 0, 0, value, value)
}

fn fits(p: Passive, source: Source) -> bool {
    p.allows(source) && PassiveTrait::fits_source(array![p].span(), source)
}

// §6 test 1: for each row of §1.3 under B, a source at its bound passes, a unit beyond is
// refused, a source that may not hold the passive is refused, and a modifier's benefit and cost are
// summed.
#[test]
#[available_gas(l2_gas: 1716257)] // ceil(1.05 × 1634530 measured)
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

/// What `n` sources of each kind that may hold `p`'s statistic add at most (`hi`) and at least
/// (`lo`): `Σ max_instances(kind) × bound(kind)` over the kinds `allows` admits.
fn envelope(i: u8, param: u8) -> (i32, i32) {
    let mut lo: i32 = 0;
    let mut hi: i32 = 0;
    for source in array![
        Source::Prefix, Source::Suffix, Source::Inscription, Source::Insignia, Source::Rune,
        Source::SetBonus,
    ] {
        if passive(i, param, 0).allows(source) {
            let (l, h) = source_bound(i, source).unwrap();
            let n: i32 = max_instances(source).into();
            lo += n * l;
            hi += n * h;
        }
    }
    (lo, hi)
}

// AUD-182-2, the capacity proof, computed from the tables the validators enforce
// (`source_bound`, `allows`, `max_instances`): every accepted build fits each field. Each passive
// alone and each source's sum lie in the source's `[lo, hi]` (`fits_source`), so whatever the
// flattening selects (a rune's benefit once per id, the highest attribute rune) with every cost
// stays within the `n × [lo, hi]` computed here. The lower ends of max health, max energy and
// energy regeneration go below their floors and are refused (DS-2); every other field is shown.
#[test]
#[available_gas(l2_gas: 275846)] // ceil(1.05 × 262710 measured)
fn test_capacity_proof() {
    // Max health: `100 + 20 (L − 1)` at level 255, the `u8`'s widest, + equipment ≤ 65,535. The
    // insignias add their pieces' 15 + 10 + 5 + 5 + 5 = 40 (DS-23), not five times the chest's 15.
    let (_, hi) = envelope(id::MAX_HEALTH, 0);
    let mut insignias: i32 = 0;
    for piece in base_slot::CHEST..base_slot::FEET + 1 {
        insignias += ModifierTrait::insignia_health(piece);
    }
    assert(insignias == 40, 'insignias 40');
    let hi = hi - 5 * 15 + insignias;
    assert(480 + hi == 1020, 'max health 1,020 at level 20');
    assert(100 + 20 * 254 + hi <= 65535, 'max health u16');
    // Max energy: 30 + Wellspring 3 × 15 + light armor 20 + equipment ≤ 255.
    let (_, hi) = envelope(id::MAX_ENERGY, 0);
    assert(30 + 3 * 15 + 20 + hi == 130, 'max energy 130 <= u8');
    // Energy regeneration: 4 + 1 + equipment ≤ 255.
    let (_, hi) = envelope(id::ENERGY_REGEN, 0);
    assert(4 + 1 + hi == 7, 'energy regen 7');
    // Health regeneration, stored + 10: within 0…20 at both ends (DS-29).
    let (lo, hi) = envelope(id::HEALTH_REGEN, 0);
    assert(10 + lo == 3 && 10 + hi == 12, 'health regen 3..12');
    // Life steal and energy on hit, `u8`.
    let (_, hi) = envelope(id::LIFE_STEAL_ON_HIT, 0);
    assert(hi == 25, 'life steal 25');
    let (_, hi) = envelope(id::ENERGY_ON_HIT, 0);
    assert(hi == 5, 'energy on hit 5');
    // A rank: 12 points and the highest rune's ≤ 3: 15, the 4 bits' widest (DS-8).
    let (_, rune) = source_bound(id::ATTRIBUTE, Source::Rune).unwrap();
    assert(12 + rune == 15, 'rank 15');
    // Weapon damage 27 personalised, and strength 5 × 15, `u8`.
    let damage: u32 = 27 * 120 / 100;
    assert(damage == 32 && 5 * 15 <= 255_u32, 'weapon');
    // Armor against a type, the durations, the knock-down: saturated whatever their sums.
    let (_, hi) = envelope(id::ARMOR_VS, damage::FIRE);
    assert(30 + hi == 149, 'armor vs 149, saturated');
    // Damage and guarded armor: 7 sources at ±18 (`assert_contributions`) in an `i8`;
    // penetration 7 × 36 in a `u8`; unguarded armor 560 + 32 × 255 within ±9,995.
    assert(7 * 18 <= 127_u32 && 7 * 36 <= 255_u32 && 560 + 32 * 255 <= 9995_u32, 'contributions');
}

// COST-2, the record (DS-23): an insignia names its piece; its health is within the piece's bound;
// the slot types that are not insignias name none; the piece round-trips in the record.
#[test]
#[available_gas(l2_gas: 267246)] // ceil(1.05 × 254520 measured)
fn test_insignia_record_piece() {
    let legs = ModifierTrait::insignia(
        base_slot::LEGS, passive(id::MAX_HEALTH, 0, 10), Default::default(),
    );
    legs.assert_legal();
    let parts = Record::<Modifier>::pack(@legs);
    assert(Record::<Modifier>::unpack(parts) == legs, 'piece round-trips');
}

#[test]
#[should_panic(expected: 'modifier: health above piece')]
#[available_gas(l2_gas: 152082)] // ceil(1.05 × 144840 measured)
fn test_insignia_record_above_piece_refused() {
    ModifierTrait::insignia(base_slot::LEGS, passive(id::MAX_HEALTH, 0, 11), Default::default())
        .assert_legal();
}

#[test]
#[should_panic(expected: 'modifier: piece')]
#[available_gas(l2_gas: 145635)] // ceil(1.05 × 138700 measured)
fn test_insignia_record_without_piece_refused() {
    ModifierTrait::new(slot::INSIGNIA, passive(id::MAX_HEALTH, 0, 5), Default::default())
        .assert_legal();
}

// AUD-182-2: the audit's rune, a fixed −32,717 health benefit and a +32,767 cost (their sum +50
// within the source's bound), is refused: each passive lies within −75…+50.
#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 126074)] // ceil(1.05 × 120070 measured)
fn test_cancelling_rune_refused() {
    ModifierTrait::new(
        slot::RUNE, passive(id::MAX_HEALTH, 0, -32717), passive(id::MAX_HEALTH, 0, 32767),
    )
        .assert_legal();
}

// AUD-182-3: a cancelling pair on one rune (+32,767 and −32,764: sum +3) is refused.
#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 126567)] // ceil(1.05 × 120540 measured)
fn test_cancelling_attribute_rune_refused() {
    ModifierTrait::new(
        slot::RUNE, passive(id::ATTRIBUTE, PRIMARY, 32767), passive(id::ATTRIBUTE, PRIMARY, -32764),
    )
        .assert_legal();
}

// §6 test 1, through the validators: a modifier a unit beyond its bound is refused.
#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 126567)] // ceil(1.05 × 120540 measured)
fn test_modifier_beyond_bound_refused() {
    ModifierTrait::new(slot::PREFIX, passive(id::MAX_HEALTH, 0, 31), Default::default())
        .assert_legal();
}

#[test]
#[should_panic(expected: 'passive: per-source bound')]
#[available_gas(l2_gas: 20916)] // ceil(1.05 × 19920 measured)
fn test_set_bonus_beyond_bound_refused() {
    let knock = passive(id::KNOCKDOWN_FLAT, 0, 2);
    ArmorSetTrait::new([1, 2, 3, 4, 5], [knock, knock]).assert_legal();
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
#[available_gas(l2_gas: 217970)] // ceil(1.05 × 207590 measured)
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
#[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
fn test_caste_multiplier_1001_refused() {
    let caste = Caste { health: 1001, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: energy regen above 10')]
#[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
fn test_caste_energy_regen_refused() {
    let caste = Caste { energy_regen: 11, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: weapon damage above 255')]
#[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
fn test_caste_weapon_damage_refused() {
    let caste = Caste {
        weapon: WeaponTrait::new(weapon::MAUL, 256, damage::BLUNT, 2, 1), ..caste_at_bounds(),
    };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: flee above 100')]
#[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
fn test_caste_flee_refused() {
    let caste = Caste { flee: 101, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

#[test]
#[should_panic(expected: 'caste: skill adrenaline')]
#[available_gas(l2_gas: 49413)] // ceil(1.05 × 47060 measured)
fn test_caste_skill_of_64_strikes_refused() {
    CasteAssert::assert_skills(array![skill_of(63), skill_of(64)].span());
}

// §6 test 9 (DS-29): a caste's health regeneration 21 is refused at `pack`; `pack_stats` refuses
// 21 and accepts 20. The tick's extremes: `test_tick::test_regeneration_extremes`.
#[test]
#[should_panic(expected: 'caste: health regen')]
#[available_gas(l2_gas: 27867)] // ceil(1.05 × 26540 measured)
fn test_caste_health_regen_21_refused_at_pack() {
    let caste = Caste { health_regen: 21, ..caste_at_bounds() };
    Record::<Caste>::pack(@caste);
}

// §6 test 7: one hit's product in a `u64` (§1.6): B's base 33,022 at x = 80 and A's 163,836.
#[test]
#[available_gas(l2_gas: 10416)] // ceil(1.05 × 9920 measured)
fn test_one_hit_product() {
    let table: u64 = Exp2::at(80).into();
    assert(33022 * table == 8656519168, 'B: < 2^34');
    assert(163836 * table == 42948624384, 'A: < 2^36');
}

// §6 test 7, DS-20: a second `ATTACK_BONUS` on one carrier is refused.
#[test]
#[should_panic(expected: 'carrier: two attack bonuses')]
#[available_gas(l2_gas: 154256)] // ceil(1.05 × 146910 measured)
fn test_second_attack_bonus_refused() {
    let bonus = EntryTrait::new(
        kind::ATTACK_BONUS, 0, 5, 5, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    EntryAssert::assert_carrier(array![bonus, bonus, Default::default()].span(), Carrier::Attack);
}
