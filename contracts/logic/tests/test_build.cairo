// D-160 (design/20 §6): the acceptance tests the validators owe before any production snapshot.
// Tests 1, 6, 7 and 9 are here, in `test_tick`, `test_capacity`, the modules' unit tests
// (`types::passive`, `models::modifier`, `models::armor_set`, `models::caste`, `helpers::exp2`,
// `types::effect`, `helpers::duration`) and the ephemeral `test_layout` (each named below); tests 2
// to 5, the flattening's, are its unit tests (`models/build.cairo`, D-167); the registry's refusals
// of the same records, when the administrator writes them (D-166), are the persistent package's
// `test_registry`. Test 8 (a hit's percents) is the damage formula's, CBT-03's, and test 10's
// counters are CBT-05's. The two tests kept here span several modules (ENG-R1c, ruling 3); each
// says which above it.
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::build::max_instances;
use grimworld_logic::models::caste::{CasteAssert, CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::index::{Caste, Skill};
use grimworld_logic::models::modifier::ModifierTrait;
use grimworld_logic::models::skill::SkillTrait;
use grimworld_logic::types::combat::{damage, skill_kind, weapon};
use grimworld_logic::types::content::Record;
use grimworld_logic::types::effect::target;
use grimworld_logic::types::passive::{Passive, PassiveTrait, Source, id, source_bound};
use grimworld_logic::types::tick::CasteSheetTrait;

fn passive(id: u8, param: u8, value: i16) -> Passive {
    PassiveTrait::new(id, param, 0, 0, value, value)
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

// Kept in `tests/`: it spans `types::passive`, `models::build` and `models::modifier` (ruling 3).
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

// Kept in `tests/`: it spans `models::caste`, `types::tick`'s caste sheet and `models::skill`
// (ruling 3).
// §6 test 6: `m` = 1,000 at level 255 gives 51,800 (a `u16` of `GoblinState`); energy 85 is 255
// thirds (a `u8`); a skill of 63 strikes is usable. It packs.
#[test]
// gas: raised, CBT-05a: a caste's sheet carries its armor and weapon
#[available_gas(l2_gas: 230853)] // ceil(1.05 × 219860 measured)
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
